# DevOps plugin implementation campaign

## Scope and inputs

Implement a DevOps SDLC plugin alongside the PHP and React plugins. Support
Terraform, Terraspace and Python/Pulumi projects, with authenticated Claude/Codex
selection. The 90% goal requires a frozen eligible operational inventory; local
fixtures and LLM simulations do not prove production automation or time savings.

## BMAD and BMALPH evidence

BMALPH 2.11.0 initialized the BMAD workflow. Doctor passed all 18 checks.
The planning bundle completed research, brief, PRD, architecture, epics/stories
and readiness. The user then added dual CLI support: FR13, NFR9 and Story 2.3.
The finalized planning artifacts were mirrored into the configured BMAD path.
Actual `bmalph implement` imported the original seven stories into Ralph.

A bounded `bmalph run --driver codex --no-dashboard` implemented Story 3.1 in
an isolated worktree: automation_coverage.py, its regression tests and inventory
documentation. The run stopped with a circuit breaker: child sandbox restrictions
prevented writing shared Git metadata, and Bandit was unavailable in that child.
The parent retained the original failed run and imported only those three files.
It installed/resolved Bandit in its permitted tooling environment and completed
independent validation. The Ralph run is BLOCKED; parent handoff work is verified.
No breaker was reset and no sandbox bypass was used. The launch loaded the
existing 100-call limit before a later configuration correction; six calls
occurred before the breaker opened. This is recorded as a launch-configuration
defect, not a compliant five-attempt stage. Future launches must inspect the
loaded limits in the initial log before proceeding.

## Verification state

- Native Claude manifest validation passed; this is packaging evidence, not an
  authenticated Claude execution campaign. Live evaluation selects Codex explicitly.
- Prompt lint and Python format/lint/types/security/complexity checks passed.
- Current deterministic campaign: 131 tests passed, with 100% coverage of 1,057
  runtime statements and 444 branches, without exclusions. Judge harness tests
  are included in the test count; runtime coverage applies to the three scripts.
- Operator E2E: all 24 primary local assertions passed. The extra report has
  eleven rows: nine local passes and two unrun cloud rows. These include actual
  Terraform semantic validation, Terraform-rendered Terraspace validation,
  Python/Pulumi mocks and real CLI preflight detection. Terraspace 2.2.20 used
  checksum-verified Terraform 1.5.7 with its default version guard enabled;
  primary Terraform checks used 1.14.3. No version-check override was needed.
- Three cloud stages were intentionally unrequested: Terraform live preview,
  Terraspace plan/apply and Pulumi stack/backend execution. The observed Terraform
  preview rejection is a local safety-test pass, not provider-preview success.
  The other two stages remain explicitly BLOCKED in the extra report. These are
  outside the authorized local acceptance scope and never count as cloud passes.
- Independent runtime security review: seven findings fixed and rechecked.
- First full live diagnostics exposed prompt and behavioral failures. Preserve
  those failed reports; fixes do not retroactively change their verdicts.
- Version-four complete prompt and behavioral campaigns are in progress. Earlier
  runs exposed procedural omissions and a Codex citation-enum schema rejection.
  The schema now uses one shared definition with literal-safe exact source
  fragments; a real three-vote command smoke passed before the full rerun. Prompt
  assessment requires all 31 artifacts with three votes each, all ten critical
  positive/negative calibration controls with three votes each, exact citations,
  complete dimension coverage and calibrated backend/model identity. Behavioral
  simulation requires all 30 scenarios plus three calibration seeds. Codex runner
  and judge selections use explicit `gpt-5.5`; no Claude authentication is requested.
- Draft PR 13 exists. Structural review comments have explicit dispositions;
  a secret-detector false positive was removed by shortening a test method name
  without changing assertions. Current-head CI and final reconciliation remain
  pending. Recheck the latest head before
  delivery; an older green head cannot close the gate.

The testing documents map every FR1--FR13 and NFR1--NFR9 to its required evidence.
The catalog's authoritative `requirement_map` covers ten FRs and all nine NFRs;
FR1, FR4 and FR12 have separate packaging, BMAD and inventory gates. These mappings
are coverage obligations, not proof that all requirements passed. See
[the verification plan](../../../plugins/devops-sdlc/docs/testing/test-plan.md)
and [requirement gates](../../../plugins/devops-sdlc/docs/testing/test-cases.md)
for exact commands and evidence boundaries. The finite test corpus does not
exhaust possible failures or establish actual deployment, rollback or recovery.

## Operational boundaries

No cloud resources or shared state were changed. Terraform/Terraspace helper
preview execution stays blocked until backend identity can be attested; use the
reviewed protected repository plan workflow. Pulumi preview requires explicit
backend/stack selection and a live account identity check; this does not attest
repository-wrapper behavior or prove provider execution succeeded. A zero exit code records COMPLETED/UNVERIFIED,
not semantic PASS. Actual operational 90% automation and human-time reduction remain unmeasured.
The reporter requires a matching frozen identity/applicability baseline before
reporting a supplied automation target; it always records external verification
as false. Real eligible-task claims need independent verification before any
operational achievement is asserted.
