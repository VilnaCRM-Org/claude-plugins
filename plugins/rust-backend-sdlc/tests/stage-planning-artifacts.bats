#!/usr/bin/env bats
# stage-planning-artifacts.bats — cases of scripts/stage-planning-artifacts.sh
# (FR-17, AC-16.2, AC-17.1, AC-17.2, ADR-10, ADR-23).
#
# Hermetic: the repository is the rust-repo fixture materialized at
# $BATS_TEST_TMPDIR/billing-service (its .gitignore ignores _bmad-output/),
# and every planning bundle is generated at runtime with bundle_write, so the
# suite needs no committed *.md fixture. Refusal cases snapshot the whole
# work tree (without .git) before and after the run: nothing written or
# removed means an identical snapshot.
#
# shellcheck disable=SC2030,SC2031 # bats cases are subshells

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  STAGE="$PLUGIN_ROOT/scripts/stage-planning-artifacts.sh"
  REPO="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$REPO"
  bundle_write "$REPO/specs/12-add-x"
  git -C "$REPO" add specs/12-add-x
  git -C "$REPO" commit -q -m 'docs(#12): add planning bundle 12-add-x'
  SPECS="$REPO/specs/12-add-x"
  DEST="$REPO/_bmad-output/planning-artifacts"
  DEST_REL=_bmad-output/planning-artifacts
  cd "$REPO" || return 1
}

teardown() {
  chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# tree_state DIR — one sorted line per entry below DIR (.git skipped): `D` for
# a directory, `L <path> -> <target>` for a symbolic link, the cksum line for
# a regular file; `absent` when DIR does not exist.
tree_state() {
  local root="$1" p
  if [[ ! -e "$root" && ! -L "$root" ]]; then
    printf 'absent\n'
    return 0
  fi
  (
    cd "$root" || exit 1
    find . -path ./.git -prune -o -type d -print | sed 's/^/D /'
    find . -path ./.git -prune -o -type l -print | while IFS= read -r p; do
      printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
    done
    find . -path ./.git -prune -o -type f -exec cksum {} +
  ) | LC_ALL=C sort
}

# file_modes DIR — `<octal mode> <name>` per entry at depth 1 of DIR, sorted.
file_modes() {
  python3 -I -c 'import os, stat, sys
for name in sorted(os.listdir(sys.argv[1])):
    print(oct(stat.S_IMODE(os.lstat(os.path.join(sys.argv[1], name)).st_mode)), name)' "$1"
}

# expected_lines PREFIX SPECS_REL DEST_REL — the six result lines of a full
# bundle, in staging order (PREFIX `STAGED:` or `WOULD: stage`).
expected_lines() {
  local prefix="$1" s="$2" d="$3" pair
  for pair in prd.md:prd.md architecture.md:architecture.md epics.md:epics.md \
    implementation-readiness.md:implementation-readiness.md \
    product-brief.md:product-brief.md research.md:technical-research.md; do
    printf '%s %s/%s -> %s/%s\n' "$prefix" "$s" "${pair%%:*}" "$d" "${pair#*:}"
  done
}

# seed_dest — a dest that already holds a stale file and an outdated prd.md.
seed_dest() {
  mkdir -p "$DEST"
  printf 'stale\n' >"$DEST/stale.md"
  printf 'outdated prd\n' >"$DEST/prd.md"
}

# constraints_len FILE — characters from the `## Constraints` heading to the
# end of FILE (the section bundle_write writes last; ASCII, so bytes).
constraints_len() {
  sed -n '/^## Constraints/,$p' "$1" | wc -c | tr -d ' '
}

# pad_constraints FILE TOTAL — append one line of `x` so that the trailing
# `## Constraints` section of FILE is exactly TOTAL characters long.
pad_constraints() {
  local file="$1" total="$2" need
  need=$((total - $(constraints_len "$file")))
  [[ "$need" -ge 2 ]] || return 1
  printf '%*s\n' "$((need - 1))" '' | tr ' ' x >>"$file"
}

# assert_refused REASON — exit 1 and stdout exactly `REFUSED: REASON`.
assert_refused() {
  if [[ "$status" -ne 1 || "$output" != "REFUSED: $1" ]]; then
    printf 'expected exit 1 and REFUSED: %s\ngot exit %s, stdout:\n%s\nstderr:\n%s\n' \
      "$1" "$status" "$output" "${stderr-}" >&2
    return 1
  fi
}

# --- usage and environment ------------------------------------------------------

@test "stage-planning-artifacts: --help prints the header and exits 0 in any position" {
  run --separate-stderr "$STAGE" --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "stage-planning-artifacts.sh — stage a specs/<N>-<slug>/ planning bundle for bmalph implement (FR-17)." ]
  [[ "$output" == *"Usage: stage-planning-artifacts.sh <specs-dir> [--dest <dir>] [--dry-run]"* ]]
  [[ "$output" == *"Exit: 0 staged"*"; 1 refused; 2 usage error"* ]]
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x --dry-run --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: stage-planning-artifacts.sh"* ]]
  for line in "${lines[@]}"; do
    [[ "$line" != "WOULD: "* && "$line" != "STAGED: "* ]]
  done
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: an unknown flag is a usage error (exit 2)" {
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x --force
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"[rust-sdlc][ERROR] unknown argument: --force"* ]]
  [[ "$stderr" == *"usage: stage-planning-artifacts.sh <specs-dir>"* ]]
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a missing specs dir, a valueless --dest and a second positional exit 2" {
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"missing <specs-dir>"* ]]
  run --separate-stderr "$STAGE" --dry-run
  [ "$status" -eq 2 ]
  run --separate-stderr "$STAGE" specs/12-add-x --dest
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--dest needs a value"* ]]
  run --separate-stderr "$STAGE" specs/12-add-x --dest --dry-run
  [ "$status" -eq 2 ]
  run --separate-stderr "$STAGE" specs/12-add-x specs/example-bundle
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"unexpected argument: specs/example-bundle"* ]]
  [ -z "$output" ]
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a working directory outside a git work tree exits 2" {
  plain="$BATS_TEST_TMPDIR/plain"
  bundle_write "$plain/specs/12-add-x"
  cd "$plain"
  ceiling="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  GIT_CEILING_DIRECTORIES="$ceiling" run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"[rust-sdlc][ERROR] not inside a git work tree"* ]]
  [ ! -e "$plain/_bmad-output" ]
  GIT_CEILING_DIRECTORIES="$ceiling" run --separate-stderr "$STAGE" specs/12-add-x --dry-run
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

# --- staging ----------------------------------------------------------------------

@test "stage-planning-artifacts: stages the exact bundle file set with one STAGED line per file" {
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines STAGED: specs/12-add-x "$DEST_REL")" ]
  [ "$(cd "$DEST" && LC_ALL=C ls -A)" = "$(printf '%s\n' architecture.md epics.md \
    implementation-readiness.md prd.md product-brief.md technical-research.md)" ]
  for f in prd.md architecture.md epics.md implementation-readiness.md product-brief.md; do
    cmp "$SPECS/$f" "$DEST/$f"
  done
  cmp "$SPECS/research.md" "$DEST/technical-research.md"
  [ ! -e "$DEST/run-summary.md" ]
  [ ! -e "$DEST/research.md" ]
  [[ "$stderr" == *"[rust-sdlc][INFO] staged 6 files from specs/12-add-x into $DEST_REL"* ]]
  [[ "$stderr" != *"WARN"* ]]
}

@test "stage-planning-artifacts: copies every ux*.md, in byte order, after the fixed files" {
  printf '# UX\n' >"$SPECS/ux.md"
  printf '# UX flows\n' >"$SPECS/ux-flows.md"
  printf '# Notes\n' >"$SPECS/notes.md"
  printf 'ux text\n' >"$SPECS/ux-notes.txt"
  mkdir -p "$SPECS/ux-assets"
  printf '# nested\n' >"$SPECS/ux-assets/ux-deep.md"
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines STAGED: specs/12-add-x "$DEST_REL"
    printf 'STAGED: specs/12-add-x/ux-flows.md -> %s/ux-flows.md\n' "$DEST_REL"
    printf 'STAGED: specs/12-add-x/ux.md -> %s/ux.md\n' "$DEST_REL")" ]
  cmp "$SPECS/ux.md" "$DEST/ux.md"
  cmp "$SPECS/ux-flows.md" "$DEST/ux-flows.md"
  [ ! -e "$DEST/notes.md" ]
  [ ! -e "$DEST/ux-notes.txt" ]
  [ ! -e "$DEST/ux-deep.md" ]
  [ ! -e "$DEST/ux-assets" ]
}

@test "stage-planning-artifacts: a re-run prints the same lines and leaves the same bytes" {
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  first_out="$output"
  first_tree="$(tree_state "$REPO")"
  first_modes="$(file_modes "$DEST")"
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  [ "$output" = "$first_out" ]
  [ "$(tree_state "$REPO")" = "$first_tree" ]
  [ "$(file_modes "$DEST")" = "$first_modes" ]
  [[ "$output" != *"REMOVED:"* ]]
}

@test "stage-planning-artifacts: removes only stale regular *.md files at depth 1 of the dest" {
  seed_dest
  printf 'old notes\n' >"$DEST/old-notes.md"
  printf 'keep\n' >"$DEST/keep.txt"
  mkdir -p "$DEST/sub"
  printf 'nested\n' >"$DEST/sub/keep.md"
  ln -s keep.txt "$DEST/link.md"
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines STAGED: specs/12-add-x "$DEST_REL"
    printf 'REMOVED: %s/old-notes.md\n' "$DEST_REL"
    printf 'REMOVED: %s/stale.md\n' "$DEST_REL")" ]
  [ ! -e "$DEST/stale.md" ]
  [ ! -e "$DEST/old-notes.md" ]
  cmp "$SPECS/prd.md" "$DEST/prd.md"
  [ "$(cat "$DEST/keep.txt")" = keep ]
  [ "$(cat "$DEST/sub/keep.md")" = nested ]
  [ -L "$DEST/link.md" ]
  [ "$(readlink "$DEST/link.md")" = keep.txt ]
}

@test "stage-planning-artifacts: optional bundle files that are absent are skipped with a warning" {
  rm "$SPECS/product-brief.md" "$SPECS/research.md" "$SPECS/implementation-readiness.md"
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines STAGED: specs/12-add-x "$DEST_REL" | head -n 3)" ]
  [ "$(cd "$DEST" && LC_ALL=C ls -A)" = "$(printf '%s\n' architecture.md epics.md prd.md)" ]
  [[ "$stderr" == *"[rust-sdlc][WARN] specs/12-add-x has no product-brief.md"* ]]
  [[ "$stderr" == *"[rust-sdlc][WARN] specs/12-add-x has no research.md"* ]]
  [[ "$stderr" == *"[rust-sdlc][WARN] specs/12-add-x has no implementation-readiness.md"* ]]
}

@test "stage-planning-artifacts: --dest under _bmad-output/ stages there and leaves the default dest alone" {
  run --separate-stderr "$STAGE" specs/12-add-x --dest _bmad-output/custom/
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines STAGED: specs/12-add-x _bmad-output/custom)" ]
  cmp "$SPECS/research.md" "$REPO/_bmad-output/custom/technical-research.md"
  [ ! -e "$DEST" ]
}

@test "stage-planning-artifacts: runs from a subdirectory and prints repository-relative paths" {
  cd "$REPO/crates"
  run --separate-stderr "$STAGE" ../specs/12-add-x/
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines STAGED: specs/12-add-x "$DEST_REL")" ]
  [ -f "$DEST/epics.md" ]
  [ ! -e "$REPO/crates/_bmad-output" ]
}

# --- refusals (AC-16.2, AC-17.2): exit 1, one REFUSED line, nothing written ---------

@test "stage-planning-artifacts: a missing epics.md, prd.md or architecture.md is refused" {
  seed_dest
  for f in epics.md prd.md architecture.md; do
    mv "$SPECS/$f" "$BATS_TEST_TMPDIR/$f"
    before="$(tree_state "$REPO")"
    run --separate-stderr "$STAGE" specs/12-add-x
    assert_refused "$f is missing from specs/12-add-x"
    [ "$(tree_state "$REPO")" = "$before" ]
    mv "$BATS_TEST_TMPDIR/$f" "$SPECS/$f"
  done
}

@test "stage-planning-artifacts: epics.md without a ### Story N.M: heading is refused" {
  seed_dest
  sed 's/^### Story \([0-9]*\)\.[0-9]*:/### Story \1:/' "$SPECS/epics.md" >"$BATS_TEST_TMPDIR/epics.md"
  cp "$BATS_TEST_TMPDIR/epics.md" "$SPECS/epics.md"
  grep -q '^### Story 1: ' "$SPECS/epics.md"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "epics.md in specs/12-add-x has no ### Story N.M: heading"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a NO-GO readiness file written by bundle_write --blocked is refused" {
  seed_dest
  bundle_write "$SPECS" --blocked
  grep -q 'NO-GO' "$SPECS/implementation-readiness.md"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused 'implementation-readiness.md in specs/12-add-x matches /NO[-\s]?GO/i (readiness is not ready)'
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: the readiness regex is bmalph's: case-insensitive and across a line break" {
  for text in 'Gate: no go' 'Gate: No-Go' 'Gate: NOGO' $'Gate: NO\nGO' $'Gate: no\tgo'; do
    printf '# Implementation Readiness\n\n%s\n' "$text" >"$SPECS/implementation-readiness.md"
    run --separate-stderr "$STAGE" specs/12-add-x
    assert_refused 'implementation-readiness.md in specs/12-add-x matches /NO[-\s]?GO/i (readiness is not ready)'
  done
  printf '# Implementation Readiness\n\nVerdict: ready. Go.\n' >"$SPECS/implementation-readiness.md"
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  cmp "$SPECS/implementation-readiness.md" "$DEST/implementation-readiness.md"
}

@test "stage-planning-artifacts: a dest that is not git-ignored is refused" {
  grep -v '^_bmad-output/$' "$REPO/.gitignore" >"$BATS_TEST_TMPDIR/gitignore"
  cp "$BATS_TEST_TMPDIR/gitignore" "$REPO/.gitignore"
  git -C "$REPO" commit -q -am 'chore: track _bmad-output'
  run ! git -C "$REPO" check-ignore -q "$DEST_REL/"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "dest $DEST_REL is tracked (not git-ignored)"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a dest holding a tracked file is refused" {
  seed_dest
  git -C "$REPO" add -f "$DEST_REL/stale.md"
  git -C "$REPO" commit -q -m 'chore: track a staged file'
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "dest $DEST_REL is tracked (not git-ignored)"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a specs dir outside the repository is refused" {
  seed_dest
  outside="$BATS_TEST_TMPDIR/elsewhere/12-add-x"
  bundle_write "$outside"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" "$outside"
  assert_refused "specs dir $outside is outside the repository"
  [ "$(tree_state "$REPO")" = "$before" ]
  run --separate-stderr "$STAGE" ../elsewhere/12-add-x
  assert_refused "specs dir ../elsewhere/12-add-x is outside the repository"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a symlinked specs dir is refused" {
  seed_dest
  bundle_write "$BATS_TEST_TMPDIR/elsewhere/12-add-x"
  ln -s 12-add-x "$REPO/specs/12-link"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/12-add-x" "$REPO/specs/12-away"
  ln -s specs "$REPO/plans"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-link
  assert_refused "specs dir specs/12-link is a symbolic link"
  run --separate-stderr "$STAGE" specs/12-link/
  assert_refused "specs dir specs/12-link/ is a symbolic link"
  run --separate-stderr "$STAGE" specs/12-away
  assert_refused "specs dir specs/12-away is a symbolic link"
  run --separate-stderr "$STAGE" plans/12-add-x
  assert_refused "specs dir plans/12-add-x has a symbolic link in its path"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a specs dir that is missing, a file or inside _bmad-output/ is refused" {
  run --separate-stderr "$STAGE" specs/99-absent
  assert_refused "specs dir specs/99-absent does not exist or is not a directory"
  run --separate-stderr "$STAGE" specs/12-add-x/prd.md
  assert_refused "specs dir specs/12-add-x/prd.md does not exist or is not a directory"
  bundle_write "$REPO/_bmad-output/12-add-x"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" _bmad-output/12-add-x
  assert_refused "specs dir _bmad-output/12-add-x is inside _bmad-output/"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: --dest target is refused with nothing written or removed" {
  seed_dest
  mkdir -p "$REPO/target"
  printf 'stale\n' >"$REPO/target/stale.md"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x --dest target
  assert_refused 'dest target is outside _bmad-output/'
  [ "$(tree_state "$REPO")" = "$before" ]
  [ "$(cat "$REPO/target/stale.md")" = stale ]
  [ "$(cat "$DEST/stale.md")" = stale ]
}

@test "stage-planning-artifacts: a dest that escapes _bmad-output/ is refused" {
  seed_dest
  before="$(tree_state "$REPO")"
  for d in _bmad-output _bmad-output/ _bmad-output/.. _bmad-output/../docs \
    _bmad-output/missing/../../docs "$BATS_TEST_TMPDIR/_bmad-output/planning-artifacts" \
    "$REPO/_bmad-output/../target/x"; do
    run --separate-stderr "$STAGE" specs/12-add-x --dest "$d"
    assert_refused "dest $d is outside _bmad-output/"
  done
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a symlinked _bmad-output or dest is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/shared"
  ln -s "$BATS_TEST_TMPDIR/shared" "$REPO/_bmad-output"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "dest $DEST_REL is outside _bmad-output/"
  [ "$(tree_state "$REPO")" = "$before" ]
  [ "$(tree_state "$BATS_TEST_TMPDIR/shared")" = "$(printf 'D .\n')" ]
  rm "$REPO/_bmad-output"
  mkdir -p "$REPO/_bmad-output/other"
  ln -s other "$DEST"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "dest $DEST_REL is a symbolic link or has one in its path"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a dest that is not a directory is refused" {
  mkdir -p "$REPO/_bmad-output"
  printf 'not a directory\n' >"$DEST"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "dest $DEST_REL is not a directory"
  run --separate-stderr "$STAGE" specs/12-add-x --dest "$DEST_REL/sub"
  assert_refused "dest $DEST_REL/sub is not a directory"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a symlinked or non-regular bundle file is refused" {
  seed_dest
  mv "$SPECS/prd.md" "$BATS_TEST_TMPDIR/prd.md"
  ln -s "$BATS_TEST_TMPDIR/prd.md" "$SPECS/prd.md"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "prd.md in specs/12-add-x is not a regular file"
  [ "$(tree_state "$REPO")" = "$before" ]
  rm "$SPECS/prd.md"
  mv "$BATS_TEST_TMPDIR/prd.md" "$SPECS/prd.md"
  mkdir "$SPECS/ux-design.md"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "ux-design.md in specs/12-add-x is not a regular file"
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a dest file that is a symbolic link is refused before any write" {
  seed_dest
  printf 'elsewhere\n' >"$BATS_TEST_TMPDIR/target.md"
  ln -s "$BATS_TEST_TMPDIR/target.md" "$DEST/epics.md"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused "cannot write $DEST_REL/epics.md"
  [[ "$stderr" == *"symbolic link"* ]]
  [ "$(tree_state "$REPO")" = "$before" ]
  [ "$(cat "$BATS_TEST_TMPDIR/target.md")" = elsewhere ]
}

# --- ## Constraints length (ADR-10: bmalph cuts the section at 5,000) ------------

@test "stage-planning-artifacts: a ## Constraints section over 4500 characters is refused with its length" {
  seed_dest
  pad_constraints "$SPECS/architecture.md" 4501
  [ "$(constraints_len "$SPECS/architecture.md")" -eq 4501 ]
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused 'architecture.md ## Constraints exceeds 4500 characters (4501)'
  [ "$(tree_state "$REPO")" = "$before" ]
  pad_constraints "$SPECS/architecture.md" 9000
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused 'architecture.md ## Constraints exceeds 4500 characters (9000)'
  [ "$(tree_state "$REPO")" = "$before" ]
}

@test "stage-planning-artifacts: a ## Constraints section of exactly 4500 characters is staged" {
  pad_constraints "$SPECS/architecture.md" 4500
  [ "$(constraints_len "$SPECS/architecture.md")" -eq 4500 ]
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines STAGED: specs/12-add-x "$DEST_REL")" ]
  cmp "$SPECS/architecture.md" "$DEST/architecture.md"
}

@test "stage-planning-artifacts: the ## Constraints length runs to the next level-2 heading only" {
  # A level-3 heading stays inside the section.
  printf '\n### Detail\n\n' >>"$SPECS/architecture.md"
  pad_constraints "$SPECS/architecture.md" 4501
  run --separate-stderr "$STAGE" specs/12-add-x
  assert_refused 'architecture.md ## Constraints exceeds 4500 characters (4501)'
  # A level-2 heading ends it: text after `## Appendix` is not counted.
  bundle_write "$SPECS"
  {
    printf '\n## Appendix\n\n'
    printf '%*s\n' 6000 '' | tr ' ' y
  } >>"$SPECS/architecture.md"
  run --separate-stderr "$STAGE" specs/12-add-x
  [ "$status" -eq 0 ]
  cmp "$SPECS/architecture.md" "$DEST/architecture.md"
}

# --- --dry-run ----------------------------------------------------------------------

@test "stage-planning-artifacts: --dry-run prints only WOULD: stage lines and writes nothing" {
  seed_dest
  printf '# UX\n' >"$SPECS/ux.md"
  before="$(tree_state "$REPO")"
  run --separate-stderr "$STAGE" --dry-run specs/12-add-x
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines 'WOULD: stage' specs/12-add-x "$DEST_REL"
    printf 'WOULD: stage specs/12-add-x/ux.md -> %s/ux.md\n' "$DEST_REL")" ]
  for line in "${lines[@]}"; do
    [[ "$line" == "WOULD: stage "* ]]
  done
  [ "$(tree_state "$REPO")" = "$before" ]
  [ "$(cat "$DEST/stale.md")" = stale ]
  rm -r "$REPO/_bmad-output"
  run --separate-stderr "$STAGE" specs/12-add-x --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_lines 'WOULD: stage' specs/12-add-x "$DEST_REL"
    printf 'WOULD: stage specs/12-add-x/ux.md -> %s/ux.md\n' "$DEST_REL")" ]
  [ ! -e "$REPO/_bmad-output" ]
}

@test "stage-planning-artifacts: --dry-run runs every pre-check and refuses like a real run" {
  bundle_write "$SPECS" --blocked
  run --separate-stderr "$STAGE" specs/12-add-x --dry-run
  assert_refused 'implementation-readiness.md in specs/12-add-x matches /NO[-\s]?GO/i (readiness is not ready)'
  bundle_write "$SPECS"
  pad_constraints "$SPECS/architecture.md" 4600
  run --separate-stderr "$STAGE" specs/12-add-x --dry-run
  assert_refused 'architecture.md ## Constraints exceeds 4500 characters (4600)'
  run --separate-stderr "$STAGE" specs/12-add-x --dry-run --dest target
  assert_refused 'dest target is outside _bmad-output/'
  [ ! -e "$REPO/_bmad-output" ]
}
