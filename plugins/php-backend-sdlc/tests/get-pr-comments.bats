#!/usr/bin/env bats
# Tests for scripts/get-pr-comments.sh (Story 2.5, FR-8 feed, ADR-4).
#
# The stub gh returns the fixture GraphQL payload for any invocation,
# so single-gh-call paths (--pr given, owner/name from the origin
# remote) are fully stub-driven. The default-PR path needs two
# DIFFERENT gh responses (pr view, then api graphql), which the static
# stub cannot produce — that case generates a subcommand-routing gh
# wrapper. The install-cache test copies the plugin tree elsewhere and
# runs it via CLAUDE_PLUGIN_ROOT per ADR-4.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/get-pr-comments.sh"
  STUBS="$BATS_TEST_DIRNAME/fixtures/bin"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/gh/pr-comments.json"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
  cd "$WORK"
  git init -q
  git remote add origin https://github.com/acme/sample-api.git
  PATH="$STUBS:$PATH"
  export STUB_GH_OUTPUT
  STUB_GH_OUTPUT="$(cat "$FIXTURE")"
}

@test "full listing: both threads, issue comment, summary line" {
  run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR #7"* ]]
  [[ "$output" == *"[unresolved] src/Catalog/Handler.php:42"* ]]
  [[ "$output" == *"[resolved] src/Order/Service.php:17"* ]]
  [[ "$output" == *"(coderabbitai) Consider validating the input length here."* ]]
  [[ "$output" == *"(maintainer) Good catch, will fix."* ]]
  [[ "$output" == *"(ci-bot) Overall summary"* ]]
  [[ "$output" == *"unresolved threads: 1"* ]]
}

@test "--unresolved-only: resolved thread and issue comments dropped" {
  run "$SCRIPT" --pr 7 --unresolved-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"[unresolved] src/Catalog/Handler.php:42"* ]]
  [[ "$output" != *"Rename this method"* ]]
  [[ "$output" != *resolved\]\ src/Order* ]]
  [[ "$output" != *"ci-bot"* ]]
  [[ "$output" == *"unresolved threads: 1"* ]]
}

@test "--json: canonical machine-readable shape" {
  run "$SCRIPT" --pr 7 --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["pr"] == 7, d["pr"]
assert len(d["review_threads"]) == 2
assert d["review_threads"][0]["is_resolved"] is False
assert d["review_threads"][1]["is_resolved"] is True
c = d["review_threads"][0]["comments"][0]
assert c["author"] == "coderabbitai"
assert c["path"] == "src/Catalog/Handler.php"
assert c["line"] == 42
assert c["url"].endswith("discussion_r100")
assert len(d["issue_comments"]) == 1
assert d["issue_comments"][0]["author"] == "ci-bot"
print("json shape OK")'
}

@test "--json --unresolved-only: filtered threads, empty issue_comments" {
  run "$SCRIPT" --pr 7 --json --unresolved-only
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert len(d["review_threads"]) == 1
assert d["review_threads"][0]["is_resolved"] is False
assert d["issue_comments"] == []
print("filtered json OK")'
}

@test "python fallback path produces identical canonical JSON" {
  # sandbox PATH without jq: route everything through the python branch
  dir="$BATS_TEST_TMPDIR/nojq-bin"
  mkdir -p "$dir"
  for tool in bash git grep sed sort head dirname python3 cat mktemp; do
    src="$(command -v "$tool")" && ln -sf "$src" "$dir/$tool"
  done
  ln -sf "$STUBS/gh" "$dir/gh"
  jq_out="$("$SCRIPT" --pr 7 --json)"
  PATH="$dir" run "$SCRIPT" --pr 7 --json
  [ "$status" -eq 0 ]
  py_out="$output"
  python3 -c '
import json, sys
a = json.loads(sys.argv[1]); b = json.loads(sys.argv[2])
assert a == b, "backends disagree"
print("backends agree")' "$jq_out" "$py_out"
}

@test "python human-render path (no jq, no --json) matches jq listing" {
  # sandbox PATH without jq AND without --json: exercises the python
  # human-render branch (the jq branch and the --json early-return both
  # bypass it), which the json-only fallback test never reaches.
  dir="$BATS_TEST_TMPDIR/nojq-human-bin"
  mkdir -p "$dir"
  for tool in bash git grep sed sort head dirname python3 cat mktemp; do
    src="$(command -v "$tool")" && ln -sf "$src" "$dir/$tool"
  done
  ln -sf "$STUBS/gh" "$dir/gh"
  PATH="$dir" run "$SCRIPT" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR #7"* ]]
  [[ "$output" == *"[unresolved] src/Catalog/Handler.php:42"* ]]
  [[ "$output" == *"[resolved] src/Order/Service.php:17"* ]]
  [[ "$output" == *"(coderabbitai) Consider validating the input length here."* ]]
  [[ "$output" == *"(maintainer) Good catch, will fix."* ]]
  [[ "$output" == *"(ci-bot) Overall summary"* ]]
  [[ "$output" == *"unresolved threads: 1"* ]]
}

@test "default PR resolved via gh pr view when --pr omitted" {
  dir="$BATS_TEST_TMPDIR/route-bin"
  mkdir -p "$dir"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  echo 7
else
  cat "$FIXTURE"
fi
EOF
  chmod +x "$dir/gh"
  PATH="$dir:$PATH" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR #7"* ]]
  [[ "$output" == *"unresolved threads: 1"* ]]
}

@test "runs from a simulated install cache via CLAUDE_PLUGIN_ROOT (ADR-4)" {
  CACHE="$BATS_TEST_TMPDIR/install-cache/php-backend-sdlc"
  mkdir -p "$(dirname "$CACHE")"
  cp -r "$PLUGIN_ROOT" "$CACHE"
  CLAUDE_PLUGIN_ROOT="$CACHE" run "$CACHE/scripts/get-pr-comments.sh" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"unresolved threads: 1"* ]]
}

@test "more than one page of review threads: dies clearly, never reports a truncated count" {
  # hasNextPage=true means the single 100-item page is incomplete; the
  # script must refuse rather than compute 'unresolved threads: N' on a
  # truncated set (which could read 0 while unresolved threads remain).
  STUB_GH_OUTPUT="$(cat "$BATS_TEST_DIRNAME/fixtures/gh/pr-comments-truncated.json")" \
    run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"more than 100 review threads"* ]]
  [[ "$output" == *"pagination is not supported"* ]]
  [[ "$output" != *"unresolved threads:"* ]]
}

@test "pagination guard fires in --json mode too" {
  STUB_GH_OUTPUT="$(cat "$BATS_TEST_DIRNAME/fixtures/gh/pr-comments-truncated.json")" \
    run "$SCRIPT" --pr 7 --json
  [ "$status" -eq 1 ]
  [[ "$output" == *"pagination is not supported"* ]]
}

@test "pagination guard fires on the python fallback path (no jq)" {
  dir="$BATS_TEST_TMPDIR/nojq-page-bin"
  mkdir -p "$dir"
  for tool in bash git grep sed sort head dirname python3 cat mktemp; do
    src="$(command -v "$tool")" && ln -sf "$src" "$dir/$tool"
  done
  # route gh to the truncated fixture
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
cat "$BATS_TEST_DIRNAME/fixtures/gh/pr-comments-truncated.json"
EOF
  chmod +x "$dir/gh"
  PATH="$dir" run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"pagination is not supported"* ]]
}

@test "gh exit 0 with non-JSON output: clean die naming the PR, no raw jq error (GPC-N3)" {
  # gh can exit 0 yet print an HTML proxy error page; the script must
  # diagnose it itself instead of surfacing a jq parse error (exit 5).
  STUB_GH_OUTPUT='this is not json <html>502</html>' run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"[php-sdlc][ERROR]"* ]]
  [[ "$output" == *"non-JSON"* ]]
  [[ "$output" == *"PR #7"* ]]
  [[ "$output" != *"jq: parse error"* ]]
}

@test "non-JSON gh output dies cleanly on the python fallback path too (no jq)" {
  dir="$BATS_TEST_TMPDIR/nojq-nonjson-bin"
  mkdir -p "$dir"
  for tool in bash git grep sed sort head dirname python3 cat mktemp; do
    src="$(command -v "$tool")" && ln -sf "$src" "$dir/$tool"
  done
  ln -sf "$STUBS/gh" "$dir/gh"
  STUB_GH_OUTPUT='this is not json <html>502</html>' PATH="$dir" run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-JSON"* ]]
  [[ "$output" != *Traceback* ]]
  [[ "$output" != *JSONDecodeError* ]]
}

@test "UTF-8 BOM before a valid payload: both backends tolerate it identically (R2-GPC-16)" {
  # jq 1.7+ silently strips a leading BOM while python's json.load rejects
  # it, so a BOM-prefixed-but-valid response would make the jq path render
  # data (exit 0) while the python path dies 'non-JSON output' (exit 1).
  # The script strips the BOM once up front so both backends agree.
  local bom; bom=$'\xef\xbb\xbf'

  # jq backend: BOM-prefixed valid payload renders normally, exit 0
  STUB_GH_OUTPUT="${bom}$(cat "$FIXTURE")" run "$SCRIPT" --pr 7 --json
  [ "$status" -eq 0 ]
  jq_out="$output"
  echo "$jq_out" | python3 -c 'import json,sys; json.load(sys.stdin)'

  # python backend (no jq on PATH): same BOM payload must also succeed
  dir="$BATS_TEST_TMPDIR/nojq-bom-bin"
  mkdir -p "$dir"
  for tool in bash git grep sed sort head dirname python3 cat mktemp; do
    src="$(command -v "$tool")" && ln -sf "$src" "$dir/$tool"
  done
  ln -sf "$STUBS/gh" "$dir/gh"
  STUB_GH_OUTPUT="${bom}$(cat "$FIXTURE")" PATH="$dir" run "$SCRIPT" --pr 7 --json
  [ "$status" -eq 0 ]
  py_out="$output"

  # backends must agree byte-for-byte on the canonical JSON
  python3 -c '
import json, sys
a = json.loads(sys.argv[1]); b = json.loads(sys.argv[2])
assert a == b, "backends disagree on BOM-prefixed payload"
print("backends agree")' "$jq_out" "$py_out"
}

@test "non-numeric --pr: usage error" {
  run "$SCRIPT" --pr seven
  [ "$status" -eq 1 ]
  [[ "$output" == *"--pr must be a number"* ]]
}

@test "unknown flag: usage error" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}

# --- R2 regression: no-PR payloads, gh-resolved PR validation --------------

@test "R2 Bug 7: wrong-shape JSON does not render '0 unresolved' (dies, exit 1)" {
  STUB_GH_OUTPUT='{"ok":true}' run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pull-request data"* ]]
  [[ "$output" != *"unresolved threads: 0"* ]]
}

@test "R2 Bug 7: an explicit null pullRequest dies, never '0 unresolved'" {
  STUB_GH_OUTPUT='{"data":{"repository":{"pullRequest":null}}}' run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pull-request data"* ]]
  [[ "$output" != *"unresolved threads: 0"* ]]
}

@test "R2 Bug 7: a GraphQL error envelope surfaces the error message (exit 1)" {
  STUB_GH_OUTPUT='{"data":null,"errors":[{"message":"Could not resolve to a PullRequest with the number of 7."}]}' \
    run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not resolve to a PullRequest"* ]]
  [[ "$output" != *"unresolved threads: 0"* ]]
}

@test "R2 Bug 7: an empty gh body dies cleanly (jq backend no longer diverges)" {
  STUB_GH_OUTPUT='' run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty response"* ]]
}

@test "R2 Bug 7: python backend handles the no-PR cases identically" {
  dir="$BATS_TEST_TMPDIR/nojq-nopr-bin"
  mkdir -p "$dir"
  for tool in bash git grep sed sort head dirname python3 cat mktemp; do
    src="$(command -v "$tool")" && ln -sf "$src" "$dir/$tool"
  done
  ln -sf "$STUBS/gh" "$dir/gh"
  STUB_GH_OUTPUT='{"data":{"repository":{"pullRequest":null}}}' PATH="$dir" run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pull-request data"* ]]
  STUB_GH_OUTPUT='{"data":null,"errors":[{"message":"boom"}]}' PATH="$dir" run "$SCRIPT" --pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"boom"* ]]
}

@test "R2 Bug 9: a non-numeric gh-resolved PR dies cleanly, not a raw jq error" {
  # gh pr view returns a non-numeric value; it must be validated like --pr
  # rather than reaching jq --argjson and surfacing 'invalid JSON text'.
  dir="$BATS_TEST_TMPDIR/route-badpr-bin"
  mkdir -p "$dir"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  echo "not-a-number"
else
  echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]},"comments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}'
fi
EOF
  chmod +x "$dir/gh"
  PATH="$dir:$PATH" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"resolved PR number is not numeric"* ]]
  [[ "$output" != *"invalid JSON text"* ]]
}
