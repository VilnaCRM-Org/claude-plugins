# Skill decision guide

The gate contract is: **every skill verdict recorded, no silent skips**.
At planning and independent review, record each skill as PASSED, FAILED,
SKIPPED (inapplicable with reason), or BLOCKED (missing prerequisites).
Every applicable skill is a required gate and needs inspected evidence to PASS.
Only a trigger outside the requested task may be SKIPPED with a reason.
Reassess applicability after each scope or source change.

## Complete inventory

- [backup-recovery](backup-recovery/SKILL.md) — Use when assessing backups, restore drills, RPO/RTO or disaster recovery. Use state-migration for state ownership transfers and delivery-and-rollback for reverting a release.
- [bmad-autonomous-planning](bmad-autonomous-planning/SKILL.md) — Use when turning infrastructure work into BMAD requirements, architecture, stories and a readiness handoff. Use infrastructure-quality for checking existing code; implementation execution is a separate command stage, outside this skill.
- [cost-optimization](cost-optimization/SKILL.md) — Use when assessing infrastructure spend, budgets, quotas or rightsizing proposals. Use observability for non-cost telemetry and environment-lifecycle for approved retirement execution.
- [delivery-and-rollback](delivery-and-rollback/SKILL.md) — Use when preparing saved-plan promotion, deployment health gates or release rollback. Use incident-response for broader incident triage and state-migration for backend ownership changes.
- [drift-management](drift-management/SKILL.md) — Use when comparing deployed infrastructure with declared configuration or planning drift reconciliation. Use state-migration for ownership transfers and incident-response for active outages.
- [environment-lifecycle](environment-lifecycle/SKILL.md) — Use when onboarding projects, upgrading templates/providers or retiring environments. Use python-pulumi for program implementation, delivery-and-rollback for deployment execution and state-migration for ownership or secrets-provider migration.
- [evidence-and-coverage](evidence-and-coverage/SKILL.md) — Use when validating result provenance or measuring eligible DevOps automation against a frozen baseline. Use infrastructure-quality to run checks and bmad-autonomous-planning to define requirements.
- [incident-response](incident-response/SKILL.md) — Use when triaging active infrastructure outages, operational alerts or credential incidents. Use observability to design telemetry and delivery-and-rollback for a specific release recovery.
- [infrastructure-quality](infrastructure-quality/SKILL.md) — Use when selecting or running infrastructure lint, type, policy and regression gates. Use security-iam for IAM design decisions and evidence-and-coverage for measuring completed work.
- [observability](observability/SKILL.md) — Use when designing or testing logs, metrics, alarms, SLOs and notification routing. Use incident-response for an active alert and security-iam for logging access permissions.
- [python-pulumi](python-pulumi/SKILL.md) — Use when creating or editing Python Pulumi programs and their engine-specific tests. Use terraform-terraspace for HCL; add state-migration for imports and environment-lifecycle for project onboarding.
- [security-iam](security-iam/SKILL.md) — Use when IAM, OIDC, KMS, secrets, public access or privileged CI permissions change. Use infrastructure-quality for routine scanner execution and incident-response for active credential incidents.
- [state-migration](state-migration/SKILL.md) — Use when moving backend/state ownership, importing resources or transferring Terraform resources to Pulumi. Use environment-lifecycle for ordinary onboarding and backup-recovery for restore drills.
- [terraform-terraspace](terraform-terraspace/SKILL.md) — Use when editing, validating or preparing reviewed plans for Terraform HCL or Terraspace stacks. Use python-pulumi for Python programs; add state-migration for ownership/import changes and delivery-and-rollback for promotion execution.

## Routing

Validate `.claude/devops-sdlc.json` using
`python3 "$DEVOPS_PLUGIN_ROOT/scripts/devops.py" validate-profile --repo .`
from the task repository; resolve `DEVOPS_PLUGIN_ROOT` as described in the agent
guide first. Failure is BLOCKED. Select the `id` of one entry in the profile `targets` list, supplied by the task.
A missing or nonmatching ID is BLOCKED; never infer the environment from the directory.
Choose terraform-terraspace for Terraform/Terraspace, python-pulumi for Python
Pulumi, and BLOCKED for an unsupported engine. Select `infrastructure-quality` when code or checks change, `security-iam` when
permissions/secrets/public access change, `delivery-and-rollback` when promotion
or recovery is requested, and `evidence-and-coverage` for completion reporting.
Record the remaining skills as SKIPPED only when their stated trigger is absent. State ownership/backend changes always receive
independent state review: a separate agent/session that did not author the change
checks the state-migration requirements. Operational maintenance selects skills by the
actual requested action; a feature task does not imply deployment authorization.

## Backend selection

Apply the [agent guide](AI-AGENT-GUIDE.md) to every selected skill for explicit
plugin-root resolution, authenticated Claude/Codex preflight and role delivery.
Before starting a new CLI process,
`python3 "$DEVOPS_PLUGIN_ROOT/scripts/agent_cli.py" detect --backend auto`
selects authenticated Claude, or authenticated Codex if Claude binary/auth fails.
Use `--prefer codex` to reverse that order. If both are unavailable, stop live
work as BLOCKED. Never replay a started or uncertain action through fallback.
The stage is the invoking command name (or directly invoked skill name). Its
budget is five procedure attempts, recorded in `specs/<task>/run-summary.md`;
reuse the existing task path or create the date/task-title slug once for new work.
An attempt starts when the first applicable procedure step begins and ends on its
PASSED, FAILED or BLOCKED outcome. Before starting, read the saved count: if it is
already five, stop with FAILED; otherwise increment once, save and report `n/5`.
Observing an already-started attempt does not increment again. Preserve counts,
applicability and evidence across sessions and backend changes. Ralph is the loop
run by BMALPH; an open/tripped circuit breaker in `.ralph/logs/` ends that run.
Preserve the failed log and partial work; never reset it to retry.

Required checks are the exact acceptance checks recorded in that same task
summary. A native Claude-plugin check means observing Claude actually load and
invoke the installed plugin; source-context execution in Codex cannot satisfy
that specific check. It is required only when the task explicitly requires that
native behavior. A live infrastructure check means observing the specified real
provider/backend operation with its scoped authorization; local mocks cannot
satisfy it. Missing prerequisites leave either required check BLOCKED, while
independent local work continues. Backend fallback cannot turn either into PASS.
