---
description: "Implement the planned stories via bmalph/Ralph with the claude-code driver: parallel react-implementer dispatch, container-only execution, circuit-breaker safety"
argument-hint: "[slug | issue-URL]"
---

# /fe-sdlc-implement — planning artifacts → implemented stories (FR-5)

Stage 3 of the SDLC loop. Transitions the `/fe-sdlc-plan` artifacts into
Ralph format and drives the autonomous implementation loop until every
story is done — or a safety mechanism stops it.

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/fe-sdlc-setup`.
- The specs directory: derived from the argument, or the `SPECS_DIR:`
  line emitted by `/fe-sdlc-plan`. A bare `<slug>` resolves to
  `specs/<slug>/`; an issue-URL derives `<slug>` exactly as
  `/fe-sdlc-plan` does (kebab-case title prefixed with the issue
  number). It must hold the six-artifact chain and `readiness.md` must
  record PASS — a missing or FAIL readiness verdict is a blocking
  finding (route back to `/fe-sdlc-plan`, do not implement unready
  plans).
- Profile `make` map: the only sanctioned way to build/test
  (container-only rule).
- `.ralphrc` in the target repository: Ralph's circuit-breaker
  configuration.

## Procedure

1. **Transition the artifacts** — run `bmalph implement` to convert the
   `specs/<slug>/` chain into Ralph's working format (fix plan, prompt,
   specs). Surface any failure output verbatim and abort — never mask a
   failed transition (same A2 discipline as setup's bootstrap).
2. **Start the loop** — run:

   ```bash
   bmalph run --driver claude-code
   ```

   The driver is ALWAYS `claude-code` — never Codex, never any other
   driver, regardless of tool defaults or `.ralphrc` contents (FR-5).
3. **Story dispatch rule** — inside the loop:
   - Stories marked **independent** in `epics-stories.md` fan out to
     parallel `react-implementer` subagents (Task tool), one story per
     agent.
   - Stories marked **dependent** run sequentially in the order the
     artifact declares; a dependent story starts only after every
     prerequisite story is done.
4. **Container-only execution** — every `react-implementer` runs build,
   test, and quality commands exclusively through the profile `make`
   map (`make.build`, `make.lint`, `make.test_unit_client`, …); an
   ad-hoc command the map does not cover (a single test file, one `tsc`
   pass) stays inside the dev container via the agent's sanctioned
   `docker compose exec dev bun x <command>` escape hatch — never a
   substitute for a mapped target. A `make.<key>: null` entry means the
   capability is absent: record it and skip that check with a note
   (NFR-4) — never substitute a host command.
5. **Monitor progress** — Ralph tracks story checkboxes and emits
   `---RALPH_STATUS---` blocks. Watch for `EXIT_SIGNAL: true`
   (success) and for circuit-breaker trips.
6. **Circuit breaker (NFR-6)** — `.ralphrc` thresholds: no-progress
   after 3 loops, same-error after 5 loops, output-decline at 70%. On a
   trip: STOP immediately, collect the last `---RALPH_STATUS---` block
   and `.ralph/logs/` tail, and emit the ESCALATED report below. NEVER
   reset, restart around, or tamper with a tripped breaker — it is a
   human-attention signal, and resetting it discards the evidence.
7. **On success** — summarize implemented stories, commits, and test
   status, then hand off to `/fe-sdlc-review`.

## Loop & exit condition

Each stage iteration inspects Ralph's progress (fix-plan checkboxes,
latest `---RALPH_STATUS---` block). Exit condition (FR-1 stage table):
**Ralph `EXIT_SIGNAL` success, all stories done**.

## Iteration guard

`MAX_ITERATIONS=5` at the stage level — at most five
`bmalph run` attempts/resumes; keep an explicit counter and restate it
every turn (`implement iteration <n>/5`). Ralph's own circuit breaker
governs the inner loop independently: the stage guard and the breaker
are separate safety nets, and EITHER one tripping ends the stage. A
breaker trip is terminal for the stage even on iteration 1 — it does
not consume the remaining stage iterations.

## Failure escalation

On breaker trip or guard breach, emit the canonical report and stop:

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
