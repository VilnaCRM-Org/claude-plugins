---
description: "Prepare a Rust template-derived repository for the plugin: preflight, bmalph setup, project profile, governance block, local permission allowlist, hooks and docs-check."
argument-hint: "[--refresh] [--with-qa-network] [--print-settings] [--exec host|container]"
---

# rs-sdlc-setup — repository setup for the plugin

Stage id `setup`. One run takes a fresh checkout of a template-derived Rust service to the state every other plugin command expects: tools at their floors, the bmalph workspace `_bmad/`, a valid project profile `.claude/rust-sdlc.yml`, the managed governance block in `CLAUDE.md` and `AGENTS.md`, the plugin's allow and deny entries in the git-ignored `.claude/settings.local.json`, active git hooks and a docs-check verdict. The steps run in the fixed order 1–9 below; each one is idempotent, so a re-run (after a template-sync merge, after a plugin update, or to change `--exec`) prints `UNCHANGED:` for everything already in place. The command never commits, pushes, stashes or labels: its summary (step 9) tells the human which files to commit, all in a single commit. /rs-sdlc-new-service runs this procedure at its step S12 with `--exec`, and that caller makes the commit.

## Inputs

- **`--refresh`** — re-detect the profile and rewrite it (step 3). The five user-owned keys (`capabilities.run_in_container`, `capabilities.dynamic_security_testing`, `capabilities.publish_pr_comments`, `review.reviewers`, `review.ai_review_agents`) keep a valid existing value (ADR-24). Without it an existing profile is kept and a detection difference is only reported.
- **`--with-qa-network`** — passed through to the allowlist merge of step 6; it is kept for compatibility and writes nothing extra (QA probes go through the library's `http_probe`, never through a `curl` allow entry).
- **`--print-settings`** — step 6 prints the merged allowlist JSON instead of writing `.claude/settings.local.json`.
- **`--exec host|container`** — chooses where make targets and hooked git calls run: `host` sets `capabilities.run_in_container` to `false`, `container` sets it to `true` (step 3). Without `--exec` no choice is passed and the generator's precedence applies: the existing profile value, then detection.
- Any other argument, an `--exec` without a value or with a value other than `host` or `container`, or two `--exec` flags with different values → `ESCALATED` before step 1 (`blocking_finding: unknown argument <arg>` or `invalid --exec value <value>`, `recommended_action: run /rs-sdlc-setup with the flags of its argument hint`); nothing runs and nothing is written.
- **Repository** — the current working directory, which must be the root of the service's git work tree (step 1 checks it). No profile is needed on entry: this command creates it, so its first fenced block is the preflight, not a profile validation.
- **Profile keys** read once the profile validates (step 4): `project.default_branch`, `capabilities.run_in_container`, `make.install_hooks`, `make.docs_check` and `make.start`. Step 2 reads `make.bmalph_setup` from the detection preview because the profile may not exist yet.
- **Iteration counter** `setup iteration <n>/5`: the number of `--refresh` regenerations step 4 has made in this run, 0 at the start.

## Procedure

### Execution rules (every step)

Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` and `bmalph run`, runs through the Bash tool with `run_in_background: true` (never a trailing `&`), logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled with `common.sh wait_log` at most every 30 s.

In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.

How the two rules apply here. Container mode means `capabilities.run_in_container: true` in the profile that step 4 validated, so the check runs once, in step 8, before the first target whose recipe runs in the `app` container; the targets of steps 2 and 7 only install bmalph and write the local hook setting, need no container, and keep their host form in both modes. This command makes no hooked git call and no raw container-route call. Each target is the one its `make.*` key maps, and a `null` key is never replaced by a raw command. Make calls are written in suffix form, variables only after the target and only from the closed set `RUN_IN_CONTAINER COMMIT_TITLE base_ref BREAKING_CHANGE_APPROVED CONFIG_CHANGE_APPROVED group context name SCHEMATHESIS_URL` (here only `RUN_IN_CONTAINER=1`, in container mode); no make option is ever passed. Before each background call the log directory exists (one foreground `mkdir -p target/rust-sdlc/logs`), the call is the wrapper `{ <make call>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/setup-<UTC>.log 2>&1` with a fresh `<UTC>` (`YYYYMMDDTHHMMSSZ`), and the wait is the background-task completion notice, else `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" wait_log <log>` (at most 110 s per call, inside the Bash tool's default 120 s timeout; it prints the last 40 lines and `RUST_SDLC_EXIT=<n>`, or `WAITING: <log> (<elapsed>s)`), called again on `WAITING:` until `RUST_SDLC_EXIT=<n>` appears or the step's budget is spent: 900 s for `make bmalph-setup` and for `make start` (about 9 calls), 60 min for `make docs-check` (about 33 calls). A wait that outlives its budget ends `ESCALATED` with the last 40 log lines.

Every result line of a step (`DONE:`, `UNCHANGED:`, `SKIP:`, `DEGRADED:`, `NEXT:`) is collected for the summary of step 9. Every target the command runs, or holds back for a reason of the closed set `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`, gets one targets-run line `<target>: passed | failed | not run (<reason>)`; a target held back by the dirty tree of step 2 is reported by its `DEGRADED:` line only.

### Step 1 — Preflight

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-preflight.sh" --report
```

The script writes nothing and prints one `<STATUS>: <check-id>: <detail>[ — remediation: <text>]` line per check, then `SUMMARY: pass=<n> warn=<n> fail=<n> info=<n>`.

- Exit 0 → `DONE: preflight (pass=<n> warn=<n> fail=0 info=<n>)`; continue. A `WARN: template-markers` row adds `DEGRADED: not template-derived: <missing markers>; template capabilities off (D20)`. A `WARN: bmalph` row (bmalph absent but installable) is the designed path: step 2 installs it.
- Exit 1 (any `FAIL` row) → print the whole table above the escalation block and stop: `blocking_finding` is the first `FAIL` row, `recommended_action` its remediation text. Nothing is written by any later step.
- Exit 2 → `ESCALATED` with `blocking_finding: setup-preflight.sh exit 2`.

### Step 2 — bmalph workspace (`make bmalph-setup`)

1. `_bmad/` present → `SKIP: bmalph-setup (_bmad/ present)`; continue with step 3 (step 1 already checked the bmalph floor and ran `bmalph doctor` on the existing workspace).
2. `_bmad/` absent → read `make.bmalph_setup` from the detection preview, which prints the profile YAML and writes nothing:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --stdout
   ```

   `make.bmalph_setup: null` → `make bmalph-setup: not run (capability absent)`, `DEGRADED: make.bmalph_setup absent: _bmad/ not created (D1)` and `NEXT: initialise bmalph in this repository, then run /rs-sdlc-setup again`; continue with step 3.
3. Mapped → check the tracked tree (D5):

   ```bash
   git status --porcelain --untracked-files=no
   ```

   Any output → the target is not run, because the bmalph installer may change tracked files and its changes must stay reviewable on their own: print `DEGRADED: make bmalph-setup not run (tracked changes: <files>)` (the paths of the output, space-separated) and `NEXT: commit or stash, then make bmalph-setup`, and continue with step 3.
4. Clean → `make bmalph-setup` in the background (budget 900 s):

   ```bash
   mkdir -p target/rust-sdlc/logs
   { make bmalph-setup; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/setup-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

   `RUST_SDLC_EXIT=0` and `_bmad/` now present → `make bmalph-setup: passed`. Any other exit, or `_bmad/` still absent → `ESCALATED` with `blocking_finding: make bmalph-setup exit <n>` and the last 40 log lines.
5. After it ran, re-check the bmalph floor:

   ```bash
   bmalph --version
   ```

   A version of at least 2.11.0 → `DONE: bmalph-setup (_bmad/ created, bmalph <version>)`. A lower version or a failing call → `ESCALATED` (`blocking_finding: bmalph --version: <output> (floor 2.11.0)`, `recommended_action: install bmalph 2.11.0 or newer, then run /rs-sdlc-setup again`).

### Step 3 — Project profile (`generate-profile.sh`)

The generator call carries `--refresh` when this run has it and translates `--exec` into `--run-in-container`; without `--exec` no flag is passed:

| This run's flags | Generator call |
| --- | --- |
| none | `"${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh"` |
| `--refresh` | `"${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --refresh` |
| `--exec host` | `"${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --run-in-container false` |
| `--exec container` | `"${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --run-in-container true` |
| `--refresh --exec host` | `"${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --refresh --run-in-container false` |
| `--refresh --exec container` | `"${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --refresh --run-in-container true` |

In short `generate-profile.sh [--refresh] [--run-in-container true|false]`. An explicit `--run-in-container` takes effect on an existing profile without `--refresh` (ADR-24): only `capabilities.run_in_container` is rewritten.

- `WROTE: .claude/rust-sdlc.yml` → `DONE: profile .claude/rust-sdlc.yml written`.
- `UPDATED: .claude/rust-sdlc.yml (capabilities.run_in_container=<v>)` → `DONE: profile .claude/rust-sdlc.yml (capabilities.run_in_container=<v>)`.
- `UNCHANGED: .claude/rust-sdlc.yml` → kept as it is.
- `DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)` and its unified diff → the file is kept; the summary repeats the diff and prints `NEXT: run /rs-sdlc-setup --refresh to apply the detected profile changes`.
- Exit 1 (a symlinked `.claude`, a symlinked or non-regular profile, a write failure) or exit 2 → `ESCALATED` with the refusal line as `blocking_finding`.

### Step 4 — Profile validation (`validate-profile.sh`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
```

- Exit 0 (`VALID: <path>`) → `DONE: validate-profile (VALID)`; read the profile keys listed under "Inputs" with the Read tool and continue.
- Exit 1 (`VIOLATION:` lines, `INVALID: <path>: <n> violation(s)`) → regenerate with `--refresh`, keeping this run's `--run-in-container` value when `--exec` was given, and validate again:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --refresh
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  (with `--exec`: `"${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --refresh --run-in-container true|false`). Each regeneration is one iteration, restated as `setup iteration <n>/5`, at most 5. A valid result → `DONE: profile regenerated with --refresh (setup iteration <n>/5)` and continue. When a regeneration prints `UNCHANGED: .claude/rust-sdlc.yml` and the same `VIOLATION:` lines come back, detection cannot converge: stop at once instead of repeating an identical attempt. Still invalid after the fifth regeneration, or stopped early → `ESCALATED` with the first `VIOLATION:` line as `blocking_finding` and `recommended_action: fix the repository signal the violation names (a gate threshold, a make target, a workflow), then run /rs-sdlc-setup --refresh`.
- Exit 2 → `ESCALATED` with `blocking_finding: validate-profile.sh exit 2`.

### Step 5 — Governance block (`inject-governance.sh`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/inject-governance.sh"
```

The script keeps exactly one managed block between `<!-- rust-backend-sdlc:begin -->` and `<!-- rust-backend-sdlc:end -->` in `CLAUDE.md` and `AGENTS.md`; text outside the markers is never changed. `CREATED: <file>`, `UPDATED: <file>` and `REPAIRED: <file> (<n> stray marker line(s) removed)` → `DONE: governance <file> <created|updated|repaired>`; `UNCHANGED: <file>` is kept as it is. Exit 1 (a symlinked, non-regular, unreadable or read-only file, a write failure) or exit 2 → `ESCALATED` with the error line as `blocking_finding`; a file the script refuses is never edited by hand. Afterwards `<!-- rust-backend-sdlc:begin -->` must be found in both files (the Grep tool); a missing marker → `ESCALATED` (D19).

### Step 6 — Local permission allowlist (`merge-settings.sh`)

The call is `merge-settings.sh [--with-qa-network] [--print]`: `--with-qa-network` when this run has it, `--print` when this run has `--print-settings`, and never `--file shared`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/merge-settings.sh"
```

(`"${CLAUDE_PLUGIN_ROOT}/scripts/merge-settings.sh" --with-qa-network`, `"${CLAUDE_PLUGIN_ROOT}/scripts/merge-settings.sh" --print` or `"${CLAUDE_PLUGIN_ROOT}/scripts/merge-settings.sh" --with-qa-network --print` for the other flag combinations.) The script merges the plugin's allow entries and plugin-owned deny entries into `.claude/settings.local.json` as unions: existing entries keep their bytes and order, and `ask`, hooks and `defaultMode` are never touched.

**Protected-settings rule (D4).** Setup never writes `.claude/settings.json` when `protected-config.toml` lists it: the allowlist goes to the git-ignored `.claude/settings.local.json` or is printed, and this command writes `.claude/settings.json` under no condition. The D4 note follows the protection check of `merge-settings.sh`, which the script runs only for `--file shared`, a flag this command never passes; so the command applies the same rule to the same file itself. Read `protected-config.toml` with the Read tool; when its `files` array names `.claude/settings.json` (a leading `./` ignored), or `.claude/settings.json` lies below an entry of its `directories` array (an entry `.` or `""` covers every path), or the file exists but cannot be read or parsed as TOML, or `files` or `directories` is not an array of strings (fail closed, as the script does), record `DEGRADED: .claude/settings.json is protected (protected-config.toml lists it); allowlist kept in .claude/settings.local.json (D4)`.

- `WROTE: .claude/settings.local.json (+<n> allow, +<m> deny)` → `DONE: allowlist .claude/settings.local.json (+<n> allow, +<m> deny)`; `UNCHANGED: .claude/settings.local.json` is kept as it is; an `INFO:` line from `--with-qa-network` is passed through.
- `--print` → the merged JSON is printed in the summary, nothing is written: `DONE: allowlist printed (nothing written)` and `NEXT: merge the printed entries into .claude/settings.local.json, or run /rs-sdlc-setup without --print-settings`.
- `REFUSED: .claude/settings.local.json is not git-ignored` (exit 1) → run the same call once more with `--print` added, print the JSON, and record `DEGRADED: .claude/settings.local.json is not git-ignored: allowlist printed, not written` and `NEXT: add .claude/settings.local.json to .gitignore, then run /rs-sdlc-setup again` (the file holds the absolute plugin root and the numeric uid:gid and must never be committed).
- Any other exit 1 (malformed existing JSON, a symlinked or non-regular file) or exit 2 → `ESCALATED` with the error line as `blocking_finding`: the allowlist is then neither present nor printed.

### Step 7 — Hooks (`common.sh hooks_active`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" hooks_active
```

`hooks_active` reads the hook state at local scope only, through the read-only `git config --local --get core.hooksPath`, never through the unqualified read-only check `git config --get core.hooksPath`, which also returns a global value. A local value of exactly `.githooks` with `.githooks/commit-msg`, `.githooks/pre-commit` and `.githooks/pre-push` executable is `HOOKS: active`; no local value is `HOOKS: unset`, also when a global value is set; any other local value is `HOOKS: foreign <value>`; a hook file that is missing or not executable is `HOOKS: missing <file>`.

- `HOOKS: active` → `UNCHANGED: hooks (HOOKS: active)`.
- `HOOKS: unset` and `make.install_hooks` mapped → `make install-hooks` in the foreground (it is on the foreground allowlist), then `hooks_active` again: `HOOKS: active` → `make install-hooks: passed` and `DONE: hooks activated with make install-hooks`; any other line, or a non-zero exit of the target → `ESCALATED` with that line or `make install-hooks exit <n>` as `blocking_finding`.
- `HOOKS: unset` and `make.install_hooks: null` → `make install-hooks: not run (capability absent)`, `DEGRADED: make.install_hooks absent: git hooks not activated (D1)` and `NEXT: activate the repository's git hooks, then run /rs-sdlc-setup again`.
- `HOOKS: foreign <value>` → `ESCALATED` with `blocking_finding: core.hooksPath=<value>` and `recommended_action: make install-hooks` (a local hook manager is a human decision; this command does not override it).
- `HOOKS: missing <file>` → `ESCALATED` with `blocking_finding: HOOKS: missing <file>` and `recommended_action: restore <file> from the default branch, then run /rs-sdlc-setup again`.
- Exit 2 → `ESCALATED` with `blocking_finding: hooks_active exit 2`.

Hooks are activated only by `make install-hooks`. This command never writes `core.hooksPath` itself: never `git config core.hooksPath …`, never `git -c core.hooksPath`, and never a hook bypass with `--no-verify`.

### Step 8 — docs-check (`make docs-check`)

`make docs-check` compiles and runs the `service` binary, so it runs in the background (budget 60 min, a cold `target/` compiles the workspace) and only under one of these conditions; otherwise a degrade note is recorded and the target is never reported as passed:

1. `make.docs_check: null` → `make docs-check: not run (capability absent)` and `DEGRADED: make.docs_check absent: docs-check not run (D1)`.
2. Host mode (`capabilities.run_in_container: false`): `command -v cargo` succeeds → run `make docs-check`. It fails (no host toolchain, D3) → `make docs-check: not run (no toolchain)`, `DEGRADED: no host toolchain and container mode off: make docs-check not run (D3)` and `NEXT: run /rs-sdlc-setup --exec container, or install the Rust toolchain, then make docs-check`.
3. Container mode (`capabilities.run_in_container: true`): the container precondition of the execution rules runs now. `docker info` fails → `make docs-check: not run (no Docker)`, `DEGRADED: container engine unreachable: make docs-check not run (D25)` and `NEXT: start the container engine, then run /rs-sdlc-setup again`. Otherwise `docker compose ps --status running --quiet app`: non-empty output → run `make docs-check RUN_IN_CONTAINER=1`. Empty output and `make.start` mapped → `make start RUN_IN_CONTAINER=1` in the background (≤ 900 s, one restart attempt with a new log), then the `docker compose ps` check again; `app` running → run `make docs-check RUN_IN_CONTAINER=1`. `make.start: null`, or `app` still not running after the restart attempt → `make docs-check: not run (no Docker)`, `DEGRADED: app container not running: make docs-check not run (D25)` and `NEXT: make start, then run /rs-sdlc-setup again`; with `make.start: null` the profile maps no start target, so the line reads `NEXT: start the app container by hand (make.start is null), then run /rs-sdlc-setup again`.

The call, in host mode and in container mode:

```bash
mkdir -p target/rust-sdlc/logs
{ make docs-check; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/setup-<UTC>.log 2>&1  # Bash tool, run_in_background: true
{ make docs-check RUN_IN_CONTAINER=1; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/setup-<UTC>.log 2>&1  # Bash tool, run_in_background: true
```

- `RUST_SDLC_EXIT=0` → `make docs-check: passed` and `DONE: docs-check passed`.
- The log contains `This target needs a reachable container engine (docker).` → `make docs-check: not run (no Docker)` and `DEGRADED: container engine unreachable: make docs-check not run (D25)`, never `failed`.
- Any other non-zero exit → `make docs-check: failed` and `ESCALATED` with the first violation line of the log as `blocking_finding` (the last 40 log lines above the block) and `recommended_action: fix the cited documentation line, then run /rs-sdlc-setup again`. The managed block is docs-check-safe by construction; a violation inside it is a plugin defect and is reported as such, never edited by hand.
- No `RUST_SDLC_EXIT=` line after 60 min → `ESCALATED` with the last 40 log lines.

### Step 9 — Summary

1. Commit check:

   ```bash
   git status --porcelain -- .claude/rust-sdlc.yml CLAUDE.md AGENTS.md
   ```

   Any output → print the instruction: commit `.claude/rust-sdlc.yml`, `CLAUDE.md` and `AGENTS.md` together in one commit (as a `NEXT:` line). The reason goes with it: the governance block backticks `.claude/rust-sdlc.yml`, and CI's docs-check sees only committed files, so the profile and the block pass CI only when they land in the same commit. No output → `UNCHANGED: setup result already committed`.
2. Branch check: `git branch --show-current` differs from `project.default_branch`, or prints nothing (detached `HEAD`) → print the warning `NEXT: warning: setup ran on <branch>, not on the default branch <project.default_branch>; bring the setup commit onto <project.default_branch> (directly or through a pull request) before feature work starts, because the loop stages escalate on a profile changed on a feature branch`.
3. Print, in this order: the `DONE:` lines (files written, plus the preflight, validation, docs-check and printed-allowlist results, which write nothing), the `UNCHANGED:` and `SKIP:` lines, any `DIFF:` text of step 3, the targets-run list, every `DEGRADED:` note, every `NEXT:` line (the commit instruction and the branch warning last). Example of a first run on a template-derived checkout in host mode:

   ```text
   DONE: preflight (pass=13 warn=0 fail=0 info=4)
   DONE: bmalph-setup (_bmad/ created, bmalph 2.11.0)
   DONE: profile .claude/rust-sdlc.yml written
   DONE: validate-profile (VALID)
   DONE: governance CLAUDE.md updated
   DONE: governance AGENTS.md updated
   DONE: allowlist .claude/settings.local.json (+66 allow, +29 deny)
   DONE: hooks activated with make install-hooks
   DONE: docs-check passed
   make bmalph-setup: passed
   make install-hooks: passed
   make docs-check: passed
   DEGRADED: .claude/settings.json is protected (protected-config.toml lists it); allowlist kept in .claude/settings.local.json (D4)
   NEXT: commit .claude/rust-sdlc.yml, CLAUDE.md and AGENTS.md together in one commit
   ```

The outcome is `SUCCESS` when no `DEGRADED:` line was recorded, `SUCCESS-WITH-REPORT` when at least one was, and `ESCALATED` when any step stopped with the block below.

## Loop & exit condition

Exit string (stage `setup`, byte-identical in the loop documentation): preflight without FAIL, profile valid, markers in both files, allowlist present or printed, docs-check passed or degraded with a note

The stage is one pass through steps 1–9. Its only loop is the regeneration of step 4 (generate with `--refresh`, validate again); the one `make start` restart attempt of step 8 is a retry, not a loop. Degrade paths (D1, D3, D4, D5, D20, D25) never loop and never fake a pass: a target that did not run is reported `not run (<reason>)` with its note. `SUCCESS` and `SUCCESS-WITH-REPORT` both mean the exit string holds; the orchestrator records `met: yes (degraded)` for the latter.

## Iteration guard

`MAX_ITERATIONS=5`, counting the `--refresh` regeneration attempts of step 4. The counter is restated before each attempt as `setup iteration <n>/5` and is never reset within a run. A fifth failing attempt, or an attempt that reproduces the same file and the same violations, ends the stage. Nothing else is retried: a preflight `FAIL`, a script refusal, a failing `make bmalph-setup`, a foreign or missing hook and a failing docs-check stop the stage at once.

## Failure escalation

Every exit that is not `SUCCESS` or `SUCCESS-WITH-REPORT` prints this block, filled in, with the preflight table, the `VIOLATION:` lines or the last 40 log lines above it, and nothing after it:

```text
=== SDLC ESCALATION ===
stage: setup
iteration: <n>/5
exit_condition: preflight without FAIL, profile valid, markers in both files, allowlist present or printed, docs-check passed or degraded with a note
status: NOT MET
blocking_finding: <first FAIL row | first VIOLATION: line | core.hooksPath=<value> | command + exit code (make docs-check exit 2)>
iteration_log: <one line per iteration: "<n>: generate-profile.sh --refresh, validate-profile.sh -> <result>", or "0: <step> -> <result>" when the stop came before any regeneration>
recommended_action: <the human action: the preflight remediation, a repository fix then /rs-sdlc-setup --refresh, make install-hooks, or a command>
=== END ===
```

Triggers, each with its `blocking_finding` and `recommended_action`:

- Unknown argument or invalid `--exec` value → the argument; run /rs-sdlc-setup with the flags of its argument hint.
- Preflight `FAIL` → the first `FAIL` row; its remediation text (install or upgrade the tool, `gh auth login`, run from the repository root).
- `make bmalph-setup` failing or `_bmad/` still absent → `make bmalph-setup exit <n>`; fix the installer error in the log, then run /rs-sdlc-setup again.
- bmalph below its floor after setup → `bmalph --version: <output> (floor 2.11.0)`; install bmalph 2.11.0 or newer.
- Generator refusal (exit 1 or 2) → the refusal line; remove the symlink or fix the profile path, then run /rs-sdlc-setup again.
- Profile still invalid after 5 regenerations, or not converging → the first `VIOLATION:` line; fix the repository signal it names, then run /rs-sdlc-setup --refresh.
- Governance refusal or a marker missing afterwards (D19) → the error line or the file without the marker; turn it into a regular, writable file, then run /rs-sdlc-setup again.
- Allowlist neither written nor printed → the `merge-settings.sh` error line; repair `.claude/settings.local.json` (valid JSON, a regular file), then run /rs-sdlc-setup again.
- `HOOKS: foreign <value>` → `core.hooksPath=<value>`; `make install-hooks`. `HOOKS: missing <file>` or hooks still inactive after `make install-hooks` → the `HOOKS:` line; restore the hook file, then run /rs-sdlc-setup again.
- `make docs-check` failing or exceeding its budget → the first violation line or `make docs-check exit <n>`; fix the cited documentation line, then run /rs-sdlc-setup again.
