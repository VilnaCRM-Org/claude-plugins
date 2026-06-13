#!/usr/bin/env python3
"""Aggregate every Tier-1 static check over one or more plugin roots.

Discovers ``check_*.py`` modules in this directory, calls each module's
``check(plugin_root)`` for every plugin under ``plugins/*/`` (or the paths given
on the command line), plus ``check_manifest.check_marketplace(repo_root)`` once,
and renders the combined findings.

Exit code: 0 when no blocking finding (severity S1/S2/S3); 1 otherwise. S4 is
advisory and never fails the gate. ``--json`` emits machine-readable output.

Pure stdlib + PyYAML (via the check modules). No pip install required:

    python3 lint/lint_all.py                 # all plugins, human output
    python3 lint/lint_all.py --json          # JSON for CI
    python3 lint/lint_all.py plugins/php-backend-sdlc
"""

from __future__ import annotations

import argparse
import importlib
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import _common  # noqa: E402
import _model  # noqa: E402

BLOCKING = {"S1", "S2", "S3"}


def _discover_check_modules() -> list:
    """Import every check_*.py module in this directory, sorted by name."""
    mods = []
    for path in sorted(HERE.glob("check_*.py")):
        mod = importlib.import_module(path.stem)
        if hasattr(mod, "check"):
            mods.append(mod)
    return mods


def _repo_root() -> pathlib.Path:
    # tools/plugin-quality/lint -> repo root is three levels up.
    return HERE.parent.parent.parent


def run(plugin_roots: list[pathlib.Path], repo_root: pathlib.Path) -> list[_common.Finding]:
    findings: list[_common.Finding] = []
    modules = _discover_check_modules()
    for root in plugin_roots:
        for mod in modules:
            try:
                findings.extend(mod.check(root))
            except Exception as exc:  # a crashing check is itself a finding, never a silent pass
                findings.append(
                    _common.Finding(
                        check="ERR",
                        rule=f"{mod.__name__}.crashed",
                        severity="S2",
                        path=str(root),
                        message=f"check module raised {type(exc).__name__}: {exc}",
                    )
                )
    # Repo-level marketplace check runs exactly once.
    mod = sys.modules.get("check_manifest")
    if mod is not None and hasattr(mod, "check_marketplace"):
        try:
            findings.extend(mod.check_marketplace(repo_root))
        except Exception as exc:
            findings.append(
                _common.Finding(
                    check="ERR",
                    rule="check_manifest.check_marketplace.crashed",
                    severity="S2",
                    path=str(repo_root),
                    message=f"marketplace check raised {type(exc).__name__}: {exc}",
                )
            )
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Static prompt-quality lint over plugin trees.")
    parser.add_argument("paths", nargs="*", help="plugin roots (default: all plugins/*/ with a manifest)")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    parser.add_argument("--repo-root", default=None, help="override repo root (for marketplace check)")
    args = parser.parse_args(argv)

    repo_root = pathlib.Path(args.repo_root) if args.repo_root else _repo_root()

    if args.paths:
        plugin_roots = [pathlib.Path(p).resolve() for p in args.paths]
    else:
        plugin_roots = _model.find_plugin_roots(repo_root)

    if not plugin_roots:
        print(f"No plugin roots found under {repo_root}/plugins/ — nothing to lint.", file=sys.stderr)
        return 0

    findings = run(plugin_roots, repo_root)
    findings.sort(key=lambda f: (f.path, f.line or 0, f.check))

    if args.json:
        print(_common.to_json(findings))
    else:
        for f in findings:
            print(f.render())
        counts = _common.summarize(findings)
        roots = ", ".join(p.name for p in plugin_roots)
        print(
            f"\nplugin-quality lint over [{roots}]: "
            f"{counts['total']} finding(s) "
            f"(S1={counts['S1']} S2={counts['S2']} S3={counts['S3']} S4={counts['S4']})",
            file=sys.stderr,
        )

    blocking = [f for f in findings if f.severity in BLOCKING]
    return 1 if blocking else 0


if __name__ == "__main__":
    raise SystemExit(main())
