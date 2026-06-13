---
stepsCompleted: [step-01-init, step-02-vision, step-03-users, step-04-metrics, step-05-scope, step-06-complete]
inputDocuments:
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/research.md
  - docs/superpowers/specs/2026-06-09-php-backend-sdlc-plugin-design.md
  - GitHub issue VilnaCRM-Org/claude-plugins#1
date: 2026-06-10
author: Mary (BMAD analyst agent, autonomous run)
mode: autonomous (no human pauses; assumptions recorded inline)
---

# Product Brief: `php-backend-sdlc` Claude Code Plugin

## 0. Executive Summary

Package user-service's proven AI engineering stack (21 skills, governance gates, BMAD/bmalph planning, Ralph implementation loop, PR finishing automation) as a single installable Claude Code plugin in the `VilnaCRM-Org/claude-plugins` marketplace. Any PHP backend repo gets, from one install plus `/sdlc-setup`, a fully autonomous SDLC: a few-sentence task description becomes a GitHub issue, BMAD plan, implemented code, reviewed/QA-verified change, and a finished PR with green CI and zero unresolved AI review comments — looping with self-criticism until done.

V1 ships one plugin (8 commands, 6 agents, 21 generalized skills, project profile, 7 shipped scripts — 3 generalized review scripts + 4 new setup scripts, plugin CI), claude-code driver only. Per-repo variance lives in a generated `.claude/php-sdlc.yml` profile that skills read at runtime; governance text is injected into target repos as delimited managed blocks. Success is measured by install-to-working-SDLC time (≤30 min), a 100% generalization audit pass, and at least one documented zero-intervention end-to-end run on `php-service-template`.

## 1. Problem Statement

VilnaCRM's `user-service` carries a mature, battle-tested AI engineering stack — 21 Claude skills, AGENTS.md/CLAUDE.md governance with protected quality thresholds, a BMAD-method install managed by `bmalph`, the Ralph autonomous implementation loop, and PR governance (21 CI workflows, CodeRabbit, `make ai-review-loop`, BMAD FR/NFR gate) — but it is locked inside that one repository.

Concrete pain (research §1, §3):

- **No installable artifact.** `core-service`, `crm`, and every repo born from `php-service-template` must hand-copy skills, governance docs, and scripts, then edit out user-service specifics.
- **Copy-drift is already corrupting content.** Inside user-service itself, `database-migrations` and `implementing-ddd-architecture` claim "Doctrine ORM (MySQL for this service)" while CLAUDE.md/AGENTS.md declare MongoDB/Doctrine ODM — direct evidence that manual copying breaks persistence assumptions.
- **Hardcoded project context** in ~10 of 21 skills (AWS EMF/AppRunner, `src/User|Shared` paths, VilnaCRM Structurizr containers, `Mongo*Repository` naming) blocks reuse without rewrites.
- **Repo-local coupling.** Skills reference `make ci` (52×), `make ai-review-loop` (22×), `make pr-comments` (7×); the backing scripts live only in `user-service/scripts/` and ship nowhere.
- **Governance lives in repo files, not the tooling.** The mandatory skill-verification gate and thresholds sit in each repo's CLAUDE.md/AGENTS.md with no distribution mechanism.

## 2. Target Users

- **Primary: VilnaCRM backend engineers** working on `user-service`, `core-service`, `crm`, and new services bootstrapped from `php-service-template`. They already run Claude Code, `bmalph`, `gh`, Docker + make, and need the same SDLC automation on every repo without hand-porting.
- **Secondary: any PHP backend team** using Claude Code on a DDD/hexagonal Symfony + API Platform codebase, who can adopt the plugin from the `VilnaCRM-Org/claude-plugins` marketplace and adapt via the project profile.
- **Tertiary: autonomous agents themselves** (Ralph loops, BMALPH planning runs) that consume the skills/commands as their operating procedures.

## 3. Value Proposition

One `claude plugin install php-backend-sdlc@vilnacrm-plugins` turns any PHP backend repo into a fully governed, autonomous SDLC environment: describe a task in a few sentences and the plugin drives GitHub issue → BMAD planning → bmalph/Ralph implementation (claude-code driver) → multi-skill review + FR/NFR gate → manual-style QA → CI auto-fix → resolution of every AI reviewer comment → finished PR, self-criticizing until green. Skills stay single-sourced in the plugin (updates flow with plugin upgrades), while per-repo variance lives in one generated file, `.claude/php-sdlc.yml` — eliminating both hand-copying and copy-drift.

## 4. Goals and Success Metrics

| # | Goal | Metric | Target |
|---|------|--------|--------|
| G1 | Fast bootstrap | Install-to-working-SDLC time on a fresh `php-service-template` clone (marketplace add + install + `/sdlc-setup` incl. profile generation and preflight) | ≤ 30 minutes, single command sequence, no manual file edits |
| G2 | Full generalization | % of 21 skills passing the generalization audit (zero user-service-specific names/paths/bounded contexts outside the profile; audit script in plugin CI) | 100% |
| G3 | Autonomous completion | `/sdlc` reference task on `php-service-template` completes issue→merged-ready PR with CI green, FR/NFR gate pass, 0 unresolved AI review comments, **0 human interventions** | ≥ 1 documented end-to-end run |
| G4 | Load integrity | Commands/agents/skills discovered after install (`claude plugin` listing + smoke prompt) | 8/8 commands, 6/6 agents, 21/21 skills |
| G5 | Gate cost control | Skill-verification gate uses applicability triage; every skill gets an explicit verdict (executed or "Not applicable + concrete reason") | 100% of skills triaged per feature; no silent skips |
| G6 | Plugin quality | Plugin repo CI (JSON validation, markdownlint, shellcheck+bats, frontmatter schema) | Green on every PR |

## 5. Scope

### In scope (v1)

- Single plugin `plugins/php-backend-sdlc/` in the existing `VilnaCRM-Org/claude-plugins` marketplace (Approach B from the approved design).
- 8 commands, 6 agents, 21 generalized skills, project-profile mechanism, 7 shipped scripts (3 generalized review scripts + 4 new setup scripts), plugin CI, docs (install/usage/SDLC loop reference).
- claude-code driver only (`bmalph run --driver claude-code`); Codex paths become optional/no-default.
- Governance injection into target repos via delimited managed blocks in CLAUDE.md/AGENTS.md.
- BMAD planning artifacts for this build in `specs/` (issue acceptance criterion).

### Out of scope (v1)

- No rewrite of the Ralph engine or bmalph CLI; no vendoring of `_bmad/`/`.ralph/` assets — wrap CLIs only.
- No non-PHP stacks (frontend/infra are future marketplace siblings); no multi-plugin split (YAGNI).
- No GitHub App or hosted service; everything runs through the user's local CLIs.
- No non-Claude agent support in v1 commands (skill markdown stays portable regardless).
- No per-repo skill rendering — skills are static and read the profile at runtime.

## 6. Key Features

1. **SDLC commands (8)**: `/sdlc` (end-to-end loop), `/sdlc-setup`, `/sdlc-issue`, `/sdlc-plan`, `/sdlc-implement`, `/sdlc-review`, `/sdlc-qa`, `/sdlc-finish-pr`. Thin orchestrators delegating to skills/agents; each documents its loop, failure path, and max-iteration guard (5/stage, then escalate with status report).
2. **Subagents (6)**: `php-implementer`, `fr-nfr-reviewer`, `code-quality-reviewer`, `qa-manual-tester`, `ci-fixer`, `pr-comment-resolver` — with explicit degrade paths (no CI checks → skip-with-report; no AI reviewer app → local review-loop equivalent).
3. **Generalized skills (21)**: ~10 substantive rewrites (HIGH/MEDIUM specificity: observability, code-organization, structurizr-sync, cache-management, openapi, api-platform-crud, DDD, migrations, deptrac-fixer, docs-creation), ~11 light-edit ports; plus ported SKILL-DECISION-GUIDE/AI-AGENT-GUIDE content.
4. **Project profile**: `.claude/php-sdlc.yml` generated by `/sdlc-setup` (detects composer.json, ORM vs ODM, make targets, bounded contexts, CI/reviewer capabilities); skills reference profile keys at runtime. Quality thresholds live in the profile; shipped defaults: complexity 94, quality/architecture/style 100, MSI 100.
5. **Setup & preflight**: `/sdlc-setup` runs `bmalph doctor` + `gh auth status` + `claude --version`; requires bmalph ≥ 2.11.0; runs `bmalph init` on fresh repos; appends managed governance blocks (`<!-- php-backend-sdlc:begin/end -->`) to CLAUDE.md/AGENTS.md without overwriting existing content.
6. **Shipped scripts**: generalized `ai-review-loop`, `get-pr-comments`, `fr-nfr-gate` (renamed from `bmad-fr-nfr-review-gate.sh`, architecture ADR-4) plus 4 new setup scripts (`setup-preflight`, `generate-profile`, `validate-profile`, `inject-governance`) in plugin `scripts/`, invoked via `${CLAUDE_PLUGIN_ROOT}`; default review agent flips from Codex to Claude.
7. **Plugin CI**: manifest JSON validation, markdownlint, shellcheck + bats, skill/command/agent frontmatter schema checks, generalization-audit check (G2).

## 7. Constraints and Assumptions

### Binding constraints (orchestrator decisions + design non-negotiables)

- Skills read `.claude/php-sdlc.yml` at runtime; `/sdlc-setup` generates it — no per-repo skill rendering.
- Governance injection only via delimited managed blocks; never clobber existing CLAUDE.md/AGENTS.md content.
- Skill-verification gate = applicability triage: every skill explicitly evaluated, executed when applicable, otherwise "Not applicable + concrete reason" recorded.
- Permissions: default `--permission-mode acceptEdits`; `bypassPermissions` is a documented opt-in for Ralph loops only.
- Root-cause culture intact: no suppression annotations, never modify `deptrac.yaml` to pass, thresholds never lowered (profile parameterizes values without weakening user-service defaults).
- Container-only execution in target repos (`make` / `docker compose exec php`).
- Every loop bounded (5 iterations/stage); honor Ralph's circuit breaker, never auto-reset it.

### Assumptions (recorded autonomously, no human confirmation)

- A1: Threshold canonicalization resolved as complexity **94** (CLAUDE.md/AGENTS.md value wins over ci-workflow's 93) and MSI **100** ("high" interpreted as 100); generalized skill text references profile keys, not literals.
- A2: bmalph 2.11.0 non-interactive `bmalph init` works on fresh repos (verified installed locally; init flags untested — preflight surfaces failures rather than assuming success).
- A3: Target repos provide Docker + make and a Makefile close enough to php-service-template's that profile detection can map make targets; missing targets are recorded in the profile as absent capabilities, not errors.
- A4: Internal licensing permits shipping generalized copies of the three review scripts in the plugin (all VilnaCRM-owned).
- A5: The G1 30-minute target excludes Docker image pulls/first `make start` of the target service.

## 8. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Token cost of the 21-skill gate per feature (135–593-line SKILL.md bodies + 44K reference files) | Applicability triage (G5) with mandatory recorded verdicts; load reference files only when a skill executes |
| bmalph/claude version drift (`_bmad/` is generated; `.ralphrc` pins CLAUDE_MIN_VERSION 2.0.76 vs 2.1.170 installed) | bmalph ≥ 2.11.0 floor; `/sdlc-setup` preflight (`bmalph doctor` + `gh auth status` + `claude --version`); never vendor generated assets so `bmalph upgrade` and the plugin never fight |
| Target-repo variance (ORM/MySQL vs ODM/MongoDB, REST vs REST+GraphQL, absent Structurizr/EMF) | Profile detection drives skill behavior; skills branch on profile keys; absent stacks → skill triaged "Not applicable + reason" |
| Copy-drift recurrence inside the plugin itself | Single-source skills in the plugin; CI generalization audit blocks user-service markers from re-entering skill text |
| Fresh repos lack CI workflows/CodeRabbit/branch protection | `ci-fixer`/`pr-comment-resolver` degrade paths: no checks → skip-with-report; no AI reviewer → shipped local `ai-review-loop`; profile records reviewer capabilities |
| Permission denials stall unattended runs | Default acceptEdits documented per command; bypassPermissions opt-in documented for Ralph; denial states surfaced in status reports instead of silent looping |
| Marketplace install-mode divergence (local relative path vs pinned `git-subdir`) | Release tagging discipline (ref + sha pinning) documented before external consumption; local source remains for development |
| Governance block conflicts with pre-existing repo rules | Managed blocks are delimited and idempotent (replace-own-block on re-run); setup diffs and reports rather than silently merging |

## 9. Open Questions (non-blocking for PRD)

1. **Profile schema final key set** — persistence, contexts, make targets, thresholds, CI/reviewer capabilities are agreed; exact YAML key names and required-vs-optional split land in architecture.
2. **Reference task for G3** — which concrete feature on `php-service-template` serves as the documented autonomous end-to-end run (small CRUD resource is the leading candidate).
3. **`ai-review-loop` behavior matrix without Codex CLI present** — Claude-only agent list is the default; exact flag mapping of the generalized script needs verification during implementation.
4. **Release cadence/versioning policy** for the marketplace (when to start pinning `ref`+`sha` for external consumers vs the current relative-path source).
