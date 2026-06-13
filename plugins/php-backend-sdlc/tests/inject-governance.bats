#!/usr/bin/env bats
# Tests for scripts/inject-governance.sh (Story 2.3, FR-2, NFR-3, ADR-3).
#
# The NFR-3 contract is the focus: re-runs must leave files byte-stable
# (asserted via git diff --quiet), user content outside the markers must
# survive byte-identical, and every corrupted-marker state must repair
# to exactly one managed block without eating user text.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INJECT="$PLUGIN_ROOT/scripts/inject-governance.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  BEGIN='<!-- php-backend-sdlc:begin -->'
  END='<!-- php-backend-sdlc:end -->'
}

# marker_pairs FILE — echoes "<begin-count> <end-count>"
marker_pairs() {
  echo "$(grep -cxF "$BEGIN" "$1" || true) $(grep -cxF "$END" "$1" || true)"
}

@test "missing files are created holding exactly one block" {
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  for f in CLAUDE.md AGENTS.md; do
    [ -f "$REPO/$f" ]
    [ "$(marker_pairs "$REPO/$f")" = "1 1" ]
    grep -q 'Skill-triage gate' "$REPO/$f"
    grep -q 'Protected quality thresholds' "$REPO/$f"
    grep -q 'Container-only execution' "$REPO/$f"
  done
}

@test "block appended to existing file; user content byte-identical outside markers" {
  printf '# My project\n\nUser intro text.\n' > "$REPO/CLAUDE.md"
  printf 'Agent notes.\n' > "$REPO/AGENTS.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  # content before the block is untouched, byte for byte
  head -n 3 "$REPO/CLAUDE.md" | cmp - <(printf '# My project\n\nUser intro text.\n')
  [ "$(marker_pairs "$REPO/CLAUDE.md")" = "1 1" ]
  head -n 1 "$REPO/AGENTS.md" | cmp - <(printf 'Agent notes.\n')
}

@test "two consecutive runs: git diff empty on second (NFR-3 AC)" {
  printf '# My project\n' > "$REPO/CLAUDE.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  git -C "$REPO" add -A
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm baseline
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *unchanged* ]]
  git -C "$REPO" diff --quiet
}

@test "stale block content is replaced in place, position preserved" {
  cat > "$REPO/CLAUDE.md" <<EOF
# Top heading

$BEGIN
old stale governance text
$END

## Section after the block
EOF
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  ! grep -q 'old stale governance text' "$REPO/CLAUDE.md"
  grep -q 'Skill-triage gate' "$REPO/CLAUDE.md"
  # position: block still between the two user headings
  [ "$(head -n 1 "$REPO/CLAUDE.md")" = "# Top heading" ]
  [ "$(tail -n 1 "$REPO/CLAUDE.md")" = "## Section after the block" ]
  [ "$(marker_pairs "$REPO/CLAUDE.md")" = "1 1" ]
}

@test "duplicated balanced blocks collapse to exactly one at the first position (NFR-3 AC)" {
  cat > "$REPO/CLAUDE.md" <<EOF
intro line
$BEGIN
first stale copy
$END
middle user line
$BEGIN
second stale copy
$END
outro line
EOF
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(marker_pairs "$REPO/CLAUDE.md")" = "1 1" ]
  ! grep -q 'stale copy' "$REPO/CLAUDE.md"
  grep -q 'middle user line' "$REPO/CLAUDE.md"
  grep -q 'intro line' "$REPO/CLAUDE.md"
  grep -q 'outro line' "$REPO/CLAUDE.md"
  # first position wins: block starts before 'middle user line'
  first_block_line="$(grep -nxF "$BEGIN" "$REPO/CLAUDE.md" | cut -d: -f1)"
  middle_line="$(grep -nxF 'middle user line' "$REPO/CLAUDE.md" | cut -d: -f1)"
  [ "$first_block_line" -lt "$middle_line" ]
}

@test "orphaned begin marker: marker line removed, user content preserved, one block appended" {
  cat > "$REPO/CLAUDE.md" <<EOF
before text
$BEGIN
user text that must NOT be swallowed
after text
EOF
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  grep -q 'user text that must NOT be swallowed' "$REPO/CLAUDE.md"
  grep -q 'before text' "$REPO/CLAUDE.md"
  grep -q 'after text' "$REPO/CLAUDE.md"
  [ "$(marker_pairs "$REPO/CLAUDE.md")" = "1 1" ]
}

@test "inverted markers (end before begin, counts balanced): user content preserved" {
  cat > "$REPO/CLAUDE.md" <<EOF
$END
user line A
$BEGIN
user line B
user line C
EOF
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  grep -q 'user line A' "$REPO/CLAUDE.md"
  grep -q 'user line B' "$REPO/CLAUDE.md"
  grep -q 'user line C' "$REPO/CLAUDE.md"
  [ "$(marker_pairs "$REPO/CLAUDE.md")" = "1 1" ]
  # repaired block is well-ordered: begin before end
  begin_line="$(grep -nxF "$BEGIN" "$REPO/CLAUDE.md" | cut -d: -f1)"
  end_line="$(grep -nxF "$END" "$REPO/CLAUDE.md" | cut -d: -f1)"
  [ "$begin_line" -lt "$end_line" ]
}

@test "CRLF managed block is recognized: replaced in place, no duplicate (IG-E5)" {
  # Windows-edited CLAUDE.md: markers carry a trailing CR. Exact-line
  # matching treated the block as absent, appended a second LF block,
  # and kept the stale CRLF copy forever.
  printf 'user\r\n%s\r\nOLD GOVERNANCE\r\n%s\r\nmore\r\n' "$BEGIN" "$END" > "$REPO/CLAUDE.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'php-backend-sdlc:begin' "$REPO/CLAUDE.md")" -eq 1 ]
  ! grep -q 'OLD GOVERNANCE' "$REPO/CLAUDE.md"
  [ "$(grep -c 'Skill-triage gate' "$REPO/CLAUDE.md")" -eq 1 ]
  # user content outside the markers keeps its CRLF endings untouched
  grep -q $'^user\r$' "$REPO/CLAUDE.md"
  grep -q $'^more\r$' "$REPO/CLAUDE.md"
  # second run is byte-stable on the repaired file
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE.md: unchanged"* ]]
}

@test "fully CRLF-converted file (unix2dos): re-run keeps exactly one governance copy (E11)" {
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  sed -i 's/$/\r/' "$REPO/CLAUDE.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'Skill-triage gate' "$REPO/CLAUDE.md")" -eq 1 ]
  [ "$(grep -c 'php-backend-sdlc:begin' "$REPO/CLAUDE.md")" -eq 1 ]
}

@test "10 concurrent runs: one block per file, user content preserved (NFR-3)" {
  # Atomic in-dir mktemp+mv plus snapshot-once rendering: any
  # serialization of complete renders must end well-formed — never
  # duplicated/interleaved blocks, never lost user lines.
  printf '# t\nuser line\n' > "$REPO/CLAUDE.md"
  for _ in $(seq 10); do
    "$INJECT" "$REPO" >/dev/null 2>&1 &
  done
  wait
  [ "$(marker_pairs "$REPO/CLAUDE.md")" = "1 1" ]
  [ "$(marker_pairs "$REPO/AGENTS.md")" = "1 1" ]
  [ "$(grep -c 'Skill-triage gate' "$REPO/CLAUDE.md")" -eq 1 ]
  [ "$(grep -c 'Skill-triage gate' "$REPO/AGENTS.md")" -eq 1 ]
  grep -qx 'user line' "$REPO/CLAUDE.md"
  # no leaked temp files from the atomic-write path
  [ -z "$(find "$REPO" -name '.sdlc-governance.*' -print -quit)" ]
}

@test "created files honor the umask instead of mktemp's 0600" {
  umask 022
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$REPO/CLAUDE.md")" = "644" ]
  [ "$(stat -c '%a' "$REPO/AGENTS.md")" = "644" ]
}

@test "--diff previews without writing" {
  printf '# My project\n' > "$REPO/CLAUDE.md"
  before="$(cat "$REPO/CLAUDE.md")"
  run "$INJECT" --diff "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pending changes"* ]]
  [[ "$output" == *"+$BEGIN"* ]]
  [ "$(cat "$REPO/CLAUDE.md")" = "$before" ]
  [ ! -f "$REPO/AGENTS.md" ]
}

@test "block text references profile keys, not hardcoded values" {
  run "$INJECT" "$REPO"
  grep -q '`.claude/php-sdlc.yml`' "$REPO/CLAUDE.md"
  grep -q '`quality.\*`' "$REPO/CLAUDE.md"
  grep -q '`make.\*`' "$REPO/CLAUDE.md"
}

@test "symlinked CLAUDE.md is refused, the symlink target outside the repo is untouched" {
  # Threat model: an untrusted cloned repo plants CLAUDE.md -> a file
  # outside the target. The tool must refuse to follow it rather than
  # rewrite the outside file (write-outside-target).
  outside="$BATS_TEST_TMPDIR/outside/important.md"
  mkdir -p "$(dirname "$outside")"
  printf 'PRECIOUS USER CONTENT\n' > "$outside"
  ln -s "$outside" "$REPO/CLAUDE.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to follow symlink"* ]]
  # the outside file is byte-identical: no managed block leaked into it
  cmp "$outside" <(printf 'PRECIOUS USER CONTENT\n')
  ! grep -q 'Skill-triage gate' "$outside"
}

@test "symlinked AGENTS.md is refused even after CLAUDE.md is processed" {
  # CLAUDE.md is a normal new file; AGENTS.md is the malicious symlink.
  # The loop must still die when it reaches the symlinked second file.
  outside="$BATS_TEST_TMPDIR/outside/agents-target.md"
  mkdir -p "$(dirname "$outside")"
  printf 'agents outside content\n' > "$outside"
  ln -s "$outside" "$REPO/AGENTS.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to follow symlink"* ]]
  cmp "$outside" <(printf 'agents outside content\n')
}

@test "unknown flag: usage error" {
  run "$INJECT" --bogus "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}

# --- R2 regression: non-regular target, fenced markers, read-only file -----

@test "R2 Bug 3: a directory named CLAUDE.md is refused, intact, no temp litter" {
  # mv -f would otherwise drop the temp file INSIDE the directory, log
  # 'managed block written', exit 0, and leave no governance file.
  mkdir -p "$REPO/CLAUDE.md"
  printf 'keep\n' > "$REPO/CLAUDE.md/keep.txt"
  run "$INJECT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a regular file"* ]]
  [ -d "$REPO/CLAUDE.md" ]
  # only the user's file is inside; no .sdlc-governance temp litter
  [ "$(ls -A "$REPO/CLAUDE.md")" = "keep.txt" ]
}

@test "R2 Bug 3: a directory CLAUDE.md is refused under --diff too (not 'would be created')" {
  mkdir -p "$REPO/CLAUDE.md"
  run "$INJECT" --diff "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a regular file"* ]]
  [[ "$output" != *"would be created"* ]]
}

@test "R2 Bug 3: a FIFO CLAUDE.md is refused and left a FIFO" {
  mkfifo "$REPO/CLAUDE.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a regular file"* ]]
  [ -p "$REPO/CLAUDE.md" ]
  rm -f "$REPO/CLAUDE.md"
}

@test "R2 Bug 4: governance markers documented inside a code fence are not clobbered (FR-2)" {
  printf '# docs\n\n```\n%s\nEXAMPLE governance text the user is documenting\n%s\n```\n\ntail\n' \
    "$BEGIN" "$END" > "$REPO/CLAUDE.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  # the fenced example survives verbatim ...
  grep -qF 'EXAMPLE governance text the user is documenting' "$REPO/CLAUDE.md"
  # ... the code fence stays intact (both fence lines preserved) ...
  [ "$(grep -cxF '```' "$REPO/CLAUDE.md")" -eq 2 ]
  # ... and exactly one REAL managed block is appended outside the fence
  # (fixture has 1 fenced begin + 1 real begin = 2 total).
  [ "$(marker_pairs "$REPO/CLAUDE.md")" = "2 2" ]
  grep -q 'Skill-triage gate' "$REPO/CLAUDE.md"
}

@test "R2 Bug 4: fenced-marker file is idempotent on rerun (no duplicate real block)" {
  printf '# docs\n\n```\n%s\nEXAMPLE text\n%s\n```\n' "$BEGIN" "$END" > "$REPO/CLAUDE.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  first="$(cat "$REPO/CLAUDE.md")"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged"* ]]
  [ "$(cat "$REPO/CLAUDE.md")" = "$first" ]
  grep -qF 'EXAMPLE text' "$REPO/CLAUDE.md"
}

@test "R2 Bug 4: an UNCLOSED fence falls back to whole-line matching and stays idempotent" {
  # Fence-aware suppression must NOT activate on an odd/unterminated fence
  # count: a stateful toggle would stay 'inside the fence' through EOF and
  # swallow the real block at the end, so the next run would append a
  # duplicate (NFR-3 regression). With an unclosed fence we match markers
  # by whole line, so a real stale block is replaced in place and the count
  # is stable across runs.
  printf '# proj\n\n```\nunclosed code fence\n\n%s\nSTALE\n%s\n' "$BEGIN" "$END" > "$REPO/CLAUDE.md"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(grep -cxF "$BEGIN" "$REPO/CLAUDE.md")" -eq 1 ]
  ! grep -qx 'STALE' "$REPO/CLAUDE.md"
  grep -q 'Skill-triage gate' "$REPO/CLAUDE.md"
  # rerun is byte-stable: no second block appended
  first="$(cat "$REPO/CLAUDE.md")"
  run "$INJECT" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged"* ]]
  [ "$(cat "$REPO/CLAUDE.md")" = "$first" ]
  [ "$(grep -cxF "$BEGIN" "$REPO/CLAUDE.md")" -eq 1 ]
}

@test "R2 Bug 5: a read-only (0444) managed file needing a change is refused, unmodified" {
  printf 'user content, no markers\n' > "$REPO/CLAUDE.md"
  chmod 0444 "$REPO/CLAUDE.md"
  before="$(cat "$REPO/CLAUDE.md")"
  run "$INJECT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"read-only"* ]]
  [ "$(cat "$REPO/CLAUDE.md")" = "$before" ]
  ! grep -q 'php-backend-sdlc:begin' "$REPO/CLAUDE.md"
  [ "$(stat -c '%a' "$REPO/CLAUDE.md")" = "444" ]
  # no temp litter left behind by the refused write
  [ -z "$(ls -A "$REPO" | grep sdlc-governance || true)" ]
}
