---
name: storybook-visual-state-nested-props
description: >-
  Use when a Storybook-driven screenshot test configures component state through `&args=` in the
  story URL and the state never applies — the story renders with default props, the recorded
  baseline looks like the rest state, or the arg targets a prop nested inside an array or object
  such as `actions[0].pressed`. Covers args that are silently ignored, not filters or stale renders.
---

# Storybook visual state via nested props

## Profile keys consumed

- `capabilities.storybook`
- `capabilities.visual_testing`
- `make.test_visual`
- `quality.visual_diffs`

## Overview

Storybook's URL-arg resolver handles flat props and top-level dot paths only. An arg aimed at an
array index or a deep object path is ignored silently — no error, no warning — so the screenshot
captures the default render while the test still reports success. Configure such states in a
dedicated story instead of in the URL.

## When to use

- A visual state test sets a prop through `?args=` or a query arg and the render never changes.
- The baseline recorded for a new state is indistinguishable from the rest-state baseline.
- The prop being set lives inside an array element or a nested object.
- A screenshot test passes but nobody can point at the state it is supposed to prove.
- Not for: stale renders from a hot-reloading dev server, diffs caused by animation and font
  loading, or a missing baseline because a title filter selected no test — none of those are
  arg-resolution problems.

## Applicability gate

This needs both a story surface and a screenshot suite. Skip with a recorded note when
`capabilities.storybook` is `false` (no stories to point a spec at) or when
`capabilities.visual_testing` is `false`; when the target mapped by `make.test_visual` is `null`,
skip the baseline-regeneration step with a recorded note and verify the story render in a browser
instead.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): partial — Storybook is configured and the repository's visual-baseline update target
  regenerates baselines, but the visual specs screenshot the running app, so this applies only to
  story-driven specs added there.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial — per-component
  stories exist, while the visual specs target the production app; the rule applies to any
  story-driven screenshot added alongside them.
- **Component-library shape** (Storybook-first, no bootable app, published package): yes — the
  states spec drives Storybook through `/iframe.html`, and the targets mapped by `make.test_visual`
  plus the repository's visual-baseline update target run and refresh the chromium baselines.

## Core pattern

Bake the nested value into a named story, then point the test at that story id:

```ts
// component.stories.tsx — dedicated state story, nested prop set in args
export const EyePressed: Story = {
  args: { label: BAR_LABEL, actions: PRESSED_ACTIONS },
  render: renderWired,
};
```

```ts
// tests/visual/states.spec.ts — the story id carries the state; no args needed
test('icon bar eye pressed', async ({ page }) => {
  await openStory(page, 'uicomponents-uiactioniconbar--eye-pressed');
  await shoot(page, 'icon-bar-eye-pressed.png');
});
```

Reserve `&args=` for flat, top-level scalars. Anything structural belongs in the story.

## Procedure

1. Open the story id in a browser (`/iframe.html?id=<id>&viewMode=story`) and confirm the intended
   state is actually rendered before recording anything.
2. If it is not, add a story whose `args` contain the fully built nested value, named for the state.
3. Repoint the spec at the new story id and drop the arg from the URL.
4. Regenerate the baseline with the repository's visual-baseline update target, then inspect the
   written PNG — the file must show the state, not the rest appearance.

   ```bash # profile-example
   # With a profile whose visual-baseline update target is `test-visual-update`:
   make test-visual-update
   ```

5. Leave a one-line note in the spec saying why the state comes from a story, so the arg is not
   reintroduced later.

## Common mistakes

- Trusting a green run as proof the state applied — a default render can sit inside the diff
  tolerance and pass forever.
- Deepening the arg path (`actions.0.pressed`, `actions[0][pressed]`) instead of moving the value
  into the story; the resolver supports none of those shapes.
- Recording the baseline before opening the story in a browser, which freezes the wrong appearance
  as the reference.
- Raising the allowed diff ratio when the state screenshot looks wrong — fix the story, the
  tolerance is not the problem. `quality.visual_diffs` is a ceiling of `0`, never a dial.
- Reusing one story for many states with args, so a single missed arg silently degrades several
  baselines at once.
