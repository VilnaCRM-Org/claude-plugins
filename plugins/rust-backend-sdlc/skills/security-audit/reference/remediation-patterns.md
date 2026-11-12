# Remediation Patterns

The root-cause fix and the regression test for each family of [owasp-catalog.md](owasp-catalog.md). The security lens cites the section of a finding's family in its evidence list; the implementer that the calling stage dispatches applies it. The audit itself never edits code ([the security-audit skill](../SKILL.md), Constraints).

Examples use `<group>/<context>` for a bounded context, `<Entity>` for an aggregate and `<entities>` for its table; they show the shape of the fix, not code to paste.

## Policy

- **Root cause only.** The vulnerable code path changes so that the reproduction no longer succeeds. A finding is never closed by hiding it.
- **Forbidden remediations.** Never an `#[allow(...)]` attribute, never a `.trivyignore` or `.gitleaksignore` entry, never an advisory exception in `deny.toml`, never a lowered bar, never a coverage or mutation exclusion. Each of them turns the lane green while the defect stays.
- **Protected files.** When the only fix is a change to a file listed by `cargo xtask config-guard --list` (for example an advisory with no patched version, where the sole option is a time-boxed exception), the finding goes to a human as a protected change: the approved-config-change label and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1. The implementer never makes that change on its own.
- **Regression test per fix.** Each fix adds a test that fails before the fix and passes after it, at the lowest level that reproduces the exploit (see [Regression tests](#regression-tests)).
- **Re-verification.** On the next review iteration the security lens repeats the finding's reproduction; only a failed reproduction sets the finding to `fixed`.

## Injection

- Use the checked macros: `sqlx::query!`, `query_as!` and `query_scalar!`, with every value as a bound parameter. After a query change, regenerate the offline metadata in `.sqlx/` as the [database-migrations](../../database-migrations/SKILL.md) skill prescribes.
- A query that must be assembled at runtime uses `QueryBuilder` with `push_bind` for every value. Identifiers (sort column, direction) come from an enum that maps each variant to a static string; request text never becomes SQL text.
- An outbound URL is built from configuration plus an allow-listed path; request data is only ever a percent-encoded query value. A process argument is passed as a separate argument from an allow-list, never through a shell.

```rust
// Before: the filter value becomes SQL text.
let sql = format!("SELECT id, name FROM <entities> WHERE name = '{}'", filter.name);
let rows = sqlx::query(&sql).fetch_all(&self.pool).await?;

// After: a checked macro with a bound parameter.
let rows = sqlx::query_as!(
    <Entity>Row,
    "SELECT id, name FROM <entities> WHERE name = $1",
    filter.name,
)
.fetch_all(&self.pool)
.await?;
```

```rust
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SortColumn {
    Name,
    CreatedAt,
}

impl SortColumn {
    const fn as_sql(self) -> &'static str {
        match self {
            Self::Name => "name",
            Self::CreatedAt => "created_at",
        }
    }
}

let mut builder = QueryBuilder::new("SELECT id, name FROM <entities> WHERE owner_id = ");
builder.push_bind(owner_id);
builder.push(" ORDER BY ").push(sort.as_sql());
```

**Regression test:** a repository integration test that stores a row whose name contains a single quote and reads it back through the filter, plus the HTTP-level test that the quoted input answers like the plain input.

## BOLA and IDOR

- Scope every lookup, update and delete by the caller's identity or tenant inside the query itself, so that "absent" and "not yours" are the same result.
- The application service receives the caller's identity from a verified credential (an extractor that validates it), never from a client-chosen header or body field, and passes it to the repository port.
- Answer an object of another owner exactly like an absent one (404), unless the specs require 403.

```rust
let row = sqlx::query_as!(
    <Entity>Row,
    "SELECT id, name FROM <entities> WHERE id = $1 AND owner_id = $2",
    id.as_uuid(),
    owner.as_uuid(),
)
.fetch_optional(&self.pool)
.await?;
```

**Regression test:** two identities; identity B's read, update and delete of identity A's object answer 404, and identity A's object is unchanged afterwards.

## Mass assignment

- Every request DTO carries `#[serde(deny_unknown_fields)]` and lists only the fields a client may set; server-owned fields (id, owner, role, status, version, timestamps) are set by the application service.
- Request DTOs are separate types from domain entities and response DTOs; the application service builds the entity from validated input.
- No `#[serde(flatten)]` on a request DTO, because it disables the unknown-field check; repeat the fields instead.
- Validate with the repository's validated JSON extractor, so constraint violations answer the validation problem.

```rust
#[derive(Debug, Clone, Deserialize, ToSchema, Validate)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Create<Entity>Request {
    #[validate(length(min = 1, max = 255))]
    pub name: String,
}
```

**Regression test:** a body with an unknown field and a body with a server-owned field each answer a 4xx problem, and no object is created.

## DoS

- Keep one body limit on the whole router, `DefaultBodyLimit::max(<configured bytes>)`, with the value from the service configuration; never disable it per route. A handler that must read a raw body reads it with that limit, never with `usize::MAX`.
- Keep the request-timeout middleware on every route; give outbound calls and pool acquisition their own timeouts from configuration (`tokio::time::timeout` around a call that has none).
- Build the GraphQL schema with both limits, values from configuration:

```rust
let schema = Schema::build(Query::default(), Mutation::default(), EmptySubscription)
    .limit_depth(config.graphql_max_depth)
    .limit_complexity(config.graphql_max_complexity)
    .finish();
```

- Cap page sizes with a validated upper bound on the query DTO, and paginate every list of a growing collection.
- Size allocations by a validated bound, never by raw request data; compile regular expressions from static patterns only.
- A new configuration value gets its row in the repository's environment documentation, as the [configuration-management](../../configuration-management/SKILL.md) skill prescribes.

**Regression test:** an oversized body answers 413; a query deeper than the depth limit and one above the complexity limit answer a GraphQL error without `data`; an oversized page-size answers a 4xx problem.

## Information disclosure

- Route every 5xx through the generic internal problem, which logs the error chain at `ERROR` and returns no detail; map domain and application errors to 4xx problems with fixed detail texts, as the [rust-error-handling](../../rust-error-handling/SKILL.md) skill prescribes.
- Never build a response text from `to_string()` or `Debug` output of an infrastructure error.

```rust
// Before: the database error text reaches the client.
Err(error) => Problem::new(StatusCode::INTERNAL_SERVER_ERROR).with_detail(error.to_string()),

// After: the chain goes to the log, the client gets the generic problem.
Err(error) => Problem::internal(&error),
```

- Instrument with `#[tracing::instrument(skip_all, fields(...))]` and record only ids and counts, as the [observability-instrumentation](../../observability-instrumentation/SKILL.md) skill prescribes.
- Give a type that holds a credential a hand-written `Debug` that redacts it, instead of deriving one:

```rust
pub struct DatabaseCredentials {
    url: String,
}

impl fmt::Debug for DatabaseCredentials {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DatabaseCredentials")
            .field("url", &"<redacted>")
            .finish_non_exhaustive()
    }
}
```

- Serve development-only routes only in the development environment, and remove version headers.

**Regression test:** a test that forces the infrastructure error and asserts the 500 problem has no detail, and a log-capture test that asserts the sensitive value is absent from every recorded field.

## Secrets

- A committed credential for a shared or production system is revoked and rotated first, by a human; removing it from the history follows. Deleting the line alone is not a fix.
- The value moves to the environment, read through the composition root's configuration, as the [configuration-management](../../configuration-management/SKILL.md) skill prescribes; committed files keep only local-stack defaults.
- Never answer a real secret with a `.gitleaksignore` fingerprint.

**Regression test:** the secret-scan lane passes on the branch; for a configuration change, the configuration test that the value is read from the environment and absent from the defaults.

## Dependency advisories

- Bump the requirement in `[workspace.dependencies]` of the root `Cargo.toml` to the first patched release, or replace the crate; `cargo tree -i <crate>` shows which workspace crate pulls a transitive one, and that crate's requirement is bumped instead. The [dependency-policy](../../dependency-policy/SKILL.md) skill covers the cargo-deny lanes and the layer allow-lists.
- An image vulnerability is fixed by moving the affected `FROM` to a patched base image digest, or by removing the package from the shipping stage.
- An advisory with no patched version, or a vulnerable package with no fixed image, goes to a human as a protected change (see [Policy](#policy)); never an exception added by the implementer.

**Regression test:** the dependency-policy lane and the image lane pass with no `error[` line and no HIGH or CRITICAL vulnerability.

## Memory safety

- Keep `unsafe_code = "forbid"` in `[workspace.lints.rust]` and `workspace = true` under `[lints]` in every member manifest; a member without it gets the table added.
- Replace an `unsafe` block with a safe API of the standard library or of an allowed crate; an FFI need goes to a human design decision.

**Regression test:** the workspace build passes with the lint inherited by every member.

## Regression tests

Place each test where it reproduces the exploit most directly, as the [testing-workflow](../../testing-workflow/SKILL.md) skill describes:

| Family | Test level |
| --- | --- |
| `injection` | repository integration test with the hostile value, plus an HTTP-level test |
| `bola-idor` | HTTP-level or end-to-end test with two identities |
| `mass-assignment` | unit test of the DTO's deserialization, plus an HTTP-level test |
| `dos` | router or schema unit test for each limit |
| `information-disclosure` | problem-mapping unit test, plus a log-capture test |
| `secrets` | the secret-scan lane, plus a configuration test |
| `dependency-advisories` | the dependency-policy and image lanes |
| `memory-safety` | the workspace build with the inherited lint |
