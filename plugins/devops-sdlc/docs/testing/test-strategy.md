# DevOps verification strategy

Keep four evidence layers separate: deterministic runtime tests, observed local
operator E2E, live prompt assessment, and live behavioral simulation. None proves
actual cloud deployment or the 90% operational automation target. Required checks
remain failed, pending or blocked until their own evidence supports success.

## Prompt assessment

`tests/prompt_judge.py` assesses all 31 shipped prompt artifacts: eight commands,
seven agents, fourteen skills and two meta-guides. Each artifact receives three
independent votes for every applicable rubric dimension. Every dimension median
must meet its floor; any critical vote at or below its blocking floor blocks.
Ten mandatory calibration cases provide positive and negative controls for all
five critical dimensions, with three votes per case: 123 calls for a full run.

The strict schema requires exactly the requested dimensions and each dimension's
integer score, bounded evidence and exact artifact-substring citation. Invalid
citations, unknown model identity, failed calibration, changed inputs or invalid
responses fail closed. Reports retain SHA256 input/artifact identities and each
vote's actual backend, CLI version, requested/observed model and model source.
A requested model is not independent proof of the model actually served.
Dimension subsets report PARTIAL and exit nonzero, even when selected dimensions
pass; fixture responses never count as live coverage.

The impartial prompt judge gets no plugin context (`plugin_root=None`) and no
tools. Its artifact is untrusted data. Reassess changed prompts live; static lint
or an earlier diagnostic cannot substitute for the final complete campaign.

## Behavioral simulation

`tests/behavior_judge.py` evaluates every catalog scenario in an inert disposable
fixture and requires three calibration seeds for a full gate. The fixture has
minimal Terraform, Terraspace and Pulumi metadata, with no credentials, state,
provider configuration or cloud resources. The runner proposes decisions; an
independent no-tool judge assesses the response. A simulation PASS establishes
only that proposed behavior met that scenario's observations.

G4 adds an exact attempt-budget boundary across authenticated backend fallback.
The same implementation ledger progresses from 4/5 to 5/5 before a failed fifth
attempt; backend availability must not permit a sixth attempt or a new ledger,
task identity or stage label for the same work. Failure evidence and independent
next actions remain required. A second G4 case covers two sessions competing for
the same final attempt: an active reservation, uncertain completion or missing
verified atomic primitive must block another start. Neither caller nor delegate
may increment separately or claim a reservation occurred in the simulation.
These cases need fresh live evidence; earlier 30- and 31-scenario results are
historical and do not satisfy the expanded catalog.

Credentialed-preview cases require a trusted host authorization for the exact
source, actor, operation, backend and temporary role. Negative cases reject a
backend mismatch and fork code offered write-capable credentials; caller flags
do not prove isolation or IAM permissions. A separate case blocks all plugin
helper execution without an independent approved source baseline. The positive
preview fixture supplies hypothetical trusted-host prerequisites and requires
runtime verification before execution; it does not claim a live cloud result.

Claude uses native plugin loading for the runner. Codex uses bounded command,
agent and skill Markdown supplied by `scripts/agent_cli.py`; it does not natively
load a Claude plugin. Both run without executable tools. The independent judge
receives no plugin directory or context. Preserve this distinction in reports.

Select `--backend auto|claude|codex`; `--prefer` orders auto preflight. Fallback is
limited to missing binary/authentication before a CLI starts. Timeout, invalid
output or uncertain execution after start never triggers replay on another CLI.
Use Codex with explicit `gpt-5.5` for this campaign; no Claude authentication or
Claude live run is required by this selection. Native packaging validation and
unavailable-Claude detection remain separately labeled checks.

## Observed execution and operational measurement

Local E2E observes actual CLI behavior, including safe refusals. A helper result
COMPLETED/UNVERIFIED is process evidence; semantic PASS needs independent observed
output, such as Terraform's JSON validation result. Source inspection is STATIC
REVIEW and cannot establish runtime PASS. Pulumi mocks are local fixture evidence.

Three engine cloud stages were intentionally unrequested: Terraform live preview,
Terraspace plan/apply and Pulumi stack/backend execution. They are not required
passes for the authorized local campaign, and none is a completed cloud operation.
Provider, saved-plan, deployment, rollback and recovery claims need separately
scoped authorization and observed operational evidence before becoming acceptance
claims. The current campaign neither exhausts possible tests nor closes every
operational requirement.

Actual automation and hands-on time remain unmeasured. The inventory reporter
separates supplied completion from autonomous completion, requires a matching
frozen identity/applicability baseline before reporting its 90% target, and sets
`externally_verified` to false. Supplied claims, simulations and local fixtures
cannot independently establish actual operational success or time savings.
