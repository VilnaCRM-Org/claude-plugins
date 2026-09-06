"""Hermetic synthetic-CLI subprocess coverage for the evaluation adapter.

These fixtures are real local processes, not live Claude or Codex vendor calls.
They expose fixed version, authentication and output-envelope markers only.
"""

import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

ENTRYPOINT = Path(__file__).resolve().parents[1] / "scripts" / "agent_cli.py"
SPEC = importlib.util.spec_from_file_location("agent_cli_e2e", ENTRYPOINT)
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)
SCHEMA = {"type": "object", "properties": {"ok": {"type": "boolean"}}}
FAKE_CLI = r"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time


name = Path(sys.argv[0]).name
args = sys.argv[1:]
log_path = Path(os.environ["SYNTHETIC_CLI_LOG"])


def record(event, **fields):
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"event": event, "backend": name, **fields}) + "\n")


if args == ["--version"]:
    record("version")
    value = os.environ.get("SYNTHETIC_" + name.upper() + "_VERSION", "9.9.9")
    if value:
        print("synthetic-" + name + " " + value)
    raise SystemExit(0)
if name == "claude" and args == ["auth", "status"]:
    record("auth")
    print(json.dumps({"loggedIn": os.environ.get("SYNTHETIC_CLAUDE_AUTH") == "1"}))
    raise SystemExit(0)
if name == "codex" and args == ["login", "status"]:
    record("auth")
    if os.environ.get("SYNTHETIC_CODEX_AUTH") == "1":
        print("Logged in using synthetic fixture")
    else:
        print("Not logged in")
    raise SystemExit(0)

prompt = sys.stdin.read()
record("execute", explicit_context="SOURCE CONTEXT" in prompt,
       native_plugin="--plugin-dir" in args)
mode = os.environ.get("SYNTHETIC_EXEC_MODE", "success")
if mode == "nonzero":
    raise SystemExit(7)
if mode == "timeout":
    marker = Path(os.environ["SYNTHETIC_CHILD_MARKER"])
    child = (
        "import pathlib,time; time.sleep(2); pathlib.Path("
        + repr(str(marker))
        + ").write_text('alive')"
    )
    subprocess.Popen([sys.executable, "-c", child])
    time.sleep(30)
if name == "codex":
    answer = Path(args[args.index("--output-last-message") + 1])
    answer.write_text(json.dumps({"ok": True, "fixture": "synthetic-cli"}))
    print(json.dumps({"event": "synthetic-codex"}))
elif mode == "malformed":
    print("not-json")
else:
    print(json.dumps({
        "structured_output": {"ok": True, "fixture": "synthetic-cli"},
        "modelUsage": {"synthetic-claude-model": {}},
    }))
"""


class AgentCliSubprocessE2ETests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.log = self.root / "synthetic-cli.jsonl"
        self.marker = self.root / "descendant-alive"
        self.write_cli("claude")
        self.write_cli("codex")

    def write_cli(self, name):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\n{FAKE_CLI}", encoding="utf-8")
        path.chmod(0o700)

    def plugin(self):
        plugin = self.root / "plugin"
        (plugin / ".claude-plugin").mkdir(parents=True, exist_ok=True)
        (plugin / ".claude-plugin/plugin.json").write_text('{"name":"fixture"}')
        (plugin / "commands").mkdir(exist_ok=True)
        (plugin / "commands/example.md").write_text("Synthetic command.")
        (plugin / "agents").mkdir(exist_ok=True)
        (plugin / "skills/sample").mkdir(parents=True, exist_ok=True)
        (plugin / "skills/sample/SKILL.md").write_text("Synthetic skill.")
        return plugin

    def environment(self, **values):
        environment = {
            "PATH": str(self.bin),
            "HOME": str(self.home),
            "NO_PROXY": "*",
            "SYNTHETIC_CLI_LOG": str(self.log),
            "SYNTHETIC_CLAUDE_AUTH": "0",
            "SYNTHETIC_CODEX_AUTH": "0",
            "SYNTHETIC_EXEC_MODE": "success",
            "SYNTHETIC_CHILD_MARKER": str(self.marker),
        }
        environment.update(values)
        return mock.patch.dict(os.environ, environment, clear=True)

    def invoke_prompt(self, **options):
        return adapter.run_prompt(
            "return the synthetic envelope",
            SCHEMA,
            self.root,
            plugin_root=options.pop("plugin_root", self.plugin()),
            **options,
        )

    def events(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def executions(self):
        return [event for event in self.events() if event["event"] == "execute"]

    def test_claude_to_codex_preflight_fallback_uses_explicit_context(self):
        with self.environment(SYNTHETIC_CODEX_AUTH="1"):
            result = self.invoke_prompt(
                backend="auto", prefer="claude", model="synthetic"
            )
        self.assertEqual(result["status"], "COMPLETED")
        self.assertEqual(result["backend"], "codex")
        self.assertEqual(result["version"], "synthetic-codex 9.9.9")
        self.assertEqual(
            result["fallback"],
            [{"backend": "claude", "reason": "authentication-unavailable"}],
        )
        self.assertEqual(
            self.executions(),
            [
                {
                    "event": "execute",
                    "backend": "codex",
                    "explicit_context": True,
                    "native_plugin": False,
                }
            ],
        )

    def test_codex_to_claude_preflight_fallback_uses_native_plugin(self):
        with self.environment(SYNTHETIC_CLAUDE_AUTH="1"):
            result = self.invoke_prompt(backend="auto", prefer="codex")
        self.assertEqual(result["status"], "COMPLETED")
        self.assertEqual(result["backend"], "claude")
        self.assertEqual(result["version"], "synthetic-claude 9.9.9")
        self.assertEqual(
            result["fallback"],
            [{"backend": "codex", "reason": "authentication-unavailable"}],
        )
        self.assertTrue(self.executions()[0]["native_plugin"])
        self.assertFalse(self.executions()[0]["explicit_context"])

    def test_missing_version_is_preflight_fallback_not_ready_execution(self):
        with self.environment(
            SYNTHETIC_CLAUDE_AUTH="1",
            SYNTHETIC_CLAUDE_VERSION="",
            SYNTHETIC_CODEX_AUTH="1",
        ):
            result = self.invoke_prompt(backend="auto", prefer="claude")
        self.assertEqual(result["status"], "COMPLETED")
        self.assertEqual(result["backend"], "codex")
        self.assertEqual(
            result["fallback"],
            [{"backend": "claude", "reason": "preflight-unavailable"}],
        )
        self.assertEqual([event["backend"] for event in self.executions()], ["codex"])

    def test_neither_and_explicit_unavailable_do_not_execute(self):
        with self.environment():
            neither = self.invoke_prompt(backend="auto", prefer="claude")
        self.assertEqual(neither["status"], "BLOCKED")
        self.assertEqual(len(neither["fallback"]), 2)
        self.assertEqual(self.executions(), [])
        self.log.unlink()
        with self.environment(SYNTHETIC_CODEX_AUTH="1"):
            explicit = self.invoke_prompt(backend="claude", prefer="codex")
        self.assertEqual(explicit["status"], "BLOCKED")
        self.assertEqual(
            explicit["fallback"],
            [{"backend": "claude", "reason": "authentication-unavailable"}],
        )
        self.assertEqual(self.executions(), [])

    def test_started_nonzero_or_malformed_response_never_replays_other_backend(self):
        for mode, expected in (("nonzero", "FAILED"), ("malformed", "BLOCKED")):
            with self.subTest(mode=mode):
                self.log.unlink(missing_ok=True)
                with self.environment(
                    SYNTHETIC_CLAUDE_AUTH="1",
                    SYNTHETIC_CODEX_AUTH="1",
                    SYNTHETIC_EXEC_MODE=mode,
                ):
                    result = self.invoke_prompt(backend="auto", prefer="claude")
                self.assertEqual(result["status"], expected)
                self.assertEqual(
                    [event["backend"] for event in self.executions()], ["claude"]
                )

    @unittest.skipUnless(os.name == "posix", "process groups require POSIX")
    def test_timeout_terminates_synthetic_cli_descendant_process_group(self):
        with self.environment(SYNTHETIC_CODEX_AUTH="1", SYNTHETIC_EXEC_MODE="timeout"):
            result = self.invoke_prompt(backend="codex", timeout=1)
        self.assertEqual(result["status"], "TIMEOUT")
        time.sleep(2.2)
        self.assertFalse(self.marker.exists())


if __name__ == "__main__":
    unittest.main()
