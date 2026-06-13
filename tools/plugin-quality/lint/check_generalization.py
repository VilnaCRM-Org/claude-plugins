"""Generalization-audit contract checks (L28-L29) for a plugin tree.

Faithful Python port of the ``generalization-audit`` job in
``.github/workflows/ci.yml``:

* L28 ``generalization.denylist`` (S1) — a case-insensitive denylist regex run
  over the four PRD component dirs (``skills``/``commands``/``agents``/``scripts``)
  for a fixed set of extensions. Before matching, fenced code blocks whose
  opening fence line carries the ``# profile-example`` marker are stripped (they
  may legitimately cite a concrete profile's ``user-service`` values). This
  mirrors the shell ``strip_profile_examples`` awk filter.
* L29 ``generalization.tree-hygiene`` (S1) — no entry literally named ``_bmad``
  or ``.ralph`` (directory OR file) anywhere under the plugin tree (NFR-7 /
  ADR-10). A ``_bmad`` *substring* inside another name is not a violation; the
  exact path component must match.

README/docs are intentionally out of scope for the denylist: install
instructions and release URLs may carry the marketplace org name.
"""

import pathlib
import re

from _common import Finding
import _model

# L28: NFR-2 denylist (case-insensitive). ``user[-_ ]service`` also covers the
# workspace.dsl container name "User Service"; ``mongo<word>repository`` catches
# concrete ODM repository class names; the rest are profile-specific paths/org.
DENY_RE = re.compile(
    r"user[-_ ]service"
    r"|mongo[a-z][a-z0-9_]*repository"
    r"|apprunner"
    r"|src/user"
    r"|src/oauth"
    r"|vilnacrm",
    re.IGNORECASE,
)

# Scope of the denylist scan: the PRD's four component dirs.
SCOPED_DIRS = ("skills", "commands", "agents", "scripts")

# Extensions the denylist scan considers.
SCANNED_SUFFIXES = {".md", ".sh", ".json", ".yml", ".yaml", ".bats"}

# A backtick code-fence opening/closing line (any indent, any info string).
# Restricted to backtick fences ONLY to match ci.yml's awk strip_profile_examples
# (its /^[[:space:]]*```/ rule), so this gate is never more lenient than CI: a
# '~~~ # profile-example' block is NOT stripped here, exactly as in CI.
_FENCE_RE = re.compile(r"^[ \t]*```")

# L29: exact path-component names that must not appear anywhere in the tree.
STRAY_NAMES = ("_bmad", ".ralph")


def _strip_profile_examples(text: str) -> list[str | None]:
    """Port of the awk ``strip_profile_examples`` filter.

    Returns a list aligned 1:1 with the original lines (so reported line numbers
    stay accurate); stripped lines are represented as ``None`` and the opening /
    closing fence lines of a stripped block are themselves dropped — exactly as
    the awk ``next`` branches drop them.
    """
    out: list[str | None] = []
    skip = False
    for line in text.splitlines():
        if _FENCE_RE.match(line):
            if skip:
                # closing fence of a skipped block: drop it, stop skipping
                skip = False
                out.append(None)
                continue
            if "# profile-example" in line:
                # opening fence carrying the marker: drop it, start skipping
                skip = True
                out.append(None)
                continue
            out.append(line)
            continue
        if skip:
            out.append(None)
            continue
        out.append(line)
    return out


def _read_text(path: pathlib.Path) -> str | None:
    """Read a scanned file's text, matching CI's raw-byte grep.

    ci.yml greps the raw bytes, so a denylisted token in a non-UTF-8 file is
    still a CI failure. We decode with ``errors="replace"`` (utf-8-sig first to
    strip a BOM) so the denylist still scans the content instead of skipping
    the file — keeping this gate in lockstep with CI rather than more lenient.
    """
    try:
        data = path.read_bytes()
    except OSError:
        return None
    return data.decode("utf-8-sig", errors="replace")


def _scoped_files(plugin_root: pathlib.Path):
    """Yield every scanned file under the scoped component dirs, in CI order."""
    for sub in SCOPED_DIRS:
        base = plugin_root / sub
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.suffix in SCANNED_SUFFIXES:
                yield path


def _denylist_finding(path: pathlib.Path, lineno: int, token: str, rel) -> Finding:
    """Build the single L28 finding for a denylisted token hit on one line."""
    return Finding(
        check="L28",
        rule="generalization.denylist",
        severity="S1",
        path=rel(path),
        line=lineno,
        message=(
            "denylisted identifier "
            f"{token!r} (NFR-2); generalize or fence the "
            "example with '# profile-example'"
        ),
    )


def _scan_file_denylist(path: pathlib.Path, rel) -> list[Finding]:
    """L28 hits in one file: strip profile-example fences, then match each line."""
    text = _read_text(path)
    if text is None:
        return []
    findings: list[Finding] = []
    for lineno, line in enumerate(_strip_profile_examples(text), start=1):
        if line is None:
            continue
        m = DENY_RE.search(line)
        if m:
            findings.append(_denylist_finding(path, lineno, m.group(0), rel))
    return findings


def _scan_denylist(plugin_root: pathlib.Path, rel) -> list[Finding]:
    """L28: denylist scan over the scoped component dirs."""
    findings: list[Finding] = []
    for path in _scoped_files(plugin_root):
        findings.extend(_scan_file_denylist(path, rel))
    return findings


def _scan_tree_hygiene(plugin_root: pathlib.Path, rel) -> list[Finding]:
    """L29: no _bmad/.ralph path component anywhere in the tree."""
    findings: list[Finding] = []
    if not plugin_root.is_dir():
        return findings
    for path in sorted(plugin_root.rglob("*")):
        if path.name in STRAY_NAMES:
            findings.append(
                Finding(
                    check="L29",
                    rule="generalization.tree-hygiene",
                    severity="S1",
                    path=rel(path),
                    message=(
                        f"vendored asset {path.name!r} must not live inside the "
                        "plugin tree (NFR-7)"
                    ),
                )
            )
    return findings


def check(plugin_root: pathlib.Path) -> list[Finding]:
    plugin_root = pathlib.Path(plugin_root)
    repo_root = plugin_root.parent.parent

    def rel(p: pathlib.Path) -> str:
        try:
            return str(p.relative_to(repo_root))
        except ValueError:
            return str(p)

    return _scan_denylist(plugin_root, rel) + _scan_tree_hygiene(plugin_root, rel)
