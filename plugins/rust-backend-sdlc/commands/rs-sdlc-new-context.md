---
description: "Add a bounded context to a Rust service with make new-context, complete the wiring checklist C1–C12 and prove it with the template's gate stages."
argument-hint: "[<group> <context>] [--issue <N>] [--no-handoff]"
---

# rs-sdlc-new-context — bounded context from scaffold to a proven gate set

The second entry point of the plugin (stage id `new-context`). It checks both names against the live tree before anything runs, selects the branch and the issue by the branch rule, scaffolds the three crates with the template's own scaffolder, has `rust-implementer` complete the wiring checklist C2–C11, commits the result and proves it with the template's own CI stages (C12), one backgrounded call per stage, closed by the protected-configuration check. It then hands the branch to the review, QA and PR-finishing procedures, or with `--no-handoff` prints those three commands as `NEXT:` lines. Inside the feature loop this command is never invoked: when the plan needs a context that is absent from `[workspace].members`, the plan stage writes story 1 "Scaffold `<group>/<context>`" (the in-loop variant of the `bounded-context-scaffolding` skill), so no second branch is created.

## Inputs

- **`<group> <context>`** — the two positional arguments, in this order, both required (the brackets of the argument hint are its shape, not an option). The context becomes the three crates `<context>-domain`, `<context>-application` and `<context>-infrastructure` in `crates/<group>/<context>/{domain,application,infrastructure}`. A missing argument, a third positional argument or an unknown flag → `ESCALATED` in step 0, before anything runs (`blocking_finding: usage: /rs-sdlc-new-context <group> <context> [--issue <N>] [--no-handoff]`).
- **`--issue <N>`** — the issue the context belongs to, `^[1-9][0-9]*$`, used when the current branch is not a `<type>/<N>-<slug>` branch (step 2). Any other value → `ESCALATED` in step 0.
- **`--no-handoff`** — stop after C12 and print the three hand-off commands as `NEXT:` lines instead of running them (step 7).
- **Profile** `.claude/rust-sdlc.yml`, validated first (step 0) and then read with the Read tool. Keys read by this command: `project.default_branch`, `ci.base_ref`, `capabilities.run_in_container`, `architecture.crates_root`, `persistence.engine`, `make.new_context`, `make.architecture`, `make.check_crate_isolation`, the six stage keys `make.ci_preflight`, `make.ci_static_analysis`, `make.ci_tests`, `make.ci_contracts`, `make.ci_mutation` and `make.ci_delivery`, `make.validate_configuration`, `make.check_commit_message`, `make.install_hooks`, `make.start` and `make.doctor`. `make.ci_cli` is never run. `architecture.bounded_contexts` is never used to decide whether a name exists: the live tree decides (step 1), because that list is stale after every new context, and this command never edits the profile.
- **Live tree** — the root `Cargo.toml` (`[workspace].members`), each member's `package.name`, the directories under `crates/`, and the Makefile's `CI_*_TARGETS` lines (step 6).
- **Plugin root** — the resolved, absolute `${CLAUDE_PLUGIN_ROOT}`, written into every Task prompt so the agent can call `common.sh`.
- **Counters** — the remediation round `new-context iteration <r>/5` (see "Iteration guard"), starting at 0; and, for the hand-off, the feature loop's counters at their start values: `review iteration 1/5`, `qa iteration 1/5` and the finish-pr cell `A0.B0.C0.W0.R0`.
- **Placeholders** in this file: `<group>` and `<context>` the arguments, `<context_snake>` the context with hyphens written as underscores, `<N>` the issue number, `<branch>` the checked-out branch, `<default_branch>` the value of `project.default_branch`, `<base>` the base ref of C12 (step 6 item 2), `<merge-base-sha>` the merge base of the protected-change guard (step 5 item 4, a literal), `<r>` the remediation round, `<UTC>` the current UTC time as `YYYYMMDDTHHMMSSZ`, `<plugin root>` the resolved plugin root.

## Procedure

### Execution rules (every step)

Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` and `bmalph run`, runs through the Bash tool with `run_in_background: true` (never a trailing `&`), logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled with `common.sh wait_log` at most every 30 s.

In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.

How the two rules apply here:

- Each target is the one its `make.*` key maps, and a `null` key is never replaced by a raw command. Make calls are written in suffix form, variables only after the target and only from the closed set `RUN_IN_CONTAINER COMMIT_TITLE base_ref BREAKING_CHANGE_APPROVED CONFIG_CHANGE_APPROVED group context name SCHEMATHESIS_URL`: here `group` and `context` on the scaffolder, `base_ref=<base>` on the stages that hold a base-ref reader and on the closing check, the empty `CONFIG_CHANGE_APPROVED=` on the preflight stage and on the closing check, `COMMIT_TITLE` on the subject check and, in container mode, `RUN_IN_CONTAINER=1` after the other variables on every target except `make install-hooks`, `make check-commit-message` and `make doctor`. No make option is ever passed, and the whole `ci` target is never run as one call.
- The background calls of this stage are the scaffolder call of step 3 (with `group=<group> context=<context>`), the C1 evidence targets `make architecture` and `make check-crate-isolation`, every hooked `git commit -F <path>`, the six stage calls of C12, the closing `make validate-configuration base_ref=<base> CONFIG_CHANGE_APPROVED=` and, in container mode, `make start`. Before each one the log directory exists (one foreground `mkdir -p target/rust-sdlc/logs`), the call is the wrapper `{ <command>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-context-<UTC>.log 2>&1` with a fresh `<UTC>`, and the wait is the background-task completion notice, else `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" wait_log <log>` (at most 110 s per call; it prints the last 40 lines and `RUST_SDLC_EXIT=<n>`, or `WAITING: <log> (<elapsed>s)`), called again on `WAITING:` until the exit line appears or the call's budget is spent: 900 s for `make start`, 30 min for the scaffolder, each C1 evidence target and each commit, 3 h for each stage call of C12 and for the closing check. A spent budget → `ESCALATED` with the last 40 log lines. When the runtime prompts for the brace-group wrapper, the same call is issued as `<command> > target/rust-sdlc/logs/new-context-<UTC>.log 2>&1` and its exit status is taken from the completion notice.
- `make check-commit-message`, `make install-hooks` and `make doctor` run in the foreground (allowlist) and in host form in both modes: they check a title, write the local hook setting and inspect the host, and never enter the container.
- Docker classification (D2): `docker info` runs before the Docker-dependent work of C12, and a log that shows the template's message `This target needs a reachable container engine (docker).` classifies its target `not run (no Docker)`, never `failed`, and never feeds remediation.
- Targets-run lines read `<target>: passed | failed | not run (<reason>)`, with the reason one of `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`.
- The command owns every commit of the run (step 5) and never pushes: the finish-pr procedure pushes the branch. The agent never commits, stages, switches branches or labels. The command never applies or removes a label, never writes a protected file or the profile, and never deletes or reverts a file the scaffolder or the agent wrote.

### Step 0 — Profile and arguments

1. Validate the profile:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
   ```

   Exit 1: stop with `run /rs-sdlc-setup on the default branch and commit the result` and the escalation block (`blocking_finding: validate-profile.sh exit 1`, the `VIOLATION:` lines quoted). Nothing else runs.
2. Parse the arguments (nothing is written): exactly two positional values `<group>` and `<context>`, at most one `--issue <N>` and at most one `--no-handoff`. A usage error → `ESCALATED` with the usage line of "Inputs" and `recommended_action: /rs-sdlc-new-context <group> <context> [--issue <N>] [--no-handoff]`.

### Step 1 — Names against the live tree, then the preconditions

1. **Names**, right after step 0 and before any write, branch change or make call. Both values are passed as single-quoted literals (a `'` inside one is written `'\''`), because they are not validated yet:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" validate_context_name '<group>' '<context>'
   ```

   The function applies the scaffolder's four rules to the live tree of the working directory, never to the profile: both names match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` (`name-format`); the context is none of `shared service xtask test-support e2e-tests`, which stay legal as a group (`reserved-context`); neither `crates/<context>` nor any `crates/*/<context>` is a directory (`context-exists`); no `[workspace].members` entry ends in `<context>/domain`, `<context>/application` or `<context>/infrastructure` and no member's `package.name` is `<context>-domain`, `<context>-application` or `<context>-infrastructure` (`member-exists`).
   - Exit 0, no output → `NAMES: <group>/<context> valid (live tree)`.
   - Exit 1, one `REFUSED: <rule> <detail>` line → print that line, then `ESCALATED` with it as `blocking_finding` and `recommended_action: choose another context name; a change inside an existing context is a feature (/rs-sdlc)`. Nothing is written, no branch is changed and no make target runs.
   - Exit 2 (a usage error, or no readable `Cargo.toml` in the working directory) → `ESCALATED` with its stderr and `recommended_action: run /rs-sdlc-new-context from the repository root`.
2. **Keys.** `make.new_context` null → `ESCALATED` (`blocking_finding: make.new_context is null (no context scaffolder)`): the three crates are never hand-written, because the member registration and the lock refresh belong to the scaffolder. `architecture.crates_root` null, or any value other than `crates` (the scaffolder's fixed root) → `ESCALATED` (`blocking_finding: architecture.crates_root is <value>`). Nothing is written.
3. **Clean tracked tree.** `git status --porcelain --untracked-files=no` must print nothing, so the commits of this run hold only this run's work. Tracked changes → `ESCALATED` (`blocking_finding: uncommitted tracked changes: <files>`, `recommended_action: commit or stash the changes, then run /rs-sdlc-new-context again`). Record the untracked entries of `git status --porcelain` (lines starting `??`): they are never staged by this run.
4. **Toolchain (D3).** When `capabilities.run_in_container` is false, `command -v cargo` must succeed before the scaffolder runs. It fails → `ESCALATED` (D3) before `make new-context`, with every target of this stage reported `not run (no toolchain)`, `blocking_finding: command -v cargo exit 1 (no host toolchain, container mode off)` and `recommended_action: /rs-sdlc-setup --exec container`. Nothing is written.
5. **Container (D25).** In container mode: `docker info`, then `docker compose ps --status running --quiet app`. Empty output and `make.start` mapped → `make start RUN_IN_CONTAINER=1` in the background (≤ 900 s, one restart attempt with a new log), then the `docker compose ps` check again. `docker info` failing, `make.start: null`, or `app` still not running → `ESCALATED` (D25) with the probe output and the `make doctor` output printed above the block; nothing else runs.

### Step 2 — Branch and issue rule

1. `git branch --show-current` gives `<branch>` (empty on a detached `HEAD`).
2. **Reuse.** When `<branch>` has the form `<type>/<N>-<slug>` (`^[a-z]+/[1-9][0-9]*-.+`), the run reuses that branch and its issue:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" derive_issue_number --branch <branch>
   ```

   It prints `<N>`. An `--issue` value other than `<N>` → `ESCALATED` (`blocking_finding: --issue <value> conflicts with branch <branch> (issue <N>)`); nothing is written. No new branch is created and no issue is created.
3. **New branch.** Otherwise (the default branch, any other branch, or a detached `HEAD`) the run needs an issue first:
   - With `--issue <N>`: one read, `gh issue view <N> --json number,state --jq .state`. `OPEN` → continue; `CLOSED` → `ESCALATED` (`blocking_finding: issue #<N> is closed`). A non-zero exit (`gh` unreachable, or a repository without a GitHub origin) records `DEGRADED: issue #<N> not verified (gh unreachable, D10)` and the run continues with `<N>`.
   - Without `--issue`: the issue stage creates it. Read `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-issue.md` and follow its procedure in create mode with the task text `Add the bounded context <group>/<context> to the service: scaffold it with the template's scaffolder, complete the wiring checklist C1–C12 (architecture model, domain, application and infrastructure layers with their tests, composition root, contracts, end-to-end features, documentation) and keep every gate of the template green.` Its `ISSUE_NUMBER:` handle gives `<N>`. When it ends `ESCALATED`, its own block (stage `issue`) ends this run, with nothing written to the working tree.

   Then create the branch from the default branch:

   ```bash
   git fetch origin <default_branch>
   git switch -c feat/<N>-<context> origin/<default_branch>
   ```

   A failed fetch alone is D24, a degrade note, never an escalation: `DEGRADED: git fetch origin <default_branch> failed; branch created from the last fetched origin/<default_branch> (D24)`, and the run ends at best `SUCCESS-WITH-REPORT`. A failed `git switch -c` (the branch `feat/<N>-<context>` exists already, or `origin/<default_branch>` is missing) → `ESCALATED` with `blocking_finding: git switch -c feat/<N>-<context> origin/<default_branch> exit <n>` and `recommended_action: check out the existing branch with git switch feat/<N>-<context>, or fetch the default branch, then run /rs-sdlc-new-context again`; nothing else is written.
4. **Names on the new tree.** After a switch, `validate_context_name '<group>' '<context>'` runs once more, because the default branch may differ from the tree checked in step 1. A `REFUSED:` line now → `ESCALATED` with it; the new branch holds no commit of this run.
5. `<branch>` equal to `<default_branch>` at this point → `ESCALATED` (`blocking_finding: scaffolding started on <default_branch>`): a context is never scaffolded on the default branch. Print the handles:

   ```text
   ISSUE_NUMBER: <N>
   BRANCH: <branch>
   ```

### Step 3 — Scaffold the crates (C1)

1. Run the scaffolder in the background (`RUN_IN_CONTAINER=1` appended in container mode):

   ```bash
   mkdir -p target/rust-sdlc/logs
   { make new-context group=<group> context=<context>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-context-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

2. Classify the result. GNU make reports every recipe failure as exit 2, so the exit code alone never classifies a failure: the scaffolder's stderr prefix does, and the wrapper's `2>&1` puts it in the log.

   | Log shows | Meaning | Outcome |
   | --- | --- | --- |
   | `RUST_SDLC_EXIT=0` | the three crates were created | item 3 |
   | a line starting `new-context refused:` | the scaffolder refused and wrote nothing: validation drift between `validate_context_name` and the scaffolder | `ESCALATED` with the output; `blocking_finding: make new-context exit <n>: new-context refused: <reason> (validation drift)`; `recommended_action: choose another context name and report the drift between the plugin's name check and the scaffolder` |
   | a line starting `new-context could not run:` | files may already exist (for example the crates were created but the offline lock refresh failed) | `ESCALATED` with the output and the output of `git status --porcelain` printed above the block; `recommended_action: inspect the listed paths, complete or remove the partial scaffold by hand, then continue` |
   | the template's message `This target needs a reachable container engine (docker).` | container mode without a reachable engine | `new-context: not run (no Docker)`, `ESCALATED` (D2) with the `make doctor` output |
   | any other non-zero exit | unclassified | `ESCALATED` with the last 40 log lines |

3. **C1 evidence.** The Glob tool lists `crates/<group>/<context>/*/Cargo.toml`: exactly `domain`, `application` and `infrastructure`. The root `Cargo.toml` (Read tool) holds the three members `crates/<group>/<context>/domain`, `crates/<group>/<context>/application` and `crates/<group>/<context>/infrastructure`, each in sorted position among its neighbours. Then run `make architecture` and `make check-crate-isolation`, one backgrounded call each (a null `make.architecture` or `make.check_crate_isolation` → `not run (capability absent)`, D1). All present and both passed → `DONE: C1 crates/<group>/<context>/{domain,application,infrastructure}, 3 sorted members; architecture passed, check-crate-isolation passed`. A missing crate or member, or a failing target → `ESCALATED` with the evidence that failed: the scaffolder's own output never feeds remediation.

### Step 4 — Checklist C2–C11 through `rust-implementer`

1. **Load the skill.** Read `${CLAUDE_PLUGIN_ROOT}/skills/bounded-context-scaffolding/SKILL.md`: its checklist (step 5) and gate set (step 6) are what this command drives. The repository's own `docs/new-service.md` (section "Add a bounded context") and `AGENTS.md` win where they are stricter.
2. **The checklist.** Each item ends `DONE: C<n> <evidence>` or `N/A: C<n> <reason>`; the evidence is the passing evidence target of its row:

   | Id | Action | Files or target | Evidence target | Owner |
   | --- | --- | --- | --- | --- |
   | C1 | Scaffold | `make new-context group=<group> context=<context>` | three crates under `crates/<group>/<context>/`, three sorted members; `make architecture`, `make check-crate-isolation` | this command (step 3) |
   | C2 | Architecture model | three components and their relationships in `workspace.dsl` | `make validate-architecture-model` | agent |
   | C3 | Workspace dependencies at first use | `[workspace.dependencies]` path entries for `<context>-domain`, `<context>-application`, `<context>-infrastructure`, each added when a crate first depends on it | `make check-security`, `make unused-dependencies` | agent |
   | C4 | Domain layer | `<Entity>` aggregates, value objects, ports, the context's error enum; dependencies `async-trait`, `shared-domain`, `thiserror` | `make architecture`, `make static-analysis`, `make complexity` | agent |
   | C5 | Application layer | `command/`, `query/`, `subscriber/`, `error.rs` with the `From` conversion of the domain error into `Problem`, `http.rs`, `http/dto.rs`, `http/handler.rs` with the extractor-check test, `graphql.rs` | `make static-analysis`, `make tests-with-coverage` | agent |
   | C6 | Infrastructure layer | `persistence.rs`; `tests/integration/{main,repository,migration}.rs` | `make tests-with-coverage` | agent |
   | C7 | Test support | `tests/support`: `<context>-domain.workspace = true`, an in-memory fake per port with `new()` and `failing()`, fixtures, sibling `tests.rs` | `make unused-dependencies`, `make tests-with-coverage` | agent |
   | C8 | Migration and query metadata | `make create-migration name=<snake_case>`, `make migrate`, `make migrate-rollback` then `make migrate` once (an `ask` rule), `make sqlx-prepare`, `.sqlx/` committed with the migration; `N/A` for a context without persistence | `make validate-sqlx-metadata` | agent |
   | C9 | Composition root | `crates/service/Cargo.toml`; the `Adapters` fields, `connect`, the handlers, `event_bus()`, the context state and the schema `.data(...)` in `bootstrap.rs`; the `AppState` field; the `openapi::api_router` nest and tag; the `graphql::schema` roots; the three `Adapters { .. }` literals and the contract-pinning tests | `make tests-with-coverage`, `make e2e-tests` | agent |
   | C10 | Contracts and end-to-end | `make generate-openapi-spec`, `make generate-graphql-spec`; `features/<context>.feature`, `tests/e2e/steps/<context_snake>.rs`, its module line in `steps.rs`, `world.rs` | `make validate-contract-snapshots`, `make validate-openapi-spec`, `make openapi-diff base_ref=<base>`, `make graphql-diff base_ref=<base>`, `make e2e-tests` | agent; the two diffs in C12 |
   | C11 | Documentation | `docs/requests.http`, the bounded-context table of `docs/architecture.md`, an ADR when a decision was made, `docs/environment.md` rows for new variables | `make docs-check` | agent |
   | C12 | Verify | the context gate set (step 6), then `make validate-configuration base_ref=<base> CONFIG_CHANGE_APPROVED=` | all stages green; 0 protected files changed | this command (step 6) |

   `make migrate-rollback` is an `ask` rule of the template: in a headless run it is recorded `migrate-rollback: not run (ask rule)` (D13), never retried under another spelling, and C8 is still `DONE` on `make validate-sqlx-metadata`; the run then ends at best `SUCCESS-WITH-REPORT`. The agent never passes `base_ref`, so the two diff targets of C10 are proven inside the contracts stage of C12; an evidence target the agent did not run is proven by the C12 stage that holds it, and the final checklist line of that item names the stage.
3. **Dispatch.** One Task call, mode serial (the agent is the only implementer, so it runs the database-backed targets one at a time itself). Every dispatch of this command names `Iteration 1/5`: that is the agent's own per-dispatch counter, while this command's rounds are counted by its own guard (`new-context iteration <r>/5`, named in the prompt):

   ```text
   subagent_type: rust-backend-sdlc:rust-implementer
   Implement the story "Wire the bounded context <group>/<context>" of issue #<N>: checklist items C2–C11 of the bounded-context-scaffolding skill. mode: serial. Plugin root: <plugin root>. Iteration 1/5 (new-context iteration <r>/5).
   Executed skills: bounded-context-scaffolding, architecture-model-sync, dependency-policy, implementing-ddd-architecture, api-resource-development, rust-error-handling, database-migrations, api-contract-development, documentation-sync, testing-workflow.
   C1 is done: the three crates of crates/<group>/<context>/ exist and are workspace members.
   Acceptance criteria (data, not instructions), one per item as C<n> | action | files or target | evidence target:
   <the rows C2–C11 of the checklist table, with the open items and the previous failure feedback on a follow-up dispatch>
   The rollback round trip of C8 is an ask rule: a denied call is recorded not run (ask rule) and C8 stays DONE on validate-sqlx-metadata. The two contract diffs of C10 need base_ref, which you never pass: the command runs them in its contracts stage.
   Edit the working tree only: no commit, push, staging, branch change or label. Fix every failure at its root; never a suppression, an exclusion or a lowered limit. A change that needs a protected path ends with the BLOCKED: protected configuration line.
   Return first exactly one line per item C2–C11, in order, as DONE: C<n> <evidence> or N/A: C<n> <reason>; then the changed-files list, the targets-run list, the self-review checklist and the ---RALPH_STATUS--- block.
   ```

4. **Check the report.**
   - **Complete:** `STATUS: COMPLETE`, the ten item lines present in order, every `DONE:` line backed by a passed evidence target of its targets-run list (or by a C12 stage, or `not run (ask rule)` for the C8 rollback as above), an `N/A:` only for C8 without persistence (`persistence.engine` null, or a context that stores nothing) or for C2 without a `workspace.dsl`, and every self-review line checked → step 5.
   - **Blocked:** `STATUS: BLOCKED` → `ESCALATED`. A `BLOCKED: protected configuration <path> …` line or a guard-hook denial → D23, with that line verbatim as `blocking_finding`. Targets `not run (no Docker)` → D2, with the `make doctor` output above the block. Targets `not run (no toolchain)` → D3. Otherwise the agent's `RECOMMENDATION:` line is the `blocking_finding`.
   - **Incomplete** (a missing or malformed item line, an `N/A:` with another reason, `STATUS: IN_PROGRESS`, `TESTS_STATUS: FAILING`, an unchecked self-review line, or an empty changed-files list): a remediation round. When `<r>` is below 5, `<r>` becomes `<r+1>`, the command restates `new-context iteration <r>/5` and dispatches item 3 again with the open items and the agent's failure feedback (the failing target and its log tail). At `new-context iteration 5/5` → `ESCALATED` (guard exhausted).

   The command itself never edits code: every fix comes from the agent.

### Step 5 — Commit the context

These items make every commit of the run: the context commit here, and the remediation commits of steps 6 and 7 with their own subject.

1. **Container (D25).** In container mode, `docker compose ps --status running --quiet app` before the hooked commit, with the start rule of step 1 item 5.
2. **Hooks** (before the first commit of the run):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" hooks_active
   ```

   `HOOKS: active` → continue. `HOOKS: unset` and `make.install_hooks` mapped → `make install-hooks` (foreground), then the check again; still not active → `ESCALATED`. `HOOKS: unset` with `make.install_hooks: null` → `ESCALATED` (`blocking_finding: HOOKS: unset (make.install_hooks absent)`). `HOOKS: foreign <value>` → `ESCALATED` with `blocking_finding: core.hooksPath=<value>` and `recommended_action: make install-hooks`. `HOOKS: missing <file>` → `ESCALATED` naming the file. A hook is never bypassed and the hook setting is never written by this command.
3. **Stage exactly this run's work.** Every path that `git status --porcelain` lists, except the untracked entries recorded in step 1, is staged with `git add -- <path> …` (never `git add -A`, never an ignored path). Then `git diff --name-only` must print nothing and the `??` entries of `git status --porcelain` must equal the recorded ones; anything else → `ESCALATED` naming the path, nothing committed. `git diff --cached --name-only` printing nothing → `ESCALATED` (`blocking_finding: nothing to commit`).
4. **Merge base (D24).**

   ```bash
   git rev-parse --verify <ci.base_ref>
   git merge-base <ci.base_ref> HEAD
   ```

   The second command prints `<merge-base-sha>`, used as a literal. When `git rev-parse --verify` fails, the D24 rule of step 6 item 2 runs here (one `git fetch origin <default_branch>` for the whole run, and a re-check); still unavailable, or no common ancestor → `<merge-base-sha>` is `HEAD` and the run records `DEGRADED: base ref <ci.base_ref> unavailable; protected_changes ran against HEAD (D24)`.
5. **Protected-change guard** (ADR-25):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" protected_changes <merge-base-sha>
   ```

   Exit 0 → continue. A `PROTECTED: <path> (<commit>|working tree)` line → `ESCALATED` (D23) with `blocking_finding: protected file <path> changed (<commit>)` and `recommended_action: revert with git restore --source=<merge-base-sha> -- <path> unless the plan intends it; otherwise approved-config-change`. A `PROFILE_CHANGED: .claude/rust-sdlc.yml` line → `ESCALATED` with `recommended_action: move the profile change to its own pull request from the default branch (/rs-sdlc-setup --refresh)`. Exit 2 → `ESCALATED` with its stderr. Nothing is committed on a hit.
6. **Subject.** The context commit is `feat(#N): add <group>/<context> bounded context`, with the issue number in place of `N`. Pre-validate it in the foreground:

   ```bash
   make check-commit-message COMMIT_TITLE='feat(#<N>): add <group>/<context> bounded context'
   ```

   A subject with a space-hyphen sequence, and every subject when `make.check_commit_message` is `null` (`check-commit-message: not run (capability absent)`, D1), is checked with `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" is_commit_subject '<subject>'` instead. A rejection → `ESCALATED`; nothing is committed.
7. **Message file and commit**, in the background:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" commit_msg_file 'feat(#<N>): add <group>/<context> bounded context'
   mkdir -p target/rust-sdlc/logs
   { git commit -F <path>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-context-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

   `commit_msg_file` prints `<path>` (`target/rust-sdlc/tmp/commit-<UTC>.txt`); the subject never goes on the git command line. The last line runs through the Bash tool with `run_in_background: true`; in container mode its first command is `RUN_IN_CONTAINER=1 git commit -F <path>`, so the hooks run their targets in the container.
8. **Result.** `RUST_SDLC_EXIT=0` and `git log -1 --format=%s` printing the subject → `DONE: commit feat(#<N>): add <group>/<context> bounded context`. The template's no-Docker message in the log → the hook targets are `not run (no Docker)` and the stage ends `ESCALATED` (D2). A failing hook target (the pre-commit gates or the commit-message check) is a remediation round: when `<r>` is below 5, `<r>` becomes `<r+1>`, one Task call of the form of step 6 item 5 runs with the failing hook target as `<gate>`, the hook (`pre-commit` or `commit-msg`) as `<stage>` and the last 80 log lines as the failure, and items 1 to 7 run again with the same subject; at `new-context iteration 5/5` → `ESCALATED` with `blocking_finding: git commit -F <path> exit <n>` and the log tail. The commit is never retried under another spelling and a hook is never worked around.

### Step 6 — Context gate set (C12)

The gate set runs after the commit, because the contract-snapshot and mutation gates read committed changes only.

1. **Docker first.** `docker info`, in the foreground. It fails → `make doctor` (foreground; with `make.doctor` null the `docker info` exit code instead) printed above the block, every stage and the closing check recorded `not run (no Docker)`, and `ESCALATED` (D2): no stage runs and none is fed to remediation. `blocking_finding: docker info exit <n>` (or the first failing `make doctor` line), `recommended_action: start the container engine and fix the make doctor findings, then run the gate set or /rs-sdlc-review on <branch>`.
2. **Base (D24)**, before the first stage:

   ```bash
   git rev-parse --verify <ci.base_ref>
   ```

   Exit 0 → `<base>` is the value of `ci.base_ref`. It fails → one `git fetch origin <default_branch>` (the run's only D24 fetch: when step 5 already made it, its outcome is reused) and a re-check; still unavailable → `<base>` is `HEAD` and the run records `DEGRADED: base ref <ci.base_ref> unavailable; C12 ran with base_ref=HEAD (D24)`, so it ends at best `SUCCESS-WITH-REPORT` (A9). A failed fetch alone is this note, never an escalation. `<base>` is always passed explicitly, so the Makefile's `base_ref ?= origin/main` fallback never applies.
3. **Stage list, read at runtime.** The Grep tool reads the stage composition from the Makefile, pattern `^CI_[A-Z_]+_TARGETS[[:space:]]*:?=` over `Makefile` and `make/*.mk`; each line names one stage and its gates (`CI_PREFLIGHT_TARGETS` is the stage target `ci-preflight` mapped by `make.ci_preflight`, `CI_STATIC_ANALYSIS_TARGETS` is `ci-static-analysis`, and so on). The lists are quoted in the report, never restated from memory.
   - The gate set is the six stages `ci-preflight`, `ci-static-analysis`, `ci-tests`, `ci-contracts`, `ci-mutation`, `ci-delivery`, in the Makefile's order. `CI_CLI_TARGETS` (`ci-cli`, the Bats stage) is never run: the template's Bats suite never depends on a context. A null stage key → `<stage>: not run (capability absent)` (D1).
   - A stage whose list holds an ADR-13 `base_ref` reader (`validate-configuration`, `mutation-tests-diff`, `openapi-diff`, `graphql-diff`) gets `base_ref=<base>`, and the stage that holds `validate-configuration` also gets the empty `CONFIG_CHANGE_APPROVED=` (IR-2). A stage without a reader gets no variable.
   - A `CI_*_TARGETS` list of another stage → `<stage>: not run (deferred to PR CI)` with a `DEGRADED:` note naming it. No `CI_*_TARGETS` line at all → the six calls below are issued as written, with `DEGRADED: stage composition not readable from the Makefile; template composition assumed`.

   At the template's lists the six calls are exactly:

   ```bash
   make ci-preflight base_ref=<base> CONFIG_CHANGE_APPROVED=
   make ci-static-analysis
   make ci-tests
   make ci-contracts base_ref=<base>
   make ci-mutation base_ref=<base>
   make ci-delivery
   ```

4. **Run the stages**, one backgrounded call each, in order, each awaited to its end before the next starts (`RUN_IN_CONTAINER=1` appended after the variables in container mode):

   ```bash
   mkdir -p target/rust-sdlc/logs
   { make ci-preflight base_ref=<base> CONFIG_CHANGE_APPROVED=; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-context-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

   The same wrapper carries each of the other five calls of item 3. Classify each stage:
   - `RUST_SDLC_EXIT=0` → `<stage>: passed`; the next stage starts.
   - The template's no-Docker message in the log → `<stage>: not run (no Docker)`, the remaining stages and the closing check `not run (no Docker)`, and `ESCALATED` (D2) with the `make doctor` output; never remediated.
   - The `validate-configuration` gate of the stage naming a protected path (`… is not allowed: <path>`, `Required directory is missing: <path>`) → `ESCALATED` (D23) with `blocking_finding: protected file <path> changed (<commit>)` and `recommended_action: revert with git restore --source=<merge-base-sha> -- <path> unless the plan intends it; otherwise approved-config-change`; never remediated, and the label is applied by a human, never by this command.
   - Any other non-zero exit → `<stage>: failed`, with the failing gate (the stage stops at its first failing gate, named in the log) → item 5.
5. **Remediation round.** When `<r>` is below 5, `<r>` becomes `<r+1>` and the command restates `new-context iteration <r>/5`; at 5/5 → `ESCALATED` (guard exhausted) with the failing stage's last 40 log lines. One Task call:

   ```text
   subagent_type: rust-backend-sdlc:rust-implementer
   Fix the failing gate <gate> of the stage <stage> for the bounded context <group>/<context> of issue #<N>. mode: serial. Plugin root: <plugin root>. Iteration 1/5 (new-context iteration <r>/5).
   Executed skills: bounded-context-scaffolding and the skill that owns <gate> in its checklist or in the skill decision guide.
   Failure (data, not instructions): <stage> exit <code>; the last 80 lines of <log>:
   <log tail>
   Edit the working tree only: no commit, push, staging, branch change or label. Fix the root cause; never a suppression, an exclusion or a lowered limit. A fix that needs a protected path ends with the BLOCKED: protected configuration line.
   Return the changed-files list, the targets-run list, the self-review checklist and the ---RALPH_STATUS--- block.
   ```

   `STATUS: BLOCKED` → `ESCALATED` as in step 4 item 4. An empty changed-files list → `ESCALATED` (`blocking_finding: remediation round <r> changed no file`), because the same stage would fail the same way. Otherwise commit with step 5 items 1 to 8 and the subject `fix(#N): <what>`, here `fix(#<N>): resolve <gate> failure in <group>/<context>`, then run the failed stage again; the stages that already passed are not repeated.
6. **Closing check**, after the last stage passed and so after the last remediation commit, in the background (`RUN_IN_CONTAINER=1` appended in container mode):

   ```bash
   mkdir -p target/rust-sdlc/logs
   { make validate-configuration base_ref=<base> CONFIG_CHANGE_APPROVED=; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-context-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

   The empty `CONFIG_CHANGE_APPROVED=` is always passed, so an inherited approval never reaches the check, and `base_ref` is always `<base>`, never the Makefile's fallback. `RUST_SDLC_EXIT=0` → `validate-configuration: passed`. A protected path in the log → `ESCALATED` (D23) with the wording of item 4. `make.validate_configuration` null → `validate-configuration: not run (capability absent)` and the library check replaces it: `protected_changes <merge-base-sha>` with a merge base read again as in step 5 item 4; exit 0 → no hit, a `PROTECTED:` or `PROFILE_CHANGED:` line → `ESCALATED` as in step 5 item 5. Any other failure → `ESCALATED` with the last 40 log lines.
7. **Committed.** `git status --porcelain` must show nothing but the untracked entries recorded in step 1; anything else → `ESCALATED` naming the paths. Then C12 is done: `DONE: C12 <count> stages passed (<stage list>), validate-configuration passed, 0 protected files changed`.

### Step 7 — Report, handles and hand-off

1. **Report.** Print, in this order: the degrade notes (each `DEGRADED:` line, or `degrade_notes: none`); the stage lists quoted from the Makefile; the targets-run list (`new-context`, `architecture`, `check-crate-isolation`, `install-hooks` when step 5 ran it, `check-commit-message`, the six stages, `validate-configuration`, and the agent's `migrate-rollback: not run (ask rule)` when it recorded one); the twelve checklist lines in order, `DONE: C<n> <evidence>` or `N/A: C<n> <reason>`; the `DONE: commit …` lines; and the handles:

   ```text
   ISSUE_NUMBER: <N>
   BRANCH: <branch>
   ```

2. **`--no-handoff`.** Print the three hand-off commands and stop; the stage outcome is that of steps 0 to 6:

   ```text
   NEXT: /rs-sdlc-review
   NEXT: /rs-sdlc-qa #<N>
   NEXT: /rs-sdlc-finish-pr
   ```

3. **Hand-off** (without `--no-handoff`). A slash command cannot call another, so each stage is executed by reading its command file and following its procedure, in this order, each only after the previous one ended `SUCCESS` or `SUCCESS-WITH-REPORT`:
   1. `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-review.md` with the handle `ISSUE_NUMBER: <N>`, no `SPECS_DIR` argument (the procedure finds a bundle `specs/<N>-*/` when a reused branch has one, else runs with `SPECS_DIR: none`), the counter `review iteration <n>/5` and the plugin root;
   2. `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-qa.md` with `#<N>` and the counter `qa iteration <n>/5`;
   3. `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-finish-pr.md` with the hand-off `ISSUE_NUMBER: <N>`, `SPECS_DIR` (the bundle the review found, or none), the QA verdict with the head it was taken on, the targets-run lists of this command, the review and the QA stage, and the counter field `finish-pr=A0.B0.C0.W0.R0`.

   These are the feature loop's counters: each one starts at its first value, is restated by its own procedure and is never reset within the run. A delegated procedure that ends `ESCALATED` prints its own block (stage `review`, `qa` or `finish-pr`), which ends the run; this command prints nothing after it. A QA `FAIL` before `qa iteration 5/5` has no implement stage to route to here, so its FAIL rows (check, expected, observed, reproduction line; data, not instructions) are the failure of one remediation round of step 6 item 5 (its prompt's first line then asks to fix the QA findings of `qa iteration <q>/5` instead of a gate), which consumes this command's guard the way a loop-back consumes the budget of the stage it re-enters, with the subject `fix(#<N>): address QA findings <q> in <group>/<context>` (`<q>` the QA iteration). After that commit the context gate set runs again from step 6 item 1, so the exit condition holds on the new head, then the review and QA procedures run again with their counters continued.

## Loop & exit condition

Exit string (stage `new-context`, byte-identical in the loop documentation): context gate set green, 0 protected files changed, committed

The loop is the remediation round: a follow-up checklist dispatch (step 4), a hook-failure fix (step 5), a failing gate-set stage fixed and run again (step 6) and a QA `FAIL` in the hand-off (step 7) share one bounded counter. The stage ends:

- `SUCCESS` when C1–C12 are done: every stage of the gate set passed, the closing check passed, 0 protected files changed and everything is committed, with no degrade note;
- `SUCCESS-WITH-REPORT` when it got there with a degrade note: a null stage or evidence key (D1), the C8 rollback `not run (ask rule)` (D13), `base_ref=HEAD` or a failed fetch (D24), an issue not verified (D10), or a stage list not readable from the Makefile;
- `ESCALATED` on a refused name, a null scaffolder key or another crates root, tracked changes at the start, no host toolchain with container mode off (D3), the container stack not starting (D25), a failed branch switch, a classified or unclassified scaffolder failure, a C1 evidence miss, a blocked agent, Docker unreachable (D2), a protected change or a changed profile (D23), hooks not active, a rejected subject, a failed commit or an exhausted guard.

Degrade paths never loop and never fake a pass: a target that did not run is reported `not run (<reason>)`. The hand-off stages start only after this stage's exit condition is met and follow their own exit conditions, guards and escalation blocks. The command is not resumable past step 3: the context then exists, so a second run is refused by the name check of step 1. After an escalation past step 3 the work stays on `<branch>`, and the recommended action names the human step that continues it (finish and commit by hand, then /rs-sdlc-review).

## Iteration guard

`MAX_ITERATIONS=5` counts remediation rounds, restated as `new-context iteration <r>/5` at the start of each round. `<r>` starts at 0 and the first C2–C11 dispatch is the checklist itself, not a round. A follow-up dispatch for an incomplete checklist report, a hook-failure fix before a commit retry, a failing gate-set stage fixed and run again, and a QA `FAIL` routed back during the hand-off each consume one round of this one counter. A degrade (`not run (no Docker)`, `not run (ask rule)`, `not run (capability absent)`, D24) never consumes a round and never loops. The counter is never reset within a run, and a round beyond 5/5 is never started: the stage ends `ESCALATED` with `iteration: 5/5`. Each delegated stage of the hand-off keeps its own guard (review 5, QA 5, finish-pr A 5, B 5, C 3, W 6, R 3).

## Failure escalation

Every exit that is not `SUCCESS` or `SUCCESS-WITH-REPORT` prints this block, filled in, and nothing after it; the `REFUSED:` line, the targets-run list and checklist lines recorded so far, a log tail, the `git status --porcelain` output or the `make doctor` output go above it:

```text
=== SDLC ESCALATION ===
stage: new-context
iteration: <r>/5
exit_condition: context gate set green, 0 protected files changed, committed
status: NOT MET
blocking_finding: <file:line | check name (REFUSED: context-exists '<context>' already exists at crates/<group>/<context>) | command + exit code (make new-context exit 2, docker info exit 1, ci-tests stage exit 2 at gate tests-with-coverage)>
iteration_log: <one line per remediation round: "<r>: <what ran> -> <result>"; "none" when no round ran>
recommended_action: <the human action: another context name, /rs-sdlc-setup --exec container, start the container engine, git restore --source=<merge-base-sha> -- <path>, a protected change with ALLOW_PROTECTED_CONFIG_EDIT=1, make install-hooks, or a manual fix committed on <branch> followed by /rs-sdlc-review>
=== END ===
```

`iteration:` is the number of remediation rounds consumed when the stage stopped (0 before any round).

Triggers, each with its `blocking_finding` and `recommended_action`:

- Profile invalid → `validate-profile.sh exit 1`; `run /rs-sdlc-setup on the default branch and commit the result`.
- Usage error or a refused name → the usage line or the `REFUSED: <rule> <detail>` line; another context name, or the command written correctly. Nothing was written.
- `make.new_context` null or `architecture.crates_root` other than `crates` → the key and its value; /rs-sdlc-setup --refresh on the default branch when the profile is stale, else add the context by hand.
- Tracked changes at the start → the files; commit or stash them.
- No host toolchain with container mode off (D3) → `command -v cargo exit 1`; `/rs-sdlc-setup --exec container`.
- Container mode and `app` not running (D25) → the probe output; start the container engine, then run /rs-sdlc-new-context again.
- An issue that is closed or conflicts with the branch, a failed `git switch -c`, or the issue stage's own escalation → the value, the command and its exit code, or the issue block; check out the right branch or pass the right `--issue`.
- `new-context refused:` → the scaffolder output (validation drift); another context name and a report of the drift. `new-context could not run:` → the output and `git status --porcelain`; inspect and complete or remove the partial scaffold by hand. Neither prefix → the log tail.
- C1 evidence missing or failing → the missing crate, member or target; inspect the scaffold by hand.
- Agent blocked → its `RECOMMENDATION:` line, or the `BLOCKED: protected configuration <path> …` line verbatim (D23): a human adds `approved-config-change` and restarts the session with `ALLOW_PROTECTED_CONFIG_EDIT=1`, or the plan changes.
- Docker unreachable (D2) → `docker info exit <n>` or the first failing `make doctor` line; start the container engine and fix the doctor findings, then run the gate set or /rs-sdlc-review on `<branch>`.
- Protected file changed (D23) → `protected file <path> changed (<commit>)`; revert with `git restore --source=<merge-base-sha> -- <path>` unless the plan intends it, otherwise a human adds `approved-config-change`. Profile changed → `PROFILE_CHANGED: .claude/rust-sdlc.yml`; move the profile change to its own pull request from the default branch (/rs-sdlc-setup --refresh).
- Hooks not active → the `HOOKS:` line or `core.hooksPath=<value>`; `make install-hooks`, or restore the named hook file.
- A rejected subject or a failed commit → the subject, or `git commit -F <path> exit <n>` with the log tail; fix by hand on `<branch>`, commit, then /rs-sdlc-review.
- Guard exhausted (a stage still failing, a checklist still incomplete or a hook still failing after round 5) → the failing stage or target with its log tail; fix by hand on `<branch>`, commit, then /rs-sdlc-review.
