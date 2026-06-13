"""Tests for the dead-reference checker (matrix rows L19–L25, cases RF-1..RF-7).

Synthetic plugin trees are built per-test in a tempdir and torn down again; no
fixtures are committed. A final test asserts the real php-backend-sdlc plugin is
clean (the contract's negative-of-negatives guard against over-matching).
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_references  # noqa: E402
import _model  # noqa: E402

REAL_PLUGIN = HERE.parent.parent.parent / "plugins" / "php-backend-sdlc"


def _write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class _Tree:
    """A throwaway synthetic plugin tree with the dirs the checker reads."""

    def __init__(self) -> None:
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="ref-test-"))
        # baseline real artifacts so cross-references resolve.
        _write(self.root / "scripts" / "validate-profile.sh", "#!/bin/sh\n")
        _write(self.root / "scripts" / "lib" / "common.sh", "#!/bin/sh\n")
        _write(self.root / "skills" / "testing-workflow" / "SKILL.md", "# testing-workflow\n")
        _write(self.root / "skills" / "code-review" / "SKILL.md", "# code-review\n")
        _write(self.root / "commands" / "sdlc.md", "# sdlc\n")
        _write(self.root / "commands" / "sdlc-plan.md", "# sdlc-plan\n")
        _write(self.root / "commands" / "sdlc-finish-pr.md", "# sdlc-finish-pr\n")
        _write(self.root / "agents" / "code-quality-reviewer.md", "# code-quality-reviewer\n")
        _write(
            self.root / "docs" / "profile-schema.md",
            "# schema\n\n`make.psalm` `make.ci` `quality.phpinsights.complexity`\n",
        )

    def command(self, name: str, body: str) -> None:
        _write(self.root / "commands" / f"{name}.md", body)

    def agent(self, name: str, body: str) -> None:
        _write(self.root / "agents" / f"{name}.md", body)

    def skill(self, name: str, body: str) -> None:
        _write(self.root / "skills" / name / "SKILL.md", body)

    def run(self):
        return check_references.check(self.root)

    def cleanup(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


class ReferenceCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tree = _Tree()

    def tearDown(self) -> None:
        self.tree.cleanup()

    def _rules(self, findings):
        return {f.rule for f in findings}

    # RF-1 (L19) script path -------------------------------------------------
    def test_rf1_script_positive(self):
        self.tree.skill(
            "code-review",
            "# code-review\n\nRun `${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh`.\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf1_script_negative_typo(self):
        self.tree.skill(
            "code-review",
            "# code-review\n\nRun `${CLAUDE_PLUGIN_ROOT}/scripts/validate-profle.sh`.\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.script.dead", findings[0].rule)
        self.assertEqual("S2", findings[0].severity)
        self.assertIn("validate-profle.sh", findings[0].message)

    def test_rf1_script_edge_subdir_resolves(self):
        # E: subdir path (scripts/lib/common.sh) and a path in a comment still checked.
        self.tree.skill(
            "code-review",
            "# code-review\n\n<!-- source ${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh -->\n",
        )
        self.assertEqual([], self.tree.run())

    # RF-2 (L20) skill path --------------------------------------------------
    def test_rf2_skillpath_positive(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nSee `${CLAUDE_PLUGIN_ROOT}/skills/code-review/SKILL.md`.\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf2_skillpath_negative_typo(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nSee `${CLAUDE_PLUGIN_ROOT}/skills/code-revew/SKILL.md`.\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.skill-path.dead", findings[0].rule)
        self.assertIn("code-revew", findings[0].message)

    def test_rf2_skillpath_edge_glob_exempt(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nLoad `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md`.\n",
        )
        self.assertEqual([], self.tree.run())

    # RF-3 (L21) relative links ----------------------------------------------
    def test_rf3_link_positive(self):
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\nSee [crud](../code-review/SKILL.md).\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf3_link_negative_typo(self):
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\nSee [crud](../code-revew/SKILL.md).\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.link.dead", findings[0].rule)

    def test_rf3_link_edge_intra_dir_with_anchor(self):
        # E: bare filename resolved relative to the linking file's dir; anchor stripped.
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\n[a](SKILL.md#section) and external [b](https://x/y.md).\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf3_link_dead_with_title_is_flagged(self):
        # Fix (cubic #2): a dead relative .md link carrying a Markdown title
        # suffix (`"Title"`) must still be resolved and flagged — the title must
        # be stripped before the path is extracted, otherwise the .md tail fuses
        # into the title and the dead link is a false negative.
        self.tree.skill(
            "testing-workflow",
            '# testing-workflow\n\nSee [crud](../code-revew/SKILL.md "The Title").\n',
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.link.dead", findings[0].rule)

    def test_rf3_link_live_with_title_not_flagged(self):
        # Fix (cubic #2) control: a LIVE relative .md link with a title resolves
        # cleanly once the title is stripped — no false positive.
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\nSee [crud](../code-review/SKILL.md 'Title').\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf3_link_dead_with_paren_title_is_flagged(self):
        # Fix (cubic P2): the PARENTHESIZED title form `](path.md (Title))` used
        # to truncate the captured target at the title's closing paren, fusing
        # the title into the path and losing the `.md` tail — so a dead link
        # silently bypassed the check. The space-separated ` (Title)` must be
        # stripped before resolution so the dead link is still flagged.
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\nSee [crud](../code-revew/SKILL.md (Some Title)).\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.link.dead", findings[0].rule)

    def test_rf3_link_live_with_paren_title_not_flagged(self):
        # Fix (cubic P2) control: a LIVE relative .md link with a paren title
        # resolves cleanly once the ` (Title)` is stripped — no false positive.
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\nSee [crud](../code-review/SKILL.md (Some Title)).\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf3_link_path_with_inner_parens_not_mis_split(self):
        # Fix (cubic P2) boundary: parens INSIDE the path with no preceding
        # whitespace (`dir(x)/f.md`) must NOT be treated as a title — the path is
        # captured intact and resolved as-is. Here the dead `dir(x)` path is
        # flagged for its real (missing) target, proving it was not mis-split
        # into `dir` + `(x)/f.md` title nor truncated.
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\nSee [crud](../dir(x)/SKILL.md).\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.link.dead", findings[0].rule)
        self.assertIn("dir(x)/SKILL.md", findings[0].message)

    def test_rf3_angle_bracket_dead_link_flagged(self):
        # Fix (round-3): CommonMark angle-bracket destination `](<path.md>)` — the
        # surrounding <> must be stripped so a dead link is still resolved/flagged.
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\nSee [crud](<../code-revew/SKILL.md>).\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.link.dead", findings[0].rule)

    def test_rf3_angle_bracket_live_link_not_flagged(self):
        # Fix (round-3) control: a LIVE angle-bracket .md link resolves cleanly.
        self.tree.skill(
            "testing-workflow",
            "# testing-workflow\n\nSee [crud](<../code-review/SKILL.md>).\n",
        )
        self.assertEqual([], self.tree.run())

    # RF-4 (L22) command refs ------------------------------------------------
    def test_rf4_command_positive(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nThen run /sdlc-finish-pr to wrap up.\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf4_command_negative_typo(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nThen run /sdlc-finsh-pr to wrap up.\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.command.dead", findings[0].rule)
        self.assertIn("/sdlc-finsh-pr", findings[0].message)

    def test_rf4_command_edge_longest_match_no_shadow(self):
        # E: /sdlc must not shadow /sdlc-plan; both resolve via longest-match token.
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nUse /sdlc to orchestrate or /sdlc-plan for planning.\n",
        )
        self.assertEqual([], self.tree.run())

    # RF-5 (L23) agent refs --------------------------------------------------
    def test_rf5_agent_positive(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nDelegate to the `code-quality-reviewer` agent.\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf5_agent_negative_typo(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nDelegate to the `code-quality-reviwer` agent.\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.agent.dead", findings[0].rule)

    def test_rf5_agent_edge_plain_backtick_not_flagged(self):
        # E: a backticked kebab token NOT called an agent is not flagged (conservative).
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nThe `some-random-token` is just a value, not an agent.\n",
        )
        self.assertEqual([], self.tree.run())

    # RF-6 (L24) skill refs --------------------------------------------------
    def test_rf6_skill_positive(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nApply the testing-workflow skill before merging.\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf6_skill_negative_typo(self):
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nApply the testng-workflow skill before merging.\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.skill.dead", findings[0].rule)
        self.assertIn("testng-workflow", findings[0].message)

    def test_rf6_skill_edge_generic_phrase_not_flagged(self):
        # E: a generic compound phrase that is not a near-typo of any skill is ignored.
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nbmad is a planning-time skill only during the gate.\n",
        )
        self.assertEqual([], self.tree.run())

    # RF-7 (L25) profile keys ------------------------------------------------
    def test_rf7_profilekey_positive(self):
        self.tree.skill(
            "code-review",
            "# code-review\n\nReads `make.psalm` and `quality.phpinsights.complexity`.\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf7_profilekey_negative_unknown(self):
        self.tree.skill(
            "code-review",
            "# code-review\n\nReads `make.pslam` (typo).\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.profile-key.unknown", findings[0].rule)
        self.assertIn("make.pslam", findings[0].message)

    def test_rf7_profilekey_edge_wildcard_and_filename_exempt(self):
        # E: `make.*` wildcard exempt; `architecture.md` filename not treated as a key.
        self.tree.skill(
            "code-review",
            "# code-review\n\nThe `make.*` map; artifact `architecture.md` is written.\n",
        )
        self.assertEqual([], self.tree.run())


    # RF-8 single-token names (Fix 7) ---------------------------------------
    def test_rf8_single_token_agent_positive(self):
        # Fix 7: a single-token agent name ('reviewer') resolves when present.
        _write(self.tree.root / "agents" / "reviewer.md", "# reviewer\n")
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nDelegate to the `reviewer` agent.\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf8_single_token_agent_negative_typo(self):
        # Fix 7: a single-token agent typo ('reviewr') is now caught.
        _write(self.tree.root / "agents" / "reviewer.md", "# reviewer\n")
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nDelegate to the `reviewr` agent.\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.agent.dead", findings[0].rule)
        self.assertIn("reviewr", findings[0].message)

    def test_rf8_single_token_skill_negative_typo(self):
        # Fix 7: a single-token "<name> skill" typo near a real single-token
        # skill is caught (edit-distance guard still applies).
        _write(self.tree.root / "skills" / "verify" / "SKILL.md", "# verify\n")
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nApply the verfy skill before merging.\n",
        )
        findings = self.tree.run()
        self.assertEqual(1, len(findings))
        self.assertEqual("references.skill.dead", findings[0].rule)
        self.assertIn("verfy", findings[0].message)

    def test_rf8_single_token_generic_word_not_flagged(self):
        # Fix 7 guard: a generic single word ('this skill') that is not a near
        # typo of any real skill must NOT be flagged — clean plugin stays quiet.
        self.tree.command(
            "sdlc-plan",
            "# sdlc-plan\n\nThis skill documents the workflow clearly.\n",
        )
        self.assertEqual([], self.tree.run())

    def test_rf8_schema_read_tolerates_bom(self):
        # Fix 1: profile-schema.md with a UTF-8 BOM must still parse its tokens
        # (utf-8-sig), so a key declared there is not falsely reported unknown.
        _write(
            self.tree.root / "docs" / "profile-schema.md",
            "﻿# schema\n\n`make.psalm` `make.bom_key`\n",
        )
        self.tree.skill(
            "code-review",
            "# code-review\n\nReads `make.bom_key`.\n",
        )
        self.assertEqual([], self.tree.run())


class RealPluginCleanTest(unittest.TestCase):
    def test_real_plugin_has_no_dead_references(self):
        self.assertTrue(REAL_PLUGIN.is_dir(), f"missing real plugin at {REAL_PLUGIN}")
        # sanity: discovery actually finds artifacts to scan.
        self.assertGreater(len(_model.discover(REAL_PLUGIN)), 0)
        findings = check_references.check(REAL_PLUGIN)
        self.assertEqual(
            [], findings, "real plugin should be clean; over-matching regex: " +
            "; ".join(f.render() for f in findings),
        )


if __name__ == "__main__":
    unittest.main()
