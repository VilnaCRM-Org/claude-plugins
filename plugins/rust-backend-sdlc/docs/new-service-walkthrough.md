# New-service walkthrough

This walkthrough creates a new Rust microservice from the service template with one command, `/rs-sdlc-new-service`, and follows it from nothing to a bootstrap pull request that the PR-finishing loop takes over. It shows what each of the fourteen steps S1–S14 prints, which of them a person still decides, and the five traps the sequence is built to avoid. The command contract lives in `commands/rs-sdlc-new-service.md`; the per-step rules live in the `service-scaffolding` skill; the setup procedure the command runs at S12 is described in the [setup walkthrough](setup-walkthrough.md), and the profile it writes in the [profile schema](profile-schema.md).

## Before you start

- Install the plugin and meet the version floors of the [setup walkthrough](setup-walkthrough.md#version-floors); `gh auth status` must report an account in GitHub mode.
- Decide the service name (kebab-case, at most 50 characters). It names the GitHub repository and the checkout directory, and the directory name becomes the Compose project name.
- Decide the template-sync flavour: `app` (a GitHub App) or `pat` (a fine-grained token). A headless run that does not name one keeps both workflows and reports the flavour as undecided.
- Decide where make targets run. With Docker reachable and no Rust toolchain on the host, the command defaults to container mode; otherwise to host mode. `--exec host|container` overrides the default, and S12 records the choice in the profile as `capabilities.run_in_container`.

## Run the command

In the directory that will hold the new checkout (or, with `--in-place`, at the root of an unmodified template checkout):

```text
/rs-sdlc-new-service <name> --description <text> --sync-flavour app|pat
```

The flags and their defaults:

| Flag | Default | Effect |
| --- | --- | --- |
| `<name>` | asked once in an interactive session; with `--in-place` a headless run takes the checkout directory name | repository `<owner>/<name>`, checkout `<dest>/<name>` |
| `--description <text>` | `<name>` | `[workspace.package].description`, so the OpenAPI title `<description> API` |
| `--owner <org>` | the login of `gh api user --jq .login` (GitHub mode only) | the repository owner and the `repository` URL |
| `--intro <text>` | the description | the README introduction |
| `--version <x.y.z>` | `default_version` of the plugin's `config/new-service.defaults.json` | the first release version, set through `scripts/set-version.sh` |
| `--visibility private\|public` | `default_visibility` of the same file | the new repository's visibility |
| `--template <owner/repo>`, `--template-path <dir>`, `--in-place` | the configured template in GitHub mode | the source; at most one of the three |
| `--dest <parent-dir>` | `.` | the parent directory of the checkout |
| `--sync-flavour app\|pat` | asked once in an interactive session; headless: undecided | the template-sync pair that stays |
| `--keep-specs` | off | keep the planning bundles the template shipped under `specs/` |
| `--issue <N>` | none | adopt an existing issue; required in local mode for any commit |
| `--exec host\|container` | `container` when `docker info` exits 0 and `cargo` is absent, else `host` | where targets, raw calls and hooked git calls run |
| `--dry-run` | off | print what would happen; create, commit, push and write nothing |

GitHub mode is the default (`--template`, no source flag, or `--in-place` in a checkout with a github.com `origin`). Local mode is `--template-path <dir>`, or `--in-place` without a GitHub `origin`: nothing is created on GitHub, and every commit needs `--issue <N>`.

An example invocation for a service owned by an organization:

```text # profile-example
/rs-sdlc-new-service billing-service --description "Billing service" --owner acme --sync-flavour app
```

## Preview with a dry run

`--dry-run` runs the script's own dry run and prints one `WOULD:` line per later step, with no GitHub call that changes anything and no write:

```text # profile-example
WOULD: source template (gh repo create acme/billing-service --template VilnaCRM-Org/rust-service-template --private; gh repo clone acme/billing-service /home/sam/src/billing-service)
WOULD: customize /home/sam/src/billing-service (identity, version, bmalph-config, readme, changelog, specs, sync-flavour, templatesyncignore, docs-check-citations)
SUMMARY: done=2 unchanged=0 skip=0 next=0
WOULD: S2 gh label create rust-backend-sdlc (when missing); gh issue create 'Initialize billing-service from the Rust service template'
WOULD: S3 import commit and push (clone-and-push only)
WOULD: S4 git switch -c chore/<N>-initialize-service
WOULD: S5 new-service.sh --phase customize (the customize line above)
WOULD: S6 print the judgment steps as NEXT lines
WOULD: S7 make doctor
WOULD: S8 make bootstrap
WOULD: S9 scripts/set-version.sh 0.1.0 (only when the copied version differs)
WOULD: S10 make generate-openapi-spec
WOULD: S11 git commit -F <path> (chore(#N): initialize service from template)
WOULD: S12 /rs-sdlc-setup --exec host
WOULD: S13 git commit -F <path> (chore(#N): add rust-backend-sdlc profile and governance)
WOULD: S14 push, gh pr create, hand-off to /rs-sdlc-finish-pr
NEXT: run /rs-sdlc-new-service without --dry-run to create billing-service
```

## The sequence S1–S14

Every step is either executed (it prints `DONE:`, `UNCHANGED:` or `SKIP:`) or printed as a `NEXT:` line with the exact command or decision. The plugin's `new-service.sh` creates the repository and makes every deterministic file edit (S1, S5) and never commits; the command owns the GitHub calls, the branch, the commits and the push.

| Step | What runs | Executed when | Otherwise |
| --- | --- | --- | --- |
| S1 | `new-service.sh --phase source` | always | — |
| S2 | managed label `rust-backend-sdlc`, bootstrap issue | GitHub mode | local mode: `--issue <N>`, else `NEXT:` |
| S3 | import commit and push of `main` | clone-and-push | skipped |
| S4 | `git switch -c chore/<N>-initialize-service` | `<N>` known | `NEXT:` |
| S5 | `new-service.sh --phase customize` | always | a failing step escalates |
| S6 | judgment steps | never | always `NEXT:` |
| S7 | `make doctor`, report only | the target exists | not run |
| S8 | `make bootstrap` in the background | Docker reachable | `NOT RUN (no Docker)` |
| S9 | `scripts/set-version.sh <v>` | the version differs and a toolchain or the `app` container exists | `NEXT:` |
| S10 | `make generate-openapi-spec` in the background | the host toolchain or a bootstrapped container exists | `NEXT:` and the run stops before S11 |
| S11 | hooks check, then the initialize commit | `<N>` known | `NEXT:` and the run stops |
| S12 | the /rs-sdlc-setup procedure with `--exec` | after S11 | — |
| S13 | the profile and governance commit | after S12 | — |
| S14 | title check, push, pull request, hand-off to /rs-sdlc-finish-pr | GitHub mode | `NEXT:` |

The sample lines below come from a GitHub-mode run in host mode with the template flag on (paths and numbers are illustrative).

### S1 Source

The script probes whether the template repository is marked as a GitHub template. With the flag on, it creates the repository from the template, waits for its first commit with a bounded poll and clones it; with the flag off, it creates an empty repository and imports the template's tracked files (clone-and-push). The command then changes into the checkout:

```text # profile-example
DONE: source template (gh repo create acme/billing-service --template VilnaCRM-Org/rust-service-template --private; gh repo clone acme/billing-service /home/sam/src/billing-service)
SOURCE_MODE: template
REPO: acme/billing-service
CHECKOUT: /home/sam/src/billing-service
SOURCE: VilnaCRM-Org/rust-service-template
SOURCE_SHA: 3e0bd3ed26cfc452402cefb46137e03a330fccbb
SUMMARY: done=1 unchanged=0 skip=0 next=0
```

With the template flag off the run continues, reports the degrade and keeps the advice for the template owner:

```text # profile-example
DONE: source clone-and-push (gh repo create acme/billing-service --private; import VilnaCRM-Org/rust-service-template into /home/sam/src/billing-service)
IMPORT_PENDING: VilnaCRM-Org/rust-service-template@3e0bd3ed26cfc452402cefb46137e03a330fccbb
NEXT: ask the template owner to enable Settings > Template repository
DEGRADED: template flag off: clone-and-push import of VilnaCRM-Org/rust-service-template@3e0bd3e (D17)
```

A second run with the same arguments finds the repository and its clone and prints `SKIP: source (exists)`; the repository is never created twice.

### S2 Bootstrap issue

The managed label is created only when it is missing, and the issue body, whose acceptance criteria are the result checks of a new service (invariants, docs-check, contract snapshots, linters on the governance files and the profile), is redacted before it is published:

```text # profile-example
S2: DONE issue #1 created
ISSUE_NUMBER: 1
```

In local mode the issue comes from `--issue <N>`. Without it the run prints `S2: NEXT create the bootstrap issue on the service's GitHub repository, then re-run with --issue <N>`, and S4 and S11–S14 become `NEXT:` lines too.

### S3 Import commit

Only the clone-and-push mode needs it: the import is committed on `main` as `chore(#N): import template <slug> at <sha7>` and pushed with `git push -u origin HEAD`. It is the one commit made before the git hooks are active, by design, because no toolchain or container exists yet; its subject is checked with the plugin's `is_commit_subject` instead of the template hook. In the template flow GitHub already made the import commit:

```text # profile-example
S3: SKIP import commit (template)
```

### S4 Bootstrap branch

```text # profile-example
S4: DONE branch chore/1-initialize-service
BRANCH: chore/1-initialize-service
```

### S5 Customize

The script applies the deterministic steps of the template's `docs/new-service.md` and reports each one:

```text # profile-example
DONE: identity Cargo.toml (description, repository)
UNCHANGED: version 0.1.0
DONE: bmalph-config bmalph/config.json
DONE: readme README.md
UNCHANGED: changelog CHANGELOG.md
DONE: specs removed specs/rust-service-template-bootstrap
DONE: sync flavour app deleted .github/workflows/template-sync-pat.yml
DONE: sync flavour app deleted .github/TEMPLATE_SYNC_PAT.md
DONE: templatesyncignore .github/workflows/template-sync-pat.yml
DONE: templatesyncignore .github/TEMPLATE_SYNC_PAT.md
DONE: docs-check citation docs/extension-seams.md:82
SUMMARY: done=9 unchanged=2 skip=0 next=0
```

A version other than the copied one prints `NEXT: scripts/set-version.sh <v>`, which S9 executes. A headless run without `--sync-flavour` prints `SKIP: sync flavour (undecided)` and `NEXT: re-run with --sync-flavour app|pat` instead of the flavour, `.templatesyncignore` and citation lines.

### S6 Judgment steps

The command decides none of these; they stay `NEXT:` lines for a person:

```text
NEXT: keep the example bounded context for now; remove it later as a guided story (docs/new-service.md section 4)
NEXT: create the secrets, repository variables and labels that docs/new-service.md section 8 lists (this command never creates a secret, a variable or an approval label)
NEXT: configure branch protection and the required status checks that docs/repository-settings.md lists
NEXT: create the credentials that the kept template-sync guide names
```

### S7 Doctor

`make doctor` runs in the foreground and only reports: on a fresh host it lists the pinned tools that the bootstrap installs and exits 1, and the run continues.

```text # profile-example
S7: DONE make doctor (report only, exit 1)
make doctor: failed
```

### S8 Bootstrap

`make bootstrap` installs the pinned tools (host mode) or only the Bats runner (container mode), activates the git hooks, builds and starts the stack. It runs in the background, writes `target/rust-sdlc/new-service/bootstrap.log` and is polled every 30 s for at most 60 minutes. Without Docker it is not run, and the run reports why:

```text # profile-example
S8: DONE make bootstrap
make bootstrap: passed
```

```text # profile-example
S8: NOT RUN (no Docker)
make bootstrap: not run (no Docker)
DEGRADED: container engine unreachable: make bootstrap not run (D2)
NEXT: start the container engine, then make bootstrap
```

### S9 Version

Runs only when S5 printed `NEXT: scripts/set-version.sh <v>`: on the host in host mode, through `docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh <v>` in container mode, and as a `NEXT:` line when neither the host toolchain nor the `app` container is available.

```text # profile-example
S9: SKIP version 0.1.0 unchanged
```

### S10 OpenAPI snapshot

`make generate-openapi-spec` rewrites the committed snapshot so that its title matches the new description. Without a toolchain to run it the command prints the target as `NEXT:` and stops before S11, because a bootstrap commit with a stale snapshot fails the contract-snapshot check of the first pull request.

```text # profile-example
S10: DONE OpenAPI snapshot regenerated (title Billing service API)
make generate-openapi-spec: passed
```

### S11 Initialize commit

The command checks that the hooks are active (`HOOKS: active`, else `make install-hooks`), stages the customization, the version, `Cargo.lock` and the snapshot, runs the protected-change check, and commits `chore(#N): initialize service from template` through a message file. The pre-commit hook runs the fast gates; when it fails, the command runs `make format`, stages the formatted files and retries, at most five rounds, and escalates when formatting changes nothing.

```text # profile-example
S11: DONE commit 4f2a9c1 chore(#1): initialize service from template
```

### S12 Setup

The command follows the /rs-sdlc-setup procedure with the resolved `--exec`, on the now-clean tree: preflight, `make bmalph-setup`, profile, governance block, local allowlist, hooks and docs-check. The setup's own commit instruction is not repeated, because S13 makes that commit.

```text # profile-example
S12: DONE setup (--exec host)
DEGRADED: .claude/settings.json is protected (protected-config.toml lists it); allowlist kept in .claude/settings.local.json (D4)
```

### S13 Profile and governance commit

`.claude/rust-sdlc.yml`, `CLAUDE.md` and `AGENTS.md` are committed together as `chore(#N): add rust-backend-sdlc profile and governance`, with the hooks active. Any other tracked change left by the setup stops the run for review instead of being committed silently.

```text # profile-example
S13: DONE commit 8b17d0e chore(#1): add rust-backend-sdlc profile and governance
```

### S14 Pull request and hand-off

The command checks the title `chore(#N): initialize service from template`, requires `HOOKS: active`, pushes with `git push -u origin HEAD` (the pre-push hook runs the unit tests), builds the body from the headings of the repository's `.github/pull_request_template.md` with `Closes #N`, redacts it, opens the pull request and hands it to the /rs-sdlc-finish-pr procedure, which loops until CI is green, the FR/NFR gate is green on the head commit and no review thread is open. In local mode S14 prints the push and the pull request as `NEXT:` lines.

```text # profile-example
S14: DONE PR #2 created; handed to finish-pr
PR_URL: https://github.com/acme/billing-service/pull/2
```

## Sample summary

The command ends with one summary: a line per step, the targets-run list, the degrade notes, the remaining `NEXT:` lines, the handles and one closing `DONE:` or `NEXT:` line. A complete GitHub-mode run:

```text # profile-example
S1: DONE source template (acme/billing-service)
S2: DONE issue #1 created
S3: SKIP import commit (template)
S4: DONE branch chore/1-initialize-service
S5: DONE customize (done=9 unchanged=2 skip=0 next=0)
S6: NEXT keep the example bounded context; secrets, variables and labels; branch protection; sync credentials
S7: DONE make doctor (report only, exit 1)
S8: DONE make bootstrap
S9: SKIP version 0.1.0 unchanged
S10: DONE OpenAPI snapshot regenerated (title Billing service API)
S11: DONE commit 4f2a9c1 chore(#1): initialize service from template
S12: DONE setup (--exec host)
S13: DONE commit 8b17d0e chore(#1): add rust-backend-sdlc profile and governance
S14: DONE PR #2 created; handed to finish-pr
make doctor: failed
make bootstrap: passed
make generate-openapi-spec: passed
check-commit-message: passed
make bmalph-setup: passed
make install-hooks: passed
make docs-check: passed
DEGRADED: .claude/settings.json is protected (protected-config.toml lists it); allowlist kept in .claude/settings.local.json (D4)
NEXT: keep the example bounded context for now; remove it later as a guided story (docs/new-service.md section 4)
NEXT: create the secrets, repository variables and labels that docs/new-service.md section 8 lists (this command never creates a secret, a variable or an approval label)
NEXT: configure branch protection and the required status checks that docs/repository-settings.md lists
NEXT: create the credentials that the kept template-sync guide names
ISSUE_NUMBER: 1
BRANCH: chore/1-initialize-service
PR_URL: https://github.com/acme/billing-service/pull/2
DONE: new-service billing-service (S1–S14 executed or printed as NEXT; bootstrap PR handed to finish-pr)
```

The degrade note comes from the setup step (a template-derived repository protects `.claude/settings.json`), so this run ends `SUCCESS-WITH-REPORT`; without any `DEGRADED:` line it ends `SUCCESS`. The finish-pr report follows the summary.

A host without Docker and without a Rust toolchain stops before the first commit, and the summary says what is left:

```text # profile-example
S8: NOT RUN (no Docker)
S9: SKIP version 0.1.0 unchanged
S10: NEXT make generate-openapi-spec
S11: NEXT commit the customization as chore(#1): initialize service from template
S12: NEXT /rs-sdlc-setup --exec host
S13: NEXT commit .claude/rust-sdlc.yml, CLAUDE.md and AGENTS.md as chore(#1): add rust-backend-sdlc profile and governance
S14: NEXT git push -u origin HEAD, then open the pull request with Closes #1 and run /rs-sdlc-finish-pr
make bootstrap: not run (no Docker)
make generate-openapi-spec: not run (no toolchain)
DEGRADED: container engine unreachable: make bootstrap not run (D2)
NEXT: start the container engine, then make bootstrap
NEXT: new-service billing-service (5 step(s) besides S6 printed as NEXT; run them in order, or re-run /rs-sdlc-new-service billing-service --issue 1 once the cause is fixed)
```

## Traps

### OpenAPI title is `<description> API`

The template builds the OpenAPI title from `[workspace.package].description` and the contact URL from `repository`. S5 changes both, so the committed snapshot under `.github/openapi-spec/` is stale until it is regenerated; the contract-snapshot check would then fail on the first pull request. S10 regenerates the snapshot and checks that its title reads `<description> API` before S11 commits it, and the command never makes the initialize commit without a fresh snapshot. Pick the description with the title in mind: `--description "Billing service"` gives the title `Billing service API`.

### Directory name is the Compose project

The Makefile derives the Compose project and the image names from the checkout directory name (lower-cased, characters outside `a-z0-9_-` replaced by `-`), and CI checks out into a directory named after the repository. The command therefore always clones into `<dest>/<name>`. With `--in-place` in a directory of another name it prints `NEXT: rename the checkout directory to <name> (it is the Compose project name)`; stop a stack started under the old name before renaming, and never override the project name with a variable.

### Version only through `scripts/set-version.sh`

A repository created from the template copies the version the template last released and none of its tags. The version changes only through the template's `scripts/set-version.sh`, which rewrites the `version` line of `[workspace.package]`, refreshes `Cargo.lock` and verifies it. S5 compares the versions and S9 runs the script on the host or in the `app` container; when neither can run, the `NEXT: scripts/set-version.sh <v>` line stays in the summary. Never edit the version line or `Cargo.lock` by hand.

### Sync flavour

The template ships two template-sync workflows, each with a guide: the App flavour and the token flavour. Keep exactly one: `--sync-flavour app|pat` keeps that pair, deletes the other workflow and guide, and adds the deleted paths to `.templatesyncignore` so the next sync does not restore them. An interactive session asks for the flavour once; a headless run without the flag keeps both and prints `SKIP: sync flavour (undecided)` with `NEXT: re-run with --sync-flavour app|pat`, and the run ends `SUCCESS-WITH-REPORT` (D18). The kept guide names the credentials to create; the command never creates a secret.

### Docs-check citation repair

The template's `docs/extension-seams.md` backtick-cites both sync guides. Deleting the guide of the other flavour, as the template's own instructions say, leaves a backticked path to a missing file, and docs-check rule 3 then fails on the first pull request. Right after the flavour deletion, S5 rewrites each such citation to the bare file name, adds each edited file to `.templatesyncignore` (otherwise the next sync restores the citation) and prints `DONE: docs-check citation <file>:<line>`; a second run prints `UNCHANGED: docs-check citations`. Citations of the kept pair stay as they are, and S12 runs docs-check to prove the result.

## Re-running and escalations

A run can be repeated with the same arguments, plus `--issue <N>` once the issue exists: the source step prints `SKIP: source (exists)`, the issue is adopted, existing commits and the branch are found, and an open bootstrap pull request is reused. When a step cannot continue, the command prints the canonical escalation block with stage `new-service`, the step's evidence as `blocking_finding` and the human action as `recommended_action`, for example a missing tool reported by `make doctor`, a hook that `make format` cannot satisfy, or a foreign `core.hooksPath`. Fix the cause, then run the command again.

## K9/K13 record

This section is filled by the first post-release run: the hands-on time from the command to the bootstrap pull request (K9, target at most 15 minutes) and the bootstrap pull request with every check that no human gates green on its first push (K13). No run is recorded yet.
