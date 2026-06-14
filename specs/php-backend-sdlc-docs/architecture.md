# Information Architecture — php-backend-sdlc documentation

## Surfaces

- **Plugin README** — `plugins/php-backend-sdlc/README.md` (expand).
- **Root README** — `README.md` (add wiki links).
- **Wiki source** — `plugins/php-backend-sdlc/wiki/*.md` (new). Authored
  in-repo (CI-linted), mirrored to the GitHub wiki by
  `plugins/php-backend-sdlc/scripts/publish-wiki.sh`.

## Link conventions (dual-context)

- Wiki page → wiki page: sibling relative `[Title](Page-Name.md)` — works
  in the PR file view AND on the published wiki.
- Wiki/README → repo reference doc: absolute GitHub blob URL
  `https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/<file>.md`.
- README → wiki Home: absolute wiki URL
  `https://github.com/VilnaCRM-Org/claude-plugins/wiki/Home` plus the
  in-repo source path for browsing.

## Canonical page manifest

Slugs are exact filenames under `plugins/php-backend-sdlc/wiki/`.

| Slug | Title | Purpose | Grounding sources |
| --- | --- | --- | --- |
| `Home.md` | Home | Pitch, install, quickstart, link grid to all pages | README, plugin.json |
| `_Sidebar.md` | (nav) | Grouped nav of every page | this manifest |
| `_Footer.md` | (footer) | Repo, issues, license links | plugin.json |
| `Getting-Started.md` | Getting Started | Prereqs, install, the 6 setup steps, first run | README, docs/setup-walkthrough.md, commands/sdlc-setup.md |
| `Concepts-and-Glossary.md` | Concepts & Glossary | Define every term + the mental model | AI-AGENT-GUIDE.md, SKILL-DECISION-GUIDE.md, all SKILL.md headers |
| `Architecture.md` | Architecture | How commands→agents→skills+profile compose; design principles | AI-AGENT-GUIDE.md, SKILL-DECISION-GUIDE.md, plugin.json, dir layout |
| `The-SDLC-Loop.md` | The SDLC Loop | 7 stages, gates, loop-backs, exit conditions, resume | docs/sdlc-loop.md, commands/sdlc.md |
| `Commands.md` | Commands | All 8 commands in detail | commands/*.md |
| `Agents.md` | Agents | All 7 subagents + contracts | agents/*.md |
| `Skills.md` | Skills | All 23 skills + 2 meta-guides, grouped; triage model | skills/*, SKILL-DECISION-GUIDE.md, AI-AGENT-GUIDE.md |
| `Project-Profile.md` | Project Profile | `.claude/php-sdlc.yml` schema overview + link to full ref | docs/profile-schema.md, commands/sdlc-setup.md |
| `Security-Audit.md` | Security Audit | OWASP red-team loop, boundaries, dynamic testing | skills/security-audit/*, agents/security-auditor.md, docs/testing/security-audit-* |
| `Review-and-Quality-Gates.md` | Review & Quality Gates | code-review + FR/NFR gate + thresholds | skills/code-review, skills/bmad-fr-nfr-review-gate, skills/quality-standards, agents/code-quality-reviewer.md, agents/fr-nfr-reviewer.md |
| `Publishing-PR-Comments.md` | Publishing PR Comments | The poster: lenses→PR comments + conclusion; gating | scripts/post-review-findings.sh, commands/sdlc-review.md, docs/permissions.md |
| `Degrade-and-Resilience.md` | Degrade & Resilience | Capability-missing behavior, breakers | docs/degrade-matrix.md |
| `Permissions.md` | Permissions | Permission model, allowlist, capability opt-ins | docs/permissions.md |
| `Testing-and-Validation.md` | Testing & Validation | How the plugin itself is tested + evidence | docs/testing/*, docs/evidence/*, tools/* |
| `Troubleshooting.md` | Troubleshooting | Symptom → cause → fix table | docs/setup-walkthrough.md, docs/degrade-matrix.md, commands/* |
| `FAQ.md` | FAQ | Short answers to common questions | all of the above |
| `Contributing-and-Releases.md` | Contributing & Releases | Dev, test, release, wiki publish | docs/release-process.md, root README, publish-wiki.sh |

## Cross-link rules (per page)

- Every page opens with one breadcrumb line: `[Home](Home.md) ›
  <Section> › <Page>` and ends with a `## See also` list of 3–5 related
  pages.
- `Home.md` links every content page once in a categorized grid.
- `_Sidebar.md` groups: **Start here** (Home, Getting-Started, Concepts),
  **Reference** (Commands, Agents, Skills, Project-Profile), **Deep
  dives** (Architecture, The-SDLC-Loop, Security-Audit,
  Review-and-Quality-Gates, Publishing-PR-Comments), **Operate**
  (Degrade-and-Resilience, Permissions, Troubleshooting, FAQ), **Build**
  (Testing-and-Validation, Contributing-and-Releases).
- Reference pages (Commands/Agents/Skills/Project-Profile) deep-link into
  the canonical `docs/*.md` for exhaustive detail rather than restating.

## Build/verify pipeline

1. Author pages (one subagent per page, parallel) from grounding sources.
2. Review loop: accuracy vs source, structure, link integrity, clarity
   → fix → repeat until zero new findings.
3. `publish-wiki.sh` lints + mirrors; `markdownlint-cli2` + a link-check
   gate locally; CI `markdown-lint` gates on PR.
