---
name: rust-error-handling
description: Use when Rust code adds or changes an error type, a fallible function, a conversion into `Problem`, an HTTP or GraphQL error response or a lint suppression, or when the target mapped by `make.static_analysis` reports `unwrap_used`, `expect_used`, `panic`, `indexing_slicing`, `as_conversions`, `error_impl_error` or an unfulfilled `#[expect]`. Covers the four-level error model (domain `thiserror` enums, one application error enum per bounded context, `BusError`, the `application/problem+json` document) and the suppression policy. Skip the HTTP mapping step when `framework.http` is null and the GraphQL error section when `framework.graphql` is false. Not for adding an endpoint or a GraphQL operation (use api-resource-development), not for aggregate and value-object design (use implementing-ddd-architecture), not for complexity findings (use complexity-management).
---

# Rust Error Handling

## Profile keys consumed

- `framework.http` — `axum` selects the step that maps errors to the `application/problem+json` document; `null` means the service has no HTTP layer and that step is skipped
- `framework.graphql` — `true` adds the GraphQL error section; `false` skips it
- `make.static_analysis` — the strict static analysis (clippy over production and test code with warnings denied) that proves the code is panic-free and its suppressions are valid; `null` degrades to a manual review of the diff

## Context

A service derived from the Rust template carries every failure through four levels, and each level has exactly one shape:

1. **Domain.** A `thiserror` enum per broken invariant set (`Invalid<Entity>`), with `property_path()` and `code()`, plus one error enum per port (for example `RepositoryError`). Domain crates neither log nor know HTTP.
2. **Application.** One application error enum per bounded context (`<Entity>Error` in `crates/<group>/<context>/application/src/error.rs`), the `Error` associated type of every command and query of that context.
3. **Bus.** `BusError<E>`: `NotRegistered { message }` (a wiring defect) or `Handler(E)` (the application error of the handler).
4. **Problem.** The RFC 9457 document served as `application/problem+json`, whose `type` is one of `about:blank`, `/problems/validation-failed` (with `violations[]`) and `/problems/dependency-unavailable` (with `failures[]`).

Use this skill when a change touches any of these levels, adds a fallible function, adds or removes a lint suppression, or when static analysis reports a panicking shortcut, a lossy `as` conversion, a type named `Error` or an unfulfilled expectation. The repository's own rules in `AGENTS.md` and its architecture document win where they are stricter.

## Task

Make every failure path typed, propagated with `?` and converted exactly once into the response the client sees, with no panicking shortcut in production code and no lint suppression outside the policy, and prove it with the target mapped by `make.static_analysis`.

## Success criteria

- Every new invariant violation is a variant of a domain `thiserror` enum that answers `property_path()` and `code()`; every new fallible function returns the `thiserror` type of its layer.
- The bounded context has exactly one application error enum, and every command and query of the context names it as its `Error` type.
- Every `From<…> for Problem` maps each variant explicitly (no wildcard arm) to one of the three problem types; every 5xx goes through `Problem::internal`.
- Production code contains no `unwrap`, `expect`, `panic!`, `todo!`, `unimplemented!`, `unreachable!`, slice or string indexing and no `as` conversion; no type is named `Error`.
- Every suppression is an item-level `#[expect(lint, reason = "…")]` that names one lint, never sits in a crate root and never names a complexity lint.
- The target mapped by `make.static_analysis` passes; when it is null, the manual review of step 9 is recorded and the result is `SUCCESS-WITH-REPORT`, never a claimed pass.

## Steps

### 1. Resolve the profile

Read `framework.http`, `framework.graphql` and `make.static_analysis` from the profile. Note which of steps 5 and 6 apply, and whether static analysis runs as a target (step 8) or degrades to the manual review (step 9). The placeholders below (`<group>/<context>`, `<Entity>`, `<entity>`, `<Context>`) stand for the bounded context and the aggregate of the change.

### 2. Domain errors

One `#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]` enum per aggregate or value-object family, one variant per broken invariant. The `#[error("…")]` text is the client-facing sentence; `property_path()` returns the wire name (camelCase) of the property that carries the invalid value, and `code()` returns a stable machine-readable code. Both are `const fn` over `self` with an exhaustive `match`:

```rust
/// A value that breaks an invariant of `<Entity>`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum Invalid<Entity> {
    /// The name is empty or too long.
    #[error("This value must not be empty or too long.")]
    NameLength,
}

impl Invalid<Entity> {
    /// The property that carries the invalid value.
    #[must_use]
    pub const fn property_path(self) -> &'static str {
        match self {
            Self::NameLength => "name",
        }
    }

    /// The machine-readable violation code.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::NameLength => "length",
        }
    }
}
```

A port error (for example `RepositoryError` with `AlreadyExists` and `Unavailable(#[source] BoxError)`) lives next to its port. `BoxError` appears only at port boundaries. Infrastructure translates every driver error into the error of the port it implements, so no driver type crosses a port, and wraps the driver error as `#[source]` instead of formatting it into the message.

### 3. One application error enum per context

The context's application crate owns exactly one error enum. Domain errors enter through `#[from]` with `#[error(transparent)]`; port failures enter through a constructor that boxes the source. Every command and query of the context sets `type Error = <Entity>Error;`:

```rust
/// What can go wrong in a command or a query of the `<context>` context.
#[derive(Debug, thiserror::Error)]
pub enum <Entity>Error {
    /// A value breaks an invariant.
    #[error(transparent)]
    Invalid(#[from] Invalid<Entity>),
    /// The storage failed.
    #[error("the <entity> storage is unavailable")]
    Storage(#[source] BoxError),
}
```

A second error enum in the same context, or a context that reuses another context's error enum, is a finding: merge it into the one enum, or route it through the shared crates (see [implementing-ddd-architecture](../implementing-ddd-architecture/SKILL.md)).

### 4. Propagation without panics

"Production code" is everything outside `#[test]` functions and `#[cfg(test)]` modules; the template's lint configuration relaxes the panic lints in tests only, so tests may unwrap. In production code replace each banned construct, never suppress it:

| Banned in production code | Lint that reports it | Replacement |
| --- | --- | --- |
| `.unwrap()` | `clippy::unwrap_used` | `?`, `ok_or`, `ok_or_else` with a typed variant |
| `.expect("…")` | `clippy::expect_used` | the same as `unwrap` |
| `panic!`, `todo!`, `unimplemented!`, `unreachable!` | `clippy::panic`, `clippy::todo`, `clippy::unimplemented`, `clippy::unreachable` | an error variant, or an exhaustive `match` that makes the case impossible by type |
| slice or string indexing (`items[i]`, `&text[a..b]`) | `clippy::indexing_slicing`, `clippy::string_slice` | `.get(i)`, `.first()`, iterators, `split_once`, `char_indices` |
| `value as u16` | `clippy::as_conversions` | `u16::try_from(value)?`, `From`, `TryFrom` |

Propagate with `?` on the line of the call, and keep the `?` on a line with code that runs, so coverage sees the line. A lower-level error is wrapped as `#[source]`, never discarded with a closure that ignores its argument (`clippy::map_err_ignore`) and never turned into a string.

Never define a type named `Error` (`clippy::error_impl_error`): name the enum after what failed (`Invalid<Entity>`, `RepositoryError`, `<Entity>Error`). An associated type `type Error = <Entity>Error;` in a trait impl is not a type definition and is expected.

### 5. Bus errors and the problem document

When `framework.http` is null, record `SKIPPED: framework.http is null` for this step and go to step 6; the service has no handlers to map.

When `framework.http` is `axum`:

- Handlers return `Result<_, Problem>` and use `?`. The shared `From<BusError<E>> for Problem` already maps `Handler(E)` through the application error's own conversion and `NotRegistered` to a 500 through `Problem::internal`; never re-implement it and never match on `BusError` in a handler.
- The context implements `From<<Entity>Error> for Problem` once, with one explicit arm per variant (no `_ =>` arm, `clippy::wildcard_enum_match_arm`), so a new variant forces a mapping decision:

| Situation | Problem type | Constructor |
| --- | --- | --- |
| The client sent a value that breaks an invariant | `/problems/validation-failed`, status 422, `violations[]` of `propertyPath`, `message`, `code` (sorted by property path, then code) | `Problem::validation_failed(vec![Violation { … }])` built from `property_path()`, the error text and `code()` |
| The status alone says everything (not found, conflict, unsupported media type) | `about:blank` | `Problem::new(status)`, optionally `.with_detail(…)` |
| A readiness probe found dependencies down | `/problems/dependency-unavailable`, status 500, `failures[]` of `dependency`, `message` | `Problem::dependency_unavailable(failures)` |
| Anything else that is the server's fault | `about:blank`, status 500, no detail | `Problem::internal(&error)`, which logs the error chain once at `ERROR` |

```rust
impl From<<Entity>Error> for Problem {
    fn from(error: <Entity>Error) -> Self {
        match &error {
            <Entity>Error::Invalid(invalid) => Self::validation_failed(vec![Violation {
                property_path: invalid.property_path().to_owned(),
                message: invalid.to_string(),
                code: invalid.code().to_owned(),
            }]),
            <Entity>Error::Storage(_) => Self::internal(&error),
        }
    }
}
```

No handler writes an error body by hand, and no problem detail, error message or log field carries SQL text, driver messages, file paths, stack traces or secrets. A fourth problem type is a contract change: use [api-contract-development](../api-contract-development/SKILL.md) instead of inventing one in a handler.

### 6. GraphQL error section

When `framework.graphql` is false, record `SKIPPED: framework.graphql is false` and go to step 7.

When `framework.graphql` is true, resolvers call the same command or query as the REST handler and convert every error through the problem document with the shared helper (`problem_to_error(Problem::from(error))` in the template), so REST and GraphQL report one failure the same way. The GraphQL error then carries `extensions.code`:

- `VALIDATION_FAILED` for a 422 problem: the message is the problem detail and `extensions.violations` lists `propertyPath`, `message` and `code` per violation.
- `INTERNAL_SERVER_ERROR` for every other status: a generic message with no detail; the cause was already logged once by `Problem::internal`.

An absent resource is a nullable field that resolves to `None`, not an error. Never build an `async_graphql` error with a hand-written code string in a resolver, and never return a 4xx-style code other than `VALIDATION_FAILED`.

### 7. Lint suppression policy

Never write `#[allow(…)]`. The only suppression is `#[expect(lint, reason = "…")]`:

- on the smallest item that needs it, naming exactly one lint, never a lint group;
- with a reason that states a fact about the code (for example `reason = "axum handlers must be async"`), never "false positive";
- only where the lint really fires: an unfulfilled expectation is itself a static-analysis finding, so remove an `#[expect]` whose cause is gone;
- never in a crate root: no `#![expect(…)]` in `lib.rs`, `main.rs`, `build.rs` or the root file of a test target;
- never for a complexity lint (`clippy::cognitive_complexity`, `clippy::too_many_lines`, `clippy::excessive_nesting`, `clippy::too_many_arguments`): refactor with [complexity-management](../complexity-management/SKILL.md);
- never for a panic lint or `clippy::as_conversions` in production code: step 4 has the replacement.

A module-level `#![expect(…)]` is allowed only where the repository's own rules name the case (code generated by a derive macro that no item-level attribute can reach); read them in `AGENTS.md` before adding one. Thresholds in `clippy.toml` and the lint levels of `[workspace.lints]` are protected configuration and are never changed to obtain a pass.

### 8. Run static analysis

When `make.static_analysis` is mapped, run that target as [verification-workflow](../verification-workflow/SKILL.md) prescribes (in the background, logged and polled to the end) and record its row in the targets-run list. On failure, fix each reported finding with steps 2 to 7 and run it again. A run that cannot start (no toolchain, no reachable container engine) is recorded `not run (no toolchain)` or `not run (no Docker)` and handed back to the calling stage, which escalates; it is never counted as a pass and never retried in a loop.

### 9. Manual review when the target is null

When `make.static_analysis` is null, record `not run (capability absent)` (degrade D1) and review the added lines of the diff instead, outside `#[cfg(test)]` modules and `tests.rs` files: `.unwrap()`, `.expect(`, `panic!`, `todo!`, `unimplemented!`, `unreachable!`, `[` index expressions on slices and strings, `as` conversions, `enum Error` or `struct Error`, `#[allow`, `#![expect` in a crate root. Fix every hit, then end with `SUCCESS-WITH-REPORT`; the manual review never replaces the gate in the evidence.

## Constraints

- Never write `#[allow(…)]`, never suppress a lint group, never put `#![expect(…)]` in a crate root and never suppress a complexity lint.
- Never use `unwrap`, `expect`, `panic!`, `todo!`, `unimplemented!`, `unreachable!`, indexing or `as` in production code, and never hide one behind a helper that panics.
- Never define a type named `Error`, never add a second application error enum to a context, and never match `_ =>` over an error enum.
- Never create a 5xx problem except through `Problem::internal`, never write an error body by hand and never leak driver messages, SQL, paths, stack traces or secrets into a problem or a log field.
- Never change `clippy.toml`, `[workspace.lints]` or the static-analysis recipe to obtain a pass: they are protected configuration. A finding that only such a change would clear is escalated with `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`.
- Values come from the profile keys above; the GraphQL section runs only when `framework.graphql` is true and the HTTP mapping only when `framework.http` is `axum`.
- The fix loop is bounded by the calling stage's iteration guard (5). The same finding on the same line after a fix, or the guard exhausted, ends the loop with the escalation block below; there is no further retry.

## Verification

- Targets-run row, in the FR-1 vocabulary: `<target of make.static_analysis>: passed | failed | not run (<reason>)`.
- The skipped steps, each as its own line: `SKIPPED: framework.http is null`, `SKIPPED: framework.graphql is false`.
- For each changed error enum: the file, its variants, and the problem type each variant maps to.
- Evidence for the `EXECUTE` verdict of this skill in the triage table: the targets-run row plus the list of suppressions added or removed (each with its lint and reason), or `none`.

### Escalation

When the loop ends without a pass, or a fix needs protected configuration, print the canonical block with the calling stage's id and exit string:

```text
=== SDLC ESCALATION ===
stage: <stage-id>
iteration: <n>/5
exit_condition: <exit string of the calling stage, verbatim>
status: NOT MET
blocking_finding: <file:line> <lint or rule>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human decision, for example a protected change with ALLOW_PROTECTED_CONFIG_EDIT=1>
=== END ===
```
