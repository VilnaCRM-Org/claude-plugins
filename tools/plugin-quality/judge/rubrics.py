"""Rubric registry for the LLM-as-judge.

Single source of truth for *both* the scoring guidance the model receives and
the thresholds the harness applies. Keeping them together prevents drift
between "what the model is asked to score" and "what the gate enforces".

Each dimension maps to docs/test-plan.md (J1..J11). ``critical`` dimensions can
block CI when their score falls below ``floor``; non-critical dimensions are
advisory (reported, never block). The model returns a 1-5 score + evidence per
dimension; Python — not the model — decides pass/fail.
"""

from __future__ import annotations

import dataclasses
import hashlib
import re

ARTIFACT_TYPES = ("command", "agent", "skill", "meta-guide")


@dataclasses.dataclass(frozen=True)
class Dimension:
    id: str
    name: str
    applies_to: tuple[str, ...]  # artifact kinds, or ("all",)
    critical: bool
    floor: int  # advisory: score < floor is reported as needs-attention
    guidance: str  # injected into the judge prompt
    name_filter: str | None = None  # only score artifacts whose name contains this
    block_floor: int = 2  # CI hard-block: a *critical* dim blocks only at score <= block_floor

    def __post_init__(self) -> None:
        # Guard the score-threshold invariants up front so a malformed dimension
        # fails loudly at construction rather than producing a nonsensical gate.
        if not isinstance(self.floor, int) or isinstance(self.floor, bool):
            raise ValueError(f"{self.id}: floor must be an int, got {self.floor!r}")
        if not isinstance(self.block_floor, int) or isinstance(self.block_floor, bool):
            raise ValueError(f"{self.id}: block_floor must be an int, got {self.block_floor!r}")
        if not (1 <= self.block_floor < self.floor <= 5):
            raise ValueError(
                f"{self.id}: require 1 <= block_floor < floor <= 5, got "
                f"block_floor={self.block_floor}, floor={self.floor}"
            )

    def applies(self, kind: str, name: str) -> bool:
        if "all" not in self.applies_to and kind not in self.applies_to:
            return False
        if self.name_filter:
            # Match name_filter on a token boundary (start/end or -/_ delimited)
            # so "qa" hits "qa", "qa-manual", "manual_qa" but not "equ-ali-qaty".
            pattern = rf"(^|[-_]){re.escape(self.name_filter)}([-_]|$)"
            if not re.search(pattern, name):
                return False
        return True


# Floor convention: critical dimensions fail below 4/5. The model is told 4 means
# "solid, minor nits only" and 3 means "a real reader-facing problem exists".
DIMENSIONS: tuple[Dimension, ...] = (
    Dimension(
        id="J1",
        name="trigger-specificity",
        applies_to=("skill", "agent"),
        critical=True,
        floor=4,
        guidance=(
            "Would Claude Code's router fire this component on the RIGHT tasks and "
            "NOT on adjacent ones, based solely on its frontmatter `description`? "
            "Reward a concrete 'Use when ... / Skip when <flag> / NOT for X (use Y instead)' "
            "shape that discriminates against sibling components. Penalize vague triggers "
            "('helps with APIs', 'code reviewer') that would over- or under-trigger. "
            "Score 5: unambiguous trigger + explicit disambiguation from siblings. "
            "Score 1: a bare topic label with no 'when'."
        ),
    ),
    Dimension(
        id="J2",
        name="body-description-fidelity",
        applies_to=("skill", "agent", "command"),
        critical=True,
        floor=4,
        guidance=(
            "Does the body deliver exactly what the `description` promises — no over-claim, "
            "no under-claim, and NO self-contradiction (e.g. description promises caching but "
            "body says 'this skill does NOT cover caching')? Score 1 on any direct contradiction "
            "between the description and the body."
        ),
    ),
    Dimension(
        id="J3",
        name="degrade-path-soundness",
        applies_to=("skill", "agent", "command"),
        critical=True,
        floor=4,
        guidance=(
            "For every external-capability or missing-input dependency, does the described "
            "degrade path actually TERMINATE — never loop forever, never silently hard-fail? "
            "It must end in an explicit reported outcome (e.g. SUCCESS-WITH-REPORT, SKIPPED, "
            "ESCALATED). Score 1 if any degrade path loops ('retry until it appears') or just "
            "crashes with no defined behavior. Reward citing NFR-4 and a concrete fallback "
            "(e.g. 'no reviewer app -> use ai-review-loop.sh, report, do not loop')."
        ),
    ),
    Dimension(
        id="J4",
        name="exit-condition-consistency",
        applies_to=("command",),
        critical=False,
        floor=4,
        guidance=(
            "Is the command's single exit condition stated consistently and measurably across its "
            "own sections (Procedure, Loop & exit condition, Iteration guard) and consistent with "
            "the FR id named in its H1 — not vague, not contradicting itself between sections? "
            "Penalize an exit condition that is phrased one way in one section and a materially "
            "different way in another, or that is too vague to verify. Judge INTERNAL consistency "
            "only; do not require an external stage table the artifact does not contain."
        ),
    ),
    Dimension(
        id="J5",
        name="loop-escalation-soundness",
        applies_to=("command", "agent"),
        critical=False,
        floor=4,
        guidance=(
            "Does the prose loop logic actually BOUND iterations (MAX_ITERATIONS=5), restate the "
            "counter each turn, and explicitly NEVER auto-reset a tripped circuit breaker? "
            "Penalize any instruction to reset/clear a breaker and retry, or a loop with no "
            "visible counter increment."
        ),
    ),
    Dimension(
        id="J6",
        name="profile-key-branching",
        applies_to=("skill",),
        critical=False,
        floor=4,
        guidance=(
            "For every profile key the skill lists under '## Profile keys consumed', does the body "
            "actually BRANCH behavior on it where relevant, with BOTH conditional branches present "
            "(e.g. persistence.mapper -> both ORM-migration and ODM-schema paths; engine -> both "
            "MySQL EXPLAIN and Mongo explain())? Penalize a key that is listed but never used, or a "
            "conditional with only one branch documented."
        ),
    ),
    Dimension(
        id="J7",
        name="semantic-generalization",
        applies_to=("all",),
        critical=True,
        floor=4,
        guidance=(
            "Beyond the literal denylist, is there PARAPHRASED or STRUCTURAL leakage of the source "
            "project (a user/OAuth service backed by MongoDB)? E.g. 'the Mongo-backed repository that "
            "stores users', a hardcoded assumption that the persistence engine is MongoDB, an example "
            "that only makes sense for a user-account domain. The component must read as generic to ANY "
            "PHP backend. Score 1 on a clear domain assumption baked in as if universal; score 5 when "
            "all examples are parameterized ('the configured repository', '{Entity}')."
        ),
    ),
    Dimension(
        id="J8",
        name="root-cause-culture",
        applies_to=("agent", "skill"),
        critical=False,
        floor=4,
        guidance=(
            "Do the instructions steer toward ROOT-CAUSE fixes and explicitly forbid suppressing "
            "findings, lowering quality thresholds, or editing config (deptrac.yaml, baselines) to "
            "pass? Penalize any loophole that permits 'add a baseline entry' / 'relax the threshold' / "
            "'skip the check' to make CI green."
        ),
    ),
    Dimension(
        id="J9",
        name="qa-black-box",
        applies_to=("agent", "command"),
        critical=False,
        floor=4,
        name_filter="qa",
        guidance=(
            "QA components only: are verdicts derived STRICTLY from observed runtime behavior "
            "(HTTP responses, CLI output) and never from reading implementation source? Penalize any "
            "instruction to inspect handlers/entities to decide a verdict."
        ),
    ),
    Dimension(
        id="J10",
        name="meta-guide-inventory",
        applies_to=("meta-guide",),
        critical=True,
        floor=4,
        guidance=(
            "Does the guide enumerate EXACTLY the skills that ship in the plugin — no stale entries, "
            "no missing ones — and does every decision-tree branch point to a real skill whose "
            "description matches the branch condition? You will be given the authoritative list of "
            "shipped skill names; score 1 if the guide lists a skill not in that set or omits one."
        ),
    ),
    Dimension(
        id="J11",
        name="instruction-unambiguity",
        applies_to=("all",),
        critical=False,
        floor=4,
        guidance=(
            "Is any individual instruction open to two materially different readings "
            "('validate the profile or skip if needed' — when?)? Penalize ambiguous conditionals, "
            "undefined placeholders, and steps whose ordering is unclear."
        ),
    ),
)

DIMENSIONS_BY_ID = {d.id: d for d in DIMENSIONS}


def applicable_dimensions(kind: str, name: str) -> list[Dimension]:
    return [d for d in DIMENSIONS if d.applies(kind, name)]


def guidance_fingerprint() -> str:
    """Short sha256 of all dimension guidance strings.

    Folded into the cache identity so that editing any dimension's ``guidance``
    self-invalidates stale verdicts without a manual ``RUBRIC_VERSION`` bump.
    """
    h = hashlib.sha256()
    for d in DIMENSIONS:
        h.update(d.id.encode("utf-8"))
        h.update(b"\x00")
        h.update(d.guidance.encode("utf-8"))
        h.update(b"\x00")
    return h.hexdigest()[:16]
