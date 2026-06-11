# Skill Decision Guide

**Choose the right skill for your task based on what you're trying to accomplish.**
**Non-negotiable rule**: Fix root causes. Do not use suppression/ignore annotations to silence PHPMD, PHPInsights, Infection, Psalm, PHPStan, or PHPCS issues. Never lower quality thresholds and never edit `deptrac.yaml` — always fix the code instead.

All make/CLI invocations below go through the profile's logical target map (`make.*` keys in `.claude/php-sdlc.yml`). "The target mapped by `make.ci`" means: look up the `make.ci` value in the profile and run that Make target. A `null` mapping means the capability is absent — skip with a note, never invent a target.

## Profile keys consumed

- `make.ci`, `make.fr_nfr_gate`, `make.load_tests`
- `quality.phpinsights.quality`, `quality.phpinsights.architecture`, `quality.phpinsights.style`, `quality.phpinsights.complexity`
- `quality.deptrac_violations`, `quality.psalm_errors`, `quality.infection_msi`
- `persistence.mapper`, `persistence.engine`
- `capabilities.structurizr`, `capabilities.observability_emf`, `capabilities.load_testing`

## Mandatory New Feature Verification Gate (ALL Skills)

If you created or modified a **NEW feature**, you MUST evaluate **every** skill in this directory **after implementation**. The decision tree below is for choosing the primary skill during the work. It does **not** replace this gate.

**Execution rules (triage-first — ADR-5/NFR-5):**

1. Decide each skill's verdict from its frontmatter `description` (in the
   listed `SKILL.md`) plus this guide alone — never load a skill body to
   decide a verdict. Record one verdict per skill: **EXECUTE** (with a
   concrete one-line trigger) or **NOT-APPLICABLE** (with a concrete
   reason). The gate contract is: **every skill verdict recorded, no
   silent skips**.
2. Open a `SKILL.md` body only **after** recording an EXECUTE verdict for
   it; then follow its steps exactly. NOT-APPLICABLE verdicts are recorded
   without loading the body — this keeps the token cost bounded (NFR-5:
   full bodies + reference files load only for EXECUTE verdicts).
3. Run required commands only through the profile's `make.*` target map (generic tooling like `composer` and `gh` is allowed directly).
4. Capability-gated skills (`structurizr-architecture-sync` via `capabilities.structurizr`, `load-testing` via `capabilities.load_testing` + `make.load_tests`) are skipped **with a recorded note** when the capability is `false` or the target maps to `null`. `observability-instrumentation` is **not** skip-gated: `capabilities.observability_emf` only selects its emission backend — when `false`, evaluate the skill through its generic metrics-backend branch instead of skipping.
5. Provide evidence in your response: commands run and outcomes. If you cannot run a command, stop and explain why.
6. Do not claim the feature is complete until this gate is finished.

**Skills to evaluate for every new feature:**

- `api-platform-crud`
- `cache-management`
- `ci-workflow`
- `clean-architecture-llm`
- `code-organization`
- `code-review`
- `complexity-management`
- `database-migrations`
- `deptrac-fixer`
- `documentation-creation`
- `documentation-sync`
- `implementing-ddd-architecture`
- `load-testing`
- `observability-instrumentation`
- `openapi-development`
- `quality-standards`
- `query-performance-analysis`
- `structurizr-architecture-sync`
- `testing-workflow`

**Conditional BMAD skills:**

- `bmad-fr-nfr-review-gate` when BMAD specs exist for the implemented work. Run it
  through the target mapped by `make.fr_nfr_gate` (the plugin substitutes its own
  gate script when the mapping is `null`); if no BMAD specs exist, record
  **"Not applicable"** with the concrete reason.
- `bmad-autonomous-planning` is a planning-time skill only; during the gate record
  **"Not applicable — planning skill"** unless the task itself was to produce specs.

## Quick Decision Tree

```text
What are you trying to do?
│
├─ Fix something broken
│   ├─ Deptrac violation → deptrac-fixer
│   ├─ High complexity / PHPInsights fails → complexity-management
│   ├─ Test failures → testing-workflow
│   ├─ N+1 queries / slow queries → query-performance-analysis
│   ├─ OpenAPI validation errors → openapi-development
│   └─ CI checks failing → ci-workflow
│
├─ Create something new
│   ├─ Full planning specs from a short prompt → bmad-autonomous-planning
│   ├─ New LLM-powered module / prompt workflow → clean-architecture-llm
│   ├─ New entity / value object / aggregate → implementing-ddd-architecture
│   ├─ New API endpoint (CRUD) → api-platform-crud
│   ├─ New OpenAPI endpoint documentation → openapi-development
│   ├─ New load test → load-testing
│   ├─ New persistence mapping / schema change → database-migrations
│   ├─ Add caching / invalidation → cache-management
│   ├─ New test cases → testing-workflow
│   ├─ Add business metrics → observability-instrumentation
│   └─ Fix file placement / boundaries → code-organization
│
├─ Refactor existing code
│   ├─ Extract LLM provider/prompt logic → clean-architecture-llm
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
│   ├─ LLM architecture review → clean-architecture-llm
│   ├─ Quality thresholds → quality-standards
│   └─ Query performance → query-performance-analysis
│
├─ Update documentation
│   ├─ New project needs docs → documentation-creation
│   └─ Any code change → documentation-sync
│
└─ Architecture diagrams
    └─ Update workspace.dsl (C4 model) → structurizr-architecture-sync
```

All 21 skills appear above: `api-platform-crud`, `bmad-autonomous-planning`,
`bmad-fr-nfr-review-gate`, `cache-management`, `ci-workflow`,
`clean-architecture-llm`, `code-organization`, `code-review`,
`complexity-management`, `database-migrations`, `deptrac-fixer`,
`documentation-creation`, `documentation-sync`, `implementing-ddd-architecture`,
`load-testing`, `observability-instrumentation`, `openapi-development`,
`quality-standards`, `query-performance-analysis`,
`structurizr-architecture-sync`, `testing-workflow`.

## Scenario-Based Guide

### "Deptrac is failing with violations"

**Use**: [deptrac-fixer](deptrac-fixer/SKILL.md)

This skill parses violation messages and provides exact fix patterns. It never edits `deptrac.yaml`; the ceiling `quality.deptrac_violations` is fixed at `0`.

**NOT**: implementing-ddd-architecture (that's for designing new patterns)
**NOT**: quality-standards (that's just an overview)

---

### "I need to create a new entity with value objects"

**Use**: [implementing-ddd-architecture](implementing-ddd-architecture/SKILL.md)

This skill guides proper DDD structure and file placement.

**NOT**: deptrac-fixer (that's for fixing violations)
**NOT**: database-migrations (that's for the persistence side)

---

### "I need to add an LLM-powered module or prompt workflow"

**Use**: [clean-architecture-llm](clean-architecture-llm/SKILL.md)

This skill guides Clean Architecture boundaries for provider-agnostic ports, prompt factories/templates, provider adapters, deterministic tests, and privacy review.

**ALSO**: Check [implementing-ddd-architecture](implementing-ddd-architecture/SKILL.md) when the LLM feature touches domain/application/infrastructure code.
**ALSO**: Check [code-organization](code-organization/SKILL.md) when adding or moving classes.

---

### "PHPInsights complexity score is too low"

**Use**: [complexity-management](complexity-management/SKILL.md)

This skill provides refactoring strategies to meet the floor set by `quality.phpinsights.complexity` (canonical default `94`). Thresholds are raise-only: a profile may tighten them above the defaults, never relax them.

**NOT**: quality-standards (that's just an overview of thresholds)

---

### "I need to write K6 load tests"

**Use**: [load-testing](load-testing/SKILL.md)

This skill has REST and GraphQL load test patterns. Gated by `capabilities.load_testing` and the target mapped by `make.load_tests`.

**NOT**: testing-workflow (that's for functional tests only)

---

### "I need to add caching / cache invalidation"

**Use**: [cache-management](cache-management/SKILL.md)

This skill covers cache key design, TTLs, tag-based invalidation, decorator-based cached repositories, and event-driven invalidation.

**NOT**: complexity-management (that's for cyclomatic complexity)

---

### "Tests are failing and I need to debug"

**Use**: [testing-workflow](testing-workflow/SKILL.md)

This skill covers unit, integration, E2E, and mutation test debugging, including the `quality.infection_msi` floor (canonical default `100`, raise-only).

**NOT**: load-testing (that's for performance tests)
**NOT**: ci-workflow (that runs tests but doesn't debug)

---

### "I need to refactor code structure / move classes"

**Use**: [code-organization](code-organization/SKILL.md)

This skill enforces "Directory X contains ONLY class type X", proper DDD naming, and provides a refactoring checklist.

**ALSO**: Check [deptrac-fixer](deptrac-fixer/SKILL.md) if refactoring involves layer boundaries.
**ALSO**: Check [complexity-management](complexity-management/SKILL.md) if refactoring to reduce complexity.

---

### "I have hardcoded config values (TTLs, timeouts, limits) in source code"

**Use**: [code-organization](code-organization/SKILL.md)

This skill includes guidance on extracting hardcoded constants to `.env` parameters and framework environment bindings.

**NOT**: ci-workflow (that runs checks but doesn't guide extraction)

---

### "I need to understand what quality metrics are protected"

**Use**: [quality-standards](quality-standards/SKILL.md)

This skill documents all `quality.*` thresholds, the raise-only rule, and directs to specialized skills.

**NOT**: complexity-management (that's specifically for complexity)

---

### "Endpoint is slow or making too many queries"

**Use**: [query-performance-analysis](query-performance-analysis/SKILL.md)

This skill detects N+1 queries, analyzes slow queries with EXPLAIN, and identifies missing indexes.

**NOT**: load-testing (that's for performance under concurrent load)
**NOT**: testing-workflow (that's for functional tests)

---

### "I'm addressing PR review comments"

**Use**: [code-review](code-review/SKILL.md)

This skill systematically handles review feedback.

**NOT**: ci-workflow (that's for running checks)

---

### "I implemented BMAD specs and need to verify FR/NFR coverage"

**Use**: [bmad-fr-nfr-review-gate](bmad-fr-nfr-review-gate/SKILL.md)

This skill checks implemented work against every BMAD FR/NFR, the pinned NFR categories, manual test evidence, GitHub review status, and CI status. It requires a full pass for every applicable row before completion. Run it through the target mapped by `make.fr_nfr_gate`.

**ALSO**: Use [code-review](code-review/SKILL.md) for PR comments and [ci-workflow](ci-workflow/SKILL.md) for local CI failures.

---

### "I made code changes and need to validate before committing"

**Use**: [ci-workflow](ci-workflow/SKILL.md)

This skill runs the comprehensive local CI suite through the target mapped by `make.ci`.

**NOT**: testing-workflow (that's specifically for tests)

---

### "I need planning specs created autonomously from a short task description"

**Use**: [bmad-autonomous-planning](bmad-autonomous-planning/SKILL.md)

This skill orchestrates research, brief, PRD, architecture, and epics/stories through focused subagents — one per planning phase — without stopping for interactive planning menus.

**NOT**: an interactive PRD flow (assumes human-in-the-loop progression)
**NOT**: sprint planning (that only derives status from existing epics)

---

### "I added a new feature and need to update docs"

**Use**: [documentation-sync](documentation-sync/SKILL.md)

This skill identifies which documentation files need updating.

---

### "I need to create documentation for a new project"

**Use**: [documentation-creation](documentation-creation/SKILL.md)

This skill guides creating a complete documentation suite from scratch.

**NOT**: documentation-sync (that's for updating existing docs)

---

### "I need to add a new field to an entity"

**Use**: [database-migrations](database-migrations/SKILL.md)

This skill guides entity modification with the persistence mapper and engine configured in the profile (`persistence.mapper`, `persistence.engine`).

**ALSO**: Check [implementing-ddd-architecture](implementing-ddd-architecture/SKILL.md) for proper DDD patterns.

---

### "I'm adding OpenAPI endpoint documentation"

**Use**: [openapi-development](openapi-development/SKILL.md)

This skill covers OpenAPI factories, processors, and validation (Spectral, OpenAPI diff, Schemathesis).

---

### "I need to add business metrics to track domain events"

**Use**: [observability-instrumentation](observability-instrumentation/SKILL.md)

This skill guides adding type-safe business metrics via event subscribers. `capabilities.observability_emf` selects the emission backend: AWS EMF when `true`, the skill's generic metrics-backend branch (Prometheus/StatsD/OTel/structured logs) when `false` — the flag never makes the skill skippable.

**NOT**: load-testing (that's for performance under load)
**NOT**: testing-workflow (that's for functional tests)

---

### "I need to update architecture diagrams"

**Use**: [structurizr-architecture-sync](structurizr-architecture-sync/SKILL.md)

This skill guides updating `workspace.dsl` when adding components or changing architecture. Gated by `capabilities.structurizr`.

**ALSO**: Use after [implementing-ddd-architecture](implementing-ddd-architecture/SKILL.md) when creating new domain models.
**ALSO**: Use after [deptrac-fixer](deptrac-fixer/SKILL.md) when fixing layer violations.

---

## Skill Relationship Map

```text
                          quality-standards
                         (overview & routing)
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
           complexity-    deptrac-fixer   testing-workflow
           management           │               │
                 │              ▼               ▼
                 │    implementing-ddd-   load-testing
                 │      architecture      (performance)
                 │            │
                 │  ┌─────────┴───────────────┐
                 ▼  ▼                         ▼
          code-organization            structurizr-
          (refactoring &               architecture-sync
           config extraction)
                 │
     ┌───────────┴───────────┐
     ▼                       ▼
database-              ci-workflow
 migrations            (validation)
```

## Common Confusions

| Confusion                                      | Clarification                                                                                                                     |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| deptrac-fixer vs implementing-ddd-architecture | **Fix violations** → deptrac-fixer; **design new patterns** → implementing-ddd-architecture                                       |
| testing-workflow vs load-testing               | **Functional tests** (unit, integration, E2E) → testing-workflow; **performance tests** (K6) → load-testing                       |
| quality-standards vs complexity-management     | **Overview of all metrics** → quality-standards; **fix complexity specifically** → complexity-management                          |
| ci-workflow vs testing-workflow                | **Run all CI checks** → ci-workflow; **debug specific test issues** → testing-workflow                                            |
| query-performance-analysis vs load-testing     | **Query optimization** (N+1, indexes) → query-performance-analysis; **concurrent load** (K6) → load-testing                       |
| implementing-ddd vs structurizr-architecture   | **Create code** → implementing-ddd-architecture; **document diagrams** → structurizr-architecture-sync                            |
| clean-architecture-llm vs implementing-ddd     | **LLM provider/prompt boundaries** → clean-architecture-llm; **general domain modeling and CQRS** → implementing-ddd-architecture |
| code-organization vs deptrac-fixer             | **File placement, naming, config extraction** → code-organization; **layer boundary violations** → deptrac-fixer                  |
| code-organization vs complexity-management     | **Structural refactoring** (move/rename/extract) → code-organization; **reduce cyclomatic complexity** → complexity-management    |

## Multiple Skills for One Task

Some tasks benefit from multiple skills:

### Creating a complete new feature

1. **implementing-ddd-architecture** - Design domain model
2. **clean-architecture-llm** - Design provider/prompt boundaries when the feature uses LLMs
3. **api-platform-crud** - Create API endpoints
4. **database-migrations** - Configure persistence
5. **observability-instrumentation** - Add business metrics (EMF or the generic-backend branch per `capabilities.observability_emf`)
6. **testing-workflow** - Write tests
7. **structurizr-architecture-sync** - Update architecture diagrams (if `capabilities.structurizr`)
8. **documentation-sync** - Update docs
9. **ci-workflow** - Validate everything

### Fixing architecture issues

1. **deptrac-fixer** - Fix the violations
2. **implementing-ddd-architecture** - Understand why (if needed)
3. **structurizr-architecture-sync** - Update diagrams to match
4. **ci-workflow** - Verify fix

### Performance optimization

1. **query-performance-analysis** - Fix N+1 queries, add indexes
2. **load-testing** - Create performance tests
3. **complexity-management** - Reduce code complexity
4. **ci-workflow** - Ensure quality maintained

### Refactoring existing code

1. **code-organization** - Verify/fix directory placement, naming, extract hardcoded configs
2. **complexity-management** - Reduce complexity if needed
3. **deptrac-fixer** - Verify architecture boundaries after moves
4. **testing-workflow** - Ensure tests still pass and cover refactored code
5. **ci-workflow** - Validate everything
