# Stub Makefile of the rust-backend-sdlc test fixture (a template-derived service, identity acme/rust-template).
# It keeps the template's target names, `##` help texts, prerequisites, CI_*_TARGETS stages and HOST check, but
# every gate recipe is a stub that prints its name: nothing here runs cargo, a database or a container.
include make/gates.mk

.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -euo pipefail -c

ifeq ($(origin PROJECT_NAME),undefined)
PROJECT_NAME := $(or $(COMPOSE_PROJECT_NAME),$(shell basename "$(CURDIR)" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_\n-' '-'))
endif
export COMPOSE_PROJECT_NAME ?= $(PROJECT_NAME)
export HOST_UID ?= $(shell id -u)
export HOST_GID ?= $(shell id -g)
export APP_IMAGE ?= $(PROJECT_NAME)-app:prod
export LOAD_TEST_APP_PORT ?= 18081
export DOCKER ?= docker
export DOCKER_COMPOSE ?= docker compose

EXEC_ENV := TEST_SEED PROPTEST_RNG_SEED CONFIG_CHANGE_APPROVED CARGO_BUILD_WARNINGS DATABASE_STATEMENT_TIMEOUT
EXEC :=
ifneq ($(filter 1 true,$(RUN_IN_CONTAINER)),)
ifeq ($(strip $(CI))$(strip $(IN_DEV_CONTAINER)),)
EXEC := $(DOCKER_COMPOSE) exec -T --user $(HOST_UID):$(HOST_GID) $(foreach v,$(EXEC_ENV),-e $(v)) app
endif
endif

# Caller-settable variables (a value set by the caller always wins).
RUN_IN_CONTAINER ?=
CI ?=
IN_DEV_CONTAINER ?=
DEPS ?= database localstack
base_ref ?= origin/main
SCHEMATHESIS_URL ?= http://localhost:$(LOAD_TEST_APP_PORT)
scenario ?=
name ?=
group ?=
context ?=
BMALPH_PLATFORM ?= claude-code
BMALPH_DRY_RUN ?= false

# Helpers of the recipes. STUB stands in for every real gate command of the template.
REQUIRE_DOCKER = @$(DOCKER) info >/dev/null 2>&1 || { echo 'This target needs a reachable container engine (docker).' >&2; exit 2; }
STUB = @printf 'stub: %s%s\n' '$@' '$(if $(EXEC), (container))'

# The seven stages of `make ci`, in order; `ci-list` prints the targets of all of them.
CI_PREFLIGHT_TARGETS := validate-configuration validate-invariants secrets-scan lint-repo lint-load-tests validate-architecture-model
CI_STATIC_ANALYSIS_TARGETS := format-check validate-manifest check-crate-isolation static-analysis complexity architecture check-security unused-dependencies check-requirements docs-check
CI_TESTS_TARGETS := setup-test-db validate-sqlx-metadata tests-with-coverage doc-tests e2e-tests
CI_CONTRACTS_TARGETS := validate-contract-snapshots validate-openapi-spec openapi-diff graphql-diff
CI_MUTATION_TARGETS := mutation-tests-diff
CI_DELIVERY_TARGETS := build-prod-image image-scan schemathesis-validate smoke-load-tests
CI_CLI_TARGETS := bats
CI_GATES = $(CI_PREFLIGHT_TARGETS) $(CI_STATIC_ANALYSIS_TARGETS) $(CI_TESTS_TARGETS) $(CI_CONTRACTS_TARGETS) $(CI_MUTATION_TARGETS) $(CI_DELIVERY_TARGETS) $(CI_CLI_TARGETS)

# A stage of `make ci` runs the gates of its CI_*_TARGETS variable, one recipe line per gate, so the first
# failing gate stops the stage.
define NEWLINE


endef
STAGE_RECIPE = $(foreach gate,$(1),@$(MAKE) --no-print-directory $(gate)$(NEWLINE))

# ---------------------------------------------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------------------------------------------
.PHONY: help doctor bootstrap start up start-deps ensure-deps ensure-database build stop down sh logs new-logs purge clean

help: ## Show this help
	@printf '%s\n' 'Usage:' '  make [target] [arg="val"...]' 'Targets:'
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | LC_ALL=C sort -t: -k1,1 | awk 'BEGIN {FS = ":.*## "} {printf "%-28s %s\n", $$1, $$2}'

doctor: ## Check host prerequisites and pinned tool versions
	$(STUB)

bootstrap: ## Prepare a fresh clone: check, install tools, hooks, build, start, migrate
	$(REQUIRE_DOCKER)
	$(STUB)

start: ## Build missing or stale images, start the development environment and wait until it is healthy
	$(REQUIRE_DOCKER)
	$(STUB)

up: start ## Alias of start

start-deps: ## Start the backing services named in DEPS if they are not running and wait until they are healthy
	$(REQUIRE_DOCKER)
	$(STUB)

ensure-deps: ## Start PostgreSQL and LocalStack unless this shell is the development container
	@[ "$(IN_DEV_CONTAINER)" = 1 ] || $(MAKE) --no-print-directory start-deps

ensure-database: ## Start PostgreSQL unless this shell is the development container
	@[ "$(IN_DEV_CONTAINER)" = 1 ] || $(MAKE) --no-print-directory start-deps DEPS=database

build: ## Rebuild the development images from scratch
	$(REQUIRE_DOCKER)
	$(STUB)

stop: ## Stop the development environment
	$(REQUIRE_DOCKER)
	$(STUB)

down: ## Remove the development containers and network (volumes are kept)
	$(REQUIRE_DOCKER)
	$(STUB)

sh: ## Open a shell in the development container
	$(REQUIRE_DOCKER)
	$(STUB)

logs: ## Follow all logs
	$(REQUIRE_DOCKER)
	$(STUB)

new-logs: ## Follow only new log lines
	$(REQUIRE_DOCKER)
	$(STUB)

purge: ## Remove generated reports and load-test results
	$(STUB)

clean: purge ## Alias of purge

# ---------------------------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------------------------
.PHONY: install update build-prod-image

install: ## Install the pinned tools and Bats on this machine and fetch dependencies from the lock file
	$(STUB)

update: ## Update Cargo.lock within the version requirements of the manifests
	$(STUB)

build-prod-image: ## Build the production image
	$(REQUIRE_DOCKER)
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Formatting, lint and analysis
# ---------------------------------------------------------------------------------------------------------------
.PHONY: format format-check format-repo lint-code lint-rustdoc static-analysis static-analysis-fix static-analysis-sarif complexity architecture validate-configuration validate-manifest check-crate-isolation validate-sqlx-metadata check-requirements unused-dependencies unused-dependencies-fix

format: ## Format the Rust code
	$(STUB)

format-check: ## Check the Rust formatting (changes nothing)
	$(STUB)

format-repo: ## Format TOML, YAML, JSON and the load-test JavaScript
	$(REQUIRE_DOCKER)
	$(STUB)

lint-code: ## Lint production code, then all targets with tests relaxed
	$(STUB)

lint-rustdoc: ## Lint the documentation comments
	$(STUB)

static-analysis: lint-code lint-rustdoc ## Run the strict static analysis with warnings denied

static-analysis-fix: ## Apply every machine-applicable lint fix, then format
	$(STUB)

static-analysis-sarif: ## Write the lint findings as SARIF to target/sarif/clippy.sarif
	$(STUB)

complexity: ## Check the complexity limits of production code
	$(STUB)

architecture: ## Check layer and bounded-context boundaries
	$(STUB)

validate-configuration: ## Check protected configuration files and required directories against base_ref
	$(STUB)

validate-manifest: ## Check that Cargo.lock matches the manifests
	$(STUB)

check-crate-isolation: ## Check that every crate builds alone, with each feature
	$(STUB)

validate-sqlx-metadata: setup-test-db ## Check that the offline query metadata in .sqlx is current
	$(STUB)

check-requirements: ## Check that the service configuration is valid
	$(STUB)

unused-dependencies: ## Fail on unused or misplaced dependencies
	$(STUB)

unused-dependencies-fix: ## Remove unused dependencies from the manifests
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------------------------------------------
.PHONY: unit-tests doc-tests integration-tests e2e-tests all-tests test bats

unit-tests: ## Run the unit tests and the documentation tests
	$(STUB)

doc-tests: ## Run the documentation tests
	$(STUB)

integration-tests: ensure-deps setup-test-db ## Run the integration tests against PostgreSQL and LocalStack
	$(STUB)

e2e-tests: ensure-deps setup-test-db ## Run the Gherkin end-to-end tests
	$(STUB)

all-tests: unit-tests integration-tests e2e-tests ## Run unit, integration and end-to-end tests

test: all-tests ## Alias of all-tests

bats: ## Run the Makefile tests
	$(REQUIRE_DOCKER)
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Coverage and mutation
# ---------------------------------------------------------------------------------------------------------------
.PHONY: tests-with-coverage coverage-xml coverage-html mutation-tests mutation-tests-diff

tests-with-coverage: ensure-deps setup-test-db ## Run the unit and integration tests with coverage and enforce 100% lines and functions
	$(STUB)

coverage-xml: ensure-deps setup-test-db ## Write target/coverage/coverage.xml (Cobertura) and lcov.info without enforcing the floor
	$(STUB)

coverage-html: ensure-deps setup-test-db ## Write the HTML coverage report to target/coverage/html
	$(STUB)

mutation-tests: ensure-deps setup-test-db ## Run mutation testing over all production code (fails on a surviving or timed-out mutant)
	$(STUB)

mutation-tests-diff: ensure-deps setup-test-db ## Run mutation testing over the code changed against base_ref
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------------------------------------------
.PHONY: generate-openapi-spec generate-graphql-spec validate-contract-snapshots validate-openapi-spec openapi-diff graphql-diff schemathesis-validate

generate-openapi-spec: ## Write the OpenAPI snapshot .github/openapi-spec/spec.yaml
	$(STUB)

generate-graphql-spec: ## Write the GraphQL snapshot .github/graphql-spec/spec
	$(STUB)

validate-contract-snapshots: generate-openapi-spec generate-graphql-spec ## Fail when a committed contract snapshot differs from the generated one
	$(STUB)

validate-openapi-spec: ## Lint the OpenAPI snapshot with Spectral
	$(REQUIRE_DOCKER)
	$(STUB)

openapi-diff: ## Fail on a breaking OpenAPI change against base_ref
	$(REQUIRE_DOCKER)
	$(STUB)

graphql-diff: ## Fail on a breaking GraphQL change against base_ref
	$(REQUIRE_DOCKER)
	$(STUB)

schemathesis-validate: ## Test the production image against the OpenAPI snapshot with Schemathesis
	$(REQUIRE_DOCKER)
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Load tests
# ---------------------------------------------------------------------------------------------------------------
.PHONY: smoke-load-tests average-load-tests stress-load-tests spike-load-tests execute-load-tests-script aws-load-tests aws-load-tests-cleanup lint-load-tests

smoke-load-tests: ## Run every load scenario with the smoke profile
	$(REQUIRE_DOCKER)
	$(STUB)

average-load-tests: ## Run every load scenario with the average profile
	$(REQUIRE_DOCKER)
	$(STUB)

stress-load-tests: ## Run every load scenario with the stress profile
	$(REQUIRE_DOCKER)
	$(STUB)

spike-load-tests: ## Run every load scenario with the spike profile
	$(REQUIRE_DOCKER)
	$(STUB)

execute-load-tests-script: ## Run one load scenario, all four profiles unless switched off: scenario=<name> runSmoke=false runAverage=false runStress=false runSpike=false
	@test -n "$(scenario)" || { echo 'Usage: make execute-load-tests-script scenario=<name> [runSmoke=false] [runAverage=false] [runStress=false] [runSpike=false] (each profile runs unless its variable is false)' >&2; exit 2; }
	$(REQUIRE_DOCKER)
	$(STUB)

aws-load-tests: ## Run the load tests on a temporary AWS instance
	$(REQUIRE_DOCKER)
	$(STUB)

aws-load-tests-cleanup: ## Remove everything aws-load-tests created
	$(REQUIRE_DOCKER)
	$(STUB)

lint-load-tests: ## Lint and format-check the load-test JavaScript
	$(REQUIRE_DOCKER)
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------------------------------------------
.PHONY: migrate migrate-rollback create-migration setup-test-db setup-load-test-db sqlx-prepare

migrate: ensure-database ## Apply all pending migrations to the development database
	$(STUB)

migrate-rollback: ensure-database ## Revert the most recently applied migration
	$(STUB)

create-migration: ## Create a reversible migration pair: name=<snake_case_description>
	@test -n "$(name)" || { echo 'Usage: make create-migration name=<snake_case_description>' >&2; exit 2; }
	$(STUB)

setup-test-db: ensure-database ## Drop, create and migrate the test database
	$(STUB)

setup-load-test-db: ## Drop, create and migrate the database of the isolated load-test environment
	$(REQUIRE_DOCKER)
	$(STUB)

sqlx-prepare: setup-test-db ## Regenerate the offline query metadata in .sqlx from the freshly migrated test database
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------------------------------------------
.PHONY: check-security check-security-offline secrets-scan image-scan

check-security: ## Check advisories, licences, bans and sources of the locked dependencies
	$(STUB)

check-security-offline: ## Check licences, bans and sources without network access
	$(STUB)

secrets-scan: ## Scan the history and the working files for secrets
	$(REQUIRE_DOCKER)
	$(STUB)

image-scan: ## Scan the production image for HIGH and CRITICAL vulnerabilities
	$(REQUIRE_DOCKER)
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Docs and architecture model
# ---------------------------------------------------------------------------------------------------------------
.PHONY: docs-check validate-architecture-model

docs-check: ## Check that commands, paths and lists cited in the documentation exist
	$(STUB)

validate-architecture-model: ## Validate workspace.dsl, its three views and its components
	$(REQUIRE_DOCKER)
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Repository lint
# ---------------------------------------------------------------------------------------------------------------
.PHONY: lint-repo lint-actions lint-yaml lint-markdown lint-shell lint-docker lint-toml lint-spelling lint-prettier validate-invariants

lint-repo: lint-actions lint-yaml lint-markdown lint-shell lint-docker lint-toml lint-spelling lint-prettier ## Run every repository linter

lint-actions: ## Lint the workflows (syntax and security)
	$(REQUIRE_DOCKER)
	$(STUB)

lint-yaml: ## Lint the YAML files
	$(REQUIRE_DOCKER)
	$(STUB)

lint-markdown: ## Lint the Markdown files
	$(REQUIRE_DOCKER)
	$(STUB)

lint-shell: ## Lint shell scripts, hooks and Bats files
	$(REQUIRE_DOCKER)
	$(STUB)

lint-docker: ## Lint the Dockerfile
	$(REQUIRE_DOCKER)
	$(STUB)

lint-toml: ## Check the TOML formatting
	$(STUB)

lint-spelling: ## Check spelling
	$(STUB)

lint-prettier: ## Check the formatting of YAML and JSON
	$(REQUIRE_DOCKER)
	$(STUB)

validate-invariants: ## Check the repository invariants: pins, versions, gate set, repository name, licence, suppressions, execution switch
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# Hooks and tooling
# ---------------------------------------------------------------------------------------------------------------
.PHONY: install-hooks pre-commit pre-push check-commit-message

install-hooks: ## Activate the git hooks of .githooks
	$(STUB)

pre-commit: format-check lint-code architecture check-security-offline unused-dependencies ## Fast gates run by the pre-commit hook

pre-push: unit-tests ## Gates run by the pre-push hook

check-commit-message: ## Check the commit message in COMMIT_MSG_FILE or the title in COMMIT_TITLE
	$(STUB)

# ---------------------------------------------------------------------------------------------------------------
# bmalph, scaffolding and aggregates
# ---------------------------------------------------------------------------------------------------------------
.PHONY: bmalph-install bmalph-claude bmalph-codex bmalph-init bmalph-setup new-context ci all ci-sequential ci-list ci-preflight ci-static-analysis ci-tests ci-contracts ci-mutation ci-delivery ci-cli

bmalph-install: ## Install and verify bmalph for BMALPH_PLATFORM=claude-code|codex
	$(STUB)

bmalph-claude: ## Install and verify bmalph for Claude Code
	$(STUB)

bmalph-codex: ## Install and verify bmalph for Codex
	$(STUB)

bmalph-init: ## Initialise bmalph in this project; BMALPH_DRY_RUN=true previews
	$(STUB)

bmalph-setup: ## Install and initialise bmalph in one step
	$(STUB)

new-context: ## Create a bounded context: group=<group> context=<context>
	@test -n "$(group)" -a -n "$(context)" || { echo 'Usage: make new-context group=<group> context=<context>' >&2; exit 2; }
	$(STUB)

ci: ## Run every gate in order and print the success line
	@$(MAKE) --no-print-directory doctor
	@for stage in $(CI_STAGES); do $(MAKE) --no-print-directory $$stage; done
	@echo "CI checks successfully passed!"

all: ci ## Alias of ci

ci-sequential: ci ## Alias of ci

ci-list: ## Print the ordered gate targets of make ci, one per line
	@printf '%s\n' $(CI_GATES)

ci-preflight: ## Stage 1 of make ci: configuration, invariants, secrets, repository lint, model
	$(call STAGE_RECIPE,$(CI_PREFLIGHT_TARGETS))

ci-static-analysis: ## Stage 2 of make ci: formatting, manifest, analysis, complexity, security, docs
	$(call STAGE_RECIPE,$(CI_STATIC_ANALYSIS_TARGETS))

ci-tests: ## Stage 3 of make ci: test database, query metadata, coverage, doc tests, end-to-end tests
	$(call STAGE_RECIPE,$(CI_TESTS_TARGETS))

ci-contracts: ## Stage 4 of make ci: contract snapshots, OpenAPI lint and diff, GraphQL diff
	$(call STAGE_RECIPE,$(CI_CONTRACTS_TARGETS))

ci-mutation: ## Stage 5 of make ci: mutation testing of the changed code
	$(call STAGE_RECIPE,$(CI_MUTATION_TARGETS))

ci-delivery: ## Stage 6 of make ci: production image, image scan, Schemathesis, smoke load tests
	$(call STAGE_RECIPE,$(CI_DELIVERY_TARGETS))

ci-cli: ## Stage 7 of make ci: the Makefile tests
	$(call STAGE_RECIPE,$(CI_CLI_TARGETS))

-include make/service.mk
