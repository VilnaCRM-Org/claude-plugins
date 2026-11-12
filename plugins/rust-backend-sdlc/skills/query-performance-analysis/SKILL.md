---
name: query-performance-analysis
description: Use when a sqlx query of a Rust service on PostgreSQL is slow, is cancelled by the configured statement timeout, runs once per item of a list (N+1), or a new query needs an index - read EXPLAIN (ANALYZE, BUFFERS) plans, choose indexes, batch reads into one statement, bound result sets, keep compile-time-checked query! macros and their offline metadata current, and prove the plan with integration tests. Skip when persistence.engine is null (SKIPPED). Not for writing the migration that creates the index (use database-migrations) and not for caching a read that is already efficient (use cache-management).
---

# Query Performance Analysis

## Profile keys consumed

- `persistence.engine` — null skips this skill; the only legal non-null value selects the PostgreSQL plan analysis
- `persistence.offline_metadata` — true when the repository commits the sqlx offline query metadata that every changed query must regenerate
- `make.sqlx_prepare` — regenerates the offline query metadata after a query or schema change
- `make.integration_tests` — runs the integration tests that carry the plan and batching evidence

## Applicability gate

Read `persistence.engine` before any other step:

1. Null: the service has no database. Print `SKIPPED: persistence.engine is null`, record the verdict NOT APPLICABLE with that reason and stop; nothing below runs.
2. Non-null (the schema admits one engine, PostgreSQL): record the verdict EXECUTE and continue with `## Steps`.

## Context

- **Where queries live.** Each bounded context keeps its SQL in the repository adapter of its infrastructure crate (`<group>/<context>`, file `persistence.rs`). The shared infrastructure crate's `persistence.rs` builds the pool lazily and sets `statement_timeout` on every connection from the service configuration; read the configured value and its bounds from the repository's environment documentation, never assume them.
- **Compile-time checking.** `query!`, `query_as!` and `query_scalar!` verify the SQL text, the parameter types and the result columns against the schema during the build. When `persistence.offline_metadata` is true the build reads `.sqlx/` instead of a live database, so a changed query text needs regenerated metadata.
- **Plans come from tests, not from a database client.** The plugin runs no database client and no raw SQL session: the list of raw calls is closed. A plan is captured by an integration test that runs `EXPLAIN (ANALYZE, BUFFERS)` through sqlx against the test database, so the evidence is reproducible and lands in the targets-run list.
- **Plans depend on data.** On a near-empty test table PostgreSQL prefers a sequential scan even when an index fits. A plan test therefore disables sequential scans inside its own transaction: it proves that an index *can* serve the predicate and order, not which plan the planner picks at production volume.
- **Timeouts cancel, they do not slow down.** A statement that outlives `statement_timeout` fails with SQLSTATE `57014` (`canceling statement due to statement timeout`); the adapter translates it into the port's unavailable error, and the request fails.
- **Repository rules first.** `AGENTS.md` and the repository's persistence rules win over this skill where they are stricter.

## Task

For every query the change adds or touches: give its predicates and its order an index the plan uses, issue one statement per request instead of one per item, keep the result set bounded so the statement finishes inside the configured timeout, keep the query compile-time checked with current offline metadata, and prove the plan and the batching with integration tests.

## Success criteria

- Every touched production statement is a `query!`, `query_as!` or `query_scalar!` macro, or a `QueryBuilder` that adds values only with `push_bind` for a filter whose shape varies; no value is formatted into SQL text.
- No read path awaits one repository call per item of a collection.
- Every list query carries a `LIMIT` bound from a page value.
- Each frequent filter and order has an index, and a plan test shows `Index Scan`, `Index Only Scan` or `Bitmap Index Scan` on that index.
- When `persistence.offline_metadata` is true, the regenerated `.sqlx/` files sit in the same change as the query.
- The integration tests pass, or the targets-run list records `integration-tests: not run (<reason>)` and the report says the plan evidence is missing.
- The configured statement timeout is unchanged.

## Steps

1. **Gate.** Apply `## Applicability gate`; stop there on the `SKIPPED:` line.
2. **Inventory the statements.** Search the changed infrastructure crates for `query!`, `query_as!`, `query_scalar!`, `sqlx::query` and `QueryBuilder`. Classify each statement as point lookup, filtered list or page, aggregate, or write, and note the columns of its `WHERE`, `JOIN` and `ORDER BY`.
3. **Remove N+1 reads.** An N+1 read is a loop (`for`, or `iter().map(…)` followed by `join_all`) that awaits a repository call per element, or a handler that queries once per row of a page. Replace it with one statement that binds every key as an array, and add a batch method to the domain port when the application needs it (the port stays in the domain crate, the SQL in the infrastructure crate):

   ```rust
   async fn select_by_ids(&self, ids: &[<Entity>Id]) -> Result<Vec<<Entity>>, RepositoryError> {
       // one bind of `uuid[]` holding the raw UUID of every identifier
       let keys: Vec<uuid::Uuid> = ids.iter().map(|id| id.value().as_uuid()).collect();
       let rows = sqlx::query_as!(
           Row,
           "SELECT id, <column> FROM <table> WHERE id = ANY($1)",
           keys.as_slice(),
       )
       .fetch_all(&self.pool)
       .await
       .map_err(translate)?;
       rows.into_iter().map(restore).collect()
   }
   ```

   `Row`, `restore` and `translate` are the adapter's existing row type, row mapping and error translation. A parent with its children is one `JOIN`, not one query per parent. When the caller needs the input order, index the result in a `HashMap` by identifier.
4. **Design the index.** Apply the index rules below, then add the index through a new migration with [database-migrations](../database-migrations/SKILL.md) (it covers `CREATE INDEX CONCURRENTLY` and the transaction directive):
   - A B-tree index serves equality columns first, then one range column, then the sort columns; its column order must match the query's `ORDER BY` for a top-N or keyset read.
   - A primary key or unique constraint already is an index; never duplicate it.
   - PostgreSQL creates no index for a foreign key: a column used in joins or cascading deletes needs its own.
   - A partial index (`WHERE <condition>`) serves a constant predicate; `INCLUDE (<column>)` allows an index-only scan of a narrow read.
   - A column with few distinct values is not indexed alone, and every index costs write time and storage.
   - A substring search (`LIKE '%<text>%'`) cannot use a B-tree index; it needs an extension, which is an architecture decision: hand the stage `blocking_finding: <file>:<line> substring search needs an index extension` and let it escalate.
5. **Bound every result set.** A list query binds its `LIMIT` (and `OFFSET`) from the page value and selects only the columns it maps. A deep `OFFSET` reads and discards every skipped row: prefer keyset pagination (`WHERE (<sort>, id) < ($1, $2) ORDER BY <sort> DESC, id DESC LIMIT $3`) for new reads; changing an existing public paging contract is an API change for [api-contract-development](../api-contract-development/SKILL.md).
6. **Respect the statement timeout.** A statement must finish well inside the configured timeout at production volume. A cancelled statement is fixed by its plan, its index, batching or bounds, never by raising the timeout for the service. A long schema statement (an index build, a backfill) follows the database-migrations skill. Prove boundedness structurally (a `LIMIT` in the SQL, an index in the plan), never with a wall-clock assertion: timings turn tests flaky.
7. **Write the plan test.** In the context's infrastructure crate, add `tests/integration/query_plan.rs` and declare it in `tests/integration/main.rs` as `#[cfg(test)] mod query_plan;`. The SQL text equals the production statement (copy the literal; a drift makes the evidence worthless). `EXPLAIN ANALYZE` executes the statement, so the test runs it in a transaction that it rolls back:

   ```rust
   use sqlx::PgPool;

   /// The plan of the lookup by `<column>`, one line per row of `EXPLAIN`.
   async fn plan_of_lookup(pool: &PgPool, value: &str) -> Vec<String> {
       let mut tx = pool.begin().await.unwrap();
       sqlx::query("SET LOCAL enable_seqscan = off").execute(&mut *tx).await.unwrap();
       let lines = sqlx::query_scalar::<_, String>(
           "EXPLAIN (ANALYZE, BUFFERS) SELECT id, <column> FROM <table> WHERE <column> = $1",
       )
       .bind(value)
       .fetch_all(&mut *tx)
       .await
       .unwrap();
       tx.rollback().await.unwrap();
       lines
   }

   #[sqlx::test(migrator = "shared_infrastructure::persistence::MIGRATOR")]
   async fn the_lookup_by_column_uses_its_index(pool: PgPool) {
       let mut rng = test_support::seed::TestRng::from_env();
       // store representative rows drawn from `rng` through the adapter, then refresh statistics
       sqlx::query("ANALYZE <table>").execute(&pool).await.unwrap();

       let plan = plan_of_lookup(&pool, "<value>").await;

       let uses_index = plan
           .iter()
           .any(|line| line.contains("Index") && line.contains("<table>_<column>_idx"));
       assert!(uses_index, "{}", plan.join("\n"));
   }
   ```

   The migrator path names the shared infrastructure crate's embedded migrations; use the path the existing integration tests use. The generator reads `TEST_SEED`, so a failure prints the seed that reproduces it. The unchecked `sqlx::query` form is acceptable here only because these statements are constant test SQL, never production queries.
8. **Write the batching test.** Next to the plan test, store several entities, call the batch method once and assert that it returns every stored entity, then assert the plan of `= ANY($1)` uses the primary key index.
9. **Regenerate the offline metadata.** Branch on `persistence.offline_metadata`:
   - true: after any change to a production query text or to the schema it reads, run `make sqlx-prepare` (`make.sqlx_prepare`) and keep every changed `.sqlx/` file in the change. `make.sqlx_prepare` null: record `sqlx-prepare: not run (capability absent)` and note that `.sqlx/` may be stale; the PR checks judge it.
   - false: the repository commits no offline metadata and the build checks queries against a live database. Record `sqlx-prepare: not run (capability absent)`.
10. **Run the evidence.** `make.integration_tests` non-null: run `make integration-tests` the way the calling stage runs `make` (in the background with a log, polled, never next to another database-backed target). A failure is fixed at its root cause and re-run; each re-run is one iteration of the calling stage's guard (`MAX_ITERATIONS=5`), and on exhaustion the stage escalates with `blocking_finding: make integration-tests exit <code>`. `make.integration_tests` null: record `integration-tests: not run (capability absent)` and write `plan evidence: not run (capability absent)` in the report; never claim that an index is used. A run classified `not run (no Docker)` (the template's container-engine message, degrade row D2) is reported as such; the calling stage decides its outcome.
11. **Report** the evidence block of `## Verification` to the calling stage.

## Constraints

- Never format or concatenate a value into SQL text; every value is a bind.
- Never raise the configured statement timeout of the service to get a query to pass.
- Never hand-edit `.sqlx/`; only the target mapped by `make.sqlx_prepare` writes it.
- Never assert a wall-clock duration in a test.
- Never open a database client or a raw SQL session outside the integration tests, and never substitute a null target with a direct tool call.
- Never add an index that no query needs, and never edit an applied migration to add one; a new migration carries it.
- Never run two database-backed targets at the same time.

## Verification

Hand the calling stage this evidence block; it becomes the `evidence or reason` cell of this skill's triage row and feeds the targets-run list:

```text
skill: query-performance-analysis EXECUTE
statements: <file>:<line> <lookup | list | aggregate | write> -> <index | batched | bounded | unchanged>
n+1: none found | fixed at <file>:<line> (one statement with = ANY($1))
plan tests: <test name> -> <Index Scan | Index Only Scan | Bitmap Index Scan> on <index>
sqlx-prepare: passed | not run (capability absent | no Docker)
integration-tests: passed | not run (capability absent | no Docker)
```

A gated run hands over the single line `SKIPPED: persistence.engine is null` instead.
