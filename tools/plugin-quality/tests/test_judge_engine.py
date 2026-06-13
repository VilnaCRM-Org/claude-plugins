"""Claude-free unit tests for the LLM-judge engine.

The actual model call (``judge._run_claude``) is stubbed, so these run in CI
with no credentials and no network. They lock the deterministic parts: verdict
extraction, structural validation, vote aggregation, the advisory-vs-blocking
gate, and the skip-when-unavailable behaviour of the runner.
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
import cache  # noqa: E402
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
        h2_sections=["Profile keys consumed"],
    )


def verdict_for(dims, score):
    return {
        "dimensions": {
            d.id: {"score": score, "evidence": f"reason {d.id}"} for d in dims
        }
    }


class TestExtractVerdict(unittest.TestCase):
    def test_plain_json(self):
        obj = judge.extract_verdict(
            '{"dimensions": {"J1": {"score": 4, "evidence": "x"}}}'
        )
        self.assertEqual(obj["dimensions"]["J1"]["score"], 4)

    def test_fenced_json(self):
        text = '```json\n{"dimensions": {"J1": {"score": 5, "evidence": "x"}}}\n```'
        self.assertIn("J1", judge.extract_verdict(text)["dimensions"])

    def test_json_with_prose(self):
        text = (
            "Here is my verdict:\n"
            '{"dimensions": {"J1": {"score": 3, "evidence": "x"}}}\nDone.'
        )
        self.assertEqual(judge.extract_verdict(text)["dimensions"]["J1"]["score"], 3)

    def test_unparseable_raises(self):
        with self.assertRaises(judge.JudgeError):
            judge.extract_verdict("no json here at all")


class TestValidateVerdict(unittest.TestCase):
    def setUp(self):
        self.dims = rubrics.applicable_dimensions("skill", "foo")

    def test_valid(self):
        v = verdict_for(self.dims, 4)
        self.assertIs(judge.validate_verdict(v, self.dims), v)

    def test_missing_dimension(self):
        v = verdict_for(self.dims, 4)
        del v["dimensions"][self.dims[0].id]
        with self.assertRaises(judge.JudgeError):
            judge.validate_verdict(v, self.dims)

    def test_bad_score(self):
        v = verdict_for(self.dims, 4)
        v["dimensions"][self.dims[0].id]["score"] = 9
        with self.assertRaises(judge.JudgeError):
            judge.validate_verdict(v, self.dims)

    def test_empty_evidence(self):
        v = verdict_for(self.dims, 4)
        v["dimensions"][self.dims[0].id]["evidence"] = ""
        with self.assertRaises(judge.JudgeError):
            judge.validate_verdict(v, self.dims)


class TestGate(unittest.TestCase):
    def setUp(self):
        self._orig = judge._run_claude

    def tearDown(self):
        judge._run_claude = self._orig

    def _stub(self, score):
        dims = rubrics.applicable_dimensions("skill", "foo")
        payload = json.dumps(verdict_for(dims, score))
        judge._run_claude = lambda prompt, model, timeout: payload

    def test_all_pass(self):
        self._stub(5)
        res = judge.judge_artifact(make_skill(), judge.JudgeOptions(use_cache=False))
        self.assertTrue(res.ok)
        self.assertEqual(res.blocking_failures, [])

    def test_score3_crit_is_advisory_not_blocking(self):
        # score 3 on a critical dim: below floor (advisory) but above block_floor.
        self._stub(3)
        res = judge.judge_artifact(make_skill(), judge.JudgeOptions(use_cache=False))
        self.assertTrue(res.ok, "score 3 must not hard-block")
        self.assertTrue(res.advisory_failures, "score 3 must be advisory")

    def test_score2_crit_blocks(self):
        self._stub(2)
        res = judge.judge_artifact(make_skill(), judge.JudgeOptions(use_cache=False))
        self.assertFalse(res.ok)
        crit_ids = {d.id for d in res.blocking_failures}
        self.assertTrue(crit_ids)  # at least one critical dim blocked

    def test_noncritical_never_blocks(self):
        self._stub(1)
        res = judge.judge_artifact(make_skill(), judge.JudgeOptions(use_cache=False))
        # every blocking failure must be a critical dimension
        self.assertTrue(all(d.critical for d in res.blocking_failures))


class TestAggregate(unittest.TestCase):
    def test_median_low(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        verdicts = [verdict_for(dims, 5), verdict_for(dims, 1), verdict_for(dims, 3)]
        agg = judge._aggregate(verdicts, dims)
        # median_low of [5,1,3] sorted [1,3,5] -> 3
        self.assertEqual(agg["dimensions"][dims[0].id]["score"], 3)
        self.assertEqual(agg["votes"], 3)

    def test_votes_block_path(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        # two low, one high -> median_low leans strict
        scores = iter([2, 2, 4])
        judge_orig = judge._run_claude
        try:
            judge._run_claude = lambda prompt, model, timeout: json.dumps(
                verdict_for(dims, next(scores))
            )
            res = judge.judge_artifact(
                make_skill(), judge.JudgeOptions(use_cache=False, votes=3)
            )
        finally:
            judge._run_claude = judge_orig
        self.assertFalse(res.ok)  # median_low([2,2,4]) = 2 -> blocks on crit dims


class TestRunnerSkip(unittest.TestCase):
    def setUp(self):
        self._orig = judge.cli_available

    def tearDown(self):
        judge.cli_available = self._orig

    def test_skip_when_unavailable(self):
        judge.cli_available = lambda: False
        self.assertEqual(run_judge.main([]), 0)

    def test_require_fails_when_unavailable(self):
        judge.cli_available = lambda: False
        self.assertEqual(run_judge.main(["--require"]), 2)


def make_command(name="sdlc-qa", raw="# Cmd\nbody"):
    return _model.Artifact(
        path=pathlib.Path(f"/x/plugins/p/commands/{name}.md"),
        plugin_root=pathlib.Path("/x/plugins/p"),
        kind="command",
        raw=raw,
        has_frontmatter=True,
        frontmatter={"name": name, "description": "Do a thing. Use when needed."},
        frontmatter_error=None,
        body=raw,
        h1=None,
        h2_sections=[],
    )


class _StubClaude:
    """Context-managed mock of judge._run_claude — never a real claude call."""

    def __init__(self, payloads):
        # payloads: a single str, or an iterable of strings consumed per-call.
        if isinstance(payloads, str):
            self._iter = iter([payloads] * 1000)
        else:
            self._iter = iter(payloads)

    def __enter__(self):
        self._patch = mock.patch.object(
            judge,
            "_run_claude",
            side_effect=lambda prompt, model, timeout: next(self._iter),
        )
        self._mock = self._patch.start()
        return self._mock

    def __exit__(self, *exc):
        self._patch.stop()
        return False


# ---- S1-A: cache hit must be revalidated ----------------------------------
class TestS1ACacheHitRevalidated(unittest.TestCase):
    def setUp(self):
        self.dims = rubrics.applicable_dimensions("skill", "foo")
        self._tmp = tempfile.TemporaryDirectory()
        self._cache_patch = mock.patch.object(
            cache, "CACHE_DIR", pathlib.Path(self._tmp.name)
        )
        self._cache_patch.start()

    def tearDown(self):
        self._cache_patch.stop()
        self._tmp.cleanup()

    def test_poisoned_cache_entry_triggers_rejudge(self):
        art = make_skill()
        ab = art.raw.encode("utf-8")
        fp = rubrics.guidance_fingerprint()
        cm = f"sonnet|votes=1|rubric={fp}"
        dim_ids = [d.id for d in self.dims]
        # Poison: an entry missing a required dimension (structurally invalid).
        poisoned = verdict_for(self.dims, 5)
        del poisoned["dimensions"][self.dims[0].id]
        cache.put(ab, cm, dim_ids, poisoned)
        # On read, the poisoned hit must be a MISS -> a real (stubbed) judge call.
        with _StubClaude(json.dumps(verdict_for(self.dims, 4))) as m:
            res = judge.judge_artifact(
                art, judge.JudgeOptions(model="sonnet", use_cache=True)
            )
        self.assertTrue(m.called, "poisoned cache must trigger a re-judge")
        self.assertFalse(res.cached)
        self.assertTrue(res.ok)

    def test_valid_cache_entry_is_served_without_call(self):
        art = make_skill()
        ab = art.raw.encode("utf-8")
        fp = rubrics.guidance_fingerprint()
        cm = f"sonnet|votes=1|rubric={fp}"
        dim_ids = [d.id for d in self.dims]
        cache.put(ab, cm, dim_ids, verdict_for(self.dims, 5))
        with _StubClaude("SHOULD NOT BE CALLED") as m:
            res = judge.judge_artifact(
                art, judge.JudgeOptions(model="sonnet", use_cache=True)
            )
        self.assertFalse(m.called, "valid cache hit must not call claude")
        self.assertTrue(res.cached)

    def test_aggregate_cache_with_bad_score_rejudges(self):
        art = make_skill()
        ab = art.raw.encode("utf-8")
        fp = rubrics.guidance_fingerprint()
        cm = f"sonnet|votes=3|rubric={fp}"
        dim_ids = [d.id for d in self.dims]
        # Aggregate-shaped cache entry with an out-of-range score -> MISS.
        bad = {
            "dimensions": {d.id: {"score": 9, "evidence": "x"} for d in self.dims},
            "votes": 3,
        }
        cache.put(ab, cm, dim_ids, bad)
        with _StubClaude([json.dumps(verdict_for(self.dims, 4))] * 3) as m:
            res = judge.judge_artifact(
                art, judge.JudgeOptions(model="sonnet", use_cache=True, votes=3)
            )
        self.assertTrue(m.called)
        self.assertFalse(res.cached)


# ---- S1-B: non-JudgeError in one artifact must not abort the run ----------
class TestS1BErrorsBecomeEntries(unittest.TestCase):
    def setUp(self):
        self._cli = judge.cli_available
        self._judge = judge.judge_artifact
        self._collect = run_judge._collect_artifacts
        judge.cli_available = lambda: True

    def tearDown(self):
        judge.cli_available = self._cli
        judge.judge_artifact = self._judge
        run_judge._collect_artifacts = self._collect

    def test_keyerror_in_one_artifact_is_caught_as_error(self):
        art = make_skill()
        run_judge._collect_artifacts = lambda paths: [art]

        def boom(a, options=None):
            raise KeyError("poisoned verdict")

        judge.judge_artifact = boom
        # --gate so errors fail the run with exit 1 (never an aborted traceback).
        rc = run_judge.main(["--gate", "x"])
        self.assertEqual(rc, 1)

    def test_judge_artifact_wraps_structural_problem_as_judgeerror(self):
        art = make_skill()
        # _run_claude returns a verdict whose 'dimensions' is the wrong type;
        # extract/validate pass shape-wise only if dict — here force a TypeError
        # in result-building by stubbing _single_verdict to return junk.
        with mock.patch.object(
            judge, "_single_verdict", return_value={"dimensions": "not-a-dict"}
        ):
            with self.assertRaises(judge.JudgeError):
                judge.judge_artifact(art, judge.JudgeOptions(use_cache=False))


# ---- S2-A: bool scores rejected -------------------------------------------
class TestS2ABoolScore(unittest.TestCase):
    def test_true_score_rejected(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        v = verdict_for(dims, 4)
        v["dimensions"][dims[0].id]["score"] = True
        with self.assertRaises(judge.JudgeError):
            judge.validate_verdict(v, dims)

    def test_false_score_rejected(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        v = verdict_for(dims, 4)
        v["dimensions"][dims[0].id]["score"] = False
        with self.assertRaises(judge.JudgeError):
            judge.validate_verdict(v, dims)


# ---- S2-B: extra/hallucinated dimension ids rejected ----------------------
class TestS2BExtraDims(unittest.TestCase):
    def test_extra_dimension_rejected(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        v = verdict_for(dims, 4)
        v["dimensions"]["J999"] = {"score": 5, "evidence": "hallucinated"}
        with self.assertRaises(judge.JudgeError):
            judge.validate_verdict(v, dims)


# ---- S2-C: extract handles prose+JSON+prose, two objects, stray braces ----
class TestS2CExtractRobust(unittest.TestCase):
    def test_prose_json_prose(self):
        text = (
            'Sure! {"dimensions": {"J1": {"score": 4, "evidence": "ok"}}} '
            "Hope that helps."
        )
        self.assertEqual(judge.extract_verdict(text)["dimensions"]["J1"]["score"], 4)

    def test_two_objects_picks_one_with_dimensions(self):
        text = (
            '{"note": "ignore me"} then '
            '{"dimensions": {"J1": {"score": 3, "evidence": "y"}}}'
        )
        out = judge.extract_verdict(text)
        self.assertIn("dimensions", out)
        self.assertEqual(out["dimensions"]["J1"]["score"], 3)

    def test_stray_braces_in_strings(self):
        text = (
            'prefix {"dimensions": {"J1": {"score": 2, '
            '"evidence": "has } brace { inside"}}} suffix'
        )
        out = judge.extract_verdict(text)
        self.assertEqual(out["dimensions"]["J1"]["evidence"], "has } brace { inside")

    def test_leading_stray_open_brace(self):
        text = (
            "{ broken not json { then "
            '{"dimensions": {"J1": {"score": 5, "evidence": "z"}}}'
        )
        out = judge.extract_verdict(text)
        self.assertEqual(out["dimensions"]["J1"]["score"], 5)


# ---- S2-D: trailing-comma tolerance ---------------------------------------
class TestS2DTrailingComma(unittest.TestCase):
    def test_trailing_comma_object(self):
        text = '{"dimensions": {"J1": {"score": 4, "evidence": "ok",},},}'
        out = judge.extract_verdict(text)
        self.assertEqual(out["dimensions"]["J1"]["score"], 4)

    def test_trailing_comma_with_prose(self):
        text = 'Verdict: {"dimensions": {"J1": {"score": 3, "evidence": "x",}}}'
        self.assertEqual(judge.extract_verdict(text)["dimensions"]["J1"]["score"], 3)


# ---- S2-E: even vote counts rejected --------------------------------------
class TestS2EEvenVotes(unittest.TestCase):
    def setUp(self):
        self._cli = judge.cli_available
        judge.cli_available = lambda: True

    def tearDown(self):
        judge.cli_available = self._cli

    def test_even_votes_errors(self):
        self.assertEqual(run_judge.main(["--votes", "2"]), 2)

    def test_odd_votes_allowed(self):
        # votes=3 with no artifacts collected returns 0 (no abort on vote check).
        with mock.patch.object(run_judge, "_collect_artifacts", return_value=[]):
            self.assertEqual(run_judge.main(["--votes", "3"]), 0)

    def test_default_one_vote_allowed(self):
        with mock.patch.object(run_judge, "_collect_artifacts", return_value=[]):
            self.assertEqual(run_judge.main([]), 0)


# ---- S3-A: cache write is atomic ------------------------------------------
class TestS3AAtomicWrite(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._patch = mock.patch.object(
            cache, "CACHE_DIR", pathlib.Path(self._tmp.name)
        )
        self._patch.start()

    def tearDown(self):
        self._patch.stop()
        self._tmp.cleanup()

    def test_failed_write_leaves_no_partial_file(self):
        ab = b"data"
        dim_ids = ["J1"]
        # Make os.replace fail; the temp file must be cleaned up, target absent.
        with mock.patch("cache.os.replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                cache.put(ab, "m", dim_ids, {"dimensions": {}})
        leftovers = list(pathlib.Path(self._tmp.name).iterdir())
        self.assertEqual(
            leftovers, [], f"no temp/partial files should remain: {leftovers}"
        )

    def test_successful_write_then_read_roundtrip(self):
        ab = b"data"
        dim_ids = ["J1"]
        payload = {"dimensions": {"J1": {"score": 4, "evidence": "x"}}}
        cache.put(ab, "m", dim_ids, payload)
        self.assertEqual(cache.get(ab, "m", dim_ids), payload)


# ---- S3-B: rubric guidance fingerprint folds into cache identity ----------
class TestS3BGuidanceFingerprint(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._patch = mock.patch.object(
            cache, "CACHE_DIR", pathlib.Path(self._tmp.name)
        )
        self._patch.start()
        self.dims = rubrics.applicable_dimensions("skill", "foo")

    def tearDown(self):
        self._patch.stop()
        self._tmp.cleanup()

    def test_fingerprint_changes_with_guidance(self):
        fp1 = rubrics.guidance_fingerprint()
        # Replace just the first dimension's guidance string.
        patched = (
            dataclasses_replace(rubrics.DIMENSIONS[0], guidance="EDITED"),
        ) + rubrics.DIMENSIONS[1:]
        with mock.patch.object(rubrics, "DIMENSIONS", patched):
            fp2 = rubrics.guidance_fingerprint()
        self.assertNotEqual(fp1, fp2, "editing guidance must change the fingerprint")

    def test_cache_identity_includes_fingerprint(self):
        # A cache entry written under the current fingerprint is NOT served when
        # the fingerprint changes (simulating an edited guidance string).
        art = make_skill()
        ab = art.raw.encode("utf-8")
        dim_ids = [d.id for d in self.dims]
        real_fp = rubrics.guidance_fingerprint()
        cache.put(
            ab, f"sonnet|votes=1|rubric={real_fp}", dim_ids, verdict_for(self.dims, 5)
        )
        with mock.patch.object(
            rubrics, "guidance_fingerprint", return_value="deadbeefdeadbeef"
        ):
            with _StubClaude(json.dumps(verdict_for(self.dims, 4))) as m:
                res = judge.judge_artifact(
                    art, judge.JudgeOptions(model="sonnet", use_cache=True)
                )
        self.assertTrue(m.called, "changed fingerprint must invalidate the entry")
        self.assertFalse(res.cached)


# ---- S3-C: reprompt does not accumulate the full prompt --------------------
class TestS3CRepromptNoAccumulation(unittest.TestCase):
    def test_each_retry_adds_one_correction_only(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        base = "BASE_PROMPT_BODY"
        good = json.dumps(verdict_for(dims, 4))
        seen = []

        def fake(prompt, model, timeout):
            seen.append(prompt)
            # First two attempts: malformed; third: valid.
            if len(seen) < 3:
                return "not json"
            return good

        with mock.patch.object(judge, "_run_claude", side_effect=fake):
            judge._single_verdict(base, dims, "sonnet", 1)

        self.assertEqual(len(seen), 3)
        self.assertEqual(seen[0], base)
        # Each later attempt = base + exactly one correction line; never base +
        # correction + correction (no cumulative growth).
        for p in seen[1:]:
            self.assertTrue(p.startswith(base))
            self.assertEqual(p.count("Your previous answer was rejected:"), 1)


# ---- S3-D: J10 authoritative list uses .name, not raw dir names ------------
class TestS3DMetaGuideUsesName(unittest.TestCase):
    def _write_plugin(self, root: pathlib.Path):
        (root / ".claude-plugin").mkdir(parents=True)
        (root / ".claude-plugin" / "plugin.json").write_text("{}", encoding="utf-8")
        skills = root / "skills"
        (skills / "dir-stem-a").mkdir(parents=True)
        # Frontmatter name differs from the directory name.
        (skills / "dir-stem-a" / "SKILL.md").write_text(
            "---\nname: fancy-name-a\ndescription: x. Use when y.\n---\nbody",
            encoding="utf-8",
        )
        (skills / "dir-stem-b").mkdir(parents=True)
        (skills / "dir-stem-b" / "SKILL.md").write_text(
            "---\nname: fancy-name-b\ndescription: x. Use when y.\n---\nbody",
            encoding="utf-8",
        )

    def test_context_lists_frontmatter_names(self):
        with tempfile.TemporaryDirectory() as td:
            # plugin must live at <repo>/plugins/<name> for _model.rel paths.
            root = pathlib.Path(td) / "plugins" / "p"
            self._write_plugin(root)
            ctx = run_judge._meta_guide_context(root)
        self.assertIn("fancy-name-a", ctx)
        self.assertIn("fancy-name-b", ctx)
        self.assertNotIn("dir-stem-a", ctx)
        self.assertNotIn("dir-stem-b", ctx)


# ---- S4-A: is_error branch tolerates non-str result -----------------------
class TestS4AErrorResultNonStr(unittest.TestCase):
    def test_dict_result_in_error_envelope(self):
        envelope = json.dumps({"is_error": True, "result": {"code": 500}})
        with mock.patch.object(judge, "cli_available", return_value=True):
            with mock.patch("judge.subprocess.run") as run:
                run.return_value = mock.Mock(returncode=0, stdout=envelope, stderr="")
                with self.assertRaises(judge.JudgeError) as ctx:
                    judge._run_claude("p", "sonnet", 1)
        # No TypeError from slicing a dict; the dict is str()'d first.
        self.assertIn("claude reported error", str(ctx.exception))

    def test_none_result_in_error_envelope(self):
        envelope = json.dumps({"is_error": True, "result": None})
        with mock.patch.object(judge, "cli_available", return_value=True):
            with mock.patch("judge.subprocess.run") as run:
                run.return_value = mock.Mock(returncode=0, stdout=envelope, stderr="")
                with self.assertRaises(judge.JudgeError):
                    judge._run_claude("p", "sonnet", 1)


# ---- S4-B: J9 name_filter matches on a token boundary ---------------------
class TestS4BNameFilterBoundary(unittest.TestCase):
    def setUp(self):
        self.j9 = rubrics.DIMENSIONS_BY_ID["J9"]

    def test_qa_tokens_match(self):
        for name in ("qa", "qa-manual-tester", "sdlc-qa", "manual_qa", "foo-qa-bar"):
            self.assertTrue(self.j9.applies("agent", name), name)

    def test_non_qa_substrings_do_not_match(self):
        for name in ("equality", "qaz", "aqa", "squad", "code-review"):
            self.assertFalse(self.j9.applies("agent", name), name)

    def test_applicable_dimensions_excludes_j9_for_nonqa(self):
        ids = {d.id for d in rubrics.applicable_dimensions("agent", "equality")}
        self.assertNotIn("J9", ids)
        ids = {d.id for d in rubrics.applicable_dimensions("agent", "sdlc-qa")}
        self.assertIn("J9", ids)


# ---- C1: critical dim below floor but above block_floor is advisory --------
class TestC1CriticalAdvisory(unittest.TestCase):
    """A critical dim at score 3 (below floor 4, above block_floor 2) must be
    reported as an advisory finding, not silently dropped from both lists."""

    def setUp(self):
        self._orig = judge._run_claude

    def tearDown(self):
        judge._run_claude = self._orig

    def test_critical_score3_is_advisory(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        self.assertTrue(any(d.critical for d in dims), "fixture needs a critical dim")
        judge._run_claude = lambda prompt, model, timeout: json.dumps(
            verdict_for(dims, 3)
        )
        res = judge.judge_artifact(make_skill(), judge.JudgeOptions(use_cache=False))
        self.assertEqual(res.blocking_failures, [], "score 3 must not hard-block")
        adv_ids = {d.id for d in res.advisory_failures}
        crit_in_adv = {d.id for d in res.advisory_failures if d.critical}
        # Every failed dimension (all are below floor at score 3) is advisory,
        # and at least one of them is a CRITICAL dim — the previously-dropped case.
        self.assertEqual(adv_ids, {d.id for d in dims})
        self.assertTrue(
            crit_in_adv, "a critical dim at score 3 must appear in advisory_failures"
        )


# ---- C2: extra_context is part of the cache identity ----------------------
class TestC2ExtraContextCacheIdentity(unittest.TestCase):
    def test_key_differs_with_extra_context(self):
        ab = b"artifact-bytes"
        dim_ids = ["J1", "J2"]
        k_empty = cache._key(ab, "sonnet|votes=1", dim_ids, "")
        k_ctx = cache._key(ab, "sonnet|votes=1", dim_ids, "skills: a, b, c")
        self.assertNotEqual(k_empty, k_ctx, "extra_context must change the cache key")

    def test_changed_extra_context_misses_cache(self):
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(cache, "CACHE_DIR", pathlib.Path(td)):
                dims = rubrics.applicable_dimensions("skill", "foo")
                art = make_skill()
                ab = art.raw.encode("utf-8")
                cm = f"sonnet|votes=1|rubric={rubrics.guidance_fingerprint()}"
                dim_ids = [d.id for d in dims]
                # Seed a verdict under extra_context "v1".
                cache.put(ab, cm, dim_ids, verdict_for(dims, 5), "v1")
                # Same artifact/model/votes, DIFFERENT context -> must miss (re-judge).
                with _StubClaude(json.dumps(verdict_for(dims, 4))) as m:
                    res = judge.judge_artifact(
                        art,
                        judge.JudgeOptions(
                            model="sonnet", extra_context="v2", use_cache=True
                        ),
                    )
                self.assertTrue(
                    m.called, "changed extra_context must invalidate the entry"
                )
                self.assertFalse(res.cached)
                # And the original context still hits without a call.
                with _StubClaude("SHOULD NOT BE CALLED") as m2:
                    res2 = judge.judge_artifact(
                        art,
                        judge.JudgeOptions(
                            model="sonnet", extra_context="v1", use_cache=True
                        ),
                    )
                self.assertFalse(
                    m2.called, "matching extra_context must still serve the cache"
                )
                self.assertTrue(res2.cached)


# ---- C3: explicit file matching no artifact warns (not silently dropped) ---
class TestC3ExplicitFileNoMatchWarns(unittest.TestCase):
    def _write_plugin(self, root: pathlib.Path):
        (root / ".claude-plugin").mkdir(parents=True)
        (root / ".claude-plugin" / "plugin.json").write_text("{}", encoding="utf-8")
        (root / "skills" / "real-skill").mkdir(parents=True)
        (root / "skills" / "real-skill" / "SKILL.md").write_text(
            "---\nname: real-skill\ndescription: x. Use when y.\n---\nbody",
            encoding="utf-8",
        )

    def test_bogus_file_inside_plugin_warns_and_returns_empty(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td) / "plugins" / "p"
            self._write_plugin(root)
            bogus = (
                root / "skills" / "real-skill" / "NOTES.md"
            )  # not a judgeable artifact
            bogus.write_text("loose notes", encoding="utf-8")
            with mock.patch("run_judge.sys.stderr", new_callable=io.StringIO) as err:
                arts = run_judge._collect_artifacts([str(bogus)])
            self.assertEqual(arts, [], "non-artifact file must not be evaluated")
            stderr = err.getvalue()
            self.assertIn("warning", stderr)
            self.assertIn(str(bogus), stderr)

    def test_real_artifact_file_is_collected(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td) / "plugins" / "p"
            self._write_plugin(root)
            real = root / "skills" / "real-skill" / "SKILL.md"
            arts = run_judge._collect_artifacts([str(real)])
            self.assertEqual([a.path for a in arts], [real.resolve()])


# ---- C-refactor: JudgeOptions is the sole knob bundle ----------------------
class TestJudgeOptionsBundle(unittest.TestCase):
    def setUp(self):
        self._orig = judge._run_claude

    def tearDown(self):
        judge._run_claude = self._orig

    def test_options_object_accepted(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        judge._run_claude = lambda prompt, model, timeout: json.dumps(
            verdict_for(dims, 5)
        )
        opts = judge.JudgeOptions(use_cache=False, votes=1)
        res = judge.judge_artifact(make_skill(), opts)
        self.assertTrue(res.ok)

    def test_options_use_cache_false_skips_cache(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        judge._run_claude = lambda prompt, model, timeout: json.dumps(
            verdict_for(dims, 5)
        )
        # use_cache=False on the options bundle forces a fresh (uncached) verdict.
        opts = judge.JudgeOptions(use_cache=False)
        res = judge.judge_artifact(make_skill(), opts)
        self.assertFalse(res.cached)


def dataclasses_replace(obj, **kw):
    import dataclasses

    return dataclasses.replace(obj, **kw)


# ===========================================================================
# PR-review fix regression tests
# ===========================================================================


# ---- F1: extract_verdict — decoy-before-real is ambiguous, not first-wins ---
class TestF1ExtractVerdictAmbiguity(unittest.TestCase):
    def test_decoy_dimensions_object_before_real_raises(self):
        # Two top-level objects, BOTH carrying "dimensions": a decoy placed first
        # must NOT be silently selected — the whole answer is ambiguous.
        text = (
            '{"dimensions": {"J1": {"score": 5, "evidence": "DECOY"}}} '
            "and the real one: "
            '{"dimensions": {"J1": {"score": 2, "evidence": "REAL"}}}'
        )
        with self.assertRaises(judge.JudgeError) as ctx:
            judge.extract_verdict(text)
        self.assertIn("ambiguous", str(ctx.exception).lower())

    def test_single_valid_object_still_returns(self):
        out = judge.extract_verdict(
            '{"dimensions": {"J1": {"score": 4, "evidence": "x"}}}'
        )
        self.assertEqual(out["dimensions"]["J1"]["score"], 4)

    def test_single_object_with_one_non_dimension_decoy_still_returns(self):
        # Only ONE object has "dimensions"; the other lacks it -> unambiguous.
        text = (
            '{"note": "ignore"} {"dimensions": {"J1": {"score": 3, "evidence": "y"}}}'
        )
        self.assertEqual(judge.extract_verdict(text)["dimensions"]["J1"]["score"], 3)

    def test_zero_dimension_objects_raises(self):
        with self.assertRaises(judge.JudgeError):
            judge.extract_verdict('{"note": "no verdict here"}')


# ---- F2: JudgeOptions.__post_init__ validation ----------------------------
class TestF2JudgeOptionsValidation(unittest.TestCase):
    def test_even_votes_rejected(self):
        with self.assertRaises(ValueError):
            judge.JudgeOptions(votes=2)

    def test_zero_votes_rejected(self):
        with self.assertRaises(ValueError):
            judge.JudgeOptions(votes=0)

    def test_negative_votes_rejected(self):
        with self.assertRaises(ValueError):
            judge.JudgeOptions(votes=-3)

    def test_zero_timeout_rejected(self):
        with self.assertRaises(ValueError):
            judge.JudgeOptions(timeout=0)

    def test_negative_timeout_rejected(self):
        with self.assertRaises(ValueError):
            judge.JudgeOptions(timeout=-1)

    def test_one_and_odd_votes_allowed(self):
        for v in (1, 3, 5, 7):
            self.assertEqual(judge.JudgeOptions(votes=v).votes, v)

    def test_positive_timeout_allowed(self):
        self.assertEqual(judge.JudgeOptions(timeout=30).timeout, 30)


# ---- F3: --gate over an empty artifact set is a false green ----------------
class TestF3GateEmptySet(unittest.TestCase):
    def setUp(self):
        self._cli = judge.cli_available
        judge.cli_available = lambda: True

    def tearDown(self):
        judge.cli_available = self._cli

    def test_gate_with_roots_but_zero_artifacts_fails(self):
        # No explicit paths; plugin roots DO exist but discovery found nothing.
        with mock.patch.object(run_judge, "_collect_artifacts", return_value=[]):
            with mock.patch.object(
                run_judge._model,
                "find_plugin_roots",
                return_value=[pathlib.Path("/x/plugins/p")],
            ):
                self.assertEqual(run_judge.main(["--gate"]), 1)

    def test_gate_with_explicit_path_matching_nothing_fails(self):
        with mock.patch.object(run_judge, "_collect_artifacts", return_value=[]):
            self.assertEqual(run_judge.main(["--gate", "no/such/artifact.md"]), 1)

    def test_no_gate_empty_set_is_zero(self):
        with mock.patch.object(run_judge, "_collect_artifacts", return_value=[]):
            self.assertEqual(run_judge.main([]), 0)

    def test_gate_with_no_roots_is_zero(self):
        # --gate, no explicit paths, and no plugin roots at all: legitimately
        # nothing to judge -> not a false green, returns 0.
        with mock.patch.object(run_judge, "_collect_artifacts", return_value=[]):
            with mock.patch.object(
                run_judge._model, "find_plugin_roots", return_value=[]
            ):
                self.assertEqual(run_judge.main(["--gate"]), 0)

    def test_no_creds_skip_path_unaffected_by_gate(self):
        # The skip-when-unavailable path returns BEFORE artifact collection, so
        # --gate must not turn a credential skip into a hard failure.
        judge.cli_available = lambda: False
        self.assertEqual(run_judge.main(["--gate"]), 0)
        self.assertEqual(run_judge.main(["--gate", "--require"]), 2)


# ---- F5: calibration corpus + --selftest harness --------------------------
import calibration  # noqa: E402


class TestF5CalibrationData(unittest.TestCase):
    def test_every_critical_dimension_has_P_and_N(self):
        for dim_id in calibration.CRITICAL_DIMENSION_IDS:
            self.assertIsNotNone(
                calibration.positive_for(dim_id), f"{dim_id} missing a P case"
            )
            self.assertIsNotNone(
                calibration.negative_for(dim_id), f"{dim_id} missing an N case"
            )

    def test_critical_ids_match_the_rubric_critical_set(self):
        rubric_critical = {d.id for d in rubrics.DIMENSIONS if d.critical}
        self.assertEqual(
            set(calibration.CRITICAL_DIMENSION_IDS),
            rubric_critical,
            "calibration must cover exactly the rubric's critical dimensions",
        )

    def test_each_case_targets_an_applicable_dimension(self):
        # A case is only meaningful if its target dim is actually scored for the
        # artifact's kind/name — otherwise the self-test could never read a score.
        for c in calibration.CASES:
            art = c.artifact()
            ids = {d.id for d in rubrics.applicable_dimensions(art.kind, art.name)}
            self.assertIn(c.dimension_id, ids, f"{c.dimension_id}/{c.polarity}")


def _calibration_scorer(p_score: int, n_score: int):
    """Build a mocked _run_claude that scores the target dim per the artifact's
    polarity, detected from a marker we embedded in each N artifact's text.

    Every applicable dimension still gets a passing score so unrelated dims never
    confuse the result; only the polarity-detected score is what the self-test
    reads for the target dimension.
    """
    import re

    def fake(prompt, model, timeout):
        ids = re.findall(r"- (J\d+) \(", prompt)
        # N artifacts in calibration.py all contain a parenthetical caveat with
        # "NOT" / "does NOT" / "loops forever" / "stale" wording; key off a stable
        # marker present only in the negative examples.
        is_negative = any(
            marker in prompt
            for marker in (
                "directly contradicting",  # J2 N
                "loops forever",  # J3 N
                "assumes the user-account",  # J7 N
                "does NOT ship",  # J10 N
                "name: helper",  # J1 N
            )
        )
        score = n_score if is_negative else p_score
        dims = {i: {"score": score, "evidence": "syn"} for i in ids}
        return json.dumps({"dimensions": dims})

    return fake


class TestF5SelftestHarness(unittest.TestCase):
    def test_selftest_reports_pass_for_well_scored_corpus(self):
        # P artifacts score 5 (>= floor 4); N artifacts score 1 (<= block_floor 2).
        with mock.patch.object(judge, "cli_available", return_value=True):
            with mock.patch.object(
                judge, "_run_claude", side_effect=_calibration_scorer(5, 1)
            ):
                rc = run_judge.main(["--selftest"])
        self.assertEqual(rc, 0, "well-calibrated corpus must PASS (exit 0)")

    def test_selftest_reports_fail_for_miscalibration(self):
        # Force the N examples to score HIGH (5): a miscalibration the self-test
        # must catch (N above block_floor) -> exit 1.
        with mock.patch.object(judge, "cli_available", return_value=True):
            with mock.patch.object(
                judge, "_run_claude", side_effect=_calibration_scorer(5, 5)
            ):
                rc = run_judge.main(["--selftest"])
        self.assertEqual(rc, 1, "miscalibrated corpus must FAIL (exit 1)")

    def test_selftest_fails_when_positive_scores_below_floor(self):
        # P scores low (1): even with N correct, P below floor is a miscalibration.
        with mock.patch.object(judge, "cli_available", return_value=True):
            with mock.patch.object(
                judge, "_run_claude", side_effect=_calibration_scorer(1, 1)
            ):
                rc = run_judge.main(["--selftest"])
        self.assertEqual(rc, 1)

    def test_selftest_skips_without_cli(self):
        # No claude CLI: skip-with-message, exit 0 (never reached on CI no-cred
        # path because CI does not pass --selftest).
        with mock.patch.object(judge, "cli_available", return_value=False):
            self.assertEqual(run_judge.main(["--selftest"]), 0)

    def test_selftest_require_fails_without_cli(self):
        with mock.patch.object(judge, "cli_available", return_value=False):
            self.assertEqual(run_judge.main(["--selftest", "--require"]), 2)


# ---- F6a: rubric registry pinned to the J1..J11 contract -------------------
class TestF6ARubricContract(unittest.TestCase):
    def test_id_to_critical_map_is_pinned(self):
        actual = {d.id: d.critical for d in rubrics.DIMENSIONS}
        expected = {
            "J1": True,
            "J2": True,
            "J3": True,
            "J4": False,
            "J5": False,
            "J6": False,
            "J7": True,
            "J8": False,
            "J9": False,
            "J10": True,
            "J11": False,
        }
        self.assertEqual(actual, expected)

    def test_applicable_dimensions_for_command(self):
        ids = {d.id for d in rubrics.applicable_dimensions("command", "deploy")}
        # command applies_to: J2, J3, J4, J5, J7(all), J9(qa only -> excluded
        # for a non-qa name), J11(all).
        self.assertEqual(ids, {"J2", "J3", "J4", "J5", "J7", "J11"})

    def test_applicable_dimensions_for_agent(self):
        ids = {d.id for d in rubrics.applicable_dimensions("agent", "deploy")}
        # agent: J1, J2, J3, J5, J7(all), J8, J9(qa only -> excluded), J11(all).
        self.assertEqual(ids, {"J1", "J2", "J3", "J5", "J7", "J8", "J11"})

    def test_applicable_dimensions_for_skill(self):
        ids = {d.id for d in rubrics.applicable_dimensions("skill", "foo")}
        # skill: J1, J2, J3, J6, J7(all), J8, J11(all).
        self.assertEqual(ids, {"J1", "J2", "J3", "J6", "J7", "J8", "J11"})

    def test_applicable_dimensions_for_meta_guide(self):
        ids = {d.id for d in rubrics.applicable_dimensions("meta-guide", "guide")}
        # meta-guide: J7(all), J10, J11(all).
        self.assertEqual(ids, {"J7", "J10", "J11"})

    def test_qa_name_filter_boundary(self):
        # J9 only joins when the name carries a 'qa' token on a boundary.
        qa_agent = {d.id for d in rubrics.applicable_dimensions("agent", "sdlc-qa")}
        self.assertIn("J9", qa_agent)
        non_qa = {d.id for d in rubrics.applicable_dimensions("agent", "equality")}
        self.assertNotIn("J9", non_qa)
        qa_cmd = {d.id for d in rubrics.applicable_dimensions("command", "qa-run")}
        self.assertIn("J9", qa_cmd)


# ---- F6b: _run_claude happy path argv/cwd contract ------------------------
class TestF6BRunClaudeHappyPath(unittest.TestCase):
    def test_argv_and_cwd_and_result(self):
        envelope = json.dumps({"is_error": False, "result": "VERDICT-TEXT"})
        with mock.patch.object(judge, "cli_available", return_value=True):
            with mock.patch("judge.subprocess.run") as run:
                run.return_value = mock.Mock(returncode=0, stdout=envelope, stderr="")
                out = judge._run_claude("MY-PROMPT", "sonnet", 42)
        self.assertEqual(out, "VERDICT-TEXT")
        # Inspect the recorded call.
        args, kwargs = run.call_args
        argv = args[0]
        self.assertEqual(argv[0], "claude")
        self.assertIn("-p", argv)
        # Prompt passed as an ARGUMENT (right after -p), not on stdin.
        self.assertEqual(argv[argv.index("-p") + 1], "MY-PROMPT")
        self.assertIn("--model", argv)
        self.assertEqual(argv[argv.index("--model") + 1], "sonnet")
        self.assertIn("--output-format", argv)
        self.assertEqual(argv[argv.index("--output-format") + 1], "json")
        # cwd is a FRESH per-call temp dir under the system temp root (neutral,
        # no project/ambient CLAUDE.md leakage). Not the shared temp dir itself.
        cwd = kwargs.get("cwd")
        self.assertIsNotNone(cwd)
        self.assertNotEqual(cwd, tempfile.gettempdir())
        self.assertTrue(
            pathlib.Path(cwd)
            .resolve()
            .is_relative_to(pathlib.Path(tempfile.gettempdir()).resolve()),
            f"cwd {cwd!r} must be under the system temp root",
        )
        self.assertIn("judge-cwd-", pathlib.Path(cwd).name)
        # No stdin input is fed (prompt is an argument, not piped).
        self.assertIsNone(kwargs.get("input"))


# ---- F6c: judge_artifact end-to-end (mocked) per kind --------------------
class TestF6CJudgeArtifactDims(unittest.TestCase):
    def _scored_payload_for(self, kind, name, score=5):
        dims = rubrics.applicable_dimensions(kind, name)
        return json.dumps(verdict_for(dims, score))

    def test_agent_fixture_dims_match_applicable(self):
        art = _model.Artifact(
            path=pathlib.Path("/x/plugins/p/agents/deployer.md"),
            plugin_root=pathlib.Path("/x/plugins/p"),
            kind="agent",
            raw="# Agent\nbody",
            has_frontmatter=True,
            frontmatter={"name": "deployer", "description": "x. Use when y."},
            frontmatter_error=None,
            body="# Agent\nbody",
            h1=None,
            h2_sections=[],
        )
        expected = {d.id for d in rubrics.applicable_dimensions("agent", "deployer")}
        with _StubClaude(self._scored_payload_for("agent", "deployer")):
            res = judge.judge_artifact(art, judge.JudgeOptions(use_cache=False))
        self.assertEqual({d.id for d in res.dimensions}, expected)

    def test_qa_command_fixture_includes_j9(self):
        art = make_command(name="sdlc-qa")
        expected = {d.id for d in rubrics.applicable_dimensions("command", "sdlc-qa")}
        self.assertIn("J9", expected)  # qa name pulls J9 in
        with _StubClaude(self._scored_payload_for("command", "sdlc-qa")):
            res = judge.judge_artifact(art, judge.JudgeOptions(use_cache=False))
        self.assertEqual({d.id for d in res.dimensions}, expected)

    def test_meta_guide_fixture_dims_match_applicable(self):
        art = _model.Artifact(
            path=pathlib.Path("/x/plugins/p/skills/guide.md"),
            plugin_root=pathlib.Path("/x/plugins/p"),
            kind="meta-guide",
            raw="# Guide\nbody",
            has_frontmatter=False,
            frontmatter={},
            frontmatter_error=None,
            body="# Guide\nbody",
            h1="Guide",
            h2_sections=[],
        )
        expected = {d.id for d in rubrics.applicable_dimensions("meta-guide", "guide")}
        with _StubClaude(self._scored_payload_for("meta-guide", "guide")):
            res = judge.judge_artifact(art, judge.JudgeOptions(use_cache=False))
        self.assertEqual({d.id for d in res.dimensions}, expected)


# ---- F6d: extract_verdict on a truncated payload raises -------------------
class TestF6DTruncatedPayload(unittest.TestCase):
    def test_truncated_json_raises(self):
        text = '{"dimensions": {"J1": {"score": 4, "evidence": "abc'
        with self.assertRaises(judge.JudgeError):
            judge.extract_verdict(text)

    def test_truncated_after_dimensions_key_raises(self):
        text = '{"dimensions": {"J1": {"score": 4,'
        with self.assertRaises(judge.JudgeError):
            judge.extract_verdict(text)


# ---- F6e: aggregate-cache revalidation on shape drift ---------------------
class TestF6EAggregateCacheRevalidation(unittest.TestCase):
    def setUp(self):
        self.dims = rubrics.applicable_dimensions("skill", "foo")
        self._tmp = tempfile.TemporaryDirectory()
        self._cache_patch = mock.patch.object(
            cache, "CACHE_DIR", pathlib.Path(self._tmp.name)
        )
        self._cache_patch.start()

    def tearDown(self):
        self._cache_patch.stop()
        self._tmp.cleanup()

    def _seed(self, verdict):
        art = make_skill()
        ab = art.raw.encode("utf-8")
        cm = f"sonnet|votes=3|rubric={rubrics.guidance_fingerprint()}"
        dim_ids = [d.id for d in self.dims]
        cache.put(ab, cm, dim_ids, verdict)
        return art

    def test_aggregate_cache_missing_dimension_rejudges(self):
        # A cached votes=3 aggregate that DROPPED a dimension must be a MISS.
        agg = {
            "dimensions": {d.id: {"score": 4, "evidence": "x"} for d in self.dims},
            "votes": 3,
        }
        del agg["dimensions"][self.dims[0].id]
        art = self._seed(agg)
        with _StubClaude([json.dumps(verdict_for(self.dims, 4))] * 3) as m:
            res = judge.judge_artifact(
                art, judge.JudgeOptions(model="sonnet", use_cache=True, votes=3)
            )
        self.assertTrue(m.called, "missing-dim aggregate must trigger a re-judge")
        self.assertFalse(res.cached)

    def test_aggregate_cache_extra_dimension_rejudges(self):
        # A cached aggregate with an EXTRA hallucinated id 'J999' must be a MISS.
        agg = {
            "dimensions": {d.id: {"score": 4, "evidence": "x"} for d in self.dims},
            "votes": 3,
        }
        agg["dimensions"]["J999"] = {"score": 5, "evidence": "ghost"}
        art = self._seed(agg)
        with _StubClaude([json.dumps(verdict_for(self.dims, 4))] * 3) as m:
            res = judge.judge_artifact(
                art, judge.JudgeOptions(model="sonnet", use_cache=True, votes=3)
            )
        self.assertTrue(m.called, "extra-id aggregate must trigger a re-judge")
        self.assertFalse(res.cached)


# ===========================================================================
# Round-2 review fix regression tests
# ===========================================================================


# ---- R2-1: votes>1 cached aggregate must carry non-empty evidence ----------
class TestR2AggregateCacheEvidence(unittest.TestCase):
    def setUp(self):
        self.dims = rubrics.applicable_dimensions("skill", "foo")
        self._tmp = tempfile.TemporaryDirectory()
        self._cache_patch = mock.patch.object(
            cache, "CACHE_DIR", pathlib.Path(self._tmp.name)
        )
        self._cache_patch.start()

    def tearDown(self):
        self._cache_patch.stop()
        self._tmp.cleanup()

    def _seed(self, verdict):
        art = make_skill()
        ab = art.raw.encode("utf-8")
        cm = f"sonnet|votes=3|rubric={rubrics.guidance_fingerprint()}"
        dim_ids = [d.id for d in self.dims]
        cache.put(ab, cm, dim_ids, verdict)
        return art

    def test_aggregate_cache_empty_evidence_rejudges(self):
        # votes>1 aggregate, score is valid but evidence is "" -> MISS (re-judge).
        agg = {
            "dimensions": {d.id: {"score": 4, "evidence": ""} for d in self.dims},
            "votes": 3,
        }
        art = self._seed(agg)
        with _StubClaude([json.dumps(verdict_for(self.dims, 4))] * 3) as m:
            res = judge.judge_artifact(
                art, judge.JudgeOptions(model="sonnet", use_cache=True, votes=3)
            )
        self.assertTrue(m.called, "empty-evidence aggregate must trigger a re-judge")
        self.assertFalse(res.cached)

    def test_aggregate_cache_missing_evidence_rejudges(self):
        # votes>1 aggregate where the evidence key is entirely absent -> MISS.
        agg = {"dimensions": {d.id: {"score": 4} for d in self.dims}, "votes": 3}
        art = self._seed(agg)
        with _StubClaude([json.dumps(verdict_for(self.dims, 4))] * 3) as m:
            res = judge.judge_artifact(
                art, judge.JudgeOptions(model="sonnet", use_cache=True, votes=3)
            )
        self.assertTrue(m.called, "missing-evidence aggregate must trigger a re-judge")
        self.assertFalse(res.cached)

    def test_aggregate_cache_with_evidence_is_served(self):
        # A well-formed aggregate (score + non-empty evidence) is served as a hit.
        agg = {
            "dimensions": {d.id: {"score": 5, "evidence": "good"} for d in self.dims},
            "votes": 3,
        }
        art = self._seed(agg)
        with _StubClaude("SHOULD NOT BE CALLED") as m:
            res = judge.judge_artifact(
                art, judge.JudgeOptions(model="sonnet", use_cache=True, votes=3)
            )
        self.assertFalse(m.called, "valid aggregate hit must not call claude")
        self.assertTrue(res.cached)


# ---- R2-2: JUDGE_TIMEOUT parsing never crashes import ----------------------
class TestR2EnvTimeout(unittest.TestCase):
    def test_unset_returns_default(self):
        with mock.patch.dict(judge.os.environ, {}, clear=True):
            self.assertEqual(judge._env_timeout(180), 180)

    def test_valid_integer_used(self):
        with mock.patch.dict(judge.os.environ, {"JUDGE_TIMEOUT": "42"}, clear=True):
            self.assertEqual(judge._env_timeout(180), 42)

    def test_non_integer_falls_back_to_default(self):
        for bad in ("fast", "", "12x", "1.5"):
            with mock.patch.dict(judge.os.environ, {"JUDGE_TIMEOUT": bad}, clear=True):
                with mock.patch.object(
                    judge.sys, "stderr", new_callable=io.StringIO
                ) as err:
                    self.assertEqual(judge._env_timeout(180), 180)
                self.assertIn("JUDGE_TIMEOUT", err.getvalue())

    def test_non_positive_falls_back_to_default(self):
        for bad in ("0", "-5"):
            with mock.patch.dict(judge.os.environ, {"JUDGE_TIMEOUT": bad}, clear=True):
                with mock.patch.object(judge.sys, "stderr", new_callable=io.StringIO):
                    self.assertEqual(judge._env_timeout(180), 180)

    def test_import_survives_bad_env(self):
        # Re-importing judge with a bad JUDGE_TIMEOUT must not raise ValueError.
        # Done in a clean subprocess so the live `judge` module the rest of the
        # suite shares is never reloaded out from under it.
        import subprocess

        env = dict(judge.os.environ)
        env["JUDGE_TIMEOUT"] = "fast"
        judge_dir = str(pathlib.Path(judge.__file__).resolve().parent)
        lint_dir = str(pathlib.Path(judge.__file__).resolve().parent.parent / "lint")
        code = (
            "import sys; sys.path[:0] = [%r, %r]; import judge; "
            "assert judge.DEFAULT_TIMEOUT == 180, judge.DEFAULT_TIMEOUT; "
            "print('OK')" % (judge_dir, lint_dir)
        )
        proc = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, env=env
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("OK", proc.stdout)
        self.assertIn("JUDGE_TIMEOUT", proc.stderr)  # the warning was emitted


# ---- R2-3: Dimension.__post_init__ guards the score thresholds -------------
class TestR2DimensionInvariants(unittest.TestCase):
    def _dim(self, **kw):
        base = dict(
            id="JX",
            name="x",
            applies_to=("skill",),
            critical=True,
            floor=4,
            guidance="g",
        )
        base.update(kw)
        return rubrics.Dimension(**base)

    def test_floor_above_5_rejected(self):
        with self.assertRaises(ValueError):
            self._dim(floor=6)

    def test_block_floor_ge_floor_rejected(self):
        with self.assertRaises(ValueError):
            self._dim(floor=4, block_floor=4)
        with self.assertRaises(ValueError):
            self._dim(floor=4, block_floor=5)

    def test_block_floor_below_1_rejected(self):
        with self.assertRaises(ValueError):
            self._dim(floor=4, block_floor=0)

    def test_non_int_floor_rejected(self):
        with self.assertRaises(ValueError):
            self._dim(floor="4")

    def test_valid_dimension_constructs(self):
        d = self._dim(floor=4, block_floor=2)
        self.assertEqual((d.floor, d.block_floor), (4, 2))

    def test_all_shipped_dimensions_construct(self):
        # The shipped registry already imported fine; re-assert each invariant.
        for d in rubrics.DIMENSIONS:
            self.assertTrue(1 <= d.block_floor < d.floor <= 5, d.id)


# ---- R2-4: OSError from cache.put becomes a recorded error, not a crash ----
class TestR2OSErrorRecorded(unittest.TestCase):
    def setUp(self):
        self._cli = judge.cli_available
        self._judge = judge.judge_artifact
        self._collect = run_judge._collect_artifacts
        judge.cli_available = lambda: True

    def tearDown(self):
        judge.cli_available = self._cli
        judge.judge_artifact = self._judge
        run_judge._collect_artifacts = self._collect

    def test_oserror_under_gate_fails_run(self):
        art = make_skill()
        run_judge._collect_artifacts = lambda paths: [art]

        def boom(a, options=None):
            raise OSError("disk full")  # mimics cache.put failing in _generate_verdict

        judge.judge_artifact = boom
        rc = run_judge.main(["--gate", "x"])
        self.assertEqual(rc, 1, "an OSError under --gate must fail, not crash")

    def test_oserror_without_gate_run_continues(self):
        good = make_skill(name="good")
        bad = make_skill(name="bad")
        run_judge._collect_artifacts = lambda paths: [bad, good]

        def selective(a, options=None):
            if a.name == "bad":
                raise OSError("disk full")
            return judge.JudgeResult(a.rel, a.kind, a.name, "sonnet", False, [], {})

        judge.judge_artifact = selective
        # No --gate: the run records the error but still returns 0 (continues).
        with mock.patch.object(
            run_judge.sys, "stderr", new_callable=io.StringIO
        ) as err:
            rc = run_judge.main(["x"])
        self.assertEqual(rc, 0, "without --gate one OSError must not fail the run")
        self.assertIn("ERROR judging", err.getvalue())

    def test_oserror_is_in_judge_exc_tuple(self):
        self.assertIn(OSError, run_judge._JUDGE_EXC)


# ---- R2-5: J4 redefined to internal exit-condition consistency ------------
class TestR2J4Consistency(unittest.TestCase):
    def test_j4_id_and_kind_unchanged(self):
        j4 = rubrics.DIMENSIONS_BY_ID["J4"]
        self.assertEqual(j4.id, "J4")
        self.assertEqual(j4.applies_to, ("command",))
        self.assertFalse(j4.critical, "J4 stays advisory/non-critical")

    def test_j4_name_reflects_consistency(self):
        j4 = rubrics.DIMENSIONS_BY_ID["J4"]
        self.assertEqual(j4.name, "exit-condition-consistency")

    def test_j4_guidance_is_internal_not_stage_table(self):
        g = rubrics.DIMENSIONS_BY_ID["J4"].guidance.lower()
        self.assertIn("consisten", g)
        self.assertIn("internal", g)
        # The old wording REQUIRED matching an external FR-1 stage-table row.
        # The redefinition must not demand a faithful paraphrase of that row.
        self.assertNotIn("faithful paraphrase", g)
        self.assertNotIn("stage-table row", g)
        # If "stage table" is mentioned at all it must be to DISCLAIM it.
        if "stage table" in g:
            self.assertIn("do not require an external stage table", g)


# ---- R2-7: explicit file outside any plugin tree warns + returns empty -----
class TestR2FileOutsidePluginTree(unittest.TestCase):
    def test_file_with_no_plugin_ancestor_warns(self):
        with tempfile.TemporaryDirectory() as td:
            # A real .md file with NO .claude-plugin ancestor anywhere above it.
            loose = pathlib.Path(td) / "loose-note.md"
            loose.write_text(
                "---\nname: x\ndescription: y. Use when z.\n---\nbody", encoding="utf-8"
            )
            with mock.patch("run_judge.sys.stderr", new_callable=io.StringIO) as err:
                arts = run_judge._collect_artifacts([str(loose)])
            self.assertEqual(arts, [], "file outside a plugin tree must not be judged")
            stderr = err.getvalue()
            self.assertIn("not inside a known plugin tree", stderr)
            self.assertIn(str(loose.resolve()), stderr)


# ===========================================================================
# Robustness review fix regression tests (run_judge collection)
# ===========================================================================


def _write_plugin_with_skill(root: pathlib.Path):
    (root / ".claude-plugin").mkdir(parents=True)
    (root / ".claude-plugin" / "plugin.json").write_text("{}", encoding="utf-8")
    (root / "skills" / "real-skill").mkdir(parents=True)
    (root / "skills" / "real-skill" / "SKILL.md").write_text(
        "---\nname: real-skill\ndescription: x. Use when y.\n---\nbody",
        encoding="utf-8",
    )


# ---- RB-1: a non-existent explicit path warns (not silently dropped) --------
class TestRBNonExistentPathWarns(unittest.TestCase):
    def test_missing_path_warns_to_stderr_and_returns_empty(self):
        with tempfile.TemporaryDirectory() as td:
            missing = pathlib.Path(td) / "no" / "such" / "thing.md"
            with mock.patch("run_judge.sys.stderr", new_callable=io.StringIO) as err:
                arts = run_judge._collect_artifacts([str(missing)])
            self.assertEqual(arts, [], "a non-existent path must not be evaluated")
            stderr = err.getvalue()
            self.assertIn("warning", stderr)
            self.assertIn("does not exist", stderr)
            self.assertIn(str(missing.resolve()), stderr)


# ---- RB-2: overlapping inputs (dir + a file within it) dedupe ---------------
class TestRBOverlappingInputsDedupe(unittest.TestCase):
    def test_dir_plus_inner_file_yields_each_artifact_once(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td) / "plugins" / "p"
            _write_plugin_with_skill(root)
            inner = root / "skills" / "real-skill" / "SKILL.md"
            # The plugin dir AND a file inside it both name the same artifact.
            arts = run_judge._collect_artifacts([str(root), str(inner)])
            paths = [a.path for a in arts]
            self.assertEqual(
                paths,
                [inner.resolve()],
                "overlapping inputs must yield each artifact exactly once",
            )

    def test_duplicate_dir_inputs_dedupe(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td) / "plugins" / "p"
            _write_plugin_with_skill(root)
            inner = root / "skills" / "real-skill" / "SKILL.md"
            # The same plugin dir passed twice must not double-count its artifacts.
            arts = run_judge._collect_artifacts([str(root), str(root)])
            self.assertEqual([a.path for a in arts], [inner.resolve()])


if __name__ == "__main__":
    unittest.main()
