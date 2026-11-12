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

# section: command helpers

# ch_repo — materializes the rust-repo fixture at
# $BATS_TEST_TMPDIR/billing-service and sets CH_REPO to it.
ch_repo() {
  CH_REPO="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$CH_REPO"
}

# ch_profile DIR [BASE_URL] — the minimal inline profile of the http_probe and
# protected_changes cases (never the golden profile): `schema_version: 1`,
# then `service:` with `base_url:` indented two spaces below it. BASE_URL is
# written verbatim (default 'http://127.0.0.1:8081', quoted).
ch_profile() {
  mkdir -p "$1/.claude"
  printf '%s\n' 'schema_version: 1' 'service:' "  base_url: ${2:-"'http://127.0.0.1:8081'"}" \
    >"$1/.claude/rust-sdlc.yml"
}

# ch_commit DIR MESSAGE — commits every change of DIR.
ch_commit() {
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# ch_hooks DIR — DIR/.githooks/{commit-msg,pre-commit,pre-push}, executable.
ch_hooks() {
  local hook
  mkdir -p "$1/.githooks"
  for hook in commit-msg pre-commit pre-push; do
    printf '#!/bin/sh\nexit 0\n' >"$1/.githooks/$hook"
    chmod 755 "$1/.githooks/$hook"
  done
}

# ch_sleep_stub [CODE] — a `sleep` first on PATH that appends its arguments to
# $BATS_TEST_TMPDIR/sleep.log, runs CODE and returns at once.
ch_sleep_stub() {
  make_stub "$BATS_TEST_TMPDIR/ch-bin" sleep "printf '%s\\n' \"\$*\" >>'$BATS_TEST_TMPDIR/sleep.log'
${1-}"
  : >"$BATS_TEST_TMPDIR/sleep.log"
  PATH="$BATS_TEST_TMPDIR/ch-bin:$PATH"
}

# ch_service — cd into $BATS_TEST_TMPDIR/svc (CH_SVC), a working directory
# with target/rust-sdlc/logs, tmp and new-service.
ch_service() {
  CH_SVC="$BATS_TEST_TMPDIR/svc"
  mkdir -p "$CH_SVC/target/rust-sdlc/logs" "$CH_SVC/target/rust-sdlc/tmp" \
    "$CH_SVC/target/rust-sdlc/new-service"
  cd "$CH_SVC"
}

# ch_capture_curl — a `curl` first on PATH that writes one argument per line
# to $CH_ARGV and its stdin to $CH_STDIN, then answers 204.
ch_capture_curl() {
  export CH_ARGV="$BATS_TEST_TMPDIR/curl.argv" CH_STDIN="$BATS_TEST_TMPDIR/curl.stdin"
  make_stub "$BATS_TEST_TMPDIR/ch-curl" curl \
    'printf "%s\n" "$@" >"$CH_ARGV"; cat >"$CH_STDIN"; printf "HTTP/1.1 204 No Content\r\n\r\n"'
  PATH="$BATS_TEST_TMPDIR/ch-curl:$PATH"
}

# ch_rejects ARG... — `common.sh http_probe ARG...` exits 2 with no stdout.
ch_rejects() {
  run --separate-stderr "$LIB" http_probe "$@"
  if [ "$status" -ne 2 ] || [ -n "$output" ]; then
    printf 'http_probe %q: status %s, stdout %s\n' "$*" "$status" "$output"
    return 1
  fi
}

# ch_add_member DIR MEMBER PACKAGE — registers MEMBER first in DIR/Cargo.toml's
# [workspace].members and writes DIR/MEMBER/Cargo.toml naming PACKAGE.
ch_add_member() {
  python3 -I - "$1/Cargo.toml" "$2" <<'PY'
import sys

path, member = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text.replace("members = [\n", 'members = [\n    "%s",\n' % member, 1))
PY
  mkdir -p "$1/$2"
  printf '[package]\nname = "%s"\nversion = "0.1.0"\n' "$3" >"$1/$2/Cargo.toml"
}

# --- layout and dispatch of the command helpers -------------------------------

@test "common-lib: layout: the command helpers section follows core and holds the seven helpers" {
  local core ch next line fn
  core="$(grep -nxF '# section: core' "$LIB" | cut -d: -f1)"
  ch="$(grep -nxF '# section: command helpers' "$LIB" | cut -d: -f1)"
  [ -n "$ch" ]
  [ "$ch" -gt "$core" ]
  # A3 order: core, then command helpers; the dispatch trailer stays last.
  [ "$(grep '^# section: ' "$LIB" | sed -n 2p)" = '# section: command helpers' ]
  [ "$(grep '^# section: ' "$LIB" | tail -n 1)" = '# section: dispatch (keep last)' ]
  next="$(awk -v from="$ch" 'NR > from && /^# section: / { print NR; exit }' "$LIB")"
  for fn in derive_issue_number commit_msg_file hooks_active wait_log http_probe \
    protected_changes validate_context_name; do
    line="$(grep -nxF "$fn() {" "$LIB" | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$ch" ]
    [ "$line" -lt "$next" ]
  done
  # Private helpers of the section carry its _ch_ prefix.
  run awk -v from="$ch" -v to="$next" 'NR > from && NR < to && /^[A-Za-z_][A-Za-z0-9_]*\(\) \{$/' "$LIB"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -vE '^(_ch_[a-z_]+|derive_issue_number|commit_msg_file|hooks_active|wait_log|http_probe|protected_changes|validate_context_name)\(\) \{$' && return 1
  true
}

@test "common-lib: _sdlc_dispatch: each of the seven command helpers runs executed with its contract status" {
  local base
  ch_repo
  cd "$CH_REPO"
  ch_profile "$CH_REPO"
  ch_hooks "$CH_REPO"
  ch_commit "$CH_REPO" 'chore: add profile and hooks'
  base="$(git rev-parse HEAD)"
  git config --local core.hooksPath .githooks
  mkdir -p target/rust-sdlc/logs
  printf 'done\nRUST_SDLC_EXIT=0\n' >target/rust-sdlc/logs/qa.log
  run "$LIB" derive_issue_number --branch feat/12-add-x
  [ "$status" -eq 0 ]
  [ "$output" = 12 ]
  SDLC_NOW_EPOCH=1794477300 run "$LIB" commit_msg_file 'feat(#12): add x'
  [ "$status" -eq 0 ]
  [ "$output" = target/rust-sdlc/tmp/commit-20261112T095500Z.txt ]
  run "$LIB" hooks_active
  [ "$status" -eq 0 ]
  [ "$output" = 'HOOKS: active' ]
  run "$LIB" wait_log target/rust-sdlc/logs/qa.log
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = 'RUST_SDLC_EXIT=0' ]
  run "$LIB" http_probe GET /health
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'HTTP_STATUS: 200' ]
  run "$LIB" protected_changes "$base"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$LIB" validate_context_name service ledger
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- derive_issue_number (AC-2.1) ----------------------------------------------

@test "common-lib: derive_issue_number: the first source in the order handle, title, branch, body wins" {
  run "$LIB" derive_issue_number --handle 7 --title 'feat(#12): add x' --branch feat/13-add-x --body 'Closes #14'
  [ "$status" -eq 0 ]
  [ "$output" = 7 ]
  run "$LIB" derive_issue_number --title 'feat(#12): add x' --branch feat/13-add-x --body 'Closes #14'
  [ "$output" = 12 ]
  run "$LIB" derive_issue_number --title 'Add x' --branch feat/13-add-x --body 'Closes #14'
  [ "$output" = 13 ]
  run "$LIB" derive_issue_number --title 'Add x' --branch main --body $'Summary\n\nCloses #14'
  [ "$output" = 14 ]
  # The flag order never changes the priority.
  run "$LIB" derive_issue_number --body 'Closes #14' --branch fix/13-y --title 'fix(#12): y' --handle 7
  [ "$output" = 7 ]
  run derive_issue_number --body 'Closes #14' --title 'docs(#12): add planning bundle 12-add-x'
  [ "$status" -eq 0 ]
  [ "$output" = 12 ]
}

@test "common-lib: derive_issue_number: ignores a PR number that differs from every source" {
  # PR 99 appears as GitHub's squash suffix and as a bare reference; the issue is 12.
  run "$LIB" derive_issue_number --title 'feat(#12): add x (#99)' --branch feat/12-add-x --body 'Implements #99. Closes #12'
  [ "$status" -eq 0 ]
  [ "$output" = 12 ]
  run "$LIB" derive_issue_number --title 'Merge pull request #99 from acme/feat' --branch acme/feat --body $'See #99\nCloses #12'
  [ "$output" = 12 ]
  run --separate-stderr "$LIB" derive_issue_number --title 'Add x (#99)' --branch 99-add-x --body 'Fixes #99'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  # There is no way to pass a PR number.
  run --separate-stderr "$LIB" derive_issue_number --pr 99 --branch feat/12-add-x
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "common-lib: derive_issue_number: no source returns 1 with no output; zero and leading zeros" {
  local args
  run --separate-stderr "$LIB" derive_issue_number
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  for args in "--handle ''" '--handle 0' '--handle 012' '--handle abc' "--title 'feat: x'" \
    "--title 'Feat(#3): x'" "--title 'feat (#3): x'" "--title 'feat(#): x'" "--title 'feat(#0): x'" \
    '--branch main' '--branch feat/12' '--branch 12-add-x' '--branch Feat/12-x' \
    "--body 'closes #5'" "--body 'XCloses #5'" "--body 'Closes 5'" "--body ''"; do
    # shellcheck disable=SC2086 # each case is a flag and a quoted value
    run --separate-stderr bash -c "\"\$0\" derive_issue_number $args" "$LIB"
    if [ "$status" -ne 1 ] || [ -n "$output" ] || [ -n "$stderr" ]; then
      printf '%s: status %s, output %s\n' "$args" "$status" "$output"
      return 1
    fi
  done
  run "$LIB" derive_issue_number --handle 0 --title 'feat(#0): x' --branch feat/0042-x
  [ "$status" -eq 0 ]
  [ "$output" = 42 ]
  run "$LIB" derive_issue_number --body $'line one\n(Closes #8)'
  [ "$output" = 8 ]
}

@test "common-lib: derive_issue_number: a missing value or an unknown argument exits 2" {
  run --separate-stderr "$LIB" derive_issue_number --title
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *'derive_issue_number: --title needs a value'* ]]
  run --separate-stderr "$LIB" derive_issue_number 12
  [ "$status" -eq 2 ]
  [[ "$stderr" == *'unknown argument: 12'* ]]
  run --separate-stderr "$LIB" derive_issue_number --issue 12
  [ "$status" -eq 2 ]
  # A value that starts with -- is still a value (a PR body may start so).
  run "$LIB" derive_issue_number --body '-- Closes #8'
  [ "$status" -eq 0 ]
  [ "$output" = 8 ]
}

# --- commit_msg_file (ADR-27) ------------------------------------------------------

@test "common-lib: commit_msg_file: writes the subject and a newline to target/rust-sdlc/tmp/commit-<utc_stamp>.txt and prints the path" {
  ch_repo
  cd "$CH_REPO"
  SDLC_NOW_EPOCH=1794477300 run --separate-stderr "$LIB" commit_msg_file 'feat(#12): add the invoice export'
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$output" = target/rust-sdlc/tmp/commit-20261112T095500Z.txt ]
  printf 'feat(#12): add the invoice export\n' | cmp - "$output"
  # No temporary file is left behind and the ignored target/ keeps git clean.
  [ "$(ls -A target/rust-sdlc/tmp)" = commit-20261112T095500Z.txt ]
  [ -z "$(git status --porcelain)" ]
  git commit -q --allow-empty -F "$output"
  [ "$(git log -1 --format=%B)" = 'feat(#12): add the invoice export' ]
  # A quote in the subject is kept byte for byte; the sourced form behaves alike.
  SDLC_NOW_EPOCH=1794477301 run commit_msg_file "fix(#3): handle the customer's name"
  [ "$status" -eq 0 ]
  [ "$output" = target/rust-sdlc/tmp/commit-20261112T095501Z.txt ]
  printf "fix(#3): handle the customer's name\n" | cmp - "$output"
}

@test "common-lib: commit_msg_file: an invalid subject exits 1 and writes nothing" {
  local s
  mkdir -p "$BATS_TEST_TMPDIR/svc"
  cd "$BATS_TEST_TMPDIR/svc"
  for s in 'feat: x' 'feat(#0): x' 'Feat(#1): x' 'feat (#1): x' 'review: gate iteration 2 remediation' \
    $'feat(#1): x\nsecond line' 'feat(#1): ' ''; do
    run --separate-stderr "$LIB" commit_msg_file "$s"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [[ "$stderr" == *'commit_msg_file: not a commit subject'* ]]
  done
  run --separate-stderr "$LIB" commit_msg_file
  [ "$status" -eq 1 ]
  run --separate-stderr "$LIB" commit_msg_file 'feat(#1): a' 'feat(#1): b'
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ ! -e target ]
}

@test "common-lib: commit_msg_file: refuses a linked target/rust-sdlc/tmp" {
  mkdir -p "$BATS_TEST_TMPDIR/svc/target/rust-sdlc" "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$BATS_TEST_TMPDIR/svc/target/rust-sdlc/tmp"
  cd "$BATS_TEST_TMPDIR/svc"
  run --separate-stderr "$LIB" commit_msg_file 'feat(#1): add x'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *'symbolic link'* ]]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/elsewhere")" ]
}

# --- hooks_active (Git rules) --------------------------------------------------------

@test "common-lib: hooks_active: active only for a local .githooks with the three executable hooks; never writes config" {
  local sum
  ch_repo
  ch_hooks "$CH_REPO"
  git -C "$CH_REPO" config --local core.hooksPath .githooks
  sum="$(cksum <"$CH_REPO/.git/config")"
  run --separate-stderr "$LIB" hooks_active "$CH_REPO"
  [ "$status" -eq 0 ]
  [ "$output" = 'HOOKS: active' ]
  [ -z "$stderr" ]
  # DIR defaults to the working directory, which may be below the root.
  cd "$CH_REPO/crates/service"
  run "$LIB" hooks_active
  [ "$status" -eq 0 ]
  [ "$output" = 'HOOKS: active' ]
  run hooks_active "$CH_REPO"
  [ "$output" = 'HOOKS: active' ]
  [ "$(cksum <"$CH_REPO/.git/config")" = "$sum" ]
}

@test "common-lib: hooks_active: unset without a local value, a global-only value included" {
  local sum gsum
  ch_repo
  ch_hooks "$CH_REPO"
  sum="$(cksum <"$CH_REPO/.git/config")"
  run "$LIB" hooks_active "$CH_REPO"
  [ "$status" -eq 1 ]
  [ "$output" = 'HOOKS: unset' ]
  git config --file "$BATS_TEST_TMPDIR/global.gitconfig" core.hooksPath .githooks
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
  gsum="$(cksum <"$GIT_CONFIG_GLOBAL")"
  # git itself sees the global value; the check reads only the local one.
  [ "$(git -C "$CH_REPO" config --get core.hooksPath)" = .githooks ]
  run "$LIB" hooks_active "$CH_REPO"
  [ "$status" -eq 1 ]
  [ "$output" = 'HOOKS: unset' ]
  [ "$(cksum <"$CH_REPO/.git/config")" = "$sum" ]
  [ "$(cksum <"$GIT_CONFIG_GLOBAL")" = "$gsum" ]
}

@test "common-lib: hooks_active: foreign for any other local value" {
  local value
  ch_repo
  ch_hooks "$CH_REPO"
  for value in .husky .githooks/ ./.githooks .GITHOOKS "$CH_REPO/.githooks"; do
    git -C "$CH_REPO" config --local core.hooksPath "$value"
    run "$LIB" hooks_active "$CH_REPO"
    [ "$status" -eq 1 ]
    [ "$output" = "HOOKS: foreign $value" ]
  done
  git -C "$CH_REPO" config --local core.hooksPath ''
  run "$LIB" hooks_active "$CH_REPO"
  [ "$status" -eq 1 ]
  [ "$output" = "HOOKS: foreign ''" ]
}

@test "common-lib: hooks_active: missing names the first absent or non-executable hook" {
  ch_repo
  ch_hooks "$CH_REPO"
  git -C "$CH_REPO" config --local core.hooksPath .githooks
  rm "$CH_REPO/.githooks/pre-push"
  run "$LIB" hooks_active "$CH_REPO"
  [ "$status" -eq 1 ]
  [ "$output" = 'HOOKS: missing .githooks/pre-push' ]
  chmod 644 "$CH_REPO/.githooks/pre-commit"
  run "$LIB" hooks_active "$CH_REPO"
  [ "$output" = 'HOOKS: missing .githooks/pre-commit' ]
  rm "$CH_REPO/.githooks/commit-msg"
  mkdir "$CH_REPO/.githooks/commit-msg"
  run "$LIB" hooks_active "$CH_REPO"
  [ "$output" = 'HOOKS: missing .githooks/commit-msg' ]
  rm -r "$CH_REPO/.githooks"
  run "$LIB" hooks_active "$CH_REPO"
  [ "$status" -eq 1 ]
  [ "$output" = 'HOOKS: missing .githooks/commit-msg' ]
}

@test "common-lib: hooks_active: a DIR that is not a directory or not a work tree exits 2" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run --separate-stderr "$LIB" hooks_active "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" run --separate-stderr "$LIB" hooks_active "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *'not inside a git work tree'* ]]
  run --separate-stderr "$LIB" hooks_active a b
  [ "$status" -eq 2 ]
}

# --- wait_log (ADR-13) ------------------------------------------------------------------

@test "common-lib: wait_log: a finished log prints its last 40 lines ending RUST_SDLC_EXIT=<n> and exits 0 without sleeping" {
  local i log=target/rust-sdlc/logs/review-20261112T101500Z.log
  ch_service
  ch_sleep_stub
  {
    for i in $(seq 1 50); do
      printf 'line %s\n' "$i"
    done
    printf 'RUST_SDLC_EXIT=0\n'
  } >"$log"
  run --separate-stderr "$LIB" wait_log "$log"
  [ "$status" -eq 0 ]
  {
    for i in $(seq 12 50); do
      printf 'line %s\n' "$i"
    done
    printf 'RUST_SDLC_EXIT=0\n'
  } >"$BATS_TEST_TMPDIR/want"
  printf '%s\n' "$output" | cmp - "$BATS_TEST_TMPDIR/want"
  [ ! -s "$BATS_TEST_TMPDIR/sleep.log" ]
}

@test "common-lib: wait_log: strips control characters, keeps a non-zero exit code and splits a marker after a partial line" {
  ch_service
  ch_sleep_stub
  printf 'ok \033[31mred\033[0m\r\ntab\there\nRUST_SDLC_EXIT=2\n' >target/rust-sdlc/logs/qa.log
  run "$LIB" wait_log target/rust-sdlc/logs/qa.log
  [ "$status" -eq 0 ]
  [ "$output" = $'ok [31mred[0m\ntabhere\nRUST_SDLC_EXIT=2' ]
  printf 'compiling\nno newlineRUST_SDLC_EXIT=101\n' >target/rust-sdlc/logs/plan.log
  run "$LIB" wait_log target/rust-sdlc/logs/plan.log
  [ "$status" -eq 0 ]
  [ "$output" = $'compiling\nno newline\nRUST_SDLC_EXIT=101' ]
  [ ! -s "$BATS_TEST_TMPDIR/sleep.log" ]
}

@test "common-lib: wait_log: a still-running log with MAX 30 checks again after 30 s and prints WAITING (exit 1)" {
  ch_service
  ch_sleep_stub
  printf 'Compiling invoice-domain\n' >target/rust-sdlc/logs/implement.log
  run --separate-stderr "$LIB" wait_log target/rust-sdlc/logs/implement.log 30
  [ "$status" -eq 1 ]
  [ "$output" = $'Compiling invoice-domain\nWAITING: target/rust-sdlc/logs/implement.log (30s)' ]
  [ "$(cat "$BATS_TEST_TMPDIR/sleep.log")" = 30 ]
}

@test "common-lib: wait_log: the default MAX is 110 s, checked every 30 s with a shortened last wait" {
  ch_service
  ch_sleep_stub
  printf 'running\n' >target/rust-sdlc/logs/qa.log
  run "$LIB" wait_log target/rust-sdlc/logs/qa.log
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = 'WAITING: target/rust-sdlc/logs/qa.log (110s)' ]
  [ "$(paste -sd ' ' "$BATS_TEST_TMPDIR/sleep.log")" = '30 30 30 20' ]
  : >"$BATS_TEST_TMPDIR/sleep.log"
  run "$LIB" wait_log target/rust-sdlc/logs/qa.log 45
  [ "${lines[1]}" = 'WAITING: target/rust-sdlc/logs/qa.log (45s)' ]
  [ "$(paste -sd ' ' "$BATS_TEST_TMPDIR/sleep.log")" = '30 15' ]
  : >"$BATS_TEST_TMPDIR/sleep.log"
  run "$LIB" wait_log target/rust-sdlc/logs/qa.log 060
  [ "${lines[1]}" = 'WAITING: target/rust-sdlc/logs/qa.log (60s)' ]
  [ "$(paste -sd ' ' "$BATS_TEST_TMPDIR/sleep.log")" = '30 30' ]
  : >"$BATS_TEST_TMPDIR/sleep.log"
  run "$LIB" wait_log target/rust-sdlc/logs/qa.log 540
  [ "${lines[1]}" = 'WAITING: target/rust-sdlc/logs/qa.log (540s)' ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/sleep.log")" -eq 18 ]
}

@test "common-lib: wait_log: a log that finishes during the wait exits 0 at the next check" {
  ch_service
  ch_sleep_stub "printf 'RUST_SDLC_EXIT=0\\n' >>'$CH_SVC/target/rust-sdlc/logs/implement.log'"
  printf 'running\n' >target/rust-sdlc/logs/implement.log
  run "$LIB" wait_log target/rust-sdlc/logs/implement.log
  [ "$status" -eq 0 ]
  [ "$output" = $'running\nRUST_SDLC_EXIT=0' ]
  [ "$(cat "$BATS_TEST_TMPDIR/sleep.log")" = 30 ]
}

@test "common-lib: wait_log: a log not written yet counts as running; new-service logs and absolute paths are accepted" {
  ch_service
  ch_sleep_stub
  run "$LIB" wait_log target/rust-sdlc/logs/absent.log 30
  [ "$status" -eq 1 ]
  [ "$output" = 'WAITING: target/rust-sdlc/logs/absent.log (30s)' ]
  printf 'bootstrap done\nRUST_SDLC_EXIT=0\n' >target/rust-sdlc/new-service/bootstrap.log
  run "$LIB" wait_log target/rust-sdlc/new-service/bootstrap.log
  [ "$status" -eq 0 ]
  [ "$output" = $'bootstrap done\nRUST_SDLC_EXIT=0' ]
  mkdir -p target/rust-sdlc/logs/nested
  printf 'RUST_SDLC_EXIT=0\n' >target/rust-sdlc/logs/nested/a.log
  run wait_log "$CH_SVC/target/rust-sdlc/logs/nested/a.log"
  [ "$status" -eq 0 ]
  [ "$output" = 'RUST_SDLC_EXIT=0' ]
}

@test "common-lib: wait_log: a log outside target/rust-sdlc/logs/ and target/rust-sdlc/new-service/ exits 2" {
  local log
  ch_service
  ch_sleep_stub
  printf 'secret\nRUST_SDLC_EXIT=0\n' >"$BATS_TEST_TMPDIR/outside.log"
  cp "$BATS_TEST_TMPDIR/outside.log" target/rust-sdlc/tmp/x.log
  cp "$BATS_TEST_TMPDIR/outside.log" target/rust-sdlc/x.log
  ln -s "$BATS_TEST_TMPDIR/outside.log" target/rust-sdlc/logs/link.log
  mkdir target/rust-sdlc/logs/dir.log
  for log in "$BATS_TEST_TMPDIR/outside.log" /etc/hostname target/rust-sdlc/tmp/x.log \
    target/rust-sdlc/x.log target/rust-sdlc/logs/../tmp/x.log target/rust-sdlc/logs/link.log \
    target/rust-sdlc/logs target/rust-sdlc/logs/ target/rust-sdlc/logs/dir.log logs/x.log ''; do
    run --separate-stderr "$LIB" wait_log "$log"
    if [ "$status" -ne 2 ] || [ -n "$output" ]; then
      printf '%s: status %s, output %s\n' "$log" "$status" "$output"
      return 1
    fi
  done
  # A linked logs directory leads outside as well.
  rm -r target/rust-sdlc/logs
  ln -s "$BATS_TEST_TMPDIR" target/rust-sdlc/logs
  run --separate-stderr "$LIB" wait_log target/rust-sdlc/logs/outside.log
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ ! -s "$BATS_TEST_TMPDIR/sleep.log" ]
}

@test "common-lib: wait_log: MAX outside 30 to 540, a missing LOG and extra arguments exit 2" {
  local max
  ch_service
  ch_sleep_stub
  printf 'RUST_SDLC_EXIT=0\n' >target/rust-sdlc/logs/qa.log
  for max in 29 541 0 abc '' -30 1e2 99999999999999999999; do
    run --separate-stderr "$LIB" wait_log target/rust-sdlc/logs/qa.log "$max"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
  done
  run --separate-stderr "$LIB" wait_log
  [ "$status" -eq 2 ]
  run --separate-stderr "$LIB" wait_log target/rust-sdlc/logs/qa.log 30 extra
  [ "$status" -eq 2 ]
  [ ! -s "$BATS_TEST_TMPDIR/sleep.log" ]
}

# --- http_probe -----------------------------------------------------------------------------

@test "common-lib: http_probe: GET goes to the profile's service.base_url with the exact curl argv" {
  ch_repo
  ch_profile "$CH_REPO"
  cd "$CH_REPO"
  run --separate-stderr "$LIB" http_probe GET /health
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  printf '%s\n' 'HTTP_STATUS: 200' 'HTTP/1.1 200 OK' 'content-type: application/json' \
    'content-length: 16' '' '{"status":"ok"}' >"$BATS_TEST_TMPDIR/want"
  printf '%s\n' "$output" | cmp - "$BATS_TEST_TMPDIR/want"
  [ "$(cat "$STUB_CURL_LOG")" = 'curl --noproxy * --proto =http --max-time 10 -sS -i -X GET -- http://127.0.0.1:8081/health' ]
  # Nothing is written: no temporary file, no file in the repository.
  mkdir -p "$BATS_TEST_TMPDIR/tmpdir"
  ch_capture_curl
  TMPDIR="$BATS_TEST_TMPDIR/tmpdir" run "$LIB" http_probe GET /health
  [ "$status" -eq 0 ]
  printf '%s\n' --noproxy '*' --proto =http --max-time 10 -sS -i -X GET -- \
    http://127.0.0.1:8081/health | cmp - "$CH_ARGV"
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/tmpdir")" ]
  [ "$(git status --porcelain)" = '?? .claude/rust-sdlc.yml' ]
  # The localhost form of service.base_url is accepted too.
  ch_profile "$CH_REPO" "'http://localhost:18081'"
  run "$LIB" http_probe OPTIONS /
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$CH_ARGV")" = http://localhost:18081/ ]
}

@test "common-lib: http_probe: headers, --body on stdin and --body-file each take one argv slot" {
  local m body i
  ch_repo
  ch_profile "$CH_REPO"
  cd "$CH_REPO"
  ch_capture_curl
  body='{"number":"INV-1","note":"--output /etc/passwd -K x http://evil.example/"}'
  run "$LIB" http_probe POST '/api/invoices?period=2026-11&fields=a,b' \
    --header 'Content-Type: application/json' --header 'X-Request-Id: qa-1 -o /tmp/x' --body "$body"
  [ "$status" -eq 0 ]
  [ "$output" = $'HTTP_STATUS: 204\nHTTP/1.1 204 No Content' ]
  printf '%s\n' --noproxy '*' --proto =http --max-time 10 -sS -i -X POST \
    -H 'Content-Type: application/json' -H 'X-Request-Id: qa-1 -o /tmp/x' --data-binary @- -- \
    'http://127.0.0.1:8081/api/invoices?period=2026-11&fields=a,b' | cmp - "$CH_ARGV"
  printf '%s' "$body" | cmp - "$CH_STDIN"
  mkdir -p target/rust-sdlc/tmp
  printf '{"a":1}' >target/rust-sdlc/tmp/body.json
  run "$LIB" http_probe PUT /api/x --body-file target/rust-sdlc/tmp/body.json
  [ "$status" -eq 0 ]
  printf '%s\n' --noproxy '*' --proto =http --max-time 10 -sS -i -X PUT \
    --data-binary @target/rust-sdlc/tmp/body.json -- http://127.0.0.1:8081/api/x | cmp - "$CH_ARGV"
  [ ! -s "$CH_STDIN" ]
  # A 16 KiB body and 10 headers are the limits, both accepted.
  run "$LIB" http_probe PATCH /api/x --body "$(head -c 16384 /dev/zero | tr '\0' a)"
  [ "$status" -eq 0 ]
  [ "$(wc -c <"$CH_STDIN")" -eq 16384 ]
  set --
  for i in 1 2 3 4 5 6 7 8 9 10; do
    set -- "$@" --header "X-H$i: $i"
  done
  run "$LIB" http_probe GET /health "$@"
  [ "$status" -eq 0 ]
  [ "$(grep -cx -- -H "$CH_ARGV")" -eq 10 ]
  for m in GET HEAD POST PUT PATCH DELETE OPTIONS; do
    run "$LIB" http_probe "$m" /
    [ "$status" -eq 0 ]
    [ "$(sed -n 10p "$CH_ARGV")" = "$m" ]
  done
}

@test "common-lib: http_probe: prints HTTP_STATUS, the headers and at most 64 KiB of body; 1xx skipped, any status exits 0" {
  local out="$BATS_TEST_TMPDIR/out" err="$BATS_TEST_TMPDIR/err" big head
  ch_repo
  ch_profile "$CH_REPO"
  cd "$CH_REPO"
  STUB_CURL_OUTPUT=$'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 422 Unprocessable Entity\r\ncontent-type: application/problem+json\r\nx-request-id: r-1\r\n\r\n{"title":"invalid"}' \
    run "$LIB" http_probe POST /api/invoices --body '{}'
  [ "$status" -eq 0 ]
  [ "$output" = $'HTTP_STATUS: 422\nHTTP/1.1 422 Unprocessable Entity\ncontent-type: application/problem+json\nx-request-id: r-1\n\n{"title":"invalid"}' ]
  STUB_CURL_OUTPUT=$'HTTP/1.1 500 Internal Server Error\nx-a: \033b\n\nboom\x01\ttab' run "$LIB" http_probe GET /boom
  [ "$status" -eq 0 ]
  [ "$output" = $'HTTP_STATUS: 500\nHTTP/1.1 500 Internal Server Error\nx-a: b\n\nboom\ttab' ]
  big="$(head -c 71680 /dev/zero | tr '\0' a)"
  STUB_CURL_OUTPUT=$'HTTP/1.1 200 OK\r\n\r\n'"$big" "$LIB" http_probe GET /big >"$out" 2>"$err"
  head=$'HTTP_STATUS: 200\nHTTP/1.1 200 OK\n\n'
  [ "$(wc -c <"$out")" -eq $((${#head} + 65536 + 1)) ]
  [ "$(head -c "${#head}" "$out")" = "${head%$'\n\n'}" ]
  grep -qF '[rust-sdlc][WARN] http_probe: body truncated to 65536 of 71681 bytes' "$err"
}

@test "common-lib: http_probe: a transport failure exits 1 with no output; HEAD keeps a complete header block" {
  ch_repo
  ch_profile "$CH_REPO"
  cd "$CH_REPO"
  STUB_CURL_EXIT=7 run --separate-stderr "$LIB" http_probe GET /health
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *'http_probe: transport failure for GET http://127.0.0.1:8081/health (curl exit 7): curl: (7)'* ]]
  STUB_CURL_OUTPUT='not http' run --separate-stderr "$LIB" http_probe GET /health
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  # curl -X HEAD keeps waiting for a body after the headers (exit 18 or 28):
  # a complete header block is the response for HEAD, never for another method.
  STUB_CURL_EXIT=28 STUB_CURL_OUTPUT=$'HTTP/1.1 200 OK\r\ncontent-length: 5\r\n\r\n' \
    run --separate-stderr "$LIB" http_probe HEAD /health
  [ "$status" -eq 0 ]
  [ "$output" = $'HTTP_STATUS: 200\nHTTP/1.1 200 OK\ncontent-length: 5' ]
  STUB_CURL_EXIT=18 STUB_CURL_OUTPUT=$'HTTP/1.1 200 OK\r\ncontent-length: 5\r\n\r\n' \
    run --separate-stderr "$LIB" http_probe HEAD /health
  [ "$status" -eq 0 ]
  STUB_CURL_EXIT=28 STUB_CURL_OUTPUT=$'HTTP/1.1 200 OK\r\ncontent-length: 5\r\n\r\n' \
    run --separate-stderr "$LIB" http_probe GET /health
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  STUB_CURL_EXIT=28 STUB_CURL_OUTPUT=$'HTTP/1.1 200 OK\r\ncontent-' \
    run --separate-stderr "$LIB" http_probe HEAD /health
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "common-lib: http_probe: a rejected METHOD, PATH, header, body or argument exits 2 and never calls curl" {
  local i m p
  ch_repo
  ch_profile "$CH_REPO"
  cd "$CH_REPO"
  mkdir -p target/rust-sdlc/tmp target/rust-sdlc/logs
  printf 'x' >target/rust-sdlc/logs/body.json
  printf 'x' >"$BATS_TEST_TMPDIR/secret"
  ln -s "$BATS_TEST_TMPDIR/secret" target/rust-sdlc/tmp/link.json
  mkdir target/rust-sdlc/tmp/dir.json
  for m in get TRACE CONNECT 'GET ' ''; do
    ch_rejects "$m" /health
  done
  for p in health '/a b' '/x#frag' '/x@evil.example' 'http://evil.example/' $'/x\n' $'/x\r' \
    $'/caf\xc3\xa9' '/[a]' '/{a,b}' '/x"' "/x'" '/x\y' ''; do
    ch_rejects GET "$p"
  done
  set --
  for i in 1 2 3 4 5 6 7 8 9 10 11; do
    set -- "$@" --header "X-H$i: $i"
  done
  ch_rejects GET /health "$@"
  ch_rejects GET /health --header $'X-A: b\r'
  ch_rejects GET /health --header $'X-A: b\r\nX-B: c'
  ch_rejects GET /health --header $'X-A: b\nHost: evil.example'
  ch_rejects GET /health --header NoColon
  ch_rejects GET /health --header ': no-name'
  ch_rejects GET /health --header 'X A: b'
  ch_rejects GET /health --header '@/etc/passwd'
  ch_rejects GET /health --header $'X-A: caf\xc3\xa9'
  ch_rejects GET /health --header $'X-A: tab\there'
  ch_rejects POST /health --body "$(head -c 16385 /dev/zero | tr '\0' a)"
  ch_rejects POST /health --body a --body b
  ch_rejects POST /health --body a --body-file target/rust-sdlc/tmp/dir.json
  ch_rejects POST /health --body-file /etc/hostname
  ch_rejects POST /health --body-file "$BATS_TEST_TMPDIR/secret"
  ch_rejects POST /health --body-file target/rust-sdlc/logs/body.json
  ch_rejects POST /health --body-file target/rust-sdlc/tmp/../logs/body.json
  ch_rejects POST /health --body-file target/rust-sdlc/tmp/link.json
  ch_rejects POST /health --body-file target/rust-sdlc/tmp/absent.json
  ch_rejects POST /health --body-file target/rust-sdlc/tmp/dir.json
  ch_rejects POST /health --body-file -
  ch_rejects GET /health http://evil.example/
  ch_rejects GET /health -- http://evil.example/
  ch_rejects GET /health --output /tmp/x
  ch_rejects GET /health -o /tmp/x
  ch_rejects GET /health -K /tmp/config
  ch_rejects GET /health --url http://evil.example/
  ch_rejects GET /health --header
  ch_rejects GET /health --body
  ch_rejects GET /health --body-file
  ch_rejects GET
  ch_rejects
  [ ! -s "$STUB_CURL_LOG" ]
}

@test "common-lib: http_probe: only a loopback service.base_url is accepted; the profile holds no other key" {
  local v
  ch_repo
  cd "$CH_REPO"
  run --separate-stderr "$LIB" http_probe GET /health
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *'no profile'* ]]
  for v in "'https://127.0.0.1:8081'" "'http://example.com:80'" "'http://127.0.0.1'" \
    "'http://127.0.0.1:8081/'" "'http://127.0.0.1:0'" "'http://127.0.0.1:65536'" \
    "'http://user@127.0.0.1:8081'" "'http://127.0.0.1:8081 http://evil.example'" "'http://127.0.0.2:8081'" \
    null "[a, b]" "{a: b}"; do
    ch_profile "$CH_REPO" "$v"
    run --separate-stderr "$LIB" http_probe GET /health
    if [ "$status" -ne 1 ] || [ -n "$output" ]; then
      printf '%s: status %s, output %s\n' "$v" "$status" "$output"
      return 1
    fi
  done
  printf 'schema_version: 1\nservice:\n  port: 8081\n' >"$CH_REPO/.claude/rust-sdlc.yml"
  run --separate-stderr "$LIB" http_probe GET /health
  [ "$status" -eq 1 ]
  [ ! -s "$STUB_CURL_LOG" ]
  # The minimal profile has none of the keys validate-profile.sh requires,
  # and http_probe never runs it.
  ch_profile "$CH_REPO" "'http://127.0.0.1:65535'"
  run "$LIB" http_probe GET /health
  [ "$status" -eq 0 ]
  grep -qF -- '-- http://127.0.0.1:65535/health' "$STUB_CURL_LOG"
  run bash -c 'source "$1"; declare -f http_probe _ch_http_exchange' _ "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" != *validate-profile* ]]
}

# --- protected_changes (ADR-25) ---------------------------------------------------------------

@test "common-lib: protected_changes: no change since the base exits 0 with no output" {
  local base
  ch_repo
  cd "$CH_REPO"
  base="$(git rev-parse HEAD)"
  run --separate-stderr "$LIB" protected_changes "$base"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  # Unprotected changes (committed, staged, untracked) and ignored files do not count.
  printf '\nmore\n' >>README.md
  ch_commit "$CH_REPO" 'docs: more'
  printf 'x\n' >crates/service/notes.txt
  printf 'y\n' >>docs/make-targets.md
  git add docs/make-targets.md
  mkdir -p target/rust-sdlc/tmp
  printf 'feat(#1): x\n' >target/rust-sdlc/tmp/commit-1.txt
  run --separate-stderr "$LIB" protected_changes "$base"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run protected_changes HEAD
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: protected_changes: a protected file changed in a commit, in the working tree or untracked below a protected directory" {
  local base sha
  ch_repo
  cd "$CH_REPO"
  base="$(git rev-parse HEAD)"
  printf '# relaxed\n' >>clippy.toml
  ch_commit "$CH_REPO" 'chore: relax clippy'
  sha="$(git log -1 --format=%h --abbrev=7)"
  printf 'docs\n' >>README.md
  ch_commit "$CH_REPO" 'docs: later commit'
  printf '# x\n' >>deny.toml
  mkdir -p xtask/tests
  printf 'fn main() {}\n' >xtask/tests/arch_fixture.rs
  run --separate-stderr "$LIB" protected_changes "$base"
  [ "$status" -eq 1 ]
  [ -z "$stderr" ]
  printf '%s\n' "PROTECTED: clippy.toml ($sha)" 'PROTECTED: deny.toml (working tree)' \
    'PROTECTED: xtask/tests/arch_fixture.rs (working tree)' >"$BATS_TEST_TMPDIR/want"
  printf '%s\n' "$output" | cmp - "$BATS_TEST_TMPDIR/want"
  # A deletion, a rename (both paths) and a change that is only staged count too.
  git checkout -q -- deny.toml
  rm xtask/tests/arch_fixture.rs
  git mv architecture.toml architecture.old.toml
  git rm -q -- rust-toolchain.toml
  run "$LIB" protected_changes "$base"
  [ "$status" -eq 1 ]
  printf '%s\n' 'PROTECTED: architecture.toml (working tree)' "PROTECTED: clippy.toml ($sha)" \
    'PROTECTED: rust-toolchain.toml (working tree)' >"$BATS_TEST_TMPDIR/want"
  printf '%s\n' "$output" | cmp - "$BATS_TEST_TMPDIR/want"
  # A committed change that the working tree reverts is no change.
  git reset -q --hard
  git show "$base:clippy.toml" >clippy.toml
  run "$LIB" protected_changes "$base"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: protected_changes: the list is read at the base, so a dropped entry is still reported" {
  local base sha
  ch_repo
  cd "$CH_REPO"
  base="$(git rev-parse HEAD)"
  grep -vxF '    "clippy.toml",' protected-config.toml >"$BATS_TEST_TMPDIR/list"
  cat "$BATS_TEST_TMPDIR/list" >protected-config.toml
  printf '# relaxed\n' >>clippy.toml
  ch_commit "$CH_REPO" 'chore: unprotect clippy'
  sha="$(git log -1 --format=%h --abbrev=7)"
  run "$LIB" protected_changes "$base"
  [ "$status" -eq 1 ]
  [ "$output" = "PROTECTED: clippy.toml ($sha)"$'\n'"PROTECTED: protected-config.toml ($sha)" ]
}

@test "common-lib: protected_changes: a profile present at the base that differs now prints PROFILE_CHANGED" {
  local base
  ch_repo
  ch_profile "$CH_REPO"
  ch_commit "$CH_REPO" 'chore: add profile'
  cd "$CH_REPO"
  base="$(git rev-parse HEAD)"
  printf 'make:\n  complexity: format\n' >>.claude/rust-sdlc.yml
  run --separate-stderr "$LIB" protected_changes "$base"
  [ "$status" -eq 1 ]
  [ "$output" = 'PROFILE_CHANGED: .claude/rust-sdlc.yml' ]
  ch_commit "$CH_REPO" 'chore: remap a gate key'
  run "$LIB" protected_changes "$base"
  [ "$status" -eq 1 ]
  [ "$output" = 'PROFILE_CHANGED: .claude/rust-sdlc.yml' ]
  git rm -q .claude/rust-sdlc.yml
  run "$LIB" protected_changes "$base"
  [ "$status" -eq 1 ]
  [ "$output" = 'PROFILE_CHANGED: .claude/rust-sdlc.yml' ]
  ch_profile "$CH_REPO"
  run "$LIB" protected_changes "$base"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: protected_changes: a profile absent at the base is exempt" {
  local base
  ch_repo
  cd "$CH_REPO"
  base="$(git rev-parse HEAD)"
  ch_profile "$CH_REPO"
  run --separate-stderr "$LIB" protected_changes "$base"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ch_commit "$CH_REPO" 'chore(#1): add rust-backend-sdlc profile and governance'
  run --separate-stderr "$LIB" protected_changes "$base"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: protected_changes: without protected-config.toml prints INFO and checks the profile only" {
  local base
  ch_repo
  cd "$CH_REPO"
  git rm -q protected-config.toml
  ch_profile "$CH_REPO"
  ch_commit "$CH_REPO" 'chore: drop the protected list'
  base="$(git rev-parse HEAD)"
  printf '# relaxed\n' >>clippy.toml
  run --separate-stderr "$LIB" protected_changes "$base"
  [ "$status" -eq 0 ]
  [ "$output" = 'INFO: no protected-config.toml' ]
  printf 'review:\n  reviewers: []\n' >>.claude/rust-sdlc.yml
  run --separate-stderr "$LIB" protected_changes "$base"
  [ "$status" -eq 1 ]
  [ "$output" = $'INFO: no protected-config.toml\nPROFILE_CHANGED: .claude/rust-sdlc.yml' ]
}

@test "common-lib: protected_changes: a missing, extra, option-like or unknown BASE_SHA exits 2" {
  local arg
  ch_repo
  cd "$CH_REPO"
  run --separate-stderr "$LIB" protected_changes
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr "$LIB" protected_changes HEAD HEAD
  [ "$status" -eq 2 ]
  for arg in "--output=$BATS_TEST_TMPDIR/diff.out" -p '' not-a-ref \
    0000000000000000000000000000000000000000 "$(git rev-parse 'HEAD^{tree}')"; do
    run --separate-stderr "$LIB" protected_changes "$arg"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
  done
  [ ! -e "$BATS_TEST_TMPDIR/diff.out" ]
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  cd "$BATS_TEST_TMPDIR/plain"
  GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" run --separate-stderr "$LIB" protected_changes HEAD
  [ "$status" -eq 2 ]
  [[ "$stderr" == *'not inside a git work tree'* ]]
}

# --- validate_context_name (FR-14, AC-14.1) ---------------------------------------------------

@test "common-lib: validate_context_name: refuses every name of the AC-14.1 list with exactly one REFUSED line" {
  local entry group context rule
  ch_repo
  for entry in 'Billing ledger name-format' 'billing Ledger name-format' '1billing ledger name-format' \
    'billing 2ledger name-format' 'billing- ledger name-format' 'billing ledger- name-format' \
    'bill--ing ledger name-format' 'billing led--ger name-format' 'billing shared reserved-context' \
    'billing service reserved-context' 'billing xtask reserved-context' \
    'billing test-support reserved-context' 'billing e2e-tests reserved-context' \
    'billing invoice context-exists' 'sales invoice context-exists' 'sales internal context-exists' \
    'billing health-check context-exists' 'sales billing context-exists'; do
    read -r group context rule <<<"$entry"
    run --separate-stderr "$LIB" validate_context_name "$group" "$context" "$CH_REPO"
    if [ "$status" -ne 1 ] || [ "${#lines[@]}" -ne 1 ] || [[ "${lines[0]}" != "REFUSED: $rule "* ]]; then
      printf '%s/%s: status %s, output %s\n' "$group" "$context" "$status" "$output"
      return 1
    fi
  done
  run "$LIB" validate_context_name Billing ledger "$CH_REPO"
  [ "$output" = "REFUSED: name-format group 'Billing' does not match ^[a-z][a-z0-9]*(-[a-z0-9]+)*\$" ]
  run "$LIB" validate_context_name billing led--ger "$CH_REPO"
  [ "$output" = "REFUSED: name-format context 'led--ger' does not match ^[a-z][a-z0-9]*(-[a-z0-9]+)*\$" ]
  run "$LIB" validate_context_name billing shared "$CH_REPO"
  [ "$output" = "REFUSED: reserved-context 'shared' is reserved (shared service xtask test-support e2e-tests)" ]
  run "$LIB" validate_context_name sales invoice "$CH_REPO"
  [ "$output" = "REFUSED: context-exists 'invoice' already exists at crates/billing/invoice" ]
  run "$LIB" validate_context_name sales internal "$CH_REPO"
  [ "$output" = "REFUSED: context-exists 'internal' already exists at crates/internal" ]
  run "$LIB" validate_context_name billing health-check "$CH_REPO"
  [ "$output" = "REFUSED: context-exists 'health-check' already exists at crates/internal/health-check" ]
}

@test "common-lib: validate_context_name: accepts valid names, including the reserved word service as a group" {
  local pair
  ch_repo
  for pair in service/ledger sales/ledger billing/invoice-export payments/refund-request a1/b2 \
    shared/ledger-v2 xtask/audit; do
    run --separate-stderr "$LIB" validate_context_name "${pair%/*}" "${pair#*/}" "$CH_REPO"
    if [ "$status" -ne 0 ] || [ -n "$output" ] || [ -n "$stderr" ]; then
      printf '%s: status %s, output %s %s\n' "$pair" "$status" "$output" "$stderr"
      return 1
    fi
  done
  cd "$CH_REPO"
  run validate_context_name service ledger
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: validate_context_name: a member package <c>-domain at a non-standard path and a member ending <c>/<layer> are refused" {
  ch_repo
  ch_add_member "$CH_REPO" libs/payments-core payments-domain
  run --separate-stderr "$LIB" validate_context_name sales payments "$CH_REPO"
  [ "$status" -eq 1 ]
  [ "$output" = "REFUSED: member-exists 'payments' is already a workspace member: libs/payments-core (package payments-domain)" ]
  ch_add_member "$CH_REPO" modules/ledger/infrastructure ledger-store
  run --separate-stderr "$LIB" validate_context_name sales ledger "$CH_REPO"
  [ "$status" -eq 1 ]
  [ "$output" = "REFUSED: member-exists 'ledger' is already a workspace member: modules/ledger/infrastructure" ]
  # Only whole path components and exact package names match.
  ch_add_member "$CH_REPO" modules/myrefund/domain refund-domains
  run --separate-stderr "$LIB" validate_context_name sales refund "$CH_REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: validate_context_name: reads the live tree, never a stale profile" {
  ch_repo
  ch_profile "$CH_REPO"
  printf '%s\n' 'architecture:' '  bounded_contexts:' '    - billing/ghost' >>"$CH_REPO/.claude/rust-sdlc.yml"
  # A context added after the profile was generated, and one the profile never listed.
  ch_add_member "$CH_REPO" crates/sales/ledger/domain ledger-domain
  run --separate-stderr "$LIB" validate_context_name sales ledger "$CH_REPO"
  [ "$status" -eq 1 ]
  [ "$output" = "REFUSED: context-exists 'ledger' already exists at crates/sales/ledger" ]
  run --separate-stderr "$LIB" validate_context_name billing invoice "$CH_REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == "REFUSED: context-exists 'invoice' "* ]]
  # A context only the stale profile names is free.
  run --separate-stderr "$LIB" validate_context_name billing ghost "$CH_REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common-lib: validate_context_name: usage errors and a ROOT without Cargo.toml exit 2" {
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  run --separate-stderr "$LIB" validate_context_name billing
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr "$LIB" validate_context_name a b c d
  [ "$status" -eq 2 ]
  run --separate-stderr "$LIB" validate_context_name sales ledger "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *'no readable Cargo.toml'* ]]
  # The name rules come first and need no tree.
  run --separate-stderr "$LIB" validate_context_name Sales ledger "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 1 ]
  [[ "$output" == 'REFUSED: name-format '* ]]
}
