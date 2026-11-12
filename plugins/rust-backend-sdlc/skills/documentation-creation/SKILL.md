---
name: documentation-creation
description: Use when a Rust service needs a documentation page that does not exist yet (a runbook, a guide to one adapter or bounded context, an integration reference) and the page must pass the service's docs-check, which means naming the service by `project.name`, citing only make targets, `service` commands, slash commands and paths that exist, and never listing gate targets outside the verification markers of AGENTS.md. Skip only the proof run, reported as not run, when `make.docs_check` is null. Not for updating pages that already exist after a code change (use documentation-sync), not for environment-variable rows of docs/environment.md (use configuration-management), and not for skills under .claude/skills/ (the plugin never writes there).
---

# Documentation Creation

## Profile keys consumed

- `project.name` — the service name the new page uses in its H1 and its prose (the checkout directory, which is also the Compose project name)
- `make.docs_check` — the documentation-drift target that proves the page; null means the proof is not run and is reported as `not run (capability absent)`

## Context

Use this skill when the calling stage needs a new page under `docs/` and no tracked page covers the topic yet. A page that already exists is updated with [documentation-sync](../documentation-sync/SKILL.md) instead.

The template's drift check, the target mapped by `make.docs_check`, reads every tracked Markdown file except `CHANGELOG.md` and the files below `specs/`. It treats only inline code spans and the lines of fenced blocks as citations; plain prose is never checked. Rules 1 to 4 decide whether a new page passes:

1. A cited `make <target>` must be a target of the Makefile.
2. A cited `service <command>` must be a command in the help of the service binary, and a code span that is exactly `/<name>` (or starts with `/<name>` and a space) must have a file `.claude/commands/<name>.md` or be a route, an API path or a mount point of the service.
3. A backticked token that starts with the name of a tracked top-level file or directory, or with `_bmad/`, `_bmad-output/`, `.ralph/` or `bmalph/state/`, must name a path that exists or that a git-ignore rule matches. The path is checked up to its first placeholder or wildcard character (`<`, `*`, `?`, `{`, `$`, `[`, `…` or `...`).
4. No numbered list and no fenced block outside the verification markers of `AGENTS.md` may cite three or more gate targets. The gate targets are the lines between those markers.

Rules 5 to 7 cover `docs/environment.md`, the two make-target references and the repository's own skill index. A new page does not touch them; [configuration-management](../configuration-management/SKILL.md) owns the variable rows and documentation-sync owns the target references.

Three more facts shape a new page:

- **Template sync.** The next template sync overwrites every file the template ships unless `.templatesyncignore` lists it. A new file the template does not ship survives every sync. Read `.templatesyncignore` at runtime; never assume its content.
- **Lints.** The service lints Markdown with markdownlint-cli2 under `.markdownlint-cli2.yaml` and spelling with typos under `_typos.toml`. Both files are protected configuration (the list comes from `cargo xtask config-guard --list`), so a finding is fixed in the page.
- **Names.** `project.name` is the only name of the service. The template's own repository name must not appear in a service page (the repository-name invariant rejects it), and neither must the names of the template's sample bounded context.

## Task

Write one new Markdown page under `docs/` for the topic the calling stage names, add one link to it from a service-owned entry page, and prove both with the target mapped by `make.docs_check`. Change no other line of any existing page.

## Success criteria

- The page is a new tracked file `docs/<kebab-topic>.md`, and before it was written no tracked page covered the topic.
- Its H1 and its first paragraph name the service by `project.name`; the template's repository name appears nowhere in it.
- Every make target, `service` command, slash-command span and backticked path in the page exists; a path that does not exist yet is written in plain prose or cut at a placeholder.
- No numbered list and no fenced block of the page cites three or more gate targets; the page links to the verification section of `AGENTS.md` instead.
- Every relative link of the page resolves, and the page is linked from an entry page that `.templatesyncignore` lists.
- The evidence line for the target mapped by `make.docs_check` is `passed`, or states `not run (<reason>)`; a page is never reported as passing without a run that exited 0.

## Steps

1. **Resolve the profile.** Read `project.name` and `make.docs_check` from `.claude/rust-sdlc.yml`; the calling command has validated the file. When the file is missing, print `SKIPPED: no profile — run /rs-sdlc-setup on the default branch and commit the result`, then the verdict line `documentation-creation: SUCCESS-WITH-REPORT`, and stop.
2. **Confirm the topic is new.** Search the tracked Markdown for the topic words:

   ```bash
   git grep -il '<topic words>' -- '*.md'
   ```

   When a tracked page already covers the topic, stop here and continue with documentation-sync on that page. Never create a parallel page.
3. **Choose the file.** Name it `docs/<kebab-topic>.md` and check that the template does not ship a file of that name (`git ls-files docs` lists what exists; a template file of the same name would be overwritten by the next sync). Never place it below `specs/` (the drift check skips that tree and planning bundles live there), below `.claude/skills/` or `scripts/` (the plugin never writes there), and never use it to replace `docs/environment.md`, `docs/make-targets.md` or `docs/make-targets-service.md`.
4. **Write the page.** Apply these rules while writing:
   - The H1 is `# <project.name> <topic>` and the first paragraph says what the page covers for that service. One H1, no duplicate heading text, a language on every fence, no inline HTML except comment markers, blank lines around lists, fences and tables.
   - Cite a make target only after `make help` lists it. When the topic maps to a profile key, cite the target the key maps to, never the key name; a null key means the capability is absent, so the page says so instead of citing a target.
   - Cite a `service <command>` only when the help of the service binary lists that command.
   - Name the plugin's commands (/rs-sdlc and its stage commands) in plain prose only. In a code span they would be read as slash commands without a file under `.claude/commands/` (rule 2).
   - Backtick only paths that exist now or that a git-ignore rule matches. Write a path that will exist later in plain prose, or backtick it with a placeholder right after the part that exists (`crates/<group>/<context>/` is checked only up to `crates/`).
   - Put at most two gate targets in one numbered list or fenced block. For the full order, write a relative link whose target is `../AGENTS.md#verification` (from a page in `docs/`).
   - State no quality threshold and copy no list the template defines (gate order, protected files, required checks); link to the page of the repository that holds it.
   - Write no secret, token, password or URL that embeds a credential, not even as an example.
5. **Link the page.** Add one link line to a service-owned entry page, normally the root `README.md`. Confirm with `.templatesyncignore` that the entry page is listed there; a template-synchronised index such as `docs/README.md` is overwritten by the next sync, so a link there is lost.
6. **Check statically.** These checks are fast and catch most findings before the proof run:

   ```bash
   grep -noE 'make +[a-z][a-z0-9_-]*' docs/<kebab-topic>.md
   make help
   git ls-files --error-unmatch <backticked path> || git check-ignore <backticked path>
   test -e docs/<relative link target>
   ```

   Every target of the first command must appear in the output of `make help`, every backticked path must pass the third line, and every relative link must pass the fourth.
7. **Prove it.** Branch on `make.docs_check`:
   - **Mapped:** run `make <make.docs_check>` the way [verification-workflow](../verification-workflow/SKILL.md) runs every target outside its foreground allowlist: backgrounded, with its log under `target/rust-sdlc/logs/`, polled until it exits. The target compiles and runs the service binary, so it never runs in the foreground. Exit 0 is `passed`. A non-zero exit prints lines `(<rule>) <file>:<line>: <message>`: fix the page or the link line for each line that names them, then run again. A log that contains `This target needs a reachable container engine (docker).` is `not run (no Docker)`, a missing toolchain is `not run (no toolchain)`; neither is ever `failed` or retried, and either one ends the skill `ESCALATED` at once (a mapped capability that cannot run, degrade rows D2 and D3) with the probe or the log line as `blocking_finding`.
   - **Null:** record `not run (capability absent)`. The static checks of step 6 are the only evidence and the outcome is `SUCCESS-WITH-REPORT`.
8. **Loop, bounded.** State the counter as `iteration <n>/5` before each run. At most 5 runs (`MAX_ITERATIONS=5`), and a run that leaves the same finding must not repeat the same edit. A finding about a file this skill did not write is recorded and handed to the calling stage, never fixed here: it belongs to documentation-sync or configuration-management. When every finding left names such a file, the loop ends: the evidence line reads `failed (<n> findings outside the page)`, the verdict is `SUCCESS-WITH-REPORT` and the calling stage's own gate run decides what happens next.
9. **Escalate when the loop ends unmet.**

   ```text
   === SDLC ESCALATION ===
   stage: <the calling stage id>
   iteration: <n>/5
   exit_condition: <the calling stage's exit string, verbatim>
   status: NOT MET
   blocking_finding: (<rule>) <file>:<line>: <message> (make <make.docs_check> exit 1)
   iteration_log: <one line per run: "<n>: drift check -> <finding count>">
   recommended_action: fix the citation named above in docs/<kebab-topic>.md, or move the finding to the skill that owns the file
   === END ===
   ```

10. **Report.** Print the evidence lines and the verdict line (step 7 decides the outcome):

    ```text
    page: docs/<kebab-topic>.md (H1 "<project.name> <topic>")
    linked from: <entry page>
    <target mapped by make.docs_check>: passed (<log path>) | failed (<n> findings) | not run (<reason>)
    documentation-creation: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
    ```

    `SUCCESS`: the drift check passed. `SUCCESS-WITH-REPORT`: the check is unmapped, every remaining finding is outside the page (step 8), or the profile was missing. `ESCALATED`: the mapped check could not run (step 7), or the block of step 9 or a `BLOCKED:` line was printed.

A sourced example, as it reads for a service whose profile maps every key to the target of the same name:

```text # profile-example
page: docs/reconciliation-runbook.md (H1 "billing-service reconciliation runbook")
linked from: README.md
docs-check: passed (target/rust-sdlc/logs/implement-20261112T101500Z.log)
documentation-creation: SUCCESS
```

## Constraints

- Never edit the drift check, `.markdownlint-cli2.yaml`, `_typos.toml` or any other path that `cargo xtask config-guard --list` prints to make a page pass. A needed change to one of them stops the work with `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`.
- Never copy the verification list of `AGENTS.md`, and never put three or more gate targets in one list or fenced block of a page.
- Never write the template's repository name or a name from the template's sample context into a page; `project.name` is the only service name. Examples in this skill use `<group>/<context>` and `<Entity>`.
- Never create a page below `.claude/skills/`, `scripts/` or `specs/`, and never create a second page for a topic that already has one.
- Never state a quality threshold in a page, and never put a secret in one.
- Never report the drift check as passed without a run whose log shows exit 0.

## Verification

```bash
make <make.docs_check>
```

The run exits 0 and the output ends with the evidence lines and the verdict line of step 10. When `make.docs_check` is null, the evidence line reads `not run (capability absent)`, the step 6 checks are clean and the verdict is `documentation-creation: SUCCESS-WITH-REPORT`.

The triage row the calling stage records for this skill:

```text
| documentation-creation | plugin | EXECUTE | <the evidence line of the drift check> |
```
