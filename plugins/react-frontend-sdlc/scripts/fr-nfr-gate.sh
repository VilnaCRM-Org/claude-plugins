#!/usr/bin/env bash
# fr-nfr-gate.sh — FR/NFR verification gate: PR comment + commit status
# (architecture §5, feeds FR-6/FR-11).
#
# Usage: fr-nfr-gate.sh [--spec-path PATH] [--pr N] [--impact-context TEXT]
#   --spec-path PATH       BMAD spec bundle to verify against (optional)
#   --pr N                 PR whose description and linked (closing) issues
#                          supply requirements (default: the current branch's
#                          PR, when one exists)
#   --impact-context TEXT  extra context appended to the verification prompt
#
# The gate is mandatory for EVERY pull request, not only spec-planned ones.
# Requirement sources, all used when present: the spec bundle, the PR
# description, the PR's linked issues, and — always — the baseline frontend
# NFR catalog that applies to every change. With neither a spec bundle nor a
# PR description / linked issue to derive functional requirements from, the
# gate fails closed (failure status, exit 1): it never passes a change it
# could not trace to a requirement.
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
# noise — the status check is the durable signal, so a status post
# that fails is itself fatal). Exit 0 = zero new findings with the
# success status recorded; anything else (findings, malformed output,
# transport failure after retry, an unpostable status) exits 1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

STATUS_CONTEXT='BMAD FR/NFR Review Gate'
SPEC_PATH=""
PR=""
IMPACT_CONTEXT=""
# Linked-issue and PR text is bounded so one oversized issue cannot crowd the
# change set out of the verification prompt.
REQ_TEXT_LIMIT=30000
while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec-path) SPEC_PATH="${2:?--spec-path needs a value}"; shift 2 ;;
    --pr) PR="${2:?--pr needs a value}"; shift 2 ;;
    --impact-context) IMPACT_CONTEXT="${2:?--impact-context needs a value}"; shift 2 ;;
    *) die "unknown argument: $1 (usage: fr-nfr-gate.sh [--spec-path PATH] [--pr N] [--impact-context TEXT])" ;;
  esac
done
[[ -z "$PR" || "$PR" =~ ^[1-9][0-9]*$ ]] || die "--pr must be a PR number, got: $PR"
if [[ -n "$SPEC_PATH" ]]; then
  [[ -e "$SPEC_PATH" ]] || die "spec path not found: $SPEC_PATH (pass an existing --spec-path, or omit it to gate against the PR and its linked issues)"

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
fi

command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH"
command -v gh >/dev/null 2>&1 || die "gh CLI not found on PATH"

# repo slug + HEAD sha for the commit status: resolve_repo_slug (lib/common.sh)
# reads owner/name from the origin remote with a gh repo view fallback — one
# shared implementation with get-pr-comments.sh so CI checkouts and forks that
# lack an 'origin' remote behave identically across gates.
repo_slug="$(resolve_repo_slug)" \
  || die "cannot resolve repository (no origin remote and gh repo view failed)"
head_sha="$(git rev-parse HEAD)" || die "cannot resolve HEAD (need at least one commit)"

post_status() {
  local state=$1 description=$2
  gh api "repos/${repo_slug}/statuses/${head_sha}" \
    -f state="$state" \
    -f context="$STATUS_CONTEXT" \
    -f description="$description" >/dev/null \
    || die "failed to post commit status to $repo_slug@${head_sha} (the status check is the gate's durable verdict; restore gh access and re-run)"
}

# --- requirement sources beyond the spec bundle -------------------------------
# The PR description and its linked issues carry the functional requirements of
# a change that was never BMAD-planned; they are read for every PR so the gate
# reviews all of them. A PR that cannot be resolved is not an error by itself —
# the no-requirement-source check below decides.
if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq .number 2>/dev/null)" || PR=""
  [[ "$PR" =~ ^[1-9][0-9]*$ ]] || PR=""
fi
PR_TEXT=""
ISSUES_TEXT=""
if [[ -n "$PR" ]]; then
  pr_body="$(gh pr view "$PR" --repo "$repo_slug" --json body --jq '.body // ""')" \
    || die "cannot read PR #$PR in $repo_slug (the PR description is a requirement source)"
  pr_title="$(gh pr view "$PR" --repo "$repo_slug" --json title --jq '.title // ""')" \
    || die "cannot read PR #$PR in $repo_slug"
  if [[ -n "${pr_body//[[:space:]]/}" ]]; then
    PR_TEXT="PR #${PR} — ${pr_title}"$'\n'"${pr_body}"
  fi
  issue_numbers="$(gh pr view "$PR" --repo "$repo_slug" --json closingIssuesReferences \
    --jq '.closingIssuesReferences[]?.number')" \
    || die "cannot list the issues linked to PR #$PR in $repo_slug"
  for n in $issue_numbers; do
    [[ "$n" =~ ^[1-9][0-9]*$ ]] || continue
    issue="$(gh issue view "$n" --repo "$repo_slug" --json title,body \
      --jq '"Issue #'"$n"' — \(.title)\n\(.body // "")"')" \
      || die "cannot read issue #$n linked to PR #$PR in $repo_slug"
    if [[ -n "${issue//[[:space:]]/}" ]]; then
      ISSUES_TEXT+="${issue}"$'\n\n'
    fi
  done
fi

if [[ -z "$SPEC_PATH" && -z "$PR_TEXT" && -z "$ISSUES_TEXT" ]]; then
  post_status failure "no requirement source: add specs/<slug>/, a PR description or a linked issue"
  die "FR/NFR gate cannot trace this change to any requirement: no spec bundle (--spec-path), no PR description and no linked issue${PR:+ on PR #$PR}. Link the issue (Closes #N) or write the acceptance criteria into the PR description, then re-run — the gate is mandatory for every PR and fails closed."
fi

sources=()
[[ -n "$SPEC_PATH" ]] && sources+=("the BMAD spec bundle under '${SPEC_PATH}'")
[[ -n "$PR_TEXT" ]] && sources+=("the pull request description")
[[ -n "$ISSUES_TEXT" ]] && sources+=("the linked issue(s)")
sources_text="$(IFS=';'; printf '%s' "${sources[*]}")"
sources_text="${sources_text//;/, }"

GATE_PROMPT="Verify this React frontend change set against its functional and non-functional requirements, taken from: ${sources_text}. Inspect the repository diff and every requirement source; derive an ID for each requirement that has none (FR-PR-<n> for the PR description, FR-<issue>-<n> for an issue's acceptance criteria). Report every NEW violation or uncovered requirement introduced by this change as a finding (one bullet per finding, citing the requirement ID). Cover both functional behavior (component contracts, user journeys, forms and validation, routing, state, i18n) and the frontend non-functional requirements the sources assert (accessibility/WCAG, performance and Lighthouse budgets, visual fidelity, responsive layout, and bundle/render cost)."
GATE_PROMPT+=" Always also verify the baseline NFR catalog that applies to every frontend PR whatever the sources say: NFR-BASE-A11Y accessibility (WCAG 2.2 AA: semantics, labels, keyboard, focus, contrast); NFR-BASE-TEST changed behavior covered by unit/integration/E2E tests; NFR-BASE-QUALITY no lint/type suppressions and no lowered quality thresholds; NFR-BASE-SEC no secrets and no unsafe HTML rendering; NFR-BASE-I18N no hard-coded user-facing strings where locale files exist; NFR-BASE-PERF no avoidable bundle or render-cost regression; NFR-BASE-UIKIT every new UI component that the UI kit does not already provide ships with a Storybook story (states and variants) and pages/features compose such components instead of inlining one-off markup."
if [[ -n "$PR_TEXT" ]]; then
  GATE_PROMPT+=" Pull request description (requirement source): <<<${PR_TEXT:0:REQ_TEXT_LIMIT}>>>."
fi
if [[ -n "$ISSUES_TEXT" ]]; then
  GATE_PROMPT+=" Linked issue(s) (requirement source): <<<${ISSUES_TEXT:0:REQ_TEXT_LIMIT}>>>."
fi
if [[ -n "$IMPACT_CONTEXT" ]]; then
  GATE_PROMPT+=" Impact context: ${IMPACT_CONTEXT}."
fi
GATE_PROMPT+=" End your response with the mandatory last line 'FR_NFR_NEW_FINDINGS: <n>' where <n> is the number of new findings (0 when the change set is clean)."

post_comment() {
  local body=$1
  local pr=$PR
  if [[ -z "$pr" ]]; then
    log_warn "no PR found for the current branch; skipping PR comment"
    return 0
  fi
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
# nonzero count — a silent gate escape. strip_zeros (lib/common.sh) is the one
# shared, wrap-safe normalizer so every gate stays on the same verified path.
findings_norm="$(strip_zeros "$findings")"
if [[ "$findings_norm" == "0" ]]; then
  post_status success "zero new FR/NFR findings"
  log_info "FR/NFR gate: PASS — zero new findings"
  exit 0
fi

post_status failure "$findings new FR/NFR finding(s)"
post_comment "## BMAD FR/NFR Review Gate: FAIL

$findings new finding(s) against ${sources_text}:

$result"
log_error "FR/NFR gate: FAIL — $findings new finding(s)"
exit 1
