"""Coverage-completion tests for the LLM-judge engine (``judge.py``).

These complement ``test_judge_engine.py`` by exercising the error, retry, and
degrade branches that the happy-path suite does not reach: the ``_run_claude``
subprocess failure modes (unavailable CLI, timeout, non-zero exit, non-JSON
envelope, ``is_error`` envelope, missing ``.result``), the brace-scan string
escape handling, the ambiguous/unparseable verdict-extraction paths, the
cached/fresh "no 'dimensions' object" guards, the reprompt-exhaustion failure,
and the no-applicable-dimensions early return.

The real model call is never made: ``judge.subprocess.run`` and
``judge.shutil.which`` are mocked so these run with no credentials and no
network.
"""

import json
import pathlib
import subprocess
import sys
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "judge"))
sys.path.insert(0, str(HERE.parent / "lint"))

import _model  # noqa: E402
import judge  # noqa: E402
import rubrics  # noqa: E402


def make_skill(name="foo", raw="# Foo\nbody"):
    return _model.Artifact(
        path=pathlib.Path(f"/x/plugins/p/skills/{name}/SKILL.md"),
        plugin_root=pathlib.Path("/x/plugins/p"),
        kind="skill",
        raw=raw,
        has_frontmatter=True,
        frontmatter={
            "name": name,
            "description": "Create things. Use when adding things.",
        },
        frontmatter_error=None,
        body=raw,
        h1=None,
        h2_sections=["Profile keys consumed"],
    )


def _proc(returncode=0, stdout="", stderr=""):
    """A stand-in for the CompletedProcess returned by subprocess.run."""
    return mock.Mock(returncode=returncode, stdout=stdout, stderr=stderr)


class TestCliAvailable(unittest.TestCase):
    def test_available_true(self):
        # line 121: shutil.which returns a path -> True
        with mock.patch.object(judge.shutil, "which", return_value="/usr/bin/claude"):
            self.assertTrue(judge.cli_available())

    def test_available_false(self):
        with mock.patch.object(judge.shutil, "which", return_value=None):
            self.assertFalse(judge.cli_available())


class TestRunClaude(unittest.TestCase):
    """Exercise every failure branch of ``_run_claude`` via mocked subprocess."""

    def test_unavailable_raises(self):
        # line 174: cli_available() False -> JudgeUnavailable
        with mock.patch.object(judge.shutil, "which", return_value=None):
            with self.assertRaises(judge.JudgeUnavailable):
                judge._run_claude("p", "sonnet", 5)

    def test_timeout_raises_judge_error(self):
        # lines 189-190: subprocess.TimeoutExpired -> JudgeError
        with mock.patch.object(judge.shutil, "which", return_value="/usr/bin/claude"):
            with mock.patch.object(
                judge.subprocess,
                "run",
                side_effect=subprocess.TimeoutExpired(cmd="claude", timeout=5),
            ):
                with self.assertRaises(judge.JudgeError) as ctx:
                    judge._run_claude("p", "sonnet", 5)
        self.assertIn("timed out", str(ctx.exception))

    def test_nonzero_exit_raises(self):
        # line 192: returncode != 0 -> JudgeError
        with mock.patch.object(judge.shutil, "which", return_value="/usr/bin/claude"):
            with mock.patch.object(
                judge.subprocess, "run", return_value=_proc(returncode=2, stderr="boom")
            ):
                with self.assertRaises(judge.JudgeError) as ctx:
                    judge._run_claude("p", "sonnet", 5)
        self.assertIn("exited 2", str(ctx.exception))
        self.assertIn("boom", str(ctx.exception))

    def test_non_json_envelope_raises(self):
        # lines 197-198: json.JSONDecodeError on envelope -> JudgeError
        with mock.patch.object(judge.shutil, "which", return_value="/usr/bin/claude"):
            with mock.patch.object(
                judge.subprocess, "run", return_value=_proc(stdout="not json")
            ):
                with self.assertRaises(judge.JudgeError) as ctx:
                    judge._run_claude("p", "sonnet", 5)
        self.assertIn("envelope not JSON", str(ctx.exception))

    def test_envelope_is_error_raises(self):
        # line 201-204: envelope.is_error truthy -> JudgeError
        env = json.dumps({"is_error": True, "result": "model said no"})
        with mock.patch.object(judge.shutil, "which", return_value="/usr/bin/claude"):
            with mock.patch.object(
                judge.subprocess, "run", return_value=_proc(stdout=env)
            ):
                with self.assertRaises(judge.JudgeError) as ctx:
                    judge._run_claude("p", "sonnet", 5)
        self.assertIn("reported error", str(ctx.exception))

    def test_missing_string_result_raises(self):
        # line 207: result not a str -> JudgeError
        env = json.dumps({"result": {"not": "a string"}})
        with mock.patch.object(judge.shutil, "which", return_value="/usr/bin/claude"):
            with mock.patch.object(
                judge.subprocess, "run", return_value=_proc(stdout=env)
            ):
                with self.assertRaises(judge.JudgeError) as ctx:
                    judge._run_claude("p", "sonnet", 5)
        self.assertIn("missing string", str(ctx.exception))

    def test_success_returns_result(self):
        # happy path: returncode 0, JSON envelope, string result.
        env = json.dumps({"is_error": False, "result": "the answer"})
        with mock.patch.object(judge.shutil, "which", return_value="/usr/bin/claude"):
            with mock.patch.object(
                judge.subprocess, "run", return_value=_proc(stdout=env)
            ) as run:
                out = judge._run_claude("hello", "sonnet", 7)
        self.assertEqual(out, "the answer")
        # argv shape + neutral cwd are passed through.
        args, kwargs = run.call_args
        self.assertEqual(
            args[0],
            ["claude", "-p", "hello", "--model", "sonnet", "--output-format", "json"],
        )
        self.assertEqual(kwargs["timeout"], 7)
        self.assertTrue(kwargs["cwd"].startswith(judge.tempfile.gettempdir()))


class TestBraceScanState(unittest.TestCase):
    """Cover the in-string escape handling of the brace-balanced scanner."""

    def test_escaped_char_in_string(self):
        # line 246: in_str + escaped -> reset escaped, do not close brace.
        st = judge._BraceScanState()
        for c in '{"a\\"b"}':
            st.feed(c)
        # an escaped quote does not end the string; the final '}' closes depth 0.
        self.assertEqual(st.depth, 0)

    def test_backslash_sets_escape(self):
        # line 248: in_str + backslash -> set escaped True (then next char eaten).
        st = judge._BraceScanState()
        results = [st.feed(c) for c in '{"\\\\"}']
        # the closing brace after the balanced string returns True exactly once.
        self.assertEqual(results.count(True), 1)

    def test_escape_then_quote_via_extract(self):
        # End-to-end: a string with an escaped quote and braces inside it must
        # not throw off the depth count when extracting a verdict.
        text = (
            'prefix {"dimensions": {"J1": {"score": 4, '
            '"evidence": "he said \\"hi\\" {x}"}}} suffix'
        )
        obj = judge.extract_verdict(text)
        self.assertEqual(obj["dimensions"]["J1"]["evidence"], 'he said "hi" {x}')


class TestExtractVerdictBranches(unittest.TestCase):
    def test_candidate_unparseable_is_skipped(self):
        # lines 318-319: a top-level {...} that fails to parse is skipped, then a
        # later valid dimension-bearing object is returned. The first brace span
        # is invalid JSON (bare word value); the second is the real verdict.
        text = (
            "{not valid json at all} "
            '{"dimensions": {"J1": {"score": 3, "evidence": "ok"}}}'
        )
        obj = judge.extract_verdict(text)
        self.assertEqual(obj["dimensions"]["J1"]["score"], 3)

    def test_ambiguous_two_verdicts_raises(self):
        # lines 324-328: more than one dimension-bearing top-level object.
        decoy = '{"dimensions": {"J1": {"score": 5, "evidence": "decoy"}}}'
        real = '{"dimensions": {"J1": {"score": 1, "evidence": "real"}}}'
        # Wrapped so the fast-path whole-string parse fails and the scan runs.
        text = f"before {decoy} middle {real} after"
        with self.assertRaises(judge.JudgeError) as ctx:
            judge.extract_verdict(text)
        self.assertIn("ambiguous", str(ctx.exception))

    def test_zero_verdicts_raises(self):
        # line 329: no dimension-bearing object found at all.
        with self.assertRaises(judge.JudgeError) as ctx:
            judge.extract_verdict('text {"other": 1} more')
        self.assertIn("could not extract", str(ctx.exception))


class TestValidateNoDimensionsObject(unittest.TestCase):
    def setUp(self):
        self.dims = rubrics.applicable_dimensions("skill", "foo")

    def test_validate_verdict_missing_dimensions(self):
        # line 366: verdict['dimensions'] is not a dict.
        with self.assertRaises(judge.JudgeError) as ctx:
            judge.validate_verdict({"dimensions": "nope"}, self.dims)
        self.assertIn("no 'dimensions' object", str(ctx.exception))

    def test_validate_cached_aggregate_missing_dimensions(self):
        # line 402: votes > 1 cached aggregate whose 'dimensions' is not a dict.
        with self.assertRaises(judge.JudgeError) as ctx:
            judge._validate_cached({"dimensions": ["x"]}, self.dims, votes=3)
        self.assertIn("no 'dimensions' object", str(ctx.exception))

    def test_validate_cached_aggregate_not_dict(self):
        # line 401-402: top-level verdict not even a dict.
        with self.assertRaises(judge.JudgeError):
            judge._validate_cached(["not", "a", "dict"], self.dims, votes=3)


class TestSingleVerdictRetries(unittest.TestCase):
    def test_reprompt_exhaustion_raises(self):
        # line 433: all MAX_REPROMPTS+1 attempts fail -> JudgeError summarising.
        dims = rubrics.applicable_dimensions("skill", "foo")
        calls = []

        def bad(prompt, model, timeout):
            calls.append(prompt)
            return "no json here"

        with mock.patch.object(judge, "_run_claude", side_effect=bad):
            with self.assertRaises(judge.JudgeError) as ctx:
                judge._single_verdict("base prompt", dims, "sonnet", 5)
        self.assertIn("judging failed after retries", str(ctx.exception))
        # exactly MAX_REPROMPTS + 1 attempts; retries append a correction line.
        self.assertEqual(len(calls), judge.MAX_REPROMPTS + 1)
        self.assertEqual(calls[0], "base prompt")
        self.assertIn("previous answer was rejected", calls[1])

    def test_recovers_after_one_reprompt(self):
        # Covers the retry loop continuing then succeeding (not just exhausting).
        dims = rubrics.applicable_dimensions("skill", "foo")
        good = json.dumps(
            {"dimensions": {d.id: {"score": 4, "evidence": "x"} for d in dims}}
        )
        answers = iter(["garbage", good])

        with mock.patch.object(
            judge, "_run_claude", side_effect=lambda p, m, t: next(answers)
        ):
            out = judge._single_verdict("base", dims, "sonnet", 5)
        self.assertEqual(out["dimensions"][dims[0].id]["score"], 4)


class TestJudgeArtifactNoDims(unittest.TestCase):
    def test_no_applicable_dimensions_early_return(self):
        # line 590: an artifact kind with no applicable dimensions returns an
        # empty JudgeResult without ever calling the model. A meta-guide named so
        # that J10 still applies? J10 applies to all meta-guides, so instead use a
        # command whose name excludes the only command dims via name_filter.
        # Simplest: stub applicable_dimensions to return [].
        with mock.patch.object(judge.rubrics, "applicable_dimensions", return_value=[]):
            res = judge.judge_artifact(
                make_skill(), judge.JudgeOptions(use_cache=False)
            )
        self.assertEqual(res.dimensions, [])
        self.assertEqual(res.raw_verdict, {})
        self.assertFalse(res.cached)
        self.assertTrue(res.ok)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
