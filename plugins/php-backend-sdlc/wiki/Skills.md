# Skills

[Home](Home.md) › Reference › Skills

The php-backend-sdlc plugin ships **22 skills** plus **2 meta-guides**
(`AI-AGENT-GUIDE.md` and `SKILL-DECISION-GUIDE.md`) — each skill lives in
its own `skills/<name>/` directory with a `SKILL.md`, and the two
meta-guides sit at the root of `skills/`. Skills are the
plugin's reusable, repo-portable workflow units: each is a self-contained
markdown file under
[`skills/`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills)
that Claude Code discovers and invokes automatically, and that any other
AI agent can read and follow by hand.

This page covers what a skill is, the applicability-triage model that
governs how skills are selected during a review, the two meta-guides, the
full grouped skill catalog (name, purpose, trigger), and how to discover
which skill fires for a given task.

## What a skill is

A skill is a pure-markdown procedure with YAML frontmatter. The
frontmatter carries a `name` and a `description`; the description states
both **what the skill does** and **when to use it** (and, for several
skills, when to skip it). Claude Code matches that description against the
incoming task to decide whether to invoke the skill. Other agents read
[`AI-AGENT-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md)
and
[`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md)
to do the same selection manually.

Skills are **profile-portable**. They never name a repository-specific
Make target directly; they reference the profile's logical target map
(`make.*` keys in `.claude/php-sdlc.yml`). "The target mapped by
`make.ci`" means: look up `make.ci` in the profile and run that target. A
`null` mapping means the capability is absent — the dependent step is
skipped with an explicit note, never invented. Generic tooling
(`composer`, `gh`) may be invoked directly. See
[Project Profile](Project-Profile.md) for the keys each skill consumes and
[`docs/profile-schema.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md)
for the full schema.

Two non-negotiable rules apply to every skill:

- **Fix root causes.** Never silence a tool with a suppression or ignore
  annotation (`@SuppressWarnings`, `@psalm-suppress`,
  `@infection-ignore-all`, `@codeCoverageIgnore`, `@phpstan-ignore`,
  `phpcs:ignore`, `@phpinsights-ignore*`).
- **Thresholds are raise-only.** Quality floors come from the profile's
  `quality.*` keys; a profile may tighten them, never relax them.
  Violation-count ceilings are fixed at `0`. `deptrac.yaml` and other
  locked quality-tool configs are never edited — the code is fixed to
  satisfy them.

## The applicability-triage model (EXECUTE / NOT-APPLICABLE)

When a **new feature** is created or modified, the skills system runs a
**Mandatory New Feature Verification Gate**: every skill in the directory
must be evaluated after implementation. This is enforced by
`/sdlc-review` and described in
[`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md).
The gate is **triage-first** (ADR-5 / NFR-5):

1. Decide each skill's verdict from its frontmatter `description` plus the
   decision guide **alone** — never load a skill body just to decide.
   Record exactly one verdict per skill:
   - **EXECUTE** — with a concrete one-line trigger.
   - **NOT-APPLICABLE** — with a concrete reason.
2. Open a skill's `SKILL.md` body **only after** recording an EXECUTE
   verdict for it, then follow its steps exactly. NOT-APPLICABLE verdicts
   are recorded without loading the body. This keeps token cost bounded:
   full bodies and reference files load only for EXECUTE verdicts (NFR-5).
3. Run required commands only through the profile's `make.*` target map.
4. Capability-gated skills are recorded NOT-APPLICABLE with a note when
   their flag is `false` or their target maps to `null` —
   `structurizr-architecture-sync` (`capabilities.structurizr`) and
   `load-testing` (`capabilities.load_testing` + `make.load_tests`).
   `observability-instrumentation` is **not** skip-gated:
   `capabilities.observability_emf` only selects its emission backend, so
   when `false` you evaluate its generic metrics-backend branch instead of
   skipping.
5. Provide evidence — commands run and outcomes — for EXECUTE skills.
6. Do not claim the feature complete until the gate is finished.

The gate contract is blunt: **every skill verdict recorded, no silent
skips.** The decision tree (below) only helps pick the *primary* skill for
the work in progress; it does not replace the gate.

Two skills have special gate handling:

- `bmad-fr-nfr-review-gate` is EXECUTE only when BMAD specs exist for the
  implemented work (run via the `make.fr_nfr_gate` target; the plugin
  substitutes its own gate script when the mapping is `null`); otherwise
  record NOT-APPLICABLE with the reason.
- `bmad-autonomous-planning` is a planning-time skill; during the gate
  record "Not applicable — planning skill" unless the task itself was to
  produce specs.

## The two meta-guides

The two files at the root of `skills/` are not skills themselves; they
orchestrate skill selection.

| Meta-guide | Purpose | Audience |
| --- | --- | --- |
| [`AI-AGENT-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md) | How the skills system works for **non-Claude agents** (Codex, Copilot, Cursor): manual discovery, the verification gate, the `make.*` target convention, protected thresholds, the locked-config exception policy, and per-task example workflows. | Other AI coding agents |
| [`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md) | How to **choose the right skill**: the triage execution rules, the Quick Decision Tree, scenario-based routing, the skill relationship map, the common-confusions table, and multi-skill task recipes. | All agents |

### AI-AGENT-GUIDE

`AI-AGENT-GUIDE.md` targets agents other than Claude Code. Claude Code
discovers and invokes skills automatically through its `Skill` tool;
everyone else reads skill files and follows the steps by hand. The guide
documents:

- The five-step quick start: understand the task, read the decision guide,
  read the chosen `SKILL.md`, follow execution steps, check supporting
  files (`reference/`, `examples/`).
- The mandatory **Step 0** New Feature Verification Gate, stated in the
  same triage-first terms as the decision guide.
- The command convention (logical `make.*` targets, `null` means skip).
- The protected-threshold table and the **Locked Configuration Exception
  Policy** — accidental config drift is reverted and CI re-run; deliberate
  config changes go in a dedicated governance PR with human approval, and
  "merge with red CI" is never normalized.
- The note that only `security-audit` prescribes dispatching a subagent
  (`security-auditor`, one per OWASP/vuln family); non-Claude agents that
  cannot dispatch subagents apply its per-family probe-and-report contract
  sequentially.

### SKILL-DECISION-GUIDE

`SKILL-DECISION-GUIDE.md` is the routing brain. It opens with the
non-negotiable root-cause rule, lists the profile keys the skills consume,
defines the verification gate and its triage rules, then provides four
selection aids:

- A **Quick Decision Tree** keyed on intent (fix / create / refactor /
  review / document / diagram).
- A **scenario-based guide** — short "I need to X → use skill Y, NOT skill
  Z" entries.
- A **skill relationship map** showing how skills feed into each other.
- A **common-confusions table** that disambiguates lookalike pairs (for
  example, deptrac-fixer vs implementing-ddd-architecture, testing-workflow
  vs load-testing, security-audit vs code-review).

It also lists **multi-skill recipes** for composite tasks such as
"creating a complete new feature" and "performance optimization".

## Skill catalog (grouped)

The 22 skills are grouped below by concern. Each row gives the skill name
(linked to its source), its purpose, and what triggers it. Skip
conditions are noted where the skill is capability- or framework-gated.

### Architecture & DDD

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [implementing-ddd-architecture](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/implementing-ddd-architecture/SKILL.md) | Design and implement DDD patterns (entities, value objects, aggregates, CQRS) with strict hexagonal layer separation. | Creating new domain objects, implementing bounded contexts, designing repository interfaces, or deciding proper layer placement for new code. For fixing existing Deptrac violations, use deptrac-fixer instead. |
| [code-organization](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/code-organization/SKILL.md) | Enforce "Directory X contains ONLY class type X", DDD naming, type safety, SOLID, factory usage, and hardcoded-config extraction to `.env`. | Placing new classes, reviewing structure, refactoring (move/rename/split), fixing CI failures from structural or naming issues, or extracting hardcoded config values. |
| [deptrac-fixer](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/deptrac-fixer/SKILL.md) | Diagnose and fix Deptrac architectural violations by refactoring code to respect hexagonal boundaries. Never modifies `deptrac.yaml`. | Deptrac reports "must not depend on", layers are coupled, Domain imports framework code, or Infrastructure calls Application handlers directly. |
| [clean-architecture-llm](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/clean-architecture-llm/SKILL.md) | Design LLM-powered modules with Clean Architecture boundaries, SOLID/DRY/KISS, and provider-agnostic ports/adapters. | Adding prompt workflows, model/provider clients, tool orchestration, AI review automation, agent skills, or other LLM-backed capabilities. |
| [structurizr-architecture-sync](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/structurizr-architecture-sync/SKILL.md) | Keep Structurizr C4 diagrams (`workspace.dsl`) in sync with code. | Adding components (processors, handlers, repositories, entities), changing relationships or boundaries, or implementing new patterns (CQRS, events, subscribers). **Skip when `capabilities.structurizr` is false.** |

`implementing-ddd-architecture` ships a detailed
[`REFERENCE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/implementing-ddd-architecture/REFERENCE.md);
`code-organization` ships
[`DIRECTORY-STRUCTURE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/code-organization/DIRECTORY-STRUCTURE.md).

### API & CRUD

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [api-platform-crud](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/api-platform-crud/SKILL.md) | Create complete REST API CRUD with API Platform, DDD/CQRS patterns, YAML resource config, and the command bus. | Adding API resources, implementing CRUD endpoints, creating DTOs, configuring operations, or setting up state processors. **Skip when `framework.api_platform` is false.** |
| [openapi-development](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/openapi-development/SKILL.md) | Contribute to the API Platform OpenAPI customization layer — endpoint/request/response/schema factories and transformers — keeping the spec valid and diff-stable. | Adding endpoint factories or processors, updating OpenAPI generation logic, or fixing validation errors (Spectral, OpenAPI diff, Schemathesis). **Skip when `framework.api_platform` is false.** |

### Quality & review

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [quality-standards](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/quality-standards/SKILL.md) | Overview of protected quality thresholds plus a router mapping every failing check to its command and specialized fixing skill. | Understanding quality metrics, running comprehensive quality checks, or learning which specialized skill to use. For specific issues, defer to the dedicated skill. |
| [complexity-management](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/complexity-management/SKILL.md) | Improve code quality with PHPInsights by refactoring instead of relaxing config, keeping scores at or above the `quality.phpinsights.*` floors. | PHPInsights fails, cyclomatic complexity is too high, a quality/architecture/style score drops, or refactoring for maintainability. |
| [code-review](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/code-review/SKILL.md) | Retrieve, categorize, and address PR review comments with an auditable evidence ledger — AI review loop, per-comment commits, suppression-free fixes, pushed-head verification of checks and approval. | Handling code-review feedback, addressing PR comments, or driving a reviewed PR to merge-ready state. |
| [bmad-fr-nfr-review-gate](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/bmad-fr-nfr-review-gate/SKILL.md) | A BMAD spec-driven post-implementation review gate that blocks completion until every requirement row scores 5/5 and the gate reports zero new findings. | A PR/feature/bugfix/task implemented against BMAD specs needs verification of every FR/NFR, pinned NFR category, quality dimension, test case, CI/coverage expectation, impact surface, manual evidence, GitHub review state, and CI check. Run via `make.fr_nfr_gate`. |

### Security

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [security-audit](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/security-audit/SKILL.md) | Adversarial, authorized red-team / pen-test loop for a PHP backend you own — one `security-auditor` subagent per OWASP/vuln family, attacking the running service (black-box HTTP/GraphQL) and inspecting source (SAST/taint, deps, secrets, config), verify-by-reproduction, CWE + OWASP id + severity mapping, then root-cause suppression-free fixes via `php-implementer` with a regression test per fix. | Red-teaming, security-auditing, pen-testing, vuln-hunting, or threat-modeling an authorized PHP backend, or when `/sdlc-review` triages the security lens. Defensive/authorized use only. **Skip dynamic probing with a note when `capabilities.dynamic_security_testing` is false or `make.start` is null** (static/SAST lanes still run). |

`security-audit` ships a
[`reference/`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/security-audit)
directory: `owasp-catalog.md` (the OWASP/CWE corpus the triage draws
from), `attack-playbooks.md` (per-family probe + reproduce steps), and
`remediation-patterns.md` (secure-by-default, suppression-free fixes). See
[Security Audit](Security-Audit.md) for the full loop.

### Testing

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [testing-workflow](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/testing-workflow/SKILL.md) | Run and manage functional tests — unit, integration, E2E, mutation — via PHPUnit, Behat-style E2E, and Infection (`make.tests`, `make.e2e`, `make.infection`). | Running tests, debugging test failures, ensuring coverage, or fixing mutation-testing issues. For load/performance tests use load-testing instead. |
| [load-testing](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/load-testing/SKILL.md) | Create and manage K6 load tests for the REST and GraphQL APIs — data generation, IRI handling, config patterns, and performance troubleshooting. | Creating load tests, writing K6 scripts, testing API performance, debugging load-test failures, or setting up performance monitoring. **Skip with a note when `capabilities.load_testing` is false** (or `make.load_tests` is null). |

`load-testing` ships a
[`reference/`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/load-testing)
directory with troubleshooting docs.

### Performance & cache

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [query-performance-analysis](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/query-performance-analysis/SKILL.md) | Detect N+1 queries, analyze slow queries with the engine-native plan tool (MySQL/MariaDB EXPLAIN or MongoDB `explain()`), find missing indexes, and create safe online index migrations — branching on `persistence.engine`. | Optimizing query performance, preventing performance regressions, or debugging slow endpoints. Complements database-migrations (index creation syntax). |
| [cache-management](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/cache-management/SKILL.md) | Production-grade caching — cache keys/TTLs/consistency classes per query, stale-while-revalidate, event-driven invalidation, HTTP cache headers, and tests for stale reads and warmup. | Adding caching to queries or repositories, implementing invalidation, configuring HTTP caching, or ensuring cache consistency and performance. |

`cache-management` is the only skill that ships an
[`examples/`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/cache-management)
directory with complete working cache patterns.

### Persistence

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [database-migrations](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/database-migrations/SKILL.md) | Create, manage, and apply schema changes with Doctrine — versioned migrations when `persistence.mapper` is `doctrine-orm`, mapping-driven schema/index sync when it is `doctrine-odm`. | Modifying entities or documents, adding fields, managing schema changes, creating repositories, or troubleshooting schema/mapping issues. |

### Observability

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [observability-instrumentation](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/observability-instrumentation/SKILL.md) | Add type-safe business metrics for domain events — emitted as AWS EMF when `capabilities.observability_emf` is true, or through a generic metrics emitter otherwise. | Implementing new endpoints, adding command handlers or domain events, or instrumenting business events for dashboards and KPIs. **Not skip-gated:** the flag selects the backend, not whether the skill runs. |

### Documentation

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [documentation-creation](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/documentation-creation/SKILL.md) | Create a comprehensive docs suite from scratch by analyzing the codebase and verifying every claim against it. | Setting up INITIAL documentation, or building a complete `docs/` suite where none exists. NOT for updating existing docs. |
| [documentation-sync](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/documentation-sync/SKILL.md) | Keep project documentation in sync with code changes. | Implementing features, modifying APIs, changing architecture, adding configuration, updating security, or any change affecting user- or developer-facing docs. Not for building an initial suite from scratch. |

### CI & loop

| Skill | Purpose | When it triggers |
| --- | --- | --- |
| [ci-workflow](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/ci-workflow/SKILL.md) | Run the full local CI suite through the profile's make target map and drive every check to green before committing. | The user asks to run CI, run quality checks, or validate code quality, or before finishing any task that involves code changes. |
| [bmad-autonomous-planning](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/bmad-autonomous-planning/SKILL.md) | Create the full BMAD planning artifact chain (research, brief, PRD, architecture, epics/stories, readiness) autonomously from a short task description or GitHub issue, one focused subagent per phase, no human interaction. | `/sdlc-plan` runs stage 2 of the SDLC loop, or the user wants BMAD-style planning from a short prompt without walking interactive menus. |

## How to discover which skill fires

Two complementary mechanisms select skills.

**Automatic (Claude Code).** Claude Code reads each skill's frontmatter
`description` and invokes the matching skill via its `Skill` tool when the
task matches. You do not call skills by name.

**Manual (the decision guide).** When you (or a non-Claude agent) need to
choose deliberately, walk
[`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md)
in this order:

1. **Quick Decision Tree** — branch on intent:
   - *Fix something broken* → deptrac-fixer (violations),
     complexity-management (PHPInsights), testing-workflow (test
     failures), query-performance-analysis (N+1 / slow queries),
     openapi-development (OpenAPI errors), ci-workflow (CI failing).
   - *Create something new* → bmad-autonomous-planning (specs),
     clean-architecture-llm (LLM module), implementing-ddd-architecture
     (entity/VO/aggregate), api-platform-crud (endpoint),
     openapi-development (endpoint docs), load-testing (load test),
     database-migrations (schema), cache-management (caching),
     testing-workflow (test cases), observability-instrumentation
     (metrics), code-organization (placement/boundaries).
   - *Refactor* → clean-architecture-llm, code-organization,
     complexity-management, deptrac-fixer, testing-workflow.
   - *Review/validate* → ci-workflow (pre-commit), code-review (PR
     feedback), security-audit (vuln-hunting), bmad-fr-nfr-review-gate
     (BMAD specs), clean-architecture-llm (LLM review), quality-standards
     (thresholds), query-performance-analysis (query perf).
   - *Update docs* → documentation-creation (new), documentation-sync
     (any change).
   - *Architecture diagrams* → structurizr-architecture-sync.
2. **Scenario-based guide** — confirm the choice against the closest "I
   need to X → use Y, NOT Z" entry.
3. **Common-confusions table** — disambiguate lookalike pairs before
   committing to a skill.
4. **Multi-skill recipes** — for composite tasks, follow the ordered
   recipe (for example, the full new-feature recipe runs
   implementing-ddd-architecture → clean-architecture-llm (if LLM) →
   api-platform-crud → database-migrations → observability-instrumentation
   → testing-workflow → structurizr-architecture-sync (if capable) →
   documentation-sync → ci-workflow).

Whatever the entry point, the **New Feature Verification Gate** still runs
after implementation: record an EXECUTE or NOT-APPLICABLE verdict for
every skill, load bodies only for EXECUTE verdicts, and never skip
silently. See [Review and Quality Gates](Review-and-Quality-Gates.md) for
how `/sdlc-review` drives this gate, and
[Degrade and Resilience](Degrade-and-Resilience.md) for the
`null`-capability degrade paths the gated skills honor.

## See also

- [Commands](Commands.md) — the 8 slash commands that invoke these skills
- [Agents](Agents.md) — the 7 subagents skills dispatch (notably
  `security-auditor` and `php-implementer`)
- [Review and Quality Gates](Review-and-Quality-Gates.md) — how
  `/sdlc-review` runs the applicability-triage gate
- [Project Profile](Project-Profile.md) — the `make.*`, `quality.*`,
  `persistence.*`, and `capabilities.*` keys skills consume
- [Security Audit](Security-Audit.md) — the `security-audit` skill's
  red-team loop in depth
