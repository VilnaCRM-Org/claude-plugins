# Setup walkthrough

This walkthrough takes a checkout of a Rust service derived from the service template from nothing to a repository the plugin can drive: install the plugin, run `/rs-sdlc-setup` once, make one commit. The command contract lives in `commands/rs-sdlc-setup.md`; the profile it writes is described in [the profile schema](profile-schema.md).

## Version floors

`/rs-sdlc-setup` checks these floors first (step 1, `setup-preflight.sh --report`); it prints every check with its remediation and stops the run when any tool is below its floor:

- bmalph ≥ 2.11.0 (or absent and installable by `make bmalph-setup` with node and npm)
- claude ≥ 2.1.248 (`--restricted`, used by the isolated FR/NFR gate session)
- gh ≥ 2.0, authenticated (`gh auth status`)
- python3 ≥ 3.11 (`tomllib`)
- GNU make ≥ 4.0
- bash ≥ 4.4
- git ≥ 2.30
- node ≥ 20 (bmalph installer, workflow harness)
- jq optional (python3 is the fallback)

YAML is read with mikefarah `yq` v4 when it is on `PATH`, else with python3 and PyYAML; one of the two must be present. Docker is needed in container mode and by the template targets that need a container engine; the Rust toolchain is needed on the host only in host mode.

## Install the plugin

```bash
claude plugin marketplace add VilnaCRM-Org/claude-plugins
claude plugin install rust-backend-sdlc@vilnacrm-plugins
```

### Use the user scope

Keep the install at user scope, the default of `claude plugin install` (`--scope user`). A user-scope plugin is available in every Claude Code session you start, including the headless sessions that bmalph's Ralph loop starts during the implement stage, so the `rust-backend-sdlc:rust-implementer` agent resolves there and independent stories may run as parallel subagents. Without the agent, the planning bundle tells Ralph to implement stories one after another under the same database rule, so both cases are correct; the user scope only adds the parallel path. A project-scope install would have to be recorded in `.claude/settings.json`, which a template-derived repository protects.

Restart Claude Code after the install so the commands load.

## Prepare the checkout

- Open the repository root, on the default branch.
- Commit or stash your own tracked changes first: on a dirty tracked tree setup skips the bmalph installation (see "Dirty tracked tree" below).
- Run `gh auth login` once if `gh auth status` reports no account.

## Run the setup command

```text
/rs-sdlc-setup
```

The flags are optional: `--refresh` (re-detect the profile), `--exec host|container` (where make targets and hooked git calls run), `--print-settings` (print the allowlist instead of writing it) and `--with-qa-network` (accepted for compatibility, writes nothing extra). The command runs nine steps in this order and is safe to repeat:

| Step | What runs | What it may write |
| --- | --- | --- |
| 1 Preflight | `setup-preflight.sh --report`; any `FAIL` row stops the run with the table | nothing |
| 2 bmalph workspace | `make bmalph-setup`, only when `_bmad/` is absent, the target is mapped and the tracked tree is clean; then the bmalph floor is checked again | `_bmad/` (git-ignored) and what the bmalph installer writes |
| 3 Profile | `generate-profile.sh`, with `--refresh` passed through and `--exec` translated to `--run-in-container` | `.claude/rust-sdlc.yml` |
| 4 Validation | `validate-profile.sh`; on failure at most 5 regenerations with `--refresh` | the profile, only when it regenerates |
| 5 Governance | `inject-governance.sh` | the managed block in `CLAUDE.md` and `AGENTS.md` |
| 6 Allowlist | `merge-settings.sh` | `.claude/settings.local.json` |
| 7 Hooks | `hooks_active` from the plugin library; `make install-hooks` when the hooks are unset | the local git hook setting |
| 8 docs-check | `make docs-check` in the background, when the toolchain or the container can run it | build output under `target/` |
| 9 Summary | the commit check and the branch check | nothing |

Setup is complete when the preflight has no `FAIL`, the profile is valid, the governance markers are in both files, the allowlist is written or printed, and docs-check passed or was skipped with a degrade note. The outcome is `SUCCESS` without degrade notes, `SUCCESS-WITH-REPORT` with at least one `DEGRADED:` line, and `ESCALATED` when a step stops the run.

## Sample output

### First run

A first run on a fresh checkout of a template-derived service, in host mode:

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

The D4 note is expected on every template-derived repository: the template protects `.claude/settings.json`, so the allowlist goes to the local settings file, and the run ends `SUCCESS-WITH-REPORT`.

### Re-run after the commit

Every file a step writes is already in its target state; the preflight, validation and docs-check results print `DONE:` on every run:

```text
DONE: preflight (pass=14 warn=0 fail=0 info=3)
DONE: validate-profile (VALID)
DONE: docs-check passed
SKIP: bmalph-setup (_bmad/ present)
UNCHANGED: .claude/rust-sdlc.yml
UNCHANGED: CLAUDE.md
UNCHANGED: AGENTS.md
UNCHANGED: .claude/settings.local.json
UNCHANGED: hooks (HOOKS: active)
UNCHANGED: setup result already committed
make docs-check: passed
DEGRADED: .claude/settings.json is protected (protected-config.toml lists it); allowlist kept in .claude/settings.local.json (D4)
```

### Run with degrade notes

A checkout with uncommitted edits to two tracked files, no `_bmad/` yet and no Rust toolchain on the host:

```text
DONE: preflight (pass=13 warn=0 fail=0 info=4)
DONE: profile .claude/rust-sdlc.yml written
DONE: validate-profile (VALID)
DONE: governance CLAUDE.md updated
DONE: governance AGENTS.md updated
DONE: allowlist .claude/settings.local.json (+66 allow, +29 deny)
DONE: hooks activated with make install-hooks
make install-hooks: passed
make docs-check: not run (no toolchain)
DEGRADED: make bmalph-setup not run (tracked changes: Cargo.toml README.md)
DEGRADED: .claude/settings.json is protected (protected-config.toml lists it); allowlist kept in .claude/settings.local.json (D4)
DEGRADED: no host toolchain and container mode off: make docs-check not run (D3)
NEXT: commit or stash, then make bmalph-setup
NEXT: run /rs-sdlc-setup --exec container, or install the Rust toolchain, then make docs-check
NEXT: commit .claude/rust-sdlc.yml, CLAUDE.md and AGENTS.md together in one commit
```

A target that did not run is never reported as passed: it carries `not run (<reason>)` and a `DEGRADED:` note.

## Commit the result in one commit

Commit `.claude/rust-sdlc.yml`, `CLAUDE.md` and `AGENTS.md` together, and nothing else:

```bash
git add .claude/rust-sdlc.yml CLAUDE.md AGENTS.md
git commit -m 'chore(#<N>): add rust-backend-sdlc profile and governance'
```

In container mode (`capabilities.run_in_container: true`), keep the `app` container running and commit with the variable in front, because the pre-commit hook runs `make pre-commit`, whose gates otherwise run `cargo` on the host:

```bash
RUN_IN_CONTAINER=1 git commit -m 'chore(#<N>): add rust-backend-sdlc profile and governance'
```

The governance block cites `.claude/rust-sdlc.yml` in backticks, and the template's docs-check fails a backticked path that does not exist. Locally the profile exists on disk, so docs-check passes before the commit; CI checks out only committed files, so a block committed without its profile fails CI. The subject follows the template's commit-message rule `<type>(#<issue>): <subject>`, and the hooks that step 7 activated check it.

Bring this commit onto the default branch before feature work starts, directly or through a short pull request when the default branch only accepts pull requests. The loop stages compare the profile with the merge base of their feature branch and escalate when it changed there, so a profile that exists only on a feature branch stops them. Setup prints a warning when it runs on any other branch than the default branch.

## Protected settings and `.claude/settings.local.json`

The template lists `.claude/settings.json` in `protected-config.toml`. Setup never writes `.claude/settings.json` when `protected-config.toml` lists it; in fact it never writes that file at all. The allow entries and the plugin-owned deny entries go to `.claude/settings.local.json`, which the template's `.gitignore` already ignores:

- The merge is a union: your existing entries keep their bytes and order, and `ask`, hooks and `defaultMode` stay untouched. The template's own deny and ask rules stay effective, because Claude Code evaluates deny before ask before allow.
- The file is per machine: it holds the absolute path of the installed plugin and your numeric uid and gid. Never commit it.
- When `.claude/settings.local.json` is not git-ignored, setup refuses to write it, prints the merged JSON instead and records `DEGRADED: .claude/settings.local.json is not git-ignored: allowlist printed, not written`; add the file to `.gitignore` and run setup again.
- `--print-settings` prints the merged JSON and writes nothing.
- `--with-qa-network` is accepted for compatibility and adds nothing: QA probes go through the plugin library's loopback-only HTTP helper, never through a `curl` allow entry.
- Setup never sets `bypassPermissions`.

The full allow and deny tables, and why the template's prefix deny rules need the plugin's own deny entries, are in the plugin's permissions guide (`docs/permissions.md`).

## Dirty tracked tree

`make bmalph-setup` runs only on a clean tracked tree (`git status --porcelain --untracked-files=no` prints nothing), because the bmalph installer may change tracked files and its changes should be reviewable on their own. On a dirty tree setup does not stop: it skips that one target, prints

```text
DEGRADED: make bmalph-setup not run (tracked changes: <files>)
NEXT: commit or stash, then make bmalph-setup
```

and continues with the profile, governance, allowlist, hooks and docs-check. Commit or stash your changes, then run `make bmalph-setup` (or `/rs-sdlc-setup` again). Untracked files, the new profile among them, do not count as changes.

## Host or container execution (`--exec`)

`capabilities.run_in_container` decides where the plugin runs make targets and hooked git calls:

- `--exec host` writes `false`: targets and hooks run on the host and need the Rust toolchain (`cargo` on `PATH`).
- `--exec container` writes `true`: targets run in the `app` container (`make <target> RUN_IN_CONTAINER=1`) and hooked commits run with `RUN_IN_CONTAINER=1`; Docker must be reachable. Before docs-check, setup checks `docker compose ps --status running --quiet app` and starts the stack with `make start` when `app` is not running (at most 900 s, one restart attempt).
- Without `--exec`, an existing profile keeps its value; a new profile takes `true` when `docker info` succeeds and `cargo` is not on `PATH`, else `false`.

On a configured repository an explicit `--exec` changes only that key, without `--refresh`:

```text
DONE: profile .claude/rust-sdlc.yml (capabilities.run_in_container=true)
```

The value is user-owned: `--refresh` keeps it. Commit the changed profile on the default branch (in container mode with `RUN_IN_CONTAINER=1 git commit`, see "Commit the result in one commit"). When docs-check cannot run (no toolchain in host mode, Docker unreachable or `app` not starting in container mode), setup records a D3 or D25 degrade note instead of a pass.

## Re-run after a template-sync merge

The template's sync overwrites `CLAUDE.md` and `AGENTS.md`, which removes the managed block. The loop stages then halt with "run /rs-sdlc-setup on the default branch and commit the result". After the sync pull request is merged, on the default branch:

1. Run `/rs-sdlc-setup`. The block is restored (`DONE: governance CLAUDE.md updated`) with no change to the text outside the markers.
2. When the sync changed what the profile detects (a make target, a gate threshold, a workflow), step 3 keeps the committed profile and prints `DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)` with the difference. Run `/rs-sdlc-setup --refresh` to adopt it; the five user-owned keys (`capabilities.run_in_container`, `capabilities.dynamic_security_testing`, `capabilities.publish_pr_comments`, `review.reviewers`, `review.ai_review_agents`) keep their values.
3. Commit the profile, `CLAUDE.md` and `AGENTS.md` together, as above.

## Re-run after `claude plugin update`

```bash
claude plugin update rust-backend-sdlc@vilnacrm-plugins
```

Restart Claude Code, then run `/rs-sdlc-setup` again in every repository that uses the plugin:

- The allow entries name the absolute plugin root, which includes the version directory of the plugin cache. The re-run adds the entries for the new root, for example `DONE: allowlist .claude/settings.local.json (+28 allow, +0 deny)`. The old entries stay, because the merge never removes anything; delete them by hand as the permissions guide describes.
- A release that adds profile keys makes the committed profile fail validation; setup then regenerates it with `--refresh` (at most 5 attempts, user-owned keys kept) and reports `DONE: profile regenerated with --refresh (setup iteration 1/5)`.
- A release that changes the governance text updates the block in both files.

Commit whatever the summary lists in one commit.

## When setup escalates

A step that cannot reach its target state stops the run with the escalation block and nothing after it. A preflight failure, for example:

```text
FAIL: gh-auth: gh auth status reports no authenticated account — remediation: run gh auth login
SUMMARY: pass=12 warn=0 fail=1 info=4
=== SDLC ESCALATION ===
stage: setup
iteration: 0/5
exit_condition: preflight without FAIL, profile valid, markers in both files, allowlist present or printed, docs-check passed or degraded with a note
status: NOT MET
blocking_finding: FAIL: gh-auth: gh auth status reports no authenticated account — remediation: run gh auth login
iteration_log: 0: setup-preflight.sh --report -> 1 FAIL
recommended_action: run gh auth login
=== END ===
```

Other stops: a failing `make bmalph-setup`, a profile that stays invalid after its regenerations, a refused governance or settings file, a hook path set by another hook manager (`blocking_finding: core.hooksPath=<value>`, `recommended_action: make install-hooks`), a missing hook file and a failing docs-check. Fix what `blocking_finding` names, then run `/rs-sdlc-setup` again; every file a completed step wrote reports `UNCHANGED:` on the next run (the preflight, validation and docs-check results, and the allowlist under `--print-settings`, print `DONE:` each time they run).
