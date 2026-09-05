#!/usr/bin/env python3
"""Calibrated, three-vote prompt assessment through an isolated agent CLI."""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import re
import statistics
import sys
import tempfile
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

REPOSITORY = Path(__file__).resolve().parents[3]
PLUGIN = Path(__file__).resolve().parents[1]
for folder in (
    REPOSITORY / "tools/plugin-quality/lint",
    REPOSITORY / "tools/plugin-quality/judge",
    PLUGIN / "scripts",
):
    sys.path.insert(0, str(folder))

import _model  # noqa: E402
import agent_cli  # noqa: E402
import calibration  # noqa: E402
import judge  # noqa: E402
import rubrics  # noqa: E402

VOTES = 3
EXPECTED_ARTIFACTS = 31
MAX_FILES = 500
MAX_FILE_BYTES = 2_000_000
MAX_CITATIONS = 512
SKIPPED_DIRECTORIES = {"__pycache__", ".pytest_cache", ".ruff_cache"}
CONTEXT = (
    "Scope: a reusable DevOps infrastructure plugin for Terraform/Terraspace and "
    "Python/Pulumi, usable through Claude or Codex. Interpret legacy PHP examples "
    "in the shared rubric as illustrative, not requirements to add PHP behavior. "
    "Preserve every rubric threshold. Evaluate only supplied artifact text and "
    "authoritative inventory; do not infer unseen implementation or test success."
)
SECRET_RE = re.compile(
    r"(?i)\b([a-z0-9_-]*(?:api[_-]?key|secret|token|password)[a-z0-9_-]*)\b"
    r"\s*[:=]\s*[^\s,;]+"
)


class AssessmentError(ValueError):
    """A safe diagnostic containing no raw agent response."""


@dataclasses.dataclass(frozen=True)
class Settings:
    backend: str = "auto"
    prefer: str = "claude"
    model: str | None = None
    timeout: int = 300
    dimensions: tuple[str, ...] = ()
    jobs: int = 3


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def json_digest(value: Any) -> str:
    return digest(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def safe_root(root: Path) -> Path:
    root = root.absolute()
    if not root.is_dir() or any(item.is_symlink() for item in (root, *root.parents)):
        raise AssessmentError("Plugin root must be an existing non-symlink directory.")
    return root


def plugin_snapshot(root: Path) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in SKIPPED_DIRECTORIES for part in relative.parts):
            continue
        if path.is_symlink():
            raise AssessmentError("Plugin inputs must not contain symlinks.")
        if not path.is_file():
            continue
        if len(hashes) >= MAX_FILES or path.stat().st_size > MAX_FILE_BYTES:
            raise AssessmentError("Plugin inputs exceed assessment bounds.")
        hashes[relative.as_posix()] = digest(path.read_bytes())
    return hashes


def rubric_dimensions(settings: Settings) -> list[rubrics.Dimension]:
    unknown = set(settings.dimensions) - set(rubrics.DIMENSIONS_BY_ID)
    if unknown or len(set(settings.dimensions)) != len(settings.dimensions):
        raise AssessmentError("Requested rubric dimensions are unknown or duplicated.")
    return [
        dimension
        for dimension in rubrics.DIMENSIONS
        if not settings.dimensions or dimension.id in settings.dimensions
    ]


def validate_settings(settings: Settings, mode: str) -> None:
    if settings.backend not in ("auto", *agent_cli.BACKENDS):
        raise AssessmentError("Unknown assessment backend.")
    if settings.prefer not in agent_cli.BACKENDS or mode not in {"live", "fixture"}:
        raise AssessmentError("Unknown backend preference or evidence mode.")
    if type(settings.timeout) is not int or not 1 <= settings.timeout <= 3600:
        raise AssessmentError("Timeout must be an integer between 1 and 3600.")
    if type(settings.jobs) is not int or not 1 <= settings.jobs <= 4:
        raise AssessmentError("Jobs must be an integer between 1 and 4.")
    rubric_dimensions(settings)


def citation_choices(artifact_raw: str) -> list[str]:
    choices = []
    for line in artifact_raw.splitlines():
        # Codex strict schemas reject escaped quote literals in enum strings.
        # Split, never rewrite: every permitted fragment remains exact source text.
        for literal in re.split(r'["\\\x00-\x1f]', line):
            for start in range(0, len(literal), 120):
                chunk = literal[start : start + 120]
                if chunk.strip() and chunk not in choices:
                    choices.append(chunk)
                    if len(choices) == MAX_CITATIONS:
                        return choices
    return choices


def verdict_schema(dimensions: list[rubrics.Dimension], artifact_raw: str = "") -> dict:
    choices = citation_choices(artifact_raw)
    if artifact_raw and not choices:
        raise AssessmentError("Artifact has no literal-safe exact citation fragments.")
    entry = {
        "type": "object",
        "additionalProperties": False,
        "required": ["score", "evidence", "citation"],
        "properties": {
            "score": {"type": "integer", "minimum": 1, "maximum": 5},
            "evidence": {"type": "string", "minLength": 1, "maxLength": 240},
            "citation": (
                {"type": "string", "enum": choices}
                if artifact_raw
                else {"type": "string", "minLength": 1, "maxLength": 120}
            ),
        },
    }
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["dimensions"],
        "$defs": {"assessment_entry": entry},
        "properties": {
            "dimensions": {
                "type": "object",
                "additionalProperties": False,
                "required": [dimension.id for dimension in dimensions],
                "properties": {
                    dimension.id: {"$ref": "#/$defs/assessment_entry"}
                    for dimension in dimensions
                },
            }
        },
    }


def strict_verdict(
    value: Any, dimensions: list[rubrics.Dimension], artifact_raw: str
) -> dict:
    if type(value) is not dict or set(value) != {"dimensions"}:
        raise AssessmentError("Verdict must contain exactly the requested dimensions.")
    try:
        judge.validate_verdict(value, dimensions)
    except judge.JudgeError as exc:
        raise AssessmentError("Verdict failed shared rubric validation.") from exc
    for dimension in dimensions:
        try:
            validate_entry(value["dimensions"][dimension.id], artifact_raw)
        except AssessmentError as exc:
            raise AssessmentError(f"Verdict {dimension.id}: {exc}") from exc
    return value


def validate_entry(entry: dict, artifact_raw: str) -> None:
    if type(entry) is not dict or set(entry) != {"score", "evidence", "citation"}:
        raise AssessmentError("Verdict dimension has missing or extra fields.")
    evidence, citation = entry["evidence"], entry["citation"]
    if (
        type(evidence) is not str
        or len(evidence) > 240
        or any(ord(char) < 32 for char in evidence)
    ):
        raise AssessmentError("Verdict evidence must be bounded single-line text.")
    if (
        type(citation) is not str
        or not citation
        or len(citation) > 120
        or any(ord(char) < 32 for char in citation)
        or citation not in artifact_raw
    ):
        raise AssessmentError(
            "Verdict citation must be a bounded exact artifact substring."
        )


def backend_identity(result: dict) -> tuple[str, str, str, str]:
    backend, version, observed, requested = (
        result.get("backend"),
        result.get("version"),
        result.get("observed_model"),
        result.get("requested_model"),
    )
    if backend not in agent_cli.BACKENDS or type(version) is not str or not version:
        raise AssessmentError("Agent result lacks observed backend/version identity.")
    if observed is not None:
        if type(observed) is str and observed:
            return backend, version, "observed", observed
        raise AssessmentError("Agent result has an invalid observed model identity.")
    if requested is not None:
        if type(requested) is str and requested:
            return backend, version, "requested", requested
        raise AssessmentError("Agent result has an invalid requested model identity.")
    raise AssessmentError(
        "Agent result lacks observed or explicitly requested model identity."
    )


def redact_evidence(value: str) -> str:
    return SECRET_RE.sub(r"\1=[REDACTED]", value)


def stored_dimensions(verdict: dict) -> dict:
    return {
        identifier: {
            "score": entry["score"],
            "evidence": redact_evidence(entry["evidence"]),
            "evidence_sha256": digest(entry["evidence"].encode()),
            "citation": redact_evidence(entry["citation"]),
            "citation_sha256": digest(entry["citation"].encode()),
        }
        for identifier, entry in verdict["dimensions"].items()
    }


def vote_metadata(result: dict, number: int, mode: str) -> dict:
    return {
        "vote": number,
        "evidence_mode": mode,
        "backend": result.get("backend"),
        "version": result.get("version"),
        "model": result.get("model"),
        "observed_model": result.get("observed_model"),
        "model_source": result.get("model_source", "adapter-reported"),
        "requested_model": result.get("requested_model"),
        "fallback": result.get("fallback", []),
        "status": result.get("status"),
    }


def one_vote(
    artifact: _model.Artifact,
    dimensions: list[rubrics.Dimension],
    context: str,
    settings: Settings,
    number: int,
    mode: str,
) -> dict:
    citation_lines = citation_choices(artifact.raw)
    prompt = (
        judge.build_prompt(artifact, dimensions, context)
        + "\n\n"
        + (
            "RESPONSE CONTRACT: Fields are score, evidence, and citation only."
            " citation is a non-empty single-line substring copied from ARTIFACT."
            " Never cite CONTEXT, a rubric, a link target, or a paraphrase."
            " Limit citation to 120 characters and verify it occurs in ARTIFACT."
            " evidence must be single-line and at most 240 characters."
        )
        + "\nAllowed exact citation fragments (copy one verbatim):\n"
        + "\n".join(citation_lines)
    )
    attempts = []
    backend = settings.backend
    for repair in range(judge.MAX_REPROMPTS + 1):
        with tempfile.TemporaryDirectory(prefix="devops-prompt-judge-") as directory:
            result = agent_cli.run_prompt(
                prompt,
                verdict_schema(dimensions, artifact.raw),
                Path(directory),
                backend=backend,
                prefer=settings.prefer,
                model=settings.model,
                plugin_root=None,
                timeout=settings.timeout,
            )
        metadata = vote_metadata(result, number, mode)
        if result.get("status") != "COMPLETED" or result.get("plugin_mode") != "none":
            return {
                **metadata,
                "status": "ERROR",
                "error": "Agent evaluation unavailable.",
                "invalid_attempts": attempts,
            }
        try:
            backend_identity(result)
        except AssessmentError:
            return {
                **metadata,
                "status": "ERROR",
                "identity_unverified": True,
                "error": "Agent model identity is unavailable.",
                "invalid_attempts": attempts,
            }
        if (
            mode == "live"
            and result.get("backend") == "codex"
            and not result.get("requested_model")
        ):
            return {
                **metadata,
                "status": "ERROR",
                "identity_unverified": True,
                "error": "Codex live assessment requires an explicit --model.",
                "invalid_attempts": attempts,
            }
        try:
            verdict = strict_verdict(result.get("output"), dimensions, artifact.raw)
        except AssessmentError as exc:
            attempts.append(
                {
                    "status": "INVALID",
                    "reason": str(exc),
                    "output_sha256": json_digest(result.get("output")),
                }
            )
            if repair == judge.MAX_REPROMPTS:
                return {
                    **metadata,
                    "status": "ERROR",
                    "error": str(exc),
                    "invalid_attempts": attempts,
                }
            backend = result["backend"]
            prompt += (
                "\nFORMAT REPAIR: Return corrected JSON only; copy citations "
                "verbatim from allowed fragments."
            )
            continue
        return {
            **metadata,
            "status": "SCORED",
            "dimensions": stored_dimensions(verdict),
            "invalid_attempts": attempts,
        }
    raise AssertionError("unreachable")


def collect_votes(
    artifact: _model.Artifact,
    dimensions: list[rubrics.Dimension],
    context: str,
    settings: Settings,
    mode: str,
) -> list[dict]:
    votes = []
    for number in range(1, VOTES + 1):
        vote = one_vote(artifact, dimensions, context, settings, number, mode)
        votes.append(vote)
        if vote["status"] == "ERROR":
            break
    return votes


def complete_votes(votes: list[dict]) -> bool:
    return len(votes) == VOTES and all(vote["status"] == "SCORED" for vote in votes)


def median_score(votes: list[dict], dimension: str) -> int:
    return int(
        statistics.median(vote["dimensions"][dimension]["score"] for vote in votes)
    )


def calibration_inventory() -> list[calibration.CalibrationCase]:
    critical = {dimension.id for dimension in rubrics.DIMENSIONS if dimension.critical}
    if critical != set(calibration.CRITICAL_DIMENSION_IDS):
        raise AssessmentError("Critical rubric dimensions lack a matching calibration.")
    cases = []
    for dimension_id in sorted(critical):
        pair = calibration.cases_for(dimension_id)
        if len(pair) != 2 or {case.polarity for case in pair} != {"P", "N"}:
            raise AssessmentError(
                "Every critical dimension needs one P and one N case."
            )
        cases.extend(pair)
    return cases


def calibrate(settings: Settings, mode: str) -> list[dict]:
    return parallel_rows(
        calibration_inventory(),
        lambda case: calibrate_case(case, settings, mode),
        settings.jobs,
    )


def parallel_rows(items: list, worker: Callable[[Any], dict], jobs: int) -> list[dict]:
    results = {}
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {
            executor.submit(worker, item): index for index, item in enumerate(items)
        }
        for future in as_completed(futures):
            results[futures[future]] = future.result()
    return [results[index] for index in range(len(items))]


def progress(label: str, status: str, mode: str) -> None:
    if mode == "live":
        print(f"{label}: {status}", file=sys.stderr, flush=True)


def progress_failures(row: dict, mode: str) -> None:
    if mode != "live" or row.get("status") != "FAILED":
        return
    for dimension in row["dimensions"]:
        if dimension["passed"]:
            continue
        evidence = [
            vote["dimensions"][dimension["id"]]["evidence"] for vote in row["votes"]
        ]
        print(
            f"artifact {row['path']} {dimension['id']}: scores={dimension['scores']} "
            f"evidence={evidence}",
            file=sys.stderr,
            flush=True,
        )


def progress_error(row: dict, mode: str) -> None:
    if mode == "live" and row.get("status") == "ERROR" and "error" in row:
        print(
            f"artifact {row['path']} error: {row['error']}",
            file=sys.stderr,
            flush=True,
        )


def calibrate_case(
    case: calibration.CalibrationCase, settings: Settings, mode: str
) -> dict:
    dimension = rubrics.DIMENSIONS_BY_ID[case.dimension_id]
    votes = collect_votes(
        case.artifact(), [dimension], case.extra_context, settings, mode
    )
    row = calibration_row(case, dimension, votes)
    progress(f"calibration {case.dimension_id}/{case.polarity}", row["status"], mode)
    return row


def calibration_row(
    case: calibration.CalibrationCase, dimension: rubrics.Dimension, votes: list[dict]
) -> dict:
    score = median_score(votes, dimension.id) if complete_votes(votes) else None
    passed = False
    if score is not None:
        passed = (
            score >= dimension.floor
            if case.polarity == "P"
            else score <= dimension.block_floor
        )
    return {
        "dimension": dimension.id,
        "polarity": case.polarity,
        "case_sha256": digest((case.raw + case.extra_context).encode()),
        "median": score,
        "floor": dimension.floor,
        "block_floor": dimension.block_floor,
        "status": "PASSED" if passed else "FAILED",
        "votes": votes,
    }


def calibrated_identity(rows: list[dict]) -> tuple[str, str, str, str] | None:
    if len(rows) != len(calibration_inventory()):
        return None
    if any(row["status"] != "PASSED" for row in rows):
        return None
    identities = {backend_identity(vote) for row in rows for vote in row["votes"]}
    return next(iter(identities)) if len(identities) == 1 else None


def dimension_results(
    votes: list[dict], dimensions: list[rubrics.Dimension]
) -> list[dict]:
    rows = []
    for dimension in dimensions:
        scores = [vote["dimensions"][dimension.id]["score"] for vote in votes]
        median = median_score(votes, dimension.id)
        blocked = dimension.critical and min(scores) <= dimension.block_floor
        rows.append(
            {
                "id": dimension.id,
                "median": median,
                "scores": scores,
                "floor": dimension.floor,
                "critical": dimension.critical,
                "block_floor": dimension.block_floor,
                "critical_block": blocked,
                "passed": median >= dimension.floor and not blocked,
            }
        )
    return rows


def assess_artifact(
    artifact: _model.Artifact,
    dimensions: list[rubrics.Dimension],
    context: str,
    settings: Settings,
    mode: str,
    identity: tuple,
) -> dict:
    row: dict[str, Any] = {
        "path": artifact.path.relative_to(artifact.plugin_root).as_posix(),
        "kind": artifact.kind,
        "name": artifact.name,
        "sha256": digest(artifact.raw.encode()),
        "prompt_text_sha256": digest(artifact.raw.encode()),
        "requested_dimensions": [dimension.id for dimension in dimensions],
        "votes": [],
        "dimensions": [],
        "status": "NOT_REQUESTED",
    }
    if not dimensions:
        return row
    votes = collect_votes(artifact, dimensions, context, settings, mode)
    row["votes"] = votes
    if not complete_votes(votes):
        return {**row, "status": "ERROR"}
    if any(backend_identity(vote) != identity for vote in votes):
        return {
            **row,
            "status": "ERROR",
            "error": "Uncalibrated backend/model identity.",
        }
    rows = dimension_results(votes, dimensions)
    return {
        **row,
        "dimensions": rows,
        "status": "PASSED" if all(item["passed"] for item in rows) else "FAILED",
    }


def artifact_inventory(root: Path, snapshot: dict[str, str]) -> list[_model.Artifact]:
    artifacts = _model.discover(root)
    if len(artifacts) != EXPECTED_ARTIFACTS:
        raise AssessmentError("Prompt inventory differs from the 31-artifact baseline.")
    if any(
        artifact.frontmatter_error or not artifact.raw.strip() for artifact in artifacts
    ):
        raise AssessmentError("Prompt inventory contains malformed or empty artifacts.")
    if any(
        snapshot.get(artifact.path.relative_to(root).as_posix())
        != digest(artifact.raw.encode())
        for artifact in artifacts
    ):
        raise AssessmentError("Artifact text differs from the initial input snapshot.")
    return artifacts


def assessment_context(artifacts: list[_model.Artifact]) -> str:
    names = sorted(artifact.name for artifact in artifacts if artifact.kind == "skill")
    return CONTEXT + "\nAuthoritative shipped skills: " + ", ".join(names)


def coverage(rows: list[dict], mode: str) -> dict:
    requested = sum(len(row["requested_dimensions"]) for row in rows)
    assessed = sum(len(row["dimensions"]) for row in rows)
    passed = sum(sum(item["passed"] for item in row["dimensions"]) for row in rows)
    return {
        "requested_dimension_pairs": requested,
        "assessed_dimension_pairs": assessed,
        "passing_dimension_pairs": passed,
        "live_assessed_dimension_pairs": assessed if mode == "live" else 0,
        "live_passing_dimension_pairs": passed if mode == "live" else 0,
        "note": (
            "Coverage concerns only requested prompt dimensions, not runtime behavior."
        ),
    }


def base_report(root: Path, snapshot: dict, settings: Settings, mode: str) -> dict:
    return {
        "schema_version": 1,
        "kind": "prompt-artifact-assessment",
        "evidence_mode": mode,
        "created_at": int(time.time()),
        "plugin": root.name,
        "plugin_sha256": json_digest(snapshot),
        "inputs": snapshot,
        "rubric_sha256": json_digest(
            [dataclasses.asdict(d) for d in rubrics.DIMENSIONS]
        ),
        "settings": dataclasses.asdict(settings),
        "votes_required": VOTES,
        "policy": (
            "Every median meets its floor; any critical vote <= block_floor blocks."
        ),
        "calibration": [],
        "artifacts": [],
        "status": "BLOCKED",
    }


def evaluate(root: Path, settings: Settings, *, mode: str = "live") -> dict:
    validate_settings(settings, mode)
    root = safe_root(root)
    snapshot = plugin_snapshot(root)
    artifacts = artifact_inventory(root, snapshot)
    dimensions = rubric_dimensions(settings)
    report = base_report(root, snapshot, settings, mode)
    report["calibration"] = calibrate(settings, mode)
    identity = calibrated_identity(report["calibration"])
    rows = evaluate_rows(artifacts, dimensions, settings, mode, identity)
    report.update(artifacts=rows, coverage=coverage(rows, mode))
    if identity is None:
        report["identity_unverified"] = any(
            vote.get("identity_unverified")
            for row in report["calibration"]
            for vote in row["votes"]
        )
        report["error"] = (
            "Mandatory calibration failed or model identity is unverified."
        )
        return report
    if plugin_snapshot(root) != snapshot:
        report["error"] = "Plugin inputs changed during assessment."
        return report
    outcomes = [row["status"] for row in rows if row["status"] != "NOT_REQUESTED"]
    passed = bool(outcomes) and all(status == "PASSED" for status in outcomes)
    report["status"] = (
        "PARTIAL"
        if passed and settings.dimensions
        else "PASSED"
        if passed
        else "FAILED"
    )
    return report


def evaluate_rows(
    artifacts: list[_model.Artifact],
    dimensions: list[rubrics.Dimension],
    settings: Settings,
    mode: str,
    identity: tuple | None,
) -> list[dict]:
    context = assessment_context(artifacts)
    return parallel_rows(
        artifacts,
        lambda artifact: evaluate_one(
            artifact, dimensions, context, settings, mode, identity
        ),
        settings.jobs,
    )


def evaluate_one(
    artifact: _model.Artifact,
    dimensions: list[rubrics.Dimension],
    context: str,
    settings: Settings,
    mode: str,
    identity: tuple | None,
) -> dict:
    row: dict[str, Any]
    requested = [d for d in dimensions if d.applies(artifact.kind, artifact.name)]
    if identity is None:
        row = {
            "path": artifact.path.relative_to(artifact.plugin_root).as_posix(),
            "sha256": digest(artifact.raw.encode()),
            "status": "BLOCKED",
            "requested_dimensions": [d.id for d in requested],
            "votes": [],
            "dimensions": [],
        }
    else:
        row = assess_artifact(artifact, requested, context, settings, mode, identity)
    progress(f"artifact {row['path']}", row["status"], mode)
    progress_failures(row, mode)
    progress_error(row, mode)
    return row


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin-root", type=Path, default=PLUGIN)
    parser.add_argument(
        "--backend", choices=("auto", *agent_cli.BACKENDS), default="auto"
    )
    parser.add_argument("--prefer", choices=agent_cli.BACKENDS, default="claude")
    parser.add_argument("--model")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--dimensions", default="")
    parser.add_argument("--jobs", type=int, default=3)
    args = parser.parse_args(argv)
    try:
        settings = Settings(
            args.backend,
            args.prefer,
            args.model,
            args.timeout,
            tuple(args.dimensions.split(",")) if args.dimensions else (),
            args.jobs,
        )
        report = evaluate(args.plugin_root, settings)
    except (AssessmentError, OSError, UnicodeError, ValueError):
        report = {
            "status": "BLOCKED",
            "evidence_mode": "live",
            "error": "Invalid assessment inputs or unavailable evaluation.",
        }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["status"] == "PASSED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
