# Test Plan — `security-audit` skill validation campaign

Operationalizes [`security-audit-test-strategy.md`](security-audit-test-strategy.md):
what is executed, with which tooling, and how each result is judged pass/fail.
The executable side lives under `tools/security-audit-validation/`.

## Test items

| Item | Artifact under test | How exercised |
| --- | --- | --- |
| TI-1 Static signatures | `security-auditor` SAST pass (semgrep lane) | `detect.py` runs `rules/security-audit.yml` over the corpus, compares hits to `corpus.py` expectations |
| TI-2 Judge verdicts | `security-auditor` reasoning under its contract | `judge/run_seed_judge.py` feeds each fixture + the auditor contract to `claude -p sonnet`, parses the FINDING/CLEAN verdict |
| TI-3 Dep demonstration | FR-7 in-tree dep promotion | `detect.py` dep-lane asserts the pinned version sits in the recorded vulnerable range and the clean pin does not |
| TI-4 N/A discipline | catalog N/A-with-reason rows | judge lane asserts the auditor returns N/A (never a fabricated finding) for an out-of-scope fixture |
| TI-5 Degrade soundness | skill/agent degrade paths | static assertions over the contract text (each degrade path terminates in a reported outcome) |

## Test approach per lane

### Static lane (TI-1, TI-3) — deterministic, CI-gating

1. `detect.py` discovers every fixture declared in `corpus.py`.
2. For each, it runs `semgrep --config rules/security-audit.yml --json <fixture>`
   (offline, no rules registry fetch).
3. It maps semgrep `results[].check_id` back to the family and compares the hit
   set to the fixture's `expect` field:
   - `expect="finding"` → at least one rule of the fixture's family fired;
   - `expect="clean"` → **no** rule fired on that file.
4. Mismatches are reported as `FALSE NEGATIVE` / `FALSE POSITIVE` with the
   file, family, and the rule that should have/should not have fired. Any
   mismatch exits non-zero (CI hard-fail).
5. The dep lane (TI-3) reads the fixture `composer.json` pins and asserts the
   vulnerable pin ∈ recorded CVE range and the clean pin ∉ it.

The run/compare split is deliberate: `_compare_results()` is a pure function
(semgrep JSON + expectations → verdict list) unit-tested with synthetic JSON, so
the gate logic is fully covered without semgrep installed; the thin
`_run_semgrep()` subprocess wrapper is covered via a monkeypatched runner. This
mirrors the prompt-quality judge's pure-core / thin-shell split.

### Judge lane (TI-2, TI-4) — bounded nondeterminism, skip-clean

1. `run_seed_judge.py` builds a prompt: the `security-auditor` boundary +
   verdict contract, the fixture source, and the family methodology excerpt.
2. It calls `claude -p --model sonnet` (arg-form, neutral cwd — the
   prompt-quality auth-safe convention), N votes (default 3), median verdict.
3. The verdict is parsed from a constrained JSON envelope
   (`{"verdict":"FINDING|CLEAN|NA","cwe":"...","why":"<=240 chars"}`).
4. PASS when the median verdict equals the fixture's `judge_expect`.
5. **No CLI → SKIP with message, exit 0** (never a false green), unless
   `--require` is passed. This keeps the credential-less CI runner green while
   still letting a developer with the CLI run the behavioral lane locally.

### Degrade-soundness lane (TI-5) — static contract assertions

A small unittest reads `SKILL.md` + `security-auditor.md` and asserts each named
degrade path resolves to an explicit reported outcome (CLEAN | FINDINGS | N/A |
SKIPPED | ESCALATED) and never the words "retry until" without a bound. This is
deterministic and CI-gating.

## Pass / fail criteria

| Lane | Pass | Fail |
| --- | --- | --- |
| Static (TI-1) | every fixture's actual hit set matches `expect` | any FN/FP |
| Dep (TI-3) | vulnerable pin in range, clean pin out | either pin misclassified |
| Judge (TI-2/TI-4) | median verdict == `judge_expect` for every fixture (CLI present) | any mismatch; SKIP when CLI absent is **not** a fail |
| Degrade (TI-5) | every degrade path terminates in a reported outcome | any unbounded/again-loop or undefined path |

## CI wiring

A new workflow `security-audit-validation.yml`:

- `static` job: install `semgrep` (pinned via `uvx`), run `detect.py` over the
  corpus → gates on TP/TN/dep.
- `unit` job: `coverage run -m unittest` over `tools/security-audit-validation/tests`
  with `--source=tools/security-audit-validation`, `--fail-under=100`.
- `ruff` step: `ruff check` + `format --check` over the new dir (added to the
  pyproject `include`).
- `judge` job: runs `run_seed_judge.py`; **skips clean** without the CLI so the
  default runner stays green; documented as the lane a credentialed run
  exercises.

Existing `python-quality.yml` (scoped to `tools/plugin-quality`) and `ci.yml`
are untouched and stay green.

## Schedule / rounds

Round 0 is the authored baseline corpus (this PR). Rounds 1..N are
subagent-generated adversarial fixtures (the loop protocol in the strategy).
Each round appends evidence; the campaign exits when a round adds zero confirmed
gaps.

## Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| A fixture secret trips GitHub push protection / repo secret scanners | Use obviously-fake, non-provider-format literals (`FAKE-...`) that match a *structural* `$key = "literal"` pattern but no real provider regex |
| semgrep version drift changes a `check_id` | Pin semgrep in CI; rules are local (`--config` file), no registry fetch |
| Judge nondeterminism flakes the gate | Odd N-vote median (3); judge lane is skip-clean in CI, authoritative only on a credentialed run |
| Coverage-100 pressure on subprocess code | Pure-core / thin-shell split; subprocess wrappers covered via monkeypatch |
