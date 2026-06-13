---
stepsCompleted: [step-01-init, step-02c-executive-summary, step-03-success, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish, step-12-complete]
inputDocuments:
  - specs/autonomous/2026-06-14-security-audit-skill/research.md
  - specs/autonomous/2026-06-14-security-audit-skill/product-brief.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md
workflowType: 'prd'
date: 2026-06-14
author: John (BMAD PM agent, autonomous run — interactive steps skipped, decisions recorded inline)
---

# Product Requirements Document — `security-audit` Skill (+ `security-auditor` Agent) for `php-backend-sdlc`

## 1. Executive Summary

Add the plugin's missing **adversarial security lens** to the existing `php-backend-sdlc` plugin (v1: 8 commands, 6 agents, 21 skills + 2 meta-guides, generalized to any PHP backend via `.claude/php-sdlc.yml`). A new skill `skills/security-audit/SKILL.md` runs an adversarial, **multi-subagent** red-team / penetration-testing loop over the target PHP backend — the plugin user's own authorized repo, **defensive/authorized use only**. The skill fans out one `security-auditor` subagent per OWASP/vuln family in parallel (reusing the plugin's existing parallel-`php-implementer` idiom — no new infrastructure); each subagent attacks the running service (black-box HTTP probing, the `qa-manual-tester` shape) **and** inspects source (SAST/taint, dependency, secret, config — the `code-quality-reviewer` shape), **verifies** every candidate by reproduction against the running service (no false positives), maps it to CWE + OWASP id + CVSS-ish severity, then the skill drives **root-cause, suppression-free fixes** (routed through the existing `php-implementer`), attaches a **regression test per fix**, re-tests, and re-dispatches only still-open families until a clean pass. Coverage spans the **entire OWASP corpus across the years** (Top 10 every edition 2003→2021, API Top 10 2019/2023, LLM Top 10, Mobile as N/A-for-backend, ASVS 5.0, WSTG 4.2, Proactive Controls/Cheat Sheets) plus CWE Top 25 2024 / SANS — enumerated in three `reference/` files so SKILL.md stays under ~500 lines. Two minimal new profile keys (a nullable `make.security` target and a dynamic-testing capability gate) extend the schema per existing conventions. Brief goals G1–G6 govern this PRD; every FR/NFR traces to them (§5).

## 2. Functional Requirements

### 2.1 The skill — `skills/security-audit/SKILL.md`

**FR-1 — `security-audit` skill, adversarial multi-subagent red-team loop** (G1, G2, G3, G4)
A new triaged skill loadable as `php-backend-sdlc:security-audit`, kept under ~500 lines, in the verified skill format (YAML frontmatter `name`/`description` + `## Profile keys consumed` + Context/Task/Success-Criteria/Steps/Constraints/Verification, relative cross-links to its `reference/` files). It reads `.claude/php-sdlc.yml` at runtime (no per-repo rendering) and runs the canonical security loop:

1. **Triage** — for every OWASP family in `reference/owasp-catalog.md`, record an explicit verdict: PROBE or N/A-with-reason (LLM family gated on detected LLM usage; OWASP Mobile and memory-safety CWEs N/A-with-reason for managed PHP). No silent skips.
2. **Fan-out** — dispatch one `security-auditor` subagent per PROBE family in parallel (BOLA/IDOR, BOPLA/mass-assignment, BFLA, SQLi, SSTI, deserialization, SSRF, auth/session, misconfiguration, vulnerable deps, secrets, file upload, rate/resource, GraphQL-when `framework.graphql`, LLM-when-detected).
3. **Find → verify** — each subagent runs source-aware SAST/dep/secret/config analysis **and** adversarial dynamic probing; a SAST candidate is **never** a finding until reproduced against the running service.
4. **Fix → regression-test** — the skill drives root-cause, secure-by-default fixes through `php-implementer`; each fix carries a failing-then-passing regression test.
5. **Re-verify → loop** — the affected family re-verifies; only still-open families re-dispatch; the loop is bounded `MAX_ITERATIONS=5` (NFR-2) and exits when an iteration yields zero new verified findings, or escalates on breach.

**AC:** A dry-run prompt walk-through shows the triage→fan-out→find→verify→fix→regress→re-verify→loop sequence, the per-family verdict table, the `MAX_ITERATIONS=5` counter, and the zero-new-findings exit condition; the skill loads as `php-backend-sdlc:security-audit`; SKILL.md is ≤ ~500 lines (CI line-count check) and every enumeration is delegated to a `reference/` file.

**FR-2 — Placement within the SDLC** (G6)
`security-audit` is a **skill, not a new command** (no `/sdlc-security` surface). It is triaged inside the existing verification gate (Stage 4 `/sdlc-review`) — `/sdlc-review`'s applicability triage records an EXECUTE-or-NOT-APPLICABLE verdict for it like every other skill, and it may be invoked standalone. It owns the find→verify→fix→regress→loop; `security-auditor` subagents are find/verify only; code edits route through `php-implementer`.
**AC:** SKILL.md documents its placement (triaged inside Stage 4, no new command) and its fix-routing through `php-implementer`; the command surface count remains 8 (no command added); the `/sdlc-review` triage list includes a `security-audit` row.

### 2.2 The agent — `agents/security-auditor.md`

**FR-3 — `security-auditor` red-team subagent** (G1, G2, G3, G4)
A new agent mirroring the plugin's verified agent anatomy (read against `qa-manual-tester.md` / `code-quality-reviewer.md`): frontmatter `name`/`description`/`tools`/`model`; an 8-section body spine — **Profile keys consumed, Role, Inputs, Outputs, Allowed actions, Degrade paths, Iteration discipline, Smoke prompt**. Tools combine both precedents: `Bash, Read, Glob, Grep` (SAST/dep/secret/config + dynamic probing). Model **opus** (judgment-heavy, like `code-quality-reviewer`/`fr-nfr-reviewer`).

- **Role:** the red-team unit dispatched in parallel — one per OWASP family — attempting to break the running service for its family and inspecting source for the same class. White/grey-box by design (MAY read source, unlike `qa-manual-tester`), but inherits the "verdict from observed behavior, no false positives" rule and the "mutate state only through the service's own API" rule.
- **Inputs:** the assigned OWASP family + its `reference/attack-playbooks.md` entry, the running service endpoint, project profile (`architecture.*`, `framework.*`, `persistence.*`, `make.*`, the new `make.security` + dynamic-testing capability), source tree.
- **Outputs:** verified findings only — each with reproduction steps, CWE id + OWASP id + CVSS-ish severity (band + rationale), and the cited remediation (OWASP cheat sheet / vetted library) from `reference/remediation-patterns.md`; or a clean-for-this-family verdict. Report-and-route: it does **not** edit code.
- **Degrade paths:** `make.security: null` ⇒ run bundled/static fallback for its family; dynamic-testing capability false or `make.start: null` ⇒ static-only with a skip-note for dynamic probing; family N/A ⇒ recorded reason, no fabricated finding.
- **Iteration discipline:** bounded by the skill's `MAX_ITERATIONS=5`; re-dispatched only while its family stays open; never auto-resets a breaker.

**AC:** `security-auditor.md` contains all eight body sections plus the four frontmatter keys; it loads in the `claude` agent listing; a smoke prompt exercises one family's happy path (verified finding with reproduction + CWE/OWASP/severity + cited remediation) plus one degrade path (`make.security: null` static-only); the agent never emits a finding lacking a reproduction and never contains a code-edit action.

### 2.3 Reference corpus — `skills/security-audit/reference/`

**FR-4 — OWASP / CWE catalog** (G2)
`reference/owasp-catalog.md` enumerates the full corpus with **edition labels** so refreshes are localized: OWASP Top 10 web 2003/2004/2007/2010/2013/2017/2021; API Security Top 10 2019/2023; LLM Top 10 (2025 v2.0); OWASP Mobile (2014/2016/2024, marked N/A-for-backend with reasoning); ASVS 5.0 (L1/L2/L3, L2 default bar) as the coverage checklist; WSTG 4.2 as the test-methodology index; Proactive Controls / Cheat Sheet Series as the remediation source-of-truth pointer; CWE Top 25 2024 (ordered, with PHP relevance and memory-safety CWEs marked N/A-with-reason); SANS treated as the same CWE/SANS Top 25 taxonomy.
**AC:** Every listed family/edition appears with its label; each OWASP family carries its mapped CWE id(s); memory-safety CWEs and Mobile carry an explicit N/A-with-reason note; the file is the single source the skill's triage table draws from.

**FR-5 — Attack playbooks** (G1, G2)
`reference/attack-playbooks.md` holds the per-family probing methodology (WSTG-test-id mapped) the `security-auditor` executes against this stack — BOLA/IDOR (IRI/object-id swap), BOPLA/mass-assignment (denormalization write-group probing), BFLA (`security`/`#[IsGranted]` bypass), SQLi (taint to DQL/native sinks), SSTI, insecure deserialization, SSRF, auth/session (JWT `none`/alg-confusion, hashing, expiry, fixation), misconfiguration (`APP_ENV`/profiler/CORS/headers/TLS), vulnerable deps, secrets, file upload, rate/resource, GraphQL (introspection/deep-query/batching). Each entry states the probe **and** the verification step that reproduces it against the running service.
**AC:** Each PHP-relevant family from `reference/owasp-catalog.md` has a playbook entry with at least one concrete probe and an explicit reproduce-against-running-service verification step; entries name the tool (`curl`/`jq`/GraphQL POST, Psalm `--taint-analysis`, Semgrep, `composer audit`, secret scan) and stay stack-generic (profile-resolved paths, no source-project literals).

**FR-6 — Remediation patterns** (G3)
`reference/remediation-patterns.md` holds secure-by-default, root-cause fixes citing the relevant OWASP cheat sheet and vetted library per class — Symfony SecurityBundle `auto` password hasher, Doctrine parameterized queries/QueryBuilder (never concatenated DQL), Twig auto-escaping (never `|raw`/dynamic templates on user input), Symfony Serializer write groups (mass-assignment), API Platform voters/`security` expressions (BOLA/BFLA), Paragon Initiative crypto guidance — with the explicit prohibition on suppressions/baselines/threshold-lowering and the requirement that each fix carries a regression test.
**AC:** Every PHP-relevant family has a remediation entry naming a vetted library/framework primitive + the OWASP cheat sheet it derives from; the file states "root-cause only, zero suppression" and "every fix gets a failing-then-passing regression test" verbatim; no entry recommends a suppression, baseline, config-relaxation, or threshold reduction.

### 2.4 Find → verify → fix → re-test discipline

**FR-7 — Verify-before-report (no false positives)** (G1)
A SAST/dep/secret/config candidate is **never** a finding. Each candidate must be reproduced against the running service (or, for static-only classes such as committed secrets, deterministically demonstrated in-tree). A finding with no working reproduction is downgraded or dropped. Findings are reported only after verification, each with reproduction steps and its CWE + OWASP id + CVSS-ish severity.
**AC:** The skill's loop shows SAST output entering as candidates and only reproduced items promoted to findings; a seeded vulnerability (e.g. an unparameterized query reachable via an endpoint) is reported with working reproduction steps; a non-reproducible SAST candidate is recorded as downgraded/dropped, not reported.

**FR-8 — Root-cause fix + regression test loop** (G3)
Verified findings drive suppression-free, secure-by-default fixes through `php-implementer`. Every fix carries a failing-then-passing regression test that reproduces the exploit and then proves it closed. After a fix the affected family re-verifies; only still-open families re-dispatch; the loop is bounded `MAX_ITERATIONS=5`. The full quality gate (`make.ci`) and affected-family re-verify run before the loop closes.
**AC:** For a seeded vulnerability, the run shows: a root-cause code fix (no suppression/baseline/threshold edit), a regression test that fails before and passes after, the affected family re-verifying clean, and the loop closing with `make.ci` green; the forbidden-suppression scan (inherited from `code-review` Step 6 / ADR-7) reports zero suppressions introduced.

### 2.5 Profile keys

**FR-9 — New profile keys in `docs/profile-schema.md`** (G4, G6)
Two minimal keys added following existing conventions:
- `make.security` — a **nullable** row in the required `make` map for the repo's own security/SAST suite (e.g. `make security`); `null` ⇒ the plugin runs its bundled/static fallback or degrades that stage with a note, exactly mirroring `make.ai_review_loop`/`make.pr_comments`/`make.fr_nfr_gate` precedent.
- a `capabilities.*` boolean gating **dynamic** security testing (final name per architecture, leaning `capabilities.dynamic_security_testing`), pairing with `make.start` the way `capabilities.load_testing` pairs with `make.load_tests`. When false (or `make.start: null`), dynamic probing degrades to skip-with-note; static/SAST/dep/secret/config still run.
Both keys are documented in `docs/profile-schema.md` (table row + annotated `# profile-example` block) so the `profile-keys-check` CI job, which greps each skill's `## Profile keys consumed` header against that page, passes.
**AC:** `docs/profile-schema.md` lists both new keys with required/nullable marking and default, and the `# profile-example` block carries them; the skill's `## Profile keys consumed` header lists both; `profile-keys-check` is green (a skill key absent from the schema page fails CI).

### 2.6 Integration deltas

**FR-10 — Component-count and guide updates** (G6)
Apply, in one consistent change, all count and guide deltas for the new skill (21→22) and agent (6→7):
- `tests/component-counts.bats` — skills assertion `21`→`22`, agents assertion `6`→`7`, and the NFR-1 header comment ("8 commands / 6 agents / 21 skills" → "…7 agents / 22 skills…").
- `skills/SKILL-DECISION-GUIDE.md` — "All 21 skills…" → 22; add the `security-audit` triage row.
- `skills/AI-AGENT-GUIDE.md` — "Available Skills (21 Total)" → 22; add the `security-audit` usage entry and the `security-auditor` cross-agent entry.
- This feature's PRD **NFR-1** counts (6→7 agents, 21→22 skills) and the original plugin PRD/architecture references (architecture file-tree + agent matrix add the new agent).
- README/docs component counts.
**AC:** `tests/component-counts.bats` asserts 8 commands / 7 agents / 22 skills and passes against the install-cache layout; both guides show 22 with new rows; no document in the plugin tree states a stale 6-agent or 21-skill count (CI count-consistency / grep check).

## 3. Non-Functional Requirements

**NFR-1 — Installability / load integrity** (G6): After install, component discovery reports exactly **8/8 commands, 7/7 agents, 22/22 skills** (+ 2 loose meta-guides). The new skill loads as `php-backend-sdlc:security-audit`; the new agent appears in the `claude` agent listing.
**AC:** `claude plugin` listing + smoke prompt enumerate all components; counts asserted in `tests/component-counts.bats` (8/7/22) against the install-cache layout.

**NFR-2 — Loop safety** (G4): Every loop in the skill is bounded `MAX_ITERATIONS=5` per stage; on breach (or on a routed `php-implementer`/Ralph circuit-breaker trip), the run halts with a structured status report (open families, per-iteration finding counts, last blocking finding, recommended action). Breakers are surfaced, never auto-reset; only still-open families re-dispatch.
**AC:** A forced-non-converging-finding test stops at iteration 5 with the status report; re-dispatch logs show only still-open families being re-run; no automatic breaker reset occurs.

**NFR-3 — Degrade paths** (G4): Every external-capability dependency has a defined no-capability behavior, never a loop or hard-fail: `make.security: null` ⇒ bundled/static fallback (no dynamic dependency); dynamic-testing capability false or `make.start: null` ⇒ dynamic probing skip-with-note, static lanes still run; `framework.graphql: false` ⇒ GraphQL family N/A; no SAST configured ⇒ that lane degrades with a note. Absent capability is recorded, not errored.
**AC:** Three simulated environments (no `make.security`, no bootable service / dynamic capability false, no GraphQL) each complete the stage with explicit degrade notes and a SUCCESS-WITH-REPORT status; none hard-fails or loops.

**NFR-4 — Generalization** (G5): Zero source-project identifiers in `security-audit`/`security-auditor`/`reference/` + schema edits outside `# profile-example` fences. The CI-greppable denylist (`VilnaCRM`, `user-service`, `Mongo[A-Z]\w*Repository`, `AppRunner`, `workspace.dsl` container names, `src/User`, `src/OAuth`) must not appear; all paths/contexts resolve from the profile (`architecture.source_root`, `architecture.bounded_contexts`, `persistence.mapper`, `framework.api_platform`, `framework.graphql`).
**AC:** The `generalization-audit` CI job exits 0 over the new files; seeding a denylist token (e.g. `MongoUserRepository` in `attack-playbooks.md`) fails the audit; 100% of the new skill/agent/reference files pass.

**NFR-5 — Authorized-use-only safety boundary** (G1): The skill and agent read unambiguously as **defensive, authorized security research** run by the repo owner against their own service. Hard boundary, restated verbatim in SKILL.md and the agent prompt: never probe hosts/URLs outside the profile-resolved local service; no exfiltration; no destructive payloads beyond what is needed to prove a vuln on a disposable container instance; mutate state only through the service's own API; container-only execution (`make` / `docker compose exec php`, never host binaries).
**AC:** SKILL.md and `security-auditor.md` each contain the authorized/defensive framing and the four boundary rules (in-scope target only, no exfiltration, mutate-via-API-only, container-only); no playbook or agent action targets an out-of-profile host or performs a destructive non-API operation.

**NFR-6 — No-false-positive verification culture** (G1): No finding is reported or fixed without a reproduction; SAST/dep/secret/config output is a candidate only; full OWASP/CWE-family coverage is achieved by an explicit per-family verdict (PROBE or N/A-with-reason) — 100% triaged, no silent skips.
**AC:** Every family in `reference/owasp-catalog.md` receives a recorded verdict in a run; every reported finding carries reproduction steps + CWE + OWASP id + severity; a candidate without reproduction is demonstrably downgraded/dropped.

**NFR-7 — Root-cause / suppression-free culture** (G3): Fixes are root-cause and secure-by-default only — never a suppression annotation, baseline/ignore, config relaxation, `deptrac.yaml` edit, or threshold reduction (raise-only thresholds, ADR-7, bind here). Each fix cites a vetted library / OWASP cheat sheet and carries a regression test.
**AC:** A run on a seeded vuln introduces zero suppressions (forbidden-suppression scan clean), keeps all `quality.*` thresholds at/above default, and produces a regression test per fix; `remediation-patterns.md` recommends no suppression anywhere.

**NFR-8 — Token-cost bounds / triage-first** (G4): The fan-out is cost-controlled — N/A families (LLM-when-not-detected, Mobile, memory-safety CWEs) are gated out up front; SAST-first triage skips zero-candidate families before dynamic probing; only still-open families re-dispatch across iterations; opus subagents run in parallel rather than serially.
**AC:** A run shows N/A families excluded before fan-out, SAST-first candidate filtering documented, and the re-dispatch set shrinking to only still-open families across iterations.

**NFR-9 — Docs / SKILL line bound** (G6): SKILL.md stays under ~500 lines with all enumerations delegated to `reference/`; the three reference files carry edition labels; the two new profile keys and the new skill/agent are documented in `docs/profile-schema.md` and the two meta-guides.
**AC:** `wc -l skills/security-audit/SKILL.md` ≤ ~500 (CI line-count check); each reference file carries its edition labels; markdownlint passes; both new profile keys documented.

## 4. Acceptance Criteria and Release Gate

Acceptance criteria are embedded per requirement above; each **AC:** block is the binding, testable criterion for its FR/NFR. The release gate for this feature requires all of:

1. All FR ACs demonstrated (FR-1..10), with a seeded-vulnerability evidence run documenting find→verify→fix→regress→re-verify→loop (FR-7/FR-8/G1/G3).
2. CI-automated NFR ACs green: NFR-1 (component counts 8/7/22 via `component-counts.bats`), NFR-4 (generalization audit over the new files), NFR-9 (SKILL line-count + markdownlint), FR-9 (`profile-keys-check`) — all in the existing plugin CI.
3. Run-documented NFR ACs evidenced: NFR-2 (forced-loop stops at 5 with report), NFR-3 (three degrade environments), NFR-5 (authorized-boundary framing present, no out-of-scope action), NFR-6 (per-family verdict + reproduction on every finding), NFR-7 (zero suppressions, regression test per fix), NFR-8 (triage-first fan-out shrinking).
4. Traceability matrix (§5) verified complete in the implementation-readiness check — no orphan requirement, no uncovered goal.

## 5. Traceability Matrix

| Brief goal | Requirements |
|---|---|
| G1 Zero false positives | FR-1, FR-5, FR-7, NFR-5, NFR-6 |
| G2 Full OWASP/CWE coverage | FR-1, FR-3, FR-4, FR-5, NFR-6 |
| G3 Root-cause, regression-tested fixes | FR-1, FR-6, FR-8, NFR-7 |
| G4 Bounded, degrade-safe loop | FR-1, FR-3, FR-9, NFR-2, NFR-3, NFR-8 |
| G5 Generalization | FR-4, FR-5, NFR-4 |
| G6 Clean plugin integration | FR-2, FR-9, FR-10, NFR-1, NFR-9 |

Reverse check: every FR/NFR appears in at least one goal row (FR-1..10, NFR-1..9 all mapped).

## 6. Out of Scope (v1)

- **No new command.** The skill is triaged inside Stage 4 `/sdlc-review`; no `/sdlc-security` surface (command count stays 8).
- **No new editing path.** `security-auditor` reports and routes; code edits flow through the existing `php-implementer`.
- **No offensive / unauthorized use.** Never probe hosts/URLs outside the profile-resolved local service; no exfiltration; no destructive payloads beyond proving a vuln on a disposable container instance.
- **No memory-safety / mobile-client fabrication.** Memory-safety CWEs and OWASP Mobile are recorded N/A-with-reason for managed PHP backends, never invented as findings.
- **No full CVSS v3.1/v4.0 scoring mandate.** Band-with-rationale (Critical/High/Medium/Low) is the bar; full vector optional.
- **No heavyweight scanner vendoring** beyond a minimal `make.security`-null fallback (ADR-level, mirroring `ai-review-loop.sh`); no GitHub App / hosted service.

## 7. Assumptions (carried from brief §7, binding for architecture)

- A1: Placement is a triaged skill inside Stage 4 `/sdlc-review`, not a new command; the feature scope is "skill + agent only" — architecture pins the exact wiring.
- A2: `security-auditor` is **report-and-route** (reports verified findings; fixes flow through `php-implementer`) to keep its tool surface clean and reuse the proven implementer — confirmed by an ADR.
- A3: Severity is a CVSS-ish band (Critical/High/Medium/Low + rationale); full CVSS vectors are optional precision.
- A4: The LLM Top 10 family is gated on detected LLM usage (composer deps / `clean-architecture-llm` artifacts / a profile signal); memory-safety CWEs and OWASP Mobile are N/A-with-reason for managed PHP backends.
- A5: A `make.security`-null repo still gets SAST/dep/secret/config via a minimal bundled fallback or documented degrade (ADR-level, mirroring `ai-review-loop.sh`); exact fallback surface in architecture.
- A6: The new capability key name (leaning `capabilities.dynamic_security_testing`) and the precise re-run policy (per-fix affected tests + family re-verify, with one final `make.ci`) are minimal-surface decisions deferred to architecture.
- Binding constraints restated: runtime profile reads; container-only execution; root-cause culture (no suppressions, no `deptrac.yaml` edits, thresholds never lowered); `MAX_ITERATIONS=5` bound + breaker honored; defensive/authorized boundary; generalization (NFR-4); SKILL.md ≤ ~500 lines.

## 8. Open Questions for Architecture

1. **Capability key name (OQ-1):** `capabilities.dynamic_security_testing` vs `capabilities.dast` vs reusing an existing flag — minimal-surface schema decision; also finalize the `make.security` schema-table wording.
2. **`make.security` null fallback (OQ-2):** ship a bundled minimal security script (à la `ai-review-loop.sh`) under `scripts/`, or degrade entirely? Decides whether a `make.security`-null repo still gets SAST and the `scripts/` surface delta.
3. **LLM-family gating signal (OQ-3):** detect target LLM usage via composer deps, `clean-architecture-llm` artifacts, or a profile flag — to switch the LLM Top 10 family on/off.
4. **Loop coupling with `make.ci` (OQ-4):** full `make.ci` per iteration (expensive) vs affected tests + family re-verify with one final `make.ci` (token/time vs safety trade-off).
5. **Fix-routing contract (OQ-5):** the exact hand-off shape from `security-auditor` finding → skill → `php-implementer` edit → regression test → family re-verify (ADR for A2).
6. **Severity rigor (OQ-6):** band-with-rationale (assumed) vs an optional CVSS vector field in the finding record.
