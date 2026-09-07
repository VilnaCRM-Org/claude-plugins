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
- `quality.coverage_statements`, `quality.mutation_msi`, `quality.depcruise_violations`,
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

All 19 process skills appear above: `accessibility-audit`, `architecture`,
`bmad-autonomous-planning`, `bmad-fr-nfr-review-gate`, `ci-workflow`, `code-organization`,
`code-review`, `complexity-management`, `documentation-creation`, `documentation-sync`,
`figma-design-check`, `frontend-component-development`, `frontend-performance-accessibility`,
`frontend-quality-workflow`, `frontend-testing-workflow`, `load-testing`,
`observability-instrumentation`, `quality-standards`, `testing-workflow`.

<!-- technique-library:start -->

## Technique library (67 skills)

The 19 process skills above own the SDLC stages and gates. The technique library below holds
narrower, symptom-triggered skills learned inside the reference repository shapes. They take part
in the same triage — **every skill verdict recorded, no silent skips** — and are decided from their
frontmatter `description` alone; open a body only after an EXECUTE verdict. None of them gates a
capability, so a NOT-APPLICABLE verdict for a technique skill always cites the absent symptom.

### Mutation testing (Stryker)

- [jsdom-mui-mutation-traps](jsdom-mui-mutation-traps/SKILL.md) — Use when mutants in MUI component styling or controlled-value handling survive despite tests that look like they cover the behaviour, when a test reads getComputedStyle on an Emotion styled element u…
- [mutation-gate-barrel-leaf-extraction](mutation-gate-barrel-leaf-extraction/SKILL.md) — Use when one Stryker shard runs far longer than its peers and the slow files import a small helper through a component barrel, when jest --findRelatedTests reports an unexpectedly large related-suite…
- [mutation-shard-capacity-growth](mutation-shard-capacity-growth/SKILL.md) — Use when a Stryker mutation shard approaches or exceeds an already-calibrated CI timeout-minutes because the mutate scope grew, when shard wall clocks are badly uneven under byte-weighted packing, or…
- [mutation-test-barrel-import-trap](mutation-test-barrel-import-trap/SKILL.md) — Use when one test suite re-runs for mutants in unrelated components and the mutation gate times out or drags, or when a source module imports from an aggregate barrel such as the components index (`@…
- [mutation-testing-stryker-gotchas](mutation-testing-stryker-gotchas/SKILL.md) — Use when a Stryker survivor cannot be explained by a missing assertion — a mutant reported `Survived` with an empty `killedBy` or `testsCompleted` of zero, a `Stryker disable next-line` comment that…
- [stryker-mutation-timeout-regression-alarm](stryker-mutation-timeout-regression-alarm/SKILL.md) — Use when a Stryker mutation workflow carries no `timeout-minutes` on its shard or merge job, when a mutation run's cost jumps an order of magnitude with no change to the mutate scope, when mutants co…

### Storybook, visual and Playwright

- [playwright-mobile-device-lane](playwright-mobile-device-lane/SKILL.md) — Use when adding or extending real mobile-device coverage to a Playwright suite — touch/tap specs, Pixel or iPhone device descriptors, `isMobile`/`hasTouch` contexts, device-pixel-ratio visual baselin…
- [playwright-visual-baseline-grep-title](playwright-visual-baseline-grep-title/SKILL.md) — Use when a Playwright run filtered with -g / --grep exits 0 but an expected visual baseline PNG was never written, when a snapshot filter has to match a title containing spaces or a separator, or whe…
- [storybook-controlled-components](storybook-controlled-components/SKILL.md) — Use when a Storybook story for a controlled component is frozen — picking an option, deleting a chip, typing, or toggling fires onChange but nothing on screen changes. Applies to any story whose comp…
- [storybook-dev-host-launch](storybook-dev-host-launch/SKILL.md) — Use when the repository's Storybook dev-server target appears to hang and the browser cannot reach port 6006, when Storybook must be opened in a real browser for interactive component work, or when c…
- [storybook-dev-server-visual-test-staleness](storybook-dev-server-visual-test-staleness/SKILL.md) — Use when a committed Playwright screenshot baseline shows an outdated render — wrong language, old design, a state the component no longer produces — while the visual suite still reports green, or wh…
- [storybook-figma-audit](storybook-figma-audit/SKILL.md) — Use when sweeping a whole component suite or showcase board against its Figma masters — before a release, after a design revision, or when several components are suspected of drift — and the output h…
- [storybook-file-pattern-sync](storybook-file-pattern-sync/SKILL.md) — Use when the set of Storybook story file extensions changes — adding a .stories.js, .stories.jsx or .stories.mjs alongside .stories.tsx, renaming a story file, or widening the stories glob in .storyb…
- [storybook-story-authoring](storybook-story-authoring/SKILL.md) — Use when adding or changing a `*.stories.tsx` file for a React component — a new shared primitive carrying `architecture.component_prefix`, a variant or state that needs documenting, sidebar `title`…
- [storybook-visual-state-nested-props](storybook-visual-state-nested-props/SKILL.md) — Use when a Storybook-driven screenshot test configures component state through `&args=` in the story URL and the state never applies — the story renders with default props, the recorded baseline look…

### Testing patterns (Jest, Testing Library, Bats)

- [access-control-safety-testing](access-control-safety-testing/SKILL.md) — Use when writing or reviewing the must-fail fixture for a gate that bans direct role or permission membership checks — an ESLint `no-restricted-syntax` selector, a dependency-cruiser rule, or a hand-…
- [aria-label-split-text-rendering](aria-label-split-text-rendering/SKILL.md) — Use when one text value is rendered across two or more elements for styling — a typed prefix in one ink and the completion in another, a highlighted search match, a two-tone label — and a getByRole q…
- [auth-testing-with-seeded-tokens](auth-testing-with-seeded-tokens/SKILL.md) — Use when writing browser tests for sign-in redirects, protected-route bounces or destination-preservation in a repository whose production-parity test image seeds every visitor with an auth token for…
- [barrel-export-validation-testing](barrel-export-validation-testing/SKILL.md) — Use when writing or repairing a test that guards a public barrel — an index that re-exports components and their prop types — and the guard parses export lines with a regex, checks names with a loose…
- [bats-fixture-full-validation](bats-fixture-full-validation/SKILL.md) — Use when a Bats helper, stub or fixture in `tests/bats/` has been edited and the change is about to be staged. Symptoms include a filtered `bats -f "pattern"` run passing while the full suite fails,…
- [bats-test-workflow](bats-test-workflow/SKILL.md) — Use when writing, running, or debugging Bats tests for infrastructure code — Makefile targets, shell scripts under the scripts and CI-scripts directories, jq filters, git hooks, and CI helpers. Trigg…
- [integration-singleton-isolation](integration-singleton-isolation/SKILL.md) — Use when an integration or unit test mutates module-level state that outlives it, such as `await import('@/…')` for a side effect, a `bind*` or `set` call on an `export default new …` singleton, or a…
- [jest-dom-aria-assertion-pattern](jest-dom-aria-assertion-pattern/SKILL.md) — Use when a component test asserts on ARIA attributes and ESLint reports jest-dom/prefer-required or jest-dom/prefer-to-have-attribute, when toBeRequired() cannot distinguish native required from aria…
- [test-discovery-contract](test-discovery-contract/SKILL.md) — Use when a test file exists, type-checks and lints clean but never runs — a spec under an e2e root named with a Jest `.test.ts` suffix, a file missing a required infix, a new extension no runner matc…
- [test-naming-and-fixture-clarity](test-naming-and-fixture-clarity/SKILL.md) — Use when naming or reviewing a test whose title does not match what its fixture actually sets up, when a fixture keeps or removes files for a non-obvious reason, or when a maintainer is about to "sim…

### Architecture and code structure

- [api-extractor-forgotten-export-resolution](api-extractor-forgotten-export-resolution/SKILL.md) — Use when a library build prints `Warning: (ae-forgotten-export) The symbol "X" needs to be exported by the entry point`, when a published `.d.ts` rollup shows props as `any` or as an opaque generated…
- [architectural-reconciliation](architectural-reconciliation/SKILL.md) — Use when merging a long-lived feature branch whose conflicts are architectural rather than textual — the branch built a route manifest while the base adopted a route registry, reads `process.env` dir…
- [compliance-drift-guard](compliance-drift-guard/SKILL.md) — Use when governance evidence lives in markdown — a component provenance registry, a deviation ledger, a definition-of-done compliance matrix, a coverage manifest — and nothing stops it going stale, s…
- [configuration-management](configuration-management/SKILL.md) — Use when adding, renaming or reading an environment variable, extending the typed config layer, or diagnosing a build that fails at boot with a schema error. Triggers include "add an env var", readin…
- [deferred-di-reflect-metadata-optimization](deferred-di-reflect-metadata-optimization/SKILL.md) — Use when a tsyringe application loads its DI container behind a dynamic `import()` and the eager entry bundle still pulls in `reflect-metadata`, or when a mobile Lighthouse performance budget is shor…
- [depcruise-rule-alternative-disjointness](depcruise-rule-alternative-disjointness/SKILL.md) — Use when an architecture rule is written as several alternatives that must each be provable — a dependency-cruiser rule in `.dependency-cruiser.js`, or an esquery `no-restricted-syntax` union of impo…
- [graphql-api-hardening](graphql-api-hardening/SKILL.md) — Use when editing an Apollo Server mock or any GraphQL resolver, error formatter, validation rule, or response shape, and when changing the pinned upstream API service version. Triggers include create…
- [host-stack-infrastructure](host-stack-infrastructure/SKILL.md) — Use when adding or changing how a browser or memory-leak suite is executed — a host-built export instead of the Docker prod stack, a new executor mode, or a Makefile switch. Triggers on "run e2e with…
- [mui-autocomplete-freesolo-ghost-text](mui-autocomplete-freesolo-ghost-text/SKILL.md) — Use when a MUI Autocomplete in freeSolo mode needs inline typeahead and the native autoComplete or autoHighlight props do nothing, or when completed text concatenates onto what the user typed instead…
- [parser-library-preference](parser-library-preference/SKILL.md) — Use when a CI gate, validation script, or config check reads YAML, JSON, TOML, or XML with `grep`, `sed`, or hand-written regex. Triggers on fail-open gate bugs, quoted or escaped keys, spaced colons…
- [rca-component-structuring](rca-component-structuring/SKILL.md) — Use when writing a new React UI component or growing an existing one and the rust-code-analysis complexity gate must pass first time — symptoms include the metrics target mapped by `make.lint_metrics…
- [react-ref-callback-cleanup](react-ref-callback-cleanup/SKILL.md) — Use when a React 19 component forwards a ref and also uses it internally — a ref-merge helper, a `React.RefCallback` built with useCallback, or an effect that writes the forwarded ref — and a consume…
- [shared-module-extraction](shared-module-extraction/SKILL.md) — Use when a duplication gate flags cloned component code — a jscpd failure, a qlty `similar-code` comment, or two components differing only in a path, a viewBox, or a stroke width — and the fix is to…
- [uri-path-validation-normalization](uri-path-validation-normalization/SKILL.md) — Use when code decides whether a request URI or a configured file path is allowed — extension allow-lists, directory allow-lists, edge/CDN request handlers, service workers, or a gate that asserts a s…

### Quality tooling (qlty, ESLint, editorconfig, metrics)

- [editorconfig-cyrillic-triage](editorconfig-cyrillic-triage/SKILL.md) — Use when a reviewer, bot, or editorconfig-checker reports a line over max_line_length while Prettier reports the file as formatted, and the line contains Cyrillic or other multi-byte UTF-8 text — Ukr…
- [eslint-config-parity-check](eslint-config-parity-check/SKILL.md) — Use when changing ESLint configuration rather than code — dropping or replacing a shared preset, migrating to flat config, upgrading eslint or a plugin major, consolidating rules into an inline rules…
- [figma-design-review-before-code](figma-design-review-before-code/SKILL.md) — Use when a component's Figma design must be reviewed BEFORE any code exists — a new UI component, a design handoff, a spec artifact, or a request to review a design against the existing components. S…
- [lint-rule-pattern-verification](lint-rule-pattern-verification/SKILL.md) — Use when a gate matches source with a regex or an AST selector — a check script under `scripts/ci/`, an esquery `no-restricted-syntax` entry, a drift guard that greps source for a helper call — and i…
- [performance-budget-calibration](performance-budget-calibration/SKILL.md) — Use when a byte budget is calibrated against the wrong unit and therefore cannot fire — setting or reviewing a Lighthouse `resource-summary` script or total size assertion, a gzip entrypoint or per-c…
- [qlty-eslint-runtime-mismatch](qlty-eslint-runtime-mismatch/SKILL.md) — Use when a Qlty check is red with "Build errored. Check the log for more information." and the cloud build log ends in linter stderr rather than findings — an ESLint version banner followed by "Error…
- [qlty-local-check-ts-sandbox-false-positive](qlty-local-check-ts-sandbox-false-positive/SKILL.md) — Use when a local `qlty check` reports a "Parsing error" naming TS5012 — cannot read the tsconfig.json under .qlty/cache/tools/eslint/\<version\>/ — on TypeScript files that pass in CI, when a newly a…
- [qlty-transient-build-error](qlty-transient-build-error/SKILL.md) — Use when a Qlty check reports state failure with "Build errored. Check the log for more information." while its inline analysis comment reports no findings or "All good", every other check is green,…
- [two-colour-focus-ring](two-colour-focus-ring/SKILL.md) — Use when a keyboard focus indicator disappears on some states — a ring invisible on a selected or filled element but fine at rest, a ring clipped by a scrolling container, or a focus style being desi…

### CI, Docker and GitHub workflow

- [adding-ci-gates](adding-ci-gates/SKILL.md) — Use when adding new CI checks or gates to a repository — batching several gate tickets onto one branch, deciding whether a gate ships now or is deferred, re-checking a gate design against the live ma…
- [batch-implementation-triage](batch-implementation-triage/SKILL.md) — Use when a list of open GitHub issues has to be filtered before automated or batch implementation — separating issues already landed on main, issues an open pull request already claims, issues whose…
- [ci-infrastructure-failure-diagnosis](ci-infrastructure-failure-diagnosis/SKILL.md) — Use when a CI job fails for infrastructure reasons rather than code — a sandbox or deploy check dying in a cloud pipeline-start call, "PR number extraction failed", cloud-credential configuration aut…
- [ci-infrastructure-refactoring](ci-infrastructure-refactoring/SKILL.md) — Use when refactoring how CI executes rather than what it checks — moving a gate between host and container, changing compose service orchestration, altering how a workflow invokes a make target, or a…
- [ci-single-check-validation](ci-single-check-validation/SKILL.md) — Use when exactly one CI check on a pull request is red while the rest are green — a code-quality or code-scanning check, one Playwright shard, one lint or mutation job — and the failure looks transie…
- [codeql-cache-corruption](codeql-cache-corruption/SKILL.md) — Use when a CodeQL analysis step fails with "Invalid checksum for page N of the compressed relation ... The database is corrupt and should be re-created", when one branch reddens the security-testing…
- [dependency-cve-gate](dependency-cve-gate/SKILL.md) — Use when a dependency-CVE gate fails a pull request, when adding or renewing an entry in an osv-scanner ignore policy, or when designing, reviewing or porting such a gate. Triggers include "CVE gate"…
- [dependency-upgrade-troubleshooting](dependency-upgrade-troubleshooting/SKILL.md) — Use when a dependency bump reddens CI rather than the code — Playwright reporting "Executable doesn't exist at", a Stryker shard dying with MODULE_NOT_FOUND on `testEnvironment`, dozens of visual sna…
- [docker-dev-rebuild-after-migration](docker-dev-rebuild-after-migration/SKILL.md) — Use when the dev container behaves as though it is running older code after a Dockerfile, base image, Node version or package-manager change — "command not found" or exit 127 for a tool the Dockerfil…
- [github-actions-workflow-authoring](github-actions-workflow-authoring/SKILL.md) — Use when a GitHub Actions workflow carries an `on.pull_request.paths` or `on.push.paths` filter and the gate can skip itself — a required check reporting success with zero jobs executed, review feedb…
- [github-pr-merge-readiness-audit](github-pr-merge-readiness-audit/SKILL.md) — Use when deciding whether one or several open pull requests can merge — a PR shows green checks but will not merge, an AI reviewer approval was dismissed after a merge commit, an approval sits on a s…
- [github-pr-workflow-approval-gate](github-pr-workflow-approval-gate/SKILL.md) — Use when a pull request will not merge although no check has failed, a workflow run sits in `action_required` or shows as waiting for approval, required checks never report at all after a push, or th…
- [husky-pre-commit-bypass](husky-pre-commit-bypass/SKILL.md) — Use when a Husky hook drags files the change never touched into a commit or rejects it for unrelated code — a `.husky/pre-commit` running the repository formatter followed by `git add -A`, `git statu…
- [make-target-maintenance](make-target-maintenance/SKILL.md) — Use when a Makefile target and its coverage manifest have drifted apart — the `bats` check failing with a `diff` between the Makefile target list and the target column of `tests/bats/make-target-cove…
- [rsbuild-dev-server-containerized-ci](rsbuild-dev-server-containerized-ci/SKILL.md) — Use when a containerized dev server becomes unreachable through its published Docker port — every job that starts the dev container fails at the start-container step, a wait-for-dev healthcheck loop…
- [shell-command-verification-robustness](shell-command-verification-robustness/SKILL.md) — Use when writing or reviewing a gate that greps source, docs, or workflows for command invocations — a Bats make-target coverage contract, a doc-references linter, a reachability check over `make \<t…

### Pull requests and AI reviewers

- [pr-batch-merge-validation](pr-batch-merge-validation/SKILL.md) — Use when several open pull requests are queued to land and the question is which of them can go in together. Triggers on stale branches behind `main`, "does this batch conflict?", a clean local merge…
- [retriggering-ai-reviews](retriggering-ai-reviews/SKILL.md) — Use when a pull request has no CodeRabbit, cubic, or Qodo review after a push, a bot replies that the review was rate limited, that the review limit was reached, that the review was skipped because t…
- [review-thread-resolution-workflow](review-thread-resolution-workflow/SKILL.md) — Use when a pull request carries many open review threads from several reviewers (CodeRabbit, cubic, qlty, humans) and they need to be answered and resolved — including deciding when to resolve, what…

<!-- technique-library:end -->

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
API-mock-backed E2E debugging path, and the `quality.coverage_statements` floor (default `100`,
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
(floor `95`) and `quality.lighthouse_mobile` (floor `85`) gates.

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
