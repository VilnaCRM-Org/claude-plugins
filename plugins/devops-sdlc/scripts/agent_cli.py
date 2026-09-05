#!/usr/bin/env python3
"""Run structured, read-only evaluations through authenticated Claude or Codex.

Fallback occurs only during binary/auth preflight. This is an evaluation adapter,
not a code execution or mutation driver. CLI defaults are never model aliases.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

BACKENDS = ("claude", "codex")
MAX_BYTES = 2_000_000
MAX_CONTEXT = 300_000
CODEX_CONFIG = (
    "features.shell_tool=false",
    "features.unified_exec=false",
    "features.apps=false",
    "features.plugins=false",
    "features.hooks=false",
    "features.multi_agent=false",
    "features.browser_use=false",
    "features.computer_use=false",
    "features.image_generation=false",
    "project_doc_max_bytes=0",
    'web_search="disabled"',
)


class AdapterError(ValueError):
    """Safe user-facing error with no raw model or authentication output."""


def probe_backend(name: str) -> dict[str, Any]:
    if name not in BACKENDS:
        raise AdapterError("Unknown backend.")
    result: dict[str, Any] = dict(
        backend=name,
        available=False,
        authenticated=False,
        version=None,
        reason="binary-missing",
    )
    binary = shutil.which(name)
    if binary is None:
        return result
    result["available"] = True
    try:
        version = probe_command([binary, "--version"])
        auth = probe_command(
            [binary, "auth", "status"]
            if name == "claude"
            else [binary, "login", "status"]
        )
        result["version"] = (
            version.stdout.strip().splitlines()[0][:160]
            if version.stdout.strip()
            else None
        )
        result["authenticated"] = auth_ok(name, auth)
        result["reason"] = (
            "ready" if result["authenticated"] else "authentication-unavailable"
        )
    except (OSError, subprocess.TimeoutExpired, ValueError):
        result["reason"] = "preflight-unavailable"
    return result


def probe_command(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        timeout=10,
    )  # nosec B603


def auth_ok(name: str, result: subprocess.CompletedProcess[str]) -> bool:
    if result.returncode:
        return False
    if name == "claude":
        body = json.loads(result.stdout)
        return isinstance(body, dict) and body.get("loggedIn") is True
    return bool(re.search(r"(?im)^logged in using\b", result.stdout + result.stderr))


def detect_backends() -> list[dict[str, Any]]:
    return [probe_backend(name) for name in BACKENDS]


def select_backend(backend: str = "auto", prefer: str = "claude") -> dict[str, Any]:
    if backend not in ("auto", *BACKENDS) or prefer not in BACKENDS:
        raise AdapterError("Invalid backend selection.")
    order = (
        [backend]
        if backend != "auto"
        else [prefer, next(n for n in BACKENDS if n != prefer)]
    )
    fallback = []
    for name in order:
        probe = probe_backend(name)
        if probe["authenticated"]:
            return {**probe, "status": "READY", "fallback": fallback}
        fallback.append({"backend": name, "reason": probe["reason"]})
    return {
        "status": "BLOCKED",
        "backend": None,
        "version": None,
        "reason": "No selected authenticated CLI is available.",
        "fallback": fallback,
    }


def read_bounded(path: Path, limit: int = MAX_BYTES) -> str:
    if (
        any(p.is_symlink() for p in (path, *path.parents))
        or not path.is_file()
        or path.stat().st_size > limit
    ):
        raise AdapterError("Input is missing, symlinked, or exceeds the size limit.")
    return path.read_text(encoding="utf-8")


def plugin_context(plugin_root: Path | str | None) -> tuple[Path | None, str]:
    if plugin_root is None:
        return None, ""
    root = Path(plugin_root).absolute()
    if any(part.is_symlink() for part in (root, *root.parents)) or not root.is_dir():
        raise AdapterError("Plugin root must be an existing non-symlink directory.")
    validate_plugin_manifest(root)
    context = read_plugin_components(root)
    if len(context.encode()) > MAX_CONTEXT:
        raise AdapterError("Plugin context exceeds the evaluation limit.")
    return root, context


def validate_plugin_manifest(root: Path) -> None:
    manifest = json.loads(read_bounded(root / ".claude-plugin/plugin.json"))
    metadata = {
        "name",
        "version",
        "description",
        "author",
        "homepage",
        "repository",
        "license",
        "keywords",
    }
    if not isinstance(manifest, dict) or set(manifest) - metadata:
        raise AdapterError("Evaluation cannot load executable plugin integrations.")
    if any(
        (root / name).exists()
        for name in ("hooks", ".mcp.json", ".lsp.json", "monitors")
    ):
        raise AdapterError("Evaluation cannot load executable plugin integrations.")


def read_plugin_components(root: Path) -> str:
    chunks = []
    for folder in ("commands", "agents", "skills"):
        directory = root / folder
        if directory.is_symlink():
            raise AdapterError("Plugin component directories must not be symlinks.")
        for path in sorted(directory.rglob("*.md")):
            body = read_bounded(path, MAX_CONTEXT)
            if re.search(r"!\s*`", body):
                raise AdapterError(
                    "Evaluation cannot load dynamic shell prompt expansion."
                )
            chunks.append(f"\n--- {path.relative_to(root).as_posix()} ---\n{body}")
    return "".join(chunks)


def validate_request(
    prompt: str, schema: dict, cwd: Path | str, model: str | None, timeout: int
) -> Path:
    validate_prompt_schema(prompt, schema)
    validate_options(model, timeout)
    return validate_directory(cwd)


def validate_prompt_schema(prompt: str, schema: dict) -> None:
    if (
        not isinstance(prompt, str)
        or not prompt.strip()
        or len(prompt.encode()) > MAX_CONTEXT
    ):
        raise AdapterError("Prompt must be non-empty and bounded.")
    if type(schema) is not dict or schema.get("type") != "object":
        raise AdapterError("Schema must describe a JSON object.")


def validate_options(model: str | None, timeout: int) -> None:
    if type(timeout) is not int or not 1 <= timeout <= 3600:
        raise AdapterError("Timeout must be an integer from 1 to 3600 seconds.")
    if model is not None and (
        not isinstance(model, str)
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,159}", model)
    ):
        raise AdapterError(
            "Model must be an explicit bounded backend model identifier."
        )


def validate_directory(cwd: Path | str) -> Path:
    root = Path(cwd).absolute()
    if not root.is_dir() or any(p.is_symlink() for p in (root, *root.parents)):
        raise AdapterError(
            "Working directory must be an existing non-symlink directory."
        )
    # User/project config can add unsandboxed MCP tools even with read-only shell.
    if any((p / ".codex/config.toml").exists() for p in (root, *root.parents)):
        raise AdapterError(
            "Evaluation directory must not inherit project Codex configuration."
        )
    return root


def evaluation_argv(
    backend: str,
    schema: dict,
    cwd: Path,
    temporary: Path,
    model: str | None,
    plugin: Path | None,
) -> list[str]:
    binary = shutil.which(backend)
    if binary is None:
        raise AdapterError("Selected CLI disappeared before execution.")
    if backend == "claude":
        argv = [
            binary,
            "-p",
            "--output-format",
            "json",
            "--json-schema",
            json.dumps(schema),
            "--tools",
            "",
            "--permission-mode",
            "plan",
            "--no-session-persistence",
            "--setting-sources",
            "",
            "--strict-mcp-config",
            "--mcp-config",
            '{"mcpServers":{}}',
            "--settings",
            '{"disableAllHooks":true}',
            "--no-chrome",
        ]
        if plugin is not None:
            argv += ["--plugin-dir", str(plugin)]
    else:
        schema_file = temporary / "schema.json"
        schema_file.write_text(json.dumps(schema), encoding="utf-8")
        argv = [
            binary,
            "exec",
            "--json",
            "--sandbox",
            "read-only",
            "--ignore-user-config",
            "--ephemeral",
            "--skip-git-repo-check",
            "-C",
            str(cwd),
            "--output-schema",
            str(schema_file),
            "--output-last-message",
            str(temporary / "answer.json"),
        ]
        for value in CODEX_CONFIG:
            argv += ["-c", value]
    if model is not None:
        argv += ["--model", model]
    return argv


def terminate(process: subprocess.Popen) -> None:
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
    except ProcessLookupError:
        pass
    process.wait()


def invoke(
    argv: list[str], prompt: str, cwd: Path, temporary: Path, timeout: int
) -> tuple[int, str]:
    with (temporary / "stdout.json").open("w+", encoding="utf-8") as output:
        process = subprocess.Popen(
            argv,
            cwd=cwd,
            stdin=subprocess.PIPE,
            stdout=output,
            stderr=subprocess.DEVNULL,
            text=True,
            start_new_session=os.name == "posix",
        )  # nosec B603
        try:
            process.communicate(input=prompt, timeout=timeout)
        except subprocess.TimeoutExpired:
            terminate(process)
            raise
    return process.returncode, read_bounded(temporary / "stdout.json")


def decode_answer(backend: str, raw: str, temporary: Path) -> tuple[dict, str | None]:
    if backend == "codex":
        answer = json.loads(read_bounded(temporary / "answer.json"))
        model = None
    else:
        envelope = json.loads(raw)
        if not isinstance(envelope, dict) or envelope.get("is_error"):
            raise AdapterError("CLI reported an invalid or failed response envelope.")
        answer = envelope.get("structured_output")
        if answer is None:
            answer = json.loads(envelope.get("result", ""))
        usage = envelope.get("modelUsage", {})
        model = (
            next(iter(usage)) if isinstance(usage, dict) and len(usage) == 1 else None
        )
    if type(answer) is not dict:
        raise AdapterError("CLI final response is not a JSON object.")
    return answer, model


def run_prompt(
    prompt: str,
    schema: dict,
    cwd: Path | str,
    *,
    backend: str = "auto",
    prefer: str = "claude",
    model: str | None = None,
    plugin_root: Path | str | None = None,
    timeout: int = 300,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": "BLOCKED",
        "backend": None,
        "version": None,
        "model": None,
        "observed_model": None,
        "model_source": "unreported",
        "requested_model": model,
        "fallback": [],
        "plugin_mode": "none",
        "output": None,
        "text": "",
    }
    try:
        root = validate_request(prompt, schema, cwd, model, timeout)
        plugin, context = plugin_context(plugin_root)
        selection = select_backend(backend, prefer)
        result.update(
            {k: selection[k] for k in ("status", "backend", "version", "fallback")}
        )
        if selection["status"] == "BLOCKED":
            result["reason"] = selection["reason"]
            return result
        return run_selected(
            prompt, schema, root, model, plugin, context, timeout, result
        )
    except subprocess.TimeoutExpired:
        result.update(
            status="TIMEOUT", reason="Evaluation timed out; no fallback was attempted."
        )
    except (AdapterError, OSError, ValueError, TypeError):
        result.update(
            status="BLOCKED",
            reason="Invalid input, CLI capability, or response; no retry attempted.",
        )
    return result


def run_selected(
    prompt: str,
    schema: dict,
    root: Path,
    model: str | None,
    plugin: Path | None,
    context: str,
    timeout: int,
    result: dict,
) -> dict:
    backend = result["backend"]
    result["plugin_mode"] = (
        ("native-claude" if backend == "claude" else "explicit-context")
        if plugin
        else "none"
    )
    if backend == "codex" and context:
        prompt = (
            "Evaluate using explicit plugin source context. "
            "This is not a native Claude plugin session.\n"
            + context
            + "\nTASK:\n"
            + prompt
        )
    with tempfile.TemporaryDirectory(prefix="devops-agent-eval-") as directory:
        temporary = Path(directory)
        argv = evaluation_argv(backend, schema, root, temporary, model, plugin)
        code, raw = invoke(argv, prompt, root, temporary, timeout)
        if code:
            return {
                **result,
                "status": "FAILED",
                "reason": "CLI failed after execution started; no fallback attempted.",
            }
        answer, observed_model = decode_answer(backend, raw, temporary)
    return {
        **result,
        "status": "COMPLETED",
        "model": observed_model or model,
        "observed_model": observed_model,
        "model_source": model_provenance(observed_model, model),
        "output": answer,
        "text": json.dumps(answer, sort_keys=True),
        "reason": "Evaluation completed; unreported CLI-default model remains null.",
    }


def model_provenance(observed: str | None, requested: str | None) -> str:
    if observed is not None:
        return "observed"
    return "requested" if requested is not None else "unreported"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("detect", "run"))
    parser.add_argument("--backend", choices=("auto", *BACKENDS), default="auto")
    parser.add_argument("--prefer", choices=BACKENDS, default="claude")
    parser.add_argument("--cwd", default=".")
    parser.add_argument("--schema")
    parser.add_argument("--plugin-root")
    parser.add_argument("--model")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args(argv)
    try:
        if args.command == "detect":
            result = select_backend(args.backend, args.prefer)
        else:
            if not args.schema:
                raise AdapterError("Run requires --schema.")
            schema = json.loads(read_bounded(Path(args.schema)))
            result = run_prompt(
                sys.stdin.read(MAX_CONTEXT + 1),
                schema,
                args.cwd,
                backend=args.backend,
                prefer=args.prefer,
                model=args.model,
                plugin_root=args.plugin_root,
                timeout=args.timeout,
            )
    except (AdapterError, OSError, ValueError):
        result = {"status": "BLOCKED", "reason": "Invalid evaluation request."}
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] in {"READY", "COMPLETED"} else 2


if __name__ == "__main__":
    raise SystemExit(main())
