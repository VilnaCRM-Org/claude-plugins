# Gate command lines and thresholds. Protected file (protected-config.toml).
FORMAT_CHECK_CMD = cargo fmt --all --check
LINT_PROD_CMD    = cargo clippy --locked --workspace --lib --bins --all-features -- -D warnings
LINT_ALL_CMD     = cargo clippy --locked --workspace --all-targets --all-features -- -D warnings -A clippy::cognitive_complexity -A clippy::too_many_lines
LINT_RUSTDOC_CMD = env RUSTDOCFLAGS="-D warnings" cargo doc --locked --workspace --no-deps --document-private-items
COMPLEXITY_CMD   = cargo clippy --locked --workspace --lib --bins --all-features -- -A warnings -D clippy::cognitive_complexity -D clippy::too_many_lines -D clippy::excessive_nesting -D clippy::too_many_arguments
ARCH_CMD         = cargo xtask arch $(ARCH_ARGS)
CONFIG_GUARD_CMD = cargo xtask config-guard --base $(base_ref)
MANIFEST_CMD     = cargo metadata --locked --format-version 1 > /dev/null
HACK_CMD         = cargo hack check --workspace --each-feature --locked
DENY_CMD         = cargo deny --locked $(DENY_ARGS) check
DENY_OFFLINE_CMD = cargo deny --locked --offline check bans licenses sources
SHEAR_CMD        = cargo shear --locked
SQLX_CHECK_CMD   = cargo sqlx prepare --workspace --check -- --all-targets --all-features --locked
CHECK_CONFIG_CMD = cargo run --locked --quiet -p service -- check-config
UNIT_CMD         = cargo nextest run --locked --workspace --lib --bins
DOCTEST_CMD      = cargo test --locked --workspace --doc
INTEGRATION_CMD  = cargo nextest run --locked --workspace --test integration
E2E_CMD          = cargo test --locked -p e2e-tests --test e2e
# Coverage of the unit and integration suites (QG-16). This group is the coverage exclusion record of NFR19:
# an exclusion is an `--ignore-filename-regex` alternative added to these commands with a comment that gives
# the reason. The first release has none.
COVERAGE_CLEAN_CMD = cargo llvm-cov clean --workspace
COVERAGE_RUN_CMD   = cargo llvm-cov --no-report nextest --locked --workspace --lib --bins --test integration --profile ci
COVERAGE_LCOV_CMD  = cargo llvm-cov report --lcov --output-path target/coverage/lcov.info
COVERAGE_HTML_CMD  = cargo llvm-cov report --html --output-dir target/coverage
COVERAGE_GATE_CMD  = cargo llvm-cov report --fail-under-lines 100 --fail-under-functions 100
COVERAGE_XML_CMD   = cargo llvm-cov report --cobertura --output-path target/coverage/coverage.xml
MUTANTS_CMD      = env -u CARGO_TARGET_DIR -u CARGO_BUILD_WARNINGS cargo mutants --workspace --cargo-arg=--locked $(if $(MUTANTS_SHARD),--shard $(MUTANTS_SHARD))
OPENAPI_EXPORT_CMD  = cargo run --locked --quiet -p service -- openapi-export --output .github/openapi-spec/spec.yaml
GRAPHQL_EXPORT_CMD  = cargo run --locked --quiet -p service -- graphql-export --output .github/graphql-spec/spec
SNAPSHOT_STATUS_CMD = test -z "$$(git status --porcelain -- .github/openapi-spec .github/graphql-spec)"
SCHEMATHESIS_FLAGS  = --checks all --phases=examples,coverage
export SPECTRAL_FLAGS = --fail-severity=hint
export OASDIFF_FLAGS  = --fail-on ERR
export TRIVY_FLAGS    = --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore
CI_STAGES ?= ci-preflight ci-static-analysis ci-tests ci-contracts ci-mutation ci-delivery ci-cli
CONFIG_CHANGE_APPROVED ?=
BREAKING_CHANGE_APPROVED ?=
