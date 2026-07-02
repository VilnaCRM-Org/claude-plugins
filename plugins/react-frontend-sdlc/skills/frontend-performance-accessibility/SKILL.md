---
name: frontend-performance-accessibility
description: Hold a React frontend to its Lighthouse performance budgets (desktop 95 / mobile 85, integer-percent floors mapped by quality.lighthouse_desktop and quality.lighthouse_mobile), keep web-vitals, bundle size, and code-splitting healthy, defend deferred-DI render paths, and meet WCAG 2.2 AA accessibility — pairing with the accessibility-audit skill and the accessibility-lead agent team. Use when improving frontend performance, Lighthouse scores, web-vitals, bundle or code-split cost, render-path / deferred-DI work, or accessibility.
---

# Frontend Performance & Accessibility

Lab performance and accessibility are one skill because they share the same surface:
the rendered route the user actually receives. This skill keeps that route fast (the
Lighthouse budgets, web-vitals, bundle/code-split cost, and deferred-DI render paths)
**and** operable for everyone (WCAG 2.2 AA). Both are non-negotiable gates in the
review and QA stages — a design match never waives either.

## Profile keys consumed

- `capabilities.lighthouse`
- `capabilities.accessibility_audit`
- `capabilities.dynamic_a11y_testing`
- `capabilities.visual_testing`
- `capabilities.memory_leak_testing`
- `make.lighthouse_desktop`
- `make.lighthouse_mobile`
- `make.build`
- `make.start_prod`
- `make.test_visual`
- `make.test_unit_client`
- `make.test_e2e`
- `make.test_memory_leak`
- `make.lint_eslint`
- `make.a11y`
- `quality.lighthouse_desktop`
- `quality.lighthouse_mobile`
- `quality.visual_diffs`
- `framework.ui`
- `framework.bundler`
- `framework.package_manager`
- `framework.router`
- `framework.i18n`
- `framework.di`
- `architecture.source_root`
- `architecture.component_prefix`
- `architecture.path_aliases`

Every audit runs through the profile's `make` target map — never a raw host
invocation of the bundler, the auditor, or a browser. A `null` mapping means the
capability is absent: skip or degrade with an explicit note (generic tooling like
`gh`, `git`, and the project package manager mapped by `framework.package_manager`
may still be invoked directly when needed).

## What this skill covers (and what it defers)

- **In scope:** Lighthouse desktop/mobile budgets, Core Web Vitals (LCP, CLS, INP)
  reasoning, bundle size and code-splitting, deferred-DI / container-free render
  paths, layout-shift avoidance, and WCAG 2.2 AA accessibility of the rendered UI.
- **Deferred — runtime telemetry / RUM:** wiring `web-vitals` and error reporting to
  a live monitoring sink is the
  [observability-instrumentation](../observability-instrumentation/SKILL.md) skill.
  Here, `web-vitals` is a *lab reasoning lens*, not a production sink.
- **Deferred — load under concurrency:** page behavior under many virtual users is the
  [load-testing](../load-testing/SKILL.md) skill (k6, production build). This skill is
  the *single-user lab budget*, not the load profile.
- **Deferred — deep a11y verdicts:** authoritative per-family WCAG findings come from
  the [accessibility-audit](../accessibility-audit/SKILL.md) skill and its
  `accessibility-auditor` agent. This skill is the build-time checklist that keeps the
  audit clean; it does not replace the audit.

## Lighthouse capability gate

The lab-performance lane is gated by `capabilities.lighthouse`. When it is `false`,
or when both `make.lighthouse_desktop` and `make.lighthouse_mobile` are `null`,
record a capability-absent note and skip the audit — never improvise a raw host
Lighthouse run against a repository that does not declare the capability:

```text
SKIPPED: Lighthouse not configured for this project (capabilities.lighthouse=false)
```

The skip is bounded to the lab-performance lane. It does **not** waive the
accessibility lane (`make.a11y` / the `accessibility-auditor` agent) or the
visual-regression lane (`make.test_visual`), which run regardless. No quality
threshold is weakened by the skip.

## Performance budgets and the Lighthouse lane

When `capabilities.lighthouse` is `true`, run the two audits through their mapped
targets and read the category scores:

```bash # profile-example
make lighthouse-desktop   # make.lighthouse_desktop
make lighthouse-mobile    # make.lighthouse_mobile
```

The Lighthouse category score is a **0..1 fraction**; the profile floors are the
same number expressed as integer percent and are read **raise-only**:

| Profile floor                | Shipped default | Fraction | As integer percent |
| ---------------------------- | --------------- | -------- | ------------------ |
| `quality.lighthouse_desktop` | `0.95`          | ≥ 0.95   | ≥ 95               |
| `quality.lighthouse_mobile`  | `0.85`          | ≥ 0.85   | ≥ 85               |

Mobile is the binding budget: it runs throttled CPU/network, so a change that passes
desktop can still sink the mobile floor. The **CI score is the one that counts** —
local numbers vary with the host; treat the audit mapped by `make.lighthouse_mobile`
as the contract and reproduce a regression there, not on a warm local run.

A profile may **raise** a floor above the default (a repo that already clears 90 on
mobile may pin `quality.lighthouse_mobile: 0.90`); it may never lower it. If a change
drops the score below the floor, fix the cause — never edit the floor down. Lighthouse
also surfaces accessibility and best-practice findings; route a11y findings into the
accessibility lane below rather than treating the Lighthouse a11y sub-score as the
authoritative WCAG verdict.

## Web-vitals and Core Web Vitals

Use the three field-aligned signals to localize *why* a budget moved, before reaching
for a fix:

- **LCP (loading)** — how fast the main content paints. Driven by the critical-path
  bytes of the first route: render-blocking CSS/JS, oversized hero media, and chunks
  pulled into first paint that the route does not need yet.
- **CLS (stability)** — visual stability. Driven by content that arrives late and
  reflows: unreserved space for dynamic labels, counters, skeletons, fonts, and
  loading/disabled state swaps. Reserve dimensions so the swap does not move layout.
- **INP (responsiveness)** — interaction latency. Driven by long tasks on the main
  thread: heavy synchronous work in event handlers or render, large hydration cost.

`web-vitals` is the runtime lens for these signals; emitting them to a dashboard is the
[observability-instrumentation](../observability-instrumentation/SKILL.md) skill. For
local validation, pair code review with the Lighthouse lane and the visual lane
(`make.test_visual`) — a CLS regression usually shows up as a visual diff first.

## Bundle size and code-splitting

The first route should download only what it needs to paint. Keep the critical path
lean regardless of the bundler mapped by `framework.bundler` (e.g. `rsbuild`, `next`,
`vite`):

- **Route-split by default.** Lazy-load routes the entry does not paint, so a heavy
  feature module under `architecture.source_root` is fetched on navigation, not at
  boot. Split by the router surface (`framework.router`, e.g. `react-router-v6`).
- **Keep heavy libraries off the first paint.** A GraphQL client, a validation library,
  the DI framework (`framework.di`), and large UI subtrees belong behind a dynamic
  `import()` on the path that first uses them, not in the entry chunk.
- **Measure before abstracting.** Use the build mapped by `make.build` (and its bundle
  analyzer variant, when the repo exposes one) to confirm a chunk's real cost before
  splitting; do not guess. Split where the analyzer shows mass, not on intuition.
- **Watch the styling layer.** A CSS-in-JS UI (`framework.ui`, e.g. Material UI v7 +
  Emotion) ships runtime styling; import components and icons by path so unused
  surface is tree-shaken instead of pulling the whole library into first paint.

## Deferred-DI and render-path performance

The most effective lever for a route on a tight mobile budget (e.g. an auth/sign-in
page) is keeping its first paint **container-free**: the DI framework
(`framework.di`), the data client, validators, and the repositories they wire must not
be in the chunk that paints the page. Defer them behind a dynamic `import()` in a thin
composition root so they load on the first user action, not on load:

```typescript
// composition root — loads the DI container + heavy actions only on first use
private async load(): Promise<StoreActions> {
  const { default: container } = await import('@/config/di-container');
  const { default: ActionsClass } = await import('./store-actions');
  return container.resolve(ActionsClass);
}
```

Supporting patterns for the render path:

- **Container-free reactive state on the paint path.** State primitives the first paint
  reads should be plain instance singletons (a reactive-var class exported as a module
  singleton), so no DI framework is pulled into the auth/landing chunk. Resolve the
  path aliases (`architecture.path_aliases`) rather than deep relative chains.
- **Do not eager-import the lazy subtree.** A statically imported "lazy" form section
  defeats the split — verify the heavy child is reached only through `import()` / a
  lazy boundary, never a top-level import.
- **Keep heavy computation out of render.** Hoist expensive work out of the render path;
  memoize only when a measurement or the code shape shows repeated cost, not by reflex.
- **Watch for leaks on long-lived routes.** When `capabilities.memory_leak_testing` is
  true, a route that mounts/unmounts repeatedly (or holds subscriptions) is checked
  through the target mapped by `make.test_memory_leak`; a retained-heap growth is a
  performance regression, not noise.

## Accessibility — WCAG 2.2 AA

Accessibility is a build-time obligation on every UI change, not a later audit step.
Prefer semantic, native, and accessible-by-default primitives from the UI layer
(`framework.ui`) before reaching for ARIA. Run this checklist as you build, then let
the audit verify it:

- [ ] Every button, link, field, dialog, and icon-only control has an accessible name
      (the localized label via `framework.i18n`, never a raw key or a transparent
      label that drops the name from the accessibility tree).
- [ ] Inputs are labeled and their errors are programmatically associated to the field;
      `aria-busy` / a polite `role="status"` announces async/submitting state.
- [ ] Dialogs trap focus, expose a title, restore focus on close, and close on `Esc`.
- [ ] Keyboard operability is complete — tab order, focus-visible state, menus,
      forms, and **client-side route changes** (focus management + a route
      announcement when `framework.router` drives navigation).
- [ ] Color contrast meets AA on text, icons, focus rings, and disabled/grey states;
      the contrast comes from the theme/token source, not per-component overrides.
- [ ] Layout stays stable for assistive tech: no content that appears/disappears
      without an announcement; `<html lang>` matches the rendered language
      (`framework.i18n`). Note: a Cyrillic-default `lang` can shift visual baselines —
      coordinate any `lang` change with a visual-baseline refresh.
- [ ] Source ships **no `data-testid`**: tests and audits locate elements by
      user-facing semantics (role, label, text), which keeps a11y coverage honest.

Static enforcement (jsx-a11y rules, semantic-HTML and ARIA-pattern checks) runs through
`make.lint_eslint` and the bundled a11y lane (`make.a11y`, or its static fallback when
`null`). This is the build-time floor; the deep verdict comes from the audit below.

## Pairing with the accessibility-audit skill and the accessibility-lead team

This skill is the *producer* of accessible UI; the
[accessibility-audit](../accessibility-audit/SKILL.md) skill is the *verifier*. The two
pair as follows:

- The audit fans out one `accessibility-auditor` agent per WCAG 2.2 family, probing the
  running stack (axe-core, keyboard-only navigation, accessible-name/role queries) and
  inspecting the JSX/ARIA source. **Dynamic** (live-browser) probing is gated by
  `capabilities.dynamic_a11y_testing`; when it is `false` or `make.a11y` is `null`,
  dynamic probing is `SKIPPED:` with a note and the **static** lane still runs, so every
  family still gets a verdict. The static lane is itself gated by
  `capabilities.accessibility_audit` for its bundled axe/ARIA tooling, with the
  source-level JSX/ARIA inspection always running.
- Technique-level remediation guidance (per-family WCAG patterns, screen-reader test
  procedures, ARIA-pattern fixes) draws on the companion accessibility-lead agent team
  documented for this plugin; consult it when a finding needs a cited fix rather than a
  guess.
- Verified findings are reported, never silently fixed by the auditor: they route to the
  `react-implementer` agent with a failing-then-passing regression test (an axe / role +
  accessible-name assertion). Bring the fix back through this skill's render rules — do
  not satisfy a finding by adding a `data-testid` hook or suppressing the lint rule.

## Verification

Run the subset that matches the change, each through the profile's `make` map, then
finish with the project formatter followed by the lint suite:

```bash # profile-example
make test-unit-client     # make.test_unit_client — component + hook behavior
make test-e2e             # make.test_e2e — user flows incl. keyboard paths
make test-visual          # make.test_visual — layout-shift / contrast regressions
make lighthouse-desktop   # make.lighthouse_desktop
make lighthouse-mobile    # make.lighthouse_mobile — the binding budget
make a11y                 # make.a11y — static + (gated) dynamic a11y lane
```

Then verify the gates landed clean:

- [ ] Lighthouse desktop ≥ `quality.lighthouse_desktop`, mobile ≥
      `quality.lighthouse_mobile` (CI scores, raise-only — never lowered).
- [ ] Visual diffs at `quality.visual_diffs` (0) — no unexplained layout shift.
- [ ] Accessibility lane clean: every WCAG family CLEAN or N/A-with-reason, zero
      verified findings open; no `data-testid` introduced.
- [ ] Critical-path bundle unchanged or smaller; heavy deps stay behind `import()`.
- [ ] `web-vitals` reasoning recorded for any LCP/CLS/INP-affecting change.

## Constraints

- **Thresholds are raise-only floors / fixed ceilings.** `quality.lighthouse_desktop`
  and `quality.lighthouse_mobile` may only be raised; `quality.visual_diffs` is fixed at
  0. Never edit a floor down or a ceiling up to make a run pass — fix the cause.
- **No suppression.** No `eslint-disable`, `@ts-ignore`, ARIA-rule silencing, or
  visual/Lighthouse-budget exclusions to dodge a finding. Satisfy every gate by
  refactoring the code, never by lowering the bar.
- **A design or Figma match never waives a gate.** Visual parity does not exempt the
  accessibility lane, the visual-regression lane, or the performance budgets.
- **Performance and a11y are co-equal.** A speed change that regresses a WCAG family is
  not done; an a11y fix that adds critical-path weight needs the same budget check.
- **Disclosure:** before presenting changes, report any changed line over 100
  characters as `path:line` with its measured length — disclosure, not failure, unless
  a project gate fails on it.

## Related skills

- [accessibility-audit](../accessibility-audit/SKILL.md) — authoritative per-family
  WCAG 2.2 verdicts via the `accessibility-auditor` agent (verifier to this producer).
- [observability-instrumentation](../observability-instrumentation/SKILL.md) — wiring
  `web-vitals` and error reporting to a live RUM sink (runtime, not lab).
- [load-testing](../load-testing/SKILL.md) — page behavior under concurrent virtual
  users (the load profile, distinct from this single-user lab budget).
- [frontend-testing-workflow](../frontend-testing-workflow/SKILL.md) — Jest, Testing
  Library, Playwright E2E/visual, and the role/label selectors that keep a11y honest.
- [ci-workflow](../ci-workflow/SKILL.md) — how the performance, visual, and a11y lanes
  fit the overall CI verification suite.
