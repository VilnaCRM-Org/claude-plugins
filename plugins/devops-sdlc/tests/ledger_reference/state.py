"""Reviewed ledger reference: state boundary."""

import json

from .history import _text


def _stop(entry, new_reservation):
    count = entry.get("count")
    if new_reservation and type(count) is int and count >= 5:
        return "FAILED"
    if entry.get("caller_stop") is True:
        return "BLOCKED"
    observed = _text(entry.get("ralph_evidence"))
    if entry.get("breaker") in ("open", "tripped") and observed:
        return "FAILED"
    if not _ready(entry, count, observed):
        return "BLOCKED"
    return None


def _ready(entry, count, observed):
    if entry.get("observation_blocked") is True or type(count) is not int or count < 0:
        return False
    if entry.get("caller_stop") is not False or entry.get("breaker") != "clear":
        return False
    return entry.get("ralph") in ("none", "completed") and (
        entry.get("ralph") != "completed" or observed
    )


def _saved_state(entry):
    if type(entry.get("caller_stop")) is not bool:
        return False
    if entry.get("breaker") not in ("clear", "open", "tripped"):
        return False
    if entry.get("ralph") not in (
        "none",
        "active",
        "pending",
        "completed",
        "uncertain",
    ):
        return False
    if entry["caller_stop"] and not _text(entry.get("caller_stop_evidence")):
        return False
    return (entry["ralph"] == "none" and entry["breaker"] == "clear") or _text(
        entry.get("ralph_evidence")
    )


def _budget_key(identity):
    return tuple(identity[:2] + identity[3:])


def _record_identity(key, task_id):
    identity = json.loads(key)
    if not isinstance(identity, list) or len(identity) != 5:
        raise ValueError("Invalid saved identity")
    if not all(_text(value) for value in identity) or identity[0] != task_id:
        raise ValueError("Invalid saved identity")
    if key != json.dumps(identity, separators=(",", ":")):
        raise ValueError("Noncanonical saved identity")
    return identity


def _assigned_agents(data):
    assigned = {}
    for key, entry in data["entries"].items():
        identity = _record_identity(key, data["task_id"])
        budget = _budget_key(identity)
        if not isinstance(entry, dict) or budget in assigned:
            raise ValueError("Conflicting budget records")
        assigned[budget] = identity[2]
    return assigned


def _assignment_valid(data, identity):
    try:
        assigned = _assigned_agents(data)
    except (ValueError, TypeError):
        return False
    return assigned.get(_budget_key(identity), identity[2]) == identity[2]
