---
name: github-actions-workflow-authoring
description: >-
  Use when a GitHub Actions workflow carries an `on.pull_request.paths` or `on.push.paths` filter
  and the gate can skip itself — a required check reporting success with zero jobs executed, review
  feedback that the filter omits the workflow's own build inputs, a path entry left pointing at a
  renamed script so it matches nothing, or a `Dockerfile`, compose file, `Makefile`, or lockfile
  change that should have re-run a gated workflow and did not.
---

# GitHub Actions paths-gate authoring

## Profile keys consumed

- `ci.provider`
- `ci.workflows`
- `ci.required_checks`
- `framework.bundler`
- `framework.package_manager`

This skill applies to the GitHub Actions provider named by `ci.provider`; the workflow files it
audits are the ones listed in `ci.workflows`, and the checks that must never skip silently are the
ones listed in `ci.required_checks`.

## Overview

A `paths:` filter decides whether a workflow runs at all. When the filter omits the workflow file
itself or the toolchain that executes it, a change to _how the gate runs_ skips the gate — silently,
with a green check and zero jobs. Every paths-gated workflow must list its own inputs.

## When to use

- Adding or editing a workflow with an `on.pull_request.paths` or `on.push.paths` filter.
- A required check went green but the run summary shows no jobs executed.
- Review feedback says a filter does not cover the workflow's own build inputs.
- Changing a `Dockerfile`, `Makefile`, or compose file and wanting the gated workflows to re-run.
- Not for: workflows with no `paths:` filter — they already run on every matching event.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — five paths-gated workflows (`bundle-size.yml`, `contract-testing.yml`,
  `dockerfile-performance.yml`, `image-optimization.yml`, `storybook-testing.yml`); verify syntax
  with the repository's workflow-syntax lint target (actionlint).
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial — same pattern across
  five paths-gated workflows; the workflow audit target runs zizmor, and there is no actionlint
  make target.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial —
  pattern applies to `alpine-base-guard.yml`, `dockerfile-performance.yml`,
  `image-optimization.yml`; no workflow-lint make target.

Where a shape ships a workflow-lint target, run it after every filter edit:

```bash # profile-example
# React SPA shape: actionlint over the workflow tree
make lint-actionlint

# Next.js shape: the zizmor-backed workflow audit
make lint-workflows
```

## Core pattern

A workflow that builds or lints inside the Docker dev container depends on far more than the source
root. List every input that can change the result:

```yaml
on:
  pull_request:
    branches: [main]
    paths:
      - 'src/**'
      - 'package.json'
      - 'bun.lock'
      # The image, its compose service, and the make target define HOW the job runs,
      # so they can change the outcome without touching the source root.
      - 'Dockerfile'
      - '.dockerignore'
      - 'docker-compose.yml'
      - 'Makefile'
      # The gate's own config and script.
      - 'config/performance-budget.json'
      - 'scripts/bundle-size-report.mjs'
      # The workflow itself — without this, edits to the gate go unvalidated.
      - '.github/workflows/bundle-size.yml'
```

## Checklist per gated workflow

- The workflow's own path, spelled exactly as the file is named.
- Every file the job reads to decide pass/fail (threshold JSON, policy config, report script).
- The container definition when a step runs `docker compose` or `make`: `Dockerfile`,
  `.dockerignore`, the compose file(s) the target composes, and `Makefile`.
- The test tree (`tests/**`) when the job runs tests, alongside the source root.
- The bundler config for `framework.bundler` when the job builds (the RSBuild config in the React
  SPA shape, `next.config.js` in the Next.js shape).
- Lockfile and manifest for `framework.package_manager`, because a dependency bump moves emitted
  bytes and lint results.

## Common mistakes

- Filtering on the source root only — a toolchain bump changes the artifact and the gate never
  re-runs.
- Omitting the workflow file, so a filter typo or a weakened step merges unvalidated.
- Listing a path that does not exist (a renamed script) — the filter matches nothing and the job
  stops firing; grep the repository for each entry after a rename.
- Adding the gate to branch protection while its filter can skip it — a skipped required check
  blocks or passes depending on repository settings, so keep the filter broad enough to fire.
- Trusting a green check without opening the run: confirm jobs actually executed.
