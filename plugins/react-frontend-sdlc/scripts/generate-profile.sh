#!/usr/bin/env bash
# generate-profile.sh — detect target-repo facts and write the project
# profile .claude/react-sdlc.yml (FR-2, architecture §4).
#
# Usage: generate-profile.sh [--refresh] [TARGET_DIR]
#   TARGET_DIR defaults to $PWD.
#
# Detection sources: package.json (framework deps, package manager,
# node engine), tsconfig.paths.json / tsconfig.json (path aliases), the
# source root layout (feature modules — or a flat component library),
# Makefile (logical→actual target map, multi-candidate per key), the
# Stryker config (mutation break threshold), .github/workflows/ (CI
# provider + workflow names), and .coderabbit.yaml.
#
# The detector is repo-shape agnostic (NFR-4): it works across an
# RSBuild SPA with src/modules/*, a Next.js app, and a flat component
# library with no modules and no `ci` target. A missing capability NEVER
# fails generation — it becomes null/false. Idempotency contract (NFR-3):
# with an existing profile, the default mode prints a unified diff against
# the freshly detected profile and KEEPS the existing file; --refresh
# overwrites it.
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

PKG="$TARGET/package.json"

# --- package.json access (jq, else python3 stdlib json) ---------------------

json_available() {
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1
}
json_available || die "need jq or python3 to read package.json"

# pkg_string JQ_FILTER PY_KEYPATH — a scalar string from package.json, '' if
# absent. JQ_FILTER is a jq path (e.g. '.name'); PY_KEYPATH is the dotted
# fallback key list for the python backend (e.g. 'name' or 'engines.node').
pkg_string() {
  local jqf=$1 pykey=$2
  [[ -f "$PKG" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r "($jqf // empty)" "$PKG" 2>/dev/null || true
  else
    python3 - "$PKG" "$pykey" <<'PYEOF'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
cur = data
for part in sys.argv[2].split('.'):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        cur = None
        break
if isinstance(cur, (str, int, float)):
    print(cur)
PYEOF
  fi
}

# pkg_dep NAME — version constraint from dependencies/devDependencies/
# peerDependencies, '' if absent. A malformed package.json degrades to
# "absent" rather than aborting generation (NFR-4).
pkg_dep() {
  local name=$1
  [[ -f "$PKG" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg p "$name" \
      '(.dependencies[$p] // .devDependencies[$p] // .peerDependencies[$p] // empty)' \
      "$PKG" 2>/dev/null || true
  else
    python3 - "$PKG" "$name" <<'PYEOF'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
name = sys.argv[2]
for field in ('dependencies', 'devDependencies', 'peerDependencies'):
    deps = data.get(field)
    if isinstance(deps, dict) and deps.get(name):
        print(deps[name])
        sys.exit(0)
PYEOF
  fi
}

has_dep() { [[ -n "$(pkg_dep "$1")" ]]; }

# pkg_alias_keys — path-alias keys from tsconfig.paths.json (preferred) or
# tsconfig.json compilerOptions.paths, one per line, trailing '/*' stripped.
# JSONC parsing needs python3; without it aliases degrade to empty (NFR-4).
pkg_alias_keys() {
  local f
  command -v python3 >/dev/null 2>&1 || return 0
  for f in "$TARGET/tsconfig.paths.json" "$TARGET/tsconfig.json"; do
    [[ -f "$f" ]] || continue
    python3 - "$f" <<'PYEOF' && return 0
import json, re, sys
raw = open(sys.argv[1]).read()
# tsconfig files allow // and /* */ comments and trailing commas — strip them.
raw = re.sub(r'/\*.*?\*/', '', raw, flags=re.S)
raw = re.sub(r'(^|\s)//.*$', '', raw, flags=re.M)
raw = re.sub(r',(\s*[}\]])', r'\1', raw)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)
paths = (data.get('compilerOptions') or {}).get('paths') or data.get('paths')
if not isinstance(paths, dict) or not paths:
    sys.exit(1)
seen = []
for k in paths:
    a = k[:-2] if k.endswith('/*') else k
    if a and a not in seen:
        seen.append(a)
for a in seen:
    print(a)
PYEOF
  done
  return 0
}

# strip_constraint "^18.3" -> 18.3 ; ">=24.8.0" -> 24.8.0 ; "20.x" -> 20 ;
# "bun@1.3.5" -> 1.3.5. Leading non-digits and trailing junk after the first
# version number are dropped; a trailing '.' from a wildcard is trimmed.
strip_constraint() {
  printf '%s\n' "$1" | sed -E 's/^[^0-9]*//; s/[^0-9.].*$//; s/\.+$//'
}

# int_part "0.9" -> 0 ; "90" -> 90 ; "" -> "" — leading integer run only.
int_part() {
  printf '%s\n' "$1" | sed -E 's/^([0-9]+).*$/\1/'
}

# strip_pm "bun@1.3.5" -> bun ; "pnpm@9.0.0" -> pnpm ; "" -> "" — the
# packageManager field pins a version after '@'; only the tool name is kept.
strip_pm() { printf '%s\n' "${1%%@*}"; }

# sanitize_inline VALUE — drop control characters (incl. newline/CR) from
# repo-derived text; profile values are emitted on a single YAML line.
sanitize_inline() {
  printf '%s' "$1" | tr -d '\000-\037\177'
}

# --- project ------------------------------------------------------------------

project_repo=""
if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  origin="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"
  if [[ -n "$origin" ]]; then
    # git@host:owner/name.git or https://host/owner/name.git -> owner/name
    project_repo="$(printf '%s\n' "$origin" | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')"
  fi
fi
pkg_name="$(sanitize_inline "$(pkg_string '.name' name)")"
[[ -z "$project_repo" ]] && project_repo="$pkg_name"
project_repo="$(sanitize_inline "$project_repo")"
# npm package names may be scoped (@scope/name) — the bare name is the slug.
project_name="${pkg_name##*/}"
[[ -z "$project_name" ]] && project_name="$(basename "$TARGET")"
project_name="$(sanitize_inline "$project_name")"

# --- framework ----------------------------------------------------------------

framework_ui=""
if has_dep @mui/material; then
  framework_ui="react-mui"
elif has_dep react; then
  framework_ui="react"
fi

framework_state=""
if has_dep zustand; then framework_state="zustand"
elif has_dep @reduxjs/toolkit || has_dep redux; then framework_state="redux"
elif has_dep mobx; then framework_state="mobx"
fi

framework_di=""
if has_dep tsyringe; then framework_di="tsyringe"
elif has_dep inversify; then framework_di="inversify"
fi

framework_router=""
if has_dep next; then framework_router="next"
elif has_dep react-router-dom || has_dep react-router; then framework_router="react-router"
fi

framework_bundler=""
if has_dep next; then framework_bundler="next"
elif has_dep @rsbuild/core; then framework_bundler="rsbuild"
elif has_dep vite; then framework_bundler="vite"
elif [[ -n "$(pkg_string '.exports' exports)$(pkg_string '.module' module)" ]]; then
  framework_bundler="library"
fi

# package_manager: the pinned packageManager field when it names a supported
# manager (anything else is untrusted repo text), else a lockfile signal.
# Required non-null by the validator, so fall back to npm when nothing pins it.
framework_pm="$(strip_pm "$(pkg_string '.packageManager' packageManager)")"
case "$framework_pm" in
  bun|pnpm|npm|yarn) ;;
  *) framework_pm="" ;;
esac
if [[ -z "$framework_pm" ]]; then
  if [[ -f "$TARGET/bun.lock" || -f "$TARGET/bun.lockb" ]]; then framework_pm="bun"
  elif [[ -f "$TARGET/pnpm-lock.yaml" ]]; then framework_pm="pnpm"
  elif [[ -f "$TARGET/yarn.lock" ]]; then framework_pm="yarn"
  elif [[ -f "$TARGET/package-lock.json" ]]; then framework_pm="npm"
  else framework_pm="npm"
  fi
fi

framework_runtime="$(strip_constraint "$(pkg_string '.engines.node' engines.node)")"

framework_i18n=""
if has_dep next-i18next; then framework_i18n="next-i18next"
elif has_dep react-i18next || has_dep i18next; then framework_i18n="react-i18next"
fi

framework_graphql_mock=""
if has_dep @apollo/server || has_dep apollo-server; then framework_graphql_mock="apollo-server"
elif has_dep msw; then framework_graphql_mock="msw"
fi

# --- architecture (source layout) ---------------------------------------------

source_root=""
[[ -d "$TARGET/src" ]] && source_root="src"

# Feature modules: src/modules/* if present, else src/components/* (a flat
# component library), else the top-level src/* dirs. MAY be empty.
modules=()
scan_dirs() {
  local base=$1 d ctx
  [[ -d "$base" ]] || return 0
  for d in "$base"/*/; do
    [[ -d "$d" ]] || continue
    ctx="$(sanitize_inline "$(basename "$d")")"
    [[ -n "$ctx" ]] && modules+=("$ctx")
  done
}
if [[ -d "$TARGET/src/modules" ]]; then
  scan_dirs "$TARGET/src/modules"
elif [[ -d "$TARGET/src/components" ]]; then
  scan_dirs "$TARGET/src/components"
elif [[ -d "$TARGET/src" ]]; then
  scan_dirs "$TARGET/src"
fi

# component_prefix: the shared PascalCase prefix of UI components, if any.
component_prefix=""
if [[ -d "$TARGET/src/components" ]]; then
  if compgen -G "$TARGET/src/components/[Uu][Ii]*" >/dev/null 2>&1; then
    component_prefix="UI"
  fi
fi

path_aliases=()
while IFS= read -r a; do
  [[ -n "$a" ]] && path_aliases+=("$(sanitize_inline "$a")")
done < <(pkg_alias_keys)

# --- make target map (multi-candidate per logical key, NFR-4) -----------------

makefile_targets=""
if [[ -f "$TARGET/Makefile" ]]; then
  # A target line is `name:`/`name::` followed by nothing or a non-`=`
  # prerequisite list; the `[^=:]` guard excludes `name:=v` variable
  # assignments. `|| true`: a target-less Makefile must yield null make.*
  # keys, never abort under pipefail+set -e.
  makefile_targets="$(grep -E '^[A-Za-z0-9_-]+:{1,2}([^=:].*)?$' "$TARGET/Makefile" \
    | sed -E 's/:.*$//' | sort -u || true)"
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
make_start="$(find_target start dev start-dev)"
make_start_prod="$(find_target start-prod)"
make_build="$(find_target build)"
make_lint="$(find_target lint)"
make_lint_eslint="$(find_target lint-eslint lint-next)"
make_lint_tsc="$(find_target lint-tsc)"
make_lint_md="$(find_target lint-md lint-markdown)"
make_lint_dup="$(find_target lint-dup)"
make_lint_metrics="$(find_target lint-metrics)"
make_lint_deps="$(find_target lint-deps lint-dep-cruiser)"
make_format="$(find_target format format-check fmt-prettier fmt)"
make_test_unit_client="$(find_target ci-test-unit-client test-unit-client test-unit)"
make_test_unit_server="$(find_target ci-test-unit-server test-unit-server)"
make_test_integration="$(find_target ci-test-integration test-integration)"
make_test_e2e="$(find_target test-e2e ci-test-e2e e2e)"
make_test_visual="$(find_target test-visual ci-test-visual)"
make_test_mutation="$(find_target test-mutation ci-test-mutation)"
make_merge_mutation="$(find_target merge-mutation-reports)"
make_test_load="$(find_target test-load ci-test-load load-tests)"
make_test_memory_leak="$(find_target test-memory-leak ci-test-memory-leak)"
make_lh_desktop="$(find_target lighthouse-desktop ci-test-lighthouse-desktop)"
make_lh_mobile="$(find_target lighthouse-mobile ci-test-lighthouse-mobile)"
make_storybook="$(find_target storybook-build build-storybook)"
make_ai_review_loop="$(find_target ai-review-loop)"
make_pr_comments="$(find_target pr-comments)"
make_fr_nfr_gate="$(find_target fr-nfr-gate)"
make_post_review_findings="$(find_target post-review-findings)"
make_a11y="$(find_target a11y test-a11y accessibility)"

# --- quality ------------------------------------------------------------------

# mutation_msi is seeded from the target's Stryker `break` threshold (floored
# to an integer) and is raise-only thereafter. Absent config -> the schema
# minimum 2, so the validator's raise-only floor still holds.
mutation_msi=2
for sc in "$TARGET"/stryker.config.mjs "$TARGET"/stryker.conf.mjs \
          "$TARGET"/stryker.config.js "$TARGET"/stryker.conf.json; do
  [[ -f "$sc" ]] || continue
  # Optional punct after `break` so a quoted key ("break": / 'break':) in a
  # JSON/JS config matches too, not just the bare `break:` of an .mjs object.
  brk="$(grep -oE 'break[[:punct:]]?[[:space:]]*:[[:space:]]*[0-9]+' "$sc" | head -1 \
         | grep -oE '[0-9]+' || true)"
  if [[ -n "$brk" ]]; then
    mutation_msi="$(int_part "$brk")"
    break
  fi
done

# The rca hard-fail policy flag is a standing commitment that stays true
# regardless of whether a lint-metrics make target exists: a metrics-less repo
# degrades at the lane level (make.lint_metrics: null), never by disabling the
# policy (docs/degrade-matrix.md, docs/profile-schema.md). validate-profile.sh
# rejects any other value.
metrics_enforced="true"

# --- capabilities -------------------------------------------------------------

cap_visual="false";       [[ -n "$make_test_visual" ]] && cap_visual="true"
cap_lighthouse="false";   [[ -n "$make_lh_desktop$make_lh_mobile" ]] && cap_lighthouse="true"
cap_mutation="false";     [[ -n "$make_test_mutation" ]] && cap_mutation="true"
cap_storybook="false"
{ [[ -n "$make_storybook" ]] || has_dep storybook || has_dep @storybook/react; } && cap_storybook="true"
cap_load="false";         [[ -n "$make_test_load" ]] && cap_load="true"
cap_memleak="false";      [[ -n "$make_test_memory_leak" ]] && cap_memleak="true"
# dynamic_a11y gates live-browser probing, which needs a bootable app dev
# server, so it pairs with make.start the way load_testing pairs with
# make.test_load (docs/profile-schema.md, docs/degrade-matrix.md). It must NOT
# key off make.a11y: that ships null by default (the plugin substitutes its
# bundled a11y lane), which would wrongly disable dynamic probing on a repo
# that boots fine.
cap_dynamic_a11y="false"; [[ -n "$make_start" ]] && cap_dynamic_a11y="true"

# --- ci -----------------------------------------------------------------------

ci_provider=""
workflows=()
if [[ -d "$TARGET/.github/workflows" ]]; then
  for wf in "$TARGET"/.github/workflows/*.yml "$TARGET"/.github/workflows/*.yaml; do
    [[ -f "$wf" ]] || continue
    ci_provider="github-actions"
    name="$(sanitize_inline "$(yaml_get "$wf" name)")"
    [[ -z "$name" ]] && name="$(sanitize_inline "$(basename "$wf" | sed -E 's/\.(yml|yaml)$//')")"
    workflows+=("$name")
  done
fi

coderabbit="false"
[[ -f "$TARGET/.coderabbit.yaml" || -f "$TARGET/.coderabbit.yml" ]] && coderabbit="true"

# --- YAML emission ------------------------------------------------------------

# Repo-derived strings (package name, dir names, workflow names, alias keys)
# are untrusted: quote them on emission and strip control characters so they
# cannot inject YAML structure into the profile or break parsing.

# scalar VALUE — emits null when empty (use only for detector-constrained
# values: enums, digit-sanitized versions, ^[A-Za-z0-9_-]+ make targets).
scalar() { if [[ -z "$1" ]]; then printf 'null'; else printf '%s' "$1"; fi; }

# yaml_quote VALUE — double-quoted YAML scalar, \ and " escaped.
yaml_quote() {
  local v=${1//\\/\\\\}
  v=${v//\"/\\\"}
  printf '"%s"' "$v"
}

# qscalar VALUE — quoted scalar, null when empty.
qscalar() { if [[ -z "$1" ]]; then printf 'null'; else yaml_quote "$1"; fi; }

# flow_list ITEM... — ["a", "b"] flow-style list, every item quoted.
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
framework:
  ui: $(scalar "$framework_ui")
  state: $(scalar "$framework_state")
  di: $(scalar "$framework_di")
  router: $(scalar "$framework_router")
  bundler: $(scalar "$framework_bundler")
  package_manager: $(scalar "$framework_pm")
  runtime: $(qscalar "$framework_runtime")
  i18n: $(scalar "$framework_i18n")
  graphql_mock: $(scalar "$framework_graphql_mock")
architecture:
  source_root: $(scalar "$source_root")
  modules: $(flow_list "${modules[@]+"${modules[@]}"}")
  component_prefix: $(scalar "$component_prefix")
  path_aliases: $(flow_list "${path_aliases[@]+"${path_aliases[@]}"}")
make:
  ci: $(scalar "$make_ci")
  start: $(scalar "$make_start")
  start_prod: $(scalar "$make_start_prod")
  build: $(scalar "$make_build")
  lint: $(scalar "$make_lint")
  lint_eslint: $(scalar "$make_lint_eslint")
  lint_tsc: $(scalar "$make_lint_tsc")
  lint_md: $(scalar "$make_lint_md")
  lint_dup: $(scalar "$make_lint_dup")
  lint_metrics: $(scalar "$make_lint_metrics")
  lint_deps: $(scalar "$make_lint_deps")
  format: $(scalar "$make_format")
  test_unit_client: $(scalar "$make_test_unit_client")
  test_unit_server: $(scalar "$make_test_unit_server")
  test_integration: $(scalar "$make_test_integration")
  test_e2e: $(scalar "$make_test_e2e")
  test_visual: $(scalar "$make_test_visual")
  test_mutation: $(scalar "$make_test_mutation")
  merge_mutation_reports: $(scalar "$make_merge_mutation")
  test_load: $(scalar "$make_test_load")
  test_memory_leak: $(scalar "$make_test_memory_leak")
  lighthouse_desktop: $(scalar "$make_lh_desktop")
  lighthouse_mobile: $(scalar "$make_lh_mobile")
  storybook_build: $(scalar "$make_storybook")
  ai_review_loop: $(scalar "$make_ai_review_loop")
  pr_comments: $(scalar "$make_pr_comments")
  fr_nfr_gate: $(scalar "$make_fr_nfr_gate")
  post_review_findings: $(scalar "$make_post_review_findings")
  a11y: $(scalar "$make_a11y")
quality:
  coverage_statements: 100
  coverage_branches: 100
  coverage_functions: 100
  coverage_lines: 100
  mutation_msi: $mutation_msi
  jscpd_clones: 0
  eslint_errors: 0
  eslint_warnings: 0
  tsc_errors: 0
  markdownlint_errors: 0
  depcruise_violations: 0
  metrics_enforced: $metrics_enforced
  visual_diffs: 0
  lighthouse_desktop: 95
  lighthouse_mobile: 85
capabilities:
  visual_testing: $cap_visual
  lighthouse: $cap_lighthouse
  mutation_testing: $cap_mutation
  storybook: $cap_storybook
  load_testing: $cap_load
  memory_leak_testing: $cap_memleak
  figma: false
  observability: false
  accessibility_audit: true
  dynamic_a11y_testing: $cap_dynamic_a11y
  publish_pr_comments: false
ci:
  provider: $(scalar "$ci_provider")
  workflows: $(flow_list "${workflows[@]+"${workflows[@]}"}")
  required_checks: []
review:
  coderabbit: $coderabbit
  ai_review_agents: [claude]
  request_changes_blocking: true
companion:
  skills: ["design-taste-frontend", "frontend-design", "make-interfaces-feel-better", "interaction-design", "oklch-skill"]
  agents: ["accessibility-lead", "aria-specialist", "keyboard-navigator", "contrast-master", "forms-specialist"]
  install_command: "manual"
PROFILE
}

# --- write / diff / refresh (NFR-3) -------------------------------------------

PROFILE_FILE="$TARGET/$SDLC_PROFILE_RELPATH"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
emit_profile >"$tmp"

# Reject symlinked write targets: a committed symlink in a processed
# (untrusted/forked) repo would otherwise let the write follow it and
# create/overwrite a file outside the repo boundary. Refuse a symlinked
# profile file, a non-regular file at the path, and a symlinked .claude dir;
# require the resolved parent dir to live inside $TARGET.
[[ -L "$PROFILE_FILE" ]] && die "profile path is a symlink; refusing to write: $PROFILE_FILE"
[[ -e "$PROFILE_FILE" && ! -f "$PROFILE_FILE" ]] && die "refusing to write profile: $PROFILE_FILE exists but is not a regular file"
PROFILE_DIR="$(dirname "$PROFILE_FILE")"
mkdir -p "$PROFILE_DIR"
[[ -L "$PROFILE_DIR" ]] && die "profile parent (.claude) is a symlink; refusing to write: $PROFILE_DIR"
target_real="$(realpath "$TARGET")" || die "cannot resolve target directory: $TARGET"
dir_real="$(realpath "$PROFILE_DIR")" || die "cannot resolve profile directory: $PROFILE_DIR"
case "$dir_real/" in
  "$target_real"/*) : ;;
  *) die "profile directory escapes the target repo (symlink redirect?): $dir_real" ;;
esac

# Write a temp file in the SAME real directory and mv it into place: the
# in-dir mktemp + mv replaces the destination atomically (a symlinked
# destination is replaced, not followed); chmod restores umask-honoring
# perms that mktemp's 0600 would otherwise clobber. On --refresh we preserve
# the existing file's mode instead.
write_profile() {
  local out mode
  out="$(mktemp "$dir_real/.react-sdlc.yml.XXXXXX")" || die "cannot create temp file in $dir_real"
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
