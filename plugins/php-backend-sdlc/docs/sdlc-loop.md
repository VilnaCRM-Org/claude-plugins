# The SDLC Loop

How `/sdlc` drives a task from text to finished PR: seven stages with
gated transitions, per-stage iteration guards, and exactly two terminal
states — SUCCESS or ESCALATED. Stage behavior is parameterized by the
[project profile](profile-schema.md).

## Stage diagram

```text
user: /sdlc "task text"
  └─ stage 0 setup-check ── validate-profile.sh + preflight ──[invalid]──► HALT: "run /sdlc-setup"
  └─ stage 1 /sdlc-issue ──────────────► artifact: issue URL (+label)
  └─ stage 2 /sdlc-plan (bmad-autonomous-planning) ─► artifact: specs/<slug>/{research,brief,prd,
        architecture,epics-stories,readiness}; loop <=5 until readiness PASS
  └─ stage 3 /sdlc-implement ── bmalph implement → bmalph run --driver claude-code
        ├─ parallel php-implementer subagents (independent stories)
        ├─ artifact: fix_plan.md checkboxes + ---RALPH_STATUS--- (EXIT_SIGNAL)
        └─[circuit breaker open]──► ESCALATED report (never reset)            ◄─┐
  └─ stage 4 /sdlc-review ── triage 21 verdicts → code-quality-reviewer +       │
        fr-nfr-reviewer → fr-nfr-gate.sh; loop <=5 until 0 new findings         │
        artifact: review report (verdicts, findings/iteration)                  │
  └─ stage 5 /sdlc-qa ── qa-manual-tester (make start + HTTP)                   │
        artifact: QA report ──[FAIL + repro steps]── loop-back ─────────────────┘
  └─ stage 6 /sdlc-finish-pr ── gh pr create/edit ─► artifact: PR URL
        ├─ ci-fixer loop <=5 ──► checks green (or skip-with-report)
        ├─ pr-comment-resolver loop <=5 (get-pr-comments.sh) ──► 0 unresolved
        │     └─[no reviewer app]── ai-review-loop.sh findings as source
        └─ exit: SUCCESS run report (issue, specs, PR, reports linked)
```

## Exit conditions and guards

A stage starts only when the previous stage's exit condition is
verifiably met — `/sdlc` re-checks each condition itself rather than
trusting the stage's own report.

| # | Stage | Exit condition | Guard |
| --- | --- | --- | --- |
| 0 | setup-check | valid `.claude/php-sdlc.yml`, preflight fresh | halt → instruct `/sdlc-setup` (never auto-generate the profile in-loop) |
| 1 | issue | GitHub issue URL exists with testable AC | 5 iterations |
| 2 | plan | `specs/` chain complete, readiness PASS | 5 iterations |
| 3 | implement | Ralph `EXIT_SIGNAL` success, all stories done | 5 iterations + circuit breaker |
| 4 | review | zero new findings in last gate iteration | 5 iterations |
| 5 | qa | QA verdict PASS (FAIL routes back to stage 3) | 5 iterations |
| 6 | finish-pr | CI green + 0 unresolved AI review comments | 5 iterations (two independent counters: CI fix, comment resolution) |

## Loop-backs

- QA FAIL → stage 3, with the QA report attached.
- Review-gate findings → fixed in-stage (a dispatched implementer),
  then the gate re-runs.
- finish-pr check/comment fixes → commit, push, re-poll.

Every loop-back CONSUMES the owning stage's 5-iteration budget —
counters are never reset. A guard breach emits the canonical
`=== SDLC ESCALATION ===` block and ends the run as ESCALATED.

## Resumability

On every invocation `/sdlc` detects the current stage from artifacts
(issue URL, `specs/<slug>/` completeness, Ralph status, review/QA
reports, PR state) and resumes at the first stage whose exit condition
is not met. It never restarts a run from scratch.

## Terminal states

- **SUCCESS** — stage 6's exit condition met; the run report links the
  issue, the specs chain, and the PR.
- **ESCALATED** — a guard breached, Ralph's circuit breaker tripped
  (never reset by the plugin), or setup-check failed. The run report
  embeds the failing stage's escalation block.

Capability gaps (no CI, no reviewer app, missing make targets) do NOT
escalate — they degrade with a report; see the
[degrade matrix](degrade-matrix.md).
