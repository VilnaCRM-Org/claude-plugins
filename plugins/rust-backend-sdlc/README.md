# rust-backend-sdlc

Full-SDLC automation for Rust microservices built from the Rust service template, as a Claude Code plugin: one-command service creation, bounded-context scaffolding, GitHub issue creation, BMAD-method planning, bmalph/Ralph implementation with the Claude CLI, multi-lens code review with the BMAD FR/NFR gate, black-box REST and GraphQL QA, CI auto-fix and AI review comment resolution, looping until the pull request is finished.

The Rust twin of `php-backend-sdlc` and `react-frontend-sdlc`: the same staged loop, gates and guards, retargeted to a template-derived Rust workspace (one crate per bounded-context layer, REST and GraphQL over axum, PostgreSQL through sqlx) and driven only through the template's own make targets. Every repository fact comes from the project profile `.claude/rust-sdlc.yml`, read at run time, so one install serves every service; the repository's own skills under `.claude/skills/`, its `AGENTS.md` and its make targets always win over the plugin's copies.

## Install

```bash
claude plugin marketplace add VilnaCRM-Org/claude-plugins
claude plugin install rust-backend-sdlc@vilnacrm-plugins
```

Keep the install at user scope, the default of `claude plugin install`: the `rust-backend-sdlc:rust-implementer` agent then also resolves in the headless sessions that Ralph starts during the implement stage. Restart Claude Code after the install so the commands load. After `claude plugin update rust-backend-sdlc@vilnacrm-plugins`, restart again and re-run /rs-sdlc-setup in every repository that uses the plugin, as [the setup walkthrough](docs/setup-walkthrough.md) describes.

## Prerequisites

A git checkout of a service derived from the Rust service template (or, to create one with /rs-sdlc-new-service, access to the template), and these tools at or above their version floors. `/rs-sdlc-setup` checks every floor first, prints each check with its remediation and stops when a tool is below its floor:

- bmalph ≥ 2.11.0 (or absent and installable by `make bmalph-setup` with node and npm)
- claude ≥ 2.1.248 (`--restricted`, used by the isolated FR/NFR gate session)
- gh ≥ 2.0, authenticated (`gh auth status`)
- python3 ≥ 3.11 (`tomllib`)
- GNU make ≥ 4.0
- bash ≥ 4.4
- git ≥ 2.30
- node ≥ 20 (bmalph installer, workflow harness)
- jq optional (python3 is the fallback)

YAML is read with mikefarah `yq` v4 when it is on `PATH`, else with python3 and PyYAML; one of the two must be present. Docker is needed in container mode and by the template targets that need a container engine; the Rust toolchain is needed on the host only in host mode.

## Quick start

From nothing to a first feature in three steps: create the service, set it up, build the feature.

### 1. Create a service

In the directory that will hold the new checkout:

```text
/rs-sdlc-new-service billing-service --description "Billing service" --sync-flavour app
```

The command runs the fourteen steps S1–S14: it creates the GitHub repository from the configured template (or copies a local template with `--template-path`), customizes the identity, version, README, changelog and template-sync flavour, removes the planning bundles the template shipped, runs `make doctor`, `make bootstrap` and the setup procedure, commits the result and opens a bootstrap pull request that the PR-finishing loop takes over. Add `--dry-run` to preview every step with nothing created or written. Merge the bootstrap pull request once it is green; [the new-service walkthrough](docs/new-service-walkthrough.md) shows the output of every step and the traps the sequence avoids.

### 2. Set up the repository

A service created in step 1 skips this step: its bootstrap pull request already carries the setup commit. For an existing template-derived service, open the repository root on the default branch and run:

```text
/rs-sdlc-setup
```

Setup checks the floors, prepares the bmalph workspace, writes the project profile `.claude/rust-sdlc.yml`, adds the managed governance block to `CLAUDE.md` and `AGENTS.md`, merges the permission allowlist into the git-ignored `.claude/settings.local.json`, activates the git hooks and runs docs-check; it is safe to repeat. Commit the three tracked files together, in one commit, and bring that commit onto the default branch before feature work starts (in container mode, put `RUN_IN_CONTAINER=1` in front of `git commit`):

```bash
git add .claude/rust-sdlc.yml CLAUDE.md AGENTS.md
git commit -m 'chore(#<N>): add rust-backend-sdlc profile and governance'
```

Run setup again after every template-sync merge and after every plugin update. [The setup walkthrough](docs/setup-walkthrough.md) covers both re-runs, `--refresh`, `--exec`, `--print-settings` and the dirty-tree degrade.

### 3. Build a feature

On a configured repository, start the loop with a task description:

```text
/rs-sdlc "Add a currency code to invoices, exposed over REST and GraphQL, that rejects codes outside ISO 4217"
```

The orchestrator creates the issue, the `<type>/<N>-<slug>` branch and the planning bundle under `specs/`, lets Ralph implement the stories, reviews the change with the FR/NFR gate, runs black-box QA against the running service and loops on the pull request until CI, the gate and every review thread are green. It prints the run report on every exit path. An interrupted run resumes with `/rs-sdlc <N>` at the first stage whose record on the issue no longer holds. A feature that needs a new bounded context starts with `/rs-sdlc-new-context <group> <context>`.

## Commands

| Command | Loop stage | Purpose |
| --- | --- | --- |
| `/rs-sdlc` | all | Drive one feature from a task text to a finished pull request through every stage below, resumable from the issue's state comment |
| `/rs-sdlc-setup` | before the loop | Preflight, bmalph workspace, project profile, governance block, local permission allowlist, hooks and docs-check, safe to repeat |
| `/rs-sdlc-new-service` | before the loop | Create a new Rust microservice from the template (S1–S14) and hand its bootstrap pull request to PR finishing |
| `/rs-sdlc-new-context` | on demand | Scaffold a bounded context with `make new-context`, complete the wiring checklist C1–C12 and prove it with the template's gate stages |
| `/rs-sdlc-issue` | 1 issue | Turn a task description into a GitHub issue with testable acceptance criteria and the `rust-backend-sdlc` label, or adopt an existing issue |
| `/rs-sdlc-plan` | 2 plan | Write and commit the BMAD planning bundle for the issue under `specs/`, ready for bmalph, without interactive prompts |
| `/rs-sdlc-implement` | 3 implement | Stage the bundle for bmalph and run the Ralph loop with the claude-code driver until every story is done |
| `/rs-sdlc-review` | 4 review | Triage all 28 skills, run the code-quality, FR/NFR and security lenses with the quality rows Q1–Q15 and loop the FR/NFR gate to zero new findings |
| `/rs-sdlc-qa` | 5 qa | Black-box QA of the running service over REST, GraphQL and the health probes, against every acceptance criterion, with HTTP evidence and a PASS/FAIL verdict |
| `/rs-sdlc-finish-pr` | 6 finish-pr | Create or update the pull request and loop until CI is green, the FR/NFR gate is green on the head commit and every review thread is resolved |

Every stage has an exit string that must hold before the next stage starts and a bounded iteration guard (`MAX_ITERATIONS=5`), and ends with one of three outcomes: `SUCCESS`, `SUCCESS-WITH-REPORT` (the exit string holds, with one or more `DEGRADED:` notes naming what could not run) or `ESCALATED` (the stage stops with the 7-field escalation block naming the human action). [The SDLC loop](docs/sdlc-loop.md) has the stage table, the counters, the resume rules and the run report.

The commands delegate to seven agents, dispatched as `rust-backend-sdlc:<agent>`: `rust-implementer`, `code-quality-reviewer`, `fr-nfr-reviewer`, `qa-manual-tester`, `ci-fixer`, `pr-comment-resolver` and `security-auditor`. The agents never commit or push; the commands commit through the template's commit-message rule with the hooks active. The 28-skill library under `skills/` is triaged per change by `skills/SKILL-DECISION-GUIDE.md` and `skills/AI-AGENT-GUIDE.md`, and every skill verdict is recorded. Thirteen scripts under `scripts/` and the library `scripts/lib/common.sh` do the deterministic work: preflight, profile generation and validation, governance, settings merge, new-service customization, staging, the FR/NFR gate, review publishing, review requests and the PR state sensor.

## Workflows

Four Workflow scripts under `workflows/` run the parts of the loop that benefit from fan-out and unattended repetition. Start one with the Workflow tool in a repository prepared by /rs-sdlc-setup, naming it by its plugin-qualified name (for example `rust-backend-sdlc:rs-sdlc-feature`) and passing its arguments as a string or an object; [the workflows guide](docs/workflows.md) has the arguments, phases, counters and return values.

| Workflow | Kind | Purpose |
| --- | --- | --- |
| `rs-sdlc-feature` | top level only | The whole loop for one feature: setup check, plan resolution, staging, `rust-implementer` rounds, nested review panel and FR/NFR review, QA, the pull request, then pr-until-green with the `GATE` hand-back; it never runs `bmalph run`, so its report always carries the note `bmalph run: not used (workflow path)` |
| `rs-sdlc-review-panel` | leaf | Stage 4 as a verified fan-out: the code-quality and FR/NFR lenses, plus the security lens when a security-relevant path changed, three refuters per finding, fixes grouped by `crates/<group>/<context>`, at most 5 iterations |
| `rs-sdlc-pr-until-green` | leaf when `onGate` is `'return'` | The workflow form of /rs-sdlc-finish-pr: one sensor verdict per read, counters fix 5, wait 6, request 3 and gate 3, carried across hand-backs and never reset |
| `rs-sdlc-fr-nfr-review` | leaf | The BMAD FR/NFR gate as a bounded loop: `fr-nfr-reviewer` once per iteration, every new finding fixed at its root cause, until zero new findings with verdict PASS, at most 5 iterations |

Both /rs-sdlc-finish-pr and `rs-sdlc-pr-until-green` read the pull request through the sensor `scripts/pr-state.sh`, which classifies every AI reviewer against the current head commit and renders exactly one verdict per read, highest priority first:

| Verdict | When | Next step |
| --- | --- | --- |
| `BLOCKED` | the pull request is merged, closed or conflicting, or a human-gated check fails | escalate, naming the conflict or the approval label a maintainer applies (the plugin never applies a label) |
| `FIX` | a check in the CI scope failed, or review threads are unresolved | `ci-fixer` and `pr-comment-resolver`, then the fixes are committed and pushed |
| `GATE` | the `BMAD FR/NFR Review Gate` status is missing or failed on the head commit | the FR/NFR review on the head (`rs-sdlc-fr-nfr-review`) |
| `REQUEST` | an AI reviewer needs a review or re-review mention | `request-ai-reviews.sh` with the arguments of the sensor's `NEXT:` line |
| `WAIT` | checks, the gate status or a requested review are still in flight | `pr-state.sh --wait-seconds 540` |
| `READY` | CI green or absent, gate green on the head, no unresolved thread, every reachable reviewer approves the head | confirmed by a second read on the same head, then the loop ends |

## Guarantees

- The branch guards run before every commit: a change to a file the template protects, or to the profile on a feature branch, ends the stage `ESCALATED` with the action that resolves it, and nothing is committed.
- Commits never bypass a hook, pushes never force, and the plugin never applies or removes an approval label; a gate that needs a human ends `ESCALATED` with the exact action.
- Every `claude -p` session the plugin starts runs with `acceptEdits`; setup writes its allowlist only to the git-ignored `.claude/settings.local.json` and never sets `bypassPermissions`. The full allow and deny tables are in [the permissions guide](docs/permissions.md).
- A missing capability never fakes a pass: a target that did not run is reported `not run (<reason>)` with a degrade note from [the degrade matrix](docs/degrade-matrix.md).
- Every issue body, pull request body, comment and reply the plugin publishes is redacted first and passed as a body file, never inline.

## Documentation

- [Setup walkthrough](docs/setup-walkthrough.md): install, the nine setup steps with sample output, the single commit, protected settings, `--exec`, re-runs after a template sync or a plugin update, and the version floors
- [New-service walkthrough](docs/new-service-walkthrough.md): the steps S1–S14 with sample output, the dry run and the five traps
- [Project profile schema](docs/profile-schema.md): every key of `.claude/rust-sdlc.yml` with its type, detection source, refresh rule and consumers, the quality-bar derivation and the validation rules
- [The SDLC loop](docs/sdlc-loop.md): stage table and exit strings, counters, state comment and resume rules, the Ralph rules, run report, escalation block, background rule, branch guards and the workflow form
- [Workflows](docs/workflows.md): the four workflows, nested names and the call-graph rule, the hand-back contract, the publish-agent exception and the test harness
- [Permissions](docs/permissions.md): the permission decision, the allow and deny tables, the calls each command makes and the entry that covers each one
- [Degrade matrix](docs/degrade-matrix.md): the rows D1–D25, each with its single outcome
- [Release process](docs/release-process.md): versioning, tags, the marketplace source and the changelog
- [Test strategy](docs/testing/test-strategy.md): the test surfaces, the 16 bats suites and their floors, fixtures and stubs, the skip policy and the degrade-to-test map

## Development

The plugin's checks run from the repository root; [the test strategy](docs/testing/test-strategy.md) lists every command, including the second bats run on the python YAML backend:

```bash
npx --yes bats plugins/rust-backend-sdlc/tests/*.bats
shellcheck -x plugins/rust-backend-sdlc/scripts/*.sh plugins/rust-backend-sdlc/scripts/lib/common.sh
npx --yes markdownlint-cli2 "plugins/rust-backend-sdlc/**/*.md"
python3 tools/plugin-quality/lint/lint_all.py
```

Releases are tagged `rust-backend-sdlc-vX.Y.Z` as [the release process](docs/release-process.md) describes. The plugin is MIT-licensed.
