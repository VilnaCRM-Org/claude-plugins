# Atomic ledger implementation reference

These exact-file listings mirror the reviewed Python package under
`tests/ledger_reference/`. Tests import that package and compare these listings
as source data; they never execute Markdown. Follow the complete caller,
filesystem, initialization, budget and recovery prerequisites in the
[agent guide](../skills/AI-AGENT-GUIDE.md) before copying or importing this package.
The reference is a caller implementation, not a `devops.py` command or proof of
host enforcement. Copy every package file and verify its recorded hash.

<!-- atomic-ledger-reference:start -->
<!-- atomic-ledger-module:ledger_reference/__init__.py -->
```python
"""Tested POSIX ledger reference; requires the documented trusted host contract."""

from .transaction import transaction

__all__ = ["transaction"]
```

<!-- atomic-ledger-module:ledger_reference/storage.py -->
```python
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
```

<!-- atomic-ledger-module:ledger_reference/history.py -->
```python
"""Reviewed ledger reference: history boundary."""

import re


def _text(value):
    return isinstance(value, str) and bool(value.strip()) and value == value.strip()


def _attempt(value):
    if not isinstance(value, dict) or type(value.get("attempt")) is not int:
        return False
    if not 1 <= value["attempt"] <= 5 or not _text(value.get("owner")):
        return False
    token = value.get("token")
    return (
        isinstance(token, str)
        and re.fullmatch("[0-9a-f]{32}", token) is not None
        and value.get("phase") in ("reserved", "started")
    )


def _past_attempt(past, number):
    if not _attempt(past) or past["attempt"] != number:
        return False
    if past.get("outcome") not in ("PASSED", "FAILED", "BLOCKED"):
        return False
    return _text(past.get("evidence")) and (
        past["outcome"] != "PASSED" or past["phase"] == "started"
    )


def _coherent(entry):
    count, active, history = (
        entry.get("count"),
        entry.get("active"),
        entry.get("history"),
    )
    if type(count) is not int or not 0 <= count <= 5 or "active" not in entry:
        return False
    if not isinstance(history, list) or len(history) != count - (active is not None):
        return False
    tokens = []
    for number, past in enumerate(history, 1):
        if not _past_attempt(past, number):
            return False
        tokens.append(past["token"])
    if active is not None:
        if not _attempt(active) or active["attempt"] != count:
            return False
        tokens.append(active["token"])
    return len(tokens) == len(set(tokens))
```

<!-- atomic-ledger-module:ledger_reference/state.py -->
```python
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
```

<!-- atomic-ledger-module:ledger_reference/observation.py -->
```python
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
```

<!-- atomic-ledger-module:ledger_reference/actions.py -->
```python
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
```

<!-- atomic-ledger-module:ledger_reference/transaction.py -->
```python
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
```
<!-- atomic-ledger-reference:end -->
