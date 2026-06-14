# Testing and Validation

[Home](Home.md) › Build › Testing and Validation

This page documents how the **plugin itself** is tested — the CI gates that
run on every pull request, the `bats` suites that pin script behavior, the
Python harnesses that grade prompt quality and security-rule detection, and
the recorded validation campaigns that provide the evidence.

A markdown prompt has no compiler. A renamed script, a vague skill trigger, a
leaked source-project literal, an off-by-one iteration guard, or a security
rule that silently misses a sink would all ship green without these checks.
The plugin therefore pins its runtime contracts (scripts, manifests,
component counts) with `bats` and `shellcheck`, its prompt-artifact contracts
(commands, agents, skills) with a static linter plus an LLM-as-judge, and its
`security-audit` detection rules with a deterministic semgrep corpus.

Verified component counts that several gates assert exactly: **8 commands,
7 agents, 22 skills** (`skills/*/SKILL.md`) plus **2 loose meta-guides**
([AI-AGENT-GUIDE.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md),
[SKILL-DECISION-GUIDE.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md))
at the `skills/` root.

## CI workflows

Four GitHub Actions workflows gate every pull request. All four set a
least-privilege `permissions: contents: read` default and check out with
`persist-credentials: false`.

| Workflow | Concern | Network needed |
| --- | --- | --- |
| `ci.yml` | Plugin **runtime** surfaces (manifest, markdown, scripts, frontmatter, profile keys, generalization) | No |
| `prompt-quality.yml` | **Prompt** quality + structural integrity of every plugin artifact, plus an LLM judge | Judge job only |
| `python-quality.yml` | Code quality of the `tools/plugin-quality` Python | No |
| `security-audit-validation.yml` | Proves the `security-audit` skill's detection works | semgrep + optional judge |

### ci.yml — seven runtime gates

Each job guards for not-yet-existing files so an empty tree still passes; in
the shipped plugin all of them run for real.

| Job | What it enforces |
| --- | --- |
| `manifest-validate` | `marketplace.json` and every `plugin.json` parse, carry required fields, semver version, and `name` == directory name (FR-19). On a `php-backend-sdlc-v*` tag build it also asserts the tag version equals the manifest version (ADR-9 release gate). |
| `markdown-lint` | `markdownlint-cli2` over every `plugins/**/*.md`. |
| `shellcheck` | `shellcheck -x` over `scripts/*.sh` (the `-x` follows the `source lib/common.sh` includes). |
| `bats` | Runs every `tests/*.bats` suite via `npx bats`. |
| `frontmatter-check` | Commands declare `description` + `argument-hint`; agents declare `name`/`description`/`tools`/`model`; each `skills/*/SKILL.md` declares `name` + `description`; loose `skills/*.md` meta-guides must have **no** frontmatter (ADR-11). Uses `yq` with a `python3` + PyYAML fallback so folded scalars parse. |
| `profile-keys-check` | Every profile key a skill lists under `## Profile keys consumed` must be declared in [profile-schema.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md) (FR-17). |
| `generalization-audit` | NFR-2 denylist grep (`user-service`, `vilnacrm`, `apprunner`, `src/oauth`, mongo repository names, …) over skills/commands/agents/scripts, with `# profile-example` fenced blocks stripped; plus NFR-7 tree hygiene (no `_bmad/` or `.ralph/` inside the plugin tree). |

### prompt-quality.yml — static lint + LLM judge

This workflow gates the prompt artifacts themselves (see
[Review and Quality Gates](Review-and-Quality-Gates.md) for the analogous
gates the plugin applies to user code). It is intentionally separate from
`ci.yml`: `ci.yml` checks runtime surfaces, this checks prompt quality.

| Job | Tier | Gate |
| --- | --- | --- |
| `prompt-lint` | Tier-1 static lint + Tier-2 manifest checks (`tools/plugin-quality/lint/lint_all.py`) | Blocks (no network) |
| `lint-selftest` | Validator + judge-engine unit tests (`unittest`, no network) | Blocks |
| `plugin-validate-cli` | `claude plugin validate --strict`, best-effort | Blocks if the CLI runs and is authenticated; otherwise skips with a message (it is auth-gated on CI) |
| `prompt-judge` | Tier-3 LLM-as-judge | Runs only when `ANTHROPIC_API_KEY` is present; blocks only a *critical* dimension scoring `<= 2` |

The judge runs `run_judge.py --gate --require --votes 3 --model sonnet` and
publishes its report to the job summary. With no Anthropic credential it
**skips with an explicit message** rather than reporting a false green, so a
fork PR without the secret still goes green on the deterministic gates.

### python-quality.yml — Python code quality

The toolkit's Python is held to the conventions of
`VilnaCRM-Org/bootstrap-infrastructure`. Since this repo has no Docker
dev-env, each job installs pinned `uv` (`0.9.21`) and runs the tool via `uvx`:

- `ruff@0.15.6` — lint + `format --check`.
- `ty@0.0.21` — type-check the library (`lint/` + `judge/`); tests excluded.
- `radon@6.0.1` + `xenon@0.9.3` — maintainability report plus a complexity
  gate (`--max-absolute B --max-modules B --max-average A`).
- `bandit[toml]@1.8.6` — security scan.
- `coverage@7.6.7` — branch coverage with `--fail-under=100` (only
  `if __name__ == "__main__"` guards are excluded).

### security-audit-validation.yml — detection-rule proof

Mirrors the same `ruff`/`ty`/`xenon`/`bandit`/100%-coverage matrix for
`tools/security-audit-validation`, and adds two detection lanes:

- `static-detect` — installs pinned `semgrep==1.165.0` and runs
  `detect.py`, asserting a true positive on every vulnerable fixture and a
  true negative on every clean one. CI-gating.
- `seed-judge` — runs `run_seed_judge.py --votes 3`; with no `claude` CLI on
  the runner the lane skips with exit 0 (never a false green). A credentialed
  local run exercises it with `--gate`.

## The bats suites and fixtures

`bats` is the deterministic backbone for the shell scripts under
[scripts/](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/scripts).
Ten suites under
[tests/](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/tests)
hold **239** `@test` cases:

| Suite | Pins | Cases |
| --- | --- | --- |
| `setup-preflight.bats` | `setup-preflight.sh` version/auth checks (Story 2.1, NFR-7, ADR-10) | 19 |
| `generate-profile.bats` | `generate-profile.sh` detection per source (Story 2.2, FR-2) | 24 |
| `inject-governance.bats` | `inject-governance.sh` managed-block idempotency (Story 2.3, NFR-3, ADR-3) | 23 |
| `validate-profile.bats` | `validate-profile.sh` per violation class (Story 1.4, FR-17) | 19 |
| `ai-review-loop.bats` | `ai-review-loop.sh` verdict + iteration logic (Story 2.4, ADR-8, NFR-6) | 23 |
| `get-pr-comments.bats` | `get-pr-comments.sh` GraphQL shaping (Story 2.5, FR-8, ADR-4) | 31 |
| `fr-nfr-gate.bats` | `fr-nfr-gate.sh` gate verdict (Story 2.6, FR-18) | 17 |
| `post-review-findings.bats` | the idempotent per-lens PR comment poster | 41 |
| `common-lib.bats` | every helper in `scripts/lib/common.sh`, incl. the PyYAML fallback (Story 1.3, FR-18) | 28 |
| `component-counts.bats` | the exact 8/7/22 + 2 layout and frontmatter contracts (Story E7-S2, NFR-1) | 14 |

The poster suite ties into [Publishing PR Comments](Publishing-PR-Comments.md);
the review-loop and gate suites underpin
[Review and Quality Gates](Review-and-Quality-Gates.md).

### Fixtures and stubbing

[tests/fixtures](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/tests/fixtures)
makes the gh/claude-dependent paths deterministic:

- `fixtures/bin/{gh,claude,bmalph}` — stub binaries prepended to `PATH`. A
  test drives outcomes via `STUB_*` env vars: `STUB_CLAUDE_VERSION`,
  `STUB_GH_AUTH_EXIT`, `STUB_BMALPH_DOCTOR_EXIT` for preflight;
  `STUB_CLAUDE_OUTPUT` / `STUB_CLAUDE_LOG` / `STUB_CLAUDE_EXIT` to script a
  review verdict (including overload errors) and record each invocation.
- `fixtures/gh/pr-comments.json` (and a truncated variant) — canned GraphQL
  payloads for the comment-fetch path.
- `fixtures/ledgers/*.json` — finding-ledger inputs for the poster (empty,
  full, duplicate pairs, 20-digit counts, secret-laden, …).
- `fixtures/profiles/*.yml` — valid and deliberately-broken profiles
  (`bad-enum`, `lowered-threshold`, `wrong-schema-version`, `missing-key`,
  `incomplete-make`, publish on/off) for the validator.
- `fixtures/stub-repo/` — a minimal PHP repo (composer.json, Makefile, src/
  contexts, workflows, `.coderabbit.yaml`) for profile generation and
  governance injection.

## Testing plans and strategy

[docs/testing/test-strategy.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/testing/test-strategy.md)
defines the QA campaign. It enumerates **9 surfaces** — `scripts-cli`,
`profile-fuzz`, `governance-inject`, `gh-integration`, `review-loop`,
`commands-semantics`, `agents-contracts`, `install-lifecycle`,
`security-adversarial` — each with its primary contract.

Key elements of the strategy:

- **Risk-based prioritization**: a higher class always preempts a lower one —
  Security → Silent failure (exit 0 on broken state) → Contract drift → UX.
- **Severity bands** S1–S4; all S1/S2 block exit, S3 fixed when confirmed
  twice, S4 logged.
- **Environments**: disposable `/tmp/sdlc-test-<surface>/` sandboxes, the
  `STUB_*` stub-binary harness, the real `claude` CLI only for
  install-lifecycle, and a `php-service-template` clone for realistic profile
  and governance runs.
- **Loop protocol**: Test → Judge (reproduce twice) → Fix the shipped
  artifact (never the test expectation) → Regression (add a `bats` test or
  documented repro) → Repeat, until **one full round across all 9 surfaces
  yields zero new confirmed bugs**.

Per-surface plans with executed case tables live under
[docs/testing/plans/](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/testing/plans/scripts-cli.md).
The `security-audit` skill has its own
[strategy](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/testing/security-audit-test-strategy.md),
[plan](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/testing/security-audit-test-plan.md),
and
[cases](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/testing/security-audit-test-cases.md).

## Validation campaigns (docs/evidence)

Recorded outcomes live under
[docs/evidence/](https://github.com/VilnaCRM-Org/claude-plugins/tree/main/plugins/php-backend-sdlc/docs/evidence).

### Adversarial QA campaign

[test-campaign-summary.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/testing/test-campaign-summary.md)
records a subagent-driven loop that confirmed each bug through a
**three-skeptic refuter panel** (majority vote) before any fix, re-ran prior
rounds' repros **live** each round, and fixed at root cause:

| Round | Confirmed bugs | Notes |
| --- | --- | --- |
| 1 | 11 | uint64 threshold/iteration wraps, governance concurrency + CRLF, preflight work-tree, profile parsing, raw tracebacks |
| 2 | 12 | Real governance lockfile, directory/FIFO/read-only refusal, fenced-marker examples, shared helpers |
| 3 | 6 | Command-doc contracts (setup `--refresh`, finish-pr MERGED/CLOSED + BLOCKED escalation, qa degrade, issue dedup) + gh shape guard |
| 4 | 0 | **Convergence** — every prior fix re-run live and held; new probes found nothing |

29 bugs found and fixed across rounds 1–3; round 4 clean. The `bats` count
grew from 0 to **197** during the campaign and has since reached 239. Fixes
never weakened a check to pass a test.

### Other evidence files

- [e2e-feature-ship.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/evidence/e2e-feature-ship.md)
  — a full headless dogfood: `claude -p "/sdlc-setup"` auto-discovered and
  ran the setup scripts, then SETUP → ISSUE → PLAN → IMPLEMENT → REVIEW →
  OPEN-PR → FINISH each reached its exit condition or a documented degrade
  shipping a `Percentage` value object on a disposable `php-service-template`
  clone, with a real issue and PR opened. Zero plugin-flow bugs.
- [security-audit-validation-campaign.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/evidence/security-audit-validation-campaign.md)
  — the security-rule hardening loop (below).
- [qa-install-setup.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/evidence/qa-install-setup.md)
  — install/enable/setup lifecycle evidence.
- [finish-pr-run.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/evidence/finish-pr-run.md)
  and
  [security-audit-dogfood-run.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/evidence/security-audit-dogfood-run.md).

## The tools/ harnesses

The two Python harnesses live at the **repo root** under `tools/` (not in the
plugin tree, so the deliberately-vulnerable fixtures never reach a consumer).

### tools/plugin-quality

The prompt-quality toolkit behind `prompt-quality.yml`:

- `lint/` — Tier-1 static validators, one `check_*.py` per family
  (frontmatter, naming, descriptions, structure, references, escalation,
  generalization, manifest, metaguides), aggregated by `lint_all.py`. The
  check matrix (L0–L33, M1–M5, J1–J11) is pinned in
  [docs/test-plan.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/tools/plugin-quality/docs/test-plan.md)
  with each row mapped to an FR/NFR. Examples: `MAX_ITERATIONS=5` in iteration
  guards (ES-1), the `=== SDLC ESCALATION ===` field set (ES-2), and a
  `qa`-named command/agent never listing `Write`/`Edit` (L33/FM-6).
- `judge/` — Tier-3 LLM-as-judge: `rubrics.py` (dimensions J1–J11),
  `judge.py` (engine), `cache.py` (content-addressed verdict cache),
  `run_judge.py` (CLI). A critical dimension blocks only at score `<= 2`.
- `tests/` — stdlib `unittest` suite, **465** tests, exercising the
  validators and the claude-free judge engine; 100% branch coverage.
- Dependencies are bare `python3` (>= 3.10) plus PyYAML; only the judge needs
  the `claude` CLI and credentials. `run.sh` runs lint + self-tests (+ judge
  if creds present).

### tools/security-audit-validation

Proves the `security-audit` skill and `security-auditor` agent (see
[Security Audit](Security-Audit.md)) detect what they claim. Two lanes:

- **Static lane** — `detect.py` runs the real `semgrep` engine over the
  fixture corpus using the local rule pack `rules/security-audit.yml`,
  asserting a true positive per vulnerable fixture and a strict true negative
  per clean one (plus an FR-7 in-tree dependency check). Deterministic and
  CI-gating; it invokes semgrep with `-j 1` to avoid an `io_uring` startup
  failure on low-`RLIMIT_MEMLOCK` hosts, and exits 2 if semgrep is
  unavailable.
- **Judge lane** — `judge/run_seed_judge.py` asks `claude -p --model sonnet`,
  under the `security-auditor` verdict contract, to classify each fixture,
  covering the logic families (BOLA/IDOR, BFLA, BOPLA, auth, rate) that no
  static rule can reach. Skip-clean without the CLI.

`corpus/` holds **17 families** of PHP fixtures (`vulnerable.php` /
`clean.php` / `edge_*.php` triads) plus two `composer.json` dependency
fixtures; `corpus.py` is the manifest mapping each fixture to its expected
static and judge verdict. The harness `tests/` is a 66-test `unittest` suite
at 100% coverage.

The detection-hardening campaign
([security-audit-validation-campaign.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/evidence/security-audit-validation-campaign.md))
ran three adversarial rounds — a Workflow fanned out one red-team author
subagent per family to generate fixtures designed to evade the current rules,
and `semgrep` arbitrated each deterministically:

| Round | Outcome |
| --- | --- |
| 0 | Hand-authored baseline: static lane passes (45 TP/TN + 2 dependency) |
| 1 | 44 adversarial fixtures → 9 soundly-fixable static gaps fixed; static lane grows to **60/60** |
| 2 | 44 more → 13 gaps fixed; static lane **73/73** |
| 3 | 44 more → 8 gaps fixed; static lane **81/81** |

Across the three rounds ~43 distinct sound rule improvements drove the static
lane from 47 to **81/81** assertions. Residual misses fall into stable
blind-spot classes (interprocedural flow, dynamic dispatch, output-context
sensitivity) carried as `JL-*` judge-lane fixtures — a documented division of
labour between the deterministic static lane and the reasoning judge lane, not
a coverage gap. Re-running the loop is the maintenance path: any new sound
sink is a one-line rule addition plus a regression fixture.

## See also

- [Review and Quality Gates](Review-and-Quality-Gates.md)
- [Security Audit](Security-Audit.md)
- [Publishing PR Comments](Publishing-PR-Comments.md)
- [Contributing and Releases](Contributing-and-Releases.md)
- [Degrade and Resilience](Degrade-and-Resilience.md)
