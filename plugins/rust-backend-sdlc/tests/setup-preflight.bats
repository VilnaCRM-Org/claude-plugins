#!/usr/bin/env bats
# setup-preflight.bats — cases of scripts/setup-preflight.sh (FR-10, AC-10.1,
# AC-10.2, AC-10.3, AC-4.4, NFR-16; degrade rows D5, D6, D15, D16, D20).
#
# Hermetic: the stubs of tests/fixtures/bin come first on PATH (common_setup),
# the repository under test is materialized at $BATS_TEST_TMPDIR/billing-service,
# and a tool is made genuinely absent with sandbox_path (a PATH holding only the
# named tools). Version stubs for git, python3, node and npm are small scripts
# written under $BATS_TEST_TMPDIR; the git and python3 ones answer --version and
# hand every other call to the real tool. The kislyuk yq stub of
# tests/fixtures/bin-kislyuk goes first on PATH only in the cases that need it.
#
# shellcheck disable=SC2016,SC2030,SC2031 # single-quoted awk programs; bats cases run in subshells

bats_require_minimum_version 1.5.0

CHECK_IDS='git-repo gh gh-auth claude claude-restricted bmalph bmalph-doctor python3 yaml-backend json-backend make bash git template-markers tracked-tree docker cargo'

setup() {
  load lib/helpers
  common_setup
  SCRIPT="$PLUGIN_ROOT/scripts/setup-preflight.sh"
  KISLYUK_BIN="$PLUGIN_ROOT/tests/fixtures/bin-kislyuk"
  REPO="$BATS_TEST_TMPDIR/billing-service"
  rr_materialize "$REPO"
  cd "$REPO" || return 1
}

# pf_fake DIR NAME BODY — an executable DIR/NAME that runs BODY under bash.
pf_fake() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\n%s\n' "$3" >"$1/$2"
  chmod 755 "$1/$2"
}

# pf_wrap DIR TOOL LINE — DIR/TOOL prints LINE for --version and runs the real
# TOOL (resolved on the current PATH) for every other call.
pf_wrap() {
  local real
  real="$(type -P "$2")" || return 1
  pf_fake "$1" "$2" "if [[ \"\${1-}\" == --version ]]; then printf '%s\\n' '$3'; exit 0; fi
exec '$real' \"\$@\""
}

# pf_python DIR VERSION — DIR/python3 reporting `Python VERSION`; an import of
# tomllib fails as in a python3 older than 3.11, every other call runs the
# real python3.
pf_python() {
  local real
  real="$(type -P python3)" || return 1
  pf_fake "$1" python3 "if [[ \"\${1-}\" == --version ]]; then printf 'Python %s\\n' '$2'; exit 0; fi
if [[ \"\$*\" == *tomllib* ]]; then printf \"ModuleNotFoundError: No module named 'tomllib'\\n\" >&2; exit 1; fi
exec '$real' \"\$@\""
}

# pf_js DIR NODE_VERSION [npm] — DIR/node printing vNODE_VERSION and, when the
# third argument is npm, DIR/npm printing 10.2.4.
pf_js() {
  pf_fake "$1" node "printf 'v%s\\n' '$2'"
  if [[ "${3-}" == npm ]]; then
    pf_fake "$1" npm "printf '10.2.4\\n'"
  fi
}

# pf_sandbox TOOL... — sandbox_path with the tools the script itself needs
# (bash, dirname, git, grep; readlink for the bmalph stub) plus TOOL....
pf_sandbox() {
  sandbox_path bash dirname git grep readlink "$@"
}

# pf_floors — every versioned tool exactly at its floor: gh 2.0, claude
# 2.1.248, bmalph 2.11.0, GNU Make 4.0, bash 4.4 (test hook), git 2.30 and
# python3 3.11 (wrappers first on PATH).
pf_floors() {
  local dir="$BATS_TEST_TMPDIR/floors"
  pf_wrap "$dir" git 'git version 2.30.0'
  pf_wrap "$dir" python3 'Python 3.11.0'
  PATH="$dir:$PATH"
  export PATH STUB_GH_VERSION=2.0.0 STUB_CLAUDE_VERSION=2.1.248 STUB_BMALPH_VERSION=2.11.0
  export STUB_MAKE_VERSION_LINE='GNU Make 4.0' RUST_SDLC_BASH_VERSION=4.4
}

# pf_shadow NAME — a PYTHONPATH directory whose NAME.py raises ImportError,
# so `import NAME` fails as if the module were not installed.
pf_shadow() {
  local dir="$BATS_TEST_TMPDIR/shadow-$1"
  mkdir -p "$dir"
  printf 'raise ImportError("No module named %s")\n' "$1" >"$dir/$1.py"
  printf '%s\n' "$dir"
}

# pf_ids — the check ids of the stdout lines of the last run, in order.
pf_ids() {
  local line out="" re='^(PASS|WARN|FAIL|INFO): ([a-z0-9-]+): '
  for line in "${lines[@]}"; do
    if [[ "$line" =~ $re ]]; then
      out+="${out:+ }${BASH_REMATCH[2]}"
    fi
  done
  printf '%s\n' "$out"
}

# pf_line ID — the stdout line of check ID in the last run (status 1 if none).
pf_line() {
  local line
  for line in "${lines[@]}"; do
    case "$line" in
      PASS:\ "$1":\ * | WARN:\ "$1":\ * | FAIL:\ "$1":\ * | INFO:\ "$1":\ *)
        printf '%s\n' "$line"
        return 0
        ;;
    esac
  done
  return 1
}

# pf_edit FILE AWK_PROGRAM — rewrite FILE through awk (temporary file + mv).
pf_edit() {
  awk "$2" "$1" >"$1.pf-edit"
  mv "$1.pf-edit" "$1"
}

# pf_snapshot DIR — every path under DIR (.git included) and every file's
# checksum, so two snapshots differ when anything was written.
pf_snapshot() {
  (cd "$1" && find . | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort)
}

# --- usage -------------------------------------------------------------------

@test "setup-preflight: --help prints the header and exits 0 in any position" {
  run --separate-stderr "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == 'setup-preflight.sh — '* ]]
  [[ "$output" == *'Usage: setup-preflight.sh [--report]'* ]]
  [[ "$output" == *'Exit: 0 no check FAILed; 1 '* ]]
  [[ "$output" != *'#'* ]]
  help="$output"
  run --separate-stderr "$SCRIPT" --report --help
  [ "$status" -eq 0 ]
  [ "$output" = "$help" ]
  run --separate-stderr "$SCRIPT" --bogus --help
  [ "$status" -eq 0 ]
  [ "$output" = "$help" ]
}

@test "setup-preflight: an unknown argument is a usage error (exit 2) and runs no check" {
  run --separate-stderr "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *'[rust-sdlc][ERROR] unknown argument: --bogus (usage: setup-preflight.sh [--report])'* ]]
  run --separate-stderr "$SCRIPT" --report extra
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *'unknown argument: extra'* ]]
  [ ! -s "$STUB_GH_LOG" ]
}

# --- order, format and modes -----------------------------------------------------------

@test "setup-preflight: --report at the floors prints every check in contract order, then the summary, exit 0" {
  pf_floors
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_ids)" = "$CHECK_IDS" ]
  [ "${#lines[@]}" -eq 18 ]
  [ "${lines[17]}" = 'SUMMARY: pass=13 warn=0 fail=0 info=4' ]
  [ "$(pf_line gh)" = 'PASS: gh: gh 2.0.0 (floor 2.0)' ]
  [ "$(pf_line claude)" = 'PASS: claude: claude 2.1.248 (floor 2.1.248)' ]
  [ "$(pf_line claude-restricted)" = 'PASS: claude-restricted: claude --help lists --restricted' ]
  [ "$(pf_line bmalph)" = 'PASS: bmalph: bmalph 2.11.0 (floor 2.11.0)' ]
  [ "$(pf_line python3)" = 'PASS: python3: python3 3.11.0 with tomllib (floor 3.11)' ]
  [ "$(pf_line make)" = 'PASS: make: GNU Make 4.0 (floor 4.0)' ]
  [ "$(pf_line bash)" = 'PASS: bash: bash 4.4 (floor 4.4)' ]
  [ "$(pf_line git)" = 'PASS: git: git 2.30.0 (floor 2.30)' ]
  [ "$(pf_line template-markers)" = 'PASS: template-markers: all 8 template markers present (template-derived)' ]
  [ "$(pf_line tracked-tree)" = 'INFO: tracked-tree: clean (no tracked changes)' ]
  [[ "$(pf_line git-repo)" == 'PASS: git-repo: inside the work tree '*billing-service ]]
  [[ "$(pf_line yaml-backend)" == 'PASS: yaml-backend: '* ]]
  [[ "$(pf_line json-backend)" == 'PASS: json-backend: '* ]]
}

@test "setup-preflight: stdout holds only check lines and the summary; logs go to stderr" {
  pf_floors
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  for line in "${lines[@]}"; do
    [[ "$line" =~ ^(PASS|WARN|FAIL|INFO):\ [a-z0-9-]+:\ [^[:space:]].*$ || "$line" =~ ^SUMMARY:\ pass=[0-9]+\ warn=[0-9]+\ fail=[0-9]+\ info=[0-9]+$ ]]
  done
  [ "${#stderr_lines[@]}" -ge 1 ]
  for line in "${stderr_lines[@]}"; do
    [[ "$line" == '[rust-sdlc]['* ]]
  done
}

@test "setup-preflight: the default mode without a FAIL runs every check and exits 0" {
  pf_floors
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pf_ids)" = "$CHECK_IDS" ]
  [ "${lines[17]}" = 'SUMMARY: pass=13 warn=0 fail=0 info=4' ]
}

@test "setup-preflight: gh 1.9 FAILs with its remediation and the default mode stops after the first FAIL" {
  STUB_GH_VERSION=1.9 run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == 'PASS: git-repo: '* ]]
  [ "${lines[1]}" = 'FAIL: gh: gh 1.9 is below 2.0 — remediation: upgrade GitHub CLI to 2.0 or newer' ]
  [ "${lines[2]}" = 'SUMMARY: pass=1 warn=0 fail=1 info=0' ]
  [[ "$stderr" == *'stopped at the first FAIL (gh); run with --report'* ]]
  [ "$(cat "$STUB_GH_LOG")" = 'gh --version' ]
  [ ! -s "$STUB_CLAUDE_LOG" ]
}

@test "setup-preflight: --report runs every check after a FAIL and exits 1" {
  STUB_GH_VERSION=1.9 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = "$CHECK_IDS" ]
  [ "$(pf_line gh)" = 'FAIL: gh: gh 1.9 is below 2.0 — remediation: upgrade GitHub CLI to 2.0 or newer' ]
  [[ "${lines[17]}" == SUMMARY:*' fail=1 '* ]]
  [[ "$stderr" == *'preflight: 1 check(s) FAILed'* ]]
}

# --- gh, claude ------------------------------------------------------------------------

@test "setup-preflight: gh absent FAILs gh and gh-auth with install remediations" {
  sb="$(pf_sandbox python3 claude bmalph make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line gh)" = 'FAIL: gh: gh not found on PATH — remediation: install GitHub CLI 2.0 or newer' ]
  [ "$(pf_line gh-auth)" = 'FAIL: gh-auth: gh not found on PATH — remediation: install GitHub CLI 2.0 or newer, then run gh auth login' ]
}

@test "setup-preflight: an unauthenticated gh FAILs gh-auth with gh auth login" {
  STUB_GH_AUTH_EXIT=1 run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = 'git-repo gh gh-auth' ]
  [ "${lines[2]}" = 'FAIL: gh-auth: gh auth status reports no authenticated account — remediation: run gh auth login' ]
  [ "${lines[3]}" = 'SUMMARY: pass=2 warn=0 fail=1 info=0' ]
}

@test "setup-preflight: claude below 2.1.248 FAILs with the upgrade remediation" {
  STUB_CLAUDE_VERSION=2.1.247 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line claude)" = 'FAIL: claude: claude 2.1.247 is below 2.1.248 — remediation: upgrade Claude Code to 2.1.248 or newer' ]
  [ "$(pf_line claude-restricted)" = 'PASS: claude-restricted: claude --help lists --restricted' ]
}

@test "setup-preflight: claude without --restricted FAILs claude-restricted with the upgrade remediation (D15)" {
  STUB_CLAUDE_RESTRICTED=0 run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = 'git-repo gh gh-auth claude claude-restricted' ]
  [[ "$(pf_line claude)" == 'PASS: claude: '* ]]
  [ "${lines[4]}" = 'FAIL: claude-restricted: claude --help does not list --restricted — remediation: upgrade Claude Code to 2.1.248 or newer' ]
  [ "${lines[5]}" = 'SUMMARY: pass=4 warn=0 fail=1 info=0' ]
}

@test "setup-preflight: claude absent FAILs claude and claude-restricted with the install remediation" {
  sb="$(pf_sandbox python3 gh bmalph make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line claude)" = 'FAIL: claude: claude not found on PATH — remediation: install Claude Code 2.1.248 or newer' ]
  [ "$(pf_line claude-restricted)" = 'FAIL: claude-restricted: claude not found on PATH — remediation: install Claude Code 2.1.248 or newer' ]
}

# --- bmalph ------------------------------------------------------------------------------

@test "setup-preflight: bmalph 2.10.0 FAILs with the upgrade remediation and stops before bmalph-doctor" {
  STUB_BMALPH_VERSION=2.10.0 run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = 'git-repo gh gh-auth claude claude-restricted bmalph' ]
  [ "${lines[5]}" = 'FAIL: bmalph: bmalph 2.10.0 is below 2.11.0 — remediation: upgrade bmalph to 2.11.0 or newer' ]
}

@test "setup-preflight: bmalph absent with a bmalph-setup target, node 20 and npm WARNs and exits 0 (D6)" {
  pf_js "$BATS_TEST_TMPDIR/js" 20.0.0 npm
  sb="$(PATH="$BATS_TEST_TMPDIR/js:$PATH" pf_sandbox python3 gh claude make node npm)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line bmalph)" = 'WARN: bmalph: bmalph not found on PATH; will be installed by make bmalph-setup (node 20.0.0, npm 10.2.4)' ]
  [ "$(pf_line bmalph-doctor)" = 'INFO: bmalph-doctor: no _bmad/ yet: bmalph doctor deferred until make bmalph-setup' ]
  [[ "${lines[17]}" == SUMMARY:*' warn=1 fail=0 '* ]]
  run --separate-stderr env PATH="$sb" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pf_ids)" = "$CHECK_IDS" ]
}

@test "setup-preflight: a bmalph-setup target in make/*.mk also makes bmalph installable" {
  pf_edit Makefile '!/^bmalph-setup:/'
  printf 'bmalph-setup: ## Install and initialise bmalph in one step\n\t@true\n' >>make/service.mk
  pf_js "$BATS_TEST_TMPDIR/js" 22.11.0 npm
  sb="$(PATH="$BATS_TEST_TMPDIR/js:$PATH" pf_sandbox python3 gh claude make node npm)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [[ "$(pf_line bmalph)" == 'WARN: bmalph: bmalph not found on PATH; will be installed by make bmalph-setup '* ]]
}

@test "setup-preflight: bmalph absent without a bmalph-setup target FAILs with the install remediation" {
  pf_edit Makefile '!/^bmalph-setup:/'
  pf_js "$BATS_TEST_TMPDIR/js" 20.0.0 npm
  sb="$(PATH="$BATS_TEST_TMPDIR/js:$PATH" pf_sandbox python3 gh claude make node npm)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line bmalph)" = 'FAIL: bmalph: bmalph not found on PATH and not installable by make bmalph-setup: no bmalph-setup Makefile target — remediation: install bmalph 2.11.0 or newer, or add a bmalph-setup Makefile target and install node 20 or newer with npm' ]
}

@test "setup-preflight: bmalph absent with node 18, without npm or without node FAILs naming what is missing" {
  pf_js "$BATS_TEST_TMPDIR/js18" 18.19.0 npm
  sb="$(PATH="$BATS_TEST_TMPDIR/js18:$PATH" pf_sandbox python3 gh claude make node npm)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [[ "$(pf_line bmalph)" == 'FAIL: bmalph: bmalph not found on PATH and not installable by make bmalph-setup: node 18.19.0 is below 20 — remediation: install bmalph 2.11.0 or newer'* ]]
  pf_js "$BATS_TEST_TMPDIR/js20" 20.1.0
  sb="$(PATH="$BATS_TEST_TMPDIR/js20:$PATH" pf_sandbox python3 gh claude make node)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [[ "$(pf_line bmalph)" == 'FAIL: bmalph: bmalph not found on PATH and not installable by make bmalph-setup: npm not found — remediation: '* ]]
  sb="$(pf_sandbox python3 gh claude make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "${lines[5]}" == 'FAIL: bmalph: bmalph not found on PATH and not installable by make bmalph-setup: node not found, npm not found — remediation: '* ]]
}

@test "setup-preflight: with _bmad/ present bmalph doctor runs in the repository root and PASSes" {
  mkdir -p _bmad crates
  cd crates
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line bmalph-doctor)" = 'PASS: bmalph-doctor: bmalph doctor passed' ]
  grep -qx 'bmalph doctor' "$STUB_BMALPH_LOG"
}

@test "setup-preflight: a failing bmalph doctor FAILs with its first output line and stops before python3" {
  mkdir -p _bmad
  STUB_BMALPH_DOCTOR_EXIT=3 STUB_BMALPH_OUTPUT='config.json is missing' run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = 'git-repo gh gh-auth claude claude-restricted bmalph bmalph-doctor' ]
  [ "${lines[6]}" = 'FAIL: bmalph-doctor: bmalph doctor exited 3: config.json is missing — remediation: run bmalph doctor in the repository root and fix what it reports' ]
}

@test "setup-preflight: without _bmad/ bmalph-doctor is INFO deferred and bmalph doctor never runs" {
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line bmalph-doctor)" = 'INFO: bmalph-doctor: no _bmad/ yet: bmalph doctor deferred until make bmalph-setup' ]
  run ! grep -q doctor "$STUB_BMALPH_LOG"
}

@test "setup-preflight: _bmad/ present while bmalph is absent FAILs bmalph-doctor" {
  mkdir -p _bmad
  pf_js "$BATS_TEST_TMPDIR/js" 20.0.0 npm
  sb="$(PATH="$BATS_TEST_TMPDIR/js:$PATH" pf_sandbox python3 gh claude make node npm)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line bmalph-doctor)" = 'FAIL: bmalph-doctor: _bmad/ exists but bmalph is not on PATH, so bmalph doctor cannot run — remediation: install bmalph 2.11.0 or newer, then run bmalph doctor' ]
}

# --- python3, YAML and JSON backends ----------------------------------------------------

@test "setup-preflight: python 3.10 through sandbox_path FAILs with the install remediation" {
  pf_python "$BATS_TEST_TMPDIR/py310" 3.10.12
  sb="$(PATH="$BATS_TEST_TMPDIR/py310:$PATH" pf_sandbox python3 gh claude bmalph make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = 'git-repo gh gh-auth claude claude-restricted bmalph bmalph-doctor python3' ]
  [ "${lines[7]}" = 'FAIL: python3: python3 3.10.12 is below 3.11 — remediation: install Python 3.11 or newer' ]
}

@test "setup-preflight: a python3 without tomllib or no python3 at all FAILs python3" {
  pf_python "$BATS_TEST_TMPDIR/py311" 3.11.4
  sb="$(PATH="$BATS_TEST_TMPDIR/py311:$PATH" pf_sandbox python3 gh claude bmalph make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line python3)" = 'FAIL: python3: python3 3.11.4 cannot import tomllib — remediation: install Python 3.11 or newer' ]
  sb="$(pf_sandbox gh claude bmalph make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line python3)" = 'FAIL: python3: python3 not found on PATH — remediation: install Python 3.11 or newer' ]
}

@test "setup-preflight: the kislyuk yq first on PATH without PyYAML FAILs yaml-backend (D16)" {
  PATH="$KISLYUK_BIN:$PATH" PYTHONPATH="$(pf_shadow yaml)" run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line yaml-backend)" = 'FAIL: yaml-backend: no mikefarah yq v4 and no python3 with PyYAML — remediation: install mikefarah yq v4, or python3 with PyYAML' ]
  [[ "$(pf_line python3)" == 'PASS: python3: '* ]]
  [[ "${lines[17]}" == SUMMARY:*' fail=1 '* ]]
}

@test "setup-preflight: the kislyuk yq first on PATH with PyYAML PASSes yaml-backend through python3 (D16)" {
  PATH="$KISLYUK_BIN:$PATH" SDLC_FORCE_PYTHON_YAML=0 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line yaml-backend)" = 'PASS: yaml-backend: python3 + PyYAML (the yq on PATH is not mikefarah v4)' ]
  PATH="$KISLYUK_BIN:$PATH" SDLC_FORCE_PYTHON_YAML=1 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line yaml-backend)" = 'PASS: yaml-backend: python3 + PyYAML (SDLC_FORCE_PYTHON_YAML=1)' ]
}

@test "setup-preflight: a yq answering !!seq PASSes as mikefarah unless SDLC_FORCE_PYTHON_YAML=1" {
  pf_fake "$BATS_TEST_TMPDIR/mikefarah" yq "cat >/dev/null; printf '!!seq\\n'"
  PATH="$BATS_TEST_TMPDIR/mikefarah:$PATH" SDLC_FORCE_PYTHON_YAML=0 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line yaml-backend)" = 'PASS: yaml-backend: mikefarah yq v4' ]
  PATH="$BATS_TEST_TMPDIR/mikefarah:$PATH" SDLC_FORCE_PYTHON_YAML=1 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line yaml-backend)" = 'PASS: yaml-backend: python3 + PyYAML (SDLC_FORCE_PYTHON_YAML=1)' ]
}

@test "setup-preflight: with jq absent json-backend PASSes through python3 (D16)" {
  sb="$(pf_sandbox python3 gh claude bmalph make)"
  run --separate-stderr env PATH="$KISLYUK_BIN:$sb" "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line json-backend)" = 'PASS: json-backend: python3 (jq not found)' ]
  [[ "$(pf_line yaml-backend)" == 'PASS: yaml-backend: python3 + PyYAML ('* ]]
}

@test "setup-preflight: with neither jq nor python3 json-backend FAILs" {
  sb="$(pf_sandbox gh claude bmalph make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line json-backend)" = 'FAIL: json-backend: neither jq nor python3 found — remediation: install jq, or python3' ]
  [ "$(pf_line yaml-backend)" = 'FAIL: yaml-backend: no mikefarah yq v4 and no python3 with PyYAML — remediation: install mikefarah yq v4, or python3 with PyYAML' ]
}

# --- make, bash, git ---------------------------------------------------------------------

@test "setup-preflight: make 3.81 FAILs with the GNU Make remediation" {
  STUB_MAKE_VERSION_LINE='GNU Make 3.81' run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = 'git-repo gh gh-auth claude claude-restricted bmalph bmalph-doctor python3 yaml-backend json-backend make' ]
  [ "${lines[10]}" = 'FAIL: make: GNU Make 3.81 is below 4.0 — remediation: install GNU Make 4.0 or newer' ]
}

@test "setup-preflight: a make that is not GNU Make, or no make, FAILs make" {
  STUB_MAKE_VERSION_LINE='bmake 20240711' run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line make)" = 'FAIL: make: make is not GNU Make (bmake 20240711) — remediation: install GNU Make 4.0 or newer' ]
  sb="$(pf_sandbox python3 gh claude bmalph)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_line make)" = 'FAIL: make: make not found on PATH — remediation: install GNU Make 4.0 or newer' ]
}

@test "setup-preflight: RUST_SDLC_BASH_VERSION=4.3 fails with install Bash 4.4 or newer before any check" {
  RUST_SDLC_BASH_VERSION=4.3 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *'[rust-sdlc][ERROR] bash 4.3 is too old: install Bash 4.4 or newer'* ]]
  [ ! -s "$STUB_GH_LOG" ]
  RUST_SDLC_BASH_VERSION=5.1 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line bash)" = 'PASS: bash: bash 5.1 (floor 4.4)' ]
}

@test "setup-preflight: git 2.29 FAILs with the upgrade remediation" {
  pf_wrap "$BATS_TEST_TMPDIR/git229" git 'git version 2.29.2'
  PATH="$BATS_TEST_TMPDIR/git229:$PATH" run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == 'PASS: git-repo: '* ]]
  [ "$(pf_ids)" = 'git-repo gh gh-auth claude claude-restricted bmalph bmalph-doctor python3 yaml-backend json-backend make bash git' ]
  [ "${lines[12]}" = 'FAIL: git: git 2.29.2 is below 2.30 — remediation: upgrade git to 2.30 or newer' ]
}

@test "setup-preflight: every under-version stub at once: --report FAILs each with its remediation, exit 1 (AC-10.1)" {
  pf_python "$BATS_TEST_TMPDIR/under" 3.10.12
  pf_wrap "$BATS_TEST_TMPDIR/under" git 'git version 2.29.2'
  sb="$(PATH="$BATS_TEST_TMPDIR/under:$PATH" pf_sandbox python3 gh claude bmalph make)"
  STUB_GH_VERSION=1.9 STUB_BMALPH_VERSION=2.10.0 STUB_CLAUDE_RESTRICTED=0 STUB_MAKE_VERSION_LINE='GNU Make 3.81' \
    run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = "$CHECK_IDS" ]
  [ "$(pf_line gh)" = 'FAIL: gh: gh 1.9 is below 2.0 — remediation: upgrade GitHub CLI to 2.0 or newer' ]
  [ "$(pf_line claude-restricted)" = 'FAIL: claude-restricted: claude --help does not list --restricted — remediation: upgrade Claude Code to 2.1.248 or newer' ]
  [ "$(pf_line bmalph)" = 'FAIL: bmalph: bmalph 2.10.0 is below 2.11.0 — remediation: upgrade bmalph to 2.11.0 or newer' ]
  [ "$(pf_line python3)" = 'FAIL: python3: python3 3.10.12 is below 3.11 — remediation: install Python 3.11 or newer' ]
  [ "$(pf_line make)" = 'FAIL: make: GNU Make 3.81 is below 4.0 — remediation: install GNU Make 4.0 or newer' ]
  [ "$(pf_line git)" = 'FAIL: git: git 2.29.2 is below 2.30 — remediation: upgrade git to 2.30 or newer' ]
  [ "${lines[17]}" = 'SUMMARY: pass=7 warn=0 fail=6 info=4' ]
}

# --- git-repo ------------------------------------------------------------------------------

@test "setup-preflight: outside a git repository git-repo FAILs and the default mode stops" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  cd "$BATS_TEST_TMPDIR/plain"
  GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == 'FAIL: git-repo: not inside a git work tree ('*') — remediation: run setup from the work tree of the target repository (git clone or git init first)' ]]
  [ "${lines[1]}" = 'SUMMARY: pass=0 warn=0 fail=1 info=0' ]
}

@test "setup-preflight: --report outside a git repository skips the tracked tree and checks markers in the working directory" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  cd "$BATS_TEST_TMPDIR/plain"
  GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 1 ]
  [ "$(pf_ids)" = "$CHECK_IDS" ]
  [ "$(pf_line tracked-tree)" = 'INFO: tracked-tree: not checked (not inside a git work tree)' ]
  [[ "$(pf_line template-markers)" == 'WARN: template-markers: missing rust-toolchain.toml, '* ]]
}

@test "setup-preflight: a bare repository and the .git/ directory have no work tree and FAIL git-repo" {
  git init -q --bare "$BATS_TEST_TMPDIR/bare.git"
  cd "$BATS_TEST_TMPDIR/bare.git"
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = 'FAIL: git-repo: no work tree here (inside .git/ or a bare repository) — remediation: run setup from the work tree of the target repository' ]
  cd "$REPO/.git"
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = 'FAIL: git-repo: no work tree here (inside .git/ or a bare repository) — remediation: run setup from the work tree of the target repository' ]
}

# --- repository state: markers, tracked tree, Docker, cargo ----------------------------------

@test "setup-preflight: a dirty tracked tree is INFO listing the files of git status, untracked files left out (AC-4.4, D5)" {
  printf 'local edit\n' >>README.md
  printf '# edit\n' >>Cargo.toml
  printf 'staged edit\n' >>AGENTS.md
  git add AGENTS.md
  printf 'scratch\n' >notes.txt
  expected="$(git status --porcelain --untracked-files=no | cut -c4- | paste -sd, - | sed 's/,/, /g')"
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line tracked-tree)" = "INFO: tracked-tree: tracked changes: $expected" ]
  [ "$(pf_line tracked-tree)" = 'INFO: tracked-tree: tracked changes: AGENTS.md, Cargo.toml, README.md' ]
  [[ "$output" != *notes.txt* ]]
}

@test "setup-preflight: dirty tree, a missing marker, Docker unreachable and no cargo are INFO/WARN only, exit 0 (AC-4.4)" {
  printf 'local edit\n' >>README.md
  rm workspace.dsl
  sb="$(pf_sandbox python3 gh claude bmalph make docker)"
  run --separate-stderr env PATH="$sb" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pf_ids)" = "$CHECK_IDS" ]
  [ "$(pf_line template-markers)" = 'WARN: template-markers: missing workspace.dsl (not template-derived: capabilities off)' ]
  [ "$(pf_line tracked-tree)" = 'INFO: tracked-tree: tracked changes: README.md, workspace.dsl' ]
  [ "$(pf_line docker)" = 'INFO: docker: unreachable (docker info failed)' ]
  [ "$(pf_line cargo)" = 'INFO: cargo: absent (no host toolchain)' ]
  [[ "${lines[17]}" == SUMMARY:*' warn=1 fail=0 '* ]]
}

@test "setup-preflight: missing A1 markers WARN naming each one and never FAIL (ADR-17, D20)" {
  rm architecture.toml xtask/Cargo.toml
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pf_line template-markers)" = 'WARN: template-markers: missing architecture.toml, xtask/Cargo.toml (not template-derived: capabilities off)' ]
  [[ "${lines[17]}" == SUMMARY:*' warn=1 fail=0 '* ]]
}

@test "setup-preflight: CI_PREFLIGHT_TARGETS must start with validate-configuration; continuation lines are joined" {
  pf_edit Makefile '$1 == "CI_PREFLIGHT_TARGETS" { print "CI_PREFLIGHT_TARGETS := secrets-scan validate-configuration"; next } { print }'
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line template-markers)" = 'WARN: template-markers: missing CI_PREFLIGHT_TARGETS starting with validate-configuration (not template-derived: capabilities off)' ]
  pf_edit Makefile '$1 == "CI_PREFLIGHT_TARGETS" { print "CI_PREFLIGHT_TARGETS := \\"; print "  validate-configuration validate-invariants"; next } { print }'
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line template-markers)" = 'PASS: template-markers: all 8 template markers present (template-derived)' ]
}

@test "setup-preflight: a repository without any marker WARNs all eight and still exits 0" {
  git init -q "$BATS_TEST_TMPDIR/bare-service"
  cd "$BATS_TEST_TMPDIR/bare-service"
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line template-markers)" = 'WARN: template-markers: missing rust-toolchain.toml, architecture.toml, protected-config.toml, xtask/Cargo.toml, make/gates.mk, crates/service/Cargo.toml, workspace.dsl, CI_PREFLIGHT_TARGETS starting with validate-configuration (not template-derived: capabilities off)' ]
  [[ "$output" != *'FAIL: template-markers'* ]]
}

@test "setup-preflight: Docker is INFO unreachable when docker info fails or docker is absent, INFO reachable otherwise (D2)" {
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line docker)" = 'INFO: docker: unreachable (docker info failed)' ]
  STUB_DOCKER_INFO_EXIT=0 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line docker)" = 'INFO: docker: reachable' ]
  sb="$(pf_sandbox python3 gh claude bmalph make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line docker)" = 'INFO: docker: unreachable (docker not found on PATH)' ]
}

@test "setup-preflight: cargo is INFO present or INFO absent and is never run" {
  run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line cargo)" = 'INFO: cargo: present (host toolchain)' ]
  [ ! -s "$STUB_CARGO_LOG" ]
  sb="$(pf_sandbox python3 gh claude bmalph make)"
  run --separate-stderr env PATH="$sb" "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_line cargo)" = 'INFO: cargo: absent (no host toolchain)' ]
}

# --- contract: no writes, only the listed calls ----------------------------------------------

@test "setup-preflight: writes nothing and calls only the commands of its contract" {
  mkdir -p _bmad
  printf 'local edit\n' >>README.md
  # A tracked file whose mtime changed but whose content did not: a plain
  # `git status` would refresh the stat data and rewrite .git/index.
  touch -t 202601020304 Cargo.lock
  before="$(pf_snapshot "$REPO")"
  STUB_DOCKER_INFO_EXIT=0 run --separate-stderr "$SCRIPT" --report
  [ "$status" -eq 0 ]
  [ "$(pf_snapshot "$REPO")" = "$before" ]
  [ "$(cat "$STUB_GH_LOG")" = $'gh --version\ngh auth status' ]
  [ "$(cat "$STUB_CLAUDE_LOG")" = $'claude --version\nclaude --help' ]
  [ "$(cat "$STUB_BMALPH_LOG")" = $'bmalph --version\nbmalph doctor' ]
  [ "$(cat "$STUB_MAKE_LOG")" = 'make --version' ]
  [ "$(cat "$STUB_DOCKER_LOG")" = 'docker info' ]
  [ ! -s "$STUB_CARGO_LOG" ]
  [ ! -s "$STUB_CURL_LOG" ]
  # Static half: no output redirection other than /dev/null or another
  # descriptor, and no file-changing command, on any code line.
  run grep -nE '>' "$SCRIPT"
  bad="$(printf '%s\n' "$output" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -E '>' | grep -vE '>/dev/null|>&[12]' || true)"
  [ -z "$bad" ]
  run grep -nwE 'tee|mkdir|touch|mv|cp|rm|ln|chmod|atomic_write|safe_write_target' "$SCRIPT"
  bad="$(printf '%s\n' "$output" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
  [ -z "$bad" ]
}
