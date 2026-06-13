#!/usr/bin/env bash
# setup-preflight.sh — environment preflight for /sdlc-setup
# (FR-2, NFR-7, ADR-10).
#
# Usage: setup-preflight.sh [--report]
#
# Checks, in order: git repository, claude CLI >= 2.1, gh CLI >= 2,
# gh authentication, bmalph >= 2.11.0 (ADR-10 floor), `bmalph doctor`
# against an existing `_bmad/` workspace (FR-2; deferred on fresh repos
# where /sdlc-setup runs `bmalph init` right after preflight), a
# YAML toolchain (yq, or python3 with PyYAML — ADR-2), and a JSON
# toolchain (jq or python3) that ai-review-loop.sh, fr-nfr-gate.sh,
# get-pr-comments.sh and generate-profile.sh hard-depend on for parsing
# claude/gh JSON — without it those scripts fail mid-loop with a
# misleading diagnosis instead of at setup.
#
# Default mode aborts on the FIRST failing check, printing its named
# remediation, so /sdlc-setup can halt early with one actionable error.
# --report runs every check and prints the full PASS/FAIL table with a
# remediation per failure. Both modes exit non-zero when anything fails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

REPORT=0
case "${1:-}" in
  --report) REPORT=1 ;;
  '') ;;
  *) die "unknown argument: $1 (usage: setup-preflight.sh [--report])" ;;
esac

FLOOR_CLAUDE="2.1"
FLOOR_GH="2"
FLOOR_BMALPH="2.11.0"

fails=0
results=()

# record STATUS CHECK DETAIL REMEDIATION
# Default mode prints progressively and aborts on the first FAIL;
# --report mode collects rows for the final table.
record() {
  local status=$1 check=$2 detail=$3 remediation=$4
  results+=("${status}|${check}|${detail}|${remediation}")
  if (( REPORT )); then
    if [[ "$status" == FAIL ]]; then
      fails=$((fails + 1))
    fi
    return 0
  fi
  if [[ "$status" == FAIL ]]; then
    printf 'FAIL: %s — %s\n' "$check" "$detail"
    printf 'remediation: %s\n' "$remediation"
    exit 1
  fi
  printf 'PASS: %s — %s\n' "$check" "$detail"
}

# ver_ge ACTUAL FLOOR — true when ACTUAL >= FLOOR (semver-ish, sort -V).
ver_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

extract_version() {
  grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

# check_version CHECK_NAME FLOOR REMEDIATION BINARY [VERSION_ARGS...]
check_version() {
  local name=$1 floor=$2 remediation=$3 binary=$4
  shift 4
  local out ver
  if ! command -v "$binary" >/dev/null 2>&1; then
    record FAIL "$name" "'$binary' not found on PATH" "$remediation"
    return 0
  fi
  if ! out="$("$binary" "$@" 2>/dev/null)"; then
    record FAIL "$name" "'$binary' version probe failed" "$remediation"
    return 0
  fi
  ver="$(printf '%s\n' "$out" | extract_version || true)"
  if [[ -z "$ver" ]]; then
    record FAIL "$name" "cannot parse a version from: $out" "$remediation"
  elif ! ver_ge "$ver" "$floor"; then
    record FAIL "$name" "version $ver below required floor $floor" "$remediation"
  else
    record PASS "$name" "version $ver (floor $floor)" "-"
  fi
}

# --- 1. git repository ------------------------------------------------------
# Compare the printed value, not just the exit code: `git rev-parse
# --is-inside-work-tree` exits 0 while printing `false` inside a bare
# repo or a normal repo's .git/ dir — locations with no work tree where
# /sdlc-setup cannot operate.
if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  record PASS "git-repo" "inside a git work tree" "-"
else
  record FAIL "git-repo" "current directory is not inside a git work tree (bare repo, .git/ dir, or no repository)" \
    "run from inside the target repository (git clone, or git init)"
fi

# --- 2. claude CLI >= 2.1 ----------------------------------------------------
check_version "claude-cli" "$FLOOR_CLAUDE" \
  "install or upgrade the Claude Code CLI to >= $FLOOR_CLAUDE: npm install -g @anthropic-ai/claude-code" \
  claude --version

# --- 3. gh CLI >= 2 ----------------------------------------------------------
check_version "gh-cli" "$FLOOR_GH" \
  "install or upgrade the GitHub CLI to >= $FLOOR_GH: https://cli.github.com" \
  gh --version

# --- 4. gh authentication ----------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  record FAIL "gh-auth" "'gh' not found on PATH" \
    "install the GitHub CLI, then run: gh auth login"
elif gh auth status >/dev/null 2>&1; then
  record PASS "gh-auth" "gh is authenticated" "-"
else
  record FAIL "gh-auth" "gh is not authenticated" "run: gh auth login"
fi

# --- 5. bmalph >= 2.11.0 (ADR-10) ---------------------------------------------
check_version "bmalph" "$FLOOR_BMALPH" \
  "install or upgrade bmalph to >= $FLOOR_BMALPH (ADR-10 compatibility floor)" \
  bmalph --version

# --- 6. bmalph doctor (FR-2) ---------------------------------------------------
# `bmalph doctor` health-checks an existing `_bmad/` workspace so a
# broken/stale bootstrap fails at setup, not mid-loop. On a fresh repo
# there is nothing to examine yet: /sdlc-setup runs `bmalph init` right
# after preflight, so the doctor check is deferred to that bootstrap.
if ! command -v bmalph >/dev/null 2>&1; then
  record FAIL "bmalph-doctor" "'bmalph' not found on PATH" \
    "install bmalph >= $FLOOR_BMALPH, then run: bmalph doctor"
elif [[ ! -d _bmad ]]; then
  record PASS "bmalph-doctor" "fresh repo (no _bmad/) — doctor deferred to post-init" "-"
elif bmalph doctor >/dev/null 2>&1; then
  record PASS "bmalph-doctor" "bmalph doctor reports a healthy _bmad/ workspace" "-"
else
  record FAIL "bmalph-doctor" "bmalph doctor reported issues with the existing _bmad/ workspace" \
    "run 'bmalph doctor' and fix the reported issues, or re-run 'bmalph init'"
fi

# --- 7. YAML toolchain (ADR-2) -------------------------------------------------
if have_yq; then
  record PASS "yaml-toolchain" "yq available" "-"
elif python3 -c 'import yaml' >/dev/null 2>&1; then
  record PASS "yaml-toolchain" "python3 + PyYAML available" "-"
else
  record FAIL "yaml-toolchain" "neither yq nor python3+PyYAML is available" \
    "install yq (https://github.com/mikefarah/yq) or PyYAML (pip install pyyaml)"
fi

# --- 8. JSON toolchain (jq or python3) -----------------------------------------
# ai-review-loop.sh / fr-nfr-gate.sh extract claude's `.result`,
# get-pr-comments.sh normalizes the gh GraphQL payload, and
# generate-profile.sh emits JSON — all need jq OR python3. A machine that
# satisfies the YAML check via yq alone (no python3, no jq) would pass
# preflight yet break those scripts mid-loop, so verify it here.
if command -v jq >/dev/null 2>&1; then
  record PASS "json-toolchain" "jq available" "-"
elif command -v python3 >/dev/null 2>&1; then
  record PASS "json-toolchain" "python3 available" "-"
else
  record FAIL "json-toolchain" "neither jq nor python3 is available" \
    "install jq (https://jqlang.github.io/jq/) or python3"
fi

# --- report table --------------------------------------------------------------
if (( REPORT )); then
  printf '%-16s %-6s %s\n' "CHECK" "RESULT" "DETAIL"
  printf '%-16s %-6s %s\n' "-----" "------" "------"
  for row in "${results[@]}"; do
    IFS='|' read -r status check detail remediation <<<"$row"
    printf '%-16s %-6s %s\n' "$check" "$status" "$detail"
    if [[ "$status" == FAIL ]]; then
      printf '%-16s %-6s remediation: %s\n' "" "" "$remediation"
    fi
  done
  if (( fails > 0 )); then
    log_error "preflight: $fails check(s) failed"
    exit 1
  fi
fi

log_info "preflight OK: all checks passed"
