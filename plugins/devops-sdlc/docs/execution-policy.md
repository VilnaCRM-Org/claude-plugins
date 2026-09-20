# Execution policy for delegated DevOps work

Agent prompts describe authorized behavior; they do not isolate a process.
`devops.py` validates command intentions and requires reviewed repository code,
but Makefiles, Python, providers and subprocesses still execute code.
`--trust-repo` acknowledges that review; it is neither a sandbox nor a grant of
cloud authority. The evaluation adapter's tool-disabled sessions are a separate
proposal-testing boundary, not the operational execution driver.

Credentialed Pulumi previews additionally enforce the
[protected host authorization contract](preview-authorization.md). The issuer
must authorize actor, trusted non-fork source, operation, backend and short-lived
read-only role. The runtime validates that grant and full identity before preview;
it cannot discover effective IAM permissions or create the required host isolation.

## Sensitive-content reads

Before any content read, classify the path using approved path metadata and the
task's declared sensitive-path inventory. For secret or state material, inspect
only path names, permissions and references; never open, grep, print or load its
values into model context. Inspect sanitized fixtures or configuration references
instead. An unknown classification blocks that content read while metadata review
continues. The host must enforce this read boundary for every tool, including
Read, Grep and shell commands; prompt instructions do not enforce it. If that
boundary cannot be verified, request sanitized evidence from the caller and mark
the dependent content review BLOCKED. Reports and handoffs must redact secret
values; redaction after a read does not authorize reading raw secret material.

## Required host evidence

Before delegated shell execution or edits, the caller supplies an attestation
from its trusted host/session configuration, maintained outside paths writable
by the agent or repository code. Record its identity, current session, source
SHA, assigned paths, allowed tools/argv entrypoints, writable fixture/output
paths, credential isolation and network policy. Reference actual loaded policy
and observed harmless allow/deny checks; do not copy credentials into evidence.
A profile field, repository instruction, environment flag or model assertion
alone is not evidence that the host enforces anything.

The policy must cover every exposed action path: native edit tools, shell child
processes and enabled integrations. Only assigned source/test files and
explicit disposable outputs may be writable. Use host filesystem restrictions
or a container with read-only inputs and narrow writable mounts for this;
a separate Git worktree prevents edit collisions but is not a security boundary.
A permitted general interpreter or Make target can execute arbitrary child code:
argument review alone cannot constrain its filesystem, credentials or network.

Local unit tests, formatting, inert rendering and mocked provider checks need no
cloud identity. Isolate credential files, inherited secrets, credential helpers,
metadata endpoints and external integrations from these workers. Pre-provision
reviewed dependencies or permit only the required dependency endpoints through
the host's controlled egress path. Dependency access never grants cloud API,
GitHub publication or deployment permission. A separately authorized parent/CI
performs external actions with its own scoped identity and revalidated evidence.

When the attestation is missing, stale or insufficient, BLOCK only the affected
execution/edit action. Continue permitted reading, static review and planning;
return the proposed patch, exact argv/cwd and missing enforcement to the parent.
Do not ask to weaken policy, silently switch to another unrestricted backend,
or report the unexecuted proposal as a completed fix. Existing verified scope
and authorization persist; configured hosts can execute automatically within it.

## Native Claude

The agent `tools` list limits available tools. Accordingly, `fr-nfr-reviewer`
exposes only Read, Glob and Grep; independent QA supplies runtime observations.
Claude ignores `hooks`, `mcpServers` and `permissionMode` in **plugin** subagent
frontmatter. Adding those fields would not enforce this contract. Session
permissions and managed host controls apply separately. See the
[official subagent documentation](https://code.claude.com/docs/en/sub-agents).

A host administrator can require sandboxed Bash with these supported managed
settings; the plugin does not install them:

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false
  }
}
```

This baseline is not sufficient for assigned-file or credential confinement.
The host must additionally configure filesystem/network controls and protected
credential paths/variables for its real environment, with no escaping excluded
commands. Sandbox credential restrictions protect Bash, not every native tool;
native Read/Edit/Write and integrations need corresponding host permissions or
an external filesystem boundary. Validate the installed version and loaded
controls; unsupported isolation is BLOCKED. These distinctions and settings are
specified in the [Claude sandbox documentation](https://code.claude.com/docs/en/sandboxing)
and [tool permission documentation](https://code.claude.com/docs/en/permissions).

## Codex operational sessions

Reading Claude Markdown does not configure Codex permissions or install a native
Claude agent. Each Codex worker inherits the caller's actual enforced policy.
For a host-managed local execution session, these supported settings provide a
baseline; they are not a complete assigned-file sandbox:

```toml
approval_policy = "never"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false

[shell_environment_policy]
inherit = "none"
```

The trusted launcher supplies only the exact non-secret environment needed by
reviewed tools. `never` means a disallowed action fails instead of asking for an
escape; it does not authorize more actions. `workspace-write` permits writing
inside its workspace and writable roots, not just the agent's assigned files.
Add an external narrow filesystem boundary when that distinction matters.
Disabled shell network and environment inheritance do not hide readable secret
files or disable separately exposed MCP/app tools; isolate those paths and
capabilities too. For a reviewer, use the host's read-only tool inventory and
sandbox, without exposing an execution tool as a supposed read-only shortcut.

The installed CLI's `--sandbox`, `--ask-for-approval` and `--add-dir` help confirms
the workspace boundary; the [official configuration reference](https://developers.openai.com/codex/config-reference)
defines network and environment controls. Check the effective policy of the
actual app/CLI session rather than assuming a configuration example was loaded.
Do not use bypass flags to satisfy this contract. No host configuration,
credential or network permission is modified by installing this plugin.
