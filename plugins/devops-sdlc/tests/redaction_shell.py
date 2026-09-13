"""Linear shell-word decoding for bounded nonsecret assignment envelopes."""

from __future__ import annotations


def _shell_escape(value: str, cursor: int, quote: str) -> tuple[str, int]:
    if cursor + 1 == len(value):
        raise ValueError("Incomplete shell escape")
    following = value[cursor + 1]
    if quote == '"' and following not in '$`"\\\n':
        return "\\" + following, cursor + 2
    return ("" if following == "\n" else following), cursor + 2


def decode_shell_word(value: str) -> str:
    """Decode one bounded shell word without expansion or quadratic concatenation."""
    chunks = []
    cursor, quote = 0, ""
    while cursor < len(value):
        char = value[cursor]
        if char == "\\" and quote != "'":
            escaped, cursor = _shell_escape(value, cursor, quote)
            chunks.append(escaped)
            continue
        if quote:
            if char == quote:
                quote = ""
            else:
                chunks.append(char)
        elif char in "\"'":
            quote = char
        elif char.isspace():
            raise ValueError("More than one shell word")
        else:
            chunks.append(char)
        cursor += 1
    if quote:
        raise ValueError("Incomplete shell quote")
    return "".join(chunks)
