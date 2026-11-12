# OWASP Catalog for Rust Services

This file is the single source of the triage in step 2 of [the security-audit skill](../SKILL.md). It defines the eight families whose kebab ids are the only values of the ledger field `rule` for the security lens, maps every category of the OWASP Top 10 and the OWASP API Security Top 10 onto one of them, and fixes the severity bands. The probes live in [attack-playbooks.md](attack-playbooks.md) and the fixes in [remediation-patterns.md](remediation-patterns.md).

Editions used: OWASP Top 10 2021, OWASP API Security Top 10 2023, CWE Top 25 2024. A newer edition changes only the mapping tables below; the eight families and their ids stay fixed, because the review ledger validates `rule` against them.

## Families

| `rule` | Family | OWASP | CWE | PROBE when | N/A only when |
| --- | --- | --- | --- | --- | --- |
| `injection` | Injection: SQL built from request data, outbound URLs and process arguments built from request data | A03:2021, A10:2021, API7:2023, API10:2023 | CWE-89, CWE-918, CWE-78, CWE-20 | the service runs SQL, calls another system or starts a process | the service has no persistence, makes no outbound call and starts no process |
| `bola-idor` | Broken object and function level authorization | A01:2021, API1:2023, API5:2023, A07:2021, API2:2023 | CWE-639, CWE-284, CWE-285, CWE-862 | any route reads, changes or deletes an object by id or a path segment | the specs state that every object is public and no route is restricted to a role |
| `mass-assignment` | Broken object property level authorization | API3:2023, A08:2021 | CWE-915 | any route deserializes a request body or GraphQL input | no route accepts a body or an input object |
| `dos` | Unrestricted resource consumption | API4:2023, API6:2023 | CWE-770, CWE-400, CWE-1333 | the service accepts HTTP requests | never N/A for an HTTP service |
| `information-disclosure` | Error and log disclosure, security misconfiguration | A05:2021, A09:2021, API8:2023, API9:2023 | CWE-209, CWE-532, CWE-200, CWE-215 | the service returns errors or writes logs | never N/A |
| `secrets` | Secrets in code and configuration | A02:2021, A07:2021 | CWE-798, CWE-312, CWE-522 | always | never N/A |
| `dependency-advisories` | Vulnerable and outdated components, untrusted sources | A06:2021, A08:2021 | CWE-1104, CWE-1395, CWE-494 | always | never N/A |
| `memory-safety` | Out-of-bounds access, use after free, data races through `unsafe` | — | CWE-119, CWE-416, CWE-787, CWE-125, CWE-362 | `unsafe_code` is not `forbid` in `[workspace.lints.rust]`, or a member does not inherit the workspace lints | recorded N/A under `unsafe_code = "forbid"` for every workspace member |

Notes on the N/A column:

- A family is N/A only when its condition holds for the whole service. A diff that does not touch a family's code is no reason for N/A: the family is `PROBE`, and the source review starts from the code the diff calls.
- `memory-safety` is N/A by construction while the workspace forbids `unsafe_code`: `forbid` cannot be lowered by an inner attribute, so no workspace crate can contain an `unsafe` block. Memory safety of third-party crates is covered by `dependency-advisories` (RUSTSEC lists unsoundness advisories).
- `bola-idor` with no authentication layer: when no extractor yields a caller identity, the family is still `PROBE` unless the specs declare every object public. An unauthenticated route that changes an object the specs scope to an owner is a finding of this family.

## OWASP Top 10 2021 mapping

| Category | Family | Rust-specific note |
| --- | --- | --- |
| A01 Broken Access Control | `bola-idor` | object scoping in queries and in application services, not only in handlers |
| A02 Cryptographic Failures | `secrets` | hard-coded keys, plain-text credentials in configuration; TLS is set up by the client libraries (rustls) |
| A03 Injection | `injection` | `sqlx::query(` with a formatted string, `QueryBuilder::push` with request data, `std::process::Command` arguments |
| A04 Insecure Design | the family of the missing control | recorded under the family whose control is absent (for example a missing page-size cap under `dos`) |
| A05 Security Misconfiguration | `information-disclosure` | development-only routes served in production, debug detail in problem documents, missing security headers |
| A06 Vulnerable and Outdated Components | `dependency-advisories` | RUSTSEC advisories in `Cargo.lock`, vulnerable packages in the production image |
| A07 Identification and Authentication Failures | `bola-idor`, `secrets` | identity checks under `bola-idor`, weak or committed credentials under `secrets` |
| A08 Software and Data Integrity Failures | `dependency-advisories`, `mass-assignment` | git or unknown registry sources under `dependency-advisories`; serde deserializes data only, so there is no object injection, and an over-wide DTO is `mass-assignment` |
| A09 Security Logging and Monitoring Failures | `information-disclosure` | secrets or personal data in log fields; missing instrumentation belongs to the observability-instrumentation skill |
| A10 Server-Side Request Forgery | `injection` | an outbound URL or host built from request data |

## OWASP API Security Top 10 2023 mapping

| Category | Family | Rust-specific note |
| --- | --- | --- |
| API1 Broken Object Level Authorization | `bola-idor` | `Path` extractors whose id reaches a repository lookup without an owner or tenant condition |
| API2 Broken Authentication | `bola-idor` | identity extraction that trusts a client-supplied header or skips verification |
| API3 Broken Object Property Level Authorization | `mass-assignment`, `information-disclosure` | over-wide request DTOs under `mass-assignment`; response DTOs that expose internal fields under `information-disclosure` |
| API4 Unrestricted Resource Consumption | `dos` | body limit, request timeout, GraphQL depth and complexity, page-size caps |
| API5 Broken Function Level Authorization | `bola-idor` | a mutation or administrative route reachable without the required role |
| API6 Unrestricted Access to Sensitive Business Flows | `dos` | only when the specs require a per-caller limit inside the service; rate limiting at the edge is out of scope |
| API7 Server Side Request Forgery | `injection` | as A10 |
| API8 Security Misconfiguration | `information-disclosure` | as A05 |
| API9 Improper Inventory Management | `information-disclosure` | a route that is served but missing from the committed contract snapshot, or a development route served in production |
| API10 Unsafe Consumption of APIs | `injection` | data from an upstream system used in SQL, URLs or process arguments without validation |

## Out of scope, recorded with a reason

- **OWASP Mobile Top 10:** the plugin audits server-side services; record nothing.
- **OWASP LLM Top 10:** the template integrates no model; a service that adds a model call records prompt-built SQL, URLs or commands under `injection`.
- **Memory-safety CWEs of workspace code:** covered by the `memory-safety` row and N/A while `unsafe_code = "forbid"` holds.

## Severity bands

Each finding takes exactly one band from the ledger enum. Choose the highest band whose condition the reproduction proves, and state the reason in the evidence list.

| Band | Condition | Rust service examples |
| --- | --- | --- |
| `Critical` | remote compromise of data or credentials with no precondition | SQL injection that reads other tables; a committed credential for a non-local system |
| `High` | access to or change of another owner's data, or code or query execution with a precondition | BOLA read or write; SQL injection behind a role; an advisory with a known exploit in a reachable code path |
| `Medium` | integrity or availability impact limited to the caller's own scope, or resource exhaustion | mass assignment of a server-owned field; a missing body limit or GraphQL depth limit with a reproduced slow or oversized response; an advisory in a reachable path without a known exploit |
| `Low` | disclosure of internal detail without data or credentials | an error chain, SQL text or file path in a problem document; a version header |
| `Info` | hardening note with no reproduced impact | a defence-in-depth layer that is missing although the reproduction failed |

## Triage table format

Step 2 prints one row per family, in the order of the Families table:

```text
| family | rule | verdict | reason or evidence |
| --- | --- | --- | --- |
| Memory safety | memory-safety | N/A | unsafe_code = "forbid" holds for every workspace member |
```
