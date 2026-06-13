#!/usr/bin/env bash
# inject-governance.sh — maintain the plugin's managed governance block
# in the target repository's CLAUDE.md and AGENTS.md (FR-2, ADR-3).
#
# Usage: inject-governance.sh [--diff] [TARGET_DIR]
#   TARGET_DIR defaults to $PWD. --diff previews changes without writing.
#
# The block between '<!-- php-backend-sdlc:begin -->' and
# '<!-- php-backend-sdlc:end -->' is replaced in place on every run;
# content outside the markers is never touched (NFR-3). A missing file
# is created holding only the block. Corrupted marker states are
# repaired to exactly one block: well-ordered duplicate pairs collapse
# into the first block's position; unbalanced or out-of-order markers
# (orphans, an END before its BEGIN) have only the marker lines removed
# — surrounding user content is preserved — and a fresh block is
# appended.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DIFF_ONLY=0
TARGET="$PWD"
for arg in "$@"; do
  case "$arg" in
    --diff) DIFF_ONLY=1 ;;
    -*) die "unknown argument: $arg (usage: inject-governance.sh [--diff] [TARGET_DIR])" ;;
    *) TARGET="$arg" ;;
  esac
done
[[ -d "$TARGET" ]] || die "target directory not found: $TARGET"

BEGIN_MARKER='<!-- php-backend-sdlc:begin -->'
END_MARKER='<!-- php-backend-sdlc:end -->'

# The governance block references profile keys instead of hardcoding
# values, so the block stays byte-stable across profile edits (NFR-3).
block_file="$(mktemp)"
new_file="$(mktemp)"
snap_file="$(mktemp)"
out_file=""
trap 'rm -f "$block_file" "$new_file" "$snap_file" ${out_file:+"$out_file"}' EXIT
cat >"$block_file" <<BLOCK
$BEGIN_MARKER
## php-backend-sdlc governance (managed block — do not edit between markers)

### Skill-triage gate

Before review or implementation work, every skill shipped by the
php-backend-sdlc plugin receives a recorded verdict: EXECUTE (with
evidence) or NOT-APPLICABLE (with a reason). Verdicts are formed from
skill frontmatter and the decision guide only; full skill bodies are
loaded solely on EXECUTE.

### Protected quality thresholds

Quality gates live in \`.claude/php-sdlc.yml\` under \`quality.*\` and are
raise-only: score thresholds (phpinsights, infection MSI) may be raised
above the shipped defaults, and the deptrac/psalm violation ceilings stay
at 0. Never lower them — \`validate-profile.sh\` rejects lowered values.

### Container-only execution

Run all build, test, and quality commands inside the project containers
through the make targets mapped in \`.claude/php-sdlc.yml\` (\`make.*\`).
Never invoke composer, php, or test runners directly on the host.
$END_MARKER
BLOCK

# Marker matching tolerates a trailing CR everywhere (the awk norm()
# helpers below): a Windows-edited CLAUDE.md carries CRLF endings, and an
# exact-line match would treat its block as absent — every run would then
# append a fresh duplicate while keeping the stale CRLF copy forever
# (NFR-3 violation). The replacement block is always written with LF;
# user content outside the markers keeps its original line endings.
#
# Marker matching is also fence-aware: a marker line that sits INSIDE a
# fenced code block (``` or ~~~) is documentation, not a real marker, so it
# is treated as ordinary user content — the same way E08 treats indented
# (non-whole-line) markers. Without this, a CLAUDE.md that DOCUMENTS the
# governance markers inside a code fence would have its example clobbered
# and the real block spliced into the fence (FR-2 user-content loss). The
# shared awk prelude below (norm + fence tracking) is reused verbatim by
# every pass so counting, pairing, and the two rewrites agree on exactly
# which lines are real markers.
#
# Fence suppression is gated on FENCE_AWARE, set by fence_balance() below to
# 1 only when the file's fence lines are BALANCED (an even count, every
# opener closed). An UNCLOSED fence must not enable suppression: a stateful
# toggle would stay "inside the fence" through EOF and swallow the real
# managed block we append at the end, so the next run would no longer see
# that block and would append ANOTHER — a duplicate-block / non-idempotent
# regression (NFR-3). With an odd fence count we fall back to plain
# whole-line marker matching (the pre-fence behaviour), which is safe and
# idempotent; the documented-example case (Bug 4) always has a balanced
# ``` pair, so it still gets the protection.
AWK_FENCE_PRELUDE='
  function norm(l) { sub(/\r$/, "", l); return l }
  # A fence opener/closer is a line whose only content (after CR strip and
  # leading-space trim) is 3+ backticks or tildes, optionally followed by an
  # info string (for an opener). Toggling on every such line treats marker
  # lines between an open and close fence as plain content. When
  # fence_aware is 0 the toggle is a no-op so every pass matches markers
  # by whole line regardless of fences.
  function fence_toggle(l,   t) {
    if (!fence_aware) return 0
    t = norm(l); sub(/^[ \t]+/, "", t)
    if (t ~ /^(```+|~~~+)/) { infence = !infence; return 1 }
    return 0
  }
'

# fence_balance FILE — print 1 when the file has an even number of fenced
# code-block delimiter lines (``` or ~~~ at column 0 after trim), else 0.
# Only a balanced count is safe for fence-aware marker suppression.
fence_balance() {
  awk '
    { t = $0; sub(/\r$/, "", t); sub(/^[ \t]+/, "", t)
      if (t ~ /^(```+|~~~+)/) n++ }
    END { print (n % 2 == 0) ? 1 : 0 }
  ' "$1"
}

# count_marker_lines FILE MARKER FENCE_AWARE — number of WHOLE-LINE markers
# equal to MARKER outside any code fence (CR-tolerant). Fenced marker
# examples are documentation and are not counted when FENCE_AWARE is 1.
count_marker_lines() {
  awk -v m="$2" -v fence_aware="${3:-0}" "$AWK_FENCE_PRELUDE"'
    { if (fence_toggle($0)) next; if (!infence && norm($0) == m) n++ }
    END { print n + 0 }
  ' "$1"
}

# markers_paired FILE FENCE_AWARE — success only when every BEGIN is closed
# by an END before the next BEGIN or EOF. Counts alone cannot catch an END
# that precedes its BEGIN: that state is count-balanced, but the replacement
# awk below would treat BEGIN..EOF as the managed region and swallow all
# user content after it. Markers inside a fence are ignored (documentation)
# when FENCE_AWARE is 1.
markers_paired() {
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v fence_aware="${2:-0}" "$AWK_FENCE_PRELUDE"'
    { if (fence_toggle($0)) next }
    !infence && norm($0) == begin { if (inblock) bad = 1; inblock = 1; next }
    !infence && norm($0) == end   { if (!inblock) bad = 1; inblock = 0; next }
    END { exit (bad || inblock) ? 1 : 0 }
  ' "$1"
}

# reject_symlink FILE — refuse to read/write through a symlink. A managed
# file that is a symlink would let `cat ... >"$file"` rewrite the link's
# target, which can be anywhere on disk (outside the target repo). The
# threat model runs this tool against untrusted cloned repos, so a planted
# `CLAUDE.md -> ~/.bashrc` (or any user-writable file) must be refused,
# not followed (NFR-3: content outside the target is never touched).
reject_symlink() {
  local file=$1
  if [[ -L "$file" ]]; then
    die "refusing to follow symlink: $file (managed governance files must be regular files inside the target repo)"
  fi
}

# reject_irregular FILE — refuse a path that exists but is NOT a regular
# file (a directory, FIFO, socket, device node). render_managed below
# decides "create vs update" on `[[ ! -f ]]`, which is also false for
# every non-regular type, so without this guard such a path is treated as
# "missing": write_managed's `mv -f "$temp" "$file"` then either drops the
# temp file INSIDE a directory CLAUDE.md (no governance written, random
# temp litter accumulates each run) or clobbers a FIFO into a regular file
# — all with exit 0 on a broken state. The managed file must be a regular
# file (round-1 N07: writing over a directory must fail non-zero).
reject_irregular() {
  local file=$1
  if [[ -e "$file" && ! -f "$file" ]]; then
    die "refusing to write managed governance: $file exists but is not a regular file (expected a regular CLAUDE.md/AGENTS.md inside the target repo)"
  fi
}

# render_managed FILE -> writes the post-injection content to $new_file
# and sets file_exists=0/1. FILE is read exactly ONCE, into $snap_file;
# marker counts, pairing, the rewrite, and the caller's diff all work on
# that snapshot. Re-reading the live file between those steps let a
# concurrent run swap the content mid-render, producing duplicated or
# interleaved governance blocks from a torn view.
file_exists=0
render_managed() {
  local file=$1
  reject_symlink "$file"
  reject_irregular "$file"
  if [[ ! -f "$file" ]]; then
    file_exists=0
    cat "$block_file" >"$new_file"
    return 0
  fi
  file_exists=1
  cat "$file" >"$snap_file"
  # Compute fence balance ONCE from the snapshot and thread the same value
  # through every pass, so counting, pairing, and the rewrites all agree on
  # whether fence suppression is active (an odd/unclosed-fence file disables
  # it and falls back to whole-line matching — see fence_balance()).
  local fence_aware begins ends
  fence_aware="$(fence_balance "$snap_file")"
  begins="$(count_marker_lines "$snap_file" "$BEGIN_MARKER" "$fence_aware")"
  ends="$(count_marker_lines "$snap_file" "$END_MARKER" "$fence_aware")"
  if [[ "$begins" == "$ends" && "$begins" -gt 0 ]] && markers_paired "$snap_file" "$fence_aware"; then
    # Balanced markers: drop every managed region, leave a placeholder at
    # the first region's position, then splice the fresh block there.
    # Fence-aware so a documented marker inside a code fence is left as
    # content and never opens a managed region (FR-2).
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v fence_aware="$fence_aware" "$AWK_FENCE_PRELUDE"'
      fence_toggle($0) { print; next }
      !infence && norm($0) == begin && !inblock { inblock = 1; if (!placed) { print "\x01MANAGED-BLOCK\x01"; placed = 1 }; next }
      inblock { if (!infence && norm($0) == end) inblock = 0; next }
      { print }
    ' "$snap_file" | awk -v blockfile="$block_file" '
      $0 == "\x01MANAGED-BLOCK\x01" {
        while ((getline line < blockfile) > 0) print line
        close(blockfile)
        next
      }
      { print }
    ' >"$new_file"
  elif [[ "$begins" -eq 0 && "$ends" -eq 0 ]]; then
    # No block yet: append after a blank separator line.
    cat "$snap_file" >"$new_file"
    if [[ -s "$snap_file" && -n "$(tail -c 1 "$snap_file")" ]]; then
      printf '\n' >>"$new_file"  # file lacked trailing newline
    fi
    printf '\n' >>"$new_file"
    cat "$block_file" >>"$new_file"
  else
    # Unbalanced/orphaned/out-of-order markers: removing a begin..EOF
    # span could swallow user content, so drop ONLY the marker lines and
    # append one fresh block at the end. Fence-aware: a documented marker
    # inside a code fence is content, not an orphan marker to strip (FR-2).
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v fence_aware="$fence_aware" "$AWK_FENCE_PRELUDE"'
      fence_toggle($0) { print; next }
      !infence && (norm($0) == begin || norm($0) == end) { next }
      { print }
    ' "$snap_file" >"$new_file"
    printf '\n' >>"$new_file"
    cat "$block_file" >>"$new_file"
  fi
}

# write_managed FILE — replace FILE with $new_file ATOMICALLY: write a
# temp file in the target directory, then mv it into place (mirrors
# generate-profile.sh). The previous truncate-and-rewrite (`cat >FILE`)
# opened a window where a concurrent run read a half-written file and
# appended duplicate/interleaved blocks — or lost user content outside
# the markers entirely. With mv, every version a reader can open is
# complete, so parallel runs serialize to a well-formed last-writer-wins
# state (NFR-3). chmod keeps the existing file's mode on overwrite and
# derives the create mode from the umask (mktemp's 0600 would clobber
# both).
write_managed() {
  local file=$1 mode
  # Refuse to rewrite a managed file the user marked read-only (round-1
  # N04). mv -f replaces by rename, which needs write permission on the
  # DIRECTORY only — not the file — so a 0444 CLAUDE.md would otherwise be
  # silently overwritten with the governance block and exit 0, changing the
  # contract from "refuse" to "silent overwrite of a file the user locked".
  # Check before creating the temp file so a refusal leaves no litter.
  if [[ -e "$file" && ! -w "$file" ]]; then
    die "refusing to overwrite read-only file: $file (it needs a managed-block update but is not writable; chmod +w it or remove it to regenerate)"
  fi
  out_file="$(mktemp "$TARGET/.sdlc-governance.XXXXXX")" \
    || die "cannot create temp file in $TARGET"
  cat "$new_file" >"$out_file"
  if [[ -f "$file" ]]; then
    chmod --reference="$file" "$out_file" 2>/dev/null || true
  else
    printf -v mode '%o' "$(( 0666 & ~0$(umask) ))"
    chmod "$mode" "$out_file" 2>/dev/null || true
  fi
  mv -f "$out_file" "$file"
  out_file=""
}

overall_changed=0
for name in CLAUDE.md AGENTS.md; do
  file="$TARGET/$name"
  render_managed "$file"
  if (( file_exists )) && diff -q "$snap_file" "$new_file" >/dev/null 2>&1; then
    log_info "$name: unchanged"
    continue
  fi
  if (( DIFF_ONLY )); then
    overall_changed=1
    log_info "$name: pending changes (--diff preview, file not written)"
    if (( file_exists )); then
      diff -u --label "$file" --label "$file (pending)" "$snap_file" "$new_file" || true
    else
      log_info "$name does not exist; it would be created with the managed block"
    fi
    continue
  fi
  overall_changed=1
  write_managed "$file"
  log_info "$name: managed block written"
done

if (( ! overall_changed )); then
  log_info "governance blocks already up to date"
fi
