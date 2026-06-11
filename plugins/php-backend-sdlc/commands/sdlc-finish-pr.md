---
description: "Create or update the PR, then drive the CI-fix and comment-resolution loops until checks are green and zero review comments remain unresolved"
argument-hint: "[pr-number]"
---

# /sdlc-finish-pr — PR finishing loops (FR-8)

Stage 6 of the SDLC loop. Two independent bounded loops finish the PR:
`ci-fixer` until all checks are green, and `pr-comment-resolver` until
zero review comments remain unresolved. Each loop keeps its OWN
iteration counter. Every missing external capability degrades with a
report instead of failing (NFR-4).

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/sdlc-setup`.
- The PR: the `pr-number` argument, or the current branch's PR
  (`gh pr view`); if none exists yet, step 1 creates it.
- `specs/<slug>/` — the planning chain the PR description links to.
- Profile keys: `ci.provider` and `ci.required_checks` (CI loop and its
  degrade), `review.coderabbit` (comment-source selection).

## Procedure

1. **PR create/update** — if the branch has no PR, create it:
   `gh pr create` with a spec-linked description: the issue URL, links
   to the `specs/<slug>/` artifacts, the implemented-stories summary,
   and the acceptance-criteria checklist. If a PR exists, refresh the
   description with `gh pr edit` instead.

2. **CI fix loop — counter A** — degrade check first: if the profile's
   `ci.provider` is `null`, or the PR reports no checks at all, SKIP
   this loop with the note "CI stage skipped: no checks configured"
   and treat the CI half of the exit condition as satisfied-with-report
   (NFR-4 — a degrade path never loops and never hard-fails).

   Otherwise dispatch the `ci-fixer` agent (Task tool): poll
   `gh pr checks`; for each failing check, fetch the failure logs
   (`gh run view --log-failed`), diagnose the root cause, fix the
   CAUSE — never suppress findings, never edit quality thresholds
   (governance-protected) — push, and re-poll. One
   poll-diagnose-fix-push cycle is one iteration of counter A
   (`ci_fix iteration <a>/5`). Loop until every check (at minimum the
   profile's `ci.required_checks`) is green, or counter A is exhausted
   → escalate.

3. **Comment source selection** — if `review.coderabbit` is true (or
   any AI reviewer app posts review comments on the PR), the PR's own
   threads are the comment source. Otherwise (no reviewer app), select
   the degraded source: `pr-comment-resolver` itself runs
   `ai-review-loop.sh --diff-base <default-branch> --max-iterations 1`
   each pass and treats its findings as the comment set to resolve
   (NFR-4). Never run `ai-review-loop.sh` directly from this command:
   the agent is the single owner of the degrade source, so the loop
   runs exactly once per iteration and every fix it applies stays
   inside counter B's accounting. Record the substitution as a degrade
   note in the final report and name the selected source in the step-4
   dispatch prompt.

4. **Comment resolution loop — counter B** — dispatch the
   `pr-comment-resolver` agent (Task tool). The single source of truth
   for what is unresolved:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/get-pr-comments.sh" --pr <n> --unresolved-only --json
   ```

   For every unresolved thread: a code fix (then push) OR a reasoned
   reply — never a silent dismissal — then mark the thread resolved.
   Re-fetch after the pass. One fetch-resolve-refetch cycle is one
   iteration of counter B (`comment_resolution iteration <b>/5`). Loop
   until the script reports zero unresolved threads (degraded source:
   the agent reports `AI_REVIEW_VERDICT: PASS`), or counter B is
   exhausted → escalate.

   Pushes made while resolving comments can re-trigger CI: after
   counter B completes with new pushes, re-check `gh pr checks` once —
   on regression, re-enter the CI loop if counter A still has budget,
   otherwise escalate.

5. **Final status** — SUCCESS when checks are green (or CI was
   skipped-with-report) AND zero comments remain unresolved. If ANY
   degrade path was taken, the status is SUCCESS-WITH-REPORT and the
   summary lists every degrade note. Always print: PR URL, checks
   state, unresolved count, counters used (`A <a>/5`, `B <b>/5`),
   degrade notes.

## Loop & exit condition

Two independent loops, re-checked per their own iterations: counter A
re-polls checks, counter B re-fetches unresolved threads. Exit
condition (FR-1 stage table): **CI green + 0 unresolved AI review
comments** — where "CI green" is satisfied-with-report when no checks
exist, and the agent-run `ai-review-loop.sh` substitutes as the
comment source when no reviewer app exists (NFR-4).

## Iteration guard

TWO separate counters, `MAX_ITERATIONS=5` EACH: `ci_fix <a>/5` and
`comment_resolution <b>/5`. Restate the active counter every turn.
Budgets are independent — spending one never consumes the other, and
exhausting either one escalates.

## Failure escalation

On either counter breaching, emit the canonical report and stop;
`blocking_finding` names which loop breached:

```text
=== SDLC ESCALATION ===
stage: finish-pr         iteration: A <a>/5, B <b>/5
exit_condition: CI green + 0 unresolved AI review comments
status: NOT MET
blocking_finding: <which loop breached + first unresolved item>
iteration_log: <one line per iteration, both counters>
recommended_action: <human next step>
=== END ===
```
