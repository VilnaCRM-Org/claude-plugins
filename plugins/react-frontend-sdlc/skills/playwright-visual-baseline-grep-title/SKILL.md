---
name: playwright-visual-baseline-grep-title
description: Use when a Playwright run filtered with -g / --grep exits 0 but an expected visual baseline PNG was never written, when a snapshot filter has to match a title containing spaces or a separator, or when regenerating a subset of visual baselines.
---

# Playwright visual baseline grep title

## Profile keys consumed

- `make.test_visual`
- `make.start_prod`
- `make.storybook_build`
- `capabilities.visual_testing`
- `capabilities.storybook`
- `quality.visual_diffs`

Every suite runs through the profile's `make` target map. Skip this skill with
a recorded note when `capabilities.visual_testing` is `false` or
`make.test_visual` maps to `null`; the baseline-update target has no profile
key, so resolve the repository's visual-baseline update target from its
Makefile and record which target you ran.

## Overview

Playwright's `-g` / `--grep` filter is a regular expression matched against a test's full title as
printed in the report — never against the file path, the Storybook story id, or the snapshot
filename. A filter that matches fewer tests than intended simply runs fewer tests, and tests that
did not run cannot fail, so a green exit code is not evidence that a baseline was captured.

## When to use

- A baseline regeneration reported success but the expected `*-snapshots/*.png` file is absent.
- The filter string is a slug (`figma-parity`) while the printed title reads as prose
  (`Figma parity`) or carries a separator between story title and story name.
- Only part of a visual suite needs re-recording and the rest of the baselines must not move — the
  `quality.visual_diffs` ceiling is `0`, so unrelated drift is a failure, not noise.
- Not for: a snapshot that was written but differs from the committed one — that is a real visual
  diff, and the report shows it.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — the repository's visual-baseline update target re-records the Playwright suite
  under the root `tests/visual` tree; a subset run means invoking Playwright inside the test
  stack's container (booted through `make.start_prod`) with the filter.
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — the same
  visual-baseline update target drives the Playwright visual suite, which lives under a source-tree
  visual directory rather than a root `tests/` tree.
- **Component-library shape** (Storybook-first, no bootable app, published package): yes — highest
  exposure, because the visual spec derives each test title from the Storybook story title and
  story name, so almost every title contains spaces and a separator.

## Procedure

1. Print the titles the filter selects before recording anything. `--list` resolves the same filter
   the run would use and writes nothing. Run it where the suite runs — inside the Playwright
   container for the React SPA and Next.js shapes, and under the Storybook harness built by
   `make.storybook_build` for the component-library shape:

   ```bash # profile-example
   playwright test tests/visual --list -g 'Figma parity'
   ```

2. Confirm the count matches the number of baselines expected. Zero or fewer than expected means the
   expression is wrong, not that the work is done.

3. Record with the same filter, then verify against the working tree rather than the exit code. The
   pathspec needs the trailing `/*` and `-uall`, or git reports the whole new snapshot directory as
   one untracked entry — or nothing at all:

   ```bash # profile-example
   playwright test tests/visual --update-snapshots -g 'Figma parity'
   git status --porcelain -uall -- '*-snapshots/*'
   ```

4. If an expected PNG is missing, widen or correct the expression — anchor on a distinctive word
   rather than the whole title, and remember the expression is a regex, so a literal separator or
   parenthesis needs escaping.

5. Commit only the baselines the change is meant to move; an unfiltered re-record rewrites every
   snapshot in the suite and buries the real diff.

## Filter facts worth remembering

- The match target is the joined title path, so a `describe` block's text is part of what `-g` sees,
  and matching on the describe text alone selects every test inside it.
- When `toHaveScreenshot()` is called with no explicit name, the filename is derived from the title,
  so a renamed test orphans its old PNG and silently records a new one on the next update run.
- A filter that selects a subset exits 0 for the tests that ran. Only a run matching nothing at all
  reports an empty selection, and `--pass-with-no-tests` — which the component-library shape's
  target mapped by `make.test_visual` passes — suppresses even that.

## Common mistakes

- Reading exit 0 as "the baseline was captured" — check the PNG exists on disk before believing it.
- Verifying with a `*-snapshots` pathspec — it matches the directory name and therefore no file at
  all; the PNGs live one level below, so use `*-snapshots/*` with `-uall`.
- Filtering with the story id, the kebab-case file name, or the snapshot name — the matcher sees
  only the joined title path, so filter on a distinctive word from the printed title.
- Re-recording the whole suite to work around a filter that did not match — fix the expression, or
  the unrelated drift is buried in the diff.
- Deleting a stale PNG and re-running without a filter — first check whether the test title was
  renamed, which is the usual cause of a missing baseline.
