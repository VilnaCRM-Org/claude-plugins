#!/usr/bin/env bats
# Tests for scripts/validate-profile.sh (Story 1.4, FR-17).
#
# One bats case per violation class from the story AC: missing key,
# incomplete make map, lowered threshold, wrong schema_version, bad list
# type, raised ceiling, and the null-vs-undeclared ci.provider distinction —
# each must exit 1 with a violation line NAMING the offending key, so
# /fe-sdlc-setup can surface actionable errors. The valid fixture mirrors
# the canonical example profile from architecture §4. The frontend prefix is
# [react-sdlc] and the profile lives at .claude/react-sdlc.yml.

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
  [[ "$output" == *"profile valid"* ]]
}

@test "missing required key: exit 1, names framework.ui" {
  run "$VALIDATOR" "$PROFILES/missing-key.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: required key 'framework.ui' missing or null"* ]]
}

@test "incomplete make map: exit 1, names make.test_e2e" {
  run "$VALIDATOR" "$PROFILES/incomplete-make.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: make map incomplete: 'make.test_e2e' not declared"* ]]
}

@test "lowered threshold: exit 1, names the quality key (ADR-7)" {
  run "$VALIDATOR" "$PROFILES/lowered-threshold.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'quality.coverage_statements' value 90 lowered below shipped default 100"* ]]
}

@test "wrong schema_version: exit 1, names schema_version" {
  run "$VALIDATOR" "$PROFILES/wrong-schema-version.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'schema_version' value '2' unsupported"* ]]
}

@test "bad list type: exit 1, architecture.modules must be a list" {
  run "$VALIDATOR" "$PROFILES/bad-list.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'architecture.modules' must be a list"* ]]
}

@test "optional list keys: scalar rejected, absent and empty stay legal" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/scalar-lists.yml" "$BATS_TEST_TMPDIR/optional-lists-ok.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['architecture']['path_aliases'] = '@'
p['ci']['workflows'] = 'CI'
p['ci']['required_checks'] = 'static-testing'
p['review']['ai_review_agents'] = 'claude'
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
p = yaml.safe_load(open(sys.argv[1]))
p['architecture'].pop('path_aliases')
p['ci']['workflows'] = []
p['review'].pop('ai_review_agents')
yaml.safe_dump(p, open(sys.argv[3], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/scalar-lists.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'architecture.path_aliases' must be a list (sequence) when declared"* ]]
  [[ "$output" == *"VIOLATION: key 'ci.workflows' must be a list (sequence) when declared"* ]]
  [[ "$output" == *"VIOLATION: key 'ci.required_checks' must be a list (sequence) when declared"* ]]
  [[ "$output" == *"VIOLATION: key 'review.ai_review_agents' must be a list (sequence) when declared"* ]]
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/optional-lists-ok.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile valid"* ]]
}

@test "package_manager: out-of-contract value rejected, yarn stays legal" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/bad-pm.yml" "$BATS_TEST_TMPDIR/yarn-pm.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['framework']['package_manager'] = 'deno'
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
p = yaml.safe_load(open(sys.argv[1]))
p['framework']['package_manager'] = 'yarn'
yaml.safe_dump(p, open(sys.argv[3], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/bad-pm.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'framework.package_manager' value 'deno' not one of: bun npm pnpm yarn"* ]]
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/yarn-pm.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile valid"* ]]
}

@test "raised ceiling: exit 1, names eslint_errors relaxed above default (ADR-7)" {
  run "$VALIDATOR" "$PROFILES/raised-ceiling.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: key 'quality.eslint_errors' value 2 relaxed above shipped default 0"* ]]
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
  [[ "$output" == *"profile valid"* ]]
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/no-ci.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: required key 'ci.provider' not declared"* ]]
}

@test "all violations reported, not just the first" {
  python3 - "$PROFILES/valid.yml" "$BATS_TEST_TMPDIR/multi.yml" <<'PYEOF'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
p['framework'].pop('ui')
p['quality']['coverage_statements'] = 90
p['quality']['eslint_errors'] = 5
yaml.safe_dump(p, open(sys.argv[2], 'w'), sort_keys=False)
PYEOF
  run "$VALIDATOR" "$BATS_TEST_TMPDIR/multi.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"required key 'framework.ui' missing or null"* ]]
  [[ "$output" == *"'quality.coverage_statements' value 90 lowered below shipped default 100"* ]]
  [[ "$output" == *"'quality.eslint_errors' value 5 relaxed above shipped default 0"* ]]
  [[ "$output" == *"3 violation(s)"* ]]
}
