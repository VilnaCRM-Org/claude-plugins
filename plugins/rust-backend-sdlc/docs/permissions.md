# Permissions

This guide is the audit record of the plugin's permission model: which calls run without a prompt in a template-derived repository, which calls are refused, why each entry exists, and which entry covers each call a command makes. `/rs-sdlc-setup` writes the entries at its step 6 through `merge-settings.sh`; the [setup walkthrough](setup-walkthrough.md) shows that step in context.

## The decision (ADR-6)

ADR-6 is "Permissions: acceptEdits, local allowlist, no bypass":

- Every `claude -p` session the plugin starts runs with `--permission-mode acceptEdits`. The two scripts that start one, `fr-nfr-gate.sh` and `ai-review-loop.sh`, use the isolated restricted session described under "Sessions the plugin starts".
- `merge-settings.sh` merges the allow entries of the table below into `permissions.allow` and the plugin-owned deny entries into `permissions.deny` of `.claude/settings.local.json` (the default, `--file local`). Both merges are unions: an existing entry keeps its bytes and its position, a new entry is appended once, and nothing is ever removed or reordered.
- `.claude/settings.local.json` is the git-ignored local scope (the template's `.gitignore` lists it). It is per user and per machine, because it holds the absolute plugin root and the numeric uid and gid. When `git check-ignore` does not report it as ignored, `merge-settings.sh` refuses to write it (`REFUSED: .claude/settings.local.json is not git-ignored`) and setup prints the merged JSON instead.
- `.claude/settings.json` is protected in the template: `protected-config.toml` lists it. `merge-settings.sh --file shared` refuses that file while `protected-config.toml` lists it in `files` or below one of its `directories`, or exists and cannot be parsed, and prints the merged JSON after the `REFUSED:` line. Setup never passes `--file shared`.
- `merge-settings.sh` never writes `ask`, `hooks`, `env` or `defaultMode`, never writes a `curl` entry and never sets `bypassPermissions`. The template's own allow, ask and deny rules and its guard hooks stay exactly as they are.

The plugin's deny entries exist because the template's deny rules are prefix rules: without the plugin's own deny entries, the plugin's broad allow entries `Bash(git commit:*)`, `Bash(git push:*)`, `Bash(gh:*)` and `Bash(make:*)` would also approve hook-bypass, force, label and gate-faking forms. "Why the plugin adds deny entries" below gives the details and the residual gaps.

## How Claude Code applies the rules

The design relies on these properties of Claude Code's permission rules, as the plugin's architecture records them from the Claude Code permissions documentation:

- **deny > ask > allow.** Rules are evaluated deny first, then ask, then allow, and the first match wins. A deny entry refuses a call that an allow entry would approve, and a template ask rule (for example `Bash(make migrate-rollback:*)`) still prompts although the plugin's `Bash(make:*)` would allow the call.
- `Bash(x:*)` is the same rule as `Bash(x *)`: it needs a space, or the end of the command, right after `x`. A `*` without a space before it matches any text, including `..` path segments, a second URL or extra options. Every plugin allow entry is either an exact command or uses the space-required form; the only entries that end in a `*` without a space before it are deny entries, where matching too much fails closed.
- A compound command (`a; b`, `a | b`, `{ a; b; }`) is approved only when every subcommand is.
- An allow rule does not match past a leading assignment of a variable that is not on Claude Code's known-safe list, while deny and ask rules match past any assignment. This is why every plugin `make` call puts its variables after the target (`make docs-check RUN_IN_CONTAINER=1`), why entries 2–4 exist for the prefix spelling, and why the deny entries also refuse a forced push behind `RUN_IN_CONTAINER=1`, which the plugin never runs.
- Environment runners such as `docker compose exec` are not stripped, so their entries name the inner command (entries 31–35).
- `.claude/settings.local.json` is the local project scope; its allow rules apply without a trust step while the file is untracked.

The template's `.claude/settings.json` adds its own rules, which keep applying next to the plugin's (as of the template version the plugin was built against):

- **allow:** the gate targets one by one (`Bash(make docs-check:*)` and its siblings), `Bash(git status:*)`, `Bash(git diff:*)`, `Bash(git log:*)`, `Bash(git show:*)`, `Bash(cargo metadata:*)`, `Bash(cargo tree:*)`, `Bash(cargo xtask config-guard --list)`, `Bash(docker compose ps:*)` and `Bash(docker compose logs:*)`. Host `cargo tree`, `cargo metadata` and `cargo xtask config-guard --list` are therefore already allowed, and the plugin writes only their container routes.
- **ask:** `make aws-load-tests`, `make aws-load-tests-cleanup`, `make update`, `make purge`, `make clean`, `make down`, `make migrate-rollback`, `make build`, `make stop`, `make static-analysis-fix` and `make unused-dependencies-fix`.
- **deny:** seven prefix rules for git (a force push, a hook bypass on commit or push, and a hook-path override or write; the plugin never uses any of them) plus reading and editing `.env.local`.

## Allow entries

`merge-settings.sh` writes these 39 rows as 66 entries, in table order. `<root>` is the absolute plugin root (`resolve_plugin_root`: `CLAUDE_PLUGIN_ROOT` when set, made absolute, including the version directory of the plugin cache); `<uid>` and `<gid>` are the output of `id -u` and `id -g` when the merge runs, written as literal numbers.

| # | Entry | Covers |
| --- | --- | --- |
| 1 | `Bash(make:*)` | every `make <target> [VAR=value]` call with the ADR-13 closed variable set (template `ask` rules still prompt: ask before allow; deny entries M1–M10 refuse options and the gate-overriding variables; any other variable is kept out by the plugin's spelling, not by a rule) |
| 2 | `Bash(RUN_IN_CONTAINER=1 make:*)` | prefix spelling typed by users or template docs |
| 3 | `Bash(RUN_IN_CONTAINER=1 git commit:*)` | hooked commits in container mode (`-F <file>`) |
| 4 | `Bash(RUN_IN_CONTAINER=1 git push:*)` | hooked pushes in container mode (`-u origin HEAD`) |
| 5 | `Bash(git status:*)` | read |
| 6 | `Bash(git diff:*)` | read |
| 7 | `Bash(git log:*)` | read (post-loop subject check with a literal merge-base sha) |
| 8 | `Bash(git add:*)` | staging |
| 9 | `Bash(git commit:*)` | commits as `git commit -F <file>`; deny entries G1–G3 refuse bypass forms in any position |
| 10 | `Bash(git push:*)` | pushes as `git push -u origin HEAD`; deny entries G4–G9 refuse force, mirror, delete and `+refspec` forms |
| 11 | `Bash(git switch:*)` | branch creation |
| 12 | `Bash(git fetch:*)` | `git fetch origin <default_branch>` (D24) |
| 13 | `Bash(git rev-parse:*)` | read (D24 probe, `HEAD`) |
| 14 | `Bash(git merge-base:*)` | read (implement post-loop, review and finish-pr guards) |
| 15 | `Bash(git config --get core.hooksPath)` and `Bash(git config --local --get core.hooksPath)` (two entries) | read-only hook probes typed by users; the plugin itself uses `common.sh hooks_active` |
| 16 | `Bash(git ls-files:*)` | read |
| 17 | `Bash(git remote get-url:*)` | read |
| 18 | `Bash(git check-ignore:*)` | read |
| 19 | `Bash(git branch --show-current)` | read |
| 20 | `Bash(gh:*)` | issues, PRs, comments, statuses, runs; paired with deny entries H1–H8 |
| 21 | `Bash(bmalph implement)` | exact; `--force` can never match |
| 22 | `Bash(bmalph run --driver claude-code --no-dashboard)` | exact |
| 23 | `Bash(bmalph doctor:*)` | health check |
| 24 | `Bash(bmalph --version)` | floor check |
| 25 | `Bash(<root>/scripts/<name>.sh:*)`, one entry per executable (13 entries: `setup-preflight`, `generate-profile`, `validate-profile`, `inject-governance`, `merge-settings`, `new-service`, `stage-planning-artifacts`, `ai-review-loop`, `fr-nfr-gate`, `get-pr-comments`, `post-review-findings`, `pr-state`, `request-ai-reviews`) | every plugin script; a space is required after the name, so no `..` path can match |
| 26 | `Bash(<root>/scripts/lib/common.sh:*)` | the library dispatcher (ADR-15) |
| 27 | `Bash("<root>/scripts/<name>.sh":*)` and `Bash("<root>/scripts/lib/common.sh":*)` (14 entries) | the same when the path is written quoted |
| 28 | `Bash(docker info:*)` | Docker probe |
| 29 | `Bash(docker compose ps:*)` | container precondition (template already allows it) |
| 30 | `Bash(docker compose logs:*)` | bounded log read (template already allows it) |
| 31 | `Bash(docker compose exec -T --user <uid>:<gid> app cargo tree:*)` | FR-1 raw call (1), container route |
| 32 | `Bash(docker compose exec -T --user <uid>:<gid> app cargo metadata:*)` | FR-1 raw call (1), container route |
| 33 | `Bash(docker compose exec -T --user <uid>:<gid> app cargo xtask config-guard --list)` | FR-1 raw call (2), exact |
| 34 | `Bash(docker compose exec -T --user <uid>:<gid> app env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)` | FR-1 raw call (3), container route |
| 35 | `Bash(docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh:*)` | FR-1 raw call (4), container route |
| 36 | `Bash(env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)` | FR-1 raw call (3), host |
| 37 | `Bash(scripts/set-version.sh:*)` | FR-1 raw call (4), host |
| 38 | `Bash(mkdir -p target/rust-sdlc/logs)` | exact; the log directory of the background wrapper (state, ledger, tmp and archive directories are created by `common.sh`) |
| 39 | `Bash(id -u)` and `Bash(id -g)` (two entries) | uid/gid resolution for the container route |

The 13 executables of row 25 are a fixed list, written in that order, never read from a directory and never checked for existence; row 27 repeats them quoted, followed by the library. No entry is `Bash(bmalph:*)`, no entry ends in `/*)` after the plugin root, and no entry names `curl`.

The 66 entries exactly as `merge-settings.sh` writes them, in order:

```text
Bash(make:*)
Bash(RUN_IN_CONTAINER=1 make:*)
Bash(RUN_IN_CONTAINER=1 git commit:*)
Bash(RUN_IN_CONTAINER=1 git push:*)
Bash(git status:*)
Bash(git diff:*)
Bash(git log:*)
Bash(git add:*)
Bash(git commit:*)
Bash(git push:*)
Bash(git switch:*)
Bash(git fetch:*)
Bash(git rev-parse:*)
Bash(git merge-base:*)
Bash(git config --get core.hooksPath)
Bash(git config --local --get core.hooksPath)
Bash(git ls-files:*)
Bash(git remote get-url:*)
Bash(git check-ignore:*)
Bash(git branch --show-current)
Bash(gh:*)
Bash(bmalph implement)
Bash(bmalph run --driver claude-code --no-dashboard)
Bash(bmalph doctor:*)
Bash(bmalph --version)
Bash(<root>/scripts/setup-preflight.sh:*)
Bash(<root>/scripts/generate-profile.sh:*)
Bash(<root>/scripts/validate-profile.sh:*)
Bash(<root>/scripts/inject-governance.sh:*)
Bash(<root>/scripts/merge-settings.sh:*)
Bash(<root>/scripts/new-service.sh:*)
Bash(<root>/scripts/stage-planning-artifacts.sh:*)
Bash(<root>/scripts/ai-review-loop.sh:*)
Bash(<root>/scripts/fr-nfr-gate.sh:*)
Bash(<root>/scripts/get-pr-comments.sh:*)
Bash(<root>/scripts/post-review-findings.sh:*)
Bash(<root>/scripts/pr-state.sh:*)
Bash(<root>/scripts/request-ai-reviews.sh:*)
Bash(<root>/scripts/lib/common.sh:*)
Bash("<root>/scripts/setup-preflight.sh":*)
Bash("<root>/scripts/generate-profile.sh":*)
Bash("<root>/scripts/validate-profile.sh":*)
Bash("<root>/scripts/inject-governance.sh":*)
Bash("<root>/scripts/merge-settings.sh":*)
Bash("<root>/scripts/new-service.sh":*)
Bash("<root>/scripts/stage-planning-artifacts.sh":*)
Bash("<root>/scripts/ai-review-loop.sh":*)
Bash("<root>/scripts/fr-nfr-gate.sh":*)
Bash("<root>/scripts/get-pr-comments.sh":*)
Bash("<root>/scripts/post-review-findings.sh":*)
Bash("<root>/scripts/pr-state.sh":*)
Bash("<root>/scripts/request-ai-reviews.sh":*)
Bash("<root>/scripts/lib/common.sh":*)
Bash(docker info:*)
Bash(docker compose ps:*)
Bash(docker compose logs:*)
Bash(docker compose exec -T --user <uid>:<gid> app cargo tree:*)
Bash(docker compose exec -T --user <uid>:<gid> app cargo metadata:*)
Bash(docker compose exec -T --user <uid>:<gid> app cargo xtask config-guard --list)
Bash(docker compose exec -T --user <uid>:<gid> app env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)
Bash(docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh:*)
Bash(env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)
Bash(scripts/set-version.sh:*)
Bash(mkdir -p target/rust-sdlc/logs)
Bash(id -u)
Bash(id -g)
```

## Deny entries

`merge-settings.sh` appends these 29 plugin-owned entries to `permissions.deny`, in this order. Deny rules match past a leading assignment, so each one also refuses its form behind `RUN_IN_CONTAINER=1`. Each entry refuses the spelling its pattern names; other spellings of the same action are a residual gap, described below. Existing deny entries, the template's included, are kept byte for byte.

### Git (G1–G9)

| # | Entry | Refuses |
| --- | --- | --- |
| G1 | `Bash(git commit *--no-verify*)` | hook bypass in any position |
| G2 | `Bash(git commit * -n *)` | short hook bypass after other options |
| G3 | `Bash(git commit * -n)` | short hook bypass as the last option |
| G4 | `Bash(git push *--force*)` | `--force`, `--force-with-lease`, `--force-if-includes` |
| G5 | `Bash(git push * -f*)` | short force in any later position |
| G6 | `Bash(git push *--no-verify*)` | hook bypass |
| G7 | `Bash(git push *--mirror*)` | mirror push |
| G8 | `Bash(git push *--delete*)` | remote branch deletion with `--delete` |
| G9 | `Bash(git push * +*)` | `+refspec` forced update |

### GitHub CLI (H1–H8)

| # | Entry | Refuses |
| --- | --- | --- |
| H1 | `Bash(gh *approved-config-change*)` | applying or removing the protected-config approval label |
| H2 | `Bash(gh *approved-breaking-change*)` | applying or removing the breaking-change approval label |
| H3 | `Bash(gh pr merge:*)` | merging with `gh pr merge` |
| H4 | `Bash(gh secret:*)` | secrets |
| H5 | `Bash(gh variable:*)` | variables |
| H6 | `Bash(gh repo delete:*)` | repository deletion |
| H7 | `Bash(gh repo edit:*)` | repository settings |
| H8 | `Bash(gh api *protection*)` | branch protection |

### bmalph (B1–B2)

P5 is the NFR-5 forbidden pattern for a forced `bmalph implement`, which the plugin never runs.

| # | Entry | Refuses |
| --- | --- | --- |
| B1 | `Bash(bmalph reset:*)` | deleting bmalph state, the breaker included |
| B2 | `Bash(bmalph implement *--force*)` | P5 |

### make (M1–M10)

| # | Entry | Refuses |
| --- | --- | --- |
| M1 | `Bash(make -*)` | any option before the target |
| M2 | `Bash(make *_CMD=*)` | gate command overrides (`COVERAGE_GATE_CMD=true`) |
| M3 | `Bash(make *_FLAGS=*)` | flag overrides (`SPECTRAL_FLAGS=`, `TRIVY_FLAGS=`) |
| M4 | `Bash(make *_ARGS=*)` | argument overrides |
| M5 | `Bash(make *CI_STAGES=*)` | stage-list overrides |
| M6 | `Bash(make *CONFIG_CHANGE_APPROVED=true*)` | self-approval of protected changes |
| M7 | `Bash(make * -i*)` | ignore errors |
| M8 | `Bash(make * -k*)` | keep going |
| M9 | `Bash(make * -n*)` | dry run |
| M10 | `Bash(make * -*)` | any other option after the target, short or long (`-f`, `-C`, `-t`, `-q`, `--eval`, `--file`) |

The 29 entries exactly as `merge-settings.sh` writes them, in order:

```text
Bash(git commit *--no-verify*)
Bash(git commit * -n *)
Bash(git commit * -n)
Bash(git push *--force*)
Bash(git push * -f*)
Bash(git push *--no-verify*)
Bash(git push *--mirror*)
Bash(git push *--delete*)
Bash(git push * +*)
Bash(gh *approved-config-change*)
Bash(gh *approved-breaking-change*)
Bash(gh pr merge:*)
Bash(gh secret:*)
Bash(gh variable:*)
Bash(gh repo delete:*)
Bash(gh repo edit:*)
Bash(gh api *protection*)
Bash(bmalph reset:*)
Bash(bmalph implement *--force*)
Bash(make -*)
Bash(make *_CMD=*)
Bash(make *_FLAGS=*)
Bash(make *_ARGS=*)
Bash(make *CI_STAGES=*)
Bash(make *CONFIG_CHANGE_APPROVED=true*)
Bash(make * -i*)
Bash(make * -k*)
Bash(make * -n*)
Bash(make * -*)
```

## Why the plugin adds deny entries

The template's git deny rules are prefix rules such as `Bash(git commit --no-verify:*)` and `Bash(git push --force:*)`. A prefix rule matches only when the forbidden option comes first, so it misses `git commit -m x --no-verify`, `git push --force-with-lease`, `git push origin HEAD --force` and `git push origin +HEAD:main` (checked against the template's `.claude/settings.json`). The plugin itself needs the broad allow entries `Bash(git commit:*)`, `Bash(git push:*)`, `Bash(gh:*)` and `Bash(make:*)`, and those would approve exactly the forms the prefix rules miss:

- **G1–G9** refuse a hook bypass or a force, mirror, `--delete` or `+refspec` push wherever the option stands, so the two entries 9 and 10 cannot approve them. The template's prefix rules still catch the forms where the option comes first.
- **H1–H8** keep `Bash(gh:*)` away from the two approval labels (any `gh` call that names one, whatever it does with it), from the subcommands `gh pr merge`, `gh secret`, `gh variable`, `gh repo delete` and `gh repo edit`, and from any `gh api` path that names `protection`. The plugin reads labels with `gh pr view --json labels` and looks for the label in the output; it never names an approval label in a `gh` call and never applies or removes one.
- **B1–B2** keep bmalph state and the Ralph circuit breaker out of reach: entry 21 is exact, so `bmalph implement --force` never matches an allow entry, and B2 refuses it in any spelling; `bmalph reset` is refused outright.
- **M1–M10** keep `Bash(make:*)` from faking a gate. GNU make command-line variables override every assignment of the template's gate makefile, so `make tests-with-coverage COVERAGE_GATE_CMD=true` or `make validate-configuration CONFIG_CHANGE_APPROVED=true` would pass a gate without running it, and an option after the target (`-i`, `-k`, `-n`, `-t`, `-q`, `-f`, `-C` or a long option) would ignore, skip, fake or redirect it. The plugin passes only the closed variable set `RUN_IN_CONTAINER COMMIT_TITLE base_ref BREAKING_CHANGE_APPROVED CONFIG_CHANGE_APPROVED group context name SCHEMATHESIS_URL`, `CONFIG_CHANGE_APPROVED` only with an empty value, and no option. A variable that M2–M6 do not name is the second residual gap below.

The plugin's own calls never match a deny entry: commits carry no message text (`git commit -F <file>`, the file written by `common.sh commit_msg_file`), pushes are always `git push -u origin HEAD`, label reads use `gh pr view --json labels`, and a commit subject that contains a space followed by a hyphen is pre-validated with `common.sh is_commit_subject` instead of `make check-commit-message COMMIT_TITLE='…'`, because M10 refuses that make call (a subject such as `fix(#7): support the -k option` matches M8 and M10).

### The residual gap: combined short options

Claude Code patterns have no character classes, so a short option folded into a group of short options matches no deny rule: `git commit -nm x` is a hook bypass that neither G2, G3 nor the template's `Bash(git commit -n:*)` matches, and `git push -uf origin HEAD` is a force push that neither G5 nor the template's `Bash(git push -f:*)` matches. The gap is closed by the plugin's own spelling, not by a rule: the plugin never types combined short options. Every commit it makes is `git commit -F <path>` after `commit_msg_file`, every push is `git push -u origin HEAD` (CC-14 pins both spellings in every command, agent and workflow), and CC-15 checks the forbidden-pattern set P1–P7 over the commands, agents, skills, workflows and scripts. A person typing in the session is not held by those checks, and the deny entries are a backstop for the plugin's broad allow entries, not a sandbox.

### The residual gap: other make variables

Claude Code patterns cannot say "every variable except these", so M2–M6 refuse only the names that override a gate of the template's `make/gates.mk`: every `*_CMD`, `*_FLAGS` and `*_ARGS` variable, `CI_STAGES` and `CONFIG_CHANGE_APPROVED=true`. Any other command-line variable matches no deny entry and still overrides its assignment in the template's `Makefile`: `make tests-with-coverage SHELL=true` runs no recipe line and exits 0, and `make ci-tests CI_TESTS_TARGETS=` runs no test target. The closed variable set is held by the plugin's own spelling, not by a rule: CC-36 rejects a make call in the commands, agents, skills and workflows that passes an option, a variable outside the set or `CONFIG_CHANGE_APPROVED` with a value. As with combined short options, a person typing in the session is not held by that check.

### The residual gap: other spellings of a refused action

G8 and H3–H7 each match one spelling of their action. A remote branch is also deleted by `git push -d origin <branch>` or `git push origin :<branch>`, which match entry 10 and no deny entry. H3–H7 match only when the subcommand follows `gh` directly, so a global option in front of it (`gh -R <owner>/<repo> pr merge <n>`, `gh --repo <owner>/<repo> secret set <name>`) passes them, and `gh api` reaches the same actions through REST paths (`gh api -X PUT repos/{owner}/{repo}/pulls/<n>/merge`, `repos/{owner}/{repo}/actions/secrets/<name>`, `repos/{owner}/{repo}/actions/variables`, `gh api -X DELETE repos/{owner}/{repo}`) that only H8 checks, and only for `protection`. A pattern broad enough for every spelling would also refuse the plugin's own `gh api` calls, which read the user, repositories, issues and review threads and write issue comments, thread replies and thread resolutions. These forms are held by the plugin's own spelling, not by a rule: every push is `git push -u origin HEAD` (CC-14), and no command, agent, skill or workflow merges a pull request, deletes a remote branch or a repository, or changes secrets, variables or repository settings. As with the other gaps, a person typing in the session is not held by that spelling.

## HTTP goes through `common.sh http_probe` only

`merge-settings.sh` writes no `curl` entry, with or without `--with-qa-network`. A `curl` pattern needs a trailing `*` without a space before it to cover a URL, and such a pattern also approves a second URL, `--resolve`, `-x`, `-o`, `-K` or `--data-binary @<secret file>`; an allow entry of that shape is no network boundary, so none is written.

Every HTTP request of the plugin goes through `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" http_probe <METHOD> <PATH> …`, covered by entry 26 or 27. The function accepts only `GET`, `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE` and `OPTIONS`, a path matching `^/[A-Za-z0-9._~%/?&=:,+-]*$`, at most 10 headers and a body of at most 16 KiB (a body file only from `target/rust-sdlc/tmp/`). It builds the URL from the profile's validated `service.base_url` plus that path, runs `curl --noproxy '*' --proto =http --max-time 10` with no caller-supplied curl option, and prints `HTTP_STATUS: <code>`, the response headers and at most 64 KiB of body. The QA stage, `qa-manual-tester` and `security-auditor` use nothing else; a reproduction `curl` line in a QA report is written as text and never run.

`--with-qa-network` is accepted by `merge-settings.sh` and `/rs-sdlc-setup` for compatibility only: it writes nothing extra and prints one INFO line as the first stdout line:

```text
INFO: QA probes run through common.sh http_probe; no curl entry is written
```

## Sessions the plugin starts

### Headless `claude -p` sessions use `acceptEdits`

`common.sh` holds the plugin's only `claude -p` calls, `claude_run_once` and `claude_run_isolated`. Both run `claude -p <prompt> --output-format json --permission-mode acceptEdits --max-turns 30`: file edits inside the session are accepted, and a Bash call still needs a matching allow rule. `fr-nfr-gate.sh` and `ai-review-loop.sh` both use the isolated form, `claude_run_isolated`, because the session reads contributor-controlled text (the pull-request body, issues, the diff):

- the argv adds `--restricted --tools 'Read,Grep,Glob' --strict-mcp-config --disallowedTools 'Bash(gh:*)' 'Bash(git push:*)' 'Bash(git credential:*)'`, so the session has no shell, no edits and no MCP server;
- the environment drops `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `SSH_AUTH_SOCK`, `GIT_ASKPASS` and `SSH_ASKPASS`, points `GH_CONFIG_DIR` at an empty temporary directory (removed on every exit path), and gives git no system, global or credential-helper configuration;
- the script publishes the commit status and the comment itself, with its own credential, after the session has returned.

### Ralph's sessions run with `bypassPermissions`

The implement stage runs `bmalph run --driver claude-code --no-dashboard`, and Ralph starts its own Claude Code sessions with the settings of `.ralph/.ralphrc`. bmalph writes that file with `CLAUDE_PERMISSION_MODE="bypassPermissions"` as its default (bmalph 2.11.0, the plugin's floor), next to `PERMISSION_DENIAL_MODE="continue"` and `CB_AUTO_RESET=false`. That is bmalph's default, not the plugin's choice, and it is stated here as it is:

- The plugin never changes it: no plugin command, agent, script or workflow edits `.ralph/.ralphrc`, and none sets `bypassPermissions` anywhere. The plugin's own writes under `.ralph/` are the fix-plan and `@AGENT.md` helpers of `common.sh` (`ralph_fix_plan_prepare`, `ralph_fix_plan_restore`, `ralph_agent_md_patch`); `ralph_breaker_state` only reads.
- Inside Ralph's sessions Claude Code does not prompt, so the plugin's allow and ask entries do not gate what those sessions run, and the plugin does not rely on its deny entries there either. To hold Ralph's sessions to the allowlist instead, set another `CLAUDE_PERMISSION_MODE` in your own `.ralph/.ralphrc` (the file lists the modes bmalph accepts); that is your decision, and the plugin never touches the value you set.
- The backstop is ADR-25, which does not depend on the permission mode. The template's guard hook matches only `Edit`, `Write`, `MultiEdit` and `NotebookEdit`, so a write through Bash is not guarded. Before every commit a command makes, it runs `common.sh protected_changes <merge-base-sha>`, which compares the branch and the working tree with `protected-config.toml` and the profile; the implement stage's post-loop and every review iteration also run `make validate-configuration base_ref=<merge-base-sha> CONFIG_CHANGE_APPROVED=`. A protected file changed by any session ends the stage `ESCALATED` (D23) with `git restore --source=<merge-base> -- <path>` as the first remedy, and a profile changed on the branch ends review and finish-pr `ESCALATED`.

### The template's guard hooks keep firing

The template's `PreToolUse` and `PostToolUse` hooks on `Edit|Write|MultiEdit|NotebookEdit` run `scripts/claude/guard-protected-files.sh` in every Claude Code session started in the checkout that has an edit tool: the commands, their agents and Ralph's sessions (the isolated gate session has no edit tool at all). The plugin adds no hook and removes none. A guard-hook denial is quoted verbatim in the report and never retried through Bash; an intended change to a protected file needs the `approved-config-change` label, applied by a maintainer, and a session restarted with `ALLOW_PROTECTED_CONFIG_EDIT=1`.

### `ask` rules in headless runs

An `ask` rule cannot be answered in a headless run (`claude -p`, a workflow, a scheduled session): the call comes back as a permission denial. The plugin records the target as `<target>: not run (ask rule)`, never retries it under another spelling and goes on; the outcome is at best `SUCCESS-WITH-REPORT` (D13 in `docs/degrade-matrix.md`). The case the plugin meets by design is the rollback round trip, `make migrate-rollback`, which is a template ask rule: in the C8 item of /rs-sdlc-new-context, C8 stays done on `make validate-sqlx-metadata`; in a `rust-implementer` story that adds a migration pair, the rollback and its re-apply are recorded `not run (ask rule)` and the story still completes. In an interactive session the prompt appears and a person answers it.

## Calls per command

Every non-make command each command issues, with the entry that covers it. How to read the tables:

- Numbers are rows of the allow table above; G, H, B and M ids are deny rows.
- Plugin scripts are written `"${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" …` in the commands; the tables shorten them to `<name>.sh …`. They are matched against the absolute plugin root: row 27 covers the quoted path the commands use, row 25 the same path unquoted.
- Library calls are written `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" <function> …`; the tables shorten them to `common.sh <function> …`. Row 27 (row 26 unquoted) covers them, and the dispatcher runs only the named function, one of the 17 ADR-15 names; any other first argument exits 64.
- Programs a plugin script starts itself (`gh`, `git`, `python3`, `curl` inside `http_probe`, `claude` inside the gate) are not separate Bash tool calls, so Claude Code checks only the script's own entry.
- **Wrapper** means the background form `{ <command>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/<stage>-<UTC>.log 2>&1` run with `run_in_background: true`; the entry of `<command>` covers it, and `echo` only prints the exit code. Whether Claude Code approves the brace group through that entry is unverified (risk R1 of the architecture): when the runtime prompts for it, the commands issue the same call as `<command> > <log> 2>&1` and take the exit status from the background-task completion notice.
- **No entry** marks a read-only call no plugin entry covers. Claude Code runs it without a prompt only when it treats the call as read-only itself; otherwise it asks, and a headless run gets a denial. Where the command names a fallback, the table says so.
- `make` calls are covered by row 1 (row 2 for the prefix spelling) and limited by M1–M10; they are not repeated per command. Agents are listed after the ten commands.

### /rs-sdlc

The orchestrator runs each stage's procedure itself, in the same session, so every call of `rs-sdlc-issue`, `rs-sdlc-plan`, `rs-sdlc-implement`, `rs-sdlc-review`, `rs-sdlc-qa` and `rs-sdlc-finish-pr` listed below is also a call of /rs-sdlc. Its own calls:

| Call | Covered by |
| --- | --- |
| `validate-profile.sh` (stage 0) | 27 |
| `grep -q '<!-- rust-backend-sdlc:begin -->' CLAUDE.md`, the same for `AGENTS.md` | no entry; when refused, the Grep tool answers the same question and a refused call is never read as a failed check |
| `test -d _bmad` | no entry; when refused, the Glob tool (`_bmad/*`) answers |
| `git status --porcelain --untracked-files=no` | 5 |
| `git branch --show-current` | 19 |
| `common.sh derive_issue_number --branch <branch>` | 27 → `derive_issue_number` |
| `gh api user --jq .login` | 20 |
| `gh api repos/{owner}/{repo}/issues/<N>/comments --paginate --jq …` | 20 |
| `gh api repos/{owner}/{repo}/issues/<N>/comments --paginate \| common.sh resume_point --comments <login>` | 20 for `gh`, 27 → `resume_point` for the library; both parts are covered |
| `common.sh resume_point --cache target/rust-sdlc/state/<N>-<slug>.json` | 27 → `resume_point` |
| `gh issue view <N> --json number,url,title,labels,state` | 20 |
| `git fetch origin <default_branch>` | 12 |
| `git rev-parse --symbolic --branches='*/<N>-*'`, `git rev-parse --symbolic --remotes='origin/*/<N>-*'` | 13 |
| `git switch <type>/<N>-<slug>`, `git switch -c <type>/<N>-<slug> origin/<default_branch>` | 11 |
| `common.sh hooks_active` | 27 → `hooks_active` |
| `common.sh redact --in target/rust-sdlc/tmp/qa-fix-story.raw.md --out target/rust-sdlc/tmp/qa-fix-story.md` | 27 → `redact` |
| `git rev-parse --verify <ci.base_ref>`, `git rev-parse HEAD` | 13 |
| `git merge-base <ci.base_ref> HEAD` | 14 |
| `common.sh protected_changes <merge-base-sha>` | 27 → `protected_changes` |
| `git add -- <SPECS_DIR>/epics.md` | 8 |
| `git diff --cached --name-only` | 6 |
| `common.sh is_commit_subject '<subject>'`, `common.sh commit_msg_file '<subject>'` | 27 → `is_commit_subject`, `commit_msg_file` |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `git commit -F <path>` (container mode: `RUN_IN_CONTAINER=1 git commit -F <path>`) | 9 (3); G1–G3 refuse bypass forms |
| `common.sh wait_log <log>` | 27 → `wait_log` |
| `git log -1 --format=%s` | 7 |
| `docker info`, `docker compose ps --status running --quiet app` (container mode) | 28, 29 |
| `common.sh state_cache_update …`, `common.sh state_comment_body …` | 27 → `state_cache_update`, `state_comment_body` |
| `common.sh redact --in target/rust-sdlc/tmp/state.raw.md --out target/rust-sdlc/tmp/state.md` | 27 → `redact` |
| `gh api repos/{owner}/{repo}/issues/comments/<id> --jq .updated_at`, the same with `--jq .body` | 20 |
| `gh api -X PATCH repos/{owner}/{repo}/issues/comments/<id> -F body=@target/rust-sdlc/tmp/state.md` | 20 |
| `gh api repos/{owner}/{repo}/issues/<N>/comments -F body=@target/rust-sdlc/tmp/state.md` | 20 |

It never runs setup, `generate-profile.sh`, `inject-governance.sh` or `merge-settings.sh`, and never pushes outside the finish-pr procedure.

### /rs-sdlc-setup

| Call | Covered by |
| --- | --- |
| `setup-preflight.sh --report` | 27 (the script's own `bmalph doctor`, `gh auth status`, `docker info` and version probes run inside it) |
| `generate-profile.sh --stdout`; `generate-profile.sh [--refresh] [--run-in-container true\|false]` | 27 |
| `git status --porcelain --untracked-files=no` | 5 |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `make bmalph-setup`, `make docs-check`, `make start` | 1 for the make call |
| `common.sh wait_log <log>` | 27 → `wait_log` |
| `bmalph --version` | 24 |
| `validate-profile.sh` | 27 |
| `inject-governance.sh` | 27 |
| `merge-settings.sh [--with-qa-network] [--print]` | 27 |
| `common.sh hooks_active` | 27 → `hooks_active` |
| `command -v cargo` | no entry (a shell built-in lookup) |
| `docker info`, `docker compose ps --status running --quiet app` | 28, 29 |
| `git status --porcelain -- .claude/rust-sdlc.yml CLAUDE.md AGENTS.md` | 5 |
| `git branch --show-current` | 19 |

On the first run the allowlist does not exist before step 6, so the calls of steps 1–5 are covered only by the template's rules and your own settings, and Claude Code asks for the rest: run the first setup interactively. It never writes `.claude/settings.json` and never writes the hook setting itself (`make install-hooks` does).

### /rs-sdlc-new-service

The command runs before any profile or allowlist exists, and the allowlist that its step S12 writes belongs to the new checkout's `.claude/settings.local.json`: run it interactively, or allow the calls below in your user settings first.

| Call | Covered by |
| --- | --- |
| `docker info` (step 0 probe) | 28 |
| `command -v cargo` (step 0 probe) | no entry (a shell built-in lookup) |
| `new-service.sh --name '<name>' --dry-run …`, `new-service.sh --phase source …`, `new-service.sh --phase customize …` | 27; the script's own `gh api`, `gh repo create`, `gh repo clone` and `git archive` calls run inside it |
| `gh issue view <N> --json number,state,labels`, `gh issue edit <N> --add-label rust-backend-sdlc` | 20 |
| `gh label list --search rust-backend-sdlc --json name --jq '.[].name'`, `gh label create rust-backend-sdlc …` | 20 |
| `gh api --paginate 'repos/{owner}/{repo}/issues?labels=rust-backend-sdlc&state=open&sort=created&direction=desc&per_page=100' --jq …` | 20 |
| `common.sh redact --in … --out target/rust-sdlc/tmp/new-service-issue.md`, the same for `new-service-pr.md` | 27 → `redact` |
| `gh issue create --title 'Initialize <name> from the Rust service template' --body-file … --label rust-backend-sdlc` | 20 |
| `git log -1 --format=%s main`, `git log -1 --format=%s`, `git log --format=%s <base>..HEAD` | 7 |
| `git rev-parse --verify -q origin/main`, `git rev-parse HEAD` | 13 |
| `git switch main`, `git switch -c chore/<N>-initialize-service`, `git switch chore/<N>-initialize-service` | 11 |
| `git add -A` (S3, S11), `git add -- <files>`, `git add -- .claude/rust-sdlc.yml CLAUDE.md AGENTS.md` | 8 |
| `git branch --show-current` | 19 |
| `git merge-base <default> HEAD` | 14 |
| `common.sh is_commit_subject '<subject>'`, `common.sh commit_msg_file '<subject>'` | 27 → `is_commit_subject`, `commit_msg_file` |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `make bootstrap`, `make generate-openapi-spec`, `make format`, `make start` | 1 for the make call |
| wrapper around `git commit -F <path>` (container mode: `RUN_IN_CONTAINER=1 git commit -F <path>`) | 9 (3); G1–G3 |
| wrapper around `git push -u origin HEAD` (container mode: `RUN_IN_CONTAINER=1 git push -u origin HEAD`) | 10 (4); G4–G9 |
| `common.sh wait_log <log>` | 27 → `wait_log` |
| `id -u`, `id -g` | 39 |
| wrapper around `scripts/set-version.sh <v>` (host) | 37 |
| wrapper around `docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh <v>` (container) | 35 |
| `docker compose ps --status running --quiet app` | 29 |
| `git status --porcelain -- .github/openapi-spec/`, `git status --porcelain --untracked-files=no` | 5 |
| `common.sh hooks_active` | 27 → `hooks_active` |
| `git diff --cached --name-only`, `git diff --name-only` | 6 |
| `common.sh protected_changes <base>` | 27 → `protected_changes` |
| `gh pr list --head chore/<N>-initialize-service --state open --json number,url --limit 20` | 20 |
| `gh pr create --base <project.default_branch> --head chore/<N>-initialize-service --title … --body-file …` | 20 |

S12 runs the /rs-sdlc-setup procedure (its calls are listed above) and S14 hands the pull request to the /rs-sdlc-finish-pr procedure (listed below).

### /rs-sdlc-new-context

| Call | Covered by |
| --- | --- |
| `validate-profile.sh` | 27 |
| `common.sh validate_context_name '<group>' '<context>'` | 27 → `validate_context_name` |
| `git status --porcelain --untracked-files=no`, `git status --porcelain` | 5 |
| `command -v cargo` | no entry (a shell built-in lookup) |
| `docker info`, `docker compose ps --status running --quiet app` | 28, 29 |
| `git branch --show-current` | 19 |
| `common.sh derive_issue_number --branch <branch>` | 27 → `derive_issue_number` |
| `gh issue view <N> --json number,state --jq .state` | 20 |
| `git fetch origin <default_branch>` | 12 |
| `git switch -c feat/<N>-<context> origin/<default_branch>` | 11 |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `make new-context group=<group> context=<context>`, the gate-set stages and `make validate-configuration base_ref=<base> CONFIG_CHANGE_APPROVED=` | 1 for the make call |
| `common.sh wait_log <log>` | 27 → `wait_log` |
| `common.sh hooks_active` | 27 → `hooks_active` |
| `git add -- <path> …` | 8 |
| `git diff --name-only`, `git diff --cached --name-only` | 6 |
| `git rev-parse --verify <ci.base_ref>` | 13 |
| `git merge-base <ci.base_ref> HEAD` | 14 |
| `common.sh protected_changes <merge-base-sha>` | 27 → `protected_changes` |
| `common.sh is_commit_subject '<subject>'`, `common.sh commit_msg_file '<subject>'` | 27 → `is_commit_subject`, `commit_msg_file` |
| wrapper around `git commit -F <path>` (container mode: `RUN_IN_CONTAINER=1 git commit -F <path>`) | 9 (3); G1–G3 |
| `git log -1 --format=%s` | 7 |

Without `--issue` on a new branch it runs the /rs-sdlc-issue procedure first (listed below). It dispatches `rust-implementer` for the wiring checklist (see "Agents"). The C8 rollback, `make migrate-rollback`, is a template ask rule (see "`ask` rules in headless runs").

### /rs-sdlc-issue

The issue stage calls no git and no make target.

| Call | Covered by |
| --- | --- |
| `validate-profile.sh` | 27 |
| `gh issue view <N> --json number,url,title,body,labels,state` | 20 |
| `gh issue edit <N> --add-label rust-backend-sdlc`, `gh issue edit <N> --body-file target/rust-sdlc/tmp/issue.md` | 20 |
| `gh api --paginate 'repos/{owner}/{repo}/issues?labels=rust-backend-sdlc&state=open&sort=created&direction=desc&per_page=100' --jq …` | 20 |
| `gh label list --search rust-backend-sdlc …`, `gh label list --search enhancement …` | 20 |
| `gh label create rust-backend-sdlc --color 5319e7 --description …` | 20 |
| `common.sh redact --in target/rust-sdlc/tmp/issue.raw.md --out target/rust-sdlc/tmp/issue.md`, the same for `issue-title.md` | 27 → `redact` |
| `gh issue create --title '<redacted title>' --body-file target/rust-sdlc/tmp/issue.md --label rust-backend-sdlc --label enhancement` | 20 |

### /rs-sdlc-plan

| Call | Covered by |
| --- | --- |
| `validate-profile.sh` | 27 |
| `git branch --show-current` | 19 |
| `common.sh derive_issue_number --handle <N> --branch <branch>` | 27 → `derive_issue_number` |
| `gh issue view <N> --json number,title,body,labels,state` | 20 |
| `git status --porcelain -- specs/<N>-<kebab-title>` | 5 |
| `git log -1 --format=%s -- specs/<N>-<kebab-title>`, `git log -1 --format=%s` | 7 |
| the readiness checks of the planning skill's `## Verification` section (`test -s`, `grep`, `awk`, `wc`, `sort`, `uniq`, `cut`, `head`, `python3 -c`) | no entry; read-only checks of the bundle |
| `SPECS_DIR="specs/<N>-<kebab-title>"` | a shell assignment on its own line; it runs no program |
| `stage-planning-artifacts.sh "$SPECS_DIR" --dry-run` | 27 |
| `docker info`, `docker compose ps --status running --quiet app` (container mode) | 28, 29 |
| `common.sh hooks_active` | 27 → `hooks_active` |
| `git add -- specs/<N>-<kebab-title>` | 8 |
| `git diff --cached --name-only` | 6 |
| `git rev-parse --verify <ci.base_ref>` | 13 |
| `git fetch origin <project.default_branch>` | 12 |
| `git merge-base <ci.base_ref> HEAD` | 14 |
| `common.sh protected_changes <merge-base-sha>` | 27 → `protected_changes` |
| `common.sh is_commit_subject '<subject>'`, `common.sh commit_msg_file '<subject>'` | 27 → `is_commit_subject`, `commit_msg_file` |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `git commit -F <path>` (container mode: `RUN_IN_CONTAINER=1 git commit -F <path>`) | 9 (3); G1–G3 |
| `common.sh wait_log target/rust-sdlc/logs/plan-<UTC>.log` | 27 → `wait_log` |

### /rs-sdlc-implement

| Call | Covered by |
| --- | --- |
| `validate-profile.sh` | 27 |
| `git branch --show-current` | 19 |
| `common.sh derive_issue_number --branch <branch>` | 27 → `derive_issue_number` |
| `git status --porcelain --untracked-files=no`, `git status --porcelain` | 5 |
| `command -v cargo` | no entry (a shell built-in lookup) |
| `docker info`, `docker compose ps --status running --quiet app` (container mode) | 28, 29 |
| `common.sh hooks_active` | 27 → `hooks_active` |
| `SPECS_DIR="specs/<N>-<slug>"` | a shell assignment on its own line; it runs no program |
| `common.sh ralph_fix_plan_prepare "$SPECS_DIR" target/rust-sdlc/state/<N>-<slug>.json` | 27 → `ralph_fix_plan_prepare` |
| `stage-planning-artifacts.sh "$SPECS_DIR"` | 27 |
| `bmalph implement` | 21 (exact); B2 refuses any forced form |
| `common.sh ralph_fix_plan_restore target/rust-sdlc/ralph-archive/<UTC>-fix_plan.md` | 27 → `ralph_fix_plan_restore` |
| `git rev-parse HEAD`, `git rev-parse --verify <ci.base_ref>` | 13 |
| `common.sh state_cache_update target/rust-sdlc/state/<N>-<slug>.json implement …` | 27 → `state_cache_update` |
| `common.sh ralph_agent_md_patch "$SPECS_DIR"` | 27 → `ralph_agent_md_patch` |
| `common.sh ralph_breaker_state` | 27 → `ralph_breaker_state` |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `bmalph run --driver claude-code --no-dashboard` | 22 (exact) |
| wrapper around `make start`, `make validate-configuration base_ref=<sha> CONFIG_CHANGE_APPROVED=`, `make tests-with-coverage` | 1 for the make call |
| `common.sh wait_log <log>` | 27 → `wait_log` |
| `git fetch origin <default_branch>` | 12 |
| `git merge-base <ci.base_ref> HEAD` | 14 |
| `git log --format=%s <sha>..HEAD`, `git log --format=%h <sha>..HEAD`, `git log --format=%h -1 <sha>..HEAD -- <path>` | 7 |
| `common.sh is_commit_subject '<subject>'` | 27 → `is_commit_subject` |
| `common.sh protected_changes <sha>` | 27 → `protected_changes` |

The stage itself never commits: Ralph's sessions commit each story, with the hooks active, under the permission mode of `.ralph/.ralphrc` (see "Ralph's sessions run with `bypassPermissions`").

### /rs-sdlc-review

| Call | Covered by |
| --- | --- |
| `validate-profile.sh` | 27 |
| `grep -q '<!-- rust-backend-sdlc:begin -->' CLAUDE.md`, the same for `AGENTS.md` | no entry; read-only |
| `git branch --show-current` | 19 |
| `common.sh derive_issue_number --branch <branch>` | 27 → `derive_issue_number` |
| `gh pr view --json number --jq .number` | 20 |
| `git status --porcelain` | 5 |
| `git add -- <path> …` | 8 |
| `date -u +%Y-%m-%dT%H:%M:%SZ` | no entry; read-only |
| `command -v cargo` | no entry (a shell built-in lookup) |
| `docker info`, `docker compose ps --status running --quiet app` (container mode) | 28, 29 |
| `git rev-parse --verify <ci.base_ref>`, `git rev-parse HEAD` | 13 |
| `git fetch origin <default_branch>` | 12 |
| `git merge-base <ci.base_ref> HEAD` | 14 |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `make validate-configuration base_ref=<sha> CONFIG_CHANGE_APPROVED=`, `make start`, the `make.post_review_findings` target | 1 for the make call |
| `common.sh wait_log <log>` | 27 → `wait_log` |
| `common.sh protected_changes <sha>` | 27 → `protected_changes` |
| `git diff --name-status -M <sha> HEAD`, `git diff --name-only <sha>`, `git diff --name-only <previous head_sha> HEAD` | 6 |
| `gh pr view <pr> --json labels` | 20; the label is looked for in the output, so H1 and H2 never match |
| `common.sh ledger_write <lens> <n> <head_sha> [--started-at <started_at>]` with the findings block as a here-document | 27 → `ledger_write` |
| `common.sh hooks_active` | 27 → `hooks_active` |
| `common.sh is_commit_subject '<subject>'`, `common.sh commit_msg_file '<subject>'` | 27 → `is_commit_subject`, `commit_msg_file` |
| wrapper around `git commit -F <path>` (container mode: `RUN_IN_CONTAINER=1 git commit -F <path>`) | 9 (3); G1–G3 |
| `git log -1 --format=%s` | 7 |
| `post-review-findings.sh <lens> --pr <pr>` | 27 |

It dispatches `code-quality-reviewer`, `fr-nfr-reviewer`, `security-auditor` and, for remediation, `rust-implementer` (see "Agents"). It never pushes; the finish-pr stage pushes.

### /rs-sdlc-qa

| Call | Covered by |
| --- | --- |
| `validate-profile.sh` | 27 |
| `git branch --show-current` | 19 |
| `common.sh derive_issue_number --branch <branch>` | 27 → `derive_issue_number` |
| `gh issue view <N> --json number,url,title,body,state` | 20 |
| `git rev-parse HEAD` | 13 |
| `git status --porcelain --untracked-files=no` | 5 |
| `common.sh http_probe GET '<service.liveness_path>'` | 27 → `http_probe` |
| `docker compose ps --status running --quiet app`, `docker info` | 29, 28 |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `make start`, `make migrate`, `make schemathesis-validate SCHEMATHESIS_URL=<service.base_url>`; foreground `make doctor` | 1 for the make call |
| `common.sh wait_log <log>` | 27 → `wait_log` |
| `docker compose logs --no-log-prefix --tail 200 app` | 30 (the only log form; never `make logs`) |
| `command -v cargo` | no entry (a shell built-in lookup) |
| the background liveness poll (a bounded loop around `common.sh http_probe GET '<service.liveness_path>'` with `grep -x`, `echo` and `sleep 5`) | 27 → `http_probe` for the probe; the loop, `grep`, `echo` and `sleep` have no entry. When the runtime refuses the loop, the same poll runs as single `http_probe` calls, one Bash call each, with the same stop rule |

It dispatches `qa-manual-tester` (see "Agents"). It never stops the shared stack and never runs a target that would.

### /rs-sdlc-finish-pr

| Call | Covered by |
| --- | --- |
| `validate-profile.sh` | 27 |
| `git branch --show-current` | 19 |
| `git rev-parse --verify <ci.base_ref>`, `git rev-parse HEAD` | 13 |
| `git fetch origin <project.default_branch>` | 12 |
| `git merge-base <ci.base_ref> HEAD` | 14 |
| `common.sh protected_changes <merge-base-sha>` | 27 → `protected_changes` |
| `git status --porcelain --untracked-files=no` | 5 |
| `common.sh hooks_active` | 27 → `hooks_active` |
| `docker info`, `docker compose ps --status running --quiet app` (container mode) | 28, 29 |
| `gh pr view <n> --json number,url,state,isDraft,title,body,headRefName,headRefOid,isCrossRepository` | 20 |
| `gh pr list --head <branch> --state all --json number,url,state --limit 20` | 20 |
| `common.sh derive_issue_number --handle … --title … --branch … --body …` | 27 → `derive_issue_number` |
| `gh api user --jq .login` | 20 |
| `gh api repos/{owner}/{repo}/issues/<N>/comments --paginate \| common.sh resume_point --comments <login>` | 20 and 27 → `resume_point` |
| `common.sh resume_point --cache target/rust-sdlc/state/<N>-<slug>.json` | 27 → `resume_point` |
| `gh issue view <N> --json title` | 20 |
| `common.sh redact --in … --out target/rust-sdlc/tmp/pr-title.md`, the same for `pr-body.md` and `state.md` | 27 → `redact` |
| `common.sh is_commit_subject '<title>'`, `common.sh commit_msg_file '<subject>'` | 27 → `is_commit_subject`, `commit_msg_file` |
| `mkdir -p target/rust-sdlc/logs` | 38 |
| wrapper around `git push -u origin HEAD` (container mode: `RUN_IN_CONTAINER=1 git push -u origin HEAD`) | 10 (4); G4–G9 |
| `common.sh wait_log <log>` | 27 → `wait_log` |
| `gh pr create --base <project.default_branch> --head <branch> --title '<title>' --body-file target/rust-sdlc/tmp/pr-body.md` | 20 |
| `gh pr edit <n> --title '<title>' --body-file target/rust-sdlc/tmp/pr-body.md` | 20 |
| `gh api repos/{owner}/{repo}/issues/<n>/comments --paginate --jq …` | 20 |
| `post-review-findings.sh <lens> --pr <n> --bot-login <login>`, `post-review-findings.sh --conclusion --pr <n> --bot-login <login>` | 27 |
| `pr-state.sh --pr <n> --json --required-checks … --reviewers … --human-gated-checks … [--wait-seconds 540]` | 27 |
| wrapper around `fr-nfr-gate.sh --pr <n> --iteration <c> --spec-path '<SPECS_DIR>'` | 27 |
| wrapper around the `make.fr_nfr_gate` and `make.post_review_findings` targets, `make start` | 1 for the make call |
| `request-ai-reviews.sh --pr <n> --reviewers <names> [--full]` | 27 |
| `git add -- <path> …` | 8 |
| `git diff --cached --name-only` | 6 |
| wrapper around `git commit -F <path>` (container mode: `RUN_IN_CONTAINER=1 git commit -F <path>`) | 9 (3); G1–G3 |
| `common.sh state_cache_update …`, `common.sh state_comment_body …` | 27 → `state_cache_update`, `state_comment_body` |
| `gh api repos/{owner}/{repo}/issues/comments/<id> --jq .updated_at` | 20 |
| `gh api -X PATCH repos/{owner}/{repo}/issues/comments/<id> -F body=@target/rust-sdlc/tmp/state.md`, `gh api repos/{owner}/{repo}/issues/<N>/comments -F body=@target/rust-sdlc/tmp/state.md` | 20 |

It dispatches `ci-fixer`, `pr-comment-resolver` and `rust-implementer` (see "Agents"). It never merges (H3), never changes the draft state and never applies a label.

### Agents

Agents run through the Task tool in the session that dispatches them and are held by the same rules. None of them commits, pushes, stages or applies a label; the commands do. Besides `make` targets (row 1), each agent's contract allows only these calls:

| Agent | Calls and the entries that cover them |
| --- | --- |
| `rust-implementer` | git reads `git status`, `git diff`, `git log`, `git ls-files`, `git merge-base <ci.base_ref> HEAD` (5, 6, 7, 16, 14); `docker info`, `docker compose ps --status running --quiet app` (28, 29); `id -u`, `id -g` (39); `cargo tree -i <crate>` and `cargo metadata --format-version 1 --no-deps` on the host (template allow rules) or through the container route (31, 32); the single-test run `env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run -p <crate> <name>` (36, container route 34); `mkdir -p target/rust-sdlc/logs` once per dispatch, in the foreground, before the first background target (38); `common.sh wait_log`, `common.sh protected_changes` (27) |
| `code-quality-reviewer` | git reads `git diff`, `git status`, `git log`, `git ls-files`, `git rev-parse`, `git merge-base` (6, 5, 7, 16, 13, 14); `gh pr view <n> --json labels` (20); `docker info`, `docker compose ps --status running --quiet app` (28, 29); the read-only text commands `grep`, `awk`, `wc -l` and `tail` over logs and reports (no entry; when one is denied, the Grep and Read tools give the same numbers); `mkdir -p target/rust-sdlc/logs` once per dispatch, in the foreground, before the first background target (38); `common.sh wait_log` (27) |
| `fr-nfr-reviewer` | `fr-nfr-gate.sh --spec-path <SPECS_DIR> --iteration <n> [--pr <n>] [--advisory]` in the wrapper (27); `gh pr view <n> --json number,body,closingIssuesReferences`, `gh issue view <m> --json title,body`, `gh pr view --json number --jq .number` (20); git reads (5, 6, 7, 13, 14, 16); `docker info`, `docker compose ps --status running --quiet app` (28, 29); `mkdir -p target/rust-sdlc/logs` once per dispatch, in the foreground, before the first background target (38); `common.sh wait_log` (27) |
| `security-auditor` | `common.sh http_probe` (27, the only network path); `git diff --name-only <base>...HEAD` and the git reads (6, 5, 7, 13, 14, 16); `docker info`, `docker compose ps --status running --quiet app` (28, 29); `id -u`, `id -g` (39); `cargo tree -i <crate>` on the host (template allow rule) or through the container route (31); `mkdir -p target/rust-sdlc/logs` once per dispatch, in the foreground, before the first background target (38); `common.sh wait_log` (27) |
| `qa-manual-tester` | `common.sh http_probe <METHOD> <PATH> …` (27, the only network path); `docker compose logs --no-log-prefix --tail 200 app` (30); `git diff <ci.base_ref> HEAD -- <service.openapi_snapshot> <service.graphql_snapshot>` (6) |
| `ci-fixer` | `pr-state.sh --pr <n> --json …` (27); `gh pr checks`, `gh pr view`, `gh run list`, `gh run view --log-failed --job <job-id>` (20); `gh run rerun --failed <run-id>`, at most once per head and never for a human-gated check (20); git reads (5, 6, 7, 13, 14, 16); `docker info`, `docker compose ps --status running --quiet app` (28, 29); `id -u`, `id -g` (39); `cargo tree -i <crate>` (template allow rule, container route 31); `mkdir -p target/rust-sdlc/logs` once per dispatch, in the foreground, before the first background target (38); `common.sh wait_log`, `common.sh protected_changes` (27) |
| `pr-comment-resolver` | `get-pr-comments.sh --unresolved-only --json --pr <n>` and `ai-review-loop.sh --max-iterations 1 --diff-base <merge-base sha>` (27); `gh api graphql …` for the thread list, the reply and the resolve mutation, `gh api user`, `gh pr view`, `gh repo view` (20); git reads (5, 6, 7, 14, 16); `docker info`, `docker compose ps --status running --quiet app` (28, 29); `id -u`, `id -g` (39); `mkdir -p target/rust-sdlc/logs` once per dispatch, in the foreground, before the first background target (38); `common.sh redact`, `common.sh wait_log`, `common.sh protected_changes` (27) |

## Maintaining the allowlist

### After `claude plugin update`

The plugin-root entries (rows 25–27, 28 entries) hold the absolute plugin root, which includes the version directory of the plugin cache. After `claude plugin update rust-backend-sdlc@vilnacrm-plugins`, restart Claude Code and run `/rs-sdlc-setup` again in every repository that uses the plugin: the merge appends the 28 entries of the new root (`DONE: allowlist .claude/settings.local.json (+28 allow, +0 deny)`). The entries of the old root stay, because the merge never removes anything; they name a directory the plugin no longer runs from and are stale.

Remove them by hand:

1. List the plugin-root entries:

   ```bash
   python3 -c 'import json,sys; print("\n".join(e for e in json.load(open(sys.argv[1]))["permissions"]["allow"] if "/scripts/" in e))' .claude/settings.local.json
   ```

2. The listing prints the entries in file order, and setup appends the entries of the current root, so they are normally the last 28 lines. Every listed entry whose root differs from theirs is stale.
3. Delete the stale entries from `permissions.allow` with an editor, keep every other entry as it is, and keep the file valid JSON.
4. Run `/rs-sdlc-setup` again: it prints `UNCHANGED: .claude/settings.local.json` when every current entry is present.

### After uninstalling the plugin

`claude plugin uninstall rust-backend-sdlc@vilnacrm-plugins` does not touch `.claude/settings.local.json`. Delete the 28 plugin-root entries as above. The other 38 allow entries and the 29 deny entries are not tied to the plugin's location: keep the deny entries if you want their backstop, and delete the allow entries you do not want to keep (the allow and deny lists above are the complete set the plugin wrote).

### Seeing the entries without writing them

`/rs-sdlc-setup --print-settings` (or `merge-settings.sh --print`) prints the merged JSON and writes nothing. When `.claude/settings.local.json` is not git-ignored, setup prints the same JSON with `DEGRADED: .claude/settings.local.json is not git-ignored: allowlist printed, not written`; add the file to `.gitignore` and run setup again.

### Permission denials in a run

A call no rule allows prompts in an interactive session. In a headless run it comes back as a permission denial: on a template ask rule the target is recorded `not run (ask rule)` (D13); any other denial is reported verbatim in the stage's report, and the stage either degrades or ends `ESCALATED` as its contract says. Never work around a denial by spelling the call differently; add the missing entry to your own settings, or run the stage interactively once, and resume.
