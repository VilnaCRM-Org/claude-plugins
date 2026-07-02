# The SDLC Loop

How `/fe-sdlc` drives a task from text to finished PR: seven stages with
gated transitions, per-stage iteration guards, and exactly two terminal
states — SUCCESS or ESCALATED. Stage behavior is parameterized by the
[project profile](profile-schema.md), so the one loop runs unchanged
against a React SPA, a Next.js app, or a component library — every
concrete target, threshold, and capability is resolved through the
profile's `make.*` map, `quality.*` thresholds, and `capabilities.*`
flags rather than hardcoded.

## Stage diagram

```text
user: /fe-sdlc "task text | issue URL"
  └─ stage 0 setup-check ── validate-profile.sh + setup-preflight.sh ──[invalid]──► HALT: "run /fe-sdlc-setup"
  └─ stage 1 /fe-sdlc-issue ─────────────► artifact: issue URL (+ label react-frontend-sdlc)
  └─ stage 2 /fe-sdlc-plan (bmad-autonomous-planning) ─► artifact: specs/<slug>/{research,brief,prd,
        architecture,epics-stories,readiness}; loop <=5 until readiness PASS
  └─ stage 3 /fe-sdlc-implement ── bmalph implement → bmalph run --driver claude-code
        ├─ parallel react-implementer subagents (independent stories)
        ├─ artifact: fix-plan checkboxes + ---RALPH_STATUS--- (EXIT_SIGNAL)
        └─[circuit breaker open]──► ESCALATED report (never reset)                    ◄─┐
  └─ stage 4 /fe-sdlc-review ── triage 19 verdicts → code-quality-reviewer +            │
        fr-nfr-reviewer + accessibility-auditor (MANDATORY a11y gate) → fr-nfr-gate.sh; │
        loop <=5 until 0 new FR/NFR findings AND a11y gate clean AND quality PASS       │
        artifact: review report (19/19 verdicts, findings/iteration)                    │
  └─ stage 5 /fe-sdlc-qa ── qa-visual-tester (make.start_prod + Mockoon stack:          │
        Playwright E2E + visual regression + Lighthouse + axe-core a11y)                │
        artifact: QA report ──[FAIL + repro steps]── loop-back ──────────────────────────┘
  └─ stage 6 /fe-sdlc-finish-pr ── gh pr create/edit ─► artifact: PR URL
        ├─ ci-fixer loop <=5 (counter A) ──► checks green (or skip-with-report)
        ├─ pr-comment-resolver loop <=5 (counter B, get-pr-comments.sh) ──► 0 unresolved
        │     └─[no reviewer app]── ai-review-loop.sh findings as the comment source
        └─ exit: SUCCESS run report (issue, specs, PR, reports linked)
```

## Exit conditions and guards

A stage starts only when the previous stage's exit condition is
verifiably met — `/fe-sdlc` re-checks each condition itself (re-reads the
issue, re-checks `readiness.md`, re-runs the review/a11y gate, re-runs
`gh pr checks`) rather than trusting the stage's own success report.

| #   | Stage       | Exit condition                                                                   | Guard                                                                      |
| --- | ----------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| 0   | setup-check | valid `.claude/react-sdlc.yml`, preflight fresh                                  | halt → instruct `/fe-sdlc-setup` (never auto-generate the profile in-loop) |
| 1   | issue       | GitHub issue URL exists with testable AC + `react-frontend-sdlc` label           | 5 iterations                                                               |
| 2   | plan        | `specs/<slug>/` chain complete, readiness PASS                                   | 5 iterations                                                               |
| 3   | implement   | Ralph `EXIT_SIGNAL` success, all stories done                                    | 5 iterations + circuit breaker                                             |
| 4   | review      | zero new findings in last gate iteration AND a11y gate clean                     | 5 iterations                                                               |
| 5   | qa          | QA verdict PASS — visual + E2E + Lighthouse + a11y (FAIL routes back to stage 3) | 5 iterations                                                               |
| 6   | finish-pr   | CI green + 0 unresolved AI review comments                                       | 5 iterations (two independent counters: CI fix, comment resolution)        |

## Loop-backs

- QA FAIL → stage 3, with the QA report attached.
- Review-gate findings (an FR/NFR finding, a `code-quality-reviewer`
  threshold FAIL row, or an `accessibility-auditor` WCAG 2.2 AA
  violation) → fixed in-stage by a dispatched react-implementer,
  committed by the loop, then all three lenses re-run on the post-fix
  tree.
- finish-pr check/comment fixes → commit, push, re-poll.

Every loop-back CONSUMES the owning stage's 5-iteration budget —
counters are never reset. A guard breach emits the canonical
`=== SDLC ESCALATION ===` block and ends the run as ESCALATED.

## Per-stage iteration guard

Each stage owns a `MAX_ITERATIONS=5` counter, tracked for the whole run
and restated on every stage turn (`stage <name>, iteration <n>/5`).
There is no run-level cap beyond the per-stage guards; the stage budgets
bound the run. Two stages carry more than one counter:

- **implement** — the stage guard (at most five `bmalph run`
  attempts/resumes) plus Ralph's own circuit breaker; EITHER tripping
  ends the stage. A breaker trip is terminal even on iteration 1 and does
  NOT consume the remaining stage iterations.
- **finish-pr** — two independent `MAX_ITERATIONS=5` counters, CI-fix (A)
  and comment-resolution (B); spending one never consumes the other, and
  exhausting either escalates.

The QA→implement loop-back does not refresh stage 3's budget: the
re-entry consumes whatever iterations remain, and if stage 3 is already
exhausted the run ends ESCALATED.

## The escalation contract

Every stage emits the same canonical block on a guard breach, a blocking
finding, or the Ralph breaker trip; `/fe-sdlc` embeds it verbatim in the
final run report and ends the run ESCALATED:

```text
=== SDLC ESCALATION ===
stage: <stage name>       iteration: <n>/5
exit_condition: <the stage's exit condition>
status: NOT MET
blocking_finding: <one line — the first unresolved cause>
iteration_log: <one line per iteration>
recommended_action: <human next step>
=== END ===
```

Two invariants make the block non-negotiable. The accessibility gate is
mandatory: an `accessibility-auditor` WCAG 2.2 AA finding blocks the
stage-4 verdict exactly like an FR/NFR finding and never silently defers
to stage 5 QA. The Ralph circuit breaker is surfaced, never reset,
restarted around, or tampered with — a trip is a human-attention signal,
and resetting it discards the evidence.

## Resumability

On every invocation `/fe-sdlc` detects the current stage from durable
artifacts and resumes at the first stage (in order 0→6) whose exit
condition is not met; it never restarts a run from scratch. Stage-1
resume keys on the durable GitHub-side signal, not the transient
`ISSUE_URL:` stdout line (which does not survive across sessions):

```bash
gh issue list --state open --label react-frontend-sdlc \
  --json number,url,title,body --limit 100
```

If a managed issue already covers the task argument, the issue stage is
satisfied and the run skips to stage 2; stage 1 repeats the same dedup
search before creating, so no duplicate is opened even on a racing
re-run. Later stages are detected the same artifact-first way:
`specs/<slug>/` completeness and readiness PASS, Ralph's `EXIT_SIGNAL`
success, the zero-findings review/a11y-gate record, the QA verdict, and
PR/check/comment state. A review-clean run whose QA verdict is FAIL
resumes at stage 3 (loop-back) while stage 3 budget remains.

## Terminal states

- **SUCCESS** — stage 6's exit condition met (CI green + zero unresolved
  AI review comments); the run report links the issue, the specs chain,
  and the PR.
- **ESCALATED** — a guard breached, Ralph's circuit breaker tripped
  (never reset by the plugin), or setup-check failed. The run report
  embeds the failing stage's escalation block.

Capability gaps — no CI (`ci.provider: null`), no reviewer app, a `null`
`make.*` target, or a `false` capability flag such as
`capabilities.visual_testing`, `capabilities.lighthouse`, or
`capabilities.dynamic_a11y_testing` — do NOT escalate. They degrade the
dependent lane with a skip-with-report note; see the
[degrade matrix](degrade-matrix.md).
