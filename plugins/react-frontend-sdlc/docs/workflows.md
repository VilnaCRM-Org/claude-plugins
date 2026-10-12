# Workflows

The plugin ships four Claude Code workflow scripts under `workflows/`. A
workflow is a JavaScript orchestration script that Claude Code runs with the
Workflow tool: deterministic control flow (loops, counters, fan-out) in the
script, model judgement only inside the agents it dispatches. The commands
under `commands/` remain the interactive, single-agent way to run each stage;
the workflows are the unattended form of the same loop for the parts of the
SDLC that benefit from fan-out and bounded repetition.

Invoke one by its namespaced name and pass its arguments in the prompt:

```text
/react-frontend-sdlc:fe-sdlc-pr-until-green 230
/react-frontend-sdlc:fe-sdlc-pr-until-green https://github.com/acme/app/pull/230 --reviewers cubic
/react-frontend-sdlc:fe-sdlc-review-panel currency-field --base origin/main
/react-frontend-sdlc:fe-sdlc-fr-nfr-review currency-field --summary "UICurrencyField wired into sign-up"
/react-frontend-sdlc:fe-sdlc-feature "Add a UICurrencyField component and wire it into sign-up"
```

`/workflows` lists them and shows live progress per phase. Every workflow
ends in exactly one of `SUCCESS`, `SUCCESS-WITH-REPORT` (a degrade path was
taken and is listed in `degrade_notes`), or `ESCALATED` (the canonical
`=== SDLC ESCALATION ===` block from the [SDLC loop](sdlc-loop.md), carried
in `escalation`). None of them runs unbounded: every loop has a counter the
report prints.

## `fe-sdlc-pr-until-green` — finish a PR with its AI reviewers

The loop most teams run by hand after a feature lands on a branch: ask the AI
reviewers, wait, fix what they and CI found, push, ask again. The workflow
turns it into a sensor-driven state machine.

| Step            | Who                                    | What                                                                                                                           |
| --------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Snapshot        | low-effort agent                       | runs `scripts/pr-state.sh --json` and returns its verdict verbatim                                                             |
| Request reviews | low-effort agent                       | runs `scripts/request-ai-reviews.sh` with the reviewers the sensor named (`--full` when CodeRabbit must re-read the same head) |
| Wait            | low-effort agent                       | runs `pr-state.sh --wait-seconds 540 --wait-verdicts WAIT` (or `WAIT,REQUEST` inside CodeRabbit's interval)                    |
| Fix             | `ci-fixer`, then `pr-comment-resolver` | root-cause fixes for failing checks and unresolved threads, in the working tree, no git                                        |
| FR/NFR gate     | nested `fe-sdlc-fr-nfr-review`         | runs the mandatory BMAD FR/NFR gate pinned to the PR head (`{ pr, head }`), fixes its findings, posts the commit status        |
| Publish         | general agent                          | format target when mapped, conventional commit with the task number, hooks on, `git push origin HEAD`                          |

The sensor's verdicts and their priority are documented in
[`scripts/pr-state.sh`](../scripts/pr-state.sh): `BLOCKED` > `FIX` >
`GATE` > `REQUEST` > `WAIT` > `READY`. `READY` means every required check
passes, the `BMAD FR/NFR Review Gate` status is `success` on the current
head, zero review threads are unresolved, and every reachable reviewer's latest
live review sits on the current head with state `APPROVED` — the state
CodeRabbit and cubic both post once their findings are addressed. A
reviewer no mention can reach (paused subscription, diff above CodeRabbit's
changed-file limit, status-check bot) is `SKIPPED`: reported in the
degrade notes, never counted as an approval (NFR-4).

The FR/NFR gate is **mandatory for every PR** and has no degrade path. The
sensor takes the `BMAD FR/NFR Review Gate` status out of the generic CI set
(so `ci-fixer` is never handed it, and `--required-checks` cannot waive it)
and reports it as `fr_nfr`. A head whose gate status is `missing` or
`failure` yields `GATE`: the workflow runs `fe-sdlc-fr-nfr-review` with
`{ pr, head }` (the nested run refuses a checkout that is not at that head
with a clean tree), publishes the fixes it made, and re-reads the state — a
pushed fix is a new head, so the gate runs again on the published code, and
only a gate run on a clean head turns the status green. A gate posted as
`pending` (a repository CI job running it) waits like any other check.

Arguments: a PR number or URL, optionally `--reviewers <list>` and
`--required-checks <list>`; or an object
`{ pr, reviewers, requiredChecks, maxFixRounds, maxWaitRounds, maxGateRounds, waitSeconds }`.
Without a PR the sensor resolves the current branch's PR.

Counters:

- `fix` — one per ci-fixer/resolver/publish round, max 5 for the run.
- `gate` — one per nested FR/NFR gate run, max 3 for the run; a gate that
  is still not green after three rounds escalates.
- `wait` — one per 9-minute poll, max 6 per head; resets when a push
  changes the head. A reviewer that acknowledged but never reviewed the
  head within the budget is dropped with a degrade note.
- `request` — one per mention round, max 3 per head; a reviewer that
  stays silent after three requests is dropped with a degrade note, while a
  reviewer that reviewed the head without approving escalates — its findings
  are outside the resolved threads and need a human. When
  `request-ai-reviews.sh` answers `WAIT:` (inside CodeRabbit's one-hour
  interval) the workflow waits through `REQUEST` verdicts instead of
  re-mentioning.

Escalates on `BLOCKED` (merged, closed, or conflicting PR), a `ci-fixer`
`BLOCKED` return, an escalated FR/NFR gate run, a failed push, or an
exhausted counter.

## `fe-sdlc-review-panel` — stage 4 as a verified fan-out

The `/fe-sdlc-review` command dispatches its reviewers one at a time. The
panel runs them in parallel and adds an adversarial verification pass so a
plausible-but-wrong finding never reaches the implementer.

1. **Scope** — one agent validates the profile, computes the changed-file
   set against the diff base, locates the `specs/<slug>/` bundle, and
   performs the skill triage from `skills/SKILL-DECISION-GUIDE.md`
   (EXECUTE / NOT-APPLICABLE for every skill).
2. **Review** — in parallel: `code-quality-reviewer`; `fr-nfr-reviewer`
   on every change set (against the bundle when one exists, else the PR
   description and linked issues, plus the baseline NFR catalog); one `accessibility-auditor` per family
   (`forms`, `keyboard`, `semantics-and-names`, `contrast-and-motion`) when
   UI files changed; and one technique lens per group of four EXECUTE
   skills, each reading the skill bodies in full.
3. **Verify** — every new finding is judged by three refuters with distinct
   lenses (correctness, standards, remedy), each told to default to
   refuted. A finding survives with at least two non-refutations.
4. **Fix** — confirmed findings are grouped by directory and handed to
   parallel `react-implementer` agents (at most four groups per
   iteration), TDD, no suppression.
5. Repeat until an iteration confirms zero new findings (`MAX_ITERATIONS=5`).
   Findings are de-duplicated against everything already seen, so a
   refuted finding does not reappear every round.

Arguments: the specs slug and optionally `--base <ref>`; or
`{ slug, base, maxIterations, a11yFamilies }`. A lens that reports
`SKIPPED` (for example dynamic a11y probing when
`capabilities.dynamic_a11y_testing` is false) is a degrade note; a lens
that reports `BLOCKED` escalates.

## `fe-sdlc-fr-nfr-review` — the BMAD FR/NFR gate as a bounded loop

The review panel runs `fr-nfr-reviewer` as one lens among several and
verifies its findings like any other. This workflow is the gate itself, the
loop the [bmad-fr-nfr-review-gate](../skills/bmad-fr-nfr-review-gate/SKILL.md)
skill describes, and it is **mandatory for every pull request with a
non-empty change set** (an empty diff has nothing to gate) — never skipped,
never passed with a report:

1. **Scope** — one agent validates the profile, computes the changed-file
   set against the diff base, and resolves the requirement sources: the
   given `specs/<slug>/`, or the newest one whose prd, epics-stories or
   brief names the changed files (a bundle counts as present only when it
   holds at least one of prd, architecture, epics-stories); and the PR
   (`--pr`, or the branch's PR) with its description and linked issues.
   Without a bundle the PR description and linked issues are the
   requirement source; the baseline NFR catalog applies either way. A
   named bundle that does not exist escalates at once (the caller passed a
   wrong slug). A change with neither a bundle nor a PR description /
   linked issue escalates too — an untraceable change cannot pass — after
   the gate script runs once so the head carries its fail-closed failure
   status. An unbundled branch therefore needs its
   PR open (a draft with acceptance criteria or `Closes #N` is enough)
   before the gate runs. With `--head <sha>` the agent also verifies the checkout
   sits at that PR head with a clean tree, because the gate posts its
   commit status for the local `HEAD`.
2. **Gate** — `fr-nfr-reviewer` runs the gate runner exactly once
   (`make.fr_nfr_gate`, or `scripts/fr-nfr-gate.sh` when that key is
   `null`), rebuilds the per-requirement matrix, and returns `verdict`,
   `new_findings`, `gate_run` and the findings. The workflow passes the
   prior iteration ledger back in, so "new" stays a delta and the counter
   never resets.
3. **Fix** — findings are grouped by directory and handed to parallel
   `react-implementer` agents (at most four groups per iteration), TDD,
   never a suppression or a spec edit.
4. Repeat until an iteration reports `new_findings=0` with `verdict=PASS`
   (`MAX_ITERATIONS=5`).

Arguments: the specs slug (when a bundle exists), optionally `--pr <n>`,
`--head <sha>`, `--base <ref>` and `--summary "<one line>"` (the gate's
impact context); or `{ slug, pr, head, base, summary, maxIterations }`.

Escalates on an invalid profile, a `BLOCKED` reviewer or implementer, a
`DEGRADED` reviewer (the requirement source vanished between Scope and
Gate), a gate runner the reviewer could not execute (`gate_run:
SKIPPED (<reason>)` — no `BMAD FR/NFR Review Gate` status was posted, and a
hand-built matrix never satisfies the mandatory gate), a `FAIL` verdict that cites no actionable finding (a
failing matrix row without a root-cause fix is a human decision), two
consecutive gate runs without a findings count (transport failure or a
malformed `FR_NFR_NEW_FINDINGS:` line — one such run only consumes an
iteration and is re-run), or an exhausted counter. A findings
count that fails to decrease across three iterations is logged as
non-converging so the ledger explains an eventual escalation.

## `fe-sdlc-feature` — the whole loop, unattended

Composes the plugin's stages for one planned feature and nests the three
workflows above:

| Stage        | Mechanism                                                                                                       | Bound                                       |
| ------------ | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| Setup check  | `validate-profile.sh` + `setup-preflight.sh`                                                                    | halt → `/fe-sdlc-setup`                     |
| Resolve plan | adopt the managed issue and `specs/<slug>/`; follow `/fe-sdlc-issue` / `/fe-sdlc-plan` once if missing          | one attempt, then escalate                  |
| Implement    | `react-implementer` per independent story in parallel, dependent stories one at a time                          | 5 rounds for the run; `BLOCKED` escalates   |
| Review       | `workflow('react-frontend-sdlc:fe-sdlc-review-panel')`                                                          | the panel's own guard                       |
| FR/NFR gate  | `workflow('react-frontend-sdlc:fe-sdlc-fr-nfr-review')` against the resolved `specs/<slug>/`                    | the gate's own counter; escalation halts    |
| QA           | `qa-visual-tester` against the running production-parity stack                                                  | `FAIL` loops back to Implement, max 2       |
| Finish PR    | PR create/update per `/fe-sdlc-finish-pr` step 1, then `workflow('react-frontend-sdlc:fe-sdlc-pr-until-green')` | the finisher's own counters                 |

Arguments: the task text or issue URL; or `{ task, slug, issue, reviewers }`.
Resumability comes from the artifacts: a story already checked off, an
existing issue, or a readiness `PASS` is adopted, never redone. If the
runtime cannot resolve a nested workflow by name the run escalates with the
manual commands to continue by hand rather than duplicating their logic.
The plan stage guarantees the spec bundle and the gate never skips, so any
gate escalation halts the feature before QA. The gate runs again in Finish
PR: `fe-sdlc-pr-until-green` requires a green `BMAD FR/NFR Review Gate`
status on the final PR head, which the pre-QA run (on uncommitted code)
cannot provide.

## How the workflows find the plugin

A workflow script has no filesystem access, so each agent it dispatches
resolves the plugin root itself, in this order: `$CLAUDE_PLUGIN_ROOT` when
Claude Code set it, the newest install-cache copy under
`~/.claude/plugins/cache/*/react-frontend-sdlc/*/`, then a marketplace
checkout found under the home directory. An agent that finds none returns
`BLOCKED` and the workflow escalates.

## Testing

`tests/lib/workflow-harness.mjs` reproduces the Workflow-tool contract in
node — `agent`, `parallel`, `pipeline`, `phase`, `log`, `workflow`, `args`,
`budget` — with scripted replies from `tests/fixtures/workflows/*.json`, so
`tests/workflows.bats` pins every counter, phase order, dispatch target and
escalation path without a model in the loop. `tests/pr-state.bats` pins the
sensor's verdict table against fixture PR shapes. Run both with the rest of
the suite:

```bash
npx --yes bats plugins/react-frontend-sdlc/tests
```
