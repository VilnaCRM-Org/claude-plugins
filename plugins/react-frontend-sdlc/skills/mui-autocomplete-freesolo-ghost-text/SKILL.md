---
name: mui-autocomplete-freesolo-ghost-text
description: >-
  Use when a MUI Autocomplete in freeSolo mode needs inline typeahead and the native autoComplete or
  autoHighlight props do nothing, or when completed text concatenates onto what the user typed
  instead of replacing it. Also for search, select, or multi-select combobox fields that must show a
  grey inline suggestion after the caret, and for sharing that ghost-text behaviour across sibling
  Autocomplete-based components.
---

# MUI Autocomplete freeSolo ghost text

## Profile keys consumed

- `framework.ui`
- `architecture.source_root`

This pattern applies when `framework.ui` is Material UI; the shared field module it produces lives
under `architecture.source_root`.

## Overview

`freeSolo` bypasses MUI's internal autocomplete machinery, so `autoComplete` and `autoHighlight`
never complete and can concatenate the suggestion into the value. The working pattern is a purely
visual, `aria-hidden` overlay — the input value stays exactly what the user typed, and the grey
completion is drawn on a layer above it.

## When to use

- A `freeSolo` Autocomplete must show a typeahead suggestion inline in the field.
- Text jumps or doubles as the user types into a `freeSolo` field.
- A second Autocomplete-based field needs the same affordance and the logic is still local to the
  first one.
- Not for: non-`freeSolo` Autocompletes, where the native props work, or dropdown-only highlighting
  that never renders inside the input.

## Applicability by repository shape

- **Component-library shape** (Storybook-first, no bootable app, published package): yes — MUI 9;
  the shared implementation lives under the source root at `components/field-controls`
  (`ghost-overlay.tsx`, `ghost-completion.ts`) and is consumed by the search, select and
  multi-select fields.
- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): partial — MUI 7 is present but no Autocomplete ships today; the pattern transfers
  unchanged, minus the shared `field-controls` module.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial — MUI 9 is present
  but no Autocomplete ships today; same caveat as the React SPA shape.

## Core pattern

The overlay is a sibling of the field inside a positioned wrapper. It renders two runs — a
**transparent mirror** of the typed text and the **grey completion** after it — so the completion
starts exactly where the real text ends.

```ts
const overlaySx = {
  position: 'absolute',
  top: 0,
  left: 0,
  display: 'flex',
  alignItems: 'center',
  gap: '2px', // room for the input's own native caret
  pointerEvents: 'none',
};

// forcedColorAdjust keeps the mirror transparent in Windows High Contrast,
// where `color: transparent` is otherwise forced opaque and doubles the text.
const typedRunSx = { whiteSpace: 'pre', color: 'transparent', forcedColorAdjust: 'none' };
const ghostRunSx = {
  whiteSpace: 'pre',
  color: palette.grey300.main,
  '@media (forced-colors: active)': { color: 'GrayText' },
};
```

Rules that make it hold together:

- **Do not draw a custom caret.** Leave a small gap and let the input keep its own native caret; a
  hand-drawn line renders inconsistently across browsers and devices.
- **Copy the computed type off the real input** (family, size, weight, line-height, letter-spacing)
  in a layout effect, so the mirror is exactly as wide as the typed text in whichever field hosts
  the overlay.
- **Measure the input's text start, not its border box** — add its `padding-left`, or a field that
  insets its input (a multi-select with chips) pushes the completion under the last typed letters.
- **Re-sync on resize and whenever the completion changes**; a breakpoint can grow a leading
  adornment and move the input.
- Mark the overlay `aria-hidden="true"`. It is decoration; the value carries the meaning.
- Match case-insensitively but commit the **whole option in its canonical casing**, so typing a
  lowercase prefix yields the properly cased option.
- Accept on Tab (never Shift+Tab, which must still move focus backward) or on ArrowRight when the
  selection is collapsed at the end of the value.

## Extraction and reuse

Once a second Autocomplete field needs the affordance, move the overlay component, the
prefix-completion helpers and the accept-key predicate into a shared field module and compose them
per field. Keep the per-field state (value, suggestions, focus) in the consuming component so each
field's ghost updates independently.

Build it test-first: the overlay is stateful across typing, selection, blur and focus, and the
failure modes (a doubled value, a misaligned mirror, a corrupted accessible name) are all invisible
in a static screenshot.

## Common mistakes

- Reaching for `autoComplete` or `autoHighlight` again on a `freeSolo` field — they do nothing.
- Writing the completion into the input value; that is the concatenation bug.
- Positioning the overlay against MUI's own input ref instead of a wrapper that both share.
- Leaving the overlay readable by assistive technology, which duplicates the field's text.
- Accepting the completion on Shift+Tab, which steals the backward focus move.
