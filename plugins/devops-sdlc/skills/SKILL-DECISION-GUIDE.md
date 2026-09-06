# Skill decision guide

At planning and independent review, record **every skill verdict, no silent skips**:
PASSED, FAILED, SKIPPED (inapplicable with reason), or BLOCKED (missing prerequisites).
Every applicable skill is required; PASS needs inspected evidence.
Only an out-of-scope trigger may be SKIPPED with a reason. Reassess after every
scope or source change.

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

Caller means host orchestrator. Before routing, read [the agent guide](AI-AGENT-GUIDE.md):
follow “Claude and Codex backend contract” for paths/preflight/role delivery and
“Atomic attempt reservation” for ledger mutations. Without it, routing, CLI calls
and ledger writes are BLOCKED. Only document/inventory reads within the user's
task authorization and host policy may continue.
Authenticate the expected root/helper hashes by that contract before execution;
missing/mismatched proof is BLOCKED.
Then run from the task repository
`python3 "$DEVOPS_PLUGIN_ROOT/scripts/devops.py" validate-profile --repo .`
for `.claude/devops-sdlc.json`. A nonzero exit or invalid profile is BLOCKED.
Use the target `id` in the current user request. Only if absent, inspect prior
`initialization-evidence-<identity-sha256>.json` beside the saved summary. Verify
its user/host-policy authority and exact target scope by the agent guide's rules
before reuse. Missing proof, ambiguous or unmatched `targets` ID is BLOCKED;
never infer scope/environment from directories.
Choose terraform-terraspace for Terraform/Terraspace, python-pulumi for Python
Pulumi, and BLOCKED for an unsupported engine. Select `infrastructure-quality` when code or checks change, `security-iam` when
permissions/secrets/public access change, `delivery-and-rollback` when promotion
or recovery is requested, and `evidence-and-coverage` for completion reporting.
Check all 14 descriptions against task facts: select every matching trigger;
absent triggers are SKIPPED, ambiguous ones BLOCKED. Before any state/backend
mutation, require PASS from `agents/state-migration-reviewer.md` in an agent/session
that did not author the changes; missing/unknown review is BLOCKED. Deployment
needs separately recorded exact authorization scope, regardless of label.

## Backend selection

Run `detect` once immediately before every new agent CLI invocation;
`detect` itself needs no preflight:
`python3 "$DEVOPS_PLUGIN_ROOT/scripts/agent_cli.py" detect --backend auto`
for authenticated Claude, falling back to Codex at binary/auth preflight.
`--prefer codex` reverses the order. Require exit zero, `status: READY`, the
selected backend, nonempty version and `available`/`authenticated` both true;
else report BLOCKED. Readiness grants no task permission. Never replay
a started or uncertain action through fallback.
The stage key is the invoked command file's basename without `.md`, e.g.
`do-sdlc-plan`; for a directly invoked skill, use its frontmatter `name`.
Each stage allows five procedure attempts.
Reuse the saved repository-relative `run-summary.md` path. For new work, choose
`specs/YYYY-MM-DD-<slug>/run-summary.md` once using the host clock's UTC date at
first ledger creation. Keep that date/path on resume. For `<slug>`, take the host-supplied current user
message before its first LF, or `task` if empty; do no Markdown parsing or
repository title lookup. It grants no authority. Lowercase,
replace runs outside `a-z` and `0-9` with one hyphen, trim edge hyphens;
if empty, use `task`.
For an existing path, verify saved task identity and initialization evidence match
this task; absent/mismatched/uncertain identity is BLOCKED. Never overwrite/reset.
Persist the exact ledger path and stage key before the first procedure attempt.
Only the caller may initialize adjacent `attempts.json`, before creating
`run-summary.md`. First verify the agent guide's protected-directory,
import-path and two-process shared-filesystem lock prerequisites; any unverified
prerequisite is BLOCKED. Save immutable evidence of identity, host/session, UTC
time and inspected results proving no prior history, caller stop, Ralph breaker
or active/pending/uncertain run. Verify this proof, then initialize count zero
and clear/no-run state under persistent `attempts.lock`; only then create the
summary file. Missing/uncertain proof is BLOCKED. Existing history with a missing
sidecar is BLOCKED until a user-authorized migration under `attempts.lock`
imports verified prior counts, states, evidence and active owner; never initialize
fresh or guess missing history.
Skill references to `specs/<task-id>/run-summary.md` mean this same saved ledger,
never a second task directory.
An attempt is consumed only by a successful atomic reservation; its first
procedure step follows the durable reservation and ends on PASSED, FAILED or
BLOCKED. The caller owns the one record keyed by task, stage, assigned agent,
target and environment. Delegates receive that exact key, owner and reservation token; they never increment
again. Use the
[atomic attempt reservation](AI-AGENT-GUIDE.md#atomic-attempt-reservation)
transaction in the agent guide. A NEW reservation uses `reserve` with no active
marker. Under the lock, apply the first matching rule, even if several hold:
count at five or more → FAILED; recorded user/caller stop directive with source →
BLOCKED; open/tripped Ralph breaker with log → FAILED. Otherwise,
missing/invalid saved count, breaker, `caller_stop` or run state is BLOCKED; a
reported stop needs its directive source, and a run or non-clear breaker needs
its log. Only then may the transaction invoke its caller-verified
`observe(identity, copied_entry)` callback under lock, following the agent guide's
exact identity, state and evidence checks. Absent/unverified or guessed observations
are BLOCKED; fresh clear state cannot repair missing history. Apply the same stop
rules before admission. Escalation is an action, not a persisted status.
The matching owner may start or observe the already-reserved fifth attempt,
subject to current stop/state checks, without reserving again. An active or
uncertain reservation blocks every competing session. Preserve counts,
applicability, evidence and active ownership across sessions and backend changes.

BMAD produces requirements, architecture, stories and a readiness decision.
BMALPH imports them and starts the implementation loop Ralph. Only
`do-sdlc-implement` may start it after readiness passes; planning or skill
selection cannot. In that stage, `bmalph implement` imports ready stories, then
`bmalph run --driver codex` or `bmalph run --driver claude-code` starts Ralph with
the selected authenticated CLI. Its circuit breaker stops repeated failures or
lack of progress. An open/tripped breaker in `.ralph/logs/` ends the run; preserve
the failed log and partial work, never reset it to retry.

Required checks are the acceptance checks recorded in that task summary.
A native Claude-plugin check requires observing Claude load and invoke the
installed plugin; Codex source context cannot satisfy it. Require this check only
when the task explicitly requests native behavior. A live infrastructure check
requires observing the specified real provider/backend operation with scoped
authorization; local mocks cannot satisfy it. Missing prerequisites leave required
checks BLOCKED while independent local work continues. Fallback cannot grant PASS.
