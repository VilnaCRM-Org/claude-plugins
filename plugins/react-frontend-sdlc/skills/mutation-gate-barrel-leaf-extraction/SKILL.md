---
name: mutation-gate-barrel-leaf-extraction
description: Use when a leaf helper — a style map, a predicate, or a formatting function — lives inside one component directory but is imported from other directories through that component's barrel, so the mutation runner's findRelatedTests pulls that component's whole suite set into every mutant run for the consuming files.
---

# Mutation gate barrel leaf extraction

## Profile keys consumed

- `make.test_mutation`
- `make.lint_tsc`
- `make.lint_deps`
- `make.storybook_build`
- `capabilities.mutation_testing`
- `capabilities.storybook`
- `architecture.source_root`
- `architecture.path_aliases`
- `framework.package_manager`

Every command resolves through the profile's `make` target map, and the
package runner comes from `framework.package_manager`. Skip this skill with a
recorded note when `capabilities.mutation_testing` is `false` or
`make.test_mutation` maps to `null`, and skip the Storybook verification step
with a note when `capabilities.storybook` is `false` or `make.storybook_build`
maps to `null`.

## Overview

Stryker's jest runner can restrict each mutant run to the tests related to the mutated file. A leaf
helper that lives inside a component directory and is consumed through that component's barrel makes
every consumer transitively related to the whole component graph, multiplying the suites each mutant
reloads. Moving the leaf to a shared `utils/` module under `architecture.source_root` restores a
precise related-test set.

## When to use

- A small style or predicate helper is exported from a component barrel and imported by components
  in other directories.
- `jest --findRelatedTests` on that helper lists the whole component's suites rather than its own
  consumers.
- A shard carrying those consuming files runs long, and the cause traces back to that one
  cross-directory leaf rather than to the shard's own file count.
- Not for: a slow shard whose files genuinely own many tests — that is a shard-count question, not
  an import-graph one. Not for a module importing an aggregate index instead of a component's own
  entry — that is the barrel-import trap, and no file needs to move.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — the Stryker config sets `jest.enableFindRelatedTests: true`, a shared `utils/`
  directory under the source root already holds leaf helpers, and the sharded mutation job runs
  under a 15-minute cap.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial —
  `enableFindRelatedTests` is on and the components directory ships an aggregate barrel, but the
  `mutate` list is a curated handful of files, so fan-out rarely dominates a shard.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — a
  shared `utils/dev-warn.ts` is the precedent and the components public-API rule does not govern
  the shared `utils` directory, but `enableFindRelatedTests` is currently `false`, so the saving
  only materialises once it is enabled.

## Procedure

1. Measure before changing anything, from inside the dev container, using the package runner
   resolved from `framework.package_manager` to list the suites related to the candidate file:

   ```bash # profile-example
   bun x jest --listTests --findRelatedTests src/components/<component>/<file>.tsx | wc -l
   ```

   Files with roughly thirty or more related suites are the candidates. File size is irrelevant
   here; reverse-dependency fan-out sets the per-mutant cost.

2. Confirm the helper qualifies. Move it only if all four hold: it is a leaf (no component state, no
   hooks, no MUI imports — pure styles, predicates, or formatting); it is consumed from outside its
   own component directory; consumers reach it through the component barrel rather than the file;
   and it is small and rarely edited.

3. Create `<source root>/utils/<name>.ts` with the helper and delete the copy under the components
   directory.

4. Re-export it from the component barrel so the published surface does not change:

   ```ts
   export { srOnlySx } from '../../utils/sr-only';
   ```

5. Point every consumer at the new module directly, using the alias declared in
   `architecture.path_aliases`, so the barrel edge disappears from the graph:

   ```ts
   import { srOnlySx } from '@/utils/sr-only';
   ```

6. Verify: the type-check mapped by `make.lint_tsc` and the dependency-cruiser gate mapped by
   `make.lint_deps` stay clean, the `--findRelatedTests` count drops, the build mapped by
   `make.storybook_build` still succeeds, and the shard timing improves.

## Limits

The extraction only pays when the helper sits on the critical path of a slow shard. A component file
that inherently owns twenty-five or more reverse-dependency suites stays expensive after the move;
that needs a packer that weights each file by related-suite cost rather than by byte size alone, or
more shards. Keep the re-export: dropping it is a public-API change disguised as a performance fix.

## Common mistakes

- Moving a helper that imports MUI or a hook — it is not a leaf and would drag the component graph
  into the shared `utils/` directory; leave it in the component directory and shard differently.
- Leaving consumers importing through the barrel after the move — repoint every consumer at the new
  module, or the exact edge the refactor targets survives.
- Raising the shard timeout instead of shrinking the related-suite set — keep the cap and shrink the
  fan-out; the cap is the tripwire for a return to full-suite reloading.
- Skipping the before/after `--findRelatedTests` count — record both, or there is no evidence the
  fan-out shrank.
