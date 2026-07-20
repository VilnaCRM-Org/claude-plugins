# Design: `react-frontend-sdlc` Claude Code Plugin

Date: 2026-07-01
Status: Approved (frontend twin of `php-backend-sdlc`; requirements derived from the /goal directive)

## 1. Problem

VilnaCRM's `crm` SPA template carries the same repo-locked AI engineering setup its
backend siblings do — but for a completely different stack:

- A large `.claude/skills/` set (frontend component work, quality/metrics gates,
  testing, performance/a11y, observability, docs, BMAD gates…) plus governance docs
  (`AGENTS.md`, `CLAUDE.md`, `SKILL-DECISION-GUIDE.md`, `AI-AGENT-GUIDE.md`)
- BMAD method install (`_bmad/` with bmm agents + 4-phase workflows) driven by `bmalph`
- The Ralph autonomous implementation loop (`.ralph/` — claude-code driver, circuit
  breaker, quality gates)
- PR governance: sharded CI (static/mutation/performance), CodeRabbit + Claude review,
  `make ci`, an FR/NFR review gate, and hard visual-regression / Lighthouse / metrics gates

`php-backend-sdlc` already packages this shape for PHP backends. But a React frontend
diverges on almost every axis — the toolchain is Jest + Playwright (E2E **and** visual) +
Stryker + Lighthouse + k6 + memlab, the domain is React 18 + TypeScript + Material UI v7 +
Emotion + Zustand + tsyringe + React Router, and — the load-bearing difference — the primary
non-functional risk is **accessibility**, not API security. None of this is installable
elsewhere: `crm`, its component libraries, and any Next.js app born in the org copy files by
hand and edit out repo specifics.

**Goal:** package the frontend setup as a repeatable Claude Code plugin — the frontend twin of
the backend one — that automates React engineering end-to-end. A user installs the plugin,
describes a task in a few sentences, and `/fe-sdlc` drives the full SDLC: GitHub issue → BMAD
planning → bmalph/Ralph implementation → multi-skill review + BMAD FR/NFR gate **plus a
mandatory WCAG 2.2 AA accessibility gate** → visual/E2E/Lighthouse QA → CI auto-fix → resolution
of every AI reviewer comment → finished PR, looping with self-criticism until everything is
green and no new findings appear.

## 2. Approaches considered

| | Approach | Trade-offs |
|---|---|---|
| A | **Thin orchestrator** — plugin ships only SDLC commands/agents, delegates to skills already in the target repo | Smallest surface, but not repeatable: fresh repos have no skills, so the core goal fails (same dead end as the backend twin's A) |
| B | **Profile-driven full bundle (chosen)** — one plugin shipping generalized skills + SDLC orchestrator + agents + BMAD/bmalph bootstrap, parameterized by a per-repo profile so ONE plugin serves every React repo shape | Single install works on a React SPA, a Next.js app, and a component library alike; marketplace layout leaves room to split later |
| C | **Per-stack plugins** — separate `react-spa-sdlc`, `nextjs-sdlc`, `component-library-sdlc` | Maximum stack fit, but 3× packaging/CI/review overhead and drifting triplicated machinery; the profile already absorbs the divergence, so nothing forces the split (YAGNI) |

**Decision: B.** One plugin, `plugins/react-frontend-sdlc/`, in the existing marketplace repo
`VilnaCRM-Org/claude-plugins` next to `php-backend-sdlc`. The single plugin is proven to serve
three deliberately divergent targets — a React SPA (RSBuild/bun, `src/modules`, full `make ci`),
a Next.js app (pnpm, no jscpd/metrics gates, no Stryker), and a Storybook-first component library
(bun, no bootable app, no aggregate `ci` target) — entirely through its project profile.

## 3. Architecture

```text
claude-plugins/                            # marketplace repo (shared with php-backend-sdlc)
├── .claude-plugin/marketplace.json        # lists both plugins
├── plugins/react-frontend-sdlc/
│   ├── .claude-plugin/plugin.json         # name, version, description, author, keywords
│   ├── commands/                          # 8 SDLC slash commands (thin; delegate to skills/agents)
│   │   ├── fe-sdlc.md                      # /fe-sdlc "<task|issue>" — full gated 7-stage loop
│   │   ├── fe-sdlc-setup.md               # bootstrap: preflight, profile, governance, permissions, companions
│   │   ├── fe-sdlc-issue.md               # create/adopt GitHub issue (react-frontend-sdlc label)
│   │   ├── fe-sdlc-plan.md                # BMAD planning (brief → PRD → architecture → stories)
│   │   ├── fe-sdlc-implement.md           # bmalph implement + bmalph run (claude-code driver)
│   │   ├── fe-sdlc-review.md              # 3-lens review + FR/NFR gate + MANDATORY a11y gate
│   │   ├── fe-sdlc-qa.md                  # visual + E2E + Lighthouse + axe QA verdict
│   │   └── fe-sdlc-finish-pr.md           # CI auto-fix + resolve every AI reviewer comment
│   ├── agents/                            # 7 subagents
│   │   ├── react-implementer.md           # modular-React implementation agent
│   │   ├── code-quality-reviewer.md       # skill-driven quality/polish lens
│   │   ├── fr-nfr-reviewer.md             # BMAD spec-compliance reviewer
│   │   ├── accessibility-auditor.md       # per-WCAG-family a11y lens (verify-by-reproduction)
│   │   ├── qa-visual-tester.md            # black-box visual/E2E/Lighthouse/axe QA
│   │   ├── ci-fixer.md                    # iterates failing GitHub checks to green
│   │   └── pr-comment-resolver.md         # fetches + addresses AI reviewer comments
│   ├── skills/                            # 19 generalized skills + 2 meta-guides (AI-AGENT / SKILL-DECISION)
│   ├── scripts/                           # 10 helpers (setup, profile gen/validate, review machinery, lib/common.sh)
│   ├── docs/                              # profile schema, sdlc-loop, accessibility-gate, companion-skills, degrade-matrix…
│   └── tests/fixtures/                    # stub-repo + profile fixtures for the bats suite
├── docs/superpowers/specs/                # this design
└── .github/workflows/                     # marketplace CI (see §5)
```

### Generalization strategy (skills)

Every command, agent, and skill is parameterized by a **project profile** —
`.claude/react-sdlc.yml` in the target repo, generated by `/fe-sdlc-setup`
(`scripts/generate-profile.sh`) and validated by `scripts/validate-profile.sh` before every
stage. Instead of hardcoding `crm`/MUI/`src/modules`, skills resolve concrete facts through
four profile sections: a `make.*` **logical→actual target map** (`make.ci`, `make.test_visual`,
`make.lighthouse_mobile`, `make.a11y`…), `capabilities.*` **opt-in flags**
(`visual_testing`, `lighthouse`, `mutation_testing`, `dynamic_a11y_testing`…),
`framework.*` (`ui: mui-v7`, `state: zustand`, `router`, `bundler`, `package_manager`), and
`architecture.*` (`source_root`, `modules`, `component_prefix`, `path_aliases`). A skill lists
its `## Profile keys consumed`; a `profile-keys-check` lint greps that list against the schema.

This is what lets one plugin serve three divergent repos. `generate-profile.sh` is
repo-shape-agnostic: multi-candidate target detection picks the first Makefile target that
exists per logical key, and it detects a flat component library (no `src/modules`, no `ci`
target, Storybook-first) as readily as a full SPA. `validate-profile.sh` is library-tolerant:
`architecture.modules` MAY be empty, an explicit `make.<key>: null` is legal (**capability
absent**, not a mistake), and `ci.provider: null` means "no CI" — but a **missing** required key
is still a violation, so "absent capability" and "forgot to declare" stay distinct. Thresholds
are **raise-only**: `quality.*` floors (coverage, MSI, Lighthouse) may be tightened, never
lowered; ceilings (`eslint_errors`, `visual_diffs`, …) ship at `0` and stay there.

### SDLC loop (the `/fe-sdlc` command)

```text
/fe-sdlc "<few-sentence task | issue URL>"
 0. setup-check → validate-profile.sh + setup-preflight.sh; HALT → /fe-sdlc-setup (never auto-gen in-loop)
 1. issue       → gh issue create/adopt (label react-frontend-sdlc; durable dedup, resumable)
 2. plan        → BMAD: brief → PRD → architecture → epics/stories → readiness PASS
 3. implement   → bmalph implement → bmalph run --driver claude-code (Ralph), parallel react-implementers
 4. review      → code-quality-reviewer + fr-nfr-reviewer + accessibility-auditor (a11y ALWAYS dispatched);
                  exit only when 0 new FR/NFR findings AND a11y gate clean AND every quality threshold met
 5. qa          → qa-visual-tester on make.start_prod: Playwright E2E + visual-regression + Lighthouse + axe
 6. finish-pr   → open PR; ci-fixer loops checks green; pr-comment-resolver clears every AI review comment
```

Stages have **gated transitions** — `/fe-sdlc` re-verifies each exit condition itself (re-reads
the issue, re-checks `readiness.md`, re-runs the review/a11y gate, re-runs `gh pr checks`) rather
than trusting a stage's own success claim. The run is **resumable** (stage detected from durable
artifacts, never restarted) and always ends in exactly one of two states — **SUCCESS** or
**ESCALATED**. A stage-5 QA FAIL routes back to stage 3, consuming its remaining budget.

The **mandatory accessibility gate** is the headline difference from the backend twin. Where
the PHP plugin runs an OWASP/CWE security deep-audit over an API, this one runs a **WCAG 2.2 AA
deep-audit over the rendered UI** and makes it non-negotiable. It gates two stages: stage 4
(the `accessibility-auditor` lens is *always* dispatched, never triaged NOT-APPLICABLE, and a
verified violation blocks the verdict — it never silently defers to QA) and stage 5 (the axe-core
lane must pass at **0 violations** or QA FAILs). Every candidate is held to a
**verify-by-reproduction** bar: an axe/jsx-a11y/ARIA hit is promoted to a finding only when
reproduced against the running stack or deterministically demonstrated in-tree (a missing `alt`,
an unassociated label, a wrong `<html lang>`, a positive `tabindex`) — no false positives. Fixes
are root-cause and accessible-by-default (semantic HTML, the right ARIA pattern, the correct MUI
slot), each carrying a failing-then-passing regression test located by user-facing semantics. An
a11y match **never** waives the visual-regression gate (`quality.visual_diffs: 0`) or the
Lighthouse floors — all gates stay green together.

Exit condition: CI green, no unresolved AI review comments, FR/NFR gate pass, a11y gate clean,
QA pass, docs/specs/tests updated.

### External dependencies

`bmalph` (npm), the `claude` CLI, the `gh` CLI, and Docker + `make` in the target repo — the
plugin **wraps, never vendors** bmalph/Ralph, and `/fe-sdlc-setup` preflights versions and runs
`bmalph init`. The frontend toolchain (Jest, Playwright, axe-core, Lighthouse, Stryker) lives in
the target repo and is reached only through `make.*` targets, never host binaries. The optional
[ui-skills.com](https://www.ui-skills.com/skills/) design/motion/a11y companion suite is
**referenced, not bundled** (mixed/unknown license): `docs/companion-skills.md` catalogs it with
a Tailwind→MUI translation, and `scripts/install-companion-skills.sh` installs only the
absent ones on demand into the user config dir — never the repo tree, never a build dependency.

## 4. Error handling

- Every loop stage has an explicit failure path: a per-stage `MAX_ITERATIONS=5` guard (counters
  survive loop-backs, never reset) then escalate to the user with the canonical
  `=== SDLC ESCALATION ===` block instead of spinning.
- Ralph's circuit breaker is **surfaced, never reset, restarted-around, or tampered with** — a
  trip inside stage 3 is terminal for the run and a human-attention signal.
- **Capability gaps are not errors.** A `false` capability flag or a `make.<key>: null` degrades
  the dependent lane to **skip-with-a-note** (SUCCESS-WITH-REPORT), never a hard fail — a
  Storybook-first library with no bootable app skips the Lighthouse/visual/dynamic-a11y lanes
  but its static a11y audit still runs and still blocks. Only guard breaches, breaker trips, and
  preflight/profile-validation failures ever produce ESCALATED/HALTED.
- The accessibility gate holds even when degraded: static-determinable barriers stay promotable
  in-tree with no running stack, so on a repo with no dev server the gate still audits and blocks.
- Skills keep the root-cause rule: no `eslint-disable`/`jsx-a11y` disables, no axe suppressions
  or baselines, no `@ts-ignore`, never a lowered threshold. The forbidden-suppression scan runs
  over the diff and `make.ci` runs at loop close as the safety net.

## 5. Testing

- **Plugin CI (marketplace repo, seven jobs):** JSON validation (plugin.json, marketplace.json),
  `manifest-validate` (name/source/semver/tag agreement), markdown lint, `shellcheck` + `bats`
  over the ten scripts, frontmatter schema check for every command/agent/skill, the
  `profile-keys-check` generalization lint, and a denylist gate (no hardcoded repo names inside
  the plugin tree — this repo-root design doc is exempt).
- **Fixtures:** `tests/fixtures/stub-repo/` (a synthetic React repo) plus profile fixtures
  (`valid.yml`, `missing-key.yml`, `lowered-threshold.yml`, `raised-ceiling.yml`, …) exercise
  `generate-profile.sh` detection and `validate-profile.sh` accept/reject paths, including the
  library-tolerant and raise-only cases.
- **QA:** install the plugin from the local marketplace, verify commands/agents/skills load, and
  dry-run `/fe-sdlc-setup` against each of the three reference repo shapes (SPA, Next.js app,
  component library) to prove one profile-driven loop covers all three.
- **Spec gate:** the BMAD FR/NFR review gate run against the plugin's own BMAD specs.

## 6. Non-goals (YAGNI)

- No rewrite of the Ralph engine or the bmalph CLI — the plugin wraps them.
- No bespoke accessibility engine — the gate orchestrates axe-core / jsx-a11y / Playwright a11y
  probing, it does not reimplement them.
- No non-React frontend stacks in v1 (the plugin already spans SPA / Next.js / component library
  via the profile; other frameworks are future marketplace siblings).
- No bundling of the third-party ui-skills.com companions (mixed license) — referenced and
  installed on demand only.
- No GitHub App / hosted service; everything runs through the user's local CLIs.
- No support for non-Claude AI review agents in v1 (`review.ai_review_agents` entries other than
  `claude` warn-and-skip); skills stay markdown-portable regardless.

## 7. Delivery

Feature branch in `VilnaCRM-Org/claude-plugins` adding `plugins/react-frontend-sdlc/`, PR linked
to the bootstrap issue, gated by the marketplace CI from §5 with CodeRabbit + Claude review
enabled. BMAD planning artifacts live in `specs/` of the repo. Releases bump the manifest
`version` (semver: MAJOR on a `schema_version` bump or command-contract break, MINOR on a new
skill/command/agent/profile key, PATCH otherwise) and tag in the plugin's own namespace
`react-frontend-sdlc-vX.Y.Z` via `claude plugin tag react-frontend-sdlc`, which
`manifest-validate` re-checks on the tag build. v1 ships a relative marketplace source (installers
track `main`); at the first external consumer or v1.0.0 the entry switches to a pinned
`git-subdir` `ref`/`sha`. Quality thresholds are **raise-only across releases** — a release may
tighten a gate, never relax one, and `validate-profile.sh` rejects any profile that tries.
