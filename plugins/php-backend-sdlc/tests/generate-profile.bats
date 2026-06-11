#!/usr/bin/env bats
# Tests for scripts/generate-profile.sh (Story 2.2, FR-2, NFR-3, NFR-4).
#
# Each detection source gets a case (composer.json, Doctrine engine,
# Makefile map, src/ layout, workflows, .coderabbit.yaml), plus the two
# modes from NFR-3 (default diff-and-keep vs --refresh) and the A3 rule
# that missing capabilities yield null/false instead of errors. The
# stub repo is copied per-test because generation writes into it.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GENERATE="$PLUGIN_ROOT/scripts/generate-profile.sh"
  VALIDATE="$PLUGIN_ROOT/scripts/validate-profile.sh"
  LIB="$PLUGIN_ROOT/scripts/lib/common.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  cp -r "$BATS_TEST_DIRNAME/fixtures/stub-repo" "$REPO"
  PROFILE="$REPO/.claude/php-sdlc.yml"
  source "$LIB"
}

pget() { yaml_get "$PROFILE" "$1"; }

@test "stub repo: composer detection (php, framework, api_platform, graphql)" {
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile created"* ]]
  [ "$(pget php.version)" = "8.4" ]
  [ "$(pget framework.name)" = "symfony" ]
  [ "$(pget framework.version)" = "7.3" ]
  [ "$(pget framework.api_platform)" = "4.2" ]
  [ "$(pget framework.graphql)" = "true" ]
}

@test "stub repo: doctrine mapper/engine, src layout, coderabbit, project" {
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(pget persistence.mapper)" = "doctrine-odm" ]
  [ "$(pget persistence.engine)" = "mongodb" ]
  [ "$(pget architecture.source_root)" = "src" ]
  [ "$(pget architecture.shared_context)" = "Shared" ]
  run yaml_get_list "$PROFILE" architecture.bounded_contexts
  [[ "$output" == *Catalog* ]]
  [[ "$output" == *Order* ]]
  [ "$(pget review.coderabbit)" = "true" ]
  [ "$(pget project.name)" = "sample-api" ]
  [ "$(pget project.repo)" = "acme/sample-api" ]
}

@test "stub repo: Makefile map and workflow names detected" {
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(pget make.ci)" = "ci" ]
  [ "$(pget make.e2e)" = "e2e-tests" ]
  [ "$(pget make.load_tests)" = "load-tests" ]
  # not in stub Makefile -> null (reads back as empty scalar)
  [ -z "$(pget make.ai_review_loop)" ]
  [ "$(pget ci.provider)" = "github-actions" ]
  run yaml_get_list "$PROFILE" ci.workflows
  [[ "$output" == *tests* ]]
  [[ "$output" == *psalm* ]]
  [ "$(pget capabilities.load_testing)" = "true" ]
  [ "$(pget capabilities.structurizr)" = "false" ]
}

@test "generated profile passes validate-profile.sh (FR-17 AC)" {
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  run "$VALIDATE" "$PROFILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile valid"* ]]
}

@test "second run without --refresh: unchanged file, no diff noise (NFR-3)" {
  run "$GENERATE" "$REPO"
  before="$(cat "$PROFILE")"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile unchanged"* ]]
  [ "$(cat "$PROFILE")" = "$before" ]
}

@test "existing profile differs: default mode prints diff and keeps file (NFR-3)" {
  run "$GENERATE" "$REPO"
  # user-edited value the detector would not produce
  sed -i 's/complexity: 94/complexity: 97/' "$PROFILE"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept existing"* ]]
  [[ "$output" == *"--refresh"* ]]
  [[ "$output" =~ -[[:space:]]+complexity:\ 97 ]]
  [[ "$output" =~ \+[[:space:]]+complexity:\ 94 ]]
  # file untouched
  grep -q 'complexity: 97' "$PROFILE"
}

@test "--refresh overwrites the existing profile (NFR-3)" {
  run "$GENERATE" "$REPO"
  sed -i 's/complexity: 94/complexity: 97/' "$PROFILE"
  run "$GENERATE" --refresh "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile refreshed"* ]]
  grep -q 'complexity: 94' "$PROFILE"
}

@test "stripped Makefile: make keys become null, no failure (NFR-4 AC)" {
  rm "$REPO/Makefile"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  for key in ci start tests e2e psalm deptrac phpinsights infection load_tests; do
    [ -z "$(pget "make.$key")" ]
  done
  # keys are DECLARED null, not missing — validator must still accept the map
  run bash -c "source '$LIB'; yaml_has '$PROFILE' make.ci"
  [ "$status" -eq 0 ]
  [ "$(pget capabilities.load_testing)" = "false" ]
}

@test "Makefile without plain targets: make keys null, exit 0 (A3/NFR-4)" {
  # only .PHONY, a variable assignment, and a pattern rule — the
  # target-name grep matches nothing; generation must still succeed
  printf '.PHONY: all\nCC := gcc\n%%.o: %%.c\n\t$(CC) -c $<\n' > "$REPO/Makefile"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile created"* ]]
  for key in ci start tests e2e psalm deptrac phpinsights infection load_tests; do
    [ -z "$(pget "make.$key")" ]
  done
  [ "$(pget capabilities.load_testing)" = "false" ]
}

@test "empty repo: never errors, everything null/false (A3)" {
  EMPTY="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$EMPTY"
  run "$GENERATE" "$EMPTY"
  [ "$status" -eq 0 ]
  PROFILE="$EMPTY/.claude/php-sdlc.yml"
  [ -z "$(pget php.version)" ]
  [ -z "$(pget framework.name)" ]
  [ -z "$(pget persistence.mapper)" ]
  [ -z "$(pget ci.provider)" ]
  [ "$(pget framework.graphql)" = "false" ]
  [ "$(pget review.coderabbit)" = "false" ]
  [ "$(pget schema_version)" = "1" ]
}

@test "doctrine-orm with mysql driver config detected" {
  python3 - "$REPO/composer.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
req = data['require']
del req['doctrine/mongodb-odm-bundle']
req['doctrine/orm'] = '^3.0'
json.dump(data, open(path, 'w'), indent=2)
PYEOF
  mkdir -p "$REPO/config/packages"
  printf 'doctrine:\n  dbal:\n    driver: pdo_mysql\n' > "$REPO/config/packages/doctrine.yaml"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(pget persistence.mapper)" = "doctrine-orm" ]
  [ "$(pget persistence.engine)" = "mysql" ]
}

@test "git origin remote wins over composer name for project.repo" {
  git -C "$REPO" init -q
  git -C "$REPO" remote add origin git@github.com:acme/real-service.git
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(pget project.repo)" = "acme/real-service" ]
}

@test "workflow names with YAML special characters survive emission intact" {
  cat > "$REPO/.github/workflows/release.yml" <<'EOF'
name: "CI: build, test"
on: push
EOF
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  run yaml_get_list "$PROFILE" ci.workflows
  [ "$status" -eq 0 ]
  printf '%s\n' "${lines[@]}" | grep -qxF 'CI: build, test'
  run "$VALIDATE" "$PROFILE"
  [ "$status" -eq 0 ]
}

@test "composer name with quote/newline cannot inject profile keys (NFR-3)" {
  python3 - "$REPO/composer.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
data['name'] = 'acme/evil"\nmalicious: true'
json.dump(data, open(sys.argv[1], 'w'))
PYEOF
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$(pget malicious)" ]
  [ -z "$(pget project.malicious)" ]
  run "$VALIDATE" "$PROFILE"
  [ "$status" -eq 0 ]
}

@test "created profile honors the umask instead of mktemp's 0600" {
  umask 022
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$PROFILE")" = "644" ]
}

@test "--refresh preserves the existing profile's mode" {
  run "$GENERATE" "$REPO"
  chmod 664 "$PROFILE"
  sed -i 's/complexity: 94/complexity: 97/' "$PROFILE"
  run "$GENERATE" --refresh "$REPO"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$PROFILE")" = "664" ]
}

@test "symlinked .claude dir does not redirect the write outside the repo" {
  OUTSIDE="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$OUTSIDE"
  rm -rf "$REPO/.claude"
  ln -s "$OUTSIDE" "$REPO/.claude"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlink"* ]]
  # the write must NOT have leaked through the symlink into $OUTSIDE
  [ ! -e "$OUTSIDE/php-sdlc.yml" ]
}

@test "--refresh through a symlinked profile file does not clobber the target" {
  OUTSIDE="$BATS_TEST_TMPDIR/outside-file"
  mkdir -p "$OUTSIDE"
  printf 'precious: keep-me\n' > "$OUTSIDE/p.yml"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  rm -f "$PROFILE"
  ln -s "$OUTSIDE/p.yml" "$PROFILE"
  run "$GENERATE" --refresh "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlink"* ]]
  # the symlink target's prior contents survive
  grep -q 'precious: keep-me' "$OUTSIDE/p.yml"
}

@test "unknown flag: usage error" {
  run "$GENERATE" --bogus "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}
