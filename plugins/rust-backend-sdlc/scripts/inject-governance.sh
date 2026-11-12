#!/usr/bin/env bash
# inject-governance.sh — keep one managed governance block in CLAUDE.md and AGENTS.md (FR-8).
#
# Usage: inject-governance.sh [--diff] [TARGET_DIR]
#
#   TARGET_DIR  the repository root that holds CLAUDE.md and AGENTS.md
#               (default: the working directory)
#   --diff      print a unified diff and `WOULD: update <file>` for every file
#               that would change; write nothing
#   --help      print this help and exit 0 (accepted in any position)
#
# The block runs from `<!-- rust-backend-sdlc:begin -->` to
# `<!-- rust-backend-sdlc:end -->` and its text is fixed (byte-stable: it
# cites profile keys, never values). A marker line counts only outside fenced
# blocks (``` and ~~~); a trailing CR is ignored for matching only. The first
# well-ordered pair is replaced in place; further pairs, orphan begins, orphan
# ends and inverted pairs are removed; when no valid pair remains, the block
# is appended after exactly one blank line. A pair between
# `<!-- verification:start -->` and `<!-- verification:end -->` is removed
# and the block appended at the end. A missing file is created holding only
# the block. The rest of the file keeps its bytes and line endings; every
# write is atomic. Both files are checked before either is written.
#
# Stdout, one line per file: `CREATED: <file>`, `UPDATED: <file>`,
# `REPAIRED: <file> (<n> stray marker line(s) removed)` or
# `UNCHANGED: <file>`; with --diff, the diff and `WOULD: update <file>` for a
# file that would change.
#
# Exit: 0 success; 1 symlinked, non-regular, unreadable or read-only file, missing TARGET_DIR or write failure; 2 usage error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# governance_block — the exact text of the architecture's "Governance Block"
# (markers included, one trailing newline).
governance_block() {
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

# render_program — the python3 program that renders one file.
# argv: BLOCK_FILE PATH OUT_FILE DIFF_FILE NAME. Reads PATH (absent → the
# block alone), writes the new content to OUT_FILE and, when DIFF_FILE is not
# empty and the content changes, a unified diff (control characters
# stripped) to DIFF_FILE; prints `<STATUS> <removed marker lines>` where
# STATUS is CREATED, UPDATED, REPAIRED or UNCHANGED. A file that cannot be
# opened as a regular file without following a symlink exits 1.
render_program() {
  cat <<'PY'
import difflib
import os
import re
import stat
import sys

BEGIN = b"<!-- rust-backend-sdlc:begin -->"
END = b"<!-- rust-backend-sdlc:end -->"
VERIFY_START = b"<!-- verification:start -->"
VERIFY_END = b"<!-- verification:end -->"
MARKER = re.compile(rb" {0,3}(" + re.escape(BEGIN) + rb"|" + re.escape(END) + rb")[ \t]*")
FENCE_SPACE = b" \t\f\v"
CONTROL = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f]")


def fail(message):
    sys.stderr.write("[rust-sdlc][ERROR] " + message + "\n")
    sys.exit(1)


def split_lines(data):
    """Lines split on LF, each keeping its terminator (CR bytes stay)."""
    parts = data.split(b"\n")
    lines = [part + b"\n" for part in parts[:-1]]
    if parts[-1]:
        lines.append(parts[-1])
    return lines


def bare(line):
    """The line without its LF and one trailing CR: the form used for matching."""
    if line.endswith(b"\n"):
        line = line[:-1]
    if line.endswith(b"\r"):
        line = line[:-1]
    return line


def fence_run(text):
    """(char, run, rest) when the line opens or may close a fence, else None."""
    stripped = text.lstrip(FENCE_SPACE)
    char = stripped[:1]
    if char not in (b"`", b"~"):
        return None
    run = len(stripped) - len(stripped.lstrip(char))
    if run < 3:
        return None
    return char, run, stripped[run:]


def scan(lines, fence_aware):
    """Marker lines outside fences, the verification state before each line,
    the verification marker lines, and whether the file ends inside a fence."""
    markers, region, verify = [], [], []
    in_fence, fence_char, fence_len, exempt = False, b"", 0, False
    for index, line in enumerate(lines):
        text = bare(line)
        region.append(exempt)
        if fence_aware:
            fence = fence_run(text)
            if fence and not in_fence:
                in_fence, fence_char, fence_len = True, fence[0], fence[1]
                continue
            if fence and fence[0] == fence_char and fence[1] >= fence_len and not fence[2].strip():
                in_fence = False
                continue
            if in_fence:
                continue
        match = MARKER.fullmatch(text)
        if match:
            markers.append((index, match.group(1) == BEGIN))
            continue
        if VERIFY_START in text:
            exempt = True
            verify.append(index)
        if VERIFY_END in text:
            exempt = False
            verify.append(index)
    return markers, region, verify, in_fence


def plan(lines):
    """(kept pair or None, line indexes to drop, marker lines removed)."""
    markers, region, verify, open_fence = scan(lines, True)
    if open_fence:
        # An unclosed fence would hide every marker after it, including a block
        # appended at the end: match whole lines without fences instead, so the
        # next run still finds that block.
        markers, region, verify, _ = scan(lines, False)
    pairs, orphans, opened = [], [], None
    for index, is_begin in markers:
        if is_begin:
            if opened is not None:
                orphans.append(opened)
            opened = index
        elif opened is None:
            orphans.append(index)
        else:
            pairs.append((opened, index))
            opened = None
    if opened is not None:
        orphans.append(opened)
    kept, drop, removed = None, set(orphans), len(orphans)
    for begin, end in pairs:
        straddles = any(begin < mark < end for mark in verify)
        if not straddles and not region[begin] and kept is None:
            kept = (begin, end)
        elif straddles:
            # The pair encloses a verification marker: drop the marker lines only.
            drop.update((begin, end))
            removed += 2
        else:
            # A further pair, or a pair inside the verification region: drop it.
            drop.update(range(begin, end + 1))
            removed += 2
    return kept, drop, removed


def render(data, block):
    lines = split_lines(data)
    kept, drop, removed = plan(lines)
    out = []
    for index, line in enumerate(lines):
        if kept is not None and kept[0] <= index <= kept[1]:
            if index == kept[0]:
                out.append(block)
            continue
        if index not in drop:
            out.append(line)
    if kept is None:
        while out and not bare(out[-1]).strip(b" \t"):
            out.pop()
        if out and not out[-1].endswith(b"\n"):
            crlf = any(line.endswith(b"\r\n") for line in lines)
            out[-1] += b"\r\n" if crlf else b"\n"
        if out:
            out.append(b"\n")
        out.append(block)
    return b"".join(out), removed


def read_regular(path):
    """The bytes of PATH, or None when it does not exist."""
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        handle = os.open(path, flags)
    except FileNotFoundError:
        return None
    except OSError as error:
        fail("cannot read %s: %s" % (path, error.strerror or error))
    with os.fdopen(handle, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            fail("refusing to read %s: it is not a regular file" % path)
        return stream.read()


def write_diff(diff_file, old, new, name):
    before = [line.decode("utf-8", "replace") for line in split_lines(old or b"")]
    after = [line.decode("utf-8", "replace") for line in split_lines(new)]
    label = "/dev/null" if old is None else "a/" + name
    out = []
    for line in difflib.unified_diff(before, after, label, "b/" + name):
        if line.endswith("\n"):
            out.append(CONTROL.sub("", line[:-1]) + "\n")
        else:
            out.append(CONTROL.sub("", line) + "\n\\ No newline at end of file\n")
    with open(diff_file, "wb") as stream:
        stream.write("".join(out).encode("utf-8", "replace"))


def main(block_file, path, out_file, diff_file, name):
    with open(block_file, "rb") as stream:
        block = stream.read()
    old = read_regular(path)
    if old is None:
        new, status, removed = block, "CREATED", 0
    else:
        new, removed = render(old, block)
        status = "REPAIRED" if removed else ("UNCHANGED" if new == old else "UPDATED")
    with open(out_file, "wb") as stream:
        stream.write(new)
    if diff_file and status != "UNCHANGED":
        write_diff(diff_file, old, new, name)
    print(status, removed)


main(*sys.argv[1:6])
PY
}

# --- arguments ---------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done

DIFF_ONLY=0
TARGET=""
HAVE_TARGET=0
while (($#)); do
  case "$1" in
    --diff) DIFF_ONLY=1 ;;
    -*) die_usage "unknown argument: $1" ;;
    *)
      if [[ "$HAVE_TARGET" == 1 ]]; then
        die_usage "unexpected argument: $1"
      fi
      TARGET="$1"
      HAVE_TARGET=1
      ;;
  esac
  shift
done
if [[ "$HAVE_TARGET" == 0 ]]; then
  TARGET="$PWD"
fi
[[ -d "$TARGET" ]] || die "target directory not found: $TARGET"
TARGET="$(CDPATH='' cd -- "$TARGET" && pwd -P)" || die "cannot enter the target directory: $TARGET"

FILES=(CLAUDE.md AGENTS.md)

# --- refusals, before anything is written --------------------------------------

for name in "${FILES[@]}"; do
  path="$TARGET/$name"
  safe_write_target "$path" "$TARGET" || exit 1
  if [[ -e "$path" && ! -r "$path" ]]; then
    die "cannot read $path: permission denied"
  fi
done

# --- render both files -----------------------------------------------------------

WORK="$(mktemp -d "${TMPDIR:-/tmp}/inject-governance.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf -- "$WORK"' EXIT
governance_block >"$WORK/block"
PROGRAM="$(render_program)"

declare -A STATUS=() REMOVED=()
PENDING=0
for name in "${FILES[@]}"; do
  diff_file=""
  if [[ "$DIFF_ONLY" == 1 ]]; then
    diff_file="$WORK/$name.diff"
  fi
  result="$(python3 -I -c "$PROGRAM" "$WORK/block" "$TARGET/$name" "$WORK/$name.new" "$diff_file" "$name")" || exit 1
  STATUS[$name]="${result%% *}"
  REMOVED[$name]="${result##* }"
  if [[ "${STATUS[$name]}" != UNCHANGED ]]; then
    PENDING=1
  fi
done

# --- write (or preview) ----------------------------------------------------------

if [[ "$DIFF_ONLY" == 0 && "$PENDING" == 1 ]]; then
  [[ -w "$TARGET" ]] || die "cannot write to $TARGET: the directory is not writable"
  for name in "${FILES[@]}"; do
    path="$TARGET/$name"
    if [[ "${STATUS[$name]}" != UNCHANGED && -e "$path" && ! -w "$path" ]]; then
      die "refusing to overwrite read-only $path: make it writable or remove it"
    fi
  done
fi

for name in "${FILES[@]}"; do
  path="$TARGET/$name"
  status="${STATUS[$name]}"
  if [[ "$status" == UNCHANGED ]]; then
    printf 'UNCHANGED: %s\n' "$name"
    continue
  fi
  if [[ "$DIFF_ONLY" == 1 ]]; then
    cat -- "$WORK/$name.diff"
    printf 'WOULD: update %s\n' "$name"
    continue
  fi
  safe_write_target "$path" "$TARGET" || exit 1
  atomic_write "$path" <"$WORK/$name.new" || die "cannot write $path"
  if [[ "$status" == REPAIRED ]]; then
    printf 'REPAIRED: %s (%s stray marker line(s) removed)\n' "$name" "${REMOVED[$name]}"
  else
    printf '%s: %s\n' "$status" "$name"
  fi
done
