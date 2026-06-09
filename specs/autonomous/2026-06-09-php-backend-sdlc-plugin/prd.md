---
stepsCompleted: [step-01-init, step-02c-executive-summary, step-03-success, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish, step-12-complete]
inputDocuments:
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/research.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/product-brief.md
workflowType: 'prd'
date: 2026-06-10
author: John (BMAD PM agent, autonomous run — interactive steps skipped, decisions recorded inline)
---

# Product Requirements Document — `php-backend-sdlc` Claude Code Plugin

## 1. Executive Summary

Package user-service's proven AI engineering stack as one installable plugin in the `VilnaCRM-Org/claude-plugins` marketplace: 8 SDLC commands, 6 subagents, 21 generalized skills, a generated per-repo project profile (`.claude/php-sdlc.yml`), 7 shipped scripts (3 generalized review scripts + 4 new setup scripts), and plugin CI. After `claude plugin install php-backend-sdlc@vilnacrm-plugins` + `/sdlc-setup`, any PHP backend repo runs a fully autonomous SDLC: task description → GitHub issue → BMAD plan → bmalph/Ralph implementation (claude-code driver) → multi-lens review + FR/NFR gate → black-box QA → finished PR with green CI and zero unresolved AI review comments. Brief goals G1–G6 govern this PRD; every FR/NFR traces to them (§5).

## 2. Functional Requirements

### 2.1 Commands (8) — `plugins/php-backend-sdlc/commands/`

All commands are thin orchestrators (markdown slash commands) that delegate to skills/agents, document their loop, failure path, and a max-5-iteration guard per stage, and never pause for human input mid-loop unless a circuit breaker fires.

**FR-1 — `/sdlc` end-to-end orchestrator** (G3)
Runs the full stage sequence with gated transitions — a stage starts only when the prior stage's exit condition is met:

| # | Stage | Delegates to | Exit condition | Guard |
|---|---|---|---|---|
| 0 | setup-check | profile + preflight validation | valid `.claude/php-sdlc.yml`, preflight fresh | halt → instruct `/sdlc-setup` (never auto-generate profile in-loop) |
| 1 | issue | `/sdlc-issue` | GitHub issue URL exists with testable AC | 5 iterations |
| 2 | plan | `/sdlc-plan` | `specs/` chain complete, readiness PASS | 5 iterations |
| 3 | implement | `/sdlc-implement` | Ralph `EXIT_SIGNAL` success, all stories done | 5 iterations + circuit breaker |
| 4 | review | `/sdlc-review` | zero new findings in last gate iteration | 5 iterations |
| 5 | qa | `/sdlc-qa` | QA verdict PASS (FAIL routes back to stage 3) | 5 iterations |
| 6 | finish-pr | `/sdlc-finish-pr` | CI green + 0 unresolved AI review comments | 5 iterations |

- Resumability: on invocation, detect current stage from artifacts (issue, `specs/` chain, branch/PR state) and resume rather than restart.
- Each stage has a max-iteration guard of 5; on breach, stop and emit a status report (stage, iteration log, blocking finding, recommended human action). Never auto-reset Ralph's circuit breaker.
- Exit conditions: SUCCESS (finish-pr exit condition met) or ESCALATED (guard breach / circuit breaker / unmet preflight) — both produce a final structured run report.
**AC:** A dry-run prompt walk-through shows all 7 stages, every gate condition, both exit paths, and the guard counter; reference task on `php-service-template` completes issue→PR-ready with 0 human interventions (G3 evidence run).

**FR-2 — `/sdlc-setup`** (G1)
- Preflight: `bmalph doctor`, `gh auth status`, `claude --version`, `git` repo check; enforce version floors (NFR-7); report each check PASS/FAIL with remediation; abort on FAIL.
- Fresh-repo bootstrap: when `_bmad/` is absent, run non-interactive `bmalph init`; surface (not mask) init failures.
- Profile generation: detect from `composer.json` (PHP version, framework, API Platform/GraphQL), Doctrine config (ORM vs ODM + engine), `Makefile` scan (target map), `src/` layout (bounded contexts), `.github/workflows/` (CI workflow names), `.coderabbit.yaml` presence (reviewer config); write `.claude/php-sdlc.yml` per FR-17 schema. Missing capabilities are recorded as absent (`null`/`false`), not errors.
- Governance injection: append delimited managed blocks (`<!-- php-backend-sdlc:begin -->` … `<!-- php-backend-sdlc:end -->`) to target-repo `CLAUDE.md` and `AGENTS.md` carrying the skill-triage gate, protected thresholds (profile-referenced), and container-only rule. Re-run replaces only its own block; existing content never clobbered; setup prints a diff summary.
- Permissions: document/write recommended `.claude/settings.json` allowlist for `--permission-mode acceptEdits`; `bypassPermissions` documented as Ralph-only opt-in.
**AC:** On a fresh `php-service-template` clone, one run produces a valid profile, managed blocks, passing preflight report in ≤30 min (excluding image pulls, per A5); second run changes nothing outside its managed blocks and profile (NFR-3 test).

**FR-3 — `/sdlc-issue`** (G3)
Converts a few-sentence task description into a GitHub issue via `gh issue create`: title, problem statement, acceptance criteria (testable bullets), scope notes, and a plugin marker label; outputs issue number/URL for downstream stages. If an issue URL is passed as argument, validates and adopts it instead of creating a duplicate.
**AC:** Given a 2-sentence input, the created issue contains ≥3 testable acceptance criteria and the command output includes the issue URL consumed by `/sdlc-plan`.

**FR-4 — `/sdlc-plan`** (G3)
Runs the BMAD planning chain non-interactively (delegating to the `bmad-autonomous-planning` skill): research → product brief → PRD → architecture → epics/stories → implementation-readiness, writing artifacts under `specs/` keyed to the issue. Assumptions are recorded inline; no human pauses. Exit condition: implementation-readiness check passes; otherwise loop corrections (max 5) then escalate.
**AC:** For the reference issue, `specs/<slug>/` contains all six artifacts with consistent cross-references and a readiness verdict; zero interactive prompts were issued.

**FR-5 — `/sdlc-implement`** (G3)
- Transitions planning artifacts via `bmalph implement`, then starts `bmalph run --driver claude-code` (never Codex by default).
- Parallel execution: stories marked independent in the epics/stories artifact are dispatched to parallel `php-implementer` subagents; dependent stories run sequentially per the artifact's ordering.
- Honors `.ralphrc` circuit breaker (no-progress 3, same-error 5, output-decline 70%); on trip, stop and report — never reset/restart automatically.
- All build/test execution inside containers (`make` / `docker compose exec php`); profile `make` map drives target names.
**AC:** Run log shows driver `claude-code`, ≥2 independent stories executed in parallel when the plan provides them, and a circuit-breaker simulation ends in ESCALATED status with report (no auto-reset).

**FR-6 — `/sdlc-review`** (G5)
- Applicability triage over all 21 skills: each skill gets an explicit recorded verdict — EXECUTE (with evidence) or NOT APPLICABLE + concrete reason; no silent skips. Reference files are loaded only for executed skills.
- Multi-lens review: `code-quality-reviewer` (skills/threshold lens) and `fr-nfr-reviewer` (spec lens) run against the diff and `specs/` artifacts.
- FR/NFR gate loop: invoke the gate (shipped script, FR-18) and re-review after fixes until an iteration yields **zero new findings**; max 5 iterations then escalate.
**AC:** Review report lists 21/21 triage verdicts, both reviewer outputs, per-iteration finding counts reaching 0, and threshold checks referencing profile values (complexity 94, quality/architecture/style 100, MSI 100 defaults).

**FR-7 — `/sdlc-qa`** (G3)
Black-box verification by `qa-manual-tester`: start the service (profile `make` map), exercise behavior against the issue/PRD acceptance criteria via HTTP/API calls only (no source reading for verdicts), cover positive/negative/edge cases, and emit a PASS/FAIL QA report with reproduction steps per failure. FAIL routes back to `/sdlc-implement` with the report attached (bounded by FR-1 guards).
**AC:** QA report for the reference task maps every issue acceptance criterion to ≥1 executed check with observed-vs-expected output; a seeded defect produces FAIL with reproduction steps.

**FR-8 — `/sdlc-finish-pr`** (G3)
- Creates/updates the PR (`gh pr create/edit`) with spec-linked description.
- CI fix loop: `ci-fixer` polls checks, diagnoses failures from logs, root-cause fixes (no suppressions/threshold edits), pushes, re-polls — until all checks green; max 5 iterations.
- AI comment resolution loop: `pr-comment-resolver` fetches comments via the shipped `get-pr-comments` script (GraphQL resolution-aware), addresses each with a code fix or reasoned reply, marks resolved, loops until 0 unresolved; max 5 iterations.
- Degrade paths per NFR-4: no CI checks configured → skip-with-report; no AI reviewer app → run shipped `ai-review-loop` locally as the review source.
**AC:** On a PR with ≥1 failing check and ≥1 CodeRabbit comment, the command ends with all checks green and 0 unresolved comments; on a repo with no workflows it ends SUCCESS-WITH-REPORT noting the skipped CI stage.

### 2.2 Subagents (6) — `plugins/php-backend-sdlc/agents/`

Each agent file declares role, inputs, outputs, allowed tools, degrade paths, and iteration discipline.

**FR-9 — `php-implementer`** (G3)
- Role: implement one story end-to-end (code + tests) per DDD/hexagonal skills; container-only execution; root-cause culture (no suppressions, no threshold edits).
- Inputs: story spec from `specs/`, project profile, governance managed blocks, applicable skills.
- Outputs: commits, story status block (`---RALPH_STATUS---`-compatible: EXIT_SIGNAL, tasks completed), self-review checklist.
- Tools: Read/Write/Edit, Bash (`make`, `docker compose exec php`, `git`), skill loading.

**FR-10 — `code-quality-reviewer`** (G5)
- Role: review the diff against executed-skill rules and protected thresholds; never propose suppressions or threshold reductions.
- Inputs: diff, profile quality keys, triage verdicts from `/sdlc-review`.
- Outputs: findings list (file:line, severity, root-cause fix proposal), per-threshold PASS/FAIL.
- Tools: Read, Grep/Glob, Bash (read-only profile `make` quality targets).

**FR-11 — `fr-nfr-reviewer`** (G3, G5)
- Role: verify every FR/NFR in the `specs/` chain is implemented and tested; drive the gate loop to zero new findings.
- Inputs: `specs/` artifacts, diff, test results, FR/NFR gate script output.
- Outputs: per-requirement PASS/FAIL matrix, new-findings count per iteration.
- Tools: Read, Bash (gate script via `${CLAUDE_PLUGIN_ROOT}`, test targets), `gh` (commit status / PR comment).

**FR-12 — `qa-manual-tester`** (G3)
- Role: black-box behavioral QA per FR-7; verdicts derived only from observed behavior, never from reading implementation source.
- Inputs: issue acceptance criteria, PRD, running service endpoint, profile (`make.start`, framework/API shape).
- Outputs: QA report — executed checks, observed vs expected, PASS/FAIL verdict, reproduction steps per failure.
- Tools: Bash (curl/HTTP clients, `make start`/logs); no source edits permitted.

**FR-13 — `ci-fixer`** (G3)
- Role: turn failing PR checks green via root-cause fixes only.
- Inputs: PR ref, check runs + failure logs (`gh`), profile `ci.workflows`/`ci.required_checks`.
- Outputs: fix commits, per-iteration check-status table, final status.
- Tools: Bash (`gh`, `git`, `make`), Read/Edit. Degrade: no checks configured → report-and-skip.

**FR-14 — `pr-comment-resolver`** (G3)
- Role: drive every AI/human review comment to resolved — code fix or reasoned reply, never silent dismissal.
- Inputs: PR ref, `get-pr-comments` script output (resolution-aware), diff context, profile `review.*`.
- Outputs: fix commits or reply text, resolution log, final unresolved count.
- Tools: Bash (`gh` GraphQL via shipped script, `git`, `make`), Read/Edit. Degrade: no reviewer app → shipped `ai-review-loop` findings as comment source.

**AC (FR-9..14):** Each agent markdown contains all six declared sections (role, inputs, outputs, tools, degrade path, iteration discipline); each agent loads in the `claude` agent listing; a per-agent smoke prompt exercises its happy path plus one degrade path where defined.

### 2.3 Skills (21) — `plugins/php-backend-sdlc/skills/`

**FR-15 — Generalized skill set, grouped by rewrite depth** (G2). All skills keep the verified format (YAML frontmatter + Context/Task/Success-Criteria/Steps/Constraints/Verification, relative cross-links) and read `.claude/php-sdlc.yml` at runtime — no per-repo rendering, no user-service literals outside fenced profile examples. Grouping follows research §1.1 specificity ratings:

*Deep rewrite — 4 skills (HIGH specificity):*
- `observability-instrumentation` — parameterize AWS EMF/AppRunner behind `capabilities.observability_emf`; generic business-metric guidance when absent.
- `code-organization` — bounded contexts and source paths from `architecture.*`; the "directory X contains only type X" law kept stack-generic.
- `structurizr-architecture-sync` — gate on `capabilities.structurizr`; container/system names from profile, not VilnaCRM literals.
- `cache-management` — repository naming derived from `persistence.mapper`/`engine` (e.g. `Cached*Repository` wrapping the persistence-specific repository), not hardcoded `Mongo*`.

*Moderate rewrite — 6 skills (MEDIUM specificity):*
- `openapi-development` — OpenAPI layer path from profile instead of `src/Shared/Application/OpenApi` literal.
- `api-platform-crud` — context/path/make references via profile; API Platform version from `framework.api_platform`.
- `implementing-ddd-architecture` — remove "Doctrine ORM with MySQL for this service" drift; branch examples on `persistence.*`.
- `database-migrations` — frontmatter and body parameterized on `persistence.mapper` (ORM migrations vs ODM schema management).
- `deptrac-fixer` — layer names/paths from `architecture.*`; "never edit deptrac.yaml" rule unchanged.
- `documentation-creation` — project naming, structure, and doc targets from profile.

*Light edit — 11 skills (LOW specificity):*
- `code-review`, `ci-workflow`, `complexity-management`, `quality-standards`, `testing-workflow` — map all `make` references through `make.*`; thresholds via `quality.*` keys (canonical defaults complexity 94, MSI 100, per A1).
- `bmad-fr-nfr-review-gate` — invoke the shipped gate script (FR-18) instead of assuming a repo-local make target.
- `documentation-sync`, `clean-architecture-llm`, `bmad-autonomous-planning` — naming/link hygiene only.
- `query-performance-analysis` — branch MySQL/MariaDB `EXPLAIN` vs MongoDB `explain()` on `persistence.engine`.
- `load-testing` — K6 endpoints/config from profile; gate on `capabilities.load_testing`.

**AC:** 21/21 skills present and loadable as `php-backend-sdlc:<skill>`; generalization audit (NFR-2 denylist) passes on every skill; cross-skill relative links resolve in the install cache; each deep/moderate-rewrite skill explicitly names the profile keys it consumes.

**FR-16 — Meta-guides** (G5): Port `SKILL-DECISION-GUIDE.md` (decision tree + triage-gate list reflecting the applicability-triage policy, not "run all verbatim") and `AI-AGENT-GUIDE.md` into plugin `docs/`/`skills/`, generalized per NFR-2.
**AC:** Both guides shipped; triage rule ("every skill verdict recorded, no silent skips") stated verbatim; audit passes.

### 2.4 Project profile

**FR-17 — `.claude/php-sdlc.yml` schema** (G1, G2). Required key set (names final-pending architecture, OQ-1):
- `project`: `name`, `repo` (owner/name)
- `php`: `version`
- `framework`: `name`, `version`, `api_platform` (bool|version), `graphql` (bool)
- `persistence`: `mapper` (`doctrine-orm`|`doctrine-odm`), `engine` (`mysql`|`mariadb`|`postgresql`|`mongodb`)
- `architecture`: `source_root`, `bounded_contexts` (list), `shared_context`
- `make`: logical→actual target map (`ci`, `start`, `tests`, `e2e`, `psalm`, `deptrac`, `phpinsights`, `infection`, `ai_review_loop`, `pr_comments`, `fr_nfr_gate`, `load_tests`); value `null` = capability absent
- `quality`: `phpinsights` (`quality`, `architecture`, `style`, `complexity`), `deptrac_violations`, `psalm_errors`, `infection_msi` — shipped defaults 100/100/100/94, 0, 0, 100; values may only be raised, never lowered below defaults
- `ci`: `provider`, `workflows` (names), `required_checks`
- `review`: `coderabbit` (bool), `ai_review_agents` (default `[claude]`), `request_changes_blocking` (bool)
- `capabilities`: `structurizr`, `observability_emf`, `load_testing` (bools)
**AC:** Schema documented in plugin docs with required/optional marking and an annotated user-service example; `/sdlc-setup` output on `php-service-template` validates against it; a skill reading any undeclared key is a CI doc-check failure.

### 2.5 Scripts, manifest, CI

**FR-18 — Shipped scripts** (G3): generalized `ai-review-loop.sh` (default agent **claude**; Codex optional via `ai_review_agents`), `get-pr-comments.sh` (GraphQL resolution-aware), `fr-nfr-gate.sh` (PR comment + commit status; renamed from `bmad-fr-nfr-review-gate.sh`, see architecture ADR-4) under plugin `scripts/`, invoked via `${CLAUDE_PLUGIN_ROOT}`; no dependency on target-repo copies.
**AC:** Each script runs from the install cache against a target repo; `ai-review-loop` completes with only `claude` CLI present; shellcheck-clean; bats-covered.

**FR-19 — Marketplace manifest + plugin metadata** (G4, G6): valid `.claude-plugin/plugin.json` (name/version/description/author/homepage, semver bumped per release) and marketplace entry in `.claude-plugin/marketplace.json` (relative `source` for dev; `git-subdir` + `ref`+`sha` pinning documented for external consumers, OQ-3).
**AC:** `claude plugin install php-backend-sdlc@vilnacrm-plugins` succeeds from a clean machine profile; manifest JSON validates in CI.

**FR-20 — Plugin CI** (G2, G6): GitHub workflows in repo `.github/workflows/`: JSON manifest validation, markdownlint, shellcheck + bats, frontmatter schema checks (commands/agents/skills), the profile-keys doc-check (FR-17 AC), and the generalization audit (NFR-2 denylist grep) — all required on PRs.
**AC:** All seven CI jobs (six check areas; architecture §6) exist and pass on the v1 PR; seeding a denylist token (e.g. `VilnaCRM` in a SKILL.md body) fails the audit check.

## 3. Non-Functional Requirements

**NFR-1 — Installability / load integrity** (G4): After install, component discovery reports exactly 8/8 commands, 6/6 agents, 21/21 skills.
**AC:** `claude plugin` listing + smoke prompt enumerate all components; counts asserted in a bats test against the install cache layout.

**NFR-2 — Generalization** (G2): Zero user-service-specific identifiers outside profile examples/docs. CI-greppable denylist (case-insensitive) over `skills/ commands/ agents/ scripts/`: `VilnaCRM` (allowed only in `plugin.json` author/homepage and marketplace metadata), `user-service`, `MongoXxxRepository`/`Mongo[A-Z]\w*Repository`, `AppRunner`, `workspace.dsl` container names, `src/User`, `src/OAuth`. Explicit profile-example blocks are fenced and excluded by marker.
**AC:** Audit script in plugin CI exits 0 on the v1 tree; 100% of 21 skills pass (G2 metric).

**NFR-3 — Idempotency of `/sdlc-setup`**: Re-running setup on an already-configured repo is a no-op outside its own artifacts: managed blocks replaced in place, profile regenerated only with `--refresh` (otherwise diff-reported), no duplicate blocks ever.
**AC:** Two consecutive runs → `git diff` empty on second run; corrupted/duplicated marker test → setup repairs to a single block.

**NFR-4 — Degrade paths**: Every external-capability dependency has a defined no-capability behavior: no CodeRabbit → local `ai-review-loop` substitutes; missing make target (profile `null`) → skill/agent records "capability absent" and skips that check with report; no CI workflows → `ci-fixer` skip-with-report. No degrade path may loop or hard-fail.
**AC:** Three simulated environments (no reviewer, stripped Makefile, no workflows) each complete their stage with an explicit degrade note and SUCCESS-WITH-REPORT status.

**NFR-5 — Token-cost bounds** (G5): The review gate uses applicability triage — full SKILL.md + reference files loaded only for skills with EXECUTE verdicts; NOT-APPLICABLE verdicts decided from frontmatter description + decision guide alone. 100% of skills receive a recorded verdict per feature.
**AC:** Review report shows verdicts for 21/21 skills; for a docs-only reference change, ≤8 skills load full bodies (triage demonstrably filtering).

**NFR-6 — Loop safety**: Every loop bounded at max 5 iterations/stage; on breach or Ralph circuit-breaker trip, run halts with a structured status report (stage, counts, last error, recommended action); breakers are surfaced, never auto-reset; cooldowns honored.
**AC:** Forced-failure tests on review and finish-pr loops stop at iteration 5 with the report; breaker-trip simulation shows no automatic restart.

**NFR-7 — Version floors**: `/sdlc-setup` preflight enforces `bmalph ≥ 2.11.0`, `claude ≥ 2.1.x`, `gh ≥ 2.x`; failures abort with named remediation. No vendored `_bmad/`/`.ralph/` assets, so `bmalph upgrade` never conflicts with the plugin.
**AC:** Preflight against an under-version stub binary aborts with the correct message; plugin tree contains no `_bmad/`/`.ralph/` files (CI check).

**NFR-8 — Docs completeness** (G1, G6): Plugin `README.md` + `docs/` cover: install (marketplace add + install), `/sdlc-setup` walkthrough, profile schema reference (FR-17), SDLC loop reference (stage diagram, exit conditions, guards), permissions model (acceptEdits default, bypassPermissions opt-in), degrade-path matrix, release/versioning notes.
**AC:** A new engineer following only README + docs reaches a passing `/sdlc-setup` on `php-service-template` within the G1 budget; markdownlint passes; every FR-17 key documented.

## 4. Acceptance Criteria and Release Gate

Acceptance criteria are embedded per requirement above; each **AC:** block is the binding, testable criterion for its FR/NFR. The v1 release gate requires all of:

1. All FR ACs demonstrated (FR-1..20), with the FR-1/G3 evidence run documented in `docs/`.
2. CI-automated NFR ACs green: NFR-1 (component counts), NFR-2 (generalization audit), NFR-3 (idempotency bats test), NFR-7 (no vendored assets check) — all in plugin CI per FR-20.
3. Run-documented NFR ACs evidenced: NFR-4 (three degrade environments), NFR-5 (triage filtering on a docs-only change), NFR-6 (forced-failure loop stops), NFR-8 (docs walkthrough).
4. Traceability matrix (§5) verified complete in the implementation-readiness check — no orphan requirement, no uncovered goal.

## 5. Traceability Matrix

| Brief goal | Requirements |
|---|---|
| G1 Fast bootstrap (≤30 min) | FR-2, FR-17, NFR-3, NFR-7, NFR-8 |
| G2 Full generalization (100% audit) | FR-15, FR-16, FR-17, FR-20, NFR-2 |
| G3 Autonomous completion (0 interventions) | FR-1, FR-3, FR-4, FR-5, FR-7, FR-8, FR-9..14, FR-18, NFR-4, NFR-6 |
| G4 Load integrity (8/6/21) | FR-19, NFR-1 |
| G5 Gate cost control (triage) | FR-6, FR-10, FR-11, FR-16, NFR-5 |
| G6 Plugin quality (CI green) | FR-19, FR-20, NFR-7, NFR-8 |

Reverse check: every FR/NFR appears in at least one goal row (FR-1..20, NFR-1..8 all mapped).

## 6. Out of Scope (v1)

- No rewrite/vendoring of Ralph, bmalph, or BMAD assets (`_bmad/`, `.ralph/`) — CLI wrapping only.
- No non-PHP stacks; no multi-plugin split; no GitHub App or hosted service.
- No non-Claude drivers in v1 commands (Codex paths optional in scripts only, never default).
- No per-repo skill rendering — skills are static, profile-read-at-runtime.
- No automatic branch-protection/CodeRabbit provisioning in target repos (detection + degrade only).

## 7. Assumptions (carried from brief §7, binding for architecture)

- A1: Thresholds canonicalized — complexity **94**, MSI **100**; skill text references profile keys, never literals.
- A2: Non-interactive `bmalph init` works on fresh repos at 2.11.0; preflight surfaces failures rather than assuming success.
- A3: Target repos provide Docker + make; unmapped make targets recorded as absent capabilities (profile `null`), not errors.
- A4: Internal licensing permits shipping generalized copies of the three review scripts.
- A5: G1's 30-minute target excludes Docker image pulls / first `make start`.
- Binding constraints restated: runtime profile reads; delimited managed governance blocks only; triage-based gate; acceptEdits default / bypassPermissions Ralph-only opt-in; root-cause culture (no suppressions, no `deptrac.yaml` edits, thresholds never lowered); container-only execution; 5-iteration bound + breaker honored everywhere.

## 8. Open Questions for Architecture

1. **Profile key naming finalization (OQ-1):** FR-17 fixes the key *set*; architecture finalizes exact YAML names, nesting, required-vs-optional split, and the schema-validation mechanism (JSON Schema vs script).
2. **`ai-review-loop` flag mapping (OQ-2):** map the generalized script's flags from the Codex-default original (`--output-last-message` dependency) to claude-CLI equivalents; define the agent-matrix behavior when only `claude` is present (brief §9.3).
3. **Release tagging policy (OQ-3):** when to switch marketplace `source` from relative path to pinned `git-subdir` (`ref`+`sha`); semver cadence and changelog discipline for external consumers (brief §9.4).
4. **Reference task for G3 (brief OQ-2) — RESOLVED:** the evidence run implements a small CRUD resource (e.g. `Currency`: code+name fields, REST CRUD endpoints) on a fresh `php-service-template` clone — sized so BMAD planning yields ≥2 independent stories for FR-5's parallel-dispatch AC (pinned in epics E7-S3).
