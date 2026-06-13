"""Self-tests for check_manifest (M1-M4).

Builds synthetic repo trees in a temp dir (no committed fixtures) with
``plugins/<name>/.claude-plugin/plugin.json`` and a repo-level
``.claude-plugin/marketplace.json`` written via ``json.dumps``, and verifies
the real shipped plugin + marketplace are clean today.
"""

import json
import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_manifest  # noqa: E402

REPO_ROOT = HERE.parent.parent.parent
REAL_PLUGIN = REPO_ROOT / "plugins" / "php-backend-sdlc"


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


class ManifestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.repo = self.tmp / "repo"
        (self.repo / "plugins").mkdir(parents=True)
        (self.repo / ".claude-plugin").mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # --- helpers ----------------------------------------------------------

    def _write_plugin(self, name, manifest):
        root = self.repo / "plugins" / name
        (root / ".claude-plugin").mkdir(parents=True, exist_ok=True)
        (root / ".claude-plugin" / "plugin.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )
        return root

    def _make_plugin_dir(self, name):
        """Create a plugins/<name>/ dir (so marketplace source resolves)."""
        (self.repo / "plugins" / name).mkdir(parents=True, exist_ok=True)

    def _write_marketplace(self, manifest):
        (self.repo / ".claude-plugin" / "marketplace.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )

    def _plugin_findings(self, root, check_id=None):
        fs = check_manifest.check(root)
        if check_id is not None:
            fs = [f for f in fs if f.check == check_id]
        return fs

    def _market_findings(self, check_id=None):
        fs = check_manifest.check_marketplace(self.repo)
        if check_id is not None:
            fs = [f for f in fs if f.check == check_id]
        return fs

    # --- MF-1 (M1) plugin.json fields ------------------------------------

    def test_mf1_full_manifest_passes(self):
        root = self._write_plugin("acme", _full_plugin_manifest("acme"))
        self.assertEqual(self._plugin_findings(root), [])

    def test_mf1_missing_license_fails(self):
        m = _full_plugin_manifest("acme")
        del m["license"]
        root = self._write_plugin("acme", m)
        fs = self._plugin_findings(root, "M1")
        self.assertEqual(len(fs), 1)
        self.assertIn("license", fs[0].message)
        self.assertEqual(fs[0].rule, "manifest.plugin.fields")
        self.assertEqual(fs[0].severity, "S1")

    def test_mf1_empty_author_name_fails(self):
        m = _full_plugin_manifest("acme")
        m["author"]["name"] = "   "
        root = self._write_plugin("acme", m)
        fs = self._plugin_findings(root, "M1")
        self.assertEqual(len(fs), 1)
        self.assertIn("author.name", fs[0].message)

    def test_mf1_empty_keywords_fails(self):
        m = _full_plugin_manifest("acme")
        m["keywords"] = []
        root = self._write_plugin("acme", m)
        fs = self._plugin_findings(root, "M1")
        self.assertEqual(len(fs), 1)
        self.assertIn("keywords", fs[0].message)

    def test_mf1_extra_unknown_field_passes(self):
        # Edge: extra unknown field is warn-only — must NOT fail.
        m = _full_plugin_manifest("acme")
        m["unknownField"] = "whatever"
        root = self._write_plugin("acme", m)
        self.assertEqual(self._plugin_findings(root), [])

    def test_mf1_missing_manifest_file_fails(self):
        root = self.repo / "plugins" / "acme"
        root.mkdir(parents=True)
        fs = self._plugin_findings(root)
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "manifest.plugin.missing")
        self.assertEqual(fs[0].severity, "S1")

    def test_mf1_unparseable_manifest_fails(self):
        root = self.repo / "plugins" / "acme"
        (root / ".claude-plugin").mkdir(parents=True)
        (root / ".claude-plugin" / "plugin.json").write_text("{ not json", encoding="utf-8")
        fs = self._plugin_findings(root)
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].check, "M1")
        self.assertIn("does not parse", fs[0].message)

    # --- MF-2 (M2) semver -------------------------------------------------

    def test_mf2_semver_passes(self):
        root = self._write_plugin("acme", _full_plugin_manifest("acme"))
        self.assertEqual(self._plugin_findings(root, "M2"), [])

    def test_mf2_version_0_1_fails(self):
        m = _full_plugin_manifest("acme")
        m["version"] = "0.1"
        root = self._write_plugin("acme", m)
        fs = self._plugin_findings(root, "M2")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "manifest.plugin.semver")
        self.assertEqual(fs[0].severity, "S1")

    def test_mf2_prerelease_passes_edge(self):
        # Edge: prerelease suffix is allowed by policy.
        m = _full_plugin_manifest("acme")
        m["version"] = "1.0.0-rc.1"
        root = self._write_plugin("acme", m)
        self.assertEqual(self._plugin_findings(root, "M2"), [])

    def test_mf2_absent_version_is_only_m1_not_m2(self):
        # Fix 3: a manifest with NO version is one root cause -> exactly ONE
        # finding (M1 missing-field), never an additional M2 semver finding.
        m = _full_plugin_manifest("acme")
        del m["version"]
        root = self._write_plugin("acme", m)
        fs = self._plugin_findings(root)
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].check, "M1")
        self.assertIn("version", fs[0].message)
        self.assertEqual(self._plugin_findings(root, "M2"), [])

    def test_mf2_empty_version_is_only_m1_not_m2(self):
        # Fix 3: an empty version string is likewise M1-only (no double finding).
        m = _full_plugin_manifest("acme")
        m["version"] = "   "
        root = self._write_plugin("acme", m)
        fs = self._plugin_findings(root)
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].check, "M1")
        self.assertEqual(self._plugin_findings(root, "M2"), [])

    def test_mf2_non_string_version_is_flagged(self):
        # Fix (cubic regression): a present-but-NON-STRING version (YAML float
        # 1.0, a list, ...) must not silently bypass M2. It is non-empty so M1
        # does not fire; M2 must catch it as not-a-semver-string.
        m = _full_plugin_manifest("acme")
        m["version"] = 1.0
        root = self._write_plugin("acme", m)
        m1 = self._plugin_findings(root, "M1")
        self.assertEqual([f for f in m1 if "version" in f.message], [])
        fs = self._plugin_findings(root, "M2")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "manifest.plugin.semver")

    # --- MF-3 (M3) name == dir -------------------------------------------

    def test_mf3_name_matches_dir_passes(self):
        root = self._write_plugin("acme", _full_plugin_manifest("acme"))
        self.assertEqual(self._plugin_findings(root, "M3"), [])

    def test_mf3_name_mismatch_fails(self):
        # Dir is "acme" but manifest name is "different".
        root = self._write_plugin("acme", _full_plugin_manifest("different"))
        fs = self._plugin_findings(root, "M3")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "manifest.plugin.name-dir")
        self.assertIn("different", fs[0].message)
        self.assertIn("acme", fs[0].message)

    # --- MF-4 (M4) marketplace -------------------------------------------

    def test_mf4_full_marketplace_passes(self):
        self._make_plugin_dir("acme")
        self._write_marketplace(_full_marketplace(("acme",)))
        self.assertEqual(self._market_findings(), [])

    def test_mf4_wrong_source_fails(self):
        self._make_plugin_dir("acme")
        m = _full_marketplace(("acme",))
        m["plugins"][0]["source"] = "./plugins/wrong"
        self._write_marketplace(m)
        fs = self._market_findings("M4")
        # source mismatch + missing dir for "./plugins/wrong".
        self.assertTrue(any("!=" in f.message for f in fs))
        self.assertTrue(all(f.severity == "S1" for f in fs))

    def test_mf4_multiple_plugins_all_validated(self):
        self._make_plugin_dir("acme")
        self._make_plugin_dir("beta")
        self._write_marketplace(_full_marketplace(("acme", "beta")))
        self.assertEqual(self._market_findings(), [])

    def test_mf4_source_dir_missing_fails(self):
        # Correct source string but the dir does not exist on disk.
        self._write_marketplace(_full_marketplace(("ghost",)))
        fs = self._market_findings("M4")
        self.assertEqual(len(fs), 1)
        self.assertIn("does not exist", fs[0].message)

    def test_mf4_missing_owner_name_fails(self):
        self._make_plugin_dir("acme")
        m = _full_marketplace(("acme",))
        del m["owner"]["name"]
        self._write_marketplace(m)
        fs = self._market_findings("M4")
        self.assertTrue(any("owner.name" in f.message for f in fs))

    def test_mf4_entry_no_name_is_only_name_finding(self):
        # Fix 4: an entry with no name yields the missing-name finding ONLY, not
        # also a spurious "source mismatch" against the undefined
        # "./plugins/None" expectation. The source points at a real dir so the
        # dir-exists check stays clean and the name finding is isolated.
        self._make_plugin_dir("acme")
        m = _full_marketplace(("acme",))
        del m["plugins"][0]["name"]
        m["plugins"][0]["source"] = "./plugins/acme"
        self._write_marketplace(m)
        fs = self._market_findings("M4")
        self.assertEqual(len(fs), 1)
        self.assertIn("missing or empty name", fs[0].message)
        self.assertFalse(any("!=" in f.message for f in fs))

    def test_mf4_empty_plugins_fails(self):
        m = _full_marketplace(())
        m["plugins"] = []
        self._write_marketplace(m)
        fs = self._market_findings("M4")
        self.assertEqual(len(fs), 1)
        self.assertIn("at least one plugin", fs[0].message)

    def test_mf4_missing_marketplace_file_fails(self):
        fs = self._market_findings()
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "manifest.marketplace.missing")
        self.assertEqual(fs[0].severity, "S1")

    def test_mf4_unparseable_marketplace_fails(self):
        (self.repo / ".claude-plugin" / "marketplace.json").write_text(
            "{ not json", encoding="utf-8"
        )
        fs = self._market_findings()
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].check, "M4")
        self.assertIn("does not parse", fs[0].message)

    # --- real shipped repo is clean today --------------------------------

    def test_real_plugin_clean(self):
        self.assertTrue(REAL_PLUGIN.is_dir(), f"missing real plugin at {REAL_PLUGIN}")
        fs = check_manifest.check(REAL_PLUGIN)
        self.assertEqual(
            fs, [], "shipped plugin manifest must be clean; got: "
            + "; ".join(f.render() for f in fs)
        )

    def test_real_marketplace_clean(self):
        fs = check_manifest.check_marketplace(REPO_ROOT)
        self.assertEqual(
            fs, [], "shipped marketplace must be clean; got: "
            + "; ".join(f.render() for f in fs)
        )


if __name__ == "__main__":
    unittest.main()
