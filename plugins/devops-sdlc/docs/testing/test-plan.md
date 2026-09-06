# DevOps verification plan

Run from the repository root with the selected CLI already authenticated. Keep
reports outside the plugin input tree and use an immutable reviewed snapshot for
live assessment. Do not change that snapshot while either campaign is running.
`uv` supplies PyYAML for the shared artifact loader; the operational helpers
remain standard-library Python.

## Deterministic and observed gates

```bash
uv run --with pyyaml==6.0.3 python -m unittest discover \
  -s plugins/devops-sdlc/tests
uv run --with pyyaml==6.0.3 python tools/plugin-quality/lint/lint_all.py
markdownlint-cli2 'plugins/devops-sdlc/**/*.md'
```

Run the repository's pinned Python format, lint, types, security, complexity and
branch-coverage gates as configured in CI. Require 100% statement and branch
coverage of the three operational scripts, without exclusions. Use
`--rcfile=/dev/null` for coverage run, report and JSON export so the repository
configuration cannot exclude CLI entry-point lines. Record the actual
test, statement and branch totals for the evaluated source in the campaign report.

Operator records are `manual-e2e.json` and `manual-e2e-extra.json`: 24 primary
local assertions passed; eleven extra rows contain nine passes and two unrun
cloud rows. Terraform live-preview refusal was observed successfully, but live
preview itself was not run. Preserve all three unrequested engine cloud stages
as gaps in operational evidence; do not turn refusal success into provider success.

## Complete prompt-quality gate

```bash
uv run --with pyyaml==6.0.3 python plugins/devops-sdlc/tests/prompt_judge.py \
  --plugin-root plugins/devops-sdlc --backend codex --model gpt-5.5 \
  --jobs 3 --timeout 300 > prompt-judge-report.json
```

This invokes all 31 artifacts with three votes each and all ten positive/negative
calibration cases with three votes each. Omit `--dimensions` for the full gate.
A subset can diagnose failures, but reports PARTIAL and exits nonzero. Require
PASSED, complete inventory/dimension coverage, valid exact citations, unchanged
input hashes and a calibrated backend/version/model identity. No authentication,
missing model identity, invalid responses or calibration failure is nonzero.

## Complete behavioral gate

```bash
uv run --with pyyaml==6.0.3 python plugins/devops-sdlc/tests/behavior_judge.py \
  --plugin-dir plugins/devops-sdlc --backend codex \
  --model gpt-5.5 --judge-model gpt-5.5 \
  --calibrate --require --jobs 2 --timeout 300 --report behavior-report.json
```

Require all 32 catalog scenarios plus the safe-preview, unsafe-apply and
false-success calibration seeds. Omit `--ids` for the full gate. A selected-case
smoke result cannot establish full catalog completion. Preserve runner/judge
provenance and verify `full_catalog` and unchanged catalog/plugin inputs.

The new G4 case, `iteration-budget-exhausted-fallback`, starts at 4/5 in a
canonical `attempts.json` entry referenced by the human summary. The caller
atomically reserves count plus active owner/token under the verified host lock;
the delegate uses that same reservation without a second increment. It consumes
the fifth attempt on a local-test failure, then tests
a successful alternate-backend preflight. Require a durable 5/5 stop, preserved
evidence and independent next work without a sixth implementation attempt. Its
live verdict must come from the current full-catalog report; earlier 30-case
campaigns do not cover it.

The G4 case `atomic-reservation-concurrent-resume` starts with two sessions
sharing one canonical task/stage/agent/target/environment identity at 4/5.
Require a verified atomic reservation before any increment or start, one
conditional winner, and BLOCKED handling for an active owner, uncertain
completion or an unavailable primitive. A proposed transaction is not evidence
that it ran. Earlier 31-case campaigns do not cover this concurrency case.

Both tools support explicit Claude selection or preflight-only automatic
fallback. Model names are backend-specific and never translated; the commands
above intentionally select Codex and require no Claude login.

## Campaign exit and open evidence

Preserve failed diagnostics alongside the final complete campaigns. Never select
only passing cases from separate stochastic runs to construct a passing campaign.
Record the actual current PR head, CI results and paginated review dispositions
before delivery. An older green head or a skip-clean LLM CI job cannot substitute
for current source verification and actual live judge evidence.

Close the authorized implementation campaign only with the required local,
complete live-evaluation and current-head PR evidence. A blocked BMALPH child run
remains BLOCKED even when parent handoff validation succeeds. Operational cloud
stages and actual 90% automation remain outside achieved results. Do not describe
this finite corpus as all possible tests or claim every requirement fully proven.
