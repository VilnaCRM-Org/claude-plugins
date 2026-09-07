# Workflows

The plugin ships three Claude Code workflow scripts under `workflows/`. A
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
| Publish         | general agent                          | format target when mapped, conventional commit with the task number, hooks on, `git push origin HEAD`                          |

The sensor's verdicts and their priority are documented in
[`scripts/pr-state.sh`](../scripts/pr-state.sh): `BLOCKED` > `FIX` >
`REQUEST` > `WAIT` > `READY`. `READY` means every required check passes,
zero review threads are unresolved, and every reachable reviewer's latest
live review sits on the current head with state `APPROVED` — the state
CodeRabbit and cubic both post once their findings are addressed. A
reviewer no mention can reach (paused subscription, diff above CodeRabbit's
changed-file limit, status-check bot) is `SKIPPED`: reported in the
degrade notes, never counted as an approval (NFR-4).

Arguments: a PR number or URL, optionally `--reviewers <list>` and
`--required-checks <list>`; or an object
`{ pr, reviewers, requiredChecks, maxFixRounds, maxWaitRounds, waitSeconds }`.
Without a PR the sensor resolves the current branch's PR.

Counters:

- `fix` — one per ci-fixer/resolver/publish round, max 5 for the run.
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
`BLOCKED` return, a failed push, or an exhausted counter.

## `fe-sdlc-review-panel` — stage 4 as a verified fan-out

The `/fe-sdlc-review` command dispatches its reviewers one at a time. The
panel runs them in parallel and adds an adversarial verification pass so a
plausible-but-wrong finding never reaches the implementer.

1. **Scope** — one agent validates the profile, computes the changed-file
   set against the diff base, locates the `specs/<slug>/` bundle, and
   performs the skill triage from `skills/SKILL-DECISION-GUIDE.md`
   (EXECUTE / NOT-APPLICABLE for every skill).
2. **Review** — in parallel: `code-quality-reviewer`; `fr-nfr-reviewer`
   when a spec bundle exists; one `accessibility-auditor` per family
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

## `fe-sdlc-feature` — the whole loop, unattended

Composes the plugin's stages for one planned feature and nests the two
workflows above:

| Stage        | Mechanism                                                                                                       | Bound                                     |
| ------------ | --------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| Setup check  | `validate-profile.sh` + `setup-preflight.sh`                                                                    | halt → `/fe-sdlc-setup`                   |
| Resolve plan | adopt the managed issue and `specs/<slug>/`; follow `/fe-sdlc-issue` / `/fe-sdlc-plan` once if missing          | one attempt, then escalate                |
| Implement    | `react-implementer` per independent story in parallel, dependent stories one at a time                          | 5 rounds for the run; `BLOCKED` escalates |
| Review       | `workflow('react-frontend-sdlc:fe-sdlc-review-panel')`                                                          | the panel's own guard                     |
| QA           | `qa-visual-tester` against the running production-parity stack                                                  | `FAIL` loops back to Implement, max 2     |
| Finish PR    | PR create/update per `/fe-sdlc-finish-pr` step 1, then `workflow('react-frontend-sdlc:fe-sdlc-pr-until-green')` | the finisher's own counters               |

Arguments: the task text or issue URL; or `{ task, slug, issue, reviewers }`.
Resumability comes from the artifacts: a story already checked off, an
existing issue, or a readiness `PASS` is adopted, never redone. If the
runtime cannot resolve a nested workflow by name the run escalates with the
two manual commands to continue by hand rather than duplicating their
logic.

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
