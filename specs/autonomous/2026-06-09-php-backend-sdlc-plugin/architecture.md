---
stepsCompleted: [step-01-init, step-02-context, step-03-starter, step-04-decisions, step-05-patterns, step-06-structure, step-07-validation, step-08-complete]
inputDocuments:
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/research.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md
workflowType: 'architecture'
date: 2026-06-10
author: Winston (BMAD architect agent, autonomous run — interactive steps skipped, decisions recorded as ADRs)
---

# Architecture — `php-backend-sdlc` Claude Code Plugin

The deliverable is a **Claude Code plugin**: markdown commands/agents/skills + pure-bash scripts + JSON manifests. Architecture follows plugin idioms (auto-discovered component dirs, `${CLAUDE_PLUGIN_ROOT}` script invocation, frontmatter contracts) — not PHP service patterns. Conventions verified against installed plugins: superpowers 5.1.0 (skills/hooks/scripts layout, `hooks/hooks.json` → `${CLAUDE_PLUGIN_ROOT}` script), pr-review-toolkit (`commands/*.md` with `description`/`argument-hint`/`allowed-tools`, `agents/*.md` with `name`/`description`/`model`), feature-dev (`tools:` comma-list in agent frontmatter).

## 1. Component Architecture

### 1.1 File tree (complete)

```
plugins/php-backend-sdlc/
├── .claude-plugin/
│   └── plugin.json                      # name/version/description/author/homepage/repository/license/keywords
├── commands/                            # 8 thin orchestrators (FR-1..8)
│   ├── sdlc.md                          # end-to-end loop, stage gating, resumability
│   ├── sdlc-setup.md                    # preflight + profile + governance + permissions
│   ├── sdlc-issue.md                    # task text → gh issue (or adopt URL)
│   ├── sdlc-plan.md                     # BMAD chain via bmad-autonomous-planning skill
│   ├── sdlc-implement.md                # bmalph implement + run --driver claude-code
│   ├── sdlc-review.md                   # 21-skill triage + multi-lens review + FR/NFR gate loop
│   ├── sdlc-qa.md                       # black-box QA via qa-manual-tester
│   └── sdlc-finish-pr.md                # PR + ci-fixer loop + pr-comment-resolver loop
├── agents/                              # 6 subagents (FR-9..14)
│   ├── php-implementer.md
│   ├── code-quality-reviewer.md
│   ├── fr-nfr-reviewer.md
│   ├── qa-manual-tester.md
│   ├── ci-fixer.md
│   └── pr-comment-resolver.md
├── skills/                              # 21 skills (FR-15) + 2 meta-guides (FR-16)
│   ├── SKILL-DECISION-GUIDE.md          # triage decision tree (loose file: preserves ../ links)
│   ├── AI-AGENT-GUIDE.md                # cross-agent usage guide
│   ├── api-platform-crud/SKILL.md
│   ├── bmad-autonomous-planning/SKILL.md
│   ├── bmad-fr-nfr-review-gate/SKILL.md
│   ├── cache-management/SKILL.md        (+ examples/ carried over, generalized)
│   ├── ci-workflow/SKILL.md
│   ├── clean-architecture-llm/SKILL.md
│   ├── code-organization/SKILL.md       (+ DIRECTORY-STRUCTURE.md, generalized)
│   ├── code-review/SKILL.md
│   ├── complexity-management/SKILL.md
│   ├── database-migrations/SKILL.md
│   ├── deptrac-fixer/SKILL.md
│   ├── documentation-creation/SKILL.md
│   ├── documentation-sync/SKILL.md
│   ├── implementing-ddd-architecture/SKILL.md  (+ REFERENCE.md, generalized)
│   ├── load-testing/SKILL.md            (+ reference/, generalized)
│   ├── observability-instrumentation/SKILL.md
│   ├── openapi-development/SKILL.md
│   ├── quality-standards/SKILL.md
│   ├── query-performance-analysis/SKILL.md
│   ├── structurizr-architecture-sync/SKILL.md
│   └── testing-workflow/SKILL.md
├── scripts/                             # pure bash, shellcheck-clean, bats-covered
│   ├── lib/common.sh                    # logging, profile read helpers, yq/python fallback
│   ├── setup-preflight.sh               # version floors, gh auth, git repo check
│   ├── generate-profile.sh              # detect → write .claude/php-sdlc.yml
│   ├── validate-profile.sh              # schema validation (ADR-2)
│   ├── inject-governance.sh             # managed blocks in CLAUDE.md/AGENTS.md (ADR-3)
│   ├── ai-review-loop.sh                # claude-driver review loop (ADR-8)
│   ├── get-pr-comments.sh               # gh GraphQL, resolution-aware
│   └── fr-nfr-gate.sh                   # FR/NFR gate: PR comment + commit status
├── tests/                               # bats suites, one file per script + layout asserts
│   ├── setup-preflight.bats
│   ├── generate-profile.bats
│   ├── validate-profile.bats
│   ├── inject-governance.bats
│   ├── ai-review-loop.bats
│   ├── get-pr-comments.bats
│   ├── fr-nfr-gate.bats
│   ├── component-counts.bats            # NFR-1: assert 8 commands / 6 agents / 21 skills
│   └── fixtures/                        # stub repo, stub claude/gh binaries, sample profiles
├── docs/
│   ├── profile-schema.md                # FR-17 reference, required/optional, annotated example
│   ├── sdlc-loop.md                     # stage diagram, exit conditions, guards (§7 source)
│   ├── permissions.md                   # acceptEdits default, bypassPermissions Ralph-only
│   ├── degrade-matrix.md                # §8 rendered for users
│   ├── release-process.md               # ADR-9 policy, changelog discipline
│   └── evidence/g3-reference-run.md     # FR-1 evidence run log
└── README.md                            # install, quickstart, links into docs/

Repo root (marketplace):
├── .claude-plugin/marketplace.json      # relative source ./plugins/php-backend-sdlc (ADR-9)
└── .github/workflows/ci.yml             # §6 jobs
```

### 1.2 Dependency direction (strict, CI-checkable)

```
commands  ──►  agents (Task tool)  ──►  skills (load on EXECUTE verdict)
commands  ──►  skills (direct load: bmad-autonomous-planning, decision guide)
commands/agents  ──►  scripts (Bash via ${CLAUDE_PLUGIN_ROOT}/scripts/…)
skills    ──►  .claude/php-sdlc.yml (runtime read) + sibling skills (relative links only)
scripts   ──►  nothing in the plugin except scripts/lib/common.sh; external: bash, git, gh, jq, claude CLI
```

Forbidden edges: skills never invoke agents or commands; scripts never read SKILL.md files; agents never invoke commands. Profile is the only shared state between skills and scripts.

## 2. Command Anatomy

Frontmatter (verified convention, pr-review-toolkit/feature-dev):

```markdown
---
description: "One-line imperative summary shown in /help"
argument-hint: "[task-description | issue-URL]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]   # only where constrained; omit on /sdlc (needs all)
---
```

`allowed-tools` is set on `sdlc-qa.md` (no Edit/Write — black-box rule) and `sdlc-review.md` (no Write); other commands omit it. Body pattern — every command states the same **stage contract** in fixed sections:

1. **Inputs** — required artifacts/arguments and where to find them (issue URL, `specs/<slug>/`, profile path); first action is always `validate-profile.sh` (except `/sdlc-setup` itself).
2. **Procedure** — numbered steps; delegation points name the agent/skill/script explicitly.
3. **Loop & exit condition** — what is re-checked each iteration; the single measurable exit condition from FR-1's stage table.
4. **Iteration guard** — `MAX_ITERATIONS=5`; the command keeps an explicit counter in its scratch state and re-states it in every loop turn.
5. **Failure escalation** — on guard breach / breaker trip, emit the canonical report and stop:

```
=== SDLC ESCALATION ===
stage: <name>            iteration: <n>/5
exit_condition: <text>   status: NOT MET
blocking_finding: <one line>
iteration_log: <one line per iteration>
recommended_action: <human next step>
=== END ===
```

`/sdlc` itself adds: stage-detection table for resumability (artifact → stage mapping), gate checks between stages, and the final run report (SUCCESS | ESCALATED). It never auto-generates a profile (halt → "run /sdlc-setup") and never resets Ralph's circuit breaker.

## 3. Agent Anatomy

Frontmatter (verified convention):

```markdown
---
name: php-implementer
description: <when-to-use prose, trigger scenarios — this is the router text>
tools: Read, Write, Edit, Glob, Grep, Bash       # comma-separated string
model: sonnet                                     # opus only where judgment-heavy
---
```

System-prompt body — six mandatory sections per FR-9..14 AC: **Role**, **Inputs**, **Outputs**, **Allowed actions** (mirrors `tools`), **Degrade paths**, **Iteration discipline** (own counter ≤5, escalation format from §2). Per-agent matrix:

| Agent | model | tools | Notes |
|---|---|---|---|
| php-implementer | sonnet | Read, Write, Edit, Glob, Grep, Bash | container-only `make`/`docker compose exec php`; emits `---RALPH_STATUS---` block |
| code-quality-reviewer | opus | Read, Glob, Grep, Bash | read-only quality `make` targets; never proposes suppressions/threshold cuts |
| fr-nfr-reviewer | opus | Read, Glob, Grep, Bash | runs `fr-nfr-gate.sh`; per-requirement PASS/FAIL matrix; tracks new-findings count |
| qa-manual-tester | sonnet | Bash, Read | verdicts from HTTP behavior only; read-only tool surface (no Edit/Write); report-only contract — the logs/specs-only Read scope is a prompt-level rule (tool frontmatter cannot path-restrict Read) |
| ci-fixer | sonnet | Bash, Read, Edit, Glob, Grep | `gh run/checks` polling; root-cause fixes; degrade: no checks → report-and-skip |
| pr-comment-resolver | sonnet | Bash, Read, Edit, Glob, Grep | `get-pr-comments.sh` source of truth; fix or reasoned reply, never silent dismissal |

## 4. Skill Anatomy & Project Profile

SKILL.md frontmatter: `name` (= dir name) + `description` (trigger-rich: "Use when…" phrasing, includes the profile-gating condition, e.g. "Skip when `capabilities.structurizr` is false"). Body keeps the verified format: Context / Task / Success Criteria / Steps / Constraints / Verification; cross-links stay relative (`../deptrac-fixer/SKILL.md`).

**Profile-key referencing convention:** skills reference keys as inline code with full dotted path (`persistence.mapper`, `make.ci`). Each generalized skill opens with a `## Profile keys consumed` list — the CI doc-check (FR-17 AC) greps these lists against the canonical schema; an undeclared key fails CI. User-service literals may appear only inside fenced blocks tagged `# profile-example` (excluded from the NFR-2 denylist grep by that marker).

**Canonical `.claude/php-sdlc.yml` (resolves OQ-1 — final names, complete example = user-service values):**

```yaml
# profile-example
schema_version: 1                  # required; int; bump on breaking schema change
project:
  name: user-service               # required
  repo: VilnaCRM-Org/user-service  # required, owner/name
php:
  version: "8.4"                   # required
framework:
  name: symfony                    # required
  version: "7.3"                   # optional
  api_platform: "4.2"              # false | version string; default false
  graphql: true                    # bool; default false
persistence:
  mapper: doctrine-odm             # required: doctrine-orm | doctrine-odm
  engine: mongodb                  # required: mysql | mariadb | postgresql | mongodb
architecture:
  source_root: src                 # required
  bounded_contexts: [User, OAuth]  # required, ≥1
  shared_context: Shared           # optional; null = none
make:                              # required map; null value = capability absent (NFR-4)
  ci: ci
  start: start
  tests: tests
  e2e: e2e-tests
  psalm: psalm
  deptrac: deptrac
  phpinsights: phpinsights
  infection: infection
  ai_review_loop: null             # plugin script substitutes when null
  pr_comments: null
  fr_nfr_gate: null
  load_tests: load-tests
quality:                           # required; values may only be RAISED vs these defaults
  phpinsights: {quality: 100, architecture: 100, style: 100, complexity: 94}
  deptrac_violations: 0
  psalm_errors: 0
  infection_msi: 100
ci:
  provider: github-actions         # required; null = no CI (degrade)
  workflows: [tests, psalm, deptrac, phpinsights, infection, openapi-validate]
  required_checks: [tests, psalm, deptrac]
review:
  coderabbit: true                 # bool
  ai_review_agents: [claude]       # default [claude]; non-claude entries warn+skip in v1
  request_changes_blocking: true   # bool
capabilities:
  structurizr: true                # bool, default false
  observability_emf: true
  load_testing: true
```

**Validation mechanism (resolves FR-17 validation question):** `scripts/validate-profile.sh` — pure bash; parses with `yq` if present, else `python3 -c 'import yaml…'` fallback (one of the two is a documented preflight requirement; checked by `setup-preflight.sh`). Checks: required keys present, enum values legal, quality values ≥ defaults, `schema_version == 1`, `make` map keys complete. Exit 0/1 + line-per-violation output. No JSON Schema dependency — keeps the toolchain bash-only and bats-testable.

## 5. Scripts

All scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, source `lib/common.sh`, invoked as `"${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"`, shellcheck-clean, every flag covered by a bats case using `tests/fixtures/` stub binaries.

| Script | Responsibility | Key interface |
|---|---|---|
| `setup-preflight.sh` | Version floors (`bmalph ≥2.11.0`, `claude ≥2.1`, `gh ≥2`), `gh auth status`, git repo, yq-or-python check | exit non-zero on first FAIL; `--report` prints PASS/FAIL table + remediation |
| `generate-profile.sh` | Detect from composer.json, doctrine config, Makefile, `src/`, workflows, `.coderabbit.yaml`; write profile | `--refresh` (overwrite), default = print diff and keep existing (NFR-3) |
| `validate-profile.sh` | §4 schema validation | `<path-to-profile>`; exit 0/1 |
| `inject-governance.sh` | Replace-in-place delimited blocks `<!-- php-backend-sdlc:begin/end -->` in target CLAUDE.md/AGENTS.md; repair duplicates to one block | idempotent; `--diff` preview |
| `ai-review-loop.sh` | Generalized review loop, **claude driver** (ADR-8): per agent in `review.ai_review_agents`, run `claude -p "$REVIEW_PROMPT" --output-format json --permission-mode acceptEdits --max-turns 30`, extract `.result` via jq, parse PASS/FAIL verdict line; loop until PASS or 5 iterations | `--agents`, `--max-iterations` (default 5), `--diff-base`; non-claude agent → warn + skip (v1 matrix = claude-only) |
| `get-pr-comments.sh` | gh GraphQL `reviewThreads(first:100){isResolved, comments…}` + issue comments; resolution-aware | `--pr <n>`, `--unresolved-only`, `--json` |
| `fr-nfr-gate.sh` | Run FR/NFR verification prompt against `specs/` + diff, post PR comment + `BMAD FR/NFR Review Gate` commit status via gh | `--spec-path`, `--impact-context`; exit 0 = zero new findings |

Codex `--output-last-message` dependency is gone: claude's `--output-format json` returns the final message in `.result`, the loop verdict is a mandatory last-line `AI_REVIEW_VERDICT: PASS|FAIL` token the prompt demands — driver-agnostic for future agents.

## 6. Marketplace / Repo CI Architecture

`.github/workflows/ci.yml` (single workflow, parallel jobs, all required on PRs):

| Job | Tooling | Checks |
|---|---|---|
| `manifest-validate` | jq | plugin.json + marketplace.json parse; required fields; semver format; names match dirs |
| `markdown-lint` | markdownlint-cli2 | all `*.md` under `plugins/` |
| `shellcheck` | shellcheck | `plugins/php-backend-sdlc/scripts/**/*.sh` |
| `bats` | bats-core | `plugins/php-backend-sdlc/tests/*.bats` incl. component-counts (NFR-1) |
| `frontmatter-check` | bash + yq | commands have `description`+`argument-hint`; agents have `name`+`description`+`tools`+`model`; skills have `name`+`description`; counts 8/6/21. Glob must account for the loose meta-guide `.md` files at `skills/` root (ADR-11): skills are matched as `skills/*/SKILL.md` only — the meta-guides must NOT have frontmatter and are exempt (a naive `skills/**/*.md` glob would fail on them) |
| `profile-keys-check` | bash + grep | greps each skill's `## Profile keys consumed` header against the canonical schema keys in `docs/profile-schema.md`; any undeclared key = fail (FR-17 AC) |
| `generalization-audit` | grep -riE | NFR-2 denylist (`VilnaCRM` outside manifests, `user-service`, `Mongo[A-Z]\w*Repository`, `AppRunner`, `src/User`, `src/OAuth`, workspace.dsl container names) excluding `# profile-example` fenced blocks; plus NFR-7 no `_bmad/`/`.ralph/` files in plugin tree |

**Release policy (resolves OQ-3):** v1 ships with relative `source: ./plugins/php-backend-sdlc` on `main` — installers track main. Switch the marketplace entry to `{"source": "git-subdir", "url": …, "path": "plugins/php-backend-sdlc", "ref": "php-backend-sdlc-vX.Y.Z", "sha": "<pin>"}` at the **first external consumer or v1.0.0, whichever comes first**. Tags: `php-backend-sdlc-vX.Y.Z`, semver (MAJOR = profile `schema_version` or command-contract break; MINOR = new skill/command/profile key; PATCH = fixes). Every release bumps `plugin.json` version (manifest-validate asserts tag == version on tag builds) and appends `docs/release-process.md` changelog.

## 7. Data Flow — SDLC Loop

```
user: /sdlc "task text"
  └─ stage 0 setup-check ── validate-profile.sh + preflight ──[invalid]──► HALT: "run /sdlc-setup"
  └─ stage 1 /sdlc-issue ──────────────► artifact: issue URL (+label)
  └─ stage 2 /sdlc-plan (bmad-autonomous-planning) ─► artifact: specs/<slug>/{research,brief,prd,
        architecture,epics-stories,readiness}; loop ≤5 until readiness PASS
  └─ stage 3 /sdlc-implement ── bmalph implement → bmalph run --driver claude-code
        ├─ parallel php-implementer subagents (independent stories)
        ├─ artifact: fix_plan.md checkboxes + ---RALPH_STATUS--- (EXIT_SIGNAL)
        └─[circuit breaker open]──► ESCALATED report (never reset)            ◄─┐
  └─ stage 4 /sdlc-review ── triage 21 verdicts → code-quality-reviewer +       │
        fr-nfr-reviewer → fr-nfr-gate.sh; loop ≤5 until 0 new findings          │
        artifact: review report (verdicts, findings/iteration)                  │
  └─ stage 5 /sdlc-qa ── qa-manual-tester (make start + HTTP)                   │
        artifact: QA report ──[FAIL + repro steps]── loop-back ─────────────────┘
  └─ stage 6 /sdlc-finish-pr ── gh pr create/edit ─► artifact: PR URL
        ├─ ci-fixer loop ≤5 ──► checks green (or skip-with-report)
        ├─ pr-comment-resolver loop ≤5 (get-pr-comments.sh) ──► 0 unresolved
        │     └─[no reviewer app]── ai-review-loop.sh findings as source
        └─ exit: SUCCESS run report (issue, specs, PR, reports linked)
Loop-backs: QA FAIL→3; review findings→fix in-stage; finish-pr check/comment fixes commit→re-poll.
Every loop-back consumes the owning stage's 5-iteration budget; breach → ESCALATED report (§2).
```

## 8. Error Handling & Degrade Matrix

| Condition | Detected by | Behavior | Status |
|---|---|---|---|
| No CodeRabbit / reviewer app | `review.coderabbit: false` | `ai-review-loop.sh` is the comment source for stage 6 | SUCCESS-WITH-REPORT |
| Missing make target | profile `make.<key>: null` | skill/agent records "capability absent", skips that check | SUCCESS-WITH-REPORT |
| No CI workflows | `ci.provider: null` / zero checks on PR | ci-fixer skip-with-report | SUCCESS-WITH-REPORT |
| Ralph circuit breaker open | `---RALPH_STATUS---` / breaker files | stop stage 3, escalation report, never reset, honor cooldown | ESCALATED |
| Guard breach (any stage) | iteration counter = 5 | §2 escalation block, run halts | ESCALATED |
| Preflight FAIL / profile invalid | setup-preflight / validate-profile | abort before stage 1 with named remediation | HALTED |
| `claude -p` non-zero / malformed JSON | ai-review-loop.sh | retry once, then count as failed iteration (never infinite) | per-loop |
| Permission denial mid-loop | non-interactive `claude` error output | surface verbatim in escalation report; point to docs/permissions.md | ESCALATED |

Rule (NFR-4): degrade paths never loop and never hard-fail the run; only guards/breakers/preflight produce ESCALATED/HALTED.

## 9. Architecture Decision Records

- **ADR-1 — Runtime profile reads, no per-repo rendering** (research OQ-1): skills are static and interpolate `.claude/php-sdlc.yml` at runtime. Keeps plugin updates atomic (`claude plugin update`), skills testable as shipped, zero drift-by-copy (the §3.2 corruption class). Cost: every skill needs the "Profile keys consumed" header; accepted.
- **ADR-2 — Profile schema & validation** (PRD OQ-1): canonical schema as in §4 (`schema_version: 1`, names exactly as listed; required: project, php.version, framework.name, persistence, architecture.source_root+bounded_contexts, make, quality, ci.provider; rest optional with defaults). Validation = `validate-profile.sh` with yq→python3-yaml fallback, not JSON Schema — bash-only toolchain, bats-friendly.
- **ADR-3 — Governance via delimited managed blocks**: `inject-governance.sh` owns `<!-- php-backend-sdlc:begin/end -->` regions in target CLAUDE.md/AGENTS.md; replace-in-place, duplicate-repair, idempotent (NFR-3). No separate imported file — agents reliably read CLAUDE.md, imports are less portable across cross-agent consumers.
- **ADR-4 — Ship the three review scripts in the plugin** (research OQ-3): `ai-review-loop.sh`, `get-pr-comments.sh`, `fr-nfr-gate.sh` live in plugin `scripts/`, invoked via `${CLAUDE_PLUGIN_ROOT}`; target repos need no copies; profile `make.*: null` routes to the shipped versions. Single maintenance point; template-sync rejected. Rename recorded: user-service's `bmad-fr-nfr-review-gate.sh` ships as `fr-nfr-gate.sh` (shorter name, lives in plugin `scripts/`).
- **ADR-5 — Triage-based review gate** (research OQ-4): all 21 skills get recorded verdicts; full bodies load only on EXECUTE (NFR-5). "Run all verbatim" rejected on token-cost grounds (order-of-magnitude difference).
- **ADR-6 — Permissions** (research OQ-5): default `--permission-mode acceptEdits` for plugin-spawned `claude -p`; `/sdlc-setup` writes a documented `.claude/settings.json` allowlist (Bash(make:*), Bash(docker compose exec php:*), Bash(git:*), Bash(gh:*)). `bypassPermissions` remains a Ralph-driver opt-in, documented, never default.
- **ADR-7 — Threshold canonicalization** (research OQ-6, =A1): complexity **94**, MSI **100** are the shipped defaults; profile may raise, never lower; the 93% ci-workflow literal is corrected during generalization.
- **ADR-8 — Claude driver flag mapping** (PRD OQ-2): Codex `--output-last-message <file>` → `claude -p --output-format json` + jq `.result`; verdict contract = mandatory `AI_REVIEW_VERDICT: PASS|FAIL` last line; `--permission-mode acceptEdits`, `--max-turns 30`. Agent matrix v1 = claude-only; non-claude entries in `review.ai_review_agents` warn+skip.
- **ADR-9 — Release tagging** (PRD OQ-3): relative source on main for v1; pin `git-subdir` ref+sha at first external consumer or v1.0.0, whichever first; tags `php-backend-sdlc-vX.Y.Z`, semver semantics per §6.
- **ADR-10 — bmalph compatibility floor** (research OQ-7): floor = 2.11.0 enforced by preflight; non-interactive `bmalph init` failure is surfaced, never masked (A2); no vendored `_bmad/`/`.ralph/` assets ever (NFR-7 CI check).
- **ADR-11 — Meta-guides live as loose files in `skills/`**: `SKILL-DECISION-GUIDE.md`/`AI-AGENT-GUIDE.md` at `skills/` root (not subdirs → not discovered as skills, no frontmatter) so existing relative links from SKILL.md files survive the install cache verbatim.
