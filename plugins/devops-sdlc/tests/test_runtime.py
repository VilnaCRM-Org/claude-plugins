"""Runtime boundary checks, including subprocess and adversarial fixtures."""

import contextlib
import copy
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

ENTRYPOINT = Path(__file__).resolve().parents[1] / "scripts" / "devops.py"
SPEC = importlib.util.spec_from_file_location("devops_runtime", ENTRYPOINT)
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.put("README.md", "fixture\n")
        subprocess.run(["git", "-C", str(self.root), "add", "README.md"], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "-qm",
                "fixture",
            ],
            check=True,
        )
        self.profile = {
            "schema_version": 1,
            "project": {"name": "Fixture", "repo": "example/fixture"},
            "targets": [
                {
                    "id": "infra",
                    "stack_type": "pulumi",
                    "root": ".",
                    "environments": {
                        "test": {
                            "stack": "org/project/test",
                            "account_id": "123456789012",
                            "region": "eu-west-1",
                            "backend": "s3://example-state",
                        }
                    },
                    "commands": {
                        "validate": {
                            "argv": ["make", "test-pulumi"],
                            "requires_credentials": False,
                        },
                        "test": {
                            "argv": ["uv", "run", "pytest", "-q", "tests"],
                            "requires_credentials": False,
                        },
                        "check": None,
                        "security": None,
                        "preview": {
                            "argv": [
                                "pulumi",
                                "preview",
                                "--stack",
                                "{stack}",
                                "--non-interactive",
                            ],
                            "requires_credentials": True,
                        },
                    },
                }
            ],
        }
        self.save_profile()

    def put(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def save_profile(self):
        self.put(runtime.PROFILE, json.dumps(self.profile))

    def plan(self, stage="validate", environment=None, now=1000):
        return runtime.build_plan(
            self.root, runtime.PROFILE, "infra", stage, environment, now=now
        )

    def test_discovery_is_text_only_and_multi_engine(self):
        self.put("Makefile", "$(shell touch SHOULD_NOT_EXIST)\ntest: ; echo fixture\n")
        self.put("pulumi/Pulumi.yaml", "name: fixture\n")
        self.put("pulumi/Pulumi.test.yaml", "secure: never-read\n")
        self.put("terraform/Gemfile", "source 'example'\n")
        self.put("terraform/app/stacks/website/main.tf", "resource {}\n")
        self.put("terraform/app/stacks/website/tfvars/test.tfvars", "fixture\n")
        self.put("raw/main.tf", "resource {}\n")
        with mock.patch.object(
            runtime.subprocess,
            "run",
            side_effect=AssertionError("No commands during discovery"),
        ):
            result = runtime.discover(self.root)
        self.assertEqual(
            {row["stack_type"] for row in result["candidates"]}, runtime.ENGINES
        )
        self.assertFalse((self.root / "SHOULD_NOT_EXIST").exists())
        self.assertIn("test", result["candidates"][0]["make_targets"])
        self.assertFalse(result["executed"])

    def test_cli_discovery_includes_pulumi_yaml_and_yml_stack_configs(self):
        self.put("pulumi/Pulumi.yml", "name: fixture\n")
        self.put("pulumi/Pulumi.test.yml", "secure: SECRET_SENTINEL_YML\n")
        self.put("pulumi/Pulumi.test.yaml", "secure: SECRET_SENTINEL_YAML\n")
        external = tempfile.TemporaryDirectory()
        self.addCleanup(external.cleanup)
        symlink_target = Path(external.name) / "Pulumi.link.yaml"
        symlink_target.write_text("secure: SECRET_SENTINEL_SYMLINK\n")
        (self.root / "pulumi" / "Pulumi.link.yaml").symlink_to(symlink_target)

        completed = subprocess.run(
            [
                sys.executable,
                str(ENTRYPOINT),
                "discover",
                "--repo",
                str(self.root),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(completed.stdout)
        [candidate] = result["candidates"]

        self.assertEqual(candidate["root"], "pulumi")
        self.assertEqual(
            candidate["configuration_filenames"],
            ["pulumi/Pulumi.test.yaml", "pulumi/Pulumi.test.yml"],
        )
        self.assertEqual(
            candidate["configuration_filenames"],
            sorted(candidate["configuration_filenames"]),
        )
        self.assertNotIn(
            "pulumi/Pulumi.link.yaml", candidate["configuration_filenames"]
        )
        self.assertNotIn("SECRET_SENTINEL", completed.stdout)
        self.assertNotIn("SECRET_SENTINEL", completed.stderr)

    def test_discovery_skips_symlinked_external_tree(self):
        (self.root / "elsewhere").symlink_to("/tmp", target_is_directory=True)
        self.assertEqual(runtime.discover(self.root)["candidates"], [])

    def test_valid_profile_and_exact_preview_placeholder(self):
        self.assertEqual(runtime.validate_profile(self.root)["schema_version"], 1)
        result = self.plan("preview", "test")
        self.assertEqual(result["argv"][3], "org/project/test")
        self.assertEqual(result["environment"], "test")
        self.assertEqual(result["kind"], "command-intention")
        self.assertFalse(result["executed"])

    def test_invalid_types_keys_and_selectors(self):
        mutations = [
            lambda p: p.update(schema_version=True),
            lambda p: p.update(extra="no"),
            lambda p: p["project"].update(repo=""),
            lambda p: p["targets"].append(copy.deepcopy(p["targets"][0])),
            lambda p: p["targets"][0].update(root="../escape"),
            lambda p: p["targets"][0].update(root="/tmp"),
            lambda p: p["targets"][0].update(environments=[]),
            lambda p: p["targets"][0]["commands"]["validate"].update(
                requires_credentials=0
            ),
            lambda p: p["targets"][0]["commands"]["validate"].update(
                requires_credentials=True
            ),
            lambda p: p["targets"][0]["environments"]["test"].update(
                account_id="wrong"
            ),
            lambda p: p["targets"][0]["environments"]["test"].update(
                backend="https://token@example.com"
            ),
            lambda p: p["targets"][0]["environments"]["test"].update(stack="../prod"),
        ]
        baseline = copy.deepcopy(self.profile)
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.profile = copy.deepcopy(baseline)
                mutation(self.profile)
                self.save_profile()
                with self.assertRaises(runtime.Invalid):
                    runtime.validate_profile(self.root)

    def test_json_duplicate_nonfinite_and_malformed_are_rejected(self):
        for contents in (
            '{"schema_version":1,"schema_version":1}',
            '{"x":NaN}',
            "not json",
        ):
            self.put(runtime.PROFILE, contents)
            with self.assertRaises(runtime.Invalid):
                runtime.validate_profile(self.root)

    def test_deep_profile_and_plan_json_return_bounded_cli_error(self):
        nested = "[" * 2000 + "0" + "]" * 2000
        for command, name in (
            ("validate-profile", runtime.PROFILE),
            ("verify-plan", ".artifacts/devops-sdlc/deep.json"),
        ):
            self.put(name, nested)
            argv = [sys.executable, str(ENTRYPOINT), command, "--repo", str(self.root)]
            if command == "verify-plan":
                argv += ["--plan", name]
            result = subprocess.run(argv, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            row = json.loads(result.stderr)
            self.assertEqual(row["status"], "BLOCKED")
            self.assertFalse(row["executed"])
            self.assertNotIn("Traceback", result.stderr)

    def test_unreadable_discovery_directory_fails_instead_of_partial_inventory(self):
        real_scandir = os.scandir
        self.put("hidden/main.tf", "fixture")

        def unreadable(path):
            if Path(path).name == "hidden":
                raise PermissionError("private directory content")
            return real_scandir(path)

        with mock.patch.object(runtime.os, "scandir", side_effect=unreadable):
            with self.assertRaisesRegex(
                runtime.Invalid, "could not read a directory"
            ) as failure:
                runtime.discover(self.root)
        self.assertNotIn("private directory content", str(failure.exception))

    def test_terraspace_stack_grammar_and_multi_stack_fail_profile_validation(self):
        self.profile["targets"][0]["stack_type"] = "terraspace"
        self.profile["targets"][0]["commands"]["preview"]["argv"] = [
            "terraspace",
            "plan",
            "{stack}",
        ]
        for selector in ("group/stack", "s" * 81):
            self.profile["targets"][0]["environments"]["test"]["stack"] = selector
            self.save_profile()
            with self.assertRaises(runtime.Invalid):
                runtime.validate_profile(self.root)
        self.profile["targets"][0]["environments"]["test"]["stack"] = "valid-stack"
        self.profile["targets"][0]["commands"]["validate"]["argv"] = [
            "make",
            "terraspace-validate",
            "stacks=one",
        ]
        self.save_profile()
        with self.assertRaisesRegex(runtime.Invalid, "Unsupported Make argument"):
            runtime.validate_profile(self.root)
        self.profile["targets"][0]["commands"]["validate"]["argv"] = [
            "terraspace",
            "validate",
            "{stack}",
        ]
        self.save_profile()
        self.assertEqual(
            runtime.validate_profile(self.root)["targets"][0]["environments"]["test"][
                "stack"
            ],
            "valid-stack",
        )

    def test_rejects_bad_argv(self):
        vectors = [
            ["sh", "-c", "echo bad"],
            ["make", "pulumi-up"],
            ["make", "test-pulumi", "SHELL=bash"],
            ["make", "test-pulumi", "-f", "evil.mk"],
            ["make", "test-pulumi", "x=$(touch bad)"],
            ["make", "test-pulumi", "stack={stack}"],
            ["make", "test-pulumi;touch"],
            ["python3", "scripts/arbitrary.py"],
            ["uv", "run", "pytest", "-p", "evil"],
            ["terraform", "apply"],
            ["pulumi", "preview", "--show-secrets"],
            ["make", "test-pulumi", "stack=../../prod"],
        ]
        for vector in vectors:
            with self.subTest(vector=vector):
                self.profile["targets"][0]["commands"]["validate"]["argv"] = vector
                self.save_profile()
                with self.assertRaises(runtime.Invalid):
                    runtime.validate_profile(self.root)

    def test_missing_environment_unknown_target_and_null_command(self):
        with self.assertRaises(runtime.Invalid):
            self.plan("preview")
        with self.assertRaises(runtime.Invalid):
            self.plan("preview", "prod")
        with self.assertRaises(runtime.Invalid):
            runtime.build_plan(self.root, runtime.PROFILE, "missing", "validate", None)
        result = self.plan("check")
        self.assertEqual(result["status"], "SKIPPED")
        self.assertIsNone(result["argv"])
        self.assertEqual(
            runtime.execute_plan(
                self.root, result, trust_repo=False, read_only_credentials=False
            )["status"],
            "SKIPPED",
        )

    def test_symlink_target_profile_and_source_rejected(self):
        (self.root / "link").symlink_to(self.root, target_is_directory=True)
        self.profile["targets"][0]["root"] = "link"
        self.save_profile()
        with self.assertRaises(runtime.Invalid):
            runtime.validate_profile(self.root)
        self.profile["targets"][0]["root"] = "."
        self.save_profile()
        (self.root / "source-link").symlink_to(self.root / "README.md")
        with self.assertRaises(runtime.Invalid):
            self.plan()

    def test_evidence_write_verify_and_no_overwrite(self):
        plan = self.plan()
        filename = runtime.ARTIFACT_ROOT + "/intent.json"
        runtime.write_plan(self.root, filename, plan)
        self.assertEqual(
            runtime.verify_plan(self.root, filename, now=1001)["status"], "VERIFIED"
        )
        with self.assertRaises(runtime.Invalid):
            runtime.write_plan(self.root, filename, plan)
        with self.assertRaises(runtime.Invalid):
            runtime.write_plan(self.root, "outside.json", plan)

    def test_intention_schema_upgrade_requires_regeneration(self):
        plan = self.plan()
        self.assertEqual(plan["schema_version"], 2)
        self.assertEqual(self.profile["schema_version"], 1)
        filename = runtime.ARTIFACT_ROOT + "/legacy.json"
        for version in (1, True, None, 3, "2"):
            for operation_present in (False, True):
                legacy = copy.deepcopy(plan)
                legacy["schema_version"] = version
                if not operation_present:
                    legacy.pop("operation_sha256")
                self.put(filename, json.dumps(legacy))
                with (
                    self.subTest(version=version, operation=operation_present),
                    mock.patch.object(runtime, "build_plan") as rebuild,
                    self.assertRaisesRegex(runtime.Invalid, "schema 2.*regenerate"),
                ):
                    runtime.verify_plan(self.root, filename, now=1001)
                rebuild.assert_not_called()
        missing_operation = copy.deepcopy(plan)
        missing_operation.pop("operation_sha256")
        self.put(filename, json.dumps(missing_operation))
        with self.assertRaises(runtime.Invalid):
            runtime.verify_plan(self.root, filename, now=1001)
        self.put(filename, json.dumps(plan))
        self.assertEqual(
            runtime.verify_plan(self.root, filename, now=1001)["status"], "VERIFIED"
        )

    def test_evidence_detects_source_profile_sha_and_argv_changes(self):
        plan = self.plan()
        filename = runtime.ARTIFACT_ROOT + "/intent.json"
        runtime.write_plan(self.root, filename, plan)
        self.put("README.md", "changed")
        with self.assertRaises(runtime.Invalid):
            runtime.verify_plan(self.root, filename, now=1001)
        self.put("README.md", "fixture\n")
        for key, value in (
            ("argv", ["make", "test-unit"]),
            ("executed", 0),
            ("schema_version", True),
            ("requires_credentials", 0),
        ):
            altered = copy.deepcopy(plan)
            altered[key] = value
            self.put(filename, json.dumps(altered))
            with self.subTest(key=key), self.assertRaises(runtime.Invalid):
                runtime.verify_plan(self.root, filename, now=1001)
        self.put(filename, json.dumps(plan))
        self.profile["project"]["name"] = "Changed"
        self.save_profile()
        with self.assertRaises(runtime.Invalid):
            runtime.verify_plan(self.root, filename, now=1001)

    def test_evidence_rejects_future_stale_and_bool_age(self):
        filename = runtime.ARTIFACT_ROOT + "/intent.json"
        runtime.write_plan(self.root, filename, self.plan())
        for now, age in (
            (999, 3600),
            (5000, 3600),
            (1001, True),
            (1001, 0),
            (1001, 86401),
        ):
            with self.subTest(now=now, age=age), self.assertRaises(runtime.Invalid):
                runtime.verify_plan(self.root, filename, age, now=now)

    def test_snapshot_never_reads_sensitive_files(self):
        secret = self.put("pulumi/Pulumi.test.yaml", "secure: secret-value")
        env = self.put(".env", "TOKEN=secret-value")
        original = Path.read_bytes

        def reject_sensitive(path):
            if path in (secret, env):
                raise AssertionError("Sensitive file read")
            return original(path)

        with mock.patch.object(Path, "read_bytes", reject_sensitive):
            result = self.plan()
        self.assertIn(
            "pulumi/Pulumi.test.yaml", result["source"]["excluded_sensitive_paths"]
        )
        self.assertNotIn("secret-value", json.dumps(result))

    def test_sensitive_metadata_changes_invalidate_without_content_reads(self):
        secret = self.put("pulumi/Pulumi.test.yaml", "secure: original")
        filename = runtime.ARTIFACT_ROOT + "/intent.json"
        runtime.write_plan(self.root, filename, self.plan())
        secret.write_text("secure: changed value")
        original = Path.read_bytes

        def reject_sensitive(path):
            if path == secret:
                raise AssertionError("Sensitive content read")
            return original(path)

        with mock.patch.object(Path, "read_bytes", reject_sensitive):
            with self.assertRaises(runtime.Invalid):
                runtime.verify_plan(self.root, filename, now=1001)

    def test_stack_and_make_environment_mismatch_rejected(self):
        self.profile["targets"][0]["commands"]["preview"]["argv"][3] = "prod"
        self.save_profile()
        with self.assertRaises(runtime.Invalid):
            self.plan("preview", "test")
        self.profile["targets"][0]["commands"]["preview"]["argv"] = [
            "make",
            "pulumi-preview",
            "env=prod",
        ]
        self.save_profile()
        with self.assertRaises(runtime.Invalid):
            self.plan("preview", "test")

    def test_ruff_write_flags_and_pytest_symlink_rejected(self):
        for argv in (
            ["uv", "run", "ruff", "check", "--output-file", "README.md"],
            ["uv", "run", "ruff", "check", "--fix"],
            ["uv", "run", "ruff", "format", "."],
        ):
            with self.assertRaises(runtime.Invalid):
                runtime.allowed_argv(argv, "check", "pulumi")
        (self.root / "tests").symlink_to("/tmp", target_is_directory=True)
        with self.assertRaises(runtime.Invalid):
            self.plan("test")

    def test_execution_requires_review_and_preview_credential_ack(self):
        plan = self.plan()
        with self.assertRaises(runtime.Invalid):
            runtime.execute_plan(
                self.root, plan, trust_repo=False, read_only_credentials=False
            )
        with self.assertRaises(runtime.Invalid):
            runtime.execute_plan(
                self.root,
                self.plan("preview", "test"),
                trust_repo=True,
                read_only_credentials=False,
            )

    def fixture_tool(self, body):
        # Tool fixture lives outside the repository to leave source identity stable.
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "make"
        path.write_text("#!" + sys.executable + "\n" + body)
        path.chmod(0o755)
        return directory.name + os.pathsep + os.environ.get("PATH", "")

    def test_subprocess_execution_suppresses_output_and_classifies_exit(self):
        for code in (0, 3):
            path = self.fixture_tool(
                "import sys\nprint('SECRET_SENTINEL')\n"
                f"print('SECRET_SENTINEL', file=sys.stderr)\nsys.exit({code})\n"
            )
            with mock.patch.dict(os.environ, {"PATH": path}):
                result = runtime.execute_plan(
                    self.root, self.plan(), trust_repo=True, read_only_credentials=False
                )
            self.assertEqual(result["status"], "COMPLETED" if code == 0 else "FAILED")
            self.assertEqual(result["semantic_result"], "UNVERIFIED")
            self.assertNotIn("SECRET_SENTINEL", json.dumps(result))

    @unittest.skipUnless(
        os.name == "posix", "Process-group guarantee is POSIX-specific"
    )
    def test_timeout_kills_child_process_group(self):
        marker = Path(tempfile.gettempdir()) / ("devops-child-" + str(os.getpid()))
        self.addCleanup(lambda: marker.unlink(missing_ok=True))
        child = (
            "import time,pathlib; time.sleep(2); pathlib.Path("
            + repr(str(marker))
            + ").write_text('alive')"
        )
        body = (
            "import subprocess,sys,time\nsubprocess.Popen([sys.executable,'-c',"
            + repr(child)
            + "])\ntime.sleep(20)\n"
        )
        path = self.fixture_tool(body)
        with mock.patch.dict(os.environ, {"PATH": path}):
            result = runtime.execute_plan(
                self.root,
                self.plan(),
                trust_repo=True,
                read_only_credentials=False,
                timeout=1,
            )
        self.assertEqual(result["status"], "TIMEOUT")
        time.sleep(1.2)
        self.assertFalse(marker.exists())

    def test_cli_skip_and_errors_are_nonzero_and_json(self):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            code = runtime.main(
                [
                    "plan",
                    "--repo",
                    str(self.root),
                    "--target",
                    "infra",
                    "--stage",
                    "check",
                ]
            )
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(out.getvalue())["intention"]["status"], "SKIPPED")
        with contextlib.redirect_stderr(io.StringIO()) as err:
            code = runtime.main(
                [
                    "plan",
                    "--repo",
                    str(self.root),
                    "--target",
                    "unknown",
                    "--stage",
                    "validate",
                ]
            )
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(err.getvalue())["status"], "BLOCKED")

    def test_tracked_build_source_invalidates_intention(self):
        self.put("build/rules.mk", "test: ; echo first")
        subprocess.run(
            ["git", "-C", str(self.root), "add", "build/rules.mk"], check=True
        )
        before = self.plan()
        self.put("build/rules.mk", "test: ; echo changed")
        self.assertNotEqual(before["source"], self.plan()["source"])

    def test_make_engine_mismatch_and_all_stack_preview_rejected(self):
        for argv, engine in (
            (["make", "terraspace-plan"], "pulumi"),
            (["make", "pulumi-preview"], "terraspace"),
            (["make", "terraspace-all-plan"], "terraspace"),
        ):
            with self.subTest(argv=argv), self.assertRaises(runtime.Invalid):
                runtime.allowed_argv(argv, "preview", engine)

    def test_absolute_engine_plan_output_rejected(self):
        with self.assertRaises(runtime.Invalid):
            runtime.bind_output_path(
                self.root,
                {"root": "."},
                ["make", "terraspace-plan-file", "out=/tmp/escape.plan"],
            )

    def test_symlinked_terraspace_stack_directory_is_rejected(self):
        self.put("Gemfile", "fixture")
        (self.root / "app").mkdir()
        (self.root / "app" / "stacks").symlink_to("/tmp", target_is_directory=True)
        with self.assertRaises(runtime.Invalid):
            runtime.discover(self.root)

    @unittest.skipUnless(os.name == "posix", "Descriptor traversal is POSIX-specific")
    def test_artifact_parent_symlink_swap_cannot_escape(self):
        destination = tempfile.TemporaryDirectory()
        self.addCleanup(destination.cleanup)
        artifact_parent = self.root / runtime.ARTIFACT_ROOT
        artifact_parent.mkdir(parents=True)
        original = runtime.secure_directory

        def swapped(path, **kwargs):
            descriptor = original(path, **kwargs)
            artifact_parent.rename(artifact_parent.with_name("moved"))
            artifact_parent.symlink_to(destination.name, target_is_directory=True)
            return descriptor

        with mock.patch.object(runtime, "secure_directory", swapped):
            runtime.write_plan(
                self.root, runtime.ARTIFACT_ROOT + "/intent.json", {"fixture": True}
            )
        self.assertFalse((Path(destination.name) / "intent.json").exists())
        self.assertTrue((artifact_parent.with_name("moved") / "intent.json").exists())


if __name__ == "__main__":
    unittest.main()
