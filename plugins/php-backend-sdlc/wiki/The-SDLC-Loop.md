# The SDLC Loop

[Home](Home.md) › Deep dives › The SDLC Loop

How `/sdlc` drives a task from free text to a finished pull request:
seven stages with gated transitions, a per-stage iteration guard, two
documented loop-backs, and exactly two terminal states — SUCCESS or
ESCALATED. Stage behavior is parameterized by the
[project profile](Project-Profile.md); the orchestrator contract lives in
[`commands/sdlc.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc.md)
and the reference doc
[`docs/sdlc-loop.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/sdlc-loop.md).

## Stage diagram

The loop runs stages 0 through 6 in order. Stage 0 validates the
environment; stages 1–6 each delegate to a dedicated command and are
re-gated by `/sdlc` itself before the next stage starts.

```text
user: /sdlc "task text"
  stage 0 setup-check    validate-profile.sh + setup-preflight.sh
        └─[invalid/stale]──► HALT: "run /sdlc-setup"
  stage 1 /sdlc-issue    ──► artifact: issue URL (+ php-backend-sdlc label)
  stage 2 /sdlc-plan     ──► specs/<slug>/{research,brief,prd,
        architecture,epics-stories,readiness}; loop ≤5 until readiness PASS
  stage 3 /sdlc-implement  bmalph implement → bmalph run --driver claude-code
        ├─ parallel php-implementer subagents (independent stories)        ◄─┐
        ├─ artifact: fix_plan.md checkboxes + ---RALPH_STATUS--- EXIT_SIGNAL │
        └─[circuit breaker open]──► ESCALATED report (never reset)           │
  stage 4 /sdlc-review   22-skill triage → code-quality-reviewer +          │
        fr-nfr-reviewer → gate; loop ≤5 until BOTH lenses clean             │
  stage 5 /sdlc-qa       qa-manual-tester (make.start + HTTP-only)          │
        └─[FAIL + repro steps]── loop-back to stage 3 ─────────────────────┘
  stage 6 /sdlc-finish-pr  gh pr create/edit ──► artifact: PR URL
        ├─ ci-fixer        loop ≤5 (counter A) ──► checks green (or skip-report)
        ├─ pr-comment-resolver loop ≤5 (counter B) ──► 0 unresolved
        │     └─[no reviewer app]── ai-review-loop.sh findings as source
        └─ exit: SUCCESS run report (issue, specs, PR, reports linked)
```

The exact diagram and terminal-state semantics are in
[`docs/sdlc-loop.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/sdlc-loop.md).

## Per-stage contract

Each stage has an entry action, a single exit condition, an iteration
guard, and a loop-back target. The columns below are taken verbatim from
the stage table in
[`commands/sdlc.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc.md)
and the individual stage commands.

| # | Stage | Delegates to | Exit condition | Guard |
| --- | --- | --- | --- | --- |
| 0 | setup-check | profile + preflight validation | valid `.claude/php-sdlc.yml`, preflight fresh | halt → instruct `/sdlc-setup` (never auto-generate in-loop) |
| 1 | issue | `/sdlc-issue` | GitHub issue URL exists with testable AC | 5 iterations |
| 2 | plan | `/sdlc-plan` | `specs/` chain complete, readiness PASS | 5 iterations |
| 3 | implement | `/sdlc-implement` | Ralph `EXIT_SIGNAL` success, all stories done | 5 iterations + circuit breaker |
| 4 | review | `/sdlc-review` | zero new findings in last gate iteration (both lenses clean) | 5 iterations |
| 5 | qa | `/sdlc-qa` | QA verdict PASS (FAIL routes back to stage 3) | 5 iterations |
| 6 | finish-pr | `/sdlc-finish-pr` | CI green + 0 unresolved AI review comments | 5 iterations each, two independent counters |

The remaining sub-sections expand entry, exit, guard, and loop-back per
stage.

### Stage 0 — setup-check

- **Entry**: `/sdlc`'s first action. Runs
  `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"` and
  `"${CLAUDE_PLUGIN_ROOT}/scripts/setup-preflight.sh"`.
- **Exit**: a valid `.claude/php-sdlc.yml` profile and a fresh preflight.
- **Guard**: none — this is a one-shot precondition, not a loop.
- **Loop-back / failure**: either script failing HALTS the run with the
  instruction to run [`/sdlc-setup`](Commands.md). `/sdlc` **never**
  generates or regenerates the profile itself — setup is a human decision
  point. See [Getting Started](Getting-Started.md) and the
  [setup walkthrough](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/setup-walkthrough.md).

### Stage 1 — issue

- **Entry**: the task argument, unchanged. The command first runs the
  durable dedup search
  (`gh issue list --state open --label php-backend-sdlc`) so a
  cross-session resume cannot open a duplicate.
- **Exit**: a GitHub issue URL exists with ≥3 testable acceptance-criteria
  bullets and the `php-backend-sdlc` marker label attached.
- **Guard**: `MAX_ITERATIONS=5`; one iteration is one
  draft → create/amend → verify cycle.
- **Loop-back**: none upstream. A blocking finding (e.g. an adopted issue
  that is closed, or `gh` cannot create the issue) escalates.

### Stage 2 — plan

- **Entry**: the `ISSUE_URL:` from stage 1 (or the URL argument). Resolves
  the issue, derives the kebab-case `<slug>` (prefixed with the issue
  number), and direct-loads the
  [`bmad-autonomous-planning`](Skills.md) skill.
- **Exit**: the six-artifact chain under `specs/<slug>/` is complete
  (`research`, `brief`, `prd`, `architecture`, `epics-stories`,
  `readiness`) and `readiness.md` records PASS.
- **Guard**: `MAX_ITERATIONS=5`; one iteration is a correction pass over
  the artifacts named by readiness findings plus a readiness re-run.
- **Loop-back**: a FAIL readiness verdict loops in-stage (correct → re-run
  readiness). The chain is fully non-interactive — open questions are
  resolved as recorded `> Assumption:` lines, never prompts.

### Stage 3 — implement

- **Entry**: the `SPECS_DIR:` from stage 2. A missing or FAIL
  `readiness.md` is a blocking finding (route back to `/sdlc-plan`, never
  implement an unready plan). Runs `bmalph implement` to transition the
  spec chain, then `bmalph run --driver claude-code` (the driver is
  **always** `claude-code`).
- **Exit**: Ralph `EXIT_SIGNAL: true` and all stories done.
- **Guard**: two independent safety nets — `MAX_ITERATIONS=5` at the stage
  level (at most five `bmalph run` attempts/resumes) **and** Ralph's own
  circuit breaker governing the inner loop. Either tripping ends the
  stage. A breaker trip is terminal even on iteration 1 and does **not**
  consume the remaining stage iterations.
- **Loop-back**: this stage is the loop-back target for stage 5 (QA FAIL).
  Stories marked **independent** in `epics-stories.md` fan out to parallel
  [`php-implementer`](Agents.md) subagents; **dependent** stories run
  sequentially in declared order. All build/test/quality work goes through
  the profile `make` map (container-only). See
  [Architecture](Architecture.md).

### Stage 4 — review

- **Entry**: the working branch diff against the default branch, plus the
  `specs/<slug>/` chain for FR/NFR traceability. Records an applicability
  verdict (`EXECUTE` / `NOT-APPLICABLE`) for all 22 shipped skills before
  any skill body loads (token bound), then dispatches two reviewer agents
  in parallel.
- **Exit**: BOTH lenses clean in the last iteration —
  [`fr-nfr-reviewer`](Agents.md) reports `new_findings=0 verdict=PASS`
  AND every non-SKIPPED [`code-quality-reviewer`](Agents.md) threshold row
  PASS (phpinsights, deptrac, psalm, infection against the profile
  `quality.*` floors).
- **Guard**: `MAX_ITERATIONS=5`; one iteration is one parallel
  re-invocation of both reviewers (exactly one gate run) preceded by a
  remediation dispatch and its commit.
- **Loop-back**: findings from either lens are fixed in-stage by a
  dispatched `php-implementer`, committed by the command, then the gate
  re-runs. An `fr-nfr-reviewer` `verdict=DEGRADED` (spec bundle
  missing/empty) is a blocking finding, not a loop state — escalate with
  `recommended_action` "re-run /sdlc-plan". See
  [Review and Quality Gates](Review-and-Quality-Gates.md).

### Stage 5 — qa

- **Entry**: the authoritative AC list from the issue and
  `specs/<slug>/prd.md`, enumerated AC-1…AC-n. Boots the service through
  the profile's `make.start` only (container-only), then dispatches
  [`qa-manual-tester`](Agents.md).
- **Exit**: QA verdict PASS — every AC's checks pass. Verdicts come
  exclusively from observed HTTP/API behavior (`curl` and friends); source
  is never read for a verdict.
- **Guard**: `MAX_ITERATIONS=5`; one iteration is a full QA pass over the
  AC list against a freshly booted service.
- **Loop-back**: a FAIL verdict routes back to **stage 3** with the QA
  report attached. A `make.start: null` capability gap does **not** fail —
  it produces the degrade verdict
  `PASS (SUCCESS-WITH-REPORT — black-box QA skipped, make.start: null)`,
  whose leading `PASS` token satisfies the stage-5 gate. A boot failure on
  an existing start target escalates. See
  [Degrade and Resilience](Degrade-and-Resilience.md).

### Stage 6 — finish-pr

- **Entry**: the PR (argument, current-branch PR, or created here). A
  MERGED or CLOSED PR, or a `gh pr create` failure, is a blocking finding
  that escalates before either loop starts.
- **Exit**: CI green (or skipped-with-report when no checks exist) AND zero
  unresolved AI review comments.
- **Guard**: **two** independent `MAX_ITERATIONS=5` counters —
  `ci_fix <a>/5` (counter A) and `comment_resolution <b>/5` (counter B).
  Spending one never consumes the other; exhausting either escalates.
- **Loop-back**: counter A drives [`ci-fixer`](Agents.md)
  (commit → push → re-poll `gh pr checks`); counter B drives
  [`pr-comment-resolver`](Agents.md)
  (resolve → commit → push → re-fetch via `get-pr-comments.sh`). Pushes
  during counter B can re-trigger CI — after counter B the command
  re-checks `gh pr checks` once and re-enters counter A if budget remains.
  When no reviewer app exists, `pr-comment-resolver` runs
  `ai-review-loop.sh` as the degraded comment source. See
  [Publishing PR Comments](Publishing-PR-Comments.md).

## Resumability and gated transitions

`/sdlc` is resumable. On every invocation it **first detects the current
stage from durable artifacts** and resumes at the first stage (in order
0→6) whose exit condition is not yet met — it never restarts a run from
scratch.

| Observed state | Resume at |
| --- | --- |
| profile invalid/missing or preflight stale | stage 0 → HALT |
| no managed open issue matching the task | stage 1 |
| issue exists; `specs/<slug>/` incomplete or readiness not PASS | stage 2 |
| readiness PASS; stories not all done (no Ralph `EXIT_SIGNAL` success) | stage 3 |
| stories done; no zero-findings review-gate record | stage 4 |
| review clean; QA verdict absent | stage 5 |
| review clean; QA verdict FAIL (loop-back, stage 3 budget remaining) | stage 3 |
| QA PASS; PR missing, checks not green, or comments unresolved | stage 6 |
| finish-pr exit condition met | nothing to do → SUCCESS report |

Issue detection is deliberately **durable**: stage-1 resume must not key
on the transient `ISSUE_URL:` stdout line (it does not survive across
sessions). Instead it queries the GitHub-side label, so a racing re-run
cannot open a duplicate.

Transitions are **gated**: a stage starts only when the previous stage's
exit condition is independently verified. After a stage reports done,
`/sdlc` re-checks the condition itself — re-reading the issue, re-checking
`readiness.md`, re-running `gh pr checks` — because the stage's own success
claim is not the gate; the verified condition is. On verification failure,
the stage is not done: it consumes one more iteration or escalates at the
guard.

### Iteration guard and loop-back accounting

Each stage keeps its **own** `MAX_ITERATIONS=5` counter, tracked for the
whole run and restated on every stage turn (`stage <name>, iteration
<n>/5`). There is no run-level iteration cap beyond the per-stage guards.

Crucially, **loop-backs consume the owning stage's budget — counters are
never reset**. A stage-5 QA FAIL re-entering stage 3 spends stage 3's
remaining iterations; if stage 3's budget is already exhausted, the run
ends ESCALATED. The two documented loop-backs are:

| Loop-back | Trigger | Target | Budget consumed |
| --- | --- | --- | --- |
| QA FAIL | stage 5 verdict FAIL (with repro steps) | stage 3 | stage 3's remaining iterations |
| Review-gate findings | stage 4 findings from either lens | in-stage (dispatched implementer, then gate re-run) | stage 4's iterations |
| finish-pr fixes | CI failure / unresolved comment | in-stage (counter A or B) | the active counter |

## Circuit breakers

Two distinct safety mechanisms bound the loop; they are independent of
the per-stage iteration guards.

- **Ralph circuit breaker (stage 3, NFR-6)** — configured in `.ralphrc`
  with these thresholds: no-progress after 3 loops, same-error after 5
  loops, output-decline at 70%. On a trip the stage STOPs immediately,
  collects the last `---RALPH_STATUS---` block and the `.ralph/logs/`
  tail, and emits the ESCALATED report. The plugin **never** resets,
  restarts around, or tampers with a tripped breaker — it is a
  human-attention signal, and resetting it would discard the evidence. A
  breaker trip is terminal for the whole run, even on iteration 1.
- **Per-stage iteration guard** — the `MAX_ITERATIONS=5` counter above.
  A guard breach emits the canonical `=== SDLC ESCALATION ===` block from
  the failing stage and ends the run as ESCALATED.

### Terminal states

A run ends in exactly one of two states, each producing the final
`=== SDLC RUN REPORT ===` (issue, specs chain, and PR linked):

- **SUCCESS** — stage 6's exit condition met (CI green + 0 unresolved AI
  review comments).
- **ESCALATED** — a guard breached, Ralph's breaker tripped (never reset),
  or setup-check failed. The run report embeds the failing stage's
  escalation block.

Capability gaps — no CI, no reviewer app, missing `make` targets — do
**not** escalate. They degrade with a note and continue
(SUCCESS-WITH-REPORT). Only guards, breakers, and preflight produce a
terminal failure. The full mapping is in
[Degrade and Resilience](Degrade-and-Resilience.md) and the
[degrade matrix](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md).

## See also

- [Commands](Commands.md)
- [Agents](Agents.md)
- [Review and Quality Gates](Review-and-Quality-Gates.md)
- [Degrade and Resilience](Degrade-and-Resilience.md)
- [Architecture](Architecture.md)
