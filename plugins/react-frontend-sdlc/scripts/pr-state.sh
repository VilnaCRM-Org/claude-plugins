#!/usr/bin/env bash
# pr-state.sh — one deterministic snapshot of a pull request's finishing state
# and the single next action it implies (the sensor behind the
# fe-sdlc-pr-until-green workflow and /fe-sdlc-finish-pr's final status).
#
# Usage: pr-state.sh [--pr <n>] [--reviewers <list>] [--required-checks <list>]
#                    [--wait-seconds <s>] [--interval-seconds <s>] [--json]
#   --pr <n>                  PR number; default: the current branch's PR
#   --reviewers <list>        comma-separated AI reviewers whose approval the
#                             verdict requires: coderabbit,cubic,qodo,qlty,
#                             sonarcloud (default: coderabbit,cubic)
#   --required-checks <list>  comma-separated check names that decide the CI
#                             verdict; default: every check on the PR
#   --wait-seconds <s>        keep re-reading while the verdict is WAIT, for at
#                             most <s> seconds (default 0 — one snapshot)
#   --interval-seconds <s>    pause between reads in wait mode (default 60)
#   --wait-verdicts <list>    verdicts that keep wait mode polling (default
#                             WAIT; pass WAIT,REQUEST to sit out CodeRabbit's
#                             request interval without re-mentioning)
#   --json                    machine-readable output (shape below)
#
# Reads the PR (gh pr view), its reviews and issue comments (gh api, paginated)
# and the unresolved review threads (get-pr-comments.sh) once per snapshot, then
# classifies every requested reviewer against the CURRENT head commit:
#   APPROVED       latest live review is on the head and approves
#   NOT_APPROVED   latest live review is on the head but does not approve
#   REQUESTED      a review mention was posted after the head was pushed and
#                  the bot has not reviewed the head yet (ack=yes|no)
#   STALE          the bot last reviewed an older commit
#   NONE           the bot has never reviewed this PR
#   SKIPPED        no mention can reach the bot (paused seat, oversized diff,
#                  status-check bot, push-only reviewer)
# and renders exactly one verdict, highest priority first:
#   BLOCKED  the PR is merged/closed or CONFLICTING — nothing bounded to do
#   FIX      a required check failed, or review threads are unresolved
#   REQUEST  a reviewer needs a (re-)review mention
#   WAIT     checks are still running, or a requested review is in flight
#   READY    checks green, zero unresolved threads, every reachable reviewer
#            approves the head (SKIPPED reviewers are reported, never passed)
# Human output is one `KEY: value` line per fact plus `VERDICT:` and `NEXT:`;
# --json emits {pr, repo, head, state, draft, mergeable, ci, unresolved,
# reviewers, notes, verdict, next}. Exit 0 whenever a snapshot was rendered
# (the verdict is data), 1 on usage errors or a failed gh call.
# SDLC_NOW_EPOCH overrides "now" (tests).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PR=""
REVIEWERS="coderabbit,cubic"
REQUIRED=""
WAIT=0
INTERVAL=60
WAIT_VERDICTS="WAIT"
JSON_OUT=0
USAGE='usage: pr-state.sh [--pr <n>] [--reviewers <list>] [--required-checks <list>] [--wait-seconds <s>] [--interval-seconds <s>] [--wait-verdicts <list>] [--json]'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr needs a value}"; shift 2 ;;
    --reviewers) REVIEWERS="${2:?--reviewers needs a value}"; shift 2 ;;
    --required-checks) REQUIRED="${2:?--required-checks needs a value}"; shift 2 ;;
    --wait-seconds) WAIT="${2:?--wait-seconds needs a value}"; shift 2 ;;
    --interval-seconds) INTERVAL="${2:?--interval-seconds needs a value}"; shift 2 ;;
    --wait-verdicts) WAIT_VERDICTS="${2:?--wait-verdicts needs a value}"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) die "unknown argument: $1 ($USAGE)" ;;
  esac
done
[[ "$WAIT" =~ ^(0|[1-9][0-9]*)$ ]] || die "--wait-seconds must be a non-negative integer without leading zeros, got: $WAIT"
[[ "$INTERVAL" =~ ^(0|[1-9][0-9]*)$ ]] || die "--interval-seconds must be a non-negative integer without leading zeros, got: $INTERVAL"
if (( WAIT > 0 && INTERVAL == 0 )); then die "--interval-seconds must be at least 1 when --wait-seconds is set"; fi
[[ "$WAIT_VERDICTS" =~ ^(WAIT|REQUEST|FIX)(,(WAIT|REQUEST|FIX))*$ ]] || die "--wait-verdicts must list WAIT, REQUEST and/or FIX, got: $WAIT_VERDICTS"
[[ "$REVIEWERS" =~ ^[a-z]+(,[a-z]+)*$ ]] || die "--reviewers must be a comma-separated list without empty elements, got: $REVIEWERS"
seen_reviewers=","
for r in ${REVIEWERS//,/ }; do
  case "$r" in
    coderabbit|cubic|qodo|qlty|sonarcloud) ;;
    *) die "unknown reviewer '$r' (known: coderabbit,cubic,qodo,qlty,sonarcloud)" ;;
  esac
  [[ "$seen_reviewers" == *",$r,"* ]] && die "duplicate reviewer '$r' in --reviewers"
  seen_reviewers+="$r,"
done

command -v gh >/dev/null 2>&1 || die "gh CLI not found on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 is required to evaluate the PR state"

if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq .number 2>/dev/null)" \
    || die "no PR found for the current branch (pass --pr <n>)"
fi
[[ "$PR" =~ ^[0-9]+$ ]] || die "--pr must be a number, got: $PR"

repo_slug="$(resolve_repo_slug)" \
  || die "cannot resolve repository (no origin remote and gh repo view failed)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# snapshot — fetch the four payloads for the current moment into $work and
# render the classification. Prints the rendered output; returns 0 always
# (a gh failure dies from inside).
snapshot() {
  gh pr view "$PR" --repo "$repo_slug" \
    --json number,url,state,isDraft,mergeable,headRefOid,commits,statusCheckRollup >"$work/pr.json" \
    || die "gh pr view failed for PR #$PR in $repo_slug"
  gh api "repos/$repo_slug/pulls/$PR/reviews?per_page=100" --paginate \
    --jq '.[] | {user: .user.login, state: .state, commit_id: .commit_id, submitted_at: .submitted_at}' \
    >"$work/reviews.ndjson" \
    || die "gh api failed listing reviews for PR #$PR in $repo_slug"
  gh api "repos/$repo_slug/issues/$PR/comments?per_page=100" --paginate \
    --jq '.[] | {user: .user.login, body: .body, created_at: .created_at}' \
    >"$work/comments.ndjson" \
    || die "gh api failed listing comments for PR #$PR in $repo_slug"
  "$SCRIPT_DIR/get-pr-comments.sh" --pr "$PR" --unresolved-only --json >"$work/threads.json" \
    || die "get-pr-comments.sh failed for PR #$PR"
  # The head's push moment: check suites are created when the commit reaches
  # GitHub, so the earliest suite dates the push; a commit's own timestamp is
  # only the fallback (a mention posted between commit and push must not read
  # as a request for that head).
  head_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("headRefOid") or "")' "$work/pr.json")"
  if [[ -n "$head_sha" ]]; then
    gh api "repos/$repo_slug/commits/$head_sha/check-suites?per_page=100" \
      --jq '[.check_suites[]? | .created_at] | map(select(. != null)) | min // empty' >"$work/pushed_at" 2>/dev/null \
      || : >"$work/pushed_at"
  else
    : >"$work/pushed_at"
  fi

  python3 - "$work" "$repo_slug" "$REVIEWERS" "$REQUIRED" "${SDLC_NOW_EPOCH:-$(date -u +%s)}" "$JSON_OUT" <<'PY'
import json, sys
from datetime import datetime, timezone

work, repo, reviewers_arg, required_arg, now_arg, json_out = sys.argv[1:7]
reviewers = [r for r in reviewers_arg.split(",") if r]
required = [c for c in required_arg.split(",") if c]
now = int(now_arg)


def epoch(ts):
    try:
        return int(datetime.strptime(ts or "", "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    except ValueError:
        return 0


def ndjson(path):
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out


pr = json.load(open(f"{work}/pr.json", encoding="utf-8"))
reviews = ndjson(f"{work}/reviews.ndjson")
comments = ndjson(f"{work}/comments.ndjson")
threads = json.load(open(f"{work}/threads.json", encoding="utf-8"))

head = pr.get("headRefOid") or ""
commit_epoch = max([epoch(c.get("committedDate")) for c in pr.get("commits") or []] or [0])
pushed_at = open(f"{work}/pushed_at", encoding="utf-8").read().strip().strip('"')
head_epoch = max(commit_epoch, epoch(pushed_at)) if pushed_at else commit_epoch
notes = []

# --- CI -----------------------------------------------------------------
PASSING = {"SUCCESS", "NEUTRAL", "SKIPPED"}
FAILING = {"FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"}
checks = {}
for c in pr.get("statusCheckRollup") or []:
    name = c.get("name") or c.get("context") or "?"
    if c.get("__typename") == "StatusContext":
        verdict = c.get("state") or "PENDING"
    elif (c.get("status") or "") != "COMPLETED":
        verdict = "PENDING"
    else:
        verdict = c.get("conclusion") or "PENDING"
    checks[name] = verdict
scope = required if required else list(checks)
failing = sorted(n for n in scope if checks.get(n) in FAILING)
pending = sorted(n for n in scope if n in checks and checks[n] not in FAILING and checks[n] not in PASSING)
missing = sorted(n for n in required if n not in checks)
if not checks and not required:
    ci_status = "none"
    notes.append("CI: the PR reports no checks — the CI half of the exit condition is satisfied-with-report, not verified")
elif failing:
    ci_status = "red"
elif pending or missing:
    ci_status = "pending"
else:
    ci_status = "green"

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
    login = (login or "").lower()
    return login[:-5] if login.endswith("[bot]") else login


by_reviewer = {}
unresolved = 0
for t in threads.get("review_threads") or []:
    if t.get("is_resolved"):
        continue
    unresolved += 1
    first = (t.get("comments") or [{}])[0]
    who = LOGIN_TO_NAME.get(norm_login(first.get("author")), "other")
    by_reviewer[who] = by_reviewer.get(who, 0) + 1

# --- reviewers -----------------------------------------------------------
MENTIONS = {
    "coderabbit": ("@coderabbitai review", "@coderabbitai full review"),
    "cubic": ("@cubic-dev-ai review",),
}
comments.sort(key=lambda c: epoch(c.get("created_at")))
reviews.sort(key=lambda r: epoch(r.get("submitted_at")))

reviewer_rows = []
for name in reviewers:
    login = BOTS[name]
    row = {"name": name, "status": None, "on_head": False, "ack": None, "reason": None}
    bot_comments = [c for c in comments if norm_login(c.get("user")) == login]
    last_bot_comment = bot_comments[-1] if bot_comments else None
    body = (last_bot_comment or {}).get("body") or ""
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
        if on_head and latest["state"] == "APPROVED":
            row["status"] = "APPROVED"
        elif on_head:
            row["status"] = "NOT_APPROVED"
            row["reason"] = f"latest review on the head is {latest['state']}"
        else:
            mention_after_head = None
            for c in comments:
                lead = (c.get("body") or "").lstrip().lower()
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
                row["reason"] = f"last live review is on {(latest.get('commit_id') or '')[:7]}"
            else:
                row["status"] = "NONE"
                row["reason"] = "has never reviewed this PR"
    reviewer_rows.append(row)

# --- verdict -------------------------------------------------------------
state = pr.get("state") or "UNKNOWN"
mergeable = pr.get("mergeable") or "UNKNOWN"
needs_request = [r for r in reviewer_rows if r["status"] in ("NONE", "STALE")
                 or (r["status"] == "NOT_APPROVED" and by_reviewer.get(r["name"], 0) == 0)]
in_flight = [r for r in reviewer_rows if r["status"] == "REQUESTED"]
skipped = [r for r in reviewer_rows if r["status"] == "SKIPPED"]
for r in skipped:
    notes.append(f"{r['name']}: SKIPPED — {r['reason']}; its missing review is reported, not passed")
if reviewer_rows and len(skipped) == len(reviewer_rows):
    notes.append("every requested reviewer is unreachable — fall back to the plugin's own review loop (/fe-sdlc-review)")

if state != "OPEN":
    verdict, nxt = "BLOCKED", f"PR is {state}; nothing bounded to do — reopen or stop"
elif mergeable == "CONFLICTING":
    verdict, nxt = "BLOCKED", "PR is CONFLICTING — resolve the merge conflict, push, then re-run"
elif ci_status == "red" or unresolved:
    verdict = "FIX"
    parts = []
    if failing:
        parts.append(f"fix failing checks {','.join(failing)} (ci-fixer)")
    if unresolved:
        parts.append(f"resolve {unresolved} review thread(s) (pr-comment-resolver)")
    nxt = "; ".join(parts) + "; then commit and push"
elif needs_request:
    verdict = "REQUEST"
    names = ",".join(r["name"] for r in needs_request)
    full = " --full" if any(r["status"] == "NOT_APPROVED" and r["name"] == "coderabbit" for r in needs_request) else ""
    nxt = f"request-ai-reviews.sh --pr {pr.get('number')} --reviewers {names}{full}"
elif ci_status == "pending" or in_flight:
    verdict = "WAIT"
    what = []
    if pending or missing:
        what.append(f"checks {','.join(pending + missing)}")
    if in_flight:
        what.append("reviews from " + ",".join(r["name"] for r in in_flight))
    nxt = f"pr-state.sh --pr {pr.get('number')} --wait-seconds 540 — waiting for " + " and ".join(what)
else:
    verdict, nxt = "READY", "exit condition met — hand the PR to its human merger"

result = {
    "pr": pr.get("number"), "url": pr.get("url"), "repo": repo, "head": head,
    "state": state, "draft": bool(pr.get("isDraft")), "mergeable": mergeable,
    "ci": {"status": ci_status, "failing": failing, "pending": pending, "missing": missing,
           "checks": checks},
    "unresolved": {"total": unresolved, "by_reviewer": by_reviewer},
    "reviewers": reviewer_rows, "notes": notes, "verdict": verdict, "next": nxt,
}
if json_out == "1":
    print(json.dumps(result, indent=2, sort_keys=True))
else:
    print(f"PR: #{result['pr']} {repo} head={head[:7]} state={state} draft={str(result['draft']).lower()} mergeable={mergeable}")
    print(f"CI: {ci_status} failing=[{','.join(failing)}] pending=[{','.join(pending)}] missing=[{','.join(missing)}]")
    print(f"UNRESOLVED: {unresolved}" + (" (" + " ".join(f"{k}={v}" for k, v in sorted(by_reviewer.items())) + ")" if by_reviewer else ""))
    for r in reviewer_rows:
        extra = f" ack={'yes' if r['ack'] else 'no'}" if r["status"] == "REQUESTED" else ""
        extra += f" head={'current' if r['on_head'] else 'other'}" if r["status"] in ("APPROVED", "NOT_APPROVED") else ""
        extra += f" — {r['reason']}" if r["reason"] else ""
        print(f"REVIEWER: {r['name']} status={r['status']}{extra}")
    for n in notes:
        print(f"INFO: {n}")
    print(f"VERDICT: {verdict}")
    print(f"NEXT: {nxt}")
PY
}

verdict_of() {
  if [[ "$JSON_OUT" -eq 1 ]]; then
    python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])' <<<"$1"
  else
    sed -n 's/^VERDICT: //p' <<<"$1"
  fi
}

start="${SDLC_NOW_EPOCH:-$(date -u +%s)}"
while :; do
  out="$(snapshot)"
  if [[ ",$WAIT_VERDICTS," != *",$(verdict_of "$out"),"* ]]; then
    break
  fi
  elapsed=$(( ${SDLC_NOW_EPOCH:-$(date -u +%s)} - start ))
  if (( elapsed + INTERVAL > WAIT )); then
    break
  fi
  sleep "$INTERVAL"
  [[ -n "${SDLC_NOW_EPOCH:-}" ]] && SDLC_NOW_EPOCH=$(( SDLC_NOW_EPOCH + INTERVAL ))
done
printf '%s\n' "$out"
