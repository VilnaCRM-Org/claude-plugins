#!/usr/bin/env bash
# merge-settings.sh — merge the plugin's allow and deny entries into the git-ignored local Claude Code settings (FR-9).
#
# Usage: merge-settings.sh [--print] [--with-qa-network] [--file local|shared] [TARGET_DIR]
#
#   TARGET_DIR         the repository root (default: the working directory)
#   --file local       merge into .claude/settings.local.json (the default); the
#                      file must be git-ignored (`git check-ignore`), because it
#                      holds the absolute plugin root and the numeric uid:gid
#   --file shared      merge into .claude/settings.json; refused while
#                      protected-config.toml lists it in `files` or below one of
#                      its `directories`, or exists and cannot be parsed
#   --print            print the merged JSON on stdout and write nothing (allowed
#                      for a local file that is not git-ignored)
#   --with-qa-network  kept for compatibility: writes nothing extra and prints
#                      `INFO: QA probes run through common.sh http_probe; no curl
#                      entry is written` as the first stdout line
#   --help             print this help and exit 0 (accepted in any position)
#
# The allow entries are the 66 entries of rows 1-39 of the architecture's
# Permissions Strategy, in table order: make, git, gh, the exact bmalph forms,
# one `Bash(<root>/scripts/<name>.sh:*)` entry per plugin script of the fixed
# 13-name list plus `Bash(<root>/scripts/lib/common.sh:*)`, the same 14 paths
# quoted, docker and the container route with literal `<uid>:<gid>`, the host
# nextest and set-version forms, the log directory and `id -u`/`id -g`. The
# script list is fixed: it is never read from a directory and never checked for
# existence. <root> is resolve_plugin_root (CLAUDE_PLUGIN_ROOT when set), made
# absolute; uid and gid come from `id -u` and `id -g`. The deny entries are the
# 29 plugin-owned entries G1-G9, H1-H8, B1-B2 and M1-M10. Both are unions:
# existing entries keep their bytes and order, new entries are appended once.
# `ask`, `hooks`, `env`, `defaultMode` and every other key stay untouched.
# A `curl` entry and a `bypassPermissions` setting are never written. The file
# is written atomically as json.dumps(obj, indent=2, ensure_ascii=False) plus a
# newline; a file that already holds every entry is left as it is.
#
# Stdout: `WROTE: <file> (+<n> allow, +<m> deny)`, `UNCHANGED: <file>`, the
# merged JSON with --print, or one refusal line:
# `REFUSED: .claude/settings.local.json is not git-ignored`,
# `REFUSED: .claude/settings.json is protected (protected-config.toml lists it); merged JSON follows`
# or the same with `(protected-config.toml unparseable)`, followed by the
# merged JSON.
#
# Exit: 0 success (written, unchanged or printed); 1 refusal (protected or not git-ignored target, symlinked or non-regular target, malformed JSON), missing TARGET_DIR or failure; 2 usage error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# The plugin executables of Permissions Strategy row 25, in table order.
PLUGIN_SCRIPTS=(
  setup-preflight generate-profile validate-profile inject-governance merge-settings
  new-service stage-planning-artifacts ai-review-loop fr-nfr-gate get-pr-comments
  post-review-findings pr-state request-ai-reviews
)

QA_NETWORK_INFO='INFO: QA probes run through common.sh http_probe; no curl entry is written'

# allow_entries ROOT UID GID — the 66 allow entries of Permissions Strategy
# rows 1-39, one per line, in table order.
allow_entries() {
  local root="$1" uid="$2" gid="$3" name exec_prefix
  exec_prefix="docker compose exec -T --user $uid:$gid app"
  printf '%s\n' \
    'Bash(make:*)' \
    'Bash(RUN_IN_CONTAINER=1 make:*)' \
    'Bash(RUN_IN_CONTAINER=1 git commit:*)' \
    'Bash(RUN_IN_CONTAINER=1 git push:*)' \
    'Bash(git status:*)' \
    'Bash(git diff:*)' \
    'Bash(git log:*)' \
    'Bash(git add:*)' \
    'Bash(git commit:*)' \
    'Bash(git push:*)' \
    'Bash(git switch:*)' \
    'Bash(git fetch:*)' \
    'Bash(git rev-parse:*)' \
    'Bash(git merge-base:*)' \
    'Bash(git config --get core.hooksPath)' \
    'Bash(git config --local --get core.hooksPath)' \
    'Bash(git ls-files:*)' \
    'Bash(git remote get-url:*)' \
    'Bash(git check-ignore:*)' \
    'Bash(git branch --show-current)' \
    'Bash(gh:*)' \
    'Bash(bmalph implement)' \
    'Bash(bmalph run --driver claude-code --no-dashboard)' \
    'Bash(bmalph doctor:*)' \
    'Bash(bmalph --version)'
  for name in "${PLUGIN_SCRIPTS[@]}"; do
    printf 'Bash(%s/scripts/%s.sh:*)\n' "$root" "$name"
  done
  printf 'Bash(%s/scripts/lib/common.sh:*)\n' "$root"
  for name in "${PLUGIN_SCRIPTS[@]}"; do
    printf 'Bash("%s/scripts/%s.sh":*)\n' "$root" "$name"
  done
  printf 'Bash("%s/scripts/lib/common.sh":*)\n' "$root"
  printf '%s\n' \
    'Bash(docker info:*)' \
    'Bash(docker compose ps:*)' \
    'Bash(docker compose logs:*)' \
    "Bash($exec_prefix cargo tree:*)" \
    "Bash($exec_prefix cargo metadata:*)" \
    "Bash($exec_prefix cargo xtask config-guard --list)" \
    "Bash($exec_prefix env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)" \
    "Bash($exec_prefix scripts/set-version.sh:*)" \
    'Bash(env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)' \
    'Bash(scripts/set-version.sh:*)' \
    'Bash(mkdir -p target/rust-sdlc/logs)' \
    'Bash(id -u)' \
    'Bash(id -g)'
}

# deny_entries — the 29 plugin-owned deny entries G1-G9, H1-H8, B1-B2 and
# M1-M10, one per line, in table order. The options these entries refuse are
# held in variables, so no line of this script spells a git or bmalph command
# together with a hook-bypass or force option: NFR-5 (CC-15) allows such a
# line under scripts/ only as a comment that says never, and this script never
# passes those options to any command.
deny_entries() {
  local no_verify='--no-verify' force='--force' short_n='-n' short_f='-f'
  printf '%s\n' \
    "Bash(git commit *$no_verify*)" \
    "Bash(git commit * $short_n *)" \
    "Bash(git commit * $short_n)" \
    "Bash(git push *$force*)" \
    "Bash(git push * $short_f*)" \
    "Bash(git push *$no_verify*)" \
    'Bash(git push *--mirror*)' \
    'Bash(git push *--delete*)' \
    'Bash(git push * +*)' \
    'Bash(gh *approved-config-change*)' \
    'Bash(gh *approved-breaking-change*)' \
    'Bash(gh pr merge:*)' \
    'Bash(gh secret:*)' \
    'Bash(gh variable:*)' \
    'Bash(gh repo delete:*)' \
    'Bash(gh repo edit:*)' \
    'Bash(gh api *protection*)' \
    'Bash(bmalph reset:*)' \
    "Bash(bmalph implement *$force*)" \
    'Bash(make -*)' \
    'Bash(make *_CMD=*)' \
    'Bash(make *_FLAGS=*)' \
    'Bash(make *_ARGS=*)' \
    'Bash(make *CI_STAGES=*)' \
    'Bash(make *CONFIG_CHANGE_APPROVED=true*)' \
    'Bash(make * -i*)' \
    'Bash(make * -k*)' \
    'Bash(make * -n*)' \
    'Bash(make * -*)'
}

# merge_program — the python3 program that merges the entries.
# argv: SETTINGS_FILE SHOWN_NAME ALLOW_FILE DENY_FILE OUT_FILE. Reads
# SETTINGS_FILE (absent → {}) without following a symlink, appends every entry
# of ALLOW_FILE and DENY_FILE (one per line) that permissions.allow or
# permissions.deny does not hold yet, writes json.dumps(obj, indent=2,
# ensure_ascii=False) + "\n" to OUT_FILE and prints `<added allow> <added deny>`.
# Malformed JSON (NaN, Infinity and -Infinity included, and a number that
# overflows to infinity, such as 1e400: JSON.parse, which Claude Code reads the
# file with, rejects what json.dumps would write for them), a top-level value
# that is not an object, a `permissions` value that is not an object or an
# `allow`/`deny` value that is not a list exits 1 with one error line.
merge_program() {
  cat <<'PY'
import json
import math
import os
import stat
import sys

path, shown, allow_file, deny_file, out_file = sys.argv[1:6]


def fail(message):
    sys.stderr.write("[rust-sdlc][ERROR] " + message + "\n")
    sys.exit(1)


def no_constant(name):
    raise ValueError("non-JSON constant " + name)


def finite(literal):
    value = float(literal)
    if not math.isfinite(value):
        raise ValueError("number out of range: " + literal)
    return value


def entries(name):
    with open(name, encoding="utf-8") as stream:
        return [line.rstrip("\n") for line in stream if line.rstrip("\n")]


def read_existing():
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        handle = os.open(path, flags)
    except FileNotFoundError:
        return None
    except OSError as error:
        fail("cannot read %s: %s" % (shown, error.strerror or error))
    with os.fdopen(handle, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            fail("refusing to read %s: it is not a regular file" % shown)
        return stream.read()


data = read_existing()
if data is None:
    settings = {}
else:
    try:
        settings = json.loads(data.decode("utf-8"), parse_constant=no_constant, parse_float=finite)
    except (UnicodeDecodeError, ValueError) as error:
        first = (str(error).splitlines() or ["invalid JSON"])[0]
        fail("%s is not valid JSON (%s); the file is left unchanged" % (shown, first))
    if not isinstance(settings, dict):
        fail("%s: the top-level JSON value is not an object; the file is left unchanged" % shown)

permissions = settings.get("permissions")
if permissions is None:
    permissions = settings["permissions"] = {}
if not isinstance(permissions, dict):
    fail("%s: permissions is not a JSON object; the file is left unchanged" % shown)

added = []
for key, new in (("allow", entries(allow_file)), ("deny", entries(deny_file))):
    current = permissions.get(key)
    if current is None:
        current = permissions[key] = []
    if not isinstance(current, list):
        fail("%s: permissions.%s is not a JSON array; the file is left unchanged" % (shown, key))
    present = {item for item in current if isinstance(item, str)}
    count = 0
    for entry in new:
        if entry not in present:
            current.append(entry)
            present.add(entry)
            count += 1
    added.append(count)

text = json.dumps(settings, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
with open(out_file, "w", encoding="utf-8") as stream:
    stream.write(text)
print(added[0], added[1])
PY
}

# protection_program — the python3 program behind the shared-file refusal.
# argv: PROTECTED_CONFIG RELATIVE_PATH. Prints `listed` when the `files` array
# names RELATIVE_PATH or it lies below an entry of `directories`, `clear`
# otherwise, and `unparseable` when the file cannot be read or parsed or either
# key is not an array of strings (fail closed). Exit 3 without tomllib.
protection_program() {
  cat <<'PY'
import sys

try:
    import tomllib
except ImportError:
    sys.exit(3)

config, target = sys.argv[1], sys.argv[2]
try:
    with open(config, "rb") as stream:
        doc = tomllib.load(stream)
except Exception:  # unreadable, not a regular file or malformed TOML
    print("unparseable")
    sys.exit(0)

files = doc.get("files", [])
directories = doc.get("directories", [])
if not isinstance(files, list) or not isinstance(directories, list) or not all(
    isinstance(item, str) for item in files + directories
):
    print("unparseable")
    sys.exit(0)


def norm(item):
    while item.startswith("./"):
        item = item[2:]
    return item


listed = any(norm(item) == target for item in files)
for item in directories:
    prefix = norm(item).rstrip("/")
    if prefix in ("", ".") or target.startswith(prefix + "/"):
        listed = True
print("listed" if listed else "clear")
PY
}

# --- arguments ---------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done

PRINT_ONLY=0
QA_NETWORK=0
MODE=local
TARGET=""
HAVE_TARGET=0
while (($#)); do
  case "$1" in
    --print) PRINT_ONLY=1 ;;
    --with-qa-network) QA_NETWORK=1 ;;
    --file)
      need_value "$1" "${2-}"
      case "$2" in
        local | shared) MODE="$2" ;;
        *) die_usage "--file must be local or shared: $2" ;;
      esac
      shift
      ;;
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

if [[ "$MODE" == shared ]]; then
  REL=.claude/settings.json
else
  REL=.claude/settings.local.json
fi
FILE="$TARGET/$REL"

if [[ "$QA_NETWORK" == 1 ]]; then
  printf '%s\n' "$QA_NETWORK_INFO"
fi

# --- inputs: plugin root, uid and gid ------------------------------------------

ROOT="$(resolve_plugin_root)" || exit 1
ROOT="$(CDPATH='' cd -- "$ROOT" && pwd)" || die "cannot enter the plugin root: $ROOT"
case "$ROOT" in
  *'*'* | *'"'* | *\\* | *[[:cntrl:]]*)
    die "refusing a plugin root that contains '*', '\"', '\\' or a control character: $ROOT"
    ;;
  /*) ;;
  *) die "the plugin root is not an absolute path: $ROOT" ;;
esac
USER_ID="$(id -u)" || die "id -u failed"
GROUP_ID="$(id -g)" || die "id -g failed"
is_uint "$USER_ID" || die "id -u printed a non-numeric uid: $USER_ID"
is_uint "$GROUP_ID" || die "id -g printed a non-numeric gid: $GROUP_ID"

# --- merge ---------------------------------------------------------------------

safe_write_target "$FILE" "$TARGET" || exit 1

WORK="$(mktemp -d "${TMPDIR:-/tmp}/merge-settings.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf -- "$WORK"' EXIT
allow_entries "$ROOT" "$USER_ID" "$GROUP_ID" >"$WORK/allow"
deny_entries >"$WORK/deny"
counts="$(python3 -I -c "$(merge_program)" "$FILE" "$REL" "$WORK/allow" "$WORK/deny" "$WORK/merged.json")" || exit 1
ADDED_ALLOW="${counts%% *}"
ADDED_DENY="${counts##* }"

# --- refusals and output ---------------------------------------------------------

if [[ "$MODE" == shared ]]; then
  CONFIG="$TARGET/protected-config.toml"
  verdict=clear
  if [[ -e "$CONFIG" || -L "$CONFIG" ]]; then
    rc=0
    verdict="$(python3 -I -c "$(protection_program)" "$CONFIG" "$REL")" || rc=$?
    if ((rc == 3)); then
      die "python3 3.11+ with tomllib is required to read protected-config.toml"
    fi
    ((rc == 0)) || die "cannot check protected-config.toml"
  fi
  case "$verdict" in
    listed | unparseable)
      if [[ "$verdict" == listed ]]; then
        printf 'REFUSED: %s is protected (protected-config.toml lists it); merged JSON follows\n' "$REL"
      else
        printf 'REFUSED: %s is protected (protected-config.toml unparseable); merged JSON follows\n' "$REL"
      fi
      cat -- "$WORK/merged.json"
      exit 1
      ;;
    *) ;;
  esac
fi

if [[ "$PRINT_ONLY" == 1 ]]; then
  cat -- "$WORK/merged.json"
  exit 0
fi

if [[ "$MODE" == local ]] && ! git -C "$TARGET" check-ignore -q -- "$REL" 2>/dev/null; then
  printf 'REFUSED: %s is not git-ignored\n' "$REL"
  exit 1
fi

if [[ "$ADDED_ALLOW" == 0 && "$ADDED_DENY" == 0 ]]; then
  printf 'UNCHANGED: %s\n' "$REL"
  exit 0
fi

safe_write_target "$FILE" "$TARGET" || exit 1
atomic_write "$FILE" <"$WORK/merged.json" || die "cannot write $FILE"
printf 'WROTE: %s (+%s allow, +%s deny)\n' "$REL" "$ADDED_ALLOW" "$ADDED_DENY"
