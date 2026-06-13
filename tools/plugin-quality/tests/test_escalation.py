"""Self-tests for check_escalation (L26-L27, cases ES-1/ES-2).

Builds synthetic command/agent .md in a temp dir (no committed fixtures) and
verifies the real shipped plugin is clean for the escalation checks.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_escalation  # noqa: E402

REPO_ROOT = HERE.parent.parent.parent
REAL_PLUGIN = REPO_ROOT / "plugins" / "php-backend-sdlc"

# --- canonical escalation block (all seven fields) -------------------------

FULL_BLOCK = """```text
=== SDLC ESCALATION ===
stage: review            iteration: <n>/5
exit_condition: zero new findings
status: NOT MET
blocking_finding: <one line>
iteration_log: <one line per iteration>
recommended_action: <human next step>
=== END ===
```"""

# Same block with recommended_action removed (ES-2 negative).
BLOCK_NO_RECOMMENDED = "\n".join(
    ln for ln in FULL_BLOCK.splitlines() if not ln.startswith("recommended_action:")
)

# Orchestrator banner — exempt from the seven-field check (ES-2 edge).
RUN_REPORT_BLOCK = """```text
=== SDLC RUN REPORT ===
task: <task>
result: SUCCESS | ESCALATED
=== END ===
```"""


def _command_md(guard_body, escalation_block):
    fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n'
    return (
        f"{fm}\n# /cmd\n\n"
        f"## Iteration guard\n\n{guard_body}\n\n"
        f"## Failure escalation\n\n{escalation_block}\n"
    )


def _agent_md(guard_body, escalation_block):
    fm = "---\nname: a\ndescription: d\ntools: Read\nmodel: opus\n---\n"
    return (
        f"{fm}\n# a\n\n"
        f"## Iteration discipline\n\n{guard_body}\n\n"
        f"## Smoke prompt\n\n{escalation_block}\n"
    )


class EscalationCase(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.root = self.tmp / "plugins" / "p"
        (self.root / "commands").mkdir(parents=True)
        (self.root / "agents").mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write_command(self, name, text):
        (self.root / "commands" / f"{name}.md").write_text(text, encoding="utf-8")

    def _write_agent(self, name, text):
        (self.root / "agents" / f"{name}.md").write_text(text, encoding="utf-8")

    def _findings(self, check_id=None):
        fs = check_escalation.check(self.root)
        if check_id is not None:
            fs = [f for f in fs if f.check == check_id]
        return fs

    # --- ES-1 (L26) iteration bound ---------------------------------------

    def test_es1_max_iterations_5_passes(self):
        self._write_command("c", _command_md("`MAX_ITERATIONS=5`.", FULL_BLOCK))
        self.assertEqual(self._findings("L26"), [])

    def test_es1_max_iterations_3_fails(self):
        # The cap must be 5; MAX_ITERATIONS=3 is the wrong bound -> L26 fires.
        self._write_command("c", _command_md("`MAX_ITERATIONS=3`.", FULL_BLOCK))
        fs = self._findings("L26")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "escalation.max-iterations")
        self.assertEqual(fs[0].severity, "S2")
        self.assertIn("Iteration guard", fs[0].message)

    def test_es1_no_bound_stated_fails(self):
        # Guard section with no number/counter at all -> L26 fires.
        body = "Keep an explicit counter and restate it every turn."
        self._write_command("c", _command_md(body, FULL_BLOCK))
        fs = self._findings("L26")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "escalation.max-iterations")
        self.assertEqual(fs[0].severity, "S2")
        self.assertIn("Iteration guard", fs[0].message)

    def test_es1_prose_max_5_iterations_passes(self):
        body = "Own iteration counter, **max 5 iterations**, never reset."
        self._write_agent("a", _agent_md(body, FULL_BLOCK))
        self.assertEqual(self._findings("L26"), [])

    def test_es1_counter_slash_5_passes(self):
        body = "Restate the counter in every report header (`iteration <n>/5`)."
        self._write_agent("a", _agent_md(body, FULL_BLOCK))
        self.assertEqual(self._findings("L26"), [])

    # --- ES-2 (L27) escalation block fields -------------------------------

    def test_es2_full_block_passes(self):
        self._write_command("c", _command_md("`MAX_ITERATIONS=5`.", FULL_BLOCK))
        self.assertEqual(self._findings("L27"), [])

    def test_es2_missing_recommended_action_fails(self):
        self._write_command(
            "c", _command_md("`MAX_ITERATIONS=5`.", BLOCK_NO_RECOMMENDED)
        )
        fs = self._findings("L27")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "escalation.block-fields")
        self.assertEqual(fs[0].severity, "S2")
        self.assertIn("recommended_action", fs[0].message)
        self.assertIsNotNone(fs[0].line)

    def test_es2_each_missing_field_fires_one_l27(self):
        # 7c: for EACH of the 7 canonical fields, build a block missing exactly
        # that field (one field per line, so the others stay intact) and assert
        # exactly one L27 finding naming it.
        for missing in check_escalation.REQUIRED_FIELDS:
            with self.subTest(field=missing):
                field_lines = [
                    f"{field}: <value>"
                    for field in check_escalation.REQUIRED_FIELDS
                    if field != missing
                ]
                block = "\n".join(
                    ["```text", "=== SDLC ESCALATION ==="]
                    + field_lines
                    + ["=== END ===", "```"]
                )
                self._write_command(
                    "c", _command_md("`MAX_ITERATIONS=5`.", block)
                )
                fs = self._findings("L27")
                self.assertEqual(
                    len(fs), 1, f"expected 1 L27 for missing {missing}, got {len(fs)}"
                )
                self.assertEqual(fs[0].rule, "escalation.block-fields")
                self.assertEqual(fs[0].severity, "S2")
                self.assertIn(missing, fs[0].message)

    def test_es2_run_report_banner_exempt(self):
        # RUN REPORT block lacks the seven fields but is exempt; the command
        # still needs an iteration bound for L26 to stay clean.
        self._write_command("c", _command_md("`MAX_ITERATIONS=5`.", RUN_REPORT_BLOCK))
        self.assertEqual(self._findings("L27"), [])

    def test_es2_two_fields_one_line_counted(self):
        # "stage: x   iteration: y" on one line satisfies both fields.
        self._write_command("c", _command_md("`MAX_ITERATIONS=5`.", FULL_BLOCK))
        fs = [
            f
            for f in self._findings("L27")
            if "stage" in f.message or "iteration" in f.message
        ]
        self.assertEqual(fs, [])

    # --- regression: fields rendered as a markdown bullet list ------------

    def test_es2_fields_as_bullet_list_counted(self):
        # Fix 4a: "- stage: 6" bullet-list fields must still be recognized, not
        # produce 7 false-positive missing-field findings.
        block = (
            "```text\n"
            "=== SDLC ESCALATION ===\n"
            "- stage: review\n"
            "- iteration: <n>/5\n"
            "- exit_condition: zero new findings\n"
            "- status: NOT MET\n"
            "- blocking_finding: <one line>\n"
            "- iteration_log: <one line>\n"
            "- recommended_action: <human next step>\n"
            "=== END ===\n"
            "```"
        )
        self._write_command("c", _command_md("`MAX_ITERATIONS=5`.", block))
        self.assertEqual(self._findings("L27"), [])

    def test_es2_two_bullet_fields_one_line_counted(self):
        # Fix 4a: a bullet line with two fields counts both via the findall path.
        block = (
            "```text\n"
            "=== SDLC ESCALATION ===\n"
            "- stage: review            iteration: <n>/5\n"
            "- exit_condition: zero new findings\n"
            "- status: NOT MET\n"
            "- blocking_finding: <one line>\n"
            "- iteration_log: <one line>\n"
            "- recommended_action: <human next step>\n"
            "=== END ===\n"
            "```"
        )
        self._write_command("c", _command_md("`MAX_ITERATIONS=5`.", block))
        self.assertEqual(self._findings("L27"), [])

    # --- regression: tightened iteration-counter bound (Fix 4b) -----------

    def test_es1_wrong_cap_with_stray_slash5_fails(self):
        # Fix 4b: MAX_ITERATIONS=3 with a stray "4/5" not in iteration context
        # must NOT satisfy the bound — the cap is wrong, so L26 fires. The
        # "ITERATIONS" inside MAX_ITERATIONS=3 must not count as counter context.
        body = "`MAX_ITERATIONS=3`. Coverage 4/5 done."
        self._write_command("c", _command_md(body, FULL_BLOCK))
        fs = self._findings("L26")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "escalation.max-iterations")

    def test_es1_counter_in_iteration_context_passes(self):
        # Fix 4b: "iteration 3/5" (the word within ~20 chars of /5) still passes.
        body = "Restate the header counter as iteration 3/5 each turn."
        self._write_agent("a", _agent_md(body, FULL_BLOCK))
        self.assertEqual(self._findings("L26"), [])

    # --- regression: ATX trailing-hash tolerance on the guard H2 (Fix 4c) -

    def test_es1_guard_h2_with_trailing_hashes_matched(self):
        # Fix 4c: "## Iteration guard ##" must still be located as the guard
        # section; a missing bound inside it then fires L26 as normal.
        fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n'
        text = (
            f"{fm}\n# /cmd\n\n"
            "## Iteration guard ##\n\n"
            "Keep a counter but state no number.\n\n"
            f"## Failure escalation ##\n\n{FULL_BLOCK}\n"
        )
        self._write_command("c", text)
        fs = self._findings("L26")
        self.assertEqual(len(fs), 1)
        self.assertIn("Iteration guard", fs[0].message)

    # --- regression: setext-headed guard section located (Fix 1) ----------

    def test_es1_setext_guard_section_with_wrong_cap_fails(self):
        # Fix 1: the "Iteration guard" H2 is written SETEXT-style (title line
        # then a '---' underline). Under the old ATX-only _section_text the
        # section was never located, so the L26 bound check was silently skipped
        # (a false negative). With setext-aware slicing the MAX_ITERATIONS=3
        # wrong cap inside it is now seen and L26 fires.
        fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n'
        text = (
            f"{fm}\n# /cmd\n\n"
            "Iteration guard\n"
            "---------------\n\n"
            "Keep a counter, `MAX_ITERATIONS=3`.\n\n"
            "Failure escalation\n"
            "------------------\n\n"
            f"{FULL_BLOCK}\n"
        )
        self._write_command("c", text)
        fs = self._findings("L26")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "escalation.max-iterations")
        self.assertEqual(fs[0].severity, "S2")
        self.assertIn("Iteration guard", fs[0].message)

    def test_es1_setext_guard_section_with_correct_cap_passes(self):
        # Fix 1 control: the same setext-headed guard section carrying the
        # correct MAX_ITERATIONS=5 cap is located and stays clean for L26.
        fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n'
        text = (
            f"{fm}\n# /cmd\n\n"
            "Iteration guard\n"
            "---------------\n\n"
            "Keep a counter, `MAX_ITERATIONS=5`.\n\n"
            "Failure escalation\n"
            "------------------\n\n"
            f"{FULL_BLOCK}\n"
        )
        self._write_command("c", text)
        self.assertEqual(self._findings("L26"), [])

    # --- regression: ATX-H1 above '---' is not a setext H2 (Fix 1) --------

    def test_es1_atx_h1_above_rule_not_treated_as_setext_title(self):
        # Fix 1: an ATX H1 ("# /cmd") immediately followed by a '---' horizontal
        # rule must NOT be read as a setext H2 titled "/cmd". If it were, the
        # bogus "/cmd" H2 would split the stream and the real "## Iteration
        # guard" section (carrying the correct MAX_ITERATIONS=5) could be
        # mis-sliced. With the H1 guard the guard section is located intact and
        # L26 stays clean.
        fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n'
        text = (
            f"{fm}\n# /cmd\n"
            "---\n\n"
            "Intro paragraph.\n\n"
            "## Iteration guard\n\n"
            "Keep a counter, `MAX_ITERATIONS=5`.\n\n"
            f"## Failure escalation\n\n{FULL_BLOCK}\n"
        )
        self._write_command("c", text)
        self.assertEqual(self._findings("L26"), [])

    def test_es1_atx_h1_above_rule_inside_guard_does_not_mask_bound(self):
        # Fix 1 control: with the H1 guard, an ATX H1 + '---' sitting INSIDE the
        # guard section does not prematurely end it; a missing bound there is
        # still seen and L26 fires (no false negative from the H1/rule pair).
        fm = '---\ndescription: "x"\nargument-hint: "[a]"\n---\n'
        text = (
            f"{fm}\n# /cmd\n\n"
            "## Iteration guard\n\n"
            "# Guard heading\n"
            "---\n\n"
            "State a counter but give no number here.\n\n"
            f"## Failure escalation\n\n{FULL_BLOCK}\n"
        )
        self._write_command("c", text)
        fs = self._findings("L26")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "escalation.max-iterations")

    # --- regression: near-miss banner still validated (Fix) ---------------

    def test_es2_near_miss_banner_still_validated(self):
        # An interior-whitespace banner variant ("=== SDLC ESCALATION  ===")
        # must still be held to the seven-field contract, not silently skipped.
        block = "```text\n=== SDLC ESCALATION  ===\nstage: review\n=== END ===\n```"
        self._write_command("c", _command_md("`MAX_ITERATIONS=5`.", block))
        fs = self._findings("L27")
        self.assertTrue(fs, "near-miss banner with missing fields must fire L27")
        self.assertTrue(all(f.rule == "escalation.block-fields" for f in fs))

    # --- real shipped plugin is clean for L26-L27 -------------------------

    def test_real_plugin_clean_for_escalation(self):
        self.assertTrue(REAL_PLUGIN.is_dir(), f"missing real plugin at {REAL_PLUGIN}")
        fs = check_escalation.check(REAL_PLUGIN)
        esc_fs = [f for f in fs if f.check in ("L26", "L27")]
        self.assertEqual(
            esc_fs,
            [],
            "shipped plugin must be clean for L26-L27; got: "
            + "; ".join(f.render() for f in esc_fs),
        )


if __name__ == "__main__":
    unittest.main()
