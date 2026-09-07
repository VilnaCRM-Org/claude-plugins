"""Owned reservation transitions; inspection never grants execution authority."""

import uuid

from .history import _text
from .state import _stop
from .storage import _save


def reserve(directory, data, entry, request):
    if entry["active"] is not None:
        return {"decision": "BLOCKED", "reason": "active reservation retained"}
    stop = _stop(entry, True)
    if stop:
        return {"decision": stop, "count": entry.get("count")}
    entry["count"] += 1
    active = {
        "token": uuid.uuid4().hex,
        "owner": request["owner"],
        "attempt": entry["count"],
        "phase": "reserved",
    }
    entry["active"] = active
    _save(directory, data)
    return {"decision": "RESERVED", **active}


def finish(directory, data, entry, request):
    active = entry["active"]
    if not _completion_verified(active, request):
        return {
            "decision": "BLOCKED",
            "reason": "completion uncertain; marker retained",
        }
    entry["history"].append(
        {**active, "outcome": request["outcome"], "evidence": request["evidence"]}
    )
    entry["active"] = None
    _save(directory, data)
    return {"decision": "RECORDED", "count": entry["count"]}


def owned_action(directory, data, entry, request):
    active = entry["active"]
    if (
        active is None
        or active["token"] != request.get("token")
        or active["owner"] != request["owner"]
    ):
        return {"decision": "BLOCKED", "reason": "reservation ownership mismatch"}
    action = request.get("action")
    if action == "finish":
        return finish(directory, data, entry, request)
    if action == "observe":
        return {"decision": "OBSERVE_ONLY", **active}
    stop = _stop(entry, False)
    if stop or action != "start" or active["phase"] != "reserved":
        return {"decision": stop or "BLOCKED", "reason": "do not start or replay"}
    active["phase"] = "started"
    _save(directory, data)
    return {"decision": "START_ONCE", **active}


def _completion_verified(active, request):
    outcome = request.get("outcome")
    if outcome not in ("PASSED", "FAILED", "BLOCKED"):
        return False
    if outcome == "PASSED" and active["phase"] != "started":
        return False
    return _text(request.get("evidence")) and request.get("no_pending_verified") is True
