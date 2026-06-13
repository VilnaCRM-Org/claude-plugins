# Test Plan — gh-integration

Surface: `scripts/get-pr-comments.sh` and `scripts/fr-nfr-gate.sh` driven
through stubbed `gh` (and stubbed `claude` for the gate), with crafted
GraphQL/REST fixture payloads.

Contracts: FR-8 (comment-resolution feed, "0 unresolved" exit condition),
FR-18 (shipped scripts), script header comments (canonical JSON shape,
pagination refusal, always-post commit status with `BMAD FR/NFR Review
Gate` context, comment only when findings > 0), `docs/testing/test-strategy.md`
severity ladder.

## Method

- Sandboxes: `/tmp/sdlc-test-gh-integration/<case-id>/`, deleted after the
  run. Each sandbox is a fresh `git init` repo with an `origin` remote
  (the scripts derive the slug from it).
- Static stub `gh`/`claude` from `tests/fixtures/bin` where one canned
  response suffices; per-case routing `gh` wrappers (the pattern already
  used by the bats suites) where different subcommands must succeed/fail
  independently (mid-sequence API failures, auth expiry mid-run).
- Crafted payloads are generated into the sandbox with `python3` (the
  100-thread boundary payloads) or written inline.
- Both transformation backends (jq present / jq stripped from `PATH`)
  are exercised on the cases where the backend choice can diverge.
- Every FAIL is reproduced twice before being recorded (strategy: confirm
  twice, drop environment flukes).

## get-pr-comments.sh — positive cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| GPC-P1 | Empty PR: `reviewThreads.nodes` and `comments.nodes` both `[]` | exit 0; both section headers; `unresolved threads: 0` | PASS |
| GPC-P2 | Empty PR, `--json` | exit 0; valid canonical JSON; `pr` int; both arrays empty | PASS |
| GPC-P3 | PR with only issue comments (no review threads) | exit 0; issue comments listed; `unresolved threads: 0` | PASS |
| GPC-P4 | Only issue comments + `--unresolved-only` | exit 0; issue comments excluded; `unresolved threads: 0` (FR-8 exit condition reachable) | PASS |
| GPC-P5 | Exactly 100 review threads (37 unresolved), every `hasNextPage:false` | exit 0; no pagination refusal; `unresolved threads: 37`; `--json` carries 100 threads | PASS |
| GPC-P6 | Exactly 100 issue comments and one thread with exactly 100 comments, `hasNextPage:false` | exit 0; all rendered; no refusal | PASS |
| GPC-P7 | Unicode/emoji/CJK/RTL/combining bodies | exit 0; bodies byte-faithful in human and `--json`; jq and python backends agree on parsed values | PASS |
| GPC-P8 | Markdown/shell/jq-injection bodies: `` `rm -rf` ``, `$(touch canary)`, `` $(env) ``, `\(env)`, `{{template}}`, fake headings | exit 0; bodies verbatim; canary file NOT created (no execution) | PASS |

## get-pr-comments.sh — negative cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| GPC-N1 | Mid-sequence failure: `gh pr view` returns 7, then `gh api graphql` exits 1 (HTTP 502) | exit 1; `gh api graphql failed for PR #7 in acme/sample-api`; gh stderr visible | PASS |
| GPC-N2 | Auth expired before PR resolution: no `--pr`, `gh pr view` exits 1 | exit 1; die `no PR found for the current branch (pass --pr <n>)` | PASS |
| GPC-N3 | `gh` exit 0 with non-JSON garbage stdout | non-zero exit; a clear error naming gh/the payload (no success-shaped output) | FAIL — raw jq/python parse error, exit 2/1, no script-level diagnosis (S3, BUG-1) |
| GPC-N4 | `gh` exit 0 with empty stdout | non-zero exit; clear error | FAIL — jq path: exit 0, zero bytes of output, no summary line (silent success); python path: traceback (S2, BUG-2) |
| GPC-N5 | `gh` exit 0 with valid JSON of the wrong shape (`{"ok":true}`) | non-zero exit; clear error | FAIL — exit 0, renders `unresolved threads: 0` for a payload with no PR data (S2, BUG-2) |
| GPC-N6 | `gh` exit 0 with `data.repository.pullRequest: null` (PR not found shape) | non-zero exit; clear error | FAIL — exit 0, `unresolved threads: 0` (same defect as GPC-N5, BUG-2) |
| GPC-N7 | `gh` absent from `PATH` | exit 1; `gh CLI not found on PATH` | PASS |

## get-pr-comments.sh — edge cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| GPC-E1 | Thread with `comments.nodes: []` | exit 0; `?:0` placeholder header; thread still counted in unresolved total | PASS |
| GPC-E2 | Missing fields: `author:null` (deleted user), `body:null`, `path:null`, `line:null` | exit 0; author falls back to `unknown`; no crash; `--json` preserves nulls; both backends agree | PASS |
| GPC-E3 | All `pageInfo` objects missing from the payload | exit 0; treated as no-next-page (no false pagination refusal) | PASS |
| GPC-E4 | `--pr 007` (leading zeros pass the `^[0-9]+$` validation) | exit 0 treating it as PR 7, or a clean usage error | PASS — both backends render `PR #7` (jq 1.8.1 `--argjson` tolerates leading zeros; older jq would reject, not reproducible on this host) |
| GPC-E5 | `hasNextPage:true` only on the issue-comments connection (threads fine) | exit 1; pagination refusal (guard covers all three connections) | PASS |
| GPC-E6 | ANSI escape sequences (`[31m`, OSC 8) in bodies | recorded informationally: raw passthrough, same as `gh` itself; output is agent-feed, not a terminal contract | PASS (informational) |

## fr-nfr-gate.sh — positive cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| FNG-P1 | Zero findings, every gh call succeeds | exit 0; success status with exact context `BMAD FR/NFR Review Gate`; no PR comment | PASS |
| FNG-P2 | SSH origin remote `git@github.com:acme/sample-api.git` | status POSTed to `repos/acme/sample-api/statuses/<HEAD sha>` | PASS |
| FNG-P3 | 2 findings, every gh call succeeds | exit 1; failure status `2 new FR/NFR finding(s)`; PR comment carries both findings | PASS |

## fr-nfr-gate.sh — negative cases (mid-sequence gh failures)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| FNG-N1 | Zero findings; `gh api .../statuses/...` exits 1 (auth expired after claude ran) | warn `failed to post commit status`; still exit 0 (documented warn-only posting) | PASS |
| FNG-N2 | 2 findings; statuses POST and `gh pr comment` both exit 1 | both warns emitted; exit 1 preserved | PASS |
| FNG-N3 | 2 findings; `gh pr view` fails mid-run (no PR / auth) | warn `no PR found for the current branch; skipping PR comment`; failure status still POSTed; exit 1 | PASS |
| FNG-N4 | Malformed verdict (missing `FR_NFR_NEW_FINDINGS` line) | exit 1; failure status `gate output malformed: missing FR_NFR_NEW_FINDINGS line`; no PR comment | PASS |
| FNG-N5 | `gh` absent from `PATH` | exit 1 before any claude invocation | PASS |

## fr-nfr-gate.sh — edge cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| FNG-E1 | Verdict `FR_NFR_NEW_FINDINGS: 18446744073709551616` (2^64, wraps to 0 in bash arithmetic) | exit 1 + failure status (any n > 0 must fail) | FAIL — exit 0, posts SUCCESS status `zero new findings`, logs PASS (S2, BUG-3) |
| FNG-E2 | Verdict `FR_NFR_NEW_FINDINGS: 08` (octal-invalid for bash) | fail-safe: exit 1 + failure status | PASS (fails safe; bash `value too great for base` noise on stderr, then failure status + exit 1) |
| FNG-E3 | Verdict line followed by trailing blank lines | still parsed (awk keeps last non-empty line); exit 0 | PASS |
| FNG-E4 | Zero findings; statuses POST succeeds but prints garbage JSON on stdout | stdout discarded (`>/dev/null`); exit 0; clean PASS log | PASS |

## Verdict summary

- Cases run: 33 (re-runs for FAIL confirmation not counted). 28 PASS,
  5 FAIL rows collapsing into 3 distinct confirmed defects.
- BUG-1 (S3): `get-pr-comments.sh` surfaces a raw jq parse error
  (exit 5) or python traceback (exit 1) when gh exits 0 with non-JSON
  output — no script-level diagnosis (GPC-N3).
- BUG-2 (S2): `get-pr-comments.sh` exits 0 with success-shaped output on
  an exit-0 gh payload carrying no PR data — empty stdout renders zero
  bytes (jq backend), wrong-shape JSON and `pullRequest:null` render
  `unresolved threads: 0` — poisoning the FR-8 "0 unresolved" exit
  condition the pagination guard exists to protect (GPC-N4/N5/N6).
- BUG-3 (S2): `fr-nfr-gate.sh` 64-bit arithmetic wrap — a findings count
  that is a multiple of 2^64 passes the gate: exit 0 plus a SUCCESS
  `BMAD FR/NFR Review Gate` commit status (FNG-E1).
- Each defect reproduced twice; exact repro commands in the round-1
  session report.
- Environment notes: `yq` absent on this host (irrelevant: neither script
  reads YAML); jq 1.8.1 — GPC-E4 leading-zero behavior is
  version-dependent and passed here.

## Round 2

Tree state: round-1 fixes applied to the working branch. For this surface
the visible fix is the `raw_is_json` guard in `get-pr-comments.sh`
(BUG-1 / GPC-N3) plus two new bats tests covering it. Round 2 re-runs the
highest-risk round-1 cases, adds NEW cases that attack the seams of the
`raw_is_json` fix (empty/whitespace stdout, JSON streams, BOM, GraphQL
error envelopes, gh-resolved PR numbers), and re-probes the round-1 S2
defects (BUG-2 success-shaped output on payloads without PR data, BUG-3
fr-nfr-gate 64-bit findings wrap) to record whether they persist.

Method is unchanged from round 1: sandboxes under
`/tmp/sdlc-test-gh-integration/<case-id>/`, static stub `gh`/`claude`
from `tests/fixtures/bin`, per-case routing wrappers where subcommands
must diverge, both jq and python3 backends where the transform can
differ, every FAIL reproduced twice.

### Round 2 — get-pr-comments.sh re-runs (regression on the fix + persisting defects)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R2-GPC-1 | Re-run GPC-N3 (jq path): gh exit 0, HTML garbage stdout | exit 1; die names non-JSON, PR, repo; no raw `jq: parse error` | PASS — BUG-1 fix holds |
| R2-GPC-2 | Re-run GPC-N3 (python path, jq stripped) | exit 1; same die; no Traceback/JSONDecodeError | PASS — BUG-1 fix holds |
| R2-GPC-3 | Re-run GPC-N1: `gh pr view` → 7, then `gh api graphql` exits 1 | exit 1; `gh api graphql failed for PR #7 in acme/sample-api` | PASS |
| R2-GPC-4 | Re-run GPC-N2: auth expired before PR resolution (no `--pr`, `pr view` exits 1) | exit 1; `no PR found for the current branch (pass --pr <n>)` | PASS |
| R2-GPC-5 | Re-run GPC-P5: exactly 100 threads (37 unresolved), all `hasNextPage:false` | exit 0; no refusal; `unresolved threads: 37` | PASS |
| R2-GPC-6 | Re-run GPC-E5: `hasNextPage:true` on the issue-comments connection only | exit 1; pagination refusal | PASS |
| R2-GPC-7 | Re-run GPC-P7: unicode/emoji/CJK/RTL bodies, both backends | exit 0; bodies byte-faithful; backends agree | PASS |
| R2-GPC-8 | Re-run GPC-P8: `$(touch canary)`/backtick/`\(env)` injection bodies | exit 0; verbatim; canary NOT created | PASS |
| R2-GPC-9 | Re-run GPC-N4 (jq path): gh exit 0 with empty stdout | exit 1; clear script-level error | FAIL — exit 0, zero bytes of output (BUG-2 persists; `jq empty` accepts empty input so `raw_is_json` passes) |
| R2-GPC-10 | Re-run GPC-N4 (python path): gh exit 0 with empty stdout | exit 1; clear error | PASS on this backend — die `non-JSON output` (backend divergence vs R2-GPC-9 recorded under BUG-2) |
| R2-GPC-11 | Re-run GPC-N5: valid JSON wrong shape `{"ok":true}` | exit 1; clear error | FAIL — exit 0, `unresolved threads: 0` (BUG-2 persists) |
| R2-GPC-12 | Re-run GPC-N6: `data.repository.pullRequest: null` | exit 1; clear error | FAIL — exit 0, `unresolved threads: 0` (BUG-2 persists) |

### Round 2 — get-pr-comments.sh NEW cases (seams of the raw_is_json fix)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R2-GPC-13 | GraphQL error envelope, gh exit 0: `{"data":null,"errors":[{"message":"Could not resolve to a PullRequest..."}]}` | exit 1; error surfaced (payload carries no PR data) | FAIL — exit 0, `unresolved threads: 0`; GraphQL error message silently discarded (BUG-2 family) |
| R2-GPC-14 | Whitespace-only stdout (spaces + newlines), both backends | exit 1; non-JSON die on both | FAIL on jq backend — exit 0, zero output (same root cause as R2-GPC-9); python backend dies cleanly |
| R2-GPC-15 | Concatenated JSON documents `{"a":1}{"b":2}` (JSON stream), both backends | consistent rejection on both backends | FAIL — backend divergence: jq accepts the stream (exit 0, `unresolved threads: 0`); python dies `non-JSON` (recorded under BUG-2: wrong-shape acceptance is the jq-path symptom) |
| R2-GPC-16 | UTF-8 BOM prefix before valid full payload, both backends | consistent: either tolerated or refused on both | FIXED (was a real backend divergence, not the prior "both refuse" claim) — on jq 1.8.1 the jq path silently strips a leading BOM and renders the payload (exit 0) while python's `json.load` rejects it (`Unexpected UTF-8 BOM`, exit 1 `non-JSON output`). Root cause: `$raw` was consumed un-normalized by both backends. Fix: strip a leading BOM once after capture (`raw="${raw#$'\xef\xbb\xbf'}"`) so both backends now tolerate it identically (exit 0, identical canonical JSON); genuinely non-JSON-after-BOM still dies on both. Regression: get-pr-comments.bats "UTF-8 BOM before a valid payload …". gh never emits a BOM, so runtime risk was low. |
| R2-GPC-17 | `gh pr view` exits 0 printing non-numeric stdout (`not-a-number`); graphql then succeeds | gh-resolved PR validated like `--pr`, or clean die; no raw jq/--argjson error | FAIL — raw `jq: Invalid JSON text passed to --argjson` + empty-canonical exit; gh-resolved PR bypasses the `^[0-9]+$` validation applied to `--pr` (NEW BUG-4, S3) |
| R2-GPC-18 | Re-run GPC-E2: `author:null`, `body:null`, `path:null`, `line:null` | exit 0; `unknown` fallback; nulls preserved in `--json`; backends agree | PASS |
| R2-GPC-19 | 100-thread payload through `--json` on both backends | parse-identical canonical JSON (jq vs python) | PASS |

### Round 2 — fr-nfr-gate.sh re-runs + commit-status posting paths

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R2-FNG-1 | Re-run FNG-P1: zero findings, all gh calls succeed | exit 0; success status, exact context `BMAD FR/NFR Review Gate`; no PR comment | PASS |
| R2-FNG-2 | Re-run FNG-P3: 2 findings, routed gh | exit 1; failure status `2 new FR/NFR finding(s)`; PR comment with both findings | PASS |
| R2-FNG-3 | Re-run FNG-E1: verdict `FR_NFR_NEW_FINDINGS: 18446744073709551616` (2^64) | exit 1 + failure status | FAIL — exit 0, success status `zero new FR/NFR findings`, PASS log (BUG-3 persists, unfixed in tree) |
| R2-FNG-4 | Verdict `FR_NFR_NEW_FINDINGS: 18446744073709551617` (2^64+1) | exit 1; failure status | PASS (wraps to 1, fails; description carries the original string) — only exact 2^64 multiples escape, confirming BUG-3 mechanism |
| R2-FNG-5 | Re-run FNG-N1: statuses POST exits 1 on the zero-findings path | warn `failed to post commit status`; exit 0 | PASS |
| R2-FNG-6 | NEW: claude transport failure twice AND statuses POST fails | both failures reported (transport die + status warn); exit 1; no crash | PASS |
| R2-FNG-7 | Re-run FNG-N3: 2 findings; `gh pr view` fails mid-run | warn `skipping PR comment`; failure status still POSTed; exit 1 | PASS |
| R2-FNG-8 | Verdict line with CRLF ending (`FR_NFR_NEW_FINDINGS: 2\r`) | fail-safe acceptable: malformed path, exit 1 + failure status | PASS (informational — fails safe via malformed-output path) |
| R2-FNG-9 | Repo with zero commits (HEAD unresolvable) | die `cannot resolve HEAD` before any claude call | PASS — exit 1, no claude invocation logged |
| R2-FNG-10 | Malformed verdict: exactly one failure status POST, no comment | one `statuses` call in the gh log; no `pr comment` | PASS |
| R2-FNG-11 | Verdict `FR_NFR_NEW_FINDINGS: 010` (octal-valid, =8) | exit 1 (any non-zero); sane description | PASS — exit 1, status description `010 new FR/NFR finding(s)` |

### Round 2 verdict summary

- Cases run: 30 (FAIL confirmation re-runs not counted). 22 PASS (2 of
  them informational), 8 FAIL rows collapsing into 3 distinct defects.
- BUG-1 (S3, round 1) — FIXED and holding: `raw_is_json` dies cleanly on
  non-JSON gh stdout on both backends (R2-GPC-1/2); regression bats in
  `tests/get-pr-comments.bats` confirmed green.
- BUG-2 (S2, round 1) — STILL PRESENT: exit-0 gh payloads with no PR data
  produce success-shaped output. The `raw_is_json` fix only rejects
  non-JSON; empty stdout still passes `jq empty` (R2-GPC-9, R2-GPC-14),
  wrong-shape JSON, `pullRequest:null`, GraphQL error envelopes, and JSON
  streams all render `unresolved threads: 0` with exit 0
  (R2-GPC-11/12/13/15), poisoning the FR-8 "0 unresolved" exit condition.
- BUG-3 (S2, round 1) — STILL PRESENT: `fr-nfr-gate.sh` posts a SUCCESS
  `BMAD FR/NFR Review Gate` commit status and exits 0 for a findings
  count of exactly 2^64 (R2-FNG-3); 2^64+1 fails correctly (R2-FNG-4),
  confirming the bash arithmetic wrap mechanism.
- BUG-4 (S3, NEW): a gh-resolved PR number (from `gh pr view` exit 0 with
  garbage stdout) bypasses the `^[0-9]+$` validation that guards `--pr`,
  surfacing a raw `jq: Invalid JSON text passed to --argjson` error
  instead of a script-level diagnosis — the same defect class the
  round-1 BUG-1 fix addressed for the GraphQL payload (R2-GPC-17).
- All FAILs reproduced twice; sandboxes under
  `/tmp/sdlc-test-gh-integration/` removed after the run.

## Round 2 (verification re-run)

Second independent round-2 pass against the same committed tree (HEAD
`ad6497e`). Goal: confirm the round-1 fix still holds, re-confirm the
persisting round-1 S2 defects and the round-1 NEW BUG-4, and hunt for
regressions introduced by the `raw_is_json` guard. Sandboxes under
`/tmp/sdlc-test2-gh-integration/<case-id>/`, removed after the run; static
stub `gh`/`claude` copied (never symlinked) from `tests/fixtures/bin`;
per-case routing wrappers where subcommands diverge; both jq (1.8.1) and
python3 (3.14) backends where the transform can differ; every FAIL
reproduced twice. Host tools: jq 1.8.1, python3 3.14.4, gh 2.x, bats
1.11.1, markdownlint-cli 0.48.0. No git mutations.

### Round 2 verify — get-pr-comments.sh re-runs

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| V2-GPC-1 | GPC-N3 jq path: gh exit 0, HTML garbage stdout | exit 1; clean die naming PR, no raw `jq: parse error` | PASS — BUG-1 fix holds |
| V2-GPC-2 | GPC-N3 python path (jq stripped) | exit 1; same die; no Traceback/JSONDecodeError | PASS — BUG-1 fix holds |
| V2-GPC-3 | GPC-N1: `pr view` → 7, then `gh api graphql` exits 1 | exit 1; `gh api graphql failed for PR #7 in acme/sample-api` | PASS |
| V2-GPC-4 | GPC-N2: auth expired, no `--pr`, `pr view` exits 1 | exit 1; `no PR found for the current branch (pass --pr <n>)` | PASS |
| V2-GPC-5 | GPC-P5: 100 threads (37 unresolved), all `hasNextPage:false` | exit 0; no refusal; `unresolved threads: 37`; `--json` carries 100 | PASS |
| V2-GPC-6 | GPC-E5: `hasNextPage:true` on issue-comments only | exit 1; pagination refusal | PASS |
| V2-GPC-7 | GPC-P7: emoji/CJK/RTL/combining bodies, both backends | exit 0; byte-faithful; backends agree | PASS |
| V2-GPC-8 | GPC-P8: `$(touch canary)`/backtick/`\(env)` bodies | exit 0; verbatim; canary NOT created | PASS |
| V2-GPC-9 | GPC-N4 jq path: gh exit 0, empty stdout | exit 1; clear error | FAIL — exit 0, zero bytes (BUG-2 persists; `jq empty` accepts empty) |
| V2-GPC-10 | GPC-N4 python path: gh exit 0, empty stdout | exit 1; clear error | PASS on this backend — die `non-JSON output` (backend divergence under BUG-2) |
| V2-GPC-11 | GPC-N5: valid JSON wrong shape `{"ok":true}` | exit 1; clear error | FAIL — exit 0, `unresolved threads: 0` (BUG-2 persists) |
| V2-GPC-12 | GPC-N6: `data.repository.pullRequest: null` | exit 1; clear error | FAIL — exit 0, `unresolved threads: 0` (BUG-2 persists) |

### Round 2 verify — get-pr-comments.sh NEW probes

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| V2-GPC-13 | GraphQL error envelope, gh exit 0: `{"data":null,"errors":[{"message":"Could not resolve..."}]}` | exit 1; error surfaced | FAIL — exit 0, `unresolved threads: 0`; error message discarded (BUG-2 family) |
| V2-GPC-14 | gh exit 0, valid stdout, warnings on stderr (`GH_TOKEN deprecated`, rate-limit) | stderr ignored; stdout parsed; correct count | PASS — stderr does not taint `$(...)`; `unresolved threads: 1`; `--json` sane |
| V2-GPC-15 | Slow gh: `gh api graphql` sleeps 3s then returns valid JSON | completes after gh returns; no hang | PASS (informational) — no internal timeout contract; relies on gh/caller |
| V2-GPC-16 | Deleted author: `author:null` in a thread comment AND an issue comment, plus a sibling with a real author | exit 0; `unknown` fallback for the deleted ones; real author preserved | PASS |
| V2-GPC-17 | Body with escaped NUL (` `), valid JSON, both backends | exit 0; backends agree on rendered body | PASS — both drop the NUL; byte-identical |
| V2-GPC-18 | Body with a literal NUL inside a JSON string value, both backends | consistent handling, no crash | PASS — bash `$(...)` strips the NUL (warns); post-strip JSON parses; both backends render the same value, exit 0 |
| V2-GPC-19 | NUL-laden non-JSON garbage stdout, both backends | exit 1; script-level `non-JSON` die on both | PASS — BUG-1 fix holds through the NUL-strip |
| V2-GPC-20 | UTF-8 BOM prefix before a valid full payload, both backends | consistent across backends | FAIL — backend divergence: jq 1.8.1 strips the BOM and parses (exit 0, renders the payload), python `json.load` rejects it (exit 1 `non-JSON`); contradicts the prior round-2 R2-GPC-16 "both refuse" claim (doc-reality mismatch) |
| V2-GPC-21 | gh-resolved PR: `gh pr view` exit 0 prints `not-a-number`; graphql then succeeds | gh-resolved PR validated like `--pr`, or clean die | FAIL — raw `jq: invalid JSON text passed to --argjson`, exit 2; gh-resolved PR bypasses the `^[0-9]+$` guard applied to `--pr` (BUG-4 persists) |

### Round 2 verify — fr-nfr-gate.sh re-runs + posting paths

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| V2-FNG-1 | FNG-P1: zero findings, all gh succeed | exit 0; success status, exact context `BMAD FR/NFR Review Gate`; no PR comment | PASS |
| V2-FNG-2 | FNG-P3: 2 findings, routed gh (`pr view` → 12) | exit 1; failure status `2 new FR/NFR finding(s)`; PR comment on #12 with both findings | PASS |
| V2-FNG-3 | FNG-E1: verdict `FR_NFR_NEW_FINDINGS: 18446744073709551616` (2^64) | exit 1 + failure status | FAIL — exit 0, SUCCESS status `zero new FR/NFR findings`, PASS log (BUG-3 persists, unfixed) |
| V2-FNG-4 | Verdict `FR_NFR_NEW_FINDINGS: 18446744073709551617` (2^64+1) | exit 1; failure status | PASS — wraps to 1, fails; description carries the original string |
| V2-FNG-5 | FNG-N1: statuses POST exits 1 on the zero-findings path | warn `failed to post commit status`; exit 0 | PASS |
| V2-FNG-6 | NEW: claude transport fails twice AND statuses POST fails | both failures reported (transport die + status warn); exit 1; no crash | PASS |
| V2-FNG-7 | FNG-N3: 2 findings; `gh pr view` fails mid-run | warn `skipping PR comment`; failure status still POSTed; exit 1; no comment | PASS |
| V2-FNG-8 | Verdict line with CRLF (`FR_NFR_NEW_FINDINGS: 2\r`) | fail-safe acceptable | PASS (informational) — `\r` breaks the regex; malformed-output path, exit 1 + failure status |
| V2-FNG-9 | Repo with zero commits (HEAD unresolvable) | die `cannot resolve HEAD` before any claude call | PASS — exit 1, claude never invoked |
| V2-FNG-10 | Malformed verdict: exactly one failure status POST, no comment | one `statuses` call; no `pr comment` | PASS |
| V2-FNG-11 | Verdict `FR_NFR_NEW_FINDINGS: 010` (octal-valid, =8) | exit 1 (any non-zero); sane description | PASS — exit 1, description `010 new FR/NFR finding(s)` |

### Round 2 (verification) verdict summary

- Cases run: 32 (FAIL-confirmation re-runs not counted). 26 PASS (3 of
  them informational), 6 FAIL rows collapsing into 3 distinct defects.
- Every round-1 FAIL that was re-run did NOT all "now pass": BUG-1 is
  fixed and holding (V2-GPC-1/2 PASS, bats 12/13 green), but the round-1
  S2 defects BUG-2 (V2-GPC-9/11/12/13) and BUG-3 (V2-FNG-3) still
  reproduce, as does the round-1 NEW BUG-4 (V2-GPC-21). So
  `r1FailsNowPass = false`.
- BUG-1 (S3, round 1) — FIXED, holding: `raw_is_json` dies cleanly on
  non-JSON gh stdout on both backends, including NUL-laden garbage
  (V2-GPC-19). Both bats suites green (get-pr-comments 15/15,
  fr-nfr-gate 14/14).
- BUG-2 (S2, round 1) — STILL PRESENT: exit-0 gh payloads carrying no PR
  data produce success-shaped output. `raw_is_json` only rejects
  non-JSON; empty stdout passes `jq empty` (V2-GPC-9), and wrong-shape
  JSON / `pullRequest:null` / GraphQL error envelopes all render
  `unresolved threads: 0` with exit 0 (V2-GPC-11/12/13), poisoning the
  FR-8 "0 unresolved" exit condition.
- BUG-3 (S2, round 1) — STILL PRESENT: `fr-nfr-gate.sh` posts a SUCCESS
  `BMAD FR/NFR Review Gate` status and exits 0 for a findings count of
  exactly 2^64 (V2-FNG-3, reproduced twice); 2^64+1 fails correctly
  (V2-FNG-4). The `(( findings == 0 ))` comparison wraps in 64-bit bash
  arithmetic; the round-1 commit did not touch `fr-nfr-gate.sh`.
- BUG-4 (S3, round 1 NEW) — STILL PRESENT: a gh-resolved PR number from
  `gh pr view` exit 0 with non-numeric stdout bypasses the `^[0-9]+$`
  validation that guards `--pr`, surfacing a raw
  `jq: invalid JSON text passed to --argjson` (exit 2) instead of a
  script-level diagnosis (V2-GPC-21).
- NEW this round — BOM backend divergence (S3, doc-reality mismatch):
  with jq 1.8.1, `jq empty` and the jq transform strip a leading UTF-8
  BOM and parse the payload (exit 0, data preserved), while the python
  fallback's `json.load` rejects the same bytes with a BOM error and the
  script dies `non-JSON` (exit 1) (V2-GPC-20). The prior round-2 row
  R2-GPC-16 records this as "PASS (informational) — both backends refuse",
  which is incorrect on this host. gh does not emit a BOM in practice, so
  the runtime risk is low, but the two backends disagree and the plan
  text overstates the guarantee.
- All FAILs reproduced twice; sandboxes under
  `/tmp/sdlc-test2-gh-integration/` removed after the run.

## Round 3

Third pass against the committed tree (HEAD `180a282`), after the
round-2 fixes landed. Goal: prove the round-1/2 fixes HOLD (re-run their
real repros, never trust commit messages), and hunt for any remaining or
fix-introduced defect. The visible round-3 fixes in this surface:
`get-pr-comments.sh` now (a) dies on an empty gh body before the backend
split (lines 126-127), (b) strips a leading UTF-8 BOM once so both
backends agree (line 107), (c) runs `pr_data_check` to refuse exit-0
payloads carrying no PR data — GraphQL error envelopes, wrong-shape
objects, `pullRequest:null` (lines 142-173), and (d) re-validates a
gh-resolved PR number with `^[0-9]+$` (lines 53-55); `fr-nfr-gate.sh` now
zero-tests the findings count as a DIGIT STRING (`findings_norm`, lines
131-133) instead of bash arithmetic, so any multiple of 2^64 fails.

Method unchanged: sandboxes under `/tmp/sdlc-test3-gh-integration/<id>/`,
removed after the run; routing `gh`/`claude` wrappers built per case
(copied, never symlinked); both jq (1.8.1) and python3 (3.14.4) backends
where the transform can diverge; every FAIL reproduced twice. Host tools:
jq 1.8.1, python3 3.14.4, gh 2.92.0, bats 1.11.1, markdownlint-cli
0.48.0. No git mutations.

### Round 3 — get-pr-comments.sh: BUG-1/2/4 fix re-runs (prove they hold)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-GPC-1 | BUG-2 re-run, jq: gh exit 0, empty stdout | exit 1; clean die `returned an empty response` | PASS — fix holds |
| R3-GPC-2 | BUG-2 re-run, python (jq stripped): empty stdout | exit 1; identical die (no backend divergence) | PASS — divergence gone |
| R3-GPC-3 | BUG-2 re-run, jq: wrong-shape `{"ok":true}` | exit 1; `no pull-request data` | PASS |
| R3-GPC-4 | BUG-2 re-run, python: wrong-shape `{"ok":true}` | exit 1; identical die | PASS |
| R3-GPC-5 | BUG-2 re-run, jq: `data.repository.pullRequest:null` | exit 1; `no pull-request data` | PASS |
| R3-GPC-6 | BUG-2 re-run, python: `pullRequest:null` | exit 1; identical die | PASS |
| R3-GPC-7 | BUG-2 re-run, jq: GraphQL error envelope `{"data":null,"errors":[…]}` | exit 1; surfaces the error message | PASS |
| R3-GPC-8 | BUG-2 re-run, python: GraphQL error envelope | exit 1; surfaces identical message | PASS |
| R3-GPC-9 | BUG-1 re-run, jq: gh exit 0, HTML garbage | exit 1; `returned non-JSON output`, no raw jq parse error | PASS |
| R3-GPC-10 | BUG-1 re-run, python: HTML garbage | exit 1; identical die, no traceback | PASS |
| R3-GPC-11 | BUG-4 re-run, jq: `gh pr view` exit 0 prints `not-a-number`, no `--pr` | exit 1; `resolved PR number is not numeric`, no raw `--argjson` error | PASS |
| R3-GPC-12 | BUG-4: `gh pr view` exit 0 prints empty string, no `--pr` | exit 1; `resolved PR number is not numeric: ''` | PASS |
| R3-GPC-13 | BUG-4 re-run, python: gh-resolved `not-a-number` | exit 1; identical die | PASS |

### Round 3 — get-pr-comments.sh: pagination guard at exactly 100 (new)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-GPC-14 | Exactly 100 review threads (37 unresolved), every `hasNextPage:false`, jq | exit 0; no refusal; `unresolved threads: 37` | PASS |
| R3-GPC-15 | Same 100-thread payload, python backend | exit 0; identical render | PASS |
| R3-GPC-16 | 100 threads, `reviewThreads.pageInfo.hasNextPage:true`, jq | exit 1; pagination refusal | PASS |
| R3-GPC-17 | Same truncation payload, python | exit 1; identical refusal | PASS |
| R3-GPC-18 | 1 thread with exactly 100 comments, `comments.pageInfo.hasNextPage:true`, jq | exit 1; refusal (comment-level guard) | PASS |
| R3-GPC-19 | Comment-level truncation payload, python | exit 1; identical refusal | PASS |

### Round 3 — get-pr-comments.sh: injection bodies w/ backticks & `$()` (new)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-GPC-20 | Body `` `touch CANARY` ``/`$(touch CANARY)`/`\(env)`/`${HOME}`, jq human render | exit 0; verbatim; no canary; no `${HOME}` expansion | PASS |
| R3-GPC-21 | Same injection body, python human render | exit 0; verbatim; no canary | PASS |
| R3-GPC-22 | Same injection body, `--json`, both backends | parse-identical canonical JSON; bodies byte-faithful | PASS |

### Round 3 — get-pr-comments.sh: pr_data_check seams (new)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-GPC-23 | GraphQL error message itself contains `$(touch ERRCANARY)`/backticks | exit 1; message rendered verbatim in the die; no canary | PASS |
| R3-GPC-24 | `data.repository:null` (not just pullRequest) | exit 1; `no pull-request data` | PASS |
| R3-GPC-25 | `errors:[…]` present ALONGSIDE valid `pullRequest` data | exit 1; errors take precedence, surfaced | PASS |
| R3-GPC-26 | `errors:[]` (empty) with valid PR data | exit 0; legitimately `unresolved threads: 0` (length 0 is not an error) | PASS |

### Round 3 — get-pr-comments.sh: standard positive/edge re-runs

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-GPC-27 | Empty PR: both arrays `[]` | exit 0; `unresolved threads: 0` | PASS |
| R3-GPC-28 | Issue comments only, one with `author:null` | exit 0; `unknown` fallback | PASS |
| R3-GPC-29 | `--unresolved-only`: issue comments excluded, resolved thread filtered | exit 0; only the open thread; `unresolved threads: 1` | PASS |
| R3-GPC-30 | All `pageInfo` objects absent | exit 0; no false refusal | PASS |
| R3-GPC-31 | `--pr 007` (leading zeros) | exit 0; renders `PR #7` | PASS |
| R3-GPC-32 | `author:null`,`body:null`,`path:null`,`line:null` | exit 0; `?:0` placeholder, `unknown` author | PASS |

### Round 3 — get-pr-comments.sh: adversarial JSON type-confusion (new)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-GPC-33 | Top-level JSON array `[1,2,3]`, jq | exit 1; clean script-level die naming PR | FAIL — exit 5 (raw jq), zero `[php-sdlc]` diagnostic lines (NEW BUG-5, S3) |
| R3-GPC-34 | Top-level array `[1,2,3]`, python | exit 1; clean die | FAIL — exit 1 but zero script-level diagnostic (BUG-5) |
| R3-GPC-35 | Top-level scalar `"hello"` / `42` / `true`, jq | exit 1; clean die | FAIL — exit 5 raw jq, no diagnostic (BUG-5) |
| R3-GPC-36 | Top-level scalar, python | exit 1; clean die | FAIL — bare exit 1, no diagnostic (BUG-5) |
| R3-GPC-37 | `pullRequest` non-null but `reviewThreads` a string (wrong type), jq | exit 1; clean die | FAIL — leaks raw `jq: error … Cannot index string with string "nodes"`, exit 5 (BUG-5) |
| R3-GPC-38 | Same wrong-type child, python | exit 1; clean die | FAIL — leaks python `Traceback … for t in (p.get("reviewThreads") …` (BUG-5) |
| R3-GPC-39 | `pullRequest:{}` (empty object) / `reviewThreads:{}`,`comments:{}` | exit 0; treated as empty PR; `unresolved threads: 0` | PASS (informational — a non-null empty PR object is legitimately empty; NOT a silent gate escape) |

### Round 3 — get-pr-comments.sh: BUG-5 fix element-level residue (BUG-6)

The BUG-5 fix (committed `pr_data_check` SHAPE guard) validates connections
only down to "`nodes` is a list" — it never checks that each `nodes`
ELEMENT is an object. A scalar comment node slips the guard and dies in
`normalize` with the exact raw error BUG-5 was built to suppress.

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-GPC-40 | Issue comment node is a scalar: `comments.nodes:[42]`, jq | exit 1; clean `unexpected response shape` die naming PR; no `jq: error`, no `Cannot index` | FAIL → BUG-6 — leaked `jq: error … Cannot index number with string "author"`, exit 5, ZERO `[php-sdlc]` line |
| R3-GPC-41 | Same scalar issue-comment node, python | exit 1; clean die | FAIL → BUG-6 — leaked `Traceback … AttributeError: 'int' object has no attribute 'get'`, exit 1 |
| R3-GPC-42 | Thread comment node is a scalar: `reviewThreads.nodes[0].comments.nodes:[42]`, jq | exit 1; clean die | FAIL → BUG-6 — same raw `jq: error … Cannot index number`, exit 5 |
| R3-GPC-43 | Same scalar thread-comment node, python | exit 1; clean die | FAIL → BUG-6 — same `AttributeError` traceback |
| R3-GPC-44 | BUG-6 fix verify: all four payloads, both backends | exit 1; `unexpected response shape`; no `jq: error`/`Cannot index`/`Traceback`/`AttributeError` | PASS — `pr_data_check` now forces per-element object access (`has("author")` under try/catch in jq; `comments_ok` isinstance loop in python); healthy multi-comment payload still renders `unresolved threads: 1` on both backends |

### Round 3 — fr-nfr-gate.sh: BUG-3 digit-string zero-test (prove it holds)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-FNG-1 | `FR_NFR_NEW_FINDINGS: 18446744073709551616` (2^64) | exit 1; FAILURE status; PR comment | PASS — `state=failure`, comment posted, exit 1; SUCCESS no longer escapes (BUG-3 FIXED) |
| R3-FNG-2 | 2^64 second independent repro | exit 1; FAILURE status | PASS — reproduced; `state=failure` |
| R3-FNG-3 | `36893488147419103232` (2×2^64, also wraps to 0 in bash) | exit 1; FAILURE status | PASS — `state=failure`; digit-string check catches all multiples |
| R3-FNG-4 | `18446744073709551617` (2^64+1) | exit 1; FAILURE status | PASS — description carries the original string |
| R3-FNG-5 | `00018446744073709551616` (leading zeros + 2^64) | exit 1; FAILURE | PASS — `findings_norm` strips zeros, still nonzero |
| R3-FNG-6 | `FR_NFR_NEW_FINDINGS: 0000` (all zeros) | exit 0; SUCCESS; no comment | PASS — normalizes to `0` |
| R3-FNG-7 | `FR_NFR_NEW_FINDINGS: 010` (octal-looking) | exit 1; FAILURE; sane description | PASS — `state=failure`, description `010 new FR/NFR finding(s)` |

### Round 3 — fr-nfr-gate.sh: positive/negative posting paths

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R3-FNG-8 | Zero findings, all gh succeed | exit 0; SUCCESS status, exact context `BMAD FR/NFR Review Gate`; no comment | PASS |
| R3-FNG-9 | 2 findings, all gh succeed | exit 1; FAILURE status `2 new FR/NFR finding(s)`; comment on #12 | PASS |
| R3-FNG-10 | SSH origin `git@github.com:acme/sample-api.git` | status POSTed to `repos/acme/sample-api/statuses/<sha>` | PASS |
| R3-FNG-11 | Malformed verdict (no `FR_NFR_NEW_FINDINGS` line) | exit 1; FAILURE status; contract-violation die; no comment | PASS |
| R3-FNG-12 | Zero findings; statuses POST exits 1 (auth expired) | warn; exit 0 (warn-only posting) | PASS |
| R3-FNG-13 | 2 findings; `gh pr view` fails mid-run | warn `skipping PR comment`; FAILURE status still POSTed; exit 1 | PASS |
| R3-FNG-14 | `gh` absent from `PATH` | exit 1 `gh CLI not found on PATH`; claude never invoked | PASS |
| R3-FNG-15 | Finding body with `` `touch GATE-CANARY` ``/`$(…)`/`${HOME}` | exit 1; body posted verbatim in PR comment; no canary; no `${HOME}` expansion | PASS |

### Round 3 verdict summary

- Cases run: 66 distinct (FAIL-confirmation re-runs not counted). 55 PASS
  (2 informational), 11 FAIL rows collapsing into 2 new defects (BUG-5,
  BUG-6) — both fixed this round with bats coverage.
- Prior fixes RE-RUN for real, NOT trusted from commit messages:
  - BUG-1 (S3, r1) — HOLDS: non-JSON gh stdout dies cleanly on both
    backends (R3-GPC-9/10).
  - BUG-2 (S2, r1, persisted through r2) — NOW FIXED and holding: empty
    stdout, wrong-shape JSON, `pullRequest:null`, GraphQL error envelopes
    all die `exit 1` with a script-level diagnostic on BOTH backends; the
    prior jq/python divergence on empty stdout is gone (R3-GPC-1..8,
    23..25). The FR-8 "0 unresolved" exit condition is no longer poisoned
    by these payloads.
  - BUG-3 (S2, r1, persisted through r2) — NOW FIXED and holding: the
    `findings_norm` digit-string zero-test fails the gate for 2^64,
    2×2^64, and leading-zero 2^64, posting a FAILURE status and exiting 1
    (R3-FNG-1..5); `0000` still passes (R3-FNG-6). A 2^64 findings count
    no longer posts SUCCESS. Reproduced twice (R3-FNG-1/2).
  - BUG-4 (S3, r1 NEW) — NOW FIXED and holding: a gh-resolved PR that is
    non-numeric or empty dies `resolved PR number is not numeric` before
    `--argjson`, no raw jq error (R3-GPC-11/12/13).
  - BOM divergence (S3, r2) — FIXED: line 107 strips a leading BOM once;
    both backends now tolerate it identically (bats test 14 green).
- NEW this round — BUG-5 (S3, fix-introduced gap in the BUG-1/2 guard
  family): when gh exits 0 with VALID JSON that is not a top-level object
  (`[1,2,3]`, `"hello"`, `42`, `true`), or an object whose `pullRequest`
  is non-null but a child connection has the wrong type
  (`reviewThreads:"oops"`), `raw_is_json` accepts it (it is valid JSON)
  and `pr_data_check` swallows its own jq/python error via `2>/dev/null`
  (returning empty ⇒ "no problem"), so the script proceeds to
  `normalize`, where jq dies with a raw `jq: error … Cannot index …`
  (exit 5) or python emits a bare `Traceback`, with ZERO `[php-sdlc]`
  script-level diagnostic. This is the exact defect class the round-1
  BUG-1 fix and round-2 BUG-2 fix were built to eliminate; they cover
  non-JSON text and no-PR-data OBJECTS but not valid-JSON-of-wrong-type.
  Not a silent success (it exits nonzero, no false "0 unresolved"), so
  S3/minor — same rating as the original BUG-1. gh's GraphQL endpoint
  returns a top-level object in practice, so runtime likelihood is low,
  but it is exactly the "gh exit 0 with unexpected JSON" scenario the
  guards exist to handle. Reproduced twice on both backends
  (R3-GPC-33..38). FIXED this round (`pr_data_check` SHAPE guard).
- NEW this round — BUG-6 (S3, residue in the BUG-5 fix itself): the
  committed BUG-5 SHAPE guard validates each connection only down to
  "`nodes` is a list" and never checks that each `nodes` ELEMENT is an
  object. A scalar comment node — `comments.nodes:[42]` (an issue
  comment) or `reviewThreads.nodes[0].comments.nodes:[42]` (a thread
  comment) — passes the guard and reaches `normalize`, which leaks the
  exact raw error BUG-5 set out to suppress: `jq: error … Cannot index
  number with string "author"` (exit 5) on jq, and `Traceback …
  AttributeError: 'int' object has no attribute 'get'` (exit 1) on
  python. Reproduced 4× (issue-comment and thread-comment positions ×
  both backends; also under `--unresolved-only` and `--json`)
  (R3-GPC-40..43). FIXED: `pr_data_check` now forces per-element object
  access — jq runs `[…nodes]|all(has("author"))` (and `has("isResolved")`
  for thread nodes) inside the same try/catch so a non-object node aborts
  to SHAPE; python adds a `comments_ok` isinstance loop over every issue
  and thread comment node. Healthy payloads, empty PRs, and null-author
  comments are NOT over-rejected (R3-GPC-44).
- Regression suites green on this tree: `tests/get-pr-comments.bats`
  31/31 (4 new R3 Bug 6 cases), `tests/fr-nfr-gate.bats` 17/17.
- All FAILs reproduced twice (BUG-6 reproduced 4×); sandboxes under
  `/tmp/sdlc-test3-*/` removed after the run.
