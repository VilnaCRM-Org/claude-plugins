# Prompt-Quality Guardrails — Test Cases

Concrete positive / negative / edge cases per check ID from `test-plan.md`.
Tier-1/2 cases are exercised by the stdlib `unittest` suite under `tests/`,
which builds each case as a synthetic plugin tree inline in
`tempfile.mkdtemp()` per test — there is no `tests/fixtures/` directory and no
`pytest` dependency. Tier-3 cases are the known-good / known-bad calibration
artifacts embedded in each CRITICAL rubric and exercised on demand by
`run_judge.py --selftest` (see "Self-test gates" below).

Convention: **P** positive (must PASS), **N** negative (must FAIL with a
specific message), **E** edge (boundary that must be classified correctly).

## Tier 1 — frontmatter

**FM-1 (L1) command description+argument-hint**
- P: `---\ndescription: "Run X"\nargument-hint: "[pr-number]"\n---`
- N: command with no `argument-hint` → fail "missing frontmatter key argument-hint"
- N: command with empty `description: ""` → fail
- E: `allowed-tools` present alongside both required keys → still PASS

**FM-2 (L2) command allowed-tools shape**
- P: `allowed-tools: ["Bash","Read","Grep"]`
- N: `allowed-tools: Bash, Read` (bare list — agent shape) → fail "allowed-tools must be a JSON array"
- N: report-only command (body says "never fix"/"report only") with `"Write"` in allowed-tools → fail
- E: command without `allowed-tools` at all → PASS (optional)

**FM-3 (L3) agent four keys**
- P: all of name/description/tools/model present
- N: missing `model` → fail
- E: `tools` as YAML list vs comma string → both PASS (accept both shapes)

**FM-4 (L4) skill two keys, no tools/model**
- P: `name` + `description` only
- N: SKILL.md with `model: sonnet` → fail "skill must not declare model"
- E: `when_to_use` present → PASS (allowed optional)

**FM-5 (L5) meta-guide no frontmatter**
- P: `skills/AI-AGENT-GUIDE.md` starting with `# Heading`
- N: a `skills/FOO.md` starting with `---` → fail "meta-guide must not have frontmatter (ADR-11)"
- E: `skills/<dir>/SKILL.md` is NOT a meta-guide (in a subdir) → not checked by this rule

**FM-6 (L33) qa command/agent must not allow mutating tools** (FR-7/FR-12)
- P: `commands/sdlc-qa.md` with `allowed-tools: ["Bash","Read"]` → no finding
- P: `agents/qa-manual-tester.md` with `tools: Bash, Read` → no finding
- N: a qa-named agent (`name` matches `(^|-)qa(-|$)`) whose `tools` include `Write` → fail "qa … must not allow mutating tools" (regardless of body phrasing)
- N: a qa command whose `allowed-tools` include `Edit` → fail
- E: a non-qa command listing `Write` → not flagged by L33 (only the body-phrasing rule L2 applies)

## Tier 1 — naming

**NM-1 (L6) agent name==stem==H1**
- P: `agents/ci-fixer.md`, `name: ci-fixer`, H1 `# ci-fixer`
- N: `name: cifixer` in `ci-fixer.md` → fail
- N: H1 `# CI Fixer` ≠ name → fail
- E: H1 with trailing description after a dash → compare only leading token

**NM-2 (L7) skill name==dir**
- P: `skills/deptrac-fixer/SKILL.md` name `deptrac-fixer`
- N: name `deptracfixer` → fail
- E: skill H1 is Title Case ("# Deptrac Fixer Skill") → do NOT compare to name

**NM-3 (L8) model enum**
- P: `model: opus` / `model: sonnet`
- N: `model: gpt-4` → fail
- E: `model: inherit` and `model: haiku` → PASS

**NM-4 (L9) argument-hint shape**
- P: `"[task-description | issue-URL]"`, `"[--refresh]"`
- N: `"pr-number"` (no brackets) → fail
- E: `"[a] [b]"` two groups → policy: PASS (plugin docs allow multiple positional hints); document the decision

**NM-5 (L10) kebab-case names**
- P: `pr-comment-resolver`
- N: `PR_Comment_Resolver` → fail
- E: digits allowed `bmad-fr-nfr-review-gate`

## Tier 1 — descriptions

**DS-1 (L11) 1536-char cap** — P: 300-char desc · N: 1600-char desc → fail · E: exactly 1536 → PASS; desc+when_to_use summed crosses cap → fail
**DS-2 (L12) skill trigger clause** — P: "...Use when adding..." · N: "Implements CRUD." (no trigger) → fail · E: "When to use this skill: ..." → PASS
**DS-3 (L13) agent delegation trigger** — P: "Delegate to this agent when..." · N: "Code reviewer." → fail · E: "Proactively reviews..." → PASS
**DS-4 (L14) non-empty ≥20 chars** — P: normal · N: `description: "x"` → fail · E: exactly 20 chars → PASS

## Tier 1 — structure

**ST-1 (L15) command 5-spine** — P: all five H2 present · N: missing `## Loop & exit condition` → fail · E: extra H2s (report template) → PASS
**ST-2 (L16) agent 8-spine** — P: all eight · N: missing `## Smoke prompt` → fail · E: order differs (fr-nfr-reviewer Role-first) → PASS (presence not order)
**ST-3 (L17) skill first H2 profile-keys** — P: first H2 `## Profile keys consumed` · N: first H2 `## Overview` → fail · E: meta-guides excluded
**ST-4 (L18) gated skill skip path** — P (literal token): `## Capability gate` + `SKIPPED: capabilities.x is false` · P (prose note tied to a predicate): gate section that says "skip when `capabilities.load_testing` is false" → PASS · N: gate section that documents NO skip path — neither a `SKIPPED:` token nor a prose skip-note tied to a `capabilities.`/`framework.`/`persistence.` predicate → fail · E: non-gated skill (no gate section) → not checked

## Tier 1 — references

**RF-1 (L19) script path** — P: `${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh` (exists) · N: `.../validate-profle.sh` → fail · E: path in a comment still checked
**RF-2 (L20) skill path** — P: `${CLAUDE_PLUGIN_ROOT}/skills/code-review/SKILL.md` · N: `.../skills/code-revew/SKILL.md` → fail · E: glob `.../skills/*/SKILL.md` → exempt
**RF-3 (L21) relative links** — P: `[x](../testing-workflow/SKILL.md)` · N: `[x](../testing-worklow/SKILL.md)` → fail · E: `[x](reference/configuration.md)` resolved relative to linking file's dir
**RF-4 (L22) command refs** — P: `/sdlc-finish-pr` (file exists) · N: `/sdlc-finsh-pr` → fail · E: `/sdlc` must not shadow `/sdlc-plan` (longest match)
**RF-5 (L23) agent refs** — P: `` `code-quality-reviewer` `` · N: `` `code-quality-reviwer` `` → fail · E: agent name inside a fenced code block referencing a real agent → still resolves
**RF-6 (L24) skill refs** — P: "testing-workflow skill" · N: "testng-workflow skill" → fail · E: a generic English word that is not a skill name → not flagged (only check explicit "<name> skill"/backticked dir-like tokens)
**RF-7 (L25) profile keys** — P: `make.psalm` in schema · N: `make.pslam` → fail · E: `make.*` wildcard exempt; `quality.phpinsights.complexity` nested key resolved

## Tier 1 — escalation

**ES-1 (L26) MAX_ITERATIONS=5** — P: `MAX_ITERATIONS=5` in guard section · N: `MAX_ITERATIONS=3` → fail · E: prose "max 5 iterations" normalized to PASS
**ES-2 (L27) escalation block fields** — P: block with all 7 fields · N: block missing `recommended_action:` → fail · E: orchestrator `=== SDLC RUN REPORT ===` → exempt from the 7-field check

## Tier 1 — generalization

**GN-1 (L28) denylist** — P: clean skill · N: skill body containing `MongoUserRepository` → fail · N: `user-service` in prose → fail · E: `user-service` inside a ```bash # profile-example fence → PASS (stripped); README/marketplace `VilnaCRM` org link → exempt path
**GN-2 (L29) tree hygiene** — P: no such dirs · N: a `plugins/x/_bmad/` dir → fail · E: `_bmad` substring inside a filename (not a dir) → not flagged

## Tier 1 — meta-guides

**MG-1 (L30) decision-guide triage clause** (FR-16) — P: a `skills/*DECISION*.md` meta-guide whose body contains the BMAD "no silent skips / every skill verdict recorded" triage clause → no finding · N: a `skills/MY-DECISION-GUIDE.md` lacking the clause → fail "decision guide must state the … triage clause" · E: a non-decision meta-guide (`AI-AGENT-GUIDE.md`) → not checked by this rule

## Tier 2 — manifest

**MF-1 (M1) plugin.json fields** — P: full manifest · N: missing `license` → fail · E: extra unknown field → PASS (warn only, unless strict)
**MF-2 (M2) semver** — P: `0.1.0` · N: `0.1` → fail · E: `1.0.0-rc.1` → policy PASS (prerelease allowed) — document
**MF-3 (M3) name==dir** — P: dir `php-backend-sdlc` name matches · N: mismatch → fail
**MF-4 (M4) marketplace** — P: entry source `./plugins/php-backend-sdlc` + dir exists · N: source `./plugins/wrong` → fail · E: multiple plugins all validated
**MF-5 (M5) claude plugin validate** — P: real plugin passes `--strict` · N: corrupt manifest fails · E: `claude` absent → skip-with-message (job neither passes silently nor false-fails)

## Tier 3 — judge calibration (each CRITICAL rubric ships one P and one N artifact)

Calibration artifacts ship for the CRITICAL dimensions only — **J1, J2, J3,
J7, J10** (the dimensions that can block CI). Each ships one known-good (P) and
one known-bad (N) artifact. `run_judge.py --selftest` runs them through the
live judge and asserts P scores `>= floor` (4) and N scores `<= block_floor`
(2) for the crit dimension. It needs `claude` credentials, costs API, and is
**on demand** — it is NOT part of the no-credential CI path. The advisory rows
below (JD-4/5/6/8/9/11) document expected judge behavior but are not gated by
the self-test.

**JD-1 trigger specificity** — P (skill): "Create REST CRUD with API Platform. Use when adding API resources... Skip when `framework.api_platform` is false." · N: "Helps with APIs." → low score, FAIL crit floor
**JD-2 body↔description fidelity** — P: description matches body scope · N: description promises caching but body says "this skill does NOT cover caching" → FAIL (self-contradiction)
**JD-3 degrade-path soundness** — P: "no CodeRabbit → fall back to `ai-review-loop.sh`, report, do not loop" · N: "if no CI, retry until checks appear" (loops) → FAIL crit
**JD-4 exit-condition fidelity** — P: command exit condition paraphrases FR-1 row faithfully · N: command claims a different exit condition than the stage table → low score (advisory)
**JD-5 loop/escalation soundness** — P: counter restated each turn, never reset · N: "reset the breaker and retry" → low score
**JD-6 profile-key branching** — P: database-migrations has both ORM-migration and ODM-schema branches · N: lists `persistence.mapper` but only documents ORM → low score
**JD-7 semantic generalization leak** — P: generic "the configured repository" · N: "the Mongo-backed repository that stores users" (no literal `Mongo<Name>Repository`, denylist misses it) → FAIL crit
**JD-8 root-cause culture** — P: "never suppress; fix the cause" · N: "if the check is noisy, add a baseline entry" → low score
**JD-9 QA black-box** — P: "derive verdicts only from HTTP responses; never read src/" · N: "inspect the handler to confirm" → low score
**JD-10 meta-guide inventory** — P: guide lists exactly the 21 shipped skills · N: guide lists 20 / lists a removed skill → FAIL crit
**JD-11 instruction unambiguity** — P: single-reading steps · N: "validate the profile or skip if needed" (ambiguous) → low score

## Self-test gates

- Tier 1/2 validators: the stdlib `unittest` suite (`python3 -m unittest
  discover -s tests`) must show every P case PASS and every N case FAIL with
  the expected message substring; edge cases classified per the documented
  policy. Each case is a synthetic plugin tree built inline in
  `tempfile.mkdtemp()` — no `tests/fixtures/` directory, no `pytest`. This
  suite is deterministic and runs in the no-credential CI path.
- Tier 3 rubrics: `run_judge.py --selftest` runs each CRITICAL rubric's
  embedded P/N calibration artifacts (J1, J2, J3, J7, J10) through the live
  judge and asserts P scores ≥ floor (4) and N scores ≤ block_floor (2) for the
  crit dimension. It requires `claude` credentials, costs API, and is run on
  demand — NOT in the no-credential CI path.
