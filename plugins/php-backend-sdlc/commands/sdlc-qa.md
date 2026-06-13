---
description: "Black-box QA: boot the service and verify every acceptance criterion through HTTP-only checks, emitting a PASS/FAIL report with reproduction steps"
argument-hint: "[issue-URL | specs-dir]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]
---

# /sdlc-qa — black-box verification (FR-7)

Stage 5 of the SDLC loop. The `qa-manual-tester` agent exercises the
RUNNING service and verdicts come exclusively from observed HTTP
behavior — never from reading source code. `allowed-tools` excludes
Edit and Write (§2 black-box rule): this command and its agent report,
they never fix.

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/sdlc-setup`.
- The acceptance criteria: from the issue (URL argument, or the
  `ISSUE_URL:` line from stage 1) and `specs/<slug>/prd.md` — together
  the authoritative AC list. Enumerate them as AC-1…AC-n before any
  check runs.
- Profile `make.start` — the only sanctioned way to boot the service
  (container-only rule).

## Procedure

1. **Enumerate the acceptance criteria** — collect every AC from the
   issue and the PRD, number them, and resolve the service base URL
   (from the repo's compose/start configuration).
2. **Boot the service** — run the profile's `make.start` target. If
   `make.start` is `null` (capability absent), do NOT hard-fail:
   record the degrade note and finish with the degrade verdict
   `PASS (SUCCESS-WITH-REPORT — black-box QA skipped, make.start: null)`
   (NFR-4). This is the PASS branch of the report template's verdict
   enum, qualified with the degrade reason — the bare `PASS` token is
   what satisfies the orchestrator's stage-5 gate ("QA verdict PASS",
   sdlc.md), while the parenthetical records that no checks actually
   ran. If the start target exists but the service fails to come up,
   that is a blocking finding — escalate.
3. **Dispatch `qa-manual-tester`** (Task tool) with the AC list, the
   base URL, the report contract, and the current QA iteration number
   from this command's iteration guard — on a re-dispatch after an
   implement-stage fix round also attach the prior iteration ledger,
   so the agent's counter resumes rather than resets (subagents are
   stateless across dispatches). Restate the agent's rules in the
   dispatch prompt:
   - Verdicts from HTTP/API behavior ONLY (`curl` and friends). No
     source reading for verdicts — Read is limited to logs and specs
     (prompt-level rule; tool frontmatter cannot path-restrict Read).
   - Report-only: no Edit, no Write, no fixes.
   - Every AC gets ≥1 executed check; across the run, cover positive
     (happy path), negative (invalid input, error handling), and edge
     cases (boundaries, empty/oversized payloads).
   - Every check records: the exact request issued, expected response,
     observed response, verdict.
   - Every FAIL records minimal reproduction steps — the exact
     commands a human can replay.
4. **Assemble the report** from the template below. The stage verdict
   is PASS only when every AC's checks pass.
5. **On FAIL** — route back to `/sdlc-implement` with the full report
   attached (inside `/sdlc` this loop-back consumes stage budget per
   FR-1). Standalone: print the report and instruct the user to re-run
   `/sdlc-implement` with it.

### Report template

```text
# QA Report — <slug>, iteration <n>/5
service: make.start = <target>, base URL = <url>

## Checks (every AC maps to >=1 executed check)
| AC | kind | request | expected | observed | verdict |
|---|---|---|---|---|---|
| AC-<n> | positive/negative/edge | <method + path + payload> | <expected> | <observed> | PASS/FAIL |

## Failures and reproduction steps
### AC-<n> — FAIL
reproduction:
  1. <exact command>
  2. <exact command>
expected: <...>   observed: <...>

## Verdict: PASS | FAIL
# The make.start:null degrade (step 2) is the PASS branch, written
# `PASS (SUCCESS-WITH-REPORT — black-box QA skipped, make.start: null)`:
# the leading `PASS` token satisfies the stage-5 gate, the parenthetical
# records that no checks ran. FAIL is reserved for an executed-and-failed
# check or a boot failure (those escalate / route back to stage 3).
```

## Loop & exit condition

Each iteration is one full QA pass over the enumerated AC list against
a freshly booted service (after an `/sdlc-implement` fix round when
routed back). Exit condition (FR-1 stage table): **QA verdict PASS
(FAIL routes back to stage 3)**.

## Iteration guard

`MAX_ITERATIONS=5`. Keep an explicit counter and restate it every turn
(`qa iteration <n>/5`). The implement-stage fix rounds triggered by
FAIL verdicts are budgeted by their own stage guard — this counter
bounds QA passes only.

## Failure escalation

On guard breach or a blocking finding (service will not boot, base URL
unreachable), emit the canonical report with the QA report attached:

```text
=== SDLC ESCALATION ===
stage: qa                iteration: <n>/5
exit_condition: QA verdict PASS (FAIL routes back to stage 3)
status: NOT MET
blocking_finding: <one line — e.g. first failing AC or boot failure>
iteration_log: <one line per iteration: checks run / failures>
recommended_action: <human next step>
=== END ===
```
