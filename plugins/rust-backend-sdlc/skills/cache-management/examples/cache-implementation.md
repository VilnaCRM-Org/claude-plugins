# Cache implementation example

A read-through cache of `<Entity>` lookups for the bounded context `<group>/<context>`, written as a decorator of the context's repository port. It is a sketch to adapt, not a file to copy verbatim.

## Placeholders

- `<group>/<context>` is the bounded context; `<context>` in a crate name (`<context>_domain`) is the context name in snake case.
- `<Entity>` is the aggregate; it appears inside type names (`<Entity>Id`, `<Entity>Repository`, `Cached<Entity>Repository`) and, in snake case, where Rust requires a function name (the fixture call of the testing example).
- The port in this sketch has one read method (`find_by_id`) and two write methods (`save`, `delete`). A real port with more methods keeps the same rule: each write method writes through and evicts, each other read method delegates uncached.
- `<Entity>Name` stands for the value objects of the aggregate; the snapshot holds one field per argument of `<Entity>::restore`, in its order.
- `shared_domain` (the shared kernel that declares `Clock`), `shared_infrastructure` and `test_support` are the crate names of a template-derived workspace; use the names its workspace manifest declares.

## Files

| File (in the `<group>/<context>` infrastructure crate) | Content |
| --- | --- |
| `src/cache.rs` | the decorator below |
| `src/cache/tests.rs` | its unit tests, see [cache-testing.md](cache-testing.md) |
| `src/lib.rs` | `pub mod cache;` and the re-export of the decorator |
| `tests/integration/cache.rs` | the integration test over the persistence adapter, declared in `tests/integration/main.rs` |
| `Cargo.toml` | the store dependency, inherited from the workspace |

The store dependency is added only when the crate is already in `[workspace.dependencies]` and on the infrastructure layer's `external` allow-list in `architecture.toml`; otherwise the skill's step 3 escalates. With an in-process store such as `moka` the manifest gains one line:

```toml
[dependencies]
moka.workspace = true
```

## The decorator (`src/cache.rs`)

```rust
//! Read-through cache of `<Entity>` lookups in front of the context's persistence adapter.

use std::sync::Arc;
use std::time::{Duration, SystemTime};

use shared_domain::Clock;
use <context>_domain::{<Entity>, <Entity>Id, <Entity>Name, <Entity>Repository, RepositoryError};

/// The stored state of one `<Entity>`: the value objects `<Entity>::restore` takes. The cache never
/// keeps the aggregate itself, because an aggregate carries the events it recorded.
#[derive(Clone)]
struct Snapshot {
    id: <Entity>Id,
    name: <Entity>Name,
}

impl Snapshot {
    fn of(entity: &<Entity>) -> Self {
        Self {
            id: entity.id(),
            name: entity.name().clone(),
        }
    }

    fn restore(self) -> <Entity> {
        <Entity>::restore(self.id, self.name)
    }
}

/// A snapshot and the time, read from the `Clock` port, from which it is no longer served.
#[derive(Clone)]
struct Entry {
    snapshot: Snapshot,
    expires_at: SystemTime,
}

/// Serves `find_by_id` from memory until an entry expires; every write goes to the wrapped
/// repository first and then evicts the entry.
pub struct Cached<Entity>Repository {
    inner: Arc<dyn <Entity>Repository>,
    clock: Arc<dyn Clock>,
    ttl: Duration,
    entries: moka::future::Cache<<Entity>Id, Entry>,
}

impl Cached<Entity>Repository {
    /// Wraps `inner`; keeps at most `capacity` entries, each for `ttl` as measured by `clock`.
    #[must_use]
    pub fn new(
        inner: Arc<dyn <Entity>Repository>,
        clock: Arc<dyn Clock>,
        ttl: Duration,
        capacity: u64,
    ) -> Self {
        // Bounded by size only: the store's own time-based expiry would read the process clock,
        // which tests cannot move.
        let entries = moka::future::Cache::builder().max_capacity(capacity).build();
        Self {
            inner,
            clock,
            ttl,
            entries,
        }
    }

    async fn lookup(&self, id: <Entity>Id) -> Result<Option<<Entity>>, RepositoryError> {
        let now = self.clock.now();
        if let Some(entry) = self.entries.get(&id).await {
            if now < entry.expires_at {
                return Ok(Some(entry.snapshot.restore()));
            }
            self.entries.invalidate(&id).await;
        }
        let found = self.inner.find_by_id(id).await?;
        if let Some(entity) = &found {
            self.remember(entity, now).await;
        }
        Ok(found)
    }

    async fn remember(&self, entity: &<Entity>, now: SystemTime) {
        // `checked_add`, not `+`: an expiry beyond the clock's range is left uncached, never a panic.
        if let Some(expires_at) = now.checked_add(self.ttl) {
            let entry = Entry {
                snapshot: Snapshot::of(entity),
                expires_at,
            };
            self.entries.insert(entity.id(), entry).await;
        }
    }

    async fn store(&self, entity: &<Entity>) -> Result<(), RepositoryError> {
        let written = self.inner.save(entity).await;
        // Evict even after a failed write: the database may hold either version.
        self.entries.invalidate(&entity.id()).await;
        written
    }

    async fn remove(&self, id: <Entity>Id) -> Result<(), RepositoryError> {
        let removed = self.inner.delete(id).await;
        self.entries.invalidate(&id).await;
        removed
    }
}

impl std::fmt::Debug for Cached<Entity>Repository {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Settings and a count only: cached values may hold personal data.
        f.debug_struct("Cached<Entity>Repository")
            .field("ttl", &self.ttl)
            .field("entries", &self.entries.entry_count())
            .finish_non_exhaustive()
    }
}

#[async_trait::async_trait]
impl <Entity>Repository for Cached<Entity>Repository {
    async fn save(&self, entity: &<Entity>) -> Result<(), RepositoryError> {
        self.store(entity).await
    }

    async fn delete(&self, id: <Entity>Id) -> Result<(), RepositoryError> {
        self.remove(id).await
    }

    async fn find_by_id(&self, id: <Entity>Id) -> Result<Option<<Entity>>, RepositoryError> {
        self.lookup(id).await
    }
}

#[cfg(test)]
mod tests;
```

Why each piece is there:

- **The port is unchanged.** Query handlers keep depending on `<Entity>Repository`; the domain gains no cache type, field or call.
- **Expiry through the `Clock` port.** `lookup` reads `Clock::now()` once, serves an entry only while that time is before `expires_at`, and evicts an expired entry before reloading it. The boundary is exclusive: at exactly `expires_at` the entry is reloaded.
- **Eviction on commands.** `store` and `remove` write through and then evict, also after an error. A lookup that started before a write can still store the value it read after the eviction; the time to live bounds that window, which is why it must stay inside the story's staleness budget.
- **Nothing else is cached.** A miss is not stored (a later insert would stay hidden), an error propagates uncached, and pages or searches delegate to `inner`.
- **No panics.** `checked_add` replaces `+` on `SystemTime`; there is no `unwrap`, `expect`, indexing or `as` cast.
- **Coverage and complexity see the logic.** The `#[async_trait]` methods only delegate to the inherent `async fn`s.

## Crate root (`src/lib.rs`)

```rust
pub mod cache;

pub use cache::Cached<Entity>Repository;
```

## Wiring in the composition root

The composition root wraps the persistence adapter once and hands the same `Arc` to every handler. The time to live and the capacity are configuration values, read where the composition root reads the rest of the service configuration and documented with it (see the configuration-management skill):

```rust
let persistence: Arc<dyn <Entity>Repository> = Arc::new(Pg<Entity>Repository::new(pool.clone()));
let repository: Arc<dyn <Entity>Repository> = Arc::new(Cached<Entity>Repository::new(
    persistence,
    Arc::clone(&clock),
    config.cache_ttl,
    config.cache_capacity,
));
```

`Pg<Entity>Repository` is the context's persistence adapter, `clock` the `Clock` adapter the composition root already builds, and `config` the service configuration (`cache_ttl` and `cache_capacity` are new settings; a service that caches several aggregates gives each its own pair). The composition root's own tests, which build the adapters, pick up the wrapping.

## Review checklist

- [ ] The adapter lives in the infrastructure layer named by `architecture.layers` (or next to the persistence adapter when that list is empty).
- [ ] No domain crate names the adapter or a cache.
- [ ] Expiry is computed and checked only through `Clock::now()`; the store is bounded by size only.
- [ ] Every write method of the port writes through, then evicts, also on error.
- [ ] Misses, errors, pages and command results are never cached.
- [ ] The time to live does not exceed the story's staleness budget and comes from configuration.
- [ ] `Debug` prints settings and a count, never a value.
- [ ] The unit tests of [cache-testing.md](cache-testing.md) exist and pass under `make.unit_tests` and `make.tests_with_coverage`.
