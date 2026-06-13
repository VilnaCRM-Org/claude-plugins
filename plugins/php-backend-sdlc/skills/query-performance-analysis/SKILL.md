---
name: query-performance-analysis
description: Detect N+1 queries, analyze slow queries with the engine-native plan tool (MySQL/MariaDB EXPLAIN or MongoDB explain()), identify missing indexes, and create safe online index migrations, branching on the profile's persistence.engine. Use when optimizing query performance, preventing performance regressions, or debugging slow endpoints. Complements database-migrations, which covers index creation syntax.
---

# Query Performance Analysis & Index Management

## Profile keys consumed

- `persistence.engine`
- `persistence.mapper`
- `framework.name`
- `make.start`
- `make.tests`
- `make.ci`
- `make.load_tests`
- `capabilities.load_testing`
- `quality.infection_msi`

## Context (Input)

Use this skill when:

- New or modified endpoints are slow
- The profiler shows many database queries for a single operation
- Need to detect N+1 query problems
- Query execution time is high
- Slow-query warnings appear in the engine's slow log / profiler
- Performance regression after code changes
- Planning safe index migrations for production
- Need to verify index effectiveness

## Engine branching (read this first)

This skill branches on `persistence.engine`:

| `persistence.engine` | Plan tool | Slow-query capture | Index build |
| --- | --- | --- | --- |
| `mysql` \| `mariadb` | `EXPLAIN` / `EXPLAIN ANALYZE` (Path A) | slow query log | online DDL (`ALGORITHM=INPLACE`) |
| `mongodb` | `explain("executionStats")` (Path B) | database profiler | online by default (4.2+) |
| `postgresql` | `EXPLAIN (ANALYZE, BUFFERS)` | `pg_stat_statements` | `CREATE INDEX CONCURRENTLY` |

For `postgresql`, follow Path A's procedure conceptually with the tools
above; the symptoms and decision rules are the same.

The N+1 fix branches on `persistence.mapper` (`doctrine-orm` vs
`doctrine-odm`) — see Issue 1.

## Task (Function)

Analyze query performance, detect N+1 issues, identify missing indexes,
and create safe online index migrations with verification steps.

**Success criteria**:

- N+1 queries detected and fixed
- Slow queries identified with plan analysis (EXPLAIN / explain())
- Missing indexes detected and added
- Query performance meets the thresholds below (<100ms reads, <500ms writes)
- Index migrations are safe for production (minimal downtime)
- Performance regression tests added

---

## TL;DR - Quick Performance Checklist

**Before merging code:**

- [ ] Run the endpoint with the profiler — check query count
- [ ] No N+1 queries (queries in loops)
- [ ] Slow queries (>100ms) analyzed with the engine's plan tool
- [ ] Missing indexes identified and added
- [ ] Eager loading / reference priming used where appropriate
- [ ] Query count reasonable for the operation (<10 queries ideal)
- [ ] Performance test added to prevent regression

**When adding indexes:**

- [ ] Index covers actual query patterns
- [ ] Composite index field order correct (leftmost-prefix for SQL, ESR for MongoDB)
- [ ] Index build is online/non-blocking
- [ ] Verification steps included
- [ ] Index usage confirmed with the plan tool

---

## Quick Start — Path A: MySQL/MariaDB (`persistence.engine: mysql | mariadb`)

### Step 1: Enable the slow query log

Connect to the database container (find the service name with
`docker compose ps`):

```bash
docker compose exec <db-service> mariadb -u root -p<password> <db>
```

```sql
-- Enable slow query log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0.1;  -- Log queries slower than 100ms
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- Verify settings
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';
```

### Step 2: Run your endpoint

Boot the service with the target mapped by `make.start`, then hit the
endpoint under test, e.g. `curl -s https://localhost/api/<resource>`.

### Step 3: Analyze query patterns

```sql
-- View recent slow queries (MariaDB)
SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;
```

When `framework.name` is `symfony`, the web profiler
(`https://localhost/_profiler`) shows per-request query count and timing.

### Step 4: Check for performance issues

**N+1 symptoms**: same query executed many times; query count grows with
data size; queries inside `foreach` loops.

**Slow-query symptoms**: execution time >100ms; EXPLAIN shows
`type: ALL` (full table scan) or `key: NULL`; high `rows` vs actual
returned rows; `Extra: Using filesort / Using temporary`.

### Step 5: Disable the slow query log (production)

```sql
SET GLOBAL slow_query_log = 'OFF';
```

---

## Quick Start — Path B: MongoDB (`persistence.engine: mongodb`)

### Step 1: Enable the database profiler

Connect with `mongosh` through the database container:

```bash
docker compose exec <db-service> mongosh "<connection-uri>"
```

```bash # profile-example
# Upstream reference repo (engine: mongodb, mapper: doctrine-odm):
docker compose exec database mongosh "mongodb://user:password@localhost:27017/db"
```

```javascript
// Profile operations slower than 100ms
db.setProfilingLevel(1, { slowms: 100 })

// Verify
db.getProfilingStatus()
```

### Step 2: Exercise the endpoint under the profiler

Boot the service with the target mapped by `make.start`, then hit the
endpoint under test, e.g. `curl -s https://localhost/api/<resource>`.

### Step 3: Inspect profiled operations and explain plans

```javascript
// View recent slow operations
db.system.profile.find().sort({ ts: -1 }).limit(10)

// Explain a suspect query
db.<collection>.find({ status: "active" }).explain("executionStats")
```

When `framework.name` is `symfony`, the web profiler also lists ODM
queries per request.

### Step 4: Spot N+1 and collection-scan symptoms

**N+1 symptoms**: identical `find` on a referenced collection repeated
per parent document; query count grows with data size.

**Slow-query symptoms**: `winningPlan` stage is `COLLSCAN` (collection
scan) instead of `IXSCAN`; `totalDocsExamined` much larger than
`nReturned` (ratio near 1 is ideal); high `executionTimeMillis`; a
`SORT` stage means an in-memory sort with no supporting index.

### Step 5: Disable the profiler (production)

```javascript
db.setProfilingLevel(0)
```

---

## Common Performance Issues

### Issue 1: N+1 Queries

**Detection**: 100+ queries for 100 records.

**Fix branches on `persistence.mapper`.**

`doctrine-orm` — eager loading with the QueryBuilder:

```php
// ❌ BAD: N+1 problem
$orders = $repository->findAll();  // 1 query
foreach ($orders as $order) {
    $customer = $order->getCustomer();  // N queries if lazy loaded!
}

// ✅ GOOD: eager loading
$qb = $this->createQueryBuilder('o');
$qb->leftJoin('o.customer', 'c')
   ->addSelect('c');  // fetch the association in the same query
$orders = $qb->getQuery()->getResult();
```

`doctrine-odm` — prime references so they are batch-fetched:

```php
// ✅ GOOD: prime the reference (one extra query, not N)
$qb = $this->createQueryBuilder()
    ->field('customer')->prime(true);
$orders = $qb->getQuery()->execute();
```

### Issue 2: Slow query without an index

**Detection (Path A)**: EXPLAIN shows `type: ALL`, execution time >100ms.

```sql
EXPLAIN SELECT * FROM orders WHERE customer_email = 'test@example.com';
-- type: ALL or key: NULL → add an index
```

**Detection (Path B)**: explain shows `COLLSCAN`.

```javascript
db.orders.find({ customerEmail: "test@example.com" }).explain("executionStats")
// winningPlan stage COLLSCAN → add an index
```

**Fix (`doctrine-orm`)** — index in a migration or the XML mapping:

```php
// migration up()
$this->addSql('CREATE INDEX idx_orders_customer_email ON orders (customer_email)');
```

```xml
<!-- config/doctrine/<Entity>.orm.xml -->
<indexes>
    <index name="idx_customer_email" columns="customer_email"/>
</indexes>
```

**Fix (`doctrine-odm`)** — index in the ODM XML mapping, then sync:

```xml
<!-- config/doctrine/<Document>.mongodb.xml -->
<indexes>
    <index>
        <key name="customerEmail" order="asc"/>
    </index>
</indexes>
```

```bash
docker compose exec <php-service> bin/console doctrine:mongodb:schema:update
```

See [database-migrations](../database-migrations/SKILL.md) for the full
migration workflow and syntax.

### Issue 3: Missing indexes on filtered fields

**Detection**: queries filter/sort on fields without indexes.

**Common patterns needing indexes**:

- Filter fields: `email = ?`, `status = ?`
- Sort fields: `created_at DESC`
- Composite filters: `status = ? AND type = ?`
- Foreign keys / reference fields

**Composite index field order — decision rules**:

- SQL (Path A): **leftmost-prefix rule** — the index `(status, id)`
  serves `WHERE status = ?` and `WHERE status = ? AND id > ?`, but NOT a
  query filtering only on `id`.
- MongoDB (Path B): **ESR rule** — order keys Equality, then Sort, then
  Range: `{ status: 1, createdAt: -1, amount: 1 }` for
  `status = ?` + sort on `createdAt` + range on `amount`.

**Cursor pagination on a UUID/ULID id**: pagination with a filter needs a
composite index `(filter_field, id)` so the cursor seek
(`WHERE status = ? AND id > ?` / `{ status, _id: { $gt } }`) stays on the
index.

---

## Performance Thresholds

| Operation                  | Target | Max acceptable |
| -------------------------- | ------ | -------------- |
| GET single                 | <50ms  | 100ms          |
| GET collection (100 items) | <200ms | 500ms          |
| POST/PATCH/PUT             | <100ms | 300ms          |
| Query count per endpoint   | <5     | 10             |

These are skill defaults, not profile keys: a project may tighten them,
never relax them.

---

## Safe Index Migrations

### Path A: MySQL/MariaDB online DDL

MariaDB 11.4+ / MySQL 8 support online DDL: most index operations are
non-blocking with `ALGORITHM=INPLACE`, and InnoDB allows concurrent
reads/writes during the build. Large tables may still take brief locks at
start/end — schedule builds during low-traffic periods.

```php
// migration with online DDL
public function up(Schema $schema): void
{
    $this->addSql('CREATE INDEX idx_orders_customer_email ON orders (customer_email) ALGORITHM=INPLACE LOCK=NONE');
}
```

**Production strategy**:

1. Create the migration with the index (see [database-migrations](../database-migrations/SKILL.md))
2. Use `ALGORITHM=INPLACE LOCK=NONE` for non-blocking creation
3. Schedule during low traffic for large tables
4. Run the migration (`docker compose exec <php-service> bin/console doctrine:migrations:migrate`)
5. Verify the index exists: `SHOW INDEX FROM <table>`
6. Verify the index is used: re-run `EXPLAIN` on the queries
7. Measure the performance improvement

### Path B: MongoDB online index builds

MongoDB 4.2+ builds all indexes with an online, non-blocking process —
there is no `ALGORITHM` clause to choose. Builds on very large
collections still consume I/O; schedule them during low traffic.

**Production strategy**:

1. Declare the index in the ODM XML mapping (keeps code and schema in sync)
2. Apply it: `docker compose exec <php-service> bin/console doctrine:mongodb:schema:update`
3. Verify the index exists: `db.<collection>.getIndexes()`
4. Verify it is used: `explain("executionStats")` shows `IXSCAN` and a
   `totalDocsExamined`/`nReturned` ratio near 1
5. Measure the performance improvement

---

## Performance Testing

Add regression tests that assert query count and latency:

```php
final class ResourceEndpointPerformanceTest extends ApiTestCase
{
    public function testNoNPlusOneQueries(): void
    {
        for ($i = 0; $i < 50; $i++) {
            $this->createFixture();
        }

        $this->enableQueryCounter();
        $this->client->request('GET', '/api/<resource>');

        $queryCount = $this->getQueryCount();
        $this->assertLessThan(10, $queryCount, 'N+1 query detected!');
    }

    public function testEndpointPerformance(): void
    {
        $start = microtime(true);
        $this->client->request('GET', '/api/<resource>');
        $duration = (microtime(true) - $start) * 1000;

        $this->assertLessThan(200, $duration, "Too slow: {$duration}ms");
    }
}
```

Run them via the target mapped by `make.tests`. New tests must keep the
mutation score at or above `quality.infection_msi` (canonical default
100 — raise-only: a profile may tighten this floor, never lower it).

---

## Quick Commands Reference

### Path A: MySQL/MariaDB

```sql
SET GLOBAL slow_query_log = 'ON';                 -- enable slow log
SET GLOBAL long_query_time = 0.1;
SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;
SHOW INDEX FROM <table>;                          -- list indexes
EXPLAIN SELECT ...;                               -- query plan
EXPLAIN ANALYZE SELECT ...;                       -- plan with real timings
SET GLOBAL slow_query_log = 'OFF';                -- IMPORTANT in production
```

```bash
# validate ORM mapping vs schema
docker compose exec <php-service> bin/console doctrine:schema:validate
```

### Path B: MongoDB

```javascript
db.setProfilingLevel(1, { slowms: 100 })          // enable profiler
db.system.profile.find().sort({ ts: -1 }).limit(10)
db.<collection>.getIndexes()                      // list indexes
db.<collection>.find({...}).explain("executionStats")
db.setProfilingLevel(0)                           // IMPORTANT in production
```

```bash
# apply ODM-mapped indexes
docker compose exec <php-service> bin/console doctrine:mongodb:schema:update
```

---

## Workflow Integration

**Use after**:

- [api-platform-crud](../api-platform-crud/SKILL.md) — after creating endpoints
- [database-migrations](../database-migrations/SKILL.md) — after adding entities/documents

**Use before**:

- [load-testing](../load-testing/SKILL.md) — optimize before load testing
  (gated by `capabilities.load_testing` and the target mapped by `make.load_tests`)
- [ci-workflow](../ci-workflow/SKILL.md) — validate via the target mapped by `make.ci`

**Related skills**:

- [testing-workflow](../testing-workflow/SKILL.md) — add performance tests
- [documentation-sync](../documentation-sync/SKILL.md) — document performance changes

**This skill vs database-migrations**: this skill identifies **WHAT**
indexes to add (plan analysis, slow logs); database-migrations covers
**HOW** to create them (migration/mapping syntax).

---

## Troubleshooting

**Issue**: can't enable the slow log / profiler

**Solution**: verify database user permissions and that you are connected
to the correct database/container (check `docker compose ps` for the
service name).

---

**Issue**: EXPLAIN shows `ALL` (or explain() shows `COLLSCAN`) but an
index exists

**Solution**:

1. Verify the index covers the actual query pattern
2. Check composite index field order (leftmost-prefix / ESR)
3. Ensure the query uses the indexed fields exactly (no functions or
   type coercion on the indexed field)
4. The optimizer may legitimately choose a full scan for tiny tables/collections

---

**Issue**: web profiler not showing queries

**Solution** (when `framework.name` is `symfony`): enable the profiler in
dev mode:

```yaml
# config/packages/dev/web_profiler.yaml
web_profiler:
  toolbar: true
  intercept_redirects: false
```

---

## External Resources

- **MySQL EXPLAIN**: <https://dev.mysql.com/doc/refman/8.0/en/explain.html>
- **MariaDB query optimization**: <https://mariadb.com/kb/en/query-optimization/>
- **MongoDB explain results**: <https://www.mongodb.com/docs/manual/reference/explain-results/>
- **MongoDB ESR rule**: <https://www.mongodb.com/docs/manual/tutorial/equality-sort-range-rule/>
- **Doctrine performance tips**: <https://www.doctrine-project.org/projects/doctrine-orm/en/current/reference/improving-performance.html>

---

## Best Practices

### DO ✅

- Use the web profiler in development for every new feature
- Analyze queries with the engine's plan tool before deploying
- Add performance tests to prevent regressions
- Use eager loading (ORM) / reference priming (ODM) to prevent N+1
- Create indexes for frequently filtered/sorted fields
- Verify index usage after creation (EXPLAIN / explain())

### DON'T ❌

- Leave the slow log / profiler enabled in production at a low threshold
- Add indexes without analyzing query patterns
- Ignore N+1 warnings (they compound quickly)
- Skip plan analysis before adding indexes
- Forget to verify the index is actually used after creation
- Add indexes on every field (write overhead, index explosion)
