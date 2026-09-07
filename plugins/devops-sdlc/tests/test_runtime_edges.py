"""Edge contracts for the DevOps runtime; test observable safety, not internals."""

from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ENTRYPOINT = Path(__file__).resolve().parents[1] / "scripts" / "devops.py"
SPEC = importlib.util.spec_from_file_location("devops_runtime_edges", ENTRYPOINT)
runtime = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(runtime)


class RuntimeEdgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.put("README.md", "fixture\n")
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "-c",
                "user.name=x",
                "-c",
                "user.email=x@y.z",
                "commit",
                "-qm",
                "x",
            ],
            check=True,
        )
        self.profile = self.make_profile()
        self.save_profile()

    def put(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def make_profile(self):
        commands = {stage: None for stage in runtime.STAGES}
        commands["validate"] = {
            "argv": ["make", "test-pulumi"],
            "requires_credentials": False,
        }
        commands["preview"] = {
            "argv": ["pulumi", "preview", "--stack", "{stack}", "--non-interactive"],
            "requires_credentials": True,
        }
        return {
            "schema_version": 1,
            "project": {"name": "x", "repo": "o/r"},
            "targets": [
                {
                    "id": "target",
                    "stack_type": "pulumi",
                    "root": ".",
                    "environments": {
                        "dev": {
                            "stack": "org/project/dev",
                            "account_id": "123456789012",
                            "region": "eu-west-1",
                            "backend": "s3://safe-state",
                        }
                    },
                    "commands": commands,
                }
            ],
        }

    def save_profile(self):
        self.put(runtime.PROFILE, json.dumps(self.profile))

    def plan(self, stage="validate", environment=None):
        return runtime.build_plan(
            self.root, runtime.PROFILE, "target", stage, environment, now=1000
        )

    def test_strict_json_and_path_tables(self):
        for contents in ('{"x":NaN}', '{"x":1,"x":2}', "[1]", "null", "not-json", ""):
            path = self.put("bad.json", contents)
            with self.subTest(contents=contents), self.assertRaises(runtime.Invalid):
                runtime.load_json(path)
        for value in ("../x", "/tmp", "a//b", "a/./b", "a\\b"):
            with self.subTest(path=value), self.assertRaises(runtime.Invalid):
                runtime.contained(self.root, value, must_exist=False)

    def test_discovery_bounds_mixed_and_secret_metadata(self):
        self.put("terraform/main.tf", "resource {}")
        self.put("pulumi/Pulumi.yaml", "name: x")
        self.put("terraspace/Gemfile", "source 'x'")
        (self.root / "terraspace/app/stacks").mkdir(parents=True)
        result = runtime.discover(self.root)
        self.assertEqual(
            {item["stack_type"] for item in result["candidates"]}, runtime.ENGINES
        )
        self.put("pulumi/Pulumi.dev.yaml", "secret-value")
        source = self.plan()["source"]
        self.assertIn("pulumi/Pulumi.dev.yaml", source["excluded_sensitive_paths"])
        self.assertNotIn("secret-value", json.dumps(source))
        with (
            mock.patch.object(runtime, "MAX_FILES", 0),
            self.assertRaises(runtime.Invalid),
        ):
            list(runtime.bounded_files(self.root))

    def test_argv_engine_selector_and_output_confinement(self):
        cases = [
            (["terraform", "validate"], "validate", "pulumi"),
            (["make", "pulumi-preview", "out=../../x"], "preview", "pulumi"),
        ]
        for argv, stage, engine in cases:
            with self.subTest(argv=argv), self.assertRaises(runtime.Invalid):
                runtime.allowed_argv(argv, stage, engine)
        target = self.profile["targets"][0]
        with self.assertRaises(runtime.Invalid):
            runtime.bind_selectors(
                ["pulumi", "preview", "--stack", "prod", "--non-interactive"],
                target,
                "dev",
                target["environments"]["dev"],
            )

    def test_source_evidence_and_execution_guards(self):
        plan = self.plan()
        name = runtime.ARTIFACT_ROOT + "/plan.json"
        runtime.write_plan(self.root, name, plan)
        self.put("README.md", "changed")
        with self.assertRaises(runtime.Invalid):
            runtime.verify_plan(self.root, name, now=1001)
        for trusted, credentials in ((False, False), (True, True)):
            with (
                self.subTest(trusted=trusted, credentials=credentials),
                self.assertRaises(runtime.Invalid),
            ):
                runtime.execute_plan(
                    self.root,
                    plan,
                    trust_repo=trusted,
                    read_only_credentials=credentials,
                )

    def test_git_subprocess_timeout_and_secret_output_suppression(self):
        with mock.patch.object(
            runtime.subprocess, "run", side_effect=subprocess.TimeoutExpired("git", 1)
        ):
            with self.assertRaises(runtime.Invalid):
                runtime.git_output(self.root, ["rev-parse", "HEAD"])
        plan = self.plan()
        process = mock.Mock()
        process.wait.return_value = 7
        process.pid = 1
        with mock.patch.object(runtime.subprocess, "Popen", return_value=process):
            result = runtime.run_process(plan, self.root, {}, 1)
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["semantic_result"], "UNVERIFIED")
        self.assertEqual(result["output"], "suppressed")

    def test_environment_and_stale_preview_guards(self):
        plan = self.plan("preview", "dev")
        self.assertEqual(
            runtime.execution_environment(plan)["PULUMI_STACK"], "org/project/dev"
        )
        changed = copy.deepcopy(plan)
        changed["source"]["git_sha"] = "0" * 40
        with self.assertRaises(runtime.Invalid):
            runtime.execute_plan(
                self.root, changed, trust_repo=True, read_only_credentials=True
            )
        with mock.patch.object(
            runtime.subprocess, "run", side_effect=OSError("missing aws")
        ):
            with self.assertRaises(runtime.Invalid):
                runtime.verify_aws_account(plan, {}, {"aws_executable": "/usr/bin/aws"})

    def test_engine_and_uv_allowlist_table(self):
        allowed = [
            (["terraform", "validate"], "validate", "terraform"),
            (["terraform", "fmt", "-check"], "check", "terraform"),
            (
                ["terraform", "plan", "-input=false", "-lock=true"],
                "preview",
                "terraform",
            ),
            (["terraspace", "validate", "dev"], "validate", "terraspace"),
            (["terraspace", "plan", "dev"], "preview", "terraspace"),
            (
                ["pulumi", "preview", "--stack", "org/dev", "--non-interactive"],
                "preview",
                "pulumi",
            ),
            (["uv", "run", "pytest", "-q", "tests"], "test", "pulumi"),
            (["uv", "run", "ruff", "format", "--check", "scripts"], "check", "pulumi"),
        ]
        for argv, stage, engine in allowed:
            with self.subTest(argv=argv):
                runtime.allowed_argv(argv, stage, engine)
        for argv in (
            ["uv", "run", "ruff", "format", "scripts"],
            ["uv", "run", "pytest", "-p", "x"],
        ):
            with self.subTest(argv=argv), self.assertRaises(runtime.Invalid):
                runtime.allowed_argv(
                    argv, "check" if "ruff" in argv else "test", "pulumi"
                )

    def test_environment_source_helpers_and_account_mismatch(self):
        values = {
            "stack": "org/project/dev",
            "account_id": "123456789012",
            "region": "eu-west-1",
            "backend": "file:///tmp/state",
        }
        self.assertEqual(runtime.environment_config(values), values)
        for invalid in ("secret.pem", ".env", "terraform.tfstate", "plain.txt"):
            with self.subTest(name=invalid):
                self.assertEqual(runtime.secret_path(invalid), invalid != "plain.txt")
        self.assertEqual(runtime.source_metadata(self.root / "missing"), None)
        with self.assertRaises(runtime.Invalid):
            runtime.source_filename(b"\xff")
        plan = self.plan("preview", "dev")
        result = mock.Mock(returncode=0, stdout=b"000000000000\n")
        with mock.patch.object(runtime.subprocess, "run", return_value=result):
            with self.assertRaises(runtime.Invalid):
                runtime.verify_aws_account(plan, {}, {"aws_executable": "/usr/bin/aws"})

    def test_process_start_error_timeout_and_termination_paths(self):
        plan = self.plan()
        with mock.patch.object(
            runtime.subprocess, "Popen", side_effect=OSError("missing")
        ):
            with self.assertRaises(runtime.Invalid):
                runtime.run_process(plan, self.root, {}, 1)
        process = mock.Mock(pid=999)
        process.wait.side_effect = [subprocess.TimeoutExpired("make", 1), 9]
        with (
            mock.patch.object(runtime.subprocess, "Popen", return_value=process),
            mock.patch.object(runtime, "terminate_process_tree") as terminated,
        ):
            result = runtime.run_process(plan, self.root, {}, 1)
        self.assertEqual(result["status"], "TIMEOUT")
        terminated.assert_called_once_with(process)

    def test_scalar_profile_and_engine_prefix_rejections(self):
        invalid_scalars = [
            lambda: runtime.string("bad\n"),
            lambda: runtime.integer(True, 1, 2),
            lambda: runtime.identifier("bad space"),
            lambda: runtime.environment_config(
                {
                    "stack": "dev",
                    "account_id": "123456789012",
                    "region": "bad",
                    "backend": "s3://state",
                }
            ),
        ]
        for check in invalid_scalars:
            with self.subTest(check=check), self.assertRaises(runtime.Invalid):
                check()
        for argv, engine in (
            (["make", "pulumi-preview"], "terraform"),
            (["make", "terraspace-plan"], "pulumi"),
        ):
            with self.subTest(argv=argv), self.assertRaises(runtime.Invalid):
                runtime.allowed_argv(argv, "preview", engine)

    def test_secure_evidence_write_and_platform_failures(self):
        plan = self.plan()
        name = runtime.ARTIFACT_ROOT + "/nested/intent.json"
        runtime.write_plan(self.root, name, plan)
        evidence = self.root / name
        self.assertEqual(evidence.stat().st_mode & 0o777, 0o600)
        with self.assertRaises(runtime.Invalid):
            runtime.write_plan(self.root, name, plan)
        with mock.patch.object(runtime.os, "name", "nt"):
            with self.assertRaises(runtime.Invalid):
                runtime.secure_directory(self.root)
        blocked = runtime.ARTIFACT_ROOT + "/blocked.json"
        with mock.patch.object(
            runtime, "secure_directory", side_effect=OSError("race")
        ):
            with self.assertRaises(OSError):
                runtime.write_plan(self.root, blocked, plan)
        self.assertFalse((self.root / blocked).exists())

    def test_snapshot_cli_and_termination_error_paths(self):
        responses = [
            b"README.md\0.claude/devops-sdlc.json\0dist/a\0",
            b".cache/x\0new.txt\0",
        ]
        with mock.patch.object(runtime, "git_output", side_effect=responses):
            self.assertEqual(
                runtime.snapshot_paths(self.root, runtime.PROFILE),
                [b"README.md", b"dist/a", b"new.txt"],
            )
        with (
            mock.patch.object(runtime, "MAX_FILES", 0),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.snapshot_paths(self.root, runtime.PROFILE)
        with (
            mock.patch.object(runtime.os, "name", "posix"),
            mock.patch.object(runtime.os, "killpg", side_effect=ProcessLookupError),
        ):
            runtime.terminate_process_tree(mock.Mock(pid=1))
        process = mock.Mock()
        with mock.patch.object(runtime.os, "name", "nt"):
            runtime.terminate_process_tree(process)
        process.kill.assert_called_once()
        for command in ("discover", "validate-profile"):
            with (
                self.subTest(command=command),
                contextlib.redirect_stdout(io.StringIO()) as output,
            ):
                code = runtime.main([command, "--repo", str(self.root)])
            self.assertEqual(code, 0)
            self.assertTrue(json.loads(output.getvalue()))

    def test_basic_input_missing_path_and_discovery_make_boundaries(self):
        for check in (
            lambda: runtime.exact_keys([], {"x"}),
            lambda: runtime.repository(str(self.root / "missing")),
            lambda: runtime.contained(self.root, "missing"),
            lambda: runtime.lexical_argv("make"),
        ):
            with self.subTest(check=check), self.assertRaises(runtime.Invalid):
                check()
        link = self.root / "repo-link"
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(runtime.Invalid):
            runtime.repository(str(link))
        self.put("Makefile", "target: ; true\n")
        with (
            mock.patch.object(runtime, "MAX_FILE_BYTES", 1),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.discover_make(self.root, self.root)

    def test_profile_snapshot_and_command_placeholder_boundaries(self):
        invalid = copy.deepcopy(self.profile)
        invalid["targets"] = []
        self.put(runtime.PROFILE, json.dumps(invalid))
        with self.assertRaises(runtime.Invalid):
            runtime.validate_profile(self.root)
        self.save_profile()
        target = self.profile["targets"][0]
        command = {
            "argv": ["pulumi", "preview", "--stack", "{stack}", "--non-interactive"],
            "requires_credentials": True,
        }
        with self.assertRaises(runtime.Invalid):
            runtime.command_argv(self.root, target, command, "preview", None, None)
        responses = [b"a\0b\0", b""]
        with (
            mock.patch.object(runtime, "git_output", side_effect=responses),
            mock.patch.object(runtime, "MAX_FILES", 0),
        ):
            with self.assertRaises(runtime.Invalid):
                runtime.snapshot_paths(self.root, runtime.PROFILE)
        with self.assertRaises(runtime.Invalid):
            runtime.build_plan(self.root, runtime.PROFILE, "target", "unknown", None)

    def test_verify_cli_output_and_credential_copy_paths(self):
        plan = self.plan()
        name = runtime.ARTIFACT_ROOT + "/verify.json"
        runtime.write_plan(self.root, name, plan)
        with (
            mock.patch.object(runtime.time, "time", return_value=1001),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            code = runtime.main(
                ["verify-plan", "--repo", str(self.root), "--plan", name]
            )
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output.getvalue())["status"], "VERIFIED")
        preview = self.plan("preview", "dev")
        with mock.patch.dict(os.environ, {"AWS_PROFILE": "fixture"}, clear=False):
            env = runtime.execution_environment(preview)
        self.assertNotIn("AWS_PROFILE", env)

    def test_source_selector_and_confined_output_fail_closed(self):
        valid_sha = b"a" * 40 + b"\n"
        with mock.patch.object(runtime, "git_output", side_effect=[b"not-a-sha\n"]):
            with self.assertRaises(runtime.Invalid):
                runtime.source_identity(self.root, runtime.PROFILE)
        (self.root / "submodule").mkdir()
        with mock.patch.object(
            runtime, "git_output", side_effect=[valid_sha, b"submodule\0", b""]
        ):
            with self.assertRaises(runtime.Invalid):
                runtime.source_identity(self.root, runtime.PROFILE)
        with (
            mock.patch.object(
                runtime, "git_output", side_effect=[valid_sha, b"README.md\0", b""]
            ),
            mock.patch.object(runtime, "MAX_SOURCE_BYTES", 0),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.source_identity(self.root, runtime.PROFILE)
        target = self.profile["targets"][0]
        env = target["environments"]["dev"]
        for argv in (
            ["make", "test-pulumi", "stack=other"],
            ["make", "test-pulumi", "stacks=all"],
        ):
            with self.subTest(argv=argv), self.assertRaises(runtime.Invalid):
                runtime.bind_selectors(argv, target, "dev", env)
        with self.assertRaises(runtime.Invalid):
            runtime.bind_output_path(
                self.root,
                target,
                ["make", "test", "out=.artifacts/devops-sdlc/engine-plans"],
            )
        command = {
            "argv": ["uv", "run", "pytest", "missing"],
            "requires_credentials": False,
        }
        with self.assertRaises(runtime.Invalid):
            runtime.command_argv(self.root, target, command, "test", None, None)

    def test_safe_write_profile_and_execution_edge_paths(self):
        with (
            mock.patch.object(runtime.os, "open", side_effect=[10, OSError("race")]),
            mock.patch.object(runtime.os, "close") as close,
            self.assertRaises(OSError),
        ):
            runtime.secure_directory(Path("/race"))
        close.assert_called_with(10)
        for project in (
            {"name": "x", "repo": "bad repo"},
            {"name": "x" * 161, "repo": "o/r"},
        ):
            invalid = copy.deepcopy(self.profile)
            invalid["project"] = project
            self.put(runtime.PROFILE, json.dumps(invalid))
            with self.subTest(project=project), self.assertRaises(runtime.Invalid):
                runtime.validate_profile(self.root)
        self.save_profile()
        skipped = self.plan("test")
        self.assertEqual(
            runtime.execute_plan(
                self.root, skipped, trust_repo=False, read_only_credentials=False
            )["status"],
            "SKIPPED",
        )
        terraform = copy.deepcopy(self.profile)
        target = terraform["targets"][0]
        target["stack_type"] = "terraform"
        target["commands"]["preview"] = {
            "argv": ["terraform", "plan", "-input=false", "-lock=true"],
            "requires_credentials": True,
        }
        self.put(runtime.PROFILE, json.dumps(terraform))
        plan = self.plan("preview", "dev")
        with self.assertRaises(runtime.Invalid):
            runtime.execute_plan(
                self.root, plan, trust_repo=True, read_only_credentials=False
            )
        with self.assertRaises(runtime.Invalid):
            runtime.execute_plan(
                self.root, plan, trust_repo=True, read_only_credentials=True
            )

    def test_cli_plan_output_execute_and_account_success(self):
        output_name = runtime.ARTIFACT_ROOT + "/cli.json"
        with (
            mock.patch.object(runtime.time, "time", return_value=1000),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            code = runtime.main(
                [
                    "plan",
                    "--repo",
                    str(self.root),
                    "--target",
                    "target",
                    "--stage",
                    "validate",
                    "--output",
                    output_name,
                ]
            )
        self.assertEqual(code, 0)
        self.assertTrue((self.root / output_name).is_file())
        self.assertEqual(
            json.loads(output.getvalue())["intention"]["status"], "PLANNED"
        )
        with (
            mock.patch.object(
                runtime, "execute_plan", return_value={"status": "COMPLETED"}
            ),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            code = runtime.main(
                [
                    "plan",
                    "--repo",
                    str(self.root),
                    "--target",
                    "target",
                    "--stage",
                    "validate",
                    "--execute",
                    "--trust-repo",
                ]
            )
        self.assertEqual(code, 0)
        self.assertEqual(
            json.loads(output.getvalue())["execution"]["status"], "COMPLETED"
        )
        plan = self.plan("preview", "dev")
        identity = {
            "Account": "123456789012",
            "Arn": "fixture-role",
            "UserId": "fixture-session",
        }
        result = mock.Mock(returncode=0, stdout=json.dumps(identity).encode())
        grant = {
            "aws_executable": "/usr/bin/aws",
            "principal_arn": identity["Arn"],
            "principal_id": identity["UserId"],
        }
        with mock.patch.object(runtime.subprocess, "run", return_value=result):
            runtime.verify_aws_account(
                plan, {"AWS_SESSION_TOKEN": "not-emitted"}, grant
            )

    def test_extracted_input_predicates_reject_unsafe_boundaries(self):
        with mock.patch.object(Path, "resolve", return_value=Path("/outside")):
            with self.assertRaises(runtime.Invalid):
                runtime.contained(self.root, "safe", must_exist=False)
        oversized = self.put("large.json", "{}")
        with (
            mock.patch.object(runtime, "MAX_FILE_BYTES", 1),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.load_json(oversized)
        link = self.root / "walk-link"
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(runtime.Invalid):
            list(runtime.bounded_files(link))
        file_link = self.root / "file-link"
        file_link.symlink_to(self.root / "README.md")
        self.assertFalse(runtime.regular_discovery_file(file_link))
        self.assertNotIn(file_link, list(runtime.bounded_files(self.root)))
        values = self.profile["targets"][0]["environments"]["dev"].copy()
        values["backend"] = "s3://state/../escape"
        with self.assertRaises(runtime.Invalid):
            runtime.environment_config(values)
        runtime.validate_argument_path("s3://state/path", expanded=True)
        runtime.validate_argument_path("https://state/../path", expanded=True)
        with self.assertRaises(runtime.Invalid):
            runtime.validate_argument_path("/tmp/path", expanded=True)
        self.assertFalse(runtime.allowed_terraspace(["plan"], "preview"))
        self.assertFalse(runtime.allowed_pulumi(["preview"], "preview"))
        self.assertFalse(runtime.allowed_ruff([]))
        invalid = copy.deepcopy(self.profile)
        invalid["targets"][0]["stack_type"] = "unknown"
        self.put(runtime.PROFILE, json.dumps(invalid))
        with self.assertRaises(runtime.Invalid):
            runtime.validate_profile(self.root)
        invalid = copy.deepcopy(self.profile)
        invalid["targets"][0]["root"] = "README.md"
        self.put(runtime.PROFILE, json.dumps(invalid))
        with self.assertRaises(runtime.Invalid):
            runtime.validate_profile(self.root)
        self.save_profile()

    def test_missing_source_preview_verification_and_pulumi_run_paths(self):
        valid_sha = b"b" * 40 + b"\n"
        with mock.patch.object(
            runtime, "git_output", side_effect=[valid_sha, b"missing-source\0", b""]
        ):
            source = runtime.source_identity(self.root, runtime.PROFILE)
        self.assertEqual(len(source["source_sha256"]), 64)
        result = mock.Mock(returncode=1, stdout=b"ignored-secret")
        with mock.patch.object(runtime.subprocess, "run", return_value=result):
            with self.assertRaises(runtime.Invalid):
                runtime.git_output(self.root, ["rev-parse", "HEAD"])
        (self.root / "tests").mkdir()
        self.put("tests/test_safe.py", "pass\n")
        target = self.profile["targets"][0]
        command = {
            "argv": ["uv", "run", "pytest", "tests/test_safe.py"],
            "requires_credentials": False,
        }
        self.assertEqual(
            runtime.command_argv(self.root, target, command, "test", None, None),
            command["argv"],
        )
        runtime.bind_output_path(self.root, target, ["make", "test-pulumi"])
        runtime.bind_make_selectors(
            ["make", "test-pulumi", "stack=org/project/dev"],
            target,
            "dev",
            target["environments"]["dev"],
        )
        runtime.bind_output_path(
            self.root,
            target,
            ["make", "test-pulumi", "env=dev"],
        )
        runtime.bind_output_path(
            self.root,
            target,
            [
                "make",
                "test-pulumi",
                "out=.artifacts/devops-sdlc/engine-plans/new.json",
            ],
        )
        preview = self.plan("preview", "dev")
        name = runtime.ARTIFACT_ROOT + "/preview.json"
        runtime.write_plan(self.root, name, preview)
        self.assertEqual(
            runtime.verify_plan(self.root, name, now=1001)["status"], "VERIFIED"
        )
        with (
            mock.patch.object(runtime, "verify_aws_account") as account,
            mock.patch.object(
                runtime,
                "authorize_preview",
                return_value={"executable": "/usr/bin/pulumi", "expires_at": 1100},
            ),
            mock.patch.object(runtime, "preview_environment", return_value={}),
            mock.patch.object(runtime, "validate_grant_time"),
            mock.patch.object(
                runtime, "run_process", return_value={"status": "COMPLETED"}
            ),
        ):
            result = runtime.execute_plan(
                self.root, preview, trust_repo=True, read_only_credentials=True
            )
        self.assertEqual(result["status"], "COMPLETED")
        account.assert_called_once()


if __name__ == "__main__":
    unittest.main()
