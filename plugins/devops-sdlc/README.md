# DevOps SDLC

VilnaCRM's Claude Code plugin for Terraform, Terraspace and Python/Pulumi. It
coordinates BMAD planning, BMALPH implementation, independent infrastructure
review, E2E QA, CI fixes and review reconciliation through a draft PR. Operational
skills cover deployment preparation, drift, incidents, state migration, recovery,
cost, observability and environment lifecycle.

## Install

```text
/plugin marketplace add VilnaCRM-Org/claude-plugins
/plugin install devops-sdlc@vilnacrm-plugins
```

For development, load the checked-out plugin directly:

```bash
claude --plugin-dir /absolute/path/to/claude-plugins/plugins/devops-sdlc
```

The behavioral simulator also supports an authenticated Codex CLI through
`scripts/agent_cli.py`. Codex receives bounded plugin Markdown as explicit
context; it does not natively load this Claude plugin. Select the adapter with
`--backend auto|claude|codex` and order preflight with
`--prefer claude|codex`. `--model` and `--judge-model` are optional,
backend-specific runner and judge model choices. Auto fallback occurs only when
binary/authentication preflight fails; a selected CLI failure after start stops
the run.

Use an authenticated Claude Code installation, Python 3.10+, Git and GitHub CLI.
BMALPH is installed separately; this implementation was developed with BMALPH
2.11.0 and Claude Code 2.1.177. Each target uses its repository's pinned IaC,
Python/Ruby, container and validation dependencies. Generated BMAD/Ralph files
belong in the target repository and are not bundled with this plugin.

## Start

```text
/devops-sdlc:do-sdlc-setup
/devops-sdlc:do-sdlc Add ownership tags to the selected test infrastructure
```

Setup discovers projects without running their code, then prepares
`.claude/devops-sdlc.json` from reviewed repository entry points. Select a target
and environment explicitly. Existing valid profiles are preserved.

| Command | Result |
| --- | --- |
| `do-sdlc` | Resumable orchestration with independently verified stage exits |
| `do-sdlc-setup` | Discovery, profile and prerequisites |
| `do-sdlc-issue` | Existing issue or explicitly requested deduplicated issue |
| `do-sdlc-plan` | BMAD research, brief, PRD, architecture, stories and readiness |
| `do-sdlc-implement` | BMALPH/Ralph implementation and repository quality checks |
| `do-sdlc-review` | Requirements, security, state and recovery review |
| `do-sdlc-qa` | Independent operator E2E and positive/negative/edge verification |
| `do-sdlc-finish-pr` | Draft PR, current-head CI and all review-thread reconciliation |

Each stage has five attempts, persisted across retries and sessions. QA failures
return to implementation. A tripped Ralph breaker remains terminal for that run.
The plugin does not merge or publish a release.

## Repository helper

The Python helper uses the standard library and emits JSON. Set `PLUGIN` to the
installed plugin's absolute path:

```bash
python3 "$PLUGIN/scripts/devops.py" discover --repo .
python3 "$PLUGIN/scripts/devops.py" validate-profile --repo .
python3 "$PLUGIN/scripts/devops.py" plan --repo . --target example --stage validate
python3 "$PLUGIN/scripts/devops.py" plan --repo . --target example --stage preview \
  --environment test --output .artifacts/devops-sdlc/preview-intention.json
python3 "$PLUGIN/scripts/devops.py" verify-plan --repo . \
  --plan .artifacts/devops-sdlc/preview-intention.json
```

`plan` creates a **command intention**, not an engine saved plan or deployment
approval. Local execution additionally requires `--execute --trust-repo` after
reviewing the repository code. Preview additionally requires
`--read-only-credentials`; the caller must actually supply a restricted IAM role.
The flag cannot reduce credential privileges. See the exact
[profile and CLI contract](docs/profile-schema.md).

Terraform and Terraspace preview execution is currently blocked by the helper
because a profile string cannot attest the effective cached backend. It still
prepares preview intentions; the engine skills use the repository's protected,
reviewed plan workflow. Pulumi preview additionally verifies the current AWS
account through STS and sets the selected backend and stack.

The helper rejects direct apply/destroy and state/credential mutation commands.
It does not sandbox Makefiles, Python programs, providers, binaries or Claude.
Repository command execution is a trust boundary even when a target is named
`test` or `validate`. Cloud deployment uses a separately scoped, reviewed handoff
through the repository's protected workflow and actual saved-plan controls.

## Engine behavior

| Engine | Preserved contracts |
| --- | --- |
| Terraform | Provider/module locks, backend and locking identity, saved plans, detailed exit codes |
| Terraspace | App stacks, `TS_ENV`, dependency ordering, actual Make/buildspec and CodePipeline revisions |
| Python/Pulumi | Project roots, uv/container commands, tests and policies, stack/backend/KMS identity, protected promotion |

Existing VilnaCRM examples include `website-infrastructure` and
`crm-infrastructure` for Terraspace, and `infrastructure-template`,
`bootstrap-infrastructure`, `user-service-infrastructure` and
`api-gateway-infrastructure` for Pulumi. Repository capabilities differ; example
or metadata-only programs do not prove a deployed service. Source evidence and
revisions are recorded in the [BMAD research](../../specs/autonomous/2026-09-05-devops-sdlc-plugin/research.md).

## Evidence and automation target

The target is true 90% coverage of a frozen eligible-task inventory, supported
by traceable accepted work and operational evidence. Supported workflow families,
synthetic benchmark successes, behavioral simulations, real completed operations
and hands-on time saved are separate measurements. This release does not claim
an observed 90% production automation rate without that reviewed inventory and
field evidence.

PASSED, FAILED, SKIPPED and BLOCKED remain distinct. Missing required credentials,
placeholder previews, stale plans, empty CI checks or incomplete review pages
cannot satisfy completion. Reports retain source SHA, target/environment,
provenance, observations and unresolved prerequisites. No raw state, decrypted
secrets or sensitive plan payloads belong in reports.

See the [skill inventory](skills/SKILL-DECISION-GUIDE.md),
[agent boundaries](skills/AI-AGENT-GUIDE.md),
[test strategy](docs/testing/test-strategy.md),
[test plan](docs/testing/test-plan.md) and
[case catalog](docs/testing/test-cases.md).

## Validation

From the marketplace repository root:

```bash
python3 tools/plugin-quality/lint/lint_all.py plugins/devops-sdlc
claude plugin validate plugins/devops-sdlc --strict
python3 -m unittest discover -s plugins/devops-sdlc/tests
python3 tools/plugin-quality/judge/run_judge.py plugins/devops-sdlc \
  --gate --require --votes 3 --model sonnet --report prompt-judge-report.md
```

The live judge requires an authenticated selected Claude or Codex CLI. It runs a
no-tool behavioral simulation and calibration; it is not runtime E2E. Actual
manual CLI E2E is independent evidence for plans, provider actions, rollback and
recovery, and deterministic fixtures never substitute for it. The test campaign
report records observed results and any remaining external prerequisites.
