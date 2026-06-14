# Architecture

[Home](Home.md) › Deep dives › Architecture

This page explains how the php-backend-sdlc plugin is composed: the four
component layers (commands, agents, skills, profile), how a command
dispatches agents and triages skills, how the project profile generalizes
everything to a concrete repository, the design principles every layer
enforces, and the on-disk layout.

The plugin ships **8 commands**, **7 agents**, and **22 skills** plus **2
meta-guides** ([`AI-AGENT-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md)
and [`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md)).

## Component layers

The plugin is four cooperating layers. Control flows top-down (a command
drives a stage, dispatches agents, triages skills); generalization flows
sideways (the profile parameterizes every other layer at runtime).

```text
+--------------------------------------------------------------+
| COMMANDS (8)  — slash-command stage orchestrators            |
|   /sdlc /sdlc-setup /sdlc-issue /sdlc-plan /sdlc-implement    |
|   /sdlc-review /sdlc-qa /sdlc-finish-pr                       |
|   own: stage gating, iteration guards (MAX_ITERATIONS=5),     |
|        commits, loop-backs, escalation reports               |
+----------------------------+---------------------------------+
            | Task tool dispatch        | direct-load + triage
            v                           v
+----------------------------+   +------------------------------+
| AGENTS (7) — subagents     |   | SKILLS (22) — markdown       |
|  php-implementer           |   | workflows + 2 meta-guides    |
|  code-quality-reviewer     |   |  api-platform-crud, ci-      |
|  fr-nfr-reviewer           |   |  workflow, deptrac-fixer,    |
|  qa-manual-tester          |   |  security-audit, ...         |
|  ci-fixer                  |   |  each: "## Profile keys      |
|  pr-comment-resolver       |   |  consumed" + frontmatter     |
|  security-auditor          |   |  trigger description         |
|  (run NO git; report only) |   +--------------+---------------+
+----------------------------+                  |
            |                                   |
            +------------------+----------------+
                               v
+--------------------------------------------------------------+
| PROFILE — .claude/php-sdlc.yml (generalization layer, FR-17) |
|   make.* target map | quality.* thresholds (raise-only)      |
|   persistence.* | architecture.* | framework.* | ci.*        |
|   review.* | capabilities.*                                  |
|   validate-profile.sh runs FIRST in every command            |
+--------------------------------------------------------------+
```

The key relationship: **commands are the only layer that holds state**
(iteration counters, commits, gate verdicts). Agents and skills are
stateless — agents are re-dispatched fresh each iteration and never run
git; skills are pure markdown read on demand. The profile is read-only
configuration that every layer resolves through the same `make.*` map.

## How a command dispatches agents and triages skills

Every command follows the same skeleton, defined per stage in the
[stage table](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc.md)
of `/sdlc`:

1. **Validate-profile first.** Every command except `/sdlc-setup` runs
   `scripts/validate-profile.sh` as its first action; exit 1 aborts the
   stage with "run `/sdlc-setup`". `/sdlc-setup` is the exception because
   it is the command that *creates* the profile.
2. **Do the stage work** — either direct-load a skill, dispatch agents
   via the Task tool, or both.
3. **Gate-check the exit condition independently.** A stage's own success
   claim is never the gate; the command re-verifies the measurable
   condition (re-read the issue, re-run `gh pr checks`, re-run the FR/NFR
   gate) before advancing.
4. **Loop under a `MAX_ITERATIONS=5` guard**, escalating with a canonical
   `=== SDLC ESCALATION ===` block on breach.

### Two dispatch mechanisms

The plugin uses **direct-load** for deterministic, single-owner work and
**Task-tool dispatch** for parallel, stateless work:

| Mechanism | Used by | Example |
| --- | --- | --- |
| Direct-load a skill body | command reads `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md` and executes it inline | `/sdlc-plan` direct-loads `bmad-autonomous-planning/SKILL.md` (the §1.2 dependency edge) |
| Task-tool subagent dispatch | command spawns an agent that returns a report | `/sdlc-review` dispatches `code-quality-reviewer` and `fr-nfr-reviewer` in parallel |

Direct-loaded skills run with the command's own permissions; dispatched
agents run with their own `tools:` frontmatter surface. Because agents are
re-dispatched fresh each iteration, the command must hand each one its
**prior iteration ledger** so the agent's counter resumes rather than
resets — this is why `/sdlc-review` re-invokes both reviewers (even one
already clean) on the committed post-fix tree.

### The skill-applicability triage (ADR-5 / NFR-5)

`/sdlc-review` is the canonical triage consumer. Before any skill body
loads, it records one verdict for **every** skill directory:

1. Decide each verdict from the skill's frontmatter `description` (a
   trigger-rich line including profile-gating conditions like "Skip when
   `capabilities.structurizr` is false") plus the
   [`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md)
   — and nothing else. Never load a body to decide a verdict.
2. Record `EXECUTE` (with one-line evidence: which changed file or
   behavior triggers it) or `NOT-APPLICABLE` (with a one-line reason,
   including profile-gated skips).
3. Only after a verdict of `EXECUTE` does the command load that skill's
   full body and reference files.

This is the **NFR-5 token bound**: full SKILL.md bodies and `reference/`
files load only for EXECUTE skills, so a no-op review never pays to read
every workflow. The gate contract is *every skill verdict recorded, no
silent skips* — the review report renders all `22/22` verdicts, and the
same gate runs after any new feature (the Mandatory New Feature
Verification Gate in both meta-guides).

### Worked example — the stage-4 review loop

`/sdlc-review` composes all of the above in one stage:

1. Validate profile, capture loop start time.
2. Triage all 22 skills (verdicts only), then load and run the EXECUTE
   bodies against the diff.
3. Dispatch `code-quality-reviewer` and `fr-nfr-reviewer` in parallel.
   The quality reviewer runs the read-only `make.psalm`, `make.deptrac`,
   `make.phpinsights`, `make.infection` targets and reports observed
   values against the profile `quality.*` thresholds; the FR/NFR reviewer
   owns the single gate run (`make.fr_nfr_gate`, `null` → the plugin's
   `fr-nfr-gate.sh`) and builds the per-requirement PASS/FAIL matrix.
4. On findings from *either* lens, dispatch one `php-implementer` to land
   root-cause fixes in the working tree, then the command commits them
   (agents run no git), then re-invokes both reviewers. That
   dispatch-commit-reinvoke cycle is one iteration.
5. Exit only when **both** lenses are clean (FR/NFR `new_findings=0
   verdict=PASS` and every non-SKIPPED quality row PASS).

The same separation holds elsewhere: `/sdlc-implement` fans out one
`php-implementer` per independent story (dependent stories run
sequentially); `/sdlc-qa` dispatches `qa-manual-tester`; `/sdlc-finish-pr`
runs two independent counters, `ci-fixer` (counter A) and
`pr-comment-resolver` (counter B). In every case the agent reports or
edits the working tree, and **the command owns the commits**.

## The project profile as the generalization layer

A single file, `.claude/php-sdlc.yml`, is "the single source of truth that
generalizes every command, agent, and skill to a concrete PHP backend
repository" (FR-17). It is generated by `/sdlc-setup`
(`scripts/generate-profile.sh`) and validated by
`scripts/validate-profile.sh` before every stage. Full key reference:
[Project-Profile](Project-Profile.md) and the
[profile-schema doc](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md).

The profile decouples the plugin's *logic* from a repository's *facts*.
The most important indirection is the **logical `make` target map**: a
skill never names a repository-specific Make target. It says "the target
mapped by `make.ci`", and the agent looks up `make.ci` in the profile and
runs that target. The same workflow therefore runs against a repo whose CI
target is `ci`, another whose target is `check`, and another that has no
CI at all.

A profile carries the facts the rest of the plugin parameterizes against:

| Profile area | What it generalizes |
| --- | --- |
| `make.*` | Logical → real Make target map; the only sanctioned command surface. A `null` value means the capability is absent (degrade, do not fail). |
| `quality.*` | Protected thresholds reviewers report against (raise-only; see below). |
| `persistence.mapper` / `persistence.engine` | `doctrine-orm` vs `doctrine-odm`, datastore — picks the migration and injection-sink shape. |
| `architecture.source_root` / `bounded_contexts` / `shared_context` | Where new code lands and which layering rules apply. |
| `framework.*` | `framework.api_platform`, `framework.graphql` gate API/GraphQL-specific skills. |
| `ci.*` | `ci.provider` (`null` = no CI), `ci.required_checks` — the `/sdlc-finish-pr` CI loop and its degrade. |
| `review.*` | `review.coderabbit` selects the comment source; `review.ai_review_agents` (v1: `claude` only). |
| `capabilities.*` | Boolean feature gates: `structurizr`, `observability_emf`, `load_testing`, `dynamic_security_testing`, `publish_pr_comments`. |

Each skill and agent declares the keys it reads under a
`## Profile keys consumed` header, and the `profile-keys-check` CI job
greps those headers against the schema doc — a key consumed but
undocumented fails CI. This makes the generalization contract
machine-checked, not just convention.

The **distinction between `null` and missing is intentional**: the `make`
map is required and must be complete, so an explicit `null` declares
"capability absent" (degrade with a note) while omitting a key entirely is
a validation error ("forgot to declare").

## Design principles

These six principles are enforced consistently across all four layers.

### FR/NFR gating

Completion is gated on a BMAD spec, not a vibe. `/sdlc-review` will not
pass until the `fr-nfr-reviewer` reports `new_findings=0 verdict=PASS`
against every requirement in `specs/<slug>/`, and the
[`bmad-fr-nfr-review-gate`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/bmad-fr-nfr-review-gate/SKILL.md)
skill checks implemented work against every FR/NFR, pinned NFR category,
quality dimension, impact surface, manual-evidence item, GitHub review
status, and CI check. A quality-threshold FAIL row blocks the verdict
*exactly like* an FR/NFR finding — it never silently defers to stage-6 CI.
See [Review-and-Quality-Gates](Review-and-Quality-Gates.md).

### Raise-only thresholds (ADR-7)

The shipped `quality.*` defaults are the **minimum bar**. A profile may
tighten a threshold, never relax it; `validate-profile.sh` rejects any
value on the wrong side of its default.

| Key | Direction | Shipped default |
| --- | --- | --- |
| `quality.phpinsights.quality` | floor (raise-only) | `100` |
| `quality.phpinsights.architecture` | floor (raise-only) | `100` |
| `quality.phpinsights.style` | floor (raise-only) | `100` |
| `quality.phpinsights.complexity` | floor (raise-only) | `94` |
| `quality.deptrac_violations` | ceiling (fixed) | `0` |
| `quality.psalm_errors` | ceiling (fixed) | `0` |
| `quality.infection_msi` | floor (raise-only) | `100` |

Score floors may be raised; violation-count ceilings ship at `0` and may
not be raised at all (more violations would lower the bar).

### Degrade-first (NFR-4)

A missing external capability degrades with a recorded note instead of
failing the run. A `make.<key>: null` is skipped with a capability-absent
note; `ci.provider: null` makes `/sdlc-finish-pr` skip check-waiting;
`make.start: null` makes `/sdlc-qa` finish with
`PASS (SUCCESS-WITH-REPORT — black-box QA skipped, make.start: null)`. The
plugin also **null-substitutes its own scripts** for absent targets:
`make.fr_nfr_gate` → `fr-nfr-gate.sh`, `make.ai_review_loop` →
`ai-review-loop.sh`, `make.pr_comments` → `get-pr-comments.sh`,
`make.post_review_findings` → `post-review-findings.sh`, `make.security` →
the bundled static lane. Degrades never loop and never hard-fail. The full
table is in [Degrade-and-Resilience](Degrade-and-Resilience.md) and the
[degrade-matrix doc](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md).

### Container-only

PHP never runs on the host. Every build, test, and quality command goes
through the profile `make` map or, for ad-hoc commands the map does not
cover, `docker compose exec php <command>`. `php-implementer` explicitly
forbids host-level `php`, `composer`, and `vendor/bin/*`. This is why
`/sdlc-setup` seeds the permission allowlist with `Bash(make:*)` and
`Bash(docker compose exec php:*)` (see [Permissions](Permissions.md)).

### No-suppression

A failing check means the code is wrong, not the check. Agents and skills
never add suppression or ignore annotations (`@psalm-suppress`,
`@SuppressWarnings`, `@infection-ignore-all`, `@codeCoverageIgnore`,
`@phpstan-ignore`, `phpcs:ignore`), never regenerate baselines, never
skip/delete tests, and never widen deptrac layers to legalize a violation.
Quality-tool config files (PHPInsights, Psalm, `deptrac.yaml`, Infection)
are treated as **locked** — the code is fixed to satisfy them, never the
reverse. `deptrac.yaml` in particular is never edited by any skill.

### Root-cause-only

Fixes target the underlying cause. `ci-fixer` fetches the failure logs,
diagnoses the cause, and fixes the cause in the working tree;
`security-auditor` promotes only findings reproduced against the running
service and routes each verified finding's root-cause fix through
`php-implementer` with a regression test. "Merge with red CI" is never a
normal workflow — it is a human-only exception path, and autonomous agents
must not self-approve or self-merge failed CI.

## Directory layout of the plugin

```text
plugins/php-backend-sdlc/
├── .claude-plugin/
│   └── plugin.json              # manifest: name, version, metadata
├── README.md                    # overview, requirements, quickstart
├── commands/                    # 8 slash-command stage orchestrators
│   ├── sdlc.md                  # end-to-end orchestrator (FR-1)
│   ├── sdlc-setup.md            # stage 0: profile + governance + perms
│   ├── sdlc-issue.md            # stage 1: task text → GitHub issue
│   ├── sdlc-plan.md             # stage 2: BMAD planning chain
│   ├── sdlc-implement.md        # stage 3: bmalph/Ralph implementation
│   ├── sdlc-review.md           # stage 4: triage + multi-lens gate
│   ├── sdlc-qa.md               # stage 5: black-box QA
│   └── sdlc-finish-pr.md        # stage 6: CI-fix + comment-resolution
├── agents/                      # 7 subagent definitions (+ .gitkeep)
│   ├── php-implementer.md       # writes code (the only writer agent)
│   ├── code-quality-reviewer.md # quality-threshold lens
│   ├── fr-nfr-reviewer.md       # FR/NFR gate lens
│   ├── qa-manual-tester.md      # black-box HTTP verification
│   ├── ci-fixer.md              # CI root-cause fixes
│   ├── pr-comment-resolver.md   # review-comment resolution
│   └── security-auditor.md      # per-family red-team unit
├── skills/                      # 22 skill dirs + 2 meta-guides
│   ├── AI-AGENT-GUIDE.md        # cross-agent skills-system guide
│   ├── SKILL-DECISION-GUIDE.md  # decision tree + verification gate
│   ├── <skill>/SKILL.md         # one dir per skill; some add
│   │                            #   reference/ and examples/
│   ├── security-audit/
│   │   ├── SKILL.md
│   │   └── reference/           # owasp-catalog, attack-playbooks, ...
│   └── cache-management/
│       └── examples/            # the only skill shipping examples/
├── scripts/                     # validate-profile.sh, generate-profile.sh,
│                                #   setup-preflight.sh, fr-nfr-gate.sh,
│                                #   ai-review-loop.sh, get-pr-comments.sh,
│                                #   post-review-findings.sh, lib/common.sh
├── docs/                        # reference docs (profile-schema, degrade-
│                                #   matrix, permissions, sdlc-loop, ...)
├── tests/                       # plugin test/validation suite
└── wiki/                        # this GitHub-wiki source
```

Skills are largely self-contained single-file workflows; only a few ship
multi-file structure (`security-audit/reference/`,
`cache-management/examples/`,
`implementing-ddd-architecture/REFERENCE.md`,
`code-organization/DIRECTORY-STRUCTURE.md`,
`load-testing/reference/`). The `scripts/` directory holds the
null-substitution fallbacks the degrade-first principle relies on, all
sourcing `lib/common.sh` for the `profile_path` / `profile_get` helpers.

## See also

- [Concepts-and-Glossary](Concepts-and-Glossary.md)
- [The-SDLC-Loop](The-SDLC-Loop.md)
- [Commands](Commands.md)
- [Agents](Agents.md)
- [Project-Profile](Project-Profile.md)
