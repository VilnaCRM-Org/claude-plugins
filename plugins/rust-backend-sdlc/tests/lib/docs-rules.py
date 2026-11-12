"""docs-rules.py — static port of the template's docs-check rules 1-4 + invariant (e).

Usage: python3 -I tests/lib/docs-rules.py --root <repo> FILE...

Reads each FILE (a path relative to --root) and prints one line
``(<rule>) <file>:<line>: <message>`` per finding, sorted by rule, file and line.
Only inline code spans and the lines of fenced blocks count as citations, never
plain prose, as in the template's scripts/check-docs.sh:

  (1) a cited ``make <target>`` (code span or fence line) whose target has no
      ``^[a-zA-Z0-9_-]+:.*##[[:space:]]`` rule in the Makefile or make/*.mk;
  (2) a code span that is exactly ``/name`` (or starts with ``/name ``) without
      .claude/commands/name.md; ``/ping``, the first segments of the OpenAPI
      snapshot paths, the router routes and the Dockerfile WORKDIR are no
      slash commands;
  (3) a backticked path whose first segment is a tracked top-level name (or
      _bmad, _bmad-output, .ralph), checked up to its first placeholder or
      wildcard, that neither exists on disk nor matches a git-ignore rule;
  (4) a numbered list or fenced block citing three or more gate targets (the
      union of the CI_*_TARGETS variables of the Makefile and make/*.mk),
      unless it sits between <!-- verification:start --> and
      <!-- verification:end --> in AGENTS.md;
  (e) a line holding the template's own repository name (the literal is
      assembled from two halves below) or the repository name of the sync
      workflows' TEMPLATE_REPOSITORY: line; that line of the two sync
      workflows is the one allowed place. (e) checks every FILE named: the
      caller picks the files (the template's rule covers CLAUDE.md, AGENTS.md
      and its code and workflow directories, not README.md or docs/).

The template's run-time parts (the verification block against make ci-list,
service commands from the binary's help) are out of scope: nothing is
executed except git. Rule 1 knows only the targets documented with ``##``,
the set ``make help`` lists in a template-derived repository. "Tracked" means
git ls-files when --root has a .git entry, else every file under --root.

Exit: 0 no finding; 1 at least one finding; 2 usage error.
"""

import argparse
import glob
import os
import re
import subprocess
import sys

TEMPLATE_NAME = "rust-service-" + "template"
SPECIALS = ("_bmad", "_bmad-output", ".ralph")
SYNC_WORKFLOWS = (
    ".github/workflows/template-sync-app.yml",
    ".github/workflows/template-sync-pat.yml",
)
VERIFY_START = "<!-- verification:start -->"
VERIFY_END = "<!-- verification:end -->"

WS = " \t\n\r\f\v"
WS_SPLIT = re.compile(r"[ \t\n\r\f\v]+")
TARGET_RULE = re.compile(r"^([a-zA-Z0-9_-]+):.*##[ \t\n\r\f\v]")
TARGET_WORD = re.compile(r"[a-z][a-z0-9_-]*\Z")
CI_VAR = re.compile(r"^(CI_[A-Za-z0-9_]*_TARGETS)[ \t]*(?:::?=|:::=|\?=|\+=|!=|=)(.*)")
ITEM = re.compile(r"^[ \t\n\r\f\v]*[0-9]+[.)][ \t\n\r\f\v]")
INDENTED = re.compile(r"^[ \t\n\r\f\v]{2}")
SLASH = re.compile(r"^/([a-z][a-z0-9-]*)(?:[ \t\n\r\f\v]|\Z)")
SEGMENT = re.compile(r"^/([a-z][a-z0-9_-]*)")
ROUTE = re.compile(r'\.route\("/([a-z][a-z0-9_-]*)')
PLACEHOLDER = re.compile(r"[<*?{$\[]|…|\.\.\.")
REPO_LINE = re.compile(r"^[ \t]*TEMPLATE_REPOSITORY:")
SLUG = re.compile(r"[A-Za-z0-9_.-]+/([A-Za-z0-9_.-]+)\Z")

PATH_CLEANUP = (
    (re.compile(r"^[\]\[(\"']+"), ""),
    (re.compile(r"[\])\"',;:.!?]+\Z"), ""),
    (re.compile(r"^[A-Za-z_][A-Za-z0-9_]*="), ""),
    (re.compile(r"#.*\Z", re.S), ""),
    (re.compile(r":[0-9]+(:[0-9]+)?\Z"), ""),
    (re.compile(r"^\./"), ""),
)


class UsageError(Exception):
    """A usage or environment problem: reported on stderr, exit 2."""


def read_lines(path):
    """Lines of a file split on LF only (a CR stays, as in awk)."""
    with open(path, "rb") as handle:
        text = handle.read().decode("utf-8", errors="replace")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def run_git(root, args, stdin=None):
    try:
        return subprocess.run(
            ["git", "-C", root, *args],
            input=stdin,
            capture_output=True,
            check=False,
        )
    except OSError as error:
        raise UsageError(f"git could not run: {error}") from error


def make_files(root):
    files = [os.path.join(root, "Makefile")]
    files += sorted(glob.glob(os.path.join(root, "make", "*.mk")))
    return [path for path in files if os.path.isfile(path)]


def logical_lines(path):
    """Make lines with backslash continuations joined."""
    joined, pending = [], ""
    for line in read_lines(path):
        line = line.rstrip("\r")
        if line.endswith("\\"):
            pending += line[:-1] + " "
            continue
        joined.append(pending + line)
        pending = ""
    if pending:
        joined.append(pending)
    return joined


def load_targets(root):
    """Targets documented with `##`, and the union of the CI_*_TARGETS words."""
    targets, gates = set(), set()
    for path in make_files(root):
        for line in read_lines(path):
            match = TARGET_RULE.match(line)
            if match:
                targets.add(match.group(1))
        for line in logical_lines(path):
            match = CI_VAR.match(line)
            if match:
                words = WS_SPLIT.split(match.group(2).split("#", 1)[0])
                gates.update(w for w in words if re.fullmatch(r"[a-zA-Z0-9_-]+", w))
    return targets, gates


def tracked_files(root):
    if os.path.exists(os.path.join(root, ".git")):
        result = run_git(root, ["ls-files", "-z"])
        if result.returncode != 0:
            raise UsageError(f"git ls-files failed in {root}")
        names = result.stdout.decode("utf-8", errors="replace").split("\0")
        in_git = True
    else:
        names = []
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if not (base == root and d == ".git")]
            for name in files:
                names.append(os.path.relpath(os.path.join(base, name), root))
        in_git = False
    files = sorted(n for n in names if n and os.path.isfile(os.path.join(root, n)))
    return files, in_git


def openapi_segments(root):
    path = os.path.join(root, ".github", "openapi-spec", "spec.yaml")
    found, in_paths = set(), False
    if not os.path.isfile(path):
        return found
    for line in read_lines(path):
        if line.startswith("paths:"):
            in_paths = True
            continue
        if re.match(r"[^ #]", line):
            in_paths = False
        match = re.match(r"  /([a-z][a-z0-9_-]*)", line)
        if in_paths and match:
            found.add(match.group(1))
    return found


def router_routes(root):
    path = os.path.join(root, "crates", "service", "src", "http", "router.rs")
    if not os.path.isfile(path):
        return set()
    return set(ROUTE.findall("\n".join(read_lines(path))))


def workdir_segments(root):
    path = os.path.join(root, "Dockerfile")
    found = set()
    if not os.path.isfile(path):
        return found
    for line in read_lines(path):
        words = line.split()
        if len(words) > 1 and words[0] == "WORKDIR":
            match = SEGMENT.match(words[1])
            if match:
                found.add(match.group(1))
    return found


def accepted_slash_names(root):
    names = {"ping"}
    commands = os.path.join(root, ".claude", "commands")
    if os.path.isdir(commands):
        for entry in os.listdir(commands):
            if entry.endswith(".md") and os.path.isfile(os.path.join(commands, entry)):
                names.add(entry[:-3])
    return names | openapi_segments(root) | router_routes(root) | workdir_segments(root)


def template_repository_names(root):
    names = set()
    for workflow in SYNC_WORKFLOWS:
        path = os.path.join(root, workflow)
        if not os.path.isfile(path):
            continue
        for line in read_lines(path):
            if not REPO_LINE.match(line):
                continue
            value = line.split("TEMPLATE_REPOSITORY:", 1)[1]
            value = re.sub(r"[ \t]+#.*", "", value).strip(WS).strip("\"'")
            match = SLUG.match(value)
            if match:
                names.add(match.group(1))
    return names


def code_spans(line):
    """Inline code spans: a run of n backticks closes at the next run of n."""
    spans, i, size = [], 0, len(line)
    while i < size:
        if line[i] != "`":
            i += 1
            continue
        run = len(line[i:]) - len(line[i:].lstrip("`"))
        j, close = i + run, -1
        while j < size:
            if line[j] != "`":
                j += 1
                continue
            other = len(line[j:]) - len(line[j:].lstrip("`"))
            if other == run:
                close = j
                break
            j += other
        if close < 0:
            i += run
            continue
        spans.append(line[i + run : close])
        i = close + run
    return spans


def clean_path(word):
    for pattern, replacement in PATH_CLEANUP:
        word = pattern.sub(replacement, word)
    return word


class Context:
    """Everything read once from --root."""

    def __init__(self, root):
        self.root = root
        self.targets, self.gates = load_targets(root)
        self.files, self.in_git = tracked_files(root)
        self.tops = {name.split("/", 1)[0] for name in self.files} | set(SPECIALS)
        self.slash_names = accepted_slash_names(root)
        self.repo_names = template_repository_names(root)
        self.findings = set()
        self.slash = set()
        self.paths = set()

    def report(self, rule, rel, number, message):
        self.findings.add((rule, rel, number, message))


class FileScan:
    """Rules 1-4 over the lines of one file (the template's awk program)."""

    def __init__(self, ctx, rel):
        self.ctx, self.rel, self.number = ctx, rel, 0
        self.in_fence, self.fence_char = False, ""
        self.fence_len, self.fence_start, self.fence_gates = 0, 0, set()
        self.in_list, self.list_start, self.list_gates = False, 0, set()
        self.pending, self.exempt = False, False

    def scan(self, lines):
        for number, line in enumerate(lines, 1):
            self.number = number
            self.feed(line)
        if self.in_list:
            self.end_list()

    def feed(self, line):
        if self.fence_marker(line):
            return
        if self.in_fence:
            if not line.strip(WS).startswith("#"):
                self.cite_make(line, "fence")
            return
        self.track_list(line)
        for span in code_spans(line):
            self.handle_span(span.strip(WS))
        if self.rel == "AGENTS.md" and VERIFY_START in line:
            self.exempt = True
        if self.rel == "AGENTS.md" and VERIFY_END in line:
            self.exempt = False

    def fence_marker(self, line):
        text = line.lstrip(WS)
        if not text or text[0] not in "`~":
            return False
        char = text[0]
        run = len(text) - len(text.lstrip(char))
        if run < 3:
            return False
        if not self.in_fence:
            self.in_fence, self.fence_char, self.fence_len = True, char, run
            self.fence_start, self.fence_gates = self.number, set()
            return True
        closes = char == self.fence_char and run >= self.fence_len
        if closes and text[run:].strip(WS) == "":
            self.end_fence()
            return True
        return False

    def end_fence(self):
        self.in_fence = False
        self.gate_finding("a fenced block", self.fence_start, self.fence_gates)
        self.fence_gates = set()

    def track_list(self, line):
        is_item = bool(ITEM.match(line))
        if self.in_list and not is_item:
            if line.strip(WS) == "":
                self.pending = True
            elif self.pending and not INDENTED.match(line):
                self.end_list()
            else:
                self.pending = False
        if is_item:
            if not self.in_list:
                self.in_list, self.list_start = True, self.number
                self.list_gates = set()
            self.pending = False

    def end_list(self):
        self.in_list, self.pending = False, False
        self.gate_finding("a numbered list", self.list_start, self.list_gates)
        self.list_gates = set()

    def gate_finding(self, what, start, gates):
        if len(gates) >= 3 and not self.exempt:
            message = (
                f"{what} cites {len(gates)} gate targets ({', '.join(sorted(gates))}); "
                "link to the verification section of AGENTS.md instead"
            )
            self.ctx.report("4", self.rel, start, message)

    def handle_span(self, span):
        if span == "":
            return
        self.cite_make(span, "span")
        self.cite_slash(span)
        self.cite_paths(span)

    def cite_make(self, text, kind):
        words = WS_SPLIT.split(text)
        for index, word in enumerate(words):
            if word != "make":
                continue
            for target in words[index + 1 :]:
                if target.startswith("-"):
                    continue
                if not TARGET_WORD.match(target):
                    break
                self.cited(target, kind)

    def cited(self, target, kind):
        if target not in self.ctx.targets:
            message = f"make {target} cites a target that the Makefile does not define"
            self.ctx.report("1", self.rel, self.number, message)
        if target in self.ctx.gates:
            if kind == "fence":
                self.fence_gates.add(target)
            elif self.in_list:
                self.list_gates.add(target)

    def cite_slash(self, span):
        match = SLASH.match(span)
        if match and match.group(1) not in self.ctx.slash_names:
            self.ctx.slash.add((match.group(1), self.rel, self.number))

    def cite_paths(self, span):
        for word in WS_SPLIT.split(span):
            path = self.candidate(clean_path(word))
            if path:
                self.ctx.paths.add((path, self.rel, self.number))

    def candidate(self, path):
        if path == "" or "://" in path:
            return ""
        segment = path.split("/", 1)[0]
        if segment not in self.ctx.tops and not re.match(r"bmalph/state(/|\Z)", path):
            return ""
        if segment in SPECIALS and path == segment:
            path += "/"
        match = PLACEHOLDER.search(path)
        if match:
            prefix = path[: match.start()]
            path = prefix if prefix.endswith("/") else re.sub(r"[^/]*\Z", "", prefix)
        return path


def slash_findings(ctx):
    for name, rel, number in ctx.slash:
        message = (
            f"slash command /{name} has no file .claude/commands/{name}.md "
            "and is no route, API path or mount point of the service"
        )
        ctx.report("2", rel, number, message)


def ignored_paths(ctx, missing):
    if not missing or not ctx.in_git:
        return set()
    payload = "\0".join(sorted(missing)).encode("utf-8") + b"\0"
    result = run_git(ctx.root, ["check-ignore", "-z", "--stdin"], stdin=payload)
    return set(result.stdout.decode("utf-8", errors="replace").split("\0")) - {""}


def path_findings(ctx):
    unique = {path for path, _, _ in ctx.paths}
    missing = {p for p in unique if not os.path.exists(os.path.join(ctx.root, p))}
    absent = missing - ignored_paths(ctx, missing)
    for path, rel, number in ctx.paths:
        if path in absent:
            message = f"{path} does not exist and no git-ignore rule matches it"
            ctx.report("3", rel, number, message)


def name_findings(ctx, rel, lines):
    patterns = [
        re.compile(rf"(?<![A-Za-z0-9_-]){re.escape(name)}(?![A-Za-z0-9_-])")
        for name in sorted(ctx.repo_names)
    ]
    for number, line in enumerate(lines, 1):
        if rel in SYNC_WORKFLOWS and REPO_LINE.match(line):
            continue
        if TEMPLATE_NAME in line or any(p.search(line) for p in patterns):
            message = (
                "the template repository name occurs outside the "
                "TEMPLATE_REPOSITORY line of a sync workflow"
            )
            ctx.report("e", rel, number, message)


def relative_name(root, name):
    """FILE as a normalized path relative to --root (an absolute FILE under it)."""
    path = os.path.normpath(os.path.join(root, name))
    rel = os.path.relpath(path, root)
    if rel == os.pardir or rel.startswith(os.pardir + os.sep):
        raise UsageError(f"{name}: not under {root}")
    if not os.path.isfile(path):
        raise UsageError(f"{name}: no such file under {root}")
    return rel.replace(os.sep, "/")


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="docs-rules.py",
        description="Static port of the template's docs-check rules 1-4 and "
        "invariant (e).",
    )
    parser.add_argument("--root", required=True, help="repository root")
    parser.add_argument("files", nargs="+", metavar="FILE", help="relative to --root")
    return parser.parse_args(argv)


def check(root, names):
    if not os.path.isdir(root):
        raise UsageError(f"the root {root} is not a directory")
    ctx = Context(root)
    for name in names:
        rel = relative_name(root, name)
        lines = read_lines(os.path.join(root, rel))
        FileScan(ctx, rel).scan(lines)
        name_findings(ctx, rel, lines)
    slash_findings(ctx)
    path_findings(ctx)
    return sorted(ctx.findings, key=lambda f: (f"({f[0]}) {f[1]}", f[2], f[3]))


def main(argv):
    args = parse_args(argv)
    try:
        findings = check(os.path.abspath(args.root), args.files)
    except UsageError as error:
        print(f"docs-rules: {error}", file=sys.stderr)
        return 2
    for rule, rel, number, message in findings:
        print(f"({rule}) {rel}:{number}: {message}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
