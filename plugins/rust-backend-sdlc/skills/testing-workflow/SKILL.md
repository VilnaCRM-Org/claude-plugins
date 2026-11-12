---
name: testing-workflow
description: Use when writing, running or debugging the tests of a Rust service at any level - sibling tests.rs unit tests, the per-crate integration binary, the cucumber end-to-end scenarios under features/, the two coverage floors, surviving mutants and the deterministic test seeds - or when one failing test must be reproduced alone. Skip the mutation section when capabilities.mutation_testing is false and the load section when capabilities.load_testing is false, each recorded as a SKIPPED line. Not for running the repository gates stage by stage (use verification-workflow), not for writing a K6 scenario or a latency budget (use load-testing) and not for the catalogue of all quality bars (use quality-standards).
---

# Testing Workflow

## Profile keys consumed

- `make.unit_tests` — the database-free target for the unit and documentation tests; the only test target that may run beside other work.
- `make.integration_tests` — the database-backed target for the integration binary of every crate.
- `make.tests_with_coverage` — the database-backed gate target that runs the unit and integration tests once under instrumentation and enforces the two coverage floors.
- `make.e2e_tests` — the database-backed target for the end-to-end scenarios.
- `make.mutation_tests_diff` — the database-backed gate target that mutates the code changed against the base ref.
- `make.setup_test_db` — the database-backed target that drops, creates and migrates the test database; it runs before the single raw test call.
- `quality.coverage_lines` — the line-coverage floor; its only legal value is 100.
- `quality.coverage_functions` — the function-coverage floor; its only legal value is 100.
- `quality.max_surviving_mutants` — the ceiling on missed plus timed-out mutants; its only legal value is 0.
- `capabilities.mutation_testing` — true runs the mutation section; false skips it.
- `capabilities.load_testing` — true hands load work to the load-testing skill; false skips the load section.

## Repository precedence

Read `.claude/skills/testing-workflow/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line.

The repository skill holds the test rules of its own tree (where tests live, how the seeded generator is bound, which fakes and fixtures exist). Where its wording differs from the Steps below, follow it and write the difference into the `precedence:` line of the evidence; a precedence note is not a degrade note and does not change the verdict. One spelling stays fixed even where the repository skill writes it shorter: the single raw test call keeps the Makefile's own test-environment prefix `env -u DATABASE_URL`, so a `DATABASE_URL` exported in the shell never points a test at the development database. When the repository skill is absent, the Steps apply in full and the evidence records `source: plugin` instead of `source: repo+plugin`.

## Context

- **Unit tests** live in a sibling `tests.rs`: the module file `src/<module>.rs` ends with `#[cfg(test)]` followed by `mod tests;`, and its tests live in `src/<module>/tests.rs`. A module never holds an inline test block. Shared fakes, fixtures and the seeded generator live in the workspace's test-support crate under `tests/support/`. `make.unit_tests` runs these tests and the documentation tests without any backing service.
- **Integration tests** of a crate form one binary whose root is `<crate>/tests/integration/main.rs`. The root declares one module per concern (for example `mod repository;`), and every test receives its own freshly migrated database (`#[sqlx::test]` with the workspace migrator), so no state is shared between tests. `make.integration_tests` runs them against the compose database and the other backing services.
- **End-to-end tests** are cucumber scenarios: Gherkin `.feature` files under `features/`, step definitions in the end-to-end test crate under `tests/e2e/`, one database per scenario. The runner fails on every skipped or undefined step. It uses its own harness, so a scenario runs only through `make.e2e_tests`, never through the single raw call.
- **Coverage** comes from `make.tests_with_coverage`: one instrumented run of the unit and integration tests that writes `target/coverage/lcov.info` and enforces the floors set in the repository's protected `make/gates.mk`. End-to-end scenarios do not count, so a branch reached only over HTTP still needs a unit or integration test.
- **Mutation testing** comes from `make.mutation_tests_diff`: it mutates only the `*.rs` code that differs between the merge base and the working tree (tracked files only). The mutation tool exits 2 for a missed mutant and 3 for a timed-out one and writes its results to `mutants.out/`.
- **Deterministic seeds.** `TEST_SEED` (the workspace's seeded generator) and `PROPTEST_RNG_SEED` (property tests) are recorded in the `[env]` table of the protected `.cargo/config.toml`, so every run through the mapped targets draws the same data; a value already set in the caller's environment wins. A test that draws seeded data binds `let mut rng = TestRng::from_env();` as its first statement and keeps it until the test ends; helpers take `&mut TestRng` and never create one. The generator prints `TEST_SEED=<seed>` only when it is dropped while the test panics.
- **One shared test database.** `make.setup_test_db`, `make.integration_tests`, `make.tests_with_coverage`, `make.e2e_tests`, `make.mutation_tests_diff` and the single raw call all use the one compose test database, and each of the five targets prepares or resets it first, so these DB-backed targets run serialized, one at a time. `make.unit_tests` is the only database-free test target.

## Task

Write the tests a change needs at the lowest level that can observe each behaviour, run the touched levels through the mapped targets in risk order with every database-backed target alone, hold the coverage floors and the surviving-mutant ceiling, reproduce a single failing test with the one raw call when a target's log is not enough, and report the targets-run list, the evidence block and the verdict line.

## Success criteria

1. Every new or changed branch of production code has a test at the lowest level that observes it, in the location the Context names.
2. The target mapped by `make.tests_with_coverage` exited 0 and `target/coverage/lcov.info` meets both floors in integer arithmetic: 100 × lines hit ≥ `quality.coverage_lines` × lines found, and 100 × functions hit ≥ `quality.coverage_functions` × functions found.
3. With `capabilities.mutation_testing` true, missed plus timed-out mutants ≤ `quality.max_surviving_mutants`, or the row is `not run (not changed)` under the run rule of step 6; with it false, the evidence holds `SKIPPED: capabilities.mutation_testing is false`.
4. No two database-backed targets, and no database-backed target and the raw call, overlapped in time.
5. The only test call outside `make` was the single raw form, run after `make.setup_test_db`.
6. No coverage exclusion, mutant skip, ignored test or weakened assertion was added, and no protected file changed.
7. The targets-run list, the evidence block and the verdict line are printed.

## Steps

### 1. Resolve the profile

Read the eleven keys above from `.claude/rust-sdlc.yml`. A missing or unreadable profile stops with the escalation block and `recommended_action: run /rs-sdlc-setup on the default branch and commit the result`. Then branch before any run:

- A `make.*` key that is non-null: its target runs where step 3, 4, 5 or 6 orders it. A `make.*` key that is null: record that target `not run (capability absent)` (degrade D1) and never substitute a raw command for it. A null `make.tests_with_coverage` leaves the two floors unverified, which is a degrade note and never a PASS.
- `make.setup_test_db` null: the single raw call of step 4 is unavailable as well, because nothing prepares its database; debug through the mapped targets and their logs only.
- `capabilities.mutation_testing` true: run step 6. False: skip step 6 with its `SKIPPED:` line.
- `capabilities.load_testing` true or false: step 7 names both branches.
- `quality.coverage_lines`, `quality.coverage_functions` and `quality.max_surviving_mutants` always hold 100, 100 and 0 (the profile validator rejects any other value); read them as the bounds of steps 5 and 6.

### 2. Write each test at the right level

| Behaviour to prove | Level | Location | Run by |
| --- | --- | --- | --- |
| a domain rule, a value object, a handler's decision with fakes behind its ports | unit | `src/<module>/tests.rs` next to the module | `make.unit_tests` |
| an adapter against the real database or a backing service, a migration | integration | `<crate>/tests/integration/<concern>.rs`, declared in `<crate>/tests/integration/main.rs` | `make.integration_tests` |
| an HTTP or GraphQL behaviour as a client sees it | end-to-end | a scenario in a `.feature` file under `features/`, its steps under `tests/e2e/` | `make.e2e_tests` |

1. Choose the lowest level that observes the behaviour; add a higher level only for what exists only there (routing, serialization, the problem document, a migration).
2. Give every branch a test that fails when the branch is mutated: assert the returned value and the observable side effect, not only that the call succeeded.
3. Draw data through the fixtures from the seeded generator bound in the test's first statement; never hard-code a value that a rule depends on.
4. A property test (`proptest!`) runs under `PROPTEST_RNG_SEED`. Turn the shrunk input of a failing property into an explicit unit test in the same `tests.rs`, so that case stays covered whatever the seed.
5. Read time and identifiers through the `Clock` and `UuidGenerator` fakes, never from the system clock or a random identifier.
6. A new step of an end-to-end scenario gets its step definition in the same change; an undefined or skipped step fails the run.

A unit test in its sibling file and an integration test in its binary (the crate paths, fixture names and migrator path are the reference template's; use the repository's own):

```rust # profile-example
// crates/<group>/<context>/domain/src/<entity>.rs ends with:
#[cfg(test)]
mod tests;

// crates/<group>/<context>/domain/src/<entity>/tests.rs
use test_support::fixture::{<entity>, <entity>_name};
use test_support::seed::TestRng;

#[test]
fn a_renamed_entity_reports_its_new_name() {
    let mut rng = TestRng::from_env();
    let mut entity = <entity>(&mut rng);
    let name = <entity>_name(&mut rng);

    entity.rename(name.clone());

    assert_eq!(entity.name(), &name);
}

// crates/<group>/<context>/infrastructure/tests/integration/main.rs
//! Integration tests of the <context> adapters; each test runs in its own database.
#[cfg(test)]
mod repository;

// crates/<group>/<context>/infrastructure/tests/integration/repository.rs
#[sqlx::test(migrator = "shared_infrastructure::persistence::MIGRATOR")]
async fn a_saved_entity_is_found_by_its_id(pool: PgPool) {
    let mut rng = TestRng::from_env();
    let repository = Pg<Entity>Repository::new(pool);
    let entity = <entity>(&mut rng);

    repository.save(&entity).await.unwrap();

    assert_eq!(repository.find_by_id(entity.id()).await.unwrap(), Some(entity));
}
```

### 3. Run the touched levels in risk order

1. Run in this order and only the levels the change touches: `make.unit_tests`, then `make.integration_tests`, then `make.e2e_tests`, then `make.tests_with_coverage` (always when production code changed, step 5), then the mutation section (step 6).
2. Run each target as [verification-workflow](../verification-workflow/SKILL.md) prescribes: `make <target>` with no option, in the background with its log under `target/rust-sdlc/logs/`, waited for through the completion notice or `common.sh wait_log`, and in container mode with that skill's suffix variable and container precondition.
3. Database rule: start a database-backed target only after the previous one has written its `RUST_SDLC_EXIT=` line. Never run two of them at once, and never while another session or subagent working in the same checkout runs one. `make.unit_tests` may run beside other work.
4. Classify each run: `RUST_SDLC_EXIT=0` is `passed`; the template's message `This target needs a reachable container engine (docker).` in the log is `not run (no Docker)`, never `failed`; any other non-zero exit is `failed`.

The resolved calls at the reference template (the merge base comes from the invoking stage):

```bash # profile-example
make unit-tests
make integration-tests
make e2e-tests
make tests-with-coverage
make mutation-tests-diff base_ref=<merge-base sha>
```

### 4. Reproduce one failing test alone

1. Take the package name of the crate and the full test name from the failing target's log.
2. Run the target mapped by `make.setup_test_db` (backgrounded, under the database rule).
3. Run the single raw form, the only test command outside `make`:

   ```bash
   env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run -p <crate> <name>
   ```

   In container mode the same call goes through the container route, with the uid and gid resolved once by `id -u` and `id -g` and written as literals:

   ```bash
   docker compose exec -T --user <uid>:<gid> app env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run -p <crate> <name>
   ```

4. The call compiles the crate's test binaries, so it runs in the background with the same log wrapper as a target, and it counts as database-backed under the database rule.
5. The call reaches unit and integration tests only. An end-to-end scenario is re-run through `make.e2e_tests` and read in that log.
6. A failure printed with a `TEST_SEED=<seed>` other than the recorded one comes from a run that set its own seed (for example a scheduled CI run). Neither the mapped targets nor the raw call take a seed argument, so record `TEST_SEED=<seed>` in the evidence, try the recorded seed first, and when the failure does not reproduce hand the seed over through `recommended_action` (rerun with `TEST_SEED` and `PROPTEST_RNG_SEED` both set to it). Never edit `.cargo/config.toml` or `.env.test` to change a seed.
7. After the fix passes in the raw call, re-run the full target that failed; the raw call never replaces a target in the targets-run list.

### 5. Hold the coverage floors

1. Run the target mapped by `make.tests_with_coverage`. Then check both floors against the report, with `<lines floor>` the value of `quality.coverage_lines` and `<functions floor>` the value of `quality.coverage_functions`:

   ```bash
   awk -F: -v floor="<lines floor>" '/^LH:/ {h += $2} /^LF:/ {f += $2} END {exit !(f > 0 && 100 * h >= floor * f)}' target/coverage/lcov.info
   awk -F: -v floor="<functions floor>" '/^FNH:/ {h += $2} /^FNF:/ {f += $2} END {exit !(f > 0 && 100 * h >= floor * f)}' target/coverage/lcov.info
   ```

2. The target exited 0 and both checks exit 0: the floors hold. A missing report, or one without any `LF:` or `FNF:` record, is a failure, never a pass.
3. Otherwise list what no test reaches, file by file:

   ```bash
   awk -F'[:,]' '/^SF:/ {file = substr($0, 4)} /^DA:/ && $3 == 0 {print file ":" $2}' target/coverage/lcov.info
   awk '/^SF:/ {file = substr($0, 4)} /^FNDA:0,/ {print file ": " substr($0, 8)}' target/coverage/lcov.info
   ```

4. Add a test at the lowest level for each uncovered line or function. Code that no test can reach is dead: delete it instead of hiding it from the report.

### 6. Mutation section (gated by `capabilities.mutation_testing`)

- `capabilities.mutation_testing` false: print `SKIPPED: capabilities.mutation_testing is false`, record the mutation target `not run (capability absent)`, and add the degrade note that the surviving-mutant ceiling is unverified. The outcome is at best `SUCCESS-WITH-REPORT`.
- `capabilities.mutation_testing` true but `make.mutation_tests_diff` null: handle it as false, with the degrade note `capabilities.mutation_testing is true but make.mutation_tests_diff is null`.
- `capabilities.mutation_testing` true and the key mapped:
  1. Stage every new `*.rs` file with `git add <file>`: both the run rule's diff and the target's own diff see tracked files only.
  2. Apply the run rule. List the production files the branch changed (a sibling `tests.rs` and anything below a `tests/` directory are test code):

     ```bash
     git diff --name-only <merge-base> -- '*.rs' | grep -vE '(^|/)tests(/|\.rs$)'
     ```

     An empty list records the row `not run (not changed)`, which counts as PASS. A non-empty list runs the target in the first measurement of the run. A later iteration re-runs it only when that iteration's fix touched a production `*.rs` file; otherwise the row carries the previous verdict as `not run (not changed)`.
  3. Run `make <make.mutation_tests_diff> base_ref=<merge-base sha>` in the background, under the database rule.
  4. Measure the survivors, a missing file counting 0:

     ```bash
     cat mutants.out/missed.txt mutants.out/timeout.txt 2>/dev/null | grep -c .
     ```

     The target exited 0 and the count ≤ `quality.max_surviving_mutants`: PASS. A non-zero exit with a count of 0 is measured `≥ 1 (exit <n>)` and fails. A log line `mutation-tests-diff could not run: <reason>` is not a mutant: re-resolve the merge-base sha and run once more; a second such line ends `ESCALATED` with that line as `blocking_finding`.
  5. Kill each survivor with a test. Each line of `missed.txt` names the file, the line and the replacement the tests did not notice:
     - a changed comparison (`>` replaced with `>=`): test the boundary value on both sides;
     - a body replaced with a default (`Ok(())`, `0`, `false`, `Default::default()`): assert the returned value and the side effect through the fakes;
     - a removed negation or a swapped operator: assert both outcomes;
     - a timed-out mutant (listed in `timeout.txt`) usually turns a loop or retry bound into an endless loop: pin the iteration count or the exit condition in a test.
  6. Re-measure under the run rule.

A surviving mutant as `missed.txt` reports it:

```text # profile-example
crates/<group>/<context>/domain/src/<entity>.rs:42:22: replace > with >= in <Entity>::is_overdue
```

### 7. Load section (gated by `capabilities.load_testing`)

- `capabilities.load_testing` true: load scenarios and their budgets belong to [load-testing](../load-testing/SKILL.md); this skill writes no scenario and runs no load target, and the evidence names that hand-over.
- `capabilities.load_testing` false: print `SKIPPED: capabilities.load_testing is false`; no load scenario is written or run.

### 8. Bound the loop and report

1. A failed target starts one iteration: read its log, fix the root cause in the code or the test, re-run that target, then the levels after it. Log `testing iteration <n>/5: <target> -> <result>`. The budget is 5 iterations; inside a stage command it is that stage's `MAX_ITERATIONS=5`, and the counter is never reset.
2. A target that cannot run is never an iteration: `not run (no Docker)`, `not run (no toolchain)` or `not run (ask rule)` ends the skill `ESCALATED` at once (degrades D2 and D3), never remediated and never retried in a loop.
3. A target still failing after iteration 5/5 ends `ESCALATED` with the escalation block below.

## Constraints

- Never add `#[coverage(off)]`, `#[mutants::skip]`, an `#[allow` attribute or `#[ignore]`, and never tag a scenario so that it is skipped; fix the code or the test instead.
- Never add an `exclude_re` or `exclude_globs` entry to `.cargo/mutants.toml`, and never add `--ignore-filename-regex` to the coverage command.
- Never lower `quality.coverage_lines` or `quality.coverage_functions`, and never raise `quality.max_surviving_mutants`.
- Never edit a file that `cargo xtask config-guard --list` prints (the gate commands, the seed table, the mutation and test-runner settings and the test-environment scripts are protected at the reference template); a change that needs one ends `ESCALATED` with `recommended_action: approved-config-change label and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`.
- Never delete a test, weaken an assertion or loosen an expected value to obtain a pass.
- Never run two database-backed targets at the same time, or one of them beside the raw call.
- Never run a test command outside `make` other than the single raw form after `make.setup_test_db`, and never substitute any command for a null `make.*` key.
- Never write an inline test module, share state between tests, or create the seeded generator inside a helper.
- Write values only by profile key; concrete values appear only in fences marked `# profile-example`.

## Verification

1. The diff adds no suppression, exclusion or ignored test (the command prints nothing):

   ```bash
   git diff <merge-base> | grep -nE '^\+.*(#\[(allow|ignore|mutants::skip|coverage\(off\))|exclude_(re|globs)|ignore-filename-regex)'
   ```

2. Every production file in the diff has a matching test change at some level, and the targets-run list shows each touched level `passed` or `not run (<reason>)` with a reason from the closed set `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`.
3. The log timestamps show no two database-backed runs overlapping.

Evidence block, printed once at the end:

```text
skill: testing-workflow
source: repo+plugin | plugin
precedence: <repository rule followed instead of a step of this skill | none>
levels: unit <n> | integration <n> | end-to-end <n> tests added or changed
targets run:
- <target>: passed | failed | not run (<reason>)
coverage: lines <hit>/<found>, functions <hit>/<found> | not run (<reason>)
mutation: <survivors> survivor(s) | SKIPPED: capabilities.mutation_testing is false | not run (not changed)
load: SKIPPED: capabilities.load_testing is false | handed to load-testing
seed: recorded | TEST_SEED=<seed> handed over
degrade notes: <one per line | none>
iteration: <n>/5
testing-workflow: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
```

The verdict is `SUCCESS` when every applicable target passed and no degrade note exists, `SUCCESS-WITH-REPORT` when the only notes are absent capabilities (`not run (capability absent)` or a `SKIPPED:` line), and `ESCALATED` otherwise. A resolved example:

```text # profile-example
- unit-tests: passed
- integration-tests: passed
- tests-with-coverage: passed
- mutation-tests-diff: passed
testing-workflow: SUCCESS
```

When the verdict is `ESCALATED`, print the canonical block with the invoking stage's id and exit string:

```text
=== SDLC ESCALATION ===
stage: <stage-id of the invoking command>
iteration: <n>/5
exit_condition: <exit string of the invoking stage, verbatim>
status: NOT MET
blocking_finding: <file:line of the failing test | target + exit code | surviving mutant line>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human action, for example a rerun with TEST_SEED=<seed> and PROPTEST_RNG_SEED=<seed>>
=== END ===
```
