---
name: async-runtime-safety
description: Use when Rust code adds or changes an `async fn`, an `.await`, a spawned task, a `tokio::select!`, a timeout, a lock shared between tasks, an `#[async_trait]` impl, or reads time or generates identifiers, and when the target mapped by `make.static_analysis` reports `await_holding_lock`, `disallowed_methods` or `clone_on_ref_ptr`. Covers blocking calls in async code (`std::fs`, `std::thread::sleep`, synchronous DNS) replaced by `tokio` equivalents or `spawn_blocking`, lock guards across `.await`, cancellation safety and timeouts, `#[async_trait]` delegation to an inherent `async fn`, the `Clock` and `UuidGenerator` ports and `Arc::clone(&x)`. Skip when the change touches no async code, no shared state and no time or identifier source. Not for error types and problem responses (use rust-error-handling), not for adding the `tokio` crate to a layer (use dependency-policy), not for slow queries (use query-performance-analysis).
---

# Async Runtime Safety

## Profile keys consumed

- `make.static_analysis` — the strict static analysis that reports a lock guard held across `.await`, a banned blocking or wall-clock API and an implicit pointer clone; `null` degrades to a manual review of the diff
- `make.unit_tests` — the unit suite, where paused-clock tests prove timeouts and cancellation without real time; `null` is recorded as a capability gap
- `make.integration_tests` — the database-backed suite, where timeouts and cancellation are proven against the real dependencies; `null` is recorded as a capability gap

## Context

The service runs on the multi-threaded `tokio` runtime: axum handlers, the command and query buses, `#[async_trait]` ports and the database driver all share a small pool of worker threads. Four failure classes are invisible to the compiler and expensive in production:

- **Blocking in async code.** A synchronous file read, a thread sleep or a synchronous DNS lookup parks a worker thread; every task on that thread stalls, request budgets expire and health probes time out.
- **A lock guard across `.await`.** A `std::sync` guard held across a suspension point makes the future non-`Send` or deadlocks the runtime; even an async mutex guard held across slow I/O serializes every caller.
- **Cancellation.** Any future can be dropped at any `.await`: by a timeout, by `tokio::select!`, or by the server when the client disconnects or the request budget expires. Code that is not cancellation-safe leaves half-applied state.
- **Hidden time and randomness.** Reading the wall clock or generating identifiers inline makes behaviour untestable; the template bans those APIs and routes them through the `Clock` and `UuidGenerator` ports.

The rules apply to code reachable from an `async fn` or a future. Synchronous start-up code that runs before the runtime starts is outside them. The repository's own rules in `AGENTS.md` and its architecture document win where they are stricter.

## Task

Make every async path of the change non-blocking, guard-free across `.await`, cancellation-safe and time-bounded, with time and identifiers read only through ports, and prove it with the targets mapped by `make.static_analysis`, `make.unit_tests` and `make.integration_tests`.

## Success criteria

- No blocking call is reachable from async code: file, sleep and DNS calls use their `tokio` equivalents, and CPU-heavy or blocking-library work runs in `tokio::task::spawn_blocking`.
- No lock guard (`std::sync`, `tokio::sync`, `RefCell`) is alive across an `.await`.
- Every await on an external dependency is bounded by a timeout whose duration comes from configuration, and every `tokio::select!` branch is cancellation-safe.
- Every method of an `#[async_trait]` impl is a single delegation to an inherent `async fn` of the same type.
- Time is read only through `Clock` (elapsed time through `tokio::time::Instant`), identifiers come only from `UuidGenerator`, and every shared pointer copy is written `Arc::clone(&x)`.
- The mapped targets pass; each null target is recorded `not run (capability absent)` and the result is `SUCCESS-WITH-REPORT`, never a claimed pass.

## Steps

### 1. Resolve the profile and the async surface

Read `make.static_analysis`, `make.unit_tests` and `make.integration_tests` from the profile. List the async surface of the diff: every added or changed `async fn`, `.await`, `tokio::spawn`, `tokio::select!`, `#[async_trait]` impl, `Mutex`, `RwLock` and `RefCell` field, and every call that reads time or creates an identifier. When the list is empty, record `NOT APPLICABLE: no async code, shared state, time or identifier source in the diff` and stop.

### 2. Replace blocking calls

| Blocking call in async code | Non-blocking replacement |
| --- | --- |
| `std::fs` (`read`, `write`, `File::open`, `metadata`, `create_dir_all`) | `tokio::fs` with the same names |
| `std::thread::sleep` | `tokio::time::sleep` |
| synchronous DNS (`std::net::ToSocketAddrs`, `to_socket_addrs`) | `tokio::net::lookup_host` |
| `std::sync::mpsc` receive, blocking `std::io` reads | `tokio::sync::mpsc`, `tokio::io` |
| CPU-heavy work (hashing, compression, large serialization) or a library that only offers a blocking API | `tokio::task::spawn_blocking` |
| `block_on` (`futures` or `Handle::block_on`) inside a task | an `.await`; never nest a runtime |

`spawn_blocking` returns a `JoinHandle`: await it and convert the `JoinError` into the layer's error as `#[source]`, never `unwrap` it. In the sketch below, `hash` is the blocking work and `<Entity>Error::worker` is a constructor of the context's error enum that boxes the `JoinError` as its source:

```rust
let digest = tokio::task::spawn_blocking(move || hash(&payload))
    .await
    .map_err(<Entity>Error::worker)?;
```

Before an infrastructure or application crate calls `tokio::fs` or `spawn_blocking`, confirm that `tokio` is on that layer's allow-list in `architecture.toml`. Domain crates stay synchronous apart from `#[async_trait]` port signatures. A missing allow-list entry is a dependency-policy decision (escalated, never edited here): see [dependency-policy](../dependency-policy/SKILL.md).

### 3. Release every lock before `.await`

Static analysis reports a `std::sync` guard (`clippy::await_holding_lock`) or a `RefCell` borrow (`clippy::await_holding_refcell_ref`) across `.await`. Apply the same rule to `tokio::sync::Mutex` and `RwLock` guards, which the lint does not see: copy or take what you need inside a block, let the guard drop at the end of the block, then await.

```rust
let pending = {
    let mut queue = self.queue.lock().await;
    std::mem::take(&mut *queue)
}; // the guard is dropped here, before the next `.await`
self.publisher.publish(pending).await?;
```

Prefer state that needs no lock across tasks: an atomic for a counter or a flag (`clippy::mutex_atomic`), a `tokio::sync::watch` or `mpsc` channel for hand-over, or an owned value moved into the task. A `std::sync::Mutex` is allowed only when every guard is dropped before the next `.await`, and its poison error is converted, never unwrapped.

### 4. Cancellation safety and timeouts

- **Bound every external await.** Wrap each call to a database, broker, outbound HTTP client or probe in `tokio::time::timeout(budget, call).await`, with `budget` read from configuration in the composition root (see [configuration-management](../configuration-management/SKILL.md)), never a literal duration in a handler. Convert the `Elapsed` error into a typed variant of the layer's error (for example `Unavailable`), so it reaches the client through [rust-error-handling](../rust-error-handling/SKILL.md).
- **Make each await a safe drop point.** A logical write becomes visible in one awaited step (one repository call, one transaction); never split it across two awaits without a way to recover. Side effects that must follow a write (event publication, cache invalidation) run after the write has succeeded, and their failure is handled, not left half-done.
- **Select only cancellation-safe branches.** In `tokio::select!`, use futures that lose nothing when dropped (`mpsc::Receiver::recv`, `watch::Receiver::changed`, `tokio::time::sleep`). A future that buffers partial progress (`read_exact`, `read_to_end`, a multi-step operation) is pinned outside the loop and polled by `&mut` reference, so a lost race does not restart it.
- **Own every spawned task.** Keep the `JoinHandle` of a `tokio::spawn` and await or abort it on shutdown; never detach a task that writes state, and never discard the handle with `let _ =` (`clippy::let_underscore_future`).
- **Test without real time.** Unit tests of timeouts and retries use `#[tokio::test(start_paused = true)]` and `tokio::time::advance`; elapsed time is measured with `tokio::time::Instant`, which follows the paused clock.

### 5. Delegate `#[async_trait]` methods to an inherent `async fn`

The body of every method in an `#[async_trait]` impl is one delegation to an inherent `async fn` of the same type. The macro rewrites the body into a boxed future, so coverage records no line counts there and the complexity check does not see it; logic placed there would pass both gates unexamined.

```rust
#[async_trait::async_trait]
impl CommandHandler<Create<Entity>> for Create<Entity>Handler {
    async fn handle(&self, command: Create<Entity>) -> Result<(), <Entity>Error> {
        self.create(command).await
    }
}
```

Synchronous trait methods (for example `Clock::now`) are not affected.

### 6. Read time and identifiers through ports

- Time comes from the `Clock` port (`fn now(&self) -> SystemTime`) and identifiers from the `UuidGenerator` port (`fn generate(&self) -> Uuid`), both injected as `Arc<dyn Clock>` and `Arc<dyn UuidGenerator>` through the handler's constructor.
- The wall-clock and identifier constructors (`SystemTime::now`, `Instant::now`, `Uuid::new_v4`, `Uuid::now_v7`) are on the `disallowed-methods` list of `clippy.toml`; read that list at runtime for the full set. Only the adapters that own a banned API call it, each with one item-level `#[expect(clippy::disallowed_methods, reason = "…")]`.
- Tests use the clock and generator doubles of the shared test-support crate, or the paused `tokio` clock, never real time.

### 7. Copy shared pointers explicitly

Write `Arc::clone(&x)`, never `x.clone()`, for an `Arc` or `Rc` (`clippy::clone_on_ref_ptr`), so the cheap pointer copy is visible and cannot be confused with a deep clone. Ports are shared as `Arc<dyn Port>` and carry `Send + Sync + std::fmt::Debug` as supertraits, so the futures that capture them stay `Send`.

### 8. Verify with the mapped targets

Run, in this order, each mapped target as [verification-workflow](../verification-workflow/SKILL.md) prescribes (in the background, logged and polled to the end):

1. `make.static_analysis` — the lock, banned-API and pointer-clone lints;
2. `make.unit_tests` — the paused-clock tests of timeouts, cancellation and delegation;
3. `make.integration_tests` — the database-backed tests; run it alone, never in parallel with another database-backed target, because it resets the shared test database.

For each null key, record `not run (capability absent)` (degrade D1). When `make.static_analysis` is null, review the added lines of the diff for `std::fs::`, `std::thread::sleep`, `to_socket_addrs`, `block_on`, `.lock()` or `.borrow()` followed by an `.await` in the same scope, `SystemTime::now`, `Instant::now`, `Uuid::new_v4`, `Uuid::now_v7` and `.clone()` on an `Arc`, and fix every hit. A target that cannot start (no toolchain, no reachable container engine) is recorded `not run (no toolchain)` or `not run (no Docker)` and handed back to the calling stage, which escalates; it never counts as a pass.

## Constraints

- Never call a blocking API from async code, never nest a runtime with `block_on`, and never unwrap a `JoinError`, a poisoned lock or an `Elapsed`.
- Never hold a lock guard across `.await`, whichever mutex type it comes from.
- Never await an external dependency without a timeout, and never hard-code the timeout duration outside the configuration.
- Never put logic in an `#[async_trait]` method body; it delegates to an inherent `async fn`.
- Never read the wall clock or create an identifier outside the `Clock` and `UuidGenerator` adapters, and never weaken the `disallowed-methods` list or the lint levels: `clippy.toml` and `[workspace.lints]` are protected configuration. A finding that only such a change would clear is escalated with `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`.
- Never write `.clone()` on an `Arc` or `Rc`; write `Arc::clone(&x)`.
- Never run the integration target in parallel with another database-backed target.
- The fix loop is bounded by the calling stage's iteration guard (5). The same finding after a fix, or the guard exhausted, ends the loop with the escalation block below; there is no further retry.

## Verification

- Targets-run rows, in the FR-1 vocabulary, one per key: `<target>: passed | failed | not run (<reason>)` for `make.static_analysis`, `make.unit_tests` and `make.integration_tests`.
- The async surface listed in step 1, each item with the rule that covers it (steps 2 to 7) and the test that proves it, or `NOT APPLICABLE` with the reason.
- Evidence for the `EXECUTE` verdict of this skill in the triage table: the targets-run rows plus the list of timeouts added (call, configuration source of the budget) and of `spawn_blocking` uses, or `none`.

### Escalation

When the loop ends without a pass, or a fix needs protected configuration or a new allow-list entry, print the canonical block with the calling stage's id and exit string:

```text
=== SDLC ESCALATION ===
stage: <stage-id>
iteration: <n>/5
exit_condition: <exit string of the calling stage, verbatim>
status: NOT MET
blocking_finding: <file:line> <lint, test name or rule>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human decision, for example a protected change with ALLOW_PROTECTED_CONFIG_EDIT=1>
=== END ===
```
