#!/usr/bin/env bats
# generate-profile.bats — cases of scripts/generate-profile.sh (FR-5, FR-6;
# AC-6.1, AC-6.2, AC-6.3, AC-6.5, AC-6.6, AC-6.7; ADR-17, ADR-24; NFR-1,
# NFR-2, NFR-3, NFR-4, NFR-13, NFR-14).
#
# Every case materializes the stub repository at $BATS_TEST_TMPDIR/billing-service
# (rr_materialize), the directory the golden profile
# tests/fixtures/profiles/golden.yml was detected from. A case that changes the
# stub states its expectation as the golden profile with the named keys set
# (gp_expect, through mutate_profile) and compares the whole output byte for
# byte, so it also proves that no other key moved. Docker is unreachable and a
# recording cargo stub is first on PATH unless a case says otherwise; a case
# that needs cargo genuinely absent runs the script with a sandbox PATH. The
# suite runs under both YAML backends (default, then SDLC_FORCE_PYTHON_YAML=1);
# the parity cases compare the two inside one run.
#
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2030,SC2031 # bats cases are subshells

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  GEN="$PLUGIN_ROOT/scripts/generate-profile.sh"
  VALIDATE="$PLUGIN_ROOT/scripts/validate-profile.sh"
  GOLDEN="$PLUGIN_ROOT/tests/fixtures/profiles/golden.yml"
  FIXTURE_REPO="$PLUGIN_ROOT/tests/fixtures/rust-repo"
  VARIANTS="$PLUGIN_ROOT/tests/fixtures/variants"
  STUB="$BATS_TEST_TMPDIR/billing-service"
  PROFILE="$STUB/.claude/rust-sdlc.yml"
  EXPECTED="$BATS_TEST_TMPDIR/expected.yml"
  OUT="$BATS_TEST_TMPDIR/out.yml"
  ERR="$BATS_TEST_TMPDIR/err.txt"
  USAGE='generate-profile.sh [--refresh] [--stdout] [--run-in-container true|false] [TARGET_DIR]'
  rr_materialize "$STUB"
}

teardown() {
  chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# --- suite helpers -------------------------------------------------------------

# gp_expect [KEY VALUE]... — $EXPECTED = the golden profile with each KEY set
# to VALUE (mutate_profile; a VALUE starting with a newline is a block value).
gp_expect() {
  cp "$GOLDEN" "$EXPECTED"
  while (($# >= 2)); do
    mutate_profile "$EXPECTED" "$1" "$2" || return 1
    shift 2
  done
}

# gp_same EXPECTED ACTUAL — byte equality; the unified diff shows on failure.
gp_same() {
  diff -u -- "$1" "$2"
}

# gp_detect [ARG...] — the generator with --stdout on the stub: YAML in $OUT,
# stderr in $ERR; returns the script's status.
gp_detect() {
  local rc=0
  "$GEN" --stdout "$@" "$STUB" >"$OUT" 2>"$ERR" || rc=$?
  return "$rc"
}

# gp_install [FILE] — FILE (default: the golden profile) as the stub's profile.
gp_install() {
  mkdir -p "$STUB/.claude"
  cp "${1:-$GOLDEN}" "$PROFILE"
}

# gp_replace FILE OLD NEW — replace the first OLD in FILE with NEW (OLD must occur).
gp_replace() {
  python3 -I -c '
import sys
path, old, new = sys.argv[1:4]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
if old not in text:
    sys.exit("gp_replace: %r not found in %s" % (old, path))
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text.replace(old, new, 1))
' "$1" "$2" "$3"
}

# gp_items FILE GROUP.KEY — the items of a block list, one per line, with the
# YAML single quotes removed (inner '' undoubled).
gp_items() {
  awk -v group="${2%%.*}" -v name="${2#*.}" '
    /^[^ ]/ { ingroup = ($0 == group ":"); inlist = 0; next }
    ingroup && $0 == "  " name ":" { inlist = 1; next }
    inlist && /^    - / {
      item = substr($0, 7)
      if (item ~ /^\047.*\047$/) {
        item = substr(item, 2, length(item) - 2)
        gsub(/\047\047/, "\047", item)
      }
      print item
      next
    }
    { inlist = 0 }
  ' "$1"
}

# gp_leftovers — temporary profile files left in the stub's .claude/ (none expected).
gp_leftovers() {
  find "$STUB/.claude" -name '.rust-sdlc.yml.*' -print
}

# gp_tree — the stub's tree snapshot (NFR-1): every changed, untracked and
# ignored path against its committed state, one porcelain line each.
gp_tree() {
  git -C "$STUB" status --porcelain --ignored --untracked-files=all
}

# gp_mode FILE — the permission bits of FILE in octal.
gp_mode() {
  python3 -I -c 'import os, stat, sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$1"
}

# gp_inode FILE — the inode number of FILE.
gp_inode() {
  python3 -I -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$1"
}

# gp_nocargo_path — a sandbox PATH with the tools the script needs and no cargo.
gp_nocargo_path() {
  local tools=(bash python3 git docker dirname basename mktemp mv rm mkdir cat chmod tr)
  if type -P yq >/dev/null 2>&1; then
    tools+=(yq)
  fi
  sandbox_path "${tools[@]}"
}

# gp_timeout CMD... — CMD under a 30 s timeout when coreutils timeout exists.
gp_timeout() {
  if type -P timeout >/dev/null 2>&1; then
    timeout 30 "$@"
  else
    "$@"
  fi
}

# gp_workflows_without STEM... — the golden ci.workflows block value without STEM...
gp_workflows_without() {
  local stem skip out=""
  while IFS= read -r stem; do
    for skip in "$@"; do
      [[ "$stem" == "$skip" ]] && continue 2
    done
    out+=$'\n'"    - '$stem'"
  done < <(gp_items "$GOLDEN" ci.workflows)
  printf '%s' "$out"
}

# --- usage (SC-SCRIPT, SC-SUITE) -------------------------------------------------

@test "generate-profile: --help prints the header and exits 0 in any position" {
  run --separate-stderr "$GEN" --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "generate-profile.sh — detect the project profile .claude/rust-sdlc.yml from repository files (FR-6)." ]
  [[ "$output" == *"Usage: $USAGE"* ]]
  [[ "$output" == *"Exit: 0 success (a reported difference keeps the file and still exits 0); 1 refusal"*"; 2 usage error"* ]]
  [ -z "$stderr" ]
  local help="$output"
  run --separate-stderr "$GEN" --refresh "$STUB" --help
  [ "$status" -eq 0 ]
  [ "$output" = "$help" ]
  [ ! -e "$PROFILE" ]
  run --separate-stderr "$GEN" --bogus -- --help
  [ "$status" -eq 0 ]
  [ "$output" = "$help" ]
}

@test "generate-profile: an unknown flag is a usage error (exit 2)" {
  run --separate-stderr "$GEN" --force "$STUB"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] unknown argument: --force (usage: $USAGE)" ]
  [ ! -e "$PROFILE" ]
}

@test "generate-profile: --run-in-container needs true or false (exit 2)" {
  run --separate-stderr "$GEN" "$STUB" --run-in-container
  [ "$status" -eq 2 ]
  [ "$stderr" = "[rust-sdlc][ERROR] --run-in-container needs a value (usage: $USAGE)" ]
  run --separate-stderr "$GEN" --run-in-container --refresh "$STUB"
  [ "$status" -eq 2 ]
  [ "$stderr" = "[rust-sdlc][ERROR] --run-in-container needs a value (usage: $USAGE)" ]
  run --separate-stderr "$GEN" --run-in-container yes "$STUB"
  [ "$status" -eq 2 ]
  [ "$stderr" = "[rust-sdlc][ERROR] --run-in-container takes true or false, not 'yes' (usage: $USAGE)" ]
  [ -z "$output" ]
  [ ! -e "$PROFILE" ]
}

@test "generate-profile: a second TARGET_DIR or an empty one is a usage error, a missing one exits 1" {
  run --separate-stderr "$GEN" "$STUB" "$STUB"
  [ "$status" -eq 2 ]
  [ "$stderr" = "[rust-sdlc][ERROR] unexpected argument: $STUB (usage: $USAGE)" ]
  run --separate-stderr "$GEN" ''
  [ "$status" -eq 2 ]
  [ "$stderr" = "[rust-sdlc][ERROR] TARGET_DIR must not be empty (usage: $USAGE)" ]
  run --separate-stderr "$GEN" "$BATS_TEST_TMPDIR/absent"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] target directory not found: $BATS_TEST_TMPDIR/absent" ]
}

@test "generate-profile: -- ends the options and the next argument is TARGET_DIR" {
  run --separate-stderr "$GEN" --stdout -- "$STUB"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  diff -u -- "$GOLDEN" <(printf '%s\n' "$output")
  [ ! -e "$PROFILE" ]
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr "$GEN" -- --refresh
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] target directory not found: --refresh" ]
  run --separate-stderr "$GEN" -- "$STUB" --stdout
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] unexpected argument: --stdout (usage: $USAGE)" ]
  [ ! -e "$PROFILE" ]
}

# --- first run: the golden profile (AC-6.1, AC-6.2, AC-6.3) ---------------------

@test "generate-profile: golden — the stub without a profile gets golden.yml byte for byte, valid, within 5 s, and no other file" {
  [ ! -e "$PROFILE" ]
  [ -z "$(gp_tree)" ]
  local start=$SECONDS
  run --separate-stderr "$GEN" "$STUB"
  local elapsed=$((SECONDS - start))
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  [ -z "$stderr" ]
  [ "$elapsed" -le 5 ]
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  gp_same "$GOLDEN" "$PROFILE"
  grep -qx '  load_tests: load-tests' "$PROFILE"
  run --separate-stderr "$VALIDATE" "$PROFILE"
  [ "$status" -eq 0 ]
  [ "$output" = "VALID: $PROFILE" ]
  [ -z "$(gp_leftovers)" ]
}

@test "generate-profile: golden — TARGET_DIR defaults to the working directory and .claude/ is created" {
  rm -rf "$STUB/.claude"
  cd "$STUB"
  run --separate-stderr "$GEN"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  [ -z "$stderr" ]
  gp_same "$GOLDEN" "$PROFILE"
}

@test "generate-profile: 0 cargo, make and gh calls; docker info is the only probe; .env.local is never read (AC-6.3)" {
  mkfifo "$STUB/.env.local"
  run --separate-stderr gp_timeout "$GEN" "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_same "$GOLDEN" "$PROFILE"
  [ ! -s "$STUB_CARGO_LOG" ]
  [ ! -s "$STUB_MAKE_LOG" ]
  [ ! -s "$STUB_GH_LOG" ]
  [ "$(cat "$STUB_DOCKER_LOG")" = "docker info" ]
}

@test "generate-profile: golden — --stdout prints the YAML and writes nothing" {
  local before
  rm -rf "$STUB/.claude"
  before="$(gp_tree)"
  gp_detect
  [ ! -s "$ERR" ]
  gp_same "$GOLDEN" "$OUT"
  [ ! -e "$STUB/.claude" ]
  [ "$(gp_tree)" = "$before" ]
}

# --- an existing profile (NFR-3, NFR-1) --------------------------------------------

@test "generate-profile: an identical existing profile prints UNCHANGED, and neither it nor any other file is touched" {
  gp_install
  local before
  before="$(gp_inode "$PROFILE")"
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "UNCHANGED: .claude/rust-sdlc.yml" ]
  [ -z "$stderr" ]
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  [ "$(gp_inode "$PROFILE")" = "$before" ]
  gp_same "$GOLDEN" "$PROFILE"
}

@test "generate-profile: a differing profile prints DIFF and a unified diff, keeps the file, writes no other file and exits 0" {
  gp_expect project.description "'Stale text'" make.complexity null
  gp_install "$EXPECTED"
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  [ "${lines[0]}" = "DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)" ]
  [ "${lines[1]}" = "--- .claude/rust-sdlc.yml" ]
  [ "${lines[2]}" = "+++ detected" ]
  [[ "${lines[3]}" == "@@ "* ]]
  [[ "$output" == *$'\n'"-  description: 'Stale text'"$'\n'"+  description: 'Rust Template'"$'\n'* ]]
  [[ "$output" == *$'\n'"-  complexity: null"$'\n'"+  complexity: complexity"$'\n'* ]]
  gp_same "$EXPECTED" "$PROFILE"
}

@test "generate-profile: --refresh rewrites atomically through mktemp .claude/.rust-sdlc.yml.XXXXXX and mv, and no other file" {
  local wrap="$BATS_TEST_TMPDIR/wrap" tool real before
  mkdir -p "$wrap"
  for tool in mktemp mv; do
    real="$(type -P "$tool")"
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %s "$*" >>"%s"\nexec %s "$@"\n' \
      "$tool" "$BATS_TEST_TMPDIR/wrap.log" "$real" >"$wrap/$tool"
    chmod 755 "$wrap/$tool"
  done
  gp_expect project.description "'Stale text'"
  gp_install "$EXPECTED"
  chmod 640 "$PROFILE"
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  before="$(gp_inode "$PROFILE")"
  PATH="$wrap:$PATH" run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  [ -z "$stderr" ]
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  gp_same "$GOLDEN" "$PROFILE"
  [ "$(gp_inode "$PROFILE")" != "$before" ]
  [ "$(gp_mode "$PROFILE")" = 0o640 ]
  grep -qx 'mktemp .claude/.rust-sdlc.yml.XXXXXX' "$BATS_TEST_TMPDIR/wrap.log"
  grep -qE '^mv -f -- \.claude/\.rust-sdlc\.yml\.[A-Za-z0-9]{6} \.claude/rust-sdlc\.yml$' "$BATS_TEST_TMPDIR/wrap.log"
  [ -z "$(gp_leftovers)" ]
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "UNCHANGED: .claude/rust-sdlc.yml" ]
}

@test "generate-profile: --stdout with an existing profile prints what --refresh would write and keeps the file" {
  gp_expect project.description "'Stale text'" capabilities.dynamic_security_testing true
  gp_install "$EXPECTED"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect capabilities.dynamic_security_testing true
  gp_same "$EXPECTED" "$OUT"
  grep -qx "  description: 'Stale text'" "$PROFILE"
}

@test "generate-profile: a symlinked .claude is refused (exit 1), also with --stdout" {
  rm -rf "$STUB/.claude"
  mkdir "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$STUB/.claude"
  run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] refusing to write .claude/rust-sdlc.yml: .claude is a symbolic link" ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/elsewhere")" ]
  run --separate-stderr "$GEN" --stdout "$STUB"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "generate-profile: a symlinked profile is refused (exit 1) and its target is untouched" {
  printf 'outside\n' >"$BATS_TEST_TMPDIR/outside.yml"
  ln -s "$BATS_TEST_TMPDIR/outside.yml" "$PROFILE"
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] refusing to write .claude/rust-sdlc.yml: it is a symbolic link" ]
  [ "$(cat "$BATS_TEST_TMPDIR/outside.yml")" = outside ]
  [ -L "$PROFILE" ]
}

@test "generate-profile: a non-regular profile (directory, FIFO) is refused (exit 1)" {
  mkdir "$PROFILE"
  run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] refusing to write .claude/rust-sdlc.yml: it is not a regular file" ]
  [ -d "$PROFILE" ]
  rmdir "$PROFILE"
  mkfifo "$PROFILE"
  run --separate-stderr gp_timeout "$GEN" --refresh "$STUB"
  [ "$status" -eq 1 ]
  [ "$stderr" = "[rust-sdlc][ERROR] refusing to write .claude/rust-sdlc.yml: it is not a regular file" ]
  [ -p "$PROFILE" ]
}

@test "generate-profile: a .claude that is not a directory is refused (exit 1), also with --stdout" {
  rm -rf "$STUB/.claude"
  printf 'x\n' >"$STUB/.claude"
  run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] refusing to write .claude/rust-sdlc.yml: .claude is not a directory" ]
  [ "$(cat "$STUB/.claude")" = x ]
  run --separate-stderr "$GEN" --refresh --stdout "$STUB"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] refusing to write .claude/rust-sdlc.yml: .claude is not a directory" ]
  [ -f "$STUB/.claude" ]
  [ "$(cat "$STUB/.claude")" = x ]
}

@test "generate-profile: an unreadable profile or an unwritable .claude/ fails with exit 1" {
  skip_if_root
  gp_install
  chmod 000 "$PROFILE"
  run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = "[rust-sdlc][ERROR] cannot read .claude/rust-sdlc.yml: permission denied" ]
  chmod 644 "$PROFILE"
  rm "$PROFILE"
  chmod 555 "$STUB/.claude"
  run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"[rust-sdlc][ERROR] cannot write .claude/rust-sdlc.yml" ]]
  [ ! -e "$PROFILE" ]
}

# --- ADR-24: user-owned keys (AC-6.6) -------------------------------------------------

@test "generate-profile: ADR-24 capabilities.run_in_container survives --refresh" {
  gp_expect capabilities.run_in_container true project.description "'Stale text'"
  gp_install "$EXPECTED"
  STUB_DOCKER_INFO_EXIT=0 run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_expect capabilities.run_in_container true
  gp_same "$EXPECTED" "$PROFILE"
  [ ! -s "$STUB_DOCKER_LOG" ]
}

@test "generate-profile: ADR-24 capabilities.dynamic_security_testing survives --refresh" {
  gp_expect capabilities.dynamic_security_testing true project.description "'Stale text'"
  gp_install "$EXPECTED"
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_expect capabilities.dynamic_security_testing true
  gp_same "$EXPECTED" "$PROFILE"
}

@test "generate-profile: ADR-24 capabilities.publish_pr_comments survives --refresh" {
  gp_expect capabilities.publish_pr_comments false project.description "'Stale text'"
  gp_install "$EXPECTED"
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_expect capabilities.publish_pr_comments false
  gp_same "$EXPECTED" "$PROFILE"
}

@test "generate-profile: ADR-24 review.reviewers survives --refresh, quoted items written bare" {
  gp_expect review.reviewers $'\n'"    - 'cubic'"$'\n'"    - qodo" project.description "'Stale text'"
  gp_install "$EXPECTED"
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_expect review.reviewers $'\n    - cubic\n    - qodo'
  gp_same "$EXPECTED" "$PROFILE"
  run --separate-stderr "$VALIDATE" "$PROFILE"
  [ "$status" -eq 0 ]
}

@test "generate-profile: ADR-24 review.ai_review_agents survives --refresh, an empty review.reviewers too" {
  gp_expect review.ai_review_agents $'\n    - claude\n    - codex' review.reviewers '[]' \
    project.description "'Stale text'"
  gp_install "$EXPECTED"
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_expect review.ai_review_agents $'\n    - claude\n    - codex' review.reviewers '[]'
  gp_same "$EXPECTED" "$PROFILE"
}

@test "generate-profile: ADR-24 an invalid user-owned value is re-detected on --refresh" {
  gp_expect capabilities.run_in_container "'true'" capabilities.dynamic_security_testing "'yes'" \
    capabilities.publish_pr_comments 1 review.reviewers $'\n    - coderabbit\n    - coderabbit' \
    review.ai_review_agents '[]'
  gp_install "$EXPECTED"
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_same "$GOLDEN" "$PROFILE"
  [ "$(cat "$STUB_DOCKER_LOG")" = "docker info" ]
  gp_expect review.ai_review_agents $'\n    - claude\n    - "true"'
  gp_install "$EXPECTED"
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  gp_same "$GOLDEN" "$PROFILE"
}

@test "generate-profile: ADR-24 a hand-flipped user-owned key without --refresh prints UNCHANGED" {
  gp_expect capabilities.run_in_container true capabilities.dynamic_security_testing true \
    capabilities.publish_pr_comments false review.reviewers $'\n    - sonarcloud' \
    review.ai_review_agents $'\n    - claude\n    - codex'
  gp_install "$EXPECTED"
  run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "UNCHANGED: .claude/rust-sdlc.yml" ]
  [ -z "$stderr" ]
  gp_same "$EXPECTED" "$PROFILE"
}

@test "generate-profile: ADR-24 an existing false plus --run-in-container true without --refresh prints UPDATED, then UNCHANGED, and neither run writes another file" {
  gp_install
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  run --separate-stderr "$GEN" --run-in-container true "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "UPDATED: .claude/rust-sdlc.yml (capabilities.run_in_container=true)" ]
  [ -z "$stderr" ]
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
  gp_expect capabilities.run_in_container true
  gp_same "$EXPECTED" "$PROFILE"
  run --separate-stderr "$GEN" --run-in-container true "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "UNCHANGED: .claude/rust-sdlc.yml" ]
  [ "$(gp_tree)" = "?? .claude/rust-sdlc.yml" ]
}

@test "generate-profile: ADR-24 --run-in-container without --refresh rewrites only that key; other drift stays a DIFF" {
  gp_expect project.description "'Stale text'"
  gp_install "$EXPECTED"
  run --separate-stderr "$GEN" --run-in-container true "$STUB"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "UPDATED: .claude/rust-sdlc.yml (capabilities.run_in_container=true)" ]
  [ "${lines[1]}" = "DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)" ]
  [[ "$output" == *$'\n'"-  description: 'Stale text'"$'\n'* ]]
  [[ "$output" != *run_in_container:* ]]
  gp_expect project.description "'Stale text'" capabilities.run_in_container true
  gp_same "$EXPECTED" "$PROFILE"
  run --separate-stderr "$GEN" --run-in-container true "$STUB"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)" ]
  gp_same "$EXPECTED" "$PROFILE"
}

@test "generate-profile: --run-in-container wins over detection and over the existing value (AC-6.6)" {
  gp_detect --run-in-container true
  gp_expect capabilities.run_in_container true
  gp_same "$EXPECTED" "$OUT"
  [ ! -s "$STUB_DOCKER_LOG" ]
  gp_install "$EXPECTED"
  STUB_DOCKER_INFO_EXIT=0 run --separate-stderr "$GEN" --refresh --run-in-container false "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_same "$GOLDEN" "$PROFILE"
}

@test "generate-profile: an existing false survives --refresh with Docker reachable and no cargo (AC-6.6)" {
  local sb
  sb="$(gp_nocargo_path)"
  gp_expect project.description "'Stale text'"
  gp_install "$EXPECTED"
  STUB_DOCKER_INFO_EXIT=0 env PATH="$sb" "$GEN" --refresh "$STUB" >"$OUT" 2>"$ERR"
  [ "$(cat "$OUT")" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_same "$GOLDEN" "$PROFILE"
  [ ! -s "$STUB_DOCKER_LOG" ]
}

@test "generate-profile: detection — Docker reachable and no cargo gives run_in_container true (AC-6.6)" {
  local sb
  sb="$(gp_nocargo_path)"
  STUB_DOCKER_INFO_EXIT=0 env PATH="$sb" "$GEN" --stdout "$STUB" >"$OUT" 2>"$ERR"
  gp_expect capabilities.run_in_container true
  gp_same "$EXPECTED" "$OUT"
  [ "$(cat "$STUB_DOCKER_LOG")" = "docker info" ]
}

@test "generate-profile: detection — Docker reachable with cargo gives run_in_container false (AC-6.6)" {
  STUB_DOCKER_INFO_EXIT=0 gp_detect
  gp_same "$GOLDEN" "$OUT"
  [ "$(cat "$STUB_DOCKER_LOG")" = "docker info" ]
  [ ! -s "$STUB_CARGO_LOG" ]
}

@test "generate-profile: detection — Docker unreachable and no cargo gives run_in_container false (AC-6.6)" {
  local sb
  sb="$(gp_nocargo_path)"
  STUB_DOCKER_INFO_EXIT=1 env PATH="$sb" "$GEN" --stdout "$STUB" >"$OUT" 2>"$ERR"
  gp_same "$GOLDEN" "$OUT"
  [ "$(cat "$STUB_DOCKER_LOG")" = "docker info" ]
}

@test "generate-profile: detection — Docker unreachable with cargo gives run_in_container false (AC-6.6)" {
  STUB_DOCKER_INFO_EXIT=1 gp_detect
  gp_same "$GOLDEN" "$OUT"
  [ "$(cat "$STUB_DOCKER_LOG")" = "docker info" ]
}

# --- one optional source missing per case (AC-6.1, D20, ADR-17) ---------------------

@test "generate-profile: fallback — no .coderabbit.yaml" {
  rm "$STUB/.coderabbit.yaml"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect review.coderabbit false review.reviewers '[]' review.request_changes_blocking false
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — no workspace.dsl" {
  rm "$STUB/workspace.dsl"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect capabilities.structurizr false capabilities.template_derived false
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — no tests/Load/" {
  rm -rf "$STUB/tests/Load"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect capabilities.load_testing false
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — no .sqlx/" {
  rm -rf "$STUB/.sqlx"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect persistence.offline_metadata false
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — no migrations/" {
  rm -rf "$STUB/migrations"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect persistence.migrations_dir null
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — no OpenAPI snapshot" {
  rm "$STUB/.github/openapi-spec/spec.yaml"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect service.openapi_snapshot null
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — no GraphQL snapshot" {
  rm "$STUB/.github/graphql-spec/spec"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect service.graphql_snapshot null
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — no docs/repository-settings.md" {
  rm "$STUB/docs/repository-settings.md"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect ci.required_checks '[]' ci.human_gated '[]'
  gp_same "$EXPECTED" "$OUT"
  "$GEN" "$STUB" >/dev/null
  run --separate-stderr "$VALIDATE" "$PROFILE"
  [ "$status" -eq 0 ]
}

@test "generate-profile: fallback — no rust-toolchain.toml" {
  rm "$STUB/rust-toolchain.toml"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect rust.toolchain null capabilities.template_derived false
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — no .env gives port 8081 even when .env.local names another" {
  rm "$STUB/.env"
  printf 'APP_PORT=9999\n' >"$STUB/.env.local"
  gp_detect
  [ ! -s "$ERR" ]
  gp_same "$GOLDEN" "$OUT"
  printf 'APP_PORT=7000\nAPP_PORT=7001\n' >"$STUB/.env"
  gp_detect
  gp_expect service.port 7000 service.base_url "'http://localhost:7000'"
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: .env APP_PORT in the dotenv forms the template's with-env.sh reads" {
  printf '# host port\nexport APP_PORT = "7002" # published by compose\n' >"$STUB/.env"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect service.port 7002 service.base_url "'http://localhost:7002'"
  gp_same "$EXPECTED" "$OUT"
  printf "APP_PORT='7003'\r\n" >"$STUB/.env"
  gp_detect
  gp_expect service.port 7003 service.base_url "'http://localhost:7003'"
  gp_same "$EXPECTED" "$OUT"
  printf 'APP_PORT=7004#no space before the hash\n' >"$STUB/.env"
  gp_detect
  gp_same "$GOLDEN" "$OUT"
}

@test "generate-profile: fallback — no sync workflows; one sync workflow gives its flavour" {
  rm "$STUB/.github/workflows/template-sync-app.yml" "$STUB/.github/workflows/template-sync-pat.yml"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect template.repository null template.sync_flavour none capabilities.template_sync false \
    ci.workflows "$(gp_workflows_without template-sync-app template-sync-pat)"
  gp_same "$EXPECTED" "$OUT"
  rr_materialize "$BATS_TEST_TMPDIR/pat/billing-service"
  STUB="$BATS_TEST_TMPDIR/pat/billing-service"
  rm "$STUB/.github/workflows/template-sync-app.yml"
  gp_detect
  gp_expect template.sync_flavour pat ci.workflows "$(gp_workflows_without template-sync-app)"
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — one A1 marker missing, or CI_PREFLIGHT_TARGETS not led by validate-configuration (ADR-17)" {
  rm "$STUB/xtask/Cargo.toml"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect capabilities.template_derived false
  gp_same "$EXPECTED" "$OUT"
  cp "$FIXTURE_REPO/xtask/Cargo.toml" "$STUB/xtask/Cargo.toml"
  gp_replace "$STUB/Makefile" 'CI_PREFLIGHT_TARGETS := validate-configuration validate-invariants' \
    'CI_PREFLIGHT_TARGETS := validate-invariants validate-configuration'
  gp_detect
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: fallback — outside a git work tree project.repo is null and publishing is off" {
  rm -rf "$STUB/.git"
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect project.repo null capabilities.publish_pr_comments false
  gp_same "$EXPECTED" "$OUT"
  [ ! -s "$STUB_GH_LOG" ]
}

@test "generate-profile: the origin/HEAD target is the default branch; a non-github origin gives no repo" {
  git -C "$STUB" update-ref refs/remotes/origin/develop HEAD
  git -C "$STUB" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
  gp_detect
  gp_expect project.default_branch "'develop'" ci.base_ref "'origin/develop'"
  gp_same "$EXPECTED" "$OUT"
  git -C "$STUB" remote set-url origin git@github.com:acme/billing-service.git
  gp_detect
  gp_same "$EXPECTED" "$OUT"
  git -C "$STUB" remote set-url origin https://gitlab.example.invalid/acme/billing-service.git
  gp_detect
  gp_expect project.default_branch "'develop'" ci.base_ref "'origin/develop'" project.repo null \
    capabilities.publish_pr_comments false
  gp_same "$EXPECTED" "$OUT"
  [ ! -s "$STUB_GH_LOG" ]
}

@test "generate-profile: template.source_commit comes from the newest import commit subject" {
  git -C "$STUB" commit -q --allow-empty -m 'chore(#3): import template acme/rust-template at 1111111'
  git -C "$STUB" commit -q --allow-empty -m 'chore(#9): import template acme/rust-template at abcdef0123'
  git -C "$STUB" commit -q --allow-empty -m 'chore(#10): import template at nothing'
  gp_detect
  gp_expect template.source_commit "'abcdef0123'"
  gp_same "$EXPECTED" "$OUT"
}

@test "generate-profile: an unparseable source warns and its keys fall back, exit 0" {
  printf '[toolchain\nchannel = \n' >"$STUB/rust-toolchain.toml"
  printf 'reviews: [unclosed\n' >"$STUB/.coderabbit.yaml"
  gp_detect
  grep -q '^\[rust-sdlc\]\[WARN\] rust-toolchain.toml is not parseable TOML (.*); the keys it feeds take their fallback$' "$ERR"
  grep -qx '\[rust-sdlc\]\[WARN\] .coderabbit.yaml is not parseable YAML; review.request_changes_blocking falls back to false' "$ERR"
  gp_expect rust.toolchain null review.request_changes_blocking false
  gp_same "$EXPECTED" "$OUT"
  printf 'project: [unclosed\n' >"$BATS_TEST_TMPDIR/broken.yml"
  gp_install "$BATS_TEST_TMPDIR/broken.yml"
  run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  [[ "$stderr" == *"[rust-sdlc][WARN] .claude/rust-sdlc.yml is not parseable YAML; its user-owned keys take their detected values"* ]]
  gp_same "$EXPECTED" "$PROFILE"
}

@test "generate-profile: an unreadable make/ or .github/workflows/ warns and its keys fall back, exit 0" {
  skip_if_root
  chmod 000 "$STUB/make" "$STUB/.github/workflows"
  gp_detect
  grep -q '^\[rust-sdlc\]\[WARN\] make is not readable (.*); the keys it feeds take their fallback$' "$ERR"
  grep -q '^\[rust-sdlc\]\[WARN\] .github/workflows is not readable (.*); the keys it feeds take their fallback$' "$ERR"
  grep -qx '  load_tests: null' "$OUT"
  grep -qx '  provider: null' "$OUT"
  grep -qx '  ci: ci' "$OUT"
}

# --- ci.* derivation (AC-6.5) ---------------------------------------------------------------

@test "generate-profile: ci.required_checks is every Required yes check name in document order, no other row" {
  gp_detect
  local want
  want="$(awk -F'|' '
    /^## / { section = $0 }
    section == "## Required status checks" && NF == 6 {
      name = $3; required = $5
      gsub(/^ +| +$/, "", name); gsub(/^ +| +$/, "", required)
      if (required == "yes") print name
    }' "$STUB/docs/repository-settings.md")"
  [ "$(printf '%s\n' "$want" | wc -l)" -eq 36 ]
  [ "$(gp_items "$OUT" ci.required_checks)" = "$want" ]
  local absent
  for absent in 'Mutation shard k/n' 'Bats: group' 'CodeQL' 'Mutation plan' 'Static-analysis findings upload'; do
    [ "$(grep -cF -- "$absent" "$OUT" || true)" = 0 ]
  done
}

@test "generate-profile: ci.human_gated is exactly the three label-gated check names, each required" {
  gp_detect
  [ "$(gp_items "$OUT" ci.human_gated)" = $'Protected configuration\nOpenAPI breaking changes\nGraphQL breaking changes' ]
  local check
  while IFS= read -r check; do
    gp_items "$OUT" ci.required_checks | grep -qxF -- "$check"
  done < <(gp_items "$OUT" ci.human_gated)
}

@test "generate-profile: docs/repository-settings-service.md adds exactly its one required check" {
  cp "$VARIANTS/repository-settings-service.md.tpl" "$STUB/docs/repository-settings-service.md"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect
  gp_replace "$EXPECTED" "    - 'Architecture model'"$'\n' \
    "    - 'Architecture model'"$'\n'"    - 'Invoice end-to-end tests'"$'\n'
  gp_same "$EXPECTED" "$OUT"
  [ "$(gp_items "$OUT" ci.required_checks | wc -l)" -eq "$(($(gp_items "$GOLDEN" ci.required_checks | wc -l) + 1))" ]
}

@test "generate-profile: check names with spaces are single-quoted list items" {
  gp_detect
  grep -qx "    - 'Changes (Quality)'" "$OUT"
  grep -qx "    - 'Makefile tests (Bats)'" "$OUT"
  local item
  while IFS= read -r item; do
    [[ "$item" =~ ^\ \ \ \ -\ \'[^\']+\'$ ]]
  done < <(awk '/^  (required_checks|human_gated):$/ { on = 1; next } /^  [a-z]/ { on = 0 } on' "$OUT")
}

@test "generate-profile: an unmapped human-gated job id warns on stderr and is dropped" {
  local docs="$STUB/docs/repository-settings.md" tick='`'
  gp_replace "$docs" "without it the job ${tick}validate-configuration${tick} fails" \
    "without it the job ${tick}config-guard${tick} fails"
  gp_detect
  grep -q "^\[rust-sdlc\]\[WARN\] .*'config-guard'" "$ERR"
  gp_expect ci.human_gated $'\n'"    - 'OpenAPI breaking changes'"$'\n'"    - 'GraphQL breaking changes'"
  gp_same "$EXPECTED" "$OUT"
  gp_replace "$docs" "without it the job ${tick}config-guard${tick} fails" \
    "without it the job ${tick}codeql${tick} fails"
  gp_detect
  grep -qx "\[rust-sdlc\]\[WARN\] human-gated check 'CodeQL' is not a required check of the repository-settings tables; ci.human_gated drops it" "$ERR"
  gp_same "$EXPECTED" "$OUT"
}

# --- contexts, make map, quality bars (AC-6.7) ------------------------------------------------

@test "generate-profile: bounded contexts are the members' <group>/<context>, never shared/* (AC-6.7)" {
  gp_detect
  [ "$(gp_items "$OUT" architecture.bounded_contexts)" = $'billing/invoice\ninternal/health-check' ]
  gp_replace "$STUB/Cargo.toml" $'    "xtask",\n]' \
    $'    "xtask",\n    "crates/billing/payment/domain",\n    "crates/shared/extra/domain",\n]'
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect architecture.bounded_contexts \
    $'\n'"    - 'billing/invoice'"$'\n'"    - 'internal/health-check'"$'\n'"    - 'billing/payment'" \
    architecture.shared_crates \
    $'\n'"    - 'crates/shared/application'"$'\n'"    - 'crates/shared/domain'"$'\n'"    - 'crates/shared/infrastructure'"$'\n'"    - 'crates/shared/extra/domain'"
  gp_same "$EXPECTED" "$OUT"
  [ -z "$(gp_items "$OUT" architecture.bounded_contexts | grep '^shared/' || true)" ]
}

@test "generate-profile: a parseable architecture.toml whose layer is not a list gives architecture.layers [] and nothing else moves" {
  local value
  for value in '5' 'true' '"domain"' '{ name = "domain" }'; do
    printf 'layer = %s\n' "$value" >"$STUB/architecture.toml"
    gp_detect
    [ ! -s "$ERR" ]
    gp_expect architecture.layers '[]'
    gp_same "$EXPECTED" "$OUT"
  done
}

@test "generate-profile: a SUBST target appended to make/service.mk maps its key; undocumented rules and assignments do not" {
  printf '\nfr-nfr-gate: ## Run the service FR/NFR gate\n\t@true\npr-comments:\n\t@true\nai-review-loop := not-a-rule ## a variable\n' \
    >>"$STUB/make/service.mk"
  gp_detect
  [ ! -s "$ERR" ]
  gp_expect make.fr_nfr_gate fr-nfr-gate
  gp_same "$EXPECTED" "$OUT"
  "$GEN" "$STUB" >/dev/null
  run --separate-stderr "$VALIDATE" "$PROFILE"
  [ "$status" -eq 0 ]
}

@test "generate-profile: a looser clippy.toml threshold warns and the profile keeps 0" {
  gp_replace "$STUB/clippy.toml" 'cognitive-complexity-threshold = 8' 'cognitive-complexity-threshold = 12'
  gp_replace "$STUB/clippy.toml" 'too-many-lines-threshold = 50' 'too-many-lines-threshold = 40'
  gp_detect
  [ "$(cat "$ERR")" = "[rust-sdlc][WARN] clippy.toml cognitive-complexity-threshold is looser than the template value 8; the profile keeps 0" ]
  gp_same "$GOLDEN" "$OUT"
}

@test "generate-profile: a looser COVERAGE_GATE_CMD floor warns and the profile keeps 100" {
  gp_replace "$STUB/make/gates.mk" '--fail-under-lines 100' '--fail-under-lines 90'
  gp_detect
  [ "$(cat "$ERR")" = "[rust-sdlc][WARN] make/gates.mk COVERAGE_GATE_CMD --fail-under-lines is looser than the template value 100; the profile keeps 100" ]
  gp_same "$GOLDEN" "$OUT"
  grep -qx '  coverage_lines: 100' "$OUT"
}

@test "generate-profile: looser SPECTRAL_FLAGS, OASDIFF_FLAGS and TRIVY_FLAGS severities warn; the bars stay 0" {
  gp_replace "$STUB/make/gates.mk" '--fail-severity=hint' '--fail-severity=warn'
  gp_replace "$STUB/make/gates.mk" 'OASDIFF_FLAGS = --fail-on ERR' 'OASDIFF_FLAGS = --format text'
  gp_replace "$STUB/make/gates.mk" '--severity HIGH,CRITICAL' '--severity CRITICAL'
  gp_detect
  [ "$(cat "$ERR")" = "[rust-sdlc][WARN] make/gates.mk SPECTRAL_FLAGS --fail-severity is looser than the template value hint; the profile keeps 0
[rust-sdlc][WARN] make/gates.mk OASDIFF_FLAGS --fail-on is looser than the template value ERR; the profile keeps 0
[rust-sdlc][WARN] make/gates.mk TRIVY_FLAGS --severity is looser than the template value HIGH,CRITICAL; the profile keeps 0" ]
  gp_same "$GOLDEN" "$OUT"
}

# --- K7: the template's linters on the output (AC-6.2) -------------------------------------------

@test "generate-profile: K7 the output is yamllint-clean with the fixture's .yamllint.yml" {
  k7_require yamllint
  "$GEN" "$STUB" >/dev/null
  run yamllint --strict -c "$FIXTURE_REPO/.yamllint.yml" "$PROFILE"
  [ "$status" -eq 0 ]
  rm "$STUB/docs/repository-settings.md" "$STUB/.coderabbit.yaml"
  gp_detect
  run yamllint --strict -c "$FIXTURE_REPO/.yamllint.yml" "$OUT"
  [ "$status" -eq 0 ]
}

@test "generate-profile: K7 the output is Prettier-clean with the fixture's .prettierrc.yml" {
  k7_require prettier
  mkdir -p "$BATS_TEST_TMPDIR/k7"
  "$GEN" "$STUB" >/dev/null
  cp "$PROFILE" "$BATS_TEST_TMPDIR/k7/rust-sdlc.yml"
  rm "$STUB/docs/repository-settings.md" "$STUB/.coderabbit.yaml"
  gp_detect
  cp "$OUT" "$BATS_TEST_TMPDIR/k7/fallbacks.yml"
  cd "$BATS_TEST_TMPDIR/k7"
  run prettier --config "$FIXTURE_REPO/.prettierrc.yml" --check rust-sdlc.yml fallbacks.yml
  [ "$status" -eq 0 ]
}

# --- parity: SDLC_FORCE_PYTHON_YAML=1 (AC-6.3) ------------------------------------------------------

@test "generate-profile: parity golden — SDLC_FORCE_PYTHON_YAML=1 writes the same golden profile" {
  SDLC_FORCE_PYTHON_YAML=1 run --separate-stderr "$GEN" "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  [ -z "$stderr" ]
  gp_same "$GOLDEN" "$PROFILE"
}

@test "generate-profile: parity — the user-owned keys survive --refresh under SDLC_FORCE_PYTHON_YAML=1" {
  gp_expect capabilities.run_in_container true review.reviewers $'\n    - qlty' project.description "'Stale text'"
  gp_install "$EXPECTED"
  "$GEN" --stdout "$STUB" >"$BATS_TEST_TMPDIR/default.yml"
  SDLC_FORCE_PYTHON_YAML=1 run --separate-stderr "$GEN" --refresh "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  gp_expect capabilities.run_in_container true review.reviewers $'\n    - qlty'
  gp_same "$EXPECTED" "$PROFILE"
  gp_same "$BATS_TEST_TMPDIR/default.yml" "$PROFILE"
}

@test "generate-profile: parity — .coderabbit.yaml and the UPDATED path read the same under SDLC_FORCE_PYTHON_YAML=1" {
  printf 'reviews:\n  request_changes_workflow: false\n' >"$STUB/.coderabbit.yaml"
  "$GEN" --stdout "$STUB" >"$BATS_TEST_TMPDIR/default.yml"
  SDLC_FORCE_PYTHON_YAML=1 "$GEN" --stdout "$STUB" >"$OUT"
  gp_expect review.request_changes_blocking false
  gp_same "$EXPECTED" "$OUT"
  gp_same "$BATS_TEST_TMPDIR/default.yml" "$OUT"
  gp_install "$EXPECTED"
  SDLC_FORCE_PYTHON_YAML=1 run --separate-stderr "$GEN" --run-in-container true "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = "UPDATED: .claude/rust-sdlc.yml (capabilities.run_in_container=true)" ]
  gp_expect review.request_changes_blocking false capabilities.run_in_container true
  gp_same "$EXPECTED" "$PROFILE"
}
