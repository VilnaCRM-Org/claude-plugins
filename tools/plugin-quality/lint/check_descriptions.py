"""Description-quality checks (L11–L14) for plugin prompt artifacts.

Pins ``plugin docs`` (length cap), ``FR-15`` (skill trigger clause),
``arch §3`` (agent delegation trigger), and the universal non-empty rule.

Checks implemented:

* **L11** ``descriptions.cap-1536`` (S2) — for skills, ``len(description) +
  len(when_to_use)`` must be ``<= 1536``; for agents and commands the
  ``description`` alone must be ``<= 1536``.
* **L12** ``descriptions.skill.no-trigger`` (S2) — a skill ``description``
  must contain a trigger clause (case-insensitive ``"use when"`` or
  ``"when to use"``).
* **L13** ``descriptions.agent.no-trigger`` (S2) — an agent ``description``
  must contain a delegation trigger (case-insensitive ``"delegate"``,
  ``"use when"``, ``"use this agent"``, or ``"proactively"``).
* **L14** ``descriptions.too-short`` (S2) — ``description`` must be present
  and ``>= 20`` characters, for commands, agents, and skills.
"""

from __future__ import annotations

import pathlib
import re

from _common import Finding
import _model

CAP = 1536
MIN_LEN = 20

# L12: skill trigger clause.
SKILL_TRIGGER_RE = re.compile(r"use when|when to use", re.IGNORECASE)
# L13: agent delegation trigger.
AGENT_TRIGGER_RE = re.compile(
    r"delegate|use when|use this agent|proactively", re.IGNORECASE
)


def _text(value) -> str:
    """Coerce a frontmatter scalar to a stripped string (non-strings -> "")."""
    return value.strip() if isinstance(value, str) else ""


def _check_too_short(art, description: str) -> list[Finding]:
    """L14: non-empty and >= 20 chars (commands + agents + skills)."""
    if len(description) >= MIN_LEN:
        return []
    return [
        Finding(
            check="L14",
            rule="descriptions.too-short",
            severity="S2",
            path=art.rel,
            message=(
                f"{art.kind} description must be non-empty and at least "
                f"{MIN_LEN} characters (got {len(description)})"
            ),
        )
    ]


def _check_cap(art, description: str) -> list[Finding]:
    """L11: length cap. Skills add ``when_to_use``; others cap description alone."""
    if art.kind == "skill":
        when = _text(art.frontmatter.get("when_to_use"))
        total = len(description) + len(when)
        if total <= CAP:
            return []
        message = (
            f"skill description + when_to_use is {total} chars; "
            f"must be <= {CAP}"
        )
    else:  # command / agent: description alone capped
        if len(description) <= CAP:
            return []
        message = (
            f"{art.kind} description is {len(description)} chars; "
            f"must be <= {CAP}"
        )
    return [
        Finding(
            check="L11",
            rule="descriptions.cap-1536",
            severity="S2",
            path=art.rel,
            message=message,
        )
    ]


def _check_skill_trigger(art, description: str) -> list[Finding]:
    """L12: skill trigger clause."""
    if art.kind != "skill" or not description or SKILL_TRIGGER_RE.search(description):
        return []
    return [
        Finding(
            check="L12",
            rule="descriptions.skill.no-trigger",
            severity="S2",
            path=art.rel,
            message=(
                'skill description must contain a trigger clause '
                '("Use when" or "When to use")'
            ),
        )
    ]


def _check_agent_trigger(art, description: str) -> list[Finding]:
    """L13: agent delegation trigger."""
    if art.kind != "agent" or not description or AGENT_TRIGGER_RE.search(description):
        return []
    return [
        Finding(
            check="L13",
            rule="descriptions.agent.no-trigger",
            severity="S2",
            path=art.rel,
            message=(
                'agent description must contain a delegation trigger '
                '("Delegate", "Use when", "Use this agent", or "Proactively")'
            ),
        )
    ]


# Per-artifact rule helpers (L14, L11, L12, L13), in original evaluation order.
_RULES = (
    _check_too_short,
    _check_cap,
    _check_skill_trigger,
    _check_agent_trigger,
)


def check(plugin_root) -> list[Finding]:
    plugin_root = pathlib.Path(plugin_root)
    findings: list[Finding] = []

    for art in _model.discover(plugin_root):
        if art.kind not in ("command", "agent", "skill"):
            continue  # meta-guides carry no frontmatter (ADR-11)

        description = _text(art.frontmatter.get("description"))
        for rule in _RULES:
            findings.extend(rule(art, description))

    return findings
