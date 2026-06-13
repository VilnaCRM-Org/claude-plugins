#!/usr/bin/env python3
"""Run the LLM-as-judge over plugin prompt artifacts.

    python3 judge/run_judge.py                      # judge every plugin, report only
    python3 judge/run_judge.py --gate               # exit 1 on a blocking failure
    python3 judge/run_judge.py --votes 3 --gate     # 3-vote median on the block path
    python3 judge/run_judge.py plugins/php-backend-sdlc/skills/code-review/SKILL.md
    python3 judge/run_judge.py --json --report report.md
    python3 judge/run_judge.py --selftest             # calibrate the rubric (live)

Vote count: use an ODD --votes for a stable median (median_low of an even split
leans on a single low vote, e.g. median_low([2,5]) == 2). ``--votes 3`` is the
recommended value for gating; even counts >1 are rejected. Default is 1.

Gating model (see docs/test-strategy.md):
  * advisory  — any dimension scoring below its floor (4) is reported.
  * blocking  — only a *critical* dimension scoring <= its block_floor (2) fails
                the gate, and only when --gate is passed.

Credential handling: if the ``claude`` CLI is absent the run SKIPS with an
explicit message and exit 0 (never a false green) unless --require is given.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "lint"))

import _model  # noqa: E402
import judge  # noqa: E402
import rubrics  # noqa: E402

REPO_ROOT = HERE.parent.parent.parent


def _meta_guide_context(plugin_root: pathlib.Path) -> str:
    # Build the authoritative list from the SAME source the judge compares
    # against: each skill artifact's resolved ``.name`` (frontmatter name when
    # present, else the dir stem), not the raw directory name. Otherwise J10
    # would flag a guide that correctly uses the frontmatter name as "stale".
    names = sorted(a.name for a in _model.discover(plugin_root) if a.kind == "skill")
    return (
        "Authoritative list of skills that ship in this plugin "
        "(for J10 inventory accuracy): " + ", ".join(names)
    )


def _collect_one_path(raw: str) -> list["_model.Artifact"]:
    """Resolve a single CLI path argument to its judgeable artifacts.

    A directory expands to everything discovered under it. A file is mapped to
    the artifact the owning plugin discovers for it; if the file is inside a
    plugin but matches no artifact (a typo or a non-artifact .md), or is outside
    any plugin tree, that is warned about — never silently evaluated as nothing.
    """
    p = pathlib.Path(raw).resolve()
    if p.is_dir():
        return list(_model.discover(p))
    if not p.is_file():
        print(
            f"warning: {p} does not exist (not a file or directory) — skipped",
            file=sys.stderr,
        )
        return []
    plugin_root = _owning_plugin_root(p)
    if plugin_root is None:
        print(
            f"warning: {p} is not inside a known plugin tree — skipped", file=sys.stderr
        )
        return []
    matched = [a for a in _model.discover(plugin_root) if a.path == p]
    if matched:
        return matched
    print(
        f"warning: {p} is inside a plugin but is not a judgeable "
        "artifact (command/agent/skill/meta-guide) — skipped",
        file=sys.stderr,
    )
    return []


def _collect_artifacts(paths: list[str]) -> list["_model.Artifact"]:
    if not paths:
        arts: list[_model.Artifact] = []
        for root in _model.find_plugin_roots(REPO_ROOT):
            arts.extend(_model.discover(root))
        return arts
    arts = []
    for raw in paths:
        arts.extend(_collect_one_path(raw))
    return _dedupe_by_path(arts)


def _dedupe_by_path(arts: list["_model.Artifact"]) -> list["_model.Artifact"]:
    """Drop duplicate artifacts (preserve order, dedupe by resolved ``.path``).

    Overlapping CLI inputs — e.g. a plugin dir plus a file inside it — would
    otherwise yield the same artifact more than once and judge it twice.
    """
    seen: set[pathlib.Path] = set()
    unique: list[_model.Artifact] = []
    for a in arts:
        key = a.path.resolve()
        if key in seen:
            continue
        seen.add(key)
        unique.append(a)
    return unique


def _owning_plugin_root(file_path: pathlib.Path) -> pathlib.Path | None:
    for parent in file_path.parents:
        if (parent / ".claude-plugin" / "plugin.json").is_file():
            return parent
    return None


def _empty_set_exit(args) -> int:
    """Decide the exit code when zero artifacts were collected.

    Mirrors lint_all's broken-manifest guard intent: a green run on an empty
    artifact set under --gate is a false green and must fail.

      * No --gate                  -> 0 (report-only, nothing to judge).
      * --gate + explicit paths    -> 1: the paths matched nothing (already
                                      warned by _collect_one_path); a gate over a
                                      path that judges nothing must not pass.
      * --gate + no explicit paths:
          - plugin roots exist but yielded zero artifacts -> 1 (broken/empty
            plugin tree hidden from the gate, like lint's no-valid-manifest).
          - no plugin roots at all -> 0 (legitimately nothing to lint).
    """
    if not args.gate:
        print("No artifacts to judge.", file=sys.stderr)
        return 0
    if args.paths:
        print(
            "error: --gate set but the given path(s) matched no judgeable "
            "artifact — refusing a false green.",
            file=sys.stderr,
        )
        return 1
    roots = _model.find_plugin_roots(REPO_ROOT)
    if roots:
        names = ", ".join(r.name for r in roots)
        print(
            f"error: --gate set but {len(roots)} plugin root(s) [{names}] yielded "
            "zero judgeable artifacts — refusing a false green.",
            file=sys.stderr,
        )
        return 1
    print("No plugin roots found — nothing to judge.", file=sys.stderr)
    return 0


def _render_result(res: "judge.JudgeResult") -> str:
    lines = [
        f"### {res.path}  ({res.kind}, model={res.model}"
        f"{', cached' if res.cached else ''})"
    ]
    if not res.dimensions:
        lines.append("  (no applicable dimensions)")
        return "\n".join(lines)
    for d in sorted(res.dimensions, key=lambda x: x.id):
        if d.blocking:
            tag = "BLOCK"
        elif not d.passed:
            tag = "warn "
        else:
            tag = "ok   "
        crit = "*" if d.critical else " "
        lines.append(
            f"  [{tag}]{crit} {d.id} {d.name}: {d.score}/5 — {d.evidence.strip()[:160]}"
        )
    return "\n".join(lines)


def _build_arg_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description="LLM-as-judge over plugin prompt artifacts."
    )
    ap.add_argument(
        "paths", nargs="*", help="files or plugin dirs (default: all plugins)"
    )
    ap.add_argument(
        "--model", default=judge.DEFAULT_MODEL, help="judge model (default: sonnet)"
    )
    ap.add_argument(
        "--votes",
        type=int,
        default=1,
        help="votes per artifact; use an ODD count (3 recommended) for a stable median",
    )
    ap.add_argument(
        "--kinds",
        default="",
        help="comma list to restrict: command,agent,skill,meta-guide",
    )
    ap.add_argument(
        "--limit", type=int, default=0, help="judge at most N artifacts (0 = all)"
    )
    ap.add_argument("--no-cache", action="store_true", help="ignore the verdict cache")
    ap.add_argument(
        "--jobs", type=int, default=1, help="concurrent judge calls (default 1)"
    )
    ap.add_argument(
        "--gate", action="store_true", help="exit 1 on any blocking failure"
    )
    ap.add_argument(
        "--require",
        action="store_true",
        help="fail (exit 2) if the claude CLI is unavailable",
    )
    ap.add_argument("--json", action="store_true", help="emit JSON results to stdout")
    ap.add_argument(
        "--report", default=None, help="write a markdown report to this path"
    )
    ap.add_argument(
        "--selftest",
        action="store_true",
        help="run the calibration self-test (live judge on known-good/bad artifacts); "
        "requires the claude CLI",
    )
    return ap


def _votes_error(args) -> bool:
    # An even vote count >1 makes the median_low aggregate flaky: median_low of
    # an even split leans on a single low vote (median_low([2,5]) == 2), so one
    # stray low score blocks. Require an odd count for stable gating.
    if args.votes > 1 and args.votes % 2 == 0:
        print(
            f"error: --votes {args.votes} is even; use an odd vote count "
            "(3 recommended) for a stable median.",
            file=sys.stderr,
        )
        return True
    return False


def _select_artifacts(args) -> list["_model.Artifact"]:
    artifacts = _collect_artifacts(args.paths)
    if args.kinds:
        wanted = {k.strip() for k in args.kinds.split(",") if k.strip()}
        artifacts = [a for a in artifacts if a.kind in wanted]
    if args.limit:
        artifacts = artifacts[: args.limit]
    return artifacts


def _judge_one(a, args):
    extra = _meta_guide_context(a.plugin_root) if a.kind == "meta-guide" else ""
    options = judge.JudgeOptions(
        model=args.model,
        extra_context=extra,
        use_cache=not args.no_cache,
        votes=args.votes,
    )
    return a, judge.judge_artifact(a, options)


# OSError is included so a cache.put failure (disk full / permissions) inside
# _generate_verdict becomes a recorded per-artifact error, never a crash that
# aborts the whole run.
_JUDGE_EXC = (
    judge.JudgeError,
    judge.JudgeUnavailable,
    OSError,
    KeyError,
    ValueError,
    TypeError,
)


def _judge_all(artifacts, args):
    """Judge every artifact, returning (results, errors). One bad artifact never
    aborts the run; its failure is recorded as an error entry instead."""
    results: list[judge.JudgeResult] = []
    errors: list[str] = []

    def _record_error(rel, exc):
        errors.append(f"{rel}: {exc}")
        print(f"ERROR judging {rel}: {exc}", file=sys.stderr)

    if args.jobs > 1 and len(artifacts) > 1:
        import concurrent.futures

        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = {pool.submit(_judge_one, a, args): a for a in artifacts}
            for fut in concurrent.futures.as_completed(futures):
                a = futures[fut]
                try:
                    _, res = fut.result()
                except _JUDGE_EXC as exc:
                    _record_error(a.rel, exc)
                    continue
                results.append(res)
        results.sort(key=lambda r: r.path)
        for res in results:
            print(_render_result(res), file=sys.stderr)
    else:
        for a in artifacts:
            try:
                _, res = _judge_one(a, args)
            except _JUDGE_EXC as exc:
                _record_error(a.rel, exc)
                continue
            results.append(res)
            print(_render_result(res), file=sys.stderr)
    return results, errors


def _report(args, results, blocking, advisory, errors) -> None:
    if args.json:
        import json as _json

        print(
            _json.dumps(
                [
                    {
                        "path": r.path,
                        "kind": r.kind,
                        "model": r.model,
                        "cached": r.cached,
                        "dimensions": [vars(d) for d in r.dimensions],
                    }
                    for r in results
                ],
                indent=2,
            )
        )

    if args.report:
        _write_report(pathlib.Path(args.report), results, blocking, advisory, errors)

    print(
        f"\njudge summary: {len(results)} artifact(s), "
        f"{len(blocking)} blocking, {len(advisory)} advisory, {len(errors)} error(s).",
        file=sys.stderr,
    )


def _score_calibration_case(case, model: str) -> int:
    """Live-judge one calibration case and return its TARGET dimension's score.

    Caching is disabled so the self-test always reflects the current model/rubric.
    Raises judge.JudgeError if the target dimension was not scored.
    """
    art = case.artifact()
    options = judge.JudgeOptions(
        model=model, extra_context=case.extra_context, use_cache=False, votes=1
    )
    res = judge.judge_artifact(art, options)
    for d in res.dimensions:
        if d.id == case.dimension_id:
            return d.score
    raise judge.JudgeError(
        f"calibration case {case.dimension_id}/{case.polarity} did not score its "
        f"target dimension {case.dimension_id}"
    )


def _selftest_one_dimension(
    dim_id: str, model: str
) -> tuple[str, int | None, int | None, bool, str]:
    """Run the P and N calibration cases for one dimension.

    Returns ``(dim_id, p_score, n_score, passed, note)``. ``passed`` is True when
    the good example scored at/above the dimension floor AND the bad example
    scored at/below its block_floor. Any judge error -> not passed with a note.
    """
    import calibration

    dim = rubrics.DIMENSIONS_BY_ID[dim_id]
    pos = calibration.positive_for(dim_id)
    neg = calibration.negative_for(dim_id)
    if pos is None or neg is None:
        return dim_id, None, None, False, "missing P or N calibration case"
    try:
        p_score = _score_calibration_case(pos, model)
        n_score = _score_calibration_case(neg, model)
    except (judge.JudgeError, judge.JudgeUnavailable) as exc:
        return dim_id, None, None, False, f"judge error: {exc}"
    p_ok = p_score >= dim.floor
    n_ok = n_score <= dim.block_floor
    note = ""
    if not p_ok:
        note = f"P scored {p_score} < floor {dim.floor}"
    elif not n_ok:
        note = f"N scored {n_score} > block_floor {dim.block_floor}"
    return dim_id, p_score, n_score, p_ok and n_ok, note


def run_selftest(model: str) -> int:
    """Calibration self-test over every critical dimension. Exit 1 on any miss.

    Prints a per-dimension PASS/FAIL table. Requires the claude CLI (the live
    judge); the caller gates on cli_available before invoking this.
    """
    import calibration

    rows = [
        _selftest_one_dimension(d, model) for d in calibration.CRITICAL_DIMENSION_IDS
    ]
    print("calibration self-test (model={}):".format(model), file=sys.stderr)
    print(f"  {'DIM':<5} {'P':>3} {'N':>3}  RESULT  note", file=sys.stderr)
    failures = 0
    for dim_id, p_score, n_score, passed, note in rows:
        if not passed:
            failures += 1
        ps = "-" if p_score is None else str(p_score)
        ns = "-" if n_score is None else str(n_score)
        tag = "PASS" if passed else "FAIL"
        print(f"  {dim_id:<5} {ps:>3} {ns:>3}  {tag:<6}  {note}", file=sys.stderr)
    print(
        f"calibration self-test: {len(rows) - failures}/{len(rows)} "
        "dimension(s) calibrated.",
        file=sys.stderr,
    )
    return 1 if failures else 0


def _run_selftest_entry(args) -> int:
    """--selftest entry point: gate on the CLI, then run the calibration check.

    Without the claude CLI: skip-with-message (exit 0) unless --require (exit 2).
    The self-test is NEVER reached on the no-cred CI path because main() runs it
    only when --selftest is passed, which CI does not pass.
    """
    if not judge.cli_available():
        msg = "claude CLI not found on PATH — calibration self-test SKIPPED."
        print(f"SKIP: {msg}", file=sys.stderr)
        return 2 if args.require else 0
    return run_selftest(args.model)


def _preflight(args) -> int | None:
    """Pre-judge guards; return an exit code to stop early, else None to proceed.

    Covers the even-votes rejection, the --selftest branch, and the missing-CLI
    skip-with-message — each preserving its original exit semantics.
    """
    if _votes_error(args):
        return 2
    if args.selftest:
        return _run_selftest_entry(args)
    if not judge.cli_available():
        msg = (
            "claude CLI not found on PATH — LLM-judge SKIPPED "
            "(deterministic lint still gates)."
        )
        print(f"SKIP: {msg}", file=sys.stderr)
        return 2 if args.require else 0
    return None


def _run_judge_flow(args) -> int:
    """Select, judge, and report artifacts; return the gate exit code."""
    artifacts = _select_artifacts(args)
    if not artifacts:
        return _empty_set_exit(args)

    results, errors = _judge_all(artifacts, args)
    blocking = [(r, d) for r in results for d in r.blocking_failures]
    advisory = [(r, d) for r in results for d in r.advisory_failures]
    _report(args, results, blocking, advisory, errors)

    # Errors are never a silent pass: under --gate, an unjudgeable artifact fails.
    if args.gate and (blocking or errors):
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    early = _preflight(args)
    if early is not None:
        return early
    return _run_judge_flow(args)


def _write_report(path, results, blocking, advisory, errors):
    out = ["# LLM-as-judge report", ""]
    out.append(f"- artifacts judged: {len(results)}")
    out.append(f"- blocking failures: {len(blocking)}")
    out.append(f"- advisory findings: {len(advisory)}")
    out.append(f"- errors: {len(errors)}")
    out.append("")
    if blocking:
        out.append("## Blocking (critical, score <= block floor)")
        for r, d in blocking:
            out.append(
                f"- `{r.path}` {d.id} {d.name} = {d.score}/5 — {d.evidence.strip()}"
            )
        out.append("")
    if advisory:
        out.append("## Advisory (score below floor)")
        for r, d in advisory:
            out.append(
                f"- `{r.path}` {d.id} {d.name} = {d.score}/5 — {d.evidence.strip()}"
            )
        out.append("")
    if errors:
        out.append("## Errors")
        out.extend(f"- {e}" for e in errors)
        out.append("")
    path.write_text("\n".join(out), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
