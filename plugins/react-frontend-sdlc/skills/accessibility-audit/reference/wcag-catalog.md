# WCAG 2.2 Family Catalog — dispatchable set, SC-mapped

This is the **single source of truth** for the `accessibility-audit` triage
table. The skill's Step 5.1 reads this file and records a per-family verdict —
**PROBE** or **N/A-with-reason** — for every family below; no family is silently
skipped (NFR-6). Probing methodology per family lives in
[`audit-playbooks.md`](audit-playbooks.md); the accessible-by-default fixes live
in [`remediation-patterns.md`](remediation-patterns.md). The loop that consumes
these verdicts is defined in [`../SKILL.md`](../SKILL.md).

The dispatchable set is exactly **18 families**, grouped by the four WCAG
principles (Perceivable, Operable, Understandable, Robust). Every cross-cutting
audit surface named in Step 5.1 is realized as one of these families:

- **forms** → `forms-labeling`
- **modals** → `modal-focus-trap`
- **keyboard** → `keyboard-operability`, `focus-order`, `focus-visible`
- **live-regions** → `live-regions`, `route-announcement`
- **contrast** → `contrast`
- **alt-text / headings** → `alt-text`, `headings-structure`
- **links** → `link-purpose`
- **tables** → `tables-structure`

Every path, module, component family, and lane resolves from the project profile
(`architecture.source_root`, `architecture.component_prefix`, `framework.ui`,
`framework.router`, `framework.i18n`, and the `make.*` targets) — never from
source-project literals (NFR-4). Where this catalog needs to name the audited
code it says "the module the story names" or `architecture.source_root`, not a
concrete directory.

## How to read this catalog

Each family block carries:

- a **family id** (the dispatch key — one `accessibility-auditor` subagent per
  PROBE family);
- the **WCAG 2.2 Success Criteria** it covers, each with its **level** (A / AA)
  and a one-line **what it checks**;
- an **N/A predicate** — the condition under which the family is recorded
  N/A-with-reason and excluded before fan-out (NFR-8 cost gate);
- a **primary evidence** note — whether the family is provable by in-tree static
  demonstration (§5.3 static-determinable classes) or needs the running stack.

Two rules govern the verdict, both from [`../SKILL.md`](../SKILL.md):

- **N/A is recorded, never silent.** A family whose *surface* is absent on the
  target (no meaningful image → `alt-text` N/A; no `<audio>` / `<video>` →
  `media-captions` N/A; no data table → `tables-structure` N/A; `framework.router`
  unset → `route-announcement` N/A) gets an explicit N/A-with-reason and is not
  dispatched (NFR-6, NFR-8).
- **A capability-gated lane is degraded with its gate reason, not dropped.** When
  a family's only proof needs live-browser rendering and
  `capabilities.dynamic_a11y_testing` is `false` (or `make.start` is null / the
  stack is unreachable), the dynamic probe is recorded `SKIPPED:` with that gate
  reason; the static lane (the jsx-a11y / ARIA rules run via the target mapped by
  `make.lint_eslint`, plus semantic-HTML / ARIA-pattern inspection over
  `architecture.source_root`) still runs so the family keeps an explicit verdict
  (NFR-6). Build-mode-sensitive families additionally cross-check against the
  production-parity build (the target mapped by `make.start_prod`) before
  reporting CLEAN or promoting a finding.

**Allowed profile keys referenced below** (the only dotted keys this catalog
uses): `framework.router`, `framework.i18n`, `framework.ui`,
`architecture.source_root`, `architecture.component_prefix`,
`capabilities.dynamic_a11y_testing`, `make.start`, `make.start_prod`,
`make.test_visual`, `make.lint_eslint`.

New-in-2.2 criteria are labelled inline. WCAG 2.2 **removed 4.1.1 Parsing**;
malformed-markup barriers now map to 4.1.2, tracked under `aria-roles-props`.

## Perceivable

### alt-text

Text alternatives for non-text content.

| SC | Level | What it checks |
| --- | --- | --- |
| 1.1.1 Non-text Content | A | Every meaningful image / icon / SVG / `role="img"` has an equivalent text alternative; decorative graphics are empty-`alt` or `aria-hidden`. |
| 1.4.5 Images of Text | AA | Text is real text, not a rasterized image, unless the presentation is essential (e.g. a logo). |

**N/A predicate:** surface — the target renders no meaningful non-text content
(text-only view, every graphic provably decorative); the static lane still
confirms decorative graphics are hidden.
**Primary evidence:** static-determinable in-tree — a missing or wrong `alt` on a
meaningful image is demonstrable directly in the JSX under
`architecture.source_root`.

### headings-structure

Heading hierarchy, landmarks, document outline, reading order, and cross-view
navigation consistency.

| SC | Level | What it checks |
| --- | --- | --- |
| 1.3.1 Info and Relationships | A | Structure conveyed visually (headings, lists, landmark regions) is exposed programmatically. |
| 1.3.2 Meaningful Sequence | A | DOM / reading order matches the intended visual reading order. |
| 2.4.5 Multiple Ways | AA | More than one way to locate a view (navigation, search, sitemap) is available. |
| 2.4.6 Headings and Labels | AA | Headings and labels describe their topic or purpose. |
| 3.2.3 Consistent Navigation | AA | Repeated navigation appears in the same relative order across views. |
| 3.2.6 Consistent Help | A (new in 2.2) | Any help mechanism appears in a consistent relative location across views. |

**N/A predicate:** never fully N/A for a rendered view (every document has a
heading / landmark structure); 2.4.5 is N/A for a single-view target and 3.2.6 is
N/A when no help mechanism exists (surface).
**Primary evidence:** static-determinable in-tree (heading levels, landmark
elements) plus the rendered accessibility-tree outline.

### contrast

Color / contrast and presentation that must not depend on a single sensory
characteristic.

| SC | Level | What it checks |
| --- | --- | --- |
| 1.4.1 Use of Color | A | Color is not the only means of conveying information (error, link, required, selected). |
| 1.3.3 Sensory Characteristics | A | Instructions do not rely solely on shape, size, position, or sound. |
| 1.4.3 Contrast (Minimum) | AA | Text vs background ≥ 4.5:1 (≥ 3:1 for large text). |
| 1.4.11 Non-text Contrast | AA | UI component boundaries, states, focus indicators, and meaningful graphics ≥ 3:1. |

**N/A predicate:** contrast ratios need computed styles → gated by
`capabilities.dynamic_a11y_testing`; when `false` (or `make.start` is null) the
rendered-DOM contrast probe is `SKIPPED:` with the gate reason and only the
color-token static heuristics run.
**Primary evidence:** dynamic — an axe-core contrast violation on the rendered
DOM (build-mode note applies; prefer the `make.start_prod` parity build).

### media-captions

Time-based media alternatives.

| SC | Level | What it checks |
| --- | --- | --- |
| 1.2.1 Audio-only and Video-only (Prerecorded) | A | An alternative is provided for audio-only and video-only media. |
| 1.2.2 Captions (Prerecorded) | A | Synchronized captions accompany prerecorded audio in video. |
| 1.2.3 Audio Description or Media Alternative (Prerecorded) | A | Audio description or a full text alternative is provided. |
| 1.2.4 Captions (Live) | AA | Captions accompany live audio content. |
| 1.2.5 Audio Description (Prerecorded) | AA | An audio-description track accompanies prerecorded video. |
| 1.4.2 Audio Control | A | Auto-playing audio longer than 3 s can be paused, stopped, or muted. |

**N/A predicate:** surface — no `<audio>`, `<video>`, or embedded media player on
the target → whole family N/A-with-reason, never dispatched (NFR-8).
**Primary evidence:** static — presence of a media element and its caption /
description / track association in the source.

### reflow-zoom

Responsive reflow, text resize, spacing, and orientation.

| SC | Level | What it checks |
| --- | --- | --- |
| 1.3.4 Orientation | AA | Content is not locked to a single display orientation. |
| 1.4.4 Resize Text | AA | Text scales to 200% without loss of content or function. |
| 1.4.10 Reflow | AA | No two-dimensional scrolling at 320 CSS px width / 400% zoom; content reflows to one column. |
| 1.4.12 Text Spacing | AA | No clipping or overlap when line-height, letter, word, and paragraph spacing are increased. |

**N/A predicate:** reflow / zoom need a rendered viewport → gated by
`capabilities.dynamic_a11y_testing`; when dynamic probing is off the family is
recorded `SKIPPED:` with the gate reason.
**Primary evidence:** dynamic — viewport resize / zoom on the booted stack;
prefer the `make.start_prod` parity build.

### tables-structure

Data-table semantics.

| SC | Level | What it checks |
| --- | --- | --- |
| 1.3.1 Info and Relationships | A | `<th>` with `scope`, a `<caption>`, and header/data association; ARIA `role="table"` / `grid` only when a native table cannot be used; no layout tables. |

**N/A predicate:** surface — no data `<table>` (nor ARIA `grid` / `treegrid`) on
the target → family N/A-with-reason when no tabular-data surface exists.
**Primary evidence:** static-determinable in-tree (table markup under
`architecture.source_root`) plus the rendered accessibility-tree.

## Operable

### keyboard-operability

Full keyboard operation of every control.

| SC | Level | What it checks |
| --- | --- | --- |
| 2.1.1 Keyboard | A | All functionality is operable via keyboard; no pointer-only interaction paths. |
| 2.1.2 No Keyboard Trap | A | Focus can move away from every component using standard keys. |
| 2.1.4 Character Key Shortcuts | A | Single-character shortcuts are remappable, focus-scoped, or toggleable. |
| 2.4.1 Bypass Blocks | A | A skip link or landmark bypasses repeated blocks of content. |

**N/A predicate:** keyboard traversal needs a rendered, focusable DOM → gated by
`capabilities.dynamic_a11y_testing` (plus `make.start`); when off, the
pointer-only-handler static heuristic (jsx-a11y `click-events-have-key-events`
via the target mapped by `make.lint_eslint`) runs and the live traversal is
`SKIPPED:` with the gate reason.
**Primary evidence:** dynamic — keyboard-only traversal of the running stack.

### focus-order

Focus sequence and focus-triggered context changes.

| SC | Level | What it checks |
| --- | --- | --- |
| 2.4.3 Focus Order | A | Focus sequence preserves meaning and operability; no positive `tabindex`. |
| 3.2.1 On Focus | A | Receiving focus does not trigger an unexpected change of context. |

**N/A predicate:** positive-`tabindex` and focus-triggered context changes are
static-determinable in-tree; the sequenced-order check needs rendering, so that
portion is gated by `capabilities.dynamic_a11y_testing`. Build-mode-sensitive — a
dev error overlay injects extra focusable nodes, so cross-check against the
`make.start_prod` parity build before reporting.
**Primary evidence:** static (positive `tabindex`) plus dynamic (rendered focus
sequence).

### focus-visible

Visibility of the keyboard focus indicator.

| SC | Level | What it checks |
| --- | --- | --- |
| 2.4.7 Focus Visible | AA | A visible focus indicator is present for every focusable control. |
| 2.4.11 Focus Not Obscured (Minimum) | AA (new in 2.2) | A focused control is not entirely hidden by sticky headers, overlays, or other author content. |

**N/A predicate:** the visible-outline and obscuring checks need computed styles
and layout → gated by `capabilities.dynamic_a11y_testing`; when off, only the
`outline: none`-without-replacement static heuristic runs and the rendered check
is `SKIPPED:` with the gate reason.
**Primary evidence:** dynamic — rendered focus ring and sticky-content overlap on
the running stack.

### modal-focus-trap

Dialogs, popovers, sheets, drawers, and hover/focus overlay content.

| SC | Level | What it checks |
| --- | --- | --- |
| 2.4.3 Focus Order | A | Focus moves into the dialog on open and is confined while it is open. |
| 2.1.2 No Keyboard Trap | A | The managed trap is escapable (Esc / close), not a dead end. |
| 4.1.2 Name, Role, Value | A | `role="dialog"` / `aria-modal` with an accessible name; focus returns to the invoker on close. |
| 1.4.13 Content on Hover or Focus | AA | Hover/focus popovers and tooltips are dismissable, hoverable, and persistent. |

**N/A predicate:** surface — no modal / dialog / popover / drawer / tooltip
overlay on the target → family N/A-with-reason. The trap and focus-return
behavior is gated by `capabilities.dynamic_a11y_testing`; the `role` / `aria-modal`
wiring is static-determinable in-tree.
**Primary evidence:** dynamic (open → trap → Esc → focus return) plus static ARIA
wiring.

### link-purpose

Descriptive link text.

| SC | Level | What it checks |
| --- | --- | --- |
| 2.4.4 Link Purpose (In Context) | A | Link text, with its programmatically-determined context, describes the destination; no bare "click here" / "read more" / "learn more". |

**N/A predicate:** surface — no hyperlinks or `role="link"` controls on the
target.
**Primary evidence:** largely static-determinable in-tree; the in-context
resolution (surrounding list item, cell, or `aria-labelledby`) may need the
rendered accessible name.

### target-size

Pointer input and pointer-target sizing.

| SC | Level | What it checks |
| --- | --- | --- |
| 2.5.1 Pointer Gestures | A | Multipoint or path-based gestures have a single-pointer alternative. |
| 2.5.2 Pointer Cancellation | A | The down-event does not complete the action; abort or undo is available on up-event. |
| 2.5.4 Motion Actuation | A | Device-motion-triggered actions have a UI-control alternative and can be disabled. |
| 2.5.7 Dragging Movements | AA (new in 2.2) | Drag operations have a single-pointer, non-drag alternative. |
| 2.5.8 Target Size (Minimum) | AA (new in 2.2) | Pointer targets are ≥ 24×24 CSS px, or meet the spacing / inline exception. |

**N/A predicate:** target size and hit-area need rendered geometry → gated by
`capabilities.dynamic_a11y_testing`; 2.5.1 / 2.5.4 / 2.5.7 are additionally N/A
when no gesture / motion / drag interaction exists (surface).
**Primary evidence:** dynamic — measured hit-area on the rendered DOM; prefer the
`make.start_prod` parity build.

### motion-reduced

Moving, flashing, auto-updating, and time-limited content.

| SC | Level | What it checks |
| --- | --- | --- |
| 2.2.1 Timing Adjustable | A | Time limits can be turned off, extended, or adjusted. |
| 2.2.2 Pause, Stop, Hide | A | Auto-moving, blinking, scrolling, or auto-updating content can be paused, stopped, or hidden. |
| 2.3.1 Three Flashes or Below Threshold | A | Nothing flashes more than three times per second. |
| 2.3.3 Animation from Interactions | AAA (advisory — the `prefers-reduced-motion` mechanism) | Non-essential motion triggered by interaction can be disabled. |

**N/A predicate:** surface — no animation, auto-updating region, carousel, or
time limit on the target → family N/A-with-reason. 2.3.3 is Level AAA and is
included only as the reduced-motion mechanism check; it is never a Level-AA
gating failure.
**Primary evidence:** dynamic — observed motion behavior and whether
`prefers-reduced-motion` is honored on the running stack.

### route-announcement

Client-side (SPA) route transitions.

| SC | Level | What it checks |
| --- | --- | --- |
| 2.4.2 Page Titled | A | Each route updates the document title to describe the view. |
| 2.4.3 Focus Order | A | On route change, focus moves to a sensible landmark / heading, not lost to `<body>`. |
| 4.1.3 Status Messages | AA | The route change is announced via a polite live region without destructively stealing focus. |

**N/A predicate:** `framework.router` unset → no client-side route transitions →
family N/A-with-reason, never dispatched (Step 5.1). When a router is present the
dynamic route-change focus / announcement check is gated by
`capabilities.dynamic_a11y_testing` (plus `make.start`). Build-mode-sensitive —
StrictMode double-invoke can duplicate announcements, so verify on the
`make.start_prod` parity build.
**Primary evidence:** dynamic — navigate, then assert focus target and
live-region announcement.

## Understandable

### forms-labeling

Form controls, labels, instructions, errors, input purpose, and authentication.

| SC | Level | What it checks |
| --- | --- | --- |
| 1.3.1 Info and Relationships | A | Control↔label and fieldset / legend groupings are exposed programmatically. |
| 1.3.5 Identify Input Purpose | AA | Common inputs carry the correct `autocomplete` token. |
| 3.2.2 On Input | A | Changing a control does not cause an unexpected change of context. |
| 3.3.1 Error Identification | A | Errors are identified in text and programmatically associated with the field. |
| 3.3.2 Labels or Instructions | A | Every control has a persistent label or instruction. |
| 3.3.3 Error Suggestion | AA | A correction suggestion is offered when one is known. |
| 3.3.4 Error Prevention (Legal, Financial, Data) | AA | Consequential submissions are reversible, checked, or confirmed. |
| 3.3.7 Redundant Entry | A (new in 2.2) | Previously entered information is auto-populated or selectable, not re-typed. |
| 3.3.8 Accessible Authentication (Minimum) | AA (new in 2.2) | No cognitive-function test without an alternative; paste into fields is allowed. |
| 4.1.2 Name, Role, Value | A | Each control exposes the correct name, role, state, and value. |

**N/A predicate:** surface — no form / input / `role`-widget on the target →
family N/A-with-reason; 3.3.4 / 3.3.8 are additionally N/A when no legal /
financial / data-changing or authentication step exists (surface).
**Primary evidence:** static-determinable in-tree for label association (a control
with no associated label) plus dynamic for error announcement behavior.

### lang-attribute

Programmatic language of the page and its parts.

| SC | Level | What it checks |
| --- | --- | --- |
| 3.1.1 Language of Page | A | `<html lang>` is present and correct. |
| 3.1.2 Language of Parts | AA | Inline foreign-language passages carry their own `lang`. |

**N/A predicate:** the sink is `framework.i18n` — when set, verify `<html lang>`
tracks the active locale the library resolves; 3.1.2 is N/A when the target has
no mixed-language content (surface). Rarely fully N/A: every rendered document
needs a page `lang`. A missing or wrong `<html lang>` is static-determinable
in-tree. Note: a `lang` value perturbs font / CJK / Cyrillic shaping, so a `lang`
change is visual-sensitive and must be re-baselined through the target mapped by
`make.test_visual` — never waived.
**Primary evidence:** static (in-tree `lang`) plus dynamic (locale switch on the
running stack).

## Robust

### aria-roles-props

Roles, states, properties, and accessible names for custom widgets.

| SC | Level | What it checks |
| --- | --- | --- |
| 4.1.2 Name, Role, Value | A | Custom widgets expose a valid role, required ARIA properties, and current state; no invalid or abstract roles; no `aria-*` on unsupported elements. |
| 1.3.1 Info and Relationships | A | ARIA relationships (`aria-labelledby` / `describedby` / `controls` / `owns`) reference existing ids. |
| 2.5.3 Label in Name | A | The accessible name contains the visible label text. |
| 3.2.4 Consistent Identification | AA | Components with the same function are named and identified consistently. |

**N/A predicate:** never fully N/A for a rendered view with any interactive
component; a purely static text view reduces this family to the jsx-a11y / ARIA
static lane only. Much is static-determinable in-tree (a `role` missing a required
property; `aria-labelledby` pointing at a missing id); live state correctness
needs rendering. WCAG 2.2 removed 4.1.1 Parsing — malformed-markup findings map
to 4.1.2 here.
**Primary evidence:** static (jsx-a11y / ARIA rules via the target mapped by
`make.lint_eslint`) plus dynamic (accessibility-tree role / name / state).

### live-regions

Announcement of dynamic content that changes without a full reload (non-route).

| SC | Level | What it checks |
| --- | --- | --- |
| 4.1.3 Status Messages | AA | Status, results, toast, and validation-count changes are announced via `role="status"` / `aria-live` without moving focus. |

**N/A predicate:** surface — no content updates without a full reload (no async
results, toasts, counters, loading states) → family N/A-with-reason. Announcement
timing needs rendering → gated by `capabilities.dynamic_a11y_testing`.
Build-mode-sensitive — StrictMode can double-fire announcements, so verify on the
`make.start_prod` parity build.
**Primary evidence:** dynamic — trigger the update, then assert the live-region
announcement.

## Dispatchable family set (→ §5.1)

The skill's §5.1 fan-out table is the 18 rows below. Each family is dispatched as
one `accessibility-auditor` instance when its gate holds; N/A families are
recorded with a reason and never dispatched (NFR-6, NFR-8). A reusable
`architecture.component_prefix` primitive that emits the same barrier across many
views collapses to **one** finding at the component (§5.4 dedupe), not one per
view.

| Family | Principle | Primary SC(s) | Level span | Gate (profile key / surface) |
| --- | --- | --- | --- | --- |
| `alt-text` | Perceivable | 1.1.1, 1.4.5 | A–AA | surface: meaningful non-text content exists |
| `headings-structure` | Perceivable | 1.3.1, 1.3.2, 2.4.5, 2.4.6, 3.2.3, 3.2.6 | A–AA | always (rendered view) |
| `contrast` | Perceivable | 1.4.1, 1.3.3, 1.4.3, 1.4.11 | A–AA | dynamic ratios: `capabilities.dynamic_a11y_testing` |
| `media-captions` | Perceivable | 1.2.1–1.2.5, 1.4.2 | A–AA | surface: `<audio>` / `<video>` present |
| `reflow-zoom` | Perceivable | 1.3.4, 1.4.4, 1.4.10, 1.4.12 | AA | dynamic viewport: `capabilities.dynamic_a11y_testing` |
| `tables-structure` | Perceivable | 1.3.1 | A | surface: data `<table>` / ARIA grid present |
| `keyboard-operability` | Operable | 2.1.1, 2.1.2, 2.1.4, 2.4.1 | A | dynamic traversal: `capabilities.dynamic_a11y_testing` + `make.start` |
| `focus-order` | Operable | 2.4.3, 3.2.1 | A | static (positive `tabindex`); sequence: `capabilities.dynamic_a11y_testing` |
| `focus-visible` | Operable | 2.4.7, 2.4.11 | AA | dynamic styles: `capabilities.dynamic_a11y_testing` |
| `modal-focus-trap` | Operable | 2.4.3, 2.1.2, 4.1.2, 1.4.13 | A–AA | surface: overlay component present |
| `link-purpose` | Operable | 2.4.4 | A | surface: hyperlinks present |
| `target-size` | Operable | 2.5.1, 2.5.2, 2.5.4, 2.5.7, 2.5.8 | A–AA | dynamic geometry: `capabilities.dynamic_a11y_testing` |
| `motion-reduced` | Operable | 2.2.1, 2.2.2, 2.3.1 (+2.3.3 advisory) | A | surface: motion / auto-update / time limit present |
| `route-announcement` | Operable | 2.4.2, 2.4.3, 4.1.3 | A–AA | `framework.router` set + `capabilities.dynamic_a11y_testing` |
| `forms-labeling` | Understandable | 1.3.1, 1.3.5, 3.2.2, 3.3.1, 3.3.2, 3.3.3, 3.3.4, 3.3.7, 3.3.8, 4.1.2 | A–AA | surface: form / input present |
| `lang-attribute` | Understandable | 3.1.1, 3.1.2 | A–AA | sink: `framework.i18n`; 3.1.2 surface: mixed-language content |
| `aria-roles-props` | Robust | 4.1.2, 1.3.1, 2.5.3, 3.2.4 | A–AA | always (rendered view); static lane min via `make.lint_eslint` |
| `live-regions` | Robust | 4.1.3 | AA | surface: async content updates; timing: `capabilities.dynamic_a11y_testing` |

**Excluded before fan-out (NFR-8 cost gate), recorded N/A-with-reason:** any
family whose surface is absent on the target (no meaningful image, no media, no
data table, no overlay, no links, no form, no motion, and `route-announcement`
when `framework.router` is unset). **Degraded with a gate reason (not dropped,
NFR-6):** any dynamic-only lane when `capabilities.dynamic_a11y_testing` is
`false` or `make.start` is null — the static lane over `architecture.source_root`
still runs so every family keeps an explicit verdict.

## Gate precedence — a WCAG match never lowers another bar

A verified WCAG match, a CLEAN family verdict, or a passing accessibility fix is
**never** grounds to waive another gate. The visual-regression gate (the target
mapped by `make.test_visual`) and the performance floors (the Lighthouse
desktop / mobile budgets) hold independently: an accessible-by-default fix that
shifts rendered pixels must be re-baselined through `make.test_visual`, not
excused by its WCAG conformance, and a fix must not regress the performance
floors. These bars are raise-only; satisfy them by fixing the code, never by
suppression, baseline edit, or threshold relaxation.
