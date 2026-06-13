# Test Plan — Surface: agents-contracts (Round 1)

Target: the 6 agent files in `plugins/php-backend-sdlc/agents/`
(`php-implementer.md`, `code-quality-reviewer.md`, `fr-nfr-reviewer.md`,
`qa-manual-tester.md`, `ci-fixer.md`, `pr-comment-resolver.md`), audited
for contract executability. Contract sources: the agent texts, the
dispatching commands (`sdlc-implement.md`, `sdlc-review.md`, `sdlc-qa.md`,
`sdlc-finish-pr.md`, `sdlc.md`), PRD FR-5..FR-14
(`specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md`),
architecture §3 agent matrix, `docs/profile-schema.md`,
`docs/degrade-matrix.md`, the shipped scripts, and the Ralph response
analyzer (`/home/kravtsov/Projects/user-service/.ralph/lib/response_analyzer.sh`)
for `---RALPH_STATUS---` field conventions.

Date: 2026-06-11. Sandbox: `/tmp/sdlc-test-agents-contracts/` (deleted
after the round). No git mutations; the only repo write is this plan file.

## Method

- **Contract integrity** (positive): every Input each agent declares must
  be supplied by the dispatching command's Task-prompt text; every Allowed
  action and degrade path must be executable with the frontmatter `tools`
  list; every script invocation an agent quotes must parse against the
  shipped script; every output token a dispatcher consumes must exist
  verbatim in the agent contract; profile keys consumed must exist in
  `docs/profile-schema.md`.
- **Degrade paths** (negative): each degrade must be reachable with the
  declared tools, representable in the agent's own report template, and
  consistent with the dispatching command's handling of it; RALPH_STATUS
  degrade variants must still parse.
- **Cross-contract edges** (edge): PRD-vs-shipped drift, counter-sharing
  semantics, analyzer first-marker behavior, data the agent needs that its
  source-of-truth script does not emit.

Verdict semantics: FAIL = an agent contract is not executable as written,
contradicts its dispatcher/scripts/schema, or its status block violates
analyzer conventions. PASS-with-note = ambiguity recorded, defaulting to
user expectation, no defect confirmed.

## Positive cases — contract integrity

| ID | Case | Check / command | Expected | Result |
| --- | --- | --- | --- | --- |
| AG-P01 | Frontmatter validity + architecture §3 matrix | parse YAML frontmatter of all 6; `name` = filename stem; `model`/`tools` byte-match architecture.md:157-162 | 6/6 parse, match | PASS (6/6; models opus only for the two judgment-heavy reviewers, per §3) |
| AG-P02 | Six mandatory sections per PRD FR-9..14 AC | grep Role / Inputs / Outputs / Allowed actions / Degrade paths / Iteration discipline + Smoke prompt headers in all 6 | 6/6 complete | PASS (6/6, plus `## Profile keys consumed` in all 6) |
| AG-P03 | Profile keys consumed exist in schema | extract keys from each agent's `## Profile keys consumed` with the CI grep logic; check each against `docs/profile-schema.md` | every key declared | PASS (ci-fixer 13, code-quality-reviewer 11, fr-nfr-reviewer 3, php-implementer 20, pr-comment-resolver 5, qa-manual-tester 3 — 0 undeclared) |
| AG-P04 | Tool list sufficient for Allowed actions + degrades | desk matrix: each allowed action / degrade step → declared tool | no action requires an undeclared tool | PASS (every allowed action and degrade maps to a declared tool; ci-fixer/pr-comment-resolver Edit-only fix surface matches their Allowed-actions text, which never claims file creation) |
| AG-P05 | Reviewer inputs supplied by `/sdlc-review` | agent Inputs (change summary, changed files, triage verdicts, ledger; spec path, stage-3 outcome) vs sdlc-review.md:58-80 step-3 prompt contract | every required input named in command text | PASS (both reviewer dispatch prompts fully enumerated, incl. prior-ledger counter resume) |
| AG-P06 | qa-manual-tester declared inputs supplied by `/sdlc-qa` | AC list, base URL, report contract vs sdlc-qa.md:42-55 | supplied | PASS for the three declared inputs (counter transport gap tracked as AG-E08) |
| AG-P07 | php-implementer inputs supplied by dispatchers | story source (`epics-stories.md` / `.ralph/@fix_plan.md` / loop-back findings) vs sdlc-implement.md:45-51 and sdlc-review.md:100-107 | story or loop-back evidence reachable per dispatch route | PASS (Ralph supplies the fix-plan story; review remediation supplies loop-back findings; agent counter is explicitly per-dispatch — no transport needed) |
| AG-P08 | Quoted script invocations parse | sandbox stub-PATH smoke: `get-pr-comments.sh --pr 42 --unresolved-only --json`, `ai-review-loop.sh --diff-base main --max-iterations 1`, `fr-nfr-gate.sh --spec-path X --impact-context Y`; bogus flags rejected | no `unknown argument`; flags reach the documented parser branches | PASS (canonical JSON shape `{pr, review_threads:[{is_resolved, comments:[{author,body,path,line,url}]}], issue_comments}` reproduced byte-for-key; unknown flags die with usage) |
| AG-P09 | Output tokens dispatchers consume exist verbatim | `FR_NFR_REVIEWER: iteration=… new_findings=… verdict=`, `Verdict: PASS \| FAIL`, `ALL-GREEN`/`FIXES-READY`/`SKIPPED-NO-CI`/`BLOCKED`, `push required`, `Remaining unresolved`, `AI_REVIEW_VERDICT: PASS`, `FR_NFR_NEW_FINDINGS:` cross-grep agents ↔ commands ↔ scripts | all tokens match | PASS (all present verbatim; sdlc-finish-pr's omission of ci-fixer `BLOCKED`/`SKIPPED-NO-CI` is the already-filed commands-semantics BUG-3 — command-side defect, agent contract complete) |
| AG-P10 | RALPH_STATUS happy block parses | sandbox: `extract_ralph_status_block_json` on the php-implementer template instance (COMPLETE/1/3/PASSING/IMPLEMENTATION/true) | status=COMPLETE, exit_signal=true (found), tasks=1, tests=PASSING | PASS (`{"status":"COMPLETE","exit_signal_found":true,"exit_signal":true,"tasks_completed_this_loop":1,"tests_status":"PASSING"}`) |
| AG-P11 | Threshold table ≡ command template ≡ schema keys | code-quality-reviewer.md:86-95 rows vs sdlc-review.md:141-149 vs `quality.*` schema keys | 7 identical metric rows, keys exist | PASS (diff clean) |
| AG-P12 | Canonical escalation block in all 6 | grep `=== SDLC ESCALATION ===` + stage/iteration/exit_condition/status/blocking_finding/iteration_log/recommended_action; stage names = dispatching command stage names | 6/6 complete, names consistent | PASS (all 7 fields in all 6; `<stage> (<agent>)` matches implement/review/qa/finish-pr) |
| AG-P13 | fr-nfr-reviewer catalog reference resolvable | `skills/bmad-fr-nfr-review-gate/SKILL.md` exists and contains the quality-dimension / NFR-catalog / system-quality-attribute catalogs | exists with catalogs | PASS (SKILL.md:11,73,129,190) |
| AG-P14 | Happy-path smoke prompts runnable | each smoke references only existing scripts/flags/profile keys/make-map semantics; expected outcome tokens appear in the agent's own output contract | 6/6 coherent | PASS (gate/comment/review-loop flags verified live in AG-P08; every expected token exists in the agent's own Outputs) |

## Negative cases — degrade paths

| ID | Case | Check / command | Expected | Result |
| --- | --- | --- | --- | --- |
| AG-N01 | RALPH_STATUS BLOCKED after escalation block | sandbox: escalation text (containing `status: NOT MET`) followed by BLOCKED block, per php-implementer exhaustion rule | status=BLOCKED, exit_signal=false, parse intact | PASS (escalation text outside the markers does not bleed into the parse: `{"status":"BLOCKED","exit_signal":false,…}`) |
| AG-N02 | `make.tests: null` degrade block (NOT_RUN + EXIT_SIGNAL true) | sandbox analyzer parse + ralph_loop `run_test_gate` semantics (ralph_loop.sh:1024-1028: only FAILING fails) | exit accepted; NOT_RUN does not fail the gate (NFR-4) | PASS (`exit_signal:true`, `tests_status:"NOT_RUN"`; gate(NOT_RUN)=pass) |
| AG-N03 | Profile-missing degrade vs validate-first commands | each agent's profile-missing row (BLOCKED / all-FAIL no-profile) vs dispatcher's validate-profile abort | defense in depth, no contradiction | PASS (all 6 degrade to BLOCKED/no-profile with "run /sdlc-setup"; dispatchers abort earlier) |
| AG-N04 | ci-fixer `ci.provider: null` skip | agent degrade row + smoke vs sdlc-finish-pr.md:37-41 command-level skip | both report-and-skip, zero iterations, no double-loop | PASS (identical note text, `SKIPPED-NO-CI`, zero iterations, no escalation) |
| AG-N05 | code-quality-reviewer null-target SKIPPED rows | SKIPPED never flips verdict vs sdlc-review exit "every non-SKIPPED row PASS" | consistent | PASS |
| AG-N06 | fr-nfr-reviewer specs-missing DEGRADED | one report, one iteration, no loop vs sdlc-review.md:93-99 escalate-immediately | consistent and bounded | PASS (agent emits once and stops; command escalates without re-invoking) |
| AG-N07 | pr-comment-resolver degraded comment source | stub-PATH run of `ai-review-loop.sh --diff-base main --max-iterations 1`: PASS verdict → exit 0; FAIL verdict → exit 1 after the single iteration | matches the agent's "verdict PASS counts as zero unresolved" exit rule | PASS (PASS→exit 0 with verdict line; FAIL→exit 1, exactly `iteration 1/1`, "no PASS within 1 iterations") |
| AG-N08 | qa-manual-tester `make.start: null` degrade | zero checks + qualified PASS representable in own template; only Bash/Read needed; vs sdlc-qa step-2 command-level skip | representable, consistent | PASS agent-side (the command-level template/gate representability gap is the already-filed commands-semantics BUG-4) |
| AG-N09 | WORK_TYPE enum vs analyzer | block parser field list (response_analyzer.sh:497-518) vs agent enum `IMPLEMENTATION\|TESTING\|DOCUMENTATION\|REFACTORING`; flat-JSON path special-cases `TEST_ONLY` only | WORK_TYPE ignored by block parser; no wrong inference, no parse break | PASS (block parser extracts only STATUS/EXIT_SIGNAL/TASKS_COMPLETED_THIS_LOOP/TESTS_STATUS; `is_test_only` stays false — "status block is authoritative", analyzer:1086) |

## Edge cases — cross-contract drift and shared state

| ID | Case | Check / command | Expected | Result |
| --- | --- | --- | --- | --- |
| AG-E01 | PRD FR-9/11/13/14 tools/outputs (git, commits, direct gh) vs shipped no-git agents | prd.md:85-119 vs agents + architecture.md:153-162 + sdlc-loop.md | adjudicate: drift resolved by architecture §3 or defect | PASS-with-note (S4 drift note: PRD bullets "Outputs: commits", "Bash(… git)", "gh (commit status)" are superseded by architecture §3's verified per-agent matrix, which the 6 agents byte-match; commands and shipped docs uniformly place git/commits in the dispatcher — planning-chain refinement, not a shipped-artifact defect; adjudicates the drift deferred by commands-semantics CS-E09) |
| AG-E02 | finish-pr dispatch prompts not enumerated (PR number, default branch) | sdlc-finish-pr.md steps 2/4 vs ci-fixer Inputs ("when available") and pr-comment-resolver Inputs (definite) | agents stay executable via self-derivation | PASS-with-note (ci-fixer inputs explicitly optional; pr-comment-resolver may self-derive PR via `gh pr view` and branch via `gh repo view --json defaultBranchRef` — both allowed actions; the counter-B element is NOT self-derivable → AG-E08) |
| AG-E03 | Counter-B sharing: agent "own counter … it is counter B" vs command-owned cycle | pr-comment-resolver.md:173-186 vs sdlc-finish-pr.md:69-93 | bounded either way; resume via passed iteration number | PASS (boundedness preserved: the command escalates at B=5 regardless of what the agent restates) |
| AG-E04 | Thread resolution needs GraphQL node IDs absent from `get-pr-comments.sh` JSON | canonical shape (no thread id, verified in AG-P08 sandbox) vs allowed action "gh api graphql to fetch review-thread node IDs"; correlation key available (`url`) | executable: re-fetch + URL correlation | PASS (node-id fetch is an explicit allowed action; every comment carries `url` for correlation) |
| AG-E05 | Analyzer takes FIRST `---RALPH_STATUS---` marker; agent rule says block is LAST | sandbox: two-block output through the analyzer | conformant output emits one block → no collision; risk noted | PASS-with-note (first block wins: two-block test returned `status:"IN_PROGRESS"`; a conformant run emits exactly one block, but an agent quoting the literal template before the real block would be mis-parsed — S4 latent-risk note: consider "never repeat the markers elsewhere in the response" wording) |
| AG-E06 | qa-manual-tester surface-mismatch degrade (`framework.graphql: false`, AC mentions GraphQL) | degrade row: probe existing surface, else FAIL with repro — executable with Bash/Read only | defined, black-box-conformant | PASS |
| AG-E07 | profile-keys CI job covers `skills/*/SKILL.md` only | ci.yml:189-223 glob vs agents' `## Profile keys consumed` headers | agents un-checked by CI — observation | PASS-with-note (profile-schema.md scopes the check to skills, so no contract breach; agents' key lists are CI-unenforced — AG-P03 compensated manually this round; consider widening the glob) |
| AG-E08 | Cross-dispatch iteration-counter transport | qa-manual-tester.md:83,155-164 ("never reset", "additional iterations … a fresh dispatch after an implement-stage fix round") vs its Inputs (lines 65-67: AC list, base URL, report contract only) and sdlc-qa.md:42-55 dispatch contents; pr-comment-resolver.md:79-81 (requires "the iteration number of counter B") vs sdlc-finish-pr.md:67-70 (never instructs passing it) | a counter that must survive dispatches needs a declared transport in BOTH the agent Inputs and the dispatcher prompt contract (the pattern sdlc-review.md:65,77 / ci-fixer.md:87 follow) | FAIL → BUG-1 (qa-manual-tester: no transport declared on either side) and BUG-2 (sdlc-finish-pr: agent requires the input, command never supplies it) |

## Confirmed bugs (round 1)

| Bug | Severity | Case | Summary |
| --- | --- | --- | --- |
| BUG-1 | S3/S4 minor | AG-E08 | `qa-manual-tester` declares a cross-dispatch iteration counter ("max 5, never reset"; "additional iterations are spent … on a fresh dispatch after an implement-stage fix round") but subagents are stateless across Task dispatches and neither its Inputs nor the `/sdlc-qa` step-3 dispatch contract carries the iteration number or prior QA report — the counter restarts at 1 on every loop-back re-dispatch, so the mandated `iteration <n>/5` report/escalation headers under-count and the agent-level cap is unenforceable (stage-level guard still bounds the loop, hence minor). Every sibling agent with a cross-dispatch counter declares exactly this transport (prior ledger / counter spent / counter-B number). |
| BUG-2 | S3 minor | AG-E08 | `pr-comment-resolver` Input 1 requires the dispatch prompt to carry "the PR number, the default branch name, and the iteration number of counter B it is consuming", but `/sdlc-finish-pr` step 4 never instructs the dispatcher to pass any of them (step 3 only says to name the selected comment source). PR and branch are self-derivable via allowed `gh` calls; the counter-B number is not — same header/escalation under-count as BUG-1 on iterations b≥2 (contrast `/sdlc-review`, which explicitly enumerates the prior-ledger transport for both reviewers). |

Adjudicated, not filed: AG-E01 PRD tools/outputs drift (superseded by
architecture §3, planning-chain refinement — S4 drift note); AG-E05
first-marker latent risk (conformant output unaffected); AG-E07 CI
keys-check scope (matches its documented contract); the command-side
handling gaps for ci-fixer `BLOCKED`/`SKIPPED-NO-CI` and the QA degrade
verdict, already filed as commands-semantics BUG-3/BUG-4.

## Evidence — sandbox runs (2026-06-11, run twice each, identical output)

RALPH_STATUS parse harness (AG-P10/N01/N02/E05) — functions extracted
verbatim from the user-service analyzer:

```bash
mkdir -p /tmp/sdlc-test-agents-contracts && cd /tmp/sdlc-test-agents-contracts
A=/home/kravtsov/Projects/user-service/.ralph/lib/response_analyzer.sh
eval "$(awk '/^trim_shell_whitespace\(\)/,/^}/' "$A")"
eval "$(awk '/^extract_ralph_status_block_json\(\)/,/^}/' "$A")"
extract_ralph_status_block_json "$(printf -- '---RALPH_STATUS---\nSTATUS: COMPLETE\nTASKS_COMPLETED_THIS_LOOP: 1\nTESTS_STATUS: PASSING\nEXIT_SIGNAL: true\n---END_RALPH_STATUS---')"
# → {"status":"COMPLETE","exit_signal_found":true,"exit_signal":true,…}
```

Script-contract smokes (AG-P08/N07) — stub `gh`/`claude` on a prepended
PATH inside a throwaway git repo; observed: canonical JSON shape with
`--unresolved-only` filtering, `unknown argument` rejection for bogus
flags, `ai-review-loop.sh` exit 0 on `AI_REVIEW_VERDICT: PASS` and exit 1
after exactly one iteration on FAIL, `fr-nfr-gate.sh` accepting
`--spec-path`/`--impact-context` and posting the `BMAD FR/NFR Review
Gate` status context with exit 0 on `FR_NFR_NEW_FINDINGS: 0`.

BUG-1/BUG-2 static repro (deterministic; confirmed by two independent
read+grep passes):

```bash
cd /home/kravtsov/Projects/claude-plugins/plugins/php-backend-sdlc
grep -n "never reset\|fresh dispatch\|iteration <n>/5" agents/qa-manual-tester.md
sed -n '63,68p' agents/qa-manual-tester.md      # Inputs: AC list, base URL, report contract — no counter
sed -n '42,44p' commands/sdlc-qa.md             # dispatch contents — no counter, no prior report
sed -n '79,81p' agents/pr-comment-resolver.md   # requires PR number, default branch, counter-B number
grep -n "dispatch prompt" commands/sdlc-finish-pr.md  # step 3 names only the comment source
grep -n "prior iteration ledger" commands/sdlc-review.md  # the pattern the dispatch contract should follow
```

Sandbox `/tmp/sdlc-test-agents-contracts/` deleted after the round.

## Round 2 — fix verification + regression hunt (2026-06-11)

Goal: confirm the round-1 fixes hold (especially the BUG-1/BUG-2
cross-dispatch counter transport) and hunt NEW defects introduced BY the
fixes. No git mutations; the only repo write is this appended section.
Sandbox: `/tmp/sdlc-test2-agents-contracts/` (deleted after the round).
Each harness was run twice with identical output. markdownlint-cli2
v0.22.1 with the repo `.markdownlint.yaml` (MD013 off).

### Re-run of the round-1 FAIL (was AG-E08 → BUG-1 + BUG-2)

| ID | Case | Check | Expected | Result |
| --- | --- | --- | --- | --- |
| AG2-R01 | BUG-1 fix: qa counter transport on BOTH ends | `qa-manual-tester.md` Inputs item 1 + Iteration discipline vs `sdlc-qa.md` step 3 dispatch contract | counter carried by agent Inputs AND supplied by dispatcher prompt | PASS — agent Inputs item 1 now carries "the current QA iteration number from the stage iteration guard … plus … the prior iteration ledger" with an explicit "assume 1/5 if omitted, say so" fallback; Iteration discipline declares statelessness ("owned by the `/sdlc-qa` stage guard … resumes from the dispatched iteration number"); `sdlc-qa.md:42-48` step 3 supplies "the current QA iteration number from this command's iteration guard" + prior ledger on re-dispatch. Transport is symmetric. |
| AG2-R02 | BUG-2 fix: pr-comment-resolver counter-B supplied by dispatcher | `pr-comment-resolver.md` Inputs item 1 vs `sdlc-finish-pr.md` step 4 | dispatcher prompt carries PR number, default branch, counter-B number, comment source | PASS — `sdlc-finish-pr.md:69-78` step 4 now mandates the Task prompt carry "the PR number, the default branch name, the current counter-B iteration number (`comment_resolution iteration <b>/5`) … and the comment source selected in step 3", plus "Increment `<b>` … on every re-dispatch so the agent's counter resumes rather than resets". Agent Input 1's three required elements are now all supplied. |

`r1FailsNowPass`: every round-1 FAIL re-run now passes.

### Regression sweep — defects possibly introduced by the fixes

| ID | Case | Check | Expected | Result |
| --- | --- | --- | --- | --- |
| AG2-R03 | Counter-transport off-by-one / double-count | trace QA + counter-B accounting: command owns counter, increments per re-dispatch, agent resumes from dispatched value and restates `<n>/5` | one dispatch = one tick, no double-increment, escalation fires at 5/5 truthfully | PASS — both models are one-pass-per-dispatch with the command owning the loop; the agent restates the dispatched number rather than maintaining its own across dispatches, so no off-by-one. sdlc-qa "Iteration guard" still scopes the QA counter to QA passes only (implement fix rounds carry their own guard) — no double-count. |
| AG2-R04 | Lint regression on round-1-touched docs | markdownlint-cli2 over `qa-manual-tester.md`, `sdlc-qa.md`, `sdlc-finish-pr.md`, this plan, repo config | 0 errors | PASS — Summary: 0 error(s) across 4 files. |
| AG2-R05 | AG-P03 profile-keys-in-schema after qa edit | re-extract `## Profile keys consumed` from all 6 agents, check each against `docs/profile-schema.md` | 0 undeclared | PASS — ci-fixer 12, code-quality-reviewer 11, fr-nfr-reviewer 3, php-implementer 19, pr-comment-resolver 5, qa-manual-tester 3; 0 missing (fr-nfr `make.fr_nfr_gate`/`make.tests`/`make.e2e` all present). |
| AG2-R06 | AG-P08 script flag parsing after diagnostic-cleanup edits | stub-PATH smoke: `get-pr-comments.sh`, `ai-review-loop.sh`, `fr-nfr-gate.sh` canonical/bogus flags | documented flags reach parser; bogus flags die with a clean `[php-sdlc][ERROR] unknown argument … (usage: …)` and NO raw traceback | PASS — get-pr-comments reproduced the canonical `{pr, review_threads:[{is_resolved, comments:[{author,body,path,line,url}]}], issue_comments}` shape byte-for-key (every comment carries `url`, AG-E04 correlation intact); all three scripts reject bogus flags with the clean diagnostic, no traceback. |
| AG2-R07 | AG-P10/N01/N02 RALPH_STATUS parsing intact | re-run `extract_ralph_status_block_json` on COMPLETE/BLOCKED-after-escalation/NOT_RUN templates | parses; escalation `status: NOT MET` text does not bleed into the BLOCKED block | PASS — COMPLETE→`exit_signal:true`; BLOCKED block after an escalation preamble→`status:"BLOCKED",exit_signal:false`; NOT_RUN+EXIT_SIGNAL true→`status:"COMPLETE",tests_status:"NOT_RUN"`. |
| AG2-R08 | AG-P12 escalation-block consistency after edits | all 6 agents: one `=== SDLC ESCALATION ===` … `=== END ===` block, 7 fields, stage name = dispatcher stage name | 6/6 complete and consistent | PASS — 1 block each, all 7 fields (stage/iteration/exit_condition/status/blocking_finding/iteration_log/recommended_action) present; `<stage> (<agent>)` matches implement/review/qa/finish-pr dispatchers. |
| AG2-R09 | pr-comment-resolver Iteration discipline prose vs command loop model | agent "spend remaining budget" / "NEXT pass" wording (untouched in round 1) vs `sdlc-finish-pr` "one command-owned cycle = one iteration" | adjudicate: malfunction or cosmetic | PASS-with-note — the multi-pass wording is pre-existing (the agent file was NOT modified in round 1) and the "NEXT pass" = the next dispatch, consistent with resuming from the dispatched `<b>`; boundedness and truthful 5/5 escalation are preserved now that the command supplies and increments `<b>`. No malfunction. Cosmetic parity gap: unlike the qa fix, this agent's Iteration discipline does not restate statelessness — consider mirroring the qa wording. |

### Round-2 verdict

All 6 agent contracts remain executable as written; the BUG-1/BUG-2
counter transport is now declared symmetrically (agent Inputs + dispatch
prompt) and is internally consistent (no off-by-one). No new defects
were introduced by the round-1 fixes: lint clean, profile-key schema
coverage intact, script flag parsing and clean diagnostics intact,
RALPH_STATUS parsing intact, escalation blocks consistent. One cosmetic
parity note recorded (AG2-R09), not a bug. Sandbox
`/tmp/sdlc-test2-agents-contracts/` deleted after the round.

## Round 3 — fix-persistence proof + remaining-defect hunt (2026-06-13)

Goal: prove the round-1/round-2 fixes HOLD against the committed tree
(round-2 commit `180a282` is HEAD; the agents/commands/scripts in this
surface carry NO uncommitted changes — verified with `git status
--short`, only other surfaces' plan files are dirty), and hunt any
remaining or fix-introduced defect. Everything below was EXECUTED for
real, each harness run twice with byte-identical output. Sandbox:
`/tmp/sdlc-test3-agents-contracts/` (deleted after the round).
markdownlint-cli2 v0.22.1 with the repo `.markdownlint.yaml`.

### Re-run of every prior FAIL (the round-1 BUG-1/BUG-2 fixes)

| ID | Case | Check | Expected | Result |
| --- | --- | --- | --- | --- |
| AG3-R01 | BUG-1 fix persistence: qa counter transport on BOTH ends | `qa-manual-tester.md:65-71` Inputs item 1 + `:157-165` Iteration discipline vs `sdlc-qa.md:42-48` step 3 | counter carried by agent Inputs AND supplied by dispatcher | PASS — agent Inputs item 1 carries "the current QA iteration number from the stage iteration guard … plus … the prior iteration ledger" with "assume iteration 1/5 if omitted, say so" fallback; Iteration discipline declares statelessness ("owned by the `/sdlc-qa` stage guard … resumes from the dispatched iteration number"); `sdlc-qa.md:43-45` supplies "the current QA iteration number from this command's iteration guard" + ledger on re-dispatch. Symmetric. |
| AG3-R02 | BUG-2 fix persistence: counter-B supplied by dispatcher | `pr-comment-resolver.md:79-83` Inputs item 1 vs `sdlc-finish-pr.md:69-78` step 4 | dispatcher prompt carries PR number, default branch, counter-B number, comment source | PASS — `sdlc-finish-pr.md:71-76` mandates the prompt carry "the PR number, the default branch name, the current counter-B iteration number (`comment_resolution iteration <b>/5`) … and the comment source selected in step 3", plus "Increment `<b>` … on every re-dispatch". Agent Input 1's three required elements are all supplied. |

`priorFailsNowPass`: both round-1 FAILs (the only confirmed FAILs in
rounds 1–2) re-pass against the committed tree.

### Positive contract integrity — re-executed

| ID | Case | Check / command | Expected | Result |
| --- | --- | --- | --- | --- |
| AG3-P01 | Frontmatter ≡ architecture §3 matrix | parse YAML of all 6; `name` = stem; model/tools vs `architecture.md:157-162` | 6/6 byte-match | PASS — name=stem 6/6; php-implementer sonnet `Read, Write, Edit, Glob, Grep, Bash`; the two reviewers opus; qa-manual-tester `Bash, Read`; ci-fixer/pr-comment-resolver `Bash, Read, Edit, Glob, Grep`; all byte-match the matrix. |
| AG3-P03 | Profile keys ∈ schema (CI grep logic, agents NOT covered by CI) | replicate `ci.yml:208-221` awk+grep over all 6 agents' `## Profile keys consumed` vs `docs/profile-schema.md` | 0 undeclared | PASS — ci-fixer 13, code-quality-reviewer 11, fr-nfr-reviewer 3, php-implementer 20, pr-comment-resolver 5, qa-manual-tester 3 (55 total); 0 undeclared. All fully-namespaced, no placeholder artifacts. |
| AG3-P04 | Tool list sufficient for Allowed actions + degrades | desk matrix: Edit-only agents (ci-fixer, pr-comment-resolver) never claim file creation; read-only agents (code-quality, fr-nfr) never write; qa Bash/Read covers all checks/degrades | no action needs an undeclared tool | PASS — grep for create/new-file/scaffold claims in the two Edit-only agents returns none; fr-nfr "never writes files", code-quality forbids write; qa degrades representable with Bash+Read. |
| AG3-P08 | Quoted script invocations parse (stub-PATH live) | `get-pr-comments.sh --pr 42 --unresolved-only --json`, `ai-review-loop.sh --diff-base main --max-iterations 1`, `fr-nfr-gate.sh --spec-path … --impact-context …` in a throwaway git repo with stub `gh`/`claude` | canonical shapes; bogus flags rejected with clean diagnostic | PASS — `get-pr-comments` reproduced `{pr, review_threads:[{is_resolved, comments:[{author,body,path,line,url}]}], issue_comments}` byte-for-key (`--unresolved-only` dropped the resolved thread and emptied issue_comments); all three scripts reject `--bogus-flag` with `[php-sdlc][ERROR] unknown argument … (usage: …)`, no traceback. |
| AG3-P09 | Output tokens dispatchers consume exist verbatim | cross-grep `FR_NFR_REVIEWER:` line, `ALL-GREEN`/`FIXES-READY`/`SKIPPED-NO-CI`/`BLOCKED`, `push required: yes`, `Remaining unresolved`, threshold rows | all match | PASS — `FR_NFR_REVIEWER: iteration=<n>/5 new_findings=<n> verdict=…` emitted by agent (`:94`) and consumed by `sdlc-review.md:83`; `push required: yes`/`Remaining unresolved` match. ci-fixer's `SKIPPED-NO-CI`/`BLOCKED` consumption gap stays a command-side defect (commands-semantics BUG-3), not an agent-contract break — agent emits all four tokens; the command's own `ci.provider`-null pre-check means `SKIPPED-NO-CI` is never returned, and a single-dispatch `BLOCKED` is still bounded by counter-A exhaustion → escalate. |
| AG3-P10 | RALPH_STATUS happy block parses | `extract_ralph_status_block_json` (extracted verbatim from the user-service analyzer) on the php-implementer COMPLETE template | status=COMPLETE, exit_signal=true, tasks=1, tests=PASSING | PASS — `{"status":"COMPLETE","exit_signal_found":true,"exit_signal":true,"tasks_completed_this_loop":1,"tests_status":"PASSING"}`. |
| AG3-P11 | Threshold table ≡ command template | `code-quality-reviewer.md:88-94` vs `sdlc-review.md:143-149` metric rows | 7 identical rows | PASS — phpinsights quality/architecture/style/complexity, deptrac violations, psalm errors, infection MSI — identical on both sides. |
| AG3-P12 | Escalation block consistency | all 6 agents: 1 `=== SDLC ESCALATION ===`…`=== END ===` block, 7 fields, stage name = dispatcher stage | 6/6 complete | PASS — 1/1 START/END each; all 7 fields (stage/iteration/exit_condition/status/blocking_finding/iteration_log/recommended_action); `<stage> (<agent>)` matches implement/review/qa/finish-pr. |

### Negative + edge — degrade paths and shared state, re-executed

| ID | Case | Check / command | Expected | Result |
| --- | --- | --- | --- | --- |
| AG3-N01 | BLOCKED after escalation preamble | analyzer parse: escalation text containing `status: NOT MET` then a BLOCKED block | escalation text outside markers does not bleed in | PASS — `{"status":"BLOCKED","exit_signal_found":true,"exit_signal":false,"tasks_completed_this_loop":0,"tests_status":"FAILING"}`; the `status: NOT MET` in the preamble does not corrupt the parse (parser slices from the FIRST `---RALPH_STATUS---`). |
| AG3-N02 | `make.tests: null` NOT_RUN + EXIT_SIGNAL true | analyzer parse of the degrade template | exit accepted, NOT_RUN | PASS — `{"status":"COMPLETE","exit_signal":true,"tests_status":"NOT_RUN"}`; matches php-implementer degrade row + NFR-4. |
| AG3-N07 | ai-review-loop PASS→exit 0 / FAIL→exit 1 (degrade source) | stub `claude` emitting `{result, is_error}` JSON via the new shared `lib/common.sh:254` `claude_run_once`; verdict last line PASS then FAIL | PASS→0, FAIL→1 after exactly 1 iteration | PASS — PASS verdict → `agent claude: PASS on iteration 1`, exit 0; FAIL verdict → `no PASS within 1 iterations — escalate`, exit 1; matches pr-comment-resolver's "verdict PASS counts as zero unresolved". |
| AG3-N09 | WORK_TYPE enum vs analyzer block parser | block parser (`response_analyzer.sh:493-518`) reads only STATUS/EXIT_SIGNAL/TASKS_COMPLETED_THIS_LOOP/TESTS_STATUS; `is_test_only` set only when flat-JSON `work_type==TEST_ONLY` (`:792-795`) | WORK_TYPE ignored; agent enum never produces TEST_ONLY | PASS — parse of a block carrying `WORK_TYPE: TESTING` returned no `is_test_only` field and an unchanged result; the agent enum (`IMPLEMENTATION\|TESTING\|DOCUMENTATION\|REFACTORING`) never hits the magic `TEST_ONLY`. The block parser at `:722` overrides the flat-JSON path. |
| AG3-E04 | Thread-resolution node IDs absent from `get-pr-comments.sh` | script GraphQL `reviewThreads.nodes` selects `isResolved`+comment fields but NOT thread `.id`; agent allowed action `:127` permits `gh api graphql` re-fetch | executable via re-fetch + `url` correlation | PASS — script JSON carries no thread node id; every comment carries `url`; agent explicitly allowed to re-fetch node IDs and correlate by url. |
| AG3-E05 | Analyzer takes FIRST `---RALPH_STATUS---` marker | two-block output through the parser | first block wins, conformant single-block output safe | PASS — two-block input returned `status:"IN_PROGRESS"` (the first block). Latent-risk note from round 1 unchanged (conformant runs emit one block). |
| AG3-E07 | profile-keys CI job covers `skills/*/SKILL.md` only | `ci.yml:199` glob vs agents | agents un-checked by CI — observation | PASS-with-note — `ci.yml:199` globs `skills/*/SKILL.md`, not `agents/*.md`; AG3-P03 compensated manually (0 undeclared). Consider widening the glob to `agents/*.md`. |
| AG3-E08 | Counter-transport off-by-one after the fixes | trace counter-B: command initializes `1/5`, increments on re-dispatch, agent resumes from dispatched `<b>`; pr-comment-resolver Iteration discipline now restates statelessness | one dispatch = one tick, escalation truthful at 5/5 | PASS — smoke + report + `MAX_ITERATIONS` all anchor at `1/5`; "Increment `<b>` … on every re-dispatch" advances 1→2…; no path increments before the first dispatch. The round-2 AG2-R09 cosmetic parity gap is now CLOSED: `pr-comment-resolver.md:180-181` restates statelessness ("this agent is stateless across dispatches, so it resumes from the dispatched `<b>`"), mirroring the qa wording. |

### Security re-check — fr-nfr-gate `--spec-path` confinement

The gate feeds resolved spec docs into the review prompt, so an
out-of-tree path is a context-injection escape. Re-executed live:

| ID | Case | Check | Expected | Result |
| --- | --- | --- | --- | --- |
| AG3-S01 | Symlinked `--spec-path` | `--spec-path specs/evil-link` (→ `/etc/passwd`) | refused | PASS — `refusing to follow symlink for --spec-path`, exit 1. |
| AG3-S02 | `../` escape | `--spec-path ../../../etc` | refused | PASS — `spec path escapes the repository boundary …`, exit 1. |
| AG3-S03 | Absolute path outside repo | `--spec-path /etc` | refused | PASS — `spec path escapes the repository boundary …`, exit 1. |

### Round-3 verdict

All 6 agent contracts remain executable as written against the
committed tree. The round-1 BUG-1/BUG-2 counter transports HOLD and are
symmetric with no off-by-one; the round-2 AG2-R09 cosmetic parity gap is
now closed (pr-comment-resolver restates statelessness). No regressions
and no fix-introduced defects found: frontmatter ≡ architecture §3
matrix, 55/55 profile keys ∈ schema, tool lists sufficient, all three
agent-quoted scripts parse and emit canonical shapes (the new shared
`lib/common.sh` sourcing works end-to-end), bogus flags die with the
clean diagnostic, RALPH_STATUS parsing intact (COMPLETE/BLOCKED-after-
escalation/NOT_RUN/two-block/WORK_TYPE all correct), escalation blocks
consistent, and the `fr-nfr-gate` symlink/`..`/absolute confinement
holds. The only carried items are pre-existing and out-of-scope for the
agent contracts: the command-side ci-fixer `BLOCKED`/`SKIPPED-NO-CI`
handling gap (commands-semantics BUG-3) and the QA degrade verdict gap
(commands-semantics BUG-4), plus the CI keys-check scope (AG3-E07,
matches its documented contract). No new agents-contracts bug filed.
Sandbox `/tmp/sdlc-test3-agents-contracts/` deleted after the round.
