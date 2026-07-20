#!/usr/bin/env bash
# inject-governance.sh — maintain the plugin's managed governance block
# in the target repository's CLAUDE.md and AGENTS.md (FR-2, ADR-3).
#
# Usage: inject-governance.sh [--diff] [TARGET_DIR]
#   TARGET_DIR defaults to $PWD. --diff previews changes without writing.
#
# The block between '<!-- react-frontend-sdlc:begin -->' and
# '<!-- react-frontend-sdlc:end -->' is replaced in place on every run;
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

BEGIN_MARKER='<!-- react-frontend-sdlc:begin -->'
END_MARKER='<!-- react-frontend-sdlc:end -->'

# The governance block references profile keys instead of hardcoding
# values, so the block stays byte-stable across profile edits (NFR-3).
block_file="$(mktemp)"
new_file="$(mktemp)"
snap_file="$(mktemp)"
out_file=""
trap 'rm -f "$block_file" "$new_file" "$snap_file" ${out_file:+"$out_file"}' EXIT
cat >"$block_file" <<BLOCK
$BEGIN_MARKER
## react-frontend-sdlc governance (managed block — do not edit between markers)

This repository's SDLC is driven by the react-frontend-sdlc plugin through the
\`/fe-sdlc\` orchestrator and its stage commands (\`/fe-sdlc-setup\`,
\`/fe-sdlc-issue\`, \`/fe-sdlc-plan\`, \`/fe-sdlc-implement\`, \`/fe-sdlc-review\`,
\`/fe-sdlc-qa\`, \`/fe-sdlc-finish-pr\`). Every command, agent, and skill reads the
project profile at \`.claude/react-sdlc.yml\` rather than hardcoding repo shape.

### Skill-triage gate

Before review or implementation work, every skill shipped by the
react-frontend-sdlc plugin receives a recorded verdict: EXECUTE (with
evidence) or NOT-APPLICABLE (with a reason). Verdicts are formed from
skill frontmatter and the decision guide only; full skill bodies are
loaded solely on EXECUTE.

### Protected quality thresholds

Quality gates live in \`.claude/react-sdlc.yml\` under \`quality.*\` and are
raise-only: score floors (coverage, mutation MSI, Lighthouse desktop/mobile)
may be raised above the shipped defaults, and the eslint, tsc, jscpd,
markdownlint, dependency-cruiser, and visual-diff violation ceilings stay at
0. Never lower them — \`validate-profile.sh\` rejects lowered values.

### Mandatory accessibility gate

Accessibility is non-negotiable. The \`/fe-sdlc-review\` and \`/fe-sdlc-qa\`
stages run the accessibility lane — the target mapped by \`make.a11y\`, or the
plugin's bundled static axe-core / semantic / ARIA checks when that mapping is
\`null\` — and must report a clean a11y verdict before a change can finish.
Never weaken or skip it.

### Make-map execution

Run all build, test, lint, and quality commands through the logical targets
mapped in \`.claude/react-sdlc.yml\` (\`make.*\` — \`make.ci\`, \`make.lint\`,
\`make.test_unit_client\`, and the rest). Never invoke the package manager,
bundler, or test runners directly on the host. A \`null\` mapping means the
capability is absent: skip or degrade with a note, never improvise a raw
host command.
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
# 1 only when the file's fences are BALANCED (every opener closed by a
# matching closer). An UNCLOSED fence must not enable suppression: a stateful
# toggle would stay "inside the fence" through EOF and swallow the real
# managed block we append at the end, so the next run would no longer see
# that block and would append ANOTHER — a duplicate-block / non-idempotent
# regression (NFR-3). With an unclosed fence we fall back to plain
# whole-line marker matching (the pre-fence behaviour), which is safe and
# idempotent; the documented-example case (Bug 4) always has a balanced
# ``` pair, so it still gets the protection.
AWK_FENCE_PRELUDE='
  function norm(l) { sub(/\r$/, "", l); return l }
  # A fence opener is a line whose content (after CR strip and leading-space
  # trim) starts with 3+ backticks or tildes, optionally followed by an info
  # string. The closer must repeat the SAME delimiter at least as long, with
  # nothing after it (CommonMark), so a shorter, longer-nested, or
  # other-delimiter fence-like line inside an open fence is plain content
  # and marker lines inside nested/longer fences stay suppressed. When
  # fence_aware is 0 the tracking is a no-op so every pass matches markers
  # by whole line regardless of fences.
  function fence_run(t, ch,   n) { n = 0; while (substr(t, n + 1, 1) == ch) n++; return n }
  function fence_toggle(l,   t, n) {
    if (!fence_aware) return 0
    t = norm(l); sub(/^[ \t]+/, "", t)
    if (!infence) {
      if (t !~ /^(```+|~~~+)/) return 0
      fence_ch = substr(t, 1, 1)
      fence_len = fence_run(t, fence_ch)
      infence = 1
      return 1
    }
    if (substr(t, 1, 1) != fence_ch) return 0
    n = fence_run(t, fence_ch)
    if (n >= fence_len && substr(t, n + 1) ~ /^[ \t]*$/) { infence = 0; return 1 }
    return 0
  }
'

# fence_balance FILE — print 1 when every fence opener in the file is
# closed by a matching closer (no fence left open at EOF), else 0. Only a
# fully closed fence state is safe for fence-aware marker suppression. The
# shared prelude drives the same opener/closer tracking as every pass.
fence_balance() {
  awk -v fence_aware=1 "$AWK_FENCE_PRELUDE"'
    { fence_toggle($0) }
    END { print infence ? 0 : 1 }
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
existing_mode=""
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
  # Capture the mode HERE, under the symlink/irregular guard, so write_managed
  # can preserve it WITHOUT a second `chmod --reference="$file"` dereference
  # later (which follows symlinks and was a TOCTOU: $file could be swapped for
  # a symlink between the guard and that chmod, letting an attacker pick the new
  # file's mode). CWE-367.
  existing_mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || true)"
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
      fence_toggle($0) { if (!inblock) print; next }
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
  # Check before creating the temp file so a refusal leaves no litter. Inspect
  # the mode BITS, not `-w` (effective access): a privileged run (root) reports
  # -w true even on a 0444 file, silently bypassing the user's lock.
  if [[ -e "$file" ]]; then
    local perm
    perm="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || true)"
    if [[ "$perm" =~ ^[0-7]+$ ]]; then
      # refuse when no write bit is set anywhere (owner/group/other): 0222 mask.
      (( (8#${perm} & 0222) == 0 )) && \
        die "refusing to overwrite read-only file: $file (it needs a managed-block update but is not writable; chmod +w it or remove it to regenerate)"
    elif [[ ! -w "$file" ]]; then
      # mode unreadable (stat failed): fall back to effective-access check.
      die "refusing to overwrite read-only file: $file (it needs a managed-block update but is not writable; chmod +w it or remove it to regenerate)"
    fi
  fi
  out_file="$(mktemp "$TARGET/.sdlc-governance.XXXXXX")" \
    || die "cannot create temp file in $TARGET"
  cat "$new_file" >"$out_file"
  # Preserve the overwrite mode from the value captured under render_managed's
  # symlink/irregular guard (no second symlink-following dereference of $file —
  # closes the CWE-367 TOCTOU). Fall back to the umask-derived create mode for a
  # new file.
  if [[ "$file_exists" -eq 1 && -n "$existing_mode" ]]; then
    chmod "$existing_mode" "$out_file" 2>/dev/null || true
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
      diff -u -L "$file" -L "$file (pending)" "$snap_file" "$new_file" || true
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
