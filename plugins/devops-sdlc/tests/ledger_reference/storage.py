"""Reviewed ledger reference: storage boundary."""

import json
import os
import re
import stat
import uuid


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate ledger key")
        result[key] = value
    return result


def _read(directory, name):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    with os.fdopen(fd) as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("Non-regular ledger")
        return json.load(stream, object_pairs_hook=_unique)


def _save(directory, value):
    name = ".attempts-" + uuid.uuid4().hex
    fd = os.open(
        name,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o600,
        dir_fd=directory,
    )
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, "attempts.json", src_dir_fd=directory, dst_dir_fd=directory)
        os.fsync(directory)
    finally:
        try:
            os.unlink(name, dir_fd=directory)
        except FileNotFoundError:
            pass


def _pending_snapshot(directory):
    """Retain crash leftovers as uncertain evidence; never promote or delete them."""
    with os.scandir(directory) as entries:
        return any(
            re.fullmatch(r"\.attempts-[0-9a-f]{32}", entry.name) for entry in entries
        )
