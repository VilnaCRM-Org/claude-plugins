"""Shared bounded redaction for evaluator evidence and prompts."""

from __future__ import annotations

import json
import re

KEY_ASSIGNMENT_RE = re.compile(
    r'(?i)[{,]\s*(?P<json_name>"(?:[^"\\]|\\.)*")\s*:'
    r"|(?<![a-z0-9_-])(?P<name>\"[a-z0-9_-]+\"|'[a-z0-9_-]+'|[a-z0-9_-]+)"
    r"\s*[:=]"
)
SECRET_MARKERS = ("api_key", "api-key", "apikey", "secret", "token", "password")


JSON_NEXT_KEY_RE = re.compile(r',\s*"(?:[^"\\]|\\.)*"\s*:')


def _secret_name(name: str, json_name: bool) -> bool:
    if json_name:
        try:
            name = json.loads(name)
        except ValueError:
            pass  # Malformed keys retain conservative raw-name marker matching.
    return any(marker in name.lower() for marker in SECRET_MARKERS)


def _json_boundary(value: str, cursor: int) -> bool:
    return value[cursor] in "}]" or (
        value[cursor] == "," and JSON_NEXT_KEY_RE.match(value, cursor) is not None
    )


def _json_container_end(value: str, start: int) -> int:
    """Consume a whole container, or the tail if it is malformed."""
    stack = []
    cursor = start
    while cursor < len(value):
        char = value[cursor]
        if char == '"':
            cursor = _json_string_end(value, cursor)
            continue
        if char in "{[":
            stack.append("}" if char == "{" else "]")
        elif char in "}]":
            if not stack or char != stack.pop():
                return len(value)
            if not stack:
                return cursor + 1
        cursor += 1
    return cursor


def _json_string_end(value: str, start: int) -> int:
    cursor = start + 1
    while cursor < len(value):
        if value[cursor] == "\\":
            cursor += 2
            continue
        if value[cursor] == '"':
            return cursor + 1
        cursor += 1
    return len(value)


def _secret_value_end(value: str, start: int, json_value: bool = False) -> int:
    """Scan one value, retaining adjacent quotes and escaped whitespace in its span."""
    cursor = (
        _json_container_end(value, start)
        if json_value and start < len(value) and value[start] in "{["
        else start
    )
    quote = ""
    while cursor < len(value):
        char = value[cursor]
        if char == "\\":
            cursor = min(cursor + 2, len(value))
            continue
        if quote:
            if char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char.isspace() or (json_value and _json_boundary(value, cursor)):
            break
        cursor += 1
    # An unterminated quote consumes the tail, including spaces and newlines.
    return cursor


def _redact_json_string(value: str, start: int) -> tuple[int, str] | None:
    """Inspect a complete JSON string before skipping its bounded source span."""
    if start == len(value) or value[start] != '"':
        return None
    end = _json_string_end(value, start)
    try:
        decoded = json.loads(value[start:end])
    except (ValueError, RecursionError):
        return None
    redacted = _redact_assignments(decoded, decode_strings=False)
    rendered = value[start:end] if redacted == decoded else json.dumps(redacted)
    return end, rendered


def _value_start(value: str, cursor: int) -> int:
    while cursor < len(value) and value[cursor].isspace():
        cursor += 1
    return cursor


def _redact_assignments(value: str, decode_strings: bool) -> str:
    chunks = []
    cursor = emitted = 0
    while match := KEY_ASSIGNMENT_RE.search(value, cursor):
        cursor = match.end()
        json_value = match["json_name"] is not None
        group = "json_name" if json_value else "name"
        name = match[group]
        start = _value_start(value, cursor)
        if not _secret_name(name, json_value):
            string = (
                _redact_json_string(value, start)
                if decode_strings and json_value
                else None
            )
            if string is not None:
                end, rendered = string
                chunks.extend((value[emitted:start], rendered))
                emitted = cursor = end
            continue
        end = _secret_value_end(value, start, json_value)
        if end == start:
            continue
        replacement = f'{name}:"[REDACTED]"' if json_value else f"{name}=[REDACTED]"
        chunks.extend((value[emitted : match.start(group)], replacement))
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
