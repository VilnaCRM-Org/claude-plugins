# react-frontend-sdlc

Full-SDLC automation for React + TypeScript frontend engineering as a
Claude Code plugin: GitHub issue creation, BMAD-method planning,
bmalph/Ralph autonomous implementation, multi-skill code review with an
FR/NFR gate and a mandatory accessibility gate, black-box visual / E2E /
Lighthouse QA, CI auto-fix, and AI review-comment resolution — looping
until the PR is finished.

The frontend twin of `php-backend-sdlc`: same staged loop, gates, and
guards, retargeted to a React 18 + TypeScript + Material UI v7 + Emotion
SPA (Zustand, React Router v6, tsyringe DI, react-i18next, RSBuild, Bun).

## Requirements

Checked by `/fe-sdlc-setup` preflight (each failure prints a named
remediation):

- a git repository (your React/TypeScript frontend project)
- Claude Code CLI ≥ 2.1
- GitHub CLI ≥ 2, authenticated (`gh auth login`)
- bmalph ≥ 2.11.0, and a healthy `_bmad/` workspace when one already
  exists (`bmalph doctor`; fresh repos are bootstrapped by
  `/fe-sdlc-setup`)
- Bun ≥ 1.3.5 (dependency manager) and Node.js ≥ 24.8.0 (runtime)
- Docker — the dev, test, lint, and Lighthouse stack runs in containers
  through the project's Make targets
- `yq`, or `python3` with PyYAML

## Install

```bash
claude plugin marketplace add VilnaCRM-Org/claude-plugins
claude plugin install react-frontend-sdlc@vilnacrm-plugins
```

## Quickstart

```bash
cd your-react-frontend-repo

# one-time: preflight, project profile, governance blocks, permissions
/fe-sdlc-setup

# then run the whole loop for a task
/fe-sdlc "Add a UICurrencyField component with validation, wire it into the sign-up form, and cover it with unit, E2E, and visual tests"
```

`/fe-sdlc-setup` detects your repository's facts into
`.claude/react-sdlc.yml` — the [project profile](docs/profile-schema.md)
that generalizes every command, agent, and skill to your codebase
(framework, source root, modules, path aliases, Make-target map, and
quality floors). All quality thresholds it carries are raise-only; see
the [schema reference](docs/profile-schema.md) for every key.

## Commands

| Command | Stage | Purpose |
| --- | --- | --- |
| `/fe-sdlc` | all | End-to-end orchestrator with gated stage transitions and resumability |
| `/fe-sdlc-setup` | 0 | Preflight, profile generation/validation, governance blocks, permissions |
| `/fe-sdlc-issue` | 1 | Task text → labeled GitHub issue with testable acceptance criteria |
| `/fe-sdlc-plan` | 2 | Non-interactive BMAD planning chain → artifacts under `specs/<slug>/` |
| `/fe-sdlc-implement` | 3 | bmalph/Ralph implementation, parallel story dispatch, breaker safety |
| `/fe-sdlc-review` | 4 | Skill triage, multi-lens review, FR/NFR + accessibility gate loop |
| `/fe-sdlc-qa` | 5 | Black-box visual + E2E + Lighthouse + a11y verification against the acceptance criteria |
| `/fe-sdlc-finish-pr` | 6 | PR creation, CI-fix loop, comment-resolution loop |

Commands delegate to seven subagents (react-implementer,
code-quality-reviewer, fr-nfr-reviewer, qa-visual-tester, ci-fixer,
pr-comment-resolver, accessibility-auditor) and an 18-skill library with
applicability triage — `skills/AI-AGENT-GUIDE.md` and
`skills/SKILL-DECISION-GUIDE.md` decide which skills load per task and
require every skill verdict to be recorded (no silent skips). The library
spans architecture, code organization, complexity, frontend component
development, quality, testing, performance/accessibility, CI, review,
documentation, observability, load testing, Figma design check, plus the
BMAD planning and FR/NFR-gate skills.

Companion skills (optional): when the profile's `companion.skills` /
`companion.agents` are set, the review and QA agents additionally lean on
your globally installed [ui-skills.com](https://www.ui-skills.com/skills/)
design, motion, and accessibility skill suite (translated from Tailwind /
shadcn guidance to MUI's `sx`, `styled()`, and theme) and a11y review
agents; `companion.install_command` records how to install them. They are
an enhancement, never a hard dependency — every gate runs without them.

## Documentation

- [`/fe-sdlc-setup` walkthrough](docs/setup-walkthrough.md) — the setup
  steps, what each produces, `--refresh` semantics, and what a failing
  preflight looks like with its remediation
- [Project profile schema](docs/profile-schema.md) — every
  `.claude/react-sdlc.yml` key, defaults, enums, raise-only rules
- [The SDLC loop](docs/sdlc-loop.md) — stage diagram, exit conditions,
  iteration guards, and the QA → implement loop-back
- [Permissions](docs/permissions.md) — acceptEdits default, the
  settings.json allowlist, bypassPermissions policy
- [Degrade matrix](docs/degrade-matrix.md) — behavior when a capability
  is missing (no CI, no reviewer app, no Lighthouse/visual/mutation, missing
  Make targets, …)
- [Release process](docs/release-process.md) — versioning, tags,
  changelog, marketplace pinning
