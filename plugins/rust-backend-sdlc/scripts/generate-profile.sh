#!/usr/bin/env bash
# generate-profile.sh — detect the project profile .claude/rust-sdlc.yml from repository files (FR-6).
#
# Usage: generate-profile.sh [--refresh] [--stdout] [--run-in-container true|false] [TARGET_DIR]
#
#   TARGET_DIR                     the repository root (default: the working directory)
#   --refresh                      rewrite an existing profile with the re-detected values; the
#                                  five user-owned keys keep a valid existing value (ADR-24)
#   --stdout                       print the profile YAML on stdout and write nothing
#   --run-in-container true|false  set capabilities.run_in_container; the flag wins over the
#                                  existing value and over detection. Without --refresh, an
#                                  existing profile gets only this key rewritten
#   --                             end of options: the next argument is TARGET_DIR
#   --help                         print this help and exit 0 (accepted in any position)
#
# Detection reads files only (Cargo.toml, rust-toolchain.toml, architecture.toml,
# protected-config.toml, Makefile and make/*.mk, clippy.toml, the workflows,
# docs/repository-settings.md and docs/repository-settings-service.md,
# .coderabbit.yaml, .env, workspace.dsl, tests/Load/, .sqlx/, migrations/, the
# contract snapshots) plus `git remote get-url origin`, the default branch and
# `git log --format=%s`. It never runs cargo, make, gh or the network and never
# reads .env.local. Its only probes are `docker info` and `command -v cargo`,
# run only when neither the flag nor an existing profile decides
# capabilities.run_in_container. A missing source never fails generation: the
# key takes its fallback. User-owned keys (kept when valid): run_in_container,
# dynamic_security_testing, publish_pr_comments, review.reviewers,
# review.ai_review_agents. The profile is written only through
# `mktemp .claude/.rust-sdlc.yml.XXXXXX` + `mv`.
#
# Stdout: `WROTE: .claude/rust-sdlc.yml` (no profile yet, or --refresh with a
# change); `UNCHANGED: .claude/rust-sdlc.yml` (the file equals what --refresh
# would write); `UPDATED: .claude/rust-sdlc.yml (capabilities.run_in_container=<v>)`;
# `DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)` followed
# by a unified diff (`--- .claude/rust-sdlc.yml`, `+++ detected`). With
# --stdout only the YAML. Stderr: `[rust-sdlc][WARN]` lines for an unmapped
# human-gated job id, a repository gate looser than the template value and an
# unparseable source file.
#
# Exit: 0 success (a reported difference keeps the file and still exits 0); 1 refusal (symlinked .claude, symlinked or non-regular profile), missing TARGET_DIR or failure; 2 usage error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROFILE_REL=.claude/rust-sdlc.yml

# gp_program — the python3 program behind every detection and comparison step.
# Modes (argv[1]):
#   detect SLUG BRANCH SOURCE_COMMIT RIC PROFILE_JSON CODERABBIT_JSON HUMAN_GATED_TSV
#       run in TARGET_DIR; prints one record per YAML line, `<prefix>\t<kind>\t<value>`
#       with kind h (prefix only), b (bare value), s (yaml_squote value) or
#       p (probe capabilities.run_in_container); WARN lines go to stderr.
#   compare FILE DETECTED DIFF_OUT
#       exit 0 when the bytes are equal, else writes the unified diff to
#       DIFF_OUT and exits 3.
#   set-ric FILE VALUE PROFILE_JSON OUT
#       writes FILE with only capabilities.run_in_container set to VALUE to OUT
#       (exit 0); exit 4 when the profile already holds VALUE, 5 when the key's
#       line cannot be located.
gp_program() {
  cat <<'PY'
import difflib
import json
import os
import re
import sys

CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f\ud800-\udfff￾￿]")
DIFF_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]")
SLUG = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
REF = re.compile(r"[A-Za-z0-9._/-]+")
LAYER = re.compile(r"[a-z][a-z0-9-]*")
CONTEXT = re.compile(r"[a-z0-9-]+/[a-z0-9-]+")
MEMBER = re.compile(r"crates/([^/]+)/([^/]+)/(domain|application|infrastructure)")
RULE = re.compile(r"([A-Za-z0-9_-]+)(?::(?![:=])|::(?![:=]))(.*)")
APP_PORT = re.compile(r"APP_PORT=([0-9]+)")
REVIEWERS = ("coderabbit", "cubic", "qodo", "qlty", "sonarcloud")
YAML_WORDS = ("null", "true", "false", "yes", "no", "on", "off")
MARKERS = ("rust-toolchain.toml", "architecture.toml", "protected-config.toml",
           "xtask/Cargo.toml", "make/gates.mk", "crates/service/Cargo.toml",
           "workspace.dsl")
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
QUALITY = (("coverage_lines", 100), ("coverage_functions", 100),
           ("max_surviving_mutants", 0), ("max_clippy_findings", 0),
           ("max_complexity_violations", 0), ("max_architecture_violations", 0),
           ("max_unused_dependencies", 0), ("max_dependency_policy_findings", 0),
           ("max_spectral_findings", 0), ("max_unapproved_breaking_changes", 0),
           ("max_image_vulnerabilities_high_critical", 0),
           ("max_smoke_budget_breaches", 0))
CLIPPY = (("cognitive-complexity-threshold", 8), ("too-many-lines-threshold", 50),
          ("too-many-arguments-threshold", 5), ("excessive-nesting-threshold", 5))
MISSING = object()


def clean(text):
    return CTRL.sub("", text)


def first_line(exc):
    return (str(exc).strip().splitlines() or [type(exc).__name__])[0]


def warn(message):
    sys.stderr.buffer.write(("[rust-sdlc][WARN] " + clean(message) + "\n")
                            .encode("utf-8", "replace"))


def read_text(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError as exc:
        warn("%s is not readable (%s); the keys it feeds take their fallback"
             % (path, first_line(exc)))
        return None


def load_toml(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "rb") as handle:
            doc = tomllib.load(handle)
    except Exception as exc:  # malformed TOML, bad encoding or unreadable file
        warn("%s is not parseable TOML (%s); the keys it feeds take their fallback"
             % (path, first_line(exc)))
        return None
    return doc


def load_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError:
        return None
    if not text.strip():
        return None
    try:
        return json.loads(text)
    except ValueError:
        return MISSING


def table(node, *keys):
    for key in keys:
        node = node.get(key) if isinstance(node, dict) else None
    return node if isinstance(node, dict) else {}


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def assignment(text, name):
    """The value of the first make assignment of NAME (=, :=, ::=, ?=)."""
    pattern = re.compile(r"\s*(?:(?:export|override)\s+)*" + re.escape(name)
                         + r"\s*(?::{1,3}|\?)?=(.*)")
    for line in text.replace("\\\n", " ").split("\n"):
        match = pattern.fullmatch(line)
        if match:
            return re.sub(r"\s*#.*\Z", "", match.group(1)).strip()
    return None


def flag_value(text, *flags):
    names = "|".join(re.escape(flag) for flag in flags)
    match = re.search(r"(?:^|\s)(?:" + names + r")(?:=|\s+)(\S+)", text)
    return match.group(1) if match else None


def looser(path, setting, template, default):
    warn("%s %s is looser than the template value %s; the profile keeps %s"
         % (path, setting, template, default))


def quality_warnings():
    gates = read_text("make/gates.mk")
    if gates is not None:
        coverage = assignment(gates, "COVERAGE_GATE_CMD")
        if coverage is not None:
            for flag in ("--fail-under-lines", "--fail-under-functions"):
                value = flag_value(coverage, flag)
                if value is None or not value.isdigit() or int(value) < 100:
                    looser("make/gates.mk", "COVERAGE_GATE_CMD " + flag, "100", "100")
        spectral = assignment(gates, "SPECTRAL_FLAGS")
        if spectral is not None:
            value = flag_value(spectral, "--fail-severity", "-F")
            if value is None or value.lower() != "hint":
                looser("make/gates.mk", "SPECTRAL_FLAGS --fail-severity", "hint", "0")
        oasdiff = assignment(gates, "OASDIFF_FLAGS")
        if oasdiff is not None:
            value = flag_value(oasdiff, "--fail-on", "-o")
            if value is None or value.upper() not in ("ERR", "WARN", "INFO"):
                looser("make/gates.mk", "OASDIFF_FLAGS --fail-on", "ERR", "0")
        trivy = assignment(gates, "TRIVY_FLAGS")
        if trivy is not None:
            value = flag_value(trivy, "--severity", "-s")
            if value is not None:
                levels = {level.strip().upper() for level in value.split(",")}
                if not {"HIGH", "CRITICAL"} <= levels:
                    looser("make/gates.mk", "TRIVY_FLAGS --severity", "HIGH,CRITICAL", "0")
    clippy = load_toml("clippy.toml")
    if clippy is not None:
        for key, limit in CLIPPY:
            value = clippy.get(key)
            if not is_int(value) or value > limit or (
                    key == "excessive-nesting-threshold" and value < 1):
                looser("clippy.toml", key, str(limit), "0")


def project_name():
    raw = os.fsencode(os.path.basename(os.getcwd()))
    name = re.sub(rb"[^a-z0-9_-]", b"-", raw.lower()).decode("ascii")
    name = name.lstrip("-_")
    if not name:
        warn("the directory name gives no project name; project.name falls back to 'project'")
        name = "project"
    return name


def relative_path(value):
    if not value or value.startswith("/") or "\\" in value or CTRL.search(value):
        return False
    return all(part not in ("", "..") for part in value.split("/"))


def members_of(workspace):
    members = workspace.get("members")
    out = []
    for member in members if isinstance(members, list) else []:
        if not isinstance(member, str):
            continue
        member = member.strip()
        while member.startswith("./"):
            member = member[2:]
        out.append(member.rstrip("/"))
    return out


def required_checks_of(path, checks):
    text = read_text(path)
    if text is None:
        return
    section, header = "", None
    for line in text.split("\n"):
        if line.startswith("## "):
            section, header = line[3:].strip().lower(), None
            continue
        row = line.strip()
        if not row.startswith("|"):
            header = None
            continue
        cells = [cell.strip() for cell in row.strip("|").split("|")]
        if header is None:
            header = [cell.lower() for cell in cells]
            continue
        if all(set(cell) <= set("-: ") for cell in cells):
            continue
        if section != "required status checks":
            continue
        if "check name" not in header or "required" not in header:
            continue
        name_at, required_at = header.index("check name"), header.index("required")
        if len(cells) <= max(name_at, required_at):
            continue
        if cells[required_at].strip("` ").lower() != "yes":
            continue
        name = clean(cells[name_at]).strip().strip("`").strip()
        if name and name not in checks:
            checks.append(name)


def existing(profile, group, key):
    node = profile.get(group) if isinstance(profile, dict) else None
    return node.get(key, MISSING) if isinstance(node, dict) else MISSING


def detect(argv):
    slug, branch, source_commit, ric, profile_json, coderabbit_json, gated_tsv = argv
    out = []

    def header(text):
        out.append(text + "\th")

    def bare(prefix, value):
        out.append(prefix + "\tb\t" + value)

    def quoted(prefix, value):
        out.append(prefix + "\ts\t" + clean(value))

    def optional(prefix, value):
        if value is None:
            bare(prefix, "null")
        else:
            quoted(prefix, value)

    def flag(prefix, value):
        bare(prefix, "true" if value else "false")

    def listing(prefix, items, quote=True):
        if not items:
            bare(prefix, "[]")
            return
        header(prefix)
        for item in items:
            (quoted if quote else bare)("    -", item)

    profile = load_json(profile_json)
    if profile is MISSING or (profile is not None and not isinstance(profile, dict)):
        warn(".claude/rust-sdlc.yml is not a YAML mapping; its user-owned keys take "
             "their detected values")
        profile = None
    coderabbit = load_json(coderabbit_json)
    if coderabbit is MISSING:
        warn(".coderabbit.yaml holds more than one document; "
             "review.request_changes_blocking falls back to false")
        coderabbit = None

    # project, rust, template
    cargo = load_toml("Cargo.toml") or {}
    workspace = table(cargo, "workspace")
    package = table(workspace, "package")
    dependencies = table(workspace, "dependencies")
    repo = slug if SLUG.fullmatch(slug) else None
    if not REF.fullmatch(branch):
        branch = "main"
    description = package.get("description")
    if isinstance(description, str):
        description = clean(re.sub(r"\s+", " ", description)).strip() or None
        if description is not None and len(description) > 200:
            warn("Cargo.toml [workspace.package].description is longer than 200 "
                 "characters; project.description falls back to null")
            description = None
    else:
        description = None
    toolchain = table(load_toml("rust-toolchain.toml") or {}, "toolchain").get("channel")
    if not (isinstance(toolchain, str) and re.fullmatch(r"[0-9A-Za-z._-]+", toolchain)):
        toolchain = None
    edition = package.get("edition")
    edition = str(edition) if isinstance(edition, str) or is_int(edition) else None
    if edition is not None and not re.fullmatch(r"20[0-9]{2}", edition):
        edition = None
    msrv = package.get("rust-version")
    if not (isinstance(msrv, str) and re.fullmatch(r"[0-9]+\.[0-9]+(\.[0-9]+)?", msrv)):
        msrv = None
    sync_app = os.path.isfile(".github/workflows/template-sync-app.yml")
    sync_pat = os.path.isfile(".github/workflows/template-sync-pat.yml")
    template_repository = None
    for name in ("template-sync-app.yml", "template-sync-pat.yml"):
        text = read_text(".github/workflows/" + name) or ""
        for line in text.split("\n"):
            match = re.fullmatch(r"\s*TEMPLATE_REPOSITORY\s*:\s*(.*?)\s*", line)
            if not match:
                continue
            value = re.sub(r"\s+#.*\Z", "", match.group(1)).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"" + chr(39):
                value = value[1:-1]
            if SLUG.fullmatch(value):
                template_repository = value
            break
        if template_repository is not None:
            break
    flavour = {(True, True): "both", (True, False): "app",
               (False, True): "pat"}.get((sync_app, sync_pat), "none")
    if not (source_commit and re.fullmatch(r"[0-9a-f]{7,40}", source_commit)):
        source_commit = None

    # framework, persistence, architecture
    http = "axum" if "axum" in dependencies else None
    openapi = "utoipa" in dependencies
    graphql = "async-graphql" in dependencies
    sqlx = dependencies.get("sqlx")
    features = sqlx.get("features") if isinstance(sqlx, dict) else None
    engine = "postgresql" if isinstance(features, list) and "postgres" in features else None
    layers = []
    declared = (load_toml("architecture.toml") or {}).get("layer")
    for layer in declared if isinstance(declared, list) else []:
        name = layer.get("name") if isinstance(layer, dict) else None
        if isinstance(name, str) and LAYER.fullmatch(name) and name not in layers:
            layers.append(name)
    contexts, shared = [], []
    for member in members_of(workspace):
        match = MEMBER.fullmatch(member)
        if match and match.group(1) != "shared":
            context = match.group(1) + "/" + match.group(2)
            if CONTEXT.fullmatch(context) and context not in contexts:
                contexts.append(context)
        if member.startswith("crates/shared/") and relative_path(member) \
                and member not in shared:
            shared.append(clean(member))

    # service
    port = 8081
    env = read_text(".env")
    for line in (env or "").split("\n"):
        match = APP_PORT.fullmatch(line)
        if match:
            if 1 <= int(match.group(1)) <= 65535:
                port = int(match.group(1))
            else:
                warn(".env APP_PORT %s is outside 1-65535; service.port falls back to 8081"
                     % match.group(1))
            break

    # make map
    documented = set()
    sources = ["Makefile"]
    if os.path.isdir("make"):
        sources += sorted("make/" + name for name in os.listdir("make")
                          if name.endswith(".mk") and not name.startswith("."))
    makefile = read_text("Makefile") or ""
    for path in sources:
        for line in (read_text(path) or "").split("\n"):
            match = RULE.fullmatch(line)
            if match and re.search(r"##\s", match.group(2)):
                documented.add(match.group(1))
    targets = {key: key.replace("_", "-") for key in MAKE}
    make = {key: (target if target in documented else None) for key, target in targets.items()}
    quality_warnings()

    # ci
    stems = set()
    if os.path.isdir(".github/workflows"):
        for name in os.listdir(".github/workflows"):
            if name.startswith(".") or not os.path.isfile(".github/workflows/" + name):
                continue
            for extension in (".yml", ".yaml"):
                if name.endswith(extension) and clean(name[:-len(extension)]):
                    stems.add(clean(name[:-len(extension)]))
    workflows = sorted(stems, key=lambda stem: stem.encode("utf-8", "replace"))
    required = []
    required_checks_of("docs/repository-settings.md", required)
    required_checks_of("docs/repository-settings-service.md", required)
    gated = []
    try:
        with open(gated_tsv, encoding="utf-8", errors="replace") as handle:
            pairs = handle.read().split("\n")
    except OSError:
        pairs = []
    for pair in pairs:
        if "\t" not in pair:
            continue
        check = clean(pair.split("\t", 1)[1]).strip()
        if not check or check in gated:
            continue
        if check in required:
            gated.append(check)
        else:
            warn("human-gated check %r is not a required check of the repository-settings "
                 "tables; ci.human_gated drops it" % check)

    # review
    has_coderabbit = os.path.isfile(".coderabbit.yaml")
    blocking = table(coderabbit, "reviews").get("request_changes_workflow") is True

    # user-owned keys (ADR-24): a valid existing value survives
    if ric:
        run_in_container = ric
    else:
        value = existing(profile, "capabilities", "run_in_container")
        run_in_container = ("true" if value else "false") if isinstance(value, bool) else None
    value = existing(profile, "capabilities", "dynamic_security_testing")
    dynamic = value if isinstance(value, bool) else False
    value = existing(profile, "capabilities", "publish_pr_comments")
    publish = value if isinstance(value, bool) else bool(workflows) and repo is not None
    reviewers = ["coderabbit"] if has_coderabbit else []
    value = existing(profile, "review", "reviewers")
    if isinstance(value, list) and all(isinstance(item, str) and item in REVIEWERS
                                       for item in value) \
            and len(set(value)) == len(value):
        reviewers = value
    agents = ["claude"]
    value = existing(profile, "review", "ai_review_agents")
    if isinstance(value, list) and value and all(
            isinstance(item, str) and LAYER.fullmatch(item) and item not in YAML_WORDS
            for item in value):
        agents = value

    # capabilities
    preflight = (assignment(makefile, "CI_PREFLIGHT_TARGETS") or "").split()
    derived = all(os.path.isfile(path) for path in MARKERS) \
        and preflight[:1] == ["validate-configuration"]

    header("# Project profile of the rust-backend-sdlc plugin (schema_version 1).")
    header("# Written by generate-profile.sh; re-detect with /rs-sdlc-setup --refresh.")
    bare("schema_version:", "1")
    header("project:")
    quoted("  name:", project_name())
    optional("  repo:", repo)
    quoted("  default_branch:", branch)
    optional("  description:", description)
    header("rust:")
    optional("  toolchain:", toolchain)
    optional("  edition:", edition)
    optional("  msrv:", msrv)
    header("template:")
    optional("  repository:", template_repository)
    bare("  sync_flavour:", flavour)
    optional("  source_commit:", source_commit)
    header("framework:")
    bare("  http:", http or "null")
    flag("  openapi:", openapi)
    flag("  graphql:", graphql)
    header("persistence:")
    bare("  engine:", engine or "null")
    optional("  migrations_dir:", "migrations" if os.path.isdir("migrations") else None)
    flag("  offline_metadata:", os.path.isdir(".sqlx"))
    header("architecture:")
    optional("  crates_root:", "crates" if os.path.isdir("crates") else None)
    optional("  composition_root:",
             "crates/service" if os.path.isfile("crates/service/Cargo.toml") else None)
    listing("  layers:", layers)
    listing("  bounded_contexts:", contexts)
    listing("  shared_crates:", shared)
    header("service:")
    bare("  port:", str(port))
    quoted("  base_url:", "http://localhost:%d" % port)
    quoted("  liveness_path:", "/ping")
    quoted("  readiness_path:", "/api/health")
    optional("  graphql_path:", "/api/graphql" if graphql else None)
    optional("  docs_path:", "/api/docs" if openapi else None)
    optional("  openapi_snapshot:", ".github/openapi-spec/spec.yaml"
             if os.path.isfile(".github/openapi-spec/spec.yaml") else None)
    optional("  graphql_snapshot:", ".github/graphql-spec/spec"
             if os.path.isfile(".github/graphql-spec/spec") else None)
    header("make:")
    for key in MAKE:
        bare("  " + key + ":", make[key] or "null")
    header("quality:")
    for key, default in QUALITY:
        bare("  " + key + ":", str(default))
    header("ci:")
    bare("  provider:", "github-actions" if workflows else "null")
    listing("  workflows:", workflows)
    listing("  required_checks:", required)
    listing("  human_gated:", gated)
    quoted("  base_ref:", "origin/" + branch)
    header("review:")
    flag("  coderabbit:", has_coderabbit)
    listing("  reviewers:", reviewers, quote=False)
    listing("  ai_review_agents:", agents, quote=False)
    flag("  request_changes_blocking:", blocking)
    header("capabilities:")
    flag("  template_derived:", derived)
    if run_in_container is None:
        out.append("  run_in_container:\tp\t")
    else:
        bare("  run_in_container:", run_in_container)
    flag("  structurizr:", os.path.isfile("workspace.dsl")
         and make["validate_architecture_model"] is not None)
    flag("  load_testing:", os.path.isdir("tests/Load") and make["smoke_load_tests"] is not None)
    flag("  mutation_testing:", make["mutation_tests_diff"] is not None)
    flag("  dynamic_security_testing:", dynamic)
    flag("  publish_pr_comments:", publish)
    flag("  protected_config:", os.path.isfile("protected-config.toml"))
    flag("  template_sync:", sync_app or sync_pat)
    sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8", "replace"))
    return 0


def lines_of(text):
    parts = text.split("\n")
    lines = [part + "\n" for part in parts[:-1]]
    if parts[-1]:
        lines.append(parts[-1])
    return lines


def compare(argv):
    path, detected, diff_out = argv
    with open(path, "rb") as handle:
        old = handle.read()
    with open(detected, "rb") as handle:
        new = handle.read()
    if old == new:
        return 0
    chunks = []
    for line in difflib.unified_diff(lines_of(old.decode("utf-8", "replace")),
                                     lines_of(new.decode("utf-8", "replace")),
                                     ".claude/rust-sdlc.yml", "detected"):
        line = DIFF_CTRL.sub("", line[:-1] if line.endswith("\n") else line)
        chunks.append(line + "\n")
    with open(diff_out, "wb") as handle:
        handle.write("".join(chunks).encode("utf-8", "replace"))
    return 3


def set_run_in_container(argv):
    path, value, profile_json, out = argv
    current = existing(load_json(profile_json), "capabilities", "run_in_container")
    if isinstance(current, bool) and ("true" if current else "false") == value:
        return 4
    with open(path, "rb") as handle:
        data = handle.read()
    if b"\0" in data:
        return 5
    lines = data.decode("utf-8", "surrogateescape").split("\n")
    inside, done = False, False
    for index, line in enumerate(lines):
        if re.match(r"[^\s#]", line):
            inside = re.fullmatch(r"capabilities\s*:\s*(#.*)?\r?", line) is not None
            continue
        if inside and not done:
            match = re.fullmatch(r"(\s+run_in_container\s*:)[^#\r]*?(\s+#[^\r]*)?(\r?)", line)
            if match:
                lines[index] = match.group(1) + " " + value + (match.group(2) or "") \
                    + match.group(3)
                done = True
    if not done:
        return 5
    with open(out, "wb") as handle:
        handle.write("\n".join(lines).encode("utf-8", "surrogateescape"))
    return 0


try:
    import tomllib
except ImportError:
    sys.stderr.write("[rust-sdlc][ERROR] python3 3.11+ with tomllib is required\n")
    sys.exit(1)

MODES = {"detect": (detect, 7), "compare": (compare, 3), "set-ric": (set_run_in_container, 4)}
try:
    handler, arity = MODES[sys.argv[1]]
    if len(sys.argv) != arity + 2:
        raise ValueError("mode %s takes %d arguments" % (sys.argv[1], arity))
    sys.exit(handler(sys.argv[2:]))
except Exception as exc:  # never a traceback: one clean error line
    sys.stderr.write("[rust-sdlc][ERROR] generate-profile: internal error: "
                     + clean(first_line(exc)) + "\n")
    sys.exit(1)
PY
}

# gp_py MODE ARG... — the program in an isolated python3 (-I: no user site, no
# PYTHON* variables, the target repository never on sys.path).
gp_py() {
  _sdlc_py -I -c "$GP_PROGRAM" "$@"
}

# gp_github_slug ORIGIN — owner/name of a github.com origin URL (https://,
# git@github.com: or ssh://git@github.com/, `.git` stripped); nothing else.
gp_github_slug() {
  local origin="${1-}" slug=""
  case "$origin" in
    https://github.com/*) slug="${origin#https://github.com/}" ;;
    git@github.com:*) slug="${origin#git@github.com:}" ;;
    ssh://git@github.com/*) slug="${origin#ssh://git@github.com/}" ;;
    *) ;;
  esac
  slug="${slug%/}"
  slug="${slug%.git}"
  if is_slug "$slug"; then
    printf '%s\n' "$slug"
  fi
}

# gp_source_commit — the commit of the first `git log --format=%s` subject of
# the form `chore(#N): import template <slug> at <sha>`.
gp_source_commit() {
  local subject pattern='^chore\(#[0-9]+\): import template [^ ]+ at ([0-9a-f]{7,40})$'
  while IFS= read -r subject; do
    if [[ "$subject" =~ $pattern ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < <(git log --format=%s -E --grep='^chore\(#[0-9]+\): import template ' 2>/dev/null || true)
}

# gp_probe_container — capabilities.run_in_container by detection: true when
# `docker info` exits 0 and no cargo is on PATH.
gp_probe_container() {
  if docker info >/dev/null 2>&1 && ! command -v cargo >/dev/null 2>&1; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

# gp_emit — the detect records on stdin as YAML lines; every string scalar
# goes through yaml_squote.
gp_emit() {
  local prefix kind value
  while IFS=$'\t' read -r prefix kind value; do
    case "$kind" in
      h) printf '%s\n' "$prefix" ;;
      b) printf '%s %s\n' "$prefix" "$value" ;;
      s)
        printf '%s ' "$prefix"
        yaml_squote "$value"
        ;;
      p) printf '%s %s\n' "$prefix" "$(gp_probe_container)" ;;
      *) die "generate-profile: internal error: unknown record kind '$kind'" ;;
    esac
  done
}

# gp_write — the detected profile into place: safe_write_target, then
# atomic_write (mktemp .claude/.rust-sdlc.yml.XXXXXX + mv).
gp_write() {
  safe_write_target "$PROFILE_REL" "$TARGET" || exit 1
  atomic_write "$PROFILE_REL" <"$1" || die "cannot write $PROFILE_REL"
}

# --- arguments ---------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == --help ]]; then
    print_usage "$0"
    exit 0
  fi
done

REFRESH=0
TO_STDOUT=0
RIC=""
TARGET=""
HAVE_TARGET=0
END=0
while (($#)); do
  if ((END == 0)); then
    case "$1" in
      --refresh)
        REFRESH=1
        shift
        continue
        ;;
      --stdout)
        TO_STDOUT=1
        shift
        continue
        ;;
      --run-in-container)
        need_value "$1" "${2-}"
        case "$2" in
          true | false) RIC="$2" ;;
          *) die_usage "--run-in-container takes true or false, not '$2'" ;;
        esac
        shift 2
        continue
        ;;
      --)
        END=1
        shift
        continue
        ;;
      -*) die_usage "unknown argument: $1" ;;
      *) ;;
    esac
  fi
  if ((HAVE_TARGET)); then
    die_usage "unexpected argument: $1"
  fi
  [[ -n "$1" ]] || die_usage "TARGET_DIR must not be empty"
  TARGET="$1"
  HAVE_TARGET=1
  shift
done
if ((HAVE_TARGET == 0)); then
  TARGET="$PWD"
fi
[[ -d "$TARGET" ]] || die "target directory not found: $TARGET"
TARGET="$(CDPATH='' cd -- "$TARGET" && pwd -P)" || die "cannot enter the target directory: $TARGET"
cd -- "$TARGET" || die "cannot enter the target directory: $TARGET"

# --- refusals, before anything is read or written (NFR-1) -----------------------

if [[ -L .claude ]]; then
  die "refusing to write $PROFILE_REL: .claude is a symbolic link"
fi
if [[ -e .claude && ! -d .claude ]]; then
  die "refusing to write $PROFILE_REL: .claude is not a directory"
fi
safe_write_target "$PROFILE_REL" "$TARGET" || exit 1
if [[ -e "$PROFILE_REL" && ! -r "$PROFILE_REL" ]]; then
  die "cannot read $PROFILE_REL: permission denied"
fi
have_cmd python3 || die "python3 3.11+ is required to detect the profile"
require_yaml_toolchain

WORK="$(mktemp -d "${TMPDIR:-/tmp}/generate-profile.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf -- "$WORK"' EXIT
GP_PROGRAM="$(gp_program)"
: >"$WORK/profile.json"
: >"$WORK/coderabbit.json"

# --- inputs that need git or a YAML backend ---------------------------------------

HAVE_PROFILE=0
if [[ -f "$PROFILE_REL" ]]; then
  HAVE_PROFILE=1
  if ! yaml_to_json "$PROFILE_REL" >"$WORK/profile.json" 2>/dev/null; then
    log_warn "$PROFILE_REL is not parseable YAML; its user-owned keys take their detected values"
    : >"$WORK/profile.json"
  fi
fi
if [[ -f .coderabbit.yaml ]]; then
  if ! yaml_to_json .coderabbit.yaml >"$WORK/coderabbit.json" 2>/dev/null; then
    log_warn ".coderabbit.yaml is not parseable YAML; review.request_changes_blocking falls back to false"
    : >"$WORK/coderabbit.json"
  fi
fi

SLUG=""
BRANCH=main
SOURCE_COMMIT=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SLUG="$(gp_github_slug "$(git remote get-url origin 2>/dev/null || true)")"
  BRANCH="$(default_branch .)"
  SOURCE_COMMIT="$(gp_source_commit)"
fi
human_gated_labels . >"$WORK/human-gated.tsv" || : >"$WORK/human-gated.tsv"

# --- detection and emission --------------------------------------------------------

gp_py detect "$SLUG" "$BRANCH" "$SOURCE_COMMIT" "$RIC" "$WORK/profile.json" \
  "$WORK/coderabbit.json" "$WORK/human-gated.tsv" >"$WORK/records" || die "profile detection failed"
gp_emit <"$WORK/records" >"$WORK/detected.yml"

if ((TO_STDOUT)); then
  cat -- "$WORK/detected.yml"
  exit 0
fi

if ((HAVE_PROFILE == 0)); then
  gp_write "$WORK/detected.yml"
  printf 'WROTE: %s\n' "$PROFILE_REL"
  exit 0
fi

if ((REFRESH)); then
  rc=0
  gp_py compare "$PROFILE_REL" "$WORK/detected.yml" "$WORK/diff" || rc=$?
  case "$rc" in
    0) printf 'UNCHANGED: %s\n' "$PROFILE_REL" ;;
    3)
      gp_write "$WORK/detected.yml"
      printf 'WROTE: %s\n' "$PROFILE_REL"
      ;;
    *) die "cannot compare $PROFILE_REL with the detected profile" ;;
  esac
  exit 0
fi

# Without --refresh the file is kept; only an explicit --run-in-container
# rewrites capabilities.run_in_container (ADR-24).
UPDATED=0
if [[ -n "$RIC" ]]; then
  rc=0
  gp_py set-ric "$PROFILE_REL" "$RIC" "$WORK/profile.json" "$WORK/updated.yml" || rc=$?
  case "$rc" in
    0)
      gp_write "$WORK/updated.yml"
      printf 'UPDATED: %s (capabilities.run_in_container=%s)\n' "$PROFILE_REL" "$RIC"
      UPDATED=1
      ;;
    4) ;;
    5) die "cannot find the capabilities.run_in_container line in $PROFILE_REL; re-run with --refresh" ;;
    *) die "cannot update capabilities.run_in_container in $PROFILE_REL" ;;
  esac
fi

rc=0
gp_py compare "$PROFILE_REL" "$WORK/detected.yml" "$WORK/diff" || rc=$?
case "$rc" in
  0)
    if ((UPDATED == 0)); then
      printf 'UNCHANGED: %s\n' "$PROFILE_REL"
    fi
    ;;
  3)
    printf 'DIFF: %s (kept; re-run with --refresh to apply)\n' "$PROFILE_REL"
    cat -- "$WORK/diff"
    ;;
  *) die "cannot compare $PROFILE_REL with the detected profile" ;;
esac
exit 0
