#!/usr/bin/env bats
# inject-governance.bats — cases of scripts/inject-governance.sh (FR-8,
# AC-8.1 to AC-8.3, ADR-3).
#
# Every case runs against the fixture repository materialized at
# $BATS_TEST_TMPDIR/billing-service. Repair cases compare the result byte for
# byte with an expected file built from literal parts and the exact block, so
# kept bytes, line endings and the single blank separator are all asserted.
# The template's own repository name is assembled from two halves, never
# written out (invariant (e), CC-28).
#
# shellcheck disable=SC2016 # single-quoted python and grep patterns are literal on purpose

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  SCRIPT="$PLUGIN_ROOT/scripts/inject-governance.sh"
  REPO="$BATS_TEST_TMPDIR/billing-service"
  BEGIN='<!-- rust-backend-sdlc:begin -->'
  END='<!-- rust-backend-sdlc:end -->'
  BLOCK="$BATS_TEST_TMPDIR/block.txt"
  ARCHITECTURE="$PLUGIN_ROOT/../../specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/architecture.md"
  ig_expected_block >"$BLOCK"
  rr_materialize "$REPO"
}

teardown() {
  # Permission cases leave unreadable or unwritable paths behind.
  chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# ig_expected_block — the exact text of the architecture's Governance Block
# (markers included, one trailing newline): the suite's golden copy.
ig_expected_block() {
  cat <<'BLOCK'
<!-- rust-backend-sdlc:begin -->

## rust-backend-sdlc governance (managed block — do not edit between markers)

The rust-backend-sdlc plugin writes this block and restores it when its setup command runs again. The values it refers to live in the project profile `.claude/rust-sdlc.yml`, which is committed together with this block.

- Skill triage: before implementation or review work, every plugin skill receives a recorded verdict, EXECUTE with evidence or NOT APPLICABLE with a reason. The rule is: every skill verdict recorded, no silent skips. A full skill body is loaded only on EXECUTE.
- Repository rules first: `AGENTS.md` and the skills listed in `.claude/skills/README.md` win over a plugin skill of the same name; the plugin skill adds only its loop, its evidence format and its escalation block.
- Tighten-only quality bars: the `quality.*` keys of the profile may only equal or tighten the values of the gates, and a file listed in `protected-config.toml` is never changed to make a check pass.
- Execution through make: every tool runs through the target that the `make.*` keys of the profile map; the order of the checks is the verification section of `AGENTS.md`.
- Commits and pull-request titles use the form type(#issue): subject, and the git hooks are never bypassed.
- Protected configuration is escalated to a maintainer with the approval label, never edited by an agent.
- Plugin commands, named here in prose: /rs-sdlc drives a feature from issue to finished pull request; /rs-sdlc-setup restores this block; /rs-sdlc-new-service, /rs-sdlc-new-context, /rs-sdlc-issue, /rs-sdlc-plan, /rs-sdlc-implement, /rs-sdlc-review, /rs-sdlc-qa and /rs-sdlc-finish-pr run one step each.

<!-- rust-backend-sdlc:end -->
BLOCK
}

# ig_sha FILE [BYTES] — sha256 of FILE, or of its first BYTES bytes.
ig_sha() {
  python3 -I -c '
import hashlib, sys
data = open(sys.argv[1], "rb").read()
if len(sys.argv) > 2:
    data = data[: int(sys.argv[2])]
print(hashlib.sha256(data).hexdigest())' "$@"
}

# ig_size FILE — size of FILE in bytes.
ig_size() {
  python3 -I -c 'import os, sys; print(os.path.getsize(sys.argv[1]))' "$1"
}

# ig_mode FILE — permission bits of FILE in octal, e.g. 644.
ig_mode() {
  python3 -I -c 'import os, sys; print("%o" % (os.stat(sys.argv[1]).st_mode & 0o777))' "$1"
}

# ig_build OUT PART... — OUT holds the PARTs in order: `@block` is the exact
# block, `@file:PATH` the bytes of PATH, any other PART is written with
# printf %b (so \n and \r expand).
ig_build() {
  local out="$1" part
  shift
  : >"$out"
  for part in "$@"; do
    case "$part" in
      @block) cat "$BLOCK" >>"$out" ;;
      @file:*) cat "${part#@file:}" >>"$out" ;;
      *) printf '%b' "$part" >>"$out" ;;
    esac
  done
}

# ig_refute CMD... — fail when CMD succeeds (bats ignores a negated command
# that is not the last line of a case).
ig_refute() {
  if "$@"; then
    printf 'unexpectedly succeeded: %s\n' "$*" >&2
    return 1
  fi
}

# ig_ends_with_block FILE — FILE ends with exactly one blank line followed by
# the exact block (or is the block alone).
ig_ends_with_block() {
  python3 -I -c '
import sys
data = open(sys.argv[1], "rb").read()
block = open(sys.argv[2], "rb").read()
if not data.endswith(block):
    sys.exit("the file does not end with the block")
head = data[: len(data) - len(block)]
if head == b"":
    sys.exit(0)
if not head.endswith(b"\n\n"):
    sys.exit("no blank line before the block")
last = head[:-2].split(b"\n")[-1]
if last.strip(b" \t\r") == b"":
    sys.exit("more than one blank line before the block")' "$1" "$BLOCK"
}

# ig_count FILE LINE — number of lines of FILE equal to LINE.
ig_count() {
  grep -cxF -- "$2" "$1" || true
}

# ig_line FILE LINE — number of the first line of FILE equal to LINE.
ig_line() {
  grep -nxF -- "$2" "$1" | head -n 1 | cut -d: -f1
}

# ig_block_of FILE — the lines from the first begin marker to the next end
# marker of FILE.
ig_block_of() {
  awk -v b="$BEGIN" -v e="$END" '$0 == b { f = 1 } f { print } f && $0 == e { exit }' "$1"
}

# ig_spans FILE — the inline code spans of FILE, one per line, backticks kept.
ig_spans() {
  grep -oE '`[^`]+`' "$1" || true
}

# ig_profile — the committed profile that the block cites (docs-check rule 3
# tests backticked paths on disk).
ig_profile() {
  printf 'schema_version: 1\n' >"$REPO/.claude/rust-sdlc.yml"
}

# ig_template_repository_name — the repository name of the fixture's
# `TEMPLATE_REPOSITORY: <owner>/<name>` line.
ig_template_repository_name() {
  awk -F'TEMPLATE_REPOSITORY:' 'NF > 1 { v = $2; gsub(/[ \t"\047]/, "", v); sub(/.*\//, "", v); print v; exit }' \
    "$REPO/.github/workflows/template-sync-app.yml"
}

# --- usage -----------------------------------------------------------------

@test "inject-governance: --help prints the header and exits 0" {
  run --separate-stderr "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "inject-governance.sh — keep one managed governance block in CLAUDE.md and AGENTS.md (FR-8)." ]
  [[ "$output" == *"Usage: inject-governance.sh [--diff] [TARGET_DIR]"* ]]
  [[ "$output" == *"Exit: 0 success; 1 "*"; 2 usage error"* ]]
  [[ "$output" != *"set -euo pipefail"* ]]
}

@test "inject-governance: --help in any position wins over other arguments and writes nothing" {
  before="$(ig_sha "$REPO/CLAUDE.md")"
  run --separate-stderr "$SCRIPT" --diff --bogus "$REPO" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: inject-governance.sh"* ]]
  [ "$(ig_sha "$REPO/CLAUDE.md")" = "$before" ]
  [ "$(ig_count "$REPO/CLAUDE.md" "$BEGIN")" -eq 0 ]
}

@test "inject-governance: an unknown flag exits 2 and writes nothing" {
  before="$(ig_sha "$REPO/AGENTS.md")"
  run --separate-stderr "$SCRIPT" --force "$REPO"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"[rust-sdlc][ERROR] unknown argument: --force"* ]]
  [[ "$stderr" == *"usage: inject-governance.sh [--diff] [TARGET_DIR]"* ]]
  [ "$(ig_sha "$REPO/AGENTS.md")" = "$before" ]
}

@test "inject-governance: a second TARGET_DIR exits 2" {
  run --separate-stderr "$SCRIPT" "$REPO" "$REPO"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"unexpected argument: $REPO"* ]]
  [ "$(ig_count "$REPO/CLAUDE.md" "$BEGIN")" -eq 0 ]
}

@test "inject-governance: a missing TARGET_DIR exits 1" {
  run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR/no-such-repo"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"target directory not found: $BATS_TEST_TMPDIR/no-such-repo"* ]]
}

# --- create, append, idempotence (AC-8.1) -----------------------------------------

@test "inject-governance: appends the exact block after one blank line and keeps the prior bytes" {
  claude_sha="$(ig_sha "$REPO/CLAUDE.md")"
  claude_size="$(ig_size "$REPO/CLAUDE.md")"
  agents_sha="$(ig_sha "$REPO/AGENTS.md")"
  agents_size="$(ig_size "$REPO/AGENTS.md")"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'UPDATED: CLAUDE.md\nUPDATED: AGENTS.md' ]
  [ -z "$stderr" ]
  ig_ends_with_block "$REPO/CLAUDE.md"
  ig_ends_with_block "$REPO/AGENTS.md"
  [ "$(ig_sha "$REPO/CLAUDE.md" "$claude_size")" = "$claude_sha" ]
  [ "$(ig_sha "$REPO/AGENTS.md" "$agents_size")" = "$agents_sha" ]
  [ "$(ig_size "$REPO/CLAUDE.md")" -eq $((claude_size + 1 + $(ig_size "$BLOCK"))) ]
  [ "$(ig_size "$REPO/AGENTS.md")" -eq $((agents_size + 1 + $(ig_size "$BLOCK"))) ]
}

@test "inject-governance: TARGET_DIR defaults to the working directory" {
  cd "$REPO"
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = $'UPDATED: CLAUDE.md\nUPDATED: AGENTS.md' ]
  ig_ends_with_block "$REPO/CLAUDE.md"
}

@test "inject-governance: a relative TARGET_DIR is resolved" {
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr "$SCRIPT" billing-service
  [ "$status" -eq 0 ]
  [ "$output" = $'UPDATED: CLAUDE.md\nUPDATED: AGENTS.md' ]
  ig_ends_with_block "$REPO/AGENTS.md"
}

@test "inject-governance: a missing file is created holding only the block" {
  rm "$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'CREATED: CLAUDE.md\nUPDATED: AGENTS.md' ]
  cmp "$REPO/CLAUDE.md" "$BLOCK"
}

@test "inject-governance: both files are created in a directory that has neither" {
  rm "$REPO/CLAUDE.md" "$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'CREATED: CLAUDE.md\nCREATED: AGENTS.md' ]
  cmp "$REPO/CLAUDE.md" "$BLOCK"
  cmp "$REPO/AGENTS.md" "$BLOCK"
}

@test "inject-governance: an empty file is updated to hold only the block" {
  : >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "UPDATED: CLAUDE.md" ]
  cmp "$REPO/CLAUDE.md" "$BLOCK"
}

@test "inject-governance: a second run is byte-identical and prints UNCHANGED for both files" {
  "$SCRIPT" "$REPO" >/dev/null
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m 'docs: inject the governance block'
  claude_sha="$(ig_sha "$REPO/CLAUDE.md")"
  agents_sha="$(ig_sha "$REPO/AGENTS.md")"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'UNCHANGED: CLAUDE.md\nUNCHANGED: AGENTS.md' ]
  [ "$(ig_sha "$REPO/CLAUDE.md")" = "$claude_sha" ]
  [ "$(ig_sha "$REPO/AGENTS.md")" = "$agents_sha" ]
  git -C "$REPO" diff --quiet
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "inject-governance: a file without a final newline gets one before the blank line" {
  printf '# Notes\n\nlast line' >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ig_build "$BATS_TEST_TMPDIR/expected" '# Notes\n\nlast line\n\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
}

@test "inject-governance: trailing blank lines collapse to exactly one before the block" {
  printf '# Notes\n\ntext\n\n\n  \n' >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ig_build "$BATS_TEST_TMPDIR/expected" '# Notes\n\ntext\n\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "${lines[0]}" = "UNCHANGED: CLAUDE.md" ]
}

# --- in-place replacement and repairs (AC-8.1) ------------------------------------

@test "inject-governance: a stale block is replaced in place and the text around it keeps its bytes" {
  printf '# Top\n\n%s\nold governance text\n%s\n\n## After\n' "$BEGIN" "$END" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "UPDATED: CLAUDE.md" ]
  ig_build "$BATS_TEST_TMPDIR/expected" '# Top\n\n' @block '\n## After\n'
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "${lines[0]}" = "UNCHANGED: CLAUDE.md" ]
}

@test "inject-governance: duplicate pairs collapse into the first position (REPAIRED)" {
  printf 'intro\n%s\nfirst stale copy\n%s\nmiddle\n%s\nsecond stale copy\n%s\noutro\n' \
    "$BEGIN" "$END" "$BEGIN" "$END" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REPAIRED: CLAUDE.md (2 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" 'intro\n' @block 'middle\noutro\n'
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
  [ "$(ig_count "$REPO/CLAUDE.md" "$BEGIN")" -eq 1 ]
  [ "$(ig_count "$REPO/CLAUDE.md" "$END")" -eq 1 ]
}

@test "inject-governance: three pairs keep the first position and report four removed lines" {
  printf '%s\na\n%s\nx\n%s\nb\n%s\ny\n%s\nc\n%s\nz\n' \
    "$BEGIN" "$END" "$BEGIN" "$END" "$BEGIN" "$END" >"$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "REPAIRED: AGENTS.md (4 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" @block 'x\ny\nz\n'
  cmp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/expected"
}

@test "inject-governance: an orphan begin is removed, the text after it kept and the block appended" {
  printf 'before\n%s\nuser text that must stay\nafter\n' "$BEGIN" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REPAIRED: CLAUDE.md (1 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" 'before\nuser text that must stay\nafter\n\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
}

@test "inject-governance: an orphan end is removed and the block appended" {
  printf 'before\n%s\nafter\n' "$END" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REPAIRED: CLAUDE.md (1 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" 'before\nafter\n\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
}

@test "inject-governance: an inverted pair is removed and one well-ordered block appended" {
  printf '%s\nuser line A\n%s\nuser line B\nuser line C\n' "$END" "$BEGIN" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REPAIRED: CLAUDE.md (2 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" 'user line A\nuser line B\nuser line C\n\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
  [ "$(ig_line "$REPO/CLAUDE.md" "$BEGIN")" -lt "$(ig_line "$REPO/CLAUDE.md" "$END")" ]
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "${lines[0]}" = "UNCHANGED: CLAUDE.md" ]
}

@test "inject-governance: an orphan begin before a valid pair is removed and the pair replaced in place" {
  printf 'a\n%s\nb\n%s\nstale\n%s\nc\n' "$BEGIN" "$BEGIN" "$END" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REPAIRED: CLAUDE.md (1 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" 'a\nb\n' @block 'c\n'
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
}

# --- fences ----------------------------------------------------------------------

@test "inject-governance: markers inside a backtick fence are content, not markers" {
  printf '# Docs\n\n```markdown\n%s\nexample governance text\n%s\n```\n' "$BEGIN" "$END" >"$REPO/CLAUDE.md"
  cp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/original"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "UPDATED: CLAUDE.md" ]
  ig_build "$BATS_TEST_TMPDIR/expected" "@file:$BATS_TEST_TMPDIR/original" '\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "${lines[0]}" = "UNCHANGED: CLAUDE.md" ]
}

@test "inject-governance: markers inside a tilde fence are content, not markers" {
  printf '# Docs\n\n~~~text\n%s\n%s\n~~~\n\ntail\n' "$END" "$BEGIN" >"$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "UPDATED: AGENTS.md" ]
  ig_build "$BATS_TEST_TMPDIR/expected" "# Docs\n\n~~~text\n$END\n$BEGIN\n~~~\n\ntail\n\n" @block
  cmp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/expected"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "${lines[1]}" = "UNCHANGED: AGENTS.md" ]
}

@test "inject-governance: a fenced marker example survives while the real stale block is replaced" {
  printf '```text\n%s\n```\n\n%s\nold\n%s\n\nafter\n' "$BEGIN" "$BEGIN" "$END" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "UPDATED: CLAUDE.md" ]
  ig_build "$BATS_TEST_TMPDIR/expected" "\`\`\`text\n$BEGIN\n\`\`\`\n\n" @block '\nafter\n'
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
}

@test "inject-governance: an unclosed fence falls back to whole-line markers and stays idempotent" {
  printf '# Project\n\n```\nunclosed code\n' >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ig_build "$BATS_TEST_TMPDIR/expected" '# Project\n\n```\nunclosed code\n\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "UNCHANGED: CLAUDE.md" ]
  [ "$(ig_count "$REPO/CLAUDE.md" "$BEGIN")" -eq 1 ]
}

# --- CRLF ------------------------------------------------------------------------

@test "inject-governance: a CRLF stale block is replaced in place and the other lines keep CRLF" {
  printf 'user\r\n%s\r\nOLD GOVERNANCE\r\n%s\r\nmore\r\n' "$BEGIN" "$END" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "UPDATED: CLAUDE.md" ]
  ig_build "$BATS_TEST_TMPDIR/expected" 'user\r\n' @block 'more\r\n'
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "${lines[0]}" = "UNCHANGED: CLAUDE.md" ]
}

@test "inject-governance: a CRLF file without markers keeps every byte before the block" {
  printf '# Notes\r\n\r\ntext\r\n' >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ig_build "$BATS_TEST_TMPDIR/expected" '# Notes\r\n\r\ntext\r\n\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "${lines[0]}" = "UNCHANGED: CLAUDE.md" ]
}

@test "inject-governance: a CRLF file without a final newline gets a CRLF terminator" {
  printf 'a\r\nlast' >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ig_build "$BATS_TEST_TMPDIR/expected" 'a\r\nlast\r\n\n' @block
  cmp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/expected"
}

@test "inject-governance: CRLF duplicate pairs repair to one block and keep CRLF elsewhere" {
  printf 'x\r\n%s\r\none\r\n%s\r\ny\r\n%s\r\ntwo\r\n%s\r\nz\r\n' "$BEGIN" "$END" "$BEGIN" "$END" >"$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "REPAIRED: AGENTS.md (2 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" 'x\r\n' @block 'y\r\nz\r\n'
  cmp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/expected"
}

# --- verification region ------------------------------------------------------------

@test "inject-governance: a pair inside the AGENTS.md verification region is removed and the block appended" {
  cp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/original"
  awk -v b="$BEGIN" -v e="$END" '{ print } $0 == "<!-- verification:start -->" { print b; print "stale governance"; print e }' \
    "$BATS_TEST_TMPDIR/original" >"$REPO/AGENTS.md"
  [ "$(ig_count "$REPO/AGENTS.md" "$BEGIN")" -eq 1 ]
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "REPAIRED: AGENTS.md (2 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" "@file:$BATS_TEST_TMPDIR/original" '\n' @block
  cmp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/expected"
  [ "$(ig_line "$REPO/AGENTS.md" "$BEGIN")" -gt "$(ig_line "$REPO/AGENTS.md" '<!-- verification:end -->')" ]
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "${lines[1]}" = "UNCHANGED: AGENTS.md" ]
}

@test "inject-governance: a pair around the verification region loses only its marker lines" {
  cp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/original"
  awk -v b="$BEGIN" -v e="$END" '
    $0 == "<!-- verification:start -->" { print b }
    { print }
    $0 == "<!-- verification:end -->" { print e }' "$BATS_TEST_TMPDIR/original" >"$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "REPAIRED: AGENTS.md (2 stray marker line(s) removed)" ]
  ig_build "$BATS_TEST_TMPDIR/expected" "@file:$BATS_TEST_TMPDIR/original" '\n' @block
  cmp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/expected"
}

@test "inject-governance: the injected block sits after the verification region of AGENTS.md" {
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  start="$(ig_line "$REPO/AGENTS.md" '<!-- verification:start -->')"
  stop="$(ig_line "$REPO/AGENTS.md" '<!-- verification:end -->')"
  begin="$(ig_line "$REPO/AGENTS.md" "$BEGIN")"
  [ -n "$start" ]
  [ -n "$stop" ]
  [ "$start" -lt "$stop" ]
  [ "$begin" -gt "$stop" ]
}

# --- --diff ------------------------------------------------------------------------

@test "inject-governance: --diff prints a unified diff and WOULD: update with every checksum unchanged" {
  claude_sha="$(ig_sha "$REPO/CLAUDE.md")"
  agents_sha="$(ig_sha "$REPO/AGENTS.md")"
  run --separate-stderr "$SCRIPT" --diff "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'--- a/CLAUDE.md\n+++ b/CLAUDE.md\n@@ '* ]]
  [[ "$output" == *$'--- a/AGENTS.md\n+++ b/AGENTS.md\n@@ '* ]]
  [[ "$output" == *"+$BEGIN"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '^WOULD: ')" -eq 2 ]
  printf '%s\n' "$output" | grep -qx 'WOULD: update CLAUDE.md'
  printf '%s\n' "$output" | grep -qx 'WOULD: update AGENTS.md'
  [ "$(ig_sha "$REPO/CLAUDE.md")" = "$claude_sha" ]
  [ "$(ig_sha "$REPO/AGENTS.md")" = "$agents_sha" ]
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "inject-governance: the --diff output applies with git apply and yields the written result" {
  run --separate-stderr "$SCRIPT" --diff "$REPO"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -v '^WOULD: ' >"$BATS_TEST_TMPDIR/governance.patch"
  git -C "$REPO" apply "$BATS_TEST_TMPDIR/governance.patch"
  ig_ends_with_block "$REPO/CLAUDE.md"
  ig_ends_with_block "$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'UNCHANGED: CLAUDE.md\nUNCHANGED: AGENTS.md' ]
}

@test "inject-governance: --diff on a missing file shows a creation diff and creates nothing" {
  rm "$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" --diff "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'--- /dev/null\n+++ b/AGENTS.md\n@@ -0,0 +1,'* ]]
  printf '%s\n' "$output" | grep -qx 'WOULD: update AGENTS.md'
  [ ! -e "$REPO/AGENTS.md" ]
}

@test "inject-governance: --diff on a repaired file writes nothing and reports UNCHANGED for a current one" {
  "$SCRIPT" "$REPO" >/dev/null
  printf '%s\n%s\n' "$END" "$(cat "$REPO/CLAUDE.md")" >"$REPO/CLAUDE.md.new"
  mv "$REPO/CLAUDE.md.new" "$REPO/CLAUDE.md"
  claude_sha="$(ig_sha "$REPO/CLAUDE.md")"
  run --separate-stderr "$SCRIPT" --diff "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-$END"* ]]
  printf '%s\n' "$output" | grep -qx 'WOULD: update CLAUDE.md'
  printf '%s\n' "$output" | grep -qx 'UNCHANGED: AGENTS.md'
  [ "$(ig_sha "$REPO/CLAUDE.md")" = "$claude_sha" ]
}

# --- refusals ----------------------------------------------------------------------

@test "inject-governance: a symlinked CLAUDE.md exits 1 and neither the link target nor AGENTS.md changes" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  printf 'precious content\n' >"$BATS_TEST_TMPDIR/outside/notes.md"
  rm "$REPO/CLAUDE.md"
  ln -s "$BATS_TEST_TMPDIR/outside/notes.md" "$REPO/CLAUDE.md"
  agents_sha="$(ig_sha "$REPO/AGENTS.md")"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"symbolic link"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/outside/notes.md")" = "precious content" ]
  [ -L "$REPO/CLAUDE.md" ]
  [ "$(ig_sha "$REPO/AGENTS.md")" = "$agents_sha" ]
}

@test "inject-governance: a symlinked AGENTS.md exits 1 before CLAUDE.md is written" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  printf 'agents outside\n' >"$BATS_TEST_TMPDIR/outside/agents.md"
  rm "$REPO/AGENTS.md"
  ln -s "$BATS_TEST_TMPDIR/outside/agents.md" "$REPO/AGENTS.md"
  claude_sha="$(ig_sha "$REPO/CLAUDE.md")"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"symbolic link"* ]]
  [ "$(ig_sha "$REPO/CLAUDE.md")" = "$claude_sha" ]
  [ "$(cat "$BATS_TEST_TMPDIR/outside/agents.md")" = "agents outside" ]
}

@test "inject-governance: a symlinked target exits 1 under --diff too" {
  rm "$REPO/CLAUDE.md"
  ln -s "$REPO/README.md" "$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" --diff "$REPO"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"symbolic link"* ]]
}

@test "inject-governance: a directory named CLAUDE.md exits 1 and is left as it was" {
  rm "$REPO/CLAUDE.md"
  mkdir "$REPO/CLAUDE.md"
  printf 'keep\n' >"$REPO/CLAUDE.md/keep.txt"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not a regular file"* ]]
  [ -d "$REPO/CLAUDE.md" ]
  [ "$(ls -A "$REPO/CLAUDE.md")" = "keep.txt" ]
  [ "$(ig_count "$REPO/AGENTS.md" "$BEGIN")" -eq 0 ]
}

@test "inject-governance: a FIFO named AGENTS.md exits 1 and stays a FIFO" {
  rm "$REPO/AGENTS.md"
  mkfifo "$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not a regular file"* ]]
  [ -p "$REPO/AGENTS.md" ]
  [ "$(ig_count "$REPO/CLAUDE.md" "$BEGIN")" -eq 0 ]
}

@test "inject-governance: an unreadable CLAUDE.md exits 1 and nothing is written" {
  skip_if_root
  chmod 000 "$REPO/CLAUDE.md"
  agents_sha="$(ig_sha "$REPO/AGENTS.md")"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read"* ]]
  [ "$(ig_sha "$REPO/AGENTS.md")" = "$agents_sha" ]
}

@test "inject-governance: a read-only file that needs a change exits 1 and neither file is written" {
  skip_if_root
  claude_sha="$(ig_sha "$REPO/CLAUDE.md")"
  agents_sha="$(ig_sha "$REPO/AGENTS.md")"
  chmod 444 "$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"read-only"* ]]
  [ "$(ig_sha "$REPO/CLAUDE.md")" = "$claude_sha" ]
  [ "$(ig_sha "$REPO/AGENTS.md")" = "$agents_sha" ]
  [ "$(ig_mode "$REPO/AGENTS.md")" = 444 ]
}

@test "inject-governance: an unwritable target directory exits 1 when a file must change" {
  skip_if_root
  chmod 555 "$REPO"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not writable"* ]]
  [ "$(ig_count "$REPO/CLAUDE.md" "$BEGIN")" -eq 0 ]
}

@test "inject-governance: read-only files already in the target state are UNCHANGED" {
  "$SCRIPT" "$REPO" >/dev/null
  chmod 444 "$REPO/CLAUDE.md" "$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'UNCHANGED: CLAUDE.md\nUNCHANGED: AGENTS.md' ]
}

# --- atomic writes -------------------------------------------------------------------

@test "inject-governance: an existing file keeps its mode and a created file honours the umask" {
  chmod 640 "$REPO/CLAUDE.md"
  rm "$REPO/AGENTS.md"
  umask 027
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(ig_mode "$REPO/CLAUDE.md")" = 640 ]
  [ "$(ig_mode "$REPO/AGENTS.md")" = 640 ]
  umask 022
  rm "$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$(ig_mode "$REPO/AGENTS.md")" = 644 ]
}

@test "inject-governance: writes leave no temporary file in the target directory" {
  printf 'x\n%s\n' "$BEGIN" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  run --separate-stderr "$SCRIPT" --diff "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$(find "$REPO" -maxdepth 1 -name '.*.md.*' -print)" ]
  [ "$(git -C "$REPO" status --porcelain | wc -l)" -eq 2 ]
}

@test "inject-governance: every run finishes within 5 seconds" {
  SECONDS=0
  "$SCRIPT" "$REPO" >/dev/null
  [ "$SECONDS" -le 5 ]
  SECONDS=0
  "$SCRIPT" "$REPO" >/dev/null
  [ "$SECONDS" -le 5 ]
  SECONDS=0
  "$SCRIPT" --diff "$REPO" >/dev/null
  [ "$SECONDS" -le 5 ]
  rm "$REPO/CLAUDE.md"
  ln -s "$REPO/README.md" "$REPO/CLAUDE.md"
  SECONDS=0
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [ "$SECONDS" -le 5 ]
  rm "$REPO/CLAUDE.md"
  mkdir "$REPO/CLAUDE.md"
  SECONDS=0
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [ "$SECONDS" -le 5 ]
  SECONDS=0
  run "$SCRIPT" --nope
  [ "$status" -eq 2 ]
  [ "$SECONDS" -le 5 ]
}

# --- content rules (AC-8.2) -------------------------------------------------------------

@test "inject-governance: the written block equals the suite's copy of the architecture's exact text" {
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ig_block_of "$REPO/CLAUDE.md" | cmp - "$BLOCK"
  ig_block_of "$REPO/AGENTS.md" | cmp - "$BLOCK"
  [ "$(ig_size "$BLOCK")" -eq 1736 ]
}

@test "inject-governance: the block equals the Exact text section of architecture.md" {
  if [[ ! -f "$ARCHITECTURE" ]]; then
    skip "architecture.md is not part of this checkout"
  fi
  awk '/^### Exact text/ { f = 1; next } f && /^```markdown$/ { g = 1; next } g && /^```$/ { exit } g' \
    "$ARCHITECTURE" >"$BATS_TEST_TMPDIR/architecture-block.txt"
  [ -s "$BATS_TEST_TMPDIR/architecture-block.txt" ]
  cmp "$BATS_TEST_TMPDIR/architecture-block.txt" "$BLOCK"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ig_block_of "$REPO/CLAUDE.md" | cmp - "$BATS_TEST_TMPDIR/architecture-block.txt"
}

@test "inject-governance: docs_rules reports nothing for rules 1-4 and invariant (e) on the injected files" {
  ig_profile
  run docs_rules CLAUDE.md AGENTS.md
  [ "$status" -eq 0 ]
  "$SCRIPT" "$REPO" >/dev/null
  run docs_rules CLAUDE.md AGENTS.md
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "inject-governance: docs_rules flags rule 3 on both files while the cited profile is absent" {
  "$SCRIPT" "$REPO" >/dev/null
  run docs_rules CLAUDE.md AGENTS.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"(3) AGENTS.md:"*".claude/rust-sdlc.yml does not exist"* ]]
  [[ "$output" == *"(3) CLAUDE.md:"*".claude/rust-sdlc.yml does not exist"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '^(3) ')" -eq 2 ]
}

@test "inject-governance: no code span starts with / and the backticked tokens are exactly those of content rule 2" {
  "$SCRIPT" "$REPO" >/dev/null
  ig_block_of "$REPO/CLAUDE.md" >"$BATS_TEST_TMPDIR/written.txt"
  ig_spans "$BATS_TEST_TMPDIR/written.txt" >"$BATS_TEST_TMPDIR/spans.txt"
  ig_refute grep -q '^`/' "$BATS_TEST_TMPDIR/spans.txt"
  sort "$BATS_TEST_TMPDIR/spans.txt" >"$BATS_TEST_TMPDIR/spans.sorted"
  printf '%s\n' '`.claude/rust-sdlc.yml`' '`AGENTS.md`' '`AGENTS.md`' '`.claude/skills/README.md`' \
    '`protected-config.toml`' '`quality.*`' '`make.*`' | sort >"$BATS_TEST_TMPDIR/rule2.sorted"
  cmp "$BATS_TEST_TMPDIR/spans.sorted" "$BATS_TEST_TMPDIR/rule2.sorted"
  [ "$(grep -o '`' "$BATS_TEST_TMPDIR/written.txt" | wc -l)" -eq 14 ]
}

@test "inject-governance: the block has no make span, numbered list, fence or table" {
  "$SCRIPT" "$REPO" >/dev/null
  ig_block_of "$REPO/AGENTS.md" >"$BATS_TEST_TMPDIR/written.txt"
  [ "$(wc -l <"$BATS_TEST_TMPDIR/written.txt")" -eq 15 ]
  ig_spans "$BATS_TEST_TMPDIR/written.txt" >"$BATS_TEST_TMPDIR/spans.txt"
  [ "$(wc -l <"$BATS_TEST_TMPDIR/spans.txt")" -eq 7 ]
  ig_refute grep -qE '^`[[:space:]]*make([[:space:]]|`)' "$BATS_TEST_TMPDIR/spans.txt"
  ig_refute grep -qE '^[[:space:]]*[0-9]+[.)][[:space:]]' "$BATS_TEST_TMPDIR/written.txt"
  ig_refute grep -qE '^[[:space:]]*(```|~~~)' "$BATS_TEST_TMPDIR/written.txt"
  ig_refute grep -qE '^[[:space:]]*\|' "$BATS_TEST_TMPDIR/written.txt"
}

@test "inject-governance: neither the template literal nor the TEMPLATE_REPOSITORY name appears in what was written" {
  literal="rust-service-""template"
  name="$(ig_template_repository_name)"
  [ "$name" = "rust-template" ]
  cp "$REPO/CLAUDE.md" "$BATS_TEST_TMPDIR/claude.before"
  cp "$REPO/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
  "$SCRIPT" "$REPO" >/dev/null
  for file in CLAUDE.md AGENTS.md; do
    ig_refute grep -qF -- "$literal" "$REPO/$file"
    ig_refute grep -qF -- "$name" "$REPO/$file"
  done
  # What was written: the bytes after the pre-existing text.
  tail -c +"$(($(ig_size "$BATS_TEST_TMPDIR/claude.before") + 1))" "$REPO/CLAUDE.md" >"$BATS_TEST_TMPDIR/written.txt"
  [ -s "$BATS_TEST_TMPDIR/written.txt" ]
  ig_refute grep -qF -- "$literal" "$BATS_TEST_TMPDIR/written.txt"
  ig_refute grep -qF -- "$name" "$BATS_TEST_TMPDIR/written.txt"
  ig_refute grep -qF -- "$literal" "$SCRIPT"
}

@test "inject-governance: stdout carries only result lines and nothing is logged on success" {
  printf 'a\n%s\nb\n' "$END" >"$REPO/CLAUDE.md"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$output" = $'REPAIRED: CLAUDE.md (1 stray marker line(s) removed)\nUPDATED: AGENTS.md' ]
}

# --- template linters (K7, AC-8.3) --------------------------------------------------------

@test "inject-governance: K7 markdownlint-cli2 with the fixture's config passes on both files" {
  k7_require markdownlint-cli2
  "$SCRIPT" "$REPO" >/dev/null
  cd "$REPO"
  [ -f .markdownlint-cli2.yaml ]
  run markdownlint-cli2 CLAUDE.md AGENTS.md
  [ "$status" -eq 0 ]
}

@test "inject-governance: K7 typos with the fixture's _typos.toml passes on both files" {
  k7_require typos
  "$SCRIPT" "$REPO" >/dev/null
  cd "$REPO"
  [ -f _typos.toml ]
  run typos --config _typos.toml CLAUDE.md AGENTS.md
  [ "$status" -eq 0 ]
}

# --- shared script contract (SC-SCRIPT) ----------------------------------------------------

@test "inject-governance: the script follows the shared skeleton and has no banned construct" {
  [ -x "$SCRIPT" ]
  [ "$(sed -n 1p "$SCRIPT")" = '#!/usr/bin/env bash' ]
  [[ "$(sed -n 2p "$SCRIPT")" == '# inject-governance.sh — '* ]]
  grep -qxF '# Usage: inject-governance.sh [--diff] [TARGET_DIR]' "$SCRIPT"
  grep -qE '^# Exit: 0 [^;]+; 1 [^;]+; 2 ' "$SCRIPT"
  grep -qxF 'set -euo pipefail' "$SCRIPT"
  grep -qxF 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' "$SCRIPT"
  grep -qxF '# shellcheck source-path=SCRIPTDIR' "$SCRIPT"
  grep -qxF '# shellcheck source=lib/common.sh' "$SCRIPT"
  grep -qxF 'source "$SCRIPT_DIR/lib/common.sh"' "$SCRIPT"
  ig_refute grep -nE '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)|while true|until false|sed -i|readlink -f|date -d|grep -P|stat -c|declare -n|mapfile -d' "$SCRIPT"
}
