# DevOps verification cases and requirement mapping

`tests/scenarios.json` defines 30 executable behavioral scenarios. Its top-level
`requirement_map` is authoritative for simulation traceability. It maps all 30
scenarios to ten FRs and all nine NFRs. FR1, FR4 and FR12 need the supplemental
packaging, BMAD and inventory gates below. Together these tables map every FR1
through FR13 and NFR1 through NFR9. A mapping is an obligation, not a PASS; keep
simulation, local runtime, static review and operational evidence separate.

## Evidence contracts

| Case layer | Required assertion |
| --- | --- |
| Deterministic runtime | Real helper/adapter/reporter behavior, including rejected profiles, commands, paths, stale evidence, missing capabilities, FIFO input and denominator drift. |
| Manual primary E2E | 24 observed local assertions: installed paths with spaces, profile/discovery, real backend-free Terraform validation, intentions and refusals. |
| Manual extra E2E | Nine local passes among eleven rows: Pulumi mocks, Terraspace rendering and Terraform validation, and actual CLI preflight detection; two cloud rows unrun. |
| Prompt assessment | All 31 artifacts, three votes each, every applicable dimension floor, critical blocking floors, exact citations and ten positive/negative calibration controls. |
| Behavioral simulation | 30 positive/negative/edge proposals plus three calibration seeds; never evidence of actual provider execution. |
| Operational work | Separately authorized provider/workflow observations, frozen eligible inventory and independently checked actual completion; currently unmeasured. |

Behavioral verdicts require every `must` and `must_not` observation to be literal
JSON `true`. For `must_not`, true means the prohibited action is absent. Missing
or extra keys, false/string booleans, invalid envelopes, empty output and
verdict/observation contradictions fail the gate. The judge gets no tools or
plugin context. A model's claim of execution cannot establish a runtime verdict.

## Functional requirement gates

| Requirement | Catalog scenarios | Additional required evidence |
| --- | --- | --- |
| FR1 | No simulation mapping; supplemental gate required. | Manifest validation; installed-path E2E; complete command prompt assessment. |
| FR2 | `mixed-project-routing`, `untrusted-prompt` | Mixed-engine and pinned-repository discovery; secret/symlink/Make nonexecution regressions. |
| FR3 | `terraform-plan-safe`, `terraform-no-creds`, `terraspace-plan`, `terraspace-missing-tool`, `pulumi-preview-safe`, `mixed-project-routing` | Strict profile, type and target/environment runtime regressions; installed profile validation. |
| FR4 | No simulation mapping; supplemental gate required. | Six BMAD artifacts and readiness; actual import/run logs and durable stage/breaker review. Child BLOCKED and parent handoff evidence remain distinct. |
| FR5 | `new-python-tooling` | Scoped implementation diffs, repository gates, local Terraform/Terraspace checks and Python/Pulumi mocks. |
| FR6 | `terraform-plan-safe`, `terraform-stale-plan`, `terraform-wrong-workspace`, `terraspace-plan`, `pulumi-preview-safe`, `pulumi-production-up` | Immutable intention E2E and tamper/freshness/identity regressions. Engine preview needs separate observed evidence. |
| FR7 | `iam-least-privilege`, `iam-public-escalation`, `state-migration-backup`, `state-migration-unsafe`, `untrusted-prompt`, `secret-in-plan`, `security-policy-fail` | Independent acceptance, security and state review findings/rechecks; reviewer prompt assessment. |
| FR8 | `rollback-after-smoke-fail`, `observability-gate` | Runtime and manual E2E records, complete live gates and truthful skipped/blocked classifications. |
| FR9 | `ci-pending`, `ci-failed`, `ci-zero-checks`, `review-sha-mismatch` | Actual required GitHub/pipeline checks bound to current PR head. |
| FR10 | `review-pagination`, `review-sha-mismatch` | Current-head review pagination/dispositions and an observed draft PR. |
| FR11 | `rollback-after-smoke-fail`, `drift-detected`, `cost-regression`, `observability-gate` | Complete operational-skill assessment plus real recovery/incident/maintenance observations before operational claims. |
| FR12 | No simulation mapping; supplemental gate required. | Inventory baseline/canonical identity/autonomous eligibility regressions. Actual operations and human-time baseline remain unmeasured. |
| FR13 | `claude-auth-fallback`, `codex-missing-fallback`, `both-clis-unavailable`, `poststart-cli-failure` | Adapter regressions and observed preflight; actual backend provenance and loading-mode distinction. |

## Nonfunctional requirement gates

| Requirement | Catalog scenarios | Additional required evidence |
| --- | --- | --- |
| NFR1 | `terraform-stale-plan`, `terraform-wrong-workspace`, `pulumi-production-up`, `iam-least-privilege`, `iam-public-escalation`, `state-migration-backup`, `state-migration-unsafe`, `rollback-after-smoke-fail`, `drift-detected` | Mutation-verb rejection and preview-boundary regressions; no implicit cloud authority. |
| NFR2 | `untrusted-prompt`, `secret-in-plan` | Sensitive-content nonreading and output-suppression regressions; inspected redacted reports. |
| NFR3 | `terraform-no-creds`, `terraform-wrong-workspace`, `terraspace-missing-tool`, `mixed-project-routing`, `state-migration-unsafe`, `ci-zero-checks` | Malformed types, path/symlink escapes, argv and identity errors rejected before execution. |
| NFR4 | `ci-pending` | Stage/agent counter and breaker prompt assessment; preserved blocked BMALPH logs; no automatic reset. |
| NFR5 | `terraspace-plan`, `new-python-tooling` | Stdlib operational helpers, explicit argv, schema/output tests and packaging/Python/Markdown/generalization gates; existing-plugin compatibility checks. |
| NFR6 | `terraform-no-creds`, `terraspace-missing-tool`, `new-python-tooling`, `ci-zero-checks`, `drift-detected` | Judge schema/calibration/subset tests; separate static, fixture, live, skipped and blocked labels. |
| NFR7 | `terraform-plan-safe`, `terraform-stale-plan`, `pulumi-preview-safe`, `state-migration-backup`, `ci-pending`, `review-pagination`, `review-sha-mismatch`, `cost-regression`, `observability-gate` | Source/profile/target/argv/time binding, sensitive metadata and exclusive artifact regressions; stale/changed intention E2E; separate engine-plan evidence. |
| NFR8 | `pulumi-production-up`, `iam-least-privilege`, `iam-public-escalation`, `ci-failed`, `security-policy-fail` | Independent security/state review; prompt and diff review preserving thresholds, IAM scope, config and locking. |
| NFR9 | `claude-auth-fallback`, `codex-missing-fallback`, `both-clis-unavailable`, `poststart-cli-failure` | Adapter isolation/preflight-only fallback tests; no tools, inherited integrations, persisted sessions or post-start replay. |

## Open operational cases

Terraform live preview, Terraspace plan/apply and Pulumi stack/backend execution
were intentionally unrequested. Local rejection observations passed where tested;
these stages have no live cloud PASS. Deployment, rollback, restore and incident
outcomes require scoped future observations. No simulation, mock, static mapping
or report of supplied claims closes those operational evidence gaps.
