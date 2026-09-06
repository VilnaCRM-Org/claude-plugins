"""Shared bounded redaction for evaluator evidence and prompts."""

from __future__ import annotations

import json
import re
import shlex

from redaction_scan import (
    json_string_end,
    json_string_tail_is_valid,
    secret_value_end,
)
from redaction_shell import decode_shell_word

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


def _redact_shell_word(value: str, start: int) -> tuple[int, str] | None:
    """Bound a nonsecret shell value before inspecting embedded assignments."""
    end = secret_value_end(value, start)
    source = value[start:end]
    if not source:
        return None
    try:
        decoded = decode_shell_word(source)
    except ValueError:
        # An unknown outer quote cannot safely delimit an embedded secret tail.
        return (end, "'[REDACTED]'") if _has_secret_assignment(source) else None
    redacted = _redact_assignments(decoded, decode_strings=False)
    if redacted == decoded:
        return end, source
    if not _single_quoted_word(source):
        # Decoding concatenated/escaped segments loses which spaces belonged to
        # the embedded secret. Keep the outer word boundary, mask its contents.
        return _shell_envelope_end(value, start, end), "'[REDACTED]'"
    return end, shlex.quote(redacted)


def _shell_envelope_end(value: str, start: int, end: int) -> int:
    """Retain a following assignment, but cover a premature inner quote's tail."""
    following = _value_start(value, end)
    if following == len(value) or KEY_ASSIGNMENT_RE.match(value, following):
        return end
    source = value[start:end]
    if not source or source[0] not in "\"'":
        return end
    for match in KEY_ASSIGNMENT_RE.finditer(source):
        name = match["json_name"] or match["name"]
        nested = _value_start(source, match.end())
        if (
            _secret_name(name, match["json_name"] is not None)
            and nested < len(source)
            and source[nested] == source[0]
        ):
            return max(end, secret_value_end(value, start + nested))
    return end


def _single_quoted_word(source: str) -> bool:
    if source.startswith("'"):
        return source.find("'", 1) == len(source) - 1
    return source.startswith('"') and json_string_end(source, 0) == len(source)


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
    if decode_strings:
        string = (
            _redact_json_string(value, start)
            if json_value
            else _redact_shell_word(value, start)
        )
        if string is not None:
            end, rendered = string
            return start, end, rendered
    return None


def _scan_assignments(
    value: str, decode_strings: bool
) -> tuple[str, tuple[tuple[int, int], ...]]:
    chunks = []
    changed = []
    cursor = emitted = 0
    while match := KEY_ASSIGNMENT_RE.search(value, cursor):
        cursor = match.end()
        edit = _assignment_edit(value, match, decode_strings)
        if edit is not None:
            start, end, replacement = edit
            chunks.extend((value[emitted:start], replacement))
            if replacement != value[start:end]:
                changed.append((start, end))
            emitted = cursor = end
    chunks.append(value[emitted:])
    return "".join(chunks), tuple(changed)


def _redact_assignments(value: str, decode_strings: bool) -> str:
    return _scan_assignments(value, decode_strings)[0]


def redacted_source_spans(value: str) -> tuple[tuple[int, int], ...]:
    """Return changed half-open character spans in unchanged original source.

    Enclosing decoded JSON/shell values may be conservatively covered in full.
    Offsets reveal no secret text. Consumers should scan once per source and
    reject intersecting citations; do not insert markers into untrusted source.
    """
    return _scan_assignments(value, decode_strings=True)[1]


def redact_text(value: str) -> str:
    """Match named shell assignments and decoded JSON keys, not arbitrary secrets.

    JSON string values are decoded once for embedded assignments; this is not
    recursive decoding of arbitrary encoded payloads. Malformed input may lose
    following context conservatively rather than expose a suspected secret tail.
    """
    return _redact_assignments(value, decode_strings=True)
