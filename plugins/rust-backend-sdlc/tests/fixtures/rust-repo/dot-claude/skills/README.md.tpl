# Skills

This directory holds the procedures an AI coding assistant follows. This file is the only skill inventory.

## Quick Start

Read `AGENTS.md`, then `AI-AGENT-GUIDE.md`, then `SKILL-DECISION-GUIDE.md`, then the `SKILL.md` of the matching skill, and follow it before claiming completion.

## Skills

- `api-resource-development`: adding or changing a REST or GraphQL operation, a command, a query, an event subscriber or a migration.
- `verification-workflow`: running the repository checks and fixing a failing gate before declaring completion.
- `complexity-management`: the complexity gate fails or a function approaches a limit.
- `architecture-boundary-fixer`: `make architecture` reports a violation or code moves between layers or contexts.
- `documentation-sync`: a change affects a command, an environment variable, an endpoint, a workflow or the guidance.
- `load-testing`: adding, changing or running a K6 scenario or a latency budget.
- `api-contract-development`: the REST or GraphQL contract changes or a contract gate fails.
- `quality-standards`: the list of gates with thresholds, Make targets and protected files.
- `architecture-model-sync`: a crate, bounded context, external dependency or relationship is added or removed.
- `testing-workflow`: writing, running or debugging tests at any level.
- `bmad-autonomous-planning`: producing a BMAD planning bundle from a short task description without interactive menus.

## Scope

Skills are guidance only. They name Make targets and paths, never copy the verification list, and state thresholds only in `quality-standards`. The rules of the repository are in `AGENTS.md`.
