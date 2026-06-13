"""Escalation / loop-safety contract checks (L26-L27) for prompt artifacts.

The SDLC loop bounds every retry loop and reports a single canonical block
when a loop breaches its guard. Two contracts are pinned here, over commands
and agents only (skills and meta-guides are exempt):

* L26 -- the iteration-bound section states its cap. Commands carry it in
  ``## Iteration guard``; agents in ``## Iteration discipline``. The cap may
  be written ``MAX_ITERATIONS=5`` or in prose ("max 5 iterations",
  "5 iterations", "iteration <n>/5", a bare "/5"). Flag when the section
  exists but names no bound.
* L27 -- every ``=== SDLC ESCALATION ===`` block carries all seven canonical
  fields. The orchestrator's ``=== SDLC RUN REPORT ===`` banner is exempt
  (it has its own shape). A file with neither banner is L26's concern, not
  this rule's.

Section text is sliced fence-aware from the artifact body; escalation blocks
are located by their banner line wherever it appears (inside a fence or not).
"""

import pathlib
import re

from _common import Finding
import _model

# L26: which H2 carries the iteration bound, per artifact kind.
GUARD_SECTION = {
    "command": "Iteration guard",
    "agent": "Iteration discipline",
}

# L26: any of these in the guard section satisfies the bound. The cap is 5:
# accept MAX_ITERATIONS=5, the prose "max 5 iteration(s)" / "5 iterations",
# or an "iteration <n>/5" / bare "/5" counter. A different number
# (MAX_ITERATIONS=3) does NOT satisfy the contract.
MAX_ITER_RE = re.compile(r"MAX_ITERATIONS\s*=\s*5\b")
PROSE_MAX_RE = re.compile(r"\bmax\b[^\n]{0,12}?\b5\s+iteration", re.IGNORECASE)
N_ITERS_RE = re.compile(r"\b5\s+iterations?\b", re.IGNORECASE)
# An "iteration <n>/5" counter only counts when it is in iteration context:
# the word "iteration" within ~20 chars on either side of the "/5" token.
# This rejects a stray "4/5" that merely co-occurs with a wrong cap
# (e.g. "MAX_ITERATIONS=3 ... 4/5 done"). The (?<![A-Za-z_]) prefix + (?!s?=)
# suffix keep the "ITERATIONS" inside "MAX_ITERATIONS=3" from qualifying.
_ITER_WORD = r"(?<![A-Za-z_])iteration(?!s?\s*=)s?"
COUNTER_RE = re.compile(
    _ITER_WORD + r"[^\n]{0,20}?/5\b|/5\b[^\n]{0,20}?" + _ITER_WORD,
    re.IGNORECASE,
)

# ATX H2 with optional trailing '#' run stripped ("## Guard ##" -> "Guard").
H2_RE = re.compile(r"^##\s+(.*?)\s*#*\s*$")

# L27: banners and the seven required fields.
ESCALATION_BANNER = "=== SDLC ESCALATION ==="
RUN_REPORT_BANNER = "=== SDLC RUN REPORT ==="
BANNER_RE = re.compile(r"^\s*===\s")
END_RE = re.compile(r"^\s*===\s*END\s*===\s*$")

REQUIRED_FIELDS = (
    "stage",
    "iteration",
    "exit_condition",
    "status",
    "blocking_finding",
    "iteration_log",
    "recommended_action",
)


def _section_text(body: str, heading: str) -> str | None:
    """Return the body text of the H2 ``heading`` (fence-aware), or None.

    Slices from the line after the heading up to (not including) the next H2.
    Headings inside code fences are ignored.
    """
    start = None
    lines: list[str] = []
    for lineno, text, in_fence in _model.iter_body_lines(body):
        if start is None:
            if not in_fence:
                m = H2_RE.match(text)
                if m and m.group(1).strip() == heading:
                    start = lineno
            continue
        # collecting: stop at the next real (non-fenced) H2.
        if not in_fence and H2_RE.match(text):
            break
        lines.append(text)
    if start is None:
        return None
    return "\n".join(lines)


def _has_iteration_bound(section: str) -> bool:
    return bool(
        MAX_ITER_RE.search(section)
        or PROSE_MAX_RE.search(section)
        or N_ITERS_RE.search(section)
        or COUNTER_RE.search(section)
    )


def _escalation_blocks(body: str):
    """Yield ``(banner_lineno, banner_text, field_names)`` for each block.

    A block starts at an ``=== ... ===`` banner line and runs until ``=== END
    ===``, the next ``=== ... ===`` banner, or end of body. ``field_names`` are
    the leading ``key:`` tokens found on the block's lines (lowercased).
    """
    blocks: list[tuple[int, str, set[str]]] = []
    banner_lineno = None
    banner_text = ""
    fields: set[str] = set()
    for lineno, text, _in_fence in _model.iter_body_lines(body):
        stripped = text.strip()
        if BANNER_RE.match(text):
            if END_RE.match(text):
                if banner_lineno is not None:
                    blocks.append((banner_lineno, banner_text, fields))
                    banner_lineno = None
                    fields = set()
                continue
            # a new (non-END) banner: flush the open block, start a new one.
            if banner_lineno is not None:
                blocks.append((banner_lineno, banner_text, fields))
            banner_lineno = lineno
            banner_text = stripped
            fields = set()
            continue
        if banner_lineno is None:
            continue
        # inside a block: capture a leading "key:" field token. An optional
        # list marker ("- stage: 6") is tolerated so fields rendered as a
        # markdown bullet list are still recognized.
        m = re.match(r"\s*(?:[-*]\s+)?([A-Za-z_]+)\s*:", text)
        if m:
            fields.add(m.group(1).lower())
            # a line may carry two fields, e.g. "stage: x   iteration: y".
            for extra in re.findall(r"(?:[-*]\s+)?\b([A-Za-z_]+)\s*:", text)[1:]:
                fields.add(extra.lower())
    if banner_lineno is not None:
        blocks.append((banner_lineno, banner_text, fields))
    return blocks


def check(plugin_root: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []

    for art in _model.discover(plugin_root):
        if art.kind not in ("command", "agent"):
            continue

        # --- L26: iteration bound stated in the guard section -------------
        heading = GUARD_SECTION[art.kind]
        section = _section_text(art.body, heading)
        if section is not None and not _has_iteration_bound(section):
            findings.append(
                Finding(
                    check="L26",
                    rule="escalation.max-iterations",
                    severity="S2",
                    path=art.rel,
                    message=(
                        f"'## {heading}' section must state the iteration bound of 5 "
                        "(MAX_ITERATIONS=5 or prose 'max 5 iterations')"
                    ),
                )
            )

        # --- L27: escalation block carries all seven fields --------------
        for banner_lineno, banner_text, fields in _escalation_blocks(art.body):
            if banner_text != ESCALATION_BANNER:
                # RUN REPORT and any other banner are exempt from the
                # seven-field escalation contract.
                continue
            missing = [f for f in REQUIRED_FIELDS if f not in fields]
            for field in missing:
                findings.append(
                    Finding(
                        check="L27",
                        rule="escalation.block-fields",
                        severity="S2",
                        path=art.rel,
                        line=banner_lineno,
                        message=(
                            f"'{ESCALATION_BANNER}' block missing required "
                            f"field '{field}:'"
                        ),
                    )
                )

    return findings
