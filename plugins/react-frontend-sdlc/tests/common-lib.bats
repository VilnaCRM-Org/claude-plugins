#!/usr/bin/env bats
# Smoke tests for scripts/lib/common.sh (react-frontend-sdlc).
#
# Exercises every pure helper in the library, including the python3+PyYAML
# fallback (ADR-2). SDLC_FORCE_PYTHON_YAML=1 disables yq detection, which
# runs the exact code path taken when yq is absent — this keeps the fallback
# testable on CI runners where yq is preinstalled. This host has no yq, so
# the python fallback is also the default backend.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LIB="$PLUGIN_ROOT/scripts/lib/common.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  VALID_PROFILE="$FIXTURES/profiles/valid.yml"
  # shellcheck source=../scripts/lib/common.sh
  source "$LIB"
}

# --- sourcing contract --------------------------------------------------

@test "refuses direct execution with exit 64" {
  run bash "$LIB"
  [ "$status" -eq 64 ]
  [[ "$output" == *"source it instead"* ]]
}

# --- logging ------------------------------------------------------------

@test "log_info writes tagged line to stdout" {
  run log_info "hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "[react-sdlc][INFO] hello world" ]
}

@test "log_error and log_warn write to stderr, not stdout" {
  run bash -c "source '$LIB'
    log_error boom 2>'$BATS_TEST_TMPDIR/err' >'$BATS_TEST_TMPDIR/out'
    log_warn careful 2>>'$BATS_TEST_TMPDIR/err' >>'$BATS_TEST_TMPDIR/out'"
  [ "$status" -eq 0 ]
  grep -q 'react-sdlc\]\[ERROR\] boom' "$BATS_TEST_TMPDIR/err"
  grep -q 'react-sdlc\]\[WARN\] careful' "$BATS_TEST_TMPDIR/err"
  [ ! -s "$BATS_TEST_TMPDIR/out" ]
}

@test "die exits 1 with message on stderr" {
  run bash -c "source '$LIB'; die 'fatal reason'; echo unreachable"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fatal reason"* ]]
  [[ "$output" != *unreachable* ]]
}

# --- wrap-safe integer helpers (ADR-7) -----------------------------------

@test "strip_zeros drops leading zeros, keeps a lone zero" {
  run strip_zeros 007
  [ "$output" = "7" ]
  run strip_zeros 000
  [ "$output" = "0" ]
  run strip_zeros 42
  [ "$output" = "42" ]
}

@test "num_gt is wrap-safe across magnitudes incl. 20+ digits" {
  # 2^64-1 (20 digits) reads as -1 under bash (( )); digit-string compare wins.
  run num_gt 18446744073709551615 1
  [ "$status" -eq 0 ]
  # 2^64 (21 digits) reads as 0 under (( )); still greater than 0.
  run num_gt 18446744073709551616 0
  [ "$status" -eq 0 ]
  # equal length -> lexicographic on digit strings.
  run num_gt 99999999999999999999 99999999999999999998
  [ "$status" -eq 0 ]
  # not greater when equal, and not greater when smaller.
  run num_gt 5 5
  [ "$status" -ne 0 ]
  run num_gt 1 18446744073709551615
  [ "$status" -ne 0 ]
}

@test "num_lt mirrors num_gt with arguments swapped" {
  run num_lt 1 18446744073709551615
  [ "$status" -eq 0 ]
  run num_lt 18446744073709551615 1
  [ "$status" -ne 0 ]
  run num_lt 7 7
  [ "$status" -ne 0 ]
}

@test "num_add is wrap-safe and rejects non-digit input" {
  run num_add 2 3
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
  # leading zeros are stripped before summing.
  run num_add 007 003
  [ "$output" = "10" ]
  # 19 nines + 1 carries into a 20-digit result without wrapping.
  run num_add 9999999999999999999 1
  [ "$output" = "10000000000000000000" ]
  # 2^64-1 + 1 would wrap to 0 under bash (( )); column addition keeps it exact.
  run num_add 18446744073709551615 1
  [ "$output" = "18446744073709551616" ]
  # non-digit operand -> '0' and a non-zero return.
  run num_add abc 5
  [ "$status" -ne 0 ]
  [ "$output" = "0" ]
}

@test "lower lowercases ASCII" {
  run lower "AbC-VilnaCRM"
  [ "$output" = "abc-vilnacrm" ]
}

# --- resolve_plugin_root (ADR-4) -----------------------------------------

@test "resolve_plugin_root honors CLAUDE_PLUGIN_ROOT" {
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" run resolve_plugin_root
  [ "$status" -eq 0 ]
  [ "$output" = "$PLUGIN_ROOT" ]
}

@test "resolve_plugin_root dies on missing CLAUDE_PLUGIN_ROOT dir" {
  CLAUDE_PLUGIN_ROOT="/nonexistent/path-$$" run resolve_plugin_root
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing directory"* ]]
}

@test "resolve_plugin_root derives root from lib location when unset" {
  unset CLAUDE_PLUGIN_ROOT
  run resolve_plugin_root
  [ "$status" -eq 0 ]
  [ "$output" = "$PLUGIN_ROOT" ]
}

# --- YAML toolchain (ADR-2) ----------------------------------------------

@test "require_yaml_toolchain passes when a backend exists" {
  run require_yaml_toolchain
  [ "$status" -eq 0 ]
}

@test "yaml_get reads a scalar" {
  run yaml_get "$VALID_PROFILE" framework.ui
  [ "$status" -eq 0 ]
  [ "$output" = "react-mui" ]
}

@test "yaml_get python fallback returns identical scalar" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$VALID_PROFILE" framework.ui
  [ "$status" -eq 0 ]
  [ "$output" = "react-mui" ]
}

@test "yaml_get python fallback normalizes booleans" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$VALID_PROFILE" capabilities.visual_testing
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  # explicit false must survive (not collapse to '').
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$VALID_PROFILE" capabilities.figma
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "yaml_get returns empty for absent key and for null value" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$VALID_PROFILE" no.such.key
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$VALID_PROFILE" make.ai_review_loop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "yaml_get dies on missing file" {
  run yaml_get "$BATS_TEST_TMPDIR/absent.yml" some.key
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such file"* ]]
}

@test "yaml_get_list prints one item per line" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get_list "$VALID_PROFILE" architecture.modules
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "alpha" ]
  [ "${lines[1]}" = "beta" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "yaml_is_list is true only for sequences, false for scalars/absent" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_is_list "$VALID_PROFILE" architecture.modules
  [ "$status" -eq 0 ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_is_list "$VALID_PROFILE" framework.ui
  [ "$status" -eq 1 ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_is_list "$VALID_PROFILE" architecture.missing_key
  [ "$status" -eq 1 ]
}

@test "yaml_has distinguishes explicit null from undeclared (NFR-4)" {
  # explicit null is declared.
  SDLC_FORCE_PYTHON_YAML=1 run yaml_has "$VALID_PROFILE" make.ai_review_loop
  [ "$status" -eq 0 ]
  # a target that valid.yml declares but incomplete-make.yml omits.
  SDLC_FORCE_PYTHON_YAML=1 run yaml_has "$VALID_PROFILE" make.test_e2e
  [ "$status" -eq 0 ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_has "$FIXTURES/profiles/incomplete-make.yml" make.test_e2e
  [ "$status" -eq 1 ]
  # top-level key.
  SDLC_FORCE_PYTHON_YAML=1 run yaml_has "$VALID_PROFILE" schema_version
  [ "$status" -eq 0 ]
}

# When yq IS available, both backends must agree (skipped where yq absent).
@test "yq and python backends agree on scalars, bools, and has()" {
  if ! command -v yq >/dev/null 2>&1; then
    skip "yq not installed here; python fallback is the active backend"
  fi
  # capabilities.figma is explicitly false and make.ai_review_loop is
  # explicitly null: keep falsy values in this loop to catch any backend
  # divergence (yq's `// ""` operator would otherwise swallow false).
  for key in framework.ui capabilities.visual_testing framework.state \
             quality.mutation_msi capabilities.figma make.ai_review_loop; do
    yq_val="$(yaml_get "$VALID_PROFILE" "$key")"
    py_val="$(SDLC_FORCE_PYTHON_YAML=1 yaml_get "$VALID_PROFILE" "$key")"
    [ "$yq_val" = "$py_val" ]
  done
  [ "$(yaml_get "$VALID_PROFILE" capabilities.figma)" = "false" ]
  yaml_has "$VALID_PROFILE" make.ai_review_loop
  ! yaml_has "$FIXTURES/profiles/incomplete-make.yml" make.test_e2e
}

# --- claude -p JSON driver (ADR-8, shared by ai-review-loop + fr-nfr-gate) -

@test "claude_extract_result pulls .result, empty on malformed or absent" {
  run claude_extract_result '{"result":"hello\nAI_REVIEW_VERDICT: PASS","is_error":false}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  run claude_extract_result 'not json at all'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run claude_extract_result '{"is_error":false}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "claude_is_error true only when .is_error == true" {
  run claude_is_error '{"is_error":true,"result":"API Error"}'
  [ "$status" -eq 0 ]
  run claude_is_error '{"is_error":false,"result":"ok"}'
  [ "$status" -ne 0 ]
  run claude_is_error '{"result":"ok"}'
  [ "$status" -ne 0 ]
  run claude_is_error 'garbage'
  [ "$status" -ne 0 ]
}

@test "claude_run_once returns 1 on is_error, non-zero exit, and malformed JSON" {
  local bin="$BATS_TEST_TMPDIR/claude-bin"
  mkdir -p "$bin"
  ln -sf "$FIXTURES/bin/claude" "$bin/claude"
  PATH="$bin:$PATH"
  # is_error=true, exit 0 -> transport failure
  STUB_CLAUDE_OUTPUT='{"is_error":true,"result":"API Error"}' run claude_run_once "prompt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is_error"* ]]
  # non-zero exit -> transport failure
  STUB_CLAUDE_OUTPUT='{"result":"x"}' STUB_CLAUDE_EXIT=2 run claude_run_once "prompt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-zero"* ]]
  # malformed JSON (no .result) -> transport failure
  STUB_CLAUDE_OUTPUT='no result here' run claude_run_once "prompt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed JSON"* ]]
  # clean result -> success, prints .result
  STUB_CLAUDE_OUTPUT='{"is_error":false,"result":"reviewed"}' run claude_run_once "prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reviewed"* ]]
}

# --- profile helpers ------------------------------------------------------

@test "profile_path defaults to PWD and accepts explicit repo dir" {
  cd "$BATS_TEST_TMPDIR"
  run profile_path
  [ "$output" = "$BATS_TEST_TMPDIR/.claude/react-sdlc.yml" ]
  run profile_path /some/repo
  [ "$output" = "/some/repo/.claude/react-sdlc.yml" ]
}

@test "profile_get returns value, or default when key absent" {
  run profile_get "$VALID_PROFILE" framework.state
  [ "$output" = "zustand" ]
  run profile_get "$VALID_PROFILE" no.such.key fallback-value
  [ "$output" = "fallback-value" ]
}

@test "profile_require returns value for present key" {
  run profile_require "$VALID_PROFILE" framework.ui
  [ "$status" -eq 0 ]
  [ "$output" = "react-mui" ]
}

@test "profile_require dies naming the missing key" {
  run profile_require "$VALID_PROFILE" project.owner_team
  [ "$status" -eq 1 ]
  [[ "$output" == *"project.owner_team"* ]]
}

# --- sample profile fixtures ----------------------------------------------

@test "fixture profiles: valid parses, invalid variants differ as labeled" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/valid.yml" schema_version
  [ "$output" = "1" ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/wrong-schema-version.yml" schema_version
  [ "$output" = "2" ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/missing-key.yml" framework.ui
  [ -z "$output" ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/lowered-threshold.yml" quality.coverage_statements
  [ "$output" = "90" ]
  SDLC_FORCE_PYTHON_YAML=1 run bash -c "source '$LIB'
    yaml_has '$FIXTURES/profiles/incomplete-make.yml' make.test_e2e && echo present || echo absent"
  [ "$output" = "absent" ]
}

# --- fixture stub binaries -------------------------------------------------

@test "stub claude: default and overridden version, exit code, call log" {
  run "$FIXTURES/bin/claude" --version
  [ "$status" -eq 0 ]
  [ "$output" = "2.1.0" ]
  STUB_CLAUDE_VERSION=1.0.9 run "$FIXTURES/bin/claude" --version
  [ "$output" = "1.0.9" ]
  STUB_CLAUDE_EXIT=3 run "$FIXTURES/bin/claude" -p "prompt"
  [ "$status" -eq 3 ]
  STUB_CLAUDE_LOG="$BATS_TEST_TMPDIR/calls.log" run "$FIXTURES/bin/claude" -p "hi"
  grep -q -- '-p hi' "$BATS_TEST_TMPDIR/calls.log"
}

@test "stub gh: version banner, auth status exit, canned output" {
  run "$FIXTURES/bin/gh" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "gh version 2.62.0 ("* ]]
  STUB_GH_AUTH_EXIT=1 run "$FIXTURES/bin/gh" auth status
  [ "$status" -eq 1 ]
  STUB_GH_OUTPUT='{"data":{}}' run "$FIXTURES/bin/gh" api graphql
  [ "$output" = '{"data":{}}' ]
}

@test "stub bmalph: version format and configurable exit" {
  run "$FIXTURES/bin/bmalph" --version
  [ "$status" -eq 0 ]
  [ "$output" = "bmalph 2.11.0" ]
  STUB_BMALPH_VERSION=2.10.0 run "$FIXTURES/bin/bmalph" --version
  [ "$output" = "bmalph 2.10.0" ]
  STUB_BMALPH_EXIT=7 run "$FIXTURES/bin/bmalph" run
  [ "$status" -eq 7 ]
}
