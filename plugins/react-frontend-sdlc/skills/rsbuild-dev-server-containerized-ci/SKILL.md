---
name: rsbuild-dev-server-containerized-ci
description: >-
  Use when a containerized dev server becomes unreachable through its published Docker port — every
  job that starts the dev container fails at the start-container step, a wait-for-dev healthcheck
  loop times out, a curl to the published port is refused — especially right after a bundler or
  framework major upgrade (Rsbuild, Next.js, Vite) that changed the default dev-server host binding.
---

# Rsbuild dev server in containerized CI

## Profile keys consumed

- `make.start`
- `framework.bundler`

The dev container is started through the target mapped by `make.start`; skip that step with a
recorded note when the key maps to `null`. Read the bundler from `framework.bundler` rather than
assuming one — the binding default that causes this failure is bundler-specific.

## Overview

A dev server that binds to `localhost` inside a container is reachable only from that container's
loopback, so Docker cannot forward the published port to it. Bundler majors change this default
quietly, and the symptom is a fleet of unrelated CI jobs failing at container startup rather than
one build error.

## When to use

- Several dev-container jobs (static, unit, integration, dependency-cruiser, bundle-size,
  Lighthouse, coverage upload) all fail at the same start-container step.
- A wait-for-dev healthcheck loop exhausts its retries with connection refused.
- The dev server log prints a loopback URL, or advises passing a host flag to expose it.
- A bundler or framework major upgrade just landed.
- Not for: the app booting and then erroring — that is an application failure, not a binding one.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — `rsbuild.config.ts` sets `server.host`, the Rsbuild core package is pinned at a v2,
  the dev service publishes `3000:3000`, and the repository's wait-for-dev healthcheck target curls
  the configured domain and dev port.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial — Next.js instead of
  Rsbuild (`next.config.js`); the dev server binds all interfaces by default, but the same
  wait-for-dev healthcheck and failure signature apply after a framework major.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — no
  bundler dev server in CI; the compose command that serves the built Storybook already binds
  explicitly, which is the same rule applied elsewhere.

## Root cause

Rsbuild v2 changed the dev-server default `server.host` from `0.0.0.0` (all interfaces) to
`localhost`. Bound to 127.0.0.1 inside the container, the process is invisible to the published port
mapping, so every healthcheck from the host or from a sibling container is refused.

## Fix

Set the host explicitly in the bundler config at the repository root, so the value is reviewed and
survives the next upgrade:

```ts
export default defineConfig({
  server: {
    host: '0.0.0.0',
  },
});
```

Prefer the config over a command-line host flag: the config is what the Makefile, compose file, and
IDE runs all share, and a flag added to one invocation leaves the others broken.

## Verify

Start the dev container through the target mapped by `make.start`, then run the repository's
wait-for-dev healthcheck target and confirm reachability through the published port:

```bash # profile-example
make start
make wait-for-dev
curl -fsS http://localhost:3000 > /dev/null && echo reachable
docker compose logs dev | grep -i network
```

The log line should name the container's non-loopback address, not only `localhost`.

## Apply this check on every bundler upgrade

Treat host binding as part of the upgrade checklist alongside config-schema renames. After bumping a
bundler or framework major, start the dev container and run the healthcheck target before running
any suite — a single reachability check costs seconds and localises a failure that otherwise looks
like a dozen unrelated broken jobs.

## Common mistakes

- Reading the fleet of red jobs as a test regression and bisecting application code, when every one
  of them died before the server answered.
- Raising the wait-for-dev retry count or timeout so the loop "passes longer" — the server is not
  slow, it is unreachable.
- Passing a host flag in one script only, leaving the compose, Makefile, and IDE paths divergent.
- Binding all interfaces in a production image as a side effect; scope the change to the dev-server
  block that CI and local development actually use.
