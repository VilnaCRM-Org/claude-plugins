# Test Plan — Surface: commands-semantics (Round 1)

Target: the 8 command files in `plugins/php-backend-sdlc/commands/`
(`sdlc.md`, `sdlc-setup.md`, `sdlc-issue.md`, `sdlc-plan.md`,
`sdlc-implement.md`, `sdlc-review.md`, `sdlc-qa.md`, `sdlc-finish-pr.md`),
audited by desk-execution: simulate an agent literally following the text
from edge starting states. Contract sources: the command texts themselves,
PRD FR-1..FR-8 / NFR-3..NFR-7 (`specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md`),
the agent files in `agents/`, the scripts in `scripts/`, and
`docs/{profile-schema,degrade-matrix,permissions,sdlc-loop}.md`.

Date: 2026-06-11. Sandbox: `/tmp/sdlc-test-commands-semantics/` (deleted
after the round). No git mutations; the only repo write is this plan file.

## Method

- **Reference integrity** (positive): every script path, flag, skill path,
  agent name, profile key, and report-contract token a command cites must
  exist in the shipped tree with matching semantics (grep/static check,
  plus a sandbox parse smoke for script flags).
- **Failure paths** (negative): for each edge starting state (no/invalid
  profile, closed issue, merged PR, breaker open, degraded capabilities,
  counter exhaustion) the command text must define a reachable, bounded
  outcome — escalation, degrade note, or documented abort.
- **Cross-command/resume** (edge): contradictions between commands, the
  orchestrator's gate/resume tables, and the degrade matrix; resumability
  after each stage from durable artifacts only.

Verdict semantics: FAIL = the text contradicts a contract source or leaves
a literal agent without a defined/bounded next step. PASS-with-note =
ambiguity recorded, defaulting to user expectation, no defect confirmed.

## Positive cases — reference integrity

| ID | Case | Check / command | Expected | Result |
| --- | --- | --- | --- | --- |
| CS-P01 | All scripts referenced by commands exist | `ls scripts/` vs references in all 8 commands (`validate-profile.sh`, `setup-preflight.sh`, `generate-profile.sh`, `inject-governance.sh`, `get-pr-comments.sh`, `ai-review-loop.sh`, `fr-nfr-gate.sh`) | all 7 present | PASS |
| CS-P02 | Every referenced script flag parses | static grep of arg parsers + sandbox smoke: `setup-preflight.sh --report`, `generate-profile.sh --refresh`, `inject-governance.sh --diff`, `get-pr-comments.sh --pr/--unresolved-only/--json`, `ai-review-loop.sh --diff-base/--max-iterations` | no `unknown argument` for any documented flag | PASS |
| CS-P03 | Skill paths referenced exist | `skills/bmad-autonomous-planning/SKILL.md` (sdlc-plan:41), `skills/SKILL-DECISION-GUIDE.md` (sdlc-review:34), `skills/*/SKILL.md` glob count = 21 (sdlc-review:42) | all exist; count 21/21 | PASS |
| CS-P04 | All agents referenced exist | `php-implementer`, `code-quality-reviewer`, `fr-nfr-reviewer`, `qa-manual-tester`, `ci-fixer`, `pr-comment-resolver` vs `agents/*.md` | 6/6 present | PASS |
| CS-P05 | Profile keys consumed are declared in schema | `project.repo`, `make.{start,tests,e2e,psalm,deptrac,phpinsights,infection,fr_nfr_gate}`, `quality.*` (4 phpinsights + deptrac_violations + psalm_errors + infection_msi), `ci.{provider,required_checks}`, `review.coderabbit`, `capabilities.structurizr` vs `docs/profile-schema.md` | every key documented | PASS |
| CS-P06 | Agent report tokens cited by commands match agent files | `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=` + `DEGRADED` (fr-nfr-reviewer.md:94,132), `Verdict: PASS \| FAIL` + SKIPPED rows (code-quality-reviewer.md:95,105), `ALL-GREEN`/`FIXES-READY` (ci-fixer.md:123), `push required: yes` / `AI_REVIEW_VERDICT: PASS` (pr-comment-resolver.md:107,154) | tokens exist verbatim | PASS |
| CS-P07 | Gate commit-status rationale in sdlc-review:112-116 is real | `fr-nfr-gate.sh` resolves `head_sha=$(git rev-parse HEAD)` and posts status context `BMAD FR/NFR Review Gate` | both present (fr-nfr-gate.sh:29,79,89) | PASS |
| CS-P08 | sdlc.md stage table ≡ PRD FR-1 table | `diff` of sdlc.md:27-35 vs prd.md:26-34 (normalized whitespace) | identical rows (only delimiter-row spacing differs) | PASS |
| CS-P09 | sdlc-setup step-7 description of inject-governance output | script emits `managed block written` / `unchanged` in apply mode, diff only behind `--diff` | matches inject-governance.sh:148,153,166 | PASS |
| CS-P10 | `VIOLATION:` lines + exit 1 contract (sdlc-setup step 4, all stage commands' first action) | `validate-profile.sh` prints `VIOLATION: …` and exits 1 on invalid profile (sandbox run) | confirmed (validate-profile.sh:27; sandbox exit 1) | PASS |
| CS-P11 | Allowlist in sdlc-setup step 6 ≡ docs/permissions.md | 4 entries `Bash(make:*)`, `Bash(docker compose exec php:*)`, `Bash(git:*)`, `Bash(gh:*)`; exit condition says "four allowlist entries" | identical sets, count consistent | PASS |
| CS-P12 | "must be a git work tree — preflight enforces this" (sdlc-setup Inputs) | setup-preflight.sh checks `git rev-parse --is-inside-work-tree` | confirmed (setup-preflight.sh:95) | PASS |
| CS-P13 | Canonical escalation block present in all 8 commands | grep `=== SDLC ESCALATION ===` with stage/iteration/exit_condition/status/blocking_finding/iteration_log/recommended_action fields | 8/8 commands carry it | PASS |
| CS-P14 | sdlc-review report template ≡ code-quality-reviewer table | metric rows (4× phpinsights, deptrac violations, psalm errors, infection MSI) byte-comparable | identical metric set | PASS |

## Negative cases — failure paths from edge starting states

| ID | Case | Desk-execution / check | Expected | Result |
| --- | --- | --- | --- | --- |
| CS-N01 | No profile / invalid profile at every stage entry | each of sdlc-issue/plan/implement/review/qa/finish-pr runs `validate-profile.sh` as first action with ABORT → `/sdlc-setup`; sdlc.md stage 0 HALTs; sdlc-setup documents its own exemption | documented abort path in all 8 | PASS |
| CS-N02 | `/sdlc-issue` adopt mode, issue already closed | sdlc-issue.md:60-63 | blocking finding, escalate, never create duplicate | PASS |
| CS-N03 | `/sdlc-plan` with closed or unresolvable issue | sdlc-plan.md:24-29 fetches `state`, escalates before planning | blocking finding documented | PASS |
| CS-N04 | `/sdlc-implement` with missing/FAIL readiness | sdlc-implement.md:22-25 routes back to `/sdlc-plan` | blocking finding documented | PASS |
| CS-N05 | `/sdlc-setup` fix-retry loop with existing invalid profile and no `--refresh` | sandbox: git repo + invalid `.claude/php-sdlc.yml`; run `generate-profile.sh` (no `--refresh`) then `validate-profile.sh`, twice | loop (sdlc-setup.md:51-64,109-116) must be able to converge; observed: generate keeps existing file (`kept existing; use --refresh`), validation fails identically every iteration — loop is provably a no-op for 5 iterations | FAIL → BUG-1 |
| CS-N06 | `/sdlc-finish-pr` blocking findings outside counters: PR already merged/closed, `gh pr create` failure | sdlc-finish-pr.md:31-35 (no PR-state check), 117-131 (escalation fires only "On either counter breaching") | sibling commands escalate on blocking findings (sdlc-issue.md:96-99); finish-pr leaves merged-PR edits, pushes to deleted branches, and PR-create failures with no defined outcome | FAIL → BUG-2 |
| CS-N07 | ci-fixer returns `BLOCKED` (or `SKIPPED-NO-CI`) inside counter A | sdlc-finish-pr.md:47-54 claims the agent "returns `ALL-GREEN` … or `FIXES-READY`"; agent contract has 4 statuses (ci-fixer.md:123-129); counter A iteration = "commit-push-repoll" only | every agent status needs a bounded handling; `BLOCKED` triggers no commit-push (no iteration consumed) and no escalation clause → undefined/unbounded per literal text (NFR-6) | FAIL → BUG-3 |
| CS-N08 | `/sdlc-qa` with `make.start: null` (degrade) under the orchestrator | sdlc-qa.md:38-41 ends SUCCESS-WITH-REPORT; report template verdict enum is `PASS \| FAIL` only (sdlc-qa.md:81); sdlc.md stage-5 gate verifies "QA verdict PASS" (sdlc.md:34,52); degrade-matrix.md requires the run to continue | degrade must satisfy the gate (cf. finish-pr "satisfied-with-report", sdlc-finish-pr.md:40-44); as written the orchestrator cannot verify stage 5 met and burns iterations/escalates a mandated-SUCCESS degrade | FAIL → BUG-4 |
| CS-N09 | `/sdlc-qa` service fails to boot (start target exists) | sdlc-qa.md:41-42, 100-101 | blocking finding → escalate, documented | PASS |
| CS-N10 | `/sdlc-review` with `fr-nfr-reviewer` `verdict=DEGRADED` (specs missing) | sdlc-review.md:93-99 | escalate immediately, no re-invoke, `recommended_action` "re-run /sdlc-plan" — documented and consistent with fr-nfr-reviewer.md:132 | PASS |
| CS-N11 | Counter exhaustion mid-stage, every command | each command defines `MAX_ITERATIONS=5`, restates counter per turn, and escalates on breach (finish-pr: two counters A/B, either breach escalates) | bounded with canonical report in all 8 | PASS |

## Edge cases — cross-command contradictions and resume

| ID | Case | Desk-execution / check | Expected | Result |
| --- | --- | --- | --- | --- |
| CS-E01 | Resume `/sdlc` after stage 1 crash (issue created, no specs yet), task-description argument | sdlc.md:43-46 detects stage 1 via "no `ISSUE_URL` artifact"; ISSUE_URL is stdout of a dead session, no durable artifact or lookup (e.g. label search) is defined; stage 1 create mode (sdlc-issue.md:33-56) has no duplicate check | resumability promise "never restarted from scratch" (sdlc.md:9-11, PRD FR-1) requires a defined issue-detection mechanism; literal desk-execution creates a duplicate issue | FAIL → BUG-5 |
| CS-E02 | Resume rows keyed on QA verdict (absent/FAIL/PASS) — verdict is non-durable (sdlc-qa has no Write tool) | sdlc.md:50-52 | cross-session resume lands at "QA verdict absent → stage 5" and re-runs QA; converges to the correct stage either way — extra work, not a wrong state | PASS (note: QA verdict rows only distinguishable in-session) |
| CS-E03 | Ralph breaker already open on a fresh `/sdlc` invocation | resume table has no breaker row; stage-3 re-entry runs `bmalph implement` + `bmalph run`; breaker state is owned by the external tool and a persisting trip re-escalates via sdlc-implement.md step 6 | bounded outcome exists (re-escalation); "never reset/tamper" not violated by re-invocation after human decision | PASS (ambiguity noted: an explicit breaker-state resume row would be safer) |
| CS-E04 | Zero applicable skills (21× NOT-APPLICABLE) in `/sdlc-review` | step 2 executes nothing; step 3 reviewers still dispatched; report still 21/21 verdicts | flow fully defined | PASS |
| CS-E05 | All reviewers degraded: every quality `make.*` null + gate runner unavailable | code-quality rows all SKIPPED (exit condition "every non-SKIPPED row PASS" is vacuous); fr-nfr-reviewer builds manual matrix (fr-nfr-reviewer.md:133); loop proceeds with degrade notes | defined, NFR-4-conformant | PASS |
| CS-E06 | Stage-4 exit wording: sdlc.md:33 "zero new findings" vs sdlc-review.md:175-177 "AND every non-SKIPPED threshold row PASS" | review never reports done with a quality FAIL (it loops or escalates), so the looser orchestrator gate cannot cause a wrong transition; both texts quote FR-1 | latent wording drift only, no reachable wrong state | PASS (S4 note) |
| CS-E07 | QA-FAIL loop-back budget accounting | sdlc.md:81-85,103-107 ≡ sdlc-qa.md:58-61,93-96 ≡ docs/sdlc-loop.md:50-56: re-entry consumes stage-3 budget, counters never reset, QA counter bounds QA passes only | consistent across all three | PASS |
| CS-E08 | Degraded comment source contract | sdlc-finish-pr.md:58-67 (`ai-review-loop.sh --diff-base <default-branch> --max-iterations 1`, agent-owned, `AI_REVIEW_VERDICT: PASS` = zero unresolved) ≡ pr-comment-resolver.md:149-154,225-228 | consistent | PASS |
| CS-E09 | Division of labor: review command no-Write + commits via Bash; `php-implementer` runs no git | sdlc-review.md frontmatter excludes Write, Bash included; php-implementer.md:144 forbids git — command text matches agent contract (PRD FR-9 "Outputs: commits" drift belongs to agents-contracts surface) | internally consistent | PASS |
| CS-E10 | No git remote / `gh` cannot create issue at stage 1 | sdlc-issue.md:97-99 names "gh cannot create the issue" as blocking finding | escalation documented | PASS |
| CS-E11 | `/sdlc` final run-report fields derivable from stage outputs | per-stage counters, A/B counters, loop-back count, degrade notes, escalation block — all emitted by the stage commands as specified | derivable | PASS |
| CS-E12 | `argument-hint` frontmatter ≡ documented inputs for all 8 commands | `[task-description \| issue-URL]`, `[--refresh]`, `[issue-URL]`, `[specs-dir]`, `[issue-URL \| specs-dir]`, `[pr-number]` | each hint matches the command's Inputs section | PASS |

## Confirmed bugs (round 1)

| Bug | Severity | Case | Summary |
| --- | --- | --- | --- |
| BUG-1 | S2 major | CS-N05 | `/sdlc-setup` generate→validate fix-retry loop can never converge without `--refresh`: step 3 forbids adding `--refresh` unless the user passed it, and `generate-profile.sh` default mode keeps the existing (invalid) profile, so all 5 iterations are provably no-ops |
| BUG-2 | S3 minor | CS-N06 | `/sdlc-finish-pr` has no blocking-finding escalation path (merged/closed PR, `gh pr create` failure) — escalation fires only on counter breach |
| BUG-3 | S2 major | CS-N07 | `/sdlc-finish-pr` step 2 omits ci-fixer's `BLOCKED`/`SKIPPED-NO-CI` statuses; a `BLOCKED` return consumes no counter-A iteration and triggers no escalation → undefined/unbounded loop per literal text (NFR-6) |
| BUG-4 | S2 major | CS-N08 | `/sdlc-qa` `make.start: null` degrade (SUCCESS-WITH-REPORT) is unrepresentable in the mandatory report template (`PASS \| FAIL`) and unsatisfiable at the `/sdlc` stage-5 gate ("QA verdict PASS"), contradicting the degrade matrix / NFR-4 |
| BUG-5 | S3 minor | CS-E01 | `/sdlc` stage-1 resume detection relies on the non-durable `ISSUE_URL` stdout artifact with no defined GitHub lookup; cross-session resume with a task-description argument desk-executes to duplicate issue creation |

## Evidence — CS-N05 sandbox repro

```bash
mkdir -p /tmp/sdlc-test-commands-semantics/repo && cd /tmp/sdlc-test-commands-semantics/repo
git init -q . && mkdir .claude && printf 'project:\n  name: x\n' > .claude/php-sdlc.yml
P=/home/kravtsov/Projects/claude-plugins/plugins/php-backend-sdlc/scripts
"$P/generate-profile.sh"; "$P/validate-profile.sh"; echo "exit=$?"   # iteration 1
"$P/generate-profile.sh"; "$P/validate-profile.sh"; echo "exit=$?"   # iteration 2 — identical
# generate-profile prints "kept existing; use --refresh to overwrite" both times;
# validate-profile prints the same VIOLATION lines and exits 1 both times.
```

Run twice on 2026-06-11; identical output both iterations (deviation
reproduced twice per the strategy's judge step). Sandbox deleted after the
round.

## Round 2

Date: 2026-06-11. Sandbox: `/tmp/sdlc-test2-commands-semantics/` (deleted
after the round). No git mutations; the only repo write is this section.

Scope: verify the round-1 doc fixes that touched this surface
(`/sdlc-qa` + `qa-manual-tester` counter transport, `/sdlc-finish-pr`
step-4 input passing to `pr-comment-resolver`) are coherent end-to-end;
re-cross-check every referenced file/flag after all 11 fixes; re-run the
five round-1 FAIL cases; hunt for contradictions introduced by the
round-1 edits (the regression-risk areas named for the campaign:
inject-governance lockfile/atomic-write, validate-profile ceiling type
checks, setup-preflight work-tree check, `:=` make parsing, counter
transports in the qa/finish-pr dispatch).

### Round 2 — fix-coherence cases (the two fixes that touched this surface)

| ID | Case | Check / desk-execution | Expected | Result |
| --- | --- | --- | --- | --- |
| R2-CS-01 | QA counter transport coherent end-to-end | `sdlc-qa.md:42-47` now dispatches "the current QA iteration number … on a re-dispatch also attach the prior iteration ledger" ≡ `qa-manual-tester.md:65-71` Inputs item 1 ("the current QA iteration number … resumes from that dispatched value; if the dispatch omits it, assume 1/5 and say so") ≡ both report headers `iteration <n>/5` | the cross-dispatch counter has a declared transport on BOTH sides with a graceful omit-fallback | PASS — AG-E08/BUG-1 fixed, symmetric |
| R2-CS-02 | finish-pr step-4 supplies every `pr-comment-resolver` Input | `sdlc-finish-pr.md:71-77` dispatch carries PR number + default-branch name + counter-B iteration `<b>` + step-3 comment source ≡ `pr-comment-resolver.md:79-81` Inputs item 1 (PR number, default branch, counter-B iteration) | the agent's required inputs are all supplied by the command | PASS — AG-E08/BUG-2 fixed on the command side |
| R2-CS-03 | finish-pr default-branch provenance | command passes "the default branch name" but its Inputs section (`sdlc-finish-pr.md:14-27`) never resolves it; agent allowed-actions include `gh repo view --json defaultBranchRef` (`pr-comment-resolver.md:124`) | the agent can self-resolve, so no agent is stranded; latent under-specification only | PASS-with-note (command never states where it reads the default branch) |
| R2-CS-04 | finish-pr "prior iteration ledger"/`<b>` durability on cross-session resume | `sdlc-qa` and `sdlc-finish-pr` have no Write tool; the ledger/`<b>` lives only in the in-session orchestrator context; the agent fallback ("assume 1/5 if omitted") covers the cross-session case | bounded — defensively handled by the omit-fallback, consistent with CS-E02 in-session-only resume model | PASS |
| R2-CS-05 | get-pr-comments `--json` shape still matches the resolver contract after the `raw_is_json` fix | `get-pr-comments.sh:16-17` emits `{pr, review_threads:[{is_resolved, comments:[…]}], issue_comments}` ≡ `pr-comment-resolver.md:53-55`; `raw_is_json` dies cleanly on non-JSON without altering the shape | CS-E08 holds | PASS |

### Round 2 — re-run of the five round-1 FAIL cases

| ID | Case | Re-execution | Round-1 | Round-2 |
| --- | --- | --- | --- | --- |
| R2-CS-N05 | `/sdlc-setup` generate→validate loop convergence (BUG-1) | sandbox: invalid 2-line profile + user fixes a repo signal (adds `Makefile`); run `generate-profile.sh` (no `--refresh`, per step 3) then `validate-profile.sh` | FAIL | FAIL — UNFIXED. `sdlc-setup.md` was not touched in round 1; generate without `--refresh` keeps the existing invalid file (`kept existing; use --refresh`), validate stays at 28 violations / exit 1; the step-4 "regenerate (step 3) and re-validate" loop body is still a no-op on the in-place-fix path |
| R2-CS-N06 | `/sdlc-finish-pr` blocking-finding escalation (BUG-2) | desk-execute merged/closed PR + `gh pr create` failure against `sdlc-finish-pr.md` | FAIL | FAIL — UNFIXED. Round-1 edit touched only step 4 (counter-B inputs); step 1 still has no PR-state check and escalation (lines 124-138) still fires only "On either counter breaching" |
| R2-CS-N07 | `/sdlc-finish-pr` step 2 omits ci-fixer `BLOCKED`/`SKIPPED-NO-CI` (BUG-3) | `sdlc-finish-pr.md:48` vs `ci-fixer.md:123` (4 statuses `ALL-GREEN \| FIXES-READY \| SKIPPED-NO-CI \| BLOCKED`) | FAIL | FAIL — UNFIXED. Step 2 still names only `ALL-GREEN`/`FIXES-READY`; a `BLOCKED` return (ci-fixer.md:169-170) consumes no counter-A iteration and triggers no escalation per literal text |
| R2-CS-N08 | `/sdlc-qa` `make.start: null` degrade unrepresentable in `PASS \| FAIL` template (BUG-4) | `sdlc-qa.md:38` (SUCCESS-WITH-REPORT) vs template enum `sdlc-qa.md:85` vs `sdlc.md:34` gate "QA verdict PASS" | FAIL | FAIL — UNFIXED. Round-1 edit added counter transport to step 3 but left the verdict template `PASS \| FAIL`; the degrade still has no first-class verdict slot (agent papers over it via `Verdict: PASS` qualified, qa-manual-tester.md:140) |
| R2-CS-E01 | `/sdlc` stage-1 resume creates duplicate issue (BUG-5) | `sdlc.md:46` ("no `ISSUE_URL` artifact → stage 1") + `sdlc-issue.md:32-52` create mode | FAIL | FAIL — UNFIXED. `sdlc.md`/`sdlc-issue.md` untouched in round 1; create mode still `gh issue create`s with no pre-create label search, so cross-session resume duplicates the issue |

### Round 2 — reference-integrity re-checks (after all 11 fixes)

| ID | Case | Check | Result |
| --- | --- | --- | --- |
| R2-CS-P01 | 7 scripts referenced by commands exist | `validate-profile`, `setup-preflight`, `generate-profile`, `inject-governance`, `get-pr-comments`, `ai-review-loop`, `fr-nfr-gate` all present | PASS |
| R2-CS-P02 | every documented flag still parses (no `unknown argument`) | sandbox smoke: `setup-preflight --report`, `generate-profile --refresh`, `inject-governance --diff`, `get-pr-comments --pr/--unresolved-only/--json`, `ai-review-loop --diff-base/--max-iterations` | PASS |
| R2-CS-P05 | profile keys consumed are declared after the validate-profile type-check fix | freshly generated valid profile validates exit 0; ceiling/floor `is_int` checks raise no false positive on the happy path | PASS |
| R2-CS-P09 | inject-governance output tokens unchanged by the snapshot/atomic-write fix | apply emits `managed block written`; re-run emits `unchanged`; `--diff` previews without writing; no leftover temp/lock file on clean exit | PASS |
| R2-CS-P10 | validate-profile clean-diagnostic abort path (malformed YAML) | malformed profile → `[php-sdlc][ERROR] profile is not valid YAML … /sdlc-setup`, exit 1, zero traceback lines | PASS |
| R2-CS-P12 | setup-preflight work-tree check matches the Inputs claim | `git rev-parse --is-inside-work-tree == "true"` compared by printed value (setup-preflight.sh:99); bare repo / `.git/` interior FAIL the `git-repo` row | PASS |
| R2-CS-P02b | `:=` make-parse fix holds | `tests := unit` is NOT emitted as a runnable target (`make.tests: null`) | PASS |
| R2-CS-E12 | argument-hints ≡ documented inputs after r1 frontmatter edits | all 8 hints intact; `sdlc-qa` `allowed-tools` frontmatter valid after the step-3 edit | PASS |

### Round 2 — NEW bug

| ID | Case | Desk-execution | Expected | Result |
| --- | --- | --- | --- | --- |
| R2-CS-NEW1 | Counter-transport fix applied asymmetrically: `pr-comment-resolver` agent still claims to OWN counter B | round 1 fixed the qa side on BOTH files (`sdlc-qa.md:42-47` AND `qa-manual-tester.md:159-162`: "owned by the `/sdlc-qa` stage guard … this agent is stateless across dispatches, so it resumes from the dispatched iteration number"); the finish-pr side got the command (`sdlc-finish-pr.md:71-77`: "the agent cannot derive `<b>` itself … resumes rather than resets") but `pr-comment-resolver.md:175` still reads "Own iteration counter, `MAX_ITERATIONS=5`, never reset" with NO stateless/resume clarification and never "resumes from the dispatched value" | both sides of the fix should match the qa pattern so a literal stateless subagent resumes `<b>` from the dispatch instead of restarting at 1 | FAIL → BUG-6 |

### Confirmed bugs (round 2)

| Bug | Severity | Case | Summary |
| --- | --- | --- | --- |
| BUG-6 | S4 minor | R2-CS-NEW1 | The round-1 counter-transport fix is asymmetric: `/sdlc-finish-pr` (command) now declares it owns counter B and "the agent cannot derive `<b>` itself", but `pr-comment-resolver.md:175` still tells the agent it has an "Own iteration counter … never reset" with none of the "stateless / resumes from the dispatched value" clarification that the symmetric `qa-manual-tester` fix received. A stateless subagent following its own file restarts counter B at 1 on every re-dispatch, so its `comment_resolution iteration <b>/5` header and exhaustion escalation under-count — the exact AG-E08/BUG-1 failure that round 1 fixed for qa-manual-tester but left standing for pr-comment-resolver. Stage-level re-dispatch still bounds the loop, hence minor. |

### Round 2 verdict summary

- Both fixes that touched this surface are coherent and hold: the QA
  counter transport is symmetric across command + agent (R2-CS-01), and
  finish-pr step 4 supplies every `pr-comment-resolver` input
  (R2-CS-02). All reference-integrity and regression-area re-checks
  pass (R2-CS-P01/P02/P02b/P05/P09/P10/P12/E12).
- `r1FailsNowPass = false`: none of this surface's five round-1 FAILs
  (CS-N05/N06/N07/N08/E01, BUG-1..5) was in the round-1 fix scope —
  `sdlc.md`, `sdlc-setup.md`, `sdlc-issue.md` were untouched and the
  finish-pr/qa edits addressed only the input/counter transport, not the
  loop-convergence, escalation-coverage, status-coverage, degrade-verdict,
  or duplicate-issue defects. All five re-run to FAIL.
- One NEW bug from the round-1 edits: BUG-6 (R2-CS-NEW1), the asymmetric
  counter-transport fix leaving `pr-comment-resolver` claiming to own a
  counter it is structurally told it receives.

Sandbox `/tmp/sdlc-test2-commands-semantics/` deleted after the round.

## Round 3

Date: 2026-06-13. Sandboxes: `/tmp/sdlc-test3-setup/`,
`/tmp/sdlc-test3-setup2/`, `/tmp/sdlc-test3-flags/`,
`/tmp/sdlc-test3-ghstub/` (all deleted after the round). No git
mutations; the only repo write is this section.

Goal: prove the round-1/2 doc-contract fixes that touch this surface
(finish-pr step-4 input passing, qa counter transport,
pr-comment-resolver counter-B ownership) are now internally consistent
across each command+agent pair; re-run every prior FAIL repro for real
(commit messages NOT trusted); re-check that every referenced
file/flag/skill/agent/token still exists in the current tree; desk-execute
the edge starting states once more.

### Round 3 — provenance check (what actually changed since round 2)

`git log` per file: `sdlc-finish-pr.md` and `sdlc-qa.md` were last touched
at `ad6497e` (round-1 test campaign); `sdlc-setup.md`, `sdlc-issue.md`,
`sdlc.md` at `eec5a16` (pre-campaign). The round-2 commit `180a282`
touched ZERO command files — only `agents/pr-comment-resolver.md` (+11/-6)
on this surface. So BUG-1..5's owning command files have had no fix
attempt in either round; only BUG-6's agent file was edited in round 2.

### Round 3 — fix-coherence re-verification (the three named fixes)

| ID | Case | Check / desk-execution | Expected | Result |
| --- | --- | --- | --- | --- |
| R3-CS-01 | QA counter transport symmetric end-to-end | `sdlc-qa.md:43-47` ("attach the prior iteration ledger, so the agent's counter resumes rather than resets") ≡ `qa-manual-tester.md:65-71,158-165` ("resumes from the dispatched iteration number … assume 1/5 and say so"); both headers `iteration <n>/5` | declared transport on BOTH sides with omit-fallback | PASS — holds |
| R3-CS-02 | finish-pr step-4 supplies every `pr-comment-resolver` Input | `sdlc-finish-pr.md:69-77` dispatch carries PR number + default-branch name + counter-B `<b>` + step-3 comment source ≡ `pr-comment-resolver.md:79-83` Inputs item 1 | every required agent input supplied | PASS — holds |
| R3-CS-03 | pr-comment-resolver counter-B ownership reconciled (BUG-6 fix) | `pr-comment-resolver.md:177-184` now reads "owned by the `/sdlc-finish-pr` stage guard and arrives in the dispatch prompt … this agent is stateless across dispatches, so it resumes from the dispatched `<b>` instead of restarting at 1"; Inputs item 1 (`:80-83`) carries the matching resume/omit-fallback clause; both use `comment_resolution iteration <b>/5` | symmetric with the qa pattern; agent no longer claims to OWN counter B | PASS — BUG-6 FIXED |
| R3-CS-04 | `get-pr-comments --json` shape still matches the resolver contract after the round-2 `raw_is_json`/`pr_data_check` additions | gh-stub sandbox: valid 2-thread payload (1 resolved, 1 unresolved) → `{pr, review_threads:[{is_resolved, comments:[{author,body,path,line,url}]}], issue_comments:[]}` under `--unresolved-only`; jq shape assertion green; reproduced twice | `pr-comment-resolver.md:53-55` shape preserved; new guards die only on bad data | PASS |
| R3-CS-05 | round-2 get-pr-comments guards do not false-"0 unresolved" | gh-stub: `pullRequest:null` → exit 1 "no pull-request data … unresolved count is unknowable"; empty body → exit 1 "empty response" | no silent "0 unresolved" on a dataless fetch | PASS |

### Round 3 — re-run of the five round-1 FAIL cases (real repros)

| ID | Case | Re-execution | R1 | R2 | R3 |
| --- | --- | --- | --- | --- | --- |
| R3-CS-N05 | `/sdlc-setup` generate→validate loop convergence (BUG-1) | sandbox: invalid 2-line profile + user fixes a real signal (adds a valid `Makefile` with a `start` target); run `generate-profile.sh` (no `--refresh`, per step 3) then `validate-profile.sh`, 3 iterations; ran twice (two sandboxes) | FAIL | FAIL | FAIL — UNFIXED. `generate-profile.sh:410` keeps the existing invalid file (`kept existing; use --refresh to overwrite`); profile stays 2 lines, `validate-profile.sh` stays exit 1 with `VIOLATION: required key 'schema_version' missing or null` across all 3 iterations. `sdlc-setup.md:47` forbids `--refresh` unless the user passed it, so the step-4 "regenerate (step 3) and re-validate" loop body is provably a no-op |
| R3-CS-N06 | `/sdlc-finish-pr` blocking-finding escalation (BUG-2) | grep + desk-execute `sdlc-finish-pr.md` for any PR-state check / non-counter escalation | FAIL | FAIL | FAIL — UNFIXED. A case-insensitive grep for merged / closed / pr-state / blocking-finding over `sdlc-finish-pr.md` returns zero hits; escalation (line 126) fires only "On either counter breaching". Sibling commands all carry an explicit "blocking finding → escalate" clause (sdlc-qa line 41, sdlc-plan line 28, sdlc-issue line 62); finish-pr has none, so a merged/closed PR or a `gh pr create` failure has no defined bounded outcome |
| R3-CS-N07 | `/sdlc-finish-pr` step 2 omits ci-fixer `BLOCKED`/`SKIPPED-NO-CI` (BUG-3) | `grep` step-2 statuses vs `ci-fixer.md:123` enum | FAIL | FAIL | FAIL — UNFIXED. Step 2 (`:48`) names only `ALL-GREEN`/`FIXES-READY`; the agent contract is 4 statuses `ALL-GREEN \| FIXES-READY \| SKIPPED-NO-CI \| BLOCKED` (`:123`). A `BLOCKED` return (ci-fixer.md:169-170, e.g. gh unauthenticated) triggers no commit-push → consumes no counter-A iteration → no escalation per literal text (NFR-6 unbounded) |
| R3-CS-N08 | `/sdlc-qa` `make.start: null` degrade unrepresentable in `PASS \| FAIL` template (BUG-4) | `sdlc-qa.md:38` ("finish as SUCCESS-WITH-REPORT") vs its own template enum `:85` (`## Verdict: PASS \| FAIL`) vs `sdlc.md:34,129` gate "QA verdict PASS" | FAIL | FAIL | FAIL — UNFIXED. The command instructs a SUCCESS-WITH-REPORT verdict its own report template cannot express; `qa-manual-tester.md:140-141` papers over it by emitting a *qualified* `Verdict: PASS`. The run does converge (gate sees PASS), but `sdlc-qa.md` remains internally contradictory — a doc-reality mismatch, minor |
| R3-CS-E01 | `/sdlc` stage-1 resume creates duplicate issue (BUG-5) | `sdlc.md:46` ("no `ISSUE_URL` artifact → stage 1") + `sdlc-issue.md:32-51` create mode | FAIL | FAIL | FAIL — UNFIXED. Resume detection keys on the non-durable `ISSUE_URL:` stdout (`sdlc-issue.md:80`) with no GitHub lookup; create mode runs `gh issue create` (`:51`) with no pre-create duplicate/label search ("never open a duplicate" appears only in the ADOPT path, `:66`). Cross-session resume with a task-description argument desk-executes to a duplicate issue |

### Round 3 — reference-integrity re-checks (current tree)

| ID | Case | Check | Result |
| --- | --- | --- | --- |
| R3-CS-P01 | 7 scripts referenced by commands exist | `validate-profile`, `setup-preflight`, `generate-profile`, `inject-governance`, `get-pr-comments`, `ai-review-loop`, `fr-nfr-gate` all present | PASS |
| R3-CS-P02 | every documented flag parses (no `unknown argument`) | sandbox/static: `setup-preflight --report`, `generate-profile --refresh`, `inject-governance --diff`, `get-pr-comments --pr/--unresolved-only/--json`, `ai-review-loop --diff-base/--max-iterations` (parser `:35-36`), `fr-nfr-gate --spec-path` (`:34`) | PASS |
| R3-CS-P04 | all 6 agents referenced exist | `php-implementer`, `code-quality-reviewer`, `fr-nfr-reviewer`, `qa-manual-tester`, `ci-fixer`, `pr-comment-resolver` | PASS |
| R3-CS-P03 | skill paths + 21-skill count | `skills/bmad-autonomous-planning/SKILL.md` (sdlc-plan:41), `skills/SKILL-DECISION-GUIDE.md` (sdlc-review:34), `skills/*/SKILL.md` glob = 21 (sdlc-review:43) | PASS — 21/21 |
| R3-CS-P06 | agent report tokens cited by commands exist verbatim | `FR_NFR_REVIEWER: iteration=<n>/5 … verdict=<PASS\|FAIL\|DEGRADED>` (fr-nfr-reviewer.md:94), `ALL-GREEN`/`FIXES-READY` (ci-fixer.md:123), `push required: yes`/`AI_REVIEW_VERDICT: PASS` (pr-comment-resolver.md:74,156) | PASS |
| R3-CS-DOCS | docs referenced by commands exist | `docs/{profile-schema,degrade-matrix,permissions,sdlc-loop}.md` | PASS |
| R3-CS-E12 | argument-hints ≡ documented Inputs for all 8 | finish-pr `[pr-number]`, implement `[specs-dir]`, issue `[task-description \| issue-URL]`, sdlc `[task-description \| issue-URL]`, plan `[issue-URL]`, qa `[issue-URL \| specs-dir]`, review `[specs-dir]`, setup `[--refresh]` — each matches its Inputs section | PASS |
| R3-CS-ESC | canonical escalation block present in all 8 | `=== SDLC ESCALATION ===` in every command | PASS — 8/8 |

### Round 3 — NEW bug hunt (fix-introduced)

No new defect introduced by the round-2 edits on this surface. The
pr-comment-resolver fix is symmetric (R3-CS-03), the get-pr-comments
shape is preserved with the new guards only firing on bad data
(R3-CS-04/05), and no command file was touched in round 2 so no command
regression was possible. Edge starting states (no/invalid profile,
closed issue, merged PR, breaker open, degraded capabilities, counter
exhaustion) re-desk-execute to the same outcomes recorded in rounds 1-2.

### Round 3 verdict summary

- The single fix that touched this surface in round 2 (BUG-6,
  pr-comment-resolver counter-B ownership) is REAL and HOLDS: the agent
  now declares it receives `<b>` from the dispatch and is stateless
  across dispatches, matching both the `qa-manual-tester` symmetric
  pattern and the `/sdlc-finish-pr` command's "the agent cannot derive
  `<b>` itself" claim. `priorFailsNowPass = 1` (BUG-6).
- BUG-1..5 (CS-N05/N06/N07/N08/E01) all RE-RUN TO FAIL — none of their
  owning command files (`sdlc-setup.md`, `sdlc-finish-pr.md`,
  `sdlc-qa.md`, `sdlc.md`, `sdlc-issue.md`) was edited in either round.
  Each was reproduced twice this round (BUG-1 in two independent
  sandboxes; the rest by repeated grep+desk-execution against the
  current tree).
- Reference integrity is fully intact (scripts, agents, skills, docs,
  tokens, hints, escalation blocks). No fix-introduced bug.

Sandboxes `/tmp/sdlc-test3-*` deleted after the round.
