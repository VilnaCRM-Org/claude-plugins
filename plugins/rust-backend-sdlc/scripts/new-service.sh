#!/usr/bin/env bash
# new-service.sh — create or import a service repository from the template and apply the deterministic customization steps (FR-12, FR-13).
#
# Usage: new-service.sh --name <n> [--description <text>] [--template <owner/repo> | --template-path <dir> | --in-place] [--owner <org>] [--visibility private|public] [--dest <dir>] [--version <x.y.z>] [--intro <text>] [--sync-flavour app|pat] [--keep-specs] [--phase source|customize|all] [--dry-run]
#   --name <n>               service name: kebab-case, at most 50 characters (required)
#   --description <text>     one line, at most 200 characters, no control characters (default: the name)
#   --template <owner/repo>  GitHub template; default RUST_SDLC_TEMPLATE_REPO, else template_repository of
#                            RUST_SDLC_CONFIG_FILE, else of the plugin's config/new-service.defaults.json
#   --template-path <dir>    import a local template checkout (refused with uncommitted tracked changes)
#   --in-place               customize the git checkout in the working directory
#   --owner <org>            GitHub owner (default in GitHub mode: the login of `gh api user --jq .login`)
#   --visibility <v>         private or public (default: default_visibility of the configuration)
#   --dest <dir>             parent directory of the checkout <dest>/<name> (default: .)
#   --version <x.y.z>        first release version (default: default_version of the configuration)
#   --intro <text>           README introduction: one line, at most 200 characters (default: the description)
#   --sync-flavour <f>       template-sync flavour to keep: app or pat (omitted: SKIP and NEXT)
#   --keep-specs             keep the planning bundles the source tree shipped under specs/
#   --phase <p>              source, customize or all (default: all)
#   --dry-run                print WOULD: lines and the summary only; no mutating gh call, no write
#   --help                   print this help
#
# Modes: GitHub (--template, no source flag, or --in-place with a github.com origin and
# `gh auth status` OK) and local (--template-path, or --in-place otherwise).
# Phase source prints SOURCE_MODE:, REPO: (GitHub mode), CHECKOUT:, SOURCE:, SOURCE_SHA:
# (clone-and-push also IMPORT_PENDING:) and writes target/rust-sdlc/new-service/source.json in
# the checkout once. Phase customize runs the steps identity, version, bmalph-config, readme,
# changelog, specs, sync-flavour, templatesyncignore and docs-check-citations in this order,
# each printing DONE:, UNCHANGED:, SKIP: or NEXT:. A run that passes validation ends with
# SUMMARY: done=<n> unchanged=<n> skip=<n> next=<n>. The script never commits or pushes,
# never removes the example context and never changes the licence.
#
# Exit: 0 success; 1 failure or refusal; 2 usage error or malformed configuration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

RECORD_REL=target/rust-sdlc/new-service/source.json
OWNER_RE='^[A-Za-z0-9][A-Za-z0-9-]{0,38}$'

NAME=""
DESCRIPTION=""
TEMPLATE_FLAG=""
TEMPLATE_PATH=""
IN_PLACE=0
SOURCE_FLAGS=0
OWNER=""
VISIBILITY=""
DEST=.
VERSION=""
INTRO=""
FLAVOUR=""
KEEP_SPECS=0
PHASE=all
DRY_RUN=0

N_DONE=0
N_UNCHANGED=0
N_SKIP=0
N_NEXT=0
NS_ARMED=0
NS_WORK=""

# Facts resolved before the phases run.
SLUG=""
KIND=""
MODE=""
CHECKOUT=""
REPO=""
POLL_ATTEMPTS=""
POLL_INTERVAL=""

# The source record (R_*) and the sync-flavour outcome shared by the steps.
R_MODE=""
R_SOURCE=""
R_SHA=""
R_IDENTITY=""
R_SPECS=()
SYNC_STATE=""
SYNC_DELETED=()

# --- python helpers (JSON, TOML and Markdown edits) -----------------------------------
# One program, one subcommand per call. A malformed input prints `<key>: <reason>`
# (or a one-line reason) on stdout and exits 3; data goes to stdout on success.
NS_PY="$(
  cat <<'PY'
import json
import os
import re
import sys

SLUG = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
SHA40 = re.compile(r"[0-9a-f]{40}\Z")
BUNDLE = re.compile(r"specs/[A-Za-z0-9][A-Za-z0-9._-]*\Z")
CONTROL = re.compile(r"[\x00-\x1f\x7f]")
TABLE = re.compile(r"(\[\[?)([^\[\]]+)\]\]?[ \t]*(#.*)?\Z")
HEADING = re.compile(r"#{1,6}([ \t]|\Z)")
CONFIG_KEYS = ("template_repository", "default_visibility", "default_version",
               "poll_attempts", "poll_interval_seconds")
RECORD_KEYS = ("schema_version", "mode", "source", "sha", "identity_slug", "specs")
MODES = ("template", "clone-and-push", "path", "in-place")


class Bad(Exception):
    """A malformed input; the message is printed and the exit status is 3."""


def unique(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise Bad(f"{key}: duplicate key")
        out[key] = value
    return out


def read_text(path):
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as handle:
        return handle.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as handle:
        handle.write(text)


def load_object(path):
    try:
        with open(path, encoding="utf-8") as handle:
            doc = json.load(handle, object_pairs_hook=unique)
    except OSError as exc:
        raise Bad(f"(file): {exc.strerror or exc}") from exc
    except ValueError as exc:
        raise Bad("(document): " + (str(exc).splitlines() or ["invalid JSON"])[0]) from exc
    if not isinstance(doc, dict):
        raise Bad("(document): not a JSON object")
    return doc


def exact_keys(doc, keys):
    for key in doc:
        if key not in keys:
            raise Bad(f"{key}: unknown key")
    for key in keys:
        if key not in doc:
            raise Bad(f"{key}: missing")


def int_in(doc, key, low, high):
    value = doc[key]
    if isinstance(value, bool) or not isinstance(value, int):
        raise Bad(f"{key}: not an integer")
    if not low <= value <= high:
        raise Bad(f"{key}: {value} is outside {low}-{high}")
    return value


def text_of(doc, key, pattern=None):
    value = doc[key]
    if not isinstance(value, str) or not value or CONTROL.search(value):
        raise Bad(f"{key}: not a one-line string")
    if pattern is not None and not pattern.match(value):
        raise Bad(f"{key}: invalid value")
    return value


def config(path):
    doc = load_object(path)
    exact_keys(doc, CONFIG_KEYS)
    slug = doc["template_repository"]
    if not isinstance(slug, str) or not SLUG.match(slug):
        raise Bad("template_repository: not an owner/name slug")
    visibility = doc["default_visibility"]
    if not isinstance(visibility, str) or visibility not in ("private", "public"):
        raise Bad("default_visibility: not one of private public")
    version = doc["default_version"]
    if not isinstance(version, str) or not SEMVER.match(version):
        raise Bad("default_version: not a MAJOR.MINOR.PATCH version")
    attempts = int_in(doc, "poll_attempts", 1, 60)
    interval = int_in(doc, "poll_interval_seconds", 0, 60)
    print("\n".join([slug, visibility, version, str(attempts), str(interval)]))


def record_read(path):
    doc = load_object(path)
    exact_keys(doc, RECORD_KEYS)
    version = doc["schema_version"]
    if isinstance(version, bool) or version != 1:
        raise Bad("schema_version: not 1")
    mode = text_of(doc, "mode")
    if mode not in MODES:
        raise Bad("mode: not one of " + " ".join(MODES))
    source = text_of(doc, "source")
    sha = text_of(doc, "sha", SHA40)
    identity = text_of(doc, "identity_slug", SLUG)
    specs = doc["specs"]
    if not isinstance(specs, list) or not all(isinstance(s, str) and BUNDLE.match(s) for s in specs):
        raise Bad("specs: not a list of specs/<directory> names")
    print("\n".join([mode, source, sha, identity, *specs]))


def record_json(mode, source, sha, identity, *specs):
    doc = {"schema_version": 1, "mode": mode, "source": source, "sha": sha,
           "identity_slug": identity, "specs": list(specs)}
    sys.stdout.write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")


def toml_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def identity(src, out, description, repository):
    import tomllib

    text = read_text(src)
    tomllib.loads(text)
    lines = text.split("\n")
    start, end = None, len(lines)
    for index, line in enumerate(lines):
        match = TABLE.match(line)
        if not match:
            continue
        if start is not None:
            end = index
            break
        name = re.sub(r"\s*\.\s*", ".", match.group(2).strip())
        if match.group(1) == "[" and name == "workspace.package":
            start = index
    if start is None:
        raise Bad("Cargo.toml has no [workspace.package] table")
    wanted = {"description": description}
    if repository:
        wanted["repository"] = repository
    done = set()
    last = start
    for index in range(start + 1, end):
        line = lines[index]
        if line.strip() and not line.lstrip().startswith("#"):
            last = index
        match = re.match(r"([ \t]*)(description|repository)[ \t]*=", line)
        if match and match.group(2) in wanted and match.group(2) not in done:
            key = match.group(2)
            lines[index] = f"{match.group(1)}{key} = {toml_string(wanted[key])}"
            done.add(key)
    missing = [f"{key} = {toml_string(value)}" for key, value in wanted.items() if key not in done]
    lines[last + 1:last + 1] = missing
    new = "\n".join(lines)
    package = tomllib.loads(new).get("workspace", {}).get("package", {})
    if any(package.get(key) != value for key, value in wanted.items()):
        raise Bad("the edited [workspace.package] does not read back")
    write_text(out, new)


def bmalph(src, out, name, description):
    doc = load_object(src)
    doc["name"] = name
    doc["description"] = description
    write_text(out, json.dumps(doc, indent=2, ensure_ascii=False) + "\n")


class Fence:
    """Fenced-block tracking (``` or ~~~, three or more), as docs-check reads it."""

    def __init__(self):
        self.open, self.char, self.size = False, "", 0

    def step(self, line):
        text = line.lstrip(" \t")
        if text[:1] in ("`", "~"):
            char = text[0]
            run = len(text) - len(text.lstrip(char))
            if run >= 3:
                if not self.open:
                    self.open, self.char, self.size = True, char, run
                    return True
                if char == self.char and run >= self.size and not text[run:].strip():
                    self.open = False
                    return True
        return self.open


def readme(src, out, description, old, new, intro):
    text = read_text(src)
    lines = text.split("\n")
    trailing = len(lines) > 1 and lines[-1] == ""
    if trailing:
        lines.pop()
    fence, h1 = Fence(), None
    for index, line in enumerate(lines):
        if fence.step(line):
            continue
        if line.startswith("# ") or line == "#":
            h1 = index
            break
    title = "# " + description
    if h1 is None:
        lines[0:0] = [title, ""]
        h1 = 0
    else:
        lines[h1] = title
    if new and old.lower() != new.lower():
        pattern = re.compile(r"(?<![A-Za-z0-9_.-])" + re.escape(old) + r"(?![A-Za-z0-9_-])",
                             re.IGNORECASE)
        lines = [pattern.sub(lambda _m: new, line) if line.startswith("[![") else line
                 for line in lines]
    start, size = h1 + 1, len(lines)
    while start < size and (not lines[start].strip() or lines[start].startswith("[![")):
        start += 1
    if start < size and not HEADING.match(lines[start]):
        end = start
        while end < size and lines[end].strip() and not HEADING.match(lines[end]):
            end += 1
        lines[start:end] = [intro]
    else:
        block = [intro, ""] if start < size else [intro]
        if lines[start - 1].strip():
            block.insert(0, "")
        lines[start:start] = block
    write_text(out, "\n".join(lines) + ("\n" if trailing else ""))


def run_length(line, index):
    end = index
    while end < len(line) and line[end] == "`":
        end += 1
    return end - index


def rewrite_spans(line, patterns):
    """Rewrite deleted paths inside the inline code spans of LINE."""
    out, index, size, count = [], 0, len(line), 0
    while index < size:
        if line[index] != "`":
            out.append(line[index])
            index += 1
            continue
        run = run_length(line, index)
        cursor, close = index + run, -1
        while cursor < size:
            if line[cursor] != "`":
                cursor += 1
                continue
            other = run_length(line, cursor)
            if other == run:
                close = cursor
                break
            cursor += other
        if close < 0:
            out.append(line[index:index + run])
            index += run
            continue
        content = line[index + run:close]
        rewritten = content
        for pattern, bare in patterns:
            rewritten = pattern.sub(lambda _m, b=bare: b, rewritten)
        if rewritten != content:
            count += 1
        out.append(line[index:index + run] + rewritten + line[close:close + run])
        index = close + run
    return "".join(out), count


def citations(out_dir, root, *rest):
    split = rest.index("--")
    deleted, files = rest[:split], rest[split + 1:]
    patterns = [
        (re.compile(r"(?<![A-Za-z0-9_./-])(?:\./)?" + re.escape(path) + r"(?![A-Za-z0-9_/-])"),
         os.path.basename(path))
        for path in deleted
    ]
    for number, rel in enumerate(files):
        lines = read_text(os.path.join(root, rel)).split("\n")
        fence, changed = Fence(), False
        for index, line in enumerate(lines):
            if fence.step(line):
                continue
            rewritten, count = rewrite_spans(line, patterns)
            if count:
                lines[index] = rewritten
                changed = True
                for _ in range(count):
                    print(f"CITE\t{rel}\t{index + 1}")
        if changed:
            target = os.path.join(out_dir, str(number))
            write_text(target, "\n".join(lines))
            print(f"FILE\t{rel}\t{target}")


def main(argv):
    sys.stdout.reconfigure(errors="surrogateescape")
    handlers = {
        "config": config,
        "record-read": record_read,
        "record-json": record_json,
        "identity": identity,
        "bmalph": bmalph,
        "readme": readme,
        "citations": citations,
    }
    try:
        handlers[argv[0]](*argv[1:])
    except Bad as exc:
        print(exc)
        return 3
    except (OSError, ValueError) as exc:
        print((str(exc).splitlines() or [type(exc).__name__])[0])
        return 3
    return 0


sys.exit(main(sys.argv[1:]))
PY
)"

ns_py() {
  python3 -I -c "$NS_PY" "$@"
}

# --- output ----------------------------------------------------------------------------

# ns_clean TEXT — TEXT without control characters (messages and printed lines).
ns_clean() {
  local text="${1-}"
  printf '%s' "${text//[[:cntrl:]]/}"
}

# ns_emit KIND TEXT — one DONE/UNCHANGED/SKIP/NEXT line, counted for the summary.
# Under --dry-run a DONE line prints as `WOULD: TEXT` and the others are only counted.
ns_emit() {
  local kind="$1" text="${2//[[:cntrl:]]/}"
  case "$kind" in
    DONE) N_DONE=$((N_DONE + 1)) ;;
    UNCHANGED) N_UNCHANGED=$((N_UNCHANGED + 1)) ;;
    SKIP) N_SKIP=$((N_SKIP + 1)) ;;
    NEXT) N_NEXT=$((N_NEXT + 1)) ;;
    *) die "ns_emit: unknown kind $kind" ;;
  esac
  if [[ "$DRY_RUN" == 1 ]]; then
    if [[ "$kind" == DONE ]]; then
      printf 'WOULD: %s\n' "$text"
    fi
    return 0
  fi
  printf '%s: %s\n' "$kind" "$text"
}

# ns_handle KEY VALUE — a source handle (not printed under --dry-run).
ns_handle() {
  if [[ "$DRY_RUN" != 1 ]]; then
    printf '%s: %s\n' "$1" "${2//[[:cntrl:]]/}"
  fi
}

# ns_refuse TEXT — `REFUSED: TEXT` on stdout, then exit 1.
ns_refuse() {
  local text="$*"
  printf 'REFUSED: %s\n' "${text//[[:cntrl:]]/}"
  exit 1
}

# ns_step_fail STEP TEXT — a failing customize step: log and exit 1.
ns_step_fail() {
  log_error "step $1 failed: $2"
  exit 1
}

# ns_on_exit — the EXIT trap: remove the work directory, then print the summary.
# shellcheck disable=SC2329 # invoked by the EXIT trap
ns_on_exit() {
  if [[ -n "$NS_WORK" ]]; then
    rm -rf -- "$NS_WORK"
  fi
  if [[ "$NS_ARMED" == 1 ]]; then
    printf 'SUMMARY: done=%s unchanged=%s skip=%s next=%s\n' \
      "$N_DONE" "$N_UNCHANGED" "$N_SKIP" "$N_NEXT"
  fi
}

# --- validation ------------------------------------------------------------------------

# ns_check_text FLAG VALUE — one line, no control characters, at most 200 characters.
ns_check_text() {
  local flag="$1" value="$2" count chars
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    die_usage "$flag must be a single line"
  fi
  if [[ "$value" =~ [[:cntrl:]] ]]; then
    die_usage "$flag must not contain control characters"
  fi
  count="${#value}"
  if num_gt "$count" 200; then
    # ${#value} counts bytes in a C locale; count characters before refusing.
    chars="$(python3 -I -c 'import sys; print(len(sys.argv[1]))' "$value")" || chars="$count"
    count="$chars"
    if num_gt "$count" 200; then
      die_usage "$flag must be at most 200 characters (got $count)"
    fi
  fi
}

# ns_read_config PATH — validate the defaults file and set the CFG_* values (exit 2 when malformed).
ns_read_config() {
  local path="$1" out rc=0
  out="$(ns_py config "$path")" || rc=$?
  if ((rc != 0)); then
    log_error "malformed $path: $(ns_clean "${out:-unreadable}")"
    exit 2
  fi
  {
    read -r CFG_SLUG
    read -r CFG_VISIBILITY
    read -r CFG_VERSION
    read -r CFG_ATTEMPTS
    read -r CFG_INTERVAL
  } <<<"$out"
}

# --- repository helpers ----------------------------------------------------------------

# ns_url_slug URL — owner/name of a github.com URL (https, git@ or ssh form); else return 1.
ns_url_slug() {
  local url="${1-}" slug=""
  case "$url" in
    https://github.com/*) slug="${url#https://github.com/}" ;;
    http://github.com/*) slug="${url#http://github.com/}" ;;
    git@github.com:*) slug="${url#git@github.com:}" ;;
    ssh://git@github.com/*) slug="${url#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
  slug="${slug%/}"
  slug="${slug%.git}"
  is_slug "$slug" || return 1
  printf '%s\n' "$slug"
}

# ns_origin_slug DIR — owner/name of DIR's github.com origin; else return 1.
ns_origin_slug() {
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  ns_url_slug "$url"
}

# ns_identity_of CARGO_TOML — owner/name of [workspace.package].repository; else return 1.
ns_identity_of() {
  local url
  [[ -f "$1" ]] || return 1
  url="$(toml_get "$1" workspace.package.repository 2>/dev/null)" || return 1
  ns_url_slug "$url"
}

# ns_template_repository DIR — the TEMPLATE_REPOSITORY of DIR's sync workflows (app, then
# pat), else the resolved template slug.
ns_template_repository() {
  local dir="$1" flavour file line value
  for flavour in app pat; do
    file="$dir/.github/workflows/template-sync-$flavour.yml"
    [[ -f "$file" ]] || continue
    line="$(grep -m 1 -E '^[[:space:]]*TEMPLATE_REPOSITORY:' "$file")" || continue
    value="${line#*TEMPLATE_REPOSITORY:}"
    value="${value%%#*}"
    value="$(printf '%s' "$value" | tr -d "[:space:]\"'")"
    if is_slug "$value"; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  printf '%s\n' "$SLUG"
}

# ns_nonempty PATH — PATH exists and is not an empty directory.
ns_nonempty() {
  [[ -e "$1" || -L "$1" ]] || return 1
  [[ -d "$1" && ! -L "$1" ]] || return 0
  [[ -n "$(ls -A "$1")" ]]
}

# ns_is_clone_of DIR SLUG — DIR is a git checkout whose origin names SLUG.
ns_is_clone_of() {
  local found
  [[ -e "$1/.git" ]] || return 1
  found="$(ns_origin_slug "$1")" || return 1
  [[ "$(lower "$found")" == "$(lower "$2")" ]]
}

# ns_write REL SRC — install the file SRC as CHECKOUT/REL (safe and atomic); a read-only
# target is refused, so it stays untouched.
ns_write() {
  local rel="$1" src="$2" path="$CHECKOUT/$1"
  safe_write_target "$path" "$CHECKOUT" || return 1
  if [[ -e "$path" && ! -w "$path" ]]; then
    log_error "refusing to write $rel: it is not writable"
    return 1
  fi
  atomic_write "$path" <"$src"
}

# ns_writable REL — the checks of ns_write without writing.
ns_writable() {
  local path="$CHECKOUT/$1"
  safe_write_target "$path" "$CHECKOUT" || return 1
  if [[ -e "$path" && ! -w "$path" ]]; then
    log_error "refusing to write $1: it is not writable"
    return 1
  fi
}

# --- source record -----------------------------------------------------------------------

# ns_record_set MODE SOURCE SHA IDENTITY [SPEC...] — the in-memory record.
ns_record_set() {
  R_MODE="$1"
  R_SOURCE="$2"
  R_SHA="$3"
  R_IDENTITY="$4"
  shift 4
  R_SPECS=("$@")
}

# ns_record_save — write the in-memory record once (an existing record is kept).
ns_record_save() {
  local out="$NS_WORK/source.json"
  if [[ -e "$CHECKOUT/$RECORD_REL" || -L "$CHECKOUT/$RECORD_REL" ]]; then
    log_info "keeping the existing source record $RECORD_REL"
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    log_info "would write the source record $RECORD_REL"
    return 0
  fi
  ns_py record-json "$R_MODE" "$R_SOURCE" "$R_SHA" "$R_IDENTITY" "${R_SPECS[@]}" >"$out" ||
    die "cannot build the source record"
  ns_write "$RECORD_REL" "$out" || die "cannot write the source record $RECORD_REL"
}

# ns_record_load — read CHECKOUT's record into R_* (exit 1 when malformed).
ns_record_load() {
  local path="$CHECKOUT/$RECORD_REL" out rc=0 lines=()
  if [[ -L "$path" || ! -f "$path" ]]; then
    die "the source record $path is not a regular file"
  fi
  out="$(ns_py record-read "$path")" || rc=$?
  if ((rc != 0)); then
    die "malformed $path: $(ns_clean "$out")"
  fi
  mapfile -t lines <<<"$out"
  ns_record_set "${lines[@]}"
}

# ns_record_from_tree MODE SOURCE SHA — the record of a freshly materialized checkout:
# identity from its Cargo.toml (before any edit), bundles = the directories under specs/.
ns_record_from_tree() {
  local identity name specs=()
  identity="$(ns_identity_of "$CHECKOUT/Cargo.toml")" || identity="$(ns_template_repository "$CHECKOUT")"
  if [[ -d "$CHECKOUT/specs" && ! -L "$CHECKOUT/specs" ]]; then
    while IFS= read -r -d '' name; do
      name="${name##*/}"
      if [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        specs+=("specs/$name")
      else
        log_warn "ignoring the bundle directory specs/$(ns_clean "$name"): unsupported name"
      fi
    done < <(find "$CHECKOUT/specs" -mindepth 1 -maxdepth 1 -type d -print0 | LC_ALL=C sort -z)
  fi
  ns_record_set "$1" "$2" "$3" "$identity" "${specs[@]}"
}

# ns_root_commit — the root commit of CHECKOUT's HEAD (the last one when there are several).
ns_root_commit() {
  local roots
  roots="$(git -C "$CHECKOUT" rev-list --max-parents=0 HEAD 2>/dev/null)" || return 1
  [[ -n "$roots" ]] || return 1
  printf '%s\n' "${roots##*$'\n'}"
}

# ns_record_from_history MODE SOURCE — the record rebuilt from CHECKOUT's root commit: sha =
# the root commit, identity from its Cargo.toml, bundles = its specs/ directories unchanged since.
ns_record_from_history() {
  local root identity="" dir specs=()
  root="$(ns_root_commit)" || die "cannot build the source record: $CHECKOUT has no commit"
  if git -C "$CHECKOUT" show "$root:Cargo.toml" >"$NS_WORK/root-Cargo.toml" 2>/dev/null; then
    identity="$(ns_identity_of "$NS_WORK/root-Cargo.toml")" || identity=""
  fi
  if [[ -z "$identity" ]]; then
    identity="$(ns_template_repository "$CHECKOUT")"
  fi
  while IFS= read -r dir; do
    [[ "$dir" =~ ^specs/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
    if git -C "$CHECKOUT" diff --quiet "$root" HEAD -- "$dir"; then
      specs+=("$dir")
    fi
  done < <(git -C "$CHECKOUT" ls-tree -d --name-only "$root" -- specs/)
  ns_record_set "$1" "$2" "$root" "$identity" "${specs[@]}"
}

# ns_handles — the source handles of the in-memory record.
ns_handles() {
  ns_handle SOURCE_MODE "$R_MODE"
  if [[ "$MODE" == github && -n "$REPO" ]]; then
    ns_handle REPO "$REPO"
  fi
  ns_handle CHECKOUT "$CHECKOUT"
  ns_handle SOURCE "$R_SOURCE"
  ns_handle SOURCE_SHA "$R_SHA"
}

# --- phase source --------------------------------------------------------------------------

# ns_import DIR — the archive import of DIR's HEAD into a new CHECKOUT, then `git init`.
ns_import() {
  local src="$1"
  mkdir -p -- "$CHECKOUT" || die "cannot create $CHECKOUT"
  git -C "$src" archive HEAD | tar -x -C "$CHECKOUT" || die "cannot import $src into $CHECKOUT"
  git -C "$CHECKOUT" init -b main >&2 || die "git init failed in $CHECKOUT"
}

# ns_poll_commits — wait until REPO has a commit (poll_attempts × poll_interval_seconds).
ns_poll_commits() {
  local attempt length
  for ((attempt = 1; attempt <= POLL_ATTEMPTS; attempt++)); do
    length="$(gh api "repos/$REPO/commits?per_page=1" --jq length 2>/dev/null)" || length=""
    if is_uint "$length" && num_gt "$length" 0; then
      return 0
    fi
    if ((attempt < POLL_ATTEMPTS)); then
      sleep "$POLL_INTERVAL"
    fi
  done
  die "repository $REPO has no commit after $POLL_ATTEMPTS attempts ${POLL_INTERVAL}s apart"
}

ns_flow_template() {
  local action="source template (gh repo create $REPO --template $SLUG --$VISIBILITY; gh repo clone $REPO $CHECKOUT)"
  local sha
  if [[ "$DRY_RUN" == 1 ]]; then
    ns_emit DONE "$action"
    return 0
  fi
  gh repo create "$REPO" --template "$SLUG" "--$VISIBILITY" >&2 || die "gh repo create $REPO failed"
  ns_poll_commits
  gh repo clone "$REPO" "$CHECKOUT" >&2 || die "gh repo clone $REPO failed"
  sha="$(git -C "$CHECKOUT" rev-parse HEAD)" || die "the clone $CHECKOUT has no commit"
  ns_record_from_tree template "$SLUG" "$sha"
  ns_record_save
  ns_emit DONE "$action"
  ns_handles
}

ns_flow_clone_and_push() {
  local action="source clone-and-push (gh repo create $REPO --$VISIBILITY; import $SLUG into $CHECKOUT)"
  local tmp="$NS_WORK/template" sha
  if [[ "$DRY_RUN" == 1 ]]; then
    ns_emit DONE "$action"
    return 0
  fi
  gh repo create "$REPO" "--$VISIBILITY" >&2 || die "gh repo create $REPO failed"
  mkdir -p -- "$tmp"
  gh repo clone "$SLUG" "$tmp" -- --depth 1 >&2 || die "gh repo clone $SLUG failed"
  sha="$(git -C "$tmp" rev-parse HEAD)" || die "the clone of $SLUG has no commit"
  ns_import "$tmp"
  git -C "$CHECKOUT" remote add origin "https://github.com/$REPO.git" ||
    die "cannot set origin in $CHECKOUT"
  ns_record_from_tree clone-and-push "$SLUG" "$sha"
  ns_record_save
  ns_emit DONE "$action"
  ns_handles
  printf 'IMPORT_PENDING: %s@%s\n' "$SLUG" "$sha"
  ns_emit NEXT "ask the template owner to enable Settings > Template repository"
}

# ns_source_existing MODE SOURCE — SKIP an existing checkout and print its handles.
ns_source_existing() {
  ns_emit SKIP "source (exists)"
  if [[ -f "$CHECKOUT/$RECORD_REL" ]]; then
    ns_record_load
  else
    ns_record_from_history "$1" "$2"
    ns_record_save
  fi
  ns_handles
}

ns_source_github() {
  local is_template found mode=template
  is_template="$(gh api "repos/$SLUG" --jq .is_template)" ||
    die "cannot read the template repository $SLUG through gh api"
  case "$is_template" in
    true) ;;
    false) mode=clone-and-push ;;
    *) die "gh api repos/$SLUG printed is_template=$(ns_clean "$is_template"); expected true or false" ;;
  esac
  if found="$(gh repo view "$REPO" --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" &&
    [[ -n "$found" ]]; then
    if ns_is_clone_of "$CHECKOUT" "$REPO"; then
      ns_source_existing "$mode" "$SLUG"
      return 0
    fi
    ns_refuse "repository $REPO already exists and $CHECKOUT is not a clone of it"
  fi
  if ns_nonempty "$CHECKOUT"; then
    ns_refuse "checkout $CHECKOUT exists and is not empty"
  fi
  if [[ "$mode" == template ]]; then
    ns_flow_template
  else
    ns_flow_clone_and_push
  fi
}

ns_source_path() {
  local dir sha dirty
  dir="$(cd "$TEMPLATE_PATH" && pwd)" || die "cannot read $TEMPLATE_PATH"
  if ns_nonempty "$CHECKOUT"; then
    if [[ -f "$CHECKOUT/$RECORD_REL" ]]; then
      ns_record_load
      if [[ "$R_SOURCE" == "local:$dir" ]]; then
        ns_emit SKIP "source (exists)"
        ns_handles
        return 0
      fi
    fi
    ns_refuse "checkout $CHECKOUT exists and is not empty"
  fi
  sha="$(git -C "$dir" rev-parse --verify -q HEAD)" || die "template checkout $dir has no commit"
  dirty="$(git -C "$dir" status --porcelain --untracked-files=no)" ||
    die "git status failed in $dir"
  if [[ -n "$dirty" ]]; then
    ns_refuse "template checkout $dir has uncommitted tracked changes"
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    ns_emit DONE "source path (import $dir into $CHECKOUT)"
    return 0
  fi
  ns_import "$dir"
  ns_record_from_tree path "local:$dir" "$sha"
  ns_record_save
  ns_emit DONE "source path (import $dir into $CHECKOUT)"
  ns_handles
}

ns_source_in_place() {
  local root
  ns_emit SKIP "source (in place)"
  if [[ "$(basename "$CHECKOUT")" != "$NAME" ]]; then
    ns_emit NEXT "rename the checkout directory to $NAME (it is the Compose project name)"
  fi
  if [[ -f "$CHECKOUT/$RECORD_REL" ]]; then
    ns_record_load
  else
    root="$(ns_root_commit)" || die "$CHECKOUT has no commit"
    ns_record_set in-place "$(ns_template_repository "$CHECKOUT")" "$root" ""
  fi
  ns_handles
}

# ns_in_place_guard — the two in-place refusals (tracked changes; already customized).
ns_in_place_guard() {
  local dirty current template
  dirty="$(git -C "$CHECKOUT" status --porcelain --untracked-files=no)" ||
    die "git status failed in $CHECKOUT"
  if [[ -n "$dirty" ]]; then
    ns_refuse "in-place target has uncommitted tracked changes"
  fi
  if [[ -f "$CHECKOUT/$RECORD_REL" ]]; then
    return 0
  fi
  [[ -f "$CHECKOUT/Cargo.toml" ]] || die "$CHECKOUT has no Cargo.toml"
  template="$(ns_template_repository "$CHECKOUT")"
  current="$(ns_identity_of "$CHECKOUT/Cargo.toml")" || current=""
  if [[ -z "$current" || "$(lower "$current")" != "$(lower "$template")" ]]; then
    ns_refuse "in-place target already customized"
  fi
}

ns_phase_source() {
  case "$KIND" in
    github) ns_source_github ;;
    path) ns_source_path ;;
    in-place) ns_source_in_place ;;
    *) die "unknown source kind $KIND" ;;
  esac
}

# --- phase customize ---------------------------------------------------------------------------

# ns_apply STEP REL NEW [DETAIL] — UNCHANGED when NEW equals CHECKOUT/REL, else write it
# (a failure leaves the file untouched and exits 1) and print DONE.
ns_apply() {
  local step="$1" rel="$2" new="$3" detail="${4-}"
  if [[ -f "$CHECKOUT/$rel" ]] && cmp -s -- "$new" "$CHECKOUT/$rel"; then
    ns_emit UNCHANGED "$step $rel"
    return 0
  fi
  if [[ "$DRY_RUN" != 1 ]]; then
    ns_write "$rel" "$new" || ns_step_fail "$step" "$rel left untouched"
  fi
  ns_emit DONE "$step $rel${detail:+ ($detail)}"
}

step_identity() {
  local repository="" detail="description, repository" out rc=0
  [[ -f "$CHECKOUT/Cargo.toml" ]] || ns_step_fail identity "Cargo.toml is missing"
  if [[ -n "$OWNER" ]]; then
    repository="https://github.com/$OWNER/$NAME"
  else
    detail="description"
  fi
  out="$(ns_py identity "$CHECKOUT/Cargo.toml" "$NS_WORK/Cargo.toml" "$DESCRIPTION" "$repository")" || rc=$?
  if ((rc != 0)); then
    ns_step_fail identity "Cargo.toml: $(ns_clean "$out")"
  fi
  ns_apply identity Cargo.toml "$NS_WORK/Cargo.toml" "$detail"
  if [[ -z "$repository" ]]; then
    ns_emit NEXT "set [workspace.package].repository once the GitHub repository exists"
  fi
}

step_version() {
  local current
  current="$(toml_get "$CHECKOUT/Cargo.toml" workspace.package.version)" ||
    ns_step_fail version "cannot read [workspace.package].version"
  if [[ "$current" == "$VERSION" ]]; then
    ns_emit UNCHANGED "version $VERSION"
  else
    ns_emit NEXT "scripts/set-version.sh $VERSION"
  fi
}

step_bmalph_config() {
  local rel=bmalph/config.json out rc=0
  if [[ ! -f "$CHECKOUT/$rel" ]]; then
    ns_emit SKIP "bmalph-config (no $rel)"
    return 0
  fi
  out="$(ns_py bmalph "$CHECKOUT/$rel" "$NS_WORK/bmalph-config.json" "$NAME" "$DESCRIPTION")" || rc=$?
  if ((rc != 0)); then
    ns_step_fail bmalph-config "malformed $rel: $(ns_clean "$out")"
  fi
  ns_apply bmalph-config "$rel" "$NS_WORK/bmalph-config.json"
}

step_readme() {
  local new_slug="" out rc=0
  if [[ ! -f "$CHECKOUT/README.md" ]]; then
    ns_emit SKIP "readme (no README.md)"
    return 0
  fi
  if [[ -n "$OWNER" ]]; then
    new_slug="$OWNER/$NAME"
  fi
  out="$(ns_py readme "$CHECKOUT/README.md" "$NS_WORK/README.md" "$DESCRIPTION" "$R_IDENTITY" \
    "$new_slug" "$INTRO")" || rc=$?
  if ((rc != 0)); then
    ns_step_fail readme "README.md: $(ns_clean "$out")"
  fi
  ns_apply readme README.md "$NS_WORK/README.md"
  if [[ -z "$new_slug" ]]; then
    ns_emit NEXT "point the README badges at the GitHub repository once it exists"
  fi
}

step_changelog() {
  printf '%s\n' \
    '# Changelog' \
    'All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.' \
    '' \
    '- - -' \
    '' \
    'Changelog generated by [cocogitto](https://github.com/cocogitto/cocogitto).' \
    >"$NS_WORK/CHANGELOG.md"
  ns_apply changelog CHANGELOG.md "$NS_WORK/CHANGELOG.md"
}

# ns_listed DIR — DIR is one of the record's bundle directories.
ns_listed() {
  local spec
  for spec in "${R_SPECS[@]}"; do
    if [[ "$spec" == "$1" ]]; then
      return 0
    fi
  done
  return 1
}

step_specs() {
  local spec dir changed=0
  if [[ "$KEEP_SPECS" == 1 ]]; then
    ns_emit SKIP "specs (--keep-specs)"
    return 0
  fi
  for spec in "${R_SPECS[@]}"; do
    [[ -e "$CHECKOUT/$spec" || -L "$CHECKOUT/$spec" ]] || continue
    if [[ -L "$CHECKOUT/specs" || -L "$CHECKOUT/$spec" || ! -d "$CHECKOUT/$spec" ]]; then
      ns_step_fail specs "$spec is not a plain directory; left untouched"
    fi
    if [[ "$DRY_RUN" != 1 ]]; then
      rm -rf -- "${CHECKOUT:?}/$spec" || ns_step_fail specs "cannot remove $spec"
    fi
    ns_emit DONE "specs removed $spec"
    changed=1
  done
  if [[ "$R_MODE" == in-place ]]; then
    while IFS= read -r dir; do
      [[ "$dir" =~ ^specs/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
      if ! ns_listed "$dir" && [[ -d "$CHECKOUT/$dir" ]]; then
        log_info "$dir changed since the import; it is kept"
        ns_emit SKIP "specs (modified since import)"
        changed=1
      fi
    done < <(git -C "$CHECKOUT" ls-tree -d --name-only "$R_SHA" -- specs/ 2>/dev/null)
  fi
  if [[ "$changed" == 0 ]]; then
    ns_emit UNCHANGED "specs"
  fi
}

step_sync_flavour() {
  local other upper other_upper keep path deleted=0
  if [[ -z "$FLAVOUR" ]]; then
    SYNC_STATE=undecided
    ns_emit SKIP "sync flavour (undecided)"
    ns_emit NEXT "re-run with --sync-flavour app|pat"
    return 0
  fi
  if [[ "$FLAVOUR" == app ]]; then other=pat; else other=app; fi
  upper="$(printf '%s' "$FLAVOUR" | tr '[:lower:]' '[:upper:]')"
  other_upper="$(printf '%s' "$other" | tr '[:lower:]' '[:upper:]')"
  keep=".github/workflows/template-sync-$FLAVOUR.yml"
  SYNC_DELETED=(".github/workflows/template-sync-$other.yml" ".github/TEMPLATE_SYNC_$other_upper.md")
  if [[ ! -f "$CHECKOUT/$keep" ]]; then
    if [[ ! -e "$CHECKOUT/${SYNC_DELETED[0]}" ]]; then
      SYNC_STATE=none
      SYNC_DELETED=()
      ns_emit SKIP "sync flavour (no template-sync workflows)"
      return 0
    fi
    ns_step_fail sync-flavour "$keep is missing; the $other flavour is kept"
  fi
  SYNC_STATE=decided
  log_info "keeping $keep and .github/TEMPLATE_SYNC_$upper.md"
  for path in "${SYNC_DELETED[@]}"; do
    [[ -e "$CHECKOUT/$path" || -L "$CHECKOUT/$path" ]] || continue
    ns_writable "$path" || ns_step_fail sync-flavour "$path left untouched"
    if [[ "$DRY_RUN" != 1 ]]; then
      rm -f -- "${CHECKOUT:?}/$path" || ns_step_fail sync-flavour "cannot delete $path"
    fi
    ns_emit DONE "sync flavour $FLAVOUR deleted $path"
    deleted=1
  done
  if [[ "$deleted" == 0 ]]; then
    ns_emit UNCHANGED "sync flavour $FLAVOUR"
  fi
}

# ns_ignore_plan PATH... — build NS_WORK/templatesyncignore = .templatesyncignore plus every
# PATH not yet listed; prints the added paths, one per line.
ns_ignore_plan() {
  local file="$CHECKOUT/.templatesyncignore" new="$NS_WORK/templatesyncignore" path
  if [[ -f "$file" ]]; then
    cat -- "$file" >"$new"
  else
    : >"$new"
  fi
  if [[ -s "$new" && -n "$(tail -c 1 -- "$new")" ]]; then
    printf '\n' >>"$new"
  fi
  for path in "$@"; do
    if ! grep -qxF -- "$path" "$new"; then
      printf '%s\n' "$path" >>"$new"
      printf '%s\n' "$path"
    fi
  done
}

step_templatesyncignore() {
  local added path
  case "$SYNC_STATE" in
    undecided)
      ns_emit SKIP "templatesyncignore (sync flavour undecided)"
      return 0
      ;;
    none)
      ns_emit SKIP "templatesyncignore (no template-sync workflows)"
      return 0
      ;;
    *) ;;
  esac
  added="$(ns_ignore_plan "${SYNC_DELETED[@]}")"
  if [[ -z "$added" ]]; then
    ns_emit UNCHANGED "templatesyncignore .templatesyncignore"
    return 0
  fi
  if [[ "$DRY_RUN" != 1 ]]; then
    ns_write .templatesyncignore "$NS_WORK/templatesyncignore" ||
      ns_step_fail templatesyncignore ".templatesyncignore left untouched"
  fi
  while IFS= read -r path; do
    ns_emit DONE "templatesyncignore $path"
  done <<<"$added"
}

# ns_markdown_set — the Markdown files docs-check reads (tracked, plus untracked ones that
# are not ignored, so a fresh import is covered), minus CHANGELOG.md, specs/** and the
# deleted flavour pair (still present under --dry-run).
ns_markdown_set() {
  local rel deleted
  while IFS= read -r -d '' rel; do
    case "$rel" in
      CHANGELOG.md | specs/*) continue ;;
      *[[:cntrl:]]*) continue ;;
      *) ;;
    esac
    for deleted in "${SYNC_DELETED[@]}"; do
      if [[ "$rel" == "$deleted" ]]; then
        continue 2
      fi
    done
    if [[ -f "$CHECKOUT/$rel" && ! -L "$CHECKOUT/$rel" ]]; then
      printf '%s\n' "$rel"
    fi
  done < <(git -C "$CHECKOUT" ls-files -z --cached --others --exclude-standard -- '*.md' | LC_ALL=C sort -zu)
}

step_docs_check_citations() {
  local files=() out rc=0 kind rel value cites=() edited=() targets=() index added
  case "$SYNC_STATE" in
    undecided)
      ns_emit SKIP "docs-check citations (sync flavour undecided)"
      return 0
      ;;
    none)
      ns_emit SKIP "docs-check citations (no template-sync workflows)"
      return 0
      ;;
    *) ;;
  esac
  mapfile -t files < <(ns_markdown_set)
  mkdir -p -- "$NS_WORK/citations"
  out="$(ns_py citations "$NS_WORK/citations" "$CHECKOUT" "${SYNC_DELETED[@]}" -- "${files[@]}")" || rc=$?
  if ((rc != 0)); then
    ns_step_fail docs-check-citations "$(ns_clean "$out")"
  fi
  while IFS=$'\t' read -r kind rel value; do
    case "$kind" in
      CITE) cites+=("$rel:$value") ;;
      FILE)
        edited+=("$rel")
        targets+=("$value")
        ;;
      *) ;;
    esac
  done <<<"$out"
  if ((${#cites[@]} == 0)); then
    ns_emit UNCHANGED "docs-check citations"
    return 0
  fi
  added="$(ns_ignore_plan "${edited[@]}")"
  if [[ "$DRY_RUN" != 1 ]]; then
    for rel in "${edited[@]}"; do
      ns_writable "$rel" || ns_step_fail docs-check-citations "$rel left untouched"
    done
    if [[ -n "$added" ]]; then
      ns_writable .templatesyncignore ||
        ns_step_fail docs-check-citations ".templatesyncignore left untouched"
    fi
    for index in "${!edited[@]}"; do
      ns_write "${edited[$index]}" "${targets[$index]}" ||
        ns_step_fail docs-check-citations "cannot write ${edited[$index]}"
    done
    if [[ -n "$added" ]]; then
      ns_write .templatesyncignore "$NS_WORK/templatesyncignore" ||
        ns_step_fail docs-check-citations "cannot write .templatesyncignore"
      log_info "listed in .templatesyncignore: ${added//$'\n'/ }"
    fi
  fi
  for value in "${cites[@]}"; do
    ns_emit DONE "docs-check citation $value"
  done
}

ns_phase_customize() {
  if [[ ! -d "$CHECKOUT" ]]; then
    if [[ "$DRY_RUN" == 1 ]]; then
      ns_emit DONE "customize $CHECKOUT (identity, version, bmalph-config, readme, changelog, specs, sync-flavour, templatesyncignore, docs-check-citations)"
      return 0
    fi
    die "checkout $CHECKOUT does not exist: run --phase source first"
  fi
  if [[ -f "$CHECKOUT/$RECORD_REL" || -L "$CHECKOUT/$RECORD_REL" ]]; then
    ns_record_load
  elif [[ "$IN_PLACE" == 1 ]]; then
    ns_record_from_history in-place "$(ns_template_repository "$CHECKOUT")"
    ns_record_save
  else
    ns_refuse "no source record $RECORD_REL in $CHECKOUT: run --phase source first"
  fi
  step_identity
  step_version
  step_bmalph_config
  step_readme
  step_changelog
  step_specs
  step_sync_flavour
  step_templatesyncignore
  step_docs_check_citations
}

# --- arguments -------------------------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done

while (($#)); do
  case "$1" in
    --name | --description | --template | --template-path | --owner | --visibility | \
      --dest | --version | --intro | --sync-flavour | --phase)
      need_value "$1" "${2-}"
      case "$1" in
        --name) NAME="$2" ;;
        --description) DESCRIPTION="$2" ;;
        --template)
          TEMPLATE_FLAG="$2"
          SOURCE_FLAGS=$((SOURCE_FLAGS + 1))
          ;;
        --template-path)
          TEMPLATE_PATH="$2"
          SOURCE_FLAGS=$((SOURCE_FLAGS + 1))
          ;;
        --owner) OWNER="$2" ;;
        --visibility) VISIBILITY="$2" ;;
        --dest) DEST="$2" ;;
        --version) VERSION="$2" ;;
        --intro) INTRO="$2" ;;
        --sync-flavour) FLAVOUR="$2" ;;
        --phase) PHASE="$2" ;;
      esac
      shift 2
      ;;
    --in-place)
      IN_PLACE=1
      SOURCE_FLAGS=$((SOURCE_FLAGS + 1))
      shift
      ;;
    --keep-specs)
      KEEP_SPECS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *) die_usage "unknown argument: $(ns_clean "$1")" ;;
  esac
done

[[ -n "$NAME" ]] || die_usage "--name is required"
is_kebab "$NAME" 50 || die_usage "--name must be kebab-case and at most 50 characters: $(ns_clean "$NAME")"
if ((SOURCE_FLAGS > 1)); then
  die_usage "--template, --template-path and --in-place are mutually exclusive"
fi
if [[ -n "$DESCRIPTION" ]]; then
  ns_check_text --description "$DESCRIPTION"
fi
if [[ -n "$INTRO" ]]; then
  ns_check_text --intro "$INTRO"
fi
if [[ -n "$OWNER" && ! "$OWNER" =~ $OWNER_RE ]]; then
  die_usage "--owner is not a GitHub owner name: $(ns_clean "$OWNER")"
fi
if [[ -n "$VERSION" ]] && ! is_semver "$VERSION"; then
  die_usage "--version must be MAJOR.MINOR.PATCH: $(ns_clean "$VERSION")"
fi
case "$VISIBILITY" in
  '' | private | public) ;;
  *) die_usage "--visibility must be private or public: $(ns_clean "$VISIBILITY")" ;;
esac
case "$FLAVOUR" in
  '' | app | pat) ;;
  *) die_usage "--sync-flavour must be app or pat: $(ns_clean "$FLAVOUR")" ;;
esac
case "$PHASE" in
  source | customize | all) ;;
  *) die_usage "--phase must be source, customize or all: $(ns_clean "$PHASE")" ;;
esac
if [[ -n "$TEMPLATE_FLAG" ]] && ! is_slug "$TEMPLATE_FLAG"; then
  die_usage "--template must be owner/repo: $(ns_clean "$TEMPLATE_FLAG")"
fi
if [[ -n "$TEMPLATE_PATH" && ! -d "$TEMPLATE_PATH" ]]; then
  die_usage "--template-path is not a directory: $(ns_clean "$TEMPLATE_PATH")"
fi
if [[ "$IN_PLACE" != 1 && ! -d "$DEST" ]]; then
  die_usage "--dest is not a directory: $(ns_clean "$DEST")"
fi

# --- configuration and template slug (ADR-12) ---------------------------------------------------

CONFIG_PATH="${RUST_SDLC_CONFIG_FILE:-}"
if [[ -z "$CONFIG_PATH" ]]; then
  CONFIG_PATH="$(resolve_plugin_root)/config/new-service.defaults.json"
fi
CFG_SLUG=""
CFG_VISIBILITY=""
CFG_VERSION=""
CFG_ATTEMPTS=""
CFG_INTERVAL=""
ns_read_config "$CONFIG_PATH"

if [[ -n "$TEMPLATE_FLAG" ]]; then
  SLUG="$TEMPLATE_FLAG"
elif [[ -n "${RUST_SDLC_TEMPLATE_REPO:-}" ]]; then
  if ! is_slug "$RUST_SDLC_TEMPLATE_REPO"; then
    log_error "malformed RUST_SDLC_TEMPLATE_REPO: not an owner/name slug: $(ns_clean "$RUST_SDLC_TEMPLATE_REPO")"
    exit 2
  fi
  SLUG="$RUST_SDLC_TEMPLATE_REPO"
else
  SLUG="$CFG_SLUG"
fi
POLL_ATTEMPTS="$(strip_zeros "$CFG_ATTEMPTS")"
POLL_INTERVAL="$(strip_zeros "$CFG_INTERVAL")"

NS_WORK="$(mktemp -d "${TMPDIR:-/tmp}/rust-sdlc-new-service.XXXXXX")" ||
  die "cannot create a temporary directory"
trap ns_on_exit EXIT
NS_ARMED=1

# --- mode, owner, defaults and checkout -----------------------------------------------------------

if [[ "$IN_PLACE" == 1 ]]; then
  KIND='in-place'
  top="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    die "--in-place needs a git checkout in the working directory"
  if [[ "$(cd "$top" && pwd -P)" != "$(pwd -P)" ]]; then
    die "--in-place must run at the top level of the checkout ($top)"
  fi
  CHECKOUT="$(pwd)"
  MODE=local
  if ns_origin_slug "$CHECKOUT" >/dev/null && gh auth status >/dev/null 2>&1; then
    MODE=github
  fi
elif [[ -n "$TEMPLATE_PATH" ]]; then
  KIND=path
  MODE=local
  CHECKOUT="$(cd "$DEST" && pwd)/$NAME"
else
  KIND=github
  MODE=github
  CHECKOUT="$(cd "$DEST" && pwd)/$NAME"
fi

if [[ -z "$OWNER" && "$MODE" == github ]]; then
  OWNER="$(gh api user --jq .login 2>/dev/null)" || OWNER=""
  OWNER="$(ns_clean "$OWNER")"
  [[ -n "$OWNER" ]] || die "gh api user printed no login: pass --owner"
  [[ "$OWNER" =~ $OWNER_RE ]] || die "gh api user printed an invalid login: pass --owner"
fi
if [[ -n "$OWNER" ]]; then
  REPO="$OWNER/$NAME"
fi
DESCRIPTION="${DESCRIPTION:-$NAME}"
INTRO="${INTRO:-$DESCRIPTION}"
VERSION="${VERSION:-$CFG_VERSION}"
VISIBILITY="${VISIBILITY:-$CFG_VISIBILITY}"

if [[ "$KIND" == in-place ]]; then
  ns_in_place_guard
fi

case "$PHASE" in
  source) ns_phase_source ;;
  customize) ns_phase_customize ;;
  all)
    ns_phase_source
    ns_phase_customize
    ;;
esac
exit 0
