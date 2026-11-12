# Repository settings

A repository created from this template starts with the files, workflows and gates, but a few settings live in the hosting platform and cannot be committed. This document lists what a maintainer applies once, in the settings of the repository or of the organisation. Nothing here is checked by a gate except the job names of the pull-request workflows: `make validate-invariants` fails when a job of a pull-request workflow is missing from the tables below.

A service that adds pull-request workflows of its own lists their jobs in a second document, docs/repository-settings-service.md, in the same table format. The template does not ship that file, so a sync never touches it, while this document is replaced by the template's copy on every sync. `make validate-invariants` accepts a job that is listed in either document.

## Contents

- [Required status checks](#required-status-checks)
- [Labels to create](#labels-to-create)

## Required status checks

Every pull-request workflow runs on pull requests to `main` and on pushes to `main`. The tables name every job by its id, with the check name that GitHub shows in brackets. Mark the jobs in the column "Required" as required status checks of the branch protection of `main`.

A job that is skipped counts as passing for a required check. This is intended for a documentation-only change: jobs that depend on the change detection (the "code" jobs) are skipped for a documentation-only change. Every job is a "code" job except the `changes` job itself, the aggregators `mutation-tests` and `bats` (they always run and pass when their matrix was skipped), and `secrets-scan`, `lint-repo`, `invariants`, `docs-check`, `title` and `validate-configuration`, which run for every change. The job `title` is also skipped for Dependabot pull requests and for pull requests labelled `template_sync`. A job that has nothing to do reports why in its log.

The `changes` job of each workflow is a required check too, under a name of its own ("Changes (Quality)", "Changes (Tests)" and so on). This is what makes a failure of the change detection block the merge: when `changes` fails or is cancelled, every code job that needs it is skipped, and the skipped jobs would count as passing, so the red `changes` check is the only signal left. The names are unique because a required check is matched by name: seven checks called "Changes" would all be satisfied by any one of them.

The matrix jobs have an aggregator job with a fixed name. The aggregator is the required check, because the names of the matrix jobs depend on the number of shards and groups: mark `mutation-tests` and `bats`, never `mutation-shard` and `bats-group`.

### `quality.yml` (Quality)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `changes` | Changes (Quality) | none (decides which jobs run) | yes |
| `format-check` | Formatting check | G1 | yes |
| `static-analysis` | Static analysis | G2 | yes |
| `clippy-sarif-upload` | Static-analysis findings upload | none (publication) | no |
| `complexity` | Complexity limits | G3 | yes |
| `architecture` | Architecture boundaries | G4 | yes |
| `manifest` | Manifest and lock validation | G5 | yes |
| `crate-isolation` | Crate isolation | G29 | yes |
| `query-metadata` | Persistence query metadata | G30 | yes |
| `check-requirements` | Configuration check | G6 | yes |
| `dependency-policy` | Dependency policy | G7 | yes |
| `unused-dependencies` | Unused dependencies | G8 | yes |

### `tests.yml` (Tests)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `changes` | Changes (Tests) | none | yes |
| `tests` | Tests and coverage | G11, G12, G14 | yes |
| `e2e-tests` | End-to-end tests | G13 | yes |
| `mutation-plan` | Mutation plan | none (sizes the matrix) | no |
| `mutation-shard` | Mutation shard k/n | G15 (one shard) | no |
| `mutation-tests` | Mutation tests | G15 (aggregator) | yes |
| `bats-group` | Bats: group | G16 (one group) | no |
| `bats` | Makefile tests (Bats) | G16 (aggregator) | yes |

### `contracts.yml` (Contracts)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `changes` | Changes (Contracts) | none | yes |
| `contract-snapshots` | Contract snapshots | G17 | yes |
| `openapi-lint` | OpenAPI lint | G18 | yes |
| `schemathesis` | Schemathesis | G21 | yes |

### `change-control.yml` (Change control)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `changes` | Changes (Change control) | none | yes |
| `title` | Pull-request title | G28 | yes |
| `validate-configuration` | Protected configuration | G25 | yes |
| `openapi-diff` | OpenAPI breaking changes | G19 | yes |
| `graphql-diff` | GraphQL breaking changes | G20 | yes |

### `load-tests.yml` (Load tests)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `changes` | Changes (Load tests) | none | yes |
| `smoke-load-tests` | Smoke load tests | G22 | yes |
| `lint-load-tests` | Load-script lint | G24 | yes |

### `security.yml` (Security)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `changes` | Changes (Security) | none | yes |
| `secrets-scan` | Secrets scan | G9 | yes |
| `image-scan` | Production-image scan | G10 | yes |
| `codeql` | CodeQL | none (publication) | no |

### `repository.yml` (Repository)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `changes` | Changes (Repository) | none | yes |
| `lint-repo` | Repository lint | G23 | yes |
| `invariants` | Repository invariants | G31 | yes |
| `docs-check` | Documentation drift | G26 | yes |
| `architecture-model` | Architecture model | G27 | yes |

The jobs that are not required have a reason:

- `mutation-plan` sizes the matrix of the mutation run and `mutation-shard` is one slice of it; their aggregator `mutation-tests` fails when any shard fails.
- `bats-group` is one of six groups of the Bats suite; its aggregator `bats` fails when any group fails.
- `clippy-sarif-upload` and `codeql` publish findings to code scanning. They are not gates, and they are skipped where code scanning is not available.

The release workflow and the two template-sync workflows do not run on pull requests, so they have no status check.

## Labels to create

Create these five labels. The workflows read the first three by name.

| Label | Purpose |
| --- | --- |
| `approved-config-change` | a maintainer approves a change to protected configuration; without it the job `validate-configuration` fails |
| `approved-breaking-change` | a maintainer approves a breaking change of the REST or GraphQL contract; without it the jobs `openapi-diff` and `graphql-diff` fail |
| `template_sync` | marks the pull requests opened by template sync and exempts them from the title check; the sync action creates it when it is missing |
| `bug` | applied by the bug-report issue template |
| `enhancement` | applied by the feature-request issue template |

Only maintainers should be allowed to apply the two approval labels. A label approves a change for the pull request that carries it; removing the label re-evaluates the checks.
