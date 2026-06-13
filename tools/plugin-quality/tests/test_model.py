"""Unit tests for the artifact model parser (``lint/_model.py``).

Focus: robustness of ``split_frontmatter`` across line-ending conventions, in
particular CRLF files whose ``---`` delimiters carry a trailing ``\\r``.
"""

import pathlib
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import _model  # noqa: E402


class TestSplitFrontmatterCRLF(unittest.TestCase):
    """A CRLF artifact's ``---\\r\\n`` delimiters must still be recognised.

    The opening and closing delimiter checks strip the carriage return too, so a
    valid frontmatter block is not silently parsed as absent on Windows-style
    line endings.
    """

    CRLF = '---\r\ndescription: "x"\r\nargument-hint: "[a]"\r\n---\r\n# body\r\n'

    def test_crlf_frontmatter_is_recognised(self):
        has_fm, data, err, body = _model.split_frontmatter(self.CRLF)
        self.assertTrue(has_fm, "CRLF '---' delimiter must be recognised")
        self.assertIsNone(err)
        self.assertEqual(data.get("description"), "x")
        self.assertEqual(data.get("argument-hint"), "[a]")
        self.assertIn("# body", body)

    def test_lf_frontmatter_still_recognised(self):
        lf = self.CRLF.replace("\r\n", "\n")
        has_fm, data, err, body = _model.split_frontmatter(lf)
        self.assertTrue(has_fm)
        self.assertIsNone(err)
        self.assertEqual(data.get("description"), "x")

    def test_crlf_no_frontmatter_is_absent(self):
        # A CRLF body with no leading '---' still reports no frontmatter.
        has_fm, data, err, body = _model.split_frontmatter("# just a body\r\nmore\r\n")
        self.assertFalse(has_fm)
        self.assertEqual(data, {})
        self.assertIsNone(err)

    def test_crlf_unterminated_frontmatter_errors(self):
        # An opened-but-never-closed CRLF block is a parse error, not "absent".
        text = "---\r\ndescription: x\r\nno closing delimiter\r\n"
        has_fm, _data, err, _body = _model.split_frontmatter(text)
        self.assertTrue(has_fm)
        self.assertIsNotNone(err)


class TestDiscoverCRLFCommand(unittest.TestCase):
    """End-to-end: a CRLF command artifact discovered from disk parses its
    frontmatter with the keys present (``has_frontmatter`` True)."""

    def test_crlf_command_discovered_with_frontmatter(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td) / "plugins" / "p"
            cmds = root / "commands"
            cmds.mkdir(parents=True)
            content = (
                '---\r\ndescription: "x"\r\nargument-hint: "[a]"\r\n---\r\n# body\r\n'
            )
            # Write bytes verbatim so the CRLF endings survive (no newline
            # translation from text-mode writes).
            (cmds / "do-thing.md").write_bytes(content.encode("utf-8"))
            arts = _model.discover(root)
        self.assertEqual(len(arts), 1)
        art = arts[0]
        self.assertEqual(art.kind, "command")
        self.assertTrue(art.has_frontmatter, "CRLF command must parse frontmatter")
        self.assertIsNone(art.frontmatter_error)
        self.assertEqual(art.frontmatter.get("description"), "x")
        self.assertEqual(art.frontmatter.get("argument-hint"), "[a]")


if __name__ == "__main__":
    unittest.main()
