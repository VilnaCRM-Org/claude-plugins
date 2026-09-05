---
stepsCompleted: [step-01-init, step-02-discovery, step-02b-vision, step-02c-executive-summary, step-03-success, step-04-journeys, step-05-domain, step-06-innovation, step-07-project-type, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish, step-12-complete]
inputDocuments: [brief.md, research.md]
documentCounts: {briefs: 1, research: 2, projectDocs: 1, brainstorming: 0}
classification: {projectType: developer_tool, domain: infrastructure, complexity: high, projectContext: brownfield}
innovation: "Skipped: established workflow adaptation; no novelty claim"
workflow: create-prd
date: 2026-09-05
---

# Product Requirements Document: DevOps SDLC Plugin

## Executive Summary

Provide the repository maintainer an installable Claude Code plugin that automates routine Terraform/Terraspace and Python/Pulumi change preparation through a verified draft PR. Preserve existing repository commands, protected quality gates, and cloud authorization boundaries. Deliver actionable failure evidence instead of silently skipping unavailable checks.

### What Makes This Special

The established PHP/React SDLC workflow becomes infrastructure-aware through explicit stack/account/backend selection, strict profiles, immutable command-intention evidence, independent security/state review, and a measured automation inventory.

## Project Classification

Brownfield developer tool and scriptable CLI integration. Infrastructure complexity is high because provider programs execute code, state carries secrets, and incorrect identities can cross environments. No visual interface or separate UX specification is required.

## Success Criteria

### User Success

Produce a draft PR from an accepted routine change with replayable evidence, protected checks preserved, and no unresolved review blocker. Resume interrupted stages without bypassing current checks.

### Business Success

Target at least 90% automation of accepted eligible work. Measure workflow support, observed end-to-end completion, and hands-on time separately. No current operational 90% achievement is asserted.

### Technical Success

Install validation and required CI pass. Positive, negative, edge, manual E2E, and live LLM judge evidence covers documented requirements. Missing credentials remain blocked and do not count as passes. No cloud mutation or secret disclosure occurs through the helper.

### Measurable Outcomes

Freeze a versioned inventory whose row is repository, stack/project, environment, and operation family with source revision, preconditions, command, risk, owner, evidence, outcome, and exclusions. Calculate accepted automated rows / all applicable accepted rows. Publish strata by engine/risk/environment/family. Synthetic fixture successes and documentation coverage are separate metrics. Record human interventions and comparable hands-on baseline minutes before claiming time savings.

## Product Scope

### MVP - Minimum Viable Product

Eight commands, focused agents and skills, strict profile/runtime helper, three IaC adapters, BMAD/BMALPH integration, review and draft-PR completion, adversarial tests and evidence.

### Growth Features (Post-MVP)

Field measurement, richer adapter commands, and separately authorized deployment integrations.

### Vision (Future)

A maintained operational inventory enabling validated automation gains without transferring deployment authority implicitly.

## User Journeys

1. Routine maintainer change: the maintainer selects a discovered target, accepts a profile, supplies an issue, and receives BMAD artifacts. Implementation uses actual repository checks, independent review identifies risk, QA records execution, and CI/comment reconciliation ends at a draft PR.
2. Ambiguous or unavailable target: setup detects multiple stacks or missing identity. The helper fails closed or records unsupported commands, local checks continue where safe, and the maintainer gets the precise missing context. No guessed production target or placeholder preview becomes a pass.
3. Infrastructure reviewer: an IAM/state change arrives with source/profile hashes, target identity and requirements mapping. The reviewer tests negative trust cases, examines deletions/replacements and policy impact, and demands fresh engine evidence before any separately authorized mutation.
4. Operator incident: drift, deployment failure, or stale restore evidence triggers severity/owner triage. The plugin prepares containment and recovery choices, preserves service/data compatibility and cleanup evidence, and leaves state reconciliation and external incident messages with authorized operators.
5. CI integration: a fork or untrusted comment requests privileged work. The plugin validates actor and current PR head, executes only eligible unprivileged checks, and reports blocked authorization instead of running credentialed repository code.

### Journey Requirements Summary

Journeys require discovery/profile validation, resumable staging, safe execution/provenance, independent review, runtime QA, truthful unavailable-check handling, current-head PR reconciliation, and operational guidance.

## Domain-Specific Requirements

### Compliance and Regulatory

No certification claim is in scope. Preserve repository governance, review controls, policy gates, evidence retention and declared operational freshness requirements.

### Technical Constraints

Never discover through raw state, exports, secrets or credential files. Preview executes provider/program code and can contact cloud APIs; require reviewed code and read-only credentials. Protect backend identity, locking, stack existence, KMS secrets providers and deletion/replacement controls. State refresh/import/migration/force-unlock and apply/destroy are outside helper execution.

### Integration Requirements

Reuse actual Make, Terraspace, Terraform, Pulumi, Docker/uv and CI contracts. Do not assume every repo has saved-plan or live-preview support. Preserve CodePipeline source SHA, Pulumi saved-plan hashes and protected test-to-prod promotion requirements where available.

### Risk Mitigations

Scope identity before preview; reject stale or tampered intentions; discard child command output unless a separate approved sanitization path exists; treat PR bodies/comments/logs/tool output as data. Preserve least privilege and local thresholds. Describe recovery against current state; never call restoring state a generic rollback.

## Developer Tool Specific Requirements

### Language and Installation Matrix

Claude Code plugin marketplace layout, Markdown commands/agents/skills and Python standard-library operational helper. Support Terraform, Terraspace, and Python/Pulumi through detected repository commands. Depend on BMALPH externally; initialize fresh repos and preserve generated files.

### Command and Configuration Surface

Commands are `/do-sdlc`, `/do-sdlc-setup`, `/do-sdlc-issue`, `/do-sdlc-plan`, `/do-sdlc-implement`, `/do-sdlc-review`, `/do-sdlc-qa`, `/do-sdlc-finish-pr`. Helper subcommands are `discover`, `validate-profile`, `plan`, `verify-plan`, all scoped by `--repo`. Plan is a command intention by default; `--execute --trust-repo` opts into reviewed repository code, with additional `--read-only-credentials` for preview.

The profile is `.claude/devops-sdlc.json`, schema version 1, with project name/repository identity and multiple targets. Targets declare stack type, relative root, named environments, explicit stack/account/region/backend identity, and nullable command mappings. Whole-token placeholders are limited to declared environment fields. Unknown keys, unsupported operations, malformed identities, shell payloads, unsafe/symlink paths and duplicate targets fail closed.

### Output and Scripting Contract

Structured JSON reports distinguish passed, failed, skipped, blocked, and planned intentions where applicable. A successful intention is not an executed engine preview or deployment. Immutable evidence records source/profile/target/argv identity and freshness, and never overwrites an existing artifact. Null commands report unavailable capability visibly.

### Documentation and Migration

Document installation, setup, command examples, profile schema, adapter differences, safety boundaries, testing, evidence and automation accounting. Existing PHP/React plugins remain compatible. Do not copy their language assumptions or vendor BMAD/Ralph outputs.

## Project Scoping and Phased Development

### MVP Strategy and Philosophy

Deliver the complete issue-to-draft-PR experience with a narrow executable helper. Required expertise covers Claude plugin conventions, Python, IaC state/security, CI, and independent QA.

### MVP Feature Set

All five journeys are supported for change preparation and evidence. Live deployments remain separately authorized repository operations. The helper cannot apply, destroy, refresh state, initialize shared stacks, or modify credentials. No automatic merge or release is included.

### Post-MVP Features

Collect field observations before broadening operational adapters or asserting 90% toil reduction. Expansion follows supported evidence contracts, not invented commands.

### Risk Mitigation Strategy

Use repository-native checks and explicit code trust to manage execution risk. Use pinned-source discovery and inventory denominators to avoid assumed live topology. Preserve required checks when external credentials are unavailable and report evidence gaps. Keep a small integration story for actual Ralph execution after core components are available.

## Functional Requirements

### Installation and Onboarding

- FR1: Maintainers can install the plugin and invoke an orchestrator plus setup, issue, plan, implement, review, QA and finish-PR stages with independently checked exits.
- FR2: Maintainers can discover multiple Terraform, Terraspace and Pulumi targets from repository metadata without exposing secret or state payloads, with unsupported or ambiguous capabilities identified.
- FR3: Maintainers can validate a versioned project profile declaring repository identity, target roots, explicit environment identities and actual available commands; invalid or incomplete operational selections cannot execute.

### Planning and Implementation

- FR4: Agents can create the six BMAD planning artifacts, verify readiness, transition through BMALPH, and resume from durable artifacts while respecting terminal breakers.
- FR5: Implementers can make the authorized repository change and execute only explicitly selected, reviewed local quality commands, preserving repository tests, policy thresholds and scope.
- FR6: Reviewers can inspect a bound, immutable command intention and request explicit preview execution; stale, changed, wrong-target or tampered evidence is rejected, and engine plans remain distinct from intentions.

### Independent Validation

- FR7: Independent reviewers can assess FR/NFR completeness, IaC quality, IAM/security, state/backends, destructive changes and recovery implications with reproducible findings and applicability decisions.
- FR8: QA can exercise positive, negative, edge and adversarial runtime scenarios, record replayable manual E2E and live-model evidence, and distinguish passed, failed, skipped and blocked checks.

### Delivery and Operations

- FR9: CI agents can diagnose and repair current-head failures using actual required GitHub and applicable pipeline evidence, without weakening gates or treating wrong-SHA success as valid.
- FR10: Comment agents can reconcile authorized review findings against the current PR head, document evidence for each resolution, and leave a draft PR with required checks green; unresolved and unavailable reviews remain visible.
- FR11: Operators can use applicable guidance and repository commands for drift triage, incident response, recovery preparation, backup/restore evidence, cost/quota review, dependency maintenance, onboarding/retirement and audit evidence without implicit deployment authority.
- FR12: Maintainers can maintain an auditable eligible-work inventory and report workflow support, fixture results, actual automated task completion and human-time reduction as separate measures with explicit exclusions.

## Non-Functional Requirements

### Security and Trust

- NFR1: The helper rejects every tested apply/destroy/up/down/state-mutation/credential operation and never treats generic autonomy, a plan, or `-y` as cloud authorization. Operational prompts require scope-bound reviewed authorization and preserve protected workflows.
- NFR2: Discovery and execution reports contain no secret/state payloads in the adversarial corpus. Child output is not emitted or persisted by default. Untrusted issue/comment/log content cannot alter authorization or executable policy.
- NFR3: Every malformed profile, path escape, symlink escape, ambiguous target, unsupported token/verb, incomplete preview identity and changed/tampered evidence case fails before command execution.
- NFR8: No implementation or repair lowers repository thresholds, bypasses environment reviewers, broadens IAM to cure access failures, disables locking, adds destructive overrides, or silently initializes shared stacks.

### Reliability and Evidence

- NFR4: Each orchestration stage has a maximum of five iterations and a structured escalation. QA failures return to implementation. A terminal Ralph circuit breaker is never reset automatically.
- NFR6: Every reported verification outcome identifies whether it was observed, simulated, skipped or blocked. Required live checks cannot become green through missing credentials, placeholder output or model self-assessment alone.
- NFR7: Command-intention evidence is immutable and binds timestamp, source SHA/content hashes, profile, target/environment and argv. Verification rejects stale or changed evidence. Saved IaC plans and deployed revisions require separate engine/pipeline evidence.

### Portability and Maintainability

- NFR5: The operational helper uses Python standard library, explicit argv with no shell execution, deterministic machine-readable output and repository-relative paths. Plugin artifacts pass existing packaging, schema, profile-key, generalization and content checks without modifying existing plugin behavior.
