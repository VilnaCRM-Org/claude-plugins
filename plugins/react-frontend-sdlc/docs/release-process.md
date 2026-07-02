# Release Process

Versioning, tagging, and marketplace pinning for react-frontend-sdlc
(ADR-9; the release gate is enforced by the shared `manifest-validate`
CI job).

## Versioning (semver)

Every release bumps `version` in the plugin manifest at
`plugins/react-frontend-sdlc/.claude-plugin/plugin.json`:

- **MAJOR** — profile `schema_version` bump or a command-contract
  break (renamed/removed commands or agents, changed stage exit
  conditions).
- **MINOR** — a new skill, command, agent, or
  [profile key](profile-schema.md).
- **PATCH** — fixes with no contract change.

The manifest `version` must be plain semver: `manifest-validate`
rejects any `plugin.json` whose `version` fails
`^[0-9]+\.[0-9]+\.[0-9]+$`.

## Tags

Tag format: `react-frontend-sdlc-vX.Y.Z`. Each plugin owns its own tag
namespace in this shared marketplace repo — `php-backend-sdlc-v*` and
`react-frontend-sdlc-v*` are the two push-tag globs the CI workflow
listens on — so a tag maps to exactly one plugin. On tag builds the
`manifest-validate` job derives the plugin from the tag prefix
(`${TAG%-v*}`) and the version from the `-vX.Y.Z` suffix
(`${TAG##*-v}`), then asserts the tag version equals that plugin's
`plugin.json` `version` — a mismatch fails the release.

### Tagging with the `claude plugin tag` helper

Rather than hand-typing the namespaced tag (and risking the exact
mismatch the gate rejects), use the `claude plugin tag` helper, which
reads the manifest version and creates the correctly-namespaced tag:

```bash
claude plugin tag react-frontend-sdlc
```

It resolves `plugins/react-frontend-sdlc/.claude-plugin/plugin.json`,
reads its `version`, and produces `react-frontend-sdlc-v<version>`, so
the namespace and version agree by construction. Push the tag after the
version bump is committed; the CI release gate then re-checks the same
invariant on the tag build.

## marketplace.json and plugin.json agreement

The root `.claude-plugin/marketplace.json` lists both plugins; the
react entry must stay in lockstep with its manifest. For every
marketplace entry `manifest-validate` asserts that:

- `plugins[].name` equals the plugin directory name and the manifest's
  own `name` — here, `react-frontend-sdlc` (FR-19);
- `plugins[].source` equals `./plugins/<name>`
  (`./plugins/react-frontend-sdlc`) and that directory exists (ADR-9);
- the manifest carries every required field (`name`, `description`,
  `version`, `author.name`, `homepage`, `repository`, `license`, and a
  non-empty `keywords`) with a semver `version`.

The marketplace entry duplicates the plugin's `description` and
`author`; keep the two identical on every release so installers read
the same metadata the manifest ships. The version itself lives only in
`plugin.json` — the marketplace entry pins a release through its
`source` (below), not a version field.

## Marketplace source and the pin trigger

v1 ships with a relative source in `.claude-plugin/marketplace.json`
(`"source": "./plugins/react-frontend-sdlc"`): installers track `main`.

**Pin trigger:** at the FIRST external consumer or v1.0.0 — whichever
comes first — the marketplace entry switches to a pinned `git-subdir`
source:

```json
{
  "source": "git-subdir",
  "url": "https://github.com/VilnaCRM-Org/claude-plugins",
  "path": "plugins/react-frontend-sdlc",
  "ref": "react-frontend-sdlc-vX.Y.Z",
  "sha": "<commit pin>"
}
```

From then on installs are reproducible per release and `main` can move
freely between tags.

## Quality thresholds are raise-only across releases

A release may tighten the quality bar but never loosen it. The shipped
`quality.*` defaults in the [profile schema](profile-schema.md) are the
floor of the bar across the plugin's whole release history:

- **Floors** — `quality.coverage_statements`,
  `quality.coverage_branches`, `quality.coverage_functions`,
  `quality.coverage_lines`, `quality.mutation_msi`,
  `quality.lighthouse_desktop`, `quality.lighthouse_mobile` — may be
  raised in a release, never lowered (ADR-7). `quality.mutation_msi`
  is seeded from the target repo's Stryker `break` and enforced against
  whichever is higher.
- **Ceilings** — `quality.jscpd_clones`, `quality.eslint_errors`,
  `quality.eslint_warnings`, `quality.tsc_errors`,
  `quality.markdownlint_errors`, `quality.depcruise_violations`,
  `quality.visual_diffs` — ship at `0` and stay there; a release may
  not raise them.
- `quality.metrics_enforced` must stay `true` (the rust-code-analysis
  hard-fail policy lives in `config/metrics-policy.json`).

`scripts/validate-profile.sh` rejects any profile that puts a value on
the wrong side of its shipped default, so a release that tried to relax
a threshold would fail validation before it could ship. Because the
shipped defaults themselves only ratchet upward, no release can weaken
a gate a prior release enforced.

## Release checklist

1. All seven CI jobs green on the release PR.
2. `plugin.json` `version` bumped per the semver rules above.
3. The marketplace.json react entry (`description`/`author`) still
   matches the manifest.
4. `quality.*` defaults unchanged or tightened only — never relaxed.
5. Changelog entry appended below.
6. Tag `react-frontend-sdlc-vX.Y.Z` created with
   `claude plugin tag react-frontend-sdlc` and pushed (the
   `manifest-validate` release gate asserts the version match).
7. Past the pin trigger: marketplace `ref`/`sha` updated to the new
   tag.

## Changelog

### 0.1.0

- Initial plugin: 8 `/fe-sdlc*` commands, 7 SDLC agents, setup/review/PR
  scripts with bats coverage, the canonical profile schema, raise-only
  quality gates, and repo CI with seven validation jobs.
