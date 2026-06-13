"""Coverage-completion tests for ``lint/_model.py`` and ``lint/_common.py``.

These exercise the edge branches not reached by the behaviour-focused suites:
``Artifact.rel``/``name`` fallbacks, empty-frontmatter normalisation, the
first-H1-wins accumulator no-op, ``find_plugin_roots``/``by_kind`` happy paths,
and every ``Finding`` reporting helper (including the ``line=None`` location
branch and the invalid-severity guard).
"""

import pathlib
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import _common  # noqa: E402
import _model  # noqa: E402


class TestArtifactRel(unittest.TestCase):
    def test_rel_relative_to_repo_root(self):
        # plugin_root is <repo>/plugins/<name>; repo root is two levels up, so a
        # file beneath the repo root renders as a repo-relative path.
        repo = pathlib.Path("/repo")
        plugin_root = repo / "plugins" / "p"
        art = _model.Artifact(
            path=plugin_root / "commands" / "do.md",
            plugin_root=plugin_root,
            kind="command",
            raw="",
            has_frontmatter=False,
            frontmatter={},
            frontmatter_error=None,
            body="",
            h1=None,
            h2_sections=[],
        )
        self.assertEqual(art.rel, "plugins/p/commands/do.md")

    def test_rel_falls_back_to_absolute_when_not_under_repo(self):
        # A path outside the computed repo root raises ValueError in
        # relative_to and falls back to the absolute string (lines 53-54).
        plugin_root = pathlib.Path("/repo/plugins/p")
        outside = pathlib.Path("/elsewhere/file.md")
        art = _model.Artifact(
            path=outside,
            plugin_root=plugin_root,
            kind="command",
            raw="",
            has_frontmatter=False,
            frontmatter={},
            frontmatter_error=None,
            body="",
            h1=None,
            h2_sections=[],
        )
        self.assertEqual(art.rel, str(outside))


class TestArtifactName(unittest.TestCase):
    def _art(self, *, path, kind, frontmatter):
        return _model.Artifact(
            path=path,
            plugin_root=pathlib.Path("/repo/plugins/p"),
            kind=kind,
            raw="",
            has_frontmatter=bool(frontmatter),
            frontmatter=frontmatter,
            frontmatter_error=None,
            body="",
            h1=None,
            h2_sections=[],
        )

    def test_name_from_frontmatter(self):
        art = self._art(
            path=pathlib.Path("/repo/plugins/p/commands/do.md"),
            kind="command",
            frontmatter={"name": "  fancy-name  "},
        )
        self.assertEqual(art.name, "fancy-name")

    def test_name_skill_uses_parent_dir(self):
        # No usable frontmatter name + kind 'skill' -> parent directory name
        # (line 67).
        art = self._art(
            path=pathlib.Path("/repo/plugins/p/skills/my-skill/SKILL.md"),
            kind="skill",
            frontmatter={},
        )
        self.assertEqual(art.name, "my-skill")

    def test_name_non_skill_uses_stem(self):
        art = self._art(
            path=pathlib.Path("/repo/plugins/p/commands/do-thing.md"),
            kind="command",
            frontmatter={"name": "   "},  # blank -> not usable, fall through
        )
        self.assertEqual(art.name, "do-thing")


class TestSplitFrontmatterEmpty(unittest.TestCase):
    def test_empty_frontmatter_normalises_to_dict(self):
        # An empty YAML block yields None from safe_load, normalised to {} on
        # line 97 (has_fm True, no error).
        text = "---\n---\n# body\n"
        has_fm, data, err, body = _model.split_frontmatter(text)
        self.assertTrue(has_fm)
        self.assertEqual(data, {})
        self.assertIsNone(err)
        self.assertIn("# body", body)


class TestHeadingsFirstH1Wins(unittest.TestCase):
    def test_only_first_h1_is_captured(self):
        # The second ATX H1 must NOT overwrite the first; add_h1's guard takes
        # the no-op exit branch (168->exit).
        body = "# First\n\n# Second\n\n## Sec\n"
        h1, h2 = _model.extract_headings(body)
        self.assertEqual(h1, "First")
        self.assertEqual(h2, ["Sec"])

    def test_add_h1_noop_direct(self):
        acc = _model._Headings()
        acc.add_h1("one")
        acc.add_h1("two")  # ignored
        self.assertEqual(acc.h1, "one")


class TestFindPluginRoots(unittest.TestCase):
    def test_no_plugins_dir_returns_empty(self):
        with tempfile.TemporaryDirectory() as td:
            self.assertEqual(_model.find_plugin_roots(pathlib.Path(td)), [])

    def test_roots_with_manifest_are_collected(self):
        # A plugins/<name>/.claude-plugin/plugin.json marks a real root; one
        # without a manifest is skipped (covers the append on line 300).
        with tempfile.TemporaryDirectory() as td:
            repo = pathlib.Path(td)
            good = repo / "plugins" / "good"
            (good / ".claude-plugin").mkdir(parents=True)
            (good / ".claude-plugin" / "plugin.json").write_text("{}", "utf-8")
            (repo / "plugins" / "nomanifest").mkdir(parents=True)
            roots = _model.find_plugin_roots(repo)
        self.assertEqual(roots, [good])


class TestByKind(unittest.TestCase):
    def test_filters_by_kind(self):
        def mk(kind):
            return _model.Artifact(
                path=pathlib.Path(f"/repo/plugins/p/{kind}.md"),
                plugin_root=pathlib.Path("/repo/plugins/p"),
                kind=kind,
                raw="",
                has_frontmatter=False,
                frontmatter={},
                frontmatter_error=None,
                body="",
                h1=None,
                h2_sections=[],
            )

        arts = [mk("command"), mk("agent"), mk("command")]
        cmds = _model.by_kind(arts, "command")
        self.assertEqual([a.kind for a in cmds], ["command", "command"])
        self.assertEqual(_model.by_kind(arts, "skill"), [])


class TestFinding(unittest.TestCase):
    def _finding(self, **kw):
        base = dict(
            check="L1",
            rule="frontmatter.command.missing-key",
            severity="S2",
            path="plugins/p/commands/do.md",
            message="missing key",
        )
        base.update(kw)
        return _common.Finding(**base)

    def test_invalid_severity_raises(self):
        # __post_init__ guard (line 48).
        with self.assertRaises(ValueError):
            self._finding(severity="S9")

    def test_as_dict_round_trips_fields(self):
        # Line 53.
        d = self._finding(line=7).as_dict()
        self.assertEqual(d["check"], "L1")
        self.assertEqual(d["severity"], "S2")
        self.assertEqual(d["line"], 7)

    def test_location_with_line(self):
        loc = self._finding(line=12).location()
        self.assertEqual(loc, "plugins/p/commands/do.md:12")

    def test_location_without_line(self):
        # line=None branch of location().
        self.assertEqual(self._finding().location(), "plugins/p/commands/do.md")

    def test_render_includes_all_parts(self):
        rendered = self._finding(line=3).render()
        self.assertIn("plugins/p/commands/do.md:3", rendered)
        self.assertIn("[S2 L1]", rendered)
        self.assertIn("missing key", rendered)
        self.assertIn("(frontmatter.command.missing-key)", rendered)


class TestToJsonAndSummarize(unittest.TestCase):
    def test_to_json_emits_sorted_array(self):
        # Line 66.
        findings = [
            _common.Finding("L1", "r.a", "S1", "a.md", "m1", line=1),
            _common.Finding("L2", "r.b", "S3", "b.md", "m2"),
        ]
        out = _common.to_json(findings)
        self.assertTrue(out.startswith("["))
        # sort_keys means 'check' sorts before 'line'/'message' within an object.
        self.assertIn('"check": "L1"', out)
        self.assertIn('"line": null', out)

    def test_to_json_empty(self):
        self.assertEqual(_common.to_json([]), "[]")

    def test_summarize_counts_by_severity(self):
        findings = [
            _common.Finding("L1", "r", "S1", "a.md", "m"),
            _common.Finding("L1", "r", "S1", "a.md", "m"),
            _common.Finding("L1", "r", "S3", "a.md", "m"),
        ]
        counts = _common.summarize(findings)
        self.assertEqual(counts["S1"], 2)
        self.assertEqual(counts["S2"], 0)
        self.assertEqual(counts["S3"], 1)
        self.assertEqual(counts["S4"], 0)
        self.assertEqual(counts["total"], 3)


if __name__ == "__main__":
    unittest.main()
