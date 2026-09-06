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
Use the exact invoked command identifier as the stage key, for example
`do-sdlc-implement`. For a skill invoked directly, use its frontmatter `name`,
for example `terraform-terraspace`. A stage has five procedure attempts.
The task ledger is the existing task's `run-summary.md`; reuse its exact saved
repository-relative path. For new work without a ledger, select its path once at
`specs/YYYY-MM-DD-<slug>/run-summary.md`: use the UTC calendar date from the host
clock when the caller first creates this task ledger, and record that date in it.
Keep the recorded date and path across resumed sessions. For `<slug>`, lowercase
the task title, replace each run of characters outside `a-z` and `0-9` with one
hyphen, and trim leading/trailing hyphens. Use `task` if the slug is empty.
For example, "Add Cache" with its ledger first created on 2026-09-06 UTC uses
`specs/2026-09-06-add-cache/run-summary.md`. If that path already belongs to a
different task, report BLOCKED; never overwrite it or reset its counter.
Persist the exact ledger path and stage key before the first procedure attempt.
Initialize the verified new sidecar under lock before creating the first human
summary; follow the atomic transaction in the agent guide.
References to `specs/<task-id>/run-summary.md` in selected skills mean this same
saved ledger; they do not create a second task directory.
An attempt is consumed only by a successful atomic reservation; its first
procedure step follows the durable reservation and ends on PASSED, FAILED or
BLOCKED. The caller owns the one record keyed by task, stage, assigned agent,
target and environment. A delegated agent receives that exact key, owner and
reservation token; it never increments a second time. Use the
[atomic attempt reservation](AI-AGENT-GUIDE.md#atomic-attempt-reservation)
transaction in the agent guide. For a NEW reservation, a saved count at five or more means
FAILED before incomplete-history checks; a known caller stop means BLOCKED;
an evidenced open/tripped Ralph breaker means FAILED; missing required state or
run evidence means BLOCKED. Escalation is an action, never a persisted status.
The matching owner may start or observe the already-reserved fifth attempt,
subject to current stop/state checks, without reserving again. An active or
uncertain reservation blocks every competing session. Preserve counts,
applicability, evidence and active ownership across sessions and backend changes.

BMAD is the installed planning workflow that produces requirements, architecture,
stories and a readiness decision. BMALPH is the command-line integration that
imports those planning artifacts and starts the implementation loop named Ralph.
Only the `do-sdlc-implement` stage starts that loop after its readiness gate passes;
skill selection or planning does not start implementation. In that stage,
`bmalph implement` imports the ready stories, then `bmalph run --driver codex`
or `bmalph run --driver claude-code` starts Ralph using the selected authenticated
CLI. Ralph's circuit breaker is its automatic stop after repeated failures or
lack of progress. An open/tripped breaker recorded in `.ralph/logs/` ends that
run. Preserve the failed log and partial work; never reset it to retry.

Required checks are the exact acceptance checks recorded in that same task
summary. A native Claude-plugin check means observing Claude actually load and
invoke the installed plugin; source-context execution in Codex cannot satisfy
that specific check. It is required only when the task explicitly requires that
native behavior. A live infrastructure check means observing the specified real
provider/backend operation with its scoped authorization; local mocks cannot
satisfy it. Missing prerequisites leave either required check BLOCKED, while
independent local work continues. Backend fallback cannot turn either into PASS.
