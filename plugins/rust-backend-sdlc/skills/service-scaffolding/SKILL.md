---
name: service-scaffolding
description: Use when creating a new Rust microservice from the service template with /rs-sdlc-new-service, re-running or resuming one of its steps S1–S14, or planning the guided story that removes the template's example bounded context from a freshly created service. Covers the `is_template` probe and the clone-and-push import, the OpenAPI title trap (`<description> API`, so the snapshot is regenerated before the first pull request), the checkout directory as the Compose project, the version set only through `scripts/set-version.sh`, the sync flavour, local mode with `base_ref=HEAD` until `origin/main` exists, and the bootstrap and doctor targets in host or container mode. Skip when the repository is an existing service whose bootstrap pull request has merged and no example-context removal is planned. Not for adding a bounded context (use bounded-context-scaffolding), not for preparing an existing template-derived repository for the plugin (that is /rs-sdlc-setup), not for the documentation of the new service (use documentation-creation).
---

# Service Scaffolding

## Profile keys consumed

- `project.name` — the Compose project and image-name prefix, derived from the checkout directory basename; it must equal the service name
- `project.repo` — the GitHub `<owner>/<name>` of the new service; non-null selects GitHub mode, null selects local mode
- `template.repository` — the template the kept sync workflow pulls from; it also identifies an `--in-place` checkout that is not yet customized; null when no sync workflow names one
- `template.sync_flavour` — the template-sync workflow the service keeps: `app`, `pat`, `both` (undecided) or `none`
- `make.bootstrap` — the fresh-clone preparation target of S8 (prerequisite check, tools, hooks, build, start); null means S8 is not run
- `make.doctor` — the host prerequisite and pinned-tool report of S7; null means S7 is not run
- `make.generate_openapi_spec` — the OpenAPI snapshot generator of S10 and of the example-removal story; null means the regeneration is a `NEXT:` line
- `capabilities.run_in_container` — `true`: every target call gets `RUN_IN_CONTAINER=1` and raw calls go through the `app` container; `false`: targets, git and raw calls run on the host toolchain

## Context

A new service starts as a copy of the Rust service template and changes very little: the `description`, `repository` and `version` lines of `[workspace.package]` in the root `Cargo.toml`, the service-owned files (`bmalph/config.json`, the README title, badges and introduction, `CHANGELOG.md`, the planning bundles under `specs/`), one of the two template-sync flavours, and the checkout directory name. Everything else (Compose project, image names, the OpenAPI title and contact URL) is derived from those values. The template's own guide for this is `docs/new-service.md` of the new repository; it wins where it is stricter.

/rs-sdlc-new-service runs the ordered sequence S1–S14 of this skill and reports every step as EXECUTED (the `DONE:`, `SKIP:` or `UNCHANGED:` lines of the step) or as NEXT (a `NEXT:` line: a human decision or a step it could not take). The deterministic edits come from `new-service.sh` (phase `source`, then phase `customize`); the command owns every commit and push. This skill holds the sequence, the condition under which each step is executed or printed as `NEXT:`, and the five traps that break a first pull request:

1. **Template flag.** The template repository may not be marked as a GitHub template, so "use this template" is not always available; the source step probes it and falls back to clone-and-push.
2. **OpenAPI title.** The OpenAPI title is `<description> API`. A new `description` changes the generated document, so the committed snapshot is stale until it is regenerated and committed; the contract-snapshot gate then fails in CI on the first pull request.
3. **Checkout directory.** The Makefile derives the Compose project and the image names from the checkout directory basename, so the directory name is part of the service identity.
4. **Version.** A repository created from the template copies the version the template last released and none of its tags. The version changes only through `scripts/set-version.sh`, which also refreshes and verifies `Cargo.lock`.
5. **Example context.** The template ships one example bounded context. Removing it in the bootstrap change breaks the documentation check and possibly the GraphQL schema, so it is kept and removed later as a guided story.

Before S12 the new repository has no `.claude/rust-sdlc.yml`. Until then each key is stood in for by what the command already knows: `project.name` by the `--name` value and the `CHECKOUT:` basename, `project.repo` by the `REPO:` handle (absent in local mode), `template.repository` by the `SOURCE:` handle, `template.sync_flavour` by `--sync-flavour`, `make.bootstrap`, `make.doctor` and `make.generate_openapi_spec` by the template's targets of the same purpose, and `capabilities.run_in_container` by the resolved `--exec` mode. From S12 on, the generated profile holds the same values and is the source.

## Task

Take a service from nothing (or from an unmodified `--in-place` checkout) to a customized repository with active hooks, a valid profile and governance block, and a bootstrap pull request handed to PR finishing. Run S1–S14 in order, execute each step whose condition holds, print every other step as a `NEXT:` line with the exact command or decision, avoid the five traps, and keep the example context. When asked for the removal of the example context, plan it as a guided story instead of doing it inside the bootstrap change.

## Success criteria

- Every step S1–S14 is reported exactly once, in order, as EXECUTED (`DONE:`, `SKIP:` or `UNCHANGED:` from the scripts) or as NEXT (a `NEXT:` line); the command's one closing `DONE:`/`NEXT:` summary lists them.
- The checkout directory basename, lower-cased with every character outside `a-z0-9_-` replaced by `-`, equals the service name, so `project.name` equals it after S12.
- The OpenAPI snapshot committed by S11 was generated after the `description` edit, so its title is `<description> API` and the contract-snapshot gate passes on the bootstrap pull request.
- The `version` line of `[workspace.package]` was changed only by `scripts/set-version.sh`, or a `NEXT: scripts/set-version.sh <v>` line was printed.
- Exactly one sync flavour remains (`template.sync_flavour` is `app` or `pat` after S12), or the run reports `SKIP: sync flavour (undecided)` and the re-run `NEXT:` line and counts the result as not met.
- The example context is untouched, and the S6 `NEXT:` line names its removal as a later guided story.
- In GitHub mode the bootstrap pull request exists with `Closes #N`; in local mode S14 is a `NEXT:` line and every base-ref reader got `base_ref=HEAD` while `origin/main` was absent.

## Steps

### 1. Resolve the keys and the mode

Read the eight keys (from the stand-ins before S12, from the profile after it) and branch:

- **Mode.** `project.repo` non-null (or a `REPO:` handle): GitHub mode, so S2, S3 (clone-and-push only) and S14 run. `project.repo` null (no `REPO:` handle): local mode, so the issue number comes from `--issue <N>`, nothing is pushed, S14 is a `NEXT:` line, and step 8 applies.
- **Execution.** `capabilities.run_in_container` `true`: every target call carries `RUN_IN_CONTAINER=1` after the target (suffix form, the closed variable set); hooked git calls carry it as a prefix (`RUN_IN_CONTAINER=1 git commit -F <path>`, `RUN_IN_CONTAINER=1 git push -u origin HEAD`); raw calls go through `docker compose exec -T --user <uid>:<gid> app <command>` with the ids resolved once from `id -u` and `id -g`. `false`: targets, git and raw calls run on the host, which needs the pinned toolchain.
- **Identity.** `template.repository` non-null: an `--in-place` checkout whose `[workspace.package]` `repository` still names it is not yet customized and may be scaffolded. Null: no sync workflow names a source, so `--in-place` relies on the source record that phase `source` or the first customize run wrote under `target/rust-sdlc/new-service/`; without it, phase `customize` refuses with `REFUSED: in-place target already customized`.

### 2. Probe the template and import it (S1)

Phase `source` of `new-service.sh` first probes `gh api repos/<slug> --jq .is_template`, where `<slug>` is the `--template` value or the plugin's configured default:

- **`true` (template flow):** `gh repo create <owner>/<name> --template <slug> --private|--public` without `--clone`, a bounded poll of `gh api 'repos/<owner>/<name>/commits?per_page=1' --jq length` until the first commit exists (a timeout exits 1, no retry loop), then `gh repo clone <owner>/<name> <checkout>`. The import commit already exists on GitHub, so S3 does not run.
- **`false` (clone-and-push):** `gh repo create <owner>/<name> --private|--public` (empty), a shallow `gh repo clone <slug> <tmp> -- --depth 1`, `git -C <tmp> archive HEAD | tar -x -C <checkout>` (tracked files only, fresh history), `git -C <checkout> init -b main` and `origin` set to the new repository. It prints `IMPORT_PENDING: <slug>@<sha>` and `NEXT: ask the template owner to enable Settings > Template repository`; the run continues and ends at best `SUCCESS-WITH-REPORT` (D17). S3 then makes and pushes the import commit.
- **`--template-path <dir>` (local):** the same `git archive HEAD` import from a local checkout whose tracked tree is clean, with no remote and no push.
- **`--in-place`:** `SKIP: source (in place)`; a checkout basename other than the name prints the rename `NEXT:` line of step 5.
- **Re-run:** the repository exists and the checkout's `origin` matches → `SKIP: source (exists)`; the repository exists with no matching checkout → exit 1 with the reason. A second `gh repo create` never runs.

Parse `SOURCE_MODE:`, `REPO:`, `CHECKOUT:`, `SOURCE:` and `SOURCE_SHA:` and change into `CHECKOUT` before S2.

### 3. Run S1–S14 in order

| Step | Action | EXECUTED when | Otherwise (NEXT, SKIP or NOT RUN) |
| --- | --- | --- | --- |
| S1 | `new-service.sh --phase source …` (step 2) | always | — |
| S2 | ensure the label `rust-backend-sdlc`; create the bootstrap issue `Initialize <name> from the Rust service template` with the G1(c) checks as acceptance criteria, body through a redacted file; print `ISSUE_NUMBER:` | GitHub mode | local mode takes `--issue <N>`; without it `<N>` stays a placeholder |
| S3 | `git add -A`; commit `chore(#N): import template <slug> at <sha7>` (pre-validated with `common.sh is_commit_subject`, committed with `git commit -F <path>`); `git push -u origin HEAD` on `main` | `SOURCE_MODE: clone-and-push` | not run in the template, path and in-place modes |
| S4 | `git switch -c chore/<N>-initialize-service` | `<N>` is known | `NEXT:` with the `<N>` placeholder |
| S5 | `new-service.sh --phase customize …` (identity, version check, `bmalph/config.json`, README, CHANGELOG, `specs/` reset unless `--keep-specs`, sync flavour, `.templatesyncignore`, docs-check citation repair) | always | a failing step exits 1 and leaves its file untouched: escalate |
| S6 | judgment steps: keep the example context (step 10); secrets, variables and labels from `docs/new-service.md`; branch protection and required checks from `docs/repository-settings.md` | never | always `NEXT:` |
| S7 | the doctor target (step 9), report only | `make.doctor` mapped | `not run (capability absent)` |
| S8 | the bootstrap target (step 9), in the background, log `target/rust-sdlc/new-service/bootstrap.log`, polled with `common.sh wait_log` every 30 s, at most 60 min; it already runs `make install-hooks` | `make.bootstrap` mapped and `docker info` exits 0 | `NOT RUN (no Docker)` (D2, `SUCCESS-WITH-REPORT`), or `not run (capability absent)` |
| S9 | `scripts/set-version.sh <v>` (step 6) | S5 printed `NEXT: scripts/set-version.sh <v>` and a host toolchain or the `app` container exists | `NEXT: scripts/set-version.sh <v>` |
| S10 | the OpenAPI snapshot target (step 4), in the background | S8 succeeded or the host toolchain exists, and `make.generate_openapi_spec` is mapped | `NEXT:` with the target, and the run stops before S11 |
| S11 | `common.sh hooks_active` (`HOOKS: unset` → `make install-hooks` and a re-check; `foreign` or `missing` → escalate); commit `chore(#N): initialize service from template` (identity, version, `Cargo.lock`, snapshot, service-owned files); the hooks run `make pre-commit` | `<N>` is known | local mode without `--issue`: `NEXT:` with the `<N>` placeholder, and the run stops |
| S12 | the procedure of /rs-sdlc-setup with `--exec <resolved>` on the now-clean tree, so `make bmalph-setup` runs and `_bmad/` and `.ralph/` exist; the explicit flag takes effect on an existing profile | after S11 | — |
| S13 | commit `chore(#N): add rust-backend-sdlc profile and governance` (`.claude/rust-sdlc.yml`, `CLAUDE.md` and `AGENTS.md` together, `HOOKS: active`) | after S12 | — |
| S14 | the title check, `HOOKS: active`, the push and the pull request (commands below the table), with the H2s of `.github/pull_request_template.md` and `Closes #N` in the body; hand-off to the /rs-sdlc-finish-pr procedure | GitHub mode | local mode: `NEXT:` lines for the push and the pull request |

S14 in detail, each call on its own:

- Title check (foreground): `make check-commit-message COMMIT_TITLE='chore(#N): initialize service from template'`.
- Push: `git push -u origin HEAD`.
- Pull request: `gh pr create --body-file <redacted file>`, the body written to a raw file and redacted before it is published.

Every commit runs only after the protected-change check of the calling command and through `git commit -F <path>` with the message file of `common.sh commit_msg_file`. S3 is the one commit made before hook activation, by design: no toolchain or container exists yet, so its subject is pre-validated with `common.sh is_commit_subject`; S11, S13 and S14 need `HOOKS: active`. A failing pre-commit hook at S11 or S13 is remediated with `make format`, a re-stage and a retry, at most five rounds; when the commit still fails after the fifth round, the run escalates.

### 4. Regenerate the OpenAPI snapshot before the first pull request (S10)

The OpenAPI title is `<description> API` and the contact URL is the `repository` value, both read from `[workspace.package]`. Phase `customize` changes both, so the committed snapshot under `.github/openapi-spec/` is stale from S5 on.

- `make.generate_openapi_spec` mapped: run it in the background after S8 (or on the host toolchain when S8 did not run), then confirm with `git status --porcelain -- .github/openapi-spec/` that the snapshot changed and that its `title` line reads `<description> API`. S11 commits it with the identity edit. A snapshot that is regenerated but left uncommitted fails the contract-snapshot gate, which requires an empty `git status --porcelain` for both snapshots.
- `make.generate_openapi_spec` null: print `NEXT:` naming the service's own snapshot generator (read it from `make help`) and stop before S11; a bootstrap commit without a fresh snapshot is never made.

### 5. Name the checkout directory after the service

The Makefile sets the Compose project to the checkout directory basename, lower-cased, with every character outside `a-z0-9_-` replaced by `-`; the images are named `<project>-app:dev`, `<project>-app:prod` and `<project>-load`. `project.name` is detected by the same rule. On a GitHub runner the checkout directory equals the repository name, so CI needs no edit.

- `--dest` is the parent directory; the checkout is always `<dest>/<name>`, so the rule holds by construction.
- `--in-place` in a directory with another basename prints `NEXT: rename the checkout directory to <name> (it is the Compose project name)`. When the stack was already started under the old name, stop it with `make down` before the rename, so no containers of the old project remain.
- After S12, `project.name` different from the service name means the rename has not happened: report it as a `NEXT:` line and never set the project name through a variable or an edited Compose file.

### 6. Change the version only through `scripts/set-version.sh` (S9)

Phase `customize` compares the copied `version` with the target (`--version`, else the plugin default) and prints `UNCHANGED: version <v>` or `NEXT: scripts/set-version.sh <v>`. The script rewrites the first `version` line of `[workspace.package]` only, refreshes `Cargo.lock` and verifies it. Run it as:

- `capabilities.run_in_container` `false` with a host toolchain: `scripts/set-version.sh <v>` from the repository root.
- `capabilities.run_in_container` `true` with the `app` container running: `docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh <v>`.
- Neither: keep the `NEXT: scripts/set-version.sh <v>` line; S11 then commits the old version, and the line stays in the summary.

Never edit the `version` line by hand, never edit `Cargo.lock` by hand, and never create a tag: release tags come from the service's own release workflow.

### 7. Keep exactly one sync flavour

The template ships two workflows that merge template changes into the service: the App flavour (`template-sync-app.yml`, guide `TEMPLATE_SYNC_APP.md`) and the token flavour (`template-sync-pat.yml`, guide `TEMPLATE_SYNC_PAT.md`). Phase `customize` keeps the pair named by `--sync-flavour app|pat`, deletes the other pair, appends both deleted paths to `.templatesyncignore` (the sync would restore them otherwise) and repairs the docs-check citations that named the deleted files. Branch on `template.sync_flavour` (before S12: on the flag):

- `app` or `pat`: one flavour is kept. Print `NEXT:` for the credentials its guide names (secrets of the App or the fine-grained token); a missing credential makes the sync job skip itself with a notice, never fail.
- `both`: the flavour is undecided. In an interactive session ask once; headless, the run prints `SKIP: sync flavour (undecided)` and `NEXT: re-run with --sync-flavour app|pat` (D18), and the creation counts as not met until phase `customize` runs again with the flag.
- `none`: the repository has no sync workflow, so it receives no template updates. Print `SKIPPED: sync flavour (no sync workflow in the repository)`; there is nothing to keep or delete.

### 8. Local mode: `base_ref=HEAD` until `origin/main` exists

In local mode (`project.repo` null, `--template-path`, or `--in-place` without a GitHub `origin`) the repository has no `origin/main`. Every target that reads `base_ref` (`validate-configuration`, `mutation-tests-diff`, `openapi-diff`, `graphql-diff` and the stages that run them) would fall back to the Makefile default and exit 2 with "base ref origin/main is not available". So:

- Pass `base_ref=HEAD` explicitly to every base-ref reader, with a D24 degrade note (`base ref unavailable: using HEAD`, `SUCCESS-WITH-REPORT`).
- Keep doing so until a GitHub remote exists and the first push created `origin/main`; from then on pass the merge base with the default branch.
- Print `NEXT:` lines for what local mode cannot do: create the GitHub repository, set `repository` in `[workspace.package]` once it exists (phase `customize` prints that line when `--owner` was not given), push, and open the bootstrap pull request.

### 9. Run doctor and bootstrap in the resolved execution mode (S7, S8)

Both targets come from the template and differ by mode. Branch on `capabilities.run_in_container` (before S12: on the resolved `--exec`, which defaults to container when `docker info` exits 0 and `cargo` is absent, else host):

- **Host (`false`).** The doctor target (`make.doctor`) checks the host prerequisites and every pinned Rust tool; the bootstrap target (`make.bootstrap`) runs the prerequisite check, installs the pinned tools on the host, activates the hooks, runs the full doctor and starts the stack.
- **Container (`true`).** Append `RUN_IN_CONTAINER=1`: the doctor target then skips the host toolchain checks (the development container provides them), and the bootstrap target installs only the Bats runner on the host, activates the hooks, builds the image and starts the stack.

S7 is report only: on a fresh host it exits 1 for the tools S8 installs, and its `[MISSING]`/`[OUTDATED]` lines are shown while the run continues. S8 runs only when `docker info` exits 0; when Docker is unreachable it is `NOT RUN (no Docker)` and S9 and S10 fall back to the host toolchain or to `NEXT:` lines. A null key reports its step `not run (capability absent)` (D1); the run continues and ends at best `SUCCESS-WITH-REPORT`.

### 10. Keep the example context; remove it only as a guided story

S6 prints `NEXT: keep the example context; remove it later as a guided story`. The script and the command never remove it. When a later task asks for the removal, plan it as one story of the feature loop (/rs-sdlc with a task such as "remove the example bounded context"), after the first real context exists, with these acceptance criteria:

1. **Find the example.** It is the `<group>/<context>` whose crates directory the template's `.templatesyncignore` lists below `crates/`. Collect its traces with `git grep -n` over its crate and package names: the three `[workspace].members` paths, its `[workspace.dependencies]` entries, its migration, its feature files and end-to-end steps, its wiring in `crates/service`, the tests that build the `Adapters` literal, the pinned contract tests, and its components and relationships in `workspace.dsl`.
2. **Edit the three docs-check rule-3 lines.** After the crates are gone, three synchronised Markdown lines still cite the removed directory as a backticked path: one in the template skill `.claude/skills/api-resource-development/SKILL.md` and one in each sync guide (`.github/TEMPLATE_SYNC_APP.md`, `.github/TEMPLATE_SYNC_PAT.md`; only the kept guide remains after S5). Rule 3 of the documentation check fails on a backticked path whose first segment is tracked and which is missing on disk. Rewrite each cited path to the first real context's directory, or drop the backticks around it; find any further line with `git grep -n` on the removed directory.
3. **Update `.templatesyncignore`.** Append each synchronised file edited in criterion 2 once (the sync would restore the template's line otherwise), and keep the entries that already list the example's paths, so the sync never restores the removed files.
4. **Replace, never delete, the GraphQL roots.** The schema module of the composition root (`crates/service/src/graphql/schema.rs`) merges one query field and one mutation field per context into its `Query` and `Mutation` roots. Replace the example's fields with the first real context's roots in the same change; never delete a root and never leave a merged root without a field, because the template gives no evidence that such a schema builds.
5. **Regenerate the snapshots.** Run the target mapped by `make.generate_openapi_spec` and `make generate-graphql-spec` and commit both snapshots in the same change. The removed operations are breaking changes for the contract diffs against the base; the label `approved-breaking-change` is a human decision, so the story escalates naming it and never applies it.
6. **Migrations.** Before the service was ever deployed, the example migration is removed with the rest. After a deployment applied it, it stays, and a new reversible migration drops the example's table instead (see [database-migrations](../database-migrations/SKILL.md)).
7. **Prove it.** The full gate sequence passes stage by stage (see [verification-workflow](../verification-workflow/SKILL.md)), including the documentation check and the contract-snapshot gate, with 0 protected files changed.

While no real context exists, the removal stays a `NEXT:` line: the example's GraphQL roots have nothing to be replaced with.

## Constraints

- Never remove the example context inside the bootstrap change, never delete the GraphQL roots, and never leave a merged root without a field.
- Never edit the `version` line or `Cargo.lock` by hand: the version changes only through `scripts/set-version.sh`.
- Never open the bootstrap pull request with an OpenAPI snapshot older than the `description` edit.
- Never name the checkout directory differently from the service, and never override the Compose project name to hide a mismatch.
- Never run a second `gh repo create` for an existing repository, never pass `--clone` to it, and never poll without the bound of the source step.
- Never commit without `git commit -F <path>` and a pre-validated subject, never commit at S11, S13 or S14 without `HOOKS: active`, and never push any other way than `git push -u origin HEAD`.
- Never pass `--no-verify` to a commit or push, never use `git push --force` and never write `core.hooksPath` with `git config`: hooks are activated only by the template's `make install-hooks`.
- Never let a base-ref reader fall back to the Makefile default in local mode: pass `base_ref=HEAD` until `origin/main` exists.
- Never apply or remove `approved-breaking-change` or `approved-config-change`, and never write a protected file; a needed protected change escalates.
- Never write secrets, repository variables or branch protection: those stay `NEXT:` lines for a human.
- The hook-failure remediation is bounded at five rounds and every other degrade ends in a report; no step is retried in an open loop.

## Verification

- One line per step, in order: `S<n>: DONE <evidence>`, `S<n>: SKIP <reason>`, `S<n>: NOT RUN (<reason>)` or `S<n>: NEXT <command or decision>`, followed by the closing `DONE:`/`NEXT:` summary.
- Evidence for the traps: the `SOURCE_MODE:` handle (and `IMPORT_PENDING:` for clone-and-push), `basename "$PWD"` equal to the service name, the `title` line of the committed OpenAPI snapshot, the `version` line of `[workspace.package]` or the `NEXT: scripts/set-version.sh <v>` line, `ls .github/workflows/template-sync-*.yml` showing one file (or the undecided or no-sync line), and the S6 line keeping the example context.
- In local mode, the D24 note for every target that received `base_ref=HEAD`.
- Targets-run rows in the FR-1 vocabulary for the doctor, bootstrap and OpenAPI snapshot targets: `<target>: passed | failed | not run (<reason>)`.
- The handles `ISSUE_NUMBER:`, `BRANCH:` and, in GitHub mode, `PR_URL:`.

### Escalation

A failing customize step, `HOOKS: foreign` or `HOOKS: missing`, a commit that still fails after the fifth hook-remediation round, a protected change, or a gh failure ends the run with the canonical block:

```text
=== SDLC ESCALATION ===
stage: new-service
iteration: <n>/5
exit_condition: S1–S14 executed or printed as NEXT, bootstrap PR handed to finish-pr (GitHub mode)
status: NOT MET
blocking_finding: <step id, command and exit code, or file:line>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human action, for example a hook fix, a label, or a new run that names the sync flavour>
=== END ===
```
