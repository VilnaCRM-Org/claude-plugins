#!/usr/bin/env bash
# post-review-findings.sh — one up-to-date pull-request comment per review lens, and one review conclusion, from the review ledgers.
#
# Usage: post-review-findings.sh <lens> [--pr N] [--file F]... [--dry-run] [--json] [--bot-login LOGIN]
#        post-review-findings.sh --conclusion [--file F]... [--pr N] [--started-at ISO] [--ended-at ISO] [--duration-seconds N] [--iterations N] [--dry-run] [--json] [--bot-login LOGIN]
#   <lens>                  security | fr-nfr | code-review: post that lens's
#                           findings under the marker
#                           <!-- rust-sdlc-review:<lens> -->
#   --conclusion            post the review conclusion (findings per lens and
#                           severity, start, end, duration, iterations) under
#                           the marker <!-- rust-sdlc-review:conclusion -->
#   --pr N                  pull-request number (^[1-9][0-9]*$, at most
#                           2147483647); default: the current branch's pull
#                           request from `gh pr view --json number --jq .number`
#   --file F                a review ledger (ADR-16 schema), repeatable; the
#                           ledgers of one lens are merged. Default: the lens
#                           ledger ${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}/<lens>.json,
#                           or with --conclusion the three lens ledgers there
#                           (an absent one counts as no ledger for its lens)
#   --dry-run               print `WOULD: post <lens>` and the rendered body;
#                           no gh call, nothing written
#   --json                  print the rendered payload as one JSON object
#                           (lens, marker, iteration as a decimal string,
#                           head_sha, counts, findings, body; with --conclusion
#                           the per-lens counts and times); no gh call,
#                           nothing written; not together with --dry-run
#   --bot-login LOGIN       the posting identity (a GitHub login); default:
#                           `gh api user --jq .login`
#   --started-at ISO        conclusion start, YYYY-MM-DDTHH:MM:SSZ; default:
#                           the earliest started_at of the ledgers
#   --ended-at ISO          conclusion end, YYYY-MM-DDTHH:MM:SSZ; default: the
#                           latest ended_at of the ledgers
#   --duration-seconds N    conclusion duration in seconds (digits); default:
#                           end minus start when both are known
#   --iterations N          review-loop iterations shown in the conclusion
#   --help                  print this help and exit 0 (accepted in any position)
#
# Rendering (FR-37): `dropped` findings are filtered; the rest are sorted by
# severity (Critical, High, Medium, Low, Info) and deduplicated by
# (file, line, rule) with null read as the empty string, the most severe
# first; file, rule and summary pass through `common.sh redact` before they
# are rendered, and the published body passes through it again (ADR-27): it is
# written to target/rust-sdlc/tmp/review-<lens>.raw.md, redacted to
# target/rust-sdlc/tmp/review-<lens>.md and sent with `-F body=@<file>`.
# A ledger without schema_version reads as schema_version 1. Iteration values
# are printed digit for digit, never rounded.
#
# Publishing (ADR-26): the posting identity is resolved once; only a comment
# whose body starts with the marker and whose author is that identity is
# edited (the oldest one, PATCH); without one a comment is created (POST).
# Marker comments by any other author are ignored with
# `DEGRADED: ignored <marker> comment by <login>`; when the identity cannot be
# resolved a new comment is created and none is edited. Nothing is ever
# deleted. The pull request's base repository must be the origin repository.
#
# Degrade-first (ADR-23): capabilities.publish_pr_comments not true (or no
# profile), gh absent, no pull request, an empty or all-dropped ledger, a
# ledger schema_version other than 1, a malformed gh read, a base-repository
# mismatch, a failed write or any unexpected failure prints one
# `DEGRADED: <reason>` line, posts nothing (further) and exits 0. A malformed
# ledger named with --file exits 1 (ledgers are read after the capability
# gate, so with publishing off nothing is read). Stdout:
# `POSTED: <lens> created <url>`, `POSTED: <lens> updated <comment-id>`,
# `WOULD: post <lens>`, the --json payload, `DEGRADED: <reason>`; logs go to
# stderr.
#
# Exit: 0 posted, rendered (--dry-run, --json) or degraded with a `DEGRADED:` line; 1 malformed ledger named with --file (not JSON, not the ADR-16 schema, another lens, unreadable); 2 usage error (unknown flag or lens, missing value, conflicting flags, invalid --pr, --bot-login, time or number)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Largest pull-request number accepted (a signed 32-bit integer).
PRF_PR_MAX=2147483647
PRF_LENSES="security fr-nfr code-review"
PRF_TMP_DIR=target/rust-sdlc/tmp
PRF_ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
PRF_LOGIN_RE='^[A-Za-z0-9][A-Za-z0-9-]{0,38}(\[bot\])?$'

# --- python programs ---------------------------------------------------------

# Ledger load, validation, redaction and rendering. argv: MODE (lens or
# conclusion), LABEL (the lens, or `conclusion`), WORK (output directory),
# BASH, COMMON (lib/common.sh, run as `BASH COMMON redact`), STARTED, ENDED,
# DURATION, ITERATIONS (the conclusion flags, empty when absent), then
# ORIGIN PATH pairs (ORIGIN `file` for --file, `default` for a default
# ledger). Writes WORK/body.md and WORK/payload.json and prints one verdict
# line: `OK`, `DEGRADED <reason>` or `MALFORMED <reason>` (a --file ledger).
# shellcheck disable=SC2016 # python source; `$` ends a regex in its messages
PRF_RENDER_PY='
import json
import os
import re
import subprocess
import sys
import unicodedata
from datetime import datetime, timezone

MODE, LABEL, WORK, BASH, COMMON = sys.argv[1:6]
STARTED_FLAG, ENDED_FLAG, DURATION_FLAG, ITERATIONS_FLAG = sys.argv[6:10]
PAIRS = sys.argv[10:]
SOURCES = list(zip(PAIRS[0::2], PAIRS[1::2]))

LENSES = ("security", "fr-nfr", "code-review")
TITLES = {"security": "Security review", "fr-nfr": "FR/NFR review", "code-review": "Code review"}
PREFIX = {"security": "SEC-", "fr-nfr": "FRN-", "code-review": "CQ-"}
TOP_KEYS = ("schema_version", "lens", "iteration", "head_sha", "findings", "started_at", "ended_at")
KEYS = ("id", "severity", "file", "line", "rule", "summary", "status")
SEVERITIES = ("Critical", "High", "Medium", "Low", "Info")
RANK = {name: index for index, name in enumerate(SEVERITIES)}
STATUSES = ("open", "fixed", "dropped")
ID = re.compile(r"[A-Z]+-[0-9]+")
SHA = re.compile(r"[0-9a-f]{40}")
CTRL = re.compile(r"[\x00-\x08\x0a-\x1f\x7f]")
ISO = "%Y-%m-%dT%H:%M:%SZ"
ISO_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
# Appended to every line of the batched redaction input: the space ends any
# run a pattern could carry into the next line, so a line keeps its sentinel
# exactly when no match touched its end (see redact_all).
SENTINEL = " \u00b6"


class Malformed(Exception):
    pass


class Degraded(Exception):
    pass


def shown(text):
    text = "".join(ch if unicodedata.category(ch)[0] != "C" else "?" for ch in str(text))
    return text[:300]


def one_line(text):
    text = text.encode("utf-8", "replace").decode("utf-8")
    return "".join(" " if unicodedata.category(ch) in ("Cc", "Cf", "Zl", "Zp") else ch for ch in text)


def unique_keys(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError("duplicate key %s" % json.dumps(key))
        seen[key] = value
    return seen


def no_constant(name):
    raise ValueError("%s is not JSON" % name)


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def utc(value):
    return datetime.strptime(value, ISO).replace(tzinfo=timezone.utc)


def is_time(value):
    # Fixed width, so the earliest start and the latest end compare as text.
    if not isinstance(value, str) or not ISO_RE.fullmatch(value):
        return False
    try:
        utc(value)
    except ValueError:
        return False
    return True


def finding_errors(lens, findings):
    errors = []
    ids = set()
    for index, finding in enumerate(findings):
        at = "findings[%d]" % index
        if not isinstance(finding, dict):
            errors.append("%s: not an object" % at)
            continue
        for key in sorted(set(finding) - set(KEYS)):
            errors.append("%s: extra key %s" % (at, json.dumps(key)))
        missing = [key for key in KEYS if key not in finding]
        for key in missing:
            errors.append("%s: missing key %s" % (at, key))
        if missing:
            continue
        fid, severity, path, line, rule, summary, status = (finding[key] for key in KEYS)
        if not isinstance(fid, str) or not ID.fullmatch(fid):
            errors.append("%s.id: %s does not match ^[A-Z]+-[0-9]+$" % (at, json.dumps(fid)))
        elif not fid.startswith(PREFIX[lens]):
            errors.append("%s.id: %s lacks the %s prefix of the %s lens" % (at, fid, PREFIX[lens], lens))
        elif fid in ids:
            errors.append("%s.id: %s is not unique" % (at, fid))
        else:
            ids.add(fid)
        if severity not in SEVERITIES:
            errors.append("%s.severity: %s is not one of %s" % (at, json.dumps(severity), " ".join(SEVERITIES)))
        if path is not None and not (
                isinstance(path, str) and path and not CTRL.search(path) and not path.startswith("/")
                and ".." not in path.replace("\\", "/").split("/")):
            errors.append("%s.file: %s is not a repository-relative path or null" % (at, json.dumps(path)))
        if line is not None and not (is_int(line) and line >= 1):
            errors.append("%s.line: %s is not an integer >= 1 or null" % (at, json.dumps(line)))
        elif line is not None and path is None:
            errors.append("%s.line: must be null when file is null" % at)
        if not isinstance(rule, str) or not rule.strip() or CTRL.search(rule):
            errors.append("%s.rule: %s is not a non-empty single-line string" % (at, json.dumps(rule)))
        if not isinstance(summary, str) or not 1 <= len(summary) <= 300 or CTRL.search(summary):
            errors.append("%s.summary: not a single-line string of 1 to 300 characters" % at)
        if status not in STATUSES:
            errors.append("%s.status: %s is not one of %s" % (at, json.dumps(status), " ".join(STATUSES)))
    return errors


def ledger_errors(doc):
    errors = ["extra top-level key %s" % json.dumps(key) for key in sorted(set(doc) - set(TOP_KEYS))]
    for key in ("lens", "iteration", "head_sha", "findings"):
        if key not in doc:
            errors.append("missing top-level key %s" % key)
    if errors:
        return errors
    if doc["lens"] not in LENSES:
        errors.append("lens %s is not one of %s" % (json.dumps(doc["lens"]), " ".join(LENSES)))
    if not (is_int(doc["iteration"]) and doc["iteration"] >= 0):
        errors.append("iteration %s is not a non-negative integer" % json.dumps(doc["iteration"])[:40])
    if not (isinstance(doc["head_sha"], str) and SHA.fullmatch(doc["head_sha"])):
        errors.append("head_sha is not 40 lower-case hex digits")
    for key in ("started_at", "ended_at"):
        if key in doc and not is_time(doc[key]):
            errors.append("%s is not YYYY-MM-DDTHH:MM:SSZ" % key)
    if not isinstance(doc["findings"], list):
        errors.append("findings is not an array")
    elif doc["lens"] in LENSES:
        errors.extend(finding_errors(doc["lens"], doc["findings"]))
    return errors


def reject(origin, path, why):
    message = "malformed ledger %s: %s" % (shown(path), shown(why))
    if origin == "file":
        raise Malformed(message)
    raise Degraded(message + "; the %s comment is not posted" % LABEL)


def load(origin, path):
    """The validated ledger at PATH, or None for an absent default ledger."""
    if not os.path.lexists(path):
        if origin == "file":
            raise Malformed("ledger file not found: %s" % shown(path))
        return None
    try:
        with open(path, "rb") as handle:
            raw = handle.read()
    except OSError as exc:
        reject(origin, path, "cannot be read (%s)" % (exc.strerror or "error"))
    try:
        doc = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_keys, parse_constant=no_constant)
    except (UnicodeDecodeError, ValueError, RecursionError) as exc:
        reject(origin, path, "not JSON (%s)" % (str(exc).splitlines() or ["invalid JSON"])[0])
    if not isinstance(doc, dict):
        reject(origin, path, "the top-level value is not an object")
    version = doc.get("schema_version", 1)
    if not (is_int(version) and version == 1):
        raise Degraded("ledger %s has schema_version %s, and only schema_version 1 is read; the %s comment is not posted"
                       % (shown(path), shown(json.dumps(version))[:40], LABEL))
    errors = ledger_errors(doc)
    if errors:
        more = " (and %d more)" % (len(errors) - 1) if len(errors) > 1 else ""
        reject(origin, path, errors[0] + more)
    if MODE == "lens" and doc["lens"] != LABEL:
        reject(origin, path, "it is a %s ledger, not a %s ledger" % (doc["lens"], LABEL))
    return doc


def run_redact(text):
    try:
        done = subprocess.run([BASH, COMMON, "redact"], input=text.encode("utf-8"),
                              stdout=subprocess.PIPE, check=False)
    except OSError as exc:
        raise Degraded("cannot run common.sh redact (%s); the %s comment is not posted" % (exc.strerror, LABEL))
    if done.returncode != 0:
        raise Degraded("common.sh redact failed; the %s comment is not posted" % LABEL)
    return done.stdout.decode("utf-8", "replace")


def redact_all(texts):
    """Each text through common.sh redact, as if redacted on its own: one
    batched call with one text per line, then a call of its own for every
    line whose sentinel did not survive (a match reached its end) and for
    every line when a match spanned lines (the line count changed)."""
    if not texts:
        return []
    out = run_redact("".join(text + SENTINEL + "\n" for text in texts)).split("\n")
    if out and out[-1] == "":
        out.pop()
    if len(out) != len(texts):
        return [run_redact(text) for text in texts]
    return [line[:-len(SENTINEL)] if line.endswith(SENTINEL) else run_redact(text)
            for text, line in zip(texts, out)]


def cell(text):
    text = one_line(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return text.replace("|", "\\|").strip() or "n/a"


def location(finding):
    if finding["file"] is None:
        return "requirement-level"
    if finding["line"] is None:
        return finding["file"]
    return "%s:%d" % (finding["file"], finding["line"])


def kept_findings(docs):
    """Non-dropped findings of DOCS, most severe first, one per
    (file, line, rule) with null read as the empty string; and the number of
    findings and of dropped findings read."""
    rows = [dict(finding) for doc in docs for finding in doc["findings"]]
    dropped = sum(1 for row in rows if row["status"] == "dropped")
    live = [row for row in rows if row["status"] != "dropped"]
    live.sort(key=lambda row: RANK[row["severity"]])
    seen = set()
    kept = []
    for row in live:
        key = (row["file"] or "", "" if row["line"] is None else str(row["line"]), row["rule"])
        if key not in seen:
            seen.add(key)
            kept.append(row)
    return kept, len(rows), dropped


def counts(rows):
    result = {"total": len(rows),
              "open": sum(1 for row in rows if row["status"] == "open"),
              "fixed": sum(1 for row in rows if row["status"] == "fixed")}
    for name in SEVERITIES:
        result[name] = sum(1 for row in rows if row["severity"] == name)
    return result


def severity_text(count):
    return ", ".join("%d %s" % (count[name], name) for name in SEVERITIES)


def latest(docs):
    return max(docs, key=lambda doc: doc["iteration"])


def render_lens(docs):
    kept, total, dropped = kept_findings(docs)
    if not kept:
        paths = ", ".join(shown(path) for _origin, path in SOURCES)
        reason = "the ledger is empty" if total == 0 else "every finding is dropped"
        raise Degraded("no findings to post from %s (%s); the %s comment is not posted" % (paths, reason, LABEL))
    texts = []
    for row in kept:
        texts.extend([row["file"] or "", row["rule"], row["summary"]])
    clean = redact_all([one_line(text) for text in texts])
    for index, row in enumerate(kept):
        path, rule, summary = clean[3 * index:3 * index + 3]
        row["file"] = path if row["file"] is not None else None
        row["rule"] = rule
        row["summary"] = summary
    count = counts(kept)
    head = latest(docs)
    marker = "<!-- rust-sdlc-review:%s -->" % LABEL
    noun = "finding" if count["total"] == 1 else "findings"
    lines = [
        marker,
        "## %s findings" % TITLES[LABEL],
        "",
        "**%d %s** (%d open, %d fixed): %s." % (count["total"], noun, count["open"], count["fixed"], severity_text(count)),
        "",
        "Ledger iteration %d at `%s`." % (head["iteration"], head["head_sha"][:7]),
        "",
        "| Severity | ID | Location | Rule | Status | Summary |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in kept:
        lines.append("| %s | %s | %s | %s | %s | %s |" % (
            row["severity"], row["id"], cell(location(row)), cell(row["rule"]), row["status"], cell(row["summary"])))
    footer = "_Updated in place by rust-backend-sdlc on every review iteration."
    if dropped:
        footer += " %d dropped %s not shown." % (dropped, "finding is" if dropped == 1 else "findings are")
    lines += ["", footer + "_"]
    body = "\n".join(lines) + "\n"
    payload = {
        "lens": LABEL,
        "marker": marker,
        "iteration": str(head["iteration"]),
        "head_sha": head["head_sha"],
        "counts": dict(count, dropped=dropped),
        "findings": [{key: row[key] for key in KEYS} for row in kept],
        "body": body,
    }
    return body, payload


def human(seconds):
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return "%dh %02dm %02ds" % (hours, minutes, secs)
    if minutes:
        return "%dm %02ds" % (minutes, secs)
    return "%ds" % secs


def render_conclusion(docs):
    if not docs:
        paths = ", ".join(shown(path) for _origin, path in SOURCES)
        raise Degraded("no review ledger at %s; the conclusion comment is not posted" % paths)
    by_lens = {lens: [doc for doc in docs if doc["lens"] == lens] for lens in LENSES}
    starts = [doc["started_at"] for doc in docs if "started_at" in doc]
    ends = [doc["ended_at"] for doc in docs if "ended_at" in doc]
    started = STARTED_FLAG or (min(starts) if starts else "")
    ended = ENDED_FLAG or (max(ends) if ends else "")
    duration = None
    if DURATION_FLAG:
        duration = int(DURATION_FLAG)
    elif started and ended and utc(ended) >= utc(started):
        duration = int((utc(ended) - utc(started)).total_seconds())
    marker = "<!-- rust-sdlc-review:conclusion -->"
    lines = [
        marker,
        "## Review conclusion",
        "",
        "| Lens | Iteration | Critical | High | Medium | Low | Info | Open | Fixed | Dropped |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    totals = dict.fromkeys(("total", "open", "fixed", "dropped") + SEVERITIES, 0)
    lenses = {}
    for lens in LENSES:
        if not by_lens[lens]:
            lenses[lens] = None
            lines.append("| %s | no ledger | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |" % lens)
            continue
        kept, _total, dropped = kept_findings(by_lens[lens])
        count = dict(counts(kept), dropped=dropped)
        head = latest(by_lens[lens])
        lenses[lens] = {"iteration": str(head["iteration"]), "head_sha": head["head_sha"], "counts": count}
        for key in totals:
            totals[key] += count[key]
        lines.append("| %s | %d | %s | %d | %d | %d |" % (
            lens, head["iteration"], " | ".join(str(count[name]) for name in SEVERITIES),
            count["open"], count["fixed"], count["dropped"]))
    lines.append("| **all** | | %s | %d | %d | %d |" % (
        " | ".join(str(totals[name]) for name in SEVERITIES), totals["open"], totals["fixed"], totals["dropped"]))
    details = []
    if started:
        details.append("- Started: %s" % started)
    if ended:
        details.append("- Ended: %s" % ended)
    if duration is not None:
        details.append("- Duration: %s (%d s)" % (human(duration), duration))
    if ITERATIONS_FLAG:
        details.append("- Iterations: %s" % ITERATIONS_FLAG)
    if details:
        lines += [""] + details
    lines += ["", "_Posted once per pull request by rust-backend-sdlc; updated in place on a re-run._"]
    body = "\n".join(lines) + "\n"
    payload = {
        "lens": "conclusion",
        "marker": marker,
        "started_at": started or None,
        "ended_at": ended or None,
        "duration_seconds": None if duration is None else str(duration),
        "iterations": ITERATIONS_FLAG or None,
        "lenses": lenses,
        "totals": totals,
        "body": body,
    }
    return body, payload


def main():
    docs = []
    for origin, path in SOURCES:
        doc = load(origin, path)
        if doc is not None:
            docs.append(doc)
    if MODE == "lens":
        if not docs:
            raise Degraded("no %s ledger at %s; the %s comment is not posted"
                           % (LABEL, ", ".join(shown(path) for _origin, path in SOURCES), LABEL))
        body, payload = render_lens(docs)
    else:
        body, payload = render_conclusion(docs)
    with open(os.path.join(WORK, "body.md"), "w", encoding="utf-8") as handle:
        handle.write(body)
    with open(os.path.join(WORK, "payload.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, indent=2, ensure_ascii=True) + "\n")
    print("OK")


try:
    main()
except Malformed as exc:
    print("MALFORMED " + one_line(str(exc)))
except Degraded as exc:
    print("DEGRADED " + one_line(str(exc)))
'

# The comment listing (`gh api --paginate …/comments`: JSON arrays, or
# NDJSON objects) on stdin → the marker comments. argv: MARKER, LOGIN (empty
# when unresolved). Prints `IGNORED <login>` per comment whose body starts with
# MARKER and whose author is not LOGIN (case-insensitive), then
# `TARGET <id>` (the oldest, lowest-id marker comment of LOGIN) or
# `TARGET none`. Anything else than objects with a positive integer id, a
# string or null body and an object or null user exits 1.
PRF_PLAN_PY='
import json
import re
import sys

marker, login = sys.argv[1], sys.argv[2].lower()
text = sys.stdin.buffer.read().decode("utf-8", "replace").lstrip("\ufeff")
decoder = json.JSONDecoder()
items = []
index = 0
while True:
    while index < len(text) and text[index] in " \t\r\n":
        index += 1
    if index >= len(text):
        break
    try:
        value, index = decoder.raw_decode(text, index)
    except ValueError:
        sys.exit(1)
    if isinstance(value, list):
        items.extend(value)
    elif isinstance(value, dict):
        items.append(value)
    else:
        sys.exit(1)
own = []
ignored = []
for item in items:
    if not isinstance(item, dict):
        sys.exit(1)
    cid = item.get("id")
    if not isinstance(cid, int) or isinstance(cid, bool) or cid < 1:
        sys.exit(1)
    body = item.get("body")
    user = item.get("user")
    if body is None:
        body = ""
    if not isinstance(body, str) or not (user is None or isinstance(user, dict)):
        sys.exit(1)
    who = user.get("login") if isinstance(user, dict) else None
    who = who if isinstance(who, str) else ""
    if not body.startswith(marker):
        continue
    if login and who.lower() == login:
        own.append(cid)
    else:
        ignored.append(re.sub(r"[^A-Za-z0-9_.\[\]-]", "?", who)[:64] or "unknown")
for who in ignored:
    print("IGNORED " + who)
print("TARGET %s" % (min(own) if own else "none"))
'

# --- helpers ---------------------------------------------------------------------

# Every exit while PRF_INTENDED is 1 is deliberate (usage error, malformed
# --file ledger); any other non-zero exit is an unexpected failure that the
# EXIT trap turns into a degrade note and exit 0 (degrade-first).
PRF_INTENDED=1
PRF_WORK=""

# shellcheck disable=SC2329 # invoked by the EXIT trap below
prf_on_exit() {
  local rc=$?
  if [[ -n "$PRF_WORK" ]]; then
    rm -rf -- "$PRF_WORK"
  fi
  if ((rc != 0 && !PRF_INTENDED)); then
    printf 'DEGRADED: unexpected failure (exit %s); nothing further is posted\n' "$rc"
    exit 0
  fi
}
trap prf_on_exit EXIT

# prf_clean TEXT — TEXT without ASCII control characters.
prf_clean() {
  printf '%s' "${1-}" | LC_ALL=C tr -d '\000-\037\177'
}

# prf_degrade REASON... — one `DEGRADED: <reason>` line on stdout.
prf_degrade() {
  printf 'DEGRADED: %s\n' "$(prf_clean "$*")"
}

# prf_stop REASON... — prf_degrade, then exit 0 (main shell only).
prf_stop() {
  prf_degrade "$@"
  exit 0
}

# prf_once FLAG — die_usage when FLAG was already given.
PRF_SEEN=" "
prf_once() {
  if [[ "$PRF_SEEN" == *" $1 "* ]]; then
    die_usage "$1 given twice"
  fi
  PRF_SEEN+="$1 "
}

# prf_valid_pr N — N is a pull-request number (^[1-9][0-9]*$, ≤ PRF_PR_MAX).
prf_valid_pr() {
  [[ "${1-}" =~ ^[1-9][0-9]*$ ]] && ! num_gt "$1" "$PRF_PR_MAX"
}

# prf_valid_time ISO — ISO is a real UTC time written YYYY-MM-DDTHH:MM:SSZ.
prf_valid_time() {
  [[ "${1-}" =~ $PRF_ISO_RE ]] || return 1
  _sdlc_py -c '
import sys
from datetime import datetime
try:
    datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
except ValueError:
    sys.exit(1)
' "$1"
}

# --- arguments ------------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done

LENS=""
CONCLUSION=0
PR=""
FILES=()
DRY_RUN=0
JSON_OUT=0
BOT_LOGIN=""
STARTED_AT=""
ENDED_AT=""
DURATION=""
ITERATIONS=""
CONCLUSION_FLAGS=""

while (($#)); do
  case "$1" in
    --conclusion)
      prf_once "$1"
      CONCLUSION=1
      ;;
    --dry-run)
      prf_once "$1"
      DRY_RUN=1
      ;;
    --json)
      prf_once "$1"
      JSON_OUT=1
      ;;
    --file)
      need_value "$1" "${2-}"
      FILES+=("$2")
      shift
      ;;
    --pr | --bot-login | --started-at | --ended-at | --duration-seconds | --iterations)
      need_value "$1" "${2-}"
      prf_once "$1"
      case "$1" in
        --pr) PR="$2" ;;
        --bot-login) BOT_LOGIN="$2" ;;
        --started-at) STARTED_AT="$2" ;;
        --ended-at) ENDED_AT="$2" ;;
        --duration-seconds) DURATION="$2" ;;
        *) ITERATIONS="$2" ;;
      esac
      case "$1" in
        --pr | --bot-login) ;;
        *) CONCLUSION_FLAGS+=" $1" ;;
      esac
      shift
      ;;
    -*)
      die_usage "unknown argument: $(prf_clean "$1")"
      ;;
    *)
      if [[ -n "$LENS" ]]; then
        die_usage "unexpected argument: $(prf_clean "$1") (one lens at most)"
      fi
      LENS="$1"
      ;;
  esac
  shift
done

if ((CONCLUSION)); then
  if [[ -n "$LENS" ]]; then
    die_usage "--conclusion takes no lens, got: $(prf_clean "$LENS")"
  fi
else
  if [[ -z "$LENS" ]]; then
    die_usage "a lens (security, fr-nfr or code-review) or --conclusion is required"
  fi
  # Exact match: a substring test would accept "security fr-nfr" as one lens.
  case "$LENS" in
    security | fr-nfr | code-review) ;;
    *) die_usage "unknown lens: $(prf_clean "$LENS") (security, fr-nfr or code-review)" ;;
  esac
  if [[ -n "$CONCLUSION_FLAGS" ]]; then
    die_usage "only --conclusion takes$CONCLUSION_FLAGS"
  fi
fi
if ((DRY_RUN && JSON_OUT)); then
  die_usage "--dry-run and --json are mutually exclusive"
fi
if [[ -n "$PR" ]] && ! prf_valid_pr "$PR"; then
  die_usage "--pr must be a pull-request number (^[1-9][0-9]*$, at most $PRF_PR_MAX), got: $(prf_clean "$PR")"
fi
if [[ -n "$BOT_LOGIN" && ! "$BOT_LOGIN" =~ $PRF_LOGIN_RE ]]; then
  die_usage "--bot-login must be a GitHub login, got: $(prf_clean "$BOT_LOGIN")"
fi
if [[ -n "$STARTED_AT" ]] && ! prf_valid_time "$STARTED_AT"; then
  die_usage "--started-at must be a UTC time YYYY-MM-DDTHH:MM:SSZ, got: $(prf_clean "$STARTED_AT")"
fi
if [[ -n "$ENDED_AT" ]] && ! prf_valid_time "$ENDED_AT"; then
  die_usage "--ended-at must be a UTC time YYYY-MM-DDTHH:MM:SSZ, got: $(prf_clean "$ENDED_AT")"
fi
if [[ -n "$DURATION" ]] && ! is_uint "$DURATION"; then
  die_usage "--duration-seconds must be a number of seconds (digits), got: $(prf_clean "$DURATION")"
fi
if [[ -n "$ITERATIONS" ]] && ! is_uint "$ITERATIONS"; then
  die_usage "--iterations must be a number (digits), got: $(prf_clean "$ITERATIONS")"
fi
[[ -z "$DURATION" ]] || DURATION="$(strip_zeros "$DURATION")"
[[ -z "$ITERATIONS" ]] || ITERATIONS="$(strip_zeros "$ITERATIONS")"
PRF_INTENDED=0

LABEL="${LENS:-conclusion}"
MARKER="<!-- rust-sdlc-review:$LABEL -->"

# --- capability gate (D12): the first real action --------------------------------

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || TOP=""
[[ -n "$TOP" ]] || TOP="$(pwd -P)"
PROFILE="$(profile_path "$TOP")"
if [[ ! -f "$PROFILE" ]]; then
  prf_stop "no profile at $PROFILE, so capabilities.publish_pr_comments is not true; the $LABEL comment is not posted"
fi
if ! have_yq && ! have_pyyaml; then
  prf_stop "no YAML toolchain to read capabilities.publish_pr_comments from $PROFILE; the $LABEL comment is not posted"
fi
PUBLISH="$(profile_get "$PROFILE" capabilities.publish_pr_comments)" ||
  prf_stop "cannot read capabilities.publish_pr_comments from $PROFILE; the $LABEL comment is not posted"
case "$PUBLISH" in
  true) ;;
  false) prf_stop "capabilities.publish_pr_comments is false; the $LABEL comment is not posted" ;;
  *) prf_stop "capabilities.publish_pr_comments is not true in $PROFILE; the $LABEL comment is not posted" ;;
esac

# --- ledgers and rendering -----------------------------------------------------

LEDGER_DIR="${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}"
SOURCES=()
if ((${#FILES[@]})); then
  for file in "${FILES[@]}"; do
    SOURCES+=(file "$file")
  done
elif ((CONCLUSION)); then
  for lens in $PRF_LENSES; do
    SOURCES+=(default "${LEDGER_DIR%/}/$lens.json")
  done
else
  SOURCES+=(default "${LEDGER_DIR%/}/$LENS.json")
fi

PRF_WORK="$(mktemp -d "${TMPDIR:-/tmp}/post-review-findings.XXXXXX")" ||
  prf_stop "cannot create a temporary directory; the $LABEL comment is not posted"
MODE=lens
((!CONCLUSION)) || MODE=conclusion
VERDICT="$(_sdlc_py -c "$PRF_RENDER_PY" "$MODE" "$LABEL" "$PRF_WORK" "$BASH" "$SCRIPT_DIR/lib/common.sh" \
  "$STARTED_AT" "$ENDED_AT" "$DURATION" "$ITERATIONS" "${SOURCES[@]}")" || VERDICT=""
case "$VERDICT" in
  OK) ;;
  "MALFORMED "*)
    PRF_INTENDED=1
    die "${VERDICT#MALFORMED }"
    ;;
  "DEGRADED "*) prf_stop "${VERDICT#DEGRADED }" ;;
  *) prf_stop "cannot render the $LABEL comment from the ledgers; it is not posted" ;;
esac

if ((JSON_OUT)); then
  cat -- "$PRF_WORK/payload.json"
  exit 0
fi
if ((DRY_RUN)); then
  printf 'WOULD: post %s\n' "$LABEL"
  cat -- "$PRF_WORK/body.md"
  exit 0
fi

# --- pull request and authorization ------------------------------------------------

have_cmd gh || prf_stop "gh not found on PATH; the $LABEL comment is not posted"
SLUG="$(resolve_repo_slug "$TOP" 2>/dev/null)" ||
  prf_stop "cannot resolve the repository (no github.com origin and gh repo view failed); the $LABEL comment is not posted"
if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq .number 2>/dev/null)" || PR=""
  prf_valid_pr "$PR" ||
    prf_stop "no pull request for the current branch; the $LABEL comment is not posted"
fi
BASE="$(gh api "repos/$SLUG/pulls/$PR" --jq .base.repo.full_name 2>/dev/null)" ||
  prf_stop "malformed gh read: cannot read pull request #$PR of $SLUG; the $LABEL comment is not posted"
is_slug "$BASE" ||
  prf_stop "malformed gh read: the base repository of pull request #$PR is not owner/name; the $LABEL comment is not posted"
if [[ "$(lower "$BASE")" != "$(lower "$SLUG")" ]]; then
  prf_stop "base repository $BASE of pull request #$PR is not the origin repository $SLUG; the $LABEL comment is not posted"
fi

# --- posting identity and the marker comments (ADR-26) ---------------------------

LOGIN="$BOT_LOGIN"
if [[ -z "$LOGIN" ]]; then
  LOGIN="$(gh api user --jq .login 2>/dev/null)" || LOGIN=""
  [[ "$LOGIN" =~ $PRF_LOGIN_RE ]] || LOGIN=""
  if [[ -z "$LOGIN" ]]; then
    prf_degrade "posting identity unresolved (gh api user failed): a new $LABEL comment is created and none is edited"
  fi
fi
gh api --paginate "repos/$SLUG/issues/$PR/comments?per_page=100" >"$PRF_WORK/comments.json" 2>/dev/null ||
  prf_stop "malformed gh read: cannot list the comments of pull request #$PR; the $LABEL comment is not posted"
PLAN="$(_sdlc_py -c "$PRF_PLAN_PY" "$MARKER" "$LOGIN" <"$PRF_WORK/comments.json")" ||
  prf_stop "malformed gh read: the comment listing of pull request #$PR is not a list of comments; the $LABEL comment is not posted"
TARGET=none
while IFS= read -r line; do
  case "$line" in
    "IGNORED "*) prf_degrade "ignored $MARKER comment by ${line#IGNORED }" ;;
    "TARGET "*) TARGET="${line#TARGET }" ;;
    *) ;;
  esac
done <<<"$PLAN"
[[ "$TARGET" == none ]] || is_uint "$TARGET" ||
  prf_stop "malformed gh read: unexpected comment id; the $LABEL comment is not posted"

# --- body file (ADR-27) and the write ------------------------------------------------

cd "$TOP" || prf_stop "cannot enter $TOP; the $LABEL comment is not posted"
RAW="$PRF_TMP_DIR/review-$LABEL.raw.md"
OUT="$PRF_TMP_DIR/review-$LABEL.md"
if ! safe_write_target "$RAW" "$TOP" || ! atomic_write "$RAW" <"$PRF_WORK/body.md"; then
  prf_stop "cannot write $RAW; the $LABEL comment is not posted"
fi
redact --in "$RAW" --out "$OUT" >/dev/null ||
  prf_stop "cannot redact $RAW into $OUT; the $LABEL comment is not posted"

if [[ "$TARGET" != none ]]; then
  gh api -X PATCH "repos/$SLUG/issues/comments/$TARGET" -F "body=@$OUT" >/dev/null 2>&1 ||
    prf_stop "gh could not update comment $TARGET on pull request #$PR (write failure); the $LABEL comment is unchanged"
  printf 'POSTED: %s updated %s\n' "$LABEL" "$TARGET"
else
  URL="$(gh api -X POST "repos/$SLUG/issues/$PR/comments" -F "body=@$OUT" --jq .html_url 2>/dev/null)" ||
    prf_stop "gh could not create the $LABEL comment on pull request #$PR (write failure)"
  URL="$(prf_clean "$URL")"
  [[ "$URL" =~ ^https://[^[:space:]]+$ ]] || URL="(url not reported)"
  printf 'POSTED: %s created %s\n' "$LABEL" "$URL"
fi
exit 0
