# Project profile schema

`.claude/rust-sdlc.yml` is the project profile of the rust-backend-sdlc plugin: the one file through which every command, agent, skill, script and workflow adapts to a concrete Rust service (its make targets, port, paths, check names and capabilities). Components read it at runtime and refer to values by dotted key, for example `make.static_analysis` or `service.port`; nothing else is rendered into the service except the governance block and the local permission file.

This page is the canonical key list of schema version 1. Every profile-key candidate in a skill's or an agent's `## Profile keys consumed` section, and in any command, must appear on this page backticked; the CI job `profile-keys-check` and `tests/component-counts.bats` fail on an undeclared key.

## Conventions

- **Location and ownership.** The profile lives at `.claude/rust-sdlc.yml` in the repository root and is committed. Only `generate-profile.sh` writes it (atomically, on the first run or with `--refresh`); `/rs-sdlc-setup` runs the generator. Hand edits are legal and survive until `--refresh` re-detects the key (see [Refresh and user-owned keys](#refresh-and-user-owned-keys)).
- **115 keys in 13 groups**, emitted in the order of the tables below. Group order: root, `project`, `rust`, `template`, `framework`, `persistence`, `architecture`, `service`, `make`, `quality`, `ci`, `review`, `capabilities`; inside a group the keys follow their table order.
- **Required (R) keys must be present; optional (O) keys may be omitted.** "null means absent; omitted means error" for every R key whose Nullable column says yes: an explicit `null` declares the value or capability absent, a missing R key is a violation. A non-nullable key may never be `null`. Every `make.*` key is R and nullable.
- **Unknown keys are violations.** A misspelled key (for example `coverage_line` under `quality`) or an unknown group fails validation (V4). A new key is a schema change: a MINOR plugin release that changes the generator, the validator, this page and the golden profile together.
- **Emission format.** The generator output is yamllint clean (`extends: default` with the template's overrides) and Prettier clean (`singleQuote: true`): block style only, never flow collections; 2-space indentation; sequence items indented two spaces under their key; no document start `---`; exactly one trailing newline; no trailing spaces; two header comment lines (`# Project profile of the rust-backend-sdlc plugin (schema_version 1).` and `# Written by generate-profile.sh; re-detect with /rs-sdlc-setup --refresh.`) and no other comments. Scalars: ints, booleans and `null` bare; enum values, `make.*` target names and `review.*` list items bare; every other string (names, paths, versions, URLs, check names, workflow stems) single-quoted through `yaml_squote` (an inner `'` is doubled).
- **Detection never runs `cargo`, `make`, `gh` or the network.** It reads files with python3 (`tomllib`, `json`, `re`) and `git` (origin URL, branches, log subjects); its only probes are `docker info` and `command -v cargo`, for `capabilities.run_in_container`. A missing source never fails generation: the key takes its fallback. An unparseable source file prints a `WARN:` line on stderr and the key falls back.
- **Refresh column.** `preserve` = an existing valid value survives `--refresh` (five user-owned keys); blank = re-detected on every `--refresh`.

| Group | Keys | Group | Keys |
| --- | --- | --- | --- |
| root | 1 | `service` | 8 |
| `project` | 4 | `make` | 55 |
| `rust` | 3 | `quality` | 12 |
| `template` | 3 | `ci` | 5 |
| `framework` | 3 | `review` | 4 |
| `persistence` | 3 | `capabilities` | 9 |
| `architecture` | 5 | **total** | **115** |

## Reading the key tables

- **Type**: `int`, `bool`, `string`, `enum`, `list of string` or `list of enum`. Types are YAML types: a quoted `'100'` is a string, not an int (V6).
- **R/O**: R = required, O = optional.
- **Nullable**: `yes` = `null` is legal; `no` = never `null`; a list marked "no (may be `[]`)" may be empty, one marked "no (non-empty)" may not.
- **Fallback (no source)**: the value the generator emits when the detection source is missing.
- **Allowed values / format**: enum members, a regular expression (Python `re` syntax) or bounds, checked by V7 and V8. `is_slug` is `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` (`owner/name`).
- **Detection source**: where `generate-profile.sh` reads the value; the files are listed again in [Detection sources and cited files](#detection-sources-and-cited-files).
- **Refresh**: `preserve` or blank, as in the conventions above.
- **Consumers**: the components that read the key. Commands appear by their slash names (for example `/rs-sdlc-qa`), agents and scripts by name; `skills:` lists exactly the skills whose `## Profile keys consumed` section declares the key. S1–S14 are the steps of `/rs-sdlc-new-service`, C1–C12 the steps of `/rs-sdlc-new-context`, Q1–Q15 the quality rows of `/rs-sdlc-review`, D1–D25 the rows of the degrade matrix.

## Keys by group

### Root key

One key. It is the first line after the two header comments and is the only key outside a group.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `schema_version` | int | R | no | `1` | `1` only | constant | | `validate-profile.sh`, every command's first step |

### `project`

Identity of the service checkout: Compose project name, GitHub slug, default branch and description.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `project.name` | string | R | no | basename rule | `^[a-z0-9][a-z0-9_-]*$` | basename of TARGET_DIR, lower-cased, every `[^a-z0-9_-]` → `-` (the Makefile's `PROJECT_NAME` rule) | | `/rs-sdlc-new-service`, run report; skills: `documentation-creation`, `service-scaffolding` |
| `project.repo` | string | R | yes | `null` | `is_slug` | `git remote get-url origin` when the host is `github.com` (`https://github.com/o/n[.git]`, `git@github.com:o/n[.git]`, `ssh://git@github.com/o/n[.git]`) | | `/rs-sdlc-issue`, `/rs-sdlc-finish-pr`, `/rs-sdlc-new-service` S14; scripts resolve the slug live with `resolve_repo_slug`; skills: `service-scaffolding` |
| `project.default_branch` | string | R | no | `'main'` | `^[A-Za-z0-9._/-]+$` | `default_branch` (origin/HEAD symbolic ref → `main` → `master` → `main`) | | `ci.base_ref`, orchestrator branch creation, setup branch warning; skills: `bmad-autonomous-planning` |
| `project.description` | string | O | yes | `null` | ≤ 200 characters, single line | `[workspace.package].description` of `Cargo.toml` | | `/rs-sdlc-issue`, `/rs-sdlc-plan` prompts |

### `rust`

Toolchain facts read from `rust-toolchain.toml` and the `[workspace.package]` table of `Cargo.toml`.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `rust.toolchain` | string | R | yes | `null` | `^[0-9A-Za-z._-]+$` | `rust-toolchain.toml` `[toolchain].channel` | | `rust-implementer` |
| `rust.edition` | string | R | yes | `null` | `^20[0-9]{2}$` | `[workspace.package].edition` | | `rust-implementer` |
| `rust.msrv` | string | O | yes | `null` | `^[0-9]+\.[0-9]+(\.[0-9]+)?$` | `[workspace.package].rust-version` | | informational; `validate-profile.sh` checks its format |

### `template`

Template-sync identity: which sync workflow flavour is kept and which template repository it pulls from.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `template.repository` | string | O | yes | `null` | `is_slug` | `TEMPLATE_REPOSITORY:` value in `.github/workflows/template-sync-app.yml`, else in `template-sync-pat.yml` | | `/rs-sdlc-new-service` (`--in-place` identity); skills: `service-scaffolding` |
| `template.sync_flavour` | enum | R | no | `none` | `app` `pat` `both` `none` | which of `template-sync-app.yml`, `template-sync-pat.yml` exist | | `/rs-sdlc-new-service`; skills: `service-scaffolding` |
| `template.source_commit` | string | O | yes | `null` | `^[0-9a-f]{7,40}$` | first `git log --format=%s` subject matching `^chore\(#[0-9]+\): import template [^ ]+ at ([0-9a-f]{7,40})$` | | informational; `validate-profile.sh` checks its format |

### `framework`

Interface frameworks, detected from `[workspace.dependencies]` of `Cargo.toml`.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `framework.http` | enum | R | yes | `null` | `axum` | key `axum` in `[workspace.dependencies]` | | `qa-manual-tester`; skills: `api-resource-development`, `rust-error-handling` |
| `framework.openapi` | bool | R | no | `false` | — | key `utoipa` in `[workspace.dependencies]` | | `/rs-sdlc-qa`, review Q12–Q14; skills: `api-resource-development`, `api-contract-development` |
| `framework.graphql` | bool | R | no | `false` | — | key `async-graphql` in `[workspace.dependencies]` | | `/rs-sdlc-qa`; skills: `api-resource-development` (GraphQL section skip), `api-contract-development`, `rust-error-handling` (GraphQL error section skip) |

### `persistence`

Database engine, migration directory and offline query metadata.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `persistence.engine` | enum | R | yes | `null` | `postgresql` | key `sqlx` in `[workspace.dependencies]` whose `features` contain `postgres` | | `/rs-sdlc-qa` pre-probe migrate, review Q11; skills: `api-resource-development`, `database-migrations` (skipped when null), `query-performance-analysis` (skipped when null) |
| `persistence.migrations_dir` | string | R | yes | `null` | relative path | `migrations/` is a directory → `'migrations'` | | new-context C8; skills: `database-migrations` |
| `persistence.offline_metadata` | bool | R | no | `false` | — | `.sqlx/` is a directory | | skills: `database-migrations`, `query-performance-analysis` |

### `architecture`

Crate layout and the layer list of `architecture.toml`. Bounded-context names are always validated against the live tree; `architecture.bounded_contexts` is informational.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `architecture.crates_root` | string | R | yes | `null` | relative path | `crates/` is a directory → `'crates'` | | `rust-implementer`; skills: `architecture-boundary-fixer`, `architecture-model-sync`, `code-organization`, `bounded-context-scaffolding` |
| `architecture.composition_root` | string | R | yes | `null` | relative path | `crates/service/Cargo.toml` exists → `'crates/service'` | | new-context C9; skills: `api-resource-development`, `clean-architecture-llm`, `code-organization`, `configuration-management` |
| `architecture.layers` | list of string | R | no (may be `[]`) | `[]` | `^[a-z][a-z0-9-]*$` items | `[[layer]].name` of `architecture.toml`, file order | | skills: `architecture-boundary-fixer`, `cache-management`, `clean-architecture-llm`, `implementing-ddd-architecture`, `dependency-policy` |
| `architecture.bounded_contexts` | list of string | R | no (may be `[]`) | `[]` | `^[a-z0-9-]+/[a-z0-9-]+$` items | `[workspace].members` entries `crates/<g>/<c>/{domain,application,infrastructure}` with `<g>` ≠ `shared`, de-duplicated, member order (includes `internal/health-check`) | | informational: `/rs-sdlc-plan` story-1 rule; never read by `validate_context_name`; skills: `architecture-model-sync`, `bmad-autonomous-planning`, `code-organization`, `implementing-ddd-architecture`, `bounded-context-scaffolding` |
| `architecture.shared_crates` | list of string | R | no (may be `[]`) | `[]` | relative paths | `[workspace].members` entries under `crates/shared/`, member order | | skills: `code-organization`, `implementing-ddd-architecture` |

### `service`

Runtime address and the HTTP paths that QA probes and the security lanes use.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `service.port` | int | R | no | `8081` | 1–65535 | `.env`, first line matching `^APP_PORT=([0-9]+)$` (`.env.local` is never read) | | `/rs-sdlc-qa`, `service.base_url` derivation, `security-auditor`; skills: `configuration-management` |
| `service.base_url` | string | R | no | `'http://localhost:<port>'` | `^http://(localhost\|127\.0\.0\.1):[0-9]+$` | derived from `service.port` | | `http_probe` (URL base for `qa-manual-tester` and `security-auditor`), schemathesis lane; skills: `security-audit` |
| `service.liveness_path` | string | R | no | `'/ping'` | starts with `/` | constant (template route) | | `/rs-sdlc-qa`; skills: `observability-instrumentation` |
| `service.readiness_path` | string | R | no | `'/api/health'` | starts with `/` | constant | | `/rs-sdlc-qa`; skills: `observability-instrumentation` |
| `service.graphql_path` | string | R | yes | `'/api/graphql'` when `framework.graphql`, else `null` | starts with `/` | derived | | `/rs-sdlc-qa` |
| `service.docs_path` | string | R | yes | `'/api/docs'` when `framework.openapi`, else `null` | starts with `/` | derived | | `/rs-sdlc-qa` |
| `service.openapi_snapshot` | string | R | yes | `null` | relative path | `.github/openapi-spec/spec.yaml` exists | | `/rs-sdlc-qa` probe set; skills: `api-contract-development` |
| `service.graphql_snapshot` | string | R | yes | `null` | relative path | `.github/graphql-spec/spec` exists | | `/rs-sdlc-qa`; skills: `api-contract-development` |

### `make` (55 keys)

Key = template target with `-` replaced by `_`; value = the target name when a rule matching `^<target>:.*##[[:space:]]` exists in `Makefile` or `make/*.mk` (including `make/service.mk`), else `null`. No other value is legal (V12), so a branch commit cannot point a gate key at a weaker target such as `make.complexity: format`. Null means absent; omitted means error: every key is present, and `null` marks a capability the repository does not have. The four `SUBST` keys are `null` unless the service defines a target with that exact name, and `null` routes to the plugin's bundled script. The template's `logs` target has no key: it follows the logs forever and no component invokes it.

Shared columns: every `make.*` key is a `string`, R, nullable, falls back to `null`, and is re-detected on `--refresh`. In the Detection source column, "rule `<target>`" means a line matching `^<target>:.*##[[:space:]]` in `Makefile` or `make/*.mk`. **Gate** = template gate id; **Class** = `STAGE` (aggregate stage), `GATE`, `LIFE` (lifecycle), `DEV` (database-free, parallel-safe), `DB` (needs the compose database, serialized), `SCAF` (scaffolding or code generation), `READ` (foreground read), `SUBST` (plugin-substitutable); **Dk** = needs Docker in host mode (`H` host target, `D` database through `ensure-deps`; in container mode every target needs the `app` container); **FG** = foreground allowlist (every other target runs in the background).

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Gate | Class | Dk | FG | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `make.ci` | string | R | yes | `null` | `null` or `ci` | rule `ci` | | — | STAGE | H | | never invoked (FR-1); the stages run one by one instead |
| `make.ci_list` | string | R | yes | `null` | `null` or `ci-list` | rule `ci-list` | | — | READ | | yes | setup/review read the gate order; skills: `quality-standards`, `verification-workflow` |
| `make.ci_preflight` | string | R | yes | `null` | `null` or `ci-preflight` | rule `ci-preflight` | | G25,G31,G9,G23,G24,G27 | STAGE | H | | new-context C12; skills: `verification-workflow`, `bounded-context-scaffolding` |
| `make.ci_static_analysis` | string | R | yes | `null` | `null` or `ci-static-analysis` | rule `ci-static-analysis` | | G1,G5,G29,G2,G3,G4,G7,G8,G6,G26 | STAGE | | | new-context C12; skills: `verification-workflow`, `bounded-context-scaffolding` |
| `make.ci_tests` | string | R | yes | `null` | `null` or `ci-tests` | rule `ci-tests` | | G30,G11–G14 | STAGE | D | | new-context C12; skills: `verification-workflow`, `bounded-context-scaffolding` |
| `make.ci_contracts` | string | R | yes | `null` | `null` or `ci-contracts` | rule `ci-contracts` | | G17–G20 | STAGE | H | | new-context C12; skills: `verification-workflow`, `bounded-context-scaffolding` |
| `make.ci_mutation` | string | R | yes | `null` | `null` or `ci-mutation` | rule `ci-mutation` | | G15 | STAGE | D | | new-context C12; skills: `verification-workflow`, `bounded-context-scaffolding` |
| `make.ci_delivery` | string | R | yes | `null` | `null` or `ci-delivery` | rule `ci-delivery` | | G10,G21,G22 | STAGE | H | | new-context C12 (Docker reachable only); skills: `verification-workflow`, `bounded-context-scaffolding` |
| `make.ci_cli` | string | R | yes | `null` | `null` or `ci-cli` | rule `ci-cli` | | G16 | STAGE | H | | never run by the plugin (new-context skips it) |
| `make.doctor` | string | R | yes | `null` | `null` or `doctor` | rule `doctor` | | — | LIFE | | yes | new-service S7; `make doctor` output in D2/D25 escalations; skills: `verification-workflow`, `service-scaffolding` |
| `make.bootstrap` | string | R | yes | `null` | `null` or `bootstrap` | rule `bootstrap` | | — | LIFE | H | | new-service S8; skills: `service-scaffolding` |
| `make.install_hooks` | string | R | yes | `null` | `null` or `install-hooks` | rule `install-hooks` | | — | LIFE | | yes | setup step 7, implement step 1; skills: `verification-workflow` |
| `make.bmalph_setup` | string | R | yes | `null` | `null` or `bmalph-setup` | rule `bmalph-setup` | | — | LIFE | | | setup step 2 |
| `make.start` | string | R | yes | `null` | `null` or `start` | rule `start` | | — | LIFE | H | | QA boot, container precondition (FR-1, D25); skills: `verification-workflow` |
| `make.format` | string | R | yes | `null` | `null` or `format` | rule `format` | | — | DEV | | | `rust-implementer`, workflow publish step; skills: `bmad-autonomous-planning` |
| `make.format_check` | string | R | yes | `null` | `null` or `format-check` | rule `format-check` | | G1 | GATE | | | review Q1 |
| `make.lint_code` | string | R | yes | `null` | `null` or `lint-code` | rule `lint-code` | | — | DEV | | | parallel implementers; skills: `bmad-autonomous-planning` |
| `make.static_analysis` | string | R | yes | `null` | `null` or `static-analysis` | rule `static-analysis` | | G2 | GATE | | | review Q2; skills: `quality-standards`, `rust-error-handling`, `async-runtime-safety` |
| `make.complexity` | string | R | yes | `null` | `null` or `complexity` | rule `complexity` | | G3 | GATE/DEV | | | review Q3; parallel implementers; skills: `bmad-autonomous-planning`, `complexity-management`, `quality-standards` |
| `make.architecture` | string | R | yes | `null` | `null` or `architecture` | rule `architecture` | | G4 | GATE/DEV | | | review Q4; parallel implementers; skills: `architecture-boundary-fixer`, `bmad-autonomous-planning`, `clean-architecture-llm`, `quality-standards` |
| `make.check_crate_isolation` | string | R | yes | `null` | `null` or `check-crate-isolation` | rule `check-crate-isolation` | | G29 | GATE | | | review Q5; skills: `architecture-boundary-fixer`, `quality-standards` |
| `make.validate_architecture_model` | string | R | yes | `null` | `null` or `validate-architecture-model` | rule `validate-architecture-model` | | G27 | GATE | H | | review Q6; C2; skills: `architecture-model-sync`, `bounded-context-scaffolding` |
| `make.check_security` | string | R | yes | `null` | `null` or `check-security` | rule `check-security` | | G7 | GATE | | | review Q7; `security-auditor` static lane; null → built-in static lane (D1); skills: `quality-standards`, `security-audit`, `dependency-policy` |
| `make.unused_dependencies` | string | R | yes | `null` | `null` or `unused-dependencies` | rule `unused-dependencies` | | G8 | GATE | | | review Q8; C3; skills: `architecture-boundary-fixer`, `quality-standards`, `dependency-policy` |
| `make.docs_check` | string | R | yes | `null` | `null` or `docs-check` | rule `docs-check` | | G26 | GATE | | | review Q15; setup step 8; C11; skills: `documentation-creation`, `documentation-sync`, `configuration-management` |
| `make.validate_invariants` | string | R | yes | `null` | `null` or `validate-invariants` | rule `validate-invariants` | | G31 | GATE | | | skills: `documentation-sync` |
| `make.validate_configuration` | string | R | yes | `null` | `null` or `validate-configuration` | rule `validate-configuration` | | G25 | GATE | | | new-context closing step; `security-auditor` evidence; skills: `bounded-context-scaffolding` |
| `make.secrets_scan` | string | R | yes | `null` | `null` or `secrets-scan` | rule `secrets-scan` | | G9 | GATE | H | | `security-auditor` lane; skills: `security-audit` |
| `make.unit_tests` | string | R | yes | `null` | `null` or `unit-tests` | rule `unit-tests` | | — | DEV | | | parallel implementers (pre-push hook runs it too); skills: `bmad-autonomous-planning`, `cache-management`, `observability-instrumentation`, `testing-workflow`, `async-runtime-safety` |
| `make.integration_tests` | string | R | yes | `null` | `null` or `integration-tests` | rule `integration-tests` | | — | DB | D | | serialized verify step; skills: `bmad-autonomous-planning`, `query-performance-analysis`, `testing-workflow`, `async-runtime-safety` |
| `make.tests_with_coverage` | string | R | yes | `null` | `null` or `tests-with-coverage` | rule `tests-with-coverage` | | G11,G12,G14 | GATE/DB | D | | review Q9; implement post-loop; skills: `api-resource-development`, `bmad-autonomous-planning`, `cache-management`, `quality-standards`, `testing-workflow` |
| `make.e2e_tests` | string | R | yes | `null` | `null` or `e2e-tests` | rule `e2e-tests` | | G13 | GATE/DB | D | | serialized verify step; C9, C10; skills: `api-resource-development`, `bmad-autonomous-planning`, `testing-workflow` |
| `make.mutation_tests_diff` | string | R | yes | `null` | `null` or `mutation-tests-diff` | rule `mutation-tests-diff` | | G15 | GATE/DB | D | | review Q10 (PA-13 run rule); skills: `quality-standards`, `testing-workflow` |
| `make.setup_test_db` | string | R | yes | `null` | `null` or `setup-test-db` | rule `setup-test-db` | | — | DB | D | | before the raw nextest call; serialized verify; skills: `bmad-autonomous-planning`, `database-migrations`, `testing-workflow` |
| `make.create_migration` | string | R | yes | `null` | `null` or `create-migration` | rule `create-migration` | | — | SCAF | | | C8 (`make create-migration name=<snake_case>`); skills: `database-migrations` |
| `make.migrate` | string | R | yes | `null` | `null` or `migrate` | rule `migrate` | | — | DB | D | | QA pre-probe; C8; skills: `database-migrations` |
| `make.migrate_rollback` | string | R | yes | `null` | `null` or `migrate-rollback` | rule `migrate-rollback` | | — | DB | D | | C8 once; template `ask` rule → headless `not run (ask rule)` (D13); skills: `database-migrations` |
| `make.sqlx_prepare` | string | R | yes | `null` | `null` or `sqlx-prepare` | rule `sqlx-prepare` | | — | SCAF/DB | D | | serialized verify; C8; skills: `bmad-autonomous-planning`, `database-migrations`, `query-performance-analysis` |
| `make.validate_sqlx_metadata` | string | R | yes | `null` | `null` or `validate-sqlx-metadata` | rule `validate-sqlx-metadata` | | G30 | GATE/DB | D | | review Q11; skills: `database-migrations` |
| `make.generate_openapi_spec` | string | R | yes | `null` | `null` or `generate-openapi-spec` | rule `generate-openapi-spec` | | — | SCAF | | | new-service S10; C10; implementer co-change; skills: `api-resource-development`, `api-contract-development`, `service-scaffolding` |
| `make.generate_graphql_spec` | string | R | yes | `null` | `null` or `generate-graphql-spec` | rule `generate-graphql-spec` | | — | SCAF | | | C10; implementer co-change; skills: `api-resource-development`, `api-contract-development` |
| `make.validate_contract_snapshots` | string | R | yes | `null` | `null` or `validate-contract-snapshots` | rule `validate-contract-snapshots` | | G17 | GATE | | | review Q12; skills: `api-contract-development` |
| `make.validate_openapi_spec` | string | R | yes | `null` | `null` or `validate-openapi-spec` | rule `validate-openapi-spec` | | G18 | GATE | H | | review Q13; skills: `api-contract-development`, `quality-standards` |
| `make.openapi_diff` | string | R | yes | `null` | `null` or `openapi-diff` | rule `openapi-diff` | | G19 | GATE | H | | review Q14; skills: `api-contract-development`, `quality-standards` |
| `make.graphql_diff` | string | R | yes | `null` | `null` or `graphql-diff` | rule `graphql-diff` | | G20 | GATE | H | | review Q14; skills: `api-contract-development`, `quality-standards` |
| `make.schemathesis_validate` | string | R | yes | `null` | `null` or `schemathesis-validate` | rule `schemathesis-validate` | | G21 | GATE | H | | QA optional lane (`capabilities.dynamic_security_testing`) |
| `make.image_scan` | string | R | yes | `null` | `null` or `image-scan` | rule `image-scan` | | G10 | GATE | H | | `security-auditor` image lane; skills: `quality-standards`, `security-audit` |
| `make.smoke_load_tests` | string | R | yes | `null` | `null` or `smoke-load-tests` | rule `smoke-load-tests` | | G22 | GATE | H | | review records `not run (deferred to PR CI)`; skills: `load-testing`, `quality-standards` |
| `make.load_tests` | string | R | yes | `null` | `null` or `load-tests` | rule `load-tests` | | — | LIFE | H | | guidance only; never run by a command; skills: `load-testing` |
| `make.new_context` | string | R | yes | `null` | `null` or `new-context` | rule `new-context` | | — | SCAF | | | new-context C1; skills: `bounded-context-scaffolding` |
| `make.check_commit_message` | string | R | yes | `null` | `null` or `check-commit-message` | rule `check-commit-message` | | G28 | READ | | yes | FR-2 pre-validation; skills: `verification-workflow` |
| `make.ai_review_loop` | string | R | yes | `null` | `null` or `ai-review-loop` | rule `ai-review-loop` (service-defined; the template has none) | | — | SUBST | | | null → `scripts/ai-review-loop.sh`; site (ADR-4): `pr-comment-resolver` D7 comment source |
| `make.pr_comments` | string | R | yes | `null` | `null` or `pr-comments` | rule `pr-comments` (service-defined; the template has none) | | — | SUBST | | | null → `scripts/get-pr-comments.sh`; site (ADR-4): `pr-comment-resolver` thread read (never inside `pr-state.sh`) |
| `make.fr_nfr_gate` | string | R | yes | `null` | `null` or `fr-nfr-gate` | rule `fr-nfr-gate` (service-defined; the template has none) | | — | SUBST | | | null → `scripts/fr-nfr-gate.sh`; sites (ADR-4): review gate run by `fr-nfr-reviewer`, finish-pr `GATE`; skills: `bmad-fr-nfr-review-gate` |
| `make.post_review_findings` | string | R | yes | `null` | `null` or `post-review-findings` | rule `post-review-findings` (service-defined; the template has none) | | — | SUBST | | | null → `scripts/post-review-findings.sh`; sites (ADR-4): per-lens posts in review and finish-pr, finish-pr conclusion; skills: `code-review` |

### `quality` (12 keys)

Twelve tighten-only bars, all R, `int`, not nullable. A floor key's only legal value is exactly `100` and a ceiling key's exactly `0`, because the template's gates already sit at those extremes; the generator always emits these defaults. Their protected sources, gate targets and measurement are in [Quality bars](#quality-bars).

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `quality.coverage_lines` | int | R | no | `100` | exactly `100` (floor) | constant `100`; a looser `--fail-under-lines` in `COVERAGE_GATE_CMD` of `make/gates.mk` only warns | | review Q9, implement post-loop; skills: `quality-standards`, `testing-workflow` |
| `quality.coverage_functions` | int | R | no | `100` | exactly `100` (floor) | constant `100`; a looser `--fail-under-functions` in `COVERAGE_GATE_CMD` of `make/gates.mk` only warns | | review Q9; skills: `quality-standards`, `testing-workflow` |
| `quality.max_surviving_mutants` | int | R | no | `0` | exactly `0` (ceiling) | constant `0` | | review Q10; skills: `quality-standards`, `testing-workflow` |
| `quality.max_clippy_findings` | int | R | no | `0` | exactly `0` (ceiling) | constant `0` | | review Q2; skills: `code-review`, `quality-standards` |
| `quality.max_complexity_violations` | int | R | no | `0` | exactly `0` (ceiling) | constant `0`; a looser threshold among the four of `clippy.toml` only warns | | review Q3 (limits quoted from `clippy.toml` in the row); skills: `complexity-management`, `quality-standards` |
| `quality.max_architecture_violations` | int | R | no | `0` | exactly `0` (ceiling) | constant `0` | | review Q4, Q5; skills: `architecture-boundary-fixer`, `quality-standards` |
| `quality.max_unused_dependencies` | int | R | no | `0` | exactly `0` (ceiling) | constant `0` | | review Q8; skills: `quality-standards`, `dependency-policy` |
| `quality.max_dependency_policy_findings` | int | R | no | `0` | exactly `0` (ceiling) | constant `0` | | review Q7, `security-auditor`; skills: `quality-standards`, `security-audit`, `dependency-policy` |
| `quality.max_spectral_findings` | int | R | no | `0` | exactly `0` (ceiling) | constant `0`; a looser `SPECTRAL_FLAGS` only warns | | review Q13; skills: `api-contract-development`, `quality-standards` |
| `quality.max_unapproved_breaking_changes` | int | R | no | `0` | exactly `0` (ceiling) | constant `0`; a looser `OASDIFF_FLAGS` only warns | | review Q14; skills: `api-contract-development`, `quality-standards` |
| `quality.max_image_vulnerabilities_high_critical` | int | R | no | `0` | exactly `0` (ceiling) | constant `0`; looser `TRIVY_FLAGS` severities only warn | | `security-auditor` image lane; finish-pr via check `Production-image scan`; skills: `quality-standards`, `security-audit` |
| `quality.max_smoke_budget_breaches` | int | R | no | `0` | exactly `0` (ceiling) | constant `0` | | finish-pr via check `Smoke load tests`; review records `not run (deferred to PR CI)`; skills: `load-testing`, `quality-standards` |

### `ci`

CI provider, workflow stems, required and human-gated check names, and the diff base.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ci.provider` | enum | R | yes | `null` | `github-actions` | at least one `.github/workflows/*.yml` or `*.yaml` | | `/rs-sdlc-finish-pr` (D8), `ci-fixer` |
| `ci.workflows` | list of string | R | no (may be `[]`) | `[]` | file stems | `.github/workflows/*.y{a,}ml` stems, sorted with `LC_ALL=C` | | `ci-fixer` |
| `ci.required_checks` | list of string | R | no (may be `[]`) | `[]` | GitHub check names | "Check name" cell of every row whose "Required" cell is `yes` in the job tables under "Required status checks" of `docs/repository-settings.md`, then `docs/repository-settings-service.md`; union, document order, de-duplicated | | `pr-state.sh` default, `/rs-sdlc-finish-pr`, `ci-fixer` |
| `ci.human_gated` | list of string | R | no (may be `[]`) | `[]` | ⊆ `ci.required_checks` | "Labels to create" table: job ids from "without it the job `<j>` fails" and "without it the jobs `<a>` and `<b>` fail", mapped to their "Check name" through the job tables of both documents; an unmapped job id is dropped with `WARN:` on stderr | | `pr-state.sh --human-gated-checks` default, `/rs-sdlc-finish-pr`, `ci-fixer` |
| `ci.base_ref` | string | R | no | `'origin/<default_branch>'` | `^[A-Za-z0-9._/-]+$` | derived from `project.default_branch` | | `/rs-sdlc-review` (diff, Q10, Q14 `base_ref=`), `ai-review-loop.sh`, `fr-nfr-gate.sh`; skills: `api-contract-development`, `bmad-fr-nfr-review-gate`, `code-review` |

### `review`

Pull-request reviewers and the AI review loop.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `review.coderabbit` | bool | R | no | `false` | — | `.coderabbit.yaml` exists | | `/rs-sdlc-finish-pr` (D7), `pr-comment-resolver` |
| `review.reviewers` | list of enum | R | no (may be `[]`) | `[coderabbit]` when `.coderabbit.yaml` exists, else `[]` | items ∈ `coderabbit` `cubic` `qodo` `qlty` `sonarcloud`, no duplicates | detection | preserve | `pr-state.sh`, `request-ai-reviews.sh`, `/rs-sdlc-finish-pr` |
| `review.ai_review_agents` | list of string | R | no (non-empty) | `[claude]` | items `^[a-z][a-z0-9-]*$`; only `claude` runs, others warn and skip | constant | preserve | `ai-review-loop.sh` |
| `review.request_changes_blocking` | bool | R | no | `false` | — | `reviews.request_changes_workflow: true` in `.coderabbit.yaml` (YAML read) | | `pr-comment-resolver`, `/rs-sdlc-finish-pr` |

### `capabilities`

Boolean switches. A false capability routes every dependent step to its documented skip or degrade path.

| Key | Type | R/O | Nullable | Fallback (no source) | Allowed values / format | Detection source | Refresh | Consumers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `capabilities.template_derived` | bool | R | no | `false` | — | all of `rust-toolchain.toml`, `architecture.toml`, `protected-config.toml`, `xtask/Cargo.toml`, `make/gates.mk`, `crates/service/Cargo.toml`, `workspace.dsl` exist and the Makefile's `CI_PREFLIGHT_TARGETS` starts with `validate-configuration` | | `setup-preflight.sh`, commands (D20) |
| `capabilities.run_in_container` | bool | R | no | `false` | — | `--run-in-container true\|false` > existing profile value > (`docker info` exits 0 and `cargo` is not on `PATH`) | preserve (flag wins) | every command that runs `make`, `git commit`, `git push` (FR-1); skills: `verification-workflow`, `service-scaffolding` |
| `capabilities.structurizr` | bool | R | no | `false` | — | `workspace.dsl` exists and `make.validate_architecture_model` is mapped | | review Q6; skills: `architecture-model-sync` (skip path) |
| `capabilities.load_testing` | bool | R | no | `false` | — | `tests/Load/` is a directory and `make.smoke_load_tests` is mapped | | skills: `load-testing` (skip path), `testing-workflow` |
| `capabilities.mutation_testing` | bool | R | no | `false` | — | `make.mutation_tests_diff` is mapped | | review Q10; skills: `testing-workflow` (mutation section skip) |
| `capabilities.dynamic_security_testing` | bool | R | no | `false` | — | never detected (opt-in by hand) | preserve | `/rs-sdlc-qa` schemathesis lane, `security-auditor` dynamic probes; skills: `security-audit` (dynamic probing skip) |
| `capabilities.publish_pr_comments` | bool | R | no | `true` when `ci.provider` and `project.repo` are non-null, else `false` | — | derived | preserve | `post-review-findings.sh`; skills: `bmad-fr-nfr-review-gate` (publishing skip), `code-review` (publishing skip) |
| `capabilities.protected_config` | bool | R | no | `false` | — | `protected-config.toml` exists | | agents' protected-change rule; skills: `architecture-boundary-fixer`, `dependency-policy` |
| `capabilities.template_sync` | bool | R | no | `false` | — | `template-sync-app.yml` or `template-sync-pat.yml` exists | | `/rs-sdlc-setup` (J6 hint) |

## Quality bars

Rule for every row: the review row is PASS when the gate target exits 0 **and** the measured value is within the bound. Measured values are evidence in the targets-run list; where the output cannot be parsed the measured value is reported as `≥ 1 (exit <n>)` and the row fails.

**Tighten-only rule.** Floors may not go below and ceilings may not go above the shipped defaults. Because the template's gates already sit at the extremes, a floor key's legal values are exactly 100 and a ceiling key's exactly 0, so every legal value equals the shipped default; `validate-profile.sh` rejects anything else (V11). Complexity limits (cognitive complexity 8, 50 lines, 5 arguments, nesting 5) are not profile keys: `clippy.toml` is their single source, quoted at review time, and `quality.max_complexity_violations` is the profile's handle on them.

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

**Looser-gate `WARN`.** `generate-profile.sh` always emits the defaults. When the repository's own gate is looser than the template value it keeps the default and prints on stderr

```text
[rust-sdlc][WARN] <file> <setting> is looser than the template value <v>; the profile keeps <default>
```

for: the `COVERAGE_GATE_CMD` floors in `make/gates.mk`, the four `clippy.toml` thresholds (`cognitive-complexity-threshold`, `too-many-lines-threshold`, `too-many-arguments-threshold`, `excessive-nesting-threshold`), `SPECTRAL_FLAGS`, `OASDIFF_FLAGS` and the `TRIVY_FLAGS` severities. The generator never lowers a bar; a relaxed repository gate is a protected-configuration change the plugin reports and never makes.

## Refresh and user-owned keys

```text
generate-profile.sh [--refresh] [--stdout] [--run-in-container true|false] [TARGET_DIR]
```

Five keys are user-owned and keep a valid existing value on `--refresh`; every other key is re-detected:

| Key | Preserve rule |
| --- | --- |
| `capabilities.run_in_container` | kept unless `--run-in-container true\|false` is passed (the flag wins) |
| `capabilities.dynamic_security_testing` | kept; never detected, opt-in by hand |
| `capabilities.publish_pr_comments` | kept |
| `review.reviewers` | kept |
| `review.ai_review_agents` | kept |

- First run (no profile): the generator writes the file and prints `WROTE: .claude/rust-sdlc.yml`.
- Profile present, no `--refresh`: the generator compares the file with exactly what `--refresh` would write (detection plus the preserve rules) and prints `UNCHANGED: .claude/rust-sdlc.yml` or `DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)` followed by a unified diff; the file is kept. A legitimate hand flip of a preserve key therefore never produces a `DIFF:`.
- Profile present, no `--refresh`, explicit `--run-in-container true|false`: only `capabilities.run_in_container` is rewritten (atomically) and the generator prints `UPDATED: .claude/rust-sdlc.yml (capabilities.run_in_container=<v>)`, or `UNCHANGED:` when the file already holds that value; any other difference is still reported as `DIFF:` and kept.
- `--refresh`: the generator writes the re-detected profile under the preserve rules and prints `WROTE:` or `UNCHANGED:`. `--stdout` prints the YAML and writes nothing.

## Detection sources and cited files

Every file `generate-profile.sh` reads, every protected file a quality bar is derived from, and the template file names the skills cite. Paths are relative to the repository root.

| Source | Read with | Role | Keys and use |
| --- | --- | --- | --- |
| `git` | `git remote get-url origin`, the `origin/HEAD` symbolic ref and local branches, `git log --format=%s` | detection | `project.repo` (github.com origins only), `project.default_branch` and through it `ci.base_ref`, `template.source_commit` |
| checkout directory | basename of TARGET_DIR | detection | `project.name` (lower-cased, every `[^a-z0-9_-]` replaced by `-`) |
| `Cargo.toml` | python3 `tomllib` | detection; bar source | `[workspace.package]`: `project.description`, `rust.edition`, `rust.msrv`; `[workspace.dependencies]`: `framework.http` (`axum`), `framework.openapi` (`utoipa`), `framework.graphql` (`async-graphql`), `persistence.engine` (`sqlx` with the `postgres` feature); `[workspace].members`: `architecture.bounded_contexts`, `architecture.shared_crates`; `[workspace.lints]` backs `quality.max_clippy_findings` |
| `rust-toolchain.toml` | python3 `tomllib` | detection; marker | `rust.toolchain` (`[toolchain].channel`); marker of `capabilities.template_derived` |
| `architecture.toml` | python3 `tomllib` | detection; marker; bar source | `architecture.layers` (`[[layer]].name`, file order); marker of `capabilities.template_derived`; with `ARCH_CMD` the source of `quality.max_architecture_violations` |
| `protected-config.toml` | existence | detection; marker | `capabilities.protected_config`; marker of `capabilities.template_derived`. The protected-file list itself is read at runtime with `cargo xtask config-guard --list`, never copied into the profile |
| `xtask/Cargo.toml` | existence | marker | `capabilities.template_derived` |
| `crates/` | directory test | detection | `architecture.crates_root` |
| `crates/service/Cargo.toml` | existence | detection; marker | `architecture.composition_root`; marker of `capabilities.template_derived` |
| `workspace.dsl` | existence | detection; marker | `capabilities.structurizr` (with `make.validate_architecture_model` mapped); marker of `capabilities.template_derived` |
| `Makefile` | python3 `re` | detection | every `make.*` key (rules with a `##` help comment); `CI_PREFLIGHT_TARGETS` starting with `validate-configuration` for `capabilities.template_derived` |
| `make/gates.mk` | python3 `re` | detection; marker; bar source | `make.*` rules (as one of `make/*.mk`); marker of `capabilities.template_derived`; `COVERAGE_GATE_CMD`, `MUTANTS_CMD`, `LINT_PROD_CMD`, `LINT_ALL_CMD`, `LINT_RUSTDOC_CMD`, `COMPLEXITY_CMD`, `ARCH_CMD`, `HACK_CMD`, `SHEAR_CMD`, `DENY_CMD`, `SPECTRAL_FLAGS`, `OASDIFF_FLAGS`, `TRIVY_FLAGS` back the `quality.*` bars; looser coverage floors and flags only warn |
| `make/*.mk` | python3 `re` | detection | `make.*` rules, including the service-owned `make/service.mk` |
| `clippy.toml` | python3 `tomllib` | bar source; cited | the four complexity thresholds behind `quality.max_complexity_violations` (looser → `WARN`); quoted at review time, never copied into the profile |
| `deny.toml` | cited, not parsed | bar source | with `DENY_CMD` the source of `quality.max_dependency_policy_findings` |
| `.spectral.yaml` | cited, not parsed | bar source | with `SPECTRAL_FLAGS` the source of `quality.max_spectral_findings` |
| `.cargo/mutants.toml` | cited, not parsed | bar source | with `MUTANTS_CMD` the source of `quality.max_surviving_mutants` |
| `scripts/graphql-diff.sh` (template) | cited, not parsed | bar source | with `OASDIFF_FLAGS` the source of `quality.max_unapproved_breaking_changes` |
| `tests/Load/config.json.dist` | cited, not parsed | bar source | `/endpoints/health/smoke/threshold` (with `thresholdsBuilder.js`) behind `quality.max_smoke_budget_breaches` |
| `tests/Load/` | directory test | detection | `capabilities.load_testing` (with `make.smoke_load_tests` mapped) |
| `migrations/` | directory test | detection | `persistence.migrations_dir` |
| `.sqlx/` | directory test | detection | `persistence.offline_metadata` |
| `.env` | python3 `re`, first line matching `^APP_PORT=([0-9]+)$` | detection | `service.port` and through it `service.base_url`; `.env.local` is never read |
| `.github/workflows/*.yml`, `.github/workflows/*.yaml` | directory listing | detection | `ci.provider`, `ci.workflows` (stems sorted with `LC_ALL=C`) |
| `.github/workflows/template-sync-app.yml`, `.github/workflows/template-sync-pat.yml` | existence; `TEMPLATE_REPOSITORY:` line | detection | `template.sync_flavour`, `template.repository`, `capabilities.template_sync` |
| `.github/openapi-spec/spec.yaml` | existence | detection | `service.openapi_snapshot` |
| `.github/graphql-spec/spec` | existence | detection | `service.graphql_snapshot` |
| `docs/repository-settings.md` | python3 `re` over the Markdown tables | detection | `ci.required_checks` ("Required status checks" job tables), `ci.human_gated` ("Labels to create" table) |
| `docs/repository-settings-service.md` | python3 `re` over the Markdown tables | detection | the service-owned checks, unioned after `docs/repository-settings.md` into `ci.required_checks` and `ci.human_gated`; absent → nothing added |
| `.coderabbit.yaml` | existence; YAML read | detection | `review.coderabbit`, `review.reviewers`, `review.request_changes_blocking` (`reviews.request_changes_workflow`) |
| `docker info`, `command -v cargo` | exit status only | detection | `capabilities.run_in_container` when neither the flag nor an existing value decides |
| `.claude/rust-sdlc.yml` | YAML read | preserve | the five user-owned keys on `--refresh` |
| `persistence.rs` | cited, never read by detection | cited file | the shared infrastructure crate's lazy pool and `MIGRATOR` (`crates/shared/infrastructure/src/persistence.rs`) and each context's repository adapter (`crates/<group>/<context>/infrastructure/src/persistence.rs`), named by the persistence skills |

`architecture.toml` and `persistence.rs` are template file names that look like dotted profile keys to the plugin lint (L25 matches the `architecture` and `persistence` prefixes and does not treat `toml` or `rs` as file extensions). Backticking them here declares them, so a skill that names either file passes the lint; a backticked token whose last segment is a file extension (`toml`, `dsl`, `md`, `yml`, `yaml`, `json`, `rs`, `sh`, `mk`) is never a profile-key candidate, so `architecture.toml`, `persistence.rs`, `workspace.dsl`, `clippy.toml` and `tests.rs` are not keys.

## Validation

```text
validate-profile.sh [PROFILE_FILE]
```

`PROFILE_FILE` defaults to `$PWD/.claude/rust-sdlc.yml`. The file is converted once to JSON (mikefarah `yq` v4, or python3 with PyYAML; both give byte-identical output) and every rule runs in python3 over that JSON, so YAML types survive. The rules are checked in this order and all violations are reported; the validator writes nothing.

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
| V12 | every non-null `make.<key>` equals `<key>` with `_` replaced by `-` (the PA-2 identity mapping the generator emits; the four SUBST keys included, so a SUBST value can never name a template gate) | `VIOLATION: make.<k>: must be null or '<k with - for _>' (<value>)` |

Output ends with `VALID: <path>` (exit 0) or `INVALID: <path>: <n> violation(s)` (exit 1). Usage errors exit 2. Every command except `/rs-sdlc-setup` and `/rs-sdlc-new-service` runs the validator as its first step and halts on `INVALID:`.

## Annotated example

The generator output for the template checkout at `3e0bd3e`, with comments added. The generator emits the same keys and values without the trailing comments. The fence's opening line carries `# profile-example`; the fence is the only place on this page where the default template slug appears.

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

## For component authors

- Refer to a value only by its full dotted key in backticks (`service.port`, `make.tests_with_coverage`), never by a concrete value; concrete values appear only inside fences whose opening line carries `# profile-example`.
- List every consumed key under the first H2 `## Profile keys consumed` of a skill or agent. The list holds keys only, never file names, and the body uses no other dotted key.
- Read a `make.*` key before running its target; `null` means the capability is absent and the component takes its documented skip or degrade path. For the four `SUBST` keys, `null` routes to the bundled script.
- Read lists the template defines (gate order, protected files, required checks) at runtime through `make.ci_list`, `cargo xtask config-guard --list` and `docs/repository-settings.md`; never restate them.
- A key consumed by a component but absent from this page fails `profile-keys-check` and `tests/component-counts.bats`; add a key only through the schema-change rule in [Conventions](#conventions).
