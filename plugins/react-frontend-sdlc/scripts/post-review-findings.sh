#!/usr/bin/env bash
# post-review-findings.sh — publish review-lens findings as ONE consolidated,
# idempotent PR comment per lens (and an aggregate --conclusion comment).
#
# DEGRADE-FIRST CONTRACT (NFR-3 / FR-9): the DEFAULT failure mode of this
# script is skip-with-note + `exit 0`. It is the DELIBERATE INVERSE of the
# sibling get-pr-comments.sh (which DIES when gh is absent because it is a READ
# the finish-pr loop's exit condition depends on). This poster is
# fire-and-forget SIDE OUTPUT: capability flag off / gh absent / no PR / empty
# ledger / malformed gh read / mismatched base repo / gh write failure all
# DEGRADE to a logged note and exit 0 — they NEVER fail the loop. Do NOT
# "fix" this script to die on a missing capability or a write failure.
#
# Idempotent via a hidden HTML marker (<!-- sdlc-review:<lens> -->): it UPDATES
# its prior bot comment instead of spamming. Authorized: writes only to the
# origin/gh-resolved repo's OWN PR (a mismatched base repo is refused). Secrets
# in finding text are redacted before render. All conclusion arithmetic uses the
# wrap-safe common.sh digit-string helpers — never bash (( )) over counts.
#
# Usage:
#   post-review-findings.sh <lens> [--pr N] [--file F]... [--dry-run] [--json]
#   post-review-findings.sh --conclusion [--file F]... [--pr N] \
#       [--started-at ISO] [--ended-at ISO] [--duration-seconds N] [--iterations N]
#   lens: accessibility | fr-nfr | code-review
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

readonly MARKER_PREFIX="<!-- sdlc-review:"
readonly MARKER_SUFFIX=" -->"
readonly VALID_LENSES="accessibility fr-nfr code-review"

usage() {
  cat >&2 <<'EOF'
Usage:
  post-review-findings.sh <lens> [options]      # lens: accessibility | fr-nfr | code-review
  post-review-findings.sh --conclusion [options]

Options:
  --pr <n>               PR number (default: resolve from the current branch)
  --file <path>          ledger JSON file (repeatable; --conclusion takes one per lens)
  --bot-login <login>    posting identity for the author filter (default: gh api user)
  --started-at <iso>     loop start (ISO-8601 UTC) — conclusion duration source
  --ended-at <iso>       loop end (ISO-8601 UTC)   — conclusion duration source
  --duration-seconds <n> explicit duration (digit string)
  --iterations <n>       orchestrator loop iteration count (conclusion)
  --dry-run              render to stdout; make ZERO gh calls
  --json                 emit the render rows as TSV to stdout; ZERO gh calls
  -h, --help             this help
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing (mirrors get-pr-comments.sh: while/case, --x needs value).
# ---------------------------------------------------------------------------
LENS=""
MODE="lens"          # lens | conclusion
PR=""
FILES=()
BOT_LOGIN=""
STARTED_AT=""
ENDED_AT=""
DURATION_SECONDS=""
ITERATIONS=""
DRY_RUN=0
JSON_OUT=0

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --conclusion) MODE="conclusion" ;;
      --lens) LENS="${2:?--lens needs a value}"; shift ;;
      --pr) PR="${2:?--pr needs a value}"; shift ;;
      --file) FILES+=("${2:?--file needs a value}"); shift ;;
      --bot-login) BOT_LOGIN="${2:?--bot-login needs a value}"; shift ;;
      --started-at) STARTED_AT="${2:?--started-at needs a value}"; shift ;;
      --ended-at) ENDED_AT="${2:?--ended-at needs a value}"; shift ;;
      --duration-seconds) DURATION_SECONDS="${2:?--duration-seconds needs a value}"; shift ;;
      --iterations) ITERATIONS="${2:?--iterations needs a value}"; shift ;;
      --dry-run) DRY_RUN=1 ;;
      --json) JSON_OUT=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) usage; die "unknown argument: $1" ;;
      *)
        if [[ -z "$LENS" ]]; then
          LENS="$1"
        else
          usage; die "unexpected positional argument: $1"
        fi
        ;;
    esac
    shift
  done

  if [[ "$MODE" == "conclusion" ]]; then
    [[ -z "$LENS" ]] || die "--conclusion is mutually exclusive with a lens argument"
  else
    [[ -n "$LENS" ]] || { usage; die "a lens (accessibility | fr-nfr | code-review) or --conclusion is required"; }
    [[ " $VALID_LENSES " == *" $LENS "* ]] || { usage; die "unknown lens: $LENS"; }
  fi
}

marker_for() { printf '%s%s%s' "$MARKER_PREFIX" "$1" "$MARKER_SUFFIX"; }

# ---------------------------------------------------------------------------
# Capability gate — the FIRST real action (NFR-6 / FR-6). Default OFF.
# ---------------------------------------------------------------------------
gate_open() {
  local profile publish="false"
  profile="$(profile_path "$PWD")"
  if [[ -f "$profile" ]] && yaml_parses "$profile"; then
    publish="$(profile_get "$profile" capabilities.publish_pr_comments false)"
  fi
  [[ "$publish" == "true" ]]
}

# ---------------------------------------------------------------------------
# JSON -> TSV projection. The ONLY backend-variable step; everything after
# (redact, dedup, sort, render) is single-implementation bash so the rendered
# body is byte-identical with or without jq (FR-1/FR-4). One line per finding:
#   severity \t id \t wcag \t level \t location \t surface \t summary \t status \t auto_fixed \t regression_test
# Absent optional fields are emitted empty (bash renders them as n/a). Tabs and
# newlines inside values are squashed to spaces to keep the TSV well-formed.
# Exit 3 = not valid JSON / wrong top-level type / missing lens (caller decides
# die-vs-skip per mode).
# ---------------------------------------------------------------------------
ledger_to_tsv() {
  local src=$1
  if command -v jq >/dev/null 2>&1; then
    jq -r '
      def cell(v): (v // "") | tostring | gsub("[\t\n\r]"; " ");
      if type != "object" then "ERR_TYPE " | halt_error(3)
      elif (has("lens") and (.lens | type == "string") | not) then "ERR_LENS " | halt_error(3)
      else (.findings // [])[]
        | [ cell(.severity), cell(.id), cell(.wcag), cell(.level), cell(.location),
            cell(.surface), cell(.summary), cell(.status),
            (if .auto_fixed == true then "true" else "false" end), cell(.regression_test) ]
        | @tsv
      end
    ' "$src" 2>/dev/null || return 3
  else
    python3 - "$src" <<'PYEOF' || return 3
import json, sys
def cell(v):
    if v is None:
        return ""
    return str(v).replace("\t", " ").replace("\n", " ").replace("\r", " ")
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(3)
if not isinstance(data, dict):
    sys.exit(3)
if not isinstance(data.get("lens"), str):
    sys.exit(3)
out = []
for f in (data.get("findings") or []):
    if not isinstance(f, dict):
        continue
    af = "true" if f.get("auto_fixed") is True else "false"
    out.append("\t".join([
        cell(f.get("severity")), cell(f.get("id")), cell(f.get("wcag")),
        cell(f.get("level")), cell(f.get("location")), cell(f.get("surface")),
        cell(f.get("summary")), cell(f.get("status")), af, cell(f.get("regression_test")),
    ]))
sys.stdout.write("\n".join(out) + ("\n" if out else ""))
PYEOF
  fi
}

# read_ledger_from_stdin -> temp file (so the jq/python path takes a filename).
stdin_to_tmp() {
  local tmp; tmp="$(mktemp)"; cat - >"$tmp"; printf '%s' "$tmp"
}

# ---------------------------------------------------------------------------
# Redaction (single bash implementation; FR-7 / NFR-5). Documented shape set.
# Applied to the free-text fields before render. Order matters: specific
# shapes first, the bounded high-entropy run last.
# ---------------------------------------------------------------------------
# Single deterministic python pass (python3 is always available; one impl, no
# jq/sed dialect drift). The high-entropy catch-all requires a DIGIT in the run
# so ordinary long identifiers / path segments are not over-redacted; the
# keyword-assignment rule requires an >=8-char value so prose like "token: expired"
# is left alone. Specific shapes first, the bounded high-entropy run last.
redact() {
  # Program on fd 3 (not `python3 -`, which would read the PROGRAM from stdin
  # and swallow the piped data we must redact). stdin stays the data pipe.
  python3 /dev/fd/3 3<<'PYEOF'
import sys, re
data = sys.stdin.read()
rules = [
    (r'(AKIA|ASIA)[0-9A-Z]{16}', r'\1...REDACTED'),
    (r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', 'eyJ...REDACTED'),
    (r'(gh[pousr]_)[A-Za-z0-9]{20,}', r'\1REDACTED'),
    (r'(?i)(password|passwd|secret|token|apikey|api_key)(\s*[=:]\s*)(\S{8,})', r'\1\2REDACTED'),
    (r'([a-z][a-z0-9+.-]*://)[^/@\s:]+:[^/@\s]+@', r'\1REDACTED@'),
    (r'(?=[A-Za-z0-9+]{0,500}[0-9])[A-Za-z0-9+]{32,}={0,2}', 'REDACTED'),
]
for pat, repl in rules:
    data = re.sub(pat, repl, data)
sys.stdout.write(data)
PYEOF
}

# Canonicalize a severity label to its Title-case form (verbatim for unknown).
severity_label() {
  case "$(lower "$1")" in
    critical) printf 'Critical' ;;
    high)     printf 'High' ;;
    medium)   printf 'Medium' ;;
    low)      printf 'Low' ;;
    *)        printf '%s' "$1" ;;
  esac
}

# Escape Markdown table-breaking pipes so a `|` in a finding summary/location
# cannot inject phantom columns into the rendered table.
cell_or_na() {
  if [[ -n "$1" ]]; then
    printf '%s' "${1//|/\\|}"
  else
    printf 'n/a'
  fi
}

# ---------------------------------------------------------------------------
# Per-lens render (FR-4). Reads TSV on stdin, emits the Markdown comment body.
# Prints nothing and returns 1 when there are zero non-dropped findings (D4).
# ---------------------------------------------------------------------------
render_lens() {
  local lens=$1 pr=$2 tsv body open_rows dropped_rows
  tsv="$(cat -)"

  # Redact, then prefix each row with its severity rank for a stable sort and
  # dedup by (wcag|location|surface); drop the rank column once sorted.
  local sorted
  sorted="$(
    printf '%s' "$tsv" | redact | awk -F'\t' '
      NF >= 8 {
        rank = 9
        sev = tolower($1)
        if (sev=="critical") rank=0; else if (sev=="high") rank=1;
        else if (sev=="medium") rank=2; else if (sev=="low") rank=3
        # Collapse the a11y-style sink tuple (wcag,location,surface) to one
        # row; but a wcag-less finding (fr-nfr / code-review) keys on its unique
        # id so two distinct findings at the same location are NOT merged away.
        # Fold status ($8) into the key so a dropped row cannot dedup away an
        # open row with the same tuple (the open/dropped split happens AFTER
        # this pass, so an earlier dropped duplicate would otherwise hide a
        # publishable finding).
        key = ($3 != "" ? $3 "|" $5 "|" $6 : ($2 != "" ? "ID:" $2 : "NOID:" $5 "|" $6 "|" $7)) "|" tolower($8)
        if (!seen[key]++) print rank "\t" $0
      }' | sort -t$'\t' -k1,1n -k3,3 -k6,6 | cut -f2- | tr '\t' '\037'
  )"

  open_rows=""
  dropped_rows=""
  local n=0 nc=0 nh=0 nm=0 nl=0 nfixed=0
  local slabel row
  # US (\037) field sep, not tab: `read` collapses consecutive whitespace-IFS,
  # which would drop empty optional columns; US is non-whitespace so empties
  # are preserved and columns stay aligned.
  while IFS=$'\037' read -r sev id wcag level loc surface summary status autofix regt; do
    [[ -n "${sev:-}" ]] || continue
    slabel="$(severity_label "$sev")"
    row="| $slabel | $(cell_or_na "$id") | $(cell_or_na "$wcag") | $(cell_or_na "$level") | $(cell_or_na "$loc") | $(cell_or_na "$surface") | $(cell_or_na "$summary") |"
    if [[ "$(lower "$status")" == "dropped" ]]; then
      dropped_rows+="| $(cell_or_na "$id") | $(cell_or_na "$loc") | $(cell_or_na "$summary") |"$'\n'
    else
      open_rows+="$row"$'\n'
      n="$(num_add "$n" 1)"
      case "$(lower "$sev")" in
        critical) nc="$(num_add "$nc" 1)" ;;
        high) nh="$(num_add "$nh" 1)" ;;
        medium) nm="$(num_add "$nm" 1)" ;;
        low) nl="$(num_add "$nl" 1)" ;;
      esac
      [[ "$autofix" == "true" && -n "$regt" ]] && nfixed="$(num_add "$nfixed" 1)"
    fi
  done <<<"$sorted"

  [[ "$n" != "0" ]] || return 1   # D4: zero open findings → no comment

  local title
  case "$lens" in
    accessibility) title="Accessibility audit" ;;
    fr-nfr) title="BMAD FR/NFR review" ;;
    code-review) title="Code review" ;;
    *) title="$lens" ;;
  esac

  body="$(marker_for "$lens")"$'\n'
  body+="## SDLC Review — ${title} findings (PR #${pr})"$'\n\n'
  body+="| severity | id | wcag | level | location | surface | summary |"$'\n'
  body+="|---|---|---|---|---|---|---|"$'\n'
  body+="$open_rows"
  if [[ -n "$dropped_rows" ]]; then
    body+=$'\n'"### Dropped / not reproduced"$'\n'
    body+="| id | location | summary |"$'\n'
    body+="|---|---|---|"$'\n'
    body+="$dropped_rows"
  fi
  body+=$'\n'"_summary: ${n} findings (${nc} critical, ${nh} high, ${nm} medium, ${nl} low); ${nfixed} auto-fixed root-cause with regression test._"$'\n'
  printf '%s' "$body"
}

# ---------------------------------------------------------------------------
# gh publish: list → marker+author match → PATCH else POST (FR-2). All writes
# degrade to a warn + exit-0-friendly return (FR-9). Honors --dry-run.
# ---------------------------------------------------------------------------
resolve_repo() {
  local origin slug=""
  origin="$(git remote get-url origin 2>/dev/null || true)"
  [[ -n "$origin" ]] && slug="$(printf '%s\n' "$origin" | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')"
  [[ -n "$slug" ]] || slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  printf '%s' "$slug"
}

resolve_pr() {
  # Notes go to stderr: this function's stdout is command-substituted into the
  # caller's PR variable, so a stdout note would be swallowed (never surfaced).
  if [[ -n "$PR" ]]; then
    [[ "$PR" =~ ^[0-9]+$ ]] || { log_info "post-review-findings: --pr '$PR' is not numeric — skipping publish" >&2; return 1; }
    printf '%s' "$PR"; return 0
  fi
  local n; n="$(gh pr view --json number --jq .number 2>/dev/null || true)"
  [[ "$n" =~ ^[0-9]+$ ]] || { log_info "post-review-findings: no PR for the current branch — skipping publish" >&2; return 1; }
  printf '%s' "$n"
}

# authorize SLUG PR — exit 0 when the PR's base repo equals SLUG (in-scope).
authorize() {
  local slug=$1 pr=$2 base
  base="$(gh api "repos/$slug/pulls/$pr" --jq .base.repo.full_name 2>/dev/null || true)"
  if [[ -z "$base" ]]; then
    log_warn "post-review-findings: cannot read PR #$pr base repo — refusing to publish"; return 1
  fi
  if [[ "$(lower "$base")" != "$(lower "$slug")" ]]; then
    log_warn "post-review-findings: PR #$pr base repo '$base' != resolved repo '$slug' — refusing (in-scope only)"; return 1
  fi
}

publish() {
  local slug=$1 pr=$2 lens=$3 body=$4 marker login list
  marker="$(marker_for "$lens")"
  login="$BOT_LOGIN"
  [[ -n "$login" ]] || login="$(gh api user --jq .login 2>/dev/null || true)"
  # If the posting identity cannot be resolved we must NOT marker-only match —
  # that could edit a human comment that merely quotes the marker. With no
  # login the update path is disabled and a fresh comment is created instead.
  [[ -n "$login" ]] || log_warn "post-review-findings: posting identity unresolved (gh api user) — will create, not edit, to avoid touching a non-bot comment ($lens)"

  # List comments; gh's embedded --jq works without a system jq. A failed/empty
  # read degrades to "create without dedup" (D5). Body newlines/tabs are
  # squashed so each comment is one TSV line; the single-line marker survives
  # as a substring.
  # .body can be JSON null (review-state/attachment-only comments); guard it
  # (// "") so gsub never errors out — an error would empty the list and make
  # the poster create a duplicate every run instead of updating.
  list="$(gh api --paginate "repos/$slug/issues/$pr/comments" \
            --jq '.[] | [(.id|tostring), (.user.login // ""), ((.body // "") | gsub("[\n\r\t]"; " "))] | @tsv' 2>/dev/null || true)"

  # Collect ALL marker+author matches (corruption-tolerant), then edit the
  # OLDEST (lowest numeric id, compared wrap-safe) and minimize the rest.
  local -a ids=()
  if [[ -n "$list" ]]; then
    while IFS=$'\t' read -r cid clogin cbody; do
      [[ -n "${cid:-}" ]] || continue
      [[ "$cbody" == *"$marker"* ]] || continue
      # Require a resolved login that matches: never edit a comment whose author
      # we can't confirm is the posting identity (R7).
      if [[ -n "$login" && "$(lower "$clogin")" == "$(lower "$login")" ]]; then
        ids+=("$cid")
      fi
    done <<<"$list"
  fi

  if [[ ${#ids[@]} -eq 0 ]]; then
    if ! printf '%s' "$body" | gh api -X POST "repos/$slug/issues/$pr/comments" -F "body=@-" >/dev/null 2>&1; then
      log_warn "post-review-findings: create comment failed (HTTP/rate/abuse) — skipping ($lens)"
    fi
    return
  fi

  local ti=0 i
  for i in "${!ids[@]}"; do
    num_lt "${ids[$i]}" "${ids[$ti]}" && ti="$i"
  done
  if ! printf '%s' "$body" | gh api -X PATCH "repos/$slug/issues/comments/${ids[$ti]}" -F "body=@-" >/dev/null 2>&1; then
    log_warn "post-review-findings: update comment ${ids[$ti]} failed — skipping ($lens)"
  fi
  # Corruption recovery (rare): hide any surplus duplicate marker'd comments.
  # node_id is fetched lazily here so the common single-comment path needs only
  # the 3-field list read above.
  local nid
  for i in "${!ids[@]}"; do
    [[ "$i" == "$ti" ]] && continue
    nid="$(gh api "repos/$slug/issues/comments/${ids[$i]}" --jq .node_id 2>/dev/null || true)"
    [[ -n "$nid" ]] || continue
    # shellcheck disable=SC2016  # $id is a GraphQL variable, not a shell var
    gh api graphql -f query='mutation($id:ID!){minimizeComment(input:{subjectId:$id,classifier:OUTDATED}){clientMutationId}}' \
      -f id="$nid" >/dev/null 2>&1 || log_warn "post-review-findings: could not minimize duplicate comment ${ids[$i]} ($lens)"
  done
}

# ---------------------------------------------------------------------------
# Conclusion aggregation (FR-5 / NFR-4). Reads the lens ledgers, counts via
# wrap-safe num_add, renders the aggregate body.
# ---------------------------------------------------------------------------
human_duration() {
  local secs=$1 h m s out
  # Digit string only, and bounded (>12 digits is >31000 years — an absurd
  # crafted value; reject it rather than risk a (( )) wrap, NFR-4).
  [[ "$secs" =~ ^[0-9]+$ && ${#secs} -le 12 ]] || { printf 'n/a'; return; }
  secs=$(( 10#$secs ))
  h=$(( secs / 3600 )); m=$(( (secs % 3600) / 60 )); s=$(( secs % 60 ))
  if (( h > 0 )); then
    out="$(printf '%dh %02dm %02ds' "$h" "$m" "$s")"
  elif (( m > 0 )); then
    out="$(printf '%dm %02ds' "$m" "$s")"
  else
    out="$(printf '%ds' "$s")"
  fi
  printf '%s' "$out"
}

iso_to_epoch() {
  local iso=$1 e
  e="$(date -u -d "$iso" +%s 2>/dev/null || true)"
  [[ -n "$e" ]] || e="$(python3 -c 'import sys,datetime
try:
    print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))
except Exception:
    pass' "$iso" 2>/dev/null || true)"
  printf '%s' "$e"
}

compute_duration() {
  if [[ -n "$DURATION_SECONDS" && "$DURATION_SECONDS" =~ ^[0-9]+$ ]]; then
    human_duration "$DURATION_SECONDS"; return
  fi
  if [[ -n "$STARTED_AT" && -n "$ENDED_AT" ]]; then
    local s e; s="$(iso_to_epoch "$STARTED_AT")"; e="$(iso_to_epoch "$ENDED_AT")"
    if [[ "$s" =~ ^[0-9]+$ && "$e" =~ ^[0-9]+$ ]] && (( e >= s )); then
      human_duration "$(( e - s ))"; return
    fi
  fi
  printf 'n/a'
}

render_conclusion() {
  local pr=$1; shift
  local files=("$@")

  # OQ-7 fallback: with no explicit duration source from the orchestrator,
  # derive it from the ledgers' own started_at/ended_at (min start … max end).
  # ISO-8601 UTC 'Z' strings sort lexicographically, so min/max are sort-based.
  if [[ -z "$DURATION_SECONDS" && -z "$STARTED_AT" && -z "$ENDED_AT" ]]; then
    local tf st en starts="" ends=""
    for tf in "${files[@]}"; do
      [[ -f "$tf" ]] || continue
      st="$(ledger_field "$tf" started_at)"; en="$(ledger_field "$tf" ended_at)"
      [[ -n "$st" ]] && starts+="$st"$'\n'
      [[ -n "$en" ]] && ends+="$en"$'\n'
    done
    [[ -n "$starts" ]] && STARTED_AT="$(printf '%s' "$starts" | sort | head -1)"
    [[ -n "$ends" ]] && ENDED_AT="$(printf '%s' "$ends" | sort | tail -1)"
  fi

  declare -A C H M L FX TOT
  local lens
  for lens in accessibility fr-nfr code-review; do C[$lens]=0; H[$lens]=0; M[$lens]=0; L[$lens]=0; FX[$lens]=0; TOT[$lens]=0; done

  local f tsv
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    # Derive the lens from the ledger's own lens field via the projection's
    # sibling read; fall back to filename stem.
    local flens; flens="$(ledger_lens "$f")"
    [[ " $VALID_LENSES " == *" $flens "* ]] || continue
    tsv="$(ledger_to_tsv "$f" 2>/dev/null | tr '\t' '\037' || true)"
    [[ -n "$tsv" ]] || continue
    while IFS=$'\037' read -r sev id wcag level loc surface summary status autofix regt; do
      [[ -n "${sev:-}" ]] || continue
      [[ "$(lower "$status")" == "dropped" ]] && continue
      TOT[$flens]="$(num_add "${TOT[$flens]}" 1)"
      case "$(lower "$sev")" in
        critical) C[$flens]="$(num_add "${C[$flens]}" 1)" ;;
        high) H[$flens]="$(num_add "${H[$flens]}" 1)" ;;
        medium) M[$flens]="$(num_add "${M[$flens]}" 1)" ;;
        low) L[$flens]="$(num_add "${L[$flens]}" 1)" ;;
      esac
      [[ "$autofix" == "true" && -n "$regt" ]] && FX[$flens]="$(num_add "${FX[$flens]}" 1)"
    done <<<"$tsv"
  done

  local allC=0 allH=0 allM=0 allL=0 allT=0
  for lens in accessibility fr-nfr code-review; do
    allC="$(num_add "$allC" "${C[$lens]}")"; allH="$(num_add "$allH" "${H[$lens]}")"
    allM="$(num_add "$allM" "${M[$lens]}")"; allL="$(num_add "$allL" "${L[$lens]}")"
    allT="$(num_add "$allT" "${TOT[$lens]}")"
  done

  local body
  body="$(marker_for conclusion)"$'\n'
  body+="## SDLC Review — Conclusion (PR #${pr})"$'\n\n'
  body+="### Findings by lens × severity"$'\n'
  body+="| lens | Critical | High | Medium | Low | total |"$'\n'
  body+="|---|---|---|---|---|---|"$'\n'
  for lens in accessibility fr-nfr code-review; do
    body+="| ${lens} | ${C[$lens]} | ${H[$lens]} | ${M[$lens]} | ${L[$lens]} | ${TOT[$lens]} |"$'\n'
  done
  body+="| **all** | ${allC} | ${allH} | ${allM} | ${allL} | ${allT} |"$'\n\n'
  body+="### Auto-fixed root-cause (with regression test)"$'\n'
  body+="| lens | auto-fixed / total |"$'\n'
  body+="|---|---|"$'\n'
  for lens in accessibility fr-nfr code-review; do
    body+="| ${lens} | ${FX[$lens]} / ${TOT[$lens]} |"$'\n'
  done
  body+=$'\n'"### Iterations"$'\n'
  body+="overall (loop): $(cell_or_na "$ITERATIONS")"$'\n\n'
  body+="### Duration"$'\n'
  body+="$(compute_duration)"$'\n'
  printf '%s' "$body"
}

# ledger_field FILE KEY -> top-level string value ('' on error/absent/non-string).
ledger_field() {
  local f=$1 k=$2
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$k" 'if type=="object" and (.[$k]|type=="string") then .[$k] else "" end' "$f" 2>/dev/null || true
  else
    python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); v=d.get(sys.argv[2]) if isinstance(d,dict) else None
    print(v if isinstance(v,str) else "")
except Exception:
    print("")' "$f" "$k" 2>/dev/null || true
  fi
}

# ledger_lens FILE -> the .lens string ('' on error). gh-jq-free.
ledger_lens() {
  local f=$1
  if command -v jq >/dev/null 2>&1; then
    jq -r 'if type=="object" and (.lens|type=="string") then .lens else "" end' "$f" 2>/dev/null || true
  else
    python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); print(d["lens"] if isinstance(d,dict) and isinstance(d.get("lens"),str) else "")
except Exception:
    print("")' "$f" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"

  # NFR-6: gate is the first real action. Off/absent → skip-note, exit 0,
  # before any gh call (honored even by --dry-run / --json).
  if ! gate_open; then
    log_info "post-review-findings: capabilities.publish_pr_comments is not true — skipping publish (opt-in, default off)"
    exit 0
  fi

  if [[ "$MODE" == "conclusion" ]]; then
    run_conclusion
  else
    run_lens
  fi
}

run_lens() {
  # Resolve the ledger source (--file or stdin).
  local src cleanup=""
  if [[ ${#FILES[@]} -gt 0 ]]; then
    src="${FILES[0]}"
    [[ -f "$src" ]] || die "ledger file not found: $src"
  else
    src="$(stdin_to_tmp)"; cleanup="$src"
  fi

  # Project + validate. A malformed per-lens ledger is a hard die (FR-3).
  local tsv rc
  tsv="$(ledger_to_tsv "$src")" && rc=0 || rc=$?
  [[ -n "$cleanup" ]] && rm -f "$cleanup"
  [[ "$rc" -eq 0 ]] || die "malformed ledger (not JSON / wrong top-level type / missing lens): ${FILES[0]:-<stdin>}"

  if [[ "$JSON_OUT" -eq 1 ]]; then
    [[ -z "$tsv" ]] || printf '%s\n' "$tsv" | redact
    exit 0
  fi

  local body
  if ! body="$(printf '%s' "$tsv" | render_lens "$LENS" "${PR:-0}")"; then
    log_info "post-review-findings: ledger for lens '$LENS' has no open findings — skipping publish"
    exit 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then printf '%s\n' "$body"; exit 0; fi

  command -v gh >/dev/null 2>&1 || { log_info "post-review-findings: gh not on PATH — skipping publish"; exit 0; }
  local slug pr
  slug="$(resolve_repo)"; [[ -n "$slug" ]] || { log_info "post-review-findings: cannot resolve repository — skipping publish"; exit 0; }
  pr="$(resolve_pr)" || exit 0
  # Re-render the body with the real PR number in the header.
  body="$(printf '%s' "$tsv" | render_lens "$LENS" "$pr")" || exit 0
  authorize "$slug" "$pr" || exit 0
  publish "$slug" "$pr" "$LENS" "$body"
  exit 0
}

run_conclusion() {
  local files=()
  if [[ ${#FILES[@]} -gt 0 ]]; then
    files=("${FILES[@]}")
  else
    local tmp; tmp="$(stdin_to_tmp)"; files=("$tmp")
    trap 'rm -f "$tmp"' EXIT
  fi

  local body pr="${PR:-0}"
  if [[ "$DRY_RUN" -eq 1 || "$JSON_OUT" -eq 1 ]]; then
    body="$(render_conclusion "$pr" "${files[@]}")"
    printf '%s\n' "$body"; exit 0
  fi

  command -v gh >/dev/null 2>&1 || { log_info "post-review-findings: gh not on PATH — skipping conclusion"; exit 0; }
  local slug
  slug="$(resolve_repo)"; [[ -n "$slug" ]] || { log_info "post-review-findings: cannot resolve repository — skipping conclusion"; exit 0; }
  pr="$(resolve_pr)" || exit 0
  authorize "$slug" "$pr" || exit 0
  body="$(render_conclusion "$pr" "${files[@]}")"
  publish "$slug" "$pr" conclusion "$body"
  exit 0
}

main "$@"
