#!/usr/bin/env bats
# Tests for scripts/generate-profile.sh (Story 2.2, FR-2, NFR-3, NFR-4).
#
# Each detection source gets a case (package.json framework deps, package
# manager, node engine, tsconfig path aliases, src/modules layout, Makefile
# map, Stryker break threshold, workflows, .coderabbit.yaml), plus the two
# modes from NFR-3 (default diff-and-keep vs --refresh) and the A3 rule that
# missing capabilities yield null/false instead of errors. The stub repo is
# copied per-test because generation writes into it — the shared fixture is
# never mutated.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GENERATE="$PLUGIN_ROOT/scripts/generate-profile.sh"
  VALIDATE="$PLUGIN_ROOT/scripts/validate-profile.sh"
  LIB="$PLUGIN_ROOT/scripts/lib/common.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  cp -r "$BATS_TEST_DIRNAME/fixtures/stub-repo" "$REPO"
  PROFILE="$REPO/.claude/react-sdlc.yml"
  source "$LIB"
}

pget() { yaml_get "$PROFILE" "$1"; }

@test "stub repo: package.json detection (ui, state, di, router, bundler, pm, runtime, i18n, graphql)" {
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile created"* ]]
  [ "$(pget framework.ui)" = "react-mui" ]
  [ "$(pget framework.state)" = "zustand" ]
  [ "$(pget framework.di)" = "tsyringe" ]
  [ "$(pget framework.router)" = "react-router" ]
  [ "$(pget framework.bundler)" = "rsbuild" ]
  [ "$(pget framework.package_manager)" = "bun" ]
  [ "$(pget framework.runtime)" = "24.8.0" ]
  [ "$(pget framework.i18n)" = "react-i18next" ]
  [ "$(pget framework.graphql_mock)" = "apollo-server" ]
}

@test "stub repo: architecture (source_root, modules, aliases), coderabbit, project" {
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(pget architecture.source_root)" = "src" ]
  run yaml_get_list "$PROFILE" architecture.modules
  [[ "$output" == *alpha* ]]
  [[ "$output" == *beta* ]]
  # src/components holds only .gitkeep (no UI* components) -> prefix null
  [ -z "$(pget architecture.component_prefix)" ]
  run yaml_get_list "$PROFILE" architecture.path_aliases
  [[ "$output" == *"@auth"* ]]
  [ "$(pget review.coderabbit)" = "true" ]
  [ "$(pget project.name)" = "stub-frontend" ]
  [ "$(pget project.repo)" = "stub-frontend" ]
}

@test "stub repo: Makefile map and workflow names detected" {
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(pget make.ci)" = "ci" ]
  # logical key test_unit_client maps to the CI-flavoured actual target
  [ "$(pget make.test_unit_client)" = "ci-test-unit-client" ]
  [ "$(pget make.storybook_build)" = "storybook-build" ]
  # not in stub Makefile -> null (reads back as empty scalar)
  [ -z "$(pget make.a11y)" ]
  [ -z "$(pget make.ai_review_loop)" ]
  [ "$(pget ci.provider)" = "github-actions" ]
  run yaml_get_list "$PROFILE" ci.workflows
  [[ "$output" == *CI* ]]
  [[ "$output" == *E2E* ]]
  [ "$(pget capabilities.load_testing)" = "true" ]
  [ "$(pget capabilities.dynamic_a11y_testing)" = "false" ]
}

@test "stub repo: quality + capabilities (mutation_msi from stryker break, storybook)" {
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  # seeded from stryker.config.mjs thresholds.break: 60
  [ "$(pget quality.mutation_msi)" = "60" ]
  [ "$(pget quality.metrics_enforced)" = "true" ]
  [ "$(pget capabilities.storybook)" = "true" ]
  [ "$(pget capabilities.visual_testing)" = "true" ]
  [ "$(pget capabilities.mutation_testing)" = "true" ]
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
  # user-edited value the detector would not re-produce
  sed -i 's/mutation_msi: 60/mutation_msi: 61/' "$PROFILE"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept existing"* ]]
  [[ "$output" == *"--refresh"* ]]
  [[ "$output" =~ -[[:space:]]+mutation_msi:\ 61 ]]
  [[ "$output" =~ \+[[:space:]]+mutation_msi:\ 60 ]]
  # file untouched
  grep -q 'mutation_msi: 61' "$PROFILE"
}

@test "--refresh overwrites the existing profile (NFR-3)" {
  run "$GENERATE" "$REPO"
  sed -i 's/mutation_msi: 60/mutation_msi: 61/' "$PROFILE"
  run "$GENERATE" --refresh "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile refreshed"* ]]
  grep -q 'mutation_msi: 60' "$PROFILE"
}

@test "stripped Makefile: make keys become null, no failure (NFR-4 AC)" {
  rm "$REPO/Makefile"
  run "$GENERATE" "$REPO"
  [ "$status" -eq 0 ]
  for key in ci start build lint test_unit_client test_e2e test_mutation storybook_build; do
    [ -z "$(pget "make.$key")" ]
  done
  # keys are DECLARED null, not missing — validator must still accept the map
  run bash -c "source '$LIB'; yaml_has '$PROFILE' make.ci"
  [ "$status" -eq 0 ]
  # no Makefile target and no test-load dep signal -> capability off
  [ "$(pget capabilities.load_testing)" = "false" ]
  [ "$(pget quality.metrics_enforced)" = "false" ]
  # storybook still true: @storybook/react dep is an independent signal
  [ "$(pget capabilities.storybook)" = "true" ]
}

@test "empty repo: never errors, everything null/false (A3)" {
  EMPTY="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$EMPTY"
  run "$GENERATE" "$EMPTY"
  [ "$status" -eq 0 ]
  PROFILE="$EMPTY/.claude/react-sdlc.yml"
  [ -z "$(pget framework.ui)" ]
  [ -z "$(pget framework.state)" ]
  [ -z "$(pget ci.provider)" ]
  [ "$(pget review.coderabbit)" = "false" ]
  [ "$(pget capabilities.storybook)" = "false" ]
  [ "$(pget schema_version)" = "1" ]
  # package_manager is required non-null by the validator, so with no
  # packageManager field and no lockfile it falls back to npm (never null)
  [ "$(pget framework.package_manager)" = "npm" ]
}

@test "unknown flag: usage error" {
  run "$GENERATE" --bogus "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}
