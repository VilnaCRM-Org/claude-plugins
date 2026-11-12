---
name: observability-instrumentation
description: Use when a change adds or alters a handler, a command or query handler, an event subscriber, an adapter call, an error path or a health probe of a Rust service and it needs `tracing` spans with structured fields, `request_id` correlation through the `x-request-id` header, JSON log lines through `tracing-subscriber` that carry no PII or secrets, and liveness and readiness probes that keep their meaning, proven by unit tests. Skip when the change touches no Rust source. Not for adding a metrics backend or exporter (this skill selects none; the template ships `tracing` logs only), not for mapping errors to problem documents (use rust-error-handling), not for auditing log and error disclosure as an attack family (use security-audit).
---

# Observability Instrumentation

## Profile keys consumed

- `service.liveness_path` — the liveness route: it answers without touching any dependency
- `service.readiness_path` — the readiness route: it probes every dependency and answers a problem document when one fails
- `make.unit_tests` — the target that runs the unit tests proving the instrumentation; null: the tests are recorded as not run

## Context

The template's observability model is logs and spans only:

- **One subscriber.** The composition root installs one `tracing-subscriber` formatter at start-up: JSON output, one object per line on stdout, events flattened into the top level, the current span as `span` and every open span, outermost first, as `spans`. The level filter takes `EnvFilter` directives from configuration.
- **The request span.** The router's `TraceLayer` opens one span per request with the method, the route template, the path and the `request_id`, and writes exactly one access-log line when the response leaves. Every line written while the request runs, in any crate, carries that span as the first element of `spans`, so `request_id` correlates all of them.
- **The request id.** The request-id layers of tower-http read the `x-request-id` header, keep an inbound value only when it matches the template's sanitizing rule, generate a UUID otherwise, and echo the id on every response, error responses included.
- **Fixed messages.** Log messages are fixed texts; the variable parts are structured fields. The repository's `docs/operations.md` (section on logs and request ids) lists every key, every fixed message with its level and fields, and the fields that are never logged. Read that list at runtime; it wins over this skill.
- **Layers.** Domain crates are framework-free and do not log; application services, event subscribers, handlers and infrastructure adapters do. The per-layer dependency allow-lists decide which crates may depend on `tracing` (see the [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md) skill).
- **No metrics backend selector.** The template ships only `tracing` and `tracing-subscriber` JSON logs. This skill chooses no metrics crate, exporter or collector, and no profile key selects one.

## Task

Instrument the changed code so that every new or changed code path is traceable by `request_id`, every log line is a fixed message with structured fields and without sensitive data, the health probes at `service.liveness_path` and `service.readiness_path` keep their meaning, and unit tests run through `make.unit_tests` prove it.

## Success criteria

- Every new handler, application service call, adapter call and spawned task runs inside the request span or a child span, so its lines carry `request_id` in the first element of `spans`.
- Every event is a `tracing` macro with structured fields and a fixed message text; no message is built with `format!`.
- No field, span field or message contains a request or response body, a header other than `x-request-id`, a credential, a token, a connection string or personal data; every `#[tracing::instrument]` carries `skip_all` and names its fields explicitly.
- Every response, errors included, still echoes `x-request-id`.
- The liveness route at `service.liveness_path` touches no dependency; the readiness route at `service.readiness_path` probes every dependency under a deadline, answers the fixed dependency problem without the cause, and logs the cause at `WARN` with the request id.
- New fixed messages and fields appear in the repository's log documentation in the same change.
- No metrics crate, exporter or second subscriber is added.
- The unit tests that assert the emitted lines pass through the target mapped by `make.unit_tests`, or are recorded `not run (capability absent)` when it is null.
- The evidence table and the verdict line of step 7 are printed.

## Steps

1. **Read the runtime lists.** Read `AGENTS.md` and the logging section and health-probe runbook of the repository's `docs/operations.md`: the keys, the fixed messages, their levels and fields, the fields that are never logged, and the probe semantics. Locate the subscriber initialiser in the composition root and the request-id and trace layers of the router. Never install a second subscriber and never call a global `init()` outside the composition root.
2. **Place spans.** A handler needs no span of its own: it runs inside the request span. Add a child span where work leaves the process or runs long: an adapter method, an outbound call, a batch, a spawned task.

   ```rust
   #[tracing::instrument(name = "<context>.load_<entity>", skip_all, fields(<entity>_id = %id))]
   async fn load(&self, id: <Entity>Id) -> Result<Option<<Entity>>, <Context>RepositoryError> {
       // ...
   }
   ```

   `skip_all` is mandatory: without it every argument is recorded with its `Debug` output, which is how bodies and credentials leak. Record ids and counts, never values a user typed.
3. **Write events.** Use the macro of the level the runtime list gives (`ERROR` for the error chain behind a 5xx, `WARN` for a degraded dependency, `INFO` for lifecycle and audit lines, `DEBUG` for diagnostics), a fixed message and named fields:

   ```rust
   tracing::warn!(dependency = probe.identifier(), cause = %cause, "<fixed message>");
   ```

   Use `%` (`Display`) for ids and error chains, and `?` (`Debug`) only for types whose `Debug` holds no data. A new fixed message or field gets its row in the repository's log documentation in the same change, as the [documentation-sync](../documentation-sync/SKILL.md) skill prescribes.
4. **Keep the correlation.** A task spawned from a request keeps the request span explicitly, because `tokio::spawn` starts without it:

   ```rust
   use tracing::Instrument as _;

   tokio::spawn(publish(event).instrument(tracing::Span::current()));
   ```

   An outbound HTTP call to another service forwards the current `x-request-id` value as a header. Never generate a second id for the same request, and never weaken the inbound sanitizing rule.
5. **Keep sensitive data out.** Never log a body, a header other than `x-request-id`, a credential, a token, a connection string or personal data. A type that holds a credential gets a hand-written `Debug` that prints `<redacted>` for it instead of a derived one (the workspace lints require a `Debug` implementation, so write it rather than omit it). Never write diagnostics with `println!`, `eprintln!` or `dbg!`: stdout carries only the subscriber's JSON lines.
6. **Keep the health probes honest.**
   - **Liveness (`service.liveness_path`):** never add a dependency check to it. It proves the process serves requests, so a dependency outage never restarts a healthy process.
   - **Readiness (`service.readiness_path`):** a new dependency gets a probe behind the health-check context's probe port, run concurrently with the others under the probe deadline. A failed or timed-out probe adds its fixed message to the dependency problem and logs the cause at `WARN` with the `dependency` and `cause` fields; the cause never appears in the response.
7. **Prove it with unit tests.** In the sibling `tests.rs` of the changed module, capture the events with the shared test-support crate's log recorder (or a `MakeWriter` buffer passed to the subscriber initialiser) and assert the message, the level, the fields, and that no sensitive value appears in any field:

   ```rust
   #[tokio::test]
   async fn a_failed_publication_logs_the_event_id_and_no_credential() {
       let (recorder, _guard) = LogRecorder::install();

       let _outcome = <the call under test, set up to fail>.await;

       let lines = recorder.lines();
       assert!(lines.iter().any(|line| line.message == "<fixed message>"
           && line.level == Level::ERROR
           && line.field("event_id").is_some()));
       assert!(lines
           .iter()
           .all(|line| line.fields.iter().all(|(_, value)| !value.contains(CREDENTIAL))));
   }
   ```

   `CREDENTIAL` is a constant of the test holding the fake credential it configured, so the second assertion proves the value never reaches a field.

   Run the target mapped by `make.unit_tests` as the [verification-workflow](../verification-workflow/SKILL.md) skill prescribes (in the background, log under `target/rust-sdlc/logs/`, waited for with `common.sh wait_log`), with no option and no variable:

   ```bash # profile-example
   make unit-tests
   ```

   - **Mapped:** a failing test is fixed at its root cause (the instrumentation or the code under test, never the assertion) and the target runs again; the calling stage's `MAX_ITERATIONS=5` guard bounds the reruns, and an exhausted guard ends `ESCALATED` with the failing test as the blocking finding.
   - **Null:** record `not run (capability absent)`, keep the tests in the change, and end `SUCCESS-WITH-REPORT`; never claim the instrumentation was proven.

   Then print the evidence table and the verdict line:

   ```text
   | check | evidence | result |
   | --- | --- | --- |
   | spans and correlation | <file:line of each new span or instrumented task> | done |
   | fields without sensitive data | <file:line of each new event> | done |
   | health probes | liveness unchanged / readiness probe <file:line> | done / not changed |
   | log documentation | <row added or "no new message"> | done / not changed |
   | unit tests | make.unit_tests | passed / failed / not run (capability absent) |

   observability-instrumentation: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
   ```

   `SUCCESS`: the unit tests passed. `SUCCESS-WITH-REPORT`: `make.unit_tests` is null. `ESCALATED`: the calling stage's guard was exhausted with a failing test.

A JSON line of a request, as the template writes it (field names from the repository's log documentation):

```json # profile-example
{"timestamp":"2026-11-12T10:15:00.000000Z","level":"WARN","message":"health probe failed","target":"health_check_application::service","dependency":"database","cause":"probe failed: timed out after 3s","span":{"name":"http.request","http.request.method":"GET","http.route":"/api/health","url.path":"/api/health","request_id":"5f0c6c1e-8c1b-4f53-9d84-1f2a7d8f6b10"},"spans":[{"name":"http.request","http.request.method":"GET","http.route":"/api/health","url.path":"/api/health","request_id":"5f0c6c1e-8c1b-4f53-9d84-1f2a7d8f6b10"}]}
```

## Constraints

- Never log a request or response body, a header other than `x-request-id`, a credential, a token, a connection string or personal data, and never use `#[tracing::instrument]` without `skip_all`.
- Never add a metrics crate, an exporter, a collector or a second subscriber; this skill has no metrics backend selector.
- Never write to stdout or stderr outside the subscriber (`println!`, `eprintln!`, `dbg!`).
- Never add a dependency check to the liveness route, and never return a probe's cause in the readiness response.
- Never add `tracing` to a domain crate; never edit the layer allow-lists to let it in.
- Never silence a lint with an `#[allow(...)]` attribute; a justified exception uses `#[expect(..., reason = "...")]` as the repository's rules allow.
- Never rename a documented log key or fixed message without changing the repository's log documentation in the same change.

## Verification

- [ ] The target mapped by `make.unit_tests` exits 0 with the new log-capture tests, or the evidence table records `not run (capability absent)` when it is null.
- [ ] `git diff` shows no `println!`, `eprintln!` or `dbg!` added to service code, and every added `#[tracing::instrument` carries `skip_all`.
- [ ] Every new event has a fixed message and named fields, and its message appears in the repository's log documentation.
- [ ] The liveness route at `service.liveness_path` still touches no dependency, and every new dependency has a readiness probe behind `service.readiness_path`.
- [ ] No metrics crate, exporter or second subscriber appears in the diff of any `Cargo.toml` or of the composition root.
- [ ] The output ends with the evidence table and the verdict line of step 7.
