"""Tier-2 manifest validation (M1-M4) for plugin packaging.

Ports the repo CI ``manifest-validate`` job's jq logic to Python so the
plugin packaging contract is enforced offline alongside the Tier-1 linters:

* M1 (manifest.plugin.fields)   -> ``plugin.json`` has the required non-empty
  identity/metadata fields (FR-19; ci.yml).
* M2 (manifest.plugin.semver)   -> ``version`` is semver, prerelease allowed
  (ADR-9).
* M3 (manifest.plugin.name-dir) -> ``plugin.json`` ``name`` equals the plugin
  directory name (FR-19).
* M4 (manifest.marketplace)     -> repo-level ``marketplace.json`` parses, has
  name+owner.name+>=1 plugin, and every entry's ``source`` is
  ``./plugins/<name>`` pointing at a real dir (ADR-9).

:func:`check` runs the per-plugin checks (M1-M3); :func:`check_marketplace`
runs the single repo-level marketplace check (M4). A missing manifest file
yields one ``*.missing`` finding rather than a crash.
"""

import json
import pathlib
import re

from _common import Finding

# M2: semver MAJOR.MINOR.PATCH with an optional prerelease suffix (ADR-9).
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$")

# M1: required top-level keys in plugin.json. Dotted entries are nested keys.
PLUGIN_REQUIRED_FIELDS = (
    "name",
    "description",
    "version",
    "author.name",
    "homepage",
    "repository",
    "license",
    "keywords",
)


def _get_nested(data: dict, dotted: str):
    """Resolve a dotted key path (``author.name``) against ``data``.

    Returns ``None`` if any segment is absent or not a mapping en route.
    """
    cur = data
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def _is_empty(value) -> bool:
    """A field is "empty" if it is None, an empty/whitespace string, or an
    empty list/dict. Non-empty scalars (numbers, True) are never empty."""
    if value is None:
        return True
    if isinstance(value, str):
        return value.strip() == ""
    if isinstance(value, (list, dict)):
        return len(value) == 0
    return False


def _load_json(path: pathlib.Path):
    """Return ``(data, error)``; exactly one is non-None."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:  # pragma: no cover - defensive
        return None, f"could not read file: {exc}"
    try:
        return json.loads(text), None
    except json.JSONDecodeError as exc:
        return None, f"JSON parse error: {exc}"


def _check_plugin_fields(data: dict, rel: str) -> list[Finding]:
    """M1: every required field present and non-empty (one finding per problem)."""
    findings: list[Finding] = []
    for field in PLUGIN_REQUIRED_FIELDS:
        value = _get_nested(data, field)
        if _is_empty(value):
            findings.append(
                Finding(
                    check="M1",
                    rule="manifest.plugin.fields",
                    severity="S1",
                    path=rel,
                    message=f"plugin.json missing or empty required field: {field}",
                )
            )
    return findings


def _check_plugin_semver(data: dict, rel: str) -> list[Finding]:
    """M2: version must be a semver STRING (prerelease suffix allowed).

    M1 already reports an absent/empty version, so M2 skips only that case to
    avoid double-counting one root cause. Anything else present — a malformed
    string ("0.1") OR a non-string value (YAML float 1.0, a list) — is M2's
    concern; a non-string version must not silently bypass the check.
    """
    version = data.get("version")
    version_absent_or_empty = version is None or (
        isinstance(version, str) and not version.strip()
    )
    if version_absent_or_empty:
        return []
    if isinstance(version, str) and SEMVER_RE.match(version):
        return []
    return [
        Finding(
            check="M2",
            rule="manifest.plugin.semver",
            severity="S1",
            path=rel,
            message=(
                f"plugin.json version {version!r} is not a semver string "
                "MAJOR.MINOR.PATCH[-prerelease]"
            ),
        )
    ]


def _check_plugin_name_dir(
    data: dict, rel: str, plugin_root: pathlib.Path
) -> list[Finding]:
    """M3: plugin.json name must equal the plugin directory name."""
    name = data.get("name")
    if not (isinstance(name, str) and name.strip()):
        return []
    if name.strip() == plugin_root.name:
        return []
    return [
        Finding(
            check="M3",
            rule="manifest.plugin.name-dir",
            severity="S1",
            path=rel,
            message=(
                f"plugin.json name {name.strip()!r} != plugin dir "
                f"name {plugin_root.name!r}"
            ),
        )
    ]


def check(plugin_root: pathlib.Path) -> list[Finding]:
    """M1-M3: validate one plugin's ``.claude-plugin/plugin.json``."""
    plugin_root = pathlib.Path(plugin_root)

    repo_root = plugin_root.parent.parent
    manifest = plugin_root / ".claude-plugin" / "plugin.json"
    try:
        rel = str(manifest.relative_to(repo_root))
    except ValueError:
        rel = str(manifest)

    if not manifest.is_file():
        return [
            Finding(
                check="M1",
                rule="manifest.plugin.missing",
                severity="S1",
                path=rel,
                message="plugin manifest .claude-plugin/plugin.json is missing",
            )
        ]

    data, error = _load_json(manifest)
    if error is not None:
        return [
            Finding(
                check="M1",
                rule="manifest.plugin.fields",
                severity="S1",
                path=rel,
                message=f"plugin.json does not parse: {error}",
            )
        ]

    # A valid JSON file whose root is not an object (``[]``, ``"x"``, ``42``)
    # has no fields to validate and would crash ``data.get(...)`` below: report
    # the wrong shape once and stop rather than raise.
    if not isinstance(data, dict):
        return [
            Finding(
                check="M1",
                rule="manifest.plugin.fields",
                severity="S1",
                path=rel,
                message="plugin.json root is not a JSON object",
            )
        ]

    findings: list[Finding] = []
    findings.extend(_check_plugin_fields(data, rel))
    findings.extend(_check_plugin_semver(data, rel))
    findings.extend(_check_plugin_name_dir(data, rel, plugin_root))
    return findings


def _market_finding(rel: str, message: str) -> Finding:
    """An M4 ``manifest.marketplace`` finding (the shared shape)."""
    return Finding(
        check="M4",
        rule="manifest.marketplace",
        severity="S1",
        path=rel,
        message=message,
    )


def _check_market_top_fields(data: dict, rel: str) -> list[Finding]:
    """M4: top-level ``name`` and ``owner.name`` present and non-empty."""
    findings: list[Finding] = []
    if _is_empty(data.get("name")):
        findings.append(
            _market_finding(
                rel, "marketplace.json missing or empty required field: name"
            )
        )
    if _is_empty(_get_nested(data, "owner.name")):
        findings.append(
            _market_finding(
                rel, "marketplace.json missing or empty required field: owner.name"
            )
        )
    return findings


def _check_market_source_match(name, source, label: str, rel: str) -> list[Finding]:
    """M4: ``source`` matches ``./plugins/<name>`` when a non-empty name exists.

    Without a name the expected path is undefined ("./plugins/None"), and the
    missing/empty name is reported by the caller — emitting a spurious "source
    mismatch" here too would double-count one root cause, so skip it.
    """
    if not (isinstance(name, str) and name.strip()):
        return []
    expected = f"./plugins/{name.strip()}"
    if source == expected:
        return []
    return [
        _market_finding(
            rel,
            f"marketplace entry {label!r} source {source!r} != {expected!r}",
        )
    ]


def _check_market_source_dir(
    source, label: str, rel: str, repo_root: pathlib.Path
) -> list[Finding]:
    """M4: the referenced ``source`` dir must exist (resolved against repo root)."""
    if not (isinstance(source, str) and source):
        return []
    if (repo_root / source).resolve().is_dir():
        return []
    return [
        _market_finding(
            rel,
            f"marketplace entry {label!r} source dir {source!r} does not exist",
        )
    ]


def _check_market_entry(
    entry, index: int, rel: str, repo_root: pathlib.Path
) -> list[Finding]:
    """M4: validate one ``plugins[index]`` entry (name + source + dir exists)."""
    if not isinstance(entry, dict):
        return [
            _market_finding(rel, f"marketplace.json plugins[{index}] is not an object")
        ]

    name = entry.get("name")
    source = entry.get("source")
    label = name if isinstance(name, str) and name.strip() else f"index {index}"

    findings: list[Finding] = []
    if _is_empty(name):
        findings.append(
            _market_finding(
                rel, f"marketplace.json plugins[{index}] missing or empty name"
            )
        )
    findings.extend(_check_market_source_match(name, source, label, rel))
    findings.extend(_check_market_source_dir(source, label, rel, repo_root))
    return findings


def check_marketplace(repo_root: pathlib.Path) -> list[Finding]:
    """M4: validate the repo-level ``.claude-plugin/marketplace.json``."""
    repo_root = pathlib.Path(repo_root)
    findings: list[Finding] = []

    manifest = repo_root / ".claude-plugin" / "marketplace.json"
    try:
        rel = str(manifest.relative_to(repo_root))
    except ValueError:
        rel = str(manifest)

    if not manifest.is_file():
        return [
            Finding(
                check="M4",
                rule="manifest.marketplace.missing",
                severity="S1",
                path=rel,
                message=(
                    "marketplace manifest .claude-plugin/marketplace.json is missing"
                ),
            )
        ]

    data, error = _load_json(manifest)
    if error is not None:
        return [_market_finding(rel, f"marketplace.json does not parse: {error}")]

    # A non-object root (``[]``, ``"x"``, ``42``) has no fields to validate and
    # would crash ``data.get(...)`` below: report the wrong shape once and stop.
    if not isinstance(data, dict):
        return [_market_finding(rel, "marketplace.json root is not a JSON object")]

    # name + owner.name present and non-empty.
    findings.extend(_check_market_top_fields(data, rel))

    # plugins must be a non-empty array.
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or len(plugins) == 0:
        findings.append(
            _market_finding(rel, "marketplace.json must list at least one plugin")
        )
        return findings

    # Each entry: source == "./plugins/<name>" and that dir exists.
    for i, entry in enumerate(plugins):
        findings.extend(_check_market_entry(entry, i, rel, repo_root))

    return findings
