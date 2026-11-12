#!/usr/bin/env bash
# setup-preflight.sh — check the tool floors and repository preconditions of /rs-sdlc-setup (FR-10).
#
# Usage: setup-preflight.sh [--report]
#
#   --report   run every check; without it the run stops after the first FAIL
#   --help     print this help and exit 0 (accepted in any position)
#
# Runs in the current directory and writes nothing. Prints one line per check,
#   <STATUS>: <check-id>: <detail>[ — remediation: <text>]
# with STATUS one of PASS, WARN, FAIL, INFO, in this order: git-repo, gh,
# gh-auth, claude, claude-restricted, bmalph, bmalph-doctor, python3,
# yaml-backend, json-backend, make, bash, git, template-markers, tracked-tree,
# docker, cargo; then `SUMMARY: pass=<n> warn=<n> fail=<n> info=<n>`.
# Floors: gh 2.0, claude 2.1.248 (--restricted), bmalph 2.11.0 (or absent and
# installable by make bmalph-setup with node 20 and npm), python3 3.11 with
# tomllib, mikefarah yq v4 or python3 with PyYAML, jq or python3, GNU Make 4.0,
# bash 4.4, git 2.30. Missing template markers only WARN (ADR-17); the
# tracked tree, Docker and cargo are INFO. A bash older than 4.4 stops in
# lib/common.sh before the first check.
# Calls: git, gh --version, gh auth status, claude --version, claude --help,
# bmalph --version, bmalph doctor, node --version, npm --version, python3, yq,
# jq, make --version, docker info, command -v cargo.
#
# Exit: 0 no check FAILed; 1 a check FAILed, or bash is older than 4.4; 2 usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

readonly FLOOR_GH=2.0
readonly FLOOR_CLAUDE=2.1.248
readonly FLOOR_BMALPH=2.11.0
readonly FLOOR_NODE=20
readonly FLOOR_PYTHON=3.11
readonly FLOOR_MAKE=4.0
readonly FLOOR_BASH=4.4
readonly FLOOR_GIT=2.30

# The seven A1 marker files; the eighth marker is CI_PREFLIGHT_TARGETS in the
# Makefile starting with validate-configuration (ADR-17).
readonly MARKER_FILES=(rust-toolchain.toml architecture.toml protected-config.toml
  xtask/Cargo.toml make/gates.mk crates/service/Cargo.toml workspace.dsl)

REPORT=0
N_PASS=0
N_WARN=0
N_FAIL=0
N_INFO=0
# Repository root (git top level once git-repo passes, else the working
# directory) and whether the working directory is inside a work tree.
ROOT="$PWD"
IN_REPO=0

# --- output -------------------------------------------------------------------

# clean TEXT — TEXT without control characters (tool and repository output).
clean() {
  printf '%s' "${1//[[:cntrl:]]/}"
}

summary() {
  printf 'SUMMARY: pass=%s warn=%s fail=%s info=%s\n' "$N_PASS" "$N_WARN" "$N_FAIL" "$N_INFO"
}

# emit STATUS CHECK DETAIL [REMEDIATION] — print one check line and count it.
# In the default mode the first FAIL ends the run: summary, then exit 1.
emit() {
  local status="$1" check="$2" detail="$3" remediation="${4-}"
  if [[ -n "$remediation" ]]; then
    printf '%s: %s: %s — remediation: %s\n' "$status" "$check" "$detail" "$remediation"
  else
    printf '%s: %s: %s\n' "$status" "$check" "$detail"
  fi
  case "$status" in
    PASS) N_PASS=$((N_PASS + 1)) ;;
    WARN) N_WARN=$((N_WARN + 1)) ;;
    FAIL) N_FAIL=$((N_FAIL + 1)) ;;
    *) N_INFO=$((N_INFO + 1)) ;;
  esac
  if [[ "$status" == FAIL && "$REPORT" == 0 ]]; then
    summary
    log_error "preflight stopped at the first FAIL ($check); run with --report to see every check"
    exit 1
  fi
}

# --- versions -----------------------------------------------------------------

# first_version TEXT — the first dotted number on TEXT's first line; status 1
# when there is none.
first_version() {
  local line="${1%%$'\n'*}"
  if [[ "$line" =~ ([0-9]+(\.[0-9]+)*) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# version_ge VERSION FLOOR — VERSION >= FLOOR, compared field by field as digit
# strings (a missing field counts as 0), never with shell arithmetic.
version_ge() {
  local a=() b=() i n x y
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  n=${#a[@]}
  if [[ ${#b[@]} -gt $n ]]; then
    n=${#b[@]}
  fi
  for ((i = 0; i < n; i++)); do
    x="${a[i]:-0}"
    y="${b[i]:-0}"
    if num_gt "$x" "$y"; then
      return 0
    fi
    if num_lt "$x" "$y"; then
      return 1
    fi
  done
  return 0
}

# check_floor CHECK TOOL NAME FLOOR VERSION_ARG — PASS when `TOOL VERSION_ARG`
# reports a version >= FLOOR, else FAIL with an install or upgrade remediation.
check_floor() {
  local check="$1" tool="$2" name="$3" floor="$4" arg="$5" out version
  if ! have_cmd "$tool"; then
    emit FAIL "$check" "$tool not found on PATH" "install $name $floor or newer"
    return 0
  fi
  if ! out="$("$tool" "$arg" 2>/dev/null)"; then
    emit FAIL "$check" "$tool $arg failed" "upgrade $name to $floor or newer"
    return 0
  fi
  if ! version="$(first_version "$out")"; then
    emit FAIL "$check" "no version in the output of $tool $arg" "upgrade $name to $floor or newer"
    return 0
  fi
  if ! version_ge "$version" "$floor"; then
    emit FAIL "$check" "$tool $version is below $floor" "upgrade $name to $floor or newer"
    return 0
  fi
  emit PASS "$check" "$tool $version (floor $floor)"
}

# --- repository helpers -------------------------------------------------------------

# makefile_has_target NAME — NAME is a rule target in the Makefile or make/*.mk
# of ROOT (read line by line; make is never run).
makefile_has_target() {
  local name="$1" file line re
  local files=()
  re="^([^:=#[:space:]]+[[:space:]]+)*${name}([[:space:]]+[^:=#[:space:]]+)*[[:space:]]*:([^=]|$)"
  if [[ -f "$ROOT/Makefile" ]]; then
    files+=("$ROOT/Makefile")
  fi
  for file in "$ROOT"/make/*.mk; do
    if [[ -f "$file" ]]; then
      files+=("$file")
    fi
  done
  for file in "${files[@]}"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "${line%$'\r'}" =~ $re ]]; then
        return 0
      fi
    done <"$file"
  done
  return 1
}

# ci_preflight_first — the first word of the Makefile's first
# CI_PREFLIGHT_TARGETS assignment (continuation lines joined, comment dropped);
# status 1 when the Makefile or the assignment is missing.
ci_preflight_first() {
  local file="$ROOT/Makefile" line value="" found=0 first re
  re='^CI_PREFLIGHT_TARGETS[[:space:]]*(::=|:=|[?+]?=)(.*)$'
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$found" == 1 ]]; then
      value+=" $line"
    elif [[ "$line" =~ $re ]]; then
      value="${BASH_REMATCH[2]}"
      found=1
    else
      continue
    fi
    if [[ "$value" == *\\ ]]; then
      value="${value%\\}"
      continue
    fi
    break
  done <"$file"
  if [[ "$found" != 1 ]]; then
    return 1
  fi
  value="${value%%#*}"
  read -r first _ <<<"$value" || true
  printf '%s' "${first-}"
}

# join_list SEP ITEM... — the items joined by SEP.
join_list() {
  local sep="$1" out="" item
  shift
  for item in "$@"; do
    if [[ -n "$out" ]]; then
      out+="$sep"
    fi
    out+="$item"
  done
  printf '%s' "$out"
}

# --- checks, in contract order -------------------------------------------------------

check_git_repo() {
  local out rc=0 top
  if ! have_cmd git; then
    emit FAIL git-repo "git not found on PATH" "install git $FLOOR_GIT or newer"
    return 0
  fi
  # The printed value decides, not the status: rev-parse exits 0 and prints
  # `false` inside .git/ and in a bare repository.
  out="$(git rev-parse --is-inside-work-tree 2>/dev/null)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    out="$(git rev-parse --is-inside-work-tree 2>&1)" || true
  fi
  if [[ "$rc" == 0 && "$out" == true ]]; then
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || top="$PWD"
    ROOT="$top"
    IN_REPO=1
    emit PASS git-repo "inside the work tree $(clean "$top")"
  elif [[ "$rc" == 0 ]]; then
    emit FAIL git-repo "no work tree here (inside .git/ or a bare repository)" \
      "run setup from the work tree of the target repository"
  else
    emit FAIL git-repo "not inside a git work tree ($(clean "${out%%$'\n'*}"))" \
      "run setup from the work tree of the target repository (git clone or git init first)"
  fi
}

check_gh_auth() {
  if ! have_cmd gh; then
    emit FAIL gh-auth "gh not found on PATH" "install GitHub CLI $FLOOR_GH or newer, then run gh auth login"
  elif gh auth status >/dev/null 2>&1; then
    emit PASS gh-auth "gh auth status reports an authenticated account"
  else
    emit FAIL gh-auth "gh auth status reports no authenticated account" "run gh auth login"
  fi
}

check_claude_restricted() {
  if ! have_cmd claude; then
    emit FAIL claude-restricted "claude not found on PATH" "install Claude Code $FLOOR_CLAUDE or newer"
  elif claude_supports_restricted; then
    emit PASS claude-restricted "claude --help lists --restricted"
  else
    emit FAIL claude-restricted "claude --help does not list --restricted" \
      "upgrade Claude Code to $FLOOR_CLAUDE or newer"
  fi
}

check_bmalph() {
  local missing=() out version node_v="" npm_v=""
  if have_cmd bmalph; then
    check_floor bmalph bmalph bmalph "$FLOOR_BMALPH" --version
    return 0
  fi
  if ! makefile_has_target bmalph-setup; then
    missing+=("no bmalph-setup Makefile target")
  fi
  if ! have_cmd node; then
    missing+=("node not found")
  elif ! out="$(node --version 2>/dev/null)" || ! version="$(first_version "$out")"; then
    missing+=("node --version failed")
  elif ! version_ge "$version" "$FLOOR_NODE"; then
    missing+=("node $version is below $FLOOR_NODE")
  else
    node_v="$version"
  fi
  if ! have_cmd npm; then
    missing+=("npm not found")
  elif ! out="$(npm --version 2>/dev/null)"; then
    missing+=("npm --version failed")
  else
    npm_v="$(first_version "$out")" || npm_v="unknown"
  fi
  if [[ ${#missing[@]} -eq 0 ]]; then
    emit WARN bmalph "bmalph not found on PATH; will be installed by make bmalph-setup (node $node_v, npm $npm_v)"
  else
    emit FAIL bmalph "bmalph not found on PATH and not installable by make bmalph-setup: $(join_list ', ' "${missing[@]}")" \
      "install bmalph $FLOOR_BMALPH or newer, or add a bmalph-setup Makefile target and install node $FLOOR_NODE or newer with npm"
  fi
}

check_bmalph_doctor() {
  local out rc=0 first
  if [[ ! -d "$ROOT/_bmad" ]]; then
    emit INFO bmalph-doctor "no _bmad/ yet: bmalph doctor deferred until make bmalph-setup"
    return 0
  fi
  if ! have_cmd bmalph; then
    emit FAIL bmalph-doctor "_bmad/ exists but bmalph is not on PATH, so bmalph doctor cannot run" \
      "install bmalph $FLOOR_BMALPH or newer, then run bmalph doctor"
    return 0
  fi
  out="$(cd "$ROOT" && bmalph doctor 2>&1)" || rc=$?
  if [[ "$rc" == 0 ]]; then
    emit PASS bmalph-doctor "bmalph doctor passed"
    return 0
  fi
  first="$(clean "${out%%$'\n'*}")"
  first="${first:0:200}"
  emit FAIL bmalph-doctor "bmalph doctor exited $rc${first:+: $first}" \
    "run bmalph doctor in the repository root and fix what it reports"
}

check_python() {
  local out version
  if ! have_cmd python3; then
    emit FAIL python3 "python3 not found on PATH" "install Python $FLOOR_PYTHON or newer"
    return 0
  fi
  out="$(python3 --version 2>/dev/null)" || out=""
  if ! version="$(first_version "$out")"; then
    emit FAIL python3 "no version in the output of python3 --version" "install Python $FLOOR_PYTHON or newer"
  elif ! version_ge "$version" "$FLOOR_PYTHON"; then
    emit FAIL python3 "python3 $version is below $FLOOR_PYTHON" "install Python $FLOOR_PYTHON or newer"
  elif ! _sdlc_py -c 'import tomllib' >/dev/null 2>&1; then
    emit FAIL python3 "python3 $version cannot import tomllib" "install Python $FLOOR_PYTHON or newer"
  else
    emit PASS python3 "python3 $version with tomllib (floor $FLOOR_PYTHON)"
  fi
}

check_yaml_backend() {
  local why
  if have_yq; then
    emit PASS yaml-backend "mikefarah yq v4"
  elif have_pyyaml; then
    if [[ "${SDLC_FORCE_PYTHON_YAML:-0}" == 1 ]]; then
      why="SDLC_FORCE_PYTHON_YAML=1"
    elif have_cmd yq; then
      why="the yq on PATH is not mikefarah v4"
    else
      why="no yq on PATH"
    fi
    emit PASS yaml-backend "python3 + PyYAML ($why)"
  else
    emit FAIL yaml-backend "no mikefarah yq v4 and no python3 with PyYAML" \
      "install mikefarah yq v4, or python3 with PyYAML"
  fi
}

check_json_backend() {
  if have_jq; then
    emit PASS json-backend "jq"
  elif have_cmd python3; then
    emit PASS json-backend "python3 (jq not found)"
  else
    emit FAIL json-backend "neither jq nor python3 found" "install jq, or python3"
  fi
}

check_make() {
  local out line version
  if ! have_cmd make; then
    emit FAIL make "make not found on PATH" "install GNU Make $FLOOR_MAKE or newer"
    return 0
  fi
  out="$(make --version 2>/dev/null)" || out=""
  line="$(clean "${out%%$'\n'*}")"
  if [[ "$line" != 'GNU Make '* ]]; then
    emit FAIL make "make is not GNU Make (${line:-no output from make --version})" \
      "install GNU Make $FLOOR_MAKE or newer"
  elif ! version="$(first_version "$line")" || ! version_ge "$version" "$FLOOR_MAKE"; then
    emit FAIL make "GNU Make ${version:-unknown} is below $FLOOR_MAKE" "install GNU Make $FLOOR_MAKE or newer"
  else
    emit PASS make "GNU Make $version (floor $FLOOR_MAKE)"
  fi
}

check_bash() {
  local raw version
  raw="${RUST_SDLC_BASH_VERSION:-${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}}"
  if version="$(first_version "$raw")" && version_ge "$version" "$FLOOR_BASH"; then
    emit PASS bash "bash $version (floor $FLOOR_BASH)"
  else
    emit FAIL bash "bash $(clean "$raw") is below $FLOOR_BASH" "install Bash $FLOOR_BASH or newer"
  fi
}

check_template_markers() {
  local file first missing=()
  for file in "${MARKER_FILES[@]}"; do
    if [[ ! -f "$ROOT/$file" ]]; then
      missing+=("$file")
    fi
  done
  first="$(ci_preflight_first)" || first=""
  if [[ "$first" != validate-configuration ]]; then
    missing+=("CI_PREFLIGHT_TARGETS starting with validate-configuration")
  fi
  if [[ ${#missing[@]} -eq 0 ]]; then
    emit PASS template-markers "all 8 template markers present (template-derived)"
  else
    emit WARN template-markers "missing $(join_list ', ' "${missing[@]}") (not template-derived: capabilities off)"
  fi
}

check_tracked_tree() {
  local out line files=()
  if [[ "$IN_REPO" != 1 ]]; then
    emit INFO tracked-tree "not checked (not inside a git work tree)"
    return 0
  fi
  if ! out="$(git -C "$ROOT" --no-optional-locks status --porcelain --untracked-files=no 2>/dev/null)"; then
    emit INFO tracked-tree "not checked (git status failed)"
    return 0
  fi
  if [[ -z "$out" ]]; then
    emit INFO tracked-tree "clean (no tracked changes)"
    return 0
  fi
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      files+=("$(clean "${line:3}")")
    fi
  done <<<"$out"
  emit INFO tracked-tree "tracked changes: $(join_list ', ' "${files[@]}")"
}

check_docker() {
  if ! have_cmd docker; then
    emit INFO docker "unreachable (docker not found on PATH)"
  elif docker info >/dev/null 2>&1; then
    emit INFO docker "reachable"
  else
    emit INFO docker "unreachable (docker info failed)"
  fi
}

check_cargo() {
  if have_cmd cargo; then
    emit INFO cargo "present (host toolchain)"
  else
    emit INFO cargo "absent (no host toolchain)"
  fi
}

# --- main ---------------------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done
while (($#)); do
  case "$1" in
    --report) REPORT=1 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
  shift
done

check_git_repo
check_floor gh gh "GitHub CLI" "$FLOOR_GH" --version
check_gh_auth
check_floor claude claude "Claude Code" "$FLOOR_CLAUDE" --version
check_claude_restricted
check_bmalph
check_bmalph_doctor
check_python
check_yaml_backend
check_json_backend
check_make
check_bash
check_floor git git git "$FLOOR_GIT" --version
check_template_markers
check_tracked_tree
check_docker
check_cargo

summary
if [[ "$N_FAIL" != 0 ]]; then
  log_error "preflight: $N_FAIL check(s) FAILed"
  exit 1
fi
log_info "preflight: no FAIL"
