---
name: mutation-test-barrel-import-trap
description: Use when one test suite re-runs for mutants in unrelated components and the mutation gate times out or drags, or when a source module imports from an aggregate barrel such as the components index (`@/components`) instead of the target component's own entry.
---

# Mutation test barrel import trap

## Profile keys consumed

- `make.test_mutation`
- `make.lint_deps`
- `capabilities.mutation_testing`
- `architecture.source_root`
- `architecture.path_aliases`

Every command resolves through the profile's `make` target map. Skip this
skill with a recorded note when `capabilities.mutation_testing` is `false` or
`make.test_mutation` maps to `null`.

## Overview

When Stryker's jest runner restricts each mutant to its related tests, the import graph decides the
cost. A source module that imports from the aggregate barrel is recorded as depending on every
export in it, so the suites covering that module become related to every component — and re-run for
every mutant in the repository.

## When to use

- A single suite appears in the run set for mutants that touch code it never exercises.
- A mutation shard takes hours, or times out, and the log shows the same suite reloading.
- A grep shows a component, service, or hook importing the aggregate components alias
  (`'@/components'`) rather than the per-component entry (`'@/components/<name>'`).
- Not for: a barrel import that the repository's public-API contract requires — see the sibling
  [mutation-gate-barrel-leaf-extraction skill](../mutation-gate-barrel-leaf-extraction/SKILL.md),
  which moves the shared leaf instead.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): partial — the Stryker config sets `jest.enableFindRelatedTests: true`, so the trap is
  real, but there is no aggregate components index and the dependency-cruiser gate mapped by
  `make.lint_deps` requires module and feature boundaries to be crossed through their barrels, so
  the remedy is leaf extraction, not a deeper import.
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — the components index
  is an aggregate barrel and `enableFindRelatedTests` is on, so an aggregate import inside the
  source root multiplies the related set directly.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — the
  aggregate barrel exists and the components public-API rule already permits the per-component
  entry, but `enableFindRelatedTests` is `false` today, so the cost is latent rather than active.

## Core pattern

The edge is usually one level below the slow suite: not in the test, but in the module it renders.
Both specifiers below use the alias declared in `architecture.path_aliases`:

```ts
// Before — one edge into the aggregate barrel makes this module related to every component.
import { UiTypography } from '@/components';

// After — the target component's own public entry, which the boundary rules already allow.
import UiTypography from '@/components/ui-typography';
```

The import form changes with the path: an aggregate barrel typically renames a default export into a
named one (`export { default as UiTypography } from './ui-typography'`), so read the target entry's
export shape instead of only swapping the specifier. Reaching past that entry into the component's
internals is a different violation and fails the public-API rule, so the per-component barrel is the
destination, not the file behind it. Check the other consumers of the same dependency and make the
import style consistent across all of them.

## Prevention

Add a fail-closed audit beside the other lint gates so a new aggregate import cannot land; only the
entry barrels are exempt, because re-exporting the aggregate surface is their job. Point the scan at
the tree named by `architecture.source_root`:

```bash # profile-example
if grep -rnE "(import|from|import\()[[:space:]]*['\"]@/components/?['\"]" src \
  --include='*.ts' --include='*.tsx' | grep -vE '^src/(components/)?index\.tsx?:'; then
  echo 'source modules must import a component through its own barrel'
  exit 1
fi
```

The alternation covers both quote styles, a dynamic `import('@/components')`, a trailing slash, and —
via the bare `import` alternative — a side-effect import (`import '@/components'`) that has neither a
`from` clause nor parentheses and would otherwise slip past the gate. The bare alternative adds no
false positives: `import('./foo')` and `import X from '@/components'` still match on their own
alternatives, and `import` immediately followed by the aggregate specifier is exactly the side-effect
form.
Re-check it against the spellings the codebase actually uses before trusting a clean run, and keep
the audit's own fixture coverage so it cannot pass vacuously.

## Common mistakes

- Fixing the test file's imports while the component it renders keeps the aggregate edge — follow
  the edge one level down into the rendered module.
- Replacing the aggregate import with a reach into another component's internals — stop at that
  component's public entry, or a performance fix becomes a boundary violation.
- Assuming file size explains the slow suite — measure reverse-dependency fan-out, which is what
  multiplies the related set.
- Shipping the audit without checking it matches every import spelling — exercise it against a known
  violation first, or it reports clean while the edge is still there.
