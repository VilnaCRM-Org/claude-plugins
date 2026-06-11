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
