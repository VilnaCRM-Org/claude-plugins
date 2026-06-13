"""Calibration corpus for the LLM-as-judge self-test.

For each CRITICAL rubric dimension (J1, J2, J3, J7, J10) this module embeds two
small synthetic artifacts:

* a known-GOOD (``P``) example that a correctly-calibrated judge should score AT
  OR ABOVE the dimension's ``floor``; and
* a known-BAD (``N``) example that a correctly-calibrated judge should score AT
  OR BELOW the dimension's ``block_floor`` (i.e. a hard-blocking failure).

``run_judge.py --selftest`` runs the LIVE judge over each P/N pair and asserts
the expected scoring, surfacing miscalibration of the rubric guidance or the
underlying model. The synthetic strings are intentionally small and exaggerated
so the expected verdict is unambiguous.

This is pure DATA (plus tiny constructors). It performs NO model calls; the live
calls happen in ``run_judge``. The unittest suite imports this to assert the
corpus is complete (every critical dimension has both a P and an N) without
spending any API budget.
"""

from __future__ import annotations

import dataclasses
import pathlib

import _model  # noqa: E402  (judge/ and lint/ are on sys.path via the importers)


# The critical dimensions this corpus calibrates. Kept here (not re-derived from
# rubrics) so the self-test fails loudly if the rubric's critical set drifts away
# from what we actually have calibration data for.
CRITICAL_DIMENSION_IDS: tuple[str, ...] = ("J1", "J2", "J3", "J7", "J10")


@dataclasses.dataclass(frozen=True)
class CalibrationCase:
    """One calibration artifact for one dimension and one polarity.

    ``polarity`` is "P" (known-good, expected >= floor) or "N" (known-bad,
    expected <= block_floor). ``extra_context`` mirrors what the runner injects
    for that kind (only meta-guides need it, for J10's inventory check).
    """

    dimension_id: str
    polarity: str  # "P" | "N"
    kind: str
    name: str
    raw: str
    extra_context: str = ""

    def artifact(self) -> "_model.Artifact":
        """Build a synthetic :class:`_model.Artifact` from this case's raw text."""
        has_fm, data, err, body = _model.split_frontmatter(self.raw)
        h1, h2 = _model.extract_headings(body)
        # A neutral synthetic path so .rel/.name resolve without touching disk.
        if self.kind == "skill":
            path = pathlib.Path(f"/calib/plugins/p/skills/{self.name}/SKILL.md")
        elif self.kind == "meta-guide":
            path = pathlib.Path(f"/calib/plugins/p/skills/{self.name}.md")
        else:  # command | agent
            folder = "commands" if self.kind == "command" else "agents"
            path = pathlib.Path(f"/calib/plugins/p/{folder}/{self.name}.md")
        return _model.Artifact(
            path=path,
            plugin_root=pathlib.Path("/calib/plugins/p"),
            kind=self.kind,
            raw=self.raw,
            has_frontmatter=has_fm,
            frontmatter=data,
            frontmatter_error=err,
            body=body,
            h1=h1,
            h2_sections=h2,
        )


# ---------------------------------------------------------------------------
# J1 — trigger-specificity (skill/agent): does the description discriminate?
# ---------------------------------------------------------------------------
_J1_GOOD = """---
name: cache-invalidator
description: Invalidate stale cache entries after a write. Use when a command handler mutates a cached aggregate and you must purge or refresh its key. Skip when the query is uncached. NOT for adding new cache entries (use cache-writer instead).
---
# Cache invalidator

Use after a mutating handler runs. Match the changed aggregate to its cache key,
purge it, and emit an invalidation event. Do not handle initial cache population.
"""

_J1_BAD = """---
name: helper
description: Helps with caching.
---
# Helper

This component helps with caching things in the application.
"""


# ---------------------------------------------------------------------------
# J2 — body-description-fidelity (skill/agent/command): no self-contradiction.
# ---------------------------------------------------------------------------
_J2_GOOD = """---
name: rate-limiter
description: Add a token-bucket rate limit to an endpoint. Use when an endpoint must cap requests per client.
---
# Rate limiter

This component adds a token-bucket rate limit to the configured endpoint, capping
requests per client exactly as the description promises. It refills the bucket on
a timer and returns 429 when the bucket is empty.
"""

_J2_BAD = """---
name: rate-limiter
description: Add a token-bucket rate limit to an endpoint, including distributed coordination across nodes.
---
# Rate limiter

This component adds a rate limit to a single endpoint. NOTE: this component does
NOT do any distributed coordination across nodes and does NOT share state — it is
purely per-process, directly contradicting the description's distributed claim.
"""


# ---------------------------------------------------------------------------
# J3 — degrade-path-soundness (skill/agent/command): terminating fallbacks.
# ---------------------------------------------------------------------------
_J3_GOOD = """---
name: pr-comment-resolver
description: Resolve PR review comments. Use when a PR has unresolved AI review threads.
---
# PR comment resolver

For every unresolved thread, either fix the code or post a reasoned reply, then
resolve the thread.

## Degrade path
If no reviewer app is installed (NFR-4), fall back to the ai-review-loop.sh
findings as the comment source, resolve those, then report SUCCESS-WITH-REPORT.
Never loop waiting for a reviewer to appear; if none can be produced, report
SKIPPED and exit. Every path ends in an explicit reported outcome.
"""

_J3_BAD = """---
name: pr-comment-resolver
description: Resolve PR review comments. Use when a PR has unresolved AI review threads.
---
# PR comment resolver

Fetch the review comments and resolve them.

## Degrade path
If the reviewer app has not posted comments yet, retry fetching the comments
until they appear, then resolve them. Keep retrying — the comments will show up
eventually. (No bound, no SKIPPED/ESCALATED outcome: this loops forever.)
"""


# ---------------------------------------------------------------------------
# J7 — semantic-generalization (all kinds): no baked-in source-project domain.
# ---------------------------------------------------------------------------
_J7_GOOD = """---
name: repository-reader
description: Read aggregates from the configured repository. Use when a query handler must load a domain object.
---
# Repository reader

Given an id, load the aggregate from the configured repository for {Entity} and
map it to a read model. Works with any persistence engine the profile selects;
all examples are parameterized as the configured repository and {Entity}.
"""

_J7_BAD = """---
name: repository-reader
description: Read aggregates from the configured repository. Use when a query handler must load a domain object.
---
# Repository reader

Load the user account from the Mongo-backed repository that stores users. The
persistence engine is MongoDB, so call db.users.find() to fetch the OAuth user
document. Every example assumes the user-account domain backed by MongoDB.
"""


# ---------------------------------------------------------------------------
# J10 — meta-guide-inventory (meta-guide): list EXACTLY the shipped skills.
# The authoritative skill list is injected as extra_context, mirroring the
# runner's _meta_guide_context.
# ---------------------------------------------------------------------------
_J10_CONTEXT = (
    "Authoritative list of skills that ship in this plugin (for J10 inventory "
    "accuracy): alpha-skill, beta-skill, gamma-skill"
)

_J10_GOOD = """# Plugin skills guide

This plugin ships exactly these skills:

- alpha-skill — does the alpha thing.
- beta-skill — does the beta thing.
- gamma-skill — does the gamma thing.

Decision tree: need alpha -> alpha-skill; need beta -> beta-skill; need gamma ->
gamma-skill. Every branch points to a real shipped skill and the list is exact.
"""

_J10_BAD = """# Plugin skills guide

This plugin ships these skills:

- alpha-skill — does the alpha thing.
- delta-skill — does the delta thing.

Decision tree: need alpha -> alpha-skill; need delta -> delta-skill. (delta-skill
does NOT ship and beta-skill and gamma-skill are missing entirely — the inventory
is both stale and incomplete.)
"""


CASES: tuple[CalibrationCase, ...] = (
    CalibrationCase("J1", "P", "skill", "cache-invalidator", _J1_GOOD),
    CalibrationCase("J1", "N", "skill", "helper", _J1_BAD),
    CalibrationCase("J2", "P", "skill", "rate-limiter", _J2_GOOD),
    CalibrationCase("J2", "N", "skill", "rate-limiter", _J2_BAD),
    CalibrationCase("J3", "P", "skill", "pr-comment-resolver", _J3_GOOD),
    CalibrationCase("J3", "N", "skill", "pr-comment-resolver", _J3_BAD),
    CalibrationCase("J7", "P", "skill", "repository-reader", _J7_GOOD),
    CalibrationCase("J7", "N", "skill", "repository-reader", _J7_BAD),
    CalibrationCase("J10", "P", "meta-guide", "skills-guide", _J10_GOOD, _J10_CONTEXT),
    CalibrationCase("J10", "N", "meta-guide", "skills-guide", _J10_BAD, _J10_CONTEXT),
)


def cases_for(dimension_id: str) -> list[CalibrationCase]:
    """Return all calibration cases for one dimension id."""
    return [c for c in CASES if c.dimension_id == dimension_id]


def positive_for(dimension_id: str) -> CalibrationCase | None:
    return next((c for c in cases_for(dimension_id) if c.polarity == "P"), None)


def negative_for(dimension_id: str) -> CalibrationCase | None:
    return next((c for c in cases_for(dimension_id) if c.polarity == "N"), None)
