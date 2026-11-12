# Cache testing example

Tests for the decorator of [cache-implementation.md](cache-implementation.md), in the infrastructure crate of `<group>/<context>`. The placeholders are the same: `<Entity>` is the aggregate, `<context>` in a crate name is the context name in snake case, `fixture::<Entity>` stands for the context's seeded `<Entity>` fixture function (its name in snake case), and the shared crate names (`shared_domain`, `test_support`) are the ones the workspace manifest declares.

## What the tests prove

| Behaviour | Test |
| --- | --- |
| a second read inside the time to live never reaches the repository | `a_second_read_inside_the_ttl_is_served_from_the_cache` |
| an entry is served up to its expiry and reloaded at it (exclusive boundary) | `an_entry_is_served_until_its_expiry_and_reloaded_at_it` |
| a write through the cache evicts the entry | `saving_through_the_cache_evicts_the_entry` |
| a failed write still evicts the entry | `a_failed_save_still_evicts_the_entry` |
| a delete through the cache evicts the entry | `deleting_through_the_cache_evicts_the_entry` |
| a miss is not cached | `a_miss_is_not_cached` |
| an error propagates and is not cached | `an_error_is_returned_and_not_cached` |
| an expiry beyond the clock's range is not cached | `an_expiry_beyond_the_clock_range_is_not_cached` |
| `Debug` shows settings and a count, never a value | `debug_shows_the_settings_and_the_count_only` |
| the cache serves what the database stored | `the_cache_serves_what_the_database_stored` (integration) |

Time moves only through a clock double, so no test sleeps and every run is deterministic; entities come from the seeded generator (`TestRng::from_env()` reads `TEST_SEED` and prints the seed when a test fails). The boundary test fails if `<` in `lookup` becomes `<=`, and each eviction test fails if its `invalidate` call is removed, so the suite also holds against mutation testing.

## Unit tests (`src/cache/tests.rs`)

The module is a child of `cache`, so it reaches the private `Snapshot` type and the `entries` field. When the test-support crate already ships an advancing clock, use it instead of the local `ManualClock`.

```rust
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use shared_domain::Clock;
use <context>_domain::{<Entity>, <Entity>Id, <Entity>Repository, RepositoryError};
use test_support::seed::TestRng;

use super::{Cached<Entity>Repository, Snapshot};

const TTL: Duration = Duration::from_secs(60);
const ONE_SECOND: Duration = Duration::from_secs(1);
const CAPACITY: u64 = 16;

/// A clock that moves only when the test advances it.
#[derive(Debug)]
struct ManualClock(Mutex<SystemTime>);

impl ManualClock {
    fn starting_at(time: SystemTime) -> Arc<Self> {
        Arc::new(Self(Mutex::new(time)))
    }

    fn advance(&self, by: Duration) {
        let mut now = self.0.lock().unwrap();
        *now += by;
    }
}

impl Clock for ManualClock {
    fn now(&self) -> SystemTime {
        *self.0.lock().unwrap()
    }
}

/// The wrapped repository: keeps snapshots in a map, counts the reads that reach it and fails on
/// demand.
#[derive(Default)]
struct FakeRepository {
    rows: Mutex<HashMap<<Entity>Id, Snapshot>>,
    reads: AtomicUsize,
    failing: AtomicBool,
}

impl FakeRepository {
    fn reads(&self) -> usize {
        self.reads.load(Ordering::SeqCst)
    }

    fn fail(&self, failing: bool) {
        self.failing.store(failing, Ordering::SeqCst);
    }

    fn check(&self) -> Result<(), RepositoryError> {
        if self.failing.load(Ordering::SeqCst) {
            Err(RepositoryError::Unavailable("fake repository failure".into()))
        } else {
            Ok(())
        }
    }
}

impl std::fmt::Debug for FakeRepository {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("FakeRepository")
    }
}

#[async_trait::async_trait]
impl <Entity>Repository for FakeRepository {
    async fn save(&self, entity: &<Entity>) -> Result<(), RepositoryError> {
        self.check()?;
        self.rows.lock().unwrap().insert(entity.id(), Snapshot::of(entity));
        Ok(())
    }

    async fn delete(&self, id: <Entity>Id) -> Result<(), RepositoryError> {
        self.check()?;
        self.rows.lock().unwrap().remove(&id);
        Ok(())
    }

    async fn find_by_id(&self, id: <Entity>Id) -> Result<Option<<Entity>>, RepositoryError> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        self.check()?;
        let stored = self.rows.lock().unwrap().get(&id).cloned();
        Ok(stored.map(Snapshot::restore))
    }
}

/// The decorator under test with handles on its clock and on the repository it wraps.
struct Subject {
    clock: Arc<ManualClock>,
    inner: Arc<FakeRepository>,
    cache: Cached<Entity>Repository,
}

fn subject_with_ttl(ttl: Duration) -> Subject {
    let clock = ManualClock::starting_at(SystemTime::UNIX_EPOCH);
    let inner = Arc::new(FakeRepository::default());
    let cache = Cached<Entity>Repository::new(Arc::clone(&inner), Arc::clone(&clock), ttl, CAPACITY);
    Subject { clock, inner, cache }
}

fn subject() -> Subject {
    subject_with_ttl(TTL)
}

/// One valid `<Entity>` from the seeded generator of the test.
fn any_entity(rng: &mut TestRng) -> <Entity> {
    test_support::fixture::<Entity>(rng)
}

fn same(left: &<Entity>, right: &<Entity>) -> bool {
    left.id() == right.id() && left.name() == right.name()
}

#[tokio::test]
async fn a_second_read_inside_the_ttl_is_served_from_the_cache() {
    let mut rng = TestRng::from_env();
    let subject = subject();
    let entity = any_entity(&mut rng);
    subject.inner.save(&entity).await.unwrap();

    let first = subject.cache.find_by_id(entity.id()).await.unwrap().unwrap();
    let second = subject.cache.find_by_id(entity.id()).await.unwrap().unwrap();

    assert!(same(&first, &entity) && same(&second, &entity));
    assert_eq!(subject.inner.reads(), 1);
}

#[tokio::test]
async fn an_entry_is_served_until_its_expiry_and_reloaded_at_it() {
    let mut rng = TestRng::from_env();
    let subject = subject();
    let entity = any_entity(&mut rng);
    subject.inner.save(&entity).await.unwrap();
    subject.cache.find_by_id(entity.id()).await.unwrap();

    subject.clock.advance(TTL - ONE_SECOND);
    subject.cache.find_by_id(entity.id()).await.unwrap();
    let reads_before_expiry = subject.inner.reads();
    subject.clock.advance(ONE_SECOND);
    subject.cache.find_by_id(entity.id()).await.unwrap();

    assert_eq!(reads_before_expiry, 1);
    assert_eq!(subject.inner.reads(), 2);
}

#[tokio::test]
async fn saving_through_the_cache_evicts_the_entry() {
    let mut rng = TestRng::from_env();
    let subject = subject();
    let entity = any_entity(&mut rng);
    let renamed = <Entity>::restore(entity.id(), any_entity(&mut rng).name().clone());
    subject.inner.save(&entity).await.unwrap();
    subject.cache.find_by_id(entity.id()).await.unwrap();

    subject.cache.save(&renamed).await.unwrap();
    let found = subject.cache.find_by_id(entity.id()).await.unwrap().unwrap();

    assert!(same(&found, &renamed));
    assert_eq!(subject.inner.reads(), 2);
}

#[tokio::test]
async fn a_failed_save_still_evicts_the_entry() {
    let mut rng = TestRng::from_env();
    let subject = subject();
    let entity = any_entity(&mut rng);
    subject.inner.save(&entity).await.unwrap();
    subject.cache.find_by_id(entity.id()).await.unwrap();

    subject.inner.fail(true);
    let saved = subject.cache.save(&entity).await;
    subject.inner.fail(false);
    subject.cache.find_by_id(entity.id()).await.unwrap();

    assert!(matches!(saved, Err(RepositoryError::Unavailable(_))));
    assert_eq!(subject.inner.reads(), 2);
}

#[tokio::test]
async fn deleting_through_the_cache_evicts_the_entry() {
    let mut rng = TestRng::from_env();
    let subject = subject();
    let entity = any_entity(&mut rng);
    subject.inner.save(&entity).await.unwrap();
    subject.cache.find_by_id(entity.id()).await.unwrap();

    subject.cache.delete(entity.id()).await.unwrap();
    let found = subject.cache.find_by_id(entity.id()).await.unwrap();

    assert!(found.is_none());
}

#[tokio::test]
async fn a_miss_is_not_cached() {
    let mut rng = TestRng::from_env();
    let subject = subject();
    let entity = any_entity(&mut rng);

    let before = subject.cache.find_by_id(entity.id()).await.unwrap();
    subject.inner.save(&entity).await.unwrap();
    let after = subject.cache.find_by_id(entity.id()).await.unwrap();

    assert!(before.is_none());
    assert!(after.is_some_and(|found| same(&found, &entity)));
}

#[tokio::test]
async fn an_error_is_returned_and_not_cached() {
    let mut rng = TestRng::from_env();
    let subject = subject();
    let entity = any_entity(&mut rng);
    subject.inner.save(&entity).await.unwrap();

    subject.inner.fail(true);
    let failed = subject.cache.find_by_id(entity.id()).await;
    subject.inner.fail(false);
    let found = subject.cache.find_by_id(entity.id()).await.unwrap();

    assert!(matches!(failed, Err(RepositoryError::Unavailable(_))));
    assert!(found.is_some());
    assert_eq!(subject.inner.reads(), 2);
}

#[tokio::test]
async fn an_expiry_beyond_the_clock_range_is_not_cached() {
    let mut rng = TestRng::from_env();
    let subject = subject_with_ttl(Duration::MAX);
    let entity = any_entity(&mut rng);
    subject.inner.save(&entity).await.unwrap();

    subject.cache.find_by_id(entity.id()).await.unwrap();
    subject.cache.find_by_id(entity.id()).await.unwrap();

    assert_eq!(subject.inner.reads(), 2);
}

#[tokio::test]
async fn debug_shows_the_settings_and_the_count_only() {
    let mut rng = TestRng::from_env();
    let subject = subject();
    let entity = any_entity(&mut rng);
    subject.inner.save(&entity).await.unwrap();
    subject.cache.find_by_id(entity.id()).await.unwrap();
    subject.cache.entries.run_pending_tasks().await;

    let text = format!("{:?}", subject.cache);

    assert_eq!(text, "Cached<Entity>Repository { ttl: 60s, entries: 1, .. }");
}
```

Notes on the doubles:

- `ManualClock` and `FakeRepository` live in the test module because only this module uses them; move one to the test-support crate when a second module needs it.
- `FakeRepository` stores `Snapshot`s, so it rebuilds a fresh aggregate on every read exactly like a database would, and it fails on demand to prove that errors are neither swallowed nor cached.
- Tests may `unwrap` (the repository's lint configuration allows it in test code); production code never does.

## Integration test (`tests/integration/cache.rs`)

One test over the real persistence adapter proves the wiring of the decorator with the database. Declare the module in `tests/integration/main.rs` (`#[cfg(test)] mod cache;`). Each test gets its own database from `#[sqlx::test]`; the migrator path is the one the existing integration tests use.

```rust
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use <context>_domain::<Entity>Repository as _;
use <context>_infrastructure::{Cached<Entity>Repository, Pg<Entity>Repository};
use sqlx::PgPool;
use test_support::clock::FixedClock;
use test_support::seed::TestRng;

#[sqlx::test(migrator = "shared_infrastructure::persistence::MIGRATOR")]
async fn the_cache_serves_what_the_database_stored(pool: PgPool) {
    let mut rng = TestRng::from_env();
    let cache = Cached<Entity>Repository::new(
        Arc::new(Pg<Entity>Repository::new(pool)),
        Arc::new(FixedClock::at(SystemTime::UNIX_EPOCH)),
        Duration::from_secs(60),
        16,
    );
    let entity = test_support::fixture::<Entity>(&mut rng);

    cache.save(&entity).await.unwrap();
    let found = cache.find_by_id(entity.id()).await.unwrap();

    assert_eq!(found.map(|stored| stored.id()), Some(entity.id()));
}
```

## Running the tests

Run the targets one at a time, the way the calling stage runs `make` (in the background with a log, polled), and record each in the targets-run list:

```bash
make unit-tests
make tests-with-coverage
```

- `make unit-tests` runs only when `make.unit_tests` is non-null; null is recorded `unit-tests: not run (capability absent)`.
- `make tests-with-coverage` runs only when `make.tests_with_coverage` is non-null; it runs the unit and the integration tests and fails when the new adapter is below the repository's coverage floors. Null is recorded `tests-with-coverage: not run (capability absent)`; a run that needs the container engine and cannot reach it is recorded `not run (no Docker)`.
- A failing test is fixed in the adapter or in the test's setup, never by deleting the assertion, ignoring the test or excluding the file from coverage.
