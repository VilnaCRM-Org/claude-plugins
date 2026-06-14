# Agents

[Home](Home.md) › Reference › Agents

The php-backend-sdlc plugin ships **7 subagents**. None of them are invoked
directly by a human. Each is dispatched by an SDLC command or by a skill via
the Task tool, runs to a tightly defined contract, and returns a single
report (or a working-tree change set) to its dispatcher. The dispatching
command — never the agent — owns git, the iteration budget at stage level,
and any loop-back routing.

Three disciplines bind every agent in this plugin:

- **Container-only execution.** PHP never runs on the host. Build, test, and
  quality commands go through the profile `make` map (`make.tests`,
  `make.psalm`, …) or `docker compose exec php <command>`; raw host `php`,
  `composer`, and `vendor/bin/*` are forbidden.
- **Root-cause culture, suppression-free.** A failing check means the code
  is wrong, not the check. No agent adds suppressions, edits baselines, or
  touches the `quality.*` thresholds — those are raise-only (ADR-7).
- **Degrade, never crash.** A `null` profile key is a missing capability:
  the agent records a one-line capability-absent note and continues
  (NFR-4). Only iteration exhaustion escalates.

## Agent roster

| Agent | Dispatched by | Role |
| --- | --- | --- |
| `php-implementer` | [`/sdlc-implement`](Commands.md) (stage 3, parallel fan-out), [`/sdlc-review`](Commands.md) and [`/sdlc-qa`](Commands.md) loop-backs, and the [security-audit](Security-Audit.md) skill via its orchestrator | Write tested code for exactly one story; fix review/QA/security findings |
| `code-quality-reviewer` | [`/sdlc-review`](Commands.md) (stage 4, quality lens) | Read-only quality verdict against the `quality.*` thresholds |
| `fr-nfr-reviewer` | [`/sdlc-review`](Commands.md) (stage 4, spec lens) | Read-only per-requirement FR/NFR matrix and convergence signal |
| `qa-manual-tester` | [`/sdlc-qa`](Commands.md) (stage 5) | Black-box acceptance-criteria verdict from observed HTTP behavior |
| `ci-fixer` | [`/sdlc-finish-pr`](Commands.md) (stage 6, counter A) | Fix red CI checks at root cause; verify locally |
| `pr-comment-resolver` | [`/sdlc-finish-pr`](Commands.md) (stage 6, counter B) | Drain unresolved review threads to zero — fix or reasoned reply |
| `security-auditor` | [security-audit](Security-Audit.md) skill orchestrator (one per OWASP/vuln family, in parallel) | Grey-box red-team verdict for one assigned vuln family |

Each agent declares its tool surface, model, and `description` in its source
front matter. Every one ends a run either with a single report message or,
for the fixer agents, with edits left in the working tree for the dispatcher
to commit.

## php-implementer

Source:
[`agents/php-implementer.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/php-implementer.md)

**Role.** The unit of work behind implementation. It turns one story's
acceptance criteria into working, tested, integrated code. This is the only
agent in the plugin that writes production source.

**When dispatched.**

- By [`/sdlc-implement`](Commands.md) (stage 3) through bmalph/Ralph — one
  `php-implementer` per independent story, fanned out in parallel.
- By the [`/sdlc-review`](Commands.md) and [`/sdlc-qa`](Commands.md)
  loop-backs to fix a review-gate finding or a QA failure (the loop-back
  carries repro steps).
- By the [security-audit](Security-Audit.md) loop, which routes a verified
  `security-auditor` finding to it for a suppression-free fix plus a
  regression test.

**Tools.** `Read, Write, Edit, Glob, Grep, Bash` — model `sonnet`.

**Input.** Exactly one story (id, description, testable acceptance criteria)
from the loop context, `specs/<slug>/epics-stories.md`, or the first
unchecked line of `.ralph/@fix_plan.md`; the profile at
`.claude/php-sdlc.yml` (read first — the `make` map is the only sanctioned
command surface); optional `specs/` artifacts for genuine ambiguities; and
optional loop-back evidence when dispatched to fix rather than to build.

**Output contract.** Source and test changes wired into the application
(creating a class is half the job; registering it is the other half); the
story checkbox toggled `- [ ]` → `- [x]` on its exact line in
`.ralph/@fix_plan.md` only when the criteria are met and tests pass (or, when
`make.tests: null`, on spec conformance plus the self-review checklist); a
completed self-review pass over every modified diff; and — as the last thing
in **every** run — a parseable status block:

```text
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: 0 | 1
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: <one line: what the dispatcher should do next>
---END_RALPH_STATUS---
```

`TASKS_COMPLETED_THIS_LOOP` is 0 or 1, never more. `EXIT_SIGNAL: true` only
when the story is done and tests pass (or are `NOT_RUN` solely because
`make.tests` is null).

**Hard constraints.** No `git` of any kind (the dispatching loop owns commits
and branches). No host PHP tooling. No edits to `.claude/php-sdlc.yml`,
quality configs, deptrac rules, CI workflows, or Ralph circuit-breaker state.
No suppression annotations, baseline regeneration, test deletion, or
`markTestSkipped` to silence failures. No questions to the user mid-run — it
runs autonomously, makes the safest reversible assumption, and surfaces doubt
via `RECOMMENDATION`. **Max 5 iterations** per dispatch
(`implementer iteration <n>/5`), never reset; on exhaustion it emits the
canonical `=== SDLC ESCALATION ===` block.

## code-quality-reviewer

Source:
[`agents/code-quality-reviewer.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/code-quality-reviewer.md)

**Role.** The read-only quality lens of the stage-4 review gate (FR-6). It
runs the project's quality tooling through the `make` map and measures
observed values against the raise-only `quality.*` thresholds, reporting
findings precise enough that a dispatched `php-implementer` can fix them
without re-discovery.

**When dispatched.** By [`/sdlc-review`](Commands.md) (stage 4), alongside
`fr-nfr-reviewer`. See [Review and Quality Gates](Review-and-Quality-Gates.md)
for how the two lenses combine.

**Tools.** `Read, Glob, Grep, Bash` — model `opus`. It writes nothing and
runs no git.

**Input.** The dispatch prompt from `/sdlc-review` (change summary, changed
files, skill-triage verdicts, and the prior iteration ledger on
re-invocation); the profile; and the source tree for `file:line` context.

**Output contract.** A single report: a 7-row threshold table (phpinsights
quality / architecture / style / complexity, deptrac violations, psalm
errors, infection MSI) each marked PASS / FAIL / SKIPPED; a findings table of
`file:line` + severity (`blocker` | `major` | `minor`) + one-line root-cause
fix; degrade notes; and a `Verdict: PASS | FAIL`. **Verdict rule:** PASS only
when every non-SKIPPED threshold row is PASS. SKIPPED rows (capability
absent) never flip the verdict.

**Hard constraints.** Never propose, draft, or hint at suppressions, baseline
additions, config exclusions, ruleset edits, or any `quality.*` reduction —
if a threshold cannot be met by fixing code, that is a FAIL for the
dispatcher, not a reason to move the bar. Never write or edit a file, run git,
install packages, or re-run a tool with weakened flags to manufacture a PASS.
Bash is limited to the four mapped targets plus read-only output handling.
Semgrep `SEMGREP_APP_TOKEN` hook noise in command output is ignored, never
reported as a finding. **Max 5 iterations** (`quality review iteration
<n>/5`); a threshold FAIL is reported once, not retried.

## fr-nfr-reviewer

Source:
[`agents/fr-nfr-reviewer.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/fr-nfr-reviewer.md)

**Role.** The BMAD spec-compliance lens of the stage-4 review gate. It
answers exactly one question: does the change set satisfy every requirement
in the specs bundle? It owns the requirement matrix; it never touches the
`quality.*` thresholds (that is `code-quality-reviewer`'s job).

**When dispatched.** By [`/sdlc-review`](Commands.md) (stage 4) or the
`/sdlc` orchestrator, alongside `code-quality-reviewer`.

**Tools.** `Read, Glob, Grep, Bash` — model `opus`. Read-only with respect to
the repository; runs no git.

**Input.** All inputs arrive in the Task prompt: the required spec bundle
path `specs/<slug>/`; the required change-set context (changed files + a
one-line summary, passed to the gate as `--impact-context`); the gate-runner
resolution (`make.fr_nfr_gate` if non-null, otherwise the plugin's
`scripts/fr-nfr-gate.sh`); an optional prior iteration ledger; and an
optional stage-3 test outcome to cite directly on "implemented AND tested"
rows.

**Output contract.** A single report ending in a machine-readable line. It
carries a per-requirement matrix (one row per FR, per NFR, and per quality
dimension / NFR catalog category / system quality attribute cataloged in the
`bmad-fr-nfr-review-gate` [skill](Skills.md) — no row skipped), a gate-run
summary, the new findings this iteration, the iteration ledger, and:

```text
FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=<PASS|FAIL|DEGRADED>
```

`new_findings=0` with `verdict=PASS` is the stage exit condition. A PASS row
needs evidence; a FAIL row needs the violated expectation and requirement id;
missing evidence fails closed (FAIL, never PASS).

**Hard constraints.** Never write files, propose threshold cuts or
suppressions, or remediate — findings route to `php-implementer` via the
dispatcher. Bash is limited to running the resolved gate runner and the
`make.tests` / `make.e2e` evidence targets (falling back to test-file
existence reads with a weaker-evidence note when those are null); never
`git`, never `gh`, never the quality targets that belong to
`code-quality-reviewer`. **Max 5 iterations**, never reset; convergence is
`new_findings=0`. If the new-findings count fails to fall across two
consecutive iterations, it says so explicitly so the dispatcher can rethink
remediation before burning budget.

## qa-manual-tester

Source:
[`agents/qa-manual-tester.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/qa-manual-tester.md)

**Role.** The black-box verification lens of stage 5 (FR-7). Verdicts come
exclusively from what the running service actually does over HTTP (or its
sanctioned CLI surface) — never from what the source suggests it should do.

**When dispatched.** By [`/sdlc-qa`](Commands.md) (stage 5). A FAIL routes
back to [`/sdlc-implement`](Commands.md) with the report attached.

**Tools.** `Bash, Read` — model `sonnet`. There is intentionally no
`Edit`/`Write`: it observes and reports, it never fixes.

**Input.** The dispatch prompt (numbered AC list from the issue and
`specs/<slug>/prd.md`, the base URL, the report contract, the QA iteration
number, and any prior ledger); the profile (to resolve `make.start`,
`framework.api_platform`, `framework.graphql`); a running service (booted by
the dispatcher, or by the agent itself via `make.start` when not already up);
and container/service logs as supporting evidence.

**Output contract.** A single report: a checks table (every AC maps to ≥1
executed check, spanning positive, negative, and edge cases) recording the
exact request, expected, observed, and verdict for each; full
copy-pasteable reproduction steps for every FAIL; degrade notes; and a
`Verdict: PASS | FAIL`. An AC is PASS only when every check mapped to it
passed; the run is PASS only when every AC is PASS.

**Hard constraints.** The **black-box rule** is non-negotiable: reading
application source by any means — `Read` *or* shell (`cat`, `grep`, `sed`,
`less`, redirection) — is forbidden. `Read` is permitted only for the
profile, spec artifacts, and log files. If a check cannot be decided without
looking at code, it is INCONCLUSIVE and reported FAIL with that reason. No
file writes, no git, no package installs, no out-of-band datastore mutation
(state changes only through the service's own API), no restart with altered
config to mask a failure. **Max 5 iterations** (`qa iteration <n>/5`,
resumed from the dispatched number). A FAIL is reported once and routed back;
a boot failure or unreachable base URL after a bounded readiness wait
escalates.

## ci-fixer

Source:
[`agents/ci-fixer.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/ci-fixer.md)

**Role.** The CI half of stage 6 (FR-8, counter A). One dispatch is one
poll → diagnose → fix → local-verify pass over the PR's failing checks: read
check states from GitHub, trace each failure to the code that caused it, fix
that code, and prove the fix locally through the `make` map.

**When dispatched.** By [`/sdlc-finish-pr`](Commands.md) (stage 6) whenever a
PR has red checks. The dispatcher owns commit, push, and the re-poll that
confirms a check went green remotely.

**Tools.** `Bash, Read, Edit, Glob, Grep` — model `sonnet`.

**Input.** The dispatch prompt (PR number, which checks were red, how much of
counter A is spent); the profile (read first — `ci.provider` decides the
degrade path before any polling); GitHub state via read-only `gh`
(`gh pr view`, `gh pr checks`, `gh run list`, `gh run view --log-failed`);
and the source tree to localize each failure.

**Output contract.** Root-cause code fixes in the working tree (each locally
verified where a `make` mirror exists, nothing committed); a check-status
table at the **start of every iteration** (check, status, root cause, action
taken, local verify); and a final report ending in one status:

- `ALL-GREEN` — every check (at minimum `ci.required_checks`) already passes.
- `FIXES-READY` — working-tree fixes await the dispatcher's
  commit/push/re-poll.
- `SKIPPED-NO-CI` — the degrade path fired (`ci.provider: null` or the PR has
  no checks).
- `BLOCKED` — no progress was possible.

**Hard constraints.** Every failing check must be mapped to a root cause
before any fix; a check is never "fixed" by an action that does not address
its cause. Never disable, delete, or skip a check — no edits to
`.github/workflows/*` adding `continue-on-error`, `if: false`, `|| true`,
path filters, or matrix exclusions. Never edit thresholds, baselines, or add
suppressions; never weaken or delete tests; never mutate repo settings
(`gh api` writes, branch protection, required-check lists). `gh run rerun
--failed` is allowed **only** for a failure classified as transient
infrastructure, at most once per check per dispatch. No `git` (the dispatcher
owns it). **Max 5 iterations** (`ci-fix iteration <n>/5`); re-running
unchanged code against the same remote state is not an iteration. See
[Degrade and Resilience](Degrade-and-Resilience.md) for the full degrade
matrix.

## pr-comment-resolver

Source:
[`agents/pr-comment-resolver.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/pr-comment-resolver.md)

**Role.** The comment-resolution half of stage 6 (FR-8, counter B). It drains
the PR's unresolved review threads — CodeRabbit, any AI reviewer, or human —
to zero. The unresolved set is re-measured by script output, never from
memory of what was handled.

**When dispatched.** By [`/sdlc-finish-pr`](Commands.md) (stage 6) whenever
the unresolved-comment count is nonzero. See
[Publishing PR Comments](Publishing-PR-Comments.md) for the comment-source
shape and reply mechanics.

**Tools.** `Bash, Read, Edit, Glob, Grep` — model `sonnet`.

**Input.** The dispatch prompt (PR number, default branch, counter-B
iteration); the profile; the unresolved-thread JSON from the comment-listing
command (`make.pr_comments` when non-null, otherwise the plugin's
`scripts/get-pr-comments.sh --pr <n> --unresolved-only --json`), fetched
fresh at the start of every pass and re-fetched at the end; and the source
tree to evaluate each comment against the actual code.

**Output contract.** A single report: the comment source line; a dispositions
table where every thread is exactly one of **fixed** (Edit + `make.tests`
verification + a reply naming the `file:line` change + thread resolved),
**replied** (a reasoned reply citing current-tree evidence + thread
resolved), or **blocked**; a `Remaining unresolved: <n>` count taken from the
post-pass re-fetch; a `Push required: yes | no`; and degrade notes. When no
reviewer app is installed, it degrades to the plugin's
`scripts/ai-review-loop.sh` findings as the comment source, and
`AI_REVIEW_VERDICT: PASS` counts as zero unresolved.

**Hard constraints.** Never resolve a thread without a posted fix-reply or
reasoned reply; never reply with bare acknowledgments ("done", "ack", "will
fix"); never delete, hide, or minimize comments — silent dismissal in any
form is a contract violation. Comments demanding suppressions, baseline
additions, or lowered `quality.*` thresholds get a reply that declines and
names the raise-only rule (ADR-7); the bar is never moved to satisfy a
reviewer. No `git` — fixes land in the working tree and the dispatcher
commits/pushes between iterations. **Max 5 iterations** (counter B,
`comment_resolution iteration <b>/5`, resumed from the dispatched value, never
reset); new threads from a re-review join the next pass and consume budget
like any other.

## security-auditor

Source:
[`agents/security-auditor.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/security-auditor.md)

**Role.** The adversarial red-team unit of the [security-audit](Security-Audit.md)
skill (FR-3). It is grey-box: it MAY read source to taint-trace a candidate
to its sink (unlike `qa-manual-tester`), but a finding is real **only** when
reproduced against the running service.

**When dispatched.** By the [security-audit](Security-Audit.md) skill
orchestrator, which fans out **one instance per OWASP/vuln family in
parallel**. Each instance red-teams exactly one assigned family (e.g.
SQLi/DQL, BOLA/IDOR, auth/session) and never wanders to another. The
[`/sdlc-review`](Commands.md) security lens triages whether this loop runs.

**Tools.** `Bash, Read, Glob, Grep` — model `opus`. No `Edit`/`Write` by
design: verified findings route to `php-implementer` through the
orchestrator, never by this agent.

**Input.** The dispatch prompt (the assigned family id, its
`reference/attack-playbooks.md` entry, the finding-record contract, the
iteration number, and any prior ledger); the profile (to resolve
`make.security`, `capabilities.dynamic_security_testing`, `make.start`,
`make.psalm`, `architecture.*`, `framework.*`, `persistence.*`); a running
service whose base URL the orchestrator supplies; and the source tree for
grey-box taint-tracing.

**Output contract.** A single report of **verified findings only**, each a
finding-record carrying CWE id, edition-labelled OWASP id, a severity band +
rationale, the profile-resolved sink `location` (`file:line`), the exploited
endpoint, copy-pasteable reproduction steps, expected vs observed, a cited
remediation, and the regression-test path the fix must add. It also lists
downgraded/dropped candidates (no reproduction — never findings), degrade
notes, and a `Family verdict: CLEAN | FINDINGS(<count>) | N/A — <reason>`.

**Hard constraints.** The **no-false-positive rule** (NFR-6) is
non-negotiable: SAST/dependency/secret/config output is a *candidate* until
either reproduced against the running service or — for the two static-only
classes (a committed secret/CWE-798, a vulnerable pinned dependency) —
deterministically demonstrated in-tree (FR-7). The **authorized/defensive
boundary** (NFR-5) binds every action: probe only the profile-resolved local
service (verify the base-URL host resolves to loopback / RFC1918 / a
container network before any dynamic probe, and refuse otherwise); no
exfiltration; mutate state only through the service's own API; container-only
execution with no destructive payload beyond what proves the vuln. No `Edit`,
no `git`, no host PHP tooling. When
`capabilities.dynamic_security_testing: false` or `make.start: null`, dynamic
probing is skipped with a note and the static lanes still run. **Max 5
iterations** per family (`security-audit iteration <n>/5`, resumed from the
dispatch, never reset).

## See also

- [Commands](Commands.md)
- [Skills](Skills.md)
- [Security Audit](Security-Audit.md)
- [Review and Quality Gates](Review-and-Quality-Gates.md)
- [The SDLC Loop](The-SDLC-Loop.md)
