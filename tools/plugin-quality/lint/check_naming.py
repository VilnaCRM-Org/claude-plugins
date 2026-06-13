"""Tier-1 naming checks (L6–L10).

Pins identity and shape conventions across plugin artifacts:

* L6  agent ``name`` == filename stem == leading token of the H1.
* L7  skill ``name`` == parent directory name (NOT compared to the H1, which is
      Title Case by design).
* L8  any ``model`` value is one of the accepted driver models.
* L9  ``argument-hint`` is one or more bracketed ``[...]`` groups.
* L10 command/agent/skill identity names are kebab-case.

Every check walks :func:`_model.discover` output generically; no filenames are
hardcoded.
"""

from __future__ import annotations

import pathlib
import re

from _common import Finding
import _model

# Accepted driver/model values (L8). Mirrors plugin docs + ADR-8.
MODEL_ENUM = frozenset({"sonnet", "opus", "haiku", "fable", "inherit"})

# Kebab-case identity: lowercase alnum tokens joined by single hyphens (L10).
# Digits are allowed inside tokens, e.g. "bmad-fr-nfr-review-gate".
KEBAB_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# One bracketed group: "[" then any non-"]" chars then "]" (L9).
_HINT_GROUP = r"\[[^\]]*\]"
# Whole argument-hint: one or more groups, optionally space-separated.
# Multi-group is allowed per plugin docs (e.g. "[a] [b]").
ARGUMENT_HINT_RE = re.compile(rf"^{_HINT_GROUP}(\s+{_HINT_GROUP})*$")

# H1 "name — description" / "name - description": split on the first em-dash or
# spaced hyphen separator and keep the leading token (L6).
_H1_SEP_RE = re.compile(r"\s+(?:—|-)\s+")


def _h1_lead_token(h1: str) -> str:
    """Leading identity token of an agent H1.

    The H1 may be ``"name — description"`` (em-dash) or ``"name - description"``
    (spaced hyphen). Compare only the part before the first such separator.
    A bare ``"name"`` H1 returns unchanged.
    """
    return _H1_SEP_RE.split(h1, maxsplit=1)[0].strip()


def _fm_str(artifact: "_model.Artifact", key: str) -> str | None:
    """Frontmatter value at ``key`` as a stripped string, else None."""
    value = artifact.frontmatter.get(key)
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def check(plugin_root: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []
    artifacts = _model.discover(plugin_root)

    for art in artifacts:
        # --- L6: agent name == filename stem == H1 leading token ---
        if art.kind == "agent":
            fm_name = _fm_str(art, "name")
            stem = art.path.stem
            if fm_name is not None:
                if fm_name != stem:
                    findings.append(
                        Finding(
                            check="L6",
                            rule="naming.agent.name-mismatch",
                            severity="S2",
                            path=art.rel,
                            message=(
                                f"agent name {fm_name!r} must equal filename "
                                f"stem {stem!r}"
                            ),
                        )
                    )
                if art.h1 is not None:
                    lead = _h1_lead_token(art.h1)
                    if fm_name != lead:
                        findings.append(
                            Finding(
                                check="L6",
                                rule="naming.agent.name-mismatch",
                                severity="S2",
                                path=art.rel,
                                message=(
                                    f"agent name {fm_name!r} must equal the H1 "
                                    f"leading token {lead!r} (from H1 "
                                    f"{art.h1!r})"
                                ),
                            )
                        )

        # --- L7: skill name == parent directory name ---
        if art.kind == "skill":
            fm_name = _fm_str(art, "name")
            dir_name = art.path.parent.name
            if fm_name is not None and fm_name != dir_name:
                findings.append(
                    Finding(
                        check="L7",
                        rule="naming.skill.name-mismatch",
                        severity="S2",
                        path=art.rel,
                        message=(
                            f"skill name {fm_name!r} must equal parent "
                            f"directory name {dir_name!r}"
                        ),
                    )
                )

        # --- L8: model enum (any artifact carrying a model) ---
        model = art.frontmatter.get("model")
        if model is not None:
            model_str = model.strip() if isinstance(model, str) else str(model)
            if model_str not in MODEL_ENUM:
                findings.append(
                    Finding(
                        check="L8",
                        rule="naming.model.enum",
                        severity="S2",
                        path=art.rel,
                        message=(
                            f"model {model_str!r} not in "
                            f"{sorted(MODEL_ENUM)}"
                        ),
                    )
                )

        # --- L9: argument-hint shape (anything carrying the key) ---
        if "argument-hint" in art.frontmatter:
            raw = art.frontmatter.get("argument-hint")
            hint = raw.strip() if isinstance(raw, str) else str(raw).strip()
            # Strip a single matched layer of surrounding quotes.
            if len(hint) >= 2 and hint[0] == hint[-1] and hint[0] in "\"'":
                hint = hint[1:-1].strip()
            if not ARGUMENT_HINT_RE.match(hint):
                findings.append(
                    Finding(
                        check="L9",
                        rule="naming.argument-hint.shape",
                        severity="S3",
                        path=art.rel,
                        message=(
                            f"argument-hint {hint!r} must be one or more "
                            f"bracketed groups, e.g. '[a]' or '[a] [b]'"
                        ),
                    )
                )

        # --- L10: kebab-case identity name ---
        if art.kind == "command":
            ident = art.path.stem
        elif art.kind == "agent":
            ident = _fm_str(art, "name") or art.path.stem
        elif art.kind == "skill":
            ident = art.path.parent.name
        else:
            ident = None  # meta-guides have no identity name to constrain
        if ident is not None and not KEBAB_RE.match(ident):
            findings.append(
                Finding(
                    check="L10",
                    rule="naming.kebab-case",
                    severity="S3",
                    path=art.rel,
                    message=(
                        f"{art.kind} name {ident!r} must be kebab-case "
                        f"(^[a-z0-9]+(-[a-z0-9]+)*$)"
                    ),
                )
            )

    return findings
