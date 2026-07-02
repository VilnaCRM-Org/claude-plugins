---
description: "Black-box frontend QA: boot the Mockoon-mocked production stack and verify every acceptance criterion through observed browser behavior — Playwright E2E, visual regression, Lighthouse budgets, and axe-core accessibility — emitting a PASS/FAIL report with reproduction steps"
argument-hint: "[slug | PR-URL]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]
---

# /fe-sdlc-qa — black-box visual + E2E + Lighthouse + a11y QA (FR-7)

Stage 5 of the SDLC loop. The `qa-visual-tester` agent exercises the
RUNNING app and verdicts come exclusively from observed browser
behavior — Playwright E2E flows, visual-regression diffs, Lighthouse
category scores, and axe-core findings — never from reading source
code. `allowed-tools` excludes Edit and Write (§5 black-box rule):
this command and its agent report, they never fix.

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/fe-sdlc-setup`.
- The acceptance criteria: from the issue (the `slug`'s linked issue,
  the `PR-URL` argument's linked issue, or the `ISSUE_URL:` line from
  stage 1) and `specs/<slug>/prd.md` — together the authoritative AC
  list. Enumerate them as AC-1…AC-n before any check runs.
- Profile `make.start_prod` — the only sanctioned way to boot the
  Mockoon-mocked production stack the browser lanes run against
  (container-only rule). E2E, visual, and Lighthouse all observe the
  production build served with the API mocked by Mockoon.
- Profile lane targets and their gates, all resolved before dispatch:
  `make.test_e2e`; `make.test_visual` (gated by
  `capabilities.visual_testing`, ceiling `quality.visual_diffs`);
  `make.lighthouse_desktop` / `make.lighthouse_mobile` (gated by
  `capabilities.lighthouse`, floors `quality.lighthouse_desktop` /
  `quality.lighthouse_mobile`); `make.a11y` (gated by
  `capabilities.dynamic_a11y_testing` for the live-browser axe-core run,
  with `capabilities.accessibility_audit` for the static fallback lane).

## Procedure

1. **Enumerate the acceptance criteria** — collect every AC from the
   issue and the PRD, number them, and resolve the app base URL (the
   production port mapped by the repo's compose/start configuration).
2. **Boot the Mockoon-mocked stack** — run the profile's
   `make.start_prod` target (it brings up the production build plus the
   Mockoon API mock the E2E/visual/Lighthouse lanes share). If
   `make.start_prod` is `null` (capability absent), do NOT hard-fail:
   record the degrade note and finish with the degrade verdict
   `PASS (SUCCESS-WITH-REPORT — black-box QA skipped, make.start_prod: null)`
   (NFR-4). This is the PASS branch of the report template's verdict
   enum, qualified with the degrade reason — the bare `PASS` token is
   what satisfies the orchestrator's stage-5 gate ("QA verdict PASS",
   fe-sdlc.md), while the parenthetical records that no checks actually
   ran. If the start target exists but the stack fails to come up, that
   is a blocking finding — escalate.
3. **Dispatch `qa-visual-tester`** (Task tool) with the AC list, the
   base URL, the lane targets and their gates, the report contract, and
   the current QA iteration number from this command's iteration guard —
   on a re-dispatch after an implement-stage fix round also attach the
   prior iteration ledger, so the agent's counter resumes rather than
   resets (subagents are stateless across dispatches). Restate the
   agent's rules in the dispatch prompt:
   - Verdicts from observed browser behavior ONLY (Playwright E2E,
     visual diffs, Lighthouse scores, axe-core results). No source
     reading for verdicts — Read is limited to logs, specs, and lane
     reports (prompt-level rule; tool frontmatter cannot path-restrict
     Read).
   - Report-only: no Edit, no Write, no fixes.
   - Every AC gets ≥1 executed E2E check located by user-facing
     semantics (`getByRole` / `getByLabelText` / `getByText`, never
     `data-testid`); across the run, cover positive (happy path),
     negative (invalid input, error handling), and edge cases
     (boundaries, empty/oversized payloads).
   - Run each enabled quality lane and gate its result: visual
     regression passes only at `quality.visual_diffs` (ceiling 0);
     Lighthouse desktop/mobile pass only at or above
     `quality.lighthouse_desktop` / `quality.lighthouse_mobile`;
     axe-core passes only at zero violations. A capability that is
     `false`/absent (or whose `make.*` target is `null`) makes its lane
     SKIPPED-with-note — never a silent pass, never a FAIL. The a11y
     lane never skips straight to that: when the live axe-core run is
     unavailable (`capabilities.dynamic_a11y_testing` false or
     `make.a11y` null) it falls back to the static a11y lane when
     `capabilities.accessibility_audit` is true; only with that flag
     also false/absent is the lane SKIPPED-with-note — the documented
     not-opted-in degrade, never an invented or relaxed threshold.
   - Every check records: the exact interaction issued (spec path +
     Playwright invocation, or lane command), expected behavior,
     observed behavior, verdict.
   - Every FAIL records minimal reproduction steps — the exact commands
     a human can replay against a freshly booted stack.
4. **Assemble the report** from the template below. The stage verdict is
   PASS only when every AC's checks pass AND every enabled lane meets
   its gate.
5. **On FAIL** — route back to `/fe-sdlc-implement` with the full report
   attached (inside `/fe-sdlc` this loop-back consumes stage budget per
   FR-1). Standalone: print the report and instruct the user to re-run
   `/fe-sdlc-implement` with it.

### Report template

```text
# QA Report — <slug>, iteration <n>/5
stack: make.start_prod = <target>, base URL = <url>

## Checks (every AC maps to >=1 executed check)
| AC | kind | interaction | expected | observed | verdict |
|---|---|---|---|---|---|
| AC-<n> | positive/negative/edge | <spec path + Playwright invocation> | <expected> | <observed> | PASS/FAIL |

## Quality lanes
| lane | target | gate | result | verdict |
|---|---|---|---|---|
| visual | make.test_visual | <= quality.visual_diffs | <diff count> | PASS/FAIL/SKIPPED |
| lighthouse-desktop | make.lighthouse_desktop | >= quality.lighthouse_desktop | <score> | PASS/FAIL/SKIPPED |
| lighthouse-mobile | make.lighthouse_mobile | >= quality.lighthouse_mobile | <score> | PASS/FAIL/SKIPPED |
| a11y (axe-core) | make.a11y | 0 violations | <violation count> | PASS/FAIL/SKIPPED |

## Failures and reproduction steps
### AC-<n> — FAIL
reproduction:
  1. <exact command>
  2. <exact command>
expected: <...>   observed: <...>

## Verdict: PASS | FAIL
# The make.start_prod:null degrade (step 2) is the PASS branch, written
# `PASS (SUCCESS-WITH-REPORT — black-box QA skipped, make.start_prod: null)`:
# the leading `PASS` token satisfies the stage-5 gate, the parenthetical
# records that no checks ran. A SKIPPED lane (capability off / target null)
# is likewise neutral. FAIL is reserved for an executed-and-failed check,
# a lane that missed its gate, or a boot failure (those escalate / route
# back to stage 3).
```

## Loop & exit condition

Each iteration is one full QA pass over the enumerated AC list and the
enabled quality lanes against a freshly booted Mockoon-mocked stack
(after a `/fe-sdlc-implement` fix round when routed back). Exit
condition (FR-1 stage table): **QA verdict PASS (FAIL routes back to
stage 3)**.

## Iteration guard

`MAX_ITERATIONS=5`. Keep an explicit counter and restate it every turn
(`qa iteration <n>/5`). The implement-stage fix rounds triggered by
FAIL verdicts are budgeted by their own stage guard — this counter
bounds QA passes only.

## Failure escalation

On guard breach or a blocking finding (stack will not boot, base URL
unreachable), emit the canonical report with the QA report attached:

```text
=== SDLC ESCALATION ===
stage: qa                iteration: <n>/5
exit_condition: QA verdict PASS (FAIL routes back to stage 3)
status: NOT MET
blocking_finding: <one line — e.g. first failing AC, lane gate miss, or boot failure>
iteration_log: <one line per iteration: checks run / lanes / failures>
recommended_action: <human next step>
=== END ===
```
