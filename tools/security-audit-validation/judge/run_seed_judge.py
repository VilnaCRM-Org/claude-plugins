#!/usr/bin/env python3
"""LLM-as-judge behavioral lane for the security-audit validation campaign.

For each fixture, an LLM is asked to act under the `security-auditor` verdict
contract and classify the fixture as FINDING / CLEAN / NA. The judged verdict is
compared to the fixture's recorded `judge_expect`. This lane validates the
*reasoning* the skill drives — including the logic families (BOLA/IDOR, BFLA,
BOPLA, auth, rate) that no sound static rule can decide.

Conventions mirror the prompt-quality judge (`tools/plugin-quality/judge/`):

* model defaults to ``sonnet``;
* the ``claude`` CLI is called in arg-form with a neutral cwd (OAuth-safe);
* an odd vote count is taken as a median (majority) verdict;
* **no CLI -> SKIP with message, exit 0** (never a false green) unless
  ``--require`` is passed.

The pure core (`build_prompt`, `parse_verdict`, `majority_verdict`,
`evaluate`) is unit-tested with synthetic input; the subprocess is a thin,
injectable shell.

    python3 judge/run_seed_judge.py                 # judge all, report only
    python3 judge/run_seed_judge.py --gate          # exit 1 on a verdict mismatch
    python3 judge/run_seed_judge.py --votes 3 --gate
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import pathlib
import re
import shutil
import subprocess  # nosec B404 - fixed argv, never shell=True
import sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import corpus  # noqa: E402

DEFAULT_MODEL = "sonnet"
CORPUS_DIR = HERE.parent / "corpus"
VALID_VERDICTS = (corpus.J_FINDING, corpus.J_CLEAN, corpus.J_NA)

# Security-conservative tie-break order: an even split never silently downgrades
# a possible vulnerability to clean.
_TIE_PRIORITY = {corpus.J_FINDING: 0, corpus.J_NA: 1, corpus.J_CLEAN: 2}

CONTRACT = """\
You are the `security-auditor` red-team subagent. Apply its verdict contract to
ONE PHP fixture and return ONE verdict for the single assigned vulnerability
family. Rules:
- FINDING: the fixture contains a real, exploitable instance of the assigned
  family (a reachable sink on attacker-controlled input, a missing
  authorization/ownership check, a committed credential, a weak primitive used
  for security).
- CLEAN: the fixture uses the secure-by-default counterpart for the family
  (parameterized query, output encoding, allowlist, constant-time compare,
  realpath containment, env-sourced secret, strong hash).
- NA: the family does not apply to a server-side PHP backend (OWASP Mobile, a
  memory-safety CWE) — never fabricate a finding for an N/A family.
Reply with ONE JSON object and nothing else:
{"verdict":"FINDING|CLEAN|NA","cwe":"CWE-..","why":"<=240 chars"}"""


@dataclasses.dataclass(frozen=True)
class JudgeResult:
    cid: str
    family: str
    expected: str
    verdict: str
    ok: bool
    votes: list[str]


class JudgeUnavailable(RuntimeError):
    """The claude CLI is not available on PATH."""


# --- pure core -------------------------------------------------------------
def build_prompt(fixture: corpus.Fixture, source_text: str) -> str:
    """Assemble the judge prompt for one fixture (pure)."""
    return (
        f"{CONTRACT}\n\n"
        f"Assigned family: {fixture.family}  (primary {fixture.cwe})\n"
        f"Fixture: {fixture.path}\n"
        "```php\n"
        f"{source_text.rstrip()}\n"
        "```\n"
    )


def parse_verdict(raw: str) -> str:
    """Extract FINDING/CLEAN/NA from a model reply (pure, tolerant).

    Prefers a JSON envelope; falls back to the first verdict token found. Raises
    ValueError when no recognizable verdict is present.
    """
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    if match:
        try:
            obj = json.loads(match.group(0))
            v = str(obj.get("verdict", "")).strip().upper()
            if v in VALID_VERDICTS:
                return v
        except json.JSONDecodeError:
            pass
    token = re.search(r"\b(FINDING|CLEAN|NA)\b", raw.upper())
    if token:
        return token.group(1)
    raise ValueError(f"no verdict found in reply: {raw[:120]!r}")


def majority_verdict(votes: list[str]) -> str:
    """The majority verdict; ties broken security-conservatively (pure)."""
    if not votes:
        raise ValueError("no votes to aggregate")
    counts = Counter(votes)
    top = max(counts.values())
    tied = [v for v, c in counts.items() if c == top]
    return min(tied, key=lambda v: _TIE_PRIORITY.get(v, 99))


def evaluate(results: list[JudgeResult]) -> tuple[int, int]:
    """Return (passed, failed) counts (pure)."""
    failed = sum(1 for r in results if not r.ok)
    return len(results) - failed, failed


# --- thin claude shell -----------------------------------------------------
def cli_available(which=shutil.which) -> bool:
    return which("claude") is not None


def _call_claude(prompt: str, model: str, runner=subprocess.run) -> str:
    """Call the claude CLI in arg-form with a neutral cwd (OAuth-safe)."""
    cmd = ["claude", "-p", prompt, "--model", model]
    proc = runner(  # nosec B603
        cmd,
        capture_output=True,
        text=True,
        check=False,
        cwd=str(pathlib.Path.home()),
    )
    if proc.returncode != 0:
        raise JudgeUnavailable(f"claude exited {proc.returncode}: {proc.stderr[:200]}")
    return proc.stdout


def judge_fixture(
    fixture: corpus.Fixture,
    corpus_dir: pathlib.Path,
    model: str,
    votes: int,
    caller=_call_claude,
    reader=None,
) -> JudgeResult:
    """Judge a single fixture with ``votes`` independent calls."""
    read = reader or (lambda p: pathlib.Path(p).read_text(encoding="utf-8"))
    source = read(corpus_dir / fixture.path)
    prompt = build_prompt(fixture, source)
    cast = [parse_verdict(caller(prompt, model)) for _ in range(votes)]
    verdict = majority_verdict(cast)
    return JudgeResult(
        cid=fixture.cid,
        family=fixture.family,
        expected=fixture.judge_expect,
        verdict=verdict,
        ok=verdict == fixture.judge_expect,
        votes=cast,
    )


# --- orchestration ---------------------------------------------------------
def run(
    fixtures: list[corpus.Fixture],
    model: str,
    votes: int,
    caller=_call_claude,
    corpus_dir: pathlib.Path = CORPUS_DIR,
) -> list[JudgeResult]:
    return [
        judge_fixture(fx, corpus_dir, model, votes, caller=caller) for fx in fixtures
    ]


def _render(results: list[JudgeResult]) -> str:
    lines = []
    for r in results:
        tag = "ok  " if r.ok else "FAIL"
        lines.append(
            f"  [{tag}] {r.cid:14} {r.family:8} expected {r.expected:8} "
            f"got {r.verdict} (votes={r.votes})"
        )
    passed, failed = evaluate(results)
    lines.append(f"\nseed-judge: {passed}/{len(results)} passed, {failed} failed.")
    return "\n".join(lines)


def _build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="security-audit LLM-judge behavioral lane")
    ap.add_argument(
        "--model", default=DEFAULT_MODEL, help="judge model (default sonnet)"
    )
    ap.add_argument("--votes", type=int, default=1, help="votes per fixture (odd)")
    ap.add_argument(
        "--gate", action="store_true", help="exit 1 on any verdict mismatch"
    )
    ap.add_argument(
        "--require",
        action="store_true",
        help="exit 2 if the claude CLI is unavailable (default: skip-clean)",
    )
    ap.add_argument("--limit", type=int, default=0, help="judge at most N fixtures")
    return ap


def _votes_invalid(votes: int) -> bool:
    return votes > 1 and votes % 2 == 0


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if _votes_invalid(args.votes):
        print(
            f"error: --votes {args.votes} is even; use an odd count.", file=sys.stderr
        )
        return 2
    if not cli_available():
        print(
            "SKIP: claude CLI not found — seed-judge lane skipped (static lane "
            "still gates).",
            file=sys.stderr,
        )
        return 2 if args.require else 0
    fixtures = corpus.judge_fixtures()
    if args.limit:
        fixtures = fixtures[: args.limit]
    results = run(fixtures, args.model, args.votes)
    print(_render(results), file=sys.stderr)
    _, failed = evaluate(results)
    return 1 if (args.gate and failed) else 0


if __name__ == "__main__":
    raise SystemExit(main())
