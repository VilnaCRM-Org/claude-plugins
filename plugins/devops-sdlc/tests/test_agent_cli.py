"""Isolation, authentication, output and no-retry adapter contracts."""

import contextlib
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ENTRYPOINT = Path(__file__).resolve().parents[1] / "scripts" / "agent_cli.py"
SPEC = importlib.util.spec_from_file_location("agent_cli_under_test", ENTRYPOINT)
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)
SCHEMA = {"type": "object", "properties": {"ok": {"type": "boolean"}}}


class AgentCliTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def put(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding="utf-8")
        return path

    def plugin(self):
        self.put("plugin/.claude-plugin/plugin.json", '{"name":"fixture"}')
        self.put("plugin/commands/sample.md", "Read this command.")
        self.put("plugin/skills/sample/SKILL.md", "Read this skill.")
        return self.root / "plugin"

    def ready(self, name="codex"):
        return dict(status="READY", backend=name, version="1.2.3", fallback=[])

    def test_probe_missing_invalid_and_detect(self):
        with self.assertRaises(adapter.AdapterError):
            adapter.probe_backend("other")
        with mock.patch.object(adapter.shutil, "which", return_value=None):
            probes = adapter.detect_backends()
        self.assertEqual(len(probes), 2)
        self.assertTrue(all(not p["available"] for p in probes))

    def test_probe_authentication_and_errors(self):
        cases = [
            ("claude", 0, '{"loggedIn":true}', "", True),
            ("claude", 0, "[]", "", False),
            ("claude", 0, '{"loggedIn":false}', "", False),
            ("codex", 0, "", "Logged in using ChatGPT", True),
            ("codex", 0, "Not logged in", "", False),
            ("codex", 1, "Logged in using ChatGPT", "", False),
        ]
        for name, code, stdout, stderr, expected in cases:
            with self.subTest(name=name, stdout=stdout, code=code):
                auth = subprocess.CompletedProcess([], code, stdout, stderr)
                version = subprocess.CompletedProcess([], 0, "1.2.3", "")
                with (
                    mock.patch.object(adapter.shutil, "which", return_value=name),
                    mock.patch.object(
                        adapter, "probe_command", side_effect=[version, auth]
                    ),
                ):
                    result = adapter.probe_backend(name)
                self.assertEqual(result["authenticated"], expected)
        for error in (OSError(), ValueError(), subprocess.TimeoutExpired("a", 1)):
            with (
                mock.patch.object(adapter.shutil, "which", return_value="cli"),
                mock.patch.object(adapter, "probe_command", side_effect=error),
            ):
                self.assertEqual(
                    adapter.probe_backend("codex")["reason"], "preflight-unavailable"
                )
        with (
            mock.patch.object(adapter.shutil, "which", return_value="cli"),
            mock.patch.object(
                adapter,
                "probe_command",
                return_value=subprocess.CompletedProcess([], 0, "", ""),
            ),
        ):
            self.assertIsNone(adapter.probe_backend("codex")["version"])

    def test_probe_command_is_fixed_argv_no_shell(self):
        with mock.patch.object(adapter.subprocess, "run") as run:
            adapter.probe_command(["cli", "--version"])
        self.assertFalse(run.call_args.kwargs["check"])
        self.assertNotIn("shell", run.call_args.kwargs)
        self.assertEqual(run.call_args.kwargs["timeout"], 10)

    def test_selection_preflight_only(self):
        no = dict(authenticated=False, reason="authentication-unavailable")
        yes = dict(authenticated=True, reason="ready", backend="codex")
        with mock.patch.object(
            adapter, "probe_backend", side_effect=[no, yes]
        ) as probe:
            result = adapter.select_backend()
        self.assertEqual(result["backend"], "codex")
        self.assertEqual(len(result["fallback"]), 1)
        self.assertEqual(probe.call_count, 2)
        with mock.patch.object(adapter, "probe_backend", return_value=no) as probe:
            self.assertEqual(adapter.select_backend("claude")["status"], "BLOCKED")
            self.assertEqual(probe.call_count, 1)
        with mock.patch.object(adapter, "probe_backend", return_value=yes):
            self.assertEqual(adapter.select_backend(prefer="codex")["fallback"], [])
        for backend, prefer in (("bad", "claude"), ("auto", "bad")):
            with self.assertRaises(adapter.AdapterError):
                adapter.select_backend(backend, prefer)

    def test_bounded_files(self):
        path = self.put("file", "hello")
        self.assertEqual(adapter.read_bounded(path), "hello")
        for bad, limit in ((path, 1), (self.root / "missing", 100)):
            with self.assertRaises(adapter.AdapterError):
                adapter.read_bounded(bad, limit)
        linked = self.root / "linked"
        linked.symlink_to(path)
        with self.assertRaises(adapter.AdapterError):
            adapter.read_bounded(linked)

    def test_plugin_sources_and_executable_rejection(self):
        self.assertEqual(adapter.plugin_context(None), (None, ""))
        plugin = self.plugin()
        root, context = adapter.plugin_context(plugin)
        self.assertEqual(root, plugin)
        self.assertIn("commands/sample.md", context)
        self.assertIn("skills/sample/SKILL.md", context)
        manifest = plugin / ".claude-plugin/plugin.json"
        for value in ("[]", '{"hooks":{}}', '{"commands":"../outside"}'):
            manifest.write_text(value)
            with self.assertRaises(adapter.AdapterError):
                adapter.plugin_context(plugin)
        manifest.write_text('{"name":"fixture"}')
        hooks = plugin / "hooks"
        hooks.mkdir()
        with self.assertRaises(adapter.AdapterError):
            adapter.plugin_context(plugin)
        hooks.rmdir()
        command = plugin / "commands/sample.md"
        command.write_text("Run !`touch /tmp/unsafe`")
        with self.assertRaises(adapter.AdapterError):
            adapter.plugin_context(plugin)
        command.write_text("x" * 80)
        with mock.patch.object(adapter, "MAX_CONTEXT", 100):
            with self.assertRaises(adapter.AdapterError):
                adapter.plugin_context(plugin)

    def test_plugin_symlinks_missing_and_nested(self):
        with self.assertRaises(adapter.AdapterError):
            adapter.plugin_context(self.root / "missing")
        plugin = self.plugin()
        linked = self.root / "linked"
        linked.symlink_to(plugin, target_is_directory=True)
        with self.assertRaises(adapter.AdapterError):
            adapter.plugin_context(linked)
        commands = plugin / "commands"
        commands.rename(plugin / "moved")
        commands.symlink_to(plugin / "moved", target_is_directory=True)
        with self.assertRaises(adapter.AdapterError):
            adapter.plugin_context(plugin)

    def test_request_validation(self):
        self.assertEqual(
            adapter.validate_request("hello", SCHEMA, self.root, None, 1), self.root
        )
        self.assertEqual(
            adapter.validate_request("hello", SCHEMA, self.root, "model-1", 3600),
            self.root,
        )
        cases = [
            (None, SCHEMA, None, 1),
            ("", SCHEMA, None, 1),
            ("x" * (adapter.MAX_CONTEXT + 1), SCHEMA, None, 1),
            ("x", [], None, 1),
            ("x", {}, None, 1),
            ("x", SCHEMA, None, True),
            ("x", SCHEMA, None, 0),
            ("x", SCHEMA, None, 3601),
            ("x", SCHEMA, 12, 1),
            ("x", SCHEMA, "--unsafe", 1),
        ]
        for prompt, schema, model, timeout in cases:
            with self.subTest(prompt=str(prompt)[:20], model=model, timeout=timeout):
                with self.assertRaises(adapter.AdapterError):
                    adapter.validate_request(prompt, schema, self.root, model, timeout)
        with self.assertRaises(adapter.AdapterError):
            adapter.validate_request("x", SCHEMA, self.root / "missing", None, 1)
        linked = self.root / "linked"
        linked.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(adapter.AdapterError):
            adapter.validate_request("x", SCHEMA, linked, None, 1)
        self.put(".codex/config.toml", "[mcp_servers.danger]")
        with self.assertRaises(adapter.AdapterError):
            adapter.validate_request("x", SCHEMA, self.root, None, 1)

    def test_argv_isolation(self):
        with mock.patch.object(adapter.shutil, "which", return_value=None):
            with self.assertRaises(adapter.AdapterError):
                adapter.evaluation_argv(
                    "codex", SCHEMA, self.root, self.root, None, None
                )
        with mock.patch.object(adapter.shutil, "which", return_value="/bin/cli"):
            for backend in adapter.BACKENDS:
                argv = adapter.evaluation_argv(
                    backend, SCHEMA, self.root, self.root, "exact-model", self.root
                )
                self.assertEqual(argv[-2:], ["--model", "exact-model"])
                if backend == "claude":
                    self.assertEqual(argv[argv.index("--tools") + 1], "")
                    self.assertIn("--strict-mcp-config", argv)
                    self.assertIn("--plugin-dir", argv)
                else:
                    self.assertIn("--ignore-user-config", argv)
                    self.assertIn("features.shell_tool=false", argv)
                    self.assertIn("read-only", argv)
                    self.assertEqual(
                        json.loads((self.root / "schema.json").read_text()), SCHEMA
                    )
            argv = adapter.evaluation_argv(
                "claude", SCHEMA, self.root, self.root, None, None
            )
            self.assertNotIn("--model", argv)
            self.assertNotIn("--plugin-dir", argv)

    def test_invoke_and_group_timeout(self):
        process = mock.Mock(returncode=0, pid=321)
        with mock.patch.object(
            adapter.subprocess, "Popen", return_value=process
        ) as popen:
            self.assertEqual(
                adapter.invoke(["cli"], "prompt", self.root, self.root, 1), (0, "")
            )
        self.assertEqual(popen.call_args.kwargs["stderr"], subprocess.DEVNULL)
        self.assertNotIn("shell", popen.call_args.kwargs)
        process.communicate.side_effect = subprocess.TimeoutExpired("cli", 1)
        with (
            mock.patch.object(adapter.subprocess, "Popen", return_value=process),
            mock.patch.object(adapter, "terminate") as terminate,
        ):
            with self.assertRaises(subprocess.TimeoutExpired):
                adapter.invoke(["cli"], "prompt", self.root, self.root, 1)
        terminate.assert_called_once_with(process)
        with (
            mock.patch.object(adapter.os, "name", "posix"),
            mock.patch.object(adapter.os, "killpg") as kill,
        ):
            adapter.terminate(process)
        kill.assert_called_once_with(321, adapter.signal.SIGKILL)
        with mock.patch.object(adapter.os, "name", "nt"):
            adapter.terminate(process)
        process.kill.assert_called_once()
        with mock.patch.object(adapter.os, "killpg", side_effect=ProcessLookupError()):
            adapter.terminate(process)

    def test_decode_envelopes(self):
        self.put("answer.json", '{"ok":true}')
        self.assertEqual(
            adapter.decode_answer("codex", "", self.root), ({"ok": True}, None)
        )
        for envelope, model in (
            (
                {"structured_output": {"ok": True}, "modelUsage": {"observed": {}}},
                "observed",
            ),
            ({"result": '{"ok":true}'}, None),
            ({"structured_output": {}, "modelUsage": []}, None),
            ({"structured_output": {}, "modelUsage": {"a": {}, "b": {}}}, None),
        ):
            answer, observed = adapter.decode_answer(
                "claude", json.dumps(envelope), self.root
            )
            self.assertIsInstance(answer, dict)
            self.assertEqual(observed, model)
        for raw in ("[]", '{"is_error":true}', '{"structured_output":[]}', "bad"):
            with self.assertRaises(ValueError):
                adapter.decode_answer("claude", raw, self.root)

    def test_run_success_metadata_native_and_explicit(self):
        plugin = self.plugin()
        for backend in adapter.BACKENDS:

            def invoke(argv, prompt, cwd, temporary, timeout):
                if backend == "codex":
                    self.assertIn("explicit plugin source context", prompt)
                    self.assertIn("Read this skill", prompt)
                    (temporary / "answer.json").write_text('{"ok":true}')
                else:
                    self.assertEqual(prompt, "question")
                    self.assertIn("--plugin-dir", argv)
                return (
                    0,
                    '{"structured_output":{"ok":true},"modelUsage":{"observed":{}}}',
                )

            with (
                mock.patch.object(
                    adapter, "select_backend", return_value=self.ready(backend)
                ),
                mock.patch.object(adapter.shutil, "which", return_value="cli"),
                mock.patch.object(adapter, "invoke", side_effect=invoke),
            ):
                result = adapter.run_prompt(
                    "question", SCHEMA, self.root, plugin_root=plugin
                )
            self.assertEqual(result["status"], "COMPLETED")
            self.assertEqual(result["output"], {"ok": True})
            self.assertEqual(
                result["model"], "observed" if backend == "claude" else None
            )
            self.assertEqual(
                result["plugin_mode"],
                "native-claude" if backend == "claude" else "explicit-context",
            )

    def test_started_failure_never_falls_back(self):
        cases = [
            (None, (1, ""), "FAILED"),
            (subprocess.TimeoutExpired("cli", 1), None, "TIMEOUT"),
            (OSError("SECRET"), None, "BLOCKED"),
            (None, (0, "invalid"), "BLOCKED"),
        ]
        for error, returned, expected in cases:
            with (
                mock.patch.object(
                    adapter, "select_backend", return_value=self.ready("claude")
                ) as select,
                mock.patch.object(adapter.shutil, "which", return_value="cli"),
                mock.patch.object(
                    adapter, "invoke", side_effect=error, return_value=returned
                ) as invoke,
            ):
                result = adapter.run_prompt("question", SCHEMA, self.root)
            self.assertEqual(result["status"], expected)
            self.assertNotIn("SECRET", json.dumps(result))
            self.assertEqual(invoke.call_count, 1)
            self.assertEqual(select.call_count, 1)
        with mock.patch.object(
            adapter,
            "select_backend",
            return_value=dict(
                status="BLOCKED",
                backend=None,
                version=None,
                fallback=[],
                reason="no auth",
            ),
        ):
            result = adapter.run_prompt("question", SCHEMA, self.root)
        self.assertEqual(result["reason"], "no auth")

    def test_model_provenance(self):
        self.assertEqual(adapter.model_provenance("actual", "alias"), "observed")
        self.assertEqual(adapter.model_provenance(None, "alias"), "requested")
        self.assertEqual(adapter.model_provenance(None, None), "unreported")
        with (
            mock.patch.object(
                adapter, "select_backend", return_value=self.ready("claude")
            ),
            mock.patch.object(adapter.shutil, "which", return_value="cli"),
            mock.patch.object(
                adapter, "invoke", return_value=(0, '{"structured_output":{}}')
            ),
        ):
            result = adapter.run_prompt("question", SCHEMA, self.root, model="alias")
        self.assertEqual(result["model"], "alias")
        self.assertIsNone(result["observed_model"])
        self.assertEqual(result["model_source"], "requested")

    def test_cli(self):
        with (
            mock.patch.object(adapter, "select_backend", return_value=self.ready()),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            self.assertEqual(adapter.main(["detect"]), 0)
        self.assertEqual(json.loads(output.getvalue())["backend"], "codex")
        schema = self.put("schema.json", json.dumps(SCHEMA))
        with (
            mock.patch.object(
                adapter, "run_prompt", return_value={"status": "COMPLETED"}
            ),
            mock.patch.object(adapter.sys, "stdin", io.StringIO("question")),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(adapter.main(["run", "--schema", str(schema)]), 0)
        for argv in (["run"], ["run", "--schema", str(schema) + ".missing"]):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(adapter.main(argv), 2)
            self.assertEqual(json.loads(output.getvalue())["status"], "BLOCKED")


if __name__ == "__main__":
    unittest.main()
