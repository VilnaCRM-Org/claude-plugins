#!/usr/bin/env bash
# ai-review-loop.sh — generalized AI review loop, claude driver (ADR-8).
#
# Usage: ai-review-loop.sh [--agents LIST] [--max-iterations N] [--diff-base REF]
#
# For each agent in review.ai_review_agents (profile), or in the
# comma/space-separated --agents override: run
#   claude -p "$REVIEW_PROMPT" --output-format json \
#     --permission-mode acceptEdits --max-turns 30
# extract .result, and parse the mandatory last-line verdict
# 'AI_REVIEW_VERDICT: PASS|FAIL'. FAIL re-reviews (acceptEdits lets the
# reviewer apply fixes) until PASS or --max-iterations (default 5,
# NFR-6). The v1 agent matrix is claude-only: other agents warn+skip.
#
# Fault contract (architecture §8): a non-zero claude exit or malformed
# JSON gets exactly ONE retry, then counts as a failed iteration. A
# well-formed FAIL verdict is not retried. A missing verdict line is an
# ADR-8 contract violation and counts as a failed iteration directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

AGENTS_OVERRIDE=""
MAX_ITERATIONS=5
DIFF_BASE="main"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents)         AGENTS_OVERRIDE="${2:?--agents needs a value}"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="${2:?--max-iterations needs a value}"; shift 2 ;;
    --diff-base)      DIFF_BASE="${2:?--diff-base needs a value}"; shift 2 ;;
    *) die "unknown argument: $1 (usage: ai-review-loop.sh [--agents LIST] [--max-iterations N] [--diff-base REF])" ;;
  esac
done
[[ "$MAX_ITERATIONS" =~ ^[1-9][0-9]*$ ]] \
  || die "--max-iterations must be a positive integer, got: $MAX_ITERATIONS"

# --- agent list: --agents override, else profile, else claude ---------------
agents=()
if [[ -n "$AGENTS_OVERRIDE" ]]; then
  IFS=', ' read -r -a agents <<<"$AGENTS_OVERRIDE"
else
  profile="$(profile_path)"
  if [[ -f "$profile" ]]; then
    mapfile -t agents < <(yaml_get_list "$profile" review.ai_review_agents)
  fi
fi
# drop empty entries; default to claude
filtered=()
for a in "${agents[@]+"${agents[@]}"}"; do
  [[ -n "$a" ]] && filtered+=("$a")
done
agents=("${filtered[@]+"${filtered[@]}"}")
[[ "${#agents[@]}" -eq 0 ]] && agents=(claude)

REVIEW_PROMPT="${REVIEW_PROMPT:-Review the working tree changes of this repository (git diff against ${DIFF_BASE}) for correctness, security, and maintainability. Apply safe fixes directly. End your response with the mandatory verdict line: 'AI_REVIEW_VERDICT: PASS' if the changes are acceptable, otherwise 'AI_REVIEW_VERDICT: FAIL'.}"

# extract_result JSON -> .result string ('' when JSON is malformed)
extract_result() {
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

# run_claude_once -> prints .result; return 1 on non-zero exit or malformed JSON
run_claude_once() {
  local raw result
  if ! raw="$(claude -p "$REVIEW_PROMPT" --output-format json \
              --permission-mode acceptEdits --max-turns 30)"; then
    log_warn "claude exited non-zero"
    return 1
  fi
  result="$(extract_result "$raw")"
  if [[ -z "$result" ]]; then
    log_warn "malformed JSON from claude (no .result)"
    return 1
  fi
  printf '%s\n' "$result"
}

overall_fail=0
for agent in "${agents[@]}"; do
  if [[ "$agent" != "claude" ]]; then
    log_warn "agent '$agent' is not supported in v1 (claude-only matrix, ADR-8); skipping"
    continue
  fi
  command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH"

  passed=0
  for (( iteration = 1; iteration <= MAX_ITERATIONS; iteration++ )); do
    log_info "agent claude: review iteration $iteration/$MAX_ITERATIONS (diff base: $DIFF_BASE)"
    # One retry on transport-level failure (architecture §8).
    if ! result="$(run_claude_once)"; then
      log_warn "retrying once (iteration $iteration)"
      if ! result="$(run_claude_once)"; then
        log_warn "retry failed too; counting iteration $iteration as failed"
        continue
      fi
    fi
    printf '%s\n' "$result"
    verdict="$(printf '%s\n' "$result" | awk 'NF { last = $0 } END { print last }')"
    case "$verdict" in
      'AI_REVIEW_VERDICT: PASS')
        log_info "agent claude: PASS on iteration $iteration"
        passed=1
        break
        ;;
      'AI_REVIEW_VERDICT: FAIL')
        log_info "agent claude: FAIL verdict — re-reviewing"
        ;;
      *)
        log_warn "missing or malformed AI_REVIEW_VERDICT last line (ADR-8 contract); counting iteration as failed"
        ;;
    esac
  done
  if (( ! passed )); then
    log_error "agent claude: no PASS within $MAX_ITERATIONS iterations — escalate"
    overall_fail=1
  fi
done

exit "$overall_fail"
