"""Original-source citation selection around named-key redaction spans."""

from __future__ import annotations

import re

from redaction import redacted_source_spans


def source_chunks(artifact_raw: str):
    """Yield exact schema-safe fragments and their unchanged-source offsets."""

    for literal in re.finditer(r'[^"\\\x00-\x1f]+', artifact_raw):
        text = literal.group()
        for start in range(0, len(text), 120):
            yield text[start : start + 120], literal.start() + start


def advance_span_index(
    spans: tuple[tuple[int, int], ...], span_index: int, start: int
) -> int:
    while span_index < len(spans) and spans[span_index][1] <= start:
        span_index += 1
    return span_index


def citation_is_redaction_stable(
    artifact_raw: str,
    citation: str,
    spans: tuple[tuple[int, int], ...] | None = None,
) -> bool:
    """Accept only a literal whose every source occurrence is unredacted."""

    spans = redacted_source_spans(artifact_raw) if spans is None else spans
    start = span_index = 0
    found = False
    while True:
        start = artifact_raw.find(citation, start)
        if start < 0:
            return found
        found = True
        end = start + len(citation)
        span_index = advance_span_index(spans, span_index, start)
        if span_index < len(spans) and spans[span_index][0] < end:
            return False
        start += 1


def citation_choices(
    artifact_raw: str,
    maximum: int,
    spans: tuple[tuple[int, int], ...] | None = None,
) -> list[str]:
    """Return bounded exact fragments that never occur in redacted source."""

    spans = redacted_source_spans(artifact_raw) if spans is None else spans
    choices: list[str] = []
    unsafe: set[str] = set()
    span_index = 0
    for chunk, start in source_chunks(artifact_raw):
        span_index = advance_span_index(spans, span_index, start)
        intersects = span_index < len(spans) and spans[span_index][0] < start + len(
            chunk
        )
        if intersects:
            unsafe.add(chunk)
            if chunk in choices:
                choices.remove(chunk)
        elif (
            chunk.strip()
            and chunk not in choices
            and chunk not in unsafe
            and len(choices) < maximum
        ):
            choices.append(chunk)
    return [
        chunk
        for chunk in choices
        if citation_is_redaction_stable(artifact_raw, chunk, spans)
    ]
