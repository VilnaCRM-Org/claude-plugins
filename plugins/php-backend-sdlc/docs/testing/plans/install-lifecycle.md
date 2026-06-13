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

## Round 2 (verification + regression hunt)

Independent re-run against the committed tree at HEAD `ad6497e` (the
round-1 fix commit). Purpose: (1) confirm the cache actually refreshes
to the NEW source tree on reinstall — the pre-test cache was the stale
`c157eea` snapshot, seven-plus commits behind HEAD and lacking every
round-1 fix; (2) re-run all round-1 cases from the refreshed cache; (3)
hunt regressions in the five round-1 fix areas (validate-profile
digit-string ceiling/floor, generate-profile `:=` make-target parsing,
setup-preflight work-tree check, inject-governance atomic write, the
qa/finish-pr counter-transport doc contract). Scripts executed FROM THE
CACHE with `CLAUDE_PLUGIN_ROOT` set to the cache, cwd
`/home/kravtsov/Projects/tmp/php-sdlc-qa/php-service-template`.
Sandboxes under `/tmp/sdlc-test2-install-lifecycle/`, removed after the
run. No git mutations. Host: claude 2.1.173, gh 2.92.0 (authed), bmalph
2.11.0, jq, python3+PyYAML (`yq` absent), bats 1.11.1,
markdownlint-cli2 0.22.1.

### Lifecycle re-runs (real `claude` CLI)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R2-IL-P1 | `plugin details` inventory | Skills(29)=21 lib+8 `sdlc*`, Agents(6), Hooks/MCP/LSP 0 | PASS |
| R2-IL-P2 | `plugin list` state | present, 0.1.0, user, enabled | PASS |
| R2-IL-P3 | `plugin uninstall …@vilnacrm-plugins` | exit 0; gone from list; registry entry removed; stale cache dir retained but inert | PASS |
| R2-IL-P4 | reinstall after uninstall (stale cache present) | exit 0; re-enabled at 0.1.0; registry `gitCommitSha` = HEAD `ad6497e` (was `c157eea`) | PASS |
| R2-IL-P5 | `plugin update` on fresh install | exit 0; `already at the latest version (0.1.0)` | PASS |
| R2-IL-P6 | cache vs tracked source byte-identity | 106 tracked files: 0 missing, 0 differ vs HEAD-committed; the only working-tree drift (plan `.md` files) is uncommitted edits from parallel round-2 agents — cache == HEAD-committed for every one | PASS |
| R2-IL-P7 | exec bits in refreshed cache | 7 `scripts/*.sh` = 775 (u+x); `lib/common.sh` = 664 (sourced, self-guards exec); `tests/fixtures/bin/{bmalph,claude,gh}` = 775; all match source | PASS |
| R2-IL-P8 | relative md links inside cache | 232 links checked, 0 broken | PASS |
| R2-IL-P9 | `setup-preflight.sh --report` from cache, env=cache, cwd=QA template | sources `lib/common.sh` from cache; all 8 checks PASS; exit 0 | PASS |
| R2-IL-P9b | `generate-profile.sh` then `validate-profile.sh` from cache against QA template | profile created (engine `postgresql` from active `pdo_pgsql`, commented `mysql://` DSN excluded; make targets resolved); validate exit 0 | PASS |
| R2-IL-P10 | `plugin validate` on plugin dir + marketplace root | both exit 0, `Validation passed` | PASS |
| R2-IL-N1 | `plugin details no-such-plugin-xyz` | exit 1; clean not-found, no stack trace | PASS |
| R2-IL-N2 | second uninstall while not installed | exit 1; clean error naming the plugin | PASS |
| R2-IL-N3 | install bogus plugin from marketplace | exit 1; clean error; no cache dir created | PASS |
| R2-IL-N4 | (a) `resolve_plugin_root` with bogus `CLAUDE_PLUGIN_ROOT`; (b) preflight with same bogus env | (a) die exit 1 `CLAUDE_PLUGIN_ROOT points to a missing directory`; (b) exit 0, env harmless (self-locates) | PASS |
| R2-IL-E3 | install while already installed | exit 0; idempotent `already installed`; still enabled | PASS |
| R2-IL-E4 | disable then enable round trip | status toggles; cache byte-unchanged after | PASS |
| R2-IL-E5 | grep cache scripts for `/home/kravtsov/Projects` | none in `scripts/` | PASS |
| R2-IL-E6 | preflight from cache WITHOUT `CLAUDE_PLUGIN_ROOT` | self-locates via `BASH_SOURCE`; all checks PASS, exit 0 | PASS |

### Cache-refresh verification (the headline case)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R2-IL-CR1 | pre-reinstall cache content signature | stale `c157eea`: `num_gt`=0, `write_managed`=0, work-tree fix absent — lacks every round-1 fix | CONFIRMED stale |
| R2-IL-CR2 | post-reinstall cache content | refreshed to HEAD: `num_gt`=4 in `validate-profile.sh`, `write_managed`=3 in `inject-governance.sh`, work-tree `== "true"` guard + `[^=:]` make guard present; full `diff -rq` of scripts/commands/agents vs source = empty | PASS — reinstall re-snapshots the cache to the NEW tree |

### Round-1 regression re-verification (from cache)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R2-IL-WT1 | preflight in a bare repo | git-repo FAIL (round-1 fix; was a false PASS) | PASS |
| R2-IL-WT2 | preflight inside a `.git/` dir | git-repo FAIL | PASS |
| R2-IL-WT3 | preflight in a non-repo dir | git-repo FAIL with remediation | PASS |
| R2-IL-WT4 | preflight in a normal work tree | git-repo PASS | PASS |
| R2-IL-VP1 | `deptrac_violations: 18446744073709551615` (2^64-1 ceiling) | VIOLATION, never wrapped to negative (ADR-7) | PASS |
| R2-IL-VP2 | leading-zero ceiling `00` / `"007"` | `00`→0 valid; `007`→magnitude 7 > 0 VIOLATION | PASS |
| R2-IL-VP3 | floor at/below default (94 / 93) and huge raise (`99999999999999999999`) | 94 valid, 93 VIOLATION, huge raise valid | PASS |
| R2-IL-VP4 | malformed YAML profile | clean `[php-sdlc]` diagnostic, no backend traceback | PASS |
| R2-IL-MK1 | Makefile with `tests := v`, `psalm:=v` (assignments) vs real `ci`/`start`/`deptrac` targets, plus a name appearing as both `::=` and a real target | assignments → null; real targets (incl. the dual `ci`) detected; bare `tests:`, `ci::`, comment-only prereq all resolve correctly | PASS |
| R2-IL-GV1 | inject-governance from cache: fresh create, idempotency, CRLF tolerance | one block; second run unchanged; CRLF file not duplicated, user content kept | PASS |
| R2-IL-GV2 | inject-governance symlink rejection | `CLAUDE.md -> outside` refused; outside file intact; link not followed | PASS |
| R2-IL-GV3 | inject-governance write_managed on read-only TARGET | clean die `cannot create temp file`; existing `CLAUDE.md` NOT truncated; no leftover `.sdlc-governance.*` temp | PASS |
| R2-IL-GV4 | inject-governance `--diff` preview | no write to `CLAUDE.md` | PASS |
| R2-IL-CT1 | counter-transport docs in cache (`sdlc-qa.md`, `qa-manual-tester.md`, `sdlc-finish-pr.md`) | command commits to passing the iteration number; agent expects + resumes from it; `/sdlc-qa` defines the `MAX_ITERATIONS=5` guard; finish-pr owns counter B — internally consistent, no doc-reality gap | PASS |
| R2-IL-BATS | full bats suite from cache (164 tests) | every round-1 fix test passes (bare repo, `.git/` dir, uint64-wrap ceiling, huge raise, malformed YAML); 162 pass; the 2 non-passes (#56 plugin.json-name == dir, #58 marketplace.json) are test-harness layout assumptions that only hold in the SOURCE tree — both PASS when the suite runs from source (exit 0, 164/164) | PASS (no plugin defect) |

### Notes (Round 2)

- Headline result (R2-IL-CR1/CR2): reinstall DOES refresh the cache to
  the current source tree. The pre-test cache was genuinely stale
  (`c157eea`, lacking all round-1 fixes); after `uninstall` +
  `install` the cache is byte-identical to HEAD `ad6497e` and the
  registry `gitCommitSha` advanced to HEAD. The version-gated `update`
  no-resync from round-1 IL-E1 still stands (update on an unchanged
  0.1.0 reports already-latest and syncs nothing) — uninstall +
  reinstall is the dev-loop refresh path, and it works.
- R2-IL-BATS: running the cached bats suite surfaced two failures
  (#56, #58) that are NOT plugin defects. They assert repo-layout
  invariants — `basename(PLUGIN_ROOT) == plugin.json .name` and the
  existence of `REPO_ROOT/.claude-plugin/marketplace.json` — that by
  design only hold in the source tree. In the per-version install
  cache `PLUGIN_ROOT` is `…/php-backend-sdlc/0.1.0` (basename `0.1.0`)
  and the repo-level `marketplace.json` is not snapshotted (the cache
  holds only the plugin subtree). Both tests PASS from source. The
  cache content is correct; the tests are source-tree-relative.
- "lockfile in inject-governance" from the regression brief: the
  shipped fix uses an atomic in-dir `mktemp` + `mv` (no lockfile).
  Verified the claimed last-writer-wins/no-torn-read behavior plus the
  hardening it carries (symlink rejection, mode preservation,
  truncation safety on a read-only dir, temp-file cleanup on failure)
  — all hold.
- Every round-1 FAIL re-run in Round 2 now passes; no regressions found
  in any of the five fix areas. Confirmed NEW defects: 0.

### Verdict summary (Round 2)

- Cases run: 36 (19 lifecycle re-runs + 2 cache-refresh + 15
  regression re-verifications; sub-case repetitions and
  reproduced-twice confirmations not counted separately).
- r1FailsNowPass: true — every round-1 FAIL that was fixed and re-run
  (work-tree preflight, uint64-wrap ceiling, `:=` make parsing,
  inject-governance atomic write / CRLF, malformed-YAML diagnostic,
  counter transport) now passes from the refreshed cache.
- Confirmed defects: 0.

## Round 3 (fixes-hold proof + remaining-defect hunt)

Date: 2026-06-13. Independent re-run against the freshly installed cache
at `~/.claude/plugins/cache/vilnacrm-plugins/php-backend-sdlc/0.1.0/`
(registry `gitCommitSha` = HEAD `180a282`, `installedAt`
`2026-06-13T10:30:16Z`). The plugin was already installed fresh from the
directory marketplace and is LEFT INSTALLED. Goal: prove the round-1/2
fixes HOLD and hunt any remaining or fix-introduced defect. Per the
campaign pattern (~half of each round's fixes regress), every repro was
re-run for real (twice) and judged on observed behavior, not on commit
messages. Scripts were executed FROM THE CACHE with
`CLAUDE_PLUGIN_ROOT="$CACHE"`, cwd / target
`/home/kravtsov/Projects/tmp/php-sdlc-qa/php-service-template`.
Sandboxes under `/tmp/sdlc-test3-install-lifecycle/`, removed after the
run. No git mutations. Host: claude 2.1.177, gh 2.92.0 (authed), bmalph
2.11.0, jq 1.8.1, python3 3.14.4 + PyYAML (`yq` absent → python fallback
is the exercised path), bats 1.11.1, markdownlint-cli2 0.22.1.

### Cache integrity + inventory (real `claude` CLI)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-IL-P1 | `plugin details php-backend-sdlc` inventory | exit 0; 0.1.0; source `php-backend-sdlc@vilnacrm-plugins`; Skills(29) = 21 lib + 8 `sdlc*`; Agents(6); Hooks/MCP/LSP 0 | PASS |
| R3-IL-P2 | `plugin list` state | present, 0.1.0, scope user, enabled (`❯`) | PASS |
| R3-IL-P3 | `diff -r scripts` cache vs source | identical (7 `*.sh` + `lib/common.sh`) | PASS |
| R3-IL-P4 | byte-identity of every tracked file cache vs HEAD-committed | 106 tracked files: 0 missing, 0 differ; whole-tree `diff -r` shows only the uncommitted source-side `review-loop.md` round-3 edit, which the cache correctly lacks (cache == committed HEAD) | PASS |
| R3-IL-P5 | counts: source vs cache | 21 skill dirs, 8 command `.md`, 6 agent `.md` in BOTH; each cache skill has `SKILL.md` | PASS |
| R3-IL-P6 | exec bits in cache | 7 `scripts/*.sh` = 775; `lib/common.sh` = 664 (sourced; self-guards direct exec, exit 64); `tests/fixtures/bin/{bmalph,gh,claude}` = 775; all match source modes | PASS |
| R3-IL-P7 | relative skill links resolve in cache | 158 `../…md` markdown link occurrences across `skills/`; all targets (incl. `../SKILL.md` from `examples/`+`reference/` subdirs and `../code-organization/DIRECTORY-STRUCTURE.md`) resolve to existing files inside the cache; 0 broken; 0 symlinks; 0 dangling (`find -L`) | PASS |
| R3-IL-P8 | `plugin validate` plugin dir + marketplace root | both exit 0, `Validation passed`; marketplace lists `php-backend-sdlc` with `./plugins/php-backend-sdlc` source (ADR-9) | PASS |
| R3-IL-N1 | `plugin details no-such-plugin-xyz-r3` | exit 1; clean not-found with remediation; no stack trace | PASS |
| R3-IL-E5 | grep cache `scripts/` for `/home/kravtsov/Projects` | 0 hits; no absolute source path baked into any cached script | PASS |

### Scripts run FROM THE CACHE (env=cache, target=QA template)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-IL-S1 | `setup-preflight.sh --report` from cache, `CLAUDE_PLUGIN_ROOT=$CACHE`, cwd=QA | all 8 checks PASS (git-repo, claude 2.1.177, gh 2.92.0 authed, bmalph 2.11.0, doctor deferred on fresh repo, python3+PyYAML, jq); exit 0 | PASS |
| R3-IL-S2 | `strace` proof of cache sourcing | `setup-preflight.sh` opens `…/0.1.0/scripts/lib/common.sh` (THE CACHE path) — scripts self-locate via `BASH_SOURCE`, not `CLAUDE_PLUGIN_ROOT` | PASS |
| R3-IL-S3 | `generate-profile.sh "$QA"` from cache | profile created at `.claude/php-sdlc.yml`; engine `postgresql` (active `pdo_pgsql` + `postgres://`; the two commented `# DB_URL=` mysql/postgresql lines excluded — round-1 comment fix holds); `make.tests=test`/`e2e=null` match Makefile; `project.name="php-serice-template"` faithfully from composer `.name` (upstream typo, not a script bug) | PASS |
| R3-IL-S4 | `validate-profile.sh` from cache on the generated profile | `profile valid`; exit 0 | PASS |
| R3-IL-S5 | idempotency (NFR-3): re-run generate without `--refresh` | `profile unchanged`; md5 stable; exit 0 | PASS |
| R3-IL-S6 | `--refresh` with identical detection | `profile unchanged`; content md5 stable; exit 0 | PASS |
| R3-IL-S7 | bogus `CLAUDE_PLUGIN_ROOT=/nonexistent` against preflight + generate | both exit 0 (scripts never consume the plugin root; self-locate via `BASH_SOURCE`) | PASS |
| R3-IL-S8 | `resolve_plugin_root` die contract (bogus dir) | `die` exit 1, `[php-sdlc][ERROR] CLAUDE_PLUGIN_ROOT points to a missing directory: …`; valid dir prints the root, exit 0 | PASS |

### Round-1/2 fix re-verification FROM THE CACHE

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-IL-WT1 | preflight inside a `.git/` dir | git-repo FAIL, exit 1 (R1 work-tree fix) | PASS |
| R3-IL-WT2 | preflight in a bare repo | git-repo FAIL, exit 1 | PASS |
| R3-IL-WT3 | preflight in a truly isolated `mktemp -d` (outside any repo) | git-repo FAIL with remediation, exit 1 | PASS |
| R3-IL-WT4 | preflight in a real work tree (QA template) | git-repo PASS | PASS |
| R3-IL-MK1 | generate-profile on Makefile with `tests := v`, `psalm ::= v` (assignments) vs real `ci`/`deptrac`/`start`/`test` targets | `tests`→`test` (real), `psalm`→null (assignment excluded), `ci`/`deptrac`/`start` detected; absent targets null (R1 `:=` fix holds, NFR-4) | PASS |
| R3-IL-RL1 | `ai-review-loop.sh --max-iterations` ceiling (R2 Bug 2) | 1000/999/500 pass validation (reach agent resolution); 1001, `2^64`, 22-digit all rejected `must not exceed 1000`, exit 1; `0` rejected `must be a positive integer`; no uint64 wrap (wrap-safe `num_gt`) | PASS |
| R3-IL-RL2 | malformed-YAML profile guard (R2 Bug 10) | one clean `[php-sdlc][ERROR] profile is not valid YAML: <path> (…)` naming the file + remediation, exit 1, NO python traceback, in default AND `SDLC_FORCE_PYTHON_YAML=1` paths; valid `[claude]` / empty profile NOT over-rejected (agent resolves, loop runs) | PASS |
| R3-IL-BATS | full bats suite from cache (188 tests) | 186 pass; the only 2 not-ok (#63 `plugin.json .name == basename(PLUGIN_ROOT)`, #65 repo-level `marketplace.json` exists) are source-tree-layout assumptions that hold ONLY in source — both PASS from source (`component-counts.bats` 0 not-ok); cache content is correct, not a plugin defect | PASS |

### Notes (Round 3)

- Cache is a faithful snapshot of HEAD `180a282`: `diff -r scripts`
  identical; all 106 tracked files byte-identical to the committed tree.
  The single whole-tree `diff -r` divergence is the source-side
  uncommitted round-3 edit to `review-loop.md`; the cache reflects
  committed content, so this is expected, not drift.
- False alarm ruled out before recording: an early "non-repo" preflight
  sandbox reported git-repo PASS because it was created UNDER a
  directory already `git init`'d in the same sandbox (its toplevel was
  the parent). Re-run in a truly isolated `mktemp -d` outside any repo
  → git-repo FAIL, exit 1. The work-tree fix is correct; the first
  result was a test-setup artifact.
- `project.name: "php-serice-template"` in the generated profile carries
  the upstream template's composer `.name` typo verbatim
  (`vilnacrm/php-serice-template`). generate-profile faithfully reads
  the source field; this is an upstream data point, not a plugin defect.
- The 2 cache bats failures (#63, #65) are unchanged in nature from
  round-2 (#56, #58 then); only the numbering shifted as the suite grew
  to 188 tests. They assert source-tree layout invariants that the
  per-version install cache (`…/0.1.0`, plugin subtree only)
  deliberately does not satisfy.

### Verdict summary (Round 3)

- Cases run: 27 (10 cache-integrity/inventory + 8 cache-script runs + 9
  round-1/2 fix re-verifications; sub-case repetitions and
  reproduced-twice confirmations not counted separately).
- priorFailsRechecked: 9 (R1 work-tree ×4, R1 `:=` make parsing, R2 Bug
  2 ceiling, R2 Bug 10 malformed-YAML, plus the 2 cache bats layout
  assumptions) — all re-run from the cache.
- priorFailsNowPass: 9 — every prior FAIL that was fixed and re-run
  still passes from the freshly installed cache; the 2 cache bats
  not-ok are confirmed (twice) as source-tree-layout assumptions, not
  regressions.
- Confirmed defects: 0. Plugin LEFT INSTALLED at 0.1.0, enabled.
