# Directory Structure Reference

The complete layout that [the code-organization skill](SKILL.md) applies: the workspace, the three layer crates of a bounded context, the shared crates, the composition root, unit and integration test files, module files, the directory law, the naming table, the move checklist and the layout checks. Every example is written for the bounded context `<group>/<context>` and the aggregate `<Entity>`; the module names are the convention of a template-derived workspace, and the repository's existing crates win where they differ.

## Placeholders

| Placeholder | Meaning |
| --- | --- |
| `<crates_root>` | the value of `architecture.crates_root` |
| `<composition_root>` | the value of `architecture.composition_root` |
| `<group>/<context>` | the bounded context: its group directory and its context directory, one of `architecture.bounded_contexts` or a new one |
| `<context>` | the crate-name stem of the context, kebab-case |
| `<layer>` | a layer directory: the `directory` value of a layer entry in `architecture.toml` |
| `<Entity>`, `<entity>` | the aggregate type in UpperCamelCase and in snake_case |
| `<Tech>` | the technology prefix of an adapter |
| `<Purpose>`, `<purpose>` | what a subscriber does, in UpperCamelCase and in snake_case |

## Workspace layout

```text
<repository>/
├── Cargo.toml                     [workspace].members, [workspace.dependencies], [workspace.lints]
├── architecture.toml              layer entries: crate patterns, directories, allowed dependencies
├── workspace.dsl                  one component per crate, one relationship per dependency edge
├── <crates_root>/
│   ├── <group>/
│   │   └── <context>/
│   │       ├── domain/            package <context>-domain
│   │       ├── application/       package <context>-application
│   │       └── infrastructure/    package <context>-infrastructure
│   ├── <shared crates>            the paths that architecture.shared_crates lists
│   └── <composition root>         when architecture.composition_root lies below <crates_root>
└── <support crates>               test doubles, end-to-end suites, tooling: the members outside <crates_root>
```

The profile of a template-derived workspace, as a sourced example (the bounded-context list holds the repository's own contexts):

```yaml # profile-example
architecture:
  crates_root: crates
  composition_root: crates/service
  shared_crates: [crates/shared/application, crates/shared/domain, crates/shared/infrastructure]
  bounded_contexts: ['<group>/<context>']
```

When `architecture.crates_root` is null there is no crates directory: the crate-placement rules do not apply, and the module, test-file and naming rules below apply to whatever crates the workspace has.

## Crate names

| Directory | Package | Library | Layer entry it must match |
| --- | --- | --- | --- |
| `<crates_root>/<group>/<context>/domain` | `<context>-domain` | `<context>_domain` | the entry whose crate pattern is `*-domain` and whose `directory` is `domain` |
| `<crates_root>/<group>/<context>/application` | `<context>-application` | `<context>_application` | the entry whose crate pattern is `*-application` |
| `<crates_root>/<group>/<context>/infrastructure` | `<context>-infrastructure` | `<context>_infrastructure` | the entry whose crate pattern is `*-infrastructure` |

- A workspace crate matches exactly one layer pattern; the boundary check fails on a crate that matches none, and on a crate outside the directory its layer entry names.
- Package names are unique in the workspace, so a context name is unique across all groups; the group is a directory only and is not part of the package name.
- Every crate manifest inherits the workspace package fields (`version.workspace = true` and the others) and sets `[lints] workspace = true`; dependencies are declared as `<name>.workspace = true` against `[workspace.dependencies]`.
- A new context is created with its three crates, its member entries and its workspace dependency entries by bounded-context-scaffolding, never by hand.

## Domain crate

```text
<crates_root>/<group>/<context>/domain/
├── Cargo.toml
└── src/
    ├── lib.rs                     crate documentation, pub mod, pub use
    ├── aggregate.rs               <Entity>
    ├── aggregate/
    │   └── tests.rs
    ├── error.rs                   Invalid<Entity>
    ├── error/
    │   └── tests.rs
    ├── event.rs                   <Entity>Created
    ├── repository.rs              <Entity>Repository, RepositoryError
    ├── value_object.rs            pub mod declarations only
    └── value_object/
        ├── id.rs                  <Entity>Id
        ├── id/
        │   └── tests.rs
        ├── name.rs                <Entity>Name
        └── name/
            └── tests.rs
```

Top-level module names of a domain crate: `aggregate`, `error`, `event`, `port`, `repository`, `value_object` (and `bus` in the shared domain crate). The domain crate has no `tests/integration/` directory: it performs no I/O, so every domain test is a unit test. Its contents are specified by [implementing-ddd-architecture](../implementing-ddd-architecture/SKILL.md).

## Application crate

```text
<crates_root>/<group>/<context>/application/
├── Cargo.toml
└── src/
    ├── lib.rs
    ├── command.rs                         pub mod declarations
    ├── command/
    │   ├── create_<entity>.rs             Create<Entity>, Create<Entity>Handler
    │   └── create_<entity>/
    │       └── tests.rs
    ├── query.rs                           <Entity>View (shared by the queries), pub mod declarations
    ├── query/
    │   ├── get_<entity>.rs                Get<Entity>, Get<Entity>Handler
    │   ├── get_<entity>/
    │   │   └── tests.rs
    │   └── tests.rs                       the tests of query.rs
    ├── subscriber.rs
    ├── subscriber/
    │   ├── <purpose>_<entity>_created.rs  <Purpose><Entity>Created
    │   └── <purpose>_<entity>_created/
    │       └── tests.rs
    ├── error.rs                           <Entity>Error, the one application error of the context
    ├── error/
    │   └── tests.rs
    ├── http.rs                            pub mod declarations, the context's router
    ├── http/
    │   ├── dto.rs                         <Entity>Response, Create<Entity>Request
    │   ├── dto/
    │   │   └── tests.rs
    │   ├── handler.rs                     the HTTP handlers
    │   └── handler/
    │       └── tests.rs
    ├── graphql.rs                         the context's query and mutation roots, when the service has GraphQL
    └── graphql/
        └── tests.rs
```

- Top-level module names of an application crate: `command`, `error`, `graphql`, `http`, `query`, `service`, `subscriber`.
- The use-case modules (`command`, `query`, `subscriber`, `error`, `service`) never import the web framework, the OpenAPI annotations or the GraphQL crate; only `http` and `graphql` do.
- A command, its handler and nothing else share one file named for the command; the same holds for a query.

## Infrastructure crate

```text
<crates_root>/<group>/<context>/infrastructure/
├── Cargo.toml
├── src/
│   ├── lib.rs
│   ├── persistence.rs             <Tech><Entity>Repository, its row type, error translation
│   └── persistence/
│       └── tests.rs
└── tests/
    └── integration/
        ├── main.rs                #[cfg(test)] mod declarations, nothing else
        ├── migration.rs
        └── repository.rs
```

Top-level module names of an infrastructure crate: `bus`, `cache`, `clock`, `id`, `messaging`, `persistence`, `probe`. Row types and driver errors never leave their module; adapters implement domain ports and never call application handlers.

## Shared crates

The paths that `architecture.shared_crates` lists form the shared kernel, laid out exactly like the layer crates of a context, one crate per layer:

```text # profile-example
crates/shared/
├── domain/            shared-domain: aggregate and event abstractions, bus ports, Clock, UuidGenerator, Cache, shared value objects
├── application/       shared-application: problem document, problem-aware extractors, fallbacks, middleware, GraphQL error helpers
└── infrastructure/    shared-infrastructure: in-process buses, cache, clock and UUID adapters, connection pool, migrator
```

- A bounded-context crate may depend on the shared crates of the layers its own layer may depend on (a context's application crate on the shared application and domain crates, for example); a shared crate never depends on a bounded context.
- A type moves into a shared crate only when a second context needs it and it carries no context meaning.
- When `architecture.shared_crates` is empty there is no shared kernel; creating one changes `architecture.toml` and is escalated through architecture-boundary-fixer.

## Composition root

The crate at `architecture.composition_root` is the only production crate that depends on every layer. A sourced example of its modules in a template-derived workspace (each module with children also has its directory, and each tested module its `tests.rs`):

```text # profile-example
crates/service/
├── Cargo.toml
├── src/
│   ├── main.rs        only the call into the library
│   ├── lib.rs
│   ├── cli.rs         command-line parsing; the only reader of the environment
│   ├── config.rs      typed configuration built from the parsed arguments
│   ├── bootstrap.rs   adapters, command, query and subscriber registration, the router
│   ├── command.rs     the subcommands of the binary
│   ├── http.rs        route assembly, fallbacks and middleware
│   ├── graphql.rs     schema assembly from the contexts' roots
│   ├── openapi.rs     contract assembly and export
│   └── telemetry.rs   logging set-up
└── tests/
    └── integration/
        └── main.rs
```

When `architecture.composition_root` is null, the same concerns live in the binary crate's entry module and its own modules; the layer crates still never wire.

## Unit test files

A module with unit tests declares the test module last and keeps the tests in the sibling file:

```rust
// src/value_object/name.rs
pub struct <Entity>Name(String);

// ... the implementation ...

#[cfg(test)]
mod tests;
```

```rust
// src/value_object/name/tests.rs
use super::<Entity>Name;

#[test]
fn rejects_an_empty_name() {
    assert!(<Entity>Name::new(String::new()).is_err());
}
```

- Files named `tests.rs` and everything under a directory named `tests` are outside the coverage report and the mutation scope by construction, which is why tests never sit inline in a production file.
- A unit test opens no socket, needs no container, reads no file outside its crate and reads time only through a clock double or the paused runtime clock.
- Test doubles are named by kind: `Fixed…`, `Sequence…`, `Stub…`, `Fake…`, `Recording…`, `InMemory…`. A domain crate defines its own in its `tests.rs` files; a double that a second crate needs lives in the workspace's test-support crate.

## Integration test files

```text
<crate>/tests/integration/
├── main.rs            one #[cfg(test)] mod <subject>; line per subject
├── support.rs         helpers shared by the subjects, when needed
├── <subject>.rs
└── <other-subject>.rs
```

```rust
// <crate>/tests/integration/main.rs
//! Integration tests of the <Context> repository; each test runs in its own database.

#[cfg(test)]
mod repository;
#[cfg(test)]
mod support;
```

- The directory with its `main.rs` is one test target named `integration`, so each crate has exactly one integration test binary.
- Every module is declared with `#[cfg(test)]`, so the test relaxations of the lint policy apply to helpers without any suppression.
- Integration tests are for a database, a message queue, real time, a socket or the built binary; everything else is a unit test.

## Module files

| Right | Wrong |
| --- | --- |
| `src/value_object.rs` declaring `pub mod name;` | `src/value_object/mod.rs` |
| `src/value_object/name.rs` | `src/value_object/name/mod.rs` |
| `src/value_object/name/tests.rs` | an inline `mod tests { ... }` block at the end of `name.rs` |
| `src/command/create_<entity>.rs` | `src/commands.rs` holding every command of the context |

- One module per file; snake_case file and module names.
- `foo/` exists only when `foo` has children or tests; `foo.rs` and `foo/mod.rs` never coexist, and `mod.rs` is never written.
- `foo.rs` holds the `pub mod` declarations of its children and only what all of them share (for example the view type that every query returns).

## The directory law

The law is: "a directory named for a type holds only that type".

| Directory | Holds only | Never holds |
| --- | --- | --- |
| `value_object/` | value objects, one per file, with their `tests.rs` | an aggregate, a port, a free helper function |
| `command/` | commands, each with its handler in the same file | queries, views, DTOs |
| `query/` | queries, each with its handler, and the tests of `query.rs` | commands or any code that changes state |
| `subscriber/` | event subscribers | command handlers, adapters |
| `port/` | port traits | adapters or other implementations |
| `http/` | DTOs, HTTP handlers and the context's router | use-case logic, storage access |
| `persistence/` | storage adapters and their row types | business rules |
| `foo/` beside `foo.rs` | the children and the tests of `foo` | modules unrelated to `foo` |

- A type that fits no existing directory goes to a new directory named for a well-known pattern (a builder, a factory, a policy), never to `utils`, `helpers`, `common`, `misc`, `types` or `models`.
- A file in the wrong directory is moved to the directory of its kind; the directory is never renamed to cover a mixed content.

## Naming

| Thing | Rule | Example |
| --- | --- | --- |
| layer crate | `<context>-<layer>`, kebab-case | `<context>-domain` |
| module and file | snake_case, one module per file | `value_object/name.rs` |
| aggregate | UpperCamelCase noun | `<Entity>` |
| value object | the aggregate name as prefix | `<Entity>Name`, `<Entity>Id` |
| domain event | the aggregate name plus a past-tense verb; wire name `<entity>.<verb>` | `<Entity>Created`, `<entity>.created` |
| command, query | an imperative verb plus the aggregate; the handler is `<Message>Handler`; the file is the snake_case message name | `Create<Entity>`, `Create<Entity>Handler`, `create_<entity>.rs` |
| port | a noun without prefix or suffix | `<Entity>Repository` |
| adapter | the technology as prefix | `<Tech><Entity>Repository` |
| subscriber | `<Purpose><EventName>` | `Audit<Entity>Created` |
| DTO | `<Entity>Response`, `<Verb><Entity>Request`, `<Verb><Entities>Params` | `Create<Entity>Request` |
| error | named for what failed, never `Error` | `Invalid<Entity>`, `RepositoryError`, `<Entity>Error` |
| test function | a snake_case sentence stating the behaviour, no `test_` prefix | `rejects_a_name_longer_than_the_maximum` |
| test double | a kind prefix | `Fixed…`, `Sequence…`, `Stub…`, `Fake…`, `Recording…`, `InMemory…` |

## Moving or renaming

1. Move `foo.rs` and the directory `foo/` together (`git mv`), so the children and the `tests.rs` files travel with the module.
2. Update the `pub mod` declaration in the old and the new parent module.
3. Update every `use` path in the crate and in the crates that import the module, and every `pub use` re-export in `lib.rs`.
4. When a type moves to another crate, move its tests with it, add the dependency to the manifest of the crate that now uses it and remove the dependency nothing uses any more.
5. When a crate is renamed or moved, update its `[workspace].members` entry, its `[workspace.dependencies]` entry, every manifest that names it and `workspace.dsl` (architecture-model-sync) in the same change.
6. Run the layout checks below, then the static analysis and the boundary check.

## Layout checks

Run from the repository root with `<roots>` set to `<crates_root>`, plus `<composition_root>` when it lies outside `<crates_root>`:

```bash
find <roots> -name mod.rs -not -path '*/target/*'
grep -rnE --include='*.rs' '^[[:space:]]*(pub )?mod tests[[:space:]]*\{' <roots>
find <roots> -path '*/tests/*.rs' -not -path '*/tests/integration/*' -not -path '*/target/*'
find <roots> \( -name utils.rs -o -name helpers.rs -o -name common.rs -o -name misc.rs \) -not -path '*/target/*'
find <roots> -type d -path '*/tests/integration' -exec test ! -f '{}/main.rs' \; -print
grep -nF '<group>/<context>/' Cargo.toml
```

The first five print nothing (no `mod.rs`, no inline test module, no stray integration test file, no catch-all module, no integration directory without its `main.rs`); the last prints one `[workspace].members` entry and one `[workspace.dependencies]` entry per layer crate of the context.
