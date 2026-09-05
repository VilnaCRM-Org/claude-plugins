"""Deterministic behavior-judge contracts, including failure paths."""

from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "behavior_judge", HERE / "behavior_judge.py"
)
judge = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(judge)


def envelope(result: object, error: bool = False) -> str:
    return json.dumps({"result": json.dumps(result), "is_error": error})


class ScenarioTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = judge.load_catalog(HERE / "scenarios.json")
        cls.scenario = cls.catalog["scenarios"][0]

    def verdict(self, status: str = "PASS") -> str:
        value = status == "PASS"
        result = {
            "verdict": status,
            "must": {key: value for key in self.scenario["must"]},
            "must_not": {key: value for key in self.scenario["must_not"]},
            "evidence": "Observed fixture response.",
        }
        return result

    def test_catalog_and_requirement_coverage(self):
        ids = {item["id"] for item in self.catalog["scenarios"]}
        self.assertGreaterEqual(len(ids), 20)
        self.assertTrue(
            {
                "terraform-stale-plan",
                "review-pagination",
                "untrusted-prompt",
                "observability-gate",
            }
            <= ids
        )
        self.assertEqual(set(self.catalog["requirement_map"]), ids)

    def test_verdict_rejects_literal_bool_schema_and_logic_failures(self):
        for mutate in (
            lambda payload: payload["result"]["must"].update(
                {self.scenario["must"][0]: "true"}
            ),
            lambda payload: payload["result"].update({"extra": True}),
            lambda payload: payload["result"]["must"].update(
                {self.scenario["must"][0]: False}
            ),
        ):
            payload = {"result": self.verdict()}
            mutate(payload)
            with self.assertRaises(ValueError):
                judge.parse_verdict(envelope(payload["result"]), self.scenario)

    def test_verdict_rejects_empty_list_null_and_error_envelopes(self):
        for raw in ("[]", "null", envelope(""), envelope({}, True)):
            with self.assertRaises(ValueError):
                judge.parse_verdict(raw, self.scenario)

    def args(self):
        return type(
            "Args",
            (),
            {
                "backend": "auto",
                "prefer": "claude",
                "model": None,
                "judge_model": None,
                "timeout": 1,
                "plugin_dir": HERE.parent,
                "selection": {"backend": "codex"},
                "scenarios": HERE / "scenarios.json",
            },
        )()

    def completed(self, output):
        return {
            "status": "COMPLETED",
            "output": output,
            "backend": "codex",
            "version": "fixture",
            "model": None,
            "fallback": [],
        }

    def test_valid_pass_and_fail_are_accepted(self):
        for status in ("PASS", "FAIL"):
            self.assertEqual(
                judge.parse_verdict(envelope(self.verdict(status)), self.scenario)[
                    "verdict"
                ],
                status,
            )

    def test_adapter_isolation(self):
        adapter = mock.Mock()
        with mock.patch.object(judge, "runtime", return_value=adapter):
            judge.invoke("prompt", self.args(), HERE, {}, HERE.parent)
            self.assertEqual(
                adapter.run_prompt.call_args.kwargs["plugin_root"], HERE.parent
            )
            judge.invoke("review", self.args(), HERE, {})
            self.assertIsNone(adapter.run_prompt.call_args.kwargs["plugin_root"])
            self.assertEqual(adapter.run_prompt.call_args.kwargs["backend"], "auto")

    def test_success_and_negative_verdict(self):
        for status in ("PASS", "FAIL"):
            with mock.patch.object(
                judge,
                "invoke",
                side_effect=[
                    self.completed({"response": "Proposed decisions."}),
                    self.completed(self.verdict(status)),
                ],
            ) as invoke:
                row = judge.run_one(self.scenario, self.args())
            self.assertEqual(row["status"], status)
            self.assertEqual(row["runner_backend"], "codex")
            self.assertEqual(len(invoke.call_args_list[0].args), 5)
            self.assertEqual(len(invoke.call_args_list[1].args), 4)

    def test_timeout_unavailable_and_malformed_runner(self):
        for result in (
            {"status": "TIMEOUT"},
            {"status": "BLOCKED", "reason": "not logged in"},
            self.completed({"response": ""}),
            self.completed({}),
            self.completed({"response": 1}),
        ):
            with mock.patch.object(judge, "invoke", return_value=result) as invoke:
                row = judge.run_one(self.scenario, self.args())
            self.assertEqual(row["status"], "ERROR")
            self.assertEqual(row["stage"], "runner")
            self.assertEqual(invoke.call_count, 1)

    def test_inconsistent_judge_is_error(self):
        bad = self.verdict()
        bad["must"][self.scenario["must"][0]] = False
        with mock.patch.object(
            judge,
            "invoke",
            side_effect=[
                self.completed({"response": "candidate"}),
                self.completed(bad),
            ],
        ):
            row = judge.run_one(self.scenario, self.args())
        self.assertEqual(row["status"], "ERROR")
        self.assertEqual(row["stage"], "judge")

    def test_always_pass_calibration_rejected(self):
        for case in self.catalog["calibration"]:
            verdict = {
                "verdict": "PASS",
                "must": dict.fromkeys(case["must"], True),
                "must_not": dict.fromkeys(case["must_not"], True),
                "evidence": "fixture",
            }
            with mock.patch.object(
                judge, "invoke", return_value=self.completed(verdict)
            ):
                row = judge.run_calibration(case, self.args())
            self.assertEqual(
                row["status"], "PASS" if case["expect"] == "PASS" else "FAIL"
            )
        with mock.patch.object(judge, "invoke", return_value={"status": "TIMEOUT"}):
            self.assertEqual(
                judge.run_calibration(self.catalog["calibration"][0], self.args())[
                    "status"
                ],
                "ERROR",
            )

    def test_report_partial_errors_are_not_live_completion(self):
        with tempfile.TemporaryDirectory() as raw:
            args = self.args()
            args.report = pathlib.Path(raw) / "report.json"
            judge.write_report(
                args,
                self.catalog,
                "fixture",
                [{"id": "fixture", "status": "PASS", "verdict": {}}],
                [{"status": "ERROR"}],
            )
            report = json.loads(args.report.read_text())
        self.assertEqual(report["counts"], {"PASS": 1, "FAIL": 0, "ERROR": 1})
        self.assertIs(report["provenance"]["live"], False)

    def test_catalog_invalid_and_selection(self):
        with self.assertRaises(ValueError):
            judge.select_scenarios(self.catalog, "unknown")
        with self.assertRaises(ValueError):
            judge.select_scenarios({"scenarios": []}, "")
        self.assertEqual(
            judge.select_scenarios(self.catalog, self.scenario["id"]), [self.scenario]
        )
        with tempfile.TemporaryDirectory() as raw:
            path = pathlib.Path(raw) / "catalog.json"
            for body in (
                None,
                [],
                {},
                {**self.catalog, "schema_version": True},
                {**self.catalog, "calibration": [None]},
                {**self.catalog, "requirement_map": {}},
            ):
                path.write_text(json.dumps(body))
                with self.assertRaises(ValueError):
                    judge.load_catalog(path)

    def test_candidate_is_not_truncated_for_judgment(self):
        candidate = "a" * 5000 + " LAST_OBSERVATION"
        self.assertIn("LAST_OBSERVATION", judge.judge_prompt(self.scenario, candidate))
        self.assertEqual(len(judge.audit_text(candidate)), judge.MAX_AUDIT_CHARS)
        self.assertNotIn("private-value", judge.audit_text("token=private-value"))

    def test_calibration_schema_rejected_before_backend_or_model_calls(self):
        invalid = [None, [], [None], [{"expect": "PASS"}, {"expect": "FAIL"}]]
        seeds = self.catalog["calibration"]
        for field in ("id", "expect", "candidate", "must", "must_not"):
            value = copy.deepcopy(seeds)
            del value[0][field]
            invalid.append(value)
        for field, bad in (
            ("candidate", ""),
            ("candidate", 1),
            ("id", " "),
            ("expect", []),
            ("expect", "unknown"),
            ("must", "text"),
            ("must", []),
            ("must_not", ["duplicate", "duplicate"]),
            ("must_not", [None]),
        ):
            value = copy.deepcopy(seeds)
            value[0][field] = bad
            invalid.append(value)
        duplicate = copy.deepcopy(seeds)
        duplicate[1]["id"] = duplicate[0]["id"]
        invalid.append(duplicate)
        collision = copy.deepcopy(seeds)
        collision[0]["id"] = self.scenario["id"]
        invalid.append(collision)
        unknown = copy.deepcopy(seeds)
        unknown[0]["extra"] = True
        invalid.append(unknown)
        invalid.append([seeds[0]])
        with tempfile.TemporaryDirectory() as raw:
            path = pathlib.Path(raw) / "catalog.json"
            for calibration in invalid:
                path.write_text(
                    json.dumps({**self.catalog, "calibration": calibration})
                )
                with (
                    self.subTest(calibration=calibration),
                    mock.patch.object(judge, "runtime") as runtime,
                    mock.patch.object(judge, "invoke") as invoke,
                    contextlib.redirect_stderr(io.StringIO()),
                ):
                    self.assertEqual(
                        judge.main(["--scenarios", str(path), "--calibrate"]), 2
                    )
                    runtime.assert_not_called()
                    invoke.assert_not_called()
        judge.validate_calibration(seeds, {self.scenario["id"]})

    def test_report_redacts_bounded_verdict_evidence_without_changing_scores(self):
        verdict = self.verdict()
        verdict["evidence"] = "token=SEEDED_SENSITIVE " + "x" * 5000
        row = {
            "id": "fixture",
            "status": "PASS",
            "verdict": verdict,
            "judge_output": verdict,
        }
        with tempfile.TemporaryDirectory() as raw:
            args = self.args()
            args.report = pathlib.Path(raw) / "report.json"
            judge.write_report(args, self.catalog, "fixture", [row], [row])
            raw_report = args.report.read_text()
            report = json.loads(raw_report)
        self.assertNotIn("SEEDED_SENSITIVE", raw_report)
        self.assertIn("SEEDED_SENSITIVE", verdict["evidence"])
        for stored in report["results"] + report["calibration"]:
            for key in ("verdict", "judge_output"):
                self.assertLessEqual(len(stored[key]["evidence"]), 500)
                self.assertEqual(stored[key]["must_not"], verdict["must_not"])
        parsed = judge.parse_verdict(envelope(verdict), self.scenario)
        self.assertNotIn("SEEDED_SENSITIVE", parsed["evidence"])

    def test_runner_judge_and_calibration_keep_model_provenance(self):
        runner = {
            **self.completed({"response": "proposal"}),
            "model": "alias",
            "requested_model": "alias",
            "observed_model": None,
            "model_source": "requested",
            "plugin_mode": "explicit-context",
        }
        reviewed = {
            **self.completed(self.verdict()),
            "model": "actual-model",
            "requested_model": "alias",
            "observed_model": "actual-model",
            "model_source": "observed",
            "plugin_mode": "none",
        }
        with mock.patch.object(judge, "invoke", side_effect=[runner, reviewed]):
            row = judge.run_one(self.scenario, self.args())
        self.assertEqual(row["runner_requested_model"], "alias")
        self.assertIsNone(row["runner_observed_model"])
        self.assertEqual(row["runner_model_source"], "requested")
        self.assertEqual(row["runner_plugin_mode"], "explicit-context")
        self.assertEqual(row["judge_observed_model"], "actual-model")
        self.assertEqual(row["judge_model_source"], "observed")
        case = self.catalog["calibration"][0]
        scored = {
            "verdict": "PASS",
            "must": dict.fromkeys(case["must"], True),
            "must_not": dict.fromkeys(case["must_not"], True),
            "evidence": "password=SEEDED_CALIBRATION",
        }
        with mock.patch.object(
            judge, "invoke", return_value={**reviewed, "output": scored}
        ):
            calibration = judge.run_calibration(case, self.args())
        self.assertEqual(calibration["observed_model"], "actual-model")
        self.assertEqual(calibration["model_source"], "observed")
        self.assertEqual(calibration["plugin_mode"], "none")
        self.assertNotIn("SEEDED_CALIBRATION", json.dumps(calibration))

    def test_source_changes_keep_tested_hashes_and_fail_freshness_without_model(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            args = self.args()
            args.plugin_dir = root / "plugin"
            args.plugin_dir.mkdir()
            source = args.plugin_dir / "command.md"
            source.write_text("original")
            args.scenarios = root / "catalog.json"
            args.scenarios.write_text(json.dumps(self.catalog))
            args.report = root / "report.json"
            args.initial_hash = judge.tree_hash(args.plugin_dir)
            args.initial_catalog = judge.digest(args.scenarios.read_text())
            with mock.patch.object(judge, "invoke") as invoke:
                self.assertTrue(judge.inputs_unchanged(args))
                args.scenarios.write_text(json.dumps(self.catalog) + " ")
                self.assertFalse(judge.inputs_unchanged(args))
                args.scenarios.write_text(json.dumps(self.catalog))
                source.write_text("changed")
                self.assertFalse(judge.inputs_unchanged(args))
                judge.write_report(args, self.catalog, "fixture", [], [])
                invoke.assert_not_called()
            report = json.loads(args.report.read_text())
            self.assertEqual(report["provenance"]["plugin_sha256"], args.initial_hash)
            self.assertEqual(
                report["provenance"]["catalog_sha256"], args.initial_catalog
            )
            self.assertIs(report["inputs_unchanged"], False)

    def test_unavailable_and_required_calibration_fail_closed(self):
        adapter = mock.Mock()
        adapter.select_backend.return_value = {
            "status": "BLOCKED",
            "reason": "No authenticated CLI",
        }
        with mock.patch.object(judge, "runtime", return_value=adapter):
            self.assertEqual(judge.main(["--require", "--calibrate"]), 2)
            adapter.select_backend.return_value = {
                "status": "READY",
                "version": "fixture",
            }
            self.assertEqual(judge.main(["--require"]), 2)


if __name__ == "__main__":
    unittest.main()
