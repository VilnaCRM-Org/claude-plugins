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

Validate `.claude/devops-sdlc.json` using `scripts/devops.py validate-profile`
from the inspected plugin root; failure is BLOCKED. Select the `id` of one entry in the profile `targets` list, supplied by the task.
A missing or nonmatching ID is BLOCKED; never infer the environment from the directory.
Choose terraform-terraspace for Terraform/Terraspace, python-pulumi for Python
Pulumi, and BLOCKED for an unsupported engine. Select `infrastructure-quality` when code or checks change, `security-iam` when
permissions/secrets/public access change, `delivery-and-rollback` when promotion
or recovery is requested, and `evidence-and-coverage` for completion reporting.
Record the remaining skills as SKIPPED only when their stated trigger is absent. State ownership/backend changes always receive
independent state review. Day-2 tasks select their operational skills by the
actual requested action; a feature task does not imply deployment authorization.

## Backend selection

Apply the [agent guide](AI-AGENT-GUIDE.md) to every selected skill for explicit
plugin-root resolution, authenticated Claude/Codex preflight and role delivery.
Before starting a new CLI process, `scripts/agent_cli.py detect --backend auto`
selects authenticated Claude, or authenticated Codex if Claude binary/auth fails.
Use `--prefer codex` to reverse that order. If both are unavailable, stop live
work as BLOCKED. Never replay a started or uncertain action through fallback.
The stage is the invoking command name (or directly invoked skill name). Each
full procedure attempt increments its persisted count before starting and reports
n/5; at 5 stop. Preserve that ledger across sessions and never reset a breaker.
Backend fallback preserves applicability decisions, evidence and stage budgets;
it does not waive an unavailable native-plugin or live-infrastructure check.
