---
description: "Turn a task description into a labeled GitHub issue with testable acceptance criteria, or validate and adopt an existing issue URL"
argument-hint: "[task-description | issue-URL]"
---

# /sdlc-issue — task text → GitHub issue (FR-3)

Stage 1 of the SDLC loop. Produces the issue artifact that `/sdlc-plan`
consumes. Two input modes: free-text task description (create) or an
existing issue URL/number (validate and adopt — never create a
duplicate).

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/sdlc-setup` — never
  continue with an invalid or missing profile.
- The argument, exactly one of:
  - **Task description** (one or more sentences) → create mode.
  - **Issue URL or `#<number>`** → adopt mode.
- Profile keys consumed: `project.repo` (the repository the issue
  belongs to — `gh` resolves it from the current checkout, which the
  profile pins).

## Procedure

### Create mode (argument is task text)

1. Draft the issue from the task text:
   - **Title**: imperative, specific, ≤72 characters.
   - **Problem statement**: what is missing or broken today and why it
     matters, 2–5 sentences (`## Problem`).
   - **Acceptance criteria**: at least 3 testable bullets
     (`## Acceptance criteria`). Testable means each bullet names an
     observable behavior a QA run can check (request → expected
     response, command → expected output, state → expected invariant).
     No vague bullets ("works correctly", "is fast").
   - **Scope notes**: explicitly in-scope and out-of-scope items
     (`## Scope`).
2. Ensure the plugin marker label `php-backend-sdlc` exists:
   `gh label list` — if absent, `gh label create php-backend-sdlc
   --description "Created by the php-backend-sdlc SDLC loop"`.
3. Create the issue:

   ```bash
   gh issue create --title "<title>" --body "<body>" --label php-backend-sdlc
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
3. Ensure the `php-backend-sdlc` marker label exists, then attach it:
   first `gh label list` — if absent, `gh label create php-backend-sdlc
   --description "Created by the php-backend-sdlc SDLC loop"` (same as
   create-mode step 2; `--add-label` fails on a repo that never ran the
   create flow if the label is missing). Then
   `gh issue edit <url> --add-label php-backend-sdlc`.

### Output (both modes)

Print the issue URL as the final line in this exact form, which
`/sdlc-plan` consumes as its input artifact:

```text
ISSUE_URL: <url>
```

## Loop & exit condition

Each iteration re-checks the created/adopted issue via `gh issue view`:
URL resolves, ≥3 testable AC bullets present, marker label attached.
Exit condition (FR-1 stage table): **GitHub issue URL exists with
testable AC**.

## Iteration guard

`MAX_ITERATIONS=5`. One iteration = one draft→create/amend→verify
cycle. Keep an explicit counter and restate it every turn
(`issue iteration <n>/5`).

## Failure escalation

On guard breach or a blocking finding (e.g. adopted issue is closed,
`gh` cannot create the issue), emit the canonical report and stop:

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
