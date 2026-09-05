# Skill decision guide

The gate contract is: **every skill verdict recorded, no silent skips**.
At planning and independent review, record each skill as PASSED, FAILED,
SKIPPED (inapplicable with reason), or BLOCKED (missing prerequisites).
An applicable required skill cannot pass without evidence. Reassess after changes.

## Complete inventory

- [terraform-terraspace](terraform-terraspace/SKILL.md) — Use when changing or operating existing Terraform or Terraspace infrastructure, including multi-stack projects.
- [python-pulumi](python-pulumi/SKILL.md) — Use when building new Python/Pulumi projects or maintaining existing Pulumi infrastructure.
- [bmad-autonomous-planning](bmad-autonomous-planning/SKILL.md) — Use when preparing infrastructure requirements, architecture and stories before a BMALPH implementation run.
- [infrastructure-quality](infrastructure-quality/SKILL.md) — Use when validating infrastructure code or choosing the repository's quality and test gates.
- [security-iam](security-iam/SKILL.md) — Use when reviewing IAM, OIDC, KMS, credentials, public access or privileged CI changes.
- [state-migration](state-migration/SKILL.md) — Use when changing infrastructure backends, importing resources or migrating Terraform/Terraspace ownership to Pulumi.
- [delivery-and-rollback](delivery-and-rollback/SKILL.md) — Use when preparing saved-plan deployments, promotions, failed-release diagnosis or rollback.
- [drift-management](drift-management/SKILL.md) — Use when detecting configuration drift or preparing reconciliation across Terraform, Terraspace or Pulumi stacks.
- [incident-response](incident-response/SKILL.md) — Use when triaging infrastructure incidents, failed deployments or operational alerts.
- [backup-recovery](backup-recovery/SKILL.md) — Use when checking backup posture, restore drills, RPO/RTO evidence or disaster recovery plans.
- [cost-optimization](cost-optimization/SKILL.md) — Use when reviewing infrastructure cost changes, budgets, quotas or optimization proposals.
- [observability](observability/SKILL.md) — Use when implementing or verifying infrastructure logs, metrics, alarms, SLOs and incident routes.
- [environment-lifecycle](environment-lifecycle/SKILL.md) — Use when onboarding a Python/Pulumi project, maintaining IaC templates or retiring an ephemeral environment.
- [evidence-and-coverage](evidence-and-coverage/SKILL.md) — Use when measuring DevOps automation, reporting completion or validating test and operational evidence.

## Routing

Choose engine skills from the validated target, then add quality, security,
delivery and evidence skills. State ownership/backend changes always receive
independent state review. Day-2 tasks select their operational skills by the
actual requested action; a feature task does not imply deployment authorization.
