#!/usr/bin/env bats
# Component-count + load-integrity tests (Story E7-S2, NFR-1).
#
# Asserts the exact install-cache layout — 8 commands / 7 agents /
# 22 skills + 2 loose meta-guides — so the suite fails when any
# component file is removed or added. Also checks the load-integrity
# invariants the CI frontmatter-check and manifest-validate jobs
# enforce, so a broken component is caught locally before push.
#
# `claude plugin` listing smoke (NFR-1): after
# `claude plugin install php-backend-sdlc@vilnacrm-plugins`, the
# `/plugin` manager must list all 8 commands, 7 agents, and 22 skills;
# these counts are the canonical reference for that manual check.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
}

# Print the frontmatter block of $1 (between the leading '---' fences);
# empty output when the file has no frontmatter.
extract_frontmatter() {
  awk 'NR==1 { if ($0 != "---") exit; next } /^---$/ { exit } { print }' "$1"
}

# Fail unless the frontmatter of $1 declares every key in $2.. with a
# non-empty value (scalar on the key line, or a block/list value
# continued on indented lines below it).
assert_frontmatter_keys() {
  local file=$1; shift
  local fm key line rest
  fm="$(extract_frontmatter "$file")"
  [ -n "$fm" ] || { echo "no frontmatter: $file"; return 1; }
  for key in "$@"; do
    line="$(printf '%s\n' "$fm" | grep -E "^${key}:" | head -n1)" \
      || { echo "missing key '$key': $file"; return 1; }
    rest="${line#"${key}":}"
    rest="${rest# }"
    if [ -z "$rest" ] || [ "$rest" = "|" ] || [ "$rest" = ">" ]; then
      # Block scalar or empty inline value: require an indented
      # continuation line so the key is not silently empty.
      printf '%s\n' "$fm" | grep -A1 -E "^${key}:" | tail -n +2 \
        | grep -qE '^[[:space:]]+[^[:space:]]' \
        || { echo "empty value for '$key': $file"; return 1; }
    fi
  done
}

# --- exact component counts (NFR-1) ---------------------------------------

@test "exactly 8 command markdown files" {
  run bash -c "ls '$PLUGIN_ROOT'/commands/*.md | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 8 ]
}

@test "exactly 7 agent markdown files" {
  run bash -c "ls '$PLUGIN_ROOT'/agents/*.md | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 7 ]
}

@test "exactly 22 skills (skills/*/SKILL.md)" {
  run bash -c "ls '$PLUGIN_ROOT'/skills/*/SKILL.md | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 22 ]
}

@test "every skill directory contains a SKILL.md" {
  for dir in "$PLUGIN_ROOT"/skills/*/; do
    [ -f "${dir}SKILL.md" ] || { echo "missing SKILL.md: $dir"; return 1; }
  done
}

@test "exactly 2 loose meta-guides at skills/ root, by name" {
  run bash -c "ls '$PLUGIN_ROOT'/skills/*.md | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
  [ -f "$PLUGIN_ROOT/skills/SKILL-DECISION-GUIDE.md" ]
  [ -f "$PLUGIN_ROOT/skills/AI-AGENT-GUIDE.md" ]
}

# --- load integrity: frontmatter contracts (ADR-11) ------------------------

@test "every command declares description frontmatter" {
  for f in "$PLUGIN_ROOT"/commands/*.md; do
    assert_frontmatter_keys "$f" description
  done
}

@test "every command declares argument-hint frontmatter (CI parity)" {
  for f in "$PLUGIN_ROOT"/commands/*.md; do
    assert_frontmatter_keys "$f" argument-hint
  done
}

@test "every agent declares name, description, tools, model" {
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    assert_frontmatter_keys "$f" name description tools model
  done
}

@test "every SKILL.md declares name and description" {
  for f in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    assert_frontmatter_keys "$f" name description
  done
}

@test "skill frontmatter name matches its directory name" {
  for f in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    dir="$(basename "$(dirname "$f")")"
    name="$(extract_frontmatter "$f" | grep -E '^name:' | head -n1)"
    name="${name#name:}"
    name="${name# }"
    [ "$name" = "$dir" ] || { echo "skill name '$name' != dir '$dir'"; return 1; }
  done
}

@test "meta-guides at skills/ root have no frontmatter (ADR-11)" {
  for f in "$PLUGIN_ROOT"/skills/*.md; do
    [ "$(head -n1 "$f")" != "---" ] \
      || { echo "meta-guide must not have frontmatter: $f"; return 1; }
  done
}

# --- load integrity: manifests ---------------------------------------------

@test "plugin.json parses and its name matches the plugin directory" {
  manifest="$PLUGIN_ROOT/.claude-plugin/plugin.json"
  [ -f "$manifest" ]
  run jq -e . "$manifest"
  [ "$status" -eq 0 ]
  run jq -r .name "$manifest"
  [ "$output" = "$(basename "$PLUGIN_ROOT")" ]
}

@test "plugin.json carries required fields with semver version" {
  manifest="$PLUGIN_ROOT/.claude-plugin/plugin.json"
  run jq -e '.name and .description and .version and .author.name
             and .homepage and .repository and .license
             and (.keywords | length > 0)' "$manifest"
  [ "$status" -eq 0 ]
  run jq -e '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' "$manifest"
  [ "$status" -eq 0 ]
}

@test "marketplace.json parses and lists this plugin with ADR-9 source" {
  marketplace="$REPO_ROOT/.claude-plugin/marketplace.json"
  [ -f "$marketplace" ]
  run jq -e . "$marketplace"
  [ "$status" -eq 0 ]
  plugin_name="$(basename "$PLUGIN_ROOT")"
  run jq -e --arg n "$plugin_name" \
    '.plugins[] | select(.name == $n) | .source == ("./plugins/" + $n)' \
    "$marketplace"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
