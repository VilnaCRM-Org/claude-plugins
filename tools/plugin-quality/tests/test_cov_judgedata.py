"""Coverage tests for the judge's pure-data / cache modules.

Targets the residual uncovered paths in:

* ``judge/cache.py``       — the ``get`` error fallback (corrupt/unreadable
                             entry -> ``None``) and the ``put`` atomic-publish
                             cleanup whose temp-file unlink may itself fail.
* ``judge/calibration.py`` — the ``CalibrationCase.artifact`` command/agent
                             path-construction branch (neither skill nor
                             meta-guide).
* ``judge/rubrics.py``     — the ``Dimension.__post_init__`` ``block_floor``
                             type guard, plus the ``applies`` name-filter branch.

No model calls are made: these modules are pure data plus tiny constructors and
a filesystem-backed cache, so the filesystem error paths are exercised by
writing real temp files and monkeypatching ``os.replace`` / ``os.unlink``.
"""

import json
import os
import pathlib
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "judge"))
sys.path.insert(0, str(HERE.parent / "lint"))

import cache  # noqa: E402
import calibration  # noqa: E402
import rubrics  # noqa: E402

ARGS = (b"artifact", "model|votes=1|rubric=abc", ["J1"], "ctx")


class TestCacheGetErrorPaths(unittest.TestCase):
    """``get`` must swallow a corrupt or unreadable entry and return ``None``."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._orig = cache.CACHE_DIR
        cache.CACHE_DIR = pathlib.Path(self._tmp.name)

    def tearDown(self):
        cache.CACHE_DIR = self._orig
        self._tmp.cleanup()

    def _entry_path(self):
        key = cache._key(*ARGS)
        return cache.CACHE_DIR / f"{key}.json"

    def test_corrupt_json_returns_none(self):
        # A present-but-invalid JSON file triggers json.JSONDecodeError -> None.
        self._entry_path().write_text("{ not valid json", encoding="utf-8")
        self.assertIsNone(cache.get(*ARGS))

    def test_unreadable_entry_returns_none(self):
        # An entry whose read raises OSError (here: a directory at the file path,
        # which is_file() reports False) -> the OSError arm returns None. To hit
        # is_file()==True AND a read error, monkeypatch read_text to raise OSError.
        path = self._entry_path()
        path.write_text(json.dumps({"ok": True}), encoding="utf-8")

        orig_read_text = pathlib.Path.read_text

        def boom(self, *a, **k):
            if self == path:
                raise OSError("simulated unreadable file")
            return orig_read_text(self, *a, **k)

        pathlib.Path.read_text = boom
        try:
            self.assertIsNone(cache.get(*ARGS))
        finally:
            pathlib.Path.read_text = orig_read_text

    def test_absent_entry_returns_none(self):
        # No file at all: the is_file() guard is False, returns None directly.
        self.assertIsNone(cache.get(*ARGS))

    def test_roundtrip_put_then_get(self):
        # Happy path: put writes atomically, get reads it back identically.
        verdict = {"score": 5, "evidence": "ok"}
        cache.put(*ARGS[:3], verdict, ARGS[3])
        self.assertEqual(cache.get(*ARGS), verdict)


class TestCachePutCleanupPath(unittest.TestCase):
    """``put``'s atomic publish: a failed ``os.replace`` must clean up the temp
    file, and an OSError during that unlink must be swallowed (then re-raise)."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._orig = cache.CACHE_DIR
        cache.CACHE_DIR = pathlib.Path(self._tmp.name)

    def tearDown(self):
        cache.CACHE_DIR = self._orig
        self._tmp.cleanup()

    def test_replace_failure_unlink_failure_reraises(self):
        orig_replace = os.replace
        orig_unlink = os.unlink

        def replace_boom(src, dst):
            raise RuntimeError("simulated replace failure")

        def unlink_boom(p):
            # The inner cleanup unlink itself fails -> OSError swallowed by pass.
            raise OSError("simulated unlink failure")

        os.replace = replace_boom
        os.unlink = unlink_boom
        try:
            with self.assertRaises(RuntimeError):
                cache.put(*ARGS[:3], {"score": 1}, ARGS[3])
        finally:
            os.replace = orig_replace
            os.unlink = orig_unlink

    def test_replace_failure_unlink_succeeds_reraises(self):
        orig_replace = os.replace

        def replace_boom(src, dst):
            raise RuntimeError("simulated replace failure")

        os.replace = replace_boom
        try:
            with self.assertRaises(RuntimeError):
                cache.put(*ARGS[:3], {"score": 1}, ARGS[3])
        finally:
            os.replace = orig_replace
        # The temp file was cleaned up: only never-published entries leak nothing.
        leftovers = list(cache.CACHE_DIR.glob("*.tmp"))
        self.assertEqual(leftovers, [])


class TestCalibrationArtifactPaths(unittest.TestCase):
    """``CalibrationCase.artifact`` builds a kind-appropriate synthetic path."""

    def _artifact_for(self, kind):
        case = calibration.CalibrationCase(
            dimension_id="JX",
            polarity="P",
            kind=kind,
            name="thing",
            raw="---\nname: thing\ndescription: d\n---\n# Thing\n\nbody\n",
        )
        return case, case.artifact()

    def test_command_path_uses_commands_folder(self):
        case, art = self._artifact_for("command")
        self.assertEqual(art.kind, "command")
        self.assertIn("/commands/thing.md", str(art.path))

    def test_agent_path_uses_agents_folder(self):
        case, art = self._artifact_for("agent")
        self.assertEqual(art.kind, "agent")
        self.assertIn("/agents/thing.md", str(art.path))

    def test_skill_path_uses_skill_dir(self):
        case, art = self._artifact_for("skill")
        self.assertIn("/skills/thing/SKILL.md", str(art.path))

    def test_meta_guide_path(self):
        case, art = self._artifact_for("meta-guide")
        self.assertIn("/skills/thing.md", str(art.path))


class TestCalibrationLookups(unittest.TestCase):
    """The dimension-keyed lookups, including the unknown-dimension None path."""

    def test_cases_for_known(self):
        self.assertEqual(len(calibration.cases_for("J1")), 2)

    def test_cases_for_unknown_is_empty(self):
        self.assertEqual(calibration.cases_for("ZZZ"), [])

    def test_positive_and_negative_for_known(self):
        self.assertEqual(calibration.positive_for("J1").polarity, "P")
        self.assertEqual(calibration.negative_for("J1").polarity, "N")

    def test_positive_for_unknown_is_none(self):
        self.assertIsNone(calibration.positive_for("ZZZ"))

    def test_negative_for_unknown_is_none(self):
        self.assertIsNone(calibration.negative_for("ZZZ"))


class TestRubricsBlockFloorGuard(unittest.TestCase):
    """``Dimension.__post_init__`` rejects a non-int / bool ``block_floor``."""

    def _make(self, **over):
        kw = dict(
            id="JX",
            name="x",
            applies_to=("skill",),
            critical=True,
            floor=4,
            guidance="g",
        )
        kw.update(over)
        return rubrics.Dimension(**kw)

    def test_block_floor_bool_rejected(self):
        with self.assertRaises(ValueError) as ctx:
            self._make(block_floor=True)
        self.assertIn("block_floor must be an int", str(ctx.exception))

    def test_block_floor_non_int_rejected(self):
        with self.assertRaises(ValueError) as ctx:
            self._make(block_floor="2")
        self.assertIn("block_floor must be an int", str(ctx.exception))

    def test_block_floor_out_of_range_rejected(self):
        # Valid int type but violates 1 <= block_floor < floor <= 5.
        with self.assertRaises(ValueError) as ctx:
            self._make(block_floor=4, floor=4)
        self.assertIn("require 1 <= block_floor < floor <= 5", str(ctx.exception))

    def test_valid_dimension_constructs(self):
        d = self._make(block_floor=2, floor=4)
        self.assertEqual(d.block_floor, 2)


class TestRubricsApplies(unittest.TestCase):
    """``Dimension.applies`` kind gating and name_filter token-boundary match."""

    def _filtered(self):
        return rubrics.Dimension(
            id="JX",
            name="x",
            applies_to=("command", "agent"),
            critical=False,
            floor=4,
            guidance="g",
            name_filter="qa",
        )

    def test_kind_not_in_applies_to(self):
        self.assertFalse(self._filtered().applies("skill", "qa"))

    def test_name_filter_token_match(self):
        d = self._filtered()
        self.assertTrue(d.applies("command", "qa"))
        self.assertTrue(d.applies("command", "qa-manual"))
        self.assertTrue(d.applies("command", "manual_qa"))

    def test_name_filter_no_match(self):
        # "qa" must not match inside a larger token (no -/_ boundary).
        self.assertFalse(self._filtered().applies("command", "equality"))

    def test_no_name_filter_applies(self):
        d = rubrics.Dimension(
            id="JY",
            name="y",
            applies_to=("all",),
            critical=False,
            floor=4,
            guidance="g",
        )
        self.assertTrue(d.applies("skill", "anything"))


if __name__ == "__main__":
    unittest.main()
