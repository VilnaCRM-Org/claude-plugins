"""Standalone code/prose quotes preserve evidence without hiding assignments."""

from __future__ import annotations

import unittest

import redaction
import test_redaction as boundaries


class QuotedContextTests(unittest.TestCase):
    surfaces = boundaries.RedactionBoundaryTests.surfaces

    def test_no_wrapper_code_and_markdown_preserve_complete_safe_proposals(self):
        for proposal in (
            '["make", "terraspace-validate", "env=development"]',
            "self.assertIn(\"unrecognized arguments: '--profile'\", output)",
            "self.assertIn('unrecognized arguments: \"--profile\"', output)",
            "```python\n"
            "self.assertIn(\"unrecognized arguments: '--profile'\", output)\n```",
            'Run `["make", "terraspace-validate", "env=development"]`.',
            "Don't change the environment; use `env=development`.",
        ):
            candidate = proposal + "\nResult READY\ntoken=ORCHID\nFinal SAFE"
            expected = candidate.replace("token=ORCHID", "token=[REDACTED]")
            with self.subTest(proposal=proposal):
                self.assertEqual(redaction.redact_text(candidate), expected)
                self.assertEqual(self.surfaces(candidate), self.surfaces(expected))
                self.assertEqual(redaction.redact_text(expected), expected)
                start = candidate.index("token=ORCHID")
                self.assertEqual(
                    redaction.redacted_source_spans(candidate),
                    ((start, start + len("token=ORCHID")),),
                )
                self.assertEqual(redaction.redact_text(proposal), proposal)
                self.assertEqual(redaction.redacted_source_spans(proposal), ())

    def test_standalone_quotes_arrays_and_apostrophes_never_hide_secrets(self):
        cases = (
            '"token=ORCHID"',
            r"token=\"ORCHID COBALT\"",
            r"token=prefix\"ORCHID COBALT\"TAIL",
            r"token=\"ORCHID\"\'COBALT QUARTZ\'TAIL",
            r"token=\"ORCHID COBALT",
            r'token=\"ORCHID" COBALT\"',
            r'token=\"ORCHID" COBALT',
            r"token=\'ORCHID' COBALT\'",
            r"token=\'ORCHID' COBALT",
            r"token=\'ORCHID COBALT\'",
            "'token=ORCHID'",
            '["token=ORCHID"]',
            "Don't print token=ORCHID",
            '"Do not print token=ORCHID"',
            '["env=development", "token=ORCHID"]',
            r'"token=\"ORCHID COBALT\""',
            r'["message=token=\"ORCHID COBALT\""]',
            '"token=ORCHID"COBALT',
            '"token=" ORCHID COBALT',
            '"token=";ORCHID COBALT',
            '"token=ORCHID"/COBALT',
            '"token=ORCHID"-COBALT',
            '"token=ORCHID".COBALT',
            "'token=ORCHID'\"COBALT QUARTZ\"TAIL",
            '"token="ORCHID COBALT"',
        )
        for candidate in cases:
            with self.subTest(candidate=candidate):
                result = redaction.redact_text(candidate)
                self.assertEqual(redaction.redact_text(result), result)
                for output in self.surfaces(candidate):
                    self.assertIn("[REDACTED]", output)
                    for fragment in ("ORCHID", "COBALT", "QUARTZ", "TAIL"):
                        self.assertNotIn(fragment, output)
                spans = redaction.redacted_source_spans(candidate)
                for fragment in ("ORCHID", "COBALT", "QUARTZ", "TAIL"):
                    index = candidate.find(fragment)
                    if index >= 0:
                        self.assertTrue(
                            any(
                                a <= index and index + len(fragment) <= b
                                for a, b in spans
                            )
                        )


if __name__ == "__main__":
    unittest.main()
