# Skill Decision Guide

This guide decides which of the plugin's 28 skills a change needs. `/rs-sdlc-review` reads it at the start of every iteration to fill its triage table, and any other stage that must pick the skills for a change follows the same protocol. It sits at the `skills/` root without frontmatter, so it is never discovered as a skill itself; the skills link to it as `../SKILL-DECISION-GUIDE.md`. The agent roster, the stage map and the escalation block live in `AI-AGENT-GUIDE.md` beside it.

## Triage protocol

The gate contract is: every skill verdict recorded, no silent skips.

A verdict is decided from two sources only: the frontmatter of each `SKILL.md` (its `name` and `description`) and this guide. Skill bodies and their supporting files load only after an `EXECUTE` verdict, which keeps a review iteration to the bodies it needs: the workflow/docs-only class marks six skills.

1. **List the change.** Take the merge base the stage already computed in its branch guards (`git merge-base <ci.base_ref> HEAD`, or `HEAD` after the D24 fallback) and list every changed path with its status, renames included:

   ```bash
   git diff --name-status -M <sha> HEAD
   ```

2. **Read the frontmatter, nothing else.** Read the 28 frontmatter blocks and stop at each closing `---`:

   ```bash
   for f in "${CLAUDE_PLUGIN_ROOT}"/skills/*/SKILL.md; do awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside' "$f"; done
   ```

   For a counterpart pair (item 6), read the frontmatter of the repository's `.claude/skills/<name>/SKILL.md` first. When the repository has its own decision guide (`.claude/skills/SKILL-DECISION-GUIDE.md`), read it first as well: a skill it names for the change's intent is `EXECUTE` with its line as evidence, and it never turns a verdict into a skip. Read the profile values the skill table names from `.claude/rust-sdlc.yml`.
3. **Classify.** Put every changed path into exactly one class with the decision tree below, then check the two branch classes (new context, new service) and the evidence overlays.
4. **Decide one verdict per skill.**
   - `EXECUTE` when a class present in the change, a branch class or an overlay marks the skill and its NOT APPLICABLE condition in the skill table does not hold. The evidence is the triggering class with its paths, or the red target, completed with the skill's own verdict line once it has run.
   - `NOT APPLICABLE` otherwise, with a concrete reason: the condition of the skill table that holds, naming the classes present (`classes present: workflow/docs-only; no Rust source, manifest, migration or Dockerfile path`) or the profile value (`SKIPPED: capabilities.structurizr is false`).
   - Never open a skill body, a reference file or an example to decide a verdict.
5. **Always `EXECUTE`.** `code-review` and `quality-standards` are `EXECUTE` in every class and every iteration; no condition turns them `NOT APPLICABLE`.
6. **Count each counterpart pair once.** Eleven plugin skills share their name with a repository skill: `api-resource-development`, `api-contract-development`, `architecture-boundary-fixer`, `architecture-model-sync`, `bmad-autonomous-planning`, `complexity-management`, `documentation-sync`, `load-testing`, `quality-standards`, `testing-workflow` and `verification-workflow`. Each pair gets one row with source `repo+plugin` when `.claude/skills/<name>/SKILL.md` exists (source `plugin` when the repository lacks it). On `EXECUTE`, read the repository skill first; it and `AGENTS.md` win where they speak, and the plugin body adds the profile resolution, the evidence format and the bounded loop. The other 17 rows have source `plugin`. A repository skill without a plugin counterpart is not a row of this table, so the table always has 28 rows.
7. **Load on `EXECUTE` only.** Open a body only after its `EXECUTE` verdict is recorded, and open a supporting file (`examples/`, `reference/`, `REFERENCE.md`, `DIRECTORY-STRUCTURE.md`) only when an executed step points at it. A `NOT APPLICABLE` skill is never loaded.
8. **Tell a section skip from a skill skip.** A section an executed skill skips (the GraphQL part when `framework.graphql` is false, comment publishing when `capabilities.publish_pr_comments` is false, the mutation section when `capabilities.mutation_testing` is false) keeps the verdict `EXECUTE`, and the skill prints `SKIPPED: <reason>` in its evidence. A whole-skill skip that the profile already decides is settled here, at triage time, as `NOT APPLICABLE` with that `SKIPPED:` reason.
9. **Triage again every iteration.** Each review iteration triages the current head: remediation changes the diff, and a quality row that ended FAIL marks its owner through the overlays. A verdict never changes inside an iteration to drop work already due.
10. **Record the table** before any review lens runs, one row per skill in the order of the skill table, the count `28` stated with it:

    ```text
    | skill | source | verdict | evidence or reason |
    | --- | --- | --- | --- |
    | <skill> | plugin | EXECUTE | <class>: <changed paths> (or <red target>); then <the skill's verdict line> |
    | <skill> | repo+plugin | NOT APPLICABLE | <the condition that holds, with the classes present or the profile value> |
    ```

A missing row, or a reason such as `not relevant`, `n/a`, `skipped` or `out of scope` without the condition behind it, is a silent skip and breaks the gate contract.

## Decision tree by change class

The review's branch guards run before the triage: a protected path or a changed profile ends the stage there, so the triage starts from a change the guards accepted. Every changed path takes the first class that matches it:

```text
changed path (git diff --name-status -M <sha> HEAD)
│
├─ inside the planning bundle (the review's SPECS_DIR) ──────► not classified: input of bmad-fr-nfr-review-gate
├─ the file of service.openapi_snapshot or service.graphql_snapshot ──► Contract
├─ under persistence.migrations_dir, or under .sqlx/ ────────► Migration
├─ any Cargo.toml, Cargo.lock or deny.toml ──────────────────► Manifest/lock
├─ under architecture.composition_root (crates/service) ─────► crates/service wiring
├─ a non-Markdown file of another [workspace].members crate ─► Rust source per layer, by the crate's layer
│    ├─ domain layer ──────────► Domain layer
│    ├─ application layer ─────► Application layer
│    ├─ infrastructure layer ──► Infrastructure layer
│    └─ any other layer ───────► Other layers (test support, end-to-end, tooling)
├─ a Markdown file, anything under docs/, a .github/ file ───► Workflow/docs-only
└─ anything else ────────────────────────────────────────────► Other files

then, for the branch as a whole:
├─ adds a <group>/<context> absent from [workspace].members at the merge base ──► New context
├─ bootstraps a service from the template, or removes its example context ─────► New service
└─ every classified path is Workflow/docs-only ─────────────────────────────────► no class marks more than the six docs-only skills
```

The skills a change needs are the union of the `EXECUTE` lists of every class present, plus the overlays. A skill that no present class and no overlay marks is `NOT APPLICABLE`, and its reason names the classes present.

### Rust source per layer

A crate's layer is the `[[layer]]` of `architecture.toml` whose `crates` pattern matches the crate's package name; the layer names are the profile's `architecture.layers`, and a `<context>-<layer>` crate sits in a directory named for its layer. Shared crates (`architecture.shared_crates`) take the layer of their own name like any other crate. When `architecture.layers` is empty, take the layer from the crate directory name (`domain`, `application`, `infrastructure`) and put every other crate under Other layers.

#### Domain layer

Aggregates, entities, value objects, domain events, domain error enums and port traits of a bounded context or of a shared domain crate.

- EXECUTE (12): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `implementing-ddd-architecture`, `clean-architecture-llm`, `code-organization`, `rust-error-handling`, `async-runtime-safety`, `complexity-management`, `testing-workflow`, `security-audit`.

#### Application layer

Commands, queries, subscribers, HTTP handlers and DTOs, GraphQL types and the error mapping into `Problem`.

- EXECUTE (15): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `api-resource-development`, `api-contract-development`, `clean-architecture-llm`, `code-organization`, `rust-error-handling`, `async-runtime-safety`, `observability-instrumentation`, `complexity-management`, `testing-workflow`, `security-audit`, `documentation-sync`.

#### Infrastructure layer

Repository adapters and their sqlx queries, cache adapters, clients of external systems, integration tests of the crate.

- EXECUTE (14): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `clean-architecture-llm`, `code-organization`, `rust-error-handling`, `async-runtime-safety`, `observability-instrumentation`, `complexity-management`, `testing-workflow`, `security-audit`, `query-performance-analysis`, `cache-management`.

#### Other layers

Test-support, end-to-end and tooling crates, wherever their `[workspace].members` entry lives.

- EXECUTE (10): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `code-organization`, `rust-error-handling`, `async-runtime-safety`, `complexity-management`, `testing-workflow`, `security-audit`.

### `crates/service` wiring

Every file under `architecture.composition_root` except its `Cargo.toml`: the router and schema roots, the `Adapters { .. }` literals, the clap CLI and config modules, the tracing subscriber, the health probes and the contract-pinning tests.

- EXECUTE (16): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `api-resource-development`, `api-contract-development`, `clean-architecture-llm`, `code-organization`, `configuration-management`, `observability-instrumentation`, `rust-error-handling`, `async-runtime-safety`, `complexity-management`, `testing-workflow`, `security-audit`, `documentation-sync`.

### Manifest/lock

Any `Cargo.toml` (the workspace manifest, a crate manifest, the composition root's manifest), `Cargo.lock` and `deny.toml`.

- EXECUTE (8): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `dependency-policy`, `architecture-model-sync`, `code-organization`, `security-audit`.

### Migration

Files under `persistence.migrations_dir` and the offline query metadata under `.sqlx/`.

- EXECUTE (8): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `database-migrations`, `query-performance-analysis`, `testing-workflow`, `security-audit`.

### Contract

The committed snapshot files named by `service.openapi_snapshot` and `service.graphql_snapshot`.

- EXECUTE (6): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `api-contract-development`, `documentation-sync`.

### Workflow/docs-only

Markdown files anywhere outside the classes above (crate READMEs, `AGENTS.md`, `CLAUDE.md`, `.claude/skills/`), every file under `docs/`, and every `.github/` file other than the contract snapshots: workflows, the pull-request template, issue templates.

- EXECUTE (6): `documentation-sync`, `documentation-creation`, `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`.
- NOT APPLICABLE: the other 22 skills. When every classified path of the change is in this class, these six are its only `EXECUTE` marks, which is the token bound the triage keeps for a documentation change.
- A changed `.github/workflows/` file also starts the security lens of `/rs-sdlc-review` by the lens's own path rule. The lens applies `security-audit` in its own session; it is not a triage verdict, so the triage row stays `NOT APPLICABLE` here.

### Other files

Every path no class above takes: build and compose files, environment files, load tests, end-to-end scenarios, the architecture model, scripts and tool configuration.

- EXECUTE (4, always): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`.
- EXECUTE by path, each only when such a path is present:
  - `tests/Load/` (a K6 scenario or its budget in `tests/Load/config.json.dist`): `load-testing`;
  - `features/` (an end-to-end scenario): `testing-workflow`;
  - `workspace.dsl`: `architecture-model-sync`;
  - `.env`, `.env.test` or a `docker-compose*.yml` file: `configuration-management`;
  - `Dockerfile`: `security-audit`;
  - `Makefile` or a `make/*.mk` file: `documentation-sync`.

### New context

A branch class: the change adds a `<group>/<context>` under `architecture.crates_root` that is not a `[workspace].members` entry at the merge base (`git show <sha>:Cargo.toml`), the run is `/rs-sdlc-new-context`, or the plan's story 1 "Scaffold `<group>/<context>`" is in progress. It adds its list to the classes of its paths.

- EXECUTE (20): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `bounded-context-scaffolding`, `architecture-model-sync`, `dependency-policy`, `implementing-ddd-architecture`, `clean-architecture-llm`, `code-organization`, `api-resource-development`, `api-contract-development`, `rust-error-handling`, `async-runtime-safety`, `observability-instrumentation`, `complexity-management`, `database-migrations`, `testing-workflow`, `security-audit`, `documentation-sync`.

### New service

A branch class: `/rs-sdlc-new-service` runs or resumes one of its steps S1–S14 (the bootstrap branch of a service created from the template), or the story removes the template's example bounded context from a fresh service. It adds its list to the classes of its paths.

- EXECUTE (11): `code-review`, `quality-standards`, `verification-workflow`, `bmad-fr-nfr-review-gate`, `service-scaffolding`, `api-contract-development`, `architecture-model-sync`, `configuration-management`, `database-migrations`, `documentation-creation`, `documentation-sync`.

### Evidence overlays

Two kinds of evidence mark a skill whatever the classes present, because they come from what happened to the change rather than from where its paths live:

1. **Red target.** A target is red when it exited non-zero, or measured over its `quality.*` bound, in the previous iteration's quality rows or in the stage's own gate run. Its owner is `EXECUTE` in the next triage, with the target and its finding as evidence:

   | Red target | Owner marked `EXECUTE` |
   | --- | --- |
   | `make.static_analysis` | `rust-error-handling` for error, panic, conversion and suppression lints; `async-runtime-safety` for `await_holding_lock`, `disallowed_methods` and `clone_on_ref_ptr` |
   | `make.complexity` | `complexity-management` |
   | `make.architecture`, `make.check_crate_isolation` | `architecture-boundary-fixer` |
   | `make.unused_dependencies` | `dependency-policy`, and `architecture-boundary-fixer` when the finding is a dependency edge between layers or contexts |
   | `make.check_security` | `dependency-policy` |
   | `make.validate_architecture_model` | `architecture-model-sync` |
   | `make.tests_with_coverage`, `make.e2e_tests`, `make.mutation_tests_diff` | `testing-workflow` |
   | `make.validate_sqlx_metadata` | `database-migrations` |
   | `make.validate_contract_snapshots`, `make.validate_openapi_spec`, `make.openapi_diff`, `make.graphql_diff` | `api-contract-development` |
   | `make.docs_check`, `make.validate_invariants` | `documentation-sync` |
   | `make.secrets_scan`, `make.image_scan` | `security-audit` |
   | `make.smoke_load_tests` | `load-testing` |
   | `make.format_check` | no owner: the formatter mapped by `make.format` fixes it, recorded in the evidence of `verification-workflow` |

   The configuration guard has no owner skill: a protected change is the branch guards' D23 escalation, never a triage verdict.
2. **Moved code.** A rename (status `R`) whose old and new paths sit in different crates, layers or bounded contexts marks `architecture-boundary-fixer` and `code-organization`.

The overlays add only the skills this evidence names; they never change what a class marks, so the workflow/docs-only class still marks six.

## Skill table

One row per skill directory, 28 rows in directory order. "EXECUTE when" names the classes and evidence that mark the skill; "NOT APPLICABLE when" gives the condition the reason must state. The skill's own `description` holds the full trigger.

| skill | EXECUTE when | NOT APPLICABLE when |
| --- | --- | --- |
| `api-contract-development` | Application layer, `crates/service` wiring, Contract, New context or New service is present (a handler annotation, DTO, GraphQL type, route or snapshot can change what clients see), or a contract target is red | none of those classes is present and no contract target is red; or `framework.openapi` and `framework.graphql` are both false (`SKIPPED: no API contract`) |
| `api-resource-development` | Application layer, `crates/service` wiring or New context is present: an operation, command, query, subscriber, extractor or problem mapping is added or changed | no application-layer or composition-root file changed and no context is added; or `framework.http` is null and `framework.graphql` is false |
| `architecture-boundary-fixer` | the overlay marks it: `make.architecture` or `make.check_crate_isolation` is red, `make.unused_dependencies` reports a cross-layer edge, or code moves between crates, layers or bounded contexts | no boundary target is red and no code moved between layers or contexts; or `make.architecture`, `make.check_crate_isolation` and `make.unused_dependencies` are all null |
| `architecture-model-sync` | Manifest/lock adds, renames or removes a `[workspace].members` entry or a crate-to-crate dependency; `workspace.dsl` changed; New context or New service; or `make.validate_architecture_model` is red | no member, crate-to-crate dependency or external system appears or disappears; or `capabilities.structurizr` is false (`SKIPPED: capabilities.structurizr is false`) |
| `async-runtime-safety` | a Rust source class, `crates/service` wiring or New context touches an `async fn`, an `.await`, a spawned task, a `tokio::select!`, a timeout, a lock shared between tasks, an `#[async_trait]` impl, a time read or an identifier source; or `make.static_analysis` reports one of its lints | the change touches no async code, no shared state and no time or identifier source (no Rust source class present, or only synchronous, stateless items changed) |
| `bmad-autonomous-planning` | the plan stage must write or rewrite the issue's planning bundle (no committed bundle with a ready verdict on the branch); no change class of this tree marks it | the bundle is already committed with a ready verdict: every review and later stage records this planning-time reason |
| `bmad-fr-nfr-review-gate` | every class: an implemented change exists on the feature branch, and the gate runs once per review iteration and before PR finishing ends | no path is classified (the diff since the merge base is empty or holds only the planning bundle: nothing implemented to trace); a false `capabilities.publish_pr_comments` skips only the publishing step and keeps `EXECUTE` |
| `bounded-context-scaffolding` | New context: the change adds a `<group>/<context>` absent from `[workspace].members` at the merge base, the run is `/rs-sdlc-new-context`, or the scaffold story 1 is in progress | every context the change touches already exists at the merge base (a feature inside it) |
| `cache-management` | Infrastructure layer adds or changes a cache adapter, or the story asks for a cache with a staleness budget or a measured need | no cache adapter is added or changed and the story gives no staleness budget or measured need |
| `clean-architecture-llm` | Domain, Application or Infrastructure layer, `crates/service` wiring or New context: a type, module, dependency or model-provider integration must be placed in a layer | no layered Rust source changed (only other layers, manifests, migrations, contracts, documentation or other files); or `architecture.layers` is empty and `architecture.composition_root` is null |
| `code-organization` | a Rust source class, `crates/service` wiring, Manifest/lock or New context adds, moves, renames or splits a crate, module, source file or test file; or a review finding or the static analysis flags the layout | no crate, module, source file or test file is added, moved, renamed or split (edits inside existing files only) and nothing flags the layout |
| `code-review` | always, in every class and every review iteration | never; a false `capabilities.publish_pr_comments` skips only its publishing step |
| `complexity-management` | a Rust source class, `crates/service` wiring or New context changes a function body (measured against the `clippy.toml` limits), or `make.complexity` is red | no Rust function body changed and `make.complexity` reports nothing; a null `make.complexity` records the measurement not run (capability absent) and leaves the verdict to the diff |
| `configuration-management` | `crates/service` wiring touches the CLI or config modules; Other files changes `.env`, `.env.test` or a compose file; or the code adds, renames or removes a setting, an environment variable, a `?=` make variable or the HTTP port (New service included) | no setting, environment variable, make or compose variable or port changes; or `architecture.composition_root` is null (`SKIPPED: architecture.composition_root is null`) |
| `database-migrations` | Migration is present, New context persists data, New service removes the example context, or `make.validate_sqlx_metadata` is red | no migration or query-metadata file changed and no schema change is needed; or `persistence.engine` is null (`SKIPPED: persistence.engine is null`) |
| `dependency-policy` | Manifest/lock is present (a dependency table, `Cargo.lock`, `deny.toml`), New context adds workspace dependencies, or `make.check_security` or `make.unused_dependencies` is red (a RUSTSEC advisory included) | no manifest or lock file changed and neither target reports a finding; or both targets are null and the change touches no manifest or lock file |
| `documentation-creation` | Workflow/docs-only or New service adds a documentation page that did not exist at the merge base (a runbook, a guide to one adapter or context, an integration reference) | the change adds no documentation page (existing pages only, or no documentation at all); a null `make.docs_check` skips only the proof run |
| `documentation-sync` | Workflow/docs-only, Application layer, `crates/service` wiring, Contract, New context or New service is present; Other files changes `Makefile` or a `make/*.mk` file; or `make.docs_check` or `make.validate_invariants` is red | no make target, `service` command or flag, environment variable, endpoint, GraphQL field, workflow job or procedure is added, renamed or removed, and no documentation or workflow file changed |
| `implementing-ddd-architecture` | Domain layer or New context: an aggregate, entity, value object, domain event, domain error enum or port trait is added or changed, or a use case needs time, identifiers or storage through a port | no domain crate changed and no context is added; or `architecture.layers` and `architecture.bounded_contexts` are both empty |
| `load-testing` | Other files changes `tests/Load/` (a scenario or its budget in `tests/Load/config.json.dist`), or `make.smoke_load_tests` or its required PR check is red | no load-test file changed and no smoke run is red; or `capabilities.load_testing` is false (`SKIPPED: capabilities.load_testing is false`) |
| `observability-instrumentation` | Application or Infrastructure layer, `crates/service` wiring or New context: a handler, command or query handler, subscriber, adapter call, error path or health probe is added or changed | the change touches no Rust source of those layers (domain only, other layers, manifests, migrations, contracts, documentation or other files) |
| `quality-standards` | always, in every class and every review iteration: the quality rows read their bars from it | never; a bar whose gate target is null is recorded not run (capability absent) inside it |
| `query-performance-analysis` | Infrastructure layer changes a sqlx query, or Migration adds an index or a query; or a query is slow, hits the statement timeout or runs once per item (N+1) | no query or index changes and no slow query is reported; or `persistence.engine` is null (`SKIPPED: persistence.engine is null`) |
| `rust-error-handling` | a Rust source class, `crates/service` wiring or New context adds or changes an error type, a fallible function, a `Problem` conversion, an HTTP or GraphQL error response or a lint suppression; or `make.static_analysis` reports one of its lints | no Rust source changed and the static analysis reports none of its lints |
| `security-audit` | a Rust source class, `crates/service` wiring, Manifest/lock, Migration, New context or a `Dockerfile` change is present, or `make.secrets_scan` or `make.image_scan` is red | the change touches no Rust source, manifest, lock, migration, query metadata, `deny.toml` or `Dockerfile` (a workflow file still starts the security lens by its own path rule); a false `capabilities.dynamic_security_testing` skips only the dynamic probes |
| `service-scaffolding` | New service: `/rs-sdlc-new-service` runs or resumes S1–S14, or the story removes the template's example bounded context | the repository is an existing service whose bootstrap pull request has merged and no example-context removal is planned |
| `testing-workflow` | a Rust source class, `crates/service` wiring, Migration or New context is present; Other files changes `features/`; or `make.tests_with_coverage`, `make.e2e_tests` or `make.mutation_tests_diff` is red | no production or test code changed (manifest, contract, documentation or other files outside `features/` only) and no test target is red; false `capabilities.mutation_testing` or `capabilities.load_testing` skips only that section |
| `verification-workflow` | every class: the change must pass the gate stages before it is called complete | no path is classified (nothing changed to prove), or every stage key from `make.ci_preflight` to `make.ci_delivery` is null; a single null stage is recorded not run (capability absent) inside it |

## Example: a workflow/docs-only change

The diff edits `docs/<existing page>.md`, adds `docs/<new page>.md` and changes `.github/workflows/<workflow>.yml`. Every path is Workflow/docs-only, no target is red and nothing moved, so six rows are `EXECUTE` and loaded:

- `documentation-sync` (`repo+plugin`): workflow/docs-only: the three paths.
- `documentation-creation` (`plugin`): workflow/docs-only: `docs/<new page>.md` is new.
- `code-review` (`plugin`): always.
- `quality-standards` (`repo+plugin`): always.
- `verification-workflow` (`repo+plugin`): workflow/docs-only: the change must pass the gate stages.
- `bmad-fr-nfr-review-gate` (`plugin`): workflow/docs-only: an implemented change exists on the branch.

The other 22 rows are `NOT APPLICABLE` and none of their bodies is opened, for example:

- `security-audit` (`plugin`): classes present: workflow/docs-only; no Rust source, manifest, lock, migration, query metadata, `deny.toml` or `Dockerfile` path (the workflow change starts the security lens on its own).
- `database-migrations` (`plugin`): classes present: workflow/docs-only; no migration or query-metadata file.
- `bmad-autonomous-planning` (`repo+plugin`): the bundle is committed with a ready verdict.
- `service-scaffolding` (`plugin`): an existing service whose bootstrap pull request has merged.

Had the diff only edited the existing page, `documentation-creation` would be `NOT APPLICABLE` (no new page) and five rows would be `EXECUTE`.
