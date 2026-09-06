"""Host-granted preview boundaries with inert credentials and executions."""

from __future__ import annotations

import copy
import json
import os
import stat
import subprocess
import types
import unittest
from pathlib import Path
from unittest import mock

import test_runtime_edges as fixtures

runtime = fixtures.runtime


class PreviewAuthorizationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.RuntimeEdgeTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.plan = self.fixture.plan("preview", "dev")
        self.grant = {
            "schema_version": 1,
            "kind": "credentialed-pulumi-preview",
            "issuer": "inert-host-policy",
            "actor": "inert-operator",
            "actor_uid": 1000,
            "fork": False,
            "repo_path": str(self.root),
            "repository": "o/r",
            "git_sha": self.plan["source"]["git_sha"],
            "operation_sha256": self.plan["operation_sha256"],
            "backend": "s3://safe-state",
            "account_id": "123456789012",
            "principal_arn": "arn:aws:sts::123456789012:assumed-role/Readonly/session",
            "principal_id": "AROAEXAMPLE:session",
            "access_key_id": "INERT-TEMPORARY-IDENTIFIER",
            "issued_at": 990,
            "expires_at": 1100,
            "credentials_expire_at": 1500,
            "source_trusted": True,
            "read_only_role_verified": True,
            "execution_isolation": "protected-toolchain-and-read-only-checkout",
            "aws_executable": "/opt/trusted/aws",
            "executable": "/opt/trusted/pulumi",
            "path": ["/opt/trusted"],
            "home": "/var/empty",
        }
        for name in ("getuid", "geteuid"):
            patch = mock.patch.object(runtime.os, name, return_value=1000)
            patch.start()
            self.addCleanup(patch.stop)
        namespace = mock.patch.object(runtime, "PREVIEW_AUTHORITY_ROOTS", (self.root,))
        namespace.start()
        self.addCleanup(namespace.stop)
        clock = mock.patch.object(runtime.time, "time", return_value=1000)
        clock.start()
        self.addCleanup(clock.stop)

    def test_operation_binding_survives_time_but_not_backend_changes(self):
        newer = runtime.build_plan(
            self.root, runtime.PROFILE, "target", "preview", "dev", now=1001
        )
        self.assertEqual(newer["operation_sha256"], self.plan["operation_sha256"])
        self.assertNotEqual(newer["intention_sha256"], self.plan["intention_sha256"])
        self.fixture.profile["targets"][0]["environments"]["dev"]["backend"] = (
            "https://attacker.invalid"
        )
        self.fixture.save_profile()
        changed = self.fixture.plan("preview", "dev")
        self.assertNotEqual(changed["operation_sha256"], self.plan["operation_sha256"])

    def test_scope_actor_and_backend_mismatches_block(self):
        runtime.validate_grant_identity(self.root, self.plan, self.grant)
        changes = {
            "schema_version": True,
            "actor_uid": 1001,
            "fork": True,
            "repository": "fork/r",
            "git_sha": "0" * 40,
            "operation_sha256": "0" * 64,
            "repo_path": "/other",
            "backend": "https://attacker.invalid",
            "account_id": "000000000000",
            "source_trusted": False,
            "read_only_role_verified": False,
            "execution_isolation": "self-attested",
            "principal_arn": "arn:aws:iam::123456789012:user/admin",
            "principal_id": "",
            "issuer": "",
            "actor": "",
        }
        for key, value in changes.items():
            with self.subTest(key=key), self.assertRaises(runtime.Invalid):
                runtime.validate_grant_identity(
                    self.root, self.plan, {**self.grant, key: value}
                )
        for backend in (
            "file:///tmp/state",
            "s3://another-bucket",
            "https://127.0.0.1",
        ):
            with self.subTest(backend=backend), self.assertRaises(runtime.Invalid):
                runtime.validate_grant_identity(
                    self.root, self.plan, {**self.grant, "backend": backend}
                )

    def test_time_windows_and_command_duration_are_enforced(self):
        runtime.validate_grant_time(self.grant, 10)
        cases = [
            {"issued_at": True},
            {"issued_at": 1001},
            {"expires_at": 1000},
            {"expires_at": 1891},
            {"credentials_expire_at": 1099},
            {"credentials_expire_at": 4591},
            {"expires_at": 1010},
        ]
        for changes in cases:
            with self.subTest(changes=changes), self.assertRaises(runtime.Invalid):
                runtime.validate_grant_time({**self.grant, **changes}, 10)

    def test_protected_metadata_checks_owner_mode_type_and_links(self):
        regular = types.SimpleNamespace(
            st_mode=stat.S_IFREG | 0o644, st_uid=0, st_nlink=1
        )
        runtime.protected_metadata(regular, directory=False)
        directory = types.SimpleNamespace(
            st_mode=stat.S_IFDIR | 0o755, st_uid=0, st_nlink=2
        )
        runtime.protected_metadata(directory, directory=True)
        for changes in (
            {"st_uid": 1000},
            {"st_mode": stat.S_IFREG | 0o666},
            {"st_mode": stat.S_IFIFO | 0o600},
            {"st_nlink": 2},
        ):
            with self.subTest(changes=changes), self.assertRaises(runtime.Invalid):
                runtime.protected_metadata(
                    types.SimpleNamespace(**(vars(regular) | changes)), directory=False
                )
        with self.assertRaises(runtime.Invalid):
            runtime.protected_metadata(regular, directory=True)

    def test_actual_caller_owned_grant_is_rejected_without_reading(self):
        grant = self.fixture.put("grant.json", json.dumps(self.grant))
        with mock.patch.object(runtime.os, "read") as reader:
            with self.assertRaises(runtime.Invalid):
                runtime.read_preview_grant(str(grant), self.root / "other-checkout")
        reader.assert_not_called()

    def test_descriptor_traversal_rejects_symlinks_and_cleans_failures(self):
        file = self.fixture.put("regular", "safe")
        link = self.root / "link"
        link.symlink_to(file)
        with mock.patch.object(runtime, "protected_metadata"):
            runtime.check_protected(file)
            runtime.check_protected(self.root, directory=True)
            with self.assertRaises(OSError):
                runtime.check_protected(link)
            with self.assertRaises(OSError):
                runtime.check_protected(self.root / "missing")
        with self.assertRaises(runtime.Invalid):
            runtime.protected_descriptor(Path("relative"))
        with self.assertRaises(runtime.Invalid):
            runtime.protected_descriptor(Path("/"))
        with (
            mock.patch.object(runtime.os, "name", "nt"),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.protected_descriptor(file)

    def test_grant_platform_identity_path_and_schema_guards(self):
        for attribute, value in (("name", "nt"), ("geteuid", 0), ("getuid", 1001)):
            patch = (
                mock.patch.object(runtime.os, attribute, value)
                if attribute == "name"
                else mock.patch.object(runtime.os, attribute, return_value=value)
            )
            with (
                patch,
                self.subTest(attribute=attribute),
                self.assertRaises(runtime.Invalid),
            ):
                runtime.read_preview_grant("/etc/grant.json", self.root)
        for value in (None, str(self.root / "grant.json"), "/etc//grant.json"):
            with self.subTest(value=value), self.assertRaises(runtime.Invalid):
                runtime.read_preview_grant(value, self.root)
        file = self.fixture.put("grant.json", json.dumps(self.grant))
        with mock.patch.object(runtime, "protected_metadata"):
            loaded = runtime.read_preview_grant(str(file), self.root / "checkout")
            self.assertEqual(loaded, self.grant)
            file.write_text('{"schema_version":1,"schema_version":1}')
            with self.assertRaises(runtime.Invalid):
                runtime.read_preview_grant(str(file), self.root / "checkout")
            file.write_text("{}")
            with self.assertRaises(runtime.Invalid):
                runtime.read_preview_grant(str(file), self.root / "checkout")
            file.write_text("x" * (runtime.MAX_GRANT_BYTES + 1))
            with self.assertRaises(runtime.Invalid):
                runtime.read_preview_grant(str(file), self.root / "checkout")
            file.write_text("{}")
            with mock.patch.object(
                runtime.os, "read", return_value=b"x" * (runtime.MAX_GRANT_BYTES + 1)
            ):
                with self.assertRaises(runtime.Invalid):
                    runtime.read_preview_grant(str(file), self.root / "checkout")

    @mock.patch.object(runtime, "verify_git_metadata")
    def test_source_status_includes_untracked_ignored_and_origin(self, _metadata):
        responses = [b"", b"git@github.com:o/r.git\n", b"README.md\0"]
        with (
            mock.patch.object(runtime, "check_protected") as protected,
            mock.patch.object(runtime, "git_output", side_effect=responses) as git,
        ):
            runtime.verify_preview_source(self.root, self.plan)
        self.assertEqual(protected.call_count, 2)
        self.assertIn("--ignored", git.call_args_list[0].args[1])
        for status in (b" M main.py", b"?? untracked.py", b"!! ignored.py"):
            with (
                mock.patch.object(runtime, "check_protected"),
                mock.patch.object(runtime, "git_output", return_value=status),
                self.subTest(status=status),
                self.assertRaises(runtime.Invalid),
            ):
                runtime.verify_preview_source(self.root, self.plan)
        with (
            mock.patch.object(runtime, "check_protected"),
            mock.patch.object(
                runtime, "git_output", side_effect=[b"", b"https://github.com/fork/r"]
            ),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.verify_preview_source(self.root, self.plan)
        with (
            mock.patch.object(runtime, "check_protected"),
            mock.patch.object(runtime, "git_output", side_effect=responses),
            mock.patch.object(runtime, "MAX_FILES", 0),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.verify_preview_source(self.root, self.plan)

    def test_toolchain_is_host_selected_and_protected(self):
        with (
            mock.patch.object(runtime, "check_protected") as protected,
            mock.patch.object(runtime.os, "access", return_value=True),
        ):
            runtime.verify_preview_tools(self.grant, self.plan)
        self.assertEqual(protected.call_count, 4)
        for value in ("relative", "/opt//pulumi"):
            with self.subTest(value=value), self.assertRaises(runtime.Invalid):
                runtime.grant_path(value)
        with (
            mock.patch.object(runtime, "check_protected"),
            mock.patch.object(runtime.os, "access", return_value=False),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.verify_preview_tools(self.grant, self.plan)
        for changes in (
            {"executable": "/opt/other"},
            {"path": "not-a-list"},
            {"path": []},
            {"path": ["/opt/tool:/tmp"]},
        ):
            with (
                mock.patch.object(runtime, "check_protected"),
                mock.patch.object(runtime.os, "access", return_value=True),
                self.subTest(changes=changes),
                self.assertRaises(runtime.Invalid),
            ):
                runtime.verify_preview_tools({**self.grant, **changes}, self.plan)

    def test_temporary_credentials_cannot_fall_back_to_home_profile(self):
        with (
            mock.patch.dict(os.environ, {"AWS_PROFILE": "unreviewed"}, clear=True),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.preview_environment({}, self.grant)
        credentials = {
            "AWS_ACCESS_KEY_ID": self.grant["access_key_id"],
            "AWS_SECRET_ACCESS_KEY": "inert-secret",
            "AWS_SESSION_TOKEN": "inert-session",
        }
        with mock.patch.dict(os.environ, credentials, clear=True):
            env = runtime.preview_environment({}, self.grant)
        self.assertEqual(env["PATH"], "/opt/trusted")
        self.assertEqual(env["HOME"], "/var/empty")
        self.assertEqual(env["AWS_CONFIG_FILE"], os.devnull)
        self.assertNotIn("AWS_PROFILE", env)
        with (
            mock.patch.dict(
                os.environ, credentials | {"AWS_ACCESS_KEY_ID": "wrong"}, clear=True
            ),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.preview_environment({}, self.grant)

    def test_full_identity_role_session_and_account_are_compared(self):
        identity = {
            "Account": "123456789012",
            "Arn": self.grant["principal_arn"],
            "UserId": self.grant["principal_id"],
        }
        success = types.SimpleNamespace(
            returncode=0, stdout=json.dumps(identity).encode()
        )
        with mock.patch.object(runtime.subprocess, "run", return_value=success) as run:
            runtime.verify_aws_account(self.plan, {}, self.grant)
        self.assertEqual(run.call_args.args[0][0], "/opt/trusted/aws")
        for key in identity:
            result = types.SimpleNamespace(
                returncode=0, stdout=json.dumps(identity | {key: "different"}).encode()
            )
            with (
                mock.patch.object(runtime.subprocess, "run", return_value=result),
                self.subTest(key=key),
                self.assertRaises(runtime.Invalid),
            ):
                runtime.verify_aws_account(self.plan, {}, self.grant)
        for result in (
            types.SimpleNamespace(returncode=1, stdout=b""),
            types.SimpleNamespace(
                returncode=0, stdout=b"x" * (runtime.MAX_GRANT_BYTES + 1)
            ),
        ):
            with (
                mock.patch.object(runtime.subprocess, "run", return_value=result),
                self.assertRaises(runtime.Invalid),
            ):
                runtime.verify_aws_account(self.plan, {}, self.grant)
        with (
            mock.patch.object(
                runtime.subprocess,
                "run",
                side_effect=subprocess.TimeoutExpired("aws", 20),
            ),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.verify_aws_account(self.plan, {}, self.grant)

    def test_authorization_and_post_identity_rechecks_precede_process(self):
        with (
            mock.patch.object(runtime, "read_preview_grant", return_value=self.grant),
            mock.patch.object(runtime, "verify_preview_source") as source,
            mock.patch.object(runtime, "verify_preview_tools") as tools,
        ):
            self.assertEqual(
                runtime.authorize_preview(self.root, self.plan, "/etc/grant", 10),
                self.grant,
            )
        source.assert_called_once()
        tools.assert_called_once()
        changed = copy.deepcopy(self.plan)
        changed["source"]["source_sha256"] = "0" * 64
        with (
            mock.patch.object(runtime, "authorize_preview", return_value=self.grant),
            mock.patch.object(runtime, "preview_environment", return_value={}),
            mock.patch.object(runtime, "verify_aws_account"),
            mock.patch.object(runtime, "build_plan", side_effect=[self.plan, changed]),
            mock.patch.object(runtime, "run_process") as process,
            self.assertRaises(runtime.Invalid),
        ):
            runtime.execute_plan(
                self.root,
                self.plan,
                trust_repo=True,
                read_only_credentials=True,
                timeout=10,
                preview_authorization="/etc/grant",
            )
        process.assert_not_called()

    def test_grant_aliases_and_nonissuer_files_are_rejected_before_open(self):
        aliases = [
            str(self.root / "sibling/../grant.json"),
            "/" + str(self.root / "grant.json"),
            "/unrelated/root-owned.json",
        ]
        with mock.patch.object(runtime, "protected_descriptor") as opened:
            for value in aliases:
                with self.subTest(value=value), self.assertRaises(runtime.Invalid):
                    runtime.read_preview_grant(value, self.root / "checkout")
        opened.assert_not_called()
        for value in aliases[:2]:
            with self.subTest(value=value), self.assertRaises(runtime.Invalid):
                runtime.grant_path(value)

    def test_low_privilege_cli_cannot_issue_its_own_grant(self):
        path = self.fixture.put("caller-grant.json", json.dumps(self.grant))
        argv = [
            str(Path(os.sys.executable)),
            str(fixtures.ENTRYPOINT),
            "plan",
            "--repo",
            str(self.root),
            "--target",
            "target",
            "--stage",
            "preview",
            "--environment",
            "dev",
            "--execute",
            "--trust-repo",
            "--read-only-credentials",
            "--preview-authorization",
            str(path),
        ]
        result = subprocess.run(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        report = json.loads(result.stderr)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertFalse(report["executed"])
        self.assertNotIn(self.grant["access_key_id"], result.stderr.decode())

    def test_git_metadata_never_uses_ambient_executable_or_credentials(self):
        marker = self.root / "fake-git-ran"
        fake = self.fixture.put("bin/git", "#!/bin/sh\ntouch " + str(marker) + "\n")
        fake.chmod(0o755)
        hostile = {
            "PATH": str(fake.parent),
            "AWS_SECRET_ACCESS_KEY": "inert-secret",
            "GIT_DIR": "/wrong",
            "GIT_INDEX_FILE": "/wrong",
            "GIT_CONFIG_COUNT": "1",
        }
        with mock.patch.dict(os.environ, hostile):
            self.assertEqual(
                runtime.git_output(self.root, ["rev-parse", "HEAD"]).strip().decode(),
                self.plan["source"]["git_sha"],
            )
        self.assertFalse(marker.exists())
        with mock.patch.object(
            runtime.subprocess,
            "run",
            return_value=types.SimpleNamespace(returncode=0, stdout=b""),
        ) as run:
            runtime.git_output(self.root, ["rev-parse", "HEAD"])
        self.assertEqual(run.call_args.args[0][0], "/usr/bin/git")
        env = run.call_args.kwargs["env"]
        self.assertNotIn("AWS_SECRET_ACCESS_KEY", env)
        self.assertNotIn("GIT_DIR", env)
        self.assertNotIn("GIT_INDEX_FILE", env)
        with (
            mock.patch.object(runtime.os, "name", "nt"),
            mock.patch.object(
                runtime.subprocess,
                "run",
                return_value=types.SimpleNamespace(returncode=0, stdout=b"local"),
            ),
        ):
            self.assertEqual(
                runtime.git_output(self.root, ["rev-parse", "HEAD"]), b"local"
            )

    def test_metadata_tree_rejects_mutable_entries_links_and_overflow(self):
        tree = self.root / "metadata"
        tree.mkdir()
        (tree / "refs").mkdir()
        (tree / "refs/main").write_text("inert")
        with mock.patch.object(runtime, "check_protected") as check:
            runtime.protected_tree(tree)
        self.assertEqual(check.call_count, 2)
        with (
            mock.patch.object(runtime, "check_protected"),
            mock.patch.object(runtime, "MAX_FILES", 1),
            self.assertRaises(runtime.Invalid),
        ):
            runtime.protected_tree(tree)
        with self.assertRaises(runtime.Invalid):
            runtime.protected_tree(tree)

    def test_git_external_metadata_and_includes_are_blocked(self):
        with (
            mock.patch.object(runtime, "check_protected"),
            mock.patch.object(runtime, "protected_tree"),
            mock.patch.object(runtime, "git_output", return_value=b"core.bare\n"),
        ):
            runtime.verify_git_metadata(self.root)
        for key in (b"include.path\n", b"includeif.gitdir:foo.path\n"):
            with (
                mock.patch.object(runtime, "check_protected"),
                mock.patch.object(runtime, "protected_tree"),
                mock.patch.object(runtime, "git_output", return_value=key),
                self.subTest(key=key),
                self.assertRaises(runtime.Invalid),
            ):
                runtime.verify_git_metadata(self.root)
        for name in (
            ".git/commondir",
            ".git/objects/info/alternates",
            ".git/config.worktree",
        ):
            path = self.fixture.put(name, "/untrusted")
            with (
                mock.patch.object(runtime, "check_protected"),
                self.subTest(name=name),
                self.assertRaises(runtime.Invalid),
            ):
                runtime.verify_git_metadata(self.root)
            path.unlink()

    def test_expiry_after_final_source_build_prevents_spawn(self):
        calls = []

        def rebuild(*_args, **_kwargs):
            calls.append(True)
            if len(calls) == 2:
                runtime.time.time.return_value = 1095
            return self.plan

        with (
            mock.patch.object(runtime, "authorize_preview", return_value=self.grant),
            mock.patch.object(runtime, "preview_environment", return_value={}),
            mock.patch.object(runtime, "verify_aws_account"),
            mock.patch.object(runtime, "build_plan", side_effect=rebuild),
            mock.patch.object(runtime, "run_process") as process,
            self.assertRaises(runtime.Invalid),
        ):
            runtime.execute_plan(
                self.root,
                self.plan,
                trust_repo=True,
                read_only_credentials=True,
                timeout=10,
                preview_authorization="/etc/grant",
            )
        self.assertEqual(len(calls), 2)
        process.assert_not_called()

    def test_absolute_deadline_clips_wait_and_blocks_expired_start(self):
        process = mock.Mock()
        process.wait.return_value = 0
        with mock.patch.object(runtime.subprocess, "Popen", return_value=process):
            result = runtime.run_process(self.plan, self.root, {}, 300, deadline=1010)
        self.assertEqual(result["status"], "COMPLETED")
        self.assertEqual(result["semantic_result"], "UNVERIFIED")
        process.wait.assert_called_once_with(timeout=10)
        with (
            mock.patch.object(runtime.subprocess, "Popen") as spawn,
            self.assertRaises(runtime.Invalid),
        ):
            runtime.run_process(self.plan, self.root, {}, 300, deadline=999)
        spawn.assert_not_called()
        process.wait.reset_mock()
        process.wait.side_effect = [subprocess.TimeoutExpired("inert", 0), -9]
        with (
            mock.patch.object(runtime.subprocess, "Popen", return_value=process),
            mock.patch.object(runtime.time, "time", side_effect=[1000, 1011]),
            mock.patch.object(runtime, "terminate_process_tree") as terminate,
        ):
            result = runtime.run_process(self.plan, self.root, {}, 300, deadline=1010)
        self.assertEqual(result["status"], "TIMEOUT")
        self.assertEqual(process.wait.call_args_list[0].kwargs["timeout"], 0)
        terminate.assert_called_once_with(process)

    def test_non_posix_local_git_retains_only_needed_host_search_environment(self):
        with (
            mock.patch.object(runtime.os, "name", "nt"),
            mock.patch.dict(
                os.environ,
                {
                    "PATH": r"C:\Git\bin",
                    "SYSTEMROOT": r"C:\Windows",
                    "AWS_SESSION_TOKEN": "inert",
                    "GIT_DIR": "wrong",
                },
                clear=True,
            ),
        ):
            env = runtime.git_environment()
        self.assertEqual(env["PATH"], r"C:\Git\bin")
        self.assertEqual(env["SYSTEMROOT"], r"C:\Windows")
        self.assertNotIn("AWS_SESSION_TOKEN", env)
        self.assertNotIn("GIT_DIR", env)
