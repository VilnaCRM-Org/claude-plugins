#!/usr/bin/env bats
# validate-profile.bats — cases of scripts/validate-profile.sh (FR-5, FR-7;
# AC-5.1, AC-7.1, AC-7.2, AC-7.3; NFR-4, NFR-7, NFR-14).
#
# The golden profile tests/fixtures/profiles/golden.yml is what
# generate-profile.sh writes for the materialized stub repository at
# $BATS_TEST_TMPDIR/billing-service; every rejection case edits a copy of it
# under $BATS_TEST_TMPDIR (mutate_profile, drop_profile_key) so the case
# carries exactly the violations it names. The suite runs under both YAML
# backends (default, then SDLC_FORCE_PYTHON_YAML=1); the parity cases compare
# the two byte for byte inside one run.
#
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2030,SC2031 # bats cases are subshells

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  VALIDATE="$PLUGIN_ROOT/scripts/validate-profile.sh"
  PROFILES="$PLUGIN_ROOT/tests/fixtures/profiles"
  GOLDEN="$PROFILES/golden.yml"
  FIXTURE_REPO="$PLUGIN_ROOT/tests/fixtures/rust-repo"
  STUB="$BATS_TEST_TMPDIR/billing-service"
  # shellcheck source=../scripts/lib/common.sh
  source "$PLUGIN_ROOT/scripts/lib/common.sh"
}

teardown() {
  chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# The 115 schema keys in emission order (§ Project Profile Schema).
SCHEMA_KEYS=(schema_version project.name project.repo project.default_branch
  project.description rust.toolchain rust.edition rust.msrv
  template.repository template.sync_flavour template.source_commit
  framework.http framework.openapi framework.graphql persistence.engine
  persistence.migrations_dir persistence.offline_metadata
  architecture.crates_root architecture.composition_root architecture.layers
  architecture.bounded_contexts architecture.shared_crates service.port
  service.base_url service.liveness_path service.readiness_path
  service.graphql_path service.docs_path service.openapi_snapshot
  service.graphql_snapshot make.ci make.ci_list make.ci_preflight
  make.ci_static_analysis make.ci_tests make.ci_contracts make.ci_mutation
  make.ci_delivery make.ci_cli make.doctor make.bootstrap make.install_hooks
  make.bmalph_setup make.start make.format make.format_check make.lint_code
  make.static_analysis make.complexity make.architecture
  make.check_crate_isolation make.validate_architecture_model
  make.check_security make.unused_dependencies make.docs_check
  make.validate_invariants make.validate_configuration make.secrets_scan
  make.unit_tests make.integration_tests make.tests_with_coverage
  make.e2e_tests make.mutation_tests_diff make.setup_test_db
  make.create_migration make.migrate make.migrate_rollback make.sqlx_prepare
  make.validate_sqlx_metadata make.generate_openapi_spec
  make.generate_graphql_spec make.validate_contract_snapshots
  make.validate_openapi_spec make.openapi_diff make.graphql_diff
  make.schemathesis_validate make.image_scan make.smoke_load_tests
  make.load_tests make.new_context make.check_commit_message
  make.ai_review_loop make.pr_comments make.fr_nfr_gate
  make.post_review_findings quality.coverage_lines quality.coverage_functions
  quality.max_surviving_mutants quality.max_clippy_findings
  quality.max_complexity_violations quality.max_architecture_violations
  quality.max_unused_dependencies quality.max_dependency_policy_findings
  quality.max_spectral_findings quality.max_unapproved_breaking_changes
  quality.max_image_vulnerabilities_high_critical
  quality.max_smoke_budget_breaches ci.provider ci.workflows
  ci.required_checks ci.human_gated ci.base_ref review.coderabbit
  review.reviewers review.ai_review_agents review.request_changes_blocking
  capabilities.template_derived capabilities.run_in_container
  capabilities.structurizr capabilities.load_testing
  capabilities.mutation_testing capabilities.dynamic_security_testing
  capabilities.publish_pr_comments capabilities.protected_config
  capabilities.template_sync)

# vp_copy NAME [SOURCE] — a writable copy of SOURCE (default: the golden
# profile) at $BATS_TEST_TMPDIR/NAME.yml; prints its path.
vp_copy() {
  local dest="$BATS_TEST_TMPDIR/$1.yml"
  cp "${2:-$GOLDEN}" "$dest"
  printf '%s\n' "$dest"
}

# expect_valid FILE — the validator accepts FILE: exit 0, stdout exactly
# `VALID: FILE`, nothing on stderr.
expect_valid() {
  run --separate-stderr "$VALIDATE" "$1"
  if [[ "$status" -ne 0 || "$output" != "VALID: $1" || -n "$stderr" ]]; then
    printf 'status %s\n--- stdout\n%s\n--- stderr\n%s\n' "$status" "$output" "$stderr"
    return 1
  fi
}

# expect_violations FILE LINE... — the validator rejects FILE with exactly the
# given VIOLATION lines, in that order, then `INVALID: FILE: <n> violation(s)`;
# exit 1, nothing on stderr.
expect_violations() {
  local file="$1" want
  shift
  want="$(printf '%s\n' "$@" "INVALID: $file: $# violation(s)")"
  run --separate-stderr "$VALIDATE" "$file"
  if [[ "$status" -ne 1 || "$output" != "$want" || -n "$stderr" ]]; then
    printf 'status %s\n--- stdout\n%s\n--- want\n%s\n--- stderr\n%s\n' \
      "$status" "$output" "$want" "$stderr"
    return 1
  fi
}

# expect_missing KEY — the golden profile without KEY is rejected with the
# single line `VIOLATION: KEY: missing` (V4).
expect_missing() {
  local f
  f="$(vp_copy "missing-$1")"
  drop_profile_key "$f" "$1"
  expect_violations "$f" "VIOLATION: $1: missing"
}

# expect_bar KEY VALUE REASON — quality.KEY set to VALUE is rejected with the
# single line `VIOLATION: quality.KEY: REASON` (V11).
expect_bar() {
  local f
  f="$(vp_copy "bar-$1")"
  mutate_profile "$f" "quality.$1" "$2"
  expect_violations "$f" "VIOLATION: quality.$1: $3"
}

# vp_parity FILE — the validator under the default backend and under
# SDLC_FORCE_PYTHON_YAML=1 prints byte-identical stdout and stderr and exits
# with the same status.
vp_parity() {
  local def="$BATS_TEST_TMPDIR/parity.default" py="$BATS_TEST_TMPDIR/parity.python"
  local sd=0 sp=0
  (
    unset SDLC_FORCE_PYTHON_YAML _SDLC_YQ_OK
    "$VALIDATE" "$1"
  ) >"$def" 2>&1 || sd=$?
  (
    export SDLC_FORCE_PYTHON_YAML=1
    "$VALIDATE" "$1"
  ) >"$py" 2>&1 || sp=$?
  if ! cmp -s "$def" "$py" || [[ "$sd" != "$sp" ]]; then
    printf 'backend mismatch (default %s, python %s)\n--- default\n' "$sd" "$sp"
    cat "$def"
    printf -- '--- python\n'
    cat "$py"
    return 1
  fi
}

# golden_value KEY — the text after `<name>: ` on the line of KEY (`name` or
# `group.name`) in the golden profile, quotes kept; nothing for a block key.
golden_value() {
  awk -v key="$1" '
    BEGIN {
      dot = index(key, ".")
      if (dot) { group = substr(key, 1, dot - 1); lead = "  " substr(key, dot + 1) ":" }
      else { group = ""; lead = key ":" }
    }
    /^[^ #]/ { current = $0; sub(/:.*/, "", current) }
    (group == "" || current == group) && substr($0, 1, length(lead)) == lead {
      rest = substr($0, length(lead) + 1)
      if (rest == "" || substr(rest, 1, 1) == " ") { sub(/^ /, "", rest); print rest; exit }
    }
  ' "$GOLDEN"
}

# golden_items KEY — the items (`    - <item>`) of the block list KEY
# (`group.name`) in the golden profile, one per line, quotes kept.
golden_items() {
  awk -v key="$1" '
    BEGIN { dot = index(key, "."); group = substr(key, 1, dot - 1); lead = "  " substr(key, dot + 1) ":" }
    /^[^ #]/ { current = $0; sub(/:.*/, "", current) }
    on && substr($0, 1, 6) == "    - " { print substr($0, 7); next }
    on { exit }
    current == group && $0 == lead { on = 1 }
  ' "$GOLDEN"
}

# squote_lines — each stdin line as a single-quoted YAML scalar.
squote_lines() {
  local line
  while IFS= read -r line; do
    yaml_squote "$line"
  done
}

# stub_toml FILE PATH — the value at the dotted PATH of the TOML FILE, one
# item per line for an array; a `[]` segment maps the rest of PATH over the
# items of an array (`layer.[].name` is the name of every [[layer]]).
stub_toml() {
  python3 -I -c '
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    values = [tomllib.load(handle)]
for part in sys.argv[2].split("."):
    if part == "[]":
        values = [item for value in values for item in value]
    else:
        values = [value[part] for value in values]
if len(values) == 1 and isinstance(values[0], list):
    values = values[0]
for value in values:
    print(value)
' "$1" "$2"
}

# --- usage (SC-SCRIPT, SC-SUITE) ---------------------------------------------

@test "validate-profile: --help prints the header and exits 0" {
  run --separate-stderr "$VALIDATE" --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "validate-profile.sh — check a project profile against schema v1 (rules V1-V12, FR-7)." ]
  [[ "$output" == *"Usage: validate-profile.sh [PROFILE_FILE]"* ]]
  [[ "$output" == *"Exit: 0 valid; 1 any violation, or the profile is missing (V1); 2 usage error."* ]]
  [ -z "$stderr" ]
}

@test "validate-profile: --help is accepted in any position and validates nothing" {
  local help
  help="$("$VALIDATE" --help)"
  run --separate-stderr "$VALIDATE" "$BATS_TEST_TMPDIR/absent.yml" --help
  [ "$status" -eq 0 ]
  [ "$output" = "$help" ]
  [ -z "$stderr" ]
  run --separate-stderr "$VALIDATE" --unknown "$GOLDEN" -- --help
  [ "$status" -eq 0 ]
  [ "$output" = "$help" ]
  [ -z "$stderr" ]
}

@test "validate-profile: an unknown flag is a usage error (exit 2)" {
  run --separate-stderr "$VALIDATE" --strict "$GOLDEN"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] unknown argument: --strict (usage: validate-profile.sh [PROFILE_FILE])" ]
}

@test "validate-profile: a second positional argument or an empty PROFILE_FILE is a usage error (exit 2)" {
  run --separate-stderr "$VALIDATE" "$GOLDEN" "$GOLDEN"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] unexpected argument: $GOLDEN (usage: validate-profile.sh [PROFILE_FILE])" ]
  run --separate-stderr "$VALIDATE" ''
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] PROFILE_FILE must not be empty (usage: validate-profile.sh [PROFILE_FILE])" ]
}

@test "validate-profile: -- ends the options, so a profile path may start with a dash" {
  mkdir -p "$BATS_TEST_TMPDIR/dash"
  cp "$GOLDEN" "$BATS_TEST_TMPDIR/dash/-profile.yml"
  cd "$BATS_TEST_TMPDIR/dash"
  run --separate-stderr "$VALIDATE" -- -profile.yml
  [ "$status" -eq 0 ]
  [ "$output" = "VALID: -profile.yml" ]
  [ -z "$stderr" ]
}

# --- the golden profile --------------------------------------------------------

@test "validate-profile: the golden profile is valid on the default backend" {
  unset SDLC_FORCE_PYTHON_YAML _SDLC_YQ_OK
  expect_valid "$GOLDEN"
}

@test "validate-profile: the golden profile is valid with SDLC_FORCE_PYTHON_YAML=1" {
  export SDLC_FORCE_PYTHON_YAML=1
  expect_valid "$GOLDEN"
}

@test "validate-profile: the golden profile holds exactly the 115 schema keys in schema order" {
  local got
  got="$(awk '
    /^[a-z_]+:/ { group = $0; sub(/:.*/, "", group); if (group == "schema_version") print group; next }
    /^  [a-z0-9_]+:/ { key = $0; sub(/^  /, "", key); sub(/:.*/, "", key); print group "." key }
  ' "$GOLDEN")"
  [ "${#SCHEMA_KEYS[@]}" -eq 115 ]
  [ "$got" = "$(printf '%s\n' "${SCHEMA_KEYS[@]}")" ]
}

@test "validate-profile: the golden profile follows the emission format" {
  # Two header lines, no other comment, no document start, block style,
  # 2-space indentation, sequence items two spaces under their key, one
  # trailing newline, no trailing space, no tab, no empty line.
  [ "$(sed -n 1p "$GOLDEN")" = "# Project profile of the rust-backend-sdlc plugin (schema_version 1)." ]
  [ "$(sed -n 2p "$GOLDEN")" = "# Written by generate-profile.sh; re-detect with /rs-sdlc-setup --refresh." ]
  [ "$(tail -c 1 "$GOLDEN" | od -An -c | tr -d ' ')" = '\n' ]
  [ -n "$(tail -n 1 "$GOLDEN")" ]
  run ! grep -n -e ' $' -e $'\t' -e '^$' -e '^---' "$GOLDEN"
  [ "$(grep -c '#' "$GOLDEN")" -eq 2 ]
  # Every line has one of the five shapes; scalars are single-quoted strings,
  # or bare ints, booleans, null, enum values and make targets; bare words
  # only on the enum keys and make.*; review.* items bare, other items quoted.
  run awk '
    function bad(why) { printf "line %d (%s): %s\n", NR, why, $0 }
    NR <= 2 { next }
    /^schema_version: 1$/ { next }
    /^[a-z_]+:$/ { group = $0; sub(/:$/, "", group); next }
    /^  [a-z0-9_]+:$/ { key = $0; sub(/^  /, "", key); sub(/:$/, "", key); key = group "." key; next }
    /^  [a-z0-9_]+: / {
      key = $0; sub(/^  /, "", key); value = key; sub(/:.*/, "", key); key = group "." key
      sub(/^[a-z0-9_]+: /, "", value)
      if (value ~ /^'\''([^'\'']|'\'''\'')*'\''$/) { if (key ~ /^make\./) bad("quoted target"); next }
      if (value ~ /^([0-9]+|true|false|null)$/) next
      if (value ~ /^[a-z][a-z0-9-]*$/) {
        if (key !~ /^make\./ && key !~ /^(template\.sync_flavour|framework\.http|persistence\.engine|ci\.provider)$/) bad("bare string")
        next
      }
      bad("value form"); next
    }
    /^    - / {
      item = substr($0, 7)
      if (key ~ /^review\./) { if (item !~ /^[a-z][a-z0-9-]*$/) bad("review item not bare"); next }
      if (item !~ /^'\''([^'\'']|'\'''\'')*'\''$/) bad("item not quoted")
      next
    }
    { bad("shape") }
  ' "$GOLDEN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate-profile: the golden identity keys are the values detected from the billing-service stub" {
  rr_materialize "$STUB"
  local name repo
  name="$(basename "$STUB" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
  [ "$(golden_value project.name)" = "'$name'" ]
  [ "$(golden_value project.name)" = "'billing-service'" ]
  repo="$(git -C "$STUB" remote get-url origin)"
  repo="${repo#https://github.com/}"
  [ "$(golden_value project.repo)" = "'${repo%.git}'" ]
  [ "$(golden_value project.repo)" = "'acme/billing-service'" ]
  [ "$(golden_value project.default_branch)" = "'$(git -C "$STUB" symbolic-ref --short HEAD)'" ]
  [ "$(golden_value project.description)" = "$(stub_toml "$STUB/Cargo.toml" workspace.package.description | squote_lines)" ]
  [ "$(golden_value rust.toolchain)" = "$(stub_toml "$STUB/rust-toolchain.toml" toolchain.channel | squote_lines)" ]
  [ "$(golden_value rust.edition)" = "$(stub_toml "$STUB/Cargo.toml" workspace.package.edition | squote_lines)" ]
  [ "$(golden_value rust.msrv)" = "$(stub_toml "$STUB/Cargo.toml" workspace.package.rust-version | squote_lines)" ]
  [ "$(golden_value template.repository)" = "$(sed -n 's/^  TEMPLATE_REPOSITORY: //p' "$STUB/.github/workflows/template-sync-app.yml" | squote_lines)" ]
  [ "$(golden_value template.repository)" = "'acme/rust-template'" ]
  [ -f "$STUB/.github/workflows/template-sync-app.yml" ]
  [ -f "$STUB/.github/workflows/template-sync-pat.yml" ]
  [ "$(golden_value template.sync_flavour)" = both ]
  [ -z "$(git -C "$STUB" log --format=%s | grep -E '^chore\(#[0-9]+\): import template [^ ]+ at [0-9a-f]{7,40}$' || true)" ]
  [ "$(golden_value template.source_commit)" = null ]
}

@test "validate-profile: the golden make map is the stub's documented targets, make.load_tests from make/service.mk, the SUBST keys null" {
  rr_materialize "$STUB"
  local key target want n=0
  for key in "${SCHEMA_KEYS[@]}"; do
    [[ "$key" == make.* ]] || continue
    n=$((n + 1))
    target="${key#make.}"
    target="${target//_/-}"
    want=null
    if grep -qE "^${target}:.*##[[:space:]]" "$STUB/Makefile" "$STUB"/make/*.mk; then
      want="$target"
    fi
    if [[ "$(golden_value "$key")" != "$want" ]]; then
      printf '%s: golden %s, stub %s\n' "$key" "$(golden_value "$key")" "$want"
      return 1
    fi
  done
  [ "$n" -eq 55 ]
  grep -qE '^load-tests:.*##[[:space:]]' "$STUB/make/service.mk"
  run ! grep -qE '^load-tests:' "$STUB/Makefile"
  [ "$(golden_value make.load_tests)" = load-tests ]
  for key in ai_review_loop pr_comments fr_nfr_gate post_review_findings; do
    [ "$(golden_value "make.$key")" = null ]
  done
}

@test "validate-profile: the golden architecture and service keys are the values detected from the stub" {
  rr_materialize "$STUB"
  local members port
  [ -d "$STUB/crates" ]
  [ "$(golden_value architecture.crates_root)" = "'crates'" ]
  [ -f "$STUB/crates/service/Cargo.toml" ]
  [ "$(golden_value architecture.composition_root)" = "'crates/service'" ]
  [ "$(golden_items architecture.layers)" = "$(stub_toml "$STUB/architecture.toml" 'layer.[].name' | squote_lines)" ]
  members="$(stub_toml "$STUB/Cargo.toml" workspace.members)"
  [ "$(golden_items architecture.bounded_contexts)" = "$(printf '%s\n' "$members" |
    sed -nE 's#^crates/([a-z0-9-]+/[a-z0-9-]+)/(domain|application|infrastructure)$#\1#p' |
    grep -v '^shared/' | awk '!seen[$0]++' | squote_lines)" ]
  [ "$(golden_items architecture.bounded_contexts)" = "$(printf "'billing/invoice'\n'internal/health-check'")" ]
  [ "$(golden_items architecture.shared_crates)" = "$(printf '%s\n' "$members" | grep '^crates/shared/' | squote_lines)" ]
  [ -d "$STUB/migrations" ]
  [ "$(golden_value persistence.migrations_dir)" = "'migrations'" ]
  [ -d "$STUB/.sqlx" ]
  [ "$(golden_value persistence.offline_metadata)" = true ]
  stub_toml "$STUB/Cargo.toml" workspace.dependencies.sqlx.features | grep -qx postgres
  [ "$(golden_value persistence.engine)" = postgresql ]
  stub_toml "$STUB/Cargo.toml" workspace.dependencies.axum.version
  [ "$(golden_value framework.http)" = axum ]
  stub_toml "$STUB/Cargo.toml" workspace.dependencies.utoipa.version
  [ "$(golden_value framework.openapi)" = true ]
  stub_toml "$STUB/Cargo.toml" workspace.dependencies.async-graphql.version
  [ "$(golden_value framework.graphql)" = true ]
  port="$(sed -nE 's/^APP_PORT=([0-9]+)$/\1/p' "$STUB/.env" | head -n 1)"
  [ "$(golden_value service.port)" = "$port" ]
  [ "$(golden_value service.base_url)" = "'http://localhost:$port'" ]
  [ "$(golden_value service.liveness_path)" = "'/ping'" ]
  [ "$(golden_value service.readiness_path)" = "'/api/health'" ]
  [ "$(golden_value service.graphql_path)" = "'/api/graphql'" ]
  [ "$(golden_value service.docs_path)" = "'/api/docs'" ]
  [ -f "$STUB/.github/openapi-spec/spec.yaml" ]
  [ "$(golden_value service.openapi_snapshot)" = "'.github/openapi-spec/spec.yaml'" ]
  [ -f "$STUB/.github/graphql-spec/spec" ]
  [ "$(golden_value service.graphql_snapshot)" = "'.github/graphql-spec/spec'" ]
}

@test "validate-profile: the golden ci keys are the stub's workflows and the checks of its repository-settings tables" {
  rr_materialize "$STUB"
  local workflows required gated
  workflows="$(cd "$STUB/.github/workflows" && for f in *.yml *.yaml; do [ -f "$f" ] && printf '%s\n' "${f%.*}"; done | LC_ALL=C sort)"
  [ "$(golden_items ci.workflows)" = "$(printf '%s\n' "$workflows" | squote_lines)" ]
  [ "$(golden_value ci.provider)" = github-actions ]
  required="$(awk '
    /^## Required status checks/ { on = 1; next }
    /^## / { on = 0 }
    on && /^\| `/ {
      n = split($0, cell, "|"); req = cell[n - 1]; name = cell[3]
      gsub(/^ +| +$/, "", req); gsub(/^ +| +$/, "", name)
      if (req == "yes" && !(name in seen)) { seen[name] = 1; print name }
    }
  ' "$STUB/docs/repository-settings.md")"
  [ "$(printf '%s\n' "$required" | wc -l)" -eq 36 ]
  [ "$(golden_items ci.required_checks)" = "$(printf '%s\n' "$required" | squote_lines)" ]
  gated="$(human_gated_labels "$STUB" | cut -f 2 | awk '!seen[$0]++')"
  [ "$(golden_items ci.human_gated)" = "$(printf '%s\n' "$gated" | squote_lines)" ]
  [ "$(golden_items ci.human_gated)" = "$(printf "'Protected configuration'\n'OpenAPI breaking changes'\n'GraphQL breaking changes'")" ]
  [ "$(golden_value ci.base_ref)" = "'origin/main'" ]
}

@test "validate-profile: the golden review, capabilities and quality keys are the detected and shipped values" {
  rr_materialize "$STUB"
  local key marker
  [ -f "$STUB/.coderabbit.yaml" ]
  [ "$(golden_value review.coderabbit)" = true ]
  [ "$(golden_items review.reviewers)" = coderabbit ]
  [ "$(golden_items review.ai_review_agents)" = claude ]
  grep -qx '  request_changes_workflow: true' "$STUB/.coderabbit.yaml"
  [ "$(golden_value review.request_changes_blocking)" = true ]
  for marker in rust-toolchain.toml architecture.toml protected-config.toml xtask/Cargo.toml \
    make/gates.mk crates/service/Cargo.toml workspace.dsl; do
    [ -f "$STUB/$marker" ]
  done
  grep -qE '^CI_PREFLIGHT_TARGETS := validate-configuration( |$)' "$STUB/Makefile"
  [ "$(golden_value capabilities.template_derived)" = true ]
  # Docker is unreachable under common_setup, so detection yields false.
  [ "$STUB_DOCKER_INFO_EXIT" = 1 ]
  [ "$(golden_value capabilities.run_in_container)" = false ]
  [ -d "$STUB/tests/Load" ]
  [ "$(golden_value capabilities.load_testing)" = true ]
  [ "$(golden_value capabilities.structurizr)" = true ]
  [ "$(golden_value capabilities.mutation_testing)" = true ]
  [ "$(golden_value capabilities.dynamic_security_testing)" = false ]
  [ "$(golden_value capabilities.publish_pr_comments)" = true ]
  [ "$(golden_value capabilities.protected_config)" = true ]
  [ "$(golden_value capabilities.template_sync)" = true ]
  for key in coverage_lines coverage_functions; do
    [ "$(golden_value "quality.$key")" = 100 ]
  done
  [ "$(grep -cE '^  max_[a-z_]+: 0$' "$GOLDEN")" -eq 10 ]
  [ "$(grep -cE '^  (coverage_[a-z]+|max_[a-z_]+): ' "$GOLDEN")" -eq 12 ]
}

@test "validate-profile: without an argument it validates .claude/rust-sdlc.yml of the working directory" {
  rr_materialize "$STUB"
  mkdir -p "$STUB/.claude"
  cp "$GOLDEN" "$STUB/.claude/rust-sdlc.yml"
  cd "$STUB"
  run --separate-stderr "$VALIDATE"
  [ "$status" -eq 0 ]
  [ "$output" = "VALID: $PWD/.claude/rust-sdlc.yml" ]
  [ -z "$stderr" ]
}

@test "validate-profile: K7 the golden profile is yamllint-clean with the template's config" {
  k7_require yamllint
  run yamllint --strict -c "$FIXTURE_REPO/.yamllint.yml" "$GOLDEN"
  [ "$status" -eq 0 ]
}

@test "validate-profile: K7 the golden profile is Prettier-clean with the template's config" {
  k7_require prettier
  mkdir -p "$BATS_TEST_TMPDIR/k7"
  cp "$GOLDEN" "$BATS_TEST_TMPDIR/k7/rust-sdlc.yml"
  cd "$BATS_TEST_TMPDIR/k7"
  run prettier --config "$FIXTURE_REPO/.prettierrc.yml" --check rust-sdlc.yml
  [ "$status" -eq 0 ]
}

# --- V1, V2 --------------------------------------------------------------------

@test "validate-profile: V1 a missing profile prints only the not-found error and exits 1" {
  run --separate-stderr "$VALIDATE" "$BATS_TEST_TMPDIR/absent.yml"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] profile not found: $BATS_TEST_TMPDIR/absent.yml (run /rs-sdlc-setup)" ]
}

@test "validate-profile: V1 a directory, or no profile at the default path, is not found" {
  run --separate-stderr "$VALIDATE" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] profile not found: $BATS_TEST_TMPDIR (run /rs-sdlc-setup)" ]
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty"
  run --separate-stderr "$VALIDATE"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] profile not found: $PWD/.claude/rust-sdlc.yml (run /rs-sdlc-setup)" ]
}

@test "validate-profile: V2 invalid-yaml.yml prints one not-parseable line without a traceback (AC-7.3)" {
  local f="$PROFILES/invalid-yaml.yml"
  run --separate-stderr "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "VIOLATION: $f: not parseable YAML ("?*")" ]]
  [ "${lines[1]}" = "INVALID: $f: 1 violation(s)" ]
  [[ "$output$stderr" != *Traceback* ]]
  [ -z "$stderr" ]
}

@test "validate-profile: V2 the python backend names the parser's first error line" {
  local f="$PROFILES/invalid-yaml.yml"
  export SDLC_FORCE_PYTHON_YAML=1
  expect_violations "$f" "VIOLATION: $f: not parseable YAML (mapping values are not allowed here)"
}

@test "validate-profile: V2 a document whose root is not a mapping is not parseable" {
  local f="$BATS_TEST_TMPDIR/list.yml"
  printf -- "- 'schema_version'\n- 1\n" >"$f"
  expect_violations "$f" "VIOLATION: $f: not parseable YAML (the root is not a mapping)"
  : >"$f"
  expect_violations "$f" "VIOLATION: $f: not parseable YAML (the root is not a mapping)"
}

@test "validate-profile: V2 an unreadable profile is reported as not parseable" {
  skip_if_root
  local f
  f="$(vp_copy unreadable)"
  chmod 000 "$f"
  run --separate-stderr "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "VIOLATION: $f: not parseable YAML ("?*")" ]]
  [ "${lines[1]}" = "INVALID: $f: 1 violation(s)" ]
}

# --- V3, V4, V5 (AC-5.1) ---------------------------------------------------------

@test "validate-profile: V3 wrong-schema-version.yml is rejected" {
  expect_violations "$PROFILES/wrong-schema-version.yml" "VIOLATION: schema_version: must be 1 (2)"
}

@test "validate-profile: V3 a quoted or null schema_version is not the integer 1" {
  local f
  f="$(vp_copy schema-quoted)"
  mutate_profile "$f" schema_version "'1'"
  expect_violations "$f" "VIOLATION: schema_version: must be 1 ('1')"
  mutate_profile "$f" schema_version null
  expect_violations "$f" "VIOLATION: schema_version: must be 1 (null)"
}

@test "validate-profile: V4 missing root key schema_version" {
  expect_missing schema_version
}

@test "validate-profile: V4 missing project key project.repo" {
  expect_missing project.repo
}

@test "validate-profile: V4 missing rust key rust.toolchain" {
  expect_missing rust.toolchain
}

@test "validate-profile: V4 missing template key template.sync_flavour" {
  expect_missing template.sync_flavour
}

@test "validate-profile: V4 missing framework key framework.http" {
  expect_missing framework.http
}

@test "validate-profile: V4 missing persistence key persistence.engine" {
  expect_missing persistence.engine
}

@test "validate-profile: V4 missing architecture key architecture.crates_root" {
  expect_missing architecture.crates_root
}

@test "validate-profile: V4 missing service key service.graphql_path" {
  expect_missing service.graphql_path
}

@test "validate-profile: V4 missing quality key quality.coverage_lines" {
  expect_missing quality.coverage_lines
}

@test "validate-profile: V4 missing ci key ci.provider" {
  expect_missing ci.provider
}

@test "validate-profile: V4 missing review key review.reviewers" {
  expect_missing review.reviewers
}

@test "validate-profile: V4 missing capabilities key capabilities.run_in_container" {
  expect_missing capabilities.run_in_container
}

@test "validate-profile: V4 missing make key make.check_security (AC-7.2)" {
  expect_missing make.check_security
}

@test "validate-profile: V4 missing make key make.start" {
  expect_missing make.start
}

@test "validate-profile: V4 missing make key make.post_review_findings" {
  expect_missing make.post_review_findings
}

@test "validate-profile: V4 a missing group reports each of its required keys" {
  local f key want=()
  f="$(vp_copy no-capabilities)"
  awk '/^capabilities:$/ { skip = 1; next } skip && /^  / { next } { skip = 0; print }' "$GOLDEN" >"$f"
  for key in "${SCHEMA_KEYS[@]}"; do
    [[ "$key" == capabilities.* ]] && want+=("VIOLATION: $key: missing")
  done
  [ "${#want[@]}" -eq 9 ]
  expect_violations "$f" "${want[@]}"
}

@test "validate-profile: the optional keys may be omitted" {
  local f
  f="$(vp_copy optional-omitted)"
  drop_profile_key "$f" project.description
  drop_profile_key "$f" rust.msrv
  drop_profile_key "$f" template.repository
  drop_profile_key "$f" template.source_commit
  expect_valid "$f"
}

@test "validate-profile: make.check_security: null is valid (AC-7.2)" {
  local f
  f="$(vp_copy check-security-null)"
  mutate_profile "$f" make.check_security null
  expect_valid "$f"
}

@test "validate-profile: null passes where the schema allows it (the missing-key cases set to null)" {
  local f key
  f="$(vp_copy nullable)"
  for key in project.repo rust.toolchain framework.http persistence.engine \
    architecture.crates_root service.graphql_path ci.provider make.check_security \
    make.start make.post_review_findings project.description rust.msrv \
    template.repository; do
    mutate_profile "$f" "$key" null
  done
  expect_valid "$f"
}

@test "validate-profile: V5 null is rejected where the schema forbids it" {
  local f
  f="$(vp_copy not-nullable)"
  mutate_profile "$f" template.sync_flavour null
  mutate_profile "$f" quality.coverage_lines null
  mutate_profile "$f" review.reviewers null
  mutate_profile "$f" capabilities.run_in_container null
  mutate_profile "$f" project.name null
  expect_violations "$f" \
    "VIOLATION: project.name: must not be null" \
    "VIOLATION: template.sync_flavour: must not be null" \
    "VIOLATION: quality.coverage_lines: must not be null" \
    "VIOLATION: review.reviewers: must not be null" \
    "VIOLATION: capabilities.run_in_container: must not be null"
}

@test "validate-profile: V4 the misspelled key quality.coverage_line is unknown" {
  local f
  f="$(vp_copy misspelled)"
  sed 's/^  coverage_lines: 100$/  coverage_line: 100/' "$GOLDEN" >"$f"
  expect_violations "$f" \
    "VIOLATION: quality.coverage_lines: missing" \
    "VIOLATION: quality.coverage_line: unknown key"
}

@test "validate-profile: V4 an unknown group is reported, a group that is not a mapping too" {
  local f
  f="$(vp_copy unknown-group)"
  printf 'extras:\n  note: 1\n' >>"$f"
  mutate_profile "$f" capabilities true
  expect_violations "$f" \
    "VIOLATION: capabilities: expected map (true)" \
    "VIOLATION: extras: unknown key"
}

# --- V6, V7, V8, V9 --------------------------------------------------------------

@test "validate-profile: V6 a quoted '100' is a string, not an int" {
  local f
  f="$(vp_copy quoted-100)"
  mutate_profile "$f" quality.coverage_lines "'100'"
  expect_violations "$f" "VIOLATION: quality.coverage_lines: expected int ('100')"
}

@test "validate-profile: V6 each key has its YAML type" {
  local f
  f="$(vp_copy types)"
  mutate_profile "$f" project.name 42
  mutate_profile "$f" framework.openapi "'true'"
  mutate_profile "$f" architecture.layers "'domain'"
  mutate_profile "$f" service.port "'8081'"
  mutate_profile "$f" make.ci true
  mutate_profile "$f" ci.workflows $'\n    - \'quality\'\n    - 7'
  expect_violations "$f" \
    "VIOLATION: project.name: expected string (42)" \
    "VIOLATION: framework.openapi: expected bool ('true')" \
    "VIOLATION: architecture.layers: expected list ('domain')" \
    "VIOLATION: service.port: expected int ('8081')" \
    "VIOLATION: make.ci: expected string (true)" \
    "VIOLATION: ci.workflows: expected list of string (['quality', 7])"
}

@test "validate-profile: V7 bad-enum.yml reports every value outside its enum" {
  local f="$PROFILES/bad-enum.yml"
  expect_violations "$f" \
    "VIOLATION: template.sync_flavour: not one of app, pat, both, none ('hybrid')" \
    "VIOLATION: framework.http: not one of axum ('actix')" \
    "VIOLATION: persistence.engine: not one of postgresql ('mysql')" \
    "VIOLATION: ci.provider: not one of github-actions ('gitlab-ci')" \
    "VIOLATION: review.reviewers: not one of coderabbit, cubic, qodo, qlty, sonarcloud ('copilot')"
}

@test "validate-profile: V8 formats of scalars, list items, the port range and the bars" {
  local f
  f="$(vp_copy formats)"
  mutate_profile "$f" project.name "'Billing Service'"
  mutate_profile "$f" project.repo "'billing-service'"
  mutate_profile "$f" rust.edition "'24'"
  mutate_profile "$f" template.source_commit "'not-a-sha'"
  mutate_profile "$f" persistence.migrations_dir "'../migrations'"
  mutate_profile "$f" architecture.bounded_contexts $'\n    - \'billing\'\n    - \'internal/health-check\''
  mutate_profile "$f" service.port 70000
  mutate_profile "$f" service.base_url "'https://billing.example.com'"
  mutate_profile "$f" service.liveness_path "'ping'"
  mutate_profile "$f" quality.max_surviving_mutants -1
  mutate_profile "$f" ci.base_ref "'origin/main branch'"
  mutate_profile "$f" review.ai_review_agents $'\n    - \'Claude Code\''
  expect_violations "$f" \
    "VIOLATION: project.name: invalid format ('Billing Service')" \
    "VIOLATION: project.repo: invalid format ('billing-service')" \
    "VIOLATION: rust.edition: invalid format ('24')" \
    "VIOLATION: template.source_commit: invalid format ('not-a-sha')" \
    "VIOLATION: persistence.migrations_dir: invalid format ('../migrations')" \
    "VIOLATION: architecture.bounded_contexts: invalid format ('billing')" \
    "VIOLATION: service.port: invalid format (70000)" \
    "VIOLATION: service.base_url: invalid format ('https://billing.example.com')" \
    "VIOLATION: service.liveness_path: invalid format ('ping')" \
    "VIOLATION: quality.max_surviving_mutants: invalid format (-1)" \
    "VIOLATION: ci.base_ref: invalid format ('origin/main branch')" \
    "VIOLATION: review.ai_review_agents: invalid format ('Claude Code')"
}

@test "validate-profile: V9 a ci.human_gated entry absent from ci.required_checks" {
  local f
  f="$(vp_copy human-gated)"
  mutate_profile "$f" ci.human_gated $'\n    - \'Protected configuration\'\n    - \'Nightly build\''
  expect_violations "$f" "VIOLATION: ci.human_gated: 'Nightly build' is not in ci.required_checks"
}

@test "validate-profile: V9 duplicate reviewers and an empty review.ai_review_agents" {
  local f
  f="$(vp_copy review-lists)"
  mutate_profile "$f" review.reviewers $'\n    - coderabbit\n    - qodo\n    - coderabbit'
  mutate_profile "$f" review.ai_review_agents '[]'
  expect_violations "$f" \
    "VIOLATION: review.reviewers: duplicate item ('coderabbit')" \
    "VIOLATION: review.ai_review_agents: must not be empty"
}

# --- V10, V12 (AC-7.2) -----------------------------------------------------------

@test "validate-profile: V10 make.start: 'start; rm -rf /' is not a target name" {
  local f
  f="$(vp_copy injection)"
  mutate_profile "$f" make.start "'start; rm -rf /'"
  expect_violations "$f" "VIOLATION: make.start: invalid target name ('start; rm -rf /')"
}

@test "validate-profile: V12 make.complexity: format reroutes a gate key" {
  local f
  f="$(vp_copy reroute-complexity)"
  mutate_profile "$f" make.complexity format
  expect_violations "$f" "VIOLATION: make.complexity: must be null or 'complexity' ('format')"
}

@test "validate-profile: V12 make.tests_with_coverage: unit-tests reroutes a gate key" {
  local f
  f="$(vp_copy reroute-coverage)"
  mutate_profile "$f" make.tests_with_coverage unit-tests
  expect_violations "$f" "VIOLATION: make.tests_with_coverage: must be null or 'tests-with-coverage' ('unit-tests')"
}

@test "validate-profile: V12 make.fr_nfr_gate: format-check points a SUBST key at a template gate" {
  local f
  f="$(vp_copy reroute-subst)"
  mutate_profile "$f" make.fr_nfr_gate format-check
  expect_violations "$f" "VIOLATION: make.fr_nfr_gate: must be null or 'fr-nfr-gate' ('format-check')"
}

# --- V11: tighten-only bars (AC-7.1, NFR-4) -----------------------------------------

@test "validate-profile: rejects quality.coverage_lines 99" {
  expect_bar coverage_lines 99 "below the floor (99 vs bound 100)"
}

@test "validate-profile: rejects quality.coverage_functions 99" {
  expect_bar coverage_functions 99 "below the floor (99 vs bound 100)"
}

@test "validate-profile: rejects quality.max_surviving_mutants 1" {
  expect_bar max_surviving_mutants 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_clippy_findings 1" {
  expect_bar max_clippy_findings 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_complexity_violations 1" {
  expect_bar max_complexity_violations 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_architecture_violations 1" {
  expect_bar max_architecture_violations 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_unused_dependencies 1" {
  expect_bar max_unused_dependencies 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_dependency_policy_findings 1" {
  expect_bar max_dependency_policy_findings 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_spectral_findings 1" {
  expect_bar max_spectral_findings 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_unapproved_breaking_changes 1" {
  expect_bar max_unapproved_breaking_changes 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_image_vulnerabilities_high_critical 1" {
  expect_bar max_image_vulnerabilities_high_critical 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects quality.max_smoke_budget_breaches 1" {
  expect_bar max_smoke_budget_breaches 1 "above the ceiling (1 vs bound 0)"
}

@test "validate-profile: rejects a floor of 101 (above the maximum)" {
  expect_bar coverage_functions 101 "above the maximum (101 vs bound 100)"
}

@test "validate-profile: rejects a 20-digit ceiling without wrapping" {
  # 30000000000000000000 wraps to a negative number in 64-bit shell
  # arithmetic, so a (( value > 0 )) check would accept it.
  local wrapped
  wrapped="$(bash -c 'echo $((30000000000000000000))')"
  [[ "$wrapped" == -* ]]
  expect_bar max_unused_dependencies 30000000000000000000 \
    "above the ceiling (30000000000000000000 vs bound 0)"
  vp_parity "$BATS_TEST_TMPDIR/bar-max_unused_dependencies.yml"
}

# --- all violations, parity, side effects, timing ------------------------------

@test "validate-profile: every violation is reported in rule order, not only the first" {
  local f
  f="$(vp_copy every-rule)"
  mutate_profile "$f" schema_version 3
  drop_profile_key "$f" project.default_branch
  printf 'extras: true\n' >>"$f"
  mutate_profile "$f" template.sync_flavour null
  mutate_profile "$f" framework.graphql 1
  mutate_profile "$f" persistence.engine sqlite
  mutate_profile "$f" service.port 0
  mutate_profile "$f" ci.human_gated $'\n    - \'Protected configuration\'\n    - \'Nightly build\''
  mutate_profile "$f" make.doctor "'doctor; true'"
  mutate_profile "$f" quality.max_spectral_findings 3
  mutate_profile "$f" make.lint_code lint-repo
  expect_violations "$f" \
    "VIOLATION: schema_version: must be 1 (3)" \
    "VIOLATION: project.default_branch: missing" \
    "VIOLATION: extras: unknown key" \
    "VIOLATION: template.sync_flavour: must not be null" \
    "VIOLATION: framework.graphql: expected bool (1)" \
    "VIOLATION: persistence.engine: not one of postgresql ('sqlite')" \
    "VIOLATION: service.port: invalid format (0)" \
    "VIOLATION: ci.human_gated: 'Nightly build' is not in ci.required_checks" \
    "VIOLATION: make.doctor: invalid target name ('doctor; true')" \
    "VIOLATION: quality.max_spectral_findings: above the ceiling (3 vs bound 0)" \
    "VIOLATION: make.lint_code: must be null or 'lint-code' ('lint-repo')"
}

@test "validate-profile: parity: the golden profile prints the same bytes on both backends" {
  vp_parity "$GOLDEN"
}

@test "validate-profile: parity: bad-enum.yml prints the same bytes on both backends" {
  vp_parity "$PROFILES/bad-enum.yml"
}

@test "validate-profile: parity: a profile with types, formats and bounds violations prints the same bytes on both backends" {
  local f
  f="$(vp_copy parity-mixed)"
  mutate_profile "$f" quality.coverage_lines "'100'"
  mutate_profile "$f" quality.max_clippy_findings 2
  mutate_profile "$f" make.complexity format
  mutate_profile "$f" service.port 65536
  drop_profile_key "$f" make.check_security
  printf 'extras: 1\n' >>"$f"
  vp_parity "$f"
  run "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "INVALID: $f: 6 violation(s)" ]
}

@test "validate-profile: writes nothing, for a valid and for a rejected profile" {
  local dir="$BATS_TEST_TMPDIR/watch" before after
  mkdir -p "$dir"
  cp "$GOLDEN" "$dir/good.yml"
  cp "$PROFILES/bad-enum.yml" "$dir/bad.yml"
  touch "$BATS_TEST_TMPDIR/marker"
  before="$(cd "$dir" && ls -lA && cksum good.yml bad.yml)"
  cd "$dir"
  run "$VALIDATE" good.yml
  [ "$status" -eq 0 ]
  run "$VALIDATE" bad.yml
  [ "$status" -eq 1 ]
  run "$VALIDATE" missing.yml
  [ "$status" -eq 1 ]
  after="$(ls -lA && cksum good.yml bad.yml)"
  [ "$before" = "$after" ]
  [ -z "$(find "$dir" -newer "$BATS_TEST_TMPDIR/marker")" ]
}

@test "validate-profile: finishes within 5 s on the golden profile" {
  local start=$SECONDS
  run "$VALIDATE" "$GOLDEN"
  [ "$status" -eq 0 ]
  [ $((SECONDS - start)) -le 5 ]
}
