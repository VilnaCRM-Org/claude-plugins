"""Shared bounded redaction for evaluator evidence and prompts."""

from __future__ import annotations

import re

KEY_ASSIGNMENT_RE = re.compile(
    r"(?i)(?<![a-z0-9_-])(?P<name>\"[a-z0-9_-]+\"|'[a-z0-9_-]+'|[a-z0-9_-]+)"
    r"\s*[:=]"
)
SECRET_MARKERS = ("api_key", "api-key", "apikey", "secret", "token", "password")


def _secret_value_end(value: str, start: int) -> int:
    """Scan one value, retaining adjacent quotes and escaped whitespace in its span."""
    cursor = start
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
        elif char.isspace():
            break
        cursor += 1
    # An unterminated quote consumes the tail, including spaces and newlines.
    return cursor


def redact_text(value: str) -> str:
    """Redact named assignments without skipping secrets inside nonsecret wrappers."""
    chunks = []
    cursor = emitted = 0
    while match := KEY_ASSIGNMENT_RE.search(value, cursor):
        cursor = match.end()
        name = match["name"]
        if not any(marker in name.lower() for marker in SECRET_MARKERS):
            continue
        start = cursor
        while start < len(value) and value[start].isspace():
            start += 1
        end = _secret_value_end(value, start)
        if end == start:
            continue
        chunks.extend((value[emitted : match.start()], f"{name}=[REDACTED]"))
        emitted = cursor = end
    chunks.append(value[emitted:])
    return "".join(chunks)
