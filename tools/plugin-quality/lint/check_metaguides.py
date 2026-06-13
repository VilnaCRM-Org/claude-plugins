"""Meta-guide content contract checks (L30) for plugin meta-guides.

A "meta-guide" is a loose ``skills/*.md`` file directly under ``skills/`` (NOT a
``skills/<name>/SKILL.md`` — those are skills, kind ``skill``). Meta-guides carry
no frontmatter (ADR-11) and document cross-cutting policy rather than a single
skill's procedure.

* L30 (metaguide.decision-guide.triage) -- the skill-DECISION guide must pin the
  BMAD triage contract: every skill is given a recorded verdict during the
  new-feature gate, with NO silent skips (FR-16 coverage gap). The shipped
  ``skills/SKILL-DECISION-GUIDE.md`` states it verbatim as::

      The gate contract is: **every skill verdict recorded, no silent skips**.

  Any meta-guide whose FILENAME contains ``DECISION`` (case-insensitive) must
  carry that contract; a meta-guide that is not a decision guide is exempt.

The match is tolerant: it accepts the "no silent skip(s)" phrasing OR the
"every skill ... verdict" phrasing so a future rewording of the same contract
keeps passing.
"""

import pathlib
import re

from _common import Finding
import _model

# L30: the BMAD triage contract clause, in either of the two equivalent
# phrasings the shipped decision guide uses. ``\s+`` tolerates the wrapped /
# bold ("**every skill verdict recorded, no silent skips**") rendering.
_NO_SILENT_SKIP_RE = re.compile(r"no\s+silent\s+skips?", re.IGNORECASE)
_EVERY_VERDICT_RE = re.compile(r"every\s+skill\b[^\n]{0,80}?\bverdict", re.IGNORECASE)

# A meta-guide whose filename marks it as the decision guide (case-insensitive).
_DECISION_NAME_RE = re.compile(r"decision", re.IGNORECASE)


def _has_triage_clause(body: str) -> bool:
    """True when the body pins the every-verdict / no-silent-skips contract."""
    return bool(_NO_SILENT_SKIP_RE.search(body) or _EVERY_VERDICT_RE.search(body))


def check(plugin_root: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []

    for art in _model.discover(plugin_root):
        if art.kind != "meta-guide":
            continue
        if not _DECISION_NAME_RE.search(art.path.name):
            continue
        if _has_triage_clause(art.body):
            continue
        findings.append(
            Finding(
                check="L30",
                rule="metaguide.decision-guide.triage",
                severity="S3",
                path=art.rel,
                message=(
                    "decision meta-guide must pin the BMAD triage contract: "
                    "every skill verdict is recorded with no silent skips "
                    "(e.g. 'every skill verdict recorded, no silent skips')"
                ),
            )
        )

    return findings
