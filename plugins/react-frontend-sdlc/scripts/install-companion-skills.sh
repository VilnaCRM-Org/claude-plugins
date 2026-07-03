#!/usr/bin/env bash
# install-companion-skills.sh — best-effort installer for the optional
# ui-skills.com design / motion / accessibility companion suite (FR-2 step 7).
#
# Usage: install-companion-skills.sh [PROFILE_FILE]
#   PROFILE_FILE defaults to <cwd>/.claude/react-sdlc.yml
#
# The companion skills and agents are THIRD-PARTY, mixed/unknown license, and
# are deliberately NOT bundled with this plugin (they are referenced, not
# vendored). This installer only ever writes under the USER config dir
# (${CLAUDE_CONFIG_DIR:-$HOME/.claude}) — it NEVER touches the target repo
# tree — and it only acts on companions that are ABSENT: anything already on
# disk is left exactly as the user has it.
#
# It is an enhancement, never a hard dependency: every gate runs without the
# companions. Install modes are read from the profile's
# `companion.install_command`:
#   - a template containing `{name}`  -> run the substituted command per absent item
#   - `plugin`                        -> `claude plugin install {name}` per absent item
#   - anything else (e.g. `manual`)   -> report-only: list the absent companions and
#                                        point at docs/companion-skills.md (the reference)
# A failed auto-install is surfaced as a warning and a non-zero exit, but the
# caller (/fe-sdlc-setup) treats that as NON-FATAL and continues.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# shellcheck disable=SC2119  # profile_path's TARGET_REPO_DIR arg is optional
PROFILE="${1:-$(profile_path)}"
[[ -f "$PROFILE" ]] || die "profile not found: $PROFILE (run /fe-sdlc-setup to generate it)"
require_yaml_toolchain

PLUGIN_ROOT="$(resolve_plugin_root)"
DOCS_REF="${PLUGIN_ROOT}/docs/companion-skills.md"

USER_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
USER_SKILLS="$USER_CONFIG/skills"
USER_AGENTS="$USER_CONFIG/agents"

install_command="$(yaml_get "$PROFILE" companion.install_command)"

# read_list KEY — companion list items, one per line ('' when absent/empty).
read_list() { yaml_get_list "$PROFILE" "$1"; }

installed=()
skipped=()
failed=()
manual=()

# present KIND NAME — exit 0 when a companion of KIND (skill|agent) named NAME
# already exists under the user config dir, in either a <name>/ dir or a
# <name>.md file (skills ship as dirs, agents as single files).
present() {
  local kind=$1 name=$2 base
  case "$kind" in
    skill) base="$USER_SKILLS" ;;
    agent) base="$USER_AGENTS" ;;
    *) return 1 ;;
  esac
  [[ -d "$base/$name" || -f "$base/$name.md" || -d "$base/$name/" ]]
}

# run_install NAME — attempt the configured auto-install for one companion.
# Returns non-zero on any failure (missing tool, non-zero installer exit).
run_install() {
  local name=$1 cmd
  if [[ "$install_command" == *"{name}"* ]]; then
    # {name} is interpolated into a string run via `bash -c`, so an unsafe
    # name is a command-injection vector — reject it. The allowlist is scoped
    # to this branch only: `plugin` mode passes $name as a proper argv arg,
    # and report-only/manual modes never execute it.
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { log_warn "skipping companion with unsafe name: $name"; return 1; }
    cmd="${install_command//\{name\}/$name}"
    bash -c "$cmd"
  elif [[ "$install_command" == "plugin" ]]; then
    command -v claude >/dev/null 2>&1 || return 1
    claude plugin install "$name" >/dev/null 2>&1
  else
    return 2  # report-only: not auto-installable in this mode
  fi
}

# process KIND — partition one companion list into installed/skipped/failed/manual.
process() {
  local kind=$1 key=$2 name rc
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if present "$kind" "$name"; then
      skipped+=("$kind:$name")
      continue
    fi
    set +e
    run_install "$name"
    rc=$?
    set -e
    if (( rc == 0 )); then
      installed+=("$kind:$name")
    elif (( rc == 2 )); then
      manual+=("$kind:$name")
    else
      failed+=("$kind:$name")
    fi
  done < <(read_list "$key")
}

process skill companion.skills
process agent companion.agents

# --- report -------------------------------------------------------------------

report_group() {
  local label=$1; shift
  (( $# > 0 )) || return 0
  log_info "$label ($#): $*"
}

report_group "already present, skipped" "${skipped[@]+"${skipped[@]}"}"
report_group "installed" "${installed[@]+"${installed[@]}"}"

if (( ${#manual[@]} > 0 )); then
  log_info "reference-only (install_command='${install_command:-manual}'): ${#manual[@]} companion(s) not auto-installed"
  log_info "install them from ui-skills.com per the catalog + MUI translations in: $DOCS_REF"
  printf '  - %s\n' "${manual[@]}"
fi

if (( ${#failed[@]} > 0 )); then
  log_warn "auto-install failed for ${#failed[@]} companion(s): ${failed[*]}"
  log_warn "these are optional — every gate runs without them; see $DOCS_REF"
  exit 1
fi

log_info "companion skills step complete (non-fatal enhancement)"
