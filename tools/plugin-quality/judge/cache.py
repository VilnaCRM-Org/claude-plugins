"""Content-addressed verdict cache.

Judging is non-deterministic and costs API spend, so a verdict is cached by a
hash of (artifact bytes + rubric version + model). Re-running on unchanged files
returns the cached verdict for free and keeps results stable. Editing a file,
bumping ``RUBRIC_VERSION``, or switching model invalidates the entry naturally.

Cache lives under ``tools/plugin-quality/.judge-cache/`` (git-ignored).
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import tempfile

# Bump when rubric guidance or the prompt contract changes materially, to
# invalidate stale verdicts.
RUBRIC_VERSION = "1"

CACHE_DIR = pathlib.Path(__file__).resolve().parent.parent / ".judge-cache"


def _key(
    artifact_bytes: bytes,
    model: str,
    dimension_ids: list[str],
    extra_context: str = "",
) -> str:
    h = hashlib.sha256()
    h.update(artifact_bytes)
    h.update(b"\x00")
    h.update(RUBRIC_VERSION.encode())
    h.update(b"\x00")
    h.update(model.encode())
    h.update(b"\x00")
    h.update(",".join(sorted(dimension_ids)).encode())
    h.update(b"\x00")
    # Fold extra_context (e.g. a meta-guide's injected skill inventory) into the
    # identity so a changed context re-judges instead of serving a stale verdict.
    h.update(extra_context.encode())
    return h.hexdigest()


def get(
    artifact_bytes: bytes,
    model: str,
    dimension_ids: list[str],
    extra_context: str = "",
) -> dict | None:
    path = CACHE_DIR / f"{_key(artifact_bytes, model, dimension_ids, extra_context)}.json"
    if path.is_file():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return None
    return None


def put(
    artifact_bytes: bytes,
    model: str,
    dimension_ids: list[str],
    verdict: dict,
    extra_context: str = "",
) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = CACHE_DIR / f"{_key(artifact_bytes, model, dimension_ids, extra_context)}.json"
    payload = json.dumps(verdict, indent=2, sort_keys=True)
    # Atomic publish: write to a temp file in the same dir, then os.replace().
    # A crash mid-write leaves the old entry (or none), never a truncated file.
    fd, tmp = tempfile.mkstemp(dir=str(CACHE_DIR), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(payload)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
