# Product Brief — php-backend-sdlc documentation

## Problem

The `php-backend-sdlc` plugin is large (8 commands, 7 agents, 23 skills +
2 meta-guides, a profile schema, a 7-stage loop, a PR-comment publisher).
Today its only narrative is a 3 KB README plus six reference docs under
`docs/`. A new engineer cannot answer, quickly: *what does it do, how do
the pieces fit, how do I run it, what does each command/agent/skill do,
and how do I recover when something degrades?* There is no navigable
overview and no wiki.

## Audience

- **Primary:** a backend engineer evaluating or adopting the plugin on a
  PHP/Symfony service — needs install, quickstart, and a mental model.
- **Secondary:** a contributor extending the plugin — needs the
  architecture, the skill/agent contracts, and the testing/release flow.
- **Tertiary:** an operator running `/sdlc` in CI/agentic loops — needs
  the degrade matrix, permissions, and troubleshooting.

## Goal

Detailed, convenient, cross-linked documentation on two surfaces:

1. **README** (plugin + root) — a fast on-ramp that routes into the wiki.
2. **GitHub Wiki** — the complete reference, one page per major area,
   navigable from any page via a sidebar.

## Success criteria

- An engineer new to the plugin can install, run a first task, and locate
  any command/agent/skill's behavior without reading source.
- Every command/agent/skill is documented accurately (verified against
  source — no invented flags/behaviors).
- All internal links resolve; README and wiki are mutually linked.
- Existing `docs/*.md` are cross-linked, not duplicated.
- `markdownlint-cli2` passes; a review loop reaches zero new findings.

## Constraints

- GitHub wiki must be seeded once via the UI before its `.wiki.git`
  remote accepts a push — so wiki content is authored in-repo under
  `plugins/php-backend-sdlc/wiki/` (CI-linted) and mirrored by a
  `publish-wiki.sh` script.
- Markdown must satisfy the repo `.markdownlint.yaml` (MD013 off).
- Dual-context links: wiki-internal links use sibling `Page.md` form
  (resolves both in the PR file view and on the published wiki);
  links into repo `docs/*.md` use absolute GitHub blob URLs.

## Non-goals

- Rewriting the existing `docs/*.md` reference pages (link to them).
- Documenting target-repo (user-service) specifics.
