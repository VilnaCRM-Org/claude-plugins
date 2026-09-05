# Behavioral simulation strategy

`tests/behavior_judge.py` evaluates 30 catalog scenarios in an inert,
disposable fixture. It is a no-tool behavioral simulation, not runtime E2E or
an operational test. The fixture has only minimal Terraform, Terraspace and
Pulumi metadata and a reviewed profile; it has no credentials, state, provider
configuration, or cloud resources.

The runner receives the plugin command explicitly. Claude uses the native
plugin directory. Codex does **not** natively load a Claude plugin:
`scripts/agent_cli.py` supplies bounded command, agent and skill Markdown as
explicit prompt context. Both backends run with tools disabled. The independent
judge receives no plugin directory or plugin context and scores only the
candidate response against its structured schema.

Choose the adapter with `--backend auto|claude|codex`; `--prefer claude|codex`
orders auto preflight. `--model` sets an optional runner model and
`--judge-model` sets an optional independent-judge model. Fallback is permitted
only when binary/authentication preflight fails. Once a CLI starts, a timeout,
bad envelope, failed process, or invalid response stops the run; the adapter
does not switch backends after start.

The report retains redacted, bounded prompts and outputs, timestamps, selected
backend/version/model, catalog and plugin hashes, verdicts and counts. Missing
auth, malformed output, incomplete observations, calibration errors, and empty
or unknown selections fail closed. A successful simulation must never claim a
real plan, credential, approval, deployment, rollback, or provider outcome.

Actual CLI E2E is independently authorized and produces separate evidence in a
disposable account/workflow. It is required to establish provider behavior,
saved-plan controls, deployment, rollback, and recovery. Simulation results do
not count as operational coverage.
