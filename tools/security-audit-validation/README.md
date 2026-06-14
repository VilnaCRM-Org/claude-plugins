# security-audit validation campaign

Validates that the `php-backend-sdlc` plugin's **`security-audit` skill** and
**`security-auditor` agent** actually detect the vulnerabilities they claim to
cover, stay silent on secure code, and degrade as documented. This is the
executable side of the campaign; the strategy/plan/cases live in
[`plugins/php-backend-sdlc/docs/testing/security-audit-test-*.md`](../../plugins/php-backend-sdlc/docs/testing/).

It is **test scaffolding**, not shipped plugin content — the deliberately
vulnerable PHP fixtures live here, outside the plugin tree, so they never reach
a consumer of the plugin.

## Layout

| Path | Purpose |
| --- | --- |
| `corpus/<family>/` | PHP fixtures: `vulnerable.php` (TP), `clean.php` (TN), `edge_*.php` |
| `corpus/deps/*.composer.json` | dependency fixtures (FR-7 in-tree demonstration) |
| `corpus.py` | the manifest — every fixture + its expected static/judge verdict |
| `rules/security-audit.yml` | the local semgrep rule pack (the static lane) |
| `detect.py` | static + dep detection harness; asserts TP/TN per fixture |
| `judge/run_seed_judge.py` | LLM-as-judge behavioral lane (`claude` sonnet) |
| `tests/` | stdlib `unittest` suite (100% coverage of the harness) |

## Two lanes

**Static lane** (deterministic, CI-gating):

```bash
python3 tools/security-audit-validation/detect.py        # 0 = all TP/TN hold
```

Runs the semgrep rule pack over the corpus and asserts each `finding` fixture is
flagged by its own family's rule and each `clean` fixture is flagged by none.
Exit 2 if semgrep is unavailable (never a silent green).

> On hosts with a low `RLIMIT_MEMLOCK`, semgrep's default multi-worker core can
> fail at startup with `io_uring_queue_init: Cannot allocate memory`. The
> harness invokes semgrep with `-j 1` (legacy single worker) to avoid this; CI
> runners are unaffected.

**Judge lane** (bounded nondeterminism, skip-clean without the CLI):

```bash
python3 tools/security-audit-validation/judge/run_seed_judge.py --votes 3 --gate
```

Asks `claude -p --model sonnet` to act under the `security-auditor` verdict
contract on each fixture and compares the majority verdict to the recorded
expectation — covering the logic families (BOLA/IDOR, BFLA, BOPLA, auth, rate)
that no static rule can decide. Skips with exit 0 when the `claude` CLI is
absent, so a credential-less CI run stays green.

## Tests + lint (mirrors python-quality)

```bash
python3 -m unittest discover -s tools/security-audit-validation/tests \
  -t tools/security-audit-validation
uvx ruff@0.15.6 check tools/security-audit-validation
uvx coverage@7.6.7 run --source=tools/security-audit-validation --omit='*/tests/*' \
  -m unittest discover -s tools/security-audit-validation/tests \
  -t tools/security-audit-validation && uvx coverage@7.6.7 report --fail-under=100
```

## Adding a fixture (a new "vulnerable PR")

1. Drop the PHP under `corpus/<family>/`.
2. Add a `Fixture(...)` row to `corpus.py` with its `static_expect` /
   `judge_expect`.
3. If the static lane should catch it, ensure a rule in
   `rules/security-audit.yml` fires (or add one).
4. Run `detect.py`; a false negative/positive fails the gate until the rule or
   the fixture is corrected.
