"""Shared bounded redaction for evaluator evidence and prompts."""

from __future__ import annotations

import json
import re

from redaction_scan import (
    json_string_end,
    json_string_tail_is_valid,
    secret_value_end,
)

KEY_ASSIGNMENT_RE = re.compile(
    r'(?i)[{,]\s*(?P<json_name>"(?:[^"\\]|\\.)*")\s*:'
    r"|(?<![a-z0-9_-])(?P<name>\"[a-z0-9_-]+\"|'[a-z0-9_-]+'|[a-z0-9_-]+)"
    r"\s*[:=]"
)
SECRET_MARKERS = ("api_key", "api-key", "apikey", "secret", "token", "password")


def _secret_name(name: str, json_name: bool) -> bool:
    if json_name:
        try:
            name = json.loads(name)
        except ValueError:
            pass  # Malformed keys retain conservative raw-name marker matching.
    return any(marker in name.lower() for marker in SECRET_MARKERS)


def _has_secret_assignment(value: str) -> bool:
    for match in KEY_ASSIGNMENT_RE.finditer(value):
        json_name = match["json_name"] is not None
        name = match["json_name"] if json_name else match["name"]
        if _secret_name(name, json_name):
            return True
    return False


def _redact_json_string(value: str, start: int) -> tuple[int, str] | None:
    """Inspect a complete JSON string before skipping its bounded source span."""
    if start == len(value) or value[start] != '"':
        return None
    end = json_string_end(value, start)
    try:
        decoded = json.loads(value[start:end])
    except (ValueError, RecursionError):
        return None
    if not json_string_tail_is_valid(value, end) and _has_secret_assignment(decoded):
        # A premature quote can strand the secret outside this decoded prefix.
        return len(value), '"[REDACTED]"'
    redacted = _redact_assignments(decoded, decode_strings=False)
    rendered = (
        value[start:end]
        if redacted == decoded
        else json.dumps(redacted, ensure_ascii=False)
        .encode("utf-8", errors="backslashreplace")
        .decode("utf-8")
    )
    return end, rendered


def _value_start(value: str, cursor: int) -> int:
    while cursor < len(value) and value[cursor].isspace():
        cursor += 1
    return cursor


def _assignment_edit(
    value: str, match: re.Match[str], decode_strings: bool
) -> tuple[int, int, str] | None:
    """Return one replacement span without advancing past untouched assignments."""
    json_value = match["json_name"] is not None
    group = "json_name" if json_value else "name"
    name = match[group]
    start = _value_start(value, match.end())
    if _secret_name(name, json_value):
        end = secret_value_end(value, start, json_value)
        if end == start:
            return None
        replacement = f'{name}:"[REDACTED]"' if json_value else f"{name}=[REDACTED]"
        return match.start(group), end, replacement
    if decode_strings and json_value:
        string = _redact_json_string(value, start)
        if string is not None:
            end, rendered = string
            return start, end, rendered
    return None


def _redact_assignments(value: str, decode_strings: bool) -> str:
    chunks = []
    cursor = emitted = 0
    while match := KEY_ASSIGNMENT_RE.search(value, cursor):
        cursor = match.end()
        edit = _assignment_edit(value, match, decode_strings)
        if edit is not None:
            start, end, replacement = edit
            chunks.extend((value[emitted:start], replacement))
            emitted = cursor = end
    chunks.append(value[emitted:])
    return "".join(chunks)


def redact_text(value: str) -> str:
    """Match named shell assignments and decoded JSON keys, not arbitrary secrets.

    JSON string values are decoded once for embedded assignments; this is not
    recursive decoding of arbitrary encoded payloads. Malformed input may lose
    following context conservatively rather than expose a suspected secret tail.
    """
    return _redact_assignments(value, decode_strings=True)
