"""Unit tests for the naming checks (L6–L10), cases NM-1..NM-5.

Trees are synthesized in tempdirs; no committed fixtures. Each test builds the
minimal plugin layout `_model.discover` needs and asserts findings by rule id.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_naming  # noqa: E402


def _rules(findings):
    return [f.rule for f in findings]


def _checks(findings):
    return [f.check for f in findings]


class NamingTestBase(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    # --- builders -----------------------------------------------------
    def _write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def agent(self, stem, name=None, h1=None, model="sonnet", extra=""):
        fm = [f"name: {name}"] if name is not None else []
        if model is not None:
            fm.append(f"model: {model}")
        if extra:
            fm.append(extra)
        body = f"\n# {h1}\n" if h1 is not None else "\nbody\n"
        text = "---\n" + "\n".join(fm) + "\n---\n" + body
        return self._write(f"agents/{stem}.md", text)

    def skill(self, dirname, name=None, h1=None):
        fm = [f"name: {name}"] if name is not None else []
        fm.append("description: A skill description.")
        body = f"\n# {h1}\n" if h1 is not None else "\nbody\n"
        text = "---\n" + "\n".join(fm) + "\n---\n" + body
        return self._write(f"skills/{dirname}/SKILL.md", text)

    def command(self, stem, argument_hint=None, model=None):
        fm = ['description: "Run a thing"']
        if argument_hint is not None:
            fm.append(f"argument-hint: {argument_hint}")
        if model is not None:
            fm.append(f"model: {model}")
        text = "---\n" + "\n".join(fm) + "\n---\n\nbody\n"
        return self._write(f"commands/{stem}.md", text)

    def lint(self):
        return check_naming.check(self.root)


# NM-1 (L6) agent name == stem == H1 leading token
class TestNM1AgentName(NamingTestBase):
    def test_positive(self):  # P
        self.agent("ci-fixer", name="ci-fixer", h1="ci-fixer")
        self.assertEqual([], self.lint())

    def test_name_mismatch_stem(self):  # N
        self.agent("ci-fixer", name="cifixer", h1="cifixer")
        rules = _rules(self.lint())
        self.assertIn("naming.agent.name-mismatch", rules)

    def test_h1_mismatch(self):  # N
        self.agent("ci-fixer", name="ci-fixer", h1="CI Fixer")
        f = self.lint()
        self.assertIn("naming.agent.name-mismatch", _rules(f))
        self.assertIn("L6", _checks(f))

    def test_edge_h1_with_emdash_description(self):  # E -> PASS
        self.agent("foo", name="foo", h1="foo — does the thing")
        self.assertEqual([], self.lint())

    def test_edge_h1_with_spaced_hyphen(self):  # E -> PASS
        self.agent("foo", name="foo", h1="foo - does the thing")
        self.assertEqual([], self.lint())


# NM-2 (L7) skill name == dir, never compared to (Title Case) H1
class TestNM2SkillName(NamingTestBase):
    def test_positive(self):  # P
        self.skill("deptrac-fixer", name="deptrac-fixer", h1="Deptrac Fixer")
        self.assertEqual([], self.lint())

    def test_name_mismatch_dir(self):  # N
        self.skill("deptrac-fixer", name="deptracfixer", h1="Deptrac Fixer")
        self.assertIn("naming.skill.name-mismatch", _rules(self.lint()))

    def test_edge_title_case_h1_not_compared(self):  # E -> PASS
        self.skill("deptrac-fixer", name="deptrac-fixer", h1="Deptrac Fixer Skill")
        self.assertEqual([], self.lint())


# NM-3 (L8) model enum
class TestNM3ModelEnum(NamingTestBase):
    def test_positive_opus(self):  # P
        self.agent("a", name="a", h1="a", model="opus")
        self.assertEqual([], self.lint())

    def test_positive_sonnet(self):  # P
        self.agent("a", name="a", h1="a", model="sonnet")
        self.assertEqual([], self.lint())

    def test_negative_unknown_model(self):  # N
        self.agent("a", name="a", h1="a", model="gpt-4")
        f = self.lint()
        self.assertIn("naming.model.enum", _rules(f))
        self.assertIn("L8", _checks(f))

    def test_edge_inherit_and_haiku(self):  # E -> PASS
        self.agent("a", name="a", h1="a", model="inherit")
        self.agent("b", name="b", h1="b", model="haiku")
        self.assertEqual([], self.lint())

    def test_model_on_command_checked(self):  # any artifact with model
        self.command("cmd", argument_hint='"[x]"', model="gpt-4")
        self.assertIn("naming.model.enum", _rules(self.lint()))


# NM-4 (L9) argument-hint shape
class TestNM4ArgumentHint(NamingTestBase):
    def test_positive_pipe_choice(self):  # P
        self.command("cmd", argument_hint='"[task-description | issue-URL]"')
        self.assertEqual([], self.lint())

    def test_positive_flag(self):  # P
        self.command("cmd", argument_hint='"[--refresh]"')
        self.assertEqual([], self.lint())

    def test_negative_no_brackets(self):  # N
        self.command("cmd", argument_hint='"pr-number"')
        f = self.lint()
        self.assertIn("naming.argument-hint.shape", _rules(f))
        self.assertIn("L9", _checks(f))

    def test_edge_two_groups(self):  # E -> PASS (multi-group allowed)
        self.command("cmd", argument_hint='"[a] [b]"')
        self.assertEqual([], self.lint())

    # --- regression: present-but-null argument-hint (Fix 3) ----------------
    def test_edge_null_argument_hint_no_l9(self):  # E -> no L9
        # Fix 3: `argument-hint:` (YAML null) is present-but-empty. L9 judges
        # only string-shaped hints; emptiness/None is L1's concern. Without the
        # guard, str(None) == "None" ran the bracket regex and yielded a
        # spurious/garbled L9. The key is present (None) so L9 must be silent.
        self.command("cmd", argument_hint="")  # `argument-hint:` -> None
        f = self.lint()
        self.assertNotIn("naming.argument-hint.shape", _rules(f))
        self.assertNotIn("L9", _checks(f))

    def test_null_argument_hint_still_flagged_by_l1(self):
        # Fix 3 control: the null required key is still caught — but by L1
        # (frontmatter), not L9 (naming). Confirms the concern wasn't dropped.
        import check_frontmatter  # local import: lint/ already on sys.path

        self.command("cmd", argument_hint="")  # `argument-hint:` -> None
        fm_findings = check_frontmatter.check(self.root)
        l1 = [
            f for f in fm_findings if f.check == "L1" and "argument-hint" in f.message
        ]
        self.assertEqual(len(l1), 1)


# NM-5 (L10) kebab-case names
class TestNM5KebabCase(NamingTestBase):
    def test_positive(self):  # P
        self.agent(
            "pr-comment-resolver",
            name="pr-comment-resolver",
            h1="pr-comment-resolver",
        )
        self.assertEqual([], self.lint())

    def test_negative_snake_pascal(self):  # N
        # File stem stays kebab so L6/L10-stem stay clean; only the frontmatter
        # name violates kebab-case -> exactly the L10 finding we assert.
        self.agent(
            "pr-comment-resolver",
            name="PR_Comment_Resolver",
            h1="PR_Comment_Resolver",
        )
        f = self.lint()
        self.assertIn("naming.kebab-case", _rules(f))
        self.assertIn("L10", _checks(f))

    def test_edge_digits_allowed(self):  # E -> PASS
        self.agent(
            "bmad-fr-nfr-review-gate",
            name="bmad-fr-nfr-review-gate",
            h1="bmad-fr-nfr-review-gate",
        )
        self.assertEqual([], self.lint())

    def test_command_stem_kebab(self):  # command identity from stem
        self.command("sdlc-finish-pr", argument_hint='"[pr-number]"')
        self.assertEqual([], self.lint())

    def test_skill_dir_kebab_violation(self):  # skill identity from dir
        self.skill("Bad_Skill", name="Bad_Skill", h1="Bad Skill")
        self.assertIn("naming.kebab-case", _rules(self.lint()))


if __name__ == "__main__":
    unittest.main()
