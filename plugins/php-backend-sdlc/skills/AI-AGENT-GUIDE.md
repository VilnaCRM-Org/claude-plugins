# AI Agent Guide to the Skills System

This guide is for **non-Claude AI agents**: OpenAI/Codex-style agents, GitHub Copilot, Cursor, and other AI coding assistants.

## Overview

This plugin ships a modular **Skills system** originally designed for Claude Code but structured to be **AI-agnostic**. All skills are pure markdown files that any AI agent can read and execute. Every skill is generalized to the host repository through a project profile at `.claude/php-sdlc.yml` (see the plugin's profile schema documentation, `docs/profile-schema.md` at the plugin root).

## Profile keys consumed

- `make.ci`, `make.tests`, `make.e2e`, `make.psalm`, `make.deptrac`, `make.phpinsights`, `make.infection`, `make.load_tests`, `make.fr_nfr_gate`
- `quality.phpinsights.quality`, `quality.phpinsights.architecture`, `quality.phpinsights.style`, `quality.phpinsights.complexity`
- `quality.deptrac_violations`, `quality.psalm_errors`, `quality.infection_msi`
- `persistence.mapper`, `persistence.engine`
- `capabilities.structurizr`, `capabilities.observability_emf`, `capabilities.load_testing`

## How This Works

### For Claude Code

Claude Code automatically discovers and invokes skills using its `Skill` tool when tasks match skill descriptions.

### For Other Agents

You need to manually discover and read skill files, then follow their step-by-step instructions. All skill directories are siblings of this guide; paths below are relative to this directory.

### Command convention (all agents)

Skills never name repository-specific Make targets directly. They reference the profile's logical target map: "the target mapped by `make.ci`" means look up `make.ci` in `.claude/php-sdlc.yml` and run that Make target. A `null` mapping means the capability is absent — skip the dependent step with an explicit note. Generic tooling (`composer`, `gh`) may be invoked directly.

## Quick Start

### Step 0: New Feature Verification Gate (Mandatory)

If you implement a **NEW feature**, you MUST evaluate **every** skill in this directory **after implementation**. Triage first (ADR-5/NFR-5): decide each skill's verdict from its frontmatter `description` plus `SKILL-DECISION-GUIDE.md` alone, and record **EXECUTE** (with a concrete trigger) or **"Not applicable"** (with a concrete reason) for each. Open a skill's `SKILL.md` body only after recording an EXECUTE verdict — NOT-APPLICABLE verdicts are decided without loading the body, so full bodies and reference files load only for EXECUTE skills (the NFR-5 token bound). Capability-gated skills whose `capabilities.*` flag is `false` are recorded NOT-APPLICABLE without loading. Exception: `observability-instrumentation` is not skip-gated — `capabilities.observability_emf: false` selects its generic metrics-backend branch, so evaluate the skill either way. The gate contract is: **every skill verdict recorded, no silent skips**. Provide evidence (commands run and outcomes) for EXECUTE skills. Run commands only through the profile's `make.*` target map. Do not claim the feature is complete until this gate is finished.

### Step 1: Understand Your Task

When the user requests a task, first determine which skill is most relevant.

### Step 2: Read the Decision Guide

Read [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md) (sibling of this file) to choose the appropriate skill:

```text
Quick Decision Tree:
│
├─ Fix something broken
│   ├─ Deptrac violation → deptrac-fixer
│   ├─ High complexity / PHPInsights fails → complexity-management
│   ├─ Test failures → testing-workflow
│   ├─ N+1 queries or slow queries → query-performance-analysis
│   ├─ OpenAPI validation errors → openapi-development
│   └─ CI checks failing → ci-workflow
│
├─ Create something new
│   ├─ Full planning specs from a short prompt → bmad-autonomous-planning
│   ├─ New LLM-powered module or prompt workflow → clean-architecture-llm
│   ├─ New entity/value object → implementing-ddd-architecture
│   ├─ New API endpoint → api-platform-crud
│   ├─ New load test → load-testing
│   ├─ New persistence mapping / schema change → database-migrations
│   ├─ Add caching / invalidation → cache-management
│   ├─ Add business metrics → observability-instrumentation
│   └─ Fix file placement / boundaries → code-organization
│
├─ Refactor existing code
│   ├─ Move class / rename / restructure → code-organization
│   ├─ Hardcoded config to .env → code-organization
│   ├─ Reduce complexity → complexity-management
│   ├─ Fix architecture boundaries → deptrac-fixer
│   └─ Improve testability → testing-workflow
│
├─ Review/validate work
│   ├─ Before committing → ci-workflow
│   ├─ PR feedback → code-review
│   ├─ Implemented BMAD specs → bmad-fr-nfr-review-gate
│   ├─ Query performance → query-performance-analysis
│   └─ Quality thresholds → quality-standards
│
├─ Update documentation
│   ├─ New project needs docs → documentation-creation
│   └─ Any code change → documentation-sync
│
└─ Architecture diagrams
    └─ Update workspace.dsl → structurizr-architecture-sync
```

### Step 3: Read the Skill File

Each skill has a main `SKILL.md` file at `{skill-name}/SKILL.md` next to this guide.

**Example**: For CI workflow issues, read [ci-workflow/SKILL.md](ci-workflow/SKILL.md).

### Step 4: Follow Execution Steps

Each skill provides structured execution steps. Follow them sequentially. Typical shape:

1. Run the target mapped by `make.ci`.
2. Exit `0` → task complete; non-zero → identify the failing check.
3. Route the failure to the matching specialized skill and fix the root cause.

```bash # profile-example
# With the canonical reference profile (make.ci: ci) this is simply:
make ci
# ✅ CI checks successfully passed!
```

### Step 5: Check Supporting Files

Complex skills have a multi-file structure:

```text
{skill-name}/
├── SKILL.md              # Core workflow (start here)
├── reference/            # Detailed reference docs (when present)
└── examples/             # Complete working examples (when present)
```

**When to read supporting files** (only a few skills ship them):

- Encountering load-test errors → `load-testing/reference/` troubleshooting docs
- Need detailed patterns → `implementing-ddd-architecture/REFERENCE.md`, `code-organization/DIRECTORY-STRUCTURE.md`
- Want complete caching examples → `cache-management/examples/`

## Available Skills (22 Total)

### Autonomous Planning Skills

| Skill                        | File                                | When to Use                                                                                                                                                    |
| ---------------------------- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Autonomous BMAD Planning** | `bmad-autonomous-planning/SKILL.md` | Create research, brief, PRD, architecture, and epics/stories from a short task description, one focused subagent per planning phase, without human interaction |

### Workflow Skills

| Skill                       | File                               | When to Use                                                                                                                                                       |
| --------------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CI Workflow**             | `ci-workflow/SKILL.md`             | Run all quality checks before committing (target mapped by `make.ci`)                                                                                             |
| **Code Review**             | `code-review/SKILL.md`             | Address PR review comments systematically                                                                                                                         |
| **BMAD FR/NFR Review Gate** | `bmad-fr-nfr-review-gate/SKILL.md` | Verify implemented BMAD-scoped work against every FR/NFR, pinned NFR category, quality dimension, impact surface, manual evidence item, GitHub gate, and CI check |
| **Testing Workflow**        | `testing-workflow/SKILL.md`        | Run/debug unit, integration, E2E, mutation tests (`make.tests`, `make.e2e`, `make.infection`)                                                                     |

### Architecture & Quality Skills

| Skill                        | File                                     | When to Use                                                                 |
| ---------------------------- | ---------------------------------------- | --------------------------------------------------------------------------- |
| **Implementing DDD**         | `implementing-ddd-architecture/SKILL.md` | Create entities, value objects, aggregates, CQRS                            |
| **Deptrac Fixer**            | `deptrac-fixer/SKILL.md`                 | Fix architectural boundary violations (never edit `deptrac.yaml`)           |
| **Quality Standards**        | `quality-standards/SKILL.md`             | Overview of protected `quality.*` thresholds                                |
| **Complexity Management**    | `complexity-management/SKILL.md`         | Reduce cyclomatic complexity in code                                        |
| **OpenAPI Development**      | `openapi-development/SKILL.md`           | OpenAPI factories, processors & validation                                  |
| **Code Organization**        | `code-organization/SKILL.md`             | Placement, naming, boundaries, type safety, config extraction, refactoring  |
| **Clean Architecture LLM**   | `clean-architecture-llm/SKILL.md`        | LLM ports/adapters, prompt boundaries, deterministic tests, privacy review  |
| **Query Performance**        | `query-performance-analysis/SKILL.md`    | N+1 detection, EXPLAIN analysis, indexing                                   |
| **Structurizr Architecture** | `structurizr-architecture-sync/SKILL.md` | Update C4 diagrams in `workspace.dsl` (gated by `capabilities.structurizr`) |

### Database & Documentation Skills

| Skill                      | File                              | When to Use                                                                                    |
| -------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------- |
| **Database Migrations**    | `database-migrations/SKILL.md`    | Create/modify entities with the configured mapper (`persistence.mapper`, `persistence.engine`) |
| **Documentation Creation** | `documentation-creation/SKILL.md` | Create full docs suite for a new project                                                       |
| **Documentation Sync**     | `documentation-sync/SKILL.md`     | Keep docs synchronized with code changes                                                       |

### API & Performance Skills

| Skill                 | File                                     | When to Use                                                                                          |
| --------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| **API Platform CRUD** | `api-platform-crud/SKILL.md`             | Create complete REST API CRUD with DDD/CQRS                                                          |
| **Load Testing**      | `load-testing/SKILL.md`                  | Create K6 performance tests (gated by `capabilities.load_testing`, `make.load_tests`)                |
| **Cache Management**  | `cache-management/SKILL.md`              | Cache keys, TTLs, invalidation, decorators                                                           |
| **Observability**     | `observability-instrumentation/SKILL.md` | Business metrics — EMF when `capabilities.observability_emf` is `true`, generic backend when `false` |

### Security Skills

| Skill              | File                      | When to Use                                                                                                                                                                                                                                                             |
| ------------------ | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Security Audit** | `security-audit/SKILL.md` | Adversarial, authorized red-team / penetration-test loop against a PHP backend you own — one auditor per OWASP/vuln family, verify-by-reproduction, root-cause suppression-free fixes (gated by `capabilities.dynamic_security_testing`, `make.security`, `make.start`) |

The `security-audit` skill ships supporting `reference/` files. Read its
`SKILL.md` first for the triage → fan-out → find → verify → fix → regress →
re-verify loop, then read its reference catalogs as you need them:

- `security-audit/reference/owasp-catalog.md` — the OWASP/CWE corpus (edition-labelled) the triage table draws from
- `security-audit/reference/attack-playbooks.md` — per-family probe + reproduce-against-running-service step
- `security-audit/reference/remediation-patterns.md` — secure-by-default, suppression-free remediation per vuln family

## Practical Examples

### Example 1: User asks to "fix Deptrac violations"

**Your workflow:**

1. **Identify skill**: Read `SKILL-DECISION-GUIDE.md` → Points to `deptrac-fixer`
2. **Read skill**: Open `deptrac-fixer/SKILL.md`
3. **Execute**: Follow the diagnostic and fix patterns in the file
4. **Validate**: Run the target mapped by `make.deptrac` to verify fixes (`quality.deptrac_violations` must stay `0`)

### Example 2: User asks to "add a new entity with CRUD endpoints"

**Your workflow:**

1. **Identify skills**: Use `implementing-ddd-architecture` for the entity, `database-migrations` for persistence, `api-platform-crud` for REST endpoints, `testing-workflow` for tests, and `ci-workflow` for validation.
2. **Triage, then read EXECUTE skills only**: record an EXECUTE verdict for each from its frontmatter description plus the decision guide, then open and execute the body of each EXECUTE skill in order (do not load bodies you have ruled NOT-APPLICABLE).
3. **Use examples**: Follow the inlined "Quick Start: Complete CRUD in 10 Steps" in `api-platform-crud/SKILL.md`; `cache-management/examples/` has complete working code if caching is involved.
4. **After implementation**: Run the **New Feature Verification Gate** — every skill verdict recorded, no silent skips.

### Example 3: User asks to "plan a feature autonomously"

**Your workflow:**

1. **Identify skill**: Read `SKILL-DECISION-GUIDE.md` → Points to `bmad-autonomous-planning`
2. **Read skill**: Open `bmad-autonomous-planning/SKILL.md`
3. **Execute in the current session**: Run each planning phase (research, brief, PRD, architecture, epics/stories, readiness) as a separate focused subagent
4. **Inspect outputs**: Review the generated artifacts and unresolved questions

### Example 4: User asks to "run tests"

**Your workflow:**

1. **Identify skill**: `testing-workflow`
2. **Read**: `testing-workflow/SKILL.md`
3. **Execute**: Run the targets mapped by `make.tests` and `make.e2e`
4. **Debug failures**: Follow troubleshooting steps in the skill file

### Example 5: User asks to "refactor code" or "extract hardcoded configs"

**Your workflow:**

1. **Identify skill**: `code-organization`
2. **Read**: `code-organization/SKILL.md`
3. **For structural refactoring**: Follow directory type classification and refactoring checklist
4. **For config extraction**: Follow the hardcoded-configuration extraction section
5. **Validate**: Run the targets mapped by `make.psalm`, `make.deptrac`, and `make.tests`
6. **If CI fails after refactoring**: Consult the CI-failure routing in `code-organization` and `ci-workflow`

### Example 6: User asks to "security-audit" or "red-team the API"

**Your workflow:**

1. **Identify skill**: Read `SKILL-DECISION-GUIDE.md` → Points to `security-audit`
2. **Read skill**: Open `security-audit/SKILL.md` and follow the triage → fan-out → find → verify → fix → regress → re-verify loop
3. **Read supporting files**: Pull in `security-audit/reference/owasp-catalog.md` (corpus + triage), `security-audit/reference/attack-playbooks.md` (per-family probes), and `security-audit/reference/remediation-patterns.md` (secure-by-default fixes) as each step needs them
4. **Stay defensive/authorized**: Probe ONLY the profile-resolved local service; never an out-of-profile host
5. **Route fixes, don't edit**: The auditor reports verified findings; root-cause fixes are routed through `php-implementer` with a failing-then-passing regression test per fix
6. **Validate**: Re-verify the affected family clean, then run the target mapped by `make.ci`

## Cross-Agent Reference

Most skills are self-contained markdown you execute directly. The `security-audit`
skill, however, prescribes fanning out a dedicated red-team subagent — one
instance per OWASP/vuln family — rather than running every probe inline:

| Agent                | File                            | Role                                                                                                                                                                                                                                             |
| -------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Security Auditor** | `../agents/security-auditor.md` | Authorized, defensive red-team unit for ONE assigned OWASP/vuln family — black-box HTTP/GraphQL probing + source SAST, verify-by-reproduction, reports findings (CWE + OWASP id + severity), never edits code (fixes route to `php-implementer`) |

Non-Claude agents that cannot dispatch a subagent should read
`../agents/security-auditor.md` and apply its per-family probe-and-report
contract sequentially, one family at a time, preserving the same
authorized/defensive boundary and verify-by-reproduction rule.

## Key Differences from Claude Code

| Aspect                | Claude Code              | Other Agents                          |
| --------------------- | ------------------------ | ------------------------------------- |
| **Discovery**         | Automatic                | Manual (read SKILL-DECISION-GUIDE.md) |
| **Invocation**        | Automatic via Skill tool | Manual (read SKILL.md file)           |
| **Execution**         | Guided by tool           | Self-guided (follow steps)            |
| **Multi-file skills** | Automatically loaded     | Read supporting files as needed       |

## Quality Standards & Protected Thresholds

**CRITICAL**: thresholds come exclusively from the profile's `quality.*` keys and are **raise-only**: a profile may tighten the bar above the canonical defaults, never relax it. Violation-count ceilings are fixed at `0`.

| Profile key                        | Metric                   | Canonical default | Skill for Issues        |
| ---------------------------------- | ------------------------ | ----------------- | ----------------------- |
| `quality.phpinsights.complexity`   | PHPInsights Complexity   | `94` (floor)      | `complexity-management` |
| `quality.phpinsights.quality`      | PHPInsights Quality      | `100` (floor)     | `complexity-management` |
| `quality.phpinsights.architecture` | PHPInsights Architecture | `100` (floor)     | `deptrac-fixer`         |
| `quality.phpinsights.style`        | PHPInsights Style        | `100` (floor)     | `code-organization`     |
| `quality.deptrac_violations`       | Deptrac violations       | `0` (fixed)       | `deptrac-fixer`         |
| `quality.psalm_errors`             | Psalm errors             | `0` (fixed)       | Fix reported issues     |
| `quality.infection_msi`            | Infection MSI            | `100` (floor)     | `testing-workflow`      |

**Always improve code quality to meet standards. Never lower thresholds.**
**Never hide problems with suppression/ignore annotations (e.g. `@SuppressWarnings`, `@psalm-suppress`, `@infection-ignore-all`, `@codeCoverageIgnore`, `@phpstan-ignore`, `phpcs:ignore`, `@phpinsights-ignore*`).**

## Locked Configuration Exception Policy (AI Agents)

Quality tool configuration files (e.g. PHPInsights config, Psalm config, `deptrac.yaml`, Infection config, PHPMD rulesets, PHP CS Fixer config) are treated as **locked**. Fix the code to satisfy them — never the other way around. `deptrac.yaml` in particular is never edited by any skill.

If CI reports that a locked configuration file was modified:

1. If the task did **not** explicitly request config updates, treat it as accidental drift:
   - Revert the locked-file changes.
   - Re-run the target mapped by `make.ci`.
2. If config updates were explicitly requested:
   - Keep changes isolated to a dedicated config-governance PR.
   - Report CI failure as expected evidence; do not hide or bypass it.
   - Escalate for human approval. Autonomous agents must not self-approve or self-merge failed CI.
   - Add explicit rationale (why the change is required, impact, rollback plan).

Never normalize "merge with red CI" as a general workflow. It is a human exception path only.

## Common Workflows

### Before Every Commit

1. Read: `ci-workflow/SKILL.md`
2. Execute: the target mapped by `make.ci`
3. Success criteria: exit code `0` (many repositories also print a success banner)
4. If it fails: follow the fix routing in the skill

### Creating New Features

1. Read: `implementing-ddd-architecture/SKILL.md` - Design domain model
2. Read: `clean-architecture-llm/SKILL.md` - Design provider/prompt boundaries when the feature uses LLMs
3. Read: `database-migrations/SKILL.md` - Configure persistence
4. Read: `api-platform-crud/SKILL.md` - Add API endpoints
5. Read: `testing-workflow/SKILL.md` - Write tests
6. Read: `structurizr-architecture-sync/SKILL.md` - Update architecture diagrams (if `capabilities.structurizr`)
7. Read: `documentation-sync/SKILL.md` - Update docs
8. Read: `ci-workflow/SKILL.md` - Validate everything
9. Finish with the New Feature Verification Gate: every skill verdict recorded, no silent skips

### Fixing Quality Issues

1. Identify issue type (Deptrac? Complexity? Tests? Naming? Hardcoded config?)
2. Read `SKILL-DECISION-GUIDE.md` to find the right skill
3. Read the specific skill file
4. Follow fix instructions
5. If refactoring is needed, also consult `code-organization/SKILL.md`
6. Run the target mapped by `make.ci` to verify

## File Structure Reference

```text
skills/
├── AI-AGENT-GUIDE.md           # This file - start here
├── SKILL-DECISION-GUIDE.md     # Decision tree for choosing skills
│
├── api-platform-crud/
├── bmad-autonomous-planning/
├── bmad-fr-nfr-review-gate/
├── cache-management/
├── ci-workflow/
├── clean-architecture-llm/
├── code-organization/
├── code-review/
├── complexity-management/
├── database-migrations/
├── deptrac-fixer/
├── documentation-creation/
├── documentation-sync/
├── implementing-ddd-architecture/
├── load-testing/
├── observability-instrumentation/
├── openapi-development/
├── quality-standards/
├── query-performance-analysis/
├── security-audit/
│   ├── SKILL.md
│   └── reference/             # OWASP catalog, attack playbooks, remediation patterns
├── structurizr-architecture-sync/
└── testing-workflow/
    └── SKILL.md                # Every skill directory has a SKILL.md;
                                # some add reference/ and examples/
```

## Tips for Effective Use

### DO

- Always start with `SKILL-DECISION-GUIDE.md` when unsure
- Read the entire SKILL.md file before executing
- Follow execution steps sequentially
- Check supporting files (`reference/`, `examples/`) when stuck
- Run the target mapped by `make.ci` before finishing any task
- Respect protected `quality.*` thresholds (raise-only)
- Record a verdict for every skill in the verification gate — every skill verdict recorded, no silent skips

### DON'T

- Skip reading the decision guide
- Jump directly to execution without reading the full skill
- Lower quality thresholds to make checks pass
- Add suppression/ignore annotations to silence quality tools
- Edit `deptrac.yaml` or other locked quality configuration
- Invent Make targets — always resolve them through the profile's `make.*` map
- Ignore supporting documentation when errors occur

## Getting Help

If you encounter issues:

1. **Read troubleshooting**: only `load-testing/` ships a `reference/` directory (including troubleshooting docs); `implementing-ddd-architecture/REFERENCE.md` and `code-organization/DIRECTORY-STRUCTURE.md` carry the detailed patterns for those skills
2. **Check examples**: only `cache-management/` ships an `examples/` directory (complete working cache patterns); other skills inline their examples in `SKILL.md`
3. **Review the host repository's agent guidelines** (its `AGENTS.md`/`CLAUDE.md`) for repo-specific conventions
4. **Check the profile**: `.claude/php-sdlc.yml` resolves every logical target and capability flag

## Conclusion

The skills system provides **modular, reusable workflows** that work across different AI agents and across different PHP backend repositories via the project profile. While Claude Code invokes skills automatically, other agents achieve the same results by reading and following the skill files manually.

**Start here:**

1. Read this guide (done)
2. Read [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md)
3. Pick a skill based on your task
4. Follow the skill's execution steps
