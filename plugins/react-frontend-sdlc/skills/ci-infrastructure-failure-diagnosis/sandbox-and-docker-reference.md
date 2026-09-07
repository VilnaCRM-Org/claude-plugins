# Sandbox, Deploy, and Docker Build Reference

Supporting detail for the
[ci-infrastructure-failure-diagnosis skill](SKILL.md).

## Sandbox provisioning workflow (per pull request)

- Triggers: `pull_request` with `types: [opened, reopened, synchronize]` only. No `push`.
- Permissions: top-level `permissions: {}`; each privileged job declares `id-token: write`, and adds
  `contents: read` only if it checks out code.
- Fork guard on every job that assumes a cloud role — the head repository must equal the repository
  named by `project.repo`:

  ```yaml # profile-example
  if: github.event.pull_request.head.repo.full_name == github.repository
  ```

- Inputs come from the event payload as workflow-level `env`
  (`PR_NUMBER: ${{ github.event.pull_request.number }}`), validated non-empty in the first step.
- Concurrency: `group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}`
  with `cancel-in-progress: false`.
- The credentials action is pinned to a commit SHA and its `role-session-name` is auditable.
- Where the pipeline depends on a stored secret (as the Next.js app shape's does), a token-rotation
  job checks that it exists and is current, so expiry surfaces as its own failure instead of as an
  empty value downstream. A provisioning job that reads everything from the event — as the React SPA
  shape's does — needs no such job.

## Production deploy workflow

- Trigger: `push` to `main` only.
- Permissions: `id-token: write` plus `contents: read`, scoped to the deploying job.
- Runs inside a protected deployment environment so protection rules apply from repository settings.
- Concurrency: `cancel-in-progress: false` — a newer push queues behind the running deploy.
- No stored-secret dependency; OIDC handles authentication.
- A downstream job that needs a value a maintainer has to supply (a public site URL for a smoke
  test) carries an explicit `if:` guard on that variable being non-empty, so it skips cleanly
  instead of reddening the deploy.

## Docker build context

- Any directory a workflow checks a second branch into (the base-branch checkout used by the
  Dockerfile performance comparison) must be excluded in the Docker ignore file. Without it the head
  image compiles the base branch's sources against head dependencies and fails for reasons the diff
  cannot explain.
- The installed-dependency directory stays excluded so the image's own install is not overwritten by
  the host tree, whose native binaries were built for a different platform.
- After editing the Docker ignore file, rebuild without cache before concluding anything: a cached
  layer still carries the old context.
- Reproduce an architecture-specific failure locally before changing the Dockerfile:

  ```bash # profile-example
  docker buildx build --platform linux/amd64,linux/arm64 -t probe:latest .
  ```

## Install gates and architecture

- A config file that makes an install strict (a package-manager config with an engine-strict flag)
  only takes effect if it is copied into the layer _before_ the install command runs. Copied after —
  or not at all — the install succeeds while silently skipping the check the gate exists for.
- Never hard-code an architecture when a layer downloads a prebuilt binary. Resolve it at build
  time, or select a per-architecture checksum by build argument:

  ```dockerfile # profile-example
  ARG TARGETARCH
  RUN curl -fsSL "https://example.invalid/tool-linux-${TARGETARCH}.tar.xz" | tar xJ
  ```

  A hard-coded value produces an image that builds cleanly and fails at run time on the other
  architecture.

## Pre-push checklist for a workflow or Dockerfile change

- Triggers are explicit and non-overlapping; no event fires the same job twice with different
  payloads.
- Permissions are minimal per job under a top-level empty default.
- Privileged jobs carry the same-repo guard.
- Every input is read from the event payload and validated non-empty.
- Actions are pinned to commit SHAs; checkout uses `persist-credentials: false`.
- Concurrency cancels on pull-request workflows and never on deploy or release workflows.
- Second-branch checkouts are excluded from the build context.
- Install-gating config is copied before the install step.
- Architecture-specific downloads resolve the target at build time.
