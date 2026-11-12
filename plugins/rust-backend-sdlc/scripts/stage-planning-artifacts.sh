#!/usr/bin/env bash
# stage-planning-artifacts.sh — stage a specs/<N>-<slug>/ planning bundle for bmalph implement (FR-17).
#
# Usage: stage-planning-artifacts.sh <specs-dir> [--dest <dir>] [--dry-run]
#   <specs-dir>   the planning bundle: a directory inside the repository,
#                 neither a symbolic link nor under _bmad-output/
#   --dest <dir>  the staging folder; it must resolve under _bmad-output/ of
#                 the repository and be git-ignored
#                 (default: _bmad-output/planning-artifacts at the repository root)
#   --dry-run     run every pre-check, print one `WOULD: stage <src> -> <dest>`
#                 line per file and write or remove nothing
#   --help        print this help and exit 0
#
# Copies prd.md, architecture.md, epics.md, implementation-readiness.md,
# product-brief.md, research.md as technical-research.md (bmalph classifies
# research only by /tech.*research/i) and every ux*.md into the dest, one
# `STAGED: <src> -> <dest>` line per file, then removes every regular *.md
# file at depth 1 of the dest that this run did not produce, one
# `REMOVED: <dest-file>` line each; subdirectories and other files stay.
# Paths are printed relative to the repository root, so a re-run prints the
# same lines and leaves the same bytes.
#
# Pre-checks, all before the first write: the specs dir resolves inside the
# repository and is not a symbolic link; prd.md, architecture.md and epics.md
# are present; epics.md has a `### Story N.M:` heading;
# implementation-readiness.md does not match /NO[-\s]?GO/i (bmalph's
# preflight regex); the `## Constraints` section of architecture.md, from its
# heading to the next level-2 heading, is at most 4500 characters (bmalph cuts
# it at 5000, ADR-10); the dest resolves under _bmad-output/, is git-ignored
# and holds no tracked file. A failed pre-check prints one `REFUSED: <reason>`
# line and nothing is written or removed.
#
# Exit: 0 staged (or previewed with --dry-run); 1 refused; 2 usage error or a working directory outside a git work tree (ADR-23).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Byte-wise globbing, sorting and character classes: the ux*.md order and the
# REMOVED order do not depend on the caller's locale.
export LC_ALL=C

readonly CONSTRAINTS_MAX=4500
readonly DEFAULT_DEST=_bmad-output/planning-artifacts

# --- helpers ------------------------------------------------------------------

# clean S — S with every control character replaced by `?`, so a crafted
# file or directory name cannot forge an output line.
clean() {
  local s="${1-}"
  printf '%s' "${s//[[:cntrl:]]/?}"
}

# refuse REASON... — the one `REFUSED: <reason>` line on stdout, then exit 1.
refuse() {
  printf 'REFUSED: %s\n' "$*"
  exit 1
}

# strip_slashes PATH — PATH without trailing slashes (`/` stays `/`).
strip_slashes() {
  local p="${1-}"
  while [[ "$p" == */ && "$p" != / ]]; do
    p="${p%/}"
  done
  printf '%s' "$p"
}

# has_link_below_root PATH — 0 when PATH, or one of its parents as written,
# is a symbolic link; the walk stops at the repository root (an alias of the
# root above it is not inspected).
has_link_below_root() {
  local d="${1-}"
  while [[ -n "$d" && "$d" != . && "$d" != / ]]; do
    if [[ "$d" -ef "$ROOT" ]]; then
      return 1
    fi
    if [[ -L "$d" ]]; then
      return 0
    fi
    d="$(dirname -- "$d")"
  done
  return 1
}

# real_path PATH — the physical location PATH names: its deepest existing
# ancestor resolved with `cd -P` (a directory itself, anything else through
# its parent), followed by the components that do not exist yet. Fails when a
# missing component is `..` (it cannot be resolved without the directory).
real_path() {
  local p="${1-}" rest="" base real
  while [[ ! -e "$p" && ! -L "$p" ]]; do
    base="$(basename -- "$p")"
    case "$base" in
      .) ;;
      ..) return 1 ;;
      *) rest="/$base$rest" ;;
    esac
    p="$(dirname -- "$p")"
  done
  if [[ -d "$p" ]]; then
    real="$(cd -P -- "$p" && pwd -P)" || return 1
  else
    real="$(cd -P -- "$(dirname -- "$p")" && pwd -P)" || return 1
    real="${real%/}/$(basename -- "$p")"
  fi
  printf '%s%s\n' "${real%/}" "$rest"
}

# existing_ancestor PATH — PATH when it exists, else its nearest existing
# parent (PATH is absolute).
existing_ancestor() {
  local d="${1-}"
  while [[ ! -e "$d" && ! -L "$d" && "$d" != / ]]; do
    d="$(dirname -- "$d")"
  done
  printf '%s\n' "$d"
}

# under DIR PATH — PATH is DIR itself or below it.
under() {
  [[ "$2" == "$1" || "$2" == "$1"/* ]]
}

# readiness_blocked FILE — prints 1 when FILE matches /NO[-\s]?GO/i over its
# whole text (a match may span a line break, as in bmalph), else 0.
readiness_blocked() {
  _sdlc_py -I -c '
import re
import sys
with open(sys.argv[1], encoding="utf-8", errors="surrogateescape", newline="") as handle:
    text = handle.read()
print(1 if re.search(r"NO[-\s]?GO", text, re.IGNORECASE) else 0)
' "$1"
}

# constraints_length FILE — prints the length in characters of the first
# `## Constraints` section of FILE: from the start of its heading line to the
# start of the next level-2 heading line (or the end of the file), line
# endings kept as written; 0 when FILE has no such section.
constraints_length() {
  _sdlc_py -I -c '
import re
import sys
with open(sys.argv[1], encoding="utf-8", errors="surrogateescape", newline="") as handle:
    text = handle.read()
heading = re.search(r"^##[ \t]+Constraints\b", text, re.MULTILINE)
if heading is None:
    print(0)
    sys.exit(0)
start = heading.start()
eol = text.find("\n", heading.end())
end = len(text)
if eol >= 0:
    following = re.compile(r"^##(?:[ \t]|\r?$)", re.MULTILINE).search(text, eol + 1)
    if following is not None:
        end = following.start()
print(end - start)
' "$1"
}

# --- arguments ----------------------------------------------------------------

for arg in "$@"; do
  case "$arg" in
    --help | -h)
      print_usage "$0"
      exit 0
      ;;
    *) ;;
  esac
done

SPECS_ARG=""
SPECS_SET=0
DEST_ARG=""
DRY_RUN=0
while (($#)); do
  case "$1" in
    --dest)
      need_value "$1" "${2-}"
      DEST_ARG="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -*)
      die_usage "unknown argument: $(clean "$1")"
      ;;
    *)
      if ((SPECS_SET)); then
        die_usage "unexpected argument: $(clean "$1")"
      fi
      SPECS_ARG="$1"
      SPECS_SET=1
      shift
      ;;
  esac
done
[[ -n "$SPECS_ARG" ]] || die_usage "missing <specs-dir>"

# --- environment (ADR-23: exit 2 outside a git work tree) -----------------------

if ! have_cmd git; then
  log_error "git is not installed: stage-planning-artifacts.sh needs git"
  exit 2
fi
if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null || true)" != true ]]; then
  log_error "not inside a git work tree: run stage-planning-artifacts.sh from the repository that holds the bundle"
  exit 2
fi
TOP="$(git rev-parse --show-toplevel)" || die "cannot read the repository root"
ROOT="$(cd -P -- "$TOP" && pwd -P)" || die "cannot enter the repository root $(clean "$TOP")"
readonly ROOT
OUTPUT_ROOT="${ROOT%/}/_bmad-output"

# --- the specs dir --------------------------------------------------------------

SPECS_SHOWN="$(clean "$SPECS_ARG")"
specs="$(strip_slashes "$SPECS_ARG")"
if [[ -L "$specs" ]]; then
  refuse "specs dir $SPECS_SHOWN is a symbolic link"
fi
if [[ ! -d "$specs" ]]; then
  refuse "specs dir $SPECS_SHOWN does not exist or is not a directory"
fi
SPECS_REAL="$(cd -P -- "$specs" && pwd -P)" || refuse "specs dir $SPECS_SHOWN cannot be entered"
if ! under "$ROOT" "$SPECS_REAL"; then
  refuse "specs dir $SPECS_SHOWN is outside the repository"
fi
if has_link_below_root "$specs"; then
  refuse "specs dir $SPECS_SHOWN has a symbolic link in its path"
fi
if under "$OUTPUT_ROOT" "$SPECS_REAL"; then
  refuse "specs dir $SPECS_SHOWN is inside _bmad-output/"
fi
SPECS_REL="${SPECS_REAL#"$ROOT"}"
SPECS_REL="${SPECS_REL#/}"
SPECS_LABEL="$(clean "${SPECS_REL:-.}")"

# --- the dest -------------------------------------------------------------------

if [[ -n "$DEST_ARG" ]]; then
  DEST_SHOWN="$(clean "$DEST_ARG")"
  dest="$(strip_slashes "$DEST_ARG")"
else
  DEST_SHOWN="$DEFAULT_DEST"
  dest="${ROOT%/}/$DEFAULT_DEST"
fi
DEST_REAL="$(real_path "$dest")" || refuse "dest $DEST_SHOWN is outside _bmad-output/"
if [[ "$DEST_REAL" != "$OUTPUT_ROOT"/?* ]]; then
  refuse "dest $DEST_SHOWN is outside _bmad-output/"
fi
if has_link_below_root "$dest"; then
  refuse "dest $DEST_SHOWN is a symbolic link or has one in its path"
fi
if [[ ! -d "$(existing_ancestor "$DEST_REAL")" ]]; then
  refuse "dest $DEST_SHOWN is not a directory"
fi
DEST_REL="${DEST_REAL#"$ROOT"/}"
DEST_LABEL="$(clean "$DEST_REL")"
if ! git -C "$ROOT" check-ignore -q -- "$DEST_REL/" ||
  [[ -n "$(git --literal-pathspecs -C "$ROOT" ls-files -- "$DEST_REL")" ]]; then
  refuse "dest $DEST_SHOWN is tracked (not git-ignored)"
fi

# --- the bundle -----------------------------------------------------------------

# check_source NAME — refuse a bundle file that is a symbolic link or not a
# regular file; status 1 when NAME is absent.
check_source() {
  local path="$SPECS_REAL/$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 1
  fi
  if [[ -L "$path" || ! -f "$path" ]]; then
    refuse "$(clean "$1") in $SPECS_LABEL is not a regular file"
  fi
}

SRC_NAMES=()
DST_NAMES=()
for name in prd.md architecture.md epics.md; do
  check_source "$name" || refuse "$name is missing from $SPECS_LABEL"
  SRC_NAMES+=("$name")
  DST_NAMES+=("$name")
done

if ! grep -Eq '^###[[:space:]]+Story[[:space:]]+[0-9]+\.[0-9]+:' "$SPECS_REAL/epics.md"; then
  refuse "epics.md in $SPECS_LABEL has no ### Story N.M: heading"
fi

if check_source implementation-readiness.md; then
  blocked="$(readiness_blocked "$SPECS_REAL/implementation-readiness.md")" ||
    die "cannot read $SPECS_LABEL/implementation-readiness.md"
  if [[ "$blocked" == 1 ]]; then
    refuse "implementation-readiness.md in $SPECS_LABEL matches /NO[-\\s]?GO/i (readiness is not ready)"
  fi
  SRC_NAMES+=(implementation-readiness.md)
  DST_NAMES+=(implementation-readiness.md)
else
  log_warn "$SPECS_LABEL has no implementation-readiness.md; it is not staged"
fi

length="$(constraints_length "$SPECS_REAL/architecture.md")" ||
  die "cannot read $SPECS_LABEL/architecture.md"
is_uint "$length" || die "cannot measure ## Constraints of $SPECS_LABEL/architecture.md"
if num_gt "$length" "$CONSTRAINTS_MAX"; then
  refuse "architecture.md ## Constraints exceeds $CONSTRAINTS_MAX characters ($(strip_zeros "$length"))"
fi

if check_source product-brief.md; then
  SRC_NAMES+=(product-brief.md)
  DST_NAMES+=(product-brief.md)
else
  log_warn "$SPECS_LABEL has no product-brief.md; it is not staged"
fi
if check_source research.md; then
  SRC_NAMES+=(research.md)
  DST_NAMES+=(technical-research.md)
else
  log_warn "$SPECS_LABEL has no research.md; technical-research.md is not staged"
fi

shopt -s nullglob
for path in "$SPECS_REAL"/ux*.md; do
  name="$(basename -- "$path")"
  check_source "$name" || continue
  SRC_NAMES+=("$name")
  DST_NAMES+=("$name")
done

# Every write target is checked before the first write.
for name in "${DST_NAMES[@]}"; do
  if ! safe_write_target "$DEST_REAL/$name" "$ROOT"; then
    refuse "cannot write $DEST_LABEL/$(clean "$name")"
  fi
done

# Stale files: regular *.md files (not symbolic links) at depth 1 of the dest
# that this run does not produce.
STALE=()
if [[ -d "$DEST_REAL" ]]; then
  for path in "$DEST_REAL"/*.md; do
    [[ -f "$path" && ! -L "$path" ]] || continue
    name="$(basename -- "$path")"
    produced=0
    for target in "${DST_NAMES[@]}"; do
      if [[ "$target" == "$name" ]]; then
        produced=1
        break
      fi
    done
    if ((produced == 0)); then
      STALE+=("$name")
    fi
  done
fi
shopt -u nullglob

# --- stage ----------------------------------------------------------------------

src_label() {
  printf '%s' "${SPECS_REL:+$SPECS_REL/}$1"
}

if ((DRY_RUN)); then
  for i in "${!SRC_NAMES[@]}"; do
    printf 'WOULD: stage %s -> %s\n' "$(clean "$(src_label "${SRC_NAMES[i]}")")" \
      "$DEST_LABEL/$(clean "${DST_NAMES[i]}")"
  done
  log_info "dry run: ${#SRC_NAMES[@]} files would be staged into $DEST_LABEL; nothing written"
  exit 0
fi

for i in "${!SRC_NAMES[@]}"; do
  atomic_write "$DEST_REAL/${DST_NAMES[i]}" <"$SPECS_REAL/${SRC_NAMES[i]}" ||
    die "cannot write $DEST_LABEL/$(clean "${DST_NAMES[i]}")"
  printf 'STAGED: %s -> %s\n' "$(clean "$(src_label "${SRC_NAMES[i]}")")" \
    "$DEST_LABEL/$(clean "${DST_NAMES[i]}")"
done

for name in "${STALE[@]}"; do
  path="$DEST_REAL/$name"
  [[ -f "$path" && ! -L "$path" ]] || continue
  rm -f -- "$path" || die "cannot remove $DEST_LABEL/$(clean "$name")"
  printf 'REMOVED: %s\n' "$DEST_LABEL/$(clean "$name")"
done

log_info "staged ${#SRC_NAMES[@]} files from $SPECS_LABEL into $DEST_LABEL"
