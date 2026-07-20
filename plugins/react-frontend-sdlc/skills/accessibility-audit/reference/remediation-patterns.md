# Remediation Patterns — Accessible-by-Default, Root-Cause Fixes

The fix catalog the `accessibility-audit` loop cites when it routes a verified
finding to the `react-implementer` agent. One entry per a11y family from
[`wcag-catalog.md`](wcag-catalog.md), aligned to the 18 family ids the loop
dispatches. Each entry pairs a **root-cause fix** — semantic HTML first, then the
correct ARIA pattern, then the right `framework.ui` component slot — with a
**failing-then-passing regression test** and the suppression "fixes" it must never
use.

Fixes are **accessible-by-default and root-cause**. The auditor never edits code;
every fix routes through `react-implementer` with the
`{location, remediation, regression_test}` slice of the finding record (the
[`../SKILL.md`](../SKILL.md) hand-off contract). **Dedupe at the sink:** a barrier
emitted by a shared `architecture.component_prefix` primitive across many views is
fixed **once at the component**, not per view — the fix propagates to every
consumer.

Every regression test locates elements by **user-facing semantics** — a Testing
Library `getByRole` / `getByLabelText` / `getByText` query for the corrected
accessible name / role, or an axe assertion on the rendered component. **Never** add
a `data-testid` to make a barrier or a test pass; fall back to a stable `id` only
when no semantic query fits.

## Policy (non-negotiable)

A remediation closes the **sink**, not the alert. The failing-then-passing
regression test **fails** on the unfixed component and **passes** once the
root-cause fix lands. A fix without that test is not a fix.

### Forbidden "fixes" (none of the patterns below use them)

A finding is **never** remediated by making the detector quiet. The following are
prohibited everywhere in this catalog and in any fix it drives — they lower the bar
instead of removing the barrier:

- An `eslint-disable` comment, a jsx-a11y disable directive, or a `@ts-ignore`
  placed to silence a candidate at its source line.
- An axe rule suppression, an axe **baseline / ignore-list** entry, or extending an
  existing one to absorb the finding.
- Relaxing a tool's configuration — loosening a jsx-a11y rule mapped by
  `make.lint_eslint`, or removing an axe check — so the candidate stops firing.
- Lowering a `quality.*` threshold — `quality.eslint_errors` or `quality.visual_diffs`
  — or deleting a visual baseline so a computed-style change slips through.
  Thresholds are **raise-only**; fix the code.
- Setting `role="presentation"`, an empty `aria-label`, or `aria-hidden` on a
  **meaningful** control to hide it from the check rather than naming it.
- Adding a `data-testid` to locate an element the accessibility tree should already
  expose by role and name.

If a fix appears to require any of the above, it is the wrong fix: trace back to the
component sink and remediate there.

## Pattern catalog

### alt-text (1.1.1 Non-text Content)

- **Root cause:** a meaningful `<img>`, SVG, or icon-only control carries no text
  alternative, or a decorative image announces its filename.
- **Wrong → right:**

```jsx
// WRONG — meaningful image with no accessible name
<img src={chart} />
// WRONG — icon-only control announces nothing
<button onClick={remove}><TrashIcon /></button>

// RIGHT — meaningful image carries concise alt
<img src={chart} alt="Revenue up 12% quarter over quarter" />
// RIGHT — decorative image is removed from the accessibility tree
<img src={divider} alt="" />
// RIGHT — icon-only control gets an accessible name; the glyph is hidden
<button onClick={remove} aria-label="Remove item"><TrashIcon aria-hidden /></button>
```

  Prefer `alt` on the semantic element; for a `framework.ui` icon button use its
  `aria-label` / visually-hidden-text slot. A complex image (chart) gets a short
  `alt` plus a longer description via `aria-describedby` pointing at adjacent text.

- **Regression test:** `expect(screen.getByRole('img', { name: /revenue up 12%/i }))`
  and `getByRole('button', { name: /remove item/i })`, plus an axe assertion that
  fails on `image-alt` / `button-name` before and passes after. Query by accessible
  name, never a `data-testid`.
- **Forbidden here:** don't set `role="presentation"` on a meaningful image, don't
  silence the jsx-a11y `alt-text` rule or add an axe baseline entry.

### headings-structure (1.3.1 Info and Relationships, 2.4.6 Headings and Labels)

- **Root cause:** visual size substitutes for heading semantics (a styled `<div>`),
  levels are skipped, or a view has no `<h1>`.
- **Wrong → right:**

```jsx
// WRONG — styled div contributes nothing to the outline
<div className="page-title">Dashboard</div>
// WRONG — jumps h2 → h4
<h2>Reports</h2>
<h4>Weekly</h4>

// RIGHT — one h1 per view, no skipped levels
<h1>Dashboard</h1>
<h2>Reports</h2>
<h3>Weekly</h3>
```

  Use real `<h1>`–`<h6>`, or the `framework.ui` typography component's
  element/variant split so the visual `variant` sets size while `component="h2"`
  sets the level. Wrap regions in landmarks (`<main>`, `<nav>`).

- **Regression test:** `getByRole('heading', { level: 1, name: /dashboard/i })` and
  an order assertion over `getAllByRole('heading')`; axe `heading-order` /
  `page-has-heading-one` fails before, passes after.
- **Forbidden here:** don't fake the outline with `aria-level` on a skipped heading,
  don't disable the jsx-a11y `heading-order` rule.

### forms-labeling (1.3.5 Identify Input Purpose, 3.3.2 Labels or Instructions, 4.1.2 Name, Role, Value)

- **Root cause:** a control relies on a placeholder or a nearby loose text node
  instead of a programmatically associated label.
- **Wrong → right:**

```jsx
// WRONG — a placeholder is not a label
<input placeholder="Email" />
// WRONG — visible text not associated with the control
<span>Email</span><input id="email" />

// RIGHT — explicit htmlFor/id association
<label htmlFor="email">Email</label>
<input id="email" name="email" type="email" />
// RIGHT — wrapping label needs no id
<label>Email<input type="email" /></label>
```

  For a `framework.ui` text field pass the `label` prop (it renders a linked
  `<label>`); group radios / checkboxes in `<fieldset>` + `<legend>`; link error
  text via `aria-describedby` + `aria-invalid`.

- **Regression test:** `getByLabelText(/email/i)` returns the input; axe `label`
  fails before, passes after. Never use `getByPlaceholderText` as the label proof.
- **Forbidden here:** don't bolt on an `aria-label` that duplicates a visible label
  while leaving `<label>` unassociated, don't disable jsx-a11y label rules.

### keyboard-operability (2.1.1 Keyboard, 2.1.3 Keyboard (No Exception))

- **Root cause:** interactive behavior lives on a non-interactive element
  (`<div onClick>`), so it is neither focusable nor `Enter` / `Space` operable.
- **Wrong → right:**

```jsx
// WRONG — a div is not focusable or key-operable
<div onClick={submit}>Save</div>

// RIGHT — a native button is keyboard-operable for free
<button type="button" onClick={submit}>Save</button>
```

  Prefer the native element (`<button>`, `<a href>`, `<input>`). Only if a custom
  widget is truly unavoidable, add the `role`, `tabIndex={0}`, and key handlers from
  the matching ARIA Authoring Practices pattern. Reach for the `framework.ui` button
  or link over a clickable `<div>`.

- **Regression test:** `getByRole('button', { name: /save/i })`, then `user.tab()`
  reaches it and `user.keyboard('{Enter}')` asserts the handler fired; axe fails on
  the non-interactive click before, passes after.
- **Forbidden here:** don't paper over it with an `onKeyDown` on a `<div>` kept as a
  `<div>`, don't disable jsx-a11y `no-static-element-interactions` /
  `click-events-have-key-events`.

### focus-order (2.4.3 Focus Order)

- **Root cause:** a positive `tabIndex`, or a DOM order that diverges from the
  visual reading order, sends focus to the wrong place.
- **Wrong → right:**

```jsx
// WRONG — positive tabindex hijacks the natural order
<input tabIndex={3} /><input tabIndex={1} />

// RIGHT — DOM order equals reading order; no positive tabindex
<input /><input />
```

  Order the DOM to match the reading order; use `tabIndex={0}` (in flow) or `-1`
  (programmatic only), never `> 0`. When a portal (menu / dialog) breaks the order,
  move focus explicitly on open.

- **Regression test:** a `user.tab()` sequence asserts the focused element matches
  the expected control resolved via `getByRole` (`toHaveFocus`); axe `tabindex`
  fails before, passes after.
- **Forbidden here:** don't renumber positive tabindexes to "reorder", don't disable
  the `tabindex` rule.

### focus-visible (2.4.7 Focus Visible, 2.4.13 Focus Appearance)

- **Root cause:** `outline: none` strips the focus indicator with no replacement.
- **Wrong → right:**

```css
/* WRONG — removes the only focus indicator */
button:focus { outline: none; }

/* RIGHT — a visible ring on keyboard focus */
button:focus-visible { outline: 2px solid; outline-offset: 2px; }
```

  Keep or restyle a visible indicator that meets contrast and appearance; set the
  focus tokens once in the Emotion / `framework.ui` theme so every shared control
  inherits them. This is a **computed-style** family — verify with `make.test_visual`.

- **Regression test:** a `make.test_visual` snapshot of the focused control (driven
  by `getByRole(...).focus()`) fails before, passes after. Contrast and appearance
  need computed styles, so this is not an in-tree-only assertion.
- **Forbidden here:** don't delete the failing visual baseline or widen
  `quality.visual_diffs` to absorb the ring, don't ship `outline: none` behind a
  disable comment.

### modal-focus-trap (2.1.2 No Keyboard Trap, 2.4.3 Focus Order, 4.1.2 Name, Role, Value)

- **Root cause:** a custom overlay `<div>` does not trap focus, does not restore it
  on close, and lacks dialog semantics.
- **Wrong → right:**

```jsx
// WRONG — plain div: focus escapes, no role, no name, no restore
{open && <div className="overlay">{children}</div>}

// RIGHT — native dialog semantics + trap + restore
<Dialog open={open} onClose={close} aria-labelledby="dlg-title">
  <h2 id="dlg-title">Confirm</h2>
  {children}
</Dialog>
```

  Prefer the `framework.ui` dialog — it traps focus, restores focus to the trigger
  on close, wires `role="dialog"` / `aria-modal`, and closes on `Escape`. If
  hand-rolled, use `<dialog>` or the APG dialog pattern: move focus in on open,
  cycle `Tab` within the dialog, return focus to the opener on close.

- **Regression test:** open the dialog, `user.tab()` cycles stay within
  `getByRole('dialog')`; `user.keyboard('{Escape}')` closes and
  `expect(trigger).toHaveFocus()`; axe fails on the unnamed overlay before, passes
  after.
- **Forbidden here:** don't set `aria-modal` on a `<div>` with no real focus trap,
  don't suppress the axe dialog rule.

### live-regions (4.1.3 Status Messages, 3.3.1 Error Identification)

- **Root cause:** async status (search results, toast, validation) updates the DOM
  silently — no polite / assertive announcement reaches assistive tech.
- **Wrong → right:**

```jsx
// WRONG — the count changes but nothing is announced
<span>{count} results</span>

// RIGHT — a polite region announces non-urgent updates
<div role="status" aria-live="polite">{count} results</div>
// RIGHT — urgent errors are assertive
<div role="alert">{error}</div>
```

  Use `role="status"` / `aria-live="polite"` for non-urgent updates and
  `role="alert"` / `assertive` for errors; render the shared
  `architecture.component_prefix` live-status component **once** and feed it
  messages. The region must exist in the DOM **before** the update.

- **Regression test:** trigger the update, then `await screen.findByRole('status')`
  (or `alert`) exposes the text via `getByText`; assert the region is empty before.
  Fails before, passes after.
- **Forbidden here:** don't fire `assertive` for every update, don't add a
  `data-testid` to locate the region, don't disable the related jsx-a11y rule.

### contrast (1.4.3 Contrast (Minimum), 1.4.11 Non-text Contrast)

- **Root cause:** a text or UI color pair falls below 4.5:1 (3:1 for large text /
  non-text components).
- **Wrong → right:**

```css
/* WRONG — #9e9e9e on #ffffff is about 2.8:1 */
.hint { color: #9e9e9e; }

/* RIGHT — a token that meets 4.5:1 */
.hint { color: #616161; }
```

  Fix the color **token** at the Emotion / `framework.ui` theme source so every
  consumer inherits the compliant value (dedupe at the token, not per view).
  Computed-style family — verify with axe on the rendered DOM and `make.test_visual`.

- **Regression test:** axe `color-contrast` on the rendered component fails before,
  passes after; a `make.test_visual` snapshot guards the token change.
- **Forbidden here:** don't disable axe `color-contrast`, don't add it to an axe
  baseline / ignore list, don't relax `quality.visual_diffs` — raise the contrast.

### link-purpose (2.4.4 Link Purpose (In Context), 2.4.9 Link Purpose (Link Only))

- **Root cause:** ambiguous link text ("click here", "read more") that fails to
  convey the destination out of context.
- **Wrong → right:**

```jsx
// WRONG — purpose unclear from the link alone
<a href={url}>Read more</a>

// RIGHT — descriptive, self-contained link text
<a href={url}>Read the Q3 revenue report</a>
// RIGHT — keep the visual short, extend the accessible name
<a href={url}>Read more<span className="sr-only"> about the Q3 revenue report</span></a>
```

  Prefer self-describing text; when the visual must stay short, extend the
  accessible name with visually-hidden text (or `aria-label`). Use `<a href>` /
  `framework.router` link for navigation and `<button>` for actions.

- **Regression test:** `getByRole('link', { name: /q3 revenue report/i })` matches
  the descriptive name; the vague-name assertion fails before, passes after.
- **Forbidden here:** don't keep "read more" and disable the link-text check.

### tables-structure (1.3.1 Info and Relationships)

- **Root cause:** tabular data is laid out with `<div>`s, or a `<table>` has no
  header cells and no caption.
- **Wrong → right:**

```jsx
// WRONG — a grid of divs with no header semantics
<div className="row"><div>Name</div><div>Total</div></div>

// RIGHT — a semantic table with scoped headers and a caption
<table>
  <caption>Orders by customer</caption>
  <thead><tr><th scope="col">Name</th><th scope="col">Total</th></tr></thead>
  <tbody><tr><th scope="row">Ada</th><td>42</td></tr></tbody>
</table>
```

  Use `<table>` / `<th scope>` / `<caption>`; apply the ARIA `grid` / `treegrid` APG
  pattern **only** when a native table cannot express the interaction. Fix once in
  the shared table component.

- **Regression test:** `getByRole('table', { name: /orders by customer/i })` and
  `getByRole('columnheader', { name: /total/i })`; axe fails on the div-table
  before, passes after.
- **Forbidden here:** don't bolt `role="table"` onto `<div>`s with no header cells,
  don't disable the check.

### media-captions (1.2.2 Captions (Prerecorded), 1.2.5 Audio Description (Prerecorded))

- **Root cause:** a `<video>` / `<audio>` element ships with no captions track and
  no transcript.
- **Wrong → right:**

```jsx
// WRONG — no captions
<video src={clip} controls />

// RIGHT — a synchronized captions track
<video src={clip} controls>
  <track kind="captions" srcLang="en" src={captionsVtt} label="English" default />
</video>
```

  Provide a `<track kind="captions">` (and a transcript for audio-only media); use
  native `controls` or a keyboard-operable custom player. Localized caption sources
  come from `framework.i18n`, never hardcoded in the component.

- **Regression test:** assert the rendered media element contains a
  `track[kind="captions"]` (resolve the media element by role / label, then its
  track); fails before, passes after. axe media rules complement.
- **Forbidden here:** don't tick the box with a player that has no track, don't
  suppress the media rule.

### route-announcement (4.1.3 Status Messages, 2.4.2 Page Titled)

- **Root cause:** a `framework.router` route change swaps content without moving
  focus or announcing — the screen reader stays on the stale view.
- **Wrong → right:**

```jsx
// WRONG — route changes; title and focus never move
<Routes>{/* content swaps silently */}</Routes>

// RIGHT — on navigation, set the title and announce + move focus
useEffect(() => {
  document.title = `${routeTitle} — App`;
  liveRegion.announce(routeTitle);   // a shared polite region
  mainRef.current?.focus();          // <main tabIndex={-1}>
}, [pathname]);
```

  Add a router-level announcer: update the document title, send the new view name to
  a polite live region, and move focus to `<main tabIndex={-1}>` or the new `<h1>`.
  One shared announcer, not one per route. N/A when `framework.router` is unset.

- **Regression test:** navigate with the `framework.router` test utilities, then
  `await screen.findByRole('status')` announces the view name and focus lands on
  `getByRole('main')` / the `<h1>`; fails before, passes after.
- **Forbidden here:** don't announce every route `assertive`, don't disable the
  rule.

### lang-attribute (3.1.1 Language of Page, 3.1.2 Language of Parts)

- **Root cause:** `<html>` has no `lang`, or a stale hardcoded value, so assistive
  tech picks the wrong pronunciation.
- **Wrong → right:**

```jsx
// WRONG — no lang, or a stale hardcoded value
<html>

// RIGHT — lang fed from the framework.i18n active locale
<html lang={i18n.language}>
// RIGHT — an inline language change marked on the element
<blockquote lang="fr">Bonjour</blockquote>
```

  Set `<html lang>` from the `framework.i18n` active language so it stays in sync
  with locale switches, and mark in-page language shifts with `lang` on the element.
  Note: changing `<html lang>` can re-hint font shaping and shift visual baselines —
  pair the change with `make.test_visual` and regenerate the baseline under the
  correct `lang`.

- **Regression test:** render the app shell and assert the `<html>` element's `lang`
  equals the active `framework.i18n` locale; fails before (empty / wrong), passes
  after. axe `html-has-lang` / `html-lang-valid` complement.
- **Forbidden here:** don't hardcode one locale to satisfy `html-has-lang` while the
  UI renders another, don't disable the axe lang rules, don't delete the shifted
  visual baseline — regenerate it under the correct `lang`.

### aria-roles-props (4.1.2 Name, Role, Value, 1.3.1 Info and Relationships)

- **Root cause:** an invalid role, a role missing its required states / props, or
  ARIA applied where native HTML would already convey the semantics.
- **Wrong → right:**

```jsx
// WRONG — role without its required props; redundant / empty ARIA
<div role="checkbox" onClick={toggle} />
<button role="button" aria-label="">Go</button>

// RIGHT — the native element needs no ARIA
<input type="checkbox" checked={checked} onChange={toggle} />
// RIGHT — a custom widget carries every required state and prop
<div role="checkbox" tabIndex={0} aria-checked={checked}
     onKeyDown={onKey} onClick={toggle} />
```

  First rule of ARIA: use the native element. When a role is required, supply every
  required state / prop from the APG pattern and keep the `aria-*` values in sync
  with component state; remove redundant or empty ARIA.

- **Regression test:** `getByRole('checkbox', { name: /accept/i })` with
  `toHaveAttribute('aria-checked', ...)`, toggled by keyboard; axe
  `aria-required-attr` / `aria-allowed-role` fails before, passes after.
- **Forbidden here:** don't disable jsx-a11y `role-has-required-aria-props`, don't
  suppress the axe aria rules, don't add an empty `aria-label` to quiet a linter.

### target-size (2.5.8 Target Size (Minimum))

- **Root cause:** an interactive control is smaller than the 24×24 CSS-px minimum
  and lacks the spacing exception.
- **Wrong → right:**

```css
/* WRONG — a 16px icon hit area */
.icon-btn { width: 16px; height: 16px; }

/* RIGHT — a target of at least 24×24 CSS px */
.icon-btn { min-width: 24px; min-height: 24px; padding: 4px; }
```

  Size the control (or its padding / hit area) to at least 24×24 CSS px at the
  shared `framework.ui` / `architecture.component_prefix` control so every instance
  complies. Computed-style family — verify with `make.test_visual` and DOM
  measurement.

- **Regression test:** a rendered-size assertion (bounding box / computed
  `min-height`) that the control is ≥ 24px, plus a `make.test_visual` snapshot;
  fails before, passes after.
- **Forbidden here:** don't relax `quality.visual_diffs` to absorb the resize, don't
  disable the check.

### reflow-zoom (1.4.10 Reflow, 1.4.4 Resize Text)

- **Root cause:** fixed-px widths or `user-scalable=no` force a second scroll axis
  or block zoom at a 320px viewport / 200% zoom.
- **Wrong → right:**

```jsx
// WRONG — blocks pinch-zoom
<meta name="viewport" content="width=device-width, user-scalable=no" />
```

```css
/* WRONG — a fixed width forces horizontal scroll */
.panel { width: 1200px; }
/* RIGHT — fluid and reflow-safe */
.panel { max-width: 100%; width: 100%; }
```

  Remove `user-scalable=no` / `maximum-scale`; use relative units and responsive
  layout so content reflows to a 320px viewport at 200% zoom without a second scroll
  axis. Fix in the shared layout component.

- **Regression test:** a render at a 320px-equivalent viewport asserts no horizontal
  overflow (`scrollWidth <= clientWidth`), plus a `make.test_visual` responsive
  snapshot; fails before, passes after.
- **Forbidden here:** don't widen `quality.visual_diffs`, don't re-add
  `user-scalable=no`.

### motion-reduced (2.3.3 Animation from Interactions, 2.2.2 Pause, Stop, Hide)

- **Root cause:** animation or auto-play runs unconditionally, ignoring the user's
  `prefers-reduced-motion` preference.
- **Wrong → right:**

```css
/* WRONG — always animates */
.card { transition: transform 300ms; }

/* RIGHT — respect the reduced-motion preference */
@media (prefers-reduced-motion: reduce) {
  .card { transition: none; }
}
```

  Guard non-essential motion behind `prefers-reduced-motion` — a CSS media query or
  a reduced-motion hook feeding the Emotion / `framework.ui` theme — and provide a
  pause / stop control for anything auto-playing beyond 5 seconds. Guard once in the
  shared animation primitive.

- **Regression test:** mock `matchMedia('(prefers-reduced-motion: reduce)')` and
  assert the component renders without the animated style / props; fails before
  (always animates), passes after.
- **Forbidden here:** don't disable the motion lint rule, don't remove the guard
  behind a suppression.

## How a fix lands (loop contract)

1. The orchestrator hands `react-implementer` the verified finding's
   `{location, remediation, regression_test}` (the [`../SKILL.md`](../SKILL.md)
   finding-record contract) and the cited pattern above.
2. `react-implementer` writes the **failing** regression test first (an axe
   assertion or a Testing Library role + accessible-name query), then the
   **root-cause** fix — a semantic-HTML element, the correct ARIA pattern, or the
   right `framework.ui` slot. No `eslint-disable`, no jsx-a11y disable directive, no
   axe suppression or baseline, no config relaxation, and no `quality.eslint_errors`
   / `quality.visual_diffs` threshold reduction.
3. The affected-family `accessibility-auditor` **re-verifies**: the
   [`audit-playbooks.md`](audit-playbooks.md) reproduction no longer succeeds and
   the new regression test passes.
4. The loop closes only when the CI gate is green (the lint lane mapped by
   `make.lint_eslint` and the visual lane mapped by `make.test_visual` included) and
   the forbidden-suppression scan reports zero suppressions introduced.

## Related references

- [`wcag-catalog.md`](wcag-catalog.md) — the family / WCAG 2.2 Success Criterion
  corpus these patterns remediate.
- [`audit-playbooks.md`](audit-playbooks.md) — the probe + reproduce step each
  regression test is built from.
- [`../SKILL.md`](../SKILL.md) — the audit loop that routes each verified finding to
  this catalog.
