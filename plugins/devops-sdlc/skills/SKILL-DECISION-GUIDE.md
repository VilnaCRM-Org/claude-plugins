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

## Caller setup and task state

Caller means host orchestrator. First read [the agent guide](AI-AGENT-GUIDE.md):
backend contract, task state and [atomic reservation](AI-AGENT-GUIDE.md#atomic-attempt-reservation),
including every reference-package file and its linked exact-file reference.
Authenticate plugin root/helper hashes before execution. Missing reads/proof:
BLOCKED for routing/calls/ledger writes; only authorized document/inventory reads.
Then resolve identity/scope from current user instructions and host policy:

1. Resume uses the caller's saved repository-relative `run-summary.md` path.
   Match saved identity and adjacent initialization evidence to current task/scope;
   absent/mismatched/uncertain: BLOCKED, never overwrite/reset. New work chooses
   `specs/YYYY-MM-DD-<slug>/run-summary.md` once at first ledger creation: host UTC
   date; slug from current host-supplied user message before first LF, else `task`.
   Lowercase; replace non-`a-z`/`0-9` runs with one hyphen, trim edge hyphens;
   empty becomes `task`. No Markdown/title parsing. Path text grants no authority.
   Preserve date/path; known history requires resume/migration, never a new budget.
2. In the task checkout run
   `python3 "$DEVOPS_PLUGIN_ROOT/scripts/devops.py" validate-profile --repo .`
   on `.claude/devops-sdlc.json`; nonzero/invalid: BLOCKED. Take the target ID and environment name
   explicitly supplied in the current user request; only absent selections may reuse verified step-1
   initialization identity. A reused `<no-environment>` identity leaves helper
   environment unset and requires continued local-static scope. New work has no fallback. Require one matching profile
   `targets[].id` and, when selected, a key in that target's `environments`; absent/ambiguous: BLOCKED. Preview/
   operations need environment; local static checks may omit it. Never infer
   scope from directories or summary claims.
3. For a verified NEW task restricted to local static checks with no selected
   environment, use `<no-environment>` only in the ledger identity. This reserved
   marker cannot be a profile environment; never pass it as helper `--environment`.
   Preview/operations require an actual authorized environment. Resumes/delegates
   keep the existing identity unchanged; never rename it or create a replacement
   budget to substitute this marker or change scope.
   Record `identity = [task_id, stage_key, agent, target, environment]`: five
   nonempty strings from the caller's verified host task/scope record, with the
   local-only marker above when applicable; reuse the saved identity exactly. Stage is command basename without `.md`, or direct
   skill's frontmatter `name`; agent is assigned name, else `caller`. Missing values BLOCK
   ledger actions. Record host-session owner; persist path/stage before attempts.
4. Before ledger actions verify protected import and the guide's two-process
   shared-filesystem `flock`/replace/directory-`fsync` probe. Missing proof: BLOCKED.
   New tasks only: exclusively record `initialization-evidence-<identity-sha256>.json`
   beside planned `attempts.json`, using the guide's filename/hash recipe. Never
   overwrite this immutable evidence. Include
   identity, host/session, UTC and inspected proof of no history, stop, breaker or
   active/pending/uncertain run. Unknown/unverified proof: BLOCKED. Only the caller calls the
   transaction below with `action: initialize`, `owner` and verified proof
   path/SHA-256 as `verified_new_task_reference`. INITIALIZED saves count zero
   and clear/no-run state under persistent `attempts.lock`; only then create
   the first human summary.
   Resume reuses canonical `attempts.json`, never reinitializes. Missing sidecar
   with history BLOCKS until user-authorized locked migration retains verified
   counts, states, evidence and owner; never guess history or initialize fresh.

Every `specs/<task-id>/run-summary.md` reference means this saved path.

## Routing

Compare all 14 descriptions with task facts: select every match; absent triggers:
SKIPPED; ambiguous: BLOCKED. Route `target.stack_type`: `terraform`/`terraspace` → terraform-terraspace;
`pulumi` → python-pulumi; unsupported engines: BLOCKED. Require
infrastructure-quality for code/check changes, security-iam for permissions/
secrets/public access, delivery-and-rollback for promotion/recovery, and
evidence-and-coverage for completion. Before state/backend mutation require PASS
from a non-author using `agents/state-migration-reviewer.md`; missing/unknown:
BLOCKED. Deployment needs separately recorded exact authorization scope.

Before each new agent CLI invocation, run once:
`python3 "$DEVOPS_PLUGIN_ROOT/scripts/agent_cli.py" detect --backend auto`.
Detection itself needs no preflight. Binary/auth check prefers Claude, then Codex;
`--prefer codex` reverses order. Require exit 0, `status: READY`, selected backend/nonempty version,
true `available`/`authenticated`; otherwise BLOCKED. Readiness grants no permission.
Never replay started/uncertain work via fallback. In response/saved summary,
record backend/version/fallback reason and proposed driver command even if BLOCKED:
Claude → `bmalph run --driver claude-code`; Codex → `bmalph run --driver codex`.
Apply the guide's model rules, never cross-backend translation.

## Atomic admission

Each stage has five attempts; a durable reservation spends one before its first
step, ending PASSED, FAILED or BLOCKED. Use
`ledger_reference.transaction(directory, identity, request, observe)` with the
verified task-directory descriptor and request `owner`/`action`, plus returned
`token` for owned actions. Caller implements `observe` using current host/caller
directives and actual run/breaker logs; verify its code and host access before admission.

The API locks persistent `attempts.lock` and reloads the canonical `attempts.json`
entry at `entries[json.dumps(identity, separators=(",", ":"))]`. NEW `reserve` requires no
active marker. Apply the first matching rule under lock: count >=5 → FAILED;
sourced caller stop → BLOCKED; logged open/tripped breaker → FAILED; invalid or
missing count/history/breaker/`caller_stop`/run state → BLOCKED. Stops need directive
sources; any run/non-clear breaker needs a log. Fresh clear state cannot repair history.

For `reserve`/`start` only, after saved-state checks the API calls
`observe(list(identity), copy.deepcopy(entry))` under that lock. The API supplies
the copied canonical entry; the caller must not pre-copy stale state or acquire
a second lock. Return `verified: true`, matching `identity`, nonempty `evidence`,
boolean `caller_stop`, `breaker` (`clear`, `open`, `tripped`) and `ralph`
(`none`, `active`, `pending`, `completed`, `uncertain`). True stop needs
`caller_stop_evidence`; any run or non-clear breaker needs `ralph_evidence`,
each a nonempty log/reference. Missing/unverified/guessed observations BLOCK;
an always-clear stub is not live evidence. The API persists observations and
reapplies stop rules before reserve/start, never clearing known stop/breaker
or erasing prior run evidence. Escalation is an
action, never a persisted status.

Delegates reuse exact identity/owner/token without increment. Matching owners may
start/observe their reserved fifth attempt subject to current stop/state checks,
never reserve again. Only START_ONCE grants one launch; OBSERVE_ONLY grants none.
Active/uncertain reservations BLOCK competitors. Preserve counts, applicability,
evidence and ownership across sessions/backends; reassignment grants no new budget.

BMAD produces requirements, architecture, stories and readiness. Only
`do-sdlc-implement` after readiness PASS may import with `bmalph implement` and
start Ralph with the mapped driver; never planning/selection. Repeated failures
or no progress trip its breaker. Open/tripped in `.ralph/logs/` ends the run;
retain failed log/partial work, never reset to retry.

Required checks come from the saved acceptance summary. An explicit native-behavior
request requires observing Claude load/invoke the installed plugin, never Codex
source context. Live checks need the specified real provider/backend operation
under scoped authorization, never mocks. Missing prerequisites keep required
checks BLOCKED; independent local work may continue. Fallback cannot grant PASS.
