#!/usr/bin/env bash
# common.sh — shared library of the rust-backend-sdlc scripts (FR-33).
#
# Usage: common.sh <dispatcher-name> [ARG...]
#        source "$SCRIPT_DIR/lib/common.sh"   (from a plugin script)
#
# Sourced, the file runs the bash floor check and defines functions; nothing
# else executes. Executed with one of the 17 ADR-15 dispatcher names, it runs
# that function with the remaining arguments and exits with its status;
# executed with no argument or any other first argument, it prints
# `common.sh is a library; source it instead of executing` and exits 64.
#
# Sections, one owner each (single-writer); a later section is inserted
# directly above the `dispatch (keep last)` trailer: core, command helpers,
# publishing and model sessions, stage state and resume, Ralph helpers.
#
# Exit: 0 success; 1 failure or refusal; 2 usage error; 64 executed without a
# dispatcher name.

# Bash floor (NFR-16). These are the first executable lines and use only
# bash 3.2 syntax, so an old bash stops here, before any function exists.
# RUST_SDLC_BASH_VERSION simulates a `major.minor` version in tests.
case "${RUST_SDLC_BASH_VERSION:-${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}}" in
  [0-3] | [0-3].* | 4 | 4.[0-3] | 4.[0-3].*)
    printf '[rust-sdlc][ERROR] bash %s is too old: install Bash 4.4 or newer\n' \
      "${RUST_SDLC_BASH_VERSION:-${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}}" >&2
    exit 1
    ;;
esac

# section: core

# --- logging, exits and argument handling ---------------------------------

# log_info / log_warn / log_error MSG... — one `[rust-sdlc][LEVEL] <msg>` line
# on stderr; stdout carries only handles and data.
log_info() {
  printf '[rust-sdlc][INFO] %s\n' "$*" >&2
}

log_warn() {
  printf '[rust-sdlc][WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[rust-sdlc][ERROR] %s\n' "$*" >&2
}

# die MSG... — log_error, then exit 1.
die() {
  log_error "$*"
  exit 1
}

# _sdlc_usage_line SCRIPT — the text after `# Usage: ` in SCRIPT's header
# comment block (empty when SCRIPT is not a readable file or has none).
_sdlc_usage_line() {
  local script="${1-}" line n=0
  [[ -f "$script" && -r "$script" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if ((n == 1)); then
      continue
    fi
    [[ "$line" == '#'* ]] || break
    if [[ "$line" == '# Usage: '* ]]; then
      printf '%s\n' "${line#'# Usage: '}"
      return 0
    fi
  done <"$script"
}

# die_usage MSG... — log_error with ` (usage: <the caller's Usage line>)`
# appended, then exit 2 (ADR-23).
die_usage() {
  local msg="$*" usage
  usage="$(_sdlc_usage_line "$0")"
  if [[ -n "$usage" ]]; then
    msg="$msg (usage: $usage)"
  fi
  log_error "$msg"
  exit 2
}

# print_usage SCRIPT — SCRIPT's header comment block: line 2 up to the first
# non-comment line, each line without its leading `#` and one space.
print_usage() {
  local script="${1-}" line n=0
  [[ -f "$script" && -r "$script" ]] || die "print_usage: cannot read $script"
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if ((n == 1)); then
      continue
    fi
    [[ "$line" == '#'* ]] || break
    line="${line#'#'}"
    printf '%s\n' "${line#' '}"
  done <"$script"
}

# need_value FLAG VALUE — die_usage "<flag> needs a value" when VALUE is empty
# or starts with `--`.
need_value() {
  local flag="${1-}" value="${2-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    die_usage "$flag needs a value"
  fi
}

# lower S — S lower-cased through tr (no trailing newline).
lower() {
  printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]'
}

# --- wrap-safe digit-string arithmetic --------------------------------------
# Integers from users and repositories are compared as digit strings, never
# with (( )): bash arithmetic wraps at 2^63, so a crafted 20-digit value would
# read as negative or zero and pass a bound.

# is_uint S — S matches ^[0-9]+$.
is_uint() {
  [[ "${1-}" =~ ^[0-9]+$ ]]
}

# strip_zeros N — N without leading zeros ('007' → '7', '000' → '0').
strip_zeros() {
  local v="${1-}"
  v="${v#"${v%%[!0]*}"}"
  printf '%s' "${v:-0}"
}

# num_gt A B — true when A > B (both uints; any other input → status 2).
num_gt() {
  local a b
  if ! is_uint "${1-}" || ! is_uint "${2-}"; then
    return 2
  fi
  a="$(strip_zeros "$1")"
  b="$(strip_zeros "$2")"
  if ((${#a} != ${#b})); then
    ((${#a} > ${#b}))
  else
    [[ "$a" > "$b" ]]
  fi
}

# num_lt A B — true when A < B (same rules as num_gt).
num_lt() {
  num_gt "${2-}" "${1-}"
}

# num_add A B — A + B by column addition with carry; non-digit input prints
# '0' and returns 1. Only single-digit sums and string indexes are computed
# with (( )), never the full value.
num_add() {
  local a b out="" carry=0 ia ib da db sum
  if ! is_uint "${1-}" || ! is_uint "${2-}"; then
    printf '0'
    return 1
  fi
  a="$(strip_zeros "$1")"
  b="$(strip_zeros "$2")"
  ia=$((${#a} - 1))
  ib=$((${#b} - 1))
  while ((ia >= 0 || ib >= 0 || carry > 0)); do
    da=0
    db=0
    if ((ia >= 0)); then
      da="${a:ia:1}"
    fi
    if ((ib >= 0)); then
      db="${b:ib:1}"
    fi
    sum=$((da + db + carry))
    out="$((sum % 10))$out"
    carry=$((sum / 10))
    ia=$((ia - 1))
    ib=$((ib - 1))
  done
  printf '%s' "$(strip_zeros "$out")"
}

# --- clock -----------------------------------------------------------------

# _sdlc_py ARG... — python3 that never puts the working directory (a target
# repository) on sys.path, so a planted module cannot shadow the stdlib.
_sdlc_py() {
  PYTHONSAFEPATH=1 python3 "$@"
}

# now_epoch — ${SDLC_NOW_EPOCH:-$(date +%s)}; a non-uint SDLC_NOW_EPOCH dies.
now_epoch() {
  if [[ -n "${SDLC_NOW_EPOCH:-}" ]]; then
    is_uint "$SDLC_NOW_EPOCH" || die "SDLC_NOW_EPOCH is not a non-negative integer: $SDLC_NOW_EPOCH"
    printf '%s\n' "$SDLC_NOW_EPOCH"
  else
    date +%s
  fi
}

# _sdlc_utc_format FORMAT — now_epoch formatted in UTC through python3.
_sdlc_utc_format() {
  local epoch
  epoch="$(now_epoch)" || return 1
  _sdlc_py -c '
import sys
from datetime import datetime, timezone
try:
    print(datetime.fromtimestamp(int(sys.argv[1]), timezone.utc).strftime(sys.argv[2]))
except (OverflowError, OSError, ValueError) as exc:
    sys.stderr.write("[rust-sdlc][ERROR] cannot format epoch %s: %s\n" % (sys.argv[1], exc))
    sys.exit(1)
' "$epoch" "$1"
}

# utc_now — now_epoch as %Y-%m-%dT%H:%M:%SZ (honours SDLC_NOW_EPOCH).
utc_now() {
  _sdlc_utc_format '%Y-%m-%dT%H:%M:%SZ'
}

# utc_stamp — now_epoch as %Y%m%dT%H%M%SZ (honours SDLC_NOW_EPOCH).
utc_stamp() {
  _sdlc_utc_format '%Y%m%dT%H%M%SZ'
}

# --- tool probes -------------------------------------------------------------

# have_cmd NAME — NAME resolves through command -v.
have_cmd() {
  command -v "${1-}" >/dev/null 2>&1
}

# have_jq — jq is on PATH.
have_jq() {
  command -v jq >/dev/null 2>&1
}

# have_pyyaml — `python3 -c 'import yaml'` succeeds.
have_pyyaml() {
  _sdlc_py -c 'import yaml' >/dev/null 2>&1
}

# have_yq — a mikefarah yq (v4) is usable. False when SDLC_FORCE_PYTHON_YAML=1.
# Presence on PATH is not enough: the kislyuk (jq-wrapper) yq answers the
# probe with "array", and every query below would misread its output. The
# verdict is cached in _SDLC_YQ_OK (1 or 0) for the rest of the process.
have_yq() {
  if [[ "${SDLC_FORCE_PYTHON_YAML:-0}" == 1 ]]; then
    return 1
  fi
  case "${_SDLC_YQ_OK:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  if command -v yq >/dev/null 2>&1 &&
    [[ "$(printf 'a: [1]\n' | yq '.a | type' 2>/dev/null)" == '!!seq' ]]; then
    _SDLC_YQ_OK=1
    return 0
  fi
  _SDLC_YQ_OK=0
  return 1
}

# require_yaml_toolchain — die unless mikefarah yq or python3 + PyYAML works.
require_yaml_toolchain() {
  if ! have_yq && ! have_pyyaml; then
    die "no YAML toolchain: install mikefarah yq v4, or python3 with PyYAML"
  fi
}

# _sdlc_err_first PREFIX CMD... — run CMD with stdout passed through; when it
# fails, log PREFIX plus the first line CMD wrote to stderr and return its
# status. A successful CMD's stderr is dropped.
_sdlc_err_first() {
  local prefix="$1" err rc=0
  shift
  { err="$("$@" 2>&1 1>&3 3>&-)" || rc=$?; } 3>&1
  if ((rc != 0)) && [[ -n "$err" ]]; then
    log_error "$prefix${err%%$'\n'*}"
  fi
  return "$rc"
}

# --- YAML access (mikefarah yq, else python3 + PyYAML; byte-identical) --------
# Keys are dotted paths of identifier segments ([A-Za-z_][A-Za-z0-9_-]*). Both
# backends print: null or absent → nothing; booleans lower-cased (true/false);
# every other scalar as written (007, 0x1F, +5, 1.50 stay as they are); a
# list one scalar item per line (a null item as `null`, nested items
# skipped); a map nothing (use yaml_type or yaml_to_json). The PyYAML loader
# types plain scalars the way go-yaml v3 (mikefarah yq) does: true/True/TRUE
# and false/False/FALSE are the only booleans, integers are Go base-0
# literals (underscores dropped, int64 or uint64 range), floats follow the
# YAML 1.2 core pattern, and yes/no, sexagesimal values and timestamps stay
# strings. yaml_to_json writes numbers the way Go's encoding/json does.

# _sdlc_yaml_args FUNCTION FILE KEY — die on a missing FILE or a bad KEY.
_sdlc_yaml_args() {
  [[ -f "$2" ]] || die "$1: no such file: $2"
  [[ "$3" =~ ^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*)*$ ]] ||
    die "$1: invalid key: $3"
}

# _sdlc_yq_path KEY — the yq path of KEY (`.a.b`, `["a-b"]` for a segment
# that is not a plain identifier).
_sdlc_yq_path() {
  local seg out="" segs=()
  IFS=. read -r -a segs <<<"$1"
  for seg in "${segs[@]}"; do
    if [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      out+=".$seg"
    elif [[ -z "$out" ]]; then
      out=".[\"$seg\"]"
    else
      out+="[\"$seg\"]"
    fi
  done
  printf '%s' "$out"
}

# _sdlc_yq EXPR FILE — mikefarah yq; on failure logs the first error line.
_sdlc_yq() {
  _sdlc_err_first "yaml: $2: " yq "$1" "$2"
}

# _sdlc_yq_items FILE PATH — the scalar items of the list at PATH, one per
# line: a boolean lower-cased, a null item as `null`, nested items skipped.
# yq prints a scalar as written (`True`, `~`), so a list holding a boolean or
# a null is printed item by item (yq's stdin is /dev/null there, so it never
# reads the tag list); only basic yq operators are used.
_sdlc_yq_items() {
  local file="$1" path="$2" tags tag value i=0
  tags="$(_sdlc_yq "${path}[] | type" "$file")" || return 1
  if [[ "$tags" != *'!!bool'* && "$tags" != *'!!null'* ]]; then
    _sdlc_yq "${path}[] | select((type != \"!!map\") and (type != \"!!seq\"))" "$file"
    return
  fi
  while IFS= read -r tag; do
    case "$tag" in
      '!!map' | '!!seq') ;;
      '!!null') printf 'null\n' ;;
      '!!bool')
        value="$(_sdlc_yq "${path}[$i]" "$file" </dev/null)" || return 1
        printf '%s\n' "$(lower "$value")"
        ;;
      *) _sdlc_yq "${path}[$i]" "$file" </dev/null || return 1 ;;
    esac
    i=$((i + 1))
  done <<<"$tags"
}

# _sdlc_yaml_py MODE FILE [KEY] — the PyYAML backend. MODE ∈ parses get list
# is_list has type json. Exit 3 when PyYAML is missing; on a parse error (or,
# for json, a value Go's encoding/json refuses, such as .inf) it prints the
# first error line on stderr (except for parses) and exits 1. Scalars keep
# their source text, so no valid plain scalar (08, 0x1F, 1_000) can raise.
_sdlc_yaml_py() {
  _sdlc_py - "$@" <<'PY'
import decimal
import json
import math
import re
import sys

mode, path = sys.argv[1], sys.argv[2]
key = sys.argv[3] if len(sys.argv) > 3 else ""
try:
    import yaml
except ImportError:
    sys.exit(3)

TAG = "tag:yaml.org,2002:"
NULLS = ("", "~", "null", "Null", "NULL")
BOOLS = ("true", "True", "TRUE", "false", "False", "FALSE")
TRUTHY = ("true", "yes", "on", "y")
INF_NAN = (".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF",
           "-.inf", "-.Inf", "-.INF", ".nan", ".NaN", ".NAN")
GO_INT = re.compile(
    r"([-+]?)(0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[bB][01]+|0[0-7]*|[1-9][0-9]*)\Z")
FLOAT = re.compile(r"[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?\Z")
BASES = {"0x": 16, "0o": 8, "0b": 2}


# A scalar as written in the file; kind is the type yaml_type reports.
class Text(str):
    kind = "str"


class YBool(Text):
    kind = "bool"


class YInt(Text):
    kind = "int"


class YFloat(Text):
    kind = "float"


# go_int TEXT — strconv.ParseInt(TEXT, 0, 64), else ParseUint(TEXT, 0, 64);
# None when neither accepts TEXT (08 is not a base-0 integer).
def go_int(text):
    match = GO_INT.match(text)
    if not match:
        return None
    sign, digits = match.groups()
    base = BASES.get(digits[:2].lower())
    if base:
        value = int(digits[2:], base)
    else:
        value = int(digits, 8 if digits.startswith("0") else 10)
    if sign == "-":
        value = -value
    if -(2 ** 63) <= value < 2 ** 63 or (not sign and value < 2 ** 64):
        return value
    return None


def is_float(text):
    return bool(FLOAT.match(text)) and math.isfinite(float(text))


# plain_tag TEXT — the tag go-yaml v3 resolves for the plain scalar TEXT.
def plain_tag(text):
    if text in NULLS:
        return TAG + "null"
    if text in BOOLS:
        return TAG + "bool"
    if text in INF_NAN:
        return TAG + "float"
    if text == "<<":
        return TAG + "merge"
    if text[0] == ".":
        return TAG + ("float" if is_float(text) else "str")
    if text[0] in "+-0123456789":
        digits = text.replace("_", "")
        if go_int(digits) is not None:
            return TAG + "int"
        if is_float(digits):
            return TAG + "float"
    return TAG + "str"


class Loader(yaml.SafeLoader):
    def resolve(self, kind, value, implicit):
        if kind is yaml.ScalarNode and implicit[0]:
            return plain_tag(value)
        return super().resolve(kind, value, implicit)


def keep(cls):
    return lambda loader, node: cls(loader.construct_scalar(node))


def undefined(loader, node):
    if isinstance(node, yaml.ScalarNode):
        return Text(loader.construct_scalar(node))
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    return loader.construct_mapping(node, deep=True)


for name, cls in (("bool", YBool), ("int", YInt), ("float", YFloat),
                  ("timestamp", Text), ("binary", Text)):
    Loader.add_constructor(TAG + name, keep(cls))
Loader.add_constructor(None, undefined)
MISSING = object()


def walk(doc, parts):
    cur = doc
    for part in parts:
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return MISSING
    return cur


def text(value):
    if value is None:
        return "null"
    if isinstance(value, YBool):
        return value.lower()
    return str(value)


def items(value):
    for item in value:
        if not isinstance(item, (dict, list)):
            print(text(item))


# to_int / go_float — the numbers yq writes in JSON: an int parsed base 16
# after 0x, base 8 after 0o, else base 10; a float in Go encoding/json form
# (80.0 → 80, 1e-07 → 1e-7).
def to_int(value):
    try:
        if value.startswith(("0x", "0X")):
            return int(value[2:], 16)
        if value.startswith("0o"):
            return int(value[2:], 8)
        return int(value, 10)
    except ValueError:
        number = go_int(value.replace("_", ""))
        if number is None:
            raise ValueError("cannot unmarshal %r into an int" % str(value))
        return number


def go_float(number):
    if not math.isfinite(number):
        raise ValueError("json: unsupported value: %r" % number)
    size = abs(number)
    if size and (size < 1e-6 or size >= 1e21):
        return re.sub(r"e-0([0-9])\Z", r"e-\1", repr(number))
    out = format(decimal.Decimal(repr(number)), "f")
    return out.rstrip("0").rstrip(".") if "." in out else out


def string(value):
    out = json.dumps(value, ensure_ascii=False)
    return out.replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")


def to_json(value, depth=0):
    pad, end = "  " * (depth + 1), "\n" + "  " * depth
    if isinstance(value, dict):
        rows = [pad + string("null" if k is None else str(k)) + ": "
                + to_json(v, depth + 1) for k, v in value.items()]
        return "{\n" + ",\n".join(rows) + end + "}" if rows else "{}"
    if isinstance(value, list):
        rows = [pad + to_json(v, depth + 1) for v in value]
        return "[\n" + ",\n".join(rows) + end + "]" if rows else "[]"
    if value is None:
        return "null"
    if isinstance(value, YBool):
        return "true" if value.lower() in TRUTHY else "false"
    if isinstance(value, YInt):
        return str(to_int(value))
    if isinstance(value, YFloat):
        return go_float(float(value))
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return go_float(value)
    return string(str(value))


try:
    with open(path, encoding="utf-8") as handle:
        doc = yaml.load(handle, Loader=Loader)
    if mode == "json":
        out = to_json(doc) + "\n"
except Exception as exc:  # any parse, read or conversion error ends the call cleanly
    if mode != "parses":
        lines = str(exc).strip().splitlines() or [type(exc).__name__]
        sys.stderr.write(lines[0] + "\n")
    sys.exit(1)

parts = key.split(".") if key else []
if mode == "parses":
    sys.exit(0)
if mode == "json":
    sys.stdout.write(out)
    sys.exit(0)
if mode == "has":
    parent = walk(doc, parts[:-1])
    sys.exit(0 if isinstance(parent, dict) and parts[-1] in parent else 1)
value = walk(doc, parts)
if mode == "type":
    if value is MISSING:
        name = "absent"
    elif value is None:
        name = "null"
    elif isinstance(value, Text):
        name = value.kind
    elif isinstance(value, list):
        name = "list"
    elif isinstance(value, dict):
        name = "map"
    else:
        name = "str"
    print(name)
elif mode == "is_list":
    sys.exit(0 if isinstance(value, list) else 1)
elif mode == "list":
    if isinstance(value, list):
        items(value)
elif mode == "get":
    if isinstance(value, list):
        items(value)
    elif value is not MISSING and value is not None and not isinstance(value, dict):
        print(text(value))
PY
}

# _sdlc_yaml_python MODE FILE [KEY] — _sdlc_yaml_py with the error contract:
# a missing python3 or PyYAML dies with the toolchain message, a parse error
# is logged with the parser's first error line.
_sdlc_yaml_python() {
  local rc=0
  if ! command -v python3 >/dev/null 2>&1; then
    die "no YAML toolchain: install mikefarah yq v4, or python3 with PyYAML"
  fi
  _sdlc_err_first "yaml: $2: " _sdlc_yaml_py "$@" || rc=$?
  if ((rc == 3)); then
    die "no YAML toolchain: install mikefarah yq v4, or python3 with PyYAML"
  fi
  return "$rc"
}

# yaml_parses FILE — 0 when FILE parses, 1 when it does not (no diagnostics);
# dies when FILE is missing.
yaml_parses() {
  local file="${1-}" rc=0
  [[ -f "$file" ]] || die "yaml_parses: no such file: $file"
  if have_yq; then
    yq '.' "$file" >/dev/null 2>&1
  else
    command -v python3 >/dev/null 2>&1 || rc=3
    if ((rc == 0)); then
      _sdlc_yaml_py parses "$file" >/dev/null 2>&1 || rc=$?
    fi
    if ((rc == 3)); then
      die "no YAML toolchain: install mikefarah yq v4, or python3 with PyYAML"
    fi
    return "$rc"
  fi
}

# yaml_get FILE KEY — the value at the dotted KEY (see the section rules).
yaml_get() {
  local file="${1-}" key="${2-}" path tag value
  _sdlc_yaml_args yaml_get "$file" "$key"
  if ! have_yq; then
    _sdlc_yaml_python get "$file" "$key"
    return
  fi
  path="$(_sdlc_yq_path "$key")"
  tag="$(_sdlc_yq "$path | type" "$file")" || return 1
  case "$tag" in
    '!!null' | '!!map') return 0 ;;
    '!!seq') _sdlc_yq_items "$file" "$path" ;;
    '!!bool')
      # yq prints a boolean as written (True, FALSE); the contract is true/false.
      value="$(_sdlc_yq "$path" "$file")" || return 1
      printf '%s\n' "$(lower "$value")"
      ;;
    *) _sdlc_yq "$path | select(. != null)" "$file" ;;
  esac
}

# yaml_get_list FILE KEY — the scalar items of the list at KEY, one per line;
# nothing when KEY is absent or not a list.
yaml_get_list() {
  local file="${1-}" key="${2-}" path tag
  _sdlc_yaml_args yaml_get_list "$file" "$key"
  if ! have_yq; then
    _sdlc_yaml_python list "$file" "$key"
    return
  fi
  path="$(_sdlc_yq_path "$key")"
  tag="$(_sdlc_yq "$path | type" "$file")" || return 1
  if [[ "$tag" == '!!seq' ]]; then
    _sdlc_yq_items "$file" "$path"
  fi
}

# yaml_is_list FILE KEY — 0 when the value at KEY is a sequence.
yaml_is_list() {
  local file="${1-}" key="${2-}"
  _sdlc_yaml_args yaml_is_list "$file" "$key"
  if have_yq; then
    [[ "$(yq "$(_sdlc_yq_path "$key") | type" "$file" 2>/dev/null)" == '!!seq' ]]
  else
    _sdlc_yaml_python is_list "$file" "$key" 2>/dev/null
  fi
}

# yaml_has FILE KEY — 0 when KEY exists, even when its value is null.
yaml_has() {
  local file="${1-}" key="${2-}" parent=. leaf
  _sdlc_yaml_args yaml_has "$file" "$key"
  if ! have_yq; then
    _sdlc_yaml_python has "$file" "$key" 2>/dev/null
    return
  fi
  leaf="${key##*.}"
  if [[ "$key" == *.* ]]; then
    parent="$(_sdlc_yq_path "${key%.*}")"
  fi
  [[ "$(yq "$parent | has(\"$leaf\")" "$file" 2>/dev/null)" == true ]]
}

# yaml_type FILE KEY — one of null bool int float str list map absent.
yaml_type() {
  local file="${1-}" key="${2-}" tag
  _sdlc_yaml_args yaml_type "$file" "$key"
  if ! have_yq; then
    _sdlc_yaml_python type "$file" "$key"
    return
  fi
  if ! yaml_has "$file" "$key"; then
    printf 'absent\n'
    return 0
  fi
  tag="$(_sdlc_yq "$(_sdlc_yq_path "$key") | type" "$file")" || return 1
  case "$tag" in
    '!!null') printf 'null\n' ;;
    '!!bool') printf 'bool\n' ;;
    '!!int') printf 'int\n' ;;
    '!!float') printf 'float\n' ;;
    '!!seq') printf 'list\n' ;;
    '!!map') printf 'map\n' ;;
    *) printf 'str\n' ;;
  esac
}

# yaml_to_json FILE — the whole document as JSON (2-space indent) on stdout;
# exit 1 with the parser's first error line (logged) when FILE does not parse.
yaml_to_json() {
  local file="${1-}" rc=0
  [[ -f "$file" ]] || die "yaml_to_json: no such file: $file"
  if have_yq; then
    _sdlc_err_first "yaml: $file: " yq -o=json '.' "$file" || rc=$?
  else
    _sdlc_yaml_python json "$file" || rc=$?
  fi
  if ((rc != 0)); then
    return 1
  fi
}

# yaml_squote VALUE — VALUE as a single-quoted YAML scalar: ASCII control
# characters stripped, every `'` doubled.
yaml_squote() {
  local value
  value="$(printf '%s' "${1-}" | LC_ALL=C tr -d '\000-\037\177')"
  printf "'%s'\n" "${value//\'/\'\'}"
}

# --- JSON access (jq, else python3; identical output) --------------------------
# json_get FILE|- KEY — the value at the dotted KEY (object members only):
# null or absent → nothing; a string raw; any other value compact JSON; an
# array one element per line (each formatted the same way).
json_get() {
  local src="${1-}" key="${2-}" rc=0
  # shellcheck disable=SC2016 # $k and $p are jq variables
  local prog='reduce ($k | split("."))[] as $p (.; if type == "object" then .[$p] else null end) | select(. != null) | if type == "array" then .[] else . end'
  [[ "$src" == - || -f "$src" ]] || die "json_get: no such file: $src"
  [[ -n "$key" ]] || die "json_get: empty key"
  if have_jq; then
    if [[ "$src" == - ]]; then
      _sdlc_err_first "json_get: " jq -rc --arg k "$key" "$prog" || rc=$?
    else
      _sdlc_err_first "json_get: $src: " jq -rc --arg k "$key" "$prog" "$src" || rc=$?
    fi
  else
    _sdlc_err_first "json_get: $src: " _sdlc_py -c '
import json
import sys

src, key = sys.argv[1], sys.argv[2]
try:
    if src == "-":
        doc = json.load(sys.stdin)
    else:
        with open(src, encoding="utf-8") as handle:
            doc = json.load(handle)
except Exception as exc:  # malformed JSON or unreadable file
    sys.stderr.write((str(exc).splitlines() or ["invalid JSON"])[0] + "\n")
    sys.exit(1)
cur = doc
for part in key.split("."):
    cur = cur.get(part) if isinstance(cur, dict) else None


def emit(value):
    if isinstance(value, str):
        print(value)
    else:
        print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


if isinstance(cur, list):
    for item in cur:
        emit(item)
elif cur is not None:
    emit(cur)
' "$src" "$key" || rc=$?
  fi
  if ((rc != 0)); then
    return 1
  fi
}

# --- TOML access (python3 3.11+ tomllib) ------------------------------------------

# _sdlc_toml MODE FILE KEY — MODE ∈ get list has. Values: strings raw,
# booleans true/false, dates ISO 8601, tables and nested arrays compact JSON;
# an array one item per line.
_sdlc_toml() {
  local mode="$1" file="$2" key="$3" rc=0
  [[ -f "$file" ]] || die "toml_$mode: no such file: $file"
  [[ "$key" =~ ^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$ ]] || die "toml_$mode: invalid key: $key"
  command -v python3 >/dev/null 2>&1 || die "python3 3.11+ with tomllib is required"
  _sdlc_err_first "toml: $file: " _sdlc_py -c '
import datetime
import json
import sys

try:
    import tomllib
except ImportError:
    sys.exit(3)

mode, path, key = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, "rb") as handle:
        doc = tomllib.load(handle)
except Exception as exc:  # malformed TOML or unreadable file
    sys.stderr.write((str(exc).splitlines() or ["invalid TOML"])[0] + "\n")
    sys.exit(1)

cur = doc
found = True
for part in key.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        found = False
        break


def fmt(value):
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (datetime.datetime, datetime.date, datetime.time)):
        return value.isoformat()
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)
    return str(value)


if mode == "has":
    sys.exit(0 if found else 1)
if not found:
    sys.exit(0)
if isinstance(cur, list):
    for item in cur:
        print(fmt(item))
elif mode == "get":
    print(fmt(cur))
' "$mode" "$file" "$key" || rc=$?
  if ((rc == 3)); then
    die "python3 3.11+ with tomllib is required"
  fi
  return "$rc"
}

# toml_get FILE KEY — the value at the dotted KEY (arrays one item per line).
toml_get() {
  _sdlc_toml get "${1-}" "${2-}"
}

# toml_get_list FILE KEY — the items of the array at KEY; nothing otherwise.
toml_get_list() {
  _sdlc_toml list "${1-}" "${2-}"
}

# toml_has FILE KEY — 0 when KEY exists.
toml_has() {
  _sdlc_toml has "${1-}" "${2-}"
}

# --- project profile ---------------------------------------------------------------

# profile_path [DIR] — ${DIR:-$PWD}/.claude/rust-sdlc.yml.
profile_path() {
  printf '%s/.claude/rust-sdlc.yml\n' "${1:-$PWD}"
}

# profile_get FILE KEY [DEFAULT] — the value at KEY; DEFAULT only when KEY is
# absent or null (`false` and '' are values).
profile_get() {
  local file="${1-}" key="${2-}" default="${3-}" value
  value="$(yaml_get "$file" "$key")" || return 1
  if [[ -z "$value" ]]; then
    case "$(yaml_type "$file" "$key")" in
      null | absent) value="$default" ;;
      *) ;;
    esac
  fi
  printf '%s\n' "$value"
}

# profile_require FILE KEY — the value at KEY, or die naming the key when it
# is absent or null.
profile_require() {
  local file="${1-}" key="${2-}" value
  value="$(yaml_get "$file" "$key")" || return 1
  if [[ -z "$value" ]]; then
    case "$(yaml_type "$file" "$key")" in
      null | absent) die "profile: required key '$key' missing or null in $file" ;;
      *) ;;
    esac
  fi
  printf '%s\n' "$value"
}

# --- plugin and repository identity -------------------------------------------------

# resolve_plugin_root — CLAUDE_PLUGIN_ROOT when set (it must be a directory),
# else the directory two levels above this library.
resolve_plugin_root() {
  local lib_dir
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    [[ -d "$CLAUDE_PLUGIN_ROOT" ]] ||
      die "CLAUDE_PLUGIN_ROOT is not a directory: $CLAUDE_PLUGIN_ROOT"
    printf '%s\n' "$CLAUDE_PLUGIN_ROOT"
    return 0
  fi
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  (cd "$lib_dir/../.." && pwd)
}

# resolve_repo_slug [DIR] — owner/name of DIR's github.com origin (https,
# git@github.com: or ssh:// form, `.git` stripped, checked with is_slug), else
# `gh repo view --json nameWithOwner --jq .nameWithOwner` run in DIR; else
# return 1 with no output.
resolve_repo_slug() {
  local dir="${1:-.}" origin slug=""
  origin="$(git -C "$dir" remote get-url origin 2>/dev/null)" || origin=""
  case "$origin" in
    https://github.com/*) slug="${origin#https://github.com/}" ;;
    git@github.com:*) slug="${origin#git@github.com:}" ;;
    ssh://git@github.com/*) slug="${origin#ssh://git@github.com/}" ;;
    *) ;;
  esac
  slug="${slug%/}"
  slug="${slug%.git}"
  if ! is_slug "$slug"; then
    slug="$(cd "$dir" 2>/dev/null && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || return 1
    is_slug "$slug" || return 1
  fi
  printf '%s\n' "$slug"
}

# default_branch [DIR] — the target of refs/remotes/origin/HEAD, else `main`,
# else `master` (each as a local or an origin/ ref), else `main`.
default_branch() {
  local dir="${1:-.}" ref name
  ref="$(git -C "$dir" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)" || ref=""
  if [[ "$ref" == refs/remotes/origin/?* ]]; then
    printf '%s\n' "${ref#refs/remotes/origin/}"
    return 0
  fi
  for name in main master; do
    if git -C "$dir" show-ref --verify --quiet "refs/heads/$name" 2>/dev/null ||
      git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$name" 2>/dev/null; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  printf 'main\n'
}

# --- validators ----------------------------------------------------------------------

# is_kebab S [MAX] — ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ and at most MAX (50)
# characters.
is_kebab() {
  local s="${1-}" max="${2:-50}"
  is_uint "$max" || return 2
  [[ "$s" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || return 1
  ! num_gt "${#s}" "$max"
}

# is_slug S — owner/name: ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$.
is_slug() {
  [[ "${1-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
}

# is_semver S — MAJOR.MINOR.PATCH without leading zeros or suffixes.
is_semver() {
  [[ "${1-}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

# is_commit_subject S — one line `<type>(#N): <subject>` (FR-2), tighter than
# the template's hook: N ≥ 1 and a non-blank subject.
is_commit_subject() {
  local s="${1-}"
  [[ "$s" != *$'\n'* && "$s" != *$'\r'* ]] || return 1
  [[ "$s" =~ ^(feat|fix|refactor|build|chore|ci|docs|style|perf|test)\(#[1-9][0-9]*\):\ [^[:space:]].*$ ]]
}

# --- safe writes -----------------------------------------------------------------------

# safe_write_target PATH ROOT — 0 when PATH may be written: it is not a
# symlink and not a non-regular file, no directory between ROOT and PATH is a
# symlink (or a non-directory), PATH has no `..` component and its real
# location is inside the real path of ROOT. A relative PATH is taken from the
# physical working directory, which may be any directory inside ROOT. Missing
# parents are allowed (atomic_write creates them). A refusal logs the reason
# and returns 1.
safe_write_target() {
  local path="${1-}" root="${2-}" shown="${1-}" root_real here d existing="" real
  if [[ -z "$path" || ! -d "$root" ]]; then
    log_error "safe_write_target: needs PATH and an existing ROOT directory"
    return 1
  fi
  root_real="$(cd "$root" && pwd -P)" || return 1
  if [[ "$root" != / ]]; then
    root="${root%/}"
  fi
  case "/$path/" in
    */../*)
      log_error "refusing to write $shown: the path contains '..'"
      return 1
      ;;
  esac
  # Absolute from here on, so the parent walk below ends at ROOT or at /.
  if [[ "$path" != /* ]]; then
    here="$(pwd -P)" || return 1
    path="${here%/}/$path"
  fi
  if [[ -L "$path" ]]; then
    log_error "refusing to write $shown: it is a symbolic link"
    return 1
  fi
  if [[ -e "$path" && ! -f "$path" ]]; then
    log_error "refusing to write $shown: it is not a regular file"
    return 1
  fi
  d="$(dirname -- "$path")"
  while [[ "$d" != "$root" ]] && ! [[ -d "$d" && ! -L "$d" && "$d" -ef "$root" ]]; do
    if [[ -L "$d" ]]; then
      log_error "refusing to write $shown: the parent $d is a symbolic link"
      return 1
    fi
    if [[ -e "$d" && ! -d "$d" ]]; then
      log_error "refusing to write $shown: the parent $d is not a directory"
      return 1
    fi
    if [[ -z "$existing" && -d "$d" ]]; then
      existing="$d"
    fi
    if [[ "$d" == / ]]; then
      log_error "refusing to write $shown: it is outside $root"
      return 1
    fi
    d="$(dirname -- "$d")"
  done
  real="$(cd "${existing:-$d}" && pwd -P)" || return 1
  if [[ "$root_real" != / && "$real" != "$root_real" && "$real" != "$root_real"/* ]]; then
    log_error "refusing to write $shown: it is outside $root"
    return 1
  fi
}

# atomic_write PATH — stdin into PATH through a same-directory mktemp file
# and `mv -f`; an existing file keeps its mode, a new one gets 0666 & ~umask.
# The parent directory is created when missing (check it first with
# safe_write_target).
atomic_write() {
  local path="${1-}" dir base tmp mode
  [[ -n "$path" ]] || die "atomic_write: needs PATH"
  dir="$(dirname -- "$path")"
  base="$(basename -- "$path")"
  mkdir -p -- "$dir" || return 1
  tmp="$(mktemp "$dir/.$base.XXXXXX")" || return 1
  if ! cat >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if [[ -e "$path" ]]; then
    if ! _sdlc_py -c 'import os, stat, sys
os.chmod(sys.argv[2], stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$path" "$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
  else
    mode="$(printf '%04o' "$((8#666 & ~8#$(umask)))")"
    if ! chmod "$mode" "$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
  fi
  if ! mv -f -- "$tmp" "$path"; then
    rm -f -- "$tmp"
    return 1
  fi
}

# --- template documents and the claude CLI ------------------------------------------------

# human_gated_labels [DIR] — library only. Parses the "Labels to create"
# table of DIR/docs/repository-settings.md and
# DIR/docs/repository-settings-service.md (both sentence forms: "without it
# the job `<j>` fails" and "without it the jobs `<a>` and `<b>` fail"), maps
# each job id to its check name through the `| Job | Check name |` tables of
# both documents and prints `<label>\t<check name>` per pair, in document
# order. A job id with no table row is reported with log_warn. Absent
# documents print nothing.
human_gated_labels() {
  local dir="${1:-.}"
  [[ -d "$dir" ]] || die "human_gated_labels: no such directory: $dir"
  _sdlc_py - "$dir" <<'PY'
import os
import re
import sys

CTRL = re.compile(r"[\x00-\x1f\x7f]")
SENTENCE = re.compile(r"without it the jobs? (.+?) fails?\b")


def clean(text):
    return CTRL.sub("", text).strip().strip("`").strip()


jobs = {}
labels = []
for name in ("repository-settings.md", "repository-settings-service.md"):
    try:
        with open(os.path.join(sys.argv[1], "docs", name), encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError:
        continue
    section = ""
    header = None
    for line in lines:
        if line.startswith("## "):
            section = line[3:].strip().lower()
            header = None
            continue
        row = line.strip()
        if not row.startswith("|"):
            header = None
            continue
        cells = [cell.strip() for cell in row.strip("|").split("|")]
        if header is None:
            header = [cell.lower() for cell in cells]
            continue
        if all(set(cell) <= set("-: ") for cell in cells):
            continue
        if header[:2] == ["job", "check name"] and len(cells) >= 2:
            checks = jobs.setdefault(clean(cells[0]), [])
            if clean(cells[1]) not in checks:
                checks.append(clean(cells[1]))
        elif section == "labels to create" and header[:1] == ["label"] and len(cells) >= 2:
            match = SENTENCE.search(" ".join(cells[1:]))
            if match:
                labels.append((clean(cells[0]), re.findall(r"`([^`]+)`", match.group(1))))

seen = set()
for label, ids in labels:
    for job in ids:
        job = clean(job)
        if job not in jobs:
            sys.stderr.write(
                "[rust-sdlc][WARN] human_gated_labels: job '%s' of label '%s' has no row "
                "in the job tables\n" % (job, label))
            continue
        for check in jobs[job]:
            if (label, check) not in seen:
                seen.add((label, check))
                print("%s\t%s" % (label, check))
PY
}

# claude_supports_restricted — `claude --help` lists `--restricted`.
claude_supports_restricted() {
  local help
  help="$(claude --help 2>/dev/null)" || help=""
  grep -qE -- '(^|[^[:alnum:]-])--restricted([^[:alnum:]-]|$)' <<<"$help"
}

# --- library CLI (ADR-15) -------------------------------------------------------------------

# _sdlc_dispatch NAME [ARG...] — executed mode only: run NAME when it is one
# of the 17 ADR-15 names and defined, under `set -euo pipefail`, and exit
# with its status; otherwise print the library refusal and exit 64.
_sdlc_dispatch() {
  local name="${1-}"
  case "$name" in
    validate_context_name | resume_point | derive_issue_number | is_commit_subject | \
      redact | state_cache_update | state_comment_body | ledger_write | hooks_active | \
      commit_msg_file | wait_log | http_probe | protected_changes | \
      ralph_fix_plan_prepare | ralph_fix_plan_restore | ralph_agent_md_patch | \
      ralph_breaker_state) ;;
    *) name="" ;;
  esac
  if [[ -z "$name" ]] || ! declare -F "$name" >/dev/null; then
    printf 'common.sh is a library; source it instead of executing\n' >&2
    exit 64
  fi
  shift
  set -euo pipefail
  "$name" "$@"
  exit "$?"
}

# section: dispatch (keep last)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  _sdlc_dispatch "$@"
fi
