# Degrade and Resilience

[Home](Home.md) › Operate › Degrade and Resilience

This page explains what the php-backend-sdlc plugin does when an external
capability is absent and how its safety mechanisms — guards, preflight, and
Ralph's circuit breaker — bound a run. The short version: capability gaps
**degrade with a recorded note** and the run still finishes; only guards,
breakers, and preflight produce a terminal `ESCALATED` or `HALTED` outcome.

The authoritative table is the
[degrade-matrix doc](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md);
this page summarizes it and links the related machinery.

## Degrade-first principle

A missing external capability never fails the run and never loops. This is
the governing rule (NFR-4) stated at the top of the
[degrade-matrix doc](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md):

> degrade paths never loop and never hard-fail the run — only guards,
> breakers, and preflight produce ESCALATED/HALTED.

Capability detection is data-driven: it reads the
[project profile](Project-Profile.md) at `.claude/php-sdlc.yml` rather than
probing for tools at runtime. Three profile signals drive the matrix:

- `make.<key>: null` — the logical Make target is absent. An explicit
  `null` means "capability absent"; omitting the key entirely is a
  validation error, because the plugin distinguishes "no such capability"
  from "forgot to declare it" (see
  [profile-schema](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md)).
- `ci.provider: null` — no CI provider; equivalently, zero checks on the
  PR.
- `review.coderabbit: false` — no third-party reviewer app.

For several null targets the plugin **substitutes its own bundled script**
rather than skipping the work entirely:

| Null target | Substituted by |
| --- | --- |
| `make.ai_review_loop` | `scripts/ai-review-loop.sh` |
| `make.pr_comments` | `scripts/get-pr-comments.sh` |
| `make.fr_nfr_gate` | `scripts/fr-nfr-gate.sh` |
| `make.post_review_findings` | `scripts/post-review-findings.sh` |
| `make.security` | bundled static lane (Psalm taint / Semgrep / `composer audit` / secret-scan) |

For targets with no substitute (for example `make.tests`, `make.psalm`,
`make.start`), the dependent check is recorded as absent and skipped with a
note — the plugin **never** falls back to a host-level `php`, `composer`,
or `vendor/bin/*` command (see [Architecture](Architecture.md) on the
container-only rule).

Two related uses of "degrade-first" appear elsewhere in the codebase but
are distinct from NFR-4. A missing capability never fails profile
generation — it becomes `null`/`false` (A3, NFR-4). NFR-3 is the separate
**idempotency / no-silent-overwrite** contract: with an existing profile,
`/sdlc-setup` (via `scripts/generate-profile.sh`) prints a unified diff
against the freshly detected profile and KEEPS the existing file; only
`--refresh` overwrites it. NFR-3 also gates the opt-in
`capabilities.dynamic_security_testing`
and `capabilities.publish_pr_comments` switches: when off, the dependent
behavior skips with a note (the static security lanes still run). See
[Security-Audit](Security-Audit.md) and
[Publishing-PR-Comments](Publishing-PR-Comments.md).

## The degrade matrix

Each row pairs a condition with the signal that detects it, the behavior,
and the resulting run-level status. This is a summary; the full table with
exact wording lives in the
[degrade-matrix doc](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md).

| Condition | Detected by | Behavior | Status |
| --- | --- | --- | --- |
| No CodeRabbit / reviewer app | `review.coderabbit: false` | `ai-review-loop.sh` becomes the comment source for stage 6 | SUCCESS-WITH-REPORT |
| Missing make target | profile `make.<key>: null` | skill/agent records "capability absent", skips that check | SUCCESS-WITH-REPORT |
| No CI workflows | `ci.provider: null` / zero checks on PR | ci-fixer skip-with-report | SUCCESS-WITH-REPORT |
| No dynamic security testing | `capabilities.dynamic_security_testing: false` or `make.start: null` | dynamic probing skips; static/SAST/dep/secret/config lanes still run | SUCCESS-WITH-REPORT |
| No black-box QA | `make.start: null` | `/sdlc-qa` finishes `PASS (SUCCESS-WITH-REPORT — black-box QA skipped)` | SUCCESS-WITH-REPORT |
| Ralph circuit breaker open | `---RALPH_STATUS---` / breaker files | stop stage 3, escalation report, never reset, honor cooldown | ESCALATED |
| Guard breach (any stage) | iteration counter = 5 | canonical escalation block, run halts | ESCALATED |
| Preflight FAIL / profile invalid | setup-preflight / validate-profile | abort before stage 1 with named remediation | HALTED |
| `claude -p` non-zero / malformed JSON | `ai-review-loop.sh` | retry once, then count as one failed iteration (never infinite) | per-loop |
| Permission denial mid-loop | non-interactive `claude` error output | surface verbatim in the escalation report; point to [Permissions](Permissions.md) | ESCALATED |

### Reading the status column

- **SUCCESS-WITH-REPORT** — the run continues and finishes; the final run
  report lists every degrade note taken along the way. These rows are
  capability gaps, not failures.
- **ESCALATED / HALTED** — terminal. The run report embeds the failing
  stage's escalation block (see [The SDLC Loop](The-SDLC-Loop.md)).
- **per-loop** — handled inside the owning loop's iteration budget,
  invisible at run level unless that budget is exhausted.

The boundary is deliberate: capability gaps (no CI, no reviewer app,
missing make targets, no dynamic testing) **do not** escalate. Only a
breached guard, a tripped breaker, or a failed preflight ends the run
without finishing.

## Circuit breakers and escalation blocks

Two independent safety nets bound a run. Either one tripping ends the
owning stage; they are never reset around.

### Stage iteration guards

Every loop-bearing stage carries `MAX_ITERATIONS=5`. The command keeps an
explicit counter and restates it each turn (for example
`implement iteration <n>/5`). Loop-backs **consume** the owning stage's
budget — counters are never reset. The seven-stage budget map is:

| Stage | Guard |
| --- | --- |
| 0 setup-check | halt → instruct `/sdlc-setup` (never auto-generate the profile in-loop) |
| 1 issue | 5 iterations |
| 2 plan | 5 iterations until readiness PASS |
| 3 implement | 5 iterations + Ralph circuit breaker |
| 4 review | 5 iterations until zero new findings |
| 5 qa | 5 iterations (FAIL routes back to stage 3) |
| 6 finish-pr | 5 iterations × two independent counters (CI fix, comment resolution) |

When a guard is breached the stage emits the canonical
`=== SDLC ESCALATION ===` block and the run ends as `ESCALATED`. See
[The SDLC Loop](The-SDLC-Loop.md) for the full stage diagram and
exit-condition table.

### Ralph's circuit breaker (stage 3)

Stage 3 (`/sdlc-implement`) runs the implementation loop through Ralph,
whose own circuit breaker is configured by `.ralphrc` in the target
repository and is **separate** from the stage iteration guard (NFR-6).
Source: [sdlc-implement.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc-implement.md).

The `.ralphrc` thresholds that trip the breaker are:

| Threshold | Trips after |
| --- | --- |
| no-progress | 3 loops |
| same-error | 5 loops |
| output-decline | output below 70% |

On a trip the command:

1. STOPs immediately.
2. Collects the last `---RALPH_STATUS---` block and the `.ralph/logs/`
   tail as evidence.
3. Emits the ESCALATED report (below).

A breaker trip is **terminal for the stage even on iteration 1** — it does
not consume the remaining stage iterations. Critically, the plugin
**never** resets, restarts around, or tampers with a tripped breaker: it is
a human-attention signal, and resetting it discards the diagnostic
evidence. The breaker also honors its cooldown.

### The canonical escalation block

Both a breaker trip and a guard breach emit the same shape so the run
report can embed it verbatim:

```text
=== SDLC ESCALATION ===
stage: implement         iteration: <n>/5
exit_condition: Ralph EXIT_SIGNAL success, all stories done
status: NOT MET
blocking_finding: <breaker trip reason, or the last RALPH_STATUS recommendation>
iteration_log: <one line per iteration>
recommended_action: <human next step — inspect .ralph/logs/ and the named blocker; never reset the breaker without diagnosing the cause>
=== END ===
```

A permission denial encountered mid-loop is surfaced verbatim inside this
block and routes the reader to [Permissions](Permissions.md) for the fix.

## See also

- [Architecture](Architecture.md) — where degrade-first, container-only,
  and no-suppression fit in the design.
- [Project-Profile](Project-Profile.md) — the `make`, `ci`, `review`, and
  `capabilities` keys that drive detection.
- [The-SDLC-Loop](The-SDLC-Loop.md) — stage diagram, guards, and terminal
  states.
- [Security-Audit](Security-Audit.md) — static-vs-dynamic lane degradation.
- [Permissions](Permissions.md) — resolving a mid-loop permission denial.
