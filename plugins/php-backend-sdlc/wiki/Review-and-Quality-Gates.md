# Review and Quality Gates

[Home](Home.md) › Deep dives › Review and Quality Gates

Stage 4 of the SDLC loop is the review gate. It runs two independent
review lenses over the change set — a **code-quality** lens and a
**FR/NFR spec-compliance** lens — and loops (dispatch fix → commit →
re-review) until both are clean. A third **security** lens runs as a
triaged skill when the change is in scope. Everything is measured
against protected, raise-only thresholds; nothing is silenced.

This page covers the review stage itself, the two reviewer agents and
their backing skills, the BMAD FR/NFR gate, the `quality-standards`
router, and how loop-backs route fixes through `php-implementer`.

For the seven-stage loop as a whole, see [The-SDLC-Loop](The-SDLC-Loop.md).
For the security lens in depth, see [Security-Audit](Security-Audit.md).
For the publishing side effects, see [Publishing-PR-Comments](Publishing-PR-Comments.md).

## The review stage (stage 4) and its lenses

The stage is driven by
[`/sdlc-review`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc-review.md)
(FR-6). Its first action is the stage contract: run
`scripts/validate-profile.sh`; on exit 1 it aborts and tells the user to
run `/sdlc-setup`. It also captures `REVIEW_STARTED_AT` for the
conclusion comment's duration (FR-10) — that timestamp has no effect on
the exit condition.

The command itself never writes files — its `allowed-tools` is
`["Bash", "Read", "Glob", "Grep", "Task"]`, deliberately excluding
`Write`. Remediation is delegated to a `php-implementer` subagent, and
the command commits that remediation between iterations (the dispatching
loop owns commits; `php-implementer` runs no git).

The stage has three moving parts:

1. **Applicability triage (ADR-5, NFR-5).** For every shipped
   `SKILL.md` (the command text pins this at 22 in v1), the command
   records one verdict — `EXECUTE` with one-line evidence (which changed
   file or behavior triggers it) or `NOT-APPLICABLE` with a one-line
   reason (including profile-gated skips such as "Skip when
   `capabilities.structurizr` is false"). The verdict is decided from
   the skill frontmatter (`name` + trigger-rich `description`) plus the
   `SKILL-DECISION-GUIDE.md` and nothing else — a skill body is **never**
   loaded to decide a verdict. All verdicts are recorded before any body
   loads; full bodies and reference files load only for `EXECUTE`
   verdicts (the NFR-5 token bound).
2. **Execute applicable skills** — load each `EXECUTE` skill's body and
   apply its checks against the change set, collecting findings.
3. **Multi-lens review** — dispatch the two reviewer agents in parallel
   via the Task tool.

### The two reviewer-agent lenses

| Lens | Agent | Question it answers | Tooling |
| --- | --- | --- | --- |
| Code quality | `code-quality-reviewer` | Does the change meet every protected `quality.*` threshold? | `make.psalm`, `make.deptrac`, `make.phpinsights`, `make.infection` |
| Spec compliance | `fr-nfr-reviewer` | Does the change satisfy every requirement in the specs bundle? | the FR/NFR gate runner against `specs/<slug>/` |

Both agents are read-only with respect to the repository: tools
`Read, Glob, Grep, Bash`, model `opus`, no `Write`, no `git`, no `gh`.
They report findings; they never remediate. The two lenses never
duplicate work — `code-quality-reviewer` owns the `quality.*` threshold
checks (psalm/deptrac/phpinsights/infection) and `fr-nfr-reviewer` owns
the spec-requirement matrix.

### The security lens

The third lens is the
[security-audit](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/security-audit/SKILL.md)
skill, surfaced through the triage step (it gets its own row in the
report template). When the change is in scope it runs an adversarial,
authorized vuln-hunt against the running service; otherwise it records a
one-line `NOT-APPLICABLE` reason. It is documented in full on
[Security-Audit](Security-Audit.md).

## code-quality lens: code-review skill + code-quality-reviewer agent

### code-quality-reviewer (the stage-4 agent)

[`code-quality-reviewer`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/code-quality-reviewer.md)
is the read-only quality lens dispatched by `/sdlc-review`. Its job is to
run the project's quality tooling through the profile `make` map, measure
observed values against the raise-only `quality.*` thresholds, and report
findings precise enough that a dispatched `php-implementer` can fix them
without re-discovery.

It executes **only** the four read-only quality targets resolved from the
profile `make` map:

| Profile `make` key | What it runs |
| --- | --- |
| `make.psalm` | static analysis |
| `make.deptrac` | layer-dependency (architecture boundary) check |
| `make.phpinsights` | lint / code-quality scores |
| `make.infection` | mutation-testing MSI |

"Lint" is covered by the phpinsights style/quality scores — no extra
ad-hoc linters are invoked. The agent's only allowed Bash is `make
<target>` for those four targets plus read-only output handling and
in-container introspection (`docker compose exec php composer show`
style); never host-level `php`, `composer`, or `vendor/bin/*`
(container-only rule). It ignores semgrep `SEMGREP_APP_TOKEN` hook errors
in command output — environmental noise, not findings.

The agent emits a single report with a 7-row **threshold table** (one row
per `quality.*` key, each marked PASS/FAIL/SKIPPED), a **findings table**
(`path/to/file.php:LINE` + severity `blocker`/`major`/`minor` + a
one-line root-cause fix that changes the **code**, not the tooling),
degrade notes, and a final `Verdict: PASS | FAIL`. The verdict rule:
**PASS only when every non-SKIPPED threshold row is PASS**; SKIPPED rows
(capability absent, `make.<key>: null`) never flip the verdict (NFR-4).

It owns an iteration counter (`MAX_ITERATIONS=5`, never reset). A
threshold FAIL is reported, not retried — re-running unchanged code
cannot change the observed value, so a FAIL does not consume an extra
iteration. On exhaustion it emits the canonical `=== SDLC ESCALATION ===`
block and stops.

#### Raise-only, no suppression (the hard prohibition)

The agent has an explicit hard prohibition: never propose, draft, or
hint at suppressions (`@psalm-suppress`, `@SuppressWarnings`, inline
ignore comments), baseline additions, config exclusions, ruleset edits,
or lowering any `quality.*` threshold. Thresholds are the floor/ceiling
as shipped — never reinterpret, round in the repo's favor, or "grade on
intent". If a threshold cannot be met by fixing code, that is a FAIL for
the dispatcher to act on, not a reason to move the bar.

### code-review skill (the PR-feedback workflow)

The agent is the in-loop quality lens; the
[code-review](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/code-review/SKILL.md)
skill is the broader workflow for driving a *reviewed PR* to merge-ready
state — retrieving, categorizing, and addressing reviewer comments with
an auditable evidence ledger. It shares the same suppression-free,
raise-only discipline and adds the GitHub-readiness machinery.

Two pieces of that skill are load-bearing for the quality story here:

**Suppression scan.** After CI passes, the skill scans the PR diff
(added lines only) for a forbidden-suppression pattern covering
`@SuppressWarnings`, `@psalm-suppress`, `@phpstan-ignore` /
`phpstan-ignore`, `phpcs:ignore` / `phpcs:disable`, `@infection-ignore`,
`@codeCoverageIgnore`, `@phpinsights-ignore`, and
`@codingStandardsIgnore` / `codingStandardsIgnore`. A match fails the
workflow — fix root causes, never silence tools. A second scan blocks
changes to quality-tool config / baseline files
(`deptrac.yaml`, `psalm.xml`, `phpstan.neon`, `phpmd*.xml`,
`phpinsights*.php`, `infection.json5`, `phpcs.xml`,
`.php-cs-fixer.dist.php`, any `*baseline*` file).

**Gate-definition isolation.** A *dedicated* gate-definition PR — one
where only gate-definition files changed versus the trusted base
(Makefile, CI workflows, quality-tool configs, lint/formatter configs,
review scripts, agent skill files, required-check declarations) — skips
the quality-config hard block, because those changes are the legitimate
subject of the PR and are reviewed on their own. The forbidden-suppression
line scan still runs, and any threshold change must be **raise-only**.
A PR that mixes gate-definition and product changes does not qualify and
is blocked: a product PR must not validate itself against gate
definitions it supplies.

**Thresholds in the skill** are read from `quality.*` and are raise-only,
with the same canonical floors/ceilings as the agent (see the table
below). A profile may tighten the floors, never relax them. The skill's
`NEVER` list spells it out: never lower any `quality.*` threshold or edit
`deptrac.yaml` to make findings disappear; fix the code instead.

## Protected quality thresholds

The canonical floors/ceilings are shared across the agent, the
`code-review` skill, and the `quality-standards` skill. They are
**raise-only** (ADR-7): a profile may tighten a floor, never relax it;
violation-count ceilings ship at `0` and may not be raised.

| Metric | Profile key | Shipped value | Type |
| --- | --- | --- | --- |
| PHPInsights quality | `quality.phpinsights.quality` | 100 | floor |
| PHPInsights architecture | `quality.phpinsights.architecture` | 100 | floor |
| PHPInsights style | `quality.phpinsights.style` | 100 | floor |
| PHPInsights complexity | `quality.phpinsights.complexity` | 94 | floor |
| Infection MSI | `quality.infection_msi` | 100 | floor |
| Deptrac violations | `quality.deptrac_violations` | 0 | ceiling (fixed) |
| Psalm errors | `quality.psalm_errors` | 0 | ceiling (fixed) |

Psalm taint-analysis security issues are bound at `0`, and Psalm
`ForbiddenCode` findings are counted inside `quality.psalm_errors`.
PHPUnit line coverage is an *independent* bar at the project's enforced
target — Infection MSI is a separate, stronger signal but does not by
itself guarantee full line coverage, because MSI is measured only over
mutated lines.

A reference-service pass at the shipped floors looks like:

```text
✅ CI checks successfully passed!
[CODE] 100.0 pts  [COMPLEXITY] 94.0 pts  [ARCHITECTURE] 100 pts  [STYLE] 100.0 pts
✅ No violations found            # deptrac
Mutation Score Indicator (MSI): 100%
```

## quality-standards skill (the router)

[quality-standards](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/quality-standards/SKILL.md)
is the overview + quick-reference router. It does not fix anything
itself; it explains the protected thresholds and maps every failing
check to its command and its specialized fixing skill. Its success
criterion is literally "know which skill to use for your specific
quality issue".

The routing table it carries:

| Failure | Specialized skill |
| --- | --- |
| Deptrac violations / "must not depend on" | deptrac-fixer |
| PHPInsights complexity below floor / high CCN | complexity-management |
| Class in wrong directory, vague naming, hardcoded config | code-organization |
| DDD pattern violations / new entities, CQRS | implementing-ddd-architecture |
| Test failures, escaped mutants, MSI below floor | testing-workflow |
| Psalm errors | fix the type errors directly |
| Code style | the repo's containerized style fixer |

It also documents the command convention used across the skill set:
`make <make.X>` means "run `make` with the target the profile maps for
key `make.X`"; a `null` mapping means the capability is absent — skip
that check with a capability-absent note rather than failing (NFR-4).
PHP tools without a `make.*` key still run through the containerized
toolchain (a repo `make` wrapper, else
`docker compose exec <php-service> vendor/bin/<tool>`), never bare on the
host. Its `NEVER` / `ALWAYS` lists restate the no-suppression,
fix-code-not-config, raise-only rules and the target of cyclomatic
complexity under 5 per method.

See [Skills](Skills.md) for the full skill catalog and the
[profile-schema](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md)
doc for the `quality.*` and `make.*` keys.

## BMAD FR/NFR gate (the spec-compliance lens)

### fr-nfr-reviewer (the stage-4 agent)

[`fr-nfr-reviewer`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/fr-nfr-reviewer.md)
is the second stage-4 lens. It answers exactly one question: **does the
change set satisfy every requirement in the specs bundle?** It does so by
(1) running the FR/NFR gate runner against `specs/<slug>/`, (2) building a
per-requirement PASS/FAIL matrix — one row per FR, per NFR, and per
quality dimension — and (3) tracking the new-findings count per iteration
so the calling loop can detect convergence.

Gate-runner resolution: read `make.fr_nfr_gate` from the profile; non-null
runs that Make target, `null` (the shipped default) substitutes the
plugin script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/fr-nfr-gate.sh" --spec-path "specs/<slug>" --impact-context "<one-line change summary>"
```

The agent's report ends with the mandatory machine-readable convergence
line — the stage's exit signal:

```text
FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<PASS|FAIL|DEGRADED>
```

`new_findings=0` with `verdict=PASS` is the stage exit condition. A
finding is **NEW** when the same requirement ID + same substance is
absent from all prior iterations' ledgers; resolved-then-regressed
findings count as new again. If the new-findings count fails to decrease
across two consecutive iterations, the agent says so explicitly — the
loop is not converging. Its iteration counter is capped at 5, never
reset; a missing/empty spec bundle yields `verdict=DEGRADED` (not a loop
state — escalate, re-run `/sdlc-plan`).

For backing "implemented AND tested" PASS rows, the agent may run the
`make.tests` / `make.e2e` evidence targets; it never touches the
quality targets (those belong to `code-quality-reviewer`) and never runs
`git` or `gh`.

### The gate itself (bmad-fr-nfr-review-gate skill)

The agent runs the gate defined by the
[bmad-fr-nfr-review-gate](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/bmad-fr-nfr-review-gate/SKILL.md)
skill: a BMAD spec-driven post-implementation gate that **blocks
completion until every applicable requirement row scores 5/5 and the gate
run reports zero new findings**.

#### The per-requirement matrix

The gate scores far more than the raw FR/NFR list. Every applicable row
must reach 5/5 across:

- **The pinned NFR catalog** (NonFunctionals.com categories): Performance,
  Usability, Maintainability, Availability, Interoperability, Security,
  Manageability, Automatability, Dependability. These categories are
  fixed — not added, removed, or renamed during a review.
- **The Expanded Quality Scorecard** — 16 dimensions including Functional
  Suitability, Performance Resource Sustainability, Reliability
  Resilience, Security Privacy Accountability, Maintainability
  Testability, Observability Diagnosability, Supply-Chain Integrity,
  Compliance Governance, and AI Automation Governance.
- **A System Quality Attributes Scorecard** covering every attribute on
  the Wikipedia list of system quality attributes — each with a scored
  row, evidence, source, status, and an improvement recommendation.
- **A Whole-Codebase Impact Analysis** across changed *and related*
  surfaces: runtime paths, architecture/layer boundaries, domain model,
  persistence, public API/schema, async events/queues, config/env,
  dependencies/lockfiles, CI/workflows, tests/fixtures, docs,
  operations/observability, security/privacy, and backward compatibility.
- **A Mandatory QA Matrix** — generated positive, negative, and
  edge/boundary/race/timeout/error cases per FR, NFR, acceptance
  criterion, story, and quality requirement, each mapped to automated
  tests and CI checks (`make.tests`, `make.e2e`, `make.infection`
  mutation, `make.load_tests` when `capabilities.load_testing` is true).

Every NFR-catalog row, expanded-quality row, and system-quality-attribute
row must cite **graph/relationship evidence** (from `make.deptrac`'s
layer-dependency graph, codebase-memory MCP, CodeQL, SCIP, or a bounded
local graph built from changed files), or give a concrete source-backed
reason why graph evidence is irrelevant for that row.

#### Scoring contract

| Score | Meaning |
| --- | --- |
| 1/5 | Requirement not addressed or evidence absent |
| 2/5 | Partial implementation with major gaps |
| 3/5 | Implemented but missing tests, evidence, or important edge cases |
| 4/5 | Implemented and mostly verified with minor unresolved risk |
| 5/5 | Fully implemented, verified, traceable, and review-ready |

A not-applicable row is allowed only with a concrete reason and source
evidence; **missing evidence fails closed**. The gate also explicitly
applies the sibling code-organization, implementing-ddd-architecture,
deptrac-fixer, and complexity-management rules before awarding 5/5 to any
Maintainability, Testability, Modularity, Simplicity, Dependability, or
architecture/layer-boundary row — a generic "looks good" is not enough.
Remediation is always root-cause: no suppression annotations, never edit
`deptrac.yaml`, and never lower `quality.phpinsights.complexity` (floor
94) or `quality.infection_msi` (floor 100).

#### Convergence = zero new findings

The shipped `fr-nfr-gate.sh` enforces one mechanical contract: its
output's mandatory last line is `FR_NFR_NEW_FINDINGS: <n>`, and **only
`n = 0` exits 0** — a missing or malformed line fails closed with a
failure commit status. The script always posts the `BMAD FR/NFR Review
Gate` commit status to the PR HEAD, and posts a findings PR comment only
when the count is above zero (success stays comment-quiet; the status
check is the durable signal).

The richer scorecard markers — `FR_NFR_SCORECARD: PASS`,
`NFR_CATALOG_SCORECARD: PASS`, `EXPANDED_QUALITY_SCORECARD: PASS`,
`SYSTEM_QUALITY_ATTRIBUTES_SCORECARD: PASS`, `WHOLE_CODEBASE_IMPACT: PASS`,
`TEST_CASE_MATRIX: PASS`, plus the `*_MIN_SCORE: 5/5` evidence markers —
are a contract on the **review report the agent authors**, not output the
shipped script emits. The script enforces only the mechanical
`FR_NFR_NEW_FINDINGS` line; the reviewer produces the marker-bearing
scorecard report itself.

## How loop-backs route fixes through php-implementer

The two lenses converge through one **remediation gate loop**
(`MAX_ITERATIONS=5`). The command reads the convergence signal from both
reports — the `fr-nfr-reviewer` last line
(`new_findings=<n> verdict=...`) and the `code-quality-reviewer`
`Verdict` plus its FAIL threshold rows — and the stage exit condition is
**both lenses clean in the last iteration**:

```text
fr-nfr-reviewer new_findings=0 verdict=PASS
  AND every non-SKIPPED code-quality-reviewer threshold row PASS
```

A `code-quality-reviewer` FAIL row (e.g. phpinsights complexity below the
profile floor, deptrac violations over threshold) blocks the stage
verdict exactly like an FR/NFR finding — it never silently defers to the
stage-6 CI check.

On findings from **either** lens, the command runs one
dispatch-commit-reinvoke cycle (one iteration):

1. **Dispatch** the combined findings — FR/NFR findings *and*
   `code-quality-reviewer` FAIL-row root-cause fixes — as a single
   remediation task to a `php-implementer` subagent via the Task tool,
   then wait. The agent lands fixes in the working tree only; it runs
   **no git** (the dispatching loop owns commits).
2. **Commit** the remediation via Bash, e.g.
   `git add -A && git commit -m "review: gate iteration <n> remediation"`,
   *before* re-invoking the reviewers. Committing matters because the
   gate runner inside `fr-nfr-reviewer` resolves
   `head_sha=$(git rev-parse HEAD)` and posts the `BMAD FR/NFR Review
   Gate` commit status to that SHA — committing first makes the status
   land on a tree that actually contains the fixes, and hands committed
   work to downstream stages.
3. **Re-invoke** *both* reviewers in parallel, passing each its prior
   iteration ledger (findings + counts from all iterations so far) so
   every agent computes "new" as a delta and **resumes** — never resets —
   its counter. A lens already clean in the prior iteration is still
   re-invoked, so its verdict is computed on the committed post-fix tree,
   not stale output.

```text
reviewers report findings (either lens)
        │
        ▼
php-implementer  ── lands fixes in working tree, NO git ──┐
        │                                                  │
        ▼                                                  │
/sdlc-review commits the remediation (git add -A && commit)│
        │                                                  │
        ▼                                                  │
re-invoke BOTH reviewers (parallel, with prior ledgers) ───┘
        │
        ▼
both lenses clean?  ── no → next iteration (≤5)
        │ yes
        ▼
stage PASS  →  conclusion comment (gated)  →  next stage
```

`php-implementer` is the only writer in the loop; the reviewers are
read-only and the command itself has no `Write` tool. This separation is
what keeps the gate honest — the agents that *judge* the code cannot
*change* it, and the loop that changes it commits before the next
judgment.

On a guard breach (either lens still dirty at iteration 5) or a blocking
finding (a SPECS-MISSING `verdict=DEGRADED` report), the command emits the
canonical `=== SDLC ESCALATION ===` block with the review report attached
and stops. After the loop closes, gated on
`capabilities.publish_pr_comments`, it posts the aggregate conclusion
comment exactly once (NFR-2) — see
[Publishing-PR-Comments](Publishing-PR-Comments.md). For the loop-wide
degrade behavior, see [Degrade-and-Resilience](Degrade-and-Resilience.md).

## See also

- [The-SDLC-Loop](The-SDLC-Loop.md)
- [Security-Audit](Security-Audit.md)
- [Agents](Agents.md)
- [Skills](Skills.md)
- [Publishing-PR-Comments](Publishing-PR-Comments.md)
