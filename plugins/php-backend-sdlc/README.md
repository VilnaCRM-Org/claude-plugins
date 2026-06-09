# php-backend-sdlc

Full-SDLC automation for PHP backend engineering as a Claude Code
plugin: GitHub issue creation, BMAD-method planning, bmalph/Ralph
autonomous implementation, multi-skill code review with an FR/NFR gate,
black-box QA, CI auto-fix, and AI review-comment resolution — looping
until the PR is finished.

## Requirements

Checked by `/sdlc-setup` preflight (each failure prints a named
remediation):

- a git repository (your PHP backend project)
- Claude Code CLI ≥ 2.1
- GitHub CLI ≥ 2, authenticated (`gh auth login`)
- bmalph ≥ 2.11.0
- `yq`, or `python3` with PyYAML

## Install

```bash
claude plugin marketplace add VilnaCRM-Org/claude-plugins
claude plugin install php-backend-sdlc@vilnacrm-plugins
```

## Quickstart

```bash
cd your-php-backend-repo

# one-time: preflight, project profile, governance blocks, permissions
/sdlc-setup

# then run the whole loop for a task
/sdlc "Add a Currency resource with code and name fields and REST CRUD endpoints"
```

`/sdlc-setup` detects your repository's facts into
`.claude/php-sdlc.yml` — the [project profile](docs/profile-schema.md)
that generalizes every command, agent, and skill to your codebase. All
quality thresholds it carries are raise-only; see the
[schema reference](docs/profile-schema.md) for every key.

## Commands

| Command | Stage | Purpose |
| --- | --- | --- |
| `/sdlc` | all | End-to-end orchestrator with gated stage transitions and resumability |
| `/sdlc-setup` | 0 | Preflight, profile generation/validation, governance blocks, permissions |
| `/sdlc-issue` | 1 | Task text → labeled GitHub issue with testable acceptance criteria |
| `/sdlc-plan` | 2 | Non-interactive BMAD planning chain → six artifacts under `specs/<slug>/` |
| `/sdlc-implement` | 3 | bmalph/Ralph implementation, parallel story dispatch, breaker safety |
| `/sdlc-review` | 4 | 21-skill triage, multi-lens review, FR/NFR gate loop |
| `/sdlc-qa` | 5 | Black-box HTTP verification against the acceptance criteria |
| `/sdlc-finish-pr` | 6 | PR creation, CI-fix loop, comment-resolution loop |

Commands delegate to six subagents (php-implementer,
code-quality-reviewer, fr-nfr-reviewer, qa-manual-tester, ci-fixer,
pr-comment-resolver) and a 21-skill library with applicability triage.

## Documentation

- [Project profile schema](docs/profile-schema.md) — every
  `.claude/php-sdlc.yml` key, defaults, enums, raise-only rules
- [The SDLC loop](docs/sdlc-loop.md) — stage diagram, exit conditions,
  iteration guards, loop-backs
- [Permissions](docs/permissions.md) — acceptEdits default, the
  settings.json allowlist, bypassPermissions policy
- [Degrade matrix](docs/degrade-matrix.md) — behavior when a capability
  is missing (no CI, no reviewer app, missing make targets, …)
- [Release process](docs/release-process.md) — versioning, tags,
  changelog, marketplace pinning
