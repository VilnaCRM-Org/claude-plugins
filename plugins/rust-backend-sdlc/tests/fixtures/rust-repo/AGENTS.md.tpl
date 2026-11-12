# Agent Guide

This file tells AI coding assistants how to work in this repository: a Rust service with one crate per bounded-context layer, built from the service template and extended by its owners. It is guidance only; it adds no behaviour and the gates enforce what it says.

## Mandatory Workflow For AI Agents

1. Read [`.claude/skills/README.md`](.claude/skills/README.md), the only skill inventory.
2. Choose the skill that matches the task.
3. Read the `SKILL.md` of that skill and follow it before you claim the work is complete.

## Working Rules

- Run every tool through `make`. Do not call cargo, docker or the linters directly unless a skill says so; `make help` lists the targets.
- Never change an item listed in `protected-config.toml` to obtain a pass. A maintainer approves such a change: the session is restarted with `ALLOW_PROTECTED_CONFIG_EDIT=1` and the pull request carries the label `approved-config-change`.
- Keep Domain crates free of frameworks and I/O. `make architecture` fails when a layer or a bounded context reaches across a boundary.
- Regenerate the contract snapshots and update `workspace.dsl` in the same change that alters a contract or adds, removes or relates a crate.
- Follow the commit and pull-request title form `type(#issue): subject`.
- Never edit a migration that has been applied; add a new migration instead.
- Install the git hooks with `make install-hooks` and never bypass them; releases and `CHANGELOG.md` are produced by the release job from the commit history, never by hand.
- Do not write `#[allow]`. A lint suppression is an `#[expect]` with a reason, and only where the lint policy permits it.

## Verification

Run the targets below, in this order, before you declare a change complete. The list is the output of `make ci-list`, the gate targets that `make ci` runs, and `make docs-check` fails when the two differ. Other documents link to this section and do not repeat it.

<!-- verification:start -->

```bash
make validate-configuration
make validate-invariants
make secrets-scan
make lint-repo
make lint-load-tests
make validate-architecture-model
make format-check
make validate-manifest
make check-crate-isolation
make static-analysis
make complexity
make architecture
make check-security
make unused-dependencies
make check-requirements
make docs-check
make setup-test-db
make validate-sqlx-metadata
make tests-with-coverage
make doc-tests
make e2e-tests
make validate-contract-snapshots
make validate-openapi-spec
make openapi-diff
make graphql-diff
make mutation-tests-diff
make build-prod-image
make image-scan
make schemathesis-validate
make smoke-load-tests
make bats
```

<!-- verification:end -->

For a change that touches only documentation, run `make lint-repo docs-check`.

## Close-Out

When you finish, state which targets you ran and their result, which targets you did not run and why, and every deviation from a skill or from these rules.

## Skills

The skills are listed in [`.claude/skills/README.md`](.claude/skills/README.md), the only skill inventory.
