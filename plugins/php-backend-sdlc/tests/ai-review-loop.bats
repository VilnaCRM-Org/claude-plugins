#!/usr/bin/env bats
# Tests for scripts/ai-review-loop.sh (Story 2.4, ADR-8, NFR-6).
#
# Single-shot verdict cases use the Story 1.3 stub claude
# (STUB_CLAUDE_OUTPUT/_LOG). Sequenced cases (FAIL-then-PASS,
# retry-counting) need different output per call, which the static stub
# cannot do, so seq_claude writes a test-local claude wrapper that
# replays a list of canned responses and records every invocation.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LOOP="$PLUGIN_ROOT/scripts/ai-review-loop.sh"
  STUBS="$BATS_TEST_DIRNAME/fixtures/bin"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
  cd "$WORK"
  PATH="$STUBS:$PATH"
  CALLS="$BATS_TEST_TMPDIR/claude-calls.log"
}

# seq_claude RESPONSE... — claude wrapper that emits RESPONSE[n] on the
# n-th call (last response repeats) and logs each invocation's argv.
seq_claude() {
  local dir="$BATS_TEST_TMPDIR/seq-bin"
  mkdir -p "$dir"
  local script="$dir/claude"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "claude $*" >> %q\n' "$CALLS"
    printf 'n=$(cat %q 2>/dev/null || echo 0)\n' "$BATS_TEST_TMPDIR/count"
    printf 'n=$((n + 1)); echo "$n" > %q\n' "$BATS_TEST_TMPDIR/count"
    printf 'case "$n" in\n'
    local i=1
    for resp in "$@"; do
      if [ "$i" -lt "$#" ]; then
        printf '  %d) printf %%s\\\\n %q ;;\n' "$i" "$resp"
      else
        printf '  *) printf %%s\\\\n %q ;;\n' "$resp"
      fi
      i=$((i + 1))
    done
    printf 'esac\n'
  } >"$script"
  chmod +x "$script"
  PATH="$dir:$PATH"
}

# grep -c prints "0" AND exits 1 on zero matches, so a bare `|| echo 0`
# would double-print; branch on file existence instead.
calls_made() {
  if [ -f "$CALLS" ]; then
    grep -c '^claude ' "$CALLS" || true
  else
    echo 0
  fi
}

PASS_JSON='{"result":"all good\nAI_REVIEW_VERDICT: PASS"}'
FAIL_JSON='{"result":"found issues\nAI_REVIEW_VERDICT: FAIL"}'

@test "PASS on first iteration with stub claude only (FR-18 AC)" {
  STUB_CLAUDE_OUTPUT="$PASS_JSON" STUB_CLAUDE_LOG="$CALLS" run "$LOOP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"iteration 1/5"* ]]
  [[ "$output" == *"PASS on iteration 1"* ]]
  [[ "$output" == *"all good"* ]]
}

@test "claude invoked with the full ADR-8 flag set" {
  STUB_CLAUDE_OUTPUT="$PASS_JSON" STUB_CLAUDE_LOG="$CALLS" run "$LOOP"
  [ "$status" -eq 0 ]
  grep -q -- '--output-format json' "$CALLS"
  grep -q -- '--permission-mode acceptEdits' "$CALLS"
  grep -q -- '--max-turns 30' "$CALLS"
  grep -q -- '-p Review' "$CALLS"
}

@test "FAIL then PASS: exits 0 after exactly 2 iterations" {
  seq_claude "$FAIL_JSON" "$PASS_JSON"
  run "$LOOP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FAIL verdict"* ]]
  [[ "$output" == *"PASS on iteration 2"* ]]
  [ "$(calls_made)" -eq 2 ]
}

@test "perpetual FAIL: stops at 5 iterations, exit 1 (NFR-6)" {
  seq_claude "$FAIL_JSON"
  run "$LOOP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"iteration 5/5"* ]]
  [[ "$output" == *"no PASS within 5 iterations"* ]]
  [[ "$output" == *escalate* ]]
  [ "$(calls_made)" -eq 5 ]
}

@test "--max-iterations 2 caps the loop" {
  seq_claude "$FAIL_JSON"
  run "$LOOP" --max-iterations 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"no PASS within 2 iterations"* ]]
  [ "$(calls_made)" -eq 2 ]
}

@test "malformed JSON takes exactly one retry per iteration (architecture §8)" {
  seq_claude 'not json at all'
  run "$LOOP" --max-iterations 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed JSON"* ]]
  [[ "$output" == *"retrying once"* ]]
  [[ "$output" == *"retry failed too"* ]]
  # attempt + exactly one retry = 2 calls for the single iteration
  [ "$(calls_made)" -eq 2 ]
}

@test "malformed JSON recovers when the retry returns a verdict" {
  seq_claude 'garbage' "$PASS_JSON"
  run "$LOOP" --max-iterations 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"retrying once"* ]]
  [[ "$output" == *"PASS on iteration 1"* ]]
  [ "$(calls_made)" -eq 2 ]
}

@test "non-zero claude exit follows the same one-retry contract" {
  STUB_CLAUDE_OUTPUT="$PASS_JSON" STUB_CLAUDE_EXIT=2 STUB_CLAUDE_LOG="$CALLS" \
    run "$LOOP" --max-iterations 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude exited non-zero"* ]]
  [[ "$output" == *"retrying once"* ]]
  [ "$(calls_made)" -eq 2 ]
}

@test "missing verdict line: ADR-8 contract violation, failed iteration, NO retry" {
  STUB_CLAUDE_OUTPUT='{"result":"review text without any verdict"}' STUB_CLAUDE_LOG="$CALLS" \
    run "$LOOP" --max-iterations 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"AI_REVIEW_VERDICT"* ]]
  [[ "$output" == *"contract"* ]]
  [[ "$output" != *"retrying once"* ]]
  [ "$(calls_made)" -eq 1 ]
}

@test "is_error=true with exit 0 takes the one-retry transport path, no contract log" {
  # claude can exit 0 while reporting is_error=true with .result holding an
  # error string ('API Error: 529 Overloaded'). That is a transport
  # failure, not reviewer output: it must retry once (architecture §8), not
  # be misrouted to the no-retry 'AI_REVIEW_VERDICT contract' path.
  STUB_CLAUDE_OUTPUT='{"is_error":true,"result":"API Error: 529 Overloaded"}' \
    STUB_CLAUDE_LOG="$CALLS" run "$LOOP" --max-iterations 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"is_error"* ]]
  [[ "$output" == *"retrying once"* ]]
  [[ "$output" == *"retry failed too"* ]]
  # the error text must NOT be treated as a review verdict
  [[ "$output" != *"contract"* ]]
  # attempt + exactly one retry = 2 calls for the single iteration
  [ "$(calls_made)" -eq 2 ]
}

@test "is_error=true recovers when the retry returns a clean PASS" {
  seq_claude '{"is_error":true,"result":"API Error"}' "$PASS_JSON"
  run "$LOOP" --max-iterations 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"is_error"* ]]
  [[ "$output" == *"retrying once"* ]]
  [[ "$output" == *"PASS on iteration 1"* ]]
  [ "$(calls_made)" -eq 2 ]
}

@test "--agents codex: warns, skips, then FAILS (no supported agent ran)" {
  STUB_CLAUDE_LOG="$CALLS" run "$LOOP" --agents codex
  [ "$status" -ne 0 ]
  [[ "$output" == *"'codex' is not supported in v1"* ]]
  [[ "$output" == *"no supported review agent ran"* ]]
  [ "$(calls_made)" -eq 0 ]
}

@test "--agents codex,claude: skips codex, runs claude" {
  STUB_CLAUDE_OUTPUT="$PASS_JSON" STUB_CLAUDE_LOG="$CALLS" \
    run "$LOOP" --agents codex,claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"'codex' is not supported"* ]]
  [[ "$output" == *"PASS on iteration 1"* ]]
  [ "$(calls_made)" -eq 1 ]
}

@test "agents resolve from profile review.ai_review_agents when no --agents" {
  mkdir -p .claude
  printf 'review:\n  ai_review_agents: [gemini]\n' > .claude/php-sdlc.yml
  STUB_CLAUDE_LOG="$CALLS" run "$LOOP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"'gemini' is not supported in v1"* ]]
  [[ "$output" == *"no supported review agent ran"* ]]
  [ "$(calls_made)" -eq 0 ]
}

@test "--diff-base lands in the default review prompt" {
  STUB_CLAUDE_OUTPUT="$PASS_JSON" STUB_CLAUDE_LOG="$CALLS" \
    run "$LOOP" --diff-base origin/release
  [ "$status" -eq 0 ]
  grep -q 'origin/release' "$CALLS"
  [[ "$output" == *"diff base: origin/release"* ]]
}

@test "invalid --max-iterations: usage error" {
  run "$LOOP" --max-iterations zero
  [ "$status" -eq 1 ]
  [[ "$output" == *"--max-iterations must be a positive integer"* ]]
}

# --- R2 regression: max-iterations wrap, malformed-profile diagnostic ------

@test "R2 Bug 2: a 19+ digit --max-iterations is rejected (no uint64 loop wrap)" {
  # The ^[1-9][0-9]*$ regex accepts this 22-digit string; the C-style loop
  # would then wrap it modulo 2^64 to ~1.8 quintillion iterations.
  run "$LOOP" --agents claude --max-iterations 9999999999999999999999
  [ "$status" -eq 1 ]
  [[ "$output" == *"must not exceed 1000"* ]]
}

@test "R2 Bug 2: a 2^63 --max-iterations is rejected (would wrap negative, 0 iterations)" {
  run "$LOOP" --agents claude --max-iterations 9223372036854775808
  [ "$status" -eq 1 ]
  [[ "$output" == *"must not exceed 1000"* ]]
}

@test "R2 Bug 2 control: --max-iterations at the ceiling (1000) is accepted" {
  STUB_CLAUDE_OUTPUT="$PASS_JSON" STUB_CLAUDE_LOG="$CALLS" \
    run "$LOOP" --agents claude --max-iterations 1000
  [ "$status" -eq 0 ]
  [[ "$output" == *"iteration 1/1000"* ]]
  [[ "$output" == *"PASS on iteration 1"* ]]
}

@test "R2 Bug 2 control: --max-iterations just over the ceiling (1001) is rejected" {
  run "$LOOP" --agents claude --max-iterations 1001
  [ "$status" -eq 1 ]
  [[ "$output" == *"must not exceed 1000"* ]]
}

@test "R2 Bug 10: a malformed profile yields one clean diagnostic, no raw traceback" {
  # The profile read must be guarded by yaml_parses so a broken
  # .claude/php-sdlc.yml fails with a [php-sdlc] message naming the file
  # instead of dumping a PyYAML/yq traceback then silently degrading to
  # the default 'claude' agent.
  mkdir -p .claude
  printf 'review:\n  ai_review_agents: [unclosed\n  broken: : :\n' > .claude/php-sdlc.yml
  STUB_CLAUDE_LOG="$CALLS" run "$LOOP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile is not valid YAML"* ]]
  [[ "$output" == *".claude/php-sdlc.yml"* ]]
  [[ "$output" != *"Traceback"* ]]
  [[ "$output" != *"yaml.parser"* ]]
  [ "$(calls_made)" -eq 0 ]
}

@test "R2 Bug 10: forced python YAML backend also gives the clean diagnostic" {
  mkdir -p .claude
  printf 'review:\n  ai_review_agents: [unclosed\n  broken: : :\n' > .claude/php-sdlc.yml
  SDLC_FORCE_PYTHON_YAML=1 STUB_CLAUDE_LOG="$CALLS" run "$LOOP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile is not valid YAML"* ]]
  [[ "$output" != *"Traceback"* ]]
  [ "$(calls_made)" -eq 0 ]
}

@test "R2 Bug 10 control: --agents bypasses a broken profile (no profile read)" {
  mkdir -p .claude
  printf 'review:\n  ai_review_agents: [unclosed\n  broken: : :\n' > .claude/php-sdlc.yml
  STUB_CLAUDE_OUTPUT="$PASS_JSON" STUB_CLAUDE_LOG="$CALLS" \
    run "$LOOP" --agents claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS on iteration 1"* ]]
}
