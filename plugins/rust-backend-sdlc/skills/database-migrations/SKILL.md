---
name: database-migrations
description: Use when a change adds or alters the PostgreSQL schema of a Rust service built on sqlx - a new reversible migration pair under persistence.migrations_dir scaffolded with make create-migration, applied with make migrate, rolled back once, with the sqlx offline query metadata regenerated and validated in the same change, and never an edit to an applied migration. Skip when persistence.engine is null (SKIPPED). Not for choosing which index or query shape a slow read needs (use query-performance-analysis) and not for the repository adapter tests that exercise the new schema (use testing-workflow).
---

# Database Migrations

## Profile keys consumed

- `persistence.engine` — the database engine; null skips this skill, the only legal non-null value selects the sqlx migration path
- `persistence.migrations_dir` — the directory that holds the reversible migration pairs
- `persistence.offline_metadata` — true when the repository commits the sqlx offline query metadata
- `make.create_migration` — scaffolds an empty reversible migration pair
- `make.migrate` — applies every pending migration to the development database
- `make.migrate_rollback` — reverts the most recently applied migration (a template ask rule)
- `make.sqlx_prepare` — regenerates the offline query metadata from a freshly migrated test database
- `make.validate_sqlx_metadata` — proves the committed offline query metadata matches the current queries
- `make.setup_test_db` — drops, creates and migrates the test database from an empty schema

## Applicability gate

Read the profile before any other step and branch:

1. `persistence.engine` is null: the service has no database. Print `SKIPPED: persistence.engine is null`, record the verdict NOT APPLICABLE with that reason and stop; nothing below runs.
2. `persistence.engine` is non-null (the schema admits one engine, PostgreSQL) and `persistence.migrations_dir` is null: the repository keeps no migration directory. When the task changes no schema, print `SKIPPED: persistence.migrations_dir is null` and stop. When the task needs a schema change, stop and hand the calling stage `blocking_finding: persistence.migrations_dir is null` with the recommended action "add the migrations directory, then re-run the plugin's setup command with refresh"; the stage ends `ESCALATED`. Never invent a directory.
3. Both keys are non-null: record the verdict EXECUTE and continue with `## Steps`. Below, `<migrations_dir>` is the value of `persistence.migrations_dir`.

## Context

- **Migrations are plain SQL pairs.** sqlx reads `<version>_<name>.up.sql` and `<version>_<name>.down.sql` from `<migrations_dir>`; the version orders them. The shared infrastructure crate embeds the directory in the service binary at compile time (`sqlx::migrate!`, exposed as `MIGRATOR` in its `persistence.rs`), integration tests run the same migrator (`#[sqlx::test(migrator = …)]`), and the service never migrates on start: migrating is its own step.
- **sqlx checks applied migrations by checksum.** Once a pair has run against a database, changing its file makes the next `make migrate` fail with "previously applied but has been modified". A migration is **applied** when it exists at the merge base the calling stage computed (`<merge-base-sha>`): it reached the default branch, and other environments may have run it. Applied migrations are immutable.
- **Queries are checked at compile time.** `query!`, `query_as!` and `query_scalar!` are verified against the schema. When `persistence.offline_metadata` is true the compiler reads `.sqlx/` instead of a live database, so a schema or query change without regenerated metadata breaks the offline build and the gate behind `make.validate_sqlx_metadata`.
- **`make.migrate_rollback` is an `ask` rule** in the template's `.claude/settings.json`: a person approves it in an interactive session; a headless run receives a permission denial. That denial is degrade row D13: the target is recorded `not run (ask rule)` and the run continues (`SUCCESS-WITH-REPORT`).
- **One database server is shared.** Every target of this skill except `make.create_migration` touches the database, so they run one at a time, each the way the calling stage runs `make` (in the background with a log, polled).
- **Target names.** A non-null `make.*` key maps the target of the same name with `-` for `_` (`make.migrate` maps `make migrate`); a null key means the capability is absent (degrade row D1).
- **Repository rules first.** `AGENTS.md` and the repository's own migration rules (usually with its operations documentation under `docs/`) win over this skill where they are stricter.

## Task

Add one reversible migration pair for the schema change the story needs, prove that it applies, reverts and re-applies, keep the offline query metadata in step with it, and leave the pair (plus `.sqlx/` when tracked) in the working tree for the calling stage's single commit, without touching any applied migration.

## Success criteria

- The change adds exactly one new pair per independent schema change under `<migrations_dir>`; both files are non-empty and the `.down.sql` file undoes the `.up.sql` file in reverse order.
- `git diff --name-status --diff-filter=MDR <merge-base-sha> -- <migrations_dir>` prints nothing: no applied migration was modified, deleted or renamed.
- The targets-run list holds one line per target with a result from the closed set: `passed`, `failed`, or `not run (<reason>)` with the reason `capability absent`, `no Docker` or `ask rule`.
- `make migrate`, the rollback round trip, `make setup-test-db` and, when `persistence.offline_metadata` is true, `make sqlx-prepare` and `make validate-sqlx-metadata` are `passed` or `not run` with a reason; none is `failed`.
- When `persistence.offline_metadata` is true, the regenerated `.sqlx/` files sit in the same change as the pair.

## Steps

The happy path, in order; each target runs only when its key is non-null, one at a time, the way the calling stage runs `make` (step 7 covers the `ask` rule of the rollback):

```bash
make create-migration name=<snake_case>
make migrate
make migrate-rollback
make migrate
make setup-test-db
make sqlx-prepare
make validate-sqlx-metadata
```

1. **Gate.** Apply `## Applicability gate`; stop there on a `SKIPPED:` line.
2. **Read the rules and the newest pair.** Read `AGENTS.md`, the repository's migration rules, and the newest pair in `<migrations_dir>` for its conventions (file naming, constraint names, `IF EXISTS` use).
3. **Name the migration.** The name matches `^[a-z][a-z0-9_]*$`, starts with a verb and names the table, for example `create_<table>` or `add_<column>_to_<table>`. One migration belongs to one bounded context (`<group>/<context>`) and touches only that context's tables.
4. **Create the pair.**
   - `make.create_migration` non-null: run `make create-migration name=<snake_case>` (the target mapped by `make.create_migration`). It writes an empty `.up.sql` and `.down.sql` with a fresh version.
   - `make.create_migration` null: record `create-migration: not run (capability absent)` and write both files by hand with the file-name pattern of the existing pairs and a version greater than every existing version.
5. **Write both files completely before the first apply.**
   - The `.up.sql` file holds the DDL with named constraints. A `NOT NULL` column on an existing table gets a default or a backfill in the same migration.
   - The `.down.sql` file drops exactly what the `.up.sql` file created, in reverse order. A down file that drops a table or column destroys data; say so in the change description.
   - A change the running release cannot tolerate (dropping or renaming a column or table, tightening a constraint) is split expand-then-contract: this change adds, a later change removes once no running release reads the old shape.
   - A new table, as a sketch (`<table>` and `<column>` stand for the names the story needs):

     ```text
     -- <version>_create_<table>.up.sql
     CREATE TABLE <table> (
         id UUID NOT NULL,
         <column> TEXT NOT NULL,
         CONSTRAINT <table>_pkey PRIMARY KEY (id),
         CONSTRAINT <table>_<column>_check CHECK (char_length(<column>) > 0)
     );

     -- <version>_create_<table>.down.sql
     DROP TABLE <table>;
     ```

   - An index on a large table: decide which index with [query-performance-analysis](../query-performance-analysis/SKILL.md). `CREATE INDEX CONCURRENTLY` cannot run inside a transaction, so its migration starts with the sqlx directive line `-- no-transaction`; the statement still runs under the configured statement timeout, which the repository's operations rules tell you how to handle for a long migration.
6. **Apply.** `make.migrate` non-null: run `make migrate`. A failure is fixed in the new pair and `make migrate` runs again: a failed migration rolled back its transaction and is not recorded as applied (a `-- no-transaction` migration has no transaction, so first make its statements safe to repeat, for example with `IF NOT EXISTS`). `make.migrate` null: record `migrate: not run (capability absent)`; step 8 then proves the apply on the test database.
7. **Round trip, exactly once.** `make.migrate_rollback` non-null: run `make migrate-rollback` once, then `make migrate` once to re-apply.
   - Headless run, permission denied: record `migrate-rollback: not run (ask rule)` and `migrate (re-apply): not run (ask rule)`, note that the down file was not executed, and continue. Never retry the denied call and never revert by another command or by hand-written SQL.
   - `make.migrate_rollback` null: record `migrate-rollback: not run (capability absent)` and continue.
   - After step 6 applied the pair to the development database, edit it only after a successful rollback. When no rollback ran, a further change to the pair cannot be applied (the checksum changed): stop and hand the stage `blocking_finding: <file> applied to the development database, rollback not run` with the recommended action "approve `make migrate-rollback` interactively, then re-run the stage"; the stage ends `ESCALATED`.
8. **Prove the whole chain from empty.** `make.setup_test_db` non-null: run `make setup-test-db`; it drops, creates and migrates the test database, so every pair applies in order. Null: record `setup-test-db: not run (capability absent)`.
9. **Offline query metadata.** Branch on `persistence.offline_metadata`:
   - true: change the queries the story needs first (the repository adapter in the `<group>/<context>` infrastructure crate's `persistence.rs`), then run `make sqlx-prepare` (`make.sqlx_prepare`) and keep every changed `.sqlx/` file in the same change as the pair, so the commit that carries the migration carries the metadata too. Then run `make validate-sqlx-metadata` (`make.validate_sqlx_metadata`); a stale or unused file it reports is fixed by following its message and re-running `make sqlx-prepare`. When `make.sqlx_prepare` or `make.validate_sqlx_metadata` is null, record that target `not run (capability absent)` and note that `.sqlx/` may be stale; the PR checks judge it.
   - false: the repository tracks no offline metadata. Record `sqlx-prepare: not run (capability absent)` and `validate-sqlx-metadata: not run (capability absent)`.
10. **Check applied migrations.** Run `git diff --name-status --diff-filter=MDR <merge-base-sha> -- <migrations_dir>`. Any line is a violation: restore the file with `git restore --source=<merge-base-sha> -- <path>` and express the correction as a new pair (back to step 3).
11. **Report** the evidence block of `## Verification` to the calling stage. A target that failed is fixed at its root cause and re-run; each re-run is one iteration of the calling stage's guard (`MAX_ITERATIONS=5`), and on exhaustion the stage escalates with `blocking_finding: make <target> exit <code>`. A target classified `not run (no Docker)` (the template's container-engine message, degrade row D2) is reported as such, never fixed by a workaround; the calling stage decides its outcome.

## Constraints

- Never edit, rename or delete an applied migration; correct it with a new pair.
- Never hand-edit `.sqlx/`; only the target mapped by `make.sqlx_prepare` writes it.
- Never retry a denied `ask` rule, and never replace `make migrate-rollback` with SQL, another target or a direct tool call.
- Never substitute a null target with a direct tool call (the sqlx CLI, a database client or a compiler run); record it `not run (capability absent)`.
- Never run two database-backed targets at the same time, and never run a migration from the service's start-up path.
- Never change a file listed by `cargo xtask config-guard --list` (read the list at runtime) to get a target to pass; a protected change is escalated to a maintainer.
- Never commit; the calling stage commits the pair and `.sqlx/` together.

## Verification

Hand the calling stage this evidence block; it becomes the `evidence or reason` cell of this skill's triage row and feeds the targets-run list:

```text
skill: database-migrations EXECUTE
migration: <migrations_dir>/<version>_<name>.up.sql, <migrations_dir>/<version>_<name>.down.sql
applied migrations: unchanged (git diff --name-status --diff-filter=MDR <merge-base-sha> printed nothing)
create-migration: passed | not run (capability absent)
migrate: passed | not run (capability absent | no Docker)
migrate-rollback: passed | not run (ask rule | capability absent | no Docker)
migrate (re-apply): passed | not run (ask rule | capability absent | no Docker)
setup-test-db: passed | not run (capability absent | no Docker)
sqlx-prepare: passed | not run (capability absent | no Docker)
validate-sqlx-metadata: passed | not run (capability absent | no Docker)
```

A gated run hands over the single line `SKIPPED: persistence.engine is null` (or `SKIPPED: persistence.migrations_dir is null`) instead. Tests for the new schema and the adapter that reads it follow [testing-workflow](../testing-workflow/SKILL.md).
