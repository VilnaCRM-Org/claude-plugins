#!/usr/bin/env bats
# Tests for scripts/fr-nfr-gate.sh (Story 2.6, FR-18, feeds FR-6/FR-11).
#
# Stub-driven per the AC: the stub claude supplies the gate verdict via
# STUB_CLAUDE_OUTPUT, the stub gh records every invocation via
# STUB_GH_LOG so the tests assert the exact commit-status context name
# ('BMAD FR/NFR Review Gate') on BOTH the success and failure paths.
# The findings path needs gh pr view to return a number while other gh
# calls just log, which the static stub cannot route — that case uses a
# routing wrapper.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GATE="$PLUGIN_ROOT/scripts/fr-nfr-gate.sh"
  STUBS="$BATS_TEST_DIRNAME/fixtures/bin"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK/specs"
  echo "FR-1: sample requirement" > "$WORK/specs/prd.md"
  cd "$WORK"
  git init -q
  git remote add origin https://github.com/acme/sample-api.git
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  SHA="$(git rev-parse HEAD)"
  PATH="$STUBS:$PATH"
  GH_LOG="$BATS_TEST_TMPDIR/gh-calls.log"
  CLAUDE_LOG="$BATS_TEST_TMPDIR/claude-calls.log"
  export STUB_GH_LOG="$GH_LOG" STUB_CLAUDE_LOG="$CLAUDE_LOG"
}

# routed gh: pr view -> PR number; everything else logs and succeeds
route_gh() {
  local dir="$BATS_TEST_TMPDIR/route-bin"
  mkdir -p "$dir"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$GH_LOG"
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  echo 7
fi
EOF
  chmod +x "$dir/gh"
  PATH="$dir:$PATH"
}

ZERO_JSON='{"result":"All requirements covered.\nFR_NFR_NEW_FINDINGS: 0"}'
FINDINGS_JSON='{"result":"- FR-3 issue creation not covered by the change set\n- NFR-6 missing iteration guard\nFR_NFR_NEW_FINDINGS: 2"}'

@test "zero findings: exit 0, success status with exact context name, no PR comment" {
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS — zero new findings"* ]]
  grep -q "api repos/acme/sample-api/statuses/$SHA" "$GH_LOG"
  grep -q -- '-f state=success' "$GH_LOG"
  grep -qF -- '-f context=BMAD FR/NFR Review Gate' "$GH_LOG"
  ! grep -q 'pr comment' "$GH_LOG"
}

@test "findings run: exit 1, failure status, comment body contains the findings" {
  route_gh
  STUB_CLAUDE_OUTPUT="$FINDINGS_JSON" run "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL — 2 new finding(s)"* ]]
  grep -q -- '-f state=failure' "$GH_LOG"
  grep -qF -- '-f context=BMAD FR/NFR Review Gate' "$GH_LOG"
  grep -q 'pr comment 7 --body' "$GH_LOG"
  grep -q 'FR-3 issue creation not covered' "$GH_LOG"
  grep -q 'NFR-6 missing iteration guard' "$GH_LOG"
}

@test "claude invoked with the full ADR-8 flag set (ADR-6 acceptEdits default)" {
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE"
  [ "$status" -eq 0 ]
  grep -q -- '--output-format json' "$CLAUDE_LOG"
  grep -q -- '--permission-mode acceptEdits' "$CLAUDE_LOG"
  grep -q -- '--max-turns 30' "$CLAUDE_LOG"
}

@test "--spec-path and --impact-context reach the claude prompt" {
  mkdir -p custom-specs
  echo spec > custom-specs/prd.md
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE" \
    --spec-path custom-specs --impact-context "touches auth flow"
  [ "$status" -eq 0 ]
  grep -q 'custom-specs' "$CLAUDE_LOG"
  grep -q 'touches auth flow' "$CLAUDE_LOG"
  grep -q -- '--output-format json' "$CLAUDE_LOG"
}

@test "no origin remote: slug falls back to gh repo view" {
  git remote remove origin
  # the stub prints STUB_GH_OUTPUT for every non-version call; for
  # `repo view --jq .nameWithOwner` that is the slug itself
  STUB_GH_OUTPUT="acme/fallback-api" STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE"
  [ "$status" -eq 0 ]
  grep -q 'repo view --json nameWithOwner' "$GH_LOG"
  grep -q "api repos/acme/fallback-api/statuses/$SHA" "$GH_LOG"
}

@test "no origin remote and empty gh fallback: dies before running claude" {
  git remote remove origin
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve repository"* ]]
  [ ! -f "$CLAUDE_LOG" ]
}

@test "missing spec path: dies with remediation before any gh call" {
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE" --spec-path /nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"spec path not found"* ]]
  [ ! -f "$GH_LOG" ]
}

@test "spec path outside the repo boundary: dies before any gh or claude call" {
  # An existing path that resolves outside the repo work tree must be
  # rejected — the gate must not route out-of-tree requirement context.
  outside="$BATS_TEST_TMPDIR/outside-spec"
  mkdir -p "$outside"
  echo spec > "$outside/prd.md"
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE" --spec-path "$outside"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escapes the repository boundary"* ]]
  [ ! -f "$GH_LOG" ]
  [ ! -f "$CLAUDE_LOG" ]
}

@test "spec path that is a symlink to an outside dir: refused before any gh or claude call" {
  # A symlink at the FINAL path component survives dirname-only
  # canonicalization, so the gate must refuse symlinked --spec-path
  # outright (mirrors inject-governance.sh's symlink policy).
  outside="$BATS_TEST_TMPDIR/outside-spec-link-target"
  mkdir -p "$outside"
  echo spec > "$outside/prd.md"
  ln -s "$outside" "$WORK/specs-link"
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE" --spec-path "$WORK/specs-link"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to follow symlink"* ]]
  [ ! -f "$GH_LOG" ]
  [ ! -f "$CLAUDE_LOG" ]
}

@test "spec path symlink with trailing slash: still confined by containment" {
  # With a trailing slash the -L test dereferences, but pwd -P then
  # resolves the link target, so containment must still reject it.
  outside="$BATS_TEST_TMPDIR/outside-spec-slash-target"
  mkdir -p "$outside"
  echo spec > "$outside/prd.md"
  ln -s "$outside" "$WORK/specs-link-slash"
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" run "$GATE" --spec-path "$WORK/specs-link-slash/"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escapes the repository boundary"* || "$output" == *"refusing to follow symlink"* ]]
  [ ! -f "$GH_LOG" ]
  [ ! -f "$CLAUDE_LOG" ]
}

@test "malformed gate output: exit 1, failure status names the contract" {
  STUB_CLAUDE_OUTPUT='{"result":"prose without the mandatory line"}' run "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract violation"* ]]
  [[ "$output" == *"FR_NFR_NEW_FINDINGS"* ]]
  grep -q -- '-f state=failure' "$GH_LOG"
  grep -q 'gate output malformed' "$GH_LOG"
}

@test "claude transport failure: one retry, then failure status and exit 1" {
  STUB_CLAUDE_OUTPUT="$ZERO_JSON" STUB_CLAUDE_EXIT=2 run "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"retrying once"* ]]
  [[ "$output" == *"transport failure after"* ]]
  [ "$(grep -c '^claude ' "$CLAUDE_LOG")" -eq 2 ]
  grep -q -- '-f state=failure' "$GH_LOG"
}

@test "is_error=true with exit 0: one retry, transport-failure status, not the malformed-output status" {
  # claude exits 0 but reports is_error=true with .result holding an API
  # error string. The truthful classification is the transport-failure path
  # (one retry, then 'transport failure' status) — NOT the misleading
  # 'gate output malformed' commit status that the FR_NFR regex would
  # otherwise trigger on the error text.
  STUB_CLAUDE_OUTPUT='{"is_error":true,"result":"API Error: 529 Overloaded"}' run "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is_error"* ]]
  [[ "$output" == *"retrying once"* ]]
  [[ "$output" == *"transport failure after"* ]]
  [ "$(grep -c '^claude ' "$CLAUDE_LOG")" -eq 2 ]
  grep -q -- '-f state=failure' "$GH_LOG"
  grep -q 'claude transport failure after retry' "$GH_LOG"
  # the error text must NOT be reported as a malformed-contract violation
  ! grep -q 'gate output malformed' "$GH_LOG"
}

@test "unknown flag: usage error" {
  run "$GATE" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}
