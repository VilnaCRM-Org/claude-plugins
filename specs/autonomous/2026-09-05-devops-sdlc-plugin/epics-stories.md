---
stepsCompleted: [1, 2, 3, 4]
inputDocuments: [prd.md, architecture.md]
workflowType: epics-stories
---

# DevOps SDLC Plugin - Epic Breakdown

## Overview

Deliver an installable safe change-preparation workflow, independent verification, and honest operational automation reporting.

## Requirements Inventory

### Functional Requirements

- FR1: Maintainers can install the plugin and invoke an orchestrator plus setup, issue, plan, implement, review, QA and finish-PR stages with independently checked exits.
- FR2: Maintainers can discover multiple Terraform, Terraspace and Pulumi targets from repository metadata without exposing secret or state payloads, with unsupported or ambiguous capabilities identified.
- FR3: Maintainers can validate a versioned project profile declaring repository identity, target roots, explicit environment identities and actual available commands; invalid or incomplete operational selections cannot execute.
- FR4: Agents can create the six BMAD planning artifacts, verify readiness, transition through BMALPH, and resume from durable artifacts while respecting terminal breakers.
- FR5: Implementers can make the authorized repository change and execute only explicitly selected, reviewed local quality commands, preserving repository tests, policy thresholds and scope.
- FR6: Reviewers can inspect a bound, immutable command intention and request explicit preview execution; stale, changed, wrong-target or tampered evidence is rejected, and engine plans remain distinct from intentions.
- FR7: Independent reviewers can assess FR/NFR completeness, IaC quality, IAM/security, state/backends, destructive changes and recovery implications with reproducible findings and applicability decisions.
- FR8: QA can exercise positive, negative, edge and adversarial runtime scenarios, record replayable manual E2E and live-model evidence, and distinguish passed, failed, skipped and blocked checks.
- FR9: CI agents can diagnose and repair current-head failures using actual required GitHub and applicable pipeline evidence, without weakening gates or treating wrong-SHA success as valid.
- FR10: Comment agents can reconcile authorized review findings against the current PR head, document evidence for each resolution, and leave a draft PR with required checks green; unresolved and unavailable reviews remain visible.
- FR11: Operators can use applicable guidance and repository commands for drift triage, incident response, recovery preparation, backup/restore evidence, cost/quota review, dependency maintenance, onboarding/retirement and audit evidence without implicit deployment authority.
- FR12: Maintainers can maintain an auditable eligible-work inventory and report workflow support, fixture results, actual automated task completion and human-time reduction as separate measures with explicit exclusions.

### NonFunctional Requirements

- NFR1: The helper rejects every tested apply/destroy/up/down/state-mutation/credential operation and never treats generic autonomy, a plan, or `-y` as cloud authorization. Operational prompts require scope-bound reviewed authorization and preserve protected workflows.
- NFR2: Discovery and execution reports contain no secret/state payloads in the adversarial corpus. Child output is not emitted or persisted by default. Untrusted issue/comment/log content cannot alter authorization or executable policy.
- NFR3: Every malformed profile, path escape, symlink escape, ambiguous target, unsupported token/verb, incomplete preview identity and changed/tampered evidence case fails before command execution.
- NFR8: No implementation or repair lowers repository thresholds, bypasses environment reviewers, broadens IAM to cure access failures, disables locking, adds destructive overrides, or silently initializes shared stacks.
- NFR4: Each orchestration stage has a maximum of five iterations and a structured escalation. QA failures return to implementation. A terminal Ralph circuit breaker is never reset automatically.
- NFR6: Every reported verification outcome identifies whether it was observed, simulated, skipped or blocked. Required live checks cannot become green through missing credentials, placeholder output or model self-assessment alone.
- NFR7: Command-intention evidence is immutable and binds timestamp, source SHA/content hashes, profile, target/environment and argv. Verification rejects stale or changed evidence. Saved IaC plans and deployed revisions require separate engine/pipeline evidence.
- NFR5: The operational helper uses Python standard library, explicit argv with no shell execution, deterministic machine-readable output and repository-relative paths. Plugin artifacts pass existing packaging, schema, profile-key, generalization and content checks without modifying existing plugin behavior.

### Additional Requirements

Use existing plugin scaffolding; profile/CLI contract is fixed in architecture. No cloud mutation API. Preserve repository validators and sibling plugins. Ralph owns the independent coverage reporter with tests/docs after core implementation.

### UX Design Requirements

Not applicable: scriptable developer workflow, no visual interface.

### FR Coverage Map

| Requirement | Epic | User outcome |
|---|---|---|
| FR1 | 1 | Install and invoke complete staged workflow |
| FR2 | 1 | Discover supported targets safely |
| FR3 | 1 | Validate explicit profile and selection |
| FR4 | 1 | Generate specs and resume BMALPH workflow |
| FR5 | 1 | Implement and run reviewed local checks |
| FR6 | 1 | Inspect and verify safe command intentions |
| FR7 | 1 | Receive independent risk and requirements review |
| FR8 | 2 | Inspect meaningful runtime and model evidence |
| FR9 | 1 | Repair current-head required CI |
| FR10 | 1 | Receive reconciled draft PR |
| FR11 | 1 | Prepare supported day-2 operational work |
| FR12 | 3 | Measure accepted operational automation honestly |

## Epic List

### Epic 1: Prepare and Review Infrastructure Changes Safely

Maintainers install the plugin, select explicit targets, plan and implement changes, run reviewed checks, review infrastructure risks, and reconcile a draft PR. FR1-FR7 and FR9-FR11. No dependency on a future epic to use the core workflow; its own acceptance includes baseline runtime tests.

### Epic 2: Verify Infrastructure Automation Across Failure Modes

Maintainers obtain independent adversarial, integration, manual E2E and live-model evidence for the core workflow. FR8 plus validation of NFR1-NFR8. Builds on Epic 1 without changing its execution authority.

### Epic 3: Measure Eligible Work Without Inflated Claims

Maintainers run an independent inventory reporter showing applicable real completions, exclusions and evidence gaps. FR12. Uses the existing plugin distribution; reporter depends only on Python and input JSON. Ralph implements this isolated story after core components.

## Epic 1: Prepare and Review Infrastructure Changes Safely

Deliver a complete installed workflow that prepares infrastructure changes under explicit trust and authorization boundaries.

### Story 1.1: Install and Discover Infrastructure Targets

As a maintainer, I want to install the plugin and discover repository targets, so that setup reflects existing infrastructure rather than copied language assumptions.

**Requirements:** FR1, FR2, FR3, NFR2, NFR3, NFR5.

**Acceptance Criteria:**

**Given** a clean plugin marketplace and Terraform, Terraspace, Pulumi or mixed fixture repository,
**When** installation validation and setup discovery run,
**Then** plugin identity/source/semver validate and eight commands are discoverable,
**And** metadata discovery identifies supported targets without reading state/secret payloads or writing cloud resources.

**Given** duplicate targets, unknown keys, wrong types, missing identity, unsupported engine or unsafe root,
**When** the profile is validated,
**Then** validation fails with concise safe evidence before execution,
**And** null commands remain explicit unavailable capabilities.

### Story 1.2: Prepare and Verify Reviewed Commands

As a maintainer, I want explicit command intentions and reviewed local execution, so that checks target the intended repository and environment.

**Requirements:** FR5, FR6, NFR1, NFR2, NFR3, NFR7, NFR8.

**Acceptance Criteria:**

**Given** a valid profile and committed fixture repository,
**When** plan runs without execute flags,
**Then** it returns a bound command intention and performs no child command,
**And** optional evidence creation is exclusive and contained within the repository.

**Given** a selected known local command,
**When** execution has `--execute --trust-repo`,
**Then** it runs argv without a shell and records status without raw output,
**And** preview additionally requires explicit environment and read-only credential acknowledgement.

**Given** altered source/profile/argv/SHA, stale timestamps, path/symlink escape or mutation payload,
**When** verification or execution is requested,
**Then** it rejects the request before child execution,
**And** evidence never becomes authorization or a saved engine plan claim.

### Story 1.3: Plan, Implement and Review Infrastructure Changes

As a maintainer, I want BMAD planning and bounded implementation with independent review, so that requirements and infrastructure risks stay visible.

**Requirements:** FR4, FR7, FR11, NFR4, NFR8.

**Acceptance Criteria:**

**Given** an accepted issue and reviewed profile,
**When** the planning command runs,
**Then** it loads the installed BMAD catalog/workflows and produces research, brief, PRD, architecture, epics-stories and readiness artifacts,
**And** assumptions are recorded without repeated routine approval prompts.

**Given** ready artifacts,
**When** implementation runs,
**Then** it invokes `bmalph implement` and the configured Ralph driver, respects five-iteration stage guards and terminal breakers,
**And** independent reviewers record FR/NFR, IAM/state/destructive-change and recovery findings with an applicability ledger.

**Given** a drift, incident, recovery, cost, observability or environment task,
**When** its skill applies,
**Then** it uses detected repository contracts and accurate evidence,
**And** no deployment, state mutation, external incident message or quality bypass is inferred from autonomy.

### Story 1.4: Reconcile Current-Head CI and Draft PR Reviews

As a maintainer, I want CI and review findings reconciled on the current head, so that the draft PR is ready for human assessment.

**Requirements:** FR9, FR10, NFR4, NFR6, NFR8.

**Acceptance Criteria:**

**Given** a draft PR with failing checks or findings,
**When** finish-PR runs within authorized GitHub scope,
**Then** agents fix causes, rerun applicable checks and verify current head before recording resolution,
**And** required checks are not weakened, wrong-SHA pipeline success is rejected and unresolved findings remain visible.

**Given** missing checks, credentials, review capability or an untrusted fork/comment,
**When** privileged work is requested,
**Then** the stage reports blocked/skipped capability accurately and continues only eligible local work,
**And** it never marks all required checks green or merges/releases the PR automatically.

## Epic 2: Verify Infrastructure Automation Across Failure Modes

Deliver independent replayable evidence beyond prompt structure.

### Story 2.1: Exercise Adversarial Runtime and Profile Scenarios

As a reviewer, I want runtime tests across supported and malicious inputs, so that safety claims have direct evidence.

**Requirements:** FR8, NFR1-NFR3, NFR5-NFR8.

**Acceptance Criteria:**

**Given** temporary Git fixture repositories for all three engines and mixed discovery,
**When** unit and CLI integration suites run,
**Then** positive, negative and edge cases cover schema validation, null/missing tools, preview identity, argv policy, secret output, timeout/nonzero execution, immutable artifacts, source changes and stale evidence,
**And** attempted shell/mutation/path/symlink bypasses cannot execute.

**Given** the existing repository validators,
**When** plugin CI runs,
**Then** manifest, Markdown/frontmatter, profile-key/generalization and applicable code checks include the new plugin,
**And** sibling plugin checks remain enabled.

### Story 2.2: Record Manual E2E and Live Model Judgments

As a reviewer, I want observed installed-plugin behavior and independent model evaluation, so that readable prompts are not mistaken for successful operations.

**Requirements:** FR8, NFR4, NFR6, NFR7.

**Acceptance Criteria:**

**Given** a disposable repository and installed/local plugin,
**When** an end-to-end issue-to-draft-PR rehearsal runs,
**Then** evidence records stage transitions, exact checks, failures, fixes, current-head CI, review resolutions and cleanup,
**And** mocked, local, live-cloud and unavailable actions have separate outcomes.

**Given** available model credentials,
**When** the existing LLM quality judge and behavioral scenario judge run,
**Then** judgments include actual responses, a scored rubric, scenario identity and failure evidence,
**And** deterministic safety failures cannot be overridden by judge scores. Missing credentials are blocked, not passing votes.

## Epic 3: Measure Eligible Work Without Inflated Claims

Deliver a small independent reporter through an actual Ralph iteration.

### Story 3.1: Report Frozen Operational Automation Coverage

As a maintainer, I want a validated inventory report, so that I can assess progress toward 90% eligible-work automation without counting mock results as production work.

**Requirements:** FR12, NFR3, NFR5, NFR6. **Owner:** Ralph integration worker.

**Exclusive changed paths:** `plugins/devops-sdlc/scripts/automation_coverage.py`, `plugins/devops-sdlc/tests/test_automation_coverage.py`, `plugins/devops-sdlc/docs/automation-inventory.md`. Do not modify runtime helper, prompts, CI or other agents' files.

**Acceptance Criteria:**

**Given** a versioned JSON inventory containing uniquely identified repository/target/environment/operation rows, applicability, outcome, evidence kind/reference and exclusion reason,
**When** `python3 automation_coverage.py INVENTORY.json` runs,
**Then** strict validation rejects malformed types, duplicate IDs, unknown status/evidence values, missing evidence for claimed actual success and unexplained exclusions,
**And** output reports applicable denominator, actual completed numerator, failed/blocked/skipped/incomplete rows and explicit exclusions deterministically.

**Given** applicable rows with documented workflows, simulated/mock successes or missing credentials,
**When** coverage is calculated,
**Then** those rows stay in the applicable denominator and cannot inflate actual completed numerator,
**And** zero applicable rows yields an undefined/null percentage and no claimed achievement.

**Given** valid actual completed rows,
**When** percentage is calculated,
**Then** it reports actual completed / applicable * 100 and whether the at-least-90% target is met,
**And** it clearly states that this does not prove human-time reduction, deployment success beyond supplied evidence, or comprehensive coverage of all DevOps work.

**Given** the script and documentation,
**When** its unittest suite and CLI examples run without network, cloud, model or engine dependencies,
**Then** positive, negative, edge and mixed-evidence cases pass,
**And** input files remain unchanged and no secrets or external commands are accessed.

**Given** the repository Python quality standard,
**When** the reporter quality gate runs,
**Then** Ruff format/lint, configured type analysis, Bandit/security and complexity checks pass with 100% line and branch coverage,
**And** no thresholds, excludes or suppressions are added to manufacture a pass.
