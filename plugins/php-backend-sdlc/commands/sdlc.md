---
description: "Run the full SDLC loop end-to-end: setup-check, issue, plan, implement, review, qa, finish-pr — gated transitions, resumable, loop-safe"
argument-hint: "[task-description | issue-URL]"
---

# /sdlc — end-to-end orchestrator (FR-1)

Drives the full stage sequence with gated transitions: a stage starts
only when the prior stage's exit condition is verifiably met. The run
is resumable (stage detected from artifacts, never restarted from
scratch), every stage is bounded by its own 5-iteration guard, and the
run always ends in one of exactly two states — SUCCESS or ESCALATED —
each with the structured run report below.

## Inputs

- The argument: a task description (a few sentences) or an existing
  issue URL — handed to stage 1 unchanged.
- Stage 0 IS the profile/preflight validation, so it is this command's
  first action (the "validate-profile first" rule, fulfilled by the
  stage itself).

## Procedure

### Stage table (FR-1)

| # | Stage | Delegates to | Exit condition | Guard |
| --- | --- | --- | --- | --- |
| 0 | setup-check | profile + preflight validation | valid `.claude/php-sdlc.yml`, preflight fresh | halt → instruct `/sdlc-setup` (never auto-generate profile in-loop) |
| 1 | issue | `/sdlc-issue` | GitHub issue URL exists with testable AC | 5 iterations |
| 2 | plan | `/sdlc-plan` | `specs/` chain complete, readiness PASS | 5 iterations |
| 3 | implement | `/sdlc-implement` | Ralph `EXIT_SIGNAL` success, all stories done | 5 iterations + circuit breaker |
| 4 | review | `/sdlc-review` | zero new findings in last gate iteration | 5 iterations |
| 5 | qa | `/sdlc-qa` | QA verdict PASS (FAIL routes back to stage 3) | 5 iterations |
| 6 | finish-pr | `/sdlc-finish-pr` | CI green + 0 unresolved AI review comments | 5 iterations |

### Resumability — artifact → stage detection

On every invocation, FIRST detect the current stage instead of
restarting: resume at the first stage (in order 0→6) whose exit
condition is not yet met.

| Observed state | Resume at |
| --- | --- |
| profile invalid/missing or preflight stale | stage 0 → HALT: "run `/sdlc-setup`" |
| no open issue for the task (no `ISSUE_URL` artifact) | stage 1 |
| issue exists; `specs/<slug>/` incomplete or readiness not PASS | stage 2 |
| readiness PASS; stories not all done (no Ralph `EXIT_SIGNAL` success) | stage 3 |
| stories done; no zero-findings review-gate record | stage 4 |
| review clean; QA verdict absent | stage 5 |
| review clean; QA verdict FAIL (loop-back, stage 3 budget remaining) | stage 3 |
| QA PASS; PR missing, checks not green, or comments unresolved | stage 6 |
| finish-pr exit condition met | nothing to do → SUCCESS report |

### Stage 0 — setup-check

Run `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"` and
`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-preflight.sh"`. Either failing
HALTS the run with the instruction to run `/sdlc-setup`. This command
NEVER generates or regenerates the profile itself — setup is a human
decision point (FR-1).

### Stages 1–6 — gated delegation

For each stage in order, starting at the detected resume point:

1. Announce the stage and its guard counter (`stage <name>,
   iteration <n>/5`).
2. Execute the stage by following the named command's full procedure
   (its own Inputs/Procedure/Loop/Guard/Escalation contract applies
   inside the stage).
3. **Gate check**: after the stage reports done, VERIFY its exit
   condition independently (e.g. re-read the issue, re-check
   `readiness.md`, re-run `gh pr checks`) — a stage's own success claim
   is not the gate; the verified condition is.
4. Only then start the next stage. On verification failure, the stage
   is not done: consume one more of its iterations or escalate at the
   guard.

### QA loop-back rule

A stage-5 FAIL verdict routes back to stage 3 with the QA report
attached. The re-entry CONSUMES stage 3's remaining iteration budget —
counters are never reset by loop-backs. If stage 3's budget is already
exhausted, the run ends ESCALATED.

### Ralph circuit breaker

A breaker trip inside stage 3 is terminal for the run: emit the
ESCALATED report immediately. NEVER reset, restart around, or tamper
with the breaker (NFR-6) — surface it.

## Loop & exit condition

The run loops over stages with gated transitions as above. Run-level
exit condition: **finish-pr exit condition met** — stage 6's
"CI green + 0 unresolved AI review comments" — then SUCCESS. The only
other terminal state is ESCALATED (guard breach, breaker trip, or
unmet setup-check). Both produce the final run report.

## Iteration guard

Each stage keeps its OWN `MAX_ITERATIONS=5` counter, tracked for the
whole run and restated on every stage turn. Counters survive
loop-backs (the QA→implement route does not refresh stage 3's budget).
There is no run-level iteration cap beyond the per-stage guards — the
stage budgets bound the run.

## Failure escalation

On any guard breach, breaker trip, or setup-check halt, emit the
canonical stage escalation block (from the failing stage) followed by
the final run report with `result: ESCALATED`.

### Final run report (both exit paths)

```text
=== SDLC RUN REPORT ===
task: <task text or issue URL>
result: SUCCESS | ESCALATED
stages:
| stage | iterations used | exit condition | met |
|---|---|---|---|
| setup-check | - | valid profile, preflight fresh | yes/no |
| issue | <n>/5 | GitHub issue URL exists with testable AC | yes/no |
| plan | <n>/5 | specs/ chain complete, readiness PASS | yes/no |
| implement | <n>/5 (+breaker state) | Ralph EXIT_SIGNAL success, all stories done | yes/no |
| review | <n>/5 | zero new findings in last gate iteration | yes/no |
| qa | <n>/5 (loop-backs: <k>) | QA verdict PASS | yes/no |
| finish-pr | A <a>/5, B <b>/5 | CI green + 0 unresolved AI review comments | yes/no |
artifacts: <issue URL> | <SPECS_DIR> | <PR URL>
degrade_notes: <every NFR-4 note collected across stages, or none>
escalation: <the failing stage's === SDLC ESCALATION === block, when ESCALATED>
=== END ===
```
