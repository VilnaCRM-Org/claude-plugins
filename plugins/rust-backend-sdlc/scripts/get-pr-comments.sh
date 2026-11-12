#!/usr/bin/env bash
# get-pr-comments.sh — every review thread and issue comment of a pull request, with resolution state and author association.
#
# Usage: get-pr-comments.sh [--pr N] [--unresolved-only] [--json]
#   --pr N             pull-request number, ^[1-9][0-9]*$ up to 2147483647
#                      (GraphQL Int); default: the current branch's pull
#                      request from `gh pr view --json number --jq .number`,
#                      validated the same way
#   --unresolved-only  keep only unresolved review threads and drop every
#                      issue comment (issue comments carry no resolution
#                      state, so "0 unresolved" stays reachable)
#   --json             print {"pr": N, "review_threads": [{"is_resolved",
#                      "comments": [{"author", "author_association", "body",
#                      "path", "line", "url"}]}], "issue_comments":
#                      [{"author", "author_association", "body", "url"}]}
#                      instead of the listing
#   --help             print this help and exit 0 (accepted in any position)
#
# Owner and name come from resolve_repo_slug. One paginated `gh api graphql`
# query reads the review threads 100 per page (`after: $cursor`), following
# pageInfo.endCursor until hasNextPage is false, so threads beyond the first
# 100 are listed and counted; issue comments come from the first page. A
# GraphQL error, a missing pull request or a malformed page exits 1: the
# unresolved count is never reported from incomplete data. `author` is the
# login (`unknown` for a deleted account) and `author_association` is
# GitHub's OWNER MEMBER COLLABORATOR CONTRIBUTOR FIRST_TIME_CONTRIBUTOR
# FIRST_TIMER MANNEQUIN NONE (any other value reads NONE), so a caller acts
# only on trusted authors (ADR-26). Control characters other than tab and
# newline are stripped from every string. Rendering uses jq when present,
# else python3, byte for byte the same. The listing ends with the line
# `unresolved threads: N`. Nothing is written to disk.
#
# Exit: 0 comments printed; 1 gh absent, no pull request, invalid PR number from gh, unresolvable repository, gh failure or malformed response; 2 usage error (unknown flag, missing value, invalid --pr)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# GraphQL Int is a signed 32-bit integer: no pull request can carry a larger
# number, and both renderers print every accepted value identically.
GPC_PR_MAX=2147483647
# Upper bound on review-thread pages (100 threads each).
GPC_MAX_PAGES=1000

# The one query (FR-36), field set exactly as the script contract states.
# shellcheck disable=SC2016 # $cursor, $owner, $name and $pr are GraphQL variables
GPC_THREADS='reviewThreads(first: 100, after: $cursor) { nodes { isResolved comments(first: 100) { nodes { author { login } authorAssociation body path line url } } } pageInfo { hasNextPage endCursor } }'
GPC_ISSUE_COMMENTS='comments(first: 100) { nodes { author { login } authorAssociation body url } }'
# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
GPC_QUERY='query($owner: String!, $name: String!, $pr: Int!, $cursor: String) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) { '"$GPC_THREADS $GPC_ISSUE_COMMENTS"' } } }'

# --- jq programs ---------------------------------------------------------------

# Shared definitions: `clean` drops C0 controls except tab and newline, DEL
# and C1 controls, and maps lone surrogates to U+FFFD (the python twin does
# the same, so both backends print the same bytes). The regex test (\p{Cc} is
# exactly U+0000-001F and U+007F-009F) only skips the costly codepoint walk
# for strings without a control character; a jq without regex support walks
# every string.
# shellcheck disable=SC2016 # jq source
GPC_JQ_DEFS='
def clean: if (try test("(?![\t\n])\\p{Cc}") catch true)
  then explode | map(if . == 9 or . == 10 then . elif . < 32 or (. >= 127 and . <= 159) then empty elif . >= 55296 and . <= 57343 then 65533 else . end) | implode
  else . end;
def oneline: clean | split("\n") | join(" ") | split("\t") | join(" ");
def isobj: type == "object";
def conn_ok: isobj and ((.nodes | type) == "array") and all(.nodes[]; isobj);
'

# Page inspection: one verdict line — NONJSON, ERRORS: <messages>,
# SHAPE: <detail>, NOPR, LAST or NEXT: <endCursor>. Input is slurped (-s), so
# anything but exactly one JSON value is NONJSON; so are NaN and infinite
# numbers and lone surrogate escapes, which jq and python3 parse differently.
# shellcheck disable=SC2016 # jq source
GPC_JQ_INSPECT='
def structure_ok:
  (.reviewThreads | isobj)
  and ((.reviewThreads.nodes | type) == "array")
  and ((.reviewThreads.pageInfo | type) == "object")
  and ((.reviewThreads.pageInfo.hasNextPage | type) == "boolean")
  and all(.reviewThreads.nodes[]; isobj and ((.isResolved | type) == "boolean") and (.comments | conn_ok))
  and (.comments | conn_ok);
def cursor_ok: type == "string" and length > 0 and all(explode[]; . >= 32 and . != 127);
if length != 1 then "NONJSON"
elif any(.[0] | .. | numbers; isnan or isinfinite) then "NONJSON"
else .[0]
  | if type != "object" then "SHAPE: the top-level JSON value is \(type), not an object"
    elif ((.errors | type) == "array") and ((.errors | length) > 0) then
      "ERRORS: " + ([.errors[] | (if isobj and ((.message | type) == "string") then .message else tojson end) | oneline] | join("; "))
    elif .data == null then "NOPR"
    elif (.data | isobj | not) then "SHAPE: .data is not an object"
    elif .data.repository == null then "NOPR"
    elif (.data.repository | isobj | not) then "SHAPE: .data.repository is not an object"
    elif .data.repository.pullRequest == null then "NOPR"
    elif (.data.repository.pullRequest | isobj | not) then "SHAPE: pullRequest is not an object"
    else .data.repository.pullRequest
      | if ((try structure_ok catch false) | not) then "SHAPE: pull-request data has an unexpected structure"
        elif (.reviewThreads.pageInfo.hasNextPage | not) then "LAST"
        elif (.reviewThreads.pageInfo.endCursor | cursor_ok) then "NEXT: " + .reviewThreads.pageInfo.endCursor
        else "SHAPE: hasNextPage is true but endCursor is missing or malformed" end
    end
end
'

# Normalization: the slurped, already inspected pages → the --json document.
# shellcheck disable=SC2016 # jq source
GPC_JQ_NORMALIZE='
def text($d): if type == "string" then clean else $d end;
def login: (if (.author | type) == "object" then (.author.login | text("")) else "" end) | if . == "" then "unknown" else . end;
def assoc: .authorAssociation as $a
  | if any(("OWNER", "MEMBER", "COLLABORATOR", "CONTRIBUTOR", "FIRST_TIME_CONTRIBUTOR", "FIRST_TIMER", "MANNEQUIN", "NONE"); . == $a)
    then $a else "NONE" end;
def line_no: if type == "number" and . >= 0 and . == floor and (tostring | explode | all(.[]; . >= 48 and . <= 57)) then . else null end;
. as $pages
| { pr: $pr,
    review_threads: [ $pages[] | .data.repository.pullRequest.reviewThreads.nodes[]
      | select(($uo == 0) or (.isResolved | not))
      | { is_resolved: .isResolved,
          comments: [ .comments.nodes[]
            | { author: login, author_association: assoc, body: (.body | text("")),
                path: (.path | text(null)), line: (.line | line_no), url: (.url | text(null)) } ] } ],
    issue_comments: (if $uo == 1 then [] else
      [ $pages[0].data.repository.pullRequest.comments.nodes[]
        | { author: login, author_association: assoc, body: (.body | text("")), url: (.url | text(null)) } ] end) }
'

# Listing: the --json document → human lines. Continuation lines of a body are
# indented, so no comment text can start a line at column 0 (a body cannot
# forge the closing `unresolved threads:` line).
# shellcheck disable=SC2016 # jq source
GPC_JQ_RENDER='
def rstrip_nl: if endswith("\n") then explode | until(length == 0 or .[-1] != 10; .[:-1]) | implode else . end;
def said($pad): (.body | rstrip_nl) as $b
  | "(\(.author), \(.author_association))" + (if $b == "" then "" else " " + ($b | split("\n") | join("\n" + $pad)) end);
def tail_url: if (.url // "") == "" then "" else " " + .url end;
"PR #\(.pr)",
"== Review threads ==",
(.review_threads[]
  | (.comments[0] // {}) as $f
  | "[\(if .is_resolved then "resolved" else "unresolved" end)] \(if ($f.path // "") == "" then "?" else $f.path end):\(if $f.line == null then "?" else $f.line end)" + ($f | tail_url),
    (.comments[] | "    " + said("      "))),
"== Issue comments ==",
(.issue_comments[] | "[comment]" + tail_url, "    " + said("      ")),
"unresolved threads: \([.review_threads[] | select(.is_resolved | not)] | length)"
'

# --- python3 twin (jq absent) ----------------------------------------------------

# shellcheck disable=SC2016 # python source
GPC_PY='
import json
import math
import sys

ASSOCIATIONS = ("OWNER", "MEMBER", "COLLABORATOR", "CONTRIBUTOR",
                "FIRST_TIME_CONTRIBUTOR", "FIRST_TIMER", "MANNEQUIN", "NONE")
DROP = {o: None for o in list(range(0, 9)) + list(range(11, 32)) + list(range(127, 160))}
DROP.update({o: 0xFFFD for o in range(0xD800, 0xE000)})


def clean(s):
    return s.translate(DROP)


def oneline(s):
    return clean(s).replace("\n", " ").replace("\t", " ")


def jq_type(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    return "object"


def finite(literal):
    value = float(literal)
    if math.isinf(value) or math.isnan(value):
        raise ValueError("non-finite number")
    return value


def finite_int(literal):
    value = int(literal)
    try:
        float(value)
    except OverflowError:
        raise ValueError("number out of range")
    return value


def no_constant(name):
    raise ValueError("non-finite number " + name)


def read_values():
    text = sys.stdin.buffer.read().decode("utf-8", "replace")
    decoder = json.JSONDecoder(parse_float=finite, parse_int=finite_int, parse_constant=no_constant)
    values, i, n = [], 0, len(text)
    while i < n:
        if text[i] in " \t\n\r":
            i += 1
            continue
        value, i = decoder.raw_decode(text, i)
        values.append(value)
    return values


def conn_ok(v):
    return (isinstance(v, dict) and isinstance(v.get("nodes"), list)
            and all(isinstance(x, dict) for x in v["nodes"]))


def structure_ok(p):
    rt = p.get("reviewThreads")
    if not isinstance(rt, dict) or not isinstance(rt.get("nodes"), list):
        return False
    info = rt.get("pageInfo")
    if not isinstance(info, dict) or not isinstance(info.get("hasNextPage"), bool):
        return False
    for t in rt["nodes"]:
        if (not isinstance(t, dict) or not isinstance(t.get("isResolved"), bool)
                or not conn_ok(t.get("comments"))):
            return False
    return conn_ok(p.get("comments"))


def cursor_ok(c):
    return isinstance(c, str) and c != "" and all(ord(ch) >= 32 and ord(ch) != 127 for ch in c)


def inspect():
    try:
        docs = read_values()
    except ValueError:
        return "NONJSON"
    if len(docs) != 1:
        return "NONJSON"
    d = docs[0]
    try:
        json.dumps(d, ensure_ascii=False).encode("utf-8")
    except UnicodeEncodeError:
        return "NONJSON"
    if not isinstance(d, dict):
        return "SHAPE: the top-level JSON value is %s, not an object" % jq_type(d)
    errors = d.get("errors")
    if isinstance(errors, list) and errors:
        msgs = []
        for e in errors:
            if isinstance(e, dict) and isinstance(e.get("message"), str):
                msgs.append(oneline(e["message"]))
            else:
                msgs.append(oneline(json.dumps(e, ensure_ascii=False, separators=(",", ":"))))
        return "ERRORS: " + "; ".join(msgs)
    data = d.get("data")
    if data is None:
        return "NOPR"
    if not isinstance(data, dict):
        return "SHAPE: .data is not an object"
    repo = data.get("repository")
    if repo is None:
        return "NOPR"
    if not isinstance(repo, dict):
        return "SHAPE: .data.repository is not an object"
    p = repo.get("pullRequest")
    if p is None:
        return "NOPR"
    if not isinstance(p, dict):
        return "SHAPE: pullRequest is not an object"
    if not structure_ok(p):
        return "SHAPE: pull-request data has an unexpected structure"
    info = p["reviewThreads"]["pageInfo"]
    if not info["hasNextPage"]:
        return "LAST"
    if cursor_ok(info.get("endCursor")):
        return "NEXT: " + info["endCursor"]
    return "SHAPE: hasNextPage is true but endCursor is missing or malformed"


def text(v, default):
    return clean(v) if isinstance(v, str) else default


def login(c):
    a = c.get("author")
    s = text(a.get("login"), "") if isinstance(a, dict) else ""
    return s or "unknown"


def assoc(c):
    a = c.get("authorAssociation")
    return a if isinstance(a, str) and a in ASSOCIATIONS else "NONE"


def line_no(v):
    return v if type(v) is int and v >= 0 else None


def normalize(pr, unresolved_only):
    pages = read_values()
    threads = []
    for page in pages:
        for t in page["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]:
            if unresolved_only and t["isResolved"]:
                continue
            threads.append({
                "is_resolved": t["isResolved"],
                "comments": [
                    {"author": login(c), "author_association": assoc(c),
                     "body": text(c.get("body"), ""), "path": text(c.get("path"), None),
                     "line": line_no(c.get("line")), "url": text(c.get("url"), None)}
                    for c in t["comments"]["nodes"]
                ],
            })
    issue = [] if unresolved_only else [
        {"author": login(c), "author_association": assoc(c),
         "body": text(c.get("body"), ""), "url": text(c.get("url"), None)}
        for c in pages[0]["data"]["repository"]["pullRequest"]["comments"]["nodes"]
    ]
    doc = {"pr": pr, "review_threads": threads, "issue_comments": issue}
    return json.dumps(doc, indent=2, ensure_ascii=False)


def said(c, pad):
    b = c["body"].rstrip("\n")
    head = "(%s, %s)" % (c["author"], c["author_association"])
    return head if b == "" else head + " " + ("\n" + pad).join(b.split("\n"))


def tail_url(c):
    return " " + c["url"] if c.get("url") else ""


def render():
    d = read_values()[0]
    out = ["PR #%s" % d["pr"], "== Review threads =="]
    for t in d["review_threads"]:
        f = t["comments"][0] if t["comments"] else {}
        state = "resolved" if t["is_resolved"] else "unresolved"
        path = f.get("path") or "?"
        line = "?" if f.get("line") is None else str(f["line"])
        out.append("[%s] %s:%s%s" % (state, path, line, tail_url(f)))
        for c in t["comments"]:
            out.append("    " + said(c, "      "))
    out.append("== Issue comments ==")
    for c in d["issue_comments"]:
        out.append("[comment]" + tail_url(c))
        out.append("    " + said(c, "      "))
    unresolved = sum(1 for t in d["review_threads"] if not t["is_resolved"])
    out.append("unresolved threads: %d" % unresolved)
    return "\n".join(out)


mode = sys.argv[1]
if mode == "inspect":
    result = inspect()
elif mode == "normalize":
    result = normalize(int(sys.argv[2]), sys.argv[3] == "1")
else:
    result = render()
sys.stdout.buffer.write((result + "\n").encode("utf-8"))
'

# --- backend dispatch -----------------------------------------------------------

# gpc_inspect — stdin: one gh page; prints the verdict line (NONJSON when the
# backend cannot parse the input).
gpc_inspect() {
  if have_jq; then
    jq -rs "$GPC_JQ_DEFS$GPC_JQ_INSPECT" 2>/dev/null || printf 'NONJSON\n'
  else
    python3 -I -c "$GPC_PY" inspect 2>/dev/null || printf 'NONJSON\n'
  fi
}

# gpc_normalize PR UNRESOLVED_ONLY — stdin: the inspected pages; prints the
# --json document.
gpc_normalize() {
  if have_jq; then
    jq -s --argjson pr "$1" --argjson uo "$2" "$GPC_JQ_DEFS$GPC_JQ_NORMALIZE"
  else
    python3 -I -c "$GPC_PY" normalize "$1" "$2"
  fi
}

# gpc_render — stdin: the --json document; prints the listing.
gpc_render() {
  if have_jq; then
    jq -r "$GPC_JQ_DEFS$GPC_JQ_RENDER"
  else
    python3 -I -c "$GPC_PY" render
  fi
}

# gpc_valid_pr S — S is a pull-request number GraphQL can carry.
gpc_valid_pr() {
  [[ "${1-}" =~ ^[1-9][0-9]*$ ]] && ! num_gt "$1" "$GPC_PR_MAX"
}

# --- arguments ------------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done

PR=""
UNRESOLVED_ONLY=0
JSON_OUT=0
while (($#)); do
  case "$1" in
    --pr)
      need_value "$1" "${2-}"
      PR="$2"
      shift 2
      ;;
    --unresolved-only)
      UNRESOLVED_ONLY=1
      shift
      ;;
    --json)
      JSON_OUT=1
      shift
      ;;
    *) die_usage "unknown argument: ${1//[[:cntrl:]]/}" ;;
  esac
done

if [[ -n "$PR" ]] && ! gpc_valid_pr "$PR"; then
  die_usage "--pr must be a pull-request number (^[1-9][0-9]*$, at most $GPC_PR_MAX), got: ${PR//[[:cntrl:]]/}"
fi

# --- environment ----------------------------------------------------------------

have_cmd gh || die "gh CLI not found on PATH: install the GitHub CLI to read pull-request comments"
have_jq || have_cmd python3 || die "neither jq nor python3 is on PATH: install python3"

if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq .number)" ||
    die "no pull request found for the current branch: pass --pr N"
  gpc_valid_pr "$PR" ||
    die "gh pr view returned an invalid pull-request number: '${PR//[[:cntrl:]]/}' (expected ^[1-9][0-9]*$): pass --pr N"
fi

SLUG="$(resolve_repo_slug)" ||
  die "cannot resolve the repository: no github.com origin remote and gh repo view failed"
OWNER="${SLUG%%/*}"
NAME="${SLUG#*/}"
WHERE="PR #$PR in $OWNER/$NAME"

# --- paginated read ---------------------------------------------------------------

declare -A SEEN_CURSORS=()
cursor=""
page=0
more=1
pages=""
while ((more)); do
  page=$((page + 1))
  if ((page > GPC_MAX_PAGES)); then
    die "more than $GPC_MAX_PAGES pages of review threads for $WHERE: the unresolved count is unknowable"
  fi
  args=(api graphql -f "query=$GPC_QUERY" -f "owner=$OWNER" -f "name=$NAME" -F "pr=$PR")
  if [[ -n "$cursor" ]]; then
    args+=(-f "cursor=$cursor")
  fi
  raw="$(gh "${args[@]}")" || die "gh api graphql failed for $WHERE (page $page)"
  # A leading UTF-8 BOM is dropped once (jq tolerates it, python does not);
  # tail cuts its three bytes, as a ${raw#…} prefix removal is quadratic in bash.
  if [[ "$raw" == $'\xef\xbb\xbf'* ]]; then
    raw="$(printf '%s' "$raw" | tail -c +4)"
  fi
  if [[ "$raw" =~ ^[[:space:]]*$ ]]; then
    die "gh api graphql returned an empty response for $WHERE (page $page): check gh auth status, then retry"
  fi
  verdict="$(printf '%s' "$raw" | gpc_inspect)"
  case "$verdict" in
    LAST) more=0 ;;
    'NEXT: '?*)
      next="${verdict#NEXT: }"
      if [[ -n "${SEEN_CURSORS[$next]+x}" ]]; then
        die "pagination did not advance for $WHERE: endCursor $next was already read; the unresolved count is unknowable"
      fi
      SEEN_CURSORS[$next]=1
      cursor="$next"
      ;;
    NONJSON)
      die "gh api graphql returned non-JSON output for $WHERE (page $page): check gh auth status, then retry"
      ;;
    'ERRORS: '*)
      die "gh api graphql reported an error for $WHERE: ${verdict#ERRORS: }"
      ;;
    'SHAPE: '*)
      die "gh api graphql returned an unexpected response shape for $WHERE (page $page): ${verdict#SHAPE: }; the unresolved count is unknowable"
      ;;
    NOPR)
      die "gh api graphql returned no pull-request data for $WHERE: the pull request may not exist; the unresolved count is unknowable"
      ;;
    *)
      die "cannot inspect the gh api graphql response for $WHERE (page $page)"
      ;;
  esac
  pages+="$raw"$'\n'
done

# --- output -------------------------------------------------------------------------

canonical="$(printf '%s' "$pages" | gpc_normalize "$PR" "$UNRESOLVED_ONLY")" ||
  die "cannot normalize the review threads of $WHERE"

if ((JSON_OUT)); then
  printf '%s\n' "$canonical"
  exit 0
fi
printf '%s\n' "$canonical" | gpc_render
