---
name: documentation-sync
description: Use when a change to a Rust service adds, renames or removes a make target, a `service` command or flag, an environment variable, an endpoint or GraphQL field, a pull-request workflow job or an operational procedure, so every page that cites it changes in the same commit and the drift check mapped by `make.docs_check` and the invariants mapped by `make.validate_invariants` stay green. Service-owned targets go to make/service.mk and docs/make-targets-service.md, never to the template Makefile. Skip a proof run, reported as not run, when its key is null. Not for writing a page that does not exist yet (use documentation-creation) and not for the code side of a new setting (use configuration-management).
---

# Documentation Sync

## Profile keys consumed

- `make.docs_check` — the documentation-drift target (rules 1 to 7: citations, the environment-variable reference, the make-target references, the skill index); null means its proof is `not run (capability absent)`
- `make.validate_invariants` — the repository-invariant target (among its rules: the gate set and the required checks against the pull-request workflows, the repository name, the licence); null means its proof is `not run (capability absent)`

## Repository precedence

Read `.claude/skills/documentation-sync/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line.

The surface table below restates the template skill's mapping, adjusted for what a template sync overwrites, so that it also serves a repository whose own skill is missing or older. When the repository skill and this table disagree, follow the repository skill and record the difference in the evidence.

## Context

Documentation changes in the same commit as the code it describes. Two targets prove it:

- **The drift check** (mapped by `make.docs_check`) reads every tracked Markdown file except `CHANGELOG.md` and `specs/`, and treats inline code spans and fenced lines as citations. It fails when a cited `make <target>` or `service <command>` does not exist (rules 1 and 2), when a slash-command span has no file under `.claude/commands/` (rule 2), when a backticked path neither exists nor is git-ignored (rule 3), when the verification block of `AGENTS.md` differs from the gate list or another list or fence cites three or more gate targets (rule 4), when `docs/environment.md` misses a variable or keeps a row nothing reads (rule 5), when a target is missing from `make help` or from its reference table (rule 6), and when a repository skill lacks a name, a description or an index entry (rule 7).
- **The invariants** (mapped by `make.validate_invariants`) check, among other rules, that the gate set of the pull-request workflows equals the gate list and that every job a service workflow adds is listed in `docs/repository-settings.md` or in the service's `docs/repository-settings-service.md` (rule (d)), and that the template's repository name occurs only where it is allowed (rule (e)). The rule letters and texts are in the header of `scripts/check-invariants.sh`; read them there.

A template sync overwrites every file the template ships unless `.templatesyncignore` lists it. Service additions therefore live in service-owned files: targets in `make/service.mk` and `docs/make-targets-service.md` (the template ships neither), workflow jobs in `docs/repository-settings-service.md`, variables in `.env`, `.env.test` and `docs/environment.md`. Read `.templatesyncignore` at runtime before writing into any page the template ships.

Surface table (trigger, then the pages to update in the same commit):

| Trigger | Update in the same commit | Never |
| --- | --- | --- |
| A service-owned make target is added, renamed or removed | the target in `make/service.mk` with a help comment (`## <text>` after the prerequisites) so `make help` lists it; a row for it in `docs/make-targets-service.md` whose first cell is the backticked target name; every page that cites the old name | the template `Makefile` or `docs/make-targets.md`, which the sync overwrites |
| A `?=` variable is declared in `make/service.mk` | its row in `docs/environment.md`, through [configuration-management](../configuration-management/SKILL.md) | a variable declared in the template `Makefile` |
| A `service` command, subcommand or flag changes | every page that cites `service <command>` (rule 2 reads the help of the binary); the rows of its variables, through configuration-management | citing a command the help does not list |
| An environment variable is added, renamed or removed | configuration-management end to end (code, `.env`, `.env.test`, the `docs/environment.md` row) | a row without a reader, or a reader without a row |
| An endpoint or a GraphQL field changes | `docs/requests.http` (one request per endpoint); the contract snapshots, regenerated through [api-contract-development](../api-contract-development/SKILL.md); the example in `README.md` when it shows one | a hand-edited snapshot |
| A pull-request workflow job or required check is added or removed | its row in `docs/repository-settings-service.md`, in the table format of `docs/repository-settings.md` and with the column that says whether the job is a required check | editing `docs/repository-settings.md`, which the sync overwrites; creating branch protection |
| An operational procedure of the service changes | a service-owned page; when none exists, create it with [documentation-creation](../documentation-creation/SKILL.md) | service content in a page the template ships |
| A rule for AI agents changes | `AGENTS.md` only (`CLAUDE.md` points to it) | the block between the verification markers; the plugin's managed governance block, which only /rs-sdlc-setup rewrites |

A removed or renamed name leaves citations behind; each one fails rule 1, 2, 3 or 5 on the next run, so they are found and fixed in the same commit.

## Task

For one change set, update every page the surface table names for each trigger in the change, remove every stale citation, and prove the result with the targets mapped by `make.docs_check` and `make.validate_invariants`. The calling stage commits; this skill never commits.

## Success criteria

- Every trigger in the change has its pages updated in the same change set; no stale citation of a removed or renamed name is left in a tracked Markdown file.
- A service-owned target is defined in `make/service.mk`, listed by `make help` and has its row in `docs/make-targets-service.md`; the template `Makefile` and `docs/make-targets.md` are unchanged.
- No service page lists three or more gate targets in one numbered list or fenced block, and the verification block of `AGENTS.md` is unchanged.
- The evidence line of each proof target is `passed`, or states `not run (<reason>)`; nothing is reported as passing without a run that exited 0.

## Steps

1. **Read the precedence files.** Read `.claude/skills/documentation-sync/SKILL.md` (when it exists) and `AGENTS.md`. Note every rule that differs from the surface table; the repository's rule wins.
2. **Resolve the profile.** Read `make.docs_check` and `make.validate_invariants` from `.claude/rust-sdlc.yml`; the calling command has validated the file. When the file is missing, print `SKIPPED: no profile — run /rs-sdlc-setup on the default branch and commit the result`, then the verdict line `documentation-sync: SUCCESS-WITH-REPORT`, and stop.
3. **Classify the change.** List the changed files against the merge base the calling stage computed (`git diff --name-only <merge-base>...HEAD`, plus the working tree) and map each one to the triggers of the surface table: `make/service.mk` (targets, `?=` variables), the CLI and configuration modules of the composition root (commands, flags, variables), `.env`, `.env.test` and the compose files (variables), the router, the OpenAPI and GraphQL modules and the contract snapshots (endpoints), `.github/workflows/` (jobs and checks), runbook-relevant code (procedures). A change set with no trigger ends here: print `SKIPPED: no documentation trigger in the change`, then `documentation-sync: SUCCESS`.
4. **Update the surfaces.** Apply each row of the surface table that a trigger selected. For a service-owned target, write the recipe and its help comment in `make/service.mk` and the row in `docs/make-targets-service.md`, as in this sourced example:

   ```text # profile-example
   make/service.mk (the recipe line starts with a tab in the real file):
     reconcile-ledger: ## Reconcile the <entity> ledger against the payment provider
         $(EXEC) <command>
   docs/make-targets-service.md:
     | `reconcile-ledger` | TOOL | database | no | Reconcile the <entity> ledger against the payment provider |
   ```

   Keep the column layout the table already has (the template's `docs/make-targets.md` uses target, class, needs, whether `make ci` runs it, and the help text); the drift check reads only the backticked first cell.
5. **Remove stale citations.** For every removed or renamed name (target, command, flag, variable, path, endpoint), search the tracked Markdown and fix each hit:

   ```bash
   git grep -n '<old name>' -- '*.md' docs/requests.http
   ```

6. **Prove it.** Run the two targets one after the other, each the way [verification-workflow](../verification-workflow/SKILL.md) runs a target outside its foreground allowlist: backgrounded, with its log under `target/rust-sdlc/logs/`, polled until it exits. The drift check compiles and runs the service binary four times, so it never runs in the foreground. Branch on each key:
   - **`make.docs_check` mapped:** run `make <make.docs_check>`. Exit 0 is `passed`; a non-zero exit prints lines `(<rule>) <file>:<line>: <message>` to fix. **Null:** record `not run (capability absent)` and grep each new or renamed citation by hand (`make help` for targets, `git ls-files` for paths) as the only evidence.
   - **`make.validate_invariants` mapped:** run `make <make.validate_invariants>`. Exit 0 is `passed`; a non-zero exit prints lines `(<letter>) <message>`. Fix the documentation for rules (d) and (e); a finding of another rule (a pin, a toolchain version, a suppression) is not a documentation finding: it is recorded, handed to the calling stage and not counted against this skill's loop. **Null:** record `not run (capability absent)`.
   - A log that contains `This target needs a reachable container engine (docker).` is `not run (no Docker)`, a missing toolchain is `not run (no toolchain)`; neither is ever `failed` or retried, and either one ends the skill `ESCALATED` at once (a mapped capability that cannot run, degrade rows D2 and D3) with the probe or the log line as `blocking_finding`.
7. **Loop, bounded.** After each round of fixes, run the failing target again and state the counter as `iteration <n>/5`. At most 5 rounds (`MAX_ITERATIONS=5`); a round that leaves the same finding must not repeat the same edit. Fix the page, never the check: a finding that only a protected file could clear stops the work with `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`.
8. **Escalate when the loop ends unmet.**

   ```text
   === SDLC ESCALATION ===
   stage: <the calling stage id>
   iteration: <n>/5
   exit_condition: <the calling stage's exit string, verbatim>
   status: NOT MET
   blocking_finding: (<rule>) <file>:<line>: <message> (make <target> exit <code>)
   iteration_log: <one line per round: "<n>: <target> -> <finding count>">
   recommended_action: update the page named above to match the code, or apply the protected change with approved-config-change and ALLOW_PROTECTED_CONFIG_EDIT=1
   === END ===
   ```

9. **Report.** Print the evidence and the verdict line:

   ```text
   | trigger | pages updated |
   | --- | --- |
   | <trigger from the surface table> | <page>, <page> |
   <target mapped by make.docs_check>: passed (<log path>) | failed (<n> findings) | not run (<reason>)
   <target mapped by make.validate_invariants>: passed (<log path>) | failed (<n> findings) | not run (<reason>)
   documentation-sync: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
   ```

   `SUCCESS`: both mapped targets passed, or the change had no trigger. `SUCCESS-WITH-REPORT`: a key is null, the only findings left belong to other invariant rules (handed to the calling stage), or the profile was missing. `ESCALATED`: a mapped target could not run (step 6), or the block of step 8 or a `BLOCKED:` line was printed.

## Constraints

- Never add a service target to the template `Makefile` or a row to `docs/make-targets.md`; both are overwritten by the next sync. Service targets live in `make/service.mk` and `docs/make-targets-service.md`.
- Never edit `scripts/check-docs.sh`, `scripts/check-invariants.sh` or any other path that `cargo xtask config-guard --list` prints to make a check pass.
- Never copy the verification list into another page, never put three or more gate targets in one numbered list or fenced block, and never edit between the verification markers of `AGENTS.md` or inside the plugin's managed governance block.
- Never write the template's repository name into a service page; the repository-name invariant rejects it.
- Never write under `.claude/skills/` of the service; the repository owns its skills and their index (rule 7).
- Never edit `.claude/rust-sdlc.yml` on a feature branch; a profile refresh is a separate /rs-sdlc-setup run on the default branch.
- Never report a check as passed without a run whose log shows exit 0.

## Verification

```bash
make <make.docs_check>
make <make.validate_invariants>
```

Both runs exit 0, `git grep` finds no citation of a removed or renamed name, and the output ends with the evidence and the verdict line of step 9. A null key shows as `not run (capability absent)` with the verdict `documentation-sync: SUCCESS-WITH-REPORT`.

The triage row the calling stage records for this skill (`repo+plugin` when the repository has its own `documentation-sync` skill, otherwise `plugin`):

```text
| documentation-sync | repo+plugin | EXECUTE | <the evidence lines of both targets> |
```
