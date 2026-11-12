---
name: quality-standards
description: Use when you need the 12 quality bars of the profile - each bar's protected source, the gate target that measures it, how its measured value is computed, the PASS, FAIL or NOT RUN verdict and the tighten-only rule. Skip a bar whose gate target the profile maps to null, recorded as not run (capability absent). Not for running the gates stage by stage (use verification-workflow), not for refactoring a complexity finding (use complexity-management) and not for the finding format of a review (use code-review).
---

# Quality Standards

## Profile keys consumed

- `quality.coverage_lines` — line-coverage floor; its only legal value is 100.
- `quality.coverage_functions` — function-coverage floor; its only legal value is 100.
- `quality.max_surviving_mutants` — ceiling on missed and timed-out mutants; only legal value 0.
- `quality.max_clippy_findings` — ceiling on static-analysis diagnostics; only legal value 0.
- `quality.max_complexity_violations` — ceiling on complexity diagnostics against the repository's four complexity limits; only legal value 0.
- `quality.max_architecture_violations` — ceiling on layer and crate-isolation violations; only legal value 0.
- `quality.max_unused_dependencies` — ceiling on unused dependencies; only legal value 0.
- `quality.max_dependency_policy_findings` — ceiling on advisory, licence, ban and source findings; only legal value 0.
- `quality.max_spectral_findings` — ceiling on OpenAPI lint findings; only legal value 0.
- `quality.max_unapproved_breaking_changes` — ceiling on unapproved OpenAPI and GraphQL breaking changes; only legal value 0.
- `quality.max_image_vulnerabilities_high_critical` — ceiling on HIGH and CRITICAL production-image findings; only legal value 0.
- `quality.max_smoke_budget_breaches` — ceiling on smoke load-test budget breaches; only legal value 0.
- `make.ci_list` — the read-only target that prints the gate order; `null` sends the reader to the repository's agent guide.
- `make.tests_with_coverage` — gate target of the two coverage floors.
- `make.mutation_tests_diff` — gate target of the surviving-mutants ceiling.
- `make.static_analysis` — gate target of the static-analysis ceiling.
- `make.complexity` — gate target of the complexity ceiling.
- `make.architecture` — gate target of the layer rules.
- `make.check_crate_isolation` — gate target that builds every crate alone.
- `make.unused_dependencies` — gate target of the unused-dependency ceiling.
- `make.check_security` — gate target of the dependency-policy ceiling.
- `make.validate_openapi_spec` — gate target of the OpenAPI lint ceiling.
- `make.openapi_diff` — gate target of the OpenAPI breaking-change check.
- `make.graphql_diff` — gate target of the GraphQL breaking-change check.
- `make.image_scan` — gate target of the production-image scan.
- `make.smoke_load_tests` — gate target of the smoke load-test budget.

## Repository precedence

Read `.claude/skills/quality-standards/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line. The repository skill states the thresholds and the protected files; this skill maps each bar to its profile key and gate target, defines how the measured value is read from the gate's output, and fixes the verdict row. Where the two disagree, quote the repository and record the difference as a degrade note.

## Context

- Every bar lives in a protected source of the repository: the protected files `make/gates.mk`, `clippy.toml`, `.cargo/mutants.toml`, `architecture.toml`, `deny.toml`, `.spectral.yaml`, `.trivyignore`, `scripts/graphql-diff.sh` and `tests/Load/utils/thresholdsBuilder.js`, plus two protected parts of files that otherwise change freely: the `[workspace.lints]` table of `Cargo.toml` and the smoke threshold value `/endpoints/health/smoke/threshold` of `tests/Load/config.json.dist`. The profile keys are handles on those bars, not copies of them: the complexity limits, for example, are not profile keys at all and are quoted from `clippy.toml` at runtime.
- The template's gates already sit at the extremes (100 % coverage, zero findings), so tighten-only means a floor key equals 100 and a ceiling key equals 0. The profile validator rejects any other value before a stage starts.
- The applicability triage always marks this skill `EXECUTE` (see the [decision guide](../SKILL-DECISION-GUIDE.md)); the review rows Q2–Q14 of `/rs-sdlc-review` and the post-loop coverage check of `/rs-sdlc-implement` read their bars from here.
- The gate order belongs to the repository and is read at runtime through `make.ci_list`; it is never restated in the plugin.

## Task

For every bar the calling stage needs, name its protected source, run its gate target through the plugin's execution route, compute the measured value with the method below, compare it with the bar's bound and record one verdict row; route every failing bar to the skill that fixes its root cause.

## Success criteria

- Each requested bar has one verdict row `| bar | gate target | measured | bound | verdict |` with verdict `PASS`, `FAIL` or `NOT RUN (<reason>)`.
- A row is `PASS` only when its gate target exited 0 and its measured value is within the bound; an unparseable output is measured `≥ 1 (exit <n>)` and the row is `FAIL`.
- The gate order was read through `make.ci_list` (or `AGENTS.md` when that key is `null`), not from memory.
- No profile value, protected file, attribute or flag was changed to obtain a pass.

## Steps

### 1. Read the gate order

- `make.ci_list` non-null: run `make` with the target mapped by `make.ci_list` in the foreground (it only prints, and it is on the foreground allowlist). It prints the ordered gate targets, one per line; run the bars in that order and quote the list as evidence.
- `make.ci_list` is `null`: read the ordered list from the Verification section of the repository's `AGENTS.md` and record the list read as `not run (capability absent)`.
- Never run the aggregate CI target in one call; run one gate target per call (see [verification-workflow](../verification-workflow/SKILL.md)).

### 2. Look up the bar

| Bar | Direction | Protected source | Gate target | Enforced in |
| --- | --- | --- | --- | --- |
| `quality.coverage_lines` | raise-only floor | `COVERAGE_GATE_CMD` flag `--fail-under-lines` in `make/gates.mk` | `make.tests_with_coverage` | review Q9, implement post-loop |
| `quality.coverage_functions` | raise-only floor | `COVERAGE_GATE_CMD` flag `--fail-under-functions` in `make/gates.mk` | `make.tests_with_coverage` | review Q9 |
| `quality.max_surviving_mutants` | lower-only ceiling | `MUTANTS_CMD` in `make/gates.mk`, `.cargo/mutants.toml`; the mutation tool exits 2 for missed and 3 for timed-out mutants | `make.mutation_tests_diff` | review Q10 |
| `quality.max_clippy_findings` | lower-only ceiling | `LINT_PROD_CMD` and `LINT_ALL_CMD` (warnings denied), `LINT_RUSTDOC_CMD` (`RUSTDOCFLAGS` denies warnings) in `make/gates.mk`; the `[workspace.lints]` table of `Cargo.toml` | `make.static_analysis` | review Q2 |
| `quality.max_complexity_violations` | lower-only ceiling | `clippy.toml` settings `cognitive-complexity-threshold`, `too-many-lines-threshold`, `too-many-arguments-threshold`, `excessive-nesting-threshold`; `COMPLEXITY_CMD` in `make/gates.mk` | `make.complexity` | review Q3, limits quoted from `clippy.toml` in the row |
| `quality.max_architecture_violations` | lower-only ceiling | `ARCH_CMD` with `architecture.toml`; `HACK_CMD` in `make/gates.mk` | `make.architecture`, `make.check_crate_isolation` | review Q4 and Q5 |
| `quality.max_unused_dependencies` | lower-only ceiling | `SHEAR_CMD` in `make/gates.mk` | `make.unused_dependencies` | review Q8 |
| `quality.max_dependency_policy_findings` | lower-only ceiling | `DENY_CMD` in `make/gates.mk` with `deny.toml` | `make.check_security` | review Q7, security audit static lane |
| `quality.max_spectral_findings` | lower-only ceiling | `SPECTRAL_FLAGS` in `make/gates.mk`, `.spectral.yaml` | `make.validate_openapi_spec` | review Q13 |
| `quality.max_unapproved_breaking_changes` | lower-only ceiling | `OASDIFF_FLAGS` in `make/gates.mk`; `scripts/graphql-diff.sh` | `make.openapi_diff`, `make.graphql_diff` | review Q14 |
| `quality.max_image_vulnerabilities_high_critical` | lower-only ceiling | `TRIVY_FLAGS` in `make/gates.mk`, `.trivyignore` | `make.image_scan` | security audit image lane; finish-pr through the production-image scan required check |
| `quality.max_smoke_budget_breaches` | lower-only ceiling | the value at `/endpoints/health/smoke/threshold` of `tests/Load/config.json.dist`, `tests/Load/utils/thresholdsBuilder.js` | `make.smoke_load_tests` | finish-pr through the smoke load-test required check; review records `not run (deferred to PR CI)` |

The required-check names are read at runtime from `docs/repository-settings.md`, and the protected list from `cargo xtask config-guard --list`.

The values the template ships, quoted with their source so the protected files can be checked against them:

```text # profile-example
# Quoted from the template's protected sources at the reference checkout; re-read the live files, never this block.
make/gates.mk  COVERAGE_GATE_CMD flags   --fail-under-lines 100 --fail-under-functions 100
clippy.toml    cognitive-complexity-threshold = 8
clippy.toml    too-many-lines-threshold = 50
clippy.toml    too-many-arguments-threshold = 5
clippy.toml    excessive-nesting-threshold = 5
make/gates.mk  SPECTRAL_FLAGS = --fail-severity=hint
make/gates.mk  OASDIFF_FLAGS  = --fail-on ERR
make/gates.mk  TRIVY_FLAGS    = --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore
tests/Load/config.json.dist  /endpoints/health/smoke/threshold = 50
```

```yaml # profile-example
# The quality block of every generated profile: the only legal values.
quality:
  coverage_lines: 100
  coverage_functions: 100
  max_surviving_mutants: 0
  max_clippy_findings: 0
  max_complexity_violations: 0
  max_architecture_violations: 0
  max_unused_dependencies: 0
  max_dependency_policy_findings: 0
  max_spectral_findings: 0
  max_unapproved_breaking_changes: 0
  max_image_vulnerabilities_high_critical: 0
  max_smoke_budget_breaches: 0
```

### 3. Run the gate target

1. Branch on the bar's gate-target key:
   - non-null: run `make` with the mapped target through the execution route of [verification-workflow](../verification-workflow/SKILL.md) (in the background, logged under `target/rust-sdlc/logs/`, container mode applied, database-backed targets one at a time).
   - `null`: record `not run (capability absent)` (degrade D1, outcome `SUCCESS-WITH-REPORT`) and never substitute a raw tool command for the missing target.
2. The mutation and breaking-change targets compare with the merge base: pass `base_ref=<merge-base sha>` as a suffix variable. Run the two breaking-change targets with `BREAKING_CHANGE_APPROVED=true` only when the PR already carries the `approved-breaking-change` label (read with `gh pr view --json labels`); never apply the label.
3. A target that cannot reach Docker (the template's message `This target needs a reachable container engine (docker).` in the log, or a failed `docker info` probe) is recorded `not run (no Docker)`; that is degrade D2 and the calling stage ends `ESCALATED`, never remediated and never retried in a loop.
4. In review, the smoke load-test target is recorded `not run (deferred to PR CI)`; the image-scan target runs only in the image lane of [security-audit](../security-audit/SKILL.md) when Docker is reachable, and outside that lane it is recorded `not run (deferred to PR CI)`. Finish-pr judges both through their required PR checks.

### 4. Measure the value

An exit-based bar measures 0 on exit 0 and `≥ 1 (exit <n>)` otherwise. The others read the target's log or report:

1. `quality.coverage_lines` — from `target/coverage/lcov.info`, sum the `LH:` and `LF:` records; PASS iff ΣLF > 0 and 100 × ΣLH ≥ `quality.coverage_lines` × ΣLF, in integer arithmetic (no rounding). A missing report, or one without any `LF:` record, is a failure, never a pass.
2. `quality.coverage_functions` — the same with the `FNH:` and `FNF:` records: PASS iff ΣFNF > 0 and 100 × ΣFNH ≥ `quality.coverage_functions` × ΣFNF.
3. `quality.max_surviving_mutants` — the number of lines of `mutants.out/missed.txt` plus `mutants.out/timeout.txt`; a missing file counts 0.
4. `quality.max_clippy_findings` — log lines matching `^(error|warning)(\[[A-Za-z0-9_]+\])?:[[:space:]]`, minus the `^error: (could not compile|aborting due to)` lines and the `generated [0-9]+ (warning|error)` summaries.
5. `quality.max_complexity_violations` — one per `^error:[[:space:]]` diagnostic naming `clippy::cognitive_complexity`, `clippy::too_many_lines`, `clippy::excessive_nesting` or `clippy::too_many_arguments`; the row also quotes the four limits read from `clippy.toml`.
6. `quality.max_architecture_violations` — for the architecture target, the `<n>` of its `architecture: FAILED. <n> violation(s) …` line (0 on exit 0); for the crate-isolation target, the number of `error: could not compile` lines, at least 1 on a non-zero exit. Each of the two rows is held to the bound on its own.
7. `quality.max_unused_dependencies` — exit-based.
8. `quality.max_dependency_policy_findings` — the number of `^error\[` lines in the log.
9. `quality.max_spectral_findings` — exit-based.
10. `quality.max_unapproved_breaking_changes` — exit-based, the two targets summed.
11. `quality.max_image_vulnerabilities_high_critical` — exit-based.
12. `quality.max_smoke_budget_breaches` — exit-based.

The coverage and static-analysis counts as commands, where `<floor>` is the bar's profile value and `<log>` the target's log file:

```bash
awk -F: -v floor="<floor>" '/^LH:/ {h += $2} /^LF:/ {f += $2} END {exit !(f > 0 && 100 * h >= floor * f)}' target/coverage/lcov.info
grep -E '^(error|warning)(\[[A-Za-z0-9_]+\])?:[[:space:]]' "<log>" | grep -vE '^error: (could not compile|aborting due to)' | grep -vcE 'generated [0-9]+ (warning|error)'
```

### 5. Record the verdict row

Write one row per bar: `| bar | gate target | measured | bound | verdict |`, for example `| quality.max_clippy_findings | <target mapped by make.static_analysis> | 0 | ≤ 0 | PASS |`. The reasons of a `NOT RUN` row come from the closed set `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`. A mutation row recorded `not run (not changed)` carries the previous iteration's verdict, and counts as PASS when the branch touches no production `*.rs` (see [testing-workflow](../testing-workflow/SKILL.md)); every other `NOT RUN` row is a degrade note or an escalation, never a PASS.

### 6. Route a failing bar

| Failing bar | Fix the root cause with |
| --- | --- |
| `quality.coverage_lines`, `quality.coverage_functions`, `quality.max_surviving_mutants` | [testing-workflow](../testing-workflow/SKILL.md) |
| `quality.max_clippy_findings` | [rust-error-handling](../rust-error-handling/SKILL.md), [async-runtime-safety](../async-runtime-safety/SKILL.md), or a direct code change for the lint named |
| `quality.max_complexity_violations` | [complexity-management](../complexity-management/SKILL.md) |
| `quality.max_architecture_violations` | [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md) |
| `quality.max_unused_dependencies`, `quality.max_dependency_policy_findings` | [dependency-policy](../dependency-policy/SKILL.md) |
| `quality.max_spectral_findings`, `quality.max_unapproved_breaking_changes` | [api-contract-development](../api-contract-development/SKILL.md) |
| `quality.max_image_vulnerabilities_high_critical` | [security-audit](../security-audit/SKILL.md) |
| `quality.max_smoke_budget_breaches` | [load-testing](../load-testing/SKILL.md) |

## Constraints

- Tighten-only rule: a floor key's only legal value is 100 and a ceiling key's only legal value is 0. The profile validator rejects a floor below 100, a floor above 100, and a ceiling above 0; the profile generator keeps these defaults and only warns when the repository's own gate is looser.
- A bar changes only in its protected source, only through a labelled pull request with the approval label named in `protected-config.toml`; the plugin never makes that change and reports the need as a protected-configuration escalation.
- Never lower a floor or raise a ceiling in the profile, and never raise a `clippy.toml` limit.
- Never loosen `SPECTRAL_FLAGS`, `OASDIFF_FLAGS` or `TRIVY_FLAGS`, never add an entry to `.trivyignore` or an exception to `deny.toml`, and never raise the smoke threshold in `tests/Load/config.json.dist`.
- Never add an `#[allow` attribute, `#[mutants::skip]` or `#[coverage(off)]` to obtain a pass.
- Never add an `exclude_re` or `exclude_globs` entry to `.cargo/mutants.toml`, and never add `--ignore-filename-regex` to the coverage command.
- Never restate the gate order or a threshold value outside a `# profile-example` fence; read `make.ci_list` and the protected files at runtime.
- Never substitute a raw tool command for a `null` gate target, and never count an unparseable output as 0.

## Verification

1. Every requested bar has exactly one verdict row, and every `PASS` row shows exit 0 and a measured value within its bound.
2. Nothing that holds a bar changed in the working tree (each command prints nothing). `Cargo.toml` and `tests/Load/config.json.dist` change freely outside their protected parts, so only the `[workspace.lints]` table and the smoke threshold value are compared with `HEAD`:

   ```bash
   git status --porcelain -- .claude/rust-sdlc.yml make/gates.mk clippy.toml .cargo/mutants.toml architecture.toml deny.toml .spectral.yaml .trivyignore scripts/graphql-diff.sh tests/Load/utils/thresholdsBuilder.js
   git show HEAD:Cargo.toml | python3 -c 'import sys, tomllib; lints = lambda d: d.get("workspace", {}).get("lints"); lints(tomllib.loads(sys.stdin.read())) == lints(tomllib.load(open("Cargo.toml", "rb"))) or print("Cargo.toml: [workspace.lints] changed")'
   git show HEAD:tests/Load/config.json.dist | python3 -c 'import json, sys; smoke = lambda d: d.get("endpoints", {}).get("health", {}).get("smoke", {}).get("threshold"); smoke(json.load(sys.stdin)) == smoke(json.load(open("tests/Load/config.json.dist"))) or print("tests/Load/config.json.dist: smoke threshold changed")'
   git diff HEAD | grep -nE '^\+.*(#\[(allow|mutants::skip|coverage\(off\))|exclude_(re|globs)|ignore-filename-regex)'
   ```

3. The gate order quoted in the evidence equals the current output of the target mapped by `make.ci_list` (or the `AGENTS.md` list when that key is `null`).
