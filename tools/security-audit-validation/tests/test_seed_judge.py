"""Tests for the LLM-as-judge behavioral lane (pure core + thin shell)."""

import pathlib
import sys
import types
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "judge"))

import corpus  # noqa: E402
import run_seed_judge as sj  # noqa: E402


def _fx(expect="FINDING", family="sqli", path="sqli/vulnerable.php"):
    return corpus.Fixture("C", family, path, "CWE-89", "finding", expect)


def _proc(stdout="", stderr="", returncode=0):
    return types.SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)


class TestPureCore(unittest.TestCase):
    def test_build_prompt_includes_family_and_source(self):
        p = sj.build_prompt(_fx(), "echo $_GET['x'];")
        self.assertIn("Assigned family: sqli", p)
        self.assertIn("echo $_GET", p)

    def test_parse_verdict_json(self):
        self.assertEqual(
            sj.parse_verdict('{"verdict":"FINDING","cwe":"CWE-89"}'), "FINDING"
        )

    def test_parse_verdict_json_invalid_verdict_falls_back_to_token(self):
        # JSON parses but verdict value is junk -> token scan finds CLEAN.
        self.assertEqual(sj.parse_verdict('{"verdict":"MAYBE"} CLEAN'), "CLEAN")

    def test_parse_verdict_bad_json_falls_back_to_token(self):
        self.assertEqual(sj.parse_verdict("{not json} the verdict is NA"), "NA")

    def test_parse_verdict_token_only(self):
        self.assertEqual(sj.parse_verdict("Verdict: finding here"), "FINDING")

    def test_parse_verdict_none_raises(self):
        with self.assertRaises(ValueError):
            sj.parse_verdict("no decision at all")

    def test_majority_clear(self):
        self.assertEqual(
            sj.majority_verdict(["FINDING", "FINDING", "CLEAN"]), "FINDING"
        )

    def test_majority_tie_security_conservative(self):
        # 1-1 tie between FINDING and CLEAN -> FINDING wins.
        self.assertEqual(sj.majority_verdict(["CLEAN", "FINDING"]), "FINDING")

    def test_majority_empty_raises(self):
        with self.assertRaises(ValueError):
            sj.majority_verdict([])

    def test_evaluate_counts(self):
        rs = [
            sj.JudgeResult("a", "f", "FINDING", "FINDING", True, ["FINDING"]),
            sj.JudgeResult("b", "f", "CLEAN", "FINDING", False, ["FINDING"]),
        ]
        self.assertEqual(sj.evaluate(rs), (1, 1))


class TestShell(unittest.TestCase):
    def test_cli_available_true(self):
        self.assertTrue(sj.cli_available(which=lambda _n: "/usr/bin/claude"))

    def test_cli_available_false(self):
        self.assertFalse(sj.cli_available(which=lambda _n: None))

    def test_call_claude_ok(self):
        runner = mock.Mock(return_value=_proc(stdout="FINDING"))
        self.assertEqual(sj._call_claude("p", "sonnet", runner), "FINDING")

    def test_call_claude_failure(self):
        runner = mock.Mock(return_value=_proc(stderr="boom", returncode=3))
        with self.assertRaises(sj.JudgeUnavailable):
            sj._call_claude("p", "sonnet", runner)


class TestJudgeAndRun(unittest.TestCase):
    @staticmethod
    def _caller(verdict):
        def _c(_prompt, _model):
            return f'{{"verdict":"{verdict}"}}'

        return _c

    def test_judge_fixture_pass(self):
        r = sj.judge_fixture(
            _fx("FINDING"),
            HERE.parent / "corpus",
            "sonnet",
            1,
            caller=self._caller("FINDING"),
        )
        self.assertTrue(r.ok)

    def test_judge_fixture_fail_with_injected_reader(self):
        r = sj.judge_fixture(
            _fx("CLEAN"),
            pathlib.Path("/nowhere"),
            "sonnet",
            3,
            caller=self._caller("FINDING"),
            reader=lambda _p: "echo 1;",
        )
        self.assertFalse(r.ok)
        self.assertEqual(r.verdict, "FINDING")

    def test_run_returns_all(self):
        rs = sj.run(
            [_fx("FINDING"), _fx("FINDING")],
            "sonnet",
            1,
            caller=self._caller("FINDING"),
            corpus_dir=HERE.parent / "corpus",
        )
        self.assertEqual(len(rs), 2)

    def test_render_has_summary(self):
        rs = [sj.JudgeResult("a", "f", "FINDING", "FINDING", True, ["FINDING"])]
        self.assertIn("passed", sj._render(rs))


class TestMain(unittest.TestCase):
    def test_even_votes_rejected(self):
        self.assertEqual(sj.main(["--votes", "2"]), 2)

    def test_skip_clean_without_cli(self):
        with mock.patch.object(sj, "cli_available", return_value=False):
            self.assertEqual(sj.main([]), 0)

    def test_require_without_cli(self):
        with mock.patch.object(sj, "cli_available", return_value=False):
            self.assertEqual(sj.main(["--require"]), 2)

    def test_gate_pass(self):
        good = [sj.JudgeResult("a", "f", "FINDING", "FINDING", True, ["FINDING"])]
        with (
            mock.patch.object(sj, "cli_available", return_value=True),
            mock.patch.object(sj, "run", return_value=good),
        ):
            self.assertEqual(sj.main(["--gate", "--limit", "1"]), 0)

    def test_gate_fail(self):
        bad = [sj.JudgeResult("a", "f", "CLEAN", "FINDING", False, ["FINDING"])]
        with (
            mock.patch.object(sj, "cli_available", return_value=True),
            mock.patch.object(sj, "run", return_value=bad),
        ):
            self.assertEqual(sj.main(["--gate"]), 1)

    def test_no_gate_with_failure_still_zero(self):
        bad = [sj.JudgeResult("a", "f", "CLEAN", "FINDING", False, ["FINDING"])]
        with (
            mock.patch.object(sj, "cli_available", return_value=True),
            mock.patch.object(sj, "run", return_value=bad),
        ):
            self.assertEqual(sj.main([]), 0)


if __name__ == "__main__":
    unittest.main()
