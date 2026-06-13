#!/usr/bin/env bash
# common.sh — shared helpers for php-backend-sdlc plugin scripts.
#
# Source this file, do not execute it. Plugin script convention:
#   set -euo pipefail
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh"
#
# YAML access uses yq when available and falls back to python3 + PyYAML
# (ADR-2). SDLC_FORCE_PYTHON_YAML=1 forces the fallback; tests use it to
# exercise the yq-absent code path on machines where yq is installed.

# Helpers assume they run in the caller's shell, and `die` must terminate
# a script — not an interactive session — so refuse direct execution.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "common.sh is a library; source it instead of executing" >&2
  exit 64
fi

# --- logging -----------------------------------------------------------

log_info()  { printf '[php-sdlc][INFO] %s\n' "$*"; }
log_warn()  { printf '[php-sdlc][WARN] %s\n' "$*" >&2; }
log_error() { printf '[php-sdlc][ERROR] %s\n' "$*" >&2; }

die() {
  log_error "$*"
  exit 1
}

# --- wrap-safe non-negative integer comparison --------------------------
# NEVER compare these magnitudes with bash arithmetic: (( )) wraps values
# >= 2^63 to negative (18446744073709551615 reads as -1) and exact
# multiples of 2^64 to 0, which would let a crafted huge value pass a
# raise-only quality ceiling (ADR-7), a findings count, or a loop bound.
# Compare as digit strings instead — by length, then lexicographically.

# strip_zeros VALUE — drop leading zeros ('007' -> '7', '000' -> '0') so
# magnitude comparison can go by digit-string length.
strip_zeros() {
  local v=$1
  v="${v#"${v%%[!0]*}"}"
  printf '%s' "${v:-0}"
}

# num_gt A B — true when A > B for non-negative decimal integer strings.
num_gt() {
  local a b
  a="$(strip_zeros "$1")"
  b="$(strip_zeros "$2")"
  if (( ${#a} != ${#b} )); then
    (( ${#a} > ${#b} ))
  else
    [[ "$a" > "$b" ]]
  fi
}

# num_lt A B — true when A < B (same wrap-safe digit-string comparison).
num_lt() { num_gt "$2" "$1"; }

# --- plugin root resolution (ADR-4) -------------------------------------

# Claude Code sets ${CLAUDE_PLUGIN_ROOT} when invoking plugin scripts from
# the install cache. Fall back to deriving the root from this file's
# location so bats suites and direct repo checkouts work identically.
resolve_plugin_root() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    if [[ ! -d "$CLAUDE_PLUGIN_ROOT" ]]; then
      die "CLAUDE_PLUGIN_ROOT points to a missing directory: $CLAUDE_PLUGIN_ROOT"
    fi
    printf '%s\n' "$CLAUDE_PLUGIN_ROOT"
    return 0
  fi
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  (cd "$lib_dir/../.." && pwd)
}

# --- YAML access (ADR-2: yq with python3+PyYAML fallback) ----------------

have_yq() {
  [[ "${SDLC_FORCE_PYTHON_YAML:-0}" != "1" ]] && command -v yq >/dev/null 2>&1
}

# Preflight helper: at least one YAML backend must be present.
require_yaml_toolchain() {
  if ! have_yq && ! python3 -c 'import yaml' >/dev/null 2>&1; then
    die "no YAML toolchain: install yq, or python3 with PyYAML"
  fi
}

# yaml_parses FILE — exit 0 when FILE is syntactically valid YAML. Backend
# parse diagnostics (yq errors, PyYAML tracebacks) are suppressed so callers
# can fail with their own clean, remediation-bearing message instead of a
# raw traceback from set -e killing the script mid-yaml_get.
yaml_parses() {
  local file=$1
  [[ -f "$file" ]] || die "yaml_parses: no such file: $file"
  if have_yq; then
    yq '.' "$file" >/dev/null 2>&1
  else
    python3 -c 'import sys, yaml
yaml.safe_load(open(sys.argv[1]))' "$file" >/dev/null 2>&1
  fi
}

# yaml_get FILE DOTTED.PATH
# Prints the scalar at DOTTED.PATH ('' when absent or null). Booleans are
# normalized to true/false in both backends; lists print one item per line
# (prefer yaml_get_list for those).
yaml_get() {
  local file=$1 keypath=$2
  [[ -f "$file" ]] || die "yaml_get: no such file: $file"
  if have_yq; then
    # NOT `// ""`: yq's alternative operator treats false like null, so an
    # explicit `false` would read back as '' and diverge from the python
    # backend. select() drops only null/absent and keeps booleans intact.
    yq ".${keypath} | select(. != null)" "$file"
  else
    python3 - "$file" "$keypath" <<'PYEOF'
import sys, yaml

cur = yaml.safe_load(open(sys.argv[1])) or {}
for part in sys.argv[2].split('.'):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        cur = None
        break
if cur is None:
    print("")
elif isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, list):
    for item in cur:
        print(item)
else:
    print(cur)
PYEOF
  fi
}

# yaml_get_list FILE DOTTED.PATH — one list item per line, '' when absent.
yaml_get_list() {
  local file=$1 keypath=$2
  [[ -f "$file" ]] || die "yaml_get_list: no such file: $file"
  if have_yq; then
    yq "(.${keypath} // [])[]" "$file"
  else
    yaml_get "$file" "$keypath"
  fi
}

# yaml_is_list FILE DOTTED.PATH — exit 0 when the value at PATH is a YAML
# sequence (list). A scalar, mapping, null, or absent key all exit 1, so
# callers can reject scalars that would otherwise read back non-empty via
# yaml_get (e.g. a single bounded context written as a bare string).
yaml_is_list() {
  local file=$1 keypath=$2
  [[ -f "$file" ]] || die "yaml_is_list: no such file: $file"
  if have_yq; then
    [[ "$(yq ".${keypath} | type" "$file" 2>/dev/null)" == "!!seq" ]]
  else
    python3 - "$file" "$keypath" <<'PYEOF'
import sys, yaml

cur = yaml.safe_load(open(sys.argv[1])) or {}
for part in sys.argv[2].split('.'):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(1)
sys.exit(0 if isinstance(cur, list) else 1)
PYEOF
  fi
}

# yaml_has FILE DOTTED.PATH — exit 0 when the key EXISTS, even with a null
# value. Distinct from yaml_get returning '': the profile schema gives
# `make.<key>: null` capability-absent semantics (NFR-4), so callers need
# to tell "explicitly null" apart from "not declared".
yaml_has() {
  local file=$1 keypath=$2
  [[ -f "$file" ]] || die "yaml_has: no such file: $file"
  if have_yq; then
    local parent leaf
    if [[ "$keypath" == *.* ]]; then
      parent=".${keypath%.*}"
      leaf="${keypath##*.}"
    else
      parent="."
      leaf="$keypath"
    fi
    [[ "$(yq "${parent} | has(\"${leaf}\")" "$file" 2>/dev/null)" == "true" ]]
  else
    python3 - "$file" "$keypath" <<'PYEOF'
import sys, yaml

cur = yaml.safe_load(open(sys.argv[1])) or {}
parts = sys.argv[2].split('.')
for part in parts[:-1]:
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(1)
sys.exit(0 if isinstance(cur, dict) and parts[-1] in cur else 1)
PYEOF
  fi
}

# --- claude -p JSON driver (ADR-8) ---------------------------------------
#
# The canonical `claude -p --output-format json` shape is a top-level
# `.result` string plus an `.is_error` bool. Shared by ai-review-loop.sh
# and fr-nfr-gate.sh so the transport-failure contract (architecture §8:
# exactly one retry on a non-zero exit, malformed JSON, OR an is_error=true
# response) stays identical in both loops.

# claude_is_error JSON — exit 0 when the JSON reports `.is_error == true`.
# claude can exit 0 while setting is_error=true with `.result` holding an
# error string (e.g. 'API Error: 529 Overloaded'); that is a transport
# failure, not reviewer output, and must take the retry path.
claude_is_error() {
  local json=$1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -e '.is_error == true' >/dev/null 2>&1
  else
    printf '%s' "$json" | python3 -c '
import json, sys
try:
    sys.exit(0 if json.load(sys.stdin).get("is_error") is True else 1)
except Exception:
    sys.exit(1)' >/dev/null 2>&1
  fi
}

# claude_extract_result JSON -> .result string ('' when JSON is malformed)
claude_extract_result() {
  local json=$1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r '.result // empty' 2>/dev/null || true
  else
    printf '%s' "$json" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("result") or "")
except Exception:
    pass' 2>/dev/null || true
  fi
}

# claude_run_once PROMPT -> prints .result on stdout; returns 1 on a
# non-zero claude exit, an is_error=true response, OR malformed JSON
# (all three are transport-level failures that earn one retry).
claude_run_once() {
  local prompt=$1 raw result
  if ! raw="$(claude -p "$prompt" --output-format json \
              --permission-mode acceptEdits --max-turns 30)"; then
    log_warn "claude exited non-zero"
    return 1
  fi
  if claude_is_error "$raw"; then
    log_warn "claude reported is_error (transport failure)"
    return 1
  fi
  result="$(claude_extract_result "$raw")"
  if [[ -z "$result" ]]; then
    log_warn "malformed JSON from claude (no .result)"
    return 1
  fi
  printf '%s\n' "$result"
}

# --- project profile helpers (architecture §4) ---------------------------

# Canonical profile location inside the target repository.
SDLC_PROFILE_RELPATH=".claude/php-sdlc.yml"

# profile_path [TARGET_REPO_DIR] — canonical profile path (default: $PWD).
profile_path() {
  printf '%s/%s\n' "${1:-$PWD}" "$SDLC_PROFILE_RELPATH"
}

# profile_get PROFILE_FILE DOTTED.KEY [DEFAULT]
profile_get() {
  local file=$1 key=$2 default=${3:-}
  local val
  val="$(yaml_get "$file" "$key")"
  if [[ -n "$val" ]]; then
    printf '%s\n' "$val"
  else
    printf '%s\n' "$default"
  fi
}

# profile_require PROFILE_FILE DOTTED.KEY — value, or die naming the key.
profile_require() {
  local file=$1 key=$2
  local val
  val="$(yaml_get "$file" "$key")"
  if [[ -z "$val" ]]; then
    die "profile: required key '$key' missing or empty in $file"
  fi
  printf '%s\n' "$val"
}
