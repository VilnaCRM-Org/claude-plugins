---
description: "Stage the planning bundle for bmalph and run the Ralph loop with the claude-code driver until every story is done with valid commit subjects and green coverage."
argument-hint: "[SPECS_DIR]"
---

# rs-sdlc-implement — planning bundle to implemented stories through bmalph and Ralph

Stage 3 of the feature loop (stage id `implement`). It stages the committed planning bundle for bmalph, turns it into Ralph's fix plan without ever forcing bmalph, overrides the build and git instructions bmalph writes for Ralph, and runs the Ralph loop with the claude-code driver as the only implementer. After the loop it proves the result itself: every commit subject on the branch, the protected configuration and the coverage floor. Ralph's circuit breaker is honoured as a terminal safety signal and is never reset. The /rs-sdlc orchestrator runs this procedure after the plan stage and again after a QA `FAIL` (the loop-back adds a fix story to the bundle); it can also run on its own on a feature branch.

## Inputs

- **`SPECS_DIR`** — the planning bundle `specs/<N>-<slug>/` committed by the plan stage. Without the argument: the `SPECS_DIR:` handle the orchestrator passes, else the single directory `specs/<N>-*/` for the `<N>` of the current feature branch `<type>/<N>-…` (step 0). The directory name gives the issue number `<N>` and the bundle slug `<slug>` (the plan stage's kebab title), and with them the state cache `target/rust-sdlc/state/<N>-<slug>.json`.
- **Profile** `.claude/rust-sdlc.yml`, validated first (step 0) and then read with the Read tool. Keys read by this command: `project.default_branch`, `ci.base_ref`, `capabilities.run_in_container`, `make.install_hooks`, `make.check_commit_message`, `make.validate_configuration`, `make.tests_with_coverage`, `make.start` and `make.doctor`. `ralph_agent_md_patch` reads its own keys (`make.bootstrap`, `make.unit_tests`, `make.setup_test_db`, `make.integration_tests`, `make.e2e_tests`, `make.tests_with_coverage`, `make.start`, `quality.coverage_lines`, `quality.coverage_functions`).
- **bmalph and Ralph state** — `_bmad/` (installed by the setup stage), the git-ignored `.ralph/` directory (`.ralph/@fix_plan.md`, `.ralph/@AGENT.md`, `.ralph/PROJECT_CONTEXT.md`, `.ralph/.circuit_breaker_state`, `.ralph/.ralphrc`, `.ralph/logs/`) and the git-ignored staging folder `_bmad-output/planning-artifacts/`.
- **Iteration counter** `implement iteration <n>/5`: `<n>` is the number of the `bmalph run` attempt about to start. The stored iteration (the `iteration` of the `implement` element of the state cache, and of the implement row of the state comment) is the number of attempts consumed so far. Step 3 item 2 records `<n>` right before each `bmalph run`; every end of step 5 that consumes no attempt (items 1, 2 and 5) writes `<n-1>` back, so the next re-entry is attempt `<n>` again. The attempts that stay counted are the resumable exits, the attempt that ends done, a run past its 6 h budget and a session lost mid-run (the last two counted conservatively). The orchestrator hands the counter over (restored from the state comment on a resume); a re-entry, such as a resume or a QA loop-back, starts at the stored iteration plus one, whether or not staging runs again (`FIX_PLAN: current` included). Standalone, it is 1 plus the `iteration` of the `implement` element of the state cache (read with the Read tool) when the cache holds one, else 1.

## Procedure

### Execution rules (every step)

Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` and `bmalph run`, runs through the Bash tool with `run_in_background: true` (never a trailing `&`), logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled with `common.sh wait_log` at most every 30 s.

In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.

How the two rules apply here:

- Each target is the one its `make.*` key maps, and a `null` key is never replaced by a raw command. Make calls are written in suffix form, variables only after the target and only from the closed set `RUN_IN_CONTAINER COMMIT_TITLE base_ref BREAKING_CHANGE_APPROVED CONFIG_CHANGE_APPROVED group context name SCHEMATHESIS_URL` (here `COMMIT_TITLE`, `base_ref`, the empty `CONFIG_CHANGE_APPROVED=` and, in container mode, `RUN_IN_CONTAINER=1` on the targets whose recipes run in the `app` container); no make option is ever passed.
- The background calls of this stage are `bmalph run --driver claude-code --no-dashboard`, `make validate-configuration base_ref=<sha> CONFIG_CHANGE_APPROVED=`, `make tests-with-coverage` and, in container mode, `make start`. Before each one the log directory exists (one foreground `mkdir -p target/rust-sdlc/logs`), the call is the wrapper `{ <command>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/implement-<UTC>.log 2>&1` with a fresh `<UTC>` (the current UTC time as `YYYYMMDDTHHMMSSZ`), and the wait is the background-task completion notice, else `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" wait_log <log>` (at most 110 s per call; it prints the last 40 lines and `RUST_SDLC_EXIT=<n>`, or `WAITING: <log> (<elapsed>s)`), called again on `WAITING:` until `RUST_SDLC_EXIT=<n>` appears or the call's budget is spent: 900 s for `make start`, 60 min for each make target of step 6, 6 h for one `bmalph run` attempt. When the runtime prompts for the brace-group wrapper, the same call is issued as `<command> > target/rust-sdlc/logs/implement-<UTC>.log 2>&1` and its exit status is taken from the completion notice.
- `make install-hooks` and `make check-commit-message` run in the foreground (allowlist) and in host form in both modes: their recipes only write the local hook setting and check a title, and never enter the container.
- A log that shows the template's message `This target needs a reachable container engine (docker).` classifies its target `not run (no Docker)`, never `failed`, and never feeds remediation (D2).
- The command commits nothing and pushes nothing: Ralph's sessions commit each story with the hooks active, and the finish-pr stage pushes the branch. The command's only writes into `.ralph/` are the three helper calls of step 2 (the archive move of the fix plan, the restore of checked stories and the `.ralph/@AGENT.md` patch). `.ralph/.ralphrc` is never edited, and the command never reads or writes a repository-root `.ralphrc` (Ralph's configuration file is `.ralph/.ralphrc`).

### Step 0 — Profile, bundle and preconditions

1. Validate the profile:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
   ```

   Exit 1: stop with `run /rs-sdlc-setup on the default branch and commit the result` and the escalation block (`blocking_finding: validate-profile.sh exit 1`, the `VIOLATION:` lines quoted). Nothing else runs.
2. Resolve the bundle. `git branch --show-current` gives the branch; an empty value (detached `HEAD`) or the value of `project.default_branch` → `ESCALATED` (`blocking_finding: implementation started on <branch>`, `recommended_action: check out the feature branch <type>/<N>-… from the default branch, then run /rs-sdlc-implement again`), because Ralph commits on the checked-out branch. `SPECS_DIR` is the argument or the handle; else `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" derive_issue_number --branch <branch>` gives `<N>` and the Glob `specs/<N>-*/` must match exactly one directory. The directory must exist, hold `epics.md` and be named `<N>-<slug>` (`^[1-9][0-9]*-[a-z0-9]+(-[a-z0-9]+)*$`); a feature branch `<type>/<N>-…` must carry the same `<N>`. Any miss → `ESCALATED` (`blocking_finding: no planning bundle for issue #<N>`, `recommended_action: run /rs-sdlc-plan #<N>`).
3. Clean start: `git status --porcelain --untracked-files=no` must print nothing, so Ralph's story commits contain only Ralph's work. Tracked changes → `ESCALATED` (`blocking_finding: uncommitted tracked changes: <files>`, `recommended_action: commit or stash the changes, then run /rs-sdlc-implement again`). Record the untracked entries of `git status --porcelain` (lines starting `??`) for the check of step 6, and `git rev-parse HEAD` as `<start_sha>`, the pre-run base of the D24 fallback of step 6.
4. Toolchain (D3): when `capabilities.run_in_container` is false, `command -v cargo` must succeed before the first make target runs. It fails → `ESCALATED` (D3) before any make target, with every target of this stage reported `not run (no toolchain)`, `blocking_finding: command -v cargo exit 1 (no host toolchain, container mode off)` and `recommended_action: /rs-sdlc-setup --exec container`.
5. Container precondition (container mode, `capabilities.run_in_container: true`): `docker info`, then `docker compose ps --status running --quiet app`. Empty output and `make.start` mapped → `make start RUN_IN_CONTAINER=1` in the background (≤ 900 s, one restart attempt with a new log), then the `docker compose ps` check again. `docker info` failing, `make.start: null`, or `app` still not running → `ESCALATED` (D25) with the probe output; nothing else runs.
6. Restate `implement iteration <n>/5`. When `<n>` is above 5 (the stored iteration was already 5: every attempt consumed) → `ESCALATED` at once (guard exhausted), with nothing run and `iteration: 5/5`.

### Step 1 — Hooks

Ralph's sessions commit every story through the template's hooks, so the hooks must be active before Ralph starts. "Active" means the read-only local check `git config --local --get core.hooksPath` (local scope only, unlike the unqualified read-only `git config --get core.hooksPath`, which also returns a global value; a global value alone counts as unset) prints exactly `.githooks` and `.githooks/commit-msg`, `.githooks/pre-commit` and `.githooks/pre-push` are executable. The library checks all of it:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" hooks_active
```

- `HOOKS: active` → step 2.
- `HOOKS: unset` and `make.install_hooks` mapped → `make install-hooks` (foreground), then `hooks_active` again: `HOOKS: active` → `install-hooks: passed`; any other line, or a non-zero exit of the target → `ESCALATED` with that line or `make install-hooks exit <n>` as `blocking_finding`. `HOOKS: unset` with `make.install_hooks: null` → `ESCALATED` (`blocking_finding: HOOKS: unset (make.install_hooks absent)`), because Ralph would commit without the hooks.
- `HOOKS: foreign <value>` → `ESCALATED` with `blocking_finding: core.hooksPath=<value>` and `recommended_action: make install-hooks` (a local hook manager is a human decision).
- `HOOKS: missing <file>` → `ESCALATED` naming the file.

Hooks are activated only by `make install-hooks`; this command never writes the hook setting itself and never bypasses a hook.

### Step 2 — Re-entry protocol and staging (ADR-10a, ADR-10b)

`bmalph implement` refuses to run while `.ralph/@fix_plan.md` exists, and `.ralph/` survives between runs (a resume, a QA loop-back, a second feature in the same checkout), so the fix plan is prepared first:

```bash
SPECS_DIR="specs/<N>-<slug>"
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ralph_fix_plan_prepare "$SPECS_DIR" target/rust-sdlc/state/<N>-<slug>.json
```

It prints exactly one line; exit 1 or 2 → `ESCALATED` with its stderr as `blocking_finding`.

| Line | Meaning | Next |
| --- | --- | --- |
| `FIX_PLAN: absent` | no fix plan yet | items 1–4 |
| `FIX_PLAN: current` | the cache's `staged_specs_dir` is this bundle and every `### Story N.M:` id of `epics.md` is in the fix plan (a resume) | skip items 1–4, go to item 5 |
| `ARCHIVED: target/rust-sdlc/ralph-archive/<UTC>-fix_plan.md keep-progress` | same bundle, but `epics.md` holds a story id the fix plan lacks (how a QA fix story arrives) | items 1–4, with the restore of item 3 |
| `ARCHIVED: target/rust-sdlc/ralph-archive/<UTC>-fix_plan.md discard-progress` | no cache, or the cache names another bundle | items 1–4, without the restore |

1. Stage the bundle with `stage-planning-artifacts.sh "$SPECS_DIR"` from the plugin root:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/stage-planning-artifacts.sh" "$SPECS_DIR"
   ```

   Exit 0 prints `STAGED:` and `REMOVED:` lines. Exit 1 prints one `REFUSED: <reason>` line → `ESCALATED` with that line (`recommended_action: /rs-sdlc-plan #<N>` for a bundle refusal such as the `## Constraints` length or the readiness regex; a refusal about `_bmad-output/` names the staging folder to fix). Exit 2 → `ESCALATED`. After an `ARCHIVED:` line the `iteration_log` names the archive path, so the archived progress stays traceable.
2. Transition the staged bundle into Ralph's format, in the foreground, plain and never with `--force`:

   ```bash
   bmalph implement
   ```

   Exit 0 → item 3. Output containing `already been run` means the fix plan still existed, which the protocol rules out: a bug in the re-entry protocol, never worked around → `ESCALATED` with `blocking_finding: bmalph implement refused: already been run (re-entry protocol defect)` and `recommended_action: report the defect with the ralph_fix_plan_prepare output; never run bmalph implement with --force`. Any other non-zero exit → `ESCALATED` with the output verbatim as `blocking_finding` and `recommended_action: /rs-sdlc-plan #<N>` (a preflight error names the bundle artifact to fix; a missing `_bmad/` names /rs-sdlc-setup instead).
3. `keep-progress` only: restore the stories already done, which the archive marks `- [x]` by both id and title:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ralph_fix_plan_restore target/rust-sdlc/ralph-archive/<UTC>-fix_plan.md
   ```

   It prints `RESTORED: <n> stories`; exit 1 or 2 → `ESCALATED` with its stderr.
4. Record the staged bundle in the state cache, with `<head-sha>` from `git rev-parse HEAD` and `<n-1>`, the attempts consumed so far (the stored iteration, 0 on a first run), because no attempt of this invocation has started yet:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" state_cache_update target/rust-sdlc/state/<N>-<slug>.json implement IN_PROGRESS <head-sha> <n-1> --staged-specs-dir "$SPECS_DIR"
   ```

   A non-zero exit → `ESCALATED` with its stderr (a later run would otherwise archive the plan as foreign).
5. Always, after the `FIX_PLAN:` or `ARCHIVED:` branch, override the build and git instructions bmalph wrote for Ralph:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ralph_agent_md_patch "$SPECS_DIR"
   ```

   It prints `UPDATED: .ralph/@AGENT.md` or `UNCHANGED: .ralph/@AGENT.md`; after it, Ralph's sessions see the profile's make targets, the 100% coverage floor, the subject form `<type>(#<N>): story N.M <title>` and no push instruction. Exit 1 (no `.ralph/@AGENT.md`, or the profile invalid) or 2 → `ESCALATED` with its stderr and `recommended_action: /rs-sdlc-plan #<N>` (no `.ralph/@AGENT.md` means the transition did not complete) or `run /rs-sdlc-setup on the default branch and commit the result` (profile).
6. Verify that both parts of the bundle's `## Constraints` reached Ralph: `.ralph/PROJECT_CONTEXT.md` (read with the Read or Grep tool) must contain part (a), the commit convention, found by the literal `(#<N>)` with the real issue number, and part (b), the story-dispatch rule, found by all ten key names: the DB-free keys `make.format`, `make.lint_code`, `make.unit_tests`, `make.architecture`, `make.complexity` and the serialized DB-backed keys `make.setup_test_db`, `make.integration_tests`, `make.tests_with_coverage`, `make.e2e_tests`, `make.sqlx_prepare`. A missing file, a missing part or a missing key → `ESCALATED` with `blocking_finding: .ralph/PROJECT_CONTEXT.md lacks part (a)|part (b) (<missing literal>)` and `recommended_action: /rs-sdlc-plan #<N> (rewrite architecture.md ## Constraints: part (a) then part (b), at most 4,500 characters), then run /rs-sdlc-implement again`.

### Step 3 — Breaker pre-check and the Ralph run (ADR-10c)

1. Before every `bmalph run`, the breaker pre-check runs first:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ralph_breaker_state
   ```

   It reads `.state` of `.ralph/.circuit_breaker_state` and `CB_AUTO_RESET` (the environment first, else the `CB_AUTO_RESET=` line of `.ralph/.ralphrc`) and edits nothing. Exit 0 (`BREAKER: CLOSED` or `BREAKER: ABSENT`, with `AUTO_RESET: false`) → item 2. `BREAKER: OPEN`, `BREAKER: HALF_OPEN` or `AUTO_RESET: true` → `ESCALATED` (D22) and nothing is run: Ralph would reset or retry around the breaker at startup, and the plugin never resets it. `blocking_finding: ralph_breaker_state: BREAKER: <state> AUTO_RESET: <value>`; `recommended_action`: inspect the newest `.ralph/logs/` file and fix the cause; for `AUTO_RESET: true`, a human removes `CB_AUTO_RESET=true` from the environment or from `.ralph/.ralphrc` (the plugin never edits that file). Exit 1 with no output, or exit 2 → `ESCALATED` with its stderr.
2. Record the attempt before it starts, with `<head-sha>` from `git rev-parse HEAD` and `<n>` the attempt about to start:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" state_cache_update target/rust-sdlc/state/<N>-<slug>.json implement IN_PROGRESS <head-sha> <n>
   ```

   No `--staged-specs-dir` here: the helper keeps the stored `staged_specs_dir`. It prints `WROTE: <file>`; a non-zero exit → `ESCALATED` with its stderr, `iteration: <n-1>/5` (the cache still holds `<n-1>`) and no `bmalph run` (an attempt that cannot be counted is never started). From here on attempt `<n>` counts as consumed until step 5 classifies its end: every end that consumes no attempt (step 5 items 1, 2 and 5) writes `<n-1>` back, while a run past its 6 h budget (item 4) and a session lost mid-run leave `<n>` stored and are counted conservatively. Then Glob `.ralph/logs/*` and keep the listed paths: the paths Glob lists later that are not among them are this attempt's `.ralph/logs/` files.
3. Run Ralph in the background, exactly as written (driver always `claude-code`; no prefix, option or variable is added, its allow entry is exact):

   ```bash
   mkdir -p target/rust-sdlc/logs
   { bmalph run --driver claude-code --no-dashboard; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/implement-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

   The second line runs through the Bash tool with `run_in_background: true`. In container mode the precondition of step 0 has already started the `app` service. When the runtime denies the call or it does not start (no log file appears), classification goes straight to step 5 item 5, whose write-back returns attempt `<n>`.
4. Poll: the background completion notice first; without it, `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" wait_log target/rust-sdlc/logs/implement-<UTC>.log`, called again on `WAITING:`, at most every 30 s. On each read, parse the `---RALPH_STATUS---` blocks (from `---RALPH_STATUS---` to `---END_RALPH_STATUS---`: `STATUS`, `TASKS_COMPLETED_THIS_LOOP`, `FILES_MODIFIED`, `TESTS_STATUS`, `WORK_TYPE`, `EXIT_SIGNAL`, `RECOMMENDATION`; a block inside a JSON `result` string carries its line breaks as `\n`) from the run log and from this attempt's `.ralph/logs/` files (item 2; each read with the Read tool, a file already parsed read again only while it is the newest by modification time). Keep the last block, and record whether any block of this `bmalph run` carries `STATUS: BLOCKED`, keeping the first such block: it is a breaker trip in step 5 even when later blocks read otherwise. Restate `implement iteration <n>/5` with the last block's `STATUS` and `RECOMMENDATION`. A run still going after the 6 h budget of one attempt → `ESCALATED` with the last 40 lines of the run log and the last 50 lines of the newest `.ralph/logs/` file; no further `bmalph run` follows, and the running loop is left to Ralph's own limits and to a human, because stopping it mid-session could leave a story half-committed. The overrun keeps `<n>` stored and prints `iteration: <n>/5`: it is counted conservatively as consumed, because the run may still end with a resumable exit.

### Step 4 — Single implementer

`bmalph run` is the only implementer; while it is active this command dispatches no `rust-implementer` and edits no file. It only polls the run log, the status blocks and `.ralph/logs/`. Parallelism happens inside Ralph's own claude-code sessions, which read the story-dispatch rule from `.ralph/PROJECT_CONTEXT.md` (step 2): DB-free targets may run in parallel `rust-backend-sdlc:rust-implementer` subagents, the DB-backed targets run in one serialized verify step. Ralph's session commits each story as `<type>(#<N>): story N.M <title>`; subagents never commit.

### Step 5 — Breaker trip and attempt classification

When the run has ended (`RUST_SDLC_EXIT=<code>` in the log, or the completion notice), or did not start (step 3 item 3), read the run log and this attempt's `.ralph/logs/` files a last time for status blocks (step 3 item 4), then classify the run, in this order.

**Write-back** (items 1, 2 and 5, each before its escalation block): attempt `<n>` was recorded as consumed by step 3 item 2, and an end that consumes no attempt returns it, with `<head-sha>` from `git rev-parse HEAD`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" state_cache_update target/rust-sdlc/state/<N>-<slug>.json implement ESCALATED <head-sha> <n-1>
```

It prints `WROTE: <file>`; the stored iteration is the consumed count `<n-1>` again, so the next re-entry is attempt `<n>`, and the escalation block prints `iteration: <n-1>/5` (the orchestrator records the same value in the state comment). A non-zero exit does not change the outcome: the escalation block still prints `iteration: <n-1>/5`, and its `blocking_finding` ends with `; write-back failed: state_cache_update exit <code> (the cache still counts attempt <n>)`.

1. **Breaker trip** (D22): `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ralph_breaker_state` again, read only for its `BREAKER:` line, which is `.state` of `.ralph/.circuit_breaker_state`: `.state == "OPEN"` after the run, or any `---RALPH_STATUS---` block of this run with `STATUS: BLOCKED`, wherever it sits among the run's blocks. A trip is terminal and consumes no attempt: the write-back, then `ESCALATED` at once with the first `STATUS: BLOCKED` block (when one appeared), the last `---RALPH_STATUS---` block and the last 50 lines of the newest `.ralph/logs/` file (Read tool) printed above the escalation block, `iteration: <n-1>/5`, `blocking_finding: Ralph circuit breaker <OPEN | STATUS: BLOCKED>: <RECOMMENDATION of the first STATUS: BLOCKED block, else of the last block>`, and `recommended_action: diagnose the cause in .ralph/logs/; the breaker is a human-attention signal, and a human decides before any further run`. After a trip there is no second `bmalph run`, the breaker is never reset and never restarted around, and `.ralph/.ralphrc` is never edited.
2. **Not closed**: `BREAKER: HALF_OPEN` after the run → the write-back, then `ESCALATED` (D22) like a trip, with `iteration: <n-1>/5`, because the next pre-check would refuse it anyway. It consumes no attempt.
3. **Done**: the last block carries `EXIT_SIGNAL: true`, the exit code is 0 and the Grep tool finds no open story line (`- [ ] Story`) in `.ralph/@fix_plan.md` → step 6. The attempt that ends done stays counted (`<n>` stays stored): it is the attempt the report names, and a QA loop-back or a re-run after a failed check of step 6 starts at `<n+1>`.
4. **Resumable exits**, the only failed ends that consume an attempt (AC-18.2); each keeps `<n>` stored and nothing is written back:
   - an API or rate-limit exit (the run log or `.ralph/status.json` names Ralph's usage-limit stop): the attempt is consumed, and because a new run before the limit resets would stop the same way, the stage ends `ESCALATED` with `iteration: <n>/5`, `blocking_finding: Ralph stopped at the API usage limit (attempt <n>/5)` and `recommended_action: run /rs-sdlc <N> (or /rs-sdlc-implement) after the limit resets; the next attempt is <n+1>/5`;
   - a timeout (exit code 124, or the run log names Ralph's execution timeout as the reason it stopped);
   - `EXIT_SIGNAL: false` in the last block with the breaker `CLOSED`.

   For a timeout or `EXIT_SIGNAL: false` with the breaker `CLOSED`: when `<n>` is below 5, `<n>` becomes `<n+1>`, `ralph_agent_md_patch "$SPECS_DIR"` runs again (ADR-10b: before every `bmalph run`; it prints `UNCHANGED:` unless a session rewrote the file) and the next attempt starts at step 3, with the breaker pre-check first and then the record of attempt `<n+1>` (step 3 item 2). At attempt 5/5 → `ESCALATED` (guard exhausted) with `iteration: 5/5`, the last status block and the log tail.
5. **Anything else** consumes no attempt and ends the stage: the write-back, then `ESCALATED` with `iteration: <n-1>/5`, the last status block (when there is one) and the last 40 lines of the run log, and no further `bmalph run`. This covers:
   - `EXIT_SIGNAL: true` in the last block while the Grep tool finds an open story line (`- [ ] Story`) in `.ralph/@fix_plan.md` → `blocking_finding: Ralph signalled EXIT_SIGNAL true with open stories in .ralph/@fix_plan.md: <ids>`, with `<ids>` the story ids of the open lines, and the last 50 lines of the newest `.ralph/logs/` file printed as well;
   - `EXIT_SIGNAL: true` in the last block with a non-zero exit code → `blocking_finding: bmalph run exit <code> after EXIT_SIGNAL true`;
   - the run did not start, a non-zero exit with no classified reason, no status block at all, or a permission denial → the exit code or the denial as `blocking_finding`. Five denied launches therefore never exhaust the guard: each one returns its attempt.

### Step 6 — Post-loop verification

1. Merge base (D24): `git rev-parse --verify <ci.base_ref>`. When it fails: one `git fetch origin <default_branch>` (`<default_branch>` is `project.default_branch`) and a re-check; still unavailable → `<sha>` is `<start_sha>`, the `HEAD` recorded in step 0 before the first `bmalph run` (`base_ref=HEAD`), never the `HEAD` read now, whose `<sha>..HEAD` range would be empty: the subject and protected-file checks then still cover every commit of this invocation. The stage records `DEGRADED: base ref <ci.base_ref> unavailable; post-loop checks ran against the pre-run HEAD <start_sha7> (D24)`, so it ends at best `SUCCESS-WITH-REPORT`. Otherwise:

   ```bash
   git merge-base <ci.base_ref> HEAD
   ```

   prints `<sha>`, used as a literal below. A non-zero exit → `ESCALATED` with the command and its exit code.
2. Working tree: `git status --porcelain` must print nothing beyond the untracked entries recorded in step 0. Anything else (Ralph left work uncommitted) → `ESCALATED` with `blocking_finding: uncommitted changes after the Ralph run: <files>` and `recommended_action: inspect the changes, commit them as their story with a valid subject or discard them by hand, then run /rs-sdlc-implement again`.
3. Commit subjects (FR-2, hard): list the subjects with

   ```bash
   git log --format=%s <sha>..HEAD
   ```

   and check each one, in the foreground, with a `'` inside the subject written `'\''`:

   ```bash
   make check-commit-message COMMIT_TITLE='<subject>'
   ```

   A subject that contains a space-hyphen sequence is checked with `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" is_commit_subject '<subject>'` instead (the plugin's deny entries would refuse that make call), and so is every subject when `make.check_commit_message` is `null` (`check-commit-message: not run (capability absent)`, D1). The first rejected subject → `ESCALATED` naming the commit: `blocking_finding: commit <sha7> subject '<subject>' rejected by check-commit-message`, with `<sha7>` the matching line of `git log --format=%h <sha>..HEAD`, and `recommended_action: reword commit <sha7> on the unpushed branch by hand, then run /rs-sdlc-implement again`. All subjects accepted → `check-commit-message: passed`. The story form `<type>(#<N>): story N.M <title>` itself is reported, not enforced.
4. Protected configuration (ADR-25), in the background (`RUN_IN_CONTAINER=1` added in container mode):

   ```bash
   mkdir -p target/rust-sdlc/logs
   { make validate-configuration base_ref=<sha> CONFIG_CHANGE_APPROVED=; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/implement-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

   The empty `CONFIG_CHANGE_APPROVED=` is always passed, so no inherited value can approve a change, and `base_ref` is always the literal `<sha>`, never the Makefile's fallback. `RUST_SDLC_EXIT=0` → `validate-configuration: passed`. A non-zero exit whose log names a protected path (`… is not allowed: <path>`, `Required directory is missing: <path>`) is a hit. When the target cannot run, the library check replaces it: `make.validate_configuration: null` (`validate-configuration: not run (capability absent)`), no Docker (the template's message in the log, or `docker info` failing in container mode: `not run (no Docker)`) or no toolchain (the log shows the toolchain command not found: `not run (no toolchain)`):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" protected_changes <sha>
   ```

   Exit 0 → no hit. A `PROTECTED: <path> (<commit>|working tree)` line, or a hit of the make target, is D23 → `ESCALATED` with `blocking_finding: protected file <path> changed (<commit>)` (the commit from `git log --format=%h -1 <sha>..HEAD -- <path>`, else `working tree`) and `recommended_action: revert with git restore --source=<sha> -- <path> unless the plan intends it; otherwise approved-config-change`; the label is applied by a human, never by this command. A `PROFILE_CHANGED: .claude/rust-sdlc.yml` line → `ESCALATED` with `recommended_action: move the profile change to its own pull request from the default branch (/rs-sdlc-setup --refresh)`. Exit 2, exit 1 without either line (an unreadable `protected-config.toml`), or any other failure of the make target → `ESCALATED` with the error line or the last 40 log lines.
5. Coverage (`make.tests_with_coverage`): `make.tests_with_coverage: null` → `tests-with-coverage: not run (capability absent)` and `DEGRADED: make.tests_with_coverage absent: coverage not verified` (D1), and no Docker probe runs. Mapped → `docker info` first, because the target starts the test database. It fails → `tests-with-coverage: not run (no Docker)` and `ESCALATED` (D2) with the `make doctor` output (foreground; `make.doctor: null` → `blocking_finding: docker info exit <n>`). Otherwise, in the background (`RUN_IN_CONTAINER=1` added in container mode):

   ```bash
   mkdir -p target/rust-sdlc/logs
   { make tests-with-coverage; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/implement-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

   `RUST_SDLC_EXIT=0` → `tests-with-coverage: passed` (the template enforces 100% lines and functions). The template's Docker message in the log → `tests-with-coverage: not run (no Docker)`, `ESCALATED` (D2) as above. Any other exit → `tests-with-coverage: failed`, `ESCALATED` with the last 40 log lines and `recommended_action: add a story for the failing or uncovered code to SPECS_DIR/epics.md (the next run archives with keep-progress), then run /rs-sdlc-implement again`.

### Step 7 — Report and handles

On success print the degrade notes (each `DEGRADED:` line), the `RESTORED:` line when step 2 printed one, the targets-run list (`<target>: passed | failed | not run (<reason>)` for `install-hooks` when step 1 ran it, `check-commit-message`, `validate-configuration` and `tests-with-coverage`), the attempts used (`implement iteration <n>/5`) and, as the last lines, the last `---RALPH_STATUS---` block:

```text
---RALPH_STATUS---
STATUS: COMPLETE
TASKS_COMPLETED_THIS_LOOP: <0 | 1>
FILES_MODIFIED: <number>
TESTS_STATUS: <PASSING | FAILING | NOT_RUN>
WORK_TYPE: <IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING>
EXIT_SIGNAL: true
RECOMMENDATION: <one line>
---END_RALPH_STATUS---
```

## Loop & exit condition

Exit string (stage `implement`, byte-identical in /rs-sdlc and the loop documentation): all stories done with EXIT_SIGNAL true, every commit subject valid, coverage green

The loop is the `bmalph run` attempt of steps 3–5; staging and the `bmalph implement` transition run once per invocation, before the first attempt, and the post-loop checks of step 6 run once, after the attempt that ends done. The stage ends `SUCCESS` when an attempt ends done (`EXIT_SIGNAL: true`, no open story) and every check of step 6 passes; `SUCCESS-WITH-REPORT` when it got there with a degrade note (D1 `make.check_commit_message` or `make.tests_with_coverage` null, D24 base ref); and `ESCALATED` on a breaker trip or a breaker that is `OPEN` or `HALF_OPEN` or has `AUTO_RESET: true` before a run (D22), Docker unreachable at the coverage target (D2), no host toolchain with container mode off (D3), a protected change (D23), the container stack not starting (D25), a rejected commit subject, any stop named above or an exhausted guard. Degrade paths never loop and never fake a pass: a target that did not run is reported `not run (<reason>)`.

## Iteration guard

`MAX_ITERATIONS=5` counts resumable `bmalph run` attempts, restated as `implement iteration <n>/5` at the start of each attempt and with every status block. Only resumable exits consume an attempt (an API or rate-limit exit, a timeout, `EXIT_SIGNAL: false` with the breaker `CLOSED`); a breaker trip, a breaker `HALF_OPEN` after the run, `EXIT_SIGNAL: true` with an open story and every other unclassified stop (a run that did not start and a permission denial included) consume none and end the stage at once, never with another `bmalph run`. The attempt that ends done is the loop's completion, not a failed end, and stays counted: it is the attempt the report names, and it is why a QA loop-back consumes this stage's budget. Ralph's own circuit breaker governs the inner loop independently and is never reset: the stage guard and the breaker are separate safety nets, and either one ends the stage.

The counter is never reset within a run and is restored from the state record on a resume. The stored iteration is the number of consumed attempts: step 3 item 2 records `<n>` before the run, and every non-consuming end of step 5 (items 1, 2 and 5) writes `<n-1>` back with `state_cache_update … implement ESCALATED <head-sha> <n-1>`, so the next re-entry, `FIX_PLAN: current` included, is attempt `<n>` again. A run past its 6 h budget and a session lost mid-run keep `<n>` stored: both are counted conservatively, because the run may have ended with a resumable exit. The `iteration:` line of the escalation block is always the stored iteration at that moment: `<n>` after a consumed attempt, `<n-1>` when attempt `<n>` never started (every stop before step 3 item 2 records it, so the exhausted guard of step 0 prints `5/5`) or ended without consuming. A QA loop-back re-enters after the done attempt with the next attempt number, so it consumes this stage's budget. An attempt beyond 5/5 is never started.

## Failure escalation

Every exit that is not `SUCCESS` or `SUCCESS-WITH-REPORT` prints this block, filled in, and nothing after it; the last `---RALPH_STATUS---` block, the last 50 lines of the newest `.ralph/logs/` file, a log tail or the `make doctor` output go above it:

```text
=== SDLC ESCALATION ===
stage: implement
iteration: <stored iteration, the consumed attempts: n | n-1>/5
exit_condition: all stories done with EXIT_SIGNAL true, every commit subject valid, coverage green
status: NOT MET
blocking_finding: <file:line (.ralph/PROJECT_CONTEXT.md lacks part (b)) | check name (Ralph circuit breaker OPEN: <RECOMMENDATION>) | command + exit code (make tests-with-coverage exit 2)>
iteration_log: <one line per attempt of this invocation: "<n>: bmalph run -> <result> (<consumed | not consumed>)", result one of EXIT_SIGNAL true | EXIT_SIGNAL false | timeout | usage limit | over 6 h budget | breaker OPEN | breaker HALF_OPEN | STATUS: BLOCKED | EXIT_SIGNAL true with open stories | not started | unclassified exit <code>; "none" when no attempt started>
recommended_action: <the human action: diagnose .ralph/logs/ before any further run, /rs-sdlc-plan #<N>, /rs-sdlc-setup --exec container, git restore --source=<sha> -- <path>, or a protected change with ALLOW_PROTECTED_CONFIG_EDIT=1>
=== END ===
```

`iteration:` is the stored iteration of `## Iteration guard`: `<n-1>/5` for every trigger before attempt `<n>` is recorded and for every end that consumes no attempt (after the step 5 write-back), `<n>/5` once attempt `<n>` is consumed.

Triggers, each with its `blocking_finding` and `recommended_action`:

- Profile invalid → `validate-profile.sh exit 1`; `run /rs-sdlc-setup on the default branch and commit the result`.
- No bundle, the default branch or a detached `HEAD`, or tracked changes before the run → the missing source, the branch or the files; /rs-sdlc-plan, a checkout of the feature branch `<type>/<N>-…`, or a commit of the changes.
- No host toolchain with container mode off (D3) → `command -v cargo exit 1`; `/rs-sdlc-setup --exec container`.
- Container mode and `app` not running after `make start` and one restart attempt, or `docker info` failing (D25) → the probe output; start the container engine, then run /rs-sdlc-implement again.
- Hooks not active → the `HOOKS:` line or `core.hooksPath=<value>`; `make install-hooks`, or restore the named hook file.
- Staging refused, `bmalph implement` failing, the `already been run` refusal, a failed restore, cache write or `.ralph/@AGENT.md` patch, or a missing `## Constraints` part in `.ralph/PROJECT_CONTEXT.md` → the `REFUSED:` line, the output verbatim or the missing literal; /rs-sdlc-plan, or a defect report for the protocol (never `--force`).
- Breaker `OPEN`, `HALF_OPEN` or `AUTO_RESET: true` before a run, a trip after a run, or any `STATUS: BLOCKED` block of a run (D22) → the `BREAKER:` line, the first `STATUS: BLOCKED` block or the last status block; diagnose the cause in `.ralph/logs/`; the plugin never resets the breaker and never edits `.ralph/.ralphrc`. No attempt is consumed: a refusal before the run never recorded `<n>`, and a trip or `HALF_OPEN` after the run writes `<n-1>` back first.
- Usage limit, a run beyond its 6 h budget or an exhausted guard (the attempt stays counted, `<n>` stored), or `EXIT_SIGNAL: true` with open stories in `.ralph/@fix_plan.md`, a run that did not start, a permission denial or an unclassified exit (no attempt consumed, `<n-1>` written back) → the last status block and the log tail (`Ralph signalled EXIT_SIGNAL true with open stories in .ralph/@fix_plan.md: <ids>` for the open stories); run again after the limit resets, or inspect the stories by hand before another run.
- A failed write-back of step 5 → the exit's own `blocking_finding` followed by `; write-back failed: state_cache_update exit <code> (the cache still counts attempt <n>)`; the exit's own `recommended_action`. The `implement` element of `target/rust-sdlc/state/<N>-<slug>.json` then overcounts by one until the orchestrator's own state write replaces it (it records the block's `iteration: <n-1>/5`) or, standalone, a human re-runs the write-back command of step 5.
- Uncommitted changes after the run or a rejected commit subject → the files, or the commit and its subject; commit or reword by hand on the unpushed branch.
- Protected file changed (D23) → `protected file <path> changed (<commit>)`; revert with `git restore --source=<sha> -- <path>` unless the plan intends it, otherwise a human adds `approved-config-change` and restarts the session with `ALLOW_PROTECTED_CONFIG_EDIT=1`. Profile changed on the branch → `PROFILE_CHANGED: .claude/rust-sdlc.yml`; move the profile change to its own pull request from the default branch (/rs-sdlc-setup --refresh).
- Docker unreachable at the coverage target (D2) → the first failing `make doctor` line or `docker info exit <n>`; start the container engine, check `make doctor`, then run /rs-sdlc-implement again.
- Coverage below the floor or failing tests → `make tests-with-coverage exit <n>` with the log tail; add a fix story to `SPECS_DIR/epics.md`, then run /rs-sdlc-implement again.
