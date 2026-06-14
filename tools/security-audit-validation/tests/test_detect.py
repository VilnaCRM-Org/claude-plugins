"""Tests for the detection harness — pure compare, thin shell, dep lane."""

import contextlib
import io
import json
import pathlib
import sys
import types
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import corpus  # noqa: E402
import detect  # noqa: E402


def _proc(stdout="", stderr="", returncode=0):
    return types.SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)


def _semgrep_json(*results):
    return json.dumps({"results": list(results)})


def _hit(path, family):
    return {"path": path, "extra": {"metadata": {"family": family}}}


class TestRunSemgrep(unittest.TestCase):
    def test_parses_json(self):
        runner = mock.Mock(return_value=_proc(stdout=_semgrep_json(_hit("a.php", "x"))))
        out = detect._run_semgrep(pathlib.Path("r.yml"), pathlib.Path("a.php"), runner)
        self.assertEqual(out["results"][0]["path"], "a.php")

    def test_empty_stdout_raises(self):
        runner = mock.Mock(
            return_value=_proc(stdout="   ", stderr="boom", returncode=2)
        )
        with self.assertRaises(detect.SemgrepUnavailable):
            detect._run_semgrep(pathlib.Path("r.yml"), pathlib.Path("t"), runner)

    def test_missing_binary_raises(self):
        def runner(*a, **k):
            raise FileNotFoundError("no semgrep")

        with self.assertRaises(detect.SemgrepUnavailable):
            detect._run_semgrep(pathlib.Path("r.yml"), pathlib.Path("t"), runner)

    def test_bad_json_raises(self):
        runner = mock.Mock(return_value=_proc(stdout="not json"))
        with self.assertRaises(detect.SemgrepUnavailable):
            detect._run_semgrep(pathlib.Path("r.yml"), pathlib.Path("t"), runner)


class TestResultFamily(unittest.TestCase):
    def test_family_present(self):
        self.assertEqual(detect._result_family(_hit("a", "sqli")), "sqli")

    def test_family_absent(self):
        self.assertIsNone(detect._result_family({"path": "a"}))

    def test_family_non_string(self):
        self.assertIsNone(detect._result_family({"extra": {"metadata": {"family": 7}}}))


class TestFamiliesByPath(unittest.TestCase):
    def test_maps_and_skips_familyless(self):
        cd = pathlib.Path("/corpus")
        data = {
            "results": [
                _hit("/corpus/sqli/vulnerable.php", "sqli"),
                _hit("/corpus/sqli/vulnerable.php", "ssrf"),
                {"path": "/corpus/x.php"},  # no family -> skipped
            ]
        }
        out = detect.families_by_path(data, cd)
        self.assertEqual(out["sqli/vulnerable.php"], {"sqli", "ssrf"})
        self.assertNotIn("x.php", out)


class TestEvaluateStatic(unittest.TestCase):
    def _fx(self, expect):
        return corpus.Fixture("C", "sqli", "sqli/x.php", "CWE-89", expect, "FINDING")

    def test_finding_pass(self):
        r = detect.evaluate_static([self._fx(corpus.FINDING)], {"sqli/x.php": {"sqli"}})
        self.assertTrue(r[0].ok)

    def test_finding_false_negative(self):
        r = detect.evaluate_static([self._fx(corpus.FINDING)], {})
        self.assertFalse(r[0].ok)
        self.assertIn("FALSE NEGATIVE", r[0].detail)

    def test_clean_pass(self):
        r = detect.evaluate_static([self._fx(corpus.CLEAN)], {})
        self.assertTrue(r[0].ok)

    def test_clean_false_positive(self):
        r = detect.evaluate_static([self._fx(corpus.CLEAN)], {"sqli/x.php": {"sqli"}})
        self.assertFalse(r[0].ok)
        self.assertIn("FALSE POSITIVE", r[0].detail)


class TestVersionHelpers(unittest.TestCase):
    def test_parse_plain(self):
        self.assertEqual(detect._parse_version("6.5.5"), (6, 5, 5))

    def test_parse_operator_and_v(self):
        self.assertEqual(detect._parse_version("^v7.4.3"), (7, 4, 3))

    def test_parse_short_pads(self):
        self.assertEqual(detect._parse_version("7.4"), (7, 4, 0))

    def test_parse_non_numeric_component(self):
        self.assertEqual(detect._parse_version("7.x.beta"), (7, 0, 0))

    def test_pin_in_range(self):
        self.assertTrue(detect._pin_is_vulnerable((6, 5, 5), [((0, 0, 0), (6, 5, 6))]))

    def test_pin_out_of_range(self):
        self.assertFalse(detect._pin_is_vulnerable((7, 9, 2), [((0, 0, 0), (6, 5, 6))]))

    def test_extract_pin_require(self):
        self.assertEqual(detect._extract_pin({"require": {"p": "1.0"}}, "p"), "1.0")

    def test_extract_pin_require_dev(self):
        self.assertEqual(detect._extract_pin({"require-dev": {"p": "2.0"}}, "p"), "2.0")

    def test_extract_pin_missing(self):
        self.assertIsNone(detect._extract_pin({"require": {}}, "p"))


class TestEvaluateDeps(unittest.TestCase):
    def _case(self, expect_vuln):
        return corpus.DepCase("D", "deps/x.json", "guzzlehttp/guzzle", expect_vuln)

    @staticmethod
    def _reader(body):
        def _read(_path):
            return body

        return _read

    def test_vulnerable_match(self):
        reader = self._reader('{"require":{"guzzlehttp/guzzle":"6.5.5"}}')
        r = detect.evaluate_deps([self._case(True)], pathlib.Path("/c"), reader=reader)
        self.assertTrue(r[0].ok)

    def test_clean_match(self):
        reader = self._reader('{"require":{"guzzlehttp/guzzle":"7.9.2"}}')
        r = detect.evaluate_deps([self._case(False)], pathlib.Path("/c"), reader=reader)
        self.assertTrue(r[0].ok)

    def test_mismatch(self):
        reader = self._reader('{"require":{"guzzlehttp/guzzle":"6.5.5"}}')
        r = detect.evaluate_deps([self._case(False)], pathlib.Path("/c"), reader=reader)
        self.assertFalse(r[0].ok)

    def test_not_pinned(self):
        reader = self._reader('{"require":{}}')
        r = detect.evaluate_deps([self._case(True)], pathlib.Path("/c"), reader=reader)
        self.assertFalse(r[0].ok)
        self.assertIn("not pinned", r[0].detail)

    def test_unreadable(self):
        def reader(p):
            raise OSError("gone")

        r = detect.evaluate_deps([self._case(True)], pathlib.Path("/c"), reader=reader)
        self.assertFalse(r[0].ok)
        self.assertIn("unreadable", r[0].detail)

    def test_default_reader_reads_disk(self):
        # Exercises the default reader branch against the real corpus fixtures.
        r = detect.evaluate_deps(list(corpus.DEP_CASES), HERE.parent / "corpus")
        self.assertTrue(all(x.ok for x in r))


class TestRunAndMain(unittest.TestCase):
    def _fake_runner(self):
        body = _semgrep_json(
            _hit(str(HERE.parent / "corpus" / "sqli" / "vulnerable.php"), "sqli")
        )
        return mock.Mock(return_value=_proc(stdout=body))

    def test_run_combines_lanes(self):
        results = detect.run(runner=self._fake_runner())
        cids = {r.cid for r in results}
        self.assertIn("SC-SQLI-P", cids)
        self.assertIn("SC-DEP-P", cids)

    def test_render_contains_summary(self):
        out = detect._render([detect.Result("C", "static", True, "ok")])
        self.assertIn("passed", out)

    def test_main_all_ok(self):
        ok = [detect.Result("C", "static", True, "ok")]
        with mock.patch.object(detect, "run", return_value=ok):
            self.assertEqual(detect.main([]), 0)

    def test_main_json(self):
        ok = [detect.Result("C", "static", True, "ok")]
        buf = io.StringIO()
        with mock.patch.object(detect, "run", return_value=ok):
            with contextlib.redirect_stdout(buf):
                self.assertEqual(detect.main(["--json"]), 0)
        self.assertIn('"cid": "C"', buf.getvalue())

    def test_main_failure(self):
        bad = [detect.Result("C", "static", False, "FALSE NEGATIVE")]
        with mock.patch.object(detect, "run", return_value=bad):
            self.assertEqual(detect.main([]), 1)

    def test_main_semgrep_unavailable(self):
        with mock.patch.object(
            detect, "run", side_effect=detect.SemgrepUnavailable("no engine")
        ):
            self.assertEqual(detect.main([]), 2)


if __name__ == "__main__":
    unittest.main()
