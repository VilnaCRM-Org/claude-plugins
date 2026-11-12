#!/usr/bin/env bats
# post-review-findings.bats — cases of scripts/post-review-findings.sh (FR-37,
# AC-37.1, ADR-16, ADR-23, ADR-26, ADR-27, D12).
#
# Hermetic: the gh stub of tests/fixtures/bin answers every call through a
# routes file in strict mode (an unexpected call exits 9). prf_gh routes a
# normal post on PR 7 of acme/billing-service: the posting identity
# rust-sdlc-bot, the base repository, the comment listing (a file chosen per
# case), the POST that answers a comment URL, the PATCH and `gh pr view`; a
# route added before prf_gh wins, which is how a case makes one call fail.
# The repository is materialized at $BATS_TEST_TMPDIR/billing-service with
# the golden profile (capabilities.publish_pr_comments: true) at
# .claude/rust-sdlc.yml. Ledgers are the ADR-16 fixtures of
# tests/fixtures/ledgers, named with --file or copied to the default ledger
# directory target/rust-sdlc/review-ledgers; variants (no schema_version,
# every finding dropped, secrets across findings) are written at runtime.
# Comment listings are the forged-marker fixture plus NDJSON lines written by
# prf_comment.
#
# shellcheck disable=SC2030,SC2031 # bats cases are subshells

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  SCRIPT="$PLUGIN_ROOT/scripts/post-review-findings.sh"
  LEDGERS="$PLUGIN_ROOT/tests/fixtures/ledgers"
  GH_FIX="$PLUGIN_ROOT/tests/fixtures/gh"
  PROFILES="$PLUGIN_ROOT/tests/fixtures/profiles"
  REPO="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$REPO"
  mkdir -p "$REPO/.claude"
  cp "$PROFILES/golden.yml" "$REPO/.claude/rust-sdlc.yml"
  cd "$REPO" || return 1
  LEDGER_DIR="$REPO/target/rust-sdlc/review-ledgers"
  unset SDLC_LEDGER_DIR
  BOT=rust-sdlc-bot
  COMMENT_URL='https://github.com/acme/billing-service/pull/7#issuecomment-3001'
  STUB_GH_ROUTES="$BATS_TEST_TMPDIR/gh-routes.tsv"
  : >"$STUB_GH_ROUTES"
  export STUB_GH_ROUTES STUB_GH_STRICT=1
}

# --- suite helpers (prf_) ------------------------------------------------------

# prf_value NAME TEXT — TEXT as the file NAME under the test directory; prints
# its path (the stdout file of a route).
prf_value() {
  printf '%s\n' "$2" >"$BATS_TEST_TMPDIR/$1"
  printf '%s\n' "$BATS_TEST_TMPDIR/$1"
}

# prf_route GLOB EXIT [FILE] — one gh route; the first matching route wins.
prf_route() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:--}" >>"$STUB_GH_ROUTES"
}

# prf_gh [LISTING] — the routes of a normal post on PR 7: identity BOT, base
# repository acme/billing-service, LISTING as the comment listing (default: no
# comment), POST answering COMMENT_URL, PATCH succeeding, `gh pr view` → 7.
prf_gh() {
  local listing="${1:-}"
  [[ -n "$listing" ]] || listing="$(prf_value listing-none.json '[]')"
  prf_route 'api user --jq .login' 0 "$(prf_value login.txt "$BOT")"
  prf_route 'api repos/acme/billing-service/pulls/7 --jq .base.repo.full_name' 0 \
    "$(prf_value base.txt acme/billing-service)"
  prf_route 'api --paginate repos/acme/billing-service/issues/7/comments*' 0 "$listing"
  prf_route 'api -X POST repos/acme/billing-service/issues/7/comments -F body=@target/rust-sdlc/tmp/review-*.md --jq .html_url' 0 \
    "$(prf_value url.txt "$COMMENT_URL")"
  prf_route 'api -X PATCH repos/acme/billing-service/issues/comments/* -F body=@target/rust-sdlc/tmp/review-*.md' 0
  prf_route 'pr view --json number --jq .number' 0 "$(prf_value number.txt 7)"
}

# prf_ledger FIXTURE [LENS] — tests/fixtures/ledgers/FIXTURE.json copied to the
# default ledger directory as LENS.json (default: the fixture's own lens).
prf_ledger() {
  local lens="${2:-}"
  if [[ -z "$lens" ]]; then
    lens="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["lens"])' "$LEDGERS/$1.json")"
  fi
  mkdir -p "$LEDGER_DIR"
  cp "$LEDGERS/$1.json" "$LEDGER_DIR/$lens.json"
}

# prf_variant FIXTURE NAME PYTHON — FIXTURE rewritten by the python statement
# PYTHON (the ledger is `d`) into $BATS_TEST_TMPDIR/NAME.json; prints its path.
prf_variant() {
  python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(d, open(sys.argv[2], "w"), indent=2)
' "$LEDGERS/$1.json" "$BATS_TEST_TMPDIR/$2.json" "$3"
  printf '%s\n' "$BATS_TEST_TMPDIR/$2.json"
}

# prf_comment ID LOGIN LABEL — one NDJSON comment by LOGIN whose body starts
# with the marker of LABEL.
prf_comment() {
  printf '{"id":%s,"user":{"login":"%s"},"body":"<!-- rust-sdlc-review:%s -->\\n## earlier body","html_url":"https://github.com/acme/billing-service/pull/7#issuecomment-%s"}\n' \
    "$1" "$2" "$3" "$1"
}

# prf_calls ERE — number of logged gh calls whose argv matches ERE.
prf_calls() {
  grep -cE "^gh $1" "$STUB_GH_LOG" || true
}

# prf_writes — number of logged POST, PATCH and DELETE calls.
prf_writes() {
  prf_calls 'api -X (POST|PATCH|DELETE) '
}

# prf_no_gh — the stub logged no call at all.
prf_no_gh() {
  [ ! -s "$STUB_GH_LOG" ]
}

# prf_rows — number of finding rows in $output.
prf_rows() {
  printf '%s\n' "$output" | grep -cE '^\| (Critical|High|Medium|Low|Info) \|' || true
}

# prf_line TEXT — the line number of the first line of $output holding TEXT.
prf_line() {
  printf '%s\n' "$output" | grep -nF -- "$1" | head -n 1 | cut -d: -f1
}

# prf_body LABEL — the redacted body file the last post sent.
prf_body() {
  cat "$REPO/target/rust-sdlc/tmp/review-$1.md"
}

# prf_secret CLEARTEXT REDACTED — the secret-laden ledger renders REDACTED in
# place of CLEARTEXT.
prf_secret() {
  run "$SCRIPT" security --file "$LEDGERS/secret-laden.json" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"$1"* ]]
  [[ "$output" == *"$2"* ]]
}

# --- usage (exit 2) ------------------------------------------------------------

@test "post-review-findings: --help prints the usage header and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "post-review-findings.sh — "* ]]
  [[ "$output" == *"Usage: post-review-findings.sh <lens> [--pr N] [--file F]... [--dry-run] [--json] [--bot-login LOGIN]"* ]]
  [[ "$output" == *"post-review-findings.sh --conclusion [--file F]... [--pr N] [--started-at ISO] [--ended-at ISO] [--duration-seconds N] [--iterations N]"* ]]
  [[ "$output" == *"Exit: 0 "*"; 1 "*"; 2 "* ]]
  [[ "$output" != *"set -euo pipefail"* ]]
  prf_no_gh
}

@test "post-review-findings: --help is accepted in any position" {
  run "$SCRIPT" security --bogus --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: post-review-findings.sh"* ]]
  run "$SCRIPT" --conclusion --pr 7 --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: post-review-findings.sh"* ]]
}

@test "post-review-findings: an unknown flag exits 2 with a usage error" {
  run "$SCRIPT" security --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"[rust-sdlc][ERROR] unknown argument: --bogus (usage: post-review-findings.sh <lens>"* ]]
  [[ "$output" != *DEGRADED* ]]
  prf_no_gh
}

@test "post-review-findings: an unknown lens exits 2" {
  run "$SCRIPT" bogus-lens --file "$LEDGERS/full.json" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown lens: bogus-lens"* ]]
  prf_no_gh
}

@test "post-review-findings: two lens names in one argument are an unknown lens" {
  run "$SCRIPT" "security fr-nfr" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown lens: security fr-nfr"* ]]
  [[ "$output" != *"DEGRADED"* ]]
  run "$SCRIPT" "fr-nfr code-review" --file "$LEDGERS/with-times.json" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown lens: fr-nfr code-review"* ]]
  [[ "$output" != *"malformed ledger"* ]]
  run "$SCRIPT" "security " --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown lens: security "* ]]
  prf_no_gh
}

@test "post-review-findings: neither a lens nor --conclusion exits 2" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"a lens (security, fr-nfr or code-review) or --conclusion is required"* ]]
}

@test "post-review-findings: conflicting arguments exit 2" {
  run "$SCRIPT" --conclusion security
  [ "$status" -eq 2 ]
  [[ "$output" == *"--conclusion takes no lens"* ]]
  run "$SCRIPT" security fr-nfr
  [ "$status" -eq 2 ]
  [[ "$output" == *"unexpected argument: fr-nfr"* ]]
  run "$SCRIPT" security --dry-run --json
  [ "$status" -eq 2 ]
  [[ "$output" == *"--dry-run and --json are mutually exclusive"* ]]
  run "$SCRIPT" security --pr 7 --pr 8
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pr given twice"* ]]
  prf_no_gh
}

@test "post-review-findings: a flag without its value exits 2" {
  local flag
  for flag in --pr --file --bot-login; do
    run "$SCRIPT" security "$flag"
    [ "$status" -eq 2 ]
    [[ "$output" == *"$flag needs a value"* ]]
  done
  run "$SCRIPT" --conclusion --iterations --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"--iterations needs a value"* ]]
}

@test "post-review-findings: an invalid --pr exits 2 before any gh call" {
  local pr
  prf_ledger full
  prf_gh
  for pr in 0 007 abc 7x 2147483648 99999999999999999999; do
    run "$SCRIPT" fr-nfr --pr "$pr"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--pr must be a pull-request number"* ]]
  done
  prf_no_gh
}

@test "post-review-findings: the conclusion flags with a lens exit 2" {
  run "$SCRIPT" security --started-at 2026-11-10T09:00:00Z
  [ "$status" -eq 2 ]
  [[ "$output" == *"only --conclusion takes --started-at"* ]]
  run "$SCRIPT" security --iterations 3 --duration-seconds 60
  [ "$status" -eq 2 ]
  [[ "$output" == *"only --conclusion takes --iterations --duration-seconds"* ]]
}

@test "post-review-findings: an invalid time, duration or iteration count exits 2" {
  run "$SCRIPT" --conclusion --started-at 2026-13-01T00:00:00Z
  [ "$status" -eq 2 ]
  [[ "$output" == *"--started-at must be a UTC time"* ]]
  run "$SCRIPT" --conclusion --ended-at 2026-11-10T09:00:00
  [ "$status" -eq 2 ]
  [[ "$output" == *"--ended-at must be a UTC time"* ]]
  run "$SCRIPT" --conclusion --duration-seconds 5m
  [ "$status" -eq 2 ]
  [[ "$output" == *"--duration-seconds must be a number"* ]]
  run "$SCRIPT" --conclusion --iterations=-1
  [ "$status" -eq 2 ]
  run "$SCRIPT" --conclusion --iterations x1
  [ "$status" -eq 2 ]
  [[ "$output" == *"--iterations must be a number"* ]]
}

@test "post-review-findings: an invalid --bot-login exits 2" {
  local login
  for login in 'two words' '-leading-dash' 'name;rm' 'a/b'; do
    run "$SCRIPT" security --bot-login "$login"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--bot-login must be a GitHub login"* ]]
  done
  prf_no_gh
}

# --- one comment per lens: create, update, never delete (ADR-26) ----------------

@test "post-review-findings: the first post creates the lens comment with its marker" {
  prf_ledger full
  prf_gh
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: fr-nfr created $COMMENT_URL" ]
  [ "$(prf_calls 'api -X POST repos/acme/billing-service/issues/7/comments -F body=@target/rust-sdlc/tmp/review-fr-nfr.md')" -eq 1 ]
  [ "$(prf_calls 'api -X PATCH ')" -eq 0 ]
  [ "$(prf_calls 'api --paginate repos/acme/billing-service/issues/7/comments\?per_page=100$')" -eq 1 ]
  [ "$(head -n 1 "$REPO/target/rust-sdlc/tmp/review-fr-nfr.md")" = '<!-- rust-sdlc-review:fr-nfr -->' ]
  [ -f "$REPO/target/rust-sdlc/tmp/review-fr-nfr.raw.md" ]
  [[ "$(prf_body fr-nfr)" == *"| Critical | FRN-1 |"* ]]
}

@test "post-review-findings: a second post PATCHes the marker comment of the posting identity" {
  prf_ledger full
  prf_comment 1001 "$BOT" fr-nfr >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: fr-nfr updated 1001" ]
  [ "$(prf_calls 'api -X PATCH repos/acme/billing-service/issues/comments/1001 -F body=@target/rust-sdlc/tmp/review-fr-nfr.md$')" -eq 1 ]
  [ "$(prf_calls 'api -X POST ')" -eq 0 ]
}

@test "post-review-findings: two runs create once and then edit the same comment" {
  prf_ledger mixed-severity
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  : >"$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" code-review --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "POSTED: code-review created "* ]]
  prf_comment 3001 "$BOT" code-review >"$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" code-review --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: code-review updated 3001" ]
  [ "$(prf_calls 'api -X POST ')" -eq 1 ]
  [ "$(prf_calls 'api -X PATCH repos/acme/billing-service/issues/comments/3001 ')" -eq 1 ]
}

@test "post-review-findings: the oldest marker comment of the posting identity is PATCHed" {
  prf_ledger full
  {
    prf_comment 1500 "$BOT" fr-nfr
    prf_comment 1200 "$BOT" fr-nfr
    prf_comment 1800 "$BOT" fr-nfr
  } >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: fr-nfr updated 1200" ]
  [ "$(prf_writes)" -eq 1 ]
  [ "$(prf_calls 'api -X PATCH repos/acme/billing-service/issues/comments/1200 ')" -eq 1 ]
}

@test "post-review-findings: nothing is ever deleted or hidden" {
  prf_ledger full
  {
    prf_comment 1200 "$BOT" fr-nfr
    prf_comment 1500 "$BOT" fr-nfr
    prf_comment 1600 someone-else fr-nfr
  } >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$(prf_calls 'api -X DELETE')" -eq 0 ]
  [ "$(prf_calls 'api graphql')" -eq 0 ]
  [ "$(prf_calls 'pr comment')" -eq 0 ]
  [ "$(prf_calls 'api -X PATCH .*/comments/1(5|6)00 ')" -eq 0 ]
  run grep -qE -- '-X DELETE|minimizeComment|--edit-last|--delete-last' "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "post-review-findings: a marker comment of another lens is not edited" {
  prf_ledger dropped-and-open
  prf_comment 1001 "$BOT" code-review >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" security --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: security created $COMMENT_URL" ]
  [ "$(prf_calls 'api -X PATCH ')" -eq 0 ]
}

@test "post-review-findings: a forged lens marker by another author is ignored and a new comment is created" {
  prf_ledger minimal
  prf_gh "$GH_FIX/pr-issue-comments-forged.ndjson"
  run "$SCRIPT" code-review --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEGRADED: ignored <!-- rust-sdlc-review:code-review --> comment by mallory-forger"* ]]
  [[ "$output" == *"POSTED: code-review created $COMMENT_URL"* ]]
  [[ "$output" != *drive-by-contributor* ]]
  [ "$(prf_calls 'api -X POST ')" -eq 1 ]
  [ "$(prf_calls 'api -X PATCH ')" -eq 0 ]
}

@test "post-review-findings: with the identity unresolved nothing is edited and a new comment is created" {
  prf_ledger minimal
  {
    cat "$GH_FIX/pr-issue-comments-forged.ndjson"
    prf_comment 3005 "$BOT" code-review
  } >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_route 'api user --jq .login' 1
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" code-review --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEGRADED: posting identity unresolved (gh api user failed): a new code-review comment is created and none is edited"* ]]
  [[ "$output" == *"DEGRADED: ignored <!-- rust-sdlc-review:code-review --> comment by mallory-forger"* ]]
  [[ "$output" == *"DEGRADED: ignored <!-- rust-sdlc-review:code-review --> comment by $BOT"* ]]
  [[ "$output" == *"POSTED: code-review created $COMMENT_URL"* ]]
  [ "$(prf_calls 'api -X PATCH ')" -eq 0 ]
  [ "$(prf_calls 'api -X POST ')" -eq 1 ]
}

@test "post-review-findings: --bot-login sets the posting identity without gh api user" {
  prf_ledger full
  prf_comment 1001 'github-actions[bot]' fr-nfr >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" fr-nfr --pr 7 --bot-login 'github-actions[bot]'
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: fr-nfr updated 1001" ]
  [ "$(prf_calls 'api user')" -eq 0 ]
}

@test "post-review-findings: --bot-login matches case-insensitively and ignores older comments by others" {
  prf_ledger full
  {
    prf_comment 900 someone-else fr-nfr
    prf_comment 1001 RUST-SDLC-BOT fr-nfr
  } >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" fr-nfr --pr 7 --bot-login "$BOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEGRADED: ignored <!-- rust-sdlc-review:fr-nfr --> comment by someone-else"* ]]
  [[ "$output" == *"POSTED: fr-nfr updated 1001"* ]]
  [ "$(prf_calls 'api -X PATCH .*/comments/900 ')" -eq 0 ]
}

@test "post-review-findings: without --pr the pull request comes from gh pr view" {
  prf_ledger full
  prf_gh
  run "$SCRIPT" fr-nfr
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: fr-nfr created $COMMENT_URL" ]
  [ "$(prf_calls 'pr view --json number --jq .number')" -eq 1 ]
}

@test "post-review-findings: a listing of raw JSON pages is read like NDJSON" {
  prf_ledger full
  printf '[{"id":10,"user":null,"body":null},{"id":11,"user":{"login":"x"},"body":"hi"}]\n[%s]\n' \
    "$(prf_comment 1001 "$BOT" fr-nfr)" >"$BATS_TEST_TMPDIR/listing.json"
  prf_gh "$BATS_TEST_TMPDIR/listing.json"
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: fr-nfr updated 1001" ]
}

# --- the conclusion ------------------------------------------------------------

@test "post-review-findings: --conclusion creates the conclusion marker comment from the default ledgers" {
  prf_ledger with-times
  prf_ledger full
  prf_ledger minimal
  prf_gh
  run "$SCRIPT" --conclusion --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: conclusion created $COMMENT_URL" ]
  [ "$(prf_calls 'api -X POST repos/acme/billing-service/issues/7/comments -F body=@target/rust-sdlc/tmp/review-conclusion.md')" -eq 1 ]
  [ "$(head -n 1 "$REPO/target/rust-sdlc/tmp/review-conclusion.md")" = '<!-- rust-sdlc-review:conclusion -->' ]
  [[ "$(prf_body conclusion)" == *"| security | 2 | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 0 |"* ]]
}

@test "post-review-findings: a second --conclusion edits the conclusion instead of adding one" {
  prf_ledger full
  {
    prf_comment 1001 "$BOT" fr-nfr
    prf_comment 1400 "$BOT" conclusion
  } >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" --conclusion --pr 7 --iterations 2
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: conclusion updated 1400" ]
  [ "$(prf_calls 'api -X POST ')" -eq 0 ]
  [ "$(prf_writes)" -eq 1 ]
}

@test "post-review-findings: a conclusion by another author does not count" {
  prf_ledger full
  prf_gh "$GH_FIX/pr-issue-comments-forged.ndjson"
  run "$SCRIPT" --conclusion --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEGRADED: ignored <!-- rust-sdlc-review:conclusion --> comment by drive-by-contributor"* ]]
  [[ "$output" == *"POSTED: conclusion created $COMMENT_URL"* ]]
  [ "$(prf_calls 'api -X PATCH ')" -eq 0 ]
  [ "$(prf_calls 'api -X POST ')" -eq 1 ]
}

@test "post-review-findings: --conclusion takes started_at and ended_at from the ledgers" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/with-times.json" --file "$LEDGERS/minimal.json" --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "WOULD: post conclusion" ]
  [[ "$output" == *"- Started: 2026-11-10T09:00:00Z"* ]]
  [[ "$output" == *"- Ended: 2026-11-10T09:05:30Z"* ]]
  [[ "$output" == *"- Duration: 5m 30s (330 s)"* ]]
  prf_no_gh
}

@test "post-review-findings: --started-at and --ended-at override the ledger times" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/with-times.json" --dry-run \
    --started-at 2026-11-10T08:00:00Z --ended-at 2026-11-10T09:00:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *"- Started: 2026-11-10T08:00:00Z"* ]]
  [[ "$output" == *"- Ended: 2026-11-10T09:00:00Z"* ]]
  [[ "$output" == *"- Duration: 1h 00m 00s (3600 s)"* ]]
  [[ "$output" != *"09:05:30"* ]]
}

@test "post-review-findings: --duration-seconds and --iterations are rendered only when given" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/minimal.json" --dry-run --duration-seconds 3725 --iterations 04
  [ "$status" -eq 0 ]
  [[ "$output" == *"- Duration: 1h 02m 05s (3725 s)"* ]]
  [[ "$output" == *"- Iterations: 4"* ]]
  run "$SCRIPT" --conclusion --file "$LEDGERS/minimal.json" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"Duration:"* ]]
  [[ "$output" != *"Iterations:"* ]]
  [[ "$output" != *"Started:"* ]]
}

@test "post-review-findings: --conclusion counts each lens, excludes dropped findings and marks a missing ledger" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --file "$LEDGERS/minimal.json" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| security | no ledger | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |"* ]]
  [[ "$output" == *"| fr-nfr | 3 | 1 | 1 | 1 | 1 | 1 | 4 | 1 | 1 |"* ]]
  [[ "$output" == *"| code-review | 1 | 0 | 0 | 1 | 0 | 0 | 1 | 0 | 0 |"* ]]
  [[ "$output" == *"| **all** | | 1 | 1 | 2 | 1 | 1 | 5 | 1 | 1 |"* ]]
}

@test "post-review-findings: --conclusion without any ledger is a degrade" {
  prf_gh
  run "$SCRIPT" --conclusion --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: no review ledger at target/rust-sdlc/review-ledgers/security.json, "* ]]
  prf_no_gh
}

# --- rendering -------------------------------------------------------------------

@test "post-review-findings: findings with the same (file, line, rule) render once, null read as empty" {
  run "$SCRIPT" fr-nfr --file "$LEDGERS/dedup-pair.json" --dry-run
  [ "$status" -eq 0 ]
  [ "$(prf_rows)" -eq 1 ]
  [[ "$output" == *"| High | FRN-1 | requirement-level | FR-7 | open |"* ]]
  [[ "$output" != *"SECOND-FINDING-SAME-KEY"* ]]
}

@test "post-review-findings: the same file:line with distinct rules is kept and a pipe is escaped" {
  run "$SCRIPT" code-review --file "$LEDGERS/pipe-and-distinct.json" --dry-run
  [ "$status" -eq 0 ]
  [ "$(prf_rows)" -eq 2 ]
  [[ "$output" == *"| CQ-1 | crates/billing/invoice/application/src/create_invoice.rs:31 | Q2 |"* ]]
  [[ "$output" == *"| CQ-2 | crates/billing/invoice/application/src/create_invoice.rs:31 | Q3 |"* ]]
  [[ "$output" == *'splits on a literal \| separator'* ]]
  [[ "$output" != *'literal | separator'* ]]
}

@test "post-review-findings: findings are sorted Critical, High, Medium, Low, Info" {
  run "$SCRIPT" code-review --file "$LEDGERS/mixed-severity.json" --dry-run
  [ "$status" -eq 0 ]
  [ "$(prf_rows)" -eq 5 ]
  [ "$(prf_line '| Critical | CQ-2 |')" -lt "$(prf_line '| High | CQ-5 |')" ]
  [ "$(prf_line '| High | CQ-5 |')" -lt "$(prf_line '| Medium | CQ-4 |')" ]
  [ "$(prf_line '| Medium | CQ-4 |')" -lt "$(prf_line '| Low | CQ-1 |')" ]
  [ "$(prf_line '| Low | CQ-1 |')" -lt "$(prf_line '| Info | CQ-3 |')" ]
}

@test "post-review-findings: dropped findings are filtered and open ones kept" {
  run "$SCRIPT" security --file "$LEDGERS/dropped-and-open.json" --dry-run
  [ "$status" -eq 0 ]
  [ "$(prf_rows)" -eq 1 ]
  [[ "$output" == *"| Medium | SEC-1 |"* ]]
  [[ "$output" != *"SEC-2"* ]]
  [[ "$output" != *"NOT-REPRODUCED-DROPPED"* ]]
  [[ "$output" == *"1 dropped finding is not shown."* ]]
}

@test "post-review-findings: a requirement-level finding renders without a location" {
  run "$SCRIPT" fr-nfr --file "$LEDGERS/null-location.json" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| High | FRN-1 | requirement-level | FR-3 | open | Acceptance criterion AC-3.2 (overdue invoices are listed first) is not implemented |"* ]]
  [[ "$output" != *null* ]]
  [[ "$output" != *None* ]]
}

@test "post-review-findings: a 20-digit iteration is printed verbatim" {
  run "$SCRIPT" code-review --file "$LEDGERS/20-digit-iteration.json" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ledger iteration 18446744073709551617 at \`a1b2c3d\`."* ]]
  run --separate-stderr "$SCRIPT" code-review --file "$LEDGERS/20-digit-iteration.json" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -I -c 'import json, sys; assert json.load(sys.stdin)["iteration"] == "18446744073709551617"'
}

@test "post-review-findings: redact masks an AWS access key id before rendering" {
  prf_secret AKIAIOSFODNN7EXAMPLE 'access key id AKIA[REDACTED] in'
}

@test "post-review-findings: redact masks a JWT before rendering" {
  prf_secret eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 'bearer JWT [REDACTED] |'
}

@test "post-review-findings: redact masks a ghp_ token before rendering" {
  prf_secret ghp_EXAMPLEonlyNotReal00 'token ghp_[REDACTED] committed'
}

@test "post-review-findings: redact masks a github_pat_ token before rendering" {
  prf_secret github_pat_EXAMPLE_ONLY_NOT_REAL_0 'token github_pat_[REDACTED] left'
}

@test "post-review-findings: redact masks a PEM private-key block before rendering" {
  prf_secret 'EXAMPLE-ONLY-NOT-A-KEY' 'helper embeds [REDACTED] inline'
  [[ "$output" != *"PRIVATE KEY"* ]]
}

@test "post-review-findings: redact masks an Authorization header value before rendering" {
  prf_secret example-only-bearer-value 'header Authorization: Bearer [REDACTED] |'
}

@test "post-review-findings: redact masks a DB_PASSWORD= assignment before rendering" {
  prf_secret 'DB_PASSWORD=example-only' 'sets DB_PASSWORD=[REDACTED] in plain text'
}

@test "post-review-findings: redact masks URL credentials before rendering" {
  prf_secret 'billing:example-only@' 'string postgres://[REDACTED]@db.example.invalid/billing is'
}

@test "post-review-findings: redact masks a long mixed base64 run before rendering" {
  prf_secret ZXhhbXBsZS1vbmx5LW5vdC1hLXJlYWwtc2lnbmluZy1rZXktMDEyMw 'material [REDACTED] is embedded'
}

@test "post-review-findings: the --json payload and the published body carry only redacted text" {
  local secret
  run --separate-stderr "$SCRIPT" security --file "$LEDGERS/secret-laden.json" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" >"$BATS_TEST_TMPDIR/payload.json"
  prf_gh
  run "$SCRIPT" security --file "$LEDGERS/secret-laden.json" --pr 7
  [ "$status" -eq 0 ]
  for secret in AKIAIOSFODNN7EXAMPLE eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 ghp_EXAMPLEonlyNotReal00 \
    EXAMPLE_ONLY_NOT_REAL_0 EXAMPLE-ONLY-NOT-A-KEY example-only-bearer-value 'DB_PASSWORD=example-only' \
    'billing:example-only@' ZXhhbXBsZS1vbmx5LW5vdC1hLXJlYWwtc2lnbmluZy1rZXktMDEyMw; do
    # grep exits 1 when no file holds the secret (2 when a file is missing).
    run grep -qF -- "$secret" "$BATS_TEST_TMPDIR/payload.json" \
      "$REPO/target/rust-sdlc/tmp/review-security.md" "$REPO/target/rust-sdlc/tmp/review-security.raw.md"
    [ "$status" -eq 1 ]
  done
  grep -qF 'AKIA[REDACTED]' "$REPO/target/rust-sdlc/tmp/review-security.md"
}

@test "post-review-findings: each finding is redacted on its own, a secret never spans two findings" {
  local ledger
  ledger="$(prf_variant minimal spanning '
f = d["findings"][0]
f["summary"] = "Config line ends with SERVICE_TOKEN:"
g = dict(f, id="CQ-2", line=28, rule="Q4", summary="Key -----BEGIN RSA PRIV" "ATE KEY----- EXAMPLE-ONLY with no end line")
h = dict(f, id="CQ-3", file="crates/billing/invoice/domain/src/after_the_key.rs", line=5, rule="Q5", summary="A later finding stays readable")
d["findings"] = [f, g, h]
')"
  run "$SCRIPT" code-review --file "$ledger" --dry-run
  [ "$status" -eq 0 ]
  [ "$(prf_rows)" -eq 3 ]
  [[ "$output" == *"| Config line ends with SERVICE_TOKEN: |"* ]]
  [[ "$output" == *"| Key [REDACTED] |"* ]]
  [[ "$output" == *"| CQ-3 | crates/billing/invoice/domain/src/after_the_key.rs:5 | Q5 | open | A later finding stays readable |"* ]]
  [[ "$output" != *"EXAMPLE-ONLY"* ]]
}

@test "post-review-findings: --json prints the payload, which parses with jq and python3" {
  run --separate-stderr "$SCRIPT" fr-nfr --file "$LEDGERS/full.json" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
assert d["lens"] == "fr-nfr" and d["marker"] == "<!-- rust-sdlc-review:fr-nfr -->"
assert d["iteration"] == "3" and d["head_sha"].startswith("a1b2c3d")
assert [f["id"] for f in d["findings"]] == ["FRN-1", "FRN-2", "FRN-3", "FRN-4", "FRN-5"]
assert d["counts"]["total"] == 5 and d["counts"]["dropped"] == 1 and d["counts"]["open"] == 4
assert d["body"].startswith(d["marker"] + "\n")
'
  if type -P jq >/dev/null 2>&1; then
    printf '%s' "$output" | jq -e '.lens == "fr-nfr" and (.findings | length) == 5' >/dev/null
  fi
  prf_no_gh
  [ ! -e "$REPO/target/rust-sdlc/tmp" ]
}

@test "post-review-findings: --json with --conclusion prints the conclusion payload" {
  run --separate-stderr "$SCRIPT" --conclusion --file "$LEDGERS/with-times.json" --json --iterations 3
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
assert d["lens"] == "conclusion" and d["marker"] == "<!-- rust-sdlc-review:conclusion -->"
assert d["started_at"] == "2026-11-10T09:00:00Z" and d["ended_at"] == "2026-11-10T09:05:30Z"
assert d["duration_seconds"] == "330" and d["iterations"] == "3"
assert d["lenses"]["fr-nfr"] is None and d["lenses"]["security"]["counts"]["Low"] == 1
'
  if type -P jq >/dev/null 2>&1; then
    printf '%s' "$output" | jq -e '.totals.total == 1' >/dev/null
  fi
}

@test "post-review-findings: --dry-run prints WOULD: post <lens>, calls no gh and writes nothing" {
  prf_gh
  run "$SCRIPT" security --file "$LEDGERS/dropped-and-open.json" --dry-run --pr 7
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "WOULD: post security" ]
  [ "${lines[1]}" = "<!-- rust-sdlc-review:security -->" ]
  [[ "$output" != *POSTED* ]]
  prf_no_gh
  [ ! -e "$REPO/target/rust-sdlc/tmp" ]
}

@test "post-review-findings: the default ledger is target/rust-sdlc/review-ledgers/<lens>.json" {
  prf_ledger mixed-severity
  run "$SCRIPT" code-review --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "WOULD: post code-review" ]
  [ "$(prf_rows)" -eq 5 ]
  run "$SCRIPT" security --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: no security ledger at target/rust-sdlc/review-ledgers/security.json; the security comment is not posted" ]
}

@test "post-review-findings: SDLC_LEDGER_DIR moves the default ledgers" {
  mkdir -p "$BATS_TEST_TMPDIR/ledgers"
  cp "$LEDGERS/null-location.json" "$BATS_TEST_TMPDIR/ledgers/fr-nfr.json"
  cp "$LEDGERS/with-times.json" "$BATS_TEST_TMPDIR/ledgers/security.json"
  SDLC_LEDGER_DIR="$BATS_TEST_TMPDIR/ledgers" run "$SCRIPT" fr-nfr --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| High | FRN-1 | requirement-level |"* ]]
  SDLC_LEDGER_DIR="$BATS_TEST_TMPDIR/ledgers" run "$SCRIPT" --conclusion --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| fr-nfr | 2 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 0 |"* ]]
  [[ "$output" == *"| security | 2 | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 0 |"* ]]
  [[ "$output" == *"| code-review | no ledger |"* ]]
}

@test "post-review-findings: repeated --file ledgers of one lens are merged and deduplicated" {
  run "$SCRIPT" fr-nfr --file "$LEDGERS/full.json" --file "$LEDGERS/full.json" --dry-run
  [ "$status" -eq 0 ]
  [ "$(prf_rows)" -eq 5 ]
  run "$SCRIPT" fr-nfr --file "$LEDGERS/full.json" --file "$LEDGERS/dedup-pair.json" --dry-run
  [ "$status" -eq 0 ]
  [ "$(prf_rows)" -eq 6 ]
  [[ "$output" == *"| FR-7 |"* ]]
}

# --- degrade-first (exit 0, nothing posted) --------------------------------------

@test "post-review-findings: publishing off (publish-off.yml) is a degrade without a gh call, also with --dry-run" {
  cp "$PROFILES/publish-off.yml" "$REPO/.claude/rust-sdlc.yml"
  prf_ledger full
  prf_gh
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: capabilities.publish_pr_comments is false; the fr-nfr comment is not posted" ]
  run "$SCRIPT" fr-nfr --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: capabilities.publish_pr_comments is false"* ]]
  [[ "$output" != *WOULD* ]]
  run "$SCRIPT" --conclusion --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: capabilities.publish_pr_comments is false; the conclusion comment is not posted" ]]
  prf_no_gh
}

@test "post-review-findings: no profile is a degrade" {
  rm "$REPO/.claude/rust-sdlc.yml"
  prf_ledger full
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: no profile at "*"/.claude/rust-sdlc.yml, so capabilities.publish_pr_comments is not true; the fr-nfr comment is not posted" ]]
  prf_no_gh
}

@test "post-review-findings: gh absent is a degrade" {
  local sandbox
  prf_ledger full
  sandbox="$(sandbox_path bash cat dirname git mktemp python3 rm tr)"
  run env PATH="$sandbox" "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: gh not found on PATH; the fr-nfr comment is not posted" ]
}

@test "post-review-findings: no pull request for the current branch is a degrade" {
  prf_ledger full
  prf_route 'pr view *' 1
  prf_gh
  run "$SCRIPT" fr-nfr
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: no pull request for the current branch; the fr-nfr comment is not posted" ]
  [ "$(prf_writes)" -eq 0 ]
}

@test "post-review-findings: an empty ledger is a degrade without a gh call" {
  prf_ledger empty
  prf_gh
  run "$SCRIPT" security --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: no findings to post from target/rust-sdlc/review-ledgers/security.json (the ledger is empty); the security comment is not posted" ]]
  prf_no_gh
}

@test "post-review-findings: an all-dropped ledger is a degrade without a gh call" {
  local ledger
  ledger="$(prf_variant dropped-and-open all-dropped 'for f in d["findings"]: f["status"] = "dropped"')"
  prf_gh
  run "$SCRIPT" security --file "$ledger" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: no findings to post from "*"(every finding is dropped); the security comment is not posted" ]]
  prf_no_gh
}

@test "post-review-findings: schema_version 2 is a degrade, also with --file" {
  prf_ledger wrong-schema-version
  prf_gh
  run "$SCRIPT" security --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: ledger target/rust-sdlc/review-ledgers/security.json has schema_version 2, and only schema_version 1 is read"* ]]
  run "$SCRIPT" security --file "$LEDGERS/wrong-schema-version.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: ledger "*"wrong-schema-version.json has schema_version 2"* ]]
  run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --file "$LEDGERS/wrong-schema-version.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: ledger "*"has schema_version 2"*"the conclusion comment is not posted" ]]
  prf_no_gh
}

@test "post-review-findings: a ledger without schema_version reads as version 1" {
  local ledger
  ledger="$(prf_variant minimal no-version 'del d["schema_version"]')"
  run "$SCRIPT" code-review --file "$ledger" --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "WOULD: post code-review" ]
  [[ "$output" == *"| Medium | CQ-1 |"* ]]
}

@test "post-review-findings: a malformed comment listing is a degrade and nothing is posted" {
  prf_ledger full
  prf_gh "$(prf_value listing-bad.txt '<html>502 Bad Gateway</html>')"
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: malformed gh read: the comment listing of pull request #7 is not a list of comments; the fr-nfr comment is not posted" ]
  [ "$(prf_writes)" -eq 0 ]
  [ ! -e "$REPO/target/rust-sdlc/tmp/review-fr-nfr.md" ]
}

@test "post-review-findings: a comment listing with a malformed comment or a failed read is a degrade" {
  prf_ledger full
  prf_gh "$(prf_value listing-noid.json '[{"user":{"login":"x"},"body":"hi"}]')"
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: malformed gh read: the comment listing"* ]]
  : >"$STUB_GH_ROUTES"
  prf_route 'api --paginate *' 1
  prf_gh
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: malformed gh read: cannot list the comments of pull request #7; the fr-nfr comment is not posted" ]
  [ "$(prf_writes)" -eq 0 ]
}

@test "post-review-findings: an unreadable base repository is a degrade" {
  prf_ledger full
  prf_route 'api repos/acme/billing-service/pulls/7 *' 1
  prf_gh
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: malformed gh read: cannot read pull request #7 of acme/billing-service; the fr-nfr comment is not posted" ]
  : >"$STUB_GH_ROUTES"
  prf_route 'api repos/acme/billing-service/pulls/7 *' 0 "$(prf_value base-bad.txt 'not a slug')"
  prf_gh
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: malformed gh read: the base repository of pull request #7 is not owner/name"* ]]
  [ "$(prf_writes)" -eq 0 ]
}

@test "post-review-findings: a base repository other than the origin is refused" {
  prf_ledger full
  prf_route 'api repos/acme/billing-service/pulls/7 *' 0 "$(prf_value base-other.txt evil/other-repo)"
  prf_gh
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: base repository evil/other-repo of pull request #7 is not the origin repository acme/billing-service; the fr-nfr comment is not posted" ]
  [ "$(prf_writes)" -eq 0 ]
  [ "$(prf_calls 'api --paginate')" -eq 0 ]
}

@test "post-review-findings: a failed create is a degrade with exit 0" {
  prf_ledger full
  prf_route 'api -X POST *' 1
  prf_gh
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: gh could not create the fr-nfr comment on pull request #7 (write failure)" ]
  [[ "$output" != *POSTED* ]]
}

@test "post-review-findings: a failed update is a degrade with exit 0" {
  prf_ledger full
  prf_comment 1001 "$BOT" fr-nfr >"$BATS_TEST_TMPDIR/listing.ndjson"
  prf_route 'api -X PATCH *' 1
  prf_gh "$BATS_TEST_TMPDIR/listing.ndjson"
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "DEGRADED: gh could not update comment 1001 on pull request #7 (write failure); the fr-nfr comment is unchanged" ]
  [ "$(prf_calls 'api -X POST ')" -eq 0 ]
}

@test "post-review-findings: a body file that cannot be written safely is a degrade" {
  prf_ledger full
  prf_gh
  mkdir -p "$REPO/target/rust-sdlc" "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$REPO/target/rust-sdlc/tmp"
  run "$SCRIPT" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEGRADED: cannot write target/rust-sdlc/tmp/review-fr-nfr.raw.md; the fr-nfr comment is not posted"* ]]
  [ "$(prf_writes)" -eq 0 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/elsewhere")" ]
}

# --- malformed ledgers named with --file (exit 1) ---------------------------------

@test "post-review-findings: an extra key in a --file ledger exits 1 and posts nothing" {
  prf_gh
  run "$SCRIPT" security --file "$LEDGERS/extra-key.json" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] malformed ledger "*"extra-key.json: findings[1]: extra key \"cwe\""* ]]
  [[ "$output" != *DEGRADED* ]]
  [[ "$output" != *Traceback* ]]
  prf_no_gh
}

@test "post-review-findings: an extra key in the default ledger is a degrade" {
  prf_ledger extra-key
  prf_gh
  run "$SCRIPT" security --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == "DEGRADED: malformed ledger target/rust-sdlc/review-ledgers/security.json: findings[1]: extra key \"cwe\"; the security comment is not posted" ]]
  prf_no_gh
}

@test "post-review-findings: a --file ledger that is not JSON, absent or of another lens exits 1" {
  printf 'this is not json {\n' >"$BATS_TEST_TMPDIR/bad.json"
  run "$SCRIPT" security --file "$BATS_TEST_TMPDIR/bad.json" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] malformed ledger "*"bad.json: not JSON"* ]]
  [[ "$output" != *Traceback* ]]
  run "$SCRIPT" security --file "$BATS_TEST_TMPDIR/absent.json" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"ledger file not found: "*"absent.json"* ]]
  run "$SCRIPT" security --file "$LEDGERS/full.json" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is a fr-nfr ledger, not a security ledger"* ]]
  run "$SCRIPT" --conclusion --file "$BATS_TEST_TMPDIR/bad.json" --dry-run
  [ "$status" -eq 1 ]
  prf_no_gh
}

@test "post-review-findings: ADR-16 field violations in a --file ledger exit 1" {
  local ledger
  ledger="$(prf_variant minimal bad-id 'd["findings"][0]["id"] = "cq-1"')"
  run "$SCRIPT" code-review --file "$ledger" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *'findings[0].id: "cq-1" does not match'* ]]
  ledger="$(prf_variant minimal bad-severity 'd["findings"][0]["severity"] = "Blocker"')"
  run "$SCRIPT" code-review --file "$ledger" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *'findings[0].severity: "Blocker" is not one of'* ]]
  ledger="$(prf_variant minimal line-zero 'd["findings"][0]["line"] = 0')"
  run "$SCRIPT" code-review --file "$ledger" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"findings[0].line: 0 is not an integer >= 1 or null"* ]]
  ledger="$(prf_variant minimal extra-top 'd["cwe"] = "CWE-1"')"
  run "$SCRIPT" code-review --file "$ledger" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *'extra top-level key "cwe"'* ]]
  ledger="$(prf_variant with-times bad-time 'd["started_at"] = "2026-11-10T9:00:00Z"')"
  run "$SCRIPT" --conclusion --file "$ledger" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"started_at is not YYYY-MM-DDTHH:MM:SSZ"* ]]
}

# --- script contract -------------------------------------------------------------

@test "post-review-findings: the script holds no NUL byte" {
  # The AC wording `grep -c $'\x00'` cannot express this in bash (the
  # argument is cut at the NUL, so grep counts every line); count the bytes.
  [ "$(tr -cd '\000' <"$SCRIPT" | wc -c)" -eq 0 ]
  [ -x "$SCRIPT" ]
  head -n 1 "$SCRIPT" | grep -qx '#!/usr/bin/env bash'
}

@test "post-review-findings: runs from a copied plugin root (install cache)" {
  local cache="$BATS_TEST_TMPDIR/install-cache/rust-backend-sdlc"
  mkdir -p "$(dirname "$cache")"
  cp -R "$PLUGIN_ROOT" "$cache"
  prf_ledger null-location
  prf_gh
  CLAUDE_PLUGIN_ROOT="$cache" run "$cache/scripts/post-review-findings.sh" fr-nfr --pr 7
  [ "$status" -eq 0 ]
  [ "$output" = "POSTED: fr-nfr created $COMMENT_URL" ]
}
