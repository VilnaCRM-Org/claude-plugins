#!/usr/bin/env bats
# Tests for scripts/request-ai-reviews.sh (FR-8 comment-source recovery).
#
# The script makes three kinds of gh call (pr view, api …/comments, pr
# comment), so each test generates a subcommand-routing gh wrapper: the
# comment listing comes from an NDJSON fixture, `pr comment` appends its
# argv to a log instead of posting, and `pr view` answers the draft query.
# SDLC_NOW_EPOCH pins "now" so the CodeRabbit interval maths is
# deterministic.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/request-ai-reviews.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures/gh"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK/bin"
  cd "$WORK"
  git init -q
  git remote add origin https://github.com/acme/stub-frontend.git
  export GH_LOG="$WORK/gh.log"
  export GH_COMMENTS_FIXTURE="$FIXTURES/pr-issue-comments.ndjson"
  export GH_IS_DRAFT=false
  export GH_HEAD_DATE="2026-09-01T09:30:00Z"
  export GH_PR_VIEW_EXIT=0
  export GH_COMMENT_EXIT=0
  cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$GH_LOG"
case "$1 $2" in
  "pr view")
    if [[ "$*" == *isDraft* ]]; then
      [[ "$GH_PR_VIEW_EXIT" -eq 0 ]] || { echo "gh: PR not found" >&2; exit "$GH_PR_VIEW_EXIT"; }
      printf '{"isDraft":%s,"headRefOid":"a1b2c3d4","commits":[{"committedDate":"%s"}]}\n' "$GH_IS_DRAFT" "$GH_HEAD_DATE"
    else echo 7; fi ;;
  "api repos/acme/stub-frontend/issues/7/comments?per_page=100")
    cat "$GH_COMMENTS_FIXTURE" ;;
  "pr comment")
    exit "$GH_COMMENT_EXIT" ;;
  "api repos/acme/stub-frontend/commits/a1b2c3d4/check-suites?per_page=100")
    [[ -n "${GH_PUSHED_AT:-}" ]] && printf '"%s"\n' "$GH_PUSHED_AT" ;;
  *)
    echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
EOF
  chmod +x "$WORK/bin/gh"
  PATH="$WORK/bin:$PATH"
  # 2026-09-01T11:30:00Z — 30 minutes after the fixture's last CodeRabbit request.
  export SDLC_NOW_EPOCH=1788262200
}

@test "inside the interval CodeRabbit waits, cubic is requested" {
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"WAIT: coderabbit 30m"* ]]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
  [[ "$output" == *"SUMMARY: requested=1 waiting=1 skipped=0"* ]]
  grep -q '^gh pr comment 7 --body @cubic-dev-ai review$' "$GH_LOG"
  ! grep -q 'coderabbitai' "$GH_LOG"
}

@test "after the interval both reviewers are requested with the exact mentions" {
  export SDLC_NOW_EPOCH=1788265800   # 2026-09-01T12:30:00Z
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
  [[ "$output" == *"SUMMARY: requested=2 waiting=0 skipped=0"* ]]
  grep -q '^gh pr comment 7 --body @coderabbitai review$' "$GH_LOG"
}

@test "--full asks CodeRabbit for a full review" {
  export SDLC_NOW_EPOCH=1788265800
  run "$SCRIPT" --pr 7 --reviewers coderabbit --full
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai full review"* ]]
  grep -q '^gh pr comment 7 --body @coderabbitai full review$' "$GH_LOG"
}

@test "--force posts inside the interval" {
  run "$SCRIPT" --pr 7 --reviewers coderabbit --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
  [[ "$output" != *"WAIT:"* ]]
}

@test "--dry-run prints the plan and posts nothing" {
  export SDLC_NOW_EPOCH=1788265800
  run "$SCRIPT" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD-POST: coderabbit @coderabbitai review"* ]]
  [[ "$output" == *"WOULD-POST: cubic @cubic-dev-ai review"* ]]
  ! grep -q 'pr comment' "$GH_LOG"
}

@test "an oversized-diff skip from CodeRabbit is reported, never re-mentioned" {
  export GH_COMMENTS_FIXTURE="$FIXTURES/pr-issue-comments-oversized.ndjson"
  export SDLC_NOW_EPOCH=1788265800
  run "$SCRIPT" --pr 7 --reviewers coderabbit
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED: coderabbit — diff exceeds CodeRabbit's changed-file limit"* ]]
  [[ "$output" == *"SUMMARY: requested=0 waiting=0 skipped=1"* ]]
  ! grep -q 'pr comment' "$GH_LOG"
}

@test "paused Qodo and status-check bots are skipped with a reason" {
  run "$SCRIPT" --pr 7 --reviewers qodo,qlty,sonarcloud
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED: qodo — reviews are paused"* ]]
  [[ "$output" == *"SKIPPED: qlty — status-check bot"* ]]
  [[ "$output" == *"SKIPPED: sonarcloud — status-check bot"* ]]
  [[ "$output" == *"SUMMARY: requested=0 waiting=0 skipped=3"* ]]
  ! grep -q 'pr comment' "$GH_LOG"
}

@test "a draft PR is noted but mentions still run" {
  export GH_IS_DRAFT=true
  run "$SCRIPT" --pr 7 --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: PR #7 is a draft"* ]]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
}

@test "PR number defaults to the current branch's PR" {
  run "$SCRIPT" --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
  grep -q '^gh pr comment 7 --body @cubic-dev-ai review$' "$GH_LOG"
}

@test "a failed gh pr comment exits 1 with the mention named" {
  export GH_COMMENT_EXIT=1
  run "$SCRIPT" --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh pr comment failed posting '@cubic-dev-ai review' on PR #7"* ]]
}

@test "unknown reviewer and bad interval are usage errors" {
  run "$SCRIPT" --pr 7 --reviewers copilot
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown reviewer 'copilot'"* ]]
  run "$SCRIPT" --pr 7 --min-interval-minutes ten
  [ "$status" -eq 1 ]
  [[ "$output" == *"--min-interval-minutes must be a non-negative integer"* ]]
}

@test "runs from an install-cache copy via CLAUDE_PLUGIN_ROOT (ADR-4)" {
  CACHE="$BATS_TEST_TMPDIR/cache/react-frontend-sdlc"
  mkdir -p "$CACHE"
  cp -R "$PLUGIN_ROOT/scripts" "$CACHE/"
  export SDLC_NOW_EPOCH=1788265800
  CLAUDE_PLUGIN_ROOT="$CACHE" run "$CACHE/scripts/request-ai-reviews.sh" --pr 7 --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
}

@test "a Review-skipped comment older than the current head no longer suppresses the mention" {
  export GH_COMMENTS_FIXTURE="$FIXTURES/pr-issue-comments-oversized.ndjson"
  export GH_HEAD_DATE="2026-09-01T10:30:00Z"
  export SDLC_NOW_EPOCH=1788265800
  run "$SCRIPT" --pr 7 --reviewers coderabbit
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
}

@test "bot logins with a [bot] suffix are recognised" {
  sed 's/"coderabbitai"/"coderabbitai[bot]"/' "$FIXTURES/pr-issue-comments-oversized.ndjson" >"$WORK/oversized-bot.ndjson"
  export GH_COMMENTS_FIXTURE="$WORK/oversized-bot.ndjson"
  export SDLC_NOW_EPOCH=1788265800
  run "$SCRIPT" --pr 7 --reviewers coderabbit
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED: coderabbit — diff exceeds CodeRabbit's changed-file limit"* ]]
}

@test "a failed gh pr view is fatal instead of silently posting" {
  export GH_PR_VIEW_EXIT=1
  run "$SCRIPT" --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh pr view failed for PR #7"* ]]
  ! grep -q 'pr comment' "$GH_LOG"
}

@test "a Review-skipped comment posted between commit and push still counts against the pushed head" {
  export GH_COMMENTS_FIXTURE="$FIXTURES/pr-issue-comments-oversized.ndjson"
  export GH_HEAD_DATE="2026-09-01T09:50:00Z"
  export GH_PUSHED_AT="2026-09-01T10:10:00Z"
  export SDLC_NOW_EPOCH=1788265800
  run "$SCRIPT" --pr 7 --reviewers coderabbit
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
}
