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

# _sdlc_json_go — re-emit the JSON document on stdin with the PyYAML
# backend's writer (2-space indent, the same string escaping, numbers in Go
# encoding/json form), so both backends print the same bytes. mikefarah yq
# keeps a float's YAML spelling (8.0, 1.50, 1e3) and turns an int beyond
# int64 into a float (3e+19); this prints 8, 1.5, 1000 and
# 30000000000000000000. Unparsable input or a non-finite number exits 1 with
# one error line on stderr.
_sdlc_json_go() {
  local prog
  prog="$(
    cat <<'JSONGO'
import decimal
import json
import math
import re
import sys


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
        rows = [pad + string(k) + ": " + to_json(v, depth + 1)
                for k, v in value.items()]
        return "{\n" + ",\n".join(rows) + end + "}" if rows else "{}"
    if isinstance(value, list):
        rows = [pad + to_json(v, depth + 1) for v in value]
        return "[\n" + ",\n".join(rows) + end + "]" if rows else "[]"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return go_float(value)
    return string(value)


try:
    doc = json.loads(sys.stdin.read())
    sys.stdout.write(to_json(doc) + "\n")
except Exception as exc:  # any parse or conversion error ends the call cleanly
    lines = str(exc).strip().splitlines() or [type(exc).__name__]
    sys.stderr.write(lines[0] + "\n")
    sys.exit(1)
JSONGO
  )"
  _sdlc_py -c "$prog"
}

# yaml_to_json FILE — the whole document as JSON (2-space indent) on stdout;
# exit 1 with the parser's first error line (logged) when FILE does not parse.
# On the yq path the output goes through _sdlc_json_go when python3 exists,
# so both backends print the same bytes.
yaml_to_json() {
  local file="${1-}" rc=0 json
  [[ -f "$file" ]] || die "yaml_to_json: no such file: $file"
  if have_yq; then
    json="$(_sdlc_err_first "yaml: $file: " yq -o=json '.' "$file")" || rc=$?
    if ((rc == 0)); then
      if command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "$json" | _sdlc_err_first "yaml: $file: " _sdlc_json_go || rc=$?
      else
        printf '%s\n' "$json"
      fi
    fi
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

# section: command helpers

# Dispatcher functions that commands and agents call through the plugin-root
# allow entry (ADR-15): issue derivation and commit message files (FR-2,
# ADR-27), hook status (Git rules), log polling (ADR-13), loopback HTTP probes,
# protected-change detection (ADR-25) and context-name validation (FR-14).
# Each validates its arguments (exit 2 on a malformed one, ADR-23), writes only
# under target/rust-sdlc/ and never writes git configuration.

# --- private helpers -----------------------------------------------------------------

# _ch_clean TEXT — TEXT without ASCII control characters (no newline added).
_ch_clean() {
  printf '%s' "${1-}" | LC_ALL=C tr -d '\000-\037\177'
}

# _ch_printable TEXT — 0 when TEXT holds printable ASCII only (0x20 to 0x7e),
# counted in bytes, so a CR, a newline or a non-ASCII byte never passes.
_ch_printable() {
  local rest
  rest="$(printf '%s' "${1-}" | LC_ALL=C tr -d ' -~' | LC_ALL=C wc -c)" || return 1
  [[ "${rest//[[:space:]]/}" == 0 ]]
}

# _ch_bytes TEXT — the byte length of TEXT.
_ch_bytes() {
  local n
  n="$(printf '%s' "${1-}" | LC_ALL=C wc -c)" || return 1
  printf '%s\n' "${n//[[:space:]]/}"
}

# _ch_resolved_under PATH DIR... — 0 when the real path of PATH lies below
# <real working directory>/DIR for one DIR. The DIRs are joined to the working
# directory without following links, so a link inside them (or a linked
# `target`) never leads outside; PATH need not exist.
_ch_resolved_under() {
  _sdlc_py -c '
import os
import sys

real = os.path.realpath(sys.argv[1])
cwd = os.path.realpath(os.getcwd())
for name in sys.argv[2:]:
    if real.startswith(os.path.join(cwd, name).rstrip(os.sep) + os.sep):
        sys.exit(0)
sys.exit(1)
' "$@"
}

# _ch_issue N — print N without leading zeros; 1 (no output) when N is 0.
_ch_issue() {
  local n
  n="$(strip_zeros "${1-}")"
  [[ "$n" != 0 ]] || return 1
  printf '%s\n' "$n"
}

# --- issue number and commit message file (FR-2, ADR-27) -------------------------------

# derive_issue_number [--handle N] [--title T] [--branch B] [--body TEXT] —
# the issue number of the first source that yields one, in this order: the
# handle (^[1-9][0-9]*$), the PR title (^[a-z]+\(#([0-9]+)\):), the branch
# (^[a-z]+/([0-9]+)-) and the PR body ((^|[^A-Za-z])Closes #([0-9]+)). An
# empty or non-matching source yields nothing; a captured number is printed
# without leading zeros and a captured 0 yields nothing. A PR number is never
# an input (Git rules). Returns 1 with no output when no source yields a
# number, 2 on a usage error.
derive_issue_number() {
  local handle="" title="" branch="" body=""
  local re_title='^[a-z]+\(#([0-9]+)\):' re_branch='^[a-z]+/([0-9]+)-'
  local re_body='(^|[^A-Za-z])Closes #([0-9]+)'
  while (($#)); do
    case "$1" in
      --handle | --title | --branch | --body)
        if (($# < 2)); then
          log_error "derive_issue_number: $1 needs a value"
          return 2
        fi
        case "$1" in
          --handle) handle="$2" ;;
          --title) title="$2" ;;
          --branch) branch="$2" ;;
          *) body="$2" ;;
        esac
        shift 2
        ;;
      *)
        log_error "derive_issue_number: unknown argument: $(_ch_clean "$1") (usage: derive_issue_number [--handle N] [--title T] [--branch B] [--body TEXT])"
        return 2
        ;;
    esac
  done
  if [[ "$handle" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$handle"
    return 0
  fi
  if [[ "$title" =~ $re_title ]] && _ch_issue "${BASH_REMATCH[1]}"; then
    return 0
  fi
  if [[ "$branch" =~ $re_branch ]] && _ch_issue "${BASH_REMATCH[1]}"; then
    return 0
  fi
  if [[ "$body" =~ $re_body ]] && _ch_issue "${BASH_REMATCH[2]}"; then
    return 0
  fi
  return 1
}

# commit_msg_file SUBJECT — validates SUBJECT with is_commit_subject (else exit
# 1, nothing written), writes SUBJECT plus a newline atomically to
# target/rust-sdlc/tmp/commit-<utc_stamp>.txt below the working directory (the
# repository root) and prints that relative path for `git commit -F <path>`.
# More than one argument exits 2.
commit_msg_file() {
  local subject="${1-}" path stamp
  if (($# > 1)); then
    log_error "commit_msg_file: expected one SUBJECT argument, got $# (usage: commit_msg_file SUBJECT)"
    return 2
  fi
  if ! is_commit_subject "$subject"; then
    log_error "commit_msg_file: not a commit subject of the form <type>(#<N>): <subject>: $(_ch_clean "$subject")"
    return 1
  fi
  stamp="$(utc_stamp)" || return 1
  path="target/rust-sdlc/tmp/commit-$stamp.txt"
  safe_write_target "$path" "$PWD" || return 1
  printf '%s\n' "$subject" | atomic_write "$path" || return 1
  printf '%s\n' "$path"
}

# --- hook status (Git rules) -----------------------------------------------------------

# hooks_active [DIR] — reads `git config --local --get core.hooksPath` in DIR
# (default .) and prints one line: `HOOKS: active` (exit 0) when the value is
# exactly `.githooks` and .githooks/commit-msg, .githooks/pre-commit and
# .githooks/pre-push of the work tree root are executable files; otherwise
# `HOOKS: unset` (no local value; a global-only value is unset), `HOOKS:
# foreign <value>` or `HOOKS: missing <file>`, each exit 1. Reads only; DIR
# that is not a directory or not in a git work tree exits 2.
hooks_active() {
  local dir="${1:-.}" top value="" rc=0 hook shown
  if (($# > 1)); then
    log_error "hooks_active: too many arguments (usage: hooks_active [DIR])"
    return 2
  fi
  if [[ ! -d "$dir" ]]; then
    log_error "hooks_active: no such directory: $(_ch_clean "$dir")"
    return 2
  fi
  if ! top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$top" ]]; then
    log_error "hooks_active: not inside a git work tree: $(_ch_clean "$dir")"
    return 2
  fi
  value="$(git -C "$dir" config --local --get core.hooksPath 2>/dev/null)" || rc=$?
  if ((rc != 0)); then
    printf 'HOOKS: unset\n'
    return 1
  fi
  if [[ "$value" != .githooks ]]; then
    shown="$(_ch_clean "$value")"
    printf 'HOOKS: foreign %s\n' "${shown:-"''"}"
    return 1
  fi
  for hook in commit-msg pre-commit pre-push; do
    if [[ ! -f "$top/.githooks/$hook" || ! -x "$top/.githooks/$hook" ]]; then
      printf 'HOOKS: missing .githooks/%s\n' "$hook"
      return 1
    fi
  done
  printf 'HOOKS: active\n'
}

# --- background log polling (ADR-13) ---------------------------------------------------

# _ch_log_finished LOG — 0 when the last line of LOG ends with
# RUST_SDLC_EXIT=<n> (control characters ignored).
_ch_log_finished() {
  local last
  [[ -f "$1" ]] || return 1
  last="$(tail -n 1 -- "$1" 2>/dev/null | LC_ALL=C tr -d '\000-\011\013-\037\177')" || return 1
  [[ "$last" =~ RUST_SDLC_EXIT=[0-9]+$ ]]
}

# _ch_log_report LOG ELAPSED — the last 40 lines of LOG without control
# characters, then the status line: RUST_SDLC_EXIT=<n> (return 0; the log's own
# last line, split off when the command's output lacked a final newline) or
# `WAITING: <log> (<elapsed>s)` (return 1).
_ch_log_report() {
  local log="$1" elapsed="$2" text="" last body code
  if [[ -f "$log" ]]; then
    text="$(tail -n 40 -- "$log" 2>/dev/null | LC_ALL=C tr -d '\000-\011\013-\037\177')" || text=""
  fi
  last="${text##*$'\n'}"
  if [[ "$last" =~ RUST_SDLC_EXIT=([0-9]+)$ ]]; then
    code="${BASH_REMATCH[1]}"
    body="${text%"RUST_SDLC_EXIT=$code"}"
    body="${body%$'\n'}"
    if [[ -n "$body" ]]; then
      printf '%s\n' "$body"
    fi
    printf 'RUST_SDLC_EXIT=%s\n' "$code"
    return 0
  fi
  if [[ -n "$text" ]]; then
    printf '%s\n' "$text"
  fi
  printf 'WAITING: %s (%ss)\n' "$(_ch_clean "$log")" "$elapsed"
  return 1
}

# wait_log LOG [MAX_SECONDS] — waits for a background command's log (the
# ADR-13 wrapper ends it with RUST_SDLC_EXIT=<n>). LOG must resolve below
# target/rust-sdlc/logs/ or target/rust-sdlc/new-service/ of the working
# directory and MAX_SECONDS must be 30 to 540 (default 110), else exit 2. The
# last line is checked at once and then every 30 s (the final wait is
# shortened to end at MAX); the output is the last 40 lines (control
# characters stripped) ending with RUST_SDLC_EXIT=<n> (exit 0) or followed by
# `WAITING: <log> (<elapsed>s)` (exit 1). A LOG not written yet counts as
# running.
wait_log() {
  local log="${1-}" max="${2-110}" elapsed=0 step
  if (($# < 1 || $# > 2)) || [[ -z "$log" ]]; then
    log_error "wait_log: needs LOG (usage: wait_log LOG [MAX_SECONDS])"
    return 2
  fi
  if ! is_uint "$max" || num_lt "$max" 30 || num_gt "$max" 540; then
    log_error "wait_log: MAX_SECONDS must be an integer from 30 to 540: $(_ch_clean "$max")"
    return 2
  fi
  max="$(strip_zeros "$max")"
  if ! _ch_resolved_under "$log" target/rust-sdlc/logs target/rust-sdlc/new-service; then
    log_error "wait_log: $(_ch_clean "$log") is not below target/rust-sdlc/logs/ or target/rust-sdlc/new-service/"
    return 2
  fi
  if [[ -e "$log" && ! -f "$log" ]]; then
    log_error "wait_log: $(_ch_clean "$log") is not a regular file"
    return 2
  fi
  while ! _ch_log_finished "$log" && num_lt "$elapsed" "$max"; do
    step=30
    if ((max - elapsed < step)); then
      step=$((max - elapsed))
    fi
    sleep "$step"
    elapsed=$((elapsed + step))
  done
  _ch_log_report "$log" "$elapsed"
}

# --- loopback HTTP probe ---------------------------------------------------------------

# _ch_http_exchange METHOD FEED CURL_ARGV... — runs CURL_ARGV (stdin passed
# through when FEED is `stdin`, else /dev/null) and renders its `-i` output
# from the pipe, so nothing is written to disk: `HTTP_STATUS: <code>`, the
# header lines of the final (non-1xx) response without control characters, a
# blank line and at most 65536 bytes of body (control characters other than
# tab and newline stripped; a truncation is logged). Without a response (a
# non-zero curl status, or no status line) it logs the transport failure with
# curl's first stderr line and exits 1. For HEAD a complete header block is
# the response even when curl then waits for a body that never comes
# (statuses 18 and 28: `-X HEAD` keeps curl reading).
_ch_http_exchange() {
  _sdlc_py -c '
import re
import subprocess
import sys

method, feed, argv = sys.argv[1], sys.argv[2], sys.argv[3:]
LIMIT = 65536
CTRL = re.compile(rb"[\x00-\x1f\x7f]")


def failure(status, detail):
    detail = CTRL.sub(b"", detail.strip().split(b"\n")[0]).decode("utf-8", "replace")
    sys.stderr.write("[rust-sdlc][ERROR] http_probe: transport failure for %s %s (curl exit %s)%s\n"
                     % (method, argv[-1], status, ": " + detail if detail else ""))
    sys.exit(1)


try:
    proc = subprocess.run(argv, stdin=sys.stdin if feed == "stdin" else subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
except OSError as exc:
    failure("-", str(exc).encode())
data, status = proc.stdout, proc.returncode
STATUS = re.compile(rb"HTTP/[0-9.]+ ([0-9]{3})(?:[ \t]|\Z)")
BLANK = re.compile(rb"\r?\n\r?\n")
pos = 0
while True:
    end = BLANK.search(data, pos)
    head = data[pos:end.start()] if end else data[pos:]
    lines = [line.rstrip(b"\r") for line in head.split(b"\n")]
    match = STATUS.match(lines[0])
    if not match:
        failure(status, proc.stderr or b"no HTTP status line in the reply")
    code = int(match.group(1))
    if end and 100 <= code < 200 and code != 101:
        pos = end.end()
        continue
    break
if status != 0 and not (method == "HEAD" and status in (18, 28) and end is not None):
    failure(status, proc.stderr)
body = data[end.end():] if end else b""
if len(body) > LIMIT:
    sys.stderr.write("[rust-sdlc][WARN] http_probe: body truncated to %d of %d bytes\n"
                     % (LIMIT, len(body)))
    body = body[:LIMIT]
body = re.sub(rb"[\x00-\x08\x0b-\x1f\x7f]", b"", body)
out = sys.stdout.buffer
out.write(b"HTTP_STATUS: %d\n" % code)
for line in lines:
    out.write(CTRL.sub(b"", line) + b"\n")
out.write(b"\n")
out.write(body)
if body and not body.endswith(b"\n"):
    out.write(b"\n")
' "$@"
}

# http_probe METHOD PATH [--header 'K: V']... [--body TEXT | --body-file F] —
# one HTTP request to the profile's service.base_url (validated here, the
# only profile key read: ^http://(localhost|127\.0\.0\.1):<port>$, port 1 to
# 65535) plus PATH, through exactly
#   curl --noproxy '*' --proto =http --max-time 10 -sS -i -X <METHOD> [-H …]
#        [--data-binary @-|@F] -- <url>
# METHOD ∈ GET HEAD POST PUT PATCH DELETE OPTIONS; PATH must match
# ^/[A-Za-z0-9._~%/?&=:,+-]*$; at most 10 headers, each printable ASCII
# matching ^[A-Za-z0-9-]+: ?[ -~]*$; --body at most 16 KiB (sent on stdin);
# F must resolve below target/rust-sdlc/tmp/. Every value lands in one argv
# slot after its flag and the URL follows `--`, so no argument adds a curl
# option or a second URL. Prints HTTP_STATUS: <code>, the response headers
# and at most 64 KiB of body. Exit 0 on any HTTP response, 1 on a transport
# failure or a missing or invalid service.base_url, 2 on a rejected argument.
http_probe() {
  local method="${1-}" path="${2-}" body="" body_file="" body_mode="" headers_n=0
  local re_path='^/[A-Za-z0-9._~%/?&=:,+-]*$' re_header='^[A-Za-z0-9-]+: ?[ -~]*$'
  local usage="(usage: http_probe METHOD PATH [--header 'K: V']... [--body TEXT | --body-file F])"
  local profile base port url
  local -a headers=() argv=()
  if (($# < 2)); then
    log_error "http_probe: needs METHOD and PATH $usage"
    return 2
  fi
  shift 2
  case "$method" in
    GET | HEAD | POST | PUT | PATCH | DELETE | OPTIONS) ;;
    *)
      log_error "http_probe: method not allowed: $(_ch_clean "$method") (GET HEAD POST PUT PATCH DELETE OPTIONS)"
      return 2
      ;;
  esac
  if ! _ch_printable "$path" || [[ ! "$path" =~ $re_path ]]; then
    log_error "http_probe: PATH must match $re_path: $(_ch_clean "$path")"
    return 2
  fi
  while (($#)); do
    case "$1" in
      --header | --body | --body-file)
        if (($# < 2)); then
          log_error "http_probe: $1 needs a value $usage"
          return 2
        fi
        ;;
      *)
        log_error "http_probe: unknown argument: $(_ch_clean "$1") $usage"
        return 2
        ;;
    esac
    case "$1" in
      --header)
        if ! _ch_printable "$2" || [[ ! "$2" =~ $re_header ]]; then
          log_error "http_probe: header must be printable ASCII matching $re_header: $(_ch_clean "$2")"
          return 2
        fi
        headers_n=$((headers_n + 1))
        if ((headers_n > 10)); then
          log_error "http_probe: at most 10 headers"
          return 2
        fi
        headers+=(-H "$2")
        ;;
      *)
        if [[ -n "$body_mode" ]]; then
          log_error "http_probe: give one --body or one --body-file $usage"
          return 2
        fi
        if [[ "$1" == --body ]]; then
          body_mode='text'
          body="$2"
          if num_gt "$(_ch_bytes "$body")" 16384; then
            log_error "http_probe: --body is larger than 16 KiB"
            return 2
          fi
        else
          body_mode='file'
          body_file="$2"
          if ! _ch_resolved_under "$body_file" target/rust-sdlc/tmp || [[ ! -f "$body_file" || ! -r "$body_file" ]]; then
            log_error "http_probe: --body-file must be a readable file below target/rust-sdlc/tmp/: $(_ch_clean "$body_file")"
            return 2
          fi
        fi
        ;;
    esac
    shift 2
  done
  profile="$(profile_path)"
  if [[ ! -f "$profile" ]]; then
    log_error "http_probe: no profile at .claude/rust-sdlc.yml"
    return 1
  fi
  base="$(yaml_get "$profile" service.base_url)" || return 1
  port=""
  if [[ "$base" =~ ^http://(localhost|127\.0\.0\.1):([0-9]+)$ ]]; then
    port="${BASH_REMATCH[2]}"
  fi
  if [[ -z "$port" ]] || num_lt "$port" 1 || num_gt "$port" 65535; then
    log_error "http_probe: service.base_url must match ^http://(localhost|127\\.0\\.0\\.1):<port>$: $(_ch_clean "$base")"
    return 1
  fi
  url="$base$path"
  argv=(--noproxy '*' --proto '=http' --max-time 10 -sS -i -X "$method" "${headers[@]}")
  case "$body_mode" in
    text) argv+=(--data-binary @-) ;;
    file) argv+=(--data-binary "@$body_file") ;;
    *) ;;
  esac
  argv+=(-- "$url")
  if [[ "$body_mode" == text ]]; then
    _ch_http_exchange "$method" stdin curl "${argv[@]}" < <(printf '%s' "$body")
  else
    _ch_http_exchange "$method" none curl "${argv[@]}"
  fi
}

# --- branch guard (ADR-25) ---------------------------------------------------------------

# protected_changes BASE_SHA — run inside the repository. Reads the `files`
# and `directories` lists of protected-config.toml (python3 tomllib; the
# BASE_SHA version when it exists there, so a branch cannot drop an entry,
# else the working tree's) and matches them against `git diff --name-only
# --no-renames BASE_SHA` plus the untracked files: one `PROTECTED: <path>
# (<commit>|working tree)` line per changed protected path (<commit> = the
# newest commit since BASE_SHA that touched it, when the change is
# committed). Then `PROFILE_CHANGED: .claude/rust-sdlc.yml` when the profile
# exists at BASE_SHA and the working tree differs (a profile absent at
# BASE_SHA is exempt). `INFO: no protected-config.toml` when the list exists
# nowhere (profile check only). Exit 0 none, 1 any (or the list cannot be
# read), 2 usage (no single argument, a leading `-`, not a commit, not in a
# work tree).
protected_changes() {
  local base="${1-}" top sha rc=0
  if (($# != 1)) || [[ -z "$base" || "$base" == -* ]]; then
    log_error "protected_changes: needs one BASE_SHA argument (usage: protected_changes BASE_SHA)"
    return 2
  fi
  if ! top="$(git rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$top" ]]; then
    log_error "protected_changes: not inside a git work tree"
    return 2
  fi
  if ! sha="$(git -C "$top" rev-parse --verify --quiet "$base^{commit}" 2>/dev/null)" || [[ -z "$sha" ]]; then
    log_error "protected_changes: not a commit: $(_ch_clean "$base")"
    return 2
  fi
  command -v python3 >/dev/null 2>&1 || die "python3 3.11+ with tomllib is required"
  _sdlc_py - "$top" "$sha" <<'PY' || rc=$?
import os
import re
import subprocess
import sys

try:
    import tomllib
except ImportError:
    sys.exit(3)

top, sha = sys.argv[1], sys.argv[2]
LIST = "protected-config.toml"
PROFILE = ".claude/rust-sdlc.yml"
CTRL = re.compile(r"[\x00-\x1f\x7f]")


def git(*args, check=True):
    proc = subprocess.run(["git", "-C", top, *args], capture_output=True)
    if check and proc.returncode != 0:
        first = proc.stderr.decode("utf-8", "replace").strip().splitlines() or ["exit %d" % proc.returncode]
        sys.stderr.write("[rust-sdlc][ERROR] protected_changes: git %s failed: %s\n" % (args[0], first[0]))
        sys.exit(4)
    return proc


def names(raw):
    return {item.decode("utf-8", "surrogateescape") for item in raw.split(b"\0") if item}


def base_blob(path):
    proc = git("cat-file", "blob", "%s:%s" % (sha, path), check=False)
    return proc.stdout if proc.returncode == 0 else None


def work_file(path):
    try:
        with open(os.path.join(top, path), "rb") as handle:
            return handle.read()
    except OSError:
        return None


def shown(path):
    return CTRL.sub("", path.encode("utf-8", "surrogateescape").decode("utf-8", "replace"))


listing = base_blob(LIST)
if listing is None:
    listing = work_file(LIST)
files, prefixes = set(), []
if listing is None:
    print("INFO: no protected-config.toml")
else:
    try:
        doc = tomllib.loads(listing.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        sys.stderr.write("[rust-sdlc][ERROR] protected_changes: cannot parse %s: %s\n" % (LIST, exc))
        sys.exit(4)
    for entry in doc.get("files", []):
        if isinstance(entry, str) and entry.strip("/"):
            files.add(entry.removeprefix("./").rstrip("/"))
    for entry in doc.get("directories", []):
        if isinstance(entry, str) and entry.strip("/"):
            prefixes.append(entry.removeprefix("./").rstrip("/"))

changed = names(git("diff", "--name-only", "--no-renames", "-z", sha, "--").stdout)
changed |= names(git("ls-files", "--others", "--exclude-standard", "-z").stdout)
committed = names(git("diff", "--name-only", "--no-renames", "-z", sha, "HEAD", "--").stdout)
hits = 0
for path in sorted(changed):
    if not (path in files or any(path == p or path.startswith(p + "/") for p in prefixes)):
        continue
    where = "working tree"
    if path in committed:
        where = git("log", "-1", "--format=%h", "--abbrev=7", "%s..HEAD" % sha, "--", path).stdout.decode().strip()
        where = where or git("rev-parse", "--short=7", "HEAD").stdout.decode().strip()
    print("PROTECTED: %s (%s)" % (shown(path), where))
    hits += 1
before = base_blob(PROFILE)
if before is not None and work_file(PROFILE) != before:
    print("PROFILE_CHANGED: %s" % PROFILE)
    hits += 1
sys.exit(1 if hits else 0)
PY
  case "$rc" in
    0 | 1) return "$rc" ;;
    3) die "python3 3.11+ with tomllib is required" ;;
    *) return 1 ;;
  esac
}

# --- bounded-context names (FR-14) ---------------------------------------------------------

# _ch_package_names ROOT MEMBER... — one line per MEMBER: the `package.name`
# of ROOT/MEMBER/Cargo.toml (python3 tomllib), empty when it is unreadable.
# Exit 3 without tomllib.
_ch_package_names() {
  _sdlc_py -c '
import os
import sys

try:
    import tomllib
except ImportError:
    sys.exit(3)
root = sys.argv[1]
for member in sys.argv[2:]:
    name = ""
    try:
        with open(os.path.join(root, member, "Cargo.toml"), "rb") as handle:
            package = tomllib.load(handle).get("package")
        if isinstance(package, dict) and isinstance(package.get("name"), str):
            name = package["name"]
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError):
        pass
    print(" ".join(name.split()))
' "$@"
}

# validate_context_name GROUP CONTEXT [ROOT] — the four FR-14 rules over the
# live tree of ROOT (default .), mirroring `cargo xtask new-context`; the
# profile is never read. In order: name-format (both names match
# ^[a-z][a-z0-9]*(-[a-z0-9]+)*$), reserved-context (CONTEXT is one of shared
# service xtask test-support e2e-tests; a reserved word is a legal group),
# context-exists (crates/<CONTEXT> or any crates/*/<CONTEXT> is a directory)
# and member-exists (a `[workspace].members` entry ends in
# <CONTEXT>/{domain,application,infrastructure}, or a member's package.name is
# <CONTEXT>-{domain,application,infrastructure}). Prints nothing and returns 0
# for a valid name, else exactly one `REFUSED: <rule> <detail>` line and
# returns 1. Exit 2 on a usage error or a ROOT without a readable Cargo.toml.
validate_context_name() {
  local group="${1-}" context="${2-}" root="${3:-.}" re='^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
  local found="" dir list names rc=0 i member package
  local -a members=() packages=()
  if (($# < 2 || $# > 3)); then
    log_error "validate_context_name: needs GROUP and CONTEXT (usage: validate_context_name GROUP CONTEXT [ROOT])"
    return 2
  fi
  if [[ ! "$group" =~ $re ]]; then
    printf "REFUSED: name-format group '%s' does not match %s\n" "$(_ch_clean "$group")" "$re"
    return 1
  fi
  if [[ ! "$context" =~ $re ]]; then
    printf "REFUSED: name-format context '%s' does not match %s\n" "$(_ch_clean "$context")" "$re"
    return 1
  fi
  case "$context" in
    shared | service | xtask | test-support | e2e-tests)
      printf "REFUSED: reserved-context '%s' is reserved (shared service xtask test-support e2e-tests)\n" "$context"
      return 1
      ;;
    *) ;;
  esac
  if [[ ! -f "$root/Cargo.toml" || ! -r "$root/Cargo.toml" ]]; then
    log_error "validate_context_name: no readable Cargo.toml in $(_ch_clean "$root")"
    return 2
  fi
  if [[ -d "$root/crates/$context" ]]; then
    found="crates/$context"
  else
    for dir in "$root"/crates/*/"$context"; do
      if [[ -d "$dir" ]]; then
        found="crates/${dir#"$root/crates/"}"
        break
      fi
    done
  fi
  if [[ -n "$found" ]]; then
    printf "REFUSED: context-exists '%s' already exists at %s\n" "$context" "$(_ch_clean "$found")"
    return 1
  fi
  list="$(toml_get_list "$root/Cargo.toml" workspace.members)" || return 2
  if [[ -n "$list" ]]; then
    mapfile -t members <<<"$list"
    names="$(_ch_package_names "$root" "${members[@]}")" || rc=$?
    if ((rc == 3)); then
      die "python3 3.11+ with tomllib is required"
    elif ((rc != 0)); then
      return 2
    fi
    mapfile -t packages <<<"$names"
  fi
  for i in "${!members[@]}"; do
    member="${members[$i]%/}"
    package="${packages[$i]-}"
    case "$package" in
      "$context-domain" | "$context-application" | "$context-infrastructure")
        printf "REFUSED: member-exists '%s' is already a workspace member: %s (package %s)\n" \
          "$context" "$(_ch_clean "$member")" "$package"
        return 1
        ;;
      *) ;;
    esac
    case "/$member" in
      */"$context"/domain | */"$context"/application | */"$context"/infrastructure)
        printf "REFUSED: member-exists '%s' is already a workspace member: %s\n" \
          "$context" "$(_ch_clean "$member")"
        return 1
        ;;
      *) ;;
    esac
  done
  return 0
}

# section: publishing and model sessions

# The single redaction implementation behind every body the plugin publishes
# (NFR-10, ADR-27), prompt-fence neutralization for contributor text, the two
# claude drivers of the review loop and the FR/NFR gate (ADR-8) and the
# validated review-ledger writer (ADR-16). redact and ledger_write are
# dispatcher names (ADR-15); writes go only below target/rust-sdlc/ or the
# ledger directory, through safe_write_target and atomic_write. Private helpers
# carry the _pm_ prefix.

# --- redaction (NFR-10, ADR-27) --------------------------------------------------------

# _pm_redact_stream — stdin to stdout through the redaction list, python3 `re`,
# applied in this order, each match replaced by [REDACTED] with the lead-in
# kept as shown:
#   (AKIA|ASIA)[0-9A-Z]{16}                          → AKIA[REDACTED]
#   JWT eyJ…{10,}.…{10,}.…{10,}                       → [REDACTED]
#   (gh[pousr]_)[A-Za-z0-9]{20,}                      → ghp_[REDACTED]
#   github_pat_[A-Za-z0-9_]{22,}                      → github_pat_[REDACTED]
#   -----BEGIN … PRIVATE KEY----- … -----END … PRIVATE KEY----- (multi-line;
#   a block without its END line is redacted to the end of the text) → [REDACTED]
#   (?i)authorization:\s*(bearer|basic|token)\s+\S+   → Authorization: Bearer [REDACTED]
#   (?i)\b[A-Z0-9_]*(PASSWORD|PASSWD|SECRET|TOKEN|APIKEY|API_KEY)[A-Z0-9_]*\s*[=:]\s*\S+
#                                                     → DB_PASSWORD=[REDACTED]
#   URL credentials ://[^/\s:@]+:[^/\s@]+@            → ://[REDACTED]@
#   a base64/hex run of 40+ characters ([A-Za-z0-9+], `=` padding) with mixed
#   classes, a letter and a digit           → [REDACTED]
# A run that is hexadecimal in one letter case (a commit sha, a sha256 digest)
# is not a mixed-class run: the state comment publishes 40-hex head_sha values
# that resume_point must read back. The bytes are kept as read (invalid UTF-8
# passes through unchanged), and text without a secret is copied byte for byte.
_pm_redact_stream() {
  _sdlc_py -c '
import re
import sys

MARK = "[REDACTED]"
RULES = (
    (re.compile(r"(AKIA|ASIA)[0-9A-Z]{16}"), r"\1" + MARK),
    (re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"), MARK),
    (re.compile(r"(gh[pousr]_)[A-Za-z0-9]{20,}"), r"\1" + MARK),
    (re.compile(r"(github_pat_)[A-Za-z0-9_]{22,}"), r"\1" + MARK),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"
                r"(?:.*?-----END [A-Z ]*PRIVATE KEY-----|.*\Z)", re.S), MARK),
    (re.compile(r"(?i)(authorization:\s*(?:bearer|basic|token)\s+)\S+"), r"\1" + MARK),
    (re.compile(r"(?i)(\b[A-Z0-9_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|APIKEY|API_KEY)"
                r"[A-Z0-9_]*\s*[=:]\s*)\S+"), r"\1" + MARK),
    (re.compile(r"://[^/\s:@]+:[^/\s@]+@"), "://" + MARK + "@"),
)
RUN = re.compile(r"(?<![A-Za-z0-9+])[A-Za-z0-9+]{40,}={0,2}(?![A-Za-z0-9+])")
LETTER = re.compile(r"[A-Za-z]")
DIGIT = re.compile(r"[0-9]")
DIGEST = re.compile(r"[0-9a-f]+|[0-9A-F]+")


def run_mark(match):
    core = match.group(0).rstrip("=")
    if LETTER.search(core) and DIGIT.search(core) and not DIGEST.fullmatch(core):
        return MARK
    return match.group(0)


text = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
for pattern, replacement in RULES:
    text = pattern.sub(replacement, text)
text = RUN.sub(run_mark, text)
sys.stdout.buffer.write(text.encode("utf-8", "surrogateescape"))
'
}

# redact [--in FILE] [--out FILE] — stdin to stdout through the redaction list
# (_pm_redact_stream), or FILE to FILE. --in must be a readable regular file
# and --out a path, both resolving below target/rust-sdlc/tmp/ of the working
# directory (the repository root), else exit 2 with nothing written. --out is
# refused (exit 1) when safe_write_target refuses it; its directory is created
# when missing, the redacted text is complete before it replaces --out
# atomically (atomic_write) and `WROTE: <out>` is printed. Without --out the
# redacted text goes to stdout. A failed redaction exits 1 and leaves --out as
# it was.
redact() {
  local usage='(usage: redact [--in FILE] [--out FILE])'
  local in="" out="" have_in=0 have_out=0 dir tmp rc=0
  while (($#)); do
    case "$1" in
      --in | --out)
        if (($# < 2)) || [[ -z "$2" ]]; then
          log_error "redact: $1 needs a value $usage"
          return 2
        fi
        if [[ "$1" == --in ]]; then
          if ((have_in)); then
            log_error "redact: --in given twice $usage"
            return 2
          fi
          have_in=1
          in="$2"
        else
          if ((have_out)); then
            log_error "redact: --out given twice $usage"
            return 2
          fi
          have_out=1
          out="$2"
        fi
        shift 2
        ;;
      *)
        log_error "redact: unknown argument: $(_ch_clean "$1") $usage"
        return 2
        ;;
    esac
  done
  if ((have_in)); then
    if ! _ch_resolved_under "$in" target/rust-sdlc/tmp; then
      log_error "redact: --in must be below target/rust-sdlc/tmp/: $(_ch_clean "$in")"
      return 2
    fi
    if [[ ! -f "$in" || ! -r "$in" ]]; then
      log_error "redact: --in is not a readable regular file: $(_ch_clean "$in")"
      return 2
    fi
  fi
  if ((!have_out)); then
    if ((have_in)); then
      _pm_redact_stream <"$in"
    else
      _pm_redact_stream
    fi
    return
  fi
  if ! _ch_resolved_under "$out" target/rust-sdlc/tmp; then
    log_error "redact: --out must be below target/rust-sdlc/tmp/: $(_ch_clean "$out")"
    return 2
  fi
  safe_write_target "$out" "$PWD" || return 1
  dir="$(dirname -- "$out")"
  mkdir -p -- "$dir" || return 1
  tmp="$(mktemp "$dir/.redact.XXXXXX")" || return 1
  if ((have_in)); then
    _pm_redact_stream <"$in" >"$tmp" || rc=$?
  else
    _pm_redact_stream >"$tmp" || rc=$?
  fi
  if ((rc == 0)); then
    atomic_write "$out" <"$tmp" || rc=$?
  fi
  rm -f -- "$tmp"
  if ((rc != 0)); then
    log_error "redact: could not write $(_ch_clean "$out")"
    return 1
  fi
  printf 'WROTE: %s\n' "$out"
}

# fence_safe — stdin to stdout with every `<<<` turned into `‹‹‹` and every
# `>>>` into `›››` (left to right, non-overlapping), so contributor text placed
# between the <<< and >>> fences of a prompt cannot close its data block
# early. Every other byte is copied unchanged. Arguments exit 2.
fence_safe() {
  if (($#)); then
    log_error "fence_safe: reads stdin and takes no argument (usage: fence_safe <TEXT)"
    return 2
  fi
  _sdlc_py -c '
import sys

data = sys.stdin.buffer.read()
data = data.replace(b"<<<", "‹‹‹".encode("utf-8"))
data = data.replace(b">>>", "›››".encode("utf-8"))
sys.stdout.buffer.write(data)
'
}

# --- claude driver and the isolated gate session (ADR-8) ----------------------------------
# `claude -p --output-format json` prints one object with a `.result` string
# and an `.is_error` bool. A non-zero exit, `is_error: true` or a missing
# `.result` is a transport failure and earns exactly one retry; a well-formed
# reply is returned as it is, so a negative verdict is never retried.

# claude_is_error JSON — 0 when JSON reports `.is_error == true` (jq, else
# python3), else 1; malformed JSON or a non-object is not an error report.
claude_is_error() {
  local json="${1-}"
  if have_jq; then
    if printf '%s' "$json" | jq -e '.is_error == true' >/dev/null 2>&1; then
      return 0
    fi
    return 1
  else
    printf '%s' "$json" | _sdlc_py -c '
import json
import sys

try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
sys.exit(0 if isinstance(doc, dict) and doc.get("is_error") is True else 1)
' 2>/dev/null
  fi
}

# claude_extract_result JSON — `.result // empty` (jq -r, else python3 with the
# same output): a string raw with a newline; null, false, a missing key,
# malformed JSON or a non-object print nothing. Always returns 0.
claude_extract_result() {
  local json="${1-}"
  if have_jq; then
    printf '%s' "$json" | jq -r '.result // empty' 2>/dev/null || true
  else
    printf '%s' "$json" | _sdlc_py -c '
import json
import sys

try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
value = doc.get("result") if isinstance(doc, dict) else None
if isinstance(value, str):
    print(value)
elif value is not None and value is not False:
    print(json.dumps(value, indent=2, ensure_ascii=False))
' 2>/dev/null || true
  fi
}

# _pm_gh_config_rm — removes the isolated session's temporary GH_CONFIG_DIR
# (the subshell variable gh_config), if any.
_pm_gh_config_rm() {
  if [[ -n "${gh_config:-}" ]]; then
    rm -rf -- "$gh_config"
  fi
  gh_config=""
}

# _pm_session_signal SIGNAL — the isolated session's HUP/INT/TERM trap: remove
# the temporary GH_CONFIG_DIR, then die of SIGNAL itself, so a caller that got
# the same signal (Ctrl-C reaches the whole process group) stops as well.
_pm_session_signal() {
  _pm_gh_config_rm
  trap - EXIT "$1"
  kill -s "$1" "$BASHPID"
  case "$1" in
    HUP) exit 129 ;;
    INT) exit 130 ;;
    *) exit 143 ;;
  esac
}

# _pm_claude_attempt MODE PROMPT — one claude session; stdout is claude's raw
# JSON and the status claude's. MODE `isolated` is react's isolated run with
# the exact environment of ADR-8, inside a subshell whose traps remove the
# fresh `mktemp -d` GH_CONFIG_DIR on every exit path (return, error, signal);
# the caller's traps and environment are untouched. The session never reads
# the caller's stdin.
_pm_claude_attempt() {
  local mode="$1" prompt="$2"
  local -a cmd=(claude -p "$prompt" --output-format json --permission-mode acceptEdits --max-turns 30)
  if [[ "$mode" != isolated ]]; then
    "${cmd[@]}" </dev/null
    return
  fi
  (
    gh_config=""
    trap _pm_gh_config_rm EXIT
    trap '_pm_session_signal HUP' HUP
    trap '_pm_session_signal INT' INT
    trap '_pm_session_signal TERM' TERM
    gh_config="$(mktemp -d)" || exit 1
    cmd=(env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN
      -u SSH_AUTH_SOCK -u GIT_ASKPASS -u SSH_ASKPASS
      GH_CONFIG_DIR="$gh_config" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
      GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
      "${cmd[@]}"
      --restricted --tools 'Read,Grep,Glob' --strict-mcp-config
      --disallowedTools 'Bash(gh:*)' 'Bash(git push:*)' 'Bash(git credential:*)')
    "${cmd[@]}" </dev/null
  )
}

# _pm_claude_session MODE PROMPT — up to two attempts of _pm_claude_attempt;
# prints `.result` of the first well-formed reply (exit 0), or logs each
# transport failure and returns 1 after the retry. A missing or empty PROMPT,
# or more than one argument, exits 2 without a session.
_pm_claude_session() {
  local mode="$1" fn="claude_run_$1" raw result attempt rc
  shift
  if (($# != 1)) || [[ -z "$1" ]]; then
    log_error "$fn: needs one non-empty PROMPT (usage: $fn PROMPT)"
    return 2
  fi
  for attempt in 1 2; do
    rc=0
    raw="$(_pm_claude_attempt "$mode" "$1")" || rc=$?
    if ((rc != 0)); then
      log_warn "$fn: attempt $attempt/2: claude exited with status $rc (transport failure)"
    elif claude_is_error "$raw"; then
      log_warn "$fn: attempt $attempt/2: claude reported is_error: true (transport failure)"
    else
      result="$(claude_extract_result "$raw")"
      if [[ -n "$result" ]]; then
        printf '%s\n' "$result"
        return 0
      fi
      log_warn "$fn: attempt $attempt/2: the claude reply has no .result (transport failure)"
    fi
  done
  log_error "$fn: claude failed after one retry"
  return 1
}

# claude_run_once PROMPT — `claude -p PROMPT --output-format json
# --permission-mode acceptEdits --max-turns 30`; prints `.result`; one retry
# on a transport failure, then return 1 (ADR-8).
claude_run_once() {
  _pm_claude_session once "$@"
}

# claude_run_isolated PROMPT — claude_run_once for a session that reads
# contributor-controlled text (PR and issue bodies, diffs): no credential
# variable, an empty temporary GH_CONFIG_DIR, git without system, global or
# credential-helper configuration, and `--restricted --tools 'Read,Grep,Glob'
# --strict-mcp-config` with gh, git push and git credential denied. The
# caller keeps its own credentials and publishes the outcome itself.
claude_run_isolated() {
  _pm_claude_session isolated "$@"
}

# --- review ledgers (ADR-16) ------------------------------------------------------------

# _pm_ledger_doc LENS ITERATION HEAD_SHA STARTED ENDED — reads the findings
# array on stdin (bare JSON, or one fenced ```json block), validates it
# against the ADR-16 field table and prints the ledger document. Every
# violation is logged; invalid findings exit 1, an impossible calendar time in
# STARTED or ENDED exits 2.
_pm_ledger_doc() {
  # shellcheck disable=SC2016 # a python program; `$` ends a regex in its messages
  _sdlc_py -c '
import json
import re
import sys
from datetime import datetime

lens, iteration, head_sha, started, ended = sys.argv[1:6]
PREFIX = {"security": "SEC-", "fr-nfr": "FRN-", "code-review": "CQ-"}[lens]
KEYS = ("id", "severity", "file", "line", "rule", "summary", "status")
SEVERITIES = ("Critical", "High", "Medium", "Low", "Info")
STATUSES = ("open", "fixed", "dropped")
ID = re.compile(r"[A-Z]+-[0-9]+")
CTRL = re.compile(r"[\x00-\x08\x0a-\x1f\x7f]")


def log(message):
    sys.stderr.write("[rust-sdlc][ERROR] ledger_write: %s\n" % CTRL.sub("?", message))


for flag, value in (("--started-at", started), ("--ended-at", ended)):
    if value:
        try:
            datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            log("%s is not a UTC time: %s" % (flag, value))
            sys.exit(2)


def unique_keys(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError("duplicate key %s" % json.dumps(key))
        seen[key] = value
    return seen


def no_constant(name):
    raise ValueError("%s is not JSON" % name)


text = sys.stdin.read().strip()
if text.startswith("```"):
    lines = text.splitlines()
    if len(lines) < 2 or lines[0].strip() not in ("```", "```json") or lines[-1].strip() != "```":
        log("stdin: a fenced block must open with ```json and close with ```")
        sys.exit(1)
    text = "\n".join(lines[1:-1])
try:
    findings = json.loads(text, object_pairs_hook=unique_keys, parse_constant=no_constant)
except ValueError as exc:
    log("stdin is not a JSON findings array: %s" % (str(exc).splitlines() or ["invalid JSON"])[0])
    sys.exit(1)

errors = []
if not isinstance(findings, list):
    errors.append("stdin: the findings must be a JSON array")
    findings = []
ids = set()
for index, finding in enumerate(findings):
    at = "findings[%d]" % index
    if not isinstance(finding, dict):
        errors.append("%s: not an object" % at)
        continue
    for key in sorted(set(finding) - set(KEYS)):
        errors.append("%s: extra key %s" % (at, json.dumps(key)))
    for key in KEYS:
        if key not in finding:
            errors.append("%s: missing key %s" % (at, key))
    if set(KEYS) - set(finding):
        continue
    fid, severity, path, line, rule, summary, status = (finding[key] for key in KEYS)
    if not isinstance(fid, str) or not ID.fullmatch(fid):
        errors.append("%s.id: %s does not match ^[A-Z]+-[0-9]+$" % (at, json.dumps(fid)))
    elif not fid.startswith(PREFIX):
        errors.append("%s.id: %s lacks the %s prefix of the %s lens" % (at, fid, PREFIX, lens))
    elif fid in ids:
        errors.append("%s.id: %s is not unique" % (at, fid))
    else:
        ids.add(fid)
    if severity not in SEVERITIES:
        errors.append("%s.severity: %s is not one of %s" % (at, json.dumps(severity), " ".join(SEVERITIES)))
    if path is not None and not (
            isinstance(path, str) and path and not CTRL.search(path) and not path.startswith("/")
            and ".." not in path.replace("\\", "/").split("/")):
        errors.append("%s.file: %s is not a repository-relative path or null" % (at, json.dumps(path)))
    if line is not None and not (isinstance(line, int) and not isinstance(line, bool) and line >= 1):
        errors.append("%s.line: %s is not an integer >= 1 or null" % (at, json.dumps(line)))
    elif line is not None and path is None:
        errors.append("%s.line: must be null when file is null" % at)
    if not isinstance(rule, str) or not rule.strip() or CTRL.search(rule):
        errors.append("%s.rule: %s is not a non-empty single-line string" % (at, json.dumps(rule)))
    if not isinstance(summary, str) or not 1 <= len(summary) <= 300 or CTRL.search(summary):
        errors.append("%s.summary: not a single-line string of 1 to 300 characters" % at)
    if status not in STATUSES:
        errors.append("%s.status: %s is not one of %s" % (at, json.dumps(status), " ".join(STATUSES)))
if errors:
    for message in errors:
        log(message)
    sys.exit(1)

doc = {
    "schema_version": 1,
    "lens": lens,
    "iteration": int(iteration),
    "head_sha": head_sha,
    "findings": [{key: finding[key] for key in KEYS} for finding in findings],
}
if started:
    doc["started_at"] = started
if ended:
    doc["ended_at"] = ended
print(json.dumps(doc, indent=2, ensure_ascii=False))
' "$@"
}

# ledger_write LENS ITERATION HEAD_SHA [--dir D] [--started-at ISO]
# [--ended-at ISO] — reads LENS's findings array (the lens agent's final fenced
# json block) on stdin and validates it against the ADR-16 field table: each
# finding has exactly id (^[A-Z]+-[0-9]+$ with the lens prefix SEC- security,
# FRN- fr-nfr, CQ- code-review; unique), severity (Critical High Medium Low
# Info), file (repository-relative path or null), line (integer >= 1, or null;
# null when file is null), rule (non-empty, single line), summary (1 to 300
# characters, single line) and status (open fixed dropped). A valid array is
# written atomically as {"schema_version": 1, "lens", "iteration", "head_sha",
# "findings"[, "started_at", "ended_at"]} to
# ${D:-${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}}/<LENS>.json and
# `WROTE: <path>` is printed. Exit 1 on invalid findings or a refused path,
# nothing written; exit 2 on a malformed argument (LENS outside security
# fr-nfr code-review, ITERATION not a digit string, HEAD_SHA not 40 lower-case
# hex, a time not YYYY-MM-DDTHH:MM:SSZ, an unknown or repeated flag).
ledger_write() {
  local usage='(usage: ledger_write LENS ITERATION HEAD_SHA [--dir D] [--started-at ISO] [--ended-at ISO])'
  local re_iso='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
  local lens="${1-}" iteration="${2-}" sha="${3-}" dir="" started="" ended="" seen=" "
  local doc path root
  if (($# < 3)); then
    log_error "ledger_write: needs LENS, ITERATION and HEAD_SHA $usage"
    return 2
  fi
  shift 3
  while (($#)); do
    case "$1" in
      --dir | --started-at | --ended-at)
        if (($# < 2)) || [[ -z "$2" ]]; then
          log_error "ledger_write: $1 needs a value $usage"
          return 2
        fi
        if [[ "$seen" == *" $1 "* ]]; then
          log_error "ledger_write: $1 given twice $usage"
          return 2
        fi
        seen+="$1 "
        case "$1" in
          --dir) dir="$2" ;;
          --started-at) started="$2" ;;
          *) ended="$2" ;;
        esac
        shift 2
        ;;
      *)
        log_error "ledger_write: unknown argument: $(_ch_clean "$1") $usage"
        return 2
        ;;
    esac
  done
  case "$lens" in
    security | fr-nfr | code-review) ;;
    *)
      log_error "ledger_write: LENS must be security, fr-nfr or code-review: $(_ch_clean "$lens")"
      return 2
      ;;
  esac
  if ! is_uint "$iteration"; then
    log_error "ledger_write: ITERATION must be a non-negative integer: $(_ch_clean "$iteration")"
    return 2
  fi
  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    log_error "ledger_write: HEAD_SHA must be 40 lower-case hex digits: $(_ch_clean "$sha")"
    return 2
  fi
  if [[ -n "$started" && ! "$started" =~ $re_iso ]] || [[ -n "$ended" && ! "$ended" =~ $re_iso ]]; then
    log_error "ledger_write: --started-at and --ended-at take YYYY-MM-DDTHH:MM:SSZ"
    return 2
  fi
  doc="$(_pm_ledger_doc "$lens" "$(strip_zeros "$iteration")" "$sha" "$started" "$ended")" || return
  dir="${dir:-${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}}"
  path="${dir%/}/$lens.json"
  if [[ "$dir" == /* ]]; then
    mkdir -p -- "$dir" || return 1
    root="$dir"
  else
    root="$PWD"
  fi
  safe_write_target "$path" "$root" || return 1
  printf '%s\n' "$doc" | atomic_write "$path" || return 1
  printf 'WROTE: %s\n' "$path"
}

# section: dispatch (keep last)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  _sdlc_dispatch "$@"
fi
