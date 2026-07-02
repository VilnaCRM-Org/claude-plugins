# Skill Decision Guide

**Choose the right skill for your task based on what you're trying to accomplish.**
**Non-negotiable rule**: Fix root causes. Do not silence ESLint, TypeScript, Prettier,
markdownlint, rust-code-analysis, dependency-cruiser, jscpd, Stryker, or any other quality
tool with `eslint-disable`, `// @ts-ignore`, `prettier-ignore`, or markdownlint disable
comments. Never lower a `quality.*` threshold and never edit `.dependency-cruiser` rules to
admit a violation — always fix the code instead.

All make/CLI invocations below go through the profile's logical target map (`make.*` keys in
`.claude/react-sdlc.yml`). "The target mapped by `make.ci`" means: look up the `make.ci` value
in the profile and run that Make target. A `null` mapping means the capability is absent — skip
with a recorded note, never invent a target. Phrase tooling generically: "the configured
bundler (`framework.bundler`)", "the project package manager (`framework.package_manager`)" —
never assume a single stack.

## Profile keys consumed

- `make.ci`, `make.fr_nfr_gate`, `make.test_load`, `make.a11y`, `make.lint_deps`,
  `make.pr_comments`, `make.lighthouse_desktop`, `make.lighthouse_mobile`
- `quality.coverage_lines`, `quality.mutation_msi`, `quality.depcruise_violations`,
  `quality.lighthouse_desktop`, `quality.lighthouse_mobile`
- `capabilities.figma`, `capabilities.load_testing`, `capabilities.accessibility_audit`,
  `capabilities.dynamic_a11y_testing`, `capabilities.observability`
- `architecture.source_root`, `architecture.modules`, `architecture.component_prefix`
- `framework.ui`, `framework.bundler`, `framework.package_manager`

## Mandatory New Feature Verification Gate (ALL Skills)

If you created or modified a **NEW feature** (a new route, component family, hook, telemetry
signal, schema, or any user-facing behavior), you MUST evaluate **every** skill in this
directory **after implementation**. The decision tree below is for choosing the primary skill
during the work. It does **not** replace this gate.

**Execution rules (triage-first):**

1. Decide each skill's verdict from its frontmatter `description` (in the listed `SKILL.md`)
   plus this guide alone — never load a skill body to decide a verdict. Record one verdict per
   skill: **EXECUTE** (with a concrete one-line trigger) or **NOT-APPLICABLE** (with a concrete
   reason). The gate contract is: **every skill verdict recorded, no silent skips**.
2. Open a `SKILL.md` body only **after** recording an EXECUTE verdict for it; then follow its
   steps exactly. NOT-APPLICABLE verdicts are recorded without loading the body — this keeps the
   token cost bounded (full bodies and reference files load only for EXECUTE verdicts).
3. Run required commands only through the profile's `make.*` target map (generic tooling like
   the project package manager, `git`, and `gh` is allowed directly).
4. Capability-gated skills are skipped **with a recorded note** when their capability is `false`
   or their target maps to `null`: `figma-design-check` via `capabilities.figma`;
   `load-testing` via `capabilities.load_testing` + `make.test_load`; `accessibility-audit` via
   `capabilities.accessibility_audit` (its dynamic-browser branch additionally via
   `capabilities.dynamic_a11y_testing`). `observability-instrumentation` is **not** skip-gated:
   `capabilities.observability` only selects its emission backend — when `false`, evaluate the
   skill through its generic web-vitals / structured-log branch instead of skipping.
5. Provide evidence in your response: commands run and outcomes. If you cannot run a command,
   stop and explain why.
6. Do not claim the feature is complete until this gate is finished.

**Skills to evaluate for every new feature:**

- `accessibility-audit`
- `architecture`
- `ci-workflow`
- `code-organization`
- `code-review`
- `complexity-management`
- `documentation-creation`
- `documentation-sync`
- `figma-design-check`
- `frontend-component-development`
- `frontend-performance-accessibility`
- `frontend-quality-workflow`
- `frontend-testing-workflow`
- `load-testing`
- `observability-instrumentation`
- `quality-standards`
- `testing-workflow`

**Conditional BMAD skills:**

- `bmad-fr-nfr-review-gate` when BMAD specs exist for the implemented work. Run it through the
  target mapped by `make.fr_nfr_gate` (the plugin substitutes its own gate script when the
  mapping is `null`); if no BMAD specs exist, record **"Not applicable"** with the concrete
  reason.
- `bmad-autonomous-planning` is a planning-time skill only; during the gate record
  **"Not applicable — planning skill"** unless the task itself was to produce specs.

## Quick Decision Tree

```text
What are you trying to do?
│
├─ Fix something broken
│   ├─ Lint, format, TS, markdown, or metrics fail → frontend-quality-workflow
│   ├─ Function/file exceeds the complexity gate → complexity-management
│   ├─ Failing Jest, Testing Library, Playwright, or visual → frontend-testing-workflow
│   ├─ Broad suite triage / pick the right suite → testing-workflow
│   ├─ Lighthouse, web-vitals, or a11y regression → frontend-performance-accessibility
│   ├─ dependency-cruiser boundary violation → architecture
│   └─ CI readiness before commit/push/PR → ci-workflow
│
├─ Create something new
│   ├─ ANY UI / visual change → figma-design-check (before writing or editing UI code)
│   ├─ React component, hook, form, or feature UI → frontend-component-development
│   ├─ Module / file placement and naming → code-organization
│   ├─ New feature, route, or service boundary → architecture
│   ├─ Jest, Testing Library, Playwright, or visual test → frontend-testing-workflow
│   ├─ K6 load scenario → load-testing
│   ├─ web-vitals, error boundary, or structured log → observability-instrumentation
│   ├─ Full planning specs from a short prompt → bmad-autonomous-planning
│   └─ Project docs suite from scratch → documentation-creation
│
├─ Refactor existing code
│   ├─ Move / rename / split files → code-organization
│   ├─ Reduce cyclomatic, cognitive, ABC, or file size → complexity-management
│   ├─ Improve testability → frontend-testing-workflow / testing-workflow
│   └─ Tighten an observability boundary → observability-instrumentation
│
├─ Review / validate work
│   ├─ Before commit, push, or PR → ci-workflow
│   ├─ Address PR review comments → code-review
│   ├─ dependency-cruiser boundary violation → architecture
│   ├─ Confirm protected thresholds → quality-standards
│   ├─ Lighthouse / web-vitals audit → frontend-performance-accessibility
│   ├─ WCAG / axe / keyboard / screen-reader audit → accessibility-audit
│   └─ Implemented BMAD specs → bmad-fr-nfr-review-gate
│
└─ Update documentation
    ├─ New project / suite needs docs → documentation-creation
    └─ Any code, command, tool, or workflow change → documentation-sync
```

All 19 skills appear above: `accessibility-audit`, `architecture`,
`bmad-autonomous-planning`, `bmad-fr-nfr-review-gate`, `ci-workflow`, `code-organization`,
`code-review`, `complexity-management`, `documentation-creation`, `documentation-sync`,
`figma-design-check`, `frontend-component-development`, `frontend-performance-accessibility`,
`frontend-quality-workflow`, `frontend-testing-workflow`, `load-testing`,
`observability-instrumentation`, `quality-standards`, `testing-workflow`.

## Scenario-Based Guide

### "Lint, Prettier, TypeScript, markdownlint, or metrics is failing"

**Use**: [frontend-quality-workflow](frontend-quality-workflow/SKILL.md)

Runs formatting (Prettier + the project formatter) before the read-only lint gate so mutating
formatters do not race it, then walks ESLint, TypeScript, markdownlint, jscpd, and the
rust-code-analysis output. Quality ceilings (`quality.eslint_errors`, `quality.tsc_errors`,
`quality.markdownlint_errors`, `quality.jscpd_clones`) are fixed at `0`.

**NOT**: complexity-management unless the rust-code-analysis hard-fail metrics specifically trip.

---

### "A rust-code-analysis hard-fail metric tripped"

**Use**: [complexity-management](complexity-management/SKILL.md)

Use named helpers, smaller files, lookup maps, and typed option objects to bring function and
file metrics (cyclomatic, cognitive, ABC, exit points, LLOC/PLOC/SLOC, Halstead, MI) back under
the hard-fail thresholds in `config/metrics-policy.json`.

**NOT**: lowering thresholds in the metrics policy — the gate is raise-only.

---

### "Jest, Testing Library, Playwright, or visual snapshots are failing"

**Use**: [frontend-testing-workflow](frontend-testing-workflow/SKILL.md)

Covers the client (jsdom) and server (node) unit environments, E2E, visual snapshot updates, the
API-mock-backed E2E debugging path, and the `quality.coverage_lines` floor (default `100`,
raise-only). Tests locate elements by user-facing semantics — never by a test-only `data-testid`.

**NOT**: testing-workflow when you already know the specific suite.

---

### "I need to pick the right test suite or triage a broad failure"

**Use**: [testing-workflow](testing-workflow/SKILL.md)

Routes to unit, E2E, visual, memory-leak, mutation, or load suites and explains environment
selection (client vs server unit env). The `quality.mutation_msi` floor (default read from the
mutation config's `break` threshold, raise-only) gates the mutation suite.

**NOT**: load-testing (that's for traffic patterns, not functional behavior).

---

### "I am building or changing a React component, hook, or feature UI"

**FIRST (before any visual change)**: [figma-design-check](figma-design-check/SKILL.md) — verify
the planned change against the Figma design via the Figma MCP. If the change alters anything the
user sees (color, layout, spacing, typography, sizing, or an interaction state), run this gate
before writing or editing UI code; ask for the Figma reference if none is known. Gated by
`capabilities.figma` — skip with a capability-absent note when it is `false`.

**Use**: [frontend-component-development](frontend-component-development/SKILL.md)

Enforces the `architecture.component_prefix` convention, the configured UI library
(`framework.ui`) + CSS-in-JS patterns, i18n catalogs, state/DI boundaries, and route
registration.

**ALSO**: [code-organization](code-organization/SKILL.md) for placement,
[frontend-testing-workflow](frontend-testing-workflow/SKILL.md) for tests.

---

### "I need to move, rename, or split a frontend file"

**Use**: [code-organization](code-organization/SKILL.md)

Confirms placement under `architecture.source_root` (modules, shared components, services,
utilities, and the test mirror) and enforces the project's path aliases and kebab-case naming.

**ALSO**: [architecture](architecture/SKILL.md) if the move crosses a module or service boundary.

---

### "Where should this feature, hook, or repository live?"

**Use**: [architecture](architecture/SKILL.md)

Embeds the layered Component → Hook → Repository → API flow, the module catalog
(`architecture.modules`), and every dependency-cruiser boundary rule. Use this when
`make.lint_deps` fails or when a data flow crosses modules or services. The
`quality.depcruise_violations` ceiling is fixed at `0`.

**ALSO**: [code-organization](code-organization/SKILL.md) for naming;
[frontend-component-development](frontend-component-development/SKILL.md) for the implementation.

---

### "I need to add or audit Lighthouse, web-vitals, or render-cost performance"

**Use**: [frontend-performance-accessibility](frontend-performance-accessibility/SKILL.md)

Runs the targets mapped by `make.lighthouse_desktop` and `make.lighthouse_mobile` and audits
web-vitals plus the Lighthouse accessibility category against the `quality.lighthouse_desktop`
(floor `0.95`) and `quality.lighthouse_mobile` (floor `0.85`) gates.

**NOT**: load-testing (that targets traffic patterns, not render cost). For a deep WCAG /
assistive-technology audit, use accessibility-audit.

---

### "I need a WCAG / axe / keyboard / screen-reader accessibility audit"

**Use**: [accessibility-audit](accessibility-audit/SKILL.md)

Drives the structured a11y review — semantic markup, ARIA correctness, focus management,
keyboard operability, contrast, and assistive-technology behavior — through the target mapped by
`make.a11y`. Gated by `capabilities.accessibility_audit`; its dynamic in-browser branch is
additionally gated by `capabilities.dynamic_a11y_testing`. **SKIPPED** with a recorded
capability-absent note when those are `false`. Accessibility is non-negotiable: route every fix
back through the component implementation, never a suppression.

**NOT**: frontend-performance-accessibility (that is the Lighthouse-category pass, not the full
WCAG audit).

---

### "I need K6 load coverage for a flow"

**Use**: [load-testing](load-testing/SKILL.md)

Smoke / average / stress / spike scenarios via the target mapped by `make.test_load`. Gated by
`capabilities.load_testing`; **SKIPPED** with a recorded note when it is `false` or
`make.test_load` is `null`.

**NOT**: frontend-performance-accessibility (that's render cost, not concurrent load).

---

### "I need web-vitals telemetry, an error boundary, or structured logs"

**Use**: [observability-instrumentation](observability-instrumentation/SKILL.md)

Adds frontend signals, error boundaries, and analytics-safe payloads. `capabilities.observability`
selects the emission backend; when `false`, the skill's generic web-vitals / structured-log
branch applies — the flag never makes the skill skippable.

**NOT**: frontend-performance-accessibility (that audits results; this emits the signal).

---

### "I'm addressing PR review comments"

**Use**: [code-review](code-review/SKILL.md)

Retrieves comments through the target mapped by `make.pr_comments` and walks the comment
categories (committable suggestion, bug, architecture, test gap, question), routing each to its
topic skill.

**NOT**: ci-workflow (that runs the gate, not the comment workflow).

---

### "I made code changes and need to validate before committing"

**Use**: [ci-workflow](ci-workflow/SKILL.md)

Sequences formatting, focused tests, and the full local gate through the target mapped by
`make.ci`. When `make.ci` is `null` (e.g. a library repo with no aggregate target), it runs the
individually-mapped sub-targets instead.

**NOT**: testing-workflow (that's specifically for tests).

---

### "I want to understand what quality metrics are protected"

**Use**: [quality-standards](quality-standards/SKILL.md)

Indexes every `quality.*` threshold (ESLint, TypeScript, markdownlint, jscpd, dependency-cruiser,
rust-code-analysis, coverage, mutation, visual, Lighthouse), the raise-only rule, and the fixed
ceilings.

**NOT**: complexity-management (that's specifically the metrics gate).

---

### "I implemented BMAD specs and need to verify FR/NFR coverage"

**Use**: [bmad-fr-nfr-review-gate](bmad-fr-nfr-review-gate/SKILL.md)

Checks implemented work against every BMAD FR/NFR, the pinned NFR categories, manual test
evidence, GitHub review status, and CI status; requires a full pass for every applicable row
before completion. Run it through the target mapped by `make.fr_nfr_gate`.

**ALSO**: [code-review](code-review/SKILL.md) for PR comments and
[ci-workflow](ci-workflow/SKILL.md) for local CI failures.

---

### "I need planning specs created autonomously from a short task description"

**Use**: [bmad-autonomous-planning](bmad-autonomous-planning/SKILL.md)

Orchestrates research, brief, PRD, architecture, and epics/stories through focused subagents —
one per planning phase — without stopping for interactive planning menus.

**NOT**: an interactive PRD flow (assumes human-in-the-loop progression).

---

### "I added a feature and need to update docs"

**Use**: [documentation-sync](documentation-sync/SKILL.md)

Identifies which documentation files need updating after a code, command, tool, or workflow
change.

---

### "I need to create the documentation suite from scratch"

**Use**: [documentation-creation](documentation-creation/SKILL.md)

Templates for feature READMEs, agent guides, and project documentation.

**NOT**: documentation-sync (that's for updating existing docs).

## Skill Relationship Map

```text
                       quality-standards
                       (thresholds & routing)
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
 frontend-quality-       complexity-           frontend-performance-
   workflow              management            accessibility
        │                     │                       │
        └─────────┬───────────┘            ┌──────────┴──────────┐
                  ▼                         ▼                     ▼
          code-organization          accessibility-        load-testing
                  │                      audit
                  ▼                         │
        architecture                        ▼
                  │                 observability-instrumentation
                  ▼
   frontend-component-development ◄── figma-design-check
                  │
                  ▼
      frontend-testing-workflow ──► testing-workflow
                  │
                  ▼
        ci-workflow ──► code-review ──► bmad-fr-nfr-review-gate
                  │
                  ▼
   documentation-sync ──► documentation-creation
```

## Common Confusions

| Confusion                                                 | Clarification                                                                                                                                                 |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| frontend-quality-workflow vs complexity-management        | **Lint, format, TS, markdown** → frontend-quality-workflow; **function/file metrics over hard-fail** → complexity-management                                  |
| testing-workflow vs frontend-testing-workflow             | **Broad suite routing / triage** → testing-workflow; **specific Jest / RTL / Playwright / visual work** → frontend-testing-workflow                           |
| ci-workflow vs frontend-quality-workflow                  | **Order, scope, and the full gate** → ci-workflow; **tooling specifics for format/lint** → frontend-quality-workflow                                          |
| frontend-performance-accessibility vs accessibility-audit | **Lighthouse-category render/a11y pass** → frontend-performance-accessibility; **full WCAG / axe / keyboard / screen-reader audit** → accessibility-audit     |
| frontend-performance-accessibility vs load-testing        | **Render cost / Lighthouse** → frontend-performance-accessibility; **traffic load (K6)** → load-testing                                                       |
| code-organization vs architecture                         | **Move/rename/split for structure** → code-organization; **layer/module boundary and dependency-cruiser rules** → architecture                                |
| code-organization vs complexity-management                | **Structural refactoring** (move/rename/split) → code-organization; **reduce code complexity metrics** → complexity-management                                |
| observability-instrumentation vs frontend-performance     | **Add signals** (web-vitals emission, error boundary, structured log) → observability-instrumentation; **audit results** → frontend-performance-accessibility |
| documentation-creation vs documentation-sync              | **Create new docs suite** → documentation-creation; **update existing docs** → documentation-sync                                                             |
| code-review vs ci-workflow                                | **Resolve PR comments** → code-review; **pre-commit / pre-push gate** → ci-workflow                                                                           |

## Multiple Skills for One Task

Some tasks benefit from multiple skills:

### Creating a complete new feature

1. **figma-design-check** – verify the planned UI against Figma before writing code (if
   `capabilities.figma`).
2. **architecture** – confirm the layer for each new file and the repository/service boundary.
3. **frontend-component-development** – component, hook, CSS-in-JS, i18n.
4. **code-organization** – module placement and exports.
5. **frontend-testing-workflow** – Jest, RTL, Playwright, visual coverage.
6. **accessibility-audit** – WCAG / keyboard / screen-reader review (if
   `capabilities.accessibility_audit`).
7. **observability-instrumentation** – telemetry where relevant.
8. **documentation-sync** – docs and READMEs.
9. **ci-workflow** – validate everything.

### Fixing a failing quality gate

1. **frontend-quality-workflow** – format, lint, types, markdown.
2. **complexity-management** – reduce metrics if the gates trip.
3. **architecture** – fix dependency-cruiser boundaries if a move broke them.
4. **frontend-testing-workflow** – update tests broken by the refactor.
5. **ci-workflow** – final validation.

### Performance and accessibility regression

1. **frontend-performance-accessibility** – measure with Lighthouse / web-vitals.
2. **accessibility-audit** – run the full WCAG audit for a11y regressions.
3. **frontend-component-development** – implement the render-cost or markup fix.
4. **observability-instrumentation** – ensure the regression signal is captured.
5. **load-testing** – validate behavior under traffic if relevant.
6. **frontend-testing-workflow** – lock in regression coverage.
7. **ci-workflow** – final validation.

### Refactoring existing code

1. **code-organization** – verify placement and naming.
2. **complexity-management** – simplify dense functions or files.
3. **architecture** – verify boundaries after the moves.
4. **frontend-testing-workflow** – ensure tests still cover the refactor.
5. **documentation-sync** – update docs if commands or APIs change.
6. **ci-workflow** – final validation.

### Addressing PR review comments

1. **code-review** – retrieve and categorize comments.
2. The skill matching the comment topic (component, test, docs, metrics, a11y).
3. **frontend-quality-workflow** – format and lint.
4. **ci-workflow** – validate before pushing changes.

For the full agent-onboarding flow and the mandatory skill-check protocol, see
[AI-AGENT-GUIDE.md](AI-AGENT-GUIDE.md).
</content>
</invoke>
