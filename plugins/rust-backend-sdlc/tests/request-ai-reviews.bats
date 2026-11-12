#!/usr/bin/env bats
# request-ai-reviews.bats — cases of scripts/request-ai-reviews.sh (FR-39,
# AC-39.1, ADR-23, NFR-5 P5 exemption).
#
# Hermetic: the gh stub of tests/fixtures/bin answers through a routes file
# that rar_run regenerates before every run from the RAR_* variables, under
# STUB_GH_STRICT=1, so any call no route names exits 9. The comment listing
# comes from an NDJSON fixture (the shape the script's --jq produces), `pr
# view` answers the draft and head-commit query, `api …/check-suites` the push
# time, and `pr comment` only logs its argv. The repository is materialized at
# $BATS_TEST_TMPDIR/billing-service (origin acme/billing-service) with the
# golden profile, whose review.reviewers is [coderabbit]. SDLC_NOW_EPOCH pins
# "now" so the CodeRabbit interval maths is deterministic. The 17 cases ported
# from the react suite pass --reviewers coderabbit,cubic where react relied on
# its built-in default.
#
# shellcheck disable=SC2030,SC2031 # bats cases are subshells: each exports its own clock

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  SCRIPT="$PLUGIN_ROOT/scripts/request-ai-reviews.sh"
  GH_FIX="$PLUGIN_ROOT/tests/fixtures/gh"
  REPO="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$REPO"
  mkdir -p "$REPO/.claude"
  cp "$PLUGIN_ROOT/tests/fixtures/profiles/golden.yml" "$REPO/.claude/rust-sdlc.yml"
  PROFILE="$REPO/.claude/rust-sdlc.yml"
  cd "$REPO" || return 1
  # The script names the profile under the work tree's real path (git
  # rev-parse --show-toplevel), which differs where a temp parent is a symlink.
  PROFILE_SHOWN="$(pwd -P)/.claude/rust-sdlc.yml"
  RAR_COMMENTS="$GH_FIX/pr-issue-comments.ndjson"
  RAR_IS_DRAFT=false
  RAR_HEAD_DATE="2026-09-01T09:30:00Z"
  RAR_PUSHED_AT=""
  RAR_PR_VIEW=""
  RAR_NUMBER=7
  RAR_NUMBER_EXIT=0
  RAR_VIEW_EXIT=0
  RAR_SUITES_EXIT=0
  RAR_COMMENTS_EXIT=0
  RAR_POST_EXIT=0
  # 2026-09-01T11:30:00Z — 30 minutes after the fixture's last CodeRabbit request.
  export SDLC_NOW_EPOCH=1788262200
}

# --- suite helpers (rar_) ------------------------------------------------------

# rar_routes — writes the gh routes of the five calls the script makes from the
# RAR_* variables and exports STUB_GH_ROUTES with STUB_GH_STRICT=1.
rar_routes() {
  local dir="$BATS_TEST_TMPDIR/gh"
  mkdir -p "$dir"
  printf '%s\n' "$RAR_NUMBER" >"$dir/pr-number.txt"
  if [[ -n "$RAR_PR_VIEW" ]]; then
    printf '%s\n' "$RAR_PR_VIEW" >"$dir/pr-view.json"
  else
    printf '{"isDraft":%s,"headRefOid":"a1b2c3d4","commits":[{"committedDate":"%s"}]}\n' \
      "$RAR_IS_DRAFT" "$RAR_HEAD_DATE" >"$dir/pr-view.json"
  fi
  if [[ -n "$RAR_PUSHED_AT" ]]; then
    printf '"%s"\n' "$RAR_PUSHED_AT" >"$dir/suites.txt"
  else
    : >"$dir/suites.txt"
  fi
  {
    printf 'pr view --json number --jq .number\t%s\t%s\n' "$RAR_NUMBER_EXIT" "$dir/pr-number.txt"
    printf 'pr view 7 --json isDraft,headRefOid,commits\t%s\t%s\n' "$RAR_VIEW_EXIT" "$dir/pr-view.json"
    printf 'api repos/acme/billing-service/commits/a1b2c3d4/check-suites?per_page=100 --jq *\t%s\t%s\n' \
      "$RAR_SUITES_EXIT" "$dir/suites.txt"
    printf 'api repos/acme/billing-service/issues/7/comments?per_page=100 --paginate --jq *\t%s\t%s\n' \
      "$RAR_COMMENTS_EXIT" "$RAR_COMMENTS"
    printf 'pr comment 7 --body *\t%s\t-\n' "$RAR_POST_EXIT"
  } >"$dir/routes.tsv"
  export STUB_GH_ROUTES="$dir/routes.tsv" STUB_GH_STRICT=1
}

# rar_run ARG... — rar_routes, then `run` the script with ARG...
rar_run() {
  rar_routes
  run "$SCRIPT" "$@"
}

# rar_posts — number of `gh pr comment` calls logged by the stub.
rar_posts() {
  grep -c '^gh pr comment ' "$STUB_GH_LOG" || true
}

# rar_count PREFIX — number of output lines that start with PREFIX.
rar_count() {
  local line n=0
  for line in "${lines[@]}"; do
    if [[ "$line" == "$1"* ]]; then
      n=$((n + 1))
    fi
  done
  printf '%s\n' "$n"
}

# --- usage -------------------------------------------------------------------

@test "request-ai-reviews: --help prints the usage header and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "request-ai-reviews.sh — "* ]]
  [[ "$output" == *"Usage: request-ai-reviews.sh [--pr N] [--reviewers LIST] [--full] [--min-interval-minutes M] [--force] [--dry-run]"* ]]
  [[ "$output" == *"--min-interval-minutes M"* ]]
  [[ "$output" == *"Exit: 0 "*"; 1 "* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: --help is accepted in any position" {
  run "$SCRIPT" --bogus --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: request-ai-reviews.sh"* ]]
  run "$SCRIPT" --pr seven --reviewers copilot --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: request-ai-reviews.sh"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: an unknown flag exits 1 with the usage line (ADR-23 react parity)" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] unknown argument: --bogus"* ]]
  [[ "$output" == *"(usage: request-ai-reviews.sh [--pr N] [--reviewers LIST] [--full] [--min-interval-minutes M] [--force] [--dry-run])"* ]]
  run "$SCRIPT" --pr=7
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --pr=7"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: a flag without its value exits 1" {
  local flag
  for flag in --pr --reviewers --min-interval-minutes; do
    run "$SCRIPT" "$flag"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[rust-sdlc][ERROR] $flag needs a value (usage: request-ai-reviews.sh "* ]]
  done
  run "$SCRIPT" --pr --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"--pr needs a value"* ]]
  run "$SCRIPT" --reviewers --force
  [ "$status" -eq 1 ]
  [[ "$output" == *"--reviewers needs a value"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: a malformed --pr exits 1 before any gh call" {
  local bad
  for bad in '' seven 0 07 -3 7a 1.5 2147483648 99999999999999999999; do
    run "$SCRIPT" --pr "$bad" --reviewers cubic
    [ "$status" -eq 1 ]
    [[ "$output" == *"--pr must be a pull-request number"* ]]
  done
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: unknown reviewer and bad interval are usage errors" {
  run "$SCRIPT" --pr 7 --reviewers copilot
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown reviewer 'copilot' in --reviewers (known: coderabbit,cubic,qodo,qlty,sonarcloud) (usage: request-ai-reviews.sh "* ]]
  run "$SCRIPT" --pr 7 --reviewers cubic,CodeRabbit
  [ "$status" -eq 1 ]
  [[ "$output" == *"--reviewers must be a comma-separated list without empty elements, got: cubic,CodeRabbit"* ]]
  local bad
  for bad in ten -5 1.5 ''; do
    run "$SCRIPT" --pr 7 --min-interval-minutes "$bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--min-interval-minutes must be a non-negative integer"* ]]
  done
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: a duplicate reviewer exits 1 (harmonised with pr-state.sh)" {
  run "$SCRIPT" --pr 7 --reviewers cubic,coderabbit,cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate reviewer 'cubic' in --reviewers"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: an empty element in --reviewers exits 1 (harmonised with pr-state.sh)" {
  local bad
  for bad in 'coderabbit,,cubic' ',cubic' 'cubic,' ',' 'cubic, qodo'; do
    run "$SCRIPT" --pr 7 --reviewers "$bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--reviewers must be a comma-separated list without empty elements, got: $bad"* ]]
  done
  [ ! -s "$STUB_GH_LOG" ]
}

# --- reviewer source: --reviewers > review.reviewers ------------------------------

@test "request-ai-reviews: without --reviewers the golden profile's review.reviewers is the list" {
  export SDLC_NOW_EPOCH=1788265800 # 2026-09-01T12:30:00Z
  rar_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
  [[ "$output" != *"cubic"* ]]
  [[ "${lines[-1]}" == "SUMMARY: requested=1 waiting=0 skipped=0" ]]
  [ "$(rar_posts)" -eq 1 ]
  grep -q '^gh pr comment 7 --body @coderabbitai review$' "$STUB_GH_LOG"
}

@test "request-ai-reviews: the profile is read at the top of the work tree from a subdirectory" {
  export SDLC_NOW_EPOCH=1788265800
  mutate_profile "$PROFILE" review.reviewers '[cubic, qlty]'
  rar_routes
  cd "$REPO/crates" || return 1
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REQUESTED: cubic @cubic-dev-ai review" ]
  [[ "${lines[1]}" == "SKIPPED: qlty — status-check bot"* ]]
  [ "${lines[2]}" = "SUMMARY: requested=1 waiting=0 skipped=1" ]
}

@test "request-ai-reviews: --reviewers overrides the profile's review.reviewers" {
  mutate_profile "$PROFILE" review.reviewers '[qlty]'
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
  [[ "$output" != *"qlty"* ]]
  [[ "$output" != *"coderabbit"* ]]
  [ "$(rar_posts)" -eq 1 ]
}

@test "request-ai-reviews: an empty review.reviewers prints INFO: no reviewers configured and exits 0" {
  mutate_profile "$PROFILE" review.reviewers '[]'
  rar_run --pr 7
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "INFO: no reviewers configured" ]
  [ "${lines[1]}" = "SUMMARY: requested=0 waiting=0 skipped=0" ]
  [ "${#lines[@]}" -eq 2 ]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: an explicit empty --reviewers means no reviewer, as in pr-state.sh" {
  rar_run --pr 7 --reviewers ''
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "INFO: no reviewers configured" ]
  [ "${lines[1]}" = "SUMMARY: requested=0 waiting=0 skipped=0" ]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: the profile's review.reviewers is validated like --reviewers" {
  mutate_profile "$PROFILE" review.reviewers '[cubic, coderabbit, cubic]'
  rar_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] duplicate reviewer 'cubic' in review.reviewers of $PROFILE_SHOWN"* ]]
  [[ "$output" != *"(usage:"* ]]
  mutate_profile "$PROFILE" review.reviewers '[copilot]'
  rar_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown reviewer 'copilot' in review.reviewers of $PROFILE_SHOWN (known: "* ]]
  mutate_profile "$PROFILE" review.reviewers '[cubic, null]'
  rar_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown reviewer 'null' in review.reviewers"* ]]
  local bad
  for bad in "[[coderabbit]]" "[CodeRabbit]" "[cubic, '']" "['', cubic]" "[cubic, '', qlty]"; do
    mutate_profile "$PROFILE" review.reviewers "$bad"
    rar_run --pr 7
    [ "$status" -eq 1 ]
    [[ "$output" == *"review.reviewers of $PROFILE_SHOWN must be a comma-separated list without empty elements, got: "* ]]
  done
  mutate_profile "$PROFILE" review.reviewers "['']"
  rar_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"review.reviewers of $PROFILE_SHOWN must be a comma-separated list without empty elements, got: ['']"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: review.reviewers missing, null or not a list exits 1" {
  drop_profile_key "$PROFILE" review.reviewers
  rar_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile: required key 'review.reviewers' missing or null in $PROFILE_SHOWN"* ]]
  cp "$PLUGIN_ROOT/tests/fixtures/profiles/golden.yml" "$PROFILE"
  mutate_profile "$PROFILE" review.reviewers 'null'
  rar_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"required key 'review.reviewers' missing or null"* ]]
  mutate_profile "$PROFILE" review.reviewers 'coderabbit'
  rar_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile: review.reviewers must be a list in $PROFILE_SHOWN, got a string"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: without a profile the list is empty with a WARN, as in pr-state.sh" {
  rm "$PROFILE"
  rar_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"[rust-sdlc][WARN] no profile at $PROFILE_SHOWN: the reviewer list defaults to empty"* ]]
  [[ "$output" == *"INFO: no reviewers configured"* ]]
  [[ "${lines[-1]}" == "SUMMARY: requested=0 waiting=0 skipped=0" ]]
  [ ! -s "$STUB_GH_LOG" ]
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
  [[ "$output" != *"WARN"* ]]
}

@test "request-ai-reviews: an unparseable profile exits 1" {
  cp "$PLUGIN_ROOT/tests/fixtures/profiles/invalid-yaml.yml" "$PROFILE"
  rar_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile: cannot read review.reviewers from $PROFILE_SHOWN"* ]]
  [[ "$output" != *Traceback* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

# --- plan and cadence (react cases) ------------------------------------------------

@test "request-ai-reviews: inside the interval CodeRabbit waits, cubic is requested" {
  rar_run --pr 7 --reviewers coderabbit,cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"WAIT: coderabbit 30m (last CodeRabbit request is inside the 60-minute interval; pass --force to override)"* ]]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
  [[ "$output" == *"SUMMARY: requested=1 waiting=1 skipped=0"* ]]
  grep -q '^gh pr comment 7 --body @cubic-dev-ai review$' "$STUB_GH_LOG"
  [ "$(grep -c 'coderabbitai' "$STUB_GH_LOG" || true)" -eq 0 ]
}

@test "request-ai-reviews: after the interval both reviewers are requested with the exact mentions" {
  export SDLC_NOW_EPOCH=1788265800 # 2026-09-01T12:30:00Z
  rar_run --pr 7 --reviewers coderabbit,cubic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REQUESTED: coderabbit @coderabbitai review" ]
  [ "${lines[1]}" = "REQUESTED: cubic @cubic-dev-ai review" ]
  [ "${lines[2]}" = "SUMMARY: requested=2 waiting=0 skipped=0" ]
  grep -q '^gh pr comment 7 --body @coderabbitai review$' "$STUB_GH_LOG"
  grep -q '^gh pr comment 7 --body @cubic-dev-ai review$' "$STUB_GH_LOG"
}

@test "request-ai-reviews: --full asks CodeRabbit for a full review" {
  export SDLC_NOW_EPOCH=1788265800
  rar_run --pr 7 --reviewers coderabbit,cubic --full
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai full review"* ]]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
  grep -q '^gh pr comment 7 --body @coderabbitai full review$' "$STUB_GH_LOG"
}

@test "request-ai-reviews: --force posts inside the interval" {
  rar_run --pr 7 --reviewers coderabbit --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
  [[ "$output" != *"WAIT:"* ]]
  grep -q '^gh pr comment 7 --body @coderabbitai review$' "$STUB_GH_LOG"
}

@test "request-ai-reviews: --dry-run prints the plan and posts nothing" {
  export SDLC_NOW_EPOCH=1788265800
  rar_run --pr 7 --reviewers coderabbit,cubic --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD-POST: coderabbit @coderabbitai review"* ]]
  [[ "$output" == *"WOULD-POST: cubic @cubic-dev-ai review"* ]]
  [[ "$output" != *"REQUESTED:"* ]]
  [[ "$output" == *"SUMMARY: requested=2 waiting=0 skipped=0"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: --min-interval-minutes overrides the 60-minute default, 0 turns it off" {
  rar_run --pr 7 --reviewers coderabbit --min-interval-minutes 90
  [ "$status" -eq 0 ]
  [[ "$output" == *"WAIT: coderabbit 60m (last CodeRabbit request is inside the 90-minute interval; pass --force to override)"* ]]
  [ "$(rar_posts)" -eq 0 ]
  rar_run --pr 7 --reviewers coderabbit --min-interval-minutes 020
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
  rar_run --pr 7 --reviewers coderabbit --min-interval-minutes 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
  [ "$(rar_posts)" -eq 2 ]
}

@test "request-ai-reviews: an oversized-diff skip from CodeRabbit is reported, never re-mentioned" {
  RAR_COMMENTS="$GH_FIX/pr-issue-comments-oversized.ndjson"
  export SDLC_NOW_EPOCH=1788265800
  rar_run --pr 7 --reviewers coderabbit
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED: coderabbit — diff exceeds CodeRabbit's changed-file limit; split the PR — a mention cannot lift it"* ]]
  [[ "$output" == *"SUMMARY: requested=0 waiting=0 skipped=1"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: paused Qodo and status-check bots are skipped with a reason" {
  rar_run --pr 7 --reviewers qodo,qlty,sonarcloud
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED: qodo — reviews are paused"* ]]
  [[ "$output" == *"SKIPPED: qlty — status-check bot"* ]]
  [[ "$output" == *"SKIPPED: sonarcloud — status-check bot"* ]]
  [[ "$output" == *"SUMMARY: requested=0 waiting=0 skipped=3"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: Qodo without a paused notice is skipped as push-only" {
  RAR_COMMENTS="$GH_FIX/pr-issue-comments-oversized.ndjson"
  rar_run --pr 7 --reviewers qodo
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED: qodo — runs on push only; this plugin posts no Qodo command"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: the SUMMARY numbers add up over all five reviewers, in list order" {
  rar_run --pr 7 --reviewers sonarcloud,qlty,qodo,cubic,coderabbit
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 6 ]
  [[ "${lines[0]}" == "SKIPPED: sonarcloud — "* ]]
  [[ "${lines[1]}" == "SKIPPED: qlty — "* ]]
  [[ "${lines[2]}" == "SKIPPED: qodo — "* ]]
  [ "${lines[3]}" = "REQUESTED: cubic @cubic-dev-ai review" ]
  [[ "${lines[4]}" == "WAIT: coderabbit 30m "* ]]
  [ "${lines[5]}" = "SUMMARY: requested=1 waiting=1 skipped=3" ]
  [ "$(rar_count 'REQUESTED: ')" -eq 1 ]
  [ "$(rar_count 'WAIT: ')" -eq 1 ]
  [ "$(rar_count 'SKIPPED: ')" -eq 3 ]
  [ "$(rar_posts)" -eq 1 ]
}

@test "request-ai-reviews: a draft PR is noted but mentions still run" {
  RAR_IS_DRAFT=true
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "INFO: PR #7 is a draft"* ]]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
}

@test "request-ai-reviews: PR number defaults to the current branch's PR" {
  rar_run --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
  grep -q '^gh pr view --json number --jq .number$' "$STUB_GH_LOG"
  grep -q '^gh pr comment 7 --body @cubic-dev-ai review$' "$STUB_GH_LOG"
}

@test "request-ai-reviews: no pull request for the current branch exits 1" {
  RAR_NUMBER_EXIT=1
  rar_run --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pull request found for the current branch: pass --pr N"* ]]
  RAR_NUMBER_EXIT=0
  RAR_NUMBER=07
  rar_run --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh pr view returned an invalid pull-request number: '07': pass --pr N"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: a failed gh pr comment exits 1 with the mention named" {
  RAR_POST_EXIT=1
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh pr comment failed posting '@cubic-dev-ai review' on PR #7"* ]]
  [[ "$output" != *"SUMMARY:"* ]]
}

@test "request-ai-reviews: runs from an install-cache copy via CLAUDE_PLUGIN_ROOT (ADR-4)" {
  local cache="$BATS_TEST_TMPDIR/cache/rust-backend-sdlc"
  mkdir -p "$cache"
  cp -R "$PLUGIN_ROOT/scripts" "$cache/"
  export SDLC_NOW_EPOCH=1788265800
  rar_routes
  CLAUDE_PLUGIN_ROOT="$cache" run "$cache/scripts/request-ai-reviews.sh" --pr 7 --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: cubic @cubic-dev-ai review"* ]]
}

@test "request-ai-reviews: a Review-skipped comment older than the current head no longer suppresses the mention" {
  RAR_COMMENTS="$GH_FIX/pr-issue-comments-oversized.ndjson"
  RAR_HEAD_DATE="2026-09-01T10:30:00Z"
  export SDLC_NOW_EPOCH=1788265800
  rar_run --pr 7 --reviewers coderabbit
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
}

@test "request-ai-reviews: bot logins with a [bot] suffix are recognised" {
  sed 's/"coderabbitai"/"coderabbitai[bot]"/' "$GH_FIX/pr-issue-comments-oversized.ndjson" >"$BATS_TEST_TMPDIR/oversized-bot.ndjson"
  RAR_COMMENTS="$BATS_TEST_TMPDIR/oversized-bot.ndjson"
  export SDLC_NOW_EPOCH=1788265800
  rar_run --pr 7 --reviewers coderabbit
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED: coderabbit — diff exceeds CodeRabbit's changed-file limit"* ]]
}

@test "request-ai-reviews: a failed gh pr view is fatal instead of silently posting" {
  RAR_VIEW_EXIT=1
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh pr view failed for PR #7 in acme/billing-service"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: a Review-skipped comment posted between commit and push still counts against the pushed head" {
  RAR_COMMENTS="$GH_FIX/pr-issue-comments-oversized.ndjson"
  RAR_HEAD_DATE="2026-09-01T09:50:00Z"
  RAR_PUSHED_AT="2026-09-01T10:10:00Z"
  export SDLC_NOW_EPOCH=1788265800
  rar_run --pr 7 --reviewers coderabbit
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQUESTED: coderabbit @coderabbitai review"* ]]
}

@test "request-ai-reviews: a failed check-suites lookup is fatal instead of silently dating the head by its commit" {
  RAR_SUITES_EXIT=1
  rar_run --pr 7 --reviewers coderabbit
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh api failed listing check suites for commit a1b2c3d4"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

# --- further refusals ----------------------------------------------------------------

@test "request-ai-reviews: a failed comment listing exits 1 and posts nothing" {
  RAR_COMMENTS_EXIT=1
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh api failed listing comments for PR #7 in acme/billing-service"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: a malformed comment listing or pull-request document exits 1 without a traceback" {
  printf '{"user":"maintainer","body":"@coderabbitai review","created_at":"2026-09-01T11:00:00Z"}\nnot json\n' \
    >"$BATS_TEST_TMPDIR/broken.ndjson"
  RAR_COMMENTS="$BATS_TEST_TMPDIR/broken.ndjson"
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"comment listing line 2 is not a JSON object"* ]]
  [[ "$output" == *"gh api returned a malformed comment listing for PR #7"* ]]
  [[ "$output" != *Traceback* ]]
  RAR_COMMENTS="$GH_FIX/pr-issue-comments.ndjson"
  RAR_PR_VIEW='<html>502 Bad Gateway</html>'
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh pr view returned a malformed document for PR #7"* ]]
  [[ "$output" != *Traceback* ]]
  RAR_PR_VIEW='{"isDraft":false,"headRefOid":"../../x","commits":[]}'
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh pr view returned a malformed head commit for PR #7"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: an unresolvable repository exits 1" {
  git remote set-url origin https://git.example.invalid/acme/billing-service.git
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve the repository"* ]]
  grep -q '^gh repo view --json nameWithOwner --jq .nameWithOwner$' "$STUB_GH_LOG"
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: gh absent exits 1, an empty reviewer list needs no gh" {
  local nogh
  nogh="$(sandbox_path bash cat dirname git python3)"
  run env PATH="$nogh" "$SCRIPT" --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] gh CLI not found on PATH"* ]]
  [[ "$output" != *"SUMMARY:"* ]]
  mutate_profile "$PROFILE" review.reviewers '[]'
  run env PATH="$nogh" "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: no reviewers configured"* ]]
}

@test "request-ai-reviews: python3 absent exits 1 before any gh call" {
  local nopy
  nopy="$(sandbox_path bash cat dirname git gh)"
  run env PATH="$nopy" "$SCRIPT" --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] python3 is required to evaluate the reviewer plan"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "request-ai-reviews: a malformed SDLC_NOW_EPOCH exits 1 before any post" {
  export SDLC_NOW_EPOCH=yesterday
  rar_run --pr 7 --reviewers cubic
  [ "$status" -eq 1 ]
  [[ "$output" == *"SDLC_NOW_EPOCH is not a non-negative integer"* ]]
  [ "$(rar_posts)" -eq 0 ]
}

@test "request-ai-reviews: the --force option matches none of the forbidden patterns P1-P5 (NFR-5 exemption)" {
  run python3 -I - "$SCRIPT" <<'PY'
import re
import sys

patterns = [r"git (commit|push)\b.*(--no-verify|\s-n\b)", r"git push\b.*(--force|--force-with-lease|\s-f\b)",
            r"git -c core\.hooksPath", r"git config ((--local|--global) )?core\.hooksPath",
            r"bmalph implement.*--force"]
force = [line for line in open(sys.argv[1], encoding="utf-8") if "--force" in line]
assert len(force) >= 3, force
hits = [line for line in force if any(re.search(p, line) for p in patterns)]
assert not hits, hits
print("ok", len(force))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok "* ]]
}
