#!/usr/bin/env bash
# pr-state.sh — one snapshot of a pull request's finishing state, turned into exactly one verdict and its next step (FR-38).
#
# Usage: pr-state.sh [--pr N] [--reviewers LIST] [--required-checks LIST] [--human-gated-checks LIST] [--wait-seconds S] [--interval-seconds S] [--wait-verdicts LIST] [--json]
#   --pr N                     pull-request number, ^[1-9][0-9]*$ up to
#                              2147483647; default: the current branch's pull
#                              request (gh pr view --json number --jq .number)
#   --reviewers LIST           comma-separated AI reviewers whose approval the
#                              verdict requires, from coderabbit cubic qodo
#                              qlty sonarcloud, no duplicate and no empty
#                              element; an empty LIST means no reviewer
#                              (default: review.reviewers of the profile)
#   --required-checks LIST     comma-separated GitHub check names (spaces
#                              allowed), matched exactly and case-sensitively
#                              against the check-run name; narrows the CI
#                              scope to LIST (default: ci.required_checks of
#                              the profile, which count as required without
#                              narrowing the scope; an empty LIST names no
#                              check and keeps that default)
#   --human-gated-checks LIST  comma-separated check names that only a
#                              maintainer's approval label unblocks
#                              (default: ci.human_gated of the profile)
#   --wait-seconds S           keep re-reading while the verdict is in the
#                              wait set, for at most S seconds (default 0:
#                              one snapshot)
#   --interval-seconds S       pause between reads in wait mode (default 60;
#                              at least 1 when --wait-seconds is not 0)
#   --wait-verdicts LIST       verdicts that keep wait mode polling, from
#                              WAIT REQUEST FIX (default WAIT)
#   --json                     print the snapshot as one JSON object
#   --help                     print this help and exit 0 (accepted in any position)
#
# The profile is .claude/rust-sdlc.yml at the repository root; an absent
# profile leaves every default list empty (with a warning). --reviewers or
# --human-gated-checks given with an empty LIST is an explicit empty list and
# overrides the profile; --required-checks with an empty LIST is no explicit
# list, so ci.required_checks still counts (an empty override would let zero
# reported checks pass as "no CI").
#
# Each snapshot reads the PR (gh pr view), its reviews and issue comments (gh
# api, paginated), the push time of the head (its check suites) and the
# unresolved review threads (get-pr-comments.sh --pr N --unresolved-only
# --json), then classifies every reviewer against the CURRENT head commit:
#   APPROVED      latest live review is on the head and approves
#   NOT_APPROVED  latest live review is on the head and does not approve
#   REQUESTED     a review mention was posted after the head was pushed and
#                 the bot has not reviewed the head yet (ack=yes|no)
#   STALE         the bot last reviewed an older commit
#   NONE          the bot has never reviewed this PR
#   SKIPPED       no mention can reach the bot (paused seat, oversized diff,
#                 status-check bot, push-only reviewer)
# The commit status 'BMAD FR/NFR Review Gate' is judged on its own, as
# success, failure, pending or missing; no list waives it.
# CI: failing and pending checks are judged over the CI scope (the explicit
# --required-checks list, else every reported check); every required check
# (explicit, else ci.required_checks) not reported yet is missing, so a PR
# that reports no check yet while a required list is set is pending, never
# "no CI". CI is `none` (D8, SKIPPED-NO-CI) only when ci.provider is null,
# or when both lists are empty, and the PR reports no checks.
# Exactly one verdict, highest priority first:
#   BLOCKED  the PR is merged or closed, CONFLICTING, or a human-gated check
#            fails: NEXT names the approval label mapped to that check by the
#            "Labels to create" tables of docs/repository-settings.md and
#            docs/repository-settings-service.md (the plugin never applies a
#            label); with no mapped label, NEXT says to apply the approval
#            label named in docs/repository-settings.md
#   FIX      a check in the CI scope failed, or review threads are unresolved
#   GATE     the FR/NFR gate status is missing or failed on the head: NEXT
#            names the rs-sdlc-fr-nfr-review workflow
#   REQUEST  a reviewer needs a (re-)review mention: NEXT is the
#            request-ai-reviews.sh command line
#   WAIT     checks, the gate status or a requested review are in flight:
#            NEXT is pr-state.sh --pr <n> --wait-seconds 540
#   READY    CI green or none, gate green on the head, no unresolved thread,
#            every reachable reviewer approves the head (when every reviewer
#            is SKIPPED, NEXT names /rs-sdlc-review as the review source)
# Text output: `PR:`, `HEAD:`, `CI:`, `FR_NFR_GATE:`, `UNRESOLVED:`, one
# `REVIEWER:` line per reviewer, `HUMAN_GATED:`, one `INFO:` line per note,
# then `VERDICT: <verdict>` and `NEXT: <hint>`. --json prints the keys ci,
# draft, fr_nfr, head, human_gated, mergeable, next, notes, pr, repo,
# reviewers, state, unresolved, url, verdict (sorted, 2-space indent).
# SDLC_NOW_EPOCH fixes "now" for tests; under it the wait-mode clock is
# virtual: each pause advances it by the interval without sleeping. Nothing
# is written outside a private temporary directory removed on exit.
#
# Exit: 0 a snapshot was rendered (the verdict is data, whatever it is); 1 usage error (unknown flag, missing or invalid value; react parity, ADR-23), gh or python3 absent, no pull request, unresolvable repository, gh failure or malformed gh output, invalid profile (a consumed required key omitted: ci.provider, ci.required_checks, ci.human_gated or review.reviewers)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# GraphQL Int bound shared with get-pr-comments.sh.
PS_PR_MAX=2147483647
PS_KNOWN_REVIEWERS="coderabbit,cubic,qodo,qlty,sonarcloud"

# --- helpers -----------------------------------------------------------------

# ps_shown VALUE — VALUE without control characters, for diagnostics.
ps_shown() {
  printf '%s' "${1//[[:cntrl:]]/}"
}

# ps_usage_error MSG... — usage errors exit 1 here, not 2 (react parity,
# ADR-23).
ps_usage_error() {
  die "$* (usage: $(_sdlc_usage_line "$0"))"
}

# ps_flag_value FLAG ARGC VALUE — FLAG must be followed by a value that does
# not start with `--`.
ps_flag_value() {
  if [[ "$2" -lt 2 || "$3" == --* ]]; then
    ps_usage_error "$1 needs a value"
  fi
}

# ps_lines_from_commas LIST — the elements of the comma-separated LIST, one
# per line, empty elements dropped, every character kept (no trimming).
ps_lines_from_commas() {
  local list="$1" item
  while [[ -n "$list" ]]; do
    item="${list%%,*}"
    if [[ -n "$item" ]]; then
      printf '%s\n' "$item"
    fi
    if [[ "$list" == *,* ]]; then
      list="${list#*,}"
    else
      list=""
    fi
  done
}

# ps_check_reviewers SOURCE LIST — LIST (comma-separated) names known
# reviewers, without duplicates or empty elements; an empty LIST is valid.
# SOURCE is the flag (a usage error) or the profile key (a plain failure).
ps_check_reviewers() {
  local src="$1" list="$2" r seen="," fail=ps_usage_error
  [[ "$src" == --* ]] || fail=die
  [[ -n "$list" ]] || return 0
  [[ "$list" =~ ^[a-z]+(,[a-z]+)*$ ]] ||
    "$fail" "$src must be a comma-separated list without empty elements, got: $(ps_shown "$list")"
  for r in ${list//,/ }; do
    case ",$PS_KNOWN_REVIEWERS," in
      *",$r,"*) ;;
      *) "$fail" "unknown reviewer '$r' in $src (known: $PS_KNOWN_REVIEWERS)" ;;
    esac
    if [[ "$seen" == *",$r,"* ]]; then
      "$fail" "duplicate reviewer '$r' in $src"
    fi
    seen+="$r,"
  done
}

# ps_valid_pr S — S is a pull-request number GraphQL can carry.
ps_valid_pr() {
  [[ "${1-}" =~ ^[1-9][0-9]*$ ]] && ! num_gt "$1" "$PS_PR_MAX"
}

# --- arguments -----------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done

PR=""
REVIEWERS=""
REVIEWERS_SET=0
REQUIRED_ARG=""
REQUIRED_SET=0
HUMAN_ARG=""
HUMAN_SET=0
WAIT_SECONDS=0
INTERVAL=60
WAIT_VERDICTS="WAIT"
JSON_OUT=0
while (($#)); do
  case "$1" in
    --pr)
      ps_flag_value "$1" "$#" "${2-}"
      PR="$2"
      shift 2
      ;;
    --reviewers)
      ps_flag_value "$1" "$#" "${2-}"
      REVIEWERS="$2"
      REVIEWERS_SET=1
      shift 2
      ;;
    --required-checks)
      ps_flag_value "$1" "$#" "${2-}"
      REQUIRED_ARG="$2"
      REQUIRED_SET=1
      shift 2
      ;;
    --human-gated-checks)
      ps_flag_value "$1" "$#" "${2-}"
      HUMAN_ARG="$2"
      HUMAN_SET=1
      shift 2
      ;;
    --wait-seconds)
      ps_flag_value "$1" "$#" "${2-}"
      WAIT_SECONDS="$2"
      shift 2
      ;;
    --interval-seconds)
      ps_flag_value "$1" "$#" "${2-}"
      INTERVAL="$2"
      shift 2
      ;;
    --wait-verdicts)
      ps_flag_value "$1" "$#" "${2-}"
      WAIT_VERDICTS="$2"
      shift 2
      ;;
    --json)
      JSON_OUT=1
      shift
      ;;
    *) ps_usage_error "unknown argument: $(ps_shown "$1")" ;;
  esac
done

[[ "$WAIT_SECONDS" =~ ^(0|[1-9][0-9]*)$ ]] ||
  ps_usage_error "--wait-seconds must be a non-negative integer without leading zeros, got: $(ps_shown "$WAIT_SECONDS")"
[[ "$INTERVAL" =~ ^(0|[1-9][0-9]*)$ ]] ||
  ps_usage_error "--interval-seconds must be a non-negative integer without leading zeros, got: $(ps_shown "$INTERVAL")"
if [[ "$WAIT_SECONDS" != 0 && "$INTERVAL" == 0 ]]; then
  ps_usage_error "--interval-seconds must be at least 1 when --wait-seconds is set"
fi
[[ "$WAIT_VERDICTS" =~ ^(WAIT|REQUEST|FIX)(,(WAIT|REQUEST|FIX))*$ ]] ||
  ps_usage_error "--wait-verdicts must list WAIT, REQUEST and/or FIX, got: $(ps_shown "$WAIT_VERDICTS")"
if ((REVIEWERS_SET)); then
  ps_check_reviewers --reviewers "$REVIEWERS"
fi
if [[ -n "$PR" ]] && ! ps_valid_pr "$PR"; then
  ps_usage_error "--pr must be a pull-request number (^[1-9][0-9]*$, at most $PS_PR_MAX), got: $(ps_shown "$PR")"
fi
START="$(now_epoch)"

# --- environment -----------------------------------------------------------------

have_cmd gh || die "gh CLI not found on PATH: install the GitHub CLI to read the pull request"
have_cmd python3 || die "python3 is required to evaluate the pull-request state"

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || TOP=""
[[ -n "$TOP" ]] || TOP="$(pwd -P)"
PROFILE="$(profile_path "$TOP")"

# Lists one item per line. An empty --required-checks names no check, so it
# is no explicit list (react parity) and ci.required_checks still applies:
# overriding it with nothing would turn zero reported checks into "no CI"
# (D8 needs the explicit and the profile list both empty; NFR-3).
REQUIRED_LIST=""
HUMAN_LIST=""
if ((REQUIRED_SET)); then
  REQUIRED_LIST="$(ps_lines_from_commas "$REQUIRED_ARG")"
  # Control characters are dropped before matching, so they name no check.
  if [[ -z "${REQUIRED_LIST//[[:cntrl:]]/}" ]]; then
    REQUIRED_SET=0
    REQUIRED_LIST=""
  fi
fi
if ((HUMAN_SET)); then
  HUMAN_LIST="$(ps_lines_from_commas "$HUMAN_ARG")"
fi

# ps_require_key KEY — die when the required profile KEY is omitted. "Null
# means absent; omitted means error": an omitted key must never be read as
# null or as an empty list, which would fake D8 or drop the required checks.
ps_require_key() {
  local type
  type="$(yaml_type "$PROFILE" "$1")" || die "cannot read $1 from $PROFILE"
  if [[ "$type" == absent ]]; then
    die "profile: required key '$1' missing in $PROFILE: run validate-profile.sh"
  fi
}

# Defaults from the profile; provider null → D8.
PROVIDER_NULL=0
if [[ -f "$PROFILE" ]]; then
  ps_require_key ci.provider
  provider_type="$(yaml_type "$PROFILE" ci.provider)" ||
    die "cannot read ci.provider from $PROFILE"
  if [[ "$provider_type" == null ]]; then
    PROVIDER_NULL=1
  fi
  ((REVIEWERS_SET)) || ps_require_key review.reviewers
  ((REQUIRED_SET)) || ps_require_key ci.required_checks
  ((HUMAN_SET)) || ps_require_key ci.human_gated
  if ((!REVIEWERS_SET)); then
    profile_reviewers="$(yaml_get_list "$PROFILE" review.reviewers)" ||
      die "cannot read review.reviewers from $PROFILE"
    REVIEWERS="${profile_reviewers//$'\n'/,}"
    ps_check_reviewers "review.reviewers of $PROFILE" "$REVIEWERS"
  fi
  if ((!REQUIRED_SET)); then
    REQUIRED_LIST="$(yaml_get_list "$PROFILE" ci.required_checks)" ||
      die "cannot read ci.required_checks from $PROFILE"
  fi
  if ((!HUMAN_SET)); then
    HUMAN_LIST="$(yaml_get_list "$PROFILE" ci.human_gated)" ||
      die "cannot read ci.human_gated from $PROFILE"
  fi
elif ((!REVIEWERS_SET || !REQUIRED_SET || !HUMAN_SET)); then
  log_warn "no profile at $PROFILE: every list not given as a flag defaults to empty"
fi

if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq .number 2>/dev/null)" ||
    die "no pull request found for the current branch: pass --pr N"
  ps_valid_pr "$PR" ||
    die "gh pr view returned an invalid pull-request number: '$(ps_shown "$PR")': pass --pr N"
fi

SLUG="$(resolve_repo_slug)" ||
  die "cannot resolve the repository: no github.com origin remote and gh repo view failed"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr-state.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

# Label of each human-gated check name, from the template's documents.
if ! human_gated_labels "$TOP" >"$WORK/labels.tsv"; then
  log_warn "cannot read the approval labels from $TOP/docs/repository-settings.md"
  : >"$WORK/labels.tsv"
fi

# --- snapshot --------------------------------------------------------------------

# ps_snapshot NOW — read the PR once into $WORK and print the rendered
# snapshot; the verdict is also written to $WORK/verdict. A gh failure or a
# malformed payload exits 1 from inside.
ps_snapshot() {
  local now="$1" head
  gh pr view "$PR" --repo "$SLUG" \
    --json number,url,state,isDraft,mergeable,headRefOid,commits,statusCheckRollup >"$WORK/pr.json" ||
    die "gh pr view failed for PR #$PR in $SLUG"
  gh api "repos/$SLUG/pulls/$PR/reviews?per_page=100" --paginate \
    --jq '.[] | {user: .user.login, state: .state, commit_id: .commit_id, submitted_at: .submitted_at}' \
    >"$WORK/reviews.ndjson" ||
    die "gh api failed listing reviews for PR #$PR in $SLUG"
  gh api "repos/$SLUG/issues/$PR/comments?per_page=100" --paginate \
    --jq '.[] | {user: .user.login, body: .body, created_at: .created_at}' \
    >"$WORK/comments.ndjson" ||
    die "gh api failed listing comments for PR #$PR in $SLUG"
  "$SCRIPT_DIR/get-pr-comments.sh" --pr "$PR" --unresolved-only --json >"$WORK/threads.json" ||
    die "get-pr-comments.sh failed for PR #$PR"
  # The head's push moment: check suites are created when the commit reaches
  # GitHub, so the earliest suite dates the push; the commit's own timestamp
  # is only the fallback (a mention posted between commit and push must not
  # read as a request for that head).
  head="$(json_get "$WORK/pr.json" headRefOid)" ||
    die "gh pr view returned malformed JSON for PR #$PR in $SLUG"
  if [[ -n "$head" && ! "$head" =~ ^[0-9a-f]{7,64}$ ]]; then
    die "gh pr view returned a malformed head commit for PR #$PR: '$(ps_shown "$head")'"
  fi
  if [[ -n "$head" ]]; then
    gh api "repos/$SLUG/commits/$head/check-suites?per_page=100" \
      --jq '[.check_suites[]? | .created_at] | map(select(. != null)) | min // empty' >"$WORK/pushed_at" ||
      die "gh api failed listing check suites for commit $head in $SLUG (the push boundary cannot be dated; retry)"
  else
    : >"$WORK/pushed_at"
  fi
  python3 -I - "$WORK" "$SLUG" "$PR" "$REVIEWERS" "$REQUIRED_LIST" "$REQUIRED_SET" \
    "$HUMAN_LIST" "$PROVIDER_NULL" "$now" "$JSON_OUT" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone

(work, repo, pr_arg, reviewers_arg, required_arg, required_set, human_arg,
 provider_null_arg, now_arg, json_out) = sys.argv[1:11]
CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f]")


def fail(message):
    sys.stderr.write("[rust-sdlc][ERROR] %s\n" % message)
    sys.exit(1)


def clean(value):
    if value is None:
        return ""
    return CTRL.sub("", value if isinstance(value, str) else str(value))


def epoch(ts):
    try:
        return int(datetime.strptime(ts or "", "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    except (TypeError, ValueError):
        return 0


def load_json(name, what):
    try:
        with open(f"{work}/{name}", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, ValueError) as exc:
        fail(f"malformed {what} for PR #{pr_arg} in {repo}: {(str(exc).splitlines() or ['invalid JSON'])[0]}")
    if not isinstance(value, dict):
        fail(f"malformed {what} for PR #{pr_arg} in {repo}: not a JSON object")
    return value


def load_ndjson(name, what):
    out = []
    try:
        with open(f"{work}/{name}", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line:
                    item = json.loads(line)
                    if not isinstance(item, dict):
                        raise ValueError("a line is not a JSON object")
                    out.append(item)
    except (OSError, ValueError) as exc:
        fail(f"malformed {what} for PR #{pr_arg} in {repo}: {(str(exc).splitlines() or ['invalid JSON'])[0]}")
    return out


def as_list(value):
    return value if isinstance(value, list) else []


reviewers = [r for r in reviewers_arg.split(",") if r]
# Check names come from the profile or a flag: cleaned like the check-run
# names they are matched against, so none prints a control character.
required = [n for n in (clean(c) for c in required_arg.split("\n")) if n]
human = [n for n in (clean(c) for c in human_arg.split("\n")) if n]
provider_null = provider_null_arg == "1"
now = int(now_arg)
pr_number = int(pr_arg)

pr = load_json("pr.json", "gh pr view output")
reviews = load_ndjson("reviews.ndjson", "review list")
comments = load_ndjson("comments.ndjson", "issue-comment list")
threads = load_json("threads.json", "get-pr-comments.sh output")
labels = {}
with open(f"{work}/labels.tsv", encoding="utf-8") as handle:
    for line in handle:
        label, _, check = line.rstrip("\n").partition("\t")
        label, check = clean(label), clean(check)
        if label and check:
            labels.setdefault(check, label)

head = clean(pr.get("headRefOid"))
commits = [c for c in as_list(pr.get("commits")) if isinstance(c, dict)]
commit_epoch = max([epoch(c.get("committedDate")) for c in commits] or [0])
with open(f"{work}/pushed_at", encoding="utf-8") as handle:
    pushed_at = handle.read().strip().strip('"')
head_epoch = max(commit_epoch, epoch(pushed_at)) if pushed_at else commit_epoch
notes = []

# --- CI -----------------------------------------------------------------
PASSING = {"SUCCESS", "NEUTRAL", "SKIPPED"}
FAILING = {"FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"}
checks = {}
for c in as_list(pr.get("statusCheckRollup")):
    if not isinstance(c, dict):
        continue
    name = clean(c.get("name") or c.get("context") or "?")
    if c.get("__typename") == "StatusContext":
        verdict = c.get("state") or "PENDING"
    elif (c.get("status") or "") != "COMPLETED":
        verdict = "PENDING"
    else:
        verdict = c.get("conclusion") or "PENDING"
    checks[name] = clean(verdict)
# The FR/NFR gate is judged on its own (mandatory for every PR, never waived
# by a list), so ci-fixer is never handed a status it cannot fix from logs.
GATE_CONTEXT = "BMAD FR/NFR Review Gate"
gate_verdict = checks.pop(GATE_CONTEXT, None)
# An explicit --required-checks naming only the gate still narrows the CI
# scope (to nothing) instead of falling back to every check.
required_explicit = required_set == "1" and bool(required)
required = [c for c in required if c != GATE_CONTEXT]
human = [c for c in human if c != GATE_CONTEXT]
if gate_verdict is None:
    fr_nfr_status = "missing"
elif gate_verdict == "SUCCESS":
    fr_nfr_status = "success"
elif gate_verdict in FAILING:
    fr_nfr_status = "failure"
else:
    fr_nfr_status = "pending"
fr_nfr = {"context": GATE_CONTEXT, "status": fr_nfr_status}
scope = required if required_explicit else list(checks)
failing = sorted(n for n in scope if checks.get(n) in FAILING)
pending = sorted(n for n in scope if n in checks and checks[n] not in FAILING and checks[n] not in PASSING)
# Required checks not reported yet are missing (pending), the profile's list
# included: right after a push GitHub reports no check runs, and reading that
# as "no CI" would fake a pass. With no CI provider nothing will report them.
missing = [] if provider_null else sorted(n for n in required if n not in checks)
if not checks and (provider_null or (not required_explicit and not required)):
    ci_status = "none"
    why = "ci.provider is null" if provider_null else "no required check is listed"
    notes.append(f"CI: the PR reports no checks and {why} — the CI half of the exit condition is "
                 "satisfied-with-report, not verified (D8: SKIPPED-NO-CI)")
elif failing:
    ci_status = "red"
elif pending or missing:
    ci_status = "pending"
else:
    ci_status = "green"
if provider_null and checks:
    notes.append("CI: ci.provider is null — required checks are not awaited; the reported checks are judged")

# --- human-gated checks ---------------------------------------------------
gated_failing = sorted(n for n in human if checks.get(n) in FAILING)
human_gated = {"checks": human, "failing": gated_failing, "labels": {n: labels.get(n) for n in human}}
gated_labels = []
gated_unmapped = []
for n in gated_failing:
    if labels.get(n):
        if labels[n] not in gated_labels:
            gated_labels.append(labels[n])
    else:
        gated_unmapped.append(n)
for n in gated_failing:
    who = f"the label {labels[n]}" if labels.get(n) else "the approval label named in docs/repository-settings.md"
    notes.append(f"{n}: failing human-gated check — a maintainer applies {who}; "
                 "the plugin never applies a label and never re-runs or fixes this check")

# --- unresolved threads ---------------------------------------------------
BOTS = {
    "coderabbit": "coderabbitai",
    "cubic": "cubic-dev-ai",
    "qodo": "qodo-code-review",
    "qlty": "qltysh",
    "sonarcloud": "sonarqubecloud",
}
LOGIN_TO_NAME = {v: k for k, v in BOTS.items()}


def norm_login(login):
    login = (login if isinstance(login, str) else "").lower()
    return login[:-5] if login.endswith("[bot]") else login


by_reviewer = {}
unresolved = 0
for t in as_list(threads.get("review_threads")):
    if not isinstance(t, dict) or t.get("is_resolved"):
        continue
    unresolved += 1
    first = (as_list(t.get("comments")) or [{}])[0]
    who = LOGIN_TO_NAME.get(norm_login(first.get("author") if isinstance(first, dict) else ""), "other")
    by_reviewer[who] = by_reviewer.get(who, 0) + 1

# --- reviewers -----------------------------------------------------------
MENTIONS = {
    "coderabbit": ("@coderabbitai review", "@coderabbitai full review"),
    "cubic": ("@cubic-dev-ai review",),
}
comments.sort(key=lambda c: epoch(c.get("created_at")))
reviews.sort(key=lambda r: epoch(r.get("submitted_at")))


def body_of(c):
    body = (c or {}).get("body")
    return body if isinstance(body, str) else ""


reviewer_rows = []
for name in reviewers:
    login = BOTS[name]
    row = {"name": name, "status": None, "on_head": False, "ack": None, "reason": None}
    bot_comments = [c for c in comments if norm_login(c.get("user")) == login]
    last_bot_comment = bot_comments[-1] if bot_comments else None
    body = body_of(last_bot_comment)
    if name in ("qlty", "sonarcloud"):
        row.update(status="SKIPPED", reason="status-check bot — re-runs on push, has no mention command and never approves")
    elif name == "qodo" and last_bot_comment and "paused" in body.lower():
        row.update(status="SKIPPED", reason="reviews are paused for this account (lapsed subscription)")
    elif name == "coderabbit" and last_bot_comment and "review skipped" in body.lower() and "exceed the limit of" in body \
            and epoch(last_bot_comment.get("created_at")) >= head_epoch:
        row.update(status="SKIPPED", reason="diff exceeds CodeRabbit's changed-file limit; split the PR")
    else:
        live = [r for r in reviews if norm_login(r.get("user")) == login and r.get("state") != "DISMISSED"]
        latest = live[-1] if live else None
        on_head = bool(latest and latest.get("commit_id") == head)
        row["on_head"] = on_head
        if on_head and latest.get("state") == "APPROVED":
            row["status"] = "APPROVED"
        elif on_head:
            row["status"] = "NOT_APPROVED"
            row["reason"] = f"latest review on the head is {clean(latest.get('state'))}"
        else:
            mention_after_head = None
            for c in comments:
                lead = body_of(c).lstrip().lower()
                if name in MENTIONS and any(lead.startswith(m) for m in MENTIONS[name]) \
                        and epoch(c.get("created_at")) >= head_epoch:
                    mention_after_head = c
            if mention_after_head:
                row["status"] = "REQUESTED"
                row["ack"] = any(epoch(c.get("created_at")) >= epoch(mention_after_head.get("created_at"))
                                 for c in bot_comments)
                row["reason"] = f"mention posted {(now - epoch(mention_after_head.get('created_at'))) // 60}m ago"
            elif name not in MENTIONS:
                row.update(status="SKIPPED", reason="runs on push only; no mention can request a review")
            elif latest:
                row["status"] = "STALE"
                row["reason"] = f"last live review is on {clean(latest.get('commit_id'))[:7]}"
            else:
                row["status"] = "NONE"
                row["reason"] = "has never reviewed this PR"
    reviewer_rows.append(row)

# --- verdict -------------------------------------------------------------
state = clean(pr.get("state")) or "UNKNOWN"
mergeable = clean(pr.get("mergeable")) or "UNKNOWN"
url = clean(pr.get("url")) or None
needs_request = [r for r in reviewer_rows if r["status"] in ("NONE", "STALE")
                 or (r["status"] == "NOT_APPROVED" and by_reviewer.get(r["name"], 0) == 0)]
in_flight = [r for r in reviewer_rows if r["status"] == "REQUESTED"]
skipped = [r for r in reviewer_rows if r["status"] == "SKIPPED"]
for r in skipped:
    notes.append(f"{r['name']}: SKIPPED — {r['reason']}; its missing review is reported, not passed")
all_skipped = bool(reviewer_rows) and len(skipped) == len(reviewer_rows)
if all_skipped:
    notes.append("every requested reviewer is unreachable — fall back to the plugin's own review loop (/rs-sdlc-review)")
if not reviewer_rows:
    notes.append("no AI reviewer is configured — the verdict waits for no review approval (D7)")

if state != "OPEN":
    verdict, nxt = "BLOCKED", f"PR is {state}; nothing bounded to do — reopen or stop"
elif mergeable == "CONFLICTING":
    verdict, nxt = "BLOCKED", "PR is CONFLICTING — resolve the merge conflict, push, then re-run"
elif gated_failing:
    verdict = "BLOCKED"
    if gated_labels:
        what = ("the label " if len(gated_labels) == 1 else "the labels ") + ",".join(gated_labels)
        if gated_unmapped:
            what += " and the approval label named in docs/repository-settings.md"
    else:
        what = "the approval label named in docs/repository-settings.md"
    nxt = (f"apply {what} — failing human-gated check(s): {','.join(gated_failing)}; a maintainer applies "
           f"the label (never the plugin), then re-run pr-state.sh --pr {pr_number}")
elif ci_status == "red" or unresolved:
    verdict = "FIX"
    parts = []
    if failing:
        parts.append(f"fix failing checks {','.join(failing)} (ci-fixer)")
    if unresolved:
        parts.append(f"resolve {unresolved} review thread(s) (pr-comment-resolver)")
    nxt = "; ".join(parts) + "; then commit and push"
elif fr_nfr_status in ("missing", "failure"):
    verdict = "GATE"
    nxt = (f"rs-sdlc-fr-nfr-review --pr {pr_number} --head {head} — the {GATE_CONTEXT} status is "
           f"{fr_nfr_status} on head {head[:7]}; the gate is mandatory for every PR")
elif needs_request:
    verdict = "REQUEST"
    names = ",".join(r["name"] for r in needs_request)
    full = " --full" if any(r["status"] == "NOT_APPROVED" and r["name"] == "coderabbit" for r in needs_request) else ""
    nxt = f"request-ai-reviews.sh --pr {pr_number} --reviewers {names}{full}"
elif ci_status == "pending" or fr_nfr_status == "pending" or in_flight:
    verdict = "WAIT"
    what = []
    if pending or missing:
        what.append(f"checks {','.join(pending + missing)}")
    if fr_nfr_status == "pending":
        what.append(f"the {GATE_CONTEXT} status")
    if in_flight:
        what.append("reviews from " + ",".join(r["name"] for r in in_flight))
    nxt = f"pr-state.sh --pr {pr_number} --wait-seconds 540 — waiting for " + " and ".join(what)
elif all_skipped:
    verdict, nxt = "READY", ("exit condition met without an AI approval: every reviewer is SKIPPED — run "
                             "/rs-sdlc-review as the review source, then hand the PR to its human merger")
else:
    verdict, nxt = "READY", "exit condition met — hand the PR to its human merger"

result = {
    "pr": pr_number, "url": url, "repo": repo, "head": head,
    "state": state, "draft": bool(pr.get("isDraft")), "mergeable": mergeable,
    "ci": {"status": ci_status, "failing": failing, "pending": pending, "missing": missing,
           "checks": checks},
    "fr_nfr": fr_nfr,
    "unresolved": {"total": unresolved, "by_reviewer": by_reviewer},
    "reviewers": reviewer_rows, "human_gated": human_gated, "notes": notes,
    "verdict": verdict, "next": nxt,
}
with open(f"{work}/verdict", "w", encoding="utf-8") as handle:
    handle.write(verdict + "\n")
if json_out == "1":
    print(json.dumps(result, indent=2, sort_keys=True))
else:
    print(f"PR: #{pr_number} {repo} state={state} draft={str(result['draft']).lower()} "
          f"mergeable={mergeable} url={url or ''}")
    print(f"HEAD: {head}")
    print(f"CI: {ci_status} failing=[{','.join(failing)}] pending=[{','.join(pending)}] missing=[{','.join(missing)}]")
    print(f"FR_NFR_GATE: {fr_nfr_status}")
    print(f"UNRESOLVED: {unresolved}" + (" (" + " ".join(f"{k}={v}" for k, v in sorted(by_reviewer.items())) + ")" if by_reviewer else ""))
    for r in reviewer_rows:
        extra = f" ack={'yes' if r['ack'] else 'no'}" if r["status"] == "REQUESTED" else ""
        extra += f" head={'current' if r['on_head'] else 'other'}" if r["status"] in ("APPROVED", "NOT_APPROVED") else ""
        extra += f" — {r['reason']}" if r["reason"] else ""
        print(f"REVIEWER: {r['name']} status={r['status']}{extra}")
    print(f"HUMAN_GATED: failing=[{','.join(gated_failing)}] labels=[{','.join(gated_labels)}]")
    for n in notes:
        print(f"INFO: {clean(n)}")
    print(f"VERDICT: {verdict}")
    print(f"NEXT: {clean(nxt)}")
PY
}

# --- wait loop ---------------------------------------------------------------------
# The budget check never subtracts: elapsed + interval > wait is
# clock + interval > start + wait, compared as digit strings.

DEADLINE="$(num_add "$START" "$WAIT_SECONDS")"
clock="$START"
reads=0
while :; do
  out="$(ps_snapshot "$clock")" || exit 1
  reads=$((reads + 1))
  verdict="$(cat "$WORK/verdict")"
  if [[ ",$WAIT_VERDICTS," != *",$verdict,"* ]]; then
    break
  fi
  next="$(num_add "$clock" "$INTERVAL")"
  if num_gt "$next" "$DEADLINE"; then
    break
  fi
  log_info "pr-state: read $reads gave $verdict; reading again in ${INTERVAL}s (budget ${WAIT_SECONDS}s)"
  if [[ -n "${SDLC_NOW_EPOCH:-}" ]]; then
    clock="$next"
  else
    sleep "$INTERVAL"
    clock="$(now_epoch)"
  fi
done
printf '%s\n' "$out"
