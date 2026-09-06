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
