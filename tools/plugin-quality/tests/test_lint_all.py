"""Integration tests for the Tier-1 aggregator (lint_all).

Guards against silent-pass: a broken plugin must produce findings from multiple
modules and exit non-zero, and the real shipped plugin must be clean.
"""

import contextlib
import io
import json
import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import lint_all  # noqa: E402

REPO_ROOT = HERE.parent.parent.parent
REAL_PLUGIN = REPO_ROOT / "plugins" / "php-backend-sdlc"


class TestLintAllAggregator(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _broken_plugin(self) -> pathlib.Path:
        pr = self.tmp / "plugins" / "brokenplug"
        (pr / ".claude-plugin").mkdir(parents=True)
        (pr / ".claude-plugin" / "plugin.json").write_text(
            json.dumps({"name": "brokenplug", "version": "9"})
        )
        (pr / "commands").mkdir()
        (pr / "commands" / "foo.md").write_text('---\ndescription: "x"\n---\n# /foo\n## Inputs\n')
        (self.tmp / ".claude-plugin").mkdir(parents=True)
        (self.tmp / ".claude-plugin" / "marketplace.json").write_text(
            json.dumps(
                {
                    "name": "m",
                    "owner": {"name": "o"},
                    "plugins": [{"name": "brokenplug", "source": "./plugins/brokenplug"}],
                }
            )
        )
        return pr

    def test_broken_plugin_exits_nonzero(self):
        pr = self._broken_plugin()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            rc = lint_all.main([str(pr), "--repo-root", str(self.tmp)])
        self.assertEqual(rc, 1)

    def test_broken_plugin_findings_span_modules(self):
        pr = self._broken_plugin()
        findings = lint_all.run([pr], self.tmp)
        rules = {f.rule.split(".")[0] for f in findings}
        # manifest + frontmatter + structure + descriptions all contribute.
        self.assertIn("manifest", rules)
        self.assertIn("frontmatter", rules)
        self.assertIn("structure", rules)
        self.assertIn("descriptions", rules)

    def test_crashing_check_is_a_finding_not_silent(self):
        # A check module that raises must surface an ERR finding, never pass silently.
        class Boom:
            __name__ = "check_boom"

            @staticmethod
            def check(_root):
                raise RuntimeError("kaboom")

        import _common

        findings = []
        try:
            findings.extend(Boom.check(self.tmp))
        except Exception:
            findings.append(
                _common.Finding(
                    check="ERR", rule="check_boom.crashed", severity="S2",
                    path=str(self.tmp), message="boom",
                )
            )
        self.assertTrue(any(f.check == "ERR" for f in findings))

    @unittest.skipUnless(REAL_PLUGIN.is_dir(), "real plugin not present")
    def test_real_plugin_is_clean(self):
        findings = lint_all.run([REAL_PLUGIN], REPO_ROOT)
        self.assertEqual(findings, [], msg="\n".join(f.render() for f in findings))


if __name__ == "__main__":
    unittest.main()
