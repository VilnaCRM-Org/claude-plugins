#!/usr/bin/env bash
# request-ai-reviews.sh — ask the pull request's AI reviewers for a review, honouring the cadence each bot enforces.
#
# Usage: request-ai-reviews.sh [--pr N] [--reviewers LIST] [--full] [--min-interval-minutes M] [--force] [--dry-run]
#   --pr N                    pull-request number, ^[1-9][0-9]*$ up to
#                             2147483647; default: the current branch's pull
#                             request from `gh pr view --json number --jq .number`
#   --reviewers LIST          comma-separated subset of coderabbit, cubic, qodo,
#                             qlty and sonarcloud, without duplicates or empty
#                             elements (the pr-state.sh rule); an empty LIST
#                             means no reviewer; default: review.reviewers of
#                             the profile (.claude/rust-sdlc.yml at the top of
#                             the work tree), checked the same way; without a
#                             profile the list is empty (a WARN on stderr)
#   --full                    ask CodeRabbit for a full review instead of the
#                             incremental one (the only bot with a full mode)
#   --min-interval-minutes M  minimum gap in minutes between two CodeRabbit
#                             requests on the pull request; default 60
#                             (CodeRabbit serves about one requested review per
#                             hour); 0 turns the cadence off
#   --force                   post the CodeRabbit mention inside the interval too
#   --dry-run                 print the plan as WOULD-POST: lines and post nothing
#   --help                    print this help and exit 0 (accepted in any position)
#
# Reads the pull request once (draft flag, head commit), dates the head's push
# from its earliest check suite (the newest commit time is the fallback), reads
# the issue comments once (paginated), decides per reviewer, then posts the
# mention comments. One line per reviewer, in list order:
#   REQUESTED: <reviewer> <mention>    the mention comment was posted
#   WOULD-POST: <reviewer> <mention>   --dry-run: the comment it would post
#   WAIT: <reviewer> <m>m (<reason>)   the last CodeRabbit request is inside the
#                                      interval; nothing posted
#   SKIPPED: <reviewer> — <reason>     no mention can help: CodeRabbit's
#                                      "Review skipped" for the current head
#                                      (changed-file limit), a paused Qodo
#                                      seat, a push-only or status-check bot
# plus `INFO: <text>` lines (a draft pull request), then the closing line
# `SUMMARY: requested=<n> waiting=<n> skipped=<n>` (a WOULD-POST counts as
# requested; the three numbers add up to the number of reviewers). An empty
# reviewer list prints `INFO: no reviewers configured` and the zero summary
# without calling gh. SDLC_NOW_EPOCH fixes "now" (tests). Nothing is written
# to disk.
#
# Exit: 0 plan computed and every post succeeded (also for an empty reviewer list); 1 usage error (unknown flag, missing value, bad --pr, --reviewers or --min-interval-minutes), unreadable profile or invalid review.reviewers, gh or python3 absent, no pull request, unresolvable repository, failed gh call or malformed gh response; 2 is never used (ADR-23: usage errors exit 1 for react parity)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# The five reviewers both PR scripts know (pr-state.sh validates the same set).
RAR_KNOWN="coderabbit,cubic,qodo,qlty,sonarcloud"
# GraphQL Int is a signed 32-bit integer: no pull request carries a larger number.
RAR_PR_MAX=2147483647
RAR_USAGE='request-ai-reviews.sh [--pr N] [--reviewers LIST] [--full] [--min-interval-minutes M] [--force] [--dry-run]'

# --- python3 programs -------------------------------------------------------------

# Pull-request facts: stdin is the `gh pr view --json isDraft,headRefOid,commits`
# document; prints `<true|false> <head sha or -> <newest commit epoch>` on one
# line, or exits 1 with a reason on stderr when the document is malformed.
# shellcheck disable=SC2016 # python source
RAR_PR_PY='
import io
import json
import sys
from datetime import datetime, timezone


def epoch(ts):
    try:
        return int(datetime.strptime(str(ts or "").strip().strip("\""), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    except ValueError:
        return 0


try:
    pr = json.load(io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8", errors="replace"))
except ValueError as exc:
    sys.stderr.write("[rust-sdlc][ERROR] the pull-request document is not JSON: %s\n" % str(exc).splitlines()[0])
    sys.exit(1)
if not isinstance(pr, dict):
    sys.stderr.write("[rust-sdlc][ERROR] the pull-request document is not a JSON object\n")
    sys.exit(1)
commits = pr.get("commits") or []
if not isinstance(commits, list):
    commits = []
sha = pr.get("headRefOid") or ""
if not isinstance(sha, str):
    sha = "?"
elif not sha:
    sha = "-"
elif not (sha.isascii() and sha.isalnum()):
    sha = "?"
newest = max([epoch(c.get("committedDate")) for c in commits if isinstance(c, dict)] or [0])
print("true" if pr.get("isDraft") is True else "false", sha, newest)
'

# The plan: stdin is the comment listing (NDJSON {user, body, created_at});
# argv is reviewers full interval force now commit_epoch pushed_at. Prints one
# ASCII line per reviewer, in list order: `POST <reviewer> <mention>`,
# `WAIT <reviewer> <minutes>` or `SKIP <reviewer> <reason-code>` (the codes of
# rar_reason). A line that is not a JSON object exits 1 with its number on
# stderr. ISO timestamps are parsed here, so the shell needs no GNU date.
# shellcheck disable=SC2016 # python source
RAR_PLAN_PY='
import io
import json
import sys
from datetime import datetime, timezone

reviewers = [r for r in sys.argv[1].split(",") if r]
full = sys.argv[2] == "1"
interval = int(sys.argv[3])
force = sys.argv[4] == "1"
now = int(sys.argv[5])
commit_epoch = int(sys.argv[6])


def epoch(ts):
    try:
        return int(datetime.strptime(str(ts or "").strip().strip("\""), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    except ValueError:
        return 0


# The push bounds which bot comments still describe the current diff: a
# "Review skipped" posted for an earlier, larger head must not keep
# suppressing mentions after a push shrank the pull request.
pushed = epoch(sys.argv[7])
head_epoch = max(commit_epoch, pushed) if pushed else commit_epoch


def norm_login(login):
    login = (login if isinstance(login, str) else "").lower()
    return login[:-5] if login.endswith("[bot]") else login


comments = []
stream = io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8", errors="replace")
for number, line in enumerate(stream, 1):
    line = line.strip()
    if not line:
        continue
    try:
        item = json.loads(line)
    except ValueError:
        item = None
    if not isinstance(item, dict):
        sys.stderr.write("[rust-sdlc][ERROR] comment listing line %d is not a JSON object\n" % number)
        sys.exit(1)
    body = item.get("body")
    comments.append({"user": norm_login(item.get("user")),
                     "body": body if isinstance(body, str) else "",
                     "epoch": epoch(item.get("created_at"))})
comments.sort(key=lambda c: c["epoch"])


def last_by(user):
    for c in reversed(comments):
        if c["user"] == user:
            return c
    return None


def last_request(prefixes):
    for c in reversed(comments):
        head = c["body"].lstrip().lower()
        if any(head.startswith(p) for p in prefixes):
            return c
    return None


for r in reviewers:
    if r == "coderabbit":
        bot = last_by("coderabbitai")
        body = (bot or {}).get("body", "")
        if bot and "exceed the limit of" in body and "review skipped" in body.lower() and bot["epoch"] >= head_epoch:
            print("SKIP coderabbit oversized")
            continue
        req = last_request(("@coderabbitai review", "@coderabbitai full review"))
        if req and not force and interval > 0:
            age = max(0, (now - req["epoch"]) // 60)
            if age < interval:
                print("WAIT coderabbit %d" % (interval - age))
                continue
        print("POST coderabbit @coderabbitai full review" if full else "POST coderabbit @coderabbitai review")
    elif r == "cubic":
        print("POST cubic @cubic-dev-ai review")
    elif r == "qodo":
        bot = last_by("qodo-code-review")
        if bot and "paused" in bot["body"].lower():
            print("SKIP qodo paused")
        else:
            print("SKIP qodo push-only")
    elif r == "qlty":
        print("SKIP qlty status-check")
    elif r == "sonarcloud":
        print("SKIP sonarcloud status-check")
'

# Profile reviewers: stdin is the profile as JSON (yaml_to_json, either YAML
# backend); prints the kind of review.reviewers on the first line (`list`,
# `absent`, `null` or `not-list <json type>`), then for a list one line per
# item: a string of lower-case letters as it is (the empty string as an empty
# line), any other item as ASCII JSON, so it can only fail the name check.
# shellcheck disable=SC2016 # python source
RAR_PROFILE_PY='
import json
import re
import sys

try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
review = doc.get("review") if isinstance(doc, dict) else None
if not isinstance(review, dict) or "reviewers" not in review:
    print("absent")
    sys.exit(0)
value = review["reviewers"]
if value is None:
    print("null")
    sys.exit(0)
if not isinstance(value, list):
    names = {bool: "boolean", int: "number", float: "number", str: "string", dict: "object"}
    print("not-list " + names.get(type(value), "value"))
    sys.exit(0)
print("list")
for item in value:
    if isinstance(item, str) and re.fullmatch(r"[a-z]*", item):
        print(item)
    else:
        print(json.dumps(item, ensure_ascii=True))
'

# --- helpers ------------------------------------------------------------------------

# rar_clean S — S without control characters (safe to echo in a diagnostic).
rar_clean() {
  printf '%s' "${1//[[:cntrl:]]/}"
}

# rar_reason CODE — the SKIPPED: reason of a plan reason code.
rar_reason() {
  case "$1" in
    oversized) printf '%s' "diff exceeds CodeRabbit's changed-file limit; split the PR — a mention cannot lift it" ;;
    paused) printf '%s' "reviews are paused for this account (lapsed subscription); no mention re-enables them" ;;
    push-only) printf '%s' "runs on push only; this plugin posts no Qodo command" ;;
    status-check) printf '%s' "status-check bot — re-runs on the next push, no mention command" ;;
    *) die "internal error: unknown skip reason '$(rar_clean "$1")'" ;;
  esac
}

# rar_usage_error MSG... — a usage error: log it with the usage line and exit 1
# (ADR-23: this script keeps react's exit code for usage, never 2).
rar_usage_error() {
  die "$* (usage: $RAR_USAGE)"
}

# rar_value FLAG ARGC VALUE — rar_usage_error "<flag> needs a value" when FLAG
# is the last argument or VALUE starts with `--` (the pr-state.sh rule; an
# empty VALUE is checked by the flag's own validation).
rar_value() {
  if [[ "$2" -lt 2 || "${3-}" == --* ]]; then
    rar_usage_error "$1 needs a value"
  fi
}

# rar_valid_pr S — S is a pull-request number GraphQL can carry.
rar_valid_pr() {
  [[ "${1-}" =~ ^[1-9][0-9]*$ ]] && ! num_gt "$1" "$RAR_PR_MAX"
}

# rar_check_reviewers SOURCE LIST — the reviewer rule of pr-state.sh, check
# for check and message for message: LIST (comma-separated) names known
# reviewers, without duplicates or empty elements; an empty LIST is valid.
# SOURCE is the flag (a usage error) or the profile key (a plain failure).
rar_check_reviewers() {
  local src="$1" list="$2" r seen="," fail=rar_usage_error
  [[ "$src" == --* ]] || fail=die
  [[ -n "$list" ]] || return 0
  [[ "$list" =~ ^[a-z]+(,[a-z]+)*$ ]] ||
    "$fail" "$src must be a comma-separated list without empty elements, got: $(rar_clean "$list")"
  for r in ${list//,/ }; do
    case ",$RAR_KNOWN," in
      *",$r,"*) ;;
      *) "$fail" "unknown reviewer '$r' in $src (known: $RAR_KNOWN)" ;;
    esac
    if [[ "$seen" == *",$r,"* ]]; then
      "$fail" "duplicate reviewer '$r' in $src"
    fi
    seen+="$r,"
  done
}

# rar_profile_reviewers — prints review.reviewers of the profile at the top of
# the work tree as one comma list (nothing for `[]`, and nothing with a WARN
# when there is no profile, as in pr-state.sh), or dies: an unparseable
# profile, the key missing, null or not a list, or an item that breaks
# rar_check_reviewers. Every item is checked, an empty or a nested one too.
rar_profile_reviewers() {
  local top profile doc out kind items list source
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
  [[ -n "$top" ]] || top="$(pwd -P)"
  profile="$(profile_path "$top")"
  source="review.reviewers of $profile"
  if [[ ! -f "$profile" ]]; then
    log_warn "no profile at $profile: the reviewer list defaults to empty (pass --reviewers LIST, or run /rs-sdlc-setup on the default branch and commit the result)"
    return 0
  fi
  require_yaml_toolchain
  doc="$(yaml_to_json "$profile")" ||
    die "profile: cannot read review.reviewers from $profile"
  # The trailing `x` keeps the final newline, so a last empty item survives the
  # command substitution and is refused instead of silently dropped.
  out="$(printf '%s\n' "$doc" | python3 -I -c "$RAR_PROFILE_PY" && printf x)" ||
    die "profile: cannot read review.reviewers from $profile"
  out="${out%x}"
  kind="${out%%$'\n'*}"
  case "$kind" in
    list) ;;
    absent | null) die "profile: required key 'review.reviewers' missing or null in $profile" ;;
    *) die "profile: review.reviewers must be a list in $profile, got a ${kind#not-list }" ;;
  esac
  items="${out#*$'\n'}"
  [[ -n "$items" ]] || return 0
  items="${items%$'\n'}"
  list="${items//$'\n'/,}"
  # A list whose only item is the empty string joins to nothing: refuse it
  # here, since an empty LIST is valid for rar_check_reviewers.
  [[ -n "$list" ]] ||
    die "$source must be a comma-separated list without empty elements, got: ['']"
  rar_check_reviewers "$source" "$list"
  printf '%s\n' "$list"
}

# --- arguments ----------------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done

PR=""
PR_GIVEN=0
REVIEWERS=""
REVIEWERS_GIVEN=0
FULL=0
INTERVAL=60
FORCE=0
DRY_RUN=0
while (($#)); do
  case "$1" in
    --pr)
      rar_value "$1" "$#" "${2-}"
      PR="$2"
      PR_GIVEN=1
      shift 2
      ;;
    --reviewers)
      rar_value "$1" "$#" "${2-}"
      REVIEWERS="$2"
      REVIEWERS_GIVEN=1
      shift 2
      ;;
    --full)
      FULL=1
      shift
      ;;
    --min-interval-minutes)
      rar_value "$1" "$#" "${2-}"
      INTERVAL="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *) rar_usage_error "unknown argument: $(rar_clean "$1")" ;;
  esac
done

is_uint "$INTERVAL" ||
  rar_usage_error "--min-interval-minutes must be a non-negative integer, got: $(rar_clean "$INTERVAL")"
INTERVAL="$(strip_zeros "$INTERVAL")"
if [[ "$PR_GIVEN" == 1 ]] && ! rar_valid_pr "$PR"; then
  rar_usage_error "--pr must be a pull-request number (^[1-9][0-9]*$, at most $RAR_PR_MAX), got: $(rar_clean "$PR")"
fi

# python3 evaluates the profile list and the plan; gh is needed only once a
# reviewer is configured.
have_cmd python3 || die "python3 is required to evaluate the reviewer plan"

if [[ "$REVIEWERS_GIVEN" == 1 ]]; then
  rar_check_reviewers --reviewers "$REVIEWERS"
else
  REVIEWERS="$(rar_profile_reviewers)" || exit 1
fi

if [[ -z "$REVIEWERS" ]]; then
  echo "INFO: no reviewers configured"
  echo "SUMMARY: requested=0 waiting=0 skipped=0"
  exit 0
fi

# --- pull request and repository -------------------------------------------------------

have_cmd gh || die "gh CLI not found on PATH: install the GitHub CLI to request AI reviews"

if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq .number)" ||
    die "no pull request found for the current branch: pass --pr N"
  rar_valid_pr "$PR" ||
    die "gh pr view returned an invalid pull-request number: '$(rar_clean "$PR")': pass --pr N"
fi

SLUG="$(resolve_repo_slug)" ||
  die "cannot resolve the repository: no github.com origin remote and gh repo view failed"

# Draft detection is informational: CodeRabbit's automatic review skips drafts,
# but an explicit mention still runs, so the plan does not change.
pr_json="$(gh pr view "$PR" --json isDraft,headRefOid,commits)" ||
  die "gh pr view failed for PR #$PR in $SLUG"
pr_facts="$(printf '%s\n' "$pr_json" | python3 -I -c "$RAR_PR_PY")" ||
  die "gh pr view returned a malformed document for PR #$PR in $SLUG"
read -r is_draft head_sha commit_epoch <<<"$pr_facts"
if [[ "$head_sha" == - ]]; then
  head_sha=""
fi
if [[ -n "$head_sha" && ! "$head_sha" =~ ^[0-9A-Fa-f]{4,64}$ ]]; then
  die "gh pr view returned a malformed head commit for PR #$PR in $SLUG: '$(rar_clean "$head_sha")'"
fi

# Check suites are created when the commit reaches GitHub, so the earliest one
# dates the push; the commit time is only the fallback (the pr-state.sh rule).
pushed_at=""
if [[ -n "$head_sha" ]]; then
  pushed_at="$(gh api "repos/$SLUG/commits/$head_sha/check-suites?per_page=100" \
    --jq '[.check_suites[]? | .created_at] | map(select(. != null)) | min // empty')" ||
    die "gh api failed listing check suites for commit $head_sha in $SLUG (the push boundary cannot be dated; retry)"
fi

# One paginated read of the issue comments as NDJSON (author, body, time).
comments="$(gh api "repos/$SLUG/issues/$PR/comments?per_page=100" --paginate \
  --jq '.[] | {user: .user.login, body: .body, created_at: .created_at}')" ||
  die "gh api failed listing comments for PR #$PR in $SLUG"

now="$(now_epoch)" || exit 1

# --- plan and posts ----------------------------------------------------------------------

plan="$(printf '%s\n' "$comments" |
  python3 -I -c "$RAR_PLAN_PY" "$REVIEWERS" "$FULL" "$INTERVAL" "$FORCE" "$now" "$commit_epoch" "${pushed_at//[[:cntrl:]]/}")" ||
  die "gh api returned a malformed comment listing for PR #$PR in $SLUG"

if [[ "$is_draft" == true ]]; then
  echo "INFO: PR #$PR is a draft — automatic CodeRabbit review skips drafts; explicit mentions still run"
fi

requested=0
waiting=0
skipped=0
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  kind="${line%% *}"
  rest="${line#* }"
  reviewer="${rest%% *}"
  detail="${rest#* }"
  case "$kind" in
    POST)
      if [[ "$DRY_RUN" == 1 ]]; then
        echo "WOULD-POST: $reviewer $detail"
      else
        gh pr comment "$PR" --body "$detail" >/dev/null ||
          die "gh pr comment failed posting '$detail' on PR #$PR"
        echo "REQUESTED: $reviewer $detail"
      fi
      requested=$((requested + 1))
      ;;
    WAIT)
      echo "WAIT: $reviewer ${detail}m (last CodeRabbit request is inside the ${INTERVAL}-minute interval; pass --force to override)"
      waiting=$((waiting + 1))
      ;;
    SKIP)
      reason="$(rar_reason "$detail")" || exit 1
      echo "SKIPPED: $reviewer — $reason"
      skipped=$((skipped + 1))
      ;;
    *) die "internal error: unexpected plan line '$(rar_clean "$line")'" ;;
  esac
done <<<"$plan"

echo "SUMMARY: requested=$requested waiting=$waiting skipped=$skipped"
