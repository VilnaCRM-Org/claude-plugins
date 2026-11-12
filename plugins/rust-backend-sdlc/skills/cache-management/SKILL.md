---
name: cache-management
description: Use when a hot or slow read path of a Rust service needs an in-process cache - a cache adapter behind the context's port in the infrastructure layer, expiry decided through the Clock port, invalidation by every command that writes the cached data, a domain that holds no cache, and unit and coverage tests that prove hits, expiry and invalidation. Skip when the story gives no staleness budget or no measured need for a cache. Not for making the underlying query faster (use query-performance-analysis) and not for designing the aggregate or its port (use implementing-ddd-architecture).
---

# Cache Management

## Profile keys consumed

- `architecture.layers` — the layer names of the architecture model; selects where the cache adapter, the port it implements and the wiring live
- `make.unit_tests` — runs the unit tests of the cache adapter
- `make.tests_with_coverage` — runs the unit and integration tests under the repository's coverage floors

## Context

- **When a cache earns its place.** All three must hold: (a) a measured need, such as a read that stays hot or slow after [query-performance-analysis](../query-performance-analysis/SKILL.md) tuned it, a load budget it breaks, or numbers in the story; (b) a staleness budget written in the story ("a served value may be at most `<n>` old"); (c) the cached data belongs to this bounded context, so the context's own commands are its only writers.
- **Port, not product.** The application layer's query handlers depend on the domain port of the context (`<Entity>Repository`, or a read port). The cache adapter implements that same port in the infrastructure layer and wraps the persistence adapter, so no handler learns that a cache exists; the composition root alone chooses the adapter. The domain holds no cache: no domain type stores, reads or evicts cached data.
- **Time comes from the `Clock` port.** The shared kernel declares `Clock` (`fn now(&self) -> SystemTime`), its adapter is the only reader of the wall clock, and the repository's lint configuration (`disallowed-methods` in `clippy.toml`) bans `SystemTime::now` and `Instant::now` elsewhere. The adapter computes each entry's expiry from `Clock::now()` and compares against it on every read, so a test moves time without sleeping.
- **What the template already ships (read it, do not assume it).** The shared kernel may declare a byte-oriented cache port (a technical port no domain type uses), with a bounded in-process adapter in the shared infrastructure crate, meant for byte payloads such as health probes. Caching an aggregate through it would need an encoder in the infrastructure layer; a typed decorator keyed by `<Entity>Id` avoids that. The store crate the decorator uses must be on the infrastructure layer's allow-list in `architecture.toml`.
- **Aggregates are not cached.** An aggregate carries the domain events it recorded; the cache keeps the stored state (the value objects that `<Entity>::restore` takes) and rebuilds a fresh aggregate on every hit.
- **An in-process cache is per instance.** A command evicts the entry only in the instance that ran it; every other instance serves its copy until it expires. The expiry is therefore the staleness bound across instances, and it must not exceed the story's staleness budget.

## Task

Put a read-through cache of the `<Entity>` lookups of `<group>/<context>` behind the context's repository port in the infrastructure layer, decide expiry through the `Clock` port, evict on every write a command performs, keep the domain free of any cache, and prove hits, expiry and eviction with unit tests and the coverage target.

## Success criteria

- One cache adapter type in the `<group>/<context>` infrastructure crate implements the port; no domain or application type names it, and only the composition root constructs it.
- Each entry stores an expiry computed as `Clock::now()` plus the time to live with `checked_add`; a read serves the entry only while `Clock::now()` is before that expiry. The adapter reads no other clock and configures no time-based expiry of its store.
- Commands invalidate: every port method a command handler calls writes to the wrapped repository first and then evicts the entry, also when the write failed. Only a read miss fills the cache; a miss (`None`), an error, a page and a command result are never cached.
- The time to live and the capacity come from configuration through the composition root, never from a literal in the adapter.
- The adapter's `Debug` output shows its settings and entry count, never a cached value.
- Unit tests prove a hit, the expiry boundary, eviction after a write, after a failed write and after a delete, that a miss, an error and an out-of-range expiry are not cached, and that `Debug` hides values; the targets-run list records `unit-tests` and `tests-with-coverage` as `passed` or `not run (<reason>)`.

## Steps

1. **Confirm the need.** Check conditions (a), (b) and (c) of `## Context`. When one is missing, add no cache: report `no cache added: <missing condition>` and stop.
2. **Locate the layers.** Read `architecture.layers`:
   - Non-empty: it lists the layers of the architecture model. The adapter goes in the infrastructure layer of that list, the port stays in the domain layer and the wiring in the composition root. When the list names no infrastructure layer, a cache adapter has no legal home: hand the calling stage `blocking_finding: architecture.layers names no infrastructure layer` and let it escalate.
   - Empty (`[]`): the repository declares no layer model. Put the adapter next to the persistence adapter it wraps, record `layers: not declared (architecture.layers is empty)` in the evidence, and apply every other rule of this skill unchanged.
3. **Choose the store.** Use a bounded in-process map keyed by `<Entity>Id`. Its crate must already be in `[workspace.dependencies]` and on the infrastructure layer's `external` allow-list in `architecture.toml` (read both at runtime). When the allow-list lacks it, the change is protected: hand the stage `blocking_finding: <crate> is not allowed for the infrastructure layer` and let it escalate; [dependency-policy](../dependency-policy/SKILL.md) covers the escalation.
4. **Write the adapter** as [examples/cache-implementation.md](examples/cache-implementation.md) shows: `src/cache.rs` in the `<group>/<context>` infrastructure crate with its unit tests in the sibling `src/cache/tests.rs` (declared `#[cfg(test)] mod tests;`, no `mod.rs`); `#[async_trait]` methods delegate to inherent `async fn`s; production code has no `unwrap`, `expect`, `panic!`, indexing or `as` casts.
5. **Invalidate on every command.** List the command handlers that write `<Entity>` and confirm each writes through the port the adapter wraps. A write that bypasses the port (another adapter, a batch job) would leave stale entries: route it through the port. Every port method that writes invalidates (evicts) the entry it touched; a read method other than the lookup by identifier (a page, a search) delegates to the wrapped repository uncached.
6. **Wire it in the composition root.** Wrap the persistence adapter once and share the result (`Arc`) with every handler; read the time to live and the capacity from the service configuration as [configuration-management](../configuration-management/SKILL.md) describes.
7. **Test it** as [examples/cache-testing.md](examples/cache-testing.md) shows, then run the targets one at a time, the way the calling stage runs `make` (in the background with a log, polled):
   - `make.unit_tests` non-null: run `make unit-tests`. Null: record `unit-tests: not run (capability absent)`.
   - `make.tests_with_coverage` non-null: run `make tests-with-coverage`; it enforces the repository's coverage floors on the new adapter. Null: record `tests-with-coverage: not run (capability absent)`.
   - A failure is fixed at its root cause and re-run; each re-run is one iteration of the calling stage's guard (`MAX_ITERATIONS=5`), and on exhaustion the stage escalates with `blocking_finding: make <target> exit <code>`. A run classified `not run (no Docker)` (the template's container-engine message, degrade row D2) is reported as such; the calling stage decides its outcome.
8. **Report** the evidence block of `## Verification` to the calling stage.

## Constraints

- Never hold, read or evict cached data in a domain crate, never add a cache type or field to an aggregate, a value object or a domain service, and never let a domain type depend on the cache adapter.
- Never read `SystemTime::now` or `Instant::now` in the adapter, and never configure the store's own time-based expiry; time comes from the `Clock` port.
- Never cache a miss, an error, a page or a command result, and never fill the cache from a write.
- Never skip the wrapped repository on a write, and never skip the eviction after a failed write.
- Never print a cached value in `Debug` output or in a log line.
- Never edit `architecture.toml`, `clippy.toml` or another file listed by `cargo xtask config-guard --list` to let the adapter pass a gate; never suppress a lint, exclude the adapter from coverage or lower a threshold.
- Never share one adapter instance between tests, and never wait on real time in a test.

## Verification

Hand the calling stage this evidence block; it becomes the `evidence or reason` cell of this skill's triage row and feeds the targets-run list:

```text
skill: cache-management EXECUTE
need: <measured hot or slow read>; staleness budget: <from the story>
adapter: <group>/<context> infrastructure crate, src/cache.rs, implements <Entity>Repository
layers: infrastructure layer of architecture.layers | not declared (architecture.layers is empty)
expiry: Clock port, expires_at = now + ttl via checked_add
evicted by: <command handler> -> <port method>
domain: no cache type, field or call
unit-tests: passed | not run (capability absent)
tests-with-coverage: passed | not run (capability absent | no Docker)
```

A run that stops at step 1 hands over the single line `no cache added: <missing condition>` instead. Wider test strategy (integration, end-to-end, mutation) follows [testing-workflow](../testing-workflow/SKILL.md).
