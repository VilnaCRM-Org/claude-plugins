#!/usr/bin/env bats
# Smoke tests for scripts/lib/common.sh (Story 1.3, FR-18).
#
# Exercises every helper in the library, including the python3+PyYAML
# fallback (ADR-2). SDLC_FORCE_PYTHON_YAML=1 disables yq detection, which
# runs the exact code path taken when yq is absent — this keeps the
# fallback testable on CI runners where yq is preinstalled.

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
  [ "$output" = "[php-sdlc][INFO] hello world" ]
}

@test "log_error and log_warn write to stderr, not stdout" {
  run bash -c "source '$LIB'
    log_error boom 2>'$BATS_TEST_TMPDIR/err' >'$BATS_TEST_TMPDIR/out'
    log_warn careful 2>>'$BATS_TEST_TMPDIR/err' >>'$BATS_TEST_TMPDIR/out'"
  [ "$status" -eq 0 ]
  grep -q 'ERROR\] boom' "$BATS_TEST_TMPDIR/err"
  grep -q 'WARN\] careful' "$BATS_TEST_TMPDIR/err"
  [ ! -s "$BATS_TEST_TMPDIR/out" ]
}

@test "die exits 1 with message on stderr" {
  run bash -c "source '$LIB'; die 'fatal reason'; echo unreachable"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fatal reason"* ]]
  [[ "$output" != *unreachable* ]]
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
  run yaml_get "$VALID_PROFILE" php.version
  [ "$status" -eq 0 ]
  [ "$output" = "8.4" ]
}

@test "yaml_get python fallback returns identical scalar" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$VALID_PROFILE" php.version
  [ "$status" -eq 0 ]
  [ "$output" = "8.4" ]
}

@test "yaml_get python fallback normalizes booleans" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$VALID_PROFILE" framework.graphql
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
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
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get_list "$VALID_PROFILE" architecture.bounded_contexts
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Catalog" ]
  [ "${lines[1]}" = "Order" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "yaml_has distinguishes explicit null from undeclared (NFR-4)" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_has "$VALID_PROFILE" make.ai_review_loop
  [ "$status" -eq 0 ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_has "$VALID_PROFILE" make.undeclared_target
  [ "$status" -eq 1 ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_has "$VALID_PROFILE" schema_version
  [ "$status" -eq 0 ]
}

# When yq IS available, both backends must agree (skipped where yq absent).
@test "yq and python backends agree on scalars, bools, and has()" {
  if ! command -v yq >/dev/null 2>&1; then
    skip "yq not installed here; python fallback is the active backend"
  fi
  for key in php.version framework.graphql persistence.mapper quality.infection_msi; do
    yq_val="$(yaml_get "$VALID_PROFILE" "$key")"
    py_val="$(SDLC_FORCE_PYTHON_YAML=1 yaml_get "$VALID_PROFILE" "$key")"
    [ "$yq_val" = "$py_val" ]
  done
  yaml_has "$VALID_PROFILE" make.ai_review_loop
  ! yaml_has "$VALID_PROFILE" make.undeclared_target
}

# --- profile helpers ------------------------------------------------------

@test "profile_path defaults to PWD and accepts explicit repo dir" {
  cd "$BATS_TEST_TMPDIR"
  run profile_path
  [ "$output" = "$BATS_TEST_TMPDIR/.claude/php-sdlc.yml" ]
  run profile_path /some/repo
  [ "$output" = "/some/repo/.claude/php-sdlc.yml" ]
}

@test "profile_get returns value, or default when key absent" {
  run profile_get "$VALID_PROFILE" persistence.engine
  [ "$output" = "mongodb" ]
  run profile_get "$VALID_PROFILE" no.such.key fallback-value
  [ "$output" = "fallback-value" ]
}

@test "profile_require returns value for present key" {
  run profile_require "$VALID_PROFILE" framework.name
  [ "$status" -eq 0 ]
  [ "$output" = "symfony" ]
}

@test "profile_require dies naming the missing key" {
  run profile_require "$VALID_PROFILE" project.owner_team
  [ "$status" -eq 1 ]
  [[ "$output" == *"project.owner_team"* ]]
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

# --- sample profile fixtures (consumed by validate-profile.bats, E1-S4) ----

@test "fixture profiles: valid parses, invalid variants differ as labeled" {
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/valid.yml" schema_version
  [ "$output" = "1" ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/wrong-schema-version.yml" schema_version
  [ "$output" = "2" ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/missing-key.yml" php.version
  [ -z "$output" ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/bad-enum.yml" persistence.mapper
  [ "$output" = "eloquent" ]
  SDLC_FORCE_PYTHON_YAML=1 run yaml_get "$FIXTURES/profiles/lowered-threshold.yml" quality.phpinsights.complexity
  [ "$output" = "90" ]
  SDLC_FORCE_PYTHON_YAML=1 run bash -c "source '$LIB'
    yaml_has '$FIXTURES/profiles/incomplete-make.yml' make.infection && echo present || echo absent"
  [ "$output" = "absent" ]
}
