#!/usr/bin/env bash
# validate-profile.sh — check a project profile against schema v1 (rules V1-V12, FR-7).
#
# Usage: validate-profile.sh [PROFILE_FILE]
#   PROFILE_FILE  the profile to check (default: $PWD/.claude/rust-sdlc.yml)
#   --            end of options: the next argument is PROFILE_FILE even when it starts with -
#   --help        print this help and exit 0 (accepted in any position)
#
# The file is converted once with yaml_to_json (mikefarah yq v4, else python3 +
# PyYAML); every rule then runs in python3 (stdlib only) over the JSON, so YAML
# types survive (a quoted '100' stays a string) and both backends print the
# same bytes. Rules are checked in order V1-V12 and every violation is
# reported, one `VIOLATION: <key>: <reason>` line each (a key that fails a rule
# is not checked by the later rules); stdout ends with `VALID: <path>` or
# `INVALID: <path>: <n> violation(s)`. Values in a line are written the YAML
# way: strings single-quoted, ints, booleans and null bare.
# A missing profile (V1) prints only the error line
# `[rust-sdlc][ERROR] profile not found: <path> (run /rs-sdlc-setup)` on stderr.
# Writes nothing.
#
# Exit: 0 valid; 1 any violation, or the profile is missing (V1); 2 usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# The rules V3-V12 over the JSON form of the profile. argv: the display path,
# then `--json` (the JSON document on stdin) or `--parse-error REASON` (V2).
# The program contains no single quote, so it lives in a single-quoted string
# and the script needs no here-document (and so no temporary file).
VP_PROGRAM='
import json
import re
import sys

CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
Q = chr(39)
ROOT = "schema_version"
GROUPS = ("project", "rust", "template", "framework", "persistence",
          "architecture", "service", "make", "quality", "ci", "review",
          "capabilities")
ENUMS = {
    "template.sync_flavour": ("app", "pat", "both", "none"),
    "framework.http": ("axum",),
    "persistence.engine": ("postgresql",),
    "ci.provider": ("github-actions",),
    "review.reviewers": ("coderabbit", "cubic", "qodo", "qlty", "sonarcloud"),
}
TARGET = re.compile(r"[a-zA-Z0-9_-]+")
SLUG = r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"
REF = r"[A-Za-z0-9._/-]+"


def clean(text):
    return CONTROL.sub("", text)


# show VALUE — VALUE as it reads in YAML: a string single-quoted (inner quotes
# doubled, control characters stripped), ints, booleans and null bare.
def show(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return Q + clean(value).replace(Q, Q + Q) + Q
    if isinstance(value, list):
        return "[" + ", ".join(show(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{" + ", ".join(clean(str(k)) + ": " + show(v)
                               for k, v in value.items()) + "}"
    return clean(str(value))


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


# cmp_uint A B — compare two digit strings without converting them: leading
# zeros dropped, then length, then lexical order (the wrap-safe digit compare).
def cmp_uint(a, b):
    a = a.lstrip("0") or "0"
    b = b.lstrip("0") or "0"
    if len(a) != len(b):
        return 1 if len(a) > len(b) else -1
    return (a > b) - (a < b)


def regex(pattern):
    compiled = re.compile(pattern)
    return lambda value: compiled.fullmatch(value) is not None


def relative_path(value):
    if not value or value.startswith("/") or "\\" in value or CONTROL.search(value):
        return False
    return all(part not in ("", "..") for part in value.split("/"))


def url_path(value):
    return value.startswith("/") and re.search(r"[\s\x00-\x1f\x7f-\x9f]", value) is None


def single_line(value):
    return len(value) <= 200 and CONTROL.search(value) is None


def check_name(value):
    return value.strip() != "" and CONTROL.search(value) is None


def file_stem(value):
    return value != "" and "/" not in value and CONTROL.search(value) is None


MAKE = ("ci", "ci_list", "ci_preflight", "ci_static_analysis", "ci_tests",
        "ci_contracts", "ci_mutation", "ci_delivery", "ci_cli", "doctor",
        "bootstrap", "install_hooks", "bmalph_setup", "start", "format",
        "format_check", "lint_code", "static_analysis", "complexity",
        "architecture", "check_crate_isolation", "validate_architecture_model",
        "check_security", "unused_dependencies", "docs_check",
        "validate_invariants", "validate_configuration", "secrets_scan",
        "unit_tests", "integration_tests", "tests_with_coverage", "e2e_tests",
        "mutation_tests_diff", "setup_test_db", "create_migration", "migrate",
        "migrate_rollback", "sqlx_prepare", "validate_sqlx_metadata",
        "generate_openapi_spec", "generate_graphql_spec",
        "validate_contract_snapshots", "validate_openapi_spec", "openapi_diff",
        "graphql_diff", "schemathesis_validate", "image_scan",
        "smoke_load_tests", "load_tests", "new_context", "check_commit_message",
        "ai_review_loop", "pr_comments", "fr_nfr_gate", "post_review_findings")
FLOORS = ("coverage_lines", "coverage_functions")
CEILINGS = ("max_surviving_mutants", "max_clippy_findings",
            "max_complexity_violations", "max_architecture_violations",
            "max_unused_dependencies", "max_dependency_policy_findings",
            "max_spectral_findings", "max_unapproved_breaking_changes",
            "max_image_vulnerabilities_high_critical",
            "max_smoke_budget_breaches")
CAPABILITIES = ("template_derived", "run_in_container", "structurizr",
                "load_testing", "mutation_testing", "dynamic_security_testing",
                "publish_pr_comments", "protected_config", "template_sync")

# (key, kind, required, nullable, format) in schema order. Kinds: int, bool,
# str, list (of strings), enum, enumlist, port, target (make.*), floor and
# ceiling (quality.*).
SPECS = [
    (ROOT, "int", True, False, None),
    ("project.name", "str", True, False, regex(r"[a-z0-9][a-z0-9_-]*")),
    ("project.repo", "str", True, True, regex(SLUG)),
    ("project.default_branch", "str", True, False, regex(REF)),
    ("project.description", "str", False, True, single_line),
    ("rust.toolchain", "str", True, True, regex(r"[0-9A-Za-z._-]+")),
    ("rust.edition", "str", True, True, regex(r"20[0-9]{2}")),
    ("rust.msrv", "str", False, True, regex(r"[0-9]+\.[0-9]+(\.[0-9]+)?")),
    ("template.repository", "str", False, True, regex(SLUG)),
    ("template.sync_flavour", "enum", True, False, None),
    ("template.source_commit", "str", False, True, regex(r"[0-9a-f]{7,40}")),
    ("framework.http", "enum", True, True, None),
    ("framework.openapi", "bool", True, False, None),
    ("framework.graphql", "bool", True, False, None),
    ("persistence.engine", "enum", True, True, None),
    ("persistence.migrations_dir", "str", True, True, relative_path),
    ("persistence.offline_metadata", "bool", True, False, None),
    ("architecture.crates_root", "str", True, True, relative_path),
    ("architecture.composition_root", "str", True, True, relative_path),
    ("architecture.layers", "list", True, False, regex(r"[a-z][a-z0-9-]*")),
    ("architecture.bounded_contexts", "list", True, False,
     regex(r"[a-z0-9-]+/[a-z0-9-]+")),
    ("architecture.shared_crates", "list", True, False, relative_path),
    ("service.port", "port", True, False, None),
    ("service.base_url", "str", True, False,
     regex(r"http://(localhost|127\.0\.0\.1):[0-9]+")),
    ("service.liveness_path", "str", True, False, url_path),
    ("service.readiness_path", "str", True, False, url_path),
    ("service.graphql_path", "str", True, True, url_path),
    ("service.docs_path", "str", True, True, url_path),
    ("service.openapi_snapshot", "str", True, True, relative_path),
    ("service.graphql_snapshot", "str", True, True, relative_path),
]
SPECS += [("make." + key, "target", True, True, None) for key in MAKE]
SPECS += [("quality." + key, "floor", True, False, None) for key in FLOORS]
SPECS += [("quality." + key, "ceiling", True, False, None) for key in CEILINGS]
SPECS += [
    ("ci.provider", "enum", True, True, None),
    ("ci.workflows", "list", True, False, file_stem),
    ("ci.required_checks", "list", True, False, check_name),
    ("ci.human_gated", "list", True, False, check_name),
    ("ci.base_ref", "str", True, False, regex(REF)),
    ("review.coderabbit", "bool", True, False, None),
    ("review.reviewers", "enumlist", True, False, None),
    ("review.ai_review_agents", "list", True, False, regex(r"[a-z][a-z0-9-]*")),
    ("review.request_changes_blocking", "bool", True, False, None),
]
SPECS += [("capabilities." + key, "bool", True, False, None) for key in CAPABILITIES]
KNOWN = {spec[0] for spec in SPECS}


def check(doc):
    lines, failed, values = [], set(), {}
    missing = object()

    def bad(key, reason):
        lines.append("VIOLATION: " + key + ": " + reason)
        failed.add(key)

    def live():
        return [(spec, values[spec[0]]) for spec in SPECS
                if spec[0] in values and spec[0] not in failed
                and values[spec[0]] is not None]

    def usable(key):
        return key in values and key not in failed and values[key] is not None

    # V3: schema_version is the integer 1.
    if ROOT in doc and not (is_int(doc[ROOT]) and doc[ROOT] == 1):
        bad(ROOT, "must be 1 (" + show(doc[ROOT]) + ")")
    # V4: every R key present; no unknown group or key.
    for key, _kind, required, _nullable, _fmt in SPECS:
        if key == ROOT:
            node, leaf = doc, ROOT
        else:
            group, leaf = key.split(".", 1)
            node = doc.get(group, missing)
        if isinstance(node, dict) and leaf in node:
            values[key] = node[leaf]
        elif required and (node is missing or isinstance(node, dict)):
            bad(key, "missing")
    for name, node in doc.items():
        if name == ROOT:
            continue
        if name not in GROUPS:
            bad(clean(str(name)), "unknown key")
        elif not isinstance(node, dict):
            bad(name, "expected map (" + show(node) + ")")
        else:
            for leaf in node:
                if name + "." + leaf not in KNOWN:
                    bad(clean(name + "." + str(leaf)), "unknown key")
    # V5: non-nullable keys are not null.
    for key, _kind, _required, nullable, _fmt in SPECS:
        if key in values and key not in failed and values[key] is None and not nullable:
            bad(key, "must not be null")
    # V6: YAML type per key.
    for (key, kind, _required, _nullable, _fmt), value in live():
        want = None
        if kind in ("int", "port", "floor", "ceiling") and not is_int(value):
            want = "int"
        elif kind == "bool" and not isinstance(value, bool):
            want = "bool"
        elif kind in ("str", "target") and not isinstance(value, str):
            want = "string"
        elif kind in ("list", "enumlist"):
            if not isinstance(value, list):
                want = "list"
            elif not all(isinstance(item, str) for item in value):
                want = "list of string"
        if want:
            bad(key, "expected " + want + " (" + show(value) + ")")
    # V7: enum membership (each item of an enum list).
    for (key, kind, _required, _nullable, _fmt), value in live():
        if kind not in ("enum", "enumlist"):
            continue
        allowed = ENUMS[key]
        for item in value if kind == "enumlist" else [value]:
            if not (isinstance(item, str) and item in allowed):
                bad(key, "not one of " + ", ".join(allowed) + " (" + show(item) + ")")
    # V8: formats (scalars, list items, port range, non-negative bars).
    for (key, kind, _required, _nullable, fmt), value in live():
        if kind in ("floor", "ceiling", "port"):
            text = str(value)
            ok = text.isdigit() and text.isascii()
            if ok and kind == "port":
                ok = cmp_uint(text, "1") >= 0 and cmp_uint(text, "65535") <= 0
            if not ok:
                bad(key, "invalid format (" + show(value) + ")")
        elif fmt is not None:
            for item in value if isinstance(value, list) else [value]:
                if not fmt(item):
                    bad(key, "invalid format (" + show(item) + ")")
    # V9: list relations.
    gated, required_checks = "ci.human_gated", "ci.required_checks"
    if usable(gated) and usable(required_checks):
        for item in values[gated]:
            if item not in values[required_checks]:
                bad(gated, show(item) + " is not in ci.required_checks")
    if usable("review.reviewers"):
        seen, duplicates = set(), []
        for item in values["review.reviewers"]:
            if item in seen and item not in duplicates:
                duplicates.append(item)
            seen.add(item)
        for item in duplicates:
            bad("review.reviewers", "duplicate item (" + show(item) + ")")
    if usable("review.ai_review_agents") and not values["review.ai_review_agents"]:
        bad("review.ai_review_agents", "must not be empty")
    # V10: make.* values are target names.
    for (key, kind, _required, _nullable, _fmt), value in live():
        if kind == "target" and TARGET.fullmatch(value) is None:
            bad(key, "invalid target name (" + show(value) + ")")
    # V11: tighten-only quality bounds (floors exactly 100, ceilings exactly 0).
    for (key, kind, _required, _nullable, _fmt), value in live():
        text = str(value)
        if kind == "floor" and cmp_uint(text, "100") < 0:
            bad(key, "below the floor (" + text + " vs bound 100)")
        elif kind == "floor" and cmp_uint(text, "100") > 0:
            bad(key, "above the maximum (" + text + " vs bound 100)")
        elif kind == "ceiling" and cmp_uint(text, "0") > 0:
            bad(key, "above the ceiling (" + text + " vs bound 0)")
    # V12: make.<key> is null or the PA-2 identity target.
    for (key, kind, _required, _nullable, _fmt), value in live():
        want = key[len("make."):].replace("_", "-")
        if kind == "target" and value != want:
            bad(key, "must be null or " + show(want) + " (" + show(value) + ")")
    return lines


# load TEXT — (document, None), or (None, V2 reason) when the root is not a
# mapping or the converter printed more than one document.
def load(text):
    if not text.strip():
        return None, "the root is not a mapping"
    try:
        doc = json.loads(text)
    except ValueError as exc:
        if getattr(exc, "msg", "") == "Extra data":
            return None, "expected a single document in the stream"
        return None, (str(exc).splitlines() or ["invalid JSON"])[0]
    if not isinstance(doc, dict):
        return None, "the root is not a mapping"
    return doc, None


def encode(text):
    try:
        return text.encode("utf-8", "surrogateescape")
    except UnicodeEncodeError:
        return text.encode("utf-8", "backslashreplace")


def main():
    path, mode = clean(sys.argv[1]), sys.argv[2]
    if mode == "--parse-error":
        doc, reason = None, clean(sys.argv[3]).strip() or "unknown parser error"
    else:
        doc, reason = load(sys.stdin.buffer.read().decode("utf-8", "replace"))
    if reason is not None:
        lines = ["VIOLATION: " + path + ": not parseable YAML (" + clean(reason) + ")"]
    else:
        lines = check(doc)
    out = sys.stdout.buffer
    for line in lines:
        out.write(encode(line + "\n"))
    if lines:
        out.write(encode("INVALID: %s: %d violation(s)\n" % (path, len(lines))))
        return 1
    out.write(encode("VALID: " + path + "\n"))
    return 0


try:
    sys.exit(main())
except Exception as exc:  # never a traceback: one clean error line
    first = (str(exc).splitlines() or [type(exc).__name__])[0]
    sys.stderr.write("[rust-sdlc][ERROR] validate-profile: internal error: "
                     + clean(first) + "\n")
    sys.exit(1)
'

# vp_rules ARG... — run VP_PROGRAM in an isolated python3 (-I: no user site,
# no PYTHON* variables, no working directory on sys.path).
vp_rules() {
  _sdlc_py -I -c "$VP_PROGRAM" "$@"
}

main() {
  local arg profile="" input end=0 rc=0 converted reason
  local args=()
  for arg in "$@"; do
    if [[ "$arg" == --help ]]; then
      print_usage "$0"
      exit 0
    fi
  done
  while (($#)); do
    if ((end)); then
      args+=("$1")
    else
      case "$1" in
        --) end=1 ;;
        -*) die_usage "unknown argument: $1" ;;
        *) args+=("$1") ;;
      esac
    fi
    shift
  done
  if ((${#args[@]} > 1)); then
    die_usage "unexpected argument: ${args[1]}"
  fi
  if ((${#args[@]} == 1)); then
    [[ -n "${args[0]}" ]] || die_usage "PROFILE_FILE must not be empty"
    profile="${args[0]}"
  else
    profile="$(profile_path)"
  fi

  # V1: the profile exists and is a regular file.
  [[ -f "$profile" ]] || die "profile not found: $profile (run /rs-sdlc-setup)"
  have_cmd python3 || die "python3 is required to validate the profile"
  require_yaml_toolchain

  # V2: one conversion. On success yaml_to_json writes nothing to stderr; on
  # failure its last line is `[rust-sdlc][ERROR] yaml: <file>: <first error>`.
  # A relative path that starts with `-` is passed as `./-…`, so the YAML
  # backend never reads it as an option; output lines keep the given path.
  input="$profile"
  if [[ "$input" == -* ]]; then
    input="./$input"
  fi
  converted="$(yaml_to_json "$input" 2>&1)" || rc=$?
  if ((rc != 0)); then
    reason="${converted##*$'\n'}"
    reason="${reason#'[rust-sdlc][ERROR] '}"
    reason="${reason#"yaml: $input: "}"
    vp_rules "$profile" --parse-error "$reason" </dev/null || exit "$?"
    exit 0
  fi
  printf '%s\n' "$converted" | vp_rules "$profile" --json || exit "$?"
}

main "$@"
