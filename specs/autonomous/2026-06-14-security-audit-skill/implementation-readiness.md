---
stepsCompleted: [step-01-document-discovery, step-02-cross-artifact-consistency, step-03-ac-traceability, step-04-profile-key-spec-check, step-05-integration-delta-verification, step-06-nfr2-generalization-enforceability, step-07-safety-boundary-check, step-08-ci-mechanism-grounding, step-09-dependency-order, step-10-verdict]
inputDocuments:
  - specs/autonomous/2026-06-14-security-audit-skill/research.md
  - specs/autonomous/2026-06-14-security-audit-skill/product-brief.md
  - specs/autonomous/2026-06-14-security-audit-skill/prd.md
  - specs/autonomous/2026-06-14-security-audit-skill/architecture.md
  - specs/autonomous/2026-06-14-security-audit-skill/epics.md
groundTruthVerified:
  - plugins/php-backend-sdlc/tests/component-counts.bats (current 8/6/21 assertions)
  - plugins/php-backend-sdlc/docs/profile-schema.md (make map + capabilities conventions)
  - plugins/php-backend-sdlc/agents/qa-manual-tester.md + code-quality-reviewer.md (agent anatomy)
  - .github/workflows/ci.yml (profile-keys-check, generalization-audit, frontmatter-check job bodies)
  - .github/workflows/prompt-quality.yml (no SKILL line-count job)
  - plugins/php-backend-sdlc/{skills/SKILL-DECISION-GUIDE.md, skills/AI-AGENT-GUIDE.md, commands/sdlc-review.md, README.md} (count strings)
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/architecture.md (parent count strings)
workflowType: 'implementation-readiness'
date: 2026-06-14
author: Winston (BMAD Architect — readiness gate, autonomous run — no human pauses)
---

# Implementation Readiness — `security-audit` Skill (+ `security-auditor` Agent) for `php-backend-sdlc`

## Verdict: READY

Initial pass (2026-06-14): **READY-WITH-CONDITIONS** — two gating findings (F-1, F-2) where an AC asserts a CI mechanism that does not exist in the actual plugin CI, plus six minor findings. All eight findings are closed below by surgical, story-local AC amendments (no scope change, no new epic). The plan is implementation-ready for waves 1–5; the gating fixes are wording/AC corrections that the implementing stories must carry, recorded as conditions C-1/C-2.

The plan is unusually clean: the artifact chain is internally consistent on the load-bearing dimensions (component counts 8/7/22, the two new profile keys, the find→verify→fix→regress→loop discipline, the authorized-use boundary, NFR-2/NFR-4 generalization). Every gap found is a mismatch between an artifact's *claim about the existing CI* and the CI as it actually stands on disk — caught only by grounding each AC against `.github/workflows/`.

## Findings

| ID | Severity | Artifact | Description | Required fix |
|---|---|---|---|---|
| F-1 | major | prd.md FR-1 AC / NFR-9 AC; architecture §4 ("CI line-count check"), §4 closing line, §12; epics E1-S1 AC, E6-S1 AC/desc | Four ACs assert a **"CI line-count check"** that `wc -l SKILL.md ≤ ~500`. **No such job exists** in `.github/workflows/ci.yml` or `prompt-quality.yml` (verified: zero `wc -l`/`500`/`line-count` hits). NFR-9 and the PRD §4 release gate item 2 list this as a *CI-automated* AC; it is currently a manual/authoring constraint only. | Either (a) reframe the four ACs from "CI line-count check" to "author-enforced ≤ ~500-line budget, spot-checked in E6-S1 with `wc -l`" (cheapest, no CI change), **or** (b) add a one-line `wc -l` gate to `prompt-quality.yml`/`ci.yml` as part of E6-S1 and keep the "CI" wording. C-1 picks (a) — matches the PRD's own "~500" softness and adds no CI surface. |
| F-2 | major | architecture §3 (agent row 1 "so `profile-keys-check` is green"), §8 ("Both keys appear in the skill's *and agent's* `## Profile keys consumed` headers so `profile-keys-check` greps clean"), §12; epics E3-S1 AC ("`## Profile keys consumed` greps clean against `docs/profile-schema.md`") | `profile-keys-check` (ci.yml L223) iterates **`skills/*/SKILL.md` ONLY** — it never scans `agents/*.md`. The agent's `## Profile keys consumed` header is therefore **not** grepped by that job, so the E3-S1 AC "the agent's header greps clean via `profile-keys-check`" is **not verifiable by the named job**. The skill's header (FR-9, E1-S1) *is* covered and is correct. | Amend E3-S1 AC and architecture §3/§8/§12: the *skill's* `## Profile keys consumed` is the `profile-keys-check`-gated header (FR-9). The agent SHOULD carry the same `## Profile keys consumed` section for parity/readability, but its CI guarantee is `frontmatter-check` (name/description/tools/model) + manual consistency, **not** `profile-keys-check`. Drop the "agent header greps clean via profile-keys-check" claim. |
| F-3 | minor | architecture §9 ("generalization-audit … runs over all NEW files (skill, agent, reference, **schema edits**)") + §12; epics E6-S1 ("generalization-audit exits 0 over the new skill/agent/reference/**schema** files") | `generalization-audit` (ci.yml L294) scopes `find "$PLUGIN/skills" "$PLUGIN/commands" "$PLUGIN/agents" "$PLUGIN/scripts"` — it does **not** cover `docs/` (profile-schema.md) or `README.md` or `specs/`. The new skill/agent/reference files ARE in scope (all under `skills/`+`agents/`); the **schema-edit** and README sub-claims are out of audit scope. | Reword §9/§12/E6-S1: the audit covers the new skill, agent, and three reference files (in scope). `docs/profile-schema.md` and `README.md` are out of the audit's path scope (and the schema only carries denylisted values inside its `# profile-example` fence anyway). Non-gating — the NFR-4 core (skill/agent/reference clean) holds. |
| F-4 | minor | epics E5-S5 vs parent architecture.md count strings | E5-S5 enumerates parent edits as "§1.1 tree, §3 agent matrix, '6 subagents'→7 / '21 skills'→22" but parent architecture also carries **"21 verdicts"** (L270) and **"all 21 skills"** (L305) — count-bearing strings E5-S5 does not name. A CI count-consistency grep (FR-10 AC) would still see stale 21s. | Extend E5-S5's file edit list to "every `6`/`21` component-count string in the parent architecture, incl. L270 'triage 21 verdicts' and L305 'all 21 skills get recorded verdicts'." (Note: L252 frontmatter-check description "counts 8/6/21" is *describing the parent's own CI job state at v1* — leave or update consistently; flag for the implementer.) |
| F-5 | minor | epics E5-S2 vs SKILL-DECISION-GUIDE.md L118 | E5-S2 says "every skill-count `21` occurrence → 22; add a row." But L118 is a **verbatim alphabetical list of all 21 skill names** ("…`testing-workflow`."). Bumping the count to 22 without inserting `security-audit` into that inline name list leaves the prose self-contradictory ("All 22 skills appear above" then lists 21 names). | E5-S2 AC: also insert `security-audit` into the L118 alphabetical skill-name enumeration (between `quality-standards`/`query-performance-analysis` region — alpha order). |
| F-6 | minor | README.md count strings vs epics E5-S5 | The plugin README has count-bearing strings the deltas must catch: L55 "`/sdlc-review` … **21-skill** triage", L61 "Commands delegate to **six subagents** (…) and a **21-skill** library", and the parenthetical six-agent name list. E5-S5 says "component counts wherever stated" (correct in spirit) but does not enumerate these exact strings; "six subagents" is spelled-out, not `6`, so a naive `\b6\b` grep misses it. | E5-S5 AC: explicitly include README L55 ("21-skill"→"22-skill"), L61 ("six subagents"→"seven subagents", "21-skill library"→"22-skill library"), and add `security-auditor` to the spelled-out subagent name list. The FR-10 "no stale count" grep must cover spelled-out numbers, not just digits. |
| F-7 | minor | architecture §3 / epics E3-S1 "8-section spine" vs actual agent anatomy | Artifacts name an "8-section spine" (Profile keys consumed, Role, Inputs, Outputs, Allowed actions, Degrade paths, Iteration discipline, Smoke prompt). The real precedents have **more** H2s (qa-manual-tester: 12, incl. Checks/Failures/Verdict between them). VERIFIED: all 8 named sections exist in BOTH precedents — the 8 are a valid **mandatory subset**, not the complete section set. No contradiction; only the word "spine" could mislead an implementer into omitting precedent sections like a Verdict/status block. | Non-gating. Optionally note in E3-S1 that the 8 are the *mandatory* sections and the author may add precedent-style sections (e.g. a status/verdict block) as the precedents do. |
| F-8 | minor | epics E6-S2/E6-S3 shared evidence file vs parent NFR-7 tree-hygiene | E6-S2/E6-S3 both write `plugins/php-backend-sdlc/docs/evidence/security-audit-dogfood-run.md` inside the **plugin tree**. The `generalization-audit` job also runs an NFR-7 tree-hygiene check (no `_bmad`/`.ralph`) and the NFR-2 denylist over `skills/commands/agents/scripts` — `docs/` is out of denylist scope, so an evidence doc with real reproduction output (which may legitimately contain a target's identifiers) will NOT trip the audit. Confirmed safe, but the evidence doc location should be a deliberate choice. | Non-gating — confirmed the evidence doc path (`docs/evidence/`) is outside the denylist scope, so dogfood output won't fail generalization-audit. Section-ownership mitigation (S2=run log, S3=NFR appendices) already in epics §"Parallelization plan". Accept as-is. |

## Cross-artifact consistency results

| Dimension | Result | Notes |
|---|---|---|
| Component counts 8/7/22 | PASS | Identical across brief G6, PRD NFR-1/FR-10, architecture §1.1/§9, epics E5-S1/E6-S1. Current on-disk baseline VERIFIED 8 cmd / 6 agent / 21 skill / 2 loose guides; deltas are +0 cmd, +1 agent (security-auditor), +1 skill (security-audit). bats assertion targets (`-eq 6`→7 L57-61, `-eq 21`→22 L63-67, header L4-13) match epics E5-S1 exactly. |
| New skill = 1 dir w/ SKILL.md | PASS | `skills/security-audit/SKILL.md` (frontmatter `name: security-audit` = dir name — `component-counts.bats` L109-117 name-matches-dir assertion satisfied). Three `reference/*.md` under it are NOT counted as skills (glob is `skills/*/SKILL.md`) — correct. |
| New agent = 1 file w/ 4 frontmatter keys | PASS | `agents/security-auditor.md` with `name`/`description`/`tools: Bash, Read, Glob, Grep`/`model: opus` — satisfies `frontmatter-check` L191-194 and bats L97-101. Tools exclude Edit/Write (SA-3 report-and-route) — consistent across PRD FR-3, architecture §3/§11, epics E3-S1. |
| Agent 8-section spine | PASS (F-7 nit) | All 8 named sections VERIFIED present in both qa-manual-tester and code-quality-reviewer; they are a mandatory subset of the precedent anatomy. Order in architecture §3 table matches. |
| Profile key names + conventions | PASS | `make.security` (nullable, default `null`, after `make.load_tests`) and `capabilities.dynamic_security_testing` (bool, default `false`, after `capabilities.load_testing`) match the schema's existing row shape exactly (verified against profile-schema.md L66-79 make map + L122-128 capabilities). Null-substitution precedent (`ai_review_loop`/`pr_comments`/`fr_nfr_gate`) cited correctly. Name SA-9 (`dynamic_security_testing` over `dast`) matches house style (`load_testing`/`structurizr`). |
| `# profile-example` block edits | PASS | Architecture §8 / E4-S1 add `security: null` to `make:` and `dynamic_security_testing: false` to `capabilities:` — inside the existing fenced `# profile-example` block (schema L136-185), so denylist-exempt. Correct. |
| FR → story reachability | PASS | Coverage table (epics §"Coverage table") maps FR-1..10 + NFR-1..9 each to ≥1 story; reverse check holds (every story → ≥1 req). Spot-verified: FR-3→E3-S1, FR-9→E4-S1, FR-7/FR-8→E1-S1+E6-S2, NFR-2→E1-S1/E3-S1/E6-S3. No orphan requirement. |
| AC names files + AC | PASS | Every story names exact file path(s) under `## Files` and a testable `## AC`. E1-S1 (SKILL.md), E2-S1/S2/S3 (3 reference files), E3-S1 (agent), E4-S1 (schema), E5-S1..S5 (count/guide files), E6-S1..S3 (CI run + evidence doc). |
| New profile keys fully specified | PASS | Both keys specified end-to-end: schema row (required/nullable/default/notes) + example line + skill `## Profile keys consumed` header + agent header + degrade behavior (§10 matrix) + the OQ-1 name decision (SA-9). FR-9 AC fully decomposed in E4-S1. |
| `profile-keys-check` coverage | PARTIAL → F-2 | The SKILL header IS gated (job scans `skills/*/SKILL.md`); FR-9/E1-S1 correct. The AGENT header is NOT scanned by that job — E3-S1's "agent header greps clean via profile-keys-check" over-claims (F-2). |
| CI line-count gate | FAIL → F-1 | NFR-9 / FR-1 / architecture §4/§12 / E1-S1 / E6-S1 cite a "CI line-count check" that does not exist in any workflow. |
| Integration count-delta locations | PARTIAL → F-4, F-5, F-6 | bats (E5-S1) and the two guides' headers (E5-S2/S3) are correctly located. Gaps: SKILL-DECISION-GUIDE inline 21-name list (F-5), parent-architecture L270/L305 strings (F-4), README spelled-out "six subagents"/"21-skill" (F-6). All caught at AC level; none changes scope. |
| NFR-2 generalization enforceability | PASS (F-3 scope nit) | `generalization-audit` denylist (`user[-_ ]service|mongo…repository|apprunner|src/user|src/oauth|vilnacrm`, ci.yml L286) runs over `skills/commands/agents/scripts` — the new skill, agent, and 3 reference files are ALL in scope and machine-enforced. PRD NFR-4 denylist matches the regex. The "schema edits in audit scope" sub-claim is inaccurate (F-3) but non-gating: schema denylisted values live only inside the `# profile-example` fence (audit strips fenced examples, L271-280). Enforceable: YES, for the four PRD component dirs. |
| Authorized-use safety boundary explicit | PASS | NFR-5 states the four boundary rules verbatim (in-scope target only, no exfiltration, mutate-via-API-only, container-only). Restated in: PRD FR-3/NFR-5, architecture §3 row 2 + §10 last row + ADR SA-10 (enforced at Allowed-actions/Constraints level, not advisory), SKILL §2 `## Gating` + §6 `## Constraints`, agent §2 Role + §5 Allowed actions. Both SKILL.md and security-auditor.md carry it (E1-S1, E3-S1 ACs). Defensive/authorized framing in skill+agent `description`. Boundary is a *forbidden action*, not just prose — strongest available enforcement. |
| ADR ↔ story conformance (SA-1..SA-10) | PASS | Each ADR traced: SA-1→E1-S1/E5-S4 (no command, triaged); SA-2→E4-S1/E1-S1 (null=bundled static lane, no script); SA-3→E3-S1 (no Edit/Write); SA-4→E1-S1/E3-S1 (grey-box, reproduce-to-promote); SA-5→E1-S1 §6 contract; SA-6→E1-S1 (affected re-verify + final make.ci); SA-7→E1-S1/E3-S1 (LLM gating); SA-8→E2-S1/E1-S1 (band+rationale); SA-9→E4-S1 (key name); SA-10→E1-S1/E3-S1 (boundary). No story contradicts any ADR. |
| Dependency order | PASS | Wave plan E4 → (E1 ∥ E2 ∥ E3) → E5 → E6 is acyclic; all deps resolve to earlier waves. E1-S1/E3-S1 dep E4-S1 (schema keys must exist for headers) — correct. E2 cites key NAMES in prose only (no content dep) — parallel-safe. E5 waits for E1+E3 (components must exist). E6 last. Wave-5 shared evidence doc has section-ownership mitigation. |
| OQ closure (OQ-1..6) | PASS | All six PRD Open Questions resolved as ADRs: OQ-1→SA-9, OQ-2→SA-2, OQ-3→SA-7, OQ-4→SA-6, OQ-5→SA-5/§6, OQ-6→SA-8. No dangling question carried into epics. |
| `make.ci` re-run policy | PASS | SA-6 (affected-family re-verify each iteration + one final `make.ci` at loop close) is consistent across architecture §5.6/§5.3/§6 and E1-S1; resolves the brief/PRD cost-vs-safety OQ deterministically. |

## Conditions for READY

1. **C-1 (fixes F-1, before E1-S1 / E6-S1):** Reframe the four "CI line-count check" ACs (PRD FR-1 AC + NFR-9 AC, architecture §4/§12, E1-S1, E6-S1) to "author-enforced ≤ ~500-line budget, verified with `wc -l` during E6-S1" — OR add a one-line `wc -l` gate to a workflow if a hard CI gate is wanted. Remove the implication that an existing CI job enforces the line count.
2. **C-2 (fixes F-2, before E3-S1):** Correct the agent `profile-keys-check` claim. The *skill's* `## Profile keys consumed` is the `profile-keys-check`-gated header (FR-9, E1-S1, unchanged). The *agent* carries the same section for parity but its CI guarantee is `frontmatter-check` only; drop "agent header greps clean via profile-keys-check" from architecture §3/§8/§12 and E3-S1 AC.

Minor findings F-3..F-8 are non-gating; fold the fixes into the affected stories (F-4/F-6→E5-S5, F-5→E5-S2, F-3→E6-S1 wording, F-7→E3-S1 note, F-8 accept-as-is).

## Conditions resolved 2026-06-14

Both conditions and all six minor findings are closed by story-local AC amendments (no scope, epic, or wave change):

| ID | Resolution |
|---|---|
| F-1 / C-1 | "CI line-count check" → "author-enforced ≤ ~500-line budget, `wc -l`-spot-checked in E6-S1" in PRD FR-1/NFR-9 ACs, architecture §4 + §12, E1-S1 AC, E6-S1 AC. PRD §4 release-gate item 2 moves the line-count from "CI-automated" to "run-documented (E6-S1 spot-check)". No new CI job added (matches SA-style minimal-surface preference). |
| F-2 / C-2 | Skill header remains the `profile-keys-check`-gated artifact (FR-9 unchanged). Architecture §3/§8/§12 + E3-S1 AC reworded: agent carries `## Profile keys consumed` for parity; its CI guarantee is `frontmatter-check` (name/description/tools/model) + manual consistency, not `profile-keys-check`. |
| F-3 | Architecture §9/§12 + E6-S1 reworded: generalization-audit covers the new skill + agent + 3 reference files (in `skills/`+`agents/` scope); `docs/profile-schema.md` + `README.md` are outside the audit path (schema's denylisted values are fence-exempt regardless). |
| F-4 | E5-S5 file-edit list extended: "every `6`/`21` count string in parent architecture, incl. L270 'triage 21 verdicts' and L305 'all 21 skills'"; L252 frontmatter-check-description count flagged for consistent update. |
| F-5 | E5-S2 AC extended: insert `security-audit` into the L118 alphabetical skill-name enumeration, not just the count number. |
| F-6 | E5-S5 AC extended: README L55 "21-skill"→"22-skill", L61 "six subagents"→"seven subagents" + "21-skill library"→"22-skill library", add `security-auditor` to the spelled-out subagent name list; FR-10 "no stale count" grep must cover spelled-out numbers. |
| F-7 | E3-S1 note added: the 8 sections are the *mandatory* spine; the author may add precedent-style sections (status/verdict block) as qa-manual-tester/code-quality-reviewer do. |
| F-8 | Accepted as-is: `docs/evidence/security-audit-dogfood-run.md` is outside the NFR-2 denylist + NFR-7 tree-hygiene path scope, so dogfood reproduction output cannot fail generalization-audit; section-ownership (S2 run log / S3 NFR appendices) already mitigates the shared-file merge risk. |

## Risk register status (brief §8 → owners)

| Risk | Carried forward | Owner (mitigating stories / ADR) |
|---|---|---|
| False positives (#1 pentest failure mode) | YES | FR-7/NFR-6, SA-4 → E1-S1 (reproduce-to-promote), E3-S1 (agent verify-before-report), E6-S2 (non-reproducible candidate dropped, evidenced) |
| Destructive / out-of-scope probing | YES | NFR-5, SA-10 → E1-S1 §Gating/§Constraints, E3-S1 §Role/§Allowed-actions, E6-S2 (no out-of-profile/destructive op, evidenced) |
| Token/time cost of opus fan-out × 5 | YES | NFR-8, SA-6/SA-7 → E1-S1 (triage-first, only still-open re-dispatch, one final make.ci), E6-S3(c) evidence |
| Capability variance (no make.security/SAST/service/GraphQL) | YES | NFR-3, SA-2 → E4-S1 (nullable key + capability gate), E1-S1/E3-S1 degrade paths, E6-S3(b) three degrade envs |
| Fix-induced regressions / scope creep | YES | FR-8/NFR-7 → E1-S1 (regression test per fix + final make.ci), E2-S3 (suppression-free remediation), E6-S2 |
| Suppression temptation under time pressure | YES | NFR-7, parent ADR-7 → E2-S3 (verbatim "zero suppression"), E1-S1 (forbidden-suppression scan inherited from code-review Step 6), E6-S2 (zero suppressions evidenced) |
| Corpus drift (OWASP/CWE editions) | YES | NFR-9 → E2-S1/S2/S3 (edition-labelled reference files, enumerations out of SKILL.md) |
| Component-count / guide drift | YES (F-4/F-5/F-6 sharpen it) | FR-10/NFR-1 → E5-S1..S5, gated by component-counts.bats + the FR-10 no-stale-count grep |
| CI mechanism over-claim (line-count, agent profile-keys) | NEW (F-1/F-2) | C-1/C-2 — closed by AC rewording above |
</content>
</invoke>
