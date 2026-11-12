---
name: security-audit
description: Use when the security lens of /rs-sdlc-review, or a standalone audit of a service the user owns, must check a Rust service for the attack families injection, BOLA/IDOR, mass assignment, DoS, information disclosure, secrets and dependency advisories, and verify every candidate by reproduction through the dependency-policy, secret-scan and image-scan lanes, a source review per family and loopback-only HTTP probes sent through common.sh http_probe. Skip, inside a review, when the diff since the merge base touches no Rust source, `Cargo.toml`, `Cargo.lock`, `migrations/`, `.sqlx/`, `deny.toml`, `Dockerfile` or CI workflow; skip only the dynamic probes when `capabilities.dynamic_security_testing` is false (the static lanes still run). Not for changing dependency allow-lists or licence policy (use dependency-policy), not for designing the error-to-problem model (use rust-error-handling), not for adding spans and log fields (use observability-instrumentation).
---

# Security Audit

## Profile keys consumed

- `capabilities.dynamic_security_testing` — true: the dynamic lane probes the running service; false: the dynamic lane is skipped and only the static lanes and the source review run
- `make.check_security` — the dependency-policy lane (advisories, licences, bans, sources); null: the built-in static review lane runs instead, with a degrade note
- `make.secrets_scan` — the secret-scan lane over the git history and the working files (needs Docker); null: the lane is not run and the secrets family rests on the source review
- `make.image_scan` — the production-image lane for HIGH and CRITICAL vulnerabilities (needs Docker); null: the lane is not run
- `quality.max_dependency_policy_findings` — the ceiling, 0, for error lines of the dependency-policy lane
- `quality.max_image_vulnerabilities_high_critical` — the ceiling, 0, for HIGH and CRITICAL vulnerabilities of the production image
- `service.base_url` — the only base URL a dynamic probe reaches (loopback, validated with the profile)

## Dynamic probing gate

Read `capabilities.dynamic_security_testing` before step 5.

- **False:** print the line below, record the dynamic lane as `not run (capability absent)` and skip step 5 entirely. Steps 1–4, 6 and 7 still run, and every finding rests on a static reproduction (step 6).

  ```text
  SKIPPED: capabilities.dynamic_security_testing is false
  ```

- **True:** step 5 runs, and every request goes through `common.sh http_probe` and nothing else. The helper builds the URL from the profile's validated `service.base_url` plus the path it is given, so a probe can only reach the loopback service. Never call `curl` directly, never pass a second URL or another host, and never send a probe the helper rejected by any other route.
- **True, but nothing answers:** the skill never starts the service. When the first probe exits 1 (transport failure), print `DEGRADED: dynamic probes: no service answers at service.base_url (http_probe exit 1)`, record the dynamic lane as `not run (capability absent)`, skip the rest of step 5 and continue with step 6. The probe is not retried.

## Context

This skill is the security lens's playbook for a Rust service built on the template stack (axum, sqlx on PostgreSQL, async-graphql, `tracing`, `tracing-subscriber`). `/rs-sdlc-review` records an `EXECUTE` verdict for it when the diff since the merge base touches `*.rs`, `Cargo.toml`, `Cargo.lock`, `migrations/`, `.sqlx/`, `deny.toml`, `Dockerfile` or `.github/workflows/`, and the security lens then follows it. It also serves a standalone audit of a service the user owns.

The caller passes the diff since the merge base, the profile `.claude/rust-sdlc.yml` and the resolved plugin root. On a later review iteration it also passes the previous security ledger. The plugin root is written `<plugin-root>` below.

Three rules shape every step:

- **Verification by reproduction.** A grep hit, a tool line or a suspicious handler is a candidate. It becomes a finding only when it is reproduced: by a dynamic probe against the running service, or, for a class that has no HTTP surface, by a deterministic static demonstration (step 6). A candidate that cannot be reproduced is recorded `dropped` and never reported as `open`.
- **Read-only.** The skill changes no repository file. The only file it may create is a probe body under `target/rust-sdlc/tmp/`. Fixes are made by the implementer that the calling stage dispatches, following [reference/remediation-patterns.md](reference/remediation-patterns.md).
- **Loopback only.** Dynamic probes reach only `service.base_url`, only through the service's own API, with the smallest payload that proves the defect, and only against data the probe itself created.

Supporting files, loaded only when this skill runs:

- [reference/owasp-catalog.md](reference/owasp-catalog.md): the eight families, their OWASP and CWE ids, the triage rules and the severity bands.
- [reference/attack-playbooks.md](reference/attack-playbooks.md): the static review patterns, the probes and the reproduction evidence of each family.
- [reference/remediation-patterns.md](reference/remediation-patterns.md): the root-cause fix and the regression test of each family.

## Task

For one review iteration, or one standalone run, audit the change and the running service for the eight families below, record a verdict for each family and a result for each lane, promote only reproduced candidates, and print the report of step 7.

| Family (ledger `rule`) | What is checked |
| --- | --- |
| Injection (`injection`) | sqlx `query!` macros versus string-built SQL: `sqlx::query(`, `query_as(`, `query_scalar(`, `raw_sql(` or `QueryBuilder::push` fed with request data; outbound URLs and process arguments built from request data |
| BOLA/IDOR (`bola-idor`) | every route that reads, changes or deletes an object by id scopes the lookup to the caller's identity or tenant, and answers an object of another owner like an absent one |
| Mass assignment (`mass-assignment`) | request DTOs carry `#[serde(deny_unknown_fields)]`, stay separate from domain entities and never expose server-owned fields (id, owner, role, status, timestamps) |
| DoS (`dos`) | body limit, timeouts, GraphQL depth and complexity, page-size caps, and allocations sized by request data |
| Information disclosure (`information-disclosure`) | problem details (an error response carries no error chain, SQL, path, panic text or configuration value) and logs (no secret, credential, body or personal data in a log field) |
| Secrets in code and configuration (`secrets`) | credentials, tokens and private keys in source, manifests, compose files, the `Dockerfile`, CI workflows and committed environment files, and in the git history |
| Dependency advisories (`dependency-advisories`) | RUSTSEC advisories, yanked crates and disallowed sources in `Cargo.lock`, and HIGH or CRITICAL vulnerabilities in the production image |
| Memory safety (`memory-safety`) | recorded N/A under `unsafe_code = "forbid"` in `[workspace.lints.rust]`, inherited by every member; probed only when that lint or its inheritance is missing |

## Success criteria

- The families table has exactly the eight rows above, each `PROBE` or `N/A` with a reason taken from [reference/owasp-catalog.md](reference/owasp-catalog.md); no family is silently skipped.
- The lanes table has the four rows of step 7, each `passed`, `failed` or `not run (<reason>)`, with the reason from the closed set `capability absent`, `no Docker`.
- The dependency-policy lane is `passed` only when the target mapped by `make.check_security` exits 0 and its log has no more lines starting with `error[` than `quality.max_dependency_policy_findings` (0).
- The image lane is `passed` only when the target mapped by `make.image_scan` exits 0: it fails on any HIGH or CRITICAL vulnerability, which is the bar `quality.max_image_vulnerabilities_high_critical` (0).
- Every `open` finding has a reproduction recorded in the evidence list; every candidate without one is `dropped`.
- Every finding has exactly the ledger fields `id` (`SEC-<n>`), `severity`, `file`, `line`, `rule` (one of the eight family ids), `summary` and `status`.
- The report ends with `## Verdict: PASS` or `## Verdict: FAIL` and, after it, one fenced `json` block holding the findings array.

## Steps

One pass per call. Each lane runs at most once per pass and no step retries in a loop; the calling stage owns the iteration guard (`MAX_ITERATIONS=5`) and the escalation block.

### 1. Resolve the inputs

1. Read the seven keys above from `.claude/rust-sdlc.yml`.
2. List the changed paths with `git diff --name-only <merge-base>...HEAD`, using the merge base the caller passed. A standalone audit has no merge base and treats every tracked file as changed.
3. When the caller passed a previous ledger, keep its `open` findings for re-verification in step 6.

### 2. Triage the families

Record `PROBE` or `N/A` with a reason for each of the eight families, using the triage rules of [reference/owasp-catalog.md](reference/owasp-catalog.md). Two checks decide the families that are N/A by construction:

- **Memory safety.** Read `[workspace.lints.rust]` in the root `Cargo.toml` and the `[lints]` table of every member manifest. When the root sets `unsafe_code = "forbid"` and every member has `workspace = true` under `[lints]`, record `memory-safety` as `N/A (unsafe_code = "forbid" holds for every workspace member)`. Otherwise record it `PROBE` and list every `unsafe` block, `unsafe fn` and `unsafe impl` of the affected crates.
- **Families without a surface.** A family is N/A only when the catalog's N/A condition holds for the whole service, never because the diff happens to miss it.

### 3. Run the static lanes

Both bars are 0: a single advisory error line or a single HIGH or CRITICAL image vulnerability fails its lane. Run each mapped target once, in this order, as the [verification-workflow](../verification-workflow/SKILL.md) skill prescribes (in the background, log under `target/rust-sdlc/logs/`, waited for with `common.sh wait_log`). Each call is `make <target>` with no option and no variable.

```bash # profile-example
make check-security
make secrets-scan
make image-scan
```

1. **Dependency policy (`make.check_security`).** Count the lines of the log that start with `error[`. Within `quality.max_dependency_policy_findings` and exit 0: `passed`. More lines: `failed`, and each line is a `dependency-advisories` candidate whose reproduction is the line itself (advisory id, crate, version). A non-zero exit with no `error[` line means the tool did not run: `failed`, with the log tail as evidence, never `passed`. When the key is null, print `DEGRADED: make.check_security is null — built-in static review lane only`, record the lane `not run (capability absent)` and review the `Cargo.toml` and `Cargo.lock` changes by hand (new git or registry sources, wildcard requirements, new crates that bind native code).
2. **Secrets (`make.secrets_scan`).** Exit 0: `passed`. A reported leak: `failed`, and each reported rule, file and line is a `secrets` candidate; the value is already redacted by the scan and is never copied anywhere. When the key is null, record `not run (capability absent)`; the `secrets` family still gets the source review of step 4.
3. **Image (`make.image_scan`).** The target builds the production image itself; never pass it an image name. Exit 0: `passed`. A non-zero exit that lists HIGH or CRITICAL vulnerabilities: `failed`, one `dependency-advisories` candidate per vulnerable package. When the key is null, record `not run (capability absent)`.

Docker: a failed `docker info` probe, or a lane log that carries the template's message that the target needs a reachable container engine, records both Docker lanes `not run (no Docker)`. Such a lane is never `failed` and never `passed`.

### 4. Review the source of each PROBE family

Apply the static patterns of [reference/attack-playbooks.md](reference/attack-playbooks.md) to the changed files first, then to the code they call (handlers, application services, repository adapters, the router and the schema builder). Clippy findings that the caller already holds are read as candidates; this skill does not run the static-analysis target itself. Record each candidate with `file:line` and the pattern that matched.

### 5. Probe the running service (gated)

Run this step only when the [Dynamic probing gate](#dynamic-probing-gate) is open. Every request uses this form and no other:

```text
"<plugin-root>/scripts/lib/common.sh" http_probe <METHOD> <PATH> [--header 'K: V']... [--body TEXT | --body-file F]
```

- The helper prints `HTTP_STATUS: <code>`, the response headers and at most 64 KiB of body. Exit 0 means any HTTP response, exit 2 a rejected argument: correct the argument once, and drop the probe when the helper cannot express it. Exit 1 is a transport failure: on the first probe it closes the lane (see the gate); after earlier probes were answered it means the service stopped answering, so record the probe sent just before as a `dos` candidate and end step 5.
- `<PATH>` starts with `/` and holds only unreserved characters and `%`-escapes, so a quote is written `%27` and a space `%20`. `--body` holds at most 16 KiB; a larger body goes through `--body-file` with a file under `target/rust-sdlc/tmp/`.
- Tag every probe with `--header 'x-request-id: sec-<rule>-<n>'` so its log lines can be found by request id.
- Create the objects a probe needs through the API first, and probe only those objects.
- Send the probes of [reference/attack-playbooks.md](reference/attack-playbooks.md) for each `PROBE` family that has an HTTP surface: `injection`, `bola-idor`, `mass-assignment`, `dos`, `information-disclosure`.

### 6. Reproduce, promote and re-verify

1. **Dynamic reproduction.** The probe's status, headers or body show the vulnerable behaviour that the playbook names as observed, where the secure behaviour was expected. Record the exact `http_probe` call, the expected and the observed result.
2. **Static reproduction**, for a family without an HTTP surface or while the dynamic lane is `not run`: a lane output line (`error[` line, secret-scan rule and location, image vulnerability), or a source trace from the extractor field to the sink with `file:line` at every hop and no binding, validation or allow-list step between them.
3. A candidate with neither is recorded with status `dropped`.
4. Give each finding the next free `SEC-<n>` id, a severity band from [reference/owasp-catalog.md](reference/owasp-catalog.md), the repository-relative `file` and `line` of the sink (`line` null for a file-level finding), the family id as `rule` and a one-line `summary` of at most 300 characters. Merge findings with the same `(file, line, rule)` into one.
5. **Re-verification.** Repeat the reproduction of every `open` finding of the previous ledger. It no longer reproduces: keep its id and set `fixed`. It still reproduces: keep its id and `open`.
6. A `dependency-advisories` finding for an advisory with no patched version says `no fixed version` in its summary, so that the calling stage escalates it; an exception for it is a protected change that this skill never makes.

### 7. Report

Print, in this order: the lanes table, the families table, the evidence list (one entry per `open` or `fixed` finding: id, reproduction, expected, observed, remediation section), the verdict line, and last the fenced `json` block with the findings array.

```text
| lane | target | result |
| --- | --- | --- |
| dependency policy | make.check_security | passed / failed / not run (<reason>) |
| secrets | make.secrets_scan | passed / failed / not run (<reason>) |
| production image | make.image_scan | passed / failed / not run (<reason>) |
| dynamic probes | common.sh http_probe on service.base_url | passed / failed / not run (<reason>) |

| family | rule | verdict | reason or evidence |
| --- | --- | --- | --- |
| Injection | injection | PROBE / N/A | <reason or SEC ids> |
```

```json
[
  {
    "id": "SEC-1",
    "severity": "High",
    "file": "<repository-relative path>",
    "line": 1,
    "rule": "injection",
    "summary": "<one line, at most 300 characters>",
    "status": "open"
  }
]
```

The dynamic lane is `passed` when every probe sent showed the expected behaviour, and `failed` when at least one reproduced a finding. Print `## Verdict: FAIL` when any finding is `open` with severity `Critical`, `High`, `Medium` or `Low`, or when a lane that ran is `failed`; otherwise print `## Verdict: PASS`. `Info` is reserved for hardening notes without a reproduced impact and never fails the verdict. A `not run` lane never counts as passed: the calling stage applies its degrade rule (an absent capability ends `SUCCESS-WITH-REPORT`; a mapped Docker lane that could not run ends `ESCALATED`).

## Constraints

- Never send a request except through `common.sh http_probe`; never call `curl` directly, never name a second URL and never reach a host other than `service.base_url`.
- Never send a destructive payload (a statement that writes, deletes or locks), never touch data the probe did not create, and never change state except through the service's API.
- Never print, copy or publish a secret value; a finding names the rule, the file and the line, and the value stays redacted.
- Never edit a repository file, never commit and never push; fixes belong to the implementer that the calling stage dispatches.
- Never hide a finding behind a suppression: never an `#[allow(...)]` attribute, never a `.trivyignore` or `.gitleaksignore` entry, never an advisory exception in `deny.toml`, never a lowered bar.
- A fix that needs a file listed by `cargo xtask config-guard --list` is a protected change: report it for the calling stage (approved-config-change label and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1), never apply it.
- Never run a raw `cargo` call except `cargo tree -i <crate>` (to find the crate that pulls an advisory) and `cargo xtask config-guard --list`, on the route the calling stage uses.
- Never report an `open` finding without a reproduction and never invent a finding for an N/A family.

## Verification

- [ ] The families table has eight rows, each `PROBE` or `N/A` with a reason, and `memory-safety` is N/A only when `unsafe_code = "forbid"` holds for every member.
- [ ] The lanes table has four rows; each mapped lane ran once, and a null key or an unreachable Docker is recorded with its `not run (<reason>)`.
- [ ] The dependency-policy lane's `error[` count is compared with `quality.max_dependency_policy_findings`, and the image lane's exit status with `quality.max_image_vulnerabilities_high_critical`.
- [ ] With `capabilities.dynamic_security_testing` false the output holds `SKIPPED: capabilities.dynamic_security_testing is false` and no probe was sent; with it true, every probe in the evidence list is an `http_probe` call on `service.base_url`.
- [ ] Every `open` finding has a reproduction, every non-reproduced candidate is `dropped`, and every previous `open` finding is now `open` or `fixed` under its old id.
- [ ] The output ends with the verdict line followed by one fenced `json` block whose findings carry exactly the seven ledger fields.
- [ ] `git status --porcelain` shows no change made by this skill outside `target/`.
