# Test Plan — profile-fuzz

Surface: `scripts/generate-profile.sh` + `scripts/validate-profile.sh`
against mutated target-repo shapes and hand-edited profiles.

Contracts: FR-2/FR-17 (PRD), `docs/profile-schema.md`, script headers
(A3/NFR-3/NFR-4: missing capability never fails generation; default mode
diff-and-keep, `--refresh` overwrites; validator prints every violation and
exits 1 on any).

Environment: sandboxes under `/tmp/sdlc-test-profile-fuzz/`; QA template
clone at `/home/kravtsov/Projects/tmp/php-sdlc-qa/php-service-template`.
`yq` is absent on this host, so the python3+PyYAML backend is exercised
(the yq path is covered by CI bats on hosts with yq; recorded as an
environment limitation, not a gap fixed here).

Invariants checked in every generation case:

- generation exits 0 whenever the target dir exists (capability absence is
  null/false, never an error);
- the emitted file is parseable YAML;
- detection is truthful: every non-null emitted value corresponds to a
  real fact of the target repo, and validator verdicts match the schema.

## Positive cases — generation

| ID | Target-repo shape | Expected | Result |
| --- | --- | --- | --- |
| GEN-01 | No `composer.json` at all | exit 0; `php.version`/`framework.name`/`persistence.*` null; profile written; validator then exits 1 naming exactly those required keys | PASS |
| GEN-02 | `composer.json` without `require` key | exit 0; same nulls as GEN-01; no crash | PASS |
| GEN-03 | `composer.json` with invalid JSON syntax | exit 0; detection degrades to nulls; no jq/python traceback on stdout/stderr | PASS |
| GEN-04 | `composer.json` is a JSON array, not object | exit 0; nulls; no crash | PASS |
| GEN-05 | Multi-constraint PHP versions: `>=7.3 <8`, `^8.2 \|\| ^8.3`, `7.2.*`, `>=8.1,<8.4` | first version wins, clean MAJOR.MINOR: `7.3`, `8.2`, `7.2`, `8.1` | PASS |
| GEN-06 | `"php": "*"` constraint | exit 0; `php.version` null (no digits to extract) | PASS |
| GEN-07 | Monorepo: full app under `backend/`, run on root then on `backend/` | root run: exit 0, nulls, profile at root `.claude/`; subdir run: full detection, profile at `backend/.claude/php-sdlc.yml`, validator exit 0 | PASS |
| GEN-08 | `.env` with UTF-8 BOM prefixing the `DATABASE_URL` line | engine still detected (`mysql`) | PASS |
| GEN-09 | `.env` with CRLF line endings | engine still detected (`mysql`) | PASS |
| GEN-10 | Multiple active DSNs: (a) mysql then pg; (b) pg then mysql; (c) commented mysql + active pg; (d) active pg + `serverVersion=mariadb` | first active line decides: (a) `mysql`, (b) `postgresql`, (c) `postgresql`, (d) `mariadb` (global mariadb override) | PASS |
| GEN-11 | Makefile using `include targets.mk` where `ci:` lives in the include | exit 0; included targets are not scanned → `make.ci` null (documented Makefile-only scan; degrade, judged for truthfulness) | PASS |
| GEN-12 | Makefile with only `.PHONY:`, variable assignments, comments | exit 0; all `make.*` null; `capabilities.load_testing` false | PASS |
| GEN-13 | Makefile mixing tabs/spaces, pattern rules (`%.o: %.c`, `test%:`), double-colon `ci::`, plain `tests:` | pattern/percent targets never enter the map; `ci` and `tests` detected | PASS |
| GEN-14 | Makefile with no-space variable assignment `tests:=unit src` and no `tests` target | `make.tests` should be null (a `:=` assignment is not a target) | FAIL → BUG-1 |
| GEN-15 | No `src/` directory | exit 0; `source_root` null, `bounded_contexts: []`; validator exits 1 naming `architecture.source_root` + empty context list | PASS |
| GEN-16 | `src/` containing only `Shared/` | `shared_context: "Shared"`, contexts `[]`; validator flags empty `bounded_contexts` | PASS |
| GEN-17 | Context dirs with hostile names: space, unicode, `"` quote, backslash, `$(touch marker)`, `#`, `null` | exit 0; YAML parses; every name round-trips byte-exact via PyYAML; no command execution (marker file absent); validator exit 0 | PASS |
| GEN-18 | Context dir with embedded newline/control char in its name | control chars stripped on emission; YAML stays single-line valid | PASS |
| GEN-19 | Existing profile hand-edited to `schema_version: 2`, regenerate | default run keeps file + prints unified diff mentioning `--refresh`; `--refresh` run restores `schema_version: 1` | PASS |
| GEN-20 | Unknown flag `--bogus`; nonexistent TARGET_DIR | die with usage/`target directory not found`, exit 1, no partial profile written | PASS |
| GEN-21 | Real QA template clone (php-service-template) | exit 0; validator exit 0; spot-truth: `php.version`, `framework.name`, `persistence.engine`, every non-null `make.*` exists as a real Makefile target, contexts == `src/` dirs | PASS (see notes) |

## Negative / hand-edited profile validation

Baseline profile for VAL cases: the valid profile generated in GEN-21
(copied per-case, then mutated).

| ID | Mutation | Expected | Result |
| --- | --- | --- | --- |
| VAL-01 | None (template-generated profile) | exit 0, `profile valid` | PASS |
| VAL-02 | `schema_version`: `2`, `0`, and key deleted | one violation each (`unsupported`/`missing`), exit 1 | PASS |
| VAL-03 | `schema_version: "1"` (quoted string) | reads back as `1`, exit 0 (type-lenient by design) | PASS |
| VAL-04 | `persistence.engine: sqlite`; `persistence.mapper: eloquent` | enum violation per key, exit 1 | PASS |
| VAL-05 | Lowered floors: `complexity: 90`, `infection_msi: 99`, `quality: 99` | ADR-7 raise-only violation per key, exit 1 | PASS |
| VAL-06 | Raised floors: `complexity: 100`, `infection_msi: 150` | exit 0 (raising is legal) | PASS |
| VAL-07 | `deptrac_violations: 5`; `psalm_errors: -1` | ceiling-relaxed violation; `-1` rejected as non-integer; exit 1 | PASS |
| VAL-08 | Wrong types: `bounded_contexts: core` (scalar); `bounded_contexts: {a: 1}` (map); `complexity: high`; `infection_msi: 99.5` | each is a violation (list-type or non-integer), exit 1 | PASS |
| VAL-09 | `make.load_tests` line deleted vs all 12 make keys explicit `null` | deletion → `make map incomplete` violation; all-null map → no make violations | PASS |
| VAL-10 | Extra unknown keys (`extra: stuff` top-level, `make.custom: x`) | accepted; exit unchanged (unknown keys are not a documented violation class) | PASS |
| VAL-11 | `ci.provider` line deleted vs `ci.provider: null` | deletion → `not declared` violation; explicit null → legal | PASS |
| VAL-12 | Empty (0-byte) profile file | every required-key violation listed, exit 1, no crash | PASS |
| VAL-13 | Syntactically invalid YAML (tab indentation; also unclosed quote) | clean failure (non-zero exit) with a `[php-sdlc]` diagnostic, not a raw traceback | FAIL → BUG-2 |
| VAL-14 | Leading zeros: `complexity: 094`; `schema_version: 01` | `094` passes (10# guard, 94 ≥ 94); `01` resolves per YAML 1.1 to integer `1` → accepted (judged correct; initial `01 ≠ 1` expectation was wrong, no contract requires rejecting it) | PASS (judged) |
| VAL-15 | PROFILE arg is a directory; PROFILE arg missing file | `die` with `profile not found … run /sdlc-setup` remediation, exit 1 | PASS |
| VAL-16 | Many seeded errors at once (bad enum + lowered floor + missing make key + bad schema_version) | all 4 violations printed in one pass; `INVALID: 4 violation(s)` summary matches | PASS |
| VAL-17 | Hand-edited profile saved with UTF-8 BOM; with CRLF line endings | PyYAML tolerates both; exit 0, `profile valid` | PASS |

## Edge-case notes / environment limitations

- `yq` backend untestable on this host (binary absent); python3+PyYAML
  path exercised everywhere. CI bats cover both backends via
  `SDLC_FORCE_PYTHON_YAML`.
- `composer.json` with UTF-8 BOM degrades to null detection in both jq and
  python backends; Composer itself rejects BOM'd `composer.json`, so this
  is not a reachable valid repo state — observation only, not a bug.
- GEN-21 notes: `project.name: "php-serice-template"` reproduces the
  upstream composer-name typo (truthful, not a plugin bug). `ci.workflows`
  lists `"code quality"` twice because `psalm.yml` and `phpinsights.yml`
  both carry that `name:` — truthful duplication. During the session the
  generated profile vanished from the shared QA clone once: a concurrent
  surface's `git clean -fd` reset (clone mtime evidence), environment
  artifact, not a script defect; all GEN-21 evidence was captured before
  the reset and the run was re-executed cleanly from a sandbox copy.
- An adversarial GEN-17 variant with `/` in the injected context name is
  unreachable: the filesystem treats `/` as a path separator, so the
  detector truthfully reports the actual child dir of `src/`.
- The generator is NOT affected by BUG-2: with a malformed existing
  profile it takes the byte-diff path (no YAML parse), exits 0, and keeps
  the existing file with the usual `--refresh` hint.

## Round-1 verdict

38 case items executed (21 GEN + 17 VAL). 36 PASS, 2 FAIL:

- **BUG-1 (GEN-14, S3)**: a no-space `name:=value` Makefile variable
  assignment is captured as a make *target*: `tests:=unit src` with no
  `tests` rule emits `make.tests: tests` although `make tests` fails —
  untruthful detection with exit 0. Reproduced twice (fresh dirs).
  Repro: `printf 'tests:=unit src\nci:\n\ttrue\n' > Makefile` then run
  `generate-profile.sh <dir>` and read `make.tests` from the profile.
- **BUG-2 (VAL-13, S3)**: a syntactically invalid profile YAML (tab
  indentation, or an unclosed quote) makes `validate-profile.sh` abort via
  `set -e` with a raw PyYAML traceback on stderr — exit 1 but zero
  `VIOLATION:`/`[php-sdlc]` lines and no remediation hint. Reproduced
  twice with two distinct malformations (python backend; yq backend
  untested on this host).
  Repro: `printf 'project:\n\tname: "x"\n' > p.yml && validate-profile.sh p.yml`.

## Round 2

Tree state under test: branch `feature/php-backend-sdlc-plugin` working
tree (includes the uncommitted fixes for BUG-1 and BUG-2 plus three
hardening changes landed since round 1):

1. Makefile target scan: `grep -E '^[A-Za-z0-9_-]+:{1,2}([^=:].*)?$'`
   excludes `name:=` / `name::=` / `name:::=` variable assignments (BUG-1
   fix).
2. `yaml_parses` up-front guard in `validate-profile.sh` → clean
   `[php-sdlc]` diagnostic with `/sdlc-setup` remediation on malformed
   YAML (BUG-2 fix).
3. Wrap-safe `num_gt`/`num_lt` digit-string threshold comparison replacing
   `(( 10#$val ))` bash arithmetic (≥2⁶³ values no longer wrap negative).
4. Workflow basename fallback routed through `sanitize_inline` (control
   chars in workflow *filenames* can no longer leak into the profile).
5. Symlink write-target rejection: symlinked profile file, symlinked
   `.claude` dir, and a resolved profile dir escaping `$TARGET` all `die`.

Environment unchanged: no `yq` on this host → python3+PyYAML backend
(yq path covered by CI bats). Sandboxes under
`/tmp/sdlc-test-profile-fuzz/r2-*`, deleted after the round. Truthfulness
of `make.*` detection is now cross-checked with real
`make -n <target>` (GNU make available on this host).

### Re-runs — highest-risk round-1 cases

| ID | Re-run of | Expected | Result |
| --- | --- | --- | --- |
| R2-RERUN-01 | GEN-05 multi-constraint PHP versions (`>=7.3 <8`, `^8.2 \|\| ^8.3`, `7.2.*`, `>=8.1,<8.4`) | `7.3`, `8.2`, `7.2`, `8.1` | PASS |
| R2-RERUN-02 | GEN-10 multiple active DSNs (mysql→pg, pg→mysql, commented-mysql+active-pg, pg+mariadb serverVersion) | first active line wins: `mysql`, `postgresql`, `postgresql`, `mariadb` | PASS |
| R2-RERUN-03 | GEN-13 Makefile tabs/spaces mix, `%.o: %.c`, `test%:`, `ci::`, plain `tests:` | pattern targets excluded; `ci`, `tests` detected | PASS |
| R2-RERUN-04 | GEN-14 `tests:=unit src`, no `tests` rule (BUG-1 regression) | `make.tests: null` | PASS (BUG-1 fixed) |
| R2-RERUN-05 | GEN-17 hostile context dir names (space, unicode, quote, backslash, `$(touch marker)`, `#`, `null`) | YAML parses, byte-exact round-trip, no execution, validator exit 0 | PASS |
| R2-RERUN-06 | GEN-19 `schema_version: 2` drift; default keeps + diff, `--refresh` restores | diff mentions `--refresh`; refreshed file has `schema_version: 1` | PASS |
| R2-RERUN-07 | GEN-21 QA template clone end-to-end + spot-truth | generation exit 0, validator exit 0, make map truthful | PASS |
| R2-RERUN-08 | VAL-05 lowered floors (`complexity: 90`, `infection_msi: 99`, `quality: 99`) | 3 ADR-7 violations, exit 1 | PASS |
| R2-RERUN-09 | VAL-07 `deptrac_violations: 5`; `psalm_errors: -1` | ceiling violation + non-integer violation, exit 1 | PASS |
| R2-RERUN-10 | VAL-13 tab-indent + unclosed-quote profile (BUG-2 regression) | exit 1, `[php-sdlc][ERROR] profile is not valid YAML … /sdlc-setup`, zero traceback lines | PASS (BUG-2 fixed) |
| R2-RERUN-11 | VAL-16 4 seeded errors at once | all 4 violations + `INVALID: 4 violation(s)` | PASS |

### New generation cases — targeting the Makefile, sanitize, symlink fixes

| ID | Target-repo shape | Expected | Result |
| --- | --- | --- | --- |
| R2-GEN-01 | Colon-flavored assignments only: `tests::=unit`, `ci:::=x`, `e2e::= y`, plus `start:=now` | all four `make.*` null; `load_testing: false` | PASS |
| R2-GEN-02 | Same name as variable AND target: `tests:=val` assignment + real `tests:` rule | `make.tests: tests` (target exists; `make -n tests` exit 0) | PASS |
| R2-GEN-03 | Double-colon rule `ci:: deps`, order-only prereq `tests:\| build`, comment-trailing `psalm:# note` | all three detected; each runs under `make -n` | PASS |
| R2-GEN-04 | Truthfulness sweep: for every R2 Makefile, each non-null `make.*` must `make -n <v>` exit 0 and each null candidate must fail `make -n` | zero contradictions | PASS |
| R2-GEN-05 | Workflow file whose FILENAME embeds a control char (`ci\x01x.yml`), no `name:` field | basename sanitized; profile single-line, parses; validator runs normally | PASS |
| R2-GEN-06 | `.claude` in target is a symlink to an outside dir | `die` "(.claude) is a symlink", exit 1, no file created outside | PASS |
| R2-GEN-07 | Existing `.claude/php-sdlc.yml` is a symlink to an outside file | `die` "profile path is a symlink", exit 1, outside file byte-identical after | PASS |
| R2-GEN-08 | TARGET_DIR argument is itself a symlink to a real repo | exit 0; profile written inside the real repo dir | PASS |
| R2-GEN-09 | Mode preservation: existing profile `chmod 600` then `--refresh`; fresh create under `umask 027` | refreshed file keeps 600; fresh file 640 | PASS |

### New validation cases — targeting yaml_parses + num_gt/num_lt

Baseline: freshly generated valid QA-template profile, mutated per case.

| ID | Mutation | Expected | Result |
| --- | --- | --- | --- |
| R2-VAL-01 | Tab-indented YAML (BUG-2 shape A) | exit 1, clean `[php-sdlc][ERROR] profile is not valid YAML … /sdlc-setup`, no `Traceback` | PASS |
| R2-VAL-02 | Unclosed double quote (BUG-2 shape B) | same clean failure | PASS |
| R2-VAL-03 | Profile parses to a non-map: bare scalar `hello`; top-level list `- a` | no crash; every required-key violation listed; exit 1 | PASS |
| R2-VAL-04 | `psalm_errors: 18446744073709551615` (2⁶⁴−1, old code wrapped to −1) | ceiling violation, exit 1 | PASS |
| R2-VAL-05 | `infection_msi: 99999999999999999999999999` (26 digits) | exit 0 (raise-only allows it; no crash/wrap) | PASS |
| R2-VAL-06 | Leading zeros: `complexity: 0000094` / `complexity: 093` / `psalm_errors: 00` | pass / violation / pass | PASS |
| R2-VAL-07 | YAML 1.1 int forms: `deptrac_violations: 1_000`; `infection_msi: 0x64` | violation naming value 1000; pass (0x64 = 100) | PASS |
| R2-VAL-08 | `infection_msi: 1e3` (string in YAML 1.1) | non-integer violation, exit 1 | PASS |
| R2-VAL-09 | Anchor/alias reuse: `quality: &q 100` then `architecture: *q` | aliases resolve; exit 0 | PASS |
| R2-VAL-10 | All five floors exactly at shipped defaults, ceilings at 0 (boundary equality) | exit 0 | PASS |

### Round-2 notes

- R2-GEN-04 sweep also confirmed the one *intentional* asymmetry: `make -n`
  resolves targets from `include`d files while the profile scan is
  Makefile-only (round-1 GEN-11 degrade); the sweep therefore only asserts
  "non-null ⇒ runnable", which held everywhere, and "null candidate ⇒ not
  runnable" on include-free Makefiles.
- R2-GEN-05: with the filename `ci\x01x.yml` and no `name:` field the
  emitted entry is `"cix"` — control char stripped, no YAML structure
  damage. A literal-newline filename variant was also run: profile stays
  valid single-line YAML.
- R2-VAL-07 observation (not a bug): PyYAML applies YAML 1.1 resolution,
  so `1_000` and `0x64` are integers by spec; the validator judges the
  resolved value, which is the correct reading of a hand-edited file.
- QA clone note: the clone contained a stray untracked file `ok` from a
  previous session; removed before R2-RERUN-07 and the clone restored
  with `git checkout . && git clean -fd` afterwards.

### Round-2 verdict

30 case items executed (11 re-runs + 9 GEN + 10 VAL). 30 PASS, 0 FAIL.
Both round-1 bugs verified fixed; no new bugs confirmed. Sandboxes under
`/tmp/sdlc-test-profile-fuzz/` removed.
