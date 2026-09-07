#!/usr/bin/env bash
# request-ai-reviews.sh — ask the PR's AI reviewers for a (re-)review by
# posting the mention comment each bot accepts, honouring the cadence the
# bots enforce (FR-8 comment-source recovery, NFR-4 degrade-with-report).
#
# Usage: request-ai-reviews.sh [--pr <n>] [--reviewers <list>] [--full]
#                              [--min-interval-minutes <m>] [--force] [--dry-run]
#   --pr <n>                    PR number; default: the current branch's PR
#   --reviewers <list>          comma-separated subset of
#                               coderabbit,cubic,qodo,qlty,sonarcloud
#                               (default: coderabbit,cubic)
#   --full                      ask CodeRabbit for a full re-review instead of
#                               the incremental one
#   --min-interval-minutes <m>  minimum gap between two CodeRabbit requests on
#                               the same PR (default 60 — CodeRabbit serves
#                               roughly one requested review per hour per repo)
#   --force                     post even inside the interval
#   --dry-run                   print the plan, post nothing
#
# Reads the PR's issue comments once (gh api, paginated), decides per
# reviewer, then posts. Output is one line per reviewer:
#   REQUESTED: <reviewer> <mention>        a comment was posted
#   WAIT: <reviewer> <minutes>m            inside the interval; nothing posted
#   SKIPPED: <reviewer> — <reason>         no mention can help (paused seat,
#                                          oversized diff, status-check bot)
#   INFO: <text>                           informational (draft PR, …)
# and a final `SUMMARY: requested=<n> waiting=<n> skipped=<n>` line. Exit 0
# whenever the plan was computed and every requested post succeeded; exit 1
# on usage errors, an unresolvable PR/repo, or a failed gh call. SDLC_NOW_EPOCH
# overrides "now" (tests).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PR=""
REVIEWERS="coderabbit,cubic"
FULL=0
INTERVAL=60
FORCE=0
DRY_RUN=0
USAGE='usage: request-ai-reviews.sh [--pr <n>] [--reviewers <list>] [--full] [--min-interval-minutes <m>] [--force] [--dry-run]'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr needs a value}"; shift 2 ;;
    --reviewers) REVIEWERS="${2:?--reviewers needs a value}"; shift 2 ;;
    --full) FULL=1; shift ;;
    --min-interval-minutes) INTERVAL="${2:?--min-interval-minutes needs a value}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) die "unknown argument: $1 ($USAGE)" ;;
  esac
done
[[ "$INTERVAL" =~ ^[0-9]+$ ]] || die "--min-interval-minutes must be a non-negative integer, got: $INTERVAL"
[[ "$REVIEWERS" =~ ^[a-z,]+$ ]] || die "--reviewers must be a comma-separated list, got: $REVIEWERS"
for r in ${REVIEWERS//,/ }; do
  case "$r" in
    coderabbit|cubic|qodo|qlty|sonarcloud) ;;
    *) die "unknown reviewer '$r' (known: coderabbit,cubic,qodo,qlty,sonarcloud)" ;;
  esac
done

command -v gh >/dev/null 2>&1 || die "gh CLI not found on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 is required to evaluate the reviewer plan"

if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq .number 2>/dev/null)" \
    || die "no PR found for the current branch (pass --pr <n>)"
fi
[[ "$PR" =~ ^[0-9]+$ ]] || die "--pr must be a number, got: $PR"

repo_slug="$(resolve_repo_slug)" \
  || die "cannot resolve repository (no origin remote and gh repo view failed)"

# Draft detection is informational: CodeRabbit's automatic review skips drafts,
# but an explicit mention still runs, so the plan is unchanged.
pr_json="$(gh pr view "$PR" --json isDraft,headRefOid,commits)" \
  || die "gh pr view failed for PR #$PR in $repo_slug"
is_draft="$(python3 -c 'import json,sys; print(str(json.loads(sys.argv[1]).get("isDraft")).lower())' "$pr_json")"
# The head's push moment bounds which bot comments still describe the current
# diff: a "Review skipped" posted for an earlier, larger head must not keep
# suppressing mentions after a push shrank the PR. Check suites are created
# when the commit reaches GitHub, so the earliest suite dates the push; the
# commit timestamp is only the fallback (same rule as pr-state.sh).
head_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("headRefOid") or "")' "$pr_json")"
pushed_at=""
if [[ -n "$head_sha" ]]; then
  pushed_at="$(gh api "repos/$repo_slug/commits/$head_sha/check-suites?per_page=100" \
    --jq '[.check_suites[]? | .created_at] | map(select(. != null)) | min // empty')" \
    || die "gh api failed listing check suites for commit $head_sha in $repo_slug (the push boundary cannot be dated; retry)"
fi
head_epoch="$(python3 - "$pr_json" "$pushed_at" <<'PY'
import json, sys
from datetime import datetime, timezone


def epoch(ts):
    try:
        return int(datetime.strptime((ts or "").strip('"'), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    except ValueError:
        return 0


pr = json.loads(sys.argv[1])
commit_epoch = max([epoch(c.get("committedDate")) for c in pr.get("commits") or []] or [0])
pushed = epoch(sys.argv[2])
print(max(commit_epoch, pushed) if pushed else commit_epoch)
PY
)"

# One paginated read of the PR's issue comments as NDJSON (author, body, time).
comments="$(gh api "repos/$repo_slug/issues/$PR/comments?per_page=100" --paginate \
  --jq '.[] | {user: .user.login, body: .body, created_at: .created_at}')" \
  || die "gh api failed listing comments for PR #$PR in $repo_slug"

now_epoch="${SDLC_NOW_EPOCH:-$(date -u +%s)}"

# The plan: one line per reviewer — POST <reviewer> <mention> | WAIT <reviewer>
# <minutes> | SKIP <reviewer> <reason>. Computed in python so ISO timestamps and
# the comment scan stay portable (no GNU-date dependency).
comments_file="$(mktemp)"
trap 'rm -f "$comments_file"' EXIT
printf '%s\n' "$comments" >"$comments_file"
plan="$(python3 - "$REVIEWERS" "$FULL" "$INTERVAL" "$FORCE" "$now_epoch" "$comments_file" "$head_epoch" <<'PY'
import json, sys
from datetime import datetime, timezone

reviewers = [r for r in sys.argv[1].split(",") if r]
full = sys.argv[2] == "1"
interval_min = int(sys.argv[3])
force = sys.argv[4] == "1"
now = int(sys.argv[5])
head_epoch = int(sys.argv[7])


def norm_login(login):
    login = (login or "").lower()
    return login[:-5] if login.endswith("[bot]") else login

comments = []
for line in open(sys.argv[6], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    c = json.loads(line)
    ts = c.get("created_at") or ""
    try:
        epoch = int(datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    except ValueError:
        epoch = 0
    comments.append({"user": norm_login(c.get("user")), "body": c.get("body") or "", "epoch": epoch})
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
            print("SKIP coderabbit diff exceeds CodeRabbit's changed-file limit; split the PR — a mention cannot lift it")
            continue
        req = last_request(("@coderabbitai review", "@coderabbitai full review"))
        if req and not force and interval_min > 0:
            age_min = (now - req["epoch"]) // 60
            if age_min < interval_min:
                print(f"WAIT coderabbit {interval_min - age_min}")
                continue
        print("POST coderabbit @coderabbitai full review" if full else "POST coderabbit @coderabbitai review")
    elif r == "cubic":
        print("POST cubic @cubic-dev-ai review")
    elif r == "qodo":
        bot = last_by("qodo-code-review")
        if bot and "paused" in bot["body"].lower():
            print("SKIP qodo reviews are paused for this account (lapsed subscription); no mention re-enables them")
        else:
            print("SKIP qodo runs on push only; this plugin posts no Qodo command")
    elif r == "qlty":
        print("SKIP qlty status-check bot — re-runs on the next push, no mention command")
    elif r == "sonarcloud":
        print("SKIP sonarcloud status-check bot — re-runs on the next push, no mention command")
PY
)"

[[ "$is_draft" == "true" ]] && echo "INFO: PR #$PR is a draft — automatic CodeRabbit review skips drafts; explicit mentions still run"

requested=0; waiting=0; skipped=0
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  kind="${line%% *}"; rest="${line#* }"
  reviewer="${rest%% *}"; detail="${rest#* }"
  case "$kind" in
    POST)
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "WOULD-POST: $reviewer $detail"
      else
        gh pr comment "$PR" --body "$detail" >/dev/null \
          || die "gh pr comment failed posting '$detail' on PR #$PR"
        echo "REQUESTED: $reviewer $detail"
      fi
      requested=$((requested + 1))
      ;;
    WAIT)
      echo "WAIT: $reviewer ${detail}m (last CodeRabbit request is inside the ${INTERVAL}-minute interval; pass --force to override)"
      waiting=$((waiting + 1))
      ;;
    SKIP)
      echo "SKIPPED: $reviewer — $detail"
      skipped=$((skipped + 1))
      ;;
    *) die "internal error: unexpected plan line '$line'" ;;
  esac
done <<<"$plan"

echo "SUMMARY: requested=$requested waiting=$waiting skipped=$skipped"
