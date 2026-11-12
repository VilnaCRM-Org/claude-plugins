---
name: api-resource-development
description: Use when adding or changing a REST or GraphQL operation, a command, a query or an event subscriber inside one bounded context of a Rust axum service, covering the four request extractors, the problem-document error model, the I/O ports, the composition-root wiring and the contract snapshot co-change. Skip the REST part when `framework.http` is null and the GraphQL part when `framework.graphql` is false. Not for snapshot validation, Spectral findings or breaking changes (use api-contract-development), not for a migration (use database-migrations) and not for creating a bounded context (use bounded-context-scaffolding).
---

# API Resource Development

## Profile keys consumed

- `framework.http` — the HTTP framework; a non-null value selects the REST steps, null skips them
- `framework.openapi` — true requires the OpenAPI annotation on every REST handler and the OpenAPI snapshot co-change; false drops both
- `framework.graphql` — true selects the GraphQL section; false skips it
- `persistence.engine` — a non-null value selects a database adapter behind the repository port; null means no database adapter
- `architecture.composition_root` — the crate that wires handlers, subscribers, adapters, routes and GraphQL roots; null stops the skill
- `make.generate_openapi_spec` — the target that regenerates the OpenAPI snapshot in the same change
- `make.generate_graphql_spec` — the target that regenerates the GraphQL snapshot in the same change
- `make.tests_with_coverage` — the evidence target for unit and integration tests under the coverage floor
- `make.e2e_tests` — the evidence target for the end-to-end scenarios over HTTP

## Repository precedence

Read `.claude/skills/api-resource-development/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line.

The repository skill holds the recipes for its own source tree (file names, module names, registration calls). Where its wording differs from the Steps below, follow the repository skill and write the difference into the `precedence:` line of the evidence; a precedence note is not a degrade note and does not change the verdict. When the repository skill is absent, the Steps below apply in full and the evidence records `source: plugin` instead of `source: repo+plugin`.

## Context

- The service is a Rust workspace with one crate per layer per bounded context. The example context in this skill is `<group>/<context>` with its three crates `domain`, `application` and `infrastructure`, and the aggregate is `<Entity>`. Never copy the template's sample context names into new code.
- Layer order is domain, then application, then infrastructure, then the wiring in the composition root named by `architecture.composition_root`. A domain crate stays framework-free and I/O-free.
- A REST handler and a GraphQL resolver call the same command or query, so a behaviour change reaches both contracts.
- The skill runs inside a loop stage (the implementation stage or the remediation step of the review stage) after the triage recorded `EXECUTE` for it, or directly when a person asks for an operation change. Snapshot validation, Spectral findings and the breaking-change policy belong to [api-contract-development](../api-contract-development/SKILL.md); migrations belong to [database-migrations](../database-migrations/SKILL.md).

## Task

Add or change one operation of `<group>/<context>` (a REST endpoint, a GraphQL field, a command, a query or an event subscriber) so that it follows the template's extractors, error model and ports, ships its regenerated contract snapshots in the same change, and is proven by the evidence targets. Report the result in the evidence format and end with the verdict line.

## Success criteria

1. Every new or changed REST handler takes its path, query and body only through `ApiPath`, `ValidatedQuery`, `ValidatedJson` or `ApiJson`; no handler signature extracts with the bare axum `Path`, `Query` or `Json`, whose rejections are plain text.
2. Every error path of a handler or resolver ends in a `Problem` served as `application/problem+json`; the context's application error enum converts into `Problem` variant by variant.
3. Every command returns no data: its handler result carries only success or the application error, and the caller reads the new state through a query.
4. Every subscriber is idempotent: handling the same event twice leaves the same state, and no subscriber dispatches a command.
5. Time, identifiers, storage and messaging are reached only through ports (`Clock`, `UuidGenerator`, the repository port, `EventBus`); outside the adapters that implement `Clock` and `UuidGenerator`, the change adds no `SystemTime::now`, `Instant::now` or `Uuid::new_v4`.
6. Each regenerated contract snapshot is part of the same change as the code: the target mapped by `make.generate_openapi_spec` ran when `framework.openapi` is true, and the target mapped by `make.generate_graphql_spec` ran when `framework.graphql` is true.
7. The targets-run list shows the targets mapped by `make.tests_with_coverage` and `make.e2e_tests` as `passed`, or as `not run (<reason>)` with a reason from the closed set.
8. The evidence block and the verdict line are printed.

## Steps

### Profile resolution

1. Read the nine keys above from `.claude/rust-sdlc.yml`. When the profile is missing or unreadable, stop with the escalation block and `recommended_action: run /rs-sdlc-setup on the default branch and commit the result`.
2. Branch on each key before any edit:
   - `architecture.composition_root` null: no wiring point exists, so no new operation can be reached. Stop with the escalation block, `blocking_finding: architecture.composition_root is null`.
   - `framework.http` non-null: run the REST operations steps. Null: skip them and record `SKIPPED: framework.http is null`.
   - `framework.openapi` true: annotate every REST handler and regenerate the OpenAPI snapshot. False: no annotation; record the OpenAPI snapshot step as `SKIPPED: framework.openapi is false`.
   - `framework.graphql` true: run the GraphQL section. False: skip it and record `SKIPPED: framework.graphql is false`.
   - `persistence.engine` non-null: the repository port gets a database adapter in the infrastructure crate. Null: no database adapter and no migration; an operation that needs new storage stops with the escalation block, `blocking_finding: persistence.engine is null`.
   - Any of the four target keys above that is null: its target is recorded `not run (capability absent)` with a degrade note; it is never replaced by a raw command.

### Domain and application

1. Read the existing slice of `<group>/<context>` and copy its shape. In the domain crate add or change the aggregate `<Entity>`, its value objects, its domain error enum, its events and the repository port trait. See [implementing-ddd-architecture](../implementing-ddd-architecture/SKILL.md) for aggregates and ports.
2. A command: a struct that implements `Command` with `Error` set to the context's application error, and a handler that holds its ports as `Arc<dyn Port>`, keeps the logic in an inherent `async fn` and lets the `#[async_trait]` `CommandHandler` impl only delegate. The handler loads or creates one aggregate, saves it, then publishes the pulled domain events; a publication failure is logged per subscriber and never fails the command. The command returns no data: the caller generates the identifier through the `UuidGenerator` port before the dispatch and reads the result through a query.
3. A query: the same shape with `Output` set to a view or a list of views. A query handler never mutates state and returns views, never aggregates.
4. An event subscriber: implements `DomainEventSubscriber` for one event, never dispatches a command, and is idempotent (an upsert keyed by the aggregate identifier or a check on the event identifier, never a blind insert). Delivery is at most once; when the story needs guaranteed delivery, stop with the escalation block, `blocking_finding: guaranteed delivery needs an outbox`, because adding an outbox is an architecture decision.
5. Error model: the context has one application error enum, and `impl From<...> for Problem` maps every variant explicitly; an invariant violation becomes the 422 problem of type `/problems/validation-failed` with one entry in `violations[]` per property. See [rust-error-handling](../rust-error-handling/SKILL.md) for the full error model.

### REST operations

Run this subsection when `framework.http` is non-null; otherwise it is skipped as recorded in the profile resolution.

1. Add the request DTO with serde and `Validate` attributes (and `ToSchema` when `framework.openapi` is true), and the response DTO.
2. Write the handler with these extractors only: `ApiPath` for path parameters, `ValidatedQuery` for a query string with constraints, `ValidatedJson` for a body with constraints, `ApiJson` for a body without constraints. Their rejections are already `Problem` documents. The handler returns `Result<_, Problem>`.
3. When `framework.openapi` is true, annotate the handler with `#[utoipa::path]`: operation id, tag, summary, description, the 2xx response, every specific problem response with content type `application/problem+json`, and the `default` response. When it is false, write no annotation.
4. Register the handler in the context's router. Unit-test it with the fake command and query buses of the repository (`FakeCommandBus`, `FakeQueryBus`) and add one end-to-end scenario per outcome (success and each problem response).

### GraphQL section

When `framework.graphql` is false, skip this section and record `SKIPPED: framework.graphql is false`. When it is true:

1. Add the field to the context's query or mutation root. It calls the same command or query as the REST handler and converts a `Problem` into a GraphQL error with the shared conversion, so both interfaces report the same problem.
2. A context that has no GraphQL roots yet adds them to the schema's root tuples and its state to the schema data in the composition root.
3. Regenerate the GraphQL snapshot with the target mapped by `make.generate_graphql_spec` (see the snapshot co-change).

### Infrastructure and wiring

1. When `persistence.engine` is non-null, implement the repository port in the infrastructure crate with compile-time checked queries, and put its integration tests in `<crate>/tests/integration/main.rs`. A schema change goes through [database-migrations](../database-migrations/SKILL.md) in the same change.
2. In the composition root named by `architecture.composition_root`: register each new command and query handler, each subscriber, each adapter, the context's router and its GraphQL roots, and extend the wiring test. The places are listed by the repository skill; in the template they are:

   ```text # profile-example
   crates/service/src/bootstrap.rs          register_commands, register_queries, event_bus, Adapters::connect
   crates/service/src/openapi.rs            api_router nests the context router under /api
   crates/service/src/graphql/schema.rs     Query and Mutation root tuples
   crates/service/src/bootstrap/tests.rs    wiring test
   ```

3. Unit tests live in a sibling `tests.rs` next to the module they test and use fake ports and fixed seeds; time and identifiers come from fake `Clock` and `UuidGenerator` implementations.

### Snapshot co-change

1. When `framework.openapi` is true, run the target mapped by `make.generate_openapi_spec`; when `framework.graphql` is true, run the target mapped by `make.generate_graphql_spec`. Stage every regenerated snapshot file in the same change as the code. A snapshot is never edited by hand.
2. A key set to null records `not run (capability absent)` and the degrade note "contract snapshot not regenerated"; the change then needs [api-contract-development](../api-contract-development/SKILL.md) before review.
3. Continue with [api-contract-development](../api-contract-development/SKILL.md) for snapshot validation, the Spectral bar and the breaking-change policy.

### Evidence and the bounded loop

1. Run the target mapped by `make.tests_with_coverage`, then the target mapped by `make.e2e_tests`, as the [verification-workflow](../verification-workflow/SKILL.md) skill prescribes (in the background, log under `target/rust-sdlc/logs/`, polled until it exits, container route when the profile asks for it).
2. Record each target as `passed`, `failed` or `not run (<reason>)` with a reason from the closed set: `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`.
3. A failed target starts one iteration: read its log, fix the root cause in the code or the test, re-run that target, then re-run both evidence targets. The iterations count against the invoking stage's guard, `MAX_ITERATIONS=5`, and the counter is never reset; used directly, the same cap of five applies.
4. A target that cannot run is not an iteration: `not run (no Docker)` or `not run (no toolchain)` ends the skill `ESCALATED` at once and is never fed to the fix loop. A fifth failed iteration ends `ESCALATED` with the escalation block.

## Constraints

- Never extract with the bare axum `Path`, `Query` or `Json` in a handler; use `ApiPath`, `ValidatedQuery`, `ValidatedJson` or `ApiJson`.
- Never return data from a command, and never dispatch a command from a query or a subscriber.
- Never call `SystemTime::now`, `Instant::now` or `Uuid::new_v4` outside the adapters behind `Clock` and `UuidGenerator`; never read I/O from a domain crate.
- Never edit a contract snapshot by hand, and never leave a contract change without its regenerated snapshot.
- Never use `unwrap`, `expect`, `panic!`, indexing or `as` casts in production code; never add a `mod.rs` or a type named `Error`.
- Never add `#[allow(...)]`, `#[coverage(off)]` or `#[mutants::skip]`, and never lower a coverage floor or delete a test so that a target passes; fix the root cause.
- Never edit a protected file (the list printed by `cargo xtask config-guard --list`); a change that needs one stops with the escalation block and `recommended_action: approved-config-change label and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`.
- Write values only by profile key; concrete service values appear only in fences marked `# profile-example`.

## Verification

Self-checks on the change before the evidence targets, where `<merge-base>` is the merge base that the invoking stage computed (used directly: the output of `git merge-base HEAD origin/<default branch>`):

```bash
git diff --name-only <merge-base> -- '*.rs'
git diff <merge-base> -- '*.rs' | grep -nE '^\+.*(SystemTime::now|Instant::now|Uuid::new_v4)'
git diff <merge-base> -- '*.rs' | grep -nE '^\+[[:space:]]*(Path|Query|Json)\([^)]*\)[[:space:]]*:[[:space:]]*(Path|Query|Json)<'
```

The first command lists the changed files. The second must print nothing outside the adapters that implement `Clock` and `UuidGenerator`, and the third (a handler parameter destructured from a bare axum extractor) must print nothing; a hit is fixed before the evidence targets run.

Evidence block, printed once at the end:

```text
skill: api-resource-development
source: repo+plugin | plugin
precedence: <repository rule followed instead of a step of this skill | none>
context: <group>/<context>
change: <REST method and path | GraphQL root.field | command <Name> | query <Name> | subscriber <Name>>
snapshots: <regenerated snapshot files | SKIPPED: <reason>>
targets run:
- <target>: passed | failed | not run (<reason>)
degrade notes: <one per line | none>
iteration: <n>/5
api-resource-development: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
```

The verdict is `SUCCESS` when every applicable target passed and no degrade note exists, `SUCCESS-WITH-REPORT` when the only notes are absent capabilities (`not run (capability absent)` or a `SKIPPED:` line for a false or null key), and `ESCALATED` otherwise. A resolved example:

```text # profile-example
- generate-openapi-spec: passed
- generate-graphql-spec: passed
- tests-with-coverage: passed
- e2e-tests: passed
api-resource-development: SUCCESS
```

When the verdict is `ESCALATED`, print the canonical block with the invoking stage's id and exit string:

```text
=== SDLC ESCALATION ===
stage: <stage-id of the invoking command>
iteration: <n>/5
exit_condition: <exit string of the invoking stage, verbatim>
status: NOT MET
blocking_finding: <file:line | target + exit code | key that is null>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human action>
=== END ===
```
