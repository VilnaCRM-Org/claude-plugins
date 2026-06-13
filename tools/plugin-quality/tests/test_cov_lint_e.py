"""Coverage-completion self-tests for check_manifest and check_generalization.

Targets the residual line/branch gaps left uncovered by ``test_manifest.py``
and ``test_generalization.py``: the missing-name guards, non-relative-path
``ValueError`` fallbacks, marketplace top-field/source-dir/entry-shape edges,
the read-error and non-dir-root short-circuits, and the latin-1 decode path.

Synthetic plugin trees are built at runtime in a temp dir; no committed
fixtures, and no denylisted literal is written into this source file (forbidden
identifiers are assembled from fragments).
"""

import json
import os
import pathlib
import shutil
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_generalization  # noqa: E402
import check_manifest  # noqa: E402

# Assemble a denylisted token from fragments so this file stays clean.
TOK_USER_SERVICE = "user" + "-" + "service"  # user[-_ ]service


def _full_plugin_manifest(name="acme"):
    return {
        "name": name,
        "description": "A fully populated plugin manifest for testing.",
        "version": "0.1.0",
        "author": {"name": "Test Author", "url": "https://example.com"},
        "homepage": "https://example.com/acme",
        "repository": "https://github.com/example/acme",
        "license": "MIT",
        "keywords": ["test", "acme"],
    }


def _full_marketplace(plugin_names=("acme",)):
    return {
        "name": "test-marketplace",
        "description": "Test marketplace",
        "owner": {"name": "Test Org", "url": "https://example.com"},
        "plugins": [
            {
                "name": n,
                "description": f"{n} plugin",
                "source": f"./plugins/{n}",
            }
            for n in plugin_names
        ],
    }


class ManifestCovCase(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.repo = self.tmp / "repo"
        (self.repo / "plugins").mkdir(parents=True)
        (self.repo / ".claude-plugin").mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write_plugin(self, name, manifest):
        root = self.repo / "plugins" / name
        (root / ".claude-plugin").mkdir(parents=True, exist_ok=True)
        (root / ".claude-plugin" / "plugin.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )
        return root

    def _write_marketplace(self, manifest):
        (self.repo / ".claude-plugin" / "marketplace.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )

    # --- M3: missing/non-string name guard (check_manifest.py:134) --------

    def test_m3_missing_name_skips_namedir_check(self):
        # No "name" key: M3's guard returns [] (covers line 134). M1 reports the
        # absent name instead; M3 must add nothing.
        m = _full_plugin_manifest("acme")
        del m["name"]
        root = self._write_plugin("acme", m)
        self.assertEqual([f for f in check_manifest.check(root) if f.check == "M3"], [])

    # --- check(): manifest not under repo_root (check_manifest.py:159-160) -

    def test_check_plugin_path_outside_repo_root_falls_back(self):
        # plugin_root.parent.parent is the "repo root". When the manifest is not
        # relative to it (it always is for a normal layout), relative_to raises
        # ValueError and rel falls back to the absolute path. Force that by
        # making plugin_root a top-level dir whose grandparent does not contain
        # the manifest path -> patch relative_to to raise.
        root = self._write_plugin("acme", _full_plugin_manifest("acme"))
        real_relative_to = pathlib.PurePath.relative_to

        def fake_relative_to(self, *args, **kwargs):
            if self.name == "plugin.json":
                raise ValueError("not relative")
            return real_relative_to(self, *args, **kwargs)

        with mock.patch.object(pathlib.PurePath, "relative_to", fake_relative_to):
            fs = check_manifest.check(root)
        # Manifest is valid, so findings are empty; the rel fallback ran without
        # crashing. Confirm via an invalid manifest so a finding carries the
        # absolute path.
        self.assertEqual(fs, [])

    def test_check_plugin_path_outside_repo_root_uses_absolute_path(self):
        # Same fallback, but with a finding so we can assert the absolute path.
        m = _full_plugin_manifest("acme")
        del m["license"]
        root = self._write_plugin("acme", m)
        real_relative_to = pathlib.PurePath.relative_to

        def fake_relative_to(self, *args, **kwargs):
            if self.name == "plugin.json":
                raise ValueError("not relative")
            return real_relative_to(self, *args, **kwargs)

        with mock.patch.object(pathlib.PurePath, "relative_to", fake_relative_to):
            fs = check_manifest.check(root)
        self.assertTrue(fs)
        self.assertTrue(os.path.isabs(fs[0].path))
        self.assertTrue(fs[0].path.endswith("plugin.json"))

    # --- M4: marketplace top-level name empty (check_manifest.py:221) ------

    def test_m4_missing_top_name_fails(self):
        m = _full_marketplace(("acme",))
        (self.repo / "plugins" / "acme").mkdir(parents=True, exist_ok=True)
        del m["name"]
        self._write_marketplace(m)
        fs = check_manifest.check_marketplace(self.repo)
        self.assertTrue(
            any("required field: name" in f.message for f in fs),
            [f.message for f in fs],
        )

    # --- M4: entry source missing/non-string (check_manifest.py:260) -------

    def test_m4_entry_without_source_skips_dir_check(self):
        # An entry with a real name but NO source: the source-match check fires
        # (source None != ./plugins/acme), but the source-DIR check must return
        # [] via its guard (line 260) since source is not a non-empty string.
        (self.repo / "plugins" / "acme").mkdir(parents=True, exist_ok=True)
        m = _full_marketplace(("acme",))
        del m["plugins"][0]["source"]
        self._write_marketplace(m)
        fs = check_manifest.check_marketplace(self.repo)
        # No "does not exist" (dir-check skipped); a mismatch is reported.
        self.assertFalse(any("does not exist" in f.message for f in fs))
        self.assertTrue(any("!=" in f.message for f in fs))

    # --- M4: plugins entry not an object (check_manifest.py:276) -----------

    def test_m4_entry_not_object_fails(self):
        m = _full_marketplace(("acme",))
        m["plugins"] = ["i-am-a-string"]
        self._write_marketplace(m)
        fs = check_manifest.check_marketplace(self.repo)
        self.assertEqual(len(fs), 1)
        self.assertIn("plugins[0] is not an object", fs[0].message)
        self.assertEqual(fs[0].check, "M4")

    # --- check_marketplace(): manifest not under repo_root (304-305) -------

    def test_check_marketplace_path_outside_repo_root_uses_absolute_path(self):
        self._write_marketplace(_full_marketplace(("ghost",)))
        real_relative_to = pathlib.PurePath.relative_to

        def fake_relative_to(self, *args, **kwargs):
            if self.name == "marketplace.json":
                raise ValueError("not relative")
            return real_relative_to(self, *args, **kwargs)

        with mock.patch.object(pathlib.PurePath, "relative_to", fake_relative_to):
            fs = check_manifest.check_marketplace(self.repo)
        self.assertTrue(fs)
        self.assertTrue(os.path.isabs(fs[0].path))
        self.assertTrue(fs[0].path.endswith("marketplace.json"))


class GeneralizationCovCase(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.root = self.tmp / "plugins" / "p"
        for sub in ("skills", "commands", "agents", "scripts"):
            (self.root / sub).mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # --- _read_text OSError + _scan_file_denylist None (96-97, 132) -------

    def test_read_text_oserror_returns_none(self):
        # A path whose read_bytes raises OSError yields None (lines 96-97).
        missing = self.root / "skills" / "ghost.md"
        self.assertIsNone(check_generalization._read_text(missing))

    def test_scan_file_denylist_skips_unreadable_file(self):
        # When _read_text returns None, _scan_file_denylist short-circuits to []
        # (line 132). Drive it through check() by patching _read_text to None for
        # a real scanned file so the whole denylist path executes with text=None.
        (self.root / "skills" / "s.md").write_text(
            f"{TOK_USER_SERVICE}\n", encoding="utf-8"
        )
        with mock.patch.object(check_generalization, "_read_text", return_value=None):
            fs = [f for f in check_generalization.check(self.root) if f.check == "L28"]
        self.assertEqual(fs, [])

    # --- _scan_tree_hygiene: plugin_root not a dir (line 155) -------------

    def test_tree_hygiene_nonexistent_root_returns_empty(self):
        # plugin_root that is not a directory: the L29 scan returns [] (line 155).
        ghost = self.tmp / "plugins" / "does-not-exist"
        fs = [f for f in check_generalization.check(ghost) if f.check == "L29"]
        self.assertEqual(fs, [])

    # --- check().rel(): path not under repo_root (lines 180-181) ----------

    def test_rel_fallback_uses_absolute_path_when_not_relative(self):
        # A denylisted token in a scoped file produces an L28 finding whose path
        # is built by rel(). Patch relative_to to raise so rel() falls back to
        # the absolute path (lines 180-181).
        d = self.root / "skills"
        (d / "leak.md").write_text(f"{TOK_USER_SERVICE}\n", encoding="utf-8")
        real_relative_to = pathlib.PurePath.relative_to

        def fake_relative_to(self, *args, **kwargs):
            if self.name == "leak.md":
                raise ValueError("not relative")
            return real_relative_to(self, *args, **kwargs)

        with mock.patch.object(pathlib.PurePath, "relative_to", fake_relative_to):
            fs = [f for f in check_generalization.check(self.root) if f.check == "L28"]
        self.assertEqual(len(fs), 1)
        self.assertTrue(os.path.isabs(fs[0].path))
        self.assertTrue(fs[0].path.endswith("leak.md"))


if __name__ == "__main__":
    unittest.main()
