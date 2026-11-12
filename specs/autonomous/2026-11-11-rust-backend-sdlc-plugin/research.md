---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/task-framing.md
  - plugins/php-backend-sdlc/** (reference plugin, read via the four research notes and spot-checked)
  - plugins/react-frontend-sdlc/{workflows,scripts,tests}/** (workflow layer, sensor, hardened gate)
  - tools/plugin-quality/lint/*.py, .github/workflows/ci.yml, .claude-plugin/marketplace.json
  - /home/user/rust-service-template (HEAD 3e0bd3e, 606 tracked files)
  - /opt/node22/lib/node_modules/bmalph (bmalph 2.11.0 installed package)
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/research.md (depth bar)
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'rust-backend-sdlc Claude Code plugin built on the Rust service template'
research_goals: 'Exact facts, contracts and hazards the PRD, architecture and stories need to build rust-backend-sdlc at php-backend-sdlc parity'
user_name: 'main agent (user surrogate)'
date: '2026-11-11'
web_research_enabled: false
source_verification: true
---

# Research: `rust-backend-sdlc` Claude Code Plugin

Date: 2026-11-11 | Stage: BMAD Analysis (technical-research) | Analyst: Mary (BMAD analyst agent), run non-interactively for the main agent acting as user surrogate
Design input: `specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/task-framing.md` (identity decisions fixed; not re-opened here).

Path conventions used for evidence: `tpl/` = `/home/user/rust-service-template/`; `php/` = `plugins/php-backend-sdlc/`;
`react/` = `plugins/react-frontend-sdlc/`; `repo/` = `/home/user/claude-plugins/`; `bmalph/` =
`/opt/node22/lib/node_modules/bmalph/`; `notes/` = the five stage-input research notes in the session scratchpad
(`php-commands-agents.md`, `php-skills.md`, `php-scripts-tests-docs.md`, `rust-template.md`,
`react-workflows-repo-ci.md`). Primary sources are cited first; notes are cited only for analysis they contain.

> Assumption: the BMAD technical-research workflow requires web search. Every source for this topic is a
> local, version-pinned checkout (reference plugin, lint tool, template, installed bmalph), which is more
> authoritative than web data, so web search was skipped. The six step files' `[C]` menus were skipped; this
> document carries the content of all six steps (scope, overview, integration, architecture, implementation,
> synthesis) under the section headings the planning chain requires.
>
> Assumption: "spot-checked" means re-read or re-executed in this stage. Claims marked **[verified]** were
> re-checked here (commands listed in the Summary); unmarked claims come from the notes, which read every
> file in full.

## Summary

`rust-backend-sdlc` is a port of `php-backend-sdlc` (8 commands, 7 agents, 22 skills + 2 meta-guides, 9
scripts, 10 bats suites with 239 tests, 6 docs) to Rust services created from the Rust service template, plus
two Rust-only commands (`/rs-sdlc-new-service`, `/rs-sdlc-new-context`) and, optionally, the Workflow-tool
layer that `react-frontend-sdlc` added. Roughly 70–80% of the reference command/agent text is
language-agnostic contract (stage machine, `MAX_ITERATIONS=5`, the 7-field escalation block, machine-readable
handles, degrade taxonomy, git ownership, triage, ledgers) and ports with identity renames only. The remaining
work is dominated by template facts the PHP plugin never faced:

1. **Make-only execution** (not container-only): every tool runs through `make`; `RUN_IN_CONTAINER=1` moves
   TOOL targets into the `app` container. 107 targets, 31 ordered gates in 7 stages (`make ci-list`).
2. **Protected configuration**: 50 files, 4 directories, `Cargo.toml [workspace.lints]`, JSON budget pointers;
   `.claude/settings.json` is one of them and a PreToolUse hook blocks agent edits. The setup command must
   write its allowlist to the git-ignored `.claude/settings.local.json`.
3. **Service-side gates bind plugin output**: `make docs-check` constrains the governance block (no backticked
   plugin slash commands, only existing backticked paths, no list of three or more gates);
   `make validate-invariants` forbids the template's name in `CLAUDE.md`/`AGENTS.md`; yamllint, Prettier and
   typos scan `.claude/rust-sdlc.yml`; the commit-msg hook rejects every commit message form the PHP plugin
   uses.
4. **bmalph integration gaps**: `bmalph implement` reads only `_bmad-output/planning-artifacts/` (or two
   aliases), while the template's planning skill writes bundles to `specs/<bundle-id>/`; a staging step is
   mandatory. The readiness preflight rejects any match of `/NO[-\s]?GO/i`.
5. **Tooling environment**: the session host's `yq` is the kislyuk Python wrapper; CI has mikefarah `yq`; the
   PHP `have_yq` accepts either and breaks on the host. React's `!!seq` probe is the fix.
6. **Generalization lint**: the default template slug contains the denylisted org token, so it must live in
   plugin configuration outside `skills/ commands/ agents/ scripts/` (recommended:
   `config/new-service.defaults.json`).

All gates of the template already sit at the strictest value (100% lines and functions, 0 surviving mutants,
0 clippy warnings, 0 architecture violations); "raise-only" therefore degenerates to "must equal the template
value" except the four clippy complexity limits, which can only be lowered.

Verification commands re-run in this stage: `make ci-list` in `tpl/` (31 targets, exact order), `yq --version`
and `printf 'a: [1]\n' | yq '.a | type'` (prints `"array"`), `python3` over `tpl/protected-config.toml` (50
files, 4 dirs, 69 override names, 14 required dirs), `tpl/.claude/settings.json` (80 allow, 11 ask, 9 deny,
`PreToolUse` + `PostToolUse` hooks), `ls tpl/.claude/commands | wc -l` (54), grep of
`bmalph/dist/transition/{artifacts,preflight}.js` and `bmalph/ralph/templates/ralphrc.template`, grep of
`repo/tools/plugin-quality/lint/{check_generalization,check_references,check_structure,check_frontmatter}.py`
and `repo/.github/workflows/ci.yml`, grep of the react workflows' `workflow(` call sites, `wc` / `grep -c '@test'`
over `php/`.

Recommended scope (detailed in Recommendations): 10 commands, 7 agents, 28 skills + 2 meta-guides, 13
executable scripts + `lib/common.sh`, 15 bats suites (16 with the workflow epic), 9 docs, 1 config file, and the 4-workflow epic with
the hand-back fix for the nesting defect found in react.

## Key Findings

1. **The reference is mostly portable contract.** All 8 php commands share the 5-H2 spine (`Inputs`,
   `Procedure`, `Loop & exit condition`, `Iteration guard`, `Failure escalation`), all 7 agents the 8-H2
   spine, one `MAX_ITERATIONS=5` per component, one canonical `=== SDLC ESCALATION ===` block and a fixed set
   of stdout handles (`ISSUE_URL:`, `SPECS_DIR:`, `---RALPH_STATUS---`, `FR_NFR_REVIEWER:`,
   `FR_NFR_NEW_FINDINGS:`, `AI_REVIEW_VERDICT:`). Only toolchain words, thresholds, artifact names and
   commit forms are PHP-specific. Evidence: `php/commands/*.md`, `php/agents/*.md`; component matrix in
   `notes/php-commands-agents.md` §4.
2. **Make-only, not container-only.** `tpl/AGENTS.md`: "Run every tool through `make`. Do not call cargo,
   docker or the linters directly unless a skill says so." `RUN_IN_CONTAINER=1|true` (outside CI and the dev
   container) sets `EXEC := docker compose exec -T --user … app`; HOST targets drive Docker themselves and exit
   2 with `This target needs a reachable container engine (docker).` when `docker info` fails. The PHP rule
   "never run php/composer on the host; `docker compose exec php`" has no Rust equivalent. Evidence:
   `tpl/Makefile` header, `tpl/docs/adr/0009-make-execution-model.md`.
3. **31 ordered gates in 7 stages; bars already at the extreme.** **[verified]** `make ci-list` prints
   `validate-configuration validate-invariants secrets-scan lint-repo lint-load-tests
   validate-architecture-model format-check validate-manifest check-crate-isolation static-analysis complexity
   architecture check-security unused-dependencies check-requirements docs-check setup-test-db
   validate-sqlx-metadata tests-with-coverage doc-tests e2e-tests validate-contract-snapshots
   validate-openapi-spec openapi-diff graphql-diff mutation-tests-diff build-prod-image image-scan
   schemathesis-validate smoke-load-tests bats`. Coverage `--fail-under-lines 100 --fail-under-functions 100`;
   cargo-mutants exit 2/3 on any MISSED/TIMEOUT; clippy `-D warnings` over `all pedantic nursery cargo` + 60+
   restriction lints; complexity cognitive 8 / 50 lines / 5 args / nesting 5 (`tpl/clippy.toml`). Full
   `make ci` measured at 24 min 42 s on 4 vCPU. Evidence: `tpl/make/gates.mk`, `tpl/clippy.toml`,
   `tpl/Cargo.toml [workspace.lints]`, `notes/rust-template.md` §3–§4.
4. **`.claude/settings.json` is protected and hook-guarded.** **[verified]** `tpl/protected-config.toml:57`
   lists it; `approval_label = "approved-config-change"`; the settings carry 80 allow, 11 ask and 9 deny rules
   plus `PreToolUse`/`PostToolUse` hooks running `scripts/claude/guard-protected-files.sh pre|post` on
   `Edit|Write|MultiEdit|NotebookEdit` (exit 2 blocks the call; the hook does not see Bash).
   `.claude/settings.local.json` is git-ignored (`tpl/.gitignore:16`). The php setup writes
   `.claude/settings.json` (`php/commands/sdlc-setup.md:90,132`) — must not be copied.
5. **`make docs-check` constrains anything the plugin writes into tracked Markdown.** **[verified]**
   `tpl/scripts/check-docs.sh` reads tracked `*.md` except `CHANGELOG.md` and `specs/**` (line 108) and
   rejects: (1) a cited `make <x>` that is not a target; (2) a code span `/name` without
   `.claude/commands/name.md` (line 397); (3) a backticked path whose first segment is a tracked top-level name
   but which neither exists nor is git-ignored (lines 401–412); (4) any numbered list or fenced block outside
   the AGENTS.md verification markers citing three or more gate targets (lines 293, 301). The target first
   compiles the service binary (`tpl/Makefile:440-446`, `cargo run -p service -- --help`), so it needs the
   pinned toolchain or `RUN_IN_CONTAINER=1`. Experiments on a planted governance block (prose `/rs-sdlc` OK,
   backticked `/rs-sdlc-plan` rule 2, untracked `.claude/rust-sdlc.yml` rule 3, `.claude/settings.local.json`
   OK) are recorded in `notes/rust-template.md` §12.1.
6. **The template name is forbidden in the files the plugin edits, and those files are synchronised.**
   **[verified]** `tpl/scripts/check-invariants.sh` rule (e) assembles the name at runtime (line 51) and scans
   `Makefile Dockerfile AGENTS.md CLAUDE.md` + compose files (line 718), `.claude/skills/**`, `scripts/`,
   `tests/`, `crates/`, workflows (except the `TEMPLATE_REPOSITORY:` lines of the two sync workflows).
   `CLAUDE.md` and `AGENTS.md` are not in `tpl/.templatesyncignore`, so every merged template-sync PR replaces
   them and deletes the injected governance block.
7. **The commit convention rejects the reference's commit messages.** **[verified]**
   `tpl/scripts/check-commit-message.sh:14`:
   `^(feat|fix|refactor|build|chore|ci|docs|style|perf|test)\(#[0-9]+\): .*` (case-insensitive; exit 0/1/2;
   title mode via `COMMIT_TITLE` backs the "Pull-request title" check). php's
   `review: gate iteration <n> remediation` and `Apply review suggestion: …` fail. The `pre-commit` hook runs
   `make pre-commit` (`format-check lint-code architecture check-security-offline unused-dependencies`), so
   every commit compiles and lints the workspace; `pre-push` runs `make unit-tests`. **[verified]** deny list:
   `git push --force|-f`, `git commit --no-verify|-n`, `git push --no-verify`, `git -c core.hooksPath`,
   `git config core.hooksPath`, `Read/Edit(./.env.local)`.
8. **bmalph cannot see `specs/<slug>/`.** **[verified]** `bmalph/dist/transition/artifacts.js:6-8` discovers
   artifacts only in `_bmad-output/planning-artifacts`, `_bmad-output/planning_artifacts`, `docs/planning`;
   `bmalph/dist/transition/preflight.js:142` blocks on `/NO[-\s]?GO/i` anywhere in the readiness file
   (overridable only by `--force`); `bmalph/dist/utils/artifact-definitions.js:12` classifies Technical
   Research only by `/tech.*research/i` (plain `research.md` is ignored). The template's own planning skill
   forbids writing bundles under `_bmad-output/` (`tpl/.claude/skills/bmad-autonomous-planning/SKILL.md`). The
   php implement command never stages (defect X5 below).
9. **Ralph bypasses permissions by default.** **[verified]** `bmalph/ralph/templates/ralphrc.template:50,56,100`:
   `CLAUDE_PERMISSION_MODE="bypassPermissions"`, `PERMISSION_DENIAL_MODE="continue"`, `CB_AUTO_RESET=false`;
   the file lives at `.ralph/.ralphrc`. php's `docs/permissions.md` calls bypass "a Ralph-driver opt-in" and
   cites `.ralphrc` at the repository root (defects X6, X8). The template's guard hooks still fire inside Ralph
   and `claude -p` sessions started in the checkout.
10. **The template ships its own skills and commands.** **[verified]** 11 skills
    (`api-contract-development`, `api-resource-development`, `architecture-boundary-fixer`,
    `architecture-model-sync`, `bmad-autonomous-planning`, `complexity-management`, `documentation-sync`,
    `load-testing`, `quality-standards`, `testing-workflow`, `verification-workflow`) + `README.md`,
    `AI-AGENT-GUIDE.md`, `SKILL-DECISION-GUIDE.md`; 54 BMAD wrapper commands in `.claude/commands/` (one note
    says 55; the count here is 54); `bmalph/config.json`. Template skills have no `## Profile keys consumed`
    (fail lint L17) and keep at most two gate targets per fenced block. Thresholds are stated only in the
    template's `quality-standards` skill.
11. **Host `yq` is the wrong `yq`.** **[verified]** `yq --version` → `yq 0.0.0`, shebang `#!/usr/bin/python3`
    (`yq==3.1.0`, kislyuk), `.a | type` → `"array"` (mikefarah prints `!!seq`). php `have_yq`
    (`php/scripts/lib/common.sh:111-113`) accepts any `yq`, which made 13 of 47 php `common-lib` +
    `validate-profile` tests fail on this host (`notes/php-scripts-tests-docs.md` §0.3). React's probe
    (`react/scripts/lib/common.sh:111-131`, cached in `_SDLC_YQ_OK`) accepts only mikefarah semantics. CI's
    `ubuntu-latest` ships mikefarah `yq` v4.
12. **The generalization denylist blocks the template slug in four directories.** **[verified]**
    `repo/tools/plugin-quality/lint/check_generalization.py` L28 denylist (case-insensitive)
    `user[-_ ]service|mongo[a-z][a-z0-9_]*repository|apprunner|src/user|src/oauth|vilnacrm` over
    `SCOPED_DIRS = ("skills", "commands", "agents", "scripts")` (line 40), stripping only backtick fences whose
    opening line contains `# profile-example`; `.sh` files have no escape. The slug in
    `tpl/.github/workflows/template-sync-{app,pat}.yml:16` and the secret names in `tpl/docs/new-service.md:81,97`
    contain the denied token. `config/`, `docs/`, `tests/`, `workflows/` are not scanned; `claude plugin
    validate --strict` forbids custom `plugin.json` keys, so the slug cannot go into the manifest.
13. **Shared lint has three Rust blind spots.** **[verified]** `check_references.py:49`
    `_COMMAND_RE = (?<![A-Za-z0-9_/])/(sdlc[a-z0-9-]*)` → `/rs-sdlc-*` typos are invisible, and any `/sdlc-…`
    mention in a Rust artifact is a dead-command finding; lines 60–63 `_PROFILE_PREFIX` lacks `rust`,
    `service`, `execution`, `contracts`, `template`, `governance`; line 68 `_FILE_EXT_RE` lacks
    `toml|rs|dsl|sql|feature`, so a backticked `architecture.toml` is an L25 finding unless the schema
    backticks it. `check_structure.py:59` L18 gate predicate recognises only
    `capabilities|framework|persistence` keys.
14. **Two CI jobs ignore new plugins.** **[verified]** `repo/.github/workflows/ci.yml:219,257` hard-code
    `PLUGIN=plugins/php-backend-sdlc` in `profile-keys-check` and `generalization-audit`; line 10 tag filter
    lacks `rust-backend-sdlc-v*`. A `plugins/*` glob would fail on `devops-sdlc` (5 dotted tokens in
    `skills/observability/SKILL.md`, `notes/react-workflows-repo-ci.md` §0.2), so the edit must use an explicit
    list.
15. **The profile must survive four service linters.** **[verified]** `tpl/.yamllint.yml` (`extends: default`,
    `braces: { min-spaces-inside: 1, max-spaces-inside: 1 }`, `indentation: { spaces: 2, indent-sequences:
    consistent }`, `document-start: disable`, `truthy`), `tpl/.prettierrc.yml` (`singleQuote: true`,
    `printWidth: 100`), Prettier invoked over the whole repository with `--ignore-path .gitignore
    --ignore-path .prettierignore` (`tpl/Makefile:85`), `tpl/_typos.toml` `ignore-hidden = false` (scans
    `.claude/`). Prettier rewrites `"x"` to `'x'` and `[ a, b ]` to `[a, b]`; php emits double-quoted flow
    lists, which `make lint-prettier` would reject.
16. **Adding a bounded context is a 12-step, 5-gate procedure.** `make new-context group=<g> context=<c>`
    (exit 0 created, 1 refused with nothing written, 2 could not run; reserved names `shared service xtask
    test-support e2e-tests`; name regex `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`) creates 6 files and 3 members only.
    Then `make validate-architecture-model` fails until `workspace.dsl` has one component per crate and one
    relationship per `[dependencies]` edge; `[workspace.dependencies]` entries must not precede use (cargo-deny
    `unused = "deny"`); service wiring touches `bootstrap.rs`, `http.rs`, `openapi.rs`, `graphql/schema.rs`
    and three tests that construct `Adapters { .. }` literally plus the contract-pinning tests
    (`openapi/tests.rs`, `graphql/schema/tests.rs` `EXPECTED_SDL`). No `architecture.toml` change is needed
    for a context, but any new third-party crate on a layer is a protected change. Evidence:
    `tpl/xtask/src/scaffold.rs` + `tpl/xtask/src/scaffold/`, `tpl/docs/new-service.md` §5, `notes/rust-template.md` §10.7.
17. **New-service creation has a deterministic core and three traps.** `tpl/docs/new-service.md` has 10 steps;
    identity edits (`[workspace.package]` `description`/`repository`/`version`, `bmalph/config.json`, README
    badges, CHANGELOG reset, `specs/` reset, sync flavour) are scriptable. Traps: (a) **[verified]** after
    removing `crates/company-subdomain/`, docs-check rule 3 fails on three synchronised lines
    (`tpl/.claude/skills/api-resource-development/SKILL.md:24`, `tpl/.github/TEMPLATE_SYNC_APP.md:51`,
    `tpl/.github/TEMPLATE_SYNC_PAT.md:55`); (b) a GraphQL `MergedObject` `Query` with no context field is
    probably invalid (unverified); (c) changing `description` changes the OpenAPI title
    (`<description> API`), so `make generate-openapi-spec` + commit is mandatory before G17 passes. The
    checkout directory name becomes `PROJECT_NAME` (Compose project, image names); the licence is pinned to
    `CC0-1.0` by invariant (f). **[verified]** `tpl/bmalph/config.json` holds the template name and an
    org-named description.
18. **The QA surface is small and fully specified.** Port 8081 (`APP_PORT`); `GET /ping` → `200 text/plain
    pong`; `GET /api/health` → `204`, or `500 application/problem+json` type `/problems/dependency-unavailable`
    with `failures[]`; `/api/docs`, `/api/docs/openapi.json`; `POST /api/graphql` (GET explorer only when
    `APP_ENV=dev`, else `405`); statuses limited to 400/404/405/413/415/422/500/503 (no 401/403/409); unknown
    JSON fields give `422 about:blank`, not validation-failed; GraphQL errors return HTTP 200 with
    `extensions.code` `VALIDATION_FAILED|INTERNAL_SERVER_ERROR`; `x-request-id` echoed when it matches
    `^[A-Za-z0-9._-]{1,128}$`. `make start` waits up to 900 s. Evidence: `tpl/crates/service/src/http/router.rs`,
    `tpl/features/*.feature`, `notes/rust-template.md` §17.
19. **The test database is a shared, destructive resource.** **[verified]** `setup-test-db` = "Drop, create
    and migrate the test database" (`tpl/Makefile:405`, `tpl/scripts/setup-test-db.sh` runs `sqlx database
    reset -y -f`); `integration-tests`, `e2e-tests`, `tests-with-coverage`, `mutation-tests-diff`,
    `sqlx-prepare` depend on it. Two agents running them in parallel corrupt each other's runs.
20. **Three gates depend on git state, not only on code.** G17 regenerates both snapshots and requires an empty
    `git status --porcelain` for them — staged-but-uncommitted snapshots fail; G15 diffs from
    `git merge-base <base_ref> HEAD` and does not mutate untracked files until `git add`; G25
    (`validate-configuration`) exits 2 `base ref origin/main is not available` in a fresh or local-only
    repository. Evidence: `tpl/make/gates.mk`, `tpl/scripts/mutation-diff.sh`, `tpl/xtask/src/config_guard.rs`.
21. **Protected directories block even new files in-session.** The hook blocks any path below
    `tests/CLI/bats/`, `xtask/tests/`, `xtask/src/arch/`, `xtask/src/config_guard/`, including new files. A
    service Make target in `make/service.mk` fails G16 unless a Bats test under `tests/CLI/bats/` invokes it,
    so adding one is a human-gated path. Evidence: `tpl/protected-config.toml` `directories`,
    `tpl/tests/CLI/bats/make_execution_mode.bats`, `notes/rust-template.md` §10.12.
22. **React's feature workflow nests two levels deep.** **[verified]** `react/workflows/fe-sdlc-feature.js:236`
    calls `workflow('…:fe-sdlc-pr-until-green')`, whose `runGate()` calls
    `workflow('…:fe-sdlc-fr-nfr-review')` at `react/workflows/fe-sdlc-pr-until-green.js:330` and converts a
    throw into `ESCALATED — nested FR/NFR gate workflow unavailable` (line 333). Under the Workflow-tool rule
    that `workflow()` nesting is one level only (quoted in `notes/react-workflows-repo-ci.md` §A1 from the
    workflow-authoring reference; the built-in reference is not on disk and was not re-read here), the
    feature workflow escalates whenever the PR head lacks a green gate status — which a fresh head always does.
    The harness (`react/tests/lib/workflow-harness.mjs`) mocks `workflow()` and cannot detect it.
23. **React hardened the gate and added a PR sensor.** `react/scripts/fr-nfr-gate.sh` is 538 lines vs php's
    146 (**[verified]** `wc -l`): PR description and linked issues as requirement sources, a baseline NFR
    catalog, fail-closed when no source exists, `--advisory`, `--iteration`, `--pr`, read-only
    `claude_run_isolated`. `react/scripts/pr-state.sh` (398 lines, verdicts
    `BLOCKED > FIX > GATE > REQUEST > WAIT > READY`) and `request-ai-reviews.sh` (228) are generic except four
    strings. The commit-status context `BMAD FR/NFR Review Gate` is shared by all plugins and must stay
    byte-identical.
24. **php's ledger directory would break service linters.** php writes `${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}`.
    In a service, `.sdlc/` is untracked and not ignored, so **[verified]** Prettier (whole repository,
    `.gitignore` as ignore path) checks its JSON, `secrets-scan` reads it (`git ls-files --cached --others
    --exclude-standard`, `tpl/scripts/secrets-scan.sh:82`) and typos scans it. `target/` is git-ignored and
    excluded by every template linter.
25. **Coverage and mutation semantics shape implementer behaviour.** Coverage is unit + integration only (e2e
    is not instrumented), so code reachable only from a Gherkin scenario fails the 100% floor; logic inside an
    `#[async_trait]` method body is invisible to coverage and complexity, so trait impls delegate to an
    inherent `async fn`; unit tests live in sibling `tests.rs` (`#[cfg(test)] mod tests;`), integration tests
    only in `<crate>/tests/integration/main.rs`; each mutant is judged by its own crate's tests, so a branch
    tested only from another crate survives. Evidence: `tpl/.cargo/mutants.toml`, `tpl/.config/nextest.toml`,
    `tpl/.claude/skills/testing-workflow/SKILL.md`, `notes/rust-template.md` §7.4.
26. **Markdown fixtures are linted in CI.** `ci.yml` `markdown-lint` runs over every `.md` under `plugins/`,
    including `tests/fixtures/`; existing plugins ship no `.md` fixtures. A Rust stub repository needs
    `README.md`, `CHANGELOG.md` and `docs/new-service.md` to test `new-service.sh`. L29 likewise forbids any
    `_bmad` or `.ralph` path component anywhere in the plugin tree, fixtures included.

## Reference Plugin Anatomy

### Components (`php-backend-sdlc` 0.1.0)

| Component | Count / size | Shape and contract |
| --- | --- | --- |
| `.claude-plugin/plugin.json` | 1 | `name`, `version` `0.1.0`, `description`, `author{name,url}`, `homepage`, `repository`, `license` `MIT`, `keywords[]`; CI requires all eight and strict semver |
| `commands/*.md` | 8, 1,183 lines | frontmatter `description` + `argument-hint` (bracket groups); `allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]` only on `sdlc-review` and `sdlc-qa`; 5-H2 spine; first action `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"` (except setup) |
| `agents/*.md` | 7, 1,574 lines | `php-implementer` (sonnet), `code-quality-reviewer` (opus), `fr-nfr-reviewer` (opus), `ci-fixer` (sonnet), `pr-comment-resolver` (sonnet), `qa-manual-tester` (sonnet, `Bash, Read`), `security-auditor` (opus); 8-H2 spine `Profile keys consumed`, `Role`, `Inputs`, `Outputs`, `Allowed actions`, `Degrade paths`, `Iteration discipline`, `Smoke prompt`; H1 lead token = `name` = filename stem |
| `skills/<name>/SKILL.md` | 22 (8,557 lines; 627 KB with supporting files) | `name` = dir, `description` with "Use when"; first H2 `## Profile keys consumed`; profile indirection ("the target mapped by `make.X`"); concrete values only in `# profile-example` fences; supporting `REFERENCE.md`, `reference/*.md`, `examples/*.md` |
| `skills/*.md` meta-guides | 2 | `AI-AGENT-GUIDE.md`, `SKILL-DECISION-GUIDE.md`; no frontmatter; decision guide carries "every skill verdict recorded, no silent skips" (L30) |
| `scripts/` | 8 executables + `lib/common.sh`, ~2,746 lines | `setup-preflight.sh [--report]`, `generate-profile.sh [--refresh] [DIR]`, `validate-profile.sh [FILE]`, `inject-governance.sh [--diff] [DIR]`, `ai-review-loop.sh`, `fr-nfr-gate.sh`, `get-pr-comments.sh`, `post-review-findings.sh`; skeleton `set -euo pipefail` + `source "$SCRIPT_DIR/lib/common.sh"`; exit 0/1 (64 when the library is executed); `[php-sdlc]` log prefix; jq/python3 and yq/PyYAML dual backends; symlink/irregular-file refusal and atomic `mktemp` + `mv` writes |
| `tests/*.bats` | 10 suites, 239 tests **[verified]** | stubs `fixtures/bin/{claude,gh,bmalph}` driven by `STUB_*` env vars; sandbox PATHs for genuine absence; backend-parity tests; install-cache test; `component-counts.bats` pins 8/7/22/2 |
| `docs/` | 6 + `testing/` | `profile-schema.md` (canonical key list, grepped by CI), `setup-walkthrough.md`, `sdlc-loop.md`, `permissions.md`, `degrade-matrix.md`, `release-process.md` (tag `php-backend-sdlc-vX.Y.Z`), `testing/test-strategy.md` + campaign summary |
| Planning bundle | `specs/autonomous/2026-06-09-php-backend-sdlc-plugin/` | `research.md`, `product-brief.md`, `prd.md`, `architecture.md`, `epics.md`, `implementation-readiness.md`, `retrospective.md`, `run-summary.md` |

### Contracts

| Contract | Exact form in the reference | Port verdict |
| --- | --- | --- |
| Stage entry | `validate-profile.sh` first; exit 1 → abort, instruct `/sdlc-setup`; setup runs `setup-preflight.sh --report` | keep, rename |
| Iteration guard | per-component `MAX_ITERATIONS=5`, never reset; finish-pr counters A (`ci_fix`) and B (`comment_resolution`); loop-backs consume the owning stage's budget; Ralph breaker trip is terminal | keep; add counter C (gate, max 3) from react |
| Escalation block | `=== SDLC ESCALATION ===` with `stage`, `iteration`, `exit_condition`, `status: NOT MET`, `blocking_finding`, `iteration_log`, `recommended_action`, `=== END ===` (L27) | keep verbatim |
| Run report | `=== SDLC RUN REPORT ===` `task`, `result: SUCCESS \| ESCALATED`, stage table, `artifacts`, `degrade_notes`, `escalation` | keep; add `branch:` |
| Handles | `ISSUE_URL:`, `SPECS_DIR:`, `---RALPH_STATUS---` block (`STATUS`, `TASKS_COMPLETED_THIS_LOOP`, `FILES_MODIFIED`, `TESTS_STATUS`, `WORK_TYPE`, `EXIT_SIGNAL`, `RECOMMENDATION`), `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<…>`, `FR_NFR_NEW_FINDINGS: <n>`, `AI_REVIEW_VERDICT: PASS\|FAIL`, `## Verdict:`, `## Status: ALL-GREEN\|FIXES-READY\|SKIPPED-NO-CI\|BLOCKED`, `VIOLATION:` | keep; add `ISSUE_NUMBER:` |
| Degrade (NFR-4) | degrade paths never loop, never hard-fail; one-line note; status `SUCCESS-WITH-REPORT`; "null means absent; omitted means error" for every `make.*` key | keep |
| Null substitution | `make.ai_review_loop`, `make.pr_comments`, `make.fr_nfr_gate`, `make.post_review_findings` null → bundled script; `make.security` null → bundled static lane | keep (Rust `make.security` maps to `check-security`) |
| Git ownership | agents never run git; commands own commits/pushes; `ci-fixer` may run one `gh run rerun --failed`; `pr-comment-resolver` may reply/resolve threads | keep; story commits owned by the implement loop (php leaves this implicit) |
| Permissions (ADR-6) | `claude -p … --output-format json --permission-mode acceptEdits --max-turns 30`, one retry on transport failure; setup merges `Bash(make:*)`, `Bash(docker compose exec php:*)`, `Bash(git:*)`, `Bash(gh:*)` into `.claude/settings.json` | keep the driver; retarget the allowlist file and entries |
| Triage (NFR-5) | every skill gets EXECUTE or NOT-APPLICABLE from frontmatter + decision guide; bodies load only on EXECUTE | keep; add repository-skill rows |
| Raise-only (ADR-7) | `validate-profile.sh` rejects floors below and ceilings above shipped defaults | generalise to tighten-only |
| Governance | managed block between `<!-- php-backend-sdlc:begin -->`/`end` in `CLAUDE.md` and `AGENTS.md`; fence-aware; idempotent; byte-stable (cites keys, never values) | keep algorithm; rewrite content for docs-check |
| Ledgers and publishing | `{security,fr-nfr,code-review}.json`; poster gated on `capabilities.publish_pr_comments`; markers `<!-- sdlc-review:<lens> -->`; conclusion exactly once | keep; new markers and directory |
| Resume | stage detected from artifacts; managed issue via `gh issue list --label <plugin>` | keep; add durable stage record |

### Reference defects that must not be copied

| # | Where | Defect | Rust fix |
| --- | --- | --- | --- |
| X1 | `docs/sdlc-loop.md` vs `sdlc-review.md` | "21 verdicts" vs "22-skill" | pin the skill count by bats in description and report |
| X2 | `sdlc.md` run report | review row omits "AND every quality threshold PASS" | one exit string everywhere |
| X3 | `sdlc-review.md` | commit `review: gate iteration <n> remediation` | `fix(#<issue>): address review gate iteration <n> findings` |
| X4 | `sdlc-review.md` conclusion | `${PR:?…}` aborts in a normal run (no PR before stage 6) | skip-with-note; finish-pr posts the deferred conclusion once |
| X5 | `sdlc-implement.md` | no staging for bmalph | staging script |
| X6 | `sdlc-implement.md` | `.ralphrc` at the repo root | `.ralph/.ralphrc` |
| X7 | `sdlc-implement.md` | story commit owner unstated | loop commits each story in the hook-valid form |
| X8 | `permissions.md`, `sdlc-setup.md` | bypass described as opt-in | state Ralph's default truthfully; plugin never changes it |
| X9 | `sdlc-setup.md` | writes `.claude/settings.json` | `.claude/settings.local.json` |
| X10 | `ci-fixer.md` vs `sdlc-finish-pr.md` | `ci-fix` vs `ci_fix` label | `ci_fix` |
| X11 | `sdlc.md` resume table | review and QA records have no durable store | durable stage record |
| X12 | `sdlc-plan.md` | readiness "PASS/FAIL" | template vocabulary "ready" / "needs work" + regex self-check |
| X13 | `security-auditor.md` | lists `make.ci` without using it | list only consumed keys |
| X14 | agents | `SEMGREP_APP_TOKEN` noise rule | drop |
| X15 | `sdlc-implement.md` | `bmalph run` without `--no-dashboard` | add it |
| X16 | `post-review-findings.sh:135-136` | two literal NUL bytes; `--json` emits TSV; documented stem fallback not implemented | plain strings; real JSON; implement or delete |
| X17 | `common.sh` `have_yq` | accepts kislyuk `yq` | `!!seq` probe |
| X18 | `profile-schema.md` vs `generate-profile.sh` | documents `make.security`, `capabilities.dynamic_security_testing` that generation never emits | generator emits every documented key |
| X19 | tests | permission tests fail as root; yq tests gate on `command -v yq` | skip under uid 0; gate on `have_yq` |

## Rust Service Template Anatomy

### Identity and layout

- Repository HEAD `3e0bd3e`, 606 tracked files, no tags. Virtual workspace (`resolver = "3"`), 13 explicit
  members: `crates/company-subdomain/some-module/{domain,application,infrastructure}` (example context),
  `crates/internal/health-check/{domain,application,infrastructure}` (readiness context),
  `crates/shared/{domain,application,infrastructure}` (shared kernel), `crates/service` (composition root, lib +
  bin `service`), `tests/support` (`test-support`), `tests/e2e` (`e2e-tests`, cucumber 0.23, `harness = false`),
  `xtask`. Crate names `<context>-<layer>`; a context is derived from the crate name.
- `[workspace.package]`: `version = "0.1.0"`, `edition = "2024"`, `rust-version = "1.99.1"` (= toolchain channel
  = Dockerfile `rust:1.99.1-slim-trixie`, invariant (c)), `license = "CC0-1.0"`, `publish = false`,
  `description` (→ OpenAPI title `<description> API`), `repository` (→ OpenAPI contact URL).
- Stack: axum 0.8.9, async-graphql 7.2.1, utoipa 6.0.0 (+ utoipa-axum, swagger-ui), sqlx 0.9.0 (postgres,
  migrate, macros, offline `.sqlx/`), tokio 1.54.1, tower-http 0.7.1, tracing + JSON subscriber, thiserror 2,
  validator 0.21, clap 4.6, moka, aws-sdk-sqs; tests rstest, proptest, fake, cucumber. PostgreSQL 16 and
  LocalStack (SQS) via Compose.
- Tool pins in `make/tool-versions.mk` (protected): cargo-nextest 0.9.151, cargo-llvm-cov 0.9.1, cargo-mutants
  27.1.0, cargo-deny 0.20.2, cargo-shear 1.14.0, cargo-hack 0.6.46, sqlx-cli 0.9.0, **bmalph 2.11.0**, Spectral,
  oasdiff, graphql-inspector, schemathesis, k6, Structurizr, gitleaks, trivy, markdownlint-cli2, yamllint.

### Command surface and gates

| Stage target | Gates (order) | Notes |
| --- | --- | --- |
| `ci-preflight` | `validate-configuration validate-invariants secrets-scan lint-repo lint-load-tests validate-architecture-model` | G25 needs `base_ref` fetched; HOST targets need Docker |
| `ci-static-analysis` | `format-check validate-manifest check-crate-isolation static-analysis complexity architecture check-security unused-dependencies check-requirements docs-check` | `docs-check` compiles the service |
| `ci-tests` | `setup-test-db validate-sqlx-metadata tests-with-coverage doc-tests e2e-tests` | shared test DB |
| `ci-contracts` | `validate-contract-snapshots validate-openapi-spec openapi-diff graphql-diff` | breaking change needs `approved-breaking-change` |
| `ci-mutation` | `mutation-tests-diff` | diff vs `base_ref` (default `origin/main`) |
| `ci-delivery` | `build-prod-image image-scan schemathesis-validate smoke-load-tests` | isolated prod stack on 18081 |
| `ci-cli` | `bats` | 297 tests, ~15 min |

`make ci` = `make doctor` + the 7 stages, stops at the first failure, prints `CI checks successfully passed!`,
exports `CARGO_BUILD_WARNINGS=deny`. Fast inner loop for implementers: `format` → `static-analysis` →
`complexity` → `architecture` → `unit-tests` → `integration-tests` / `tests-with-coverage` → `e2e-tests` →
`mutation-tests-diff`. Every `?=` variable (including one declared in `make/service.mk`) needs a row in
`docs/environment.md` (docs-check rule 5).

### Thresholds (all protected; the plugin may only tighten)

| Bar | Value | Source | Gate |
| --- | --- | --- | --- |
| Line / function coverage | 100 / 100 | `make/gates.mk` `COVERAGE_GATE_CMD` | G14 `tests-with-coverage` |
| Surviving or timed-out mutants on the diff | 0 | `.cargo/mutants.toml`, exit 2/3 | G15 `mutation-tests-diff` |
| clippy findings (`all pedantic nursery cargo` + restriction picks), rustdoc warnings | 0 | `Cargo.toml [workspace.lints]`, `clippy.toml` | G2 `static-analysis` |
| Cognitive complexity / lines / arguments / nesting | 8 / 50 / 5 / 5 | `clippy.toml` | G3 `complexity` |
| Architecture violations, unassigned crates | 0 | `architecture.toml`, `cargo xtask arch` (exit 0/1/2) | G4 `architecture` |
| Dependency policy (advisories, licences, bans, sources, unused/duplicate workspace deps) | 0 | `deny.toml` | G7 `check-security` |
| Unused / misplaced dependencies | 0 | `cargo shear --locked` | G8 `unused-dependencies` |
| Spectral findings at any severity | 0 | `.spectral.yaml`, `--fail-severity=hint` | G18 `validate-openapi-spec` |
| Unapproved breaking OpenAPI / GraphQL changes | 0 | oasdiff `--fail-on ERR`, graphql-inspector | G19, G20 |
| Smoke p99 (health) | 50 ms | `tests/Load/config.json.dist` pointers | G22 `smoke-load-tests` |
| Image vulnerabilities HIGH, CRITICAL | 0 | Trivy, `.trivyignore` | G10 `image-scan` |

### Conventions a coding agent must follow

- Error model: domain `thiserror` enums (with `property_path()`/`code()` for validation) → one application error
  enum per context → `BusError` → `Problem` (`application/problem+json`, types `about:blank`,
  `/problems/validation-failed` with `violations[]`, `/problems/dependency-unavailable` with `failures[]`).
- Handlers extract only through `ApiPath`, `ValidatedQuery`, `ValidatedJson`, `ApiJson` (+ `State`); a
  source-scanning unit test fails on bare `Path`/`Query`/`Json`.
- Commands return no data (the handler generates the id with the `UuidGenerator` port, then reads back through
  a query); queries return views; subscribers are idempotent and never dispatch commands.
- Lint consequences: no `unwrap`/`expect`/`panic`/indexing/`as` casts in production code; `"x".to_owned()`;
  `Arc::clone(&x)`; no `_ =>` on enums; no `mod.rs`; no error type named `Error`; `#[allow]` anywhere fails G31
  rule (g); `#[expect(lint, reason = "…")]` only where the lint policy permits and never in crate roots or for
  complexity lints; banned APIs `std::env::var*`, `SystemTime::now`, `Instant::now`, `Uuid::{new_v4,now_v7}`,
  socket binds (use the `Clock`/`UuidGenerator` ports and configuration).
- Domain crates may depend only on `async-trait`, `thiserror`, `uuid` (+ `shared-domain`); `tokio`, `sqlx`,
  `axum` are forbidden transitively. Per-layer third-party allow-lists live in `architecture.toml`.
- Migrations: `make create-migration name=<snake_case>` (reversible pair), `make migrate`, rollback-and-reapply
  once, `make sqlx-prepare`, commit `.sqlx/` with the migration; never edit an applied migration; G30 fails on
  stale or orphan `.sqlx/query-*.json`.
- Contracts are generated, never hand-edited: `make generate-openapi-spec` → `.github/openapi-spec/spec.yaml`,
  `make generate-graphql-spec` → `.github/graphql-spec/spec`; a new OpenAPI tag needs a description in
  `ApiDoc`; in-code tests pin the operation, tag and schema lists and the exact SDL.
- Tests: deterministic seeds (`TEST_SEED`, `PROPTEST_RNG_SEED` = 20261110), hand-written fakes in
  `tests/support`, one fresh database per `#[sqlx::test]`, no mocking libraries or testcontainers.

### Extension points

| Seam | Where | Rule |
| --- | --- | --- |
| Service-owned Make targets | `make/service.mk` (`-include` on the last Makefile line) + `docs/make-targets-service.md` | recipes behind `$(EXEC)` (invariant (h)); `## help`; Bats test needed (protected dir) |
| Service-owned PR workflows | `.github/workflows/*.yml` + `docs/repository-settings-service.md` | run only gate targets (invariant (d)) |
| Bounded contexts | `make new-context` (`cargo xtask new-context`) | §Key Finding 16 |
| Health probes | `crates/internal/health-check/{domain/src/value_object/dependency.rs,infrastructure/src/probe.rs}` | sync-ignored extension files |
| Configuration | `crates/service/src/{cli,config}.rs`, `.env`, `.env.test`, `docs/environment.md` | never `std::env::var` |
| Template-extended files | `.templatesyncignore` | add each synchronised path a service changes in the same PR |
| Documented seams | `docs/extension-seams.md` (authentication, outbox, remote cache, exporter) | protected changes where allow-lists move |
| Sync flavour | keep `template-sync-app.yml` + `.github/TEMPLATE_SYNC_APP.md` or the PAT pair; delete the other and add it to `.templatesyncignore` | slug lines are the allowed exception to invariant (e) |

### Protected configuration

50 files (`.cargo/config.toml`, `.cargo/mutants.toml`, `.config/nextest.toml`, `.spectral.yaml`,
`architecture.toml`, `clippy.toml`, `deny.toml`, `protected-config.toml`, `rust-toolchain.toml`, `rustfmt.toml`,
four xtask sources, `make/gates.mk`, `make/tool-versions.mk`, the three hooks, 15 scripts including
`scripts/check-docs.sh`, `scripts/check-invariants.sh`, `scripts/claude/guard-protected-files.sh`, linter configs,
`cog.toml`, `.claude/settings.json`), 4 directories, the `Cargo.toml [workspace.lints]` table, the health budget
JSON pointers, 69 override names (a new `.markdownlint*`, `.prettierrc*`, `clippy.toml`, `deny.toml`, … anywhere
is a violation) and 14 required directories. Approval: PR label `approved-config-change` (locally
`CONFIG_CHANGE_APPROVED=true`) and, for the assistant, a session restarted with `ALLOW_PROTECTED_CONFIG_EDIT=1`.
`cargo xtask config-guard --list` prints the list (allowed in settings) — skills must read it, not restate it.

### docs-check traps (`make docs-check`, G26)

| Rule | Rejects | Trap for the plugin | Verified outcome |
| --- | --- | --- | --- |
| (1) | backticked or fenced `make <x>` where `x` is not a target | governance text citing a plugin pseudo-target | `make rs-sdlc-qa` in a span → `(1)` |
| (2) | code span exactly `/name` without `.claude/commands/name.md` | plugin slash commands in backticks | prose `/rs-sdlc` OK; span `/rs-sdlc-plan` → `(2) … has no file .claude/commands/rs-sdlc-plan.md` |
| (3) | backticked path whose first segment is tracked but which neither exists nor is ignored | citing `.claude/rust-sdlc.yml` before it is committed; citing `scripts/<plugin-script>.sh`; removing the example context | untracked profile → `(3)`; `.claude/settings.local.json` OK (ignored); `specs/<bundle-id>/prd.md` OK (checked up to `<`) |
| (4) | numbered list or fenced block (outside the AGENTS.md verification markers) naming ≥ 3 gate targets | a verification snippet in the block, an issue template, a skill copied into the repo | fence with three gates → `(4)`; list with two → OK |
| (5)–(7) | env-var table drift; target without a `##` help comment or doc row; `.claude/skills/<dir>` without an index line | writing into `.claude/skills/`; adding `?=` variables | n/a for the block |

Only tracked files are read, so a block that passes locally before `git add` can fail in CI if the profile it
cites is not committed in the same change. `CHANGELOG.md` and `specs/**` are exempt.

### Runtime surface for QA

`make start` (dev stack, debug build, `APP_ENV=dev`, port 8081, waits ≤ 900 s) or the isolated production image
on 18081 via `scripts/with-load-test-stack.sh` (`APP_ENV=test`). Probe set: §Key Finding 18. Logs are one JSON
object per line (`docker compose logs --no-log-prefix app`), correlated by the `request_id` span field. Fault
injection is not available over HTTP; the e2e suite covers dependency failures. `SCHEMATHESIS_URL=<url> make
schemathesis-validate` reuses a running stack as a deterministic fuzz lane.

### BMAD and bmalph inside the template

`make bmalph-setup` installs pinned bmalph 2.11.0 if missing, runs `bmalph init --platform claude-code --name
<bmalph/config.json name> --description …`, upgrades incomplete assets with `bmalph upgrade --force`, then
**restores every tracked file bmalph modified** (`CLAUDE.md`, `.gitignore`, `.claude/commands/`,
`bmalph/config.json`); it refuses (exit 1) on tracked changes unless `BMALPH_DRY_RUN=true`. `_bmad/`,
`_bmad-output/`, `.ralph/`, `bmalph/state/` are git-ignored. Planning bundle format (template skill, normative
for bmalph): `specs/<bundle-id>/{research,product-brief,prd,architecture,epics,implementation-readiness,run-summary}.md`;
`prd.md` H2s `Executive Summary`, `Functional Requirements`, `Non-Functional Requirements`, `Product Scope`;
`architecture.md` `## Tech Stack` names only the Rust toolchain and crates; `epics.md` `## Epic N: Title`,
`### Story N.M: Title`, `**Acceptance Criteria:**` with `**Given**/**When**/**Then**`; readiness verdict
"ready" or "needs work".

## Mapping: PHP Plugin to Rust Plugin

### Commands (prefix `rs-sdlc`, stage labels unchanged)

| php command | Rust command | Port | Rust-specific delta |
| --- | --- | --- | --- |
| `sdlc.md` | `rs-sdlc.md` | contract verbatim | branch step `<type>/<issue>-<slug>` before implement; durable stage record; full review exit string; finish-pr row with counters A/B/C; managed label `rust-backend-sdlc` |
| `sdlc-setup.md` | `rs-sdlc-setup.md` | order verbatim | preflight adds `toml-toolchain`, `gnu-make`; `make bmalph-setup` only on a clean tree and only when `_bmad/` is absent; allowlist → `.claude/settings.local.json` via `merge-settings.sh`; optional `make install-hooks`; `make docs-check` after injection when the toolchain is available; "commit profile and governance block together" |
| — | `rs-sdlc-new-service.md` | new | `new-service.sh` (deterministic steps) + guided judgment (example context, secrets, labels, branch protection) + bootstrap issue/branch/PR + `/rs-sdlc-setup` in the new checkout |
| — | `rs-sdlc-new-context.md` | new | `make new-context` + wiring checklist dispatched to `rust-implementer` + context gate set + `feat(#N): add <group>/<context> bounded context` |
| `sdlc-issue.md` | `rs-sdlc-issue.md` | verbatim | body follows `.github/ISSUE_TEMPLATE/feature_request.md` H2s when present (`Problem statement`, `Proposed change`, `Affected area`, `Tasks`, `Acceptance criteria`); labels `rust-backend-sdlc` + `enhancement`; emits `ISSUE_NUMBER:` |
| `sdlc-plan.md` | `rs-sdlc-plan.md` | non-interactive loop verbatim | template artifact set and bmalph format; slug `<issue>-<kebab-title>`; readiness "ready"; regex self-check; `Depends on:` metadata line per story; repository skill wins |
| `sdlc-implement.md` | `rs-sdlc-implement.md` | dispatch + breaker verbatim | `stage-planning-artifacts.sh`; `bmalph implement` (never `--force`); `bmalph run --driver claude-code --no-dashboard`; per-story commit `<type>(#N): story N.M <title>`; shared-DB rule for parallel stories; final coverage run |
| `sdlc-review.md` | `rs-sdlc-review.md` | triage + two lenses verbatim | Rust metric rows; `fix(#N)` remediation commits; conclusion deferred when no PR; ledgers under `target/rust-sdlc/` |
| `sdlc-qa.md` | `rs-sdlc-qa.md` | black-box contract verbatim | readiness `/ping` + `/api/health`; probe set from the OpenAPI snapshot and SDL; GraphQL via POST; problem+json negatives; no Write/Edit (L33) |
| `sdlc-finish-pr.md` | `rs-sdlc-finish-pr.md` | A/B state machine verbatim | title pre-validated with `COMMIT_TITLE=… make check-commit-message`; PR body from `.github/pull_request_template.md`; `pr-state.sh` + `request-ai-reviews.sh`; counter C (gate, max 3); human-gated checks never labelled by an agent |

### Agents

| php agent | Rust agent | Delta |
| --- | --- | --- |
| `php-implementer` | `rust-implementer` (sonnet) | make-only; Rust suppression list; layer rules; co-change rules (contracts, `workspace.dsl`, migrations + `.sqlx/`); verify set; protected change → `BLOCKED` naming `approved-config-change`; guard-hook denial reported verbatim |
| `code-quality-reviewer` | same (opus) | rows: format-check, static-analysis, complexity, architecture, unused-dependencies, check-security, coverage (lines, functions), mutation-diff; never runs `-fix` targets; root-cause remedies only |
| `fr-nfr-reviewer` | same (opus) | requirement ids `FR-12`/`FR12`/`NFR-3`/`G12`; evidence via test targets only; react gate interface |
| `ci-fixer` | same (sonnet) | check-name → target mirror for the 36 required checks; human-gated checks; RUSTSEC advisory without fix → escalate |
| `pr-comment-resolver` | same (sonnet) | decline list: `#[allow]`, unjustified `#[expect]`, protected-config edits, coverage or mutant exclusions, lowered thresholds |
| `qa-manual-tester` | same (sonnet, `Bash, Read`) | forbidden reads `crates/ tests/ features/ xtask/ migrations/ .sqlx/ Cargo.toml`; allowed: profile, spec bundle, logs, fetched OpenAPI |
| `security-auditor` | same (opus) | static lanes `check-security`, `secrets-scan`, `image-scan`, clippy; sqlx dynamic-SQL taint; families incl. BOLA, mass assignment (`deny_unknown_fields`), DoS (body limit, timeout, GraphQL depth), information disclosure; memory safety N/A (`unsafe_code = "forbid"`); loopback boundary on `http://localhost:8081` |

### Skills (22 mapped + 6 new = 28, + 2 meta-guides)

| php skill | Rust skill | Template counterpart (repository wins) | Gate key (L18) |
| --- | --- | --- | --- |
| `api-platform-crud` | `api-resource-development` | same name | `framework.graphql` |
| `bmad-autonomous-planning` | `bmad-autonomous-planning` | same name | — |
| `bmad-fr-nfr-review-gate` | `bmad-fr-nfr-review-gate` | — | `capabilities.publish_pr_comments` |
| `cache-management` | `cache-management` | — | — |
| `ci-workflow` | `verification-workflow` | same name | — |
| `clean-architecture-llm` | `clean-architecture-llm` | — | — |
| `code-organization` | `code-organization` | — | — |
| `code-review` | `code-review` | — | `capabilities.publish_pr_comments` |
| `complexity-management` | `complexity-management` | same name | — |
| `database-migrations` | `database-migrations` | recipe only | `persistence.engine` |
| `deptrac-fixer` | `architecture-boundary-fixer` | same name | — |
| `documentation-creation` | `documentation-creation` | — | — |
| `documentation-sync` | `documentation-sync` | same name | — |
| `implementing-ddd-architecture` | `implementing-ddd-architecture` | — | — |
| `load-testing` | `load-testing` | same name | `capabilities.load_testing` |
| `observability-instrumentation` | `observability-instrumentation` | — | backend selector, not skip-gated |
| `openapi-development` | `api-contract-development` | same name | `framework.graphql` |
| `quality-standards` | `quality-standards` | same name | — |
| `query-performance-analysis` | `query-performance-analysis` | — | `persistence.engine` |
| `security-audit` | `security-audit` | — | `capabilities.dynamic_security_testing` |
| `structurizr-architecture-sync` | `architecture-model-sync` | same name | `capabilities.structurizr` |
| `testing-workflow` | `testing-workflow` | same name | `capabilities.load_testing` (load section) |
| — | `service-scaffolding` (new) | — | — |
| — | `bounded-context-scaffolding` (new) | — | — |
| — | `rust-error-handling` (new) | — | — |
| — | `async-runtime-safety` (new) | — | — |
| — | `dependency-policy` (new) | — | — |
| — | `configuration-management` (new) | — | — |

Eleven Rust skills share a name with a template skill; each gets a `## Repository precedence` H2 right after
`## Profile keys consumed` (read the repository skill first; it and `AGENTS.md` win; the plugin adds only the
SDLC wrapper: profile resolution, evidence format, bounded loop, escalation block, verdict line). The template's
skill names were adopted so the precedence lookup is mechanical (`test -f .claude/skills/<name>/SKILL.md`).

### Scripts

| php script | Rust script | Delta |
| --- | --- | --- |
| `lib/common.sh` | `lib/common.sh` | `[rust-sdlc]` prefix; profile `.claude/rust-sdlc.yml`; mikefarah `have_yq` probe; `toml_get`/`toml_get_list`/`toml_has` via python3 `tomllib`; `yaml_squote` (Prettier-compatible quoting); `resolve_repo_slug`; `is_kebab`, `is_slug`, `is_semver`; `claude_run_isolated` (react) |
| `setup-preflight.sh` | same | + `toml-toolchain`, `gnu-make` (≥ 4.0), claude floor for `--restricted` (≥ 2.1.248) when the hardened gate is used; dirty tracked tree reported before `bmalph-setup`; Docker and Rust toolchain stay `make doctor`'s concern |
| `generate-profile.sh` | same | detection from `Cargo.toml`, `rust-toolchain.toml`, `architecture.toml`, `clippy.toml`, `make/gates.mk`, `protected-config.toml`, Makefile + `make/service.mk` targets, workflows, `docs/repository-settings.md` (`yes` rows), `.coderabbit.yaml`, sync workflows; never runs `cargo` or `make`; block-style YAML |
| `validate-profile.sh` | same | Rust required keys, enums, make-map completeness, tighten-only floors and ceilings |
| `inject-governance.sh` | same | algorithm byte-identical; markers `rust-backend-sdlc`; docs-check-safe content |
| — | `merge-settings.sh` (new) | merge-not-clobber into `.claude/settings.local.json`; refuses `.claude/settings.json` when protected; `--print` |
| `ai-review-loop.sh` | same | default diff base `origin/<default branch>`; Rust review prompt |
| `fr-nfr-gate.sh` | same (react interface) | `--spec-path --pr --impact-context --iteration --advisory`; Rust baseline NFR catalog; fail-closed no-source path |
| `get-pr-comments.sh` | same | renames only, `resolve_repo_slug` |
| `post-review-findings.sh` | same | markers `<!-- rust-sdlc-review:<lens> -->`; ledger dir `target/rust-sdlc/review-ledgers`; X16 fixes |
| — | `new-service.sh` (new) | deterministic `docs/new-service.md` steps; `--dry-run`; idempotent `UNCHANGED:` |
| — | `stage-planning-artifacts.sh` (new) | copy `specs/<slug>/` into `_bmad-output/planning-artifacts/` (research as `technical-research.md`); exit 0/1/2 |
| — | `pr-state.sh`, `request-ai-reviews.sh` (from react) | profile-defaulted reviewers and required checks; `--human-gated-checks` |

### Tests, docs, config, repository wiring

| Area | php | Rust |
| --- | --- | --- |
| bats suites | 10 (239 tests) | the 10 ported + `new-service.bats`, `merge-settings.bats`, `stage-planning-artifacts.bats`, `pr-state.bats`, `request-ai-reviews.bats`, and `workflows.bats` with the epic |
| Fixtures | PHP stub repo, profiles, ledgers, gh payloads, `bin/{claude,gh,bmalph}` | Rust stub repo (`acme/billing-service`, `crates/billing/invoice/*`), Rust paths in ledgers and gh payloads, `bin/cargo`, `bin/make` stubs; Markdown files and `_bmad`/`.ralph` dirs generated at runtime |
| `component-counts.bats` | 8 / 7 / 22 / 2 | 10 / 7 / 28 / 2 (+ 4 workflows); plus plugin-local tests for `/rs-sdlc*` tokens and `rust.*`-style keys |
| docs | 6 + testing | + `new-service-walkthrough.md`, `workflows.md` (epic); `profile-schema.md` gains a detection-source table that backticks `architecture.toml` |
| config | — | `config/new-service.defaults.json` |
| workflows | — | `workflows/rs-sdlc-{feature,review-panel,pr-until-green,fr-nfr-review}.js` + `tests/lib/workflow-harness.mjs` |
| Repo | marketplace entry, README row, CI jobs php-only | marketplace entry (`source: ./plugins/rust-backend-sdlc`), README row + install line, `ci.yml` tag filter + explicit php/rust lists in two jobs |

## Integration Hazards

| # | Hazard (evidence) | Consequence | Mitigation |
| --- | --- | --- | --- |
| H1 | **Protected `.claude/settings.json`** (`tpl/protected-config.toml:57`, guard hook in `tpl/.claude/settings.json`) | a php-style setup edit is blocked (exit 2) in-session; a Bash rewrite evades the hook but fails G25 "Protected configuration" in CI | `merge-settings.sh` writes only `.claude/settings.local.json` (git-ignored) or prints the JSON; it detects protection by reading `protected-config.toml` `files`; never weaken the template's deny/ask rules (deny > ask > allow keeps them effective) |
| H2 | **docs-check rule 2** (slash commands) | a backticked `/rs-sdlc-*` in `CLAUDE.md`/`AGENTS.md` fails G26 in every service | governance block names plugin commands in plain prose only; bats test asserts no code span starting with `/` in the block |
| H3 | **docs-check rule 3** (paths) | a backticked `.claude/rust-sdlc.yml` that is not yet tracked, or any `scripts/<plugin-script>.sh`, fails G26; a local run passes because untracked Markdown is not read | backtick only paths that exist in every template-derived repo (`AGENTS.md`, `protected-config.toml`, `.claude/skills/README.md`) plus the profile; setup reports "commit the profile and the governance block in the same commit"; never cite plugin script paths in service files |
| H4 | **docs-check rule 4** (gate lists) | a fenced block or numbered list naming three gates fails G26 | bullets citing profile keys; link to the AGENTS.md verification section; never copy `make ci-list` output into a tracked file; bats test counts gate names per list/fence |
| H5 | **docs-check needs a compiled service** (`tpl/Makefile:440-446`) | running it after injection without the toolchain or Docker exits non-zero for environmental reasons | run `make docs-check` when `make doctor` passes or the profile selects container execution and Docker is reachable; otherwise a degrade note plus the plugin's static block tests; never report it as passed |
| H6 | **Invariant (e)** template name in `AGENTS.md`/`CLAUDE.md` (`tpl/scripts/check-invariants.sh:51,718`) | a block or profile reference that spells the template name fails G31 | block text never contains it; the profile may (`.claude/` outside `skills/` is unscanned — verified in `notes/rust-template.md` §1 item 8) |
| H7 | **Template sync wipes the block** (`CLAUDE.md`, `AGENTS.md` absent from `tpl/.templatesyncignore`) | after each merged `template_sync` PR the governance block is gone | `/rs-sdlc-setup` is idempotent and re-runnable; `/rs-sdlc` stage 0 and `/rs-sdlc-review` warn when markers are missing; do not add the files to `.templatesyncignore` (the verification block must follow the Makefile) |
| H8 | **AGENTS.md verification markers** | a block inserted between `<!-- verification:start -->`/`end` breaks rule 4's equality with `make ci-list` | inject outside the markers (append at end or keep the existing block position) |
| H9 | **yamllint/Prettier/typos on the profile** (`tpl/.yamllint.yml`, `tpl/.prettierrc.yml`, `tpl/Makefile:85`, `tpl/_typos.toml`) | php-style double-quoted flow lists fail `make lint-prettier`; `yes`/`no` values fail yamllint `truthy`; a `---` header fails nothing but diverges; repo-derived words may trip typos | block style, 2-space indent, sequences indented under keys, `yaml_squote` for repo-derived strings, bare enums/targets/ints/bools, quoted versions, single trailing newline, no `---`; bats tests run yamllint/Prettier when installed |
| H10 | **Commit-message hook and title check** (`tpl/scripts/check-commit-message.sh:14`, `.githooks/commit-msg`) | every php commit form is rejected; a PR title without `(#N)` fails "Pull-request title" | one commit builder `<type>(#<issue>): <subject>`; issue number from `ISSUE_NUMBER:`, else PR title, branch `^[a-z]+/([0-9]+)-`, PR body `Closes #N` — never the PR number; pre-validate titles with `COMMIT_TITLE='…' make check-commit-message` |
| H11 | **Pre-commit and pre-push hooks compile the workspace** (`tpl/.githooks/pre-commit` → `make pre-commit`) | each commit costs minutes and needs the toolchain; in a Docker-only host commits fail unless `RUN_IN_CONTAINER=1` is in the environment | commands export `RUN_IN_CONTAINER=1` for `git commit`/`git push` when the profile selects container execution; 600 s tool timeouts; a red hook is an iteration finding, never `--no-verify` (denied anyway) |
| H12 | **Template's own skills** (11, same names as 11 plugin skills) | the model may follow only the plugin copy and contradict repository rules; triage cost doubles | `## Repository precedence` H2 in every overlapping plugin skill; triage records one verdict per pair (source `repo+plugin`); never copy plugin skills into `.claude/skills/` (docs-check rule 7 and sync would break) |
| H13 | **Template's own commands** (54 BMAD wrappers requiring `_bmad/`) | `/rs-sdlc-plan` fails on a fresh clone when it relies on wrappers before `make bmalph-setup` | setup runs `make bmalph-setup` first on a clean tree; plan loads the planning skill directly, never the wrappers; no name collision exists (no wrapper starts `rs-sdlc`) |
| H14 | **`make bmalph-setup` refuses a dirty tree and restores tracked files** | re-running setup after an uncommitted governance injection exits 1; running it after injection would revert `CLAUDE.md` | order: preflight → bmalph-setup (only when `_bmad/` is absent) → generate → validate → inject → merge-settings; preflight reports a dirty tree with remediation "commit or stash, or preview with `BMALPH_DRY_RUN=true`" |
| H15 | **bmalph artifact discovery** (`bmalph/dist/transition/artifacts.js:6-8`) | `bmalph implement` finds nothing in `specs/<slug>/`; the template forbids writing bundles under `_bmad-output/` | `stage-planning-artifacts.sh` copies the bundle into the git-ignored `_bmad-output/planning-artifacts/` (clearing foreign files), renaming `research.md` to `technical-research.md` |
| H16 | **Readiness regex** (`bmalph/dist/transition/preflight.js:142`) | innocent phrases (a "no" followed by a word starting "go") block `bmalph implement` | plan loop greps the readiness file with the same regex before declaring "ready"; writers avoid such phrases; never pass `--force` |
| H17 | **yq variants** (host kislyuk, CI mikefarah) | php-style `have_yq` misreads quoted scalars and `type` on the host; tests pass in CI and fail locally | react probe (`.a \| type` must print `!!seq`, cached in `_SDLC_YQ_OK`); `SDLC_FORCE_PYTHON_YAML=1` forces PyYAML; yq-dependent tests gate on `have_yq`, not `command -v yq` |
| H18 | **NFR-2 denylist vs template slug default** (`check_generalization.py`, slug contains the denied org token) | spelling the default slug or the template's secret names in a command, skill, agent or script is an S1 lint finding and a CI failure; `.sh` has no escape fence | default slug in `config/new-service.defaults.json` (unscanned), read by `new-service.sh` through `resolve_plugin_root`; override order `--template` > `RUST_SDLC_TEMPLATE_REPO` > config; secret and label names read from the target's `docs/new-service.md` at runtime or described generically; fixtures use `acme/rust-template` |
| H19 | **Lint blind spots** (L22 `/sdlc` only, L25 prefixes and file extensions, L18 predicate) | `/rs-sdlc-*` typos ship unnoticed; a stray `/sdlc-…` mention is flagged; backticked `architecture.toml` is flagged; gating on a `rust.*` key does not satisfy L18 | gating flags under `capabilities.`/`framework.`/`persistence.`; the schema backticks `architecture.toml` (detection-source table); plugin-local bats tests for command tokens and non-L25 namespaces; lint widening as a separate repository change |
| H20 | **CI jobs hard-coded to php** (`ci.yml:10,219,257`) | the Rust plugin escapes `profile-keys-check` and `generalization-audit`; tag builds are not triggered | add `rust-backend-sdlc-v*` to the tag filter; loop both jobs over `plugins/php-backend-sdlc plugins/rust-backend-sdlc` (explicit list; a glob fails on devops) |
| H21 | **CI profile-keys-check treats any dotted lower-case backticked token in a skill's key section as a key** | listing `clippy.toml` or `deny.toml` in `## Profile keys consumed` fails unless the schema declares it | keep file names out of that section, or declare them in the schema's detection-source table |
| H22 | **Markdown and `_bmad` fixtures** (CI markdown-lint over all plugin `.md`; L29) | a stub `README.md`/`CHANGELOG.md` must be markdownlint-clean; a fixture dir named `_bmad` or `.ralph` is an S1 finding | generate those files in bats `setup()` under `$BATS_TEST_TMPDIR` (heredocs or `*.md.tpl` renamed at runtime) |
| H23 | **Ledger and state location** (`.sdlc/` untracked in a service; Prettier, gitleaks files mode, typos) | review ledgers appear in `git status`, in Prettier and secrets scans | `${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}` and `target/rust-sdlc/state/`; `cargo clean` loss is tolerated because resume re-derives stages from durable artifacts (issue label, bundle, commits, PR, commit status) |
| H24 | **Poster markers shared with php** | a repository running both plugins would cross-edit the other plugin's PR comments | markers `<!-- rust-sdlc-review:<lens> -->` and `<!-- rust-sdlc-review:conclusion -->` |
| H25 | **Shared test database** (`tpl/Makefile:405`) | parallel story or fix agents running DB-backed targets clobber each other; flaky failures read as real | parallel prompts run only DB-free targets (`format`, `unit-tests`, `lint-code`, `architecture`, `complexity`); one serialized verify step runs the DB gates; no `isolation: 'worktree'` (full recompiles, Compose name and port clashes) |
| H26 | **Docker-dependent and long gates** (HOST targets exit 2 without Docker; `make ci` ~25 min; Bash foreground cap 600 s) | sandboxed sessions cannot run QA or a third of the gates; one `make ci` call times out | degrade with `make doctor` output and `SUCCESS-WITH-REPORT`, never a faked pass; run stage targets individually (`make ci-preflight` … `make ci-cli`) or in the background |
| H27 | **Git-state gates** (G17 porcelain, G15 untracked, G25 base ref) | snapshots regenerated but uncommitted fail; new untracked files are not mutated; fresh or local repos exit 2 | commit snapshots before G17; `git add` before mutation runs; `git fetch origin <default>` or `base_ref=<ref>`; new-service local mode documents `base_ref=HEAD` until `origin/main` exists |
| H28 | **Protected directories and human-gated checks** (`tests/CLI/bats/`, `xtask/tests/`; change-control jobs) | a needed service Make target, Bats test, layer allow-list entry, `deny.toml` exception, equivalent mutant or budget change cannot be produced by an agent | escalate as `ESCALATED`/`BLOCKED` naming `approved-config-change` (+ `ALLOW_PROTECTED_CONFIG_EDIT=1` restart) or `approved-breaking-change`; agents never apply labels; ci-fixer reports human-gated checks separately |
| H29 | **Example-context removal** (three rule-3 lines, GraphQL root risk, breaking contract change) | `--remove-example` breaks docs-check and possibly the schema build | default keep-example; removal only as a guided `rust-implementer` story that edits the three lines, adds them to `.templatesyncignore`, replaces (not deletes) the GraphQL roots with the first real context, regenerates snapshots before the first snapshot reaches `main` |
| H30 | **Identity and licence invariants** (checkout dir = `PROJECT_NAME`; licence pinned to CC0-1.0; version change needs a lock refresh) | a mismatched directory name gives wrong Compose/image names; a licence change fails G31; a version change without `cargo update --workspace` fails G5 | clone into `./<service-name>`; never offer a licence change; keep `version = "0.1.0"` unless asked, and then report the lock refresh as a `NEXT:` step |
| H31 | **Generation never calls cargo** (`rust-toolchain.toml` makes rustup download 1.99.1) | slow, networked, nondeterministic setup | read TOML with python3 `tomllib` only (3.11+; host 3.13, CI 3.12) |
| H32 | **Workflow nesting** (Key Finding 22) | a ported feature workflow escalates at finish-pr on every fresh PR head | hand-back contract (Workflow Port Assessment) |

## Workflow Port Assessment

### What react ships

| File | Lines | Role |
| --- | --- | --- |
| `workflows/fe-sdlc-feature.js` | 251 | top-level orchestrator: setup check → resolve plan → implement rounds → nested review panel → nested FR/NFR gate → QA → PR → nested pr-until-green |
| `workflows/fe-sdlc-review-panel.js` | 304 | leaf: scope + triage, parallel lenses, 3 refuters per finding, grouped fixes, ≤ 5 iterations |
| `workflows/fe-sdlc-fr-nfr-review.js` | 318 | leaf: scope (bundle, PR sources, clean tree, head match), gate loop ≤ 5, advisory mode |
| `workflows/fe-sdlc-pr-until-green.js` | 483 | sensor loop: Snapshot, Request reviews, Wait, Fix, FR/NFR gate, Publish; counters fix 5, wait 6, request 3, gate 3 |
| `scripts/pr-state.sh`, `scripts/request-ai-reviews.sh` | 398, 228 | sensor and review-request cadence |
| `tests/lib/workflow-harness.mjs` | 92 | node harness: meta extraction, scenario-matched agent replies, mocked `workflow()` |
| `tests/workflows.bats`, `pr-state.bats`, `request-ai-reviews.bats` | 49, 30, 17 tests | all green locally (`notes/react-workflows-repo-ci.md` §0.2) |

### Runtime contract and the defect

The Workflow tool runs plain JavaScript with `agent`, `parallel`, `pipeline`, `phase`, `log`, `workflow`,
`budget`, `args`; `Date.now()`, `Math.random()` and argless `new Date()` throw; `meta` must be a pure literal; a
nested `workflow()` call is allowed only one level deep. React violates the depth rule (Key Finding 22). Fix
for Rust: `rs-sdlc-pr-until-green` accepts `onGate: 'nested' | 'return'` (default `'nested'` when called at top
level); `rs-sdlc-feature` calls it with `onGate: 'return'`, and on a `GATE` result runs
`rs-sdlc-fr-nfr-review {pr, head}` itself, publishes fixes, then re-enters `pr-until-green` with
`carry: {counters, journal, degrade_notes}` so budgets resume; a feature-owned gate counter stops at 3. The
harness gains `--as-child` (any `workflow()` call throws) and `workflows.bats` gains a static call-graph test.
The design is valid whether or not the depth rule is enforced exactly as quoted, because no path exceeds depth
one.

### Per-workflow delta

| Workflow | Generic share | Rust changes |
| --- | --- | --- |
| `rs-sdlc-pr-until-green` | sensor protocol, counters, READY double-check, dropped-reviewer degrade | `onGate`/`carry`; reviewers default from profile `review.reviewers`, not `coderabbit,cubic`; ci-fixer prompt: human-gated checks, make-only, title fix via `gh pr edit`; publish commit `fix(#N): …` with issue-number derivation (never the PR number), hooks on, 600 s timeouts |
| `rs-sdlc-review-panel` | scope/triage, refuters, fix grouping by first three path segments (`crates/<group>/<context>`) | security lens (`security-auditor`, `securityFamilies: ['all']`) replaces the accessibility lens; file classes `*.rs`, manifests, migrations, contract snapshots; Rust fix prohibitions; agent types `rust-backend-sdlc:*` |
| `rs-sdlc-fr-nfr-review` | sources, advisory, ledger, transport handling — byte-for-byte | renames; `.claude/rust-sdlc.yml`; Rust fix prohibitions; depends on the react-interface `fr-nfr-gate.sh` |
| `rs-sdlc-feature` | stage composition | layer-first implementation order (domain → application → infrastructure → `crates/service` wiring, with migration, snapshots and `workspace.dsl` in the same story); shared-resource rule + serialized verify agent; QA through `make start` and the REST/GraphQL/health probe set; branch `<type>/<issue>-<slug>`; hand-back loop |

### Rust-specific risks

| Risk | Severity | Decision |
| --- | --- | --- |
| Grandchild `workflow()` | HIGH | hand-back, `--as-child`, call-graph test |
| Parallel agents in one Cargo workspace and one test DB | HIGH | DB-free targets in parallel; serialized verify agent; cargo build-lock waits are expected |
| Gates longer than the 600 s foreground cap | MEDIUM | stage targets individually, never `make ci` in one foreground call |
| Commit and title convention | MEDIUM | `fix(#N):`/`feat(#N):` pinned by bats |
| Human-gated change-control checks | MEDIUM | `ci.human_gated` in the sensor, BLOCKED naming the label |
| Absent second AI reviewer wastes ~27 min of request rounds | LOW | profile reviewers (`[coderabbit]` when `.coderabbit.yaml` exists) |
| Plugin workflow name resolution unverified offline | LOW | keep graceful escalation with manual commands |

### Dependencies, effort, verdict

Dependencies: `lib/common.sh` (`resolve_repo_slug`, YAML helpers), `get-pr-comments.sh`, the react-interface
`fr-nfr-gate.sh`, the 7 agents, `pr-state.sh`, `request-ai-reviews.sh`. Effort: ≈ 1,500 LOC of workflows,
≈ 700 LOC of sensor and request scripts, ≈ 110 LOC harness, ≈ 58 workflow tests and ≈ 52 sensor tests,
≈ 260 lines of docs. Verdict: **include** as an epic of 6 stories ordered (1) sensor + request scripts with
tests, (2) harness + contract tests, (3) fr-nfr-review, (4) review-panel, (5) pr-until-green with `onGate`,
(6) feature + docs + counts. Risk is controlled because the harness is deterministic (no model in the loop) and
the Rust plugin needs only node + jq in CI, both present on `ubuntu-latest`.

## Recommendations

1. **Identity.** Apply the fixed identity verbatim; add poster markers `rust-sdlc-review:<lens>`, temp names
   `.rust-sdlc.yml.XXXXXX` / `.rust-sdlc-governance.XXXXXX`, env prefix `RUST_SDLC_` for new variables, keep the
   shared names `SDLC_FORCE_PYTHON_YAML`, `SDLC_LEDGER_DIR` and the status context `BMAD FR/NFR Review Gate`.
2. **Inventory.** 10 commands, 7 agents (`rust-implementer`, `code-quality-reviewer`, `fr-nfr-reviewer`,
   `ci-fixer`, `pr-comment-resolver`, `qa-manual-tester`, `security-auditor`), 28 skills + 2 meta-guides,
   13 executable scripts + `lib/common.sh`, 4 workflows; pin every count in `component-counts.bats`.
   > Assumption: 28 skills exceed the "~25" guidance by 3; php parity (1:1 mapping) plus six Rust-only skills
   > outweighs the guidance, so parity wins.
3. **Contracts.** Port the stage, guard, escalation, run-report, handle, degrade, null-substitution, git-ownership
   and triage contracts verbatim; fix X1–X19; add `ISSUE_NUMBER:`, the branch step and a durable stage record
   under `target/rust-sdlc/state/`.
4. **Execution.** Make-only through the profile `make.*` map; a container flag (see Open Question 2) prefixes
   `RUN_IN_CONTAINER=1`; the only raw commands are the template-sanctioned ones (`cargo tree -i`,
   `cargo metadata`, `cargo xtask config-guard --list`, `scripts/with-env.sh .env .env.test -- cargo nextest run
   -p <crate> <name>`). Long gates run stage by stage.
5. **Profile.** `schema_version: 1`; keys under the L25 namespaces wherever natural; gating booleans under
   `capabilities.*`/`framework.*`/`persistence.*`; tighten-only validation (floors `quality.coverage_lines`,
   `quality.coverage_functions` = 100; zero-count ceilings for clippy, architecture, unused dependencies,
   dependency policy, surviving mutants); every documented key emitted by the generator; emission rules of
   H9; required checks parsed from `docs/repository-settings.md` `yes` rows (36 today); template slug and sync
   flavour recorded for information.
6. **Setup.** Order: `setup-preflight.sh --report` → `make bmalph-setup` (clean tree, `_bmad/` absent) →
   `generate-profile.sh` → `validate-profile.sh` (bounded `--refresh` retry, max 5) → `inject-governance.sh` →
   `merge-settings.sh` → optional `make install-hooks` → `make docs-check` when possible → summary naming the
   files to commit together. Exit: preflight PASS + profile valid + governance in both files + allowlist
   present + docs-check green or degraded with a note.
7. **Governance block.** H2 `rust-backend-sdlc governance (managed block — do not edit between markers)` with
   bullets for the skill-triage gate, repository-rules-first, tighten-only bars and make-only execution; prose
   slash commands; backticked paths only from H3's list; no gate lists; no template name; outside the
   verification markers; markdownlint-clean under the template config.
8. **Plan and implement.** Bundle `specs/<issue>-<kebab-title>/` in the template format; `Depends on:` metadata
   per story; readiness "ready" + regex self-check; `stage-planning-artifacts.sh`; `bmalph implement` without
   `--force`; `bmalph run --driver claude-code --no-dashboard`; per-story hook-valid commits; final
   `tests-with-coverage` run; Ralph breaker never reset.
9. **Review.** Triage over plugin skills with repository-skill rows; two lenses + security lens when Rust,
   manifest or migration files changed; mutation run once per iteration only when production code changed;
   `fix(#N)` remediation commits; conclusion deferred to finish-pr when no PR exists.
10. **QA.** Boot with `make.start`; readiness `/ping` then `/api/health`; probe set from the committed OpenAPI
    snapshot and SDL plus acceptance criteria; evidence (method, path, body, status, content type,
    `x-request-id`, excerpt); assert status + `type` + content type, not axum rejection texts; never stop the
    shared stack; no Write/Edit.
11. **Finish PR.** Title validated locally; body from the PR template with `Closes #N` and "targets run / not
    run with reason"; `pr-state.sh` + `request-ai-reviews.sh`; counters A (ci_fix 5), B (comment_resolution 5),
    C (gate 3); exit "CI green + gate green on the head + 0 unresolved threads"; labels never applied by agents.
12. **FR/NFR gate.** Port react's hardened `fr-nfr-gate.sh` with a Rust baseline catalog: `NFR-BASE-TEST`
    (100% lines+functions, zero surviving mutants on changed code), `NFR-BASE-QUALITY` (no `#[allow]`, clippy
    clean, complexity limits), `NFR-BASE-ARCH` (`architecture.toml`, pure domain, `workspace.dsl` current),
    `NFR-BASE-CONTRACT` (snapshots regenerated, breaking changes labelled), `NFR-BASE-DATA` (no edited applied
    migration, `.sqlx/` current), `NFR-BASE-SEC`, `NFR-BASE-OBS`.
13. **New service.** `new-service.sh --name --description (--template | --template-path | --in-place) [--owner]
    [--visibility] [--dest] [--version] [--intro] [--sync-flavour app|pat] [--keep-specs] [--dry-run]`; steps
    source → identity (inside `[workspace.package]` only) → `bmalph/config.json` → README badges/title/intro →
    CHANGELOG cocogitto skeleton → `specs/` reset → sync flavour + `.templatesyncignore` → `DONE:/SKIP:/UNCHANGED:`
    report and `NEXT:` lines (`make generate-openapi-spec`, `make doctor`, `make bootstrap`, `make install-hooks`, setup,
    bootstrap commit on `chore/<issue>-initialize-service`); exit 0/1; never commits, never removes the example.
    The command adds the guided steps and a bootstrap issue/branch/PR in GitHub mode.
14. **New context.** Name checks mirroring xtask; `make new-context`; wiring story to `rust-implementer`;
    verify set `architecture`, `check-crate-isolation`, `validate-architecture-model`, `static-analysis`,
    `unused-dependencies`, `validate-sqlx-metadata` (with a migration), `validate-contract-snapshots`,
    `tests-with-coverage`, then `validate-configuration` to prove no protected change; commit
    `feat(#N): add <group>/<context> bounded context` (issue required).
15. **Tests.** Hermetic bats (stubs for `claude`, `gh`, `bmalph`, `cargo`, `make`); uid-0 skips; `have_yq`
    gating; runtime-generated Markdown and `_bmad`/`.ralph` fixtures; yamllint/Prettier parity tests when the
    tools exist; governance-block docs-check-rule tests; plugin-local token tests for `/rs-sdlc*` and
    non-L25 keys.
16. **Docs.** `profile-schema.md` (with detection sources incl. `architecture.toml`), `setup-walkthrough.md`,
    `sdlc-loop.md`, `permissions.md`, `degrade-matrix.md` (+ protected settings, no Docker, null mutation,
    snapshots absent, sync flavour undecided), `release-process.md` (tag `rust-backend-sdlc-vX.Y.Z`),
    `new-service-walkthrough.md`, `testing/test-strategy.md` (+ new-service and template-integration surfaces),
    `workflows.md`.
17. **Repository wiring.** Marketplace entry (`source: ./plugins/rust-backend-sdlc`, category `development`);
    README plugin row and install line; `ci.yml` tag filter and explicit php + rust lists in
    `profile-keys-check` and `generalization-audit`; no Python in the plugin; no lint widening in the plugin PR.
18. **Workflow epic.** Include it (6 stories) with the hand-back fix, the shared-resource rule and the
    profile-defaulted reviewers.

## Open Questions

1. **Complexity limits in the profile.** Mirror `quality.complexity.{cognitive,lines,arguments,nesting}` as
   lower-only ceilings, or record only a zero-violation ceiling and cite `clippy.toml`? A stricter profile value
   cannot be enforced by `make complexity` (limits are read from the protected `clippy.toml`). Recommended
   default: zero-violation ceiling only in v0.1.0; quote the limits from `clippy.toml` at review time.
2. **Final profile namespaces.** `rust.*`, `service.*`/`runtime.*`, `execution.*` are clearer but invisible to
   L25; folding them into `project.*`/`capabilities.*` keeps lint coverage. Recommended default: `rust.*` for
   toolchain facts and `service.*` for runtime URLs and paths, with the plugin-local declaration test; the
   container switch as `capabilities.run_in_container` (gating predicate).
3. **QA network permissions.** Add loopback-scoped `curl` entries to `.claude/settings.local.json`, or accept
   prompts? Prefix semantics of `Bash(curl …:*)` with varying flag order need checking. Recommended default:
   print, do not write, the curl entries in v0.1.0.
4. **Example-context removal scope.** Automate the docs-check line edits and `.templatesyncignore` updates in
   `new-service.sh`, or keep them in the guided implementer story? Recommended default: guided story only.
5. **Lint widening timing.** Widen L22/L25 in `tools/plugin-quality` before or after the plugin lands (needs
   unit tests and 100% coverage of the lint package)? Recommended default: after, as a separate change.
6. **`gh repo create --template` timing.** Whether `--clone` races the asynchronous template generation was not
   verified. Recommended default: create without `--clone`, poll the commits API (10 × 3 s), then clone.
7. **Empty GraphQL root.** Whether a `MergedObject` `Query` with no context field compiles and exports a valid
   SDL was not compiled here. Recommended default: treat as invalid; replace, never delete.
8. **Durable stage record format.** JSON under `target/rust-sdlc/state/<slug>.json` (lost on `cargo clean`) vs
   GitHub-side records only (issue comments, commit statuses). Recommended default: local JSON as a cache, with
   GitHub artifacts as the source of truth on resume.
9. **Template version drift.** The template has no tags; gate names, xtask commands and file paths may change.
   Recommended default: detect capabilities at setup (template heuristic: `rust-toolchain.toml`,
   `architecture.toml`, `protected-config.toml`, `xtask/Cargo.toml`, `make/gates.mk`, `crates/service/Cargo.toml`,
   `workspace.dsl`, and `make ci-list` starting with `validate-configuration`), read lists at runtime, and record
   the template commit in the profile for diagnostics.
10. **Docker-less sessions.** When `make.start` is mapped but Docker is unreachable, is QA `SUCCESS-WITH-REPORT`
    or `ESCALATED`? Recommended default: ESCALATED at stage 5 with the `make doctor` output (a mapped capability
    that cannot run is a blocking environment finding, unlike an absent capability).
11. **React in the CI key check.** Append `plugins/react-frontend-sdlc` to the explicit `profile-keys-check`
    list (it passes today)? Recommended default: out of scope; mention in the PR.
12. **Workflow name resolution.** `workflow('rust-backend-sdlc:rs-sdlc-…')` cannot be verified offline.
    Recommended default: keep graceful escalation with the manual command line in every nested call site.
