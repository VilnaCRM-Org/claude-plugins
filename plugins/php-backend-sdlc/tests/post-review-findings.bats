#!/usr/bin/env bats
# Tests for scripts/post-review-findings.sh — the idempotent per-lens PR
# comment poster (architecture.md §12.1 case table, PRD FR-1..11 / NFR-1..8).
#
# The poster's DEFAULT failure mode is skip-with-note + exit 0 (degrade-first,
# the deliberate INVERSE of get-pr-comments.sh which dies). These tests pin the
# render contract (--dry-run / --json, byte-identical jq vs python3), the
# idempotent CREATE→UPDATE marker algorithm asserted via the gh call log, the
# gating + authorization + redaction boundaries, every degrade row (D2..D7),
# the per-lens malformed-ledger hard die, and the conclusion arithmetic.
#
# gh stubbing reuses the env-driven fixture stub (STUB_GH_OUTPUT / STUB_GH_EXIT
# / STUB_GH_LOG, tests/fixtures/bin/gh). Cases that need DIFFERENT output for
# the list call vs the create/patch call (the two-response routing path) use a
# subcommand-routing gh wrapper (the get-pr-comments.bats:121-137 technique),
# routing on the API path: pulls/<pr> -> base repo, `api user` -> login,
# issues/<pr>/comments --jq -> the comment list, -X POST/PATCH -> the write.
#
# The capability gate reads capabilities.publish_pr_comments from
# $PWD/.claude/php-sdlc.yml; setup() writes the flag-on profile there so the
# default path proceeds, and the gating-off case overwrites it with flag-off.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/post-review-findings.sh"
  COMMON="$PLUGIN_ROOT/scripts/lib/common.sh"
  STUBS="$BATS_TEST_DIRNAME/fixtures/bin"
  LEDGERS="$BATS_TEST_DIRNAME/fixtures/ledgers"
  PROFILES="$BATS_TEST_DIRNAME/fixtures/profiles"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK/.claude"
  cd "$WORK"
  git init -q
  git remote add origin https://github.com/acme/sample-api.git
  # Flag ON by default so the render/publish path is reached. The gating-off
  # case overwrites this file.
  cp "$PROFILES/publish-on.yml" "$WORK/.claude/php-sdlc.yml"
  PATH="$STUBS:$PATH"
  GH_LOG="$BATS_TEST_TMPDIR/gh-calls.log"
  export STUB_GH_LOG="$GH_LOG"
}

flag_off() { cp "$PROFILES/publish-off.yml" "$WORK/.claude/php-sdlc.yml"; }

# A no-jq sandbox PATH: every coreutil the script's SCRIPT_DIR resolution and
# transforms need (dirname/env for `cd "$(dirname …)"`, the python3 ledger +
# PyYAML profile backends), MINUS jq — so the python branch is exercised. The
# gh stub is linked in so the publish path still routes.
nojq_bin() {
  local dir=$1
  mkdir -p "$dir"
  local tool src
  for tool in bash git grep sed sort cut tr awk dirname env cat mktemp rm \
              date python3 printf basename head tail wc mkdir ln chmod; do
    src="$(command -v "$tool")" && ln -sf "$src" "$dir/$tool"
  done
  ln -sf "$STUBS/gh" "$dir/gh"
}

# Routing gh wrapper writing every argv to $GH_LOG and emitting, per route:
#   pulls/<pr>      -> base repo full_name  ($1 default acme/sample-api)
#   api user        -> login                ($2 default botuser)
#   issues/.../comments --jq -> the comment list TSV ($3, may be multi-line)
#   everything else -> nothing (POST/PATCH succeed silently)
route_gh() {
  local dir=$1 base=${2:-acme/sample-api} login=${3:-botuser} list=${4:-}
  mkdir -p "$dir"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'echo "gh $*" >> %q\n' "$GH_LOG"
    printf 'case "$*" in\n'
    printf '  *"pulls/7"*) printf "%%s\\n" %q ;;\n' "$base"
    printf '  "api user"*) printf "%%s\\n" %q ;;\n' "$login"
    printf '  *"issues/7/comments"*"--jq"*) printf "%%s" %q ;;\n' "$list"
    printf '  *) : ;;\n'
    printf 'esac\n'
  } > "$dir/gh"
  chmod +x "$dir/gh"
}

# ---------------------------------------------------------------------------
# Render (no gh) — FR-3 / FR-4
# ---------------------------------------------------------------------------

@test "render full ledger (--dry-run): marker, severity-ordered table, summary; zero gh calls" {
  run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"<!-- sdlc-review:security -->"* ]]
  [[ "$output" == *"## SDLC Review — Security audit findings (PR #7)"* ]]
  [[ "$output" == *"| severity | id | cwe | owasp | location | endpoint | summary |"* ]]
  # Critical row appears before the High row (severity order).
  crit_line="$(printf '%s\n' "$output" | grep -n 'A03-1' | cut -d: -f1)"
  high_line="$(printf '%s\n' "$output" | grep -n 'A01-1' | cut -d: -f1)"
  [ "$crit_line" -lt "$high_line" ]
  [[ "$output" == *"_summary: 3 findings (1 critical, 1 high, 1 medium, 0 low); 1 auto-fixed root-cause with regression test._"* ]]
  # zero gh calls in a dry-run
  [ ! -f "$GH_LOG" ]
}

@test "render minimal (required-only): absent cwe/owasp shown as n/a, never null" {
  run "$SCRIPT" fr-nfr --file "$LEDGERS/minimal.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Medium | FR-1-1 | n/a | n/a | src/Catalog/Handler.php:5 | n/a | Acceptance criterion not covered by the change set |"* ]]
  [[ "$output" != *"null"* ]]
}

@test "jq vs python3 byte-identical render (--dry-run, jq removed from PATH)" {
  jq_out="$("$SCRIPT" security --file "$LEDGERS/full.json" --pr 7 --dry-run)"
  dir="$BATS_TEST_TMPDIR/nojq-render"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_out" ]
}

@test "jq vs python3 byte-identical render (--json TSV projection)" {
  jq_out="$("$SCRIPT" security --file "$LEDGERS/full.json" --pr 7 --json)"
  dir="$BATS_TEST_TMPDIR/nojq-json"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7 --json
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_out" ]
}

@test "jq vs python3 byte-identical conclusion render" {
  jq_out="$("$SCRIPT" --conclusion --file "$LEDGERS/full.json" --file "$LEDGERS/minimal.json" \
            --pr 7 --duration-seconds 724 --iterations 4 --dry-run)"
  dir="$BATS_TEST_TMPDIR/nojq-concl"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --file "$LEDGERS/minimal.json" \
    --pr 7 --duration-seconds 724 --iterations 4 --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_out" ]
}

# ---------------------------------------------------------------------------
# Idempotent CREATE / UPDATE / duplicate — FR-2 / NFR-2
# ---------------------------------------------------------------------------

@test "idempotent CREATE (first run): exactly one POST, zero PATCH" {
  # static stub: list returns the slug (no marker) -> create. STUB_GH_OUTPUT
  # also satisfies the base-repo authorize and the `api user` login reads.
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X POST repos/acme/sample-api/issues/7/comments' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X PATCH' "$GH_LOG")" -eq 0 ]
}

@test "idempotent UPDATE (second run): exactly one PATCH on the matched id, zero POST" {
  dir="$BATS_TEST_TMPDIR/route-update"
  route_gh "$dir" "acme/sample-api" "botuser" \
    "$(printf '555\tbotuser\t<!-- sdlc-review:security --> prior body')"
  PATH="$dir:$PATH" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X PATCH repos/acme/sample-api/issues/comments/555' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X POST' "$GH_LOG")" -eq 0 ]
}

@test "duplicate-marker collapse: one PATCH on the oldest, never a third create" {
  # Two marker'd, author-matched comments (REST lists oldest-first: 555 then
  # 777). The poster must edit the oldest and never POST a new one.
  dir="$BATS_TEST_TMPDIR/route-dup"
  route_gh "$dir" "acme/sample-api" "botuser" \
    "$(printf '555\tbotuser\t<!-- sdlc-review:security --> dup one\n777\tbotuser\t<!-- sdlc-review:security --> dup two')"
  PATH="$dir:$PATH" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X PATCH repos/acme/sample-api/issues/comments/555' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X POST' "$GH_LOG")" -eq 0 ]
  # exactly one edit total — no second PATCH, no create
  [ "$(grep -cE 'api -X (POST|PATCH)' "$GH_LOG")" -eq 1 ]
}

@test "never uses gh pr comment --edit-last" {
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  ! grep -q -- '--edit-last' "$GH_LOG"
  ! grep -q 'pr comment' "$GH_LOG"
}

# ---------------------------------------------------------------------------
# Dedup + severity order — FR-4
# ---------------------------------------------------------------------------

@test "dedup by (cwe,location,endpoint): the pair collapses to one row" {
  run "$SCRIPT" security --file "$LEDGERS/dedup-pair.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  # exactly one data row in the findings table (the | separator line is |---)
  data_rows="$(printf '%s\n' "$output" | grep -cE '^\| (Critical|High|Medium|Low) ')"
  [ "$data_rows" -eq 1 ]
  # the second finding's distinct summary text is gone (collapsed away)
  [[ "$output" != *"SECOND-FINDING-SAME-SINK"* ]]
}

@test "severity order: Critical first, Low last; dropped grouped below, never above an open row" {
  run "$SCRIPT" code-review --file "$LEDGERS/mixed-severity.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  crit="$(printf '%s\n' "$output" | grep -n 'CRIT-1' | cut -d: -f1)"
  high="$(printf '%s\n' "$output" | grep -n 'HIGH-1' | cut -d: -f1)"
  med="$(printf '%s\n' "$output"  | grep -n 'MED-1'  | cut -d: -f1)"
  low="$(printf '%s\n' "$output"  | grep -n 'LOW-1'  | cut -d: -f1)"
  [ "$crit" -lt "$high" ]
  [ "$high" -lt "$med" ]
  [ "$med" -lt "$low" ]
  # the dropped row sits in its own section, strictly below every open row
  [[ "$output" == *"Dropped / not reproduced"* ]]
  dropped="$(printf '%s\n' "$output" | grep -n 'STALE-DECLINED-THREAD' | cut -d: -f1)"
  [ "$dropped" -gt "$low" ]
}

@test "dropped + open mix: open row in the main table, dropped only in its section" {
  run "$SCRIPT" security --file "$LEDGERS/dropped-and-open.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  open_line="$(printf '%s\n' "$output" | grep -n 'OPEN-1' | cut -d: -f1)"
  drop_hdr="$(printf '%s\n'  "$output" | grep -n 'Dropped / not reproduced' | cut -d: -f1)"
  drop_line="$(printf '%s\n' "$output" | grep -n 'DROP-X' | cut -d: -f1)"
  [ "$open_line" -lt "$drop_hdr" ]
  [ "$drop_hdr" -lt "$drop_line" ]
}

# ---------------------------------------------------------------------------
# Redaction — FR-7 / NFR-5
# ---------------------------------------------------------------------------

@test "redaction: AWS key, JWT, password=, url-creds masked; cleartext absent from body" {
  run "$SCRIPT" security --file "$LEDGERS/secret-laden.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  # cleartext of each shape must NOT survive into the rendered body
  [[ "$output" != *"AKIAIOSFODNN7EXAMPLE"* ]]
  [[ "$output" != *"SflKxwRJSMeKKF2QT4fwpMeJf36"* ]]
  [[ "$output" != *"SuperSecretPw123"* ]]
  [[ "$output" != *"admin:hunter2"* ]]
  # and each is replaced by a REDACTED marker
  [[ "$output" == *"AKIA...REDACTED"* ]]
  [[ "$output" == *"eyJ...REDACTED"* ]]
  [[ "$output" == *"password=REDACTED"* ]]
  [[ "$output" == *"https://REDACTED@internal.example.com/feed"* ]]
}

@test "redaction is identical on the python3 backend (no jq)" {
  jq_out="$("$SCRIPT" security --file "$LEDGERS/secret-laden.json" --pr 7 --dry-run)"
  dir="$BATS_TEST_TMPDIR/nojq-redact"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" security --file "$LEDGERS/secret-laden.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_out" ]
  [[ "$output" != *"AKIAIOSFODNN7EXAMPLE"* ]]
}

# ---------------------------------------------------------------------------
# Gating — FR-6 / NFR-6
# ---------------------------------------------------------------------------

@test "gating OFF: skip-note, exit 0, zero gh calls (even with --dry-run)" {
  flag_off
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"capabilities.publish_pr_comments is not true"* ]]
  [ ! -f "$GH_LOG" ]
}

@test "gating OFF honored by --dry-run: prints skip-note, does not render the body" {
  flag_off
  run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"capabilities.publish_pr_comments is not true"* ]]
  [[ "$output" != *"<!-- sdlc-review:security -->"* ]]
}

@test "gating ON: proceeds to publish (a CREATE call is made)" {
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X POST repos/acme/sample-api/issues/7/comments' "$GH_LOG")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Degrade matrix D2..D7 — FR-9 / NFR-3
# ---------------------------------------------------------------------------

@test "D2 gh absent: skip-note, exit 0 (NOT a die)" {
  # sandbox PATH with the coreutils + python3 the script needs, but no gh
  dir="$BATS_TEST_TMPDIR/nogh"
  mkdir -p "$dir"
  local tool src
  for tool in bash git grep sed sort cut tr awk dirname env cat mktemp rm \
              date python3 printf basename head tail wc jq; do
    src="$(command -v "$tool")" && ln -sf "$src" "$dir/$tool"
  done
  PATH="$dir" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh not on PATH — skipping publish"* ]]
}

@test "D3 no PR (gh pr view empty, no --pr): skip-note, exit 0, zero write calls" {
  # routing stub: `pr view` returns nothing -> unresolvable PR -> degrade.
  dir="$BATS_TEST_TMPDIR/route-nopr"
  mkdir -p "$dir"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$GH_LOG"
case "\$*" in
  "pr view"*) : ;;
  *) : ;;
esac
EOF
  chmod +x "$dir/gh"
  PATH="$dir:$PATH" run "$SCRIPT" security --file "$LEDGERS/full.json"
  [ "$status" -eq 0 ]
  [ "$(grep -cE 'api -X (POST|PATCH)' "$GH_LOG")" -eq 0 ]
}

@test "D4 empty ledger: skip-note, exit 0, zero gh calls" {
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" security --file "$LEDGERS/empty.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"no open findings — skipping publish"* ]]
  [ ! -f "$GH_LOG" ]
}

@test "D4 all-dropped ledger (zero open after split): skip-note, exit 0, zero gh calls" {
  # a ledger whose ONLY finding is dropped has zero open rows after the
  # open/dropped split -> same D4 empty-ledger degrade, no empty comment.
  printf '{"lens":"security","findings":[{"id":"D","severity":"Low","location":"a:1","summary":"x","status":"dropped"}]}' > "$WORK/alldrop.json"
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" security --file "$WORK/alldrop.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"no open findings — skipping publish"* ]]
  [ ! -f "$GH_LOG" ]
}

@test "D5 malformed comment-list read: warn, fall back to CREATE, exit 0" {
  # the list call returns junk (HTML proxy error); the dedup fails so the
  # poster creates without dedup rather than failing the loop (R11).
  dir="$BATS_TEST_TMPDIR/route-badlist"
  route_gh "$dir" "acme/sample-api" "botuser" "not a tsv line <html>502</html>"
  PATH="$dir:$PATH" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X POST repos/acme/sample-api/issues/7/comments' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X PATCH' "$GH_LOG")" -eq 0 ]
}

@test "D6 base-repo mismatch: refuse-note, exit 0, zero write calls" {
  dir="$BATS_TEST_TMPDIR/route-mismatch"
  route_gh "$dir" "evil/other-repo" "botuser" ""
  PATH="$dir:$PATH" run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"base repo 'evil/other-repo' != resolved repo 'acme/sample-api'"* ]]
  [ "$(grep -cE 'api -X (POST|PATCH)' "$GH_LOG")" -eq 0 ]
}

@test "D7 gh write failure: warn, exit 0 (never fails the loop)" {
  # STUB_GH_EXIT=1 makes every gh call exit nonzero (but still print
  # STUB_GH_OUTPUT), so authorize/list read the slug fine and only the POST
  # fails -> the create-failed warn path.
  STUB_GH_OUTPUT="acme/sample-api" STUB_GH_EXIT=1 run "$SCRIPT" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"create comment failed"* ]]
}

# ---------------------------------------------------------------------------
# Malformed per-lens ledger is the ONE non-degrade case — FR-3
# ---------------------------------------------------------------------------

@test "malformed per-lens ledger: hard die (exit 1), [php-sdlc][ERROR], no traceback" {
  printf 'this is not json {\n' > "$WORK/bad.json"
  run "$SCRIPT" security --file "$WORK/bad.json" --pr 7 --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"[php-sdlc][ERROR]"* ]]
  [[ "$output" == *"malformed ledger"* ]]
  [[ "$output" != *"Traceback"* ]]
  [[ "$output" != *"jq: error"* ]]
}

@test "malformed per-lens ledger dies on the python3 backend too (no jq)" {
  printf '[1,2,3]\n' > "$WORK/wrongtype.json"
  dir="$BATS_TEST_TMPDIR/nojq-malformed"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" security --file "$WORK/wrongtype.json" --pr 7 --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed ledger"* ]]
  [[ "$output" != *"Traceback"* ]]
}

# ---------------------------------------------------------------------------
# Conclusion — FR-5 / NFR-4 / OQ-7
# ---------------------------------------------------------------------------

@test "conclusion math: per-lens severity counts match source; dropped excluded; auto-fixed counted" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --file "$LEDGERS/minimal.json" \
    --pr 7 --duration-seconds 724 --iterations 4 --dry-run
  [ "$status" -eq 0 ]
  # full.json (security): 1 Critical + 1 High + 1 Medium open, 1 dropped excluded => total 3
  [[ "$output" == *"| security | 1 | 1 | 1 | 0 | 3 |"* ]]
  # minimal.json (fr-nfr): 1 Medium
  [[ "$output" == *"| fr-nfr | 0 | 0 | 1 | 0 | 1 |"* ]]
  # code-review absent -> zero row
  [[ "$output" == *"| code-review | 0 | 0 | 0 | 0 | 0 |"* ]]
  # all = 1/1/2/0 total 4
  [[ "$output" == *"| **all** | 1 | 1 | 2 | 0 | 4 |"* ]]
  # auto-fixed: security has 1 (auto_fixed:true + regression_test) of 3
  [[ "$output" == *"| security | 1 / 3 |"* ]]
  [[ "$output" == *"| fr-nfr | 0 / 1 |"* ]]
}

@test "conclusion wrap-safe: num_add on a 20-digit count is exact, and the poster uses no (( )) over counts" {
  # 10^20 finding rows cannot be materialised, so the wrap-safe contract is
  # asserted (a) directly against the num_add accumulator the conclusion uses,
  # and (b) by a code-grep showing no bash (( )) arithmetic over the finding
  # counters (NFR-4 AC). bash (( )) would wrap a 20-digit value modulo 2^64.
  source "$COMMON"
  run num_add 99999999999999999999 1
  [ "$status" -eq 0 ]
  [ "$output" = "100000000000000000000" ]
  # the per-lens/total counters are accumulated via num_add, never (( )), in
  # render_lens and render_conclusion.
  ! grep -Eq '\(\(\s*(n|nc|nh|nm|nl|nfixed|allC|allH|allM|allL|allT)\b' "$SCRIPT"
  ! grep -Eq '\(\(\s*[A-Z]+\[\$' "$SCRIPT"
}

@test "conclusion idempotent (second run): PATCH not POST" {
  dir="$BATS_TEST_TMPDIR/route-concl-update"
  route_gh "$dir" "acme/sample-api" "botuser" \
    "$(printf '900\tbotuser\t<!-- sdlc-review:conclusion --> prior conclusion')"
  PATH="$dir:$PATH" run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" \
    --file "$LEDGERS/minimal.json" --pr 7 --iterations 4
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X PATCH repos/acme/sample-api/issues/comments/900' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X POST' "$GH_LOG")" -eq 0 ]
}

@test "conclusion zero-row for a missing lens" {
  # only the security ledger -> fr-nfr and code-review render explicit zero rows
  run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| fr-nfr | 0 | 0 | 0 | 0 | 0 |"* ]]
  [[ "$output" == *"| code-review | 0 | 0 | 0 | 0 | 0 |"* ]]
  [[ "$output" == *"| security | 1 | 1 | 1 | 0 | 3 |"* ]]
}

@test "conclusion duration: --started-at/--ended-at delta renders human-readable" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --pr 7 \
    --started-at 2026-06-14T10:00:00Z --ended-at 2026-06-14T10:12:04Z --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Duration"* ]]
  [[ "$output" == *"12m 04s"* ]]
}

@test "conclusion duration: --duration-seconds takes precedence" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --pr 7 --duration-seconds 3725 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"1h 02m 05s"* ]]
}

@test "conclusion duration: no source renders n/a" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  # full.json carries started_at/ended_at, so a standalone fallback would use
  # those; assert the dedicated n/a path with a ledger that has no timestamps.
  run "$SCRIPT" --conclusion --file "$LEDGERS/minimal.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  duration_section="$(printf '%s\n' "$output" | sed -n '/### Duration/,$p')"
  [[ "$duration_section" == *"n/a"* ]]
}

# ---------------------------------------------------------------------------
# Installability — NFR-8
# ---------------------------------------------------------------------------

@test "runs from a simulated install cache via CLAUDE_PLUGIN_ROOT (ADR-4)" {
  CACHE="$BATS_TEST_TMPDIR/install-cache/php-backend-sdlc"
  mkdir -p "$(dirname "$CACHE")"
  cp -r "$PLUGIN_ROOT" "$CACHE"
  STUB_GH_OUTPUT="acme/sample-api" CLAUDE_PLUGIN_ROOT="$CACHE" \
    run "$CACHE/scripts/post-review-findings.sh" security --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X POST repos/acme/sample-api/issues/7/comments' "$GH_LOG")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Argument grammar — FR-1
# ---------------------------------------------------------------------------

@test "unknown lens: clean die with usage" {
  run "$SCRIPT" bogus-lens --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown lens: bogus-lens"* ]]
}

@test "unknown flag: clean die with usage" {
  run "$SCRIPT" security --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}

@test "missing lens and no --conclusion: usage error" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"a lens"* || "$output" == *"--conclusion is required"* ]]
}
