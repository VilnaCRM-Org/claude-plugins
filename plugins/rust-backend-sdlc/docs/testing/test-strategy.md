# Test strategy

This document explains how rust-backend-sdlc is tested: the four surfaces under test, the 16 bats suites and their floors, the fixtures and stub executables the suites run against, the pinned template linters, the skip policy, the two YAML backends, the map from every degrade path D1–D25 to the tests that prove it, and the recorded negative check of the generalization audit (AC-43.2). The degrade paths themselves are described in [the degrade matrix](../degrade-matrix.md); the profile keys the suites mutate are described in [the profile schema](../profile-schema.md); the stages and exit strings the Markdown contracts pin are described in [the SDLC loop](../sdlc-loop.md).

## Surfaces

| Surface | Under test | How it is exercised | What pins it |
| --- | --- | --- | --- |
| Scripts | the 13 executables of `scripts/` and the library `scripts/lib/common.sh` with its 17 dispatcher names | one bats suite per script plus `common-lib.bats`; each script runs as a black box in a materialized repository with stubs first on `PATH`; the library is sourced for its functions and executed for its dispatcher | every documented flag, exit code (ADR-23), refusal and `--help` has a case (NFR-8); `shellcheck -x` reports nothing |
| Markdown contracts | the 10 commands, 7 agents, 28 skills, 2 meta-guides, 9 docs, `.claude-plugin/plugin.json` and the marketplace entry | `component-counts.bats` reads the files and asserts CC-01 to CC-36; the CI jobs `markdown-lint`, `frontmatter-check`, `profile-keys-check` and `generalization-audit`; `tools/plugin-quality/lint/lint_all.py` in the `prompt-lint` job of `prompt-quality.yml` | counts, the command and agent spines, verbatim sentences, exit strings, command tokens, the P1–P7 rules, profile keys and the degrade map below |
| Workflows through the harness | the 4 `workflows/*.js` scripts | `workflows.bats` runs `node tests/lib/workflow-harness.mjs [--as-child] <workflow.js> <scenario.json>`: the harness loads the script without Claude Code, answers every agent call from the scenario's scripted replies and prints `{meta, result or error, calls, phases, logs}` as JSON | 11 static cases plus one case per scenario file (103) and one schema-gap case; a scenario gap (an agent call without a reply) or a schema gap fails the case |
| Fixtures | everything under `tests/fixtures/` | the repository fixture is materialized into `$BATS_TEST_TMPDIR` by `rr_materialize`; the data fixtures (profiles, ledgers, payloads, scenarios) are read-only inputs; no case writes under `tests/fixtures/` | CC-29 and AC-42.1: no `*.md` file under `tests/fixtures/`, no path the root `.gitignore` matches, no `_bmad` or `.ralph` path component |

Every suite is hermetic. Its `setup` loads `lib/helpers` and calls `common_setup`, which puts `tests/fixtures/bin` first on `PATH`, points every `STUB_*_LOG` into `$BATS_TEST_TMPDIR/stub-logs/`, exports `STUB_DOCKER_INFO_EXIT=1` (Docker is unreachable unless a case says otherwise) and unsets `CLAUDE_PLUGIN_ROOT`. A case writes only under `$BATS_TEST_TMPDIR`, reaches no network (`gh`, `curl` and `claude` are stubs), reads the clock through `SDLC_NOW_EPOCH` where time matters and is named `@test "<script>: <behaviour>"`. Suite-local helpers stay in their suite; `tests/lib/helpers.bash` is single-writer.

`tests/lib/docs-rules.py` is the static port of the template's docs-check rules 1–4 plus invariant (e); the `docs_rules` helper runs it, and `inject-governance.bats` uses it to prove that the governance block passes the template's documentation checks (AC-8.2).

## Suites and floors

A floor is the minimum number of cases a suite holds, counted with `grep -c '^@test' tests/<suite>.bats`; CC-08 asserts every floor. The binding floors are the architecture's: they amend the per-suite floors of NFR-8 and may only be raised. The floors total **557** (NFR-8 asks for at least 460); after the workflow cut they total **491** (NFR-8 asks for at least 415).

| Suite | Floor | NFR-8 floor | Script or surface | Focus |
| --- | --- | --- | --- | --- |
| `common-lib.bats` | 72 | 36 | `scripts/lib/common.sh` | every function and the 17-name dispatcher (no argument exits 64); `ledger_write` refusals; `have_yq` rejects the kislyuk stub; YAML parity; `toml_*`; `validate_context_name`; `resume_point` and `state_cache_update`; `utc_now`/`utc_stamp`; `redact` per pattern; `wait_log`; `http_probe`; `protected_changes`; the Ralph helpers; the bash floor |
| `setup-preflight.bats` | 23 | 23 | `setup-preflight.sh` | each check PASS/FAIL with its remediation; `--report`; under-version stubs; the bmalph WARN path; kislyuk `yq` with and without PyYAML; dirty tree INFO |
| `generate-profile.bats` | 33 | 30 | `generate-profile.sh` | golden byte-equality; one fallback per optional source; no `cargo`, `make` or `gh` call; `--refresh` and ADR-24 preserve; AC-6.5 to AC-6.7; K7 yamllint and Prettier; 5 s timing; parity |
| `validate-profile.bats` | 33 | 30 | `validate-profile.sh` | the golden profile valid on both backends; the V1–V12 rejections; null where allowed and where not; malformed YAML without a traceback |
| `inject-governance.bats` | 30 | 30 | `inject-governance.sh` | create, append, idempotent, in-place replace; duplicate, orphan, inverted, fenced and CRLF markers; `--diff`; docs-check rules and invariant (e); K7 markdownlint-cli2 and typos; the exact block text |
| `merge-settings.bats` | 24 | 15 | `merge-settings.sh` | protected settings untouched; a local file that is not git-ignored refused; allow and deny union and order; the exact allow set; second run `UNCHANGED:` |
| `new-service.bats` | 34 | 30 | `new-service.sh` | the five modes with `gh` routes; every customize step; both sync flavours and the citation repair; defaults and config precedence; K7 on `README.md`, `CHANGELOG.md` and `bmalph/config.json` |
| `stage-planning-artifacts.bats` | 15 | 12 | `stage-planning-artifacts.sh` | the staged file set; stale removal; the six FR-17 refusals; `## Constraints` over 4,500 characters; exit 2 outside a git work tree; `--dry-run` |
| `ai-review-loop.bats` | 25 | 23 | `ai-review-loop.sh` | the php cases ported; profile defaults; the isolated session argv and environment; a session that changes the tree exits 1; parity |
| `fr-nfr-gate.bats` | 54 | 50 | `fr-nfr-gate.sh` | the react cases ported: sources, fail-closed, advisory, status context, isolation, retries, byte budgets; the baseline ids; `--bot-login` |
| `get-pr-comments.bats` | 32 | 31 | `get-pr-comments.sh` | pagination, filters, the JSON shape with `author_association`, jq and python parity, validation |
| `post-review-findings.bats` | 46 | 41 | `post-review-findings.sh` | the ADR-16 ledger schema; lens and conclusion markers; forged markers ignored; `--bot-login`; degrade-first exits |
| `pr-state.bats` | 33 | 30 | `pr-state.sh` | the verdict priority; human-gated checks by check name; service-added checks; profile defaults; zero checks with a profile list is `WAIT`; the `NEXT:` label |
| `request-ai-reviews.bats` | 17 | 17 | `request-ai-reviews.sh` | the react cases ported; profile default reviewers; validation harmonised with `pr-state.sh` |
| `component-counts.bats` | 20 | 20 | Markdown contracts | one case per id CC-01 to CC-36 and the check of every citation in the degrade map below |
| `workflows.bats` | 66 | 45 | workflows through the harness | 115 cases: 11 static cases (meta literal, phases, banned clock and random calls, nested names, call depth, P1–P7 and generalization grep, prompt sentences), one case per scenario (103) and one schema-gap case |
| **Total** | **557** | 463 | | after the cut: 491 (NFR-8: 418) |

The workflow layer is the cut line (ADR-18). If it is cut, `workflows.bats`, the four workflows, the harness, the 103 scenario files and `docs/workflows.md` leave the plugin together: 15 suites with floors totalling 491, 8 docs, and the Workflow scenarios column of the degrade map empties (D21, which only a workflow can reach, leaves the map with them).

## Fixtures and stubs

No case writes under `tests/fixtures/`, and no fixture is a committed `*.md` file: planning bundles are written at runtime by `bundle_write DIR [--blocked]` (seven files; `--blocked` puts `NO-GO` in the readiness file), `_bmad/` and `.ralph/` trees are created by the cases or by the `bmalph` stub, and fixture Markdown ships as `*.md.tpl`.

### The materialized repository

`tests/fixtures/rust-repo/` is the stub of a template-derived service (`acme/billing-service`, template `acme/rust-template`): a virtual workspace with `crates/billing/invoice/{domain,application,infrastructure}`, `crates/shared/*`, `crates/internal/health-check/*`, `crates/service`, `tests/support`, `tests/e2e` and `xtask`, the template's configuration files (`architecture.toml`, `clippy.toml`, `deny.toml`, `protected-config.toml`, `make/gates.mk`, `make/service.mk`, a `Makefile` with `##` targets and `CI_*_TARGETS`), the CI workflows including both sync workflows, the OpenAPI and GraphQL snapshots, copies of the template's linter configurations (`.yamllint.yml`, `.prettierrc.yml`, `.markdownlint-cli2.yaml`, `_typos.toml`) and the template's Markdown documents.

`rr_materialize DEST [ORIGIN_SLUG]` copies it to `DEST` (the suites use `$BATS_TEST_TMPDIR/billing-service`, the directory name the golden profile assumes) and applies the rename map:

| In the fixture | Materialized as | Why |
| --- | --- | --- |
| `*.tpl` (for example `README.md.tpl`, `AGENTS.md.tpl`, `docs/repository-settings.md.tpl`) | the same name without `.tpl` | no committed `*.md` under `tests/fixtures/` (AC-42.1, CC-29): fixture Markdown never reaches the repository's `markdown-lint` job |
| `gitignore.tpl` | `.gitignore` | a fixture `.gitignore` would change what the marketplace repository tracks |
| `dot-claude/` | `.claude/` | the root `.gitignore` matches `.claude/` at any depth, so a fixture directory of that name would never be committed |
| `dot-bmalph/` | `bmalph/` | the root `.gitignore` matches `bmalph/` at any depth, for the same reason |

It then runs `git init -q -b main`, makes one commit authored and committed by `acme <ci@example.invalid>` with fixed dates, and sets `origin` to `https://github.com/${ORIGIN_SLUG:-acme/billing-service}.git`. Because no fixture path is git-ignored, a plain `git add` ships every fixture and CI sees the tree a local run sees; CC-29 runs `git check-ignore --no-index` over every fixture file to keep it so.

### Other fixtures

| Directory | Holds | Used by |
| --- | --- | --- |
| `profiles/` | `golden.yml` (the generator's output for the materialized repository) and the variants `bad-enum.yml`, `invalid-yaml.yml`, `publish-off.yml`, `wrong-schema-version.yml`; every other invalid profile is made at runtime with `mutate_profile FILE KEY VALUE` or `drop_profile_key FILE KEY` | `ai-review-loop`, `common-lib`, `fr-nfr-gate`, `generate-profile`, `post-review-findings`, `pr-state`, `request-ai-reviews`, `validate-profile` |
| `ledgers/` | review ledgers of the ADR-16 schema: valid, edge (null location, times, 20-digit iteration, deduplication) and invalid (extra key, wrong `schema_version`) | `post-review-findings` |
| `gh/` | `gh` JSON payloads: PR review comments (paged, truncated, untrusted), issue comments (regular, forged, oversized NDJSON), issue state comments, and `gh/pr-state/` with the PR snapshots, review streams and comment streams of the sensor | `common-lib`, `get-pr-comments`, `post-review-findings`, `pr-state`, `request-ai-reviews` |
| `variants/` | `repository-settings-service.md.tpl` (the service variant with one more `Required: yes` row) and `extension-seams-fixed.md.tpl` (the already repaired citation) | `common-lib`, `generate-profile`, `new-service` |
| `ralph/` | `AGENT.md.tpl`, the `.ralph/@AGENT.md` the `bmalph` stub writes on `implement` | `common-lib` |
| `workflows/` | the 103 scenario files: `feat-` (32), `fnr-` (23), `pug-` (30), `rp-` (18) | `workflows.bats` |
| `bin/`, `bin-kislyuk/` | the stub executables below | `bin/`: every suite, through `common_setup`; `bin-kislyuk/`: `common-lib`, `setup-preflight` |

### Stub executables

Every stub logs its calls to its `STUB_<NAME>_LOG` and is driven only by environment variables, so a case states its world in its own body.

| Stub | Main controls (default) | Behaviour |
| --- | --- | --- |
| `bin/claude` | `STUB_CLAUDE_VERSION` (`2.1.322`), `STUB_CLAUDE_RESTRICTED` (`1`), `STUB_CLAUDE_EXIT`, `STUB_CLAUDE_OUTPUT`, `STUB_CLAUDE_OUTPUTS_DIR` | `--version`; `--help` lists `--restricted` when enabled; otherwise prints the JSON reply (the n-th file of the outputs directory, the last one repeating) and logs the argv and the ADR-8 environment set as `NAME=<value>` or `NAME unset` |
| `bin/gh` | `STUB_GH_VERSION` (`2.62.0`), `STUB_GH_AUTH_EXIT`, `STUB_GH_EXIT`, `STUB_GH_OUTPUT`, `STUB_GH_ROUTES`, `STUB_GH_STRICT`, `STUB_GH_CLONE_SOURCE` | routes are `<argv glob>`, exit code and stdout file per line, first match wins; strict mode makes an unmatched call exit 9; `repo clone` copies and commits the clone source; logs the argv and the stdin of `-F body=@-` |
| `bin/bmalph` | `STUB_BMALPH_VERSION` (`2.11.0`), `STUB_BMALPH_EXIT`, `STUB_BMALPH_DOCTOR_EXIT`, `STUB_BMALPH_OUTPUT` | `--version`, `doctor`, `run`; `implement` mirrors bmalph 2.11.0: with `.ralph/@fix_plan.md` present it prints `Warning: bmalph implement has already been run.` and exits 1, otherwise it writes `.ralph/@fix_plan.md`, `.ralph/PROJECT_CONTEXT.md` and `.ralph/@AGENT.md` |
| `bin/curl` | `STUB_CURL_EXIT`, `STUB_CURL_OUTPUT` | logs the argv and prints a canned `HTTP/1.1 200` response for the `http_probe` cases |
| `bin/cargo` | `STUB_CARGO_EXIT` | records calls (the generator asserts zero) |
| `bin/make` | `STUB_MAKE_VERSION_LINE` (`GNU Make 4.4.1`), `STUB_MAKE_EXIT` | `--version`; records calls |
| `bin/docker` | `STUB_DOCKER_INFO_EXIT` (`1` after `common_setup`) | the exit code of `docker info`; records calls |
| `bin-kislyuk/yq` | none | prints `"array"` for any expression and `yq 3.4.3` for `--version` |

The kislyuk `yq` stub lives in `tests/fixtures/bin-kislyuk/`, not in `tests/fixtures/bin/`, on purpose (ADR-22). `common_setup` puts `tests/fixtures/bin` first on `PATH` in every case, so a `yq` there would shadow the real mikefarah `yq` in every suite and silently move all of them onto the python backend. Only the cases that need the python wrapper (the `have_yq` rejection in `common-lib.bats`, the yaml-backend rows of `setup-preflight.bats`) put `bin-kislyuk/` first on `PATH`.

`sandbox_path TOOL…` builds a `PATH` that holds only the named tools, which is how a case makes `jq`, `python3`, `node` or another tool genuinely absent.

## Template linter pins (K7)

Plugin output written into a service must pass the template's own linters. The K7 cases run each linter with the configuration copied from the template into the fixture, at the versions the template pins:

| Tool | Version | Installed in CI by | Cases |
| --- | --- | --- | --- |
| yamllint | 1.38.0 | `pipx install yamllint==1.38.0` | `generate-profile.bats`, `validate-profile.bats` (the profile, with `.yamllint.yml`) |
| Prettier | 3.9.10 | `npm install --prefix "$RUNNER_TEMP/k7" prettier@3.9.10` | `generate-profile.bats`, `validate-profile.bats` (the profile), `new-service.bats` (`bmalph/config.json`), with `.prettierrc.yml` |
| typos | 1.52.0 | `pipx install typos==1.52.0` | `inject-governance.bats` (`CLAUDE.md`, `AGENTS.md`), `new-service.bats` (`README.md`, `CHANGELOG.md`), with `_typos.toml` |
| markdownlint-cli2 | 0.24.0 | `npm install --prefix "$RUNNER_TEMP/k7" markdownlint-cli2@0.24.0` | `inject-governance.bats`, `new-service.bats`, with `.markdownlint-cli2.yaml` |

The `bats` job of `.github/workflows/ci.yml` installs all four before it runs the suites, so every K7 case runs in CI. Each K7 case starts with `k7_require <tool>`.

## Skip policy

A case may skip only for one of the reasons below, and every skip prints its reason, which bats shows in its report. No case skips to hide a failure, and no threshold is lowered to make a case pass.

| Reason | Mechanism | Printed reason |
| --- | --- | --- |
| uid 0 | permission-denied cases (an unreadable profile, a read-only file, an unwritable directory) call `skip_if_root` first, because root ignores file modes | `running as root (uid 0): file permissions are not enforced` |
| an absent optional tool | K7 cases call `k7_require <tool>`; the jq parity case of `get-pr-comments.bats` needs both renderers | `<tool> not installed (runs in CI)`; `jq not installed: the parity case needs both renderers` |
| an absent optional input | the byte-identity cases against the sibling plugins (CC-30) and the cases that compare with the architecture document skip when that file is not part of the checkout | the missing plugin or file, named |
| a yq-only case | a case that needs mikefarah `yq` gates on `have_yq`, never on `command -v yq`: the kislyuk wrapper also answers to `yq` but cannot run mikefarah expressions | the missing mikefarah `yq`, named |

A K7 skip is expected on a workstation without the tool and is a defect in CI, where the `bats` job installs every pinned tool.

## YAML backends and the two-backend run

The scripts read YAML through one of two backends. `have_yq` accepts a `yq` only when `printf 'a: [1]\n' | yq '.a | type'` prints `!!seq` (mikefarah); anything else, including the kislyuk wrapper that prints `"array"`, falls back to python3 with PyYAML. `SDLC_FORCE_PYTHON_YAML=1` forces the python backend even where mikefarah `yq` is installed. Both backends must print the same bytes.

- Locally, every suite runs twice: once as is and once with `SDLC_FORCE_PYTHON_YAML=1`. A session host usually has the kislyuk wrapper, so the first run often takes the python path too; the second run proves the python path on a host with mikefarah `yq`.
- CI's `bats` job runs every suite once on a runner with mikefarah `yq`, which exercises the `yq` path. The python path is pinned there by the explicit parity cases, which set `SDLC_FORCE_PYTHON_YAML=1` and compare both outputs byte for byte, in `common-lib.bats`, `generate-profile.bats`, `validate-profile.bats` and `ai-review-loop.bats`; `setup-preflight.bats` asserts the variable's effect on its yaml-backend row.
- JSON has a backend pair as well: `jq` when present, python3 otherwise. The jq-absent cases use `sandbox_path` without `jq`.

## Degrade map (D1–D25)

Every degrade path of [the degrade matrix](../degrade-matrix.md) is proven by at least one test. The map is machine-checked: the case `component-counts: D-map: …` of `tests/component-counts.bats` parses this table and fails when a citation does not resolve.

Map format: each backticked entry of the Bats cases column is the exact name of a `@test` (the text between its quotes), and the word before its first colon names the suite (`<word>.bats`); each entry of the Contract cases column is the id of a `tests/component-counts.bats` case; each entry of the Workflow scenarios column is a file name under `tests/fixtures/workflows/`; `—` marks an empty cell.

| ID | Condition | Outcome | Bats cases | Contract cases | Workflow scenarios |
| --- | --- | --- | --- | --- | --- |
| D1 | `make.<key>: null` | SUCCESS-WITH-REPORT | `validate-profile: make.check_security: null is valid (AC-7.2)`; `validate-profile: null passes where the schema allows it (the missing-key cases set to null)`; `common-lib: ralph_agent_md_patch: a null make key drops its line and an empty block reads not available (capability absent)` | `CC-20`; `CC-32` | — |
| D2 | Docker unreachable | ESCALATED (implement, review, QA with `make.start`, new-context C12); SUCCESS-WITH-REPORT (new-service S8) | `setup-preflight: Docker is INFO unreachable when docker info fails or docker is absent, INFO reachable otherwise (D2)` | `CC-11`; `CC-19`; `CC-20` | — |
| D3 | no host toolchain, container mode off | SUCCESS-WITH-REPORT (setup step 8); ESCALATED (loop stages, new-context) | `setup-preflight: cargo is INFO present or INFO absent and is never run`; `generate-profile: detection — Docker unreachable and no cargo gives run_in_container false (AC-6.6)` | `CC-17` | — |
| D4 | `.claude/settings.json` protected | SUCCESS-WITH-REPORT | `merge-settings: --file shared on the stub is refused, prints the merged JSON and leaves settings.json unchanged`; `merge-settings: settings.json keeps its checksum under every flag combination`; `merge-settings: --file shared is refused when a listed directory holds .claude/settings.json` | — | — |
| D5 | dirty tracked tree at setup | SUCCESS-WITH-REPORT (setup); ESCALATED (stage 0 while `_bmad/` is absent) | `setup-preflight: a dirty tracked tree is INFO listing the files of git status, untracked files left out (AC-4.4, D5)`; `setup-preflight: dirty tree, a missing marker, Docker unreachable and no cargo are INFO/WARN only, exit 0 (AC-4.4)` | `CC-17` | — |
| D6 | bmalph absent but installable | SUCCESS | `setup-preflight: bmalph absent with a bmalph-setup target, node 20 and npm WARNs and exits 0 (D6)`; `setup-preflight: a bmalph-setup target in make/*.mk also makes bmalph installable` | `CC-17` | — |
| D7 | no AI reviewer | SUCCESS-WITH-REPORT | `request-ai-reviews: an empty review.reviewers prints INFO: no reviewers configured and exits 0`; `ai-review-loop: PASS on iteration 1 exits 0 with the iteration line and the review text` | `CC-20` | `pug-silent-reviewer.json` |
| D8 | no CI | SUCCESS-WITH-REPORT | `pr-state: ci.provider null is CI none when the PR reports no checks, and required checks are never awaited`; `pr-state: zero reported checks with a non-empty ci.required_checks is WAIT, never CI none or SKIPPED-NO-CI`; `pr-state: an empty --required-checks never fakes no CI: zero reported checks with a non-empty ci.required_checks is WAIT (D8)` | `CC-21` | — |
| D9 | failing human-gated check, or an unlabelled breaking change | ESCALATED | `pr-state: a failing human-gated check named with a space is BLOCKED naming approved-config-change, not FIX`; `pr-state: a failing human-gated check that no label maps falls back to the label named in docs/repository-settings.md`; `common-lib: human_gated_labels: maps the fixture's labels to check names (singular and plural forms)` | — | `pug-human-gated-blocked.json` |
| D10 | `gh` unreachable | ESCALATED (issue, finish-pr); SUCCESS-WITH-REPORT (resume from the cache) | `common-lib: resume_point: a resume at review iteration 3 restores the counter, from the cache and from its state comment`; `common-lib: resume_point: a missing or malformed cache exits 1, a bad cache name exits 2` | `CC-33` | — |
| D11 | no PR at review time | SUCCESS-WITH-REPORT | `fr-nfr-gate: the fail-closed path with --advisory posts nothing (D11)`; `fr-nfr-gate: --advisory reviews but posts neither a status nor a comment`; `fr-nfr-gate: with no pull request and no base branch a publishing run fails closed; --advisory reviews the whole tree` | — | `fnr-advisory.json` |
| D12 | comment publishing off | SUCCESS-WITH-REPORT | `post-review-findings: publishing off (publish-off.yml) is a degrade without a gh call, also with --dry-run`; `generate-profile: fallback — outside a git work tree project.repo is null and publishing is off` | — | — |
| D13 | `ask` rule in a headless run | SUCCESS-WITH-REPORT | — | `CC-20`; `CC-21` | — |
| D14 | a call that may exceed 600 s | SUCCESS | `common-lib: wait_log: a still-running log with MAX 30 checks again after 30 s and prints WAITING (exit 1)`; `common-lib: wait_log: a log that finishes during the wait exits 0 at the next check` | `CC-11` | — |
| D15 | claude without `--restricted` | ESCALATED | `setup-preflight: claude without --restricted FAILs claude-restricted with the upgrade remediation (D15)`; `fr-nfr-gate: a claude without --restricted fails fast with the upgrade remediation (D15)`; `ai-review-loop: claude without --restricted exits 1 before any session`; `common-lib: claude_supports_restricted: true exactly when claude --help lists --restricted` | — | — |
| D16 | kislyuk `yq` on the host | SUCCESS | `common-lib: have_yq: rejects the kislyuk stub and caches the verdict`; `setup-preflight: the kislyuk yq first on PATH with PyYAML PASSes yaml-backend through python3 (D16)`; `setup-preflight: the kislyuk yq first on PATH without PyYAML FAILs yaml-backend (D16)`; `validate-profile: parity: the golden profile prints the same bytes on both backends` | — | — |
| D17 | template flag off | SUCCESS-WITH-REPORT | `new-service: clone-and-push imports the template and prints IMPORT_PENDING (D17)` | — | — |
| D18 | sync flavour undecided (headless) | SUCCESS-WITH-REPORT | `new-service: an omitted sync flavour prints SKIP and NEXT (D18)` | — | — |
| D19 | governance markers missing | ESCALATED | — | `CC-20`; `CC-33` | — |
| D20 | not template-derived | SUCCESS-WITH-REPORT | `generate-profile: fallback — one A1 marker missing, or CI_PREFLIGHT_TARGETS not led by validate-configuration (ADR-17)`; `setup-preflight: missing A1 markers WARN naming each one and never FAIL (ADR-17, D20)`; `setup-preflight: a repository without any marker WARNs all eight and still exits 0` | — | — |
| D21 | workflow name unresolved | ESCALATED | — | — | `feat-no-nested.json` |
| D22 | Ralph breaker trips or is not CLOSED before a run | ESCALATED | `common-lib: ralph_breaker_state: OPEN fails`; `common-lib: ralph_breaker_state: HALF_OPEN fails`; `common-lib: ralph_breaker_state: CB_AUTO_RESET=true from the environment fails even with a CLOSED breaker`; `common-lib: ralph_breaker_state: CB_AUTO_RESET=true from .ralph/.ralphrc fails`; `common-lib: resume_point: BLOCKED_STAGE when the implement row is ESCALATED and the breaker is OPEN or HALF_OPEN` | `CC-20` | `feat-implementer-blocked.json` |
| D23 | protected change needed or made | ESCALATED | `common-lib: protected_changes: a protected file changed in a commit, in the working tree or untracked below a protected directory`; `common-lib: protected_changes: a profile present at the base that differs now prints PROFILE_CHANGED`; `common-lib: protected_changes: the list is read at the base, so a dropped entry is still reported` | `CC-20`; `CC-21`; `CC-36` | — |
| D24 | base ref unavailable | SUCCESS-WITH-REPORT | — | `CC-20` | — |
| D25 | container mode, `app` not running | SUCCESS (stack started); SUCCESS-WITH-REPORT (setup step 8, new-service); ESCALATED (loop stages, new-context) | — | `CC-11` | — |

### What the contract cases assert for the map

The contract cases prove the paths that live in Markdown (a command or an agent detects them and reacts in prose), where no script runs that a bats case could call.

- **D2, the Docker precondition and the message-based classification.** `rs-sdlc-implement.md` and `rs-sdlc-review.md` (CC-20) and `rs-sdlc-new-context.md` (CC-19) each state the Docker precondition, a `docker info` probe before the Docker-dependent work (the coverage target of implement, the review rows marked †, the C12 gates of new-context), and the message-based classification: a log that shows the template's message `This target needs a reachable container engine (docker).` classifies its target `not run (no Docker)`, never `failed`, and never feeds remediation, because make exits 2 for any failure and only the message classifies. CC-11 pins the container-precondition sentence quoted under D25 in the same files.
- **D25, the container-precondition sentence (CC-11).** The 9 commands that run make or git (every command except `rs-sdlc-issue.md`) and the 6 agents that run make (every agent except `qa-manual-tester.md`) carry this sentence verbatim:

  > In container mode, before the first make target, raw container-route call or hooked git call, check `docker compose ps --status running --quiet app`; empty output starts `make.start` in the background (≤ 900 s, one restart attempt); `docker info` failing or the stack not starting is D25.

- **D14, the background rule (CC-11).** The same files carry the background sentence, which names `run_in_background: true` and `common.sh wait_log`; no component appends `&` to a make, git or bmalph call. The `wait_log` cases prove the polling bound the sentence relies on.
- **D1, D13, D19, D22, D23 and D24 (CC-20, CC-21, CC-33, CC-36).** The stage commands and agents name the degrade notes and tokens of their rows: `not run (capability absent)` and the Q7 static lane (D1), `not run (ask rule)` (D13), the setup wording of the stage-0 check and the state comment (D19), `ralph_breaker_state`, `.circuit_breaker_state`, `CB_AUTO_RESET` and `BLOCKED_STAGE` (D22), `protected_changes`, `git restore --source=` and `make validate-configuration base_ref=<sha> CONFIG_CHANGE_APPROVED=` (D23), and the one-fetch fallback to `base_ref=HEAD` (D24). CC-32 adds that a `null` key is never replaced by a raw `cargo` call.

## Negative check: the generalization audit (AC-43.2)

The CI job `generalization-audit` of `.github/workflows/ci.yml` greps the component directories (`skills`, `commands`, `agents`, `scripts`, `workflows`) of `plugins/php-backend-sdlc` and `plugins/rust-backend-sdlc` for the NFR-2 denylist, case-insensitively, after dropping every fence whose opening line carries `# profile-example`, and fails on any hit. The denylist holds the marketplace organization's name, so a skill that names the organization in its body must fail the job.

Recorded result (2026-11-12, on a scratch copy of the committed tree): the unseeded copy passes with exit 0 and no output; after one line naming the organization is appended to the body of `skills/testing-workflow/SKILL.md`, the job fails with exit 1 and prints:

```text
FAIL (NFR-2): plugins/rust-backend-sdlc/skills/testing-workflow/SKILL.md contains denylisted identifiers:
<n>:This skill was written for the VilnaCRM services.
```

`<n>` is the line number in the skill after the `# profile-example` fences are dropped. The same seeded copy also fails `python3 tools/plugin-quality/lint/lint_all.py plugins/rust-backend-sdlc` with one `[S1 L28]` finding (`denylisted identifier 'VilnaCRM'`), the rule the `prompt-lint` job applies. The only exemption is a fence whose opening line carries `# profile-example`.

To reproduce, run from the repository root. The commands extract the job's own script from `ci.yml`, so the check is exactly the one CI runs; either `yq` flavour works, and the scratch copy is the committed tree, as CI checks it out:

```bash
scratch=$(mktemp -d) && audit=$(mktemp)
git archive HEAD | tar -x -C "$scratch"
yq -r '.jobs["generalization-audit"].steps[1].run' .github/workflows/ci.yml >"$audit"
(cd "$scratch" && bash "$audit"); echo "control exit=$?"
printf '\nThis skill was written for the VilnaCRM services.\n' >>"$scratch/plugins/rust-backend-sdlc/skills/testing-workflow/SKILL.md"
(cd "$scratch" && bash "$audit"); echo "seeded exit=$?"
rm -rf "$scratch" "$audit"
```

Expected: `control exit=0`, then the two `FAIL (NFR-2)` lines above and `seeded exit=1`. The working tree is never touched.

## Running the checks

From the repository root:

```bash
npx --yes bats plugins/rust-backend-sdlc/tests/*.bats
SDLC_FORCE_PYTHON_YAML=1 npx --yes bats plugins/rust-backend-sdlc/tests/*.bats
for f in plugins/rust-backend-sdlc/tests/*.bats; do printf '%5d %s\n' "$(grep -c '^@test' "$f")" "$f"; done
shellcheck -x plugins/rust-backend-sdlc/scripts/*.sh plugins/rust-backend-sdlc/scripts/lib/common.sh
npx --yes markdownlint-cli2 "plugins/rust-backend-sdlc/**/*.md"
python3 tools/plugin-quality/lint/lint_all.py
```

One suite runs with `npx --yes bats plugins/rust-backend-sdlc/tests/<suite>.bats`, and one group of cases with `--filter '<suite>: <words of the name>'`. To run the K7 cases locally, install the four pinned tools at the versions of the K7 table and put them on `PATH` first.

In CI, the `bats` job runs every suite of every plugin with the K7 tools installed and node available for `workflows.bats`; `shellcheck`, `markdown-lint`, `frontmatter-check`, `profile-keys-check`, `generalization-audit` and `manifest-validate` cover the rest of `ci.yml`, and `prompt-quality.yml` runs `lint_all.py` and `claude plugin validate plugins/rust-backend-sdlc --strict`.
