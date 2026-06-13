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
# Setext H2 underline: a line of two-or-more '-' (matches _model._SETEXT_H2_RE).
# _section_text duplicates the setext-aware slicing of check_structure here
# (we may not edit _model.py to factor a shared helper).
_SETEXT_H2_RE = re.compile(r"^-{2,}\s*$")

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


def _h2_title_at(idx: int, lines: list[tuple[str, bool]]) -> str | None:
    """Return the H2 title that BEGINS at stream index ``idx``, else None.

    Recognises both ATX (``## X``) and setext (``X`` then ``----``) H2 forms,
    consistent with :func:`_model.extract_headings`. For a setext heading the
    boundary line is the underline, so the title comes from the preceding
    non-blank, non-fenced text line. Duplicated from check_structure because
    _model.py may not be edited to share it.
    """
    text, in_fence = lines[idx]
    if in_fence:
        return None
    m = H2_RE.match(text)
    if m:
        return m.group(1).strip()
    if _SETEXT_H2_RE.match(text) and idx > 0:
        prev_text, prev_fenced = lines[idx - 1]
        if not prev_fenced and prev_text.strip() and not H2_RE.match(prev_text):
            return prev_text.strip()
    return None


def _section_text(body: str, heading: str) -> str | None:
    """Return the body text of the H2 ``heading`` (fence-aware), or None.

    Slices from the line after the heading up to (not including) the next
    non-fenced H2 (ATX or setext). Headings inside code fences are ignored.
    """
    lines = [(text, in_fence) for _lineno, text, in_fence in _model.iter_body_lines(body)]
    start = None  # stream index of the first content line of the section
    out: list[str] = []
    for idx in range(len(lines)):
        title = _h2_title_at(idx, lines)
        if start is None:
            if title == heading:
                start = idx + 1
            continue
        if title is not None:
            # A setext boundary's underline follows its title line, which we
            # already appended; drop that trailing title line from the section.
            text = lines[idx][0]
            if _SETEXT_H2_RE.match(text) and out:
                out.pop()
            break
        out.append(lines[idx][0])
    if start is None:
        return None
    return "\n".join(out)


def _has_iteration_bound(section: str) -> bool:
    return bool(
        MAX_ITER_RE.search(section)
        or PROSE_MAX_RE.search(section)
        or N_ITERS_RE.search(section)
        or COUNTER_RE.search(section)
    )


# A leading "key:" field token, tolerating an optional markdown list marker
# ("- stage: 6") so bullet-list fields are still recognized.
_FIELD_RE = re.compile(r"(?:[-*]\s+)?\b([A-Za-z_]+)\s*:")


def _line_fields(text: str) -> list[str]:
    """Lowercased ``key:`` field tokens on a single block line.

    A line may carry more than one field, e.g. ``"stage: x   iteration: y"``.
    Returns an empty list when the line opens with no recognizable field token.
    """
    if not re.match(r"\s*(?:[-*]\s+)?[A-Za-z_]+\s*:", text):
        return []
    return [name.lower() for name in _FIELD_RE.findall(text)]


def _escalation_blocks(body: str):
    """Yield ``(banner_lineno, banner_text, field_names)`` for each block.

    A block starts at an ``=== ... ===`` banner line and runs until ``=== END
    ===``, the next ``=== ... ===`` banner, or end of body. ``field_names`` are
    the leading ``key:`` tokens found on the block's lines (lowercased).
    """
    blocks: list[tuple[int, str, set[str]]] = []
    banner_lineno: int | None = None
    banner_text = ""
    fields: set[str] = set()

    for lineno, text, _in_fence in _model.iter_body_lines(body):
        is_banner = bool(BANNER_RE.match(text))

        # A line inside an open block that adds field tokens.
        if not is_banner:
            if banner_lineno is not None:
                fields.update(_line_fields(text))
            continue

        # Any banner closes the currently open block first.
        if banner_lineno is not None:
            blocks.append((banner_lineno, banner_text, fields))
            banner_lineno = None
            fields = set()

        # An END banner only closes; a non-END banner opens a fresh block.
        if not END_RE.match(text):
            banner_lineno = lineno
            banner_text = text.strip()
            fields = set()

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
