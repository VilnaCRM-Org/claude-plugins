"""Exercise CLI entrypoint exit codes and machine-readable output in-process."""

import contextlib
import io
import json
import runpy
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class EntrypointTests(unittest.TestCase):
    def test_direct_entrypoints_preserve_cli_exit_and_json_contracts(self):
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "invalid-inventory.json"
            invalid.write_text('{"unexpected": true}')
            cases = (
                ("devops.py", ["discover", "--repo", directory], 0, "DISCOVERED"),
                ("agent_cli.py", ["detect"], 2, "BLOCKED"),
                ("automation_coverage.py", [str(invalid)], 2, "BLOCKED"),
            )
            for filename, arguments, exit_code, status in cases:
                output, errors = io.StringIO(), io.StringIO()
                with (
                    self.subTest(script=filename),
                    mock.patch.object(sys, "argv", [filename, *arguments]),
                    mock.patch("shutil.which", return_value=None),
                    contextlib.redirect_stdout(output),
                    contextlib.redirect_stderr(errors),
                    self.assertRaises(SystemExit) as stopped,
                ):
                    runpy.run_path(str(SCRIPTS / filename), run_name="__main__")
                self.assertEqual(stopped.exception.code, exit_code)
                self.assertEqual(
                    json.loads(output.getvalue() or errors.getvalue())["status"], status
                )
                self.assertNotIn("Traceback", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
