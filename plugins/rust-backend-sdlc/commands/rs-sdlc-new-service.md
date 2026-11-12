---
description: "Create a new Rust microservice from the service template: repository, identity, sync flavour, bootstrap, setup and a bootstrap pull request handed to PR finishing."
argument-hint: "[<name>] [--description <text>] [--owner <org>] [--visibility private|public] [--template <owner/repo> | --template-path <dir> | --in-place] [--dest <parent-dir>] [--version <x.y.z>] [--intro <text>] [--sync-flavour app|pat] [--keep-specs] [--issue <N>] [--exec host|container] [--dry-run]"
---

# rs-sdlc-new-service — new service from the template

Stage id `new-service`. One run takes a service from nothing (or from an unmodified `--in-place` checkout) to a customized repository with active hooks, a valid project profile, the governance block and, in GitHub mode, a bootstrap pull request handed to the /rs-sdlc-finish-pr procedure. It runs the ordered sequence S1–S14 below; every step is either EXECUTED (it prints `DONE:`, `UNCHANGED:` or `SKIP:`) or printed as a `NEXT:` line with the exact command or human decision, never silently dropped. `new-service.sh` owns the repository creation and every deterministic file edit (S1, S5) and never commits or pushes; this command owns the GitHub calls, the branch, every commit and every push (S2–S4, S7–S14). The service-scaffolding skill (`${CLAUDE_PLUGIN_ROOT}/skills/service-scaffolding/SKILL.md`) holds the per-step rules and the traps this sequence avoids; load it before S1.

No project profile exists before S12, so this command does not start with a profile validation: its first action is the argument check of step 0, and the profile is validated by the setup procedure at S12.

## Inputs

- **`<name>`** — the service name: kebab-case, at most 50 characters (`new-service.sh` validates it with `is_kebab` before anything is created; exit 2 → `ESCALATED`). It names the repository `<owner>/<name>` and the checkout directory `<dest>/<name>`, which is also the Compose project name.
- **Identity flags and their defaults** (applied by `new-service.sh`, stated here so the run report can show them):
  - `--description <text>` defaults to `<name>`; it feeds `[workspace.package].description` and so the OpenAPI title `<description> API`.
  - `--owner <org>` defaults to the login printed by `gh api user --jq .login` (GitHub mode only; an empty login → `pass --owner`, exit 1).
  - `--intro <text>` defaults to the description; it becomes the README introduction.
  - `--version <x.y.z>` defaults to `default_version` of `config/new-service.defaults.json`; the version changes only through `scripts/set-version.sh` (S9).
  - `--visibility private|public` defaults to `default_visibility` of the same file; `--dest <parent-dir>` defaults to `.`.
- **Source** — at most one of `--template <owner/repo>`, `--template-path <dir>` and `--in-place` (two → exit 2). None → GitHub mode with the configured template (`RUST_SDLC_TEMPLATE_REPO`, else the plugin configuration). GitHub mode: `--template`, no source flag, or `--in-place` in a checkout with a github.com `origin` and `gh auth status` OK. Local mode: `--template-path`, or `--in-place` otherwise.
- **`--sync-flavour app|pat`** — the template-sync workflow pair to keep; **`--keep-specs`** keeps the planning bundles the source tree shipped under `specs/`.
- **`--issue <N>`** (`^[1-9][0-9]*$`) — the bootstrap issue. Required in local mode for any commit (the commit-msg hook needs `(#N)`); in GitHub mode it adopts an existing open issue instead of creating one.
- **`--exec host|container`** — where make targets, raw calls and hooked git calls run, and the value S12 records as `capabilities.run_in_container`. Default: `container` when `docker info` exits 0 and `cargo` is absent (`command -v cargo` fails), else `host`.
- **`--dry-run`** — `new-service.sh --dry-run` plus one `WOULD:` line per step S2–S14; no GitHub mutation, no commit, no push, no make target, no write.
- **Missing values.** An interactive session (a person answers in the conversation) asks once for a missing name and once for a missing sync flavour, then passes the answers as flags. A headless run (`claude -p`, a workflow, a scheduled session) asks nothing and takes the documented defaults: an undecided flavour becomes `SKIP: sync flavour (undecided)` plus `NEXT: re-run with --sync-flavour app|pat` (D18); a missing name defaults, with `--in-place` only, to the basename of the checkout directory (the Compose project name), and is `ESCALATED` before S1 in every other mode.
- Any other argument, a flag without its value, an enumeration value outside its list, two different values for one flag, or `--issue` not matching its pattern → `ESCALATED` before step 0 ends (`blocking_finding: unknown argument <arg>` or `invalid <flag> value <value>`, `recommended_action: run /rs-sdlc-new-service with the flags of its argument hint`); nothing runs and nothing is written.
- **Working directory** — the parent directory of the new checkout (`--dest` is resolved from it), or, with `--in-place`, the root of the checkout itself.
- **Files read** — the plugin's `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-setup.md` (S12) and `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-finish-pr.md` (S14), with the Read tool; in the new repository `docs/new-service.md`, `docs/repository-settings.md`, `.github/pull_request_template.md` and the target list of `make help`.
- **Profile keys** read after S12 validated the profile: `project.default_branch`, `capabilities.run_in_container`, `make.check_commit_message`, `make.install_hooks`, `make.format` and `make.start`. Before S12 the template's targets stand in for the `make.*` keys (see "Execution rules").
- **Iteration counter** `new-service iteration <n>/5`: the hook-failure remediation rounds of S11 and S13, 0 at the start.

## Procedure

### Execution rules (every step)

Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` and `bmalph run`, runs through the Bash tool with `run_in_background: true` (never a trailing `&`), logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled with `common.sh wait_log` at most every 30 s.

In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.

How the two rules apply here:

- **Container mode** means the resolved `--exec container` (from S12 on, `capabilities.run_in_container: true`). S7 and S8 run before any `app` container can exist: `make doctor RUN_IN_CONTAINER=1` checks only what container mode needs on the host, and `make bootstrap RUN_IN_CONTAINER=1` builds the image and starts the stack itself. The precondition check therefore runs first before S9 and again before S10, every `make format` of a remediation round and the hooked git calls of S11, S13 and S14. Empty output and the `start` target listed → `make start RUN_IN_CONTAINER=1` in the background (≤ 900 s, one restart attempt with a new log), then the check again. `docker info` failing, or `app` still not running (D25) → the step and every later step are printed as `NEXT:` lines and the run stops (before S11 when it happens at S9 or S10), `SUCCESS-WITH-REPORT`. The S3 import commit is not a hooked call (hooks are not active yet) and keeps its plain form.
- **Targets.** Before S12 there is no profile, so the template's own targets stand in for the `make.*` keys: `doctor` (`make.doctor`), `bootstrap` (`make.bootstrap`), `generate-openapi-spec` (`make.generate_openapi_spec`), `install-hooks` (`make.install_hooks`), `format` (`make.format`), `start` (`make.start`) and `check-commit-message` (`make.check_commit_message`). S7 reads `make help` once (foreground) and keeps the list of targets it prints; a target missing from that list is treated like a `null` key: its step reports `<target>: not run (capability absent)` with a D1 note and is never replaced by a raw command. From S12 on the profile's keys decide.
- **Make calls** are written in suffix form, variables only after the target and only from the closed set `RUN_IN_CONTAINER COMMIT_TITLE base_ref BREAKING_CHANGE_APPROVED CONFIG_CHANGE_APPROVED group context name SCHEMATHESIS_URL` (here `RUN_IN_CONTAINER=1` on every target in container mode, and `COMMIT_TITLE`); no make option is ever passed. Hooked git calls in container mode carry `RUN_IN_CONTAINER=1` as a prefix (`RUN_IN_CONTAINER=1 git commit -F <path>`, `RUN_IN_CONTAINER=1 git push -u origin HEAD`), so the hooks run their targets in the container.
- **Background wrapper.** Before the first background call one foreground `mkdir -p target/rust-sdlc/logs` in the checkout. Each background call is `{ <command>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-service-<UTC>.log 2>&1` with a fresh `<UTC>` (`YYYYMMDDTHHMMSSZ`), except S8, whose log is `target/rust-sdlc/new-service/bootstrap.log`. The wait is the background-task completion notice, else `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" wait_log <log>` (at most 110 s per call; it prints the last 40 lines and `RUST_SDLC_EXIT=<n>`, or `WAITING: <log> (<elapsed>s)`), called again on `WAITING:` until the exit line appears or the step's budget is spent: 60 min for `make bootstrap`, `make generate-openapi-spec`, `make format`, `scripts/set-version.sh` and every commit and push (their hooks compile and test the workspace), 900 s for `make start`. A wait that outlives its budget ends `ESCALATED` with the last 40 log lines.
- **No Docker (D2).** A log that contains `This target needs a reachable container engine (docker).`, or a failing `docker info` probe taken before the step, classifies the affected target `not run (no Docker)`: never `failed`, never remediated.
- **Results.** Every result line of a step (`DONE:`, `UNCHANGED:`, `SKIP:`, `DEGRADED:`, `NEXT:`, `WOULD:`) is collected for the summary. Every target run or held back gets one targets-run line `<target>: passed | failed | not run (<reason>)` with `<reason>` from the closed set `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`.
- **Placeholders.** `<name>` the service name, `<owner>` the owner, `<REPO>` the `REPO:` handle (`<owner>/<name>`, GitHub mode only), `<CHECKOUT>` the `CHECKOUT:` handle, `<N>` the issue number (written `N` inside the fixed subjects `chore(#N): …` and in `Closes #N`, where it is replaced by that number too), `<branch>` = `chore/<N>-initialize-service`, `<base>` the merge base of S4, `<v>` the target version, `<uid>`/`<gid>` the output of `id -u`/`id -g`. A `'` inside a single-quoted argument is written `'\''`.

### Step 0 — Arguments, execution mode and dry run

1. Check the arguments as "Inputs" describes; resolve a missing name and a missing sync flavour (interactive: one question each; headless: the documented defaults). The values are passed to `new-service.sh` single-quoted, exactly as given; `--issue`, `--exec` and `--dry-run` belong to this command, and only `--dry-run` is passed on.
2. Resolve the execution mode with two read-only probes, unless `--exec` was given:

   ```bash
   docker info
   command -v cargo
   ```

   `docker info` exits 0 and `command -v cargo` fails → `container`; anything else → `host`. Record `--exec <resolved>`; S12 passes it on. The `docker info` result is also the Docker probe of S8 (taken again there).
3. `--dry-run` → run the script's dry run (it validates every flag, prints `WOULD:` lines and its `SUMMARY:` line, and writes nothing):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/new-service.sh" --name '<name>' --dry-run <the pass-through flags>
   ```

   Exit 2 or 1 → `ESCALATED` with its error line. Exit 0 → print one `WOULD:` line for each step S2–S14, in order, with the resolved values: `WOULD: S2 gh label create rust-backend-sdlc (when missing); gh issue create 'Initialize <name> from the Rust service template'` (GitHub mode; local mode: `WOULD: S2 use issue #<N>` or the `<N>` placeholder), then S3 (`WOULD: S3 import commit and push (clone-and-push only)`), S4 to S13 (the call each would make in the resolved execution mode; S5 refers to the script's customize line, S6 to the judgment `NEXT:` lines, S9 to `scripts/set-version.sh <v>` when the copied version differs) and S14 (`WOULD: S14 push, gh pr create, hand-off to /rs-sdlc-finish-pr`; local mode: the `NEXT:` lines it would print). Nothing else runs: no `gh` mutation, no commit, no push, no make target, no write. End with `NEXT: run /rs-sdlc-new-service without --dry-run to create <name>`; the outcome is `SUCCESS`.

### S1 — Source (`new-service.sh --phase source`)

S1 runs `"${CLAUDE_PLUGIN_ROOT}/scripts/new-service.sh" --phase source …` with the name and the pass-through flags:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/new-service.sh" --phase source --name '<name>' <the pass-through flags>
```

The script probes `gh api repos/<slug> --jq .is_template` (GitHub mode), then creates the repository from the template (`is_template` true), or creates an empty repository and imports the template with `git archive` (clone-and-push, `is_template` false), or imports a local checkout (`--template-path`), or skips (`--in-place`, `SKIP: source (in place)`). A second run finds the repository and the matching clone and prints `SKIP: source (exists)`; `gh repo create` never runs twice.

- Exit 0 → parse the handles `SOURCE_MODE:` (`template`, `clone-and-push`, `path` or `in-place`), `REPO:` (GitHub mode only; its presence is how the command knows the mode), `CHECKOUT:`, `SOURCE:` and `SOURCE_SHA:`, and change into `CHECKOUT`: every later step runs with `<CHECKOUT>` as its working directory, and every later `gh` call addresses `<REPO>` through the checkout's `origin`. `S1: DONE source <SOURCE_MODE> (<REPO or CHECKOUT>)`.
- `IMPORT_PENDING: <slug>@<sha>` (clone-and-push) → keep the script's `NEXT: ask the template owner to enable Settings > Template repository` and record `DEGRADED: template flag off: clone-and-push import of <slug>@<sha7> (D17)`.
- A `NEXT: rename the checkout directory to <name> (it is the Compose project name)` line (`--in-place` in a directory with another basename) is kept for the summary.
- Exit 1 (a `REFUSED:` line, a gh failure, a poll timeout) or exit 2 → `ESCALATED` with that line as `blocking_finding`.

### S2 — Label and bootstrap issue

GitHub mode (`REPO:` printed):

1. `--issue <N>` given → `gh issue view <N> --json number,state,labels`. Open → adopt it (`S2: UNCHANGED issue #<N> (adopted)`); a missing `rust-backend-sdlc` label is added after item 2 with `gh issue edit <N> --add-label rust-backend-sdlc`. Closed or not found → `ESCALATED`.
2. Ensure the managed label, created only when missing:

   ```bash
   gh label list --search rust-backend-sdlc --json name --jq '.[].name'
   gh label create rust-backend-sdlc --color 5319e7 --description "Managed by the rust-backend-sdlc plugin"
   ```

   The second call runs only when the first prints no line equal to `rust-backend-sdlc`. No other label is created or applied; the human approval labels and the labels the template lists in `docs/new-service.md` stay `NEXT:` lines (S6).
3. Without `--issue`, adopt an open issue a previous run created: `gh issue list --state open --label rust-backend-sdlc --json number,title --limit 100`, an exact title match `Initialize <name> from the Rust service template` → adopt it. None → create it. Write the body with the Write tool to `target/rust-sdlc/tmp/new-service-issue.raw.md` (its acceptance criteria are the result checks of a new service), redact it, then publish it with `gh issue create --body-file <redacted file>`:

   ```markdown
   ## Summary

   Create `<REPO>` from the Rust service template with /rs-sdlc-new-service: identity, version, service-owned files, sync flavour, bootstrap, plugin setup and a bootstrap pull request.

   ## Acceptance criteria

   - [ ] `make validate-invariants` passes.
   - [ ] `make docs-check` passes.
   - [ ] `make validate-contract-snapshots` passes, with the OpenAPI title `<description> API`.
   - [ ] markdownlint-cli2 and typos pass on `CLAUDE.md`, `AGENTS.md`, `README.md` and `CHANGELOG.md`.
   - [ ] Prettier passes on `bmalph/config.json` and `.claude/rust-sdlc.yml`, and yamllint passes on `.claude/rust-sdlc.yml`.
   - [ ] Where the toolchain and Docker exist, `make ci-preflight base_ref=origin/main CONFIG_CHANGE_APPROVED=` and `make ci-static-analysis` pass.
   ```

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" redact --in target/rust-sdlc/tmp/new-service-issue.raw.md --out target/rust-sdlc/tmp/new-service-issue.md
   gh issue create --title 'Initialize <name> from the Rust service template' --body-file target/rust-sdlc/tmp/new-service-issue.md --label rust-backend-sdlc
   ```

   `gh` prints the issue URL; `<N>` is its last path segment. `S2: DONE issue #<N> created`.
4. Print `ISSUE_NUMBER: <N>`.

Local mode: `--issue <N>` → `ISSUE_NUMBER: <N>` and `S2: UNCHANGED issue #<N> (--issue)`. Without it → `S2: NEXT create the bootstrap issue on the service's GitHub repository, then re-run with --issue <N>`; `<N>` stays a placeholder and S4 and S11–S14 become `NEXT:` lines.

Every `gh` call runs once. A non-zero exit → `ESCALATED` (D10) with the command and its exit code as `blocking_finding` and the first stderr line, redacted, in `iteration_log`; it is never retried in a loop and no `ISSUE_NUMBER:` is printed for an issue `gh` did not return.

### S3 — Import commit (clone-and-push only)

S3 runs only when S1 printed `SOURCE_MODE: clone-and-push`; the template flow already holds GitHub's import commit, an in-place checkout already has its history, and the path mode has no remote to push to (`S3: SKIP import commit (<SOURCE_MODE>)`). It runs before hook activation, by design (Git rules): no toolchain or container exists yet, so the subject is pre-validated with `is_commit_subject` instead of the template's hook, and S11, S13 and S14 require `HOOKS: active`. There is no earlier commit, so the import is the root commit and the protected-change check has no base to compare against.

1. A re-run finds the import on `main` (`git log -1 --format=%s main` prints the subject): with `git rev-parse --verify -q origin/main` succeeding the import is pushed → `S3: UNCHANGED import commit`, nothing runs; without `origin/main` the earlier push did not happen → `git switch main`, then item 5 only.
2. Stage the imported tree: `git add -A`.
3. The subject is `chore(#N): import template <slug> at <sha7>` (`<slug>` from `SOURCE:`, `<sha7>` the first 7 characters of `SOURCE_SHA:`):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" is_commit_subject 'chore(#N): import template <slug> at <sha7>'
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" commit_msg_file 'chore(#N): import template <slug> at <sha7>'
   ```

   A rejection → `ESCALATED`. `commit_msg_file` prints the message-file path `<path>`; the subject never goes on the git command line.
4. Commit in the background: `{ git commit -F <path>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-service-<UTC>.log 2>&1`.
5. Push `main` in the background: `{ git push -u origin HEAD; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-service-<UTC>.log 2>&1`.

Both exit 0 → `S3: DONE import commit <sha7> pushed to main`. Any other exit → `ESCALATED` with the call and its exit code and the last 40 log lines.

### S4 — Bootstrap branch

Needs `<N>`; without it → `S4: NEXT git switch -c chore/<N>-initialize-service` (local mode without `--issue`), and the run continues on the current branch.

1. Record `<default>`: `main` for the template, clone-and-push and path modes (the script creates it), else the branch the in-place checkout is on (`git branch --show-current`). Record `<base>` = `git rev-parse HEAD`, the merge base of the bootstrap branch by construction (a re-run on the branch uses `git merge-base <default> HEAD`). In path mode before the first commit there is no `HEAD`: `<base>` stays empty until S11 makes the root commit.
2. Create the branch:

   ```bash
   git switch -c chore/<N>-initialize-service
   ```

   The branch exists already (a re-run) → `git switch chore/<N>-initialize-service` (`S4: UNCHANGED`). A failure → `ESCALATED` with the call and its exit code. Print `BRANCH: chore/<N>-initialize-service`.

### S5 — Customize (`new-service.sh --phase customize`)

Run the script again with the arguments of S1, `--phase customize` in place of `--phase source`, `--dest` set to the parent directory of `<CHECKOUT>` (with `--in-place` no `--dest`), a relative `--template-path` made absolute (the session now sits inside the checkout, so a relative path would resolve elsewhere), and `--owner <owner>` from `<REPO>` in GitHub mode, so the owner is not resolved twice:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/new-service.sh" --phase customize --name '<name>' --dest '<parent of CHECKOUT>' --owner '<owner>' <the other pass-through flags>
```

The steps run in this order, each printing `DONE:`, `UNCHANGED:`, `SKIP:` or `NEXT:`: identity (`description` and `repository` of `[workspace.package]` only), version check, `bmalph/config.json`, README title, badges and introduction, `CHANGELOG.md` reset, `specs/` reset (skipped with `--keep-specs`), sync flavour, `.templatesyncignore` and the docs-check citation repair (a backticked citation of a deleted sync-flavour file is rewritten to the bare file name, `DONE: docs-check citation <file>:<line>`).

- Exit 0 → `S5: DONE customize (<the SUMMARY: counts>)`. Keep `NEXT: scripts/set-version.sh <v>` for S9 and every `<file>` of a `DONE: docs-check citation` line for S11. `SKIP: sync flavour (undecided)` with `NEXT: re-run with --sync-flavour app|pat` → `DEGRADED: sync flavour undecided: both template-sync workflows kept (D18)`. Every other `NEXT:` line (the repository URL and the README badges in local mode without `--owner`) goes to the summary.
- Exit 1 (a failing step; it leaves its file untouched) or exit 2 → `ESCALATED` with the error line as `blocking_finding`.

### S6 — Judgment steps (always NEXT)

The command takes none of these decisions; it prints them as `NEXT:` lines, read from the new repository's own guides:

- `NEXT: keep the example bounded context for now; remove it later as a guided story (docs/new-service.md section 4)`.
- `NEXT: create the secrets, repository variables and labels that docs/new-service.md section 8 lists (this command never creates a secret, a variable or an approval label)`.
- `NEXT: configure branch protection and the required status checks that docs/repository-settings.md lists`.
- With a kept flavour, `NEXT: create the credentials that the kept template-sync guide names`.

### S7 — Doctor (report only)

Read the target list once:

```bash
make help
```

Then, when `doctor` is listed, in the foreground (`make doctor RUN_IN_CONTAINER=1` in container mode):

```bash
make doctor
```

The doctor is report only: on a fresh host it exits 1 for the pinned tools that S8 installs. Its `[MISSING]` and `[OUTDATED]` lines are shown and the run continues whatever it exits with; it is never remediated. `make doctor: passed` (exit 0) or `make doctor: failed` (any other exit), and `S7: DONE make doctor (report only, exit <n>)`. Not listed → `make doctor: not run (capability absent)`.

### S8 — Bootstrap (`make bootstrap`)

The bootstrap target runs the prerequisite check, installs the pinned tools (host mode) or only the Bats runner (container mode), activates the hooks, runs the full doctor and starts the stack. It runs when `bootstrap` is listed and `docker info` exits 0, in the background with its own log (the directory `target/rust-sdlc/new-service/` exists: S1 and S5 wrote the source record there):

```bash
{ make bootstrap; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/new-service/bootstrap.log 2>&1  # Bash tool, run_in_background: true
{ make bootstrap RUN_IN_CONTAINER=1; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/new-service/bootstrap.log 2>&1  # container mode
```

Poll with `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" wait_log target/rust-sdlc/new-service/bootstrap.log`, which checks every 30 s, at most 60 min in total (about 33 calls).

- `RUST_SDLC_EXIT=0` → `make bootstrap: passed`, `S8: DONE make bootstrap`.
- `docker info` failing, or the log holding the template's no-Docker message → `S8: NOT RUN (no Docker)`, `make bootstrap: not run (no Docker)`, `DEGRADED: container engine unreachable: make bootstrap not run (D2)` and `NEXT: start the container engine, then make bootstrap`; S9 and S10 then fall back to the host toolchain or to `NEXT:` lines.
- `bootstrap` not listed → `make bootstrap: not run (capability absent)` with a D1 note.
- Any other non-zero exit → `make bootstrap: failed` and `ESCALATED` with the first failing line of the log as `blocking_finding` (the last 40 lines above the block). No `RUST_SDLC_EXIT=` line after 60 min → `ESCALATED` with the last 40 lines.

### S9 — Version (`scripts/set-version.sh`)

Runs only when S5 printed `NEXT: scripts/set-version.sh <v>`; S5's `UNCHANGED: version <v>` → `S9: SKIP version <v> unchanged`. The script sets the first `version` line of `[workspace.package]`, refreshes `Cargo.lock` and verifies it, so the version is never edited by hand. It runs in the background:

- Host mode and `command -v cargo` succeeds → on the host:

  ```bash
  scripts/set-version.sh <v>
  ```

- Container mode and the `app` container running (the precondition check of the execution rules) → read `<uid>` and `<gid>` once with `id -u` and `id -g`, then the container route with those literal numbers, `docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh <v>`:

  ```bash
  docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh <v>
  ```

- Otherwise (no host toolchain, or no Docker) → `S9: NEXT scripts/set-version.sh <v>`.

`RUST_SDLC_EXIT=0` → `S9: DONE version <v>`. A non-zero exit → `ESCALATED` with the call, its exit code and the last 40 log lines.

### S10 — OpenAPI snapshot (`make generate-openapi-spec`)

The OpenAPI title is `<description> API` and the contact URL is the `repository` value, so the committed snapshot is stale from S5 on. S10 runs when `generate-openapi-spec` is listed and the mode can build the workspace: in host mode `command -v cargo` succeeds; in container mode S8 passed and the precondition check finds `app` running. Then, in the background:

```bash
{ make generate-openapi-spec; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-service-<UTC>.log 2>&1  # Bash tool, run_in_background: true
{ make generate-openapi-spec RUN_IN_CONTAINER=1; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-service-<UTC>.log 2>&1  # container mode
```

- `RUST_SDLC_EXIT=0` → check the result with `git status --porcelain -- .github/openapi-spec/` and the `title:` line of the snapshot (the Grep tool): it reads `<description> API` → `make generate-openapi-spec: passed`, `S10: DONE OpenAPI snapshot regenerated (title <description> API)` (`UNCHANGED:` on a re-run whose snapshot is already current). Another title → `ESCALATED` (`blocking_finding: OpenAPI title <title>, expected <description> API`).
- The no-Docker message in the log → `make generate-openapi-spec: not run (no Docker)` (D2), then the not-runnable case below. Any other non-zero exit → `make generate-openapi-spec: failed` and `ESCALATED` with the log tail.
- Not runnable (no host toolchain in host mode, S8 not passed in container mode, or D25) → `make generate-openapi-spec: not run (no toolchain)` (or `no Docker`, or `capability absent` when the target is not listed), `S10: NEXT make generate-openapi-spec` (with `RUN_IN_CONTAINER=1` in container mode), and the run stops before S11: S11–S14 are printed as `NEXT:` lines, because a bootstrap commit without a fresh snapshot fails the contract-snapshot gate on the first pull request. The outcome is `SUCCESS-WITH-REPORT`.

### Commit procedure (S11 and S13)

Both commits follow the same sequence; only the staged set and the subject differ.

1. **Hooks.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" hooks_active
   ```

   `HOOKS: active` → continue. `HOOKS: unset` and the `install-hooks` target listed (`make.install_hooks` from S12 on) → `make install-hooks` in the foreground, then `hooks_active` again; still not active, or the target missing → `ESCALATED`. `HOOKS: foreign <value>` → `ESCALATED` with `blocking_finding: core.hooksPath=<value>` and `recommended_action: make install-hooks`. `HOOKS: missing <file>` → `ESCALATED` naming the file. Hooks are activated only by `make install-hooks`; this command never writes `core.hooksPath` itself and never bypasses a hook (`--no-verify` is never passed).
2. **Container precondition** (container mode), as the execution rules say.
3. **Stage** the step's set (S11 and S13 below) and list it with `git diff --cached --name-only`. An empty list on a re-run whose `git log --format=%s <base>..HEAD` already holds the subject → `UNCHANGED: S<k> commit already made`, skip to the next step.
4. **Protected-change guard** (ADR-25), when `<base>` is set:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" protected_changes <base>
   ```

   Exit 0 → continue. A `PROTECTED: <path> (<commit>|working tree)` line → `ESCALATED` (D23) with `blocking_finding: protected file <path> changed (<commit>)` and `recommended_action: revert with git restore --source=<base> -- <path>; customization never changes a protected file` (an intended change needs `approved-config-change`, applied by a maintainer, never by this command, and a session restarted with `ALLOW_PROTECTED_CONFIG_EDIT=1`). The profile is absent at `<base>`, so it is exempt and prints no `PROFILE_CHANGED:` line. Exit 2 → `ESCALATED`.
5. **Pre-validate the subject** in the foreground: `make check-commit-message COMMIT_TITLE='<subject>'` when the `check-commit-message` target is listed (from S12 on: `make.check_commit_message` mapped) and the subject has no space-hyphen sequence; otherwise `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" is_commit_subject '<subject>'` (with `check-commit-message: not run (capability absent)` when the target is missing). A rejection → `ESCALATED`.
6. **Message file:** `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" commit_msg_file '<subject>'` prints `<path>`.
7. **Commit** in the background; the hooks run `make pre-commit` and the commit-msg check:

   ```bash
   { git commit -F <path>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-service-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   { RUN_IN_CONTAINER=1 git commit -F <path>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-service-<UTC>.log 2>&1  # container mode
   ```

8. **Result.** `RUST_SDLC_EXIT=0` and `git log -1 --format=%s` printing the subject → `S<k>: DONE commit <sha7> <subject>`. A non-zero exit is classified from the log:
   - the template's no-Docker message → the hook targets are `not run (no Docker)`; D25: this step and the later ones become `NEXT:` lines and the run stops (`SUCCESS-WITH-REPORT`);
   - a commit-msg rejection (the log names `check-commit-message`) → `ESCALATED` at once: the subject was pre-validated, so a rejection is a defect, never worked around;
   - any other failure is a failing pre-commit hook → one remediation round, below.

**Hook-failure remediation round** (counted by the iteration guard, shared by S11 and S13):

1. Restate `new-service iteration <n>/5`.
2. `make format` in the background (`make format RUN_IN_CONTAINER=1` in container mode). The `format` target missing (`make.format: null` from S12 on) or failing → `ESCALATED`: nothing can remediate the hook.
3. `git diff --name-only` lists what the formatter changed. Nothing → the failure is not a formatting failure: stop at once, `ESCALATED` with the first failing target of the hook log as `blocking_finding`; an identical retry is never made.
4. Re-stage those files (`git add -- <files>`), then repeat items 4–8 of the commit procedure (the guard runs again before the retry).

A fifth round whose retry still fails ends `ESCALATED`. The rounds never edit code beyond what `make format` writes, never retry under another spelling and never skip a hook.

### S11 — Initialize commit

Needs `<N>`; local mode without `--issue` → `S11: NEXT commit the customization as chore(#N): initialize service from template` with the `<N>` placeholder, then S12–S14 as `NEXT:` lines, and the run stops (`SUCCESS-WITH-REPORT`, `DEGRADED: local mode without --issue: S4 and S11–S14 printed as NEXT`).

1. Commit procedure items 1 and 2: `common.sh hooks_active` must end at `HOOKS: active` (S8 normally activated the hooks; `HOOKS: unset` runs `make install-hooks`; `foreign` or `missing` escalates), then the container precondition.
2. Commit procedure item 3 with this set: stage everything the run changed with `git add -A`. Every staged path must belong to the S11 set: `Cargo.toml`, `Cargo.lock`, `bmalph/config.json`, `README.md`, `CHANGELOG.md`, paths under `specs/` and `.github/` (the removed bundles, the deleted flavour pair, the OpenAPI snapshot), `.templatesyncignore`, the files of S5's `DONE: docs-check citation` lines and the files a remediation round formatted. Another staged path → `ESCALATED` before committing (`blocking_finding: unexpected change at S11: <paths>`, `recommended_action: review the listed paths (restore them, or add them to .gitignore when a tool wrote them), then re-run /rs-sdlc-new-service <name> --issue <N>`). In path mode the S11 commit is the root commit and holds the whole imported tree: the set check and item 4 of the commit procedure are skipped, and `<base>` becomes this commit for S13.
3. Commit procedure items 4–8 with the subject `chore(#N): initialize service from template`.

### S12 — Plugin setup (procedure of /rs-sdlc-setup)

Read `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-setup.md` with the Read tool and follow its procedure, steps 1–9, as `/rs-sdlc-setup --exec <resolved>` with the `--exec` value of step 0. The tree is clean after S11, so its step 2 runs `make bmalph-setup` and `_bmad/` exists afterwards; its step 3 translates the flag into `generate-profile.sh --run-in-container true|false`, so the choice is recorded as `capabilities.run_in_container` and takes effect on an existing profile too (ADR-24), and its step 4 validates the profile.

- Setup's `DONE:`, `UNCHANGED:`, `SKIP:`, `DEGRADED:` and `NEXT:` lines and its targets-run lines join this run's lists. Two of its `NEXT:` lines are consumed here and not repeated: the single-commit instruction (S13 makes that commit) and the warning that setup ran on a branch other than the default branch (the bootstrap pull request brings the setup commit to the default branch).
- Setup ending `ESCALATED` → this run ends `ESCALATED` with stage `new-service`, `blocking_finding: S12 setup: <setup's blocking_finding>` and setup's `recommended_action`.
- After it, read the profile keys of "Inputs" with the Read tool: from here on they replace the stand-ins. `S12: DONE setup (--exec <resolved>)`.

### S13 — Profile and governance commit

1. Commit procedure items 1 and 2 again: `HOOKS: active` is required, then the container precondition.
2. Commit procedure item 3 with this set: the three setup files together, as setup requires:

   ```bash
   git add -- .claude/rust-sdlc.yml CLAUDE.md AGENTS.md
   git diff --name-only
   ```

   The second call lists tracked changes left unstaged. Any → `ESCALATED` before committing (`blocking_finding: tracked changes outside the S13 set: <files>`, typically what the bmalph installer wrote; `recommended_action: review them, commit or restore them, then re-run /rs-sdlc-new-service <name> --issue <N>`).
3. Commit procedure items 4–8 with the subject `chore(#N): add rust-backend-sdlc profile and governance`, pre-validated through `make check-commit-message` now that the profile maps `make.check_commit_message`.

### S14 — Title check, push, pull request and hand-off

Local mode (no `REPO:` handle) → `S14: NEXT` lines instead: `NEXT: create the GitHub repository <owner>/<name> and add it as origin`, `NEXT: git push -u origin HEAD`, `NEXT: open the pull request chore(#N): initialize service from template with Closes #N, then run /rs-sdlc-finish-pr`. The run ends there.

GitHub mode: the title check, `HOOKS: active`, `git push -u origin HEAD`, then `gh pr create --body-file <redacted file>` with the body built from the H2s of `.github/pull_request_template.md` and `Closes #N`, then the finish-pr procedure.

1. **Title check.** The title is `chore(#N): initialize service from template`, pre-validated in the foreground with `make check-commit-message COMMIT_TITLE='chore(#N): initialize service from template'` when `make.check_commit_message` is mapped, else with `is_commit_subject`. A rejection → `ESCALATED`.
2. **Hooks.** `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" hooks_active` must print `HOOKS: active` (commit procedure item 1 otherwise). `git status --porcelain --untracked-files=no` must print nothing; tracked changes → `ESCALATED`.
3. **Push.** Container precondition first, then in the background (`RUN_IN_CONTAINER=1 git push -u origin HEAD` in container mode; the pre-push hook runs the unit tests):

   ```bash
   { git push -u origin HEAD; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/new-service-<UTC>.log 2>&1  # Bash tool, run_in_background: true
   ```

   The no-Docker message → D25 (`NEXT:` and stop). Any other non-zero exit → `ESCALATED` with the last 40 log lines; a rejected push is never retried under another spelling and is outside the remediation rounds.
4. **Existing pull request** (a re-run): `gh pr list --head chore/<N>-initialize-service --state open --json number,url --limit 20` → an open one is reused (`S14: UNCHANGED PR #<n>`), and items 5 and 6 are skipped.
5. **Body (ADR-27: raw file → `common.sh redact --in … --out …` → `--body-file`).** Read `.github/pull_request_template.md` and use its level-2 headings in their order (guidance lines dropped, checkbox lists kept with only the boxes that hold ticked); without the template, `## Description`, `## Related issue`, `## How it was tested`, `## Checklist`. Content: the description section summarizes the bootstrap (source mode, identity, version, sync flavour, plugin setup) and repeats the S6 `NEXT:` lines; the related-issue section holds `Closes #N` on its own line; the type-of-change list ticks the build/chore box; the testing section holds this run's targets-run list. Write it with the Write tool to `target/rust-sdlc/tmp/new-service-pr.raw.md`, then:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" redact --in target/rust-sdlc/tmp/new-service-pr.raw.md --out target/rust-sdlc/tmp/new-service-pr.md
   gh pr create --base <project.default_branch> --head chore/<N>-initialize-service --title 'chore(#N): initialize service from template' --body-file target/rust-sdlc/tmp/new-service-pr.md
   ```

   `gh` prints the URL; `<n>` is its last path segment. A non-zero exit → `ESCALATED` (D10), never retried in a loop. The call carries no label, reviewer or draft flag.
6. Print `PR_URL: <url>` and the summary below.
7. **Hand-off.** Read `${CLAUDE_PLUGIN_ROOT}/commands/rs-sdlc-finish-pr.md` with the Read tool and follow its procedure with `--pr <n>` and this hand-off: `ISSUE_NUMBER: <N>`, `SPECS_DIR: none` (the bootstrap has no planning bundle), QA verdict not recorded, this run's targets-run list, and the counters `finish-pr=A0.B0.C0.W0.R0`. From here the finish-pr counters and its exit rules apply; its report and its `## Status:` line end the run.

### Summary and handles

Every exit path except an escalation prints one summary, in this order: one line per step S1–S14, each `S<k>: DONE <evidence>`, `S<k>: UNCHANGED <evidence>`, `S<k>: SKIP <reason>`, `S<k>: NOT RUN (<reason>)` or `S<k>: NEXT <command or decision>`; the targets-run list; every `DEGRADED:` note; every remaining `NEXT:` line (S6 and the steps printed as `NEXT:`); the handles `ISSUE_NUMBER: <N>`, `BRANCH: chore/<N>-initialize-service` and, in GitHub mode, `PR_URL: <url>`; and one closing line, `DONE: new-service <name> (S1–S14 executed or printed as NEXT; bootstrap PR handed to finish-pr)` when every step except the judgment step S6 executed, else `NEXT: new-service <name> (<k> step(s) besides S6 printed as NEXT; run them in order, or re-run /rs-sdlc-new-service <name> --issue <N> once the cause is fixed)`. In local mode the closing line is always the `NEXT:` form, because S14 is a `NEXT:` step there.

The outcome is `SUCCESS` when no `DEGRADED:` line was recorded, `SUCCESS-WITH-REPORT` when at least one was (D1, D2, D17, D18, D25, local mode without `--issue`, setup's own notes), and `ESCALATED` when a step stopped with the block below.

## Loop & exit condition

Exit string (stage `new-service`, byte-identical in the loop documentation): S1–S14 executed or printed as NEXT, bootstrap PR handed to finish-pr (GitHub mode)

The stage is one pass through S1–S14. Its only loop is the hook-failure remediation of S11 and S13 (`make format`, re-stage, retry); the one `make start` restart attempt of the container precondition is a retry, not a loop. A re-run with the same arguments (and `--issue <N>` once the issue exists) is safe: S1 prints `SKIP: source (exists)`, S2 adopts the issue, S3 and S11 find their commits, S4 switches to the existing branch and S14 reuses the open pull request. Degrade paths (D1, D2, D17, D18, D25, local mode) never loop and never fake a pass: a step that did not run is printed as `NEXT:` or reported `not run (<reason>)` with its note. `SUCCESS` and `SUCCESS-WITH-REPORT` both mean the exit string holds; the orchestrator records `met: yes (degraded)` for the latter. After the S14 hand-off the finish-pr procedure's own exit string and counters decide the pull request's state.

## Iteration guard

`MAX_ITERATIONS=5`, counting the hook-failure remediation rounds at S11 and S13: a failing pre-commit hook → `make format`, re-stage, retry. The counter is restated before each round as `new-service iteration <n>/5`, is shared by both commits and is never reset within a run. A round in which `make format` changes nothing ends the stage at once instead of repeating an identical attempt, and a fifth failing round ends it too. After the hand-off the finish-pr counters apply as `rs-sdlc-finish-pr.md` defines them (A 5, B 5, C 3, W 6, R 3), starting at `A0.B0.C0.W0.R0`. Nothing else is retried: a script refusal, a `gh` failure, a failing bootstrap, version or snapshot target, a commit-msg rejection, a protected change and a rejected push stop the stage at once.

## Failure escalation

Every exit that is not `SUCCESS` or `SUCCESS-WITH-REPORT` prints the summary lines of the steps reached, the last 40 log lines or the refusal line above it, then this block, filled in, and nothing after it:

```text
=== SDLC ESCALATION ===
stage: new-service
iteration: <n>/5
exit_condition: S1–S14 executed or printed as NEXT, bootstrap PR handed to finish-pr (GitHub mode)
status: NOT MET
blocking_finding: <S<k>: refusal line | command + exit code (make bootstrap exit 2) | core.hooksPath=<value> | protected file <path> changed (<commit>) | file:line>
iteration_log: <one line per iteration: "<n>: make format, git commit -F <path> -> <result>", or "0: S<k> <what ran> -> <result>" when the stop came before any remediation round>
recommended_action: <the human action: a corrected flag, gh auth login, a hook or tool fix, a review of the listed paths, then /rs-sdlc-new-service <name> --issue <N> again>
=== END ===
```

Triggers, each with its `blocking_finding` and `recommended_action`:

- Unknown argument, invalid value, or a headless run without a name outside `--in-place` → the argument; run /rs-sdlc-new-service with the flags of its argument hint.
- S1 or S5 script exit 1 or 2 → the `REFUSED:` or error line; fix what it names (an existing repository or checkout, uncommitted template changes, a malformed configuration), then run again.
- A `gh` failure at S2 or S14 (D10), or an `--issue` that is closed or missing → the command and its exit code; `gh auth login`, network access to github.com or the missing repository permission, then run again.
- S3 commit or push failing, S4 `git switch -c` failing → the call and its exit code; fix the git identity or the remote, then run again.
- `make bootstrap` failing or exceeding 60 min (not D2) → the first failing log line; install what `make doctor` reports missing, then run again with `--issue <N>`.
- `scripts/set-version.sh` failing, `make generate-openapi-spec` failing (not D2) or a wrong OpenAPI title → the call and its exit code, or the title; fix the cause, then run again.
- `HOOKS: foreign <value>` → `core.hooksPath=<value>`; `make install-hooks`. `HOOKS: missing <file>`, or hooks still inactive after `make install-hooks` → the `HOOKS:` line; restore the hook file from the template.
- An unexpected path at S11 or a tracked change outside the S13 set → the paths; review, then commit or restore them.
- A protected change before a commit (D23) → `protected file <path> changed (<commit>)`; `git restore --source=<base> -- <path>`.
- A commit-msg rejection, a pre-commit failure that `make format` does not change, or a fifth failing remediation round → the first failing hook target; fix the code the hook names, then run again with `--issue <N>`.
- S12 setup escalating → `S12 setup: <its blocking_finding>`; setup's recommended action.
- A rejected push (pre-push hook or remote) → `git push -u origin HEAD exit <n>`; fix what the hook names or integrate the remote branch by hand, then run again.
