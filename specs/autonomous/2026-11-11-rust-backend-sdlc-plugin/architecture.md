---
stepsCompleted: [step-01-init, step-02-context, step-03-starter, step-04-decisions, step-05-patterns, step-06-structure, step-07-validation, step-08-complete]
inputDocuments:
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/task-framing.md
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/research.md
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/product-brief.md
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/prd.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/architecture.md (depth bar, same artifact kind)
  - scratchpad research notes (rust-template, php-commands-agents, php-scripts-tests-docs, php-skills, react-workflows-repo-ci)
workflowType: 'architecture'
project_name: 'rust-backend-sdlc'
date: 2026-11-12
author: Winston (BMAD architect agent), autonomous run for the main agent acting as user surrogate
mode: autonomous (A/P/C menus skipped; every decision recorded as an ADR or an inline Assumption)
---

# Architecture: `rust-backend-sdlc` Claude Code Plugin

This document is the implementation contract for `plugins/rust-backend-sdlc/` 0.1.0. Two implementers who follow it must produce the same file tree, the same profile schema, the same script interfaces and the same component contracts. Where this document and the PRD differ, this document wins and names the PRD item it amends (marked **amends FR-n**). Where it says nothing, the PRD holds.

Path conventions: `tpl/` = the Rust service template (`/home/user/rust-service-template`, HEAD `3e0bd3e`); `php/` = `plugins/php-backend-sdlc/`; `react/` = `plugins/react-frontend-sdlc/`; `repo/` = the marketplace root; plugin paths (`commands/`, `scripts/`, …) are relative to `plugins/rust-backend-sdlc/`. FR/NFR/PA/D/J/K ids are the PRD's; S/C ids are the brief's new-service steps and new-context checklist; H/X ids are research hazards and reference defects.

> Assumption: the BMAD create-architecture workflow (architect agent "Winston", `_bmad/bmm/workflows/3-solutioning/bmad-create-architecture/`) ran non-interactively. Step 1 found the four bundle inputs; step 2 is "Project Context Analysis"; step 3 (starter template) maps to "the reference plugin is the starter": the php tree is mirrored and react's workflow layer is adopted; step 4 is "Core Architectural Decisions"; step 5 is "Implementation Patterns and Consistency Rules"; step 6 is "Project Structure" plus the contract sections; step 7 is "Architecture Validation"; step 8 is recorded in the frontmatter. Every A/P/C menu was answered "C" by the user surrogate; no web search changed a version (all versions come from the PRD floors and the local checkouts).
>
> Assumption: facts marked **[verified]** were re-checked in this session against `tpl/` at `3e0bd3e`, the bmalph 2.x `dist/` sources installed on the host, the Claude Code permissions documentation (`code.claude.com/docs/en/permissions`, fetched 2026-11-12) or a scratch run (template `scripts/check-docs.sh`, yamllint 1.38.0, Prettier 3.x, markdownlint-cli2 0.24.0).

## Constraints

Binding rules for every story that implements this plugin (bmalph copies this section into `.ralph/PROJECT_CONTEXT.md`):

- Write only under `plugins/rust-backend-sdlc/` plus three wiring files: `.claude-plugin/marketplace.json`, root `README.md`, `.github/workflows/ci.yml`. Never edit another plugin, `tools/plugin-quality/`, `_bmad/`, the template checkout or this bundle.
- Commit subjects in this repository: `<type>(rust-backend-sdlc): <subject>` (types `feat fix docs test ci chore refactor`), one story per commit or more; never `--no-verify`, never force-push.
- Done means all green: `python3 tools/plugin-quality/lint/lint_all.py` (0 findings, all plugins); `shellcheck -x plugins/rust-backend-sdlc/scripts/*.sh plugins/rust-backend-sdlc/scripts/lib/common.sh`; `npx --yes markdownlint-cli2 "plugins/rust-backend-sdlc/**/*.md"`; `npx --yes bats plugins/rust-backend-sdlc/tests/*.bats`, run once more with `SDLC_FORCE_PYTHON_YAML=1`; every per-suite floor of the Test Architecture met.
- Generalization: no `vilnacrm`, `user-service`/`user_service`/`user service`, `mongo…repository`, `apprunner`, `src/user`, `src/oauth` (case-insensitive) in `skills/ commands/ agents/ scripts/ workflows/` outside fences whose opening line carries `# profile-example`; `.sh` and `.js` files have no escape. The default template slug lives only in `config/new-service.defaults.json`. Fixtures use `acme/rust-template` and `acme/billing-service`.
- No path component named `_bmad` or `.ralph` anywhere in the plugin tree (fixtures create them at runtime). Fixture Markdown and fixture `.gitignore` ship as `*.tpl` and are materialized by `tests/lib/helpers.bash`.
- Pinned counts: 10 commands, 7 agents, 28 skills, 2 meta-guides, 13 scripts + `scripts/lib/common.sh`, 4 workflows, 9 docs, 16 bats suites. A story that changes a count updates `tests/component-counts.bats` in the same commit.
- Single-writer files (one story at a time, serialized): `tests/component-counts.bats`, `tests/lib/helpers.bash`, `docs/profile-schema.md`, `scripts/lib/common.sh`, `tests/fixtures/rust-repo/**`. Stories touching other, disjoint files may run in parallel.
- Byte-identical shared names: commit status context `BMAD FR/NFR Review Gate`; env vars `SDLC_FORCE_PYTHON_YAML`, `SDLC_LEDGER_DIR`, `SDLC_NOW_EPOCH`; new variables use the `RUST_SDLC_` prefix.
- Never write a php command token (a slash followed by `sdlc`) in any artifact; plugin command tokens are only the 10 `/rs-sdlc…` stems.
- Scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, source `lib/common.sh`, exit 0 success / 1 failure or refusal / 2 usage (exceptions: `pr-state.sh` and `request-ai-reviews.sh` exit 1 on usage, react parity), logs to stderr with `[rust-sdlc]`, data and handles to stdout; no `eval`, no `while true`, no `sed -i`, `readlink -f`, `date -d`, `grep -P`, `stat -c`; bash ≥ 4.4.
- Every documented flag, exit code and refusal of a script has a bats case; tests are hermetic (stubs on `PATH`, writes under `$BATS_TEST_TMPDIR`, no network).
- Plugin output written into a service must pass the template's linters (yamllint, Prettier, markdownlint-cli2, typos) and docs-check rules 1–4; the governance block text is fixed by the Governance Block section of this document.

## Project Context Analysis

**Requirements load.** 44 FRs (FR-1 to FR-44) and 16 NFRs. They group into seven architectural concerns, each owned by one component family:

| Concern | FRs | Owning components |
| --- | --- | --- |
| Stage machine, handles, escalation, run report, resume | FR-1 to FR-3, FR-15 to FR-21 | `commands/`, `scripts/lib/common.sh` (`resume_point`, state helpers) |
| Per-repository variance | FR-5 to FR-7 | `.claude/rust-sdlc.yml` (profile), `generate-profile.sh`, `validate-profile.sh` |
| Safe writes into a service | FR-4, FR-8, FR-9, FR-12 | `inject-governance.sh`, `merge-settings.sh`, `new-service.sh` |
| Lifecycle (service, context) | FR-11 to FR-14 | `rs-sdlc-new-service`, `rs-sdlc-new-context`, `new-service.sh`, `config/new-service.defaults.json`, `validate_context_name` |
| Review, gate, PR sensor | FR-19, FR-21, FR-34 to FR-39 | 6 review/PR scripts, 6 agents |
| Knowledge | FR-30 to FR-32 | 28 skills, 2 meta-guides |
| Packaging, docs, tests, CI, workflows | FR-40 to FR-44 | manifest, docs, bats, harness, CI jobs, `workflows/` |

**Cross-cutting concerns** (each has one implementation, referenced everywhere else): the profile (single shared state between scripts, skills, agents and commands); make-only execution with the container route and the background-and-poll rule (FR-1); hook-valid git (FR-2); the 7-field escalation block; the closed status vocabulary `SUCCESS` / `SUCCESS-WITH-REPORT` / `ESCALATED`; redaction before publishing (NFR-10); the forbidden-pattern set P1–P7 (NFR-5).

**Scale.** About 160 files: 10 commands, 7 agents, 42 skill-tree files + 2 meta-guides, 14 scripts, 1 config, 4 workflows, 10 docs (9 + README), 16 bats suites, about 150 fixture files. Medium complexity: low regulatory load, high integration surface (GitHub, Claude CLI, bmalph, the template's make surface, docker compose).

**Starter.** The reference plugin (`php/`) is the starter: directory layout, frontmatter contracts, script skeleton, test helpers and governance algorithm are mirrored; react's `pr-state.sh`, `request-ai-reviews.sh`, hardened `fr-nfr-gate.sh`, mikefarah `have_yq` probe, `resolve_repo_slug`, `claude_run_isolated` and the Workflow layer are ported with the Rust changes recorded below.

> Assumption: the `## Tech Stack` section below deliberately avoids the words bmalph's `detectTechStack` (`bmalph/dist/transition/tech-stack.js`) treats as stack markers (the JavaScript runtime's short name, its package manager, the scripting language without its version suffix, its installer, the service language's name and its build tool). When one of them appears there, `bmalph implement` rewrites the `.ralph/@AGENT.md` setup and test commands to that ecosystem's defaults, which are wrong for a bash/bats plugin repository **[verified]**. The real verification commands are in `## Constraints`. The service toolchain the plugin drives is described in "Template contract" under Core Architectural Decisions.

## Tech Stack

| Layer | Technology and version floor | Used for |
| --- | --- | --- |
| Prompt components | Markdown with YAML frontmatter in the Claude Code plugin format | 10 commands, 7 agents, 28 skills, 2 meta-guides |
| Manifests and configuration | JSON | `.claude-plugin/plugin.json`, the marketplace entry, `config/new-service.defaults.json` |
| Scripts | GNU Bash ≥ 4.4 on Linux (GNU userland) and macOS (BSD userland); git ≥ 2.30 | 13 executables and `scripts/lib/common.sh` |
| Data helpers | python3 ≥ 3.11 standard library (`json`, `tomllib`, `re`, `difflib`); YAML through mikefarah yq v4 or python3 with PyYAML; jq optional with a python3 fallback | profile, settings, ledgers, TOML and JSON reads |
| External command-line tools | gh ≥ 2.0; claude ≥ 2.1.248 (needs `--restricted`); bmalph ≥ 2.11.0; GNU make ≥ 4.0 and docker compose in the target repository only | GitHub, model sessions, the Ralph loop, the template's gates |
| Workflow layer | JavaScript scripts for the Claude Code Workflow tool; a JavaScript runtime ≥ 20 runs the deterministic test harness | `workflows/*.js`, `tests/lib/workflow-harness.mjs` |
| Tests | bats-core (fetched with npx in CI), stub executables, python3 helper for the static docs-check port | 16 suites, at least 460 cases |
| Linters | shellcheck with `-x`; markdownlint-cli2 0.24.0 with the repository `.markdownlint.yaml`; `tools/plugin-quality/lint/lint_all.py`; template-compatibility linters yamllint 1.38.0, Prettier 3.9.10, typos 1.52.0 | CI jobs `shellcheck`, `markdown-lint`, `bats` |

## Core Architectural Decisions

Each ADR states Context, Decision and Consequences. ADR-1 to ADR-11 carry the php ADRs forward with their Rust changes; ADR-12 onward are new.

### ADR-1: Runtime profile reads, no per-repository rendering

- **Context.** Skills, agents and commands must adapt to each service (targets, ports, paths, check names) without copies in the service, because copies drift and the template rejects plugin files under `.claude/skills/` (docs-check rule 7, template sync).
- **Decision.** Every component reads `.claude/rust-sdlc.yml` at runtime and refers to values by dotted key (`make.static_analysis`, `service.port`). Nothing is rendered into the service except the profile, the governance block and the local permission file.
- **Consequences.** Plugin updates are atomic (`claude plugin update`); every skill and agent carries a `## Profile keys consumed` section checked against `docs/profile-schema.md` (CI `profile-keys-check`, `component-counts.bats`); concrete values appear only inside `# profile-example` fences.

### ADR-2: Profile schema v1, bash-only validation, tighten-only bars

- **Context.** PRD FR-5 fixes 115 keys in 13 groups; PA-1 allows additions with a recorded decision.
- **Decision.** The schema is exactly the key table of "Project Profile Schema" (115 keys, no additions, no renames). `validate-profile.sh` parses YAML with mikefarah yq v4 or python3 + PyYAML (python is the reference implementation), never JSON Schema. TOML is read only through python3 `tomllib`. The 12 `quality.*` keys are tighten-only: floors may not be lower than 100, ceilings may not be higher than 0, and because those are the extremes every legal value equals the shipped default.
- **Consequences.** No schema dependency beyond python3; 12 rejection cases in `validate-profile.bats`; the generator never lowers a bar even when the repository relaxed its own gate (it warns instead, see `generate-profile.sh`).

### ADR-3: Governance through one docs-check-safe managed block

- **Context.** The template's `make docs-check` rejects backticked slash commands without `.claude/commands/<name>.md`, backticked paths that do not exist, `make <x>` citations of unknown targets, and numbered lists or fences naming three or more gate targets; invariant (e) rejects the literal template name in `CLAUDE.md`/`AGENTS.md`; template sync overwrites both files.
- **Decision.** `inject-governance.sh` owns one block between `<!-- rust-backend-sdlc:begin -->` and `<!-- rust-backend-sdlc:end -->` in `CLAUDE.md` and `AGENTS.md`, with the exact text of "Governance Block". Plugin commands are named in plain prose; the only backticked tokens are `.claude/rust-sdlc.yml`, `AGENTS.md`, `.claude/skills/README.md`, `protected-config.toml`, `quality.*` and `make.*`; no list is numbered and no fence exists. The algorithm is php's (fence-aware, CRLF-tolerant, duplicate repair, atomic write), with placement outside the `AGENTS.md` verification markers.
- **Consequences.** Verified clean against the template's own `scripts/check-docs.sh` and markdownlint-cli2 with the template configuration **[verified]**; the profile must be committed in the same commit as the block (rule 3 reads tracked files) and setup says so; re-running setup after a template-sync merge restores the block (J6).

### ADR-4: Bundled review and PR scripts with null substitution

- **Context.** Services do not ship review-loop, comment, gate or poster scripts.
- **Decision.** `ai-review-loop.sh`, `get-pr-comments.sh`, `fr-nfr-gate.sh`, `post-review-findings.sh` ship in `scripts/` and run as `"${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"`. The profile keys `make.ai_review_loop`, `make.pr_comments`, `make.fr_nfr_gate`, `make.post_review_findings` are `null` by default; a non-null value names a service make target that replaces the script.
- **Consequences.** One maintenance point; the generator maps these four keys only when the service defines targets with those exact names.

### ADR-5: Triage-based review with three lenses and the Q1–Q15 rows

- **Context.** Loading 28 skill bodies per review iteration costs an order of magnitude more tokens than triage.
- **Decision.** `/rs-sdlc-review` records 28 verdicts from frontmatter plus `skills/SKILL-DECISION-GUIDE.md`; bodies and reference files load only on `EXECUTE`. Lenses: `code-quality-reviewer` and `fr-nfr-reviewer` always; `security-auditor` when the diff since the merge base touches a security path (PA-5). Quality rows Q1–Q15 are exactly the PRD FR-19 table.
- **Consequences.** NFR-12 holds statically (docs-only class marks 6 skills `EXECUTE`); the 11 counterpart pairs count once (`repo+plugin`).

### ADR-6: Permissions: acceptEdits, local allowlist, no bypass

- **Context.** `.claude/settings.json` is protected in the template; the template's `deny` and `ask` rules must stay effective; headless runs cannot answer prompts.
- **Decision.** Every plugin `claude -p` call uses `--permission-mode acceptEdits`; the FR/NFR gate uses the isolated restricted session. `merge-settings.sh` merges the allowlist of "Permissions Strategy" into the git-ignored `.claude/settings.local.json` (default) and refuses `.claude/settings.json` when `protected-config.toml` lists it. `bypassPermissions` is never set by the plugin.
- **Consequences.** deny > ask > allow keeps the template's guard; headless `ask` targets are recorded `not run (ask rule)` (D13); the allowlist is per machine (it holds the absolute plugin root and the numeric uid:gid).

### ADR-7: Threshold canonicalization from the template's gates

- **Context.** Bars live in protected files (`make/gates.mk`, `clippy.toml`, `.spectral.yaml`, `tests/Load/config.json.dist`).
- **Decision.** Shipped defaults equal the template's values at `3e0bd3e` (derivation table in "Quality bars"). Complexity limits (cognitive 8, 50 lines, 5 arguments, nesting 5) are **not** profile keys: `clippy.toml` is their single source, quoted at review time; `quality.max_complexity_violations` (ceiling 0) is the profile's handle on them.
- **Consequences.** A profile copy of a protected limit could only drift, and a tighter copy could not be enforced without editing the protected `clippy.toml`; so the plugin reads the file instead. `generate-profile.sh` warns when the repository's gate is looser than the template value.

### ADR-8: Claude driver and the isolated gate session

- **Context.** Codex flags in older loops; contributor-controlled text (PR body, issues) reaches the gate prompt.
- **Decision.** `claude_run_once PROMPT` runs `claude -p "$PROMPT" --output-format json --permission-mode acceptEdits --max-turns 30`, extracts `.result` with jq or python3, retries once on transport failure (non-zero exit, `is_error: true`, missing `.result`); a well-formed negative verdict is never retried. `claude_run_isolated PROMPT` adds `--restricted --tools Read,Grep,Glob --strict-mcp-config --disallowedTools 'Bash(gh:*)' 'Bash(git push:*)' 'Bash(git credential:*)'`, unsets `GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN SSH_AUTH_SOCK`, sets `GH_CONFIG_DIR` to an empty temp dir and `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`. Verdict lines are mandatory last lines (`AI_REVIEW_VERDICT: PASS|FAIL`, `FR_NFR_NEW_FINDINGS: <n>`).
- **Consequences.** claude ≥ 2.1.248 is a preflight FAIL (PA-10); stub argv is asserted in `ai-review-loop.bats` and `fr-nfr-gate.bats`.

### ADR-9: Release tagging and marketplace source

- **Context.** Siblings install from `main` through a relative source.
- **Decision.** v0.1.0 ships with `"source": "./plugins/rust-backend-sdlc"`. Tags are `rust-backend-sdlc-vX.Y.Z`. Switch the entry to a pinned `git-subdir` source at the first external consumer or at v1.0.0, whichever comes first. Semver: MAJOR = profile `schema_version` bump, a removed or renamed command, agent, script flag or handle; MINOR = a new skill, command, profile key, script flag or degrade row; PATCH = fixes and wording.
- **Consequences.** CI `manifest-validate` asserts tag version = `plugin.json` version on tag builds once the tag filter includes the namespace.

### ADR-10: bmalph compatibility floor and the single implementer

- **Context.** bmalph `implement` copies `## Constraints` of `architecture.md` into `.ralph/PROJECT_CONTEXT.md` (`dist/transition/context.js:89-91`) and classifies research files only by `/tech.*research/i`; two implementers on one tree race.
- **Decision.** Floor bmalph 2.11.0 (preflight). Command path: `bmalph run --driver claude-code --no-dashboard` is the only implementer; the command polls and never dispatches `rust-implementer` while it runs. Workflow path: `stage-planning-artifacts.sh` + `bmalph implement`, then orchestrated `rust-implementer` rounds over `.ralph/@fix_plan.md`, never `bmalph run` (degrade note `bmalph run: not used (workflow path)`, PA-17). No vendored `_bmad/` or `.ralph/`; `bmalph implement --force` never; `.ralph/.ralphrc` never edited.
- **Consequences.** The story-dispatch rule reaches Ralph only through `## Constraints` of the service bundle; `/rs-sdlc-implement` verifies it in `.ralph/PROJECT_CONTEXT.md` before `bmalph run`.

### ADR-11: Meta-guides as loose files

- **Decision.** `skills/AI-AGENT-GUIDE.md` and `skills/SKILL-DECISION-GUIDE.md` sit at the `skills/` root without frontmatter, so they are not discovered as skills and relative links from `SKILL.md` files (`../SKILL-DECISION-GUIDE.md`) survive the install cache.
- **Consequences.** CI `frontmatter-check` matches skills as `skills/*/SKILL.md`; L5 and L30 cover the guides.

### ADR-12: Default template slug in plugin configuration

- **Context.** NFR-2 forbids the organization token in the four scanned directories; `/rs-sdlc-new-service` needs a default template.
- **Decision.** `config/new-service.defaults.json` (outside `skills/ commands/ agents/ scripts/ workflows/`) holds `template_repository` and four other defaults; `new-service.sh` resolves it through `resolve_plugin_root`. Override order: `--template` > `RUST_SDLC_TEMPLATE_REPO` > `RUST_SDLC_CONFIG_FILE` (alternate config path, tests) > `config/new-service.defaults.json`.
- **Consequences.** L28 and CI `generalization-audit` pass with the slug present; `component-counts.bats` greps the four directories plus `workflows/` for the slug and finds nothing.

### ADR-13: Make-only execution, suffix variables, container route, background by allowlist

- **Context.** Claude Code allow rules match the command text; a leading assignment of a variable that is not on Claude Code's known-safe list stops an allow rule from matching **[verified]**; `make` exports command-line variables to recipes, so `make check-commit-message COMMIT_TITLE='feat(#1): add x'` works (exit 0; a rejected title exits 2 through make) **[verified]**; foreground tool calls cap at 600 s.
- **Decision (amends FR-1, FR-2 spelling).** Every gate runs as `make <target> [VAR=value …]` with variables after the target: `make <t> RUN_IN_CONTAINER=1` in container mode, `make check-commit-message COMMIT_TITLE='<subject>'`, `make openapi-diff base_ref=<ref> BREAKING_CHANGE_APPROVED=true` (only when the PR carries the label), `make new-context group=<g> context=<c>`, `make create-migration name=<n>`, `make schemathesis-validate SCHEMATHESIS_URL=<url>`. Only hooked git calls keep the prefix form, because the hook's `make` reads the environment: `RUN_IN_CONTAINER=1 git commit …`, `RUN_IN_CONTAINER=1 git push …`. Raw calls are limited to the FR-1 exception list; in container mode calls (1)–(4) use the container route with the uid:gid resolved once to literals: `docker compose exec -T --user 1000:1000 app <command>`. Every `make` call except the foreground allowlist (`make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`), every hooked `git commit`/`git push` and `bmalph run` run in the background as `{ <command>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/<stage>-<YYYYMMDDTHHMMSSZ>.log 2>&1`, polled with `tail -n 40 <log>` at most every 30 s until the last line matches `^RUST_SDLC_EXIT=[0-9]+$`.
- **Consequences.** `Bash(make:*)` covers every gate call; `component-counts.bats` asserts the suffix spelling and the background sentence; docker-less hosts are classified by the template's message, never by make's exit 2 (D2).

### ADR-14: Durable stage state on the issue, cache second, resume as a tested helper

- **Context.** Resume must survive `cargo clean` and fresh clones (G2(c)); two runs on one issue can interleave (PRD open question 2).
- **Decision.** One issue comment with marker `<!-- rust-sdlc-state -->` holds the table `| stage | result | head_sha | iteration | at |` (`result` ∈ `PASS`, `IN_PROGRESS`, `ESCALATED`; one row per stage, edited in place). The cache `target/rust-sdlc/state/<N>-<kebab-title>.json` mirrors it. `lib/common.sh` provides `state_cache_update`, `state_comment_body` and `resume_point`; the orchestrator writes the comment with `gh api`. Concurrency: read the comment's `updated_at`, re-read it immediately before the PATCH; if it changed, re-merge once; a second change → `ESCALATED` with `blocking_finding: concurrent /rs-sdlc runs on issue #<N>`.
- **Consequences.** PA-7 rules are bats-tested (`common-lib.bats`); the workflow path keeps no state comment (resume within a run only, through `carry`).

### ADR-15: Library CLI dispatcher for command-side helpers

- **Context.** Commands need `validate_context_name`, `resume_point`, `derive_issue_number`, `is_commit_subject`, the state helpers and a ledger writer (`/rs-sdlc-review` has no `Write` tool); the script count is pinned at 13 + lib, and executing the library must exit 64 (AC-33.1).
- **Decision.** `scripts/lib/common.sh` is executable. Sourced, it defines functions only. Executed with a first argument in the closed set `validate_context_name resume_point derive_issue_number is_commit_subject redact state_cache_update state_comment_body ledger_write`, it runs that function with the remaining arguments and exits with its status; executed with no argument or any other first argument it prints `common.sh is a library; source it instead of executing` to stderr and exits 64.
- **Consequences.** Commands call `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" validate_context_name <g> <c>`, covered by the plugin-root allow rule; `common-lib.bats` tests both modes.

### ADR-16: Ledger schema versioning

- **Decision (resolves PRD open question 3).** Review ledgers are `{"schema_version": 1, "lens": "<security|fr-nfr|code-review>", "iteration": <n>, "head_sha": "<sha40>", "findings": [{"id", "severity", "file", "line", "rule", "summary", "status"}]}` with `severity` ∈ `Critical High Medium Low Info` and `status` ∈ `open fixed dropped`. `post-review-findings.sh` accepts a missing `schema_version` as 1 and rejects any other value with a degrade note (exit 0, nothing posted).
- **Consequences.** Ledger fixtures carry `schema_version: 1`; one bats case per rejection.

### ADR-17: Template detection evolves by WARN

- **Decision (resolves PRD open question 4).** The seven A1 marker files plus `CI_PREFLIGHT_TARGETS` starting with `validate-configuration` define `capabilities.template_derived`. A missing marker is a preflight `WARN` and sets the capability `false`; capabilities that depend on a missing file become `false`/`null` individually. No marker ever produces a `FAIL`.
- **Consequences.** A template rename degrades capabilities instead of blocking setup (D20).

### ADR-18: Workflow epic in v0.1.0 with a hand-back contract

- **Context.** React's feature workflow nests `workflow()` two levels deep, which the runtime forbids; PA-9 puts the epic in scope as the cut line.
- **Decision.** Ship 4 workflows, the harness and `workflows.bats`. `rs-sdlc-pr-until-green` takes `onGate: 'nested' | 'return'`; `rs-sdlc-feature` (top level only) calls it with `'return'`, runs `rs-sdlc-fr-nfr-review` itself on `GATE` and re-enters with `carry`. Workflows call plugin scripts through agents and parse `--json` output or verdict lines; no shared JS module (resolves PRD open question 5).
- **Consequences.** Static call-graph test (depth ≤ 1) and `--as-child` runs; if the epic slips, the same change removes the 4 workflows, `workflows.bats`, the harness, the fixtures and `docs/workflows.md` and sets the counts to 0 / 15 / 8.

### ADR-19: No lint widening in the plugin change

- **Context.** L22 is blind to `/rs-sdlc-…` tokens; L25 ignores the `rust`, `service`, `template` namespaces and flags `architecture.toml` and `persistence.rs` (A6).
- **Decision.** `tools/plugin-quality` is not changed. Plugin-local substitutes live in `component-counts.bats` (command-token check AC-1.4, dotted-key check AC-5.2). `docs/profile-schema.md` backticks `architecture.toml` and `persistence.rs` in its detection-source table so L25 finds them declared.
- **Consequences.** The change set stays inside the plugin plus three wiring files.

### ADR-20: Sync-flavour citation repair inside `new-service.sh`

- **Context.** Deleting either sync guide breaks docs-check rule 3 through `tpl/docs/extension-seams.md:82` (PA-20).
- **Decision.** `new-service.sh --phase customize` rewrites each code span naming a deleted flavour path to its bare file name and lists the edited file once in `.templatesyncignore`; when the template fixes the line the step prints `UNCHANGED: docs-check-citations`.
- **Consequences.** G1(a) holds with 0 manual edits; AC-12.5 covers both flavours.

### ADR-21: Plugin agents inside Ralph's sessions

- **Decision (resolves PRD open question 7).** The service bundle's `## Constraints` text (FR-16) states both branches: "when the `rust-backend-sdlc:rust-implementer` agent is available, independent stories may run as parallel subagents under the DB rule; otherwise implement stories sequentially under the same DB rule". `docs/setup-walkthrough.md` recommends a user-scope install so the agent resolves in Ralph's claude-code sessions.
- **Consequences.** No plugin component inspects install scope; both branches are correct.

### ADR-22: Hermetic test architecture with materialized fixtures

- **Decision.** All suites run against `tests/fixtures/rust-repo/` copied into `$BATS_TEST_TMPDIR` by `rr_materialize` (renames `*.tpl`, `git init -b main`, one commit, `origin` set); stub executables in `tests/fixtures/bin/`; a kislyuk-style `yq` stub only in `tests/fixtures/bin-kislyuk/`; K7 linter cases skip with a reason when the tool is absent locally and run in CI.
- **Consequences.** Fixture Markdown never reaches the repository's markdownlint job; fixture `.gitignore` never affects the marketplace repository's tracking.

### ADR-23: Exit-code convention

- **Decision.** 0 success; 1 failure or refusal; 2 usage error (unknown flag, missing value, conflicting flags, malformed `config/new-service.defaults.json`); 64 only for executing the library without a dispatcher name. Exceptions kept for react parity: `pr-state.sh` and `request-ai-reviews.sh` exit 1 on usage. `post-review-findings.sh` is degrade-first: every non-usage failure exits 0 with a `DEGRADED:` line, except a malformed ledger named with `--file` (exit 1, php parity).
- **Consequences.** `component-counts.bats` asserts every script's `Usage:` header lists its exit codes; each suite has an unknown-flag case.

### ADR-24: Refresh semantics and user-owned keys

- **Context.** `--refresh` re-detects the profile; PA-12 requires a hand flip of `capabilities.run_in_container` to survive.
- **Decision.** Five keys are user-owned and keep a valid existing value on `--refresh`: `capabilities.run_in_container` (unless `--run-in-container` is passed), `capabilities.dynamic_security_testing`, `capabilities.publish_pr_comments`, `review.reviewers`, `review.ai_review_agents`. Every other key is re-detected.
- **Consequences.** One preserve case per key in `generate-profile.bats`; the schema table marks them "preserve".

### Template contract (what the plugin drives, read-only)

The plugin drives services derived from the template; it never builds them itself. Facts it relies on **[verified]**: 51 template targets used by the `make.*` map exist in `Makefile` (none in `make/gates.mk`, which holds command lines and thresholds; `make/service.mk` is `-include`d at `Makefile:565`); `make ci` = `doctor` + 7 stages from `CI_STAGES` (`make/gates.mk`); `CI_*_TARGETS` at `Makefile:89-95`; HOST targets exit 2 with `This target needs a reachable container engine (docker).` (`Makefile:80`); the commit regex is case-sensitive `^(feat|fix|refactor|build|chore|ci|docs|style|perf|test)\(#[0-9]+\): .*` (`scripts/check-commit-message.sh:14`); the template's `.claude/settings.json` allows 80 rules, asks 11 (`make migrate-rollback`, `make build`, `make stop`, `make down`, `make clean`, `make purge`, `make update`, `make static-analysis-fix`, `make unused-dependencies-fix`, `make aws-load-tests`, `make aws-load-tests-cleanup`) and denies `--no-verify`, `-n`, force push, `git -c core.hooksPath`, `git config core.hooksPath`, and `.env.local` access; `.claude/settings.local.json` is git-ignored; 36 required checks and 3 human-gated checks come from `docs/repository-settings.md`.

## Implementation Patterns and Consistency Rules

### Naming

| Thing | Rule | Example |
| --- | --- | --- |
| Command file | `commands/rs-sdlc[-<stage>].md`, kebab, H1 `# rs-sdlc-<stage> — <title>` | `commands/rs-sdlc-plan.md` |
| Agent file | `agents/<name>.md`, `name` = stem = H1 lead token (`# <name> — <title>`) | `# rust-implementer — story implementer` |
| Skill | `skills/<name>/SKILL.md`, `name` = directory | `skills/dependency-policy/SKILL.md` |
| Script | `scripts/<verb-noun>.sh`, executable bit set | `scripts/merge-settings.sh` |
| Workflow | `workflows/rs-sdlc-<name>.js`, `meta.name` = stem | `rs-sdlc-pr-until-green` |
| Agent type in workflows and Task calls | `rust-backend-sdlc:<agent>` | `rust-backend-sdlc:ci-fixer` |
| Env var (new) | `RUST_SDLC_<NAME>` | `RUST_SDLC_TEMPLATE_REPO` |
| Plugin state in a service | under `target/rust-sdlc/` (git-ignored by the template's `target/`) | `target/rust-sdlc/logs/review-20261112T101500Z.log` |
| Issue state comment marker | `<!-- rust-sdlc-state -->` | — |
| PR comment markers | `<!-- rust-sdlc-review:<lens> -->`, `<!-- rust-sdlc-review:conclusion -->` | `<!-- rust-sdlc-review:security -->` |
| Managed label | `rust-backend-sdlc` | — |
| Bats test names | `@test "<script>: <behaviour>"` | `@test "validate-profile: rejects coverage_lines 99"` |

### Output vocabulary (stdout, one item per line, parsed by commands and workflows)

| Prefix | Emitted by | Meaning |
| --- | --- | --- |
| `DONE: <step> <detail>` | `new-service.sh`, commands | step executed and changed something |
| `UNCHANGED: <step-or-file> <detail>` | all writing scripts | already in the target state |
| `SKIP: <step> (<reason>)` | `new-service.sh`, commands | step not applicable |
| `NEXT: <instruction>` | `new-service.sh`, commands, `pr-state.sh` | a human or follow-up action |
| `WOULD: <action>` | `--dry-run` modes | nothing was done |
| `DEGRADED: <note>` | scripts and commands | one degrade note (collected into `degrade_notes`) |
| `WROTE:` / `CREATED:` / `UPDATED:` / `REPAIRED:` / `REFUSED:` / `STAGED:` / `REMOVED:` | writing scripts | file-level result |
| `VIOLATION: <key>: <reason>[ (<value> vs bound <bound>)]` | `validate-profile.sh` | one per violation |
| `PASS:` / `WARN:` / `FAIL:` / `INFO:` | `setup-preflight.sh` | `<STATUS>: <check-id>: <detail>[ — remediation: <text>]` |
| handles | commands, agents | `ISSUE_URL:`, `ISSUE_NUMBER:`, `BRANCH:`, `SPECS_DIR:`, `PR_URL:`, `---RALPH_STATUS---` block, `FR_NFR_REVIEWER:`, `FR_NFR_NEW_FINDINGS:`, `AI_REVIEW_VERDICT:`, `## Verdict:`, `## Status:` |

`DEGRADED:` is only a line prefix, never a status. Stage statuses are exactly `SUCCESS`, `SUCCESS-WITH-REPORT`, `ESCALATED`; the run report knows only `result: SUCCESS | ESCALATED` (mapping per PRD FR conventions).

### Script conventions

1. Skeleton, in this order: shebang; header comment (`# <name>.sh — <one line>`, blank comment, `# Usage: …`, flag list, `# Exit: 0 …; 1 …; 2 …`); `set -euo pipefail`; `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`; `# shellcheck source-path=SCRIPTDIR` and `# shellcheck source=lib/common.sh`; `source "$SCRIPT_DIR/lib/common.sh"`. Scripts resolve the library relative to themselves, so they run identically from a checkout and from the install cache.
2. `--help` prints the header block (lines 2 up to the first non-comment line, with the leading hash and one space stripped) through `print_usage "$0"` and exits 0; it is accepted in any position.
3. Argument parsing: `while (($#)); do case "$1" in …` with `"${2:?…}"` values through `need_value`; unknown flag → `die_usage "unknown argument: $1"` (exit 2).
4. Writes: only to the documented paths; `safe_write_target PATH ROOT` before every write (refuses a symlink, a non-regular file, a symlinked parent or a path outside the real path of ROOT); `atomic_write PATH` (same-directory `mktemp` + `mv -f`, keeps an existing file's mode, else `0666 & ~umask`).
5. Repository-derived text is stripped of control characters before it is printed, quoted with `yaml_squote` before it is emitted as YAML, and passed through `redact` before it is published.
6. Integers from users or repositories are compared with `strip_zeros`/`num_gt`/`num_lt`/`num_add`; never with `(( ))` on unbounded input.
7. Banned constructs (grep-tested over `scripts/`): `eval`, `while true`, `until false`, `sed -i`, `readlink -f`, `date -d`, `grep -P`, `stat -c`, `declare -n`, `mapfile -d`.

### Markdown component conventions

- **Commands.** Frontmatter `description` (≥ 20 characters, ≤ 1,536) and `argument-hint` (L9 shape: one or more `[…]` groups, nothing outside brackets). `allowed-tools` only on `rs-sdlc-review` and `rs-sdlc-qa`, value `["Bash", "Read", "Glob", "Grep", "Task"]`. Body H2s in this order: `Inputs`, `Procedure`, `Loop & exit condition`, `Iteration guard`, `Failure escalation` (extra H2s allowed after `Procedure`: `Resume table`, `Run report`, `Stage table`). The first fenced block of every command except setup and new-service runs `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"`. `## Iteration guard` states `MAX_ITERATIONS=5`; `## Failure escalation` holds the 7-field block.
- **Agents.** Frontmatter `name`, `description` (contains "Use when" or "Use this agent"), `tools` (comma string), `model` (`sonnet` or `opus`). Body H2s: `Profile keys consumed`, `Role`, `Inputs`, `Outputs`, `Allowed actions`, `Degrade paths`, `Iteration discipline`, `Smoke prompt`.
- **Skills.** Frontmatter `name` and `description` only (contains "Use when"; L11 cap 1,536 characters including `name`). First H2 `## Profile keys consumed` (a bullet list of backticked keys, or the single bullet `- none`); for the 11 counterparts the second H2 is `## Repository precedence`; then `## Context`, `## Task`, `## Success criteria`, `## Steps`, `## Constraints`, `## Verification`. An H2 whose text matches `gate` or `gating` as a word must contain the word `skip`/`skipped` or a `SKIPPED:` line (L18). Relative links only to files inside the plugin; target-repository files are backticked, never linked (L21).
- **Everywhere.** Every fence has a language (`bash`, `yaml`, `json`, `text`, `rust`, `toml`, `markdown`); no inline HTML except comment markers; one H1; no duplicate heading text in a file (the repository's markdownlint has `MD024` without `siblings_only`); concrete service values only inside fences whose opening line carries `# profile-example`; never name `php-implementer`, `react-implementer` or `general-purpose` as a backticked agent (L23).

### The canonical escalation block

```text
=== SDLC ESCALATION ===
stage: <stage-id>
iteration: <n>/5
exit_condition: <exit string, verbatim from the stage table>
status: NOT MET
blocking_finding: <file:line | check name + URL | command + exit code>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human action: a label, a protected change with ALLOW_PROTECTED_CONFIG_EDIT=1, a command>
=== END ===
```

Stage ids: `setup`, `setup-check`, `new-service`, `new-context`, `issue`, `plan`, `implement`, `review`, `qa`, `finish-pr`. For finish-pr the `iteration` field names the exhausted counter: `iteration: 5/5 (ci_fix)`.

### Git rules (FR-2, ADR-13)

- Subject builder: `<type>(#<N>): <subject>`; `<subject>` is lower-case first word, no trailing period, ≤ 72 characters total, single line; a `'` inside is written `'\''` in the shell call.
- Pre-validation before every commit and every `gh pr create|edit --title`: `make check-commit-message COMMIT_TITLE='<subject>'` when `make.check_commit_message` is mapped (foreground), else `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" is_commit_subject '<subject>'`.
- Issue number: `derive_issue_number --handle <ISSUE_NUMBER> --title <PR title> --branch <branch> --body <PR body>` (first non-empty source wins; PR number never used).
- Hooks: `git config --get core.hooksPath` empty → `make install-hooks`. Commands own every commit and push; agents never commit.

## Project Structure

### Plugin tree (complete; every file the implementation creates)

```text
plugins/rust-backend-sdlc/
├── .claude-plugin/
│   └── plugin.json                         # 8 keys, see "Plugin Manifest and Configuration"
├── README.md                               # install, floors, 10 commands, quick start, workflows, docs links
├── config/
│   └── new-service.defaults.json           # default template slug + 4 defaults (ADR-12); outside scanned dirs
├── commands/                               # 10 (FR-1..FR-4, FR-11, FR-14..FR-16, FR-18..FR-21)
│   ├── rs-sdlc.md                          # orchestrator: stage table, resume table, state comment, run report
│   ├── rs-sdlc-setup.md                    # preflight → bmalph-setup → profile → governance → allowlist → hooks → docs-check
│   ├── rs-sdlc-new-service.md              # S1–S14
│   ├── rs-sdlc-new-context.md              # name validation, make new-context, C1–C12, context gate set
│   ├── rs-sdlc-issue.md                    # stage 1
│   ├── rs-sdlc-plan.md                     # stage 2
│   ├── rs-sdlc-implement.md                # stage 3 (bmalph run, single implementer)
│   ├── rs-sdlc-review.md                   # stage 4 (triage 28, 3 lenses, Q1–Q15, gate loop)
│   ├── rs-sdlc-qa.md                       # stage 5 (black-box HTTP)
│   └── rs-sdlc-finish-pr.md                # stage 6 (sensor loop A/B/C/W/R)
├── agents/                                 # 7 (FR-22..FR-29)
│   ├── rust-implementer.md                 # sonnet
│   ├── code-quality-reviewer.md            # opus
│   ├── fr-nfr-reviewer.md                  # opus
│   ├── qa-manual-tester.md                 # sonnet, tools Bash, Read
│   ├── ci-fixer.md                         # sonnet
│   ├── pr-comment-resolver.md              # sonnet
│   └── security-auditor.md                 # opus
├── skills/                                 # 28 skills (FR-30, FR-31) + 2 meta-guides (FR-32)
│   ├── AI-AGENT-GUIDE.md                   # no frontmatter
│   ├── SKILL-DECISION-GUIDE.md             # no frontmatter; 28-row table; "every skill verdict recorded, no silent skips"
│   ├── api-contract-development/SKILL.md
│   ├── api-resource-development/SKILL.md
│   ├── architecture-boundary-fixer/SKILL.md
│   ├── architecture-model-sync/SKILL.md
│   ├── async-runtime-safety/SKILL.md
│   ├── bmad-autonomous-planning/SKILL.md
│   ├── bmad-fr-nfr-review-gate/SKILL.md
│   ├── bounded-context-scaffolding/SKILL.md
│   ├── cache-management/SKILL.md
│   ├── cache-management/examples/cache-implementation.md
│   ├── cache-management/examples/cache-testing.md
│   ├── clean-architecture-llm/SKILL.md
│   ├── code-organization/SKILL.md
│   ├── code-organization/DIRECTORY-STRUCTURE.md
│   ├── code-review/SKILL.md
│   ├── complexity-management/SKILL.md
│   ├── configuration-management/SKILL.md
│   ├── database-migrations/SKILL.md
│   ├── dependency-policy/SKILL.md
│   ├── documentation-creation/SKILL.md
│   ├── documentation-sync/SKILL.md
│   ├── implementing-ddd-architecture/SKILL.md
│   ├── implementing-ddd-architecture/REFERENCE.md
│   ├── load-testing/SKILL.md
│   ├── load-testing/reference/configuration.md
│   ├── load-testing/reference/graphql-patterns.md
│   ├── load-testing/reference/rest-api-patterns.md
│   ├── load-testing/reference/troubleshooting.md
│   ├── load-testing/reference/utils-extensions.md
│   ├── observability-instrumentation/SKILL.md
│   ├── quality-standards/SKILL.md
│   ├── query-performance-analysis/SKILL.md
│   ├── rust-error-handling/SKILL.md
│   ├── security-audit/SKILL.md
│   ├── security-audit/reference/attack-playbooks.md
│   ├── security-audit/reference/owasp-catalog.md
│   ├── security-audit/reference/remediation-patterns.md
│   ├── service-scaffolding/SKILL.md
│   ├── testing-workflow/SKILL.md
│   └── verification-workflow/SKILL.md
├── scripts/                                # 13 executables + library (all chmod 755)
│   ├── lib/common.sh                       # library + closed CLI dispatcher (ADR-15)
│   ├── setup-preflight.sh                  # FR-10
│   ├── generate-profile.sh                 # FR-6
│   ├── validate-profile.sh                 # FR-7
│   ├── inject-governance.sh                # FR-8
│   ├── merge-settings.sh                   # FR-9
│   ├── new-service.sh                      # FR-12
│   ├── stage-planning-artifacts.sh         # FR-17
│   ├── ai-review-loop.sh                   # FR-34
│   ├── fr-nfr-gate.sh                      # FR-35
│   ├── get-pr-comments.sh                  # FR-36
│   ├── post-review-findings.sh             # FR-37
│   ├── pr-state.sh                         # FR-38
│   └── request-ai-reviews.sh               # FR-39
├── workflows/                              # 4 (FR-44, epic 8, the cut line)
│   ├── rs-sdlc-feature.js                  # top level only
│   ├── rs-sdlc-review-panel.js             # leaf
│   ├── rs-sdlc-pr-until-green.js           # leaf when onGate:'return'
│   └── rs-sdlc-fr-nfr-review.js            # leaf
├── docs/                                   # 9 (FR-41)
│   ├── profile-schema.md
│   ├── setup-walkthrough.md
│   ├── sdlc-loop.md
│   ├── permissions.md
│   ├── degrade-matrix.md
│   ├── release-process.md
│   ├── new-service-walkthrough.md
│   ├── workflows.md
│   └── testing/test-strategy.md
└── tests/                                  # 16 suites (FR-42)
    ├── ai-review-loop.bats
    ├── common-lib.bats
    ├── component-counts.bats
    ├── fr-nfr-gate.bats
    ├── generate-profile.bats
    ├── get-pr-comments.bats
    ├── inject-governance.bats
    ├── merge-settings.bats
    ├── new-service.bats
    ├── post-review-findings.bats
    ├── pr-state.bats
    ├── request-ai-reviews.bats
    ├── setup-preflight.bats
    ├── stage-planning-artifacts.bats
    ├── validate-profile.bats
    ├── workflows.bats
    ├── lib/
    │   ├── helpers.bash                    # shared setup, rr_materialize, sandbox_path, k7_require, bundle_write
    │   ├── docs-rules.py                   # static port of docs-check rules 1–4 + invariant (e), run with python3 -I
    │   └── workflow-harness.mjs            # ported from react + --as-child + top-level schema `required` check
    └── fixtures/
        ├── bin/                            # stubs driven by STUB_* env vars; each appends argv to $STUB_<NAME>_LOG
        │   ├── bmalph
        │   ├── cargo
        │   ├── claude
        │   ├── docker
        │   ├── gh
        │   └── make
        ├── bin-kislyuk/
        │   └── yq                          # prints "array" for `.a | type` (rejected by have_yq)
        ├── rust-repo/                      # stub template-derived repository, identity acme/rust-template
        │   ├── .claude/settings.json
        │   ├── .claude/skills/README.md.tpl
        │   ├── .coderabbit.yaml
        │   ├── .env
        │   ├── .env.test
        │   ├── .github/ISSUE_TEMPLATE/feature_request.md.tpl
        │   ├── .github/TEMPLATE_SYNC_APP.md.tpl
        │   ├── .github/TEMPLATE_SYNC_PAT.md.tpl
        │   ├── .github/graphql-spec/spec
        │   ├── .github/openapi-spec/spec.yaml
        │   ├── .github/pull_request_template.md.tpl
        │   ├── .github/workflows/change-control.yml
        │   ├── .github/workflows/contracts.yml
        │   ├── .github/workflows/load-tests.yml
        │   ├── .github/workflows/quality.yml
        │   ├── .github/workflows/release.yml
        │   ├── .github/workflows/repository.yml
        │   ├── .github/workflows/security.yml
        │   ├── .github/workflows/template-sync-app.yml   # TEMPLATE_REPOSITORY: acme/rust-template
        │   ├── .github/workflows/template-sync-pat.yml   # TEMPLATE_REPOSITORY: acme/rust-template
        │   ├── .github/workflows/tests.yml
        │   ├── .markdownlint-cli2.yaml          # copy of the template's
        │   ├── .prettierrc.yml                  # copy of the template's
        │   ├── .sqlx/query-fixture.json
        │   ├── .templatesyncignore
        │   ├── .yamllint.yml                    # copy of the template's
        │   ├── AGENTS.md.tpl                    # with <!-- verification:start/end --> markers
        │   ├── CHANGELOG.md.tpl                 # with one release section (proves the reset)
        │   ├── CLAUDE.md.tpl
        │   ├── Cargo.lock
        │   ├── Cargo.toml                       # virtual workspace, [workspace.package], [workspace.dependencies]
        │   ├── Makefile                         # stub `##` targets for the 51 mapped targets, CI_*_TARGETS, -include make/service.mk
        │   ├── README.md.tpl                    # banner, H1, acme/rust-template badges, intro paragraph
        │   ├── _typos.toml                      # copy of the template's
        │   ├── architecture.toml                # 7 layers
        │   ├── bmalph/config.json
        │   ├── clippy.toml                      # 8 / 50 / 5 / 5
        │   ├── crates/billing/invoice/application/Cargo.toml
        │   ├── crates/billing/invoice/domain/Cargo.toml
        │   ├── crates/billing/invoice/infrastructure/Cargo.toml
        │   ├── crates/internal/health-check/application/Cargo.toml
        │   ├── crates/internal/health-check/domain/Cargo.toml
        │   ├── crates/internal/health-check/infrastructure/Cargo.toml
        │   ├── crates/service/Cargo.toml
        │   ├── crates/shared/application/Cargo.toml
        │   ├── crates/shared/domain/Cargo.toml
        │   ├── crates/shared/infrastructure/Cargo.toml
        │   ├── deny.toml
        │   ├── docs/extension-seams.md.tpl      # line citing both .github/TEMPLATE_SYNC_*.md guides
        │   ├── docs/make-targets.md.tpl         # gate table `| G1 | format-check |` …
        │   ├── docs/new-service.md.tpl
        │   ├── docs/repository-settings.md.tpl  # the template's 7 job tables + "Labels to create" verbatim
        │   ├── gitignore.tpl                    # becomes .gitignore (target/, .claude/settings.local.json, _bmad-output/, …)
        │   ├── make/gates.mk                    # COVERAGE_GATE_CMD, CI_STAGES, SPECTRAL/OASDIFF/TRIVY flags
        │   ├── migrations/20261110000000_create_invoices.down.sql
        │   ├── migrations/20261110000000_create_invoices.up.sql
        │   ├── protected-config.toml            # files incl. .claude/settings.json, clippy.toml, architecture.toml, make/gates.mk
        │   ├── rust-toolchain.toml              # channel "1.99.1"
        │   ├── specs/example-bundle/prd.md.tpl  # a shipped bundle (proves the specs reset)
        │   ├── tests/Load/config.json.dist
        │   ├── tests/e2e/Cargo.toml
        │   ├── tests/support/Cargo.toml
        │   ├── workspace.dsl
        │   └── xtask/Cargo.toml
        ├── variants/
        │   ├── repository-settings-service.md.tpl  # adds one `Required: yes` row (AC-6.5)
        │   └── extension-seams-fixed.md.tpl         # bare-name citations (UNCHANGED path of ADR-20)
        ├── profiles/
        │   ├── golden.yml                       # exact generate-profile.sh output for the materialized rust-repo
        │   ├── invalid-yaml.yml
        │   ├── wrong-schema-version.yml
        │   ├── bad-enum.yml
        │   └── publish-off.yml
        ├── ledgers/
        │   ├── 20-digit-count.json
        │   ├── dedup-pair.json
        │   ├── dropped-and-open.json
        │   ├── empty.json
        │   ├── full.json
        │   ├── minimal.json
        │   ├── mixed-severity.json
        │   ├── pipe-and-distinct.json
        │   ├── secret-laden.json
        │   ├── with-times.json
        │   └── wrong-schema-version.json
        ├── gh/
        │   ├── pr-comments.json
        │   ├── pr-comments-truncated.json
        │   ├── pr-issue-comments.ndjson
        │   ├── pr-issue-comments-oversized.ndjson
        │   └── pr-state/
        │       ├── comments-quiet.ndjson
        │       ├── comments-requested.ndjson
        │       ├── comments-skips.ndjson
        │       ├── pr-conflicting.json
        │       ├── pr-merged.json
        │       ├── pr-open-gate-failed.json
        │       ├── pr-open-gate-pending.json
        │       ├── pr-open-green-nogate.json
        │       ├── pr-open-green.json
        │       ├── pr-open-human-gated-red.json     # failing check run named "Protected configuration"
        │       ├── pr-open-nochecks.json
        │       ├── pr-open-pending.json
        │       ├── pr-open-red.json
        │       ├── pr-open-service-check-red.json   # failing check from a service-added workflow
        │       ├── reviews-approved.ndjson
        │       ├── reviews-coderabbit-changes.ndjson
        │       ├── reviews-cubic-stale.ndjson
        │       ├── reviews-none.ndjson
        │       └── threads-empty.json
        └── workflows/                       # harness scenarios (53), see "Workflow Epic"
            └── <prefix>-<scenario>.json
```

The 53 scenario files are listed by name in "Workflow Epic"; no other file exists in the tree. No `.gitkeep` files are shipped.

### Repository wiring files (outside the plugin)

| File | Change | Section |
| --- | --- | --- |
| `.claude-plugin/marketplace.json` | append one plugin entry | Repository Wiring |
| `README.md` | one plugin-table row, one install line | Repository Wiring |
| `.github/workflows/ci.yml` | tag filter; explicit plugin list in `profile-keys-check` and `generalization-audit`; K7 linter install in `bats` | Repository Wiring |

### Dependency direction (strict, grep-checked in `component-counts.bats`)

```text
commands  ──►  agents (Task, subagent_type rust-backend-sdlc:<agent>)  ──►  skills (load on EXECUTE)
commands  ──►  skills (direct: bmad-autonomous-planning, bounded-context-scaffolding, service-scaffolding, decision guide)
commands, agents, workflows  ──►  scripts via "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" (workflows: via agents, $P root)
workflows ──►  agents (agentType) and at most one level of workflow() (feature → leaves)
skills    ──►  .claude/rust-sdlc.yml (runtime read) + sibling skills (relative links)
scripts   ──►  scripts/lib/common.sh, config/new-service.defaults.json (new-service.sh only), get-pr-comments.sh (pr-state.sh only)
```

Forbidden edges: skills never invoke agents, commands or scripts; scripts never read `SKILL.md`, `commands/` or `agents/`; agents never invoke commands or workflows; nothing reads `docs/` at runtime.

## Plugin Manifest and Configuration

### `.claude-plugin/plugin.json` (exact)

```json
{
  "name": "rust-backend-sdlc",
  "version": "0.1.0",
  "description": "Full-SDLC automation for Rust microservices built from the Rust service template: one-command service creation, bounded-context scaffolding, GitHub issue creation, BMAD-method planning, bmalph/Ralph implementation with Claude CLI, multi-lens code review with the BMAD FR/NFR gate, black-box REST and GraphQL QA, CI auto-fix, and AI review comment resolution, looping until the PR is finished.",
  "author": {
    "name": "VilnaCRM",
    "url": "https://github.com/VilnaCRM-Org"
  },
  "homepage": "https://github.com/VilnaCRM-Org/claude-plugins/tree/main/plugins/rust-backend-sdlc",
  "repository": "https://github.com/VilnaCRM-Org/claude-plugins",
  "license": "MIT",
  "keywords": ["rust", "sdlc", "bmad", "ralph", "microservices", "axum", "automation", "code-review", "qa", "ci", "github"]
}
```

Exactly these 8 keys, no custom keys (CI `manifest-validate`, M1–M3). The marketplace entry's `description` is byte-identical to this one.

### `config/new-service.defaults.json` (exact)

```json
{
  "template_repository": "VilnaCRM-Org/rust-service-template",
  "default_visibility": "private",
  "default_version": "0.1.0",
  "poll_attempts": 10,
  "poll_interval_seconds": 3
}
```

Validation on read (`new-service.sh`, python3 `json`): an object with exactly these keys; `template_repository` matches `is_slug`; `default_visibility` ∈ `private public`; `default_version` matches `is_semver`; `poll_attempts` integer 1–60; `poll_interval_seconds` integer 0–60. Any violation → `[rust-sdlc][ERROR] malformed <path>: <key>: <reason>` and exit 2. `RUST_SDLC_CONFIG_FILE` names an alternate file with the same schema (tests write one with `poll_interval_seconds: 0`).

## Project Profile Schema (`.claude/rust-sdlc.yml`)

### Conventions

- **Location and ownership.** `.claude/rust-sdlc.yml` at the repository root, committed. Written only by `generate-profile.sh` (atomic, `--refresh` or first run); hand edits are legal and survive unless `--refresh` re-detects the key (ADR-24).
- **115 keys in 13 groups**, emitted in the order of the tables below (group order: root, `project`, `rust`, `template`, `framework`, `persistence`, `architecture`, `service`, `make`, `quality`, `ci`, `review`, `capabilities`).
- **Required (R) keys must be present; optional (O) keys may be omitted.** "Null means absent; omitted means error" for every R key whose Nullable column says yes; a non-nullable R key may never be `null`. Every `make.*` key is R and nullable.
- **Unknown keys are violations** (a misspelled key, for example coverage_line under quality, fails validation); a new key requires a schema change (ADR-9 MINOR).
- **Emission format** (yamllint `extends: default` with the template's overrides and Prettier `singleQuote: true` clean, **[verified]** on the example below): block style only, never flow collections; 2-space indentation; sequence items indented two spaces under their key; no document start `---`; exactly one trailing newline; no trailing spaces; two header comment lines (`# Project profile of the rust-backend-sdlc plugin (schema_version 1).` and `# Written by generate-profile.sh; re-detect with /rs-sdlc-setup --refresh.`); no other comments. Scalars: ints and booleans and `null` bare; enum values, `make.*` target names and `review.*` list items bare; every other string (names, paths, versions, URLs, check names, workflow stems) single-quoted through `yaml_squote` (inner `'` doubled).
- **Detection never runs `cargo`, `make`, `gh` or the network.** It reads files with python3 (`tomllib`, `json`, `re`) and `git` (origin URL, branches, log subjects). A missing source never fails generation; the key takes its fallback.
- **Refresh column.** `preserve` = an existing valid value survives `--refresh` (ADR-24); blank = re-detected.

### Keys other than `make.*` and `quality.*`

| Key | Type | Req | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `schema_version` | int | R | no | `1` | `1` only | constant | | `validate-profile.sh`, every command's first step |
| `project.name` | string | R | no | basename rule | `^[a-z0-9][a-z0-9_-]*$` | basename of TARGET_DIR, lower-cased, every `[^a-z0-9_-]` → `-` (the Makefile's `PROJECT_NAME` rule) | | `/rs-sdlc-new-service`, run report, `service-scaffolding` |
| `project.repo` | string | R | yes | `null` | `is_slug` | `git remote get-url origin` when the host is `github.com` (`https://github.com/o/n[.git]`, `git@github.com:o/n[.git]`, `ssh://git@github.com/o/n[.git]`) | | `/rs-sdlc-issue`, `/rs-sdlc-finish-pr`, `/rs-sdlc-new-service` S14, `service-scaffolding`; scripts resolve the slug live with `resolve_repo_slug` |
| `project.default_branch` | string | R | no | `'main'` | `^[A-Za-z0-9._/-]+$` | `default_branch` (origin/HEAD symbolic ref → `main` → `master` → `main`) | | `ci.base_ref`, orchestrator branch creation, setup branch warning, `bmad-autonomous-planning` |
| `project.description` | string | O | yes | `null` | ≤ 200 characters, single line | `[workspace.package].description` of `Cargo.toml` | | `/rs-sdlc-issue`, `/rs-sdlc-plan` prompts, `service-scaffolding` |
| `rust.toolchain` | string | R | yes | `null` | `^[0-9A-Za-z._-]+$` | `rust-toolchain.toml` `[toolchain].channel` | | `rust-implementer`, `verification-workflow` |
| `rust.edition` | string | R | yes | `null` | `^20[0-9]{2}$` | `[workspace.package].edition` | | `rust-implementer`, `code-organization` |
| `rust.msrv` | string | O | yes | `null` | `^[0-9]+\.[0-9]+(\.[0-9]+)?$` | `[workspace.package].rust-version` | | `dependency-policy` |
| `template.repository` | string | O | yes | `null` | `is_slug` | `TEMPLATE_REPOSITORY:` value in `.github/workflows/template-sync-app.yml`, else in `template-sync-pat.yml` | | `service-scaffolding`, `/rs-sdlc-new-service` (`--in-place` identity) |
| `template.sync_flavour` | enum | R | no | `none` | `app` `pat` `both` `none` | which of `template-sync-app.yml`, `template-sync-pat.yml` exist | | `service-scaffolding`, `/rs-sdlc-new-service` |
| `template.source_commit` | string | O | yes | `null` | `^[0-9a-f]{7,40}$` | first `git log --format=%s` subject matching `^chore\(#[0-9]+\): import template [^ ]+ at ([0-9a-f]{7,40})$` | | `service-scaffolding` |
| `framework.http` | enum | R | yes | `null` | `axum` | key `axum` in `[workspace.dependencies]` | | `api-resource-development`, `rust-error-handling`, `qa-manual-tester` |
| `framework.openapi` | bool | R | no | `false` | — | key `utoipa` in `[workspace.dependencies]` | | `api-contract-development`, `/rs-sdlc-qa`, review Q12–Q14 |
| `framework.graphql` | bool | R | no | `false` | — | key `async-graphql` in `[workspace.dependencies]` | | `api-resource-development` (GraphQL section skip), `api-contract-development`, `/rs-sdlc-qa` |
| `persistence.engine` | enum | R | yes | `null` | `postgresql` | key `sqlx` in `[workspace.dependencies]` whose `features` contain `postgres` | | `database-migrations`, `query-performance-analysis`, `/rs-sdlc-qa` pre-probe migrate, review Q11 |
| `persistence.migrations_dir` | string | R | yes | `null` | relative path | `migrations/` is a directory → `'migrations'` | | `database-migrations`, C8 |
| `persistence.offline_metadata` | bool | R | no | `false` | — | `.sqlx/` is a directory | | `database-migrations`, `query-performance-analysis` |
| `architecture.crates_root` | string | R | yes | `null` | relative path | `crates/` is a directory → `'crates'` | | `code-organization`, `bounded-context-scaffolding`, `rust-implementer` |
| `architecture.composition_root` | string | R | yes | `null` | relative path | `crates/service/Cargo.toml` exists → `'crates/service'` | | `clean-architecture-llm`, `configuration-management`, C9 |
| `architecture.layers` | list of string | R | no (may be `[]`) | `[]` | `^[a-z][a-z0-9-]*$` items | `[[layer]].name` of `architecture.toml`, file order | | `architecture-boundary-fixer`, `implementing-ddd-architecture`, `dependency-policy` |
| `architecture.bounded_contexts` | list of string | R | no (may be `[]`) | `[]` | `^[a-z0-9-]+/[a-z0-9-]+$` items | `[workspace].members` entries `crates/<g>/<c>/{domain,application,infrastructure}` with `<g>` ≠ `shared`, de-duplicated, member order (includes `internal/health-check`) | | informational: `/rs-sdlc-plan` story-1 rule, `architecture-model-sync`, `bounded-context-scaffolding`; never read by `validate_context_name` |
| `architecture.shared_crates` | list of string | R | no (may be `[]`) | `[]` | relative paths | `[workspace].members` entries under `crates/shared/`, member order | | `code-organization`, `implementing-ddd-architecture` |
| `service.port` | int | R | no | `8081` | 1–65535 | `.env`, first line matching `^APP_PORT=([0-9]+)$` (`.env.local` is never read) | | `/rs-sdlc-qa`, `merge-settings.sh --with-qa-network`, `security-auditor` |
| `service.base_url` | string | R | no | `'http://localhost:<port>'` | `^http://(localhost\|127\.0\.0\.1):[0-9]+$` | derived from `service.port` | | `qa-manual-tester`, `security-auditor`, schemathesis lane |
| `service.liveness_path` | string | R | no | `'/ping'` | starts with `/` | constant (template route) | | `/rs-sdlc-qa`, `observability-instrumentation` |
| `service.readiness_path` | string | R | no | `'/api/health'` | starts with `/` | constant | | `/rs-sdlc-qa`, `observability-instrumentation` |
| `service.graphql_path` | string | R | yes | `'/api/graphql'` when `framework.graphql`, else `null` | starts with `/` | derived | | `/rs-sdlc-qa` |
| `service.docs_path` | string | R | yes | `'/api/docs'` when `framework.openapi`, else `null` | starts with `/` | derived | | `/rs-sdlc-qa` |
| `service.openapi_snapshot` | string | R | yes | `null` | relative path | `.github/openapi-spec/spec.yaml` exists | | `/rs-sdlc-qa` probe set, `api-contract-development` |
| `service.graphql_snapshot` | string | R | yes | `null` | relative path | `.github/graphql-spec/spec` exists | | `/rs-sdlc-qa`, `api-contract-development` |
| `ci.provider` | enum | R | yes | `null` | `github-actions` | at least one `.github/workflows/*.yml` or `*.yaml` | | `/rs-sdlc-finish-pr` (D8), `ci-fixer` |
| `ci.workflows` | list of string | R | no (may be `[]`) | `[]` | file stems | `.github/workflows/*.y{a,}ml` stems, sorted with `LC_ALL=C` | | `ci-fixer`, `verification-workflow` |
| `ci.required_checks` | list of string | R | no (may be `[]`) | `[]` | GitHub check names | "Check name" cell of every row whose "Required" cell is `yes` in the job tables under "Required status checks" of `docs/repository-settings.md`, then `docs/repository-settings-service.md`; union, document order, de-duplicated | | `pr-state.sh` default, `/rs-sdlc-finish-pr`, `ci-fixer` |
| `ci.human_gated` | list of string | R | no (may be `[]`) | `[]` | ⊆ `ci.required_checks` | "Labels to create" table: job ids from "without it the job `<j>` fails" and "without it the jobs `<a>` and `<b>` fail", mapped to their "Check name" through the job tables of both documents; an unmapped job id is dropped with `WARN:` on stderr | | `pr-state.sh --human-gated-checks` default, `/rs-sdlc-finish-pr`, `ci-fixer` |
| `ci.base_ref` | string | R | no | `'origin/<default_branch>'` | `^[A-Za-z0-9._/-]+$` | derived from `project.default_branch` | | `/rs-sdlc-review` (diff, Q10, Q14 `base_ref=`), `ai-review-loop.sh`, `fr-nfr-gate.sh`, `code-review` |
| `review.coderabbit` | bool | R | no | `false` | — | `.coderabbit.yaml` exists | | `/rs-sdlc-finish-pr` (D7), `pr-comment-resolver` |
| `review.reviewers` | list of enum | R | no (may be `[]`) | `[coderabbit]` when `.coderabbit.yaml` exists, else `[]` | items ∈ `coderabbit` `cubic` `qodo` `qlty` `sonarcloud`, no duplicates | detection | preserve | `pr-state.sh`, `request-ai-reviews.sh`, `/rs-sdlc-finish-pr` |
| `review.ai_review_agents` | list of string | R | no (non-empty) | `[claude]` | items `^[a-z][a-z0-9-]*$`; only `claude` runs, others warn and skip | constant | preserve | `ai-review-loop.sh` |
| `review.request_changes_blocking` | bool | R | no | `false` | — | `reviews.request_changes_workflow: true` in `.coderabbit.yaml` (YAML read) | | `pr-comment-resolver`, `/rs-sdlc-finish-pr` |
| `capabilities.template_derived` | bool | R | no | `false` | — | all of `rust-toolchain.toml`, `architecture.toml`, `protected-config.toml`, `xtask/Cargo.toml`, `make/gates.mk`, `crates/service/Cargo.toml`, `workspace.dsl` exist and the Makefile's `CI_PREFLIGHT_TARGETS` starts with `validate-configuration` | | `setup-preflight.sh`, commands (D20) |
| `capabilities.run_in_container` | bool | R | no | `false` | — | `--run-in-container true\|false` > existing profile value > (`docker info` exits 0 and `cargo` is not on `PATH`) | preserve (flag wins) | every command that runs `make`, `git commit`, `git push` (FR-1); `verification-workflow` |
| `capabilities.structurizr` | bool | R | no | `false` | — | `workspace.dsl` exists and `make.validate_architecture_model` is mapped | | `architecture-model-sync` (skip path), review Q6 |
| `capabilities.load_testing` | bool | R | no | `false` | — | `tests/Load/` is a directory and `make.smoke_load_tests` is mapped | | `load-testing`, `testing-workflow` |
| `capabilities.mutation_testing` | bool | R | no | `false` | — | `make.mutation_tests_diff` is mapped | | review Q10, `testing-workflow` |
| `capabilities.dynamic_security_testing` | bool | R | no | `false` | — | never detected (opt-in by hand) | preserve | `/rs-sdlc-qa` schemathesis lane, `security-auditor` dynamic probes, `security-audit` |
| `capabilities.publish_pr_comments` | bool | R | no | `true` when `ci.provider` and `project.repo` are non-null, else `false` | — | derived | preserve | `post-review-findings.sh`, `bmad-fr-nfr-review-gate`, `code-review` |
| `capabilities.protected_config` | bool | R | no | `false` | — | `protected-config.toml` exists | | agents' protected-change rule, `dependency-policy`, `architecture-boundary-fixer` |
| `capabilities.template_sync` | bool | R | no | `false` | — | `template-sync-app.yml` or `template-sync-pat.yml` exists | | `/rs-sdlc-setup` (J6 hint), `service-scaffolding` |

### `make.*` map (55 keys, all R, all nullable)

Key = template target with `-` → `_` (PA-2); value = the target name when a rule matching `^<target>:.*##[[:space:]]` exists in `Makefile` or `make/*.mk` (incl. `make/service.mk`), else `null`. The four `SUBST` keys are `null` unless the service defines a target with that exact name; `null` routes to the bundled script. Columns: **Gate** = template gate id; **Class** = `STAGE` (aggregate stage), `GATE`, `LIFE` (lifecycle), `DEV` (DB-free, parallel-safe), `DB` (needs the compose database, serialized), `SCAF` (scaffolding/codegen), `READ` (foreground read), `SUBST`; **Dk** = needs Docker in host mode (`H` HOST target, `D` database through `ensure-deps`; in container mode every target needs the `app` container); **FG** = foreground allowlist (everything else runs backgrounded, ADR-13).

| Key | Target | Gate | Class | Dk | FG | Plugin use |
| --- | --- | --- | --- | --- | --- | --- |
| `make.ci` | `ci` | — | STAGE | H | | never invoked (FR-1); documented in `verification-workflow` |
| `make.ci_list` | `ci-list` | — | READ | | yes | setup/review read the gate order; `verification-workflow`, `quality-standards` |
| `make.ci_preflight` | `ci-preflight` | G25,G31,G9,G23,G24,G27 | STAGE | H | | new-context C12; `verification-workflow` |
| `make.ci_static_analysis` | `ci-static-analysis` | G1,G5,G29,G2,G3,G4,G7,G8,G6,G26 | STAGE | | | new-context C12 |
| `make.ci_tests` | `ci-tests` | G30,G11–G14 | STAGE | D | | new-context C12 |
| `make.ci_contracts` | `ci-contracts` | G17–G20 | STAGE | H | | new-context C12 |
| `make.ci_mutation` | `ci-mutation` | G15 | STAGE | D | | new-context C12 |
| `make.ci_delivery` | `ci-delivery` | G10,G21,G22 | STAGE | H | | new-context C12 (Docker reachable only) |
| `make.ci_cli` | `ci-cli` | G16 | STAGE | H | | never run by the plugin (new-context skips it) |
| `make.doctor` | `doctor` | — | LIFE | | yes | new-service S7; `make doctor` output in D2/D25 escalations |
| `make.bootstrap` | `bootstrap` | — | LIFE | H | | new-service S8 |
| `make.install_hooks` | `install-hooks` | — | LIFE | | yes | setup step 7, implement step 1 |
| `make.bmalph_setup` | `bmalph-setup` | — | LIFE | | | setup step 2 |
| `make.start` | `start` | — | LIFE | H | | QA boot, container precondition (FR-1, D25) |
| `make.format` | `format` | — | DEV | | | `rust-implementer`, workflow publish step |
| `make.format_check` | `format-check` | G1 | GATE | | | review Q1 |
| `make.lint_code` | `lint-code` | — | DEV | | | parallel implementers |
| `make.static_analysis` | `static-analysis` | G2 | GATE | | | review Q2 |
| `make.complexity` | `complexity` | G3 | GATE/DEV | | | review Q3; parallel implementers |
| `make.architecture` | `architecture` | G4 | GATE/DEV | | | review Q4; parallel implementers |
| `make.check_crate_isolation` | `check-crate-isolation` | G29 | GATE | | | review Q5 |
| `make.validate_architecture_model` | `validate-architecture-model` | G27 | GATE | H | | review Q6; C2 |
| `make.check_security` | `check-security` | G7 | GATE | | | review Q7; `security-auditor` static lane; null → built-in static lane (D1) |
| `make.unused_dependencies` | `unused-dependencies` | G8 | GATE | | | review Q8; C3 |
| `make.docs_check` | `docs-check` | G26 | GATE | | | review Q15; setup step 8; C11 |
| `make.validate_invariants` | `validate-invariants` | G31 | GATE | | | `documentation-sync`, `quality-standards` |
| `make.validate_configuration` | `validate-configuration` | G25 | GATE | | | new-context closing step; `security-auditor` evidence |
| `make.secrets_scan` | `secrets-scan` | G9 | GATE | H | | `security-auditor` lane |
| `make.unit_tests` | `unit-tests` | — | DEV | | | parallel implementers (pre-push hook runs it too) |
| `make.integration_tests` | `integration-tests` | — | DB | D | | serialized verify step |
| `make.tests_with_coverage` | `tests-with-coverage` | G11,G12,G14 | GATE/DB | D | | review Q9; implement post-loop |
| `make.e2e_tests` | `e2e-tests` | G13 | GATE/DB | D | | serialized verify step; C9, C10 |
| `make.mutation_tests_diff` | `mutation-tests-diff` | G15 | GATE/DB | D | | review Q10 (PA-13 run rule) |
| `make.setup_test_db` | `setup-test-db` | — | DB | D | | before the raw nextest call; serialized verify |
| `make.create_migration` | `create-migration` | — | SCAF | | | C8 (`make create-migration name=<snake_case>`) |
| `make.migrate` | `migrate` | — | DB | D | | QA pre-probe; C8 |
| `make.migrate_rollback` | `migrate-rollback` | — | DB | D | | C8 once; template `ask` rule → headless `not run (ask rule)` (D13) |
| `make.sqlx_prepare` | `sqlx-prepare` | — | SCAF/DB | D | | serialized verify; C8 |
| `make.validate_sqlx_metadata` | `validate-sqlx-metadata` | G30 | GATE/DB | D | | review Q11 |
| `make.generate_openapi_spec` | `generate-openapi-spec` | — | SCAF | | | new-service S10; C10; implementer co-change |
| `make.generate_graphql_spec` | `generate-graphql-spec` | — | SCAF | | | C10; implementer co-change |
| `make.validate_contract_snapshots` | `validate-contract-snapshots` | G17 | GATE | | | review Q12 |
| `make.validate_openapi_spec` | `validate-openapi-spec` | G18 | GATE | H | | review Q13 |
| `make.openapi_diff` | `openapi-diff` | G19 | GATE | H | | review Q14 |
| `make.graphql_diff` | `graphql-diff` | G20 | GATE | H | | review Q14 |
| `make.schemathesis_validate` | `schemathesis-validate` | G21 | GATE | H | | QA optional lane (`capabilities.dynamic_security_testing`) |
| `make.image_scan` | `image-scan` | G10 | GATE | H | | `security-auditor` image lane |
| `make.smoke_load_tests` | `smoke-load-tests` | G22 | GATE | H | | review records `not run (deferred to PR CI)`; `load-testing` |
| `make.load_tests` | `load-tests` | — | LIFE | H | | `load-testing` guidance only; never run by a command |
| `make.new_context` | `new-context` | — | SCAF | | | new-context C1 |
| `make.check_commit_message` | `check-commit-message` | G28 | READ | | yes | FR-2 pre-validation |
| `make.ai_review_loop` | — | — | SUBST | | | null → `scripts/ai-review-loop.sh` |
| `make.pr_comments` | — | — | SUBST | | | null → `scripts/get-pr-comments.sh` |
| `make.fr_nfr_gate` | — | — | SUBST | | | null → `scripts/fr-nfr-gate.sh` |
| `make.post_review_findings` | — | — | SUBST | | | null → `scripts/post-review-findings.sh` |

### Quality bars (12 keys, all R, int, not nullable)

Rule for every row: the review row is PASS when the target exits 0 **and** the measured value is within the bound; a floor key's legal values are exactly 100 and a ceiling key's exactly 0, because the template's gates already sit at the extremes (ADR-2, ADR-7). Measured values are evidence in the targets-run list; where the output cannot be parsed the measured value is reported as `≥ 1 (exit <n>)` and the row fails.

| Key | Default | Direction | Derived from (protected source) | Gate target | Measured by | Enforced in |
| --- | --- | --- | --- | --- | --- | --- |
| `quality.coverage_lines` | 100 | raise-only floor | `make/gates.mk` `COVERAGE_GATE_CMD … --fail-under-lines 100` | `make.tests_with_coverage` | `target/coverage/lcov.info`: PASS iff `100 × ΣLH ≥ floor × ΣLF` (integer arithmetic) | review Q9, implement post-loop |
| `quality.coverage_functions` | 100 | raise-only floor | `COVERAGE_GATE_CMD … --fail-under-functions 100` | `make.tests_with_coverage` | `100 × ΣFNH ≥ floor × ΣFNF` | review Q9 |
| `quality.max_surviving_mutants` | 0 | lower-only ceiling | `MUTANTS_CMD`, `.cargo/mutants.toml`, cargo-mutants exit 2 (missed) / 3 (timeout) | `make.mutation_tests_diff` | lines of `mutants.out/missed.txt` + `mutants.out/timeout.txt` (missing file = 0) | review Q10 |
| `quality.max_clippy_findings` | 0 | lower-only ceiling | `LINT_PROD_CMD`, `LINT_ALL_CMD` (`-D warnings`), `LINT_RUSTDOC_CMD` (`RUSTDOCFLAGS="-D warnings"`), `Cargo.toml [workspace.lints]` | `make.static_analysis` | log lines matching `^(error\|warning)(\[[A-Za-z0-9_]+\])?:[[:space:]]` minus `^error: (could not compile\|aborting due to)` and `generated [0-9]+ (warning\|error)` summaries | review Q2 |
| `quality.max_complexity_violations` | 0 | lower-only ceiling | `clippy.toml` `cognitive-complexity-threshold = 8`, `too-many-lines-threshold = 50`, `too-many-arguments-threshold = 5`, `excessive-nesting-threshold = 5`; `COMPLEXITY_CMD` | `make.complexity` | diagnostics naming `clippy::cognitive_complexity`, `clippy::too_many_lines`, `clippy::excessive_nesting`, `clippy::too_many_arguments` (one per `^error:[[:space:]]` line) | review Q3 (limits quoted from `clippy.toml` in the row) |
| `quality.max_architecture_violations` | 0 | lower-only ceiling | `ARCH_CMD` + `architecture.toml`; `HACK_CMD` | `make.architecture`, `make.check_crate_isolation` | `<n>` of `architecture: FAILED. <n> violation(s) …` (0 on exit 0); crate isolation: `error: could not compile` lines, minimum 1 on non-zero exit | review Q4, Q5 |
| `quality.max_unused_dependencies` | 0 | lower-only ceiling | `SHEAR_CMD` (`cargo shear --locked`) | `make.unused_dependencies` | exit-based | review Q8 |
| `quality.max_dependency_policy_findings` | 0 | lower-only ceiling | `DENY_CMD` + `deny.toml` | `make.check_security` | `^error\[` lines in the log | review Q7, `security-auditor` |
| `quality.max_spectral_findings` | 0 | lower-only ceiling | `SPECTRAL_FLAGS = --fail-severity=hint` + `.spectral.yaml` | `make.validate_openapi_spec` | exit-based | review Q13 |
| `quality.max_unapproved_breaking_changes` | 0 | lower-only ceiling | `OASDIFF_FLAGS = --fail-on ERR`; `scripts/graphql-diff.sh` | `make.openapi_diff`, `make.graphql_diff` | exit-based, the two targets summed | review Q14 |
| `quality.max_image_vulnerabilities_high_critical` | 0 | lower-only ceiling | `TRIVY_FLAGS = --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore` | `make.image_scan` | exit-based | `security-auditor` image lane; finish-pr via check `Production-image scan` |
| `quality.max_smoke_budget_breaches` | 0 | lower-only ceiling | `tests/Load/config.json.dist` `/endpoints/health/smoke/threshold` (protected JSON value), `thresholdsBuilder.js` | `make.smoke_load_tests` | exit-based | finish-pr via check `Smoke load tests`; review records `not run (deferred to PR CI)` |

`generate-profile.sh` always emits these defaults. When the repository's own gate is looser than the template value it keeps the default and prints on stderr `[rust-sdlc][WARN] <file> <setting> is looser than the template value <v>; the profile keeps <default>` for: `COVERAGE_GATE_CMD` floors in `make/gates.mk`, the four `clippy.toml` thresholds, `SPECTRAL_FLAGS`, `OASDIFF_FLAGS`, `TRIVY_FLAGS` severities.

### Validation rules (`validate-profile.sh`, checked in this order, all violations reported)

| # | Rule | Violation line |
| --- | --- | --- |
| V1 | file exists and is a regular file | (no line) `[rust-sdlc][ERROR] profile not found: <path> (run /rs-sdlc-setup)`, exit 1 |
| V2 | parses as YAML with a mapping at the root | `VIOLATION: <path>: not parseable YAML (<first error line>)`, exit 1, no traceback |
| V3 | `schema_version` is the integer 1 | `VIOLATION: schema_version: must be 1 (<value>)` |
| V4 | every R key present; no unknown group or key | `VIOLATION: <key>: missing` / `VIOLATION: <key>: unknown key` |
| V5 | non-nullable keys are not `null` | `VIOLATION: <key>: must not be null` |
| V6 | type per table (YAML int, bool, string, list; a quoted `'100'` is not an int) | `VIOLATION: <key>: expected <type> (<value>)` |
| V7 | enum membership | `VIOLATION: <key>: not one of <values> (<value>)` |
| V8 | formats (regexes above; `service.port` 1–65535; list items) | `VIOLATION: <key>: invalid format (<value>)` |
| V9 | `ci.human_gated` ⊆ `ci.required_checks`; `review.reviewers` without duplicates; `review.ai_review_agents` non-empty | `VIOLATION: ci.human_gated: '<name>' is not in ci.required_checks` |
| V10 | every non-null `make.*` value matches `^[a-zA-Z0-9_-]+$` | `VIOLATION: make.<k>: invalid target name (<value>)` |
| V11 | quality bounds with wrap-safe digit compare | `VIOLATION: quality.<k>: below the floor (<value> vs bound 100)` / `above the maximum (<value> vs bound 100)` / `above the ceiling (<value> vs bound 0)` |

Output ends with `VALID: <path>` (exit 0) or `INVALID: <path>: <n> violation(s)` (exit 1). Usage errors exit 2.

### Annotated example (the generator output for the template checkout at `3e0bd3e`, comments added)

The block below is yamllint-clean with the template's `.yamllint.yml` and Prettier-clean with its `.prettierrc.yml` **[verified]**. The generator emits the same keys and values without the trailing comments; `docs/profile-schema.md` carries this example verbatim.

```yaml # profile-example
# Project profile of the rust-backend-sdlc plugin (schema_version 1).
# Written by generate-profile.sh; re-detect with /rs-sdlc-setup --refresh.
schema_version: 1 # required; only 1 is valid
project:
  name: 'rust-service-template' # checkout directory = Compose project name
  repo: 'VilnaCRM-Org/rust-service-template' # owner/name of a github.com origin, or null
  default_branch: 'main'
  description: 'Rust Service Template' # [workspace.package].description, or null
rust:
  toolchain: '1.99.1' # rust-toolchain.toml [toolchain].channel
  edition: '2024'
  msrv: '1.99.1' # [workspace.package].rust-version
template:
  repository: 'VilnaCRM-Org/rust-service-template' # TEMPLATE_REPOSITORY of a sync workflow
  sync_flavour: both # app | pat | both | none
  source_commit: null # from an import commit subject, when present
framework:
  http: axum # axum | null
  openapi: true
  graphql: true
persistence:
  engine: postgresql # postgresql | null
  migrations_dir: 'migrations'
  offline_metadata: true # .sqlx/ exists
architecture:
  crates_root: 'crates'
  composition_root: 'crates/service'
  layers:
    - 'domain'
    - 'application'
    - 'infrastructure'
    - 'composition-root'
    - 'test-support'
    - 'e2e'
    - 'tooling'
  bounded_contexts: # informational; context names are validated against the live tree
    - 'company-subdomain/some-module'
    - 'internal/health-check'
  shared_crates:
    - 'crates/shared/application'
    - 'crates/shared/domain'
    - 'crates/shared/infrastructure'
service:
  port: 8081 # .env APP_PORT
  base_url: 'http://localhost:8081'
  liveness_path: '/ping'
  readiness_path: '/api/health'
  graphql_path: '/api/graphql'
  docs_path: '/api/docs'
  openapi_snapshot: '.github/openapi-spec/spec.yaml'
  graphql_snapshot: '.github/graphql-spec/spec'
make: # template target per key; null = capability absent (never omitted)
  ci: ci
  ci_list: ci-list
  ci_preflight: ci-preflight
  ci_static_analysis: ci-static-analysis
  ci_tests: ci-tests
  ci_contracts: ci-contracts
  ci_mutation: ci-mutation
  ci_delivery: ci-delivery
  ci_cli: ci-cli
  doctor: doctor
  bootstrap: bootstrap
  install_hooks: install-hooks
  bmalph_setup: bmalph-setup
  start: start
  format: format
  format_check: format-check
  lint_code: lint-code
  static_analysis: static-analysis
  complexity: complexity
  architecture: architecture
  check_crate_isolation: check-crate-isolation
  validate_architecture_model: validate-architecture-model
  check_security: check-security
  unused_dependencies: unused-dependencies
  docs_check: docs-check
  validate_invariants: validate-invariants
  validate_configuration: validate-configuration
  secrets_scan: secrets-scan
  unit_tests: unit-tests
  integration_tests: integration-tests
  tests_with_coverage: tests-with-coverage
  e2e_tests: e2e-tests
  mutation_tests_diff: mutation-tests-diff
  setup_test_db: setup-test-db
  create_migration: create-migration
  migrate: migrate
  migrate_rollback: migrate-rollback
  sqlx_prepare: sqlx-prepare
  validate_sqlx_metadata: validate-sqlx-metadata
  generate_openapi_spec: generate-openapi-spec
  generate_graphql_spec: generate-graphql-spec
  validate_contract_snapshots: validate-contract-snapshots
  validate_openapi_spec: validate-openapi-spec
  openapi_diff: openapi-diff
  graphql_diff: graphql-diff
  schemathesis_validate: schemathesis-validate
  image_scan: image-scan
  smoke_load_tests: smoke-load-tests
  load_tests: load-tests
  new_context: new-context
  check_commit_message: check-commit-message
  ai_review_loop: null # null = the plugin's bundled scripts/ai-review-loop.sh
  pr_comments: null # null = scripts/get-pr-comments.sh
  fr_nfr_gate: null # null = scripts/fr-nfr-gate.sh
  post_review_findings: null # null = scripts/post-review-findings.sh
quality: # tighten-only: floors may not go below, ceilings may not go above these values
  coverage_lines: 100 # floor
  coverage_functions: 100 # floor
  max_surviving_mutants: 0 # ceiling
  max_clippy_findings: 0
  max_complexity_violations: 0 # limits are read from clippy.toml at review time
  max_architecture_violations: 0
  max_unused_dependencies: 0
  max_dependency_policy_findings: 0
  max_spectral_findings: 0
  max_unapproved_breaking_changes: 0
  max_image_vulnerabilities_high_critical: 0
  max_smoke_budget_breaches: 0
ci:
  provider: github-actions # github-actions | null
  workflows:
    - 'change-control'
    - 'contracts'
    - 'load-tests'
    - 'quality'
    - 'release'
    - 'repository'
    - 'scheduled'
    - 'security'
    - 'template-sync-app'
    - 'template-sync-pat'
    - 'tests'
  required_checks: # GitHub check names from docs/repository-settings.md, Required = yes
    - 'Changes (Quality)'
    - 'Formatting check'
    - 'Static analysis'
    - 'Complexity limits'
    - 'Architecture boundaries'
    - 'Manifest and lock validation'
    - 'Crate isolation'
    - 'Persistence query metadata'
    - 'Configuration check'
    - 'Dependency policy'
    - 'Unused dependencies'
    - 'Changes (Tests)'
    - 'Tests and coverage'
    - 'End-to-end tests'
    - 'Mutation tests'
    - 'Makefile tests (Bats)'
    - 'Changes (Contracts)'
    - 'Contract snapshots'
    - 'OpenAPI lint'
    - 'Schemathesis'
    - 'Changes (Change control)'
    - 'Pull-request title'
    - 'Protected configuration'
    - 'OpenAPI breaking changes'
    - 'GraphQL breaking changes'
    - 'Changes (Load tests)'
    - 'Smoke load tests'
    - 'Load-script lint'
    - 'Changes (Security)'
    - 'Secrets scan'
    - 'Production-image scan'
    - 'Changes (Repository)'
    - 'Repository lint'
    - 'Repository invariants'
    - 'Documentation drift'
    - 'Architecture model'
  human_gated: # subset of required_checks that pass only with an approval label
    - 'Protected configuration'
    - 'OpenAPI breaking changes'
    - 'GraphQL breaking changes'
  base_ref: 'origin/main'
review:
  coderabbit: true # .coderabbit.yaml exists
  reviewers:
    - coderabbit
  ai_review_agents:
    - claude
  request_changes_blocking: true # reviews.request_changes_workflow in .coderabbit.yaml
capabilities:
  template_derived: true
  run_in_container: false # preserved on --refresh; --exec host|container sets it
  structurizr: true
  load_testing: true
  mutation_testing: true
  dynamic_security_testing: false # opt-in; preserved on --refresh
  publish_pr_comments: true # preserved on --refresh
  protected_config: true
  template_sync: true
```

## Script Contracts

### Shared contract

- Skeleton, `--help`, argument parsing, safe writes, banned constructs: see "Script conventions".
- Logging: `log_info`, `log_warn`, `log_error` write `[rust-sdlc][INFO|WARN|ERROR] <msg>` to **stderr**; handles and data go to stdout (amends php, where `log_info` wrote stdout).
- Exit codes: ADR-23. Every script's header lists its exit codes; `component-counts.bats` checks the header and `--help` exit 0 for all 13.
- Tools: `bash`, `git`, coreutils, `python3`; optional `jq` (python3 fallback), mikefarah `yq` (PyYAML fallback); `gh`, `claude`, `tar` only where the table says so. No script calls `cargo`, `make`, `docker` or the network except as listed.

| Environment variable | Read by | Default | Meaning |
| --- | --- | --- | --- |
| `CLAUDE_PLUGIN_ROOT` | `resolve_plugin_root` | set by Claude Code | plugin root; else `$(dirname BASH_SOURCE)/../..` |
| `SDLC_FORCE_PYTHON_YAML` | YAML helpers | unset | `1` forces python3 + PyYAML (shared name) |
| `SDLC_LEDGER_DIR` | `post-review-findings.sh`, `/rs-sdlc-review` | `target/rust-sdlc/review-ledgers` | ledger directory (shared name) |
| `SDLC_NOW_EPOCH` | `pr-state.sh`, `request-ai-reviews.sh`, `now_epoch` | current time | fixed clock for tests (shared name) |
| `FR_NFR_STATUS_RETRY_DELAY` | `fr-nfr-gate.sh` | `5` | seconds between the 3 status-post attempts (react name kept for parity) |
| `RUST_SDLC_TEMPLATE_REPO` | `new-service.sh` | unset | template slug override (ADR-12) |
| `RUST_SDLC_CONFIG_FILE` | `new-service.sh` | unset | alternate `new-service.defaults.json` |
| `RUST_SDLC_BASH_VERSION` | `lib/common.sh` | unset | test hook: simulated `major.minor` for the bash floor check |

### `scripts/lib/common.sh`

Sourced by every script; first executable lines check the bash floor (`RUST_SDLC_BASH_VERSION` or `BASH_VERSINFO` below 4.4 → `[rust-sdlc][ERROR] bash <v> is too old: install Bash 4.4 or newer`, exit 1) before any function definition, so bash 3.2 fails cleanly. Executed directly: the ADR-15 dispatcher.

| Function | Signature | Behaviour and return |
| --- | --- | --- |
| `log_info` / `log_warn` / `log_error` | `MSG…` | stderr, prefix `[rust-sdlc][LEVEL]` |
| `die` / `die_usage` | `MSG…` | `log_error`; exit 1 / exit 2 (`usage: …` appended from the caller's header) |
| `print_usage` | `SCRIPT` | prints the header comment block; used by `--help` |
| `need_value` | `FLAG VALUE` | `die_usage "<flag> needs a value"` when VALUE is empty or starts with `--` |
| `lower` | `S` | lower-case via `tr` |
| `strip_zeros` / `num_gt` / `num_lt` / `num_add` / `is_uint` | `A [B]` | digit-string arithmetic, wrap-safe; `is_uint` = `^[0-9]+$` |
| `now_epoch` / `utc_now` / `utc_stamp` | — | `${SDLC_NOW_EPOCH:-$(date +%s)}`; `date -u +%Y-%m-%dT%H:%M:%SZ`; `date -u +%Y%m%dT%H%M%SZ` |
| `have_cmd` | `NAME` | `command -v` |
| `have_yq` | — | mikefarah probe: false when `SDLC_FORCE_PYTHON_YAML=1`; true only when `printf 'a: [1]\n' \| yq '.a \| type'` prints exactly `!!seq`; verdict cached in `_SDLC_YQ_OK` |
| `have_pyyaml` / `require_yaml_toolchain` | — | `python3 -c 'import yaml'`; die `no YAML toolchain: install mikefarah yq v4, or python3 with PyYAML` |
| `have_jq` | — | `command -v jq` |
| `yaml_parses` | `FILE` | 0 when parseable; dies when FILE is missing |
| `yaml_get` | `FILE KEY` | dotted key; `null`/absent → empty; booleans `true`/`false`; lists one item per line; yq form `.a.b \| select(. != null)` |
| `yaml_get_list` / `yaml_is_list` / `yaml_has` / `yaml_type` | `FILE KEY` | list items; 0 when a list; 0 when the key exists even if `null`; prints `null bool int str list map absent` |
| `yaml_to_json` | `FILE` | whole document as JSON on stdout (yq `-o=json '.'` or python3 + PyYAML); exit 1 with the parser's first error line when unparseable |
| `yaml_squote` | `VALUE` | `'…'` with `'` doubled, control characters stripped |
| `json_get` | `FILE\|- KEY` | dotted key via jq, else python3; identical output (parity-tested) |
| `toml_get` / `toml_get_list` / `toml_has` | `FILE KEY` | python3 `tomllib`; dotted keys (`workspace.package.description`, `workspace.dependencies.sqlx.features`); arrays one item per line; dies `python3 3.11+ with tomllib is required` |
| `profile_path` / `profile_get` / `profile_require` | `[DIR]` / `FILE KEY [DEFAULT]` / `FILE KEY` | `${DIR:-$PWD}/.claude/rust-sdlc.yml`; value or default (`false` is a value); die `profile: required key '<k>' missing or null in <file>` |
| `resolve_plugin_root` | — | `CLAUDE_PLUGIN_ROOT` when it is a directory (else die), else the library's `../..` |
| `resolve_repo_slug` | `[DIR]` | github.com origin parse (https, `git@github.com:`, `ssh://`), `.git` stripped, `is_slug`; else `gh repo view --json nameWithOwner --jq .nameWithOwner`; else return 1, no output |
| `default_branch` | `[DIR]` | `refs/remotes/origin/HEAD` target → `main` → `master` (local or `origin/` ref) → `main` |
| `is_kebab` | `S [MAX]` | `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`, length ≤ MAX (default 50) |
| `is_slug` / `is_semver` | `S` | `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`; `^(0\|[1-9][0-9]*)\.(0\|[1-9][0-9]*)\.(0\|[1-9][0-9]*)$` |
| `is_commit_subject` | `S` | single line matching `^(feat\|fix\|refactor\|build\|chore\|ci\|docs\|style\|perf\|test)\(#[1-9][0-9]*\): [^[:space:]].*$` (tighter than the template's: non-empty subject, no `#0`) |
| `derive_issue_number` | `[--handle N] [--title T] [--branch B] [--body TEXT]` | first source that yields N: handle `^[1-9][0-9]*$`; title `^[a-z]+\(#([0-9]+)\):`; branch `^[a-z]+/([0-9]+)-`; body `(^\|[^A-Za-z])Closes #([0-9]+)`; prints N or returns 1 |
| `validate_context_name` | `GROUP CONTEXT [ROOT]` | the four FR-14 rules over the live tree (`toml_get_list` of `[workspace].members`, each member's `package.name`, `crates/<c>` and `crates/*/<c>` directories); 0, or 1 with one line `REFUSED: <rule> <detail>` where rule ∈ `name-format` `reserved-context` `context-exists` `member-exists` |
| `resume_point` | `[--cache FILE]` | reads the state table from stdin (comment body) or the cache JSON; applies PA-7 with `git merge-base --is-ancestor` and `git rev-parse HEAD`; prints `DONE_STAGE: <stage> <sha7> <iteration>` per valid stage, then `RESUME_STAGE: <stage>`, then `COUNTERS: issue=<n>,plan=<n>,implement=<n>,review=<n>,qa=<n>,finish-pr=<n>`; never calls `gh`; malformed input → exit 1 |
| `state_cache_update` | `FILE STAGE RESULT HEAD_SHA ITERATION` | creates or updates the cache JSON atomically (`{"schema_version":1,"issue":N,"slug":"…","stages":[…]}`); validates stage ∈ `issue plan implement review qa finish-pr`, result ∈ `PASS IN_PROGRESS ESCALATED`, 40-hex sha, uint iteration |
| `state_comment_body` | `FILE` | prints `<!-- rust-sdlc-state -->`, a blank line and the 5-column table from the cache, redacted |
| `ledger_write` | `LENS ITERATION HEAD_SHA [DIR]` | reads the lens's findings array (JSON) on stdin, validates it against ADR-16, writes `{schema_version: 1, lens, iteration, head_sha, findings}` atomically to `${DIR:-${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}}/<lens>.json`; exit 1 on invalid input |
| `redact` | stdin → stdout | masks AWS key ids (`AKIA[0-9A-Z]{16}`), JWTs, `gh[pousr]_[A-Za-z0-9]{36,}`, `github_pat_…`, `password\|passwd\|secret\|token\|apikey\|api_key` assignments, URL credentials `://user:pass@`, base64/hex runs ≥ 40 characters with mixed classes → `[REDACTED]` |
| `fence_safe` | stdin → stdout | neutralizes `<<<` and `>>>` in contributor text placed inside prompt fences |
| `safe_write_target` / `atomic_write` | `PATH ROOT` / `PATH` (content on stdin) | see "Script conventions" |
| `claude_is_error` / `claude_extract_result` | `JSON` | `.is_error == true`; `.result // empty` |
| `claude_run_once` / `claude_run_isolated` | `PROMPT` | ADR-8 argv; print `.result`; return 1 after the retry |
| `claude_supports_restricted` | — | `claude --help` lists `--restricted` |

Dispatcher names (ADR-15): `validate_context_name`, `resume_point`, `derive_issue_number`, `is_commit_subject`, `redact`, `state_cache_update`, `state_comment_body`, `ledger_write`.

### `scripts/setup-preflight.sh` (FR-10)

- **Usage** `setup-preflight.sh [--report]` (runs in `$PWD`). Default mode stops after the first `FAIL`; `--report` runs every check. Output lines `<STATUS>: <check-id>: <detail>[ — remediation: <text>]`, then `SUMMARY: pass=<n> warn=<n> fail=<n> info=<n>`. Exit 0 no `FAIL`, 1 any `FAIL`, 2 usage.
- **Checks, in order:** `git-repo` (inside a non-bare work tree, not inside `.git/`); `gh` (≥ 2.0); `gh-auth` (`gh auth status`); `claude` (≥ 2.1.248); `claude-restricted` (`claude_supports_restricted`); `bmalph` (≥ 2.11.0; absent with a `bmalph-setup` Makefile target, node ≥ 20 and npm → `WARN … will be installed by make bmalph-setup`; else `FAIL`); `bmalph-doctor` (only when `_bmad/` exists; else `INFO … deferred until make bmalph-setup`); `python3` (≥ 3.11 and `import tomllib`); `yaml-backend` (mikefarah yq v4, else PyYAML, else `FAIL`); `json-backend` (jq, else python3); `make` (`GNU Make` ≥ 4.0 from `make --version`); `bash` (≥ 4.4; below the floor the library has already exited 1, AC-10.1); `git` (≥ 2.30); `template-markers` (`WARN` listing missing A1 markers); `tracked-tree` (`INFO` listing `git status --porcelain --untracked-files=no`); `docker` (`INFO reachable|unreachable`); `cargo` (`INFO present|absent`, input to `capabilities.run_in_container`).
- **Calls:** `git`, `gh --version`, `gh auth status`, `claude --version`, `claude --help`, `bmalph --version`, `bmalph doctor`, `node --version`, `npm --version`, `python3`, `yq`, `jq`, `make --version`, `docker info`, `command -v cargo`. Writes nothing.

### `scripts/generate-profile.sh` (FR-6)

- **Usage** `generate-profile.sh [--refresh] [--stdout] [--run-in-container true|false] [TARGET_DIR]` (TARGET_DIR default `$PWD`).
- **Reads** (never `cargo`, `make`, `gh`, `.env.local`): `Cargo.toml`, `rust-toolchain.toml`, `architecture.toml`, `protected-config.toml`, `Makefile` and `make/*.mk`, `make/gates.mk`, `clippy.toml`, `.github/workflows/*.y{a,}ml`, `docs/repository-settings.md`, `docs/repository-settings-service.md`, `.coderabbit.yaml`, `.env`, `workspace.dsl`, `tests/Load/`, `.sqlx/`, `migrations/`, `.github/openapi-spec/spec.yaml`, `.github/graphql-spec/spec`, `git remote get-url origin`, `git log --format=%s`, the existing profile (preserve keys); probes `docker info` and `command -v cargo` only for `capabilities.run_in_container` detection.
- **Writes** `TARGET_DIR/.claude/rust-sdlc.yml` only (creates `.claude/` when missing); atomic via `mktemp .claude/.rust-sdlc.yml.XXXXXX` + `mv`; refuses a symlinked `.claude`, a symlinked or non-regular profile (exit 1).
- **Modes:** no profile → write, `WROTE: .claude/rust-sdlc.yml`; profile exists, no `--refresh` → compare with fresh detection: identical → `UNCHANGED: .claude/rust-sdlc.yml`; different → `DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)` followed by a unified diff (`--- .claude/rust-sdlc.yml`, `+++ detected`), file kept, exit 0; `--refresh` → write (preserve rules of ADR-24), `WROTE:` or `UNCHANGED:`; `--stdout` → print the YAML, write nothing.
- **Stderr:** `WARN:` lines for an unmapped human-gated job id, a looser repository gate (Quality bars), an unparseable source file (key falls back).
- **Exit** 0 success, 1 refusal or failure, 2 usage. Runs in ≤ 5 s on the fixture.

### `scripts/validate-profile.sh` (FR-7)

- **Usage** `validate-profile.sh [PROFILE_FILE]` (default `$PWD/.claude/rust-sdlc.yml`). Rules V1–V11, output and exit codes as in "Validation rules". The file is converted once with `yaml_to_json` (mikefarah `yq -o=json '.'` or python3 + PyYAML `json.dumps(yaml.safe_load(…))`), then every rule runs in python3 over the JSON (stdlib only), so YAML types survive (`'100'` stays a string) and both backends give byte-identical output (parity cases; fixtures avoid YAML-1.1-only scalars such as `yes`/`on`). Writes nothing.

### `scripts/inject-governance.sh` (FR-8)

- **Usage** `inject-governance.sh [--diff] [TARGET_DIR]`. Maintains the block of "Governance Block" in `CLAUDE.md` and `AGENTS.md`.
- **Algorithm** (php port): normalise CR for matching only; a marker line counts only outside fences (```` ``` ```` and `~~~`); the first well-ordered begin/end pair is replaced in place by the block; further pairs, orphan begins, orphan ends and inverted pairs are removed (`REPAIRED:`); when no valid pair remains the block is appended after exactly one blank line; a missing file is created holding only the block; the block is never placed between `<!-- verification:start -->` and `<!-- verification:end -->` (a pair found inside that region is removed and the block appended at the end); original line endings of the rest of the file are preserved; atomic write.
- **Stdout** per file: `CREATED: <file>` / `UPDATED: <file>` / `REPAIRED: <file> (<n> stray marker line(s) removed)` / `UNCHANGED: <file>`; `--diff` prints a unified diff per changed file and `WOULD: update <file>`, writes nothing.
- **Exit** 0, 1 (symlink, non-regular file, unreadable, write failure), 2 usage.

### `scripts/merge-settings.sh` (FR-9)

- **Usage** `merge-settings.sh [--print] [--with-qa-network] [--file local|shared] [TARGET_DIR]` (default `--file local`).
- **Reads** the target settings file, `protected-config.toml` (`files` array and `directories` prefixes, through `tomllib`), `.claude/rust-sdlc.yml` (`service.port`, only with `--with-qa-network`; missing profile → exit 1 `profile missing: run generate-profile.sh first`), `id -u`, `id -g`, `resolve_plugin_root`.
- **Writes** `.claude/settings.local.json` (local) or `.claude/settings.json` (shared). Shared is refused when `.claude/settings.json` is listed in `files` or below a listed directory: `REFUSED: .claude/settings.json is protected (protected-config.toml lists it); merged JSON follows`, the merged JSON on stdout, exit 1, file untouched.
- **Merge:** union into `permissions.allow` only (existing entries and order kept, new entries appended in the order of "Permissions Strategy", de-duplicated); `deny`, `ask`, `hooks`, `env`, `defaultMode` and all other keys untouched; output `json.dumps(obj, indent=2, ensure_ascii=False) + "\n"`; malformed existing JSON → exit 1, file unchanged; symlink refused.
- **Stdout:** `WROTE: <file> (+<n> entries)` / `UNCHANGED: <file>` / `--print` the merged JSON (writes nothing). Exit 0, 1, 2.

### `scripts/new-service.sh` (FR-12, FR-13)

- **Usage** `new-service.sh --name <n> [--description <text>] [--template <owner/repo> | --template-path <dir> | --in-place] [--owner <org>] [--visibility private|public] [--dest <dir>] [--version <x.y.z>] [--intro <text>] [--sync-flavour app|pat] [--keep-specs] [--phase source|customize|all] [--dry-run]`.
- **Validation (exit 2):** `--name` `is_kebab` ≤ 50; `--description` and `--intro` single line ≤ 200 characters without control characters; `--owner` `^[A-Za-z0-9][A-Za-z0-9-]{0,38}$`; `--version` `is_semver`; enums; two source flags; malformed config.
- **Defaults:** description = name; owner = `gh api user --jq .login` (GitHub mode; empty → exit 1 `pass --owner`); intro = description; version = `default_version`; visibility = `default_visibility`; dest = `.`; checkout = `<dest>/<name>` (`--in-place`: `$PWD`, with `NEXT: rename the checkout directory to <name> (it is the Compose project name)` when the basenames differ).
- **Mode:** GitHub = `--template`, no source flag (slug per ADR-12), or `--in-place` with a github.com `origin` and `gh auth status` OK; local = `--template-path`, or `--in-place` otherwise.
- **Phase `source`** (exact gh/git argv, asserted by the gh stub log): `gh api repos/<slug> --jq .is_template`; existence `gh repo view <owner>/<name> --json nameWithOwner --jq .nameWithOwner`; template flow `gh repo create <owner>/<name> --template <slug> --private|--public` (never `--clone`), poll `gh api 'repos/<owner>/<name>/commits?per_page=1' --jq length` up to `poll_attempts` × `poll_interval_seconds` (timeout → exit 1), `gh repo clone <owner>/<name> <checkout>`; clone-and-push `gh repo create <owner>/<name> --private|--public`, `gh repo clone <slug> <tmp> -- --depth 1`, `git -C <tmp> archive HEAD | tar -x -C <checkout>`, `git -C <checkout> init -b main`, `git -C <checkout> remote add origin https://github.com/<owner>/<name>.git`; path `git -C <dir> status --porcelain --untracked-files=no` must be empty (else `REFUSED: template checkout <dir> has uncommitted tracked changes`, exit 1), then the same archive import without a remote; in-place `SKIP: source (in place)`. Re-run: repository exists and the checkout's `origin` matches → `SKIP: source (exists)`; repository exists otherwise, or `<checkout>` exists non-empty and is not that clone → exit 1, no `gh repo create`.
- **Source handles:** `SOURCE_MODE: template|clone-and-push|path|in-place`, `REPO: <owner>/<name>` (GitHub mode), `CHECKOUT: <absolute path>`, `SOURCE: <slug>|local:<path>`, `SOURCE_SHA: <sha40>`, and for clone-and-push `IMPORT_PENDING: <slug>@<sha40>` + `NEXT: ask the template owner to enable Settings > Template repository`. The phase writes `<checkout>/target/rust-sdlc/new-service/source.json` (`{"schema_version":1,"mode":…,"source":…,"sha":…,"specs":[<bundle dirs of the source tree>]}`) once; an existing record is never overwritten.
- **Phase `customize`** (steps in order; each prints `DONE:`/`UNCHANGED:`/`SKIP:`/`NEXT:`; a failing step leaves its file untouched and exits 1):

| Step id | Action | Files |
| --- | --- | --- |
| `identity` | `description` and `repository` lines of `[workspace.package]` only (line edit inside that table; `repository = "https://github.com/<owner>/<name>"`; local mode without `--owner`: description only + `NEXT: set [workspace.package].repository once the GitHub repository exists`) | `Cargo.toml` |
| `version` | equal → `UNCHANGED: version <v>`; else `NEXT: scripts/set-version.sh <v>` (executed by the command at S9) | — |
| `bmalph-config` | `name` = name, `description` = description; other keys and order kept; `indent=2` + newline (Prettier-clean) | `bmalph/config.json` |
| `readme` | first H1 line → `# <description>`; in lines starting `[![`, the old slug (owner/name from the pre-edit `[workspace.package].repository`) → `<owner>/<name>`; the first paragraph between the badge block and the first H2 heading → the intro | `README.md` |
| `changelog` | replace the whole file with the cocogitto skeleton: `# Changelog`, the "All notable changes…" line, a blank line, `- - -`, a blank line, `Changelog generated by [cocogitto](https://github.com/cocogitto/cocogitto).`, newline | `CHANGELOG.md` |
| `specs` | delete the bundle directories listed in `source.json` that still exist; `--keep-specs` → `SKIP: specs (--keep-specs)`; none left → `UNCHANGED: specs` | `specs/` |
| `sync-flavour` | keep `template-sync-<f>.yml` + `TEMPLATE_SYNC_<F>.md`, delete the other pair; omitted flag → `SKIP: sync-flavour (undecided)` + `NEXT: re-run with --sync-flavour app\|pat` | `.github/workflows/`, `.github/` |
| `templatesyncignore` | append each deleted path once | `.templatesyncignore` |
| `docs-check-citations` | ADR-20 repair over `git ls-files '*.md'` minus `CHANGELOG.md` and `specs/**`; each rewritten span prints `DONE: docs-check citation <file>:<line>`; each edited file appended once to `.templatesyncignore`; nothing to do → `UNCHANGED: docs-check-citations` | cited Markdown files |

- **End:** `SUMMARY: done=<n> unchanged=<n> skip=<n> next=<n>`. `--dry-run`: only `WOULD:` lines and the summary; no mutating gh call, no write. Never commits, pushes, removes the example context or changes the licence. Exit 0, 1, 2.

### `scripts/stage-planning-artifacts.sh` (FR-17)

- **Usage** `stage-planning-artifacts.sh <specs-dir> [--dest <dir>] [--dry-run]` (dest default `_bmad-output/planning-artifacts`). Pre-checks, copies and refusals exactly as FR-17; `research.md` is staged as `technical-research.md`; `ux*.md` copied when present. Stdout `STAGED: <src> -> <dest>` per file, `REMOVED: <dest-file>` per stale file, `REFUSED: <reason>` on refusal; `--dry-run` prints `WOULD: stage <src> -> <dest>`. Exit 0 staged, 1 refused, 2 usage or environment (not a git repository).

### `scripts/ai-review-loop.sh` (FR-34)

- **Usage** `ai-review-loop.sh [--agents LIST] [--max-iterations N] [--diff-base REF]`. Agents: `--agents` > `review.ai_review_agents` > `claude` (the profile list must be a YAML list); unsupported names → `[rust-sdlc][WARN] agent <a> is not supported in v0.1.0; skipped`; no supported agent → exit 1. Diff base: `--diff-base` > `ci.base_ref` > `origin/main`. `--max-iterations` default 5, `^[0-9]+$`, 1–20 by digit-string compare (else exit 2).
- **Per iteration:** prompt = Rust review rules (FR-23 rule set, P6 prohibitions) + `git diff <base>...HEAD` capped at 50,000 bytes (truncation note) + the mandatory-last-line demand; `claude_run_once`; stdout `ITERATION: <i>/<max> agent=<a> verdict=<PASS|FAIL>` then the review text; a missing verdict line is a failed iteration (no retry).
- **End:** `AI_REVIEW_VERDICT: PASS|FAIL` last line. Exit 0 PASS, 1 FAIL or no agent, 2 usage. Writes nothing.

### `scripts/fr-nfr-gate.sh` (FR-35, react interface)

- **Usage** `fr-nfr-gate.sh [--spec-path PATH] [--pr N] [--impact-context TEXT] [--iteration N] [--advisory]`.
- **Sources:** bundle (`--spec-path`, contained in the repository after symlink resolution, else exit 1 before any gh/claude call), PR description and linked closing issues (`gh api graphql` `closingIssuesReferences(first: 50)`; more than 50 → fail closed), always the 7-id Rust baseline catalog (`NFR-BASE-TEST`, `NFR-BASE-QUALITY`, `NFR-BASE-ARCH`, `NFR-BASE-CONTRACT`, `NFR-BASE-DATA`, `NFR-BASE-SEC`, `NFR-BASE-OBS`). No bundle and no PR text → failure status (unless `--advisory`), `cannot trace this change to any requirement`, exit 1.
- **Budgets (bytes):** source 12,000 each, sources 40,000 total, diff 50,000, files list 16,000, prompt 120,000, comment 60,000; contributor text fenced through `fence_safe`.
- **Run:** `claude_supports_restricted` or fail fast (`upgrade Claude Code to 2.1.248 or newer`, exit 1); `claude_run_isolated`; last line must match `^FR_NFR_NEW_FINDINGS: ([0-9]+)$` (else failure status + exit 1).
- **Publish (not with `--advisory`):** commit status on `git rev-parse HEAD`, context `BMAD FR/NFR Review Gate`, state `success` (n = 0) or `failure`, 3 attempts spaced by `FR_NFR_STATUS_RETRY_DELAY × attempt` (unpostable → exit 1); a redacted PR comment (marker `<!-- rust-sdlc-fr-nfr-gate -->`, iteration shown) only when n > 0.
- **Stdout:** review text, `STATUS_POSTED: <state> <sha7>` or `ADVISORY: no status or comment posted`, `COMMENT_POSTED: <url>` when posted, last line `FR_NFR_NEW_FINDINGS: <n>`. Exit 0 zero findings, 1 otherwise, 2 usage.

### `scripts/get-pr-comments.sh` (FR-36)

- **Usage** `get-pr-comments.sh [--pr N] [--unresolved-only] [--json]`. PR default `gh pr view --json number --jq .number`; validated `^[1-9][0-9]*$` whatever the source. One paginated `gh api graphql` query (`reviewThreads(first: 100, after: $cursor) { nodes { isResolved comments(first: 100) { nodes { author { login } body path line url } } } pageInfo { hasNextPage endCursor } }`, `comments(first: 100)` for issue comments). `--json` → `{"pr": N, "review_threads": [{"is_resolved": bool, "comments": [{"author", "body", "path", "line", "url"}]}], "issue_comments": [{"author", "body", "url"}]}`; `--unresolved-only` drops resolved threads and all issue comments. Human output ends `unresolved threads: N`. `gh` absent → exit 1. Exit 0, 1, 2.

### `scripts/post-review-findings.sh` (FR-37)

- **Usage** `post-review-findings.sh <lens> [--pr N] [--file F]... [--dry-run] [--json]` and `post-review-findings.sh --conclusion [--file F]... [--pr N] [--started-at ISO] [--ended-at ISO] [--duration-seconds N] [--iterations N]`; lens ∈ `security fr-nfr code-review`; default ledgers `${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}/<lens>.json` (ADR-16 schema).
- **Behaviour:** one comment per lens with marker `<!-- rust-sdlc-review:<lens> -->`, updated in place (PATCH the oldest matching comment, delete none); conclusion marker `<!-- rust-sdlc-review:conclusion -->` posted once per PR; findings deduplicated by `(file, line, rule)`, sorted by severity; `redact` before render; writes only to the origin repository's own PR (base repository mismatch refused).
- **Degrade-first (exit 0 with `DEGRADED: <reason>`):** `capabilities.publish_pr_comments: false`, gh absent, no PR, empty or all-dropped ledger, ledger `schema_version` ≠ 1, malformed gh read, base mismatch, write failure.
- **Stdout:** `POSTED: <lens> created <url>` / `POSTED: <lens> updated <comment-id>` / `WOULD: post <lens>` / `--json` the rendered payload. Exit 0, 2 usage, 1 only for a malformed ledger file given with `--file`.

### `scripts/pr-state.sh` (FR-38, react port + human-gated)

- **Usage** `pr-state.sh [--pr N] [--reviewers LIST] [--required-checks LIST] [--human-gated-checks LIST] [--wait-seconds S] [--interval-seconds S] [--wait-verdicts LIST] [--json]`. Defaults from the profile: `review.reviewers`, `ci.required_checks`, `ci.human_gated` (comma-joined); check names matched exactly and case-sensitively against check-run `name`; an explicit `--required-checks` narrows CI scope (react semantics).
- **Snapshot:** react's five gh reads plus `get-pr-comments.sh --pr N --unresolved-only --json`; context `BMAD FR/NFR Review Gate` judged on its own (`success failure pending missing`).
- **Verdict** (exactly one, priority `BLOCKED > FIX > GATE > REQUEST > WAIT > READY`): `BLOCKED` = state ≠ OPEN, `mergeable == CONFLICTING`, or a failing check whose name is in the human-gated list (`NEXT:` names the label from `docs/repository-settings.md`: `approved-config-change` for `Protected configuration`, `approved-breaking-change` for the two breaking-change checks; never applied by the plugin); other rules as react.
- **Output:** `KEY: value` lines (`PR:`, `HEAD:`, `CI:`, `FR_NFR_GATE:`, `UNRESOLVED:`, `REVIEWER:`…, `HUMAN_GATED:`, `INFO:`…), `VERDICT: <v>`, `NEXT: <hint>`; `--json` sorted keys `{ci, draft, fr_nfr, head, human_gated, mergeable, next, notes, pr, repo, reviewers, state, unresolved, url, verdict}`. NEXT hints name `rs-sdlc-fr-nfr-review` (GATE), `request-ai-reviews.sh …` (REQUEST), `pr-state.sh --pr <n> --wait-seconds 540` (WAIT), `/rs-sdlc-review` (all reviewers skipped). Exit 0 whenever a snapshot rendered, 1 on usage, unresolvable repository or gh failure.

### `scripts/request-ai-reviews.sh` (FR-39, react port)

- **Usage** `request-ai-reviews.sh [--pr N] [--reviewers LIST] [--full] [--min-interval-minutes M] [--force] [--dry-run]`; reviewers `--reviewers` > `review.reviewers`; validation harmonised with `pr-state.sh` (known names, no duplicates, no empty element). Plan and output lines as react: `REQUESTED: <r> <mention>`, `WOULD-POST: …`, `WAIT: <r> <m>m (…)`, `SKIPPED: <r> — <reason>`, `INFO: …`, then `SUMMARY: requested=<n> waiting=<n> skipped=<n>`; empty list → `INFO: no reviewers configured`, exit 0. Exit 0 plan computed and posts succeeded, 1 usage, repository or gh failure.

## Command Contracts

### Shared command contract (FR-1)

- Frontmatter and H2 spine per "Markdown component conventions". First fenced block (all but setup and new-service): `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"`; exit 1 → stop with `run /rs-sdlc-setup on the default branch and commit the result` and the stage's escalation block.
- Every command that runs `make`, `git commit` or `git push` contains, verbatim, the background sentence ("Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` and `bmalph run`, runs in the background, logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled at most every 30 s.") and the container-precondition sentence ("In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.").
- Docker-dependent work is preceded by `docker info`; a failing probe, or the message `This target needs a reachable container engine (docker).` in a log, classifies the affected targets `not run (no Docker)` (never `failed`, never remediated, D2).
- Targets-run list: `<target>: passed | failed | not run (<reason>)`, reasons ∈ `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`.
- Agents are invoked with the Task tool, `subagent_type: rust-backend-sdlc:<agent>`; stage commands invoked by the orchestrator are executed by reading `${CLAUDE_PLUGIN_ROOT}/commands/<stage>.md` and following its procedure with the stage's arguments (a slash command cannot call another).
- Every exit path prints either the stage's success handles plus `## Status:`/`## Verdict:` where defined, or the escalation block. Commands never write protected files, never apply labels, never pass P1–P7 constructs.

### Exit strings (single source; byte-identical in the stage command, `rs-sdlc.md` and `docs/sdlc-loop.md`)

| Stage id | Exit string | Guard |
| --- | --- | --- |
| `setup-check` | valid profile, governance markers in CLAUDE.md and AGENTS.md, _bmad/ present | halt with "run /rs-sdlc-setup on the default branch and commit the result" |
| `issue` | issue with ≥ 3 testable acceptance criteria and label rust-backend-sdlc exists | 5 |
| `branch` | branch `<type>/<N>-<slug>` checked out from the default branch | — |
| `plan` | bundle complete, readiness "ready", readiness regex clean, bundle committed | 5 |
| `implement` | all stories done with EXIT_SIGNAL true, every commit subject valid, coverage green | 5 + Ralph circuit breaker (never reset) |
| `review` | zero new gate findings AND every quality row PASS | 5 |
| `qa` | QA verdict PASS on HEAD (FAIL routes to stage 3) | 5 |
| `finish-pr` | CI green + FR/NFR gate green on the head SHA + 0 unresolved review threads | A 5, B 5, C 3, W 6, R 3 |
| `setup` | preflight without FAIL, profile valid, markers in both files, allowlist present or printed, docs-check passed or degraded with a note | 5 (regeneration attempts) |
| `new-service` | S1–S14 executed or printed as NEXT, bootstrap PR handed to finish-pr (GitHub mode) | 5 (hook-failure remediation rounds) |
| `new-context` | context gate set green, 0 protected files changed, committed | 5 (remediation rounds) |

### `/rs-sdlc` (FR-3)

- **Frontmatter:** `description: "Drive a Rust service feature from a task description to a finished pull request: issue, BMAD plan, bmalph implementation, review with the FR/NFR gate, black-box QA and PR finishing; resumable."`, `argument-hint: "[task-text | #N | issue-URL]"`.
- **Inputs:** task text, `<N>`/`#<N>`/issue URL (resume), or nothing on a `<type>/<N>-…` branch (resume N); the profile; `CLAUDE.md`, `AGENTS.md`; `_bmad/`.
- **Procedure:** (1) stage 0 `setup-check`: `validate-profile.sh`; `grep -q '<!-- rust-backend-sdlc:begin -->'` in both files; `test -d _bmad`; any failure → escalate with the halt wording, never run setup. (2) Resume: `gh api repos/{owner}/{repo}/issues/<N>/comments --paginate` → the body starting `<!-- rust-sdlc-state -->` piped into `common.sh resume_point`, else `common.sh resume_point --cache target/rust-sdlc/state/<N>-<slug>.json`, else fresh (D10 note when gh is unreachable and the cache is absent: review and QA re-run). (3) Stage 1 issue → `ISSUE_URL:`, `ISSUE_NUMBER:`. (4) Branch: `git fetch origin <default_branch>` once (D24 on failure), `git switch -c <type>/<N>-<slug>` from `origin/<default_branch>` (type `fix` when the issue carries `bug`, else `feat`; slug = kebab of the issue title ≤ 40), or reuse the existing branch. (5) Stages 2–6 in order; QA `FAIL` returns to stage 3 with the QA report (consumes implement's budget). (6) After each stage: `common.sh state_cache_update …` then `common.sh state_comment_body …` → `gh api -X PATCH repos/{owner}/{repo}/issues/comments/<id>` (or `POST …/issues/<N>/comments` the first time) with the ADR-14 concurrency check. (7) Run report.
- **Additional H2s:** `## Stage table` (the exit-strings table rows 0–6 with "Delegates to"), `## Resume table` (stage → durable record → validity: issue/plan/implement = ancestor, review/qa = equal, finish-pr = live `pr-state.sh`), `## Run report`.
- **Run report (8 fields, every exit path):**

```text
=== SDLC RUN REPORT ===
task: <task text or "#<N> (resumed)">
branch: <branch>
result: SUCCESS | ESCALATED
stages:
| stage | iterations used | exit string | met |
| --- | --- | --- | --- |
| issue | 1/5 | issue with ≥ 3 testable acceptance criteria and label rust-backend-sdlc exists | yes |
artifacts: issue=<url> specs=<SPECS_DIR> pr=<url>
degrade_notes: <"none" or one "- <note>" line each>
targets_not_run: <"none" or one "- <target>: <reason>" line each>
escalation: <the failing stage's block, or none>
=== END ===
```

- **Loop & exit:** each stage's own guard; a `SUCCESS-WITH-REPORT` stage records `met: yes (degraded)` and keeps `result: SUCCESS`; an `ESCALATED` stage records `met: no` and ends the run. **Guard:** `MAX_ITERATIONS=5` per stage, counters never reset within a run, restored from the state comment on resume. **Escalation stage ids:** those of the delegated stage. **Handles:** `ISSUE_URL:`, `ISSUE_NUMBER:`, `BRANCH:`, `SPECS_DIR:`, `PR_URL:`, the run report.

### `/rs-sdlc-setup` (FR-4)

- **Frontmatter:** `description: "Prepare a Rust template-derived repository for the plugin: preflight, bmalph setup, project profile, governance block, local permission allowlist, hooks and docs-check."`, `argument-hint: "[--refresh] [--with-qa-network] [--print-settings] [--exec host|container]"`.
- **Procedure** (exactly FR-4 steps 1–9): `setup-preflight.sh --report` (any `FAIL` → escalate with the table); `make bmalph-setup` when `_bmad/` is absent, `make.bmalph_setup` mapped and the tracked tree clean (dirty → `DEGRADED: make bmalph-setup not run (tracked changes: <files>)` + `NEXT: commit or stash, then make bmalph-setup`), then re-check the bmalph floor; `generate-profile.sh [--refresh] [--run-in-container true|false]` (`--exec host` → `false`, `--exec container` → `true`, no `--exec` → no flag); `validate-profile.sh` (failure → regenerate with `--refresh`, ≤ 5 attempts); `inject-governance.sh`; `merge-settings.sh [--with-qa-network] [--print]` (protected-settings rule, D4 note); `make install-hooks` when `git config --get core.hooksPath` prints nothing; `make docs-check` backgrounded under the step-8 conditions, else a degrade note (D3/D25); summary with written files, `UNCHANGED:` files, degrade notes, the single-commit instruction ("commit `.claude/rust-sdlc.yml`, `CLAUDE.md` and `AGENTS.md` together in one commit") and a warning when not on the default branch.
- **Guard:** `MAX_ITERATIONS=5` (regeneration). **Escalation stage:** `setup`. **Handles:** `DONE:`/`UNCHANGED:`/`DEGRADED:`/`NEXT:` lines.

### `/rs-sdlc-new-service` (FR-11)

- **Frontmatter:** `description: "Create a new Rust microservice from the service template: repository, identity, sync flavour, bootstrap, setup and a bootstrap pull request handed to PR finishing."`, `argument-hint: "[<name>] [--description <text>] [--owner <org>] [--visibility private|public] [--template <owner/repo> | --template-path <dir> | --in-place] [--dest <parent-dir>] [--version <x.y.z>] [--intro <text>] [--sync-flavour app|pat] [--keep-specs] [--issue <N>] [--exec host|container] [--dry-run]"`.
- **Inputs:** the flags; interactive sessions ask for a missing name and a missing sync flavour once; headless runs take the documented defaults (`SKIP: sync-flavour (undecided)`).
- **Procedure (S1–S14, EXECUTED or NEXT):** S1 `new-service.sh --phase source …` (parse `SOURCE_MODE:`, `REPO:`, `CHECKOUT:`, `SOURCE:`, `SOURCE_SHA:`); `cd` into `CHECKOUT`. S2 GitHub mode: `gh label create rust-backend-sdlc --color 5319e7 --description "Managed by the rust-backend-sdlc plugin"` when missing, `gh issue create` (title `Initialize <name> from the Rust service template`, acceptance criteria = G1(c) checks) → `ISSUE_NUMBER:`; local mode uses `--issue`. S3 clone-and-push only: `git add -A`, commit `chore(#N): import template <slug> at <sha7>`, `git push -u origin main`. S4 `git switch -c chore/<N>-initialize-service`. S5 `new-service.sh --phase customize …`. S6 `NEXT:` lines (keep the example context; secrets, variables and labels from `docs/new-service.md`; branch protection from `docs/repository-settings.md`). S7 `make doctor` (report only). S8 `make bootstrap` backgrounded (log `target/rust-sdlc/new-service/bootstrap.log`, poll 30 s, ≤ 60 min) when Docker is reachable, else `NOT RUN (no Docker)`. S9 `scripts/set-version.sh <v>` when S5 printed it (host: direct; container: `docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh <v>`; no Docker: `NEXT:`). S10 `make generate-openapi-spec` (backgrounded) when S8 succeeded or the host toolchain exists, else `NEXT:` and stop before S11. S11 commit `chore(#N): initialize service from template` (local mode without `--issue`: `NEXT:` with `<N>` and stop). S12 `/rs-sdlc-setup --exec <resolved>` (procedure of `rs-sdlc-setup.md`). S13 commit `chore(#N): add rust-backend-sdlc profile and governance`. S14 title check, `git push -u origin chore/<N>-initialize-service`, `gh pr create` with the body built from `.github/pull_request_template.md` H2s and `Closes #N`, then the finish-pr procedure.
- **`--exec` default:** `container` when `docker info` exits 0 and `cargo` is absent, else `host`. **`--dry-run`:** `new-service.sh --dry-run` plus `WOULD:` lines for S2–S14; no GitHub mutation.
- **Guard:** `MAX_ITERATIONS=5` hook-failure remediation rounds at S11/S13 (a failing pre-commit hook → `make format`, re-stage, retry); finish-pr counters after hand-off. **Escalation stage:** `new-service`. **Handles:** `ISSUE_NUMBER:`, `BRANCH:`, `PR_URL:`, one `DONE:`/`NEXT:` summary.

### `/rs-sdlc-new-context` (FR-14)

- **Frontmatter:** `description: "Add a bounded context to a Rust service with make new-context, complete the wiring checklist C1–C12 and prove it with the template's gate stages."`, `argument-hint: "[<group> <context>] [--issue <N>] [--no-handoff]"`.
- **Procedure:** (1) `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" validate_context_name <g> <c>` before anything (exit 1 → print the `REFUSED:` line and escalate, nothing written). (2) Branch/issue rule (reuse `<type>/<N>-…` branch; else `--issue` or the issue stage; then `feat/<N>-<context>` from the default branch). (3) `make new-context group=<g> context=<c>` backgrounded; non-zero → classify by stderr prefix `new-context refused:` / `new-context could not run:` (attach `git status --porcelain`) / neither (log tail) → escalate. (4) Load `bounded-context-scaffolding`; dispatch C2–C11 to `rust-implementer` (each item returns `DONE: C<n> <evidence>` or `N/A: C<n> <reason>`). (5) Commit `feat(#N): add <group>/<context> bounded context`. (6) C12: `docker info` first (fail → `ESCALATED` with `make doctor` output); then `make ci-preflight`, `make ci-static-analysis`, `make ci-tests`, `make ci-contracts`, `make ci-mutation`, `make ci-delivery` (stage list read at runtime from `CI_*_TARGETS`; `ci-cli` never), one backgrounded call each; a failing stage → `rust-implementer` remediation, commit `fix(#N): <what>`; finally `make validate-configuration`. (7) Hand-off to review → QA → finish-pr procedures with the counters, or with `--no-handoff` three `NEXT:` lines naming /rs-sdlc-review, /rs-sdlc-qa and /rs-sdlc-finish-pr.
- **Guard:** `MAX_ITERATIONS=5` remediation rounds. **Escalation stage:** `new-context`. **Handles:** `ISSUE_NUMBER:`, `BRANCH:`, checklist lines, targets-run list.

### `/rs-sdlc-issue` (FR-15)

- **Frontmatter:** `description: "Turn a task description into a GitHub issue with testable acceptance criteria and the rust-backend-sdlc label, or adopt an existing issue."`, `argument-hint: "[task-text | issue-URL | #N]"`.
- **Procedure:** adopt (`gh issue view <N> --json number,url,title,body,labels,state`; open and ≥ 3 testable criteria → add the label if missing) or create: body with the H2s of `.github/ISSUE_TEMPLATE/feature_request.md` (fallback `Problem statement`, `Proposed change`, `Affected area`, `Tasks`, `Acceptance criteria`), ≥ 3 criteria phrased as observable HTTP/GraphQL behaviour, text through `common.sh redact`, `gh issue create --title … --body-file … --label rust-backend-sdlc [--label enhancement]` (label created when missing; `enhancement` only when it exists). Self-check loop on the criteria.
- **Guard:** `MAX_ITERATIONS=5`. **Escalation stage:** `issue`. **Handles:** `ISSUE_URL:`, `ISSUE_NUMBER:`.

### `/rs-sdlc-plan` (FR-16)

- **Frontmatter:** `description: "Write and commit the BMAD planning bundle for an issue under specs/, ready for bmalph, without interactive prompts."`, `argument-hint: "[#N] [--slug <kebab-title>]"`.
- **Procedure:** load `.claude/skills/bmad-autonomous-planning/SKILL.md` when present (repository wins), else `${CLAUDE_PLUGIN_ROOT}/skills/bmad-autonomous-planning/SKILL.md`; write `specs/<N>-<kebab-title>/` with the seven FR-16 files; `architecture.md` carries `## Tech Stack` (Rust toolchain and crates only) and `## Constraints` with (a) the commit convention containing the literal `(#<N>)` and the `story N.M` subject form and (b) the story-dispatch rule naming the five DB-free keys (`make.format`, `make.lint_code`, `make.unit_tests`, `make.architecture`, `make.complexity`) and five DB-backed keys (`make.setup_test_db`, `make.integration_tests`, `make.tests_with_coverage`, `make.e2e_tests`, `make.sqlx_prepare`) with both ADR-21 branches; story 1 "Scaffold `<group>/<context>`" when a needed context is absent from `[workspace].members`; readiness self-check (`/NO[-\s]?GO/i` must not match; verdict "ready"); commit `docs(#N): add planning bundle <N>-<kebab-title>`.
- **Guard:** `MAX_ITERATIONS=5`. **Escalation stage:** `plan`. **Handles:** `SPECS_DIR:`.

### `/rs-sdlc-implement` (FR-18)

- **Frontmatter:** `description: "Stage the planning bundle for bmalph and run the Ralph loop with the claude-code driver until every story is done with valid commit subjects and green coverage."`, `argument-hint: "[SPECS_DIR]"`.
- **Procedure:** (1) hooks active (`git config --get core.hooksPath`, else `make install-hooks`); (2) `stage-planning-artifacts.sh "$SPECS_DIR"`, `bmalph implement` (never `--force`), verify both `## Constraints` parts in `.ralph/PROJECT_CONTEXT.md` (missing → escalate naming /rs-sdlc-plan); (3) `bmalph run --driver claude-code --no-dashboard` backgrounded, log polled ≤ 30 s, `---RALPH_STATUS---` blocks parsed; (4) single-implementer sentence: "`bmalph run` is the only implementer; while it is active this command dispatches no `rust-implementer` and edits no file"; (5) breaker trip (`.ralph/` state or `STATUS: BLOCKED` with the breaker message) → `ESCALATED` with the last status block and `tail -n 50` of the newest `.ralph/logs/` file, no second `bmalph run`, `.ralph/.ralphrc` never edited; (6) post-loop: every subject of `git log --format=%s $(git merge-base <ci.base_ref> HEAD)..HEAD` through `make check-commit-message COMMIT_TITLE='<subject>'` (mismatch → escalate naming the commit); `make tests-with-coverage` backgrounded (Docker unreachable → D2).
- **Guard:** `MAX_ITERATIONS=5` `bmalph run` attempts/resumes + breaker. **Escalation stage:** `implement`. **Handles:** last `---RALPH_STATUS---` block, targets-run list.

### `/rs-sdlc-review` (FR-19)

- **Frontmatter:** `description: "Review the branch: triage all 28 plugin skills, run the code-quality, FR/NFR and security lenses with the quality rows Q1–Q15, and loop the FR/NFR gate to zero new findings."`, `argument-hint: "[SPECS_DIR] [--base <ref>]"`, `allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]`.
- **Procedure:** marker check (stage-0 wording); triage table `| skill | source | verdict | evidence or reason |` with 28 rows (counterpart pairs `repo+plugin`, repository skill read first); lenses per ADR-5 with the PA-5 trigger list (`*.rs`, `Cargo.toml`, `Cargo.lock`, `migrations/`, `.sqlx/`, `deny.toml`, `Dockerfile`, `.github/workflows/`); quality rows Q1–Q15 exactly as FR-19 (keys per "Quality bars"); enforced-elsewhere sentence for `quality.max_image_vulnerabilities_high_critical` and `quality.max_smoke_budget_breaches`; mutation run rule PA-13; gate loop `fr-nfr-gate.sh --spec-path "$SPECS_DIR" --iteration <n> [--pr <n>] [--advisory]` (or `make.fr_nfr_gate`); remediation = one Task to `rust-implementer` with all findings, then the command commits `fix(#N): address review gate iteration <n> findings`; each lens's findings piped into `"${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh" ledger_write <lens> <n> <head_sha>` (ledgers under `${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}`); `post-review-findings.sh <lens>` per lens when a PR exists, else deferred to finish-pr; emits `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<PASS|FAIL>` per iteration and `## Verdict: PASS|FAIL`.
- **Guard:** `MAX_ITERATIONS=5`. **Escalation stage:** `review`.

### `/rs-sdlc-qa` (FR-20)

- **Frontmatter:** `description: "Black-box QA of the running service over REST, GraphQL and the health probes against every acceptance criterion, with HTTP evidence and a PASS/FAIL verdict."`, `argument-hint: "[SPECS_DIR | #N]"`, `allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]`.
- **Procedure:** boot (liveness probe; else `make.start` backgrounded ≤ 900 s; `make.start: null` → `SUCCESS-WITH-REPORT`; Docker unreachable with `make.start` mapped → `ESCALATED` with `make doctor`); `make migrate` backgrounded when `persistence.engine` is non-null and `make.migrate` mapped; liveness poll every ≤ 10 s, ≤ 900 s, two consecutive 200s (timeout → `ESCALATED` with `docker compose logs --no-log-prefix --tail 200 app`); delegate to `qa-manual-tester` with the probe rules of FR-20; never stop the stack; FAIL → report routes to stage 3.
- **Guard:** `MAX_ITERATIONS=5`. **Escalation stage:** `qa`. **Handles:** `## Verdict: PASS|FAIL`, the evidence table.

### `/rs-sdlc-finish-pr` (FR-21)

- **Frontmatter:** `description: "Create or update the pull request and loop until CI is green, the FR/NFR gate is green on the head commit and every review thread is resolved."`, `argument-hint: "[--pr <n>]"`.
- **Procedure:** PR create/edit (title pre-validated; body from `.github/pull_request_template.md` H2s with `Closes #N`, `SPECS_DIR`, QA verdict, targets run / not run); sensor loop on `pr-state.sh --json` with the dispatch table below; READY confirmed by a second snapshot, then `post-review-findings.sh --conclusion` once and `## Status: ALL-GREEN`.

| Verdict | Action | Counter (cap) |
| --- | --- | --- |
| `FIX` | `ci-fixer` for failing non-human-gated checks; `pr-comment-resolver` for unresolved threads; the command commits (`fix(#N): resolve <check> failure`, `fix(#N): address review comment on <path>`) and pushes | A `ci_fix` (5), B `comment_resolution` (5) |
| `GATE` | `fr-nfr-gate.sh --pr <n> --iteration <c>` on the clean head | C `fr_nfr_gate` (3) |
| `REQUEST` | `request-ai-reviews.sh` with the arguments of the sensor's `NEXT:` hint | R `request` (3) |
| `WAIT` | `pr-state.sh --wait-seconds 540` | W `wait` (6) |
| `BLOCKED` | `ESCALATED` naming the label or the conflict | — |
| `READY` | second snapshot; conclusion comment; `## Status: ALL-GREEN` | — |

- **Degrades:** no CI or zero checks → `## Status: SKIPPED-NO-CI` (D8); no reviewer → `ai-review-loop.sh` as comment source (D7); comments off (D12). **Guard:** `MAX_ITERATIONS=5` and the counters above. **Escalation stage:** `finish-pr`. **Handles:** `PR_URL:`, `## Status: ALL-GREEN|FIXES-READY|SKIPPED-NO-CI|BLOCKED`.

## Agent Contracts

Shared (FR-22): 8-H2 spine; git ownership (no commit, push, label, `.ralph/` edit; `ci-fixer` may `gh run rerun --failed` once per head; `pr-comment-resolver` may reply to and resolve threads); protected change → `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`, a guard-hook denial reported verbatim, never retried through Bash; make-only execution with the FR-1 vocabulary; `## Iteration discipline` states `MAX_ITERATIONS=5`; `## Smoke prompt` holds one happy-path and one degrade-path prompt.

| Agent | model | tools | Inputs | Output / verdict format |
| --- | --- | --- | --- | --- |
| `rust-implementer` | sonnet | Read, Write, Edit, Glob, Grep, Bash | story text + acceptance criteria, `SPECS_DIR`, profile, governance block, `AGENTS.md`, executed skills, prior failure feedback | changed-files list; targets-run list; self-review checklist (FR-23 rules); final `---RALPH_STATUS---` block (`STATUS: IN_PROGRESS\|COMPLETE\|BLOCKED`, `TASKS_COMPLETED_THIS_LOOP`, `FILES_MODIFIED`, `TESTS_STATUS: PASSING\|FAILING\|NOT_RUN`, `WORK_TYPE`, `EXIT_SIGNAL: true\|false`, `RECOMMENDATION`) |
| `code-quality-reviewer` | opus | Read, Glob, Grep, Bash | diff vs `ci.base_ref`, executed skills, profile | findings `file:line \| severity \| rule \| root-cause fix`; Q1–Q15 table `\| row \| target key \| quality key or "binary gate, no quality key" \| PASS/FAIL/NOT RUN (reason) \| measured \|` byte-identical row→key mapping with `rs-sdlc-review.md`; `## Verdict: PASS\|FAIL` |
| `fr-nfr-reviewer` | opus | Read, Glob, Grep, Bash | bundle, PR text, baseline catalog, prior ledger | per-requirement matrix `\| id \| requirement \| PASS/FAIL \| evidence (test target) \|`; last line `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<PASS\|FAIL>`; degrade → `verdict=FAIL` + `DEGRADED: <reason>` + `blocking_finding` (`SPECS MISSING: <path>`, `REQUIREMENTS MISSING: PR #<n>`) |
| `qa-manual-tester` | sonnet | Bash, Read | profile, bundle, committed snapshots, issue acceptance criteria | evidence table `\| check \| method \| URL \| request \| status \| content type \| x-request-id \| excerpt (≤ 20 lines) \| expected \| observed \|`; each FAIL with a reproduction `curl`; `## Verdict: PASS\|FAIL` |
| `ci-fixer` | sonnet | Read, Edit, Write, Glob, Grep, Bash | `pr-state.sh --json`, `gh run view --log-failed`, `docs/repository-settings*.md`, `docs/make-targets.md` | per-iteration table `\| check \| gate id(s) \| target \| action \| result \|`; counter line `ci_fix <n>/5`; `## Status: ALL-GREEN\|FIXES-READY\|SKIPPED-NO-CI\|BLOCKED` |
| `pr-comment-resolver` | sonnet | Read, Edit, Write, Glob, Grep, Bash | `get-pr-comments.sh --unresolved-only --json` (or `ai-review-loop.sh` findings, D7) | per-thread table `\| thread url \| decision fix\|reply\|decline \| commit or reply text \|`; counter line `comment_resolution <n>/5`; `remaining_unresolved: <n>` |
| `security-auditor` | opus | Read, Glob, Grep, Bash | diff, profile, security-audit skill | ledger-format findings (`{id, severity, file, line, rule, summary, status}`) per family; lanes table `\| lane \| target \| result \|`; `## Verdict: PASS\|FAIL` |

Agent-specific rules (token-tested in `component-counts.bats`): `rust-implementer` carries every FR-23 rule token (`ValidatedJson`, `ApiPath`, `ValidatedQuery`, `ApiJson`, `UuidGenerator`, `Clock`, `tests.rs`, `#[expect`, `reason =`, `sqlx-prepare`, `create-migration`, `generate-openapi-spec`, `generate-graphql-spec`, `workspace.dsl`, `Problem`, `no mod.rs`) and the DB rule; `code-quality-reviewer` never runs `-fix` targets and never proposes suppressions; `qa-manual-tester` forbids reads of `crates/`, `tests/`, `features/`, `xtask/`, `migrations/`, `.sqlx/`, `Cargo.toml`, uses only `curl http://localhost:<port>/…` or `curl http://127.0.0.1:<port>/…` (URL first, never `-o`, `--output`, `-T`, `--upload-file`) and the single log form `docker compose logs --no-log-prefix --tail 200 app`; `ci-fixer` maps check → gate id ("Gate" cell) → target (`docs/make-targets.md` gate table), reports `none` gates and human-gated checks without fixing, escalates RUSTSEC advisories without a fixed version; `pr-comment-resolver` declines the six categories of FR-28 with a reply citing the rule; `security-auditor` lanes `make.check_security`, `make.secrets_scan`, `make.image_scan`, clippy findings, families of FR-29, dynamic probes only on `service.base_url` and only when `capabilities.dynamic_security_testing` is true.

## Skill Library

### Skill anatomy (every `skills/<name>/SKILL.md`)

```markdown
---
name: <name>
description: Use when <trigger>. Skip when <profile condition>. Not for <neighbour> (use <other skill>).
---

# <Title>

## Profile keys consumed

- `<dotted.key>` — <what it selects>

## Repository precedence

Read `.claude/skills/<name>/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line.

## Context
## Task
## Success criteria
## Steps
## Constraints
## Verification
```

Rules: keys listed are declared in `docs/profile-schema.md` and are the only dotted keys the body uses; no file names in `## Profile keys consumed`; a gating section names its skip path (`SKIPPED: <reason>` when `capabilities.<key>` is false); lists the template defines (gate order, protected files, required checks) are read at runtime (`make.ci_list`, `cargo xtask config-guard --list`, `docs/repository-settings.md`), never restated except as sourced examples inside `# profile-example` fences; the example bounded context is written `<group>/<context>` and `<Entity>`, never the template's sample names.

### Final list (28 skills)

| # | Skill | Scope (one line) | Profile keys consumed | Defers to template skill | Supporting files / gating |
| --- | --- | --- | --- | --- | --- |
| 1 | `api-resource-development` | add or change a REST/GraphQL operation, command, query, subscriber in a context (extractors, `Problem`, ports) | `framework.http`, `framework.openapi`, `framework.graphql`, `persistence.engine`, `architecture.composition_root`, `make.generate_openapi_spec`, `make.generate_graphql_spec`, `make.tests_with_coverage`, `make.e2e_tests` | `api-resource-development` | GraphQL section skipped when `framework.graphql` is false |
| 2 | `api-contract-development` | regenerate and validate contract snapshots; breaking-change policy | `framework.openapi`, `framework.graphql`, `service.openapi_snapshot`, `service.graphql_snapshot`, `make.generate_openapi_spec`, `make.generate_graphql_spec`, `make.validate_contract_snapshots`, `make.validate_openapi_spec`, `make.openapi_diff`, `make.graphql_diff`, `quality.max_spectral_findings`, `quality.max_unapproved_breaking_changes`, `ci.base_ref` | `api-contract-development` | — |
| 3 | `architecture-boundary-fixer` | resolve `make architecture`/crate-isolation/dependency findings by moving code, never by editing allow-lists | `architecture.layers`, `architecture.crates_root`, `make.architecture`, `make.check_crate_isolation`, `make.unused_dependencies`, `quality.max_architecture_violations`, `capabilities.protected_config` | `architecture-boundary-fixer` | — |
| 4 | `architecture-model-sync` | keep `workspace.dsl` components and relationships equal to crates and dependency edges | `capabilities.structurizr`, `make.validate_architecture_model`, `architecture.crates_root`, `architecture.bounded_contexts` | `architecture-model-sync` | skipped when `capabilities.structurizr` is false |
| 5 | `bmad-autonomous-planning` | write the planning bundle non-interactively, incl. `## Constraints` and the story-dispatch rule | `project.default_branch`, `architecture.bounded_contexts`, `make.format`, `make.lint_code`, `make.unit_tests`, `make.architecture`, `make.complexity`, `make.setup_test_db`, `make.integration_tests`, `make.tests_with_coverage`, `make.e2e_tests`, `make.sqlx_prepare` | `bmad-autonomous-planning` | — |
| 6 | `bmad-fr-nfr-review-gate` | run the FR/NFR gate loop and publish its verdict | `make.fr_nfr_gate`, `capabilities.publish_pr_comments`, `ci.base_ref` | — | publishing skipped when `capabilities.publish_pr_comments` is false |
| 7 | `cache-management` | add a cache behind a port in infrastructure (TTL through the `Clock` port, invalidation on commands, no cache in domain) | `architecture.layers`, `make.unit_tests`, `make.tests_with_coverage` | — | `examples/cache-implementation.md`, `examples/cache-testing.md` |
| 8 | `clean-architecture-llm` | layer responsibilities and dependency rule for AI-written Rust | `architecture.layers`, `architecture.composition_root`, `make.architecture` | — | — |
| 9 | `code-organization` | crate, module and file layout (`<context>-<layer>` crates, sibling `tests.rs`, no `mod.rs`) | `architecture.crates_root`, `architecture.composition_root`, `architecture.shared_crates`, `architecture.bounded_contexts` | — | `DIRECTORY-STRUCTURE.md` |
| 10 | `code-review` | review protocol, finding format, ledger and PR comment publishing | `capabilities.publish_pr_comments`, `make.post_review_findings`, `quality.max_clippy_findings`, `ci.base_ref` | — | publishing skipped when `capabilities.publish_pr_comments` is false |
| 11 | `complexity-management` | refactor to the `clippy.toml` limits (quoted at runtime), never raise them | `make.complexity`, `quality.max_complexity_violations` | `complexity-management` | — |
| 12 | `database-migrations` | add a reversible migration, migrate, prepare `.sqlx/`, never edit an applied one | `persistence.engine`, `persistence.migrations_dir`, `persistence.offline_metadata`, `make.create_migration`, `make.migrate`, `make.migrate_rollback`, `make.sqlx_prepare`, `make.validate_sqlx_metadata`, `make.setup_test_db` | — | skipped when `persistence.engine` is null |
| 13 | `documentation-creation` | write new service documentation that passes docs-check | `project.name`, `make.docs_check` | — | — |
| 14 | `documentation-sync` | keep docs in step with commands, targets, variables and endpoints | `make.docs_check`, `make.validate_invariants` | `documentation-sync` | — |
| 15 | `implementing-ddd-architecture` | aggregates, value objects, domain errors, ports in pure domain crates | `architecture.layers`, `architecture.bounded_contexts`, `architecture.shared_crates` | — | `REFERENCE.md` |
| 16 | `load-testing` | add or change a K6 scenario and its budget | `capabilities.load_testing`, `make.smoke_load_tests`, `make.load_tests`, `quality.max_smoke_budget_breaches` | `load-testing` | `reference/configuration.md`, `reference/graphql-patterns.md`, `reference/rest-api-patterns.md`, `reference/troubleshooting.md`, `reference/utils-extensions.md`; skipped when `capabilities.load_testing` is false |
| 17 | `observability-instrumentation` | `tracing` spans and fields, `request_id` correlation, no PII, health probes | `service.liveness_path`, `service.readiness_path`, `make.unit_tests` | — | — |
| 18 | `quality-standards` | the 12 bars, their sources and how each is measured | `quality.coverage_lines`, `quality.coverage_functions`, `quality.max_surviving_mutants`, `quality.max_clippy_findings`, `quality.max_complexity_violations`, `quality.max_architecture_violations`, `quality.max_unused_dependencies`, `quality.max_dependency_policy_findings`, `quality.max_spectral_findings`, `quality.max_unapproved_breaking_changes`, `quality.max_image_vulnerabilities_high_critical`, `quality.max_smoke_budget_breaches`, `make.ci_list` | `quality-standards` | — |
| 19 | `query-performance-analysis` | sqlx query plans, indexes, N+1 avoidance, statement timeouts | `persistence.engine`, `persistence.offline_metadata`, `make.sqlx_prepare`, `make.integration_tests` | — | skipped when `persistence.engine` is null |
| 20 | `security-audit` | OWASP-family audit of a Rust service, verify by reproduction | `capabilities.dynamic_security_testing`, `make.check_security`, `make.secrets_scan`, `make.image_scan`, `quality.max_dependency_policy_findings`, `quality.max_image_vulnerabilities_high_critical`, `service.base_url` | — | `reference/attack-playbooks.md`, `reference/owasp-catalog.md`, `reference/remediation-patterns.md`; dynamic probing skipped when `capabilities.dynamic_security_testing` is false |
| 21 | `testing-workflow` | unit, integration, e2e, coverage and mutation testing, deterministic seeds | `make.unit_tests`, `make.integration_tests`, `make.tests_with_coverage`, `make.e2e_tests`, `make.mutation_tests_diff`, `make.setup_test_db`, `quality.coverage_lines`, `quality.coverage_functions`, `quality.max_surviving_mutants`, `capabilities.mutation_testing`, `capabilities.load_testing` | `testing-workflow` | mutation section skipped when `capabilities.mutation_testing` is false |
| 22 | `verification-workflow` | run the gates stage by stage (never `make ci` in one call), container mode, background rule | `make.ci_list`, `make.ci_preflight`, `make.ci_static_analysis`, `make.ci_tests`, `make.ci_contracts`, `make.ci_mutation`, `make.ci_delivery`, `make.doctor`, `capabilities.run_in_container` | `verification-workflow` | — |
| 23 | `service-scaffolding` | S1–S14 and their traps (FR-31) | `project.name`, `project.repo`, `template.repository`, `template.sync_flavour`, `make.bootstrap`, `make.doctor`, `make.generate_openapi_spec`, `capabilities.run_in_container` | — | — |
| 24 | `bounded-context-scaffolding` | name rules, C1–C12 with evidence targets, context gate set, in-loop story-1 variant (FR-31) | `make.new_context`, `architecture.crates_root`, `architecture.bounded_contexts`, `make.validate_architecture_model`, `make.ci_preflight`, `make.ci_static_analysis`, `make.ci_tests`, `make.ci_contracts`, `make.ci_mutation`, `make.ci_delivery`, `make.validate_configuration` | — | — |
| 25 | `rust-error-handling` | four-level error model to `application/problem+json`, banned panics (FR-31) | `framework.http`, `framework.graphql`, `make.static_analysis` | — | GraphQL error section skipped when `framework.graphql` is false |
| 26 | `async-runtime-safety` | no blocking in async, no guard across `.await`, cancellation, `#[async_trait]` delegation (FR-31) | `make.static_analysis`, `make.unit_tests`, `make.integration_tests` | — | — |
| 27 | `dependency-policy` | cargo-deny lanes, cargo-shear, per-layer allow-lists (escalate), workspace inheritance (FR-31) | `architecture.layers`, `make.check_security`, `make.unused_dependencies`, `quality.max_dependency_policy_findings`, `quality.max_unused_dependencies`, `capabilities.protected_config` | — | — |
| 28 | `configuration-management` | configuration through the composition root's CLI/config modules, `.env`, `docs/environment.md` rows (FR-31) | `architecture.composition_root`, `service.port`, `make.docs_check` | — | — |

The 11 counterparts (rows 1–5, 11, 14, 16, 18, 21, 22) carry `## Repository precedence`; all names equal the template's skill directory names **[verified]**.

### Meta-guides

- `skills/SKILL-DECISION-GUIDE.md` (no frontmatter): the sentence "The gate contract is: every skill verdict recorded, no silent skips."; the triage protocol (verdicts from frontmatter + this guide; bodies only on EXECUTE; counterpart pairs once, source `repo+plugin`; always-EXECUTE `code-review` and `quality-standards`); a decision tree by change class — Rust source per layer, `crates/service` wiring, manifest/lock, migration, contract, workflow/docs-only, new context, new service; a 28-row table `| skill | EXECUTE when | NOT APPLICABLE when |`. The docs-only class marks exactly 6 skills `EXECUTE`: `documentation-sync`, `documentation-creation`, `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`.
- `skills/AI-AGENT-GUIDE.md` (no frontmatter): the 7 agents with model, tools and when each runs; the stage map (stage → command → agents → scripts → exit string); the handle list; the escalation block; the status vocabulary; the shared-resource (DB) rule; the git ownership rule. It enumerates exactly the 28 shipped skill names (LLM-judge J10).

## Governance Block

### Content rules (checked by `inject-governance.bats`)

1. Plugin commands appear only in plain prose (no code span starts with `/`).
2. Backticked tokens are exactly: `.claude/rust-sdlc.yml`, `AGENTS.md` (twice), `.claude/skills/README.md`, `protected-config.toml`, `quality.*`, `make.*`. Each path either exists in every template-derived repository or is the profile committed in the same commit.
3. No `make <target>` code span; no fenced block; no numbered list; no table.
4. Neither the literal assembled from `rust-service-` + `template` nor the fixture's `TEMPLATE_REPOSITORY` name.
5. Byte-stable: cites profile keys, never values; identical output on every run and every repository.
6. Passes markdownlint-cli2 with the template's `.markdownlint-cli2.yaml` and typos with `_typos.toml`; sits outside `<!-- verification:start -->` … `<!-- verification:end -->`; appended after exactly one blank line.

### Exact text (written between and including the markers; one trailing newline)

```markdown
<!-- rust-backend-sdlc:begin -->

## rust-backend-sdlc governance (managed block — do not edit between markers)

The rust-backend-sdlc plugin writes this block and restores it when its setup command runs again. The values it refers to live in the project profile `.claude/rust-sdlc.yml`, which is committed together with this block.

- Skill triage: before implementation or review work, every plugin skill receives a recorded verdict, EXECUTE with evidence or NOT APPLICABLE with a reason. The rule is: every skill verdict recorded, no silent skips. A full skill body is loaded only on EXECUTE.
- Repository rules first: `AGENTS.md` and the skills listed in `.claude/skills/README.md` win over a plugin skill of the same name; the plugin skill adds only its loop, its evidence format and its escalation block.
- Tighten-only quality bars: the `quality.*` keys of the profile may only equal or tighten the values of the gates, and a file listed in `protected-config.toml` is never changed to make a check pass.
- Execution through make: every tool runs through the target that the `make.*` keys of the profile map; the order of the checks is the verification section of `AGENTS.md`.
- Commits and pull-request titles use the form type(#issue): subject, and the git hooks are never bypassed.
- Protected configuration is escalated to a maintainer with the approval label, never edited by an agent.
- Plugin commands, named here in prose: /rs-sdlc drives a feature from issue to finished pull request; /rs-sdlc-setup restores this block; /rs-sdlc-new-service, /rs-sdlc-new-context, /rs-sdlc-issue, /rs-sdlc-plan, /rs-sdlc-implement, /rs-sdlc-review, /rs-sdlc-qa and /rs-sdlc-finish-pr run one step each.

<!-- rust-backend-sdlc:end -->
```

Verified in this session: appended to the template's `CLAUDE.md` and `AGENTS.md` with `.claude/rust-sdlc.yml` tracked, the template's `scripts/check-docs.sh` reports no violation in either file and markdownlint-cli2 reports 0 issues; without the tracked profile, rule 3 fires on both files; a backticked `/rs-sdlc-setup` fires rule 2 **[verified]**.

## Permissions Strategy

**Facts [verified in the Claude Code permissions documentation]:** rules are evaluated deny → ask → allow, first match wins; `Bash(x:*)` equals `Bash(x *)` and requires a space (or end) after `x`; a `*` without a preceding space matches any text; compound commands need every subcommand allowed; an allow rule does not match past a leading assignment of a variable outside Claude Code's known-safe list, while deny and ask rules match past any assignment; environment runners such as `docker compose exec` are not stripped, so their rules must name the inner command; `.claude/settings.local.json` is the per-user, git-ignored local scope and its allow rules apply without a trust step when untracked.

**Strategy.** `merge-settings.sh` writes the entries below into `permissions.allow` of `.claude/settings.local.json` (default `--file local`). It never touches `.claude/settings.json` when `protected-config.toml` lists it (the template does), never writes `deny`, `ask`, `defaultMode` or hooks, and never adds `bypassPermissions`. `<root>` = `resolve_plugin_root` (absolute, including the cache version directory, so re-run `/rs-sdlc-setup` after `claude plugin update`; older entries stay because the merge is union-only); `<uid>`/`<gid>` = `id -u`/`id -g` at merge time; `<port>` = `service.port`.

| # | Entry | Covers |
| --- | --- | --- |
| 1 | `Bash(make:*)` | every `make <target> [VAR=value]` call (template `ask` rules still prompt: ask before allow) |
| 2 | `Bash(RUN_IN_CONTAINER=1 make:*)` | prefix spelling typed by users or template docs |
| 3 | `Bash(RUN_IN_CONTAINER=1 git commit:*)` | hooked commits in container mode |
| 4 | `Bash(RUN_IN_CONTAINER=1 git push:*)` | hooked pushes in container mode |
| 5 | `Bash(git status:*)` | read |
| 6 | `Bash(git diff:*)` | read |
| 7 | `Bash(git log:*)` | read |
| 8 | `Bash(git add:*)` | staging |
| 9 | `Bash(git commit:*)` | commits (template denies `--no-verify`/`-n`: deny wins) |
| 10 | `Bash(git push:*)` | pushes (template denies force and `--no-verify`) |
| 11 | `Bash(git switch:*)` | branch creation |
| 12 | `Bash(git fetch:*)` | `git fetch origin <default_branch>` (D24) |
| 13 | `Bash(gh:*)` | issues, PRs, comments, statuses, runs |
| 14 | `Bash(bmalph:*)` | `bmalph implement`, `bmalph run`, `bmalph doctor` |
| 15 | `Bash(<root>/scripts/*)` | every plugin script and the library dispatcher |
| 16 | `Bash("<root>/scripts/*)` | the same when the path is written quoted |
| 17 | `Bash(docker info:*)` | Docker probe |
| 18 | `Bash(docker compose ps:*)` | container precondition (template already allows it) |
| 19 | `Bash(docker compose logs:*)` | bounded log read (template already allows it) |
| 20 | `Bash(docker compose exec -T --user <uid>:<gid> app cargo tree:*)` | FR-1 raw call (1), container route |
| 21 | `Bash(docker compose exec -T --user <uid>:<gid> app cargo metadata:*)` | FR-1 raw call (1), container route |
| 22 | `Bash(docker compose exec -T --user <uid>:<gid> app cargo xtask config-guard --list)` | FR-1 raw call (2), exact |
| 23 | `Bash(docker compose exec -T --user <uid>:<gid> app env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)` | FR-1 raw call (3), container route |
| 24 | `Bash(docker compose exec -T --user <uid>:<gid> app scripts/set-version.sh:*)` | FR-1 raw call (4), container route |
| 25 | `Bash(env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)` | FR-1 raw call (3), host |
| 26 | `Bash(scripts/set-version.sh:*)` | FR-1 raw call (4), host |
| 27 | `Bash(mkdir -p target/rust-sdlc/*)` | log, state and ledger directories |
| 28 | `Bash(id -u)` and `Bash(id -g)` (two entries) | uid/gid resolution for the container route |
| — | with `--with-qa-network`: `Bash(curl http://localhost:<port>/*)` and `Bash(curl http://127.0.0.1:<port>/*)` | QA, URL-first loopback probes (resolves PA-14: the no-space `*` form, because `Bash(curl http://localhost:<port>/:*)` would require a space after the slash) |

`cargo tree`, `cargo metadata` and `cargo xtask config-guard --list` on the host are already allowed by the template. Plugin-spawned headless sessions (`claude -p`) run with `--permission-mode acceptEdits`; Ralph's own `CLAUDE_PERMISSION_MODE="bypassPermissions"` default in `.ralph/.ralphrc` is documented truthfully in `docs/permissions.md` and never changed.

## Workflow Epic (decision: IN for v0.1.0, the cut line; ADR-18)

**Files:** `workflows/rs-sdlc-feature.js`, `workflows/rs-sdlc-review-panel.js`, `workflows/rs-sdlc-pr-until-green.js`, `workflows/rs-sdlc-fr-nfr-review.js`, `tests/lib/workflow-harness.mjs`, `tests/workflows.bats`, `tests/fixtures/workflows/*.json` (53), `docs/workflows.md`; plus a "Workflows" section in the plugin `README.md` and a "Workflow form" section in `docs/sdlc-loop.md`.

**Runtime rules (all four):** first statement `export const meta = {…}` as a pure literal (`name` = file stem, `description`, `whenToUse`, `phases: [{title, detail}]`) with no `}` at column 0 before the closing one; every `phase('<t>')` title appears in `meta.phases`; no `Date.now()`, `Math.random()`, argless `new Date()`; plain JavaScript, no filesystem API; agents get the plugin root block (`$CLAUDE_PLUGIN_ROOT` → newest `~/.claude/plugins/cache/*/rust-backend-sdlc/*/` by `sort -V` → `find "$HOME" -maxdepth 8 -path "*/plugins/rust-backend-sdlc/.claude-plugin/plugin.json"`; empty → `BLOCKED`); agent types `rust-backend-sdlc:<agent>`; results are `{result: 'SUCCESS' | 'SUCCESS-WITH-REPORT' | 'ESCALATED', …, degrade_notes: [], escalation?: '<7-field block>'}`; nested `workflow()` only from `rs-sdlc-feature` and from `rs-sdlc-pr-until-green` with `onGate: 'nested'` when top level; a nested call that throws escalates with the manual command line (A12).

| Workflow | Args | Phases | Agents | Counters | Return |
| --- | --- | --- | --- | --- | --- |
| `rs-sdlc-fr-nfr-review` (leaf) | string `[slug] [--slug s] [--base ref] [--summary text] [--pr n] [--head sha]` or `{slug, pr, head, base, summary, maxIterations}`; strict `PR_ARG` regex | Scope, Gate, Fix | scope (effort low), `fr-nfr-reviewer`, `rust-implementer` (≤ 4 fix groups) | gate iterations ≤ 5 | `{result, iterations, new_findings, fixed, requirement_source, advisory, degrade_notes}` |
| `rs-sdlc-review-panel` (leaf) | `[slug] [--slug s] [--base ref]` or `{slug, base, maxIterations, securityFamilies: ['all']}` | Scope, Review, Verify, Fix | scope + triage, `code-quality-reviewer`, `fr-nfr-reviewer`, `security-auditor` (only when the PA-5 paths changed), 3 refuters per finding (`correctness`, `standards`, `remedy`), `rust-implementer` fix groups keyed by the first three path segments (`crates/<group>/<context>`), ≤ 4 per iteration | iterations ≤ 5 | `{result, iterations, findings, fixed, carried, degrade_notes}` |
| `rs-sdlc-pr-until-green` | number, string (`<n>`, `#<n>`, PR URL, `--reviewers`, `--required-checks`, `--pr`) or `{pr, reviewers, requiredChecks, humanGatedChecks, maxFixRounds: 5, maxWaitRounds: 6, maxRequestRounds: 3, maxGateRounds: 3, waitSeconds: 540, onGate: 'nested'\|'return', carry: {counters, journal, degrade_notes}}`; `reviewers`/`requiredChecks`/`humanGatedChecks` default `null` (the sensor reads the profile) | Snapshot, Request reviews, Wait, Fix, FR/NFR gate, Publish | snapshot (runs `pr-state.sh … --json`), request (runs the sensor's `NEXT:` command), `ci-fixer`, `pr-comment-resolver`, publish (`make.format`, commit `fix(#N): <subject>` with FR-2 issue derivation, never the PR number, hooks on, 600 s timeouts) | fix 5, wait 6, request 3, gate 3 (carried) | `{result, pr, head, verdict, counters, journal, degrade_notes}`; with `onGate: 'return'` a `GATE` verdict returns `{result: 'GATE', pr, head, counters, journal, degrade_notes}` |
| `rs-sdlc-feature` (top level only) | task string (an issue URL becomes `issue`) or `{task, slug, issue, reviewers, maxImplementRounds: 5, maxQaLoops: 2}` | Setup check, Resolve plan, Stage, Implement, Review, FR/NFR gate, QA, Finish PR | setup check (`validate-profile.sh`, `setup-preflight.sh`), plan resolution (issue + bundle via the issue/plan command procedures), stage (`stage-planning-artifacts.sh`, `bmalph implement`, the two-part `.ralph/PROJECT_CONTEXT.md` check), `rust-implementer` rounds over `.ralph/@fix_plan.md` (layer-first; parallel stories run DB-free targets only; one serialized `verify <round>` agent runs the DB-backed targets), review panel, FR/NFR review, QA (`qa-manual-tester` after `make start` + `make migrate`), PR, pr-until-green with `onGate: 'return'` | implement rounds 5 (whole run), QA loops 2, feature-owned gate 3 | `{result, task, branch, issue_url, specs_dir, pr_url, stages, degrade_notes (always contains "bmalph run: not used (workflow path)"), escalation?}` |

**Hand-back loop (feature):** `pr-until-green({…, onGate: 'return', carry})` → on `GATE` run `rs-sdlc-fr-nfr-review {pr, head}` → publish its fixes → re-enter with `carry` (counters resume, never reset) → at most 3 gate rounds, then `ESCALATED`.

**Harness** (`tests/lib/workflow-harness.mjs`, react port, about 110 lines): `node tests/lib/workflow-harness.mjs [--as-child] <workflow.js> [scenario.json]`; exit 2 usage, 1 no meta literal / script threw / scenario gap (`scenario gap: no reply for agent label="<l>" prompt starts "<80 chars>"`) / schema gap (a reply lacking a top-level `required` key of `opts.schema`), 0 success; stdout pretty JSON `{meta, result | error, calls, phases, logs}`; scenario `{args, replies: [{match, reply}], workflows: {<name>: result | [results]}}` (regex on label or prompt, flag `s`; array replies consumed in order, clamped); `parallel` resolves throws to `null`; `workflow()` returns the scenario's canned result or throws `unknown workflow: <name>`; with `--as-child` every `workflow()` throws `workflow() nesting is one level only`; `budget = {total: null, spent: () => 0, remaining: () => Infinity}`.

**Scenario files (53):**

| Prefix | Files |
| --- | --- |
| `feat-` (14) | `feat-happy`, `feat-setup-fails`, `feat-null-slug`, `feat-incomplete-story`, `feat-no-nested`, `feat-gate-escalated`, `feat-qa-skipped-accepted`, `feat-qa-skipped-rejected`, `feat-implementer-blocked`, `feat-staging-order`, `feat-staging-context-missing`, `feat-gate-handback`, `feat-gate-handback-exhausted`, `feat-verify-serialized` |
| `fnr-` (15) | `fnr-advisory`, `fnr-bad-pr`, `fnr-converges`, `fnr-degraded`, `fnr-exhausted`, `fnr-fail-no-findings`, `fnr-fix-blocked`, `fnr-head-mismatch`, `fnr-no-source`, `fnr-no-specs`, `fnr-pr-source`, `fnr-scope-blocked`, `fnr-skipped-runner`, `fnr-transport`, `fnr-transport-twice` |
| `pug-` (16) | `pug-blocked`, `pug-carry`, `pug-coderabbit-interval`, `pug-fix-exhausted`, `pug-full-loop`, `pug-gate`, `pug-gate-escalated`, `pug-gate-exhausted`, `pug-human-gated-blocked`, `pug-malformed-ready`, `pug-not-approved`, `pug-ready`, `pug-ready-without-gate`, `pug-return-gate`, `pug-silent-reviewer`, `pug-wait-exhausted` |
| `rp-` (8) | `rp-all-refuted`, `rp-carry`, `rp-converges`, `rp-exhausted`, `rp-missing-lens`, `rp-scope-blocked`, `rp-security-skipped`, `rp-unverified` |

## Repository Wiring

### `.claude-plugin/marketplace.json` (append to `plugins`, keep the other entries untouched)

```json
{
  "name": "rust-backend-sdlc",
  "description": "<byte-identical to plugin.json description>",
  "author": {
    "name": "VilnaCRM",
    "url": "https://github.com/VilnaCRM-Org"
  },
  "category": "development",
  "source": "./plugins/rust-backend-sdlc"
}
```

### Root `README.md`

- Install block: add the line `claude plugin install rust-backend-sdlc@vilnacrm-plugins` after the php line.
- Plugins table: add the row `| [rust-backend-sdlc](plugins/rust-backend-sdlc/) | Full-SDLC automation for Rust microservices built from the Rust service template: one-command service creation and bounded-context scaffolding → GitHub issue → BMAD planning → bmalph/Ralph implementation → multi-lens review + BMAD FR/NFR gate → black-box REST/GraphQL QA → CI auto-fix → finished PR. |` after the react row.

### `.github/workflows/ci.yml`

1. `on.push.tags`: `['php-backend-sdlc-v*', 'react-frontend-sdlc-v*', 'devops-sdlc-v*', 'rust-backend-sdlc-v*']`.
2. `profile-keys-check`: replace `PLUGIN=plugins/php-backend-sdlc` and the body with a loop `for PLUGIN in plugins/php-backend-sdlc plugins/rust-backend-sdlc; do … done` around the existing per-plugin logic (no skills → `continue` with a note; missing schema → fail); `fail` accumulates across plugins. The explicit list (not `plugins/*`) keeps `devops-sdlc` and `react-frontend-sdlc` out (A11).
3. `generalization-audit`: the same explicit loop; the scanned directories become `skills commands agents scripts workflows` (missing directories ignored) and the name filter adds `-o -name '*.js'`; the `_bmad`/`.ralph` check runs per plugin.
4. `bats`: before "Run bats suites" add:

```yaml
      - name: Install template-compatibility linters (rust-backend-sdlc K7 cases)
        run: |
          set -euo pipefail
          python3 -m pip install --user yamllint==1.38.0 typos==1.52.0
          npm install --prefix "$RUNNER_TEMP/k7" prettier@3.9.10 markdownlint-cli2@0.24.0
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
          echo "$RUNNER_TEMP/k7/node_modules/.bin" >> "$GITHUB_PATH"
```

No other job changes: `manifest-validate`, `markdown-lint`, `shellcheck` and `frontmatter-check` already iterate `plugins/*` (fixture Markdown ships as `*.md.tpl`, so `markdown-lint` never sees it). `tools/plugin-quality` is untouched (ADR-19).

## Test Architecture

### Layout and helpers

- `tests/lib/helpers.bash` (loaded by every suite with `load lib/helpers`): `common_setup` (sets `PLUGIN_ROOT`, prepends `tests/fixtures/bin` to `PATH`, points every `STUB_*_LOG` into `$BATS_TEST_TMPDIR`, exports `STUB_DOCKER_INFO_EXIT=1` so Docker is unreachable by default, unsets `CLAUDE_PLUGIN_ROOT`); `rr_materialize DEST [ORIGIN_SLUG]` (copies `tests/fixtures/rust-repo/` to DEST, renames every `*.tpl` by dropping the suffix and `gitignore` → `.gitignore`, `git init -q -b main`, commits once as `acme <ci@example.invalid>`, sets `origin` to `https://github.com/${ORIGIN_SLUG:-acme/billing-service}.git`); `sandbox_path TOOL…` (a PATH with only the named tools linked, for genuine absence); `k7_require TOOL` (`skip "<tool> not installed (runs in CI)"`); `bundle_write DIR [--blocked]` (writes a valid planning bundle at runtime; `--blocked` puts `NO-GO` in the readiness file); `mutate_profile FILE KEY VALUE` and `drop_profile_key FILE KEY` (line edits on the block-style golden profile); `docs_rules FILE…` (runs `python3 -I tests/lib/docs-rules.py --root <repo> FILE…`); `skip_if_root` (permission cases).
- `tests/lib/docs-rules.py`: static port of the template's docs-check rules 1–4 (Makefile targets from `^[a-zA-Z0-9_-]+:.*##[[:space:]]`, slash commands vs `.claude/commands/`, backticked paths vs tracked top-level names and `git check-ignore`, gate-target lists/fences outside the verification markers) plus invariant (e) (the literal assembled from two halves and the fixture's `TEMPLATE_REPOSITORY` name); prints `(<rule>) <file>:<line>: <message>`; exit 0/1.

### Stub executables (`tests/fixtures/bin/`)

| Stub | Controls | Behaviour |
| --- | --- | --- |
| `claude` | `STUB_CLAUDE_VERSION` (`2.1.322`), `STUB_CLAUDE_RESTRICTED` (`1`), `STUB_CLAUDE_EXIT` (`0`), `STUB_CLAUDE_OUTPUT`, `STUB_CLAUDE_OUTPUTS_DIR` (n-th call prints `<dir>/<n>.json`, last repeats), `STUB_CLAUDE_LOG` | `--version`; `--help` lists `--restricted` when enabled; otherwise prints the JSON reply and logs argv and selected env (`GH_TOKEN`, `GH_CONFIG_DIR`) |
| `gh` | `STUB_GH_VERSION` (`2.62.0`), `STUB_GH_AUTH_EXIT`, `STUB_GH_EXIT`, `STUB_GH_OUTPUT`, `STUB_GH_ROUTES` (file of `<argv glob>\t<exit>\t<stdout file>` lines, first match wins), `STUB_GH_STRICT` (`1` → unmatched call exits 9), `STUB_GH_CLONE_SOURCE` (directory copied and committed on `repo clone`), `STUB_GH_LOG` | logs `gh <argv>` and stdin for `-F body=@-` |
| `bmalph` | `STUB_BMALPH_VERSION` (`2.11.0`), `STUB_BMALPH_EXIT`, `STUB_BMALPH_DOCTOR_EXIT`, `STUB_BMALPH_OUTPUT`, `STUB_BMALPH_LOG` | `--version`, `doctor`, `implement`, `run` |
| `cargo` | `STUB_CARGO_EXIT`, `STUB_CARGO_LOG` | records calls (generate-profile asserts 0 calls) |
| `make` | `STUB_MAKE_VERSION_LINE` (`GNU Make 4.4.1`), `STUB_MAKE_EXIT`, `STUB_MAKE_LOG` | `--version`; records calls |
| `docker` | `STUB_DOCKER_INFO_EXIT` (`1`), `STUB_DOCKER_LOG` | `docker info` exit code; records calls |
| `bin-kislyuk/yq` | — | prints `"array"` for any expression, `yq 3.4.3` for `--version`; on `PATH` only in the cases that need it |

### Suites, floors and focus (floors total 463 ≥ 460; post-cut 418 ≥ 415)

| Suite | Floor | Focus (every flag, exit code, refusal and `--help` of its script) |
| --- | --- | --- |
| `common-lib.bats` | 36 | every function incl. dispatcher (8 names, no-arg exit 64), `ledger_write` schema refusals; `have_yq` rejects the kislyuk stub; YAML parity (`SDLC_FORCE_PYTHON_YAML=1`); `toml_*` on the fixture; `validate_context_name` (AC-14.1 list); `resume_point` (AC-3.4 a); `state_*`; `redact` one case per rule; `derive_issue_number` priority; `is_commit_subject` (AC-2.1); bash floor via `RUST_SDLC_BASH_VERSION=4.3` |
| `setup-preflight.bats` | 23 | each check PASS/FAIL with remediation; `--report` table and summary; under-version stubs (gh 1.9, bmalph 2.10.0, claude without `--restricted`, python 3.10 via sandbox, make 3.81, git 2.29); bmalph WARN path; kislyuk yq without/with PyYAML; dirty tree INFO |
| `generate-profile.bats` | 30 | golden byte-equality; one fallback case per optional source; 0 `cargo`/`make`/`gh` calls; diff-and-keep, `--refresh`, `--stdout`, symlink and non-regular refusals; ADR-24 preserve per key; AC-6.5 CI derivation incl. service variant; AC-6.6 container switch (4 combinations + flag + preserve); AC-6.7 contexts; looser-gate WARN; K7 yamllint + Prettier; 5 s timing; 3 parity cases |
| `validate-profile.bats` | 30 | golden valid (both backends); 12 quality rejections (floors 99, ceilings 1) + 101 floor + 20-digit ceiling; missing key per group + 3 `make.*`; null where allowed vs not; enum, type, format, unknown key, subset rule; malformed YAML without traceback; `make.start: 'start; rm -rf /'` |
| `inject-governance.bats` | 30 | create, append, idempotent (checksums), in-place replace, duplicates, orphan, inverted, fenced markers, CRLF, verification-marker placement, `--diff`, symlink/non-regular refusals; AC-8.2 docs-rules and invariant (e); K7 markdownlint + typos; block text equals the architecture's exact text |
| `merge-settings.bats` | 15 | protected settings untouched (`--file shared` exit 1 + JSON; default mode); union and order; second run byte-identical; `--with-qa-network` loopback entries with the profile port; malformed JSON; no `bypassPermissions`/`defaultMode`/non-loopback host; uid:gid literals |
| `new-service.bats` | 30 | the five modes with gh routes (`is_template` true/false, path, in-place, dry-run); argv order (no `--clone`, poll, clone); existing repository with matching / mismatched origin; dirty template path; every customize step golden diff; second run only `UNCHANGED:`/`SKIP:`; specs from `source.json`; both flavours + citation repair (AC-12.5) + fixed-variant `UNCHANGED`; defaults (AC-12.6); config override order and malformed config exit 2; 0 commit/push calls; K7 on README, CHANGELOG, `bmalph/config.json` |
| `stage-planning-artifacts.bats` | 12 | happy path file set incl. `technical-research.md`; stale removal; re-run identical; the six refusals; `--dry-run` |
| `ai-review-loop.bats` | 23 | php cases ported + profile agents/base defaults + argv assertion + parity |
| `fr-nfr-gate.bats` | 50 | react cases ported (sources, fail-closed, advisory, status context, comment only when n > 0, containment, isolation argv and env, `--restricted` absent, retries, malformed last line, byte budgets) + 7 baseline ids in the prompt |
| `get-pr-comments.bats` | 31 | php cases ported (pagination, filters, JSON shape, parity, validation) |
| `post-review-findings.bats` | 41 | php cases ported + ledger `schema_version` cases + markers `rust-sdlc-review:<lens>` |
| `pr-state.bats` | 30 | react cases ported + human-gated by check name (AC-21.3), service-added failing check → `FIX`, profile defaults, check names with spaces |
| `request-ai-reviews.bats` | 17 | react cases ported + profile default reviewers + harmonised validation |
| `component-counts.bats` | 20 | the CC assertions below |
| `workflows.bats` | 45 | meta literal and phases for 4 files; banned clock/random calls; agent types exist; call graph depth ≤ 1; leaves under `--as-child`; P1–P7 and generalization grep over `workflows/`; commit literals; one case per scenario (53) |

### `component-counts.bats` assertions

CC-01 10 commands with the exact stems; CC-02 7 agents with names, models and tools of "Agent Contracts"; CC-03 28 skill directories with the exact names, each with `SKILL.md`, `name` = directory; CC-04 2 meta-guides without frontmatter; CC-05 13 executable scripts + executable `lib/common.sh`; CC-06 4 workflows starting `export const meta = {`; CC-07 9 docs; CC-08 16 suites and every per-suite floor (`grep -c '^@test'`); CC-09 frontmatter keys of commands, agents, skills; CC-10 command spine, `MAX_ITERATIONS=5`, `validate-profile.sh` in the first fence (except setup, new-service), 7 fields in every escalation block; CC-11 background and container sentences in the 9 commands that run `make` or git (all except `rs-sdlc-issue`); CC-12 exit strings byte-identical across stage command, `rs-sdlc.md`, `docs/sdlc-loop.md`; CC-13 command tokens (AC-1.4) with the path negative case; CC-14 commit-subject literals (AC-2.2); CC-15 P1–P7 with the exemptions and the positive cases; CC-16 profile keys (AC-5.2, AC-6.4) with the five-name negative case; CC-17 setup steps (AC-4.1, AC-4.4); CC-18 new-service S1–S14 (AC-11.1); CC-19 new-context (AC-14.2); CC-20 issue, plan, implement, review, QA, finish-pr content (AC-15.1, AC-16.1, AC-18.1, AC-18.2, AC-19.1, AC-20.2, AC-21.1); CC-21 agent tokens (AC-23.1 to AC-29.1); CC-22 counterparts' `## Repository precedence` and FR-31 tokens; CC-23 decision guide (AC-32.2); CC-24 `plugin.json` and the marketplace entry; CC-25 README commands, doc links and version floors equal to `docs/setup-walkthrough.md`; CC-26 degrade matrix ids and outcome vocabulary; CC-27 relative links in `docs/` resolve; CC-28 generalization grep over `skills commands agents scripts workflows` and the template slug only in `config/`; CC-29 no `_bmad`/`.ralph` components, no `*.md` under `tests/fixtures`; CC-30 shared names byte-identical with `php/` and `react/` scripts; CC-31 script skeleton, `Usage:` and exit codes in the header, `--help` exit 0, banned constructs absent; CC-32 no `make logs` outside prohibition lines, no raw `cargo` outside the FR-1 list; CC-33 state-comment marker and columns (AC-3.3), run report fields (AC-3.1), resume table (AC-3.2); CC-34 counters and labels identical (AC-21.1); CC-35 Q1–Q15 mapping identical in `rs-sdlc-review.md` and `code-quality-reviewer.md`; CC-36 suffix spelling: no `RUN_IN_CONTAINER=1 make` and no `COMMIT_TITLE=… make` in `commands/ agents/ skills/ workflows/` (ADR-13).

### Backend and environment matrix

- YAML: CI has mikefarah yq (yq path), the session host has kislyuk yq (python path); four suites carry explicit `SDLC_FORCE_PYTHON_YAML=1` parity cases; yq-only cases gate on `have_yq`, never on `command -v yq`.
- JSON: jq-absent cases use `sandbox_path` without `jq`.
- K7 (template linters): cases in `generate-profile.bats`, `inject-governance.bats`, `new-service.bats` run with the fixture's copied configs; skipped locally with the reason when a tool is absent; always run in CI (bats job installs them).
- Root: permission-denied cases `skip_if_root` with a reason.
- Timing: `generate-profile.sh`, `validate-profile.sh`, `inject-governance.sh`, `merge-settings.sh` each finish in ≤ 5 s on the fixture (bats `SECONDS` check).

## Documentation Set (FR-40, FR-41)

| File | Content contract |
| --- | --- |
| `README.md` (plugin) | install lines (`claude plugin marketplace add VilnaCRM-Org/claude-plugins`, `claude plugin install rust-backend-sdlc@vilnacrm-plugins`); prerequisites with the NFR-16 floors (identical to `docs/setup-walkthrough.md`); the 10 commands with one-line purpose; quick start (new service → setup → feature); "Workflows" table (4 rows, all six sensor verdicts named); links to all 9 docs |
| `docs/profile-schema.md` | conventions; every key of the three schema tables with type, R/O, nullable, fallback, format, detection source, refresh, consumers; "null means absent; omitted means error"; detection-source table backticking `architecture.toml`, `persistence.rs`, `clippy.toml`, `deny.toml`, `protected-config.toml`, `make/gates.mk`, `docs/repository-settings-service.md`; the quality-bar derivation table; validation rules V1–V11; the annotated example of this document verbatim |
| `docs/setup-walkthrough.md` | install → `/rs-sdlc-setup` → single commit; protected settings and `.claude/settings.local.json`; dirty-tree degrade; `--exec`; re-run after template sync (J6) and after `claude plugin update`; user-scope install recommendation (ADR-21); version floors |
| `docs/sdlc-loop.md` | stage table with the exit strings byte-identical; counters A/B/C/W/R with labels `ci_fix`, `comment_resolution`, `fr_nfr_gate`, `wait`, `request`; state comment format and resume rules; run report; escalation block; background rule; "Workflow form" section |
| `docs/permissions.md` | ADR-6 and the full "Permissions Strategy" table; deny > ask > allow; `ask` rules in headless runs (`not run (ask rule)`); Ralph's `bypassPermissions` default stated truthfully, never changed |
| `docs/degrade-matrix.md` | D1–D25 exactly as "Degrade Matrix" (outcome words only `SUCCESS`, `SUCCESS-WITH-REPORT`, `ESCALATED`) |
| `docs/release-process.md` | ADR-9 policy, tag namespace, version bump rules, marketplace source switch rule, a `## Changelog` section with one `### X.Y.Z — YYYY-MM-DD` entry per release (first: 0.1.0) |
| `docs/new-service-walkthrough.md` | S1–S14 with sample `DONE:`/`NEXT:` output, the traps (OpenAPI title, directory name = Compose project, version via `scripts/set-version.sh`, sync flavour, citation repair), and an empty "K9/K13 record" section for the post-release run |
| `docs/workflows.md` | the 4 workflows (args, phases, counters, returns), hand-back contract, harness usage and `--as-child`, fidelity gaps |
| `docs/testing/test-strategy.md` | surfaces, the 16 suites and floors, fixtures and stubs, K7 tool pins, skip policy, the D1–D25 → test-case map, the AC-43.2 negative check (seeding the denylisted organization token into a skill body fails `generalization-audit`) |

## Degrade Matrix

Outcome vocabulary is closed (`SUCCESS`, `SUCCESS-WITH-REPORT`, `ESCALATED`); an absent capability ends `SUCCESS-WITH-REPORT`, a mapped capability that cannot run or a safety block ends `ESCALATED`; degrade paths never loop and never fake a pass. Each row names the component that detects it and the test that proves it.

| # | Condition | Detected by | Outcome | Proven by |
| --- | --- | --- | --- | --- |
| D1 | `make.<key>: null` | every command and agent | SUCCESS-WITH-REPORT (`not run (capability absent)`) | CC-20 tokens; `rs-sdlc-review` Q7 null → static lane |
| D2 | Docker unreachable | `docker info` / template message in a log | ESCALATED (implement, review, QA with `make.start`, new-context C12); SUCCESS-WITH-REPORT (new-service S8) | CC-11, CC-19, CC-20 |
| D3 | no host toolchain, container mode off | `command -v cargo`, profile | SUCCESS-WITH-REPORT (setup step 8) / ESCALATED (loop stages, new-context) | CC-17; `setup-preflight.bats` cargo INFO |
| D4 | `.claude/settings.json` protected | `merge-settings.sh` (`protected-config.toml`) | SUCCESS-WITH-REPORT | `merge-settings.bats` |
| D5 | dirty tracked tree at setup | `git status --porcelain --untracked-files=no` | SUCCESS-WITH-REPORT (setup) / ESCALATED (stage 0 while `_bmad/` absent) | `setup-preflight.bats`, CC-17 |
| D6 | bmalph absent but installable | preflight | SUCCESS | `setup-preflight.bats` |
| D7 | no AI reviewer | `review.reviewers: []`, `review.coderabbit: false` | SUCCESS-WITH-REPORT (`ai-review-loop.sh` as source) | CC-20; `pug-silent-reviewer` |
| D8 | no CI | `ci.provider: null` or zero checks | SUCCESS-WITH-REPORT (`## Status: SKIPPED-NO-CI`) | `pr-state.bats` nochecks; CC-21 |
| D9 | failing human-gated check / unlabelled breaking change | `pr-state.sh` / review Q14 | ESCALATED (label named, never applied) | `pr-state.bats` AC-21.3; `pug-human-gated-blocked` |
| D10 | `gh` unreachable | `gh api` failure | ESCALATED (issue, finish-pr) / SUCCESS-WITH-REPORT (resume from cache) | `common-lib.bats` `resume_point --cache`; CC-33 |
| D11 | no PR at review time | `gh pr view` failure | SUCCESS-WITH-REPORT (gate `--advisory`) | `fr-nfr-gate.bats` advisory; `fnr-advisory` |
| D12 | comment publishing off | `capabilities.publish_pr_comments: false` | SUCCESS-WITH-REPORT | `post-review-findings.bats` |
| D13 | `ask` rule in a headless run | permission denial on an `ask` target | SUCCESS-WITH-REPORT (`not run (ask rule)`) | CC-20 (C8 text) |
| D14 | call may exceed 600 s | ADR-13 allowlist | SUCCESS (designed path) | CC-11 |
| D15 | claude without `--restricted` | `claude_supports_restricted` | ESCALATED (preflight FAIL; gate fails fast) | `setup-preflight.bats`, `fr-nfr-gate.bats` |
| D16 | kislyuk `yq` on host | `have_yq` probe | SUCCESS (python fallback) | `common-lib.bats`, `setup-preflight.bats` |
| D17 | template flag off | `is_template` false | SUCCESS-WITH-REPORT (clone-and-push, `IMPORT_PENDING:`) | `new-service.bats` |
| D18 | sync flavour undecided (headless) | flag omitted | SUCCESS-WITH-REPORT (`SKIP:` + `NEXT:`) | `new-service.bats` |
| D19 | governance markers missing | marker grep | ESCALATED (setup wording) | CC-20, CC-33 |
| D20 | not template-derived | A1 markers | SUCCESS-WITH-REPORT (capabilities off) | `generate-profile.bats`, `setup-preflight.bats` |
| D21 | workflow name unresolved | nested `workflow()` throws | ESCALATED (manual command line) | `feat-no-nested` |
| D22 | Ralph breaker trips | `---RALPH_STATUS---` / `.ralph/` state | ESCALATED (never reset, no second run) | CC-20 (AC-18.2); `feat-implementer-blocked` (workflow analogue) |
| D23 | protected change needed | implementer/reviewer finding | ESCALATED (`approved-config-change` + `ALLOW_PROTECTED_CONFIG_EDIT=1`) | CC-21 |
| D24 | base ref unavailable | `git rev-parse <ci.base_ref>` | SUCCESS-WITH-REPORT (`base_ref=HEAD` after one fetch) | CC-20 |
| D25 | container mode, `app` not running | `docker compose ps --status running --quiet app` | SUCCESS (stack started) / SUCCESS-WITH-REPORT (setup step 8, new-service) / ESCALATED (loop stages, new-context) | CC-11 |

## Release and Versioning

- **v0.1.0 release gate:** K1–K8 of the PRD (lint 0 for all plugins; every `ci.yml` job green with the Rust plugin covered and the tag filter present; counts 10/7/28/2/13+lib/4/9; 16 suites ≥ 463 floors, 0 failures; 0 shellcheck and markdownlint findings; 0 denylist hits; K7 cases green in CI; harness green with depth ≤ 1).
- **Tag** `rust-backend-sdlc-v0.1.0` on the merge commit of `main`; CI's `manifest-validate` tag step checks `plugin.json` version = tag version.
- **Version bumps:** every release changes `plugin.json` `version` and appends `docs/release-process.md` `## Changelog`; MAJOR/MINOR/PATCH per ADR-9; a profile key addition is MINOR and requires the generator, the validator, `docs/profile-schema.md`, the golden profile and CC-16 in the same change; a `schema_version` bump is MAJOR and requires a migration note.
- **Marketplace source:** relative `./plugins/rust-backend-sdlc` until v1.0.0 or the first external consumer; then `{"source": "git-subdir", "url": "https://github.com/VilnaCRM-Org/claude-plugins", "path": "plugins/rust-backend-sdlc", "ref": "rust-backend-sdlc-vX.Y.Z", "sha": "<commit>"}` together with a `manifest-validate` change allowing that shape for this plugin.
- **Post-release evidence:** K9/K13 recorded in `docs/new-service-walkthrough.md`, K10 run report appended to `docs/sdlc-loop.md` or a new `docs/evidence/` file in a PATCH release (not counted in the 9 docs of v0.1.0).

## Risks

| # | Risk | Likelihood / impact | Mitigation in this architecture |
| --- | --- | --- | --- |
| R1 | Claude Code permission matching differs from the documented semantics (quoted script paths, uid literals) | medium / medium | both quoted and unquoted plugin-root entries; literal uid:gid; suffix make variables; prompts are still answerable interactively; headless denials are reported verbatim (D13 wording) |
| R2 | Template drift (renamed target, marker, job table format) | medium / medium | runtime reads (`make ci-list`, `CI_*_TARGETS`, `docs/repository-settings.md`), null-means-absent, WARN-only detection (ADR-17), golden fixture copied from the template at `3e0bd3e` |
| R3 | Workflow runtime rejects nesting or name resolution | medium / low | hand-back contract, `--as-child`, call-graph test, graceful escalation (D21); epic is the cut line |
| R4 | Parallel implementers clobber the shared test database | high / high | DB-free targets only in parallel, one serialized verify step, carried by `## Constraints` into Ralph (ADR-10, ADR-21) |
| R5 | bmalph changes its section extraction or tech-stack sniffing | low / medium | `## Constraints` and `## Tech Stack` headings exactly as bmalph matches them; implement verifies `.ralph/PROJECT_CONTEXT.md` before running |
| R6 | Fixture realism gap (stub repo passes, real template fails) | medium / medium | fixture configs are byte copies of the template's lint configs and job tables; K7 linters in CI; post-release K9–K13 on a real copy |
| R7 | Long gates exceed tool limits | high / medium | background-and-poll by allowlist (ADR-13); `make ci` never one call |
| R8 | Generalization leak through the default slug | low / high | slug only in `config/`; CC-28 and CI audit over five directories |

## Architecture Validation

**Coherence.** The profile is the only shared state; every script interface used by a command, agent or workflow is defined once in "Script Contracts"; exit strings, counters, Q-row mapping and markers are single-sourced and pinned by CC-12, CC-33 to CC-35; the forbidden-pattern set P1–P7 is defined once (PRD NFR-5) and enforced by CC-15.

**Requirement coverage.**

| Requirement | Architectural home |
| --- | --- |
| FR-1, FR-2 | Implementation Patterns (output vocabulary, escalation block, git rules), ADR-13, shared command contract |
| FR-3 | `/rs-sdlc`, ADR-14, `resume_point`, `state_*` |
| FR-4 to FR-10 | `/rs-sdlc-setup`; profile schema; `generate-profile.sh`, `validate-profile.sh`, `inject-governance.sh`, `merge-settings.sh`, `setup-preflight.sh`; Governance Block; Permissions Strategy |
| FR-11 to FR-13 | `/rs-sdlc-new-service`, `new-service.sh`, `config/new-service.defaults.json`, ADR-12, ADR-20 |
| FR-14 | `/rs-sdlc-new-context`, `validate_context_name`, ADR-15 |
| FR-15 to FR-21 | stage command contracts, `stage-planning-artifacts.sh`, ADR-5, ADR-10 |
| FR-22 to FR-29 | Agent Contracts |
| FR-30 to FR-32 | Skill Library |
| FR-33 to FR-39 | Script Contracts |
| FR-40, FR-41 | Plugin Manifest, Documentation Set |
| FR-42 | Test Architecture |
| FR-43 | Repository Wiring |
| FR-44 | Workflow Epic |
| NFR-1 | idempotence rules in every writing script; second-run cases per suite |
| NFR-2 | ADR-12, CC-28, CI audit loop |
| NFR-3 | Degrade Matrix |
| NFR-4 | ADR-2, ADR-7, Quality bars, V11, CC-15 (P6) |
| NFR-5 | Permissions Strategy, CC-15, agent git ownership |
| NFR-6 | guards and counters per command; workflow counters; script caps; `while true` ban |
| NFR-7 | script conventions, backend matrix, bash floor in the library |
| NFR-8 | suite floors, CC-08, CI jobs |
| NFR-9 | run report, escalation block, ledgers (ADR-16), logs path, state comment |
| NFR-10 | `redact`, `claude_run_isolated`, least-privilege tools, loopback QA entries, containment checks |
| NFR-11 | file tree, CC-01 to CC-07, CC-29 |
| NFR-12 | ADR-5, decision guide docs-only class (6) |
| NFR-13 | emission format, Governance Block, K7 cases |
| NFR-14 | ADR-13, timing cases |
| NFR-15 | runtime reads, CC-30 |
| NFR-16 | `setup-preflight.sh` checks, CC-25 |

**PRD open questions resolved.**

| PRD open question | Resolution |
| --- | --- |
| 1 Allowlist spelling (PA-14) | Permissions Strategy: suffix make variables; `Bash(curl http://localhost:<port>/*)` no-space form; prefix-form entries kept for user-typed commands |
| 2 State-comment concurrency | ADR-14 (re-read `updated_at`, one re-merge, then `ESCALATED`) |
| 3 Ledger schema versioning | ADR-16 (`schema_version: 1`) |
| 4 Template-detection evolution | ADR-17 (WARN, capability false) |
| 5 Workflow ↔ script data exchange | ADR-18 (agents run scripts; `--json` and verdict lines; no shared JS module) |
| 6 Upstream citation fix | ADR-20 (repair in `new-service.sh`; `UNCHANGED` once fixed upstream) |
| 7 Plugin agents inside Ralph's sessions | ADR-21 (both branches in `## Constraints`; user-scope install recommended) |
| 8 Container-route permission spelling | ADR-13 + entries 20–24 (uid:gid resolved to literals; one entry per inner command) |

**Gap analysis.** No FR, NFR, goal or journey lacks a home. Remaining implementation-level choices (exact prose of skills and commands, fixture file contents) are constrained by the token tests and golden files above.

## Open Questions

None blocking. Two items are deliberately left to post-release evidence: (a) whether the quoted plugin-root entry (Permissions Strategy entry 16) is ever needed in practice, measured in K10; (b) the measured count of skill bodies loaded for a docs-only diff (NFR-12 post-release form), also in K10.
