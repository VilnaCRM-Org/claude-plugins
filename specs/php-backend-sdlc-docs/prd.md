# PRD — php-backend-sdlc documentation

## Functional requirements

- **FR-1 — README on-ramp.** The plugin README states what the plugin
  is, prerequisites, install, a 2-command quickstart, a command table,
  and a "Documentation" section linking the wiki Home and every existing
  `docs/*.md`. The root README links the plugin and its wiki.
- **FR-2 — Wiki landing + nav.** `Home.md` gives the pitch, install,
  quickstart, and a categorized link grid to every page. `_Sidebar.md`
  lists all pages grouped (Start here / Reference / Deep dives /
  Operate / Contribute). `_Footer.md` carries repo + issue links.
- **FR-3 — Getting started.** A page covers prerequisites, install, the
  six `/sdlc-setup` steps, and a first end-to-end run, cross-linking the
  setup-walkthrough and profile pages.
- **FR-4 — Commands reference.** Every one of the 8 commands documented:
  stage, purpose, inputs, outputs/artifacts, flags, exit/loop behavior,
  one example, and which agents/skills it drives.
- **FR-5 — Agents reference.** Every one of the 7 agents documented:
  role, when dispatched (by which command/stage), tools, inputs, output
  contract, and its hard constraints (no-suppression, container-only…).
- **FR-6 — Skills reference.** All 23 skills + the 2 meta-guides
  (`AI-AGENT-GUIDE`, `SKILL-DECISION-GUIDE`) documented, grouped by
  theme, each with purpose, trigger, and profile keys consumed; includes
  the applicability-triage model.
- **FR-7 — Concept pages.** Architecture (how commands→agents→skills+
  profile compose), the SDLC loop (stages/gates/loop-backs/resume),
  security audit, review & quality gates, PR-comment publishing, the
  degrade matrix, permissions, testing/validation.
- **FR-8 — Glossary + FAQ + troubleshooting.** A glossary of every term
  (BMAD, Ralph, bmalph, FR/NFR, profile, lens, triage, degrade, breaker,
  raise-only, MSI, deptrac, psalm, infection, container-only), an FAQ,
  and a troubleshooting page mapping symptoms → causes → fixes.
- **FR-9 — Publish mechanism.** `scripts/publish-wiki.sh` mirrors
  `plugins/php-backend-sdlc/wiki/` → the wiki remote; the one-time UI
  seed is documented in Getting-Started/Contributing.

## Non-functional requirements

- **NFR-1 — Accuracy.** Every documented flag/behavior/path is verified
  against plugin source. No invented surface. Reviewer lens enforces.
- **NFR-2 — Navigability.** From any page a reader can reach any other in
  ≤2 clicks (sidebar + in-body cross-links). Every page has a
  breadcrumb/"See also".
- **NFR-3 — Link integrity.** 100% of internal links resolve
  (link-checker gate). No orphan pages (each reachable from `_Sidebar`).
- **NFR-4 — Lint clean.** `markdownlint-cli2` passes under the repo
  config for all new `plugins/**/*.md`.
- **NFR-5 — No duplication.** Reference depth lives once (in `docs/*.md`);
  wiki narrates and links to it.
- **NFR-6 — Engineer-readable.** Concrete examples, tables over prose
  where it helps, consistent voice, no marketing fluff.

## Acceptance

A review loop scores each page on accuracy, structure, cross-links, and
clarity; iterate until a round yields zero new findings. Link-check and
markdownlint must be green. README↔wiki links verified bidirectional.
