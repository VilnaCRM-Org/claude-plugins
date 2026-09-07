"""Lock-scoped ledger bootstrap, admission, and owned-action routing."""

import fcntl
import json
import os
import stat

from .actions import owned_action, reserve
from .history import _coherent, _text
from .observation import _refresh
from .state import _assignment_valid, _saved_state
from .storage import _pending_snapshot, _read, _save


def transaction(directory, identity, request, observe=None):
    # The caller supplies a verified retained task-directory descriptor.
    lock = os.open(
        "attempts.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600, dir_fd=directory
    )
    try:
        if not stat.S_ISREG(os.fstat(lock).st_mode):
            raise ValueError("Non-regular lock")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if _pending_snapshot(directory):
            return {
                "decision": "BLOCKED",
                "reason": "uncertain snapshot requires recovery",
            }
        return _locked(directory, identity, request, observe)
    except BlockingIOError:
        return {"decision": "BLOCKED", "reason": "reservation conflict"}
    finally:
        os.close(lock)  # Never unlink the persistent lock inode.


def _load(directory, identity, action):
    try:
        return _read(directory, "attempts.json"), None
    except FileNotFoundError:
        pass
    try:
        os.stat("run-summary.md", dir_fd=directory, follow_symlinks=False)
    except FileNotFoundError:
        if action == "initialize":
            return {"schema_version": 1, "task_id": identity[0], "entries": {}}, None
        reason = "missing ledger/history"
    else:
        reason = "verified locked migration required"
    return None, {"decision": "BLOCKED", "reason": reason}


def _schema(data, identity):
    if not isinstance(data, dict) or type(data.get("schema_version")) is not int:
        raise ValueError("Ledger identity/schema mismatch")
    if (
        data["schema_version"] != 1
        or data.get("task_id") != identity[0]
        or not isinstance(data.get("entries"), dict)
    ):
        raise ValueError("Ledger identity/schema mismatch")


def _initialize(directory, data, key, request):
    if key in data["entries"]:
        return {
            "decision": "BLOCKED",
            "reason": "initialization cannot replace history",
        }
    data["entries"][key] = {
        "count": 0,
        "caller_stop": False,
        "breaker": "clear",
        "ralph": "none",
        "ralph_evidence": None,
        "active": None,
        "history": [],
        "observations": [],
        "initialization_reference": request["verified_new_task_reference"],
    }
    _save(directory, data)
    return {"decision": "INITIALIZED", "count": 0}


def _known_stop(entry, action):
    if action == "reserve" and entry.get("active") is not None:
        return {"decision": "BLOCKED", "reason": "active reservation retained"}
    if action == "reserve" and type(entry.get("count")) is int and entry["count"] >= 5:
        return {"decision": "FAILED", "count": entry["count"]}
    if action in ("reserve", "start"):
        if entry.get("caller_stop") is True:
            return {"decision": "BLOCKED", "reason": "known caller stop retained"}
        if entry.get("breaker") in ("open", "tripped") and _text(
            entry.get("ralph_evidence")
        ):
            return {"decision": "FAILED", "reason": "evidenced breaker retained"}
    return None


def _admit(directory, data, identity, action, observe):
    entry = data["entries"][json.dumps(identity, separators=(",", ":"))]
    known = _known_stop(entry, action)
    if known is not None:
        return known
    if not _coherent(entry) or not isinstance(entry.get("observations"), list):
        return {
            "decision": "BLOCKED",
            "reason": "invalid history/active ownership; retained",
        }
    if action in ("reserve", "start"):
        if not _saved_state(entry):
            return {
                "decision": "BLOCKED",
                "reason": "missing/invalid saved state; retained",
            }
        if not _refresh(entry, identity, observe):
            return {
                "decision": "BLOCKED",
                "reason": "missing/unverified current observation",
            }
        _save(directory, data)
    return None


def _locked(directory, identity, request, observe):
    if (
        not isinstance(identity, list)
        or len(identity) != 5
        or not all(_text(x) for x in identity)
        or not _text(request.get("owner"))
    ):
        raise ValueError("Missing immutable identity or host session owner")
    key = json.dumps(identity, separators=(",", ":"))
    action = request.get("action")
    if action == "initialize" and not _text(request.get("verified_new_task_reference")):
        return {"decision": "BLOCKED", "reason": "invalid initialization reference"}
    data, blocked = _load(directory, identity, action)
    if blocked is not None:
        return blocked
    _schema(data, identity)
    if not _assignment_valid(data, identity):
        return {
            "decision": "BLOCKED",
            "reason": "conflicting budget or agent reassignment",
        }
    if action == "initialize":
        return _initialize(directory, data, key, request)
    return _dispatch(directory, data, identity, request, observe)


def _dispatch(directory, data, identity, request, observe):
    key = json.dumps(identity, separators=(",", ":"))
    entry = data["entries"].get(key)
    if not isinstance(entry, dict):
        return {"decision": "BLOCKED", "reason": "missing prior record"}
    action = request.get("action")
    blocked = _admit(directory, data, identity, action, observe)
    if blocked is not None:
        return blocked
    if action == "reserve":
        return reserve(directory, data, entry, request)
    return owned_action(directory, data, entry, request)
