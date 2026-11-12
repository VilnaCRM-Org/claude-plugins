# Make targets

The Makefile prints every target with its help text. This reference names, for each gate, the target that passes it, the stage of `make ci` that runs it and the Bats file that holds its negative test.

The ordered list of gate targets is not repeated here. It lives in one place, the verification section of `AGENTS.md`, and `make ci-list` prints it.

## Gate targets: passing run and negative test

A gate target has its negative test in the Bats suite and no second passing run there. The passing run is the stage of `make ci` named below and the CI job of the gate, so the suite does not repeat it. Stage 7 holds the suite itself.

| Gate | Target | Passing run | Negative test (Bats file) |
| --- | --- | --- | --- |
| G1 | `format-check` | stage 2 of `make ci` | `make_quality_gates.bats` (unformatted lines appended to `xtask/src/main.rs`) |
| G2 | `static-analysis` | stage 2 | `make_quality_gates.bats` (an `unwrap`; a `SystemTime::now()` call; a suppression without a reason; a broken intra-doc link, which rustdoc rejects) |
| G3 | `complexity` | stage 2 | `make_quality_gates.bats` (one test per limit: a six-parameter function; a function over the line limit; a function nested six levels deep; a function over the cognitive-complexity limit) |
| G4 | `architecture` | stage 2 | `make_quality_gates.bats` (the checker's fixture workspace) |
| G5 | `validate-manifest` | stage 2 | `make_quality_gates.bats` (version changed without a lock update) |
| G6 | `check-requirements` | stage 2 | `make_quality_gates.bats` (`DATABASE_URL=mysql://x`) |
| G7 | `check-security` | stage 2 | `make_quality_gates.bats` (one test per policy) |
| G8 | `unused-dependencies` | stage 2 | `make_quality_gates.bats` (a misplaced dependency) |
| G9 | `secrets-scan` | stage 1 | `make_security.bats` (a key pair generated at test time; a key that exists only in the history) |
| G10 | `image-scan` | stage 6 | `make_security.bats` (a vulnerable fixture image) |
| G11 | `doc-tests`, `tests-with-coverage` | stage 3 | `make_tests.bats` (a failing test appended to `xtask`, run by `unit-tests`; a failing documentation example appended to the test-support crate, run by `doc-tests`) |
| G12 | `tests-with-coverage` | stage 3 | `make_tests.bats` (a failing integration test) |
| G13 | `e2e-tests` | stage 3 | `make_tests.bats` (a feature with an undefined step; the same step in a scenario tagged `@allow.skipped`) |
| G14 | `tests-with-coverage` | stage 3 | `make_tests.bats` (an uncovered function) |
| G15 | `mutation-tests-diff` | stage 5 | `make_tests.bats` (an uncovered function: a `MISSED` line) |
| G16 | `bats` | stage 7 | `make_general.bats` (a failing suite fixture) |
| G17 | `validate-contract-snapshots` | stage 4 | `make_contracts.bats` (a changed snapshot per file) |
| G18 | `validate-openapi-spec` | stage 4 | `make_contracts.bats` (an operation description removed) |
| G19 | `openapi-diff` | stage 4 | `make_contracts.bats` (a required response property removed) |
| G20 | `graphql-diff` | stage 4 | `make_contracts.bats` (a field removed; the same change approved with `BREAKING_CHANGE_APPROVED=true`; a base ref that does not exist) |
| G21 | `schemathesis-validate` | stage 6 | `make_contracts.bats` (an undocumented path added) |
| G22 | `smoke-load-tests` | stage 6 | `make_load_tests.bats` (a budget that cannot be met; a scenario whose check cannot pass) |
| G23 | `lint-repo` | stage 1 | `make_repository.bats` (one test per linter) |
| G24 | `lint-load-tests` | stage 1 | `make_load_tests.bats` (a script with `console.log` and `==`) |
| G25 | `validate-configuration` | stage 1 | `make_quality_gates.bats` (a comment appended to `clippy.toml`) |
| G26 | `docs-check` | stage 2 | `make_repository.bats` (an unknown target cited in `README.md`) |
| G27 | `validate-architecture-model` | stage 1 | `make_repository.bats` and `check_architecture_model.bats` |
| G28 | `check-commit-message` | CI only (pull-request job `title`) | `make_hooks_and_commits.bats` (each rejected example) |
| G29 | `check-crate-isolation` | stage 2 | `make_quality_gates.bats` (a function that breaks the build of one crate alone) |
| G30 | `validate-sqlx-metadata` | stage 3 | `make_tests.bats` (one file of `.sqlx/` removed; a file of `.sqlx/` that no query generates, which `scripts/check-sqlx-metadata.sh` turns from a warning of `sqlx-cli` into a failure) |
| G31 | `validate-invariants` | stage 1 | `make_repository.bats` and `check_invariants.bats` (one test per rule) |
