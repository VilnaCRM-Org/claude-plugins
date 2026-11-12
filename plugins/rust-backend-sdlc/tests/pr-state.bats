#!/usr/bin/env bats
# pr-state.bats — cases of scripts/pr-state.sh (FR-38, AC-38.1, AC-21.3, D8,
# D9, ADR-23).
#
# Hermetic: the shared gh stub of tests/fixtures/bin answers every call
# through a routes file (strict: an unexpected call exits 9). One snapshot
# makes five gh calls (pr view, reviews, issue comments, the GraphQL thread
# query of get-pr-comments.sh, the head's check suites); each is routed to a
# fixture of tests/fixtures/gh/pr-state/ chosen by a PS_* variable, so every
# verdict is pinned against a known PR shape. A suite-local wrapper in front
# of the stub switches to a second routes file from the second `gh pr view 7`
# call on (PS_PR_2), for the wait-mode cases. The repository is materialized
# at $BATS_TEST_TMPDIR/billing-service (origin acme/billing-service) with the
# golden profile at .claude/rust-sdlc.yml; the cases ported from the react
# suite run on a parity profile (no required or human-gated check, reviewers
# coderabbit and cubic), the profile-default cases restore the golden one.
# SDLC_NOW_EPOCH pins "now" to 2026-09-01T11:00:00Z, 30 minutes after the
# fixture head was pushed.
#
# shellcheck disable=SC2030,SC2031 # bats cases are subshells

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  SCRIPT="$PLUGIN_ROOT/scripts/pr-state.sh"
  FX="$PLUGIN_ROOT/tests/fixtures/gh/pr-state"
  GH_FIX="$PLUGIN_ROOT/tests/fixtures/gh"
  GOLDEN="$PLUGIN_ROOT/tests/fixtures/profiles/golden.yml"
  REPO="$BATS_TEST_TMPDIR/billing-service"
  PROFILE="$REPO/.claude/rust-sdlc.yml"
  HEAD_SHA=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
  rr_materialize "$REPO"
  mkdir -p "$REPO/.claude"
  ps_parity_profile
  cd "$REPO" || return 1
  PS_PR="$FX/pr-open-green.json"
  PS_PR_2=""
  PS_PR_EXIT=0
  PS_NUMBER_EXIT=0
  PS_REVIEWS="$FX/reviews-approved.ndjson"
  PS_COMMENTS="$FX/comments-quiet.ndjson"
  PS_THREADS="$FX/threads-empty.json"
  PS_THREADS_EXIT=0
  PS_PUSHED_AT=""
  PS_SUITES_EXIT=0
  export STUB_GH_STRICT=1
  ps_install_gh
  export SDLC_NOW_EPOCH=1788260400
}

# --- suite helpers (ps_) -------------------------------------------------------

# ps_parity_profile — the golden profile with the react suite's implicit
# defaults: no required check, no human-gated check, reviewers coderabbit and
# cubic.
ps_parity_profile() {
  cp "$GOLDEN" "$PROFILE"
  mutate_profile "$PROFILE" ci.required_checks '[]'
  mutate_profile "$PROFILE" ci.human_gated '[]'
  mutate_profile "$PROFILE" review.reviewers $'\n    - coderabbit\n    - cubic'
}

# ps_golden_profile — the golden profile unchanged (36 required checks, three
# human-gated checks, reviewer coderabbit).
ps_golden_profile() {
  cp "$GOLDEN" "$PROFILE"
}

# ps_install_gh — a gh wrapper first on PATH: from the second `gh pr view 7`
# call on, the shared stub answers from the second routes file.
ps_install_gh() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<EOF
#!/usr/bin/env bash
if [[ "\${1-} \${2-} \${3-}" == "pr view 7" ]] && grep -q '^gh pr view 7 ' "\$STUB_GH_LOG" 2>/dev/null; then
  export STUB_GH_ROUTES="\$PS_ROUTES_2"
fi
exec "$PLUGIN_ROOT/tests/fixtures/bin/gh" "\$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export PATH
}

# ps_write_routes FILE PR_FIXTURE — one routes file for the shared gh stub.
ps_write_routes() {
  local file="$1" pr="$2" pushed=-
  printf '7\n' >"$BATS_TEST_TMPDIR/pr-number"
  if [[ -n "$PS_PUSHED_AT" ]]; then
    printf '"%s"\n' "$PS_PUSHED_AT" >"$BATS_TEST_TMPDIR/pushed-at"
    pushed="$BATS_TEST_TMPDIR/pushed-at"
  fi
  {
    printf '%s\t%s\t%s\n' 'pr view --json number --jq .number' "$PS_NUMBER_EXIT" "$BATS_TEST_TMPDIR/pr-number"
    printf '%s\t%s\t%s\n' 'pr view 7 --repo acme/billing-service --json *' "$PS_PR_EXIT" "$pr"
    printf '%s\t%s\t%s\n' 'api repos/acme/billing-service/pulls/7/reviews?per_page=100 --paginate *' 0 "$PS_REVIEWS"
    printf '%s\t%s\t%s\n' 'api repos/acme/billing-service/issues/7/comments?per_page=100 --paginate *' 0 "$PS_COMMENTS"
    printf '%s\t%s\t%s\n' 'api graphql *' "$PS_THREADS_EXIT" "$PS_THREADS"
    printf '%s\t%s\t%s\n' "api repos/acme/billing-service/commits/$HEAD_SHA/check-suites?per_page=100 *" "$PS_SUITES_EXIT" "$pushed"
  } >"$file"
}

# ps_routes — write both routes files from the PS_* variables.
ps_routes() {
  ps_write_routes "$BATS_TEST_TMPDIR/gh-routes.tsv" "$PS_PR"
  ps_write_routes "$BATS_TEST_TMPDIR/gh-routes-2.tsv" "${PS_PR_2:-$PS_PR}"
  export STUB_GH_ROUTES="$BATS_TEST_TMPDIR/gh-routes.tsv"
  export PS_ROUTES_2="$BATS_TEST_TMPDIR/gh-routes-2.tsv"
}

# ps_run [--separate-stderr] ARG... — routes, then `run` the script.
ps_run() {
  local opts=()
  if [[ "${1-}" == --separate-stderr ]]; then
    opts+=("$1")
    shift
  fi
  ps_routes
  run "${opts[@]}" "$SCRIPT" "$@"
}

# ps_calls — number of snapshots taken (`gh pr view 7 …` calls).
ps_calls() {
  grep -c '^gh pr view 7 ' "$STUB_GH_LOG" || true
}

# ps_json PYTHON — run PYTHON (asserts) with the last run's stdout as `d`.
ps_json() {
  printf '%s' "$output" | python3 -I -c "import json, sys
d = json.load(sys.stdin)
$1"
}

# ps_gate_only_payload — prints the path of an open PR payload that reports
# no check run at all, only the FR/NFR gate status as SUCCESS.
ps_gate_only_payload() {
  python3 -I - "$FX/pr-open-nochecks.json" "$BATS_TEST_TMPDIR/pr-gate-only.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
payload["statusCheckRollup"] = [
    {"__typename": "StatusContext", "context": "BMAD FR/NFR Review Gate", "state": "SUCCESS"}]
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY
  printf '%s\n' "$BATS_TEST_TMPDIR/pr-gate-only.json"
}

# ps_service_doc — docs/repository-settings-service.md of a service that adds
# the workflow behind "Invoice PDF rendering" and an approval label for it.
ps_service_doc() {
  cat >"$REPO/docs/repository-settings-service.md" <<'EOF'
# Repository settings of this service

## Required status checks

### `pdf.yml` (PDF)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `invoice-pdf` | Invoice PDF rendering | none | yes |

## Labels to create

| Label | Purpose |
| --- | --- |
| `approved-pdf-layout` | a maintainer approves an invoice layout change; without it the job `invoice-pdf` fails |
EOF
}

# --- usage ---------------------------------------------------------------------

@test "pr-state: --help in any position prints the usage header, exits 0 and calls no gh" {
  run "$SCRIPT" --pr 7 --json --help
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "pr-state.sh — "* ]]
  [[ "$output" == *"Usage: pr-state.sh [--pr N] [--reviewers LIST] [--required-checks LIST] [--human-gated-checks LIST]"* ]]
  [[ "$output" == *"Exit: 0 a snapshot was rendered"* ]]
  [[ "$output" != *"set -euo pipefail"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "pr-state: an unknown flag or a flag without a value is a usage error with exit 1 (react parity)" {
  run "$SCRIPT" --pr 7 --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] unknown argument: --bogus (usage: pr-state.sh [--pr N]"* ]]
  run "$SCRIPT" --pr
  [ "$status" -eq 1 ]
  [[ "$output" == *"--pr needs a value"* ]]
  run "$SCRIPT" --pr 7 --reviewers --json
  [ "$status" -eq 1 ]
  [[ "$output" == *"--reviewers needs a value"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "pr-state: --pr must be a pull-request number without leading zeros within the GraphQL Int range" {
  for bad in 0 007 abc 2147483648 -1; do
    run "$SCRIPT" --pr "$bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--pr must be a pull-request number"* ]]
  done
  [ ! -s "$STUB_GH_LOG" ]
}

@test "pr-state: unknown reviewer and bad numbers are usage errors" {
  run "$SCRIPT" --pr 7 --reviewers copilot
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown reviewer 'copilot'"* ]]
  run "$SCRIPT" --pr 7 --wait-seconds soon
  [ "$status" -eq 1 ]
  [[ "$output" == *"--wait-seconds must be a non-negative integer"* ]]
}

@test "pr-state: leading-zero durations, empty reviewer elements and duplicate reviewers are usage errors" {
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

@test "pr-state: an SDLC_NOW_EPOCH that is not an integer is refused with exit 1" {
  export SDLC_NOW_EPOCH=soon
  ps_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"SDLC_NOW_EPOCH is not a non-negative integer"* ]]
  [[ "$output" != *"VERDICT:"* ]]
}

# --- verdicts (react cases) ------------------------------------------------------

@test "pr-state: READY when checks are green, no threads are open and both bots approve the head" {
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: green"* ]]
  [[ "$output" == *"UNRESOLVED: 0"* ]]
  [[ "$output" == *"REVIEWER: coderabbit status=APPROVED head=current"* ]]
  [[ "$output" == *"REVIEWER: cubic status=APPROVED head=current"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
  [[ "$output" == *"NEXT: exit condition met — hand the PR to its human merger"* ]]
}

@test "pr-state: a dismissed review never counts; the latest live review decides" {
  ps_run --pr 7 --reviewers cubic
  [ "$status" -eq 0 ]
  [[ "$output" == *"cubic status=APPROVED"* ]]
  [[ "$output" != *"REVIEWER: coderabbit"* ]]
}

@test "pr-state: FIX when a check fails or review threads are unresolved, naming both fixers" {
  PS_PR="$FX/pr-open-red.json"
  PS_THREADS="$GH_FIX/pr-comments.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: red failing=[unit testing] pending=[e2e testing]"* ]]
  [[ "$output" == *"UNRESOLVED: 1 (coderabbit=1)"* ]]
  [[ "$output" == *"VERDICT: FIX"* ]]
  [[ "$output" == *"NEXT: fix failing checks unit testing (ci-fixer); resolve 1 review thread(s) (pr-comment-resolver); then commit and push"* ]]
}

@test "pr-state: REQUEST when a reviewer last reviewed an older commit" {
  PS_REVIEWS="$FX/reviews-cubic-stale.ndjson"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"REVIEWER: cubic status=STALE — last live review is on 0123456"* ]]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
  [[ "$output" == *"NEXT: request-ai-reviews.sh --pr 7 --reviewers cubic"* ]]
  [[ "$output" != *"--full"* ]]
}

@test "pr-state: a never-reviewed PR asks for every reviewer" {
  PS_REVIEWS="$FX/reviews-none.ndjson"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"coderabbit status=NONE"* ]]
  [[ "$output" == *"cubic status=NONE"* ]]
  [[ "$output" == *"NEXT: request-ai-reviews.sh --pr 7 --reviewers coderabbit,cubic"* ]]
}

@test "pr-state: CodeRabbit CHANGES_REQUESTED on the head with every thread resolved asks for a full re-review" {
  PS_REVIEWS="$FX/reviews-coderabbit-changes.ndjson"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"coderabbit status=NOT_APPROVED head=current — latest review on the head is CHANGES_REQUESTED"* ]]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
  [[ "$output" == *"--reviewers coderabbit --full"* ]]
}

@test "pr-state: WAIT while a requested review is in flight, with the acknowledgement flag" {
  PS_REVIEWS="$FX/reviews-none.ndjson"
  PS_COMMENTS="$FX/comments-requested.ndjson"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"REVIEWER: coderabbit status=REQUESTED ack=yes — mention posted 25m ago"* ]]
  [[ "$output" == *"REVIEWER: cubic status=REQUESTED ack=no"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" == *"NEXT: pr-state.sh --pr 7 --wait-seconds 540 — waiting for reviews from coderabbit,cubic"* ]]
}

@test "pr-state: WAIT while checks are still running" {
  PS_PR="$FX/pr-open-pending.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: pending failing=[] pending=[e2e testing]"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" == *"waiting for checks e2e testing"* ]]
}

@test "pr-state: a pending review request outranks a running check in the NEXT hint but a stale reviewer outranks both" {
  PS_PR="$FX/pr-open-pending.json"
  PS_REVIEWS="$FX/reviews-cubic-stale.ndjson"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
}

@test "pr-state: --required-checks with spaced names narrows the CI verdict and reports a missing required check as pending" {
  PS_PR="$FX/pr-open-red.json"
  ps_run --pr 7 --required-checks "static testing,visual tests"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=[visual tests]"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  ps_run --pr 7 --required-checks "static testing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: green"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
}

@test "pr-state: unreachable reviewers are SKIPPED with a reason, never counted as approvals, and NEXT names /rs-sdlc-review" {
  PS_COMMENTS="$FX/comments-skips.ndjson"
  PS_REVIEWS="$FX/reviews-none.ndjson"
  ps_run --pr 7 --reviewers coderabbit,qodo,qlty
  [ "$status" -eq 0 ]
  [[ "$output" == *"coderabbit status=SKIPPED — diff exceeds CodeRabbit's changed-file limit"* ]]
  [[ "$output" == *"qodo status=SKIPPED — reviews are paused"* ]]
  [[ "$output" == *"qlty status=SKIPPED — status-check bot"* ]]
  [[ "$output" == *"INFO: every requested reviewer is unreachable"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
  [[ "$output" == *"NEXT: exit condition met without an AI approval"*"/rs-sdlc-review"* ]]
}

@test "pr-state: a PR with no checks is never READY: the mandatory FR/NFR gate status is missing" {
  PS_PR="$FX/pr-open-nochecks.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: none"* ]]
  [[ "$output" == *"INFO: CI: the PR reports no checks and no required check is listed"*"SKIPPED-NO-CI"* ]]
  [[ "$output" == *"FR_NFR_GATE: missing"* ]]
  [[ "$output" == *"VERDICT: GATE"* ]]
}

@test "pr-state: GATE when CI is green and both bots approve but the FR/NFR gate never ran on the head" {
  PS_PR="$FX/pr-open-green-nogate.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: green"* ]]
  [[ "$output" == *"FR_NFR_GATE: missing"* ]]
  [[ "$output" == *"VERDICT: GATE"* ]]
  [[ "$output" == *"NEXT: rs-sdlc-fr-nfr-review --pr 7 --head $HEAD_SHA"* ]]
  [[ "$output" == *"mandatory for every PR"* ]]
}

@test "pr-state: GATE when the FR/NFR gate failed on the head; the gate status is never handed to ci-fixer" {
  PS_PR="$FX/pr-open-gate-failed.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: green failing=[]"* ]]
  [[ "$output" == *"FR_NFR_GATE: failure"* ]]
  [[ "$output" == *"VERDICT: GATE"* ]]
  [[ "$output" != *"ci-fixer"* ]]
}

@test "pr-state: --required-checks cannot waive the FR/NFR gate" {
  PS_PR="$FX/pr-open-green-nogate.json"
  ps_run --pr 7 --required-checks "unit testing"
  [[ "$output" == *"CI: green"* ]]
  [[ "$output" == *"VERDICT: GATE"* ]]
  ps_run --pr 7 --required-checks "unit testing,BMAD FR/NFR Review Gate"
  [[ "$output" == *"CI: green failing=[] pending=[] missing=[]"* ]]
  [[ "$output" == *"VERDICT: GATE"* ]]
}

@test "pr-state: WAIT while the FR/NFR gate status is posted as pending" {
  PS_PR="$FX/pr-open-gate-pending.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"FR_NFR_GATE: pending"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" == *"the BMAD FR/NFR Review Gate status"* ]]
}

@test "pr-state: --json carries the fr_nfr object" {
  PS_PR="$FX/pr-open-gate-failed.json"
  ps_run --separate-stderr --pr 7 --json
  [ "$status" -eq 0 ]
  ps_json 'assert d["fr_nfr"] == {"context": "BMAD FR/NFR Review Gate", "status": "failure"}
assert d["verdict"] == "GATE"
assert "BMAD FR/NFR Review Gate" not in d["ci"]["checks"]'
}

@test "pr-state: BLOCKED for a merged or conflicting PR" {
  PS_PR="$FX/pr-merged.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: BLOCKED"* ]]
  [[ "$output" == *"PR is MERGED"* ]]
  PS_PR="$FX/pr-conflicting.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: BLOCKED"* ]]
  [[ "$output" == *"CONFLICTING"* ]]
}

@test "pr-state: --json emits the canonical shape" {
  PS_PR="$FX/pr-open-red.json"
  ps_run --separate-stderr --pr 7 --json
  [ "$status" -eq 0 ]
  ps_json 'assert d["pr"] == 7 and d["verdict"] == "FIX" and d["ci"]["status"] == "red"
assert d["ci"]["failing"] == ["unit testing"]
assert len(d["reviewers"]) == 2 and d["reviewers"][0]["name"] == "coderabbit"
assert d["unresolved"]["total"] == 0
assert isinstance(d["next"], str)
assert d["url"] == "https://github.com/acme/billing-service/pull/7"
assert d["repo"] == "acme/billing-service"'
}

@test "pr-state: wait mode re-reads until the verdict leaves WAIT" {
  PS_PR="$FX/pr-open-pending.json"
  PS_PR_2="$FX/pr-open-green.json"
  ps_run --pr 7 --wait-seconds 300 --interval-seconds 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: READY"* ]]
  [ "$(ps_calls)" -eq 2 ]
}

@test "pr-state: wait mode returns the WAIT snapshot once the budget is spent" {
  PS_PR="$FX/pr-open-pending.json"
  ps_run --pr 7 --wait-seconds 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [ "$(ps_calls)" -eq 1 ]
}

@test "pr-state: PR number defaults to the current branch's PR" {
  ps_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR: #7 acme/billing-service"* ]]
  grep -q '^gh pr view --json number --jq .number$' "$STUB_GH_LOG"
}

@test "pr-state: runs from an install-cache copy via CLAUDE_PLUGIN_ROOT (ADR-4)" {
  CACHE="$BATS_TEST_TMPDIR/cache/rust-backend-sdlc"
  mkdir -p "$CACHE"
  cp -R "$PLUGIN_ROOT/scripts" "$CACHE/"
  ps_routes
  CLAUDE_PLUGIN_ROOT="$CACHE" run "$CACHE/scripts/pr-state.sh" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: READY"* ]]
}

@test "pr-state: --wait-verdicts REQUEST keeps polling through a REQUEST verdict" {
  PS_REVIEWS="$FX/reviews-cubic-stale.ndjson"
  PS_PR_2="$FX/pr-open-green.json"
  ps_run --pr 7 --wait-seconds 2 --interval-seconds 1 --wait-verdicts WAIT,REQUEST
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
  [ "$(ps_calls)" -ge 2 ]
  ps_run --pr 7 --wait-verdicts SOON
  [ "$status" -eq 1 ]
  [[ "$output" == *"--wait-verdicts must list"* ]]
  ps_run --pr 7 --wait-seconds 5 --interval-seconds 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"--interval-seconds must be at least 1"* ]]
}

@test "pr-state: a mention posted after the commit but before the push does not count as a request for this head" {
  PS_REVIEWS="$FX/reviews-none.ndjson"
  PS_COMMENTS="$FX/comments-requested.ndjson"
  PS_PUSHED_AT="2026-09-01T10:40:00Z"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"coderabbit status=NONE"* ]]
  [[ "$output" == *"VERDICT: REQUEST"* ]]
}

@test "pr-state: --required-checks on a PR with an empty check rollup reports the checks as missing, never READY" {
  PS_PR="$FX/pr-open-nochecks.json"
  ps_run --pr 7 --required-checks "unit testing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=[unit testing]"* ]]
  [[ "$output" == *"VERDICT: GATE"* ]]
  [[ "$output" != *"VERDICT: READY"* ]]
  [[ "$output" != *"reports no checks"* ]]
}

@test "pr-state: a failed check-suites lookup is fatal instead of silently dating the head by its commit" {
  PS_SUITES_EXIT=1
  ps_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh api failed listing check suites"* ]]
  [[ "$output" != *"VERDICT:"* ]]
}

@test "pr-state: --required-checks naming only the FR/NFR gate narrows the CI scope to nothing, not to every check" {
  PS_PR="$FX/pr-open-red.json"
  ps_run --pr 7 --required-checks "BMAD FR/NFR Review Gate"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: green failing=[] pending=[] missing=[]"* ]]
  [[ "$output" == *"FR_NFR_GATE: success"* ]]
  [[ "$output" != *"VERDICT: FIX"* ]]
}

@test "pr-state: every PR fixture renders exactly one verdict and the 15 JSON keys" {
  local fixture expected
  while read -r fixture expected; do
    PS_PR="$FX/$fixture"
    ps_run --separate-stderr --pr 7 --json
    [ "$status" -eq 0 ]
    ps_json "assert sorted(d) == ['ci', 'draft', 'fr_nfr', 'head', 'human_gated', 'mergeable', 'next', 'notes',
    'pr', 'repo', 'reviewers', 'state', 'unresolved', 'url', 'verdict'], sorted(d)
assert d['verdict'] == '$expected', ('$fixture', d['verdict'])
assert d['next']"
    ps_run --separate-stderr --pr 7
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^VERDICT: ')" -eq 1 ]
    [[ "$output" == *"VERDICT: $expected"* ]]
  done <<'EOF'
pr-conflicting.json BLOCKED
pr-merged.json BLOCKED
pr-open-gate-failed.json GATE
pr-open-gate-pending.json WAIT
pr-open-green-nogate.json GATE
pr-open-green.json READY
pr-open-human-gated-red.json FIX
pr-open-nochecks.json GATE
pr-open-pending.json WAIT
pr-open-red.json FIX
pr-open-service-check-red.json FIX
EOF
}

@test "pr-state: the verdict follows the priority BLOCKED > FIX > GATE > REQUEST > WAIT > READY" {
  PS_PR="$FX/pr-conflicting.json"
  PS_THREADS="$GH_FIX/pr-comments.json"
  PS_REVIEWS="$FX/reviews-cubic-stale.ndjson"
  ps_run --pr 7
  [[ "$output" == *"UNRESOLVED: 1"*"VERDICT: BLOCKED"* ]]
  PS_PR="$FX/pr-open-gate-failed.json"
  ps_run --pr 7
  [[ "$output" == *"FR_NFR_GATE: failure"*"VERDICT: FIX"* ]]
  PS_THREADS="$FX/threads-empty.json"
  ps_run --pr 7
  [[ "$output" == *"cubic status=STALE"*"VERDICT: GATE"* ]]
  PS_PR="$FX/pr-open-gate-pending.json"
  ps_run --pr 7
  [[ "$output" == *"FR_NFR_GATE: pending"*"VERDICT: REQUEST"* ]]
  PS_REVIEWS="$FX/reviews-approved.ndjson"
  ps_run --pr 7
  [[ "$output" == *"VERDICT: WAIT"* ]]
  PS_PR="$FX/pr-open-green.json"
  ps_run --pr 7
  [[ "$output" == *"VERDICT: READY"* ]]
}

# --- human-gated checks (AC-21.3, D9) ----------------------------------------------

@test "pr-state: a failing human-gated check named with a space is BLOCKED naming approved-config-change, not FIX" {
  PS_PR="$FX/pr-open-human-gated-red.json"
  ps_run --pr 7 --human-gated-checks 'Protected configuration,OpenAPI breaking changes,GraphQL breaking changes'
  [ "$status" -eq 0 ]
  [[ "$output" == *"HUMAN_GATED: failing=[Protected configuration] labels=[approved-config-change]"* ]]
  [[ "$output" == *"VERDICT: BLOCKED"* ]]
  [[ "$output" == *"NEXT: apply the label approved-config-change — failing human-gated check(s): Protected configuration"* ]]
  [[ "$output" == *"never the plugin"* ]]
  [[ "$output" != *"VERDICT: FIX"* ]]
  [[ "$output" != *"NEXT: fix failing"* ]]
}

@test "pr-state: a job id or a differently cased name in the human-gated list matches no check run, so the failure is FIX" {
  PS_PR="$FX/pr-open-human-gated-red.json"
  ps_run --pr 7 --human-gated-checks 'validate-configuration'
  [ "$status" -eq 0 ]
  [[ "$output" == *"HUMAN_GATED: failing=[] labels=[]"* ]]
  [[ "$output" == *"VERDICT: FIX"* ]]
  [[ "$output" == *"NEXT: fix failing checks Protected configuration (ci-fixer)"* ]]
  ps_run --pr 7 --human-gated-checks 'protected configuration'
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: FIX"* ]]
  ps_run --pr 7 --required-checks 'Static Analysis'
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=[Static Analysis]"* ]]
}

@test "pr-state: a failing check of a service-added workflow listed in --required-checks is FIX, never READY" {
  PS_PR="$FX/pr-open-service-check-red.json"
  ps_run --pr 7 --required-checks 'Static analysis,Tests and coverage,Protected configuration,Invoice PDF rendering' \
    --human-gated-checks 'Protected configuration,OpenAPI breaking changes,GraphQL breaking changes'
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: red failing=[Invoice PDF rendering] pending=[] missing=[]"* ]]
  [[ "$output" == *"VERDICT: FIX"* ]]
  [[ "$output" == *"NEXT: fix failing checks Invoice PDF rendering (ci-fixer)"* ]]
  [[ "$output" != *"VERDICT: READY"* ]]
}

@test "pr-state: a failing human-gated check that no label maps falls back to the label named in docs/repository-settings.md" {
  PS_PR="$FX/pr-open-service-check-red.json"
  ps_run --pr 7 --human-gated-checks 'Invoice PDF rendering'
  [ "$status" -eq 0 ]
  [[ "$output" == *"HUMAN_GATED: failing=[Invoice PDF rendering] labels=[]"* ]]
  [[ "$output" == *"VERDICT: BLOCKED"* ]]
  [[ "$output" == *"NEXT: apply the approval label named in docs/repository-settings.md — failing human-gated check(s): Invoice PDF rendering"* ]]
}

@test "pr-state: the label comes from the Labels to create table of the service document too" {
  ps_service_doc
  PS_PR="$FX/pr-open-service-check-red.json"
  ps_run --separate-stderr --pr 7 --human-gated-checks 'Protected configuration,Invoice PDF rendering' --json
  [ "$status" -eq 0 ]
  ps_json 'assert d["verdict"] == "BLOCKED"
assert d["next"].startswith("apply the label approved-pdf-layout — failing human-gated check(s): Invoice PDF rendering")
assert d["human_gated"] == {"checks": ["Protected configuration", "Invoice PDF rendering"],
    "failing": ["Invoice PDF rendering"],
    "labels": {"Protected configuration": "approved-config-change", "Invoice PDF rendering": "approved-pdf-layout"}}'
}

# --- profile defaults (D8) ---------------------------------------------------------

@test "pr-state: without list flags the defaults come from review.reviewers, ci.required_checks and ci.human_gated" {
  ps_golden_profile
  PS_PR="$FX/pr-open-human-gated-red.json"
  ps_run --separate-stderr --pr 7 --json
  [ "$status" -eq 0 ]
  ps_json 'assert [r["name"] for r in d["reviewers"]] == ["coderabbit"]
assert d["reviewers"][0]["status"] == "APPROVED"
assert d["human_gated"]["checks"] == ["Protected configuration", "OpenAPI breaking changes", "GraphQL breaking changes"]
assert d["human_gated"]["labels"] == {"Protected configuration": "approved-config-change",
    "OpenAPI breaking changes": "approved-breaking-change", "GraphQL breaking changes": "approved-breaking-change"}
assert d["human_gated"]["failing"] == ["Protected configuration"]
assert "Changes (Quality)" in d["ci"]["missing"] and "Architecture model" in d["ci"]["missing"]
assert d["verdict"] == "BLOCKED" and "approved-config-change" in d["next"]'
}

@test "pr-state: profile-listed required checks count as missing even when not passed, so a green PR still WAITs for them" {
  ps_golden_profile
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=[Architecture boundaries,Architecture model,"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" == *"NEXT: pr-state.sh --pr 7 --wait-seconds 540 — waiting for checks Architecture boundaries,"* ]]
}

@test "pr-state: zero reported checks with a non-empty ci.required_checks is WAIT, never CI none or SKIPPED-NO-CI" {
  ps_golden_profile
  PS_PR="$(ps_gate_only_payload)"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=["*"Changes (Quality)"* ]]
  [[ "$output" == *"FR_NFR_GATE: success"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" != *"CI: none"* ]]
  [[ "$output" != *"SKIPPED-NO-CI"* ]]
}

@test "pr-state: a profile that omits ci.provider or ci.required_checks is refused with exit 1 before any gh call, never read as D8" {
  local key
  for key in ci.provider ci.required_checks ci.human_gated review.reviewers; do
    ps_golden_profile
    drop_profile_key "$PROFILE" "$key"
    PS_PR="$(ps_gate_only_payload)"
    : >"$STUB_GH_LOG"
    ps_run --pr 7
    [ "$status" -eq 1 ]
    [[ "$output" == *"required key '$key' missing"* ]]
    [[ "$output" != *"VERDICT:"* ]]
    [[ "$output" != *"SKIPPED-NO-CI"* ]]
    [ "$(ps_calls)" -eq 0 ]
  done
}

@test "pr-state: ci.provider null is CI none when the PR reports no checks, and required checks are never awaited" {
  ps_golden_profile
  mutate_profile "$PROFILE" ci.provider null
  PS_PR="$(ps_gate_only_payload)"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: none failing=[] pending=[] missing=[]"* ]]
  [[ "$output" == *"INFO: CI: the PR reports no checks and ci.provider is null"*"SKIPPED-NO-CI"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
  PS_PR="$FX/pr-open-red.json"
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: red failing=[unit testing] pending=[e2e testing] missing=[]"* ]]
  [[ "$output" == *"INFO: CI: ci.provider is null — required checks are not awaited"* ]]
  [[ "$output" == *"VERDICT: FIX"* ]]
}

@test "pr-state: empty --reviewers and --human-gated-checks override the profile; an empty --required-checks keeps ci.required_checks" {
  ps_golden_profile
  PS_PR="$FX/pr-open-human-gated-red.json"
  ps_run --pr 7 --reviewers '' --required-checks '' --human-gated-checks ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: red failing=[Protected configuration] pending=[] missing=[Architecture boundaries,Architecture model,"* ]]
  ci_line="$(grep '^CI:' <<<"$output")"
  [[ "$ci_line" != *"Static analysis"* ]]
  [[ "$ci_line" != *"Protected configuration,"* ]]
  [[ "$output" == *"HUMAN_GATED: failing=[] labels=[]"* ]]
  [[ "$output" != *"REVIEWER:"* ]]
  [[ "$output" == *"INFO: no AI reviewer is configured"* ]]
  [[ "$output" == *"VERDICT: FIX"* ]]
}

@test "pr-state: an empty --required-checks never fakes no CI: zero reported checks with a non-empty ci.required_checks is WAIT (D8)" {
  ps_golden_profile
  PS_PR="$(ps_gate_only_payload)"
  ps_run --pr 7 --required-checks ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=[Architecture boundaries,"*"Changes (Quality)"* ]]
  [[ "$output" == *"FR_NFR_GATE: success"* ]]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [[ "$output" == *"NEXT: pr-state.sh --pr 7 --wait-seconds 540 — waiting for checks Architecture boundaries,"* ]]
  [[ "$output" != *"CI: none"* ]]
  [[ "$output" != *"SKIPPED-NO-CI"* ]]
  [[ "$output" != *"no required check is listed"* ]]
  ps_run --pr 7 --required-checks ',' --json
  [ "$status" -eq 0 ]
  ps_json 'assert d["ci"]["status"] == "pending" and len(d["ci"]["missing"]) == 36, d["ci"]
assert d["verdict"] == "WAIT" and not any("SKIPPED-NO-CI" in n for n in d["notes"])'
  # Both lists empty (finish-pr passing an empty profile list): D8 applies.
  ps_parity_profile
  ps_run --pr 7 --required-checks ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: none failing=[] pending=[] missing=[]"* ]]
  [[ "$output" == *"INFO: CI: the PR reports no checks and no required check is listed"*"(D8: SKIPPED-NO-CI)"* ]]
}

@test "pr-state: check names from the profile are printed without control characters" {
  mutate_profile "$PROFILE" ci.required_checks $'\n    - "Evil\\e[31mcheck"'
  ps_run --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI: pending failing=[] pending=[] missing=[Evil[31mcheck]"* ]]
  [[ "$output" == *"NEXT: pr-state.sh --pr 7 --wait-seconds 540 — waiting for checks Evil[31mcheck"* ]]
  [[ "$output" != *$'\e'* ]]
  ps_run --pr 7 --json --human-gated-checks $'Gate\e[0m'
  [ "$status" -eq 0 ]
  ps_json 'assert d["ci"]["missing"] == ["Evil[31mcheck"], d["ci"]
assert d["human_gated"]["checks"] == ["Gate[0m"], d["human_gated"]'
}

@test "pr-state: without a profile every list not given as a flag defaults to empty, with a warning" {
  rm "$PROFILE"
  ps_run --separate-stderr --pr 7
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[rust-sdlc][WARN] no profile at $REPO/.claude/rust-sdlc.yml"* ]]
  [[ "$output" != *"REVIEWER:"* ]]
  [[ "$output" == *"CI: green"* ]]
  [[ "$output" == *"VERDICT: READY"* ]]
}

@test "pr-state: an invalid review.reviewers in the profile is refused with exit 1 before any gh call" {
  mutate_profile "$PROFILE" review.reviewers $'\n    - copilot'
  ps_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown reviewer 'copilot' in review.reviewers of $PROFILE"* ]]
  [ "$(ps_calls)" -eq 0 ]
}

# --- output shape ------------------------------------------------------------------

@test "pr-state: --json prints exactly the 15 sorted keys" {
  ps_run --separate-stderr --pr 7 --json
  [ "$status" -eq 0 ]
  ps_json 'keys = ["ci", "draft", "fr_nfr", "head", "human_gated", "mergeable", "next", "notes", "pr",
        "repo", "reviewers", "state", "unresolved", "url", "verdict"]
assert list(d) == keys, list(d)
assert d["head"] == "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
assert d["state"] == "OPEN" and d["draft"] is False and d["mergeable"] == "MERGEABLE"
assert sorted(d["ci"]) == ["checks", "failing", "missing", "pending", "status"]
assert sorted(d["human_gated"]) == ["checks", "failing", "labels"]
assert d["verdict"] == "READY"'
  [[ "${lines[0]}" == "{" ]]
  [[ "${lines[1]}" == '  "ci": {' ]]
}

@test "pr-state: text mode prints the KEY: value lines in order, then VERDICT and NEXT" {
  PS_COMMENTS="$FX/comments-skips.ndjson"
  PS_REVIEWS="$FX/reviews-none.ndjson"
  ps_run --separate-stderr --pr 7 --reviewers coderabbit,qodo
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | cut -d: -f1 | uniq | tr '\n' ' ')" = "PR HEAD CI FR_NFR_GATE UNRESOLVED REVIEWER HUMAN_GATED INFO VERDICT NEXT " ]
  [ "${lines[0]}" = "PR: #7 acme/billing-service state=OPEN draft=false mergeable=MERGEABLE url=https://github.com/acme/billing-service/pull/7" ]
  [ "${lines[1]}" = "HEAD: $HEAD_SHA" ]
  [ "$(printf '%s\n' "$output" | grep -c '^VERDICT: ')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^NEXT: ')" -eq 1 ]
  [[ "${lines[-1]}" == "NEXT: "* ]]
}

# --- wait mode -----------------------------------------------------------------------

@test "pr-state: wait mode is bounded by --wait-seconds under the fixed clock and never sleeps for real" {
  PS_PR="$FX/pr-open-pending.json"
  SECONDS=0
  ps_run --separate-stderr --pr 7 --wait-seconds 300 --interval-seconds 60
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 60 ]
  [[ "$output" == *"VERDICT: WAIT"* ]]
  [ "$(ps_calls)" -eq 6 ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'reading again in 60s (budget 300s)')" -eq 5 ]
  [ "$(printf '%s\n' "$output" | grep -c '^VERDICT: ')" -eq 1 ]
}

# --- failures ------------------------------------------------------------------------

@test "pr-state: a failed gh pr view exits 1 without a verdict" {
  PS_PR_EXIT=1
  ps_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] gh pr view failed for PR #7 in acme/billing-service"* ]]
  [[ "$output" != *"VERDICT:"* ]]
}

@test "pr-state: a failed thread read through get-pr-comments.sh exits 1 without a verdict" {
  PS_THREADS_EXIT=1
  ps_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"get-pr-comments.sh failed for PR #7"* ]]
  [[ "$output" != *"VERDICT:"* ]]
}

@test "pr-state: malformed gh output exits 1 with a diagnostic and no traceback" {
  printf 'not json\n' >"$BATS_TEST_TMPDIR/garbage"
  PS_PR="$BATS_TEST_TMPDIR/garbage"
  ps_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh pr view returned malformed JSON for PR #7"* ]]
  [[ "$output" != *Traceback* ]]
  PS_PR="$FX/pr-open-green.json"
  PS_REVIEWS="$BATS_TEST_TMPDIR/garbage"
  ps_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] malformed review list for PR #7 in acme/billing-service"* ]]
  [[ "$output" != *Traceback* ]]
  [[ "$output" != *"VERDICT:"* ]]
}

@test "pr-state: no pull request for the current branch exits 1" {
  PS_NUMBER_EXIT=1
  ps_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pull request found for the current branch: pass --pr N"* ]]
  [ "$(ps_calls)" -eq 0 ]
}

@test "pr-state: an invalid pull-request number from gh pr view exits 1 before any snapshot" {
  local number
  for number in abc 07 2147483648; do
    ps_routes
    printf '%s\n' "$number" >"$BATS_TEST_TMPDIR/pr-number"
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[rust-sdlc][ERROR] gh pr view returned an invalid pull-request number: '$number': pass --pr N"* ]]
    [[ "$output" != *"VERDICT:"* ]]
    [ "$(ps_calls)" -eq 0 ]
  done
}

@test "pr-state: an unresolvable repository exits 1" {
  git -C "$REPO" remote remove origin
  ps_run --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve the repository"* ]]
  [ "$(ps_calls)" -eq 0 ]
}

@test "pr-state: an absent gh exits 1" {
  run env PATH="$(sandbox_path bash dirname git python3)" "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh CLI not found on PATH"* ]]
}

@test "pr-state: an absent python3 exits 1 before any gh call" {
  ps_routes
  run env PATH="$(sandbox_path bash dirname git gh)" "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"[rust-sdlc][ERROR] python3 is required to evaluate the pull-request state"* ]]
  [[ "$output" != *"VERDICT:"* ]]
  [ ! -s "$STUB_GH_LOG" ]
}
