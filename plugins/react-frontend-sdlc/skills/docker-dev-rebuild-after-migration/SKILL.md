---
name: docker-dev-rebuild-after-migration
description: >-
  Use when the dev container behaves as though it is running older code after a Dockerfile, base
  image, Node version or package-manager change — "command not found" or exit 127 for a tool the
  Dockerfile installs, "Cannot find module" or HTTP 500 from the dev server despite the module being
  present, a dependency resolving to a version the lockfile no longer pins, or a build artifact
  directory that cannot be removed because it is root-owned.
---

# Docker dev rebuild after migration

## Profile keys consumed

- `make.start`
- `make.build`
- `make.ci`
- `framework.bundler`
- `framework.package_manager`

## Overview

Starting the dev stack does not necessarily rebuild the image, and mounted volumes carry state
forward across restarts regardless. After any change to the Dockerfile or the dependency tree, the
image and the mounted module and build-artifact directories all have to be refreshed explicitly, in
that order.

## When to use

- A tool the Dockerfile installs is missing inside the container.
- The dev server serves stale compiled output — a module error or a 500 for code that is correct on
  disk.
- An installed dependency resolves to a version the lockfile no longer pins.
- A gate passes on the host and fails in the container, or the reverse — including the aggregate
  suite mapped by `make.ci`.
- A build-artifact directory refuses to delete because a previous container created it as root.
- Not for: application bugs reproducible on a freshly built image, or CI failures — CI runners build
  from scratch and share no cache with a local checkout.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — the dev service bind-mounts the worktree and keeps a **named** `node_modules`
  volume, which is the piece that goes stale; the target mapped by `make.start` already passes
  `--build`, and the target mapped by `make.build` runs the application build, not the image build,
  so rebuild with `docker compose build dev`. The repository's dependency-install, stop and clean
  targets (the last removes this project's volumes and locally built images) apply as described.
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — the target mapped by
  `make.start` is a plain `up -d dev` against a cached image and the target mapped by `make.build`
  rebuilds the images; the dev service bind-mounts the worktree over an **anonymous**
  `/app/node_modules` volume that Compose carries forward across `up`, and the build cache of the
  bundler named by `framework.bundler` is the stale-artifact directory.
- **Component-library shape** (Storybook-first, no bootable app, published package): no — start
  rebuilds; nothing mounted.

Skip a step with a recorded note when the key it depends on maps to `null`: no `make.start` means
there is no dev stack to refresh, and no `make.build` means the image build is reached only through
`docker compose build` directly.

## Procedure

1. **Rebuild the image** with the current Dockerfile. Check the target mapped by `make.start` before
   trusting it: in the Next.js shape it starts containers against a cached image and never rebuilds,
   while in the React SPA shape it passes `--build`. Rebuilding explicitly is always safe, and the
   target mapped by `make.build` is the image build only where the applicability bullet says so:

   ```bash
   docker compose build dev
   ```

2. **Refresh the module volume** so the image's freshly installed tree wins over the previous
   container's. Docker seeds a volume only when it is created, so a lockfile change does not reach
   an existing one. The dependency-install target has no logical key in the profile; it runs the
   package manager named by `framework.package_manager` inside the running container:

   ```bash # profile-example
   make install                                    # reinstall into the running container
   docker compose up -d --renew-anon-volumes dev   # anonymous volume
   docker volume rm <project>_node_modules         # named volume, container stopped
   ```

3. **Clear stale build artifacts** in the bind-mounted worktree — the build-cache directory of the
   bundler named by `framework.bundler` and any generated output. Pre-compiled chunks are served in
   preference to source, so correct code can still produce a module error until they are gone.

4. **Restart and verify** — the stop target has no logical key in the profile, so pair it with the
   target mapped by `make.start`:

   ```bash # profile-example
   make down && make start
   docker compose ps                 # the dev service reports healthy
   curl -sSf http://localhost:3000   # returns 200
   ```

If it is still wrong, rebuild every service rather than just `dev` — building one service can miss a
shared base-stage update — and, as the last step, remove this project's volumes and locally built
images and start again.

## Root-owned artifacts

The dev container runs as root while the worktree is bind-mounted, so anything it writes is
root-owned on the host and a user-shell delete fails. Stop the container first to release the
directory, then remove it with elevated privileges. The same ownership trap is why generator targets
that write tracked or ignored files into the worktree are deliberately host-only in some repository
shapes: running them inside the container leaves a root-owned file that later host commands cannot
touch.

## Common mistakes

- Assuming the target mapped by `make.start` rebuilds the image — read the recipe, and build
  explicitly when it does not pass `--build`.
- Rebuilding the image but leaving the module volume in place, so the old dependency tree survives
  the rebuild that was supposed to replace it.
- Deleting artifacts while the container still holds the directory — the delete half-succeeds and
  leaves the tree in a worse state.
- Assuming a local cache and a CI cache are the same thing; clearing one does nothing for the other.
- Running out of disk mid-rebuild — a stale build cache can be gigabytes, so check free space before
  blaming the build.
