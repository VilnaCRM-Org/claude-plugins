#!/usr/bin/env bash
# validate-profile.sh — schema validation for .claude/php-sdlc.yml
# (architecture §4, ADR-2, FR-17).
#
# Usage: validate-profile.sh [PROFILE_FILE]
#   PROFILE_FILE defaults to <cwd>/.claude/php-sdlc.yml
#
# Checks: required keys, enum legality, schema_version == 1, make map
# completeness (null values are legal — capability absent, NFR-4), and
# the ADR-7 raise-only quality rule: score thresholds may only move up
# from the shipped defaults, violation-count ceilings may only stay at 0.
# Prints one line per violation; exit 0 = valid, exit 1 = any violation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# shellcheck disable=SC2119  # profile_path's TARGET_REPO_DIR arg is optional
PROFILE="${1:-$(profile_path)}"
[[ -f "$PROFILE" ]] || die "profile not found: $PROFILE (run /sdlc-setup to generate it)"
require_yaml_toolchain
# Fail malformed YAML up front with a clean diagnostic: without this guard
# the first yaml_get on an unparseable file dies via set -e with a raw
# backend traceback (PyYAML scanner error / yq parse error) instead of a
# [php-sdlc] message naming the file and a remediation.
yaml_parses "$PROFILE" \
  || die "profile is not valid YAML: $PROFILE (fix the syntax or regenerate it with /sdlc-setup)"

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

check_enum() {
  local key=$1; shift
  local val candidate
  val="$(yaml_get "$PROFILE" "$key")"
  [[ -z "$val" ]] && return 0  # absence already reported by require_nonnull
  for candidate in "$@"; do
    if [[ "$val" == "$candidate" ]]; then
      return 0
    fi
  done
  violation "key '$key' value '$val' not a legal enum value (expected one of: $*)"
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
require_nonnull php.version
require_nonnull framework.name
require_nonnull persistence.mapper
require_nonnull persistence.engine
require_nonnull architecture.source_root

# --- enums ----------------------------------------------------------------
check_enum persistence.mapper doctrine-orm doctrine-odm
check_enum persistence.engine mysql mariadb postgresql mongodb

# --- bounded contexts (must be a list with ≥1 entry) -----------------------
# Type-check first: a bare scalar (e.g. `bounded_contexts: core`) reads back
# non-empty via yaml_get_list and would otherwise pass — reject it as a
# schema error so the key is always a sequence.
if ! yaml_is_list "$PROFILE" architecture.bounded_contexts; then
  violation "key 'architecture.bounded_contexts' must be a list (sequence) of bounded contexts"
else
  contexts="$(yaml_get_list "$PROFILE" architecture.bounded_contexts)"
  if [[ -z "$contexts" ]]; then
    violation "key 'architecture.bounded_contexts' must list at least one bounded context"
  fi
fi

# --- make map completeness (null = capability absent, NFR-4) ----------------
MAKE_KEYS=(ci start tests e2e psalm deptrac phpinsights infection
           ai_review_loop pr_comments fr_nfr_gate load_tests)
for key in "${MAKE_KEYS[@]}"; do
  if ! yaml_has "$PROFILE" "make.$key"; then
    violation "make map incomplete: 'make.$key' not declared (use null when the capability is absent)"
  fi
done

# --- quality thresholds (ADR-7 shipped defaults) ----------------------------
check_floor quality.phpinsights.quality 100
check_floor quality.phpinsights.architecture 100
check_floor quality.phpinsights.style 100
check_floor quality.phpinsights.complexity 94
check_floor quality.infection_msi 100
check_ceiling quality.deptrac_violations 0
check_ceiling quality.psalm_errors 0

# --- ci ---------------------------------------------------------------------
# Key must be declared; explicit null means "no CI" and triggers the
# degrade path (NFR-4) downstream, so it is legal here.
require_declared ci.provider

# --- verdict ----------------------------------------------------------------
if (( violations > 0 )); then
  log_error "profile INVALID: $violations violation(s) in $PROFILE"
  exit 1
fi
log_info "profile valid: $PROFILE"
