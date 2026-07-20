# Audit Playbooks — per-family probe + verify-by-reproduction

Per-family probing methodology each `accessibility-auditor` subagent executes
against an **authorized** React frontend the caller owns. One family per
dispatched subagent. The family set and its WCAG 2.2 Success-Criterion mappings
mirror the corpus in [wcag-catalog.md](wcag-catalog.md); the accessible-by-default
fix each finding cites lives in
[remediation-patterns.md](remediation-patterns.md). The loop that dispatches
these entries is described in [../SKILL.md](../SKILL.md).

**Authorized / defensive use only.** Every dynamic probe below drives ONLY the
profile-resolved local stack (the base URL of the `make.start`-booted stack,
verified loopback / private / container host). No exfiltration; interact via the
app's own UI only (keyboard / click / axe over the running page); container-only
execution (`make` / `docker compose exec`, never host binaries). A static
(jsx-a11y / axe) hit is a **candidate**, never a finding, until its reproduction
succeeds against the running stack OR it is deterministically demonstrated
in-tree for the static-determinable classes below — an un-reproduced candidate is
recorded downgraded/dropped, not reported.

## How to read an entry

Each family entry has the same shape:

- **WCAG 2.2** — the Success-Criterion id(s) + conformance level (A / AA) the
  family maps to (the authoritative mapping index; see
  [wcag-catalog.md](wcag-catalog.md)).
- **Static lane (candidate)** — the source-aware probe: the jsx-a11y / ARIA
  rules run via the target mapped by `make.lint_eslint`, the axe static-rule
  pass, and semantic-HTML + ARIA-pattern inspection over
  `architecture.source_root`. Output is a *candidate*, not a finding.
- **Static-determinable** — whether the barrier belongs to the in-tree class that
  needs no rendered styles (the JSX attribute is provably absent/malformed), or
  whether it needs the running stack to prove.
- **Dynamic lane** — the adversarial probe against the running DOM: axe-core on
  the rendered page, keyboard-only traversal, and accessibility-tree /
  accessible-name / role queries. Route-change focus + live-region checks apply
  **only when `framework.router` is set**.
- **Verify by reproduction** — the explicit step that promotes a candidate to a
  finding by demonstrating the barrier against a freshly booted stack, or (for a
  static-determinable class) by pointing at the absent/malformed attribute
  in-tree.

**Finding record (shared)** — every promoted finding carries the same fields:
`location` (`architecture.source_root`-relative `file:line` of the JSX/component
sink), the **WCAG SC id**, the **level** (A / AA), a **severity**
band-with-rationale (impact — does the barrier block task completion — × reach —
a shared `architecture.component_prefix` primitive vs a single view), the
**reproduction** steps, and a **remediation pointer** into
[remediation-patterns.md](remediation-patterns.md). Each entry names the SC,
level, and remediation pointer for its family; the field list is not repeated
per-entry.

**Build-mode caveat (shared)** — a dev-server build can **mask or inflate** a
dynamic result: a dev error overlay injects extra focusable nodes (a false
keyboard-order / focus finding), React StrictMode double-invokes and can
duplicate `id`s or live-region announcements, and dev-only attributes differ from
production output. Any family whose verdict depends on build-toggled rendered
output (focus order, live-region timing, duplicate-`id` ARIA, route announcement)
must cross-check against the production-parity build (the target mapped by
`make.start_prod`) before reporting CLEAN or promoting a finding, and must state
the build mode in its verdict. Each entry flags whether it is build-sensitive.

**Degrade (shared)** — when `capabilities.dynamic_a11y_testing` is false or
`make.start` is null, the orchestrator passes no base URL and only the static
lanes run. A static-determinable family stays promotable by in-tree
demonstration; a family that needs the running stack becomes a static-only
candidate recorded downgraded with the reason — never a fabricated finding. Each
entry states what survives degrade.

## Profile-resolved paths (no source-project literals)

Every path and surface below resolves from the profile, never a literal:
`<source_root>` = `architecture.source_root`; `<base_url>` = the dispatched
running-stack base URL (booted via `make.start`, or `make.start_prod` for the
authoritative pass); the component family prefix = `architecture.component_prefix`;
the UI kit whose accessible primitives a fix reaches for = `framework.ui`; the
SPA router whose navigations gate the route-announcement family =
`framework.router`; the localization layer that owns the document / part language
= `framework.i18n`. React / MUI / axe-core / Playwright / Testing Library appear
only as illustrative examples.

---

## alt-text — Non-text content (WCAG 1.1.1, level A)

- **Static lane (candidate):** Run the jsx-a11y `alt-text` /
  `img-redundant-alt` rules via `make.lint_eslint` and the axe `image-alt` /
  `role-img-alt` / `svg-img-alt` static rules; inspect `<img>`, `<svg role="img">`,
  icon-font, `background-image`-as-content, and `framework.ui` image/avatar
  components under `architecture.source_root`. Candidate = a meaningful image with
  no `alt` (or no accessible name), or a decorative image not neutralized
  (`alt=""` / `aria-hidden`).
- **Static-determinable:** Yes — a missing `alt` on a meaningful image (1.1.1) is
  provable from the JSX; the attribute is absent.
- **Dynamic lane:** axe-core `image-alt` on the rendered DOM; query the
  accessibility tree for each `img`/`role="img"` node's accessible name; confirm
  decorative images are absent from the tree.
- **Verify by reproduction:** promote when axe flags the node on the rendered
  page, or (static-determinable) when the JSX shows the meaningful image with no
  name. Distinguish an empty/placeholder name (`alt=" "`, filename echoed) — a
  low-quality-name finding — from a truly missing one.
- **Build-mode / degrade / record:** not build-sensitive; survives degrade via
  in-tree demonstration. Record as 1.1.1 (A); remediation pointer → the
  meaningful-vs-decorative-image pattern in
  [remediation-patterns.md](remediation-patterns.md).

## headings-structure — Info & relationships / headings (WCAG 1.3.1 level A, 2.4.6 level AA)

- **Static lane (candidate):** Run jsx-a11y `heading-has-content` via
  `make.lint_eslint` and the axe `empty-heading` / `heading-order` static rules;
  inspect the heading elements (`h1`–`h6`, `role="heading"` + `aria-level`) and
  landmark structure under `architecture.source_root`. Candidate = a skipped
  level, a page with no `h1` or multiple `h1`s, an empty heading, or text styled
  as a heading without a heading role.
- **Static-determinable:** Partial — an empty heading and a missing heading role
  are in-tree; the rendered document outline (skips introduced by composed
  routes/layouts) needs the running DOM.
- **Dynamic lane:** axe-core `heading-order` / `page-has-heading-one` on the
  rendered page; walk the accessibility-tree heading list to reconstruct the
  outline and confirm one logical `h1` per view and no skipped levels.
- **Verify by reproduction:** promote when the rendered outline shows the skip /
  missing `h1`, or when the JSX shows the empty/mis-roled heading.
- **Build-mode / degrade / record:** build-sensitive (composed layouts differ by
  build — cross-check `make.start_prod`); the outline check degrades to
  static-only. Record as 1.3.1 (A) / 2.4.6 (AA); remediation pointer → the
  heading-hierarchy pattern in [remediation-patterns.md](remediation-patterns.md).

## forms-labeling — Labels, name/role/value, input purpose (WCAG 3.3.2 level A, 4.1.2 level A, 1.3.5 level AA)

- **Static lane (candidate):** Run jsx-a11y `label-has-associated-control` /
  `control-has-associated-label` via `make.lint_eslint` and the axe `label` /
  `select-name` / `aria-input-field-name` static rules; inspect every control
  (`input`, `select`, `textarea`, `framework.ui` field wrappers) under
  `architecture.source_root` for a programmatic label (`<label htmlFor>`,
  `aria-label`, `aria-labelledby`), grouped controls' `fieldset`/`legend`, error
  wiring (`aria-describedby` → error text), and `autocomplete` tokens.
- **Static-determinable:** Yes — a control with no associated label
  (1.3.5 / 3.3.2 / 4.1.2) is provable in-tree; no `htmlFor`/`aria-label*` resolves
  to it.

  ```tsx
  // candidate: placeholder is not a label — no accessible name
  <input type="email" placeholder="Email" />
  ```

- **Dynamic lane:** axe-core `label` on the rendered form; Testing Library
  `getByLabelText` / `getByRole('textbox', { name })` to confirm each control's
  accessible name; submit invalid input and confirm the error is announced and
  associated (`aria-describedby`, `aria-invalid`).
- **Verify by reproduction:** promote when `getByLabelText` throws / returns the
  wrong control, when axe flags the unlabeled control, or (static-determinable)
  when the JSX shows no label association.
- **Build-mode / degrade / record:** not build-sensitive; survives degrade via
  in-tree demonstration. Record as 3.3.2 / 4.1.2 (A) and 1.3.5 (AA); remediation
  pointer → the accessible-form-field + error-association pattern in
  [remediation-patterns.md](remediation-patterns.md).

## keyboard-operability — Keyboard, no trap, shortcuts (WCAG 2.1.1 / 2.1.2 / 2.1.4, level A)

- **Static lane (candidate):** Run jsx-a11y `no-noninteractive-element-interactions`
  / `click-events-have-key-events` / `interactive-supports-focus` via
  `make.lint_eslint`; inspect for click handlers on non-interactive elements
  (`<div onClick>` with no key handler / role / `tabIndex`), custom widgets, and
  single-character key shortcuts under `architecture.source_root`. Candidate = an
  operable control not reachable or not actionable by keyboard.
- **Static-determinable:** Partial — a `<div onClick>` with no keyboard affordance
  is a strong in-tree candidate; actual reachability and trap behavior need the
  running stack.
- **Dynamic lane:** keyboard-only traversal — `Tab`/`Shift+Tab` across the view,
  `Enter`/`Space`/arrow activation per the control's role, and a trap check
  (`Tab` past the last control returns to the page, never sticks):

  ```ts
  // Playwright: drive with keyboard only, never a mouse
  await page.keyboard.press('Tab');
  await page.keyboard.press('Enter');   // must activate the focused control
  ```

- **Verify by reproduction:** promote when a control cannot receive focus or
  cannot be activated by keyboard, or when focus enters a subtree it cannot leave
  (a trap, 2.1.2).
- **Build-mode / degrade / record:** build-sensitive (a dev overlay adds focusable
  nodes — cross-check `make.start_prod`); the reachability/trap check needs the
  running stack, so it degrades to a static-only candidate. Record as 2.1.1 /
  2.1.2 / 2.1.4 (A); remediation pointer → the native-element / key-handler
  pattern in [remediation-patterns.md](remediation-patterns.md).

## focus-order — Focus order (WCAG 2.4.3, level A)

- **Static lane (candidate):** Run the jsx-a11y `tabindex-no-positive` rule via
  `make.lint_eslint` and grep `architecture.source_root` for `tabIndex={` values
  greater than `0`, DOM order that diverges from visual/reading order (CSS
  reordering, portals), and roving-tabindex widgets. Candidate = a positive
  `tabindex` or a source order that will not match reading order.
- **Static-determinable:** Yes for the positive-`tabindex` class (2.4.3) — a
  `tabIndex={1}`+ is provable in-tree. A reading-order mismatch is not
  static-determinable — it needs the rendered layout.
- **Dynamic lane:** keyboard-only traversal recording the focus sequence; compare
  it to the visual reading order (including modals, portals, and inserted content).
- **Verify by reproduction:** promote when the observed focus sequence diverges
  from reading order on the running page, or (static-determinable) when a positive
  `tabindex` is present in the JSX.
- **Build-mode / degrade / record:** build-sensitive (StrictMode/overlay can alter
  the sequence — cross-check `make.start_prod`); the order-mismatch check degrades
  to static-only, the positive-`tabindex` class survives degrade. Record as
  2.4.3 (A); remediation pointer → the DOM-order / no-positive-tabindex pattern in
  [remediation-patterns.md](remediation-patterns.md).

## focus-visible — Focus visible (WCAG 2.4.7 level AA, 2.4.11 level AA)

- **Static lane (candidate):** Inspect global CSS / theme tokens / `framework.ui`
  overrides under `architecture.source_root` for `outline: none` (or
  `:focus { outline: 0 }`) with no replacement `:focus-visible` style, and for
  sticky headers/footers that could obscure a focused control (2.4.11). Candidate
  = a focus indicator removed or with no visible substitute.
- **Static-determinable:** No — a visible focus indicator needs computed styles;
  `outline: none` in source is only a candidate until the rendered ring is checked.
- **Dynamic lane:** keyboard-focus each interactive control and capture the
  computed focus style (outline / box-shadow / border delta) and screenshot;
  confirm a perceivable indicator and that no sticky element hides the focused
  control.
- **Verify by reproduction:** promote when a keyboard-focused control shows no
  perceivable indicator on the rendered page, or is fully obscured by other
  content.
- **Build-mode / degrade / record:** build-sensitive for obscuring layout;
  degrades to static-only (the `outline: none` candidate cannot be confirmed
  without computed styles). Record as 2.4.7 / 2.4.11 (AA); remediation pointer →
  the `:focus-visible` indicator pattern in
  [remediation-patterns.md](remediation-patterns.md).

## modal-focus-trap — Dialog focus management (WCAG 2.4.3 / 2.1.2 / 4.1.2, level A)

- **Static lane (candidate):** Inspect modal / dialog / drawer / popover
  components (and the `framework.ui` dialog primitive) under
  `architecture.source_root` for `role="dialog"`/`aria-modal`, an accessible name
  (`aria-labelledby`), initial-focus and focus-return wiring, `Escape` handling,
  and inert/`aria-hidden` on the background. Candidate = an overlay missing the
  dialog role/name, focus containment, focus return, or `Escape`.
- **Static-determinable:** Partial — a missing dialog role/name (4.1.2) is in-tree;
  the *trap-and-return* behavior needs the running stack.
- **Dynamic lane:** open the overlay, confirm focus moves into it, `Tab`-cycle
  stays contained, `Escape` closes it, and focus returns to the invoking control;
  query the accessibility tree for the dialog role + name and background inertness.
- **Verify by reproduction:** promote when focus escapes the open dialog, does not
  enter it on open, does not return on close, or the dialog exposes the wrong
  role/name.
- **Build-mode / degrade / record:** build-sensitive (portal/overlay nodes and
  StrictMode double-mount — cross-check `make.start_prod`); the behavior check
  degrades to static-only. Record as 2.4.3 / 2.1.2 / 4.1.2 (A); remediation
  pointer → the APG dialog focus-management pattern in
  [remediation-patterns.md](remediation-patterns.md).

## live-regions — Status messages (WCAG 4.1.3, level AA)

- **Static lane (candidate):** Inspect content that updates without a reload
  (toasts, inline validation, search-result counts, loading/busy states) under
  `architecture.source_root` for a live region (`role="status"` / `role="alert"` /
  `aria-live`) and correct politeness. Candidate = a dynamic status with no live
  region, or the wrong politeness (assertive spam / polite for an urgent alert).
- **Static-determinable:** No — the *announcement* needs the running stack;
  presence of a region in source does not prove it announces on update.
- **Dynamic lane:** trigger the update via the UI, then query the accessibility
  tree / live-region state to confirm the message is exposed with the intended
  politeness and is not duplicated.
- **Verify by reproduction:** promote when triggering the update yields no
  announcement, or a duplicated / mistimed one, on the running page.
- **Build-mode / degrade / record:** **strongly build-sensitive** — StrictMode
  double-invoke can duplicate announcements; confirm against `make.start_prod`
  before promoting a "double announcement" finding. Degrades to static-only.
  Record as 4.1.3 (AA); remediation pointer → the polite/assertive live-region
  pattern in [remediation-patterns.md](remediation-patterns.md).

## contrast — Text & non-text contrast (WCAG 1.4.3 level AA, 1.4.11 level AA)

- **Static lane (candidate):** Run the axe `color-contrast` static rule and
  inspect theme tokens / palette / `framework.ui` overrides under
  `architecture.source_root` for low-ratio foreground/background pairs and
  low-contrast UI-component boundaries / focus indicators (1.4.11). Candidate = a
  token pair or component style below 4.5:1 (text) / 3:1 (large text, non-text).
- **Static-determinable:** No — the ratio needs computed, rendered colors
  (opacity, overlays, gradients, images behind text); a token pair is only a
  candidate.
- **Dynamic lane:** axe-core `color-contrast` on the rendered DOM; sample computed
  foreground/background for flagged nodes and compute the ratio against the
  1.4.3 / 1.4.11 thresholds; corroborate with the target mapped by
  `make.test_visual` where a pixel baseline exists.
- **Verify by reproduction:** promote only when axe (or the computed-style
  sample) confirms the sub-threshold ratio on the rendered page — never from a
  hex pair alone.
- **Build-mode / degrade / record:** cross-check against `make.start_prod` (theme
  differs by build); degrades to a static-only candidate recorded downgraded (no
  computed styles ⇒ no reproduction). Record as 1.4.3 / 1.4.11 (AA); remediation
  pointer → the accessible-token / contrast pattern in
  [remediation-patterns.md](remediation-patterns.md).

## link-purpose — Link purpose in context (WCAG 2.4.4, level A)

- **Static lane (candidate):** Grep `architecture.source_root` for anchors /
  `framework.ui` link components whose accessible name is vague ("click here",
  "read more", "learn more", "here", an icon-only link with no name) or whose
  target is unclear from the link + its context. Candidate = a non-descriptive
  link name.
- **Static-determinable:** Partial — an icon-only link with no name (also 4.1.2)
  is in-tree; whether context disambiguates a "read more" needs the rendered
  surrounding content.
- **Dynamic lane:** query the accessibility tree for each link's computed
  accessible name (including `aria-label`/`aria-labelledby` and visually-hidden
  text); confirm it conveys purpose standing alone or within its programmatic
  context.
- **Verify by reproduction:** promote when the computed accessible name is vague
  or empty on the rendered page, or (static-determinable) when an icon-only link
  has no name in the JSX.
- **Build-mode / degrade / record:** not meaningfully build-sensitive; the
  no-name class survives degrade, the context question degrades to static-only.
  Record as 2.4.4 (A); remediation pointer → the descriptive-link-text /
  visually-hidden-label pattern in [remediation-patterns.md](remediation-patterns.md).

## tables-structure — Data-table info & relationships (WCAG 1.3.1, level A)

*Dispatched only when a data table exists on the target (else N/A-with-reason).*

- **Static lane (candidate):** Inspect data tables under `architecture.source_root`
  for semantic markup — `<table>` with `<th scope>`, `<caption>` / accessible
  name, header/data association, and (for a custom grid) correct `role="table"` /
  `role="grid"` + row/cell roles. Candidate = a layout of `<div>`s posing as a
  table, missing `scope`/headers, or a grid with incomplete roles.
- **Static-determinable:** Partial — missing `<th scope>` / caption is in-tree;
  header-to-cell association correctness is best confirmed rendered.
- **Dynamic lane:** axe-core `table` rules (`th-has-data-cells`,
  `td-headers-attr`, `scope-attr-valid`) on the rendered DOM; walk the
  accessibility tree to confirm each cell resolves to its column/row headers.
- **Verify by reproduction:** promote when axe flags the table structure, or when
  the accessibility tree shows cells with no associated headers.
- **Build-mode / degrade / record:** not build-sensitive; degrades with the axe
  static rules retained, the tree walk lost. Record as 1.3.1 (A); remediation
  pointer → the semantic-table / scope-headers pattern in
  [remediation-patterns.md](remediation-patterns.md).

## media-captions — Captions & alternatives (WCAG 1.2.2 level A, 1.2.1 level A, 1.2.5 level AA)

*Dispatched only when audio / video exists on the target (else N/A-with-reason).*

- **Static lane (candidate):** Inspect `<video>` / `<audio>` / embedded-player
  usage under `architecture.source_root` for a captions `<track kind="captions">`,
  a transcript for audio-only, and an audio-description track / alternative for
  video (1.2.5). Candidate = time-based media with no captions/transcript.
- **Static-determinable:** Partial — a `<video>` with no `<track>` is a strong
  in-tree candidate; caption *quality/sync* is not statically assessable.
- **Dynamic lane:** load the media surface, enumerate its text tracks / caption
  controls in the DOM, and confirm a captions track is present and selectable and
  a transcript is reachable.
- **Verify by reproduction:** promote when the rendered player exposes no caption
  track / transcript, or (static-determinable) when the JSX media element has no
  `<track>`.
- **Build-mode / degrade / record:** not build-sensitive; the no-`<track>` class
  survives degrade. Record as 1.2.2 / 1.2.1 (A), 1.2.5 (AA); remediation pointer →
  the captions/transcript pattern in [remediation-patterns.md](remediation-patterns.md).

## route-announcement — SPA route-change focus & announcement (WCAG 4.1.3 level AA, 2.4.3 level A)

*Dispatched only when `framework.router` is set (else N/A-with-reason).*

- **Static lane (candidate):** Inspect the router integration / layout shell under
  `architecture.source_root` for post-navigation focus management (move focus to
  the new `h1` / main / a route heading) and a route-change live-region
  announcement, plus a per-route document-title update. Candidate = a client
  navigation with no focus move and no announcement.
- **Static-determinable:** No — the focus move and announcement are runtime
  behaviors on navigation; source presence does not prove them.
- **Dynamic lane:** with `framework.router` set, trigger an in-app navigation and
  observe (a) where focus lands after the route change and (b) whether a live
  region announces the new view / title:

  ```ts
  // Playwright: navigate within the SPA, then inspect focus + live region
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.waitForURL(/settings/);
  // focused element and role="status"/aria-live content are the evidence
  ```

- **Verify by reproduction:** promote when, after a route change on the running
  stack, focus remains on the stale control (or resets to `<body>`) and no
  announcement is exposed.
- **Build-mode / degrade / record:** **strongly build-sensitive** — StrictMode
  double navigation can duplicate the announcement; confirm against
  `make.start_prod`. Gated entirely on `framework.router`; degrades to static-only
  when dynamic testing is off. Record as 4.1.3 (AA) / 2.4.3 (A); remediation
  pointer → the route-focus / route-announcer pattern in
  [remediation-patterns.md](remediation-patterns.md).

## lang-attribute — Language of page & parts (WCAG 3.1.1 level A, 3.1.2 level AA)

- **Static lane (candidate):** Inspect the document shell and the `framework.i18n`
  wiring under `architecture.source_root` for `<html lang>` set to a valid
  language subtag matching the served content, and for `lang` on any part in a
  different language (3.1.2). Candidate = a missing, empty, or wrong `<html lang>`,
  or an untagged foreign-language part.
- **Static-determinable:** Yes — a missing or wrong `<html lang>` (3.1.1) is
  provable in-tree via the `framework.i18n` sink; the attribute is absent or does
  not match the active locale.
- **Dynamic lane:** axe-core `html-has-lang` / `html-lang-valid` /
  `valid-lang` on the rendered document; read the served `<html lang>` and confirm
  it matches the content language (and any per-part `lang`).
- **Verify by reproduction:** promote when axe flags the document language on the
  rendered page, or (static-determinable) when the JSX/shell provably ships a
  missing/wrong `lang`.
- **Build-mode / degrade / record:** not build-sensitive; survives degrade via
  in-tree demonstration through `framework.i18n`. Record as 3.1.1 (A) / 3.1.2 (AA);
  remediation pointer → the document-language pattern in
  [remediation-patterns.md](remediation-patterns.md). (A `lang` value can also
  perturb locale-dependent visual baselines — corroborate with the target mapped
  by `make.test_visual` where one exists.)

## aria-roles-props — Name, role, value / ARIA validity (WCAG 4.1.2 level A, 1.3.1 level A)

- **Static lane (candidate):** Run jsx-a11y `role-has-required-aria-props` /
  `aria-props` / `aria-role` / `role-supports-aria-props` /
  `no-redundant-roles` via `make.lint_eslint` and the axe `aria-required-attr` /
  `aria-valid-attr-value` / `aria-allowed-role` static rules over
  `architecture.source_root`. Candidate = an ARIA `role` missing a required
  property, an invalid attribute/value, a redundant/abused role, or an
  `aria-*`/`role` on an element that does not support it.
- **Static-determinable:** Yes — an ARIA `role` missing its required ARIA property
  (4.1.2) is provable in-tree; the required attribute is absent from the JSX.

  ```tsx
  // candidate: role="checkbox" requires aria-checked
  <span role="checkbox" onClick={toggle}>Remember me</span>
  ```

- **Dynamic lane:** axe-core ARIA rules on the rendered DOM; query the
  accessibility tree for each custom-widget node's role, name, and state and
  confirm they match the intended pattern (and update on interaction).
- **Verify by reproduction:** promote when axe flags the invalid/incomplete ARIA
  on the rendered page, or (static-determinable) when the required property is
  provably absent in the JSX.
- **Build-mode / degrade / record:** build-sensitive for duplicate-`id`
  `aria-labelledby`/`describedby` targets (StrictMode double-mount — cross-check
  `make.start_prod`); the required-property class survives degrade. Record as
  4.1.2 / 1.3.1 (A); remediation pointer → the correct-ARIA-pattern / native-first
  entry in [remediation-patterns.md](remediation-patterns.md).

## target-size — Target size minimum (WCAG 2.5.8, level AA)

- **Static lane (candidate):** Inspect interactive-control styling (icon buttons,
  compact links, close buttons, `framework.ui` size overrides) under
  `architecture.source_root` for hit areas that render below the 24×24 CSS-pixel
  minimum with no adequate spacing exception. Candidate = a control likely to
  render under-sized.
- **Static-determinable:** No — the box needs computed, rendered dimensions; a
  small size token is only a candidate.
- **Dynamic lane:** measure the computed bounding box of flagged interactive
  targets on the rendered page and evaluate against the 24×24 CSS-px minimum plus
  the spacing exception (adjacent-target offset).
- **Verify by reproduction:** promote only when the measured rendered target is
  below the minimum and no spacing exception applies — never from a style token
  alone.
- **Build-mode / degrade / record:** cross-check `make.start_prod` (density/theme
  differs by build); degrades to a static-only candidate recorded downgraded (no
  measured box ⇒ no reproduction). Record as 2.5.8 (AA); remediation pointer →
  the minimum-target-size / spacing pattern in
  [remediation-patterns.md](remediation-patterns.md).

## reflow-zoom — Reflow & resize text (WCAG 1.4.10 level AA, 1.4.4 level AA)

- **Static lane (candidate):** Inspect layout CSS under `architecture.source_root`
  for fixed-pixel widths / viewport-locking (`user-scalable=no`,
  `maximum-scale=1`), horizontal-scroll-forcing containers, and `px`-locked font
  sizes that block resize. Candidate = a layout or viewport meta likely to break
  reflow at 320 CSS px / 400% zoom or to block 200% text resize.
- **Static-determinable:** Partial — a `user-scalable=no` viewport meta is an
  in-tree candidate; loss of content/functionality on reflow needs the rendered
  layout.
- **Dynamic lane:** resize the viewport to 320 CSS px (and emulate 400% zoom /
  200% text) on the running page; confirm no two-dimensional scroll for content,
  no clipped/overlapped content, and no lost functionality.
- **Verify by reproduction:** promote when the reflowed / zoomed rendered page
  shows horizontal scrolling of content, clipping, or lost function, or
  (static-determinable) when the viewport meta blocks zoom.
- **Build-mode / degrade / record:** build-sensitive; degrades to static-only for
  the layout check, the viewport-meta class survives. Record as 1.4.10 / 1.4.4
  (AA); remediation pointer → the responsive-reflow / zoomable-viewport pattern in
  [remediation-patterns.md](remediation-patterns.md).

## motion-reduced — Reduced motion / moving content (WCAG 2.2.2 level A, 2.3.3 level AAA)

- **Static lane (candidate):** Inspect animations / transitions / auto-advancing
  content (carousels, marquees, parallax, auto-play) under
  `architecture.source_root` for a `prefers-reduced-motion` guard and, for
  content that moves/auto-updates for more than five seconds, a pause/stop/hide
  control (2.2.2). Candidate = motion with no reduced-motion path or no pause
  control.
- **Static-determinable:** No — honoring the user preference is a runtime behavior
  under the media query; source is only a candidate.
- **Dynamic lane:** emulate `prefers-reduced-motion: reduce` on the running page
  and confirm non-essential animation is reduced/removed; confirm any
  auto-advancing content exposes a working pause/stop control.
- **Verify by reproduction:** promote when animation still plays under the emulated
  reduced-motion preference, or auto-advancing content has no pause/stop/hide.
- **Build-mode / degrade / record:** build-sensitive (dev vs production animation
  differs — cross-check `make.start_prod`); degrades to a static-only candidate
  (no media-query emulation ⇒ no reproduction). Record as 2.2.2 (A) primarily
  (2.3.3 AAA where interaction-triggered motion applies, flagged as best-practice);
  remediation pointer → the reduced-motion / pause-control pattern in
  [remediation-patterns.md](remediation-patterns.md).

---

## Cross-family notes

- **Static-determinable classes** (missing `alt` 1.1.1; an unlabeled control
  1.3.5 / 3.3.2 / 4.1.2; a missing/wrong `<html lang>` 3.1.1 via `framework.i18n`;
  a positive `tabindex` 2.4.3; an ARIA `role` missing a required property 4.1.2)
  are promoted by deterministic in-tree demonstration — the attribute provably
  absent/malformed in the JSX — and stay promotable even when dynamic testing is
  degraded. Every other family requires a live reproduction against the running
  stack; a candidate that can neither be reproduced nor in-tree-demonstrated is
  recorded downgraded/dropped with the reason, never reported.
- **Build mode is a first-class variable.** Prefer the production-parity build
  (the target mapped by `make.start_prod`) for the authoritative dynamic pass — it
  is the same artifact the visual-regression (`make.test_visual`) and performance
  gates audit. Any focus-order, live-region-timing, duplicate-`id` ARIA, or
  route-announcement verdict taken on a dev build must be cross-checked against
  production parity before CLEAN or promotion, and the build mode stated in the
  verdict.
- **Degrade.** When `capabilities.dynamic_a11y_testing` is false or `make.start`
  is null, no base URL is passed and only the static lanes (jsx-a11y / ARIA via
  the `make.lint_eslint` target, the axe static-rule pass, semantic-HTML /
  ARIA-pattern inspection over `architecture.source_root`) run; the
  static-determinable classes remain promotable and every other family's dynamic
  candidate is recorded downgraded. No degrade path loops or hard-fails.
- **Promotion.** Each promoted finding carries the shared record fields
  (`location` `file:line`, WCAG SC id, level A/AA, severity band-with-rationale,
  reproduction, remediation pointer), maps to a Success Criterion in
  [wcag-catalog.md](wcag-catalog.md), and cites its accessible-by-default fix from
  [remediation-patterns.md](remediation-patterns.md). No `eslint-disable`, jsx-a11y
  disable directive, axe rule suppression, baseline, or `data-testid`-to-dodge is
  ever a remediation — fix the code at the root cause.
