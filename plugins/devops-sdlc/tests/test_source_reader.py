"""Inert regression tests for the reader embedded in the shipped agent guide."""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
GUIDE_PATH = PLUGIN / "skills" / "AI-AGENT-GUIDE.md"
GUIDE = GUIDE_PATH.read_text(encoding="utf-8")
SCRIPT = GUIDE.split("<<'PY'\n", 1)[1].split("\nPY\n```", 1)[0] + "\n"


class ReaderTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="reader-contract-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.paths = [
            self.root / name for name in ["manifest.json", "helper.py", "adapter.py"]
        ]
        for path, body in zip(
            self.paths,
            [
                b'{"name":"synthetic"}',
                b"# synthetic helper\n",
                'print("caf\u00e9")\n'.encode(),
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

    def test_reader_is_extracted_from_shipped_guide(self):
        self.assertEqual(GUIDE.count("<<'PY'\n"), 1)
        self.assertEqual(GUIDE.count("\nPY\n```"), 1)
        self.assertTrue(SCRIPT.strip())
        command = next(
            x for x in GUIDE.splitlines() if x.startswith('"$TRUSTED_PYTHON"')
        )
        self.assertIn(" -I - ", command)
        self.assertEqual(command.count("$DEVOPS_PLUGIN_ROOT/"), 3)

    def test_expected_bytes_text_and_digests(self):
        result, output = self.run_reader()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(output["status"], "VERIFIED")
        self.assertEqual(len(output["files"]), 3)
        for row, path, digest in zip(output["files"], self.paths, self.expected):
            self.assertEqual(
                row,
                {"path": str(path), "sha256": digest, "utf8_text": path.read_text()},
            )
            self.assertEqual(row["utf8_text"].encode(), path.read_bytes())

    def test_tampered_last_file_does_not_emit_earlier_source(self):
        self.paths[2].write_text("changed")
        self.blocked(*self.run_reader())

    def test_unavailable_source(self):
        self.paths[1].unlink()
        self.blocked(*self.run_reader())

    def test_unavailable_host_executable(self):
        with self.assertRaises(FileNotFoundError):
            subprocess.run(
                [str(self.root / "missing-host-python"), "-I", "-"],
                input=SCRIPT,
                text=True,
                capture_output=True,
                timeout=5,
            )

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
        for path, data in zip(self.paths, [b"x" * 1_999_998, b"y", b"z"]):
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
