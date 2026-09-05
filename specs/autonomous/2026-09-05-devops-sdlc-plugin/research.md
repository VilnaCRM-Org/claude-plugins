# Research: DevOps SDLC Plugin

Date: 2026-09-05. BMAD analyst research uses local repository evidence and delegated infrastructure research.

## Verified inputs

- `CLAUDE.md` requires BMAD analysis, planning, solutioning, then BMALPH implementation.
- `_bmad/COMMANDS.md` resolves the installed workflow files; `_bmad/config.yaml` is the available configuration. The workflows reference an absent `_bmad/bmm/config.yaml`; the generated root config supplies equivalent variables.
- `../research/plugin-patterns.md` records PHP/React architecture, artifact spines, stage loops, CI rules, and LLM judge constraints.
- BMALPH 2.11.0 was initialized by the parent agent. No BMAD or Ralph assets will be vendored into the plugin.

## Workflow execution policy

Execute catalog commands by reading their backing agent, workflow, and step files progressively. The user authorized autonomous planning; routine discovery/menu decisions use an explicit surrogate Continue decision based on supplied requirements. Record assumptions, do not claim a human approved inferred details. Planning artifacts are copied to `_bmad-output/planning-artifacts` for `bmalph implement`.

## Initial risks

Missing cloud credentials must produce blocked live checks. Preview can execute provider/program code and reveal secrets; it requires explicit reviewed target context. Time-savings claims need operational observations beyond a synthetic test corpus.

## Infrastructure evidence

Research date: 2026-09-05. Read-only repository/source inspection; no cloud calls, deployments, credential access, repository edits, or messages to third parties.

### Verified repository inventory

Current GitHub `main` tree SHAs were queried through `gh api`; paths below refer to those revisions. Repo names alone are insufficient to infer an operational service.

| Repository | Main revision | Observed implementation |
| --- | --- | --- |
| website-infrastructure | `4513eb429b8c4b660245352941a7894cec1d8e31` | Terraform/Terraspace, 6 stack directories, AWS CodePipeline/CodeBuild, GitHub checks |
| crm-infrastructure | `e0bcb90177eb63cff584c1c26cc597eb8f5ac906` | Terraform/Terraspace, 6 stack directories, AWS CodePipeline/CodeBuild, GitHub checks |
| infrastructure-template | `37e1ffd1b9683620183f9c8b5081cec8fd63fb1c` | Modern Python/Pulumi template; committed `dev` stack, example config, quality/security/preview workflows |
| bootstrap-infrastructure | `d3015695def1c704b1265db347ed411690314b32` | Python/Pulumi AWS bootstrap; `test` and `prod`, saved-plan deployment, operations evidence |
| user-service-infrastructure | `2bfb6e62298042045903ef7fefe754e95e916c54` | Modern template and tests; `pulumi/__main__.py` exports environment/service/tag metadata only; committed `dev` |
| api-gateway-infrastructure | `f056c8b32c64e502101ec573191d8f229881bc7a` | Minimal Python/Pulumi S3 example (`s3.BucketV2("my-bucket")`); example stack only; limited generic Make/CI surface |

Adjacent application clone: `user-service` at `2a9d9d728273a12c8071450c59f49e1a1ee5148e`. Symfony/PHP service with MongoDB schema controls, contract/E2E/load/memory/mutation checks. Its CI and health tests are deployment acceptance inputs; they do not prove that the metadata-only infrastructure repository hosts it.

The separate local `bootstrap-governance` checkout is at `4b97403414db7330c0de6c38d80f12f2d61b75a2` with extensive staged/unstaged changes, including governance, CI bootstrap, IAM boundaries, service scaffolding, and promotion. Treat those as unmerged proposals, not verified `main` or deployed controls. No changes made there.

### Adapters and concrete command coverage

#### Existing Terraform/Terraspace

Website stack names: `ci-cd-iam`, `ci-cd-infrastructure`, `iam-groups`, `website-iam`, `website-sandbox`, `website`. CRM equivalents: `ci-cd-iam`, `ci-cd-infrastructure-crm`, `iam-groups`, `crm-iam`, `crm-sandbox`, `crm`.

Sources: each repository's `terraform/app/stacks/`; website `Makefile`, `terraform/config/app.rb`, `terraform/config/terraform/backend.tf`, `.github/workflows/ci-cd-infra.yml`, `aws/buildspecs/ci-cd-infrastructure/{plan,up,validate}.yml`.

Required adapter behavior:

- Discover `terraform/`, `Gemfile`, stack directories and `test`/`prod` tfvars filenames without reading secret files. Pass explicit `env`/`TS_ENV` and `stack`; never infer a live environment from the shell default.
- Reuse `terraspace-init`, `terraspace-validate`, `terraspace-plan-file`, `terraspace-up-plan`, and their selected-stack/all-stack counterparts. Support `terraspace-ci-cd-infra-init` and `terraspace-ci-cd-infra-validate` for the four CI/IAM stacks. Record which targets exist per repo; do not assume identical Makefiles.
- Treat `up`, `down`, all-stack operations, and Docker targets that source shell credentials as privileged/mutating. Existing targets often embed `-y`; a command name or lack of an interactive prompt is not authorization.
- Preserve backend identity: S3 bucket `terraform-state-:ACCOUNT-:REGION-:ENV`, state key containing project/region/app/role/env/build directory, encryption enabled, DynamoDB table `terraform_locks`. Serialize by actual backend/stack identity; don't disable locking or use force-unlock as generic recovery.
- Preserve Terraspace dependency ordering; `config.all.concurrency = 10` is an existing framework setting, not permission to run arbitrary dependent stack applies concurrently.
- Understand the CodePipeline execution chain as well as GitHub checks. Plan buildspec creates four saved plans; staging/restoration scripts carry them into apply. Require provenance tying saved plan, environment, account, source SHA and execution ID together.
- Verify the effective CodePipeline source revision. GitHub workflow requests `${GITHUB_SHA}` but has a V1 fallback that starts without a revision override; a successful trigger is insufficient proof that the reviewed SHA deployed.
- Map existing checks: Terraform format/validate/docs, TFLint, Checkov, tfsec, Terrascan, super-linter, Infracost, OIDC smoke, GitHub-token-rotation workflows. Rotation support should validate metadata/workflow results without reading credentials.
- Distinguish infrastructure rollback from application rollback. Website already provisions a dedicated CloudFront rollback CodeBuild project/role at `terraform/app/stacks/ci-cd-infrastructure/rollback.tf`; inspect the selected project's documented inputs before invoking it. Never treat restoring an old Terraform state object as a normal rollback.

Website modules establish real day-2 scope: S3 website/logging/replication, CloudFront/WAF, Route53 DNS, IAM/OIDC, CodeBuild/CodePipeline, canary/static/anomaly alarms, dashboards, SNS and Chatbot, sandbox creation/deletion. CRM buildspecs additionally expose integration tests.

#### Modern Python/Pulumi

Sources: bootstrap and user-service infrastructure `AGENTS.md`, `Makefile`, `docs/ci-guardrails.md`, `docs/sre-operations.md`, `scripts/run_pulumi_command.py`, `scripts/_pulumi_command_support.py`, `scripts/run_pulumi_drift_check.py`, `.github/workflows/pulumi-{test-deploy,prod,pr-commands,pr-command-runner}.yml` (deployment workflows are bootstrap-specific).

- Use `make doctor`, `make start`, Docker Compose, and `uv run`; direct Pulumi commands use `pulumi -C pulumi`. Keep local suites independent of AWS credentials. Reuse the repo's seeded uv/policy environment contracts.
- Route failures to existing targets: structural/catalog/fanout; policy/CrossGuard; Ruff/Ty/architecture/maintainability/dependency hygiene; unit/integration; coverage; mutation; Bats CLI; security/repo hygiene; preview/destructive/IAM/cost gates. `make ci-pr-unprivileged` is bootstrap's credential-free PR battery; `make ci-pr` and `make ci` have distinct scope.
- Preserve 100% covered branch expectations and per-suite 100% line coverage where repositories require them; plugin tests do not substitute for repository tests.
- Use bootstrap `pulumi-plan` and `pulumi-up-plan` for reviewed execution. Its manifest records preview/plan hashes, commit SHA, backend URL, stack, and creation time; apply validates relevant provenance and freshness. Other repositories lack this full saved-plan frontend, so report the capability gap rather than silently inventing commands.
- Require explicit repository/project/backend/stack/account/region/role-purpose selection. Shared backends require AWS KMS; missing shared stacks fail instead of being implicitly initialized. Stack initialization and secrets-provider migrations are separate operations.
- Enforce `test`, `prod-preview`, protected `prod` boundaries. Production workflow takes a concrete commit SHA and requires successful test deployment evidence for that SHA. Preserve environment reviewers, branch restrictions, plan provenance, and non-cancelling apply concurrency.
- OIDC short-lived roles only for CI. Preserve role purpose and least privilege. Changes to trust, platform IAM, permission boundaries, KMS, state access, or cross-repository control require dedicated risk review and negative tests; don't grant a broad admin role to make a command succeed.
- Enforce policy pack and destructive-diff controls. `allow-destructive-infra-change` is the documented override, not something an agent should add automatically to silence a failure.
- Report four distinct outcomes: passed, failed, skipped, blocked. Drift returns success with a skip when no shared backend is configured; credential-free preview artifacts can be placeholders. Neither proves live safety.
- Detect drift using `preview --refresh --expect-no-changes` and the policy pack. A `refresh` operation writes state and is a separate reconciliation decision, not a read-only drift check.
- Keep `pr-<number>`/`smoke` ephemeral environments separate from shared test/prod and verify cleanup. Never apply broad destruction to clean a local test environment.

### State, incident, cost and evidence requirements

Bootstrap sources: `pulumi/infra/{pulumi_state,pulumi_secrets,logging_bucket,backup,operations_monitoring,cost_controls}.py`, `docs/sre-operations.md`.

- State/logging controls include versioning, encryption, TLS-only policies, access blocking, logging and cross-region replicas. Shared Pulumi secrets use KMS. Replica region migration must account for both state and central logging together; the documented runbook forbids partial state-only migration updates.
- Preserve metadata-only evidence: account/region, environment, role purpose, backend type, stack, SHA, workflow URL, execution/artifact IDs, resource names and timestamps. Never inspect state object contents, raw exports, `.env`, credential-export scripts, tokens or decrypted outputs for inventory.
- Bootstrap operations signals cover failed/aborted/expired backup jobs; KMS destructive/security changes; IAM/OIDC changes; S3 encryption/logging/policy/replication changes. SNS/KMS/EventBridge plus durable SQS capture exist in code. A queue/subscription alone does not prove a staffed incident route.
- Support severity/owner triage, containment options, rollback versus fail-forward, recovery validation, cleanup and post-incident actions. Do not fabricate human attestations or send incident messages without authorized scope.
- Reuse `report-well-architected-evidence`, question verification, closeout, and reviewed owner/alert/DR/exception evidence targets. Missing owner/external-control evidence remains blocked.
- Existing freshness expectations: shared-stack drift 24 hours; restore drill 90 days; alert route and cost threshold review 30 days. Bootstrap target posture is daily Backup + S3 versioning RPO and reviewed restore within one business day; report observed proof separately from targets.
- Cost adapter must separate Terraform Infracost estimate from Pulumi static resource/quota cost proxy and actual AWS cost telemetry. Website Infracost currently reads `terraform/plan.json`; verify freshness and source SHA before presenting the diff as current. Bootstrap budgets alert at actual >80% and forecast >100%; anomaly threshold is configurable. Support ownership/cost allocation tags and catalog fanout/quota checks.
- Never promise generic automatic infrastructure rollback. Prepare a revert/fail-forward plan against current state; validate data/schema compatibility and backup recovery separately. The service's MongoDB schema/fixture reset targets must not be used against production for health verification.

### Measuring “90%+ automated” honestly

Use a versioned machine-readable inventory, not command count or test coverage. One denominator row is `(repository, project/stack, environment, operation-family)` with source revision/path, detected backend class, owner, risk tier, required preconditions, adapter command, required evidence, expected outcome, and exclusion reason if applicable. Freeze baseline and additions/removals in review.

Seed scope with the six verified infrastructure repositories, 12 Terraspace stack definitions, and four committed non-example Pulumi stack configurations (`dev` in template and user-service; `test`/`prod` in bootstrap). API gateway's example config is onboarding scope, not a deployed stack. Do not assume every Terraform stack/env combination is live; reconcile tfvars/catalog declarations with authorized metadata inventory first.

Operation families: discovery/preflight, local validation, security/policy, preview/plan, change review, deploy, post-deploy health, drift, incident triage, rollback/recovery preparation, backup/restore verification, cost/quota, dependency/template maintenance, environment onboarding/retirement, audit evidence. These are a proposed taxonomy, not 15 equally applicable operations everywhere.

Coverage = accepted applicable rows completed end-to-end by the plugin / all accepted applicable rows. Report separately by engine, risk tier, environment and family; also report frequency-weighted human toil where measured. Human approvals may remain an intentional checkpoint, but an automated proposal alone is not a completed deployment. Skipped/no-credential/mock runs, docs-only handlers and unsupported repositories stay visibly incomplete. Publish denominator, exclusions, task traces, manual interventions and failed/blocked cases alongside the percentage. No present 90% achievement claim is supported by this research.

### Acceptance scenarios

1. Fresh credential-free clone: detects the correct engine and actual supported Make targets, runs appropriate local checks, and labels cloud preview/drift skipped rather than passed.
2. Terraform saved-plan path: selects website/CRM stack and test account explicitly, preserves S3/DynamoDB identity, stages/restores the exact plan, verifies CodePipeline SHA and health; rejects the V1 unpinned fallback as same-SHA evidence.
3. Pulumi test-to-prod promotion: reviewed commit and saved plan survive handoff; stale/tampered/hash/backend/stack/SHA mismatch and missing test-deploy proof are rejected before apply.
4. Fork/untrusted PR: no privileged credential execution; useful unprivileged checks still run. PR comment commands validate actor, repo, PR head, supported command and environment.
5. IAM/state/KMS change: negative policy/trust tests fail on wider access; unsupported overrides and silent shared-stack creation are rejected; no state/secret payload enters outputs.
6. Drift incident: real shared stack drift produces a non-mutating diff, severity/owner/evidence, and reviewed reconciliation options; no automatic `refresh`/apply.
7. Critical deletion or replica move: guardrails block unintended deletion/replacement and partial migration; approved recovery plan identifies state/log dependencies and retained data.
8. Failed deployment: diagnoses GitHub and CodePipeline/CodeBuild evidence, distinguishes application CloudFront rollback from IaC revert/fail-forward, validates recovered service and retains cleanup proof.
9. Operations/cost: stale restore/alert/cost proof or ownerless queue remains blocked; cost proxy is never labeled actual spend; stale plan.json is rejected for current cost claims.
10. New Python/Pulumi service: scaffold into authorized repository using current template, test policy/runtime/CI contracts without AWS, prepare explicit KMS-backed initialization and ownership; metadata-only and S3-example repos are not reported as deployed services.

### Validation and unresolved limits

Validated by pinned GitHub tree/content reads and clean local clone source inspection. No runtime tests were needed for this research-only artifact. No live deployment, IAM, environment reviewer, account owner, backend, state, alert delivery or health assertions were made. Full CRM implementation parity and all Terraform runtime configuration remain unverified. The dirty governance checkout may change future interfaces and should receive a separate review at its final committed revision. Plan artifact confidentiality and exact runtime authorization must be assessed before operational plugin implementation.

## Existing Plugin Pattern Evidence

Source reviewed: `work/claude-plugins` at `9580854`.

### Architecture to reuse

Model the plugin on `php-backend-sdlc` / `react-frontend-sdlc`:

1. Add `plugins/devops-sdlc/.claude-plugin/plugin.json` and a matching entry
   in `.claude-plugin/marketplace.json` (`name` must equal the directory name;
   `source` must be `./plugins/devops-sdlc`).
2. Use seven stage commands: setup, issue, plan, implement, review, QA, and
   finish-PR, plus one `/devops-sdlc` orchestrator. Every command needs
   frontmatter `description`, bracketed `argument-hint`, and the five exact
   H2 sections: Inputs, Procedure, Loop & exit condition, Iteration guard,
   Failure escalation.
3. Setup owns a generated, validated `.claude/devops-sdlc.yml` project profile.
   Treat declared `null` target/capability as an explicit skip-with-note; do
   not invent a host command. Profile keys used by skills must be listed in
   `docs/profile-schema.md`.
4. Keep the staged orchestration invariant: independently re-check each stage
   exit condition; resume from durable artifacts; cap every stage at five
   iterations; QA FAIL returns to implementation; a Ralph breaker is terminal
   and is never reset. Finish only after green required checks and no unresolved
   review findings (or explicitly documented capability degrade).
5. Reuse BMAD/BMALPH the same way: setup runs `bmalph init` only for a fresh
   target; planning direct-loads a `bmad-autonomous-planning` skill and produces
   `research.md`, `brief.md`, `prd.md`, `architecture.md`,
   `epics-stories.md`, and `readiness.md` under `specs/<slug>/`; implementation
   runs `bmalph implement` then `bmalph run --driver claude-code`. Record
   assumptions rather than prompting during planning.

For DevOps, replace language-specific profile facts with detected IaC and
delivery facts, for example: `iac.tool`, `iac.root`, `iac.modules`,
`iac.environment`, `runner.{validate,lint,plan,test,apply_dry_run}`, CI required
checks, deployment target, and capabilities such as ephemeral environment,
policy-as-code, security scan, smoke test, and publish PR comments. Make every
write/deploy/apply action opt-in and distinguish plan/dry-run from apply.

### Agents, skills, scripts

Use seven agents with the existing mandatory eight-section spine: Profile keys
consumed, Role, Inputs, Outputs, Allowed actions, Degrade paths, Iteration
discipline, Smoke prompt. Agent frontmatter requires `name`, `description`,
`tools`, and `model`; names must be kebab-case and match filename and H1. A
DevOps set could be `devops-implementer`, `iac-policy-reviewer`,
`fr-nfr-reviewer`, `qa-deployment-tester`, `ci-fixer`,
`pr-comment-resolver`, and `security-auditor`.

Skills belong at `skills/<kebab-name>/SKILL.md`, with only `name` and
`description` frontmatter. The first H2 must be exactly `## Profile keys
consumed`; skill descriptions must say `Use when` or `When to use`. Include an
applicability/capability gate and its skip path. Ship a root-level
`SKILL-DECISION-GUIDE.md` without frontmatter, with a triage-first decision
ledger so no skill is silently skipped. Candidate DevOps skills: IaC
architecture/modules, Terraform/OpenTofu or Pulumi workflow, Kubernetes/Helm,
CI workflow, policy-as-code, secrets/configuration review, deployment strategy,
rollback and smoke testing, observability/SLO, cost/performance, security audit,
and BMAD FR/NFR gate.

Scripts are Bash under `scripts/`, tested by matching `.bats` files. Reuse the
common helper/profile-generation/validation/governance/FR-NFR/comment-loop
shape; DevOps-specific scripts should parse the profile, run only mapped
commands, and be idempotent. There are no `hooks/` directories in either
existing plugin, despite the generic README listing hooks as an optional Claude
plugin component.

### Meaningful E2E and LLM judge

The existing PHP dogfood is a useful standard: use a disposable sandbox
repository, run actual installed-plugin scripts with `CLAUDE_PLUGIN_ROOT`, drive
setup through PR, record each stage exit condition, commands/evidence, skill
triage decisions, commits/PR, and honest environmental degrade notes. For
DevOps, use a fixture IaC repo and an isolated local/emulated target; prove
validate, lint, policy scan, plan/dry-run, ephemeral deploy, smoke test,
rollback, PR checks, and comment handling. Never claim an apply/deploy executed
if only static validation ran. Keep this as a documented evidence artifact;
the existing E2E is not a CI test.

The repository's LLM-as-judge automatically discovers every plugin artifact.
CI runs it only with `ANTHROPIC_API_KEY`, using:

```bash
python3 tools/plugin-quality/judge/run_judge.py \
  --gate --require --votes 3 --model sonnet --report judge-report.md
```

It evaluates commands, agents, skills, and meta-guides; odd three-vote median
is required for a stable gate. It blocks only when a critical dimension scores
1--2. Deterministic checks remain mandatory regardless of credentials, so add
unit tests only for new Python tooling and Bats tests for shell scripts.

### Required local checks

```bash
npx --yes markdownlint-cli2 "plugins/devops-sdlc/**/*.md"
shellcheck -x plugins/devops-sdlc/scripts/*.sh
npx --yes bats plugins/devops-sdlc/tests/*.bats
python3 tools/plugin-quality/lint/lint_all.py
(cd tools/plugin-quality && python3 -m unittest discover -s tests -v)
claude plugin validate plugins/devops-sdlc --strict
```

If Python toolkit code changes, CI additionally requires Ruff format/lint, ty,
Bandit, Xenon, and 100% line-and-branch coverage. Python tooling must stay under
`tools/plugin-quality` or `tools/security-audit-validation` to be included.

### Known traps

- Root `ci.yml` hard-codes `plugins/php-backend-sdlc` for profile-key and
  generalization checks. A new DevOps plugin needs equivalent generic or
  additional DevOps checks; otherwise its profile-key references and
  generalization invariants are not covered by those jobs.
- Marketplace CI iterates all `plugins/*`, so new manifest, semver, source, and
  plugin-directory identity must be correct immediately. Release tags must use
  `devops-sdlc-vX.Y.Z` matching the manifest.
- QA command/agent names containing the dash token `qa` must exclude `Write`
  and `Edit` from `allowed-tools` / agent `tools` (L33). QA verdicts must derive
  from observed runtime behavior and include replayable reproduction steps.
- Static lint treats all S1--S3 findings as blockers. In particular: skill and
  agent trigger phrases, exact H2 spines, `allowed-tools` shape, declared
  references, canonical escalation fields, and meta-guide no-frontmatter rules
  are enforced.
- Keep concrete target-repository names and values out of plugin components;
  profile examples must use a fenced opener carrying `# profile-example` or
  generalization audit will flag them.

## Planning Execution Record

The installed catalog commands analyst/create-brief/create-prd/create-architecture/create-epics-stories/implementation-readiness were executed by progressively reading their backing workflow and step files. Routine A/P/C selections used authorized autonomous surrogate Continue decisions. Root `_bmad/config.yaml` supplied the missing module-config variables. Brief steps 1-6, PRD init/discovery/vision/executive-summary/success/journeys/domain/innovation-skip/project-type/scoping/functional/nonfunctional/polish/complete, architecture steps 1-8, epics steps 1-4, and readiness steps 1-6 completed. User did not separately approve surrogate assumptions.

## Final Contract Overrides

The inherited pattern report is research, not the final specification. This plugin uses `/do-sdlc*`, `.claude/devops-sdlc.json` and the Python standard-library helper described in architecture.md. Earlier suggested `/devops-sdlc`/YAML/Bash designs were not selected. Commands support only declared reviewed contracts; no mutation adapter is added to the helper.
