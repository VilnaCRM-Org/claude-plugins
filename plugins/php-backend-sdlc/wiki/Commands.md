# Commands

[Home](Home.md) › Reference › Commands

The php-backend-sdlc plugin ships **8 slash commands**. One of them
(`/sdlc`) is the end-to-end orchestrator; the other seven are the
individual stages it drives — each is also runnable on its own.

Every command except `/sdlc-setup` opens with the same stage contract:
its first action runs `scripts/validate-profile.sh`, and on a non-zero
exit it ABORTS and tells you to run `/sdlc-setup`. No command proceeds
against a missing or invalid profile. Each stage is bounded by its own
`MAX_ITERATIONS=5` guard and ends in exactly one of two states: its exit
condition met, or a canonical `=== SDLC ESCALATION ===` block.

For how these stages chain together (gated transitions, resumability,
loop-backs), see [The SDLC Loop](The-SDLC-Loop.md). For the subagents
they dispatch, see [Agents](Agents.md). For the skill catalog the review
stage triages, see [Skills](Skills.md).

## Command table

| Command | Stage | FR | Purpose |
| --- | --- | --- | --- |
| `/sdlc` | orchestrator | FR-1 | Run the full loop end-to-end with gated, resumable transitions |
| `/sdlc-setup` | 0 (setup) | FR-2 | Preflight, generate/validate the project profile, inject governance, allowlist permissions |
| `/sdlc-issue` | 1 | FR-3 | Turn task text into a labeled GitHub issue with testable AC, or adopt an existing issue |
| `/sdlc-plan` | 2 | FR-4 | Run the BMAD planning chain non-interactively into `specs/<slug>/` |
| `/sdlc-implement` | 3 | FR-5 | Drive Ralph (`claude-code` driver) to implement the planned stories |
| `/sdlc-review` | 4 | FR-6 | Skill-triage + multi-lens (FR/NFR + code-quality) review gate until clean |
| `/sdlc-qa` | 5 | FR-7 | Black-box QA against the running service, every AC via HTTP only |
| `/sdlc-finish-pr` | 6 | FR-8 | Create/update the PR, then drive CI-fix and comment-resolution loops |

The stage numbering matches the orchestrator's stage table: stage 0 is
setup-check, stages 1–6 map to `/sdlc-issue` … `/sdlc-finish-pr`.

## /sdlc

- **Stage:** orchestrator (FR-1).
- **Argument:** `[task-description | issue-URL]` — handed to stage 1
  unchanged.
- **Inputs:** the argument, plus the live repository state (profile,
  GitHub issues, `specs/`, Ralph progress, PR state) which it reads to
  detect where to resume.
- **Outputs/artifacts:** the issue URL, the `specs/<slug>/` chain, the
  PR — collected into a final **`=== SDLC RUN REPORT ===`** with
  `result: SUCCESS | ESCALATED`, a per-stage iterations-used table, the
  artifact handles, and every degrade note gathered across stages.

**Key behavior:**

- **Gated transitions** — a stage starts only when the prior stage's
  exit condition is *independently verified* by the orchestrator
  (re-read the issue, re-check `readiness.md`, re-run `gh pr checks`); a
  stage's own success claim is not the gate.
- **Resumable** — on every invocation it detects the current stage from
  durable artifacts and resumes at the first stage (0→6) whose exit
  condition is unmet, never restarting from scratch. Issue-stage resume
  keys on `gh issue list --label php-backend-sdlc`, never on the
  transient `ISSUE_URL:` stdout line, so a cross-session re-run cannot
  open a duplicate.
- **Per-stage guards** — each stage carries its own `MAX_ITERATIONS=5`
  counter, tracked for the whole run; there is no run-level cap.
- **QA loop-back** — a stage-5 FAIL routes back to stage 3 and
  *consumes* stage 3's remaining budget (counters are never reset by
  loop-backs).
- **Ralph circuit breaker** — a breaker trip in stage 3 is terminal:
  emit ESCALATED immediately, never reset or restart around it (NFR-6).
- **Setup is never automated in-loop** — stage 0 only *validates*; an
  invalid profile HALTS with "run `/sdlc-setup`" (setup is a human
  decision point).

The two terminal states are **SUCCESS** (stage 6 exit condition met) and
**ESCALATED** (guard breach, breaker trip, or failed setup-check). Each
stage's own command contract applies inside that stage.

**Drives:** every stage command below, and through them every agent and
skill in the plugin.

**Example:**

```text
/sdlc Add a currency-conversion endpoint to the billing API
```

```text
/sdlc https://github.com/acme/billing/issues/42
```

## /sdlc-setup

- **Stage:** 0 — environment and profile setup (FR-2).
- **Argument:** `[--refresh]`.
- **Inputs:** the current working directory (must be a git work tree —
  preflight enforces this). No profile is required on entry; this command
  *creates* it. `--refresh` regenerates `.claude/php-sdlc.yml` from
  detection even when one already exists.
- **Outputs/artifacts:** `.claude/php-sdlc.yml` (the project profile);
  the managed `<!-- php-backend-sdlc:begin/end -->` governance block in
  `CLAUDE.md` and `AGENTS.md`; the permissions allowlist in
  `.claude/settings.json`; and a diff summary of exactly what changed.

**Key behavior:**

1. **Preflight** — `scripts/setup-preflight.sh --report`; any FAIL row
   ABORTS immediately with the named remediation (preflight failures are
   never retried).
2. **BMAD bootstrap** — if `_bmad/` is absent, run `bmalph init`
   non-interactively; surface failures verbatim and abort (never mask or
   retry a failed bootstrap).
3. **Generate the profile** — `scripts/generate-profile.sh` (plus
   `--refresh` only if the user passed it). Without `--refresh`, an
   existing profile is **kept** and only a detection drift diff is shown
   (NFR-3, no silent overwrite).
4. **Validate** — `scripts/validate-profile.sh`; on violation, enter the
   bounded fix-retry loop, which regenerates **with `--refresh`** (so the
   corrected repo signals actually overwrite the invalid profile —
   otherwise every retry is a no-op).
5. **Inject governance** — `scripts/inject-governance.sh` maintains the
   managed block; user content outside the markers is never touched.
6. **Permissions allowlist (ADR-6)** — merge (never clobber) these four
   entries into `permissions.allow` so plugin-spawned
   `claude -p … --permission-mode acceptEdits` sessions run unprompted:
   `Bash(make:*)`, `Bash(docker compose exec php:*)`, `Bash(git:*)`,
   `Bash(gh:*)`. `bypassPermissions` is a Ralph-driver opt-in only and is
   never written here.

**Exit condition:** `setup-preflight.sh` exits 0 AND
`validate-profile.sh` exits 0 AND the governance block exists in
`CLAUDE.md`/`AGENTS.md` AND `.claude/settings.json` carries the four
allowlist entries. Re-running is safe and a no-op when nothing drifted.

**Drives:** plugin setup scripts (`setup-preflight.sh`,
`generate-profile.sh`, `validate-profile.sh`, `inject-governance.sh`) and
`bmalph init` — no subagents or skills. See
[Project Profile](Project-Profile.md) and
[Permissions](Permissions.md), the
[profile schema](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md),
and the
[setup walkthrough](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/setup-walkthrough.md).

**Example:**

```text
/sdlc-setup
```

```text
/sdlc-setup --refresh
```

## /sdlc-issue

- **Stage:** 1 — task text → GitHub issue (FR-3).
- **Argument:** `[task-description | issue-URL]` — exactly one of a
  free-text task (create mode) or an issue URL / `#<number>`
  (adopt mode).
- **Inputs:** the validated profile (`project.repo` pins the repository
  `gh` resolves). The argument selects the mode.
- **Outputs/artifacts:** a GitHub issue carrying a `## Problem`
  statement, an `## Acceptance criteria` section with **≥3 testable
  bullets**, and `## Scope` notes, labeled `php-backend-sdlc`. The final
  stdout line is the handle `/sdlc-plan` consumes:

  ```text
  ISSUE_URL: <url>
  ```

**Key behavior:**

- **Create mode** starts with a **pre-create dedup search**
  (`gh issue list --state open --label php-backend-sdlc`): if a managed
  issue already covers the task, it switches to adopt mode on that URL
  instead of opening a second one. If `gh issue list` fails it escalates
  rather than create blind (a blind create is how duplicates appear). It
  then drafts the title (imperative, ≤72 chars), problem, ≥3 testable AC,
  and scope; ensures the marker label exists; creates the issue; and
  verifies by reading it back.
- **Adopt mode** validates the issue is OPEN (a closed/missing issue is
  a blocking finding — never silently re-created), ensures ≥3 testable AC
  (deriving and appending them via `gh issue edit` if missing), and
  attaches the marker label (creating it first if absent).
- "Testable" means each bullet names an observable behavior a QA run can
  check — request→response, command→output, state→invariant. Vague
  bullets ("works correctly", "is fast") are rejected.

**Exit condition:** the GitHub issue URL exists with testable AC
(re-verified each iteration via `gh issue view`).

**Drives:** the `gh` CLI only — no subagents or skills.

**Example:**

```text
/sdlc-issue Add idempotency keys to the payment-capture endpoint
```

```text
/sdlc-issue https://github.com/acme/billing/issues/42
```

## /sdlc-plan

- **Stage:** 2 — issue → planning artifacts (FR-4).
- **Argument:** `[issue-URL]` — the URL, or the `ISSUE_URL:` line from
  `/sdlc-issue`.
- **Inputs:** the validated profile; the issue resolved via
  `gh issue view … --json url,number,title,body,state` (a non-OPEN or
  unresolvable issue is a blocking finding). The `<slug>` is the
  number-prefixed kebab-case of the issue title (e.g. `42-currency-crud`).
- **Outputs/artifacts:** the **six-artifact BMAD chain** under
  `specs/<slug>/`, written in order:
  1. `research.md` — domain/technical research
  2. `brief.md` — product brief
  3. `prd.md` — requirements, with the issue's AC traced into FRs
  4. `architecture.md` — technical design
  5. `epics-stories.md` — epics and stories, each marked **independent**
     or **dependent** (the parallel-dispatch input for `/sdlc-implement`)
  6. `readiness.md` — PASS/FAIL implementation-readiness verdict

  On PASS the final stdout line is the handle `/sdlc-implement` consumes:

  ```text
  SPECS_DIR: specs/<slug>
  ```

**Key behavior:**

- **Non-interactive mandate** — zero prompts anywhere in the chain.
  Wherever BMAD would normally elicit input, the command decides
  autonomously and records it inline as
  `> Assumption: <decision and rationale>`. It never uses
  AskUserQuestion and never waits for confirmation.
- **Direct skill load** — it reads and executes
  `skills/bmad-autonomous-planning/SKILL.md` itself rather than going
  through an agent (a §1.2 dependency edge).
- **Cross-reference consistency** — each artifact links its predecessors
  and contradicts no upstream decision.
- **Readiness loop** — a FAIL verdict triggers corrections to the named
  artifacts and a readiness re-run (the bounded loop below).

**Exit condition:** all six artifacts exist under `specs/<slug>/` and
`readiness.md` records PASS.

**Drives:** the
[bmad-autonomous-planning](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/bmad-autonomous-planning/SKILL.md)
skill (direct-loaded). That skill in turn orchestrates focused BMAD
planning subagents per phase.

**Example:**

```text
/sdlc-plan https://github.com/acme/billing/issues/42
```

## /sdlc-implement

- **Stage:** 3 — planning artifacts → implemented stories (FR-5).
- **Argument:** `[specs-dir]` — the directory, or the `SPECS_DIR:` line
  from `/sdlc-plan`.
- **Inputs:** the validated profile (its `make` map is the only
  sanctioned build/test path); the `specs/<slug>/` chain with
  `readiness.md` = PASS (a missing/FAIL readiness verdict routes back to
  `/sdlc-plan`); `.ralphrc` (Ralph's circuit-breaker configuration).
- **Outputs/artifacts:** implemented stories landed as commits, with a
  summary of stories, commits, and test status; Ralph status records
  (`---RALPH_STATUS---` blocks, `.ralph/logs/`).

**Key behavior:**

1. **Transition** — `bmalph implement` converts the `specs/<slug>/` chain
   into Ralph's working format (fix plan, prompt, specs); failures
   surface verbatim and abort.
2. **Start** — `bmalph run --driver claude-code`. The driver is
   **always** `claude-code` — never Codex, never any other, regardless
   of tool defaults or `.ralphrc` contents.
3. **Story dispatch** — stories marked **independent** fan out to
   parallel `php-implementer` subagents (one story per agent); stories
   marked **dependent** run sequentially in declared order, each starting
   only after its prerequisites are done.
4. **Container-only execution** — every `php-implementer` runs build,
   test, and quality commands exclusively through the profile `make` map
   (`make.tests`, `make.psalm`, … or `docker compose exec php`). A
   `make.<key>: null` capability is recorded and skipped with a note
   (NFR-4) — never substituted by a host command.
5. **Circuit breaker (NFR-6)** — `.ralphrc` thresholds: no-progress
   after 3 loops, same-error after 5 loops, output-decline at 70%. On a
   trip: STOP, collect the last status block and log tail, and ESCALATE.
   The breaker is never reset, restarted around, or tampered with — it is
   a human-attention signal. A trip is terminal for the stage even on
   iteration 1 and does not consume remaining stage iterations.

**Exit condition:** Ralph `EXIT_SIGNAL` success, all stories done. The
stage guard (`≤5 bmalph run` attempts) and Ralph's inner breaker are
separate safety nets; either tripping ends the stage.

**Drives:** Ralph via `bmalph`, dispatching the
[php-implementer](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/php-implementer.md)
agent in parallel. `php-implementer` in turn applies the implementation
[Skills](Skills.md) (DDD, API Platform, migrations, CI workflow, etc.).

**Example:**

```text
/sdlc-implement specs/42-currency-crud
```

## /sdlc-review

- **Stage:** 4 — triage-based multi-lens review gate (FR-6).
- **Argument:** `[specs-dir]` — the directory, or the `SPECS_DIR:` line
  from `/sdlc-plan`.
- **`allowed-tools`:** `Bash, Read, Glob, Grep, Task` — note **no
  Write**: this command never edits files itself.
- **Inputs:** the validated profile (`quality.*` thresholds are the
  protected floors); the working branch's diff against the default
  branch; the `specs/<slug>/` chain (FR/NFR traceability); and the
  direct-loaded triage guide
  `skills/SKILL-DECISION-GUIDE.md`.
- **Outputs/artifacts:** an **SDLC Review Report** with a 22/22 skill
  triage table, the `code-quality-reviewer` threshold table, the
  `fr-nfr-reviewer` per-requirement matrix, the gate-iteration ledger,
  and a `PASS | ESCALATED` verdict. After the loop exits it posts (once)
  an aggregate PR conclusion comment when
  `capabilities.publish_pr_comments` is true.

**Key behavior:**

1. **Applicability triage (ADR-5, NFR-5)** — for every shipped skill
   (the v1 catalog of 22), record one verdict — `EXECUTE` with one-line
   evidence or `NOT-APPLICABLE` with a one-line reason (including
   profile-gated skips) — decided from frontmatter + the decision guide
   *only*, never by loading a skill body. Full bodies load only for
   EXECUTE verdicts (the NFR-5 token bound).
2. **Execute applicable skills** against the change set, collecting
   findings.
3. **Multi-lens review (parallel Task dispatch)** —
   `code-quality-reviewer` runs the read-only quality targets
   (`make.psalm`, `make.deptrac`, `make.phpinsights`, `make.infection`)
   and reports observed values against `quality.*` (never proposing
   suppressions or threshold cuts); `fr-nfr-reviewer` is the single
   owner of the FR/NFR gate run (`make.fr_nfr_gate`, null →
   `fr-nfr-gate.sh`) and builds the per-requirement matrix.
4. **Remediation gate loop** — on findings from either lens, dispatch a
   single combined remediation task to a `php-implementer` subagent
   (working-tree only — it runs no git), **commit** that remediation,
   then **re-invoke both** reviewers in parallel with their prior
   iteration ledgers so "new" is computed as a delta and counters resume.
   The dispatch→commit→re-invoke cycle is one iteration.

**Exit condition:** BOTH lenses clean in the last iteration —
`fr-nfr-reviewer` `new_findings=0 verdict=PASS` **AND** every non-SKIPPED
`code-quality-reviewer` threshold row PASS. A quality FAIL row blocks the
verdict exactly like an FR/NFR finding; it never defers to stage-6 CI. A
`fr-nfr-reviewer` `verdict=DEGRADED` (spec bundle missing/empty) is a
blocking finding — escalate immediately with `recommended_action`
"re-run /sdlc-plan", do not re-invoke.

**Drives:** the
[code-quality-reviewer](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/code-quality-reviewer.md)
and
[fr-nfr-reviewer](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/fr-nfr-reviewer.md)
agents (in parallel), the
[php-implementer](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/php-implementer.md)
agent for remediation, and — through the triage — the whole skill
catalog. See
[Review and Quality Gates](Review-and-Quality-Gates.md) and
[Publishing PR Comments](Publishing-PR-Comments.md).

**Example:**

```text
/sdlc-review specs/42-currency-crud
```

## /sdlc-qa

- **Stage:** 5 — black-box verification (FR-7).
- **Argument:** `[issue-URL | specs-dir]`.
- **`allowed-tools`:** `Bash, Read, Glob, Grep, Task` — note **no Edit
  and no Write**: this command and its agent report, they never fix.
- **Inputs:** the validated profile (`make.start` is the only sanctioned
  way to boot the service); the acceptance criteria from the issue
  (`ISSUE_URL:` from stage 1) **and** `specs/<slug>/prd.md`, enumerated
  as AC-1…AC-n before any check runs.
- **Outputs/artifacts:** a **QA Report** with a per-AC checks table
  (request / expected / observed / verdict), reproduction steps for every
  FAIL, and a `PASS | FAIL` verdict.

**Key behavior:**

1. **Enumerate the AC** from the issue and PRD; resolve the service base
   URL.
2. **Boot the service** via `make.start`. If `make.start` is `null`,
   degrade rather than hard-fail: record the note and finish with
   `PASS (SUCCESS-WITH-REPORT — black-box QA skipped, make.start: null)`
   — the leading `PASS` token satisfies the orchestrator's stage-5 gate,
   the parenthetical records that no checks ran (NFR-4). If the target
   exists but the service will not come up, that is a blocking finding.
3. **Dispatch `qa-manual-tester`** with the AC list, base URL, report
   contract, and the current iteration number (and, on a re-dispatch
   after a fix round, the prior ledger so the counter resumes). The agent
   verdicts **exclusively from observed HTTP/API behavior** (`curl` and
   friends) — never from reading source; it is report-only (no Edit, no
   Write). Every AC gets ≥1 executed check, and the run covers positive,
   negative, and edge cases; every check records request / expected /
   observed / verdict, and every FAIL records minimal reproduction steps.
4. **On FAIL** — route back to `/sdlc-implement` with the full report
   attached (inside `/sdlc` this loop-back consumes stage-3 budget).

**Exit condition:** QA verdict PASS (every AC's checks pass). FAIL routes
back to stage 3.

**Drives:** the
[qa-manual-tester](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/qa-manual-tester.md)
agent. No skills (black-box, HTTP-only by contract). See
[Degrade and Resilience](Degrade-and-Resilience.md) for the
`make.start: null` path.

**Example:**

```text
/sdlc-qa https://github.com/acme/billing/issues/42
```

## /sdlc-finish-pr

- **Stage:** 6 — PR finishing loops (FR-8).
- **Argument:** `[pr-number]` — or the current branch's PR; if none
  exists, step 1 creates it.
- **Inputs:** the validated profile (`ci.provider` and
  `ci.required_checks` drive the CI loop and its degrade;
  `review.coderabbit` selects the comment source); `specs/<slug>/` (the
  PR description links it).
- **Outputs/artifacts:** a created/updated PR with a spec-linked
  description (issue URL, links to the `specs/<slug>/` artifacts,
  implemented-stories summary, AC checklist); pushed CI fixes and
  comment-resolution fixes; a final status line listing PR URL, checks
  state, unresolved count, both counters, and degrade notes.

**Key behavior:**

1. **PR create/update** — resolve state with `gh pr view`. No PR → create
   it (a `gh pr create` failure is a blocking finding); open PR → refresh
   the description with `gh pr edit`; **MERGED or CLOSED** PR → a blocking
   finding, escalate without editing or pushing.
2. **CI fix loop — counter A** — degrade-first: `ci.provider` null or no
   checks → skip-with-report (the CI half is satisfied). Otherwise
   dispatch the `ci-fixer` agent, which polls `gh pr checks`, fetches
   failure logs, and fixes the *cause* (never suppressing findings, never
   editing governance-protected thresholds), returning one of
   `ALL-GREEN | FIXES-READY | SKIPPED-NO-CI | BLOCKED`. On `FIXES-READY`
   **the command** commits and pushes the working-tree fixes, then
   re-polls — one iteration of counter A. `BLOCKED` escalates immediately
   (no commit, no push, no loop).
3. **Comment source selection** — `review.coderabbit` true (or any AI
   reviewer app posting comments) → the PR's own threads; otherwise the
   degraded source: `pr-comment-resolver` runs
   `ai-review-loop.sh --diff-base <default-branch> --max-iterations 1`
   each pass.
4. **Comment resolution loop — counter B** — dispatch
   `pr-comment-resolver` with the PR number, default branch, current
   counter-B value, and the selected source. The single source of truth
   for what is unresolved is
   `scripts/get-pr-comments.sh --pr <n> --unresolved-only --json`. For
   each unresolved thread the agent applies a working-tree fix OR posts a
   reasoned reply (never a silent dismissal) and marks it resolved; the
   agent runs no git, so **the command** commits and pushes code fixes
   when it reports `push required: yes` — one iteration of counter B.
   Pushes can re-trigger CI, so after counter B the command re-checks
   `gh pr checks` once and re-enters the CI loop on regression if counter
   A has budget.

**Exit condition:** CI green + 0 unresolved AI review comments — where
"CI green" is satisfied-with-report when no checks exist, and the
agent-run `ai-review-loop.sh` substitutes as the comment source when no
reviewer app exists (NFR-4). Final status is **SUCCESS** or, if any
degrade path was taken, **SUCCESS-WITH-REPORT**. The CI and comment loops
keep **two independent** `MAX_ITERATIONS=5` counters (A and B); spending
one never consumes the other, and exhausting either escalates.

**Drives:** the
[ci-fixer](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/ci-fixer.md)
and
[pr-comment-resolver](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/pr-comment-resolver.md)
agents, plus the plugin's `get-pr-comments.sh` and `ai-review-loop.sh`
scripts. See [Publishing PR Comments](Publishing-PR-Comments.md) and
[Degrade and Resilience](Degrade-and-Resilience.md).

**Example:**

```text
/sdlc-finish-pr
```

```text
/sdlc-finish-pr 137
```

## See also

- [The SDLC Loop](The-SDLC-Loop.md) — how the eight commands chain with
  gated, resumable transitions
- [Agents](Agents.md) — the 7 subagents these commands dispatch
- [Skills](Skills.md) — the 22-skill catalog plus the two meta-guides
- [Review and Quality Gates](Review-and-Quality-Gates.md) — the
  `/sdlc-review` lenses and thresholds in depth
- [Degrade and Resilience](Degrade-and-Resilience.md) — the
  `null`-capability degrade paths every stage honors
