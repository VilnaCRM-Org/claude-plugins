---
description: "Ask the PR's AI reviewers (CodeRabbit, cubic) for a review or re-review by posting the exact mention each bot accepts, honouring CodeRabbit's one-review-per-hour cadence and reporting the reviewers no mention can reach (paused Qodo, status-check bots, oversized diffs)"
argument-hint: "[PR-number | PR-URL] [--full] [--force]"
allowed-tools: ["Bash", "Read"]
---

# /fe-sdlc-request-reviews — mention-driven AI review requests (FR-8 support)

Stage 6 support command. Automatic AI review is not reliable on every
repository: CodeRabbit's auto-review is often paused at the organization
level and skips drafts, cubic reviews only when asked, and Qodo stops
when its subscription lapses. This command posts the mention comment each
bot accepts, spaces CodeRabbit requests an hour apart, and names every
reviewer that a mention cannot reach so the run report never mistakes a
missing review for a clean one. Never post the mentions by hand from a
loop — the bundled script owns the cadence bookkeeping.

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/fe-sdlc-setup`.
- The PR: a `PR-number` or `PR-URL` argument, else the current branch's
  PR (`gh pr view`). No PR is a blocking finding — this command never
  creates one (that is `/fe-sdlc-finish-pr` step 1).
- Flags: `--full` asks CodeRabbit for a full re-review instead of the
  incremental one (use after a long gap or a dismissed review);
  `--force` posts inside the one-hour interval.
- Profile keys consumed: `review.coderabbit` (when `true`, CodeRabbit is
  in the default reviewer set; when `false`, request cubic only unless
  the PR history shows CodeRabbit comments), `make.pr_comments` (the
  thread listing used to pre-flight unresolved threads; the bundled
  `get-pr-comments.sh` substitutes when `null`), `ci.required_checks`
  (pre-flight: none of them may be failing).

## Procedure

1. **Pre-flight the PR** so the bots review the final diff:
   - `gh pr view <n> --json isDraft,mergeable,statusCheckRollup` — a
     `CONFLICTING` PR is a blocking finding (fix the conflict first); a
     failing check in `ci.required_checks` means wait, do not request; a
     draft is allowed (an explicit mention still runs) but is reported.
   - Unresolved threads from an earlier round must already carry a reply
     or a fix. List them with the target mapped by `make.pr_comments`
     (default substitution):

     ```bash
     "${CLAUDE_PLUGIN_ROOT}/scripts/get-pr-comments.sh" --pr <n> --unresolved-only
     ```

     Unanswered threads are not a blocking finding, but note their count in
     the report — CodeRabbit will not approve while they stay open.
2. **Plan before posting** with a dry run and read the plan lines:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/request-ai-reviews.sh" --pr <n> --dry-run
   ```

   `WOULD-POST:` lines are the mentions that will go out; `WAIT:` means the
   last CodeRabbit request is inside the interval; `SKIPPED:` names a
   reviewer no mention can reach, with the reason (paused subscription,
   diff above CodeRabbit's changed-file limit, status-check bot).
3. **Post** the plan (add `--full` / `--force` when the argument asked for
   them; add `--reviewers coderabbit` or `--reviewers cubic` to narrow):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/request-ai-reviews.sh" --pr <n>
   ```

   The script posts exactly `@coderabbitai review` (or
   `@coderabbitai full review`) and `@cubic-dev-ai review` as whole
   comments — text before a mention can stop the bot parsing it.
4. **Wait for the acknowledgement**, then for the review. Both bots reply
   within a minute ("Starting a review", "I have started the AI code
   review") and finish in two to five minutes. Let the bundled sensor do
   the polling — it classifies each reviewer against the current head and
   returns as soon as the verdict leaves `WAIT`:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/pr-state.sh" --pr <n> --wait-seconds 540
   ```

5. **Report**: one line per reviewer with its state (`requested`,
   `waiting <m>m`, `skipped — <reason>`, `reviewed`, `no response after
   <t>`), the draft flag, the unresolved-thread count, and — for a
   `SKIPPED` reviewer — the degrade note that the missing review is
   **not** a pass (NFR-4). When every mention-driven reviewer is skipped
   or silent, tell the caller to fall back to the reviewers that did run
   plus the plugin's own review loop (`/fe-sdlc-review`).
6. When several PRs need CodeRabbit in one session, request them one per
   hour: run step 3 for the first PR now and re-run this command for the
   next PR when the `WAIT:` line reaches zero. cubic has no such limit
   and may be requested on every PR at once.

## Loop & exit condition

One iteration = one plan → post → acknowledgement cycle for one PR. Exit
condition: **every requested reviewer has acknowledged, and every
non-requestable reviewer is reported with its reason**. A `WAIT:` line is
not a failure: report the minutes and stop; the caller re-runs after the
interval.

## Iteration guard

`MAX_ITERATIONS=5` acknowledgement polls per PR (one per minute). Restate
the counter every turn (`request-reviews iteration <n>/5`). A bot that has
not acknowledged after the fifth poll is reported as `no response` and
treated like a `SKIPPED` reviewer — never re-mentioned in a tight loop
(CodeRabbit queues repeated requests silently).

## Failure escalation

Escalate — emit the canonical report and stop — when no PR exists for the
branch, the PR is `CONFLICTING`, `gh` cannot post (`gh pr comment`
failure), or the guard is breached with a bot still silent:

```text
=== SDLC ESCALATION ===
stage: request-reviews   iteration: <n>/5
exit_condition: every requested reviewer acknowledged; non-requestable reviewers reported
status: NOT MET
blocking_finding: <no PR | CONFLICTING | gh pr comment failed: <mention> | <bot> silent after 5 polls>
iteration_log: <one line per poll>
recommended_action: <human next step — e.g. resolve the conflict, check the bot's app installation, fall back to /fe-sdlc-review>
=== END ===
```
