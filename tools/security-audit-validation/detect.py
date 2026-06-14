#!/usr/bin/env python3
"""Static-lane detection harness for the security-audit validation campaign.

Runs the local semgrep rule pack (``rules/security-audit.yml``) over the fixture
corpus and asserts, per fixture, that:

* a ``finding`` fixture is flagged by **its own family's** rule (cross-family
  hits on an already-vulnerable fixture are tolerated), and
* a ``clean`` fixture is flagged by **no** rule (strict true-negative).

Plus the FR-7 dependency lane: a pinned ``composer.json`` version is classified
vulnerable/clean against an in-tree known-vulnerable range (offline; stands in
for ``composer audit``).

Exit 0 when every assertion holds, 1 on any false negative / false positive, 2
when semgrep is unavailable (so a missing engine is never a silent green).

    python3 detect.py                 # run the full static + dep lane
    python3 detect.py --json          # machine-readable results

The compare logic (`evaluate_static`, `evaluate_deps`) is pure and unit-tested
with synthetic input; the semgrep subprocess is a thin, injectable shell.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import pathlib
import subprocess  # nosec B404 - fixed argv, never shell=True
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import corpus  # noqa: E402

RULES_PATH = HERE / "rules" / "security-audit.yml"
CORPUS_DIR = HERE / "corpus"


class SemgrepUnavailable(RuntimeError):
    """semgrep could not be executed (binary missing or engine startup error)."""


@dataclasses.dataclass(frozen=True)
class Result:
    cid: str
    lane: str  # "static" | "dep"
    ok: bool
    detail: str


# --- semgrep shell (thin, injectable) -------------------------------------
def _run_semgrep(
    rules_path: pathlib.Path,
    target: pathlib.Path,
    runner=subprocess.run,
    jobs: int = 1,
) -> dict:
    """Invoke semgrep and return parsed JSON. Raises SemgrepUnavailable on failure.

    ``-j 1`` keeps the legacy single-worker path, which avoids an io_uring
    startup failure on hosts with a low ``RLIMIT_MEMLOCK``; semgrep exit code 1
    only means "findings present" and is expected.
    """
    cmd = [
        "semgrep",
        "scan",
        "-j",
        str(jobs),
        "-q",
        "--metrics=off",
        "--disable-version-check",
        "--no-git-ignore",
        "--config",
        str(rules_path),
        "--json",
        str(target),
    ]
    try:
        proc = runner(cmd, capture_output=True, text=True, check=False)  # nosec B603
    except (FileNotFoundError, OSError) as exc:
        raise SemgrepUnavailable(f"could not execute semgrep: {exc}") from exc
    if not proc.stdout.strip():
        raise SemgrepUnavailable(
            f"semgrep produced no JSON (exit {proc.returncode}): "
            f"{proc.stderr.strip()[:300]}"
        )
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise SemgrepUnavailable(f"semgrep JSON parse error: {exc}") from exc


def _result_family(result: dict) -> str | None:
    """The dispatch family a semgrep result belongs to (rule metadata.family)."""
    meta = result.get("extra", {}).get("metadata", {})
    fam = meta.get("family")
    return fam if isinstance(fam, str) else None


def families_by_path(semgrep_json: dict, corpus_dir: pathlib.Path) -> dict[str, set]:
    """Map each scanned file (path relative to corpus_dir, POSIX) to the set of
    dispatch families whose rules fired on it."""
    out: dict[str, set] = {}
    for r in semgrep_json.get("results", []):
        fam = _result_family(r)
        if fam is None:
            continue
        rel = os.path.relpath(r.get("path", ""), corpus_dir)
        out.setdefault(pathlib.PurePath(rel).as_posix(), set()).add(fam)
    return out


# --- pure compare ----------------------------------------------------------
def evaluate_static(
    fixtures: list[corpus.Fixture], hits: dict[str, set]
) -> list[Result]:
    """Compare semgrep hits to each static fixture's expectation (pure)."""
    results: list[Result] = []
    for fx in fixtures:
        fired = hits.get(fx.path, set())
        if fx.static_expect == corpus.FINDING:
            ok = fx.family in fired
            detail = (
                f"{fx.family} fired"
                if ok
                else f"FALSE NEGATIVE: {fx.family} did "
                f"not fire (fired: {sorted(fired) or 'none'})"
            )
        else:  # CLEAN
            ok = not fired
            detail = (
                "no rule fired"
                if ok
                else f"FALSE POSITIVE: {sorted(fired)} fired on clean fixture"
            )
        results.append(Result(fx.cid, "static", ok, detail))
    return results


def _parse_version(spec: str) -> tuple[int, int, int]:
    """Parse a pinned version constraint to a (major, minor, patch) tuple.

    Tolerates a leading operator/`v` and missing components ("7.4" -> (7,4,0)).
    Non-numeric components are treated as 0.
    """
    cleaned = spec.lstrip("^~>=< vV").strip()
    parts = cleaned.split(".")[:3]
    nums = []
    for p in parts:
        digits = "".join(ch for ch in p if ch.isdigit())
        nums.append(int(digits) if digits else 0)
    while len(nums) < 3:
        nums.append(0)
    return (nums[0], nums[1], nums[2])


def _pin_is_vulnerable(version: tuple[int, int, int], ranges: list) -> bool:
    """True when ``version`` falls in any [low_inclusive, high_exclusive) range."""
    return any(low <= version < high for low, high in ranges)


def _extract_pin(composer: dict, package: str) -> str | None:
    """The pinned version string for ``package`` in a parsed composer.json."""
    for section in ("require", "require-dev"):
        block = composer.get(section)
        if isinstance(block, dict) and package in block:
            return block[package]
    return None


def evaluate_deps(
    dep_cases: list[corpus.DepCase],
    corpus_dir: pathlib.Path,
    reader=None,
) -> list[Result]:
    """Classify each composer fixture vulnerable/clean and compare to expectation."""
    read = reader or (lambda p: pathlib.Path(p).read_text(encoding="utf-8"))
    results: list[Result] = []
    for dc in dep_cases:
        ranges = corpus.VULN_RANGES.get(dc.package, [])
        try:
            data = json.loads(read(corpus_dir / dc.path))
        except (OSError, json.JSONDecodeError) as exc:
            results.append(Result(dc.cid, "dep", False, f"unreadable fixture: {exc}"))
            continue
        pin = _extract_pin(data, dc.package)
        if pin is None:
            results.append(
                Result(dc.cid, "dep", False, f"{dc.package} not pinned in fixture")
            )
            continue
        is_vuln = _pin_is_vulnerable(_parse_version(pin), ranges)
        ok = is_vuln == dc.expect_vulnerable
        detail = (
            f"{dc.package} {pin} -> "
            f"{'vulnerable' if is_vuln else 'clean'} (expected "
            f"{'vulnerable' if dc.expect_vulnerable else 'clean'})"
        )
        results.append(Result(dc.cid, "dep", ok, detail))
    return results


# --- orchestration ---------------------------------------------------------
def run(
    corpus_dir: pathlib.Path = CORPUS_DIR,
    rules_path: pathlib.Path = RULES_PATH,
    runner=subprocess.run,
) -> list[Result]:
    """Run both lanes and return the combined per-fixture results."""
    semgrep_json = _run_semgrep(rules_path, corpus_dir, runner=runner)
    hits = families_by_path(semgrep_json, corpus_dir)
    results = evaluate_static(corpus.static_fixtures(), hits)
    results += evaluate_deps(list(corpus.DEP_CASES), corpus_dir)
    return results


def _render(results: list[Result]) -> str:
    lines = []
    for r in results:
        tag = "ok  " if r.ok else "FAIL"
        lines.append(f"  [{tag}] {r.cid:14} ({r.lane}) {r.detail}")
    failed = [r for r in results if not r.ok]
    lines.append(
        f"\nsecurity-audit detection: {len(results) - len(failed)}/{len(results)} "
        f"passed, {len(failed)} failed."
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="security-audit static detection harness")
    ap.add_argument("--json", action="store_true", help="emit JSON results")
    args = ap.parse_args(argv)
    try:
        results = run()
    except SemgrepUnavailable as exc:
        print(f"SEMGREP UNAVAILABLE: {exc}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps([dataclasses.asdict(r) for r in results], indent=2))
    else:
        print(_render(results), file=sys.stderr)
    return 1 if any(not r.ok for r in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
