# shellcheck shell=bash
# helpers.bash — shared helpers of the rust-backend-sdlc bats suites.
#
# Every suite loads this file with `load lib/helpers` and calls `common_setup`
# from its `setup`. The file defines functions only: nothing runs when it is
# loaded, so it can also be sourced outside bats. Suite-local helpers stay in
# their suite; this file is single-writer.
#
#   common_setup                    PLUGIN_ROOT, stub PATH, stub logs, no Docker
#   rr_materialize DEST [SLUG]      materialize tests/fixtures/rust-repo/ at DEST
#   sandbox_path TOOL...            a PATH directory holding only the named tools
#   k7_require TOOL                 skip a template-linter case when TOOL is absent
#   bundle_write DIR [--blocked]    write the seven planning-bundle files into DIR
#   mutate_profile FILE KEY VALUE   set one key of the block-style golden profile
#   drop_profile_key FILE KEY       remove one key of the block-style golden profile
#   docs_rules [--root DIR] FILE... run tests/lib/docs-rules.py over FILE...
#   skip_if_root                    skip a permission case under uid 0

# _rr_plugin_root — the plugin root, derived from this file's location
# (tests/lib/helpers.bash), so it is right in and outside bats.
_rr_plugin_root() {
  (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
}

# common_setup — call first in every suite's setup.
# Sets PLUGIN_ROOT, puts tests/fixtures/bin first on PATH, points the call log
# of every stub (STUB_<NAME>_LOG) into $BATS_TEST_TMPDIR/stub-logs/ (created
# empty), exports STUB_DOCKER_INFO_EXIT=1 so Docker is unreachable unless a
# case says otherwise, and unsets CLAUDE_PLUGIN_ROOT so no script under test
# resolves the installed plugin by accident.
common_setup() {
  local tmp="${BATS_TEST_TMPDIR:?common_setup needs BATS_TEST_TMPDIR}"
  local name lower var
  PLUGIN_ROOT="$(_rr_plugin_root)" || return 1
  PATH="$PLUGIN_ROOT/tests/fixtures/bin:$PATH"
  export PATH
  mkdir -p "$tmp/stub-logs" || return 1
  for name in CLAUDE GH BMALPH CURL CARGO MAKE DOCKER; do
    lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    export "STUB_${name}_LOG=$tmp/stub-logs/$lower.log"
    : >"$tmp/stub-logs/$lower.log" || return 1
  done
  # Any other STUB_*_LOG inherited from the caller's environment is moved
  # under the test directory too, so no stub ever writes outside it.
  for var in $(compgen -e); do
    case "$var" in
      STUB_CLAUDE_LOG | STUB_GH_LOG | STUB_BMALPH_LOG | STUB_CURL_LOG) ;;
      STUB_CARGO_LOG | STUB_MAKE_LOG | STUB_DOCKER_LOG) ;;
      STUB_*_LOG)
        lower="$(printf '%s' "$var" | tr '[:upper:]' '[:lower:]')"
        export "$var=$tmp/stub-logs/${lower#stub_}"
        ;;
      *) ;;
    esac
  done
  export STUB_DOCKER_INFO_EXIT=1
  unset CLAUDE_PLUGIN_ROOT
}

# rr_materialize DEST [ORIGIN_SLUG]
# Copies tests/fixtures/rust-repo/ to DEST and turns it into the repository the
# fixture stands for: every *.tpl file loses its suffix, `gitignore` becomes
# `.gitignore`, `dot-claude/` becomes `.claude/` and `dot-bmalph/` becomes
# `bmalph/`; then `git init -q -b main`, one commit authored and committed by
# `acme <ci@example.invalid>` (fixed dates, so the commit is reproducible) and
# `origin` set to https://github.com/${ORIGIN_SLUG:-acme/billing-service}.git.
# Suites use DEST=$BATS_TEST_TMPDIR/billing-service, the directory name the
# golden profile assumes. The identity is also written to DEST's local git
# config, so later commits a case makes need no global identity.
rr_materialize() {
  local dest="${1:?usage: rr_materialize DEST [ORIGIN_SLUG]}"
  local slug="${2:-acme/billing-service}"
  local root src file
  root="${PLUGIN_ROOT:-$(_rr_plugin_root)}"
  src="$root/tests/fixtures/rust-repo"
  if [[ ! -d "$src" ]]; then
    printf 'rr_materialize: fixture directory %s is missing\n' "$src" >&2
    return 1
  fi
  mkdir -p "$dest" || return 1
  cp -R "$src/." "$dest/" || return 1
  while IFS= read -r -d '' file; do
    mv "$file" "${file%.tpl}" || return 1
  done < <(find "$dest" -type f -name '*.tpl' -print0)
  while IFS= read -r -d '' file; do
    mv "$file" "$(dirname "$file")/.gitignore" || return 1
  done < <(find "$dest" -type f -name gitignore -print0)
  if [[ -d "$dest/dot-claude" ]]; then
    mv "$dest/dot-claude" "$dest/.claude" || return 1
  fi
  if [[ -d "$dest/dot-bmalph" ]]; then
    mv "$dest/dot-bmalph" "$dest/bmalph" || return 1
  fi
  git -C "$dest" init -q -b main || return 1
  git -C "$dest" config user.name acme || return 1
  git -C "$dest" config user.email ci@example.invalid || return 1
  git -C "$dest" config commit.gpgsign false || return 1
  git -C "$dest" add -A || return 1
  GIT_AUTHOR_NAME=acme GIT_AUTHOR_EMAIL=ci@example.invalid \
    GIT_COMMITTER_NAME=acme GIT_COMMITTER_EMAIL=ci@example.invalid \
    GIT_AUTHOR_DATE='2026-11-10T00:00:00Z' GIT_COMMITTER_DATE='2026-11-10T00:00:00Z' \
    git -C "$dest" commit -q -m 'chore: materialize the rust-repo fixture' || return 1
  git -C "$dest" remote add origin "https://github.com/${slug}.git" || return 1
}

# sandbox_path TOOL...
# Prints a fresh directory under $BATS_TEST_TMPDIR that holds a symbolic link
# for each named tool and nothing else; use it as the whole PATH to make every
# other tool genuinely absent. Each tool resolves through the current PATH, so
# a stub of tests/fixtures/bin wins over the host tool after common_setup.
# Fails when a named tool cannot be found (name it only when the case needs it).
sandbox_path() {
  local dir tool src
  dir="$(mktemp -d "${BATS_TEST_TMPDIR:?sandbox_path needs BATS_TEST_TMPDIR}/sandbox-path.XXXXXX")" || return 1
  for tool in "$@"; do
    case "$tool" in
      '' | */*)
        printf 'sandbox_path: %s is not a tool name\n' "${tool:-<empty>}" >&2
        return 1
        ;;
      *) ;;
    esac
    if ! src="$(type -P "$tool")"; then
      printf 'sandbox_path: %s is not on PATH\n' "$tool" >&2
      return 1
    fi
    ln -s "$src" "$dir/$tool" || return 1
  done
  printf '%s\n' "$dir"
}

# k7_require TOOL — a K7 (template linter) case runs only where TOOL is on
# PATH; locally it is skipped with the reason, in CI the bats job installs it.
k7_require() {
  local tool="${1:?usage: k7_require TOOL}"
  if ! type -P "$tool" >/dev/null 2>&1; then
    skip "$tool not installed (runs in CI)"
  fi
}

# skip_if_root — permission-denied cases cannot fail for uid 0.
skip_if_root() {
  if [[ "$(id -u)" == 0 ]]; then
    skip "running as root (uid 0): file permissions are not enforced"
  fi
}

# bundle_write DIR [--blocked]
# Writes the seven planning-bundle files of /rs-sdlc-plan into DIR (created):
# research.md, product-brief.md, prd.md, architecture.md, epics.md,
# implementation-readiness.md and run-summary.md. The issue number is the
# leading number of DIR's base name (specs/12-add-x → 12), else 1.
# architecture.md ends with `## Constraints` (parts (a) and (b), well under
# 4,500 characters), so text appended to the file lands in that section.
# epics.md uses the format bmalph's story-parsing.js reads without a warning.
# The readiness verdict is `ready`; with --blocked the readiness text
# contains NO-GO.
bundle_write() {
  local dir="${1:?usage: bundle_write DIR [--blocked]}"
  local blocked=0 base n
  case "${2-}" in
    '') ;;
    --blocked) blocked=1 ;;
    *)
      printf 'bundle_write: unknown option %s\n' "$2" >&2
      return 2
      ;;
  esac
  base="$(basename "$dir")"
  n="${base%%-*}"
  [[ "$n" =~ ^[0-9]+$ ]] || n=1
  mkdir -p "$dir" || return 1
  _bundle_research "$base" >"$dir/research.md" || return 1
  _bundle_brief "$base" >"$dir/product-brief.md" || return 1
  _bundle_prd "$base" >"$dir/prd.md" || return 1
  _bundle_architecture "$base" "$n" >"$dir/architecture.md" || return 1
  _bundle_epics "$base" >"$dir/epics.md" || return 1
  _bundle_readiness "$base" "$blocked" >"$dir/implementation-readiness.md" || return 1
  _bundle_summary "$base" "$n" >"$dir/run-summary.md" || return 1
}

_bundle_research() {
  cat <<EOF
# Technical Research: $1

The billing context already owns invoices in PostgreSQL through sqlx, and the
service crate wires axum routes for REST and async-graphql for GraphQL. An
invoice export needs one new application query and one REST route; the
workspace dependencies cover both, so no crate is added.
EOF
}

_bundle_brief() {
  cat <<EOF
# Product Brief: $1

Finance staff close each month by exporting the invoices of the period. Today
they copy rows by hand. The service offers a CSV export of one period instead,
so the monthly close takes minutes and every export reads the same rows.
EOF
}

_bundle_prd() {
  cat <<EOF
# Product Requirements: $1

## Executive Summary

Add a CSV export of the invoices of one period to the billing context.

## Functional Requirements

- FR-1: an application query lists the invoices of a period ordered by number.
- FR-2: GET /api/invoices/export?period=YYYY-MM returns the query result as CSV.

## Non-Functional Requirements

- NFR-1: the export of 10,000 invoices answers within 2 seconds.

## Product Scope

In scope: the query and the REST route. Out of scope: GraphQL and PDF output.
EOF
}

_bundle_architecture() {
  cat <<EOF
# Architecture: $1

## Tech Stack

- Rust toolchain 1.99.1, edition 2024
- Crates: axum, sqlx with the postgres feature, serde, tokio

## Constraints

(a) Commit convention: every commit subject has the form type(#$2): subject
with the literal issue number, and a story commit names its story in the
story N.M subject form, for example feat(#$2): story 1.1 add the export query.

(b) Story dispatch: a story whose Depends on line is satisfied is independent.
When the rust-backend-sdlc:rust-implementer agent is available, independent
stories may run as parallel subagents under the DB rule; otherwise implement
stories sequentially under the same DB rule. DB rule: parallel agents run only
the DB-free targets make.format, make.lint_code, make.unit_tests,
make.architecture and make.complexity; one serialized verify step runs the
DB-backed targets make.setup_test_db, make.integration_tests,
make.tests_with_coverage, make.e2e_tests and make.sqlx_prepare.
EOF
}

_bundle_epics() {
  cat <<EOF
# Epics: $1

## Epic 1: Invoice export

Finance staff export the invoices of one period as CSV from the billing context.

### Story 1.1: Add the export query to the billing context

As a finance clerk,
I want an application query that lists the invoices of a period,
So that every export reads one consistent set of rows.

**Acceptance Criteria:**

- Given two invoices dated in November, when the query runs for November, then it returns both rows ordered by number

**Depends on:** none

### Story 1.2: Expose the export over REST

As a finance clerk,
I want a GET route that returns the query result as CSV,
So that I can download the export from the browser.

**Acceptance Criteria:**

- Given the query of story 1.1, when GET /api/invoices/export?period=2026-11 is called, then the response is 200 with a text/csv body

**Depends on:** 1.1
EOF
}

_bundle_readiness() {
  if [[ "$2" == 1 ]]; then
    cat <<EOF
# Implementation Readiness: $1

Verdict: needs work

Gate: NO-GO. Story 1.2 lacks a measurable acceptance criterion.
EOF
  else
    cat <<EOF
# Implementation Readiness: $1

Verdict: ready

Every story has a description, an acceptance criterion and a Depends on line,
and the Constraints section of architecture.md holds parts (a) and (b).
EOF
  fi
}

_bundle_summary() {
  cat <<EOF
# Run Summary: $1

Planning bundle for issue #$2: one epic with two stories, readiness checked.
EOF
}

# _profile_edit MODE FILE KEY [VALUE] — the line edit behind mutate_profile
# (MODE set) and drop_profile_key (MODE drop). KEY is `name` (a top-level key)
# or `group.name` (a key indented two spaces under the column-0 line
# `group:`). The key's line is replaced or removed together with the lines
# that belong to it (deeper indentation, or `- ` items at its indentation).
# The file is rewritten in place (same inode and mode); an absent key is an
# error, so a mistyped key never passes silently.
_profile_edit() {
  local mode="$1" file="$2" key="$3" value="${4-}" tmp
  if [[ ! -f "$file" ]]; then
    printf '%s: no such profile: %s\n' "$mode" "$file" >&2
    return 1
  fi
  tmp="$(mktemp "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/profile-edit.XXXXXX")" || return 1
  # shellcheck disable=SC2016 # the awk program is single-quoted on purpose
  if ! PE_MODE="$mode" PE_KEY="$key" PE_VALUE="$value" awk '
    function starts(s, p, rest) {
      if (substr(s, 1, length(p)) != p) return 0
      rest = substr(s, length(p) + 1, 1)
      return rest == "" || rest == " "
    }
    BEGIN {
      mode = ENVIRON["PE_MODE"]; key = ENVIRON["PE_KEY"]; value = ENVIRON["PE_VALUE"]
      dot = index(key, ".")
      if (dot > 0) { group = substr(key, 1, dot - 1); name = substr(key, dot + 1); indent = "  " }
      else { group = ""; name = key; indent = "" }
      ingroup = (group == ""); found = 0; skipping = 0
    }
    {
      line = $0
      if (skipping) {
        if (line != "" && (substr(line, 1, length(indent) + 1) == indent " " || substr(line, 1, length(indent) + 2) == indent "- ")) next
        skipping = 0
      }
      if (group != "" && line ~ /^[^ #]/) ingroup = starts(line, group ":")
      if (!found && ingroup && starts(line, indent name ":")) {
        found = 1; skipping = 1
        if (mode == "set") {
          sep = (value == "" || substr(value, 1, 1) == "\n") ? "" : " "
          print indent name ":" sep value
        }
        next
      }
      print
    }
    END { exit found ? 0 : 3 }
  ' "$file" >"$tmp"; then
    rm -f "$tmp"
    printf '%s: key %s not found in %s\n' "$mode" "$key" "$file" >&2
    return 1
  fi
  cat "$tmp" >"$file" || return 1
  rm -f "$tmp"
}

# mutate_profile FILE KEY VALUE — set KEY to VALUE, written verbatim after
# `KEY: ` (quote strings yourself, e.g. "'start; rm -rf /'"); a VALUE that
# starts with a newline is written right after the colon (a block value).
mutate_profile() {
  if [[ $# -ne 3 ]]; then
    printf 'usage: mutate_profile FILE KEY VALUE\n' >&2
    return 2
  fi
  _profile_edit set "$1" "$2" "$3"
}

# drop_profile_key FILE KEY — remove KEY (and its block value, if any).
drop_profile_key() {
  if [[ $# -ne 2 ]]; then
    printf 'usage: drop_profile_key FILE KEY\n' >&2
    return 2
  fi
  _profile_edit drop "$1" "$2"
}

# docs_rules [--root DIR] FILE...
# Runs `python3 -I tests/lib/docs-rules.py --root DIR FILE...` (FILE relative
# to DIR) and returns its status: 0 clean, 1 findings (one
# `(<rule>) <file>:<line>: <message>` line each). DIR defaults to the
# materialized repository $BATS_TEST_TMPDIR/billing-service.
docs_rules() {
  local root="${BATS_TEST_TMPDIR:-.}/billing-service" plugin
  if [[ "${1-}" == --root ]]; then
    root="${2:?usage: docs_rules [--root DIR] FILE...}"
    shift 2
  fi
  plugin="${PLUGIN_ROOT:-$(_rr_plugin_root)}"
  python3 -I "$plugin/tests/lib/docs-rules.py" --root "$root" "$@"
}
