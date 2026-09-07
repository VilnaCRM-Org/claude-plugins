---
name: depcruise-rule-alternative-disjointness
description: >-
  Use when an architecture rule is written as several alternatives that must each be provable — a
  dependency-cruiser rule in `.dependency-cruiser.js`, or an esquery `no-restricted-syntax` union of
  import shapes — and a must-fail fixture for one alternative still passes after that alternative is
  deleted, or two rules fire on the same fixture and the rule-rot guard reports an overlap.
---

# Dependency-cruiser rule alternative disjointness

## Profile keys consumed

- `make.lint_deps`
- `make.lint_eslint`
- `quality.depcruise_violations`

The dependency-cruiser rules run through the target mapped by `make.lint_deps` and the esquery
selector union through `make.lint_eslint`; skip the dependent half with a recorded note when either
maps to `null`. `quality.depcruise_violations` is the ceiling those rules are held to — raise-only,
never relaxed to clear a finding.

## Overview

A rule built from several alternatives is only verifiable if the alternatives match disjoint sets.
When one alternative is a superset of another, removing the subset changes no behaviour, no fixture
can pin it, and it can rot into a dead selector while the rule still looks healthy.

## When to use

- Adding an alternative to a forbidden rule or to a `no-restricted-syntax` selector union.
- A fixture-based rule-rot guard reports that a rule fired on a fixture it does not own.
- A selector was edited and every fixture still passes — suspect a broader sibling covering for it.
- Not for: a single-alternative rule; one fixture already pins it.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — 49 rules in `.dependency-cruiser.js` pinned by
  `scripts/ci/depcruise-rule-fixtures.mjs`, `scripts/ci/cruise-depcruise-fixtures.mjs` and
  `tests/unit/tooling/depcruise-rules.test.ts`; the esquery selector union lives in
  `config/di-collaborator-policy.js` with fixtures in `scripts/ci/eslint-gate-fixtures.mjs`.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial —
  `.dependency-cruiser.js` and a mapped `make.lint_deps` target exist with far fewer rules and no
  fixture guard; the disjointness rule applies to any rule added there.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — same,
  `.dependency-cruiser.js` plus a mapped `make.lint_deps` target, no fixture guard.

## Core pattern

An import declaration creates a runtime edge in exactly four shapes. Written naively, the
side-effect branch swallows the other three:

```js
// Overlapping — a bare "no named specifier" also matches default and namespace imports,
// so neither of those branches can be pinned by a fixture.
':has(ImportDefaultSpecifier)',
':has(ImportNamespaceSpecifier)',
":has(ImportSpecifier[importKind!='type'])",
':not(:has(ImportSpecifier))',
```

Narrow the catch-all by excluding what the earlier alternatives already claim:

```js
const SIDE_EFFECT_IMPORT = [
  ':not(:has(ImportSpecifier))',
  ':not(:has(ImportDefaultSpecifier))',
  ':not(:has(ImportNamespaceSpecifier))',
].join('');
```

Now each alternative owns one spelling — `import x from`, `import * as x from`, `import { x } from`,
`import 'y'` — so deleting any one makes its fixture pass when it must fail.

## Verification checklist

- Each alternative matches a disjoint set; a later alternative negates every earlier one it would
  otherwise contain.
- Deleting any single alternative makes at least one must-fail fixture stop failing.
- At least two fixtures per alternative, one per context the selector must work in (for the import
  union: a project-relative specifier and a third-party library specifier).
- Rules that genuinely co-fire because one is a strict subset of another are listed in the guard's
  documented-overlap map, in both the fixture file and the test — two reviewed edits, so padding one
  to hide a regression is visible.
- The guard asserts completeness in both directions: every rule has a fixture, and every fixture
  names a live rule.

## Gotchas

- The dependency-cruiser programmatic `cruise()` API returns zero violations unless called with
  `validate: true`; without it the whole guard passes vacuously.
- Strip `tsConfig` from the fixture cruise options so no path alias resolves out of the sandbox into
  real source, and give every fixture file an edge so it does not trip the orphan rule.
- An esquery attribute regex is delimited by `/`, so encode a literal slash inside the pattern as
  its Unicode escape rather than a backslash escape, whose handling is not contractual.
- The fixtures prove each rule still _fires_; they do not prove its exemption clauses still exempt.
  A weakened `pathNot` is caught only if it leaks into another fixture.

## Common mistakes

- Adding a broad alternative "to be safe" and leaving the narrow ones unobservable.
- Writing one fixture per rule instead of one per alternative, so a partial regression stays green.
- Widening the documented-overlap map to clear a failure instead of restoring disjointness.
- Landing a new rule with no fixture — the completeness assertion has no exemption list, so add the
  fixture in the same change rather than as a follow-up.
