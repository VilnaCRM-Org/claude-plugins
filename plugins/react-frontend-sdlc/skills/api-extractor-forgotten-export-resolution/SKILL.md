---
name: api-extractor-forgotten-export-resolution
description: >-
  Use when a library build prints `Warning: (ae-forgotten-export) The symbol "X" needs to be
  exported by the entry point`, when a published `.d.ts` rollup shows props as `any` or as an
  opaque generated alias, or when adding a component whose prop type is declared in a sibling
  `types.ts` and must reach the package entry point.
---

# API Extractor forgotten-export resolution

## Profile keys consumed

- `make.build`
- `architecture.source_root`

## Overview

`ae-forgotten-export` means a type is reachable from an exported component's public API but is not
re-exported at the entry point that API Extractor rolls up. The rollup then invents a local alias,
so consumers lose the real type. The fix is always a source-side `export` plus a barrel re-export —
never an edit to a generated declaration file.

## When to use

- A build prints one or more `(ae-forgotten-export)` warnings and you need them at zero.
- A consumer's IDE resolves a component prop to `any` or to a name the package never documented.
- A new component's props type lives in its own `types.ts` and has not been threaded to the barrel.
- Not for: silencing the warning through API Extractor `messages` log levels, or hand-editing the
  generated `.d.ts` under the temp declaration directory.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): no — no api-extractor config present.
- **Next.js app shape** (routed pages, no aggregate duplication gate): no — no api-extractor config
  present.
- **Component-library shape** (Storybook-first, no bootable app, published package): yes — an
  `api-extractor.json` rolls the temp declaration directory's component index up into the published
  `build/index.d.ts`; the build config runs the extractor during the target mapped by `make.build`
  (skip with a recorded note when it maps to `null`), and the repository's declaration-rollup target
  runs the extractor on its own. The entry barrel is the components index under
  `architecture.source_root`.

  ```bash # profile-example
  # In a component library whose declaration-rollup target is `generate-ts-doc`:
  make generate-ts-doc   # runs: api-extractor run --local --verbose
  ```

## Procedure

1. **Collect** every warned symbol from the build output together with the component that pulls it
   into the public surface.
2. **Locate the declaration.** Most sit in that component's `types.ts`; some are imported from a
   shared types module or from a sibling component's `types.ts`.
3. **Choose the export route.**
   - Declared locally: add `export` at the declaration, then add the name to that component's
     `export type { … } from './<dir>/types';` line in the entry barrel.
   - Imported from elsewhere: make sure the intermediate module re-exports it, then add it to the
     entry barrel's type line for the component that surfaces it.
4. **Trace the whole chain** before rebuilding — source declaration → owning `types.ts` → any
   intermediate re-export → entry barrel. A break anywhere leaves the warning.
5. **Iterate.** Each round can expose nested symbols that only became reachable once the previous
   round exported their parent. Rebuild until the extractor reports zero `ae-forgotten-export`
   warnings and exits `0`.

## Worked chain

A heading-level union declared in a card item's `types.ts` is imported by a card list's `types.ts`
and used in its public props. Exporting it at the declaration is not enough: the card list must
re-export it, and the entry barrel's type line for the card list must name it. A shared asset type
imported two levels deep needs the same treatment — the barrel names it under the component that
actually exposes it, not under the module it was declared in.

## Common mistakes

- Editing the generated declaration files in the temp rollup directory — they are regenerated on
  every build; edit sources.
- Exporting internal helper or debug types to clear a warning — those types belong to an internal
  child signature, so keep them off the barrel and export only what a consumer can observe.
- Creating a re-export loop between two component barrels to satisfy a chain — thread the name
  through the entry barrel instead.
- Stopping after one clean round: nested symbols surface only after their parent is exported.
- Lowering an extractor message log level so the warning disappears; the type is still missing from
  the rollup.
