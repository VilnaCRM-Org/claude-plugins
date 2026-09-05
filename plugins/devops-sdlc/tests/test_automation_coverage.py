"""Exercise honest counting and fail-closed input handling without live services."""

from __future__ import annotations

import copy
import importlib
import io
import json
import os
import runpy
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "automation_coverage.py"
sys.path.insert(0, str(SCRIPT.parent))
reporter = importlib.import_module("automation_coverage")


def row(identifier="actual", **changes):
    result = {
        "id": identifier,
        "repository": "example/service",
        "target": identifier,
        "environment": "test",
        "operation": "validate",
        "applicable": True,
        "outcome": "complete",
        "evidence": {"kind": "actual", "reference": "opaque:run-1"},
        "exclusion_reason": None,
    }
    result.update(changes)
    return result


def inventory(rows=None):
    return {
        "schema_version": 1,
        "inventory_version": "baseline-1",
        "rows": [row()] if rows is None else rows,
    }


class ValidationTests(unittest.TestCase):
    def reject_row(self, **changes):
        with self.assertRaises(reporter.ValidationError):
            reporter.build_report(inventory([row(**changes)]))

    def test_exact_top_level_schema(self):
        for value in (None, [], "text", 1, True, {}, {**inventory(), "extra": 1}):
            with self.subTest(value=value), self.assertRaises(reporter.ValidationError):
                reporter.build_report(value)
        for version in (None, True, 1.0, "1", 0, 2, float("inf"), float("nan")):
            with self.subTest(version=version):
                value = inventory()
                value["schema_version"] = version
                with self.assertRaises(reporter.ValidationError):
                    reporter.build_report(value)

    def test_collection_bounds_and_row_schema(self):
        for rows in (None, {}, "rows", [None], [{}], [row(extra=1)]):
            with self.subTest(rows=rows), self.assertRaises(reporter.ValidationError):
                reporter.build_report({**inventory(), "rows": rows})
        with patch.object(reporter, "MAX_ROWS", 1):
            reporter.build_report(inventory([row()]))
            with self.assertRaises(reporter.ValidationError):
                reporter.build_report(inventory([row(), row("two")]))
        for key in reporter.REQUIRED_ROW:
            value = row()
            del value[key]
            with self.subTest(key=key), self.assertRaises(reporter.ValidationError):
                reporter.build_report(inventory([value]))

    def test_identifiers_and_text_bounds(self):
        invalid = (None, False, 7, [], {}, "", " ", " x", "x ", "a\nb", "\ud800")
        for key in (*reporter.IDENTITY, "id", *reporter.OPTIONAL_TEXT):
            for value in invalid:
                with self.subTest(key=key, value=value):
                    self.reject_row(**{key: value})
        with patch.object(reporter, "MAX_TEXT", 4):
            self.assertEqual(reporter.text_field("four"), "four")
            with self.assertRaises(reporter.ValidationError):
                reporter.text_field("fives")
        value = inventory()
        value["inventory_version"] = ""
        with self.assertRaises(reporter.ValidationError):
            reporter.build_report(value)

    def test_duplicate_ids_and_operational_identities(self):
        # New IDs must not allow duplicate operations to inflate the denominator.
        cases = ([row(), row(target="other")], [row(), row("two", target="actual")])
        for rows in cases:
            with self.subTest(rows=rows), self.assertRaises(reporter.ValidationError):
                reporter.build_report(inventory(rows))
        distinct = [row(), row("two", environment="production")]
        self.assertEqual(
            reporter.build_report(inventory(distinct))["summary"][
                "applicable_denominator"
            ],
            2,
        )

    def test_boolean_and_enum_types_are_strict(self):
        for value in (None, 0, 1, "true", [], {}):
            with self.subTest(value=value):
                self.reject_row(applicable=value)
                self.reject_row(workflow_supported=value)
        for value in ("passed", "COMPLETE", "", None, 1, []):
            with self.subTest(value=value):
                self.reject_row(outcome=value)
                self.reject_row(evidence={"kind": value, "reference": "trace"})

    def test_evidence_is_required_and_exact(self):
        for value in (
            None,
            [],
            {},
            {"kind": "actual"},
            {"kind": "actual", "reference": "ref", "extra": True},
        ):
            with self.subTest(value=value):
                self.reject_row(evidence=value)
        for kind in reporter.EVIDENCE_KINDS[:-1]:
            for reference in (None, "", " ", 1, [], {}):
                with self.subTest(kind=kind, reference=reference):
                    self.reject_row(evidence={"kind": kind, "reference": reference})
        self.reject_row(evidence={"kind": "none", "reference": "trace"})
        self.reject_row(evidence={"kind": "none", "reference": None})

    def test_exclusions_must_be_explicit_and_consistent(self):
        self.reject_row(exclusion_reason="Unavailable credentials")
        self.reject_row(outcome="excluded")
        self.reject_row(applicable=False)
        self.reject_row(applicable=False, exclusion_reason="Out of scope")
        for reason in ("", " ", None, 1):
            with self.subTest(reason=reason):
                self.reject_row(
                    applicable=False, outcome="excluded", exclusion_reason=reason
                )

    def test_optional_metadata_is_bounded_inert_data(self):
        value = row(
            engine="pulumi",
            risk="high",
            family="validation",
            source_revision="a" * 40,
            owner="team",
            command=["sh", "-c", "touch /must-not-run"],
            preconditions=[],
            workflow_supported=False,
        )
        self.assertEqual(reporter.build_report(inventory([value]))["rows"], [value])
        for key in ("command", "preconditions"):
            for value in (None, "run", {}, ["x"] * 257, [0], [""]):
                with self.subTest(key=key, value=value):
                    self.reject_row(**{key: value})
        reporter.build_report(
            inventory([row(command=["x"] * 256, preconditions=["reviewed"])])
        )


class ReportingTests(unittest.TestCase):
    def test_mixed_evidence_keeps_every_applicable_row(self):
        rows = [
            row(
                kind,
                evidence={"kind": kind, "reference": "opaque:trace"},
                workflow_supported=True,
            )
            for kind in reporter.EVIDENCE_KINDS[:-1]
        ]
        rows.extend(
            row(outcome, outcome=outcome, evidence={"kind": "none", "reference": None})
            for outcome in ("failed", "blocked", "skipped", "incomplete")
        )
        rows.append(
            row(
                "excluded",
                applicable=False,
                outcome="excluded",
                evidence={"kind": "none", "reference": None},
                exclusion_reason="No deployed environment",
            )
        )
        report = reporter.build_report(inventory(rows))
        summary = report["summary"]
        self.assertEqual(summary["applicable_denominator"], 9)
        self.assertEqual(summary["supplied_actual_completed_numerator"], 1)
        self.assertAlmostEqual(summary["supplied_actual_completion_percentage"], 100 / 9)
        self.assertFalse(summary["reported_automation_target_met"])
        self.assertEqual(summary["total_rows"], 10)
        self.assertEqual(summary["excluded_count"], 1)
        self.assertEqual(
            summary["outcome_counts"],
            {"complete": 5, "failed": 1, "blocked": 1, "skipped": 1, "incomplete": 1},
        )
        self.assertEqual(summary["evidence_kind_counts"]["none"], 4)
        self.assertEqual(
            summary["completed_by_evidence_kind"],
            {
                "actual": 1,
                "fixture": 1,
                "mock": 1,
                "simulated": 1,
                "documentation": 1,
                "none": 0,
            },
        )
        self.assertEqual(summary["workflow_supported_count"], 5)
        self.assertEqual(summary["workflow_support_unreported_count"], 4)
        self.assertIsNone(summary["human_time_reduction_percentage"])
        self.assertEqual(report["supplied_actual_completed_ids"], ["actual"])
        self.assertEqual(len(report["outstanding_automation_ids"]), 9)
        self.assertEqual(report["excluded_rows"], [rows[-1]])
        self.assertIn("not independently verified", " ".join(report["limitations"]))
        self.assertIn("human-time reduction", " ".join(report["limitations"]))
        self.assertIn("deployment success", " ".join(report["limitations"]))
        self.assertIn("comprehensive coverage", " ".join(report["limitations"]))

    def test_zero_denominator_never_claims_achievement(self):
        excluded = row(
            applicable=False, outcome="excluded", exclusion_reason="Retired target"
        )
        for rows in ([], [excluded]):
            with self.subTest(rows=rows):
                summary = reporter.build_report(inventory(rows))["summary"]
                self.assertEqual(summary["applicable_denominator"], 0)
                self.assertEqual(summary["supplied_actual_completed_numerator"], 0)
                self.assertIsNone(summary["supplied_actual_completion_percentage"])
                self.assertFalse(summary["reported_automation_target_met"])

    def test_target_boundary_uses_actual_unrounded_ratio(self):
        for completed, total, expected in (
            (9, 10, True),
            (8, 9, False),
            (1, 1, True),
            (0, 1, False),
            (899, 1000, False),
        ):
            with self.subTest(completed=completed, total=total):
                rows = [
                    row(
                        str(index),
                        outcome="complete" if index < completed else "blocked",
                        execution_mode="autonomous",
                        workflow_supported=True,
                        source_revision="a" * 40,
                        owner="platform",
                    )
                    for index in range(total)
                ]
                summary = reporter.build_report(inventory(rows), inventory(rows))["summary"]
                self.assertEqual(summary["supplied_actual_completed_numerator"], completed)
                self.assertEqual(
                    summary["supplied_actual_completion_percentage"], completed / total * 100
                )
                self.assertEqual(summary["target_percentage"], 90)
                self.assertEqual(summary["reported_automation_target_met"], expected)

    def test_breakdowns_reconcile_without_hiding_missing_metadata(self):
        rows = [
            row("one", engine="pulumi", risk="high", family="preview"),
            row(
                "two",
                engine="terraform",
                risk="low",
                family="validate",
                environment="production",
                outcome="blocked",
            ),
            row(
                "three",
                engine="pulumi",
                risk="high",
                family="preview",
                applicable=False,
                outcome="excluded",
                exclusion_reason="Retired",
            ),
            row("four", outcome="skipped"),
        ]
        report = reporter.build_report(inventory(rows))
        for dimension in reporter.DIMENSIONS:
            groups = report["breakdowns"][dimension]
            with self.subTest(dimension=dimension):
                self.assertEqual(sum(g["total_rows"] for g in groups), 4)
                self.assertEqual(sum(g["applicable_denominator"] for g in groups), 3)
                self.assertEqual(
                    sum(g["supplied_actual_completed_numerator"] for g in groups), 1
                )
                self.assertEqual(sum(g["excluded_count"] for g in groups), 1)
        engines = report["breakdowns"]["engine"]
        self.assertEqual([g["value"] for g in engines], ["pulumi", "terraform", None])
        self.assertEqual(engines[0]["supplied_actual_completion_percentage"], 100)
        self.assertEqual(engines[1]["outcome_counts"]["blocked"], 1)
        self.assertEqual(engines[2]["outcome_counts"]["skipped"], 1)

    def test_deterministic_snapshot_and_immutable_input(self):
        value = inventory([row("z"), row("a")])
        before = copy.deepcopy(value)
        report = reporter.build_report(value)
        self.assertEqual(value, before)
        value["rows"].reverse()
        self.assertEqual(report, reporter.build_report(value))
        self.assertEqual([item["id"] for item in report["rows"]], ["a", "z"])
        value["inventory_version"] = "baseline-2"
        self.assertNotEqual(
            report["inventory_sha256"], reporter.build_report(value)["inventory_sha256"]
        )
        self.assertEqual(len(report["inventory_sha256"]), 64)


class CliTests(unittest.TestCase):
    def call_main(self, args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = reporter.main(args)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_cli_reads_only_input_and_never_executes_references(self):
        # Block network, subprocess and environment access; permit exactly one file.
        value = inventory(
            [
                row(
                    command=["touch", "/must-not-run"],
                    evidence={
                        "kind": "actual",
                        "reference": "https://invalid.example/../../secret",
                    },
                )
            ]
        )
        payload = json.dumps(value).encode()
        opened = []

        def read_input(path):
            self.assertEqual(path, Path("inventory.json"))
            opened.append(path)
            return payload

        with (
            patch.object(reporter, "read_payload", read_input),
            patch("builtins.open", side_effect=AssertionError("Unexpected read")),
            patch("subprocess.Popen", side_effect=AssertionError("Execution")),
            patch("socket.socket", side_effect=AssertionError("Network")),
            patch("os.getenv", side_effect=AssertionError("Environment")),
        ):
            code, stdout, stderr = self.call_main(["inventory.json"])
        self.assertEqual((code, stderr), (0, ""))
        self.assertEqual(opened, [Path("inventory.json")])
        self.assertEqual(json.loads(stdout), reporter.build_report(value))

    def test_cli_entrypoint_and_file_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "inventory.json"
            payload = json.dumps(inventory()).encode()
            path.write_bytes(payload)
            before = path.stat()
            stdout = io.StringIO()
            with (
                patch.object(sys, "argv", [str(SCRIPT), str(path)]),
                redirect_stdout(stdout),
                self.assertRaises(SystemExit) as result,
            ):
                runpy.run_path(str(SCRIPT), run_name="__main__")
            self.assertEqual(result.exception.code, 0)
            self.assertIsNone(json.loads(stdout.getvalue())["summary"]["reported_automation_target_met"])
            self.assertEqual(path.read_bytes(), payload)
            self.assertEqual(path.stat().st_mtime_ns, before.st_mtime_ns)

    def test_usage_and_unreadable_input(self):
        for args in ([], ["one", "two"]):
            with self.subTest(args=args):
                code, stdout, stderr = self.call_main(args)
                self.assertEqual((code, stdout), (2, ""))
                self.assertIn("Usage:", stderr)
        with patch.object(reporter, "read_payload", side_effect=OSError("sensitive filename")):
            code, stdout, stderr = self.call_main(["secret-path"])
        self.assertEqual((code, stdout), (2, ""))
        self.assertEqual(
            json.loads(stderr), {"status": "BLOCKED", "error": "Invalid inventory or baseline mismatch."}
        )

    def test_invalid_json_fails_without_echoing_values(self):
        payloads = [
            b"not JSON secret",
            b"\xff",
            b"{} trailing",
            b'"scalar"',
            b'{"schema_version":1,"schema_version":1}',
            json.dumps(inventory())
            .replace('"kind": "actual"', '"kind": "actual", "kind": "mock"')
            .encode(),
            b'{"secret":NaN}',
            b'{"secret":Infinity}',
            b'{"secret":-Infinity}',
            b'{"secret":1e999}',
            b"[" * 2000 + b"]" * 2000,
            b'{"secret":' + b"1" * 5000 + b"}",
        ]
        for payload in payloads:
            with (
                self.subTest(payload=payload[:40]),
                patch.object(reporter, "read_payload", return_value=payload),
            ):
                code, stdout, stderr = self.call_main(["input"])
                self.assertEqual((code, stdout), (2, ""))
                self.assertEqual(
                    json.loads(stderr), {"status": "BLOCKED", "error": "Invalid inventory or baseline mismatch."}
                )

    def test_input_byte_limit(self):
        payload = json.dumps(inventory()).encode()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.json"
            path.write_bytes(payload)
            with patch.object(reporter, "MAX_BYTES", len(payload)):
                self.assertEqual(self.call_main([str(path)])[0], 0)
            with patch.object(reporter, "MAX_BYTES", len(payload) - 1):
                self.assertEqual(self.call_main([str(path)])[0], 2)


if __name__ == "__main__":
    unittest.main()
