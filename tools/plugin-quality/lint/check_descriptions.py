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


def check(plugin_root) -> list[Finding]:
    plugin_root = pathlib.Path(plugin_root)
    findings: list[Finding] = []

    for art in _model.discover(plugin_root):
        if art.kind not in ("command", "agent", "skill"):
            continue  # meta-guides carry no frontmatter (ADR-11)

        description = _text(art.frontmatter.get("description"))

        # L14: non-empty and >= 20 chars (commands + agents + skills).
        if len(description) < MIN_LEN:
            findings.append(
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
            )

        # L11: length cap.
        if art.kind == "skill":
            when = _text(art.frontmatter.get("when_to_use"))
            total = len(description) + len(when)
            if total > CAP:
                findings.append(
                    Finding(
                        check="L11",
                        rule="descriptions.cap-1536",
                        severity="S2",
                        path=art.rel,
                        message=(
                            f"skill description + when_to_use is {total} chars; "
                            f"must be <= {CAP}"
                        ),
                    )
                )
        else:  # command / agent: description alone capped
            if len(description) > CAP:
                findings.append(
                    Finding(
                        check="L11",
                        rule="descriptions.cap-1536",
                        severity="S2",
                        path=art.rel,
                        message=(
                            f"{art.kind} description is {len(description)} chars; "
                            f"must be <= {CAP}"
                        ),
                    )
                )

        # L12: skill trigger clause.
        if art.kind == "skill" and description and not SKILL_TRIGGER_RE.search(description):
            findings.append(
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
            )

        # L13: agent delegation trigger.
        if art.kind == "agent" and description and not AGENT_TRIGGER_RE.search(description):
            findings.append(
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
            )

    return findings
