---
name: deferred-di-reflect-metadata-optimization
description: >-
  Use when a tsyringe application loads its DI container behind a dynamic `import()` and the eager
  entry bundle still pulls in `reflect-metadata`, or when a mobile Lighthouse performance budget is
  short by a few hundredths. Symptoms include `import 'reflect-metadata';` on the first line of the
  client entry alongside a composition root that already imports it, and a bundle report showing the
  shim on the critical render path.
---

# Deferred DI Reflect-Metadata Optimization

## Profile keys consumed

- `make.build`
- `make.lighthouse_mobile`
- `make.test_unit_client`
- `quality.lighthouse_mobile`
- `capabilities.lighthouse`
- `framework.di`
- `framework.bundler`

Every command runs through the profile's `make` target map. Skip the audit step with a recorded
capability-absent note when `capabilities.lighthouse` is `false` or `make.lighthouse_mobile` maps to
`null`; the whole skill is inapplicable when `framework.di` names no container.

## Overview

With a deferred composition root — the container and the decorated classes loaded behind a dynamic
`import()` on first use — the eager `reflect-metadata` import in the client entry is redundant. The
composition root pulls it in when the deferred chunk loads, so removing it takes roughly 16 KB gzip
off the critical render path for no behavioural change.

## When to use

- The client entry begins with `import 'reflect-metadata';` and the DI composition root imports it
  too.
- A mobile Lighthouse performance budget is failing by a small margin and the eager entrypoint needs
  to shrink.
- Auditing what the initial chunk contains and finding decorator-metadata support that nothing on
  the paint path uses.
- Not for: applications whose entry file, or anything it statically imports, defines or instantiates
  a decorated class — there the eager import is load-bearing.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — `src/config/dependency-injection-config.ts` imports `reflect-metadata` on its first
  line, `src/index.tsx` does not, and the contract is pinned by
  `tests/unit/performance/public-index.test.js` under the target mapped by `make.test_unit_client`;
  the mobile budget it protects lives in `lighthouse/lighthouserc.mobile.js` and is enforced through
  `make.lighthouse_mobile` against `quality.lighthouse_mobile`.
- **Next.js app shape** (routed pages, no aggregate duplication gate): no — no DI container
  (`framework.di` is absent).
- **Component-library shape** (Storybook-first, no bootable app, published package): no — no DI
  container.

## Preconditions

Check all three before removing the import:

1. The composition root loads the container dynamically (a `load()` method or equivalent behind
   `await import(...)`), so the container is not on the eager graph.
2. The composition root's own module imports `reflect-metadata` before touching the container.
3. Nothing in the entry file's **static** import closure declares or constructs a decorated class.
   Walk the closure; a single `@injectable()` reached eagerly makes the entry import necessary.

## Core pattern

Delete the entry-file import, then pin the contract so it cannot come back:

```js
it('keeps dependency injection metadata out of the client entry bundle', () => {
  const entrySource = fs.readFileSync(path.resolve(__dirname, '../../../src/index.tsx'), 'utf8');

  expect(entrySource).not.toContain("import '@/config/dependency-injection-config';");
  expect(entrySource).not.toContain("import 'reflect-metadata';");
});
```

Asserting the composition-root import as well as the shim matters: re-adding either one puts the
container back on the eager graph, and the second is the more common regression because it looks
like an ordinary module import.

## Verification

- Rebuild through the target mapped by `make.build` and read the bundle report the configured
  bundler (`framework.bundler`) emits: the entrypoint should shrink by about 16 KB gzip, and the
  metadata shim should no longer appear in the initial chunk.
- Run the mobile Lighthouse audit through the target mapped by `make.lighthouse_mobile`; the
  measured lift is roughly +0.03 on the performance category. Skip this step with a recorded note
  when `capabilities.lighthouse` is `false`.
- Exercise a flow that resolves from the container so the deferred chunk actually loads, and confirm
  decorator resolution still works at runtime rather than only at build time.
- Never bank the saving by lowering `quality.lighthouse_mobile` — the budgets ratchet one way.

## Common mistakes

- Removing the import without walking the static closure — a decorated class reached eagerly then
  throws on first resolution, and only at runtime.
- Pinning only the shim and not the composition-root import — the container returns through the
  other door.
- Assuming the saving without a bundle report — the number depends on what else the entry pulls in.
- Applying this where the container is imported eagerly — the deferred composition root is the whole
  precondition, not an implementation detail.
