# Release process

How a release of rust-backend-sdlc is versioned, tagged, published through the marketplace and recorded in the changelog. The policy is ADR-9 of the plugin's architecture, "Release tagging and marketplace source"; the CI side is the `manifest-validate` job of `.github/workflows/ci.yml` at the repository root.

## Policy (ADR-9)

- **Version.** The single version of the plugin is `version` in `plugins/rust-backend-sdlc/.claude-plugin/plugin.json`, plain semver `X.Y.Z`. Every release changes it and appends one entry to the [changelog](#changelog) below.
- **Tag.** Each release is tagged `rust-backend-sdlc-vX.Y.Z` on the merge commit of `main` that carries the version bump. The namespace belongs to this plugin alone; the other plugins of this marketplace repository tag in their own namespaces.
- **Tag check.** On a tag build, CI's `manifest-validate` job fails unless the tag's version equals the `plugin.json` version.
- **Semver.** MAJOR for a profile `schema_version` bump or a removed or renamed command, agent, script flag or handle; MINOR for a new skill, command, profile key, script flag or degrade row; PATCH for fixes and wording.
- **Marketplace source.** v0.1.0 ships with the relative source `"source": "./plugins/rust-backend-sdlc"`. The entry switches to a pinned `git-subdir` source at the first external consumer or at v1.0.0, whichever comes first.

## Version bumps

| Bump | A release that contains any of |
| --- | --- |
| MAJOR | a profile `schema_version` bump; a removed or renamed command, agent, script flag or handle (an output line a command or workflow parses, such as `SPECS_DIR:`, `PR_URL:` or `FR_NFR_NEW_FINDINGS:`) |
| MINOR | a new skill, command, profile key, script flag or degrade row |
| PATCH | fixes and wording that change no contract above |

A release that holds changes of several kinds takes the highest bump among them.

### A new profile key is MINOR

A profile key addition is MINOR, and the change that adds it changes these five places together, in the same pull request:

1. `scripts/generate-profile.sh`, which detects the key and writes it;
2. `scripts/validate-profile.sh`, which checks its type, nullability and format;
3. `docs/profile-schema.md`, the schema document (type, R/O, nullable, fallback, format, detection source, refresh and consumers of the key);
4. the golden profile `tests/fixtures/profiles/golden.yml`, the exact generator output the generator and validator suites compare against;
5. CC-16 in `tests/component-counts.bats`, the profile-key check that pins every key a component consumes to the schema document.

A key added to only some of the five either fails the suites or leaves a component reading a key the validator does not know.

### A `schema_version` bump is MAJOR

A `schema_version` bump makes every committed profile of the previous version invalid, so it is MAJOR and its changelog entry carries a migration note: which keys were added, removed, renamed or retyped, and how an existing `.claude/rust-sdlc.yml` reaches the new version. The usual path is `/rs-sdlc-setup --refresh` on the default branch, which regenerates the profile, keeps the five user-owned keys (`capabilities.run_in_container`, `capabilities.dynamic_security_testing`, `capabilities.publish_pr_comments`, `review.reviewers`, `review.ai_review_agents`) and is committed in one commit; the note says so, or names the manual steps when a key cannot be carried over.

## Tag and the `manifest-validate` check

Tag the merge commit of `main` that the release pull request produced, after that pull request is merged with every check green:

```bash
git fetch origin main
gh pr view <release-pr-number> --json mergeCommit --jq .mergeCommit.oid
git tag -a rust-backend-sdlc-vX.Y.Z -m 'rust-backend-sdlc X.Y.Z' <merge-commit-sha>
git push origin rust-backend-sdlc-vX.Y.Z
```

The second line prints the sha of the release pull request's merge commit, read from the pull request itself, so a pull request merged into `main` after it cannot take its place; tag that sha, never the tip of `origin/main` and never a commit of a feature branch. `.github/workflows/ci.yml` runs on pushed tags that match `rust-backend-sdlc-v*`. On a tag build the `manifest-validate` job:

1. derives the plugin name from the tag (`${GITHUB_REF_NAME%-v*}`, here `rust-backend-sdlc`) and the version from its suffix (`${GITHUB_REF_NAME##*-v}`);
2. fails when `plugins/rust-backend-sdlc/.claude-plugin/plugin.json` does not exist;
3. fails when the tag's version differs from the manifest's `version`, and prints `OK: tag '<tag>' matches <manifest> version <version>` otherwise.

On every build, tag or not, the same job checks that `version` is plain semver (`^[0-9]+\.[0-9]+\.[0-9]+$`) and that every marketplace entry's `source` is `./plugins/<name>`.

## Release checklist

1. **Release pull request.** Bump `version` in `.claude-plugin/plugin.json` by the rules above, append the changelog entry, and, for a profile key or a `schema_version` change, make the changes the two sections above require. The marketplace entry's `description` stays byte-identical to the manifest's.
2. **Checks.** Every job of `.github/workflows/ci.yml` is green (`manifest-validate`, `markdown-lint`, `shellcheck`, `bats`, `frontmatter-check`, `profile-keys-check`, `generalization-audit`), and `.github/workflows/prompt-quality.yml` is green.
3. **Release gate (v0.1.0).** K1–K8 of the product requirements hold: lint reports 0 findings for every plugin (K1); every `ci.yml` job is green with this plugin covered and the `rust-backend-sdlc-v*` tag filter present (K2); the component counts are 10 commands, 7 agents, 28 skills, 2 meta-guides, 13 scripts plus the library, 4 workflows and 9 docs (K3); the 16 bats suites meet their floors with 0 failures (K4); 0 shellcheck and markdownlint findings (K5); 0 denylist hits (K6); the template-compatibility cases are green in CI (K7); the workflow harness is green with a call-graph depth of at most 1 (K8).
4. **Merge** the release pull request into `main`.
5. **Tag** the merge commit and push the tag as above; the tag build's `manifest-validate` job must pass.
6. **Pinned source** (once the switch below has happened): update `ref` and `sha` of the marketplace entry to the new tag and its commit, in a follow-up pull request.

## Marketplace source

Until v1.0.0 or the first external consumer, whichever comes first, the entry in `.claude-plugin/marketplace.json` keeps the relative source, and installs follow `main`:

```json
{
  "name": "rust-backend-sdlc",
  "source": "./plugins/rust-backend-sdlc"
}
```

From then on the entry's `source` is a pinned `git-subdir` source, with `ref` set to the release tag and `sha` to the full sha of the commit that tag points at:

```json
{
  "name": "rust-backend-sdlc",
  "source": {
    "source": "git-subdir",
    "url": "https://github.com/VilnaCRM-Org/claude-plugins",
    "path": "plugins/rust-backend-sdlc",
    "ref": "rust-backend-sdlc-vX.Y.Z",
    "sha": "<commit>"
  }
}
```

The other fields of the entry (`description`, `author`, `category`) stay as they are. The `manifest-validate` job requires `./plugins/<name>` for every entry today, so the switch changes that job in the same pull request to accept the pinned shape for this plugin. After the switch, `main` can move between releases without reaching installed users, and every release updates `ref` and `sha`.

## Evidence after a release

The measurable outcomes recorded after v0.1.0 ship in a PATCH release: K9 and K13 in the [K9/K13 record](new-service-walkthrough.md#k9k13-record) section of the new-service walkthrough, and the K10 run report appended to `docs/sdlc-loop.md` or to a new file under `docs/evidence/` (which is not one of the 9 docs of v0.1.0).

## Changelog

Each release appends one entry at the end of this section, headed `### X.Y.Z — YYYY-MM-DD`; a MAJOR entry carries its migration note.

### 0.1.0 — 2026-11-12

- First release of rust-backend-sdlc, installed from the relative marketplace source `./plugins/rust-backend-sdlc`.
- Ten commands: /rs-sdlc (the feature loop, resumable from the state comment on the issue), /rs-sdlc-setup, /rs-sdlc-new-service, /rs-sdlc-new-context, /rs-sdlc-issue, /rs-sdlc-plan, /rs-sdlc-implement, /rs-sdlc-review, /rs-sdlc-qa and /rs-sdlc-finish-pr.
- Seven agents (`rust-implementer`, `code-quality-reviewer`, `fr-nfr-reviewer`, `security-auditor`, `qa-manual-tester`, `ci-fixer`, `pr-comment-resolver`), 28 skills and two meta-guides.
- Thirteen scripts and the `scripts/lib/common.sh` library, among them the profile generator and validator (profile schema v1), the governance injector, the local permission allowlist merge, the new-service source and customization script, the isolated BMAD FR/NFR gate and the pull-request state sensor.
- Four workflows with the hand-back contract, and 16 hermetic bats suites.
- Nine docs: the profile schema, the setup and new-service walkthroughs, the SDLC loop, permissions, the degrade matrix, this release process, workflows and the test strategy.
