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

# Validate the PR number whatever its source. The --pr guard above runs
# only on the flag path; a gh-resolved value (above) skipped it, so a
# non-numeric or empty `gh pr view` result (e.g. a misconfigured wrapper
# or detached HEAD) would otherwise reach `jq --argjson pr` and surface as
# a raw 'jq: invalid JSON text passed to --argjson' (exit 2) instead of a
# clean script-level diagnosis.
if [[ ! "$PR" =~ ^[0-9]+$ ]]; then
  die "resolved PR number is not numeric: '$PR' (gh pr view returned an unexpected value; pass --pr <n>)"
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

# Strip a leading UTF-8 BOM (EF BB BF) once, before any backend consumes
# $raw. jq 1.7+ silently tolerates a leading BOM while python's json.load
# rejects it ("Unexpected UTF-8 BOM"), so a BOM-prefixed payload would make
# the jq and python paths diverge — one rendering the data, the other dying
# 'non-JSON output'. gh never emits a BOM in practice, so removing it is
# behaviour-preserving for real responses and keeps both backends identical.
raw="${raw#$'\xef\xbb\xbf'}"

# raw_is_json — exit 0 when $raw parses as JSON. gh can exit 0 yet emit
# non-JSON (proxy HTML error pages, prompts); without this guard that
# output reaches the normalize step and surfaces as a raw jq parse error
# or python traceback instead of a script-level diagnosis.
raw_is_json() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq empty >/dev/null 2>&1
  else
    printf '%s' "$raw" | python3 -c 'import json, sys
json.load(sys.stdin)' >/dev/null 2>&1
  fi
}

# An empty body is not "JSON" for our purposes even though `jq empty`
# accepts empty input (the python backend rejects it): treat it as the
# non-JSON case so both backends diverge no further (an empty fetch carries
# no PR data and must not be reported as "0 unresolved").
[[ -n "$raw" ]] \
  || die "gh api graphql returned an empty response for PR #$PR in $OWNER/$NAME (check 'gh auth status' and network/proxy, then retry)"

raw_is_json \
  || die "gh api graphql returned non-JSON output for PR #$PR in $OWNER/$NAME (check 'gh auth status' and network/proxy, then retry)"

# pr_data_present — the payload must actually carry pull-request data of the
# expected SHAPE before any "0 unresolved" conclusion is drawn (FR-8). gh can
# exit 0 with a body that parses as JSON yet has NO usable PR: a GraphQL error
# envelope ({"data":null,"errors":[...]}), a wrong-shape object ({"ok":true}),
# or an explicit null pullRequest ({"data":{"repository":{"pullRequest":null}}}).
# It can ALSO exit 0 with valid JSON of the wrong TYPE: a top-level array or
# scalar ([1,2,3], 42, "hello", true), or an object whose pullRequest (or one
# of its child connections) is the wrong type
# ({"data":{"repository":{"pullRequest":{"reviewThreads":"oops",...}}}}).
# The null/error/wrong-shape cases previously normalized to "unresolved
# threads: 0" with exit 0 (a false "nothing to resolve"); the wrong-TYPE cases
# slipped past this guard entirely — every guard here runs under 2>/dev/null,
# so a type error in the guard itself was swallowed into "no problem" and the
# un-guarded normalize()/has_next_page() step downstream died with a bare jq
# exit 5 / python traceback and ZERO script-level diagnostic. This check must
# therefore positively validate the structural contract those later steps rely
# on (a top-level object; a pullRequest that is an object; reviewThreads /
# comments connections of the expected type) and emit a clean diagnostic for
# any deviation, never silently pass it through. Both backends apply the
# identical check.
pr_data_check() {
  if command -v jq >/dev/null 2>&1; then
    # Plain `jq -r` (no -e): -e sets exit 4 when the result is empty, which
    # is exactly the healthy "no problem" case, and that nonzero status
    # would propagate through the command substitution. Emit the diagnostic
    # string on a problem, nothing otherwise. `type` never errors on any
    # value, and the connection traversal is wrapped in try/catch so a
    # wrong-type child surfaces here as SHAPE rather than aborting jq.
    printf '%s' "$raw" | jq -r '
      if (type != "object")
        then "SHAPE: top-level JSON is a \(type), not an object"
      elif (.errors | type == "array" and length > 0)
        then "ERRORS: " + ([.errors[].message] | join("; "))
      elif ((try (.data.repository.pullRequest == null) catch "ERR") == "ERR")
        then "SHAPE: response is not the expected repository/pullRequest object"
      elif (.data.repository.pullRequest == null)
        then "NOPR"
      elif ((try (
              (.data.repository.pullRequest) as $p
              # Force per-ELEMENT object access exactly as normalize does:
              # each review thread, each thread comment, and each issue
              # comment must be an object. A scalar node (e.g. comments
              # .nodes:[42]) passes a nodes-is-a-list check but makes the
              # later .author/.body index abort with a bare
              # "jq error Cannot index number". has(...) forces an index that
              # errors on a non-object node; all(...) over a collected array
              # consumes the whole stream and still yields a single value, so
              # the pipe below always reaches "ok" on healthy data while any
              # wrong-type node aborts the try and surfaces as SHAPE here.
              | ([ ($p.reviewThreads.nodes // [])[] ] | all(has("isResolved")))
              | ([ ($p.reviewThreads.nodes // [])[] | (.comments.nodes // [])[] ]
                 | all(has("author")))
              | ([ ($p.comments.nodes // [])[] ] | all(has("author")))
              | ($p.reviewThreads.pageInfo.hasNextPage // false)
              | "ok"
            ) catch "ERR") == "ERR")
        then "SHAPE: pull-request data has an unexpected structure"
      else empty end' 2>/dev/null
  else
    printf '%s' "$raw" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    print("SHAPE: top-level JSON is a %s, not an object" % type(d).__name__)
    sys.exit(0)
errs = d.get("errors")
if isinstance(errs, list) and errs:
    print("ERRORS: " + "; ".join(
        str(e.get("message", e)) if isinstance(e, dict) else str(e) for e in errs))
    sys.exit(0)
data = d.get("data")
if data is not None and not isinstance(data, dict):
    print("SHAPE: .data is not an object")
    sys.exit(0)
repo = (data or {}).get("repository")
if repo is not None and not isinstance(repo, dict):
    print("SHAPE: .data.repository is not an object")
    sys.exit(0)
pr = (repo or {}).get("pullRequest")
if pr is None:
    print("NOPR")
    sys.exit(0)
if not isinstance(pr, dict):
    print("SHAPE: pullRequest is not an object")
    sys.exit(0)

def conn_ok(obj, key):
    v = obj.get(key)
    if v is None:
        return True
    if not isinstance(v, dict):
        return False
    nodes = v.get("nodes")
    return nodes is None or isinstance(nodes, list)

def nodes_of(obj, key):
    return ((obj.get(key) or {}).get("nodes")) or []

# Each comment node (issue comments AND thread comments) must itself be an
# object: a scalar node (e.g. comments.nodes:[42]) passes conn_ok (nodes IS a
# list) but makes the later c.get("author") raise a bare AttributeError.
def comments_ok(nodes):
    return all(isinstance(c, dict) for c in nodes)

if not conn_ok(pr, "reviewThreads") or not conn_ok(pr, "comments"):
    print("SHAPE: pull-request data has an unexpected structure")
    sys.exit(0)
if not comments_ok(nodes_of(pr, "comments")):
    print("SHAPE: pull-request data has an unexpected structure")
    sys.exit(0)
for t in nodes_of(pr, "reviewThreads"):
    if (not isinstance(t, dict) or not conn_ok(t, "comments")
            or not comments_ok(nodes_of(t, "comments"))):
        print("SHAPE: pull-request data has an unexpected structure")
        sys.exit(0)
' 2>/dev/null
  fi
}

pr_data_problem="$(pr_data_check)"
if [[ -n "$pr_data_problem" ]]; then
  if [[ "$pr_data_problem" == ERRORS:* ]]; then
    die "gh api graphql reported an error for PR #$PR in $OWNER/$NAME: ${pr_data_problem#ERRORS: }"
  fi
  if [[ "$pr_data_problem" == SHAPE:* ]]; then
    die "gh api graphql returned an unexpected response shape for PR #$PR in $OWNER/$NAME: ${pr_data_problem#SHAPE: } (the unresolved count is unknowable)"
  fi
  die "gh api graphql returned no pull-request data for PR #$PR in $OWNER/$NAME (the PR may not exist, or the response shape is unexpected; the unresolved count is unknowable)"
fi

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
