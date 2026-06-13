"""Coverage-completion tests for ``judge/run_judge.py`` (the CLI driver).

Every model call is stubbed: ``judge.judge_artifact``, ``judge.cli_available``,
and ``judge._run_claude`` are mocked so these run with no credentials and no
network. They exercise the rendering/report helpers, the threadpool fan-out in
``_judge_all``, artifact selection filters, the JSON/markdown report paths, the
calibration self-test (with scoring mocked), and the ``main`` glue — the lines
the engine suite leaves uncovered.
"""

import io
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "judge"))
sys.path.insert(0, str(HERE.parent / "lint"))

import _model  # noqa: E402
import calibration  # noqa: E402
import judge  # noqa: E402
import rubrics  # noqa: E402
import run_judge  # noqa: E402


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
        h2_sections=[],
    )


def make_dim_result(
    dim_id="J1",
    name="trigger-specificity",
    *,
    critical=True,
    score=4,
    passed=True,
    blocking=False,
    evidence="some evidence here",
):
    return judge.DimensionResult(
        id=dim_id,
        name=name,
        critical=critical,
        floor=4,
        block_floor=2,
        score=score,
        evidence=evidence,
        passed=passed,
        blocking=blocking,
    )


def make_result(path="plugins/p/skills/foo/SKILL.md", dimensions=None, *, cached=False):
    return judge.JudgeResult(
        path=path,
        kind="skill",
        name="foo",
        model="sonnet",
        cached=cached,
        dimensions=[] if dimensions is None else dimensions,
        raw_verdict={},
    )


def parse_args(argv):
    return run_judge._build_arg_parser().parse_args(argv)


class TestRenderResult(unittest.TestCase):
    def test_no_dimensions(self):
        out = run_judge._render_result(make_result(dimensions=[]))
        self.assertIn("(no applicable dimensions)", out)
        # Single header line + the no-dimensions note, nothing else.
        self.assertEqual(len(out.splitlines()), 2)

    def test_cached_marker_in_header(self):
        out = run_judge._render_result(make_result(dimensions=[], cached=True))
        self.assertIn("cached", out)

    def test_block_warn_ok_tags_and_critical_star(self):
        dims = [
            make_dim_result("J3", critical=True, score=1, passed=False, blocking=True),
            make_dim_result("J2", critical=False, score=3, passed=False),
            make_dim_result("J1", critical=True, score=5, passed=True),
        ]
        out = run_judge._render_result(make_result(dimensions=dims))
        lines = out.splitlines()
        # Sorted by id: J1 (ok, critical -> '*'), J2 (warn, not critical), J3 (BLOCK).
        self.assertIn("[ok   ]*", lines[1])
        self.assertIn("J1", lines[1])
        self.assertIn("[warn ] ", lines[2])
        self.assertIn("J2", lines[2])
        self.assertIn("[BLOCK]*", lines[3])
        self.assertIn("J3", lines[3])

    def test_evidence_truncated_to_160(self):
        long_ev = "x" * 500
        dim = make_dim_result(score=5, passed=True, blocking=False, evidence=long_ev)
        out = run_judge._render_result(make_result(dimensions=[dim]))
        # The 160-char slice means far fewer than 500 x's survive.
        self.assertLess(out.count("x"), 200)


class TestSelectArtifacts(unittest.TestCase):
    def test_kinds_filter(self):
        skill = make_skill("a")
        guide = _model.Artifact(
            path=pathlib.Path("/x/plugins/p/skills/g.md"),
            plugin_root=pathlib.Path("/x/plugins/p"),
            kind="meta-guide",
            raw="# g",
            has_frontmatter=False,
            frontmatter={},
            frontmatter_error=None,
            body="# g",
            h1="g",
            h2_sections=[],
        )
        with mock.patch.object(
            run_judge, "_collect_artifacts", return_value=[skill, guide]
        ):
            args = parse_args(["--kinds", "skill"])
            out = run_judge._select_artifacts(args)
        self.assertEqual([a.kind for a in out], ["skill"])

    def test_limit_truncates(self):
        arts = [make_skill(f"s{i}") for i in range(5)]
        with mock.patch.object(run_judge, "_collect_artifacts", return_value=arts):
            args = parse_args(["--limit", "2"])
            out = run_judge._select_artifacts(args)
        self.assertEqual(len(out), 2)

    def test_no_filters_passthrough(self):
        arts = [make_skill("only")]
        with mock.patch.object(run_judge, "_collect_artifacts", return_value=arts):
            args = parse_args([])
            out = run_judge._select_artifacts(args)
        self.assertEqual(len(out), 1)


class TestCollectArtifactsNoPaths(unittest.TestCase):
    def test_no_paths_walks_plugin_roots(self):
        root_a = pathlib.Path("/x/plugins/a")
        root_b = pathlib.Path("/x/plugins/b")
        art_a = make_skill("a")
        art_b = make_skill("b")

        def fake_discover(root):
            return [art_a] if root == root_a else [art_b]

        with (
            mock.patch.object(
                run_judge._model, "find_plugin_roots", return_value=[root_a, root_b]
            ),
            mock.patch.object(run_judge._model, "discover", side_effect=fake_discover),
        ):
            out = run_judge._collect_artifacts([])
        self.assertEqual(out, [art_a, art_b])


class TestJudgeAllThreadpool(unittest.TestCase):
    def _verdict(self, score):
        dims = rubrics.applicable_dimensions("skill", "foo")
        return [
            make_dim_result(
                d.id,
                d.name,
                critical=d.critical,
                score=score,
                passed=score >= d.floor,
                blocking=d.critical and score <= d.block_floor,
            )
            for d in dims
        ]

    def test_jobs_gt_one_parallel_path_success(self):
        arts = [make_skill("a"), make_skill("b")]

        def fake_judge(a, opts):
            return make_result(path=f"plugins/p/skills/{a.name}/SKILL.md")

        args = parse_args(["--jobs", "2"])
        with (
            mock.patch.object(judge, "judge_artifact", side_effect=fake_judge),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
        ):
            results, errors = run_judge._judge_all(arts, args)
        self.assertEqual(len(results), 2)
        self.assertEqual(errors, [])
        # Sorted by path: a before b.
        self.assertEqual([r.path for r in results], sorted(r.path for r in results))

    def test_jobs_gt_one_parallel_path_records_error(self):
        arts = [make_skill("a"), make_skill("b")]

        def fake_judge(a, opts):
            if a.name == "a":
                raise judge.JudgeError("boom")
            return make_result(path="plugins/p/skills/b/SKILL.md")

        args = parse_args(["--jobs", "2"])
        with (
            mock.patch.object(judge, "judge_artifact", side_effect=fake_judge),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO) as err,
        ):
            results, errors = run_judge._judge_all(arts, args)
        self.assertEqual(len(results), 1)
        self.assertEqual(len(errors), 1)
        self.assertIn("boom", errors[0])
        self.assertIn("ERROR judging", err.getvalue())

    def test_jobs_gt_one_single_artifact_uses_serial(self):
        # len(artifacts) <= 1 keeps the serial branch even with --jobs 4.
        arts = [make_skill("solo")]
        args = parse_args(["--jobs", "4"])
        with (
            mock.patch.object(
                judge, "judge_artifact", return_value=make_result()
            ) as mj,
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
        ):
            results, errors = run_judge._judge_all(arts, args)
        self.assertEqual(len(results), 1)
        self.assertEqual(errors, [])
        self.assertEqual(mj.call_count, 1)

    def test_serial_path_records_error(self):
        arts = [make_skill("a")]
        args = parse_args([])
        with (
            mock.patch.object(
                judge, "judge_artifact", side_effect=judge.JudgeError("nope")
            ),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
        ):
            results, errors = run_judge._judge_all(arts, args)
        self.assertEqual(results, [])
        self.assertEqual(len(errors), 1)


class TestReport(unittest.TestCase):
    def test_json_emitted_to_stdout(self):
        dim = make_dim_result(score=3, passed=False)
        results = [make_result(dimensions=[dim])]
        args = parse_args(["--json"])
        with (
            mock.patch.object(run_judge.sys, "stdout", new_callable=io.StringIO) as out,
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
        ):
            run_judge._report(args, results, [], [], [])
        payload = json.loads(out.getvalue())
        self.assertEqual(payload[0]["path"], results[0].path)
        self.assertEqual(payload[0]["dimensions"][0]["id"], "J1")

    def test_report_file_written(self):
        results = [make_result(dimensions=[make_dim_result()])]
        with tempfile.TemporaryDirectory() as td:
            rp = pathlib.Path(td) / "report.md"
            args = parse_args(["--report", str(rp)])
            with mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO):
                run_judge._report(args, results, [], [], [])
            text = rp.read_text(encoding="utf-8")
        self.assertIn("# LLM-as-judge report", text)
        self.assertIn("artifacts judged: 1", text)

    def test_summary_only_no_json_no_report(self):
        args = parse_args([])
        with mock.patch.object(
            run_judge.sys, "stderr", new_callable=io.StringIO
        ) as err:
            run_judge._report(args, [], [], [], [])
        self.assertIn("judge summary:", err.getvalue())


class TestWriteReport(unittest.TestCase):
    def test_full_report_all_sections(self):
        blk = make_dim_result("J3", "degrade", score=1, passed=False, blocking=True)
        adv = make_dim_result("J5", "advisory", critical=False, score=3, passed=False)
        rb = make_result(path="plugins/p/skills/b/SKILL.md", dimensions=[blk])
        ra = make_result(path="plugins/p/skills/a/SKILL.md", dimensions=[adv])
        with tempfile.TemporaryDirectory() as td:
            rp = pathlib.Path(td) / "r.md"
            run_judge._write_report(
                rp,
                [rb, ra],
                [(rb, blk)],
                [(ra, adv)],
                ["plugins/p/skills/x/SKILL.md: oops"],
            )
            text = rp.read_text(encoding="utf-8")
        self.assertIn("blocking failures: 1", text)
        self.assertIn("advisory findings: 1", text)
        self.assertIn("errors: 1", text)
        self.assertIn("## Blocking (critical, score <= block floor)", text)
        self.assertIn("J3 degrade = 1/5", text)
        self.assertIn("## Advisory (score below floor)", text)
        self.assertIn("J5 advisory = 3/5", text)
        self.assertIn("## Errors", text)
        self.assertIn("- plugins/p/skills/x/SKILL.md: oops", text)

    def test_empty_report_no_sections(self):
        with tempfile.TemporaryDirectory() as td:
            rp = pathlib.Path(td) / "r.md"
            run_judge._write_report(rp, [], [], [], [])
            text = rp.read_text(encoding="utf-8")
        self.assertIn("artifacts judged: 0", text)
        self.assertNotIn("## Blocking", text)
        self.assertNotIn("## Advisory", text)
        self.assertNotIn("## Errors", text)


class TestScoreCalibrationCase(unittest.TestCase):
    def test_returns_target_dimension_score(self):
        case = calibration.positive_for("J1")
        dims = rubrics.applicable_dimensions(case.kind, case.name)
        res = make_result(
            dimensions=[
                make_dim_result(d.id, d.name, score=5 if d.id == "J1" else 4)
                for d in dims
            ]
        )
        with mock.patch.object(judge, "judge_artifact", return_value=res):
            score = run_judge._score_calibration_case(case, "sonnet")
        self.assertEqual(score, 5)

    def test_missing_target_dimension_raises(self):
        case = calibration.positive_for("J1")
        # A result whose dimensions never include the case's target id.
        res = make_result(dimensions=[make_dim_result("J99", "other", score=3)])
        with mock.patch.object(judge, "judge_artifact", return_value=res):
            with self.assertRaises(judge.JudgeError):
                run_judge._score_calibration_case(case, "sonnet")


class TestSelftestOneDimension(unittest.TestCase):
    def test_pass_when_p_high_n_low(self):
        with mock.patch.object(
            run_judge, "_score_calibration_case", side_effect=[5, 1]
        ):
            dim_id, p, n, passed, note = run_judge._selftest_one_dimension(
                "J1", "sonnet"
            )
        self.assertEqual((dim_id, p, n, passed, note), ("J1", 5, 1, True, ""))

    def test_fail_when_p_below_floor(self):
        with mock.patch.object(
            run_judge, "_score_calibration_case", side_effect=[2, 1]
        ):
            _, _, _, passed, note = run_judge._selftest_one_dimension("J1", "sonnet")
        self.assertFalse(passed)
        self.assertIn("< floor", note)

    def test_fail_when_n_above_block_floor(self):
        with mock.patch.object(
            run_judge, "_score_calibration_case", side_effect=[5, 4]
        ):
            _, _, _, passed, note = run_judge._selftest_one_dimension("J1", "sonnet")
        self.assertFalse(passed)
        self.assertIn("> block_floor", note)

    def test_missing_calibration_case(self):
        with mock.patch.object(calibration, "positive_for", return_value=None):
            dim_id, p, n, passed, note = run_judge._selftest_one_dimension(
                "J1", "sonnet"
            )
        self.assertEqual((p, n, passed), (None, None, False))
        self.assertIn("missing P or N", note)

    def test_judge_error_marks_not_passed(self):
        with mock.patch.object(
            run_judge,
            "_score_calibration_case",
            side_effect=judge.JudgeError("kaboom"),
        ):
            _, p, n, passed, note = run_judge._selftest_one_dimension("J1", "sonnet")
        self.assertEqual((p, n, passed), (None, None, False))
        self.assertIn("judge error", note)


class TestRunSelftest(unittest.TestCase):
    def test_all_pass_exit_zero(self):
        rows = [(d, 5, 1, True, "") for d in calibration.CRITICAL_DIMENSION_IDS]
        with (
            mock.patch.object(run_judge, "_selftest_one_dimension", side_effect=rows),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO) as err,
        ):
            rc = run_judge.run_selftest("sonnet")
        self.assertEqual(rc, 0)
        self.assertIn("PASS", err.getvalue())

    def test_any_fail_exit_one_and_dash_for_none(self):
        ids = calibration.CRITICAL_DIMENSION_IDS
        rows = [(ids[0], None, None, False, "missing P or N calibration case")]
        rows += [(d, 5, 1, True, "") for d in ids[1:]]
        with (
            mock.patch.object(run_judge, "_selftest_one_dimension", side_effect=rows),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO) as err,
        ):
            rc = run_judge.run_selftest("sonnet")
        self.assertEqual(rc, 1)
        out = err.getvalue()
        self.assertIn("FAIL", out)
        # None scores render as '-'.
        self.assertRegex(out, r"\s-\s+-\s+FAIL")


class TestMainSelftest(unittest.TestCase):
    def test_selftest_skips_without_cli(self):
        with (
            mock.patch.object(judge, "cli_available", return_value=False),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO) as err,
        ):
            self.assertEqual(run_judge.main(["--selftest"]), 0)
        self.assertIn("SKIPPED", err.getvalue())

    def test_selftest_require_without_cli_exit_two(self):
        with (
            mock.patch.object(judge, "cli_available", return_value=False),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
        ):
            self.assertEqual(run_judge.main(["--selftest", "--require"]), 2)

    def test_selftest_runs_when_cli_available(self):
        rows = [(d, 5, 1, True, "") for d in calibration.CRITICAL_DIMENSION_IDS]
        with (
            mock.patch.object(judge, "cli_available", return_value=True),
            mock.patch.object(run_judge, "_selftest_one_dimension", side_effect=rows),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
        ):
            self.assertEqual(run_judge.main(["--selftest"]), 0)


class TestMainFlow(unittest.TestCase):
    def test_full_flow_json_and_report(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        dim_results = [
            make_dim_result(
                d.id, d.name, critical=d.critical, score=5, passed=True, blocking=False
            )
            for d in dims
        ]
        result = make_result(dimensions=dim_results)
        with tempfile.TemporaryDirectory() as td:
            rp = pathlib.Path(td) / "out.md"
            with (
                mock.patch.object(judge, "cli_available", return_value=True),
                mock.patch.object(
                    run_judge, "_select_artifacts", return_value=[make_skill()]
                ),
                mock.patch.object(judge, "judge_artifact", return_value=result),
                mock.patch.object(
                    run_judge.sys, "stdout", new_callable=io.StringIO
                ) as out,
                mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
            ):
                rc = run_judge.main(["--json", "--report", str(rp), "--jobs", "2"])
            report_text = rp.read_text(encoding="utf-8")
        self.assertEqual(rc, 0)
        self.assertIn("# LLM-as-judge report", report_text)
        json.loads(out.getvalue())  # stdout was valid JSON

    def test_gate_passes_when_clean(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        dim_results = [
            make_dim_result(d.id, d.name, critical=d.critical, score=5, passed=True)
            for d in dims
        ]
        result = make_result(dimensions=dim_results)
        with (
            mock.patch.object(judge, "cli_available", return_value=True),
            mock.patch.object(
                run_judge, "_select_artifacts", return_value=[make_skill()]
            ),
            mock.patch.object(judge, "judge_artifact", return_value=result),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
        ):
            self.assertEqual(run_judge.main(["--gate"]), 0)

    def test_gate_fails_on_blocking(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        dim_results = [
            make_dim_result(
                d.id,
                d.name,
                critical=d.critical,
                score=1 if d.critical else 5,
                passed=not d.critical,
                blocking=d.critical,
            )
            for d in dims
        ]
        result = make_result(dimensions=dim_results)
        with (
            mock.patch.object(judge, "cli_available", return_value=True),
            mock.patch.object(
                run_judge, "_select_artifacts", return_value=[make_skill()]
            ),
            mock.patch.object(judge, "judge_artifact", return_value=result),
            mock.patch.object(run_judge.sys, "stderr", new_callable=io.StringIO),
        ):
            self.assertEqual(run_judge.main(["--gate"]), 1)


if __name__ == "__main__":
    unittest.main()
