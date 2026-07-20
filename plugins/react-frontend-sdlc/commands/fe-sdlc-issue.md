---
description: "Turn a task description into a labeled GitHub issue (label react-frontend-sdlc) with testable, QA-observable acceptance criteria; dedup-search the repo first so a cross-session resume never opens a duplicate"
argument-hint: "[task-description]"
---

# /fe-sdlc-issue — task text → GitHub issue (FR-3)

Stage 1 of the frontend SDLC loop. Produces the issue artifact that
`/fe-sdlc-plan` consumes. The primary input is a free-text task
description (create mode). On a cross-session resume the orchestrator may
hand this stage an existing issue URL/number instead; that is validated
and adopted, never duplicated.

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/fe-sdlc-setup` — never
  continue with an invalid or missing profile.
- The argument:
  - **Task description** (one or more sentences) → create mode.
  - **Issue URL or `#<number>`** (resume case) → adopt mode: validate
    and adopt the existing issue rather than opening a new one.
- Profile keys consumed: `project.repo` (the repository the issue
  belongs to — `gh` resolves it from the current checkout, which the
  profile pins).

## Procedure

### Create mode (argument is task text)

0. **Pre-create dedup search (never open a duplicate)** — before
   drafting, search the repo for an existing SDLC-managed issue that
   already covers this task, so a cross-session resume (where the
   `ISSUE_URL:` stdout line from a prior run is gone) does not create a
   second issue:

   ```bash
   gh issue list --state open --label react-frontend-sdlc \
     --json number,url,title,body --limit 100
   ```

   Match an existing issue by title/problem overlap with the task text.
   If one matches, do NOT create — switch to **adopt mode** on that
   issue's URL (validate it, ensure ≥3 testable AC, keep the marker
   label) and emit its `ISSUE_URL:`. Only when no managed issue matches
   does create mode proceed to draft a new one. (If `gh issue list`
   fails — `gh` unauthenticated/unavailable — that is a blocking
   finding: escalate, do not create blind, since a blind create is
   exactly how the duplicate appears.)

1. Draft the issue from the task text:
   - **Title**: imperative, specific, ≤72 characters.
   - **Problem statement**: what is missing or broken in the UI today and
     why it matters, 2–5 sentences (`## Problem`).
   - **Acceptance criteria**: at least 3 testable bullets
     (`## Acceptance criteria`). Testable means each bullet names an
     observable behavior a frontend QA run (E2E / visual / Lighthouse /
     a11y) can check (user interaction → expected rendered state, route →
     expected view/URL, input/prop → expected component output,
     accessible query → expected role/name, command → expected output).
     No vague bullets ("looks right", "feels fast").
   - **Scope notes**: explicitly in-scope and out-of-scope items
     (`## Scope`).
2. Ensure the plugin marker label `react-frontend-sdlc` exists:
   `gh label list` — if absent, `gh label create react-frontend-sdlc
   --description "Created by the react-frontend-sdlc SDLC loop"`.
3. Create the issue — write the drafted body to a temp file (e.g.
   `mktemp`) and pass it via `--body-file`; never inline the multiline
   markdown body as a shell argument, where its quotes, backticks, and
   `$` would be re-interpreted by the shell:

   ```bash
   gh issue create --title "<title>" --body-file "<temp-body-file>" \
     --label react-frontend-sdlc
   ```

4. Verify by reading it back (`gh issue view <url> --json url,title,body,labels`):
   the body contains ≥3 acceptance-criteria bullets and the marker
   label is attached. Fix with `gh issue edit` if anything is missing.

### Adopt mode (argument is an issue URL or number)

1. Validate it: `gh issue view <arg> --json url,title,body,state,labels`
   must succeed and the issue must be OPEN. A closed or missing issue
   is a blocking finding — escalate, do not silently create a new one.
2. Check the body for ≥3 testable acceptance-criteria bullets. If they
   are missing or vague, derive them from the issue body and append an
   `## Acceptance criteria` section via `gh issue edit` — amend the
   existing issue, never open a duplicate.
3. Ensure the `react-frontend-sdlc` marker label exists, then attach it:
   first `gh label list` — if absent, `gh label create react-frontend-sdlc
   --description "Created by the react-frontend-sdlc SDLC loop"` (same as
   create-mode step 2; `--add-label` fails on a repo that never ran the
   create flow if the label is missing). Then
   `gh issue edit <url> --add-label react-frontend-sdlc`.

### Output (both modes)

Print the issue URL as the final line in this exact form, which
`/fe-sdlc-plan` consumes as its input artifact:

```text
ISSUE_URL: <url>
```

## Loop & exit condition

Each iteration re-checks the created/adopted issue via `gh issue view`:
URL resolves, ≥3 testable AC bullets present, marker label attached.
Exit condition (FR-1 stage table): **GitHub issue URL exists with
testable AC and the `react-frontend-sdlc` label**.

## Iteration guard

`MAX_ITERATIONS=5`. One iteration = one draft→create/amend→verify
cycle. Keep an explicit counter and restate it every turn
(`issue iteration <n>/5`).

## Failure escalation

On guard breach or a blocking finding (e.g. adopted issue is closed,
`gh` cannot list or create the issue), emit the canonical report and
stop:

```text
=== SDLC ESCALATION ===
stage: issue             iteration: <n>/5
exit_condition: GitHub issue URL exists with testable AC
status: NOT MET
blocking_finding: <one line>
iteration_log: <one line per iteration>
recommended_action: <human next step>
=== END ===
```
