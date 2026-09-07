---
name: ci-infrastructure-failure-diagnosis
description: Use when a CI job fails for infrastructure reasons rather than code — a sandbox or deploy check dying in a cloud pipeline-start call, "PR number extraction failed", cloud-credential configuration auth errors, a job firing on the wrong event, a fork pull request triggering a privileged job, or a Docker build failing only on one architecture or only in CI.
---

# CI Infrastructure Failure Diagnosis

## Profile keys consumed

- `ci.provider`
- `ci.workflows`
- `project.repo`
- `make.build`

## Overview

Infrastructure failures look like code failures but are caused by the workflow's triggers,
permissions, credentials, concurrency, or build context. Diagnose them by reading the event that
fired, the permissions the job held, and where each value came from — not by re-running.

## When to use

- A cloud-provisioning check fails with a parameter-validation or auth error.
- The same check fails on every re-run of one pull request, or only on fork pull requests.
- A job that should run once fires twice with different inputs, one of them empty.
- A Docker build fails only in CI, only on one architecture, or type-checks files nobody touched.
- Not for: a single red check on an otherwise green pipeline that has not been reproduced locally
  yet (that is the [ci-single-check-validation skill](../ci-single-check-validation/SKILL.md)), or a
  refactor that moved a gate between execution contexts (that is the
  [ci-infrastructure-refactoring skill](../ci-infrastructure-refactoring/SKILL.md)).

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — a sandbox-creation workflow provisions per-pull-request sandboxes via cloud OIDC;
  a Dockerfile-performance workflow checks the base branch out into a second directory, excluded by
  the Docker ignore file.
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — the same sandbox
  workflow plus a deploy workflow for pushes to `main`, gated behind a protected deployment
  environment; same second-branch exclusion.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — no
  sandbox or deploy workflow, so only the Docker build-context and architecture half applies.

## Procedure

1. **Read the event, not the check name.** Open the failed run and record the workflow file (cross
   -checked against `ci.workflows`), the triggering event, the branch or pull-request number, the
   failing step, the exit code, and the verbatim error. A sandbox check comes from the sandbox
   workflow, not the deploy workflow.
2. **Check the triggers for a race.** A workflow listening on both `push` and `pull_request` runs
   twice; the push run has no pull-request payload, so values read from it are empty and the
   provisioning call fails parameter validation while the pull-request run passes. Sandbox
   provisioning should listen on `pull_request` types `opened`, `reopened`, `synchronize` only;
   production deploys on `push` to `main` only.
3. **Trace every input to its source.** Values that exist in the event payload must be read from it
   (`PR_NUMBER: ${{ github.event.pull_request.number }}`), never fetched back through an API call
   with a stored token — a rotated or expired secret then presents as an extraction failure on every
   re-run, with no auth error to point at. Validate each one is non-empty in an early step.
4. **Compare permissions against what the job does.** Top-level `permissions: {}`, then the minimum
   per job: `id-token: write` for the OIDC exchange, and `contents: read` only if the job checks out
   code. A job that reads its inputs from the event and checks nothing out needs no repository scope
   at all. Pin the credentials action to a commit SHA, use `persist-credentials: false` on checkout,
   and confirm the cloud role's trust policy names the `ci.provider` OIDC provider.
5. **Test cross-branch consistency.** Failing on every push to one pull request means configuration,
   not flake. Failing only on forks means a missing same-repo guard — fork pull requests receive no
   OIDC token and no secrets, so privileged jobs must carry a guard comparing the head repository
   against `project.repo`:

   ```yaml # profile-example
   if: github.event.pull_request.head.repo.full_name == github.repository
   ```

6. **Check concurrency and upstream jobs.** Aborting an in-flight cloud pipeline trigger is unsafe,
   so provisioning and deploy workflows serialize with `cancel-in-progress: false`. Confirm any
   `needs:` job actually succeeded rather than being skipped.
7. **For build failures, inspect the context and the layers.** Reproduce the image build through the
   target mapped by `make.build` (skip with a recorded note when it maps to `null`), and see
   [sandbox-and-docker-reference.md](sandbox-and-docker-reference.md) for the build-context,
   install-gate, and architecture checks, and for the pre-push checklist.
8. **Compare against a sibling repository of the same lineage.** The React SPA and Next.js shapes
   carry near-identical sandbox workflows; diffing them is usually faster than deriving the correct
   shape from first principles.

## Common mistakes

- Re-running a failed provisioning job instead of reading which event fired it.
- Reading a value through an API call when the event payload already carries it.
- Granting a workflow-wide write scope because one job needs one write scope.
- Setting `cancel-in-progress: true` on a deploy workflow, killing in-flight production triggers.
- Assuming a fork pull request failure is a code problem — it is a missing same-repo guard.
- Rebuilding a Docker image without clearing cache after changing the Docker ignore file, then
  concluding the exclusion did not work.
