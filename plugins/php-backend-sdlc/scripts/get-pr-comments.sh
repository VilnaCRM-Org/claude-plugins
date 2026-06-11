#!/usr/bin/env bash
# get-pr-comments.sh — resolution-aware PR comment listing (FR-8 feed).
#
# Usage: get-pr-comments.sh [--pr <n>] [--unresolved-only] [--json]
#   --pr <n>           PR number; default: the current branch's PR
#   --unresolved-only  only unresolved review threads; issue comments are
#                      excluded in this mode (they carry no resolution
#                      state, and the FR-8 loop's exit condition is
#                      "0 unresolved" — unresolvable items would make
#                      that unreachable)
#   --json             machine-readable output (canonical shape below)
#
# Fetches reviewThreads(first:100){isResolved, comments...} plus issue
# comments through one gh GraphQL call, then renders either a human
# listing with an 'unresolved threads: N' summary line or canonical
# JSON: {pr, review_threads: [{is_resolved, comments: [{author, body,
# path, line, url}]}], issue_comments: [{author, body, url}]}.
# Transformation uses jq when present, python3 stdlib otherwise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PR=""
UNRESOLVED_ONLY=0
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr needs a value}"; shift 2 ;;
    --unresolved-only) UNRESOLVED_ONLY=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) die "unknown argument: $1 (usage: get-pr-comments.sh [--pr <n>] [--unresolved-only] [--json])" ;;
  esac
done
if [[ -n "$PR" && ! "$PR" =~ ^[0-9]+$ ]]; then
  die "--pr must be a number, got: $PR"
fi
command -v gh >/dev/null 2>&1 || die "gh CLI not found on PATH"

if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq .number 2>/dev/null)" \
    || die "no PR found for the current branch (pass --pr <n>)"
fi

# owner/name from the origin remote; gh repo view as fallback.
origin="$(git remote get-url origin 2>/dev/null || true)"
repo_slug=""
if [[ -n "$origin" ]]; then
  repo_slug="$(printf '%s\n' "$origin" | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')"
fi
if [[ -z "$repo_slug" ]]; then
  repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
    || die "cannot resolve repository (no origin remote and gh repo view failed)"
fi
OWNER="${repo_slug%%/*}"
NAME="${repo_slug##*/}"

# pageInfo is requested on every connection so a PR exceeding any first:100
# page can be detected and refused, never silently truncated: the FR-8 loop
# treats this script as the single source of truth for "what is unresolved",
# so a truncated fetch could report "0 unresolved" while unresolved threads
# remain past the first page and let /sdlc-finish-pr exit early on incomplete
# data. (Minimal guard: fetch one page, die clearly when more pages exist.)
# shellcheck disable=SC2016  # $owner/$name/$pr are GraphQL variables, not shell
QUERY='query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        pageInfo { hasNextPage }
        nodes {
          isResolved
          comments(first: 100) {
            pageInfo { hasNextPage }
            nodes { author { login } body path line url }
          }
        }
      }
      comments(first: 100) {
        pageInfo { hasNextPage }
        nodes { author { login } body url }
      }
    }
  }
}'

raw="$(gh api graphql -f query="$QUERY" -f owner="$OWNER" -f name="$NAME" -F pr="$PR")" \
  || die "gh api graphql failed for PR #$PR in $OWNER/$NAME"

# Refuse truncated data: if any connection reports hasNextPage, the single
# 100-item page is incomplete and the unresolved count would be unreliable.
has_next_page() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -e '
      [ .data.repository.pullRequest
        | (.reviewThreads.pageInfo.hasNextPage // false),
          (.comments.pageInfo.hasNextPage // false),
          ((.reviewThreads.nodes // [])[] | .comments.pageInfo.hasNextPage // false)
      ] | any' >/dev/null 2>&1
  else
    printf '%s' "$raw" | python3 -c '
import json, sys
p = (json.load(sys.stdin).get("data") or {}).get("repository", {}).get("pullRequest") or {}
flags = [
    ((p.get("reviewThreads") or {}).get("pageInfo") or {}).get("hasNextPage"),
    ((p.get("comments") or {}).get("pageInfo") or {}).get("hasNextPage"),
]
for t in (p.get("reviewThreads") or {}).get("nodes") or []:
    flags.append(((t.get("comments") or {}).get("pageInfo") or {}).get("hasNextPage"))
sys.exit(0 if any(flags) else 1)' >/dev/null 2>&1
  fi
}

if has_next_page; then
  die "PR #$PR has more than 100 review threads, thread comments, or issue comments — GraphQL pagination is not supported; the unresolved count would be truncated and unreliable"
fi

# normalize RAW -> canonical JSON, honoring the unresolved-only filter
normalize() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq --argjson pr "$PR" --argjson uo "$UNRESOLVED_ONLY" '
      (.data.repository.pullRequest // {}) as $p |
      { pr: $pr,
        review_threads: [ ($p.reviewThreads.nodes // [])[]
          | select(($uo == 0) or (.isResolved | not))
          | { is_resolved: .isResolved,
              comments: [ (.comments.nodes // [])[]
                | { author: (.author.login // "unknown"),
                    body, path, line, url } ] } ],
        issue_comments: (if $uo == 1 then [] else
          [ ($p.comments.nodes // [])[]
            | { author: (.author.login // "unknown"), body, url } ] end) }'
  else
    printf '%s' "$raw" | python3 -c '
import json, sys
pr = int(sys.argv[1])
unresolved_only = sys.argv[2] == "1"
p = (json.load(sys.stdin).get("data") or {}).get("repository", {}).get("pullRequest") or {}
threads = []
for t in (p.get("reviewThreads") or {}).get("nodes") or []:
    if unresolved_only and t.get("isResolved"):
        continue
    threads.append({
        "is_resolved": t.get("isResolved"),
        "comments": [
            {"author": (c.get("author") or {}).get("login") or "unknown",
             "body": c.get("body"), "path": c.get("path"),
             "line": c.get("line"), "url": c.get("url")}
            for c in (t.get("comments") or {}).get("nodes") or []
        ],
    })
issue_comments = [] if unresolved_only else [
    {"author": (c.get("author") or {}).get("login") or "unknown",
     "body": c.get("body"), "url": c.get("url")}
    for c in (p.get("comments") or {}).get("nodes") or []
]
print(json.dumps({"pr": pr, "review_threads": threads,
                  "issue_comments": issue_comments}, indent=2))
' "$PR" "$UNRESOLVED_ONLY"
  fi
}

canonical="$(normalize)"

if (( JSON_OUT )); then
  printf '%s\n' "$canonical"
  exit 0
fi

# human rendering from the canonical JSON
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$canonical" | jq -r '
    "PR #\(.pr)",
    "== Review threads ==",
    (.review_threads[]
      | "[\(if .is_resolved then "resolved" else "unresolved" end)] \(.comments[0].path // "?"):\(.comments[0].line // 0) \(.comments[0].url // "")",
        (.comments[] | "    (\(.author)) \(.body)")),
    "== Issue comments ==",
    (.issue_comments[] | "  (\(.author)) \(.body) \(.url // "")"),
    "unresolved threads: \([.review_threads[] | select(.is_resolved | not)] | length)"'
else
  printf '%s' "$canonical" | python3 -c '
import json, sys
d = json.load(sys.stdin)
pr = d["pr"]
print(f"PR #{pr}")
print("== Review threads ==")
for t in d["review_threads"]:
    state = "resolved" if t["is_resolved"] else "unresolved"
    first = t["comments"][0] if t["comments"] else {}
    path = first.get("path") or "?"
    line = first.get("line") or 0
    url = first.get("url") or ""
    print(f"[{state}] {path}:{line} {url}")
    for c in t["comments"]:
        author = c["author"]
        body = c["body"]
        print(f"    ({author}) {body}")
print("== Issue comments ==")
for c in d["issue_comments"]:
    author = c["author"]
    body = c["body"]
    url = c.get("url") or ""
    print(f"  ({author}) {body} {url}")
unresolved = sum(1 for t in d["review_threads"] if not t["is_resolved"])
print(f"unresolved threads: {unresolved}")
'
fi
