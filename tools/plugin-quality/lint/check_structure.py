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

# ATX H2 with optional trailing '#' run stripped (matches _model.H2_RE).
_H2_RE = re.compile(r"^##\s+(.*?)\s*#*\s*$")


def _section_text(body: str, heading: str) -> str | None:
    """Return the fence-aware body text of the H2 ``heading``, or None.

    Slices from the line after the heading up to (not including) the next
    non-fenced H2. Headings inside code fences are ignored.
    """
    start = None
    lines: list[str] = []
    for lineno, text, in_fence in _model.iter_body_lines(body):
        if start is None:
            if not in_fence:
                m = _H2_RE.match(text)
                if m and m.group(1).strip() == heading:
                    start = lineno
            continue
        if not in_fence and _H2_RE.match(text):
            break
        lines.append(text)
    if start is None:
        return None
    return "\n".join(lines)


def check(plugin_root: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []

    for art in _model.discover(plugin_root):
        if art.kind == "command":
            present = set(art.h2_sections)
            for section in COMMAND_SPINE:
                if section not in present:
                    findings.append(
                        Finding(
                            check="L15",
                            rule="structure.command.spine",
                            severity="S2",
                            path=art.rel,
                            message=f"command missing required H2 section: ## {section}",
                        )
                    )

        elif art.kind == "agent":
            present = set(art.h2_sections)
            for section in AGENT_SPINE:
                if section not in present:
                    findings.append(
                        Finding(
                            check="L16",
                            rule="structure.agent.spine",
                            severity="S2",
                            path=art.rel,
                            message=f"agent missing required H2 section: ## {section}",
                        )
                    )

        elif art.kind == "skill":
            # L17: first H2 must be exactly "Profile keys consumed".
            first = art.h2_sections[0] if art.h2_sections else None
            if first != SKILL_FIRST_H2:
                findings.append(
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
                )

            # L18: a capability-gating section must emit a SKIPPED degrade path.
            # The skip note must be scoped to gating context, not satisfied by an
            # unrelated "skipping ahead" elsewhere in the body. It counts when it
            # lives in ANY gate-named section, or when a skip word sits next to a
            # gate predicate (capabilities./framework./persistence.) anywhere —
            # the genuine "skip when <predicate> is false" contract, which some
            # skills document outside a literally "gate"-named H2.
            gate_sections = [h for h in art.h2_sections if GATE_RE.search(h)]
            if gate_sections:
                in_gate_section = any(
                    "SKIPPED:" in (sec := _section_text(art.body, h) or "")
                    or SKIP_NOTE_RE.search(sec)
                    for h in gate_sections
                )
                has_skip = in_gate_section or bool(
                    SKIP_PREDICATE_RE.search(art.body)
                )
                if not has_skip:
                    findings.append(
                        Finding(
                            check="L18",
                            rule="structure.skill.gate-skipped-token",
                            severity="S2",
                            path=art.rel,
                            message=(
                                "gated skill (H2 "
                                f"'## {gate_sections[0]}') must emit a 'SKIPPED:' "
                                "skip-path token in its body (NFR-4)"
                            ),
                        )
                    )

        # meta-guides are exempt from L17/L18 (ADR-11).

    return findings
