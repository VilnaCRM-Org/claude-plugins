"""Reviewed ledger reference: observation boundary."""

import copy

from .history import _text
from .state import _saved_state


def _refresh(entry, identity, observe):
    if not callable(observe):
        return False
    try:
        value = observe(list(identity), copy.deepcopy(entry))
    except Exception:
        return False
    if not _valid_observation(value, identity):
        return False
    lost_run = entry.get("ralph") not in (None, "none") and value["ralph"] == "none"
    if entry.get("caller_stop") is not True:
        entry["caller_stop"] = value["caller_stop"]
        entry["caller_stop_evidence"] = value.get("caller_stop_evidence")
    if entry.get("breaker") not in ("open", "tripped"):
        entry["breaker"] = value["breaker"]
        if not lost_run:
            entry["ralph_evidence"] = value.get("ralph_evidence")
    elif value["breaker"] in ("open", "tripped") and not lost_run:
        entry["ralph_evidence"] = value["ralph_evidence"]
    if not lost_run:
        entry["ralph"] = value["ralph"]
    entry["observation_blocked"] = lost_run
    entry["observations"].append(
        {
            key: value.get(key)
            for key in (
                "identity",
                "evidence",
                "caller_stop",
                "caller_stop_evidence",
                "breaker",
                "ralph",
                "ralph_evidence",
            )
        }
    )
    return True


def _valid_observation(value, identity):
    if not isinstance(value, dict) or value.get("verified") is not True:
        return False
    return (
        value.get("identity") == identity
        and _text(value.get("evidence"))
        and _saved_state(value)
    )
