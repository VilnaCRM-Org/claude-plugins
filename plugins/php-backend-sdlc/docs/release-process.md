# Release Process

Versioning, tagging, and marketplace pinning for php-backend-sdlc
(ADR-9, architecture §6).

## Versioning (semver)

Every release bumps `version` in `.claude-plugin/plugin.json`:

- **MAJOR** — profile `schema_version` bump or a command-contract
  break (renamed/removed commands, changed stage exit conditions).
- **MINOR** — a new skill, command, or [profile key](profile-schema.md).
- **PATCH** — fixes with no contract change.

## Tags

Tag format: `php-backend-sdlc-vX.Y.Z` (one plugin per tag namespace in
this marketplace repo). On tag builds, the `manifest-validate` CI job
asserts the tag version equals `plugin.json`'s `version` — a mismatch
fails the release.

## Marketplace source and the pin trigger

v1 ships with a relative source in `.claude-plugin/marketplace.json`
(`"source": "./plugins/php-backend-sdlc"`): installers track `main`.

**Pin trigger:** at the FIRST external consumer or v1.0.0 — whichever
comes first — the marketplace entry switches to a pinned `git-subdir`
source:

```json
{
  "source": "git-subdir",
  "url": "https://github.com/VilnaCRM-Org/claude-plugins",
  "path": "plugins/php-backend-sdlc",
  "ref": "php-backend-sdlc-vX.Y.Z",
  "sha": "<commit pin>"
}
```

From then on installs are reproducible per release and `main` can move
freely between tags.

## Release checklist

1. All seven CI jobs green on the release PR.
2. `plugin.json` version bumped per the semver rules above.
3. Changelog entry appended below.
4. Tag `php-backend-sdlc-vX.Y.Z` pushed (manifest-validate asserts the
   version match).
5. Past the pin trigger: marketplace `ref`/`sha` updated to the new
   tag.

## Changelog

### 0.1.0

- Initial plugin: 8 SDLC commands, setup/review/PR scripts with bats
  coverage, canonical profile schema, repo CI with seven validation
  jobs.
