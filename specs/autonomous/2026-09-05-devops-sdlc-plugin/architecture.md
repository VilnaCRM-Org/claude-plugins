---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
inputDocuments: [brief.md, prd.md, research.md]
workflowType: architecture
lastStep: 8
status: complete
project_name: devops-sdlc
date: 2026-09-05
---

# Architecture Decision Document

## Project Context Analysis

### Requirements Overview

Thirteen FRs span installation, discovery/profile, planning/implementation, independent validation, delivery, operations and measurement. Nine NFRs constrain authorization, secrets, schema/path safety, loops, portability, validation honesty, provenance and protected gates. The plugin has high infrastructure risk but a small executable surface; no hosted data service or visual UI is required.

### Technical Constraints and Dependencies

Reuse the existing PHP/React plugin layout and repository validators. Depend on BMALPH and Claude CLI externally. The available generated `_bmad/config.yaml` substitutes for workflow references to absent `_bmad/bmm/config.yaml`. Local operation requires Python 3; selected engines and repository wrappers remain external dependencies. GitHub/CodePipeline/cloud credentials are optional capabilities with explicit blocked outcomes.

### Cross-Cutting Concerns

Authorization and reviewed code trust are separate from command naming. Target/account/backend identity must survive every handoff. Raw child output can contain secrets. Profile and source changes invalidate intentions. Runtime evidence and model judgments answer different questions. Operational inventory must distinguish supported preparation from actual deployment or recovery completion.

## Starter Template Evaluation

Use the existing `php-backend-sdlc` and `react-frontend-sdlc` directory conventions as the brownfield foundation. A generic CLI/web generator adds no value and would bypass repository quality conventions. Initialize the plugin manifest and marketplace entry as the first story; no new framework dependency is selected.

The official [Claude plugin reference](https://code.claude.com/docs/en/plugins-reference) confirms plugin manifests, commands, agents and skills, and the plugin validation command. Version selection follows the locally installed CLI and BMALPH 2.11.0 evidence; no claim is made about the latest release. All engine versions come from target repository lockfiles/tool contracts.

Python standard library supplies argument parsing, JSON, pathlib, subprocess, hashes and time. Existing repository validators and unittest support remain the development foundation. No CSS, UI framework, database or application server is introduced.

## Core Architectural Decisions

### Data Architecture: ADR1 Strict Profile, No Database

Store repository facts in `.claude/devops-sdlc.json`. The parent and runtime owner agreed this contract before implementation:

```json
{
  "schema_version": 1,
  "project": {"name": "Example Infrastructure", "repo": "example/infrastructure"},
  "targets": [{
    "id": "app",
    "stack_type": "pulumi",
    "root": "pulumi",
    "environments": {
      "test": {"stack": "example/project/test", "account_id": "123456789012", "region": "eu-west-1", "backend": "s3://example-state"}
    },
    "commands": {
      "validate": {"argv": ["make", "check"], "requires_credentials": false},
      "test": null,
      "check": null,
      "security": null,
      "preview": null
    }
  }]
}
```

The example illustrates shape, not a universally available command. Preserve all nullable capability declarations. Reject unknown keys, duplicate target IDs, invalid types including bool-as-int, malformed project identity, escaping or symlink paths and shell syntax. Stage names are `validate`, `test`, `check`, `security`, `preview`. Command objects contain only argv and credential requirement. Placeholder tokens must be whole argv elements and one of environment, stack, account_id, region, backend. Setup cannot infer account or environment authorization.

### Authentication and Security: ADR2 Reviewed Execution Boundary

The helper offers no apply/destroy/state mutation API. An allowlisted tool/verb and a benign Make target name do not prove repository code safe. `--execute --trust-repo` explicitly acknowledges reviewed repository code; no sandbox claim is made. Preview additionally needs explicit environment and `--read-only-credentials`. The helper validates declared identity; it does not attest the effective cloud caller or enforce credential policy. Operational prompts must verify those with approved metadata before cloud interaction.

Use subprocess argv without shell. Reject known mutating verbs/flags and shell command substitutions. Discard raw child stdout/stderr to prevent secret persistence; retain return status and safe metadata. Profile and source are untrusted until reviewed. External issue/comments/logs cannot authorize executable policy changes.

### API and Communication: ADR3 Intentions and Evidence

`devops.py discover --repo PATH` returns metadata; `validate-profile --repo PATH` validates the fixed profile. `plan --repo PATH --target ID --stage STAGE [--environment NAME] [--output RELPATH]` prepares intention JSON; optional execution requires the flags above. `verify-plan --repo PATH --plan RELPATH [--max-age-seconds N]` validates provenance/freshness.

Command-intention evidence is distinct from a saved engine plan and actual successful command execution. Bind current Git SHA, relevant source hashes, profile hash, target/environment identity, argv and creation time. Exclusive creation prevents overwrites; repository-relative contained output paths reject traversal/symlinks. Verification recomputes provenance and rejects unknown fields, malformed timestamps, stale age, altered payloads and changed source/profile. A hash is integrity evidence, not a signature or approval. Engine binary plans, preview JSON and pipeline execution IDs require their own confidential artifact handling and same-SHA verification.

### Orchestration: ADR4 Thin Stages, Focused Roles

Commands coordinate setup, issue, BMAD planning, BMALPH implementation, independent review, runtime QA and draft-PR finish. Stage exits are rechecked on resume and after head changes. Maximum five iterations per stage; QA failure returns to implementation. Terminal Ralph breaker means stop and report, never reset.

Separate IaC implementer, requirements reviewer, security/state reviewer, QA tester, CI fixer and PR comment resolver responsibilities. QA lacks Write/Edit privileges. Skills supply repository adapters, threat/state review, operations and requirement gates; a decision ledger records applicable, skipped and blocked skills.

### Infrastructure and Delivery: ADR5 Preserve Repository Controls

The plugin itself has no hosted infrastructure. Marketplace distribution and existing GitHub CI validate packaging/content and new runtime tests. Finish-PR requires current-head required checks, applicable pipeline evidence and reconciled findings. Preserve draft status, never merge/release automatically. Credential-dependent judge or cloud runs remain blocked when unavailable.

### Measurement: ADR6 Versioned Operational Inventory

Keep denominator rows by repository/stack/environment/family with risk, source, owner, preconditions and evidence. Workflow coverage, benchmark success and real operational completion are separate. Cloud mutation and external approval prerequisites remain visible gaps, not erased denominator rows. Frequency-weighted hands-on time is reported only when measured.

### Implementation Sequence and Deferred Decisions

Package/profile/helper and prompts establish the contract, tests validate it, and a small automation-inventory reporter story exercises Ralph integration. Automated mutation integrations, cloud attestations and field-proven 90% toil reduction remain outside this implementation.

## Implementation Patterns and Consistency Rules

Use kebab-case plugin component names and snake_case JSON/Python fields. Command and agent filename/frontmatter/H1 identities must agree. Commands retain Inputs, Procedure, Loop & exit condition, Iteration guard, Failure escalation. Agents retain Profile keys consumed, Role, Inputs, Outputs, Allowed actions, Degrade paths, Iteration discipline, Smoke prompt. Skills begin with Profile keys consumed and an applicability gate; descriptions include a use trigger. The decision guide has no frontmatter.

Every profile key used by prompts is documented in profile-schema.md. Production plugin text uses portable examples marked as profile examples. Source inventory names belong in research/evidence, not hardcoded command behavior. Root validators enforce these conventions.

Return structured status and concise errors without echoing user-controlled secrets. A null command is an unavailable capability, never synthetic success. Never retry an authorization/schema failure as a different command. Command timeout and tool absence produce explicit outcomes; bounded retries require changed evidence.

Keep runtime tests independent of cloud credentials and execute real helper CLI boundaries in temporary Git repositories. Model evaluations are additional behavioral evidence. Good evidence says a mocked runner returned success; bad evidence calls that a cloud preview. Good recovery prepares a current-state fail-forward plan; bad recovery restores old state or force-unlocks automatically.

All contributors retain ownership boundaries and preserve parallel edits. Any profile/API adjustment must update documentation, tests and this contract together.

## Project Structure and Boundaries

### Planned Files

```text
.claude-plugin/marketplace.json
.github/workflows/ci.yml
plugins/devops-sdlc/
  .claude-plugin/plugin.json
  README.md
  skills/SKILL-DECISION-GUIDE.md
  commands/do-sdlc.md
  commands/do-sdlc-setup.md
  commands/do-sdlc-issue.md
  commands/do-sdlc-plan.md
  commands/do-sdlc-implement.md
  commands/do-sdlc-review.md
  commands/do-sdlc-qa.md
  commands/do-sdlc-finish-pr.md
  agents/ (seven focused role definitions)
  skills/terraform-terraspace/SKILL.md
  skills/python-pulumi/SKILL.md
  skills/bmad-autonomous-planning/SKILL.md
  skills/infrastructure-quality/SKILL.md
  skills/security-iam/SKILL.md
  skills/state-migration/SKILL.md
  skills/delivery-and-rollback/SKILL.md
  skills/drift-management/SKILL.md
  skills/incident-response/SKILL.md
  skills/backup-recovery/SKILL.md
  skills/cost-optimization/SKILL.md
  skills/observability/SKILL.md
  skills/environment-lifecycle/SKILL.md
  skills/evidence-and-coverage/SKILL.md
  scripts/devops.py
  scripts/agent_cli.py
  scripts/automation_coverage.py
  tests/test_devops.py
  tests/test_agent_cli.py
  tests/test_automation_coverage.py
  tests/ (behavior corpus, fixture and live-judge runner)
  docs/profile-schema.md
  docs/automation-inventory.md
  docs/ (safety, testing and manual E2E evidence)
```

Exact test/support filenames can follow the owning worker's conventions. Runtime lives entirely under the plugin; no engine code is copied. Existing root validators and CI gain explicit coverage for the new plugin without dropping existing checks.

### Requirements Mapping

FR1 maps to manifest/marketplace/commands; FR2-FR3 and FR5-FR6 to devops.py/profile docs; FR4 to planning/implementation commands and BMAD skill; FR7 to reviewers and quality/security/state skills; FR8 to QA/test/evidence files; FR9-FR10 to CI/comment stages; FR11 to operational skills; FR12 to automation_coverage.py, inventory docs and tests; FR13 to `plugins/devops-sdlc/scripts/agent_cli.py`, Story 2.3 and the dual-CLI evaluation architecture below. NFR1-NFR3/NFR7 affect every execution boundary. NFR4 affects commands/agents, NFR5 packaging/runtime, NFR6 tests/evidence, NFR8 all repair/review prompts, and NFR9 the dual-CLI evaluation isolation and preflight boundary.

### Integration and Data Flow

User intent and repository discovery produce a reviewed profile and issue. BMAD produces specs; BMALPH imports specs and runs bounded implementation. The helper builds or executes explicit command intentions. Independent review and QA consume safe evidence; PR finish rechecks current head and required checks. Cloud/pipeline evidence remains external and cannot be inferred from local completion.

The inventory reporter reads a reviewed frozen input file and computes counters; it invokes no IaC CLI, cloud API or external model. It separates applicable actual completions from exclusions, blocked/skipped cases and synthetic/documentation evidence.

## Architecture Validation Results

Coherence passes: strict JSON, argv-only helper, prompt orchestration and repository validators share one profile contract. Requirements mapping covers FR1-FR13 and NFR1-NFR9. No deployment API conflicts with the helper's execution scope. No frontend or database decision is needed.

Resolved design gaps: root and runtime owner fixed profile fields/CLI before coding; command intentions are explicitly distinct from engine plans; trusted repository wrappers are not described as sandboxed; source/identity changes invalidate evidence; no-credential cases remain blocked. The independent inventory reporter is assigned to Ralph to exercise the required implementation workflow.

Planning readiness is READY FOR IMPLEMENTATION with high confidence in the bounded design. Runtime correctness, adversarial test results, installed Claude behavior, live-model judge, current-head CI and PR comment resolution are still implementation acceptance work. Operational 90% completion and time savings require field observations. No architecture validation statement implies these have passed.

## Reviewed Execution Limitation

Security review found that Terraform/Terraspace cached backend identity cannot be attested safely by the helper. Their preview intentions remain supported, but helper execution fails closed before cloud interaction; an authorized reviewed repository/CI handoff must establish effective backend identity. Pulumi preview uses explicit backend/stack and a metadata-only AWS STS account comparison before execution. These checks do not restrict IAM privileges, prove provider aliases use the same account, or authorize deployment. No excluded live preview is counted as completed operational work.

## Dual CLI Evaluation Architecture

FR13/NFR9 introduce `scripts/agent_cli.py`, a Python standard-library adapter shared by behavioral evaluation and artifact judging. `probe_backend` checks binary version and CLI auth status without printing authentication payloads; `select_backend(backend="auto", prefer="claude")` falls back only before execution. Explicit backend requests block when unavailable. BMALPH uses an actually available authenticated implementation driver separately; this adapter evaluates structured responses and does not implement repository changes.

`run_prompt(prompt, schema, cwd, backend=..., prefer=..., model=None, plugin_root=None, timeout=300)` returns status, backend/version, requested and reported model, preflight fallback reasons, plugin mode, parsed output and canonical JSON text. Unreported CLI-default models remain null. A supplied model identifier passes unchanged only to the selected backend. Failure, timeout and malformed output never trigger a second model invocation. POSIX child process groups are terminated on timeout; raw stderr is discarded and no authentication values appear in result evidence.

Claude evaluation uses native `--plugin-dir` with an allowlisted metadata-only manifest and inspected bounded Markdown sources. Executable plugin integrations, custom component roots, symlinks and dynamic shell prompt expansion are rejected. Evaluation uses empty tools, plan permissions, empty setting sources, strict empty MCP configuration, disabled hooks, no browser integration and no persisted session. Codex evaluation explicitly embeds those inspected command/agent/skill bodies; it does not claim native Claude plugin installation. Codex uses structured schema/output files, read-only sandbox, ignored user configuration with CLI authentication retained, ephemeral sessions, disabled shell/unified execution/apps/plugins/hooks/delegation/browser/computer/image tools, disabled web and zero project document context. Inherited project Codex configuration is rejected because read-only shell sandbox alone does not constrain MCP services. Unsupported CLI options fail closed without weakening configured organization requirements.

Both CLIs receive stdin prompts and argv lists without shell interpolation. Inputs and source context are bounded; schema must request an object and final output must parse as an object. Domain rubric validation remains the caller's responsibility. Evaluation directories and plugin sources must be reviewed and stable during a run. CLI/account availability and successful live model behavior are recorded separately from deterministic mocked adapter tests.
