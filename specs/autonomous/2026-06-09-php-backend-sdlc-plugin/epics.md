---
stepsCompleted: [step-01-validate-prerequisites, step-02-design-epics, step-03-create-stories, step-04-final-validation]
inputDocuments:
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/architecture.md
workflowType: 'epics-stories'
date: 2026-06-10
author: BMAD PM/SM agents (autonomous run — interactive steps skipped, decisions recorded inline)
---

# Epics & Stories — `php-backend-sdlc` Claude Code Plugin

7 epics, 52 stories. Dependency order: **E1 → E2 → (E3 ∥ E4 ∥ E5) → E6 → E7**.
All paths relative to repo root; plugin root = `plugins/php-backend-sdlc/`. Sizes: S (≤1h focused agent run), M (1–3h), L (3h+ or evidence run). Execution mode: **PARALLEL** = disjoint file set, fan out to a subagent; **SEQUENTIAL** = must wait for listed deps.

---

## Epic E1 — Foundation: repo CI, scripts lib, profile schema & validator

Establishes the plugin skeleton, the shared bash library, the canonical profile schema (ADR-2), and the repo CI that every later story must pass. Nothing in E2–E7 merges without E1's checks existing.

### E1-S1 — Plugin scaffold and manifests (S, PARALLEL)
**Description:** Validate/extend the existing scaffold — `marketplace.json` and `plugin.json` already exist in the repo (research §2) — per architecture §1.1/§6: `plugin.json` (name `php-backend-sdlc`, semver `0.1.0`, description, author, homepage, repository, license, keywords) and marketplace entry with relative `source: ./plugins/php-backend-sdlc` (ADR-9). Complete empty component dirs (`commands/`, `agents/`, `skills/`, `scripts/`, `tests/`, `docs/`) with `.gitkeep` where needed.
**AC:** Both manifests parse with `jq`; required fields present; name matches dir (FR-19). `claude plugin install php-backend-sdlc@vilnacrm-plugins` resolves the relative source locally (FR-19 AC, partial — full install test in E7-S5).
**Deps:** none.
**Files:** `plugins/php-backend-sdlc/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`.

### E1-S2 — Repo CI workflow with all seven jobs (M, PARALLEL)
**Description:** Single workflow, parallel jobs per architecture §6: `manifest-validate` (jq), `markdown-lint` (markdownlint-cli2), `shellcheck`, `bats`, `frontmatter-check` (bash+yq: commands need `description`+`argument-hint`; agents need `name`+`description`+`tools`+`model`; skills need `name`+`description`; skill glob is `skills/*/SKILL.md` only — loose meta-guides at `skills/` root are exempt and must NOT have frontmatter, ADR-11), `profile-keys-check` (bash+grep: greps each skill's `## Profile keys consumed` header against the canonical schema keys in `plugins/php-backend-sdlc/docs/profile-schema.md`; any undeclared key = fail, FR-17 AC), `generalization-audit` (NFR-2 denylist grep, case-insensitive: `VilnaCRM` outside manifests, `user-service`, `Mongo[A-Z]\w*Repository`, `AppRunner`, `src/User`, `src/OAuth`, workspace.dsl container names; `# profile-example` fenced blocks excluded by marker; plus NFR-7 check: no `_bmad/`/`.ralph/` files in plugin tree). Exact-count assertion (8/6/21) deferred to `component-counts.bats` (E7-S2).
**AC:** All seven jobs run on PR and pass on the E1 tree (FR-20). Seeding `VilnaCRM` into a SKILL.md body fails `generalization-audit` (FR-20 AC, NFR-2). Seeding an undeclared key into a skill's `## Profile keys consumed` header fails `profile-keys-check` (FR-17 AC). Adding a stub `_bmad/x` under the plugin tree fails the NFR-7 check.
**Deps:** E1-S1, E1-S5 (`profile-keys-check` reads `docs/profile-schema.md` as the canonical key list).
**Files:** `.github/workflows/ci.yml` (`profile-keys-check` consumes `plugins/php-backend-sdlc/docs/profile-schema.md`).

### E1-S3 — Scripts library and test fixtures (M, PARALLEL)
**Description:** `lib/common.sh`: logging helpers, profile read helpers, yq→`python3 -c 'import yaml…'` fallback resolution (ADR-2), `${CLAUDE_PLUGIN_ROOT}` resolution guard, `set -euo pipefail` conventions. Fixtures: stub target repo (composer.json, Makefile, `src/` layout, `.github/workflows/`), stub `claude`/`gh`/`bmalph` binaries (configurable version output / exit codes), sample valid+invalid profiles.
**AC:** `common.sh` shellcheck-clean; a bats smoke test sources it and exercises each helper, including the yq-absent→python fallback path (FR-18 toolchain prerequisite). Fixtures usable by every later `.bats` suite.
**Deps:** none (E1-S1 for dir layout only).
**Files:** `plugins/php-backend-sdlc/scripts/lib/common.sh`, `tests/fixtures/**` (stub repo, stub binaries, sample profiles), `tests/common-lib.bats`.

### E1-S4 — `validate-profile.sh` + bats (M, SEQUENTIAL after E1-S3)
**Description:** Implement schema validation per architecture §4/ADR-2: required keys (`schema_version`, `project.*`, `php.version`, `framework.name`, `persistence.*`, `architecture.source_root`+`bounded_contexts`, `make` map complete, `quality`, `ci.provider`), enum legality (`mapper`, `engine`), quality values ≥ shipped defaults (100/100/100/94, 0, 0, 100 — never lower, ADR-7), `schema_version == 1`. Exit 0/1, line-per-violation output.
**AC:** Validates the canonical user-service example profile (exit 0); each violation class (missing key, bad enum, lowered threshold, wrong schema_version, incomplete make map) produces exit 1 with a named violation line, each covered by a bats case (FR-17, FR-18 quality bar: shellcheck-clean, bats-covered).
**Deps:** E1-S3.
**Files:** `plugins/php-backend-sdlc/scripts/validate-profile.sh`, `tests/validate-profile.bats`.

### E1-S5 — Profile schema reference doc (S, PARALLEL)
**Description:** Write `docs/profile-schema.md`: every FR-17 key with required/optional marking, defaults, enums, the raise-only quality rule, `make.<key>: null` = capability-absent semantics (NFR-4), and the annotated user-service example inside a `# profile-example` fenced block. This doc is the canonical list the FR-17 CI doc-check greps skills' "Profile keys consumed" headers against.
**AC:** Every key from architecture §4 documented (FR-17 AC); markdownlint passes; example block carries the `# profile-example` marker so the NFR-2 audit excludes it (NFR-8 partial).
**Deps:** none.
**Files:** `plugins/php-backend-sdlc/docs/profile-schema.md`.

---

## Epic E2 — Setup command + shipped scripts

All seven plugin scripts (setup trio + review trio + the setup command). E2-S1…S6 are PARALLEL (disjoint script+bats pairs); E2-S7 is SEQUENTIAL last.

### E2-S1 — `setup-preflight.sh` + bats (M, PARALLEL)
**Description:** Version floors `bmalph ≥ 2.11.0`, `claude ≥ 2.1`, `gh ≥ 2` (NFR-7, ADR-10); `gh auth status`; git repo check; yq-or-python3-yaml presence check. `--report` prints PASS/FAIL table with named remediation per failure; exit non-zero on first FAIL.
**AC:** Against under-version stub binaries (fixtures), aborts with the correct named remediation message (NFR-7 AC); all-pass fixture yields full PASS table; every check has a bats case (FR-2 preflight, FR-18 quality bar).
**Deps:** E1-S3.
**Files:** `plugins/php-backend-sdlc/scripts/setup-preflight.sh`, `tests/setup-preflight.bats`.

### E2-S2 — `generate-profile.sh` + bats (L, PARALLEL)
**Description:** Detection per FR-2: composer.json (PHP version, framework, API Platform/GraphQL), Doctrine config (ORM vs ODM + engine), Makefile scan (logical→actual target map), `src/` layout (bounded contexts, shared context), `.github/workflows/` (CI names), `.coderabbit.yaml`. Missing capabilities → `null`/`false`, never errors (A3). Default mode prints diff vs existing profile and keeps it; `--refresh` overwrites (NFR-3).
**AC:** On the fixture stub repo, output validates via `validate-profile.sh` exit 0 (FR-17); stripped-Makefile fixture yields `make.<key>: null` entries without failure (NFR-4); second run without `--refresh` leaves file untouched and prints diff (NFR-3); bats covers each detection source and both modes (FR-2).
**Deps:** E1-S3, E1-S4.
**Files:** `plugins/php-backend-sdlc/scripts/generate-profile.sh`, `tests/generate-profile.bats`.

### E2-S3 — `inject-governance.sh` + bats (M, PARALLEL)
**Description:** Replace-in-place delimited managed blocks `<!-- php-backend-sdlc:begin -->`…`<!-- php-backend-sdlc:end -->` in target `CLAUDE.md`/`AGENTS.md` (ADR-3) carrying skill-triage gate, profile-referenced protected thresholds, container-only rule. Duplicate-marker repair to a single block; `--diff` preview; never touches content outside its block.
**AC:** Two consecutive runs → `git diff` empty on second (NFR-3 AC); corrupted/duplicated-marker fixture repaired to exactly one block (NFR-3 AC); pre-existing user content byte-identical outside markers (FR-2 governance); bats-covered, shellcheck-clean (FR-18 quality bar).
**Deps:** E1-S3.
**Files:** `plugins/php-backend-sdlc/scripts/inject-governance.sh`, `tests/inject-governance.bats`.

### E2-S4 — `ai-review-loop.sh` (claude driver) + bats (L, PARALLEL)
**Description:** Generalized review loop per ADR-8: per agent in `review.ai_review_agents` run `claude -p "$REVIEW_PROMPT" --output-format json --permission-mode acceptEdits --max-turns 30`, extract `.result` via jq, parse mandatory last-line `AI_REVIEW_VERDICT: PASS|FAIL`; loop until PASS or max iterations. Flags `--agents`, `--max-iterations` (default 5), `--diff-base`. Non-claude agent → warn+skip (v1 matrix). Malformed JSON / non-zero exit → retry once then count as failed iteration (architecture §8).
**AC:** Completes with only the stub `claude` CLI present (FR-18 AC); FAIL-then-PASS stub sequence exits after 2 iterations; perpetual-FAIL stub stops at 5 (NFR-6); `--agents codex` warns and skips; malformed-JSON stub takes exactly one retry; all paths bats-covered.
**Deps:** E1-S3.
**Files:** `plugins/php-backend-sdlc/scripts/ai-review-loop.sh`, `tests/ai-review-loop.bats`.

### E2-S5 — `get-pr-comments.sh` + bats (M, PARALLEL)
**Description:** gh GraphQL `reviewThreads(first:100){isResolved, comments…}` + issue comments, resolution-aware. Flags `--pr <n>`, `--unresolved-only`, `--json`.
**AC:** Against stub `gh` returning fixture GraphQL payloads: full listing, unresolved-only filtering, and JSON output each verified by bats (FR-18); runs purely from install cache paths via `${CLAUDE_PLUGIN_ROOT}` (ADR-4).
**Deps:** E1-S3.
**Files:** `plugins/php-backend-sdlc/scripts/get-pr-comments.sh`, `tests/get-pr-comments.bats`.

### E2-S6 — `fr-nfr-gate.sh` + bats (M, PARALLEL)
**Description:** Run FR/NFR verification prompt against `specs/` + diff; post PR comment and `BMAD FR/NFR Review Gate` commit status via `gh`. Flags `--spec-path`, `--impact-context`; exit 0 = zero new findings.
**AC:** Stub-driven bats verify: zero-findings run exits 0 and posts success status; findings run exits 1 with comment body containing the findings; both gh calls assert correct status context name (FR-18, feeds FR-6/FR-11).
**Deps:** E1-S3.
**Files:** `plugins/php-backend-sdlc/scripts/fr-nfr-gate.sh`, `tests/fr-nfr-gate.bats`.

### E2-S7 — `/sdlc-setup` command (M, SEQUENTIAL after E2-S1, E2-S2, E2-S3; refs E1-S4)
**Description:** Markdown command per architecture §2 stage contract (Inputs / Procedure / Loop & exit condition / Iteration guard / Failure escalation). Sequence: preflight (abort on FAIL) → fresh-repo `bmalph init` bootstrap when `_bmad/` absent, surfacing failures (A2) → `generate-profile.sh` → `validate-profile.sh` → `inject-governance.sh` → write/document `.claude/settings.json` allowlist for `acceptEdits` (ADR-6; `bypassPermissions` documented Ralph-only) → diff summary.
**AC:** Frontmatter has `description`+`argument-hint` (passes frontmatter-check); body invokes all four scripts via `${CLAUDE_PLUGIN_ROOT}` with documented abort-on-FAIL semantics (FR-2); idempotency statement matches NFR-3 (re-run = no-op outside managed artifacts, profile regenerated only with `--refresh`); the ≤30-min fresh-clone walkthrough AC is evidenced in E7-S3/E7-S4 (G1).
**Deps:** E2-S1, E2-S2, E2-S3, E1-S4.
**Files:** `plugins/php-backend-sdlc/commands/sdlc-setup.md`.

---

## Epic E3 — Skills generalization wave 1: 11 light-edit skills

**Common contract (applies to every E3 story, all FR-15):** keep verified format (frontmatter `name`+`description` with "Use when…" trigger phrasing + Context/Task/Success-Criteria/Steps/Constraints/Verification); add `## Profile keys consumed` header listing only keys present in `docs/profile-schema.md`; map all `make` references through `make.*`; thresholds via `quality.*` keys (complexity 94, MSI 100 canonical, A1/ADR-7); user-service literals only inside `# profile-example` fenced blocks; relative cross-links to sibling skills only.
**Common AC:** loads as `php-backend-sdlc:<skill>`; passes `generalization-audit`, `markdown-lint`, `frontmatter-check` (NFR-2); profile-keys header greps clean against schema (FR-17 AC); cross-links resolve within `skills/` (FR-15 AC).
**Deps (all):** E1-S2, E1-S5. **All 11 stories PARALLEL — fully disjoint file sets.**

| Story | Skill (dir under `plugins/php-backend-sdlc/skills/`) | Size | Story-specific AC on top of common |
|---|---|---|---|
| E3-S1 | `code-review/SKILL.md` | S | `make` map + `quality.*` threshold refs only; no repo-literal paths |
| E3-S2 | `ci-workflow/SKILL.md` | S | the legacy 93% complexity literal corrected to profile-keyed 94 default (ADR-7) |
| E3-S3 | `complexity-management/SKILL.md` | S | PHPInsights thresholds read from `quality.phpinsights.*`; raise-only rule stated |
| E3-S4 | `quality-standards/SKILL.md` | S | quick-reference table cites profile keys, not literals; links to sibling skills resolve |
| E3-S5 | `testing-workflow/SKILL.md` | S | `make.tests`/`make.e2e`/`make.infection` mapping; MSI via `quality.infection_msi` |
| E3-S6 | `bmad-fr-nfr-review-gate/SKILL.md` | S | invokes `${CLAUDE_PLUGIN_ROOT}/scripts/fr-nfr-gate.sh`, no repo-local make target assumed (FR-18 link); `make.fr_nfr_gate: null` → shipped script (NFR-4) |
| E3-S7 | `documentation-sync/SKILL.md` | S | naming/link hygiene only; zero denylist hits |
| E3-S8 | `clean-architecture-llm/SKILL.md` | S | naming/link hygiene only; zero denylist hits |
| E3-S9 | `bmad-autonomous-planning/SKILL.md` | S | naming/link hygiene; consumable by `/sdlc-plan` (loaded directly per §1.2 dependency rules) |
| E3-S10 | `query-performance-analysis/SKILL.md` | S | branches MySQL/MariaDB `EXPLAIN` vs MongoDB `explain()` on `persistence.engine`; both branches present |
| E3-S11 | `load-testing/SKILL.md` + `load-testing/reference/` | M | gated on `capabilities.load_testing` (skip-with-note when false, NFR-4); K6 endpoints/config profile-keyed; carried-over `reference/` files generalized |

E3-S6 additionally lists `make.fr_nfr_gate` in its profile-keys header (Deps: + E2-S6 interface).

---

## Epic E4 — Skills generalization wave 2: 6 moderate + 4 deep rewrites + meta-guides

**Common contract and common AC identical to E3.** Deep-rewrite stories must additionally name every consumed profile key explicitly in the body where behavior branches (FR-15 AC). **Deps (all):** E1-S2, E1-S5. **All 11 stories PARALLEL — fully disjoint file sets.** E4 runs in parallel with E3 and E5.

| Story | Skill | Size | Story-specific AC on top of common |
|---|---|---|---|
| E4-S1 | `openapi-development/SKILL.md` | M | OpenAPI layer path derived from `architecture.source_root`+`architecture.shared_context` (no `src/Shared/Application/OpenApi` literal) |
| E4-S2 | `api-platform-crud/SKILL.md` | M | context/path/make refs via profile; API Platform version branch on `framework.api_platform`; skip-note when `false` |
| E4-S3 | `implementing-ddd-architecture/SKILL.md` + `REFERENCE.md` | M | "Doctrine ORM with MySQL for this service" drift removed; examples branch on `persistence.mapper`/`engine`; REFERENCE.md generalized |
| E4-S4 | `database-migrations/SKILL.md` | M | frontmatter + body parameterized on `persistence.mapper` (ORM migrations vs ODM schema management); both paths documented |
| E4-S5 | `deptrac-fixer/SKILL.md` | M | layer names/paths from `architecture.*`; "never edit deptrac.yaml" rule preserved verbatim |
| E4-S6 | `documentation-creation/SKILL.md` | M | project naming/structure/doc targets from `project.*`+`architecture.*` |
| E4-S7 | `observability-instrumentation/SKILL.md` | L | AWS EMF/AppRunner content gated behind `capabilities.observability_emf`; generic business-metric guidance branch when `false`; zero `AppRunner` hits outside profile-example blocks |
| E4-S8 | `code-organization/SKILL.md` + `DIRECTORY-STRUCTURE.md` | L | bounded contexts/source paths from `architecture.*`; "directory X contains only type X" law stack-generic; zero `src/User`/`src/OAuth` hits |
| E4-S9 | `structurizr-architecture-sync/SKILL.md` | L | gated on `capabilities.structurizr` (skip-with-note when false, NFR-4); container/system names profile-derived, zero workspace.dsl VilnaCRM container names |
| E4-S10 | `cache-management/SKILL.md` + `examples/` | L | repository naming derived from `persistence.mapper`/`engine` (`Cached*Repository` wrapping persistence-specific repo); zero `Mongo[A-Z]\w*Repository` hits; examples generalized |
| E4-S11 | `SKILL-DECISION-GUIDE.md` + `AI-AGENT-GUIDE.md` (loose files at `skills/` root, ADR-11) | M | FR-16: triage decision tree lists all 21 skills; rule "every skill verdict recorded, no silent skips" stated verbatim (NFR-5 policy source); no frontmatter (must NOT be discovered as skills); existing `../` relative links survive install cache |

---

## Epic E5 — Subagents (6)

**Common contract (FR-9..14 AC):** agent frontmatter `name`/`description` (trigger-rich router text)/`tools` (comma-list)/`model` per architecture §3 matrix; body contains all six sections — Role, Inputs, Outputs, Allowed actions, Degrade paths, Iteration discipline (own counter ≤5 + §2 escalation block format, NFR-6).
**Common AC:** loads in `claude` agent listing; passes `frontmatter-check` + `generalization-audit`; six sections present (FR-9..14 AC); smoke prompt documented for happy path + one degrade path where defined.
**Deps (all):** E1-S2, E1-S5; script interfaces from E2 as noted. **All 6 stories PARALLEL — one file each.** E5 runs in parallel with E3 and E4.

| Story | Agent file (under `plugins/php-backend-sdlc/agents/`) | model / tools | Size | Story-specific AC |
|---|---|---|---|---|
| E5-S1 | `php-implementer.md` | sonnet / Read, Write, Edit, Glob, Grep, Bash | L | FR-9: container-only execution (`make`/`docker compose exec php`); root-cause culture (no suppressions/threshold edits); emits `---RALPH_STATUS---`-compatible status block with EXIT_SIGNAL |
| E5-S2 | `code-quality-reviewer.md` | opus / Read, Glob, Grep, Bash | M | FR-10: read-only quality `make` targets; findings as file:line+severity+root-cause fix; per-threshold PASS/FAIL vs `quality.*`; never proposes suppressions/threshold cuts |
| E5-S3 | `fr-nfr-reviewer.md` | opus / Read, Glob, Grep, Bash | M | FR-11: runs `${CLAUDE_PLUGIN_ROOT}/scripts/fr-nfr-gate.sh`; per-requirement PASS/FAIL matrix; tracks new-findings count per iteration (Deps: + E2-S6) |
| E5-S4 | `qa-manual-tester.md` | sonnet / Bash, Read (logs/specs only) | M | FR-12: verdicts from HTTP behavior only; source-reading forbidden in prompt AND tool surface (no Edit/Write); reproduction steps per failure |
| E5-S5 | `ci-fixer.md` | sonnet / Bash, Read, Edit, Glob, Grep | M | FR-13: `gh run/checks` polling; root-cause fixes only; per-iteration check-status table; degrade: no checks configured → report-and-skip (NFR-4) |
| E5-S6 | `pr-comment-resolver.md` | sonnet / Bash, Read, Edit, Glob, Grep | M | FR-14: `get-pr-comments.sh` is the source of truth (Deps: + E2-S5); fix or reasoned reply, never silent dismissal; degrade: no reviewer app → `ai-review-loop.sh` findings as source (Deps: + E2-S4, NFR-4) |

---

## Epic E6 — SDLC commands (7 remaining; orchestrator last)

**Common contract:** every command implements the architecture §2 stage contract — Inputs (first action `validate-profile.sh`), Procedure (explicit agent/skill/script delegation), Loop & exit condition (the single measurable condition from FR-1's stage table), Iteration guard (`MAX_ITERATIONS=5`, counter restated each turn), Failure escalation (canonical `=== SDLC ESCALATION ===` block, NFR-6).
**Common AC:** frontmatter `description`+`argument-hint` (+ `allowed-tools` only where §2 mandates); passes frontmatter-check/markdownlint/generalization-audit; all five contract sections present; exit condition matches FR-1 stage table verbatim.
**Deps (all):** E2 complete, E3+E4+E5 complete (commands reference agents/skills by final name). **E6-S1…S6 PARALLEL (disjoint files); E6-S7 SEQUENTIAL last.**

### E6-S1 — `/sdlc-issue` (S, PARALLEL)
**Description/AC:** FR-3 — task text → `gh issue create` with title, problem statement, ≥3 testable AC bullets, scope notes, plugin marker label; outputs issue URL; issue-URL argument → validate and adopt, no duplicate. AC: dry-run walk-through shows both input modes and URL output consumed by `/sdlc-plan` (FR-3 AC).
**Files:** `plugins/php-backend-sdlc/commands/sdlc-issue.md`.

### E6-S2 — `/sdlc-plan` (M, PARALLEL)
**Description/AC:** FR-4 — non-interactive BMAD chain via direct load of `bmad-autonomous-planning` skill (§1.2 edge); writes six artifacts under `specs/<slug>/`; assumptions inline; loop ≤5 until readiness PASS then escalate. AC: procedure names the skill, lists all six artifacts, zero interactive prompts mandated (FR-4 AC).
**Files:** `plugins/php-backend-sdlc/commands/sdlc-plan.md`.

### E6-S3 — `/sdlc-implement` (L, PARALLEL)
**Description/AC:** FR-5 — `bmalph implement` → `bmalph run --driver claude-code` (never Codex); independent stories fan out to parallel `php-implementer` subagents, dependent stories sequential per epics artifact; honors `.ralphrc` circuit breaker (no-progress 3, same-error 5, output-decline 70%) — trip → stop+report, never reset (NFR-6); container-only execution via profile `make` map. AC: body asserts driver `claude-code`, parallel-dispatch rule, breaker-trip → ESCALATED report path (FR-5 AC).
**Files:** `plugins/php-backend-sdlc/commands/sdlc-implement.md`.

### E6-S4 — `/sdlc-review` (L, PARALLEL)
**Description/AC:** FR-6 — applicability triage over all 21 skills (EXECUTE+evidence or NOT-APPLICABLE+reason; verdicts from frontmatter+decision guide only, full bodies loaded only on EXECUTE — NFR-5/ADR-5); multi-lens `code-quality-reviewer` + `fr-nfr-reviewer`; gate loop via `fr-nfr-gate.sh` until zero new findings, ≤5 iterations. `allowed-tools` excludes Write (§2). AC: report template includes 21/21 verdicts, both reviewer outputs, per-iteration finding counts, threshold checks referencing profile values (FR-6 AC, NFR-5 AC).
**Files:** `plugins/php-backend-sdlc/commands/sdlc-review.md`.

### E6-S5 — `/sdlc-qa` (M, PARALLEL)
**Description/AC:** FR-7 — `qa-manual-tester` black-box run: `make.start` service, HTTP-only checks vs issue/PRD AC, positive/negative/edge coverage, PASS/FAIL report with reproduction steps; FAIL routes back to `/sdlc-implement` with report attached. `allowed-tools` excludes Edit/Write (§2 black-box rule). AC: report template maps every AC → ≥1 executed check with observed-vs-expected (FR-7 AC).
**Files:** `plugins/php-backend-sdlc/commands/sdlc-qa.md`.

### E6-S6 — `/sdlc-finish-pr` (L, PARALLEL)
**Description/AC:** FR-8 — `gh pr create/edit` with spec-linked description; `ci-fixer` loop ≤5 until checks green; `pr-comment-resolver` loop ≤5 until 0 unresolved (via `get-pr-comments.sh`); degrades: no CI checks → skip-with-report; no reviewer app → `ai-review-loop.sh` as comment source (NFR-4). AC: body documents both loops with separate counters, both degrade paths with SUCCESS-WITH-REPORT status (FR-8 AC, NFR-4 AC).
**Files:** `plugins/php-backend-sdlc/commands/sdlc-finish-pr.md`.

### E6-S7 — `/sdlc` end-to-end orchestrator (L, SEQUENTIAL after E6-S1…S6)
**Description/AC:** FR-1 — full 7-stage table (setup-check…finish-pr) with gated transitions, exit conditions, and per-stage 5-iteration guards; resumability via artifact→stage detection table; never auto-generates profile (halt → "run /sdlc-setup"); never resets Ralph breaker; final structured run report SUCCESS|ESCALATED; QA-FAIL loop-back to stage 3 consumes stage budget. AC: dry-run prompt walk-through shows all 7 stages, every gate condition, both exit paths, guard counters (FR-1 AC, NFR-6).
**Deps:** E6-S1…S6, E2-S7.
**Files:** `plugins/php-backend-sdlc/commands/sdlc.md`.

---

## Epic E7 — Docs, QA evidence, release readiness

### E7-S1 — User docs suite + README (M, PARALLEL within E7)
**Description:** NFR-8 set: `README.md` (marketplace add + install + quickstart), `docs/sdlc-loop.md` (stage diagram, exit conditions, guards — architecture §7), `docs/permissions.md` (acceptEdits default, bypassPermissions Ralph-only, settings.json allowlist — ADR-6), `docs/degrade-matrix.md` (architecture §8 rendered), `docs/release-process.md` (ADR-9 tagging/semver/changelog, git-subdir pin policy).
**AC:** Every FR-17 key reachable from docs (cross-link to profile-schema.md); markdownlint passes; degrade matrix covers all 8 §8 rows; release doc states tag format `php-backend-sdlc-vX.Y.Z` and pin trigger (NFR-8 AC, FR-19).
**Deps:** E6 complete.
**Files:** `plugins/php-backend-sdlc/README.md`, `docs/sdlc-loop.md`, `docs/permissions.md`, `docs/degrade-matrix.md`, `docs/release-process.md`.

### E7-S2 — Component-count + load-integrity tests (S, PARALLEL within E7)
**Description:** `component-counts.bats` asserting exactly 8 commands / 6 agents / 21 skills + 2 loose meta-guides in the install cache layout; wire into the existing CI `bats` job as required.
**AC:** Test passes on the complete tree and fails when any component file is removed/added (NFR-1 AC); `claude plugin` listing smoke documented (NFR-1).
**Deps:** E2-S7, E3, E4, E5, E6 complete.
**Files:** `plugins/php-backend-sdlc/tests/component-counts.bats`.

### E7-S3 — G3 reference evidence run (L, SEQUENTIAL after E7-S1, E7-S2)
**Description:** Execute the full `/sdlc` reference task — pinned (resolves brief OQ-2, PRD §8.4): a small CRUD resource (e.g. `Currency`: code+name fields, REST CRUD endpoints) on a fresh `php-service-template` clone, chosen so BMAD planning yields ≥2 independent stories for FR-5 parallel dispatch — issue→plan→implement→review→qa→finish-pr with 0 human interventions; capture run log as evidence doc, including fresh-clone `/sdlc-setup` ≤30 min (excl. image pulls, A5).
**AC:** Evidence doc shows all 7 stages with met exit conditions, issue URL, specs chain, PR URL, green CI, 0 unresolved comments (FR-1 AC, G3); setup timing recorded (FR-2 AC, G1); plan stage demonstrably yields ≥2 independent stories dispatched in parallel (FR-5 AC).
**Deps:** E7-S1, E7-S2.
**Files:** `plugins/php-backend-sdlc/docs/evidence/g3-reference-run.md`.

### E7-S4 — NFR + FR demonstration evidence runs: degrade, triage, loop safety, QA/finish-pr (L, SEQUENTIAL after E7-S2; PARALLEL with E7-S3)
**Description:** Three simulated environments (no reviewer app, stripped Makefile, no workflows) each completing with explicit degrade note + SUCCESS-WITH-REPORT (NFR-4 AC); docs-only change run showing ≤8 full skill-body loads with 21/21 verdicts (NFR-5 AC); forced-failure tests on review and finish-pr loops stopping at iteration 5 with the escalation report + breaker-trip no-restart simulation (NFR-6 AC). Plus two FR demonstration runs (PRD §4 release-gate item 1): (a) FR-7 seeded-defect QA run — introduce a deliberate defect; `qa-manual-tester` must emit FAIL with reproduction steps; (b) FR-8 finish-pr run — a PR with ≥1 failing check and ≥1 AI reviewer comment driven to all checks green + 0 unresolved comments. Results appended to the evidence doc.
**AC:** All three NFR AC blocks evidenced with logs; each maps to its NFR ID explicitly. FR-7 seeded-defect run evidenced: QA verdict FAIL with reproduction steps per failure (FR-7 AC). FR-8 run evidenced: starting state ≥1 failing check + ≥1 AI reviewer comment, ending state all checks green + 0 unresolved (FR-8 AC). Permission-denial behavior captured: one run with default `acceptEdits` documenting any permission prompts encountered (and their handling per architecture §8 / docs/permissions.md) — closes the brief §8 "permission denials stall unattended runs" risk with evidence, not docs-only.
**Deps:** E7-S2.
**Files:** `plugins/php-backend-sdlc/docs/evidence/g3-reference-run.md` (NFR appendix sections).

### E7-S5 — Release gate: traceability + clean install + version (M, SEQUENTIAL last)
**Description:** Verify PRD §4 release gate: all FR/NFR ACs demonstrated or CI-automated; coverage table below re-checked against implemented stories; `claude plugin install php-backend-sdlc@vilnacrm-plugins` from a clean machine profile (FR-19 AC); `plugin.json` version bumped; changelog entry appended.
**AC:** Install succeeds from clean profile with 8/6/21 discovery (FR-19, NFR-1); all seven CI jobs green on the release PR (FR-20, G6); no orphan requirement in the matrix (PRD §4.4).
**Deps:** E7-S1…S4.
**Files:** `plugins/php-backend-sdlc/.claude-plugin/plugin.json` (version), `docs/release-process.md` (changelog).

---

## Parallelization plan (implementation fan-out)

| Wave | Stories | Mode |
|---|---|---|
| 1 | E1-S1, E1-S3, E1-S5 | PARALLEL (3 agents) |
| 2 | E1-S2, E1-S4 | PARALLEL (2 agents, after wave 1) |
| 3 | E2-S1…E2-S6 | PARALLEL (6 agents) |
| 4 | E2-S7 | SEQUENTIAL |
| 5 | E3-S1…S11 ∥ E4-S1…S11 ∥ E5-S1…S6 | PARALLEL (up to 28 agents — fully disjoint file sets) |
| 6 | E6-S1…E6-S6 | PARALLEL (6 agents) |
| 7 | E6-S7 | SEQUENTIAL |
| 8 | E7-S1, E7-S2 | PARALLEL (2 agents) |
| 9 | E7-S3 ∥ E7-S4 | PARALLEL (2 agents; both touch the evidence doc — S4 appends appendix sections only) |
| 10 | E7-S5 | SEQUENTIAL (release gate) |

39 of 52 stories are parallel-safe. The only shared-file risk is wave 9 (single evidence doc) — mitigated by section ownership (S3 = main run log, S4 = NFR appendices); serialize if the implementer prefers zero merge risk.

## Coverage table — FR/NFR → stories

| Req | Stories | | Req | Stories |
|---|---|---|---|---|
| FR-1 | E6-S7, E7-S3 | | FR-15 | E3-S1…S11, E4-S1…S10 |
| FR-2 | E2-S1, E2-S2, E2-S3, E2-S7, E7-S3 | | FR-16 | E4-S11 |
| FR-3 | E6-S1 | | FR-17 | E1-S2, E1-S4, E1-S5, E2-S2 |
| FR-4 | E6-S2 | | FR-18 | E2-S4, E2-S5, E2-S6 |
| FR-5 | E6-S3, E7-S3 | | FR-19 | E1-S1, E7-S1, E7-S5 |
| FR-6 | E6-S4 | | FR-20 | E1-S2, E7-S5 |
| FR-7 | E6-S5, E7-S4 | | NFR-1 | E7-S2, E7-S5 |
| FR-8 | E6-S6, E7-S4 | | NFR-2 | E1-S2 + every E3/E4/E5/E6 story (common AC) |
| FR-9 | E5-S1 | | NFR-3 | E2-S2, E2-S3, E2-S7 |
| FR-10 | E5-S2 | | NFR-4 | E2-S2, E3-S6, E3-S11, E4-S9, E5-S5, E5-S6, E6-S6, E7-S4 |
| FR-11 | E5-S3 | | NFR-5 | E4-S11, E6-S4, E7-S4 |
| FR-12 | E5-S4 | | NFR-6 | E2-S4, E5 (common), E6 (common), E6-S7, E7-S4 |
| FR-13 | E5-S5 | | NFR-7 | E1-S2, E2-S1 |
| FR-14 | E5-S6 | | NFR-8 | E1-S5, E7-S1 |

**Uncovered requirements: none.** All FR-1…FR-20 and NFR-1…NFR-8 map to ≥1 story; reverse check: every story maps to ≥1 requirement (E1-S3 supports FR-18's quality bar and all script stories transitively).
