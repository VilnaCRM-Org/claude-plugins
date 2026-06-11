#!/usr/bin/env bash
# generate-profile.sh — detect target-repo facts and write the project
# profile .claude/php-sdlc.yml (FR-2, architecture §4).
#
# Usage: generate-profile.sh [--refresh] [TARGET_DIR]
#   TARGET_DIR defaults to $PWD.
#
# Detection sources: composer.json (php version, framework, API
# Platform, GraphQL, Doctrine mapper), Doctrine/.env config (engine),
# Makefile (logical→actual target map), src/ layout (bounded contexts,
# shared context), .github/workflows/ (CI provider + workflow names),
# .coderabbit.yaml, workspace.dsl (structurizr capability).
#
# A missing capability NEVER fails generation — it becomes null/false
# (A3, NFR-4). Idempotency contract (NFR-3): with an existing profile,
# the default mode prints a unified diff against the freshly detected
# profile and KEEPS the existing file; --refresh overwrites it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

REFRESH=0
TARGET="$PWD"
for arg in "$@"; do
  case "$arg" in
    --refresh) REFRESH=1 ;;
    -*) die "unknown argument: $arg (usage: generate-profile.sh [--refresh] [TARGET_DIR])" ;;
    *) TARGET="$arg" ;;
  esac
done
[[ -d "$TARGET" ]] || die "target directory not found: $TARGET"
require_yaml_toolchain

COMPOSER="$TARGET/composer.json"

# --- composer.json access (jq, else python3 stdlib json) --------------------

json_available() {
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1
}

# composer_req PACKAGE — version constraint from require/require-dev, '' if absent
composer_req() {
  local pkg=$1
  [[ -f "$COMPOSER" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg p "$pkg" '(.require[$p] // ."require-dev"[$p] // empty)' "$COMPOSER" 2>/dev/null || true
  else
    python3 - "$COMPOSER" "$pkg" <<'PYEOF'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
pkg = sys.argv[2]
val = data.get('require', {}).get(pkg) or data.get('require-dev', {}).get(pkg)
if val:
    print(val)
PYEOF
  fi
}

composer_name() {
  [[ -f "$COMPOSER" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '.name // empty' "$COMPOSER" 2>/dev/null || true
  else
    python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("name") or "")
except Exception:
    pass' "$COMPOSER"
  fi
}

# strip_constraint "^8.4" -> 8.4 ; ">=7.3 <8" -> 7.3 ; "" -> ""
strip_constraint() {
  printf '%s\n' "$1" | sed -E 's/^[^0-9]*//; s/[^0-9.].*$//'
}

# sanitize_inline VALUE — drop control characters (incl. newline/CR) from
# repo-derived text; profile values are emitted on a single YAML line.
sanitize_inline() {
  printf '%s' "$1" | tr -d '\000-\037\177'
}

json_available || die "need jq or python3 to read composer.json"

# --- project ------------------------------------------------------------------

project_repo=""
if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  origin="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"
  if [[ -n "$origin" ]]; then
    # git@host:owner/name.git or https://host/owner/name.git -> owner/name
    project_repo="$(printf '%s\n' "$origin" | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')"
  fi
fi
pkg_name="$(sanitize_inline "$(composer_name)")"
[[ -z "$project_repo" ]] && project_repo="$pkg_name"
project_repo="$(sanitize_inline "$project_repo")"
project_name="${pkg_name##*/}"
[[ -z "$project_name" ]] && project_name="$(basename "$TARGET")"
project_name="$(sanitize_inline "$project_name")"

# --- php / framework ------------------------------------------------------------

php_version="$(strip_constraint "$(composer_req php)")"

framework_name=""
framework_version=""
if [[ -n "$(composer_req symfony/framework-bundle)" ]]; then
  framework_name="symfony"
  framework_version="$(strip_constraint "$(composer_req symfony/framework-bundle)")"
elif [[ -n "$(composer_req laravel/framework)" ]]; then
  framework_name="laravel"
  framework_version="$(strip_constraint "$(composer_req laravel/framework)")"
fi

api_platform_constraint="$(composer_req api-platform/core)"
api_platform="false"
[[ -n "$api_platform_constraint" ]] && api_platform="\"$(strip_constraint "$api_platform_constraint")\""

graphql="false"
if [[ -n "$(composer_req webonyx/graphql-php)" ]] || [[ -n "$(composer_req overblog/graphql-bundle)" ]]; then
  graphql="true"
fi

# --- persistence -----------------------------------------------------------------

mapper=""
if [[ -n "$(composer_req doctrine/mongodb-odm-bundle)" ]] || [[ -n "$(composer_req doctrine/mongodb-odm)" ]]; then
  mapper="doctrine-odm"
elif [[ -n "$(composer_req doctrine/orm)" ]] || [[ -n "$(composer_req doctrine/doctrine-bundle)" ]]; then
  mapper="doctrine-orm"
fi

engine=""
if [[ "$mapper" == "doctrine-odm" ]]; then
  engine="mongodb"
elif [[ "$mapper" == "doctrine-orm" ]]; then
  # Look for the driver in doctrine config, then in .env DATABASE_URL.
  hints=""
  for f in "$TARGET"/config/packages/doctrine.yaml "$TARGET"/config/packages/doctrine.yml \
           "$TARGET"/.env "$TARGET"/.env.dist; do
    [[ -f "$f" ]] && hints+="$(cat "$f")"$'\n'
  done
  if grep -qiE 'mariadb' <<<"$hints"; then
    engine="mariadb"
  elif grep -qiE 'pdo_mysql|mysql://|mysqli' <<<"$hints"; then
    engine="mysql"
  elif grep -qiE 'pdo_pgsql|postgres(ql)?://' <<<"$hints"; then
    engine="postgresql"
  fi
fi

# --- architecture (src/ layout) ----------------------------------------------------

source_root=""
shared_context=""
contexts=()
if [[ -d "$TARGET/src" ]]; then
  source_root="src"
  for d in "$TARGET"/src/*/; do
    [[ -d "$d" ]] || continue
    ctx="$(sanitize_inline "$(basename "$d")")"
    if [[ "$ctx" == "Shared" || "$ctx" == "Common" ]]; then
      shared_context="$ctx"
    else
      contexts+=("$ctx")
    fi
  done
fi

# --- make target map ----------------------------------------------------------------

makefile_targets=""
if [[ -f "$TARGET/Makefile" ]]; then
  # `|| true`: a Makefile with no plain targets (only .PHONY/pattern
  # rules/variable assignments) makes grep exit 1, which pipefail+set -e
  # would turn into a silent abort — but a target-less Makefile must
  # yield null make.* keys, never a failure (A3, NFR-4).
  makefile_targets="$(grep -oE '^[A-Za-z0-9_-]+:' "$TARGET/Makefile" | tr -d ':' | sort -u || true)"
fi

# first existing Makefile target among candidates, else empty
find_target() {
  local candidate
  for candidate in "$@"; do
    if grep -qxF "$candidate" <<<"$makefile_targets"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

make_ci="$(find_target ci)"
make_start="$(find_target start up)"
make_tests="$(find_target tests test)"
make_e2e="$(find_target e2e-tests e2e)"
make_psalm="$(find_target psalm)"
make_deptrac="$(find_target deptrac)"
make_phpinsights="$(find_target phpinsights insights)"
make_infection="$(find_target infection)"
make_ai_review_loop="$(find_target ai-review-loop)"
make_pr_comments="$(find_target pr-comments)"
make_fr_nfr_gate="$(find_target fr-nfr-gate)"
make_load_tests="$(find_target load-tests smoke-load-tests)"

# --- ci ----------------------------------------------------------------------------

ci_provider=""
workflows=()
if [[ -d "$TARGET/.github/workflows" ]]; then
  for wf in "$TARGET"/.github/workflows/*.yml "$TARGET"/.github/workflows/*.yaml; do
    [[ -f "$wf" ]] || continue
    ci_provider="github-actions"
    name="$(sanitize_inline "$(yaml_get "$wf" name)")"
    [[ -z "$name" ]] && name="$(basename "$wf" | sed -E 's/\.(yml|yaml)$//')"
    workflows+=("$name")
  done
fi

# --- review / capabilities ------------------------------------------------------------

coderabbit="false"
[[ -f "$TARGET/.coderabbit.yaml" || -f "$TARGET/.coderabbit.yml" ]] && coderabbit="true"

structurizr="false"
[[ -f "$TARGET/workspace.dsl" ]] && structurizr="true"

load_testing="false"
[[ -n "$make_load_tests" ]] && load_testing="true"

# --- YAML emission ---------------------------------------------------------------------

# Repo-derived strings (composer name, src/ dir names, workflow names) are
# untrusted: quote them on emission and strip control characters so they
# cannot inject YAML structure into the profile or break parsing.

# scalar VALUE — emits null when empty (use only for detector-constrained
# values: enums, digit-sanitized versions, ^[A-Za-z0-9_-]+ make targets)
scalar() { if [[ -z "$1" ]]; then printf 'null'; else printf '%s' "$1"; fi; }

# yaml_quote VALUE — double-quoted YAML scalar, \ and " escaped
yaml_quote() {
  local v=${1//\\/\\\\}
  v=${v//\"/\\\"}
  printf '"%s"' "$v"
}

# qscalar VALUE — quoted scalar, null when empty
qscalar() { if [[ -z "$1" ]]; then printf 'null'; else yaml_quote "$1"; fi; }

# flow_list ITEM... — ["a", "b"] flow-style list, every item quoted
flow_list() {
  local out="" item
  for item in "$@"; do
    [[ -n "$out" ]] && out+=", "
    out+="$(yaml_quote "$item")"
  done
  printf '[%s]' "$out"
}

emit_profile() {
  cat <<PROFILE
schema_version: 1
project:
  name: $(qscalar "$project_name")
  repo: $(qscalar "$project_repo")
php:
  version: $(qscalar "$php_version")
framework:
  name: $(scalar "$framework_name")
  version: $(qscalar "$framework_version")
  api_platform: $api_platform
  graphql: $graphql
persistence:
  mapper: $(scalar "$mapper")
  engine: $(scalar "$engine")
architecture:
  source_root: $(scalar "$source_root")
  bounded_contexts: $(flow_list "${contexts[@]+"${contexts[@]}"}")
  shared_context: $(scalar "$shared_context")
make:
  ci: $(scalar "$make_ci")
  start: $(scalar "$make_start")
  tests: $(scalar "$make_tests")
  e2e: $(scalar "$make_e2e")
  psalm: $(scalar "$make_psalm")
  deptrac: $(scalar "$make_deptrac")
  phpinsights: $(scalar "$make_phpinsights")
  infection: $(scalar "$make_infection")
  ai_review_loop: $(scalar "$make_ai_review_loop")
  pr_comments: $(scalar "$make_pr_comments")
  fr_nfr_gate: $(scalar "$make_fr_nfr_gate")
  load_tests: $(scalar "$make_load_tests")
quality:
  phpinsights:
    quality: 100
    architecture: 100
    style: 100
    complexity: 94
  deptrac_violations: 0
  psalm_errors: 0
  infection_msi: 100
ci:
  provider: $(scalar "$ci_provider")
  workflows: $(flow_list "${workflows[@]+"${workflows[@]}"}")
  required_checks: []
review:
  coderabbit: $coderabbit
  ai_review_agents: [claude]
  request_changes_blocking: true
capabilities:
  structurizr: $structurizr
  observability_emf: false
  load_testing: $load_testing
PROFILE
}

# --- write / diff / refresh (NFR-3) ------------------------------------------------------

PROFILE_FILE="$TARGET/$SDLC_PROFILE_RELPATH"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
emit_profile >"$tmp"

# Reject symlinked write targets: a committed symlink in a processed
# (untrusted/forked) repo would otherwise let `cat >` follow it and
# create/overwrite a file outside the repo boundary. Refuse both a
# symlinked profile file and a symlinked .claude dir, and require the
# resolved parent dir to live inside $TARGET.
[[ -L "$PROFILE_FILE" ]] && die "profile path is a symlink; refusing to write: $PROFILE_FILE"
PROFILE_DIR="$(dirname "$PROFILE_FILE")"
mkdir -p "$PROFILE_DIR"
[[ -L "$PROFILE_DIR" ]] && die "profile parent (.claude) is a symlink; refusing to write: $PROFILE_DIR"
target_real="$(realpath "$TARGET")" || die "cannot resolve target directory: $TARGET"
dir_real="$(realpath "$PROFILE_DIR")" || die "cannot resolve profile directory: $PROFILE_DIR"
case "$dir_real/" in
  "$target_real"/*) : ;;
  *) die "profile directory escapes the target repo (symlink redirect?): $dir_real" ;;
esac

# Write a temp file in the SAME real directory and mv it into place. The
# in-dir mktemp + mv replaces the destination atomically (so a symlinked
# destination would be replaced, not followed); chmod restores umask-
# honoring perms that mktemp's 0600 would otherwise clobber. On --refresh
# we preserve the existing file's mode instead.
write_profile() {
  local out mode
  out="$(mktemp "$dir_real/.php-sdlc.yml.XXXXXX")" || die "cannot create temp file in $dir_real"
  cat "$tmp" >"$out"
  if [[ -f "$PROFILE_FILE" ]]; then
    chmod --reference="$PROFILE_FILE" "$out" 2>/dev/null || true
  else
    printf -v mode '%o' "$(( 0666 & ~0$(umask) ))"
    chmod "$mode" "$out" 2>/dev/null || true
  fi
  mv -f "$out" "$PROFILE_FILE"
}

if [[ ! -f "$PROFILE_FILE" ]]; then
  write_profile
  log_info "profile created: $PROFILE_FILE"
elif diff -q "$PROFILE_FILE" "$tmp" >/dev/null 2>&1; then
  log_info "profile unchanged: $PROFILE_FILE"
elif (( REFRESH )); then
  write_profile
  log_info "profile refreshed: $PROFILE_FILE"
else
  log_warn "detected profile differs from existing $PROFILE_FILE (kept existing; use --refresh to overwrite)"
  diff -u "$PROFILE_FILE" "$tmp" || true
fi
