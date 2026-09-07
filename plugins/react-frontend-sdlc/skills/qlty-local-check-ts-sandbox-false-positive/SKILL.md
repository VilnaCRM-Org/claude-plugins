---
name: qlty-local-check-ts-sandbox-false-positive
description: >-
  Use when a local `qlty check` reports a "Parsing error" naming TS5012 — cannot read the
  tsconfig.json under .qlty/cache/tools/eslint/<version>/ — on TypeScript files that pass in CI,
  when a newly added .ts/.tsx test appears broken only locally, or when qlty flags untracked scratch
  files as unformatted.
---

# Local qlty check TS5012 sandbox false positive

## Profile keys consumed

- `make.lint_tsc`
- `make.lint_eslint`
- `architecture.source_root`

## Overview

`qlty check` copies `eslint.config.mjs` into its own tool cache before running it. A config that
derives its tsconfig path from `import.meta.url` therefore resolves it against the cache directory
instead of the repository root, and the TypeScript parser reports `TS5012` on every file it lints.
CI runs ESLint from the repository root, so the same files pass there.

## When to use

- Local `qlty check` prints `TS5012` for a tsconfig path under the qlty tool cache.
- A file that lints, type-checks and tests clean in CI "fails" only under the local qlty run.
- Untracked scratch files (agent working directories, local notes) show up as unformatted.
- Not for: a red Qlty status in CI — that is either a runtime-version mismatch or a cloud outage,
  and both are diagnosed from the cloud build log.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — `eslint.config.mjs` computes `rootDir` from `fileURLToPath(import.meta.url)` and
  joins `tsconfig.json` onto it, which is exactly the shape that mis-resolves in the sandbox.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial — the diagnosis no
  longer reproduces; the config already sets `tsconfigRootDir: process.cwd()`, which is the fix
  below.
- **Component-library shape** (Storybook-first, no bootable app, published package): yes — same
  `import.meta.url`-derived `tsconfigPath` in `eslint.config.mjs`.

## Prove it is the sandbox before touching the file

Run the same local command against a pre-existing TypeScript suite that is green in CI. An identical
`TS5012` means the new file is not the cause:

```bash
qlty check "$(git ls-files 'tests/**/*.test.ts' | head -1)"
```

A file with no syntax error that passes lint, type-check and tests in CI is not broken. Editing it
to satisfy a sandbox artifact changes working code for no defect.

## Root-cause fix: resolve tsconfig from the working directory

The parser option that decides this is `tsconfigRootDir`. Anchoring it to the process working
directory — lint is always invoked from the repository root — survives being copied into a cache
directory, while `import.meta.url` does not. The `files` glob below is written against
`architecture.source_root`:

```ts
{
  files: ['src/**/*.{ts,tsx}'],
  languageOptions: {
    parser: '@typescript-eslint/parser',
    parserOptions: {
      project: './tsconfig.json',
      tsconfigRootDir: process.cwd(),
      sourceType: 'module',
    },
  },
}
```

The same reasoning applies to any other value the config derives from its own file location: a
literal, or a working-directory-relative path, is portable; a `__dirname`-style derivation is not.

## Until the config is fixed

Get the authoritative local signal from the repository's own gates rather than through qlty: the
target mapped by `make.lint_tsc` in all three shapes, plus the target mapped by `make.lint_eslint`
(in the Next.js and component-library shapes that key resolves to the framework-native lint target).
Skip either with a recorded note when the key maps to `null`. Untracked scratch files never reach a
pull request, so qlty formatting findings on them carry no information.

## Common mistakes

- "Fixing" a file whose only failure is the sandbox parse error — reproduce against a known-green
  file first.
- Reading `TS5012` as a tsconfig-content problem — the path is wrong, not the file.
- Assuming the local run and the cloud run share a resolution model — they do not; treat the cloud
  build log as the authority for a red check.
