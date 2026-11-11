# Task Framing: rust-backend-sdlc Plugin

> Input to the BMAD planning chain. Written by the main agent acting as the user
> surrogate. Every planning and implementation subagent reads this first.

## The request

"Using BMAD and BMALPH, implement fully the new plugin for Rust based on the
rust service template, to allow users of this plugin to easily create new
Rust-based microservices and build features using it. The reference is
`plugins/php-backend-sdlc` of the claude-plugins marketplace."

## Repositories (local checkouts)

| Path | Role |
| --- | --- |
| `/home/user/claude-plugins` | The marketplace. The new plugin goes to `plugins/rust-backend-sdlc/`. Branch `claude/lucid-dirac-v73lfa`. |
| `/home/user/claude-plugins/plugins/php-backend-sdlc` | THE REFERENCE PLUGIN (structure, contracts, scripts, tests, docs). Mirror it. |
| `/home/user/claude-plugins/plugins/react-frontend-sdlc` | Newest sibling plugin: adds `workflows/*.js` (Workflow-tool scripts), `scripts/pr-state.sh`, `scripts/request-ai-reviews.sh`, `tests/lib/workflow-harness.mjs`, `tests/workflows.bats`. Source for the optional workflow epic. |
| `/home/user/claude-plugins/specs/autonomous/2026-06-09-php-backend-sdlc-plugin` | The BMAD bundle that produced the reference plugin. Use its depth and structure as the bar. |
| `/home/user/claude-plugins/tools/plugin-quality` | Tier-1 prompt lint (`python3 tools/plugin-quality/lint/lint_all.py`) that every plugin must pass with 0 findings. |
| `/home/user/claude-plugins/.github/workflows/ci.yml` | Repo CI: manifest-validate, markdown-lint, shellcheck, bats, frontmatter-check, profile-keys-check (php-only today), generalization-audit (php-only today). |
| `/home/user/rust-service-template` | The Rust service template the plugin serves (VilnaCRM-Org/rust-service-template). Read-only for planning. |

## Identity decisions (fixed — do not re-litigate)

| Item | Value |
| --- | --- |
| Plugin name / dir | `rust-backend-sdlc` / `plugins/rust-backend-sdlc/` |
| Version | `0.1.0`, license MIT, author VilnaCRM (same shape as php `plugin.json`) |
| Command prefix | `rs-sdlc` (php uses `sdlc`, react `fe-sdlc`, devops `do-sdlc`; prefixes avoid collisions when several plugins are installed) |
| Commands | `/rs-sdlc` (orchestrator), `/rs-sdlc-setup`, `/rs-sdlc-new-service`, `/rs-sdlc-new-context`, `/rs-sdlc-issue`, `/rs-sdlc-plan`, `/rs-sdlc-implement`, `/rs-sdlc-review`, `/rs-sdlc-qa`, `/rs-sdlc-finish-pr` |
| Project profile | `.claude/rust-sdlc.yml` in the target repository, `schema_version: 1` |
| Governance markers | `<!-- rust-backend-sdlc:begin -->` / `<!-- rust-backend-sdlc:end -->` in `CLAUDE.md` and `AGENTS.md` |
| Managed issue label | `rust-backend-sdlc` |
| Log prefix | `[rust-sdlc]` |
| Release tag namespace | `rust-backend-sdlc-vX.Y.Z` |
| Bundle dir | `specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/` |

## Goals

- G1 — Create a new Rust microservice from the template in one guided command
  (`/rs-sdlc-new-service`): repository creation from the template (GitHub
  "template" flow via `gh repo create --template`, or a local path for offline
  use), the template's own `docs/new-service.md` steps automated where they are
  deterministic (package identity in `[workspace.package]`, `bmalph/config.json`,
  README badges/intro, CHANGELOG reset, planning bundle reset, sync-flavour
  choice), judgment steps guided (keep/remove example context), then
  `/rs-sdlc-setup`.
- G2 — Build features through the full SDLC loop (issue → BMAD plan →
  bmalph/Ralph implementation → multi-lens review + BMAD FR/NFR gate → QA
  against the running service (REST + GraphQL + health/ping) → finished PR
  (CI green + AI review comments resolved)), resumable, bounded, with the
  SUCCESS / ESCALATED report contract of the php plugin.
- G3 — Add bounded contexts easily (`/rs-sdlc-new-context`): `make new-context
  group=<g> context=<c>` plus the template's wiring checklist (workspace deps,
  `service` crate wiring, `workspace.dsl`, migration, sqlx metadata, contract
  snapshots), verified by the gates.
- G4 — Every quality bar comes from the template's gates and is raise-only
  (the plugin may tighten, never relax): 100% line+function coverage,
  zero surviving mutants on changed code, clippy `-D warnings` with
  pedantic/nursery/cargo groups, complexity limits from `clippy.toml`, zero
  architecture violations, contract snapshots current, no breaking OpenAPI /
  GraphQL change without the `approved-breaking-change` label.

## Template facts the plugin must respect (verified by the main agent)

- One command surface: every tool runs through `make` (`make help`). Gate
  order = `make ci-list`; `make ci` runs 7 stages (`ci-preflight`,
  `ci-static-analysis`, `ci-tests`, `ci-contracts`, `ci-mutation`,
  `ci-delivery`, `ci-cli`). `RUN_IN_CONTAINER=1` runs targets in containers.
- Layout: `crates/<group>/<context>/{domain,application,infrastructure}`,
  plus `crates/shared/*`, `crates/internal/health-check/*`, composition root
  `crates/service`, `tests/e2e` (cucumber, `features/*.feature`),
  `tests/support`, `xtask` (`cargo xtask arch`, `config-guard`, `scaffold`).
- `architecture.toml` is the layer/context allow-list model checked by
  `make architecture`; `workspace.dsl` is the Structurizr model checked by
  `make validate-architecture-model`.
- Protected configuration: `protected-config.toml` lists protected files
  (including `.claude/settings.json`, `clippy.toml`, `architecture.toml`,
  `make/gates.mk`, `Cargo.toml [workspace.lints]`). Changing one needs a
  session restarted with `ALLOW_PROTECTED_CONFIG_EDIT=1` and the PR label
  `approved-config-change`; a PreToolUse hook
  (`scripts/claude/guard-protected-files.sh`) blocks edits. **Consequence:**
  `/rs-sdlc-setup` must NOT write `.claude/settings.json` when it is
  protected; it writes the permission allowlist to the git-ignored
  `.claude/settings.local.json` (or prints it) instead.
- `make docs-check` (`scripts/check-docs.sh`) rejects: a backticked
  `make <target>` that does not exist; a backticked slash command (`/name`)
  without a `.claude/commands/name.md` file; a backticked path starting with a
  tracked top-level name that does not exist and is not git-ignored; any
  numbered list or fenced block outside AGENTS.md's verification markers that
  cites three or more gate targets. **Consequence:** the governance block the
  plugin injects into `CLAUDE.md`/`AGENTS.md` must cite plugin slash commands in
  plain prose (never in backticks), must not list 3+ gate targets in a fenced
  block or numbered list, and must only backtick paths that exist.
- Repo linters a service runs on its own files: markdownlint (`MD013` off,
  `MD024` siblings_only, `MD033` allows a/img/p), typos, yamllint
  (`extends: default`, braces `{ a: 1 }` with one inner space, 2-space
  indentation, no document-start), prettier (`singleQuote: true`,
  `printWidth: 100`) over YAML/JSON. **Consequence:** the generated
  `.claude/rust-sdlc.yml` must be yamllint- and prettier-clean (block style,
  single-quoted strings where quoting is needed).
- `specs/` is excluded from markdownlint, prettier and typos in the template,
  so BMAD bundles under `specs/<slug>/` are safe.
- Commits and PR titles: `type(#issue): subject` (enforced by a commit-msg
  hook and CI); branch `type/<issue>-<slug>`; hooks are never bypassed
  (`--no-verify` is denied); releases/CHANGELOG are produced by the release job.
- `#[allow]` is forbidden; a suppression is `#[expect(lint, reason = "...")]`
  only where the lint policy permits it. No `unwrap`/`expect`/`panic` in
  production code. Domain crates are framework- and I/O-free.
- Never edit an applied migration; add a new one (`make create-migration
  name=<snake_case>`), then `make migrate` and `make sqlx-prepare`, commit
  `.sqlx/` with the migration.
- Regenerate contract snapshots (`make generate-openapi-spec`,
  `make generate-graphql-spec`) and update `workspace.dsl` in the same change.
- Service-owned Make targets go to `make/service.mk` + `docs/make-targets-service.md`
  (never edit the template Makefile). Template sync flavours: App
  (`template-sync-app.yml`) or PAT (`template-sync-pat.yml`).
- The template ships its own 11 skills under `.claude/skills/`, its BMAD
  slash commands under `.claude/commands/`, and `bmalph/config.json`.
  The plugin's skills COMPLEMENT them; where both exist, the plugin skill
  defers to the repository's skill and `AGENTS.md` (repository wins).
- Health: `/ping` liveness, `/api/health` readiness; API docs `/api/docs`;
  GraphQL `/api/graphql`; default port 8081.

## Repository constraints for the plugin (claude-plugins)

- `python3 tools/plugin-quality/lint/lint_all.py` must report 0 findings for
  all plugins, including the new one.
- Generalization (NFR-2): components under `skills/`, `commands/`, `agents/`,
  `scripts/` must not contain `vilnacrm`, `user-service`, etc. (see
  `tools/plugin-quality/lint/check_generalization.py`). Concrete values may
  appear only inside fenced blocks whose opening fence carries
  `# profile-example`. The template repository slug used as the default
  for `/rs-sdlc-new-service` therefore lives in plugin configuration outside
  those four directories (decide where in the architecture) or is passed by
  the caller.
- No `_bmad/` or `.ralph/` inside the plugin tree.
- Frontmatter: commands need `description` + `argument-hint`; agents need
  `name`, `description`, `tools`, `model`; skills need `name` + `description`;
  meta-guides at `skills/*.md` must NOT have frontmatter.
- Every skill lists consumed profile keys under `## Profile keys consumed`;
  each key must be declared in `docs/profile-schema.md` (extend the CI
  `profile-keys-check` and `generalization-audit` jobs to cover the new plugin).
- Shell scripts pass `shellcheck -x`; tests are bats; markdown passes
  markdownlint-cli2 with the repo `.markdownlint.yaml`.
- Local YAML backend caveat: the session host has the Python `yq` wrapper,
  CI has mikefarah `yq`. The new `common.sh` must detect mikefarah yq
  specifically and otherwise fall back to python3 + PyYAML.

## Scope guidance

- Parity with php-backend-sdlc: ~10 commands, 7 agents, a Rust skill library
  (~25 skills incl. meta-guides `AI-AGENT-GUIDE.md`, `SKILL-DECISION-GUIDE.md`),
  scripts (`lib/common.sh`, `setup-preflight.sh`, `generate-profile.sh`,
  `validate-profile.sh`, `inject-governance.sh`, `ai-review-loop.sh`,
  `get-pr-comments.sh`, `fr-nfr-gate.sh`, `post-review-findings.sh`, plus the
  new `new-service.sh`), bats suites with fixtures (stub Rust repo, profiles,
  ledgers, gh/claude/bmalph stubs), docs (profile schema, setup walkthrough,
  SDLC loop, permissions, degrade matrix, release process, new-service
  walkthrough, test strategy).
- Rust-specific additions: new-service and new-context commands; skills for
  Rust error handling, async/tokio safety, dependency policy (cargo-deny,
  cargo-shear, architecture allow-lists), sqlx migrations, utoipa/async-graphql
  contracts, cucumber/nextest/llvm-cov/cargo-mutants testing, clippy
  complexity, tracing observability, Rust security audit.
- Optional epic (decide in architecture, prefer to include if risk is
  controlled): port the react plugin's Workflow scripts as
  `workflows/rs-sdlc-*.js` with the harness and bats tests.
- Repo wiring: `marketplace.json` entry, root `README.md` row, `ci.yml` tag
  namespace and per-plugin jobs.

## Out of scope

- Changing the rust-service-template's gates or protected configuration.
- Running a real Ralph loop against GitHub from this session (stories are
  executed by orchestrated agents following the Ralph fix plan).
