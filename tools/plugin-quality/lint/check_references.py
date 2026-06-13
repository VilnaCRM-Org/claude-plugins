"""Dead-reference checker (Tier-1 static lint, matrix rows L19–L25).

Scans every discovered plugin artifact's raw text for cross-references and
flags the ones that do not resolve on disk:

* L19 ``references.script.dead``      ``${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh``
* L20 ``references.skill-path.dead``  ``${CLAUDE_PLUGIN_ROOT}/skills/<x>/SKILL.md``
* L21 ``references.link.dead``        relative markdown ``](...md)`` links
* L22 ``references.command.dead``     ``/sdlc-*`` command tokens (longest match)
* L23 ``references.agent.dead``       backticked name called an ``agent``/``subagent``
* L24 ``references.skill.dead``       ``<name> skill`` prose (typo of a real skill)
* L25 ``references.profile-key.unknown`` backticked dotted profile keys

Every finding is severity ``S2``. The checker is deliberately conservative: on
the known-clean plugin it returns no findings. Line numbers are best-effort,
recovered from ``raw.splitlines()``.
"""

from __future__ import annotations

import dataclasses
import pathlib
import re

from _common import Finding
import _model

CHECK = "L25"  # matrix band L19–L25; per-rule check id set on each Finding

# ${CLAUDE_PLUGIN_ROOT}/scripts/<path>.sh — path may include subdirs (lib/common.sh).
_SCRIPT_RE = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}/scripts/([A-Za-z0-9_./-]+\.sh)")
# ${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md ; literal-asterisk glob form is exempt.
_SKILLPATH_RE = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}/skills/([A-Za-z0-9_*-]+)/SKILL\.md")
# markdown link target: ](<path>)
_LINK_RE = re.compile(r"\]\(([^)]+)\)")
# optional Markdown link title suffix: ` "Title"`, ` 'Title'`, or ` (Title)`.
# Stripped before path resolution so a dead link carrying a title is still
# caught (otherwise the title text fuses into the path and the .md tail is lost).
_LINK_TITLE_RE = re.compile(r"""\s+(?:"[^"]*"|'[^']*'|\([^)]*\))\s*$""")
# /sdlc-style command token in prose.
_COMMAND_RE = re.compile(r"(?<![A-Za-z0-9_/])/(sdlc[a-z0-9-]*)")
# backticked token explicitly called an agent/subagent (either order). The
# inner hyphen group is OPTIONAL so single-token names ('reviewer') are caught
# too; the existing-name set + edit-distance guards keep the clean plugin quiet.
_AGENT_RE = re.compile(
    r"`([a-z0-9]+(?:-[a-z0-9]+)*)`\s+(?:agent|subagent)\b"
    r"|\b(?:agent|subagent)\s+`([a-z0-9]+(?:-[a-z0-9]+)*)`"
)
# "<name> skill" prose form: kebab-case, one or more words.
_SKILL_PROSE_RE = re.compile(r"\b([a-z0-9]+(?:-[a-z0-9]+)*)\s+skill\b")
# backticked dotted profile-key candidate.
_PROFILE_PREFIX = r"(?:make|quality|capabilities|framework|persistence|architecture|ci|project)"
_PROFILE_RE = re.compile(r"^" + _PROFILE_PREFIX + r"\.[a-z0-9_.<>*-]+$")
# any backticked token (used for the agent/skill negative-set guards).
_BACKTICK_RE = re.compile(r"`([^`]+)`")
# extensions that mark a backticked dotted token as a filename, not a profile key.
_FILE_EXT_RE = re.compile(r"\.(md|sh|ya?ml|json|php|txt|xml|dist|lock|neon)$")


def _line_of(raw: str, needle: str) -> int | None:
    """Best-effort 1-based line of the first raw line containing ``needle``."""
    for i, line in enumerate(raw.splitlines(), start=1):
        if needle in line:
            return i
    return None


def _levenshtein(a: str, b: str) -> int:
    m, n = len(a), len(b)
    prev = list(range(n + 1))
    for i in range(1, m + 1):
        cur = [i] + [0] * n
        for j in range(1, n + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
        prev = cur
    return prev[n]


def _existing_commands(plugin_root: pathlib.Path) -> set[str]:
    cmd_dir = plugin_root / "commands"
    if not cmd_dir.is_dir():
        return set()
    return {p.stem for p in cmd_dir.glob("*.md")}


def _existing_agents(plugin_root: pathlib.Path) -> set[str]:
    agent_dir = plugin_root / "agents"
    if not agent_dir.is_dir():
        return set()
    return {p.stem for p in agent_dir.glob("*.md")}


def _existing_skills(plugin_root: pathlib.Path) -> set[str]:
    skills_dir = plugin_root / "skills"
    if not skills_dir.is_dir():
        return set()
    return {p.name for p in skills_dir.iterdir() if p.is_dir()}


def _schema_tokens(plugin_root: pathlib.Path) -> set[str]:
    """Backticked tokens declared in docs/profile-schema.md."""
    schema = plugin_root / "docs" / "profile-schema.md"
    if not schema.is_file():
        return set()
    # utf-8-sig so a BOM on the schema file does not corrupt its first token.
    return set(_BACKTICK_RE.findall(schema.read_text(encoding="utf-8-sig")))


@dataclasses.dataclass
class _Ctx:
    """Per-plugin shared state for the reference rules.

    Bundling the discovered name sets and the running ``findings`` list here
    lets each rule helper take just ``(ctx, art)`` and lets ``add`` close over
    the list with three call-site args instead of six.
    """

    plugin_root: pathlib.Path
    commands: set[str]
    agents: set[str]
    skills: set[str]
    schema_tokens: set[str]
    findings: list[Finding] = dataclasses.field(default_factory=list)

    def add(self, check_id: str, rule: str, art, needle: str, message: str) -> None:
        self.findings.append(
            Finding(
                check=check_id,
                rule=rule,
                severity="S2",
                path=art.rel,
                message=message,
                line=_line_of(art.raw, needle),
            )
        )


def _link_path(target: str) -> str | None:
    """Resolve a markdown link target to a relative ``.md`` path, or None.

    Strips an optional Markdown title suffix (``"t"`` / ``'t'`` / ``(t)``) and
    any anchor/query, then returns the cleaned path only when it is a relative
    ``.md`` link worth resolving (external URLs, anchors, and absolute paths
    return None).
    """
    t = target.strip()
    if not t or t.startswith("#"):
        return None
    if re.match(r"^[a-z][a-z0-9+.-]*://", t) or t.startswith("mailto:"):
        return None
    # Drop an optional Markdown link title before touching the path.
    t = _LINK_TITLE_RE.sub("", t).strip()
    cleaned = t.split("#", 1)[0].split("?", 1)[0].strip()
    if not cleaned.endswith(".md") or cleaned.startswith("/"):
        return None
    return cleaned


def _rule_script(ctx: _Ctx, art) -> None:
    """L19 — ${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh resolves on disk."""
    for relscript in dict.fromkeys(_SCRIPT_RE.findall(art.raw)):
        if not (ctx.plugin_root / "scripts" / relscript).is_file():
            ctx.add(
                "L19", "references.script.dead", art,
                f"scripts/{relscript}",
                f"dead script reference: ${{CLAUDE_PLUGIN_ROOT}}/scripts/{relscript} "
                f"does not exist on disk",
            )


def _rule_skill_path(ctx: _Ctx, art) -> None:
    """L20 — ${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md resolves; glob '*' exempt."""
    for name in dict.fromkeys(_SKILLPATH_RE.findall(art.raw)):
        if "*" in name:
            continue
        if not (ctx.plugin_root / "skills" / name / "SKILL.md").is_file():
            ctx.add(
                "L20", "references.skill-path.dead", art,
                f"skills/{name}/SKILL.md",
                f"dead skill-path reference: ${{CLAUDE_PLUGIN_ROOT}}/skills/{name}/SKILL.md "
                f"does not resolve",
            )


def _rule_link(ctx: _Ctx, art) -> None:
    """L21 — relative markdown links to .md files resolve from the linking file's dir."""
    for target in dict.fromkeys(_LINK_RE.findall(art.raw)):
        cleaned = _link_path(target)
        if cleaned is None:
            continue
        if not (art.path.parent / cleaned).resolve().is_file():
            ctx.add(
                "L21", "references.link.dead", art,
                f"]({target})",
                f"dead relative link: {cleaned} does not resolve from {art.path.parent.name}/",
            )


def _rule_command(ctx: _Ctx, art) -> None:
    """L22 — /sdlc-* command token maps to commands/<token>.md (longest match)."""
    for tok in dict.fromkeys(_COMMAND_RE.findall(art.raw)):
        if tok not in ctx.commands:
            ctx.add(
                "L22", "references.command.dead", art,
                f"/{tok}",
                f"dead command reference: /{tok} has no commands/{tok}.md",
            )


def _rule_agent(ctx: _Ctx, art) -> None:
    """L23 — backticked token called an agent/subagent must have agents/<name>.md."""
    for m1, m2 in _AGENT_RE.findall(art.raw):
        name = m1 or m2
        if name and name not in ctx.agents:
            ctx.add(
                "L23", "references.agent.dead", art,
                f"`{name}`",
                f"dead agent reference: `{name}` is called an agent but has no "
                f"agents/{name}.md",
            )


def _rule_skill_prose(ctx: _Ctx, art) -> None:
    """L24 — "<name> skill" prose that is a near-typo of a real skill name."""
    for name in dict.fromkeys(_SKILL_PROSE_RE.findall(art.raw)):
        if name in ctx.skills:
            continue
        # Conservative: only flag a near-typo of an existing skill (edit distance 1–2),
        # so generic compound phrases ("planning-time skill") are not false-flagged.
        nearest = min((_levenshtein(name, s) for s in ctx.skills), default=99)
        if 0 < nearest <= 2:
            ctx.add(
                "L24", "references.skill.dead", art,
                f"{name} skill",
                f"dead skill reference: '{name} skill' has no skills/{name}/ directory "
                f"(likely typo)",
            )


def _rule_profile_key(ctx: _Ctx, art) -> None:
    """L25 — backticked dotted profile key declared in profile-schema.md."""
    for tok in dict.fromkeys(_BACKTICK_RE.findall(art.raw)):
        if not _PROFILE_RE.match(tok):
            continue
        if tok.endswith(".*"):
            continue  # wildcard form exempt
        if _FILE_EXT_RE.search(tok):
            continue  # filename (e.g. architecture.md), not a profile key
        if tok in ctx.schema_tokens:
            continue
        ctx.add(
            "L25", "references.profile-key.unknown", art,
            f"`{tok}`",
            f"unknown profile key: `{tok}` is not declared in docs/profile-schema.md",
        )


_RULES = (
    _rule_script,
    _rule_skill_path,
    _rule_link,
    _rule_command,
    _rule_agent,
    _rule_skill_prose,
    _rule_profile_key,
)


def check(plugin_root: pathlib.Path) -> list[Finding]:
    plugin_root = pathlib.Path(plugin_root)
    ctx = _Ctx(
        plugin_root=plugin_root,
        commands=_existing_commands(plugin_root),
        agents=_existing_agents(plugin_root),
        skills=_existing_skills(plugin_root),
        schema_tokens=_schema_tokens(plugin_root),
    )
    for art in _model.discover(plugin_root):
        for rule in _RULES:
            rule(ctx, art)
    return ctx.findings
