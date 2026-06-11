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
| R2-GPC-16 | UTF-8 BOM prefix before valid full payload, both backends | consistent: either tolerated or refused on both | PASS (informational) — both backends refuse (`non-JSON output` die); matches python `json.load` and jq behavior; gh never emits BOM |
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
