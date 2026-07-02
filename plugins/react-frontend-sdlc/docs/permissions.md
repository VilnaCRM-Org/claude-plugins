# Permissions

How plugin-spawned `claude` sessions get the access they need without
interactive prompts — and where the hard line sits.

## Default: `--permission-mode acceptEdits`

Every `claude -p` invocation the plugin makes (the AI review loop in
`scripts/ai-review-loop.sh`, the FR/NFR gate in `scripts/fr-nfr-gate.sh`)
runs with `--permission-mode acceptEdits`: file edits are accepted
automatically, while Bash commands still need to be covered by the
allowlist below. This is the plugin-wide default and the only mode its
scripts use.

## The settings.json allowlist

`/fe-sdlc-setup` writes (merge, never clobber) this allowlist into the
target repository's `.claude/settings.json` so the container-only
workflow runs unprompted:

```json
{
  "permissions": {
    "allow": [
      "Bash(make:*)",
      "Bash(bun:*)",
      "Bash(docker compose exec dev:*)",
      "Bash(git:*)",
      "Bash(gh:*)"
    ]
  }
}
```

Five entries, matching how the plugin works:

- `Bash(make:*)` — every build/lint/test lane runs through a `make`
  target from the [profile](profile-schema.md) `make` map (the logical
  targets mapped by `make.lint_eslint`, `make.build`, `make.test_e2e`,
  and the rest of the map). The plugin never invents a raw host command
  for a lane the profile maps.
- `Bash(bun:*)` — the package manager from `framework.package_manager`,
  for the dependency operations the SDLC stages occasionally run directly
  (installing a new dependency, refreshing the lockfile).
- `Bash(docker compose exec dev:*)` — the container-only escape hatch: a
  single Jest test, a scoped Playwright spec, or an ad-hoc command run
  inside the repo's dev compose service without a dedicated `make` target.
- `Bash(git:*)` and `Bash(gh:*)` — the SDLC stages drive branch, commit,
  push, and PR/issue operations through `git` and the GitHub CLI.

### Merge, never clobber

`/fe-sdlc-setup` never overwrites `.claude/settings.json`. It reads any
existing file, unions these entries into `permissions.allow`
(deduplicating), and writes it back. A repo that already allowlists other
commands keeps every one of them — the plugin only adds its own entries,
it never replaces the array or the surrounding settings.

### The allowlist is adapted per repo

The block above is the SPA / component-library reference (bun). The
package-manager entry tracks `framework.package_manager`: on a repo whose
`framework.package_manager` is `pnpm` (a Next.js app) or `npm`,
`/fe-sdlc-setup` writes `Bash(pnpm:*)` / `Bash(npm:*)` instead of
`Bash(bun:*)`. The `docker compose exec` entry likewise names the repo's
own dev compose service. The shape stays the same; only the two
stack-specific tokens are filled from the profile.

### Why container-only

The frontend toolchain — the bundler (RSBuild / Next / Vite), Jest,
Playwright (E2E + visual), Stryker, Lighthouse, k6, memlab — runs inside
Docker for every SDLC stage, reached through `make` targets or a direct
`docker compose exec` into the dev service. The allowlist grants exactly
those two surfaces plus the package manager and `git` / `gh`; it never
grants a broad `Bash(*)`. So a non-interactive session can drive the full
container toolchain and the VCS/PR flow, but cannot run arbitrary host
binaries.

## `bypassPermissions`: Ralph-only opt-in

`bypassPermissions` is NEVER a default anywhere in this plugin and
`/fe-sdlc-setup` never writes it. It exists solely as a documented opt-in
for the Ralph driver (`bmalph`), where the autonomous loop runs unattended
by design. If you enable it there, that is your explicit decision for that
driver — nothing in the plugin, and nothing `/fe-sdlc-setup` does, will
enable it for you.

## Permission denials mid-loop

A non-interactive `claude` session that hits a permission denial cannot
prompt anyone. Per the [degrade matrix](degrade-matrix.md), the error
output is surfaced verbatim in the escalation report and points back to
this document. Fix: add the denied command pattern to `permissions.allow`
(or run the affected stage interactively once) and resume.
