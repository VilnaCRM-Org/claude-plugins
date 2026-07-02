#!/usr/bin/env bats
# Tests for scripts/setup-preflight.sh (react-frontend-sdlc; FR-2, NFR-7, ADR-10).
#
# The frontend preflight checks, in order: git-repo, claude-cli (>= 2.1),
# gh-cli (>= 2), gh-auth, bmalph (>= 2.11.0), bmalph-doctor, package-manager
# (any of bun|pnpm|npm), node (>= 20.0.0), docker, yaml-toolchain, and
# json-toolchain. Logging is prefixed [react-sdlc] and the profile lives at
# .claude/react-sdlc.yml (do NOT copy the backend [php-sdlc] text).
#
# Stub claude/gh/bmalph binaries from fixtures/bin are prepended to PATH so
# version and auth outcomes are driven per-test via STUB_* env vars (they
# shadow any real binaries). The node/docker/package-manager checks use the
# host's real tools. The sandbox-PATH helper builds a minimal bin dir for the
# cases that need a binary or YAML/JSON backend to be genuinely ABSENT, which
# PATH-prepending cannot simulate.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PREFLIGHT="$PLUGIN_ROOT/scripts/setup-preflight.sh"
  STUBS="$BATS_TEST_DIRNAME/fixtures/bin"
  # A git repo to satisfy the git-repo check.
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  cd "$REPO"
  PATH="$STUBS:$PATH"
}

# sandbox_path TOOL... — builds a dir holding ONLY the named tools (system
# symlinks or fixture stubs) and echoes it. Used as the entire PATH to make
# everything else invisible.
sandbox_path() {
  local dir="$BATS_TEST_TMPDIR/sandbox-bin"
  rm -rf "$dir"
  mkdir -p "$dir"
  local tool src
  for tool in "$@"; do
    if [ -x "$STUBS/$tool" ]; then
      ln -s "$STUBS/$tool" "$dir/$tool"
    else
      src="$(command -v "$tool")"
      ln -s "$src" "$dir/$tool"
    fi
  done
  echo "$dir"
}

# Tools the script itself needs (bash for stubs, git, coreutils, grep).
SCRIPT_DEPS="bash git grep sort head dirname env"

@test "all-pass: exit 0, every check reports PASS" {
  run "$PREFLIGHT"
  [ "$status" -eq 0 ]
  for check in git-repo claude-cli gh-cli gh-auth bmalph bmalph-doctor \
    package-manager node docker yaml-toolchain json-toolchain; do
    [[ "$output" == *"PASS: $check"* ]]
  done
  # non-report mode prints the full detail (contrast: --report truncates it)
  [[ "$output" == *"any of bun|pnpm|npm satisfies"* ]]
  [[ "$output" == *"preflight OK"* ]]
  [[ "$output" == *"[react-sdlc]"* ]]
  [[ "$output" != *FAIL* ]]
}

@test "all-pass --report: full PASS table, exit 0" {
  run "$PREFLIGHT" --report
  [ "$status" -eq 0 ]
  [[ "$output" == *CHECK*RESULT* ]]
  for check in git-repo claude-cli gh-cli gh-auth bmalph bmalph-doctor \
    package-manager node docker yaml-toolchain json-toolchain; do
    [[ "$output" == *"$check"* ]]
  done
  [[ "$output" =~ package-manager[[:space:]]+PASS ]]
  [[ "$output" =~ node[[:space:]]+PASS ]]
  [[ "$output" =~ docker[[:space:]]+PASS ]]
  [[ "$output" != *FAIL* ]]
}

@test "under-version claude: aborts with named remediation before later checks" {
  STUB_CLAUDE_VERSION=1.9.0 run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: claude-cli"* ]]
  [[ "$output" == *"version 1.9.0 below required floor 2.1"* ]]
  [[ "$output" == *"npm install -g @anthropic-ai/claude-code"* ]]
  # first-FAIL abort: bmalph check (later in order) must not have run
  [[ "$output" != *bmalph* ]]
}

@test "under-version gh: named remediation" {
  STUB_GH_VERSION=1.5.0 run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: gh-cli"* ]]
  [[ "$output" == *"below required floor 2"* ]]
  [[ "$output" == *"https://cli.github.com"* ]]
}

@test "under-version bmalph: named remediation citing the ADR-10 floor" {
  STUB_BMALPH_VERSION=2.10.9 run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: bmalph"* ]]
  [[ "$output" == *"version 2.10.9 below required floor 2.11.0"* ]]
  [[ "$output" == *"ADR-10 compatibility floor"* ]]
}

@test "unauthenticated gh: remediation says gh auth login" {
  STUB_GH_AUTH_EXIT=1 run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: gh-auth"* ]]
  [[ "$output" == *"gh auth login"* ]]
}

@test "outside a git repository: git-repo FAIL with remediation" {
  mkdir -p "$BATS_TEST_TMPDIR/not-a-repo"
  cd "$BATS_TEST_TMPDIR/not-a-repo"
  run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: git-repo"* ]]
  [[ "$output" == *"git clone, or git init"* ]]
}

@test "bare repository: git-repo FAIL — exit-code-0 'false' from rev-parse is not a pass" {
  # `git rev-parse --is-inside-work-tree` exits 0 while PRINTING 'false' in a
  # bare repo; the check must compare the value, not the exit code.
  mkdir -p "$BATS_TEST_TMPDIR/bare-repo"
  git -C "$BATS_TEST_TMPDIR/bare-repo" init -q --bare
  cd "$BATS_TEST_TMPDIR/bare-repo"
  run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: git-repo"* ]]
  [[ "$output" == *"git clone, or git init"* ]]
}

@test "inside .git/ of a normal repo: git-repo FAIL (no work tree)" {
  cd "$REPO/.git"
  run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: git-repo"* ]]
}

@test "bmalph doctor: fresh repo without _bmad/ passes as deferred (FR-2)" {
  run "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: bmalph-doctor"* ]]
  [[ "$output" == *"doctor deferred"* ]]
}

@test "bmalph doctor: healthy existing _bmad/ workspace passes (FR-2)" {
  mkdir -p "$REPO/_bmad"
  run "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: bmalph-doctor"* ]]
  [[ "$output" == *"healthy _bmad/ workspace"* ]]
}

@test "bmalph doctor failure on existing _bmad/: FAIL with remediation (FR-2)" {
  mkdir -p "$REPO/_bmad"
  STUB_BMALPH_DOCTOR_EXIT=1 run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: bmalph-doctor"* ]]
  [[ "$output" == *"run 'bmalph doctor'"* ]]
  [[ "$output" == *"re-run 'bmalph init'"* ]]
  # first-FAIL abort: package-manager (later in order) must not have run
  [[ "$output" != *package-manager* ]]
}

@test "missing bmalph binary: FAIL names the binary" {
  # shellcheck disable=SC2086
  sandbox="$(sandbox_path $SCRIPT_DEPS python3 claude gh)"
  PATH="$sandbox" run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: bmalph"* ]]
  [[ "$output" == *"'bmalph' not found on PATH"* ]]
  # aborted before the package-manager check
  [[ "$output" != *package-manager* ]]
}

@test "no package manager (bun|pnpm|npm absent): FAIL with install remediation" {
  # sandbox lacks bun, pnpm, and npm; checks 1-6 pass, package-manager FAILs
  # shellcheck disable=SC2086
  sandbox="$(sandbox_path $SCRIPT_DEPS claude gh bmalph)"
  PATH="$sandbox" run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: package-manager"* ]]
  [[ "$output" == *"none of bun, pnpm, or npm found on PATH"* ]]
  [[ "$output" == *"https://bun.sh"* ]]
  # first-FAIL abort: yaml-toolchain (later in order) must not have run
  [[ "$output" != *yaml-toolchain* ]]
}

@test "under-version node: FAIL citing the Node floor" {
  # Shadow the real node with a stub that reports an old version. A package
  # manager and every earlier check still pass, so node (check 8) is the abort.
  fakebin="$BATS_TEST_TMPDIR/fake-node"
  mkdir -p "$fakebin"
  printf '#!/usr/bin/env bash\nprintf "v18.19.0\\n"\n' >"$fakebin/node"
  chmod +x "$fakebin/node"
  PATH="$fakebin:$PATH" run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: node"* ]]
  [[ "$output" == *"version 18.19.0 below required floor 20.0.0"* ]]
  [[ "$output" == *"https://nodejs.org"* ]]
  # first-FAIL abort: yaml-toolchain (later in order) must not have run
  [[ "$output" != *yaml-toolchain* ]]
}

@test "missing docker binary: FAIL with get-docker remediation" {
  # sandbox has a package manager (bun) and node so checks 1-8 pass; docker
  # (check 9) is absent and must FAIL.
  # shellcheck disable=SC2086
  sandbox="$(sandbox_path $SCRIPT_DEPS claude gh bmalph bun node)"
  PATH="$sandbox" run "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: docker"* ]]
  [[ "$output" == *"'docker' not found on PATH"* ]]
  [[ "$output" == *"docs.docker.com"* ]]
  # first-FAIL abort: yaml-toolchain (later in order) must not have run
  [[ "$output" != *yaml-toolchain* ]]
}

@test "no YAML toolchain: FAIL with yq-or-PyYAML remediation" {
  # sandbox without python3 and without yq
  # shellcheck disable=SC2086
  sandbox="$(sandbox_path $SCRIPT_DEPS claude gh bmalph)"
  PATH="$sandbox" run "$PREFLIGHT" --report
  [ "$status" -eq 1 ]
  [[ "$output" =~ yaml-toolchain[[:space:]]+FAIL ]]
  [[ "$output" == *"install yq"* ]]
  [[ "$output" == *PyYAML* ]]
}

@test "no JSON toolchain (no jq, no python3): FAIL with jq-or-python3 remediation" {
  # sandbox with a YAML backend (yq) but neither jq nor python3, so the
  # yaml-toolchain check passes while json-toolchain must FAIL — the exact
  # yq-only machine that previously slipped past preflight.
  if ! command -v yq >/dev/null 2>&1; then
    skip "yq not installed here; cannot isolate the json-toolchain failure from yaml-toolchain"
  fi
  # shellcheck disable=SC2086
  sandbox="$(sandbox_path $SCRIPT_DEPS claude gh bmalph bun node docker yq)"
  PATH="$sandbox" run "$PREFLIGHT" --report
  [ "$status" -eq 1 ]
  [[ "$output" =~ yaml-toolchain[[:space:]]+PASS ]]
  [[ "$output" =~ json-toolchain[[:space:]]+FAIL ]]
  [[ "$output" == *"install jq"* ]]
  [[ "$output" == *"python3"* ]]
}

@test "json-toolchain passes on python3 alone (no jq)" {
  # sandbox with python3 but no jq and no yq: json-toolchain must still PASS
  # via the python3 fallback (yaml passes via python3+PyYAML).
  # shellcheck disable=SC2086
  sandbox="$(sandbox_path $SCRIPT_DEPS claude gh bmalph python3)"
  PATH="$sandbox" run "$PREFLIGHT" --report
  [[ "$output" =~ json-toolchain[[:space:]]+PASS ]]
  [[ "$output" == *"python3 available"* ]]
}

@test "--report with multiple failures lists every FAIL row, exit 1" {
  STUB_CLAUDE_VERSION=1.0.0 STUB_GH_VERSION=1.0.0 STUB_BMALPH_VERSION=1.0.0 \
    run "$PREFLIGHT" --report
  [ "$status" -eq 1 ]
  [[ "$output" =~ claude-cli[[:space:]]+FAIL ]]
  [[ "$output" =~ gh-cli[[:space:]]+FAIL ]]
  [[ "$output" =~ bmalph[[:space:]]+FAIL ]]
  # report mode still names a remediation per failure
  [[ "$output" == *"npm install -g @anthropic-ai/claude-code"* ]]
  [[ "$output" == *"https://cli.github.com"* ]]
  [[ "$output" == *"ADR-10"* ]]
  [[ "$output" == *"3 check(s) failed"* ]]
}

@test "version floors are inclusive: exact-floor versions pass" {
  STUB_CLAUDE_VERSION=2.1 STUB_GH_VERSION=2.0.0 STUB_BMALPH_VERSION=2.11.0 \
    run "$PREFLIGHT"
  [ "$status" -eq 0 ]
}

@test "unknown argument: usage error" {
  run "$PREFLIGHT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
  [[ "$output" == *"usage"* ]]
}
