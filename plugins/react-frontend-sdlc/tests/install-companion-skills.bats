#!/usr/bin/env bats
# Tests for scripts/install-companion-skills.sh (FR-2 step 7).
#
# The installer only ever writes under the USER config dir
# (${CLAUDE_CONFIG_DIR:-$HOME/.claude}); it must NEVER touch the target repo
# tree, and only acts on companions that are ABSENT. Every test points
# CLAUDE_CONFIG_DIR at a throwaway fake config under $BATS_TEST_TMPDIR and
# CLAUDE_PLUGIN_ROOT at the real plugin (so DOCS_REF resolves to the shipped
# docs/companion-skills.md). SDLC_FORCE_PYTHON_YAML=1 pins the python3+PyYAML
# YAML backend (yq is absent on this host anyway) so parsing is deterministic.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/install-companion-skills.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  STUBS="$FIX/bin"

  # Fake user config dir — the ONLY tree the installer may write to.
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_CONFIG_DIR/agents"

  # DOCS_REF resolves under here; docs/companion-skills.md ships in the plugin.
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export SDLC_FORCE_PYTHON_YAML=1

  # A stand-in "target repo" the installer must leave untouched.
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/.claude" "$REPO/src"
  printf 'keep\n' >"$REPO/src/app.tsx"
}

# --- helpers -----------------------------------------------------------------

# write_profile FILE INSTALL_CMD SKILLS_CSV AGENTS_CSV
# Emit a minimal profile fixture into $BATS_TEST_TMPDIR. SKILLS_CSV/AGENTS_CSV
# are comma-separated names ('' -> empty list []). INSTALL_CMD is written as a
# single-quoted YAML scalar so backslashes/globs survive verbatim.
write_profile() {
  local file=$1 cmd=$2 skills=$3 agents=$4
  {
    printf 'companion:\n'
    printf '  skills: [%s]\n' "$(csv_to_yaml "$skills")"
    printf '  agents: [%s]\n' "$(csv_to_yaml "$agents")"
    printf "  install_command: '%s'\n" "$cmd"
  } >"$file"
}

# csv_to_yaml a,b,c -> "a", "b", "c"   ('' -> '')
csv_to_yaml() {
  local csv=$1 out="" item
  [[ -n "$csv" ]] || { printf ''; return 0; }
  local IFS=','
  for item in $csv; do
    out+="\"$item\", "
  done
  printf '%s' "${out%, }"
}

# fingerprint DIR — a stable snapshot of a tree: sorted path list plus content
# hashes, so a test can assert byte-for-byte that the tree did not change.
fingerprint() {
  ( cd "$1" && find . | LC_ALL=C sort \
      && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort )
}

# ============================================================================
# (b) manual mode (default): absent companions are reference-only, exit 0
# ============================================================================

@test "manual mode: absent companions reported reference-only pointing at docs, exit 0" {
  # valid.yml ships install_command: "manual" with 5 skills + 5 agents.
  run "$SCRIPT" "$FIX/profiles/valid.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[react-sdlc][INFO] reference-only (install_command='manual'): 10 companion(s) not auto-installed"* ]]
  [[ "$output" == *"install them from ui-skills.com per the catalog + MUI translations in:"* ]]
  [[ "$output" == *"docs/companion-skills.md"* ]]
  [[ "$output" == *"  - skill:design-taste-frontend"* ]]
  [[ "$output" == *"  - agent:accessibility-lead"* ]]
  [[ "$output" == *"[react-sdlc][INFO] companion skills step complete (non-fatal enhancement)"* ]]
  # nothing was installed and nothing was already present
  [[ "$output" != *"[react-sdlc][INFO] installed ("* ]]
  [[ "$output" != *"already present, skipped"* ]]
  [[ "$output" != *"auto-install failed"* ]]
}

@test "manual mode: writes nothing under the user skills/agents dirs" {
  run "$SCRIPT" "$FIX/profiles/valid.yml"
  [ "$status" -eq 0 ]
  # report-only mode installs nothing, so both trees stay empty
  [ -z "$(ls -A "$CLAUDE_CONFIG_DIR/skills")" ]
  [ -z "$(ls -A "$CLAUDE_CONFIG_DIR/agents")" ]
}

# ============================================================================
# (a) already-present companions are reported skipped and NOT reinstalled
# ============================================================================

@test "already-present skill dir and agent .md are skipped and never reinstalled" {
  local prof="$BATS_TEST_TMPDIR/skip.yml"
  local log="$BATS_TEST_TMPDIR/install.log"
  # A template install_command that records each invocation, so we can prove
  # the present ones were NOT passed to it.
  write_profile "$prof" "echo {name} >> $log" \
    "design-taste-frontend,oklch-skill" "accessibility-lead,aria-specialist"

  # skills ship as a <name>/ dir; agents as a <name>.md file
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/design-taste-frontend"
  : >"$CLAUDE_CONFIG_DIR/agents/accessibility-lead.md"

  run "$SCRIPT" "$prof"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[react-sdlc][INFO] already present, skipped (2):"* ]]
  [[ "$output" == *"skill:design-taste-frontend"* ]]
  [[ "$output" == *"agent:accessibility-lead"* ]]
  [[ "$output" == *"[react-sdlc][INFO] installed (2):"* ]]
  [[ "$output" == *"skill:oklch-skill"* ]]
  [[ "$output" == *"agent:aria-specialist"* ]]

  # The installer ran ONLY for the absent two — present ones untouched.
  run cat "$log"
  [[ "$output" == *"oklch-skill"* ]]
  [[ "$output" == *"aria-specialist"* ]]
  [[ "$output" != *"design-taste-frontend"* ]]
  [[ "$output" != *"accessibility-lead"* ]]
}

@test "companion present as a skill .md file (not a dir) is also skipped" {
  local prof="$BATS_TEST_TMPDIR/skip-md.yml"
  local log="$BATS_TEST_TMPDIR/install.log"
  write_profile "$prof" "echo {name} >> $log" "frontend-design" ""
  # present() matches a <name>.md file for skills too
  : >"$CLAUDE_CONFIG_DIR/skills/frontend-design.md"

  run "$SCRIPT" "$prof"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already present, skipped (1): skill:frontend-design"* ]]
  [[ "$output" != *"[react-sdlc][INFO] installed ("* ]]
  [ ! -f "$log" ]
}

# ============================================================================
# (c) an install_command "{name}" template that succeeds installs the absent
# ============================================================================

@test "template install_command that succeeds installs every absent companion, exit 0" {
  local prof="$BATS_TEST_TMPDIR/tmpl.yml"
  local marks="$BATS_TEST_TMPDIR/marks"
  mkdir -p "$marks"
  write_profile "$prof" "touch $marks/{name}" \
    "frontend-design,oklch-skill" "aria-specialist"

  run "$SCRIPT" "$prof"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[react-sdlc][INFO] installed (3):"* ]]
  [[ "$output" == *"skill:frontend-design"* ]]
  [[ "$output" == *"skill:oklch-skill"* ]]
  [[ "$output" == *"agent:aria-specialist"* ]]
  [[ "$output" == *"companion skills step complete (non-fatal enhancement)"* ]]
  [[ "$output" != *"reference-only"* ]]
  [[ "$output" != *"already present, skipped"* ]]

  # the substituted command actually ran once per absent name
  [ -f "$marks/frontend-design" ]
  [ -f "$marks/oklch-skill" ]
  [ -f "$marks/aria-specialist" ]
}

@test "plugin mode installs absent companions via 'claude plugin install', exit 0" {
  local prof="$BATS_TEST_TMPDIR/plugin.yml"
  local clog="$BATS_TEST_TMPDIR/claude.log"
  write_profile "$prof" "plugin" "frontend-design" "aria-specialist"

  STUB_CLAUDE_LOG="$clog" PATH="$STUBS:$PATH" run "$SCRIPT" "$prof"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[react-sdlc][INFO] installed (2):"* ]]
  run cat "$clog"
  [[ "$output" == *"claude plugin install frontend-design"* ]]
  [[ "$output" == *"claude plugin install aria-specialist"* ]]
}

# ============================================================================
# (d) the installer NEVER writes into the target repo tree
# ============================================================================

@test "never writes into the target repo tree (manual mode, run from repo)" {
  # profile at the default path inside the repo; run with cwd = repo, no arg
  write_profile "$REPO/.claude/react-sdlc.yml" "manual" \
    "frontend-design" "aria-specialist"
  local before after
  before="$(fingerprint "$REPO")"
  run bash -c 'cd "$1" && "$2"' _ "$REPO" "$SCRIPT"
  [ "$status" -eq 0 ]
  after="$(fingerprint "$REPO")"
  [ "$before" == "$after" ]
}

@test "never writes into the target repo tree (template install goes to config space)" {
  local prof="$REPO/.claude/react-sdlc.yml"
  local dest="$BATS_TEST_TMPDIR/dest"
  mkdir -p "$dest"
  # install command writes only under a config-adjacent dir, never the repo
  write_profile "$prof" "mkdir -p $dest/{name}" \
    "frontend-design,oklch-skill" "aria-specialist"

  local before after
  before="$(fingerprint "$REPO/src")"
  run bash -c 'cd "$1" && "$2"' _ "$REPO" "$SCRIPT"
  [ "$status" -eq 0 ]
  after="$(fingerprint "$REPO/src")"
  [ "$before" == "$after" ]
  # the .claude/ dir holds only the profile we wrote — no new skills/agents
  [ "$(find "$REPO/.claude" -mindepth 1 | LC_ALL=C sort)" == "$REPO/.claude/react-sdlc.yml" ]
  # installs actually landed in config space
  [ -d "$dest/frontend-design" ]
  [ -d "$dest/aria-specialist" ]
}

# ============================================================================
# exit codes: failed auto-install (non-fatal to the caller, but non-zero here)
# ============================================================================

@test "failed auto-install: WARN listing the failures, exit 1" {
  local prof="$BATS_TEST_TMPDIR/fail.yml"
  # a {name} template that always fails
  write_profile "$prof" "false {name}" "frontend-design" "aria-specialist"

  run "$SCRIPT" "$prof"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[react-sdlc][WARN] auto-install failed for 2 companion(s):"* ]]
  [[ "$output" == *"skill:frontend-design"* ]]
  [[ "$output" == *"agent:aria-specialist"* ]]
  [[ "$output" == *"these are optional — every gate runs without them; see"* ]]
  [[ "$output" == *"docs/companion-skills.md"* ]]
  # the final success line must NOT print when there are failures
  [[ "$output" != *"companion skills step complete"* ]]
}

@test "plugin mode with no claude on PATH: auto-install fails, exit 1" {
  local prof="$BATS_TEST_TMPDIR/plugin.yml"
  local sandbox="$BATS_TEST_TMPDIR/sandbox-bin"
  mkdir -p "$sandbox"
  local tool src
  for tool in bash python3 env cat printf dirname mkdir sha256sum find; do
    src="$(command -v "$tool" || true)"
    [ -n "$src" ] && ln -sf "$src" "$sandbox/$tool"
  done
  write_profile "$prof" "plugin" "frontend-design" ""

  PATH="$sandbox" run "$SCRIPT" "$prof"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[react-sdlc][WARN] auto-install failed for 1 companion(s): skill:frontend-design"* ]]
}

# ============================================================================
# empty lists / missing profile — boundary behavior
# ============================================================================

@test "empty companion lists: only the completion line, exit 0" {
  local prof="$BATS_TEST_TMPDIR/empty.yml"
  write_profile "$prof" "manual" "" ""
  run "$SCRIPT" "$prof"
  [ "$status" -eq 0 ]
  [[ "$output" == *"companion skills step complete (non-fatal enhancement)"* ]]
  [[ "$output" != *"reference-only"* ]]
  [[ "$output" != *"already present, skipped"* ]]
  [[ "$output" != *"[react-sdlc][INFO] installed ("* ]]
}

@test "missing profile: dies naming the path and pointing at /fe-sdlc-setup, exit 1" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR/does-not-exist.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[react-sdlc][ERROR] profile not found: $BATS_TEST_TMPDIR/does-not-exist.yml"* ]]
  [[ "$output" == *"run /fe-sdlc-setup to generate it"* ]]
}

@test "default profile path is <cwd>/.claude/react-sdlc.yml when no arg is given" {
  write_profile "$REPO/.claude/react-sdlc.yml" "manual" "frontend-design" ""
  run bash -c 'cd "$1" && "$2"' _ "$REPO" "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reference-only (install_command='manual'): 1 companion(s) not auto-installed"* ]]
  [[ "$output" == *"  - skill:frontend-design"* ]]
}
