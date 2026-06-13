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
# NFR-6). The v1 agent matrix is claude-only: other agents warn+skip,
# but a run where NO supported agent ran exits non-zero — an
# all-skipped matrix produces no verdict and must not pass silently.
#
# Fault contract (architecture §8): a non-zero claude exit, an
# is_error=true response, or malformed JSON gets exactly ONE retry, then
# counts as a failed iteration. A well-formed FAIL verdict is not
# retried. A missing verdict line is an ADR-8 contract violation and
# counts as a failed iteration directly.
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
# Bound the value BEFORE it reaches the C-style loop. A 19+ digit input
# (e.g. 9999999999999999999999) survives the regex above, then bash
# arithmetic in `for (( ... <= MAX_ITERATIONS ))` wraps it modulo 2^64:
# ~1.8 quintillion iterations (runaway), or a 2^63 value wraps negative
# so the loop runs ZERO times and escalates without reviewing. Reject
# anything above a sane ceiling using a wrap-safe digit-string compare
# (length, then lexicographic) — never bash arithmetic, mirroring
# validate-profile.sh's num_gt. The cap is far below the documented
# default (5, NFR-6) yet generous for any real review loop.
MAX_ITERATIONS_CEILING=1000
if num_gt "$MAX_ITERATIONS" "$MAX_ITERATIONS_CEILING"; then
  die "--max-iterations must not exceed $MAX_ITERATIONS_CEILING, got: $MAX_ITERATIONS"
fi

# --- agent list: --agents override, else profile, else claude ---------------
agents=()
if [[ -n "$AGENTS_OVERRIDE" ]]; then
  IFS=', ' read -r -a agents <<<"$AGENTS_OVERRIDE"
else
  # shellcheck disable=SC2119  # profile_path's TARGET_REPO_DIR arg is optional
  profile="$(profile_path)"
  if [[ -f "$profile" ]]; then
    # Guard the read with yaml_parses so a malformed profile fails with one
    # clean [php-sdlc] diagnostic naming the bad file, instead of letting
    # yaml_get_list's backend dump a raw ~30-line PyYAML traceback (or a yq
    # error) and then silently degrading to the default 'claude' agent
    # (a hidden misconfiguration). This loop is reachable standalone via
    # code-review/SKILL.md and `make ai-review-loop` without a preceding
    # validate-profile step, so it must self-diagnose. Mirrors the guard
    # validate-profile.sh and get-pr-comments.sh already carry.
    yaml_parses "$profile" \
      || die "profile is not valid YAML: $profile (fix the syntax or regenerate it with /sdlc-setup, or pass --agents to bypass the profile)"
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

REVIEW_PROMPT="${REVIEW_PROMPT:-Review the working tree changes of this repository (git diff against ${DIFF_BASE}) for correctness, security, maintainability, FR/NFR coverage, and code health: system design tradeoffs, appropriate design pattern use, code smells, SOLID/DRY/KISS, DDD/CQRS, Hexagonal Architecture, and repository rules. Keep findings concrete and scoped to changed code or directly affected behavior. Apply safe fixes directly. End your response with the mandatory verdict line: 'AI_REVIEW_VERDICT: PASS' if the changes are acceptable, otherwise 'AI_REVIEW_VERDICT: FAIL'.}"

overall_fail=0
ran_any=0
for agent in "${agents[@]}"; do
  if [[ "$agent" != "claude" ]]; then
    log_warn "agent '$agent' is not supported in v1 (claude-only matrix, ADR-8); skipping"
    continue
  fi
  ran_any=1
  command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH"

  passed=0
  for (( iteration = 1; iteration <= MAX_ITERATIONS; iteration++ )); do
    log_info "agent claude: review iteration $iteration/$MAX_ITERATIONS (diff base: $DIFF_BASE)"
    # One retry on transport-level failure (architecture §8).
    if ! result="$(claude_run_once "$REVIEW_PROMPT")"; then
      log_warn "retrying once (iteration $iteration)"
      if ! result="$(claude_run_once "$REVIEW_PROMPT")"; then
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

# A run where every configured agent was skipped (no supported agent ran)
# is a failure, not a silent success: it produced no review verdict.
if (( ! ran_any )); then
  die "no supported review agent ran (v1 supports only 'claude', ADR-8); configure 'claude' in review.ai_review_agents or pass --agents claude"
fi

exit "$overall_fail"
