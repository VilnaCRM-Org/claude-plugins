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

1. **PR create/update** — first resolve the PR and its state with
   `gh pr view --json state,url,number` (or `gh pr view <pr-number>`
   when the argument is given):

   - **No PR for the branch** — create it: `gh pr create` with a
     spec-linked description: the issue URL, links to the `specs/<slug>/`
     artifacts, the implemented-stories summary, and the
     acceptance-criteria checklist. If `gh pr create` FAILS (gh
     unauthenticated/unavailable, no remote, branch not pushed, etc.),
     that is a blocking finding — escalate with the verbatim error and
     the named remediation (do NOT proceed to push to a branch with no
     PR).
   - **Open PR** — refresh the description with `gh pr edit` instead,
     then continue to step 2.
   - **MERGED or CLOSED PR** — a finished PR is a blocking finding:
     escalate immediately and do NOT edit the PR or push to its branch
     (the branch may be deleted, and editing/pushing a merged or closed
     PR has no defined bounded outcome). Tell the user the PR is already
     `<state>` and that finishing is complete or the PR must be reopened
     before re-running.

   Any blocking finding in this step emits the canonical escalation
   block below with `blocking_finding: PR <state>/create-failure` and
   stops — it never enters the counter-A or counter-B loops.

2. **CI fix loop — counter A** — degrade check first: if the profile's
   `ci.provider` is `null`, or the PR reports no checks at all, SKIP
   this loop with the note "CI stage skipped: no checks configured"
   and treat the CI half of the exit condition as satisfied-with-report
   (NFR-4 — a degrade path never loops and never hard-fails).

   Otherwise dispatch the `ci-fixer` agent (Task tool): it polls
   `gh pr checks`; for each failing check, fetches the failure logs
   (`gh run view --log-failed`), diagnoses the root cause, and fixes the
   CAUSE in the working tree — never suppressing findings, never editing
   quality thresholds (governance-protected). The agent runs NO git and
   returns exactly one of its four contract statuses
   (`ALL-GREEN | FIXES-READY | SKIPPED-NO-CI | BLOCKED`); handle each
   with a bounded outcome:

   - `ALL-GREEN` — nothing to fix; the CI half of the exit condition is
     satisfied. Leave counter A as-is and continue to step 3.
   - `FIXES-READY` — working-tree edits await commit/push. THE COMMAND
     commits the working-tree fixes and pushes, then re-polls
     `gh pr checks`. That command-owned commit-push-repoll is one
     iteration of counter A (`ci_fix iteration <a>/5`). Re-dispatch and
     loop until every check (at minimum the profile's
     `ci.required_checks`) is green, or counter A is exhausted →
     escalate.
   - `SKIPPED-NO-CI` — the agent hit the degrade path at dispatch time
     (the PR turned out to have zero checks even though `ci.provider`
     was non-null). Treat the CI half as satisfied-with-report exactly
     like the up-front degrade above, record the degrade note, and
     continue to step 3. Consumes no counter-A iteration.
   - `BLOCKED` — no progress is possible (e.g. `gh` unauthenticated, or
     no PR exists; see ci-fixer Degrade paths). This is NOT a counter-A
     breach and never loops: escalate immediately with the agent's
     verbatim blocking finding and its recommended action
     (`blocking_finding: ci-fixer BLOCKED — <reason>`). Do NOT commit or
     push on a `BLOCKED` return.

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
   `pr-comment-resolver` agent (Task tool). Its Task prompt must carry
   the PR number, the default branch name, the current counter-B
   iteration number (`comment_resolution iteration <b>/5` — this
   command owns counter B; the agent cannot derive `<b>` itself, and
   without it the agent's exhaustion escalation can never fire
   truthfully), and the comment source selected in step 3. Increment
   `<b>` in the prompt on every re-dispatch so the agent's counter
   resumes rather than resets. The single source of truth for what is
   unresolved:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/get-pr-comments.sh" --pr <n> --unresolved-only --json
   ```

   For every unresolved thread the agent applies a working-tree code fix
   OR posts a reasoned reply (via `gh`) — never a silent dismissal — then
   marks the thread resolved. The agent runs NO git: code fixes land in
   the working tree and its report flags `push required: yes`. When it
   returns with `push required: yes`, THE COMMAND commits the code fixes
   and pushes (replies are already posted by the agent via `gh` and need
   no push), then re-fetches. One command-owned
   resolve-commit-push-refetch cycle is one iteration of counter B
   (`comment_resolution iteration <b>/5`). Loop until the script reports
   zero unresolved threads (degraded source: the agent reports
   `AI_REVIEW_VERDICT: PASS`), or counter B is exhausted → escalate.

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

Escalate — emit the canonical report and stop — on ANY of: either
counter breaching; a step-1 PR-state/create blocking finding (merged,
closed, or `gh pr create` failure); or a `ci-fixer` `BLOCKED` return in
step 2. The escalation is identical in form for every case; the
`blocking_finding` line names the cause, and the `iteration` line
carries whatever counter values had been reached (both `0/5` for a
pre-loop step-1/step-2 block):

```text
=== SDLC ESCALATION ===
stage: finish-pr         iteration: A <a>/5, B <b>/5
exit_condition: CI green + 0 unresolved AI review comments
status: NOT MET
blocking_finding: <cause — which loop breached + first unresolved item, OR "PR <state>/create-failure", OR "ci-fixer BLOCKED — <reason>">
iteration_log: <one line per iteration, both counters>
recommended_action: <human next step>
=== END ===
```
