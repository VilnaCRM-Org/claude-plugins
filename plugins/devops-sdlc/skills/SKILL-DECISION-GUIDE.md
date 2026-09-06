# Skill decision guide

Planning/independent review: **every skill verdict, no silent skips**:
PASSED: inspected evidence; FAILED; SKIPPED only for out-of-scope triggers
with reason; BLOCKED: missing prerequisites. Applicable skills are required.
Reassess on scope/source changes.

## Complete inventory

- [backup-recovery](backup-recovery/SKILL.md) — Use when assessing backups, restore drills, RPO/RTO or disaster recovery. Use state-migration for state ownership transfers and delivery-and-rollback for reverting a release.
- [bmad-autonomous-planning](bmad-autonomous-planning/SKILL.md) — Use when turning infrastructure work into BMAD requirements, architecture, stories and a readiness handoff. Use infrastructure-quality for checking existing code; implementation execution is a separate command stage, outside this skill.
- [cost-optimization](cost-optimization/SKILL.md) — Use when assessing infrastructure spend, budgets, quotas or rightsizing proposals. Use observability for non-cost telemetry and environment-lifecycle for approved retirement execution.
- [delivery-and-rollback](delivery-and-rollback/SKILL.md) — Use when preparing saved-plan promotion, deployment health gates or release rollback. Use incident-response for broader incident triage and state-migration for backend ownership changes.
- [drift-management](drift-management/SKILL.md) — Use when comparing deployed infrastructure with declared configuration or planning drift reconciliation. Use state-migration for ownership transfers and incident-response for active outages.
- [environment-lifecycle](environment-lifecycle/SKILL.md) — Use when onboarding projects, upgrading templates/providers or retiring environments. Use python-pulumi for program implementation, delivery-and-rollback for deployment execution and state-migration for ownership or secrets-provider migration.
- [evidence-and-coverage](evidence-and-coverage/SKILL.md) — Use when validating result provenance or measuring eligible DevOps automation against a frozen baseline. Use infrastructure-quality to run checks and bmad-autonomous-planning to define requirements.
- [incident-response](incident-response/SKILL.md) — Use when triaging active infrastructure outages, alerts or credential incidents. Otherwise, skip: route telemetry design to observability and release recovery to delivery-and-rollback.
- [infrastructure-quality](infrastructure-quality/SKILL.md) — Use when selecting or running infrastructure lint, type, policy and regression gates. Use security-iam for IAM design decisions and evidence-and-coverage for measuring completed work.
- [observability](observability/SKILL.md) — Use when designing or testing logs, metrics, alarms, SLOs and notification routing. Use incident-response for an active alert and security-iam for logging access permissions.
- [python-pulumi](python-pulumi/SKILL.md) — Use when creating, editing or previewing Python Pulumi programs and their engine-specific tests. Use terraform-terraspace for HCL; add state-migration for imports and environment-lifecycle for project onboarding.
- [security-iam](security-iam/SKILL.md) — Use when IAM, OIDC, KMS, secrets, public access or privileged CI permissions change. Use infrastructure-quality for routine scanner execution and incident-response for active credential incidents.
- [state-migration](state-migration/SKILL.md) — Use when moving backend/state ownership, importing resources or transferring Terraform resources to Pulumi. Use environment-lifecycle for ordinary onboarding and backup-recovery for restore drills.
- [terraform-terraspace](terraform-terraspace/SKILL.md) — Use when editing, validating or preparing reviewed plans for Terraform HCL or Terraspace stacks. Use python-pulumi for Python programs; add state-migration for ownership/import changes and delivery-and-rollback for promotion execution.

## Routing

The caller is the host orchestrator. Before routing, read [the agent guide](AI-AGENT-GUIDE.md):
“Claude and Codex backend contract” governs paths/preflight/role delivery;
“Atomic attempt reservation” governs ledger writes. Without this read, those
operations are BLOCKED; only authorized document/inventory reads may continue.
Authenticate root/helper hashes by that contract; missing/mismatched proof is
BLOCKED before execution. From the task repository, run
`python3 "$DEVOPS_PLUGIN_ROOT/scripts/devops.py" validate-profile --repo .`
for `.claude/devops-sdlc.json`. A nonzero exit or invalid profile is BLOCKED.
Use the current request's target `id`. If absent, reuse
`initialization-evidence-<identity-sha256>.json` beside the saved summary only after verifying user/host
policy authority and exact target scope under the agent guide. Missing proof or
ambiguous/unmatched `targets` ID is BLOCKED. Directories never define scope/environment.
Choose terraform-terraspace for Terraform/Terraspace, python-pulumi for Python
Pulumi, and BLOCKED for an unsupported engine. Select `infrastructure-quality` when code or checks change, `security-iam` when
permissions/secrets/public access change, `delivery-and-rollback` when promotion
or recovery is requested, and `evidence-and-coverage` for completion reporting.
Compare all 14 descriptions with task facts: select every match; absent triggers
are SKIPPED, ambiguous ones BLOCKED. Before state/backend mutation, require PASS
from a non-author agent/session using `agents/state-migration-reviewer.md`;
missing/unknown review is BLOCKED. Deployment requires separately recorded exact
authorization scope, regardless of label.

## Backend selection

Immediately before each new agent CLI invocation, run once:
`python3 "$DEVOPS_PLUGIN_ROOT/scripts/agent_cli.py" detect --backend auto`.
This binary/auth preflight prefers Claude, then Codex; `--prefer codex` reverses
it. Detection needs no preflight. Require exit zero, `status: READY`, selected
backend, nonempty version, and true `available`/`authenticated`; otherwise BLOCKED.
Readiness grants no task permission. Never replay started/uncertain work through fallback.
Record backend/version/fallback reason and proposed implementation handoff in
response/saved summary: Claude → `bmalph run --driver claude-code`;
Codex → `bmalph run --driver codex`. Include it while implementation is BLOCKED. Apply the agent
guide's model rules; no cross-backend translation.
Stage key is the invoked command basename without `.md`, e.g. `do-sdlc-plan`,
or the direct skill's frontmatter `name`. Each stage allows five procedure attempts.
Reuse the saved repository-relative summary path. For new work, choose
`specs/YYYY-MM-DD-<slug>/run-summary.md` once with the host UTC date at first ledger
creation; retain date/path on resume. Slug input is the host-supplied current user
message before its first LF, or `task` if empty. Lowercase it, replace runs outside
`a-z`/`0-9` with one hyphen, trim edge hyphens; empty becomes `task`. Never parse
Markdown or look up repository titles; this input grants no authority.
Existing paths require matching saved task identity and initialization evidence;
absent/mismatched/uncertain identity is BLOCKED, never overwritten/reset.
Persist exact ledger path and stage key before the first attempt.
Only the caller initializes adjacent `attempts.json`, before the first summary.
Verify the guide's protected-directory, import-path and two-process shared-lock
prerequisites. Retain immutable identity, host/session, UTC time and inspected
proof of no prior history, caller stop, Ralph breaker or active/pending/uncertain
run. Missing/unverified/uncertain prerequisites or proof are BLOCKED. Only then
initialize count zero and clear/no-run state under persistent `attempts.lock`,
then create the summary. Existing history without this sidecar is BLOCKED until
user-authorized migration under that lock imports verified counts, states,
evidence and active owner; never initialize fresh or guess history.
All `specs/<task-id>/run-summary.md` references mean this saved path, never a
second task directory.
A successful durable reservation consumes one attempt before its first procedure
step; it ends PASSED, FAILED or BLOCKED. The caller owns the entry keyed by task,
stage, assigned agent, target and environment. Delegates reuse its exact key,
owner and token without incrementing. Use the guide's
[atomic transaction](AI-AGENT-GUIDE.md#atomic-attempt-reservation).
A NEW `reserve` has no active marker. Under lock, apply the first matching rule:
count >=5 → FAILED; sourced user/caller stop → BLOCKED; logged open/tripped Ralph
breaker → FAILED; missing/invalid saved count, breaker, `caller_stop` or run state
→ BLOCKED. A reported stop requires its directive source; a run or non-clear
breaker requires its log. Only then invoke the caller-verified
`observe(identity, copied_entry)` under lock with the guide's exact identity,
state and evidence checks. Absent/unverified/guessed observations are BLOCKED;
fresh clear state cannot repair missing history. Reapply stop rules before
admission. Escalation is an action, not a persisted status.
The matching owner may start or observe the already-reserved fifth attempt,
subject to current stop/state checks, without reserving again. An active or
uncertain reservation blocks every competing session. Preserve counts,
applicability, evidence and active ownership across sessions and backend changes.

BMAD yields requirements, architecture, stories and readiness. Only
`do-sdlc-implement` after readiness passes may import stories with `bmalph implement`
and start Ralph with the mapped driver, never planning or skill selection.
Repeated failures/lack of progress trip its breaker: open/tripped in `.ralph/logs/`
ends the run. Keep failed log and partial work; never reset to retry.

Required checks are the acceptance checks recorded in that task summary.
Only an explicit native-behavior request requires observing Claude load and invoke
the installed plugin; Codex source context cannot satisfy it. A live infrastructure
check requires the specified real provider/backend operation under scoped
authorization, never local mocks. Missing prerequisites keep required checks BLOCKED
while independent local work continues. Fallback cannot grant PASS.
