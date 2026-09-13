"""Quoted shell envelope regressions across the shared evaluator surfaces."""

from __future__ import annotations

import unittest

import redaction
import test_redaction as boundaries


class ShellContextTests(unittest.TestCase):
    surfaces = boundaries.RedactionBoundaryTests.surfaces

    def test_nonsecret_shell_values_bound_embedded_secrets_and_preserve_neighbors(self):
        cases = (
            'key="api_token=ORCHID"',
            "key='api_token=ORCHID'",
            'key="api_token=ORCHID"COBALT',
            "key=api_token=ORCHID\\ COBALT",
            'key="api_token=ORCHID\\\nCOBALT"',
            "key='api_token=ORCHID'\"COBALT QUARTZ\"TAIL",
            'key="api_token=ORCHID\\"COBALT"',
            'key=prefix" api_token=ORCHID"COBALT',
            "key='message=api_token=ORCHID'",
            'key="Перевірка 東京 api_token=ORCHID"',
            "key='api_token=\"ORCHID COBALT\"'",
        )
        for assignment in cases:
            candidate = assignment + "\nusername=alice\nresult=READY\n"
            with self.subTest(candidate=candidate):
                redacted = redaction.redact_text(candidate)
                self.assertIn("\nusername=alice\nresult=READY\n", redacted)
                self.assertEqual(redaction.redact_text(redacted), redacted)
                for output in self.surfaces(candidate):
                    self.assertIn("alice", output)
                    self.assertIn("READY", output)
                    for fragment in ("ORCHID", "COBALT", "QUARTZ", "TAIL"):
                        self.assertNotIn(fragment, output)
        for control in (
            'key="Перевірка ordinary words"\nusername=alice\n',
            "key='ordinary'\" words\"tail\nusername=alice\n",
            'key="token without assignment"\nusername=alice\n',
        ):
            self.assertEqual(redaction.redact_text(control), control)

    def test_premature_outer_shell_quote_cannot_strand_secret_tail(self):
        for assignment in (
            'key="api_token="ORCHID COBALT"',
            "key='api_token='ORCHID COBALT'",
            'key="api_token="ORCHID\nCOBALT"',
        ):
            candidate = assignment + "\nusername=alice\n"
            with self.subTest(candidate=candidate):
                result = redaction.redact_text(candidate)
                self.assertIn("\nusername=alice\n", result)
                for output in self.surfaces(candidate):
                    self.assertNotIn("ORCHID", output)
                    self.assertNotIn("COBALT", output)
                    self.assertIn("alice", output)
        # Valid concatenation with a separate public assignment stays bounded.
        result = redaction.redact_text('key="api_token="ORCHID username=alice\n')
        self.assertNotIn("ORCHID", result)
        self.assertIn("username=alice", result)

    def test_source_spans_cover_all_sentinels_and_preserve_public_neighbors(self):
        for candidate in (
            "token=ORCHID\nusername=alice",
            'key="api_token=ORCHID"\nusername=alice',
            'key="api_token="ORCHID COBALT"\nusername=alice',
            '{"message":"token=ORCHID","public":"alice"}',
            '{"token":"ORCHID\\"COBALT',
            "token='ORCHID'\"COBALT QUARTZ\"TAIL\nusername=alice",
        ):
            with self.subTest(candidate=candidate):
                spans = redaction.redacted_source_spans(candidate)
                self.assertEqual(tuple(sorted(spans)), spans)
                for start, end in spans:
                    self.assertTrue(0 <= start < end <= len(candidate))
                for word in ("ORCHID", "COBALT", "QUARTZ", "TAIL"):
                    index = candidate.find(word)
                    if index >= 0:
                        self.assertTrue(
                            any(a <= index and index + len(word) <= b for a, b in spans)
                        )
                index = candidate.find("alice")
                if index >= 0:
                    self.assertFalse(any(a < index + 5 and index < b for a, b in spans))
        raw = "token=ORCHID"
        start = raw.index("ken=ORCHID")
        self.assertTrue(
            any(
                a < len(raw) and start < b
                for a, b in redaction.redacted_source_spans(raw)
            )
        )
        self.assertEqual(redaction.redacted_source_spans('key="ordinary"'), ())

    def test_malformed_nonsecret_outer_shell_quote_redacts_secret_tail(self):
        for candidate in (
            'key="api_token=ORCHID\nCOBALT QUARTZ',
            "key='api_token=ORCHID\nCOBALT QUARTZ",
            'key="api_token=ORCHID\\',
        ):
            for output in self.surfaces(candidate):
                for fragment in ("ORCHID", "COBALT", "QUARTZ"):
                    self.assertNotIn(fragment, output)


if __name__ == "__main__":
    unittest.main()
