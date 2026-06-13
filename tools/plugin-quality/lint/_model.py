"""Plugin artifact discovery and parsing.

A Claude Code plugin ships four kinds of prompt artifact under its root:

* ``commands/*.md``            -> kind ``command``
* ``agents/*.md``              -> kind ``agent``
* ``skills/<name>/SKILL.md``   -> kind ``skill``
* ``skills/*.md`` (loose)      -> kind ``meta-guide`` (ADR-11: no frontmatter)

This module turns each file into an :class:`Artifact` with its parsed
frontmatter, body, H1, and the list of H2 section titles. Heading and fence
scanning is fence-aware: ``##`` lines inside ```` ``` ```` code fences are not
treated as section headers, and ``---`` inside the body is not mistaken for a
frontmatter terminator.
"""

from __future__ import annotations

import dataclasses
import pathlib
import re

import yaml

FENCE_RE = re.compile(r"^\s*(```+|~~~+)")
# ATX headings: strip an optional run of trailing '#' (CommonMark closing
# sequence), e.g. "## Inputs ##" -> "Inputs".
H1_RE = re.compile(r"^#\s+(.*?)\s*#*\s*$")
H2_RE = re.compile(r"^##\s+(.*?)\s*#*\s*$")
# Setext underlines: a line of all '=' (H1) or all '-' (H2), len>=1/>=2.
_SETEXT_H1_RE = re.compile(r"^=+\s*$")
_SETEXT_H2_RE = re.compile(r"^-{2,}\s*$")


@dataclasses.dataclass
class Artifact:
    path: pathlib.Path
    plugin_root: pathlib.Path
    kind: str  # command | agent | skill | meta-guide
    raw: str
    has_frontmatter: bool
    frontmatter: dict
    frontmatter_error: str | None
    body: str
    h1: str | None
    h2_sections: list[str]

    @property
    def rel(self) -> str:
        """Path relative to the repo root if possible, else absolute."""
        try:
            return str(self.path.relative_to(_repo_root(self.plugin_root)))
        except ValueError:
            return str(self.path)

    @property
    def name(self) -> str:
        """Frontmatter ``name`` if present, else the file/dir stem.

        For skills the identity is the parent directory name; for commands and
        agents it is the filename stem.
        """
        fm_name = self.frontmatter.get("name")
        if isinstance(fm_name, str) and fm_name.strip():
            return fm_name.strip()
        if self.kind == "skill":
            return self.path.parent.name
        return self.path.stem


def _repo_root(plugin_root: pathlib.Path) -> pathlib.Path:
    # plugin_root is <repo>/plugins/<name>; repo root is two levels up.
    return plugin_root.parent.parent


def split_frontmatter(text: str) -> tuple[bool, dict, str | None, str]:
    """Return ``(has_fm, data, error, body)``.

    Frontmatter is a leading ``---`` line, YAML, then a closing ``---`` line.
    ``error`` is non-None when a frontmatter block exists but fails to parse.
    """
    lines = text.splitlines(keepends=True)
    # Strip the carriage return too (not just "\n") so a CRLF file's "---\r\n"
    # delimiter is still recognised; otherwise a trailing "\r" would make valid
    # frontmatter silently parse as absent.
    if not lines or lines[0].rstrip("\r\n") != "---":
        return False, {}, None, text
    for idx in range(1, len(lines)):
        if lines[idx].rstrip("\r\n") == "---":
            fm_text = "".join(lines[1:idx])
            body = "".join(lines[idx + 1 :])
            try:
                data = yaml.safe_load(fm_text)
            except yaml.YAMLError as exc:  # malformed frontmatter is itself a finding
                return True, {}, f"YAML parse error: {exc}", body
            if data is None:
                data = {}
            if not isinstance(data, dict):
                return True, {}, "frontmatter is not a mapping", body
            return True, data, None, body
    # opened but never closed
    return True, {}, "frontmatter block not terminated by closing '---'", ""


def iter_body_lines(body: str):
    """Yield ``(lineno, text, in_fence)`` for body lines, tracking code fences.

    ``lineno`` is 1-based within ``body``. ``in_fence`` is True for lines inside
    a fenced code block (including the closing fence line is reported as inside).
    """
    in_fence = False
    fence_marker = ""
    fence_len = 0
    for i, line in enumerate(body.splitlines(), start=1):
        m = FENCE_RE.match(line)
        if m:
            run = m.group(1)
            marker = run[0]  # ` or ~
            if not in_fence:
                in_fence = True
                fence_marker = marker
                fence_len = len(run)
                yield i, line, True
                continue
            # CommonMark: a closing fence must be the same char, at least as
            # long as the opening fence, AND carry no info string — only the
            # fence run plus optional trailing whitespace. A shorter inner fence
            # (e.g. ``` inside a ```` block) does not close it, and neither does
            # a line like "```bash" whose info text marks it as an opening fence.
            after = line[m.end() :]
            if marker == fence_marker and len(run) >= fence_len and not after.strip():
                in_fence = False
                fence_marker = ""
                fence_len = 0
                yield i, line, True
                continue
        yield i, line, in_fence


def _atx_heading(line: str) -> tuple[int, str] | None:
    """Return ``(level, title)`` for an ATX H1/H2 line, else None."""
    m1 = H1_RE.match(line)
    if m1:
        return 1, m1.group(1).strip()
    m2 = H2_RE.match(line)
    if m2:
        return 2, m2.group(1).strip()
    return None


def _setext_level(line: str) -> int | None:
    """Return 1 for a setext H1 underline, 2 for a setext H2 underline, else None."""
    if _SETEXT_H1_RE.match(line):
        return 1
    if _SETEXT_H2_RE.match(line):
        return 2
    return None


@dataclasses.dataclass
class _Headings:
    """Accumulator for :func:`extract_headings` (first H1, all H2s)."""

    h1: str | None = None
    h2: list[str] = dataclasses.field(default_factory=list)

    def add_h1(self, title: str) -> None:
        if self.h1 is None:  # only the FIRST H1 is ever captured
            self.h1 = title

    def add_h2(self, title: str) -> None:
        self.h2.append(title)


def _apply_atx(line: str, acc: _Headings) -> bool:
    """Consume an ATX heading line into ``acc``; return True if it was a heading.

    An H2 is always recorded. The first H1 is recorded; a *later* H1 is reported
    as "not consumed" (returns False) so the caller keeps it as the preceding
    text line for a following setext underline — preserving original behaviour.
    """
    atx = _atx_heading(line)
    if atx is None:
        return False
    level, title = atx
    if level == 2:
        acc.add_h2(title)
        return True
    if acc.h1 is None:
        acc.add_h1(title)
        return True
    return False  # a later H1: fall through to act as setext-prelude text


def _apply_setext(line: str, prev_text: str | None, acc: _Headings) -> bool:
    """Consume a setext underline against ``prev_text``; return True if consumed.

    The underline counts only when ``prev_text`` is a non-blank paragraph line
    (the heading text). ``---`` here is a real setext-H2/HR underline — never
    frontmatter, which the body has already had split off.
    """
    if prev_text is None or not prev_text.strip():
        return False
    level = _setext_level(line)
    if level == 1:
        acc.add_h1(prev_text.strip())
        return True
    if level == 2:
        acc.add_h2(prev_text.strip())
        return True
    return False


def extract_headings(body: str) -> tuple[str | None, list[str]]:
    acc = _Headings()
    prev_text: str | None = None  # last non-blank, non-fenced, non-ATX line
    for _lineno, line, in_fence in iter_body_lines(body):
        if in_fence:
            prev_text = None
            continue
        if _apply_atx(line, acc) or _apply_setext(line, prev_text, acc):
            prev_text = None
            continue
        prev_text = line if line.strip() else None
    return acc.h1, acc.h2


def _make(path: pathlib.Path, plugin_root: pathlib.Path, kind: str) -> Artifact:
    try:
        # utf-8-sig strips a leading BOM so a BOM'd file is not mis-parsed as
        # having no frontmatter (its first line would otherwise be '﻿---').
        raw = path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError) as exc:
        # An unreadable / non-UTF-8 file becomes a stub whose frontmatter_error
        # surfaces via check_frontmatter's existing parse-error finding, instead
        # of letting the exception escape discover().
        return Artifact(
            path=path,
            plugin_root=plugin_root,
            kind=kind,
            raw="",
            has_frontmatter=False,
            frontmatter={},
            frontmatter_error=f"could not read file as UTF-8 ({exc})",
            body="",
            h1=None,
            h2_sections=[],
        )
    has_fm, data, err, body = split_frontmatter(raw)
    h1, h2 = extract_headings(body)
    return Artifact(
        path=path,
        plugin_root=plugin_root,
        kind=kind,
        raw=raw,
        has_frontmatter=has_fm,
        frontmatter=data,
        frontmatter_error=err,
        body=body,
        h1=h1,
        h2_sections=h2,
    )


def discover(plugin_root: pathlib.Path) -> list[Artifact]:
    """Find every prompt artifact under one plugin root."""
    plugin_root = pathlib.Path(plugin_root)
    out: list[Artifact] = []

    cmd_dir = plugin_root / "commands"
    if cmd_dir.is_dir():
        for p in sorted(cmd_dir.glob("*.md")):
            out.append(_make(p, plugin_root, "command"))

    agent_dir = plugin_root / "agents"
    if agent_dir.is_dir():
        for p in sorted(agent_dir.glob("*.md")):
            out.append(_make(p, plugin_root, "agent"))

    skills_dir = plugin_root / "skills"
    if skills_dir.is_dir():
        for p in sorted(skills_dir.glob("*/SKILL.md")):
            out.append(_make(p, plugin_root, "skill"))
        # Loose .md directly under skills/ are meta-guides (ADR-11).
        for p in sorted(skills_dir.glob("*.md")):
            out.append(_make(p, plugin_root, "meta-guide"))

    return out


def find_plugin_roots(repo_root: pathlib.Path) -> list[pathlib.Path]:
    """Every ``plugins/<name>/`` that carries a plugin manifest."""
    repo_root = pathlib.Path(repo_root)
    roots: list[pathlib.Path] = []
    plugins_dir = repo_root / "plugins"
    if not plugins_dir.is_dir():
        return roots
    for child in sorted(plugins_dir.iterdir()):
        if (child / ".claude-plugin" / "plugin.json").is_file():
            roots.append(child)
    return roots


def by_kind(artifacts: list[Artifact], kind: str) -> list[Artifact]:
    return [a for a in artifacts if a.kind == kind]


# --- Shared H2 section slicing (ATX + setext) -------------------------------
# Factored here so the escalation and structure checks share one implementation
# instead of duplicating the setext-aware slicing logic.
_SECT_ATX_H2_RE = re.compile(r"^##\s+(.*?)\s*#*\s*$")
_SECT_ATX_H1_RE = re.compile(r"^#\s+")
_SECT_SETEXT_H2_RE = re.compile(r"^-{2,}\s*$")


def h2_title_at(idx: int, lines: list[tuple[str, bool]]) -> str | None:
    """Return the H2 title that BEGINS at stream index ``idx`` (else None).

    Recognises both ATX (``## X``) and setext (``X`` then ``----``) H2 forms,
    consistent with :func:`extract_headings`. ``lines`` is the ``(text,
    in_fence)`` stream from :func:`iter_body_lines`. An ATX H1/H2 line preceding
    a ``---`` underline is its own heading (the ``---`` is a horizontal rule),
    never a setext title.
    """
    text, in_fence = lines[idx]
    if in_fence:
        return None
    m = _SECT_ATX_H2_RE.match(text)
    if m:
        return m.group(1).strip()
    if _SECT_SETEXT_H2_RE.match(text) and idx > 0:
        prev_text, prev_fenced = lines[idx - 1]
        if (
            not prev_fenced
            and prev_text.strip()
            and not _SECT_ATX_H2_RE.match(prev_text)
            and not _SECT_ATX_H1_RE.match(prev_text)
        ):
            return prev_text.strip()
    return None


def section_text(body: str, heading: str) -> str | None:
    """Return the fence-aware body text of the H2 ``heading`` (ATX or setext).

    Slices from the line after the heading up to (not including) the next
    non-fenced H2. Headings inside code fences are ignored. Returns None when the
    heading is absent.
    """
    lines = [(text, in_fence) for _lineno, text, in_fence in iter_body_lines(body)]
    start = None
    out: list[str] = []
    for idx in range(len(lines)):
        title = h2_title_at(idx, lines)
        if start is None:
            if title == heading:
                start = idx + 1
            continue
        if title is not None:
            # A setext boundary's underline follows its title line, already
            # appended; drop that trailing title line from the section.
            if _SECT_SETEXT_H2_RE.match(lines[idx][0]) and out:
                out.pop()
            break
        out.append(lines[idx][0])
    if start is None:
        return None
    return "\n".join(out)
