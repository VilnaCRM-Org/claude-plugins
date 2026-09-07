"""Inert regression tests for the reader embedded in the shipped agent guide."""

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
GUIDE_PATH = PLUGIN / "skills" / "AI-AGENT-GUIDE.md"
GUIDE = GUIDE_PATH.read_text(encoding="utf-8")
READER_BLOCKS = [
    block
    for block in re.findall(r"(?ms)^```bash\n(.*?)^```[ \t]*$", GUIDE)
    if "<<'PY'\n" in block
]
if len(READER_BLOCKS) != 1:
    raise ValueError("Expected one complete documented reader shell block")
READER_SHELL = READER_BLOCKS[0]
SCRIPT = READER_SHELL.split("<<'PY'\n", 1)[1].rsplit("\nPY\n", 1)[0] + "\n"


class ReaderTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="reader-contract-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.paths = [
            self.root / name
            for name in [
                "manifest.json",
                "helper.py",
                "adapter.py",
                "automation_coverage.py",
            ]
        ]
        for path, body in zip(
            self.paths,
            [
                b'{"name":"synthetic"}',
                b"# synthetic helper\n",
                'print("caf\u00e9")\n'.encode(),
                b"# synthetic automation coverage helper\n",
            ],
        ):
            path.write_bytes(body)
        self.expected = [hashlib.sha256(p.read_bytes()).hexdigest() for p in self.paths]

    def run_reader(self, paths=None, hashes=None, environment=None):
        args = [
            v
            for pair in zip(paths or self.paths, hashes or self.expected)
            for v in map(str, pair)
        ]
        result = subprocess.run(
            [sys.executable, "-I", "-", *args],
            input=SCRIPT,
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=5,
            env=environment,
        )
        self.assertEqual(result.stderr, "")
        return result, json.loads(result.stdout)

    def blocked(self, result, output):
        self.assertEqual(result.returncode, 2)
        self.assertEqual(
            output, {"status": "BLOCKED", "reason": "Source verification failed"}
        )

    def run_documented_reader_shell(self, environment):
        return subprocess.run(
            ["/bin/sh", "-c", READER_SHELL],
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=5,
            env=environment,
        )

    def test_documented_helper_uses_trusted_isolated_python(self):
        helper_command = next(
            line
            for line in GUIDE.splitlines()
            if line.startswith('"$TRUSTED_PYTHON"')
            and "validate-profile --repo ." in line
        )
        self.assertEqual(
            helper_command,
            '"$TRUSTED_PYTHON" -I "$DEVOPS_PLUGIN_ROOT/scripts/devops.py" '
            "validate-profile --repo .",
        )
        plugin_root = self.root / "plugin"
        scripts = plugin_root / "scripts"
        scripts.mkdir(parents=True)
        helper = scripts / "devops.py"
        helper.write_text(
            "import json\n"
            "import sys\n"
            "print(json.dumps({'isolated': sys.flags.isolated, "
            "'argv': sys.argv[1:]}))\n"
        )
        malicious_bin = self.root / "malicious-bin"
        malicious_bin.mkdir()
        marker = self.root / "malicious-path-python-ran"
        startup_marker = self.root / "malicious-pythonpath-ran"
        fake_python = malicious_bin / "python3"
        fake_python.write_text(
            "#!/bin/sh\nprintf executed > " + shlex.quote(str(marker)) + "\n"
        )
        fake_python.chmod(0o755)
        (self.root / "sitecustomize.py").write_text(
            "from pathlib import Path\n"
            + "Path("
            + repr(str(startup_marker))
            + ').write_text("executed")\n'
        )
        environment = {
            "PATH": str(malicious_bin),
            "PYTHONPATH": str(self.root),
            "TRUSTED_PYTHON": sys.executable,
            "DEVOPS_PLUGIN_ROOT": str(plugin_root),
        }
        result = subprocess.run(
            ["/bin/sh", "-c", helper_command],
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=5,
            env=environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(
            json.loads(result.stdout),
            {"isolated": 1, "argv": ["validate-profile", "--repo", "."]},
        )
        self.assertFalse(marker.exists())
        self.assertFalse(startup_marker.exists())

    def test_documented_reader_shell_reaches_all_four_inputs(self):
        plugin_root = self.root / "documented plugin"
        relative_paths = [
            ".claude-plugin/plugin.json",
            "scripts/devops.py",
            "scripts/agent_cli.py",
            "scripts/automation_coverage.py",
        ]
        for relative, source in zip(relative_paths, self.paths):
            target = plugin_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        environment = {
            "PATH": "",
            "TRUSTED_PYTHON": sys.executable,
            "DEVOPS_PLUGIN_ROOT": str(plugin_root),
            "MANIFEST_SHA256": self.expected[0],
            "DEVOPS_SHA256": self.expected[1],
            "AGENT_CLI_SHA256": self.expected[2],
            "AUTOMATION_COVERAGE_SHA256": self.expected[3],
        }
        result = self.run_documented_reader_shell(environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        output = json.loads(result.stdout)
        self.assertEqual(output["status"], "VERIFIED")
        self.assertEqual(len(output["files"]), 4)
        for row, relative, source, digest in zip(
            output["files"], relative_paths, self.paths, self.expected
        ):
            self.assertEqual(
                row,
                {
                    "path": str(plugin_root / relative),
                    "sha256": digest,
                    "utf8_text": source.read_text(),
                },
            )

    def test_reader_is_extracted_from_shipped_guide(self):
        self.assertEqual(GUIDE.count("<<'PY'\n"), 1)
        self.assertEqual(GUIDE.count("\nPY\n```"), 1)
        self.assertTrue(SCRIPT.strip())
        self.assertTrue(READER_SHELL.startswith('"$TRUSTED_PYTHON" -I - '))
        self.assertTrue(READER_SHELL.endswith("\nPY\n"))
        command = next(
            x for x in GUIDE.splitlines() if x.startswith('"$TRUSTED_PYTHON"')
        )
        self.assertIn(" -I - ", command)
        self.assertEqual(command.count("$DEVOPS_PLUGIN_ROOT/"), 4)

    def test_expected_bytes_text_and_digests(self):
        result, output = self.run_reader()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(output["status"], "VERIFIED")
        self.assertEqual(len(output["files"]), 4)
        for row, path, digest in zip(output["files"], self.paths, self.expected):
            self.assertEqual(
                row,
                {"path": str(path), "sha256": digest, "utf8_text": path.read_text()},
            )
            self.assertEqual(row["utf8_text"].encode(), path.read_bytes())

    def test_tampered_last_file_does_not_emit_earlier_source(self):
        self.paths[-1].write_text("changed")
        self.blocked(*self.run_reader())

    def test_unavailable_source(self):
        self.paths[1].unlink()
        self.blocked(*self.run_reader())

    def test_unavailable_host_executable(self):
        malicious_bin = self.root / "malicious-bin"
        malicious_bin.mkdir()
        marker = self.root / "malicious-path-python-ran"
        fake_python = malicious_bin / "python3"
        fake_python.write_text(
            "#!/bin/sh\n"
            + "printf 'MALICIOUS_PATH_PYTHON_MARKER'\n"
            + "printf executed > "
            + shlex.quote(str(marker))
            + "\n"
        )
        fake_python.chmod(0o755)
        environment = {
            "PATH": str(malicious_bin),
            "TRUSTED_PYTHON": str(self.root / "missing-trusted-python"),
            "DEVOPS_PLUGIN_ROOT": str(self.root),
            "MANIFEST_SHA256": self.expected[0],
            "DEVOPS_SHA256": self.expected[1],
            "AGENT_CLI_SHA256": self.expected[2],
            "AUTOMATION_COVERAGE_SHA256": self.expected[3],
            "PYTHONPATH": str(self.root),
        }
        result = self.run_documented_reader_shell(environment)
        self.assertEqual(result.returncode, 127, result.stderr)
        self.assertIn(environment["TRUSTED_PYTHON"], result.stderr)
        self.assertNotIn("Syntax error", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("MALICIOUS_PATH_PYTHON_MARKER", result.stderr)
        self.assertFalse(marker.exists())

    def test_missing_and_invalid_expected_digest(self):
        for value in ["", "f" * 63, "F" * 64, "x" * 64]:
            with self.subTest(value=value):
                self.blocked(*self.run_reader(hashes=[value, *self.expected[1:]]))

    def test_relative_parent_and_noncanonical_paths(self):
        for value in [
            "manifest.json",
            str(self.root / ".." / self.root.name / "manifest.json"),
            str(self.root) + "//manifest.json",
        ]:
            with self.subTest(path=value):
                self.blocked(*self.run_reader(paths=[value, *self.paths[1:]]))

    def test_final_and_parent_symlinks(self):
        link = self.root / "link"
        link.symlink_to(self.paths[0])
        self.blocked(*self.run_reader(paths=[link, *self.paths[1:]]))
        folder = self.root / "linked-folder"
        folder.symlink_to(self.root, target_is_directory=True)
        self.blocked(
            *self.run_reader(paths=[folder / "manifest.json", *self.paths[1:]])
        )

    def test_nonregular_fifo_and_directory(self):
        fifo = self.root / "fifo"
        os.mkfifo(fifo)
        for path in [fifo, self.root]:
            with self.subTest(path=str(path)):
                self.blocked(*self.run_reader(paths=[path, *self.paths[1:]]))

    def test_exact_total_bound_and_one_byte_overflow(self):
        for path, data in zip(self.paths, [b"x" * 1_999_997, b"y", b"z", b"q"]):
            path.write_bytes(data)
        self.expected = [hashlib.sha256(p.read_bytes()).hexdigest() for p in self.paths]
        result, output = self.run_reader()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            sum(len(x["utf8_text"].encode()) for x in output["files"]), 2_000_000
        )
        self.paths[-1].write_bytes(b"zz")
        self.expected[-1] = hashlib.sha256(b"zz").hexdigest()
        self.blocked(*self.run_reader())

    def test_invalid_utf8_even_with_matching_hash(self):
        self.paths[-1].write_bytes(b"\xff")
        self.expected[-1] = hashlib.sha256(b"\xff").hexdigest()
        self.blocked(*self.run_reader())

    def test_source_is_data_and_isolated_mode_ignores_pythonpath(self):
        marker = self.root / "executed"
        attack = (
            'token = "SYNTHETIC_NOT_A_CREDENTIAL"\n'
            "from pathlib import Path\nPath("
            + repr(str(marker))
            + ').write_text("executed")\n'
        )
        self.paths[1].write_text(attack)
        self.expected[1] = hashlib.sha256(attack.encode()).hexdigest()
        (self.root / "sitecustomize.py").write_text(attack)
        env = dict(
            os.environ, PYTHONPATH=str(self.root), PYTHONSTARTUP=str(self.paths[1])
        )
        result, output = self.run_reader(environment=env)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(output["files"][1]["utf8_text"], attack)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
