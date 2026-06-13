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
        frontmatter={"name": name, "description": "Create things. Use when adding things."},
        frontmatter_error=None,
        body=raw,
        h1=None,
        h2_sections=["Profile keys consumed"],
    )


def verdict_for(dims, score):
    return {"dimensions": {d.id: {"score": score, "evidence": f"reason {d.id}"} for d in dims}}


class TestExtractVerdict(unittest.TestCase):
    def test_plain_json(self):
        obj = judge.extract_verdict('{"dimensions": {"J1": {"score": 4, "evidence": "x"}}}')
        self.assertEqual(obj["dimensions"]["J1"]["score"], 4)

    def test_fenced_json(self):
        text = '```json\n{"dimensions": {"J1": {"score": 5, "evidence": "x"}}}\n```'
        self.assertIn("J1", judge.extract_verdict(text)["dimensions"])

    def test_json_with_prose(self):
        text = 'Here is my verdict:\n{"dimensions": {"J1": {"score": 3, "evidence": "x"}}}\nDone.'
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
            judge._run_claude = lambda prompt, model, timeout: json.dumps(verdict_for(dims, next(scores)))
            res = judge.judge_artifact(make_skill(), judge.JudgeOptions(use_cache=False, votes=3))
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
            judge, "_run_claude", side_effect=lambda prompt, model, timeout: next(self._iter)
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
        self._cache_patch = mock.patch.object(cache, "CACHE_DIR", pathlib.Path(self._tmp.name))
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
            res = judge.judge_artifact(art, judge.JudgeOptions(model="sonnet", use_cache=True))
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
            res = judge.judge_artifact(art, judge.JudgeOptions(model="sonnet", use_cache=True))
        self.assertFalse(m.called, "valid cache hit must not call claude")
        self.assertTrue(res.cached)

    def test_aggregate_cache_with_bad_score_rejudges(self):
        art = make_skill()
        ab = art.raw.encode("utf-8")
        fp = rubrics.guidance_fingerprint()
        cm = f"sonnet|votes=3|rubric={fp}"
        dim_ids = [d.id for d in self.dims]
        # Aggregate-shaped cache entry with an out-of-range score -> MISS.
        bad = {"dimensions": {d.id: {"score": 9, "evidence": "x"} for d in self.dims}, "votes": 3}
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
        dims = rubrics.applicable_dimensions("skill", "foo")
        # _run_claude returns a verdict whose 'dimensions' is the wrong type;
        # extract/validate pass shape-wise only if dict — here force a TypeError
        # in result-building by stubbing _single_verdict to return junk.
        with mock.patch.object(judge, "_single_verdict", return_value={"dimensions": "not-a-dict"}):
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
        text = 'Sure! {"dimensions": {"J1": {"score": 4, "evidence": "ok"}}} Hope that helps.'
        self.assertEqual(judge.extract_verdict(text)["dimensions"]["J1"]["score"], 4)

    def test_two_objects_picks_one_with_dimensions(self):
        text = '{"note": "ignore me"} then {"dimensions": {"J1": {"score": 3, "evidence": "y"}}}'
        out = judge.extract_verdict(text)
        self.assertIn("dimensions", out)
        self.assertEqual(out["dimensions"]["J1"]["score"], 3)

    def test_stray_braces_in_strings(self):
        text = 'prefix {"dimensions": {"J1": {"score": 2, "evidence": "has } brace { inside"}}} suffix'
        out = judge.extract_verdict(text)
        self.assertEqual(out["dimensions"]["J1"]["evidence"], "has } brace { inside")

    def test_leading_stray_open_brace(self):
        text = '{ broken not json { then {"dimensions": {"J1": {"score": 5, "evidence": "z"}}}'
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
        self._patch = mock.patch.object(cache, "CACHE_DIR", pathlib.Path(self._tmp.name))
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
        self.assertEqual(leftovers, [], f"no temp/partial files should remain: {leftovers}")

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
        self._patch = mock.patch.object(cache, "CACHE_DIR", pathlib.Path(self._tmp.name))
        self._patch.start()
        self.dims = rubrics.applicable_dimensions("skill", "foo")

    def tearDown(self):
        self._patch.stop()
        self._tmp.cleanup()

    def test_fingerprint_changes_with_guidance(self):
        fp1 = rubrics.guidance_fingerprint()
        # Replace just the first dimension's guidance string.
        patched = (dataclasses_replace(rubrics.DIMENSIONS[0], guidance="EDITED"),) + rubrics.DIMENSIONS[1:]
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
        cache.put(ab, f"sonnet|votes=1|rubric={real_fp}", dim_ids, verdict_for(self.dims, 5))
        with mock.patch.object(rubrics, "guidance_fingerprint", return_value="deadbeefdeadbeef"):
            with _StubClaude(json.dumps(verdict_for(self.dims, 4))) as m:
                res = judge.judge_artifact(art, judge.JudgeOptions(model="sonnet", use_cache=True))
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
            "---\nname: fancy-name-a\ndescription: x. Use when y.\n---\nbody", encoding="utf-8"
        )
        (skills / "dir-stem-b").mkdir(parents=True)
        (skills / "dir-stem-b" / "SKILL.md").write_text(
            "---\nname: fancy-name-b\ndescription: x. Use when y.\n---\nbody", encoding="utf-8"
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
        judge._run_claude = lambda prompt, model, timeout: json.dumps(verdict_for(dims, 3))
        res = judge.judge_artifact(make_skill(), judge.JudgeOptions(use_cache=False))
        self.assertEqual(res.blocking_failures, [], "score 3 must not hard-block")
        adv_ids = {d.id for d in res.advisory_failures}
        crit_in_adv = {d.id for d in res.advisory_failures if d.critical}
        # Every failed dimension (all are below floor at score 3) is advisory,
        # and at least one of them is a CRITICAL dim — the previously-dropped case.
        self.assertEqual(adv_ids, {d.id for d in dims})
        self.assertTrue(crit_in_adv, "a critical dim at score 3 must appear in advisory_failures")


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
                        art, judge.JudgeOptions(model="sonnet", extra_context="v2", use_cache=True)
                    )
                self.assertTrue(m.called, "changed extra_context must invalidate the entry")
                self.assertFalse(res.cached)
                # And the original context still hits without a call.
                with _StubClaude("SHOULD NOT BE CALLED") as m2:
                    res2 = judge.judge_artifact(
                        art, judge.JudgeOptions(model="sonnet", extra_context="v1", use_cache=True)
                    )
                self.assertFalse(m2.called, "matching extra_context must still serve the cache")
                self.assertTrue(res2.cached)


# ---- C3: explicit file matching no artifact warns (not silently dropped) ---
class TestC3ExplicitFileNoMatchWarns(unittest.TestCase):
    def _write_plugin(self, root: pathlib.Path):
        (root / ".claude-plugin").mkdir(parents=True)
        (root / ".claude-plugin" / "plugin.json").write_text("{}", encoding="utf-8")
        (root / "skills" / "real-skill").mkdir(parents=True)
        (root / "skills" / "real-skill" / "SKILL.md").write_text(
            "---\nname: real-skill\ndescription: x. Use when y.\n---\nbody", encoding="utf-8"
        )

    def test_bogus_file_inside_plugin_warns_and_returns_empty(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td) / "plugins" / "p"
            self._write_plugin(root)
            bogus = root / "skills" / "real-skill" / "NOTES.md"  # not a judgeable artifact
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
        judge._run_claude = lambda prompt, model, timeout: json.dumps(verdict_for(dims, 5))
        opts = judge.JudgeOptions(use_cache=False, votes=1)
        res = judge.judge_artifact(make_skill(), opts)
        self.assertTrue(res.ok)

    def test_options_use_cache_false_skips_cache(self):
        dims = rubrics.applicable_dimensions("skill", "foo")
        judge._run_claude = lambda prompt, model, timeout: json.dumps(verdict_for(dims, 5))
        # use_cache=False on the options bundle forces a fresh (uncached) verdict.
        opts = judge.JudgeOptions(use_cache=False)
        res = judge.judge_artifact(make_skill(), opts)
        self.assertFalse(res.cached)


def dataclasses_replace(obj, **kw):
    import dataclasses
    return dataclasses.replace(obj, **kw)


if __name__ == "__main__":
    unittest.main()
