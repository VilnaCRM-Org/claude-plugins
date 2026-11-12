# Workflows

The plugin ships four Workflow scripts under `workflows/`. A Workflow script is plain JavaScript that Claude Code runs with the Workflow tool: the script owns the control flow (loops, counters, fan-out, hand-backs) and dispatches agents for every step that needs judgement. The commands under `commands/` stay the interactive way to run each stage, and the command path is the only one that runs Ralph's own loop; the workflows are the unattended form of the same loop, with the same agents, counters, exit conditions and escalation block (see [the SDLC loop](sdlc-loop.md)).

| Workflow | Source | Kind | Nests |
| --- | --- | --- | --- |
| `rs-sdlc-fr-nfr-review` | [rs-sdlc-fr-nfr-review.js](../workflows/rs-sdlc-fr-nfr-review.js) | leaf | nothing |
| `rs-sdlc-review-panel` | [rs-sdlc-review-panel.js](../workflows/rs-sdlc-review-panel.js) | leaf | nothing |
| `rs-sdlc-pr-until-green` | [rs-sdlc-pr-until-green.js](../workflows/rs-sdlc-pr-until-green.js) | leaf when `onGate` is `'return'` | `rs-sdlc-fr-nfr-review`, only when `onGate` is `'nested'` |
| `rs-sdlc-feature` | [rs-sdlc-feature.js](../workflows/rs-sdlc-feature.js) | top level only | `rs-sdlc-review-panel`, `rs-sdlc-fr-nfr-review`, `rs-sdlc-pr-until-green` |

Start a workflow with the Workflow tool in a repository prepared by `/rs-sdlc-setup`, naming it by its plugin-qualified name and passing its arguments as a string or as an object. Every run ends with exactly one `result`: `SUCCESS`, `SUCCESS-WITH-REPORT` (a degrade path was taken; `degrade_notes` names each one) or `ESCALATED` (the 7-field block of [the SDLC loop](sdlc-loop.md#escalation-block) in `escalation`). The single other value is the `GATE` hand-back of `rs-sdlc-pr-until-green` under `onGate: 'return'`, which is an instruction to its caller, never a final outcome. No workflow runs unbounded: every loop has a counter with a fixed cap, and the caps in the arguments only lower it.

## Runtime rules

All four files follow the same rules, and `tests/workflows.bats` checks each one statically:

- **Meta literal.** The first statement is `export const meta = {…}`, a pure literal (strings, keys and punctuation only) with `name` equal to the file stem, `description`, `whenToUse` and `phases: [{title, detail}]`. No `}` sits at column 0 before the closing one, and every `phase('<title>')` the script calls is declared in `meta.phases`.
- **Determinism.** No `Date.now()`, `Math.random()` or argless `new Date()`, and no filesystem or process API: the script sees only `args`, the agent replies and the nested results, so the same replies always give the same run.
- **Plugin root.** A script cannot read files, so every agent resolves the plugin root itself, in this order: `$CLAUDE_PLUGIN_ROOT`, the newest `~/.claude/plugins/cache/*/rust-backend-sdlc/*/` by `sort -V`, then `find "$HOME" -maxdepth 8 -path "*/plugins/rust-backend-sdlc/.claude-plugin/plugin.json"`. An agent that finds none returns `BLOCKED` and the workflow escalates.
- **Agent types.** Plugin agents are dispatched with the type `rust-backend-sdlc:<agent>`, which names a file under `agents/`. Helper steps (scope, sensor reads, review requests, staging, refuters, QA boot) run as untyped agents whose prompt names every command they may run; the only untyped agent that commits is the publish step described in [The publish-agent exception](#the-publish-agent-exception).
- **Verbatim sentences.** The prompt of every agent that runs `make`, `git commit` or `git push` (the implement, verify, fix and publish rounds) carries the background sentence and the container-precondition sentence of [the SDLC loop](sdlc-loop.md#background-rule) word for word.
- **Results.** Every return value carries `result` and `degrade_notes`; an `ESCALATED` result adds `escalation`, and only an `ESCALATED` result carries the block.

## Nested names and the call graph

A nested call always names the plugin-qualified workflow `rust-backend-sdlc:rs-sdlc-<name>`, for example `workflow('rust-backend-sdlc:rs-sdlc-fr-nfr-review', {pr, head})`; the harness scenarios key their canned nested results by the same string. The Workflow runtime allows one level of nesting, and the plugin keeps every path within it:

- `rs-sdlc-fr-nfr-review` and `rs-sdlc-review-panel` never call `workflow()`.
- `rs-sdlc-pr-until-green` takes `onGate: 'nested' | 'return'` with the default `'nested'` (a script has no runtime signal that tells it whether it runs at the top level). Its only `workflow()` call sits inside the branch guarded by `OPTS.onGate === 'nested'`.
- `rs-sdlc-feature` runs only at the top level and always calls `rs-sdlc-pr-until-green` with the literal `onGate: 'return'`.

**Static call-graph rule (ADR-18).** An edge is every literal that names a workflow. An edge from `rs-sdlc-pr-until-green` is excluded only when its call sits inside the branch guarded by `OPTS.onGate === 'nested'`. Under this rule the graph has depth at most 1: only `rs-sdlc-feature` has edges, and none of its targets has an edge of its own. When `rs-sdlc-pr-until-green` runs as a child, its caller must pass `onGate: 'return'`, so the guarded branch is never taken.

**A nested call that throws** (for example `unknown workflow: <name>` when the runtime cannot resolve the name, or the runtime refusing a second nesting level) ends the run `ESCALATED` with the manual command line that runs the same step by hand: the [degrade matrix](degrade-matrix.md) row D21.

## `rs-sdlc-fr-nfr-review`

The BMAD FR/NFR gate as a bounded leaf loop. It is mandatory for every pull request with a non-empty change set: it never passes without a real gate run that reports `new_findings=0` with `verdict=PASS`.

- **Arguments.** A string `[slug] [--slug s] [--base ref] [--summary text] [--pr n] [--head sha]` (quoted values allowed) or the object `{slug, pr, head, base, summary, maxIterations}`. `--pr` accepts only `N`, `#N` or a pull-request URL; trailing digits of a malformed value never become a PR number, and a malformed value escalates before any agent runs. `--head` is a 7 to 40 character commit sha. `maxIterations` is a whole number of at least 1 that only lowers the cap of 5; any other value escalates the same way.
- **Phases.** *Scope*: one low-effort agent runs `validate-profile.sh`, computes the diff base (one fetch, then `base_ref=HEAD` with a D24 note; a file list taken against `HEAD` after that fallback proves no empty change set, so the gate still runs and computes its own diff), resolves the requirement sources (the `specs/<N>-<slug>/` bundle with `prd.md` and `epics.md`, the pull-request description and its linked issues with a non-blank body) and checks that the tracked tree is clean and `HEAD` is the PR head. *Gate*: `fr-nfr-reviewer` runs the gate exactly once per iteration and ends with `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<PASS|FAIL>`; the workflow hands the prior ledger back, so "new" stays a delta. *Fix*: the open findings go to `rust-implementer` agents grouped by the first three path segments (`crates/<group>/<context>`), at most 4 groups; several groups run in parallel without the DB-backed targets, then one serialized verify step runs them.
- **Counter.** Gate iterations at most 5. A gate run without a findings count consumes one iteration and is re-run; two in a row escalate.
- **Returns.** `{result, iterations, new_findings, fixed, requirement_source, advisory, degrade_notes}`, plus `escalation` with `stage: review`.
- **Advisory runs.** Without a pull request (D11), with uncommitted tracked changes, or with `HEAD` off the PR head, the gate runs with `--advisory`: it posts no `BMAD FR/NFR Review Gate` status, and the run ends `SUCCESS-WITH-REPORT` at best.
- **Escalates on** an invalid profile, a named bundle that does not exist, a change with no requirement source (after one authoritative gate run records the fail-closed status), a reviewer that reports the source missing or could not run the gate runner, a `FAIL` verdict without an open finding, a `BLOCKED` implementer, or 5 iterations without a passing run.

## `rs-sdlc-review-panel`

Stage 4 as a verified fan-out: three lenses, three refuters per finding, fixes by bounded context.

- **Arguments.** `[slug] [--slug s] [--base ref]` or `{slug, base, maxIterations, securityFamilies: ['all']}`; `securityFamilies` is `['all']` or a list of the eight security-audit family ids.
- **Phases.** *Scope*: profile check, merge base, change set, the branch guard `protected_changes <merge-base>` (a `PROTECTED:` line escalates as `protected file <path> changed (<commit>)` with the D23 remedy for that path, a `PROFILE_CHANGED:` line with `move the profile change to its own pull request from the default branch (/rs-sdlc-setup --refresh)`; a scope reply without the guard result is never a pass), the planning bundle and the triage of all 28 skills (EXECUTE or NOT APPLICABLE with a reason). *Review*: `code-quality-reviewer` and `fr-nfr-reviewer` in parallel, plus `security-auditor` when the diff touches a security-relevant path (`*.rs`, `Cargo.toml`, `Cargo.lock`, `migrations/`, `.sqlx/`, `deny.toml`, a Dockerfile, `.github/workflows/`). *Verify*: every new finding goes to three refuters (`correctness`, `standards`, `remedy`) told to default to refuted; a finding survives with at least two non-refutations, and a finding with a missing vote is kept as unverified with a degrade note. *Fix*: surviving findings go to `rust-implementer` groups keyed by `crates/<group>/<context>`, at most 4 per iteration; the rest, and every incomplete group, are carried into the next iteration.
- **Counter.** Iterations at most 5.
- **Returns.** `{result, iterations, findings, fixed, carried, degrade_notes}`, plus `escalation` with `stage: review`.
- **Escalates on** an invalid profile, a protected change, a lens that returns nothing or reports `BLOCKED` or `SKIPPED` (a lens that did not review never passes as a note), a lens finding that quotes the `BLOCKED: protected configuration <path>` line (that line verbatim, D23; never verified or fixed), a `FAIL` verdict with no open finding, a `BLOCKED` implementer, or 5 iterations that still confirm findings. The fixes stay uncommitted for the caller to publish.

## `rs-sdlc-pr-until-green`

The workflow form of `/rs-sdlc-finish-pr`: a state machine over the verdicts of the PR state sensor `pr-state.sh --json`, one verdict per read, in the priority `BLOCKED` > `FIX` > `GATE` > `REQUEST` > `WAIT` > `READY`.

| Verdict | Action | Counter |
| --- | --- | --- |
| `BLOCKED` | escalate: a merged, closed or conflicting PR, a failing human-gated check (named with its approval label, D9) or an unreachable sensor (D10) | — |
| `FIX` | `ci-fixer` for failing checks, `pr-comment-resolver` for unresolved threads, then the publish step | `fix`, cap 5 |
| `GATE` | the FR/NFR review on the PR head (nested, or handed back) and the publish step for its fixes | `gate`, cap 3 |
| `REQUEST` | one low-effort agent runs `request-ai-reviews.sh` with the arguments of the sensor's `NEXT:` hint | `request`, cap 3 |
| `WAIT` | `pr-state.sh --wait-seconds 540` while checks, the gate status or requested reviews are in flight | `wait`, cap 6 |
| `READY` | confirmed only by a second read on the same head; a READY payload that contradicts the exit condition escalates | — |

- **Phases.** *Snapshot*: `pr-state.sh --json`, one verdict per read, with `READY` confirmed by a second read on the same head. *Request reviews*: one low-effort agent runs `request-ai-reviews.sh` with the arguments of the sensor's `NEXT:` hint. *Wait*: `pr-state.sh --wait-seconds 540`. *Fix*: `ci-fixer` for failing checks and `pr-comment-resolver` for unresolved threads, or the D7 pass with `ai-review-loop.sh` as the comment source. *FR/NFR gate*: the nested `rs-sdlc-fr-nfr-review` on the PR head under `onGate: 'nested'`, or the `GATE` hand-back under `onGate: 'return'`. *Publish*: the publish step of [The publish-agent exception](#the-publish-agent-exception), which commits and pushes the fixes of a *Fix* round or a nested gate run before the next *Snapshot*.
- **Arguments.** A number; a string (`<n>`, `#<n>`, a PR URL, `--pr`, `--reviewers <list>`, `--required-checks <list>`); or `{pr, reviewers, requiredChecks, humanGatedChecks, maxFixRounds: 5, maxWaitRounds: 6, maxRequestRounds: 3, maxGateRounds: 3, waitSeconds: 540, onGate: 'nested' | 'return', carry: {counters, journal, degrade_notes}}`. `reviewers`, `requiredChecks` and `humanGatedChecks` default to `null`, so the sensor reads the profile; an empty `reviewers` list means no AI reviewer (D7).
- **Counters.** `fix` 5, `wait` 6, `request` 3, `gate` 3. With `carry`, every counter, the journal and the degrade notes resume from the earlier run of the same pull request; no counter is ever reset.
- **Returns.** `{result, pr, head, verdict, counters, journal, degrade_notes}`, plus `escalation` with `stage: finish-pr` and an iteration line such as `3/3 (fr_nfr_gate)`. With `onGate: 'return'`, a `GATE` verdict returns `{result: 'GATE', pr, head, counters, journal, degrade_notes}` instead of nesting.
- **Reviewers.** A reviewer that stays silent after 3 requests or 6 waits is dropped with a degrade note (its missing review is reported, never passed); a reviewer that reviewed the head without approving escalates after 3 requests. Inside CodeRabbit's request interval the wait also waits out `REQUEST` verdicts instead of mentioning again. When no AI reviewer covers the `READY` head, one `pr-comment-resolver` pass uses `ai-review-loop.sh` as the comment source (D7); each such pass spends one `fix` round and has its own journal line, also when it changes nothing.
- **No CI.** When `ci-fixer` reports `SKIPPED-NO-CI`, the CI half of every later snapshot counts as none (D8) and no fix round is spent on checks.
- **Degrade notes.** No AI reviewer (D7) and no CI (D8) leave one degrade note each, the workflow's own, however many sensor reads or agent reports name the condition.

## `rs-sdlc-feature`

The whole loop for one feature as a single top-level run.

| Phase | What runs | Bound |
| --- | --- | --- |
| Setup check | `validate-profile.sh`, `setup-preflight.sh --report`, the governance markers in `CLAUDE.md` and `AGENTS.md`, `_bmad/` | a failure halts with "run /rs-sdlc-setup on the default branch and commit the result" |
| Resolve plan | the issue, the `<type>/<N>-<slug>` branch and the `specs/<N>-<slug>/` bundle through the issue and plan command procedures; a new bundle is committed by the publish step | one attempt, then `ESCALATED` at `issue`, `branch` or `plan` |
| Stage | the re-entry protocol: `ralph_fix_plan_prepare`; only after `FIX_PLAN: absent` or `ARCHIVED:`, `stage-planning-artifacts.sh`, `bmalph implement` (plain, in the foreground) and, after `keep-progress`, `ralph_fix_plan_restore`, then `state_cache_update`; always `ralph_agent_md_patch` and the two-part `.ralph/PROJECT_CONTEXT.md` check | the order the agent reports is checked against the protocol; any deviation escalates |
| Implement | `rust-implementer` rounds over the stories of `.ralph/@fix_plan.md` (read only), layer-first; at most 4 independent stories in parallel on the DB-free targets, then one serialized `verify <round>` agent on the DB-backed targets; the publish step commits each story | 5 rounds for the whole run, QA fix rounds included |
| Review | nested `rs-sdlc-review-panel`; its fixes are published | the panel's own 5 iterations |
| FR/NFR gate | nested `rs-sdlc-fr-nfr-review` before QA (advisory while no pull request exists) | the gate's own 5 iterations |
| QA | `make start` and `make migrate`, then `qa-manual-tester` over HTTP; a `FAIL` hands its FAIL rows to one `rust-implementer` round directly, with no restage | 2 QA loops |
| Finish PR | the publish push, the pull request created or updated, then nested `rs-sdlc-pr-until-green` with `onGate: 'return'` and the hand-back loop | 3 feature-owned gate rounds |

- **Arguments.** A task string (an issue URL becomes `issue`) or `{task, slug, issue, reviewers, maxImplementRounds: 5, maxQaLoops: 2}`.
- **Returns.** `{result, task, branch, issue_url, specs_dir, pr_url, stages, degrade_notes}`, plus `escalation` whose `stage` is one of `setup-check`, `issue`, `branch`, `plan`, `implement`, `review`, `qa` or `finish-pr`. `stages` holds one row per stage with its iterations, exit condition and whether it was met.
- **No Ralph loop.** The workflow never runs `bmalph run`: Ralph's own loop cannot be driven from inside a script, and two implementers would race on the same tree. Its `degrade_notes` therefore always contain `bmalph run: not used (workflow path)`, and a finished run ends `SUCCESS-WITH-REPORT`. A story counts as done only when its serial round, or the verify step after its parallel round, ends `STATUS: COMPLETE` with `EXIT_SIGNAL: true`; an implementer reply with `status: BLOCKED` ends the run `ESCALATED`, the workflow analogue of a tripped breaker (D22).
- **State.** The workflow keeps no state comment. Inside one run, resume is the `carry` of the hand-back; across sessions, resume is the command path (`/rs-sdlc <N>`).
- **QA skip.** A boot reply `SKIPPED` is accepted only after a check confirms that the profile maps no `make.start` (D1); otherwise the run escalates.

## Hand-back contract

`rs-sdlc-feature` answers every `GATE` verdict itself, so no path nests deeper than one level:

1. The feature calls `workflow('rust-backend-sdlc:rs-sdlc-pr-until-green', {pr, reviewers, onGate: 'return', carry})`, with `carry` `null` on the first entry.
2. On a `GATE` verdict, pr-until-green spends one `gate` round and returns `{result: 'GATE', pr, head, counters, journal, degrade_notes}`.
3. The feature checks the hand-back (a sha for `head`, the same `pr`, counters, journal and notes present) and spends one round of its own gate counter.
4. It runs `workflow('rust-backend-sdlc:rs-sdlc-fr-nfr-review', {pr, head})` on that head. An escalated review, or an advisory run (the checkout is not the clean PR head), escalates the feature.
5. When the review fixed findings, the publish step commits them as `fix(#<N>): address review gate iteration <n> findings` and pushes.
6. The feature re-enters pr-until-green with `carry: {counters, journal, degrade_notes}`: the counters it handed back, its journal plus one hand-back entry, and its degrade notes. The counters resume and are never reset.
7. After 3 hand-back rounds the next `GATE` ends the run `ESCALATED` at stage `finish-pr` with iteration `3/3 (fr_nfr_gate)`.

```text
rs-sdlc-feature                              rs-sdlc-pr-until-green (child, onGate 'return')
  workflow(pr-until-green, carry: null)  ->  FIX ... GATE: gate 1/3
                                         <-  {result: 'GATE', pr, head, counters, journal, degrade_notes}
  workflow(fr-nfr-review, {pr, head})
  publish fix(#<N>): address review gate iteration 1 findings
  workflow(pr-until-green, carry)        ->  counters resume ... READY confirmed
                                         <-  {result: 'SUCCESS', pr, head, verdict, counters, journal, degrade_notes}
```

## The publish-agent exception

Agents never commit (FR-22): fixers and implementers leave their changes in the working tree. The publish step is the single explicit exception. It is an untyped workflow agent (no `rust-backend-sdlc:<agent>` type) that the workflow dispatches with the exact list of changes to commit, used by `rs-sdlc-pr-until-green` for its fix and gate rounds and by `rs-sdlc-feature` for the bundle, the stories, the review and QA fixes and the final push. Its prompt fixes the order:

1. One foreground `mkdir -p target/rust-sdlc/logs`; every later call runs in the background, logs to `target/rust-sdlc/logs/publish-<UTC>.log` and is polled with `common.sh wait_log` at most every 30 s within 1,800 s per call.
2. The issue number: the feature workflow passes the issue of its plan; pr-until-green derives it with `common.sh derive_issue_number` from the PR title, the head branch and the `Closes #N` line of the PR body. The pull-request number is never the issue number, and no source means nothing is committed.
3. The merge base, with the one-fetch fallback of D24, then `make <make.format>` in suffix form (`RUN_IN_CONTAINER=1` after the target in container mode).
4. The branch guard `common.sh protected_changes <merge-base-sha>`: a `PROTECTED:` or `PROFILE_CHANGED:` line stops the step with nothing committed (D23).
5. `common.sh hooks_active` must print `HOOKS: active` (`HOOKS: unset` runs `make <make.install_hooks>` first).
6. Per change: stage exactly its files, pre-validate the subject (`make <make.check_commit_message>` or `common.sh is_commit_subject`), write the message with `common.sh commit_msg_file '<subject>'` and commit with `git commit -F <file>` (`RUN_IN_CONTAINER=1 git commit -F <file>` in container mode).
7. One push after the last commit: `git push -u origin HEAD` (`RUN_IN_CONTAINER=1 git push -u origin HEAD` in container mode).
8. A failing hook runs `make <make.format>` once and retries the failed call once; a second failure returns the last 40 log lines and the workflow escalates. The cause is fixed, never the hook: the step never bypasses a hook, never rewrites `core.hooksPath`, never force-pushes, amends, rebases or resets, never pushes to the default branch and never applies or removes a label.

Every subject follows the template's commit regex: `fix(#<N>): resolve <check> failure`, `fix(#<N>): address review comment on <path>`, `fix(#<N>): address review gate iteration <n> findings`, `fix(#<N>): address QA findings <n>`, `docs(#<N>): add planning bundle <N>-<kebab-title>` and `<type>(#<N>): story <N.M> <title>`.

## Testing with the harness

[`tests/lib/workflow-harness.mjs`](../tests/lib/workflow-harness.mjs) runs one workflow script in node, without Claude Code, against the scripted replies of one scenario file:

```bash
node plugins/rust-backend-sdlc/tests/lib/workflow-harness.mjs [--as-child] <workflow.js> [scenario.json]
```

- **Scenario.** `{args, replies: [{match, reply}], workflows: {<name>: result | [results]}}`. `match` is a regular expression (flag `s`) tried on the agent label, then on the prompt; an array reply is consumed in order and repeats its last element. `workflows` keys are the plugin-qualified names `rust-backend-sdlc:rs-sdlc-<name>`; `workflow()` returns that canned result and throws `unknown workflow: <name>` for any other name.
- **Runtime.** `parallel` resolves a throwing branch to `null`, `phase` and `log` are recorded, and `budget` is `{total: null, spent: () => 0, remaining: () => Infinity}`.
- **`--as-child`.** Every `workflow()` call throws `workflow() nesting is one level only`, which is how the runtime treats a nested call from a workflow that is itself nested. A leaf passes unchanged under it; `rs-sdlc-pr-until-green` passes only with `onGate: 'return'` (with the default it escalates with D21 at its first `GATE`).
- **Output.** Pretty JSON `{meta, result | error, calls, phases, logs}`; each call records its label, phase, agent type and prompt, or the nested name and arguments.
- **Exit codes.** 2 on a usage error; 1 on a missing meta literal, a script that throws, a scenario gap (`scenario gap: no reply for agent label="<l>" prompt starts "<80 chars>"`) or a schema gap (a reply that lacks a top-level `required` key of the agent's schema); 0 otherwise. A gap fails the run even when the script catches it.

[`tests/workflows.bats`](../tests/workflows.bats) is the release gate of this layer: 11 static cases (the meta literal and phases, the clock and random ban, agent types, nested names, the call-graph depth, the `onGate: 'return'` hand-back literal, the leaves under `--as-child`, P1–P7 and the generalization denylist, the commit literals, the publish prompt, the verbatim sentences), one case for each of the 103 scenario files under `tests/fixtures/workflows/`, which asserts the outcome its name documents: result word, key counters and the ordered calls, and one schema-gap case (`rp-schema`) that drops a required key from two of them: 115 cases. Every scenario run also checks the shared contract: exit 0, the 7-field block on `ESCALATED` and only there, phases declared in `meta.phases`, agent types that name a file under `agents/`, plugin-qualified nested names, and the `bmalph run: not used (workflow path)` note in every feature report.

| Prefix | Workflow | Scenarios |
| --- | --- | --- |
| `feat-` | `rs-sdlc-feature` | 32 |
| `fnr-` | `rs-sdlc-fr-nfr-review` | 23 |
| `pug-` | `rs-sdlc-pr-until-green` | 30 |
| `rp-` | `rs-sdlc-review-panel` | 18 |

The suite needs only node: a workstation without it skips each case with the reason, and CI, where node is always installed, fails instead. Run it from the repository root:

```bash
npx --yes bats plugins/rust-backend-sdlc/tests/workflows.bats
node plugins/rust-backend-sdlc/tests/lib/workflow-harness.mjs plugins/rust-backend-sdlc/workflows/rs-sdlc-pr-until-green.js plugins/rust-backend-sdlc/tests/fixtures/workflows/pug-full-loop.json
node plugins/rust-backend-sdlc/tests/lib/workflow-harness.mjs --as-child plugins/rust-backend-sdlc/workflows/rs-sdlc-pr-until-green.js plugins/rust-backend-sdlc/tests/fixtures/workflows/pug-as-child.json
```

A new scenario is a JSON file with the workflow's prefix plus one case in `tests/workflows.bats`; the [test strategy](testing/test-strategy.md) lists the floors and the degrade paths each scenario proves.

## Fidelity gaps

The harness proves control flow over mocked replies: given these replies, the script takes these steps, spends these counters and returns this result. It never observes model behaviour or Ralph. In particular:

- **Agents are not run.** A reply is whatever the scenario says; the suite asserts what a prompt asks for (the verbatim sentences, the commit and push forms, the gate run exactly once), never that a real agent complies, reads the right files or reports truthfully.
- **Ralph is not run.** The feature workflow never runs `bmalph run`, and the harness does not run `bmalph implement`, the staging script or the Ralph helpers either: the staging agent's reply stands in for them. Their behaviour is pinned by the script suites (`stage-planning-artifacts.bats`, `common-lib.bats`) and by the command path.
- **Nested workflows are canned.** A parent run receives the scenario's result for a nested name and never executes the child, so the hand-back shape is pinned from both sides by separate scenarios (`pug-return-gate` and `pug-as-child` for the child, `feat-gate-handback` for the parent), not by one end-to-end run.
- **Schemas are checked shallowly.** A reply must hold every top-level `required` key of its schema; types, enums and nested shapes are not validated.
- **No outside world.** No GitHub, CI, Docker, make target or clock is touched: a 540-second wait returns at once, and the sensor verdicts are the scenario's. `pr-state.bats`, `request-ai-reviews.bats` and the other script suites pin those scripts against fixtures.
- **The runtime is modelled.** `parallel`, the budget and the one-level nesting rule (`--as-child`) follow the Workflow tool's contract as documented; a change in the real runtime is not detected by the suite.
