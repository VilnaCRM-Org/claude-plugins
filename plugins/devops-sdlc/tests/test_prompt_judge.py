"""Fixture-only checks for prompt assessment; no authenticated CLI is invoked."""

from __future__ import annotations

import contextlib
import copy
import io
import json
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prompt_judge as subject  # noqa: E402


def fake_agent(prompt, schema, cwd, **kwargs):
    ids = schema["properties"]["dimensions"]["required"]
    score = 5
    citation = "Validate"
    for case in subject.calibration.CASES:
        if case.raw in prompt:
            score = 5 if case.polarity == "P" else 1
            citation = next(line for line in case.raw.splitlines() if line)
    return {
        "status": "COMPLETED",
        "backend": "claude",
        "version": "fixture-cli-1",
        "model": "fixture-model",
        "observed_model": "fixture-model",
        "requested_model": kwargs["model"],
        "fallback": [],
        "plugin_mode": "none",
        "output": {
            "dimensions": {
                dimension: {
                    "score": score,
                    "evidence": "Specific fixture evidence.",
                    "citation": citation,
                }
                for dimension in ids
            }
        },
    }


class PromptJudgeTests(unittest.TestCase):
    def test_importlib_loader_finds_shared_redaction_from_foreign_directory(self):
        code = "\n".join(
            (
                "import importlib.util, pathlib, sys",
                f"path = {str(Path(subject.__file__).resolve())!r}",
                "spec = importlib.util.spec_from_file_location("
                "'isolated_prompt_judge', path)",
                "module = importlib.util.module_from_spec(spec)",
                "sys.modules[spec.name] = module",
                "spec.loader.exec_module(module)",
                "import redaction",
                "assert module._redact_text is redaction.redact_text",
                "assert pathlib.Path(redaction.__file__).resolve() "
                "== pathlib.Path(path).parent / 'redaction.py'",
                "assert module.redact_evidence('api_token=fixture') "
                "== 'api_token=[REDACTED]'",
                "seen = []",
                "def observe(value):",
                "    seen.append(value)",
                "    return 'alias-delegated'",
                "module._redact_text = observe",
                "assert module.redact_evidence('delegation-sentinel') "
                "== 'alias-delegated'",
                "assert seen == ['delegation-sentinel']",
            )
        )
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, "-c", code],
                cwd=directory,
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "plugins/example"
        artifact = self.root / "commands/example.md"
        artifact.parent.mkdir(parents=True)
        artifact.write_text(
            "---\ndescription: Validate infrastructure.\n---\n"
            "# Example\nValidate the selected stack and report evidence.\n"
        )
        self.expected = mock.patch.object(subject, "EXPECTED_ARTIFACTS", 1)
        self.expected.start()
        self.addCleanup(self.expected.stop)
        self.settings = subject.Settings()

    def run_fixture(self, runner=fake_agent, settings=None):
        with mock.patch.object(subject.agent_cli, "run_prompt", side_effect=runner):
            return subject.evaluate(
                self.root, settings or self.settings, mode="fixture"
            )

    def test_full_fixture_calibrates_all_critical_dimensions_and_never_claims_live(
        self,
    ):
        calls = []

        def runner(*args, **kwargs):
            calls.append((args, kwargs))
            return fake_agent(*args, **kwargs)

        report = self.run_fixture(runner)
        self.assertEqual(report["status"], "PASSED")
        self.assertEqual(len(report["calibration"]), 10)
        self.assertEqual(len(calls), 33)
        self.assertEqual(report["coverage"]["live_assessed_dimension_pairs"], 0)
        self.assertGreater(report["coverage"]["assessed_dimension_pairs"], 0)
        self.assertEqual(len(report["artifacts"][0]["votes"]), 3)
        self.assertEqual(len({str(args[2]) for args, _ in calls}), 33)
        for args, kwargs in calls:
            self.assertIsNone(kwargs["plugin_root"])
            self.assertEqual(kwargs["backend"], "auto")
            self.assertFalse(args[1]["additionalProperties"])
            self.assertIn("DATA", args[0])
            self.assertIn("RESPONSE CONTRACT", args[0])

    def test_prompt_provenance_hashes_full_request_and_context(self):
        sent = []

        def capture(prompt, *args, **kwargs):
            sent.append(prompt)
            return fake_agent(prompt, *args, **kwargs)

        report = self.run_fixture(capture)
        row = report["artifacts"][0]
        self.assertEqual(row["prompt_text_sha256"], subject.digest(sent[-1].encode()))
        self.assertNotEqual(row["prompt_text_sha256"], row["sha256"])
        for vote, prompt in zip(row["votes"], sent[-3:], strict=True):
            self.assertEqual(
                vote["prompt_text_sha256"], subject.digest(prompt.encode())
            )
        with mock.patch.object(
            subject, "CONTEXT", subject.CONTEXT + " Additional contract."
        ):
            changed = self.run_fixture()
        self.assertNotEqual(
            row["prompt_text_sha256"], changed["artifacts"][0]["prompt_text_sha256"]
        )
        self.assertEqual(row["sha256"], changed["artifacts"][0]["sha256"])

    def test_default_inventory_is_exactly_31_in_repository(self):
        with mock.patch.object(subject, "EXPECTED_ARTIFACTS", 31):
            artifacts = subject.artifact_inventory(
                subject.PLUGIN, subject.plugin_snapshot(subject.PLUGIN)
            )
        self.assertEqual(len(artifacts), 31)
        self.assertEqual(sum(a.kind == "meta-guide" for a in artifacts), 2)

    def test_missing_auth_fails_closed_without_artifact_votes(self):
        def unavailable(*args, **kwargs):
            return {"status": "BLOCKED", "backend": None, "version": None}

        report = self.run_fixture(unavailable)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertEqual(report["artifacts"][0]["votes"], [])
        self.assertEqual(report["artifacts"][0]["kind"], "command")
        self.assertEqual(report["artifacts"][0]["name"], "example")
        self.assertEqual(report["coverage"]["assessed_dimension_pairs"], 0)

    def test_malformed_unknown_and_bool_verdicts_are_rejected(self):
        dims = [subject.rubrics.DIMENSIONS_BY_ID["J1"]]
        values = [
            [],
            {"dimensions": {}, "extra": True},
            {"dimensions": {"J1": {"score": True, "evidence": "bad"}}},
            {"dimensions": {"J1": {"score": 5, "evidence": "good", "extra": True}}},
            {"dimensions": {"J1": {"score": 5, "evidence": "x" * 241}}},
            {"dimensions": {"J1": {"score": 5, "evidence": "two\nlines"}}},
            {
                "dimensions": {
                    "J1": {"score": 5, "evidence": "good"},
                    "J2": {"score": 5, "evidence": "extra"},
                }
            },
        ]
        for value in values:
            with self.subTest(value=value), self.assertRaises(subject.AssessmentError):
                subject.strict_verdict(value, dims, "Validate infrastructure.")

    def test_citations_bind_verdicts_and_stored_evidence_is_redacted(self):
        def secret_evidence(*args, **kwargs):
            result = fake_agent(*args, **kwargs)
            for entry in result["output"]["dimensions"].values():
                entry["evidence"] = "API_KEY=secret-sentinel is not retained."
            return result

        report = self.run_fixture(secret_evidence)
        vote = report["artifacts"][0]["votes"][0]["dimensions"]
        entry = next(iter(vote.values()))
        self.assertEqual(entry["evidence"], "API_KEY=[REDACTED] is not retained.")
        self.assertNotIn("secret-sentinel", json.dumps(report))
        self.assertEqual(
            entry["evidence_sha256"], subject.digest(entry["evidence"].encode())
        )
        self.assertNotIn(
            subject.digest(b"API_KEY=secret-sentinel is not retained."),
            json.dumps(report),
        )
        self.assertEqual(
            subject.redact_evidence("AWS_SECRET_ACCESS_KEY: not-retained"),
            "AWS_SECRET_ACCESS_KEY=[REDACTED]",
        )
        identifier = "a" * 10_000
        self.assertEqual(subject.redact_evidence(identifier), identifier)
        redacted = subject.redact_evidence(
            'db_password=sentinel,more;tail "api_token": "quoted sentinel value"'
        )
        for value in ("sentinel", "more", "tail", "quoted"):
            self.assertNotIn(value, redacted)
        self.assertNotIn("value", redacted)
        self.assertIn('"api_token"=[REDACTED]', redacted)
        concatenated = (
            "api_token='orchid'\"cobalt quartz\"tailend "
            'db_password="maple \\"cinder dawn\\""suffixend'
        )
        redacted = subject.redact_evidence(concatenated)
        for value in (
            "orchid",
            "cobalt",
            "quartz",
            "tailend",
            "maple",
            "cinder",
            "dawn",
            "suffixend",
        ):
            self.assertNotIn(value, redacted)
        self.assertEqual(redacted, "api_token=[REDACTED] db_password=[REDACTED]")
        malformed_cases = (
            (
                'api_token="orchid\nterminal-backslash\\',
                ("orchid", "terminal", "backslash"),
            ),
            ("api_token='lilac'\"cobalt quartz", ("lilac", "cobalt", "quartz")),
            ('api_token="marigold\\', ("marigold",)),
        )
        for malformed, values in malformed_cases:
            with self.subTest(malformed=malformed):
                redacted = subject.redact_evidence(malformed)
                self.assertEqual(redacted, "api_token=[REDACTED]")
                for value in values:
                    self.assertNotIn(value, redacted)
        json_newline = '"api_token": "orchid\\" cobalt\nquartz"'
        redacted = subject.redact_evidence(json_newline)
        self.assertEqual(redacted, '"api_token"=[REDACTED]')
        for value in ("orchid", "cobalt", "quartz"):
            self.assertNotIn(value, redacted)
        value = {
            "dimensions": {
                "J1": {
                    "score": 5,
                    "evidence": "Specific evidence.",
                    "citation": "not in artifact",
                }
            }
        }
        with self.assertRaises(subject.AssessmentError):
            subject.strict_verdict(
                value, [subject.rubrics.DIMENSIONS_BY_ID["J1"]], "artifact text"
            )
        with self.assertRaisesRegex(subject.AssessmentError, r"Verdict J1:.*citation"):
            subject.strict_verdict(
                value, [subject.rubrics.DIMENSIONS_BY_ID["J1"]], "artifact text"
            )

    def test_stored_evidence_redacts_nested_and_escaped_assignments(self):
        cases = (
            "note: api_token=WRAPPED_SENTINEL",
            '{"message": "api_token=WRAPPED_SENTINEL"}',
            "'api_token'='WRAPPED_SENTINEL'",
            "api_token=WRAPPED_SENTINEL\\ ESCAPED_SENTINEL",
            "api_token=WRAPPED_SENTINEL\\\nESCAPED_SENTINEL",
            "api_token='WRAPPED_SENTINEL password=INNER_SENTINEL'",
        )
        for candidate in cases:
            verdict = {
                "dimensions": {
                    "J1": {"score": 5, "evidence": candidate, "citation": candidate}
                }
            }
            with self.subTest(candidate=candidate):
                stored = subject.stored_dimensions(verdict)
                self.assertNotIn("SENTINEL", json.dumps(stored))
                self.assertEqual(stored["J1"]["score"], 5)
                self.assertEqual(
                    stored["J1"]["evidence_sha256"],
                    subject.digest(stored["J1"]["evidence"].encode()),
                )

    def test_evidence_redaction_retains_nonsecret_text_and_empty_assignment(self):
        for candidate in (
            'note="ordinary words" status=READY',
            '{"message": "ordinary words"}',
            "token is a word here",
            "api_token=   ",
        ):
            with self.subTest(candidate=candidate):
                self.assertEqual(subject.redact_evidence(candidate), candidate)
        self.assertEqual(
            subject.redact_evidence('"api_token"=""'), '"api_token"=[REDACTED]'
        )

    def test_invalid_output_has_safe_error_without_raw_response(self):
        def invalid(*args, **kwargs):
            result = fake_agent(*args, **kwargs)
            result["output"] = {"SECRET_SENTINEL": "malformed"}
            return result

        report = self.run_fixture(invalid)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertNotIn("SECRET_SENTINEL", json.dumps(report))

    def test_exported_dimension_digests_do_not_fingerprint_raw_secrets(self):
        exported = []
        for secret in ("guessable-one", "guessable-two"):
            raw = f"api_token={secret}"
            verdict = {
                "dimensions": {"J1": {"score": 5, "evidence": raw, "citation": raw}}
            }
            entry = subject.stored_dimensions(verdict)["J1"]
            exported.append(entry)
            self.assertEqual(entry["digest_scope"], "redacted UTF-8 text")
            for field in ("evidence", "citation"):
                self.assertEqual(
                    entry[field + "_sha256"], subject.digest(entry[field].encode())
                )
                self.assertNotEqual(
                    entry[field + "_sha256"], subject.digest(raw.encode())
                )
            self.assertNotIn(secret, json.dumps(entry))
            self.assertNotIn(subject.digest(raw.encode()), json.dumps(entry))
        self.assertEqual(exported[0], exported[1])

    def test_citation_choices_and_validation_require_redaction_stable_source(self):
        unsafe = "api_token=guessable-secret"
        source = unsafe + "\nUse bounded validation."
        self.assertNotIn(unsafe, subject.citation_choices(source))
        self.assertIn("Use bounded validation.", subject.citation_choices(source))
        entry = {"score": 5, "evidence": "Observed source.", "citation": unsafe}
        with self.assertRaisesRegex(subject.AssessmentError, "redaction-stable"):
            subject.validate_entry(entry, source)
        entry["citation"] = "Use bounded validation."
        subject.validate_entry(entry, source)
        self.assertEqual(
            subject.stored_dimensions({"dimensions": {"J1": entry}})["J1"]["citation"],
            entry["citation"],
        )

    def test_invalid_model_output_exports_no_raw_digest(self):
        raw_output = {"api_token": "guessable-secret"}

        def invalid(*args, **kwargs):
            result = fake_agent(*args, **kwargs)
            result["output"] = raw_output
            return result

        report = self.run_fixture(invalid)
        rendered = json.dumps(report)
        self.assertNotIn(subject.json_digest(raw_output), rendered)
        self.assertNotIn("guessable-secret", rendered)
        attempts = [
            attempt
            for row in report["artifacts"] + report["calibration"]
            for vote in row["votes"]
            for attempt in vote.get("invalid_attempts", [])
        ]
        self.assertGreater(len(attempts), 0)
        for attempt in attempts:
            self.assertIsNone(attempt["output_sha256"])
            self.assertEqual(
                attempt["output_digest_scope"], "omitted: untrusted model output"
            )

    def test_all_floors_and_any_critical_block_are_enforced(self):
        dims = [subject.rubrics.DIMENSIONS_BY_ID[key] for key in ("J2", "J11")]
        votes = [
            {"dimensions": {"J2": {"score": critical}, "J11": {"score": 3}}}
            for critical in (5, 5, 1)
        ]
        rows = subject.dimension_results(votes, dims)
        self.assertEqual(rows[0]["median"], 5)
        self.assertTrue(rows[0]["critical_block"])
        self.assertFalse(rows[0]["passed"])
        self.assertFalse(rows[1]["passed"])

    def test_calibration_positive_negative_and_missing_cases_fail_closed(self):
        def too_generous(*args, **kwargs):
            result = fake_agent(*args, **kwargs)
            for item in result["output"]["dimensions"].values():
                item["score"] = 5
            return result

        self.assertEqual(self.run_fixture(too_generous)["status"], "BLOCKED")
        with mock.patch.object(subject.calibration, "CASES", ()):
            with self.assertRaises(subject.AssessmentError):
                subject.calibration_inventory()
        with mock.patch.object(subject.calibration, "CRITICAL_DIMENSION_IDS", ()):
            with self.assertRaises(subject.AssessmentError):
                subject.calibration_inventory()

    def test_uncalibrated_backend_or_model_change_blocks_artifact(self):
        def changed(prompt, *args, **kwargs):
            result = fake_agent(prompt, *args, **kwargs)
            if not any(case.raw in prompt for case in subject.calibration.CASES):
                result["backend"] = "codex"
            return result

        report = self.run_fixture(changed)
        self.assertEqual(report["status"], "FAILED")
        self.assertEqual(report["artifacts"][0]["status"], "ERROR")

    def test_missing_model_identity_blocks_without_invention(self):
        def unreported(*args, **kwargs):
            result = fake_agent(*args, **kwargs)
            result["model"] = None
            result["observed_model"] = None
            result["requested_model"] = None
            return result

        report = self.run_fixture(unreported)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertTrue(report["identity_unverified"])

    def test_only_requested_dimensions_count_as_coverage(self):
        report = self.run_fixture(settings=subject.Settings(dimensions=("J11",)))
        row = report["artifacts"][0]
        self.assertEqual(row["requested_dimensions"], ["J11"])
        self.assertEqual(report["coverage"]["requested_dimension_pairs"], 1)
        self.assertEqual(report["coverage"]["assessed_dimension_pairs"], 1)
        self.assertEqual(report["status"], "PARTIAL")
        report = self.run_fixture(settings=subject.Settings(dimensions=("J1",)))
        self.assertEqual(report["artifacts"][0]["status"], "NOT_REQUESTED")
        self.assertEqual(report["status"], "FAILED")

    def test_not_requested_artifact_has_no_prompt_hash_or_vote_call(self):
        artifact = subject.artifact_inventory(
            self.root, subject.plugin_snapshot(self.root)
        )[0]
        with mock.patch.object(subject, "collect_votes") as votes:
            row = subject.assess_artifact(
                artifact, [], subject.CONTEXT, self.settings, "fixture", ()
            )
        self.assertEqual(row["status"], "NOT_REQUESTED")
        self.assertIsNone(row["prompt_text_sha256"])
        votes.assert_not_called()

    def test_plugin_changes_during_run_invalidate_report(self):
        counter = 0

        def changed(*args, **kwargs):
            nonlocal counter
            counter += 1
            if counter == 33:
                (self.root / "commands/example.md").write_text("changed")
            return fake_agent(*args, **kwargs)

        report = self.run_fixture(changed)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertIn("changed", report["error"])

    def test_artifact_raw_must_match_the_initial_snapshot(self):
        snapshot = subject.plugin_snapshot(self.root)
        (self.root / "commands/example.md").write_text("changed after snapshot")
        with self.assertRaises(subject.AssessmentError):
            subject.artifact_inventory(self.root, snapshot)

    def test_live_codex_requires_explicit_model_for_identity(self):
        def codex(*args, **kwargs):
            result = fake_agent(*args, **kwargs)
            result.update(backend="codex", observed_model=None, requested_model=None)
            return result

        with mock.patch.object(subject.agent_cli, "run_prompt", side_effect=codex):
            report = subject.evaluate(self.root, self.settings, mode="live")
        self.assertEqual(report["status"], "BLOCKED")
        self.assertTrue(report["identity_unverified"])

        def explicit_codex(*args, **kwargs):
            result = fake_agent(*args, **kwargs)
            result.update(backend="codex", observed_model=None)
            return result

        with mock.patch.object(
            subject.agent_cli, "run_prompt", side_effect=explicit_codex
        ):
            report = subject.evaluate(
                self.root, subject.Settings(model="gpt-5.5"), mode="live"
            )
        self.assertEqual(report["status"], "PASSED")

    def test_invalid_settings_inventory_and_symlinks_rejected(self):
        for settings in (
            subject.Settings(backend="unknown"),
            subject.Settings(prefer="unknown"),
            subject.Settings(timeout=True),
            subject.Settings(dimensions=("J99",)),
            subject.Settings(dimensions=("J1", "J1")),
        ):
            with (
                self.subTest(settings=settings),
                self.assertRaises(subject.AssessmentError),
            ):
                subject.validate_settings(settings, "fixture")
        (self.root / "link").symlink_to("/tmp", target_is_directory=True)
        with self.assertRaises(subject.AssessmentError):
            subject.plugin_snapshot(self.root)

    def test_schema_requires_exact_artifact_specific_dimension_ids(self):
        dims = subject.rubrics.applicable_dimensions("command", "example")
        schema = subject.verdict_schema(dims)
        selected = schema["properties"]["dimensions"]
        self.assertEqual(selected["required"], [dim.id for dim in dims])
        self.assertEqual(set(selected["properties"]), set(selected["required"]))
        self.assertFalse(selected["additionalProperties"])

    def test_schema_citations_are_bounded_exact_artifact_chunks(self):
        schema = subject.verdict_schema(
            [subject.rubrics.DIMENSIONS_BY_ID["J1"]], "short line\n" + "x" * 121
        )
        choices = schema["$defs"]["assessment_entry"]["properties"]["citation"]["enum"]
        self.assertEqual(choices, ["short line", "x" * 120, "x"])

    def test_multidimension_schema_shares_one_literal_safe_exact_citation_enum(self):
        raw = 'Run "quoted" command with \\path and\ttab.\n' + "x" * 121
        dims = subject.rubrics.applicable_dimensions("command", "example")
        schema = subject.verdict_schema(dims, raw)
        choices = schema["$defs"]["assessment_entry"]["properties"]["citation"]["enum"]
        self.assertIn("quoted", choices)
        self.assertIn("path and", choices)
        self.assertIn("x" * 120, choices)
        for choice in choices:
            self.assertIn(choice, raw)
            self.assertLessEqual(len(choice), 120)
            self.assertNotIn('"', choice)
            self.assertNotIn("\\", choice)
            self.assertTrue(all(ord(char) >= 32 for char in choice))
        self.assertEqual(json.dumps(schema).count('"enum"'), 1)
        for entry in schema["properties"]["dimensions"]["properties"].values():
            self.assertEqual(entry, {"$ref": "#/$defs/assessment_entry"})
        with self.assertRaises(subject.AssessmentError):
            subject.verdict_schema(dims, '"\\\t')

    def test_all_shipped_artifact_schemas_have_exact_bounded_single_enum(self):
        artifacts = subject._model.discover(subject.PLUGIN)
        for artifact in artifacts:
            dims = subject.rubrics.applicable_dimensions(artifact.kind, artifact.name)
            schema = subject.verdict_schema(dims, artifact.raw)
            choices = schema["$defs"]["assessment_entry"]["properties"]["citation"][
                "enum"
            ]
            with self.subTest(artifact=artifact.name):
                self.assertEqual(json.dumps(schema).count('"enum"'), 1)
                self.assertTrue(choices)
                self.assertLessEqual(len(choices), subject.MAX_CITATIONS)
                self.assertTrue(all(c in artifact.raw for c in choices))
                self.assertTrue(all('"' not in c and "\\" not in c for c in choices))
        with mock.patch.object(subject, "MAX_CITATIONS", 2):
            self.assertEqual(
                subject.citation_choices("one\none\ntwo\nthree"), ["one", "two"]
            )

    def test_prompt_and_schema_offer_identical_citation_fragments(self):
        artifact = subject.artifact_inventory(
            self.root, subject.plugin_snapshot(self.root)
        )[0]
        dimensions = subject.rubrics.applicable_dimensions(artifact.kind, artifact.name)

        def runner(prompt, schema, *args, **kwargs):
            choices = schema["$defs"]["assessment_entry"]["properties"]["citation"][
                "enum"
            ]
            self.assertTrue(all(c in prompt for c in choices))
            self.assertIn("Allowed exact citation fragments", prompt)
            return fake_agent(prompt, schema, *args, **kwargs)

        with mock.patch.object(subject.agent_cli, "run_prompt", side_effect=runner):
            vote = subject.one_vote(
                artifact, dimensions, subject.CONTEXT, self.settings, 1, "fixture"
            )
        self.assertEqual(vote["status"], "SCORED")

    def test_invalid_structured_output_repairs_only_until_valid(self):
        calls = []

        def runner(*args, **kwargs):
            calls.append(kwargs["backend"])
            result = fake_agent(*args, **kwargs)
            if len(calls) == 1:
                next(iter(result["output"]["dimensions"].values()))["citation"] = "bad"
            return result

        artifact = subject.artifact_inventory(
            self.root, subject.plugin_snapshot(self.root)
        )[0]
        dimensions = subject.rubrics.applicable_dimensions(artifact.kind, artifact.name)
        with mock.patch.object(subject.agent_cli, "run_prompt", side_effect=runner):
            vote = subject.one_vote(
                artifact, dimensions, subject.CONTEXT, self.settings, 1, "fixture"
            )
        self.assertEqual(vote["status"], "SCORED")
        self.assertEqual(len(vote["invalid_attempts"]), 1)
        self.assertEqual(calls, ["auto", "claude"])

    def test_always_invalid_and_cli_error_do_not_overretry(self):
        artifact = subject.artifact_inventory(
            self.root, subject.plugin_snapshot(self.root)
        )[0]
        dimensions = subject.rubrics.applicable_dimensions(artifact.kind, artifact.name)

        def invalid(*args, **kwargs):
            result = fake_agent(*args, **kwargs)
            for entry in result["output"]["dimensions"].values():
                entry["citation"] = "bad"
            return result

        with mock.patch.object(
            subject.agent_cli, "run_prompt", side_effect=invalid
        ) as call:
            vote = subject.one_vote(
                artifact, dimensions, subject.CONTEXT, self.settings, 1, "fixture"
            )
        self.assertEqual(vote["status"], "ERROR")
        self.assertEqual(call.call_count, subject.judge.MAX_REPROMPTS + 1)
        self.assertEqual(len(vote["invalid_attempts"]), subject.judge.MAX_REPROMPTS + 1)
        with mock.patch.object(
            subject.agent_cli, "run_prompt", return_value={"status": "TIMEOUT"}
        ) as call:
            vote = subject.one_vote(
                artifact, dimensions, subject.CONTEXT, self.settings, 1, "fixture"
            )
        self.assertEqual(vote["status"], "ERROR")
        self.assertEqual(call.call_count, 1)

    def test_cli_no_auth_returns_nonzero_and_json(self):
        with mock.patch.object(
            subject.agent_cli, "run_prompt", return_value={"status": "BLOCKED"}
        ):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                code = subject.main(["--plugin-root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(output.getvalue())["status"], "BLOCKED")

    def test_fixture_identity_calibration_rejects_mixed_backends(self):
        rows = self.run_fixture()["calibration"]
        altered = copy.deepcopy(rows)
        altered[0]["votes"][0]["backend"] = "codex"
        self.assertIsNone(subject.calibrated_identity(altered))

    def test_jobs_bounds_and_parallel_cli_calls_preserve_three_votes(self):
        for jobs in (True, 0, 5, 2.5):
            with self.subTest(jobs=jobs), self.assertRaises(subject.AssessmentError):
                subject.validate_settings(subject.Settings(jobs=jobs), "fixture")
        lock = threading.Lock()
        active = maximum = 0

        def runner(*args, **kwargs):
            nonlocal active, maximum
            with lock:
                active += 1
                maximum = max(maximum, active)
            try:
                time.sleep(0.005)
                return fake_agent(*args, **kwargs)
            finally:
                with lock:
                    active -= 1

        report = self.run_fixture(runner, subject.Settings(jobs=2))
        self.assertEqual(report["status"], "PASSED")
        self.assertEqual(maximum, 2)
        self.assertEqual(report["settings"]["jobs"], 2)
        for row in report["calibration"] + report["artifacts"]:
            self.assertEqual(len(row["votes"]), 3)

    def test_parallel_rows_keep_inventory_order_despite_completion_order(self):
        def worker(number):
            time.sleep((3 - number) * 0.002)
            return {"number": number}

        rows = subject.parallel_rows([1, 2, 3], worker, 3)
        self.assertEqual([row["number"] for row in rows], [1, 2, 3])

    def test_progress_uses_stderr_only_and_fixture_mode_is_quiet(self):
        with contextlib.redirect_stderr(io.StringIO()) as output:
            subject.progress("artifact example", "PASSED", "live")
            subject.progress("fixture", "PASSED", "fixture")
        self.assertEqual(output.getvalue(), "artifact example: PASSED\n")

    def test_live_failure_progress_uses_redacted_evidence(self):
        row = {
            "path": "commands/example.md",
            "status": "FAILED",
            "dimensions": [{"id": "J1", "passed": False, "scores": [1, 2, 1]}],
            "votes": [
                {"dimensions": {"J1": {"evidence": "API_KEY=[REDACTED]"}}},
                {"dimensions": {"J1": {"evidence": "missing trigger"}}},
                {"dimensions": {"J1": {"evidence": "missing trigger"}}},
            ],
        }
        with contextlib.redirect_stderr(io.StringIO()) as output:
            subject.progress_failures(row, "live")
        self.assertIn("J1", output.getvalue())
        self.assertIn("[REDACTED]", output.getvalue())

    def test_live_error_progress_includes_only_static_reason(self):
        row = {
            "path": "agents/ci-fixer.md",
            "status": "ERROR",
            "error": "Verdict J2: citation is not an exact artifact substring.",
        }
        with contextlib.redirect_stderr(io.StringIO()) as output:
            subject.progress_error(row, "live")
        self.assertEqual(
            output.getvalue(),
            "artifact agents/ci-fixer.md error: Verdict J2: citation is not an "
            "exact artifact substring.\n",
        )


if __name__ == "__main__":
    unittest.main()
