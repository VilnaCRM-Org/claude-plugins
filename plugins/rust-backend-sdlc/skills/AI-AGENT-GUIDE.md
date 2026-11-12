# AI Agent Guide

This guide orients every session that works on a Rust service through the `rust-backend-sdlc` plugin, whether a feature engineer driving the loop or an agent dispatched into it: which of the seven agents runs at which stage, which command dispatches it, which bundled script each stage calls, which handles a stage prints, how a stage ends and how it escalates. It sits at the `skills/` root without frontmatter, so it is never discovered as a skill. Its sibling [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md) decides which of the 28 skills a change needs; this guide names the skills and who applies them, and leaves the verdicts to that guide.

## How to orient yourself

1. **Find your stage.** The command that started the session names it (stage map below); a dispatched agent finds its stage in its Task prompt and its own row in the agent roster.
2. **Read the profile.** `.claude/rust-sdlc.yml` resolves every value: each tool runs as the make target its `make.<key>` maps to, and a key mapped to `null` means the capability is absent, recorded as `not run (capability absent)`, never replaced by a raw command.
3. **Pick the skills.** Follow the triage of [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md): verdicts from frontmatter plus that guide, bodies only on `EXECUTE`.
4. **Do only your stage's work** with the agents and scripts its row names, inside its guard.
5. **End with output, never with silence.** A stage prints its handles and its status; a stage that cannot meet its exit string prints the escalation block.

## Agent roster

The plugin ships exactly seven agents, under `agents/` of the plugin root. Commands dispatch them through the Task tool and workflows through their agent calls, both with the agent type `rust-backend-sdlc:<agent>`, one dispatch per iteration; the dispatcher passes the resolved plugin root in the prompt so the agent can call `common.sh`.

| agent | model | tools | runs when | dispatched by | returns |
| --- | --- | --- | --- | --- | --- |
| [`rust-implementer`](../agents/rust-implementer.md) | sonnet | Read, Write, Edit, Glob, Grep, Bash | a planned story, a review-gate remediation, a QA fix story, a new-context checklist item or a failing test must be implemented, code plus tests | the claude-code sessions of `bmalph run` inside /rs-sdlc-implement (never the command itself), the remediation step of /rs-sdlc-review (one Task with all findings), /rs-sdlc-new-context (checklist items C2–C11 and gate remediation), workflow implementation and fix rounds | changed-files list, targets-run list, self-review checklist, a final `---RALPH_STATUS---` block |
| [`code-quality-reviewer`](../agents/code-quality-reviewer.md) | opus | Read, Glob, Grep, Bash | every review iteration, always: the quality rows Q1–Q15 and the branch diff against `ci.base_ref` | /rs-sdlc-review, the review-panel workflow | findings as `file:line`, severity, rule and root-cause fix; the Q1–Q15 table; a verdict line; last, a fenced `json` block of `CQ-` findings |
| [`fr-nfr-reviewer`](../agents/fr-nfr-reviewer.md) | opus | Read, Glob, Grep, Bash | every review iteration, always: it runs the FR/NFR gate exactly once per iteration and traces every requirement to test evidence | /rs-sdlc-review, the review-panel and FR/NFR-review workflows | per-requirement matrix, a fenced `json` block of `FRN-` findings, the last line `FR_NFR_REVIEWER:` |
| [`security-auditor`](../agents/security-auditor.md) | opus | Read, Glob, Grep, Bash | a review iteration whose diff since the merge base touches `*.rs`, `Cargo.toml`, `Cargo.lock`, `migrations/`, `.sqlx/`, `deny.toml`, a `Dockerfile` or `.github/workflows/` (re-run only when remediation touched those paths), or a standalone audit of a service the user owns | /rs-sdlc-review, the review-panel workflow | lanes table, families table, a verdict line; last, a fenced `json` block of `SEC-` findings |
| [`qa-manual-tester`](../agents/qa-manual-tester.md) | sonnet | Bash, Read | stage 5, after the stage has booted the stack and applied the migrations: a verdict on the change from observed HTTP behaviour only | /rs-sdlc-qa, the QA phase of the feature workflow | evidence table, a reproduction `curl` command line as text for each FAIL, a verdict line |
| [`ci-fixer`](../agents/ci-fixer.md) | sonnet | Read, Edit, Write, Glob, Grep, Bash | the `FIX` verdict of the finish-pr sensor names failing checks that are not human-gated (counter A, label `ci_fix`) | /rs-sdlc-finish-pr, the Fix phase of the pr-until-green workflow | per-check table, the counter line `ci_fix <n>/5`, a status line |
| [`pr-comment-resolver`](../agents/pr-comment-resolver.md) | sonnet | Read, Edit, Write, Glob, Grep, Bash | the `FIX` verdict reports unresolved review threads (counter B, label `comment_resolution`), or no AI reviewer is configured and the isolated review loop is the comment source | /rs-sdlc-finish-pr, the Fix phase of the pr-until-green workflow | per-thread table, the counter line `comment_resolution <n>/5`, `remaining_unresolved: <n>` |

Rules every agent follows:

- **One spine.** Each agent file has the eight sections `Profile keys consumed`, `Role`, `Inputs`, `Outputs`, `Allowed actions`, `Degrade paths`, `Iteration discipline` and `Smoke prompt`; `## Iteration discipline` states `MAX_ITERATIONS=5`. The dispatching command owns the counter and restates it in the prompt as `<n>/5`.
- **Make only.** Every tool runs as `make <target>` resolved through the profile, with variables after the target and only from the closed set `RUN_IN_CONTAINER`, `COMMIT_TITLE`, `base_ref`, `BREAKING_CHANGE_APPROVED`, `CONFIG_CHANGE_APPROVED`, `group`, `context`, `name`, `SCHEMATHESIS_URL`; no make option, `CONFIG_CHANGE_APPROVED` only empty, `base_ref` always explicit. Results go into the targets-run list (see Handles).
- **Background and container.** The six agents that run `make` (all except `qa-manual-tester`) carry these two sentences verbatim, because a subagent's Bash call has the same 600 s cap as the command's:

  Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` and `bmalph run`, runs through the Bash tool with `run_in_background: true` (never a trailing `&`), logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled with `common.sh wait_log` at most every 30 s.

  In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.

- **Least privilege.** The three review lenses and `qa-manual-tester` hold no `Write` or `Edit`: they report, `rust-implementer` fixes. `qa-manual-tester` never reads service source, tests or manifests and never runs `make`; it sends every request through `common.sh http_probe` to `service.base_url`.
- **Protected configuration.** An agent that would have to change a protected file stops and reports exactly `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`. A guard-hook denial is quoted verbatim and never retried through Bash.
- **Agents report, commands escalate.** No agent prints the escalation block. An agent ends with its verdict, status or Ralph block (`## Verdict: FAIL`, `## Status: BLOCKED`, `verdict=FAIL`, `STATUS: BLOCKED`, plus its `DEGRADED:` notes), and the dispatching command turns that into the stage's status or its escalation block.

## Stage map

`/rs-sdlc` runs stage 0 to stage 6 in this order and stops at the first escalation; each stage command also runs on its own. The last three rows are the commands outside the loop. Exit strings are byte-equal to the stage commands, `/rs-sdlc` and the plugin's loop documentation; an escalation quotes them verbatim in `exit_condition:`.

| # | stage | command | agents | scripts | exit string | guard |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | `setup-check` | /rs-sdlc (stage 0) | none | `validate-profile.sh`; the governance-marker check of `CLAUDE.md` and `AGENTS.md`; `test -d _bmad` | valid profile, governance markers in CLAUDE.md and AGENTS.md, _bmad/ present | halt with "run /rs-sdlc-setup on the default branch and commit the result" |
| 1 | `issue` | /rs-sdlc-issue | none | `validate-profile.sh`; `common.sh redact` for the issue body | issue with ≥ 3 testable acceptance criteria and label rust-backend-sdlc exists | 5 |
| — | `branch` | /rs-sdlc (branch step) | none | none: one `git fetch origin <default_branch>`, then `git switch -c` from `origin/<default_branch>` or reuse of the branch | branch `<type>/<N>-<slug>` checked out from the default branch | — |
| 2 | `plan` | /rs-sdlc-plan | none: the command applies `bmad-autonomous-planning` itself, the repository copy first | `validate-profile.sh`; `stage-planning-artifacts.sh "$SPECS_DIR" --dry-run` (the staging dry run, which also proves the `## Constraints` length); `common.sh protected_changes`, `commit_msg_file` | bundle complete, readiness "ready", readiness regex clean, bundle committed | 5 |
| 3 | `implement` | /rs-sdlc-implement | `rust-implementer`, only inside the claude-code sessions of `bmalph run` | `validate-profile.sh`; `common.sh hooks_active`, `ralph_fix_plan_prepare`, `ralph_fix_plan_restore`, `ralph_agent_md_patch`, `ralph_breaker_state`, `wait_log`, `is_commit_subject`, `protected_changes`; `stage-planning-artifacts.sh "$SPECS_DIR"` | all stories done with EXIT_SIGNAL true, every commit subject valid, coverage green | 5 + Ralph circuit breaker (never reset) |
| 4 | `review` | /rs-sdlc-review | `code-quality-reviewer` and `fr-nfr-reviewer` always; `security-auditor` on its path rule; `rust-implementer` for remediation | `validate-profile.sh`; `fr-nfr-gate.sh`, run only by `fr-nfr-reviewer` and only when `make.fr_nfr_gate` is null; `common.sh ledger_write`, `protected_changes`, `commit_msg_file`; `post-review-findings.sh <lens>` when a PR exists | zero new gate findings AND every quality row PASS | 5 |
| 5 | `qa` | /rs-sdlc-qa | `qa-manual-tester` | `validate-profile.sh`; `common.sh wait_log`; `common.sh http_probe` (every probe, sent by the agent) | QA verdict PASS on HEAD (FAIL routes to stage 3) | 5 |
| 6 | `finish-pr` | /rs-sdlc-finish-pr | `ci-fixer`, `pr-comment-resolver` | `validate-profile.sh`; `pr-state.sh` (the sensor); `fr-nfr-gate.sh --pr <n>`; `request-ai-reviews.sh`; `post-review-findings.sh` (deferred lens comments, then `--conclusion` once on READY); `get-pr-comments.sh` and `ai-review-loop.sh` (through `pr-comment-resolver`); `common.sh redact`, `protected_changes`, `commit_msg_file` | CI green + FR/NFR gate green on the head SHA + 0 unresolved review threads | A 5, B 5, C 3, W 6, R 3 |
| — | `setup` | /rs-sdlc-setup | none | `setup-preflight.sh --report`, `generate-profile.sh`, `validate-profile.sh`, `inject-governance.sh`, `merge-settings.sh`; `common.sh hooks_active` | preflight without FAIL, profile valid, markers in both files, allowlist present or printed, docs-check passed or degraded with a note | 5 (regeneration attempts) |
| — | `new-service` | /rs-sdlc-new-service | none of its own; after the hand-off, the finish-pr agents `ci-fixer` and `pr-comment-resolver` | `new-service.sh --phase source`, `new-service.sh --phase customize`; `common.sh is_commit_subject`, `hooks_active`, `commit_msg_file`, `redact`; the setup scripts at S12 and the finish-pr scripts after S14 | S1–S14 executed or printed as NEXT, bootstrap PR handed to finish-pr (GitHub mode) | 5 (hook-failure remediation rounds) |
| — | `new-context` | /rs-sdlc-new-context | `rust-implementer` (checklist items C2–C11 and gate remediation); after the hand-off, the review, QA and finish-pr agents | `validate-profile.sh`; `common.sh validate_context_name`, `protected_changes`, `commit_msg_file` | context gate set green, 0 protected files changed, committed | 5 (remediation rounds) |

Scripts live under `scripts/` of the plugin root; commands call them by their absolute plugin-root path, and `common.sh <function>` is the library dispatcher `scripts/lib/common.sh`. Skills never call scripts, agents or commands.

How the stages hand over:

- **Stage 0** never runs setup itself: any failed check ends `ESCALATED` with stage `setup-check` and the halt wording of its guard.
- **Resume.** `/rs-sdlc <N>` reads the state comment `<!-- rust-sdlc-state -->` authored by the posting identity (`common.sh resume_point --comments`), else the cache under `target/rust-sdlc/state/` (`resume_point --cache`), and restores every counter; `BLOCKED_STAGE: implement` escalates without running anything.
- **Stage 3** stages the bundle (`stage-planning-artifacts.sh`, then `bmalph implement`, never with `--force`) unless the fix plan is current, then starts `bmalph run --driver claude-code --no-dashboard` in the background, and has a single implementer: "`bmalph run` is the only implementer; while it is active this command dispatches no `rust-implementer` and edits no file". Ralph's own sessions may fan stories out to `rust-implementer` subagents under the DB rule. A tripped or not-closed breaker ends `ESCALATED`; it is never reset and `bmalph run` is not started a second time.
- **Stage 4** never runs the gate script itself: `fr-nfr-reviewer` runs it once per iteration and copies the script's `FR_NFR_NEW_FINDINGS:` value into its `FR_NFR_REVIEWER:` line. The loop exits on `new_findings=0` AND every quality row PASS; otherwise one Task to `rust-implementer` carries all findings and the command commits `fix(#N): address review gate iteration <n> findings`. The conclusion comment is posted only by finish-pr, on READY.
- **Stage 5 FAIL** routes to stage 3. `/rs-sdlc-qa` holds no `Edit` or `Write`; the orchestrator appends `### Story <E>.<k>: Fix QA findings <n>` with the FAIL rows as acceptance criteria to `SPECS_DIR/epics.md`, commits `docs(#N): add QA fix story <n>` and runs stage 3 again, inside implement's budget.
- **Stage 6** loops on the sensor `pr-state.sh --json` and dispatches by its verdict:

  | verdict | action | counter (cap) |
  | --- | --- | --- |
  | `FIX` | `ci-fixer` for failing checks that are not human-gated, `pr-comment-resolver` for unresolved threads from trusted authors; then the command commits and pushes | A `ci_fix` (5), B `comment_resolution` (5) |
  | `GATE` | `make <make.fr_nfr_gate>` when mapped, else `fr-nfr-gate.sh --pr <n>`, on the clean head | C `fr_nfr_gate` (3) |
  | `REQUEST` | `request-ai-reviews.sh` with the arguments of the sensor's `NEXT:` line | R `request` (3) |
  | `WAIT` | `pr-state.sh --wait-seconds 540` | W `wait` (6) |
  | `BLOCKED` | `ESCALATED`, naming the label or the conflict | — |
  | `READY` | a second snapshot, the conclusion comment, `## Status: ALL-GREEN` | — |

  The five counters are written to the state cell `A<n>.B<n>.C<n>.W<n>.R<n>` and restored on resume; they never reset within a run.
- **New context** hands over to the review, QA and finish-pr procedures with the counters, or prints three `NEXT:` lines naming /rs-sdlc-review, /rs-sdlc-qa and /rs-sdlc-finish-pr when started with `--no-handoff`. **New service** hands its bootstrap pull request to the finish-pr procedure after S14.

## Workflow form

The plugin's four workflows run the same stages from a Workflow script: `rs-sdlc-feature` (top level), `rs-sdlc-review-panel`, `rs-sdlc-pr-until-green` and `rs-sdlc-fr-nfr-review`, nested by the plugin-qualified names `rust-backend-sdlc:rs-sdlc-<name>` and never deeper than one level. They dispatch the same seven agents by the agent types `rust-backend-sdlc:<agent>`, next to untyped helper agents of their own (scope, refuters, publish), and return the same status words. The feature workflow never runs `bmalph run`: after staging it drives `rust-implementer` rounds over `.ralph/@fix_plan.md` (read-only) itself and records the degrade note `bmalph run: not used (workflow path)`. In pr-until-green, an untyped publish agent commits and pushes the fixes; it is the single exception to the no-commit rule below.

## Handles

Handles are the lines a stage or agent prints for the next one to parse, one item per line on stdout:

- `ISSUE_URL: <url>` and `ISSUE_NUMBER: <N>`: printed by /rs-sdlc-issue (the number also by /rs-sdlc-new-service and /rs-sdlc-new-context); the branch name, the planning bundle and every commit subject `<type>(#<N>): <subject>` take `<N>` from them.
- `BRANCH: <type>/<N>-<slug>`: printed by the branch step of /rs-sdlc, /rs-sdlc-new-service and /rs-sdlc-new-context.
- `SPECS_DIR: specs/<N>-<kebab-title>`: printed by /rs-sdlc-plan; the argument of implement, review and QA.
- `PR_URL: <url>`: printed by /rs-sdlc-finish-pr and /rs-sdlc-new-service; the `pr=` artifact of the run report.
- `---RALPH_STATUS---` block: the last block of every `rust-implementer` report and of each Ralph loop, with `STATUS: IN_PROGRESS|COMPLETE|BLOCKED`, `TASKS_COMPLETED_THIS_LOOP`, `FILES_MODIFIED`, `TESTS_STATUS: PASSING|FAILING|NOT_RUN`, `WORK_TYPE`, `EXIT_SIGNAL: true|false` and `RECOMMENDATION`; implement parses it, and `STATUS: BLOCKED` counts as a breaker trip.
- `FR_NFR_NEW_FINDINGS: <n>`: the mandatory last line of `fr-nfr-gate.sh` and of a service's `make <make.fr_nfr_gate>`.
- `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<PASS|FAIL>`: the last line of `fr-nfr-reviewer`, with `new_findings` copied from the gate; /rs-sdlc-review prints it once per iteration.
- `AI_REVIEW_VERDICT: PASS|FAIL`: the mandatory last line of `ai-review-loop.sh`, read by `pr-comment-resolver` when that loop is the comment source.
- `## Verdict: PASS|FAIL`: printed by `code-quality-reviewer`, `security-auditor`, `qa-manual-tester`, /rs-sdlc-review and /rs-sdlc-qa.
- `## Status: ALL-GREEN|FIXES-READY|SKIPPED-NO-CI|BLOCKED`: printed by `ci-fixer` per iteration; /rs-sdlc-finish-pr ends with `## Status: ALL-GREEN` on READY or `## Status: SKIPPED-NO-CI` when the repository has no CI.

Around the handles, scripts and commands print result lines that are never statuses: `DONE:`, `UNCHANGED:`, `SKIP:`, `NEXT:`, `WOULD:` (dry runs), `DEGRADED:` (one degrade note, collected into `degrade_notes`), the file-level results `WROTE:`, `CREATED:`, `UPDATED:`, `REPAIRED:`, `REFUSED:`, `STAGED:`, `REMOVED:`, the validator's `VIOLATION:` lines, the preflight's `PASS:`, `WARN:`, `FAIL:` and `INFO:` lines, and one result line per `common.sh` function (`HOOKS:`, `FIX_PLAN:`, `ARCHIVED:`, `RESTORED:`, `BREAKER:`, `AUTO_RESET:`, `PROTECTED:`, `PROFILE_CHANGED:`, `HTTP_STATUS:`, `WAITING:`, `RUST_SDLC_EXIT=`).

Every report that ran targets carries the targets-run list, one line per target:

```text
<target>: passed | failed | not run (<reason>)
```

with `<reason>` one of `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`. `/rs-sdlc` ends every exit path with the run report `=== SDLC RUN REPORT ===` and its eight fields `task`, `branch`, `result`, `stages`, `artifacts`, `degrade_notes`, `targets_not_run`, `escalation`.

## Escalation block

A command whose stage cannot meet its exit string within its guard prints this block, fills every field and stops:

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

- **Stage ids:** `setup`, `setup-check`, `new-service`, `new-context`, `issue`, `branch`, `plan`, `implement`, `review`, `qa`, `finish-pr`. `branch` covers a failed `git switch -c`, including one caused by a missing `origin/<default_branch>`; a failed `git fetch` alone is a degrade note, never an escalation.
- **Cap:** the stage guard (`5`), or the exhausted finish-pr counter with its label: `iteration: 5/5 (ci_fix)`, `iteration: 5/5 (comment_resolution)`, `iteration: 3/3 (fr_nfr_gate)`, `iteration: 6/6 (wait)`, `iteration: 3/3 (request)`.
- **Evidence:** `blocking_finding` is concrete (a `file:line`, a check name with its URL, or a command with its exit code) and `recommended_action` names what a human does next. No escalation path loops, retries in the background or fakes a pass; under `/rs-sdlc` the block becomes the `escalation:` field of the run report.

## Status vocabulary

A stage ends with exactly one of three words:

| status | meaning | run report |
| --- | --- | --- |
| `SUCCESS` | exit string met, no degrade note | `met: yes` |
| `SUCCESS-WITH-REPORT` | exit string met with at least one degrade note: an absent capability skipped or substituted | `met: yes (degraded)`, the notes appended to `degrade_notes` |
| `ESCALATED` | exit string not met; the escalation block printed | `met: no`, `result: ESCALATED`, the run ends |

The run report knows only `result: SUCCESS` (no stage escalated; degraded stages included) and `result: ESCALATED`.

An absent capability ends `SUCCESS-WITH-REPORT`; a mapped capability that cannot run, or a safety block, ends `ESCALATED`, unless its degrade-matrix row names `SUCCESS-WITH-REPORT` for the stage: D13, whose `ask` targets are lifecycle and `-fix` targets and never a gate, and the setup and new-service cells of D2, D3, D5 and D25, which only report what they could not verify. `DEGRADED:` is only the prefix of a degrade-note line, never a status. Agent verdicts and status lines (`PASS`, `FAIL`, `ALL-GREEN`, `FIXES-READY`, `SKIPPED-NO-CI`, `BLOCKED`, the `STATUS:` of a Ralph block) are inputs the command maps onto these three words: for example `## Status: SKIPPED-NO-CI` ends finish-pr `SUCCESS-WITH-REPORT`, and `## Status: BLOCKED` ends it `ESCALATED`. Workflows return the same three words in `result`; the only other value is the hand-back `GATE` that pr-until-green returns to the feature workflow when that workflow owns the gate.

## Shared-resource (DB) rule

The template's DB-backed targets share one test database, so two implementers that run them at the same time clobber each other's data:

- **Parallel work is DB-free.** Implementers running at the same time run only the five DB-free keys `make.format`, `make.lint_code`, `make.unit_tests`, `make.architecture` and `make.complexity`, plus `make.create_migration`, which only writes a new file pair.
- **One serialized verify step.** During implementation the five DB-backed keys `make.setup_test_db`, `make.integration_tests`, `make.tests_with_coverage`, `make.e2e_tests` and `make.sqlx_prepare`, together with `make.migrate` and the snapshot targets, run only in one serialized verify step. `rust-implementer` takes its mode from the dispatch: `mode: parallel` (DB-free only), `mode: serial` (the only implementer running, so it is its own verify step; the default when the prompt names no mode) or `mode: verify` (the step after a parallel round).
- **How the rule reaches each path.** Ralph reads it from part (b) of the bundle's `## Constraints`, which states both branches: when the `rust-backend-sdlc:rust-implementer` agent is available, independent stories may run as parallel subagents under the DB rule; otherwise stories are implemented sequentially under the same DB rule. The feature workflow runs parallel rounds on the DB-free keys and one serialized `verify <round>` agent for the rest.
- **The shared stack stays up.** QA boots the stack and applies the migrations once before `qa-manual-tester` runs, and never stops the shared stack afterwards.
- DB-backed targets never run in parallel, and two implementers never work on one tree: in the command path `bmalph run` is the only implementer.

## Git ownership rule

- **Commands own every commit and every push.** A commit is always `common.sh protected_changes <merge-base-sha>` (the branch guard), then `common.sh commit_msg_file '<subject>'`, then `git commit -F <path>`; a push is always `git push -u origin HEAD`. In container mode the hooked calls take the prefix form `RUN_IN_CONTAINER=1 git commit -F <path>` and `RUN_IN_CONTAINER=1 git push -u origin HEAD`. The subject is `<type>(#<N>): <subject>`, checked first with `make check-commit-message COMMIT_TITLE='<subject>'` when `make.check_commit_message` is mapped and the subject contains no space-hyphen sequence (the plugin's deny entries refuse that make call), else with `common.sh is_commit_subject '<subject>'`.
- **Agents never commit, push, label or edit `.ralph/`.** They change the working tree and report; the dispatching command commits. The exceptions are exactly these: `ci-fixer` may run `gh run rerun --failed <run-id>` once per head commit for an infrastructure flake; `pr-comment-resolver` may reply to and resolve review threads, each reply published as a redacted body file; the untyped publish agent of the pr-until-green workflow commits and pushes in the forms above.
- **Hooks stay on.** Commits need `common.sh hooks_active` to print `HOOKS: active` (the one exception by design is the new-service S3 import commit, made before hooks can be activated and checked with `common.sh is_commit_subject`); `HOOKS: unset` runs `make install-hooks` and checks again, `HOOKS: foreign <value>` and `HOOKS: missing <file>` end `ESCALATED`. Never pass `--no-verify`, never force-push and never write `core.hooksPath`.
- **Labels belong to humans.** Commands apply only the managed label `rust-backend-sdlc` and, at issue creation, `enhancement`; nobody in the plugin ever applies or removes `approved-config-change` or `approved-breaking-change`, and an escalation names the label a human must add.
- **Protected files and the profile.** A protected change found by `protected_changes` or `make validate-configuration base_ref=<sha> CONFIG_CHANGE_APPROVED=` ends the stage `ESCALATED`, with `recommended_action` to revert it with `git restore --source=<merge-base> -- <path>` or, when the change is wanted, to add `approved-config-change` and restart the session with `ALLOW_PROTECTED_CONFIG_EDIT=1`; a changed profile also ends the stage `ESCALATED`.
- **`.ralph/` is Ralph's.** The only plugin writes into it are the fix-plan archive and restore of `common.sh ralph_fix_plan_prepare` and `ralph_fix_plan_restore` and the `common.sh ralph_agent_md_patch` overrides; `.ralph/.ralphrc` is never edited and `bmalph implement` never runs with `--force`.
- **Publishing is redacted.** Every published body (issue, pull request, comment, state comment, thread reply) is written to a raw file, passed through `common.sh redact --in <raw> --out target/rust-sdlc/tmp/<name>.md`, and published with `--body-file <file>` or `-F body=@<file>`.
- Uncommitted user changes are never discarded: no `git reset --hard`, `git checkout -- .` or `git clean -fd`, ever.

## Skill inventory

The plugin ships exactly these 28 skills, one directory each under `skills/`, listed in directory order. The eleven marked `repo+plugin` share their name with a skill of the service template: the repository's `.claude/skills/<name>/SKILL.md` and `AGENTS.md` are read first and win, and the pair counts as one triage row.

| skill | covers | source | typically applied by |
| --- | --- | --- | --- |
| [`api-contract-development`](api-contract-development/SKILL.md) | regenerate and validate the REST and GraphQL contract snapshots; the breaking-change policy | `repo+plugin` | `rust-implementer`; the contract rows of `code-quality-reviewer` |
| [`api-resource-development`](api-resource-development/SKILL.md) | add or change a REST or GraphQL operation, command, query or subscriber inside one bounded context | `repo+plugin` | `rust-implementer` |
| [`architecture-boundary-fixer`](architecture-boundary-fixer/SKILL.md) | resolve boundary, crate-isolation and unused-dependency findings by moving code, never by editing allow-lists | `repo+plugin` | `rust-implementer`; `ci-fixer` for a red boundary check |
| [`architecture-model-sync`](architecture-model-sync/SKILL.md) | keep `workspace.dsl` components and relationships equal to the crates and their dependency edges | `repo+plugin` | `rust-implementer`; `ci-fixer` for a red model check |
| [`async-runtime-safety`](async-runtime-safety/SKILL.md) | no blocking in async code, no lock guard across `.await`, cancellation and timeouts, `#[async_trait]` delegation | `plugin` | `rust-implementer`; `code-quality-reviewer` |
| [`bmad-autonomous-planning`](bmad-autonomous-planning/SKILL.md) | write the planning bundle without prompts, with `## Constraints` of at most 4,500 characters | `repo+plugin` | /rs-sdlc-plan, which loads it directly |
| [`bmad-fr-nfr-review-gate`](bmad-fr-nfr-review-gate/SKILL.md) | loop the FR/NFR gate to zero new findings and publish its verdict | `plugin` | `fr-nfr-reviewer` in /rs-sdlc-review; the `GATE` verdict of /rs-sdlc-finish-pr |
| [`bounded-context-scaffolding`](bounded-context-scaffolding/SKILL.md) | name rules, the checklist C1–C12 with evidence targets and the context gate set for a new `<group>/<context>` | `plugin` | /rs-sdlc-new-context, which loads it directly; `rust-implementer` for the plan's scaffold story 1 |
| [`cache-management`](cache-management/SKILL.md) | a cache behind a port in infrastructure, expiry through the `Clock` port, invalidation by commands | `plugin` | `rust-implementer` |
| [`clean-architecture-llm`](clean-architecture-llm/SKILL.md) | which layer a type, module, dependency or model-provider integration belongs to | `plugin` | `rust-implementer`; `code-quality-reviewer` |
| [`code-organization`](code-organization/SKILL.md) | crate, module and file layout: `<context>-<layer>` crates, sibling `tests.rs`, no `mod.rs` | `plugin` | `rust-implementer`; `code-quality-reviewer` |
| [`code-review`](code-review/SKILL.md) | the review protocol, the finding format with its final fenced `json` block, the ledger and its PR comment | `plugin` | `code-quality-reviewer`, and /rs-sdlc-review for the lens ledgers and their PR comments, in every review iteration |
| [`complexity-management`](complexity-management/SKILL.md) | refactor a function to the `clippy.toml` limits, never raise them | `repo+plugin` | `rust-implementer`; `ci-fixer` for a red complexity check |
| [`configuration-management`](configuration-management/SKILL.md) | settings through the composition root's CLI and config modules, `.env` placeholders, one `docs/environment.md` row per variable | `plugin` | `rust-implementer` |
| [`database-migrations`](database-migrations/SKILL.md) | a reversible migration, migrate, rollback once, regenerate the offline query metadata, never edit an applied migration | `plugin` | `rust-implementer` in its serialized verify step |
| [`dependency-policy`](dependency-policy/SKILL.md) | dependency lanes, unused dependencies, per-layer allow-lists (a needed change escalates), workspace inheritance | `plugin` | `rust-implementer`; `ci-fixer` for a red dependency check or an advisory |
| [`documentation-creation`](documentation-creation/SKILL.md) | a new documentation page that passes the service's docs-check | `plugin` | `rust-implementer` |
| [`documentation-sync`](documentation-sync/SKILL.md) | keep pages in step with make targets, commands, variables, endpoints and workflow jobs | `repo+plugin` | `rust-implementer`; `ci-fixer` for a red docs check |
| [`implementing-ddd-architecture`](implementing-ddd-architecture/SKILL.md) | aggregates, value objects, domain events, domain errors and ports in pure domain crates | `plugin` | `rust-implementer` |
| [`load-testing`](load-testing/SKILL.md) | add or change a K6 scenario and its latency budget | `repo+plugin` | `rust-implementer`; `ci-fixer` for a red smoke run |
| [`observability-instrumentation`](observability-instrumentation/SKILL.md) | `tracing` spans and fields, `request_id` correlation, no PII in logs, health probes | `plugin` | `rust-implementer` |
| [`quality-standards`](quality-standards/SKILL.md) | the 12 quality bars, their sources and how each is measured | `repo+plugin` | `code-quality-reviewer` for the Q1–Q15 rows, in every review iteration |
| [`query-performance-analysis`](query-performance-analysis/SKILL.md) | query plans, indexes, N+1 avoidance and statement timeouts for sqlx queries | `plugin` | `rust-implementer`; `code-quality-reviewer` |
| [`rust-error-handling`](rust-error-handling/SKILL.md) | the four-level error model into `application/problem+json`, banned panics, the suppression policy | `plugin` | `rust-implementer`; `code-quality-reviewer`; `ci-fixer` for static-analysis findings |
| [`security-audit`](security-audit/SKILL.md) | attack-family audit of a Rust service, every candidate verified by reproduction, probes only through `common.sh http_probe` | `plugin` | `security-auditor` |
| [`service-scaffolding`](service-scaffolding/SKILL.md) | create a service from the template: steps S1–S14 and their traps | `plugin` | /rs-sdlc-new-service, which loads it directly |
| [`testing-workflow`](testing-workflow/SKILL.md) | unit, integration, end-to-end, coverage and mutation testing with deterministic seeds | `repo+plugin` | `rust-implementer`; `ci-fixer` for a red test check |
| [`verification-workflow`](verification-workflow/SKILL.md) | run the CI stage targets one per call in the background, container mode included | `repo+plugin` | `rust-implementer` in its verify step; /rs-sdlc-new-context for its gate set; `ci-fixer` to reproduce a check |

Triage, in short: the gate contract is: every skill verdict recorded, no silent skips. `/rs-sdlc-review` records one verdict per skill, 28 rows, `EXECUTE` with evidence or `NOT APPLICABLE` with a concrete reason, decided from the frontmatter and [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md) alone; bodies and supporting files load only on `EXECUTE`; `code-review` and `quality-standards` are `EXECUTE` in every iteration. The dispatching command names the executed skills in the agent's prompt, and the agent reads those bodies, a repository counterpart first.
