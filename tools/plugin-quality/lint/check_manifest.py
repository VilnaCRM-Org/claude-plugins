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


def check(plugin_root: pathlib.Path) -> list[Finding]:
    """M1-M3: validate one plugin's ``.claude-plugin/plugin.json``."""
    plugin_root = pathlib.Path(plugin_root)
    findings: list[Finding] = []

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

    # M1: every required field present and non-empty (one finding per problem).
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

    # M2: version must be semver (prerelease suffix allowed).
    version = data.get("version")
    if not isinstance(version, str) or not SEMVER_RE.match(version):
        findings.append(
            Finding(
                check="M2",
                rule="manifest.plugin.semver",
                severity="S1",
                path=rel,
                message=(
                    f"plugin.json version {version!r} is not semver "
                    "MAJOR.MINOR.PATCH[-prerelease]"
                ),
            )
        )

    # M3: plugin.json name must equal the plugin directory name.
    name = data.get("name")
    if isinstance(name, str) and name.strip() and name.strip() != plugin_root.name:
        findings.append(
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
        )

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
                message="marketplace manifest .claude-plugin/marketplace.json is missing",
            )
        ]

    data, error = _load_json(manifest)
    if error is not None:
        return [
            Finding(
                check="M4",
                rule="manifest.marketplace",
                severity="S1",
                path=rel,
                message=f"marketplace.json does not parse: {error}",
            )
        ]

    # name + owner.name present and non-empty.
    if _is_empty(data.get("name")):
        findings.append(
            Finding(
                check="M4",
                rule="manifest.marketplace",
                severity="S1",
                path=rel,
                message="marketplace.json missing or empty required field: name",
            )
        )
    if _is_empty(_get_nested(data, "owner.name")):
        findings.append(
            Finding(
                check="M4",
                rule="manifest.marketplace",
                severity="S1",
                path=rel,
                message="marketplace.json missing or empty required field: owner.name",
            )
        )

    # plugins must be a non-empty array.
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or len(plugins) == 0:
        findings.append(
            Finding(
                check="M4",
                rule="manifest.marketplace",
                severity="S1",
                path=rel,
                message="marketplace.json must list at least one plugin",
            )
        )
        return findings

    # Each entry: source == "./plugins/<name>" and that dir exists.
    for i, entry in enumerate(plugins):
        if not isinstance(entry, dict):
            findings.append(
                Finding(
                    check="M4",
                    rule="manifest.marketplace",
                    severity="S1",
                    path=rel,
                    message=f"marketplace.json plugins[{i}] is not an object",
                )
            )
            continue

        name = entry.get("name")
        source = entry.get("source")
        label = name if isinstance(name, str) and name.strip() else f"index {i}"

        if _is_empty(name):
            findings.append(
                Finding(
                    check="M4",
                    rule="manifest.marketplace",
                    severity="S1",
                    path=rel,
                    message=f"marketplace.json plugins[{i}] missing or empty name",
                )
            )

        expected = f"./plugins/{name}" if isinstance(name, str) else None
        if expected is None or source != expected:
            findings.append(
                Finding(
                    check="M4",
                    rule="manifest.marketplace",
                    severity="S1",
                    path=rel,
                    message=(
                        f"marketplace entry {label!r} source {source!r} != "
                        f"{expected!r}"
                    ),
                )
            )

        # The referenced dir must exist (resolve against repo root).
        if isinstance(source, str) and source:
            target = (repo_root / source).resolve()
            if not target.is_dir():
                findings.append(
                    Finding(
                        check="M4",
                        rule="manifest.marketplace",
                        severity="S1",
                        path=rel,
                        message=(
                            f"marketplace entry {label!r} source dir "
                            f"{source!r} does not exist"
                        ),
                    )
                )

    return findings
