"""JSON field preservation and secret removal across real evaluator surfaces."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

import behavior_judge
import prompt_judge
import redaction


class RedactionBoundaryTests(unittest.TestCase):
    def surfaces(self, value: str) -> tuple[str, ...]:
        scenario = {
            "id": "redaction-boundary",
            "prompt": "Describe a safe validation proposal.",
            "must": ["validate"],
            "must_not": ["mutate"],
        }
        citation = "Reviewed safe source."
        artifact = citation + "\n" + value
        if len(value.splitlines()) > 1:
            with self.assertRaises(prompt_judge.AssessmentError):
                prompt_judge.stored_dimensions(
                    {
                        "dimensions": {
                            "J1": {"score": 5, "evidence": value, "citation": citation}
                        }
                    },
                    artifact,
                )
        # The persisted judge field requires single-line evidence. Raw multiline
        # candidates still exercise the other three real redaction surfaces.
        evidence = " ".join(value.splitlines())
        stored = prompt_judge.stored_dimensions(
            {
                "dimensions": {
                    "J1": {"score": 5, "evidence": evidence, "citation": citation}
                }
            },
            artifact,
        )
        return (
            redaction.redact_text(value),
            behavior_judge.audit_text(value),
            behavior_judge.judge_prompt(scenario, value),
            json.dumps(stored),
        )

    def test_json_neighbors_survive_without_secret_fragments(self):
        cases = (
            '{"token":"ORCHID","must":"validate"}',
            '{"token":"ORCHID\\"COBALT","must":"validate"}',
            '{"outer":{"token":"ORCHID","must":"validate"}}',
            '{"token":"ORCHID,COBALT;QUARTZ","must":"validate"}',
            '{"token":123456,"must":"validate"}',
            '{"token":"ORCHID","password":"COBALT","must":"validate"}',
            '{"token":"ORCHID", "must": "validate"}',
        )
        for candidate in cases:
            with self.subTest(candidate=candidate):
                for result in self.surfaces(candidate):
                    self.assertIn("validate", result)
                    for secret in ("ORCHID", "COBALT", "QUARTZ", "123456"):
                        self.assertNotIn(secret, result)
        self.assertEqual(
            redaction.redact_text(cases[0]),
            '{"token":"[REDACTED]","must":"validate"}',
        )

    def test_structured_secret_values_and_embedded_assignments_preserve_neighbors(self):
        cases = (
            '{"token":{"first":"ORCHID","second":"COBALT"},"must":"validate"}',
            '{"token":["ORCHID","COBALT"],"must":"validate"}',
            '{"token":{"deep":[{"key":"ORCHID"},"COBALT"]},"must":"validate"}',
            '{"token":{"first":"ORCHID\\"COBALT"},"must":"validate"}',
            '{"message":"token=ORCHID","must":"validate"}',
            '{"message":"token=\\"ORCHID COBALT\\"","must":"validate"}',
            '{"message":"token=ORCHID tail \\ud800","must":"validate"}',
        )
        for candidate in cases:
            with self.subTest(candidate=candidate):
                redacted = redaction.redact_text(candidate)
                parsed = json.loads(redacted)
                self.assertEqual(parsed["must"], "validate")
                self.assertEqual(redaction.redact_text(redacted), redacted)
                for result in self.surfaces(candidate):
                    self.assertIn("validate", result)
                    for fragment in ("ORCHID", "COBALT"):
                        self.assertNotIn(fragment, result)

    def test_changed_json_strings_preserve_readable_unicode_and_surrogate_safety(self):
        for suffix in ("Перевірка 東京 🌿", r"Перевірка \ud800", r"東京 \udfff"):
            candidate = '{"message":"token=ORCHID ' + suffix + '","must":"validate"}'
            with self.subTest(suffix=suffix):
                redacted = redaction.redact_text(candidate)
                redacted.encode("utf-8")
                self.assertIn(suffix.split()[0], redacted)
                self.assertEqual(json.loads(redacted)["must"], "validate")
                self.assertEqual(redaction.redact_text(redacted), redacted)
                for result in self.surfaces(candidate):
                    result.encode("utf-8")
                    self.assertNotIn("ORCHID", result)

    def test_decoded_and_punctuated_json_secret_keys_preserve_public_fields(self):
        for key in (r"to\u006ben", "db.password", r"api\u005fkey", r"db\"token"):
            candidate = '{"' + key + '":"ORCHID","must":"validate"}'
            with self.subTest(key=key):
                for result in self.surfaces(candidate):
                    self.assertNotIn("ORCHID", result)
                    self.assertIn("validate", result)
                redacted = redaction.redact_text(candidate)
                self.assertEqual(json.loads(redacted)["must"], "validate")
                self.assertEqual(redaction.redact_text(redacted), redacted)
        control = r'{"pub\u006cic.key":"ordinary","must":"validate"}'
        self.assertEqual(redaction.redact_text(control), control)

    def test_malformed_secret_container_consumes_tail(self):
        for candidate in (
            '{"token":{"first":"ORCHID","second":"COBALT"',
            '{"token":["ORCHID",{"key":"COBALT"}]',
            '{"token":["ORCHID"},"COBALT"',
        ):
            with self.subTest(candidate=candidate):
                for result in self.surfaces(candidate):
                    for fragment in ("ORCHID", "COBALT"):
                        self.assertNotIn(fragment, result)

    def test_shell_joined_quotes_punctuation_and_tails_remain_one_secret(self):
        cases = (
            "token='ORCHID'\"COBALT QUARTZ\"TAIL",
            '"token"="ORCHID",COBALT;TAIL',
            "token=ORCHID\\ COBALT",
            "token=ORCHID\\\nCOBALT",
            "token='ORCHID'\"COBALT QUARTZ",
            'token="ORCHID\\',
            '{"token":"ORCHID"TAIL,"must":"validate"}',
        )
        for candidate in cases:
            with self.subTest(candidate=candidate):
                for result in self.surfaces(candidate):
                    for secret in ("ORCHID", "COBALT", "QUARTZ", "TAIL"):
                        self.assertNotIn(secret, result)

    def test_unclosed_json_quote_consumes_tail_not_fake_fields(self):
        candidate = '{"token":"ORCHID\\"COBALT,\\"must\\":\\"QUARTZ'
        for result in self.surfaces(candidate):
            for fragment in ("ORCHID", "COBALT", "QUARTZ"):
                self.assertNotIn(fragment, result)

    def test_premature_json_quotes_never_strand_named_secret_tails(self):
        cases = (
            '{"message": "api_token="ORCHID COBALT""}',
            '{"message":"api_token="ORCHID"COBALT","must":"QUARTZ"}',
            '{"message":"password=prefix"ORCHID COBALT"}',
            '{"message":"token="  ORCHID COBALT}',
            '{"message":"token=",ORCHID COBALT}',
            '{"message":"token=";ORCHID COBALT}',
        )
        for candidate in cases:
            with self.subTest(candidate=candidate):
                for result in self.surfaces(candidate):
                    for fragment in ("ORCHID", "COBALT", "QUARTZ"):
                        self.assertNotIn(fragment, result)
                result = redaction.redact_text(candidate)
                self.assertEqual(redaction.redact_text(result), result)
        for candidate in (
            '{"message":"token=","must":"validate"}',
            '{"message":"token=ORCHID","must":"validate"}',
            '{"message":"token=\\"ORCHID COBALT\\"","must":"validate"}',
        ):
            with self.subTest(valid=candidate):
                result = redaction.redact_text(candidate)
                self.assertEqual(json.loads(result)["must"], "validate")
                self.assertNotIn("ORCHID", result)
                self.assertNotIn("COBALT", result)

    def test_nonsecret_json_and_shell_controls_are_unchanged(self):
        for candidate in (
            '{"must":"validate","safe":[1,2]}',
            'message="ordinary words" status=READY',
            '{"outer":{"must":"validate"},"safe":true}',
            '"token" is a word',
        ):
            self.assertEqual(redaction.redact_text(candidate), candidate)

    def test_quoted_nonsecret_assignments_do_not_consume_later_secret_controls(self):
        cases = (
            'argv=["make", "terraspace-validate", "env=development"] token=ORCHID',
            "message=\"unrecognized arguments: '--profile'\" token=ORCHID",
            "python=\"self.assertIn('validate', output)\" token=ORCHID",
        )
        for candidate in cases:
            with self.subTest(candidate=candidate):
                result = redaction.redact_text(candidate)
                self.assertIn("[REDACTED]", result)
                self.assertNotIn("ORCHID", result)
                self.assertIn("token=", result)
                self.assertEqual(redaction.redact_text(result), result)
                for output in self.surfaces(candidate):
                    self.assertNotIn("ORCHID", output)
                    self.assertIn("[REDACTED]", output)

    def test_invalid_public_json_tail_cannot_hide_escaped_secret_keys(self):
        for tail in (
            r' "\u0074oken":"ORCHID COBALT"}',
            r'; "api\u005fkey":["ORCHID","COBALT"]}',
            r'junk "db.pass\u0077ord":{"value":"ORCHID COBALT"}}',
            r' "\u0074oken":"ORCHID\"COBALT',
        ):
            candidate = '{"note":"safe"' + tail
            with self.subTest(candidate=candidate):
                for result in self.surfaces(candidate):
                    for fragment in ("ORCHID", "COBALT"):
                        self.assertNotIn(fragment, result)
                result = redaction.redact_text(candidate)
                self.assertEqual(result, '{"note":"[REDACTED]"')
                self.assertEqual(redaction.redact_text(result), result)
                self.assertEqual(
                    redaction.redacted_source_spans(candidate),
                    ((candidate.index('"safe"'), len(candidate)),),
                )
        for control in (
            r'{"note":"safe", "pub\u006cic":"ordinary"}',
            '{"note":"safe"  }',
            '{"notes":[{"note":"safe"}]}',
            '{"note":"safe"',
        ):
            self.assertEqual(redaction.redact_text(control), control)
            self.assertEqual(redaction.redacted_source_spans(control), ())

    def test_long_json_and_shell_inputs_finish_in_bounded_process(self):
        code = """
from redaction import redact_text
escaped_quote = chr(92) + chr(34)
for n in (1000, 4000, 16000):
    for text in ('a' * n, 'secret' * n, 'secret' * n + '=   '):
        assert redact_text(text) == text
    for key in ('x' * n + escaped_quote * n, ('x,' + escaped_quote) * n):
        malformed = '{"' + key
        assert redact_text(malformed) == malformed
    text = '{' + ','.join('"token":"ORCHID","safe":"validate"' for _ in range(n)) + '}'
    result = redact_text(text)
    assert result.count('validate') == n and 'ORCHID' not in result
    text = 'token="' + ('ORCHID' + escaped_quote) * n
    assert 'ORCHID' not in redact_text(text)
    text = '{"message":"' + ('secret' * n) + '="ORCHID COBALT""}'
    result = redact_text(text)
    assert 'ORCHID' not in result and 'COBALT' not in result
    text = '{"message":"token="' + (' ' * n) + 'ORCHID COBALT}'
    result = redact_text(text)
    assert 'ORCHID' not in result and 'COBALT' not in result
    text = '{"note":"safe"' + (' ' * n) + '"' + chr(92) + 'u0074oken":"ORCHID COBALT"}'
    result = redact_text(text)
    assert 'ORCHID' not in result and 'COBALT' not in result
    text = 'key="' + ('ordinary ' * n) + 'api_token=ORCHID"\\nusername=alice'
    result = redact_text(text)
    assert 'ORCHID' not in result and 'username=alice' in result
    text = 'key=' + ('nested=' * n) + 'api_token=ORCHID\\nusername=alice'
    result = redact_text(text)
    assert 'ORCHID' not in result and 'username=alice' in result
    text = 'token=' + escaped_quote + ('ORCHID ' * n) + escaped_quote
    assert 'ORCHID' not in redact_text(text)
    text = 'token=' + escaped_quote + ('ORCHID ' * n)
    assert 'ORCHID' not in redact_text(text)
    text = '[' + ','.join('"env=development"' for _ in range(n)) + ']'
    assert redact_text(text) == text
    text += '\\ntoken=ORCHID\\nFinal SAFE'
    result = redact_text(text)
    assert 'ORCHID' not in result and result.endswith('Final SAFE')
    text = "Don't " * n + 'token=ORCHID'
    assert 'ORCHID' not in redact_text(text)
    text = '[' + ','.join('"token=ORCHID"' for _ in range(n)) + ']'
    assert 'ORCHID' not in redact_text(text)
    for key in ('token', 'to' + chr(92) + 'u006ben'):
        text = ('run "{"' + key + '":"ORCHID COBALT"}" now ' ) * n
        result = redact_text(text)
        assert 'ORCHID' not in result and 'COBALT' not in result
        text = ('message="{"' + key + '":"ORCHID COBALT"}" now ') * n
        result = redact_text(text)
        assert 'ORCHID' not in result and 'COBALT' not in result
    text = ("'api_key=ORCHID" + chr(92) + "' status=READY ") * n
    result = redact_text(text)
    assert 'ORCHID' not in result and result.count('READY') == n
print('bounded-redaction-PASS')
"""
        result = subprocess.run(
            [sys.executable, "-c", code],
            cwd=Path(__file__).parent,
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
        self.assertEqual(result.stdout.strip(), "bounded-redaction-PASS")


if __name__ == "__main__":
    unittest.main()
