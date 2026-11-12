#!/usr/bin/env bats
# common-lib.bats — cases of scripts/lib/common.sh (FR-33, AC-33.1, AC-2.1).
#
# Sections (single-writer, one owner each, in this order): core defines
# setup, teardown and the shared suite helpers; command helpers (ch_),
# publishing and model sessions (pm_), stage state and resume (sr_) and
# Ralph helpers (rh_) append @test blocks plus helpers carrying their prefix
# and never redefine a function of another section.
#
# The suite is hermetic: stubs come first on PATH (common_setup), every file
# is written under $BATS_TEST_TMPDIR, and YAML cases compare the default
# backend (mikefarah yq when present) with SDLC_FORCE_PYTHON_YAML=1 byte for
# byte.
#
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2030,SC2031 # single-quoted snippets run in child shells; bats cases are subshells

# section: core

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  LIB="$PLUGIN_ROOT/scripts/lib/common.sh"
  FIXTURE_REPO="$PLUGIN_ROOT/tests/fixtures/rust-repo"
  KISLYUK_BIN="$PLUGIN_ROOT/tests/fixtures/bin-kislyuk"
  DISPATCH_NAMES=(validate_context_name resume_point derive_issue_number
    is_commit_subject redact state_cache_update state_comment_body ledger_write
    hooks_active commit_msg_file wait_log http_probe protected_changes
    ralph_fix_plan_prepare ralph_fix_plan_restore ralph_agent_md_patch
    ralph_breaker_state)
  # shellcheck source=../scripts/lib/common.sh
  source "$LIB"
}

teardown() {
  # Permission cases may leave unreadable or unwritable paths behind; make the
  # test directory removable again.
  chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# lib_shell CODE [ARG...] — CODE in a fresh bash that has sourced the library;
# the arguments are $1... inside CODE.
lib_shell() {
  local code="$1"
  shift
  bash -c 'source "$1"; shift; '"$code" _ "$LIB" "$@"
}

# is_dispatch_name NAME — NAME is one of the 17 ADR-15 dispatcher names.
is_dispatch_name() {
  local n
  for n in "${DISPATCH_NAMES[@]}"; do
    [[ "$n" == "$1" ]] && return 0
  done
  return 1
}

# make_stub DIR NAME BODY — an executable DIR/NAME running BODY under bash.
make_stub() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\n%s\n' "$3" >"$1/$2"
  chmod 755 "$1/$2"
}

# shadow_module NAME — a PYTHONPATH directory whose NAME.py raises ImportError,
# so `import NAME` fails as if the module were not installed.
shadow_module() {
  local dir="$BATS_TEST_TMPDIR/shadow-$1"
  mkdir -p "$dir"
  printf 'raise ImportError("No module named %s")\n' "$1" >"$dir/$1.py"
  printf '%s\n' "$dir"
}

# write_tool SCRIPT BODY — a tool script with a header comment block that
# sources the library and runs BODY.
write_tool() {
  cat >"$1" <<EOF
#!/usr/bin/env bash
# tool.sh — a tool of the common-lib suite
#
# Usage: tool.sh [--name VALUE]
#   --name VALUE   a value
#
# Exit: 0 success; 2 usage error
set -euo pipefail
source "$LIB"
$2
EOF
  chmod 755 "$1"
}

# write_yaml_sample FILE — the YAML document of the parity cases.
write_yaml_sample() {
  cat >"$1" <<'EOF'
name: 'billing-service'
count: 42
ratio: 0.5
enabled: true
disabled: false
nothing: null
tilde: ~
empty: ''
list:
  - alpha
  - 'beta gamma'
  - 3
  - true
  - null
  - [nested]
  - {k: v}
empty_list: []
map:
  inner: value
  deep:
    key: 7
  dash-key: dashed
quoted_bool: 'true'
legacy_yes: yes
clock: 10:30
upper_bool: True
upper_false: FALSE
zero_eight: 08
octal_like: 007
hex: 0x1F
plus: +5
trailing_zero: 1.50
exp: 1e3
cased_list:
  - [n]
  - True
  - ~
  - 1.50
  - {k: v}
  - FALSE
  - 007
EOF
}

# parity FUNC ARG... — FUNC under the default backend and under
# SDLC_FORCE_PYTHON_YAML=1; fails unless stdout is byte-identical and the
# status equal. Leaves the stdout file in PARITY_OUT and the status in
# PARITY_STATUS.
parity() {
  local def="$BATS_TEST_TMPDIR/parity.default" py="$BATS_TEST_TMPDIR/parity.python"
  local sd=0 sp=0
  (
    unset SDLC_FORCE_PYTHON_YAML _SDLC_YQ_OK
    "$@"
  ) >"$def" 2>/dev/null || sd=$?
  (
    export SDLC_FORCE_PYTHON_YAML=1
    "$@"
  ) >"$py" 2>/dev/null || sp=$?
  if ! cmp -s "$def" "$py" || [[ "$sd" != "$sp" ]]; then
    printf 'backend mismatch for %s (default %s, python %s)\n' "$*" "$sd" "$sp"
    printf -- '--- default\n'
    od -c "$def"
    printf -- '--- python\n'
    od -c "$py"
    return 1
  fi
  PARITY_OUT="$def"
  PARITY_STATUS="$sd"
}

# expect_case FUNC FILE KEY STATUS BYTES — parity, then the status and the
# exact stdout bytes (BYTES is a printf %b string).
expect_case() {
  parity "$1" "$2" "$3"
  if [[ "$PARITY_STATUS" != "$4" ]]; then
    printf '%s %s: status %s, want %s\n' "$1" "$3" "$PARITY_STATUS" "$4"
    return 1
  fi
  if ! printf '%b' "$5" | cmp -s - "$PARITY_OUT"; then
    printf '%s %s: unexpected bytes\n' "$1" "$3"
    od -c "$PARITY_OUT"
    return 1
  fi
}

# perms FILE — the permission string of FILE (`-rw-r-----`).
perms() {
  # shellcheck disable=SC2012 # one known path, only the mode column is read
  ls -ld "$1" | cut -c1-10
}

# git_init_empty DIR BRANCH — a repository with one empty commit on BRANCH.
git_init_empty() {
  git init -q -b "$2" "$1"
  git -C "$1" -c user.name=acme -c user.email=ci@example.invalid \
    -c commit.gpgsign=false commit -q --allow-empty -m init
}

# --- layout and the library CLI (ADR-15) -------------------------------------

@test "common-lib: layout: shebang, header, bash floor, core section and the dispatch trailer" {
  local guard core first_fn first_code
  [ -x "$LIB" ]
  [ "$(head -n 1 "$LIB")" = '#!/usr/bin/env bash' ]
  grep -qE '^# common\.sh — ' "$LIB"
  first_code="$(awk 'NR > 1 && !/^#/ && !/^[[:space:]]*$/ { print NR; exit }' "$LIB")"
  guard="$(grep -n 'RUST_SDLC_BASH_VERSION:-' "$LIB" | head -n 1 | cut -d: -f1)"
  core="$(grep -nxF '# section: core' "$LIB" | cut -d: -f1)"
  first_fn="$(grep -nE '^[A-Za-z_][A-Za-z0-9_]*\(\) \{$' "$LIB" | head -n 1 | cut -d: -f1)"
  [ "$first_code" -eq "$guard" ]
  [ "$guard" -lt "$core" ]
  [ "$core" -lt "$first_fn" ]
  [ "$(grep -c '^# section: ' "$LIB")" -ge 2 ]
  [ "$(grep -m 1 '^# section: ' "$LIB")" = '# section: core' ]
  tail -n 4 "$LIB" >"$BATS_TEST_TMPDIR/trailer"
  # shellcheck disable=SC2016 # the trailer is compared literally
  printf '%s\n' '# section: dispatch (keep last)' \
    'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then' '  _sdlc_dispatch "$@"' 'fi' |
    cmp - "$BATS_TEST_TMPDIR/trailer"
  run grep -nE '^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{|^[[:space:]]*function[[:space:]]' "$LIB"
  [ "$status" -eq 1 ]
  grep -qxF '_sdlc_dispatch() {' "$LIB"
}

@test "common-lib: layout: banned constructs, organization tokens and the template slug are absent" {
  run grep -nE '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)|while true|until false|sed -i|readlink -f|date -d|grep -P|stat -c|declare -n|mapfile -d' "$LIB"
  [ "$status" -eq 1 ]
  # The denylist is assembled from halves so this suite never holds the tokens.
  local u=us o=oa a=app pattern
  pattern="vilna""crm|rust-service-""template|${u}er[-_ ]service|${a}runner|src/${u}er|src/${o}uth"
  run grep -niE "$pattern" "$LIB"
  [ "$status" -eq 1 ]
}

@test "common-lib: _sdlc_dispatch: no argument prints the library refusal and exits 64" {
  run --separate-stderr "$LIB"
  [ "$status" -eq 64 ]
  [ -z "$output" ]
  [ "$stderr" = 'common.sh is a library; source it instead of executing' ]
}

@test "common-lib: _sdlc_dispatch: every name outside the 17 exits 64" {
  local fn rc names
  names="$(lib_shell 'declare -F | awk "{ print \$3 }"')"
  [ -n "$names" ]
  for fn in $names --help help source ''; do
    if is_dispatch_name "$fn"; then
      continue
    fi
    rc=0
    "$LIB" "$fn" a b >"$BATS_TEST_TMPDIR/out" 2>"$BATS_TEST_TMPDIR/err" || rc=$?
    if [ "$rc" -ne 64 ] || [ -s "$BATS_TEST_TMPDIR/out" ]; then
      printf '%s exited %s\n' "$fn" "$rc"
      return 1
    fi
    grep -qxF 'common.sh is a library; source it instead of executing' "$BATS_TEST_TMPDIR/err"
  done
}

@test "common-lib: _sdlc_dispatch: each of the 17 names runs with the remaining arguments and its status" {
  local wrap="$BATS_TEST_TMPDIR/wrap.sh" n
  [ "${#DISPATCH_NAMES[@]}" -eq 17 ]
  {
    printf 'source "%s"\n' "$LIB"
    for n in "${DISPATCH_NAMES[@]}"; do
      printf '%s() { printf "ran %s %%s|" "$@"; printf "\\n"; return 7; }\n' "$n" "$n"
    done
    # shellcheck disable=SC2016 # written literally into the wrapper
    printf '_sdlc_dispatch "$@"\n'
  } >"$wrap"
  for n in "${DISPATCH_NAMES[@]}"; do
    run bash "$wrap" "$n" one 'two words'
    [ "$status" -eq 7 ]
    [ "$output" = "ran $n one|ran $n two words|" ]
  done
}

@test "common-lib: _sdlc_dispatch: executed is_commit_subject exits with the function's status" {
  run "$LIB" is_commit_subject 'feat(#1): add x'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$LIB" is_commit_subject 'feat: x'
  [ "$status" -eq 1 ]
  run "$LIB" is_commit_subject
  [ "$status" -eq 1 ]
}

@test "common-lib: source: defines functions only (no output, no variable, options unchanged)" {
  run lib_shell 'declare -F yaml_get is_commit_subject _sdlc_dispatch'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  # shellcheck disable=SC2016 # the snippet runs in a child bash
  run bash -c 'before=; opts=; after=
    opts="$(set +o; shopt -p)"
    before="$(compgen -v | sort)"
    source "$1"
    after="$(compgen -v | sort)"
    [ "$opts" = "$(set +o; shopt -p)" ] || echo OPTIONS-CHANGED
    comm -13 <(printf "%s\n" "$before") <(printf "%s\n" "$after")' _ "$LIB"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: source: bash 4.3 or 3.2 stops before any function is defined" {
  local probe="$BATS_TEST_TMPDIR/probe.sh"
  # The EXIT trap counts the functions the sourced file defined before it
  # stopped (functions inherited from the environment are subtracted).
  # shellcheck disable=SC2016 # written literally into the probe
  printf '%s\n' 'before="$(declare -F | grep -c .)"' \
    'trap '\''printf "new functions=%s\n" "$(($(declare -F | grep -c .) - before))"'\'' EXIT' \
    'source "$1"' 'echo sourced' >"$probe"
  RUST_SDLC_BASH_VERSION=4.3 run bash "$probe" "$LIB"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = '[rust-sdlc][ERROR] bash 4.3 is too old: install Bash 4.4 or newer' ]
  [ "${lines[1]}" = 'new functions=0' ]
  [ "${#lines[@]}" -eq 2 ]
  RUST_SDLC_BASH_VERSION=3.2 run --separate-stderr "$LIB" is_commit_subject 'feat(#1): add x'
  [ "$status" -eq 1 ]
  [ "$stderr" = '[rust-sdlc][ERROR] bash 3.2 is too old: install Bash 4.4 or newer' ]
}

@test "common-lib: source: bash 4.4 and newer pass the floor" {
  local v
  for v in 4.4 4.10 5.0 5.2 10.1; do
    RUST_SDLC_BASH_VERSION="$v" run lib_shell 'declare -F log_info'
    [ "$status" -eq 0 ]
    [ "$output" = log_info ]
  done
}

# --- logging, exits and argument handling ------------------------------------

@test "common-lib: log_info: log_info, log_warn and log_error write [rust-sdlc][LEVEL] to stderr only" {
  run --separate-stderr log_info hello world
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = '[rust-sdlc][INFO] hello world' ]
  run --separate-stderr log_warn careful
  [ -z "$output" ]
  [ "$stderr" = '[rust-sdlc][WARN] careful' ]
  run --separate-stderr log_error boom
  [ -z "$output" ]
  [ "$stderr" = '[rust-sdlc][ERROR] boom' ]
}

@test "common-lib: die: logs the message and exits 1" {
  run --separate-stderr lib_shell 'die "fatal reason"; echo unreachable'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = '[rust-sdlc][ERROR] fatal reason' ]
}

@test "common-lib: die_usage: exits 2 with the caller's Usage line appended" {
  write_tool "$BATS_TEST_TMPDIR/tool.sh" 'die_usage "unknown argument: --bogus"'
  run --separate-stderr "$BATS_TEST_TMPDIR/tool.sh"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = '[rust-sdlc][ERROR] unknown argument: --bogus (usage: tool.sh [--name VALUE])' ]
}

@test "common-lib: need_value: rejects an empty value and one starting --, accepts a value" {
  # shellcheck disable=SC2016 # the body is written literally into the tool
  write_tool "$BATS_TEST_TMPDIR/tool.sh" 'while (($#)); do
  case "$1" in
    --name) need_value "$1" "${2-}"; printf "name=%s\n" "$2"; shift 2 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done'
  run --separate-stderr "$BATS_TEST_TMPDIR/tool.sh" --name ''
  [ "$status" -eq 2 ]
  [ "$stderr" = '[rust-sdlc][ERROR] --name needs a value (usage: tool.sh [--name VALUE])' ]
  run --separate-stderr "$BATS_TEST_TMPDIR/tool.sh" --name --other
  [ "$status" -eq 2 ]
  [[ "$stderr" == '[rust-sdlc][ERROR] --name needs a value'* ]]
  run --separate-stderr "$BATS_TEST_TMPDIR/tool.sh" --name
  [ "$status" -eq 2 ]
  run --separate-stderr "$BATS_TEST_TMPDIR/tool.sh" --name -v
  [ "$status" -eq 0 ]
  [ "$output" = 'name=-v' ]
}

@test "common-lib: print_usage: prints the header comment block without the leading hash" {
  write_tool "$BATS_TEST_TMPDIR/tool.sh" 'print_usage "$0"'
  run --separate-stderr "$BATS_TEST_TMPDIR/tool.sh"
  [ "$status" -eq 0 ]
  printf '%s\n' 'tool.sh — a tool of the common-lib suite' '' 'Usage: tool.sh [--name VALUE]' \
    '  --name VALUE   a value' '' 'Exit: 0 success; 2 usage error' >"$BATS_TEST_TMPDIR/want"
  printf '%s\n' "$output" | cmp - "$BATS_TEST_TMPDIR/want"
}

@test "common-lib: lower: lower-cases through tr" {
  run lower 'Acme/Billing-SERVICE'
  [ "$status" -eq 0 ]
  [ "$output" = 'acme/billing-service' ]
  run lower ''
  [ -z "$output" ]
}

# --- wrap-safe digit-string arithmetic -----------------------------------------

@test "common-lib: strip_zeros: drops leading zeros" {
  [ "$(strip_zeros 007)" = 7 ]
  [ "$(strip_zeros 000)" = 0 ]
  [ "$(strip_zeros 0)" = 0 ]
  [ "$(strip_zeros 00018446744073709551616)" = 18446744073709551616 ]
}

@test "common-lib: num_gt: num_gt and num_lt compare 20-digit values without wrapping" {
  num_gt 18446744073709551616 18446744073709551615
  num_gt 18446744073709551616 9223372036854775807
  run ! num_gt 9223372036854775807 18446744073709551616
  num_lt 9223372036854775807 18446744073709551616
  run ! num_lt 18446744073709551616 18446744073709551616
  run ! num_gt 007 7
  num_gt 100 99
  run num_gt 1a 2
  [ "$status" -eq 2 ]
  run num_lt 1 -2
  [ "$status" -eq 2 ]
}

@test "common-lib: num_add: adds 20-digit values with carry and refuses non-digits" {
  [ "$(num_add 18446744073709551615 1)" = 18446744073709551616 ]
  [ "$(num_add 99999999999999999999 1)" = 100000000000000000000 ]
  [ "$(num_add 007 0)" = 7 ]
  [ "$(num_add 0 0)" = 0 ]
  run num_add 1 x
  [ "$status" -eq 1 ]
  [ "$output" = 0 ]
}

@test "common-lib: is_uint: accepts digit strings only" {
  is_uint 0
  is_uint 0123
  is_uint 18446744073709551616
  run ! is_uint ''
  run ! is_uint -1
  run ! is_uint 1a
  run ! is_uint ' 1'
}

# --- clock -------------------------------------------------------------------

@test "common-lib: now_epoch: honours SDLC_NOW_EPOCH and refuses a non-integer" {
  SDLC_NOW_EPOCH=1700000000 run now_epoch
  [ "$status" -eq 0 ]
  [ "$output" = 1700000000 ]
  unset SDLC_NOW_EPOCH
  run now_epoch
  [ "$status" -eq 0 ]
  is_uint "$output"
  SDLC_NOW_EPOCH=yesterday run --separate-stderr now_epoch
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'SDLC_NOW_EPOCH is not a non-negative integer'* ]]
}

@test "common-lib: utc_now: formats SDLC_NOW_EPOCH as an ISO 8601 UTC time" {
  SDLC_NOW_EPOCH=1700000000 run utc_now
  [ "$status" -eq 0 ]
  [ "$output" = 2023-11-14T22:13:20Z ]
  SDLC_NOW_EPOCH=0 run utc_now
  [ "$output" = 1970-01-01T00:00:00Z ]
}

@test "common-lib: utc_stamp: formats SDLC_NOW_EPOCH as a compact UTC stamp" {
  SDLC_NOW_EPOCH=1700000000 run utc_stamp
  [ "$status" -eq 0 ]
  [ "$output" = 20231114T221320Z ]
  unset SDLC_NOW_EPOCH
  run utc_stamp
  [[ "$output" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
}

# --- tool probes ----------------------------------------------------------------

@test "common-lib: have_cmd: follows command -v" {
  have_cmd bash
  have_cmd git
  run ! have_cmd definitely-not-a-tool-of-this-suite
  run ! have_cmd ''
}

@test "common-lib: have_jq: true exactly when jq is on PATH" {
  local sb
  sb="$(sandbox_path)"
  run env PATH="$sb" "$BASH" -c 'source "$1"; have_jq' _ "$LIB"
  [ "$status" -eq 1 ]
  make_stub "$sb" jq 'exit 0'
  run env PATH="$sb" "$BASH" -c 'source "$1"; have_jq' _ "$LIB"
  [ "$status" -eq 0 ]
}

@test "common-lib: have_pyyaml: true exactly when python3 -c 'import yaml' succeeds" {
  local want=0 shadow
  python3 -c 'import yaml' 2>/dev/null || want=1
  run have_pyyaml
  [ "$status" -eq "$want" ]
  shadow="$(shadow_module yaml)"
  PYTHONPATH="$shadow" run have_pyyaml
  [ "$status" -eq 1 ]
}

@test "common-lib: have_yq: rejects the kislyuk stub and caches the verdict" {
  unset SDLC_FORCE_PYTHON_YAML _SDLC_YQ_OK
  PATH="$KISLYUK_BIN:$PATH"
  [ "$(printf 'a: [1]\n' | yq '.a | type')" = '"array"' ]
  run have_yq
  [ "$status" -eq 1 ]
  have_yq || true
  [ "$_SDLC_YQ_OK" = 0 ]
}

@test "common-lib: have_yq: accepts a yq that answers !!seq and caches the verdict" {
  local dir="$BATS_TEST_TMPDIR/mikefarah"
  unset SDLC_FORCE_PYTHON_YAML _SDLC_YQ_OK
  make_stub "$dir" yq "cat >/dev/null; printf '%s\\n' '!!seq'"
  PATH="$dir:$PATH"
  have_yq
  [ "$_SDLC_YQ_OK" = 1 ]
  # The cached verdict wins over a later PATH change in the same process.
  PATH="$KISLYUK_BIN:$PATH"
  have_yq
}

@test "common-lib: have_yq: SDLC_FORCE_PYTHON_YAML=1 is false regardless of the cache" {
  _SDLC_YQ_OK=1 SDLC_FORCE_PYTHON_YAML=1 run have_yq
  [ "$status" -eq 1 ]
  unset SDLC_FORCE_PYTHON_YAML
  _SDLC_YQ_OK=1 run have_yq
  [ "$status" -eq 0 ]
}

@test "common-lib: require_yaml_toolchain: passes with a backend and dies without yq and PyYAML" {
  local shadow
  run require_yaml_toolchain
  [ "$status" -eq 0 ]
  shadow="$(shadow_module yaml)"
  write_yaml_sample "$BATS_TEST_TMPDIR/sample.yml"
  PATH="$KISLYUK_BIN:$PATH" PYTHONPATH="$shadow" run --separate-stderr require_yaml_toolchain
  [ "$status" -eq 1 ]
  [ "$stderr" = '[rust-sdlc][ERROR] no YAML toolchain: install mikefarah yq v4, or python3 with PyYAML' ]
  SDLC_FORCE_PYTHON_YAML=1 PYTHONPATH="$shadow" run --separate-stderr yaml_get "$BATS_TEST_TMPDIR/sample.yml" name
  [ "$status" -eq 1 ]
  [ "$stderr" = '[rust-sdlc][ERROR] no YAML toolchain: install mikefarah yq v4, or python3 with PyYAML' ]
}

# --- YAML access (both backends) ---------------------------------------------------

@test "common-lib: yaml_get: scalars, booleans, null and absent keys are byte-identical on both backends" {
  local f="$BATS_TEST_TMPDIR/sample.yml"
  write_yaml_sample "$f"
  expect_case yaml_get "$f" name 0 'billing-service\n'
  expect_case yaml_get "$f" count 0 '42\n'
  expect_case yaml_get "$f" ratio 0 '0.5\n'
  expect_case yaml_get "$f" enabled 0 'true\n'
  expect_case yaml_get "$f" disabled 0 'false\n'
  expect_case yaml_get "$f" nothing 0 ''
  expect_case yaml_get "$f" tilde 0 ''
  expect_case yaml_get "$f" empty 0 '\n'
  expect_case yaml_get "$f" absent 0 ''
  expect_case yaml_get "$f" map.absent.deeper 0 ''
  expect_case yaml_get "$f" map 0 ''
  expect_case yaml_get "$f" map.deep.key 0 '7\n'
  expect_case yaml_get "$f" map.dash-key 0 'dashed\n'
  expect_case yaml_get "$f" quoted_bool 0 'true\n'
  expect_case yaml_get "$f" legacy_yes 0 'yes\n'
  expect_case yaml_get "$f" clock 0 '10:30\n'
}

@test "common-lib: yaml_get: booleans lower-cased, numbers as written on both backends" {
  local f="$BATS_TEST_TMPDIR/sample.yml"
  write_yaml_sample "$f"
  expect_case yaml_get "$f" upper_bool 0 'true\n'
  expect_case yaml_get "$f" upper_false 0 'false\n'
  expect_case yaml_get "$f" zero_eight 0 '08\n'
  expect_case yaml_get "$f" octal_like 0 '007\n'
  expect_case yaml_get "$f" hex 0 '0x1F\n'
  expect_case yaml_get "$f" plus 0 '+5\n'
  expect_case yaml_get "$f" trailing_zero 0 '1.50\n'
  expect_case yaml_get "$f" exp 0 '1e3\n'
  expect_case yaml_get "$f" cased_list 0 'true\nnull\n1.50\nfalse\n007\n'
}

@test "common-lib: yaml_get: a list prints one scalar item per line on both backends" {
  local f="$BATS_TEST_TMPDIR/sample.yml"
  write_yaml_sample "$f"
  expect_case yaml_get "$f" list 0 'alpha\nbeta gamma\n3\ntrue\nnull\n'
  expect_case yaml_get "$f" empty_list 0 ''
}

@test "common-lib: yaml_get: dies on a missing file and on an invalid key" {
  local f="$BATS_TEST_TMPDIR/sample.yml"
  write_yaml_sample "$f"
  run --separate-stderr yaml_get "$BATS_TEST_TMPDIR/absent.yml" name
  [ "$status" -eq 1 ]
  [ "$stderr" = "[rust-sdlc][ERROR] yaml_get: no such file: $BATS_TEST_TMPDIR/absent.yml" ]
  run --separate-stderr yaml_get "$f" 'name | del(.)'
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'yaml_get: invalid key: name | del(.)' ]]
  run --separate-stderr yaml_get "$f" ''
  [ "$status" -eq 1 ]
}

@test "common-lib: yaml_get_list: list items, nothing for scalars, maps and absent keys" {
  local f="$BATS_TEST_TMPDIR/sample.yml"
  write_yaml_sample "$f"
  expect_case yaml_get_list "$f" list 0 'alpha\nbeta gamma\n3\ntrue\nnull\n'
  expect_case yaml_get_list "$f" cased_list 0 'true\nnull\n1.50\nfalse\n007\n'
  expect_case yaml_get_list "$f" empty_list 0 ''
  expect_case yaml_get_list "$f" name 0 ''
  expect_case yaml_get_list "$f" map 0 ''
  expect_case yaml_get_list "$f" nothing 0 ''
  expect_case yaml_get_list "$f" absent 0 ''
}

@test "common-lib: yaml_is_list: true only for sequences on both backends" {
  local f="$BATS_TEST_TMPDIR/sample.yml"
  write_yaml_sample "$f"
  expect_case yaml_is_list "$f" list 0 ''
  expect_case yaml_is_list "$f" empty_list 0 ''
  expect_case yaml_is_list "$f" name 1 ''
  expect_case yaml_is_list "$f" map 1 ''
  expect_case yaml_is_list "$f" nothing 1 ''
  expect_case yaml_is_list "$f" absent 1 ''
}

@test "common-lib: yaml_has: true for a key set to null, false for an absent key" {
  local f="$BATS_TEST_TMPDIR/sample.yml"
  write_yaml_sample "$f"
  expect_case yaml_has "$f" nothing 0 ''
  expect_case yaml_has "$f" tilde 0 ''
  expect_case yaml_has "$f" disabled 0 ''
  expect_case yaml_has "$f" map.inner 0 ''
  expect_case yaml_has "$f" map.dash-key 0 ''
  expect_case yaml_has "$f" zero_eight 0 ''
  expect_case yaml_has "$f" absent 1 ''
  expect_case yaml_has "$f" map.absent 1 ''
  expect_case yaml_has "$f" absent.child 1 ''
}

@test "common-lib: yaml_type: names every value kind on both backends" {
  local f="$BATS_TEST_TMPDIR/sample.yml"
  write_yaml_sample "$f"
  expect_case yaml_type "$f" name 0 'str\n'
  expect_case yaml_type "$f" count 0 'int\n'
  expect_case yaml_type "$f" ratio 0 'float\n'
  expect_case yaml_type "$f" enabled 0 'bool\n'
  expect_case yaml_type "$f" nothing 0 'null\n'
  expect_case yaml_type "$f" tilde 0 'null\n'
  expect_case yaml_type "$f" empty 0 'str\n'
  expect_case yaml_type "$f" list 0 'list\n'
  expect_case yaml_type "$f" map 0 'map\n'
  expect_case yaml_type "$f" quoted_bool 0 'str\n'
  expect_case yaml_type "$f" legacy_yes 0 'str\n'
  expect_case yaml_type "$f" clock 0 'str\n'
  expect_case yaml_type "$f" upper_bool 0 'bool\n'
  expect_case yaml_type "$f" upper_false 0 'bool\n'
  expect_case yaml_type "$f" octal_like 0 'int\n'
  expect_case yaml_type "$f" hex 0 'int\n'
  expect_case yaml_type "$f" plus 0 'int\n'
  expect_case yaml_type "$f" trailing_zero 0 'float\n'
  expect_case yaml_type "$f" exp 0 'float\n'
  expect_case yaml_type "$f" cased_list 0 'list\n'
  # zero_eight (08) is a float to go-yaml v3 and to the PyYAML loader, but a
  # go-yaml that drops YAML 1.1 octals may call it an int: not asserted.
  expect_case yaml_type "$f" absent 0 'absent\n'
  expect_case yaml_type "$f" map.absent 0 'absent\n'
}

@test "common-lib: yaml_to_json: prints the document as JSON on both backends" {
  local f="$BATS_TEST_TMPDIR/doc.yml"
  cat >"$f" <<'EOF'
name: billing
count: 3
enabled: false
nothing: null
list:
  - a
  - 2
  - true
map:
  inner: value
  deep:
    key: 7
empty_list: []
EOF
  parity yaml_to_json "$f"
  [ "$PARITY_STATUS" -eq 0 ]
  cat >"$BATS_TEST_TMPDIR/want.json" <<'EOF'
{
  "name": "billing",
  "count": 3,
  "enabled": false,
  "nothing": null,
  "list": [
    "a",
    2,
    true
  ],
  "map": {
    "inner": "value",
    "deep": {
      "key": 7
    }
  },
  "empty_list": []
}
EOF
  cmp "$BATS_TEST_TMPDIR/want.json" "$PARITY_OUT"
}

@test "common-lib: yaml_to_json: numbers and booleans as Go's encoding/json writes them on both backends" {
  local f="$BATS_TEST_TMPDIR/numbers.yml"
  cat >"$f" <<'EOF'
upper_bool: True
octal_like: 007
zero_eight: 08
hex: 0x1F
plus: +5
trailing_zero: 1.50
whole: 80.0
exp: 1e3
small: 0.00001
quoted: '007'
EOF
  parity yaml_to_json "$f"
  [ "$PARITY_STATUS" -eq 0 ]
  cat >"$BATS_TEST_TMPDIR/want.json" <<'EOF'
{
  "upper_bool": true,
  "octal_like": 7,
  "zero_eight": 8,
  "hex": 31,
  "plus": 5,
  "trailing_zero": 1.5,
  "whole": 80,
  "exp": 1000,
  "small": 0.00001,
  "quoted": "007"
}
EOF
  cmp "$BATS_TEST_TMPDIR/want.json" "$PARITY_OUT"
}

@test "common-lib: yaml_to_json: exits 1 with the parser's first error line" {
  local f="$BATS_TEST_TMPDIR/bad.yml"
  printf 'a: [1, 2\nb: c\n' >"$f"
  for force in 0 1; do
    SDLC_FORCE_PYTHON_YAML="$force" run --separate-stderr yaml_to_json "$f"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [ "${#stderr_lines[@]}" -eq 1 ]
    [[ "$stderr" == "[rust-sdlc][ERROR] yaml: $f: "?* ]]
    [[ "$stderr" != *Traceback* ]]
  done
  SDLC_FORCE_PYTHON_YAML=1 run --separate-stderr yaml_to_json "$f"
  [ "$stderr" = "[rust-sdlc][ERROR] yaml: $f: while parsing a flow sequence" ]
}

@test "common-lib: yaml_parses: true for valid YAML, false for malformed, dies for a missing file" {
  local good="$BATS_TEST_TMPDIR/sample.yml" bad="$BATS_TEST_TMPDIR/bad.yml"
  write_yaml_sample "$good"
  printf 'a: [1, 2\nb: c\n' >"$bad"
  expect_case yaml_parses "$good" '' 0 ''
  printf 'month: 08\nok: yes\n' >"$BATS_TEST_TMPDIR/month.yml"
  expect_case yaml_parses "$BATS_TEST_TMPDIR/month.yml" '' 0 ''
  expect_case yaml_has "$BATS_TEST_TMPDIR/month.yml" ok 0 ''
  expect_case yaml_get "$BATS_TEST_TMPDIR/month.yml" month 0 '08\n'
  parity yaml_parses "$bad"
  [ "$PARITY_STATUS" -eq 1 ]
  [ ! -s "$PARITY_OUT" ]
  SDLC_FORCE_PYTHON_YAML=1 run --separate-stderr yaml_parses "$bad"
  [ "$status" -eq 1 ]
  [ -z "$stderr" ]
  run --separate-stderr yaml_parses "$BATS_TEST_TMPDIR/absent.yml"
  [ "$status" -eq 1 ]
  [ "$stderr" = "[rust-sdlc][ERROR] yaml_parses: no such file: $BATS_TEST_TMPDIR/absent.yml" ]
}

@test "common-lib: yaml_squote: doubles single quotes and strips control characters" {
  run yaml_squote "it's"
  [ "$output" = "'it''s'" ]
  run yaml_squote $'a\tb\x1bc\x7fd\ne\r'
  [ "$output" = "'abcde'" ]
  run yaml_squote "Protected configuration"
  [ "$output" = "'Protected configuration'" ]
  run yaml_squote ''
  [ "$output" = "''" ]
}

# --- JSON and TOML access ---------------------------------------------------------

@test "common-lib: json_get: identical output with jq and without jq" {
  local f="$FIXTURE_REPO/.sqlx/query-fixture.json" sb key
  sb="$(sandbox_path python3)"
  run env PATH="$sb" "$BASH" -c 'source "$1"; have_jq' _ "$LIB"
  [ "$status" -eq 1 ]
  for key in db_name hash describe describe.columns describe.parameters.Left \
    describe.parameters describe.absent absent.deeper query.sub; do
    json_get "$f" "$key" >"$BATS_TEST_TMPDIR/default.out"
    env PATH="$sb" "$BASH" -c 'source "$1"; json_get "$2" "$3"' _ "$LIB" "$f" "$key" \
      >"$BATS_TEST_TMPDIR/python.out"
    cmp "$BATS_TEST_TMPDIR/default.out" "$BATS_TEST_TMPDIR/python.out"
  done
  [ "$(json_get "$f" db_name)" = PostgreSQL ]
  printf '%s\n' Uuid Text Text Int8 | cmp - <(json_get "$f" describe.parameters.Left)
  [ "$(json_get "$f" describe)" = '{"columns":[],"parameters":{"Left":["Uuid","Text","Text","Int8"]},"nullable":[]}' ]
  [ -z "$(json_get "$f" describe.columns)" ]
  [ -z "$(json_get "$f" describe.absent)" ]
}

@test "common-lib: json_get: reads stdin with - and fails on malformed JSON" {
  local sb
  sb="$(sandbox_path python3)"
  run json_get - upstreamVersions.bmadCommit <"$FIXTURE_REPO/dot-bmalph/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = d1163f85 ]
  printf '{"a": true, "b": [1, null, {"c": "d"}], "n": null}\n' >"$BATS_TEST_TMPDIR/v.json"
  for key in a b n; do
    json_get - "$key" <"$BATS_TEST_TMPDIR/v.json" >"$BATS_TEST_TMPDIR/default.out"
    env PATH="$sb" "$BASH" -c 'source "$1"; json_get - "$2"' _ "$LIB" "$key" \
      <"$BATS_TEST_TMPDIR/v.json" >"$BATS_TEST_TMPDIR/python.out"
    cmp "$BATS_TEST_TMPDIR/default.out" "$BATS_TEST_TMPDIR/python.out"
  done
  [ "$(json_get - a <"$BATS_TEST_TMPDIR/v.json")" = true ]
  printf '1\nnull\n{"c":"d"}\n' | cmp - <(json_get - b <"$BATS_TEST_TMPDIR/v.json")
  printf '{"a": ' >"$BATS_TEST_TMPDIR/bad.json"
  run --separate-stderr json_get "$BATS_TEST_TMPDIR/bad.json" a
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run --separate-stderr env PATH="$sb" "$BASH" -c 'source "$1"; json_get "$2" a' _ "$LIB" "$BATS_TEST_TMPDIR/bad.json"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run --separate-stderr json_get "$BATS_TEST_TMPDIR/absent.json" a
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'json_get: no such file'* ]]
}

@test "common-lib: toml_get: reads workspace.package.description and toolchain.channel" {
  run toml_get "$FIXTURE_REPO/Cargo.toml" workspace.package.description
  [ "$status" -eq 0 ]
  [ "$output" = 'Rust Template' ]
  run toml_get "$FIXTURE_REPO/rust-toolchain.toml" toolchain.channel
  [ "$status" -eq 0 ]
  [ "$output" = 1.99.1 ]
  run toml_get "$FIXTURE_REPO/Cargo.toml" workspace.package.publish
  [ "$output" = false ]
  run toml_get "$FIXTURE_REPO/Cargo.toml" workspace.dependencies.axum
  [ "$output" = '{"version":"0.8.9","features":["macros"]}' ]
  run toml_get "$FIXTURE_REPO/Cargo.toml" workspace.dependencies.async-graphql.version
  [ "$output" = 7.2.1 ]
  run toml_get "$FIXTURE_REPO/Cargo.toml" workspace.nope
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: toml_get_list: reads workspace.members one per line" {
  run toml_get_list "$FIXTURE_REPO/Cargo.toml" workspace.members
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 13 ]
  [ "${lines[0]}" = crates/billing/invoice/application ]
  [ "${lines[12]}" = xtask ]
  run toml_get_list "$FIXTURE_REPO/Cargo.toml" workspace.dependencies.sqlx.features
  [ "${#lines[@]}" -eq 6 ]
  [ "${lines[2]}" = postgres ]
  run toml_get_list "$FIXTURE_REPO/Cargo.toml" workspace.package.description
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: toml_has: true for a present key, false for an absent one" {
  toml_has "$FIXTURE_REPO/Cargo.toml" workspace.members
  toml_has "$FIXTURE_REPO/Cargo.toml" workspace.dependencies.sqlx
  toml_has "$FIXTURE_REPO/rust-toolchain.toml" toolchain.channel
  run toml_has "$FIXTURE_REPO/Cargo.toml" workspace.nope
  [ "$status" -eq 1 ]
  run toml_has "$FIXTURE_REPO/Cargo.toml" workspace.members.deeper
  [ "$status" -eq 1 ]
}

@test "common-lib: toml_get: dies without python3 3.11+ tomllib" {
  local shadow sb
  shadow="$(shadow_module tomllib)"
  PYTHONPATH="$shadow" run --separate-stderr toml_get "$FIXTURE_REPO/rust-toolchain.toml" toolchain.channel
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$stderr" = '[rust-sdlc][ERROR] python3 3.11+ with tomllib is required' ]
  sb="$(sandbox_path)"
  run --separate-stderr env PATH="$sb" "$BASH" -c 'source "$1"; toml_has "$2" toolchain.channel' \
    _ "$LIB" "$FIXTURE_REPO/rust-toolchain.toml"
  [ "$status" -eq 1 ]
  [ "$stderr" = '[rust-sdlc][ERROR] python3 3.11+ with tomllib is required' ]
}

# --- project profile ----------------------------------------------------------------

@test "common-lib: profile_path: prints DIR/.claude/rust-sdlc.yml, PWD by default" {
  run profile_path /srv/billing-service
  [ "$output" = /srv/billing-service/.claude/rust-sdlc.yml ]
  cd "$BATS_TEST_TMPDIR"
  run profile_path
  [ "$output" = "$PWD/.claude/rust-sdlc.yml" ]
}

@test "common-lib: profile_get: the default only for absent or null keys" {
  local f="$BATS_TEST_TMPDIR/rust-sdlc.yml"
  printf '%s\n' 'schema_version: 1' 'review:' '  enabled: false' '  nothing: null' \
    "  empty: ''" '  agents:' '    - code-quality' '    - security' 'quality:' \
    '  coverage_lines: 90' >"$f"
  parity profile_get "$f" review.enabled fallback
  [ "$(cat "$PARITY_OUT")" = false ]
  parity profile_get "$f" quality.coverage_lines 80
  [ "$(cat "$PARITY_OUT")" = 90 ]
  parity profile_get "$f" review.nothing fallback
  [ "$(cat "$PARITY_OUT")" = fallback ]
  parity profile_get "$f" review.absent fallback
  [ "$(cat "$PARITY_OUT")" = fallback ]
  parity profile_get "$f" review.empty fallback
  printf '\n' | cmp - "$PARITY_OUT"
  parity profile_get "$f" review.agents
  printf '%s\n' code-quality security | cmp - "$PARITY_OUT"
  parity profile_get "$f" review.absent
  printf '\n' | cmp - "$PARITY_OUT"
}

@test "common-lib: profile_require: dies naming a missing or null key" {
  local f="$BATS_TEST_TMPDIR/rust-sdlc.yml"
  printf '%s\n' 'review:' '  enabled: false' '  nothing: null' >"$f"
  run profile_require "$f" review.enabled
  [ "$status" -eq 0 ]
  [ "$output" = false ]
  run --separate-stderr profile_require "$f" review.nothing
  [ "$status" -eq 1 ]
  [ "$stderr" = "[rust-sdlc][ERROR] profile: required key 'review.nothing' missing or null in $f" ]
  SDLC_FORCE_PYTHON_YAML=1 run --separate-stderr profile_require "$f" quality.coverage_lines
  [ "$status" -eq 1 ]
  [ "$stderr" = "[rust-sdlc][ERROR] profile: required key 'quality.coverage_lines' missing or null in $f" ]
}

# --- plugin and repository identity ---------------------------------------------------

@test "common-lib: resolve_plugin_root: prefers a CLAUDE_PLUGIN_ROOT directory" {
  mkdir -p "$BATS_TEST_TMPDIR/installed"
  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/installed" run resolve_plugin_root
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/installed" ]
}

@test "common-lib: resolve_plugin_root: dies when CLAUDE_PLUGIN_ROOT is not a directory" {
  : >"$BATS_TEST_TMPDIR/a-file"
  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/missing" run --separate-stderr resolve_plugin_root
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"CLAUDE_PLUGIN_ROOT is not a directory: $BATS_TEST_TMPDIR/missing" ]]
  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/a-file" run resolve_plugin_root
  [ "$status" -eq 1 ]
}

@test "common-lib: resolve_plugin_root: falls back to the library's ../.." {
  unset CLAUDE_PLUGIN_ROOT
  cd "$BATS_TEST_TMPDIR"
  run resolve_plugin_root
  [ "$status" -eq 0 ]
  [ "$output" = "$PLUGIN_ROOT" ]
  [ -f "$output/scripts/lib/common.sh" ]
}

@test "common-lib: resolve_repo_slug: parses https, git@ and ssh:// github.com origins" {
  local repo="$BATS_TEST_TMPDIR/billing-service" url
  rr_materialize "$repo"
  run resolve_repo_slug "$repo"
  [ "$status" -eq 0 ]
  [ "$output" = acme/billing-service ]
  for url in https://github.com/octo/ledger https://github.com/octo/ledger.git \
    git@github.com:octo/ledger.git git@github.com:octo/ledger \
    ssh://git@github.com/octo/ledger.git ssh://git@github.com/octo/ledger; do
    git -C "$repo" remote set-url origin "$url"
    run resolve_repo_slug "$repo"
    [ "$status" -eq 0 ]
    [ "$output" = octo/ledger ]
  done
  cd "$repo"
  run resolve_repo_slug
  [ "$output" = octo/ledger ]
  [ ! -s "$STUB_GH_LOG" ]
}

@test "common-lib: resolve_repo_slug: falls back to gh repo view, else returns 1 with no output" {
  local repo="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$repo"
  git -C "$repo" remote set-url origin https://git.example.invalid/octo/ledger.git
  STUB_GH_OUTPUT=octo/from-gh run resolve_repo_slug "$repo"
  [ "$status" -eq 0 ]
  [ "$output" = octo/from-gh ]
  grep -qxF 'gh repo view --json nameWithOwner --jq .nameWithOwner' "$STUB_GH_LOG"
  STUB_GH_EXIT=1 run --separate-stderr resolve_repo_slug "$repo"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  STUB_GH_OUTPUT='not a slug' run --separate-stderr resolve_repo_slug "$repo"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  git -C "$repo" remote remove origin
  STUB_GH_OUTPUT=octo/no-origin run resolve_repo_slug "$repo"
  [ "$output" = octo/no-origin ]
}

@test "common-lib: default_branch: origin/HEAD, then main, then master, then main" {
  local repo="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$repo"
  run default_branch "$repo"
  [ "$output" = main ]
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
  run default_branch "$repo"
  [ "$output" = develop ]
  git_init_empty "$BATS_TEST_TMPDIR/legacy" master
  run default_branch "$BATS_TEST_TMPDIR/legacy"
  [ "$output" = master ]
  git_init_empty "$BATS_TEST_TMPDIR/remote-master" trunk
  git -C "$BATS_TEST_TMPDIR/remote-master" update-ref refs/remotes/origin/master HEAD
  run default_branch "$BATS_TEST_TMPDIR/remote-master"
  [ "$output" = master ]
  git_init_empty "$BATS_TEST_TMPDIR/trunk" trunk
  run default_branch "$BATS_TEST_TMPDIR/trunk"
  [ "$output" = main ]
  mkdir -p "$BATS_TEST_TMPDIR/not-a-repo"
  cd "$BATS_TEST_TMPDIR/not-a-repo"
  run default_branch
  [ "$status" -eq 0 ]
  [ "$output" = main ]
}

# --- validators -----------------------------------------------------------------------

@test "common-lib: is_commit_subject: accepts every FR-2 fixed subject with N=1" {
  local s t
  for s in 'docs(#1): add planning bundle 1-add-invoice-export' \
    'feat(#1): story 1.1 add the export query' \
    'fix(#1): address review gate iteration 1 findings' \
    'fix(#1): resolve Static analysis failure' \
    'fix(#1): address review comment on crates/service/src/main.rs' \
    'feat(#1): add billing/invoice bounded context' \
    'chore(#1): import template acme/rust-template at 3e0bd3e' \
    'chore(#1): initialize service from template' \
    'chore(#1): add rust-backend-sdlc profile and governance' \
    'docs(#1): add QA fix story 1'; do
    is_commit_subject "$s" || {
      printf 'rejected: %s\n' "$s"
      return 1
    }
  done
  for t in feat fix refactor build chore ci docs style perf test; do
    is_commit_subject "$t(#1): x"
  done
  is_commit_subject 'fix(#1234): x'
}

@test "common-lib: is_commit_subject: rejects the AC-2.1 subjects, #0, a blank subject and a second line" {
  local s
  for s in 'review: gate iteration 2 remediation' 'Apply review suggestion: x' \
    'feat: x' 'feat(#): x' 'Feat (#1): x' 'feat(#0): x' 'feat(#01): x' \
    'feat (#1): x' 'feat(#1):x' 'feat(#1): ' 'feat(#1):  x' 'feature(#1): x' \
    $'feat(#1): x\nsecond line' $'feat(#1): x\r' ''; do
    if is_commit_subject "$s"; then
      printf 'accepted: %q\n' "$s"
      return 1
    fi
  done
}

@test "common-lib: is_kebab: follows the kebab regex and the length bound" {
  is_kebab a
  is_kebab add-invoice-export
  is_kebab v2-api-3
  run ! is_kebab Add
  run ! is_kebab a--b
  run ! is_kebab -a
  run ! is_kebab a-
  run ! is_kebab 1a
  run ! is_kebab a_b
  run ! is_kebab ''
  is_kebab "$(printf 'a%.0s' {1..50})"
  run ! is_kebab "$(printf 'a%.0s' {1..51})"
  is_kebab abcdefghij 10
  run ! is_kebab abcdefghijk 10
  run is_kebab abc x
  [ "$status" -eq 2 ]
}

@test "common-lib: is_slug: owner/name only" {
  is_slug acme/billing-service
  is_slug A.b_c-d/e.f
  run ! is_slug acme
  run ! is_slug a/b/c
  run ! is_slug /b
  run ! is_slug a/
  run ! is_slug 'a b/c'
  run ! is_slug ''
}

@test "common-lib: is_semver: MAJOR.MINOR.PATCH without leading zeros" {
  is_semver 0.1.0
  is_semver 1.99.1
  is_semver 10.20.30
  run ! is_semver 01.2.3
  run ! is_semver 1.02.3
  run ! is_semver 1.2
  run ! is_semver 1.2.3-rc.1
  run ! is_semver v1.2.3
  run ! is_semver ''
}

# --- safe writes ---------------------------------------------------------------------

@test "common-lib: safe_write_target: accepts a new or regular file inside ROOT" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/sub"
  : >"$root/existing.txt"
  safe_write_target "$root/new.txt" "$root"
  safe_write_target "$root/existing.txt" "$root"
  safe_write_target "$root/sub/new.txt" "$root"
  safe_write_target "$root/missing/deeper/new.txt" "$root/"
  ln -s "$root" "$BATS_TEST_TMPDIR/root-link"
  safe_write_target "$BATS_TEST_TMPDIR/root-link/new.txt" "$BATS_TEST_TMPDIR/root-link"
  cd "$root"
  safe_write_target sub/new.txt .
  safe_write_target target/rust-sdlc/tmp/x.md "$root"
}

@test "common-lib: safe_write_target: takes a relative PATH from a subdirectory of ROOT" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/sub/deeper" "$BATS_TEST_TMPDIR/outside"
  cd "$root/sub"
  safe_write_target x.txt "$root"
  safe_write_target deeper/y.txt "$root"
  safe_write_target missing/z.txt "$root"
  safe_write_target x.txt "$PWD/.."
  run safe_write_target ../../outside/f.txt "$root"
  [ "$status" -eq 1 ]
  cd "$BATS_TEST_TMPDIR/outside"
  run --separate-stderr safe_write_target f.txt "$root"
  [ "$status" -eq 1 ]
  [ "$stderr" = "[rust-sdlc][ERROR] refusing to write f.txt: it is outside $root" ]
}

@test "common-lib: safe_write_target: refuses a symlink" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root"
  : >"$root/real.txt"
  ln -s "$root/real.txt" "$root/link.txt"
  ln -s "$root/nowhere.txt" "$root/dangling.txt"
  run --separate-stderr safe_write_target "$root/link.txt" "$root"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'symbolic link'* ]]
  run safe_write_target "$root/dangling.txt" "$root"
  [ "$status" -eq 1 ]
}

@test "common-lib: safe_write_target: refuses a non-regular file" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/dir"
  mkfifo "$root/fifo"
  run --separate-stderr safe_write_target "$root/dir" "$root"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'not a regular file'* ]]
  run safe_write_target "$root/fifo" "$root"
  [ "$status" -eq 1 ]
  : >"$root/plain"
  run --separate-stderr safe_write_target "$root/plain/child.txt" "$root"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'not a directory'* ]]
}

@test "common-lib: safe_write_target: refuses a symlinked parent" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/real/sub" "$BATS_TEST_TMPDIR/outside"
  ln -s "$root/real" "$root/linked"
  ln -s "$BATS_TEST_TMPDIR/outside" "$root/escape"
  run --separate-stderr safe_write_target "$root/linked/f.txt" "$root"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"the parent $root/linked is a symbolic link"* ]]
  run safe_write_target "$root/linked/sub/f.txt" "$root"
  [ "$status" -eq 1 ]
  run safe_write_target "$root/linked/missing/f.txt" "$root"
  [ "$status" -eq 1 ]
  run safe_write_target "$root/escape/f.txt" "$root"
  [ "$status" -eq 1 ]
}

@test "common-lib: safe_write_target: refuses a path outside ROOT" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root" "$BATS_TEST_TMPDIR/outside"
  run --separate-stderr safe_write_target "$BATS_TEST_TMPDIR/outside/f.txt" "$root"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'outside'* ]]
  run safe_write_target "$root/../outside/f.txt" "$root"
  [ "$status" -eq 1 ]
  run safe_write_target "$root/sub/../../outside/f.txt" "$root"
  [ "$status" -eq 1 ]
  cd "$root"
  run safe_write_target ../outside/f.txt .
  [ "$status" -eq 1 ]
  run safe_write_target f.txt "$BATS_TEST_TMPDIR/outside"
  [ "$status" -eq 1 ]
  run safe_write_target "$root/f.txt" "$BATS_TEST_TMPDIR/missing-root"
  [ "$status" -eq 1 ]
}

@test "common-lib: atomic_write: writes stdin through a same-directory temp file and mv -f" {
  local root="$BATS_TEST_TMPDIR/root" logbin="$BATS_TEST_TMPDIR/logbin" real_mv
  mkdir -p "$root"
  real_mv="$(type -P mv)"
  export MV_LOG="$BATS_TEST_TMPDIR/mv.log"
  make_stub "$logbin" mv "printf '%s\\n' \"\$*\" >>\"\$MV_LOG\"; exec '$real_mv' \"\$@\""
  printf 'old\n' >"$root/f.txt"
  PATH="$logbin:$PATH" atomic_write "$root/f.txt" < <(printf 'line one\nline two\n')
  printf 'line one\nline two\n' | cmp - "$root/f.txt"
  [ "$(wc -l <"$MV_LOG")" -eq 1 ]
  grep -qE "^-f (-- )?$root/\.f\.txt\.[A-Za-z0-9]+ $root/f\.txt$" "$MV_LOG"
  run ls -A "$root"
  [ "$output" = f.txt ]
  printf 'nested\n' | atomic_write "$root/a/b/c.txt"
  [ "$(cat "$root/a/b/c.txt")" = nested ]
}

@test "common-lib: atomic_write: keeps an existing file's mode" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root"
  printf 'x\n' >"$root/private.txt"
  chmod 640 "$root/private.txt"
  printf 'y\n' | atomic_write "$root/private.txt"
  [ "$(perms "$root/private.txt")" = '-rw-r-----' ]
  [ "$(cat "$root/private.txt")" = y ]
  printf '#!/bin/sh\n' >"$root/tool.sh"
  chmod 755 "$root/tool.sh"
  printf '#!/bin/sh\nexit 0\n' | atomic_write "$root/tool.sh"
  [ "$(perms "$root/tool.sh")" = '-rwxr-xr-x' ]
}

@test "common-lib: atomic_write: a new file gets 0666 & ~umask" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root"
  (
    umask 027
    printf 'a\n' | atomic_write "$root/a.txt"
  )
  [ "$(perms "$root/a.txt")" = '-rw-r-----' ]
  (
    umask 022
    printf 'b\n' | atomic_write "$root/b.txt"
  )
  [ "$(perms "$root/b.txt")" = '-rw-r--r--' ]
}

# --- template documents and the claude CLI ------------------------------------------------

@test "common-lib: human_gated_labels: maps the fixture's labels to check names (singular and plural forms)" {
  local repo="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$repo"
  run --separate-stderr human_gated_labels "$repo"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  printf '%s\t%s\n' approved-config-change 'Protected configuration' \
    approved-breaking-change 'OpenAPI breaking changes' \
    approved-breaking-change 'GraphQL breaking changes' >"$BATS_TEST_TMPDIR/want"
  printf '%s\n' "$output" | cmp - "$BATS_TEST_TMPDIR/want"
  cd "$repo"
  run --separate-stderr human_gated_labels
  printf '%s\n' "$output" | cmp - "$BATS_TEST_TMPDIR/want"
}

@test "common-lib: human_gated_labels: reads the service document, warns on an unmapped job, prints nothing without documents" {
  local repo="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$repo"
  cp "$PLUGIN_ROOT/tests/fixtures/variants/repository-settings-service.md.tpl" \
    "$repo/docs/repository-settings-service.md"
  printf '%s\n' '' '## Labels to create' '' '| Label | Purpose |' '| --- | --- |' \
    '| `approved-invoice-change` | approves an invoice export change; without it the job `invoice-e2e` fails |' \
    '| `approved-ghost-change` | without it the jobs `ghost-job` and `invoice-e2e` fail |' \
    >>"$repo/docs/repository-settings-service.md"
  run --separate-stderr human_gated_labels "$repo"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  [ "${lines[3]}" = "$(printf 'approved-invoice-change\tInvoice end-to-end tests')" ]
  [ "${lines[4]}" = "$(printf 'approved-ghost-change\tInvoice end-to-end tests')" ]
  [ "$stderr" = "[rust-sdlc][WARN] human_gated_labels: job 'ghost-job' of label 'approved-ghost-change' has no row in the job tables" ]
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  run --separate-stderr human_gated_labels "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: claude_supports_restricted: true exactly when claude --help lists --restricted" {
  local sb
  STUB_CLAUDE_RESTRICTED=1 run claude_supports_restricted
  [ "$status" -eq 0 ]
  STUB_CLAUDE_RESTRICTED=0 run claude_supports_restricted
  [ "$status" -eq 1 ]
  sb="$(sandbox_path grep)"
  run env PATH="$sb" "$BASH" -c 'source "$1"; claude_supports_restricted' _ "$LIB"
  [ "$status" -eq 1 ]
  grep -q '^claude --help' "$STUB_CLAUDE_LOG"
}
