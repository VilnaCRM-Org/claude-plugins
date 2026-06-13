#!/usr/bin/env bash
# fr-nfr-gate.sh — FR/NFR verification gate: PR comment + commit status
# (architecture §5, feeds FR-6/FR-11).
#
# Usage: fr-nfr-gate.sh [--spec-path PATH] [--impact-context TEXT]
#   --spec-path PATH       requirement specs to verify against (default: specs/)
#   --impact-context TEXT  extra context appended to the verification prompt
#
# Runs the FR/NFR verification prompt through the claude driver (ADR-8
# conventions: --output-format json, .result extraction,
# --permission-mode acceptEdits (the ADR-6 plugin-wide default),
# --max-turns 30, one retry on transport failure — a non-zero exit, an
# is_error=true response, or malformed JSON all count as transport
# failures, shared with ai-review-loop.sh via lib/common.sh). The prompt demands a
# mandatory last line
# 'FR_NFR_NEW_FINDINGS: <n>'. Always posts the 'BMAD FR/NFR Review
# Gate' commit status for HEAD; posts a PR comment carrying the
# findings only when n > 0 (success stays comment-quiet to limit PR
# noise — the status check is the durable signal). Exit 0 = zero new
# findings; anything else (findings, malformed output, transport
# failure after retry) exits 1 with a failure status.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

STATUS_CONTEXT='BMAD FR/NFR Review Gate'
SPEC_PATH="specs/"
IMPACT_CONTEXT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec-path) SPEC_PATH="${2:?--spec-path needs a value}"; shift 2 ;;
    --impact-context) IMPACT_CONTEXT="${2:?--impact-context needs a value}"; shift 2 ;;
    *) die "unknown argument: $1 (usage: fr-nfr-gate.sh [--spec-path PATH] [--impact-context TEXT])" ;;
  esac
done
[[ -e "$SPEC_PATH" ]] || die "spec path not found: $SPEC_PATH (pass --spec-path)"

# Confine --spec-path to the repository: the gate feeds the resolved
# requirement docs into the review prompt, so a path outside the repo
# (absolute, or escaping via '..'/symlink) would route out-of-tree
# context into the gate. Canonicalize both and require containment.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "not inside a git work tree (cannot bound --spec-path)"
repo_root="$(cd "$repo_root" && pwd -P)"
# A symlinked final component would survive dirname-only canonicalization
# and bypass containment (cd -P resolves parents, not the leaf): refuse
# it outright, mirroring inject-governance.sh's symlink policy.
[[ -L "$SPEC_PATH" ]] \
  && die "refusing to follow symlink for --spec-path: $SPEC_PATH"
if [[ -d "$SPEC_PATH" ]]; then
  spec_abs="$(cd "$SPEC_PATH" && pwd -P)"
else
  spec_abs="$(cd "$(dirname "$SPEC_PATH")" && pwd -P)/$(basename "$SPEC_PATH")"
fi
case "$spec_abs" in
  "$repo_root" | "$repo_root"/*) : ;;
  *) die "spec path escapes the repository boundary: $SPEC_PATH (must resolve inside $repo_root)" ;;
esac

command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH"
command -v gh >/dev/null 2>&1 || die "gh CLI not found on PATH"

# repo slug + HEAD sha for the commit status: owner/name from the origin
# remote; gh repo view as fallback (mirrors get-pr-comments.sh — CI
# checkouts and forks may lack an 'origin' remote).
origin="$(git remote get-url origin 2>/dev/null || true)"
repo_slug=""
if [[ -n "$origin" ]]; then
  repo_slug="$(printf '%s\n' "$origin" | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')"
fi
if [[ -z "$repo_slug" ]]; then
  repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
    || die "cannot resolve repository (no origin remote and gh repo view failed)"
fi
[[ -n "$repo_slug" ]] || die "cannot resolve repository (no origin remote and gh repo view failed)"
head_sha="$(git rev-parse HEAD)" || die "cannot resolve HEAD (need at least one commit)"

GATE_PROMPT="Verify this change set against the functional and non-functional requirements documented under '${SPEC_PATH}'. Inspect the repository diff and the requirement documents; report every NEW violation or uncovered requirement introduced by this change as a finding (one bullet per finding, citing the requirement ID)."
if [[ -n "$IMPACT_CONTEXT" ]]; then
  GATE_PROMPT+=" Impact context: ${IMPACT_CONTEXT}."
fi
GATE_PROMPT+=" End your response with the mandatory last line 'FR_NFR_NEW_FINDINGS: <n>' where <n> is the number of new findings (0 when the change set is clean)."

post_status() {
  local state=$1 description=$2
  gh api "repos/${repo_slug}/statuses/${head_sha}" \
    -f state="$state" \
    -f context="$STATUS_CONTEXT" \
    -f description="$description" >/dev/null \
    || log_warn "failed to post commit status to $repo_slug@${head_sha}"
}

post_comment() {
  local body=$1
  local pr
  pr="$(gh pr view --json number --jq .number 2>/dev/null)" || {
    log_warn "no PR found for the current branch; skipping PR comment"
    return 0
  }
  gh pr comment "$pr" --body "$body" >/dev/null \
    || log_warn "failed to post PR comment on #$pr"
}

# --- run the gate (one retry on transport failure, architecture §8) -----------
if ! result="$(claude_run_once "$GATE_PROMPT")"; then
  log_warn "retrying once"
  if ! result="$(claude_run_once "$GATE_PROMPT")"; then
    post_status failure "gate could not run: claude transport failure after retry"
    die "FR/NFR gate failed: claude transport failure after one retry"
  fi
fi

verdict_line="$(printf '%s\n' "$result" | awk 'NF { last = $0 } END { print last }')"
if [[ ! "$verdict_line" =~ ^FR_NFR_NEW_FINDINGS:\ ([0-9]+)$ ]]; then
  post_status failure "gate output malformed: missing FR_NFR_NEW_FINDINGS line"
  die "FR/NFR gate contract violation: expected last line 'FR_NFR_NEW_FINDINGS: <n>', got: $verdict_line"
fi
findings="${BASH_REMATCH[1]}"

printf '%s\n' "$result"

# Zero-test the findings count as a DIGIT STRING, never via bash arithmetic.
# (( findings == 0 )) wraps any exact multiple of 2^64 to 0 (e.g.
# 18446744073709551616 reads as 0), which would post a SUCCESS status for a
# nonzero count — a silent gate escape. Strip leading zeros and compare to
# the literal "0": the only value that means "no findings" (same wrap-safe
# rule validate-profile.sh's num_gt enforces).
findings_norm="${findings#"${findings%%[!0]*}"}"
findings_norm="${findings_norm:-0}"
if [[ "$findings_norm" == "0" ]]; then
  post_status success "zero new FR/NFR findings"
  log_info "FR/NFR gate: PASS — zero new findings"
  exit 0
fi

post_status failure "$findings new FR/NFR finding(s)"
post_comment "## BMAD FR/NFR Review Gate: FAIL

$findings new finding(s) against \`$SPEC_PATH\`:

$result"
log_error "FR/NFR gate: FAIL — $findings new finding(s)"
exit 1
