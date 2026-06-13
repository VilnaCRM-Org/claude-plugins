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


def check(plugin_root: pathlib.Path) -> list[Finding]:
    plugin_root = pathlib.Path(plugin_root)
    artifacts = _model.discover(plugin_root)

    commands = _existing_commands(plugin_root)
    agents = _existing_agents(plugin_root)
    skills = _existing_skills(plugin_root)
    schema_tokens = _schema_tokens(plugin_root)

    findings: list[Finding] = []

    def add(check_id: str, rule: str, raw: str, rel: str, needle: str, message: str) -> None:
        findings.append(
            Finding(
                check=check_id,
                rule=rule,
                severity="S2",
                path=rel,
                message=message,
                line=_line_of(raw, needle),
            )
        )

    for art in artifacts:
        raw = art.raw
        rel = art.rel

        # L19 — ${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh resolves on disk.
        for relscript in dict.fromkeys(_SCRIPT_RE.findall(raw)):
            if not (plugin_root / "scripts" / relscript).is_file():
                add(
                    "L19",
                    "references.script.dead",
                    raw,
                    rel,
                    f"scripts/{relscript}",
                    f"dead script reference: ${{CLAUDE_PLUGIN_ROOT}}/scripts/{relscript} "
                    f"does not exist on disk",
                )

        # L20 — ${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md resolves; glob '*' exempt.
        for name in dict.fromkeys(_SKILLPATH_RE.findall(raw)):
            if "*" in name:
                continue
            if not (plugin_root / "skills" / name / "SKILL.md").is_file():
                add(
                    "L20",
                    "references.skill-path.dead",
                    raw,
                    rel,
                    f"skills/{name}/SKILL.md",
                    f"dead skill-path reference: ${{CLAUDE_PLUGIN_ROOT}}/skills/{name}/SKILL.md "
                    f"does not resolve",
                )

        # L21 — relative markdown links to .md files resolve from the linking file's dir.
        for target in dict.fromkeys(_LINK_RE.findall(raw)):
            t = target.strip()
            if not t or t.startswith("#"):
                continue
            if re.match(r"^[a-z][a-z0-9+.-]*://", t) or t.startswith("mailto:"):
                continue
            # strip anchor / query suffix before resolving.
            cleaned = t.split("#", 1)[0].split("?", 1)[0].strip()
            if not cleaned.endswith(".md"):
                continue
            if cleaned.startswith("/"):
                continue  # absolute path — not a relative link
            # relative: ../ , ./ , or a bare filename/subpath.
            resolved = (art.path.parent / cleaned).resolve()
            if not resolved.is_file():
                add(
                    "L21",
                    "references.link.dead",
                    raw,
                    rel,
                    f"]({target})",
                    f"dead relative link: {t} does not resolve from {art.path.parent.name}/",
                )

        # L22 — /sdlc-* command token maps to commands/<token>.md (longest match).
        for tok in dict.fromkeys(_COMMAND_RE.findall(raw)):
            if tok not in commands:
                add(
                    "L22",
                    "references.command.dead",
                    raw,
                    rel,
                    f"/{tok}",
                    f"dead command reference: /{tok} has no commands/{tok}.md",
                )

        # L23 — backticked token called an agent/subagent must have agents/<name>.md.
        for m1, m2 in _AGENT_RE.findall(raw):
            name = m1 or m2
            if name and name not in agents:
                add(
                    "L23",
                    "references.agent.dead",
                    raw,
                    rel,
                    f"`{name}`",
                    f"dead agent reference: `{name}` is called an agent but has no "
                    f"agents/{name}.md",
                )

        # L24 — "<name> skill" prose that is a typo of a real skill name.
        for name in dict.fromkeys(_SKILL_PROSE_RE.findall(raw)):
            if name in skills:
                continue
            # Conservative: only flag a near-typo of an existing skill (edit distance 1–2),
            # so generic compound phrases ("planning-time skill") are not false-flagged.
            nearest = min((_levenshtein(name, s) for s in skills), default=99)
            if 0 < nearest <= 2:
                add(
                    "L24",
                    "references.skill.dead",
                    raw,
                    rel,
                    f"{name} skill",
                    f"dead skill reference: '{name} skill' has no skills/{name}/ directory "
                    f"(likely typo)",
                )

        # L25 — backticked dotted profile key declared in profile-schema.md.
        for tok in dict.fromkeys(_BACKTICK_RE.findall(raw)):
            if not _PROFILE_RE.match(tok):
                continue
            if tok.endswith(".*"):
                continue  # wildcard form exempt
            if _FILE_EXT_RE.search(tok):
                continue  # filename (e.g. architecture.md), not a profile key
            if tok in schema_tokens:
                continue
            add(
                "L25",
                "references.profile-key.unknown",
                raw,
                rel,
                f"`{tok}`",
                f"unknown profile key: `{tok}` is not declared in docs/profile-schema.md",
            )

    return findings
