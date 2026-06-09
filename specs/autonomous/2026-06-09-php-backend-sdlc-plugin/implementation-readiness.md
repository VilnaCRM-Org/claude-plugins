---
stepsCompleted: [step-01-document-discovery, step-02-cross-artifact-consistency, step-03-ac-traceability, step-04-adr-conflict-scan, step-05-dependency-order, step-06-risk-carryforward, step-07-verdict]
inputDocuments:
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/product-brief.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/architecture.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/epics.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/research.md (claim spot-checks)
workflowType: 'implementation-readiness'
date: 2026-06-10
author: BMAD PM/SM readiness gate (autonomous run — no human pauses)
---

# Implementation Readiness — `php-backend-sdlc` Claude Code Plugin

## Verdict: READY

Initial verdict (2026-06-10, first pass): READY-WITH-CONDITIONS — four major findings required small artifact amendments. All ten findings (4 major + 6 minor) were resolved by surgical artifact amendments the same day; see "Conditions resolved" below. No blocker remains for waves 1–10.

## Findings

| ID | Severity | Artifact | Description | Required fix |
|---|---|---|---|---|
| F-1 | major | prd.md (FR-18, FR-15/`bmad-fr-nfr-review-gate` bullet) vs architecture.md §1.1/§5 + epics E2-S6/E3-S6/E5-S3 | Gate script named `bmad-fr-nfr-review-gate.sh` in brief §6.6 and PRD FR-18, but `fr-nfr-gate.sh` everywhere in architecture and epics. The rename is never recorded as a decision; PRD FR-18 AC and the skill story reference different filenames for the same artifact. | Amend PRD FR-18 (and brief feature 6 if touched) to `fr-nfr-gate.sh`, or add a one-line rename note in architecture §5; epics already self-consistent — keep `fr-nfr-gate.sh`. |
| F-2 | major | architecture.md §4/§6 + epics E1-S2, coverage table | FR-17 AC requires "a skill reading any undeclared key is a CI doc-check failure"; architecture §4 promises "the CI doc-check … greps these lists against the canonical schema" — but the §6 CI job table (6 jobs) contains no such job, E1-S2 doesn't implement it, and no story owns it. E3/E4 common AC asserts "profile-keys header greps clean against schema" against a check that never gets built. | Add the profile-keys doc-check (grep `## Profile keys consumed` lists vs `docs/profile-schema.md`) to architecture §6 and E1-S2 (7th job, or fold into `frontmatter-check`). |
| F-3 | major | epics E7-S3 (also PRD §8, architecture) | Brief OQ-2 ("Reference task for G3 — which concrete feature on `php-service-template`?") was dropped: not carried into PRD §8, not resolved in architecture, and E7-S3 just says "the full `/sdlc` reference task". FR-3/4/5/6/7 ACs all reference "the reference task/issue"; FR-5's parallel-dispatch AC needs a task whose plan yields ≥2 independent stories. The evidence run is under-specified. | Pin the reference task in E7-S3 (brief's leading candidate: a small CRUD resource on `php-service-template`, sized to produce ≥2 independent stories). |
| F-4 | major | epics E7-S3/E7-S4 vs PRD §4 release gate | PRD release gate item 1 requires *all* FR ACs demonstrated, but two runtime demonstrations have no owning story: FR-7's "a seeded defect produces FAIL with reproduction steps" and FR-8's "PR with ≥1 failing check and ≥1 CodeRabbit comment ends with all checks green and 0 unresolved". E6-S5/E6-S6 ACs only verify command-body templates; E7-S4 enumerates NFR-4/5/6 evidence only. | Extend E7-S4 (or E7-S3) to enumerate: seeded-defect QA FAIL run (FR-7) and failing-check + unresolved-comment finish-pr run (FR-8). |
| F-5 | minor | prd.md FR-20 vs architecture §6 / epics E1-S2 | PRD says "all five checks"; architecture/epics define six CI jobs (shellcheck and bats split). Substance identical; count text diverges. | One-line PRD FR-20 wording fix ("five check areas / six jobs"). |
| F-6 | minor | brief §0/§6, prd.md §1 | "3 generalized scripts" in both executive summaries vs 7 shipped scripts + `lib/common.sh` in architecture §5 / epics E2 ("All seven plugin scripts"). No AC asserts a script count, but summary inventories mislead. | Clarify summaries: "3 generalized review scripts + 4 new setup scripts". |
| F-7 | minor | architecture §3 / epics E5-S4 | qa-manual-tester claims source reading "forbidden in prompt AND tool surface" while granting `Read (logs/specs only)` — agent `tools:` frontmatter cannot path-restrict Read. Enforceable tool-surface restriction is only the absence of Edit/Write. | Reword: tool surface excludes Edit/Write; the logs/specs-only Read scope is a prompt-level rule. |
| F-8 | minor | epics E1-S2 vs ADR-11/E4-S11 | `frontmatter-check` requires skills to have `name`+`description` and counts 21, but ADR-11 places two loose `.md` meta-guides at `skills/` root that "must NOT" have frontmatter. The check's glob (`skills/*/SKILL.md` only) is unstated — naive `skills/**/*.md` fails on the meta-guides. | State the glob explicitly in E1-S2 (count dirs with `SKILL.md`; exclude loose root files). |
| F-9 | minor | epics (risk carry-forward) | Brief risk "Permission denials stall unattended runs" has docs coverage (E7-S1, architecture §8 row) but no test/evidence story; the other §8 failure rows are exercised by E7-S4 or bats. | Optionally add a permission-denial simulation to E7-S4; at minimum accept docs-only mitigation knowingly. |
| F-10 | minor | epics E1-S1 vs research §2 | E1-S1 says "Create … both JSON manifests", but research §2 records `plugin.json` (valid, v0.1.0) and the marketplace entry as already existing in the repo (verified: `.claude-plugin/marketplace.json` and `plugins/php-backend-sdlc/` exist). | Reword E1-S1 to "verify/complete existing scaffold"; AC unchanged. |

## Consistency check results

| Dimension | Result | Notes |
|---|---|---|
| Component counts 8/6/21 | PASS | Identical in brief G4, PRD NFR-1/FR-19, architecture §1.1 (8 command files, 6 agent files, 21 skill dirs + 2 loose guides), epics E7-S2. Story count "7 epics, 52 stories" verified by enumeration (5+7+11+11+6+7+5). Skill split 4 deep + 6 moderate + 11 light = 21 matches E3 (11) + E4 (10 skills + meta-guides). |
| Threshold numbers | PASS | Complexity 94, quality/architecture/style 100, deptrac 0, psalm 0, MSI 100 identical across brief A1, PRD FR-17/A1, architecture §4 example + ADR-7, epics E1-S4/E3-S2/E3-S3. The legacy 93 literal is explicitly corrected (ADR-7, E3-S2). |
| Profile key names (PRD FR-17 vs architecture §4) | PASS with note | All FR-17 keys appear verbatim in the architecture example (same nesting, same enums, same 12-entry `make` map). Architecture adds `schema_version` — legitimate under FR-17's "names final-pending architecture" delegation (OQ-1); E1-S4/E1-S5 carry it consistently. |
| Script names/paths | FAIL → F-1 | `ai-review-loop.sh`, `get-pr-comments.sh` consistent everywhere; gate script name diverges (PRD `bmad-fr-nfr-review-gate.sh` vs architecture/epics `fr-nfr-gate.sh`). All invocations consistently via `${CLAUDE_PLUGIN_ROOT}/scripts/`. |
| Agent model/tool matrices | PASS | Architecture §3 and epics E5 tables are identical (models sonnet/opus, comma-list tools). PRD FR-9..14 tool lists are subsets (architecture adds Glob/Grep — refinement, not contradiction). Six mandatory body sections consistent across PRD AC, architecture §3, E5 common contract. F-7 wording nit on qa-manual-tester only. |
| PRD AC → story reachability | PARTIAL → F-2, F-3, F-4 | Coverage table is complete at requirement level (FR-1..20, NFR-1..8 all mapped; spot-checked correct). Three AC clauses lack an owning story: FR-17's undeclared-key CI failure (F-2), FR-7 seeded defect and FR-8 failing-check/comment demonstrations (F-4); evidence-run AC determinism degraded by unpinned reference task (F-3). |
| ADR contradictions (11 ADRs) | PASS | Each ADR traced to ≥1 conforming story: ADR-1→E3/E4 runtime-read contract; ADR-2→E1-S4; ADR-3→E2-S3; ADR-4→E2-S4..S6; ADR-5→E6-S4; ADR-6→E2-S7; ADR-7→E1-S4/E3-S2; ADR-8→E2-S4; ADR-9→E1-S1/E7-S5; ADR-10→E2-S1/E2-S7; ADR-11→E4-S11/E7-S2. No story contradicts any ADR (F-8 is an unstated mechanic, not a contradiction). Dependency-direction rules (§1.2) respected by all stories. |
| Dependency order | PASS | All declared deps resolve to earlier waves: E1-S2/S4←wave 1; E2-S2←E1-S4 (wave 2); E3-S6/E5-S3←E2-S6, E5-S6←E2-S4/S5 (waves 3–4 before wave 5); E6←E2–E5; E6-S7←E6-S1..S6+E2-S7; E7 chain ordered, E7-S5 last. No story depends on a later wave. Wave-9 shared evidence file has an explicit section-ownership mitigation. |
| Open-question closure | PARTIAL → F-3 | PRD OQ-1/OQ-2/OQ-3 all resolved (ADR-2, ADR-8, ADR-9). Brief OQ-2 (reference task) silently dropped between brief and PRD. |

## Risk register status (brief §8 → owners)

| Risk | Carried forward | Owner (mitigating stories) |
|---|---|---|
| Token cost of 21-skill gate | YES | ADR-5/NFR-5 → E6-S4, E4-S11; evidenced E7-S4 |
| bmalph/claude version drift | YES | ADR-10/NFR-7 → E2-S1, E2-S7; CI no-vendor check E1-S2 |
| Target-repo variance | YES | FR-17/NFR-4 → E2-S2; gated skills E3-S10/S11, E4-S2/S4/S7/S9 |
| Copy-drift recurrence | YES | NFR-2 → E1-S2 audit + every E3/E4/E5/E6 common AC |
| Fresh repos lack CI/CodeRabbit | YES | NFR-4 → E5-S5, E5-S6, E6-S6; evidenced E7-S4 |
| Permission denials stall runs | PARTIAL (F-9) | ADR-6, architecture §8 row, docs E7-S1 — no test/evidence story |
| Marketplace install-mode divergence | YES | ADR-9 → E1-S1, E7-S5, docs E7-S1 |
| Governance block conflicts | YES | ADR-3 → E2-S3 (idempotency + duplicate repair, bats) |

## Conditions for READY

1. **C-1 (before wave 1, fixes F-1):** Canonicalize the gate script name to `fr-nfr-gate.sh` — amend PRD FR-18 and the FR-15 `bmad-fr-nfr-review-gate` bullet (or record the rename as an architecture note PRD readers are pointed to).
2. **C-2 (before wave 2, fixes F-2):** Add the profile-keys doc-check to architecture §6 and epics E1-S2 so FR-17's "undeclared key fails CI" AC has an implementing job and owning story.
3. **C-3 (before wave 8, fixes F-3):** Pin the G3 reference task in E7-S3 (small CRUD resource on `php-service-template`, must yield ≥2 independent stories for FR-5's parallel AC).
4. **C-4 (before wave 9, fixes F-4):** Extend E7-S4/E7-S3 ACs to enumerate the FR-7 seeded-defect run and the FR-8 failing-check + unresolved-comment run, keeping PRD §4 gate item 1 satisfiable.

Minor findings F-5..F-10 are non-gating; fix opportunistically during the affected stories.

## Conditions resolved 2026-06-10

All four conditions (C-1..C-4) and all six minor findings closed by artifact amendments:

| ID | Resolution |
|---|---|
| F-1 | Gate script canonicalized to `fr-nfr-gate.sh` in PRD FR-18 and brief §6.6; rename decision recorded in architecture ADR-4 (shorter name, shipped in plugin `scripts/`). |
| F-2 | `profile-keys-check` added as 7th CI job in architecture §6 and epics E1-S2 (description, AC, deps E1-S5, files); PRD FR-20 and the coverage table (FR-17 → +E1-S2) updated. |
| F-3 | Reference task pinned in E7-S3 — small CRUD resource (e.g. `Currency`: code+name, REST CRUD) on a fresh `php-service-template` clone, sized to yield ≥2 independent stories for FR-5 parallel dispatch; mirrored in PRD §8.4 (brief OQ-2 resolved). |
| F-4 | E7-S4 extended with explicit FR-7 seeded-defect QA run (must FAIL with reproduction steps) and FR-8 finish-pr run (≥1 failing check + ≥1 AI reviewer comment → all green + 0 unresolved); coverage table FR-7/FR-8 → +E7-S4. |
| F-5 | PRD FR-20 AC now reads "All seven CI jobs (six check areas)"; epics E1-S2 and E7-S5 counts updated to seven. |
| F-6 | Executive summaries corrected to "7 shipped scripts (3 generalized review scripts + 4 new setup scripts)" in brief §0/§5/§6 and PRD §1. |
| F-7 | Architecture §3 qa-manual-tester row reworded: read-only tool surface (no Edit/Write); report-only contract; logs/specs-only Read scope is a prompt-level rule. |
| F-8 | frontmatter-check glob made explicit in architecture §6 and epics E1-S2: skills matched as `skills/*/SKILL.md` only; loose ADR-11 meta-guides at `skills/` root exempt (must have no frontmatter). |
| F-9 | E7-S4 AC adds permission-denial behavior evidence: one run with default `acceptEdits` documenting any prompts encountered — risk closed with evidence, not docs-only. |
| F-10 | E1-S1 reworded from "create" to "validate/extend existing" for `marketplace.json` + `plugin.json` (both already exist per research §2). |
