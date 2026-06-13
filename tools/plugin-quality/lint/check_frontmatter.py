"""Frontmatter contract checks (L1-L5) for plugin prompt artifacts.

Validates the YAML frontmatter shape of every artifact a plugin ships:

* commands  -> ``description`` + ``argument-hint``; ``allowed-tools`` shape (L1, L2)
* agents    -> ``name`` + ``description`` + ``tools`` + ``model`` (L3)
* skills    -> ``name`` + ``description``, never ``tools``/``model`` (L4)
* meta-guides -> no frontmatter at all (ADR-11) (L5)

Any artifact whose frontmatter block fails to parse yields a single
``frontmatter.parse-error`` finding so the malformed file is surfaced rather
than silently skipped.
"""

import pathlib

from _common import Finding
import _model

# Tools accepted in a command's ``allowed-tools`` array (L2).
KNOWN_TOOLS = {"Bash", "Read", "Write", "Edit", "Glob", "Grep", "Task", "WebFetch", "WebSearch"}

# Case-insensitive signals that mark a command as report-only (L2): such a
# command must not be allowed to mutate the tree (no Write/Edit).
REPORT_ONLY_SIGNALS = ("report only", "never fix", "read-only", "no self-fix", "does not edit")

# Tools that mutate the working tree; forbidden for report-only commands (L2).
MUTATING_TOOLS = {"Write", "Edit"}


def _nonempty_str(value) -> bool:
    """True when ``value`` is a string with non-whitespace content."""
    return isinstance(value, str) and value.strip() != ""


def _present_tools(value) -> bool:
    """Agent ``tools`` (L3) is present in either YAML-list or comma-string shape.

    A list satisfies the contract only when at least one element is a non-empty
    string: a malformed list like ``[123]`` or ``[null]`` (no usable tool name)
    must NOT count as a present ``tools`` list, so L3 still flags it.
    """
    if isinstance(value, list):
        return any(_nonempty_str(item) for item in value)
    return _nonempty_str(value)


def _is_report_only(body: str) -> bool:
    lowered = body.lower()
    return any(signal in lowered for signal in REPORT_ONLY_SIGNALS)


def _parse_error_finding(art) -> Finding:
    """L0: surface an artifact whose frontmatter block failed to parse."""
    return Finding(
        check="L0",
        rule="frontmatter.parse-error",
        severity="S2",
        path=art.rel,
        message=f"frontmatter failed to parse: {art.frontmatter_error}",
    )


def _check_command(art) -> list[Finding]:
    """L1 + L2: command required keys and allowed-tools shape."""
    findings: list[Finding] = []
    fm = art.frontmatter

    # L1: required keys.
    for key in ("description", "argument-hint"):
        if not _nonempty_str(fm.get(key)):
            findings.append(
                Finding(
                    check="L1",
                    rule="frontmatter.command.missing-key",
                    severity="S2",
                    path=art.rel,
                    message=f"command missing frontmatter key {key}",
                )
            )

    # L2: allowed-tools shape (only when declared).
    findings.extend(_check_allowed_tools(art))
    return findings


def _check_allowed_tools(art) -> list[Finding]:
    """L2: allowed-tools array shape, unknown-tool, and report-only rules."""
    fm = art.frontmatter
    if "allowed-tools" not in fm:
        return []

    tools = fm.get("allowed-tools")
    if not isinstance(tools, list):
        return [
            Finding(
                check="L2",
                rule="frontmatter.command.allowed-tools",
                severity="S2",
                path=art.rel,
                message="allowed-tools must be a JSON array of known tools",
            )
        ]

    findings: list[Finding] = []
    unknown = [t for t in tools if t not in KNOWN_TOOLS]
    if unknown:
        findings.append(
            Finding(
                check="L2",
                rule="frontmatter.command.allowed-tools",
                severity="S2",
                path=art.rel,
                message=f"allowed-tools contains unknown tools: {', '.join(map(str, unknown))}",
            )
        )

    if _is_report_only(art.body):
        mutating = [t for t in tools if t in MUTATING_TOOLS]
        if mutating:
            findings.append(
                Finding(
                    check="L2",
                    rule="frontmatter.command.allowed-tools",
                    severity="S2",
                    path=art.rel,
                    message=(
                        "report-only command must not allow mutating tools: "
                        f"{', '.join(mutating)}"
                    ),
                )
            )
    return findings


def _check_agent(art) -> list[Finding]:
    """L3: four required keys (tools accepts list or comma-string shape)."""
    findings: list[Finding] = []
    fm = art.frontmatter

    for key in ("name", "description", "model"):
        if not _nonempty_str(fm.get(key)):
            findings.append(
                Finding(
                    check="L3",
                    rule="frontmatter.agent.missing-key",
                    severity="S2",
                    path=art.rel,
                    message=f"agent missing frontmatter key {key}",
                )
            )
    if not _present_tools(fm.get("tools")):
        findings.append(
            Finding(
                check="L3",
                rule="frontmatter.agent.missing-key",
                severity="S2",
                path=art.rel,
                message="agent missing frontmatter key tools",
            )
        )
    return findings


def _check_skill(art) -> list[Finding]:
    """L4: two required keys, and no tools/model."""
    findings: list[Finding] = []
    fm = art.frontmatter

    for key in ("name", "description"):
        if not _nonempty_str(fm.get(key)):
            findings.append(
                Finding(
                    check="L4",
                    rule="frontmatter.skill.shape",
                    severity="S2",
                    path=art.rel,
                    message=f"skill missing frontmatter key {key}",
                )
            )
    for forbidden in ("tools", "model"):
        if forbidden in fm:
            findings.append(
                Finding(
                    check="L4",
                    rule="frontmatter.skill.shape",
                    severity="S2",
                    path=art.rel,
                    message=f"skill must not declare {forbidden}",
                )
            )
    return findings


def _check_meta_guide(art) -> list[Finding]:
    """L5: meta-guides carry no frontmatter (ADR-11)."""
    if not art.has_frontmatter:
        return []
    return [
        Finding(
            check="L5",
            rule="frontmatter.metaguide.no-frontmatter",
            severity="S2",
            path=art.rel,
            message="meta-guide must not have frontmatter (ADR-11)",
        )
    ]


# Per-kind dispatch table: kind -> rule helper.
_KIND_CHECKS = {
    "command": _check_command,
    "agent": _check_agent,
    "skill": _check_skill,
    "meta-guide": _check_meta_guide,
}


def check(plugin_root: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []

    for art in _model.discover(plugin_root):
        # Surface unparseable frontmatter on any artifact kind first.
        if art.frontmatter_error:
            findings.append(_parse_error_finding(art))
            continue

        handler = _KIND_CHECKS.get(art.kind)
        if handler is not None:
            findings.extend(handler(art))

    return findings
