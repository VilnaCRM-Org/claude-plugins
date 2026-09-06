#!/usr/bin/env python3
"""Discover IaC sources and prepare bounded, reviewable command intentions.

Repository commands execute trusted code. This helper is not a sandbox, an
engine saved-plan verifier, or a source of deployment authorization.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import signal

# Bounded argv execution is this helper's purpose.
import subprocess  # nosec B404
import sys
import time
from pathlib import Path, PurePosixPath
from typing import Any

STAGES = {"validate", "test", "check", "security", "preview"}
ENGINES = {"terraform", "terraspace", "pulumi"}
VARIABLES = {"environment", "stack", "account_id", "region", "backend"}
PROFILE = ".claude/devops-sdlc.json"
ARTIFACT_ROOT = ".artifacts/devops-sdlc"
MAX_FILE_BYTES = 2_000_000
MAX_SOURCE_BYTES = 50_000_000
MAX_FILES = 10_000
MAX_AGE = 3600
ID = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}$")
MAKE_TARGET = re.compile(r"^([A-Za-z0-9][A-Za-z0-9_.-]*):(?!=)")
FORBIDDEN_WORDS = {
    "apply",
    "up",
    "up-plan",
    "destroy",
    "down",
    "refresh",
    "import",
    "state",
    "force-unlock",
    "taint",
    "untaint",
    "init",
    "login",
    "logout",
    "cancel",
    "set",
    "rm",
    "remove",
    "delete",
    "clean",
    "reset",
    "install",
    "sync",
    "--show-secrets",
    "--yes",
    "-y",
    "--auto-approve",
    "-auto-approve",
}
SKIP_DIRS = {
    ".git",
    ".terraform",
    ".terraspace-cache",
    ".pulumi",
    ".pulumi-backend",
    ".venv",
    "venv",
    "node_modules",
    "vendor",
    "__pycache__",
    ".artifacts",
    "dist",
    "build",
    "coverage",
    "htmlcov",
    ".next",
    ".nuxt",
    ".cache",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
}


class Invalid(ValueError):
    """A bounded validation error safe to display without source contents."""


def exact_keys(
    value: Any, required: set[str], optional: set[str] | None = None
) -> dict:
    if type(value) is not dict:
        raise Invalid("Expected an object.")
    keys = set(value)
    if not required <= keys or keys - required - (optional or set()):
        raise Invalid("Missing or unknown object keys.")
    return value


def string(value: Any, *, empty: bool = False, maximum: int = 2048) -> str:
    if not valid_string(value, empty=empty, maximum=maximum):
        raise Invalid("Expected a bounded non-empty string.")
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise Invalid("Control characters are prohibited.")
    return value


def valid_string(value: Any, *, empty: bool, maximum: int) -> bool:
    return type(value) is str and len(value) <= maximum and (empty or bool(value))


def integer(value: Any, low: int, high: int) -> int:
    if type(value) is not int or not low <= value <= high:
        raise Invalid("Expected an integer within the documented limits.")
    return value


def identifier(value: Any) -> str:
    if not ID.fullmatch(string(value, maximum=80)):
        raise Invalid("Invalid identifier.")
    return value


def repository(value: str) -> Path:
    path = Path(value).absolute()
    for part in (path, *path.parents):
        if part.is_symlink():
            raise Invalid("Repository path must not contain symlinks.")
    if not path.is_dir():
        raise Invalid("Repository directory does not exist.")
    return path.resolve()


def contained(root: Path, value: Any, *, must_exist: bool = True) -> Path:
    parts = relative_parts(value)
    path = root.joinpath(*parts.parts)
    current = root
    for part in parts.parts:
        current = current / part
        if current.is_symlink():
            raise Invalid("Symlink paths are prohibited.")
    if not path.resolve().is_relative_to(root):
        raise Invalid("Path escapes the repository.")
    if must_exist and not path.exists():
        raise Invalid("Required repository path is missing.")
    return path


def relative_parts(value: Any) -> PurePosixPath:
    raw = string(value)
    parts = PurePosixPath(raw)
    if "\\" in raw or parts.is_absolute() or ".." in parts.parts:
        raise Invalid("Path must remain inside the repository.")
    if raw != "." and any(part in {"", "."} for part in raw.split("/")):
        raise Invalid("Path must use a canonical relative form.")
    return parts


def load_json(path: Path) -> dict:
    if not path.is_file() or path.stat().st_size > MAX_FILE_BYTES:
        raise Invalid("JSON input is missing, not a regular file, or too large.")

    def pairs(items: list[tuple[str, Any]]) -> dict:
        result = {}
        for key, value in items:
            if key in result:
                raise Invalid("Duplicate JSON keys are prohibited.")
            result[key] = value
        return result

    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(
                Invalid("Non-finite JSON numbers are prohibited.")
            ),
        )
        if type(value) is not dict:
            raise Invalid("JSON input must be an object.")
        return value
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise Invalid("Input is not valid UTF-8 JSON.") from exc


def secret_path(path: str) -> bool:
    name = PurePosixPath(path).name.lower()
    return (
        name.startswith(".env")
        or name in {"credentials", "config.json", "terraform.tfstate"}
        or name.endswith(
            (".tfstate", ".tfstate.backup", ".pem", ".key", ".p12", ".pfx")
        )
        or any(word in name for word in ("credential", "secret", "token", "kubeconfig"))
        or (name.startswith("pulumi.") and name.endswith((".yaml", ".yml")))
    )


def bounded_files(root: Path):
    if root.is_symlink():
        raise Invalid("Discovery root must not be a symlink.")
    count = 0
    for directory, directories, filenames in os.walk(
        root, followlinks=False, onerror=discovery_error
    ):
        directories[:] = sorted(
            name for name in directories if walk_directory(Path(directory) / name)
        )
        for name in sorted(filenames):
            path = Path(directory) / name
            if not regular_discovery_file(path):
                continue
            count += 1
            if count > MAX_FILES:
                raise Invalid("Repository discovery exceeds the file limit.")
            yield path


def discovery_error(_error: OSError) -> None:
    raise Invalid("Repository discovery could not read a directory safely.")


def walk_directory(path: Path) -> bool:
    return path.name not in SKIP_DIRS and not path.is_symlink()


def regular_discovery_file(path: Path) -> bool:
    return not path.is_symlink() and path.is_file()


def discover(root: Path) -> dict:
    directories: dict[str, dict] = {}
    for path in bounded_files(root):
        parent = path.parent.relative_to(root).as_posix()
        engine = detect_engine(path)
        if engine == "terraform":
            directories.setdefault(parent, {"root": parent, "stack_type": engine})
        elif engine:
            directories[parent] = {"root": parent, "stack_type": engine}
    directories = collapse_terraspace(directories)
    candidates = []
    for number, (relative, candidate) in enumerate(sorted(directories.items()), 1):
        candidates.append(discover_candidate(root, relative, candidate, number))
    return {
        "schema_version": 1,
        "status": "DISCOVERED",
        "executed": False,
        "candidates": candidates,
        "note": (
            "Candidates require review; filenames do not establish "
            "deployed environments."
        ),
    }


def detect_engine(path: Path) -> str | None:
    if path.name in {"Pulumi.yaml", "Pulumi.yml"}:
        return "pulumi"
    if path.suffix == ".tf":
        return "terraform"
    if path.name == "Gemfile" and (path.parent / "app" / "stacks").is_dir():
        return "terraspace"
    return None


def collapse_terraspace(directories: dict) -> dict:
    roots = [
        key for key, value in directories.items() if value["stack_type"] == "terraspace"
    ]
    return {
        key: value
        for key, value in directories.items()
        if not nested_terraspace(key, roots)
    }


def nested_terraspace(key: str, roots: list[str]) -> bool:
    return any(key != ts and (ts == "." or key.startswith(ts + "/")) for ts in roots)


def discover_candidate(root: Path, relative: str, candidate: dict, number: int) -> dict:
    target_root = contained(root, relative)
    metadata = []
    if candidate["stack_type"] == "pulumi":
        metadata = [
            path.relative_to(root).as_posix()
            for path in sorted(
                path
                for suffix in ("yaml", "yml")
                for path in target_root.glob(f"Pulumi.*.{suffix}")
            )
            if regular_discovery_file(path)
        ]
    elif candidate["stack_type"] == "terraspace":
        stack_root = contained(
            root, (target_root / "app" / "stacks").relative_to(root).as_posix()
        )
        metadata = [
            path.relative_to(root).as_posix()
            for path in bounded_files(stack_root)
            if path.suffix == ".tfvars"
        ]
    makefiles, make_targets = discover_make(root, target_root)
    return {
        "id": f"target-{number}",
        **candidate,
        "configuration_filenames": metadata,
        "makefiles": makefiles,
        "make_targets": make_targets,
    }


def discover_make(root: Path, target_root: Path) -> tuple[list[str], list[str]]:
    makefiles = []
    targets = set()
    for makefile in {root / "Makefile", target_root / "Makefile"}:
        if makefile.is_file() and not makefile.is_symlink():
            if makefile.stat().st_size > MAX_FILE_BYTES:
                raise Invalid("Makefile exceeds discovery size limit.")
            makefiles.append(makefile.relative_to(root).as_posix())
            for line in makefile.read_text(
                encoding="utf-8", errors="replace"
            ).splitlines():
                match = MAKE_TARGET.match(line)
                if match:
                    targets.add(match.group(1))
    return sorted(makefiles), sorted(targets)


def environment_config(value: Any) -> dict:
    value = exact_keys(value, {"stack", "account_id", "region", "backend"})
    stack = string(value["stack"], maximum=160)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_./-]*", stack) or ".." in stack.split(
        "/"
    ):
        raise Invalid("Invalid stack selector.")
    if not re.fullmatch(r"[0-9]{12}", string(value["account_id"])):
        raise Invalid("AWS account_id must contain 12 digits.")
    if not re.fullmatch(r"[a-z]{2}(?:-[a-z]+)+-[0-9]+", string(value["region"])):
        raise Invalid("Invalid AWS region.")
    backend = string(value["backend"])
    if not re.fullmatch(
        r"(?:s3://[A-Za-z0-9._/-]+|file:///[A-Za-z0-9._/-]+|https://[A-Za-z0-9.-]+(?:/[A-Za-z0-9._/-]+)?)",
        backend,
    ):
        raise Invalid(
            "Backend must be a non-secret s3, file, or https identifier "
            "without query/credentials."
        )
    if ".." in backend.split("/"):
        raise Invalid("Invalid backend path.")
    return value


def lexical_argv(argv: Any, *, expanded: bool = False) -> list[str]:
    if type(argv) is not list or not 2 <= len(argv) <= 40:
        raise Invalid("Command argv must contain 2–40 arguments.")
    for argument in argv:
        lexical_argument(argument, expanded=expanded)
    return argv


def lexical_argument(argument: Any, *, expanded: bool) -> None:
    argument = string(argument, maximum=512)
    if any(
        char in argument for char in (";", "|", "&", "`", "$", "\n", "\r", "<", ">")
    ):
        raise Invalid("Shell syntax is prohibited in argv.")
    validate_placeholder(argument, expanded=expanded)
    if forbidden_argument(argument):
        raise Invalid("Mutating or secret-bearing command arguments are prohibited.")
    validate_argument_path(argument, expanded=expanded)


def validate_placeholder(argument: str, *, expanded: bool) -> None:
    if "{" in argument or "}" in argument:
        if expanded or argument not in {"{" + name + "}" for name in VARIABLES}:
            raise Invalid("Only documented whole-argument placeholders are supported.")


def forbidden_argument(argument: str) -> bool:
    return argument in FORBIDDEN_WORDS or bool(
        re.search(
            r"(?:^|[-_])(apply|destroy|delete|refresh|password|secret|token|credential|force-unlock)(?:$|[-_=])",
            argument,
        )
    )


def validate_argument_path(argument: str, *, expanded: bool) -> None:
    if argument.startswith(("/", "~")) or ".." in argument.split("/"):
        if not (expanded and argument.startswith(("s3://", "file:///", "https://"))):
            raise Invalid("Absolute or escaping command paths are prohibited.")


def allowed_argv(argv: list[str], stage: str, engine: str) -> None:
    lexical_argv(argv, expanded=True)
    tool, args = argv[0], argv[1:]
    if tool == "make":
        validate_make_engine(args[0], engine)
        validate_make(args, stage)
        return
    if tool == "uv" and args[0] == "run" and len(args) >= 2:
        validate_uv(args[1:], stage)
        return
    if not allowed_engine(tool, args, stage, engine):
        raise Invalid("Tool or arguments are outside this stage's bounded allowlist.")


def validate_make_engine(target: str, engine: str) -> None:
    for prefix in ("terraspace", "pulumi"):
        if target.startswith(prefix + "-") and engine != prefix:
            raise Invalid("Engine-specific Make target does not match stack_type.")


def validate_make(args: list[str], stage: str) -> None:
    target = args[0]
    permitted = {
        "validate": {
            "terraspace-validate",
            "terraspace-validate-stacks",
            "terraspace-ci-cd-infra-validate",
            "test-pulumi",
            "test-repository-catalogs",
            "test-repository-fanout",
        },
        "test": {
            "test",
            "test-unit",
            "test-integration",
            "test-integration-unprivileged",
            "test-policy",
            "test-crossguard",
            "test-cli",
            "test-mutation",
            "test-coverage",
        },
        "check": {
            "doctor",
            "test-quality",
            "test-ruff",
            "test-ty",
            "test-architecture",
            "test-maintainability",
            "test-lockfile",
            "test-dependency-hygiene",
            "test-repo-hygiene",
            "test-actionlint",
            "test-yaml",
            "test-dockerfile",
        },
        "security": {
            "test-security",
            "test-bandit",
            "test-secrets",
            "test-deps-security",
            "test-destructive-diff",
            "test-cost-proxy",
            "test-iam-validation-unprivileged",
        },
        "preview": {
            "pulumi-preview",
            "test-preview",
            "terraspace-plan",
            "terraspace-plan-file",
        },
    }[stage]
    if target not in permitted:
        raise Invalid("Make target is outside this stage's bounded allowlist.")
    for item in args[1:]:
        if not re.fullmatch(
            r"(?:env|stack|PULUMI_STACK|PULUMI_DIR|out)=[A-Za-z0-9_./-]+", item
        ):
            raise Invalid("Unsupported Make argument or variable assignment.")


def allowed_engine(tool: str, args: list[str], stage: str, engine: str) -> bool:
    if tool != engine:
        return False
    validators = {
        "terraform": allowed_terraform,
        "terraspace": allowed_terraspace,
        "pulumi": allowed_pulumi,
    }
    validator = validators.get(tool)
    return bool(validator and validator(args, stage))


def allowed_terraform(args: list[str], stage: str) -> bool:
    allowed = {
        "validate": {("validate",)},
        "check": {("fmt", "-check"), ("fmt", "-check", "-recursive")},
        "preview": {("plan", "-input=false", "-lock=true")},
    }
    return tuple(args) in allowed.get(stage, set())


def allowed_terraspace(args: list[str], stage: str) -> bool:
    if len(args) != 2:
        return False
    expected = {"validate": "validate", "preview": "plan"}.get(stage)
    return args[0] == expected and bool(ID.fullmatch(args[1]))


def allowed_pulumi(args: list[str], stage: str) -> bool:
    if stage != "preview" or len(args) != 4:
        return False
    return args[:2] == ["preview", "--stack"] and args[3] == "--non-interactive"


def validate_uv(args: list[str], stage: str) -> None:
    program, rest = args[0], args[1:]
    if (stage, program) == ("test", "pytest") and allowed_pytest(rest):
        return
    if (stage, program) == ("check", "ruff") and allowed_ruff(rest):
        return
    raise Invalid("Tool or arguments are outside this stage's bounded allowlist.")


def allowed_pytest(args: list[str]) -> bool:
    pattern = r"(?:-q|--strict-markers|tests(?:/[A-Za-z0-9_.-]+)*)"
    return all(re.fullmatch(pattern, item) for item in args)


def allowed_ruff(args: list[str]) -> bool:
    if not args or args[0] not in {"check", "format"}:
        return False
    if args[0] == "format" and "--check" not in args[1:]:
        raise Invalid("Ruff formatting requires --check.")
    return all(ruff_argument(item) for item in args[1:])


def ruff_argument(item: str) -> bool:
    return item == "--check" or bool(
        re.fullmatch(r"[A-Za-z0-9_.][A-Za-z0-9_./-]*", item)
        and not item.startswith("-")
    )


def validate_profile(root: Path, profile_path: str = PROFILE) -> dict:
    profile = load_json(contained(root, profile_path))
    exact_keys(profile, {"schema_version", "project", "targets"})
    if type(profile["schema_version"]) is not int or profile["schema_version"] != 1:
        raise Invalid("Only schema_version 1 is supported.")
    project = exact_keys(profile["project"], {"name", "repo"})
    string(project["name"], maximum=160)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", string(project["repo"])):
        raise Invalid("project.repo must be owner/name.")
    targets = profile["targets"]
    if type(targets) is not list or not 1 <= len(targets) <= 100:
        raise Invalid("Profile needs 1–100 targets.")
    ids = set()
    for target in targets:
        target_id = validate_target(root, target)
        if target_id in ids:
            raise Invalid("Target IDs must be unique.")
        ids.add(target_id)
    return profile


def validate_target(root: Path, target: Any) -> str:
    exact_keys(target, {"id", "stack_type", "root", "environments", "commands"})
    target_id = identifier(target["id"])
    if type(target["stack_type"]) is not str or target["stack_type"] not in ENGINES:
        raise Invalid("Unsupported stack_type.")
    if not contained(root, target["root"]).is_dir():
        raise Invalid("Target root must be a directory.")
    environments = target["environments"]
    if type(environments) is not dict or len(environments) > 50:
        raise Invalid("Environments must be an object with at most 50 entries.")
    for name, environment in environments.items():
        identifier(name)
        environment_config(environment)
        if target["stack_type"] == "terraspace":
            identifier(environment["stack"])
    commands = exact_keys(target["commands"], STAGES)
    for stage, command in commands.items():
        validate_command(command, stage, target["stack_type"])
    return target_id


def validate_command(command: Any, stage: str, engine: str) -> None:
    if command is None:
        return
    exact_keys(command, {"argv", "requires_credentials"})
    if type(command["requires_credentials"]) is not bool:
        raise Invalid("requires_credentials must be boolean.")
    if command["requires_credentials"] != (stage == "preview"):
        raise Invalid(
            "Only preview may require credentials; preview must declare them."
        )
    lexical_argv(command["argv"])
    substitutions = {
        "environment": "test",
        "stack": "test",
        "account_id": "123456789012",
        "region": "eu-west-1",
        "backend": "s3://example-state",
    }
    example = [
        substitutions[item[1:-1]] if item.startswith("{") else item
        for item in command["argv"]
    ]
    allowed_argv(example, stage, engine)


def git_output(root: Path, args: list[str]) -> bytes:
    command = [
        "git",
        "--no-optional-locks",
        "-c",
        "core.fsmonitor=false",
        "-C",
        str(root),
        *args,
    ]
    try:
        # Fixed Git metadata commands; PATH/toolchain are part of reviewed local trust.
        result = subprocess.run(  # nosec B603
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Invalid("Cannot read Git source identity.") from exc
    if result.returncode:
        raise Invalid("Command intentions require a repository with a Git commit.")
    return result.stdout


def source_identity(root: Path, profile_path: str) -> dict:
    sha = git_output(root, ["rev-parse", "HEAD"]).decode("ascii").strip()
    if not re.fullmatch(r"[0-9a-f]{40,64}", sha):
        raise Invalid("Invalid Git revision identity.")
    paths = snapshot_paths(root, profile_path)
    digest = hashlib.sha256()
    excluded = []
    sensitive_metadata = {}
    total_bytes = 0
    for encoded in sorted(set(paths)):
        name = source_filename(encoded)
        path = contained(root, name, must_exist=False)
        if secret_path(name):
            excluded.append(name)
            sensitive_metadata[name] = source_metadata(path)
            continue
        if path.is_dir():
            raise Invalid(
                "Submodule/directory source entries require separate targets."
            )
        digest.update(encoded + b"\0")
        if not path.exists():
            digest.update(b"MISSING\0")
            continue
        size = path.stat().st_size
        total_bytes += size
        if total_bytes > MAX_SOURCE_BYTES:
            raise Invalid("Source snapshot exceeds the byte limit.")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return {
        "git_sha": sha,
        "source_sha256": digest.hexdigest(),
        "excluded_sensitive_paths": excluded,
        "sensitive_file_metadata": sensitive_metadata,
    }


def snapshot_paths(root: Path, profile_path: str) -> list[bytes]:
    tracked = set(git_output(root, ["ls-files", "--cached", "-z"]).split(b"\0"))
    untracked = set(
        git_output(root, ["ls-files", "--others", "--exclude-standard", "-z"]).split(
            b"\0"
        )
    )
    paths = tracked | untracked
    if len(paths) > MAX_FILES + 1:
        raise Invalid("Source snapshot exceeds the file limit.")
    selected = []
    for encoded in sorted(paths):
        if not encoded:
            continue
        name = source_filename(encoded)
        if name == profile_path:
            continue
        if encoded not in tracked and any(
            part in SKIP_DIRS for part in PurePosixPath(name).parts
        ):
            continue
        selected.append(encoded)
    return selected


def source_filename(encoded: bytes) -> str:
    try:
        return encoded.decode("utf-8")
    except UnicodeError as exc:
        raise Invalid("Source filename is not UTF-8.") from exc


def source_metadata(path: Path) -> dict | None:
    if not path.exists():
        return None
    metadata = path.stat()
    return {
        "size": metadata.st_size,
        "mtime_ns": metadata.st_mtime_ns,
        "mode": metadata.st_mode,
    }


def canonical_hash(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(
            value, sort_keys=True, separators=(",", ":"), allow_nan=False
        ).encode()
    ).hexdigest()


def select(
    profile: dict, target_id: str, environment: str | None, stage: str
) -> tuple[dict, dict | None]:
    targets = [target for target in profile["targets"] if target["id"] == target_id]
    if not targets:
        raise Invalid("Unknown target.")
    target = targets[0]
    if environment is not None and environment not in target["environments"]:
        raise Invalid("Unknown target environment.")
    if stage == "preview" and not environment:
        raise Invalid("Preview requires an explicit configured environment.")
    return target, target["environments"].get(environment)


def build_plan(
    root: Path,
    profile_path: str,
    target_id: str,
    stage: str,
    environment: str | None,
    *,
    now: int | None = None,
) -> dict:
    if stage not in STAGES:
        raise Invalid("Unknown operation stage.")
    profile = validate_profile(root, profile_path)
    target, env = select(profile, target_id, environment, stage)
    command = target["commands"][stage]
    argv = command_argv(root, target, command, stage, environment, env)
    plan = {
        "schema_version": 1,
        "kind": "command-intention",
        "created_at": int(time.time()) if now is None else now,
        "profile": profile_path,
        "profile_sha256": canonical_hash(profile),
        "project": profile["project"],
        "target": target_id,
        "stack_type": target["stack_type"],
        "root": target["root"],
        "stage": stage,
        "environment": environment,
        "environment_config": env,
        "argv": argv,
        "requires_credentials": command["requires_credentials"] if command else False,
        "status": "PLANNED" if command else "SKIPPED",
        "executed": False,
        "source": source_identity(root, profile_path),
    }
    plan["intention_sha256"] = canonical_hash(plan)
    return plan


def command_argv(
    root: Path,
    target: dict,
    command: dict | None,
    stage: str,
    environment: str | None,
    env: dict | None,
) -> list[str] | None:
    if command is None:
        return None
    values = {"environment": environment, **(env or {})}
    argv = []
    for item in command["argv"]:
        replacement = values.get(item[1:-1]) if item.startswith("{") else item
        if not replacement:
            raise Invalid("Command placeholder requires an explicit environment.")
        argv.append(replacement)
    allowed_argv(argv, stage, target["stack_type"])
    bind_selectors(argv, target, environment, env)
    bind_output_path(root, target, argv)
    offset = {("uv", "run", "pytest"): 3, ("uv", "run", "ruff"): 4}.get(tuple(argv[:3]))
    if offset:
        for item in argv[offset:]:
            if not item.startswith("-"):
                contained(contained(root, target["root"]), item)
    return argv


def bind_selectors(
    argv: list[str], target: dict, environment: str | None, env: dict | None
) -> None:
    index = {"pulumi": 3, "terraspace": 2}.get(argv[0])
    if index and env and argv[index] != env["stack"]:
        raise Invalid("Engine argv stack differs from selected environment.")
    if argv[0] != "make":
        return
    bind_make_selectors(argv, target, environment, env)


def bind_make_selectors(
    argv: list[str], target: dict, environment: str | None, env: dict | None
) -> None:
    selectors = {
        "stack": (env or {}).get("stack"),
        "PULUMI_STACK": (env or {}).get("stack"),
        "env": environment,
        "PULUMI_DIR": target["root"],
    }
    for item in argv[2:]:
        key, value = item.split("=", 1)
        if key in selectors and value != selectors[key]:
            raise Invalid("Make selector differs from the selected target/environment.")
        if key == "stacks":
            raise Invalid(
                "Multi-stack Make execution requires separate target intentions."
            )


def bind_output_path(root: Path, target: dict, argv: list[str]) -> None:
    if argv[0] != "make":
        return
    for item in argv[2:]:
        if item.startswith("out="):
            value = item[4:]
            target_root = contained(root, target["root"])
            path = contained(target_root, value, must_exist=False)
            prefix = target_root / ARTIFACT_ROOT / "engine-plans"
            if not path.is_relative_to(prefix) or path == prefix or path.exists():
                raise Invalid("Engine plan output needs a new confined artifact path.")


def write_plan(root: Path, filename: str, plan: dict) -> None:
    path = contained(root, filename, must_exist=False)
    prefix = root / ARTIFACT_ROOT
    if not path.is_relative_to(prefix) or path == prefix:
        raise Invalid("Evidence output must be inside .artifacts/devops-sdlc/.")
    parent_fd = secure_directory(path.parent, create=True)
    try:
        file_fd = os.open(
            path.name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=parent_fd,
        )
        with os.fdopen(file_fd, "w", encoding="utf-8") as handle:
            json.dump(plan, handle, indent=2, sort_keys=True)
            handle.write("\n")
    except FileExistsError as exc:
        raise Invalid(
            "Evidence files are immutable; choose a new output path."
        ) from exc
    finally:
        os.close(parent_fd)


def secure_directory(path: Path, *, create: bool = False) -> int:
    if os.name != "posix":
        raise Invalid("Race-safe evidence writing currently requires POSIX.")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    descriptor = os.open("/", flags)
    try:
        for part in path.parts[1:]:
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
            following = os.open(part, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = following
    except OSError:
        os.close(descriptor)
        raise
    return descriptor


def verify_plan(
    root: Path, filename: str, max_age: int = MAX_AGE, *, now: int | None = None
) -> dict:
    integer(max_age, 1, 86400)
    stored = load_json(contained(root, filename))
    exact_keys(
        stored,
        {
            "schema_version",
            "kind",
            "created_at",
            "profile",
            "profile_sha256",
            "project",
            "target",
            "stack_type",
            "root",
            "stage",
            "environment",
            "environment_config",
            "argv",
            "requires_credentials",
            "status",
            "executed",
            "source",
            "intention_sha256",
        },
    )
    created = integer(stored["created_at"], 1, 2**53)
    current = int(time.time()) if now is None else now
    if created > current or current - created > max_age:
        raise Invalid("Command intention is stale or has a future timestamp.")
    identifier(stored["target"])
    string(stored["stage"])
    string(stored["profile"])
    if stored["environment"] is not None:
        identifier(stored["environment"])
    expected = build_plan(
        root,
        stored["profile"],
        stored["target"],
        stored["stage"],
        stored["environment"],
        now=created,
    )
    # Canonical JSON comparison preserves the distinction between bool and int.
    if json.dumps(stored, sort_keys=True) != json.dumps(expected, sort_keys=True):
        raise Invalid(
            "Command intention differs from current source/profile/selectors/argv."
        )
    return {
        "status": "VERIFIED",
        "kind": "command-intention",
        "executed": False,
        "intention_sha256": expected["intention_sha256"],
        "note": (
            "Integrity/freshness only; no authorship, authorization, "
            "engine plan or execution claim."
        ),
    }


def execute_plan(
    root: Path,
    plan: dict,
    *,
    trust_repo: bool,
    read_only_credentials: bool,
    timeout: int = 300,
) -> dict:
    integer(timeout, 1, 3600)
    if plan["argv"] is None:
        return {
            "status": "SKIPPED",
            "executed": False,
            "reason": "No configured command.",
        }
    if not trust_repo:
        raise Invalid(
            "Execution requires --trust-repo after review of repository "
            "code and toolchain."
        )
    if plan["requires_credentials"] and not read_only_credentials:
        raise Invalid(
            "Preview execution requires --read-only-credentials acknowledgement."
        )
    fresh = build_plan(
        root,
        plan["profile"],
        plan["target"],
        plan["stage"],
        plan["environment"],
        now=plan["created_at"],
    )
    if fresh != plan:
        raise Invalid(
            "Source/profile changed before execution; prepare a new intention."
        )
    cwd = contained(root, plan["root"])
    env = execution_environment(plan)
    if plan["requires_credentials"]:
        if plan["stack_type"] != "pulumi":
            raise Invalid(
                "Terraform/Terraspace preview execution requires backend attestation "
                "through the reviewed repository or CI handoff."
            )
        verify_aws_account(plan, env)
    return run_process(plan, cwd, env, timeout)


def execution_environment(plan: dict) -> dict[str, str]:
    env = {
        name: os.environ[name]
        for name in ("PATH", "HOME", "USER", "TMPDIR", "SYSTEMROOT")
        if name in os.environ
    }
    env.update(
        {"CI": "true", "GIT_TERMINAL_PROMPT": "0", "PULUMI_SKIP_UPDATE_CHECK": "true"}
    )
    if not plan["requires_credentials"]:
        env.update(
            {
                "AWS_EC2_METADATA_DISABLED": "true",
                "AWS_CONFIG_FILE": os.devnull,
                "AWS_SHARED_CREDENTIALS_FILE": os.devnull,
            }
        )
    if plan["environment_config"]:
        selected = plan["environment_config"]
        env.update(
            {
                "AWS_REGION": selected["region"],
                "AWS_DEFAULT_REGION": selected["region"],
                "AWS_ACCOUNT_ID": selected["account_id"],
                "TS_ENV": plan["environment"],
                "TF_WORKSPACE": selected["stack"],
                "PULUMI_STACK": selected["stack"],
                "PULUMI_BACKEND_URL": selected["backend"],
                "stack": selected["stack"],
                "env": plan["environment"],
            }
        )
    if plan["requires_credentials"]:
        for name in (
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY",
            "AWS_SESSION_TOKEN",
            "AWS_PROFILE",
            "AWS_WEB_IDENTITY_TOKEN_FILE",
            "AWS_ROLE_ARN",
        ):
            if name in os.environ:
                env[name] = os.environ[name]
    return env


def verify_aws_account(plan: dict, env: dict[str, str]) -> None:
    command = [
        "aws",
        "sts",
        "get-caller-identity",
        "--query",
        "Account",
        "--output",
        "text",
    ]
    try:
        # Fixed metadata-only STS command; output is compared, never echoed.
        result = subprocess.run(  # nosec B603
            command,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Invalid("AWS account metadata preflight could not complete.") from exc
    expected = plan["environment_config"]["account_id"].encode()
    if result.returncode or result.stdout.strip() != expected:
        raise Invalid("AWS caller account does not match the selected environment.")


def run_process(plan: dict, cwd: Path, env: dict[str, str], timeout: int) -> dict:
    started = time.monotonic()
    try:
        # Revalidated allowlisted argv, explicit trust, no shell, suppressed output.
        process = subprocess.Popen(  # nosec B603
            plan["argv"],
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=os.name == "posix",
        )
    except OSError as exc:
        raise Invalid(
            "Configured executable could not be started; inspect local tooling."
        ) from exc
    timed_out = False
    try:
        exit_code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        terminate_process_tree(process)
        exit_code = process.wait()
    return {
        "status": "TIMEOUT"
        if timed_out
        else ("COMPLETED" if exit_code == 0 else "FAILED"),
        "executed": True,
        "exit_code": exit_code,
        "duration_seconds": round(time.monotonic() - started, 3),
        "intention_sha256": plan["intention_sha256"],
        "output": "suppressed",
        "semantic_result": "UNVERIFIED",
        "note": (
            "Exit code is not proof of live safety; inspect authorized sanitized "
            "tool artifacts for skips and guardrail evidence."
        ),
    }


def terminate_process_tree(process: subprocess.Popen) -> None:
    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    else:
        process.kill()


def argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    for name in ("discover", "validate-profile", "plan", "verify-plan"):
        subparser = subcommands.add_parser(name)
        subparser.add_argument("--repo", required=True)
        if name in {"validate-profile", "plan"}:
            subparser.add_argument("--profile", default=PROFILE)
        if name == "plan":
            subparser.add_argument("--target", required=True)
            subparser.add_argument("--stage", required=True, choices=sorted(STAGES))
            subparser.add_argument("--environment")
            subparser.add_argument("--output")
            subparser.add_argument("--execute", action="store_true")
            subparser.add_argument("--trust-repo", action="store_true")
            subparser.add_argument("--read-only-credentials", action="store_true")
            subparser.add_argument("--timeout", type=int, default=300)
        if name == "verify-plan":
            subparser.add_argument("--plan", required=True)
            subparser.add_argument("--max-age-seconds", type=int, default=MAX_AGE)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = argument_parser().parse_args(argv)
    result: dict[str, Any]
    try:
        root = repository(args.repo)
        if args.command == "discover":
            result = discover(root)
        elif args.command == "validate-profile":
            profile = validate_profile(root, args.profile)
            result = {
                "status": "VALID",
                "schema_version": 1,
                "target_count": len(profile["targets"]),
            }
        elif args.command == "verify-plan":
            result = verify_plan(root, args.plan, args.max_age_seconds)
        else:
            plan = build_plan(
                root, args.profile, args.target, args.stage, args.environment
            )
            if args.output:
                write_plan(root, args.output, plan)
            result = {"intention": plan}
            if args.execute:
                result["execution"] = execute_plan(
                    root,
                    plan,
                    trust_repo=args.trust_repo,
                    read_only_credentials=args.read_only_credentials,
                    timeout=args.timeout,
                )
        print(json.dumps(result, indent=2, sort_keys=True))
        outcome = result.get("execution", result.get("intention", result))
        return 1 if outcome.get("status") in {"FAILED", "TIMEOUT", "SKIPPED"} else 0
    except (Invalid, OSError, UnicodeError, RecursionError) as exc:
        message = (
            str(exc)
            if isinstance(exc, Invalid)
            else "Repository input could not be read safely."
        )
        print(
            json.dumps({"status": "BLOCKED", "executed": False, "error": message}),
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
