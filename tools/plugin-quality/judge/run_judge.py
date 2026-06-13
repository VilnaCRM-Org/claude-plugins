#!/usr/bin/env python3
"""Run the LLM-as-judge over plugin prompt artifacts.

    python3 judge/run_judge.py                      # judge every plugin, report only
    python3 judge/run_judge.py --gate               # exit 1 on a blocking failure
    python3 judge/run_judge.py --votes 3 --gate     # 3-vote median on the block path
    python3 judge/run_judge.py plugins/php-backend-sdlc/skills/code-review/SKILL.md
    python3 judge/run_judge.py --json --report report.md

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
    names = sorted(
        a.name for a in _model.discover(plugin_root) if a.kind == "skill"
    )
    return (
        "Authoritative list of skills that ship in this plugin (for J10 inventory accuracy): "
        + ", ".join(names)
    )


def _collect_artifacts(paths: list[str]) -> list["_model.Artifact"]:
    arts: list[_model.Artifact] = []
    if paths:
        for raw in paths:
            p = pathlib.Path(raw).resolve()
            if p.is_dir():
                arts.extend(_model.discover(p))
            elif p.is_file():
                # Resolve which plugin owns this file so kind detection is right.
                plugin_root = _owning_plugin_root(p)
                if plugin_root:
                    matched = [a for a in _model.discover(plugin_root) if a.path == p]
                    if matched:
                        arts.extend(matched)
                    else:
                        # Inside a plugin but not a discoverable artifact (a typo
                        # or a non-artifact .md). Never silently evaluate nothing.
                        print(
                            f"warning: {p} is inside a plugin but is not a judgeable "
                            "artifact (command/agent/skill/meta-guide) — skipped",
                            file=sys.stderr,
                        )
                else:
                    print(f"warning: {p} is not inside a known plugin tree — skipped", file=sys.stderr)
    else:
        for root in _model.find_plugin_roots(REPO_ROOT):
            arts.extend(_model.discover(root))
    return arts


def _owning_plugin_root(file_path: pathlib.Path) -> pathlib.Path | None:
    for parent in file_path.parents:
        if (parent / ".claude-plugin" / "plugin.json").is_file():
            return parent
    return None


def _render_result(res: "judge.JudgeResult") -> str:
    lines = [f"### {res.path}  ({res.kind}, model={res.model}{', cached' if res.cached else ''})"]
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
        lines.append(f"  [{tag}]{crit} {d.id} {d.name}: {d.score}/5 — {d.evidence.strip()[:160]}")
    return "\n".join(lines)


def _build_arg_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="LLM-as-judge over plugin prompt artifacts.")
    ap.add_argument("paths", nargs="*", help="files or plugin dirs (default: all plugins)")
    ap.add_argument("--model", default=judge.DEFAULT_MODEL, help="judge model (default: sonnet)")
    ap.add_argument(
        "--votes", type=int, default=1,
        help="votes per artifact; use an ODD count (3 recommended) for a stable median",
    )
    ap.add_argument("--kinds", default="", help="comma list to restrict: command,agent,skill,meta-guide")
    ap.add_argument("--limit", type=int, default=0, help="judge at most N artifacts (0 = all)")
    ap.add_argument("--no-cache", action="store_true", help="ignore the verdict cache")
    ap.add_argument("--jobs", type=int, default=1, help="concurrent judge calls (default 1)")
    ap.add_argument("--gate", action="store_true", help="exit 1 on any blocking failure")
    ap.add_argument("--require", action="store_true", help="fail (exit 2) if the claude CLI is unavailable")
    ap.add_argument("--json", action="store_true", help="emit JSON results to stdout")
    ap.add_argument("--report", default=None, help="write a markdown report to this path")
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
    return a, judge.judge_artifact(
        a, model=args.model, extra_context=extra,
        use_cache=not args.no_cache, votes=args.votes,
    )


_JUDGE_EXC = (judge.JudgeError, judge.JudgeUnavailable, KeyError, ValueError, TypeError)


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
        print(_json.dumps([{
            "path": r.path, "kind": r.kind, "model": r.model, "cached": r.cached,
            "dimensions": [vars(d) for d in r.dimensions],
        } for r in results], indent=2))

    if args.report:
        _write_report(pathlib.Path(args.report), results, blocking, advisory, errors)

    print(
        f"\njudge summary: {len(results)} artifact(s), "
        f"{len(blocking)} blocking, {len(advisory)} advisory, {len(errors)} error(s).",
        file=sys.stderr,
    )


def main(argv: list[str] | None = None) -> int:
    args = _build_arg_parser().parse_args(argv)

    if _votes_error(args):
        return 2

    if not judge.cli_available():
        msg = "claude CLI not found on PATH — LLM-judge SKIPPED (deterministic lint still gates)."
        print(f"SKIP: {msg}", file=sys.stderr)
        return 2 if args.require else 0

    artifacts = _select_artifacts(args)
    if not artifacts:
        print("No artifacts to judge.", file=sys.stderr)
        return 0

    results, errors = _judge_all(artifacts, args)
    blocking = [(r, d) for r in results for d in r.blocking_failures]
    advisory = [(r, d) for r in results for d in r.advisory_failures]
    _report(args, results, blocking, advisory, errors)

    # Errors are never a silent pass: under --gate, an unjudgeable artifact fails.
    if args.gate and (blocking or errors):
        return 1
    return 0


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
            out.append(f"- `{r.path}` {d.id} {d.name} = {d.score}/5 — {d.evidence.strip()}")
        out.append("")
    if advisory:
        out.append("## Advisory (score below floor)")
        for r, d in advisory:
            out.append(f"- `{r.path}` {d.id} {d.name} = {d.score}/5 — {d.evidence.strip()}")
        out.append("")
    if errors:
        out.append("## Errors")
        out.extend(f"- {e}" for e in errors)
        out.append("")
    path.write_text("\n".join(out), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
