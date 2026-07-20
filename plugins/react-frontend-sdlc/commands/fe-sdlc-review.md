---
description: "Review implemented frontend changes: 19-skill applicability triage, multi-lens quality + FR/NFR review with a MANDATORY accessibility gate, looping until zero new findings and a clean a11y verdict"
argument-hint: "[slug | PR-URL]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]
---

# /fe-sdlc-review — triage-based multi-lens review gate (FR-6)

Stage 4 of the SDLC loop. Every shipped skill receives a recorded
applicability verdict, three reviewer agents examine the change set from
independent lenses (FR/NFR, code quality, and accessibility), and the
gate loops until ALL THREE lenses are clean — zero new FR/NFR findings,
every quality threshold met, AND a clean accessibility verdict.
Accessibility is non-negotiable: an `accessibility-auditor` finding
blocks the stage verdict exactly like an FR/NFR finding and never
silently defers to stage 5 QA. This command never writes files itself
(`allowed-tools` excludes Write): remediation is delegated to a
`react-implementer` subagent, and this command commits that remediation
between iterations (the dispatching loop owns commits — `react-implementer`
runs no git).

## Inputs

- First action (stage contract): run

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
  REVIEW_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ```

  On exit 1, ABORT and instruct the user to run `/fe-sdlc-setup`. Capturing
  `REVIEW_STARTED_AT` here records the loop start for the conclusion comment's
  duration (FR-10); it has no effect on the stage exit condition.
- The change set: the working branch's diff against the default branch.
- The planning chain: `specs/<slug>/` from the `slug` argument or the
  `SPECS_DIR:` line emitted by `/fe-sdlc-plan` — requirement
  traceability for the FR/NFR lens. When the argument is a PR URL,
  resolve the branch (and the PR number for the conclusion comment) from
  it, then its `specs/<slug>/` bundle.
- Direct-load the triage decision guide (§1.2 dependency edge):

  ```text
  ${CLAUDE_PLUGIN_ROOT}/skills/SKILL-DECISION-GUIDE.md
  ```

- Profile `quality.*` values — the protected thresholds every check
  reports against — and the `capabilities.accessibility_audit` /
  `capabilities.dynamic_a11y_testing` flags that scope the a11y lane.

## Procedure

1. **Applicability triage (ADR-5, NFR-5)** — for EVERY skill directory
   at `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md` (19 in v1):
   - Decide from the skill's frontmatter (`name` + trigger-rich
     `description`, including profile-gating conditions like "Skip when
     `capabilities.figma` is false") plus the decision guide — and
     NOTHING else. Never load a skill body to decide a verdict.
   - Record one verdict per skill: `EXECUTE` with one-line evidence
     (which changed file or behavior triggers it) or `NOT-APPLICABLE`
     with a one-line reason (including profile-gated skips).
   - All 19 verdicts are recorded before any body loads. Token bound
     (NFR-5): full SKILL.md bodies + reference files load only for
     EXECUTE verdicts.
2. **Execute applicable skills** — load each EXECUTE skill's body and
   apply its checks against the change set, collecting findings.
3. **Multi-lens review** — dispatch all three reviewer agents via the
   Task tool, in parallel:
   - `code-quality-reviewer`: runs the read-only quality targets from
     the profile `make` map (`make.lint_eslint`, `make.lint_tsc`,
     `make.lint_md`, `make.lint_dup`, `make.lint_metrics`,
     `make.lint_deps`, `make.test_mutation` + `make.merge_mutation_reports`
     — skipping `null` entries with a capability-absent note, NFR-4) and
     reports observed values against the profile `quality.*` thresholds.
     It never proposes suppressions (`eslint-disable`, `@ts-ignore`),
     baselines, or threshold cuts. Its Task prompt must carry the
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
     `make.test_integration`/`make.test_e2e` evidence targets the agent
     is permitted to run), and — on re-invocation — the prior iteration
     ledger. Never run the gate script directly from this command: the
     agent is the single gate owner, so each iteration pays for exactly
     one gate run and yields exactly one new-findings count.
   - `accessibility-auditor` (MANDATORY — a11y is non-negotiable): owns
     the accessibility gate. It resolves the a11y runner from the
     profile (`make.a11y`, `null` → its bundled a11y lane: axe-core +
     Playwright role/label probing + static ARIA / semantic / contrast /
     focus-order checks), audits the change set against WCAG 2.2 AA
     (POUR), and reports the per-criterion PASS/FAIL matrix plus the
     new-findings count. Dynamic (live-browser) probing is gated by
     `capabilities.dynamic_a11y_testing` + `make.start`; when either is
     absent it degrades to the static lane with a note — the static
     a11y lane ALWAYS runs and ALWAYS gates (a11y never skips). Its Task
     prompt must carry the one-line change summary, the changed-file
     list (the rendered UI surface — `*.tsx` and the module the story
     names), the skill-triage verdicts, and — on re-invocation — the
     prior iteration ledger.
4. **Remediation gate loop (all three lenses)** — read the convergence
   signals: the `fr-nfr-reviewer` report's mandatory last line
   (`FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=...`),
   the `accessibility-auditor` report's mandatory last line
   (`ACCESSIBILITY_AUDITOR: iteration=<n>/5 new_findings=<n> verdict=...`),
   and the `code-quality-reviewer` report's `Verdict: PASS | FAIL` plus
   its FAIL threshold rows. The stage exit condition is ALL THREE lenses
   clean in the last iteration: `fr-nfr-reviewer` `new_findings=0
   verdict=PASS` AND `accessibility-auditor` `new_findings=0
   verdict=PASS` AND every non-SKIPPED `code-quality-reviewer` threshold
   row PASS. A `code-quality-reviewer` FAIL row (e.g. an rca metrics
   hard-fail, an eslint/tsc error over the fixed `0` ceiling, a jscpd
   clone, a depcruise violation, mutation MSI below the `quality.mutation_msi`
   floor) blocks the stage verdict exactly like an FR/NFR finding — it
   never silently defers to stage 6 CI. An `accessibility-auditor` FAIL
   row (a WCAG 2.2 AA violation — missing accessible name, broken focus
   order, insufficient contrast, an unlabeled control) blocks the stage
   verdict exactly the same way and never defers to stage 5 QA.
   `fr-nfr-reviewer` `verdict=DEGRADED` (spec bundle missing or empty)
   is a blocking finding, not a loop state: nothing exists to remediate
   and re-invoking cannot change the outcome, so escalate immediately —
   do NOT re-invoke the agents — with `recommended_action` "re-run
   /fe-sdlc-plan". An `accessibility-auditor` `verdict=DEGRADED` arises
   ONLY when the change set touches no rendered UI surface (zero
   render-path files): it is a clean no-op (a11y lens satisfied for this
   change set), recorded with a note and not re-invoked for remediation;
   any change set touching a `*.tsx` or the named module MUST yield a
   PASS/FAIL static verdict instead. (A dynamic-probing or a11y-runner
   degrade is different: the static lane still reports PASS/FAIL, so the
   loop proceeds normally with the degrade note.)
   On findings from ANY lens: this command cannot write fixes (no Write
   tool), so it owns the remediation cycle:
   1. **Dispatch** the combined findings — FR/NFR findings,
      `code-quality-reviewer` FAIL-row root-cause fixes, AND
      `accessibility-auditor` WCAG findings — as a single remediation
      task to a `react-implementer` subagent (Task tool) and wait for
      its completion. The agent lands fixes in the working tree only; it
      runs NO git (`react-implementer` forbids it — the dispatching loop
      owns commits). Fixes change the CODE (a real accessible name, a
      corrected `aria-*`, a contrast-passing token), never a suppression.
   2. **Commit** the remediation via Bash (`allowed-tools` includes
      Bash), e.g. `git add -A && git commit -m "review: gate iteration
      <n> remediation"`, BEFORE re-invoking the reviewers. The gate
      runner inside `fr-nfr-reviewer` resolves `head_sha=$(git
      rev-parse HEAD)` and posts the "BMAD FR/NFR Review Gate" commit
      status to that SHA — committing here is what makes the status
      land on a tree that actually contains the fixes the gate is
      about to verify, and it hands committed work to downstream
      stages.
   3. **Re-invoke** all three of `fr-nfr-reviewer`,
      `code-quality-reviewer`, and `accessibility-auditor` (in parallel,
      as in step 3), passing each its prior iteration ledger (findings
      list and counts from all iterations so far) so every agent computes
      "new" as a delta and resumes — never resets — its iteration
      counter. A lens already clean in the prior iteration is still
      re-invoked so the verdict is computed on the committed post-fix
      tree, not stale output.
   That dispatch-commit-reinvoke cycle is one iteration of the loop
   below.
5. **Report** — render the report template below. Every section is
   mandatory; verdicts must cover 19/19 skills, and threshold rows must
   cite the actual values read from the profile.

### Report template

```text
# SDLC Review Report — <slug>, iteration <n>/5

## Skill triage (19/19 verdicts)
| skill | verdict | evidence / reason |
|---|---|---|
| <one row per skill, all 19> | EXECUTE \| NOT-APPLICABLE | <one line> |
| frontend-performance-accessibility | EXECUTE \| NOT-APPLICABLE | <a11y/perf static checks against the changed UI surface when in scope; the live a11y verdict is owned by the always-dispatched accessibility-auditor agent> |

## code-quality-reviewer
| metric | profile threshold | observed | status |
|---|---|---|---|
| eslint errors | <quality.eslint_errors> | <observed> | PASS/FAIL |
| eslint warnings | <quality.eslint_warnings> | <observed> | PASS/FAIL |
| tsc errors | <quality.tsc_errors> | <observed> | PASS/FAIL |
| markdownlint errors | <quality.markdownlint_errors> | <observed> | PASS/FAIL |
| jscpd clones | <quality.jscpd_clones> | <observed> | PASS/FAIL |
| depcruise violations | <quality.depcruise_violations> | <observed> | PASS/FAIL |
| rca metrics gate | <quality.metrics_enforced> | <observed> | PASS/FAIL |
| mutation MSI | <quality.mutation_msi> | <observed> | PASS/FAIL |
(null make targets: listed as capability-absent, skipped)
(any FAIL row blocks the stage verdict and joins the next remediation dispatch)

## fr-nfr-reviewer
| requirement | verdict | note |
|---|---|---|
| <FR/NFR id, one row each> | PASS/FAIL | <one line> |

## accessibility-auditor (MANDATORY — a11y is non-negotiable)
| WCAG 2.2 AA criterion / axe rule | verdict | note |
|---|---|---|
| <one row per audited criterion> | PASS/FAIL/N-A | <one line; N-A needs a concrete source-backed reason; lanes: dynamic\|static-only> |
(any FAIL row blocks the stage verdict and joins the next remediation dispatch)

## Gate iterations
| iteration | new findings (fr-nfr / a11y) |
|---|---|
| <n> | <count> / <count> |
(copied verbatim from the fr-nfr-reviewer and accessibility-auditor iteration ledgers)

## Verdict: PASS | ESCALATED
(PASS requires ALL THREE lenses clean: fr-nfr-reviewer new_findings=0
verdict=PASS AND accessibility-auditor new_findings=0 verdict=PASS AND
every non-SKIPPED code-quality-reviewer row PASS)
```

## Loop & exit condition

Each iteration: remediation dispatch (if findings from any lens), then a
commit of that remediation, then a fresh parallel invocation of
`fr-nfr-reviewer` (which performs the iteration's single gate run),
`accessibility-auditor` (the iteration's single a11y audit), and
`code-quality-reviewer`; record the reported new-findings counts and the
quality threshold table in the report. Exit condition (FR-1 stage
table): **zero new FR/NFR findings AND zero new a11y findings in the last
iteration AND every non-SKIPPED quality threshold row PASS** — all three
lenses clean.

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
# Resolve the poster from make.post_review_findings, the SAME null-substitution
# the per-lens Publish steps use: read the profile value (common.sh profile_get),
# falling back to the bundled script when the key is null (its shipped default).
# PR is optional: when unset, --pr is omitted and the poster resolves the PR
# from the current branch or degrades (skip-with-note, FR-9) — never a crash.
profile="$(profile_path)"
POSTER="$(profile_get "$profile" make.post_review_findings "")"
POSTER="${POSTER:-${CLAUDE_PLUGIN_ROOT}/scripts/post-review-findings.sh}"
"$POSTER" --conclusion \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/accessibility.json" \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/fr-nfr.json" \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/code-review.json" \
  ${PR:+--pr "$PR"} --started-at "$REVIEW_STARTED_AT" \
  --ended-at "$REVIEW_ENDED_AT" --iterations "$ITERATION"
```

(`profile_path` / `profile_get` are the `lib/common.sh` helpers the plugin
scripts already source; a non-null `make.post_review_findings` maps to a custom
publisher, otherwise the bundled `scripts/post-review-findings.sh` is used.)

The poster is idempotent (hidden `<!-- sdlc-review:conclusion -->` marker) and
DEGRADES (FR-9, NFR-3): the flag false/absent, `gh` absent, no PR, empty/missing
ledgers, a mismatched base repo, or a `gh` write failure all skip-with-note and
exit 0 — this post NEVER fails or re-enters the review loop. Ownership is
`/fe-sdlc-review` only: a `/fe-sdlc-finish-pr` hand-off does NOT post a second
conclusion (FR-10).

## Iteration guard

`MAX_ITERATIONS=5`. One iteration = one parallel re-invocation of
`fr-nfr-reviewer` (exactly one gate run, executed inside the agent),
`accessibility-auditor` (exactly one a11y audit, executed inside the
agent), and `code-quality-reviewer`, plus the preceding remediation
dispatch and its commit after the first. Keep an explicit counter in
lockstep with the agents' own (`iteration <n>/5` in each report header)
and restate it every turn (`review iteration <n>/5`).

## Failure escalation

On guard breach (any lens still dirty at iteration 5) or a blocking
finding (e.g. a SPECS-MISSING `verdict=DEGRADED` report, or a still-open
WCAG 2.2 AA violation), emit the canonical report (with the review report
above attached) and stop:

```text
=== SDLC ESCALATION ===
stage: review            iteration: <n>/5
exit_condition: zero new FR/NFR + a11y gate findings AND every quality threshold PASS
status: NOT MET
blocking_finding: <first unresolved gate finding, a11y violation, or quality FAIL row>
iteration_log: <one line per iteration: fr-nfr + a11y findings counts + remediation summary>
recommended_action: <human next step>
=== END ===
```
