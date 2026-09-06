"""Linear source-span scanning for quoted and structured secret values."""

from __future__ import annotations

import re

JSON_NEXT_KEY_RE = re.compile(r',\s*"(?:[^"\\]|\\.)*"\s*:')


def _json_boundary(value: str, cursor: int) -> bool:
    return value[cursor] in "}]" or (
        value[cursor] == "," and JSON_NEXT_KEY_RE.match(value, cursor) is not None
    )


def json_string_tail_is_valid(value: str, end: int) -> bool:
    """Require a field boundary after a decoded field string before trusting it."""
    while end < len(value) and value[end].isspace():
        end += 1
    return end == len(value) or _json_boundary(value, end)


def _json_container_end(value: str, start: int) -> int:
    """Consume a whole container, or the tail if it is malformed."""
    stack = []
    cursor = start
    while cursor < len(value):
        char = value[cursor]
        if char == '"':
            cursor = json_string_end(value, cursor)
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


def json_string_end(value: str, start: int) -> int:
    cursor = start + 1
    while cursor < len(value):
        if value[cursor] == "\\":
            cursor += 2
            continue
        if value[cursor] == '"':
            return cursor + 1
        cursor += 1
    return len(value)


def secret_value_end(value: str, start: int, json_value: bool = False) -> int:
    """Scan one value, retaining adjacent quotes and escaped whitespace in its span."""
    cursor = (
        _json_container_end(value, start)
        if json_value and start < len(value) and value[start] in "{["
        else start
    )
    quote = ""
    encoded_quote = False
    while cursor < len(value):
        char = value[cursor]
        if char == "\\":
            following = value[cursor + 1 : cursor + 2]
            if encoded_quote and following == quote:
                quote, encoded_quote = "", False
            elif not quote and following in ('"', "'"):
                quote, encoded_quote = following, True
            cursor = min(cursor + 2, len(value))
            continue
        if quote:
            if char == quote and not encoded_quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char.isspace() or (json_value and _json_boundary(value, cursor)):
            break
        cursor += 1
    # An unterminated quote consumes the tail, including spaces and newlines.
    return cursor
