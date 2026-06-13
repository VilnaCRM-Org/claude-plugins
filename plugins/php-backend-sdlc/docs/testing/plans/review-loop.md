# Test Plan — Surface: review-loop

Target: `plugins/php-backend-sdlc/scripts/ai-review-loop.sh` driven by stub
`claude` binaries. Contract sources: the script header (ADR-8 fault
contract), `scripts/lib/common.sh` (`claude_run_once` transport contract),
PRD FR-8 / FR-18 / NFR-6, and `tests/ai-review-loop.bats`.

Date: 2026-06-11. Sandbox: `/tmp/sdlc-test-review-loop/` (deleted after the
round). No git mutations; the only repo write is this plan file.

## Harness

- Static stub: `tests/fixtures/bin/claude` (`STUB_CLAUDE_OUTPUT`,
  `STUB_CLAUDE_EXIT`, `STUB_CLAUDE_LOG`) prepended to `PATH`.
- Sequenced stub: per-case generated `claude` wrapper that replays response
  N on call N (last repeats) and appends argv to a call log — same pattern
  as `seq_claude` in the bats suite.
- Each case runs in a fresh work dir; call counts come from the argv log.
- Runner: `/tmp/sdlc-test-review-loop/runner.sh` asserting exit status,
  output substrings, and exact call counts per case.

Canned responses:

```text
PASS_JSON  {"result":"all good\nAI_REVIEW_VERDICT: PASS"}
FAIL_JSON  {"result":"found issues\nAI_REVIEW_VERDICT: FAIL"}
```

## Positive cases

| ID | Case | Setup / command | Expected | Result |
| --- | --- | --- | --- | --- |
| RL-P01 | PASS verdict on first iteration | static stub, `PASS_JSON`; run loop with defaults | exit 0; output has `PASS on iteration 1` and the result body; 1 claude call | PASS |
| RL-P02 | FAIL then PASS | seq: `FAIL_JSON`, `PASS_JSON` | exit 0; `FAIL verdict` then `PASS on iteration 2`; 2 calls | PASS |
| RL-P03 | PASS exactly at `--max-iterations` boundary | seq: FAIL, FAIL, PASS; `--max-iterations 3` | exit 0; `PASS on iteration 3`; 3 calls | PASS |
| RL-P04 | `--max-iterations 1` with immediate PASS | static stub `PASS_JSON`; `--max-iterations 1` | exit 0; 1 call | PASS |
| RL-P05 | JSON with extra fields (canonical CLI shape) | `{"type":"result","subtype":"success","is_error":false,"duration_ms":42,"result":"ok\nAI_REVIEW_VERDICT: PASS","session_id":"s1","total_cost_usd":0.01}` | exit 0; PASS on iteration 1; extra keys ignored | PASS |
| RL-P06 | explicit `is_error:false` | `{"is_error":false,"result":"fine\nAI_REVIEW_VERDICT: PASS"}` | exit 0; no `is_error` warning; 1 call | PASS |
| RL-P07 | multi-line result, blank lines after verdict | `{"result":"l1\nl2\n\nAI_REVIEW_VERDICT: PASS\n\n\n"}` | exit 0; trailing blank lines tolerated (last non-empty line is the verdict) | PASS |
| RL-P08 | `REVIEW_PROMPT` env override | `REVIEW_PROMPT='QA_CUSTOM_PROMPT_7731 …'` + `PASS_JSON` | exit 0; call log contains the custom prompt and NOT the default `Review the working tree` prompt | PASS |
| RL-P09 | space-separated `--agents "codex claude"` | static stub `PASS_JSON` | exit 0; warn+skip for codex; claude runs once | PASS |
| RL-P10 | profile matrix mixed: `[codex, claude]` | `.claude/php-sdlc.yml` with `review.ai_review_agents: [codex, claude]`, no `--agents` | exit 0; codex warn+skip; claude PASS; 1 call | PASS |
| RL-P11 | profile present but no `review.ai_review_agents` key | profile with unrelated keys only | exit 0; defaults to claude; 1 call | PASS |

## Negative cases

| ID | Case | Setup / command | Expected | Result |
| --- | --- | --- | --- | --- |
| RL-N01 | perpetual FAIL hits default cap (NFR-6) | seq: `FAIL_JSON` forever | exit 1; `iteration 5/5`; `no PASS within 5 iterations`; `escalate`; exactly 5 calls | PASS |
| RL-N02 | well-formed FAIL is NOT retried | seq `FAIL_JSON`; `--max-iterations 1` | exit 1; exactly 1 call; no `retrying once` | PASS |
| RL-N03 | verdict missing entirely | `{"result":"review text without verdict"}`; max 1 | exit 1; contract-violation warn; NO retry; 1 call | PASS |
| RL-N04 | verdict present but not last line | `{"result":"AI_REVIEW_VERDICT: PASS\ntrailing remark"}`; max 1 | exit 1; contract-violation warn (last non-empty line is not a verdict); no retry; 1 call | PASS |
| RL-N05 | `is_error:true` with exit 0 | `{"is_error":true,"result":"API Error: 529 Overloaded"}`; max 1 | exit 1; `is_error` warn; `retrying once`; no `contract` log; 2 calls | PASS |
| RL-N06 | claude exit code 1 (valid PASS on stdout) | static stub `PASS_JSON`, `STUB_CLAUDE_EXIT=1`; max 1 | exit 1; `claude exited non-zero`; one retry; output not parsed as verdict; 2 calls | PASS |
| RL-N07 | claude exit code 124 (timeout-like) | static stub `PASS_JSON`, `STUB_CLAUDE_EXIT=124`; max 1 | exit 1; same one-retry transport contract; 2 calls | PASS |
| RL-N08 | empty result string | `{"result":""}`; max 1 | exit 1; treated as no-`.result` transport failure; one retry; 2 calls | PASS |
| RL-N09 | `--max-iterations 0` | run with `--max-iterations 0` | exit 1; `must be a positive integer`; 0 claude calls | PASS |
| RL-N10 | `--max-iterations -1` | run with `--max-iterations -1` | exit 1; `must be a positive integer`; 0 calls | PASS |
| RL-N11 | `--max-iterations 1.5` | run with `--max-iterations 1.5` | exit 1; `must be a positive integer`; 0 calls | PASS |
| RL-N12 | all agents unsupported via `--agents codex` | `--agents codex` | exit non-zero; codex warn; `no supported review agent ran`; 0 calls | PASS |
| RL-N13 | all agents unsupported via profile `[gemini, codex]` | profile list without claude | exit non-zero; both warns; `no supported review agent ran`; 0 calls | PASS |
| RL-N14 | unknown flag | `--bogus` | exit 1; `unknown argument` with usage string; 0 calls | PASS |
| RL-N15 | `--agents` without a value | `--agents` as last arg | exit non-zero; error mentions `--agents needs a value`; 0 calls | PASS |
| RL-N16 | claude CLI absent from PATH | `PATH=/usr/bin:/bin` (no stub, no real claude); `--agents claude` | exit 1; `claude CLI not found on PATH`; 0 calls | PASS |
| RL-N17 | mixed matrix where the supported agent never passes | `--agents codex,claude`; seq `FAIL_JSON`; max 1 | exit 1; codex skip warn AND `no PASS within 1 iterations` escalation | PASS |

## Edge cases

| ID | Case | Setup / command | Expected | Result |
| --- | --- | --- | --- | --- |
| RL-E01 | `is_error:true` then clean PASS on retry | seq: is_error JSON, `PASS_JSON`; max 1 | exit 0; `retrying once`; `PASS on iteration 1`; 2 calls | PASS |
| RL-E02 | garbage (non-JSON) then PASS on retry | seq: `garbage`, `PASS_JSON`; max 1 | exit 0; `malformed JSON` warn; `retrying once`; 2 calls | PASS |
| RL-E03 | mixed sequence FAIL, missing-verdict, PASS | seq of 3; `--max-iterations 3` | exit 0; missing verdict consumes exactly one iteration without retry; `PASS on iteration 3`; 3 calls | PASS |
| RL-E04 | verdict line with trailing space | `{"result":"ok\nAI_REVIEW_VERDICT: PASS "}`; max 1 | exit 1; strict exact-line contract → counted as malformed verdict, no retry; 1 call (record behavior) | PASS |
| RL-E05 | PASS mid-text, FAIL as last line | `{"result":"AI_REVIEW_VERDICT: PASS\nmore\nAI_REVIEW_VERDICT: FAIL"}`; max 1 | exit 1; last line wins → FAIL verdict path, no contract warn, no retry; 1 call | PASS |
| RL-E06 | non-string `.result` (number) | `{"result":42}`; max 1 | exit 1; stringified `42` is not a verdict → contract path, no retry; 1 call | PASS |
| RL-E07 | exit 0 with completely empty stdout | static stub, no `STUB_CLAUDE_OUTPUT`; max 1 | exit 1; malformed-JSON transport path; one retry; 2 calls | PASS |
| RL-E08 | `REVIEW_PROMPT` set to empty string | `REVIEW_PROMPT=` + `PASS_JSON` | exit 0; falls back to the default prompt (call log contains `Review the working tree`) | PASS |
| RL-E09 | duplicate agent `--agents claude,claude` | static stub `PASS_JSON` | exit 0; agent loop runs twice; 2 calls (documented observation, not a defect) | PASS |
| RL-E10 | verdict without space `AI_REVIEW_VERDICT:PASS` | `{"result":"ok\nAI_REVIEW_VERDICT:PASS"}`; max 1 | exit 1; exact-format contract → malformed verdict; 1 call | PASS |
| RL-E11 | repeated `--max-iterations` flags | `--max-iterations 1 --max-iterations 2`; seq FAIL | exit 1; last flag wins; `no PASS within 2 iterations`; 2 calls | PASS |

## Verdict and findings

Round 1 executed 2026-06-11: **39/39 cases PASS, zero confirmed bugs.**
Every case was run twice (full matrix re-executed) with identical results,
plus a negative-control run proving the harness detects deviations.

Observations recorded (judged not bugs):

- RL-E04 / RL-E10: verdict lines with trailing whitespace or a missing
  space after the colon are rejected as ADR-8 contract violations and fail
  closed (exit 1, no retry). Strict but matches the documented
  "mandatory last-line verdict" contract; never a silent pass.
- RL-N08 / RL-E07: an empty `.result` string takes the one-retry
  transport path with a "malformed JSON" warning rather than the no-retry
  contract path. Both paths end in a failed iteration and exit 1, so the
  loop-safety outcome is identical; logged as contract ambiguity only.
- RL-E09: `--agents claude,claude` runs the claude loop twice. Consistent
  with "for each agent in the list" semantics; user-controlled input.
- RL-N15: `--agents` without a value aborts via the bash `${2:?}`
  expansion message (`--agents needs a value`), exit 1 — terse but
  accurate and non-zero.

No S1–S4 defects found on this surface in round 1.

## Round 2

Date: 2026-06-11. The tree gained fixes since round 1 (cubic review fixes,
symlink hardening in `fr-nfr-gate.sh`, and a new `yaml_parses` helper in
`scripts/lib/common.sh` — the review loop's transport/profile library).
`ai-review-loop.sh` itself is unchanged, so round 2 re-runs the
highest-risk round-1 cases (loop-safety, fault contract, all-skip matrix)
to catch regressions through the shared library, plus NEW cases targeting
the library changes (profile parsing edges, python fallbacks) and inputs
not covered in round 1 (prompt injection, CRLF, null result, jq-absent
parity).

Sandbox: `/tmp/sdlc-test-review-loop/` (fresh, deleted after the round).
Same harness as round 1: static fixture stub + per-case sequenced stub
with argv call log; every deviation re-run twice before judging.

### Round-2 re-runs (highest-risk subset)

Re-executed 2026-06-11 against the post-fix tree (commit `ad6497e`). Default
backend on this host: `jq` present, `yq` ABSENT so all YAML access takes the
python3+PyYAML fallback.

| ID | Case (see round-1 tables) | Result |
| --- | --- | --- |
| RL-P01 | PASS verdict on first iteration | PASS |
| RL-P02 | FAIL then PASS | PASS |
| RL-P03 | PASS exactly at `--max-iterations` boundary | PASS |
| RL-P04 | `--max-iterations 1` with immediate PASS | PASS |
| RL-P05 | JSON with extra fields (canonical CLI shape) | PASS |
| RL-P08 | `REVIEW_PROMPT` env override | PASS |
| RL-P09 | space-separated `--agents "codex claude"` | PASS |
| RL-P10 | profile matrix mixed `[codex, claude]` | PASS |
| RL-N01 | perpetual FAIL hits default cap (NFR-6) | PASS |
| RL-N02 | well-formed FAIL is NOT retried | PASS |
| RL-N03 | verdict missing entirely | PASS |
| RL-N04 | verdict present but not last line | PASS |
| RL-N05 | `is_error:true` with exit 0 | PASS |
| RL-N06 | claude exit code 1 | PASS |
| RL-N07 | claude exit code 124 | PASS |
| RL-N08 | empty result string | PASS |
| RL-N09 | `--max-iterations 0` | PASS |
| RL-N12 | all agents unsupported via `--agents codex` | PASS |
| RL-E01 | `is_error:true` then clean PASS on retry | PASS |
| RL-E02 | garbage (non-JSON) then PASS on retry | PASS |

All 20 re-run cases reproduce their round-1 results. No round-1 case
regressed through the shared-library changes (`yaml_parses` addition,
unchanged `claude_run_once`).

### Round-2 new cases

| ID | Case | Setup / command | Expected | Result |
| --- | --- | --- | --- | --- |
| RL2-01 | malformed YAML profile | `.claude/php-sdlc.yml` with broken syntax (`[unclosed`), no `--agents`; `PASS_JSON` | no crash; degrades to default agent claude; exit 0; 1 call | PASS (see BUG-RL2 note) |
| RL2-02 | profile `review.ai_review_agents` is a scalar, not a list | `review:\n  ai_review_agents: claude`; `PASS_JSON` | no crash; either uses claude or defaults to claude; exit 0 | PASS |
| RL2-03 | `REVIEW_PROMPT` injection payload | `REVIEW_PROMPT='$(touch HACKED) \`touch HACKED2\` ; rm -rf x'` + `PASS_JSON` | no file created, no command executed; payload passed verbatim as one argv to claude; exit 0 | PASS |
| RL2-04 | jq absent — python3 JSON fallback, PASS | restricted PATH without jq (bash/awk/dirname/env/python3 + stub only); `PASS_JSON` | exit 0; PASS on iteration 1; 1 call | PASS |
| RL2-05 | jq absent — python3 fallback, `is_error:true` | same restricted PATH; is_error JSON; max 1 | exit 1; `is_error` warn; one retry; 2 calls | PASS |
| RL2-06 | CRLF line endings in result | `{"result":"ok\r\nAI_REVIEW_VERDICT: PASS\r"}`; max 1 | trailing CR breaks the exact verdict match → fail closed (exit 1, contract warn, no retry, 1 call); never a silent pass | PASS (both backends) |
| RL2-07 | `.result` is JSON `null` | `{"result":null}`; max 1 | transport path (no `.result`); one retry; exit 1; 2 calls | PASS |
| RL2-08 | `is_error` is string `"true"`, not bool | `{"is_error":"true","result":"ok\nAI_REVIEW_VERDICT: PASS"}`; max 1 | strict bool compare → not a transport error; verdict parsed; exit 0; 1 call (record) | PASS |
| RL2-09 | `--diff-base` flows into default prompt | `--diff-base develop` + `PASS_JSON`, no `REVIEW_PROMPT` | call log contains `git diff against develop`; exit 0 | PASS |
| RL2-10a | `--max-iterations 007` (leading zero) | run with `--max-iterations 007` | exit 1; `must be a positive integer`; 0 calls | PASS |
| RL2-10b | large `--max-iterations 100`, immediate PASS | `--max-iterations 100` + `PASS_JSON` | exit 0; exactly 1 call (no useless looping) | PASS |
| RL2-11 | mixed separators `--agents "codex, claude"` | comma+space in one token; `PASS_JSON` | codex warn+skip; empty token dropped; exit 0; 1 call | PASS |
| RL2-12 | trailing garbage after JSON on stdout | stub prints `PASS_JSON` then a bare log line; max 1 | record behavior; must end deterministically (PASS via salvaged `.result`, or transport retry); no crash | PASS (backend-divergent, see note) |
| RL2-13 | multi-line `REVIEW_PROMPT` override | 3-line prompt via env + `PASS_JSON` | full prompt incl. newlines reaches claude argv; exit 0 | PASS |
| RL2-14 | python YAML fallback for profile matrix | `SDLC_FORCE_PYTHON_YAML=1`, profile `[codex, claude]`; `PASS_JSON` | codex warn+skip; claude PASS; exit 0; 1 call (parity with RL-P10) | PASS |

### Round-2 supplementary probes (not in the planned matrix)

Executed to chase the round-2 focus areas (regressions from fixes, the
task-named prompt/CRLF/collision vectors). All recorded as observations.

- Concurrent loops, same CWD + shared profile: `ai-review-loop.sh` and
  `claude_run_once` write NO on-disk iteration/temp logs (all logging is
  stdout/stderr; the iteration counter is a shell loop variable). Two loops
  run in parallel produced independent, correct results — the "iteration log
  collision" hypothesis does not apply to the product (only the test stub's
  own `STUB_CLAUDE_LOG` is a file, and that is test-side).
- `REVIEW_PROMPT` with embedded double quotes, single quotes, a genuine LF
  newline, `$VAR`, and backticks: passed verbatim as one argv to claude with
  zero expansion (it is a value, never `eval`'d). No injection, no file
  created.
- Verdict line with a trailing SPACE: fail-closed (exit 1, contract warn, 1
  call) on BOTH the jq and python3 backends — consistent.
- Empty list `[]`, explicit null `ai_review_agents:`, and an all-empty-token
  `--agents "  ,  , "` all default to claude correctly (set -u empty-array
  guard `${agents[@]+...}` holds). A tab-separated `--agents` token is treated
  as one unsupported agent name (IFS is documented as `', '`), so it
  fail-closes with "no supported agent" rather than silently passing.

### Round-2 verdict

35/35 planned round-2 cases PASS (20 re-runs + 15 new). Every round-1 case
that was re-run reproduced its round-1 outcome; no regression through the
shared-library fixes. Supplementary probes for the task-named vectors
(prompt quotes/newlines, CRLF, concurrent-loop log collision) found no new
defect.

One MINOR finding recorded — **BUG-RL2 (malformed-YAML traceback leak)**:
when the profile YAML is syntactically broken, `ai-review-loop.sh` runs
`yaml_get_list` directly (line 51) without first calling the round-1
`yaml_parses` guard, so a raw multi-line PyYAML traceback (yq error under
the yq backend) is dumped to stderr; the loop then silently degrades to the
default `claude` agent and exits 0. Functionally safe (no crash, no wrong
verdict, loop-safety intact) but a diagnostics/silent-misconfiguration gap:
the round-1 commit added `yaml_parses` precisely to replace raw tracebacks
with clean remediation messages in `validate-profile`/`get-pr-comments`, and
`ai-review-loop.sh` is reachable standalone (`code-review/SKILL.md`,
`make ai-review-loop`) without a preceding `validate-profile` step.

Observation (not a defect): RL2-12 trailing-garbage stdout is
backend-divergent — jq salvages `.result` from the leading object (exit 0, 1
call) while python3's `json.load` rejects "Extra data" and takes the
transport retry (exit 1, 2 calls). The round-1 plan explicitly accepted
either outcome for RL2-12, and neither path silently passes a FAIL, so this
is logged as a documented backend ambiguity rather than a bug.

## Round 3

Date: 2026-06-13. Goal: prove the round-2 fixes HOLD against the post-fix
tree (commit `180a282`) and hunt for any remaining or fix-introduced defect.
Prior rounds fixed 23 bugs total; the documented pattern is that ~half of
each round's "fixes" regress, so every repro below was re-run for real (twice)
and judged on observed behavior, NOT on commit messages.

The two round-2 findings that landed code changes in `ai-review-loop.sh`:

- **R2 Bug 2 (uint64 loop wrap)**: a `--max-iterations` value that survives
  the `^[1-9][0-9]*$` regex but exceeds a sane bound would wrap modulo 2^64
  in the C-style loop. Fixed at lines 40-54 with a `MAX_ITERATIONS_CEILING`
  of 1000 enforced by the wrap-safe `num_gt` digit-string compare.
- **BUG-RL2 (malformed-YAML traceback leak / silent degrade)**: the profile
  read now runs `yaml_parses` (lines 72-73) before `yaml_get_list`, so a
  broken profile dies with one clean `[php-sdlc]` diagnostic naming the file
  instead of dumping a raw traceback and silently degrading to the default
  `claude` agent.

Sandbox: `/tmp/sdlc-test3-review-loop/` (fresh, deleted after the round).
Harness: copied static fixture stub + a `seqgen.sh`-generated sequenced stub
with an argv call log (same pattern as the bats `seq_claude` helper).
Backend on this host: `jq` PRESENT, `yq` ABSENT (so all YAML access takes the
python3+PyYAML fallback unless `SDLC_FORCE_PYTHON_YAML` is explicit). The full
`bats tests/ai-review-loop.bats` (23 tests) and `tests/common-lib.bats` (28
tests) suites were also run twice — all green both times.

### Round-3 key-fix verification (R2 Bug 2 — `--max-iterations` ceiling)

| ID | Case | Setup / command | Expected | Result |
| --- | --- | --- | --- | --- |
| RL3-C01 | ceiling control: 1000 accepted | `--max-iterations 1000`, `PASS_JSON` | exit 0; `iteration 1/1000`; PASS on iteration 1 | PASS |
| RL3-C02 | just over ceiling: 1001 rejected | `--max-iterations 1001` | exit 1; `must not exceed 1000`; 0 calls | PASS |
| RL3-C03 | 18-digit (`999999999999999999`) | over ceiling | exit 1; `must not exceed 1000` | PASS |
| RL3-C04 | 19-digit (`9999999999999999999`) | over ceiling | exit 1; `must not exceed 1000` | PASS |
| RL3-C05 | 22-digit (`9999999999999999999999`) | regex-valid, would wrap to ~1.8e18 | exit 1; `must not exceed 1000` | PASS |
| RL3-C06 | 2^63 (`9223372036854775808`) | would wrap NEGATIVE → 0 iterations | exit 1; `must not exceed 1000` | PASS |
| RL3-C07 | 2^64 (`18446744073709551616`) | would wrap to 0 → 0 iterations | exit 1; `must not exceed 1000` | PASS |
| RL3-C08 | 2^64+1 (`18446744073709551617`) | would wrap to 1 → 1 iteration | exit 1; `must not exceed 1000` | PASS |
| RL3-C09 | `--max-iterations 0` / `-1` / `1.5` | sub-ceiling invalids | exit 1; `must be a positive integer`; 0 calls | PASS |
| RL3-C10 | leading-zero `007` / `0001000` | regex rejects leading zero before ceiling | exit 1; `must be a positive integer` | PASS |
| RL3-C11 | `num_gt` unit probe | direct source of `common.sh`; 8 boundary pairs | all 8 match expected (equal, length, lexicographic, 2^64) | PASS |
| RL3-C12 | ordering: bad ceiling + all-skip agents | `--agents codex --max-iterations 99…99` | exit 1; ceiling die fires first (validation-before-resolution) | PASS |

### Round-3 key-fix verification (BUG-RL2 — malformed-YAML guard)

| ID | Case | Setup / command | Expected | Result |
| --- | --- | --- | --- | --- |
| RL3-Y01 | broken list + stray colons (python3) | `[unclosed` + `broken: : :`; no `--agents` | exit 1; `profile is not valid YAML`; 0 calls; no traceback; no silent PASS | PASS |
| RL3-Y02 | same, forced python3 backend | `SDLC_FORCE_PYTHON_YAML=1` | exit 1; clean diag; 0 calls; no traceback | PASS |
| RL3-Y03 | pure unclosed bracket `[a, b` | malformed | exit 1; clean diag; 0 calls | PASS |
| RL3-Y04 | tab-indented mapping (YAML forbids tabs) | malformed | exit 1; clean diag; 0 calls | PASS |
| RL3-Y05 | diagnostic content | malformed profile | message names the file path AND gives remediation (`/sdlc-setup`, `--agents`) | PASS |
| RL3-Y06 | control: duplicate key (valid for safe_load) | `ai_review_agents` twice | exit 0; parses; 1 call (guard does NOT over-reject) | PASS |
| RL3-Y07 | control: empty file | `.claude/php-sdlc.yml` empty | exit 0; defaults to claude; 1 call | PASS |
| RL3-Y08 | control: valid claude list | `[claude]` | exit 0; 1 call | PASS |
| RL3-Y09 | control: valid, no review key | unrelated keys only | exit 0; defaults to claude; 1 call | PASS |
| RL3-Y10 | control: valid `[codex, claude]` | matrix | exit 0; codex skip; claude PASS; 1 call | PASS |
| RL3-Y11 | control: scalar agent / empty list | `ai_review_agents: claude` and `[]` | exit 0; default-claude; 1 call each | PASS |

### Round-3 verdict / is_error / prompt vectors

| ID | Case | Setup / command | Expected | Result |
| --- | --- | --- | --- | --- |
| RL3-V01 | clean PASS (control) | `ok\nAI_REVIEW_VERDICT: PASS`; max 1 | exit 0; PASS; 1 call | PASS |
| RL3-V02 | CRLF result, CR after verdict | `ok\r\nAI_REVIEW_VERDICT: PASS\r`; max 1 | exit 1; contract warn; no retry; 1 call; never silent pass | PASS |
| RL3-V03 | CR only after verdict line | `…PASS\r`; max 1 | exit 1; contract warn; 1 call | PASS |
| RL3-V04 | trailing space after PASS | verdict line is `…PASS` + one trailing space; max 1 | exit 1; contract warn; 1 call | PASS |
| RL3-V05 | leading space / tab before token | one space or tab prefixes `AI_REVIEW_VERDICT: PASS`; max 1 | exit 1; contract warn; 1 call | PASS |
| RL3-V06 | missing space after colon | `AI_REVIEW_VERDICT:PASS`; max 1 | exit 1; contract warn; 1 call | PASS |
| RL3-V07 | trailing blank lines after verdict | `…PASS\n\n\n`; max 1 | exit 0; awk NF picks last non-empty line; PASS; 1 call | PASS |
| RL3-V08 | PASS mid-text, FAIL last line | two verdicts; max 1 | exit 1; last line wins → FAIL path; NO contract warn; 1 call | PASS |
| RL3-V09 | lowercase `pass` | `…VERDICT: pass`; max 1 | exit 1; case-sensitive contract; warn; 1 call | PASS |
| RL3-V10 | `.result` null / empty / number 42 | three transport/contract shapes; max 1 | null+empty → transport retry (2 calls); 42 → contract no-retry (1 call); all exit 1 | PASS |
| RL3-E01 | is_error:true bool | `{"is_error":true,…}`; max 1 | exit 1; is_error warn; one retry; 2 calls; no contract log | PASS |
| RL3-E02 | is_error:false bool | `{"is_error":false,…PASS}`; max 1 | exit 0; verdict parsed; no is_error warn; 1 call | PASS |
| RL3-E03 | is_error string `"true"` | strict bool compare; max 1 | exit 0; NOT a transport error; verdict parsed; 1 call | PASS |
| RL3-E04 | is_error number `1` | not `=== true`; max 1 | exit 0; verdict parsed; 1 call | PASS |
| RL3-E05 | is_error:true WITH a PASS body | transport wins over verdict; max 1 | exit 1; retry; 2 calls (PASS body NOT honored) | PASS |
| RL3-E06 | is_error parity, jq ABSENT | restricted PATH (no jq); 3 shapes | python3 fallback matches jq results exactly | PASS |
| RL3-P01 | `REVIEW_PROMPT` cmd-subst payload | `$(touch HACKED) \`touch HACKED2\` ; rm -rf x` | exit 0; NO file created; payload verbatim as one argv | PASS |
| RL3-P02 | prompt `$(touch /tmp/…/PWNED)` | abs-path cmd-subst | no file created; verbatim argv | PASS |
| RL3-P03 | prompt with `"`/`'`/`$VAR`/pipe/redirect/backtick/glob | 7 metachar payloads | exit 0; zero expansion; zero file creation; verbatim each | PASS |
| RL3-P04 | multi-line `REVIEW_PROMPT` w/ embedded `$(touch ML_HACK)` | 3-line env value | newlines reach claude argv; NO file created | PASS |
| RL3-P05 | empty `REVIEW_PROMPT` | `REVIEW_PROMPT=` | falls back to default `Review the working tree` prompt; exit 0 | PASS |

### Round-3 regression re-runs (highest-risk prior cases)

| ID | Case | Result |
| --- | --- | --- |
| RL-P02 | FAIL then PASS (2 calls) | PASS |
| RL-N01 | perpetual FAIL hits default cap 5 (NFR-6) | PASS |
| RL-P03 | PASS exactly at boundary (iter 3) | PASS |
| RL2-04/06 | malformed JSON 1-retry; garbage-then-PASS recover | PASS |
| RL-E01 | is_error-then-PASS on retry | PASS |
| RL-E03 | mixed FAIL/missing-verdict/PASS over 3 iters | PASS |
| RL2-07 | `.result` null → transport retry | PASS |
| RL-N08 | empty result string → transport retry | PASS |
| RL-E06 | `.result` number 42 → contract no-retry | PASS |
| RL-N12/N13 | all-skip matrix (`codex`, `gemini,codex`) → no-agent fail | PASS |
| RL-P09/E09 | `--agents codex,claude` / `claude,claude` (dup) | PASS |
| RL2-11 | `--agents "codex, claude"` separators; empty tokens dropped | PASS |
| RL-N14/N15 | unknown flag; `--agents`/`--max-iterations` without value | PASS |
| RL-N16 | claude CLI absent from PATH | PASS |

### Round-3 verdict

**Cases run: 62** (12 ceiling + 11 YAML-guard + 24 verdict/is_error/prompt +
15 regression re-runs), plus the 23-test bats suite and 28-test common-lib
suite, every one executed at least twice with identical results.

**Prior fails re-checked: 2** (R2 Bug 2 ceiling, BUG-RL2 malformed-YAML guard
— the only two round-2 findings that produced code changes in this surface).
**Prior fails now passing: 2.** Both HOLD: the `MAX_ITERATIONS_CEILING`
`num_gt` guard rejects every 19+ digit / 2^63 / 2^64 / 2^64-multiple value
with `must not exceed 1000` and zero claude calls; the `yaml_parses` guard
fail-closes every malformed profile with one clean diagnostic, 0 calls, no
traceback leak, and no silent degrade to `claude` — on BOTH backends. The
round-2 BUG-RL2 is fully resolved (it was a MINOR diagnostics gap, now closed)
and did not regress.

**No new or fix-introduced defects found.** The ceiling check is wrap-safe
(digit-string compare, never bash arithmetic), validation fires before agent
resolution, and the new `yaml_parses` guard does not over-reject any valid
profile (duplicate-key, empty file, scalar agent, empty list, no-review-key
all still resolve correctly). Verdict matching remains strictly fail-closed on
CRLF/whitespace/format variants; is_error is a strict bool compare with jq /
python3 parity; `REVIEW_PROMPT` is passed verbatim as one argv with zero shell
expansion across all 12 metacharacter payloads. Zero S1–S4 defects on this
surface in round 3.
