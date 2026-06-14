# Contributing and Releases

[Home](Home.md) › Build › Contributing and Releases

This page is for people who change the plugin itself rather than run it
against a PHP backend. It covers the repository layout and Claude Code
plugin format, how to run the local test suites that gate every change
(bats, markdownlint, shellcheck), the release process (versioning, tags,
changelog, marketplace pinning), and how the GitHub wiki is published —
the one-time UI seed plus the mirror script.

The plugin ships **8 commands**, **7 agents**, and **22 skills** plus **2
meta-guides**
([`AI-AGENT-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md)
and
[`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md)).
Those counts are load-bearing — CI and the bats suite assert them
exactly, so adding or removing a component means updating the counts in
the same change (see [Testing](#how-to-run-the-test-suites-locally)).

## Repository layout and plugin format

The plugin lives in a marketplace monorepo. The marketplace manifest at
the repo root,
[`.claude-plugin/marketplace.json`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/.claude-plugin/marketplace.json),
lists each plugin under `plugins/<name>/`, and every plugin carries its
own
[`.claude-plugin/plugin.json`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/.claude-plugin/plugin.json)
manifest. The plugin name in `plugin.json` must equal its directory name,
and the marketplace `source` must be `./plugins/<name>` — CI's
`manifest-validate` job enforces both.

The plugin directory follows the
[Claude Code plugin format](https://docs.claude.com/en/docs/claude-code/plugins):

| Path | Holds | Format contract |
| --- | --- | --- |
| `.claude-plugin/plugin.json` | name, version, description, author, homepage, repository, license, keywords | all required; version is strict semver |
| `commands/*.md` | the 8 slash commands | frontmatter needs `description` + `argument-hint` |
| `agents/*.md` | the 7 subagents | frontmatter needs `name`, `description`, `tools`, `model` |
| `skills/*/SKILL.md` | the 22 skills (one dir each) | frontmatter needs `name` + `description`; `name` must equal dir |
| `skills/*.md` | the 2 loose meta-guides | must NOT have frontmatter (matched by the `skills/*/SKILL.md` glob only, per ADR-11) |
| `scripts/*.sh` | null-substitution fallbacks for the loop | source `lib/common.sh`; pass `shellcheck -x` |
| `scripts/lib/common.sh` | shared helpers (`profile_path`, `profile_get`, YAML toolchain guard) | sourced by every script |
| `tests/*.bats` | the bats suites + fixtures | one suite per script, plus `common-lib.bats` (for the shared `lib/common.sh`) and `component-counts.bats`; `publish-wiki.sh` has no bats suite |
| `docs/*.md` | canonical reference docs | the single source of depth; wiki links here, does not restate |
| `wiki/*.md` | this GitHub-wiki source | authored in-repo, CI-linted, mirrored by `publish-wiki.sh` |

A deeper walk-through of how the layers compose (commands → agents →
skills + profile) is on [Architecture](Architecture.md).

### Component frontmatter and the meta-guide exemption

The `frontmatter-check` CI job parses YAML frontmatter with `yq` (falling
back to `python3` + PyYAML, per the ADR-2 toolchain convention) and fails
if a command, agent, or `skills/*/SKILL.md` is missing a required key.
The two meta-guides at the `skills/` root
([`AI-AGENT-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md),
[`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md))
are matched by `skills/*.md` and must NOT carry frontmatter — the job
fails them if they do.

### Profile keys are declared once

Any profile key a skill consumes must be declared in
[`docs/profile-schema.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md).
The `profile-keys-check` CI job scans each skill's `## Profile keys
consumed` section and fails on any namespaced key (or the bare
`schema_version`) that the schema doc does not declare. When you teach a
skill a new key, add it to the schema doc in the same change. The
[Project Profile](Project-Profile.md) page narrates the schema.

### Generalization hygiene

The `generalization-audit` CI job keeps the plugin target-repo-agnostic
(NFR-2/NFR-7): it greps `skills/`, `commands/`, `agents/`, and `scripts/`
for a denylist of consumer-specific identifiers and fails on any hit
outside a fenced block marked `# profile-example`, and it fails if any
`_bmad/` or `.ralph/` entry leaks into the plugin tree. Keep examples
generic, or fence and mark them.

## How to run the test suites locally

Every change is gated by the same checks CI runs. Run them from the repo
root before pushing. CI fans these out as seven parallel jobs defined in
[`.github/workflows/ci.yml`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/.github/workflows/ci.yml);
locally you run the three that exercise the plugin's shipped artifacts.

### bats (script behavior)

The bats suites under
[`tests/`](https://github.com/VilnaCRM-Org/claude-plugins/tree/main/plugins/php-backend-sdlc/tests)
are the primary test surface — one suite per script, plus
`common-lib.bats` (for the shared `lib/common.sh`) and
`component-counts.bats`, which asserts the exact 8/7/22 + 2 counts and
the frontmatter rules. `publish-wiki.sh` has no bats suite. They drive
scripts deterministically with stub `gh`, `claude`, and `bmalph`
binaries on a prepended `PATH` (see `tests/fixtures/bin`).

```bash
# run every bats suite the way CI does
mapfile -t files < <(find plugins/php-backend-sdlc/tests -type f -name '*.bats')
npx --yes bats "${files[@]}"

# or a single suite while iterating
npx --yes bats plugins/php-backend-sdlc/tests/generate-profile.bats
```

The suite is large (the convergence campaign grew it from 0 to 197
tests; it has continued to grow since) and must be fully green before a
release. New behavior or a fixed bug lands with a regression test in the
matching suite — fixes never weaken a check to make a test pass. The
testing methodology is on [Testing and Validation](Testing-and-Validation.md).

### markdownlint (docs and wiki)

CI lints every `plugins/**/*.md` with `markdownlint-cli2` under the repo
config
[`.markdownlint.yaml`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/.markdownlint.yaml).
Only `MD013` (line length) is disabled; all other default rules apply —
ATX headings, blank lines around headings/lists/fences, a language on
every code fence, exactly one H1, no trailing spaces, and a single
trailing newline.

```bash
# lint everything CI lints
mapfile -t files < <(find plugins -type f -name '*.md')
npx --yes markdownlint-cli2 "${files[@]}"

# lint just the wiki source while editing it
npx --yes markdownlint-cli2 plugins/php-backend-sdlc/wiki/*.md
```

### shellcheck (scripts)

CI runs `shellcheck -x` over every `scripts/*.sh` (the `-x` follows the
`source lib/common.sh` includes). Run it the same way:

```bash
mapfile -t files < <(find plugins/php-backend-sdlc/scripts -type f -name '*.sh')
shellcheck -x "${files[@]}"
```

### The other CI jobs

`manifest-validate`, `frontmatter-check`, `profile-keys-check`, and
`generalization-audit` are pure shell + `jq`/`yq` and run on every PR.
You can reproduce any of them by copying its step out of
[`ci.yml`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/.github/workflows/ci.yml),
but in practice the bats `component-counts` suite catches the count and
frontmatter drift those jobs guard, so running bats + markdownlint +
shellcheck locally covers the common cases. All seven jobs must be green
on the release PR.

## Release process

The full rules — semver triggers, the tag/version assertion, and the
marketplace pin — live in
[`docs/release-process.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/release-process.md).
Summary below.

### Versioning (semver)

Every release bumps `version` in `plugin.json`:

| Bump | Trigger |
| --- | --- |
| MAJOR | profile `schema_version` bump, or a command-contract break (renamed/removed command, changed stage exit condition) |
| MINOR | a new skill, command, or profile key |
| PATCH | a fix with no contract change |

### Tags and the version assertion

Tags use the namespace `php-backend-sdlc-vX.Y.Z` (one plugin per tag
namespace in this marketplace repo). On a tag build, the
`manifest-validate` job asserts the tag's version equals the version in
`plugin.json` — a mismatch fails the release. The tag workflow trigger
is `tags: ['php-backend-sdlc-v*']` in
[`ci.yml`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/.github/workflows/ci.yml).

### Marketplace source and the pin trigger

v1 ships a relative source in `marketplace.json`
(`"source": "./plugins/php-backend-sdlc"`), so installers track `main`.
At the first external consumer or v1.0.0 — whichever comes first — the
entry switches to a pinned `git-subdir` source (`url` + `path` + `ref`
tag + `sha` commit pin) so installs become reproducible per release while
`main` moves freely between tags. The exact pinned-entry shape is in
[`docs/release-process.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/release-process.md).

### Release checklist

1. All seven CI jobs green on the release PR.
2. `plugin.json` version bumped per the semver rules above.
3. Changelog entry appended in `docs/release-process.md`.
4. Tag `php-backend-sdlc-vX.Y.Z` pushed (`manifest-validate` asserts the
   version match).
5. Past the pin trigger: marketplace `ref`/`sha` updated to the new tag.

## Publishing the wiki

The wiki is authored in-repo under `plugins/php-backend-sdlc/wiki/`
so it is reviewed in PRs and gated by the `markdown-lint` CI job, then
mirrored to the GitHub wiki remote by `scripts/publish-wiki.sh`.
Wiki-internal links are written in the sibling `Slug.md` form so they
resolve in the PR file view; the publish script strips the `.md` suffix
when mirroring, because the GitHub wiki resolves page links by slug
(`Slug`, not `Slug.md`). Links into repo reference docs use absolute
GitHub blob URLs.

### The one-time UI seed

A GitHub wiki's `.wiki.git` remote does not exist until the wiki has at
least one page. Before the mirror script can push, create the first wiki
page once through the GitHub UI:

1. Open the repository's **Wiki** tab on GitHub.
2. Click **Create the first page**, save any placeholder content.

This makes `https://github.com/VilnaCRM-Org/claude-plugins.wiki.git`
pushable. The seed is needed exactly once for the lifetime of the repo;
after that the mirror script owns the content.

### Running the mirror script

`scripts/publish-wiki.sh` clones the wiki remote, copies the reviewed
in-repo `wiki/*.md` over it, and commits/pushes — replacing the wiki's
content with the reviewed in-repo pages so the published wiki always
matches `main`. It does not lint: linting is enforced earlier by the
`markdown-lint` CI job and locally via `markdownlint-cli2`, not by
`publish-wiki.sh`. Pass `--dry-run` to clone read-only and show what
would be copied or pushed without any network writes, and set
`WIKI_REMOTE` to override the wiki git remote URL. Run it from the repo
root after the wiki source has merged:

```bash
plugins/php-backend-sdlc/scripts/publish-wiki.sh
```

Because the in-repo `wiki/` tree is the source of truth, never edit pages
directly in the GitHub wiki UI (beyond the one-time seed) — those edits
would be overwritten on the next mirror. Make changes in `wiki/*.md`, get
them through review and the `markdown-lint` job, then re-run the script.

## See also

- [Testing and Validation](Testing-and-Validation.md) — the adversarial
  test campaign, surfaces, and evidence behind the suites
- [Architecture](Architecture.md) — how the commands, agents, skills, and
  profile layers compose
- [Project Profile](Project-Profile.md) — the `.claude/php-sdlc.yml`
  schema whose keys `profile-keys-check` enforces
- [Permissions](Permissions.md) — the permission model the plugin ships
- [Getting Started](Getting-Started.md) — installing and running the
  plugin as a consumer
