"""Self-tests for check_structure (L15-L18).

Builds synthetic plugin trees in a temp dir (no committed fixtures) and
also verifies the real shipped plugin is clean for the structure checks.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_structure  # noqa: E402
import _model  # noqa: E402

REPO_ROOT = HERE.parent.parent.parent
REAL_PLUGIN = REPO_ROOT / "plugins" / "php-backend-sdlc"

# --- spine bodies for synthetic artifacts ----------------------------------

COMMAND_SPINE_H2 = (
    "Inputs",
    "Procedure",
    "Loop & exit condition",
    "Iteration guard",
    "Failure escalation",
)
AGENT_SPINE_H2 = (
    "Profile keys consumed",
    "Role",
    "Inputs",
    "Outputs",
    "Allowed actions",
    "Degrade paths",
    "Iteration discipline",
    "Smoke prompt",
)


def _h2_body(h1, sections):
    out = [f"# {h1}", ""]
    for s in sections:
        out.append(f"## {s}")
        out.append("")
        out.append("body text")
        out.append("")
    return "\n".join(out)


def _command_md(sections=COMMAND_SPINE_H2):
    fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n\n'
    return fm + _h2_body("/cmd", sections)


def _agent_md(sections=AGENT_SPINE_H2):
    fm = "---\nname: a\ndescription: d\ntools: Read\nmodel: opus\n---\n\n"
    return fm + _h2_body("a", sections)


def _skill_md(sections, body_extra=""):
    fm = "---\nname: s\ndescription: d\n---\n\n"
    return fm + _h2_body("Skill", sections) + body_extra


class StructureCase(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        # Make the temp tree look like <repo>/plugins/<name> so .rel works.
        self.root = self.tmp / "plugins" / "p"
        (self.root / "commands").mkdir(parents=True)
        (self.root / "agents").mkdir(parents=True)
        (self.root / "skills").mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write_command(self, name, text):
        (self.root / "commands" / f"{name}.md").write_text(text, encoding="utf-8")

    def _write_agent(self, name, text):
        (self.root / "agents" / f"{name}.md").write_text(text, encoding="utf-8")

    def _write_skill(self, name, text):
        d = self.root / "skills" / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "SKILL.md").write_text(text, encoding="utf-8")

    def _write_metaguide(self, name, text):
        (self.root / "skills" / f"{name}.md").write_text(text, encoding="utf-8")

    def _findings(self, check_id=None):
        fs = check_structure.check(self.root)
        if check_id is not None:
            fs = [f for f in fs if f.check == check_id]
        return fs

    # --- ST-1 command 5-spine ---------------------------------------------

    def test_st1_command_full_spine_passes(self):
        self._write_command("c", _command_md())
        self.assertEqual(self._findings("L15"), [])

    def test_st1_command_missing_loop_section_fails(self):
        sections = tuple(s for s in COMMAND_SPINE_H2 if s != "Loop & exit condition")
        self._write_command("c", _command_md(sections))
        fs = self._findings("L15")
        self.assertEqual(len(fs), 1)
        self.assertIn("Loop & exit condition", fs[0].message)
        self.assertEqual(fs[0].rule, "structure.command.spine")
        self.assertEqual(fs[0].severity, "S2")

    def test_st1_command_extra_h2_passes(self):
        sections = COMMAND_SPINE_H2 + ("Report template", "Notes")
        self._write_command("c", _command_md(sections))
        self.assertEqual(self._findings("L15"), [])

    # --- ST-2 agent 8-spine -----------------------------------------------

    def test_st2_agent_full_spine_passes(self):
        self._write_agent("a", _agent_md())
        self.assertEqual(self._findings("L16"), [])

    def test_st2_agent_missing_smoke_prompt_fails(self):
        sections = tuple(s for s in AGENT_SPINE_H2 if s != "Smoke prompt")
        self._write_agent("a", _agent_md(sections))
        fs = self._findings("L16")
        self.assertEqual(len(fs), 1)
        self.assertIn("Smoke prompt", fs[0].message)
        self.assertEqual(fs[0].rule, "structure.agent.spine")

    def test_st2_agent_role_first_order_passes(self):
        # fr-nfr-reviewer ships Role first; presence not order.
        reordered = ("Role",) + tuple(s for s in AGENT_SPINE_H2 if s != "Role")
        self._write_agent("a", _agent_md(reordered))
        self.assertEqual(self._findings("L16"), [])

    # --- ST-3 skill first H2 ----------------------------------------------

    def test_st3_skill_profile_keys_first_passes(self):
        self._write_skill("s", _skill_md(("Profile keys consumed", "Overview")))
        self.assertEqual(self._findings("L17"), [])

    def test_st3_skill_overview_first_fails(self):
        self._write_skill("s", _skill_md(("Overview", "Profile keys consumed")))
        fs = self._findings("L17")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "structure.skill.first-h2")
        self.assertIn("Overview", fs[0].message)

    def test_st3_metaguide_exempt(self):
        # Meta-guide (loose skills/*.md) starting with Overview must not be checked.
        self._write_metaguide("GUIDE", "# Guide\n\n## Overview\n\nstuff\n")
        self.assertEqual(self._findings("L17"), [])

    # --- ST-4 gated skill SKIPPED token -----------------------------------

    def test_st4_gated_with_skipped_token_passes(self):
        body = "\n\nWhen disabled emit `SKIPPED: capabilities.x is false`.\n"
        self._write_skill(
            "s", _skill_md(("Profile keys consumed", "Capability gate"), body)
        )
        self.assertEqual(self._findings("L18"), [])

    def test_st4_gated_without_skip_token_fails(self):
        # Gate section but no SKIPPED token and no skip-degrade prose at all.
        body = "\n\nThis section gates on a capability and does other things.\n"
        self._write_skill(
            "s", _skill_md(("Profile keys consumed", "Capability gate"), body)
        )
        fs = self._findings("L18")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "structure.skill.gate-skipped-token")
        self.assertEqual(fs[0].severity, "S2")

    def test_st4_non_gated_skill_not_checked(self):
        # No gate H2 -> L18 does not apply even without a SKIPPED token.
        self._write_skill("s", _skill_md(("Profile keys consumed", "Overview")))
        self.assertEqual(self._findings("L18"), [])

    # --- regression: Fix 6 — skip note scoped to the gate context ---------

    def test_st4_skip_word_in_other_section_does_not_satisfy(self):
        # Fix 6: a gate section with no skip path, but a stray "skipping ahead"
        # in an UNRELATED section, must still fail L18 (the loophole is closed).
        body = (
            "\n\nThis section gates on a capability.\n"
            "\n## Notes\n\nWe are skipping ahead to the summary here.\n"
        )
        self._write_skill(
            "s", _skill_md(("Profile keys consumed", "Capability gate"), body)
        )
        fs = self._findings("L18")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "structure.skill.gate-skipped-token")

    def test_st4_setext_gate_section_skip_token_bounded_passes(self):
        # Fix (cubic #3): a gate section whose H2 is a SETEXT heading must be
        # sliced correctly by _section_text so its in-section `SKIPPED:` token is
        # found. Under the old ATX-only slicing the setext gate section was never
        # located, _section_text returned None, and L18 fired a false positive.
        # No gate predicate appears anywhere, so passing proves the SETEXT
        # section body (not a predicate fallback) satisfied the rule.
        text = (
            "---\nname: s\n---\n\n"
            "Profile keys consumed\n"
            "---------------------\n\n"
            "Reads keys.\n\n"
            "Capability gate\n"
            "---------------\n\n"
            "When off emit `SKIPPED: feature disabled` and stop.\n\n"
            "Notes\n"
            "-----\n\n"
            "Unrelated trailing prose.\n"
        )
        self._write_skill("s", text)
        self.assertEqual(self._findings("L18"), [])

    def test_st4_setext_gate_skip_token_in_other_section_fails(self):
        # Fix (cubic #3) guard: the setext gate section itself has NO skip path;
        # a stray `SKIPPED:` lives only in a LATER setext section. Correct
        # bounding must NOT let that later section satisfy the gate, so L18 fires.
        text = (
            "---\nname: s\n---\n\n"
            "Profile keys consumed\n"
            "---------------------\n\n"
            "Reads keys.\n\n"
            "Capability gate\n"
            "---------------\n\n"
            "This section gates on a capability and does nothing else.\n\n"
            "Notes\n"
            "-----\n\n"
            "Elsewhere we emit `SKIPPED: unrelated` for another reason.\n"
        )
        self._write_skill("s", text)
        fs = self._findings("L18")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "structure.skill.gate-skipped-token")

    def test_st4_skip_predicate_outside_gate_h2_passes(self):
        # Fix 6: a genuine "skip when <predicate> is false" note, tied to a gate
        # predicate but living outside a literally gate-named H2, still passes
        # (mirrors the shipped bmad-fr-nfr-review-gate skill).
        body = (
            "\n\nResolve the gate runner from the make map.\n"
            "\n## Matrix\n\nRun load tests behind `make.load_tests` when "
            "`capabilities.load_testing` is true (skip with a note when false).\n"
        )
        self._write_skill(
            "s", _skill_md(("Profile keys consumed", "Gate runner resolution"), body)
        )
        self.assertEqual(self._findings("L18"), [])

    # --- regression: Fix 3 — ATX trailing hashes + setext headings --------

    def test_st1_command_atx_trailing_hashes_matched(self):
        # Fix 3a: "## Inputs ##" must be read as the "Inputs" spine section, not
        # "Inputs ##", so a full spine with closed ATX headings stays clean.
        fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n\n'
        lines = ["# /cmd", ""]
        for s in COMMAND_SPINE_H2:
            lines += [f"## {s} ##", "", "body", ""]
        self._write_command("c", fm + "\n".join(lines))
        self.assertEqual(self._findings("L15"), [])

    def test_st1_command_setext_h2_spine_matched(self):
        # Fix 3b: setext H2 underlines (Title\n-----) count as spine sections.
        fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n\n'
        lines = ["# /cmd", ""]
        for s in COMMAND_SPINE_H2:
            lines += [s, "-----", "", "body", ""]
        self._write_command("c", fm + "\n".join(lines))
        self.assertEqual(self._findings("L15"), [])

    def test_setext_h1_detected_by_model(self):
        # Fix 3b: a setext H1 (Title\n=====) is extracted as h1.
        h1, h2 = _model.extract_headings("My Title\n=====\n\nbody\n")
        self.assertEqual(h1, "My Title")
        self.assertEqual(h2, [])

    def test_setext_does_not_misfire_on_table_separator(self):
        # Fix 3b guard: a markdown table separator row is not a setext H2.
        body = "| col |\n| --- |\n| val |\n"
        _h1, h2 = _model.extract_headings(body)
        self.assertEqual(h2, [])

    # --- regression: Fix 2 — fence run length tracked ---------------------

    def test_inner_short_fence_does_not_close_outer(self):
        # Fix 2: a 4-backtick block containing an inner 3-backtick line must NOT
        # close early; "## Leak" inside the block must not surface as an H2.
        body = (
            "## Real\n\n"
            "````markdown\n"
            "```\n"
            "## Leak\n"
            "```\n"
            "````\n\n"
            "## After\n"
        )
        _h1, h2 = _model.extract_headings(body)
        self.assertIn("Real", h2)
        self.assertIn("After", h2)
        self.assertNotIn("Leak", h2)

    def test_info_string_fence_does_not_close_open_fence(self):
        # Fix (cubic #1): a "```python" line inside a "```" block is an OPENING
        # fence (it carries an info string), so per CommonMark it must NOT close
        # the open block. "## Leak" between the two same-length fence lines stays
        # fenced and never surfaces as an H2; "After" (the genuine bare close)
        # ends the block.
        body = (
            "## Real\n\n"
            "```\n"
            "```python\n"
            "## Leak\n"
            "```\n\n"
            "## After\n"
        )
        _h1, h2 = _model.extract_headings(body)
        self.assertIn("Real", h2)
        self.assertIn("After", h2)
        self.assertNotIn("Leak", h2)

    def test_bare_close_fence_with_trailing_whitespace_closes(self):
        # Fix (cubic #1) control: a closing fence MAY carry trailing whitespace
        # only ("```   "), so the block still closes and "After" is an H2.
        body = "## Real\n\n```\nx = 1\n```   \n\n## After\n"
        _h1, h2 = _model.extract_headings(body)
        self.assertIn("Real", h2)
        self.assertIn("After", h2)

    # --- regression: Fix 1 — BOM strip + non-UTF-8 stub -------------------

    def test_st1_command_with_bom_full_spine_passes(self):
        # Fix 1b: a UTF-8 BOM must be stripped so frontmatter parses and the
        # spine is read normally (no false missing-section / missing-key).
        text = "﻿" + _command_md()
        self._write_command("c", text)
        self.assertEqual(self._findings("L15"), [])

    def test_non_utf8_file_yields_stub_without_crash(self):
        # Fix 1a: a non-UTF-8 command file must not crash discover(); it becomes
        # a stub with a frontmatter_error instead.
        p = self.root / "commands" / "bad.md"
        p.write_bytes(b"\xff\xfe---\ndescription: x\n---\n# bad\n")
        arts = _model.discover(self.root)
        bad = [a for a in arts if a.path == p]
        self.assertEqual(len(bad), 1)
        self.assertFalse(bad[0].has_frontmatter)
        self.assertIsNotNone(bad[0].frontmatter_error)
        self.assertIn("UTF-8", bad[0].frontmatter_error)

    # --- real shipped plugin is clean for L15-L18 -------------------------

    def test_real_plugin_clean_for_structure(self):
        self.assertTrue(REAL_PLUGIN.is_dir(), f"missing real plugin at {REAL_PLUGIN}")
        fs = check_structure.check(REAL_PLUGIN)
        structure_fs = [f for f in fs if f.check in ("L15", "L16", "L17", "L18")]
        self.assertEqual(
            structure_fs,
            [],
            "shipped plugin must be clean for L15-L18; got: "
            + "; ".join(f.render() for f in structure_fs),
        )


if __name__ == "__main__":
    unittest.main()
