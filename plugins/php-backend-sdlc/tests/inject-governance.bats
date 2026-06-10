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

@test "unknown flag: usage error" {
  run "$INJECT" --bogus "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}
