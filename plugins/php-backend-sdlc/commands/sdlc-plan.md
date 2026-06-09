---
description: "Run the BMAD planning chain non-interactively for a GitHub issue, writing the six-artifact specs/<slug>/ chain until readiness passes"
argument-hint: "[issue-URL]"
---

# /sdlc-plan — issue → planning artifacts (FR-4)

Stage 2 of the SDLC loop. Converts the stage-1 issue into the complete
BMAD planning chain under `specs/<slug>/`, fully non-interactively: the
chain never pauses for human input — every open question is resolved by
a recorded assumption.

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/sdlc-setup`.
- The issue: the URL argument, or the `ISSUE_URL:` line emitted by
  `/sdlc-issue`. Resolve it with
  `gh issue view <url> --json url,number,title,body` — title, problem
  statement, and acceptance criteria seed the chain. A missing or
  closed issue is a blocking finding.
- `<slug>`: kebab-case of the issue title (prefix with the issue
  number, e.g. `42-currency-crud`); all artifacts live under
  `specs/<slug>/`.

## Procedure

1. Resolve the issue and derive `<slug>` as above.
2. **Direct-load the planning skill** (§1.2 dependency edge — this
   command loads it itself rather than going through an agent): read

   ```text
   ${CLAUDE_PLUGIN_ROOT}/skills/bmad-autonomous-planning/SKILL.md
   ```

   and execute it end-to-end against the issue.
3. **Non-interactive mandate (FR-4)**: zero interactive prompts are
   permitted anywhere in the chain. Wherever the BMAD workflow would
   normally elicit input, decide autonomously and record the decision
   inline in the artifact as `> Assumption: <decision and rationale>`.
   Never use AskUserQuestion; never wait for confirmation.
4. The chain writes the six artifacts under `specs/<slug>/`, in order:
   1. `research.md` — domain/technical research for the issue
   2. `brief.md` — product brief
   3. `prd.md` — requirements, with the issue's acceptance criteria
      traced into FRs
   4. `architecture.md` — technical design
   5. `epics-stories.md` — epics and stories, each story marked
      independent or dependent (the `/sdlc-implement` parallel-dispatch
      input)
   6. `readiness.md` — implementation-readiness verdict (PASS/FAIL with
      named findings)

   Cross-references must stay consistent: each artifact links its
   predecessors, and no artifact contradicts an upstream decision.
5. If the readiness verdict is FAIL, apply corrections to the artifacts
   the findings name, then re-run the readiness check — this is the
   bounded loop below.
6. On PASS, print the artifact handle as the final line, which
   `/sdlc-implement` consumes:

   ```text
   SPECS_DIR: specs/<slug>
   ```

## Loop & exit condition

Each iteration re-checks: all six artifacts exist under `specs/<slug>/`
and `readiness.md` records a PASS verdict. Exit condition (FR-1 stage
table): **`specs/` chain complete, readiness PASS**.

## Iteration guard

`MAX_ITERATIONS=5`. One iteration = one correction pass over the
artifacts named by readiness findings plus a readiness re-run. Keep an
explicit counter and restate it every turn (`plan iteration <n>/5`).

## Failure escalation

On guard breach or a blocking finding (issue unresolvable, skill file
missing from the install cache), emit the canonical report and stop:

```text
=== SDLC ESCALATION ===
stage: plan              iteration: <n>/5
exit_condition: specs/ chain complete, readiness PASS
status: NOT MET
blocking_finding: <one line — e.g. the first unresolved readiness finding>
iteration_log: <one line per iteration>
recommended_action: <human next step>
=== END ===
```
