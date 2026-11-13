# Attack Playbooks

One entry per family of [owasp-catalog.md](owasp-catalog.md). Each entry gives the static review patterns (step 4 of [the security-audit skill](../SKILL.md)), the dynamic probes (step 5, only while the dynamic probing gate is open) and the evidence that counts as a reproduction (step 6). Fixes are in [remediation-patterns.md](remediation-patterns.md).

Placeholders: `<plugin-root>` is the resolved plugin root the caller passed; `<collection-path>`, `<item-path>` and `<graphql-path>` are routes read from the router and the committed contract snapshots; `<field>` is a field of the route's request body and `<page-size parameter>` the query parameter that sets a page size. Concrete routes and values never appear in this file.

## Probe form

Every dynamic probe is one call of the helper, and nothing else sends HTTP:

```text
"<plugin-root>/scripts/lib/common.sh" http_probe <METHOD> '<PATH>' [--header 'K: V']... [--body TEXT | --body-file F]
```

- METHOD is one of `GET`, `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`.
- PATH starts with `/` and uses only letters, digits, `._~%/?&=:,+-`. Percent-encode everything else: a single quote is `%27`, a space `%20`, a double quote `%22`.
- At most 10 headers of the form `Name: value`, printable ASCII only.
- `--body` holds at most 16 KiB. A larger or generated body is written under `target/rust-sdlc/tmp/` first and sent with `--body-file`; the helper refuses a file anywhere else.
- Output: `HTTP_STATUS: <code>`, the response headers, at most 64 KiB of body. Exit 0 for any HTTP response, 1 for a transport failure, 2 for a rejected argument.
- Tag each probe with `--header 'x-request-id: sec-<rule>-<n>'`; the service echoes the id, which proves the answer belongs to the probe.
- Write credentials in the evidence as `<token of identity A>`, never as their value.

## Injection

**Static review.** Search the changed files and the repository adapters they call:

```text
sqlx::query\(|sqlx::query_as\(|sqlx::query_scalar\(|sqlx::raw_sql\(
QueryBuilder::new|\.push\(
format!\([^)]*(SELECT|INSERT|UPDATE|DELETE|WHERE|ORDER BY|LIMIT)
std::process::Command|Command::new
Url::parse|\.get\(format!|\.post\(format!
```

- **Safe:** the macros `sqlx::query!`, `query_as!` and `query_scalar!` (checked at compile time against the offline metadata in `.sqlx/`, parameters bound as `$1`, `$2`); a string literal passed to `sqlx::query("…")` with every value added through `.bind(…)`; `QueryBuilder::push_bind`.
- **Candidate:** SQL text that is not a literal (`format!`, `+`, `push_str`, a `String` parameter) reaching `sqlx::query(`, `query_as(`, `query_scalar(` or `raw_sql(`; `QueryBuilder::push` with request data, including a sort column or direction taken from a query parameter; an outbound URL or host built from request data (A10, API7); a `Command` argument built from request data.

**Dynamic probes.** For each route whose input reaches an SQL candidate, send the input with one single quote, then with two:

```bash
"<plugin-root>/scripts/lib/common.sh" http_probe GET '/<collection-path>?<field>=x%27' --header 'x-request-id: sec-injection-1'
"<plugin-root>/scripts/lib/common.sh" http_probe GET '/<collection-path>?<field>=x%27%27' --header 'x-request-id: sec-injection-2'
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<collection-path>' --header 'content-type: application/json' --header 'x-request-id: sec-injection-3' --body '{"<field>":"x'\''"}'
```

- **Expected:** the quote is data: a 2xx answer, or a 4xx problem document, identical in kind to the answer without the quote.
- **Observed (reproduced):** a 5xx answer for one quote while the doubled quote (an escaped quote in SQL) answers like the plain input. The pair proves that the value lands inside an SQL string literal.
- The payload stays one or two quotes. Never send a statement that writes, deletes or locks, and never a time-based payload.
- Outbound-URL and process sinks are verified statically only: never send a URL, a host or a command as a probe value.

**Reproduction evidence.** The probe pair with both statuses, plus the sink's `file:line`; without the dynamic lane, the source trace from the extractor field to the non-literal SQL with `file:line` at every hop.

## BOLA and IDOR

**Static review.**

- Find every route with a `Path` extractor (or the repository's validated path extractor) that carries an object id, and every GraphQL field or mutation that takes an id argument.
- Follow the id through the application service to the repository query. Candidate: the query filters by id only, with no owner, tenant or role condition, and no authorization check precedes it.
- Candidate (`Low`): an object of another owner is answered 403 while an absent object is answered 404, which reveals that the id exists.
- Candidate: the caller's identity is read from a client-controlled header or body field instead of a verified credential.

**Dynamic probes.** Use two identities only when the specs or the repository's test setup provide test credentials; never use real credentials.

```bash
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<collection-path>' --header 'content-type: application/json' --header 'authorization: Bearer <token of identity A>' --header 'x-request-id: sec-bola-idor-1' --body '{"<field>":"sec-audit"}'
"<plugin-root>/scripts/lib/common.sh" http_probe GET '/<item-path with the id from the first answer>' --header 'authorization: Bearer <token of identity B>' --header 'x-request-id: sec-bola-idor-2'
"<plugin-root>/scripts/lib/common.sh" http_probe DELETE '/<item-path with the id from the first answer>' --header 'authorization: Bearer <token of identity B>' --header 'x-request-id: sec-bola-idor-3'
```

- **Expected:** 404 for identity B (403 only when the specs say so), and the object unchanged when identity A reads it again.
- **Observed (reproduced):** identity B reads, changes or deletes identity A's object.
- When the service has no authentication at all and the specs scope objects to an owner, the second call is sent without any credential; a 2xx answer reproduces the finding.

**Reproduction evidence.** The three calls with statuses (credentials as placeholders) and the repository query's `file:line`.

## Mass assignment

**Static review.**

- Every type deserialized from a request body (`Json<…>` or the repository's validated JSON extractor) or used as a GraphQL `InputObject`.
- Candidate: a request DTO without `#[serde(deny_unknown_fields)]`.
- Candidate: a request DTO that is the domain entity itself, or that carries a server-owned field: id, owner or tenant, role or permission, status, version, creation or update time.
- Candidate: `#[serde(flatten)]` on a request DTO; serde does not apply `deny_unknown_fields` across a flattened field, so unknown fields are accepted silently.
- Candidate: `#[serde(default)]` on a field that grants a privilege.
- GraphQL input objects reject unknown fields by the GraphQL specification, so for GraphQL only the server-owned-field candidate applies.

**Dynamic probes.** A valid create body plus one unknown field, then plus one server-owned field:

```bash
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<collection-path>' --header 'content-type: application/json' --header 'x-request-id: sec-mass-assignment-1' --body '{"<field>":"sec-audit","unexpectedField":true}'
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<collection-path>' --header 'content-type: application/json' --header 'x-request-id: sec-mass-assignment-2' --body '{"<field>":"sec-audit","id":"00000000-0000-0000-0000-000000000001"}'
```

- **Expected:** a 4xx `application/problem+json` answer for both bodies.
- **Observed (reproduced):** a 2xx answer for the unknown field, or a 2xx answer for the server-owned field after which a read of the created object shows the client-chosen value.

**Reproduction evidence.** The calls with statuses, the follow-up read for a server-owned field, and the DTO's `file:line`.

## DoS

**Static review.**

- **Body limit:** the router applies `DefaultBodyLimit::max(…)` or tower-http's `RequestBodyLimitLayer`. Candidate: `DefaultBodyLimit::disable()`, a route outside the limited router, or a handler that reads the raw body with a limit of `usize::MAX`.
- **Timeouts:** a request-timeout middleware or `TimeoutLayer` wraps every route; outbound calls, pool acquisition and long SQL have their own timeouts. Candidate: a route outside the timeout layer, or an awaited outbound call without a timeout.
- **GraphQL depth and complexity:** the schema builder calls `limit_depth(…)` and `limit_complexity(…)`, and `limit_recursive_depth(…)` when inputs are recursive. Candidate: either limit missing while a GraphQL route is served; a handler that accepts batched requests without a cap on the batch size.
- **Page size:** every list route validates an upper bound on its page-size parameter. Candidate: an unbounded page size or an unpaginated list of a growing collection.
- **Allocations:** `Vec::with_capacity(…)`, `vec![…; n]` or `.repeat(n)` sized by request data; `Regex::new(…)` on request data (CWE-1333).

**Dynamic probes.**

Body limit: one byte above the limit that the repository's `docs/environment.md` documents for the body-limit setting.

```bash
mkdir -p target/rust-sdlc/tmp
head -c "$((BODY_LIMIT_BYTES + 1))" /dev/zero | tr '\0' 'a' > target/rust-sdlc/tmp/sec-dos-body.txt
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<collection-path>' --header 'content-type: application/json' --header 'x-request-id: sec-dos-1' --body-file target/rust-sdlc/tmp/sec-dos-body.txt
```

`BODY_LIMIT_BYTES` is the documented limit, set in the same shell call. Expected: 413. Observed (reproduced): any other status once the whole body was accepted.

Page size: `GET '/<collection-path>?<page-size parameter>=1000000'`. Expected: a 4xx problem, or a page no larger than the documented maximum. Observed (reproduced): a larger page.

GraphQL depth: a query nested deeper than the configured `limit_depth` (nest more `ofType` levels when the limit is above this example's depth of 19):

```bash
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<graphql-path>' --header 'content-type: application/json' --header 'x-request-id: sec-dos-2' --body '{"query":"{ __schema { types { fields { type { ofType { ofType { ofType { ofType { ofType { ofType { ofType { ofType { ofType { ofType { ofType { ofType { ofType { ofType { name } } } } } } } } } } } } } } } } } } }"}'
```

GraphQL complexity: 500 aliases of one field in one query.

```bash
{ printf '{"query":"{'; for i in $(seq 1 500); do printf ' a%d: __typename' "$i"; done; printf ' }"}'; } > target/rust-sdlc/tmp/sec-dos-complexity.json
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<graphql-path>' --header 'content-type: application/json' --header 'x-request-id: sec-dos-3' --body-file target/rust-sdlc/tmp/sec-dos-complexity.json
```

- **Expected (both GraphQL probes):** an answer with an `errors` entry that rejects the query's depth or complexity, and no `data`.
- **Observed (reproduced):** `data` is returned.
- When introspection is disabled and the schema has no recursive type, depth is bounded by construction: record the depth probe as not applicable with that reason.
- Timeouts are verified statically only; the skill never makes a dependency slow.

**Reproduction evidence.** The call, the status and the relevant body excerpt, plus the `file:line` of the router layer or schema builder that lacks the limit.

## Information disclosure

**Static review.**

- **Problem details:** a problem document whose detail is built from `to_string()` or `format!("{:?}", …)` of an infrastructure error (sqlx, IO, an SDK client); `Json(error.to_string())`; a 5xx answer that does not go through the generic internal problem, which logs the error chain and returns no detail; a panic message that reaches a response.
- **Logs:** a `tracing` macro field that holds a request or response body, a header other than `x-request-id`, a credential, a token, a connection string or personal data; `#[instrument]` without `skip_all` on a function that takes such a value (every argument is recorded with its `Debug` output); `#[derive(Debug)]` on a configuration or credential type that is logged; `println!`, `eprintln!` or `dbg!` in service code.
- **Responses and routes:** a response DTO that serializes internal fields; a development-only route (GraphQL explorer, debug endpoint) served in every environment; a `server` or `x-powered-by` header with a version.

**Dynamic probes.** Trigger each error class once and inspect the answer:

```bash
"<plugin-root>/scripts/lib/common.sh" http_probe GET '/sec-audit-unknown-route' --header 'x-request-id: sec-information-disclosure-1'
"<plugin-root>/scripts/lib/common.sh" http_probe DELETE '/<route that allows only GET>' --header 'x-request-id: sec-information-disclosure-2'
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<collection-path>' --header 'content-type: application/json' --header 'x-request-id: sec-information-disclosure-3' --body '{'
"<plugin-root>/scripts/lib/common.sh" http_probe POST '/<collection-path>' --header 'content-type: application/json' --header 'x-request-id: sec-information-disclosure-4' --body '{"<field>":12345}'
"<plugin-root>/scripts/lib/common.sh" http_probe GET '/<item-path with a random id>' --header 'x-request-id: sec-information-disclosure-5'
```

- **Expected:** every answer is `application/problem+json`, echoes the sent `x-request-id`, and its body holds no SQL text, file path, crate or type name, `panicked at`, stack frame or configuration value; no header reveals a version.
- **Observed (reproduced):** any of these appears.
- The log side has no dynamic probe here: the security lens does not read service logs. A log leak is reproduced statically by the trace from the sensitive value to the log macro, with `file:line` at every hop.

**Reproduction evidence.** The call, the status, the content type and the leaking excerpt (a secret in it replaced by `<redacted>`), plus the `file:line` that builds the leaking text.

## Secrets

**Static review.** Run these patterns over the changed files and over committed configuration (`*.rs` string literals and clap `default_value`s, committed `.env*` files, `docker-compose*.yml`, the `Dockerfile`'s `ENV` and `ARG`, `.github/workflows/*.yml`, `*.toml`):

```text
AKIA[0-9A-Z]{16}
-----BEGIN [A-Z ]*PRIVATE KEY-----
gh[pousr]_[A-Za-z0-9]{36,}
eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.
(password|passwd|secret|token|api_?key)[[:space:]]*[:=][[:space:]]*["'][^"'$<{]{8,}
://[^/:@[:space:]]+:[^/@[:space:]]+@
```

- A value that works only against the local compose stack and is documented as a local default is not a finding.
- A credential for any shared or production system is `Critical`, wherever it appears, including the git history.
- There is no dynamic probe.

**Reproduction evidence.** The secret-scan lane's rule, file and line, or the pattern and `file:line` of the match. The value itself is never printed, copied or published. A leaked credential is revoked and rotated by a human; this skill never rewrites history.

## Dependency advisories

**Static review.**

- `Cargo.toml` changes: a new dependency, a `git =` or `registry =` source, a wildcard requirement.
- `Cargo.lock` changes: the versions the new requirements resolved to.
- The `Dockerfile`: every `FROM` pinned by digest.
- When the dependency-policy lane is null, record in the families table that the advisory database was not consulted; manual candidates are promoted only with their `file:line` demonstration.

**Reproduction evidence.**

- Dependency policy: the `error[` line with the advisory id, the crate and the version; `cargo tree -i <crate>` shows which workspace crate pulls it. `file` is `Cargo.lock`, `line` the line of the crate's `name =` entry.
- Production image: the package, the installed version and the fixed version from the image lane's log. `file` is the `Dockerfile`, `line` the `FROM` line of the stage that ships the package.
- Severity comes from the band table of [owasp-catalog.md](owasp-catalog.md); quote the advisory's CVSS score in the evidence when it has one. An advisory without a patched version says `no fixed version` in its summary.

## Memory safety

**Static review.** Only when the triage made the family `PROBE`:

```text
unsafe[[:space:]]*\{|unsafe fn|unsafe impl|extern "C"|#\[no_mangle\]
```

- The missing workspace lint without any `unsafe` code is an `Info` finding on the root `Cargo.toml` (or on the member manifest that lacks `workspace = true` under `[lints]`).
- An `unsafe` block is a candidate when request data can reach it; record the invariant the block relies on and the `// SAFETY:` comment, or its absence.

**Reproduction evidence.** Static only: the trace from the request data to the `unsafe` block with `file:line` at every hop. A block that request data cannot reach is `dropped`, and the lint finding stays `Info`.
