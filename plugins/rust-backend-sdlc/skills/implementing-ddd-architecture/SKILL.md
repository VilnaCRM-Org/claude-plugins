---
name: implementing-ddd-architecture
description: Use when Rust code adds or changes an aggregate, an entity, a value object, a domain event, a domain error enum or a port trait (a repository, `Clock`, `UuidGenerator` or another driven capability) in the domain crate of a bounded context, or when a use case needs the current time, a new identifier or storage and must reach it through a port. Covers rich aggregates that record their events, validated value objects, domain errors as `thiserror` enums (never a type named `Error`), ports instead of `SystemTime::now`, `Instant::now` and `Uuid::new_v4`, and pure domain crates (only `async-trait`, `thiserror`, `uuid` and domain crates of the own or the shared context). Skip when `architecture.layers` and `architecture.bounded_contexts` are both empty (no layered bounded-context workspace). Not for crate, module and test-file placement (use code-organization), not for mapping errors to problem documents (use rust-error-handling), not for the responsibilities of the non-domain layers (use clean-architecture-llm), not for repairing a failing boundary check (use architecture-boundary-fixer).
---

# Implementing DDD Architecture in Rust

## Profile keys consumed

- `architecture.layers` — the declared layer names; the layer that depends on no other layer is the domain layer, and its third-party allow-list bounds what a domain crate may use
- `architecture.bounded_contexts` — the existing `<group>/<context>` names (informational; the live workspace members win), which decide whether the change extends a context or needs a new one first
- `architecture.shared_crates` — the shared-kernel crates whose domain crate provides the aggregate, event, error and port abstractions (`AggregateRoot`, `DomainEvent`, `BoxError`, `Clock`, `UuidGenerator`) that a context reuses instead of redefining

## Context

Use this skill before writing or reviewing domain code: a new aggregate or entity, a new invariant, a value object, a domain event, a domain error, a repository or another port trait, or a use case that would otherwise read the system clock, generate an identifier or touch storage directly. Generated Rust drifts toward anemic structs with public fields, validation in handlers, `SystemTime::now()` inside an aggregate and a catch-all `Error` type; this skill fixes the shape before the boundary check and static analysis have to.

Placeholders used throughout: `<group>/<context>` is the bounded context of the change (for example the directory pair below the crates root), `<context>` is its crate-name stem (`<context>-domain`, imported as `<context>_domain`), `<Entity>` is the aggregate type in UpperCamelCase and `<entity>` its snake_case form. Read the real names from the repository; never copy names from the repository's sample context into a new one.

Inputs: the story or review scope, the profile, the domain layer entry of `architecture.toml`, the domain crate of `<group>/<context>` when it exists, and the shared-kernel domain crate when `architecture.shared_crates` lists one. Worked examples of every pattern below (manifest, value objects, errors, aggregate, events, ports, adapter, use case, tests, shared kernel) are in [REFERENCE.md](REFERENCE.md).

## Task

Model the change as aggregates, value objects, domain events, domain errors and ports inside the pure domain crate of `<group>/<context>`, so that application handlers only orchestrate (load, call one aggregate method, save, publish), infrastructure adapters only implement ports, and the domain crate compiles with nothing but the dependencies its layer entry allows.

## Success criteria

- Every new invariant is enforced in a value-object constructor or an aggregate method, never in a handler, a DTO or an adapter.
- Every aggregate keeps its fields private, is built only from valid value objects, records exactly one event per state change through `AggregateRoot`, and offers `create` (records the creation event) and `restore` (records nothing).
- Every value object is a newtype with a private field whose `new` validates and returns `Result<Self, Invalid<Entity>>`; the identity is `<Entity>Id(Uuid)`.
- Every domain error is a `thiserror` enum named for what failed (`Invalid<Entity>`, `RepositoryError`, `<Capability>Error`); invariant enums answer `property_path()` and `code()`; no type anywhere is named `Error`.
- Every port is a trait declared in a domain crate with `std::fmt::Debug + Send + Sync` supertraits (`#[async_trait::async_trait]` when its methods are `async`); time comes from `Clock`, identifiers from `UuidGenerator`; no `SystemTime::now`, `Instant::now`, `Uuid::new_v4` or `Uuid::now_v7` call exists outside the one adapter that owns it.
- The domain manifest's `[dependencies]` lists only `async-trait`, `thiserror`, `uuid` and domain crates of `<context>` or the shared kernel, or exactly what the domain layer entry of `architecture.toml` allows when that entry differs; the domain crate never logs, never spawns, never performs I/O.
- Every new domain module has deterministic unit tests in its sibling `tests.rs` (literal UUIDs and times, no clock, no randomness without a fixed seed).
- The verdict line of step 11 is printed.

## Steps

1. **Resolve the profile.** Read the three keys. When `architecture.layers` and `architecture.bounded_contexts` are both empty, the repository is not a layered bounded-context workspace: print `SKIPPED: architecture.layers and architecture.bounded_contexts are empty`, then `implementing-ddd-architecture: SUCCESS-WITH-REPORT`, and stop. When only `architecture.layers` is empty, apply every rule below to the crate whose name ends in `-domain`, note `no layer model: domain identified by crate name` in the evidence, and never invent a layer entry.
2. **Find the domain layer and its allow-list.** When `architecture.layers` is non-empty, read each named entry in `architecture.toml`; the entry whose `depends_on` names no layer but its own is the domain layer. Its `external` list is the complete set of third-party crates a domain crate may use and its `forbidden_transitive` list names crates that must not be reachable at all. A sourced example (the domain `[[layer]]` entry of a template-derived repository):

   ```toml # profile-example
   [[layer]]
   name = "domain"
   crates = ["*-domain"]
   depends_on = ["domain"]
   external = ["async-trait", "thiserror", "uuid"]
   forbidden_transitive = ["axum", "hyper", "reqwest", "sqlx", "tokio"]
   ```

   When the change needs a crate outside `external` (a time library, a decimal type, a serialization derive), redesign first: keep the domain on the standard library and the allowed crates, and move the integration outward behind a port (step 7). When no redesign removes the need, stop and hand the decision to [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md), whose escalation block covers allow-list changes; this skill's verdict is then `ESCALATED`.
3. **Locate the bounded context.** When `architecture.bounded_contexts` lists `<group>/<context>`, confirm it in the live workspace members of the root `Cargo.toml` (the list is informational and the live tree wins) and extend its domain crate. When the list is empty or does not contain the context, search the live members for a `<context>-domain` crate; when none exists, the context must be created first through [bounded-context-scaffolding](../bounded-context-scaffolding/SKILL.md), then this skill resumes at step 4; when that skill escalates, this skill's verdict is `ESCALATED`. Place files as [code-organization](../code-organization/SKILL.md) prescribes.
4. **Reuse the shared kernel or declare locally.** When `architecture.shared_crates` lists a path whose manifest names a package ending in `-domain`, that crate is the shared domain kernel: import `AggregateRoot`, `RecordedEvents`, `DomainEvent`, `BoxError`, `Clock`, `UuidGenerator` and the shared value objects from it, and never redefine them in a context. Move a type into that crate only when a second context needs it, and only types that are domain abstractions (never a context's aggregate, error or repository port). When `architecture.shared_crates` is empty or lists no domain crate, there is no shared domain kernel: declare the clock and identifier ports in the `port` module of `<context>-domain` itself, with the same trait shapes (REFERENCE.md, "Ports"), and record `no shared kernel: ports declared in <context>-domain` in the evidence.
5. **Model value objects.** One newtype per concept that carries a rule (an identifier, a bounded text, an amount): private field, `new` that validates and returns `Result<Self, Invalid<Entity>>`, read accessors (`as_str`, `value`), `Debug`, `Clone`, `PartialEq`, `Eq` derives, and `Copy` for small types. Name value objects with the aggregate as prefix (`<Entity>Name`, `<Entity>Id`). Count text length in Unicode scalar values (`chars().count()`), never in bytes. A field with no rule stays a primitive; a value object that only wraps without validating is noise, except the identity.
6. **Model the aggregate.** A struct with private fields of value-object types plus `events: RecordedEvents`; `create(...)` builds the aggregate and records `<Entity>Created`; `restore(...)` rebuilds a stored aggregate and records nothing; each behaviour method takes valid value objects, enforces the cross-field invariant, changes state and records one past-tense event; accessors are `#[must_use] pub const fn` where possible; `impl AggregateRoot for <Entity>` returns the event store. The time and the event identifier of a recorded event are **arguments** (`event_id: Uuid`, `occurred_at: SystemTime`), so the aggregate stays a pure function of its inputs.
7. **Declare ports.** A port is a trait in a domain crate named for the capability without prefix or suffix (`<Entity>Repository`, `Clock`, `UuidGenerator`, `<Entity>Notifier`), never for a vendor. It takes and returns domain types only, returns `Result<_, <Port>Error>` where it can fail, and has `std::fmt::Debug + Send + Sync` as supertraits so handlers can hold it as `Arc<dyn Port>`. Async methods use `#[async_trait::async_trait]`; every implementation of such a method is a single delegation to an inherent `async fn` of the adapter (REFERENCE.md, "Adapters"). The port error wraps an infrastructure failure as `Unavailable(#[source] BoxError)`, the only place `BoxError` appears.
8. **Replace clock and identifier calls with ports.** The wall clock is read only through `Clock::now()`, new identifiers only through `UuidGenerator::generate()`, both injected into the application handler as `Arc<dyn Clock>` and `Arc<dyn UuidGenerator>`; the handler passes the values into the aggregate (step 6). `SystemTime::now`, `Uuid::new_v4` and `Uuid::now_v7` appear only inside the single adapter of each port. Search for `impl Clock for` and `impl UuidGenerator for`: when the repository already ships an adapter, inject it and never add a second one; when it ships none (typically together with no shared kernel), add exactly one adapter per port in an infrastructure crate, carrying the item-level `#[expect(clippy::disallowed_methods, reason = "...")]` the lint policy requires, and wire it in the composition root. `Instant::now` has no domain use: a domain rule that depends on elapsed time takes the instants or the duration as arguments, and an outer layer that measures elapsed time or a timeout uses `tokio::time`, which tests can pause. The `disallowed-methods` list of `clippy.toml` is the authoritative ban list; read it, never restate or edit it.
9. **Model domain errors.** One `thiserror` enum per invariant family (`Invalid<Entity>`), one variant per broken rule, the `#[error("...")]` text the client-facing sentence, plus `const fn property_path(self)` and `const fn code(self)` with exhaustive matches; one enum per port (`RepositoryError` with `AlreadyExists` and `Unavailable(#[source] BoxError)` variants, for example). A lower-level error is wrapped as `#[source]`, never formatted into the message. The conversion of these errors into the context's application error and the problem document belongs to [rust-error-handling](../rust-error-handling/SKILL.md).
10. **Test the domain.** Unit tests go in the sibling `tests.rs` of each module (`value_object/name.rs` ends with `#[cfg(test)] mod tests;`, the tests are in `value_object/name/tests.rs`). Use literal UUIDs (`Uuid::parse` of a fixed string) and fixed times (`SystemTime::UNIX_EPOCH` plus a constant duration); a property test of a value-object bound uses the repository's fixed seed. A domain crate defines the few fakes it needs inside its own `tests.rs` files, because the domain layer takes no dev-dependency on the test-support crate. Each behaviour method has a test for every invariant branch and for the exact event it records.
11. **Verify and report.** Run the commands of `## Verification` on the domain crate of `<group>/<context>`; each prints nothing or only the allowed crates. Then run the boundary check and the static analysis as [clean-architecture-llm](../clean-architecture-llm/SKILL.md) step 8 and [verification-workflow](../verification-workflow/SKILL.md) prescribe. Print exactly one verdict line:

    ```text
    implementing-ddd-architecture: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
    ```

    `SUCCESS`: every check passes and the boundary check ran and passed. `SUCCESS-WITH-REPORT`: the skill was skipped in step 1, ran without a layer model or a shared kernel, or the boundary check is not mapped and the manual manifest check was recorded instead. `ESCALATED`: step 2 or step 3 handed off a decision that escalated; the escalation block printed by that skill is the evidence.

## Constraints

- Never add a framework, driver, runtime, logging, serialization or HTTP crate to a domain manifest, and never edit the allow-list in `architecture.toml` so that domain code compiles; an allow-list change is escalated through architecture-boundary-fixer.
- Never name a type `Error`; name every error enum for what failed.
- Never call `SystemTime::now`, `Instant::now`, `Uuid::new_v4` or `Uuid::now_v7` in a domain, application or infrastructure module other than the one adapter that owns the call, and never edit the `disallowed-methods` list of `clippy.toml`.
- Never expose an aggregate field as `pub`, never let a handler change aggregate state field by field, and never validate a domain rule only in a DTO.
- Never put wire-format, database-row or framework derives on a domain type; map to and from such types in the outer layer.
- Never write `#[allow]`; a suppression is an item-level `#[expect(lint, reason = "...")]` only where the lint policy permits it.
- Never import from another bounded context's crates; share through a domain event or a shared-kernel type.
- Write examples as `<group>/<context>` and `<Entity>`; read the real names from the repository.

## Verification

Run from the repository root with `<domain-crate>` set to the directory of the `<context>-domain` crate:

```bash
grep -rnE 'SystemTime::now|Instant::now|Uuid::new_v4|Uuid::now_v7' <domain-crate>/src
grep -rnE '(enum|struct|type) Error\b' <domain-crate>/src
grep -rnE '^use (axum|sqlx|tokio|serde|tracing|reqwest|hyper)' <domain-crate>/src
awk '/^\[dependencies\]/{f=1;next} /^\[/{f=0} f' <domain-crate>/Cargo.toml
```

The first three print nothing; the last prints only `async-trait`, `thiserror`, `uuid` and domain crates of `<context>` or the shared kernel (or exactly the crates the domain layer entry allows). The boundary check and the static analysis then pass as step 11 describes, and the output ends with the verdict line.
