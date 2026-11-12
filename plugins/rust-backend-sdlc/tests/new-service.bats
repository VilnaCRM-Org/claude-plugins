#!/usr/bin/env bats
# new-service.bats — cases of scripts/new-service.sh and config/new-service.defaults.json
# (FR-12, FR-13, AC-12.1 to AC-12.6, AC-13.1, AC-13.2, D17, D18).
#
# Hermetic: the gh stub answers from a routes file (STUB_GH_STRICT=1, so an unexpected
# call fails), `repo clone` copies the runtime template checkout $BATS_TEST_TMPDIR/template,
# a suite-local git wrapper logs the script's git calls, every write lands under
# $BATS_TEST_TMPDIR and the configuration is a test file with poll_interval_seconds 0.
# The template slug of the shipped configuration is read from that file at runtime and
# never written here.
#
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2030,SC2031 # golden diffs hold literal backticks; bats cases are subshells

bats_require_minimum_version 1.5.0

setup() {
  load lib/helpers
  common_setup
  NS="$PLUGIN_ROOT/scripts/new-service.sh"
  TPL="$BATS_TEST_TMPDIR/template"
  CO="$BATS_TEST_TMPDIR/billing-service"
  RECORD="$CO/target/rust-sdlc/new-service/source.json"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  ns_config "$BATS_TEST_TMPDIR/defaults.json"
  export RUST_SDLC_CONFIG_FILE="$BATS_TEST_TMPDIR/defaults.json"
  unset RUST_SDLC_TEMPLATE_REPO
  ns_git_wrapper
  ROUTES_DIR="$BATS_TEST_TMPDIR/gh-routes"
  mkdir -p "$ROUTES_DIR"
  : >"$ROUTES_DIR/routes"
  export STUB_GH_ROUTES="$ROUTES_DIR/routes" STUB_GH_STRICT=1 STUB_GH_CLONE_SOURCE="$TPL"
}

teardown() {
  # Permission cases leave read-only files behind; make the test directory removable.
  chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# --- suite-local helpers ----------------------------------------------------------------

# ns_config FILE [SLUG] [VISIBILITY] [VERSION] [ATTEMPTS] [INTERVAL] — a defaults file.
ns_config() {
  printf '{\n  "template_repository": "%s",\n  "default_visibility": "%s",\n  "default_version": "%s",\n  "poll_attempts": %s,\n  "poll_interval_seconds": %s\n}\n' \
    "${2:-acme/rust-template}" "${3:-private}" "${4:-0.1.0}" "${5:-3}" "${6:-0}" >"$1"
}

# ns_git_wrapper — a `git` that logs `git <argv>` to $NS_GIT_LOG and runs the real git.
# Calls made by the gh stub's clone emulation (its fixed committer date) are not logged:
# they are the stub's, not the script's.
ns_git_wrapper() {
  local real
  real="$(type -P git)"
  NS_GIT_BIN="$BATS_TEST_TMPDIR/git-bin"
  NS_GIT_LOG="$BATS_TEST_TMPDIR/stub-logs/git.log"
  mkdir -p "$NS_GIT_BIN"
  : >"$NS_GIT_LOG"
  cat >"$NS_GIT_BIN/git" <<EOF
#!/usr/bin/env bash
if [[ "\${GIT_COMMITTER_DATE:-}" != 2026-01-01T00:00:00Z ]]; then
  printf 'git %s\n' "\$*" >>"$NS_GIT_LOG"
fi
exec "$real" "\$@"
EOF
  chmod +x "$NS_GIT_BIN/git"
}

# ns_run ARG... — the script with the git wrapper first on PATH; stdout in $output,
# stderr in $stderr.
ns_run() {
  run --separate-stderr env "PATH=$NS_GIT_BIN:$PATH" "$NS" "$@"
}

# ns_route GLOB EXIT [STDOUT] — one gh stub route.
ns_route() {
  local n
  n="$(wc -l <"$ROUTES_DIR/routes" | tr -d ' ')"
  if (($# > 2)); then
    printf '%s\n' "$3" >"$ROUTES_DIR/out$n"
    printf '%s\t%s\tout%s\n' "$1" "$2" "$n" >>"$ROUTES_DIR/routes"
  else
    printf '%s\t%s\t-\n' "$1" "$2" >>"$ROUTES_DIR/routes"
  fi
}

# ns_routes IS_TEMPLATE EXISTS [COMMITS] — the gh routes of acme/billing-service created
# from acme/rust-template (login acme).
ns_routes() {
  ns_route 'api user --jq .login' 0 acme
  ns_route 'auth status' 0
  ns_route 'api repos/acme/rust-template --jq .is_template' 0 "$1"
  if [[ "$2" == 1 ]]; then
    ns_route 'repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner' 0 acme/billing-service
  else
    ns_route 'repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner' 1
  fi
  ns_route 'repo create acme/billing-service --template acme/rust-template --private' 0 https://github.com/acme/billing-service
  ns_route 'repo create acme/billing-service --private' 0 https://github.com/acme/billing-service
  ns_route 'api repos/acme/billing-service/commits?per_page=1 --jq length' 0 "${3:-1}"
  ns_route 'repo clone acme/billing-service *' 0
  ns_route 'repo clone acme/rust-template * -- --depth 1' 0
}

# ns_reroute IS_TEMPLATE EXISTS — replace the routes.
ns_reroute() {
  : >"$ROUTES_DIR/routes"
  ns_routes "$@"
}

# ns_template — the template checkout at $TPL (origin acme/rust-template), with the
# xtask entry point and a LICENSE the stub tree lacks, as in the real template.
ns_template() {
  rr_materialize "$TPL" acme/rust-template
  mkdir -p "$TPL/xtask/src"
  printf 'fn main() {}\n' >"$TPL/xtask/src/main.rs"
  printf 'CC0 1.0 Universal\n' >"$TPL/LICENSE"
  git -C "$TPL" add -A
  git -C "$TPL" commit -q -m 'chore: add the xtask entry point and the licence'
}

# ns_source — phase source of the template flow into $CO (the template is created first
# when absent).
ns_source() {
  [[ -d "$TPL" ]] || ns_template
  ns_reroute true 0
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --phase source
  if [[ "$status" -ne 0 ]]; then
    printf 'phase source failed (%s)\n%s\n%s\n' "$status" "$output" "$stderr" >&2
    return 1
  fi
}

# ns_customize ARG... — phase customize of $CO as acme/billing-service.
ns_customize() {
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --phase customize "$@"
}

# ns_golden REL — the diff of $CO/REL against the clone's commit, without the file header.
ns_golden() {
  diff -U0 <(git -C "$CO" show "HEAD:$1") "$CO/$1" | tail -n +3
}

# ns_tree DIR — a listing of every path and file checksum under DIR (without .git).
ns_tree() {
  (
    cd "$1" || exit 1
    find . -path ./.git -prune -o -print | LC_ALL=C sort
    find . -path ./.git -prune -o -type f -exec cksum {} + | LC_ALL=C sort
  )
}

# ns_md_set — the Markdown files docs-check reads in $CO (tracked, present, minus
# CHANGELOG.md and specs/**).
ns_md_set() {
  local file
  git -C "$CO" ls-files '*.md' | grep -vxE 'CHANGELOG\.md|specs/.*' | while IFS= read -r file; do
    if [[ -f "$CO/$file" ]]; then
      printf '%s\n' "$file"
    fi
  done
}

# ns_rule3 — the rule-3 findings of docs_rules over the Markdown set of $CO.
ns_rule3() {
  local files
  mapfile -t files < <(ns_md_set)
  docs_rules --root "$CO" "${files[@]}" | grep '^(3) ' || true
}

# ns_only PATTERN — every stdout line matches the extended regex PATTERN.
ns_only() {
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! [[ "$line" =~ $1 ]]; then
      printf 'unexpected line: %s\n' "$line" >&2
      return 1
    fi
  done <<<"$output"
}

# ns_shipped_slug — template_repository of the shipped configuration.
ns_shipped_slug() {
  python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["template_repository"])' \
    "$PLUGIN_ROOT/config/new-service.defaults.json"
}

# --- usage -------------------------------------------------------------------------------

@test "new-service: --help prints the header and exits 0 in any position" {
  ns_run --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: new-service.sh --name <n>"* ]]
  [[ "$output" == *"Exit: 0 success; 1 failure or refusal; 2 usage error"* ]]
  ns_run --name billing-service --visibility nope --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: new-service.sh"* ]]
  [ "$(wc -l <"$STUB_GH_LOG")" -eq 0 ]
}

@test "new-service: an unknown flag exits 2" {
  ns_run --name billing-service --bogus
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[rust-sdlc][ERROR] unknown argument: --bogus"* ]]
  [[ "$output" != *SUMMARY* ]]
}

@test "new-service: a missing --name or a flag without a value exits 2" {
  ns_run --owner acme
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--name is required"* ]]
  ns_run --name
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--name needs a value"* ]]
  ns_run --name billing-service --owner --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--owner needs a value"* ]]
}

# --- configuration (FR-13, AC-13.1, AC-13.2) -------------------------------------------------

@test "new-service: the shipped defaults file holds exactly the five keys with valid values" {
  run python3 -I -c '
import json, re, sys
d = json.load(open(sys.argv[1]))
assert sorted(d) == ["default_version", "default_visibility", "poll_attempts", "poll_interval_seconds", "template_repository"], sorted(d)
assert re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", d["template_repository"])
assert d["default_visibility"] == "private" and d["default_version"] == "0.1.0"
assert d["poll_attempts"] == 10 and d["poll_interval_seconds"] == 3
' "$PLUGIN_ROOT/config/new-service.defaults.json"
  [ "$status" -eq 0 ]
}

@test "new-service: --template wins over RUST_SDLC_TEMPLATE_REPO and RUST_SDLC_CONFIG_FILE" {
  ns_config "$BATS_TEST_TMPDIR/alt.json" acme/config-template
  ns_route 'api repos/acme/flag-template --jq .is_template' 0 true
  ns_route 'repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner' 1
  RUST_SDLC_CONFIG_FILE="$BATS_TEST_TMPDIR/alt.json" RUST_SDLC_TEMPLATE_REPO=acme/env-template \
    ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --template acme/flag-template --dry-run
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$STUB_GH_LOG")" = "gh api repos/acme/flag-template --jq .is_template" ]
  [[ "$output" == *"--template acme/flag-template --private"* ]]
}

@test "new-service: RUST_SDLC_TEMPLATE_REPO wins over RUST_SDLC_CONFIG_FILE" {
  ns_config "$BATS_TEST_TMPDIR/alt.json" acme/config-template
  ns_route 'api repos/acme/env-template --jq .is_template' 0 true
  ns_route 'repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner' 1
  RUST_SDLC_CONFIG_FILE="$BATS_TEST_TMPDIR/alt.json" RUST_SDLC_TEMPLATE_REPO=acme/env-template \
    ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$STUB_GH_LOG")" = "gh api repos/acme/env-template --jq .is_template" ]
}

@test "new-service: RUST_SDLC_CONFIG_FILE wins over the shipped defaults file" {
  ns_config "$BATS_TEST_TMPDIR/alt.json" acme/config-template
  ns_route 'api repos/acme/config-template --jq .is_template' 0 true
  ns_route 'repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner' 1
  RUST_SDLC_CONFIG_FILE="$BATS_TEST_TMPDIR/alt.json" \
    ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$STUB_GH_LOG")" = "gh api repos/acme/config-template --jq .is_template" ]
}

@test "new-service: without an override the shipped template slug is probed through resolve_plugin_root" {
  local slug
  slug="$(ns_shipped_slug)"
  unset RUST_SDLC_CONFIG_FILE
  ns_route "api repos/$slug --jq .is_template" 0 true
  ns_route 'repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner' 1
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$STUB_GH_LOG")" = "gh api repos/$slug --jq .is_template" ]
  # CLAUDE_PLUGIN_ROOT, when set, is the plugin root that holds the configuration.
  : >"$STUB_GH_LOG"
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$STUB_GH_LOG")" = "gh api repos/$slug --jq .is_template" ]
}

@test "new-service: a malformed configuration exits 2 naming the file, the key and the reason" {
  local cfg="$BATS_TEST_TMPDIR/bad.json" body key
  local -a cases=(
    'template_repository|{"template_repository": "acme/a", "default_visibility": "private", "default_version": "0.1.0", "poll_attempts": 3, "poll_interval_seconds": 0, "extra": 1}|extra: unknown key'
    'template_repository|{"template_repository": "not a slug", "default_visibility": "private", "default_version": "0.1.0", "poll_attempts": 3, "poll_interval_seconds": 0}|template_repository: not an owner/name slug'
    'default_visibility|{"template_repository": "acme/a", "default_visibility": "internal", "default_version": "0.1.0", "poll_attempts": 3, "poll_interval_seconds": 0}|default_visibility: not one of private public'
    'default_version|{"template_repository": "acme/a", "default_visibility": "private", "default_version": "0.1", "poll_attempts": 3, "poll_interval_seconds": 0}|default_version: not a MAJOR.MINOR.PATCH version'
    'poll_attempts|{"template_repository": "acme/a", "default_visibility": "private", "default_version": "0.1.0", "poll_attempts": 0, "poll_interval_seconds": 0}|poll_attempts: 0 is outside 1-60'
    'poll_attempts|{"template_repository": "acme/a", "default_visibility": "private", "default_version": "0.1.0", "poll_attempts": 61, "poll_interval_seconds": 0}|poll_attempts: 61 is outside 1-60'
    'poll_attempts|{"template_repository": "acme/a", "default_visibility": "private", "default_version": "0.1.0", "poll_attempts": "3", "poll_interval_seconds": 0}|poll_attempts: not an integer'
    'poll_interval_seconds|{"template_repository": "acme/a", "default_visibility": "private", "default_version": "0.1.0", "poll_attempts": 3, "poll_interval_seconds": 61}|poll_interval_seconds: 61 is outside 0-60'
    'poll_interval_seconds|{"template_repository": "acme/a", "default_visibility": "private", "default_version": "0.1.0", "poll_attempts": 3, "poll_interval_seconds": true}|poll_interval_seconds: not an integer'
    'missing|{"template_repository": "acme/a", "default_visibility": "private", "default_version": "0.1.0", "poll_attempts": 3}|poll_interval_seconds: missing'
    'json|{"template_repository": "acme/a",|(document): '
    'array|["acme/a"]|(document): not a JSON object'
  )
  for body in "${cases[@]}"; do
    key="${body%%|*}"
    body="${body#*|}"
    printf '%s\n' "${body%|*}" >"$cfg"
    RUST_SDLC_CONFIG_FILE="$cfg" ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --dry-run
    [ "$status" -eq 2 ] || { echo "case $key: status $status" >&2; return 1; }
    [[ "$stderr" == *"[rust-sdlc][ERROR] malformed $cfg: ${body##*|}"* ]] || { echo "case $key: $stderr" >&2; return 1; }
  done
  [ "$(wc -l <"$STUB_GH_LOG")" -eq 0 ]
  RUST_SDLC_CONFIG_FILE="$BATS_TEST_TMPDIR/absent.json" ns_run --name billing-service --owner acme --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed $BATS_TEST_TMPDIR/absent.json: (file): "* ]]
}

@test "new-service: a malformed RUST_SDLC_TEMPLATE_REPO or --template exits 2" {
  RUST_SDLC_TEMPLATE_REPO='not a slug' ns_run --name billing-service --owner acme --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed RUST_SDLC_TEMPLATE_REPO"* ]]
  ns_run --name billing-service --owner acme --template 'acme' --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--template must be owner/repo"* ]]
  [ "$(wc -l <"$STUB_GH_LOG")" -eq 0 ]
}

@test "new-service: the template slug appears in no file under skills commands agents scripts workflows" {
  local slug dir
  slug="$(ns_shipped_slug)"
  [ -n "$slug" ]
  for dir in skills commands agents scripts workflows; do
    [[ -d "$PLUGIN_ROOT/$dir" ]] || continue
    run grep -rliF -- "$slug" "$PLUGIN_ROOT/$dir"
    [ "$status" -eq 1 ] || { echo "slug found: $output" >&2; return 1; }
  done
}

# --- validation (AC-12.6) -------------------------------------------------------------------

@test "new-service: --name must be kebab-case and at most 50 characters" {
  local name
  for name in Billing billing_service -billing billing- 1billing "billing service" "$(printf 'a%.0s' {1..51})"; do
    ns_run --name "$name" --owner acme --dry-run
    [ "$status" -eq 2 ] || { echo "accepted --name $name" >&2; return 1; }
    [[ "$stderr" == *"--name must be kebab-case and at most 50 characters"* ]]
  done
  ns_route 'api repos/acme/rust-template --jq .is_template' 0 true
  ns_route 'repo view acme/* --json nameWithOwner --jq .nameWithOwner' 1
  ns_run --name "$(printf 'a%.0s' {1..50})" --owner acme --dest "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
}

@test "new-service: --description and --intro must be one line of at most 200 characters without control characters" {
  local flag
  for flag in --description --intro; do
    ns_run --name billing-service --owner acme "$flag" $'first\nsecond' --dry-run
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"$flag must be a single line"* ]]
    ns_run --name billing-service --owner acme "$flag" $'tab\there' --dry-run
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"$flag must not contain control characters"* ]]
    ns_run --name billing-service --owner acme "$flag" "$(printf 'x%.0s' {1..201})" --dry-run
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"$flag must be at most 200 characters"* ]]
  done
  ns_route 'api repos/acme/rust-template --jq .is_template' 0 true
  ns_route 'repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner' 1
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" \
    --description "$(printf 'x%.0s' {1..200})" --intro 'Fakturierung für Acme — ünïcödé' --dry-run
  [ "$status" -eq 0 ]
}

@test "new-service: --owner, --version and the enums are validated" {
  ns_run --name billing-service --owner -acme --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--owner is not a GitHub owner name"* ]]
  ns_run --name billing-service --owner "acme/x" --dry-run
  [ "$status" -eq 2 ]
  ns_run --name billing-service --owner "$(printf 'a%.0s' {1..40})" --dry-run
  [ "$status" -eq 2 ]
  ns_run --name billing-service --owner acme --version 1.0 --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--version must be MAJOR.MINOR.PATCH"* ]]
  ns_run --name billing-service --owner acme --version 01.0.0 --dry-run
  [ "$status" -eq 2 ]
  ns_run --name billing-service --owner acme --visibility internal --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--visibility must be private or public"* ]]
  ns_run --name billing-service --owner acme --sync-flavour both --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--sync-flavour must be app or pat"* ]]
  ns_run --name billing-service --owner acme --phase build --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--phase must be source, customize or all"* ]]
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR/absent" --dry-run
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--dest is not a directory"* ]]
  [ "$(wc -l <"$STUB_GH_LOG")" -eq 0 ]
}

@test "new-service: two source flags exit 2" {
  ns_template
  ns_run --name billing-service --template acme/rust-template --template-path "$TPL"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--template, --template-path and --in-place are mutually exclusive"* ]]
  ns_run --name billing-service --template acme/rust-template --in-place
  [ "$status" -eq 2 ]
  ns_run --name billing-service --template-path "$TPL" --in-place
  [ "$status" -eq 2 ]
  ns_run --name billing-service --template-path "$BATS_TEST_TMPDIR/absent"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--template-path is not a directory"* ]]
  [ "$(wc -l <"$STUB_GH_LOG")" -eq 0 ]
}

@test "new-service: omitted flags take their defaults (AC-12.6)" {
  ns_template
  ns_routes true 0
  cd "$BATS_TEST_TMPDIR"
  ns_run --name billing-service --sync-flavour app
  [ "$status" -eq 0 ]
  [ "$(head -n 2 "$STUB_GH_LOG")" = "gh api user --jq .login
gh api repos/acme/rust-template --jq .is_template" ]
  grep -qxF 'gh repo create acme/billing-service --template acme/rust-template --private' "$STUB_GH_LOG"
  [[ "$output" == *"CHECKOUT: $CO"* ]]
  [ "$(cd "$CO" && python3 -I -c 'import tomllib; print(tomllib.load(open("Cargo.toml", "rb"))["workspace"]["package"]["description"])')" = billing-service ]
  grep -qxF '# billing-service' "$CO/README.md"
  [ "$(sed -n '13p' "$CO/README.md")" = billing-service ]
  [[ "$output" == *"UNCHANGED: version 0.1.0"* ]]
  grep -qF '"description": "billing-service",' "$CO/bmalph/config.json"
}

@test "new-service: visibility and version default from the configuration" {
  ns_template
  ns_config "$BATS_TEST_TMPDIR/public.json" acme/rust-template public 0.2.0
  ns_routes true 0
  ns_route 'repo create acme/billing-service --template acme/rust-template --public' 0
  RUST_SDLC_CONFIG_FILE="$BATS_TEST_TMPDIR/public.json" \
    ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --sync-flavour app
  [ "$status" -eq 0 ]
  grep -qxF 'gh repo create acme/billing-service --template acme/rust-template --public' "$STUB_GH_LOG"
  [[ "$output" == *"NEXT: scripts/set-version.sh 0.2.0"* ]]
  ns_customize --sync-flavour app --version 0.1.0
  [[ "$output" == *"UNCHANGED: version 0.1.0"* ]]
  # --visibility wins over default_visibility.
  ns_run --name billing-service --owner acme --dest "$TMPDIR" --visibility public --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh repo create acme/billing-service --template acme/rust-template --public;"* ]]
}

@test "new-service: an empty gh login exits 1 asking for --owner" {
  ns_route 'api user --jq .login' 0 ''
  ns_run --name billing-service --dest "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"pass --owner"* ]]
  [ "$(cat "$STUB_GH_LOG")" = "gh api user --jq .login" ]
}

# --- phase source (AC-12.2, D17) --------------------------------------------------------------

@test "new-service: the template flow runs the exact gh argv order without --clone" {
  ns_source
  [ "$(cat "$STUB_GH_LOG")" = "gh api repos/acme/rust-template --jq .is_template
gh repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner
gh repo create acme/billing-service --template acme/rust-template --private
gh api repos/acme/billing-service/commits?per_page=1 --jq length
gh repo clone acme/billing-service $CO" ]
  run grep -c -- '--clone' "$STUB_GH_LOG"
  [ "$output" = 0 ]
  [ "$(git -C "$CO" remote get-url origin)" = https://github.com/acme/billing-service.git ]
}

@test "new-service: the template flow prints the source handles and writes source.json" {
  local sha
  ns_source
  sha="$(git -C "$CO" rev-parse HEAD)"
  [[ "$output" == *"SOURCE_MODE: template"* ]]
  [[ "$output" == *"REPO: acme/billing-service"* ]]
  [[ "$output" == *"CHECKOUT: $CO"* ]]
  [[ "$output" == *"SOURCE: acme/rust-template"* ]]
  [[ "$output" == *"SOURCE_SHA: $sha"* ]]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=1 unchanged=0 skip=0 next=0" ]
  run python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert list(d) == ["schema_version", "mode", "source", "sha", "identity_slug", "specs"], list(d)
assert d["schema_version"] == 1 and d["mode"] == "template" and d["source"] == "acme/rust-template"
assert d["sha"] == sys.argv[2] and d["identity_slug"] == "acme/rust-template"
assert d["specs"] == ["specs/example-bundle"], d["specs"]
' "$RECORD" "$sha"
  [ "$status" -eq 0 ]
}

@test "new-service: a repository without commits after the poll budget exits 1" {
  ns_template
  ns_routes true 0 0
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"repository acme/billing-service has no commit after 3 attempts 0s apart"* ]]
  [ "$(grep -c 'commits?per_page=1' "$STUB_GH_LOG")" -eq 3 ]
  run grep -c 'repo clone' "$STUB_GH_LOG"
  [ "$output" = 0 ]
  [ ! -e "$CO" ]
}

@test "new-service: clone-and-push imports the template and prints IMPORT_PENDING (D17)" {
  local sha
  ns_template
  ns_routes false 0
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 0 ]
  [ "$(head -n 3 "$STUB_GH_LOG")" = "gh api repos/acme/rust-template --jq .is_template
gh repo view acme/billing-service --json nameWithOwner --jq .nameWithOwner
gh repo create acme/billing-service --private" ]
  [[ "$(sed -n '4p' "$STUB_GH_LOG")" =~ ^gh\ repo\ clone\ acme/rust-template\ .+\ --\ --depth\ 1$ ]]
  [ "$(wc -l <"$STUB_GH_LOG")" -eq 4 ]
  grep -qE '^git -C .+ archive HEAD$' "$NS_GIT_LOG"
  grep -qxF "git -C $CO init -b main" "$NS_GIT_LOG"
  grep -qxF "git -C $CO remote add origin https://github.com/acme/billing-service.git" "$NS_GIT_LOG"
  sha="$(printf '%s\n' "$output" | sed -n 's/^SOURCE_SHA: //p')"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]]
  [[ "$output" == *"SOURCE_MODE: clone-and-push"* ]]
  [[ "$output" == *"IMPORT_PENDING: acme/rust-template@$sha"* ]]
  [[ "$output" == *"NEXT: ask the template owner to enable Settings > Template repository"* ]]
  [ -f "$CO/Cargo.toml" ]
  [ -f "$CO/xtask/src/main.rs" ]
  run git -C "$CO" rev-parse --verify -q HEAD
  [ "$status" -ne 0 ]
  [ "$(git -C "$CO" remote get-url origin)" = https://github.com/acme/billing-service.git ]
  grep -qF '"mode": "clone-and-push"' "$RECORD"
  grep -qF "\"sha\": \"$sha\"" "$RECORD"
}

@test "new-service: an existing repository with a matching origin prints SKIP: source (exists)" {
  ns_source
  ns_reroute true 1
  : >"$STUB_GH_LOG"
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: source (exists)"* ]]
  [[ "$output" == *"SOURCE_MODE: template"* ]]
  [[ "$output" == *"CHECKOUT: $CO"* ]]
  run grep -c 'repo create\|repo clone' "$STUB_GH_LOG"
  [ "$output" = 0 ]
}

@test "new-service: an existing repository with a mismatched origin exits 1 without repo create" {
  ns_source
  git -C "$CO" remote set-url origin https://github.com/acme/other-service.git
  ns_reroute true 1
  : >"$STUB_GH_LOG"
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED: repository acme/billing-service already exists and $CO is not a clone of it"* ]]
  run grep -c 'repo create' "$STUB_GH_LOG"
  [ "$output" = 0 ]
  # The repository exists and no checkout is there at all: refused the same way.
  rm -rf "$CO"
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 1 ]
  run grep -c 'repo create' "$STUB_GH_LOG"
  [ "$output" = 0 ]
}

@test "new-service: a foreign non-empty checkout exits 1 without repo create" {
  ns_template
  ns_routes true 0
  mkdir -p "$CO"
  printf 'notes\n' >"$CO/notes.txt"
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED: checkout $CO exists and is not empty"* ]]
  run grep -c 'repo create' "$STUB_GH_LOG"
  [ "$output" = 0 ]
  [ "$(ls -A "$CO")" = notes.txt ]
}

@test "new-service: source.json is written once and never overwritten" {
  ns_source
  python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["identity_slug"] = "acme/kept-identity"
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
' "$RECORD"
  cp "$RECORD" "$BATS_TEST_TMPDIR/record.before"
  ns_reroute true 1
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  cmp "$RECORD" "$BATS_TEST_TMPDIR/record.before"
  grep -q 'acme/kept-identity' "$RECORD"
}

@test "new-service: --template-path imports a clean local checkout without a remote" {
  local sha
  ns_template
  sha="$(git -C "$TPL" rev-parse HEAD)"
  ns_run --name billing-service --template-path "$TPL" --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCE_MODE: path"* ]]
  [[ "$output" != *"REPO:"* ]]
  [[ "$output" == *"SOURCE: local:$TPL"* ]]
  [[ "$output" == *"SOURCE_SHA: $sha"* ]]
  grep -qxF "git -C $TPL status --porcelain --untracked-files=no" "$NS_GIT_LOG"
  grep -qxF "git -C $TPL archive HEAD" "$NS_GIT_LOG"
  grep -qxF "git -C $CO init -b main" "$NS_GIT_LOG"
  run git -C "$CO" remote
  [ -z "$output" ]
  [ -f "$CO/README.md" ]
  [ "$(wc -l <"$STUB_GH_LOG")" -eq 0 ]
  # A re-run recognizes its own import.
  ns_run --name billing-service --template-path "$TPL" --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: source (exists)"* ]]
}

@test "new-service: --template-path on a checkout with uncommitted tracked changes is refused" {
  ns_template
  printf 'local edit\n' >>"$TPL/README.md"
  ns_run --name billing-service --template-path "$TPL" --dest "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED: template checkout $TPL has uncommitted tracked changes"* ]]
  [ ! -e "$CO" ]
  # Untracked files do not count.
  git -C "$TPL" checkout -q -- README.md
  printf 'scratch\n' >"$TPL/untracked.txt"
  ns_run --name billing-service --template-path "$TPL" --dest "$BATS_TEST_TMPDIR" --phase source
  [ "$status" -eq 0 ]
}

# --- in-place mode -------------------------------------------------------------------------------

@test "new-service: --in-place skips the source and writes source.json from the root commit" {
  local root
  rr_materialize "$CO"
  root="$(git -C "$CO" rev-list --max-parents=0 HEAD)"
  ns_route 'auth status' 0
  cd "$CO"
  ns_run --name billing-service --in-place --owner acme --sync-flavour app
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: source (in place)"* ]]
  [[ "$output" == *"SOURCE_MODE: in-place"* ]]
  [[ "$output" == *"REPO: acme/billing-service"* ]]
  [[ "$output" == *"SOURCE_SHA: $root"* ]]
  [[ "$output" != *"NEXT: rename"* ]]
  [[ "$output" == *"DONE: specs removed specs/example-bundle"* ]]
  run python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["mode"] == "in-place" and d["sha"] == sys.argv[2], d
assert d["identity_slug"] == "acme/rust-template" and d["specs"] == ["specs/example-bundle"], d
assert d["source"] == "acme/rust-template", d
' "$RECORD" "$root"
  [ "$status" -eq 0 ]
  grep -qF 'https://github.com/acme/billing-service/actions' "$CO/README.md"
  # Once committed, a second in-place run passes the guards through the record.
  git -C "$CO" add -A
  git -C "$CO" commit -q -m 'chore: customize'
  ns_run --name billing-service --in-place --owner acme --sync-flavour app
  [ "$status" -eq 0 ]
  ns_only '^(UNCHANGED|SKIP|SUMMARY|SOURCE_MODE|REPO|CHECKOUT|SOURCE|SOURCE_SHA): '
}

@test "new-service: --in-place with uncommitted tracked changes is refused" {
  rr_materialize "$CO"
  printf 'edit\n' >>"$CO/README.md"
  cd "$CO"
  ns_run --name billing-service --in-place --owner acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED: in-place target has uncommitted tracked changes"* ]]
  [[ "$output" != *"SKIP: source"* ]]
  [ ! -e "$RECORD" ]
}

@test "new-service: --in-place on an already customized target is refused" {
  rr_materialize "$CO"
  sed 's#^repository = .*#repository = "https://github.com/acme/billing-service"#' "$CO/Cargo.toml" >"$BATS_TEST_TMPDIR/Cargo.toml"
  cp "$BATS_TEST_TMPDIR/Cargo.toml" "$CO/Cargo.toml"
  git -C "$CO" commit -q -am 'chore: set the identity'
  cd "$CO"
  ns_run --name billing-service --in-place --owner acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED: in-place target already customized"* ]]
  [ ! -e "$RECORD" ]
}

@test "new-service: --in-place keeps a bundle modified since the import" {
  rr_materialize "$CO"
  printf '\n- FR-3: one more requirement.\n' >>"$CO/specs/example-bundle/prd.md"
  mkdir -p "$CO/specs/12-later-bundle"
  printf '# Later\n' >"$CO/specs/12-later-bundle/prd.md"
  git -C "$CO" add -A
  git -C "$CO" commit -q -m 'docs: plan more'
  ns_route 'auth status' 0
  cd "$CO"
  ns_run --name billing-service --in-place --owner acme --sync-flavour app
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: specs (modified since import)"* ]]
  [[ "$output" != *"DONE: specs removed"* ]]
  [ -f "$CO/specs/example-bundle/prd.md" ]
  [ -f "$CO/specs/12-later-bundle/prd.md" ]
  grep -qF '"specs": []' "$RECORD"
}

@test "new-service: --in-place names the checkout rename when the directory name differs" {
  local dir="$BATS_TEST_TMPDIR/checkout"
  rr_materialize "$dir"
  cd "$dir"
  ns_run --name billing-service --in-place --owner acme --phase source
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: source (in place)"* ]]
  [[ "$output" == *"NEXT: rename the checkout directory to billing-service (it is the Compose project name)"* ]]
  # Without `gh auth status` the mode is local: no REPO handle.
  [[ "$output" != *"REPO:"* ]]
}

# --- phase customize (AC-12.1) -------------------------------------------------------------------

@test "new-service: customize runs the nine steps in order" {
  local steps
  ns_source
  ns_customize --sync-flavour app
  [ "$status" -eq 0 ]
  steps="$(printf '%s\n' "$output" | sed -nE 's/^(DONE|UNCHANGED|SKIP|NEXT): (identity|version|bmalph-config|readme|changelog|specs|sync flavour|templatesyncignore|docs-check citation).*/\2/p' | uniq | tr '\n' ',')"
  [ "$steps" = "identity,version,bmalph-config,readme,changelog,specs,sync flavour,templatesyncignore,docs-check citation," ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=10 unchanged=1 skip=0 next=0" ]
}

@test "new-service: identity edits only description and repository of [workspace.package]" {
  ns_source
  ns_customize --sync-flavour app --description 'Billing Service'
  [ "$status" -eq 0 ]
  [[ "$output" == *"DONE: identity Cargo.toml (description, repository)"* ]]
  run ns_golden Cargo.toml
  [ "$output" = '@@ -27,2 +27,2 @@
-description = "Rust Template"
-repository = "https://github.com/acme/rust-template"
+description = "Billing Service"
+repository = "https://github.com/acme/billing-service"' ]
}

@test "new-service: version prints UNCHANGED: version or NEXT: scripts/set-version.sh" {
  ns_source
  ns_customize --sync-flavour app
  [[ "$output" == *"UNCHANGED: version 0.1.0"* ]]
  ns_customize --sync-flavour app --version 1.2.3
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEXT: scripts/set-version.sh 1.2.3"* ]]
  grep -qx 'version = "0.1.0"' "$CO/Cargo.toml"
}

@test "new-service: bmalph-config sets name and description and keeps the other keys" {
  ns_source
  ns_customize --sync-flavour app --description 'Billing Service'
  [[ "$output" == *"DONE: bmalph-config bmalph/config.json"* ]]
  run ns_golden bmalph/config.json
  [ "$output" = '@@ -2,2 +2,2 @@
-  "name": "rust-template",
-  "description": "Acme Rust service template",
+  "name": "billing-service",
+  "description": "Billing Service",' ]
}

@test "new-service: readme rewrites the title, the badges from identity_slug and the intro" {
  ns_source
  ns_customize --sync-flavour app --description 'Billing Service' --intro 'Invoices and payments of Acme.'
  [[ "$output" == *"DONE: readme README.md"* ]]
  run ns_golden README.md
  [ "$output" = '@@ -3 +3 @@
-# Rust Template
+# Billing Service
@@ -5,7 +5,7 @@
-[![Quality](https://github.com/acme/rust-template/actions/workflows/quality.yml/badge.svg)](https://github.com/acme/rust-template/actions/workflows/quality.yml)
-[![Tests](https://github.com/acme/rust-template/actions/workflows/tests.yml/badge.svg)](https://github.com/acme/rust-template/actions/workflows/tests.yml)
-[![Contracts](https://github.com/acme/rust-template/actions/workflows/contracts.yml/badge.svg)](https://github.com/acme/rust-template/actions/workflows/contracts.yml)
-[![Security](https://github.com/acme/rust-template/actions/workflows/security.yml/badge.svg)](https://github.com/acme/rust-template/actions/workflows/security.yml)
-[![codecov](https://codecov.io/gh/acme/rust-template/graph/badge.svg)](https://codecov.io/gh/acme/rust-template)
-[![Latest release](https://img.shields.io/github/v/release/acme/rust-template)](https://github.com/acme/rust-template/releases/latest)
-[![License](https://img.shields.io/github/license/acme/rust-template)](https://github.com/acme/rust-template/blob/main/LICENSE)
+[![Quality](https://github.com/acme/billing-service/actions/workflows/quality.yml/badge.svg)](https://github.com/acme/billing-service/actions/workflows/quality.yml)
+[![Tests](https://github.com/acme/billing-service/actions/workflows/tests.yml/badge.svg)](https://github.com/acme/billing-service/actions/workflows/tests.yml)
+[![Contracts](https://github.com/acme/billing-service/actions/workflows/contracts.yml/badge.svg)](https://github.com/acme/billing-service/actions/workflows/contracts.yml)
+[![Security](https://github.com/acme/billing-service/actions/workflows/security.yml/badge.svg)](https://github.com/acme/billing-service/actions/workflows/security.yml)
+[![codecov](https://codecov.io/gh/acme/billing-service/graph/badge.svg)](https://codecov.io/gh/acme/billing-service)
+[![Latest release](https://img.shields.io/github/v/release/acme/billing-service)](https://github.com/acme/billing-service/releases/latest)
+[![License](https://img.shields.io/github/license/acme/billing-service)](https://github.com/acme/billing-service/blob/main/LICENSE)
@@ -13 +13 @@
-The Acme baseline for backend services written in Rust: a Cargo workspace with one crate per bounded-context layer, a REST and GraphQL API on axum, PostgreSQL through sqlx, contract snapshots, architecture guards, quality gates behind one command surface, and guidance for AI coding assistants. A downstream service inherits the platform concerns instead of rebuilding them.
+Invoices and payments of Acme.' ]
}

@test "new-service: changelog becomes the cocogitto skeleton" {
  ns_source
  ns_customize --sync-flavour app
  [[ "$output" == *"DONE: changelog CHANGELOG.md"* ]]
  [ "$(cat "$CO/CHANGELOG.md")" = '# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -

Changelog generated by [cocogitto](https://github.com/cocogitto/cocogitto).' ]
  [ "$(tail -c 1 "$CO/CHANGELOG.md" | od -An -c | tr -d ' ')" = '\n' ]
}

@test "new-service: specs deletes the bundles listed in source.json and --keep-specs skips" {
  ns_source
  mkdir -p "$CO/specs/7-service-bundle"
  printf '# Service plan\n' >"$CO/specs/7-service-bundle/prd.md"
  ns_customize --sync-flavour app --keep-specs
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: specs (--keep-specs)"* ]]
  [ -d "$CO/specs/example-bundle" ]
  ns_customize --sync-flavour app
  [ "$status" -eq 0 ]
  [[ "$output" == *"DONE: specs removed specs/example-bundle"* ]]
  [ ! -e "$CO/specs/example-bundle" ]
  [ -f "$CO/specs/7-service-bundle/prd.md" ]
  ns_customize --sync-flavour app
  [[ "$output" == *"UNCHANGED: specs"* ]]
}

@test "new-service: a second customize run prints only UNCHANGED and SKIP lines (AC-12.1)" {
  ns_source
  ns_customize --sync-flavour app --description 'Billing Service' --intro 'Invoices and payments of Acme.'
  [ "$status" -eq 0 ]
  ns_customize --sync-flavour app --description 'Billing Service' --intro 'Invoices and payments of Acme.'
  [ "$status" -eq 0 ]
  ns_only '^(UNCHANGED|SKIP|SUMMARY): '
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=0 unchanged=9 skip=0 next=0" ]
  ns_customize --sync-flavour app --description 'Billing Service' --intro 'Invoices and payments of Acme.' --keep-specs
  [ "$status" -eq 0 ]
  ns_only '^(UNCHANGED|SKIP|SUMMARY): '
}

# --- sync flavour and citation repair (AC-12.5, D18) ----------------------------------------------

@test "new-service: --sync-flavour app keeps the app pair and repairs the citation (AC-12.5)" {
  ns_source
  ns_customize --sync-flavour app
  [ "$status" -eq 0 ]
  [ -f "$CO/.github/workflows/template-sync-app.yml" ]
  [ -f "$CO/.github/TEMPLATE_SYNC_APP.md" ]
  [ ! -e "$CO/.github/workflows/template-sync-pat.yml" ]
  [ ! -e "$CO/.github/TEMPLATE_SYNC_PAT.md" ]
  [[ "$output" == *"DONE: sync flavour app deleted .github/workflows/template-sync-pat.yml"* ]]
  [[ "$output" == *"DONE: docs-check citation docs/extension-seams.md:43"* ]]
  run ns_golden .templatesyncignore
  [ "$output" = '@@ -24,0 +25,3 @@
+.github/workflows/template-sync-pat.yml
+.github/TEMPLATE_SYNC_PAT.md
+docs/extension-seams.md' ]
  run ns_golden docs/extension-seams.md
  [ "$output" = '@@ -43 +43 @@
-The template sync (see the sync guide, `.github/TEMPLATE_SYNC_APP.md` or `.github/TEMPLATE_SYNC_PAT.md`) resolves every difference in favour of the template, so a sync pull request removes what a service added to a synchronised file. The template does not put the files of these seams on its own ignore list on purpose: a fix of the router, the request span or the shutdown sequence must keep reaching every service that has not changed them. A service that uses a seam therefore:
+The template sync (see the sync guide, `.github/TEMPLATE_SYNC_APP.md` or `TEMPLATE_SYNC_PAT.md`) resolves every difference in favour of the template, so a sync pull request removes what a service added to a synchronised file. The template does not put the files of these seams on its own ignore list on purpose: a fix of the router, the request span or the shutdown sequence must keep reaching every service that has not changed them. A service that uses a seam therefore:' ]
  run ns_rule3
  [ -z "$output" ]
  # Control: the unrepaired line is a rule-3 violation once the guide is gone.
  cp "$CO/docs/extension-seams.md" "$BATS_TEST_TMPDIR/repaired.md"
  git -C "$CO" show HEAD:docs/extension-seams.md >"$CO/docs/extension-seams.md"
  run ns_rule3
  [[ "$output" == *"(3) docs/extension-seams.md:43: .github/TEMPLATE_SYNC_PAT.md does not exist"* ]]
  cp "$BATS_TEST_TMPDIR/repaired.md" "$CO/docs/extension-seams.md"
  ns_customize --sync-flavour app
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCHANGED: docs-check citations"* ]]
  [ "$(grep -cxF docs/extension-seams.md "$CO/.templatesyncignore")" -eq 1 ]
  [ "$(grep -cxF .github/TEMPLATE_SYNC_PAT.md "$CO/.templatesyncignore")" -eq 1 ]
}

@test "new-service: --sync-flavour pat keeps the pat pair and repairs the citation (AC-12.5)" {
  ns_source
  ns_customize --sync-flavour pat
  [ "$status" -eq 0 ]
  [ -f "$CO/.github/workflows/template-sync-pat.yml" ]
  [ -f "$CO/.github/TEMPLATE_SYNC_PAT.md" ]
  [ ! -e "$CO/.github/workflows/template-sync-app.yml" ]
  [ ! -e "$CO/.github/TEMPLATE_SYNC_APP.md" ]
  [[ "$output" == *"DONE: docs-check citation docs/extension-seams.md:43"* ]]
  run ns_golden .templatesyncignore
  [ "$output" = '@@ -24,0 +25,3 @@
+.github/workflows/template-sync-app.yml
+.github/TEMPLATE_SYNC_APP.md
+docs/extension-seams.md' ]
  run ns_golden docs/extension-seams.md
  [ "$output" = '@@ -43 +43 @@
-The template sync (see the sync guide, `.github/TEMPLATE_SYNC_APP.md` or `.github/TEMPLATE_SYNC_PAT.md`) resolves every difference in favour of the template, so a sync pull request removes what a service added to a synchronised file. The template does not put the files of these seams on its own ignore list on purpose: a fix of the router, the request span or the shutdown sequence must keep reaching every service that has not changed them. A service that uses a seam therefore:
+The template sync (see the sync guide, `TEMPLATE_SYNC_APP.md` or `.github/TEMPLATE_SYNC_PAT.md`) resolves every difference in favour of the template, so a sync pull request removes what a service added to a synchronised file. The template does not put the files of these seams on its own ignore list on purpose: a fix of the router, the request span or the shutdown sequence must keep reaching every service that has not changed them. A service that uses a seam therefore:' ]
  run ns_rule3
  [ -z "$output" ]
  ns_customize --sync-flavour pat
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCHANGED: docs-check citations"* ]]
  [ "$(grep -cxF docs/extension-seams.md "$CO/.templatesyncignore")" -eq 1 ]
  # The other flavour after one was chosen would leave none: refused, nothing deleted.
  ns_customize --sync-flavour app
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"step sync-flavour failed"* ]]
  [ -f "$CO/.github/workflows/template-sync-pat.yml" ]
}

@test "new-service: the fixed extension-seams variant prints UNCHANGED: docs-check citations" {
  ns_template
  cp "$PLUGIN_ROOT/tests/fixtures/variants/extension-seams-fixed.md.tpl" "$TPL/docs/extension-seams.md"
  git -C "$TPL" commit -q -am 'docs: cite the sync guides by bare name'
  ns_source
  ns_customize --sync-flavour app
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCHANGED: docs-check citations"* ]]
  [[ "$output" != *"DONE: docs-check citation"* ]]
  run grep -cxF docs/extension-seams.md "$CO/.templatesyncignore"
  [ "$output" = 0 ]
  run ns_golden docs/extension-seams.md
  [ -z "$output" ]
  run ns_rule3
  [ -z "$output" ]
}

@test "new-service: an omitted sync flavour prints SKIP and NEXT (D18)" {
  ns_source
  ns_customize
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: sync flavour (undecided)"* ]]
  [[ "$output" == *"NEXT: re-run with --sync-flavour app|pat"* ]]
  [[ "$output" == *"SKIP: templatesyncignore (sync flavour undecided)"* ]]
  [[ "$output" == *"SKIP: docs-check citations (sync flavour undecided)"* ]]
  [ -f "$CO/.github/workflows/template-sync-app.yml" ]
  [ -f "$CO/.github/workflows/template-sync-pat.yml" ]
  run ns_golden .templatesyncignore
  [ -z "$output" ]
  run ns_golden docs/extension-seams.md
  [ -z "$output" ]
}

# --- failures and modes ----------------------------------------------------------------------------

@test "new-service: a read-only CHANGELOG.md fails its step untouched and a re-run rewrites the badges from identity_slug" {
  skip_if_root
  ns_source
  chmod 0444 "$CO/CHANGELOG.md"
  ns_customize --sync-flavour app
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"step changelog failed"* ]]
  [[ "$output" == *"DONE: readme README.md"* ]]
  [[ "$output" != *"specs removed"* ]]
  run ns_golden CHANGELOG.md
  [ -z "$output" ]
  git -C "$CO" show HEAD:README.md >"$CO/README.md"
  chmod 0644 "$CO/CHANGELOG.md"
  ns_customize --sync-flavour app
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCHANGED: identity Cargo.toml"* ]]
  [[ "$output" == *"DONE: readme README.md"* ]]
  grep -qF 'https://github.com/acme/billing-service/actions/workflows/quality.yml' "$CO/README.md"
  run grep -c 'acme/rust-template' "$CO/README.md"
  [ "$output" = 0 ]
}

@test "new-service: a symlinked CHANGELOG.md fails its step untouched and a re-run rewrites the badges from identity_slug" {
  ns_source
  printf 'outside\n' >"$BATS_TEST_TMPDIR/outside.md"
  rm "$CO/CHANGELOG.md"
  ln -s "$BATS_TEST_TMPDIR/outside.md" "$CO/CHANGELOG.md"
  ns_customize --sync-flavour app
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"step changelog failed"* ]]
  [ -L "$CO/CHANGELOG.md" ]
  [ "$(cat "$BATS_TEST_TMPDIR/outside.md")" = outside ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=3 unchanged=1 skip=0 next=0" ]
  rm "$CO/CHANGELOG.md"
  git -C "$CO" show HEAD:CHANGELOG.md >"$CO/CHANGELOG.md"
  git -C "$CO" show HEAD:README.md >"$CO/README.md"
  ns_customize --sync-flavour app
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCHANGED: identity Cargo.toml"* ]]
  [[ "$output" == *"DONE: readme README.md"* ]]
  grep -qF '[![codecov](https://codecov.io/gh/acme/billing-service/graph/badge.svg)]' "$CO/README.md"
  run grep -c 'acme/rust-template' "$CO/README.md"
  [ "$output" = 0 ]
}

@test "new-service: local mode without --owner edits the description only and prints NEXT" {
  ns_template
  ns_run --name billing-service --template-path "$TPL" --dest "$BATS_TEST_TMPDIR" --sync-flavour app
  [ "$status" -eq 0 ]
  [[ "$output" == *"DONE: identity Cargo.toml (description)"* ]]
  [[ "$output" == *"NEXT: set [workspace.package].repository once the GitHub repository exists"* ]]
  [[ "$output" == *"NEXT: point the README badges at the GitHub repository once it exists"* ]]
  grep -qx 'description = "billing-service"' "$CO/Cargo.toml"
  grep -qx 'repository = "https://github.com/acme/rust-template"' "$CO/Cargo.toml"
  # The fresh import is untracked, and its citation is repaired all the same.
  [[ "$output" == *"DONE: docs-check citation docs/extension-seams.md:43"* ]]
  [ "$(wc -l <"$STUB_GH_LOG")" -eq 0 ]
  # With --owner, local mode sets the repository too.
  ns_run --name billing-service --template-path "$TPL" --dest "$BATS_TEST_TMPDIR" --sync-flavour app --owner acme
  [ "$status" -eq 0 ]
  grep -qx 'repository = "https://github.com/acme/billing-service"' "$CO/Cargo.toml"
}

@test "new-service: customize without a source record or with a malformed one exits 1" {
  rr_materialize "$CO"
  ns_customize --sync-flavour app
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED: no source record target/rust-sdlc/new-service/source.json in $CO"* ]]
  run ns_golden Cargo.toml
  [ -z "$output" ]
  mkdir -p "$(dirname "$RECORD")"
  printf '{"schema_version": 1, "mode": "template", "source": "acme/rust-template", "sha": "abc", "identity_slug": "acme/rust-template", "specs": ["../etc"]}\n' >"$RECORD"
  ns_customize --sync-flavour app
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"malformed $RECORD: sha: invalid value"* ]]
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR/absent-parent" --phase customize
  [ "$status" -eq 2 ]
}

# --- dry run, summary and safety (AC-12.3, AC-12.4) ---------------------------------------------------

@test "new-service: --dry-run of a new service prints only WOULD lines and makes no mutating gh call (AC-12.3)" {
  ns_template
  ns_routes true 0
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --sync-flavour app --dry-run
  [ "$status" -eq 0 ]
  ns_only '^(WOULD|SUMMARY): '
  [[ "$output" == *"WOULD: source template (gh repo create acme/billing-service --template acme/rust-template --private; gh repo clone acme/billing-service $CO)"* ]]
  [[ "$output" == *"WOULD: customize $CO"* ]]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=2 unchanged=0 skip=0 next=0" ]
  run grep -vE '^gh (api repos/acme/rust-template --jq \.is_template|repo view )' "$STUB_GH_LOG"
  [ -z "$output" ]
  [ ! -e "$CO" ]
  # Clone-and-push and local imports stay dry too.
  ns_reroute false 0
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
  ns_only '^(WOULD|SUMMARY): '
  ns_run --name billing-service --template-path "$TPL" --dest "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
  ns_only '^(WOULD|SUMMARY): '
  [ ! -e "$CO" ]
  run grep -E 'repo (create|clone)' "$STUB_GH_LOG"
  [ -z "$output" ]
}

@test "new-service: --dry-run on an existing checkout leaves the tree unchanged" {
  ns_source
  ns_tree "$CO" >"$BATS_TEST_TMPDIR/tree.before"
  ns_reroute true 1
  : >"$STUB_GH_LOG"
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --sync-flavour app --dry-run
  [ "$status" -eq 0 ]
  ns_only '^(WOULD|SUMMARY): '
  [[ "$output" == *"WOULD: identity Cargo.toml (description, repository)"* ]]
  [[ "$output" == *"WOULD: specs removed specs/example-bundle"* ]]
  [[ "$output" == *"WOULD: docs-check citation docs/extension-seams.md:43"* ]]
  [[ "$output" != *"citation .github/"* ]]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=10 unchanged=1 skip=1 next=0" ]
  ns_tree "$CO" >"$BATS_TEST_TMPDIR/tree.after"
  cmp "$BATS_TEST_TMPDIR/tree.before" "$BATS_TEST_TMPDIR/tree.after"
  run grep -E 'repo (create|clone)' "$STUB_GH_LOG"
  [ -z "$output" ]
  # In place, the record that a real run would write stays unwritten too.
  rm -rf "$CO"
  rr_materialize "$CO"
  ns_tree "$CO" >"$BATS_TEST_TMPDIR/tree.before"
  cd "$CO"
  ns_run --name billing-service --in-place --owner acme --sync-flavour pat --dry-run
  [ "$status" -eq 0 ]
  ns_only '^(WOULD|SUMMARY): '
  ns_tree "$CO" >"$BATS_TEST_TMPDIR/tree.after"
  cmp "$BATS_TEST_TMPDIR/tree.before" "$BATS_TEST_TMPDIR/tree.after"
}

@test "new-service: every run ends with the SUMMARY line, refusals included" {
  ns_source
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=1 unchanged=0 skip=0 next=0" ]
  ns_customize
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=5 unchanged=1 skip=3 next=1" ]
  rr_materialize "$BATS_TEST_TMPDIR/other"
  printf 'edit\n' >>"$BATS_TEST_TMPDIR/other/README.md"
  ns_run --name billing-service --template-path "$BATS_TEST_TMPDIR/other" --dest "$BATS_TEST_TMPDIR/tmp"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "SUMMARY: done=0 unchanged=0 skip=0 next=0" ]
}

@test "new-service: the git and gh logs show no commit and no push (AC-12.4)" {
  ns_template
  ns_routes true 0
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --sync-flavour app
  [ "$status" -eq 0 ]
  ns_reroute false 0
  rm -rf "$CO"
  ns_run --name billing-service --owner acme --dest "$BATS_TEST_TMPDIR" --sync-flavour pat
  [ "$status" -eq 0 ]
  grep -q '^git -C ' "$NS_GIT_LOG"
  run grep -E '^git( -C [^ ]+)? (commit|push)( |$)' "$NS_GIT_LOG"
  [ -z "$output" ]
  run grep -E '(^| )(commit|push)( |$)' "$STUB_GH_LOG"
  [ -z "$output" ]
}

@test "new-service: the example context and the licence are never touched" {
  ns_source
  ns_customize --sync-flavour app
  [ "$status" -eq 0 ]
  run git -C "$CO" status --porcelain -- crates LICENSE migrations workspace.dsl
  [ -z "$output" ]
  [ -f "$CO/crates/billing/invoice/domain/Cargo.toml" ]
  grep -qx 'license = "CC0-1.0"' "$CO/Cargo.toml"
  grep -qF '"crates/billing/invoice/domain",' "$CO/Cargo.toml"
}

# --- K7: the written files pass the template's linters (NFR-13) ---------------------------------------

@test "new-service: K7 markdownlint-cli2 passes on README.md and CHANGELOG.md after customize" {
  k7_require markdownlint-cli2
  ns_source
  ns_customize --sync-flavour app --description 'Billing Service' --intro 'Invoices and payments of Acme.'
  [ "$status" -eq 0 ]
  cd "$CO"
  run markdownlint-cli2 README.md CHANGELOG.md
  [ "$status" -eq 0 ]
}

@test "new-service: K7 typos passes on README.md and CHANGELOG.md after customize" {
  k7_require typos
  ns_source
  ns_customize --sync-flavour app --description 'Billing Service' --intro 'Invoices and payments of Acme.'
  [ "$status" -eq 0 ]
  cd "$CO"
  run typos README.md CHANGELOG.md
  [ "$status" -eq 0 ]
}

@test "new-service: K7 Prettier passes on bmalph/config.json after customize" {
  k7_require prettier
  ns_source
  ns_customize --sync-flavour app --description 'Billing "Service" — Acme'
  [ "$status" -eq 0 ]
  cd "$CO"
  run prettier --check bmalph/config.json
  [ "$status" -eq 0 ]
  grep -qF '"description": "Billing \"Service\" — Acme",' bmalph/config.json
}
