"""Branch/line-coverage closeout tests for the Tier-1 lint modules.

Targets the residual uncovered lines/branches in five linters:
``check_frontmatter``, ``check_naming``, ``check_references``,
``check_escalation`` and ``lint_all``. Each test drives a real code path over a
synthetic temp tree (or, for the aggregator's branch guards, a real
``lint_all.main([...])`` / ``run`` call), never a mock of the logic under test.
"""

import contextlib
import importlib
import io
import json
import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import _model  # noqa: E402
import check_escalation  # noqa: E402
import check_frontmatter  # noqa: E402
import check_naming  # noqa: E402
import check_references  # noqa: E402
import lint_all  # noqa: E402


def _write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class TempTreeBase(unittest.TestCase):
    """A throwaway ``<repo>/plugins/demo`` tree so ``Artifact.rel`` resolves."""

    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.plugin_root = self.tmp / "plugins" / "demo"
        (self.plugin_root / "commands").mkdir(parents=True)
        (self.plugin_root / "agents").mkdir(parents=True)
        (self.plugin_root / "skills").mkdir(parents=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def command(self, name: str, text: str) -> None:
        _write(self.plugin_root / "commands" / f"{name}.md", text)

    def agent(self, name: str, text: str) -> None:
        _write(self.plugin_root / "agents" / f"{name}.md", text)

    def skill(self, name: str, text: str) -> None:
        _write(self.plugin_root / "skills" / name / "SKILL.md", text)


# --------------------------------------------------------------------------- #
# check_frontmatter
# --------------------------------------------------------------------------- #
class FrontmatterCoverageTests(TempTreeBase):
    def test_present_tools_rejects_non_list_non_str(self) -> None:
        # check_frontmatter line 73: _present_tools default return False for a
        # value that is neither a list nor a string (here an int).
        self.assertFalse(check_frontmatter._present_tools(123))
        self.assertFalse(check_frontmatter._present_tools(None))

    def test_present_tools_accepts_valid_shapes(self) -> None:
        # Positive control for the two non-default branches.
        self.assertTrue(check_frontmatter._present_tools(["Read"]))
        self.assertTrue(check_frontmatter._present_tools("Bash, Read"))

    def test_tool_names_default_empty_for_non_list_non_str(self) -> None:
        # check_frontmatter line 253: _tool_names returns [] when the value is
        # neither a list nor a non-empty string (None / int / empty string).
        self.assertEqual(check_frontmatter._tool_names(None), [])
        self.assertEqual(check_frontmatter._tool_names(42), [])
        self.assertEqual(check_frontmatter._tool_names("   "), [])

    def test_skill_missing_required_key_flagged(self) -> None:
        # check_frontmatter line 219: skill with no name/description yields the
        # L4 missing-key finding.
        self.skill("demo-skill", "---\ntools: Read\n---\n# Demo\nbody\n")
        findings = check_frontmatter.check(self.plugin_root)
        l4 = [f for f in findings if f.check == "L4"]
        self.assertTrue(
            any("missing frontmatter key name" in f.message for f in l4),
            msg=[f.render() for f in l4],
        )

    def test_unknown_kind_skips_handler_then_l33(self) -> None:
        # check_frontmatter branch 319->323: an artifact whose kind is not in
        # _KIND_CHECKS (handler is None) must skip the handler dispatch and fall
        # through to the L33 command/agent guard (also skipped here). We inject a
        # synthetic artifact via _model.discover so check()'s own dispatch runs.
        art = _model.Artifact(
            path=self.plugin_root / "weird.md",
            plugin_root=self.plugin_root,
            kind="mystery",  # not in _KIND_CHECKS, not command/agent
            raw="body",
            has_frontmatter=False,
            frontmatter={},
            frontmatter_error=None,
            body="body",
            h1=None,
            h2_sections=[],
        )
        original = _model.discover
        _model.discover = lambda _root: [art]
        try:
            findings = check_frontmatter.check(self.plugin_root)
        finally:
            _model.discover = original
        self.assertEqual(findings, [])


# --------------------------------------------------------------------------- #
# check_naming
# --------------------------------------------------------------------------- #
class NamingCoverageTests(TempTreeBase):
    def test_fm_str_returns_none_for_non_string(self) -> None:
        # check_naming line 57: _fm_str returns None for a non-string value.
        self.agent("a", "---\nname: 123\nmodel: opus\n---\n# a\nbody\n")
        art = next(a for a in _model.discover(self.plugin_root) if a.kind == "agent")
        self.assertIsNone(check_naming._fm_str(art, "name"))

    def test_agent_with_no_name_short_circuits(self) -> None:
        # check_naming line 66: _check_agent_name returns [] when fm name is
        # absent (nothing to compare against the stem/H1).
        self.agent("a", "---\nmodel: opus\n---\n# a\nbody\n")
        findings = check_naming.check(self.plugin_root)
        self.assertEqual(
            [f for f in findings if f.rule == "naming.agent.name-mismatch"], []
        )

    def test_agent_name_matches_stem_but_no_h1(self) -> None:
        # check_naming branch 80->96: name == stem and art.h1 is None, so the
        # H1-comparison block is skipped and no mismatch is raised.
        self.agent("widget", "---\nname: widget\nmodel: opus\n---\nbody only\n")
        art = next(a for a in _model.discover(self.plugin_root) if a.kind == "agent")
        self.assertIsNone(art.h1)
        self.assertEqual(
            [
                f
                for f in check_naming.check(self.plugin_root)
                if f.rule == "naming.agent.name-mismatch"
            ],
            [],
        )

    def test_argument_hint_surrounding_quotes_stripped(self) -> None:
        # check_naming line 153: a quoted argument-hint has its matched quote
        # layer stripped before the bracket-shape match, so a valid quoted hint
        # passes without an L9 finding.
        self.command(
            "cmd",
            '---\ndescription: "x"\nargument-hint: "\'[a]\'"\n---\n# /cmd\nbody\n',
        )
        art = next(a for a in _model.discover(self.plugin_root) if a.kind == "command")
        # The frontmatter value is the inner "'[a]'" (outer YAML quotes consumed
        # by the parser); line 153 strips the remaining single-quote layer.
        self.assertEqual(art.frontmatter.get("argument-hint"), "'[a]'")
        self.assertEqual(
            [
                f
                for f in check_naming.check(self.plugin_root)
                if f.rule == "naming.argument-hint.shape"
            ],
            [],
        )


# --------------------------------------------------------------------------- #
# check_references
# --------------------------------------------------------------------------- #
class ReferencesCoverageTests(unittest.TestCase):
    def test_line_of_returns_none_when_absent(self) -> None:
        # check_references line 76: _line_of returns None when the needle is not
        # on any line.
        self.assertIsNone(check_references._line_of("a\nb\nc\n", "zzz"))
        self.assertEqual(check_references._line_of("a\nb\nc\n", "b"), 2)

    def test_existing_commands_empty_without_commands_dir(self) -> None:
        # check_references line 95: _existing_commands returns an empty set when
        # there is no commands/ directory.
        empty = pathlib.Path(tempfile.mkdtemp())
        try:
            self.assertEqual(check_references._existing_commands(empty), set())
        finally:
            shutil.rmtree(empty, ignore_errors=True)

    def test_link_path_none_for_non_md_and_absolute(self) -> None:
        # check_references line 171: _link_path returns None when the cleaned
        # target is not a .md link or is absolute.
        self.assertIsNone(check_references._link_path("notes.txt"))
        self.assertIsNone(check_references._link_path("/abs/path.md"))
        # Positive control: a relative .md link resolves to a cleaned path.
        self.assertEqual(check_references._link_path("doc.md"), "doc.md")


# --------------------------------------------------------------------------- #
# check_escalation
# --------------------------------------------------------------------------- #
class EscalationCoverageTests(unittest.TestCase):
    def test_block_open_at_eof_is_appended(self) -> None:
        # check_escalation line 129: a banner block that runs to end-of-body with
        # no closing/next banner is still appended by the trailing flush.
        body = (
            "=== SDLC ESCALATION ===\n"
            "stage: review\n"
            "iteration: 1/5\n"
            "exit_condition: x\n"
        )
        blocks = check_escalation._escalation_blocks(body)
        self.assertEqual(len(blocks), 1)
        _lineno, banner_text, fields = blocks[0]
        self.assertEqual(banner_text, "=== SDLC ESCALATION ===")
        self.assertIn("stage", fields)


# --------------------------------------------------------------------------- #
# lint_all
# --------------------------------------------------------------------------- #
class LintAllCoverageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _valid_plugin(self) -> pathlib.Path:
        pr = self.tmp / "plugins" / "demo"
        (pr / ".claude-plugin").mkdir(parents=True)
        (pr / ".claude-plugin" / "plugin.json").write_text(
            json.dumps({"name": "demo", "version": "1"})
        )
        (pr / "commands").mkdir()
        _write(
            pr / "commands" / "sdlc-foo.md",
            '---\ndescription: "x"\nargument-hint: "[a]"\n---\n# /sdlc-foo\n',
        )
        return pr

    def test_repo_root_default_is_three_levels_up(self) -> None:
        # lint_all line 47: _repo_root() with no override resolves to the repo
        # root (lint dir's great-grandparent).
        self.assertEqual(lint_all._repo_root(), lint_all.HERE.parent.parent.parent)

    def test_json_output_branch(self) -> None:
        # lint_all line 122: the --json branch prints machine-readable output.
        pr = self._valid_plugin()
        out = io.StringIO()
        with (
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            rc = lint_all.main([str(pr), "--json", "--repo-root", str(self.tmp)])
        self.assertIn(rc, (0, 1))
        # Output must be valid JSON (a list of finding dicts).
        parsed = json.loads(out.getvalue())
        self.assertIsInstance(parsed, list)

    def test_discover_skips_module_without_check(self) -> None:
        # lint_all branch 40->38: a check_*.py module lacking a `check` attr is
        # skipped (loop continues) while a sibling with `check` is collected. We
        # point HERE at a temp dir holding both, on sys.path, and call the real
        # _discover_check_modules.
        lint_dir = self.tmp / "lintmods"
        lint_dir.mkdir(parents=True)
        (lint_dir / "check_has.py").write_text("def check(root):\n    return []\n")
        (lint_dir / "check_missing.py").write_text("X = 1\n")
        orig_here = lint_all.HERE
        sys.path.insert(0, str(lint_dir))
        lint_all.HERE = lint_dir
        try:
            mods = lint_all._discover_check_modules()
        finally:
            lint_all.HERE = orig_here
            sys.path.remove(str(lint_dir))
            sys.modules.pop("check_has", None)
            sys.modules.pop("check_missing", None)
            importlib.invalidate_caches()
        names = {m.__name__ for m in mods}
        self.assertIn("check_has", names)
        self.assertNotIn("check_missing", names)

    def test_run_without_check_manifest_skips_marketplace(self) -> None:
        # lint_all branch 73->86: when check_manifest is not in sys.modules,
        # run() skips the marketplace block entirely rather than crashing. We
        # stub _discover_check_modules to [] so run() does NOT re-import every
        # check_*.py (which would re-populate sys.modules["check_manifest"] and
        # defeat the None lookup), then pop the module for the duration.
        orig_discover = lint_all._discover_check_modules
        lint_all._discover_check_modules = lambda: []
        saved = sys.modules.pop("check_manifest", None)
        try:
            findings = lint_all.run([self.tmp], self.tmp)
        finally:
            lint_all._discover_check_modules = orig_discover
            if saved is not None:
                sys.modules["check_manifest"] = saved
        # With no check modules and no marketplace check, run() yields nothing.
        self.assertEqual(findings, [])

    def test_run_surfaces_marketplace_crash_as_finding(self) -> None:
        # lint_all lines 76-77: when check_marketplace raises, run() converts it
        # into an ERR finding instead of propagating. We inject a stub module
        # under the name run() looks up (sys.modules["check_manifest"]).
        class _BoomManifest:
            __name__ = "check_manifest"

            @staticmethod
            def check_marketplace(_repo_root):
                raise RuntimeError("market-boom")

        saved = sys.modules.get("check_manifest")
        sys.modules["check_manifest"] = _BoomManifest
        try:
            findings = lint_all.run([self.tmp], self.tmp)
        finally:
            if saved is not None:
                sys.modules["check_manifest"] = saved
            else:  # pragma: no cover - check_manifest is always imported here
                sys.modules.pop("check_manifest", None)
        err = [
            f for f in findings if f.rule == "check_manifest.check_marketplace.crashed"
        ]
        self.assertTrue(err, msg=[f.render() for f in findings])
        self.assertEqual(err[0].severity, "S2")
        self.assertIn("market-boom", err[0].message)


if __name__ == "__main__":
    unittest.main()
