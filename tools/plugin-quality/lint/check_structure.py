"""Section-structure contract checks (L15-L18) for plugin prompt artifacts.

Pins the H2 "spine" every artifact kind must carry so the SDLC loop's
prompts stay shaped the way the orchestrator expects (presence, not order):

* commands -> 5-section spine (L15)
* agents   -> 8-section spine (L16)
* skills   -> first H2 is ``## Profile keys consumed`` (L17); meta-guides exempt
* skills   -> a capability-gating section must document its skip path (L18)

Section titles are compared case-sensitively against the exact H2 text.
"""

import pathlib
import re

from _common import Finding
import _model

# L15: command 5-section spine (presence anywhere in h2_sections, any order).
COMMAND_SPINE = (
    "Inputs",
    "Procedure",
    "Loop & exit condition",
    "Iteration guard",
    "Failure escalation",
)

# L16: agent 8-section spine (presence, order may differ).
AGENT_SPINE = (
    "Profile keys consumed",
    "Role",
    "Inputs",
    "Outputs",
    "Allowed actions",
    "Degrade paths",
    "Iteration discipline",
    "Smoke prompt",
)

# L17: a skill's first H2 must be exactly this.
SKILL_FIRST_H2 = "Profile keys consumed"

# L18: an H2 that names a capability gate, e.g. "Applicability gate",
# "Capability gate", "Gating".
GATE_RE = re.compile(r"(^|\s)gat(e|ing)\b", re.IGNORECASE)

# L18: a gating section must document its skip path. The canonical degrade
# marker is the literal ``SKIPPED:`` token; the shipped skills also express
# the same NFR-4 contract in prose ("record a skip note ... and skip"), so a
# ``skip``/``skipped`` degrade word in the gate SECTION satisfies the rule too.
SKIP_NOTE_RE = re.compile(r"\bskip(ped|ping)?\b", re.IGNORECASE)

# A skip degrade word tied to a gating predicate: a ``skip`` token within ~60
# chars of a profile gate key (capabilities./framework./persistence.). This is
# the genuine "skip when <predicate> is false" contract; it lets a skill whose
# skip-path lives outside a literally "gate"-named H2 still pass, while an
# unrelated navigational "skipping ahead" (no adjacent predicate) does not.
_GATE_PREDICATE = r"(?:capabilities|framework|persistence)\.[a-z0-9_.]+"
SKIP_PREDICATE_RE = re.compile(
    r"skip(?:ped|ping)?\b[^\n]{0,60}?" + _GATE_PREDICATE
    + r"|" + _GATE_PREDICATE + r"[^\n]{0,60}?\bskip(?:ped|ping)?\b",
    re.IGNORECASE,
)

# H2 section slicing (ATX + setext) is shared via _model.section_text.


def _check_spine(art, check_id: str, rule: str, spine, label: str) -> list[Finding]:
    """L15/L16: every spine section must be present (any order)."""
    present = set(art.h2_sections)
    return [
        Finding(
            check=check_id,
            rule=rule,
            severity="S2",
            path=art.rel,
            message=f"{label} missing required H2 section: ## {section}",
        )
        for section in spine
        if section not in present
    ]


def _check_skill_first_h2(art) -> list[Finding]:
    """L17: a skill's first H2 must be exactly ``Profile keys consumed``."""
    first = art.h2_sections[0] if art.h2_sections else None
    if first == SKILL_FIRST_H2:
        return []
    return [
        Finding(
            check="L17",
            rule="structure.skill.first-h2",
            severity="S2",
            path=art.rel,
            message=(
                f"skill first H2 must be '## {SKILL_FIRST_H2}', "
                f"found {('## ' + first) if first else '(no H2 sections)'}"
            ),
        )
    ]


def _gate_has_skip(art) -> bool:
    """True when a gating skill documents its skip path (NFR-4).

    Satisfied when a skip note lives in ANY gate-named section, or when a skip
    word sits next to a gate predicate (capabilities./framework./persistence.)
    anywhere — the genuine "skip when <predicate> is false" contract, which some
    skills document outside a literally "gate"-named H2.
    """
    gate_sections = [h for h in art.h2_sections if GATE_RE.search(h)]
    in_gate_section = any(
        "SKIPPED:" in (sec := _model.section_text(art.body, h) or "")
        or SKIP_NOTE_RE.search(sec)
        for h in gate_sections
    )
    return in_gate_section or bool(SKIP_PREDICATE_RE.search(art.body))


def _check_skill_gate(art) -> list[Finding]:
    """L18: a capability-gating section must document its skip path.

    Accepted in either form (see :func:`_gate_has_skip`): a literal ``SKIPPED:``
    token, or an in-gate-section skip note tied to a capability predicate.
    """
    gate_sections = [h for h in art.h2_sections if GATE_RE.search(h)]
    if not gate_sections or _gate_has_skip(art):
        return []
    return [
        Finding(
            check="L18",
            rule="structure.skill.gate-skipped-token",
            severity="S2",
            path=art.rel,
            message=(
                "gated skill (H2 "
                f"'## {gate_sections[0]}') must document its skip path "
                "(NFR-4): either a literal 'SKIPPED:' token, or an in-gate "
                "skip note tied to a capability predicate "
                "(capabilities./framework./persistence.)"
            ),
        )
    ]


def check(plugin_root: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []

    for art in _model.discover(plugin_root):
        if art.kind == "command":
            findings += _check_spine(
                art, "L15", "structure.command.spine", COMMAND_SPINE, "command"
            )
        elif art.kind == "agent":
            findings += _check_spine(
                art, "L16", "structure.agent.spine", AGENT_SPINE, "agent"
            )
        elif art.kind == "skill":
            findings += _check_skill_first_h2(art)
            findings += _check_skill_gate(art)
        # meta-guides are exempt from L17/L18 (ADR-11).

    return findings
