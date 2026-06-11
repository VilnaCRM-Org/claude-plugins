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
trap 'rm -f "$block_file" "$new_file"' EXIT
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

# markers_paired FILE — success only when every BEGIN is closed by an END
# before the next BEGIN or EOF. Counts alone cannot catch an END that
# precedes its BEGIN: that state is count-balanced, but the replacement
# awk below would treat BEGIN..EOF as the managed region and swallow all
# user content after it.
markers_paired() {
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { if (inblock) bad = 1; inblock = 1; next }
    $0 == end   { if (!inblock) bad = 1; inblock = 0; next }
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

# render_managed FILE -> writes the post-injection content to $new_file
render_managed() {
  local file=$1
  reject_symlink "$file"
  if [[ ! -f "$file" ]]; then
    cat "$block_file" >"$new_file"
    return 0
  fi
  local begins ends
  begins="$(grep -cxF "$BEGIN_MARKER" "$file" || true)"
  ends="$(grep -cxF "$END_MARKER" "$file" || true)"
  if [[ "$begins" == "$ends" && "$begins" -gt 0 ]] && markers_paired "$file"; then
    # Balanced markers: drop every managed region, leave a placeholder at
    # the first region's position, then splice the fresh block there.
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
      $0 == begin && !inblock { inblock = 1; if (!placed) { print "\x01MANAGED-BLOCK\x01"; placed = 1 }; next }
      inblock { if ($0 == end) inblock = 0; next }
      { print }
    ' "$file" | awk -v blockfile="$block_file" '
      $0 == "\x01MANAGED-BLOCK\x01" {
        while ((getline line < blockfile) > 0) print line
        close(blockfile)
        next
      }
      { print }
    ' >"$new_file"
  elif [[ "$begins" -eq 0 && "$ends" -eq 0 ]]; then
    # No block yet: append after a blank separator line.
    cat "$file" >"$new_file"
    if [[ -s "$file" && -n "$(tail -c 1 "$file")" ]]; then
      printf '\n' >>"$new_file"  # file lacked trailing newline
    fi
    printf '\n' >>"$new_file"
    cat "$block_file" >>"$new_file"
  else
    # Unbalanced/orphaned/out-of-order markers: removing a begin..EOF
    # span could swallow user content, so drop ONLY the marker lines and
    # append one fresh block at the end.
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
      $0 == begin || $0 == end { next }
      { print }
    ' "$file" >"$new_file"
    printf '\n' >>"$new_file"
    cat "$block_file" >>"$new_file"
  fi
}

overall_changed=0
for name in CLAUDE.md AGENTS.md; do
  file="$TARGET/$name"
  render_managed "$file"
  if [[ -f "$file" ]] && diff -q "$file" "$new_file" >/dev/null 2>&1; then
    log_info "$name: unchanged"
    continue
  fi
  if (( DIFF_ONLY )); then
    overall_changed=1
    log_info "$name: pending changes (--diff preview, file not written)"
    if [[ -f "$file" ]]; then
      diff -u "$file" "$new_file" || true
    else
      log_info "$name does not exist; it would be created with the managed block"
    fi
    continue
  fi
  overall_changed=1
  # cat-through-redirect, not cp: cp from the mktemp file would create a
  # new CLAUDE.md/AGENTS.md with mktemp's 0600 mode; redirect honors the
  # umask on create and keeps the existing mode on overwrite.
  cat "$new_file" >"$file"
  log_info "$name: managed block written"
done

if (( ! overall_changed )); then
  log_info "governance blocks already up to date"
fi
