# Prompt-Quality Guardrails — Test Strategy

Scope: a CI guardrail layer that protects the **prompt quality and structural
integrity** of Claude Code plugins under `plugins/*/`. It is a *separate
concern* from — and a *separate PR on top of* — the
`php-backend-sdlc` plugin PR (`feature/php-backend-sdlc-plugin`).

The plugin PR already ships a behavioral QA campaign: 197 `bats` tests over
nine runtime surfaces (scripts, profile fuzz, governance injection, gh
integration, review loop, command/agent semantics, install lifecycle,
security). That campaign answers *"do the scripts and flows behave?"*.

This layer answers a different question: ***"are the prompt artifacts
themselves — commands, agents, skills, meta-guides — well-formed, internally
consistent, free of dead references, generalized, and high enough quality that
Claude routes to and executes them correctly?"*** Markdown prompts have no
compiler; without these checks, a renamed script, a vague skill description, a
leaked `user-service` literal, or a broken `../skill/SKILL.md` link ships
silently.

## Contract sources

Every check traces to a contract. A check that cannot cite one is not added.

| Source | Path | What it pins |
| --- | --- | --- |
| BMAD PRD | `specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md` | FR-1..20, NFR-1..8 |
| BMAD architecture | `…/architecture.md` | Command/agent/skill anatomy (§2/§3/§4), §6 CI, §8 degrade matrix |
| BMAD epics | `…/epics.md` | Per-artifact "Common contract" sections |
| ADRs | architecture.md §ADR | ADR-1..11 invariants |
| Claude Code plugin docs | code.claude.com/docs (plugins, skills, sub-agents) | Frontmatter schema, description→trigger semantics, `${CLAUDE_PLUGIN_ROOT}`, 1536-char description cap, `claude plugin validate` |
| Observed plugin tree | `plugins/php-backend-sdlc/**` | The de-facto structural patterns the plugin already follows uniformly |

A finding is any artifact behavior contradicting a cited contract: a missing
required frontmatter key, a dead reference, a section-spine gap, a denylisted
identifier, a description that would mis-route, a degrade path that loops or
hard-fails. Not findings: stylistic preferences with no contract, the two
meta-guides legitimately lacking frontmatter (ADR-11), `# profile-example`
fenced blocks that intentionally cite user-service values.

## Three check tiers

Checks are layered by cost and determinism. A higher tier never substitutes for
a lower one; they compose.

### Tier 1 — Static lint (deterministic, no network, hard CI gate)

Pure-Python validators over `plugins/*/`. Zero external calls, millisecond
runtime, reproducible. These are the **blocking** gate. Categories:

| Module | Pins | Examples of what it catches |
| --- | --- | --- |
| `frontmatter` | arch §2/§3/§4, plugin docs | command missing `description`/`argument-hint`; agent missing `name`/`description`/`tools`/`model`; SKILL.md missing `name`/`description`; meta-guide that wrongly carries frontmatter (ADR-11) |
| `naming` | arch §6, ADR-11 | agent `name` ≠ filename stem ≠ H1; skill `name` ≠ directory name; `model` outside `{sonnet,opus,haiku,fable,inherit}`; `argument-hint` not a single `[...]` group |
| `descriptions` | plugin docs (1536-char cap), FR-15 | description over the cap; skill/agent description with no trigger clause ("Use when"/"Delegate"/"Use this agent"/"Proactively") |
| `structure` | arch §2/§3, epics E5/E6 | command missing one of the 5-section spine; agent missing one of the 8-section spine; skill missing `## Profile keys consumed` as first H2 |
| `references` | arch §4/§5, readiness F-class | dead `${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh`; dead `../<skill>/SKILL.md` link; `/sdlc-*` with no `commands/*.md`; backticked agent name with no `agents/*.md`; "X skill" with no `skills/X/` dir; profile key not in `docs/profile-schema.md` |
| `escalation` | arch §2, NFR-6 | command `## Iteration guard` / agent `## Iteration discipline` missing `MAX_ITERATIONS=5`; `=== SDLC ESCALATION ===` block missing a canonical field |
| `generalization` | NFR-2 | denylist (`VilnaCRM` outside manifests, `user[-_ ]service`, `Mongo\w*Repository`, `AppRunner`, `src/User`, `src/OAuth`, workspace.dsl containers), with `# profile-example` fences stripped — a Python re-implementation of the ci.yml grep, unit-tested |

Tier 1 ships with a stdlib `unittest` suite: every rule has positive (passes),
negative (fails), and edge cases. The cases are synthetic plugin trees built
inline in `tempfile.mkdtemp()` per test — there is no `fixtures/` directory and
no `pytest` dependency. The validators are tested as code, not just trusted.

### Tier 2 — Manifest validation (deterministic, hard gate where tool present)

`claude plugin validate <plugin> --strict` when the `claude` binary is
available, plus a self-contained Python manifest validator (`plugin.json` /
`marketplace.json` field + semver + source-path checks) as the portable
fallback that always runs. This overlaps the existing `manifest-validate`
ci.yml job intentionally — the Python version is unit-tested and generic over
all `plugins/*`, so it stays correct as plugins are added.

### Tier 3 — LLM-as-judge (non-deterministic, gated, advisory-to-blocking)

Python harness invoking the **Claude CLI** headless:
`claude -p <prompt> --model sonnet --output-format json`, parsing `.result`.
The prompt is passed as a positional **argument** (not on stdin, which trips the
CLI's prompt-injection guard) and the call runs from a **neutral working
directory** so no project `CLAUDE.md`/output-style loads. `--bare` is
deliberately *not* used: it skips the credential store and the CLI reports
"Not logged in" under OAuth/subscription auth. Contamination by ambient
instructions is instead neutralised inside the prompt itself, which frames the
artifact explicitly as **DATA to evaluate, not instructions to obey** — defeating
both ambient style and embedded-instruction hijacking — while still keeping
per-call cost low by judging one artifact per call against a focused rubric.

The judge scores dimensions a regex cannot: trigger specificity of a
description, degrade-path soundness, exit-condition fidelity vs the FR-1 stage
table, profile-key branching completeness, semantic (paraphrased) user-service
leakage, root-cause-culture adherence, docs-vs-code accuracy. One rubric per
artifact type plus a cross-cutting generalization rubric. Output is a strict
JSON verdict (per-dimension 1–5 score + pass/fail + evidence). The verdict is
validated **structurally in Python** by `judge.py`'s `validate_verdict`, which
mirrors the documented contract in `schema/verdict.schema.json` (the schema file
is the human-readable contract; it is not loaded at runtime).

Default model **sonnet** (`claude-sonnet-4-6` via the `sonnet` alias),
overridable with `JUDGE_MODEL`. Verdicts are cached by file-content SHA so
unchanged files are not re-spent across runs.

## Determinism & flakiness control for the judge

LLM judgment is inherently non-deterministic; the harness contains the
flakiness rather than pretending it away:

- **Structured output**: model must emit JSON whose shape `validate_verdict`
  accepts (mirroring `verdict.schema.json`); malformed output triggers up to 2
  reprompts, then the file is marked `ERROR` (not silently passed).
- **Critical vs advisory dimensions**: only a small set of high-confidence
  dimensions (dead-on-arrival trigger text, contradiction with own body,
  semantic generalization leak) can *block*. The rest are advisory scores
  surfaced in the report. This keeps a noisy judge from flapping the gate.
- **Threshold, not vibe**: blocking dimensions fail only below an explicit
  score floor stated in the rubric.
- **Content-hash cache**: same file bytes → same cached verdict, so reruns on
  unchanged files are stable and free.
- **CI gating**: the judge job runs only when Anthropic credentials are present
  (secret in CI, login locally). With no credentials it **skips with an
  explicit message**, never a false green — mirroring the existing ci.yml
  "no files yet — pass" defensive idiom but distinguishing *skipped* from
  *passed* in the job summary.

## Risk-based prioritization

Fix/Block order, highest preempts lower:

1. **Generalization leak (S1)** — a user-service literal or semantic
   leak shipping in a "generalized" plugin (NFR-2). Hard block, both tiers.
2. **Dead reference / broken contract (S2)** — a renamed script, skill, or
   command that prompts still point at; a missing required frontmatter key that
   stops a component loading (FR-19, NFR-1). Hard block.
3. **Structural drift (S2)** — missing section spine, missing
   `MAX_ITERATIONS=5`, malformed escalation block (NFR-6). Hard block.
4. **Quality / routing (S3)** — vague descriptions, weak degrade-path prose,
   exit-condition paraphrase drift. Judge advisory; blocks only on the
   critical-dimension floor.

## Environments

- **CI (GitHub Actions, `ubuntu-latest`)**: Tier 1 + Tier 2 fallback run with
  no network. Tier 2 `claude plugin validate` and Tier 3 judge run only when
  the runner has `claude` + credentials; otherwise skip-with-message.
- **Local**: full suite including Tier 3 against the developer's `claude`
  login. The `./run.sh` entrypoint runs everything (lint + self-tests, plus the
  judge if creds exist); `./run.sh --no-judge` runs only the deterministic
  tiers, and `./run.sh --judge-only` runs only the LLM-judge. Passing both
  flags is rejected (they are mutually exclusive).
- **Self-test**: the validators' own stdlib `unittest` suite lives under
  `tools/plugin-quality/tests/` and builds synthetic good/bad plugin trees inline
  in `tempfile.mkdtemp()` (no `fixtures/` directory), never the real plugin, so
  the suite is hermetic.

## Severity

| Severity | Definition | Tier / gate |
| --- | --- | --- |
| S1 | Generalization leak; manifest invalid so plugin won't install | T1/T2/T3, hard block |
| S2 | Dead reference; missing required frontmatter; missing section spine; missing loop guard | T1, hard block |
| S3 | Mis-routing-risk description; weak/looping degrade prose; exit-condition drift | T3 critical floor blocks; else advisory |
| S4 | Stylistic inconsistency (mixed scalar style, optional-key variance) | Reported, never blocks |

## Entry criteria

- `feature/plugin-ci-guardrails` branched from `feature/php-backend-sdlc-plugin`.
- `claude` CLI ≥ 2.1 and `python3` ≥ 3.10 available locally.
- Plugin tree present at `plugins/php-backend-sdlc/`.

## Exit criteria

- Tier 1 lint + its `unittest` suite green over `plugins/*/`.
- Tier 2 manifest validation green.
- Tier 3 judge executed over all command/agent/skill/meta-guide files;
  every blocking-dimension verdict PASS or the finding fixed (in this PR if the
  fix is to the *guardrail*, recorded as a cross-PR finding if the fix belongs
  to the plugin itself).
- `prompt-quality.yml` green on the PR (judge job either passing or
  cleanly skipped-with-message when CI lacks credentials).
- New PR opened with base `feature/php-backend-sdlc-plugin`, all checks green,
  zero unresolved review comments.

## Loop protocol

Per round until exit criteria hold:

1. **Generate/refresh** the check matrix from the FR/NFR catalog (`test-plan.md`).
2. **Build/extend** a validator or rubric for any uncovered contract.
3. **Run** all three tiers; capture pass/fail per check.
4. **Judge** each deviation: real finding (reproduce twice / majority skeptic
   vote for judge findings), tool bug (fix the validator), or contract
   ambiguity (record, default to the stricter reading).
5. **Fix** at root cause — the validator or the rubric, never by weakening a
   threshold to pass. Plugin-artifact fixes are recorded as cross-PR findings.
6. **Regress** — add a fixture (Tier 1/2) or a calibration example (Tier 3).
7. **Repeat** until a full round adds zero new findings.
