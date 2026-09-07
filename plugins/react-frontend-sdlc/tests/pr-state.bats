#!/usr/bin/env bats
# Tests for scripts/pr-state.sh — the finishing-state sensor behind the
# fe-sdlc-pr-until-green workflow.
#
# The script makes four gh calls per snapshot (pr view, reviews, issue
# comments, and the GraphQL thread query made by get-pr-comments.sh). The
# generated gh wrapper routes each to a fixture chosen by environment
# variable, so every verdict is pinned against a known PR shape.
# SDLC_NOW_EPOCH pins "now".

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/pr-state.sh"
  FX="$BATS_TEST_DIRNAME/fixtures/gh/pr-state"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK/bin"
  cd "$WORK"
  git init -q
  git remote add origin https://github.com/acme/stub-frontend.git
  export GH_LOG="$WORK/gh.log"
  export GH_CALLS="$WORK/pr-view-calls"
  export GH_PR_FIXTURE="$FX/pr-open-green.json"
  export GH_PR_FIXTURE_2=""
  export GH_REVIEWS_FIXTURE="$FX/reviews-approved.ndjson"
  export GH_COMMENTS_FIXTURE="$FX/comments-quiet.ndjson"
  export GH_THREADS_FIXTURE="$FX/threads-empty.json"
  export GH_PUSHED_AT=""
  cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$GH_LOG"
case "$1 $2 ${3:-}" in
  "pr view --json") echo 7 ;;
  "pr view 7")
    n=$(( $(cat "$GH_CALLS" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$GH_CALLS"
    if [[ -n "$GH_PR_FIXTURE_2" && "$n" -gt 1 ]]; then cat "$GH_PR_FIXTURE_2"; else cat "$GH_PR_FIXTURE"; fi ;;
  "api repos/acme/stub-frontend/pulls/7/reviews?per_page=100 --paginate") cat "$GH_REVIEWS_FIXTURE" ;;
  "api repos/acme/stub-frontend/issues/7/comments?per_page=100 --paginate") cat "$GH_COMMENTS_FIXTURE" ;;
  "api graphql -f") cat "$GH_THREADS_FIXTURE" ;;
  "api repos/acme/stub-frontend/commits/a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2/check-suites?per_page=100 --jq")
    [[ -n "$GH_PUSHED_AT" ]] && printf '"%s"\n' "$GH_PUSHED_AT" ;;
  *) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
EOF
  chmod +x "$WORK/bin/gh"
  PATH="$WORK/bin:$PATH"
  # 2026-09-01T11:00:00Z — 30 minutes after the fixture head was pushed.
  export SDLC_NOW_EPOCH=1788260400
}

@test "READY when checks are green, no threads are open and both bots approve the head" {
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: green"* ]]
  [[ "$output" == *"UNRESOLVED: 0"* ]]
  [[ "$output" == *"REVIEWER: coderabbit status=APPROVED head=current"* ]]
  [[ "$output" == *"REVIEWER: cubic status=APPROVED head=current"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
}

@test "a dismissed review never counts; the latest live review decides" {
  run "$SCRIPT" --pr 7 --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"cubic status=APPROVED"* ]]
}

@test "FIX when a check fails or review threads are unresolved, naming both fixers" {
  export GH_PR_FIXTURE="$FX/pr-open-red.json"
  export GH_THREADS_FIXTURE="$BATS_TEST_DIRNAME/fixtures/gh/pr-comments.json"
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: red failing=[unit testing] pending=[e2e testing]"* ]]
  [[ "$output" == *"UNRESOLVED: 1 (coderabbit=1)"* ]]
  [[ "$output" == *"VERDICT: FIX"* ]]
  [[ "$output" == *"NEXT: fix failing checks unit testing (ci-fixer); resolve 1 review thread(s) (pr-comment-resolver); then commit and push"* ]]
}

@test "REQUEST when a reviewer last reviewed an older commit" {
  export GH_REVIEWS_FIXTURE="$FX/reviews-cubic-stale.ndjson"
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"REVIEWER: cubic status=STALE — last live review is on 0123456"* ]]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
  [[ "$output" == *"NEXT: request-ai-reviews.sh --pr 7 --reviewers cubic"* ]]
  [[ "$output" != *"--full"* ]]
}

@test "a never-reviewed PR asks for every reviewer" {
  export GH_REVIEWS_FIXTURE="$FX/reviews-none.ndjson"
  run "$SCRIPT" --pr 7
  [[ "$output" == *"coderabbit status=NONE"* ]]
  [[ "$output" == *"cubic status=NONE"* ]]
  [[ "$output" == *"NEXT: request-ai-reviews.sh --pr 7 --reviewers coderabbit,cubic"* ]]
}

@test "CodeRabbit CHANGES_REQUESTED on the head with every thread resolved asks for a full re-review" {
  export GH_REVIEWS_FIXTURE="$FX/reviews-coderabbit-changes.ndjson"
  run "$SCRIPT" --pr 7
  [[ "$output" == *"coderabbit status=NOT_APPROVED head=current — latest review on the head is CHANGES_REQUESTED"* ]]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
  [[ "$output" == *"--reviewers coderabbit --full"* ]]
}

@test "WAIT while a requested review is in flight, with the acknowledgement flag" {
  export GH_REVIEWS_FIXTURE="$FX/reviews-none.ndjson"
  export GH_COMMENTS_FIXTURE="$FX/comments-requested.ndjson"
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"REVIEWER: coderabbit status=REQUESTED ack=yes — mention posted 25m ago"* ]]
  [[ "$output" == *"REVIEWER: cubic status=REQUESTED ack=no"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" == *"waiting for reviews from coderabbit,cubic"* ]]
}

@test "WAIT while checks are still running" {
  export GH_PR_FIXTURE="$FX/pr-open-pending.json"
  run "$SCRIPT" --pr 7
  [[ "$output" == *"CI: pending failing=[] pending=[e2e testing]"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" == *"waiting for checks e2e testing"* ]]
}

@test "a pending review request outranks a running check in the NEXT hint but a stale reviewer outranks both" {
  export GH_PR_FIXTURE="$FX/pr-open-pending.json"
  export GH_REVIEWS_FIXTURE="$FX/reviews-cubic-stale.ndjson"
  run "$SCRIPT" --pr 7
  [[ "$output" == *"VERDICT: REQUEST"* ]]
}

@test "--required-checks narrows the CI verdict and reports a missing required check as pending" {
  export GH_PR_FIXTURE="$FX/pr-open-red.json"
  run "$SCRIPT" --pr 7 --required-checks "static testing,visual tests"
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=[visual tests]"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  run "$SCRIPT" --pr 7 --required-checks "static testing"
  [[ "$output" == *"CI: green"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
}

@test "unreachable reviewers are SKIPPED with a reason and never counted as approvals" {
  export GH_COMMENTS_FIXTURE="$FX/comments-skips.ndjson"
  export GH_REVIEWS_FIXTURE="$FX/reviews-none.ndjson"
  run "$SCRIPT" --pr 7 --reviewers coderabbit,qodo,qlty
  [ "$status" -eq 0 ]
  [[ "$output" == *"coderabbit status=SKIPPED — diff exceeds CodeRabbit's changed-file limit"* ]]
  [[ "$output" == *"qodo status=SKIPPED — reviews are paused"* ]]
  [[ "$output" == *"qlty status=SKIPPED — status-check bot"* ]]
  [[ "$output" == *"INFO: every requested reviewer is unreachable"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
}

@test "a PR with no checks is READY with a satisfied-with-report note" {
  export GH_PR_FIXTURE="$FX/pr-open-nochecks.json"
  run "$SCRIPT" --pr 7
  [[ "$output" == *"CI: none"* ]]
  [[ "$output" == *"INFO: CI: the PR reports no checks"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
}

@test "BLOCKED for a merged or conflicting PR" {
  export GH_PR_FIXTURE="$FX/pr-merged.json"
  run "$SCRIPT" --pr 7
  [[ "$output" == *"VERDICT: BLOCKED"* ]]
  [[ "$output" == *"PR is MERGED"* ]]
  export GH_PR_FIXTURE="$FX/pr-conflicting.json"
  run "$SCRIPT" --pr 7
  [[ "$output" == *"VERDICT: BLOCKED"* ]]
  [[ "$output" == *"CONFLICTING"* ]]
}

@test "--json emits the canonical shape" {
  export GH_PR_FIXTURE="$FX/pr-open-red.json"
  run "$SCRIPT" --pr 7 --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pr == 7 and .verdict == "FIX" and .ci.status == "red"
    and (.ci.failing == ["unit testing"]) and (.reviewers | length == 2)
    and (.reviewers[0].name == "coderabbit") and (.unresolved.total == 0) and (.next | type == "string")'
}

@test "wait mode re-reads until the verdict leaves WAIT" {
  export GH_PR_FIXTURE="$FX/pr-open-pending.json"
  export GH_PR_FIXTURE_2="$FX/pr-open-green.json"
  run "$SCRIPT" --pr 7 --wait-seconds 300 --interval-seconds 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: READY"* ]]
  [ "$(cat "$GH_CALLS")" -eq 2 ]
}

@test "wait mode returns the WAIT snapshot once the budget is spent" {
  export GH_PR_FIXTURE="$FX/pr-open-pending.json"
  run "$SCRIPT" --pr 7 --wait-seconds 0
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [ "$(cat "$GH_CALLS")" -eq 1 ]
}

@test "PR number defaults to the current branch's PR" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR: #7 acme/stub-frontend"* ]]
}

@test "unknown reviewer and bad numbers are usage errors" {
  run "$SCRIPT" --pr 7 --reviewers copilot
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown reviewer 'copilot'"* ]]
  run "$SCRIPT" --pr 7 --wait-seconds soon
  [ "$status" -eq 1 ]
  [[ "$output" == *"--wait-seconds must be a non-negative integer"* ]]
}

@test "runs from an install-cache copy via CLAUDE_PLUGIN_ROOT (ADR-4)" {
  CACHE="$BATS_TEST_TMPDIR/cache/react-frontend-sdlc"
  mkdir -p "$CACHE"
  cp -R "$PLUGIN_ROOT/scripts" "$CACHE/"
  CLAUDE_PLUGIN_ROOT="$CACHE" run "$CACHE/scripts/pr-state.sh" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: READY"* ]]
}

@test "--wait-verdicts REQUEST keeps polling through a REQUEST verdict" {
  export GH_REVIEWS_FIXTURE="$FX/reviews-cubic-stale.ndjson"
  export GH_PR_FIXTURE_2="$FX/pr-open-green.json"
  run "$SCRIPT" --pr 7 --wait-seconds 2 --interval-seconds 1 --wait-verdicts WAIT,REQUEST
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
  [ "$(cat "$GH_CALLS")" -ge 2 ]
  run "$SCRIPT" --pr 7 --wait-verdicts SOON
  [ "$status" -eq 1 ]
  [[ "$output" == *"--wait-verdicts must list"* ]]
  run "$SCRIPT" --pr 7 --wait-seconds 5 --interval-seconds 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"--interval-seconds must be at least 1"* ]]
}

@test "a mention posted after the commit but before the push does not count as a request for this head" {
  export GH_REVIEWS_FIXTURE="$FX/reviews-none.ndjson"
  export GH_COMMENTS_FIXTURE="$FX/comments-requested.ndjson"
  export GH_PUSHED_AT="2026-09-01T10:40:00Z"
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"coderabbit status=NONE"* ]]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
}

@test "--required-checks on a PR with an empty check rollup reports the checks as missing, never READY" {
  export GH_PR_FIXTURE="$FX/pr-open-nochecks.json"
  run "$SCRIPT" --pr 7 --required-checks "unit testing"
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=[unit testing]"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" != *"reports no checks"* ]]
}

@test "leading-zero durations, empty reviewer elements and duplicate reviewers are usage errors" {
  run "$SCRIPT" --pr 7 --wait-seconds 08 --interval-seconds 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"without leading zeros"* ]]
  run "$SCRIPT" --pr 7 --reviewers ","
  [ "$status" -eq 1 ]
  [[ "$output" == *"without empty elements"* ]]
  run "$SCRIPT" --pr 7 --reviewers cubic,cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate reviewer 'cubic'"* ]]
}
