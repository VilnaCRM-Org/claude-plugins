# Behavioral simulation plan

`tests/scenarios.json` is the executable source of truth. Its 30 positive,
negative, and edge scenarios map to FR1--FR13 and NFR1--NFR9 and cover
Terraform, Terraspace, Pulumi, mixed projects, IAM, state migration, stale
plans, CI/review evidence, secrets, untrusted prompts, drift, rollback, cost,
security, observability, incidents, and onboarding.

Run deterministic validation before a live simulation:

```bash
python3 -m unittest discover -s plugins/devops-sdlc/tests
```

Run the complete behavioral gate with an authenticated selected CLI:

```bash
python3 plugins/devops-sdlc/tests/behavior_judge.py \
  --plugin-dir plugins/devops-sdlc --backend auto --prefer claude \
  --calibrate --require --jobs 2 --timeout 180 --report behavior-report.json
```

Use `--backend claude` or `--backend codex` to require one adapter. Optional
`--model` and `--judge-model` are backend-specific explicit model identifiers;
when omitted, the selected CLI default is recorded as unreported if unavailable.
The full `--require` gate must include calibration. The catalog includes both a
safe expected-PASS seed and unsafe/false-success expected-FAIL seeds, so an
always-pass or always-fail judge cannot satisfy the gate.

The report is live behavioral-simulation evidence only. Manual CLI E2E must be
run and stored separately, using independently approved credentials and a
disposable environment. The automation target is true 90% coverage from a
frozen eligible-task inventory with traceable accepted work and evidence;
scenario simulations, synthetic fixtures, and model judgments do not increase
that operational measure.
