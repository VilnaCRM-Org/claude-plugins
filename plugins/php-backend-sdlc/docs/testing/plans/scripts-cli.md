# Test Plan — scripts-cli (round 1)

Surface: the 7 shipped `scripts/*.sh` plus `scripts/lib/common.sh`, exercised
as real CLI invocations against disposable sandboxes under
`/tmp/sdlc-test-scripts-cli/`. Contracts: each script's header comment, the
bats suites in `tests/`, and the PRD
(`specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md`).

Conventions:

- Stub `claude`/`gh`/`bmalph` come from `tests/fixtures/bin` (or purpose-built
  routing/stateful wrappers where one static response is not enough).
- "PATH sandbox" = a minimal `PATH` containing only an allowlisted set of
  tools, used to simulate missing `yq`/`jq`/`python3`/`gh`/`claude`.
- The host lacks `yq`; yq-backend cases ran against a downloaded real
  `yq v4.44.3` binary prepended to `PATH`.
- Every case records PASS/FAIL in the Result column. FAIL rows reference the
  bug list at the bottom. OBSERVE-style cases record the observed behavior
  inline.

## lib/common.sh (CL)

### CL — positive cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| CL-P1 | `log_info` output | tagged `[php-sdlc][INFO]` line on stdout | PASS |
| CL-P2 | `log_warn`/`log_error` | tagged lines on stderr only, stdout empty | PASS |
| CL-P3 | `yaml_get` scalar + boolean via yq backend | scalar verbatim; booleans `true`/`false` | PASS |
| CL-P4 | `yaml_get` forced python fallback (`SDLC_FORCE_PYTHON_YAML=1`) | identical scalar and normalized booleans | PASS |
| CL-P5 | `yaml_has` explicit-null vs undeclared; `yaml_is_list` seq vs scalar | null key exists (0), undeclared (1); list 0, scalar 1 | PASS |
| CL-P6 | `profile_get` with default; `profile_require` present key | default printed when absent; value printed when present | PASS |
| CL-P7 | `resolve_plugin_root` with and without `CLAUDE_PLUGIN_ROOT` | env dir wins; falls back to lib-derived root | PASS |

### CL — negative cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| CL-N1 | execute `common.sh` directly | refusal message, exit 64 | PASS |
| CL-N2 | `yaml_get` on missing file | `die` exit 1, names the file | PASS |
| CL-N3 | `CLAUDE_PLUGIN_ROOT` → missing dir | `resolve_plugin_root` dies | PASS |
| CL-N4 | `profile_require` on missing key | dies naming the key | PASS |
| CL-N5 | `require_yaml_toolchain`, PATH sandbox without yq/PyYAML | dies with install hint | PASS |

### CL — edge cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| CL-E1 | `yaml_get` on CRLF YAML file (yq and python backends) | scalar parses, no `\r` artifacts | PASS |
| CL-E2 | YAML file path with spaces + unicode | reads normally | PASS |
| CL-E3 | `claude_run_once`: non-zero exit / `is_error:true` / malformed JSON | returns 1 with the matching WARN for each | PASS |
| CL-E4 | `claude_extract_result` with jq vs without jq (python3 only) | identical `.result` text | PASS |
| CL-E5 | `yaml_get` on 10k-key YAML | correct value, completes quickly | PASS |

## setup-preflight.sh (SP)

### SP — positive cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| SP-P1 | all checks green (stubs + git repo) | every check PASS, exit 0, `preflight OK` | PASS |
| SP-P2 | `--report` all green | full table, exit 0 | PASS |
| SP-P3 | fresh repo without `_bmad/` | bmalph-doctor PASS as "deferred" | PASS |
| SP-P4 | `_bmad/` present, doctor exit 0 | bmalph-doctor PASS | PASS |

### SP — negative cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| SP-N1 | unknown argument | usage `die`, exit 1 | PASS |
| SP-N2 | not a git repo | first-FAIL abort with clone/init remediation, exit 1 | PASS |
| SP-N3 | claude 2.0 (< 2.1 floor) | FAIL with npm remediation; later checks not printed (default mode) | PASS |
| SP-N4 | gh unauthenticated (`STUB_GH_AUTH_EXIT=1`) | FAIL gh-auth, remediation `gh auth login` | PASS |
| SP-N5 | bmalph missing from PATH | FAIL naming the binary | PASS |
| SP-N6 | `_bmad/` present, doctor exit 1 | FAIL with doctor/init remediation | PASS |
| SP-N7 | PATH sandbox without yq and PyYAML | yaml-toolchain FAIL, remediation | PASS |
| SP-N8 | PATH sandbox without jq and python3 | json-toolchain FAIL, remediation | PASS |

### SP — edge cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| SP-E1 | run inside a bare git repository | git-repo check should not claim "inside a git work tree" | FAIL → Bug 1 |
| SP-E2 | exact floor versions (claude 2.1, bmalph 2.11.0, gh 2.0.0) | inclusive floors: PASS | PASS |
| SP-E3 | `--report` with multiple failures | every FAIL row listed with remediation, exit 1 | PASS |
| SP-E4 | extra argument after `--report` | ignored or usage error — observe | PASS (observed: silently ignored; `case "${1:-}"` checks only `$1`; cosmetic) |
| SP-E5 | `claude --version` prints garbage (no digits) | FAIL "cannot parse a version" | PASS |
| SP-E6 | run from inside `.git/` of a normal repo | same class as SP-E1 — observe | FAIL → Bug 1 (same root cause) |

## generate-profile.sh (GP)

### GP — positive cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| GP-P1 | stub-repo fixture detection | php 8.4, symfony 7.3, api_platform "4.2", graphql true, doctrine-odm/mongodb (fixture declares the ODM bundle), contexts Catalog+Order, shared Shared, full make map, github-actions workflows, coderabbit true | PASS |
| GP-P2 | second run, no flags | `profile unchanged`, file byte-identical, exit 0 | PASS |
| GP-P3 | existing differing profile, no flags | unified diff printed, file kept, exit 0 | PASS |
| GP-P4 | `--refresh` over differing profile | file overwritten, `profile refreshed` | PASS |
| GP-P5 | generated profile → `validate-profile.sh` | valid, exit 0 (FR-17 AC) | PASS |

### GP — negative cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| GP-N1 | unknown flag `--bogus` | usage `die` | PASS |
| GP-N2 | nonexistent TARGET_DIR | `die` target not found | PASS |
| GP-N3 | TARGET_DIR is a regular file | `die` target not found | PASS |
| GP-N4 | PATH sandbox without YAML toolchain | `die` no YAML toolchain | PASS |
| GP-N5 | yq only, no jq/python3 | `die` need jq or python3 | PASS |
| GP-N6 | read-only `.claude/` dir | clean `die` "cannot create temp file" | PASS |

### GP — edge cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| GP-E1 | empty dir, not a git repo | everything null/false, exit 0 (A3) | PASS |
| GP-E2 | bare git repo as TARGET | no crash, profile written into bare-repo dir | PASS |
| GP-E3 | TARGET path with spaces + unicode | profile written at correct path, exit 0 | PASS |
| GP-E4 | malformed `composer.json` | nulls, exit 0, no crash | PASS |
| GP-E5 | CRLF `composer.json`/`Makefile`/`.env` (ORM flavor, commented pgsql DSN + active mysql DSN) | detection still correct (engine mysql, no `\r` leakage into values) | PASS |
| GP-E6 | Makefile with 20k targets | completes < 10 s, map correct | PASS (268 ms) |
| GP-E7 | two TARGET_DIR args | usage contract says one — observe | PASS (observed: last wins silently; cosmetic, logged as note) |
| GP-E8 | symlinked `.claude` dir / profile file | refused, symlink target untouched | PASS |
| GP-E9 | no stray `.php-sdlc.yml.*` temp files after create/refresh runs | none left | PASS |
| GP-E10 | unicode bounded-context dir names | emitted quoted, profile validates | PASS |

## validate-profile.sh (VP)

### VP — positive cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| VP-P1 | valid fixture profile | exit 0, `profile valid`, zero VIOLATION lines | PASS |
| VP-P2 | valid fixture, forced python fallback | exit 0 | PASS |
| VP-P3 | no-arg run from repo cwd | resolves `$PWD/.claude/php-sdlc.yml` | PASS |

### VP — negative cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| VP-N1 | missing profile file | `die` with `/sdlc-setup` hint, exit 1 | PASS |
| VP-N2 | bad enum (`persistence.mapper: eloquent`) | VIOLATION names key + value, exit 1 | PASS |
| VP-N3 | lowered threshold | VIOLATION cites ADR-7 raise-only, exit 1 | PASS |
| VP-N4 | `schema_version: 2` | VIOLATION names schema_version, exit 1 | PASS |
| VP-N5 | make map missing a key | VIOLATION names `make.<key>`, exit 1 | PASS |
| VP-N6 | scalar `bounded_contexts` | VIOLATION "must be a list", exit 1 | PASS |
| VP-N7 | non-integer quality value | VIOLATION "is not an integer", exit 1 | PASS |
| VP-N8 | 0-byte profile file | violations (not a crash), exit 1 | PASS |

### VP — edge cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| VP-E1 | profile path with spaces + unicode | validates normally | PASS |
| VP-E2 | CRLF profile file | parses on available backends, exit 0 | PASS |
| VP-E3 | directory passed as PROFILE_FILE | `die` profile not found | PASS |
| VP-E4 | extra positional args | contract is one arg — observe | PASS (observed: `$2+` silently ignored; cosmetic, logged as note) |
| VP-E5 | leading-zero value `complexity: 094` | no octal parse error; 94 ≥ floor passes | PASS |
| VP-E6 | raised thresholds above defaults | accepted, exit 0 | PASS |
| VP-E7 | uint64-overflow ceiling value `psalm_errors: 18446744073709551615` | should be rejected (> 0) — observe bash arithmetic wrap | FAIL → Bug 2 (exit 0, "profile valid", twice; floor-side wrap `infection_msi: 2^64` rejects, but with a misleading "lowered below" message) |

## inject-governance.sh (IG)

### IG — positive cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| IG-P1 | empty target dir | CLAUDE.md + AGENTS.md created, exactly one block each | PASS |
| IG-P2 | existing user content | block appended; bytes outside markers identical | PASS |
| IG-P3 | second run | `unchanged`, zero diff (NFR-3) | PASS |
| IG-P4 | stale block content | replaced in place, position preserved | PASS |
| IG-P5 | `--diff` | preview printed, files not written | PASS |

### IG — negative cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| IG-N1 | unknown flag | usage `die` | PASS |
| IG-N2 | missing TARGET_DIR | `die` target not found | PASS |
| IG-N3 | symlinked CLAUDE.md | refused; symlink target byte-identical | PASS |

### IG — edge cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| IG-E1 | duplicate balanced blocks | collapse to one at first position | PASS |
| IG-E2 | orphan BEGIN marker | marker line removed, user content kept, fresh block appended | PASS |
| IG-E3 | END before BEGIN (count-balanced) | user content preserved, repaired to one block | PASS |
| IG-E4 | file without trailing newline | separator added, content intact | PASS |
| IG-E5 | CRLF file containing a CRLF managed block | markers should still be recognized — observe | FAIL → Bug 3 (2 begin markers + stale block after run; second run reports "unchanged"; reproduced twice in fresh sandboxes) |
| IG-E6 | target path with spaces + unicode | normal operation | PASS |
| IG-E7 | 30 MB CLAUDE.md (400k lines) | completes, user bytes preserved | PASS (67 ms) |
| IG-E8 | CLAUDE.md is a directory | non-zero exit — observe error quality | PASS (exit 1, raw bash "Is a directory"; UX-only, logged as note) |
| IG-E9 | read-only CLAUDE.md (chmod 444) | non-zero exit, file untouched | PASS |
| IG-E10 | SIGKILL mid-write on a huge file | partial-state risk of non-atomic `cat >` — observe | PASS (window not reproducible: kill landed before/after write; no truncation observed in 20 attempts; noted as design observation) |
| IG-E11 | existing 0-byte CLAUDE.md | block written, no stray leading garbage | PASS |

## ai-review-loop.sh (AR)

### AR — positive cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| AR-P1 | stub claude returns PASS verdict | exit 0 on iteration 1 | PASS |
| AR-P2 | FAIL then PASS (stateful stub) | exit 0 after exactly 2 iterations | PASS |
| AR-P3 | `--agents codex,claude` | codex warn+skip, claude runs, exit 0 | PASS |
| AR-P4 | agents from profile `review.ai_review_agents` | profile list honored | PASS |
| AR-P5 | ADR-8 flag set | `-p --output-format json --permission-mode acceptEdits --max-turns 30` in stub log | PASS |
| AR-P6 | `--diff-base release` in default prompt; `REVIEW_PROMPT` env override wins | both visible in stub log | PASS |

### AR — negative cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| AR-N1 | unknown argument | usage `die` | PASS |
| AR-N2 | `--max-iterations` 0 / -1 / abc / 05 | rejected as not a positive integer | PASS |
| AR-N3 | `--agents` with no value (end of argv) | clean parameter error, non-zero | PASS |
| AR-N4 | claude absent from PATH | `die` claude CLI not found | PASS |
| AR-N5 | `--agents codex` only | warn+skip, then die "no supported review agent ran", non-zero | PASS |

### AR — edge cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| AR-E1 | perpetual FAIL verdict | stops at 5 iterations, exit 1, escalation message (NFR-6) | PASS |
| AR-E2 | malformed JSON every call | exactly one retry per iteration: 2×5 stub calls, exit 1 | PASS |
| AR-E3 | `is_error:true` then clean PASS on retry | transport retry path, exit 0 | PASS |
| AR-E4 | missing verdict line | contract violation: failed iteration, NO retry (1 call/iteration) | PASS |
| AR-E5 | `--agents ","` (only separators) | empty override — observe (defaults to claude?) | PASS (observed: falls back to claude; matches "drop empty entries; default to claude"; logged as note) |
| AR-E6 | 1 MB result body ending in PASS verdict | verdict parsed, exit 0 | PASS |
| AR-E7 | verdict line with trailing space | strict per ADR-8: counted as malformed — observe | PASS (treated as contract violation; consistent with header) |
| AR-E8 | PATH sandbox without jq and python3 | degraded "malformed JSON" warnings, exit 1, never a silent PASS (preflight owns the diagnosis) | PASS |

## fr-nfr-gate.sh (FG)

### FG — positive cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| FG-P1 | verdict `FR_NFR_NEW_FINDINGS: 0` | exit 0, success status posted, NO PR comment | PASS |
| FG-P2 | verdict `FR_NFR_NEW_FINDINGS: 2` | exit 1, failure status, PR comment with findings | PASS |
| FG-P3 | `--spec-path` + `--impact-context` | both reach the claude prompt | PASS |
| FG-P4 | no origin remote | repo slug via `gh repo view` fallback | PASS |

### FG — negative cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| FG-N1 | unknown flag | usage `die` | PASS |
| FG-N2 | missing spec path | `die` with `--spec-path` remediation, before gh/claude | PASS |
| FG-N3 | `--spec-path /etc` (outside repo) | `die` boundary escape | PASS |
| FG-N4 | symlinked spec path | refused | PASS |
| FG-N5 | non-git directory | `die` "not inside a git work tree" | PASS |
| FG-N6 | claude absent | `die` claude CLI not found | PASS |
| FG-N7 | gh absent | `die` gh CLI not found | PASS |
| FG-N8 | repo with zero commits | `die` cannot resolve HEAD | PASS |

### FG — edge cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| FG-E1 | transport failure on both attempts | one retry, failure status "transport failure", exit 1 | PASS |
| FG-E2 | output without `FR_NFR_NEW_FINDINGS` line | failure status "malformed", exit 1 | PASS |
| FG-E3 | `FR_NFR_NEW_FINDINGS: 00` | parsed as 0 → success | PASS |
| FG-E4 | verdict line with trailing space | strict regex: malformed, exit 1 | PASS |
| FG-E5 | gh status/comment posts fail (exit 1) | warns, gate verdict still decides exit code | PASS |
| FG-E6 | spec dir name with spaces | containment math still correct, runs | PASS |
| FG-E7 | bare repo | `die` (no work tree) | PASS |
| FG-E8 | `--spec-path specs/../specs` | resolves inside → allowed | PASS |

## get-pr-comments.sh (PC)

### PC — positive cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| PC-P1 | full listing (fixture PR 7) | threads + issue comment + `unresolved threads: 1` | PASS |
| PC-P2 | `--unresolved-only` | resolved thread + issue comments dropped | PASS |
| PC-P3 | `--json` | canonical shape (pr, review_threads, issue_comments) | PASS |
| PC-P4 | `--json --unresolved-only` | filtered threads, `issue_comments: []` | PASS |
| PC-P5 | no `--pr` (routing gh wrapper) | PR number from `gh pr view` | PASS |

### PC — negative cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| PC-N1 | unknown flag | usage `die` | PASS |
| PC-N2 | `--pr abc` and `--pr ''` | usage / parameter error, non-zero | PASS |
| PC-N3 | gh absent from PATH | `die` gh CLI not found | PASS |
| PC-N4 | no PR for branch (gh pr view fails) | `die` "pass --pr" | PASS |
| PC-N5 | `gh api graphql` non-zero | `die` names PR and repo | PASS |

### PC — edge cases

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| PC-E1 | truncated fixture (`hasNextPage: true`) | `die` pagination guard, both human and `--json` modes | PASS |
| PC-E2 | PATH sandbox without jq (python fallback) | byte-equivalent canonical JSON | PASS |
| PC-E3 | thread with empty `comments.nodes` | human render `?:0`, no crash (jq + python paths) | PASS |
| PC-E4 | unicode + control chars in body | body survives both render paths | PASS |
| PC-E5 | `--pr 0` | passes numeric guard, gh decides — observe | PASS (gh error surfaces as `die gh api graphql failed`) |
| PC-E6 | no git repo, no origin | repo slug via `gh repo view` fallback | PASS |
| PC-E7 | 1 MB comment body | renders, no crash | PASS |

## Execution summary

- Cases executed: 149 (CL 17, SP 18, GP 21, VP 18, IG 19, AR 19, FG 20,
  PC 17); several IDs bundle multiple sub-assertions.
- Result: 145 PASS, 4 FAIL rows (SP-E1 and SP-E6 share one root cause) →
  3 confirmed bugs, each reproduced twice.
- Sandboxes under `/tmp/sdlc-test-scripts-cli/` removed after the run.

## Confirmed bugs

1. **SP-E1/SP-E6 — `setup-preflight.sh` git-repo check passes in a bare
   repo and inside `.git/`** (S3). `git rev-parse --is-inside-work-tree`
   exits 0 while printing `false` in both locations; the script tests only
   the exit code, so the check reports `PASS: git-repo — inside a git work
   tree` where there is no work tree. Repro:
   `git init --bare /tmp/b.git && cd /tmp/b.git && setup-preflight.sh`.
2. **VP-E7 — `validate-profile.sh` accepts `quality.psalm_errors:
   18446744073709551615`** (S2 per the strategy's own example: "validate
   passes invalid profile"). The 64-bit bash arithmetic in `check_ceiling`
   wraps the value to `-1`, so `-1 > 0` is false and the relaxed ceiling
   validates with exit 0 (`profile valid`) — a crafted value defeats the
   ADR-7 raise-only protection that the governance block promises
   (`validate-profile.sh rejects lowered values`).
3. **IG-E5 — `inject-governance.sh` duplicates the governance block in
   CRLF files** (S3). CRLF marker lines (`<!-- ...begin -->\r`) fail the
   exact-match tests, so a CRLF file that already carries the managed block
   is treated as marker-free and a second LF block is appended; the stale
   CRLF block (including the "do not edit" banner) survives every
   subsequent run, and re-runs report "unchanged" — contradicting the
   header contract "replaced in place on every run" / "repaired to exactly
   one block" (NFR-3).

## Notes (observations, not defects)

- SP-E4 / VP-E4 / GP-E7: extra positional arguments are silently ignored
  (or last-wins). Cosmetic divergence from single-arg usage strings.
- IG-E8: a directory named `CLAUDE.md` produces a raw bash
  "Is a directory" error (non-zero exit). UX-only.
- IG-E10: `cat "$new_file" > "$file"` is non-atomic by design (mode
  preservation); a kill in the truncate-write window could leave a partial
  file, but the window was not hittable in 20 SIGKILL attempts against a
  30 MB file.
- AR-E5: `--agents ","` falls back to the default `claude` agent, matching
  the in-code comment.

## Round 2 — fix verification + new edges

Re-ran every round-1 FAIL case against the post-fix scripts and added new
edges targeting the fixes (work-tree preflight shapes, ceiling/floor type
checks, `:=` make parsing, CRLF marker repair, transport-retry counters,
lockfile/atomic-write contention, LC_ALL=C vs UTF-8 locale). Sandboxes
under `/tmp/sdlc-test2-scripts-cli/`, real `yq v4.44.3` downloaded for the
yq backend. The bundled `tests/*.bats` suite (164 cases) passes clean.

### R2 — round-1 FAIL cases re-run (must now PASS)

| ID | Re-run case | Round-2 result |
| --- | --- | --- |
| SP-E1 | bare repo, default + `--report` mode | PASS (git-repo now FAILs correctly, exit 1; later checks still run in `--report`) |
| SP-E6 | inside a normal repo's `.git/` | PASS (git-repo FAILs, exit 1) |
| VP-E7 | `psalm_errors: 18446744073709551615` (yq + python) | PASS (VIOLATION "relaxed above 0", exit 1) |
| VP-E7b | `deptrac_violations: 2^64` ceiling | PASS (VIOLATION, exit 1) |
| VP-E7c | `infection_msi: 2^64-1` floor (a raise) | PASS (exit 0, no misleading "lowered below") |
| IG-E5 | CRLF file carrying a CRLF managed block | PASS (1 begin/1 end/1 banner, block rewritten LF, user CRLF lines kept, run 2 "unchanged") |

All six round-1 FAIL cases now PASS on both backends. Bugs 1, 2, 3 are
confirmed fixed at the root cause.

### R2 — work-tree / preflight shapes (new)

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R2-WT1 | setup-preflight inside a linked `git worktree add` work tree | git-repo PASS (real work tree), exit 0 | PASS |
| R2-WT2 | setup-preflight inside `.git/worktrees/` admin dir | git-repo FAIL, exit 1 | PASS |
| R2-WT3 | fr-nfr-gate (FG-N5) in a non-git dir | `die` "not inside a git work tree" before gh/claude | PASS |
| R2-WT4 | fr-nfr-gate (FG-E7) in a bare repo | `die` (no work tree; `--show-toplevel` exits 128) | PASS |
| R2-WT5 | fr-nfr-gate inside `.git/` with spec under `.git/specs` | `die` (no work tree) — not a containment bypass | PASS |
| R2-WT6 | fr-nfr-gate in a linked worktree, spec inside | runs, containment correct, PASS verdict, exit 0 | PASS |
| R2-WT7 | generate-profile (GP-E2) into a bare repo | profile written, no crash, exit 0 | PASS |
| R2-WT8 | generate-profile in a linked worktree | origin remote resolved (`acme/myrepo`), exit 0 | PASS |

### R2 — validate-profile ceiling/floor type checks (new)

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R2-VP1 | `psalm_errors: -1` | VIOLATION "is not an integer" (both backends) | PASS |
| R2-VP2 | `psalm_errors: 0.5` | VIOLATION "is not an integer" | PASS |
| R2-VP3 | `psalm_errors: "5"` (quoted) | VIOLATION "relaxed above 0" | PASS |
| R2-VP4 | `psalm_errors: 000` | strip_zeros → 0, PASS | PASS |
| R2-VP5 | `psalm_errors: 007` | → 7 > 0, VIOLATION | PASS |
| R2-VP6 | `complexity: 094` (VP-E5) | → 94 ≥ 94, PASS | PASS |
| R2-VP7 | `psalm_errors: 0x10` | rejected on both backends; yq → "not an integer", python YAML-1.1 → 16 → "relaxed above 0" (both exit 1; backend-message divergence noted) | PASS |
| R2-VP8 | unicode + CJK `bounded_contexts: [Café, Ordén, 注文]` under UTF-8 and LC_ALL=C, yq + python | valid, exit 0, no "must be a list" | PASS |

### R2 — generate-profile make-map `:=` parsing (new)

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R2-GP1 | Makefile mixing `tests := …`, `psalm ::= …`, `deptrac :::= …` with real `ci:`/`start:` targets | assignments → null; `ci`/`start` detected | PASS |
| R2-GP2 | `ci:= notatarget`, `psalm: vendor/bin/psalm:latest` (value-side colon), `infection?=`, `deptrac+=` | `ci` null (assignment), `psalm` detected (real target), `?=`/`+=` not matched | PASS |
| R2-GP3 | GP-E5 engine: commented `# mysql://` + active `postgresql://` DSN | engine postgresql (comment loses) | PASS |
| R2-GP4 | engine: commented pgsql + active `mysql://` | engine mysql | PASS |
| R2-GP5 | engine: `serverVersion=mariadb` on a mysql DSN | engine mariadb (global win) | PASS |
| R2-GP6 | GP-E10 unicode `src/Café`, `src/Ordén` under UTF-8 vs LC_ALL=C | bounded_contexts byte-identical across locales | PASS |

### R2 — inject-governance contention + CRLF repair (new)

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R2-IG1 | 20 parallel runs into a dir with pre-seeded user content | serializes via atomic `mv`; 1 block, user content kept, no stray `.sdlc-governance.*` temp | PASS |
| R2-IG2 | 30 runs, 15 SIGKILLed mid-flight, then one clean run | recovers to 1 well-formed block; no orphan temp left (kill window not hit) | PASS |
| R2-IG3 | CRLF + unicode user content, run under LC_ALL=C | 1 block/banner, unicode CRLF user lines kept, idempotent on re-run | PASS |
| R2-IG4 | IG-E1/E2/E3 marker-corruption repair (LF) | each repairs to exactly one block, user content preserved | PASS |
| R2-IG5 | CRLF orphan BEGIN marker | repaired to one block, orphan content kept, run 2 "unchanged" | PASS |
| R2-IG6 | CRLF duplicate balanced blocks | collapse to one block at first position, user content kept | PASS |

### R2 — ai-review-loop transport / arg edges (new)

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R2-AR1 | AR-P1/P2/E1/E2/E3/E4 + non-zero-exit retry, counted via a call-counting stub | exact call counts: PASS=1, FAIL→PASS=2, 5×FAIL=5 (escalate), malformed=10 (1 retry/iter), is_error→PASS=2, missing-verdict=5 (NO retry), non-zero→PASS=2 | PASS |
| R2-AR2 | AR-N1/N2/N3/N4/N5/E5 argument and matrix validation | `0`/`-1`/`abc`/`05`/`3.5`/`''` rejected; `--agents` end-of-argv error; unknown arg; claude-absent die; codex-only die; `,` falls back to claude | PASS |
| R2-AR3 | `--max-iterations 9999999999999999999999` (22-digit) | regex `^[1-9][0-9]*$` accepts the string, then `(( iteration <= MAX ))` wraps it (→ `1864712049423024127`, or negative at exactly 2^63) | FAIL → Bug 4 |

### R2 — fr-nfr-gate findings counter (new)

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R2-FG1 | findings boundary sweep `0,00,1,999,2^63` | correct: 0/00 → success; 1/999/2^63 → failure | PASS |
| R2-FG2 | `FR_NFR_NEW_FINDINGS: 18446744073709551616` (2^64) | should report FAIL (findings > 0) | FAIL → Bug 5 |

### R2 — get-pr-comments locale / parity (new)

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R2-PC1 | PC-P1 human listing with unicode + emoji bodies under UTF-8 | renders, `unresolved threads: 1` | PASS |
| R2-PC2 | same under LC_ALL=C | unicode/emoji body survives | PASS |
| R2-PC3 | PC-E2 jq vs python `--json` | canonically equal JSON | PASS |
| R2-PC4 | PC-E1 pagination guard `hasNextPage: true` (human + json) | `die` pagination, exit 1 | PASS |
| R2-PC5 | PC-N5 gh returns non-JSON (`<html>` proxy page) | `die` non-JSON with remediation, exit 1 | PASS |

## Round-2 execution summary

- Cases executed: 41 round-2 IDs (6 re-run FAILs + 35 new edges), plus the
  164-case bundled bats suite run clean.
- Every round-1 FAIL re-run now PASSES (Bugs 1, 2, 3 fixed at root cause);
  no regressions found in the re-sampled round-1 PASS cases.
- Two NEW bugs found, both the same uint64 bash-arithmetic-wrap class that
  round-1 fixed in `validate-profile.sh` but left in two sibling scripts:
  - Bug 4 (R2-AR3): `ai-review-loop.sh` `--max-iterations` accepts a 19+
    digit value, then the `(( ))` loop bound wraps — a runaway loop for
    most huge values, or 0 iterations (immediate escalate) at exactly
    2^63. Adversarial operator input only; severity minor.
  - Bug 5 (R2-FG2): `fr-nfr-gate.sh` `(( findings == 0 ))` wraps a findings
    count that is a multiple of 2^64 to 0, reporting "PASS — zero new
    findings" and posting a `success` commit status. Requires an
    implausible reviewer output, but is a silent gate escape; severity
    minor.
- Sandboxes under `/tmp/sdlc-test2-scripts-cli/` removed after the run.

## Round-2 notes (observations, not defects)

- The round-1 commit message says inject-governance "takes a lockfile
  against concurrent runs," but the shipped implementation uses an atomic
  in-dir `mktemp` + `mv` (last-writer-wins), not a lockfile. The atomic-mv
  approach is sound and verified under 20-way contention (R2-IG1); the
  "lockfile" wording is a commit-message/reality mismatch only, not a code
  defect.
- R2-VP7: `0x10` diverges by backend (yq treats it as a string → "not an
  integer"; python `yaml.safe_load` parses YAML 1.1 hex → 16). Both reject
  with exit 1, so it is not an escape — only the violation message differs.
- Orphan `.sdlc-governance.*` temp files from a SIGKILLed run are not
  swept by later runs (each run's `trap` only removes its own temp). The
  kill window was not hittable in this round; design observation only.

## Round 3 — fix-hold verification + fence-aware coverage

Goal: prove rounds 1–2 fixes HOLD (do not trust commit messages — every
prior FAIL repro re-run for real) and hunt any remaining or fix-introduced
defect. All 8 surfaces re-exercised as real CLI invocations against
disposable sandboxes under `/tmp/sdlc-test3-scripts-cli/`; a real
`yq v4.44.3` binary was downloaded for the yq backend, and the forced
python fallback (`SDLC_FORCE_PYTHON_YAML=1`) was run alongside it.
Locale matrix: `en_US.UTF-8` and `LC_ALL=C`. The bundled `tests/*.bats`
suite has grown to 188 cases and passes clean on both backends
(`bats tests/*.bats` and `SDLC_FORCE_PYTHON_YAML=1 bats tests/*.bats`,
188/188 each); `bash -n` is clean on all 7 scripts + `lib/common.sh`.

Since round 2, `inject-governance.sh` gained FENCE-AWARE marker matching
(a documented marker inside a balanced ``` / ~~~ code fence is treated as
user content, not a real marker; an odd/unclosed fence disables
suppression and falls back to whole-line matching). That new code path
is the freshest fix and was the primary fix-introduced-bug target this
round.

### R3 — round-1/2 FAIL cases re-run (must still PASS)

| ID | Re-run case | Round-3 result |
| --- | --- | --- |
| SP-E1 | bare repo, default + `--report` | PASS (git-repo FAILs, exit 1; `--report` still runs later checks) |
| SP-E6 | inside a normal repo's `.git/` | PASS (git-repo FAILs, exit 1) |
| VP-E7 | `psalm_errors: 2^64-1` (yq + py) | PASS (VIOLATION "relaxed above 0", exit 1, both backends) |
| VP-E7b | `deptrac_violations: 2^64` | PASS (VIOLATION, exit 1) |
| VP-E7c | `infection_msi: 2^64-1` (a raise) | PASS (exit 0, no misleading "lowered below") |
| IG-E5 | CRLF file carrying a CRLF managed block (two independent repros) | PASS (1 begin/1 end/1 banner, stale gone, user CRLF lines kept, run 2 "unchanged", 0 stray temp) |
| R2-AR3 | `--max-iterations` huge (2^64, 2^63, 22-digit) | PASS (ceiling 1000 rejects, exit 1, 0 claude calls); boundary 1000 accepted |
| R2-FG2 | `FR_NFR_NEW_FINDINGS: 2^64` | PASS (exit 1, `failure` status posted — no silent escape) |

All eight prior FAIL repros still PASS. Bugs 1–5 are confirmed fixed at
the root cause; no regression observed.

### R3 — setup-preflight + work-tree shapes

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R3-SP1 | all-green normal repo (stubs) | every check PASS, exit 0 | PASS |
| R3-SP2 | linked `git worktree add` work tree | git-repo PASS, exit 0 | PASS |
| R3-SP3 | inside `.git/worktrees/<wt>` admin dir | git-repo FAIL | PASS |
| R3-SP4 | `--help` / `-h` / unknown flag | usage `die`, exit 1 | PASS |

### R3 — validate-profile type/ceiling/floor + locale

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R3-VP1 | `psalm_errors` `-1` / `0.5` / `0x10` (yq + py) | "is not an integer" (yq); py `0x10`→16 "relaxed above 0"; all exit 1 | PASS |
| R3-VP2 | `psalm_errors: "5"` quoted | "relaxed above 0", exit 1 | PASS |
| R3-VP3 | leading zeros `000`→0 PASS, `007`→7 violation, `complexity: 094`→94 PASS | as stated, both backends | PASS |
| R3-VP4 | unicode/CJK `bounded_contexts: [Café, Ordén, 注文]`, 4 backend×locale combos | valid, exit 0 | PASS |
| R3-VP5 | `--help` / `-h` (treated as PROFILE_FILE) | `die` "profile not found: --help", exit 1 (no crash) | PASS (note) |

### R3 — generate-profile make `:=` parsing + engine + symlink

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R3-GP1 | Makefile mixing `:=`/`::=`/`:::=`/`?=`/`+=` with real `ci:`/`start:`/`psalm:` (value-side colon) targets | assignments → null; real targets detected | PASS |
| R3-GP2 | `ci :=` assignment with NO real `ci:` target | `ci` null | PASS |
| R3-GP3 | `test-unit:` target + `test-unit-flag := 1` | only `test-unit` extracted | PASS |
| R3-GP4 | engine: commented mysql + active postgresql / commented pgsql + active mysql / mariadb global win / ODM→mongodb | correct active-line winner each time | PASS |
| R3-GP5 | engine hint from `config/packages/doctrine.yaml` (commented mysql + active `pdo_pgsql`) | postgresql | PASS |
| R3-GP6 | unicode `src/Café`, `src/Ordén` under UTF-8 vs `LC_ALL=C` | `bounded_contexts` byte-identical | PASS |
| R3-GP7 | unknown flag / nonexistent target / regular-file target / symlinked `.claude` dir | `die` each; symlink target untouched | PASS |

### R3 — inject-governance fence-aware (new code) + repair + contention

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R3-IG1 | documented marker inside a balanced ``` fence, no real block | fenced example kept, real block appended after fence; re-run idempotent | PASS |
| R3-IG2 | documented marker inside a `~~~` fence | same as R3-IG1 | PASS |
| R3-IG3 | real block already present + a separate fenced example | real block replaced in place, example kept, idempotent | PASS |
| R3-IG4 | odd/unclosed fence + a marker-delimited block | falls back to whole-line matching, treats it as a real block, replaces in place; all user content outside markers kept | PASS |
| R3-IG5 | indented (4-space) fence; fence with info string | no crash, fenced markers suppressed, idempotent | PASS |
| R3-IG6 | IG-E1/E2/E3 marker repair (dup, orphan BEGIN, END-before-BEGIN) | each repairs to one block, user content kept, idempotent | PASS |
| R3-IG7 | CRLF + unicode user content under `LC_ALL=C` | 1 block/banner, unicode CRLF lines kept, idempotent | PASS |
| R3-IG8 | 20 parallel runs into a pre-seeded dir | serialize to 1 block, user kept, 0 stray temp | PASS |
| R3-IG9 | symlinked / read-only CLAUDE.md; `--diff` preview | refused (target untouched); `--diff` writes nothing | PASS |

### R3 — ai-review-loop iteration counting + arg matrix

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R3-AR1 | call-counting stub: PASS=1, fail→pass=2, 5×FAIL=5, malformed=10 (1 retry/iter), missing-verdict=5 (NO retry), is_error→PASS=2, non-zero→PASS=2 | exact counts | PASS |
| R3-AR2 | `--max-iterations` `0`/`-1`/`abc`/`05`/`3.5`/`''` rejected; `1000` accepted; `>1000`/`2^63`/`2^64`/22-digit rejected by ceiling (0 calls) | as stated | PASS |
| R3-AR3 | `--agents` end-of-argv error; unknown flag; codex-only `die`; `,` → claude fallback; `codex,claude` → skip+run | as stated | PASS |
| R3-AR4 | claude absent from PATH | `die` claude CLI not found | PASS |

### R3 — fr-nfr-gate findings + containment + transport

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R3-FG1 | findings sweep `0,00,1,999,2^63,2^64,2^64-1` (digit-string compare) | 0/00→success exit 0; all nonzero→failure exit 1 | PASS |
| R3-FG2 | missing/trailing-space `FR_NFR_NEW_FINDINGS` line | `failure` status, "contract violation", exit 1 | PASS |
| R3-FG3 | `--spec-path` missing / `/etc` / symlinked / `specs/../specs` | `die` for first three; allowed for the last (findings 0 → success) | PASS |
| R3-FG4 | non-git dir / bare repo / zero-commit repo | `die` "not inside a git work tree" (first two); `die` "cannot resolve HEAD" (zero commit, git's own stderr is cosmetic) | PASS |
| R3-FG5 | claude absent / gh absent (truly isolated PATH incl. bash) | `die` naming the CLI, exit 1 | PASS |
| R3-FG6 | transport failure both attempts | exactly 2 claude calls, `failure` status, exit 1 | PASS |

### R3 — get-pr-comments parity + locale + guards

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R3-PC1 | human listing, `--unresolved-only`, fixture PR 7 | `unresolved threads: 1`; resolved + issue comments dropped in unresolved mode | PASS |
| R3-PC2 | pagination guard (truncated fixture, human + `--json`) | `die` "more than 100", exit 1 | PASS |
| R3-PC3 | jq vs python `--json` | canonically equal JSON | PASS |
| R3-PC4 | human listing under `LC_ALL=C` | `unresolved threads: 1` | PASS |
| R3-PC5 | unknown flag; `--pr abc`/`''`; non-JSON gh; pullRequest null; GraphQL error envelope; empty body | clean `die` each, exit 1 | PASS |
| R3-PC6 | no `--pr` (gh-resolved) | PR 7 resolved, listing rendered, exit 0 | PASS |

### R3 — lib/common.sh wrap-safe helpers under set -e + locale

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R3-CL1 | `strip_zeros` `007`→7, `000`→0, `''`→0, `100`→100 | as stated | PASS |
| R3-CL2 | `num_gt`/`num_lt` length-then-lex (incl. 2^64 vs 0, 999 vs 1000, 10 vs 9, 5 vs 5) | correct ordering, survives `set -euo pipefail` | PASS |
| R3-CL3 | `num_gt` same-length pairs under `LC_ALL=C` vs `en_US.UTF-8` | byte-identical results (ASCII-digit collation stable) | PASS |

## Round-3 execution summary

- Cases executed: 56 round-3 IDs (8 re-run prior FAILs + 48 new/edge),
  plus the 188-case bundled bats suite run clean on BOTH the yq and the
  forced-python backends, and `bash -n` clean on all scripts.
- Every round-1 and round-2 FAIL repro re-run still PASSES — Bugs 1–5 are
  confirmed fixed at the root cause; no regression in re-sampled prior
  PASS cases.
- The new fence-aware `inject-governance.sh` code path was probed
  adversarially (balanced ``` / `~~~` fences, info strings, indented
  fences, odd/unclosed-fence fallback, real-block-plus-example
  coexistence): user content is preserved and runs are idempotent in
  every case.
- NO new or fix-introduced bugs found this round.
- Sandboxes under `/tmp/sdlc-test3-scripts-cli/` removed after the run.

## Round-3 notes (observations, not defects)

- `validate-profile.sh` has no `--help` flag by contract (`[PROFILE_FILE]`
  is a single positional path), so `--help`/`-h` are read as filenames and
  die with "profile not found: --help" (exit 1, no crash). Cosmetic
  divergence from the other scripts' `unknown argument` usage line.
- FG zero-commit repo: `git rev-parse HEAD` prints its own
  `fatal: ambiguous argument 'HEAD'` to stderr before the script's clean
  `cannot resolve HEAD` message. The git line is cosmetic noise; the exit
  code and the script-level diagnostic are correct.
- The `/tmp/sdlc-test3-*` sandbox tree is shared with sibling QA surfaces
  and was twice wiped mid-run by concurrent cleanup; re-created each time
  with a fresh `yq` download. No effect on results (each case is
  self-contained), recorded only as a test-harness observation.

## Round 4 — convergence (prove rounds 1–3 fixes HOLD)

Goal: re-run every round-1..3 FAIL repro LIVE and prove Bugs 1–5 hold fixed
at the root cause, then probe an adversarial-new matrix (empty profile,
profile missing required keys, SIGPIPE, concurrent invocations sharing a
temp dir) plus the shared `lib/common.sh` refactor
(`strip_zeros`/`num_gt`/`num_lt`) to confirm `validate-profile.sh` and
`ai-review-loop.sh` use one identical implementation. All 8 surfaces
exercised as real CLI invocations against disposable sandboxes under
`/tmp/sdlc-test4-<surface>/`; a real `yq v4.44.3` binary was downloaded
for the yq backend and the forced python fallback
(`SDLC_FORCE_PYTHON_YAML=1`) was run alongside it. The bundled
`tests/*.bats` suite is 197 cases and passes 197/197 on the yq backend
(the supported/CI configuration); `bash -n` is clean on all 7 scripts +
`lib/common.sh`. The QA clone (real `php-service-template`) was used as a
realistic target (copied to a scratch dir, never pushed).

### R4 — round-1/2/3 FAIL repros re-run LIVE (must still PASS)

| ID | Re-run case | Round-4 result |
| --- | --- | --- |
| SP-E1 | bare repo, default + `--report` | PASS (git-repo FAILs, exit 1; `--report` still runs later checks) |
| SP-E6 | inside a normal repo's `.git/` | PASS (git-repo FAILs, exit 1) |
| VP-E7 | `psalm_errors: 2^64-1` (yq + py) | PASS (VIOLATION "relaxed above 0", exit 1, both backends) |
| VP-E7b | `deptrac_violations: 2^64` (yq + py) | PASS (VIOLATION, exit 1, both backends) |
| VP-E7c | `infection_msi: 2^64-1` (a raise) | PASS (exit 0, no misleading "lowered below", both backends) |
| IG-E5 | CRLF file carrying a CRLF managed block (two fresh sandboxes) | PASS (1 begin/1 end/1 banner, stale gone, user CRLF lines kept, run 2 "unchanged", 0 stray temp) |
| R2-AR3 | `--max-iterations` `2^64`/`2^63`/22-digit/`1001` | PASS (ceiling 1000 rejects, exit 1, 0 claude calls); boundary 1000 accepted (2000 calls = 1000 iter × retry, escalates exit 1) |
| R2-FG2 | `FR_NFR_NEW_FINDINGS: 2^64` (full sweep 0,00,1,999,2^63,2^64,2^64-1) | PASS (0/00 → `success` exit 0; all nonzero → `failure` exit 1, no silent escape) |

All eight prior FAIL repros still PASS. Bugs 1–5 confirmed fixed at the
root cause; no regression observed.

### R4 — adversarial-new: empty / missing-key profile + arg edges

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R4-A1 | 0-byte profile → `validate-profile.sh` (yq + py) | 29 violations, exit 1, identical both backends, no crash | PASS |
| R4-A2 | `missing-key.yml` fixture → validate | VIOLATION names `php.version`, exit 1, both backends | PASS |
| R4-A3 | profile missing `review.ai_review_agents` → `ai-review-loop.sh` | defaults to claude, PASS iteration 1, exit 0 (no crash) | PASS |
| R4-A4 | malformed-YAML matrix (unclosed quote, bad indent, tab indent, dangling anchor, NUL/control bytes) → validate + ai-review-loop, both backends | clean `[php-sdlc] profile is not valid YAML` diagnostic, exit 1, ZERO raw traceback; AR self-diagnoses (does not silently default to claude) | PASS |
| R4-A5 | `--agents`/`--max-iterations` with no value (end of argv) | clean `${2:?…}` parameter error, exit 1 | PASS |

### R4 — adversarial-new: SIGPIPE under `set -euo pipefail`

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R4-SP1 | `validate-profile.sh \| head -1` (29 VIOLATION lines, reader closes pipe) | first line emitted, writer killed by SIGPIPE (141), no hang, no corrupt state | PASS |
| R4-SP2 | `ai-review-loop.sh \| head -1` (5000-line result body) | same; benign SIGPIPE on writer | PASS |
| R4-SP3 | `get-pr-comments.sh \| head -1` (80-thread listing) | same | PASS |
| R4-SP4 | `setup-preflight.sh --report \| head -1` | same | PASS |
| R4-SP5 | `generate-profile.sh` diff output `\| head -1` | diff prints, EXIT trap fires, 0 stray `.php-sdlc.yml.*` temp | PASS |

### R4 — adversarial-new: concurrent invocations sharing a temp dir

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R4-C1 | 30 parallel `inject-governance.sh` into one pre-seeded dir (CLAUDE.md + AGENTS.md with user content) | serialize via atomic `mv`; 1 begin/1 end/1 banner each, user content kept, 0 stray `.sdlc-governance.*`, post-storm run "unchanged" | PASS |
| R4-C2 | 20 parallel `generate-profile.sh` into one dir (minimal composer) | one complete profile, parses as YAML, byte-identical to a single non-concurrent run, 0 stray temp | PASS |
| R4-C3 | 25 parallel `generate-profile.sh` into the `stub-repo` fixture dir | concurrent profile is VALID and byte-identical to the golden single run, 0 stray temp | PASS |

### R4 — lib/common.sh shared-refactor equivalence

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R4-L1 | both `validate-profile.sh` and `ai-review-loop.sh` `source lib/common.sh` and call `num_gt`/`num_lt` | one shared implementation, no per-script copy | PASS (verified by source) |
| R4-L2 | `strip_zeros`/`num_gt`/`num_lt` table under `set -euo pipefail`: `007→7`, `000→0`, `100=100`, `5=5`, `10>9`, `999<1000`, `2^64-1>0`, `2^64>0`, `2^63 vs 2^63-1` | wrap-safe digit-string ordering correct, survives `set -e` | PASS |
| R4-L3 | validate `check_ceiling`/`check_floor` vs ai-review-loop `MAX_ITERATIONS` ceiling on the same 2^63/2^64 magnitudes | identical verdicts (reject/accept) — one num_gt | PASS |

### R4 — fence-aware inject-governance (freshest code path) re-probe

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R4-F1 | documented markers inside a balanced ` ``` ` fence, no real block | fenced example kept (2 begin total: 1 fenced + 1 real), real banner appended once, run 2 "unchanged" | PASS |
| R4-F2 | odd/unclosed fence wrapping marker-delimited content | fallback to whole-line matching, treated as a real block (1 begin/1 end), user tail kept, idempotent | PASS |

### R4 — fr-nfr-gate + get-pr-comments edge re-sweep

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R4-FG1 | `--spec-path` `/etc` / `specs/../../../../etc` / symlinked / `specs/../specs` | `die` boundary-escape / symlink-refusal for first three, allowed for the last (runs to PASS); all die paths exit 1 | PASS |
| R4-FG2 | verdict trailing-space / missing line | "contract violation", exit 1 (strict regex) | PASS |
| R4-FG3 | bare repo / non-git dir | `die` "not inside a git work tree" before gh/claude, exit 1 | PASS |
| R4-PC1 | `--pr abc` / `--pr ''` / unknown flag / non-JSON gh / `hasNextPage:true` / `pullRequest:null` | clean `die` each, exit 1 | PASS |
| R4-PC2 | healthy empty PR (yq + py) | exit 0, `unresolved threads: 0`, both backends | PASS |

### R4 — QA clone (real php-service-template) end-to-end

| ID | Case | Expected | Result |
| --- | --- | --- | --- |
| R4-QA1 | generate-profile on the real template (yq + py) | exit 0, full feature map (php 8.2, symfony 7.2, api_platform 4.0, graphql, doctrine-orm/postgresql, contexts, structurizr, load_testing) | PASS |
| R4-QA2 | generated profile → validate-profile (yq + py) | exit 0, 0 violations, both backends | PASS |
| R4-QA3 | generate-profile second run, no flags | "unchanged", byte-identical (NFR-3) | PASS |
| R4-QA4 | inject-governance into the real CLAUDE.md (1322 B user content) + AGENTS.md | 1 block each, user bytes kept, idempotent re-run "unchanged", 0 stray temp | PASS |
| R4-QA5 | engine detection from active `pdo_pgsql` / `postgres://` (commented hints excluded) | postgresql | PASS |
| R4-QA6 | validate mutations on the QA-derived valid profile: lower complexity, relax psalm/deptrac (incl. 2^64), bad enum, schema_version 2, raise 100→101 | each lowered/relaxed/illegal value → VIOLATION exit 1; raises → exit 0; both backends | PASS |
| R4-QA7 | generate-profile make-map `:=`/`::=`/`:::=`/`?=`/`+=` adversarial Makefile + real `start:`/`e2e-tests:`/`psalm: vendor/bin/psalm` targets | assignments → null; real targets (incl. value-side-colon `psalm:`) detected | PASS |

## Round-4 execution summary

- Cases executed: 41 round-4 IDs (8 re-run prior FAILs + 33 new/edge),
  plus the 197-case bundled bats suite run on the yq backend (197/197) and
  the forced-python backend (196/197 — see note below), and `bash -n`
  clean on all 7 scripts + `lib/common.sh`.
- Every round-1/2/3 FAIL repro re-run still PASSES — Bugs 1–5 are
  confirmed fixed at the root cause; no regression in re-sampled prior
  PASS cases.
- The adversarial-new matrix (empty profile, missing-key profile, SIGPIPE
  to `head`, 30-/25-/20-way concurrent invocations sharing a temp dir) is
  clean: clean diagnostics, no crashes, atomic `mv` serialization, zero
  stray temp files. The shared `lib/common.sh` refactor is identical by
  construction (both scripts source one file) and verified behaviorally
  across the 2^63/2^64 wrap boundaries.
- NO new or fix-introduced bugs found this round. The surface is clean.
- Sandboxes under `/tmp/sdlc-test4-*/` removed after the run.

## Round-4 notes (observations, not defects)

- The single forced-python bats delta (test 174, "no JSON toolchain") is a
  CONTRADICTORY test configuration, not a defect: that test builds a PATH
  sandbox holding a real `yq` but neither `jq` nor `python3` (to isolate
  the json-toolchain failure on a yq-only machine), then asserts
  `yaml-toolchain PASS`. Running the whole suite with a global
  `SDLC_FORCE_PYTHON_YAML=1` disables `have_yq()`, so the yaml-toolchain
  check falls back to a python3 that the sandbox deliberately omits and
  FAILs — a logically impossible combination (force-python-yaml AND
  python-absent). The script behaves correctly in both the production
  scenario (yq-only machine, no force flag: yaml PASS + json FAIL, exit 1)
  and the contradictory one. The yq backend (the CI/supported config)
  passes 197/197.
- SIGPIPE on a script's own stdout (`| head -1`) reports pipestatus 141
  (128+13) — the READER closing the pipe, not a writer fault. No state
  corruption and no stray temp resulted in any script.
- generate-profile against a minimal composer.json (php only, no
  framework/persistence/src) legitimately emits null required keys, so the
  freshly generated profile fails validate-profile — this is correct A3/
  NFR-4 detection of a bare repo, not a generation defect (proven
  byte-identical to a single non-concurrent run).
- The QA template's profile lists `"code quality"` twice in `ci.workflows`
  because there are genuinely two workflow files named "code quality" in
  `.github/workflows/`; faithful detection, not a duplication bug
  (`required_checks` stays `[]`).
