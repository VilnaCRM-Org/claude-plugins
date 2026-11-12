---
stepsCompleted: [step-01-init, step-02-discovery, step-02b-vision, step-02c-executive-summary, step-03-success, step-04-journeys, step-05-domain, step-06-innovation, step-07-project-type, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish, step-12-complete]
inputDocuments:
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/task-framing.md
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/research.md
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/product-brief.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md (depth bar, same artifact kind)
documentCounts: { briefCount: 1, researchCount: 1, brainstormingCount: 0, projectDocsCount: 1 }
classification:
  projectType: developer_tool (Claude Code plugin) with cli_tool traits (slash commands, shell scripts)
  domain: general (software-delivery tooling; no regulated data)
  complexity: medium (low regulatory, high integration surface)
  projectContext: brownfield (new plugin in an existing marketplace, serving an existing template)
workflowType: 'prd'
date: 2026-11-11
revised: 2026-11-12 (reviser pass over 41 review findings; see Revision Log)
author: John (BMAD PM agent), autonomous run for the main agent acting as user surrogate
mode: autonomous (A/P/C menus and elicitation skipped; decisions recorded inline as Assumptions)
---

# Product Requirements Document: `rust-backend-sdlc` Claude Code Plugin

Path conventions: `tpl/` = the Rust service template checkout (`/home/user/rust-service-template`, HEAD `3e0bd3e`); `php/` = `plugins/php-backend-sdlc/`; `react/` = `plugins/react-frontend-sdlc/`; `repo/` = the marketplace root (`/home/user/claude-plugins`). "KF n", "H n", "X n" cite Key Finding, Integration Hazard and Reference Defect n of `research.md`; "P n", "A n", "K n", "S n", "C n" cite the Pain, Assumption, KPI, new-service Step and new-context Checklist ids of `product-brief.md`. Plugin paths (`commands/`, `scripts/`, …) are relative to `plugins/rust-backend-sdlc/`.

> Assumption: the BMAD create-prd workflow (PM agent "John", `_bmad/core/tasks/bmad-create-prd/`) was run non-interactively. Step mapping: step 1 discovered the three bundle inputs (no `_bmad-output/` or project-context file holds anything for this topic); step 2 classification is in the frontmatter (project-types row `developer_tool`, domain row `general`); steps 2b/2c → Executive Summary; step 3 → Goals and Success Criteria; step 4 → User Journeys; step 5 (domain) skipped: domain `general` has no compliance section; step 6 (innovation) folded into the Executive Summary differentiators; step 7 (project type) → Scope "Product surface"; step 8 → Scope and Out of Scope; steps 9/10 → Functional and Non-Functional Requirements; step 11 polish applied; step 12 completion recorded in the frontmatter. Every menu and elicitation pause was answered by the user surrogate.
>
> Assumption: the orchestrator's required H2 set supersedes the template's section names (`Product Scope` → `Scope`; extra H2s such as `Open Questions for Architecture` are allowed). bmalph copies the first 5,000 characters of `Executive Summary`, `Success Criteria`, `Scope`, `Target Users` and `Non-Functional Requirements` into `.ralph/PROJECT_CONTEXT.md` (`bmalph/dist/utils/constants.js:22`, `SECTION_EXTRACT_MAX_LENGTH = 5000`), so each of those sections leads with its densest content (the NFR section opens with a one-line index of all NFRs).
>
> Assumption: task-framing identity decisions (name, version, prefix, the 10 commands, profile path, markers, label, log prefix, tag namespace, bundle dir) and the brief's assumptions A1–A22 are binding and are not re-opened. This PRD resolves the brief's five open questions (PA-3 to PA-6 below) and fixes the profile key set (PA-1).

## Executive Summary

`rust-backend-sdlc` 0.1.0 is a Claude Code plugin in the `vilnacrm-plugins` marketplace (`plugins/rust-backend-sdlc/`) that turns the Rust service template into a product line for microservices. Three entry points carry the value: `/rs-sdlc-new-service` creates a service from the template and ends with a green bootstrap PR; `/rs-sdlc-new-context` adds a bounded context and proves it with the template's gates; `/rs-sdlc` drives a feature from a few sentences to a ready-to-merge PR: GitHub issue → BMAD planning bundle → bmalph/Ralph implementation → multi-lens review with the BMAD FR/NFR gate → black-box QA against the running service (REST, GraphQL, `/ping`, `/api/health`) → PR with CI green and every review thread resolved. Seven stage commands (`/rs-sdlc-setup`, `/rs-sdlc-issue`, `/rs-sdlc-plan`, `/rs-sdlc-implement`, `/rs-sdlc-review`, `/rs-sdlc-qa`, `/rs-sdlc-finish-pr`) run each step alone and resume an interrupted loop. The command path implements through `bmalph run` (Ralph); the Workflow-tool path (`workflows/rs-sdlc-feature.js`, epic 8) stages the same plan with `bmalph implement` and executes Ralph's fix plan through orchestrated `rust-implementer` rounds, never `bmalph run` (FR-44, PA-17).

**Problem.** The template defines what "mergeable" means with unusual precision — 31 ordered gates in 7 stages (`make ci-list`), 100% line and function coverage, zero surviving mutants on the diff, clippy `-D warnings` over `all pedantic nursery cargo`, cognitive complexity 8 / 50 lines / 5 arguments / nesting 5, zero architecture violations, current contract snapshots — yet ships no driver that gets a change there. `php-backend-sdlc` has the driver but cannot be reused: it writes the protected `.claude/settings.json`, its commit subjects fail the template's commit-msg hook, its governance text fails `make docs-check`, it never stages the plan where bmalph reads it, and it carries 19 catalogued defects (X1–X19).

**Approach.** Port the language-agnostic 70–80% of the PHP contract (stage machine, `MAX_ITERATIONS=5`, the 7-field `=== SDLC ESCALATION ===` block, machine-readable handles, degrade taxonomy, ledgers, the FR/NFR gate with React's hardened interface) and rebuild the rest around the 32 verified template hazards (H1–H32). Per-repository variance lives in one committed file, `.claude/rust-sdlc.yml` (`schema_version: 1`), that every component reads at runtime. Binding principles: repository wins (the template's 11 skills and `AGENTS.md` take precedence over same-named plugin skills); make-only execution through the profile's `make.*` map; tighten-only quality bars; protected-configuration safety (permission allowlist goes to the git-ignored `.claude/settings.local.json`); docs-check-safe governance blocks; hook-valid `type(#issue): subject` commits; bounded, resumable, honest loops that end in exactly `SUCCESS` or `ESCALATED` and never fake a pass.

**Inventory (v0.1.0).** 10 commands, 7 agents, 28 skills + 2 meta-guides, 13 executable scripts + `scripts/lib/common.sh`, 4 Workflow-tool scripts with a deterministic harness (epic 8: in scope, and the cut line), 1 configuration file (`config/new-service.defaults.json`), 9 docs + plugin `README.md`, 16 bats suites (≥ 460 tests); wired into `.claude-plugin/marketplace.json`, the root `README.md` and `.github/workflows/ci.yml`.

**Differentiators.** (1) Built against the template's exact contract, re-read at runtime where it can drift (`make ci-list`, `cargo xtask config-guard --list`, `make help`). (2) Cross-stack parity: same stage machine, run report, ledgers and byte-identical `BMAD FR/NFR Review Gate` commit status as the PHP and React plugins. (3) Lifecycle commands the siblings lack (service creation, bounded-context addition). (4) Lessons already paid for: X1–X19 fixed, React's two-level `workflow()` nesting replaced by a hand-back contract.

**Success** is G1–G4 (Goals) plus the marketplace release gate RG: 0 plugin-quality lint findings, all CI jobs green with the Rust plugin covered, pinned component counts, ≥ 460 bats tests with 0 failures.

## Goals

| Id | Goal | Release-gate measure (v0.1.0) | Post-release measure |
| --- | --- | --- | --- |
| G1 | Create a new Rust microservice from the template in one guided command | (a) 8 of 8 deterministic `docs/new-service.md` steps (identity, version, `bmalph/config.json`, README, CHANGELOG, `specs/` reset, sync flavour, `.templatesyncignore`) automated with 0 manual file edits when `--sync-flavour` is given; (b) a second `new-service.sh` run with the same arguments prints only `UNCHANGED:`/`SKIP:` lines and exits 0; (c) on the stub fixture the written files pass yamllint, Prettier, markdownlint-cli2, typos, static docs-check rules 1–4 (incl. 0 rule-3 violations after either sync-flavour deletion, FR-12) and invariant (e) (neither the literal `rust-service-template` nor the fixture's `TEMPLATE_REPOSITORY` name, K7) | (c′) on a scratch template copy after S1–S14: `make validate-invariants`, `make docs-check`, `make validate-contract-snapshots` pass; (d) ≤ 15 min hands-on (K9); bootstrap PR green on first push, ≤ 2 h wall clock (K13) |
| G2 | Build features through the full SDLC loop, bounded and resumable, with the SUCCESS / ESCALATED report contract | (a) every stage bounded (stages 5; finish-pr counters A 5, B 5, C 3, W 6, R 3); 0 unbounded loops; (b) 100% of runs end `result: SUCCESS` or `result: ESCALATED`, every escalation carries all 7 fields with a concrete `blocking_finding`; (c) resume repeats 0 completed stages, also after `cargo clean` or in a fresh clone, when `gh` is reachable (otherwise D10 applies) — proven by `common-lib.bats` cases on `resume_point` (ancestor / equal / live rules, a fresh clone without the `target/rust-sdlc/state/` cache, a stale QA verdict), the `rs-sdlc.md` resume-table contract test (AC-3.2) and (epic 8) the `carry` re-entry harness scenario (AC-3.4) | (d) ≥ 1 documented reference run (CRUD resource in a new bounded context on a fresh service) reaching a ready PR with 0 human interventions (K10) |
| G3 | Add a bounded context with one command, verified by the gates | (a) 100% of invalid names (regex on both names, reserved context name, a context that already exists anywhere in the live tree by xtask's rule, FR-14) refused before `make new-context` runs, nothing written; (b) checklist C1–C12 each `DONE` with evidence or `N/A: <reason>`; (d) commit `feat(#N): add <group>/<context> bounded context` hook-valid on the branch the branch rule selects — proven by `common-lib.bats` and contract tests | (c) Docker reachable: the six-stage context gate set green (`ci-preflight`, `ci-static-analysis`, `ci-tests`, `ci-contracts`, `ci-mutation`, `ci-delivery`); Docker unreachable: C12 `ESCALATED` with `make doctor` output (D2); 0 protected files changed; (e) hand-off to review → QA → finish-pr — in the reference run |
| G4 | Every quality bar comes from the template's gates and is tighten-only | (a) `validate-profile.sh` rejects 12 of 12 looser threshold values; (b) 0 plugin components instruct a token of the NFR-4 list (`#[allow`, `#[mutants::skip]`, `#[coverage(off)]`, `exclude_re`, `exclude_globs`, `--ignore-filename-regex`) or a lowered limit outside prohibition lines; an `#[expect]` without `reason` is rejected by the template's static-analysis gate (G2); (c) 0 plugin code paths write a protected file; (d) the governance block violates 0 docs-check rules (1–4) and contains neither invariant (e)'s fixed literal `rust-service-template` nor the fixture's `TEMPLATE_REPOSITORY` name | 0 PRs merged with a relaxed bar (K11) |
| RG | Marketplace release gate (repository constraint from task framing, not a product goal) | `python3 tools/plugin-quality/lint/lint_all.py` 0 findings for all plugins; every `ci.yml` job green with `plugins/rust-backend-sdlc` in `profile-keys-check` and `generalization-audit`; counts 10 commands / 7 agents / 28 skills / 2 meta-guides / 13 scripts + lib / 4 workflows / 9 docs; ≥ 460 bats tests, 0 failures; 0 shellcheck and markdownlint findings | — |

## Target Users

| Segment | Persona | Job to be done | What the plugin must give them | Primary FRs |
| --- | --- | --- | --- | --- |
| Primary: service creator | "Sam", tech lead starting `billing-service` under a mandate to use the template | Get from nothing to a template-clean repository with SDLC tooling and a green first PR | One command; `DONE:` per deterministic step, `NEXT:` per human decision (secrets, labels, branch protection, keep/remove example context, sync flavour); the OpenAPI-title, directory-name and version traps handled; no CI surprise on the first push | FR-11, FR-12, FR-13, FR-4, FR-31 |
| Primary: feature engineer | "Alex", backend engineer who knows Rust but not every template rule (`ValidatedJson`, `Clock`/`UuidGenerator` ports, sibling `tests.rs`, no `mod.rs`) | Ship a feature or a new bounded context without a day of gate-chasing | Issue → plan → implementation that passes gates stage by stage → QA with real HTTP evidence → CI-green PR with 0 open threads; or a precise escalation naming the human decision; resume after any interruption | FR-3, FR-14 to FR-21, FR-23, FR-31 |
| Secondary: reviewer / maintainer | "Jordan", code owner of several services | Approve on design, not on re-running gates or hunting suppressions | PR body with targets run / not run (reason), `Closes #N`, `BMAD FR/NFR Review Gate` status on the head SHA, one conclusion comment per lens, review ledgers, proof that no protected file or bar changed | FR-19, FR-21, FR-35, FR-37 |
| Secondary: platform team | Maintainers of the template and the marketplace | Keep one SDLC contract across services and stacks without forking the template | Plugin consumes the template (runtime lists, repository wins, no protected writes), survives template sync (re-runnable setup), passes marketplace lint/CI | FR-4, FR-8, FR-30, FR-40 to FR-43 |
| Tertiary: autonomous agents | Ralph loops (`bmalph run`), Workflow-tool scripts, the 7 subagents | Execute procedures without human pauses | Machine-readable handles (`ISSUE_URL:`, `ISSUE_NUMBER:`, `BRANCH:`, `SPECS_DIR:`, `---RALPH_STATUS---`, `FR_NFR_REVIEWER:`, `FR_NFR_NEW_FINDINGS:`, `AI_REVIEW_VERDICT:`, `## Verdict:`, `## Status:`), hard iteration limits, degrade paths that never loop | FR-1, FR-22, FR-44 |

## User Journeys

Each journey names its trigger, the flow, the success outcome, the failure branches and the requirements it reveals. Journey ids (J1–J6) are used in Traceability.

### J1 — New service (Sam)

- **Trigger:** `/rs-sdlc-new-service billing-service --description "Billing" --sync-flavour app` in an empty parent directory; plugin installed; `gh auth status` OK.
- **Flow:** (1) S1 `new-service.sh --phase source` probes `gh api repos/<slug> --jq .is_template` for the slug from `--template` > `RUST_SDLC_TEMPLATE_REPO` > `config/new-service.defaults.json`; `true` → `gh repo create <owner>/billing-service --template <slug> --private` (no `--clone`), poll commits 10 × 3 s, clone into `./billing-service`; `false` → empty repository + `git archive HEAD` import, `IMPORT_PENDING:` and the advice `NEXT:` line. (2) S2 label `rust-backend-sdlc` ensured, bootstrap issue N created, `ISSUE_NUMBER: N`. (3) S3 import commit `chore(#N): import template <slug> at <sha7>` on `main` (clone-and-push only). (4) S4 branch `chore/N-initialize-service`. (5) S5 `--phase customize` prints `DONE:` for identity, `bmalph/config.json`, README, CHANGELOG, `specs/` reset, sync flavour and the docs-check citation repair of the deleted flavour's paths. (6) S6 judgment steps printed as `NEXT:`. (7) S7 `make doctor` report-only. (8) S8 `make bootstrap` in the background (log `target/rust-sdlc/new-service/bootstrap.log`, polled every 30 s, ≤ 60 min). (9) S9 `scripts/set-version.sh <v>` when the version differs (container mode: through the FR-1 container route once S8 started the stack). (10) S10 `make generate-openapi-spec`. (11) S11 commit `chore(#N): initialize service from template`. (12) S12 `/rs-sdlc-setup`. (13) S13 commit `chore(#N): add rust-backend-sdlc profile and governance`. (14) S14 title pre-validated, push, `gh pr create` from `.github/pull_request_template.md` with `Closes #N`, hand-off to `/rs-sdlc-finish-pr`.
- **Success:** one `DONE:`/`NEXT:` summary; bootstrap PR with every non-human-gated required check green; remaining `NEXT:` lines are only human decisions.
- **Failure branches:** repository exists with another `origin` → exit 1, nothing created; no Docker → S8 `NOT RUN (no Docker)`, S10 `NEXT`, command stops before S11 with a report; local mode without `--issue` → stops before S11, prints S11–S14 with a `<N>` placeholder; headless without `--sync-flavour` → `SKIP: sync flavour (undecided)` + `NEXT:`; a failing finish-pr counter → `ESCALATED` block.
- **Reveals:** FR-2, FR-4, FR-11, FR-12, FR-13, FR-21, FR-31; NFR-1, NFR-3, NFR-13, NFR-14.

### J2 — New feature end to end (Alex)

- **Trigger:** `/rs-sdlc "Add invoice cancellation: a cancelled invoice cannot be paid; expose REST and GraphQL."` on a configured service (profile committed, governance markers present, `_bmad/` present).
- **Flow:** stage 0 setup-check → stage 1 issue (`ISSUE_URL:`, `ISSUE_NUMBER: 42`) → branch `feat/42-invoice-cancellation` → stage 2 plan (bundle `specs/42-invoice-cancellation/`, `## Constraints` with the literal `(#42)`, readiness "ready", regex clean, commit `docs(#42): add planning bundle 42-invoice-cancellation`) → stage 3 implement (hooks active, `stage-planning-artifacts.sh`, `bmalph implement`, `bmalph run --driver claude-code --no-dashboard` as the only implementer, whose sessions fan independent stories out under the `## Constraints` dispatch rule (DB-free targets in parallel, one serialized DB verify step), per-story commits `feat(#42): story 1.2 <title>`, post-loop subject check, final `make tests-with-coverage`) → stage 4 review (28/28 triage verdicts, code-quality + FR/NFR lenses, security lens because `*.rs` changed, gate loop to zero new findings, `fix(#42): address review gate iteration <n> findings`) → stage 5 QA (`make start`, `/ping` 200 `pong`, `/api/health` 204, REST + GraphQL probes from the committed snapshots and every acceptance criterion, `## Verdict: PASS`) → stage 6 finish-pr (title `feat(#42): add invoice cancellation`, sensor loop to READY).
- **Success:** `=== SDLC RUN REPORT ===` with `result: SUCCESS`, stage table, artifacts (issue URL, `SPECS_DIR:`, PR URL), `degrade_notes`.
- **Failure branches:** QA FAIL → back to stage 3 with the QA report (bounded); Ralph circuit breaker trips → terminal `ESCALATED`; a needed protected change (layer allow-list, `deny.toml` exception, equivalent mutant) → `ESCALATED` naming `approved-config-change` and `ALLOW_PROTECTED_CONFIG_EDIT=1`; a breaking contract change → `ESCALATED` naming `approved-breaking-change`; Docker unreachable at implement, review or QA (with `make.start` mapped) → `ESCALATED` with `make doctor` output (D2); container mode with a stack that cannot start → `ESCALATED` (D25).
- **Reveals:** FR-1, FR-2, FR-3, FR-15 to FR-30, FR-32 to FR-39, FR-44; NFR-3 to NFR-6, NFR-9, NFR-10, NFR-12.

### J3 — New bounded context (Alex)

- **Trigger (standalone):** `/rs-sdlc-new-context billing invoice --issue 57` on the default branch.
- **Flow:** names validated against the live tree (`^[a-z][a-z0-9]*(-[a-z0-9]+)*$` for both names; context not reserved `shared service xtask test-support e2e-tests`; no `crates/invoice` or `crates/*/invoice` directory and no member ending in `invoice/<layer>` or named `invoice-<layer>`) → branch `feat/57-invoice` → `make new-context group=billing context=invoice` (exit 0) → C2–C11 dispatched to `rust-implementer` (each `DONE` with evidence or `N/A: <reason>`) → commit `feat(#57): add billing/invoice bounded context` → C12 context gate set one stage per call (every `make` call backgrounded and polled, FR-1), remediation commits `fix(#57): …`, closing `make validate-configuration` → hand-off to `/rs-sdlc-review` → `/rs-sdlc-qa` → `/rs-sdlc-finish-pr`.
- **Trigger (inside the loop):** the plan stage finds `<group>/<context>` absent from `[workspace].members` and makes story 1 "Scaffold `<group>/<context>`" with C1–C12 as acceptance criteria; no second branch, no command call.
- **Success:** context gate set green, 0 protected files changed, PR finished (or three `NEXT:` lines with `--no-handoff`).
- **Failure branches:** invalid name → exit 1 before any write; `make new-context` non-zero (GNU make reports every recipe failure as exit 2) → classified by the stderr prefix: `new-context refused:` (nothing written) or `new-context could not run:` (crates may already exist; `git status --porcelain` attached) → `ESCALATED` with its output; Docker unreachable at C12 → `ESCALATED` with `make doctor` output (D2); no issue and not on a `<type>/<N>-…` branch → issue stage first (A18).
- **Reveals:** FR-2, FR-14, FR-16, FR-18 to FR-21, FR-23, FR-31, FR-33; NFR-5, NFR-6.

### J4 — Resume after interruption (Alex)

- **Trigger:** the session died during stage 4 iteration 3; Alex runs `/rs-sdlc 42` (or `/rs-sdlc` with no argument on `feat/42-invoice-cancellation`), possibly after `cargo clean` or in a fresh clone.
- **Flow:** stage 0 → read durable records: managed label on issue 42, branch, `docs(#42)` bundle commit, the issue state comment `<!-- rust-sdlc-state -->` (stage, result, `head_sha`, iteration, UTC), PR and `BMAD FR/NFR Review Gate` status; issue/plan/implement count as done when their `head_sha` is an ancestor of `HEAD`; review/QA only when their `head_sha` equals `HEAD`; finish-pr from a live `pr-state.sh` snapshot → resume at review iteration 3 (counters restored from the state comment).
- **Success:** 0 completed stages repeated; the run report's stage table shows resumed stages with their recorded iterations.
- **Failure branches:** fresh clone (no cache) with `gh` reachable → the state comment alone drives `resume_point`, 0 completed stages repeated; `gh` unreachable → the cache `target/rust-sdlc/state/42-invoice-cancellation.json` is the only record; when absent, review and QA re-run and the run reports a degrade note (D10); a new commit since the QA verdict → QA is stale and re-runs.
- **Reveals:** FR-3, FR-19, FR-20, FR-44; NFR-1, NFR-3, NFR-9.

### J5 — PR finishing (Alex or Jordan)

- **Trigger:** `/rs-sdlc-finish-pr` on a branch with an open PR (from the loop, from new-service S14, or a hand-written PR).
- **Flow:** title validated with `COMMIT_TITLE='<title>' make check-commit-message` (issue number never taken from the PR number) → body from the PR template → sensor loop on `pr-state.sh --json`: `FIX` → `ci-fixer` (counter A `ci_fix`) for failing non-human-gated checks, `pr-comment-resolver` (counter B `comment_resolution`) for unresolved threads; `GATE` → `fr-nfr-gate.sh --pr <n> --iteration <c>` on the head (counter C); `REQUEST` → `request-ai-reviews.sh` (counter R); `WAIT` → `pr-state.sh --wait-seconds 540` (counter W); `BLOCKED` → escalate; `READY` → second snapshot confirms → deferred review conclusion posted once → `## Status: ALL-GREEN`.
- **Success:** CI green + FR/NFR gate green on the head SHA + 0 unresolved review threads.
- **Failure branches:** a human-gated check (check names `Protected configuration`, `OpenAPI breaking changes`, `GraphQL breaking changes`, i.e. jobs `validate-configuration`, `openapi-diff`, `graphql-diff`) fails → `BLOCKED` naming the label, never labelled by an agent; no CI → `## Status: SKIPPED-NO-CI` and `SUCCESS-WITH-REPORT`; no AI reviewer configured → `ai-review-loop.sh` findings are the comment source; RUSTSEC advisory without a fixed version → `ESCALATED`.
- **Reveals:** FR-2, FR-21, FR-27, FR-28, FR-34 to FR-39; NFR-3, NFR-5, NFR-6, NFR-10.

### J6 — Re-setup after a template-sync merge (platform team, Alex)

- **Trigger:** a merged `template_sync` PR replaced `CLAUDE.md` and `AGENTS.md` (they are not in `.templatesyncignore`), deleting the governance block.
- **Flow:** the next `/rs-sdlc` halts at stage 0 (and `/rs-sdlc-review` at its marker check) with "run /rs-sdlc-setup on the default branch and commit the result"; the user runs `/rs-sdlc-setup` on the default branch; `inject-governance.sh` restores the block in place; profile shown as a diff unless `--refresh`; commit.
- **Success:** governance restored with 0 changes to user-owned text; second setup run changes nothing.
- **Reveals:** FR-3, FR-4, FR-8; NFR-1, NFR-13.

### Journey Requirements Summary

| Capability revealed | Journeys | FRs |
| --- | --- | --- |
| Deterministic service creation with idempotent re-run and GitHub/local/in-place modes | J1 | FR-11, FR-12, FR-13 |
| Setup that never writes protected files and restores governance | J1, J6 | FR-4 to FR-10 |
| Bounded, resumable stage machine with durable per-stage records | J2, J4 | FR-1, FR-3 |
| Hook-valid commits and titles everywhere | J1, J2, J3, J5 | FR-2 |
| bmalph-compatible planning and staging | J2, J3 | FR-16, FR-17, FR-18 |
| Triage-based multi-lens review with the FR/NFR gate | J2, J3, J4 | FR-19, FR-24, FR-25, FR-29, FR-32, FR-35 |
| Black-box QA over HTTP with evidence | J2, J3, J4 | FR-20, FR-26 |
| PR sensor loop with human-gated awareness | J1, J5 | FR-21, FR-27, FR-28, FR-36 to FR-39 |
| Context scaffolding with checklist and gate set | J3 | FR-14, FR-23, FR-31 |
| Deterministic workflow orchestration | J2, J4, J5 | FR-44 |

## Scope

### In scope (v0.1.0)

| Component | Count | Members | FRs |
| --- | --- | --- | --- |
| Manifest + plugin README | 1 + 1 | `.claude-plugin/plugin.json` (8 keys, no custom keys), `README.md` | FR-40 |
| Commands (`commands/*.md`) | 10 | `rs-sdlc`, `rs-sdlc-setup`, `rs-sdlc-new-service`, `rs-sdlc-new-context`, `rs-sdlc-issue`, `rs-sdlc-plan`, `rs-sdlc-implement`, `rs-sdlc-review`, `rs-sdlc-qa`, `rs-sdlc-finish-pr` | FR-1 to FR-4, FR-11, FR-14 to FR-16, FR-18 to FR-21 |
| Agents (`agents/*.md`) | 7 | `rust-implementer`, `code-quality-reviewer`, `fr-nfr-reviewer`, `qa-manual-tester`, `ci-fixer`, `pr-comment-resolver`, `security-auditor` | FR-22 to FR-29 |
| Skills (`skills/<name>/SKILL.md`) | 28 | 22 mapped from PHP (11 share a template skill's name) + 6 Rust-only | FR-30, FR-31 |
| Meta-guides (`skills/*.md`) | 2 | `AI-AGENT-GUIDE.md`, `SKILL-DECISION-GUIDE.md` | FR-32 |
| Scripts (`scripts/`) | 13 + lib | `lib/common.sh`; `setup-preflight.sh`, `generate-profile.sh`, `validate-profile.sh`, `inject-governance.sh`, `merge-settings.sh`, `new-service.sh`, `stage-planning-artifacts.sh`, `ai-review-loop.sh`, `fr-nfr-gate.sh`, `get-pr-comments.sh`, `post-review-findings.sh`, `pr-state.sh`, `request-ai-reviews.sh` | FR-6 to FR-10, FR-12, FR-17, FR-33 to FR-39 |
| Configuration | 1 | `config/new-service.defaults.json` | FR-13 |
| Workflows (`workflows/*.js`) — epic 8 | 4 | `rs-sdlc-feature`, `rs-sdlc-review-panel`, `rs-sdlc-pr-until-green`, `rs-sdlc-fr-nfr-review`; harness `tests/lib/workflow-harness.mjs` | FR-44 |
| Docs (`docs/`) | 9 | `profile-schema.md`, `setup-walkthrough.md`, `sdlc-loop.md`, `permissions.md`, `degrade-matrix.md`, `release-process.md`, `new-service-walkthrough.md`, `testing/test-strategy.md`, `workflows.md` (epic 8) | FR-41 |
| Tests (`tests/`) | 16 suites | 10 ported (`ai-review-loop`, `common-lib`, `component-counts`, `fr-nfr-gate`, `generate-profile`, `get-pr-comments`, `inject-governance`, `post-review-findings`, `setup-preflight`, `validate-profile`) + `new-service`, `merge-settings`, `stage-planning-artifacts`, `pr-state`, `request-ai-reviews` + `workflows` (epic 8); fixtures and stubs | FR-42 |
| Repository wiring | 3 files | `.claude-plugin/marketplace.json`, root `README.md`, `.github/workflows/ci.yml` | FR-43 |
| Planning bundle | 1 dir | `specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/` | — |

### Delivery order and cut line

Epics deliver usable value in order: (1) package skeleton, `lib/common.sh`, profile scripts, preflight, governance, settings merge, setup command; (2) new-service (script, config, command, `service-scaffolding`); (3) feature-loop commands and agents; (4) skills and meta-guides; (5) review, gate and PR scripts (`ai-review-loop.sh`, `fr-nfr-gate.sh`, `get-pr-comments.sh`, `post-review-findings.sh`, `pr-state.sh`, `request-ai-reviews.sh`, `stage-planning-artifacts.sh`) with their suites; (6) new-context; (7) docs and marketplace/CI wiring; (8) **the workflow epic — decided IN for v0.1.0** (PA-9). Epic 8 contains exactly the 4 `workflows/rs-sdlc-*.js` files, `tests/lib/workflow-harness.mjs`, `tests/workflows.bats` and `docs/workflows.md`; it is the cut line. If it slips, G1–G4 still hold through the command layer (finish-pr's sensor and requester live in epic 5) and the counts drop to 0 workflows / 15 suites / 8 docs / ≥ 415 tests in the same change that removes it.

### Product surface (developer-tool requirements)

- **Language and runtime matrix:** Markdown prompts (commands, agents, skills); bash ≥ 4.4 scripts (the template's `make doctor` floor, `tpl/scripts/doctor.sh:104`) and git ≥ 2.30 (`tpl/scripts/doctor.sh:106`) with python3 ≥ 3.11 (stdlib `tomllib`, `json`; PyYAML optional) fallbacks; node ≥ 20 for the Workflow harness only; Linux and macOS hosts.
- **Installation:** `claude plugin marketplace add VilnaCRM-Org/claude-plugins` then `claude plugin install rust-backend-sdlc@vilnacrm-plugins`; per repository `/rs-sdlc-setup` once per clone and after each template-sync merge.
- **API surface:** 10 slash commands; 13 script CLIs with documented flags and exit codes (FR-6 to FR-39); the profile schema (FR-5); stdout handles (FR-1); commit subjects (FR-2); ledgers and the state comment (NFR-9).
- **Examples:** annotated `# profile-example` fences in `docs/profile-schema.md` and skills; sample transcripts in `docs/setup-walkthrough.md` and `docs/new-service-walkthrough.md`.
- **Migration guide:** not applicable for a new plugin; the setup walkthrough covers re-running setup after a template-sync merge (J6).

### Post-v0.1.0 (growth and vision)

- Widen `tools/plugin-quality` (L22, L25, L18) as a separate change (A6).
- Scripted example-context removal (A5, A8); template drift report from the recorded commit.
- A shared SDLC core across the PHP, React and Rust plugins; non-template workspaces via capabilities (A1).

## Out of Scope

- Changing the template: its gates, thresholds, protected configuration, Makefile, xtask, hooks or repository skills; requesting `approved-config-change` as part of setup. A change the template routes to a human-gated label is escalated, never produced.
- Writing `.claude/settings.json` where `protected-config.toml` lists it; weakening any template `deny` or `ask` rule.
- Copying plugin skills into a service's `.claude/skills/` or plugin scripts into its `scripts/` (docs-check rules 3 and 7, template sync).
- Automated removal of the template's example context in `new-service.sh` (guided `rust-implementer` story only, A5); licence changes (invariant (f) pins `CC0-1.0`).
- Creating secrets, repository variables, approval labels or branch protection; the plugin creates only its own label `rust-backend-sdlc` (A19).
- Running a live Ralph loop or a live GitHub flow from the planning session (the reference run K10 is post-release, A15).
- Rewriting bmalph or Ralph; vendoring `_bmad/` or `.ralph/`; editing `.ralph/.ralphrc` (including its `bypassPermissions` default); passing `--force` to `bmalph implement`.
- Widening `tools/plugin-quality` in the plugin PR (A6); adding `plugins/react-frontend-sdlc` to the CI key-check list (A11).
- Worktree isolation for parallel agents (`isolation: 'worktree'`); non-Claude drivers (Codex and others) as defaults; hosted services or GitHub Apps; Windows hosts.
- Fault injection over HTTP, load testing beyond the template's `smoke-load-tests`, and performance benchmarking of services.
- First-class support for Rust repositories not derived from the template (best effort through absent capabilities, A1).

## Functional Requirements

Conventions. Each FR states a capability, then **Acceptance criteria** (AC-n.m) that name their verifying artifact: a bats suite under `tests/`, a plugin-quality lint rule (`L<n>`), a contract test in `tests/component-counts.bats` (static assertions over Markdown/JS text), a harness scenario in `tests/workflows.bats` (epic 8), or the post-release reference run. "Exit string" is the single stage exit condition text used verbatim in the command, the run report and `docs/sdlc-loop.md`. "Degrade note" is one line collected into `degrade_notes`. Status vocabulary (stage level, closed): `SUCCESS` (exit string met, no degrade note), `SUCCESS-WITH-REPORT` (exit string met with ≥ 1 degrade note: an absent capability skipped or substituted), `ESCALATED` (exit string not met; 7-field block). Mapping to the run report (FR-3), which knows only `result: SUCCESS | ESCALATED`: a stage ending `SUCCESS-WITH-REPORT` yields run `result: SUCCESS` (unless another stage escalates), its notes are appended to `degrade_notes`, and its stage-table row records `met: yes (degraded)`; `SUCCESS` records `met: yes`; `ESCALATED` records `met: no` and ends the run. No other outcome word (`DEGRADED`, `normal`, `note`) is a status; `DEGRADED:` is only the prefix of a degrade-note line.

### Feature-loop orchestration and shared contracts

#### FR-1 — Shared command contract (G2, RG)

- Frontmatter: `description` and `argument-hint` (one or more `[...]` groups); `allowed-tools` only on `rs-sdlc-review` and `rs-sdlc-qa`, value `["Bash", "Read", "Glob", "Grep", "Task"]` (never `Write`/`Edit` on the QA command).
- Body: the 5-H2 spine `Inputs`, `Procedure`, `Loop & exit condition`, `Iteration guard`, `Failure escalation`.
- First action of every command except `rs-sdlc-setup` and `rs-sdlc-new-service`: `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"`; exit 1 → stop with "run /rs-sdlc-setup on the default branch and commit the result".
- `## Iteration guard` states `MAX_ITERATIONS=5`; counters never reset within a run; a loop-back consumes the budget of the stage it re-enters.
- `## Failure escalation` holds the canonical block with exactly these 7 fields: `stage`, `iteration: <n>/5`, `exit_condition: <exit string>`, `status: NOT MET`, `blocking_finding`, `iteration_log`, `recommended_action`, framed by `=== SDLC ESCALATION ===` / `=== END ===`.
- Handles (stdout, one per line, parseable by the orchestrator and workflows): `ISSUE_URL:`, `ISSUE_NUMBER:`, `BRANCH:`, `SPECS_DIR:`, the `---RALPH_STATUS---` block (`STATUS`, `TASKS_COMPLETED_THIS_LOOP`, `FILES_MODIFIED`, `TESTS_STATUS`, `WORK_TYPE`, `EXIT_SIGNAL`, `RECOMMENDATION`), `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<PASS|FAIL>` (closed enum: a reviewer degrade path such as a missing bundle emits `verdict=FAIL` plus a `DEGRADED:` line, fail-closed like FR-35), `FR_NFR_NEW_FINDINGS: <n>`, `AI_REVIEW_VERDICT: PASS|FAIL`, `## Verdict: PASS|FAIL` (QA, review), `## Status: ALL-GREEN|FIXES-READY|SKIPPED-NO-CI|BLOCKED` (finish-pr, ci-fixer), and `DONE:`/`SKIP:`/`UNCHANGED:`/`NEXT:`/`DEGRADED:` lines.
- Execution: every gate runs as `make <target>` resolved through the profile `make.*` map, prefixed with `RUN_IN_CONTAINER=1` when `capabilities.run_in_container: true` (including `git commit` and `git push`, whose hooks run `make pre-commit` and `make pre-push` → `make unit-tests`); a `null` key is never substituted by a raw command.
- Raw (non-`make`) calls — the complete exception list: (1) `cargo tree -i <crate>` and `cargo metadata --format-version 1 --no-deps`; (2) `cargo xtask config-guard --list` (protected list), falling back to a python3 `tomllib` read of `protected-config.toml` when neither the host toolchain nor the container route is available; (3) `env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run -p <crate> <name>` after `make setup-test-db` (the template's `TEST_ENV` form, `tpl/Makefile:41`, so a shell `DATABASE_URL` never points tests at the development database); (4) new-service S9 `scripts/set-version.sh <v>` (it runs `cargo update --workspace` and `cargo metadata` directly, `tpl/scripts/set-version.sh:31-32`); (5) QA's bounded log read `docker compose logs --no-log-prefix --tail 200 app`; (6) the probes `docker info` and `docker compose ps --status running --quiet app`. Calls (1)–(4) run on the host in host mode and, when `capabilities.run_in_container: true`, through the **container route** `docker compose exec -T --user "$(id -u):$(id -g)" app <command>` (the Makefile's `EXEC` shape, `tpl/Makefile:33-36`).
- Container precondition (container mode only): before the first TOOL target, raw container-route call or hooked `git commit`/`git push` of a command, the command checks `docker compose ps --status running --quiet app`; empty output → `make.start` in the background (≤ 900 s, polled). When `docker info` fails, or `make start` fails, or an exec fails because `app` is not running after one restart attempt, the affected targets are recorded `not run (no Docker)` and the outcome is D25: `ESCALATED` in a loop stage and in new-context; in new-service the step is printed as `NEXT:` and the command stops before S11 (J1's no-Docker branch); a degrade note in setup step 8.
- Long calls: no foreground tool call exceeds 600 s. Every `make` call except the foreground allowlist `make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`, and every `git commit` / `git push` (their hooks compile and test the workspace), plus `bmalph run`, runs in the background, logs to `target/rust-sdlc/logs/<stage>-<UTC>.log` and is polled at most every 30 s until it exits (stage budgets: NFR-6); `make ci` is never run as one call. The rule is closed by allowlist, not by a list of slow targets, because any TOOL target (`docs-check` runs `cargo run -p service` four times, `tpl/Makefile:441-446`) can exceed 600 s on a cold `target/`.
- Docker-less classification: GNU make exits 2 for every failing recipe, so a target is classified `not run (no Docker)` — never `failed`, never fed to remediation — by the template's message `This target needs a reachable container engine (docker).` (`tpl/Makefile:80`) or by a failed `docker info` probe taken before a stage that needs Docker (D2).
- Targets-run list: every command that runs gates records `<target>: passed | failed | not run (<reason>)`, reason from the closed set `capability absent`, `no Docker`, `ask rule`, `no toolchain`, `skipped by triage`, `not changed`, `deferred to PR CI` (the last only for the `CI_DELIVERY_TARGETS` that the review and implement stages never run — `build-prod-image`, `image-scan` outside the security lane, `schemathesis-validate`, `smoke-load-tests` — whose PR CI checks finish-pr judges).

**Acceptance criteria**
- AC-1.1 `component-counts.bats` asserts for each `commands/rs-sdlc*.md`: both frontmatter keys, the 5 H2s, `MAX_ITERATIONS=5`, `validate-profile.sh` in the first fenced block (except setup and new-service), and 7 fields in every escalation block; for each command that runs `make`, `git commit` or `git push`: the background-and-poll sentence with the 5-target foreground allowlist and `target/rust-sdlc/logs/`, and the container-precondition sentence naming `docker compose ps --status running --quiet app` and `make.start`; no file under `commands/ agents/ skills/ workflows/` names a raw `cargo` call outside the FR-1 exception list.
- AC-1.2 `lint_all.py` reports 0 findings for L1, L2, L9, L15, L26, L27, L33 on the plugin.
- AC-1.3 `component-counts.bats` asserts each stage's exit string is byte-identical in the stage command, the `rs-sdlc.md` stage table and `docs/sdlc-loop.md` (fixes X1, X2).
- AC-1.4 `component-counts.bats` asserts no file under `commands/ agents/ skills/ workflows/ docs/` contains a `/sdlc-` command token and every command token is one of the 10 command stems (plugin-local substitute for L22, H19). A command token is the ERE `` (^|[[:space:]`(])/(rs-)?sdlc[a-z-]* `` — it starts at line start or after whitespace, a backtick or `(`; a negative case proves that a path such as `workflows/rs-sdlc-feature.js` or `plugins/php-backend-sdlc/commands/sdlc-review.md` is not a command token.

#### FR-2 — Hook-valid git conventions (G1, G2, G3, G4)

- One subject form `<type>(#<issue>): <subject>`, type ∈ `feat fix refactor build chore ci docs style perf test`, single line, matching the template's `^(feat|fix|refactor|build|chore|ci|docs|style|perf|test)\(#[0-9]+\): .*` (`tpl/scripts/check-commit-message.sh:14`).
- Issue-number derivation order: the `ISSUE_NUMBER:` handle → PR title `(#N)` → branch `^[a-z]+/([0-9]+)-` → PR body `Closes #N`; the PR number is never used; no source → `ESCALATED`, nothing committed.
- Branch form `<type>/<issue>-<kebab-slug>` (slug ≤ 40 characters, `is_kebab`), created from the default branch.
- Fixed subjects: plan `docs(#N): add planning bundle <issue>-<kebab-title>`; story `<type>(#N): story <N.M> <title>` (reported, best-effort inside Ralph); review `fix(#N): address review gate iteration <n> findings`; CI fix `fix(#N): resolve <check> failure`; thread fix `fix(#N): address review comment on <path>`; context `feat(#N): add <group>/<context> bounded context`; new service `chore(#N): import template <slug> at <sha7>`, `chore(#N): initialize service from template`, `chore(#N): add rust-backend-sdlc profile and governance`.
- Pre-validation before every `git commit` and every `gh pr create|edit --title`: `COMMIT_TITLE='<subject>' make check-commit-message` when `make.check_commit_message` is mapped, else `is_commit_subject` from `lib/common.sh`.
- Hooks are activated only by `make install-hooks` (when the read-only check `git config --get core.hooksPath` prints nothing); `--no-verify`, `-n`, `--force`, `-f`, `--force-with-lease`, `git -c core.hooksPath` and a `core.hooksPath` write (`git config core.hooksPath …`) are never used. The precise forbidden-pattern set is defined once in NFR-5 and shared by AC-2.3, NFR-4 and NFR-5.
- Commands own every commit and push; agents never commit (FR-22).

**Acceptance criteria**
- AC-2.1 `common-lib.bats`: `is_commit_subject` accepts every fixed subject with `N=1` and rejects `review: gate iteration 2 remediation`, `Apply review suggestion: x`, `feat: x`, `feat(#): x`, `Feat (#1): x` with a space; `derive_issue_number` returns the right number for each source in priority order and ignores a PR number that differs from every source.
- AC-2.2 `component-counts.bats`: every backticked literal matching `^[a-z]+\(#` in `commands/*.md` and `workflows/*.js`, with `<…>` placeholders replaced by `1`/`x`, matches the template regex.
- AC-2.3 `component-counts.bats`: over `commands/ agents/ skills/ workflows/`, each pattern P1–P5 of the NFR-5 set matches only on prohibition lines (lines containing `never`, `Never`, `forbidden` or `decline`); the read-only form `git config --get core.hooksPath` is exempt and required in `rs-sdlc-setup.md` and `rs-sdlc-implement.md`.

#### FR-3 — `/rs-sdlc` orchestrator (G2)

Argument forms: `"<task text>"` starts a run; `<N>`, `#<N>` or an issue URL resumes that issue; no argument on a `<type>/<N>-…` branch resumes issue N.

| # | Stage | Delegates to | Exit string | Guard |
| --- | --- | --- | --- | --- |
| 0 | setup-check | `validate-profile.sh`, marker check, `_bmad/` check | valid profile, governance markers in CLAUDE.md and AGENTS.md, _bmad/ present | halt with "run /rs-sdlc-setup on the default branch and commit the result"; setup is never re-run on a feature branch |
| 1 | issue | `/rs-sdlc-issue` | issue with ≥ 3 testable acceptance criteria and label rust-backend-sdlc exists | 5 |
| — | branch | orchestrator | branch `<type>/<N>-<slug>` checked out from the default branch | — |
| 2 | plan | `/rs-sdlc-plan` | bundle complete, readiness "ready", readiness regex clean, bundle committed | 5 |
| 3 | implement | `/rs-sdlc-implement` | all stories done with EXIT_SIGNAL true, every commit subject valid, coverage green | 5 + Ralph circuit breaker (never reset) |
| 4 | review | `/rs-sdlc-review` | zero new gate findings AND every quality row PASS | 5 |
| 5 | qa | `/rs-sdlc-qa` | QA verdict PASS on HEAD (FAIL routes to stage 3) | 5 |
| 6 | finish-pr | `/rs-sdlc-finish-pr` | CI green + FR/NFR gate green on the head SHA + 0 unresolved review threads | A 5, B 5, C 3, W 6, R 3 |

- **State comment:** after each stage, one comment on the managed issue, marker `<!-- rust-sdlc-state -->`, edited in place (`gh api -X PATCH repos/{owner}/{repo}/issues/comments/{id}`), holding a Markdown table `| stage | result | head_sha | iteration | at |` with one row per completed stage (`at` = UTC ISO-8601); all text passes `redact` (NFR-10). The JSON cache `target/rust-sdlc/state/<issue>-<kebab-title>.json` mirrors it.
- **Resume rules (PA-7):** issue, plan and implement are done when recorded with `result: PASS` and `git merge-base --is-ancestor <head_sha> HEAD`; review and QA only when `head_sha` equals `HEAD`; finish-pr is re-derived from a live `pr-state.sh` snapshot; iteration counters resume from the recorded value. The rules are computed by `resume_point` in `lib/common.sh` (FR-33) from the state-comment table (or the cache), so they are bats-tested, not only prompt text. Source order: the state comment when `gh` is reachable (a fresh clone or a cleaned `target/` resumes from it alone), else the cache; without `gh` and without the cache, review and QA re-run (degrade note, D10).
- **Run report:** `=== SDLC RUN REPORT ===` with exactly 8 fields — `task`, `branch`, `result: SUCCESS | ESCALATED`, `stages` (the stage table `stage | iterations used | exit string | met`, `met` ∈ `yes`, `yes (degraded)`, `no`), `artifacts` (issue URL, `SPECS_DIR`, PR URL), `degrade_notes`, `targets_not_run`, `escalation` (the failing stage's block or `none`) — then `=== END ===`; emitted on every exit path. Stage outcomes map to `result` per the FR conventions (a `SUCCESS-WITH-REPORT` stage keeps `result: SUCCESS` and adds its notes).

**Acceptance criteria**
- AC-3.1 `component-counts.bats`: `rs-sdlc.md` holds the 8-row table above with the exact exit strings and guards, and the run-report block with exactly the 8 field names `task`, `branch`, `result`, `stages`, `artifacts`, `degrade_notes`, `targets_not_run`, `escalation`, the three `met` values and the SUCCESS-WITH-REPORT mapping sentence.
- AC-3.2 `component-counts.bats`: `rs-sdlc.md` holds a resume table with one row per stage naming its durable record and validity rule (ancestor / equal / live).
- AC-3.3 `component-counts.bats`: the state-comment marker and the 5 column names appear identically in `rs-sdlc.md` and `docs/sdlc-loop.md`.
- AC-3.4 resume and termination proofs, split by the artifact that implements them: (a) `common-lib.bats` cases on `resume_point`: a fresh clone with no `target/rust-sdlc/state/` cache and a state comment recording issue/plan/implement/review PASS resumes at QA with 0 repeated stages; a resume at review iteration 3 restores the counter; a new commit after the QA verdict marks QA stale; an implement `head_sha` that is not an ancestor of `HEAD` re-runs implement; (b) harness scenarios (FR-44, the workflow path) cover a fresh run ending `SUCCESS`, an implementer reply `status: BLOCKED` ending `ESCALATED` with the 7-field block (the workflow analogue of the Ralph breaker, which the workflow never runs), and a `rs-sdlc-pr-until-green` re-entry with `carry` that resets 0 counters; (c) the command-path breaker trip is a contract test (AC-18.2).
- AC-3.5 reference run (K10): `result: SUCCESS` with 0 human interventions.

### Setup and project profile

#### FR-4 — `/rs-sdlc-setup` (G1, G4)

Argument hint `[--refresh] [--with-qa-network] [--print-settings] [--exec host|container]`. Procedure, in this order:

1. `setup-preflight.sh --report` (FR-10); any FAIL → stop with the table.
2. `make bmalph-setup` only when `_bmad/` is absent, `make.bmalph_setup` is mapped and `git status --porcelain --untracked-files=no` is empty; on a dirty tree: `DEGRADED: make bmalph-setup not run (tracked changes: <files>)` + `NEXT: commit or stash, then make bmalph-setup`, and continue; after it runs, re-check the bmalph version floor.
3. `generate-profile.sh` (FR-6): `--refresh` passes through; `--exec host` → `--run-in-container false`, `--exec container` → `--run-in-container true`; without `--exec` no flag is passed and FR-6's precedence applies (existing profile value, then detection).
4. `validate-profile.sh` (FR-7); on failure regenerate with `--refresh`, at most 5 attempts, then escalate.
5. `inject-governance.sh` (FR-8).
6. `merge-settings.sh` (`--with-qa-network`, `--print` from `--print-settings`) (FR-9). **Protected-settings rule:** setup never writes `.claude/settings.json` when `protected-config.toml` lists it; the allowlist goes to the git-ignored `.claude/settings.local.json` or is printed.
7. `make install-hooks` when `git config --get core.hooksPath` is empty and the target is mapped.
8. `make docs-check`, in the background and polled (FR-1; it compiles and runs the `service` binary four times), when `capabilities.run_in_container: false` and `cargo` is on `PATH`, or when `capabilities.run_in_container: true` and the FR-1 container precondition brought `app` up; otherwise (no toolchain, Docker unreachable, or the stack cannot start, D3/D25) a degrade note — never reported as passed.
9. Summary: files written, `UNCHANGED:` files, degrade notes, and "commit `.claude/rust-sdlc.yml`, `CLAUDE.md` and `AGENTS.md` together in one commit", because CI's docs-check sees only committed files (its Markdown set comes from `git ls-files`) and the governance block backticks `.claude/rust-sdlc.yml`, which must therefore be committed with it; a warning when the current branch is not the default branch.

Exit string: preflight without FAIL, profile valid, markers in both files, allowlist present or printed, docs-check passed or degraded with a note.

**Acceptance criteria**
- AC-4.1 `component-counts.bats`: `rs-sdlc-setup.md` lists steps 1–9 in this order, states the protected-settings rule, the `--exec` → `--run-in-container` pass-through and the step-8 background/container conditions.
- AC-4.2 `merge-settings.bats`: with `protected-config.toml` listing `.claude/settings.json`, the file's checksum is unchanged under every flag combination.
- AC-4.3 bats over the stub fixture (`generate-profile.bats` + `inject-governance.bats` + `merge-settings.bats` in setup order): after committing the first run's output, a second run leaves `git status --porcelain` empty and prints only `UNCHANGED:` lines.
- AC-4.4 `setup-preflight.bats`: a dirty tracked tree is reported with the files listed; `component-counts.bats`: the `DEGRADED:`/`NEXT:` wording is present in the command.

#### FR-5 — Profile schema `.claude/rust-sdlc.yml` (G1, G4)

`schema_version: 1`. Key set fixed here (PA-1); every key documented in `docs/profile-schema.md` with type, required/optional, default, detection source and consumers. "Null means absent; omitted means error" for every `make.*` key.

| Group | Keys (type; R = required, O = optional) |
| --- | --- |
| root | `schema_version` (int, R, `1`) |
| `project` | `project.name` (string R; checkout directory = Compose project), `project.repo` (`owner/name` or null, R), `project.default_branch` (string R), `project.description` (string O; `[workspace.package].description`) |
| `rust` | `rust.toolchain` (quoted string R; `rust-toolchain.toml` channel), `rust.edition` (quoted string R), `rust.msrv` (quoted string O; `rust-version`) |
| `template` | `template.repository` (`owner/name` or null, O; `TEMPLATE_REPOSITORY:` line of the kept sync workflow), `template.sync_flavour` (enum `app pat both none`, R), `template.source_commit` (string or null, O; from an import commit subject when present) |
| `framework` | `framework.http` (enum `axum` or null, R), `framework.openapi` (bool R), `framework.graphql` (bool R) |
| `persistence` | `persistence.engine` (enum `postgresql` or null, R), `persistence.migrations_dir` (string or null, R), `persistence.offline_metadata` (bool R; `.sqlx/` present) |
| `architecture` | `architecture.crates_root` (string R), `architecture.composition_root` (string R), `architecture.layers` (list R), `architecture.bounded_contexts` (list of `<group>/<context>` R, may be empty; derivation in FR-6; informational — name validation reads the live tree, FR-14), `architecture.shared_crates` (list R) |
| `service` | `service.port` (int 1–65535 R; `.env` `APP_PORT`, default 8081), `service.base_url` (string R), `service.liveness_path` (R, `/ping`), `service.readiness_path` (R, `/api/health`), `service.graphql_path` (R or null), `service.docs_path` (R or null), `service.openapi_snapshot` (path or null R), `service.graphql_snapshot` (path or null R) |
| `make` | key = template target with `-` → `_` (PA-2), value = target name or null: `ci`, `ci_list`, `ci_preflight`, `ci_static_analysis`, `ci_tests`, `ci_contracts`, `ci_mutation`, `ci_delivery`, `ci_cli`, `doctor`, `bootstrap`, `install_hooks`, `bmalph_setup`, `start`, `format`, `format_check`, `lint_code`, `static_analysis`, `complexity`, `architecture`, `check_crate_isolation`, `validate_architecture_model`, `check_security`, `unused_dependencies`, `docs_check`, `validate_invariants`, `validate_configuration`, `secrets_scan`, `unit_tests`, `integration_tests`, `tests_with_coverage`, `e2e_tests`, `mutation_tests_diff`, `setup_test_db`, `create_migration`, `migrate`, `migrate_rollback`, `sqlx_prepare`, `validate_sqlx_metadata`, `generate_openapi_spec`, `generate_graphql_spec`, `validate_contract_snapshots`, `validate_openapi_spec`, `openapi_diff`, `graphql_diff`, `schemathesis_validate`, `image_scan`, `smoke_load_tests`, `load_tests`, `new_context`, `check_commit_message`; plugin-substitutable (null → bundled script): `ai_review_loop`, `pr_comments`, `fr_nfr_gate`, `post_review_findings` — 55 keys, all R (no `make.logs`: the template's `logs` target follows forever, `tpl/Makefile:165-167`, and is never invoked by a plugin component, PA-16) |
| `quality` | the 12 tighten-only keys of NFR-4 (int, R) |
| `ci` | `ci.provider` (enum `github-actions` or null, R), `ci.workflows` (list R), `ci.required_checks` (list of GitHub check names R; the "Check name" cells of the rows whose "Required" cell is `yes` in `docs/repository-settings.md` and, when present, the service-owned `docs/repository-settings-service.md` — union, de-duplicated, document order; e.g. `'Protected configuration'`), `ci.human_gated` (list of check names R, ⊆ `ci.required_checks`, same name space; PA-6: the jobs named by the "Labels to create" table mapped to their "Check name" — today `Protected configuration`, `OpenAPI breaking changes`, `GraphQL breaking changes`), `ci.base_ref` (string R, `origin/<default_branch>`) |
| `review` | `review.coderabbit` (bool R), `review.reviewers` (list ⊆ `coderabbit cubic qodo qlty sonarcloud`, R; `[coderabbit]` when `.coderabbit.yaml` exists, else `[]`), `review.ai_review_agents` (list R, default `[claude]`), `review.request_changes_blocking` (bool R) |
| `capabilities` | `capabilities.template_derived`, `capabilities.run_in_container` (precedence: generator flag > existing profile value > detection, FR-6), `capabilities.structurizr`, `capabilities.load_testing`, `capabilities.mutation_testing`, `capabilities.dynamic_security_testing`, `capabilities.publish_pr_comments`, `capabilities.protected_config`, `capabilities.template_sync` (bool, all R) |

**Acceptance criteria**
- AC-5.1 `validate-profile.bats`: a profile missing any one required key (one case per group, plus 3 `make.*` keys) fails with a line naming the key; the same key set to `null` (where allowed) passes.
- AC-5.2 `component-counts.bats`: every key above appears backticked in `docs/profile-schema.md`; every profile-key candidate in any skill's `## Profile keys consumed`, any agent's `## Profile keys consumed` and any command appears in the schema (covers the non-L25 namespaces `rust`, `service`, `template`, H19). A candidate is a backticked token matching `^(schema_version|(project|rust|template|framework|persistence|architecture|service|make|quality|ci|review|capabilities)\.[a-z0-9_<>]+)$` whose last dot-segment is not a file extension (`toml`, `dsl`, `md`, `yml`, `yaml`, `json`, `rs`, `sh`, `mk`), so `architecture.toml`, `persistence.rs`, `workspace.dsl`, `clippy.toml` and `tests.rs` are never candidates; a negative case pins these five.
- AC-5.3 CI `profile-keys-check` passes for `plugins/rust-backend-sdlc`.

#### FR-6 — Profile generation `scripts/generate-profile.sh` (G1)

Usage `generate-profile.sh [--refresh] [--stdout] [--run-in-container true|false] [TARGET_DIR]` (default `$PWD`).

- Detection reads only files, never runs `cargo` or `make`: `Cargo.toml` (`[workspace].members`, `[workspace.package]`, dependency names for `axum`, `utoipa`, `async-graphql`, `sqlx` features), `rust-toolchain.toml`, `architecture.toml` (layers), `protected-config.toml`, `Makefile` + `make/service.mk` targets (regex `^[a-zA-Z0-9_-]+:.*## `), `CI_*_TARGETS` assignments (`tpl/Makefile:89-95`) and `CI_STAGES` (`tpl/make/gates.mk:37`), `.github/workflows/*.yml`, `docs/repository-settings.md` (workflow job tables, "Labels to create" table), `docs/repository-settings-service.md` when present (the service's own job tables, same format), `.coderabbit.yaml`, `template-sync-{app,pat}.yml`, `.env` (`APP_PORT`), `.sqlx/`, `migrations/`, `workspace.dsl`, `tests/Load/`, `.github/openapi-spec/spec.yaml`, `.github/graphql-spec/spec`. TOML via python3 `tomllib` only.
- A missing source never fails generation: the key becomes `null`/`false`/`[]`; `make.*` maps only targets that exist; `quality.*` are emitted at the shipped defaults (detected values are never lowered into the profile).
- `capabilities.template_derived` is true when all A1 markers exist (`rust-toolchain.toml`, `architecture.toml`, `protected-config.toml`, `xtask/Cargo.toml`, `make/gates.mk`, `crates/service/Cargo.toml`, `workspace.dsl`, and `CI_PREFLIGHT_TARGETS` starting with `validate-configuration`).
- `architecture.bounded_contexts` = the `<g>/<c>` of every `[workspace].members` entry matching `crates/<g>/<c>/{domain,application,infrastructure}` with `<g>` ≠ `shared`, de-duplicated, in member order. It **includes** `internal/health-check` (it has the three layers and its name collides for xtask like any context); consumers that want feature contexts only filter the `internal` group. The key is informational: `validate_context_name` never reads it (FR-14).
- `ci.required_checks`: for each table under "Required status checks" of `docs/repository-settings.md` and, when the file exists, `docs/repository-settings-service.md`, the "Check name" cell of every row whose "Required" cell is `yes`; union in document order, de-duplicated.
- `ci.human_gated`: parse the "Labels to create" table of `docs/repository-settings.md` for both sentence forms — "without it the job `<j>` fails" and "without it the jobs `<a>` and `<b>` fail" — then map each job id to its "Check name" through the job tables of either document; a job id with no table row is dropped with a `WARN:` on stderr. Values are check names (the strings GitHub reports as check-run `name`), never job ids.
- `capabilities.run_in_container` precedence: `--run-in-container true|false` > the value in an existing profile (kept on `--refresh`, so a hand flip survives) > detection (true when `docker info` exits 0 and no `cargo` is on `PATH`, else false).
- Emission (H9): block style, 2-space indentation, sequences indented under their key, `yaml_squote` for repository-derived strings, bare enums/targets/ints/bools/`null`, quoted versions, keys in schema order, no `---`, exactly one trailing newline.
- With an existing profile and no `--refresh`: print a unified diff against the fresh detection to stdout, keep the file, exit 0 (`UNCHANGED:` when identical); `--refresh` writes atomically (`mktemp .claude/.rust-sdlc.yml.XXXXXX` + `mv`); `--stdout` writes nothing. Refuses a symlinked or non-regular `.claude/rust-sdlc.yml` (exit 1). Exit 0 success, 1 failure, 2 usage.

**Acceptance criteria**
- AC-6.1 `generate-profile.bats` on the stub fixture: the output equals a golden profile byte for byte; on a fixture stripped of each optional source the corresponding key is `null`/`false` and exit is 0.
- AC-6.2 `generate-profile.bats`: the output passes `validate-profile.sh`; with yamllint 1.38.0 and Prettier 3.9.10 present (CI), `yamllint -c <fixture>/.yamllint.yml` and `prettier --check` pass (K7).
- AC-6.3 `generate-profile.bats`: a `cargo`/`make` stub that records calls shows 0 invocations; the diff/keep, `--refresh`, `--stdout` and symlink-refusal paths each have a case; parity cases re-run 3 cases with `SDLC_FORCE_PYTHON_YAML=1`.
- AC-6.4 `component-counts.bats`: every key documented in `docs/profile-schema.md` is emitted by the golden profile (fixes X18).
- AC-6.5 `generate-profile.bats` (CI derivation): over a fixture copy of the template's real `docs/repository-settings.md` tables, `ci.human_gated` equals exactly `Protected configuration`, `OpenAPI breaking changes`, `GraphQL breaking changes` (singular and plural label sentences both parsed) and each is in `ci.required_checks`; non-required rows (`mutation-shard`, `bats-group`, `codeql`) are absent; a `docs/repository-settings-service.md` fixture adding one `Required: yes` row adds exactly that check name; check names with spaces are emitted single-quoted and pass yamllint.
- AC-6.6 `generate-profile.bats` (container switch): `--run-in-container true` on a host with `cargo` emits `true`; an existing profile holding `false` keeps `false` under `--refresh` with Docker reachable and no `cargo`; with neither flag nor profile, the docker/cargo stubs drive detection in all four combinations.
- AC-6.7 `generate-profile.bats` (contexts): the fixture's members yield `billing/invoice` and `internal/health-check` and never a `shared/*` entry.

#### FR-7 — Profile validation `scripts/validate-profile.sh` (G1, G4)

Usage `validate-profile.sh [PROFILE_FILE]` (default `.claude/rust-sdlc.yml` in `$PWD`).

- Checks: parseable YAML (clean `[rust-sdlc]` diagnostic, no traceback); `schema_version == 1`; every required key present; enum legality; list types; `project.repo` matches `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` or null; `service.port` 1–65535; every `make.*` key present (null legal) and each non-null value matches `^[a-zA-Z0-9_-]+$`; the 12 `quality.*` keys are non-negative integers within tighten-only bounds (NFR-4).
- Output: one line per violation, `VIOLATION: <key>: <reason> (<value> vs bound <bound>)`; exit 0 valid, 1 any violation, 2 usage. Numeric comparison uses the wrap-safe helpers (`strip_zeros`, `num_gt`, `num_lt`), so a 19+-digit value cannot wrap.

**Acceptance criteria**
- AC-7.1 `validate-profile.bats`: 12 rejection cases, one per `quality.*` key, each loosened by 1 (floors 99, ceilings 1), each naming its key; a 20-digit ceiling value is rejected, not wrapped.
- AC-7.2 `validate-profile.bats`: `make.check_security: null` passes; an omitted `make.check_security` fails; `make.start: 'start; rm -rf /'` fails the target regex.
- AC-7.3 `validate-profile.bats`: malformed YAML exits 1 with a message naming the file; parity cases with `SDLC_FORCE_PYTHON_YAML=1`.

#### FR-8 — Governance injection `scripts/inject-governance.sh` (G1, G4)

Usage `inject-governance.sh [--diff] [TARGET_DIR]`.

- Maintains one block between `<!-- rust-backend-sdlc:begin -->` and `<!-- rust-backend-sdlc:end -->` in `CLAUDE.md` and `AGENTS.md`; algorithm ported from php (replace in place, fence-aware marker matching, CRLF-tolerant, duplicate pairs collapsed into the first position, orphan or out-of-order markers removed and a fresh block appended, missing file created holding only the block); atomic writes; `--diff` writes nothing.
- Placement: never between `<!-- verification:start -->` and `<!-- verification:end -->` in `AGENTS.md` (H8); a new block is appended at the end of the file.
- Content (byte-stable: cites profile keys, never values): an H2 `rust-backend-sdlc governance (managed block — do not edit between markers)` and bullets covering (1) the skill-triage gate with the verbatim rule "every skill verdict recorded, no silent skips"; (2) repository rules first (`AGENTS.md` and `.claude/skills/README.md` win over plugin skills); (3) tighten-only bars (profile `quality` keys; files listed by `protected-config.toml`); (4) make-only execution, verification order = the AGENTS.md verification section; (5) commit subject form `type(#issue): subject`, hooks never bypassed; (6) protected configuration is escalated, never edited; (7) the plugin's commands named in plain prose.
- docs-check safety (H2–H6): no backticked slash command; backticked paths only from the safe list `AGENTS.md`, `CLAUDE.md`, `protected-config.toml`, `.claude/skills/README.md`, `.claude/rust-sdlc.yml`; no backticked or fenced `make <x>`; no numbered list or fence naming ≥ 3 gate targets (the block has no numbered lists or fences at all); never the template's repository name; passes markdownlint (template config) and typos.
- Invariant (e) uses a fixed literal: `tpl/scripts/check-invariants.sh:50-51` assembles `rust-service-` + `template` and greps `AGENTS.md`, `CLAUDE.md`, `Makefile`, `Dockerfile`, compose files and the trees `.github/workflows scripts tests crates xtask features .claude/skills make` for it (`rule_e`, l.711-735); it never reads the `TEMPLATE_REPOSITORY:` line. The block and every text the plugin writes into `CLAUDE.md` or `AGENTS.md` therefore exclude that literal, independent of the slug a given service was created from.

**Acceptance criteria**
- AC-8.1 `inject-governance.bats`: two runs → byte-identical files; content outside the markers keeps its sha256; duplicate, orphan, out-of-order, fenced-marker and CRLF fixtures each repair to exactly one block; `--diff` leaves checksums unchanged.
- AC-8.2 `inject-governance.bats` static docs-check cases over the injected block: 0 code spans starting with `/`; every backticked token with a `/` or a file extension is in the safe list; 0 `make <x>` spans; 0 numbered lists and 0 fences; the injected block, and the whole of `CLAUDE.md` and `AGENTS.md` after injection minus the fixture's pre-existing text, contain neither the literal `rust-service-template` (invariant (e)'s actual token; the test assembles it from two halves like the template) nor the repository name from the fixture's `TEMPLATE_REPOSITORY: acme/rust-template` line; the block sits outside the verification markers.
- AC-8.3 `inject-governance.bats` (K7, CI): markdownlint-cli2 with the fixture's `.markdownlint-cli2.yaml` and typos with its `_typos.toml` pass on both files.

#### FR-9 — Permission allowlist `scripts/merge-settings.sh` (G1, G4)

Usage `merge-settings.sh [--print] [--with-qa-network] [--file local|shared] [TARGET_DIR]` (default `--file local`).

- Entries merged into `permissions.allow`: `Bash(make:*)`, `Bash(RUN_IN_CONTAINER=1 make:*)`, `Bash(git status:*)`, `Bash(git diff:*)`, `Bash(git log:*)`, `Bash(git add:*)`, `Bash(git commit:*)`, `Bash(git push:*)`, `Bash(git switch:*)`, `Bash(gh:*)`, `Bash(bmalph:*)`, `Bash(<absolute plugin root>/scripts/:*)`, `Bash(docker compose ps:*)`, `Bash(docker compose logs:*)` (both already allowed by the template) and one container-route entry for the FR-1 `docker compose exec -T --user … app` form (exact spelling fixed in architecture with PA-14); with `--with-qa-network` also loopback-only `curl` entries for `http://localhost:<service.port>/` and `http://127.0.0.1:<service.port>/` in the URL-first form `qa-manual-tester` uses (exact spelling fixed in architecture, PA-14).
- Target `--file local` = `.claude/settings.local.json` (git-ignored by the template); `--file shared` = `.claude/settings.json` and is refused (exit 1, merged JSON printed instead) when `protected-config.toml` lists `.claude/settings.json` or the file is hook-guarded.
- Merge semantics: union into `permissions.allow` only; existing keys, entries and their order preserved; never touches `deny`, `ask`, `hooks`, `env`; JSON validated before an atomic replace; 2-space indentation, trailing newline; refuses symlinks; second run byte-identical, prints `UNCHANGED:`. `--print` writes nothing. Exit 0, 1 refusal/failure, 2 usage.

**Acceptance criteria**
- AC-9.1 `merge-settings.bats`: protected `.claude/settings.json` untouched under `--file shared` (exit 1, JSON on stdout) and under default mode.
- AC-9.2 `merge-settings.bats`: pre-existing `allow`/`deny`/`ask`/`hooks` content preserved; union de-duplicated; second run byte-identical; `--with-qa-network` adds only loopback URLs with the profile port; malformed existing JSON → exit 1, file unchanged.
- AC-9.3 `merge-settings.bats`: no entry contains `bypassPermissions`, `defaultMode`, or a non-loopback host.

#### FR-10 — Preflight `scripts/setup-preflight.sh` (G1)

Usage `setup-preflight.sh [--report]`. Checks in order, each `PASS|WARN|FAIL|INFO <check> <detail> <remediation>`: git repository; `gh` ≥ 2.0 and `gh auth status`; `claude` present and `--restricted` supported (≥ 2.1.248, FAIL otherwise, PA-10); bmalph ≥ 2.11.0, or WARN "will be installed by make bmalph-setup" when absent and `bmalph-setup` is a Makefile target and node ≥ 20 and npm exist, FAIL otherwise; `bmalph doctor` when `_bmad/` exists; python3 ≥ 3.11 with `tomllib`; YAML backend (mikefarah yq v4 by the `!!seq` probe, or python3 + PyYAML); JSON backend (jq or python3); GNU make ≥ 4.0; bash ≥ 4.4 and git ≥ 2.30 (the template's `make doctor` floors, `tpl/scripts/doctor.sh:103-106`; the plugin also relies on `git merge-base --is-ancestor` and `git check-ignore --stdin`); template markers (A1; WARN when absent); tracked-tree cleanliness (INFO listing files); Docker reachability (INFO; input to `capabilities.run_in_container`). Default mode stops at the first FAIL; `--report` runs all and prints the table. Exit 0 when no FAIL, 1 otherwise.

**Acceptance criteria**
- AC-10.1 `setup-preflight.bats`: under-version stubs (`gh 1.9`, `bmalph 2.10.0`, `claude` without `--restricted`, python 3.10, make 3.81, git 2.29) each FAIL with the named remediation; a bash 4.3 run (simulated through the test hook `RUST_SDLC_BASH_VERSION`, because `BASH_VERSINFO` is read-only) FAILs with "install Bash 4.4 or newer".
- AC-10.2 `setup-preflight.bats`: bmalph absent + `bmalph-setup` target + node 20 + npm → WARN and exit 0; bmalph absent without them → FAIL.
- AC-10.3 `setup-preflight.bats`: a kislyuk `yq` stub (prints `"array"`) without PyYAML → YAML FAIL; with PyYAML → PASS via fallback.

### Service and context lifecycle

#### FR-11 — `/rs-sdlc-new-service` (G1)

Argument hint `[<name>] [--description <text>] [--owner <org>] [--visibility private|public] [--template <owner/repo> | --template-path <dir> | --in-place] [--dest <parent-dir>] [--version <x.y.z>] [--intro <text>] [--sync-flavour app|pat] [--keep-specs] [--issue <N>] [--exec host|container] [--dry-run]`.

- Validates `<name>` with `is_kebab` (≤ 50 characters) before any action; modes: GitHub (`--template`, configured default, or `--in-place` with a GitHub `origin` and `gh auth status` OK) and local (`--template-path`, or `--in-place` without a GitHub `origin`).
- Runs the ordered sequence S1–S14 of the brief (table "Ordered sequence run by the command") with the same EXECUTED/NEXT rules: S1 source, S2 label + bootstrap issue (`ISSUE_NUMBER:`), S3 import commit (clone-and-push only), S4 branch `chore/<N>-initialize-service`, S5 customize, S6 judgment steps as `NEXT:` (keep example context by default; secrets, variables and labels read from the new repository's `docs/new-service.md`; branch protection from `docs/repository-settings.md`), S7 `make doctor` report-only, S8 `make bootstrap` backgrounded (≤ 60 min, polled every 30 s, log `target/rust-sdlc/new-service/bootstrap.log`) or `NOT RUN (no Docker)`, S9 `scripts/set-version.sh <v>` when the version differs (host mode: on the host; container mode: through the FR-1 container route after S8 started the stack; Docker unreachable: printed as `NEXT:`), S10 `make generate-openapi-spec` (backgrounded, FR-1), S11 commit, S12 `/rs-sdlc-setup --exec <host|container>` (the command's resolved `--exec` value, so S12 records it as `capabilities.run_in_container`), S13 commit, S14 title check, push, `gh pr create` (body from `.github/pull_request_template.md`: `Description`, `Related issue` with `Closes #N`, `Type of change`, `How it was tested`, `Checklist`), hand-off to `/rs-sdlc-finish-pr`.
- `--dry-run` prints `WOULD:` lines, creates nothing on GitHub, writes nothing.
- `--exec` default: `container` when Docker is reachable and no host `cargo`, else `host`; passed to S12 as `/rs-sdlc-setup --exec <value>` → `generate-profile.sh --run-in-container true|false`, so the choice is recorded as `capabilities.run_in_container` and survives later `--refresh` runs (FR-6 precedence).
- Defaults of the optional identity flags: `--description` = `<name>`; `--owner` = the login printed by `gh api user --jq .login` (GitHub mode only); `--intro` = the description; `--version` = `default_version` of `config/new-service.defaults.json`.
- Ends with one `DONE:`/`NEXT:` summary; exit string "S1–S14 executed or printed as NEXT, bootstrap PR handed to finish-pr (GitHub mode)".

**Acceptance criteria**
- AC-11.1 `component-counts.bats`: `rs-sdlc-new-service.md` lists S1–S14 in order with the EXECUTED/NEXT condition of each (S9's three modes included), the three fixed commit subjects, S12's `--exec` pass-through, the four identity defaults, and the hand-off.
- AC-11.2 `new-service.bats` (via the script, FR-12) covers the GitHub-template, clone-and-push (`is_template=false`), local, in-place and dry-run modes with gh/git stubs recording calls.
- AC-11.3 post-release (K9, K13): walkthrough recorded in `docs/new-service-walkthrough.md` with hands-on ≤ 15 min and a green bootstrap PR.

#### FR-12 — `scripts/new-service.sh` (G1)

Usage `new-service.sh --name <n> [--description <text>] [--template <owner/repo> | --template-path <dir> | --in-place] [--owner <org>] [--visibility private|public] [--dest <dir>] [--version <x.y.z>] [--intro <text>] [--sync-flavour app|pat] [--keep-specs] [--phase source|customize|all] [--dry-run]`.

- Source resolution: at most one of `--template`, `--template-path`, `--in-place` (two → exit 2); none → GitHub mode with the template slug resolved per FR-13 (`RUST_SDLC_TEMPLATE_REPO`, then `config/new-service.defaults.json`). Defaults: `--description` = `<name>`; `--owner` = `gh api user --jq .login` (GitHub mode; an empty login → exit 1 "pass --owner"); `--intro` = the description; `--version` = `default_version`; `--visibility` = `default_visibility`.

- `--phase source`: probe `gh api repos/<slug> --jq .is_template`; `true` → `gh repo create <owner>/<name> --template <slug> --private|--public` (no `--clone`), poll `gh api repos/<owner>/<name>/commits?per_page=1` up to `poll_attempts` × `poll_interval_seconds` (FR-13), `gh repo clone` into `<dest>/<name>`; `false` → empty `gh repo create`, `gh repo clone <slug> <tmp> -- --depth 1`, `git -C <tmp> archive HEAD | tar -x -C <dest>/<name>`, `git init -b main`, `origin` set, `IMPORT_PENDING: <slug>@<sha>` + `NEXT: ask the template owner to enable Settings > Template repository`; `--template-path` → same `git archive HEAD` import, refused with exit 1 when the template checkout has uncommitted tracked changes (PA-3); `--in-place` → `SKIP: source (in place)`. Re-run: repository exists and `<dest>/<name>` is a clone with matching `origin` → `SKIP: source (exists)`; repository exists otherwise → exit 1; `gh repo create` never runs twice.
- `--phase customize` (deterministic `docs/new-service.md` steps, each printing `DONE:`/`SKIP:`/`UNCHANGED:`): `[workspace.package]` `description` and `repository` only (other tables untouched); version (`UNCHANGED: version <v>` or `NEXT: scripts/set-version.sh <v>`); `bmalph/config.json` `name`/`description` (Prettier-clean JSON); README title, badges (owner/name substituted) and intro; `CHANGELOG.md` reset to the cocogitto skeleton; `specs/` reset = delete every bundle directory the source commit shipped (enumerated at runtime, never named in the script), skipped with `--keep-specs`; sync flavour = keep one workflow + guide pair, delete the other pair, append both deleted paths to `.templatesyncignore`; without `--sync-flavour`: `SKIP: sync flavour (undecided)` + `NEXT: re-run with --sync-flavour app|pat`.
- **Docs-check citation repair** (sub-step right after the flavour deletion; template defect: `tpl/docs/extension-seams.md:82` backtick-cites both `.github/TEMPLATE_SYNC_APP.md` and `.github/TEMPLATE_SYNC_PAT.md`, so deleting either guide exactly as `docs/new-service.md` §9 says yields `(3) docs/extension-seams.md:82: .github/TEMPLATE_SYNC_PAT.md does not exist and no git-ignore rule matches it` — reproduced on a template copy): scan the tracked Markdown set docs-check reads (`git ls-files '*.md'` minus `CHANGELOG.md` and `specs/**`) for code spans naming either deleted path (`.github/workflows/template-sync-<other>.yml`, `.github/TEMPLATE_SYNC_<OTHER>.md`); rewrite each such span to the bare file name (the convention the guides and `docs/new-service.md` already use); append each edited file once to `.templatesyncignore` (otherwise the next sync restores the citation); print `DONE: docs-check citation <file>:<line>`. Re-run: no span left → `UNCHANGED: docs-check citations`. Spans naming the kept pair are untouched.
- `--phase all` (default) runs both. Never commits, never pushes, never removes the example context, never changes the licence. A failing step leaves its file untouched. Exit 0 success, 1 refused/failed, 2 usage (including malformed `config/new-service.defaults.json`).

**Acceptance criteria**
- AC-12.1 `new-service.bats` on a runtime-generated copy of the stub repo: each customize step's file diff equals its golden diff; a second run prints only `UNCHANGED:`/`SKIP:` and exits 0.
- AC-12.2 `new-service.bats`: gh stub `is_template=true` → `repo create --template` without `--clone`, then poll, then clone; `is_template=false` → clone-and-push path with `IMPORT_PENDING:`; existing repository with matching origin → `SKIP: source (exists)`; mismatched origin → exit 1 and no `repo create` call.
- AC-12.3 `new-service.bats`: `--template-path` on a dirty checkout → exit 1; `--dry-run` → only `WOULD:` lines and an unchanged tree; omitted flavour → `SKIP:` + `NEXT:`; K7 linters pass on `README.md`, `CHANGELOG.md`, `bmalph/config.json` after customize.
- AC-12.4 `new-service.bats`: the stub git log shows 0 `commit`/`push` calls by the script.
- AC-12.5 `new-service.bats`: with the fixture `docs/extension-seams.md` citing both guide paths, `--sync-flavour app` and (separately) `--sync-flavour pat` each leave 0 violations of the bats helper's rule-3 port (every backticked path whose first segment is a tracked top-level name exists or is git-ignored, Markdown set as docs-check builds it), rewrite exactly the deleted flavour's span, add `docs/extension-seams.md` to `.templatesyncignore` once, and print the `DONE: docs-check citation` line; a second run prints `UNCHANGED: docs-check citations`.
- AC-12.6 `new-service.bats` (defaults): omitted `--description` → `[workspace.package].description` = `<name>`; omitted `--owner` → `repo create <stub-login>/<name>` from the gh stub's `api user`; omitted `--intro` → README intro = the description; no source flag → the FR-13 slug is probed; two source flags → exit 2.

#### FR-13 — `config/new-service.defaults.json` (G1, RG)

- JSON object with `template_repository` (`owner/name`), `default_visibility` (`private`), `default_version` (`0.1.0`), `poll_attempts` (10), `poll_interval_seconds` (3). Lives outside the four generalization-scanned directories so the default slug (which contains a denylisted token) is legal (H18).
- Read by `new-service.sh` through `resolve_plugin_root`; override order `--template` > `RUST_SDLC_TEMPLATE_REPO` > config; validated on read (types, slug regex), malformed → exit 2.

**Acceptance criteria**
- AC-13.1 `new-service.bats`: override order proven with three cases; malformed JSON and a non-slug value → exit 2.
- AC-13.2 CI `generalization-audit` and L28 pass with the file present (the directory is unscanned); no component under `skills/ commands/ agents/ scripts/` contains the slug.

#### FR-14 — `/rs-sdlc-new-context` (G3)

Argument hint `<group> <context> [--issue <N>] [--no-handoff]`.

- Name validation through `validate_context_name <group> <context>` (FR-33) before anything runs, mirroring xtask (`tpl/xtask/src/scaffold/name.rs`, `tpl/xtask/src/scaffold.rs` `existing`/`listed`, `tpl/docs/new-service.md` §5) and reading the **live tree**, never the profile (which goes stale after every new context): (1) both names match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`; (2) the context is not reserved (`shared service xtask test-support e2e-tests`) — reserved words are legal as a group (`service/ledger` is accepted, `tpl/xtask/src/scaffold/name/tests.rs:80-84`); (3) refused when `crates/<context>` is a directory or any `crates/*/<context>` is a directory (a context name is unique in the workspace whatever its group); (4) refused when a `[workspace].members` entry ends in `<context>/domain`, `<context>/application` or `<context>/infrastructure`, or a member's `package.name` is `<context>-domain`, `<context>-application` or `<context>-infrastructure`. Refusal prints `REFUSED: <rule> <detail>` and exits 1 with nothing written.
- Branch and issue rule: on a `<type>/<N>-<slug>` branch reuse it and issue N; otherwise require `--issue` or create the issue through the issue stage (A18), then `feat/<N>-<context>` from the default branch.
- Runs `make new-context group=<g> context=<c>` (backgrounded, FR-1). Exit 0 = created. Any non-zero exit is always 2 through GNU make, so the plugin classifies by the xtask stderr prefix (`tpl/xtask/src/cli.rs:180,184`): `new-context refused:` → nothing written → `ESCALATED` with the output (validation drift between plugin and xtask, reported as such); `new-context could not run:` → files may already exist (e.g. the `Fault::Lock` case: "the crates were created, but `cargo update --workspace --offline` failed") → `ESCALATED` with the output and `git status --porcelain`; neither prefix → `ESCALATED` with the log tail.
- Dispatches checklist C2–C11 (brief table: architecture model, workspace dependencies at first use, domain, application, infrastructure, test support, migration + `.sqlx/` (or `N/A` without persistence), composition root incl. the three `Adapters { .. }` literals and contract-pinning tests, contracts + end-to-end, documentation) to `rust-implementer`; each item ends `DONE` with evidence or `N/A: <reason>`.
- Commits `feat(#N): add <group>/<context> bounded context`, then C12: the context gate set read at runtime from the Makefile's `CI_*_TARGETS` — `make ci-preflight`, `make ci-static-analysis`, `make ci-tests`, `make ci-contracts`, `make ci-mutation`, `make ci-delivery` (`ci-cli` not run) — one stage per call, each backgrounded and polled (FR-1). Docker reachability (`docker info`) is checked first: five of the six stages need it (`secrets-scan`, `lint-repo`, `lint-load-tests`, `validate-architecture-model`, `validate-openapi-spec`, `openapi-diff`, `graphql-diff` start with `$(REQUIRE_DOCKER)`; the test, sqlx and mutation targets need the compose database through `ensure-deps`/`ensure-database`), so Docker unreachable → C12 `ESCALATED` with `make doctor` output, no stage fed to remediation (D2). Remediation commits `fix(#N): …`; closing `make validate-configuration`.
- End: hand-off to `/rs-sdlc-review` → `/rs-sdlc-qa` → `/rs-sdlc-finish-pr` with the loop's counters, or with `--no-handoff` three `NEXT:` lines. Exit string "context gate set green, 0 protected files changed, committed". Guard: `MAX_ITERATIONS=5` remediation rounds.

**Acceptance criteria**
- AC-14.1 `common-lib.bats`: `validate_context_name` over the fixture tree refuses 100% of a fixture list — uppercase, leading digit, trailing hyphen, double hyphen (in group and in context), each reserved context name, the existing context in its own group (`billing/invoice`), the same context in another group (`sales/invoice`), `sales/internal` (`crates/internal` is a directory), `billing/health-check` (`crates/internal/health-check` exists), a member whose package is named `<c>-domain` at a non-standard path, and a context present in the tree but absent from a stale profile's `architecture.bounded_contexts` — and accepts valid names including group `service` (`service/ledger`); the command text calls it before `make new-context`.
- AC-14.2 `component-counts.bats`: `rs-sdlc-new-context.md` lists C1–C12 with evidence targets, the six gate-set stages and the Docker precondition, both stderr prefixes of the exit classification, the branch rule, the commit subject and both end states.
- AC-14.3 reference run: gate set green, `make validate-configuration` green.

### Feature-loop stages

#### FR-15 — `/rs-sdlc-issue` (G2, G3)

Argument hint `<task text | issue URL | #N>`. Converts a few-sentence task into a GitHub issue via `gh issue create`, or validates and adopts an existing issue (no duplicate). Body follows the H2s of `.github/ISSUE_TEMPLATE/feature_request.md` when present (`Problem statement`, `Proposed change`, `Affected area`, `Tasks`, `Acceptance criteria`), else those five H2s; ≥ 3 testable acceptance-criteria bullets (observable behaviour, HTTP status or GraphQL result, no "should work"); labels `rust-backend-sdlc` (created when missing) and `enhancement` when that label exists; all text redacted. Emits `ISSUE_URL:` and `ISSUE_NUMBER:`. Guard 5 (AC-quality self-check retries).

**Acceptance criteria**
- AC-15.1 `component-counts.bats`: the command names both handles, both labels, the template-H2 rule and the ≥ 3 AC rule.
- AC-15.2 reference run: the issue holds ≥ 3 testable criteria consumed by plan and QA.

#### FR-16 — `/rs-sdlc-plan` (G2, G3)

Argument hint `[#N] [--slug <kebab-title>]`.

- Loads the repository's `.claude/skills/bmad-autonomous-planning/SKILL.md` first when present (repository wins), else the plugin skill; never the BMAD wrapper commands; no interactive prompt.
- Writes `specs/<N>-<kebab-title>/` (never under `_bmad-output/`): `research.md`, `product-brief.md`, `prd.md` (H2 `Executive Summary`, `Functional Requirements`, `Non-Functional Requirements`, `Product Scope`), `architecture.md` (`## Tech Stack` naming only the Rust toolchain and crates; `## Constraints` stating (a) the commit convention with the literal issue number and the `story N.M` subject form and (b) the story-dispatch rule: stories whose `Depends on:` is satisfied may run as parallel `rust-implementer` subagents; parallel agents run only the DB-free targets `make.format`, `make.lint_code`, `make.unit_tests`, `make.architecture`, `make.complexity`; one serialized verify step runs the DB-backed targets (`make.setup_test_db`, `make.integration_tests`, `make.tests_with_coverage`, `make.e2e_tests`, `make.sqlx_prepare`); without the plugin's agents the loop implements stories sequentially under the same DB rule — this section is the only channel into Ralph, because bmalph copies `## Constraints` into `.ralph/PROJECT_CONTEXT.md`, `bmalph/dist/transition/context.js:89-91`), `epics.md` (`## Epic N: Title`, `### Story N.M: Title`, `**Acceptance Criteria:**` with `**Given**/**When**/**Then**`, one `Depends on: <story ids or none>` line per story), `implementation-readiness.md` (verdict "ready" or "needs work"), `run-summary.md`.
- A `<group>/<context>` the plan needs but `[workspace].members` lacks → story 1 "Scaffold `<group>/<context>`" with C1–C12 as acceptance criteria.
- Readiness self-check: the readiness file must not match `/NO[-\s]?GO/i` (same regex as bmalph preflight); loop corrections (max 5) until "ready" and clean.
- Commits the bundle `docs(#N): add planning bundle <N>-<kebab-title>` on the feature branch; emits `SPECS_DIR:`.

**Acceptance criteria**
- AC-16.1 `component-counts.bats`: artifact list, required H2s, both parts of the `## Constraints` rule (commit convention; story-dispatch rule with the five DB-free and five DB-backed keys), `Depends on:` rule, regex self-check and commit subject present in `rs-sdlc-plan.md`.
- AC-16.2 `stage-planning-artifacts.bats`: a bundle generated at runtime in this format stages successfully; the same bundle with a readiness file that matches the bmalph regex is refused (fixture text generated in `setup()`, never committed as `.md`, FR-42).

#### FR-17 — `scripts/stage-planning-artifacts.sh` (G2)

Usage `stage-planning-artifacts.sh <specs-dir> [--dest <dir>] [--dry-run]` (default dest `_bmad-output/planning-artifacts`).

- Copies `prd.md`, `architecture.md`, `epics.md`, `implementation-readiness.md`, `product-brief.md` (and `ux*.md` when present) and `research.md` as `technical-research.md` (bmalph classifies research only by `/tech.*research/i`); prints `STAGED: <src> -> <dest>`.
- Pre-checks: `<specs-dir>` inside the repository (symlinks resolved); `prd.md`, `architecture.md`, `epics.md` present; at least one `### Story N.M:` heading; readiness not matching `/NO[-\s]?GO/i`; dest git-ignored (`git check-ignore` exit 0) — otherwise exit 1 with the reason.
- Clears files in dest not produced by this run (dest only); never writes elsewhere; deterministic output. Exit 0 staged, 1 refused, 2 usage/environment.

**Acceptance criteria**
- AC-17.1 `stage-planning-artifacts.bats`: happy path produces the exact file set incl. `technical-research.md`; stale files in dest removed; a re-run is byte-identical.
- AC-17.2 `stage-planning-artifacts.bats`: missing `epics.md`, zero stories, a blocked readiness file, a tracked dest, a specs dir outside the repo and a symlinked specs dir each exit 1 with nothing written.

#### FR-18 — `/rs-sdlc-implement` (G2, G3)

Argument hint `[SPECS_DIR]`.

1. Hooks active: `git config --get core.hooksPath` non-empty, else `make install-hooks`.
2. `stage-planning-artifacts.sh "$SPECS_DIR"`; then `bmalph implement` (never `--force`); verify `.ralph/PROJECT_CONTEXT.md` contains (a) the commit convention with the literal `(#N)` and (b) the story-dispatch rule from `architecture.md ## Constraints` (FR-16; checked by its DB-free and DB-backed key lists); a missing part or failure output surfaced verbatim → `ESCALATED` naming `/rs-sdlc-plan` as the fix.
3. `bmalph run --driver claude-code --no-dashboard` in the background (driver always `claude-code`); parse `---RALPH_STATUS---` blocks; Ralph's circuit breaker from `.ralph/.ralphrc` is honoured and never edited, reset or restarted around (trip → terminal `ESCALATED` with the last status block and the `.ralph/logs/` tail, no second `bmalph run`).
4. Single implementer: in the command path `bmalph run` is the only implementer. While it is active the command dispatches no `rust-implementer` and edits no file; it only polls the log and the status blocks. Parallelism happens inside Ralph's own claude-code sessions, which read the story-dispatch rule from `.ralph/PROJECT_CONTEXT.md` (step 2) and may fan stories out to `rust-implementer` subagents under it (DB-free targets in parallel, one serialized DB-backed verify step, no worktree isolation); the plugin never writes into `.ralph/` to steer them.
5. Each story is committed as `<type>(#N): story <N.M> <title>` by Ralph's session (subagents never commit); hooks stay active (step 1).
6. Post-loop (Ralph exited with `EXIT_SIGNAL: true`): every subject in `git log --format=%s $(git merge-base <base> HEAD)..HEAD` passes `COMMIT_TITLE='<subject>' make check-commit-message` (hard; mismatch → `ESCALATED` naming the commit); final `make tests-with-coverage` green (backgrounded; Docker unreachable → `ESCALATED`, D2).

Exit string: all stories done with EXIT_SIGNAL true, every commit subject valid, coverage green. Guard 5 `bmalph run` attempts/resumes.

**Acceptance criteria**
- AC-18.1 `component-counts.bats`: `rs-sdlc-implement.md` names `stage-planning-artifacts.sh`, `bmalph implement` without `--force`, `--driver claude-code --no-dashboard`, `.ralph/.ralphrc` (never a repository-root `.ralphrc`, X6), the two-part `.ralph/PROJECT_CONTEXT.md` check, the single-implementer sentence ("`bmalph run` is the only implementer"; no `rust-implementer` dispatch by the command while it is active), the DB-free/serialized split as carried by `## Constraints`, the post-loop subject check and the never-reset rule.
- AC-18.2 `component-counts.bats` (command path): `rs-sdlc-implement.md` states that a breaker trip ends `ESCALATED` with the last `---RALPH_STATUS---` block and the `.ralph/logs/` tail and that no second `bmalph run` follows; the live behaviour is observed in the reference run (K10). The workflow path's analogue (an implementer `BLOCKED` reply) is a harness scenario (AC-3.4 b, AC-44.1).

#### FR-19 — `/rs-sdlc-review` (G2, G3, G4)

Argument hint `[SPECS_DIR] [--base <ref>]`.

- Marker check: missing governance markers → halt with the stage-0 wording.
- **Applicability triage** (FR-32): one verdict per plugin skill (28/28) — `EXECUTE` with evidence or `NOT APPLICABLE` with a concrete reason — decided from frontmatter + decision guide; the 11 skills that share a template skill's name get one verdict per pair (source `repo+plugin`), and the repository skill is read first; full bodies and reference files load only on `EXECUTE`. Triage table `| skill | source | verdict | evidence or reason |`.
- **Lenses:** `code-quality-reviewer` and `fr-nfr-reviewer` always; `security-auditor` when the diff since the merge base touches `*.rs`, `Cargo.toml`, `Cargo.lock`, `migrations/`, `.sqlx/`, `deny.toml`, `Dockerfile` or `.github/workflows/`, re-run in later iterations only when that iteration's remediation touched them (PA-5).
- **Quality rows** — the complete row table; each row is PASS / FAIL / NOT RUN (reason). A keyed row is PASS when its target exits 0 and its measured count is within its `quality.*` bound (NFR-4); a binary row is PASS when its target exits 0. Docker-dependent rows (D2) are marked †; Docker unreachable → those rows `not run (no Docker)` and the stage ends `ESCALATED` (never remediated).

| # | Row (profile target key) | `quality.*` key | Notes |
| --- | --- | --- | --- |
| Q1 | `make.format_check` | — (binary gate, no quality key) | |
| Q2 | `make.static_analysis` | `quality.max_clippy_findings` | |
| Q3 | `make.complexity` | `quality.max_complexity_violations` | limits quoted from `clippy.toml` at review time |
| Q4 | `make.architecture` | `quality.max_architecture_violations` | |
| Q5 | `make.check_crate_isolation` | `quality.max_architecture_violations` | shares Q4's key |
| Q6 | `make.validate_architecture_model` † | — (binary gate, no quality key) | |
| Q7 | `make.check_security` | `quality.max_dependency_policy_findings` | null → `security-auditor` static lane (D1) |
| Q8 | `make.unused_dependencies` | `quality.max_unused_dependencies` | |
| Q9 | `make.tests_with_coverage` † | `quality.coverage_lines`, `quality.coverage_functions` | |
| Q10 | `make.mutation_tests_diff` † | `quality.max_surviving_mutants` | run rule below (PA-13) |
| Q11 | `make.validate_sqlx_metadata` † | — (binary gate, no quality key) | `N/A` when `persistence.engine: null` |
| Q12 | `make.validate_contract_snapshots` | — (binary gate, no quality key) | |
| Q13 | `make.validate_openapi_spec` † | `quality.max_spectral_findings` | |
| Q14 | `make.openapi_diff` † and `make.graphql_diff` † | `quality.max_unapproved_breaking_changes` | against `ci.base_ref`; run with `BREAKING_CHANGE_APPROVED=true` only when the PR already carries `approved-breaking-change` (read with `gh pr view --json labels`, mirroring CI); a breaking change without the label → `ESCALATED` naming the label (D9), never "fixed" by weakening the contract unless the plan did not intend it |
| Q15 | `make.docs_check` | — (binary gate, no quality key) | |

Keys with no review row, and the stage that enforces each: `quality.max_image_vulnerabilities_high_critical` — `security-auditor`'s `make.image_scan` lane when Docker is reachable (FR-29), and finish-pr through the required check `Production-image scan`; `quality.max_smoke_budget_breaches` — `not run (deferred to PR CI)` in review, judged by finish-pr through the required check `Smoke load tests`. Both are therefore not part of the review exit string.
- **Mutation run rule (PA-13):** iteration 1 runs Q10 when the branch diff against `ci.base_ref` touches production `*.rs` (after `git add` of new files); iteration n > 1 re-runs it only when that iteration's remediation touched production `*.rs`; a skipped row carries the previous iteration's verdict and is recorded `not run (not changed)`; a branch diff touching no production `*.rs` records Q10 `not run (not changed)` and counts as PASS.
- **Gate loop:** `fr-nfr-gate.sh --spec-path "$SPECS_DIR" --iteration <n>` (or `make.fr_nfr_gate` when mapped), `--pr <n>` when a PR exists, `--advisory` when no PR exists or the tree is dirty. Remediation: this command has no `Write`/`Edit` and its three lenses are read-only, so the combined findings (FR/NFR findings and `code-quality-reviewer` FAIL-row root-cause fixes) are dispatched as one task to `rust-implementer` via Task; the agent edits the working tree only, and the command then commits `fix(#N): address review gate iteration <n> findings` before re-invoking the lenses (php `sdlc-review.md` pattern). Loop until an iteration yields zero new findings AND every quality row is PASS (NOT RUN for an absent capability is a degrade note → `SUCCESS-WITH-REPORT`; a mapped row that cannot run is `ESCALATED`). Emits `FR_NFR_REVIEWER:` per iteration.
- Ledgers `{code-review,fr-nfr,security}.json` under `${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}`; per-lens comments and the conclusion via `post-review-findings.sh` when a PR exists, else deferred to finish-pr (posted once there, X4). State-comment row with the head SHA.

Exit string: zero new gate findings AND every quality row PASS.

**Acceptance criteria**
- AC-19.1 `component-counts.bats`: the command pins the count `28` in its triage text (equal to the number of skill directories), the pair rule, the three lenses with the security trigger list, the Q1–Q15 table exactly (row target key → `quality.*` key or "binary gate, no quality key"), the two keys enforced elsewhere with their enforcing stage, the mutation run rule, the `rust-implementer` remediation dispatch, the remediation subject and the deferred-conclusion rule; every one of the 12 `quality.*` keys appears either in a row or in the enforced-elsewhere sentence.
- AC-19.2 harness (FR-44): per-iteration finding counts 3 → 1 → 0 end the loop; 5 non-zero iterations end `ESCALATED` with the 7-field block.
- AC-19.3 `component-counts.bats` (release gate, NFR-12): `skills/SKILL-DECISION-GUIDE.md`'s change class "workflow/docs-only" marks ≤ 6 skills `EXECUTE`. The measured body count for a docs-only diff is recorded in the reference run (K10), not asserted by the harness.

#### FR-20 — `/rs-sdlc-qa` (G2, G3)

Argument hint `[SPECS_DIR | #N]`. `allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]`.

- Boot: if `GET <service.base_url><service.liveness_path>` fails, start `make.start` in the background (waits ≤ 900 s); `make.start: null` → skip QA `SUCCESS-WITH-REPORT`; mapped but Docker unreachable → `ESCALATED` with `make doctor` output (A10). The shared stack is never stopped. Before the first probe: when `persistence.engine` is non-null and `make.migrate` is mapped, run `make migrate` (backgrounded, idempotent), because compose's `migrate` service runs only on `up` and an already-running stack never applies a migration added since it started; then poll liveness every ≤ 10 s for ≤ 900 s until two consecutive 200 responses (the watchexec dev process restarts after source changes, so a single success can flap); timeout → `ESCALATED` with `docker compose logs --no-log-prefix --tail 200 app`.
- Readiness: liveness → 200 `text/plain` `pong`; readiness → 204 (a 500 `application/problem+json` with type `/problems/dependency-unavailable` is a FAIL with its `failures[]`).
- Probe set: every issue acceptance criterion maps to ≥ 1 check; REST operations from the committed `service.openapi_snapshot` touched by the change; GraphQL via `POST <service.graphql_path>` with a JSON body built from `service.graphql_snapshot`; negatives per operation where applicable: 400/404/405/413/415/422 with `application/problem+json`, asserted on status + `type` + content type (never on axum rejection text); GraphQL errors asserted as HTTP 200 + `extensions.code` (`VALIDATION_FAILED`, `INTERNAL_SERVER_ERROR`); `x-request-id` echo for a value matching `^[A-Za-z0-9._-]{1,128}$`. Optional lane: `SCHEMATHESIS_URL=<base_url> make schemathesis-validate` when `capabilities.dynamic_security_testing` and the key are set.
- Evidence per check: method, URL, request body, status, content type, `x-request-id`, ≤ 20-line excerpt, expected vs observed. Verdict `## Verdict: PASS|FAIL`; each FAIL carries a reproduction `curl` command. FAIL routes to stage 3 with the report. Delegates to `qa-manual-tester`; no source reading for verdicts.

**Acceptance criteria**
- AC-20.1 L33: 0 findings (no mutating tools on the command or agent).
- AC-20.2 `component-counts.bats`: the command names both readiness probes with expected statuses, the pre-probe `make migrate` rule and the bounded liveness poll, the snapshot-derived probe rule, the problem+json assertion rule, the GraphQL error rule, the evidence fields and both degrade outcomes (A10).
- AC-20.3 reference run: QA report maps every acceptance criterion to an executed check; a seeded defect yields FAIL with a reproduction command.

#### FR-21 — `/rs-sdlc-finish-pr` (G1, G2, G3)

Argument hint `[--pr <n>]`.

- PR create/edit: title `<type>(#N): <subject>` pre-validated (FR-2), issue number never from the PR number; body from `.github/pull_request_template.md` H2s with `Closes #N`, the spec bundle path, the QA verdict, and "targets run / not run (reason)"; draft state left as the user set it.
- Sensor loop on `pr-state.sh --json --required-checks <ci.required_checks> --reviewers <review.reviewers> --human-gated-checks <ci.human_gated>` (both check lists are GitHub check names, e.g. `Protected configuration`, passed comma-separated and matched exactly against check-run `name`): `FIX` → `ci-fixer` for failing non-human-gated checks (counter **A** `ci_fix` ≤ 5) and `pr-comment-resolver` for unresolved threads (counter **B** `comment_resolution` ≤ 5), fixes committed and pushed by the command; `GATE` → `fr-nfr-gate.sh --pr <n> --iteration <c>` on the clean head (counter **C** ≤ 3); `REQUEST` → `request-ai-reviews.sh` (counter **R** ≤ 3); `WAIT` → `pr-state.sh --wait-seconds 540` (counter **W** ≤ 6); `BLOCKED` (closed, merged, conflicting, or a failing human-gated check) → `ESCALATED` naming the label or conflict; `READY` → a second snapshot confirms, then the deferred review conclusion is posted once and `## Status: ALL-GREEN`.
- Degrades: no CI provider or zero checks → `## Status: SKIPPED-NO-CI`, `SUCCESS-WITH-REPORT`; `review.reviewers: []` and `review.coderabbit: false` → `ai-review-loop.sh` findings become the comment source; `capabilities.publish_pr_comments: false` → findings stay in ledgers.
- Never applies or removes labels; never re-runs human-gated checks; `gh run rerun --failed` at most once per head (by `ci-fixer`).

Exit string: CI green + FR/NFR gate green on the head SHA + 0 unresolved review threads.

**Acceptance criteria**
- AC-21.1 `component-counts.bats`: counters A/B/C/W/R with their caps and labels `ci_fix`/`comment_resolution` identical in `rs-sdlc-finish-pr.md`, `agents/ci-fixer.md` and `docs/sdlc-loop.md` (X10); the verdict-dispatch table covers all six verdicts.
- AC-21.2 harness (FR-44, `rs-sdlc-pr-until-green`): FIX → GATE → READY path succeeds; a failing human-gated check ends BLOCKED/`ESCALATED` naming the label; 6 WAITs exhaust W and escalate.
- AC-21.3 `pr-state.bats`: a gh payload whose failing check run is named `Protected configuration` (a name with a space), with `--human-gated-checks 'Protected configuration,OpenAPI breaking changes,GraphQL breaking changes'`, yields `BLOCKED` naming `approved-config-change`, not `FIX`; the same payload with the job id `validate-configuration` in the list does not match (pins the name space); a failing check from a service-added workflow listed in `--required-checks` yields `FIX`, never `READY`.

### Agents

#### FR-22 — Shared agent contract (G2, G4)

- Frontmatter `name` (= filename stem = H1 lead token), `description` ("Use when …"), `tools`, `model` (`sonnet` or `opus`).
- 8-H2 spine: `Profile keys consumed` (only keys the agent uses, X13), `Role`, `Inputs`, `Outputs`, `Allowed actions`, `Degrade paths`, `Iteration discipline` (`MAX_ITERATIONS=5` or `<n>/5`), `Smoke prompt` (happy path + one degrade path).
- Git ownership: agents never `git commit`, `git push`, apply labels or edit `.ralph/`; exceptions: `ci-fixer` may run `gh run rerun --failed` once per head; `pr-comment-resolver` may reply to and resolve review threads.
- Protected change: report `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`; a guard-hook denial is reported verbatim; never retried through Bash.
- Make-only execution and the targets-run vocabulary of FR-1.

**Acceptance criteria**
- AC-22.1 `component-counts.bats`: exactly 7 agents with the names and models of FR-23 to FR-29 and the 8 H2s each.
- AC-22.2 `lint_all.py`: 0 findings for L3, L6, L8, L10, L13, L16, L23, L26, L33.

#### FR-23 — `rust-implementer` (sonnet) (G2, G3, G4)

Implements one story end to end (code + tests) following the executed skills. Inputs: story text and acceptance criteria, `SPECS_DIR`, profile, governance block, the repository's `AGENTS.md` and skills. Rules it must apply: layer order domain → application → infrastructure → `crates/service` wiring; domain crates framework- and I/O-free (only `async-trait`, `thiserror`, `uuid`, shared domain); error model through `Problem` (`application/problem+json`); handlers extract only via `ApiPath`, `ValidatedQuery`, `ValidatedJson`, `ApiJson`; commands return no data; idempotent subscribers; `Clock`/`UuidGenerator` ports instead of `SystemTime::now`, `Instant::now`, `Uuid::new_v4`; no `unwrap`/`expect`/`panic`/indexing/`as` in production code; no `mod.rs`; no type named `Error`; no `#[allow]`; `#[expect(lint, reason = "…")]` only where the lint policy permits (never in crate roots or for complexity lints); `#[async_trait]` methods delegate to an inherent `async fn`; unit tests in sibling `tests.rs`, integration tests in `<crate>/tests/integration/main.rs`; deterministic seeds (`TEST_SEED`, `PROPTEST_RNG_SEED`); co-change rules (migration + `.sqlx/` via `make create-migration`, `make migrate`, `make sqlx-prepare`; snapshots via `make generate-openapi-spec`/`make generate-graphql-spec`; `workspace.dsl` with every crate or dependency edge change); never edits an applied migration. Outputs: changed files list, targets-run list, `---RALPH_STATUS---` block, self-review checklist. Tools: `Read, Write, Edit, Glob, Grep, Bash`.

**Acceptance criteria**
- AC-23.1 `component-counts.bats`: each rule above is present as a token (`ValidatedJson`, `UuidGenerator`, `tests.rs`, `#[expect`, `sqlx-prepare`, `workspace.dsl`, …).

#### FR-24 — `code-quality-reviewer` (opus) (G2, G4)

Reviews the diff against executed-skill rules and the quality rows of FR-19; never runs `-fix` targets (`static-analysis-fix`, `unused-dependencies-fix` are `ask` rules); never proposes a suppression, exclusion or lowered limit. Outputs findings `file:line | severity | rule | root-cause fix` and one PASS/FAIL/NOT RUN verdict per FR-19 row Q1–Q15, each with its `quality.*` key or "binary gate, no quality key". Tools `Read, Glob, Grep, Bash` (read-only make targets).

**Acceptance criteria**
- AC-24.1 `component-counts.bats`: rows Q1–Q15 named with the same row → key mapping as FR-19 (byte-identical to `rs-sdlc-review.md`); prohibition list present; `tools` lacks `Write`/`Edit`.

#### FR-25 — `fr-nfr-reviewer` (opus) (G2)

Verifies every requirement id (`FR-12`, `FR12`, `NFR-3`, `G12` forms) of the bundle and of the Rust baseline catalog (FR-35) is implemented and tested, with evidence from test targets only; drives the gate loop to zero new findings; outputs a per-requirement PASS/FAIL matrix and `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<PASS|FAIL>`. Degrade paths (bundle missing or empty, gate runner unavailable) emit `verdict=FAIL` with a `DEGRADED: <reason>` line and a concrete `blocking_finding` (e.g. `SPECS MISSING: <path>` → re-run `/rs-sdlc-plan`), fail-closed like FR-35; there is no `DEGRADED` verdict. Tools `Read, Glob, Grep, Bash`.

**Acceptance criteria**
- AC-25.1 `component-counts.bats`: the four id forms, the baseline ids and the handle format with the closed enum `PASS|FAIL` present; the agent file contains no `verdict=DEGRADED`.

#### FR-26 — `qa-manual-tester` (sonnet) (G2)

Black-box QA per FR-20; verdicts only from observed HTTP behaviour; forbidden reads `crates/`, `tests/`, `features/`, `xtask/`, `migrations/`, `.sqlx/`, `Cargo.toml`; allowed reads: profile, spec bundle, committed snapshots, service logs through the one bounded form `docker compose logs --no-log-prefix --tail 200 app` (FR-1 raw-call exception (5); allowed by the template's `Bash(docker compose logs:*)` rule; `make logs` follows forever and is never used); loopback URLs only (`service.base_url`), URL-first `curl` form. Tools `Bash, Read` only.

**Acceptance criteria**
- AC-26.1 L33 0 findings; `component-counts.bats`: `tools` equals `Bash, Read`; forbidden-read list present; the bounded log form present; the token `make logs` appears in no file under `agents/` or `commands/` (except a prohibition line).

#### FR-27 — `ci-fixer` (sonnet) (G2)

Turns failing required checks green by root-cause fixes; maps a failing check to make targets in two steps: (1) check name → gate id(s) from the "Gate" cell of its row in `docs/repository-settings.md` or `docs/repository-settings-service.md` (e.g. `Tests and coverage` → `G11, G12, G14`); (2) gate id → target from the gate table of `docs/make-targets.md` (e.g. `| G1 | format-check |`); a check whose Gate cell is `none` (e.g. the `changes` jobs) or whose gate has no target row gets no target and is reported with its log URL, never "fixed"; human-gated checks (`ci.human_gated`: `Protected configuration`, `OpenAPI breaking changes`, `GraphQL breaking changes` today) reported separately and never "fixed"; RUSTSEC advisory without a fixed version → `ESCALATED` (a `deny.toml` exception is protected); one `gh run rerun --failed` per head for infrastructure flakes; outputs a per-iteration check table and `## Status: ALL-GREEN|FIXES-READY|SKIPPED-NO-CI|BLOCKED`; counter label `ci_fix`. Tools `Read, Edit, Write, Glob, Grep, Bash`.

**Acceptance criteria**
- AC-27.1 `component-counts.bats`: status values, `ci_fix` label, human-gated rule, rerun-once rule, and the two-step check → gate id → target mapping naming both documents and the `none` rule present.

#### FR-28 — `pr-comment-resolver` (sonnet) (G2, G4)

Drives every review thread to resolved: a code fix or a reasoned reply, never silent dismissal; source `get-pr-comments.sh --unresolved-only --json` (or `ai-review-loop.sh` findings in degrade); declines with a reply citing the rule any request for `#[allow]`, an unjustified `#[expect]`, a protected-config edit, a coverage or mutant exclusion, a lowered threshold, or an edited applied migration; counter label `comment_resolution`. Tools `Read, Edit, Write, Glob, Grep, Bash`.

**Acceptance criteria**
- AC-28.1 `component-counts.bats`: the six decline categories and the label present.

#### FR-29 — `security-auditor` (opus) (G2, G4)

Static lanes `make.check_security`, `make.secrets_scan` (Docker), `make.image_scan` (Docker; judged against `quality.max_image_vulnerabilities_high_critical`, the review-time enforcement of that key, FR-19), clippy findings; a Docker-dependent lane with Docker unreachable is `not run (no Docker)` (D2); when `make.check_security` is null, its built-in static review lane only (degrade note). Families: injection (sqlx dynamic SQL taint; `query!` macros vs string-built SQL), BOLA/IDOR, mass assignment (`deny_unknown_fields`), DoS (body limit, timeouts, GraphQL depth/complexity), information disclosure (problem details, logs), secrets in code/config, dependency advisories; memory safety recorded N/A (`unsafe_code = "forbid"`); dynamic probing only on the loopback base URL. Outputs ledger-format findings with severity. Tools `Read, Glob, Grep, Bash`.

**Acceptance criteria**
- AC-29.1 `component-counts.bats`: lanes, families and the loopback boundary present; `tools` lacks `Write`/`Edit`.

### Skills

#### FR-30 — Skill library (28 skills) (G2, G4, RG)

| # | Skill | PHP origin | Template counterpart (repository wins) | Gate key (L18) |
| --- | --- | --- | --- | --- |
| 1 | `api-resource-development` | `api-platform-crud` | yes | `framework.graphql` (GraphQL section) |
| 2 | `api-contract-development` | `openapi-development` | yes | `framework.openapi`, `framework.graphql` |
| 3 | `architecture-boundary-fixer` | `deptrac-fixer` | yes | — |
| 4 | `architecture-model-sync` | `structurizr-architecture-sync` | yes | `capabilities.structurizr` |
| 5 | `bmad-autonomous-planning` | same | yes | — |
| 6 | `bmad-fr-nfr-review-gate` | same | — | `capabilities.publish_pr_comments` |
| 7 | `cache-management` | same | — | — |
| 8 | `clean-architecture-llm` | same | — | — |
| 9 | `code-organization` | same | — | — |
| 10 | `code-review` | same | — | `capabilities.publish_pr_comments` |
| 11 | `complexity-management` | same | yes | — |
| 12 | `database-migrations` | same | — | `persistence.engine` |
| 13 | `documentation-creation` | same | — | — |
| 14 | `documentation-sync` | same | yes | — |
| 15 | `implementing-ddd-architecture` | same | — | — |
| 16 | `load-testing` | same | yes | `capabilities.load_testing` |
| 17 | `observability-instrumentation` | same | — | — (tracing-based, no backend selector: the template ships only `tracing` + `tracing-subscriber` JSON logs, `tpl/Cargo.toml:82-83`; php's `capabilities.observability_emf` has no Rust counterpart) |
| 18 | `quality-standards` | same | yes | — |
| 19 | `query-performance-analysis` | same | — | `persistence.engine` |
| 20 | `security-audit` | same | — | `capabilities.dynamic_security_testing` |
| 21 | `testing-workflow` | same | yes | `capabilities.load_testing`, `capabilities.mutation_testing` |
| 22 | `verification-workflow` | `ci-workflow` | yes | — |
| 23–28 | `service-scaffolding`, `bounded-context-scaffolding`, `rust-error-handling`, `async-runtime-safety`, `dependency-policy`, `configuration-management` | new (FR-31) | — | — |

- Format: frontmatter `name` (= directory) and `description` with "Use when" (≤ 1,536 characters incl. name, L11); first H2 `## Profile keys consumed` listing only schema-declared keys and no file names (H21); for the 11 counterparts a second H2 `## Repository precedence` ("read `.claude/skills/<name>/SKILL.md` and `AGENTS.md` first; they win; this skill adds only profile resolution, evidence format, bounded loop, escalation block and verdict line"); body sections Context, Task, Success criteria, Steps, Constraints, Verification; gating sections document their skip path (L18); profile indirection ("the target mapped by `make.static_analysis`"); concrete values only inside fences whose opening line carries `# profile-example`; supporting files `REFERENCE.md`, `reference/*.md`, `examples/*.md` with relative links.
- Lists the template defines (gate order, protected files, required checks) are read at runtime (`make ci-list`, `cargo xtask config-guard --list`, `docs/repository-settings.md`), never restated except as quoted examples with their source.

**Acceptance criteria**
- AC-30.1 `component-counts.bats`: exactly 28 skill directories with these names; the 11 counterparts have `## Repository precedence` as second H2 citing `.claude/skills/<name>/SKILL.md`.
- AC-30.2 `lint_all.py`: 0 findings for L4, L7, L10, L11, L12, L17, L18, L20, L21, L24, L25, L28; CI `profile-keys-check` and `generalization-audit` pass.

#### FR-31 — Rust-only skills (G1, G3)

| Skill | Must cover (each verified as present by a token test) |
| --- | --- |
| `service-scaffolding` | S1–S14; `is_template` probe and clone-and-push; OpenAPI title = `<description> API` → regenerate snapshot before the first PR; checkout directory = Compose project; version only via `scripts/set-version.sh`; keep the example context, removal as a guided story (edit the three docs-check rule-3 lines, update `.templatesyncignore`, replace — never delete — GraphQL roots, regenerate snapshots); sync flavour; local mode `base_ref=HEAD` until `origin/main` exists |
| `bounded-context-scaffolding` | name rules, reserved context names and xtask's existence rule (live tree, any group, `crates/<c>`, member path or package name); C1–C12 with evidence targets; `workspace.dsl` one component per crate and one relationship per dependency edge; `[workspace.dependencies]` at first use (cargo-deny `unused = "deny"`); composition-root wiring points incl. `Adapters { .. }` literals and contract-pinning tests; context gate set; branch rule; in-loop story-1 variant |
| `rust-error-handling` | domain `thiserror` enums with `property_path()`/`code()`; one application error enum per context; `BusError` → `Problem` types `about:blank`, `/problems/validation-failed` (`violations[]`), `/problems/dependency-unavailable` (`failures[]`); `?` propagation; banned `unwrap`/`expect`/`panic`/indexing/`as`; no type named `Error`; `#[expect]` policy |
| `async-runtime-safety` | no blocking calls in async code (`std::fs`, `std::thread::sleep`, sync DNS) → `tokio` equivalents or `spawn_blocking`; no lock guard held across `.await`; cancellation safety and timeouts; `#[async_trait]` delegation to inherent `async fn`; `Clock`/`UuidGenerator` ports; `Arc::clone(&x)` |
| `dependency-policy` | `deny.toml` lanes (advisories, licences, bans, sources), `cargo shear`, per-layer allow-lists in `architecture.toml` (changes are protected → escalate), domain dependency whitelist, RUSTSEC without fix → escalate, diagnosis with `cargo tree -i`, workspace inheritance |
| `configuration-management` | configuration through `crates/service/src/{cli,config}.rs` (clap), `.env`/`.env.test`, never `std::env::var`; a `docs/environment.md` row for every `?=` variable and environment variable (docs-check rule 5); secrets never committed; `scripts/with-env.sh` |

**Acceptance criteria**
- AC-31.1 `component-counts.bats`: each skill contains its listed tokens; each passes FR-30's format checks; `lint_all.py` reports 0 L25 findings on them, which requires `persistence.rs` and `architecture.toml` (the two template file names that match L25's prefix regex without a whitelisted extension) to be backticked in `docs/profile-schema.md` (FR-41).

#### FR-32 — Meta-guides and applicability triage (G2, RG)

- `skills/AI-AGENT-GUIDE.md` (agent roster, stage map, handles, escalation block) and `skills/SKILL-DECISION-GUIDE.md`, both without frontmatter.
- The decision guide holds the verbatim rule "every skill verdict recorded, no silent skips", a decision tree by change class (Rust source per layer, `crates/service` wiring, manifest/lock, migration, contract, workflow/docs-only, new context, new service), one row per skill (28) with its EXECUTE trigger, and the triage protocol: verdicts from frontmatter + guide only; bodies and references only on EXECUTE; counterpart pairs counted once (`repo+plugin`).

**Acceptance criteria**
- AC-32.1 `lint_all.py`: 0 findings for L5, L30.
- AC-32.2 `component-counts.bats`: the decision guide has a row for each of the 28 skill names and the verbatim sentence; its change class "workflow/docs-only" marks ≤ 6 skills `EXECUTE` (NFR-12 release-gate form).

### Review, gate and PR scripts

#### FR-33 — `scripts/lib/common.sh` and the shared script contract (G1, G2, G3, G4, RG)

- Skeleton for every script: `#!/usr/bin/env bash`, `set -euo pipefail`, `SCRIPT_DIR`, `source "$SCRIPT_DIR/lib/common.sh"`; a header with `Usage:` and exit codes; `--help` prints it and exits 0; logs to stderr with prefix `[rust-sdlc]`, handles and data to stdout; executing `common.sh` directly exits 64.
- Writes: `mktemp` in the target directory + `mv`; refuse symlinked or non-regular targets; never write outside documented paths.
- Functions: `log_info`, `log_warn`, `log_error`, `die`; `have_yq` (mikefarah only: `printf 'a: [1]\n' | yq '.a | type'` must print `!!seq`; cached in `_SDLC_YQ_OK`; `SDLC_FORCE_PYTHON_YAML=1` forces PyYAML); `yaml_get`, `yaml_get_list`, `yaml_has`, `yaml_squote`; `json_get` (jq, else python3); `toml_get`, `toml_get_list`, `toml_has` (python3 `tomllib`); `profile_path` (`.claude/rust-sdlc.yml`); `resolve_plugin_root`; `resolve_repo_slug`; `default_branch`; `is_kebab`, `is_slug`, `is_semver`, `is_commit_subject`, `derive_issue_number`, `validate_context_name <group> <context> [ROOT]` (the four FR-14 rules over the live tree: `toml_get_list` of `[workspace].members`, each member's `package.name`, `crates/<c>` and `crates/*/<c>` directories; returns 0, or 1 with one `REFUSED:` line); `resume_point [--cache FILE]` (reads the `<!-- rust-sdlc-state -->` table from stdin or the cache JSON, applies the PA-7 rules with `git merge-base --is-ancestor` and `git rev-parse HEAD`, prints `RESUME_STAGE: <stage>`, one `DONE_STAGE: <stage> <head_sha7> <iteration>` per stage still valid and `COUNTERS: <stage>=<n>,…`; never calls `gh`); `strip_zeros`, `num_gt`, `num_lt`; `redact`; `claude_run_once` (`claude -p … --output-format json --permission-mode acceptEdits --max-turns 30`, one retry on transport failure), `claude_run_isolated`, `claude_supports_restricted`.
- Shared names kept byte-identical with siblings: `SDLC_FORCE_PYTHON_YAML`, `SDLC_LEDGER_DIR`, commit-status context `BMAD FR/NFR Review Gate`; new variables use the `RUST_SDLC_` prefix.

**Acceptance criteria**
- AC-33.1 `common-lib.bats`: one or more cases per function (`validate_context_name`: AC-14.1; `resume_point`: AC-3.4 a); a kislyuk `yq` stub is rejected by `have_yq`; YAML helpers pass with both backends (parity cases); `toml_*` read the fixture `Cargo.toml`/`rust-toolchain.toml`; executing the library exits 64.
- AC-33.2 `component-counts.bats`: every `scripts/*.sh` has the skeleton, a `Usage:` header, and answers `--help` with exit 0; CI `shellcheck -x` 0 findings.

#### FR-34 — `scripts/ai-review-loop.sh` (G2)

Usage `ai-review-loop.sh [--agents LIST] [--max-iterations N] [--diff-base REF]`. Agents from `review.ai_review_agents` (default `claude`; others warn and skip; a run where no supported agent ran exits 1); diff base default `ci.base_ref`; Rust review prompt (the FR-23 rule set, suppression prohibitions); mandatory last line `AI_REVIEW_VERDICT: PASS|FAIL`; FAIL re-reviews up to `--max-iterations` (default 5, values above 20 rejected by digit-string compare); one retry on transport failure; missing verdict line = failed iteration. Exit 0 PASS, 1 otherwise, 2 usage.

**Acceptance criteria**
- AC-34.1 `ai-review-loop.bats` (≥ 23 cases): PASS first iteration; FAIL → PASS; 5 FAILs → exit 1; transport failure retried once; missing verdict; only-unsupported agents → exit 1; 20-digit `--max-iterations` rejected; claude stub argv shows `--permission-mode acceptEdits --max-turns 30`; parity case with `SDLC_FORCE_PYTHON_YAML=1`.

#### FR-35 — `scripts/fr-nfr-gate.sh` (G2)

Usage `fr-nfr-gate.sh [--spec-path PATH] [--pr N] [--impact-context TEXT] [--iteration N] [--advisory]` (React interface).

- Requirement sources (all used when present): the bundle, the PR description, the PR's linked closing issues, and always the Rust baseline catalog: `NFR-BASE-TEST` (100% lines + functions; zero surviving mutants on changed code), `NFR-BASE-QUALITY` (no `#[allow]`, clippy clean, complexity limits), `NFR-BASE-ARCH` (`architecture.toml` boundaries, pure domain, `workspace.dsl` current), `NFR-BASE-CONTRACT` (snapshots regenerated, breaking changes labelled), `NFR-BASE-DATA` (no edited applied migration, `.sqlx/` current), `NFR-BASE-SEC` (no secrets, input validation, problem details), `NFR-BASE-OBS` (tracing spans and `request_id` correlation on new handlers). No bundle and no PR text/linked issue → fail closed (failure status, exit 1).
- Runs through `claude_run_isolated` (`--restricted --tools Read,Grep,Glob`, tokens unset, empty `GH_CONFIG_DIR`, git credential helpers off); the script computes the diff and passes it in; requires `claude_supports_restricted` (else fail fast with the upgrade remediation).
- Mandatory last line `FR_NFR_NEW_FINDINGS: <n>`; unless `--advisory`, posts commit status context `BMAD FR/NFR Review Gate` on HEAD (success/failure) and a redacted PR comment with findings when n > 0 (iteration shown). `--spec-path` confined to the repository (symlinks resolved). Exit 0 zero findings, 1 otherwise, 2 usage.

**Acceptance criteria**
- AC-35.1 `fr-nfr-gate.bats` (≥ 50 cases): each source combination; fail-closed path; advisory posts nothing; status context byte-identical; comment only when n > 0 and redacted; `--spec-path` outside repo and via symlink rejected; isolated argv asserted on the claude stub; old claude without `--restricted` fails fast; transport retry once; malformed last line → exit 1; all 7 baseline ids present in the prompt.

#### FR-36 — `scripts/get-pr-comments.sh` (G2)

Usage `get-pr-comments.sh [--pr N] [--unresolved-only] [--json]`. One paginated `gh api graphql` query for `reviewThreads` (`isResolved`, comments with author, body, path, line, url) and issue comments; `--unresolved-only` excludes issue comments; JSON shape `{pr, review_threads: [{is_resolved, comments: [...]}], issue_comments: [...]}`; human output ends with `unresolved threads: N`; owner/name via `resolve_repo_slug`; PR number validated whatever its source; dies (exit 1) when `gh` is absent — this read decides an exit condition.

**Acceptance criteria**
- AC-36.1 `get-pr-comments.bats` (≥ 31 cases): pagination beyond 100 threads; unresolved filter; JSON shape; non-numeric PR rejected; gh absent → exit 1; jq-absent python fallback parity.

#### FR-37 — `scripts/post-review-findings.sh` (G2)

Usage `post-review-findings.sh <lens> [--pr N] [--file F]... [--dry-run] [--json]` and `post-review-findings.sh --conclusion [--file F]... [--pr N] [--started-at ISO] [--ended-at ISO] [--duration-seconds N] [--iterations N]`; lens ∈ `security fr-nfr code-review`.

- One consolidated, idempotent comment per lens, marker `<!-- rust-sdlc-review:<lens> -->`; conclusion marker `<!-- rust-sdlc-review:conclusion -->` posted exactly once per PR; updates its prior comment instead of adding one.
- Ledgers default `${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}/{security,fr-nfr,code-review}.json`.
- Degrade-first: capability `capabilities.publish_pr_comments: false`, gh absent, no PR, empty ledger, malformed gh read, mismatched base repository or a write failure → note and exit 0.
- Redaction before render (`redact`); `--json` emits valid JSON; no literal NUL bytes in the script (X16); writes only to the origin repository's own PR.

**Acceptance criteria**
- AC-37.1 `post-review-findings.bats` (≥ 41 cases): every degrade path exits 0 with its note; marker idempotence (second post edits); conclusion once; each redaction rule; `--json` parses with `jq`/python; no NUL byte in the script (`tr -cd '\000' < script | wc -c` is 0); mismatched base repo refused.

#### FR-38 — `scripts/pr-state.sh` (G2)

Usage `pr-state.sh [--pr N] [--reviewers LIST] [--required-checks LIST] [--human-gated-checks LIST] [--wait-seconds S] [--interval-seconds S] [--wait-verdicts LIST] [--json]`; defaults from `review.reviewers`, `ci.required_checks`, `ci.human_gated`. Check lists are comma-separated GitHub check names (spaces allowed, e.g. `Protected configuration`), matched exactly and case-sensitively against check-run `name`; an explicit `--required-checks` narrows the CI scope to that list (react semantics, `react/scripts/pr-state.sh:198-212`), which is why `ci.required_checks` must include the service document's rows (FR-6).

- One snapshot per read (PR, reviews, issue comments, unresolved threads via `get-pr-comments.sh`); reviewer states `APPROVED NOT_APPROVED REQUESTED STALE NONE SKIPPED` against the current head; the `BMAD FR/NFR Review Gate` status judged on its own (`success failure pending missing`).
- Exactly one verdict, priority `BLOCKED > FIX > GATE > REQUEST > WAIT > READY`; a failing human-gated check → `BLOCKED` with `NEXT:` naming the label from `docs/repository-settings.md`. Output `KEY: value` lines + `VERDICT:` + `NEXT:`, or `--json` `{pr, repo, head, state, draft, mergeable, ci, fr_nfr, unresolved, reviewers, human_gated, notes, verdict, next}`. Exit 0 whenever a snapshot was rendered, 1 on usage or gh failure. `SDLC_NOW_EPOCH` overrides now (tests).

**Acceptance criteria**
- AC-38.1 `pr-state.bats` (≥ 30 cases): each verdict from gh fixtures; priority ordering; human-gated BLOCKED by check name (AC-21.3); a check name containing spaces parsed from `--required-checks` and matched against the payload's check-run names; wait mode bounded by `--wait-seconds`; JSON shape; missing gate status → GATE.

#### FR-39 — `scripts/request-ai-reviews.sh` (G2)

Usage `request-ai-reviews.sh [--pr N] [--reviewers LIST] [--full] [--min-interval-minutes M] [--force] [--dry-run]`; default reviewers `review.reviewers`; posts the mention each bot accepts, honouring cadence (CodeRabbit default 60 min); output `REQUESTED:`/`WAIT:`/`SKIPPED:`/`INFO:` lines + `SUMMARY: requested=<n> waiting=<n> skipped=<n>`; empty reviewer list → `INFO: no reviewers configured`, exit 0. Exit 0 when the plan was computed and posts succeeded, 1 on usage, unresolvable PR/repo or a failed gh call.

**Acceptance criteria**
- AC-39.1 `request-ai-reviews.bats` (≥ 17 cases): interval WAIT; `--force`; `--dry-run` posts nothing; unknown reviewer rejected; empty list INFO; summary arithmetic.

### Packaging, documentation, tests and marketplace

#### FR-40 — Plugin manifest and README (RG)

`.claude-plugin/plugin.json` with exactly `name` (`rust-backend-sdlc`), `version` (`0.1.0`), `description`, `author` (`{name: VilnaCRM, url}`), `homepage` (`…/tree/main/plugins/rust-backend-sdlc`), `repository`, `license` (`MIT`), `keywords` (incl. `rust`, `sdlc`, `bmad`, `ralph`, `microservices`); no custom keys. Plugin `README.md`: install lines, prerequisites with version floors (NFR-16), the 10 commands with one-line purpose, quick start (new service → setup → feature), links to the 9 docs.

**Acceptance criteria**
- AC-40.1 CI `manifest-validate` passes; `claude plugin validate --strict plugins/rust-backend-sdlc` exits 0 where the CLI is available.
- AC-40.2 `component-counts.bats`: README names all 10 commands and links every doc that exists.

#### FR-41 — Documentation set (G1, RG)

| Doc | Required content |
| --- | --- |
| `docs/profile-schema.md` | every FR-5 key (type, R/O, default, source, consumers); detection-source and cited-file table (backticks `architecture.toml`, `persistence.rs`, `clippy.toml`, `deny.toml`, `protected-config.toml`, `docs/repository-settings-service.md`; `architecture.toml` and `persistence.rs` are the template file names L25 would otherwise flag); tighten-only table (NFR-4); "null means absent; omitted means error"; annotated `# profile-example` profile |
| `docs/setup-walkthrough.md` | install → `/rs-sdlc-setup` → single commit; protected settings and `.claude/settings.local.json`; dirty-tree degrade; re-run after template sync (J6) |
| `docs/sdlc-loop.md` | stage table with byte-identical exit strings; counters A/B/C/W/R; state comment format; resume rules; run report; escalation block |
| `docs/permissions.md` | plugin `claude -p` calls use `acceptEdits`; gate session isolation; allowlist entries and `--with-qa-network`; Ralph's `CLAUDE_PERMISSION_MODE="bypassPermissions"` default in `.ralph/.ralphrc` stated truthfully, never changed by the plugin; template guard hooks still fire; deny > ask > allow; headless `ask` rules recorded `not run (ask rule)` |
| `docs/degrade-matrix.md` | every NFR-3 row |
| `docs/release-process.md` | tag `rust-backend-sdlc-vX.Y.Z`; semver; marketplace `source`; changelog discipline |
| `docs/new-service-walkthrough.md` | S1–S14 with sample output; the K9/K13 record section |
| `docs/testing/test-strategy.md` | surfaces, suites, floors (NFR-8), fixtures, stubs, K7 tool pins, skip policy |
| `docs/workflows.md` (epic 8) | the 4 workflows, hand-back contract, counters, harness and `--as-child` |

**Acceptance criteria**
- AC-41.1 CI `markdown-lint` 0 findings; `component-counts.bats` asserts each FR-5 key in `profile-schema.md`, each NFR-3 row id in `degrade-matrix.md`, and that relative links in `docs/` resolve.

#### FR-42 — Test suites and fixtures (RG)

- 16 suites (Scope inventory table), hermetic: no network, stubs on `PATH`, all writes under `$BATS_TEST_TMPDIR`.
- Fixtures: `tests/fixtures/rust-repo/` stub (`acme/billing-service`): virtual workspace with `crates/billing/invoice/{domain,application,infrastructure}`, `crates/shared/*`, `crates/internal/health-check/*`, `crates/service`, `tests/support`, `tests/e2e`, `xtask/Cargo.toml`, `rust-toolchain.toml`, `architecture.toml`, `clippy.toml`, `deny.toml`, `protected-config.toml`, `make/gates.mk`, `make/service.mk`, a Makefile with `##` targets and `CI_*_TARGETS`, `workspace.dsl`, `.env`, `.github/workflows/*.yml` incl. both sync workflows with `TEMPLATE_REPOSITORY: acme/rust-template`, `.github/openapi-spec/spec.yaml`, `.github/graphql-spec/spec`, `.coderabbit.yaml`, `bmalph/config.json`, `.claude/settings.json`, copies of the template's `.yamllint.yml`, `.prettierrc.yml`, `.markdownlint-cli2.yaml`, `_typos.toml`; `.templatesyncignore`; Markdown files (`README.md`, `CHANGELOG.md`, `CLAUDE.md`, `AGENTS.md` with verification markers, `docs/new-service.md`, `docs/repository-settings.md` reproducing the template's seven workflow job tables and its "Labels to create" table verbatim (singular and plural sentence forms), an optional `docs/repository-settings-service.md` variant adding one `Required: yes` row, `docs/make-targets.md` with the gate table, `docs/extension-seams.md` citing both `.github/TEMPLATE_SYNC_APP.md` and `.github/TEMPLATE_SYNC_PAT.md`, the two guides themselves, `.github/ISSUE_TEMPLATE/feature_request.md`, `.github/pull_request_template.md`) and any `_bmad`/`.ralph` directories generated at runtime (heredocs or `*.md.tpl`); profiles (golden + one invalid variant per rule); ledgers; gh JSON payloads; stubs `tests/fixtures/bin/{claude,gh,bmalph,cargo,make,docker,yq}` driven by `STUB_*` variables with call logs.

**Acceptance criteria**
- AC-42.1 CI `bats` job runs all suites with 0 failures; `find plugins/rust-backend-sdlc -name '*.md' -path '*fixtures*'` returns nothing; L29 0 findings.

#### FR-43 — Marketplace and CI wiring (RG)

- `.claude-plugin/marketplace.json`: entry `{name: rust-backend-sdlc, description, author {name, url}, category: development, source: ./plugins/rust-backend-sdlc}` (php entry shape).
- Root `README.md`: plugin table row and install line.
- `.github/workflows/ci.yml`: tag filter adds `'rust-backend-sdlc-v*'`; `profile-keys-check` and `generalization-audit` iterate the explicit list `plugins/php-backend-sdlc plugins/rust-backend-sdlc` (a `plugins/*` glob would fail on `devops-sdlc`); the `bats` job installs yamllint 1.38.0 and typos 1.52.0 (pip) and pre-fetches Prettier 3.9.10 and markdownlint-cli2 0.24.0 (npx) so K7 cases run; node is available for `workflows.bats`. No change to `tools/plugin-quality` (A6); React not added to the key check (A11).

**Acceptance criteria**
- AC-43.1 every `ci.yml` job green on the plugin PR; `lint_all.py` 0 findings for all plugins.
- AC-43.2 negative check recorded in `docs/testing/test-strategy.md`: seeding the denylisted org token into a Rust skill body makes `generalization-audit` fail.

### Workflow epic (in scope for v0.1.0; the cut line)

#### FR-44 — Workflow-tool scripts, harness and tests (G2)

- `workflows/rs-sdlc-fr-nfr-review.js` (leaf): scope (bundle, PR sources, clean tree, head match) → gate loop ≤ 5 via `fr-nfr-gate.sh` → advisory mode when the tree is dirty or not the PR head.
- `workflows/rs-sdlc-review-panel.js` (leaf): scope + triage, parallel lenses (code-quality, FR/NFR, security with `securityFamilies: ['all']`), 3 refuters per finding, fixes grouped by the first three path segments (`crates/<group>/<context>`), ≤ 5 iterations, Rust fix prohibitions, agent types `rust-backend-sdlc:<agent>`.
- `workflows/rs-sdlc-pr-until-green.js`: sensor loop Snapshot → Request → Wait → Fix → Gate → Publish with counters fix 5, wait 6, request 3, gate 3; `onGate: 'nested' | 'return'` (default `'nested'` only when top-level); accepts `carry: {counters, journal, degrade_notes}`; publish commits `fix(#N): …` with issue derivation per FR-2; hooks on.
- `workflows/rs-sdlc-feature.js`: setup check → plan resolution → **staging**: `stage-planning-artifacts.sh "$SPECS_DIR"` + `bmalph implement` (never `--force`) and the same two-part `.ralph/PROJECT_CONTEXT.md` check as FR-18 step 2 → layer-first implementation rounds that execute the stories of Ralph's fix plan (`.ralph/@fix_plan.md`, read-only) through `rust-implementer` agents (DB-free parallel, serialized verify; reply schema `status: COMPLETE | IN_PROGRESS | BLOCKED`, `BLOCKED` → `ESCALATED`; rounds ≤ 5) → review panel → gate → QA (`make start`, `make migrate`, REST/GraphQL/health probes) → PR → `pr-until-green` with `onGate: 'return'`; on a `GATE` result it runs `rs-sdlc-fr-nfr-review` itself, publishes, and re-enters with `carry` (feature-owned gate counter ≤ 3). The workflow **never runs `bmalph run`** (Ralph's own loop cannot be driven from inside a Workflow script, and two implementers would race): its report records `bmalph run: not used (workflow path)` as a degrade note, so a workflow run ends at best `SUCCESS-WITH-REPORT` for stage 3 (PA-17). It keeps no state comment: resume within a run is `carry`; resume across sessions is the command path (`/rs-sdlc <N>`, FR-3). No path nests `workflow()` deeper than one level; every nested call site escalates gracefully with the manual command line when resolution fails (A12).
- Runtime constraints: `meta` is a pure literal; no `Date.now()`, `Math.random()` or argless `new Date()`.
- `tests/lib/workflow-harness.mjs`: meta extraction, scenario-matched agent replies, mocked `workflow()`, and `--as-child` (any `workflow()` call throws). `tests/workflows.bats`: scenarios incl. those named in AC-3.4 (b), AC-19.2, AC-21.2, and a static call-graph test. The harness asserts only behaviour the scripts implement (control flow over mocked replies); it never claims to observe what a real model loaded or how Ralph behaves.

**Acceptance criteria**
- AC-44.1 `workflows.bats` (≥ 45 cases) green; static call-graph depth ≤ 1; each leaf workflow passes under `--as-child`; scenarios: an implementer `BLOCKED` reply → `ESCALATED` with 7 fields; the staging step's script calls appear in order (`stage-planning-artifacts.sh`, then `bmalph implement`) and no shell command the workflow issues or asks an agent to run invokes `bmalph run`; `carry` re-entry keeps counters; the report carries the `bmalph run: not used (workflow path)` degrade note.
- AC-44.2 `component-counts.bats` pins 4 workflows; a grep test finds no `Date.now`, `Math.random` or `new Date()` in `workflows/`.

## Non-Functional Requirements

| Id | Requirement (one line) | Measured by |
| --- | --- | --- |
| NFR-1 | Idempotent, no-clobber writes: second runs change nothing; content outside owned regions is byte-identical | per-script bats checksum cases |
| NFR-2 | Generalization: 0 denylist hits and 0 service literals in `skills/ commands/ agents/ scripts/` outside `# profile-example` fences | L28/L29, CI `generalization-audit`, bats |
| NFR-3 | Degrade matrix: every capability gap has one defined outcome; degrades never loop and never fake a pass | `docs/degrade-matrix.md` rows ↔ tests |
| NFR-4 | Tighten-only bars: 12 threshold keys can only equal or tighten the template's values | 12 `validate-profile.bats` rejections, grep tests |
| NFR-5 | Safety: never bypass hooks, force-push, edit protected config, reset the Ralph breaker, set `bypassPermissions`, or apply approval labels | grep/contract tests, merge-settings bats |
| NFR-6 | Boundedness: every loop has a numeric cap; breach ends in the 7-field escalation | contract tests, harness, script tests |
| NFR-7 | Portability: bash ≥ 4.4, git ≥ 2.30, Linux + macOS, mikefarah-yq-or-PyYAML, jq-or-python3, python3 `tomllib` | parity tests, banned-construct grep, shellcheck |
| NFR-8 | Testability: every script bats-covered per flag/exit code; ≥ 460 tests; lint/shellcheck/markdownlint 0 | CI jobs, floors table |
| NFR-9 | Observability: every run ends with a report; state comment, ledgers, logs and targets-run list are produced | contract tests, ledger schema tests |
| NFR-10 | Security: redaction before publishing, isolated gate session, least-privilege tools, loopback-only QA network, input validation | redaction/isolation/containment bats |
| NFR-11 | Installability: install exposes 10/7/28/2 components; no `_bmad`/`.ralph` in the tree | `component-counts.bats`, L29 |
| NFR-12 | Token cost: triage verdicts for 28/28 skills from frontmatter; ≤ 6 `EXECUTE` skills for a docs-only change class | `component-counts.bats` over the decision guide; measured body count in K10 |
| NFR-13 | Template compatibility: every file written into a service passes its linters and docs-check rules 1–4 | K7 bats in CI |
| NFR-14 | Runtime bounds: no foreground call > 600 s; script timings; hands-on and wall-clock targets | contract tests, bats timing, K9/K13 |
| NFR-15 | Drift resistance: template lists read at runtime; shared names and counts pinned | grep tests, `component-counts.bats` |
| NFR-16 | Version floors enforced with named remediation | `setup-preflight.bats` |

### NFR-1 — Idempotence and no-clobber (G1, G4)

- `/rs-sdlc-setup` second run on a committed first run: `git status --porcelain` empty; only `UNCHANGED:` lines.
- `inject-governance.sh`: content outside the markers keeps its sha256; exactly one block after any marker corruption; `--diff` writes nothing.
- `generate-profile.sh`: an existing profile is kept unless `--refresh`; the diff is printed.
- `merge-settings.sh`: union only; existing entries and order preserved; second run byte-identical.
- `new-service.sh`: second run prints only `UNCHANGED:`/`SKIP:`; `gh repo create` never runs twice.
- `stage-planning-artifacts.sh`: deterministic output; removals confined to its git-ignored dest.
- **AC:** each script's suite holds a "second run" case and an "outside region untouched" checksum case; a tree snapshot before/after shows no file written outside the documented targets.

### NFR-2 — Generalization (RG, G1)

- 0 hits of `user[-_ ]service|mongo[a-z][a-z0-9_]*repository|apprunner|src/user|src/oauth|vilnacrm` (case-insensitive) in `skills/ commands/ agents/ scripts/` outside fences whose opening line carries `# profile-example`; `.sh` files have no escape.
- The default template slug lives only in `config/new-service.defaults.json`; fixtures use `acme/rust-template` and `acme/billing-service`.
- No component hardcodes the template's example-context path or service names; they are read from the target (`architecture.bounded_contexts`, the target's `docs/new-service.md`).
- Values (ports, paths, thresholds, check names) come from profile keys; literal defaults appear only in `generate-profile.sh` detection code with their source comment, or in profile-example fences.
- **AC:** L28/L29 0 findings; CI `generalization-audit` passes for the Rust plugin; a bats grep finds no example-context path outside profile-example fences in the four directories.

### NFR-3 — Degrade matrix (G2)

Rules: a degrade path never loops and never fakes a pass. The Outcome column uses only the stage-level status vocabulary of the FR conventions — `SUCCESS` (designed path, no degrade note), `SUCCESS-WITH-REPORT` (exit string met, exactly one degrade note emitted, shown in the Behaviour column) and `ESCALATED` (7-field block) — and maps to the run report as stated there (`SUCCESS-WITH-REPORT` → `result: SUCCESS` + a `degrade_notes` entry + `met: yes (degraded)`). An **absent** capability ends `SUCCESS-WITH-REPORT`; a **mapped capability that cannot run** or a safety block ends `ESCALATED`, unless its row names `SUCCESS-WITH-REPORT` for the stage (D13, whose `ask` targets are lifecycle and `-fix` targets and never a gate, and the setup and new-service cells of D2, D3, D5 and D25). Where one condition hits several stages, the outcome is given per stage.

| # | Condition | Detection | Behaviour (degrade note in quotes) | Outcome |
| --- | --- | --- | --- | --- |
| D1 | Make target absent | `make.<key>: null` | skip the check, `not run (capability absent)`; "`make.<key>` absent" | SUCCESS-WITH-REPORT |
| D2 | Docker unreachable | `docker info` ≠ 0 before a Docker-dependent stage, or the message `This target needs a reachable container engine (docker).` in a make log (make's exit is 2 for any failure, so the message classifies, never the code) | Docker is a precondition of `ci-preflight`, `ci-tests`, `ci-contracts`, `ci-mutation`, `ci-delivery` and of the review rows Q6, Q9, Q10, Q11, Q13, Q14 and the `security-auditor` lanes `make.secrets_scan`/`make.image_scan`; affected targets are recorded `not run (no Docker)` and never fed to remediation; "Docker unreachable: `<targets>` not run" + `make doctor` output | ESCALATED (implement, review, QA with `make.start` mapped, new-context C12) / SUCCESS-WITH-REPORT (new-service S8 `NOT RUN (no Docker)`, which stops before S11 per J1) |
| D3 | No host toolchain and container mode off | `cargo` absent, `capabilities.run_in_container: false` | targets `not run (no toolchain)`; "no toolchain: re-run /rs-sdlc-setup --exec container or install the toolchain" | SUCCESS-WITH-REPORT (setup step 8) / ESCALATED (loop stages, new-context) |
| D4 | `.claude/settings.json` protected | `protected-config.toml` lists it | allowlist to `.claude/settings.local.json` or printed; "allowlist written to .claude/settings.local.json (settings.json is protected)" | SUCCESS-WITH-REPORT |
| D5 | Dirty tracked tree at setup | `git status --porcelain --untracked-files=no` | `DEGRADED: make bmalph-setup not run (tracked changes: <files>)` + `NEXT:`; a later stage 0 halts until `_bmad/` exists (D19 wording) | SUCCESS-WITH-REPORT (setup) / ESCALATED (stage 0 while `_bmad/` is absent) |
| D6 | bmalph absent but installable | Makefile `bmalph-setup` + node ≥ 20 + npm | preflight WARN; setup step 2 installs; floor re-checked after install (no capability lost, no degrade note) | SUCCESS |
| D7 | No AI reviewer | `review.reviewers: []`, `review.coderabbit: false` | `ai-review-loop.sh` is the comment source; "no AI reviewer configured" | SUCCESS-WITH-REPORT |
| D8 | No CI | `ci.provider: null` or zero checks | `## Status: SKIPPED-NO-CI`; "CI absent: CI half of the exit condition not verified" | SUCCESS-WITH-REPORT |
| D9 | Human-gated check failing, or an intended breaking contract change without the label | check name ∈ `ci.human_gated` (check names, e.g. `Protected configuration`); review row Q14 | BLOCKED naming the label read from `docs/repository-settings.md`; never labelled by an agent | ESCALATED |
| D10 | `gh` unreachable | `gh api` fails | resume from the cache; review/QA re-run when the cache is absent ("gh unreachable: resumed from cache" / "no durable record: review and QA re-run"); issue and finish-pr cannot run | ESCALATED (issue, finish-pr) / SUCCESS-WITH-REPORT (resume) |
| D11 | No PR at review time | `gh pr view` fails | gate `--advisory`; conclusion deferred to finish-pr; "gate advisory: no PR" | SUCCESS-WITH-REPORT |
| D12 | Comment publishing off | `capabilities.publish_pr_comments: false` | findings stay in ledgers; "comments not published (capability off)" | SUCCESS-WITH-REPORT |
| D13 | `ask` rule in a headless run | target in the template's `ask` list (lifecycle and `-fix` targets, never a gate) | `not run (ask rule)`, never reported as passed; "`<target>` not run (ask rule)" | SUCCESS-WITH-REPORT |
| D14 | Call may exceed 600 s | any `make` call outside the FR-1 foreground allowlist, `git commit`/`git push`, `bmalph run` | background + poll ≤ 30 s (designed path, no note) | SUCCESS |
| D15 | claude without `--restricted` | `claude_supports_restricted` false | preflight FAIL; gate fails fast with upgrade remediation | ESCALATED |
| D16 | kislyuk `yq` on host | `!!seq` probe fails | python3 + PyYAML backend (transparent substitution, no note) | SUCCESS |
| D17 | Template repository flag off | `is_template` false | clone-and-push + `IMPORT_PENDING:` + `NEXT:` advice; "template flag off: imported by clone-and-push" | SUCCESS-WITH-REPORT |
| D18 | Sync flavour undecided (headless) | `--sync-flavour` omitted | `SKIP:` + `NEXT:`; "sync flavour undecided"; G1(a) not met for that run | SUCCESS-WITH-REPORT |
| D19 | Governance markers missing | marker grep | stage 0 / review halt with the setup wording | ESCALATED |
| D20 | Not template-derived | A1 markers missing | preflight WARN; profile with null/false capabilities; "not template-derived: capabilities off" | SUCCESS-WITH-REPORT |
| D21 | Workflow name unresolved | nested `workflow()` throws | escalate with the manual command line | ESCALATED |
| D22 | Ralph circuit breaker trips | `---RALPH_STATUS---` / `.ralph/` state | stop; never reset; no second `bmalph run` | ESCALATED |
| D23 | Protected change needed (allow-list, `deny.toml` exception, equivalent mutant, budget) | implementer/reviewer finding | `BLOCKED` naming `approved-config-change` + `ALLOW_PROTECTED_CONFIG_EDIT=1` | ESCALATED |
| D24 | Base ref unavailable (local repo) | `git rev-parse <ci.base_ref>` fails | `git fetch origin <default>` once; local-only → `base_ref=HEAD`; "base ref unavailable: using HEAD" | SUCCESS-WITH-REPORT |
| D25 | Container mode, `app` not running | `capabilities.run_in_container: true` and `docker compose ps --status running --quiet app` empty, or an exec fails with "service app is not running" | `make.start` in the background (≤ 900 s), one restart attempt; still down or Docker unreachable → targets `not run (no Docker)`; "container stack unavailable" + `make doctor` output | SUCCESS (stack started) / SUCCESS-WITH-REPORT (setup step 8; new-service, which prints the remaining steps as `NEXT:` and stops before S11) / ESCALATED (loop stages, new-context) |

- **AC:** `docs/degrade-matrix.md` lists D1–D25 with exactly these outcome words (bats asserts each id and that the Outcome column uses only `SUCCESS`, `SUCCESS-WITH-REPORT`, `ESCALATED`); `docs/testing/test-strategy.md` maps each row to ≥ 1 bats, contract or harness case, including for D2 a `component-counts.bats` assertion that `rs-sdlc-review.md`, `rs-sdlc-implement.md` and `rs-sdlc-new-context.md` state the Docker precondition and the message-based classification, and for D25 the container-precondition sentence (AC-1.1).

### NFR-4 — Tighten-only bars (G4)

| Key | Bound (shipped default = template value) | Gate |
| --- | --- | --- |
| `quality.coverage_lines` | floor 100 | `tests-with-coverage` |
| `quality.coverage_functions` | floor 100 | `tests-with-coverage` |
| `quality.max_surviving_mutants` | ceiling 0 | `mutation-tests-diff` |
| `quality.max_clippy_findings` | ceiling 0 | `static-analysis` |
| `quality.max_complexity_violations` | ceiling 0 (limits quoted from `clippy.toml` at review time) | `complexity` |
| `quality.max_architecture_violations` | ceiling 0 | `architecture` |
| `quality.max_unused_dependencies` | ceiling 0 | `unused-dependencies` |
| `quality.max_dependency_policy_findings` | ceiling 0 | `check-security` |
| `quality.max_spectral_findings` | ceiling 0 | `validate-openapi-spec` |
| `quality.max_unapproved_breaking_changes` | ceiling 0 | `openapi-diff`, `graphql-diff` |
| `quality.max_image_vulnerabilities_high_critical` | ceiling 0 | `image-scan` |
| `quality.max_smoke_budget_breaches` | ceiling 0 (budget quoted from `tests/Load/config.json.dist`) | `smoke-load-tests` |

- Floors above 100 and negative ceilings are invalid values; because the template's bars sit at their extremes, tighten-only means "equal to the template value" for all 12 keys.
- No plugin component instructs `#[allow]`, `#[mutants::skip]`, `#[coverage(off)]`, an `exclude_re`/`exclude_globs` entry in `.cargo/mutants.toml`, an `--ignore-filename-regex` coverage flag, or a `clippy.toml` limit change, except inside prohibition sentences. An `#[expect]` without `reason` cannot be detected by grep in prompt text and needs none: the template's static-analysis gate rejects it (gate G2 negative test "a suppression without a reason"), and `code-quality-reviewer`/`pr-comment-resolver` decline unjustified ones (FR-24, FR-28).
- **AC:** 12 rejection cases (AC-7.1); pattern P6 of the NFR-5 set — the fixed-string token list `#[allow`, `#[mutants::skip]`, `#[coverage(off)]`, `exclude_re`, `exclude_globs`, `--ignore-filename-regex` — matches in `commands/ agents/ skills/ workflows/` only on prohibition lines (containing `never`, `Never`, `forbidden` or `decline`).

### NFR-5 — Safety (G2, G4)

The plugin never: passes `--no-verify`/`-n` to `git commit` or `--no-verify` to `git push`; force-pushes; writes `core.hooksPath`; writes any file listed by `protected-config.toml` / `cargo xtask config-guard --list` (incl. `.claude/settings.json`); asks the user to set `ALLOW_PROTECTED_CONFIG_EDIT` as part of normal flow (only in escalation text); edits `.ralph/.ralphrc`, resets or restarts around a tripped Ralph breaker, or passes `--force` to `bmalph implement`; sets `bypassPermissions` (every plugin `claude -p` call uses `--permission-mode acceptEdits`; the gate uses the isolated restricted session); applies or removes `approved-config-change` / `approved-breaking-change`; creates secrets, variables or branch protection; edits an applied migration or hand-edits contract snapshots or `.sqlx/`; stops the shared dev stack in QA; runs DB-backed targets in parallel; discards uncommitted user changes (`git reset --hard`, `git checkout -- .`, `git clean -fd`); copies plugin skills or scripts into the service.

- **Forbidden-pattern set** (single source for AC-2.3, NFR-4 and this AC; Python `re` syntax, evaluated with python3 for macOS/Linux parity, matched per line, case-sensitive):

| Id | Pattern | Exemptions |
| --- | --- | --- |
| P1 | `git (commit\|push)\b.*(--no-verify\|\s-n\b)` | — |
| P2 | `git push\b.*(--force\|--force-with-lease\|\s-f\b)` | — |
| P3 | `git -c core\.hooksPath` | — |
| P4 | `git config ((--local\|--global) )?core\.hooksPath` (a write; the read-only `git config --get core.hooksPath` does not match) | — |
| P5 | `bmalph implement.*--force` | the option `--force` of `request-ai-reviews.sh` (its usage, parser and `WAIT` lines, FR-39) is not a git or bmalph construct and matches none of P1–P5 |
| P6 | fixed strings `#[allow`, `#[mutants::skip]`, `#[coverage(off)]`, `exclude_re`, `exclude_globs`, `--ignore-filename-regex` | — |
| P7 | `bypassPermissions` | `docs/permissions.md` (states Ralph's default truthfully) |

- **AC:** `component-counts.bats` applies P1–P7 over `commands/ agents/ skills/ workflows/` (matches allowed only on prohibition lines containing `never`, `Never`, `forbidden` or `decline`) and over `scripts/` (matches allowed only in comment lines containing `never`); a positive case proves `request-ai-reviews.sh --force` and `git config --get core.hooksPath` match nothing; claude-stub argv assertions in `ai-review-loop.bats` and `fr-nfr-gate.bats`; `merge-settings.bats` protected-file cases.

### NFR-6 — Boundedness (G2, G3)

- Stage guard `MAX_ITERATIONS=5`; finish-pr counters A 5, B 5, C 3, W 6 (each wait ≤ 540 s), R 3; workflow counters fix 5, wait 6, request 3, gate 3; `ai-review-loop.sh` default 5 (cap 20); setup `--refresh` retries 5; new-context remediation 5; new-service poll 10 × 3 s, bootstrap ≤ 60 min; `make start` wait ≤ 900 s (QA boot and the FR-1 container precondition, one restart attempt); QA liveness poll ≤ 900 s; every backgrounded call polled at most every 30 s and bounded by its stage's budget (a poll that outlives the budget ends `ESCALATED` with the log tail).
- Scripts contain no unbounded loop (`while true`, `until false`) without a numeric guard.
- On any breach: the 7-field escalation block and a run report.
- **AC:** contract tests for every cap (AC-1.1, AC-21.1); harness exhaustion scenarios (AC-19.2, AC-21.2); a bats grep finds no `while true` in `scripts/`; overflow inputs rejected (AC-7.1, AC-34.1).

### NFR-7 — Portability (RG, G1)

- bash ≥ 4.4 and git ≥ 2.30, the floors of the template's `make doctor` that every gate runs behind (scripts check `BASH_VERSINFO` and exit 1 with the remediation "install Bash 4.4 or newer" below 4.4, e.g. macOS's bash 3.2); Linux (GNU userland) and macOS (BSD userland); no `readlink -f`, `sed -i`, `date -d`, `grep -P` or `stat -c` (in-place edits go through `mktemp` + `mv` or python3); python3 is used for portable path, JSON, YAML and TOML work.
- YAML: mikefarah `yq` v4 (by `!!seq` probe) else python3 + PyYAML; JSON: jq else python3; TOML: python3 ≥ 3.11 `tomllib` only.
- **AC:** backend-parity cases (`SDLC_FORCE_PYTHON_YAML=1`) in `common-lib.bats`, `validate-profile.bats`, `generate-profile.bats`, `ai-review-loop.bats`; a bats grep for the banned constructs over `scripts/`; CI `shellcheck -x` 0 findings.

### NFR-8 — Testability (RG)

- Every script has a suite covering each documented flag, each exit code, each refusal and `--help`.
- Per-suite floors: `ai-review-loop` 23, `common-lib` 36, `component-counts` 20, `fr-nfr-gate` 50, `generate-profile` 30, `get-pr-comments` 31, `inject-governance` 30, `post-review-findings` 41, `setup-preflight` 23, `validate-profile` 30, `merge-settings` 15, `new-service` 30, `stage-planning-artifacts` 12, `pr-state` 30, `request-ai-reviews` 17, `workflows` 45 → ≥ 460 total (≥ 415 after the cut).
- Hermetic: stubs, `$BATS_TEST_TMPDIR`, no network; permission tests skip under uid 0 with a reason; yq tests gate on `have_yq`; K7 linter cases skip locally only when the tool is absent (they run in CI); every skip prints its reason.
- Lint: `lint_all.py` 0 findings; `shellcheck -x` 0; markdownlint-cli2 0.
- **AC:** CI `bats`, `shellcheck`, `markdown-lint`, `frontmatter-check` green; `grep -c '^@test'` per suite ≥ its floor (asserted in `component-counts.bats`).

### NFR-9 — Observability of runs (G2)

- Every `/rs-sdlc` exit path emits `=== SDLC RUN REPORT ===`; every stage-command exit path emits either its success handles or an escalation block — never silence.
- `blocking_finding` is concrete: `file:line`, check name + URL, or command + exit code.
- State comment rows (FR-3), the cache JSON, review ledgers (`{lens, iteration, head_sha, findings: [{id, severity, file, line, rule, summary, status}]}`), logs `target/rust-sdlc/logs/<stage>-<UTC>.log`, the targets-run list (FR-1) in reports and the PR body, and aggregated `degrade_notes`.
- **AC:** contract tests on report and escalation fields; ledger schema cases in `post-review-findings.bats`; harness scenarios assert a report on every terminal path.

### NFR-10 — Security (G2, RG)

- Redaction (`redact` in `lib/common.sh`) applied before every publish (PR/issue comments, state comment, PR body, gate comment): AWS key ids, JWTs, GitHub tokens (`gh[pousr]_…`), `password|passwd|secret|token|apikey|api_key` assignments, URL credentials, long high-entropy strings.
- The gate's model session reads contributor-controlled text only inside `claude_run_isolated` (no shell, no edits, no credentials); prompts frame PR/issue text as data.
- Least privilege: QA command and agent without `Write`/`Edit`; reviewers and `security-auditor` without `Write`/`Edit`; agents never hold git push rights (commands push).
- QA network: loopback (`localhost`, `127.0.0.1`) on `service.port` only.
- Poster writes only to the origin repository's own PR; `--spec-path` and dest paths contained in the repository; symlink refusal; inputs validated (`is_slug`, `is_kebab`, numeric guards); no `eval` of input; the generator never reads `.env.local` (the template denies it).
- **AC:** one redaction case per rule; isolation argv asserted; base-repo refusal; containment and symlink cases; bats grep finds no `eval` in `scripts/`.

### NFR-11 — Installability and load integrity (RG)

- After `claude plugin install rust-backend-sdlc@vilnacrm-plugins`, components load as `rust-backend-sdlc:<name>`: 10 commands, 7 agents, 28 skills, 2 meta-guides; `${CLAUDE_PLUGIN_ROOT}/scripts/…` and `…/skills/…/SKILL.md` references resolve (L19, L20); no dependency on copies in the target repository.
- No `_bmad` or `.ralph` path component anywhere in the plugin tree, fixtures included.
- **AC:** `component-counts.bats` pins 10/7/28/2/13/4/9; L19, L20, L29 0 findings.

### NFR-12 — Token-cost bounds (G2)

- Triage verdicts for 28/28 skills from frontmatter + decision guide; full bodies and reference files only for EXECUTE verdicts; one verdict per counterpart pair.
- **AC:** release gate (static): `component-counts.bats` asserts that `rs-sdlc-review.md` pins 28 verdicts (AC-19.1) and that the decision guide's "workflow/docs-only" change class marks ≤ 6 skills `EXECUTE` (AC-19.3, AC-32.2). Post-release: the reference run (K10) records the number of full skill bodies loaded for a docs-only diff (target ≤ 6). The harness cannot observe which bodies a model loads, so it asserts nothing here.

### NFR-13 — Template compatibility of written files (G1, G4)

- Files the plugin writes into a service pass the service's own tooling: `.claude/rust-sdlc.yml` → yamllint (template config) + `prettier --check`; `bmalph/config.json` → Prettier; `CLAUDE.md`, `AGENTS.md`, `README.md`, `CHANGELOG.md` → markdownlint-cli2 (template config) + typos; governance block → docs-check rules 1–4 and invariant (e) (no literal `rust-service-template`, FR-8); docs after a sync-flavour deletion → docs-check rule 3 (FR-12 citation repair).
- Plugin state lives only in git-ignored locations (`target/rust-sdlc/`, `_bmad-output/planning-artifacts/`, `.claude/settings.local.json`); bundles under `specs/` (excluded from the template's linters); nothing written into `.claude/skills/` or `scripts/`.
- **AC:** K7 cases in `generate-profile.bats`, `inject-governance.bats`, `new-service.bats` run in CI with the pinned tools.

### NFR-14 — Runtime bounds (G1, G2)

- No foreground tool call exceeds 600 s: every `make` call outside the five-target foreground allowlist, every `git commit`/`git push` and `bmalph run` are backgrounded and polled (FR-1), and container mode starts the stack first (D25); `generate-profile.sh`, `validate-profile.sh`, `inject-governance.sh`, `merge-settings.sh` each finish in ≤ 5 s on the stub fixture (no cargo, no make, no network); the plugin's bats suites finish in ≤ 10 min in the CI `bats` job; new-service hands-on ≤ 15 min (K9); bootstrap PR ≤ 2 h wall clock (K13).
- **AC:** bats timing cases with a 5 s budget per script; CI job duration; K9/K13 in the walkthrough.

### NFR-15 — Drift resistance and maintainability (RG, G2)

- Template lists read at runtime (`make ci-list` / `CI_*_TARGETS`, `cargo xtask config-guard --list`, `make help`, `docs/repository-settings.md`); never restated in skills except as sourced examples.
- Single-sourced shared names (`BMAD FR/NFR Review Gate`, `SDLC_FORCE_PYTHON_YAML`, `SDLC_LEDGER_DIR`) byte-identical with the sibling plugins; component counts and exit strings pinned by tests; `template.source_commit` recorded when known.
- **AC:** `component-counts.bats` asserts the shared names are byte-identical to the php/react scripts; grep tests for runtime-read lists.

### NFR-16 — Version floors (G1, RG)

- bmalph ≥ 2.11.0; `claude` ≥ 2.1.248 (`--restricted`); `gh` ≥ 2.0; python3 ≥ 3.11; GNU make ≥ 4.0; bash ≥ 4.4; git ≥ 2.30; node ≥ 20 (bmalph installer, workflow harness); jq optional.
- **AC:** AC-10.1; `README.md` and `docs/setup-walkthrough.md` list the same floors (bats compares).

## Success Criteria

### User success

- **Sam (service creator):** the bootstrap PR passes every non-human-gated required check on its first push; every remaining human decision is a printed `NEXT:` line, none discovered in CI (K13).
- **Alex (feature engineer):** 0 manual interventions between `/rs-sdlc "<task>"` and a ready PR for the reference task (K10); every escalation names the exact human action (a label, a protected change with `ALLOW_PROTECTED_CONFIG_EDIT=1`, an advisory without a fix).
- **Jordan (reviewer):** every plugin PR body lists targets run and not run with reasons and carries `Closes #N`; exactly one conclusion comment per review lens; the gate status is on the head SHA.
- **Platform team:** 0 template changes and 0 protected-file edits needed to adopt the plugin; re-running setup after a template-sync merge restores governance with 0 changes to user-owned text.

### Technical success (release gate, all required for v0.1.0)

1. K1 — `python3 tools/plugin-quality/lint/lint_all.py` reports 0 findings for every plugin.
2. K2 — every `ci.yml` job green, with `profile-keys-check` and `generalization-audit` covering `plugins/rust-backend-sdlc` and the `rust-backend-sdlc-v*` tag filter present.
3. K3 — `component-counts.bats` pins 10 commands / 7 agents / 28 skills / 2 meta-guides / 13 scripts + lib / 4 workflows / 9 docs (post-cut 0 workflows, 8 docs).
4. K4 — 16 bats suites (15 post-cut), ≥ 460 tests (≥ 415 post-cut), 0 failures, per-suite floors met, skips only for uid 0 or an absent optional tool with a reason.
5. K5 — 0 `shellcheck -x` findings; 0 markdownlint-cli2 findings under `plugins/`.
6. K6 — 0 denylist hits in the four scanned directories outside profile-example fences.
7. K7 — on the stub fixture: yamllint + Prettier on the profile, Prettier on `bmalph/config.json`, markdownlint-cli2 + typos on `CLAUDE.md`, `AGENTS.md`, `README.md`, `CHANGELOG.md`, static docs-check rules 1–4 and invariant (e) (neither `rust-service-template` nor the fixture's `TEMPLATE_REPOSITORY` name in anything written to `CLAUDE.md`/`AGENTS.md`) on the governance block, 0 rule-3 violations after either sync-flavour deletion, byte-identical second injection — all in CI.
8. K8 — (epic 8) all harness scenarios pass, static call-graph depth ≤ 1, leaves pass under `--as-child`.
9. Every FR acceptance criterion marked as a bats, lint or contract check passes; the traceability matrix has no orphan FR/NFR and no uncovered goal (verified in implementation readiness).

### Measurable outcomes (post-release)

| Id | Outcome | Target | When |
| --- | --- | --- | --- |
| K9 | New-service hands-on time | ≤ 15 min (A14) | first new service |
| K10 | Reference feature run (CRUD resource in a new bounded context on a fresh service), setup with `merge-settings.sh --with-qa-network` | `result: SUCCESS`, 0 interventions, run report attached to docs | first release cycle |
| K11 | Escalation precision | 100% of `ESCALATED` runs carry the 7-field block with a concrete `blocking_finding`; 0 PRs merged with a relaxed bar | ongoing |
| K12 | Adoption | ≥ 1 service created with `/rs-sdlc-new-service` and ≥ 1 feature PR finished with `/rs-sdlc` (`gh search prs --owner <org> "initialize service from template" in:title`, `gh search issues --owner <org> --label rust-backend-sdlc`) | first release cycle |
| K13 | Green bootstrap PR | all non-human-gated required checks green on the first push; 0 edits beyond printed `NEXT:` steps; ≤ 2 h from S1 | first new service |

## Assumptions

PRD-level decisions (this stage):

> Assumption: **PA-1 — Profile key set.** FR-5 fixes the key set and spellings (resolves brief OQ1 within A2/A3). Architecture may add keys; renaming one requires a recorded decision and a schema-doc update in the same change. Namespaces `rust`, `service`, `template` are invisible to L25, so `component-counts.bats` covers them (AC-5.2).
>
> Assumption: **PA-2 — Mechanical `make.*` naming.** Key = template target with `-` replaced by `_` (e.g. `make.tests_with_coverage`), plus the four plugin-substitutable keys. This makes generation and validation mechanical; PHP's `make.security` becomes `make.check_security`, and its null substitution is the `security-auditor` static lane.
>
> Assumption: **PA-3 — Dirty template path (brief OQ2).** `new-service.sh --template-path` refuses a checkout with uncommitted tracked changes (exit 1), because `git archive HEAD` would silently drop them.
>
> Assumption: **PA-4 — Test floor (brief OQ3).** ≥ 460 tests across 16 suites with per-suite floors anchored on the PHP and React counterparts (NFR-8).
>
> Assumption: **PA-5 — Security lens trigger (brief OQ4).** The lens runs when the diff since the merge base touches `*.rs`, `Cargo.toml`, `Cargo.lock`, `migrations/`, `.sqlx/`, `deny.toml`, `Dockerfile` or `.github/workflows/`; later iterations re-run it only if that iteration's remediation touched those paths.
>
> Assumption: **PA-6 — Human-gated checks (brief OQ5).** `ci.human_gated` holds GitHub **check names**, the same name space as `ci.required_checks` and a subset of it, because GitHub reports check runs under the job `name:` (`tpl/.github/workflows/change-control.yml:53,72,88`). `generate-profile.sh` parses both sentence forms of the "Labels to create" table of `docs/repository-settings.md` ("without it the job `<j>` fails", "without it the jobs `<a>` and `<b>` fail") and maps each job id to its "Check name" through the job tables of `docs/repository-settings.md` or `docs/repository-settings-service.md`: today `Protected configuration` (job `validate-configuration`), `OpenAPI breaking changes` (`openapi-diff`) and `GraphQL breaking changes` (`graphql-diff`). The profile may override; `pr-state.sh --human-gated-checks` consumes it; job ids never appear in either list.
>
> Assumption: **PA-7 — Stage validity on resume.** Requiring `head_sha == HEAD` for every stage (brief A9 wording) would re-run implement after each review remediation commit. Issue, plan and implement therefore count as done when their `head_sha` is an ancestor of `HEAD`; review and QA only when equal; finish-pr is always re-derived live.
>
> Assumption: **PA-8 — Sensor budgets.** In addition to A/B/C, finish-pr bounds WAIT (W ≤ 6 waits of ≤ 540 s) and REQUEST (R ≤ 3), the React counters, so the sensor loop is bounded (NFR-6).
>
> Assumption: **PA-9 — Workflow epic in scope.** Restating A13: epic 8 ships in v0.1.0 as the cut line (deterministic harness, node + jq only in CI, hand-back contract removes the nesting risk).
>
> Assumption: **PA-10 — `--restricted` is a preflight FAIL.** The FR/NFR gate is mandatory at review and finish-pr and cannot run without the restricted sandbox; failing at setup is cheaper than failing at stage 4.
>
> Assumption: **PA-11 — Section names.** The orchestrator's required H2 set governs this file; the template's planning skill format (with `Product Scope`) governs bundles that `/rs-sdlc-plan` writes in services (FR-16).
>
> Assumption: **PA-12 — Container switch.** `capabilities.run_in_container` is a gating boolean (L18-visible). Precedence: `generate-profile.sh --run-in-container true|false` (passed by `/rs-sdlc-setup --exec host|container`, which new-service S12 calls with its own resolved `--exec`) > the value already in the profile (kept on `--refresh`, so a hand flip survives) > detection (Docker reachable and no host `cargo`). In container mode the commands start the stack before the first TOOL target (FR-1, D25).
>
> Assumption: **PA-13 — Mutation per iteration.** `make mutation-tests-diff` is the slowest gate and diff-scoped, so review iteration 1 runs it when the branch diff against `ci.base_ref` touches production `*.rs` (after `git add` of new files), and iteration n > 1 re-runs it only when that iteration's remediation touched production `*.rs`; a skipped row carries the previous verdict as `not run (not changed)`. `quality.max_surviving_mutants` is therefore always verified before the PR whenever production code changed.
>
> Assumption: **PA-14 — QA allowlist spelling.** The URL-first loopback `curl` entry form is fixed in architecture after checking Claude Code's prefix semantics; `qa-manual-tester` always uses that exact form.
>
> Assumption: **PA-15 — Stage exit strings.** The strings in FR-3's table are the single source; commands, report and docs copy them byte for byte (AC-1.3).
>
> Assumption: **PA-16 — `make.logs` dropped from the key set (amends PA-1).** The template's `logs` target runs `docker compose logs --follow` and never exits (`tpl/Makefile:165-167`), so no plugin component may invoke it (NFR-14). The only log read is the bounded raw call `docker compose logs --no-log-prefix --tail 200 app` (FR-1 exception (5)). The `make` group has 55 keys.
>
> Assumption: **PA-17 — Two implementation paths, one implementer each.** Command path: `bmalph run` is the only implementer; the command dispatches nothing while it runs, and Ralph's own sessions apply the story-dispatch rule carried by `architecture.md ## Constraints` → `.ralph/PROJECT_CONTEXT.md` (FR-16, FR-18). Workflow path (`rs-sdlc-feature.js`): it runs `stage-planning-artifacts.sh` + `bmalph implement` so the plan is staged and Ralph's fix plan exists, then executes that fix plan through orchestrated `rust-implementer` rounds and never runs `bmalph run` (a Workflow script cannot drive Ralph's loop, and two implementers would race); this is recorded as the degrade note `bmalph run: not used (workflow path)`. This matches the task framing ("stories are executed by orchestrated agents following the Ralph fix plan") and G2's bmalph/Ralph implementation holds on the command path.
>
> Assumption: **PA-18 — Resume logic is a tested helper.** The PA-7 rules live in `resume_point` (`lib/common.sh`), so G2(c) is proven by `common-lib.bats` (fresh clone without cache, ancestor/equal/live rules, stale QA) rather than by prompt text alone; the workflow path resumes only within a run (`carry`).
>
> Assumption: **PA-19 — Docker is a precondition, not a gate result.** Because the template's HOST targets exit 2 with `This target needs a reachable container engine (docker).` and the test targets need the compose database, a Docker-less host can run only `ci-static-analysis` in host mode; review, implement, new-context C12 and QA therefore escalate without Docker (D2), and the `CI_DELIVERY_TARGETS` that review never runs are recorded `not run (deferred to PR CI)` and judged by finish-pr from the required checks.
>
> Assumption: **PA-20 — Sync-flavour citation repair.** Deleting one sync flavour exactly as `docs/new-service.md` §9 says breaks docs-check rule 3 through `tpl/docs/extension-seams.md:82` (verified on a template copy). `new-service.sh` repairs the citation (bare file name + `.templatesyncignore` entry) instead of stopping with a `NEXT:` line, because G1(a) promises 0 manual file edits; the template defect is raised upstream (Open Question 6).
>
> Assumption: **PA-21 — Background by allowlist.** Long-running calls are identified by a closed foreground allowlist (`make.ci_list`, `make help`, `make.check_commit_message`, `make.doctor`, `make.install_hooks`) rather than a list of slow targets, because any TOOL target and every hooked `git commit`/`git push` can exceed 600 s on a cold `target/` (FR-1, NFR-14).

Carried brief assumptions (binding; full text in `product-brief.md`): A1 template-derived repositories are first-class, detected by seven markers + `CI_PREFLIGHT_TARGETS`; A2 the 12 threshold keys (NFR-4); A3 profile namespaces (now fixed by PA-1); A4 QA network opt-in via `--with-qa-network`, precondition of K10; A5 example context never removed by the script; A6 lint widening after the plugin; A7 `is_template` probe then template flow or clone-and-push; A8 GraphQL roots replaced, never deleted; A9 state comment as the durable record (refined by PA-7); A10 Docker-less QA escalates when `make.start` is mapped; A11 React not added to the key check; A12 workflow names escalate gracefully; A13 workflow epic included; A14 15-minute hands-on excludes downloads/compiles; A15 live evidence is post-release; A16 28 skills over the "about 25" guidance; A17 tool floors; A18 new contexts need an issue; A19 the plugin creates only its own label; A20 new-service ownership (script edits, command commits); A21 standalone context runs hand off to review → QA → finish-pr; A22 setup on a dirty tree continues with a `DEGRADED:` line.

## Open Questions for Architecture

Non-blocking; each has a recommended default.

1. **Allowlist entry spelling** (PA-14): verify Claude Code `Bash(<prefix>:*)` matching for `RUN_IN_CONTAINER=1 make …` and URL-first `curl`; default: entries as in FR-9, adjusted to verified semantics.
2. **State-comment concurrency:** two `/rs-sdlc` runs on one issue could interleave PATCHes; default: read-modify-write with an `updated_at` check and one retry, then escalate.
3. **Ledger schema versioning:** add `schema_version` to ledger JSON; default: `1`, validated by the poster.
4. **Template-detection evolution:** when the template renames a marker file, default to WARN (not FAIL) and record `capabilities.template_derived: false` until the plugin updates.
5. **Workflow ↔ script data exchange:** default: workflows call scripts and parse their `--json` output; no shared JS module.
6. **Upstream template suggestion (PA-20):** `docs/extension-seams.md:82` should cite the sync guides by bare file name, like `docs/new-service.md` and both guides already do, so that deleting a flavour needs no edit; default: the plugin repairs it in `new-service.sh` and the suggestion is filed against the template; when the template fixes it, the repair step finds nothing and prints `UNCHANGED: docs-check citations`.
7. **Plugin agents inside Ralph's sessions (PA-17):** whether `rust-backend-sdlc:rust-implementer` resolves inside the claude-code sessions `bmalph run` starts depends on the plugin's install scope; default: a user-scope install makes it available, otherwise Ralph implements stories sequentially under the same DB rule (the `## Constraints` text covers both).
8. **Container-route permission spelling (FR-1, FR-9):** verify how Claude Code's `Bash(<prefix>:*)` matching treats `docker compose exec -T --user "$(id -u):$(id -g)" app …` (command substitution may force a prompt); default: resolve the uid/gid once into literals before the call and allow the literal prefix.

## Traceability

### FR → goals and journeys

| FR | Title | Goals | Journeys |
| --- | --- | --- | --- |
| FR-1 | Shared command contract | G2, RG | J2, J3, J4, J5 |
| FR-2 | Hook-valid git conventions | G1, G2, G3, G4 | J1, J2, J3, J5 |
| FR-3 | `/rs-sdlc` orchestrator | G2 | J2, J4, J6 |
| FR-4 | `/rs-sdlc-setup` | G1, G4 | J1, J6 |
| FR-5 | Profile schema | G1, G4 | J1, J2, J6 |
| FR-6 | `generate-profile.sh` | G1 | J1, J6 |
| FR-7 | `validate-profile.sh` | G1, G4 | J1, J2, J6 |
| FR-8 | `inject-governance.sh` | G1, G4 | J1, J6 |
| FR-9 | `merge-settings.sh` | G1, G4 | J1, J6 |
| FR-10 | `setup-preflight.sh` | G1 | J1, J6 |
| FR-11 | `/rs-sdlc-new-service` | G1 | J1 |
| FR-12 | `new-service.sh` | G1 | J1 |
| FR-13 | `config/new-service.defaults.json` | G1, RG | J1 |
| FR-14 | `/rs-sdlc-new-context` | G3 | J3 |
| FR-15 | `/rs-sdlc-issue` | G2, G3 | J2, J3 |
| FR-16 | `/rs-sdlc-plan` | G2, G3 | J2, J3 |
| FR-17 | `stage-planning-artifacts.sh` | G2 | J2 |
| FR-18 | `/rs-sdlc-implement` | G2, G3 | J2, J3 |
| FR-19 | `/rs-sdlc-review` | G2, G3, G4 | J2, J3, J4 |
| FR-20 | `/rs-sdlc-qa` | G2, G3 | J2, J3, J4 |
| FR-21 | `/rs-sdlc-finish-pr` | G1, G2, G3 | J1, J2, J3, J5 |
| FR-22 | Shared agent contract | G2, G4 | J2, J3, J5 |
| FR-23 | `rust-implementer` | G2, G3, G4 | J2, J3 |
| FR-24 | `code-quality-reviewer` | G2, G4 | J2, J3 |
| FR-25 | `fr-nfr-reviewer` | G2 | J2, J5 |
| FR-26 | `qa-manual-tester` | G2 | J2, J3 |
| FR-27 | `ci-fixer` | G2 | J5 |
| FR-28 | `pr-comment-resolver` | G2, G4 | J5 |
| FR-29 | `security-auditor` | G2, G4 | J2, J3 |
| FR-30 | Skill library | G2, G4, RG | J2, J3 |
| FR-31 | Rust-only skills | G1, G3 | J1, J3 |
| FR-32 | Meta-guides and triage | G2, RG | J2, J3 |
| FR-33 | `lib/common.sh` + script contract | G1, G2, G3, G4, RG | J1–J6 |
| FR-34 | `ai-review-loop.sh` | G2 | J5 |
| FR-35 | `fr-nfr-gate.sh` | G2 | J2, J5 |
| FR-36 | `get-pr-comments.sh` | G2 | J5 |
| FR-37 | `post-review-findings.sh` | G2 | J2, J5 |
| FR-38 | `pr-state.sh` | G2 | J4, J5 |
| FR-39 | `request-ai-reviews.sh` | G2 | J5 |
| FR-40 | Manifest and README | RG | (install) |
| FR-41 | Documentation set | G1, RG | J1, J6 |
| FR-42 | Test suites and fixtures | RG | — |
| FR-43 | Marketplace and CI wiring | RG | (install) |
| FR-44 | Workflow epic | G2 | J2, J4, J5 |

### NFR → goals

| NFR | Goals |
| --- | --- |
| NFR-1 Idempotence | G1, G4 |
| NFR-2 Generalization | RG, G1 |
| NFR-3 Degrade matrix | G2 |
| NFR-4 Tighten-only bars | G4 |
| NFR-5 Safety | G2, G4 |
| NFR-6 Boundedness | G2, G3 |
| NFR-7 Portability | RG, G1 |
| NFR-8 Testability | RG |
| NFR-9 Observability | G2 |
| NFR-10 Security | G2, RG |
| NFR-11 Installability | RG |
| NFR-12 Token cost | G2 |
| NFR-13 Template compatibility | G1, G4 |
| NFR-14 Runtime bounds | G1, G2 |
| NFR-15 Drift resistance | RG, G2 |
| NFR-16 Version floors | G1, RG |

### Goal → requirements (reverse check)

| Goal | FRs | NFRs |
| --- | --- | --- |
| G1 | FR-2, FR-4 to FR-13, FR-21, FR-31, FR-33, FR-41 | NFR-1, NFR-2, NFR-7, NFR-13, NFR-14, NFR-16 |
| G2 | FR-1 to FR-3, FR-15 to FR-30, FR-32 to FR-39, FR-44 | NFR-3, NFR-5, NFR-6, NFR-9, NFR-10, NFR-12, NFR-14, NFR-15 |
| G3 | FR-2, FR-14 to FR-16, FR-18 to FR-21, FR-23, FR-31, FR-33 | NFR-6 |
| G4 | FR-2, FR-4, FR-5, FR-7 to FR-9, FR-19, FR-22 to FR-24, FR-28 to FR-30, FR-33 | NFR-1, NFR-4, NFR-5, NFR-13 |
| RG | FR-1, FR-13, FR-30, FR-32, FR-33, FR-40 to FR-43 | NFR-2, NFR-7, NFR-8, NFR-10, NFR-11, NFR-15, NFR-16 |

Reverse check: FR-1 to FR-44 and NFR-1 to NFR-16 each map to at least one goal; each goal G1–G4 and RG maps to at least one FR and one NFR; each journey J1–J6 maps to at least one FR. Brief scope items 1–13 map to FR-40 (1), FR-1/FR-3/FR-15–FR-21 (2, 8), FR-22–FR-29 (3), FR-30–FR-32 (4), FR-5–FR-7 (5), FR-4/FR-8–FR-10 (6), FR-11–FR-14 (7), FR-33–FR-39 (9), FR-44 (10), FR-41/FR-42 (11), FR-43 (12); item 13 (this bundle) needs no FR.

## Revision Log

Reviser pass of 2026-11-12 over 41 findings (in the order received). Each was verified against the cited source (template at `3e0bd3e`, `react/`, `php/`, bmalph `dist/`, `tools/plugin-quality`); duplicates were applied once and are marked so. 41 applied, 0 rejected.

| # | Finding (location) | Verdict | Rationale / where applied |
| --- | --- | --- | --- |
| 1 | `ci.human_gated` vs `ci.required_checks` name spaces (PA-6, FR-5, J5, D9, AC-21.3) | applied | verified `change-control.yml:53,72,88` job names; both keys now hold check names; AC-6.5 derives the three names, AC-21.3/AC-38.1 match a spaced name |
| 2 | required checks of service-added workflows ignored (FR-5, FR-6) | applied | verified `repository-settings.md` intro and `check-invariants.sh:686-690`; union with `docs/repository-settings-service.md` in FR-5/FR-6/FR-38, fixture in FR-42, AC-6.5 |
| 3 | quality rows ↔ 12 keys mismatch (FR-19, NFR-4, AC-19.1) | applied | explicit Q1–Q15 table with keys or "binary gate"; image-scan and smoke keys assigned to the security lane / finish-pr; exit string now "every quality row PASS" (FR-3, FR-19) |
| 4 | `validate_context_name` narrower than xtask (FR-14, FR-33, G3(a), FR-5) | applied | verified `scaffold.rs` `existing`/`listed` and `name/tests.rs:80-84`; four live-tree rules, group `service` accepted, AC-14.1 cases, `bounded_contexts` derivation in FR-6 (includes `internal/health-check`) |
| 5 | `--exec` choice lost (FR-4, FR-6, FR-11, PA-12) | applied | `--exec` on setup, `--run-in-container` on the generator, precedence flag > profile > detection, S12 pass-through, AC-6.6 |
| 6 | background rule a closed list; no container precondition (FR-1, FR-4 step 8, NFR-14) | applied | verified `Makefile:441-446` and the hooks; foreground allowlist rule (PA-21), container precondition, AC-1.1 assertion, D25 |
| 7 | AC-5.2 dotted-key scan hits file names | applied | anchored namespace regex with file-extension exclusion stated in AC-5.2 |
| 8 | invariant (e) uses a fixed literal (AC-8.2, G1(c), G4(d), K7, NFR-13) | applied | verified `check-invariants.sh:50-51,711-735`; AC-8.2 asserts absence of the literal and of the fixture name; FR-8 note |
| 9 | workflow path has no bmalph step (FR-44, AC-3.4, AC-18.2, G2(c)) | applied | hybrid of option (b): workflow stages with `bmalph implement`, executes Ralph's fix plan via `rust-implementer`, never `bmalph run`, degrade note; scenarios replaced; G2(c) names `resume_point` (PA-17, PA-18) |
| 10 | stage-3 dispatcher undefined (FR-18, FR-16) | applied | verified bmalph `context.js:89-91`; `bmalph run` is the only implementer; dispatch rule carried by `## Constraints` and checked in `.ralph/PROJECT_CONTEXT.md`; AC-16.1, AC-18.1 |
| 11 | FR-12 usage vs FR-13 fallback; missing defaults | applied | optional source and `--description`; defaults for description, owner, intro, version; AC-12.6 |
| 12 | AC-3.1 says 9 run-report fields | applied | 8 fields named in FR-3 and AC-3.1 |
| 13 | status vocabulary vs run report; `DEGRADED` outcome | applied | mapping rule in FR conventions and FR-3; D5 → SUCCESS-WITH-REPORT; `FR_NFR_REVIEWER` enum stays PASS/FAIL, degrade emits FAIL (FR-1, FR-25) |
| 14 | AC-1.4 token lacks left boundary | applied | ERE with line-start/whitespace/backtick/`(` boundary and a path negative case |
| 15 | AC-2.3 forbids the required `git config --get core.hooksPath` | applied | read-only form exempt; writes still forbidden (P4) |
| 16 | NFR-12 harness measurement untestable | applied | static decision-guide assertion (AC-19.3, AC-32.2); body count moved to K10 |
| 17 | FR-27 Gate column holds gate ids, not targets | applied | verified `make-targets.md` gate table; two-step mapping, `none` → reported, never fixed |
| 18 | S9 `set-version.sh` runs host cargo | applied | verified `set-version.sh:31-32`; container route after S8, `NEXT:` without Docker; FR-1 exception (4) |
| 19 | G2(c) fresh-clone claim vs D10 | applied | qualified "when `gh` is reachable"; fresh-clone `resume_point` case (AC-3.4 a) |
| 20 | observability "backend selector" key undefined | applied | row 17 → "—": template is tracing-only (`Cargo.toml:82-83`), no `observability_emf` |
| 21 | bash 4.0 / no git floor below template's doctor | applied | verified `doctor.sh:103-106`; bash ≥ 4.4 and git ≥ 2.30 in FR-10, NFR-7, NFR-16, product surface, AC-10.1 |
| 22 | wrong rationale "rule 3 reads only tracked files" | applied | verified `check-docs.sh:406` tests on-disk existence; reworded to CI sees only committed files |
| 23 | Docker-less hosts break five of six stages (D2, G3(c), FR-14, J3, FR-19) | applied | verified `REQUIRE_DOCKER` recipes and `ensure-deps`; D2 rewritten as precondition with message-based classification; G3(c) and C12 restated (PA-19) |
| 24 | human-gated job ids; plural label sentence missed | applied | duplicate of 1 plus both sentence forms parsed (FR-6, PA-6) |
| 25 | sync-flavour deletion breaks docs-check rule 3 | applied | reproduced on a template copy; citation-repair sub-step in FR-12, AC-12.5, fixture, Open Question 6 (PA-20) |
| 26 | 13 rows vs 12 keys (FR-19, AC-24.1) | applied | duplicate of 3; AC-24.1 now pins the Q1–Q15 mapping; openapi/graphql diff and Spectral are review rows |
| 27 | grep ACs contradict required content | applied | single pattern set P1–P7 in NFR-5 shared by AC-2.3 and NFR-4; `request-ai-reviews.sh --force` and the read-only hooksPath form exempt |
| 28 | container mode never starts `app`; raw calls lack container route | applied | duplicate of 6 plus container route for raw calls, `tomllib` fallback for the protected list, D25, FR-4 step 8 condition |
| 29 | `make logs` never exits | applied | verified `Makefile:165-167`; bounded `docker compose logs --tail 200` only; `make.logs` dropped (55 keys, PA-16); token test in AC-26.1 |
| 30 | make never returns exit 1; lock fault writes files | applied | verified `cli.rs:180,184` and make's status 2; stderr-prefix classification with `git status --porcelain` (FR-14, J3) |
| 31 | `bounded_contexts` derivation undefined; stale profile | applied | duplicate of 4: derivation in FR-6, validation reads the live tree, stale-profile case in AC-14.1 |
| 32 | review remediation actor unnamed | applied | verified php `sdlc-review.md`; `rust-implementer` via Task, command commits; pinned in AC-19.1 |
| 33 | mutation row ambiguous at iteration 1 | applied | iteration-1 branch-diff rule, carried verdict `not run (not changed)` (FR-19, PA-13) |
| 34 | FR-27 gate ids; service settings document | applied | duplicate of 17 and 2 |
| 35 | L25 flags `persistence.rs` | applied | verified `check_references.py` regex and 3 tracked files; backticked in `docs/profile-schema.md` (FR-41), lint assertion in AC-31.1 |
| 36 | nextest call lacks `env -u DATABASE_URL` | applied | verified `Makefile:41`; FR-1 exception (3) spelled as the template's `TEST_ENV` |
| 37 | AC-3.1 field count | applied | duplicate of 12 |
| 38 | PA-12 `--exec` undefined path | applied | duplicate of 5 |
| 39 | QA never migrates a running stack; liveness flaps | applied | verified compose `migrate` service and watchexec CMD; `make migrate` before probes, bounded double-200 liveness poll (FR-20, AC-20.2, NFR-6) |
| 40 | Ralph vs fan-out actor; workflow without bmalph | applied | duplicate of 9 and 10; wording pinned in AC-18.1 and AC-44.1 |
| 41 | NFR-3 outcome words outside the vocabulary | applied | Outcome column normalised to SUCCESS / SUCCESS-WITH-REPORT / ESCALATED with notes in Behaviour; AC asserts the closed set |

- 2026-11-12 (Phase 4, orchestrator): AC-37.1: `grep -c $'\x00'` replaced by a `tr -cd '\000' | wc -c` NUL-byte count. Bash cannot pass a NUL byte in an argument, so `$'\x00'` expanded to an empty pattern and the check counted every line; it could never pass.

- 2026-11-12 (Phase 4, orchestrator): the workflow scenario set grew from 55 to 103 files after mutation testing of the four workflows, and the plugin tree from 283 to 331 files. New scenarios: `feat-` (15 → 32) `feat-layer-first-batches`, `feat-verify-without-exit-signal`, `feat-verify-blocked`, `feat-parallel-story-blocked`, `feat-qa-loops-exhausted`, `feat-qa-boot-blocked`, `feat-plan-not-ready`, `feat-branch-blocked`, `feat-staging-out-of-order`, `feat-staging-context-part-a-missing`, `feat-fix-branch`, `feat-gate-handback-advisory`, `feat-gate-handback-wrong-pr`, `feat-gate-handback-null-pr`, `feat-gate-handback-clean`, `feat-finish-escalated`, `feat-lowered-caps`; `fnr-` (15 → 23) `fnr-d24-base-head`, `fnr-degrade-notes`, `fnr-fanout-cap`, `fnr-iteration-cap`, `fnr-malformed-handle`, `fnr-no-source-no-pr`, `fnr-verify-blocked`, `fnr-wrong-iteration`; `pug-` (17 → 30) `pug-ci-fixer-blocked`, `pug-d7-once-per-head`, `pug-gate-advisory`, `pug-gate-publish-failed`, `pug-interval-mixed`, `pug-malformed-carry`, `pug-no-ci`, `pug-no-ci-conflicting`, `pug-request-failed`, `pug-resolver-protected`, `pug-sensor-unreachable`, `pug-skipped-reviewer`, `pug-untrusted-thread`; `rp-` (8 → 18) `rp-degraded`, `rp-fail-no-findings`, `rp-fix-blocked`, `rp-lens-blocked`, `rp-lens-protected`, `rp-profile-changed`, `rp-protected`, `rp-reopened`, `rp-security-not-rerun`, `rp-split-vote`. No requirement changed and no floor changed (AC-44.1 keeps `workflows.bats` at 45 cases or more; it holds 115). Workflow defects fixed:
  - `rs-sdlc-feature`: a `GATE` hand-back whose `pr` is null or missing was accepted and spent a gate round; the check is now `finish.pr !== run.pr`, so it escalates (`docs/workflows.md` Hand-back contract step 3: the same `pr`).
  - `rs-sdlc-pr-until-green`: the D8 path emitted two degrade notes for one condition; the workflow now keeps one D8 note (PRD NFR-3: exactly one degrade note).
  - `rs-sdlc-pr-until-green`: an explicit empty `reviewers` list emitted two D7 notes; the workflow now keeps one (PRD NFR-3).
  - `rs-sdlc-pr-until-green`: a clean D7 review pass spent a `fix` round without an iteration-log line; it is now journaled (architecture, the canonical escalation block: `iteration_log`).
  - `rs-sdlc-review-panel`: a `PROFILE_CHANGED:` line got the D23 protected-file remedy; it now gets the ADR-25 profile remedy.
  - `rs-sdlc-review-panel`: the scope schema did not require `protected`, so the branch guard failed open; `protected` is now required.
  - `rs-sdlc-review-panel`: the `PROTECTED:` escalation printed the raw guard line; it now reads `protected file <path> changed (<commit>)` (ADR-25).
  - `rs-sdlc-review-panel`: the D23 `recommended_action` kept the literal `-- <path>` placeholder; it now names the path.
  - `rs-sdlc-review-panel`: a lens finding that quotes `BLOCKED: protected configuration <path>` was refuted or fixed instead of escalating; it now ends `ESCALATED` with that line verbatim (`commands/rs-sdlc-review.md` decision rule 1).
  - `rs-sdlc-fr-nfr-review`: `EXIT_CONDITION` was not the review stage's exit string; it is now `zero new gate findings AND every quality row PASS` verbatim (architecture, the canonical escalation block).
  - `rs-sdlc-fr-nfr-review`: after the D24 fallback (`base_ref=HEAD`) an empty file list returned `SUCCESS-WITH-REPORT` without a gate run; the empty-change-set exit now requires a base other than `HEAD` (`docs/workflows.md`: never passes without a real gate run).

- 2026-11-12 (PR #17 review): NFR-3 rules. "A mapped capability that cannot run ends `ESCALATED`" contradicted D13 and the setup and new-service outcomes of D2, D3, D5 and D25, which end `SUCCESS-WITH-REPORT`; the rule now names those rows as its exceptions, and no row changed (architecture PR-D3).
