"""Self-tests for the frontmatter linter (FM-1..FM-5).

Synthetic plugin trees are built at runtime under a tempdir; no fixture files
are committed. Each FM case has a positive (PASS), negative (FAIL with an
expected message), and edge test.
"""

import pathlib
import sys
import shutil
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_frontmatter  # noqa: E402


class FrontmatterTestBase(unittest.TestCase):
    """Builds a throwaway ``plugins/<name>/`` tree per test."""

    def setUp(self) -> None:
        # A realistic layout: <repo>/plugins/<name> so Artifact.rel resolves.
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.plugin_root = self.tmp / "plugins" / "demo"
        (self.plugin_root / "commands").mkdir(parents=True)
        (self.plugin_root / "agents").mkdir(parents=True)
        (self.plugin_root / "skills").mkdir(parents=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    # --- helpers -----------------------------------------------------------
    def write_command(self, name: str, text: str) -> None:
        (self.plugin_root / "commands" / f"{name}.md").write_text(text, encoding="utf-8")

    def write_agent(self, name: str, text: str) -> None:
        (self.plugin_root / "agents" / f"{name}.md").write_text(text, encoding="utf-8")

    def write_skill(self, name: str, text: str) -> None:
        d = self.plugin_root / "skills" / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "SKILL.md").write_text(text, encoding="utf-8")

    def write_metaguide(self, name: str, text: str) -> None:
        (self.plugin_root / "skills" / f"{name}.md").write_text(text, encoding="utf-8")

    def run_check(self):
        return check_frontmatter.check(self.plugin_root)

    def assert_no_findings(self, findings):
        self.assertEqual(
            findings, [], msg=f"expected no findings, got: {[f.render() for f in findings]}"
        )

    def assert_finding(self, findings, check, rule, msg_substr):
        matches = [
            f
            for f in findings
            if f.check == check and f.rule == rule and msg_substr.lower() in f.message.lower()
        ]
        self.assertTrue(
            matches,
            msg=(
                f"no finding with check={check} rule={rule} msg~={msg_substr!r}; "
                f"got: {[f.render() for f in findings]}"
            ),
        )


# --- FM-1 (L1) command description + argument-hint -------------------------
class TestFM1(FrontmatterTestBase):
    def test_positive(self):
        self.write_command("ok", '---\ndescription: "Run X"\nargument-hint: "[pr-number]"\n---\nbody\n')
        self.assert_no_findings(self.run_check())

    def test_negative_missing_argument_hint(self):
        self.write_command("nohint", '---\ndescription: "Run X"\n---\nbody\n')
        self.assert_finding(
            self.run_check(), "L1", "frontmatter.command.missing-key", "argument-hint"
        )

    def test_negative_empty_description(self):
        self.write_command("empty", '---\ndescription: ""\nargument-hint: "[x]"\n---\nbody\n')
        self.assert_finding(
            self.run_check(), "L1", "frontmatter.command.missing-key", "description"
        )

    def test_edge_allowed_tools_present_still_pass(self):
        self.write_command(
            "edge",
            '---\ndescription: "Run X"\nargument-hint: "[x]"\nallowed-tools: ["Bash","Read"]\n---\nbody\n',
        )
        self.assert_no_findings(self.run_check())


# --- FM-2 (L2) command allowed-tools shape ---------------------------------
class TestFM2(FrontmatterTestBase):
    def test_positive(self):
        self.write_command(
            "ok",
            '---\ndescription: "Run X"\nargument-hint: "[x]"\nallowed-tools: ["Bash","Read","Grep"]\n---\nbody\n',
        )
        self.assert_no_findings(self.run_check())

    def test_negative_bare_string_not_array(self):
        # A bare comma string parses as str under YAML -> not a list -> fail.
        self.write_command(
            "bare",
            '---\ndescription: "Run X"\nargument-hint: "[x]"\nallowed-tools: Bash, Read\n---\nbody\n',
        )
        self.assert_finding(
            self.run_check(), "L2", "frontmatter.command.allowed-tools", "must be a JSON array"
        )

    def test_negative_report_only_with_write(self):
        self.write_command(
            "ro",
            '---\ndescription: "Run X"\nargument-hint: "[x]"\nallowed-tools: ["Bash","Write"]\n---\n'
            "This command is report only and never fix anything.\n",
        )
        self.assert_finding(
            self.run_check(), "L2", "frontmatter.command.allowed-tools", "report-only"
        )

    def test_edge_no_allowed_tools_pass(self):
        self.write_command("noat", '---\ndescription: "Run X"\nargument-hint: "[x]"\n---\nbody\n')
        self.assert_no_findings(self.run_check())

    # --- regression (7a): unknown-tool branch of L2 ------------------------
    def test_negative_unknown_tool_flagged(self):
        # 7a: an allowed-tools array carrying a tool not in KNOWN_TOOLS
        # ("FooBar") -> L2 frontmatter.command.allowed-tools "unknown tool".
        self.write_command(
            "unknown",
            '---\ndescription: "Run X"\nargument-hint: "[x]"\nallowed-tools: ["Bash","FooBar"]\n---\nbody\n',
        )
        self.assert_finding(
            self.run_check(), "L2", "frontmatter.command.allowed-tools", "unknown tool"
        )


# --- FM-3 (L3) agent four keys ---------------------------------------------
class TestFM3(FrontmatterTestBase):
    def test_positive(self):
        self.write_agent(
            "ok",
            "---\nname: ok\ndescription: An agent that does work.\ntools: [Read, Grep]\nmodel: sonnet\n---\nbody\n",
        )
        self.assert_no_findings(self.run_check())

    def test_negative_missing_model(self):
        self.write_agent(
            "nomodel",
            "---\nname: nomodel\ndescription: An agent.\ntools: [Read]\n---\nbody\n",
        )
        self.assert_finding(self.run_check(), "L3", "frontmatter.agent.missing-key", "model")

    def test_edge_tools_list_vs_comma_string_both_pass(self):
        self.write_agent(
            "listtools",
            "---\nname: listtools\ndescription: An agent.\ntools: [Read, Grep]\nmodel: opus\n---\nbody\n",
        )
        self.write_agent(
            "strtools",
            "---\nname: strtools\ndescription: An agent.\ntools: Read, Grep\nmodel: opus\n---\nbody\n",
        )
        self.assert_no_findings(self.run_check())

    # --- regression: malformed tools list must still be flagged (Fix 2) ----
    def test_negative_tools_list_of_ints_flagged(self):
        # Fix 2: a list with no non-empty string (e.g. [123]) is NOT a present
        # tools list; the old `or item not in (None, "")` loophole accepted it.
        self.write_agent(
            "intlist",
            "---\nname: intlist\ndescription: An agent.\ntools: [123]\nmodel: opus\n---\nbody\n",
        )
        self.assert_finding(self.run_check(), "L3", "frontmatter.agent.missing-key", "tools")

    def test_negative_tools_list_of_null_flagged(self):
        # Fix 2: [null] yields [None] -> no non-empty string -> L3 fires.
        self.write_agent(
            "nulllist",
            "---\nname: nulllist\ndescription: An agent.\ntools: [null]\nmodel: opus\n---\nbody\n",
        )
        self.assert_finding(self.run_check(), "L3", "frontmatter.agent.missing-key", "tools")

    def test_positive_tools_single_item_list_passes(self):
        # Fix 2 control: a list with one real tool name still passes.
        self.write_agent(
            "onelist",
            "---\nname: onelist\ndescription: An agent.\ntools: [Read]\nmodel: opus\n---\nbody\n",
        )
        self.assert_no_findings(self.run_check())

    def test_positive_tools_comma_string_passes(self):
        # Fix 2 control: a comma-string still passes (string branch unaffected).
        self.write_agent(
            "csv",
            "---\nname: csv\ndescription: An agent.\ntools: Read, Bash\nmodel: opus\n---\nbody\n",
        )
        self.assert_no_findings(self.run_check())


# --- FM-4 (L4) skill two keys, no tools/model ------------------------------
class TestFM4(FrontmatterTestBase):
    def test_positive(self):
        self.write_skill(
            "myskill", "---\nname: myskill\ndescription: A skill that helps.\n---\nbody\n"
        )
        self.assert_no_findings(self.run_check())

    def test_negative_declares_model(self):
        self.write_skill(
            "badskill",
            "---\nname: badskill\ndescription: A skill.\nmodel: sonnet\n---\nbody\n",
        )
        self.assert_finding(self.run_check(), "L4", "frontmatter.skill.shape", "must not declare model")

    def test_edge_when_to_use_pass(self):
        self.write_skill(
            "wtu",
            "---\nname: wtu\ndescription: A skill.\nwhen_to_use: Use when doing X.\n---\nbody\n",
        )
        self.assert_no_findings(self.run_check())


# --- FM-5 (L5) meta-guide no frontmatter -----------------------------------
class TestFM5(FrontmatterTestBase):
    def test_positive(self):
        self.write_metaguide("AI-AGENT-GUIDE", "# Heading\n\nGuide body.\n")
        self.assert_no_findings(self.run_check())

    def test_negative_has_frontmatter(self):
        self.write_metaguide("FOO", "---\nname: foo\n---\n# Heading\n")
        self.assert_finding(
            self.run_check(), "L5", "frontmatter.metaguide.no-frontmatter", "ADR-11"
        )

    def test_edge_subdir_skill_not_metaguide(self):
        # SKILL.md inside a subdir is a skill, not a meta-guide: frontmatter OK.
        self.write_skill(
            "realskill", "---\nname: realskill\ndescription: A real skill.\n---\nbody\n"
        )
        self.assert_no_findings(self.run_check())


# --- parse-error surfacing -------------------------------------------------
class TestParseError(FrontmatterTestBase):
    def test_malformed_frontmatter_surfaced(self):
        # Unterminated frontmatter block -> _model reports an error.
        self.write_command("broken", "---\ndescription: oops\n")
        self.assert_finding(self.run_check(), "L0", "frontmatter.parse-error", "failed to parse")

    # --- regression (7b): L0 parse-error variants --------------------------
    def test_invalid_yaml_in_block_surfaced(self):
        # 7b(i): a terminated block with invalid YAML (unbalanced bracket) ->
        # L0 frontmatter.parse-error.
        self.write_command("badyaml", "---\nkey: [unbalanced\n---\nbody\n")
        self.assert_finding(self.run_check(), "L0", "frontmatter.parse-error", "failed to parse")

    def test_frontmatter_not_a_mapping_surfaced(self):
        # 7b(ii): frontmatter that parses to a YAML sequence (not a mapping) ->
        # L0 frontmatter.parse-error.
        self.write_command("seqfm", "---\n- a\n- b\n---\nbody\n")
        self.assert_finding(self.run_check(), "L0", "frontmatter.parse-error", "failed to parse")


# --- L33 QA artifacts must be read-only (Fix 6) ----------------------------
class TestQANoMutatingTools(FrontmatterTestBase):
    def test_qa_agent_with_write_flagged(self):
        # Fix 6: a qa-named agent whose tools include Write -> L33.
        self.write_agent(
            "qa-manual-tester",
            "---\nname: qa-manual-tester\ndescription: QA agent.\n"
            "tools: Bash, Read, Write\nmodel: sonnet\n---\nbody\n",
        )
        self.assert_finding(
            self.run_check(), "L33", "frontmatter.qa.no-mutating-tools", "Write"
        )

    def test_qa_agent_read_only_passes(self):
        # Control: a qa agent with tools Bash, Read has no L33 finding.
        self.write_agent(
            "qa-manual-tester",
            "---\nname: qa-manual-tester\ndescription: QA agent.\n"
            "tools: Bash, Read\nmodel: sonnet\n---\nbody\n",
        )
        l33 = [f for f in self.run_check() if f.check == "L33"]
        self.assertEqual(l33, [])

    def test_qa_command_read_only_passes(self):
        # Fix 6: a qa command with allowed-tools ["Bash","Read"] -> no L33.
        self.write_command(
            "sdlc-qa",
            '---\ndescription: "QA"\nargument-hint: "[x]"\n'
            'allowed-tools: ["Bash","Read"]\n---\nbody\n',
        )
        l33 = [f for f in self.run_check() if f.check == "L33"]
        self.assertEqual(l33, [])

    def test_qa_command_with_edit_flagged(self):
        # Fix 6: a qa command whose allowed-tools include Edit -> L33.
        self.write_command(
            "sdlc-qa",
            '---\ndescription: "QA"\nargument-hint: "[x]"\n'
            'allowed-tools: ["Bash","Edit"]\n---\nbody\n',
        )
        self.assert_finding(
            self.run_check(), "L33", "frontmatter.qa.no-mutating-tools", "Edit"
        )

    def test_non_qa_command_with_write_not_flagged_by_l33(self):
        # Fix 6: a non-qa command with Write is NOT an L33 concern (the name
        # gate excludes it; report-only L2 may still apply to other commands).
        self.write_command(
            "sdlc-implement",
            '---\ndescription: "Implement"\nargument-hint: "[x]"\n'
            'allowed-tools: ["Bash","Write"]\n---\nbody\n',
        )
        l33 = [f for f in self.run_check() if f.check == "L33"]
        self.assertEqual(l33, [])

    def test_qa_name_token_not_substring_match(self):
        # Fix 6: "qa" must be a dash-delimited token; "squash" is not a qa name.
        self.write_command(
            "squash-helper",
            '---\ndescription: "Squash"\nargument-hint: "[x]"\n'
            'allowed-tools: ["Bash","Write"]\n---\nbody\n',
        )
        l33 = [f for f in self.run_check() if f.check == "L33"]
        self.assertEqual(l33, [])


if __name__ == "__main__":
    unittest.main()
