#!/usr/bin/env bats
# Tests for scripts/validate-profile.sh (Story 1.4, FR-17/FR-18).
#
# One bats case per violation class from the story AC: missing key, bad
# enum, lowered threshold, wrong schema_version, incomplete make map —
# each must exit 1 with a violation line NAMING the offending key, so
# /sdlc-setup can surface actionable errors. The valid fixture mirrors
# the canonical example profile from architecture §4.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  VALIDATOR="$PLUGIN_ROOT/scripts/validate-profile.sh"
  PROFILES="$BATS_TEST_DIRNAME/fixtures/profiles"
}

@test "valid profile: exit 0, no violation lines" {
  run "$VALIDATOR" "$PROFILES/valid.yml"
  [ "$status" -eq 0 ]
  [[ "$output" != *VIOLATION* ]]
  [[ "$output" == *"profile valid"* ]]
}

@test "valid profile under forced python fallback: exit 0 (ADR-2)" {
  SDLC_FORCE_PYTHON_YAML=1 run "$VALIDATOR" "$PROFILES/valid.yml"
  [ "$status" -eq 0 ]
  [[ "$output" != *VIOLATION* ]]
}

@test "missing required key: exit 1, names php.version" {
  run "$VALIDATOR" "$PROFILES/missing-key.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: required key 'php.version' missing or null"* ]]
}

@test "bad enum: exit 1, names persistence.mapper and the bad value" {
  run "$VALIDATOR" "$PROFILES/bad-enum.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'persistence.mapper' value 'eloquent'"* ]]
  [[ "$output" == *doctrine-orm* ]]
}

@test "lowered threshold: exit 1, names the quality key (ADR-7)" {
  run "$VALIDATOR" "$PROFILES/lowered-threshold.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'quality.phpinsights.complexity' value 90 lowered below shipped default 94"* ]]
}

@test "wrong schema_version: exit 1, names schema_version" {
  run "$VALIDATOR" "$PROFILES/wrong-schema-version.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'schema_version' value '2' unsupported"* ]]
}

@test "incomplete make map: exit 1, names make.infection" {
  run "$VALIDATOR" "$PROFILES/incomplete-make.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: make map incomplete: 'make.infection' not declared"* ]]
}

@test "all violations reported, not just the first" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/multi.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['php'].pop('version')
p['persistence']['engine'] = 'oracle'
p['quality']['psalm_errors'] = 5
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/multi.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'php.version' missing"* ]]
  [[ "$output" == *"'persistence.engine' value 'oracle'"* ]]
  [[ "$output" == *"'quality.psalm_errors' value 5 relaxed above shipped default 0"* ]]
  [[ "$output" == *"3 violation(s)"* ]]
}

@test "null ci.provider is legal (declared, NFR-4 degrade) but undeclared is not" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/null-ci.yml" "$BATS_TEST_TMPDIR/no-ci.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['ci']['provider'] = None
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
p['ci'].pop('provider')
yaml.safe_dump(p, open(sys.argv[3], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/null-ci.yml"
  [ "$status" -eq 0 ]
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/no-ci.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: required key 'ci.provider' not declared"* ]]
}

@test "empty bounded_contexts: exit 1" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/no-contexts.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['architecture']['bounded_contexts'] = []
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/no-contexts.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'architecture.bounded_contexts' must list at least one"* ]]
}

@test "scalar bounded_contexts (not a list): exit 1" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/scalar-contexts.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['architecture']['bounded_contexts'] = 'Catalog'
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/scalar-contexts.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'architecture.bounded_contexts' must be a list"* ]]
}

@test "non-integer quality value: exit 1, named" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/garbage.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['quality']['infection_msi'] = 'high'
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/garbage.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'quality.infection_msi' value 'high' is not an integer"* ]]
}

@test "raised thresholds above defaults are accepted (raise-only, ADR-7)" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/raised.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['quality']['phpinsights']['complexity'] = 100
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/raised.yml"
  [ "$status" -eq 0 ]
}

@test "uint64-wrap ceiling value (2^64-1) is rejected, never wrapped negative (ADR-7, VP-E7)" {
  # 18446744073709551615 wraps to -1 in bash 64-bit arithmetic; a wrapped
  # comparison would let a crafted huge value defeat the raise-only gate.
  sed 's/^  psalm_errors:.*/  psalm_errors: 18446744073709551615/' \
    "$PROFILES/valid.yml" > "$BATS_TEST_TMPDIR/wrap.yml"
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/wrap.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'quality.psalm_errors' value 18446744073709551615 relaxed above shipped default 0"* ]]
}

@test "huge raised score threshold (>2^63) is still accepted as a raise (ADR-7)" {
  # The wrap-safe comparison must not over-reject: an absurdly raised
  # floor value is a (pointless but legal) raise, not a violation.
  sed 's/^  infection_msi:.*/  infection_msi: 18446744073709551615/' \
    "$PROFILES/valid.yml" > "$BATS_TEST_TMPDIR/huge-raise.yml"
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/huge-raise.yml"
  [ "$status" -eq 0 ]
  [[ "$output" != *VIOLATION* ]]
}

@test "malformed YAML profile: clean [php-sdlc] diagnostic, no backend traceback" {
  # Tab indentation is illegal YAML; without the up-front parse guard the
  # first yaml_get dies via set -e with a raw PyYAML/yq parse error.
  printf 'project:\n\tname: "x"\n' > "$BATS_TEST_TMPDIR/tabs.yml"
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/tabs.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[php-sdlc][ERROR] profile is not valid YAML"* ]]
  [[ "$output" == *"$BATS_TEST_TMPDIR/tabs.yml"* ]]
  [[ "$output" == *"/sdlc-setup"* ]]
  [[ "$output" != *Traceback* ]]
  [[ "$output" != *"yaml.scanner"* ]]
}

@test "malformed YAML (unclosed quote): same clean diagnostic" {
  printf 'a: "unclosed\n' > "$BATS_TEST_TMPDIR/unclosed.yml"
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/unclosed.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile is not valid YAML"* ]]
  [[ "$output" != *Traceback* ]]
}

@test "no-arg invocation resolves <cwd>/.claude/php-sdlc.yml" {
  mkdir -p "$BATS_TEST_TMPDIR/repo/.claude"
  cp "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/repo/.claude/php-sdlc.yml"
  cd "$BATS_TEST_TMPDIR/repo"
  run "$VALIDATOR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile valid"* ]]
}

@test "missing profile file: exit 1 with remediation hint" {
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/absent.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile not found"* ]]
  [[ "$output" == *"/sdlc-setup"* ]]
}
