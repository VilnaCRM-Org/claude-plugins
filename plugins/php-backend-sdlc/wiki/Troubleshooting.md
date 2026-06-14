# Troubleshooting

[Home](Home.md) › Operate › Troubleshooting

Symptom → cause → fix for the most common failures across the SDLC loop.
Every entry is grounded in the command contracts and the
[degrade matrix](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md).
The governing rule is NFR-4: **degrade paths never loop and never
hard-fail** — only preflight, profile validation, guards, and the Ralph
circuit breaker produce a terminal HALTED/ESCALATED state. Everything
else continues and is recorded as a degrade note in the run report.

## Symptom → cause → fix

| Symptom | Cause | Fix |
| --- | --- | --- |
| `/sdlc-setup` aborts at step 1 with a `FAIL:` row before touching the repo | A preflight check failed: git work tree, `claude`/`gh` CLI version floor, `gh` auth, bmalph version/doctor, the YAML toolchain (`yq` or `python3` + PyYAML), or the JSON toolchain (`jq` or `python3`) | Apply the `remediation:` line printed under the failing row verbatim (e.g. `gh auth login`, install/upgrade `claude`/`gh`/`bmalph` to the floor, install `yq`/PyYAML/`jq`), then re-run `/sdlc-setup`. Preflight is **not** retried — it aborts on the first FAIL |
| `/sdlc-setup` aborts at step 4 with `VIOLATION:` lines | `validate-profile.sh` rejected the generated `.claude/php-sdlc.yml` | If the violation is a detection gap, fix the underlying repository signal and re-run `/sdlc-setup --refresh` (the in-loop regenerate uses `--refresh` so the corrected signals overwrite the invalid profile). If it is not fixable by re-detection, edit the profile by hand. The generate→validate loop is bounded at 5 iterations |
| A stage command aborts immediately with "run `/sdlc-setup`" | Missing or invalid profile — every command except `/sdlc-setup` runs `validate-profile.sh` as its first action and aborts on exit 1 | Run `/sdlc-setup` (first time) or `/sdlc-setup --refresh` (after changing repository signals) to create/repair `.claude/php-sdlc.yml` |
| A skill or agent reports "capability absent" and skips a check | A profile `make.<key>` is `null` — the target does not exist in the repo | Expected degrade (SUCCESS-WITH-REPORT), not an error. To enable the check, add the make target to the repo and re-run `/sdlc-setup --refresh` so detection populates `make.<key>` |
| Stage 6 review comments come from `ai-review-loop.sh` instead of PR threads | No reviewer app — `review.coderabbit: false` and no AI reviewer posting on the PR | Expected degrade. `pr-comment-resolver` runs `ai-review-loop.sh --diff-base <default-branch> --max-iterations 1` as the comment source; the substitution is logged as a degrade note. To use a reviewer app, enable CodeRabbit and set `review.coderabbit: true` via `/sdlc-setup --refresh` |
| `/sdlc-finish-pr` CI loop is skipped with "no checks configured" | `ci.provider: null` in the profile, or the PR reports zero checks | Expected degrade (SUCCESS-WITH-REPORT) — the CI half of the exit condition is satisfied-with-report. To run CI, configure a CI workflow so detection sets `ci.provider` and `ci.required_checks`, then `/sdlc-setup --refresh` |
| CI stays red; `/sdlc-finish-pr` counter A exhausts and escalates | `ci-fixer` returned `FIXES-READY` repeatedly without converging, or a required check keeps failing for 5 iterations | Inspect the escalation block's `blocking_finding` and `iteration_log`. Fix the named check cause by hand (the agent never suppresses findings or edits quality thresholds), push, then re-run `/sdlc-finish-pr` |
| `/sdlc-finish-pr` escalates with `ci-fixer BLOCKED — <reason>` | No progress is possible (e.g. `gh` unauthenticated, or no PR exists). This is **not** a counter-A breach and never loops | Apply the agent's `recommended_action` (typically `gh auth login` or create the PR), then re-run. The command does not commit or push on a `BLOCKED` return |
| `/sdlc-finish-pr` escalates at step 1 with `PR <state>/create-failure` | `gh pr create` failed (gh unauthenticated/unavailable, no remote, branch not pushed), or the PR is already `MERGED`/`CLOSED` | For a create failure, apply the verbatim `gh` remediation. For a merged/closed PR, finishing is already complete or the PR must be reopened before re-running — the command never edits or pushes to a finished PR's branch |
| `/sdlc-implement` stops mid-stage with an ESCALATED report (circuit breaker tripped) | Ralph's `.ralphrc` breaker fired: no-progress after 3 loops, same-error after 5 loops, or output-decline at 70% | Terminal for the stage (NFR-6) — even on iteration 1. Inspect `.ralph/logs/` and the last `---RALPH_STATUS---` block named in the report; fix the root cause. **Never** reset, restart around, or tamper with a tripped breaker — it is a human-attention signal and resetting it discards the evidence |
| Any stage halts with a guard breach | A stage iteration counter hit 5 (`MAX_ITERATIONS=5`); `/sdlc-finish-pr` has two independent counters (`A` for CI, `B` for comments) | Read the canonical escalation block's `blocking_finding` and `iteration_log`, resolve the named blocker by hand, then re-run the stage. Counters survive loop-backs in a full `/sdlc` run and are not refreshed |
| A `claude -p` mid-loop call fails with a permission denial | A non-interactive `claude` session hit an operation outside the four-entry allowlist | The error is surfaced verbatim in the escalation report. Confirm `.claude/settings.json` carries `Bash(make:*)`, `Bash(docker compose exec php:*)`, `Bash(git:*)`, `Bash(gh:*)` — re-run `/sdlc-setup` to merge them. See [Permissions](Permissions.md) |
| Wiki pages pushed from `wiki/` do not appear on GitHub | The GitHub wiki is empty — pages will not publish until the wiki has at least one page (its git remote must exist) | One-time seed: create the initial `Home` page through the GitHub web UI (or push a first commit to the wiki git remote), then push the remaining pages. See [Contributing and Releases](Contributing-and-Releases.md) |

## Where to look

When a run stops, the evidence is structured and local. Read it in this
order.

### The stage escalation block

Every terminal stage failure emits the canonical block before stopping.
It names the exact blocker and the human next step:

```text
=== SDLC ESCALATION ===
stage: <stage>           iteration: <n>/5
exit_condition: <the stage's measurable exit condition>
status: NOT MET
blocking_finding: <one line — the first FAIL row, first VIOLATION, breaker reason, or BLOCKED reason>
iteration_log: <one line per attempt>
recommended_action: <the named remediation from the failing script or agent>
=== END ===
```

- `blocking_finding` — start here; it is the single root cause.
- `recommended_action` — the literal next step to take.
- `iteration_log` — how many attempts were spent and what each did.
- For `/sdlc-finish-pr`, the `iteration` line carries **both** counters
  (`A <a>/5, B <b>/5`); `0/5, 0/5` means a pre-loop step-1/step-2 block.

### The final run report (full `/sdlc` runs)

A whole-loop `/sdlc` invocation ends with a run report on **both** exit
paths. It tells you which stage stopped the run and embeds the failing
stage's escalation block:

```text
=== SDLC RUN REPORT ===
task: <task text or issue URL>
result: SUCCESS | ESCALATED
stages: <per-stage table with iterations used and met yes/no>
artifacts: <issue URL> | <SPECS_DIR> | <PR URL>
degrade_notes: <every NFR-4 note collected across stages, or none>
escalation: <the failing stage's escalation block, when ESCALATED>
=== END ===
```

- `result` is `SUCCESS` only when stage 6's exit condition is met; any
  guard breach, breaker trip, or unmet setup-check yields `ESCALATED`.
- `degrade_notes` lists every NFR-4 substitution taken (missing make
  target, no CI, no reviewer app) — these are expected, not failures.
- `stages` shows iterations used per stage, including `(+breaker state)`
  for implement, so you can see which budget was spent.

### Ralph logs (stage 3 / `/sdlc-implement`)

On a circuit-breaker trip the report points at:

- `.ralph/logs/` — the loop's output tail; diagnose the no-progress /
  same-error / output-decline cause here.
- the last `---RALPH_STATUS---` block — Ralph's own status and
  recommendation, captured at the trip.
- `.ralphrc` — the breaker thresholds in effect (do not edit to "fix" a
  trip; that only hides the signal).

### Preflight and profile reports

- `/sdlc-setup` step 1 prints a PASS/FAIL table from
  `setup-preflight.sh --report`; each FAIL carries its own
  `remediation:` line.
- Step 4 prints every `VIOLATION:` line from `validate-profile.sh`. The
  [setup walkthrough](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/setup-walkthrough.md)
  and the
  [profile schema](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md)
  document each key the validator enforces.

For the full behavior of every degrade and safety path, see the
[Degrade and Resilience](Degrade-and-Resilience.md) page.

## See also

- [Degrade and Resilience](Degrade-and-Resilience.md)
- [Getting Started](Getting-Started.md)
- [Project Profile](Project-Profile.md)
- [Permissions](Permissions.md)
- [The SDLC Loop](The-SDLC-Loop.md)
