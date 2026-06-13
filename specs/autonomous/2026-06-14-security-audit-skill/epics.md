---
stepsCompleted: [step-01-validate-prerequisites, step-02-design-epics, step-03-create-stories, step-04-final-validation]
inputDocuments:
  - specs/autonomous/2026-06-14-security-audit-skill/prd.md
  - specs/autonomous/2026-06-14-security-audit-skill/architecture.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/epics.md
workflowType: 'epics-stories'
date: 2026-06-14
author: BMAD PM/SM agents (autonomous run — interactive steps skipped, decisions recorded inline)
---

# Epics & Stories — `security-audit` Skill (+ `security-auditor` Agent) for `php-backend-sdlc`

6 epics, 24 stories. This is a **delta on the existing v1 plugin** (8 commands, 6 agents, 21 skills + 2 meta-guides). Dependency order: **E4 → (E1 ∥ E2 ∥ E3) → E5 → E6**. The two profile keys (E4) and the reference catalogs (E2) are the data sources the skill body (E1) and agent (E3) cite, so E4 leads and E2 can land in parallel with E1/E3 (E1/E3 reference the `reference/` files by relative path only — they don't read their content at authoring time). Integration/count edits (E5) wait for the new components to exist; tests + dogfood evidence (E6) come last.

All paths relative to repo root; plugin root = `plugins/php-backend-sdlc/`. Sizes: S (≤1h focused agent run), M (1–3h), L (3h+ or evidence run). Execution mode: **PARALLEL** = disjoint file set, fan out to a subagent; **SEQUENTIAL** = must wait for listed deps. Every story inherits the parent plugin's CI gates (markdownlint, frontmatter-check, generalization-audit, profile-keys-check) and the NFR-4 denylist (`VilnaCRM` outside manifests, `user-service`, `Mongo[A-Z]\w*Repository`, `AppRunner`, `src/User`, `src/OAuth`, workspace.dsl container names) — none of these tokens may appear outside `# profile-example` fences.

---

## Epic E4 — Profile schema keys (leads: data contract for everything downstream)

Adds the two minimal profile keys (architecture §8, FR-9, resolves OQ-1/OQ-2) so the skill's and agent's `## Profile keys consumed` headers grep clean against the schema page (`profile-keys-check` is the gate). E4 leads because E1/E3's headers must name keys that exist in `docs/profile-schema.md`.

### E4-S1 — `make.security` + `capabilities.dynamic_security_testing` schema rows (S, SEQUENTIAL — lead)
**Description:** Edit `docs/profile-schema.md` per architecture §8. Add one row to the **`make` — logical target map** table after `make.load_tests`: `make.security` — required (nullable), default `null`, "Security/SAST suite; plugin runs its bundled static lane (Psalm taint / Semgrep / `composer audit` / secret-scan) when `null` (SA-2); mirrors `make.ai_review_loop`/`make.pr_comments`/`make.fr_nfr_gate` null-substitution precedent." Add one row to the **`capabilities`** table after `capabilities.load_testing`: `capabilities.dynamic_security_testing` — optional, bool, default `false`, "Gates dynamic (live-service) security probing; pairs with `make.start` the way `capabilities.load_testing` pairs with `make.load_tests`; when `false` or `make.start: null`, dynamic probing degrades to skip-with-note, static lanes still run (NFR-3)." Add `security: null` to the `make:` map and `dynamic_security_testing: false` to `capabilities:` in the canonical `# profile-example` block. Key name `dynamic_security_testing` (SA-9, not `dast`) to match the `load_testing`/`structurizr` house style.
**AC:** Both keys present with required/nullable marking + default (FR-9 AC); the `# profile-example` block carries both new lines; markdownlint passes; the rows match the existing table column shape exactly; no key appears outside its table row / example fence. `profile-keys-check` will pass once E1/E3 declare the same keys (verified in E6-S1).
**Deps:** none.
**Files:** `plugins/php-backend-sdlc/docs/profile-schema.md`.

---

## Epic E2 — OWASP reference catalogs (splittable per file for max parallelism)

The three `reference/` files (architecture §7, FR-4/FR-5/FR-6) that keep SKILL.md under ~500 lines (NFR-9). Three fully disjoint files → three parallel stories. Each carries edition labels (NFR-9), uses profile-resolved paths only (NFR-4), and is linked from SKILL.md with `../`-relative paths. **All three PARALLEL.** They depend on E4 only nominally (they cite key names in prose); they may start immediately and land before E1 links them.

### E2-S1 — `reference/owasp-catalog.md` — full OWASP/CWE corpus, edition-labelled (L, PARALLEL)
**Description:** FR-4. Enumerate the entire corpus with **edition labels** so refreshes are localized, plus a per-family CWE mapping and a PHP-relevance / N/A-with-reason column — the single source the skill's triage table draws from. Contents: OWASP Top 10 web 2003/2004/2007/2010/2013/2017/2021; API Security Top 10 2019/2023; LLM Top 10 (2025 v2.0); OWASP Mobile 2014/2016/2024 (marked **N/A-for-backend** with reasoning); ASVS 5.0 (L1/L2/L3, **L2 default bar**) as the coverage checklist; WSTG 4.2 as the test-methodology index; Proactive Controls / Cheat Sheet Series as the remediation source-of-truth pointer; CWE Top 25 2024 (ordered, with PHP relevance and **memory-safety CWEs marked N/A-with-reason**); SANS treated as the same CWE/SANS Top 25 taxonomy.
**AC:** Every listed family/edition appears with its label; each OWASP family carries its mapped CWE id(s); memory-safety CWEs and Mobile carry an explicit N/A-with-reason note (FR-4 AC); the dispatchable family set (architecture §5.1 table — BOLA/IDOR…GraphQL/LLM) is derivable from this file's rows; passes markdownlint + generalization-audit; zero denylist tokens outside `# profile-example` fences.
**Deps:** none (cites E4 key names in prose only).
**Files:** `plugins/php-backend-sdlc/skills/security-audit/reference/owasp-catalog.md`.

### E2-S2 — `reference/attack-playbooks.md` — per-family probe + reproduce-against-service step (L, PARALLEL)
**Description:** FR-5. Per-family probing methodology, **WSTG-4.2-test-id mapped**, that the `security-auditor` executes against this stack. Each entry states a concrete probe **and** an explicit reproduce-against-running-service verification step, and names the tool (`curl`/`jq`/GraphQL POST, Psalm `--taint-analysis`, Semgrep, `composer audit`, secret-scan). Families: BOLA/IDOR (object-id/IRI swap), BOPLA/mass-assignment (write-group/denormalization probing), BFLA (`#[IsGranted]`/`security`-expression bypass), SQLi/DQL (taint to DQL/native sink), SSTI (Twig `|raw`/dynamic-template), insecure deserialization (`unserialize`/object-injection sinks), SSRF (URL-fetch sink), auth/session (JWT `none`/alg-confusion, hashing, expiry, fixation), misconfiguration (`APP_ENV`/profiler/CORS/headers/TLS), vulnerable deps (`composer audit` + advisory DB), cryptographic failures/secrets (secret-scan + crypto review), file upload (CWE-434), rate/resource exhaustion, GraphQL (introspection/deep-query/batching). Stack-generic: profile-resolved paths (`architecture.source_root`, `persistence.mapper`, `framework.*`), no source-project literals.
**AC:** Each PHP-relevant family from `owasp-catalog.md` has a playbook entry with ≥1 concrete probe **and** an explicit reproduce-against-running-service verification step (FR-5 AC); entries name the tool; entries map to WSTG 4.2 test ids; every path/context is profile-resolved (NFR-4); passes markdownlint + generalization-audit (seeding e.g. `MongoUserRepository` would fail it).
**Deps:** none (family list mirrors E2-S1's corpus; authored independently from the architecture §5.1 table).
**Files:** `plugins/php-backend-sdlc/skills/security-audit/reference/attack-playbooks.md`.

### E2-S3 — `reference/remediation-patterns.md` — secure-by-default, cheat-sheet-cited, suppression-free (M, PARALLEL)
**Description:** FR-6. Secure-by-default, root-cause fix per vuln class, each citing the relevant **OWASP cheat sheet + a vetted library/framework primitive**: Symfony SecurityBundle `auto` password hasher; Doctrine parameterized queries/QueryBuilder (never concatenated DQL); Twig auto-escaping (never `|raw`/dynamic templates on user input); Symfony Serializer write-groups (mass-assignment); API Platform voters / `security` expressions (BOLA/BFLA); Paragon Initiative crypto guidance. The file states **"root-cause only, zero suppression"** and **"every fix gets a failing-then-passing regression test"** verbatim (NFR-7), and recommends **no** suppression / baseline / config-relaxation / threshold-reduction / `deptrac.yaml` edit anywhere.
**AC:** Every PHP-relevant family has a remediation entry naming a vetted library/primitive + the OWASP cheat sheet it derives from (FR-6 AC); the two verbatim policy sentences are present; no entry recommends a suppression/baseline/config-relaxation/threshold cut; carries a cheat-sheet edition pointer (NFR-9); passes markdownlint + generalization-audit.
**Deps:** none.
**Files:** `plugins/php-backend-sdlc/skills/security-audit/reference/remediation-patterns.md`.

---

## Epic E1 — Skill body (`security-audit/SKILL.md`)

The orchestrating skill (architecture §4, FR-1/FR-2/FR-7/FR-8) — the canonical triage→fan-out→find→verify→fix→regress→re-verify→loop, ≤ ~500 lines (NFR-9) with every enumeration delegated to the E2 `reference/` files. One file, one story. **SEQUENTIAL after E4** (its `## Profile keys consumed` header must name schema-declared keys); it links the E2 files by `../`-relative path but does not need their content at authoring time, so it may run in parallel with E2.

### E1-S1 — `security-audit/SKILL.md` — adversarial multi-subagent red-team loop (L, SEQUENTIAL after E4-S1)
**Description:** FR-1, FR-2, FR-7, FR-8. Write the skill in the verified body format (frontmatter `name: security-audit` = dir name + trigger-rich `description` noting defensive/authorized-only and the `capabilities.dynamic_security_testing`-false skip-note), with body sections in the architecture §4 fixed order: (1) `## Profile keys consumed` first H2 — the dotted-path list from architecture §3 row 1 (`make.security`, `capabilities.dynamic_security_testing`, `make.start`, `make.ci`, `make.psalm`, `architecture.source_root`, `architecture.bounded_contexts`, `framework.api_platform`, `framework.graphql`, `persistence.mapper`, `persistence.engine`); (2) `## Gating` — defensive/authorized boundary verbatim (NFR-5), the three degrade gates, LLM-family-on-detection (SA-7); (3) `## Context`; (4) `## Task`; (5) `## Steps` — the canonical loop 5.1 Triage → 5.2 Fan-out (one `security-auditor` per PROBE family in parallel) → 5.3 Find→verify → 5.4 Aggregate/dedupe/promote → 5.5 Fix→regression-test (route to `php-implementer`) → 5.6 Re-verify→loop (`MAX_ITERATIONS=5`, affected-family re-verify each iteration + one final `make.ci`, SA-6), each enumeration delegated to a `reference/` file; (6) `## Constraints`; (7) `## Format` — the finding-record schema (architecture §6) + run-report shape; (8) `## Verification`; (9) `## Related Skills` — `../code-review/`, `../testing-workflow/`, `../ci-workflow/`, `../bmad-fr-nfr-review-gate/` (all `../`-relative). The body PRESCRIBES the fan-out as text; it contains **no** Task-tool call (skills never invoke agents).
**AC:** A dry-run prompt walk-through shows the triage→fan-out→find→verify→fix→regress→re-verify→loop sequence, the per-family verdict table, the `MAX_ITERATIONS=5` counter, and the zero-new-findings exit (FR-1 AC); SKILL.md documents its triaged-in-Stage-4/standalone placement and fix-routing through `php-implementer` (FR-2 AC); SAST output enters as candidates, only reproduced items become findings (FR-7 AC); the fix→regression→re-verify→`make.ci`-green loop and the zero-suppression scan are documented (FR-8 AC); `wc -l SKILL.md` ≤ ~500 (NFR-9 CI line-count check); every enumeration is delegated to `reference/` (no inline OWASP/playbook/remediation lists); loads as `php-backend-sdlc:security-audit`; passes frontmatter-check, markdownlint, generalization-audit; `## Profile keys consumed` greps clean against `docs/profile-schema.md` (so `profile-keys-check` passes).
**Deps:** E4-S1 (schema keys). Links E2-S1/S2/S3 by path; no content dependency.
**Files:** `plugins/php-backend-sdlc/skills/security-audit/SKILL.md`.

---

## Epic E3 — `security-auditor` agent

The red-team subagent unit the skill dispatches in parallel, one per OWASP family (architecture §3, FR-3). One file, one story. **SEQUENTIAL after E4** (its `## Profile keys consumed` header names schema keys); parallel with E1/E2 otherwise.

### E3-S1 — `agents/security-auditor.md` — red-team subagent, report-and-route (L, SEQUENTIAL after E4-S1)
**Description:** FR-3, NFR-5, NFR-6, NFR-7. Author the agent mirroring the plugin's verified anatomy (matched against `agents/qa-manual-tester.md` and `agents/code-quality-reviewer.md`). Frontmatter: `name: security-auditor`; trigger-rich `description` (one instance per OWASP family, grey-box SAST+DAST, verify-by-reproduction, report verified findings mapped to CWE+OWASP+CVSS-ish, authorized/defensive boundary, **never edits code — findings route to php-implementer**); `tools: Bash, Read, Glob, Grep` (combining the dynamic-probe + source-read precedents; **no `Edit`/`Write`** per SA-3); `model: opus`. Body = the **eight-section spine** in the fixed order (architecture §3 table): (1) Profile keys consumed (same dotted-path list as the skill); (2) Role — red-team unit for ONE assigned family, grey-box, restates the NFR-5 four boundary rules verbatim; (3) Inputs — dispatch prompt (family id, its `attack-playbooks.md` entry, report contract, iteration number, prior ledger on re-dispatch), profile, running-service base URL, source tree; (4) Outputs — the finding-record report (architecture §6 schema), verified findings only or a clean verdict, report-and-route, never edits; (5) Allowed actions — `Bash` SAST/dep/secret/config + dynamic probing, `Read`/`Glob`/`Grep` for localization, with the forbidden-action list (no edits, no git, no host package install, no out-of-band datastore mutation, no out-of-profile host, no destructive non-API op); (6) Degrade paths — `make.security: null` ⇒ bundled static lane (SA-2), capability-false/`make.start: null` ⇒ static-only skip-note, family N/A ⇒ recorded reason, never loop/hard-fail (NFR-3); (7) Iteration discipline — own counter `MAX_ITERATIONS=5`, never reset, stateless across dispatches, re-dispatched only while family open, canonical escalation block; (8) Smoke prompt — happy path (one family, verified finding with reproduction + CWE/OWASP/severity + cited remediation, no files written, no git) + degrade path (`make.security: null` static-only).
**AC:** `security-auditor.md` contains all eight body sections plus the four frontmatter keys (FR-3 AC); loads in the `claude` agent listing; the smoke prompt exercises one family's happy path + one degrade path; the agent **never** emits a finding lacking a reproduction and contains **no** code-edit action (no `Edit`/`Write` in tools or body); the authorized/defensive framing + four boundary rules appear verbatim (NFR-5 AC); passes frontmatter-check, markdownlint, generalization-audit; `## Profile keys consumed` greps clean against `docs/profile-schema.md`.
**Deps:** E4-S1 (schema keys). References E2 files by name only.
**Files:** `plugins/php-backend-sdlc/agents/security-auditor.md`.

---

## Epic E5 — Integration, meta-guides & component counts

The single consistent count/guide delta for the new skill (21→22) and agent (6→7) across the plugin tree and the parent planning artifacts (architecture §9, FR-10, FR-2 AC). **SEQUENTIAL after E1+E3** (the new components must exist to be referenced). E5-S1…S5 are PARALLEL (disjoint files).

### E5-S1 — `tests/component-counts.bats` — counts 8/7/22 (S, PARALLEL after E1-S1, E3-S1)
**Description:** FR-10, NFR-1. `@test "exactly 6 agent…"` → `7`; `@test "exactly 21 skills…"` → `22`; header comment "8 commands / 6 agents / 21 skills" → "8 commands / 7 agents / 22 skills"; the `claude plugin` smoke comment "6 agents, and 21 skills" → "7 agents, and 22 skills". Asserts against the install-cache layout (2 loose meta-guides still exempt).
**AC:** Asserts exactly 8 commands / 7 agents / 22 skills + 2 loose meta-guides and passes on the complete tree; fails if the new skill or agent is removed (NFR-1 AC). (This is the binding count gate referenced by FR-10/NFR-1.)
**Deps:** E1-S1, E3-S1.
**Files:** `plugins/php-backend-sdlc/tests/component-counts.bats`.

### E5-S2 — `skills/SKILL-DECISION-GUIDE.md` — 22 + security-audit triage row (S, PARALLEL after E1-S1)
**Description:** FR-10. "All 21 skills…" → 22 (every skill-count `21` occurrence); add a `## Security audit` decision section + a `**Use**: [security-audit](security-audit/SKILL.md)` row + a disambiguation-table row: "security-audit vs code-review: **adversarial vuln-hunting against the running service** → security-audit; **PR-comment / quality review** → code-review."
**AC:** Shows 22 with the new section + row + disambiguation entry; the relative link resolves within `skills/`; remains a loose file with **no** frontmatter (must not be discovered as a skill); markdownlint passes; no stale 21 skill-count remains.
**Deps:** E1-S1.
**Files:** `plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md`.

### E5-S3 — `skills/AI-AGENT-GUIDE.md` — 22 + skill/agent entries (S, PARALLEL after E1-S1, E3-S1)
**Description:** FR-10. "Available Skills (21 Total)" → "(22 Total)"; add the `security-audit` usage entry (steps to read SKILL + its `reference/` files) and a `security-auditor` cross-agent entry.
**AC:** Shows 22 with both new entries; cross-links resolve; remains a loose file with no frontmatter; markdownlint passes; no stale 21 skill-count remains.
**Deps:** E1-S1, E3-S1.
**Files:** `plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md`.

### E5-S4 — `commands/sdlc-review.md` — triage count 21→22 + security-audit verdict row (S, PARALLEL after E1-S1)
**Description:** FR-2 AC, FR-10. Every "21" triage reference → "22" (`21-skill triage` in description, "21 in v1", "All 21 verdicts", "21/21 skills", "Skill triage (21/21 verdicts)", "all 21" comment). The triage list now records an EXECUTE / NOT-APPLICABLE verdict for `security-audit` like every other skill (no new command — surface stays 8).
**AC:** The triage list includes a `security-audit` row and the count reads 22/22 (FR-2 AC); no `/sdlc-security` command added (command count stays 8); markdownlint + frontmatter-check pass; no stale 21 triage count remains.
**Deps:** E1-S1.
**Files:** `plugins/php-backend-sdlc/commands/sdlc-review.md`.

### E5-S5 — `README.md` + parent planning-artifact counts (S, PARALLEL after E1-S1, E3-S1)
**Description:** FR-10. Update plugin `README.md` component counts (6→7 agents, 21→22 skills) wherever stated. Update the parent plugin's own planning artifacts (architecture §9 cross-spec edits): `specs/autonomous/2026-06-09-php-backend-sdlc-plugin/architecture.md` §1.1 file tree (add `agents/security-auditor.md` + `skills/security-audit/`), §3 agent matrix (add a `security-auditor | opus | Bash, Read, Glob, Grep` row), and counts "6 subagents"→7 / "21 skills"→22.
**AC:** No document in the plugin tree states a stale 6-agent or 21-skill count (CI count-consistency / grep check, FR-10 AC); README shows 7 agents / 22 skills; the parent architecture tree + agent matrix include the new components; markdownlint passes.
**Deps:** E1-S1, E3-S1.
**Files:** `plugins/php-backend-sdlc/README.md`, `specs/autonomous/2026-06-09-php-backend-sdlc-plugin/architecture.md`.

---

## Epic E6 — Tests / regression verification + dogfood audit

Verifies the CI-automated ACs are green and runs the seeded-vulnerability + degrade + loop-safety evidence (PRD §4 release gate). **SEQUENTIAL after E5.** E6-S1 (CI verification) gates E6-S2/S3 (evidence runs); E6-S2 ∥ E6-S3.

### E6-S1 — CI-automated AC verification (M, SEQUENTIAL after E5)
**Description:** Run the existing plugin CI matrix over the new files and confirm every CI-automated AC is green with no new job required (architecture §12): `component-counts.bats` asserts 8/7/22; `generalization-audit` exits 0 over the new skill/agent/reference/schema files (NFR-4) and a seeded denylist token (e.g. `MongoUserRepository` in `attack-playbooks.md`) fails it; `profile-keys-check` is green (both new keys declared in the skill's and agent's `## Profile keys consumed` headers and documented in `docs/profile-schema.md`; a skill key absent from the schema page fails CI — FR-9 AC); markdownlint + SKILL line-count (≤ ~500) pass (NFR-9 AC); frontmatter-check passes for the new agent + skill.
**AC:** All CI-automated NFR/FR ACs green: NFR-1 (8/7/22), NFR-4 (generalization audit over the new files, with the seed-fails-audit check demonstrated), NFR-9 (SKILL line-count + markdownlint), FR-9 (`profile-keys-check`) — all in the existing CI, no new job added.
**Deps:** E5 complete (E1, E2, E3, E4 transitively).
**Files:** none new (runs existing CI; records results in E6-S2's evidence doc header if convenient).

### E6-S2 — Seeded-vulnerability dogfood audit run (find→verify→fix→regress→re-verify→loop) (L, SEQUENTIAL after E6-S1; PARALLEL with E6-S3)
**Description:** PRD §4 release-gate item 1, FR-7/FR-8/G1/G3, NFR-6/NFR-7. Execute the `security-audit` skill against an authorized target with a seeded vulnerability (e.g. an unparameterized query reachable via an endpoint). Capture the run as an evidence doc: SAST output entering as candidates, only the reproduced item promoted to a finding (FR-7), a non-reproducible SAST candidate recorded downgraded/dropped (FR-7/NFR-6), the finding mapped to CWE+OWASP id+severity band with reproduction steps (NFR-6), a root-cause secure-by-default fix routed through `php-implementer` (no suppression/baseline/threshold edit — NFR-7), a regression test that fails before and passes after (FR-8), the affected family re-verifying clean, and the loop closing with `make.ci` green + the forbidden-suppression scan clean (FR-8/NFR-7). Defensive/authorized boundary observed throughout (NFR-5): in-scope local service only, no exfiltration, mutate-via-API-only, container-only.
**AC:** Evidence doc shows the full find→verify→fix→regress→re-verify→loop with the seeded vuln reported (working reproduction), the non-reproducible candidate dropped, a root-cause fix with a failing-then-passing regression test, family re-verify clean, `make.ci` green, zero suppressions introduced (FR-7/FR-8 AC; NFR-6/NFR-7 AC); no action targets an out-of-profile host or performs a destructive non-API op (NFR-5 AC).
**Deps:** E6-S1.
**Files:** `plugins/php-backend-sdlc/docs/evidence/security-audit-dogfood-run.md`.

### E6-S3 — Loop-safety + degrade + triage-first evidence (L, SEQUENTIAL after E6-S1; PARALLEL with E6-S2)
**Description:** PRD §4 release-gate item 3, NFR-2/NFR-3/NFR-8. Three appendix sections to the evidence doc: (a) **loop safety** — a forced-non-converging finding stops at iteration 5 with the canonical escalation block (open families, per-iteration finding counts, last blocking finding, recommended action); re-dispatch logs show only still-open families re-run; no automatic breaker reset (NFR-2 AC). (b) **degrade paths** — three simulated environments each complete with explicit degrade notes + SUCCESS-WITH-REPORT, none hard-fails or loops: no `make.security` (bundled static lane), no bootable service / `capabilities.dynamic_security_testing: false` (dynamic skip-with-note, static lanes run), `framework.graphql: false` (GraphQL family N/A) (NFR-3 AC). (c) **triage-first / token-cost** — N/A families (Mobile, memory-safety CWEs, LLM-when-not-detected) excluded before fan-out; SAST-first candidate filtering documented; the re-dispatch set shrinks to only still-open families across iterations (NFR-8 AC).
**AC:** Each NFR (NFR-2, NFR-3, NFR-8) is evidenced with logs and mapped to its NFR id explicitly; the degrade section covers all three §10 environments; the loop-safety section shows the iteration-5 stop + shrinking re-dispatch set + no breaker reset.
**Deps:** E6-S1.
**Files:** `plugins/php-backend-sdlc/docs/evidence/security-audit-dogfood-run.md` (NFR appendix sections; section ownership: S2 = main run log, S3 = NFR appendices — serialize if zero merge risk is preferred).

---

## Parallelization plan (implementation fan-out)

| Wave | Stories | Mode |
|---|---|---|
| 1 | E4-S1 | SEQUENTIAL (schema lead — data contract) |
| 2 | E1-S1 ∥ E2-S1 ∥ E2-S2 ∥ E2-S3 ∥ E3-S1 | PARALLEL (5 agents — fully disjoint files; E1/E3 cite schema keys from wave 1) |
| 3 | E5-S1 ∥ E5-S2 ∥ E5-S3 ∥ E5-S4 ∥ E5-S5 | PARALLEL (5 agents — disjoint count/guide files, after E1+E3 exist) |
| 4 | E6-S1 | SEQUENTIAL (CI-automated AC verification) |
| 5 | E6-S2 ∥ E6-S3 | PARALLEL (2 agents; both touch the evidence doc — S2 = main run log, S3 = NFR appendices) |

18 of 24 stories are parallel-safe. The only shared-file risk is wave 5 (single evidence doc) — mitigated by section ownership (S2 = main run log, S3 = NFR appendices); serialize if the implementer prefers zero merge risk. E2 reference files are the maximum-parallelism block: three independent OWASP catalogs splittable across three subagents with zero conflicts.

## Coverage table — FR/NFR → stories

| Req | Stories | | Req | Stories |
|---|---|---|---|---|
| FR-1 | E1-S1, E6-S2 | | FR-9 | E4-S1, E6-S1 |
| FR-2 | E1-S1, E5-S4 | | FR-10 | E5-S1, E5-S2, E5-S3, E5-S4, E5-S5 |
| FR-3 | E3-S1 | | NFR-1 | E5-S1, E6-S1 |
| FR-4 | E2-S1 | | NFR-2 | E1-S1, E3-S1, E6-S3 |
| FR-5 | E2-S2 | | NFR-3 | E1-S1, E3-S1, E6-S3 |
| FR-6 | E2-S3 | | NFR-4 | E2-S1, E2-S2, E2-S3, E1-S1, E3-S1, E6-S1 |
| FR-7 | E1-S1, E6-S2 | | NFR-5 | E1-S1, E3-S1, E6-S2 |
| FR-8 | E1-S1, E6-S2 | | NFR-6 | E1-S1, E3-S1, E6-S2 |
| | | | NFR-7 | E2-S3, E1-S1, E6-S2 |
| | | | NFR-8 | E1-S1, E6-S3 |
| | | | NFR-9 | E2-S1, E2-S2, E2-S3, E1-S1, E6-S1 |

**Uncovered requirements: none.** All FR-1…FR-10 and NFR-1…NFR-9 map to ≥1 story; reverse check: every story maps to ≥1 requirement.
