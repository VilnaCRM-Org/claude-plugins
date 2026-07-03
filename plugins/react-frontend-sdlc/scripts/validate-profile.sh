#!/usr/bin/env bash
# validate-profile.sh — schema validation for .claude/react-sdlc.yml
# (architecture §4, ADR-2, FR-17).
#
# Usage: validate-profile.sh [PROFILE_FILE]
#   PROFILE_FILE defaults to <cwd>/.claude/react-sdlc.yml
#
# Checks: required keys, schema_version == 1, list-typed keys (the required
# feature-module list plus the optional list keys, empty lists legal; a flat
# component library may declare modules empty), make map completeness
# (null values are legal — capability absent, NFR-4), and the ADR-7
# raise-only quality rule: score thresholds may only move up from the
# shipped defaults, violation-count ceilings may only stay at 0.
# Prints one line per violation; exit 0 = valid, exit 1 = any violation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# shellcheck disable=SC2119  # profile_path's TARGET_REPO_DIR arg is optional
PROFILE="${1:-$(profile_path)}"
[[ -f "$PROFILE" ]] || die "profile not found: $PROFILE (run /fe-sdlc-setup to generate it)"
require_yaml_toolchain
# Fail malformed YAML up front with a clean diagnostic: without this guard
# the first yaml_get on an unparseable file dies via set -e with a raw
# backend traceback (PyYAML scanner error / yq parse error) instead of a
# [react-sdlc] message naming the file and a remediation.
yaml_parses "$PROFILE" \
  || die "profile is not valid YAML: $PROFILE (fix the syntax or regenerate it with /fe-sdlc-setup)"

violations=0
violation() {
  printf 'VIOLATION: %s\n' "$*"
  violations=$((violations + 1))
}

# Key must exist with a non-null, non-empty value.
require_nonnull() {
  local key=$1
  local val
  val="$(yaml_get "$PROFILE" "$key")"
  if [[ -z "$val" ]]; then
    violation "required key '$key' missing or null"
  fi
}

# Key must be declared; an explicit null value is legal (NFR-4 degrade).
require_declared() {
  local key=$1
  if ! yaml_has "$PROFILE" "$key"; then
    violation "required key '$key' not declared"
  fi
}

# Key, when present, must be one of an allowlisted value set. A missing/null
# value is left to require_nonnull so we do not double-report; this guards
# only against an out-of-contract value (e.g. a package_manager the agent
# runner mapping does not define), which is interpolated into agent commands.
require_enum() {
  local key=$1; shift
  local val allowed
  val="$(yaml_get "$PROFILE" "$key")"
  [[ -z "$val" ]] && return 0
  for allowed in "$@"; do
    [[ "$val" == "$allowed" ]] && return 0
  done
  violation "key '$key' value '$val' not one of: $*"
}

# Thresholds are scores/counts: non-negative integers only.
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

# strip_zeros, num_gt, num_lt — wrap-safe non-negative integer comparison
# helpers are shared via lib/common.sh (sourced above) so this script and
# ai-review-loop.sh use one implementation.

# Score thresholds: raise-only vs shipped default (ADR-7).
check_floor() {
  local key=$1 floor=$2
  local val
  val="$(yaml_get "$PROFILE" "$key")"
  if [[ -z "$val" ]]; then
    violation "required key '$key' missing or null"
    return 0
  fi
  if ! is_int "$val"; then
    violation "key '$key' value '$val' is not an integer"
    return 0
  fi
  if num_lt "$val" "$floor"; then
    violation "key '$key' value $val lowered below shipped default $floor (ADR-7: raise-only)"
  fi
}

# Violation-count ceilings: shipped default 0 may not be relaxed (ADR-7).
check_ceiling() {
  local key=$1 ceiling=$2
  local val
  val="$(yaml_get "$PROFILE" "$key")"
  if [[ -z "$val" ]]; then
    violation "required key '$key' missing or null"
    return 0
  fi
  if ! is_int "$val"; then
    violation "key '$key' value '$val' is not an integer"
    return 0
  fi
  if num_gt "$val" "$ceiling"; then
    violation "key '$key' value $val relaxed above shipped default $ceiling (ADR-7: raise-only)"
  fi
}

# Optional list key: MAY be absent, but a declared value must be a sequence
# (a bare scalar reads back non-empty via yaml_get_list and would otherwise
# pass silently, same trap as architecture.modules below).
check_optional_list() {
  local key=$1
  if yaml_has "$PROFILE" "$key" && ! yaml_is_list "$PROFILE" "$key"; then
    violation "key '$key' must be a list (sequence) when declared"
  fi
}

# --- schema_version -------------------------------------------------------
schema_version="$(yaml_get "$PROFILE" schema_version)"
if [[ -z "$schema_version" ]]; then
  violation "required key 'schema_version' missing or null"
elif [[ "$schema_version" != "1" ]]; then
  violation "key 'schema_version' value '$schema_version' unsupported (expected 1)"
fi

# --- required scalars -----------------------------------------------------
require_nonnull project.name
require_nonnull project.repo
require_nonnull framework.ui
require_nonnull framework.package_manager
# Allowlist mirrors generate-profile.sh's supported set; each maps to a
# documented package-runner in agents/react-implementer.md and
# commands/fe-sdlc-implement.md (bun→bun x, npm→npx, pnpm→pnpm exec,
# yarn→yarn exec). Reject anything outside it so a malformed value cannot
# reach the `docker compose exec dev <runner>` interpolation.
require_enum framework.package_manager bun npm pnpm yarn
require_nonnull architecture.source_root

# --- feature modules (declared list; MAY be empty for a flat library) ------
# Type-check only: a bare scalar (e.g. `modules: user`) reads back non-empty
# via yaml_get_list and would otherwise pass — reject it as a schema error so
# the key is always a sequence. An EMPTY list is legal: a flat component
# library has no src/modules/* dirs, so do NOT require at least one entry.
if ! yaml_is_list "$PROFILE" architecture.modules; then
  violation "key 'architecture.modules' must be a list (sequence) of feature-module directory names"
fi

# --- optional list keys ------------------------------------------------------
# Absent is legal (the schema defaults apply), but a declared value must be
# a sequence; an EMPTY list stays valid. companion.* is deliberately NOT
# checked — the schema declares it non-validated.
check_optional_list architecture.path_aliases
check_optional_list ci.workflows
check_optional_list ci.required_checks
check_optional_list review.ai_review_agents

# --- make map completeness (null = capability absent, NFR-4) ----------------
MAKE_KEYS=(ci start start_prod build lint lint_eslint lint_tsc lint_md
           lint_dup lint_metrics lint_deps format test_unit_client
           test_unit_server test_integration test_e2e test_visual
           test_mutation merge_mutation_reports test_load test_memory_leak
           lighthouse_desktop lighthouse_mobile storybook_build
           ai_review_loop pr_comments fr_nfr_gate post_review_findings a11y)
for key in "${MAKE_KEYS[@]}"; do
  if ! yaml_has "$PROFILE" "make.$key"; then
    violation "make map incomplete: 'make.$key' not declared (use null when the capability is absent)"
  fi
done

# --- quality thresholds (ADR-7 shipped defaults) ----------------------------
check_floor quality.coverage_statements 100
check_floor quality.coverage_branches 100
check_floor quality.coverage_functions 100
check_floor quality.coverage_lines 100
# quality.mutation_msi is seeded from the target repo's stryker.config.mjs
# `break` threshold (floored to an integer) and is raise-only thereafter.
check_floor quality.mutation_msi 2
# Lighthouse floors are integer percents (95 == minScore 0.95) so the same
# wrap-safe integer check_floor applies; raise-only above the shipped bar.
check_floor quality.lighthouse_desktop 95
check_floor quality.lighthouse_mobile 85
check_ceiling quality.jscpd_clones 0
check_ceiling quality.eslint_errors 0
check_ceiling quality.eslint_warnings 0
check_ceiling quality.tsc_errors 0
check_ceiling quality.markdownlint_errors 0
check_ceiling quality.depcruise_violations 0
check_ceiling quality.visual_diffs 0

# --- ci + metrics gate ------------------------------------------------------
# Both keys must be declared; an explicit null ci.provider means "no CI" and
# triggers the degrade path (NFR-4) downstream, so it is legal here.
# quality.metrics_enforced is the rust-code-analysis hard-fail toggle (bool):
# the schema mandates it stay `true` (docs/profile-schema.md). A metrics-less
# repo degrades at the LANE level (make.lint_metrics: null), never by flipping
# this policy flag, so a `false`/absent value would silently disable the
# raise-only metrics gate (ADR-7) — reject anything but true.
require_declared ci.provider
metrics_enforced="$(yaml_get "$PROFILE" quality.metrics_enforced)"
if [[ -z "$metrics_enforced" ]]; then
  violation "required key 'quality.metrics_enforced' missing or null"
elif [[ "$metrics_enforced" != "true" ]]; then
  violation "key 'quality.metrics_enforced' value '$metrics_enforced' must be true (the rust-code-analysis hard-fail gate may not be disabled; ADR-7)"
fi

# --- verdict ----------------------------------------------------------------
if (( violations > 0 )); then
  log_error "profile INVALID: $violations violation(s) in $PROFILE"
  exit 1
fi
log_info "profile valid: $PROFILE"
