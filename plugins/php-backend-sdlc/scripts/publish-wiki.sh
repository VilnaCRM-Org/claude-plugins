#!/usr/bin/env bash
# publish-wiki.sh — mirror the in-repo wiki source to the GitHub wiki remote.
#
# The canonical wiki source lives in the repository at
#   plugins/php-backend-sdlc/wiki/*.md
# and is published to the project's GitHub wiki, which is itself a separate
# git repository at <owner>/<repo>.wiki.git — derived automatically from this
# checkout's `origin` remote (override with the WIKI_REMOTE env var).
#
# ONE-TIME SEED REQUIREMENT
#   GitHub does NOT create the wiki repo until the wiki has at least one
#   page. A brand-new project's wiki remote does not exist yet, so the very
#   first `git clone` of `<repo>.wiki.git` fails with a "Repository not
#   found" / "could not read" error. There is no API or git way to bootstrap
#   it; you MUST create the first page once, by hand, through the GitHub UI:
#       Repo → Wiki tab → "Create the first page" → Save.
#   The page content is irrelevant — this script overwrites everything on the
#   next run. After that single manual seed, the wiki remote exists and this
#   script can clone, mirror, and push to it forever after.
#
# WHAT IT DOES
#   1. Clones the wiki remote into a temp dir (removed on exit via trap).
#   2. Copies every plugins/php-backend-sdlc/wiki/*.md into the clone.
#   3. `git add -A`, commits (skipped when nothing changed), and pushes.
#
# USAGE
#   plugins/php-backend-sdlc/scripts/publish-wiki.sh [--dry-run]
#
#   --dry-run   Clone read-only, show exactly what would be copied and
#               whether a push would happen, and make NO network writes
#               (no commit, no push).
#
# ENVIRONMENT
#   WIKI_REMOTE   Override the wiki git remote URL (default: derived from the
#                 `origin` remote as https://github.com/<owner>/<repo>.wiki.git).
#
# Authentication for the push uses your existing git credentials (HTTPS
# token helper or an SSH-rewritten URL via WIKI_REMOTE).
set -euo pipefail

# --- configuration ----------------------------------------------------------
# Source dir is resolved relative to this script, so the script works from any
# cwd: <script_dir>/../wiki holds the canonical *.md pages.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI_SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/wiki"

# Derive the wiki remote from this checkout's origin remote so the script is
# repo-agnostic: <owner>/<repo>.git -> https://github.com/<owner>/<repo>.wiki.git
# (override by exporting WIKI_REMOTE).
derive_wiki_remote() {
  local url path
  url="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)" \
    || die "no 'origin' remote found; set WIKI_REMOTE explicitly"
  case "$url" in
    git@github.com:*)       path="${url#git@github.com:}" ;;
    ssh://git@github.com/*) path="${url#ssh://git@github.com/}" ;;
    https://github.com/*)   path="${url#https://github.com/}" ;;
    *) die "unsupported origin URL '$url'; set WIKI_REMOTE explicitly" ;;
  esac
  printf 'https://github.com/%s.wiki.git\n' "${path%.git}"
}

# --- logging ----------------------------------------------------------------
log_info()  { printf '[php-sdlc][INFO] %s\n' "$*"; }
log_warn()  { printf '[php-sdlc][WARN] %s\n' "$*" >&2; }
log_error() { printf '[php-sdlc][ERROR] %s\n' "$*" >&2; }
die() { log_error "$*"; exit 1; }

# --- argument parsing -------------------------------------------------------
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      # Print the leading comment block (the usage docs) and exit cleanly.
      sed -n '2,/^set -euo pipefail$/{/^set -euo pipefail$/d;s/^# \{0,1\}//;p;}' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) die "unknown argument: $1 (usage: publish-wiki.sh [--dry-run])" ;;
  esac
done

# --- temp dir + cleanup trap ------------------------------------------------
# Created up front so the trap can always remove it, even on early failure.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/php-sdlc-wiki.XXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- preflight --------------------------------------------------------------
command -v git >/dev/null 2>&1 || die "git not found on PATH"
[[ -d "$WIKI_SRC_DIR" ]] || die "wiki source dir not found: $WIKI_SRC_DIR"

# Resolve the wiki remote (env override wins; otherwise derive from origin).
WIKI_REMOTE="${WIKI_REMOTE:-$(derive_wiki_remote)}"

# Collect the source pages up front so an empty source is caught before any
# network work. Nullglob keeps the glob from matching a literal '*.md' when
# the directory has no markdown files.
shopt -s nullglob
src_pages=("$WIKI_SRC_DIR"/*.md)
shopt -u nullglob
[[ "${#src_pages[@]}" -gt 0 ]] \
  || die "no *.md files to publish in $WIKI_SRC_DIR"

log_info "wiki remote:  $WIKI_REMOTE"
log_info "wiki source:  $WIKI_SRC_DIR (${#src_pages[@]} page(s))"

# --- clone the wiki remote --------------------------------------------------
CLONE_DIR="$TMP_DIR/wiki"
log_info "cloning wiki remote into temp dir..."
if ! git clone --depth 1 "$WIKI_REMOTE" "$CLONE_DIR" 2>"$TMP_DIR/clone.err"; then
  log_error "failed to clone wiki remote: $WIKI_REMOTE"
  if [[ -s "$TMP_DIR/clone.err" ]]; then
    while IFS= read -r line; do log_error "  git: $line"; done <"$TMP_DIR/clone.err"
  fi
  log_error "The GitHub wiki repository does not exist yet."
  log_error "GitHub only creates it after the wiki has its first page, and"
  log_error "there is no API to bootstrap it. Seed it ONCE by hand:"
  log_error "  Repo -> Wiki tab -> \"Create the first page\" -> Save."
  log_error "The page content does not matter; this script overwrites it on"
  log_error "the next run. After that one-time seed, re-run this script."
  die "wiki remote not initialized; manual one-time seed required (see above)"
fi

# --- copy source pages into the clone ---------------------------------------
# Mirror semantics: pages removed from the source are also removed from the
# wiki. Delete the clone's existing *.md (tracked by `git add -A` below as
# deletions), then copy the current source set in.
log_info "mirroring source pages into the clone..."
shopt -s nullglob
existing_pages=("$CLONE_DIR"/*.md)
shopt -u nullglob

if (( DRY_RUN )); then
  for f in "${existing_pages[@]+"${existing_pages[@]}"}"; do
    log_info "  would remove (if not re-copied): $(basename "$f")"
  done
  for f in "${src_pages[@]}"; do
    log_info "  would copy: $(basename "$f")"
  done
else
  for f in "${existing_pages[@]+"${existing_pages[@]}"}"; do
    rm -f "$f"
  done
  for f in "${src_pages[@]}"; do
    cp -f "$f" "$CLONE_DIR/"
  done
  # GitHub wiki resolves page links by slug WITHOUT a .md suffix; a
  # [Title](Page.md) link 404s / falls through to repo content on the wiki.
  # Strip .md from sibling wiki-page links in the PUBLISHED copies only — the
  # in-repo source keeps .md so it browses correctly in the PR file view. The
  # pattern matches bare slugs only (no slash/scheme), so absolute repo blob
  # URLs like .../profile-schema.md are left untouched.
  link_re='s/\]\(([A-Za-z0-9_-]+)\.md(#[^)]*)?\)/](\1\2)/g'
  if command -v perl >/dev/null 2>&1; then
    for f in "$CLONE_DIR"/*.md; do perl -i -pe "$link_re" "$f"; done
    log_info "normalized sibling wiki links (stripped .md) for wiki resolution"
  elif sed --version >/dev/null 2>&1; then
    for f in "$CLONE_DIR"/*.md; do sed -E -i "$link_re" "$f"; done
    log_info "normalized sibling wiki links (stripped .md) for wiki resolution"
  else
    log_warn "neither perl nor GNU sed found; wiki page links keep .md and may not resolve"
  fi
fi

# --- stage, commit, push ----------------------------------------------------
commit_msg="docs(wiki): sync from plugins/php-backend-sdlc/wiki ($(date -u +%Y-%m-%dT%H:%M:%SZ))"

if (( DRY_RUN )); then
  log_info "[dry-run] no files copied, no commit, no push performed"
  log_info "[dry-run] would commit with message: $commit_msg"
  log_info "[dry-run] would push to: $WIKI_REMOTE"
  exit 0
fi

git -C "$CLONE_DIR" add -A

# `git diff --cached --quiet` exits non-zero when there is something staged.
if git -C "$CLONE_DIR" diff --cached --quiet; then
  log_info "no changes to publish — wiki already up to date"
  exit 0
fi

log_info "committing changes..."
# Use a per-clone identity so the script works in environments (CI) without a
# global git user configured. This never touches the user's global config.
git -C "$CLONE_DIR" \
  -c user.name="php-backend-sdlc wiki bot" \
  -c user.email="wiki-bot@users.noreply.github.com" \
  commit -m "$commit_msg" >/dev/null

log_info "pushing to wiki remote..."
git -C "$CLONE_DIR" push origin HEAD
log_info "wiki published successfully"
