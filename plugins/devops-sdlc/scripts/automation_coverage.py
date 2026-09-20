"""Report supplied operational evidence without executing or verifying it."""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import sys
from collections import Counter
from pathlib import Path
from typing import cast

MAX_BYTES = 8 * 1024 * 1024
MAX_ROWS = 10_000
MAX_TEXT = 4096
OUTCOMES = ("complete", "failed", "blocked", "skipped", "incomplete", "excluded")
EVIDENCE_KINDS = ("actual", "fixture", "mock", "simulated", "documentation", "none")
EXECUTION_MODES = ("autonomous", "assisted", "manual")
IDENTITY = ("repository", "target", "environment", "operation")
DIMENSIONS = ("engine", "risk", "environment", "family")
REQUIRED_ROW = frozenset(
    (*IDENTITY, "id", "applicable", "outcome", "evidence", "exclusion_reason")
)
OPTIONAL_TEXT = ("engine", "risk", "family", "source_revision", "owner")
OPTIONAL_ROW = frozenset(
    (*OPTIONAL_TEXT, "preconditions", "command", "workflow_supported", "execution_mode")
)
LIMITATIONS = (
    "Evidence is supplied by the inventory author and is not independently verified.",
    "References and commands are inert data; they are never opened or executed.",
    "This report does not prove human-time reduction; no time savings are measured.",
    "This report does not prove deployment success beyond the supplied evidence.",
    "This frozen inventory does not prove comprehensive coverage of all DevOps work.",
    "The digest identifies this snapshot; it does not attest approval or truth.",
    "Autonomous completion and references remain author-supplied claims.",
    "A supplied baseline match does not authenticate or approve that baseline.",
)


class ValidationError(ValueError):
    """Invalid inventory, with diagnostics that never echo supplied values."""


def object_fields(
    value: object, required: frozenset[str], optional: frozenset[str] = frozenset()
) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ValidationError("Expected an object.")
    if not required <= value.keys() or value.keys() - required - optional:
        raise ValidationError("Missing or unknown object fields.")
    return cast(dict[str, object], value)


def text_field(value: object) -> str:
    if not isinstance(value, str):
        raise ValidationError("Expected a string.")
    if not value.strip() or value != value.strip() or len(value) > MAX_TEXT:
        raise ValidationError("Strings must be nonempty, trimmed and bounded.")
    if any(ord(char) < 32 or 0xD800 <= ord(char) <= 0xDFFF for char in value):
        raise ValidationError("Control characters and lone surrogates are forbidden.")
    return value


def enum_field(value: object, choices: tuple[str, ...]) -> str:
    result = text_field(value)
    if result not in choices:
        raise ValidationError("Unknown outcome or evidence kind.")
    return result


def bool_field(value: object) -> bool:
    if type(value) is not bool:
        raise ValidationError("Expected a boolean.")
    return value


def identifier_field(value: object) -> str:
    result = text_field(value)
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,127}", result, flags=re.ASCII):
        raise ValidationError("Identifiers must use canonical lowercase ASCII tokens.")
    return result


def repository_field(value: object) -> str:
    result = text_field(value)
    pattern = r"[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?/[a-z0-9][a-z0-9._-]{0,99}"
    if not re.fullmatch(pattern, result, flags=re.ASCII):
        raise ValidationError(
            "Repository must be canonical lowercase GitHub owner/repo."
        )
    return result


def revision_field(value: object) -> str:
    result = text_field(value)
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", result, flags=re.ASCII):
        raise ValidationError(
            "Source revision must be a full lowercase Git commit hash."
        )
    return result


def validate_evidence(value: object) -> str:
    evidence = object_fields(value, frozenset(("kind", "reference")))
    kind = enum_field(evidence["kind"], EVIDENCE_KINDS)
    if kind == "none":
        if evidence["reference"] is not None:
            raise ValidationError("Absent evidence requires a null reference.")
    else:
        text_field(evidence["reference"])
    return kind


def validate_applicability(row: dict[str, object], outcome: str) -> None:
    if bool_field(row["applicable"]):
        if row["exclusion_reason"] is not None or outcome == "excluded":
            raise ValidationError("Applicable rows cannot be excluded.")
    else:
        text_field(row["exclusion_reason"])
        if outcome != "excluded":
            raise ValidationError("Inapplicable rows require the excluded outcome.")


def validate_metadata(row: dict[str, object]) -> None:
    for key in OPTIONAL_TEXT:
        if key in row:
            if key == "source_revision":
                revision_field(row[key])
            else:
                identifier_field(row[key])
    for key in ("command", "preconditions"):
        if key in row:
            text_array(row[key])
    if "workflow_supported" in row:
        bool_field(row["workflow_supported"])
    if "execution_mode" in row:
        enum_field(row["execution_mode"], EXECUTION_MODES)


def text_array(values: object) -> None:
    if not isinstance(values, list) or len(values) > 256:
        raise ValidationError("Expected a bounded string array.")
    for value in values:
        text_field(value)


def validate_row(value: object) -> dict[str, object]:
    row = object_fields(value, REQUIRED_ROW, OPTIONAL_ROW)
    repository_field(row["repository"])
    for key in ("target", "environment", "operation", "id"):
        identifier_field(row[key])
    outcome = enum_field(row["outcome"], OUTCOMES)
    kind = validate_evidence(row["evidence"])
    validate_applicability(row, outcome)
    if outcome == "complete" and kind == "none":
        raise ValidationError("A claimed completion requires evidence.")
    validate_metadata(row)
    return row


def validate_inventory(value: object) -> dict[str, object]:
    inventory = object_fields(
        value, frozenset(("schema_version", "inventory_version", "rows"))
    )
    version = inventory["schema_version"]
    if type(version) is not int or version != 1:
        raise ValidationError("Only integer schema_version 1 is supported.")
    text_field(inventory["inventory_version"])
    rows = inventory["rows"]
    if not isinstance(rows, list) or len(rows) > MAX_ROWS:
        raise ValidationError("Expected a bounded row array.")
    ids: set[str] = set()
    identities: set[tuple[str, ...]] = set()
    for value in rows:
        row = validate_row(value)
        row_id = cast(str, row["id"])
        identity = tuple(cast(str, row[key]) for key in IDENTITY)
        if row_id in ids or identity in identities:
            raise ValidationError("Duplicate row ID or operational identity.")
        ids.add(row_id)
        identities.add(identity)
    return inventory


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValidationError("Duplicate JSON object key.")
        result[key] = value
    return result


def reject_constant(_value: str) -> object:
    raise ValidationError("Non-finite JSON numbers are forbidden.")


def input_parent(path: Path) -> int:
    if os.name != "posix":
        raise ValidationError("Safe inventory input currently requires POSIX.")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    descriptor = os.open("/", flags)
    try:
        for part in path.absolute().parent.parts[1:]:
            following = os.open(part, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = following
    except OSError:
        os.close(descriptor)
        raise
    return descriptor


def read_payload(path: Path) -> bytes:
    parent = input_parent(path)
    try:
        descriptor = os.open(
            path.name, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW, dir_fd=parent
        )
    finally:
        os.close(parent)
    with os.fdopen(descriptor, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValidationError("Inventory input must be a regular file.")
        payload = stream.read(MAX_BYTES + 1)
    if len(payload) > MAX_BYTES:
        raise ValidationError("Inventory exceeds the byte limit.")
    return payload


def load_inventory(path: Path) -> dict[str, object]:
    # Bound explicit regular-file reads; never resolve embedded references.
    payload = read_payload(path)
    value = json.loads(
        payload.decode("utf-8"),
        object_pairs_hook=unique_object,
        parse_constant=reject_constant,
    )
    return validate_inventory(value)


def evidence_kind(row: dict[str, object]) -> str:
    return cast(str, cast(dict[str, object], row["evidence"])["kind"])


def actual_complete(row: dict[str, object]) -> bool:
    return row["outcome"] == "complete" and evidence_kind(row) == "actual"


def automated_complete(row: dict[str, object]) -> bool:
    required = ("source_revision", "owner")
    return (
        actual_complete(row)
        and row.get("execution_mode") == "autonomous"
        and row.get("workflow_supported") is True
        and all(key in row for key in required)
    )


def evidence_counts(applicable: list[dict[str, object]]) -> dict[str, object]:
    evidence = Counter(evidence_kind(row) for row in applicable)
    completions = Counter(
        evidence_kind(row) for row in applicable if row["outcome"] == "complete"
    )
    return {
        "evidence_kind_counts": {key: evidence[key] for key in EVIDENCE_KINDS},
        "completed_by_evidence_kind": {key: completions[key] for key in EVIDENCE_KINDS},
    }


def summarize(
    rows: list[dict[str, object]], baseline_matched: bool = False
) -> dict[str, object]:
    applicable = [row for row in rows if row["applicable"]]
    denominator = len(applicable)
    numerator = sum(actual_complete(row) for row in applicable)
    outcomes = Counter(cast(str, row["outcome"]) for row in applicable)
    return {
        "total_rows": len(rows),
        "applicable_denominator": denominator,
        "supplied_actual_completed_numerator": numerator,
        "supplied_actual_completion_percentage": numerator / denominator * 100
        if denominator
        else None,
        **automation_metrics(applicable, baseline_matched),
        "externally_verified": False,
        "excluded_count": len(rows) - denominator,
        "outcome_counts": {key: outcomes[key] for key in OUTCOMES[:-1]},
        **evidence_counts(applicable),
        "workflow_supported_count": sum(
            row.get("workflow_supported") is True for row in applicable
        ),
        "workflow_support_unreported_count": sum(
            "workflow_supported" not in row for row in applicable
        ),
        "human_time_reduction_percentage": None,
        **execution_counts(applicable),
    }


def automation_metrics(
    applicable: list[dict[str, object]], baseline_matched: bool
) -> dict[str, object]:
    denominator = len(applicable)
    automated = sum(automated_complete(row) for row in applicable)
    return {
        "reported_automation_numerator": automated,
        "reported_automation_percentage": automated / denominator * 100
        if denominator
        else None,
        "target_percentage": 90,
        "reported_automation_target_met": (
            denominator > 0 and automated * 100 >= denominator * 90
        )
        if baseline_matched
        else None,
    }


def execution_counts(applicable: list[dict[str, object]]) -> dict[str, object]:
    return {
        "supplied_actual_completions_by_execution_mode": {
            mode: sum(
                actual_complete(row) and row.get("execution_mode") == mode
                for row in applicable
            )
            for mode in EXECUTION_MODES
        },
        "execution_mode_unreported_count": sum(
            "execution_mode" not in row for row in applicable
        ),
    }


def breakdown(
    rows: list[dict[str, object]], dimension: str, baseline_matched: bool = False
) -> list[dict[str, object]]:
    groups: dict[str, list[dict[str, object]]] = {}
    missing: list[dict[str, object]] = []
    for row in rows:
        if dimension in row:
            groups.setdefault(cast(str, row[dimension]), []).append(row)
        else:
            missing.append(row)
    result = [
        {"value": key, **summarize(groups[key], baseline_matched)}
        for key in sorted(groups)
    ]
    if missing:
        result.append({"value": None, **summarize(missing, baseline_matched)})
    return result


def denominator_contract(inventory: dict[str, object]) -> list[dict[str, object]]:
    fields = (*IDENTITY, "id", "applicable")
    rows = cast(list[dict[str, object]], inventory["rows"])
    return [
        {key: row[key] for key in fields}
        for row in sorted(rows, key=lambda item: cast(str, item["id"]))
    ]


def canonical_digest(value: object) -> str:
    canonical = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def baseline_contract(
    inventory: dict[str, object], baseline: object | None
) -> dict[str, object]:
    contract = denominator_contract(inventory)
    if baseline is None:
        return {
            "supplied": False,
            "matched": None,
            "denominator_sha256": canonical_digest(contract),
        }
    frozen = validate_inventory(baseline)
    if denominator_contract(frozen) != contract:
        raise ValidationError(
            "Current identities or applicability differ from baseline."
        )
    return {
        "supplied": True,
        "matched": True,
        "inventory_version": frozen["inventory_version"],
        "denominator_sha256": canonical_digest(contract),
    }


def build_report(value: object, baseline: object | None = None) -> dict[str, object]:
    """Validate and summarize a snapshot; supplied data is never modified."""
    inventory = validate_inventory(value)
    frozen = baseline_contract(inventory, baseline)
    baseline_matched = frozen["matched"] is True
    rows = sorted(
        cast(list[dict[str, object]], inventory["rows"]),
        key=lambda row: cast(str, row["id"]),
    )
    return {
        "schema_version": 1,
        "status": "REPORTED",
        "externally_verified": False,
        "inventory_version": inventory["inventory_version"],
        "inventory_sha256": canonical_digest({**inventory, "rows": rows}),
        "baseline": frozen,
        "summary": summarize(rows, baseline_matched),
        "breakdowns": {
            key: breakdown(rows, key, baseline_matched) for key in DIMENSIONS
        },
        "rows": rows,
        **row_indexes(rows),
        "limitations": list(LIMITATIONS),
    }


def row_indexes(rows: list[dict[str, object]]) -> dict[str, object]:
    applicable = applicability_rows(rows, True)
    return {
        "supplied_actual_completed_ids": [
            row["id"] for row in applicable if actual_complete(row)
        ],
        "reported_automated_ids": [
            row["id"] for row in applicable if automated_complete(row)
        ],
        "outstanding_automation_ids": [
            row["id"] for row in applicable if not automated_complete(row)
        ],
        "excluded_rows": applicability_rows(rows, False),
    }


def applicability_rows(
    rows: list[dict[str, object]], applicable: bool
) -> list[dict[str, object]]:
    return [row for row in rows if row["applicable"] is applicable]


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if not valid_arguments(args):
        print(
            "Usage: python3 automation_coverage.py INVENTORY.json [--baseline FILE]",
            file=sys.stderr,
        )
        return 2
    try:
        baseline = load_inventory(Path(args[2])) if len(args) == 3 else None
        report = build_report(load_inventory(Path(args[0])), baseline)
    except (OSError, ValueError, RecursionError):
        # Do not echo input paths, malformed JSON, or evidence into diagnostics.
        print(
            '{"status":"BLOCKED","error":"Invalid inventory or baseline mismatch."}',
            file=sys.stderr,
        )
        return 2
    print(json.dumps(report, sort_keys=True, indent=2, allow_nan=False))
    return 0


def valid_arguments(args: list[str]) -> bool:
    if len(args) not in (1, 3):
        return False
    return len(args) == 1 or args[1] == "--baseline"


if __name__ == "__main__":
    sys.exit(main())
