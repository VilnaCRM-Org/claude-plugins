#!/usr/bin/env bats
# merge-settings.bats — cases of scripts/merge-settings.sh (FR-9, FR-4;
# AC-4.2, AC-4.3, AC-9.1 to AC-9.3 as amended by ADR-6 and the architecture's
# Permissions Strategy; Degrade Matrix D4; epics A8 and A11; NFR-1, NFR-3,
# NFR-5, NFR-10, NFR-14).
#
# Every case runs against the stub repository materialized at
# $BATS_TEST_TMPDIR/billing-service, whose protected-config.toml lists
# .claude/settings.json and whose .gitignore ignores
# .claude/settings.local.json. Every case also points CLAUDE_PLUGIN_ROOT at the
# sandbox $BATS_TEST_TMPDIR/plugin (after common_setup): an executable stub
# scripts/lib/common.sh and the 13 executables scripts/<name>.sh of
# Permissions Strategy row 25, each mode 755, so the plugin-root entries are
# asserted against that sandbox and the suite does not depend on which plugin
# scripts exist yet (A8); the real tree is checked by component-counts.bats
# (CC-05). The expected entries are the suite's own copy of the architecture
# tables (ms_expected_allow, ms_expected_deny), and one case compares that
# copy with the tables of architecture.md when the checkout carries it.
#
# shellcheck disable=SC2016 # single-quoted python programs are literal on purpose

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/plugin"
  ms_sandbox "$CLAUDE_PLUGIN_ROOT"
  SCRIPT="$PLUGIN_ROOT/scripts/merge-settings.sh"
  REPO="$BATS_TEST_TMPDIR/billing-service"
  LOCAL="$REPO/.claude/settings.local.json"
  SHARED="$REPO/.claude/settings.json"
  OUT="$BATS_TEST_TMPDIR/out.txt"
  USAGE='merge-settings.sh [--print] [--with-qa-network] [--file local|shared] [TARGET_DIR]'
  INFO='INFO: QA probes run through common.sh http_probe; no curl entry is written'
  ARCHITECTURE="$PLUGIN_ROOT/../../specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/architecture.md"
  UID_NOW="$(id -u)"
  GID_NOW="$(id -g)"
  rr_materialize "$REPO"
  # Only the repository's own ignore rules decide: no global excludes file.
  : >"$BATS_TEST_TMPDIR/no-global-excludes"
  git -C "$REPO" config core.excludesFile "$BATS_TEST_TMPDIR/no-global-excludes"
}

teardown() {
  chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# ms_names — the 13 plugin executables of Permissions Strategy row 25, in
# table order.
ms_names() {
  printf '%s\n' setup-preflight generate-profile validate-profile inject-governance \
    merge-settings new-service stage-planning-artifacts ai-review-loop fr-nfr-gate \
    get-pr-comments post-review-findings pr-state request-ai-reviews
}

# ms_sandbox ROOT — the sandbox plugin root: an executable stub
# scripts/lib/common.sh and the 13 row-25 executables, each mode 755.
ms_sandbox() {
  local root="$1" name
  mkdir -p "$root/scripts/lib"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/scripts/lib/common.sh"
  chmod 755 "$root/scripts/lib/common.sh"
  while IFS= read -r name; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$root/scripts/$name.sh"
    chmod 755 "$root/scripts/$name.sh"
  done < <(ms_names)
}

# ms_expected_allow ROOT UID GID — the 66 allow entries of rows 1-39, in
# table order (the suite's golden copy).
ms_expected_allow() {
  local root="$1" uid="$2" gid="$3" line
  while IFS= read -r line; do
    line="${line//@ROOT@/$root}"
    line="${line//@UID@/$uid}"
    printf '%s\n' "${line//@GID@/$gid}"
  done <<'EOF'
Bash(make:*)
Bash(RUN_IN_CONTAINER=1 make:*)
Bash(RUN_IN_CONTAINER=1 git commit:*)
Bash(RUN_IN_CONTAINER=1 git push:*)
Bash(git status:*)
Bash(git diff:*)
Bash(git log:*)
Bash(git add:*)
Bash(git commit:*)
Bash(git push:*)
Bash(git switch:*)
Bash(git fetch:*)
Bash(git rev-parse:*)
Bash(git merge-base:*)
Bash(git config --get core.hooksPath)
Bash(git config --local --get core.hooksPath)
Bash(git ls-files:*)
Bash(git remote get-url:*)
Bash(git check-ignore:*)
Bash(git branch --show-current)
Bash(gh:*)
Bash(bmalph implement)
Bash(bmalph run --driver claude-code --no-dashboard)
Bash(bmalph doctor:*)
Bash(bmalph --version)
Bash(@ROOT@/scripts/setup-preflight.sh:*)
Bash(@ROOT@/scripts/generate-profile.sh:*)
Bash(@ROOT@/scripts/validate-profile.sh:*)
Bash(@ROOT@/scripts/inject-governance.sh:*)
Bash(@ROOT@/scripts/merge-settings.sh:*)
Bash(@ROOT@/scripts/new-service.sh:*)
Bash(@ROOT@/scripts/stage-planning-artifacts.sh:*)
Bash(@ROOT@/scripts/ai-review-loop.sh:*)
Bash(@ROOT@/scripts/fr-nfr-gate.sh:*)
Bash(@ROOT@/scripts/get-pr-comments.sh:*)
Bash(@ROOT@/scripts/post-review-findings.sh:*)
Bash(@ROOT@/scripts/pr-state.sh:*)
Bash(@ROOT@/scripts/request-ai-reviews.sh:*)
Bash(@ROOT@/scripts/lib/common.sh:*)
Bash("@ROOT@/scripts/setup-preflight.sh":*)
Bash("@ROOT@/scripts/generate-profile.sh":*)
Bash("@ROOT@/scripts/validate-profile.sh":*)
Bash("@ROOT@/scripts/inject-governance.sh":*)
Bash("@ROOT@/scripts/merge-settings.sh":*)
Bash("@ROOT@/scripts/new-service.sh":*)
Bash("@ROOT@/scripts/stage-planning-artifacts.sh":*)
Bash("@ROOT@/scripts/ai-review-loop.sh":*)
Bash("@ROOT@/scripts/fr-nfr-gate.sh":*)
Bash("@ROOT@/scripts/get-pr-comments.sh":*)
Bash("@ROOT@/scripts/post-review-findings.sh":*)
Bash("@ROOT@/scripts/pr-state.sh":*)
Bash("@ROOT@/scripts/request-ai-reviews.sh":*)
Bash("@ROOT@/scripts/lib/common.sh":*)
Bash(docker info:*)
Bash(docker compose ps:*)
Bash(docker compose logs:*)
Bash(docker compose exec -T --user @UID@:@GID@ app cargo tree:*)
Bash(docker compose exec -T --user @UID@:@GID@ app cargo metadata:*)
Bash(docker compose exec -T --user @UID@:@GID@ app cargo xtask config-guard --list)
Bash(docker compose exec -T --user @UID@:@GID@ app env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)
Bash(docker compose exec -T --user @UID@:@GID@ app scripts/set-version.sh:*)
Bash(env -u DATABASE_URL scripts/with-env.sh .env .env.test -- cargo nextest run:*)
Bash(scripts/set-version.sh:*)
Bash(mkdir -p target/rust-sdlc/logs)
Bash(id -u)
Bash(id -g)
EOF
}

# ms_expected_deny — the 29 plugin-owned deny entries G1-G9, H1-H8, B1-B2
# and M1-M10, in table order (the suite's golden copy).
ms_expected_deny() {
  cat <<'EOF'
Bash(git commit *--no-verify*)
Bash(git commit * -n *)
Bash(git commit * -n)
Bash(git push *--force*)
Bash(git push * -f*)
Bash(git push *--no-verify*)
Bash(git push *--mirror*)
Bash(git push *--delete*)
Bash(git push * +*)
Bash(gh *approved-config-change*)
Bash(gh *approved-breaking-change*)
Bash(gh pr merge:*)
Bash(gh secret:*)
Bash(gh variable:*)
Bash(gh repo delete:*)
Bash(gh repo edit:*)
Bash(gh api *protection*)
Bash(bmalph reset:*)
Bash(bmalph implement *--force*)
Bash(make -*)
Bash(make *_CMD=*)
Bash(make *_FLAGS=*)
Bash(make *_ARGS=*)
Bash(make *CI_STAGES=*)
Bash(make *CONFIG_CHANGE_APPROVED=true*)
Bash(make * -i*)
Bash(make * -k*)
Bash(make * -n*)
Bash(make * -*)
EOF
}

# ms_list FILE KEY — the items of permissions.KEY of the JSON FILE, one per line.
ms_list() {
  python3 -I -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    doc = json.load(stream)
for item in doc["permissions"][sys.argv[2]]:
    print(item)' "$1" "$2"
}

# ms_sha FILE — sha256 of FILE.
ms_sha() {
  python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

# ms_mode FILE — permission bits of FILE in octal, e.g. 644.
ms_mode() {
  python3 -I -c 'import os, sys; print("%o" % (os.stat(sys.argv[1]).st_mode & 0o777))' "$1"
}

# ms_edit FILE OLD NEW — replace the one occurrence of OLD in FILE with NEW.
ms_edit() {
  python3 -I -c '
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit("ms_edit: %r occurs %d times in %s" % (old, text.count(old), path))
open(path, "w", encoding="utf-8").write(text.replace(old, new))' "$1" "$2" "$3"
}

# ms_tail_json IN OUT — OUT holds IN without its first line (the JSON after a
# REFUSED or INFO line).
ms_tail_json() {
  tail -n +2 "$1" >"$2"
}

# --- usage -----------------------------------------------------------------

@test "merge-settings: --help prints the header and exits 0" {
  run --separate-stderr "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "merge-settings.sh — "* ]]
  [[ "$output" == *"Usage: $USAGE"* ]]
  [[ "$output" == *"Exit: 0 success"*"; 1 refusal"*"; 2 usage error"* ]]
  [[ "$output" != *"set -euo pipefail"* ]]
  [ ! -e "$LOCAL" ]
}

@test "merge-settings: --help in any position wins over other arguments and writes nothing" {
  run --separate-stderr "$SCRIPT" --file shared --bogus "$REPO" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: $USAGE"* ]]
  [ ! -e "$LOCAL" ]
}

@test "merge-settings: an unknown flag exits 2 and writes nothing" {
  before="$(ms_sha "$SHARED")"
  run --separate-stderr "$SCRIPT" --force "$REPO"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"[rust-sdlc][ERROR] unknown argument: --force"* ]]
  [[ "$stderr" == *"usage: $USAGE"* ]]
  [ ! -e "$LOCAL" ]
  [ "$(ms_sha "$SHARED")" = "$before" ]
}

@test "merge-settings: --file without a value or with a value other than local or shared exits 2" {
  run --separate-stderr "$SCRIPT" "$REPO" --file
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--file needs a value"* ]]
  run --separate-stderr "$SCRIPT" --file --print "$REPO"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--file needs a value"* ]]
  run --separate-stderr "$SCRIPT" --file global "$REPO"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--file must be local or shared: global"* ]]
  [ -z "$output" ]
  [ ! -e "$LOCAL" ]
}

@test "merge-settings: a second TARGET_DIR exits 2 and a missing TARGET_DIR exits 1" {
  run --separate-stderr "$SCRIPT" "$REPO" "$REPO"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"unexpected argument: $REPO"* ]]
  run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR/no-such-repo"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"target directory not found: $BATS_TEST_TMPDIR/no-such-repo"* ]]
  [ ! -e "$LOCAL" ]
}

# --- the plugin-root entries (A8) -------------------------------------------------

@test "merge-settings: the plugin-root entries are the fixed 13 + 1 list in table order plus their 14 quoted variants" {
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ms_list "$LOCAL" allow | grep -F "$CLAUDE_PLUGIN_ROOT/" >"$BATS_TEST_TMPDIR/root-entries"
  {
    while IFS= read -r name; do
      printf 'Bash(%s/scripts/%s.sh:*)\n' "$CLAUDE_PLUGIN_ROOT" "$name"
    done < <(ms_names)
    printf 'Bash(%s/scripts/lib/common.sh:*)\n' "$CLAUDE_PLUGIN_ROOT"
    while IFS= read -r name; do
      printf 'Bash("%s/scripts/%s.sh":*)\n' "$CLAUDE_PLUGIN_ROOT" "$name"
    done < <(ms_names)
    printf 'Bash("%s/scripts/lib/common.sh":*)\n' "$CLAUDE_PLUGIN_ROOT"
  } >"$BATS_TEST_TMPDIR/expected-root-entries"
  diff -u "$BATS_TEST_TMPDIR/expected-root-entries" "$BATS_TEST_TMPDIR/root-entries"
  [ "$(wc -l <"$BATS_TEST_TMPDIR/root-entries")" -eq 28 ]
  # Rows 25-27 sit right after row 24 (`Bash(bmalph --version)`), at positions 26-53.
  ms_list "$LOCAL" allow | sed -n '26,53p' | diff -u "$BATS_TEST_TMPDIR/expected-root-entries" -
}

@test "merge-settings: the plugin-root list never depends on which scripts exist under the root" {
  "$SCRIPT" --print "$REPO" >"$BATS_TEST_TMPDIR/full.json"
  rm -rf "$CLAUDE_PLUGIN_ROOT/scripts"
  mkdir -p "$CLAUDE_PLUGIN_ROOT/scripts"
  printf '#!/usr/bin/env bash\n' >"$CLAUDE_PLUGIN_ROOT/scripts/extra-tool.sh"
  chmod 755 "$CLAUDE_PLUGIN_ROOT/scripts/extra-tool.sh"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+66 allow, +29 deny)" ]
  cmp "$LOCAL" "$BATS_TEST_TMPDIR/full.json"
  run ! grep -q extra-tool "$LOCAL"
}

@test "merge-settings: every plugin-root entry names an existing executable under the sandbox scripts/" {
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  count=0
  while IFS= read -r entry; do
    path="${entry#Bash(}"
    path="${path#\"}"
    path="${path%%.sh*}.sh"
    [[ "$path" == "$CLAUDE_PLUGIN_ROOT/scripts/"* ]]
    [ -f "$path" ]
    [ -x "$path" ]
    count=$((count + 1))
  done < <(ms_list "$LOCAL" allow | grep -F "$CLAUDE_PLUGIN_ROOT")
  [ "$count" -eq 28 ]
}

# --- the merged file ----------------------------------------------------------------

@test "merge-settings: a fresh local file gets the 66 allow and 29 deny entries in table order" {
  [ ! -e "$LOCAL" ]
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+66 allow, +29 deny)" ]
  ms_expected_allow "$CLAUDE_PLUGIN_ROOT" "$UID_NOW" "$GID_NOW" >"$BATS_TEST_TMPDIR/expected-allow"
  ms_expected_deny >"$BATS_TEST_TMPDIR/expected-deny"
  [ "$(wc -l <"$BATS_TEST_TMPDIR/expected-allow")" -eq 66 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/expected-deny")" -eq 29 ]
  ms_list "$LOCAL" allow | diff -u "$BATS_TEST_TMPDIR/expected-allow" -
  ms_list "$LOCAL" deny | diff -u "$BATS_TEST_TMPDIR/expected-deny" -
  python3 -I -c '
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert list(doc) == ["permissions"], list(doc)
assert list(doc["permissions"]) == ["allow", "deny"], list(doc["permissions"])' "$LOCAL"
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "merge-settings: the file is json.dumps with indent 2, ensure_ascii off and one trailing newline" {
  printf '{"permissions":{"allow":["Bash(echo café:*)"]},"note":"naïve ✓"}' >"$LOCAL"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+66 allow, +29 deny)" ]
  python3 -I -c '
import json, sys
raw = open(sys.argv[1], "rb").read()
doc = json.loads(raw.decode("utf-8"))
expected = (json.dumps(doc, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
assert raw == expected, "not the json.dumps form"
assert raw.endswith(b"}\n") and not raw.endswith(b"\n\n")
assert "café".encode() in raw and b"\\u00e9" not in raw
assert raw.startswith(b"{\n  \"permissions\": {\n    \"allow\": [\n      \"Bash(echo caf")' "$LOCAL"
  [ "$(ms_list "$LOCAL" allow | head -1)" = "Bash(echo café:*)" ]
}

@test "merge-settings: the allow and deny entries equal the Permissions Strategy tables of architecture.md" {
  if [[ ! -f "$ARCHITECTURE" ]]; then
    skip "architecture.md is not part of this checkout"
  fi
  python3 -I -c '
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
start = text.index("\n## Permissions Strategy\n")
end = text.index("\n## ", start + 1)
section = text[start:end]
allow_part = section[section.index("**Allow entries.**"):section.index("**Plugin-owned deny entries**")]
deny_part = section[section.index("**Plugin-owned deny entries**"):]
root, uid, gid = sys.argv[2:5]
names, allow = [], []
for line in allow_part.splitlines():
    match = re.match(r"\| (\d+) \| (.*?) \| ", line)
    if not match:
        continue
    items = re.findall(r"`([^`]+)`", match.group(2))
    names = [item for item in items if not item.startswith("Bash(")] or names
    for item in items:
        if not item.startswith("Bash("):
            continue
        for entry in ([item.replace("<name>", name) for name in names] if "<name>" in item else [item]):
            allow.append(entry.replace("<root>", root).replace("<uid>", uid).replace("<gid>", gid))
deny = re.findall(r"^\| [GHBM][0-9]+ \| `([^`]+)` \|", deny_part, re.M)
open(sys.argv[5], "w").write("".join(entry + "\n" for entry in allow))
open(sys.argv[6], "w").write("".join(entry + "\n" for entry in deny))' \
    "$ARCHITECTURE" "$CLAUDE_PLUGIN_ROOT" "$UID_NOW" "$GID_NOW" \
    "$BATS_TEST_TMPDIR/table-allow" "$BATS_TEST_TMPDIR/table-deny"
  [ "$(wc -l <"$BATS_TEST_TMPDIR/table-allow")" -eq 66 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/table-deny")" -eq 29 ]
  ms_expected_allow "$CLAUDE_PLUGIN_ROOT" "$UID_NOW" "$GID_NOW" | diff -u "$BATS_TEST_TMPDIR/table-allow" -
  ms_expected_deny | diff -u "$BATS_TEST_TMPDIR/table-deny" -
  "$SCRIPT" "$REPO" >/dev/null
  ms_list "$LOCAL" allow | diff -u "$BATS_TEST_TMPDIR/table-allow" -
  ms_list "$LOCAL" deny | diff -u "$BATS_TEST_TMPDIR/table-deny" -
}

@test "merge-settings: uid and gid are literals read from id -u and id -g" {
  mkdir -p "$BATS_TEST_TMPDIR/id-bin"
  printf '#!/usr/bin/env bash\ncase "$1" in -u) echo 4242 ;; -g) echo 4343 ;; *) exit 1 ;; esac\n' \
    >"$BATS_TEST_TMPDIR/id-bin/id"
  chmod 755 "$BATS_TEST_TMPDIR/id-bin/id"
  PATH="$BATS_TEST_TMPDIR/id-bin:$PATH" run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  ms_expected_allow "$CLAUDE_PLUGIN_ROOT" 4242 4343 | diff -u - <(ms_list "$LOCAL" allow)
  [ "$(ms_list "$LOCAL" allow | grep -cF -- '--user 4242:4343 app ')" -eq 5 ]
  [ "$(ms_list "$LOCAL" allow | grep -c -- '--user')" -eq 5 ]
  run ! grep -qF '$(id' "$LOCAL"
  run ! grep -qF '<uid>' "$LOCAL"
}

@test "merge-settings: a non-numeric id -u exits 1 and writes nothing" {
  mkdir -p "$BATS_TEST_TMPDIR/id-bin"
  printf '#!/usr/bin/env bash\necho nobody\n' >"$BATS_TEST_TMPDIR/id-bin/id"
  chmod 755 "$BATS_TEST_TMPDIR/id-bin/id"
  PATH="$BATS_TEST_TMPDIR/id-bin:$PATH" run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"id -u printed a non-numeric uid: nobody"* ]]
  [ ! -e "$LOCAL" ]
}

@test "merge-settings: TARGET_DIR defaults to the working directory" {
  cd "$REPO"
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+66 allow, +29 deny)" ]
  [ -f "$LOCAL" ]
}

# --- union semantics (AC-9.2 as amended) --------------------------------------------

@test "merge-settings: existing allow entries keep their order and only missing plugin entries are appended" {
  cat >"$LOCAL" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(npm test:*)",
      "Bash(gh:*)",
      "Bash(npm test:*)",
      "Bash(git status:*)",
      "WebFetch(domain:example.invalid)"
    ]
  }
}
EOF
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+64 allow, +29 deny)" ]
  {
    printf '%s\n' 'Bash(npm test:*)' 'Bash(gh:*)' 'Bash(npm test:*)' 'Bash(git status:*)' 'WebFetch(domain:example.invalid)'
    ms_expected_allow "$CLAUDE_PLUGIN_ROOT" "$UID_NOW" "$GID_NOW" | grep -vxF -e 'Bash(gh:*)' -e 'Bash(git status:*)'
  } >"$BATS_TEST_TMPDIR/expected-allow"
  ms_list "$LOCAL" allow | diff -u "$BATS_TEST_TMPDIR/expected-allow" -
  [ "$(ms_list "$LOCAL" allow | wc -l)" -eq 69 ]
  [ "$(ms_list "$LOCAL" allow | grep -cxF 'Bash(gh:*)')" -eq 1 ]
}

@test "merge-settings: existing deny entries are kept byte for byte and G1-M10 follow" {
  printf '%s\n' '{"permissions": {"deny": ["Read(./.env.local)", "Bash(git push --force:*)", "Bash(gh secret:*)", "Bash(rm -rf /:*)"]}}' >"$LOCAL"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+66 allow, +28 deny)" ]
  {
    printf '%s\n' 'Read(./.env.local)' 'Bash(git push --force:*)' 'Bash(gh secret:*)' 'Bash(rm -rf /:*)'
    ms_expected_deny | grep -vxF 'Bash(gh secret:*)'
  } >"$BATS_TEST_TMPDIR/expected-deny"
  ms_list "$LOCAL" deny | diff -u "$BATS_TEST_TMPDIR/expected-deny" -
  python3 -I -c '
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert list(doc["permissions"]) == ["deny", "allow"], list(doc["permissions"])' "$LOCAL"
}

@test "merge-settings: ask, hooks, env, defaultMode and every other key stay untouched" {
  cat >"$LOCAL" <<'EOF'
{
  "env": {"RUST_LOG": "debug", "DEPTH": 3},
  "permissions": {
    "ask": ["Bash(make purge:*)", "Bash(make down:*)"],
    "defaultMode": "default",
    "additionalDirectories": ["../shared"],
    "allow": ["Bash(make help:*)"]
  },
  "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "true"}]}]},
  "model": "opus",
  "enabledPlugins": {"x@y": true, "z@y": false},
  "cleanupPeriodDays": 30.5,
  "statusLine": null
}
EOF
  cp "$LOCAL" "$BATS_TEST_TMPDIR/before.json"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+66 allow, +29 deny)" ]
  python3 -I -c '
import json, sys
before = json.load(open(sys.argv[1], encoding="utf-8"))
after = json.load(open(sys.argv[2], encoding="utf-8"))
assert list(after) == list(before), (list(after), list(before))
for key in before:
    if key != "permissions":
        assert after[key] == before[key], key
assert list(after["permissions"]) == ["ask", "defaultMode", "additionalDirectories", "allow", "deny"], list(after["permissions"])
for key in ("ask", "defaultMode", "additionalDirectories"):
    assert after["permissions"][key] == before["permissions"][key], key
assert after["permissions"]["allow"][0] == "Bash(make help:*)"
assert type(after["env"]["DEPTH"]) is int and after["cleanupPeriodDays"] == 30.5' \
    "$BATS_TEST_TMPDIR/before.json" "$LOCAL"
}

@test "merge-settings: a second run is byte-identical and prints UNCHANGED" {
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  first="$(ms_sha "$LOCAL")"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "UNCHANGED: .claude/settings.local.json" ]
  [ "$(ms_sha "$LOCAL")" = "$first" ]
  run --separate-stderr "$SCRIPT" --with-qa-network "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'INFO: QA probes run through common.sh http_probe; no curl entry is written\nUNCHANGED: .claude/settings.local.json' ]
  [ "$(ms_sha "$LOCAL")" = "$first" ]
}

@test "merge-settings: a file that already holds every entry is left byte for byte, whatever its formatting" {
  "$SCRIPT" "$REPO" >/dev/null
  python3 -I -c '
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc, indent=4))' "$LOCAL"
  before="$(ms_sha "$LOCAL")"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "UNCHANGED: .claude/settings.local.json" ]
  [ "$(ms_sha "$LOCAL")" = "$before" ]
}

# --- what is never written (AC-9.3 as amended) ---------------------------------------

@test "merge-settings: no allow entry is Bash(bmalph:*) or contains curl, bypassPermissions, defaultMode or /*) after the plugin root" {
  run --separate-stderr "$SCRIPT" --with-qa-network "$REPO"
  [ "$status" -eq 0 ]
  ms_list "$LOCAL" allow >"$BATS_TEST_TMPDIR/allow"
  run ! grep -qxF 'Bash(bmalph:*)' "$BATS_TEST_TMPDIR/allow"
  run ! grep -qE 'curl|bypassPermissions|defaultMode' "$BATS_TEST_TMPDIR/allow"
  run ! grep -qE 'curl|bypassPermissions|defaultMode' "$LOCAL"
  run ! grep -qF '/*)' "$BATS_TEST_TMPDIR/allow"
  while IFS= read -r entry; do
    after_root="${entry#*"$CLAUDE_PLUGIN_ROOT"}"
    [[ "$after_root" != *'/*)'* ]]
    [[ "$after_root" == /scripts/*'.sh:*)' || "$after_root" == /scripts/*'.sh":*)' ]]
  done < <(grep -F "$CLAUDE_PLUGIN_ROOT" "$BATS_TEST_TMPDIR/allow")
  # The bmalph entries are the four exact forms of rows 21-24.
  grep '^Bash(bmalph' "$BATS_TEST_TMPDIR/allow" | diff -u - <(printf '%s\n' 'Bash(bmalph implement)' \
    'Bash(bmalph run --driver claude-code --no-dashboard)' 'Bash(bmalph doctor:*)' 'Bash(bmalph --version)')
  # Only deny entries end in a no-space `*`.
  run ! grep -E '[^ :]\*\)$' "$BATS_TEST_TMPDIR/allow"
}

@test "merge-settings: the script spells no P1-P7 construct outside a comment line that says never" {
  # NFR-5 for scripts/: the deny entries refuse these forms, so the script
  # builds them from variables instead of spelling them on one line.
  python3 -I -c '
import re, sys
patterns = [
    r"git (commit|push)\b.*(--no-verify|\s-n\b)",
    r"git push\b.*(--force|--force-with-lease|\s-f\b)",
    r"git -c core\.hooksPath",
    r"git config ((--local|--global) )?core\.hooksPath",
    r"bmalph implement.*--force",
    r"#\[allow|#\[mutants::skip\]|#\[coverage\(off\)\]|exclude_re|exclude_globs|--ignore-filename-regex",
    r"bypassPermissions",
]
bad = []
for number, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    if any(re.search(pattern, line) for pattern in patterns):
        if not (line.lstrip().startswith("#") and "never" in line):
            bad.append("%d: %s" % (number, line.rstrip()))
print("\n".join(bad))
sys.exit(1 if bad else 0)' "$SCRIPT"
}

@test "merge-settings: --with-qa-network adds nothing and prints the INFO line" {
  "$SCRIPT" --print "$REPO" >"$BATS_TEST_TMPDIR/plain.json"
  run --separate-stderr "$SCRIPT" --with-qa-network "$REPO"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$INFO" ]
  [ "${lines[1]}" = "WROTE: .claude/settings.local.json (+66 allow, +29 deny)" ]
  [ "${#lines[@]}" -eq 2 ]
  cmp "$LOCAL" "$BATS_TEST_TMPDIR/plain.json"
  run ! grep -q curl "$LOCAL"
  "$SCRIPT" --print --with-qa-network "$REPO" >"$OUT"
  [ "$(head -1 "$OUT")" = "$INFO" ]
  ms_tail_json "$OUT" "$BATS_TEST_TMPDIR/printed.json"
  cmp "$BATS_TEST_TMPDIR/printed.json" "$BATS_TEST_TMPDIR/plain.json"
}

@test "merge-settings: --print prints the merged JSON and writes nothing" {
  printf '{"permissions": {"allow": ["Bash(make help:*)"]}}\n' >"$LOCAL"
  before="$(ms_sha "$LOCAL")"
  "$SCRIPT" --print "$REPO" >"$OUT"
  [ "$(ms_sha "$LOCAL")" = "$before" ]
  [ "$(ms_list "$OUT" allow | head -1)" = "Bash(make help:*)" ]
  [ "$(ms_list "$OUT" allow | wc -l)" -eq 67 ]
  [ "$(ms_list "$OUT" deny | wc -l)" -eq 29 ]
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  cmp "$LOCAL" "$OUT"
  [ -z "$(find "$REPO/.claude" -name '.settings*' -print)" ]
}

# --- protected shared settings (AC-4.2, AC-9.1, D4) -----------------------------------------

@test "merge-settings: --file shared on the stub is refused, prints the merged JSON and leaves settings.json unchanged" {
  before="$(ms_sha "$SHARED")"
  "$SCRIPT" --file shared "$REPO" >"$OUT" && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
  [ "$(head -1 "$OUT")" = "REFUSED: .claude/settings.json is protected (protected-config.toml lists it); merged JSON follows" ]
  ms_tail_json "$OUT" "$BATS_TEST_TMPDIR/merged.json"
  # The merged JSON is the shared file plus the missing entries: the five
  # entries the template already allows are not repeated.
  [ "$(ms_list "$BATS_TEST_TMPDIR/merged.json" allow | wc -l)" -eq $(($(ms_list "$SHARED" allow | wc -l) + 61)) ]
  ms_list "$SHARED" allow | diff -u - <(ms_list "$BATS_TEST_TMPDIR/merged.json" allow | head -n "$(ms_list "$SHARED" allow | wc -l)")
  ms_list "$SHARED" deny | diff -u - <(ms_list "$BATS_TEST_TMPDIR/merged.json" deny | head -n 9)
  ms_list "$BATS_TEST_TMPDIR/merged.json" deny | tail -n 29 | diff -u <(ms_expected_deny) -
  [ "$(ms_sha "$SHARED")" = "$before" ]
  [ ! -e "$LOCAL" ]
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "merge-settings: settings.json keeps its checksum under every flag combination" {
  before="$(ms_sha "$SHARED")"
  for flags in '' '--print' '--with-qa-network' '--file local' '--file local --print' \
    '--print --with-qa-network' '--file shared' '--file shared --print' \
    '--file shared --with-qa-network' '--file shared --print --with-qa-network'; do
    # shellcheck disable=SC2086 # the flag words split on purpose
    run --separate-stderr "$SCRIPT" $flags "$REPO"
    case "$flags" in
      *shared*)
        [ "$status" -eq 1 ]
        [[ "$output" == *"REFUSED: .claude/settings.json is protected (protected-config.toml lists it); merged JSON follows"* ]]
        ;;
      *) [ "$status" -eq 0 ] ;;
    esac
    [ "$(ms_sha "$SHARED")" = "$before" ]
  done
  # Default mode wrote only the local file.
  [ -f "$LOCAL" ]
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "merge-settings: --file shared is refused when a listed directory holds .claude/settings.json" {
  ms_edit "$REPO/protected-config.toml" '    ".claude/settings.json",'$'\n' ''
  ms_edit "$REPO/protected-config.toml" $'\ndirectories = [' $'\ndirectories = [".claude/", '
  before="$(ms_sha "$SHARED")"
  run --separate-stderr "$SCRIPT" --file shared "$REPO"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "REFUSED: .claude/settings.json is protected (protected-config.toml lists it); merged JSON follows" ]
  [ "${lines[1]}" = "{" ]
  [ "$(ms_sha "$SHARED")" = "$before" ]
  ms_edit "$REPO/protected-config.toml" $'\ndirectories = [".claude/", ' $'\ndirectories = ["./.claude", '
  run --separate-stderr "$SCRIPT" --file shared "$REPO"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "REFUSED: .claude/settings.json is protected (protected-config.toml lists it); merged JSON follows" ]
  [ "$(ms_sha "$SHARED")" = "$before" ]
}

@test "merge-settings: --file shared is refused with the unparseable form when protected-config.toml is malformed" {
  before="$(ms_sha "$SHARED")"
  printf 'files = [\n' >"$REPO/protected-config.toml"
  "$SCRIPT" --file shared "$REPO" >"$OUT" && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
  [ "$(head -1 "$OUT")" = "REFUSED: .claude/settings.json is protected (protected-config.toml unparseable); merged JSON follows" ]
  ms_tail_json "$OUT" "$BATS_TEST_TMPDIR/merged.json"
  ms_list "$BATS_TEST_TMPDIR/merged.json" deny | tail -n 29 | diff -u <(ms_expected_deny) -
  [ "$(ms_sha "$SHARED")" = "$before" ]
  # A `files` value that is not an array of strings fails closed the same way.
  printf 'files = ".claude/settings.json"\n' >"$REPO/protected-config.toml"
  run --separate-stderr "$SCRIPT" --file shared --print "$REPO"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "REFUSED: .claude/settings.json is protected (protected-config.toml unparseable); merged JSON follows" ]
  [ "$(ms_sha "$SHARED")" = "$before" ]
}

@test "merge-settings: --file shared writes settings.json when protected-config.toml does not list it or is absent" {
  cp "$SHARED" "$BATS_TEST_TMPDIR/shared-orig.json"
  ms_edit "$REPO/protected-config.toml" '    ".claude/settings.json",'$'\n' ''
  run --separate-stderr "$SCRIPT" --file shared "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.json (+61 allow, +29 deny)" ]
  ms_list "$BATS_TEST_TMPDIR/shared-orig.json" ask | diff -u - <(ms_list "$SHARED" ask)
  python3 -I -c '
import json, sys
before = json.load(open(sys.argv[1], encoding="utf-8"))
after = json.load(open(sys.argv[2], encoding="utf-8"))
assert after["hooks"] == before["hooks"]
assert after["permissions"]["allow"][: len(before["permissions"]["allow"])] == before["permissions"]["allow"]
assert after["permissions"]["deny"][: len(before["permissions"]["deny"])] == before["permissions"]["deny"]' \
    "$BATS_TEST_TMPDIR/shared-orig.json" "$SHARED"
  [ ! -e "$LOCAL" ]
  run --separate-stderr "$SCRIPT" --file shared "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "UNCHANGED: .claude/settings.json" ]
  cp "$BATS_TEST_TMPDIR/shared-orig.json" "$SHARED"
  rm "$REPO/protected-config.toml"
  run --separate-stderr "$SCRIPT" --file shared "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.json (+61 allow, +29 deny)" ]
}

# --- the local file must be git-ignored ----------------------------------------------------

@test "merge-settings: a local file that is not git-ignored is refused and --print still prints the merged JSON" {
  ms_edit "$REPO/.gitignore" $'.claude/settings.local.json\n' ''
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [ "$output" = "REFUSED: .claude/settings.local.json is not git-ignored" ]
  [ ! -e "$LOCAL" ]
  "$SCRIPT" --print "$REPO" >"$OUT"
  [ ! -e "$LOCAL" ]
  [ "$(ms_list "$OUT" allow | wc -l)" -eq 66 ]
  [ "$(ms_list "$OUT" deny | wc -l)" -eq 29 ]
  printf '{}\n' >"$LOCAL"
  before="$(ms_sha "$LOCAL")"
  run --separate-stderr "$SCRIPT" --with-qa-network "$REPO"
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "REFUSED: .claude/settings.local.json is not git-ignored" ]
  [ "$(ms_sha "$LOCAL")" = "$before" ]
}

@test "merge-settings: a target outside a git work tree is refused as not git-ignored" {
  export GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/plain/.claude"
  run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 1 ]
  [ "$output" = "REFUSED: .claude/settings.local.json is not git-ignored" ]
  [ ! -e "$BATS_TEST_TMPDIR/plain/.claude/settings.local.json" ]
}

@test "merge-settings: a tracked settings.local.json is refused as not git-ignored" {
  printf '{}\n' >"$LOCAL"
  git -C "$REPO" add -f .claude/settings.local.json
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [ "$output" = "REFUSED: .claude/settings.local.json is not git-ignored" ]
  [ "$(cat "$LOCAL")" = "{}" ]
}

# --- refusals and limits ---------------------------------------------------------------------

@test "merge-settings: malformed existing JSON exits 1 and the file is unchanged" {
  printf '{"permissions": {"allow": ["Bash(make:*)",' >"$LOCAL"
  before="$(ms_sha "$LOCAL")"
  for flags in '' '--print' '--with-qa-network'; do
    # shellcheck disable=SC2086 # the flag words split on purpose
    run --separate-stderr "$SCRIPT" $flags "$REPO"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"[rust-sdlc][ERROR] .claude/settings.local.json is not valid JSON"* ]]
    [[ "$output" != *"{"* ]]
    [ "$(ms_sha "$LOCAL")" = "$before" ]
  done
  : >"$LOCAL"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [ ! -s "$LOCAL" ]
  printf '{"a": "\xff"}' >"$LOCAL"
  before="$(ms_sha "$LOCAL")"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [ "$(ms_sha "$LOCAL")" = "$before" ]
  [ -z "$(find "$REPO/.claude" -name '.settings*' -print)" ]
}

@test "merge-settings: NaN, Infinity and a number that overflows to infinity are malformed JSON, exit 1 and leave the file unchanged" {
  for doc in '{"x": NaN}' '{"x": Infinity}' '{"x": -Infinity}' '{"x": 1e400}' '{"cleanupPeriodDays": -1e400}'; do
    printf '%s\n' "$doc" >"$LOCAL"
    before="$(ms_sha "$LOCAL")"
    for flags in '' '--print'; do
      # shellcheck disable=SC2086 # the flag words split on purpose
      run --separate-stderr "$SCRIPT" $flags "$REPO"
      [ "$status" -eq 1 ]
      [[ "$stderr" == *"[rust-sdlc][ERROR] .claude/settings.local.json is not valid JSON"* ]]
      [[ "$output" != *"{"* ]]
      [[ "$output" != *"WROTE"* ]]
      [ "$(ms_sha "$LOCAL")" = "$before" ]
    done
  done
  [ -z "$(find "$REPO/.claude" -name '.settings*' -print)" ]
  # A finite number is still a number: it is kept and the file stays JSON.parse-able.
  printf '{"x": 1.5, "y": -2e3}\n' >"$LOCAL"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+66 allow, +29 deny)" ]
  python3 -I -c '
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"), parse_constant=lambda name: sys.exit("constant " + name))
assert doc["x"] == 1.5 and doc["y"] == -2000.0, doc
text = open(sys.argv[1], encoding="utf-8").read()
assert "NaN" not in text and "Infinity" not in text' "$LOCAL"
}

@test "merge-settings: a non-regular settings file (directory or FIFO) exits 1 and nothing is written" {
  mkdir "$LOCAL"
  for flags in '' '--print'; do
    # shellcheck disable=SC2086 # the flag words split on purpose
    run --separate-stderr "$SCRIPT" $flags "$REPO"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"it is not a regular file"* ]]
    [[ "$output" != *"{"* ]]
    [ -d "$LOCAL" ]
    [ -z "$(find "$LOCAL" -mindepth 1 -print)" ]
    [ -z "$(find "$REPO/.claude" -name '.settings*' -print)" ]
  done
  rmdir "$LOCAL"
  mkfifo "$LOCAL"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"it is not a regular file"* ]]
  [ -p "$LOCAL" ]
  [ -z "$(find "$REPO/.claude" -name '.settings*' -print)" ]
  rm "$SHARED"
  mkdir "$SHARED"
  run --separate-stderr "$SCRIPT" --file shared "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"it is not a regular file"* ]]
  [ -d "$SHARED" ]
  [ -z "$(find "$SHARED" -mindepth 1 -print)" ]
}

@test "merge-settings: a non-object document, a non-object permissions or a non-array allow exits 1 unchanged" {
  for doc in '[]' '"text"' '{"permissions": []}' '{"permissions": {"allow": "Bash(make:*)"}}' \
    '{"permissions": {"deny": {"x": 1}}}'; do
    printf '%s\n' "$doc" >"$LOCAL"
    before="$(ms_sha "$LOCAL")"
    run --separate-stderr "$SCRIPT" "$REPO"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"the file is left unchanged"* ]]
    [ "$(ms_sha "$LOCAL")" = "$before" ]
  done
}

@test "merge-settings: a symlinked settings.local.json exits 1 and the link target is unchanged" {
  printf '{}\n' >"$BATS_TEST_TMPDIR/elsewhere.json"
  ln -s "$BATS_TEST_TMPDIR/elsewhere.json" "$LOCAL"
  for flags in '' '--print'; do
    # shellcheck disable=SC2086 # the flag words split on purpose
    run --separate-stderr "$SCRIPT" $flags "$REPO"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"symbolic link"* ]]
    [ -L "$LOCAL" ]
    [ "$(cat "$BATS_TEST_TMPDIR/elsewhere.json")" = "{}" ]
  done
  rm "$SHARED"
  ln -s "$BATS_TEST_TMPDIR/elsewhere.json" "$SHARED"
  run --separate-stderr "$SCRIPT" --file shared "$REPO"
  [ "$status" -eq 1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/elsewhere.json")" = "{}" ]
}

@test "merge-settings: a symlinked .claude directory exits 1 and nothing is written through it" {
  mv "$REPO/.claude" "$BATS_TEST_TMPDIR/real-claude"
  ln -s "$BATS_TEST_TMPDIR/real-claude" "$REPO/.claude"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"symbolic link"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/real-claude/settings.local.json" ]
}

@test "merge-settings: a CLAUDE_PLUGIN_ROOT that is not a directory or holds a wildcard exits 1" {
  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/no-such-plugin" run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"CLAUDE_PLUGIN_ROOT is not a directory: $BATS_TEST_TMPDIR/no-such-plugin"* ]]
  [ ! -e "$LOCAL" ]
  mkdir -p "$BATS_TEST_TMPDIR/wild*card"
  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/wild*card" run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"refusing a plugin root"* ]]
  [ ! -e "$LOCAL" ]
}

@test "merge-settings: an existing file keeps its mode and no temporary file is left behind" {
  printf '{}\n' >"$LOCAL"
  chmod 600 "$LOCAL"
  run --separate-stderr "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(ms_mode "$LOCAL")" = 600 ]
  [ -z "$(find "$REPO/.claude" -name '.settings*' -print)" ]
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "merge-settings: every run finishes within 5 seconds" {
  SECONDS=0
  "$SCRIPT" "$REPO" >/dev/null
  [ "$SECONDS" -le 5 ]
  SECONDS=0
  "$SCRIPT" "$REPO" >/dev/null
  [ "$SECONDS" -le 5 ]
  SECONDS=0
  "$SCRIPT" --print --with-qa-network "$REPO" >/dev/null
  [ "$SECONDS" -le 5 ]
  SECONDS=0
  run "$SCRIPT" --file shared "$REPO"
  [ "$status" -eq 1 ]
  [ "$SECONDS" -le 5 ]
  printf '{' >"$LOCAL"
  SECONDS=0
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [ "$SECONDS" -le 5 ]
}

# --- setup order (AC-4.3, NFR-1, A11) ------------------------------------------------------------

@test "merge-settings: setup order: generate-profile, inject-governance and merge-settings, committed and run again, change nothing" {
  [ ! -e "$REPO/.claude/rust-sdlc.yml" ]
  run --separate-stderr "$PLUGIN_ROOT/scripts/generate-profile.sh" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/rust-sdlc.yml" ]
  run --separate-stderr "$PLUGIN_ROOT/scripts/inject-governance.sh" "$REPO"
  [ "$status" -eq 0 ]
  run --separate-stderr "$PLUGIN_ROOT/scripts/merge-settings.sh" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "WROTE: .claude/settings.local.json (+66 allow, +29 deny)" ]
  git -C "$REPO" add -A && git -C "$REPO" commit -q -m 'chore(#1): set up the rust-backend-sdlc plugin'
  [ -z "$(git -C "$REPO" ls-files -- .claude/settings.local.json)" ]
  git -C "$REPO" check-ignore -q .claude/settings.local.json
  [ -n "$(git -C "$REPO" ls-files -- .claude/rust-sdlc.yml)" ]
  local_sha="$(ms_sha "$LOCAL")"
  for script in generate-profile inject-governance merge-settings; do
    run --separate-stderr "$PLUGIN_ROOT/scripts/$script.sh" "$REPO"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 1 ]
    for line in "${lines[@]}"; do
      [[ "$line" == "UNCHANGED: "* ]]
    done
  done
  [ -z "$(git -C "$REPO" status --porcelain)" ]
  [ "$(ms_sha "$LOCAL")" = "$local_sha" ]
}
