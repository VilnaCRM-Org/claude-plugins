# AI Agent Guide to the Skills System

This guide is for **non-Claude AI agents**: OpenAI/Codex-style agents, GitHub Copilot, Cursor, and other AI coding assistants. Claude Code discovers and invokes these skills automatically; every other agent reaches the same result by reading the skill files and following their steps.

## Overview

This plugin ships a modular **Skills system** for the **React 18 + TypeScript + Material UI v7 + Emotion** frontend SDLC. The skills are pure markdown files that any AI agent can read and execute. Every skill is generalized to the host frontend repository through a project profile at `.claude/react-sdlc.yml` (see the plugin's profile schema documentation, `docs/profile-schema.md` at the plugin root). Nothing in a skill is hardcoded to one repository's shape: the same skill library drives a React SPA, a Next.js app, and a component library through that one profile.

## Profile keys consumed

- Logical target map: `make.ci`, `make.lint`, `make.lint_eslint`, `make.lint_deps`, `make.format`, `make.test_unit_client`, `make.test_unit_server`, `make.test_integration`, `make.test_e2e`, `make.test_visual`, `make.test_mutation`, `make.lighthouse_desktop`, `make.lighthouse_mobile`, `make.test_load`, `make.storybook_build`, `make.a11y`
- Quality floors / ceilings: `quality.coverage_statements`, `quality.mutation_msi`, `quality.eslint_errors`, `quality.lighthouse_mobile`, `quality.visual_diffs`
- Framework / architecture: `framework.ui`, `framework.bundler`, `framework.package_manager`, `framework.state`, `framework.di`, `architecture.source_root`, `architecture.modules`, `architecture.component_prefix`
- Capability flags: `capabilities.accessibility_audit`, `capabilities.dynamic_a11y_testing`, `capabilities.figma`, `capabilities.lighthouse`, `capabilities.visual_testing`, `capabilities.mutation_testing`, `capabilities.load_testing`, `capabilities.storybook`, `capabilities.observability`
- Companion install metadata: `companion.skills`, `companion.agents`, `companion.install_command`

## How This Works

### For Claude Code

Claude Code automatically discovers and invokes skills using its `Skill` tool when a task matches a skill's `description`.

### For Other Agents

You manually discover and read skill files, then follow their step-by-step instructions. All skill directories are siblings of this guide; paths below are relative to this directory.

### Command convention (all agents) — everything runs through the profile's `make` map

Skills never name a repository-specific Make target directly. They reference the profile's **logical** target map: "the target mapped by `make.ci`" means look up `make.ci` in `.claude/react-sdlc.yml` and run whatever Make target it points to. A `null` mapping means the capability is absent in this repository — **skip the dependent step with an explicit note**, never improvise a raw host command. Generic tooling (the project package manager via `framework.package_manager`, plus `gh` and `git`) may be invoked directly when a step needs it.

This is what lets one skill library work across divergent repositories:

- A **React SPA** maps `make.ci`, split `make.test_unit_client` / `make.test_unit_server`, `make.lint_eslint`, `make.lint_deps`, `make.lint_metrics`, and `make.test_mutation`.
- A **Next.js app** maps `make.ci` and an eslint-backed `make.lint_eslint`, but leaves duplication, metrics, and mutation-merge targets `null`.
- A **component library** may have **no `make.ci`** at all (so `ci-workflow` runs the individually-mapped sub-targets), a single `make.test_unit_client`, and a Storybook-first build.

Always read the logical key, run the mapped target, and degrade with a note when the value is `null`. Never assume a specific bundler (`framework.bundler`), package manager (`framework.package_manager`), or runtime — read them from the profile.

## Quick Start

### Step 0: New Feature Verification Gate (Mandatory)

If you implement a **new feature**, you MUST evaluate **every** skill in this directory **after implementation**. Triage first: decide each skill's verdict from its frontmatter `description` plus [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md) alone, and record **EXECUTE** (with a concrete trigger) or **"Not applicable"** (with a concrete reason) for each. Open a skill's `SKILL.md` body only after recording an EXECUTE verdict — NOT-APPLICABLE verdicts are decided without loading the body, so full bodies and reference files load only for EXECUTE skills (the token bound).

Capability-gated skills whose `capabilities.*` flag is `false` are recorded NOT-APPLICABLE without loading: `figma-design-check` when `capabilities.figma` is `false`, `load-testing` when `capabilities.load_testing` is `false`, and the dynamic-browser branch of the accessibility gate when `capabilities.dynamic_a11y_testing` is `false`. Exception: `observability-instrumentation` is **not** skip-gated — `capabilities.observability: false` selects its deferred structured-log sink instead of a RUM/Sentry sink, so evaluate it either way.

**The accessibility gate is never optional for UI changes** — see "The mandatory accessibility gate" below.

The gate contract is: **every skill verdict recorded, no silent skips**. Provide evidence (commands run and outcomes, via the profile's `make.*` map) for EXECUTE skills. Do not claim the feature is complete until this gate is finished.

### Step 1: Understand Your Task

Translate the request into one intent: fix something broken, create something new, refactor existing code, review/validate work, or update documentation.

### Step 2: Read the Decision Guide

Read [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md) (sibling of this file) and walk the tree:

```text
What are you trying to do?
│
├─ Fix something broken
│   ├─ Format / ESLint / TypeScript / markdown / duplication / metrics → frontend-quality-workflow
│   ├─ rust-code-analysis metric, or file/function over budget       → complexity-management
│   ├─ Failing Jest / Testing Library / Playwright / visual test     → frontend-testing-workflow
│   ├─ Broader unit / integration / E2E / mutation triage            → testing-workflow
│   ├─ dependency-cruiser layer / import boundary violation          → architecture
│   ├─ Lighthouse / web-vitals regression                            → frontend-performance-accessibility
│   ├─ Accessibility (a11y) violation                                → accessibility-audit
│   └─ Pre-commit / pre-push CI readiness                            → ci-workflow
│
├─ Create something new
│   ├─ Full planning specs from a short prompt                       → bmad-autonomous-planning
│   ├─ React component, hook, form, or feature UI                    → frontend-component-development
│   ├─ Module / file placement & naming                             → code-organization
│   ├─ New feature, repository, or layer boundary                    → architecture
│   ├─ Jest, Testing Library, Playwright, or visual test             → frontend-testing-workflow
│   ├─ K6 load scenario                                              → load-testing
│   ├─ Client telemetry (error boundary, web-vitals, failures)       → observability-instrumentation
│   └─ Initial project documentation suite                           → documentation-creation
│
├─ Refactor existing code
│   ├─ Move / rename / extract / split a file                        → code-organization
│   ├─ Reduce complexity or split a file                             → complexity-management
│   └─ Improve testability                                           → frontend-testing-workflow / testing-workflow
│
├─ Review / validate work
│   ├─ Before commit, push, or PR                                    → ci-workflow
│   ├─ Address PR review comments                                    → code-review
│   ├─ Implemented BMAD specs vs every FR/NFR                        → bmad-fr-nfr-review-gate
│   ├─ Verify a UI change against the Figma reference                → figma-design-check
│   ├─ Lighthouse / web-vitals / accessibility                       → frontend-performance-accessibility
│   ├─ Mandatory accessibility gate (any UI change)                  → accessibility-audit
│   └─ Protected quality thresholds                                  → quality-standards
│
└─ Update documentation
    ├─ New project needs docs                                        → documentation-creation
    └─ Any code or workflow change                                   → documentation-sync
```

### Step 3: Read the Skill File

Each skill has a main `SKILL.md` file at `{skill-name}/SKILL.md` next to this guide. **Example**: for PR review work, read `code-review/SKILL.md`.

### Step 4: Follow Execution Steps

Each skill provides structured execution steps. Follow them sequentially. Run every check through the profile's logical target map so behavior matches CI. A typical shape:

1. Run the target mapped by `make.ci` (or, when `make.ci` is `null`, the individually-mapped sub-targets).
2. Exit `0` → task complete; non-zero → identify the failing check.
3. Route the failure to the matching specialized skill and fix the root cause.

```bash # profile-example
# With a profile whose make.ci maps to the `ci` target this is simply:
make ci
# ✅ frontend CI checks successfully passed!
```

### Step 5: Check Supporting Files

Complex skills use progressive disclosure:

```text
{skill-name}/
├── SKILL.md              # Core workflow (start here)
├── reference/            # Detailed reference docs (when present)
└── examples/             # Complete working examples (when present)
```

Load supporting files only when the active task needs the extra detail.

## The mandatory accessibility gate

Accessibility is **non-negotiable** for any change that adds or alters user-facing UI — components, layouts, forms, routes, color, focus, or interaction states. The `accessibility-audit` skill is the gate, and it is **never recorded NOT-APPLICABLE for a UI change**:

- Its static review (semantic HTML, ARIA, accessible names, focus order, keyboard operability, color contrast, target size, error messaging) **always runs** when `capabilities.accessibility_audit` is enabled.
- Its dynamic-browser branch (live audits against the running app) is gated by `capabilities.dynamic_a11y_testing`; when that flag is `false`, record the dynamic branch SKIPPED with a capability-absent note and complete the static review regardless.
- The audit is driven through the target mapped by `make.a11y` when present; when that key is `null`, the plugin substitutes its bundled accessibility lane so the gate still runs.

The `accessibility-auditor` agent runs this gate as the blocking reviewer in the review stage, alongside the `code-quality-reviewer` and `fr-nfr-reviewer` agents. The review stage does not pass while the a11y gate has open findings. For deeper, technique-level coverage, pair the audit with the companion accessibility team described below.

## Available Skills (19 Total)

### Autonomous Planning & Review-Gate Skills

| Skill                        | File                                | When to Use                                                                                                                      |
| ---------------------------- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **Autonomous BMAD Planning** | `bmad-autonomous-planning/SKILL.md` | Generate research, brief, PRD, architecture, and epics/stories from a short task description via focused planning subagents.     |
| **BMAD FR/NFR Review Gate**  | `bmad-fr-nfr-review-gate/SKILL.md`  | Verify implemented BMAD-scoped work against every FR/NFR, quality dimension, impact surface, manual evidence item, and CI check. |

### Workflow Skills

| Skill                | File                        | When to Use                                                                                               |
| -------------------- | --------------------------- | --------------------------------------------------------------------------------------------------------- |
| **CI Workflow**      | `ci-workflow/SKILL.md`      | Run the full local frontend CI suite through the profile and drive every check green before committing.   |
| **Code Review**      | `code-review/SKILL.md`      | Retrieve, categorize, and address PR review comments with an auditable, suppression-free evidence ledger. |
| **Testing Workflow** | `testing-workflow/SKILL.md` | Run and triage the functional test suites (unit, integration, E2E, visual, mutation).                     |

### Frontend Implementation Skills

| Skill                              | File                                          | When to Use                                                                                                      |
| ---------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Frontend Component Development** | `frontend-component-development/SKILL.md`     | Build or change a React component, hook, form, or feature view; wire UI to state, routing, i18n, or DI.          |
| **Frontend Testing Workflow**      | `frontend-testing-workflow/SKILL.md`          | Write or fix Jest, Testing Library, Playwright, or visual tests; strengthen tests to kill escaped mutants.       |
| **Frontend Quality Workflow**      | `frontend-quality-workflow/SKILL.md`          | Run or fix formatting, ESLint, TypeScript, markdownlint, duplication, and metrics — raise-only, no suppressions. |
| **Frontend Performance & A11y**    | `frontend-performance-accessibility/SKILL.md` | Improve Lighthouse scores, web-vitals, and accessibility on the perf/a11y improvement lane.                      |

### Quality & Architecture Skills

| Skill                     | File                             | When to Use                                                                                                      |
| ------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Architecture**          | `architecture/SKILL.md`          | Place a feature/component/hook/store/repository, decide a file's layer, or fix a dependency-cruiser violation.   |
| **Quality Standards**     | `quality-standards/SKILL.md`     | Overview and router of the protected quality thresholds → make target → specialized fixing skill.                |
| **Complexity Management** | `complexity-management/SKILL.md` | A component, hook, file, or function exceeds a rust-code-analysis complexity/size/Halstead budget.               |
| **Code Organization**     | `code-organization/SKILL.md`     | Place, move, rename, or split files; enforce naming, type-only files, semantic selectors, and config extraction. |

### Accessibility & Design Skills

| Skill                   | File                           | When to Use                                                                                                                              |
| ----------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **Accessibility Audit** | `accessibility-audit/SKILL.md` | The mandatory a11y gate — audit any UI change for WCAG compliance (static always; dynamic gated by `capabilities.dynamic_a11y_testing`). |
| **Figma Design Check**  | `figma-design-check/SKILL.md`  | Verify a planned or completed visual change against the Figma reference before writing UI code (gated by `capabilities.figma`).          |

### Documentation, Observability & Performance Skills

| Skill                      | File                                     | When to Use                                                                                                  |
| -------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **Documentation Creation** | `documentation-creation/SKILL.md`        | Build an INITIAL documentation suite from scratch for a project that has none.                               |
| **Documentation Sync**     | `documentation-sync/SKILL.md`            | Keep existing docs aligned after a code, command, tool, or workflow change.                                  |
| **Observability**          | `observability-instrumentation/SKILL.md` | Add client telemetry (error boundaries, web-vitals, captured failures) to a RUM/Sentry or deferred log sink. |
| **Load Testing**           | `load-testing/SKILL.md`                  | Create, run, or debug K6 load tests for the key SPA journeys (gated by `capabilities.load_testing`).         |

## Companion skills and agents (installed via `/fe-sdlc-setup`)

This plugin's skills own **process and gates**. The companion layer adds **technique-level depth** that the gates lean on but do not bundle. Running `/fe-sdlc-setup` installs the companion bundle declared by `companion.skills`, `companion.agents`, and `companion.install_command`:

- **Third-party ui-skills.com skills** — curated, global, technique-level skills for UI polish, motion/animation, design systems, color/contrast, performance, React/TypeScript, and accessibility. They are invoked by name (Claude Code) or read manually (other agents) when a task needs design-engineering depth beyond the process skills here.
- **The accessibility-lead agent team** — an accessibility-lead orchestrator plus a specialist team (ARIA, forms, keyboard navigation, contrast, alt-text/headings, live regions, modals, tables/data, and testing coaching). This team supplies the deep, multi-domain review that the `accessibility-auditor` agent and the `accessibility-audit` skill escalate to for any non-trivial UI change. For any UI change, the mandatory accessibility gate plus this companion team is the complete a11y review.

Read `docs/companion-skills.md` (at the plugin root) for the full catalog, the task → companion-skill map, and the exact install procedure. Companion skills are installed globally and are not committed inside this plugin tree; reference them by name once installed.

## Practical Examples

### Example 1: "fix the failing lint"

1. Read this guide and [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md).
2. Decision tree → `frontend-quality-workflow`.
3. Open `frontend-quality-workflow/SKILL.md`; run the target mapped by `make.format`, then the target mapped by `make.lint`.
4. If a metric fails, also consult `complexity-management/SKILL.md`; if duplication fails, refactor to deduplicate — never suppress.

### Example 2: "add a new Settings feature module"

1. Decision tree picks `frontend-component-development`, `code-organization`, `frontend-testing-workflow`, `accessibility-audit`, `documentation-sync`, and `ci-workflow`.
2. Triage every skill first; record an EXECUTE or NOT-APPLICABLE verdict for each, and open only the EXECUTE bodies.
3. Follow `code-organization` for placement under the source root (`architecture.source_root`) and `frontend-component-development` for component, styling, i18n, and DI patterns.
4. Add tests per `frontend-testing-workflow`; run the **mandatory accessibility gate** via `accessibility-audit`; update docs per `documentation-sync`.
5. Validate with the targets mapped by `make.format`, focused tests, then `make.ci`, and finish with the New Feature Verification Gate — every skill verdict recorded, no silent skips.

### Example 3: "address PR comments on this branch"

1. Decision tree → `code-review`. Open `code-review/SKILL.md`.
2. Retrieve the comments, categorize each (committable suggestion, bug, architecture, test gap, question), and apply suppression-free fixes with per-comment commits.
3. Re-run the targets mapped by `make.format`, focused tests, and `make.ci` against the pushed head before reporting completion.

### Example 4: "plan a feature autonomously"

1. Decision tree → `bmad-autonomous-planning`. Open its `SKILL.md`.
2. Run each planning phase (research, brief, PRD, architecture, epics/stories, readiness) as a separate focused subagent.
3. Review the generated artifacts and any unresolved questions before moving to implementation.

### Example 5: "investigate a Lighthouse regression"

1. Decision tree → `frontend-performance-accessibility`.
2. Run the targets mapped by `make.lighthouse_desktop` and `make.lighthouse_mobile`; cross-check web-vitals via `observability-instrumentation` if telemetry is missing.
3. If the fix changes rendering cost, use `frontend-component-development` for the implementation and `frontend-testing-workflow` to lock in regression coverage. Re-run the **accessibility gate** if the markup changed.

## Quality Standards & Protected Thresholds

Thresholds come exclusively from the profile's `quality.*` keys and are **raise-only**: a profile may tighten a bar above the canonical default, never relax it. Violation-count ceilings are fixed at `0`.

| Profile key                    | Metric                                | Skill for issues                     |
| ------------------------------ | ------------------------------------- | ------------------------------------ |
| `quality.eslint_errors`        | ESLint errors (ceiling `0`)           | `frontend-quality-workflow`          |
| `quality.tsc_errors`           | TypeScript errors (ceiling `0`)       | `frontend-quality-workflow`          |
| `quality.markdownlint_errors`  | markdownlint violations (ceiling `0`) | `frontend-quality-workflow`          |
| `quality.jscpd_clones`         | Duplication clones (ceiling `0`)      | `complexity-management`              |
| `quality.metrics_enforced`     | rust-code-analysis hard-fail gate     | `complexity-management`              |
| `quality.depcruise_violations` | dependency-cruiser violations (`0`)   | `architecture`                       |
| `quality.coverage_statements`  | Jest coverage floor                   | `frontend-testing-workflow`          |
| `quality.mutation_msi`         | Stryker mutation MSI floor            | `frontend-testing-workflow`          |
| `quality.visual_diffs`         | Visual diffs (ceiling `0`)            | `frontend-testing-workflow`          |
| `quality.lighthouse_mobile`    | Mobile Lighthouse floor               | `frontend-performance-accessibility` |

**Always improve the code to meet the standard. Never lower a threshold. Never silence a finding** with `eslint-disable`, `// @ts-ignore`, `editorconfig-checker-disable`, `prettier-ignore`, or markdownlint disable comments. Fix the root cause; if a rule genuinely does not fit, refactor the code so the rule's intent still holds.

## Locked Configuration Policy

Configuration files for lint, format, TypeScript, metrics, duplication, dependency-cruiser, and the test harnesses are **locked**. Fix the code to satisfy them — never the reverse. If a task requires changing one:

1. Confirm the change was explicitly requested.
2. Keep it isolated in a dedicated configuration PR with rationale, impact, and rollback.
3. Never bypass it with disable/ignore comments, and never normalize "merge with red CI" — that is a human exception path only.

## Key Differences from Claude Code

| Aspect                | Claude Code               | Other Agents                          |
| --------------------- | ------------------------- | ------------------------------------- |
| **Discovery**         | Automatic                 | Manual (read SKILL-DECISION-GUIDE.md) |
| **Invocation**        | Automatic via Skill tool  | Manual (read the `SKILL.md` file)     |
| **Execution**         | Tool-guided               | Self-guided (follow steps)            |
| **Multi-file skills** | Auto-loaded as referenced | Read supporting files as needed       |

## Common Workflows

### Before every commit or push

1. Read `ci-workflow/SKILL.md`.
2. Run the target mapped by `make.format`, focused tests, then `make.ci` (or the mapped sub-targets when `make.ci` is `null`).
3. Success criteria: exit code `0` (many repositories also print a success banner).
4. On failure, follow the fix routing in the matching skill.

### Creating a new feature

1. `frontend-component-development` — React, the configured UI library, theming, i18n, DI.
2. `code-organization` — placement under the source root and the allowed-folder law.
3. `frontend-testing-workflow` — unit, E2E, and visual coverage.
4. `accessibility-audit` — the mandatory a11y gate (never skipped for UI).
5. `observability-instrumentation` — telemetry when user-impacting signals are involved.
6. `documentation-sync` — update docs.
7. `ci-workflow` — validate everything, then run the New Feature Verification Gate: every skill verdict recorded, no silent skips.

### Fixing quality issues

1. Identify the issue type (lint, types, markdown, duplication, metrics, complexity, tests, boundaries, a11y, performance).
2. Use the decision guide to pick the most specific skill.
3. Read the `SKILL.md`, follow its remediation, and consult `complexity-management` / `code-organization` when refactoring.
4. Re-run the targets mapped by `make.format` and `make.ci`.

## File Structure Reference

```text
skills/
├── AI-AGENT-GUIDE.md           # This file — start here
├── SKILL-DECISION-GUIDE.md     # Decision tree for choosing skills
│
├── accessibility-audit/
├── architecture/
├── bmad-autonomous-planning/
├── bmad-fr-nfr-review-gate/
├── ci-workflow/
├── code-organization/
├── code-review/
├── complexity-management/
├── documentation-creation/
├── documentation-sync/
├── figma-design-check/
├── frontend-component-development/
├── frontend-performance-accessibility/
├── frontend-quality-workflow/
├── frontend-testing-workflow/
├── load-testing/
├── observability-instrumentation/
├── quality-standards/
└── testing-workflow/           # Every skill directory has a SKILL.md;
                                # some add reference/ and examples/
```

## Tips for Effective Use

### Do

- Start with [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md) when unsure.
- Read the entire `SKILL.md` before executing, and follow its steps sequentially.
- Resolve every command through the profile's `make.*` map; degrade with a note when a value is `null`.
- Treat the accessibility gate as mandatory for any UI change.
- Respect protected `quality.*` thresholds (raise-only) and complexity gates.
- Record a verdict for every skill in the verification gate — every skill verdict recorded, no silent skips.

### Do Not

- Skip the decision guide or jump to execution without reading the full skill.
- Lower lint, TypeScript, test, metrics, coverage, or Lighthouse thresholds.
- Silence findings with disable / ignore / suppress annotations.
- Invent Make targets — always resolve them through the profile's logical map.
- Assume a specific bundler, package manager, or runtime — read `framework.*` from the profile.
- Skip the accessibility gate on a UI change.

## Getting Help

1. Read a skill's `reference/` directory when it ships one (e.g. detailed patterns and troubleshooting).
2. Check `examples/` when a skill ships complete working examples.
3. Read `docs/companion-skills.md` for the companion skills and accessibility team.
4. Check the profile: `.claude/react-sdlc.yml` resolves every logical target and capability flag.

## Conclusion

The skills system provides **modular, reusable workflows** that work across AI agents and across divergent React/TypeScript frontend repositories via the project profile. Claude Code invokes skills automatically; other agents achieve the same result by reading and following the skill files manually.

**Start here:**

1. Read this guide (done).
2. Read [SKILL-DECISION-GUIDE.md](SKILL-DECISION-GUIDE.md).
3. Pick every relevant skill for your task.
4. Follow each skill's execution steps, and finish a new feature with the verification gate.
