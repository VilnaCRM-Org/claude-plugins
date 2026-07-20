# The Mandatory Accessibility Gate

This is the one gate that distinguishes the `react-frontend-sdlc` plugin from
its backend twin, `php-backend-sdlc`. The two plugins share the same
SDLC machinery — the same triage → fan-out → find → verify → fix → regress →
re-verify loop, the same profile-driven generalization, the same
degrade-with-a-note discipline. Where the backend twin runs a security deep-audit
lens (OWASP / CWE) over an API, the frontend plugin runs an **accessibility
deep-audit lens** (WCAG 2.2 AA) over a rendered UI, and it makes that lens
**non-negotiable**: no user-facing change ships without a clean accessibility
verdict.

This document is the contract for that gate. The mechanics live in the
[`accessibility-audit`](../skills/accessibility-audit/SKILL.md) skill and the
[`accessibility-auditor`](../agents/accessibility-auditor.md) agent; this page
states the guarantees those two pieces uphold and how the SDLC stages enforce
them. It applies unchanged across every repository the plugin serves — a React
SPA, a Next.js app, or a Storybook-first component library — because every
concrete path, target, and threshold resolves through the project profile at
`.claude/react-sdlc.yml` (see [`profile-schema.md`](profile-schema.md)), never
through a hardcoded stack.

## The gate is non-negotiable

Every SDLC stage that touches user-facing UI runs the `accessibility-audit`
skill through the `accessibility-auditor` agent. Accessibility is not an
advisory lens and not a "nice to have" deferred to a later pass — it blocks
exactly like a functional-requirement finding.

Two stages own the gate, and both block:

- **Stage 4 — review (`/fe-sdlc-review`).** The review gate dispatches three
  independent lenses in parallel — `fr-nfr-reviewer` (spec), `code-quality-reviewer`
  (quality), and `accessibility-auditor` (accessibility). The accessibility lens
  is **always dispatched**; it is not subject to the applicability triage that
  can mark other skills NOT-APPLICABLE. The stage exit condition is that all
  three lenses report clean: zero new FR/NFR findings **and** zero new verified
  a11y findings **and** every quality threshold met. An `accessibility-auditor`
  FAIL row (a WCAG 2.2 AA violation — a missing accessible name, a broken focus
  order, insufficient contrast, an unlabeled control) blocks the stage verdict
  and **never silently defers to Stage 5 QA**.
- **Stage 5 — QA (`/fe-sdlc-qa`).** The `qa-visual-tester` agent boots the
  production-parity stack and runs an axe-core accessibility lane against the
  rendered DOM alongside the Playwright E2E, visual-regression, and Lighthouse
  lanes. The a11y lane passes only at **0 violations**; a FAIL routes the work
  back to the implement stage. QA is the second, black-box enforcement of the
  same standard the Stage 4 review lens enforced grey-box.

The audit skill is also invocable **standalone** as
`react-frontend-sdlc:accessibility-audit` against an authorized target, with the
identical loop body. Whichever entry point runs it, the target is driven to
**zero new verified accessibility findings** before the stage passes.

When a changeset touches no user-facing surface, the lens records a clean
DEGRADED no-op (a11y satisfied for a change with no UI sink) rather than
inventing work — the gate is present on every stage but only exercises the audit
when there is UI to audit.

## The standard: WCAG 2.2 Level AA

The conformance target is **WCAG 2.2 Level AA**. Every reported finding is mapped
to a WCAG 2.2 Success Criterion id, a conformance level (A or AA), and a severity
band with a one-line rationale that weighs impact (does the barrier block task
completion) and reach (a shared `architecture.component_prefix` primitive versus a
single view).

The enumerations that drive the audit are never inlined — they live in the
skill's `reference/` directory so the audit stays comprehensive without bloating
the loop:

- [`skills/accessibility-audit/reference/wcag-catalog.md`](../skills/accessibility-audit/reference/wcag-catalog.md)
  — the family catalog: the full WCAG 2.2 AA corpus grouped by the POUR
  principles (Perceivable, Operable, Understandable, Robust) plus the
  cross-cutting surfaces (forms, modals/dialogs, keyboard, live regions, contrast,
  alt-text / headings, links, tables), each with its SC mappings and profile
  gates. This is the single source for the dispatchable family set.
- [`skills/accessibility-audit/reference/audit-playbooks.md`](../skills/accessibility-audit/reference/audit-playbooks.md)
  — the per-family probe playbooks: the static check, the reproduce-against-stack
  step, and the axe rule ids / WCAG test procedure each `accessibility-auditor`
  subagent follows for its one assigned family.
- [`skills/accessibility-audit/reference/remediation-patterns.md`](../skills/accessibility-audit/reference/remediation-patterns.md)
  — the remediation patterns: the semantic-HTML element, ARIA Authoring Practices
  pattern, or `framework.ui` component slot (for example a Material UI v7 slot
  that owns the accessible name/role) each fix is cited against.

Triage covers the **entire** catalog: every family receives an explicit verdict
— PROBE or N/A-with-reason — with no silent skips. A family whose surface does
not exist on the target (a tables family with no data table, a media-captions
family with no audio or video, a route-announcement family when `framework.router`
is unset) is recorded N/A-with-reason up front and never dispatched, which keeps
the fan-out cost bounded.

## The verify-by-reproduction bar

A static hit is a **candidate**, never a finding. The no-false-positive rule is
non-negotiable: an axe-core violation from a static rule pass, a jsx-a11y lint
hit, or an ARIA-pattern smell is promoted to a reported finding only when one of
two proofs succeeds:

- **Reproduced against the running stack** — an axe-core violation on the
  rendered DOM, a keyboard sequence that traps focus or cannot reach a control,
  or an accessibility-tree / accessible-name / role query that returns the wrong
  value; **or**
- **Deterministically demonstrated in-tree** — for the static-determinable
  classes that need no rendered styles: a missing `alt` on a meaningful image
  (1.1.1), a form control with no associated label (1.3.5 / 3.3.2 / 4.1.2), a
  missing or wrong `<html lang>` (3.1.1, the `framework.i18n` sink), a positive
  `tabindex` (2.4.3), or an ARIA `role` missing its required ARIA property
  (4.1.2) — the attribute provably absent or malformed in the JSX.

A candidate that can be neither reproduced against the stack nor demonstrated
in-tree — a contrast ratio that needs computed styles, a focus-order or
live-region-timing question, a keyboard-trap behavior — is recorded
downgraded/dropped with its reason. It is never reported and never fixed. The
`accessibility-auditor` subagents enforce this first; the skill orchestrator is
the second gate at the aggregate/dedupe/promote step.

Build mode is part of the reproduction record. A dev-server build can mask or
inflate findings — a dev error overlay injects extra focusable nodes, StrictMode
double-invokes and can duplicate `id`s or live-region announcements, and dev-only
attributes differ from production output. So the build mode travels in every
dispatch, and a family whose verdict depends on build-toggled rendered output
(focus order, live-region timing, duplicate-`id` ARIA) is cross-checked against a
production-parity build before it is reported CLEAN or promoted. The authoritative
dynamic pass prefers the `make.start_prod` build — the same artifact the
visual-regression and Lighthouse gates audit.

## Fixes are root-cause and accessible-by-default

Every verified finding routes to the [`react-implementer`](../agents/react-implementer.md)
agent — never edited by the audit skill and never by the `accessibility-auditor`
subagent (its tool surface deliberately has no Edit/Write). The implementer
receives the `{location, remediation, regression_test}` slice of the finding
record plus the cited remediation pattern, and produces a fix that is
**root-cause and accessible-by-default**: a semantic-HTML element, the correct
ARIA pattern, or the right `framework.ui` component slot — not a band-aid over
the symptom.

Every fix carries a **failing-then-passing regression test** that reproduces the
barrier and then proves it closed — an axe assertion on the rendered component,
or a Testing Library query for the now-correct accessible name / role. Elements
are located by **user-facing semantics** — `getByRole`, `getByLabelText`,
`getByText`, falling back to a stable `id` only when no semantic query fits —
**never** by a test-only `data-testid` added to make the test pass. The affected
family is then re-dispatched to re-verify that the reproduction no longer
succeeds and the new test passes.

## No suppression, ever

A finding is closed by fixing the code, never by hiding it. The following are
forbidden as a way to make a barrier or a gate disappear:

- an `eslint-disable` or a `jsx-a11y` disable directive;
- an axe rule suppression or an axe baseline / allowlist;
- a `@ts-ignore` or any lint/type config relaxation;
- lowering any `quality.*` threshold — the profile's floors are raise-only and
  its ceilings are fixed at `0`.

The forbidden-suppression scan runs over the diff before the loop declares
success, and the full `make.ci` target runs once at loop close as the safety net.
This is the same root-cause-not-suppression policy the plugin applies to ESLint,
TypeScript, duplication, and metrics — applied to accessibility with no exception.

## An a11y match never waives another gate

The accessibility gate is additive. Passing it does not buy relief from any other
quality gate, and conversely an a11y finding never excuses a regression
elsewhere. In particular:

- The **visual-regression gate** (the target mapped by `make.test_visual`, gated
  by `capabilities.visual_testing`) still holds at its `quality.visual_diffs`
  ceiling of `0`. A remediation that changes rendered output must update the
  authoritative baselines through the normal visual-regression flow — an a11y fix
  is not a licence to ship an unreviewed pixel diff.
- The **Lighthouse floors** (`make.lighthouse_desktop` / `make.lighthouse_mobile`,
  gated by `capabilities.lighthouse`) still hold at `quality.lighthouse_desktop`
  `95` and `quality.lighthouse_mobile` `85`. An accessible-by-default fix must
  stay within the performance budget; it does not get to regress the score.

The audit loop states this explicitly: a WCAG match never waives the
visual-regression gate or the performance floors that follow it. All gates must be
green together.

## Capability gating: static-only versus dynamic probing

The gate always runs, but *how much* of it runs is controlled by the profile so
the plugin behaves correctly across a React SPA, a Next.js app, and a
Storybook-first component library that may not boot a full stack. Two capability
flags and two `make.*` targets decide the lanes:

- **`capabilities.dynamic_a11y_testing`** gates live-browser probing (axe-core on
  the rendered DOM, keyboard-only traversal, accessibility-tree queries, and —
  when `framework.router` is set — route-change focus and live-region checks). It
  pairs with **`make.start`** the way `capabilities.load_testing` pairs with its
  load target: dynamic probing runs only when the flag is `true` **and**
  `make.start` is non-null so a stack can boot. The orchestrator prefers the
  production-parity build via **`make.start_prod`** for the authoritative dynamic
  pass when one exists.
- **`capabilities.accessibility_audit`** gates the bundled axe / ARIA tool lane.

Degrade paths are always **skip-with-note**, never a loop and never a hard fail:

- `capabilities.dynamic_a11y_testing: false` **or** `make.start: null` (or a stack
  that stays unreachable) ⇒ dynamic probing is skipped with a note; the static
  JSX / ARIA / semantic-HTML lanes still run, and the static-determinable classes
  stay promotable by deterministic in-tree demonstration.
- `capabilities.accessibility_audit: false` ⇒ the bundled axe / ARIA tool lane is
  skipped with a note, but the source-level JSX/ARIA audit still runs over
  `architecture.source_root` so every family still gets an explicit verdict.
- `make.a11y: null` ⇒ the plugin substitutes its bundled static lane — the
  jsx-a11y / ARIA rules via the target mapped by `make.lint_eslint`, the axe
  static-rule pass, and ARIA-pattern + semantic-HTML inspection — and adds no
  dynamic dependency.

The crucial invariant: the **source-level static audit always runs and the gate
always applies**. Degrading dynamic probing narrows the evidence the auditor can
gather (a contrast ratio needing computed styles cannot be promoted static-only),
but it never turns the gate off and never lets a static-determinable barrier
slip. On a library repo with no dev server, the gate still audits and still
blocks on what it can prove in-tree.

Findings are published to a PR only when `capabilities.publish_pr_comments` is
`true`: the loop projects its promoted findings to the accessibility review
ledger and posts one consolidated, idempotent comment through the target mapped by
`make.post_review_findings` (the plugin substitutes its bundled poster when that
key is `null`). Publishing is opt-in and degrades with a note; it never fails the
audit loop.
