# DevOps SDLC repository profile

The runtime reads `.claude/devops-sdlc.json`. Discovery prints candidates and
Make target names by reading source text; it never runs Make, installs tools,
initializes a backend, or writes a profile. Review the candidates, then create
the profile with the setup command. Preserve an existing profile unless the
user has authorized its update.

## Version 1

| Field | Contract |
| --- | --- |
| `schema_version` | Integer `1`; booleans do not count as integers. |
| `project` | Exactly `name` and `repo`; repo is non-empty `owner/name` for GitHub routing. |
| `project.name` | Non-empty display name, at most 160 characters. |
| `project.repo` | GitHub repository identity in `owner/name` form. Schema validation is not authorization; the issue command binds this destination to the authorized task repository and origin before GitHub access. |
| `targets` | 1–100 objects with unique `id` values. |
| `id` | 1–80 letters, digits, dots, underscores or hyphens; starts alphanumeric. |
| `stack_type` | `terraform`, `terraspace` or `pulumi`. |
| `root` | Existing repository-relative command working directory; `.` is allowed. No absolute paths, parent traversal or symlink components. |
| `environments` | Object keyed by environment ID; may be empty for local-only targets; at most 50 entries. |
| Environment entry | Exactly `stack`, 12-digit AWS `account_id`, `region`, and non-secret `backend`. |
| Terraspace `stack` | Same 1–80 character identifier grammar as `id`; slash-containing or longer selectors fail profile validation before planning. |
| `backend` | An `s3://`, absolute `file:///` or `https://` identifier; no credentials, query strings, fragments or parent traversal. |
| `commands` | All five keys required: `validate`, `test`, `check`, `security`, `preview`. |
| Command entry | `null`, or exactly `argv` and boolean `requires_credentials`. |
| `argv` | 2–40 non-empty string tokens, up to 512 characters each, passing the stage/tool allowlist. No shell evaluation. |
| `requires_credentials` | False for local stages; true for a configured preview command. |

```json
{
  "schema_version": 1,
  "project": {
    "name": "Example infrastructure",
    "repo": "example/infrastructure"
  },
  "targets": [
    {
      "id": "platform",
      "stack_type": "pulumi",
      "root": ".",
      "environments": {
        "test": {
          "stack": "test",
          "account_id": "123456789012",
          "region": "eu-west-1",
          "backend": "s3://example-test-state"
        }
      },
      "commands": {
        "validate": {
          "argv": ["make", "test-pulumi"],
          "requires_credentials": false
        },
        "test": {
          "argv": ["make", "test-unit"],
          "requires_credentials": false
        },
        "check": {
          "argv": ["make", "doctor"],
          "requires_credentials": false
        },
        "security": null,
        "preview": {
          "argv": ["make", "pulumi-preview"],
          "requires_credentials": true
        }
      }
    }
  ]
}
```

This is a schema example, not a recommendation to use these targets in every
repository. Keep only commands discovered and reviewed in the target repository.
The account and backend above are illustrative.

Unknown keys, duplicate JSON keys, malformed types, non-finite numbers, control
characters and oversized profiles are rejected. Profiles must contain only
non-secret identifiers and commands.

Choose `root` for the actual command working directory. A repository-root
Makefile generally needs `root: "."`; direct Pulumi CLI commands generally need
the directory containing `Pulumi.yaml`. Discovery reports both engine directories
and Makefile paths so setup can choose deliberately. It does not assume an
example stack is deployed.

## Command planning and execution

Run from any directory, substituting the installed plugin script path:

```sh
python3 scripts/devops.py discover --repo /path/to/repository
python3 scripts/devops.py validate-profile --repo /path/to/repository
python3 scripts/devops.py plan --repo /path/to/repository --target platform --stage validate
python3 scripts/devops.py plan --repo /path/to/repository --target platform --stage preview --environment test --output .artifacts/devops-sdlc/test-intention.json
python3 scripts/devops.py verify-plan --repo /path/to/repository --plan .artifacts/devops-sdlc/test-intention.json
```

Planning does not execute the configured command. It requires a Git repository
with a commit and records both the current commit and current working source.
Use `--profile` for a different contained profile path.

For local execution, add `--execute --trust-repo` to `plan`. The trust flag means
the caller has already reviewed the relevant repository code and toolchain.
It does not sandbox Make, pytest, Python imports, providers, Docker or the host.
Even a target named `test` can run arbitrary repository code. The runtime never
interprets a profile as permission to run it.

Pulumi preview execution additionally requires `--environment NAME` and
`--read-only-credentials`. Before starting the preview it runs the fixed
metadata-only command `aws sts get-caller-identity --query Account --output text`
and rejects an account mismatch or failed preflight. The flag acknowledges
appropriate read-only credential scope; STS identity does not prove IAM
permissions are read-only. Use short-lived credentials already provided by
the authorized workflow.

Terraform and Terraspace preview intentions are supported. Their runtime
`--execute` preview path is blocked because this helper cannot safely attest the
cached backend without reading potentially secret-bearing state. Use the
existing protected repository/CI preview flow, verify its account, backend,
workspace/stack, source SHA and artifacts, then retain sanitized evidence.
Do not weaken this block by relabeling the engine.

There is no helper command for apply, destroy, refresh, import, state repair,
backend initialization, secrets changes or deployment. Those operations require
the reviewed repository workflow and its existing authorization controls.

## Selector and tool rules

Only whole-token placeholders are substituted:
`{environment}`, `{stack}`, `{account_id}`, `{region}`, `{backend}`.
For example a direct Pulumi preview may use:

```json
["pulumi", "preview", "--stack", "{stack}", "--non-interactive"]
```

Embedded strings such as `stack={stack}` are rejected. Make receives the selected
environment through `TS_ENV` and `env`, and the selected stack through
`PULUMI_STACK` and `stack`. The runtime also sets `TF_WORKSPACE`,
`AWS_ACCOUNT_ID`, `AWS_REGION`, `AWS_DEFAULT_REGION`, and
`PULUMI_BACKEND_URL` from the selection. Explicit Make `env=`, `stack=`,
`PULUMI_STACK=`, or `PULUMI_DIR=` arguments must match that selection.
Direct engine stack arguments must match the selected stack.

These supplied values are a command contract, not independent proof of a
provider's destination. Reviewed repository code must honor them. A Pulumi
program can define additional providers; STS preflight only attests the caller
identity used by that preflight.

The allowlist supports specific existing Make test/quality/security/preview
targets, direct Terraform validation and check-only formatting, direct
Terraspace validation, Pulumi preview, and bounded `uv run pytest`/`uv run ruff`
forms. The exact allowlist lives in
[`devops.py`](../scripts/devops.py). Engine-specific Make prefixes must match
`stack_type`. Unknown tools, arbitrary Python scripts, shells, alternate
Makefiles, overriding `SHELL`, mutation verbs, destructive flags and automatic
format fixes are rejected. Unsupported repository commands need a reviewed
adapter change or a documented repository handoff.

All-stack preview commands and multi-stack Make assignments are rejected.
Create separate target intentions. Engine plan output arguments must select a
new path inside the target's `.artifacts/devops-sdlc/engine-plans/`; they must
not overwrite a file or traverse a symlink.

For local stages the inherited environment is reduced and conventional AWS
shared-config/credential lookup and EC2 metadata are disabled. Repository code
is still trusted code, so this does not establish credential isolation.
Raw child stdout/stderr are suppressed. The runtime reports only exit code,
duration and status; obtain authorized sanitized repository artifacts
separately for diagnosis and semantic validation.

## Intention evidence

`--output` creates a new JSON intention file under
`.artifacts/devops-sdlc/`. It never overwrites an existing file. Evidence writing
currently requires POSIX and uses descriptor-anchored directory traversal with
no-follow flags and exclusive creation, including protection against parent
symlink swaps. File mode is `0600`.

The intention binds the profile content hash, Git HEAD, selected target,
environment configuration, stage, argv, source snapshot and creation time.
`verify-plan` rebuilds the intention from current inputs and compares it exactly.
It rejects changed source, profile, selectors or argv, mismatched types,
future timestamps and stale intentions. Default maximum age is 3,600 seconds;
`--max-age-seconds` accepts 1–86,400.

Tracked non-sensitive files are hashed even under directories named `build`,
`dist` or `vendor`. Untracked generated/cache/artifact directories are excluded
by fixed runtime rules. Sensitive filenames, including Pulumi stack configs,
credential/token files, key files and `.env` files, are not read: discovered
entries bind only size, modification time and mode. Git HEAD still invalidates
evidence when committed sensitive inputs change.

Sensitive metadata is not cryptographic proof of content. Ignored untracked
files, external dependencies, the toolchain, cloud state and credentials are
not fully attested by this snapshot. Limits prevent unbounded scans; large or
unsupported repositories fail visibly instead of producing partial proof.
Hash agreement establishes neither authorship nor user authorization.

An intention is **not** a Terraform saved plan, a Pulumi update plan, a
deployment approval, or evidence of a completed preview. The repository's
actual saved-plan provenance and live controls remain separate requirements.

## Outcomes and timeouts

- `PLANNED`: command intention generated, no command executed.
- `SKIPPED`: command is `null`; exit status 1, never a passed required check.
- `COMPLETED`: process returned zero; `semantic_result: UNVERIFIED`.
- `FAILED`/`TIMEOUT`: execution failed; exit status 1.
- `BLOCKED`: invalid input or unmet safety precondition; exit status 2.
- `VERIFIED`: current command-intention integrity/freshness matched; no execution.

A command returning zero may still have skipped live checks. Required QA must
examine sanitized repository evidence and must not translate `COMPLETED` or
`VERIFIED` into deployment success. The runtime timeout defaults to 300 seconds
and accepts 1–3,600. On POSIX a timed-out command's process group is killed and
reaped; execution on other platforms has a narrower direct-process termination
guarantee.
