# Implementing DDD Architecture — Reference

Worked patterns for [the implementing-ddd-architecture skill](SKILL.md): the anatomy of a pure domain crate, value objects, domain errors, aggregates, domain events, ports, the adapters and use cases that meet them, the clock and identifier rules, domain tests and the shared kernel. Every example is written for the bounded context `<group>/<context>` and the aggregate `<Entity>`; replace the placeholders with the names of the change and copy the shapes of the repository's existing contexts where they differ.

## Placeholders

| Placeholder | Meaning | Example use |
| --- | --- | --- |
| `<group>/<context>` | the bounded context: its group directory and its context directory | `<group>/<context>/domain/` |
| `<context>` | the crate-name stem of the context, kebab-case | package `<context>-domain`, imported as `<context>_domain` |
| `<Context>` | the context name in prose | crate description |
| `<Entity>` | the aggregate type, UpperCamelCase | `<Entity>`, `<Entity>Id`, `<Entity>Created` |
| `<entity>` | the aggregate in snake_case | event wire name `<entity>.created`, file `create_<entity>.rs` |
| `<Tech>` | the technology prefix of an adapter | `<Tech><Entity>Repository` |

## Domain crate anatomy

One domain crate per bounded context, beside its application and infrastructure crates. The module names below are the convention of a template-derived workspace; follow whatever the repository's existing domain crates use, and add a top-level module only when none of them fits. File placement rules (sibling `tests.rs`, no `mod.rs`) are in [code-organization](../code-organization/SKILL.md).

```text
<group>/<context>/domain/
├── Cargo.toml
└── src/
    ├── lib.rs               crate documentation, pub mod declarations, pub use re-exports
    ├── aggregate.rs         <Entity>
    ├── aggregate/
    │   └── tests.rs
    ├── error.rs             Invalid<Entity>
    ├── error/
    │   └── tests.rs
    ├── event.rs             <Entity>Created, <Entity>Renamed
    ├── repository.rs        <Entity>Repository, RepositoryError
    ├── value_object.rs      pub mod declarations only
    └── value_object/
        ├── id.rs            <Entity>Id
        ├── id/
        │   └── tests.rs
        ├── name.rs          <Entity>Name
        └── name/
            └── tests.rs
```

When the workspace has no shared kernel (`architecture.shared_crates` is empty), the context's domain crate also carries the technical ports:

```text
<group>/<context>/domain/src/
├── port.rs                  pub mod declarations only
└── port/
    ├── clock.rs             Clock
    └── uuid_generator.rs    UuidGenerator
```

## Manifest of a pure domain crate

The manifest declares only what the domain layer entry of `architecture.toml` allows. A sourced example from a template-derived repository, where `shared-domain` is the package of the shared-kernel domain crate whose path `architecture.shared_crates` lists:

```toml # profile-example
[package]
name = "<context>-domain"
description = "<Context> context, domain layer: the <Entity> aggregate, its value objects, events and repository port"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true
publish.workspace = true
repository.workspace = true

[dependencies]
async-trait.workspace = true
shared-domain.workspace = true
thiserror.workspace = true

[dev-dependencies]
proptest.workspace = true
rstest.workspace = true

[lints]
workspace = true
```

- `uuid` is added only when the crate needs the raw `uuid::Uuid` type; the shared kernel re-exports a validated `Uuid` value object that contexts use instead.
- No `tokio`, `serde`, `tracing`, `sqlx`, `axum` or HTTP client, not even as an optional or transitive dependency: the domain layer's `forbidden_transitive` list makes the boundary check fail on them.
- No dev-dependency on the test-support crate: the domain layer allows none, so domain tests define their own small fakes.

## Value objects

### Identity value object

The identity wraps the shared `Uuid` and never changes. It is `Copy`, hashable and has no validation of its own because `Uuid` is already valid.

```rust
//! Identifier of an `<Entity>`.

use shared_domain::Uuid;

/// The identifier of an `<Entity>`; it never changes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct <Entity>Id(Uuid);

impl <Entity>Id {
    /// Wraps a UUID.
    #[must_use]
    pub const fn new(value: Uuid) -> Self {
        Self(value)
    }

    /// Returns the wrapped UUID.
    #[must_use]
    pub const fn value(self) -> Uuid {
        self.0
    }
}

#[cfg(test)]
mod tests;
```

### Validated value object

A value object with a rule validates in `new` and cannot be built invalid. The error is a variant of the context's invariant enum, so the application layer can report the property and the code.

```rust
//! The name of an `<Entity>`.

use crate::error::Invalid<Entity>;

/// A name of 1 to 255 Unicode scalar values without U+0000, stored as given.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct <Entity>Name(String);

impl <Entity>Name {
    /// The largest number of Unicode scalar values.
    pub const MAX_CHARS: usize = 255;

    /// Validates the name.
    ///
    /// # Errors
    ///
    /// [`Invalid<Entity>::NameLength`] when the value is empty or longer than
    /// [`Self::MAX_CHARS`], [`Invalid<Entity>::NameContainsNul`] when it contains U+0000.
    pub fn new(value: String) -> Result<Self, Invalid<Entity>> {
        if !(1..=Self::MAX_CHARS).contains(&value.chars().count()) {
            return Err(Invalid<Entity>::NameLength);
        }
        if value.contains('\0') {
            return Err(Invalid<Entity>::NameContainsNul);
        }
        Ok(Self(value))
    }

    /// The name as given.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[cfg(test)]
mod tests;
```

### When to create a value object

| Field | Decision | Reason |
| --- | --- | --- |
| the aggregate's identifier | value object `<Entity>Id` | identities of different aggregates must never be mixed up |
| a text or number with bounds, a format or a forbidden character | value object `<Entity><Concept>` | the rule lives in one constructor instead of every caller |
| an amount with a unit or a currency | value object | arithmetic and comparison need the unit |
| a flag or a free text with no rule | primitive field | a wrapper without a rule adds code and no safety |
| a reference to another aggregate | that aggregate's identifier type | the aggregate holds identities, never other aggregates |

## Domain errors

### Invariant error enum

One enum per invariant family, one variant per broken rule. The message is the client-facing sentence; `property_path()` and `code()` let the application layer build a validation problem without parsing text. The type is named for what failed; a type named `Error` is never written (the static analysis flags it as `error_impl_error`).

```rust
//! Domain errors of the <Context> context.

/// A value that breaks an invariant of `<Entity>`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum Invalid<Entity> {
    /// The name has fewer than 1 or more than 255 characters.
    #[error("This value must contain between 1 and 255 characters.")]
    NameLength,
    /// The name contains U+0000.
    #[error("This value must not contain the NUL character.")]
    NameContainsNul,
}

impl Invalid<Entity> {
    /// The property that carries the invalid value.
    #[must_use]
    pub const fn property_path(self) -> &'static str {
        match self {
            Self::NameLength | Self::NameContainsNul => "name",
        }
    }

    /// The machine-readable violation code.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::NameLength => "length",
            Self::NameContainsNul => "does_not_contain",
        }
    }
}

#[cfg(test)]
mod tests;
```

### Port error enum

Each port that can fail has its own enum, declared in the module of its port (`RepositoryError` in `repository.rs`). An infrastructure failure crosses the port as `#[source] BoxError`, the only place `BoxError` is used; a driver type (a database or SDK error) never appears in a domain signature.

```rust
use shared_domain::BoxError;

/// A repository operation failed.
#[derive(Debug, thiserror::Error)]
pub enum RepositoryError {
    /// An aggregate with the same identifier is already stored.
    #[error("the aggregate already exists")]
    AlreadyExists,
    /// The storage cannot be reached or answered with a failure.
    #[error("the repository is unavailable")]
    Unavailable(#[source] BoxError),
}
```

The context's application error wraps these enums with `#[from]` or a constructor and is converted to the problem document once; that mapping is owned by [rust-error-handling](../rust-error-handling/SKILL.md).

## Aggregates

An aggregate is the consistency boundary: one transaction changes one aggregate. Its fields are private, it is built only from valid value objects, every state change goes through a method that enforces the invariant and records one event, and it implements `AggregateRoot` so the handler can drain the events after saving.

```rust
//! The `<Entity>` aggregate.

use std::time::SystemTime;

use shared_domain::{AggregateRoot, RecordedEvents, Uuid};

use crate::event::{<Entity>Created, <Entity>Renamed};
use crate::value_object::id::<Entity>Id;
use crate::value_object::name::<Entity>Name;

/// An `<Entity>`: an identifier and a name, built only from valid value objects.
#[derive(Debug)]
pub struct <Entity> {
    id: <Entity>Id,
    name: <Entity>Name,
    events: RecordedEvents,
}

impl <Entity> {
    /// Builds a new aggregate and records `<Entity>Created`.
    #[must_use]
    pub fn create(id: <Entity>Id, name: <Entity>Name, event_id: Uuid, occurred_at: SystemTime) -> Self {
        let mut entity = Self::restore(id, name);
        entity.events.record(<Entity>Created {
            event_id,
            aggregate_id: id.value(),
            occurred_at,
        });
        entity
    }

    /// Rebuilds a stored aggregate; records nothing.
    #[must_use]
    pub fn restore(id: <Entity>Id, name: <Entity>Name) -> Self {
        Self {
            id,
            name,
            events: RecordedEvents::default(),
        }
    }

    /// Renames the aggregate and records `<Entity>Renamed`; renaming to the current name records
    /// nothing.
    pub fn rename(&mut self, name: <Entity>Name, event_id: Uuid, occurred_at: SystemTime) {
        if self.name == name {
            return;
        }
        self.name = name;
        self.events.record(<Entity>Renamed {
            event_id,
            aggregate_id: self.id.value(),
            occurred_at,
        });
    }

    /// The identifier.
    #[must_use]
    pub const fn id(&self) -> <Entity>Id {
        self.id
    }

    /// The name.
    #[must_use]
    pub const fn name(&self) -> &<Entity>Name {
        &self.name
    }
}

impl AggregateRoot for <Entity> {
    fn recorded_events(&mut self) -> &mut RecordedEvents {
        &mut self.events
    }
}

#[cfg(test)]
mod tests;
```

Rules the example shows:

- `create` and `restore` are separate: loading from storage must not record a creation event.
- The time and the event identifier are arguments. The aggregate never reads a clock or generates an identifier, so its tests need no doubles and every result is reproducible.
- A behaviour method takes value objects, so it cannot receive an invalid value; a rule that spans several fields is checked inside the method and returns `Result<(), Invalid<Entity>>` when it can fail.
- An aggregate references another aggregate only by identifier.

## Domain events

An event is an immutable fact named in the past tense. It carries its own identifier, the aggregate identifier, the time and the data subscribers need, and a stable wire name `<entity>.<past_tense_verb>`.

```rust
//! Domain events of the <Context> context.

use std::time::SystemTime;

use shared_domain::{DomainEvent, Uuid};

/// An `<Entity>` was created.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct <Entity>Created {
    /// Identifier of the event.
    pub event_id: Uuid,
    /// Identifier of the created aggregate.
    pub aggregate_id: Uuid,
    /// When the aggregate was created.
    pub occurred_at: SystemTime,
}

impl <Entity>Created {
    /// The stable wire name of the event.
    pub const NAME: &'static str = "<entity>.created";
}

impl DomainEvent for <Entity>Created {
    fn event_id(&self) -> Uuid {
        self.event_id
    }

    fn aggregate_id(&self) -> Uuid {
        self.aggregate_id
    }

    fn occurred_at(&self) -> SystemTime {
        self.occurred_at
    }

    fn event_name(&self) -> &'static str {
        Self::NAME
    }
}
```

Subscribers live in the application crate, are idempotent and never call the command bus; another bounded context reacts to the event instead of importing this context's crates.

## Ports

### Repository port

A repository stores and loads whole aggregates of one type. It is declared in the domain crate, takes and returns domain types, and has `std::fmt::Debug + Send + Sync` as supertraits so a handler can hold it as `Arc<dyn <Entity>Repository>`.

```rust
//! Repository port of the <Context> context.

use shared_domain::{BoxError, PageRequest};

use crate::aggregate::<Entity>;
use crate::value_object::id::<Entity>Id;

// RepositoryError, shown under "Port error enum", is declared here, beside the port.

/// Stores `<Entity>` aggregates.
#[async_trait::async_trait]
pub trait <Entity>Repository: std::fmt::Debug + Send + Sync {
    /// Inserts a new aggregate.
    ///
    /// # Errors
    ///
    /// [`RepositoryError::AlreadyExists`] when the identifier is stored,
    /// [`RepositoryError::Unavailable`] when the storage fails.
    async fn save(&self, entity: &<Entity>) -> Result<(), RepositoryError>;

    /// Finds an aggregate by identifier.
    ///
    /// # Errors
    ///
    /// [`RepositoryError::Unavailable`] when the storage fails.
    async fn find_by_id(&self, id: <Entity>Id) -> Result<Option<<Entity>>, RepositoryError>;

    /// Returns one page of aggregates in a stable order.
    ///
    /// # Errors
    ///
    /// [`RepositoryError::Unavailable`] when the storage fails.
    async fn find_page(&self, page: PageRequest) -> Result<Vec<<Entity>>, RepositoryError>;
}
```

Methods are named for domain intent (`save`, `find_by_id`, `find_page`), never for SQL or a driver call, and return aggregates, never rows or views. A read model for a query is the application layer's concern.

### Clock and identifier ports

The shared kernel's domain crate declares both technical ports. When `architecture.shared_crates` is empty, the context's domain crate declares them in its own `port` module with the same shapes:

```rust
//! Clock port.

/// Source of the current time.
pub trait Clock: std::fmt::Debug + Send + Sync {
    /// The current time.
    fn now(&self) -> std::time::SystemTime;
}
```

```rust
//! UUID generator port.

use crate::value_object::uuid::Uuid;

/// Source of new identifiers.
pub trait UuidGenerator: std::fmt::Debug + Send + Sync {
    /// A new identifier.
    fn generate(&self) -> Uuid;
}
```

### Other driven capabilities

A capability the domain needs from the outside world (sending a notification, asking an external system, evaluating with a model provider) is a port named for the capability (`<Entity>Notifier`, `<Entity>Evaluator`), with typed request and response value objects and its own error enum. The vendor, the credentials, the client and the retries live in the infrastructure adapter; the composition root chooses the adapter.

## Adapters

An adapter in the infrastructure crate implements a port. Every method of an `#[async_trait]` implementation is a single delegation to an inherent `async fn` of the adapter, because coverage records no line counts and the complexity check reports nothing inside such a body; the logic and the translation of driver errors into the port error live in the inherent methods.

```rust
/// Stores `<Entity>` aggregates with <Tech>.
#[derive(Debug)]
pub struct <Tech><Entity>Repository {
    // the client or pool of <Tech>
}

impl <Tech><Entity>Repository {
    async fn insert(&self, entity: &<Entity>) -> Result<(), RepositoryError> {
        // driver call; every driver error goes through one translation function that returns
        // RepositoryError::AlreadyExists or RepositoryError::Unavailable(Box::new(error))
    }
}

#[async_trait::async_trait]
impl <Entity>Repository for <Tech><Entity>Repository {
    async fn save(&self, entity: &<Entity>) -> Result<(), RepositoryError> {
        self.insert(entity).await
    }

    // find_by_id and find_page delegate the same way
}
```

The clock and identifier adapters already exist once in the shared infrastructure crate of a template-derived repository (search for `impl Clock for` and `impl UuidGenerator for`). They are the only items allowed to call the banned methods, each with an item-level `#[expect(clippy::disallowed_methods, reason = "...")]`; a context injects them and never writes another.

## Using ports in a use case

The application handler holds the ports, reads the time and a new event identifier from them, passes both into the aggregate, saves it and publishes the drained events. The trait method only delegates to the inherent `async fn`.

```rust
use std::sync::Arc;

use shared_domain::{AggregateRoot as _, Clock, Command, CommandHandler, EventBus, Uuid, UuidGenerator};
use <context>_domain::{<Entity>, <Entity>Id, <Entity>Name, <Entity>Repository};

use crate::error::<Entity>Error;

/// Creates an `<Entity>` with an identifier chosen by the caller.
#[derive(Debug, Clone)]
pub struct Create<Entity> {
    /// Identifier of the new aggregate.
    pub id: Uuid,
    /// Name of the new aggregate.
    pub name: String,
}

impl Command for Create<Entity> {
    type Error = <Entity>Error;
    const NAME: &'static str = "Create<Entity>";
}

/// Handles [`Create<Entity>`].
#[derive(Debug)]
pub struct Create<Entity>Handler {
    repository: Arc<dyn <Entity>Repository>,
    event_bus: Arc<dyn EventBus>,
    clock: Arc<dyn Clock>,
    uuid_generator: Arc<dyn UuidGenerator>,
}

impl Create<Entity>Handler {
    async fn create(&self, command: Create<Entity>) -> Result<(), <Entity>Error> {
        let mut entity = self.build(command)?;
        self.store(&entity).await?;
        self.publish(&mut entity).await;
        Ok(())
    }

    fn build(&self, command: Create<Entity>) -> Result<<Entity>, <Entity>Error> {
        let name = <Entity>Name::new(command.name)?;
        Ok(<Entity>::create(
            <Entity>Id::new(command.id),
            name,
            self.uuid_generator.generate(),
            self.clock.now(),
        ))
    }

    // store maps RepositoryError into <Entity>Error; publish sends entity.pull_domain_events()
    // to the event bus and logs a failed subscriber without failing the command
}

#[async_trait::async_trait]
impl CommandHandler<Create<Entity>> for Create<Entity>Handler {
    async fn handle(&self, command: Create<Entity>) -> Result<(), <Entity>Error> {
        self.create(command).await
    }
}
```

A command returns no data; a query handler never changes state and returns views, not aggregates.

## Time and identifiers

The `disallowed-methods` list of `clippy.toml` is the source of the ban; read it in the repository. The replacements:

| Never call | Use instead | Where the value comes from |
| --- | --- | --- |
| `SystemTime::now` | `Clock::now()` | `Arc<dyn Clock>` injected into the handler; the aggregate receives `occurred_at: SystemTime` as an argument |
| `Instant::now` | nothing in the domain; `tokio::time` (`Instant`, `sleep`, `timeout`) in an outer layer | a domain rule about elapsed time takes the instants or the `Duration` as arguments; tests pause tokio time instead of waiting |
| `Uuid::new_v4`, `Uuid::now_v7` | `UuidGenerator::generate()` | `Arc<dyn UuidGenerator>` injected into the handler; an aggregate identifier chosen by the client arrives in the command |

The composition root wires the real adapters; tests wire a fixed clock and a sequence generator, so every time and identifier in a test is known in advance.

## Testing the domain

Tests live in the sibling `tests.rs` of the module they test and use literal values only. Tests may unwrap, so helper functions build fixtures directly:

```rust
use std::time::{Duration, SystemTime};

use shared_domain::{AggregateRoot as _, DomainEvent as _, Uuid};

use super::<Entity>;
use crate::value_object::id::<Entity>Id;
use crate::value_object::name::<Entity>Name;

fn uuid(text: &str) -> Uuid {
    Uuid::parse(text).unwrap()
}

fn time() -> SystemTime {
    SystemTime::UNIX_EPOCH.checked_add(Duration::from_secs(1_700_000_000)).unwrap()
}

fn id() -> <Entity>Id {
    <Entity>Id::new(uuid("0192f3a0-7b1c-7d2e-8f3a-4b5c6d7e8f90"))
}

fn name(text: &str) -> <Entity>Name {
    <Entity>Name::new(text.to_owned()).unwrap()
}

#[test]
fn create_records_exactly_one_created_event() {
    let event_id = uuid("0192f3a0-7b1c-7d2e-8f3a-000000000001");
    let mut entity = <Entity>::create(id(), name("First"), event_id, time());

    let events = entity.pull_domain_events();

    assert_eq!(events.len(), 1);
    assert_eq!(events.first().unwrap().event_name(), "<entity>.created");
    assert!(entity.pull_domain_events().is_empty());
}

#[test]
fn renaming_to_the_current_name_records_nothing() {
    let mut entity = <Entity>::restore(id(), name("First"));

    entity.rename(name("First"), uuid("0192f3a0-7b1c-7d2e-8f3a-000000000002"), time());

    assert!(entity.pull_domain_events().is_empty());
}
```

- Test names are snake_case sentences that state the behaviour, without a `test_` prefix.
- A value object gets one test per rule and one per boundary (empty, the maximum, the maximum plus one, the forbidden character); a property test uses the repository's fixed seed.
- An invariant enum gets a test for the message, the `property_path()` and the `code()` of every variant.
- A domain crate takes no dev-dependency on the test-support crate; a fake it needs (for example a port double for a domain service) is defined in its own `tests.rs`. Application tests use the shared doubles of the test-support crate instead.

## Shared kernel

The shared-kernel crates (the paths `architecture.shared_crates` lists) hold what every context needs and nothing context-specific:

| Belongs in the shared domain crate | Stays in the context |
| --- | --- |
| `AggregateRoot`, `RecordedEvents`, `DomainEvent`, `DomainEventSubscriber` | the aggregate, its value objects and its events |
| command, query and event bus traits and the bus error | the context's application error enum |
| `Clock`, `UuidGenerator`, `Cache` and other technical ports | the repository port and capability ports of the context |
| value objects with no context meaning (`Uuid`, `PageRequest`) | value objects named for the aggregate |
| `BoxError` and error-chain helpers | the invariant and port error enums |

A type moves into the shared kernel only when a second context needs it, and only when it carries no context meaning. When `architecture.shared_crates` is empty there is no shared kernel: each context declares the abstractions it needs, and creating a shared context is an `architecture.toml` change that is escalated, never made in passing.

## Anti-patterns

| Anti-pattern | Why it fails | Fix |
| --- | --- | --- |
| public aggregate fields set by a handler | invariants are bypassed and events are not recorded | private fields and a behaviour method that records the event |
| validation only in a request DTO | other entry points (GraphQL, subscribers, tests) skip it | validate in the value-object constructor; the DTO validation is an early, friendlier copy |
| `SystemTime::now()` or a random identifier in an aggregate | non-deterministic tests, a clippy ban-list finding | pass `occurred_at` and `event_id` in; read them from `Clock` and `UuidGenerator` in the handler |
| `pub enum Error` or a crate-wide catch-all error | names nothing, collides with `std::error::Error`, flagged by the static analysis | one enum per invariant family and per port, named for what failed |
| a database row or wire-format derive on a domain type | the domain depends on a framework; the boundary check fails | a row or DTO type in the outer layer with explicit mapping |
| a repository that returns rows or views | storage leaks into the domain | return aggregates; build views in the query handler |
| an adapter that holds business rules | rules become untestable without the infrastructure | move the rule into the aggregate or a value object |
| logging or spawning inside the domain | the domain gains a runtime and side effects | the application logs where the error is handled |
| importing another context's domain crate | contexts couple and the boundary check fails | a domain event, or a type moved into the shared kernel |

## Review checklist

- [ ] The domain manifest lists only `async-trait`, `thiserror`, `uuid` and domain crates of `<context>` or the shared kernel, or exactly what the domain layer entry allows.
- [ ] No `SystemTime::now`, `Instant::now`, `Uuid::new_v4` or `Uuid::now_v7` call outside the owning adapter.
- [ ] No type named `Error`; every error enum derives `thiserror::Error` and invariant enums answer `property_path()` and `code()`.
- [ ] Aggregate fields are private; `create` records one event, `restore` records none, each behaviour method records one past-tense event.
- [ ] Every port has `std::fmt::Debug + Send + Sync` supertraits and every `#[async_trait]` implementation method delegates to an inherent `async fn`.
- [ ] Every new module has its tests in a sibling `tests.rs` with literal UUIDs and times.
- [ ] Nothing context-specific was moved into the shared kernel, and nothing from the shared kernel was redefined in the context.
