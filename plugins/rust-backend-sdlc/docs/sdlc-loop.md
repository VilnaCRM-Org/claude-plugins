# The SDLC loop

`/rs-sdlc` drives one feature of a Rust service from a task text to a finished pull request: a setup check, then the stages issue, branch, plan, implement, review, QA and PR finishing. Each stage has an exit string that must hold before the next stage starts and a bounded iteration guard. Every run ends with exactly one of two results, `SUCCESS` or `ESCALATED`, and prints the run report on every exit path. The run is resumable: the stage record lives on the issue, so a later `/rs-sdlc <N>` continues at the first stage whose record no longer holds.

This page describes the loop as a whole: the stage table, the guards and counters, the durable state and the resume rules, the Ralph rules of the implement stage, the run report, the escalation block, the background rule, the branch guards and the workflow form. Each stage's own contract is its command file under `commands/` (the orchestrator is `commands/rs-sdlc.md`). Every value a stage reads comes from the project profile described in [the profile schema](profile-schema.md); setup and new services are walked through in [the setup walkthrough](setup-walkthrough.md) and [the new-service walkthrough](new-service-walkthrough.md); every degraded outcome is a row of [the degrade matrix](degrade-matrix.md).

## Stage diagram

```text
/rs-sdlc "<task text>" | /rs-sdlc <N> | /rs-sdlc (on a <type>/<N>-<slug> branch)
 └─ stage 0 setup-check: validate-profile.sh, governance markers, _bmad/ ──[any failure]──► ESCALATED
 │     (recommended_action: run /rs-sdlc-setup on the default branch and commit the result)
 └─ resume: state comment by the posting identity, else the state cache, else a fresh start
 └─ stage 1 issue (/rs-sdlc-issue) ──► ISSUE_URL:, ISSUE_NUMBER:
 └─ branch: git fetch origin <default_branch>; git switch -c <type>/<N>-<slug> origin/<default_branch> ──► BRANCH:
 └─ stage 2 plan (/rs-sdlc-plan) ──► SPECS_DIR: specs/<N>-<slug>/ (committed)
 └─ stage 3 implement (/rs-sdlc-implement)                                                        ◄──┐
 │     ralph_fix_plan_prepare → stage-planning-artifacts.sh → bmalph implement → ralph_agent_md_patch │
 │     → ralph_breaker_state → bmalph run --driver claude-code --no-dashboard                        │
 │     └─[breaker OPEN or STATUS: BLOCKED]──► ESCALATED (breaker never reset, no second run)          │
 └─ stage 4 review (/rs-sdlc-review): 28-skill triage, three lenses, Q1–Q15, FR/NFR gate ──► PASS     │
 └─ stage 5 qa (/rs-sdlc-qa): qa-manual-tester over REST, GraphQL and health probes ──► PASS          │
 │     └─[## Verdict: FAIL]── append "Fix QA findings <n>" to SPECS_DIR/epics.md, commit ─────────────┘
 └─ stage 6 finish-pr (/rs-sdlc-finish-pr): pr-state.sh sensor loop, counters A B C W R
       └──► PR_URL:, ## Status: ALL-GREEN (or SKIPPED-NO-CI) ──► run report, result: SUCCESS
```

## Stage table

The exit strings are byte-identical in every file that carries them (CC-12): the six loop stages `issue`, `plan`, `implement`, `review`, `qa` and `finish-pr` in their stage command and in `commands/rs-sdlc.md`; `setup-check` and `branch`, which have no stage command, in `commands/rs-sdlc.md`; `setup`, `new-service` and `new-context` in their own command. A stage's escalation block quotes its exit string verbatim in `exit_condition:`, and the run report quotes it in the `stages:` table.

| Stage id | Exit string | Guard |
| --- | --- | --- |
| `setup-check` | valid profile, governance markers in CLAUDE.md and AGENTS.md, _bmad/ present | halt with "run /rs-sdlc-setup on the default branch and commit the result" |
| `issue` | issue with ≥ 3 testable acceptance criteria and label rust-backend-sdlc exists | 5 |
| `branch` | branch `<type>/<N>-<slug>` checked out from the default branch | — |
| `plan` | bundle complete, readiness "ready", readiness regex clean, bundle committed | 5 |
| `implement` | all stories done with EXIT_SIGNAL true, every commit subject valid, coverage green | 5 + Ralph circuit breaker (never reset) |
| `review` | zero new gate findings AND every quality row PASS | 5 |
| `qa` | QA verdict PASS on HEAD (FAIL routes to stage 3) | 5 |
| `finish-pr` | CI green + FR/NFR gate green on the head SHA + 0 unresolved review threads | A 5, B 5, C 3, W 6, R 3 |
| `setup` | preflight without FAIL, profile valid, markers in both files, allowlist present or printed, docs-check passed or degraded with a note | 5 (regeneration attempts) |
| `new-service` | S1–S14 executed or printed as NEXT, bootstrap PR handed to finish-pr (GitHub mode) | 5 (hook-failure remediation rounds) |
| `new-context` | context gate set green, 0 protected files changed, committed | 5 (remediation rounds) |

Where each stage runs and what it hands to the next one:

| Order | Stage id | Run by | Success handles |
| --- | --- | --- | --- |
| 0 | `setup-check` | `/rs-sdlc` itself: `validate-profile.sh`, the managed-block marker in `CLAUDE.md` and `AGENTS.md`, `test -d _bmad` | none; any failure escalates |
| 1 | `issue` | `/rs-sdlc-issue` | `ISSUE_URL:`, `ISSUE_NUMBER:` |
| — | `branch` | `/rs-sdlc` itself, one attempt | `BRANCH:` |
| 2 | `plan` | `/rs-sdlc-plan` | `SPECS_DIR:` |
| 3 | `implement` | `/rs-sdlc-implement` | the last `---RALPH_STATUS---` block with `EXIT_SIGNAL: true`, the targets-run list |
| 4 | `review` | `/rs-sdlc-review` | `FR_NFR_REVIEWER:` per iteration, `## Verdict: PASS` |
| 5 | `qa` | `/rs-sdlc-qa` | `## Verdict: PASS` and the evidence table, or `SKIP: qa (make.start absent)` (D1) |
| 6 | `finish-pr` | `/rs-sdlc-finish-pr` | `PR_URL:`, `## Status: ALL-GREEN` or `## Status: SKIPPED-NO-CI` (D8) |
| outside the loop | `setup` | `/rs-sdlc-setup`, on the default branch | `DONE:`, `UNCHANGED:`, `DEGRADED:` and `NEXT:` lines |
| outside the loop | `new-service` | `/rs-sdlc-new-service`, which hands its bootstrap pull request to the finish-pr procedure | `ISSUE_NUMBER:`, `BRANCH:`, `PR_URL:`, one `DONE:`/`NEXT:` summary |
| outside the loop | `new-context` | `/rs-sdlc-new-context`, which hands over to the review, QA and finish-pr procedures (or prints three `NEXT:` lines with `--no-handoff`) | `ISSUE_NUMBER:`, `BRANCH:`, the checklist lines, the targets-run list |

How the stages run:

- A stage starts only when the previous one met its exit string. `/rs-sdlc` executes each stage by reading `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-<stage>.md` and following its procedure with the stage's arguments, because a slash command cannot call another; the stage's own inputs, guard, degrade paths and escalation apply unchanged, and under the orchestrator its escalation block is followed by the run report.
- Stage 0 never runs setup. Setup is a human decision on the default branch: a profile that does not validate, a missing marker (D19) or an absent `_bmad/` (D5 named in `iteration_log`) escalate at `setup-check` with `run /rs-sdlc-setup on the default branch and commit the result`.
- The branch step fetches the default branch once (`git fetch origin <default_branch>`; a failure is D24, a degrade note), reuses the issue's branch when one exists locally or on `origin`, and otherwise creates `<type>/<N>-<slug>` from `origin/<default_branch>`: `<type>` is `fix` when the issue carries the `bug` label, else `feat`; `<slug>` is the kebab of the issue title, at most 40 characters. Only a failed switch escalates, with `stage: branch` and `iteration: 1/1`.
- Agents are dispatched with the Task tool as `subagent_type: rust-backend-sdlc:<agent>`. On the command path the plugin's agents never commit or push: every commit and push of a stage belongs to its command, except the story commits that Ralph's own sessions make inside the implement stage.

## Outcomes

A stage ends with exactly one status: `SUCCESS` (exit string met, no degrade note), `SUCCESS-WITH-REPORT` (exit string met, one or more `DEGRADED:` notes) or `ESCALATED` (the escalation block). `DEGRADED:` is only a line prefix, never a status. The run knows only `result: SUCCESS` or `result: ESCALATED`: a `SUCCESS-WITH-REPORT` stage keeps the run at `SUCCESS`, adds its notes to `degrade_notes` and records `met: yes (degraded)`; an `ESCALATED` stage records `met: no` and ends the run.

Degrade paths never loop and never fake a pass: an absent capability ends a stage `SUCCESS-WITH-REPORT` with its note, a mapped capability that cannot run or a safety block ends it `ESCALATED` unless its degrade-matrix row names `SUCCESS-WITH-REPORT` for the stage (for the loop stages only D13, whose `ask` targets are lifecycle and `-fix` targets and never a gate), and a skipped QA is never reported as a QA pass. Every target a stage runs or holds back gets one targets-run line, `<target>: passed | failed | not run (<reason>)`, with `<reason>` one of `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed` or `deferred to PR CI`. The 25 degrade paths and their outcomes are listed in [the degrade matrix](degrade-matrix.md).

## Iteration guards

- `MAX_ITERATIONS=5` per stage, restated as `<stage> iteration <n>/5` on every stage turn. The counters are never reset within a run, a QA loop-back included, and are restored from the state record on a resume. A stage that must run while its restored counter is already 5 starts no iteration and escalates at once with `iteration: 5/5`.
- `implement`: at most five resumable `bmalph run` attempts, plus Ralph's circuit breaker, which is never reset (see "Ralph rules" below). Only resumable exits consume an attempt.
- `qa`: a QA `FAIL` routes to stage 3 through the QA loop-back, which consumes implement's budget, and the next QA pass consumes QA's; at most four loop-backs fit one run before QA's own guard escalates.
- `setup-check` and `branch` run once per invocation and are never retried.
- `setup`: five regeneration attempts of the profile. `new-service`: five hook-failure remediation rounds at S11 and S13, then the finish-pr counters after the hand-off. `new-context`: five remediation rounds of the gate stages.
- There is no run-level cap beyond the stage guards: they bound the run, and Ralph's circuit breaker ends it independently (D22).

### Finish-pr counters

Stage 6 holds five counters instead of one. They are owned and persisted by `commands/rs-sdlc-finish-pr.md`, and the `ci-fixer` agent (`agents/ci-fixer.md`) uses the same names and caps (AC-21.1). The stage guard `MAX_ITERATIONS=5` is the cap of A and B.

| Counter | Label | Cap | One unit is |
| --- | --- | --- | --- |
| A | `ci_fix` | 5 | one `FIX` round with failing checks: one `ci-fixer` dispatch, then the command's commit and push (never spent under the no-CI rule, D8) |
| B | `comment_resolution` | 5 | one `FIX` round with unresolved review threads, or one D7 pass: one `pr-comment-resolver` dispatch, then the commit and push |
| C | `fr_nfr_gate` | 3 | one `GATE` run of the FR/NFR gate on the clean head, with its remediation commit |
| W | `wait` | 6 | one `WAIT` of the sensor (`--wait-seconds 540`) |
| R | `request` | 3 | one `REQUEST` for AI re-reviews |

In one line: A `ci_fix` 5, B `comment_resolution` 5, C `fr_nfr_gate` 3, W `wait` 6, R `request` 3.

- **State cell.** The five values are stored together in the `iteration` cell of the `finish-pr` row as `A<n>.B<n>.C<n>.W<n>.R<n>` (regex `^A[0-9]+\.B[0-9]+\.C[0-9]+\.W[0-9]+\.R[0-9]+$`, for example `A2.B0.C1.W3.R0`), restored from it at the start of the stage and written back after every round, so a resume continues every counter where it stopped.
- **Restatement.** Every round starts with `finish-pr round <k>: verdict <verdict>; counters A<a>/5 B<b>/5 C<c>/3 W<w>/6 R<r>/3`; the counter of the action is raised before the action runs.
- **Exhaustion.** A counter above its cap ends the stage `ESCALATED` with `iteration: <cap>/<cap> (<label>)`: `iteration: 5/5 (ci_fix)`, `iteration: 5/5 (comment_resolution)`, `iteration: 3/3 (fr_nfr_gate)`, `iteration: 6/6 (wait)` or `iteration: 3/3 (request)`. Every round except the last (`BLOCKED`, a confirmed `READY` or an escalation) spends at least one unit, so one run holds at most 22 rounds (5 + 5 + 3 + 6 + 3) before its last one.
- **Dispatch.** Each round takes one `pr-state.sh --json` snapshot with the profile lists `ci.required_checks`, `review.reviewers` and `ci.human_gated` passed explicitly, and acts on its verdict:

| Verdict | Action | Counter (cap) |
| --- | --- | --- |
| `FIX` | `ci-fixer` for failing non-human-gated checks; `pr-comment-resolver` for unresolved threads from trusted authors (ADR-26; the Task prompt carries the PR number and plugin root, never thread bodies); the command runs `protected_changes`, commits (`fix(#N): resolve <check> failure`, `fix(#N): address review comment on <path>`) and pushes | A `ci_fix` (5), B `comment_resolution` (5) |
| `GATE` | `make <make.fr_nfr_gate>` when that key is non-null (ADR-4; output must end `FR_NFR_NEW_FINDINGS: <n>`), else `fr-nfr-gate.sh --pr <n> --iteration <c>`, on the clean head | C `fr_nfr_gate` (3) |
| `REQUEST` | `request-ai-reviews.sh` with the arguments of the sensor's `NEXT:` hint | R `request` (3) |
| `WAIT` | `pr-state.sh --wait-seconds 540` | W `wait` (6) |
| `BLOCKED` | `ESCALATED` naming the label or the conflict | — |
| `READY` | second snapshot; conclusion comment; `## Status: ALL-GREEN` | — |

`READY` is confirmed by a second snapshot on the same head before the conclusion comment is posted. No CI (`ci.provider: null`, D8) never spends A and ends `## Status: SKIPPED-NO-CI`; no AI reviewer (D7) makes the isolated review loop the comment source and spends B.

## Durable state

The orchestrator records every stage on the issue itself, so a resume survives `cargo clean`, a fresh clone and a new session (ADR-14). The workflow path keeps no state comment (see "Workflow form").

### State comment

One issue comment per issue, edited in place, holds one row per stage:

```markdown
<!-- rust-sdlc-state -->

| stage | result | head_sha | iteration | at |
| --- | --- | --- | --- | --- |
| issue | PASS | <40-hex sha> | 1 | <YYYY-MM-DDTHH:MM:SSZ> |
| plan | PASS | <40-hex sha> | 2 | <YYYY-MM-DDTHH:MM:SSZ> |
| implement | PASS | <40-hex sha> | 1 | <YYYY-MM-DDTHH:MM:SSZ> |
| review | PASS | <40-hex sha> | 3 | <YYYY-MM-DDTHH:MM:SSZ> |
| qa | IN_PROGRESS | <40-hex sha> | 1 | <YYYY-MM-DDTHH:MM:SSZ> |
| finish-pr | IN_PROGRESS | <40-hex sha> | A1.B0.C1.W2.R0 | <YYYY-MM-DDTHH:MM:SSZ> |
```

- The marker `<!-- rust-sdlc-state -->` is the first line; the table has exactly the columns `| stage | result | head_sha | iteration | at |`.
- `result` is `PASS` (the stage ended `SUCCESS` or `SUCCESS-WITH-REPORT`), `IN_PROGRESS` or `ESCALATED`. `IN_PROGRESS` also marks a QA `FAIL` routed to stage 3, the implement row that loop-back reopens and a skipped QA, because no verdict exists that a `PASS` row could stand for.
- `head_sha` is the full `git rev-parse HEAD` the stage ended on (QA: the head its verdict is about; review: the head of its last iteration).
- `iteration` is an unsigned integer, the stage's counter at its end; for `finish-pr` it is the cell `A<n>.B<n>.C<n>.W<n>.R<n>`.
- `at` is the UTC time in ISO-8601 form.

After every stage 1–6 that ran, and on its escalation, the orchestrator updates the cache, builds the body, redacts it (ADR-27) and publishes it; finish-pr writes its own row with the same procedure:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" state_cache_update target/rust-sdlc/state/<N>-<slug>.json <stage> <result> <head> <iteration>
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" state_comment_body target/rust-sdlc/state/<N>-<slug>.json
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" redact --in target/rust-sdlc/tmp/state.raw.md --out target/rust-sdlc/tmp/state.md
gh api -X PATCH repos/{owner}/{repo}/issues/comments/<id> -F body=@target/rust-sdlc/tmp/state.md
gh api repos/{owner}/{repo}/issues/<N>/comments -F body=@target/rust-sdlc/tmp/state.md
```

The body from `state_comment_body` is written to `target/rust-sdlc/tmp/state.raw.md` before the redaction. The `PATCH` edits the posting identity's comment; the last call creates the comment the first time. When one of the orchestrator's own records cannot be published, the failing `gh` call is a degrade note (D10), the cache keeps the record and the next record publishes the whole table again; finish-pr, which cannot run without `gh` anyway, escalates on a failing state-comment post instead.

### Author filter

Anyone who can comment on the issue could post a comment that starts with the marker, and a forged table claiming `PASS` at `HEAD` would skip review and QA on resume. So the record is trusted only from the posting identity (ADR-26):

- The identity is resolved once per run with `gh api user --jq .login` and handed to the finish-pr procedure.
- Only marker comments whose `user.login` equals it are read or edited, oldest first; every other marker comment is ignored with `DEGRADED: ignored state comment by <login>`.
- An identity that cannot be resolved treats the record as absent (D10): a new comment is created and none is edited.

### Concurrency

Two runs on one issue can interleave. Before each edit the orchestrator reads the comment's `updated_at` again (`gh api repos/{owner}/{repo}/issues/comments/<id> --jq .updated_at`) and compares it with the value it last saw. A change means another run wrote the comment: its rows of the other stages are merged into the cache once and the body is rebuilt. A second change ends the current stage `ESCALATED` with `blocking_finding: concurrent /rs-sdlc runs on issue #<N>`.

### State cache

The cache mirrors the comment in the service checkout, under the git-ignored `target/`:

```text
target/rust-sdlc/state/<N>-<kebab-title>.json
{"schema_version": 1, "issue": <N>, "slug": "<kebab-title>", "staged_specs_dir": "<path>" | null,
 "stages": [{"stage": "<stage>", "result": "<result>", "head_sha": "<sha>", "iteration": <iteration>, "at": "<UTC>"}]}
```

`issue` and `slug` come from the file name (`^([1-9][0-9]*)-([a-z0-9-]+)\.json$`); `staged_specs_dir` is the bundle the last `bmalph implement` staged (the re-entry protocol below reads it). The cache is written only through `state_cache_update`. `cargo clean` deletes it; the state comment survives.

## Resume

Resume rules are computed by `common.sh resume_point` (PA-7, bats-tested), never judged by reading the table by eye. The source order is the state comment authored by the posting identity while `gh` is reachable, else the cache, else a fresh start:

```bash
gh api user --jq .login
gh api repos/{owner}/{repo}/issues/<N>/comments --paginate | "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" resume_point --comments <login>
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" resume_point --cache target/rust-sdlc/state/<N>-<slug>.json
```

What `resume_point --comments <login>` and `resume_point --cache <file>` print:

```text
DEGRADED: ignored state comment by <login>
DONE_STAGE: <stage> <sha7> <iteration>
RESUME_STAGE: <stage>
BLOCKED_STAGE: implement breaker=<OPEN|HALF_OPEN>
COUNTERS: issue=<n>,plan=<n>,implement=<n>,review=<n>,qa=<n>,finish-pr=A<n>.B<n>.C<n>.W<n>.R<n>
```

- `DONE_STAGE:` a stage whose record still holds; it is not run again, and its run-report row reads `<iteration>/5 (resumed)` with `met: yes`.
- `RESUME_STAGE:` the first stage to run. `RESUME_STAGE:` and `BLOCKED_STAGE:` exclude each other.
- `BLOCKED_STAGE: implement breaker=<OPEN|HALF_OPEN>` — the implement row is `ESCALATED` and Ralph's breaker is still open (D22): the orchestrator escalates at once without running anything, because a new `bmalph run` would let Ralph reset the breaker itself.
- `COUNTERS:` every stage counter and the five finish-pr counters, restored and never reset within the run.

| Stage | Durable record | Validity on resume |
| --- | --- | --- |
| `setup-check` | none: it runs on every invocation | always re-run |
| `issue` | the `issue` row and the open issue labelled `rust-backend-sdlc` | ancestor: `git merge-base --is-ancestor <head_sha> HEAD` |
| `branch` | the branch `<type>/<N>-<slug>` itself, local or on `origin` | reused when it exists, never recreated |
| `plan` | the `plan` row and the committed bundle `specs/<N>-<slug>/` | ancestor |
| `implement` | the `implement` row, the story commits, `.ralph/@fix_plan.md` and the cache's `staged_specs_dir` | ancestor; an `ESCALATED` row with the breaker `OPEN` or `HALF_OPEN` → `BLOCKED_STAGE` (D22) |
| `review` | the `review` row and the review ledgers | equal: `head_sha` equals `HEAD` |
| `qa` | the `qa` row | equal: a commit after the verdict makes it stale |
| `finish-pr` | the `finish-pr` row (its counter cell) and the pull request | live: re-derived from a live `pr-state.sh` snapshot; the cell restores A, B, C, W and R |

The three rules:

- **Ancestor** (issue, plan, implement): the work is committed, so the record holds while its `head_sha` is an ancestor of `HEAD`. Rebased or rewritten history re-runs the stage.
- **Equal** (review, QA): a verdict is about one head, so the record holds only while `head_sha` equals `HEAD`; any later commit makes the verdict stale.
- **Live** (finish-pr): the pull-request state changes outside the run, so it is re-derived from a live `pr-state.sh` snapshot every time; only the counters come from the record.

A stage counts only while every earlier stage counts, and only a `PASS` row counts. With `gh` reachable a resume repeats no completed stage, also after `cargo clean` or in a fresh clone. Without `gh` the cache is used (`DEGRADED: gh unreachable: state restored from target/rust-sdlc/state/<N>-<slug>.json (D10)`); without both, the run starts fresh (`DEGRADED: gh unreachable and no state cache: fresh start, review and QA re-run (D10)`), and every stage finds its own durable work: the issue stage adopts the issue, the plan stage finds the committed bundle, implement's `FIX_PLAN: current` skips staging, and review and QA re-run.

## Ralph rules

On the command path the implement stage hands the stories to bmalph (floor 2.11.0) and its Ralph loop. Four rules keep that loop inside the plugin's contract.

### Single implementer

`bmalph run --driver claude-code --no-dashboard` is the only implementer: "`bmalph run` is the only implementer; while it is active this command dispatches no `rust-implementer` and edits no file". Ralph's own sessions commit each story as `<type>(#<N>): story N.M <title>` with the hooks active; inside them, DB-free targets may run in parallel `rust-backend-sdlc:rust-implementer` subagents and the DB-backed targets run in one serialized verify step. That story-dispatch rule reaches Ralph only through `## Constraints` of the bundle's `architecture.md` (at most 4,500 characters, part (a) the commit convention, then part (b) the dispatch rule naming the five DB-free keys `make.format`, `make.lint_code`, `make.unit_tests`, `make.architecture`, `make.complexity` and the five DB-backed keys `make.setup_test_db`, `make.integration_tests`, `make.tests_with_coverage`, `make.e2e_tests`, `make.sqlx_prepare`), which bmalph copies into `.ralph/PROJECT_CONTEXT.md`; the stage verifies both parts there before `bmalph run` and escalates naming `/rs-sdlc-plan` when one is missing.

The plugin never runs `bmalph implement` with `--force` and never edits `.ralph/.ralphrc`. Its only writes into `.ralph/` are three: moving `.ralph/@fix_plan.md` into the archive, re-marking restored stories, and the `.ralph/@AGENT.md` patch.

### Re-entry protocol (ADR-10a)

`bmalph implement` refuses with `already been run` (exit 1) whenever `.ralph/@fix_plan.md` exists, and `.ralph/` survives between runs: a resume, a QA loop-back and a second feature in the same checkout would all hit the refusal. So the implement stage (and the workflow's Stage phase) prepares the fix plan first:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ralph_fix_plan_prepare "$SPECS_DIR" target/rust-sdlc/state/<N>-<slug>.json
```

| Line | When | Then |
| --- | --- | --- |
| `FIX_PLAN: absent` | no fix plan yet | stage, `bmalph implement` |
| `FIX_PLAN: current` | the cache's `staged_specs_dir` is this bundle and every `### Story N.M:` id of `SPECS_DIR/epics.md` is in the fix plan (a resume) | skip staging and `bmalph implement`; go on to the patch, the context check and `bmalph run` |
| `ARCHIVED: target/rust-sdlc/ralph-archive/<UTC>-fix_plan.md keep-progress` | same bundle, but `epics.md` holds a story id the fix plan lacks (how a QA fix story arrives) | stage, `bmalph implement`, then restore |
| `ARCHIVED: target/rust-sdlc/ralph-archive/<UTC>-fix_plan.md discard-progress` | no cache, or the cache names another bundle | stage, `bmalph implement`, no restore |

- Staging is `"${CLAUDE_PLUGIN_ROOT}/scripts/stage-planning-artifacts.sh" "$SPECS_DIR"`, then a plain `bmalph implement`. An `already been run` refusal after the protocol is a defect of the protocol and escalates; it is never worked around.
- After `keep-progress`, `common.sh ralph_fix_plan_restore <archive>` re-marks `- [x]` every story whose id **and** title were checked in the archive and prints `RESTORED: <n> stories`. Fix-plan lines have the form `- [ ] Story <id>: <title>` and `- [x] Story <id>: <title>`.
- After a successful `bmalph implement` the stage records the bundle with `state_cache_update … --staged-specs-dir "$SPECS_DIR"`.
- A cache lost to `cargo clean` is read as a foreign plan (`discard-progress`): already-committed stories are verified again, which costs time and is never wrong; restoring by id and title across bundles could mark an unrelated story done.

### QA loop-back

A QA `FAIL` below `qa iteration 5/5` routes to stage 3. `/rs-sdlc-qa` holds no `Edit` or `Write` and changes no file, so the orchestrator does the loop-back:

1. Budget: when implement's stored iteration is already 5, the run escalates at stage `implement` with `iteration: 5/5` and nothing is appended.
2. Hooks: `common.sh hooks_active` must print `HOOKS: active` (after `make install-hooks` for `HOOKS: unset`).
3. Append, under the last epic of `SPECS_DIR/epics.md`, one story whose acceptance criteria are the FAIL rows of the QA evidence table, redacted first, in the format bmalph's story parser reads (description lines before `**Acceptance Criteria:**`, every criterion starting with `Given`):

   ```markdown
   ### Story <E>.<k>: Fix QA findings <n>
   As a feature engineer,
   I want the QA FAIL rows of run <n> fixed,
   So that QA passes on HEAD.

   **Acceptance Criteria:**
   - Given <check>, when <METHOD> <URL> is probed, then <expected> (observed: <observed>)
   **Depends on:** <E>.<k-1>
   ```

4. Guard and commit: `protected_changes <merge-base-sha>` (ADR-25), only `SPECS_DIR/epics.md` staged, the subject `docs(#N): add QA fix story <n>` pre-validated, then `git commit -F <path>` in the background.
5. Record the `qa` row and the reopened `implement` row `IN_PROGRESS`, then re-enter stage 3 on its continuing counter: `ralph_fix_plan_prepare` prints `ARCHIVED: … keep-progress`, `bmalph implement` adds the fix story, and the restore keeps every story already done, so only the new story is unchecked. Stages 4, 5 and 6 follow in order, and QA judges the new `HEAD`.

The workflow path never restages for QA: it hands the FAIL rows to one `rust-implementer` round directly (see "Workflow form").

### `.ralph/@AGENT.md` overrides (ADR-10b)

The bundle's `## Tech Stack` names the Rust toolchain, so bmalph writes cargo commands into `.ralph/@AGENT.md`, and bmalph's template for that file also asks for 85% coverage, a `git add .` commit with a `feat(module)` subject, `feature/<name>` branches and a `git push origin <branch-name>` before the next feature. Each of these contradicts the make-only rule, the subject form, the 100% coverage floor or the rule that commands own every push. Right after every `bmalph implement` and before every `bmalph run` (on the workflow path, right after the staging `bmalph implement`) the stage runs:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ralph_agent_md_patch "$SPECS_DIR"
```

| Part of `.ralph/@AGENT.md` | After the patch |
| --- | --- |
| fenced block under `## Project Setup` | `make <make.bootstrap>` |
| fenced block under `## Running Tests` | `make <make.unit_tests>`, then the DB-backed keys in serialized order: `make.setup_test_db`, `make.integration_tests`, `make.e2e_tests` |
| fenced block under `## Build Commands` | `make <make.tests_with_coverage>` |
| fenced block under `## Development Server` | `make <make.start>` |
| every line containing `85%` | `Coverage floor: <quality.coverage_lines>% lines and <quality.coverage_functions>% functions` |
| items 1–3 of `### Git Workflow Requirements` | three rules: commit each story as `<type>(#<N>): story N.M <title>` with the hooks active; stay on the branch the plugin checked out (`<type>/<N>-<slug>`); never push, the plugin command pushes |
| item 4 ("Ralph Integration") | kept |

A `null` key drops its line, and an empty block reads `not available (capability absent)`. A missing heading is not an error: the function appends a `## rust-backend-sdlc overrides` section with the same four commands and three rules. It prints `UPDATED: .ralph/@AGENT.md` or, on a second run, `UNCHANGED: .ralph/@AGENT.md`, and exits 1 when `.ralph/@AGENT.md` is absent or the profile is invalid.

### Breaker pre-check and attempt classification (ADR-10c)

Ralph's circuit breaker recovers on its own: `.ralph/.circuit_breaker_state` moves from `OPEN` to `HALF_OPEN` after a cooldown, and to `CLOSED` at startup when `CB_AUTO_RESET=true`. A plain resume would therefore let Ralph reset a tripped breaker, which the plugin forbids. Before every `bmalph run`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ralph_breaker_state
```

It prints `BREAKER: CLOSED`, `BREAKER: OPEN`, `BREAKER: HALF_OPEN` or `BREAKER: ABSENT`, and `AUTO_RESET: true` or `AUTO_RESET: false` (`CB_AUTO_RESET` from the environment, else from a `CB_AUTO_RESET=` line of `.ralph/.ralphrc`), and edits nothing.

- `OPEN`, `HALF_OPEN` or `AUTO_RESET: true` → `ESCALATED` (D22) and nothing runs.
- After a run, a trip is `.state == "OPEN"` (the primary signal) or a `---RALPH_STATUS---` block with `STATUS: BLOCKED`: `ESCALATED` with the last status block and the last 50 lines of the newest `.ralph/logs/` file, no second `bmalph run`, the breaker never reset and never restarted around.
- Only resumable exits consume one of the five attempts: an API or rate-limit exit, a timeout, or `EXIT_SIGNAL: false` with the breaker `CLOSED`. A trip, a `HALF_OPEN` breaker after the run and any unclassified end consume no attempt.
- On resume, `resume_point` reports `BLOCKED_STAGE: implement breaker=<OPEN|HALF_OPEN>` for an `ESCALATED` implement row while the state file is `OPEN` or `HALF_OPEN`, and the orchestrator escalates without running anything.

The breaker is a human-attention signal: the recommended action is to diagnose the cause in `.ralph/logs/`, and a human decides before any further run.

## Run report

`/rs-sdlc` prints it last on every exit path, success and escalation alike, with exactly these 8 fields:

```text
=== SDLC RUN REPORT ===
task: <task text or "#<N> (resumed)">
branch: <branch>
result: SUCCESS | ESCALATED
stages:
| stage | iterations used | exit string | met |
| --- | --- | --- | --- |
| issue | 1/5 | issue with ≥ 3 testable acceptance criteria and label rust-backend-sdlc exists | yes |
artifacts: issue=<url> specs=<SPECS_DIR> pr=<url>
degrade_notes: <"none" or one "- <note>" line each>
targets_not_run: <"none" or one "- <target>: <reason>" line each>
escalation: <the failing stage's block, or none>
=== END ===
```

- `task:` the task text, or `#<N> (resumed)` when the run started from `<N>`, `#<N>`, an issue URL or a feature branch.
- `branch:` the branch printed by the branch step, `none` before it.
- `result:` `SUCCESS` or `ESCALATED`, nothing else.
- `stages:` one row per stage that ran or was resumed, in stage-table order, up to the stage that ended the run. `iterations used` is `<n>/5`, `<n>/5 (resumed)` for a `DONE_STAGE`, `—` for `setup-check` and `branch`, `A<a>/5 B<b>/5 C<c>/3 W<w>/6 R<r>/3` for `finish-pr`, with `(loop-backs: <k>)` appended to `qa` after a loop-back; `exit string` is the stage's exit string verbatim; `met` is `yes`, `yes (degraded)` or `no`.
- `artifacts:` `issue=`, `specs=` and `pr=` from the `ISSUE_URL:`, `SPECS_DIR:` and `PR_URL:` handles, each `none` when not produced.
- `degrade_notes:` every `DEGRADED:` note of the run, in order, each as `- <note>`, or `none`.
- `targets_not_run:` every `<target>: not run (<reason>)` line of the stages as `- <target>: <reason>`, or `none`.
- `escalation:` the failing stage's block, from `=== SDLC ESCALATION ===` to its `=== END ===`, or `none`.

Mapping: a stage ending `SUCCESS-WITH-REPORT` yields run `result: SUCCESS` (unless another stage escalates), its notes are appended to `degrade_notes`, and its stage-table row records `met: yes (degraded)`; `SUCCESS` records `met: yes`; `ESCALATED` records `met: no` and ends the run.

## Escalation block

Every stage stops with the same 7-field block between its delimiters:

```text
=== SDLC ESCALATION ===
stage: <stage-id>
iteration: <n>/<cap>[ (<label>)]
exit_condition: <exit string, verbatim from the stage table>
status: NOT MET
blocking_finding: <file:line | check name + URL | command + exit code>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human action: a label, a protected change with ALLOW_PROTECTED_CONFIG_EDIT=1, a command>
=== END ===
```

- `stage:` one of the 11 stage ids: `setup`, `setup-check`, `new-service`, `new-context`, `issue`, `branch`, `plan`, `implement`, `review`, `qa`, `finish-pr`. `branch` covers a failed `git switch -c`, including one caused by a missing `origin/<default_branch>`; a failed `git fetch` alone is D24, a degrade note.
- `iteration:` the stage guard as `<n>/5`, `1/1` for `setup-check` and `branch`, or the exhausted finish-pr counter with its label: `iteration: 5/5 (ci_fix)`, `iteration: 5/5 (comment_resolution)`, `iteration: 3/3 (fr_nfr_gate)`, `iteration: 6/6 (wait)` or `iteration: 3/3 (request)`.
- `exit_condition:` the stage's exit string from the stage table, byte for byte.
- `blocking_finding:` one concrete finding: a `file:line`, a check name with its URL, or a command with its exit code.
- `recommended_action:` the human action. A label is applied by a maintainer, never by the plugin; a protected change needs a session restarted with `ALLOW_PROTECTED_CONFIG_EDIT=1`.

Under `/rs-sdlc` the block is followed by the run report, which repeats it in its `escalation:` field, and the stage's row is recorded `ESCALATED`, so a later `/rs-sdlc <N>` resumes at that stage with its counter. For example, a repository whose `AGENTS.md` lost the managed block:

```text
=== SDLC ESCALATION ===
stage: setup-check
iteration: 1/1
exit_condition: valid profile, governance markers in CLAUDE.md and AGENTS.md, _bmad/ present
status: NOT MET
blocking_finding: governance marker missing in AGENTS.md
iteration_log: 1: validate-profile.sh, marker check, _bmad/ check -> marker missing in AGENTS.md
recommended_action: run /rs-sdlc-setup on the default branch and commit the result
=== END ===
```

## Background rule

Every command that runs `make`, `git commit` or `git push`, and every agent that runs `make`, carries these two sentences verbatim:

Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` and `bmalph run`, runs through the Bash tool with `run_in_background: true` (never a trailing `&`), logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled with `common.sh wait_log` at most every 30 s.

In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.

The Bash tool caps a foreground call at 600 s, and gates, builds and Ralph's loop run longer (D14), so every such call has the same shape:

```bash
mkdir -p target/rust-sdlc/logs
{ <command>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/<stage>-<UTC>.log 2>&1  # Bash tool, run_in_background: true
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" wait_log target/rust-sdlc/logs/<stage>-<UTC>.log
```

- `<UTC>` is the current UTC time as `YYYYMMDDTHHMMSSZ`; the log directory is created by one foreground `mkdir -p`.
- The background-task completion notice is the primary signal. Progress reads, and the wait when no notice arrives (headless runs), use `wait_log`: it checks the last line every 30 s for at most 110 s per call, inside the Bash tool's default 120 s timeout, prints the last 40 lines and either `RUST_SDLC_EXIT=<n>` (exit 0) or `WAITING: <log> (<elapsed>s)` (exit 1). The stage calls it again until the line appears or its budget is spent, and then escalates with the log tail.
- The call is never sent to the background with a trailing `&` or `nohup`, and no stage waits with a bare foreground `sleep`.
- When the runtime prompts for the brace-group wrapper, the same call is issued as `<command> > target/rust-sdlc/logs/<stage>-<UTC>.log 2>&1` and its exit status is taken from the completion notice.
- Make calls use the suffix form `make <target> [VAR=value …]` with no make option, and only the variables of the closed set `RUN_IN_CONTAINER COMMIT_TITLE base_ref BREAKING_CHANGE_APPROVED CONFIG_CHANGE_APPROVED group context name SCHEMATHESIS_URL`, because a command-line variable overrides the gate's own settings. `CONFIG_CHANGE_APPROVED=` is always passed empty on `make validate-configuration` and `make ci-preflight`, and `base_ref=<…>` is always explicit, so neither an inherited approval nor the Makefile's `base_ref` fallback ever applies. Only the hooked git calls keep the prefix form in container mode: `RUN_IN_CONTAINER=1 git commit -F <path>` and `RUN_IN_CONTAINER=1 git push -u origin HEAD`.
- A log with the template message `This target needs a reachable container engine (docker).` classifies its target `not run (no Docker)`, never `failed` (D2).

## Branch guards

The template's guard hook covers only the file-editing tools, so edits made through Bash and inside Ralph's sessions are not guarded by it, and the profile is read from the feature branch, where a commit could remap a gate key or flip a capability. The branch guards close both gaps (ADR-25):

```bash
git merge-base <ci.base_ref> HEAD
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" protected_changes <merge-base-sha>
```

- `protected_changes` reads the `files` and `directories` of the template's `protected-config.toml`, matches them against `git diff --name-only <merge-base-sha>` plus the untracked files, and checks whether `.claude/rust-sdlc.yml` existed at the merge base and differs now. It prints `PROTECTED: <path> (<commit or "working tree">)` and `PROFILE_CHANGED: .claude/rust-sdlc.yml`, and exits 0 when there is no hit, 1 when there is any.
- It runs before every commit a command makes and before the workflow publish step. In addition, `make validate-configuration base_ref=<merge-base-sha> CONFIG_CHANGE_APPROVED=` (backgrounded; the template's authoritative check) runs at the implement post-loop and at the start of each review iteration, as a pre-check outside the Q1–Q15 table, and falls back to `protected_changes` when no toolchain or Docker is available. Finish-pr runs the guard first.
- The merge base is read once with `git merge-base <ci.base_ref> HEAD` and passed as a literal. When `<ci.base_ref>` is unavailable after one fetch, `HEAD` is used with a D24 note.
- A `PROTECTED:` hit ends `ESCALATED` (D23) with `blocking_finding: protected file <path> changed (<commit>)` and `recommended_action: revert with git restore --source=<merge-base> -- <path> unless the plan intends it; otherwise approved-config-change`. The label is applied by a maintainer, and a protected edit needs a session restarted with `ALLOW_PROTECTED_CONFIG_EDIT=1`.
- A `PROFILE_CHANGED:` hit ends `ESCALATED` with `recommended_action: move the profile change to its own pull request from the default branch (/rs-sdlc-setup --refresh)`. A profile absent at the merge base (the new-service bootstrap pull request, a first setup pull request) is exempt.

Together with the profile validation rule V12 (every non-null `make.<key>` must name the target `<key>` with `-` for `_`; see [the profile schema](profile-schema.md)), a feature branch can neither relax a protected bar nor reroute a gate key. Commits follow the same path everywhere: `protected_changes <merge-base-sha>`, then `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" commit_msg_file '<subject>'`, then `git commit -F <path>` with the hooks active (`hooks_active` prints `HOOKS: active`; `HOOKS: unset` runs `make install-hooks`, `HOOKS: foreign <value>` and `HOOKS: missing <file>` escalate). Pushes are only `git push -u origin HEAD`. No stage applies or removes `approved-config-change` or `approved-breaking-change`.

## Workflow form

The same loop also runs as four Workflow scripts under `workflows/`, nested by their plugin-qualified names `rust-backend-sdlc:rs-sdlc-<name>`. They dispatch the same agents as `rust-backend-sdlc:<agent>`, return the same status words (`result` is `SUCCESS`, `SUCCESS-WITH-REPORT` or `ESCALATED`, with the 7-field block in `escalation`) and keep the same counters. The full contract, including the harness, is in `docs/workflows.md`.

| Workflow | Runs | Counters | Returns |
| --- | --- | --- | --- |
| `rs-sdlc-feature` | stages 0–6 for one feature, top level only; phases Setup check, Resolve plan, Stage, Implement, Review, FR/NFR gate, QA, Finish PR | implement rounds 5 (whole run), QA loops 2, feature-owned gate 3 | `{result, task, branch, issue_url, specs_dir, pr_url, stages, degrade_notes, escalation?}` |
| `rs-sdlc-review-panel` | stage 4: the lenses in parallel (`security-auditor` only when security-relevant paths changed), three refuters per finding, `rust-implementer` fix groups | iterations ≤ 5 | `{result, iterations, findings, fixed, carried, degrade_notes}` |
| `rs-sdlc-fr-nfr-review` | the FR/NFR gate as its own bounded loop: `fr-nfr-reviewer` once per iteration, fixes by `rust-implementer` | gate iterations ≤ 5 | `{result, iterations, new_findings, fixed, requirement_source, advisory, degrade_notes}` |
| `rs-sdlc-pr-until-green` | stage 6 as a sensor-driven loop over `pr-state.sh` verdicts | fix 5, wait 6, request 3, gate 3 (carried) | `{result, pr, head, verdict, counters, journal, degrade_notes}` |

- **Nesting.** Only `rs-sdlc-feature` nests workflows, and `rs-sdlc-pr-until-green` nests the FR/NFR review only inside a branch guarded by `OPTS.onGate === 'nested'` (its default), so the call graph is never deeper than one level. A nested call that throws, such as an unresolved name, ends `ESCALATED` with the manual command line (D21).
- **Hand-back with `carry`.** The feature workflow calls `workflow('rust-backend-sdlc:rs-sdlc-pr-until-green', {…, onGate: 'return', carry})` with the literal `onGate: 'return'`. On a `GATE` verdict pr-until-green hands control back instead of nesting; the feature workflow runs `workflow('rust-backend-sdlc:rs-sdlc-fr-nfr-review', {pr, head})`, publishes its fixes and re-enters pr-until-green with `carry` (`{counters, journal, degrade_notes}`): the counters resume and are never reset. After 3 gate rounds the run ends `ESCALATED`.
- **No Ralph loop.** The workflow path never runs `bmalph run`. Its Stage phase applies the re-entry protocol (`ralph_fix_plan_prepare`, then on `FIX_PLAN: absent` or `ARCHIVED:` the staging script, `bmalph implement` and, after `keep-progress`, `ralph_fix_plan_restore`; always `ralph_agent_md_patch` and the two-part `.ralph/PROJECT_CONTEXT.md` check); then `rust-implementer` rounds execute the stories of `.ralph/@fix_plan.md` (read-only) layer-first, parallel stories run DB-free targets only, and one serialized `verify <round>` agent runs the DB-backed targets. Its `degrade_notes` always contain `bmalph run: not used (workflow path)`. An implementer reply `status: BLOCKED` ends `ESCALATED`, the workflow analogue of the breaker trip.
- **QA.** `qa-manual-tester` runs after `make start` and `make migrate`; a QA `FAIL` hands its FAIL rows to one `rust-implementer` round directly, with no restage and at most 2 QA loops.
- **State.** The workflow path keeps no state comment; it resumes only within a run, through `carry`.
- **Publishing.** In pr-until-green an untyped publish agent commits and pushes the fixes (`protected_changes`, `commit_msg_file`, `git commit -F <path>`, `git push -u origin HEAD`, each in the background form): the single exception to the rule that agents never commit. The prompts of every agent that runs `make`, `git commit` or `git push` carry the background and container-precondition sentences verbatim.
