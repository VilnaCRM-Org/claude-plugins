---
description: "Review implemented changes: 22-skill applicability triage, multi-lens quality and FR/NFR review, gate loop until zero new findings"
argument-hint: "[specs-dir]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]
---

# /sdlc-review — triage-based multi-lens review gate (FR-6)

Stage 4 of the SDLC loop. Every shipped skill receives a recorded
applicability verdict, two reviewer agents examine the change set from
independent lenses (FR/NFR and code quality), and the gate loops until
BOTH lenses are clean — zero new FR/NFR findings AND every quality
threshold met. This command never writes files itself (`allowed-tools`
excludes Write): remediation is delegated to a `php-implementer`
subagent, and this command commits that remediation between iterations
(the dispatching loop owns commits — `php-implementer` runs no git).

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  REVIEW_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ```

  On exit 1, ABORT and instruct the user to run `/sdlc-setup`. Capturing
  `REVIEW_STARTED_AT` here records the loop start for the conclusion comment's
  duration (FR-10); it has no effect on the stage exit condition.
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
   at `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md` (22 in v1):
   - Decide from the skill's frontmatter (`name` + trigger-rich
     `description`, including profile-gating conditions like "Skip when
     `capabilities.structurizr` is false") plus the decision guide —
     and NOTHING else. Never load a skill body to decide a verdict.
   - Record one verdict per skill: `EXECUTE` with one-line evidence
     (which changed file or behavior triggers it) or `NOT-APPLICABLE`
     with a one-line reason (including profile-gated skips).
   - All 22 verdicts are recorded before any body loads. Token bound
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
     suppressions or threshold cuts. Its Task prompt must carry the
     one-line change summary, the changed-file list, the skill-triage
     verdicts, and — on re-invocation — the prior iteration ledger, so
     its `file:line` findings are scoped to the change set and the
     iteration counter resumes rather than resets.
   - `fr-nfr-reviewer`: owns the FR/NFR gate run — it resolves the
     gate runner from the profile (`make.fr_nfr_gate`, `null` → the
     plugin's `fr-nfr-gate.sh`), executes it, builds the
     per-requirement PASS/FAIL matrix against `specs/<slug>/`, and
     reports the new-findings count. Its Task prompt must carry the
     spec bundle path, the changed-file list plus a one-line change
     summary, the latest stage-3 test outcome (so "implemented AND
     tested" PASS rows cite it instead of re-running the
     `make.tests`/`make.e2e` evidence targets the agent is permitted to
     run), and — on re-invocation — the prior iteration ledger.
     Never run the gate script directly from this command: the agent
     is the single gate owner, so each iteration pays for exactly one
     gate run and yields exactly one new-findings count.
4. **Remediation gate loop (both lenses)** — read the convergence
   signal from the `fr-nfr-reviewer` report's mandatory last line
   (`FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=...`)
   and the `code-quality-reviewer` report's `Verdict: PASS | FAIL`
   plus its FAIL threshold rows. The stage exit condition is BOTH
   lenses clean in the last iteration: `fr-nfr-reviewer`
   `new_findings=0 verdict=PASS` AND every non-SKIPPED
   `code-quality-reviewer` threshold row PASS. A `code-quality-reviewer`
   FAIL row (e.g. phpinsights complexity below the profile `quality.*`
   floor, deptrac violations over threshold) blocks the stage verdict
   exactly like an FR/NFR finding — it never silently defers to stage 6
   CI.
   `fr-nfr-reviewer` `verdict=DEGRADED` (spec bundle missing or empty)
   is a blocking finding, not a loop state: nothing exists to remediate
   and re-invoking cannot change the outcome, so escalate immediately —
   do NOT re-invoke either agent — with `recommended_action` "re-run
   /sdlc-plan". (A gate-runner-unavailable degrade is different: the
   agent still reports PASS/FAIL from its manually built matrix, so
   the loop proceeds normally with the degrade note.)
   On findings from EITHER lens: this command cannot write fixes (no
   Write tool), so it owns the remediation cycle:
   1. **Dispatch** the combined findings — FR/NFR findings AND
      `code-quality-reviewer` FAIL-row root-cause fixes — as a single
      remediation task to a `php-implementer` subagent (Task tool) and
      wait for its completion. The agent lands fixes in the working
      tree only; it runs NO git (`php-implementer` forbids it — the
      dispatching loop owns commits).
   2. **Commit** the remediation via Bash (`allowed-tools` includes
      Bash), e.g. `git add -A && git commit -m "review: gate iteration
      <n> remediation"`, BEFORE re-invoking the reviewers. The gate
      runner inside `fr-nfr-reviewer` resolves `head_sha=$(git
      rev-parse HEAD)` and posts the "BMAD FR/NFR Review Gate" commit
      status to that SHA — committing here is what makes the status
      land on a tree that actually contains the fixes the gate is
      about to verify, and it hands committed work to downstream
      stages.
   3. **Re-invoke** BOTH `fr-nfr-reviewer` and `code-quality-reviewer`
      (in parallel, as in step 3), passing each its prior iteration
      ledger (findings list and counts from all iterations so far) so
      every agent computes "new" as a delta and resumes — never
      resets — its iteration counter. A lens already clean in the prior
      iteration is still re-invoked so the verdict is computed on the
      committed post-fix tree, not stale output.
   That dispatch-commit-reinvoke cycle is one iteration of the loop
   below.
5. **Report** — render the report template below. Every section is
   mandatory; verdicts must cover 22/22 skills, and threshold rows must
   cite the actual values read from the profile.

### Report template

```text
# SDLC Review Report — <slug>, iteration <n>/5

## Skill triage (22/22 verdicts)
| skill | verdict | evidence / reason |
|---|---|---|
| <one row per skill, all 22> | EXECUTE \| NOT-APPLICABLE | <one line> |
| security-audit | EXECUTE \| NOT-APPLICABLE | <adversarial vuln-hunt against the running service when in scope, else one-line reason> |

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
(any FAIL row blocks the stage verdict and joins the next remediation dispatch)

## fr-nfr-reviewer
| requirement | verdict | note |
|---|---|---|
| <FR/NFR id, one row each> | PASS/FAIL | <one line> |

## Gate iterations
| iteration | new findings |
|---|---|
| <n> | <count> |
(copied verbatim from the fr-nfr-reviewer iteration ledger)

## Verdict: PASS | ESCALATED
(PASS requires BOTH lenses clean: fr-nfr-reviewer new_findings=0
verdict=PASS AND every non-SKIPPED code-quality-reviewer row PASS)
```

## Loop & exit condition

Each iteration: remediation dispatch (if findings from either lens),
then a commit of that remediation, then a fresh parallel invocation of
`fr-nfr-reviewer` (which performs the iteration's single gate run) and
`code-quality-reviewer`; record the reported new-findings count and the
quality threshold table in the report. Exit condition (FR-1 stage
table): **zero new findings in last gate iteration AND every
non-SKIPPED quality threshold row PASS** — both lenses clean.

### Conclusion comment (post-exit side effect, gated)

This does NOT change the single exit condition above — it is a side effect that
runs ONCE after the loop has already exited. After the loop closes (the exit
condition met, or escalation), capture `REVIEW_ENDED_AT="$(date -u
+%Y-%m-%dT%H:%M:%SZ)"`. Then, gated on `capabilities.publish_pr_comments` being
`true` (skip-with-note when false/absent), post the aggregate conclusion comment
EXACTLY ONCE for the whole loop (never per iteration, NFR-2) via the
`--conclusion` mode of the target mapped by `make.post_review_findings` (null →
`"${CLAUDE_PLUGIN_ROOT}/scripts/post-review-findings.sh"`), passing the three
lens ledgers, the captured timing, and the existing `iteration <n>/5` counter:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/post-review-findings.sh" --conclusion \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/security.json" \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/fr-nfr.json" \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/code-review.json" \
  --pr "$PR" --started-at "$REVIEW_STARTED_AT" --ended-at "$REVIEW_ENDED_AT" \
  --iterations "$ITERATION"
```

The poster is idempotent (hidden `<!-- sdlc-review:conclusion -->` marker) and
DEGRADES (FR-9, NFR-3): the flag false/absent, `gh` absent, no PR, empty/missing
ledgers, a mismatched base repo, or a `gh` write failure all skip-with-note and
exit 0 — this post NEVER fails or re-enters the review loop. Ownership is
`/sdlc-review` only: a `/sdlc-finish-pr` hand-off does NOT post a second
conclusion (FR-10).

## Iteration guard

`MAX_ITERATIONS=5`. One iteration = one parallel re-invocation of
`fr-nfr-reviewer` (exactly one gate run, executed inside the agent) and
`code-quality-reviewer`, plus the preceding remediation dispatch and
its commit after the first. Keep an explicit counter in lockstep with
the agents' own (`iteration <n>/5` in each report header) and restate
it every turn (`review iteration <n>/5`).

## Failure escalation

On guard breach (either lens still dirty at iteration 5) or a blocking
finding (e.g. a SPECS-MISSING `verdict=DEGRADED` report), emit the
canonical report (with the review report above attached) and stop:

```text
=== SDLC ESCALATION ===
stage: review            iteration: <n>/5
exit_condition: zero new gate findings AND every quality threshold PASS
status: NOT MET
blocking_finding: <first unresolved gate finding or quality FAIL row>
iteration_log: <one line per iteration: findings count + remediation summary>
recommended_action: <human next step>
=== END ===
```
