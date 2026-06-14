# Concepts and Glossary

[Home](Home.md) › Start here › Concepts and Glossary

This page gives you the mental model behind the php-backend-sdlc plugin
and then a glossary of every term you will meet in the commands, agents,
skills, profile, and docs. Read it once and the rest of the wiki stops
feeling like jargon.

## Mental model

The plugin is organized around four kinds of building block. They have
distinct jobs and deliberately do not overlap.

### Commands orchestrate

A **command** (`/sdlc`, `/sdlc-review`, …) is a slash-invoked stage
driver. It owns control flow: it validates the project profile, decides
what to do next, dispatches work to agents, enforces the iteration
guard, commits remediation between iterations, and reports a verdict.
Commands generally do not write product code themselves —
`/sdlc-review`, for example, ships with an `allowed-tools` list that
*excludes* `Write`, so all remediation is delegated and the command only
commits it. There are 8 commands, one per SDLC stage plus the `/sdlc`
end-to-end orchestrator. See [Commands](Commands.md).

### Agents execute

An **agent** (a subagent dispatched through the Task tool) does the
concrete, isolated work: `php-implementer` writes code, `ci-fixer`
drives CI to green, `code-quality-reviewer` runs the read-only quality
targets, `security-auditor` red-teams one vuln family. Agents are the
"hands" — they run inside their own context, return findings or commits,
and respect the same profile the command resolved. There are 7 agents.
See [Agents](Agents.md).

### Skills are knowledge

A **skill** is a self-contained markdown playbook for one engineering
concern — how to add an API Platform CRUD resource, how to fix a Deptrac
violation, how to design a cache key. Skills carry *no* control flow of
their own; a command or agent decides *whether* a skill applies (via
**applicability triage**, defined in the glossary below) and then loads
its `SKILL.md` body to follow its steps. There are 22 skills plus 2 meta-guides
([AI-AGENT-GUIDE.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md)
and
[SKILL-DECISION-GUIDE.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md)).
See [Skills](Skills.md).

### The profile generalizes

The **project profile** (`.claude/php-sdlc.yml`) is the single source of
truth that makes the same commands, agents, and skills work on *your*
PHP backend. Skills never hardcode a repository's Make targets or
quality numbers — they reference logical keys like `make.ci`,
`persistence.mapper`, or `quality.infection_msi`, and the profile maps
those to the concrete target name, mapper, or threshold for the current
repo. `/sdlc-setup` generates it; `validate-profile.sh` checks it before
every stage. This is the layer that turns a plugin written against one
reference service into one that runs on any conforming PHP backend. See
[Project Profile](Project-Profile.md).

### How they fit together

```text
/sdlc (command, orchestrator)
  └─ stage command (e.g. /sdlc-review)        ← orchestrates
        ├─ reads .claude/php-sdlc.yml          ← profile generalizes
        ├─ triages 22 skills                   ← skills = knowledge
        └─ dispatches code-quality-reviewer    ← agent executes
                 └─ loads ci-workflow/SKILL.md ← skill = knowledge
```

The flow is always the same shape: a command resolves the profile,
triages which knowledge (skills) is relevant, hands execution to agents,
and loops under a guard until its exit condition is met. The
[Architecture](Architecture.md) and [The SDLC Loop](The-SDLC-Loop.md)
pages expand this.

## Glossary

| Term | Definition |
| --- | --- |
| **BMAD** | The spec-driven planning method this plugin automates. Stage 2 produces a six-artifact chain under `specs/<slug>/` — research, brief, PRD, architecture, epics-stories, readiness — and stage 4 verifies the implementation against it. See [bmad-autonomous-planning](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/bmad-autonomous-planning/SKILL.md). |
| **Ralph** | The autonomous implementation loop run in stage 3. Driven by `bmalph run --driver claude-code`, it works through fix-plan checkboxes, emits `---RALPH_STATUS---` blocks, and signals completion with `EXIT_SIGNAL: true`. Its inner loop is independently protected by a **circuit breaker** (see below). |
| **bmalph** | The CLI that bridges BMAD planning to Ralph execution. `bmalph implement` transitions the `specs/<slug>/` chain into Ralph's working format (fix plan, prompt, specs); `bmalph run` starts the loop. Required at version ≥ 2.11.0; `bmalph doctor` checks the `_bmad/` workspace. |
| **FR** | Functional Requirement — a behavior the change must deliver, captured in the BMAD spec chain and verified row-by-row by the FR/NFR **gate** (see below) in stage 4. |
| **NFR** | Non-Functional Requirement — a quality, performance, security, or operability constraint (e.g. NFR-4 = degrade behavior, NFR-5 = the triage token bound, NFR-6 = the circuit breaker). Also verified by the FR/NFR gate. |
| **Project profile** | `.claude/php-sdlc.yml`: the per-repository config that generalizes every command, agent, and skill (FR-17). Generated by `/sdlc-setup`, validated by `validate-profile.sh`, and consumed via logical keys (`make.*`, `quality.*`, `persistence.*`, `capabilities.*`, …). See the [profile schema](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md). |
| **Skill** | A self-contained markdown playbook (`{name}/SKILL.md`) for one concern. Carries domain knowledge and steps, not control flow. 22 ship in v1, plus 2 meta-guides. |
| **Agent** | A subagent dispatched via the Task tool to do isolated work (implement, review, fix CI, resolve comments, QA, red-team). 7 ship in v1. |
| **Command** | A slash-invoked stage driver that orchestrates: validates the profile, dispatches agents, enforces guards, commits, and reports. 8 ship in v1. |
| **Lens** | An independent review viewpoint in stage 4. `/sdlc-review` runs two lenses in parallel — the FR/NFR lens (`fr-nfr-reviewer`, requirement traceability against `specs/<slug>/`) and the code-quality lens (`code-quality-reviewer`, the `quality.*` thresholds). The gate loops until BOTH lenses are clean. |
| **Applicability triage** | The ADR-5/NFR-5 step where every shipped skill receives a recorded verdict — `EXECUTE` (with a one-line trigger) or `NOT-APPLICABLE` (with a one-line reason) — decided from the skill's frontmatter `description` plus `SKILL-DECISION-GUIDE.md` alone. A skill's `SKILL.md` body is loaded only *after* an EXECUTE verdict, which bounds token cost. The contract is "every skill verdict recorded, no silent skips." |
| **Degrade-first** | The NFR-4 policy that a missing capability degrades with a note rather than failing the run. When a `make.<key>` is `null`, `ci.provider` is `null`, or `review.coderabbit` is `false`, the dependent step is skipped-with-report and the run still reaches SUCCESS. Degrade paths never loop and never hard-fail — only guards, breakers, and preflight produce ESCALATED/HALTED. See the [degrade matrix](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md) and [Degrade and Resilience](Degrade-and-Resilience.md). |
| **Circuit breaker** | Ralph's inner safety mechanism (NFR-6), configured in `.ralphrc`: trips on no-progress after 3 loops, same-error after 5 loops, or output-decline at 70%. On a trip the stage stops immediately and emits the escalation block. The plugin **never** resets, restarts around, or tampers with a tripped breaker — it is a human-attention signal, and resetting it discards the evidence. |
| **Raise-only thresholds** | The ADR-7 rule for `quality.*` values: shipped defaults are the minimum bar. Score floors (`quality.phpinsights.*`, `quality.infection_msi`) may be raised above defaults, never lowered; violation ceilings (`quality.deptrac_violations`, `quality.psalm_errors`) ship at `0` and may not be raised. `validate-profile.sh` rejects any value on the wrong side of its default. |
| **Container-only** | The stage-3 execution rule: every `php-implementer` runs build, test, and quality commands exclusively through the profile `make` map (or `docker compose exec php`), never a raw host command. A `make.<key>: null` entry means the capability is absent — record and skip with a note, never substitute a host command. |
| **MSI / infection** | Mutation Score Indicator, produced by Infection mutation testing (the target mapped by `make.infection`). The gate is `MSI ≥ quality.infection_msi` (canonical default `100`, raise-only). Fix the *tests* to raise MSI — never suppress mutations or lower the threshold. |
| **Deptrac** | The static layer-dependency checker. It enforces hexagonal architecture boundaries (e.g. Domain must not import framework code; Infrastructure must not call Application handlers directly). `quality.deptrac_violations` is fixed at `0`; the `deptrac-fixer` skill always fixes the *code*, never `deptrac.yaml`. |
| **Psalm** | The static analysis tool run via the target mapped by `make.psalm`. `quality.psalm_errors` is fixed at `0`. Fix reported issues at the root cause — suppression annotations (`@psalm-suppress`, …) are forbidden. |
| **PHPInsights** | The code-quality scorer reporting four metrics: quality, architecture, style, and complexity. Each maps to a `quality.phpinsights.*` floor (defaults `100/100/100/94`, raise-only). The `complexity-management` skill refactors to meet the bar rather than relaxing config. |
| **SDLC loop** | The seven-stage pipeline `/sdlc` drives from task text to finished PR: setup-check, issue, plan, implement, review, qa, finish-pr. It is gated, resumable, and ends in exactly one of two terminal states — SUCCESS or ESCALATED. See [The SDLC Loop](The-SDLC-Loop.md). |
| **Gate** | A stage's exit condition that must be *verifiably* met before the next stage starts — `/sdlc` re-checks each condition itself rather than trusting a stage's own report. The stage-4 FR/NFR gate is the canonical example: it blocks completion until both lenses report zero new findings and every requirement row passes. |
| **Loop-back** | A controlled return to an earlier stage when a downstream check fails — e.g. a QA FAIL routes back to stage 3 with the QA report attached, and review-gate findings are fixed in-stage before the gate re-runs. Every loop-back consumes the owning stage's 5-iteration budget; counters are never reset, and a breach emits the canonical `=== SDLC ESCALATION ===` block. |

## See also

- [Architecture](Architecture.md) — how commands, agents, skills, and
  the profile are wired together
- [The SDLC Loop](The-SDLC-Loop.md) — the seven stages, gates, and
  loop-backs in detail
- [Project Profile](Project-Profile.md) — every `.claude/php-sdlc.yml`
  key and the raise-only rules
- [Skills](Skills.md) — the 22-skill library and applicability triage
- [Degrade and Resilience](Degrade-and-Resilience.md) — degrade-first,
  guards, and the circuit breaker
