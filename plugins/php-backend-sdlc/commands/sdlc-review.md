---
description: "Review implemented changes: 21-skill applicability triage, multi-lens quality and FR/NFR review, gate loop until zero new findings"
argument-hint: "[specs-dir]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]
---

# /sdlc-review — triage-based multi-lens review gate (FR-6)

Stage 4 of the SDLC loop. Every shipped skill receives a recorded
applicability verdict, two reviewer agents examine the change set from
independent lenses, and the FR/NFR gate loops until it reports zero new
findings. This command never writes files itself (`allowed-tools`
excludes Write); remediation between gate iterations is delegated.

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  ```

  On exit 1, ABORT and instruct the user to run `/sdlc-setup`.
- The change set: the working branch's diff against the default branch.
- The planning chain: `specs/<slug>/` from the argument or the
  `SPECS_DIR:` line emitted by `/sdlc-plan` — requirement traceability
  for the FR/NFR lens.
- Direct-load the triage decision guide (§1.2 dependency edge):

  ```text
  ${CLAUDE_PLUGIN_ROOT}/skills/SKILL-DECISION-GUIDE.md
  ```

- Profile `quality.*` values — the protected thresholds every check
  reports against.

## Procedure

1. **Applicability triage (ADR-5, NFR-5)** — for EVERY skill directory
   at `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md` (21 in v1):
   - Decide from the skill's frontmatter (`name` + trigger-rich
     `description`, including profile-gating conditions like "Skip when
     `capabilities.structurizr` is false") plus the decision guide —
     and NOTHING else. Never load a skill body to decide a verdict.
   - Record one verdict per skill: `EXECUTE` with one-line evidence
     (which changed file or behavior triggers it) or `NOT-APPLICABLE`
     with a one-line reason (including profile-gated skips).
   - All 21 verdicts are recorded before any body loads. Token bound
     (NFR-5): full SKILL.md bodies + reference files load only for
     EXECUTE verdicts.
2. **Execute applicable skills** — load each EXECUTE skill's body and
   apply its checks against the change set, collecting findings.
3. **Multi-lens review** — dispatch both reviewer agents via the Task
   tool, in parallel:
   - `code-quality-reviewer`: runs the read-only quality targets from
     the profile `make` map (`make.psalm`, `make.deptrac`,
     `make.phpinsights`, `make.infection` — skipping `null` entries
     with a capability-absent note, NFR-4) and reports observed values
     against the profile `quality.*` thresholds. It never proposes
     suppressions or threshold cuts.
   - `fr-nfr-reviewer`: builds the per-requirement PASS/FAIL matrix
     against `specs/<slug>/` and tracks the new-findings count.
4. **FR/NFR gate loop** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/fr-nfr-gate.sh" --spec-path "specs/<slug>" --impact-context "<one-line change summary>"
   ```

   Exit 0 means zero new findings — the stage exit condition. On
   findings: this command cannot write fixes (no Write tool), so
   dispatch the findings as a remediation task to a `php-implementer`
   subagent (Task tool), wait for its completion, then re-run the gate.
   That dispatch-fix-rerun cycle is one iteration of the loop below.
5. **Report** — render the report template below. Every section is
   mandatory; verdicts must cover 21/21 skills, and threshold rows must
   cite the actual values read from the profile.

### Report template

```text
# SDLC Review Report — <slug>, iteration <n>/5

## Skill triage (21/21 verdicts)
| skill | verdict | evidence / reason |
|---|---|---|
| <one row per skill, all 21> | EXECUTE \| NOT-APPLICABLE | <one line> |

## code-quality-reviewer
| metric | profile threshold | observed | status |
|---|---|---|---|
| phpinsights quality | <quality.phpinsights.quality> | <observed> | PASS/FAIL |
| phpinsights architecture | <quality.phpinsights.architecture> | <observed> | PASS/FAIL |
| phpinsights style | <quality.phpinsights.style> | <observed> | PASS/FAIL |
| phpinsights complexity | <quality.phpinsights.complexity> | <observed> | PASS/FAIL |
| deptrac violations | <quality.deptrac_violations> | <observed> | PASS/FAIL |
| psalm errors | <quality.psalm_errors> | <observed> | PASS/FAIL |
| infection MSI | <quality.infection_msi> | <observed> | PASS/FAIL |
(null make targets: listed as capability-absent, skipped)

## fr-nfr-reviewer
| requirement | verdict | note |
|---|---|---|
| <FR/NFR id, one row each> | PASS/FAIL | <one line> |

## Gate iterations
| iteration | new findings |
|---|---|
| <n> | <count> |

## Verdict: PASS | ESCALATED
```

## Loop & exit condition

Each iteration: remediation dispatch (if findings), then a fresh
`fr-nfr-gate.sh` run; record the new-findings count in the report.
Exit condition (FR-1 stage table): **zero new findings in last gate
iteration**.

## Iteration guard

`MAX_ITERATIONS=5`. One iteration = one gate run (plus the preceding
remediation dispatch after the first). Keep an explicit counter and
restate it every turn (`review iteration <n>/5`).

## Failure escalation

On guard breach, emit the canonical report (with the review report
above attached) and stop:

```text
=== SDLC ESCALATION ===
stage: review            iteration: <n>/5
exit_condition: zero new findings in last gate iteration
status: NOT MET
blocking_finding: <first unresolved gate finding>
iteration_log: <one line per iteration: findings count + remediation summary>
recommended_action: <human next step>
=== END ===
```
