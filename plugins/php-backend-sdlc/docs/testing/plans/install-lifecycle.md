# Test Plan — install-lifecycle (Round 1)

Surface: real `claude` CLI (2.1.173) plugin lifecycle for
`php-backend-sdlc@vilnacrm-plugins` against the local directory
marketplace at `/home/kravtsov/Projects/claude-plugins`: details
inventory, uninstall, reinstall, update, and integrity of the installed
cache copy at
`~/.claude/plugins/cache/vilnacrm-plugins/php-backend-sdlc/<version>/`.

Contracts: `.claude-plugin/plugin.json` and the marketplace manifest,
plugin `README.md` (Install section, 21-skill library + 8 commands +
6 subagents), `scripts/lib/common.sh` plugin-root resolution contract,
`commands/sdlc-setup.md` `${CLAUDE_PLUGIN_ROOT}` invocations, PRD
`specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md`,
`docs/testing/test-strategy.md` severity ladder.

## Method

- No git mutations in `/home/kravtsov/Projects/claude-plugins`; the
  branch stays `feature/php-backend-sdlc-plugin` throughout.
- Sandboxes for script execution: `/tmp/sdlc-test-install-lifecycle/`,
  deleted after the run.
- Source-vs-cache comparison uses tracked files only (`git ls-files`)
  for the completeness contract; untracked working-tree files are
  recorded informationally (IL-E2).
- "CACHE" below means the versioned install dir reported by
  `installed_plugins.json` (`.../php-backend-sdlc/0.1.0`).
- Every FAIL is reproduced twice before being recorded; installed +
  enabled state is restored at the end (IL-R1).
- Note on inventory counting: CLI ≥ 2.1 unifies commands into the
  "Skills" section of `plugin details`, so the expected skills line is
  21 library skills + 8 `sdlc*` commands = 29 entries, plus 6 agents.

## Positive cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| IL-P1 | `claude plugin details php-backend-sdlc` while installed | exit 0; version 0.1.0; source `php-backend-sdlc@vilnacrm-plugins`; skills list = 21 skill dirs + 8 command names, agents list = the 6 `agents/*.md`; 0 hooks/MCP/LSP | PASS |
| IL-P2 | `claude plugin list` state | plugin present, version 0.1.0, scope user, enabled | PASS |
| IL-P3 | `claude plugin uninstall php-backend-sdlc@vilnacrm-plugins` | exit 0; gone from `plugin list`; registry entry removed; cache copy removed or inert | PASS |
| IL-P4 | `claude plugin install php-backend-sdlc@vilnacrm-plugins` after uninstall | exit 0; reappears enabled at 0.1.0; cache repopulated; registry `gitCommitSha` = current HEAD | PASS |
| IL-P5 | `claude plugin update php-backend-sdlc` on fresh install | exit 0; reports up-to-date or re-syncs; cache still consistent afterwards | PASS |
| IL-P6 | Cache completeness vs tracked source: every `commands/`, `agents/`, `skills/`, `scripts/`, `docs/`, `tests/`, `README.md`, `.claude-plugin/plugin.json` file | every tracked file present in CACHE and byte-identical to the working tree | PASS |
| IL-P7 | Executable bits on `scripts/*.sh` + `scripts/lib/common.sh` + `tests/fixtures/bin/*` in CACHE | mode 755 (or at least u+x) preserved exactly as in source | PASS |
| IL-P8 | Relative markdown links between cache files (`skills/*/SKILL.md` cross-references, `README.md` → `docs/*`, command/agent doc links) | every relative link target resolves to an existing file INSIDE the cache | PASS |
| IL-P9 | Run `"$CACHE/scripts/setup-preflight.sh" --report` from a sandbox git repo with `CLAUDE_PLUGIN_ROOT="$CACHE"` | script runs from cache, sources `lib/common.sh` from cache, prints full PASS/FAIL table; exit reflects environment, not a path error | PASS |
| IL-P10 | `claude plugin validate` on the plugin dir and on the marketplace root | both exit 0, manifest valid | PASS |

## Negative cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| IL-N1 | `claude plugin details no-such-plugin-xyz` | non-zero exit; clean "not found" error, no stack trace | PASS |
| IL-N2 | Second `claude plugin uninstall` while not installed | non-zero exit; clean error naming the plugin | PASS |
| IL-N3 | `claude plugin install no-such-plugin-xyz@vilnacrm-plugins` | non-zero exit; clean error; no cache dir created | PASS |
| IL-N4 | Missing-dir `CLAUDE_PLUGIN_ROOT` contract: (a) source cache `lib/common.sh`, call `resolve_plugin_root` with `CLAUDE_PLUGIN_ROOT=/nonexistent-qa-dir`; (b) same env against `setup-preflight.sh --report` | (a) die `CLAUDE_PLUGIN_ROOT points to a missing directory: …`, exit 1; (b) preflight unaffected (it never consumes the plugin root — scripts self-locate via `BASH_SOURCE`) | PASS (a: die exit 1; b: exit 0, bogus env harmless; see notes) |

## Edge cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| IL-E1 | Stale-cache refresh: cache snapshot predating HEAD (observed pre-test: missing `docs/evidence/*`, older scripts) then `claude plugin update` | update re-syncs the cache to the marketplace working tree; previously-missing tracked files appear; changed scripts match HEAD | DEVIATION — update is version-gated: exits 0 with `already at the latest version (0.1.0)` and leaves stale cache content untouched (reproduced twice). Judged NOT a defect: consistent with `docs/release-process.md` ("every release bumps `version`") and standard package semantics; re-sync path is uninstall + reinstall (verified). See notes |
| IL-E2 | Untracked working-tree files (`docs/testing/`) at install time | informational: record whether directory-source install copies untracked files; contract covers tracked files only | PASS (informational — untracked files ARE copied; see notes) |
| IL-E3 | `claude plugin install` while already installed | clean "already installed"-style outcome or idempotent reinstall; no corruption, still enabled | PASS |
| IL-E4 | `claude plugin disable` then `claude plugin enable` round trip | status toggles in `plugin list`; cache untouched | PASS |
| IL-E5 | Grep CACHE scripts/docs for baked-in absolute source paths (`/home/kravtsov/Projects`) | no absolute source-tree path required at runtime by any cached script | PASS (hits are doc/test-plan prose only, none load-bearing) |
| IL-E6 | Run `"$CACHE/scripts/setup-preflight.sh"` from cache WITHOUT `CLAUDE_PLUGIN_ROOT` set | `common.sh` self-locates via `BASH_SOURCE`; identical behavior to IL-P9 | PASS |

## Restore

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| IL-R1 | End state after all cases | plugin installed at 0.1.0, enabled, cache complete (IL-P6 re-checked post-restore); sandboxes under `/tmp/sdlc-test-install-lifecycle` deleted | PASS |

## Notes and observations

- IL-P1: `plugin details` shows "Skills (29)" because CLI 2.1.x folds
  the 8 commands into the unified skills inventory; all 21 + 8 + 6
  names match the source tree one-for-one (set-diff empty). Not a
  defect.
- IL-P3: uninstall removes the registry entry and the plugin from
  `plugin list`; the versioned cache dir is retained on disk but inert
  (no registry pointer). Reinstall re-snapshots it from the
  marketplace directory.
- IL-P4: after reinstall the registry `gitCommitSha` equals the repo
  HEAD (`c157eea…`) and the cache is byte-identical to the working
  tree (file list, contents, and permission modes all match).
- IL-P5/IL-E1: `update` compares only `version` in `plugin.json`.
  With an unchanged 0.1.0 it exits 0 reporting already-latest and
  performs no content sync — same-version drift (e.g. the genuinely
  stale pre-test snapshot at `21268f6`, seven commits behind HEAD
  including the fr-nfr-gate symlink fix) is not propagated by
  `update`. Consistent with `docs/release-process.md` (every release
  bumps the version), so classified informational, not a defect.
  Dev-loop refresh is uninstall + reinstall.
- CLI naming quirk (informational): `claude plugin update
  php-backend-sdlc` (bare name) fails with `Plugin "php-backend-sdlc"
  not found` while `details`/`uninstall` accept the bare name; the
  `plugin@marketplace` form works everywhere. claude CLI behavior,
  not a plugin artifact.
- IL-N4/IL-E6: no shipped script invokes `resolve_plugin_root`;
  every script self-locates via `BASH_SOURCE`, so all seven scripts
  run correctly from the cache with `CLAUDE_PLUGIN_ROOT` set,
  unset, or bogus. The library die-path contract itself holds
  (`[php-sdlc][ERROR] CLAUDE_PLUGIN_ROOT points to a missing
  directory: …`, exit 1).
- IL-P9: full preflight from the cache passes all 8 checks (git repo,
  claude 2.1.173, gh 2.92.0 authed, bmalph 2.11.0, doctor deferred on
  fresh repo, python3+PyYAML, jq), exit 0. A second cache script
  (`validate-profile.sh` against the cache's `valid.yml` fixture)
  also runs clean from the cache, exit 0.
- IL-E2: directory-source installs snapshot the whole plugin dir
  including untracked files (`docs/testing/` was untracked yet
  copied); the tracked-files completeness contract is met a fortiori.

## Verdict summary

- Cases run: 21 (10 positive + 4 negative + 6 edge + restore;
  deviation-confirmation re-runs not counted).
- Confirmed defects: 0. Two informational deviations recorded
  (version-gated `update` no-resync at IL-E1; bare-name `update`
  lookup quirk) — both claude CLI semantics consistent with or
  outside the plugin's shipped contract, per the strategy's
  "not bugs" carve-outs.
- Environment notes: host has bmalph 2.11.0, gh 2.92.0 (authed),
  jq, python3+PyYAML; `yq` absent (python fallback path is the one
  exercised).
