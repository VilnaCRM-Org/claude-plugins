---
name: dependency-upgrade-troubleshooting
description: >-
  Use when a dependency bump reddens CI rather than the code — Playwright reporting "Executable
  doesn't exist at", a Stryker shard dying with MODULE_NOT_FOUND on `testEnvironment`, dozens of
  visual snapshots diffing by a pixel with no UI change, baselines that pass then fail after an
  image-compression bot commit, or a test container still reporting the previous tool version after
  its image was rebuilt for the bump.
---

# Dependency Upgrade Troubleshooting

## Profile keys consumed

- `make.test_e2e`
- `make.test_visual`
- `make.test_mutation`
- `make.test_unit_client`
- `make.storybook_build`
- `capabilities.visual_testing`
- `capabilities.mutation_testing`
- `capabilities.storybook`
- `framework.package_manager`

Every suite runs through the profile's `make` target map. Skip a pattern with a recorded
capability-absent note when its key maps to `null`, or when `capabilities.visual_testing` /
`capabilities.mutation_testing` is `false`. The snapshot-update target and the container/volume
teardown target have no logical key, so they are named by purpose and shown as concrete commands
only inside `# profile-example` fences.

## Overview

Most upgrade failures are infrastructure, not code: a browser image out of step with its npm
package, a runner that resolves paths without the project's transforms, a renderer that changed a
pixel, a bot that rewrites test assets, or a volume that outlived its container. Each has a fixed
cause and a fixed remedy.

## When to use

- A Playwright bump lands and the browser fails to launch inside the test container.
- A Stryker shard fails during Jest initialization while the plain unit suite passes.
- A visual suite fails broadly on one engine after an engine upgrade, with no UI diff.
- Snapshots pass on the first run and fail after an automated image-compression commit.
- A rebuilt container still reports the old tool version.
- Not for: genuine behavioural breakage from a major version — that is a code migration, and
  re-baselining or rebuilding will not hide it.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — `Playwright.Dockerfile` pins the browser image and exact `apt` package versions,
  `jest.mutation.config.ts` resolves a CommonJS test environment,
  `.github/workflows/image-optimization.yml` sets `ignorePaths`, the repository's
  snapshot-update target and its sharded mutation target reproduce the failures, and the
  repository's clean target tears down the named `node_modules` volume.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial — same
  `Playwright.Dockerfile` and snapshot-update target, but the mutation config uses the plain `jsdom`
  environment string, so pattern two does not arise, and `ignorePaths` guards `src/test/**`.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — the
  browser image is `Dockerfile.playwright`, `ignorePaths` guards `tests/visual/**`, and the visual
  suite runs against Storybook, so the snapshot-update target boots Storybook (the target mapped by
  `make.storybook_build`, gated on `capabilities.storybook`) before re-baselining.

```bash # profile-example
# The three targets with no logical profile key, in a repository that maps them this way:
make test-visual-update
make test-mutation-shard MUTATION_SHARD_INDEX=1 MUTATION_SHARD_TOTAL=8
make clean
```

## Failure patterns

**Browser binary out of step.** A Playwright bump needs matching browser binaries. Update the base
image tag in the Playwright Dockerfile to the exact new version, keep the `apt` package pins exact
so a distribution point release cannot break the build, rebuild the image, and re-run the browser
suites (the targets mapped by `make.test_e2e` and `make.test_visual`, the latter gated on
`capabilities.visual_testing`) in the new container. A pinned
image is also why local baselines match CI.

**Mutation runner cannot resolve the test environment.** The Stryker Jest runner resolves
`testEnvironment` with a raw `require.resolve()` — no `<rootDir>` expansion and no TypeScript
transform — so a `.ts` environment file fails with `MODULE_NOT_FOUND` inside a shard while the unit
suite mapped by `make.test_unit_client` is fine. Write the environment as CommonJS and resolve it
explicitly in the mutation config:

```ts
testEnvironment: require.resolve('./tests/jsdom-fetch-environment.cjs'),
```

Reproduce on one shard of the target mapped by `make.test_mutation` rather than the whole matrix
before and after the fix; the pattern does not arise at all when `capabilities.mutation_testing` is
`false`.

**Renderer drift in visual baselines.** New engine releases change sub-pixel layout, font rendering
and colour rounding, so baselines fail with no UI change and often on one engine only. Regenerate
inside the new container with the repository's snapshot-update target, read every diff to confirm it
is cosmetic rather than a real regression, note which engine moved, and commit the regenerated
baselines in the same change as the version bump.

**Image-compression bot rewriting baselines.** An image-optimization action recompresses PNGs
lossily and commits them back, corrupting snapshots that were byte-exact. Add the snapshot
directories to the action's `ignorePaths` input — a comma-separated string, not a list — and push
the uncompressed baselines again with a lease-checked force so the recompressed commit is replaced.
Verify by checksum that the committed files match what the container renders.

**Stale container volume.** Recreating containers does not drop named or anonymous volumes, so a
`node_modules` volume keeps the previous dependency tree and the container reports the old tool
version. Tear the volumes down (the repository's clean target, or a compose down with volumes)
before rebuilding, then confirm the version from inside the container — via the package runner named
by `framework.package_manager` — rather than from the host.

## Common mistakes

- Bumping the Playwright package without the browser image — the image tag and the package version
  are one pin.
- Loosening the `apt` pins to make an image build — pin to the current point release instead.
- Committing failing baselines, or re-baselining without reading the diffs — a real regression hides
  in the same failure shape.
- Leaving snapshot paths unguarded in the image-optimization workflow — the bot corrupts them again
  on the next image change.
- Debugging a stale container as if it were a code problem — check the in-container tool version
  first.
