---
name: storybook-dev-server-visual-test-staleness
description: >-
  Use when a committed Playwright screenshot baseline shows an outdated render — wrong language, old
  design, a state the component no longer produces — while the visual suite still reports green, or
  when regenerating snapshots does not rewrite a baseline that is obviously wrong. Applies to
  toHaveScreenshot against a Storybook or app dev server with hot module replacement, and to any
  visual config carrying a maxDiffPixelRatio or maxDiffPixels tolerance.
---

# Stale visual baselines from a dev server

## Profile keys consumed

- `capabilities.visual_testing`
- `make.test_visual`
- `capabilities.storybook`
- `make.storybook_build`
- `framework.package_manager`

The visual suite runs through the target mapped by `make.test_visual`; skip the whole skill with a
recorded capability-absent note when `capabilities.visual_testing` is `false` or `make.test_visual`
maps to `null`. The static Storybook build comes from the target mapped by `make.storybook_build`
(skip with a recorded note when it maps to `null`), and the story build command is invoked through
the runner named by `framework.package_manager`. Baseline regeneration has no logical key: use the
repository's visual-baseline update target.

## Overview

A dev server applies hot-module updates asynchronously. `toHaveScreenshot` captures the first stable
layout, which can be the pre-update frame, while a settled `page.screenshot` catches the live
render. A pixel tolerance then hides the gap, so the suite passes against a wrong baseline and
`--update-snapshots` never rewrites it. Screenshot a **static build**, with no tolerance.

## When to use

- A baseline image disagrees with what the story or page renders in a browser, yet the suite is
  green.
- Re-running with `--update-snapshots` leaves a known-wrong baseline untouched.
- A visual project points Playwright at a hot-reloading dev server.
- Not for: genuine cross-platform font or renderer diffs, which are solved by pinning the browser
  image, not by changing how the app is served.

## Applicability by repository shape

- **Component-library shape** (Storybook-first, no bootable app, published package): yes — the specs
  under `tests/visual/` screenshot Storybook stories; the compose `storybook` service already builds
  static and serves the output directory, and the specs carry no diff tolerance. The targets mapped
  by `make.test_visual` and the repository's visual-baseline update target drive it.
- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): partial — visual specs target the app, not Storybook, but the same rule is encoded there
  as separate non-gating dev-mode snapshots under `tests/visual/__snapshots__-dev/`; only the
  production build produces authoritative baselines.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial — visual specs under
  `src/test/visual` target the app; Storybook is built in its own workflow and never screenshotted.

## Procedure

1. **Confirm the drift.** Open the story or page against a settled render and compare it with the
   committed baseline. If the two disagree while the suite is green, the tolerance is masking a
   stale image, not absorbing noise.
2. **Serve a build, not a dev server.** Build the static output once and serve that directory on the
   port Playwright targets. This is what the component-library shape's compose service does.

   ```bash # profile-example
   bun x storybook build --output-dir storybook-static --quiet
   python3 -m http.server 6006 --bind 0.0.0.0 --directory storybook-static
   ```

3. **Keep the comparison exact.** A static build renders deterministically, so no
   `maxDiffPixelRatio` or `maxDiffPixels` is needed; carrying one only lets the next stale baseline
   pass. Reach for determinism helpers instead of tolerance.
4. **Freeze the frame** before every shot — emulate `reducedMotion: 'reduce'`, inject a stylesheet
   that disables `animation`, `transition`, `scroll-behavior` and the text caret, wait for the story
   root to be visible, and await `document.fonts.ready`.
5. **Pin one engine.** Pixel baselines are environment-locked; generate them on the same Linux
   browser image CI uses and skip the other projects in the visual spec.
6. **Regenerate only after verifying the live render**, then review every changed image before
   committing. Regeneration runs inside the browser container, so bind-mount the test directory into
   it or the rewritten baselines never reach the working tree. Re-baselining to turn a red suite
   green is how the drift started.

## Cost and trade-offs

- Adds a build step (roughly one to two minutes) to each visual run.
- Live editing during a visual run is gone, which is correct — a visual suite freezes a design.
- A lossless image-recompression bot may rewrite committed PNG files; pixel content is unchanged, so
  baselines stay valid.

## Common mistakes

- Widening the diff tolerance when a shot fails — that is the mechanism that hid the stale baseline.
- Trusting a green visual suite as proof the baseline is correct; it only proves the shot matched
  the image on disk.
- Comparing with `page.screenshot` in a probe and concluding the baseline is fine — the probe
  settles and the assertion does not, which is exactly the discrepancy to chase.
- Serving the build from a still-running dev server container, so the old bundle is what gets shot.
