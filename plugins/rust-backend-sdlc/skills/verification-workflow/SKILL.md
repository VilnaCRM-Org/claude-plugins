---
name: verification-workflow
description: Use when a change of a Rust service must be proven by the repository's gates before it is called complete, or when a gate stage fails and its owning skill must be found - runs the six CI stage targets one per call in the order the repository prints (never the aggregate make ci in one call), each in the background with a log polled by wait_log, in container mode when capabilities.run_in_container is true, and classifies a Docker-less target as not run (no Docker) with the doctor output instead of remediating it. Skip a stage whose stage target the profile maps to null, recorded as not run (capability absent). Not for writing or debugging a single test (use testing-workflow), not for the meaning and measurement of each quality bar (use quality-standards) and not for fixing a specific finding (use the owning skill this one routes to).
---

# Verification Workflow

## Profile keys consumed

- `make.ci_list` — the read-only target that prints the ordered gate targets, one per line; it runs in the foreground, and null falls back to the repository's documented verification list (step 4).
- `make.ci_preflight` — the first stage target; it reads the base ref and runs the configuration check, so it always receives `base_ref=<sha> CONFIG_CHANGE_APPROVED=`.
- `make.ci_static_analysis` — the second stage target; it receives no variable but the container suffix.
- `make.ci_tests` — the third stage target; it uses the shared test database.
- `make.ci_contracts` — the fourth stage target; it reads the base ref, so it always receives `base_ref=<sha>`.
- `make.ci_mutation` — the fifth stage target; it uses the shared test database and reads the base ref, so it always receives `base_ref=<sha>`.
- `make.ci_delivery` — the sixth stage target; the implementation and review stages record it `not run (deferred to PR CI)`.
- `make.doctor` — the foreground host-prerequisite report attached to every `not run (no Docker)` classification.
- `capabilities.run_in_container` — true selects container mode (suffix variable, container precondition, container route); false runs every call on the host.
- `make.check_commit_message` — the foreground commit-subject check that the background sentence names.
- `make.install_hooks` — the foreground hook activation that the background sentence names.
- `make.start` — the target the container precondition starts in the background when the `app` service is not running.

## Repository precedence

Read `.claude/skills/verification-workflow/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line.

The repository skill names the owning skill of every gate and says what a documentation-only change runs; follow it, and route by its owner list before the table in step 7. Where it asks for the aggregate `make ci` before completion, run the same stages one per call in the same order instead: the aggregate target only runs the doctor and then loops over those stages, but as one call it can outlive the 600-second foreground limit and hides which stage failed. Write that substitution, and any other difference, into the `precedence:` line of the evidence. When the repository skill is absent, the Steps apply in full and the evidence records `source: plugin` instead of `source: repo+plugin`.

## Context

- The gate order belongs to the repository. The target mapped by `make.ci_list` prints it at runtime; the stage a gate belongs to is read from the Makefile's `CI_*_TARGETS` variables. Neither list is restated here except as the sourced example in step 4.
- The gates run stage by stage, never `make ci` in one call. The six stage keys run in the order listed above. The aggregate target also runs a seventh stage, the Makefile's own tests; it has no key in this skill, the plugin never runs it, and its PR check is judged by the finish-pr stage.
- A foreground tool call is capped at 600 seconds, and any stage can exceed that on a cold `target/` directory, so every stage runs in the background and is polled.
- GNU make exits 2 for every failing recipe, so a Docker-less target is recognised by the template's message, never by the exit code.
- The tests and mutation stages share the one compose test database with every other database-backed target (see [testing-workflow](../testing-workflow/SKILL.md)); stages run one at a time, which keeps that rule.

## Task

Prove the current tree by running the repository's gate stages one per call through the profile's stage targets, in the order the repository prints, each backgrounded, logged and polled, in container mode when the profile asks for it. Route each failing gate to the skill that owns its root cause and re-run within a bounded loop; classify a Docker-less target `not run (no Docker)` with the doctor output instead of remediating it; and report the targets-run list, the evidence block and the verdict line.

## Success criteria

1. The aggregate `make ci` was never invoked; each non-null stage target ran in its own call, in order, after the gate order was read and quoted.
2. Every `make` call outside the foreground allowlist ran through the Bash tool with `run_in_background: true`, with its log under `target/rust-sdlc/logs/`, and was waited for through the completion notice or `common.sh wait_log`; no trailing `&`, no `nohup` and no bare `sleep` appear in the run.
3. In container mode the container precondition held before the first `make` target, and every `make` call carried the suffix `RUN_IN_CONTAINER=1`.
4. Each stage has one row `<stage target>: passed | failed | not run (<reason>)`; a Docker-less stage is `not run (no Docker)` with the doctor output attached, never `failed`.
5. Every stage that reads the base ref received `base_ref=<sha>` explicitly, and the first stage also `CONFIG_CHANGE_APPROVED=` with an empty value.
6. No protected file, profile value or gate flag changed to obtain a pass, and no target is reported passed that did not run.
7. The evidence block and the verdict line are printed.

## Steps

### 1. Resolve the profile and the base

1. Read the twelve keys above from `.claude/rust-sdlc.yml`. A missing or unreadable profile stops with the escalation block and `recommended_action: run /rs-sdlc-setup on the default branch and commit the result`.
2. Branch on `capabilities.run_in_container`: true selects container mode (step 3, then the suffix `RUN_IN_CONTAINER=1` on every `make` call); false selects host mode, where `command -v cargo` must succeed. In host mode with no `cargo` on `PATH`, record every stage `not run (no toolchain)` (degrade D3) and end `ESCALATED`.
3. A stage key that is null records that stage `not run (capability absent)` (degrade D1); never substitute another target or a raw command for it.
4. Take the base from the invoking stage: the merge-base sha it computed, or `HEAD` after its D24 fallback. Used directly, compute it once with `git merge-base HEAD origin/<default branch>`.

### 2. Run every call outside the foreground allowlist in the background

Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` and `bmalph run`, runs through the Bash tool with `run_in_background: true` (never a trailing `&`), logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled with `common.sh wait_log` at most every 30 s.

1. Create the log directory once, in the foreground: `mkdir -p target/rust-sdlc/logs`.
2. Take the UTC stamp in the foreground with `date -u +%Y%m%dT%H%M%SZ`; `<stage>` is the invoking stage id (`implement`, `review`, `new-context`, ...).
3. Start the call with `run_in_background: true` as the wrapper `{ <command>; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/<stage>-<UTC>.log 2>&1`.
4. Wait for the background-task completion notice. When none arrives (headless runs) and for progress reads, run `common.sh wait_log target/rust-sdlc/logs/<stage>-<UTC>.log` (the plugin library's dispatcher). It checks the last line every 30 s for at most 110 s per call, prints the last 40 lines and then either `RUST_SDLC_EXIT=<n>` (exit 0) or `WAITING: <log> (<elapsed>s)` (exit 1). On `WAITING:` call it again at once; it does the waiting itself.
5. Stop waiting when the invoking stage's time budget is spent: record the stage `failed`, quote the log tail and end `ESCALATED`. A poll never outlives the budget.
6. When the runtime prompts for the wrapper, issue the same call as `<command> > target/rust-sdlc/logs/<stage>-<UTC>.log 2>&1` in the background and take the exit status from the completion notice instead of the `RUST_SDLC_EXIT=` line.

The foreground allowlist and the branch for each key when it is null:

| Foreground call | Used for | When the key is null |
| --- | --- | --- |
| `make <make.ci_list>` | reading the gate order (step 4) | read the Verification section of `AGENTS.md`; record the read `not run (capability absent)` |
| `make help` | listing the targets when a profile value must be checked against the Makefile | — |
| `make <make.check_commit_message> COMMIT_TITLE='<subject>'` | the plugin commands' pre-validation of a commit or PR title without a space-hyphen sequence | the commands validate with `common.sh is_commit_subject '<subject>'` |
| `make <make.doctor>` | the host-prerequisite report attached to a Docker-less classification (step 5) | the evidence records `doctor: not available (capability absent)` |
| `make <make.install_hooks>` | activating the hooks when `common.sh hooks_active` prints `HOOKS: unset` | record `not run (capability absent)`; a stage that must commit then escalates with the hook state |

A stage call as it is issued at the reference template:

```bash # profile-example
mkdir -p target/rust-sdlc/logs
date -u +%Y%m%dT%H%M%SZ
{ make ci-static-analysis RUN_IN_CONTAINER=1; echo "RUST_SDLC_EXIT=$?"; } > target/rust-sdlc/logs/review-20261112T101500Z.log 2>&1
```

### 3. Container mode

In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.

- `capabilities.run_in_container` true:
  1. Probe `docker info` in the foreground. A failing probe is D25: record every stage `not run (no Docker)`, attach the doctor output of step 5 and end `ESCALATED`.
  2. Check `docker compose ps --status running --quiet app`. Non-empty output means `app` runs; go on.
  3. Empty output: run `make <make.start> RUN_IN_CONTAINER=1` in the background (step 2) and wait at most 900 s. When it exits non-zero, or the check still prints nothing, run it once more (the one restart attempt). A second failure, or a null `make.start`, is D25: every stage `not run (no Docker)`, the doctor output attached, `ESCALATED`.
  4. Append `RUN_IN_CONTAINER=1` after the target of every `make` call; the prefix form is for hooked git calls only (`RUN_IN_CONTAINER=1 git commit -F <file>`, `RUN_IN_CONTAINER=1 git push -u origin HEAD`), which the plugin commands own and this skill never issues.
  5. A raw call of the plugin's short exception list (for example the single raw test call of [testing-workflow](../testing-workflow/SKILL.md)) goes through the container route `docker compose exec -T --user <uid>:<gid> app <command>`, with the uid and gid resolved once by `id -u` and `id -g` and written as literals.
  6. An exec that fails because `app` stopped mid-run gets the same single restart attempt; a second failure is D25.
- `capabilities.run_in_container` false: no suffix and no precondition; the stages run on the host toolchain, and the Docker probe of step 5 still applies.

### 4. Read the gate order

1. `make.ci_list` non-null: run `make <make.ci_list>` in the foreground (with the container suffix in container mode). It prints the ordered gate targets, one per line; quote them in the evidence.
2. `make.ci_list` null: read the ordered list from the Verification section of the repository's `AGENTS.md` and record the read `not run (capability absent)`.
3. Read which gate belongs to which stage from the Makefile, so that a failing gate can be named and routed:

   ```bash
   grep -hE '^CI_[A-Z_]+_TARGETS[[:space:]]*:?=' Makefile make/*.mk
   ```

The stage membership at the reference template, quoted from its `Makefile` (re-read the live file, never this block; the last line is the seventh stage, which the plugin never runs):

```text # profile-example
CI_PREFLIGHT_TARGETS := validate-configuration validate-invariants secrets-scan lint-repo lint-load-tests validate-architecture-model
CI_STATIC_ANALYSIS_TARGETS := format-check validate-manifest check-crate-isolation static-analysis complexity architecture check-security unused-dependencies check-requirements docs-check
CI_TESTS_TARGETS := setup-test-db validate-sqlx-metadata tests-with-coverage doc-tests e2e-tests
CI_CONTRACTS_TARGETS := validate-contract-snapshots validate-openapi-spec openapi-diff graphql-diff
CI_MUTATION_TARGETS := mutation-tests-diff
CI_DELIVERY_TARGETS := build-prod-image image-scan schemathesis-validate smoke-load-tests
CI_CLI_TARGETS := bats
```

### 5. Classify a Docker-less target

1. In host mode, probe `docker info` in the foreground before the first stage. A failing probe means the Docker-dependent gates cannot run: record every stage `not run (no Docker)`, run no stage, and go to item 3.
2. During a stage, the template's message `This target needs a reachable container engine (docker).` in the log marks that stage `not run (no Docker)`, never `failed`, whatever the exit code; the stages after it are recorded `not run (no Docker)` as well and are not started.
3. Run `make <make.doctor>` in the foreground (with the container suffix in container mode) and attach its output to the evidence and to `blocking_finding`; a null `make.doctor` records `doctor: not available (capability absent)`.
4. A Docker-less classification is degrade D2 (D25 in container mode): the skill ends `ESCALATED`. It is never fed to a fix, never retried in a loop and never counted as an iteration.

### 6. Run the stages one per call

For each stage key in order (`make.ci_preflight`, `make.ci_static_analysis`, `make.ci_tests`, `make.ci_contracts`, `make.ci_mutation`, `make.ci_delivery`):

1. Null key: the row is `not run (capability absent)`; continue with the next stage.
2. `make.ci_delivery` when the invoking stage is the implementation or the review stage: the row is `not run (deferred to PR CI)`; the finish-pr stage judges those checks on the pull request.
3. Build the call with no make option and only these suffix variables:
   - `make <make.ci_preflight> base_ref=<sha> CONFIG_CHANGE_APPROVED=` (the approval variable always empty);
   - `make <make.ci_contracts> base_ref=<sha>` and `make <make.ci_mutation> base_ref=<sha>`;
   - `make <make.ci_static_analysis>`, `make <make.ci_tests>` and `make <make.ci_delivery>` with no variable;
   - plus `RUN_IN_CONTAINER=1` on each of them in container mode.
4. Run the call in the background (step 2) and wait for its exit line before starting the next stage; never two stages at once.
5. Classify: `RUST_SDLC_EXIT=0` is `passed`; the template's Docker message is step 5; any other non-zero exit is `failed`. A stage stops at its first failing gate. The first `*** [` line of the log names that gate, or the prerequisite inside it that failed (`make[1]: *** [<file>:<line>: <gate>] Error <n>`); the failing tool's own output sits right above that line.
6. A `failed` stage goes to step 7 before the next stage starts.

The six calls at the reference template, host mode (container mode appends `RUN_IN_CONTAINER=1` to each line):

```bash # profile-example
make ci-preflight base_ref=<merge-base sha> CONFIG_CHANGE_APPROVED=
make ci-static-analysis
make ci-tests
make ci-contracts base_ref=<merge-base sha>
make ci-mutation base_ref=<merge-base sha>
make ci-delivery
```

### 7. Fix a failing gate within the bound

1. Route the failing gate to its owner: first by the repository skill's owner list, else by this table.

   | Failing gate (what it checks) | Owner |
   | --- | --- |
   | configuration guard (a protected file or directory differs from the base) | nobody may fix it in the loop: end `ESCALATED` with `recommended_action: approved-config-change label and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1` |
   | repository invariants, repository lint, documentation drift | [documentation-sync](../documentation-sync/SKILL.md) |
   | secrets scan, production-image build and scan | [security-audit](../security-audit/SKILL.md) |
   | architecture model | [architecture-model-sync](../architecture-model-sync/SKILL.md) |
   | load-script lint, smoke load budget | [load-testing](../load-testing/SKILL.md) |
   | formatting and strict lint | apply the repository's formatter for formatting; lint diagnostics with [rust-error-handling](../rust-error-handling/SKILL.md) or [async-runtime-safety](../async-runtime-safety/SKILL.md) |
   | complexity | [complexity-management](../complexity-management/SKILL.md) |
   | layer rules, crate isolation | [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md) |
   | lockfile against manifests, dependency policy, unused dependencies | [dependency-policy](../dependency-policy/SKILL.md) |
   | service configuration check | [configuration-management](../configuration-management/SKILL.md) |
   | test-database setup and migrations, offline query metadata | [database-migrations](../database-migrations/SKILL.md) |
   | unit, documentation, integration and end-to-end tests, coverage, mutation | [testing-workflow](../testing-workflow/SKILL.md) |
   | contract snapshots, OpenAPI lint, breaking-change diffs, conformance | [api-contract-development](../api-contract-development/SKILL.md) |

2. Fix the root cause with the owning skill; never change the gate, its configuration or the profile.
3. One iteration is one fix followed by a re-run of the failed stage and then of the stages after it. Log `verification iteration <n>/5: <stage target> (<gate>) -> <result>`. The budget is 5 iterations; inside a stage command it is that stage's `MAX_ITERATIONS=5`, and the counter is never reset.
4. A fix changes the tree, so once every stage has passed, run once more each stage that passed before the last fix (a confirmation round). A failure in that round starts the next iteration.
5. A stage still failing after iteration 5/5 ends `ESCALATED` with the escalation block, `blocking_finding: <stage target> -> <gate> (exit <n>), log <path>`.

### 8. Record the result

1. Write one row per stage key: `<stage target>: passed | failed | not run (<reason>)`, the reason from the closed set `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI`. A call refused by a permission ask rule is `not run (ask rule)` and ends `ESCALATED`.
2. Close out as the repository asks: the targets that ran with their result, the targets that did not run with the reason, and every gate that stayed red with its cause. Never report a target as passed that did not run.
3. Print the evidence block and the verdict line of the Verification section.

## Constraints

- Never run the aggregate `make ci` in one call, and never run two stage targets in one call or at the same time.
- Never put a make option before or after the target, and never pass a variable other than `RUN_IN_CONTAINER=1`, `base_ref=<sha>` and the empty `CONFIG_CHANGE_APPROVED=`; the approval variable is never given a value.
- Never append `&` to a make, git or bmalph call, never use `nohup`, and never wait with a bare `sleep`; wait only through the completion notice or `common.sh wait_log`.
- Never run a `make` call outside the five-call foreground allowlist in the foreground.
- Never record a Docker-less target as `failed`, never remediate it and never retry it in a loop.
- Never edit a protected file (the list printed by `cargo xtask config-guard --list`), a gate flag or the profile to obtain a pass; a needed protected change ends `ESCALATED`.
- Never restate the gate order or the stage membership outside a `# profile-example` fence; read both at runtime.

## Verification

1. Each call left a log with its exit line, and no stage target appears twice in one log (each command prints one line per call):

   ```bash
   grep -H '^RUST_SDLC_EXIT=' target/rust-sdlc/logs/<stage>-*.log
   ```

2. The gate order quoted in the evidence equals the current output of the target mapped by `make.ci_list` (or the `AGENTS.md` list when that key is null).
3. Nothing protected changed: `git status --porcelain` lists no path from `cargo xtask config-guard --list`.

Evidence block, printed once at the end:

```text
skill: verification-workflow
source: repo+plugin | plugin
precedence: <repository rule followed instead of a step of this skill | none>
mode: host | container
gate order: <targets in printed order | read from AGENTS.md>
base_ref: <merge-base sha | HEAD (D24)>
targets run:
- <stage target>: passed | failed | not run (<reason>)
failing gate: <gate> -> <owning skill> | none
doctor: <doctor output summary | not run | not available (capability absent)>
logs: <one log path per call>
degrade notes: <one per line | none>
iteration: <n>/5
verification-workflow: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
```

The verdict is `SUCCESS` when every stage the invoking stage runs passed (a delivery row `not run (deferred to PR CI)` in the implementation or review stage is the designed path, not a note), `SUCCESS-WITH-REPORT` when the only notes are absent capabilities (`not run (capability absent)`), and `ESCALATED` otherwise. A resolved example from a review run:

```text # profile-example
- ci-preflight: passed
- ci-static-analysis: passed
- ci-tests: passed
- ci-contracts: passed
- ci-mutation: passed
- ci-delivery: not run (deferred to PR CI)
verification-workflow: SUCCESS
```

When the verdict is `ESCALATED`, print the canonical block with the invoking stage's id and exit string:

```text
=== SDLC ESCALATION ===
stage: <stage-id of the invoking command>
iteration: <n>/5
exit_condition: <exit string of the invoking stage, verbatim>
status: NOT MET
blocking_finding: <stage target -> gate (exit n), log path | not run (no Docker) with the doctor output>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human action: start Docker, an approved-config-change label, a fix the owning skill could not make>
=== END ===
```
