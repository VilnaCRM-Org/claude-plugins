# php-backend-sdlc

[Home](Home.md) › Start here › Home

Full-SDLC automation for PHP backend engineering, packaged as a Claude
Code plugin. It takes one task description through the entire delivery
loop — GitHub issue creation, BMAD-method planning, bmalph/Ralph
autonomous implementation, multi-skill code review with an FR/NFR gate,
black-box QA, CI auto-fix, and AI review-comment resolution — looping
until the pull request is finished. It is for backend engineers working
on git-tracked PHP repositories who want a gated, resumable, loop-safe
pipeline rather than ad-hoc prompting.

## Install

```bash
claude plugin marketplace add VilnaCRM-Org/claude-plugins
claude plugin install php-backend-sdlc@vilnacrm-plugins
```

## Quickstart

Two commands take you from a clean repository to a running loop. Run
them from inside your PHP backend project:

```bash
cd your-php-backend-repo

# one-time: preflight, project profile, governance blocks, permissions
/sdlc-setup

# then run the whole loop for a task
/sdlc "Add a Currency resource with code and name fields and REST CRUD endpoints"
```

`/sdlc-setup` detects your repository's facts into `.claude/php-sdlc.yml`
— the [project profile](Project-Profile.md) that generalizes every
command, agent, and skill to your codebase. All quality thresholds it
carries are raise-only. `/sdlc` then runs the seven stages end-to-end
with gated transitions; it is resumable and loop-safe, so you can stop
and re-run it. See [Getting Started](Getting-Started.md) for the full
walkthrough and [The SDLC Loop](The-SDLC-Loop.md) for the stage diagram.

## Documentation map

Every wiki page, grouped by what you are trying to do.

### Start here

- [Home](Home.md) — this landing page: pitch, install, quickstart, map.
- [Getting Started](Getting-Started.md) — install, setup, and your first
  loop end to end.
- [Concepts and Glossary](Concepts-and-Glossary.md) — BMAD, Ralph,
  profile, gate, lens, and the rest of the vocabulary.

### Reference

- [Commands](Commands.md) — all 8 slash commands and their stages.
- [Agents](Agents.md) — the 7 subagents the commands delegate to.
- [Skills](Skills.md) — the 22-skill library plus 2 meta-guides.
- [Project Profile](Project-Profile.md) — every `.claude/php-sdlc.yml`
  key, defaults, enums, and raise-only rules.
- [Permissions](Permissions.md) — `acceptEdits` default, the
  `settings.json` allowlist, and the `bypassPermissions` policy.

### Deep dives

- [Architecture](Architecture.md) — how commands, agents, skills, and
  the profile fit together.
- [The SDLC Loop](The-SDLC-Loop.md) — stage diagram, exit conditions,
  iteration guards, and loop-backs.
- [Review and Quality Gates](Review-and-Quality-Gates.md) — the 22-skill
  applicability triage, multi-lens review, and the FR/NFR gate.
- [Security Audit](Security-Audit.md) — the adversarial, authorized
  red-team loop and its capability gating.
- [Degrade and Resilience](Degrade-and-Resilience.md) — behavior when a
  capability is missing (no CI, no reviewer app, missing make targets).

### Operate

- [Publishing PR Comments](Publishing-PR-Comments.md) — how findings and
  resolutions reach the pull request.
- [Troubleshooting](Troubleshooting.md) — common failures and fixes.
- [FAQ](FAQ.md) — quick answers to recurring questions.

### Build

- [Testing and Validation](Testing-and-Validation.md) — the test
  strategy, plans, and recorded evidence runs.
- [Contributing and Releases](Contributing-and-Releases.md) — versioning,
  tags, changelog, and marketplace pinning.

### Repository reference docs

These live in the plugin's `docs/` tree and back the pages above:

- [setup-walkthrough.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/setup-walkthrough.md)
  — the six setup steps, `--refresh` semantics, failing-preflight output.
- [profile-schema.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md)
  — every profile key, defaults, enums, raise-only rules.
- [sdlc-loop.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/sdlc-loop.md)
  — stage diagram, exit conditions, iteration guards, loop-backs.
- [permissions.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/permissions.md)
  — `acceptEdits` default, allowlist, `bypassPermissions` policy.
- [degrade-matrix.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md)
  — missing-capability behavior.
- [release-process.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/release-process.md)
  — versioning, tags, changelog, marketplace pinning.

## Requirements

`/sdlc-setup` preflight checks each item below and prints a named
remediation for every failure:

| Requirement | Notes |
| --- | --- |
| A git repository | Your PHP backend project must be git-tracked. |
| Claude Code CLI ≥ 2.1 | The host this plugin runs in. |
| GitHub CLI ≥ 2, authenticated | Run `gh auth login` first. |
| bmalph ≥ 2.11.0 | A healthy `_bmad/` workspace is required when one already exists (`bmalph doctor`); fresh repos are bootstrapped by `/sdlc-setup`. |
| `yq`, or `python3` with PyYAML | Used to read and write the YAML profile. |
| `jq`, or `python3` | JSON toolchain — parses claude/gh JSON across review/profile scripts. |

## See also

- [Getting Started](Getting-Started.md)
- [Commands](Commands.md)
- [The SDLC Loop](The-SDLC-Loop.md)
- [Project Profile](Project-Profile.md)
- [Concepts and Glossary](Concepts-and-Glossary.md)
