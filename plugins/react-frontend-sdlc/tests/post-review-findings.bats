#!/usr/bin/env bats
# Tests for scripts/post-review-findings.sh — the idempotent per-lens PR
# comment poster for the react-frontend-sdlc plugin.
#
# The poster's DEFAULT failure mode is skip-with-note + exit 0 (degrade-first,
# the deliberate INVERSE of get-pr-comments.sh which dies). These tests pin the
# render contract (--dry-run / --json, byte-identical jq vs python3), the
# idempotent CREATE→UPDATE marker algorithm asserted via the gh call log, the
# gating + authorization + redaction boundaries, every degrade row (D2..D7),
# the per-lens malformed-ledger hard die, and the conclusion arithmetic.
#
# Frontend specifics (vs the backend sibling): lenses are
# accessibility | fr-nfr | code-review; the render columns are
# severity | id | wcag | level | location | surface | summary; log lines use
# the [react-sdlc] prefix; the capability profile lives at
# $PWD/.claude/react-sdlc.yml.
#
# gh stubbing reuses the env-driven fixture stub (STUB_GH_OUTPUT / STUB_GH_EXIT
# / STUB_GH_LOG, tests/fixtures/bin/gh). Cases that need DIFFERENT output for
# the list call vs the create/patch call use a subcommand-routing gh wrapper,
# routing on the API path: pulls/<pr> -> base repo, `api user` -> login,
# issues/<pr>/comments --jq -> the comment list, -X POST/PATCH -> the write.

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
  cp "$PROFILES/publish-on.yml" "$WORK/.claude/react-sdlc.yml"
  PATH="$STUBS:$PATH"
  GH_LOG="$BATS_TEST_TMPDIR/gh-calls.log"
  export STUB_GH_LOG="$GH_LOG"
}

flag_off() { cp "$PROFILES/publish-off.yml" "$WORK/.claude/react-sdlc.yml"; }

# A no-jq sandbox PATH: every coreutil the script's SCRIPT_DIR resolution and
# transforms need, MINUS jq — so the python branch is exercised. The gh stub is
# linked in so the publish path still routes.
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
  run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"<!-- sdlc-review:accessibility -->"* ]]
  [[ "$output" == *"## SDLC Review — Accessibility audit findings (PR #7)"* ]]
  [[ "$output" == *"| severity | id | wcag | level | location | surface | summary |"* ]]
  # Critical row (A11Y-1) appears before the High row (A11Y-2) (severity order).
  crit_line="$(printf '%s\n' "$output" | grep -n 'A11Y-1' | cut -d: -f1)"
  high_line="$(printf '%s\n' "$output" | grep -n 'A11Y-2' | cut -d: -f1)"
  [ "$crit_line" -lt "$high_line" ]
  [[ "$output" == *"_summary: 3 findings (1 critical, 1 high, 1 medium, 0 low); 1 auto-fixed root-cause with regression test._"* ]]
  # zero gh calls in a dry-run
  [ ! -f "$GH_LOG" ]
}

@test "render minimal (required-only): absent wcag/level/surface shown as n/a, never null" {
  run "$SCRIPT" fr-nfr --file "$LEDGERS/minimal.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Medium | FR-1-1 | n/a | n/a | src/modules/alpha/features/login/login-form.tsx:5 | n/a | Acceptance criterion not covered by the change set |"* ]]
  [[ "$output" != *"null"* ]]
}

@test "jq vs python3 byte-identical render (--dry-run, jq removed from PATH)" {
  jq_out="$("$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7 --dry-run)"
  dir="$BATS_TEST_TMPDIR/nojq-render"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_out" ]
}

@test "jq vs python3 byte-identical render (--json TSV projection)" {
  jq_out="$("$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7 --json)"
  dir="$BATS_TEST_TMPDIR/nojq-json"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7 --json
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_out" ]
}

@test "--json on an empty ledger: exit 0, empty stdout (no skip-note pollution)" {
  run "$SCRIPT" accessibility --file "$LEDGERS/empty.json" --pr 7 --json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$GH_LOG" ]
}

@test "--json on an all-dropped ledger still emits the projection rows" {
  # render_lens would skip (zero open) — the machine-readable projection must
  # still come out, including the dropped row.
  printf '{"lens":"accessibility","findings":[{"id":"D","severity":"Low","location":"a:1","summary":"x","status":"dropped"}]}' > "$WORK/alldrop.json"
  run "$SCRIPT" accessibility --file "$WORK/alldrop.json" --pr 7 --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"dropped"* ]]
  [[ "$output" == *"a:1"* ]]
  [ ! -f "$GH_LOG" ]
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
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X POST repos/acme/sample-api/issues/7/comments' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X PATCH' "$GH_LOG")" -eq 0 ]
  # Regression: the body MUST be sent via -F (reads stdin). gh's -f posts the
  # literal string "@-" instead of the rendered comment (caught in real-PR QA).
  grep -q 'api -X POST .* -F body=@-' "$GH_LOG"
  ! grep -q -- '-f body=@-' "$GH_LOG"
}

@test "idempotent UPDATE (second run): exactly one PATCH on the matched id, zero POST" {
  dir="$BATS_TEST_TMPDIR/route-update"
  route_gh "$dir" "acme/sample-api" "botuser" \
    "$(printf '555\tbotuser\t<!-- sdlc-review:accessibility --> prior body')"
  PATH="$dir:$PATH" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X PATCH repos/acme/sample-api/issues/comments/555' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X POST' "$GH_LOG")" -eq 0 ]
}

@test "duplicate-marker collapse: one PATCH on the oldest, never a third create" {
  # Two marker'd, author-matched comments (REST lists oldest-first: 555 then
  # 777). The poster must edit the oldest and never POST a new one.
  dir="$BATS_TEST_TMPDIR/route-dup"
  route_gh "$dir" "acme/sample-api" "botuser" \
    "$(printf '555\tbotuser\t<!-- sdlc-review:accessibility --> dup one\n777\tbotuser\t<!-- sdlc-review:accessibility --> dup two')"
  PATH="$dir:$PATH" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X PATCH repos/acme/sample-api/issues/comments/555' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X POST' "$GH_LOG")" -eq 0 ]
  # exactly one edit total — no second PATCH, no create
  [ "$(grep -cE 'api -X (POST|PATCH)' "$GH_LOG")" -eq 1 ]
}

@test "never uses gh pr comment --edit-last" {
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  ! grep -q -- '--edit-last' "$GH_LOG"
  ! grep -q 'pr comment' "$GH_LOG"
}

# ---------------------------------------------------------------------------
# Dedup + severity order — FR-4
# ---------------------------------------------------------------------------

@test "dedup by (wcag,location,surface): the pair collapses to one row" {
  run "$SCRIPT" accessibility --file "$LEDGERS/dedup-pair.json" --pr 7 --dry-run
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
  run "$SCRIPT" accessibility --file "$LEDGERS/dropped-and-open.json" --pr 7 --dry-run
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
  run "$SCRIPT" code-review --file "$LEDGERS/secret-laden.json" --pr 7 --dry-run
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

@test "redaction: --json TSV output is redacted too, not just the rendered body" {
  run "$SCRIPT" code-review --file "$LEDGERS/secret-laden.json" --pr 7 --json
  [ "$status" -eq 0 ]
  [[ "$output" != *"AKIAIOSFODNN7EXAMPLE"* ]]
  [[ "$output" != *"SflKxwRJSMeKKF2QT4fwpMeJf36"* ]]
  [[ "$output" != *"SuperSecretPw123"* ]]
  [[ "$output" != *"admin:hunter2"* ]]
  [[ "$output" == *"AKIA...REDACTED"* ]]
  [[ "$output" == *"password=REDACTED"* ]]
}

@test "redaction is identical on the python3 backend (no jq)" {
  jq_out="$("$SCRIPT" code-review --file "$LEDGERS/secret-laden.json" --pr 7 --dry-run)"
  dir="$BATS_TEST_TMPDIR/nojq-redact"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" code-review --file "$LEDGERS/secret-laden.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_out" ]
  [[ "$output" != *"AKIAIOSFODNN7EXAMPLE"* ]]
}

# ---------------------------------------------------------------------------
# Gating — FR-6 / NFR-6
# ---------------------------------------------------------------------------

@test "gating OFF: skip-note, exit 0, zero gh calls (even with --dry-run)" {
  flag_off
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"capabilities.publish_pr_comments is not true"* ]]
  [ ! -f "$GH_LOG" ]
}

@test "gating OFF honored by --dry-run: prints skip-note, does not render the body" {
  flag_off
  run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"capabilities.publish_pr_comments is not true"* ]]
  [[ "$output" != *"<!-- sdlc-review:accessibility -->"* ]]
}

@test "gating ON: proceeds to publish (a CREATE call is made)" {
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
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
  PATH="$dir" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
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
  PATH="$dir:$PATH" run "$SCRIPT" accessibility --file "$LEDGERS/full.json"
  [ "$status" -eq 0 ]
  [ "$(grep -cE 'api -X (POST|PATCH)' "$GH_LOG")" -eq 0 ]
}

@test "D4 empty ledger: skip-note, exit 0, zero gh calls" {
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" accessibility --file "$LEDGERS/empty.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"no open findings — skipping publish"* ]]
  [ ! -f "$GH_LOG" ]
}

@test "D4 all-dropped ledger (zero open after split): skip-note, exit 0, zero gh calls" {
  # a ledger whose ONLY finding is dropped has zero open rows after the
  # open/dropped split -> same D4 empty-ledger degrade, no empty comment.
  printf '{"lens":"accessibility","findings":[{"id":"D","severity":"Low","location":"a:1","summary":"x","status":"dropped"}]}' > "$WORK/alldrop.json"
  STUB_GH_OUTPUT="acme/sample-api" run "$SCRIPT" accessibility --file "$WORK/alldrop.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"no open findings — skipping publish"* ]]
  [ ! -f "$GH_LOG" ]
}

@test "D5 malformed comment-list read: warn, fall back to CREATE, exit 0" {
  # the list call returns junk (HTML proxy error); the dedup fails so the
  # poster creates without dedup rather than failing the loop (R11).
  dir="$BATS_TEST_TMPDIR/route-badlist"
  route_gh "$dir" "acme/sample-api" "botuser" "not a tsv line <html>502</html>"
  PATH="$dir:$PATH" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api -X POST repos/acme/sample-api/issues/7/comments' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'api -X PATCH' "$GH_LOG")" -eq 0 ]
}

@test "D6 base-repo mismatch: refuse-note, exit 0, zero write calls" {
  dir="$BATS_TEST_TMPDIR/route-mismatch"
  route_gh "$dir" "evil/other-repo" "botuser" ""
  PATH="$dir:$PATH" run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"base repo 'evil/other-repo' != resolved repo 'acme/sample-api'"* ]]
  [ "$(grep -cE 'api -X (POST|PATCH)' "$GH_LOG")" -eq 0 ]
}

@test "D7 gh write failure: warn, exit 0 (never fails the loop)" {
  # STUB_GH_EXIT=1 makes every gh call exit nonzero (but still print
  # STUB_GH_OUTPUT), so authorize/list read the slug fine and only the POST
  # fails -> the create-failed warn path.
  STUB_GH_OUTPUT="acme/sample-api" STUB_GH_EXIT=1 run "$SCRIPT" accessibility --file "$LEDGERS/full.json" --pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"create comment failed"* ]]
}

# ---------------------------------------------------------------------------
# Malformed per-lens ledger is the ONE non-degrade case — FR-3
# ---------------------------------------------------------------------------

@test "malformed per-lens ledger: hard die (exit 1), [react-sdlc][ERROR], no traceback" {
  printf 'this is not json {\n' > "$WORK/bad.json"
  run "$SCRIPT" accessibility --file "$WORK/bad.json" --pr 7 --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"[react-sdlc][ERROR]"* ]]
  [[ "$output" == *"malformed ledger"* ]]
  [[ "$output" != *"Traceback"* ]]
  [[ "$output" != *"jq: error"* ]]
}

@test "malformed per-lens ledger dies on the python3 backend too (no jq)" {
  printf '[1,2,3]\n' > "$WORK/wrongtype.json"
  dir="$BATS_TEST_TMPDIR/nojq-malformed"
  nojq_bin "$dir"
  PATH="$dir" run "$SCRIPT" accessibility --file "$WORK/wrongtype.json" --pr 7 --dry-run
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
  # full.json (accessibility): 1 Critical + 1 High + 1 Medium open, 1 dropped excluded => total 3
  [[ "$output" == *"| accessibility | 1 | 1 | 1 | 0 | 3 |"* ]]
  # minimal.json (fr-nfr): 1 Medium
  [[ "$output" == *"| fr-nfr | 0 | 0 | 1 | 0 | 1 |"* ]]
  # code-review absent -> zero row
  [[ "$output" == *"| code-review | 0 | 0 | 0 | 0 | 0 |"* ]]
  # all = 1/1/2/0 total 4
  [[ "$output" == *"| **all** | 1 | 1 | 2 | 0 | 4 |"* ]]
  # auto-fixed: accessibility has 1 (auto_fixed:true + regression_test) of 3
  [[ "$output" == *"| accessibility | 1 / 3 |"* ]]
  [[ "$output" == *"| fr-nfr | 0 / 1 |"* ]]
}

@test "conclusion count handling: the 20-digit-count fixture severity counts render exactly" {
  # 20-digit-count.json (fr-nfr): 2 High + 1 Medium open, no dropped.
  run "$SCRIPT" --conclusion --file "$LEDGERS/20-digit-count.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| fr-nfr | 0 | 2 | 1 | 0 | 3 |"* ]]
  [[ "$output" == *"| **all** | 0 | 2 | 1 | 0 | 3 |"* ]]
  [[ "$output" == *"| fr-nfr | 0 / 3 |"* ]]
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
  # only the accessibility ledger -> fr-nfr and code-review render explicit zero rows
  run "$SCRIPT" --conclusion --file "$LEDGERS/full.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| fr-nfr | 0 | 0 | 0 | 0 | 0 |"* ]]
  [[ "$output" == *"| code-review | 0 | 0 | 0 | 0 | 0 |"* ]]
  [[ "$output" == *"| accessibility | 1 | 1 | 1 | 0 | 3 |"* ]]
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

@test "conclusion duration: leading-zero --duration-seconds is decimal, never octal, never a crash" {
  # bash (( )) would read 011 as octal 9 and abort on 0090 (9 invalid in octal)
  run "$SCRIPT" --conclusion --file "$LEDGERS/minimal.json" --pr 7 --duration-seconds 011 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"11s"* ]]
  [[ "$output" != *"value too great for base"* ]]
  run "$SCRIPT" --conclusion --file "$LEDGERS/minimal.json" --pr 7 --duration-seconds 0090 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"1m 30s"* ]]
  [[ "$output" != *"value too great for base"* ]]
}

@test "conclusion stdin path cleans up its mktemp file" {
  tmpd="$BATS_TEST_TMPDIR/concl-tmpdir"
  mkdir -p "$tmpd"
  TMPDIR="$tmpd" run bash -c "\"$SCRIPT\" --conclusion --pr 7 --dry-run < \"$LEDGERS/full.json\""
  [ "$status" -eq 0 ]
  # the ledger was actually read before removal...
  [[ "$output" == *"| accessibility | 1 | 1 | 1 | 0 | 3 |"* ]]
  # ...and no stale mktemp file is left behind
  [ -z "$(ls -A "$tmpd")" ]
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
  CACHE="$BATS_TEST_TMPDIR/install-cache/react-frontend-sdlc"
  mkdir -p "$(dirname "$CACHE")"
  cp -r "$PLUGIN_ROOT" "$CACHE"
  STUB_GH_OUTPUT="acme/sample-api" CLAUDE_PLUGIN_ROOT="$CACHE" \
    run "$CACHE/scripts/post-review-findings.sh" accessibility --file "$LEDGERS/full.json" --pr 7
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
  run "$SCRIPT" accessibility --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}

@test "missing lens and no --conclusion: usage error" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"a lens"* || "$output" == *"--conclusion is required"* ]]
}

# --- Regression tests for the adversarial-critic findings --------------------

@test "regression: a pipe in a finding field is escaped, not table-breaking (FR-4)" {
  run "$SCRIPT" fr-nfr --file "$LEDGERS/pipe-and-distinct.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'has a \| pipe char'* ]]
  [[ "$output" != *'has a | pipe char'* ]]
}

@test "regression: distinct wcag-less findings at one location are NOT deduped away (FR-4)" {
  run "$SCRIPT" fr-nfr --file "$LEDGERS/pipe-and-distinct.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"| F1 |"* ]]
  [[ "$output" == *"| F2 |"* ]]
}

@test "regression: id-less wcag-less findings with distinct fields are NOT collapsed (FR-4)" {
  printf '{"lens":"code-review","findings":[{"severity":"High","location":"src/a.ts:1","summary":"FIRST-NOID"},{"severity":"High","location":"src/b.ts:9","summary":"SECOND-NOID"}]}' > "$WORK/noid.json"
  run "$SCRIPT" code-review --file "$WORK/noid.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIRST-NOID"* ]]
  [[ "$output" == *"SECOND-NOID"* ]]
}

@test "regression: identical id-less rows still dedupe to one row (FR-4)" {
  printf '{"lens":"code-review","findings":[{"severity":"High","location":"src/a.ts:1","summary":"SAME-NOID"},{"severity":"High","location":"src/a.ts:1","summary":"SAME-NOID"}]}' > "$WORK/noid-dup.json"
  run "$SCRIPT" code-review --file "$WORK/noid-dup.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  data_rows="$(printf '%s\n' "$output" | grep -cE '^\| (Critical|High|Medium|Low) ')"
  [ "$data_rows" -eq 1 ]
}

@test "regression: a normal digit-less location path is not over-redacted (FR-7)" {
  run "$SCRIPT" fr-nfr --file "$LEDGERS/pipe-and-distinct.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/modules/alpha/features/checkout/handler.ts:10"* ]]
}

@test "regression: conclusion duration falls back to ledger started_at/ended_at (FR-5/OQ-7)" {
  run "$SCRIPT" --conclusion --file "$LEDGERS/with-times.json" --pr 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Duration"* ]]
  [[ "$output" == *"5m 30s"* ]]
}
