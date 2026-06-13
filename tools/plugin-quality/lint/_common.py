"""Shared types and reporting for the plugin-quality static linters.

Every Tier-1 check module exposes a single entrypoint::

    def check(plugin_root: pathlib.Path) -> list[Finding]: ...

and returns zero or more :class:`Finding` objects. The aggregator
(``lint_all.py``) discovers those entrypoints, runs them over every
``plugins/*/`` tree, and renders the combined result.

No third-party dependency beyond PyYAML (used in ``_model``). Self-tests use
the stdlib ``unittest`` runner, so the whole toolkit runs with a bare
``python3`` + PyYAML — no pip install required.
"""

from __future__ import annotations

import dataclasses
import json
from typing import Iterable

# Severity ladder mirrors docs/test-strategy.md.
SEVERITIES = ("S1", "S2", "S3", "S4")


@dataclasses.dataclass(frozen=True)
class Finding:
    """One contract violation found in a plugin artifact.

    Attributes:
        check: matrix id from docs/test-plan.md, e.g. ``"L1"``.
        rule: stable dotted rule id, e.g. ``"frontmatter.command.missing-key"``.
        severity: one of :data:`SEVERITIES`.
        path: repo-relative file path the finding is about.
        message: human-readable, actionable description.
        line: 1-based line number when known, else ``None``.
    """

    check: str
    rule: str
    severity: str
    path: str
    message: str
    line: int | None = None

    def __post_init__(self) -> None:
        if self.severity not in SEVERITIES:
            raise ValueError(f"invalid severity {self.severity!r}; expected one of {SEVERITIES}")

    def as_dict(self) -> dict:
        return dataclasses.asdict(self)

    def location(self) -> str:
        return f"{self.path}:{self.line}" if self.line is not None else self.path

    def render(self) -> str:
        return f"{self.location()}: [{self.severity} {self.check}] {self.message} ({self.rule})"


def to_json(findings: Iterable[Finding]) -> str:
    return json.dumps([f.as_dict() for f in findings], indent=2, sort_keys=True)


def summarize(findings: list[Finding]) -> dict[str, int]:
    """Count findings by severity for a compact CI summary line."""
    counts = {s: 0 for s in SEVERITIES}
    for f in findings:
        counts[f.severity] += 1
    counts["total"] = len(findings)
    return counts
