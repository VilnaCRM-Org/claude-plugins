# plugin-quality

Prompt-quality guardrails for Claude Code plugins under `plugins/*/`. A separate
concern from `ci.yml` (which gates the plugin's runtime surfaces): this toolkit
gates the **prompt quality and structural integrity** of the prompt artifacts
themselves — commands, agents, skills, and meta-guides.

Markdown prompts have no compiler. Without these checks a renamed script, a
vague skill description, a leaked source-project literal, or a broken
`../skill/SKILL.md` link ships silently. This toolkit catches those.

## Layout

```
tools/plugin-quality/
  docs/        test-strategy.md, test-plan.md (check matrix), test-cases.md
  lint/        Tier-1 static validators (deterministic, no network)
               _common.py  Finding dataclass + reporting
               _model.py   artifact discovery + frontmatter/section parsing
               check_*.py   one module per check family (frontmatter, naming,
                            descriptions, structure, references, escalation,
                            generalization, manifest)
               lint_all.py  aggregator + CLI
  judge/       Tier-3 LLM-as-judge (Claude CLI, sonnet)
               rubrics.py   dimension registry (guidance + thresholds, J1..J11)
               judge.py     engine: build prompt -> claude -p -> parse + gate
               cache.py     content-addressed verdict cache
               run_judge.py CLI runner
  schema/      verdict.schema.json
  tests/       stdlib unittest suite (validators + claude-free judge engine)
```

## Dependencies

Bare `python3` (>= 3.10) plus **PyYAML** — that's it. Self-tests use the stdlib
`unittest` runner, so no `pip install` is required to run the deterministic gate.
The LLM-judge additionally needs the `claude` CLI and Anthropic credentials.

## Running

```bash
# Tier 1 — static lint (deterministic, gates CI)
python3 lint/lint_all.py                  # all plugins
python3 lint/lint_all.py --json           # machine-readable
python3 lint/lint_all.py plugins/php-backend-sdlc

# Self-tests (validators + judge engine, no network)
python3 -m unittest discover -s tests

# Tier 3 — LLM-as-judge (needs claude CLI + creds)
python3 judge/run_judge.py --gate --jobs 6 --report judge-report.md
python3 judge/run_judge.py plugins/php-backend-sdlc/skills/code-review/SKILL.md
JUDGE_MODEL=sonnet python3 judge/run_judge.py --votes 3 --gate   # robust gate

# Everything at once
./run.sh                                   # lint + selftest (+ judge if creds)
```

## Gating model

| Tier | Determinism | CI gate |
| --- | --- | --- |
| 1 static lint | deterministic | **blocks** (severity S1/S2/S3) |
| 1 self-tests | deterministic | **blocks** |
| 2 `claude plugin validate` | deterministic | blocks when the CLI is present AND authenticated; otherwise skip-with-message (on CI `claude plugin validate` is auth-gated and skips) |
| 3 LLM-judge | non-deterministic | runs only with creds; **blocks** only a *critical* dimension scoring ≤ 2 (`block_floor`); everything below the floor (4) is advisory |

The judge never produces a false green: with no `claude` CLI / no
`ANTHROPIC_API_KEY` it **skips with an explicit message**, and an unjudgeable
artifact under `--gate` fails rather than passing silently.

See `docs/test-strategy.md` for the full approach and `docs/test-plan.md` for
the check-to-requirement matrix (mapped to the BMAD FR/NFR catalog).
