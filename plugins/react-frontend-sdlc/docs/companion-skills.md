# Companion skills and agents — catalog and MUI/Emotion translation

The optional [ui-skills.com](https://www.ui-skills.com/skills/) design, motion,
and accessibility suite is the **companion layer** for this plugin. The plugin's
own skills own **process and gates**; the companions add **technique-level
depth** — the design-engineering, motion, color, and a11y craft that the review
and QA agents lean on when a task needs polish beyond the process skills.

This page is the canonical catalog. It is referenced by:

- `/fe-sdlc-setup` **step 7** (the "Install companion skills" step),
- [`scripts/install-companion-skills.sh`](../scripts/install-companion-skills.sh)
  (the best-effort installer that points here in report-only mode),
- the [`accessibility-audit`](../skills/accessibility-audit/SKILL.md) skill and
  the [`accessibility-auditor`](../agents/accessibility-auditor.md) agent (which
  escalate technique-level remediation to the companion accessibility team), and
- the ["Companion skills and agents"](../skills/AI-AGENT-GUIDE.md) section of the
  AI-agent guide.

The companions are **Tailwind / shadcn-oriented**. The bulk of this page is the
translation of that guidance to this plugin's stack (Material UI, e.g.
`framework.ui: mui-v7`) — express each companion's advice through the MUI theme,
the `sx` prop, `styled()`, and Emotion `keyframes` instead of utility classes.

## Reference-and-auto-install policy

The companion skills and agents are **third-party, mixed / unknown license**.
They are deliberately **not bundled** with this plugin — they are *referenced*
here and *installed on demand*, never vendored into the plugin tree or the target
repository:

- **Not committed.** No companion source ships inside the plugin. This page names
  them and links to ui-skills.com; the install is a separate, opt-in action.
- **User config only.** When installed, they are written **only** under the user
  config directory (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}` — its `skills/` and
  `agents/` subdirectories). The installer **never** touches the target
  repository tree, so companions do not enter any repo's git history or diff.
- **Enhancement, never a dependency.** Every gate in this plugin runs to
  completion **without** the companions. They deepen technique and review
  quality; they never gate a build. A missing companion degrades a review lens to
  "process-only," never to failure.
- **Non-fatal install.** Because they are optional, a failed or skipped install
  is surfaced as a warning and is explicitly outside the `/fe-sdlc-setup` exit
  condition — the setup command continues.

Because `docs/` are exempt from the generalization denylist, this page may name
ui-skills.com and the individual tools directly. Behavior, though, stays
stack-generic: it is described through profile keys (`framework.ui`,
`make.a11y`, `capabilities.accessibility_audit`, `quality.lighthouse_mobile`, …),
never a single hardcoded toolchain.

## How install works

The installer is driven entirely by three profile keys, read from
`.claude/react-sdlc.yml`:

- `companion.skills` — the list of companion **skill** names to ensure present.
- `companion.agents` — the list of companion **agent** names to ensure present.
- `companion.install_command` — the install **mode** (see below).

```yaml # profile-example
companion:
  skills:
    - design-taste-frontend
    - frontend-design
    - make-interfaces-feel-better
    - interaction-design
    - oklch-skill
  agents:
    - accessibility-lead
    - aria-specialist
    - keyboard-navigator
    - contrast-master
    - forms-specialist
  install_command: manual # or a '{name}' template, or 'plugin'
```

### Absent-only

For each listed name, the installer checks the user config dir first and acts
**only on companions that are ABSENT** — a skill present as `skills/<name>/` or
an agent present as `agents/<name>.md` is left exactly as the user has it (reported
as "already present, skipped"). Re-running setup never re-installs or clobbers a
companion you already have.

### Install modes (`companion.install_command`)

The mode value selects how each absent companion is handled:

| `companion.install_command` value        | Behavior for each absent companion                                                                      |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| a template containing `{name}`           | Run the substituted command (`{name}` → the companion name), e.g. `my-fetch-skill {name}`.              |
| `plugin`                                 | Run `claude plugin install {name}` (skipped if the `claude` CLI is absent).                             |
| anything else — **defaults to `manual`** | **Report-only**: list the absent companions and point at this page. Nothing is installed automatically. |

`manual` is the **default** (an unset or unrecognized value is treated as
report-only). Auto-install — the `{name}` template or `plugin` mode — is
**opt-in**: a project that wants hands-off setup declares one of those two forms.
In every mode the installer writes only under the user config dir, and a failed
auto-install is a non-fatal warning.

Run it directly (or let `/fe-sdlc-setup` step 7 run it):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/install-companion-skills.sh"
```

## Catalog

Each companion's guidance below is stated as its **purpose** and its **MUI v7 +
Emotion translation** — how to apply Tailwind / shadcn-shaped advice to a MUI
stack. Read the once-only mapping in
[Translation cheatsheet](#translation-cheatsheet) first; the per-companion rows
build on it.

### Companion skills

| Skill                         | Purpose                                                                                                                                           | MUI v7 + Emotion translation                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `design-taste-frontend`       | Anti-slop design direction: infer the right visual language from the brief, ship interfaces that do not look templated, audit-first on redesigns. | Encode taste in the **theme**, not in ad-hoc utility stacks: `createTheme` palette / typography / shape / spacing tokens, plus `theme.components` `styleOverrides` + `defaultProps`, so every `architecture.component_prefix` primitive inherits the direction. Reserve `styled()` / `sx` for genuine per-instance deviations, never to fork the system. Audit-first = read the existing theme (e.g. `src/styles/theme.ts`) before adding a variant.                   |
| `frontend-design`             | Distinctive, production-grade interfaces that avoid generic AI aesthetics.                                                                        | Build layout with MUI primitives (`Stack`, `Grid`, `Box`) driven by the `theme.spacing` scale rather than utility-class grids; give a view its identity via `styled(Component)` with Emotion template literals that read `theme.palette` / `theme.typography`. Keep all values as theme tokens so light/dark modes and the visual-regression baselines (`make.test_visual`) stay stable.                                                                               |
| `make-interfaces-feel-better` | Micro-polish: hover / focus states, shadows, borders, typography detail, optical alignment, tabular numbers, enter/exit motion.                   | Hover/focus via `sx` pseudo-selectors (`'&:hover'`, `'&:focus-visible'`); elevation via `theme.shadows` tokens, never raw `box-shadow` strings; radius via `theme.shape.borderRadius`; tabular numbers via `fontVariantNumeric: 'tabular-nums'` in `sx` or a typography variant; optical nudges via small `sx` margins; enter/exit via MUI `Fade` / `Grow` / `Collapse` or Emotion `keyframes`. Gate motion on `theme.transitions` and honor `prefers-reduced-motion`. |
| `interaction-design`          | Microinteractions, transitions, loading states, and user feedback.                                                                                | Loading via `Button` `loading` + `loadingIndicator`, `Skeleton`, or `CircularProgress`; feedback via `Snackbar` / `Alert`; transitions via MUI transition components using `theme.transitions.duration` / `easing` tokens; bespoke motion via Emotion `keyframes` inside `styled()`. Keep durations within the animation budgets the visual and a11y lenses check, and expose busy state with `aria-busy` + a polite live region.                                      |
| `oklch-skill`                 | OKLCH color space: convert hex/rgb/hsl to OKLCH, generate perceptually even palettes, check contrast, handle gamut and dark mode.                 | Author palette values in `oklch()` and feed them straight into `createTheme({ palette })` and `colorSchemes` — MUI and Emotion pass any CSS color string through unchanged. Use OKLCH ramps to hit the WCAG contrast ratios the accessibility gate enforces and to keep `palette.primary` / `secondary` tonally consistent across modes; provide an sRGB fallback where a target browser lacks wide-gamut support.                                                     |

### Companion agents

| Agent                | Purpose                                                                                                           | MUI v7 + Emotion translation                                                                                                                                                                                                                                                                                  |
| -------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `accessibility-lead` | Orchestrator of the a11y specialist team — deep, multi-domain accessibility review for any non-trivial UI change. | Coordinates the specialists over MUI usage — correct semantic component slots, `FormControl` wiring, `Dialog` focus management — and routes systemic fixes back into `theme.components` overrides so one correction covers every instance, rather than patching per view.                                     |
| `aria-specialist`    | ARIA roles, states, properties, and authoring-practice patterns.                                                  | Verifies ARIA on MUI components: `aria-label` on icon-only `IconButton`, `role` / `aria-modal` on `Dialog`, live regions, and ARIA forwarded through `slotProps` to the inner DOM node. Prefers a semantic MUI component over a hand-rolled `role` whenever a native element exists.                          |
| `keyboard-navigator` | Keyboard operability, focus order, and focus management.                                                          | Checks tab order and focus trapping in `Menu` / `Dialog` / `Drawer`, a visible `:focus-visible` ring via theme overrides, and the absence of positive `tabindex`; ensures no `sx` rule suppresses the focus outline.                                                                                          |
| `contrast-master`    | Color contrast against WCAG minimums (4.5:1 text, 3:1 large / UI).                                                | Audits `theme.palette` text/background pairs and any `sx` color override against the ratios, including disabled states (`action.disabled` / `action.disabledBackground`). Pairs with `oklch-skill` to fix the ramp **in the theme**, not per instance, and flags design-owner-accepted deviations explicitly. |
| `forms-specialist`   | Form accessibility: label association, error messaging, required semantics.                                       | Validates `TextField` / `FormControl` label association, `helperText` + `error` for messages wired via `aria-describedby`, `aria-invalid` on failure, and required semantics; ensures validation errors are announced through a live region rather than color alone.                                          |

### Translation cheatsheet

The companions speak Tailwind utility classes and shadcn primitives. Map them
once to MUI:

| Companion idiom (Tailwind / shadcn)              | MUI v7 + Emotion equivalent                                                                                  |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| Utility classes (`p-4`, `text-lg`, `flex gap-2`) | `sx` prop with theme-aware values (`sx={{ p: 2, typography: 'h6', display: 'flex', gap: 1 }}`).              |
| `@apply` / extracted component classes           | `styled(Component)` with an Emotion template literal, or a `theme.components.<Name>.styleOverrides` entry.   |
| `tailwind.config` theme tokens                   | `createTheme` — `palette`, `typography`, `spacing`, `shape`, `shadows`, `transitions`, `colorSchemes`.       |
| `dark:` variant                                  | `theme.colorSchemes` / `theme.applyStyles('dark', …)`, or `theme.palette.mode` branches.                     |
| `hover:` / `focus-visible:` variants             | `sx` pseudo-selectors: `'&:hover'`, `'&:focus-visible'`, `'&.Mui-disabled'`.                                 |
| CSS keyframe / transition utilities              | MUI transition components (`Fade`, `Grow`, `Collapse`) or Emotion `keyframes`, timed by `theme.transitions`. |
| shadcn primitive (`<Button>`, `<Dialog>`)        | The MUI counterpart and its `slots` / `slotProps`, kept behind the `architecture.component_prefix` wrapper.  |

```tsx # profile-example
// Tailwind: <button className="rounded-lg px-4 py-2 bg-primary hover:bg-primary/90">
// MUI + Emotion equivalent — tokens from the theme, hover via sx pseudo-selector:
<Button
  variant="contained"
  sx={{
    borderRadius: 2,
    px: 2,
    py: 1,
    '&:hover': { bgcolor: 'primary.dark' },
  }}
/>
```

## Which agents lean on the companions

The companions are invoked by name (Claude Code) or read manually (other agents)
during the review and QA stages — `/fe-sdlc-review` and `/fe-sdlc-qa`. They are
consulted for technique; they never replace a plugin gate.

| Plugin agent            | Companions it leans on                                                                               | When                                                                                                                                                                                                                                                   |
| ----------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `accessibility-auditor` | `accessibility-lead`, `aria-specialist`, `keyboard-navigator`, `contrast-master`, `forms-specialist` | Technique-level remediation for verified WCAG findings in the `accessibility-audit` loop — the auditor finds and verifies; the companion team supplies the deep, multi-domain fix guidance. Gated by `capabilities.accessibility_audit` / `make.a11y`. |
| `code-quality-reviewer` | `make-interfaces-feel-better`, `design-taste-frontend`, `frontend-design`                            | The design-quality / polish lens of the review stage — hover/focus detail, elevation and typography consistency, theme-token discipline over one-off `sx`.                                                                                             |
| `qa-visual-tester`      | `interaction-design`, `make-interfaces-feel-better`, `oklch-skill`                                   | Judging visual-regression and interaction snapshots (`make.test_visual`) — transition timing, motion polish, and color/contrast fidelity of the rendered UI.                                                                                           |
| `fr-nfr-reviewer`       | `accessibility-lead`, `contrast-master`, `frontend-design`                                           | The NFR lens where an accessibility or visual-design non-functional requirement is in scope.                                                                                                                                                           |
| `react-implementer`     | any of the above, as routed                                                                          | Applies the root-cause fix a review or audit lens prescribes, translating the companion's Tailwind-shaped remediation into MUI theme / `sx` / `styled()` code.                                                                                         |

When a companion is not installed, each of these agents falls back to the
plugin's own process skills — the review still runs and still gates; it simply
carries less technique-level depth for that lens.

## See also

- [`../scripts/install-companion-skills.sh`](../scripts/install-companion-skills.sh) — the installer this page documents.
- [`../commands/fe-sdlc-setup.md`](../commands/fe-sdlc-setup.md) — step 7 runs the installer.
- [`../skills/accessibility-audit/SKILL.md`](../skills/accessibility-audit/SKILL.md) — escalates to the companion accessibility team.
- [`../skills/AI-AGENT-GUIDE.md`](../skills/AI-AGENT-GUIDE.md) — the companion-layer overview.
- [`profile-schema.md`](profile-schema.md) — the profile keys referenced throughout this page.
