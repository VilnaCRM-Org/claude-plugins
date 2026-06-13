# Prompt-Quality Guardrails — Test Cases

Concrete positive / negative / edge cases per check ID from `test-plan.md`.
Tier-1/2 cases become `pytest` fixtures under `tests/fixtures/`; Tier-3 cases
become calibration examples embedded in each rubric (a known-good and
known-bad artifact the judge must score correctly during rubric self-test).

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
**ST-4 (L18) gated skill SKIPPED token** — P: `## Capability gate` + `SKIPPED: capabilities.x is false` · N: gate section, no SKIPPED token → fail · E: non-gated skill (no gate section) → not checked

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

## Tier 2 — manifest

**MF-1 (M1) plugin.json fields** — P: full manifest · N: missing `license` → fail · E: extra unknown field → PASS (warn only, unless strict)
**MF-2 (M2) semver** — P: `0.1.0` · N: `0.1` → fail · E: `1.0.0-rc.1` → policy PASS (prerelease allowed) — document
**MF-3 (M3) name==dir** — P: dir `php-backend-sdlc` name matches · N: mismatch → fail
**MF-4 (M4) marketplace** — P: entry source `./plugins/php-backend-sdlc` + dir exists · N: source `./plugins/wrong` → fail · E: multiple plugins all validated
**MF-5 (M5) claude plugin validate** — P: real plugin passes `--strict` · N: corrupt manifest fails · E: `claude` absent → skip-with-message (job neither passes silently nor false-fails)

## Tier 3 — judge calibration (each rubric ships one P and one N artifact)

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

- Tier 1/2 validators: `pytest` must show every P fixture PASS and every N
  fixture FAIL with the expected message substring; edge fixtures classified
  per the documented policy.
- Tier 3 rubrics: a `--selftest` mode runs the embedded P/N calibration
  artifacts through the live judge and asserts P scores ≥ floor and N scores <
  floor for the crit dimensions. Run on demand (costs API), not in the
  no-credential CI path.
