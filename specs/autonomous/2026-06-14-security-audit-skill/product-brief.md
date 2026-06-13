---
stepsCompleted: [step-01-init, step-02-vision, step-03-users, step-04-metrics, step-05-scope, step-06-complete]
inputDocuments:
  - specs/autonomous/2026-06-14-security-audit-skill/research.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/product-brief.md
  - plugins/php-backend-sdlc/agents/qa-manual-tester.md
  - plugins/php-backend-sdlc/agents/code-quality-reviewer.md
  - plugins/php-backend-sdlc/docs/profile-schema.md
date: 2026-06-14
author: Mary (BMAD analyst agent, autonomous run)
mode: autonomous (no human pauses; assumptions recorded inline)
---

# Product Brief: `security-audit` Skill (+ `security-auditor` Agent) for `php-backend-sdlc`

## 0. Executive Summary

Add a security lens to the existing `php-backend-sdlc` plugin: a new `skills/security-audit/SKILL.md` that runs an adversarial, multi-subagent red-team / penetration-testing loop over the target PHP backend (the plugin user's own authorized repo — defensive use only). The skill fans out one `security-auditor` red-team subagent per OWASP/vuln family in parallel; each subagent attempts to break the running service (black-box HTTP probing like `qa-manual-tester`) **and** analyzes source (SAST/taint, dependency, secret, config — like `code-quality-reviewer`), then **verifies** every candidate against the running service to eliminate false positives, maps it to CWE + OWASP id + severity, and the skill drives root-cause fixes (routed through the existing `php-implementer`), adds a regression test per fix, re-tests, and loops within the SDLC until zero new vulnerabilities remain.

The feature is the plugin's first skill that BOTH reads source AND attacks the running service, and the first verification lens that **fixes** rather than only reporting. It is bounded (`MAX_ITERATIONS=5` per stage, NFR-6), container-only via the profile `make` map, profile-driven, and fully generalized to any PHP backend (NFR-2 — no hardcoded source-project identifiers). Coverage spans ALL OWASP corpora across the years (Top 10 every edition, API Top 10 2019/2023, LLM Top 10, Mobile as N/A-for-backend, ASVS, WSTG, Proactive Controls/Cheat Sheets) plus CWE Top 25 and SANS — enumerated in `reference/` files so SKILL.md stays under ~500 lines. Two minimal new profile keys (a nullable `make.security` target and a dynamic-testing capability gate) extend the schema following existing conventions. Success is measured by zero-false-positive verified findings, every fix carrying a regression test with no suppression, a clean generalization audit, and correct component-count integration deltas (21→22 skills, 6→7 agents).

## 1. Problem Statement

The `php-backend-sdlc` plugin (v1: 8 commands, 6 agents, 21 skills + 2 meta-guides, generalized to any PHP backend via `.claude/php-sdlc.yml`) ships two verification stages but **no adversarial security pass** (research §1):

- **Stage 4 `/sdlc-review`** is a read-only quality lens (`code-quality-reviewer`, opus) running `make.psalm`/`make.deptrac`/`make.phpinsights`/`make.infection` against raise-only thresholds. The `code-review` skill names "security" as one AI-review scope but performs **no dedicated vulnerability hunt** — no SAST taint pass, no dependency/secret scan, no dynamic attack probing.
- **Stage 5 `/sdlc-qa`** is a black-box lens (`qa-manual-tester`, sonnet) that renders verdicts purely from observed HTTP behavior. It verifies acceptance criteria, **not adversarial inputs**.

Concrete gaps this feature fills:

- **No adversarial pass anywhere in the loop.** A feature can pass review and QA while still shipping a BOLA/IDOR hole, SQL injection, mass-assignment leak, JWT `none`-alg bypass, exposed `/_profiler`, committed secret, or a dependency with a known CVE.
- **No find→verify→fix→regress→loop for vulnerabilities.** The plugin's bedrock loop discipline (bounded, suppression-free, root-cause-only) exists for quality but has never been pointed at the security surface.
- **No structured finding taxonomy.** There is no place mapping observations to CWE + OWASP id + severity, so security feedback (when it appears at all in AI review) is ad-hoc and unverifiable.
- **No parallel decomposition by attack surface.** The plugin already fans out `php-implementer` on independent stories, but nothing fans out red-team probes by OWASP family — the idiom the automated-pentest literature converges on (research §6.1).

The result: security is the one SDLC dimension the plugin asserts but does not exercise. This feature closes that gap by reusing both proven agent shapes (HTTP probing + source-aware analysis) under the canonical bounded loop.

## 2. Target Users

- **Primary: PHP backend engineers running the plugin on their own authorized repo.** They already run `/sdlc-review` and `/sdlc-qa`; they want an adversarial security gate that finds real, reproduced vulnerabilities and drives root-cause fixes in the same loop — defensive, authorized, against their own running service only.
- **Secondary: security-conscious teams adopting the plugin from the marketplace.** Any DDD/hexagonal Symfony + API Platform + Doctrine backend that needs OWASP/CWE-mapped findings, secure-by-default remediation citing OWASP cheat sheets, and a regression test per fix — adapted entirely through the project profile.
- **Tertiary: autonomous agents themselves** (`/sdlc` loop, bmalph/Ralph runs, the `/sdlc-review` orchestration) that invoke `security-audit` as a triaged skill and consume its verdicts as operating procedure.

## 3. Value Proposition

One triaged skill turns the existing SDLC verification gate into an adversarial security loop: it spawns parallel `security-auditor` subagents (one per OWASP family), each breaks the running service and inspects its source, **verifies every finding by reproduction** (no false positives), maps it to CWE + OWASP id + CVSS-ish severity, then the skill drives **root-cause, suppression-free fixes** through `php-implementer`, attaches a **regression test per fix**, re-tests, and re-dispatches only still-open families until a clean pass — all bounded at 5 iterations with explicit degrade paths. Coverage is the entire OWASP corpus across the years plus CWE Top 25/SANS, kept current in versioned `reference/` files. Everything is profile-driven and generalized: the same skill works on any PHP backend with zero source-project literals, no new command surface, and only two minimal new profile keys.

## 4. Goals and Success Metrics

| # | Goal | Metric | Target |
|---|------|--------|--------|
| G1 | Zero false positives | Reported/fixed findings that carry a working reproduction against the running service (SAST candidate alone is never a finding) | 100% — any finding without a reproduction is downgraded/dropped |
| G2 | Full OWASP/CWE coverage | OWASP families (Top 10 all editions, API 2019/2023, LLM, Mobile, ASVS, WSTG) + CWE Top 25 each given an explicit verdict per run: probed, or N/A-with-reason | 100% triaged; no silent skips |
| G3 | Root-cause, regression-tested fixes | Every fixed vulnerability is fixed in code (zero suppression/baseline/threshold-lowering) AND carries a failing-then-passing regression test | 100% of fixes |
| G4 | Bounded, degrade-safe loop | Stage honors `MAX_ITERATIONS=5` then escalates with a status report; absent capabilities (`make.security: null`, no bootable service, no GraphQL) degrade to skip-with-note, never hard-fail | 0 unbounded loops; 0 hard-fails on absent capability |
| G5 | Generalization | `security-audit`/`security-auditor`/`reference/` + schema edits pass the plugin's generalization audit (no `user-service`/`VilnaCRM`/`Mongo*Repository`/`AppRunner`/`src/User`/`src/OAuth` outside `# profile-example` fences) | 100% — CI generalization-audit green |
| G6 | Clean plugin integration | Component counts and guides updated consistently: 21→22 skills, 6→7 agents across `tests/component-counts.bats`, `SKILL-DECISION-GUIDE.md`, `AI-AGENT-GUIDE.md`, NFR-1, README/docs; both new profile keys documented so `profile-keys-check` passes; SKILL.md ≤ ~500 lines | Plugin CI green on every PR |

## 5. Scope

### In scope (v1)

- New skill `plugins/php-backend-sdlc/skills/security-audit/SKILL.md` — adversarial multi-subagent red-team loop (find → verify → root-cause fix → regression test → loop until clean), bounded `MAX_ITERATIONS=5`, explicit degrade paths, container-only via the profile `make` map, profile-driven, generalized.
- Three reference files keeping SKILL.md under ~500 lines: `reference/owasp-catalog.md` (all OWASP editions + CWE Top 25/SANS with edition labels), `reference/attack-playbooks.md` (per-family WSTG techniques and probes), `reference/remediation-patterns.md` (secure-by-default fixes citing OWASP cheat sheets + vetted libraries).
- New agent `plugins/php-backend-sdlc/agents/security-auditor.md` — the red-team subagent unit dispatched in parallel (one per OWASP family); mirrors the plugin agent anatomy (frontmatter `name`/`description`/`tools`/`model`; 8-section body spine: Profile keys consumed, Role, Inputs, Outputs, Allowed actions, Degrade paths, Iteration discipline, Smoke prompt). Tools combine both precedents (`Bash, Read, Glob, Grep`); model **opus** (judgment-heavy). White/grey-box: MAY read source, but inherits "verify against observed behavior, no false positives" and "mutate only via the API".
- Two minimal new profile keys in `docs/profile-schema.md`: nullable `make.security` (the repo's security/SAST suite; mirrors `make.ai_review_loop`/`make.pr_comments` nullable precedent) and a `capabilities.*` boolean gating dynamic testing (pairs with `make.start`, mirroring `capabilities.load_testing`).
- Integration deltas: `tests/component-counts.bats` (21→22 skills, 6→7 agents, NFR-1 header), `skills/SKILL-DECISION-GUIDE.md` + `skills/AI-AGENT-GUIDE.md` (counts 21→22 + triage/usage rows), PRD NFR-1, architecture file-tree/agent matrix, README/docs counts.
- Defensive/authorized framing throughout; secure-by-default remediation; findings mapped to CWE + OWASP id + CVSS-ish severity (band + rationale).
- BMAD planning artifacts for this feature in `specs/autonomous/2026-06-14-security-audit-skill/`.

### Out of scope (v1)

- **No new command.** The skill is triaged inside the existing verification gate (most naturally Stage 4 `/sdlc-review`); no `/sdlc-security` surface (PRD/architecture to pin placement).
- **No offensive / unauthorized use.** Never probe hosts/URLs outside the profile-resolved local service; no exfiltration; no destructive payloads beyond what is needed to prove a vuln against a disposable container instance.
- **No new editing path.** `security-auditor` reports and routes; code edits flow through the existing `php-implementer` (subject to an ADR).
- **No memory-safety / mobile-client fabrication.** Memory-safety CWEs and OWASP Mobile are recorded N/A-with-reason for managed PHP backends, never invented as findings.
- **No full CVSS v3.1/v4.0 scoring mandate** — band-with-rationale is the bar (full vector optional precision).
- **No bundled heavyweight scanner vendoring** beyond a minimal `make.security`-null fallback decision (ADR-level, mirroring `ai-review-loop.sh` precedent); no GitHub App / hosted service.

## 6. Key Features

1. **Parallel red-team fan-out.** The skill dispatches one `security-auditor` subagent per OWASP/vuln family in parallel (BOLA/IDOR, BOPLA/mass-assignment, BFLA, SQLi, SSTI, deserialization, SSRF, auth/session, misconfiguration, vulnerable deps, secrets, file upload, rate/resource, GraphQL-specific, LLM-when-detected), reusing the plugin's existing parallel-Task idiom — no new infrastructure.
2. **Dual-mode auditing per subagent.** Each subagent runs source-aware SAST/taint (Psalm `--taint-analysis`, Semgrep), dependency SCA (`composer audit`), secret scanning, and config audit **and** adversarial dynamic probing (`curl`/`jq`/GraphQL POSTs with malicious payloads, auth-swap requests for BOLA) — SAST localizes candidates, dynamic probing verifies them.
3. **Verify-before-report discipline.** A SAST candidate is never a finding; it must be reproduced against the running service. Findings without a working reproduction are downgraded/dropped — the plugin's "verdicts from observed behavior" rule turned into the pentest false-positive guard.
4. **Root-cause fix + regression test loop.** Verified findings drive suppression-free, secure-by-default fixes (Symfony `auto` hasher, Doctrine parameterized queries, Twig auto-escaping, Serializer write groups, API Platform voters) routed through `php-implementer`; each fix gets a failing-then-passing regression test; the affected family re-verifies and only still-open families re-dispatch, bounded at 5 iterations.
5. **Finding taxonomy.** Every finding maps to CWE id + OWASP id + CVSS-ish severity (Critical/High/Medium/Low + vector rationale), with the OWASP cheat sheet / vetted library cited for each remediation.
6. **Reference corpus, versioned.** `reference/owasp-catalog.md` / `attack-playbooks.md` / `remediation-patterns.md` hold the full enumeration with edition labels (Top 10 2003→2021, API 2019/2023, LLM, ASVS 5.0, WSTG 4.2, CWE Top 25 2024) so refreshes are localized and SKILL.md stays under ~500 lines.
7. **Minimal profile extension + degrade matrix.** Nullable `make.security` + dynamic-testing capability gate; when absent, static/SAST/dep/secret/config still run and dynamic probing degrades to skip-with-note; LLM/Mobile/memory-safety families gate to N/A-with-reason up front.

## 7. Constraints and Assumptions

### Binding constraints (plugin non-negotiables, inherited)

- **Defensive, authorized only.** Run by the repo owner against their own service; never touch hosts outside the profile-resolved local service; mutate state only through the service's own API; no exfiltration or destructive payloads beyond proving a vuln on a disposable container instance.
- **Container-only execution** (`make` / `docker compose exec php`); never host binaries (research §5).
- **Root-cause culture intact.** No suppression annotations, no baselines/ignores, never modify `deptrac.yaml`/configs to pass, thresholds never lowered (the `code-review` forbidden-suppression scan + ADR-7 raise-only thresholds bind here too).
- **Every loop bounded** at `MAX_ITERATIONS=5` per stage with an escalation block on exhaustion (NFR-6); honor degrade paths over hard-fail (NFR-4).
- **Profile-driven + generalized (NFR-2).** All paths/contexts come from the profile (`architecture.source_root`, `architecture.bounded_contexts`, `persistence.mapper`, `framework.api_platform`, `framework.graphql`); no source-project literals outside `# profile-example` fences; `generalization-audit` and `profile-keys-check` CI jobs must pass.
- **SKILL.md ≤ ~500 lines**; enumerations live in `reference/`.
- **Component counts must stay consistent** across bats tests, guides, NFR-1, and docs (21→22 skills, 6→7 agents).

### Assumptions (recorded autonomously, no human confirmation)

- A1: Placement is a triaged skill inside the existing verification gate (Stage 4 `/sdlc-review`), not a new command — the feature scope is "skill + agent only"; PRD/architecture pin the exact wiring.
- A2: `security-auditor` is **report-and-route** (reports verified findings; fixes flow through `php-implementer`) to keep its tool surface clean and reuse the proven implementer — to be confirmed by an ADR.
- A3: Severity is recorded as a CVSS-ish band (Critical/High/Medium/Low + rationale); full CVSS vectors are optional precision, not required, to stay actionable.
- A4: The LLM Top 10 family is gated on detected LLM usage in the target (composer deps / `clean-architecture-llm` artifacts / a profile signal); memory-safety CWEs and OWASP Mobile are N/A-with-reason for managed PHP backends.
- A5: A `make.security`-null repo still gets SAST/dep/secret/config via a minimal bundled fallback or documented degrade (ADR-level, mirroring `ai-review-loop.sh`); the exact fallback surface lands in architecture.
- A6: The new capability key name (e.g. `capabilities.dynamic_security_testing`) and the precise re-run policy (per-fix affected tests + family re-verify, with one final `make.ci`) are minimal-surface decisions deferred to architecture.

## 8. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| **False positives** (the #1 pentest failure mode) | Mandatory reproduce-against-running-service before any finding is reported or fixed; SAST output is a candidate, not a finding; no reproduction ⇒ downgraded/dropped (G1) |
| **Destructive / out-of-scope probing** against a real datastore | Container-only, disposable instance, mutate-only-via-API, never touch hosts outside the profile-resolved local service, defensive/authorized framing throughout |
| **Token/time cost of parallel opus fan-out × 5 iterations** | SAST-first triage to skip zero-candidate families; gate LLM/Mobile/memory-safety as N/A up front; bound at `MAX_ITERATIONS=5`; re-dispatch only still-open families |
| **Capability variance** (no `make.security`, no SAST, no bootable service, no GraphQL) | Nullable `make.security` + dynamic-testing capability gate + per-family N/A reasons (NFR-4 degrade matrix); never hard-fail on absent capability (G4) |
| **Fix-induced regressions / scope creep** | Every fix carries a regression test, then the affected family re-verifies and the quality gate (`make.ci`) runs before the loop closes; route edits through existing `php-implementer` |
| **Suppression temptation under time pressure** | `code-review` forbidden-suppression diff scan (Step 6) + ADR-7 raise-only thresholds already block this; restate the prohibition in the new agent/skill (G3) |
| **Corpus drift** (OWASP/CWE editions update — Top 10 2025 in progress, ASVS 5.0, CWE Top 25 annual) | Enumerations live in versioned `reference/` files with edition labels, not in SKILL.md; refreshes are localized |
| **Component-count / guide drift** | Update `component-counts.bats`, `SKILL-DECISION-GUIDE.md`, `AI-AGENT-GUIDE.md`, NFR-1, README/docs in one change; CI count assertions enforce consistency (G6) |

## 9. Open Questions (non-blocking for PRD)

1. **Placement** — standalone skill triaged inside `/sdlc-review`, a new sub-stage, or its own command? (Scope says skill + agent only; leaning Stage 4 triage — PRD must pin it.)
2. **Who fixes** — `security-auditor` edits code, or strictly reports/routes while the skill dispatches `php-implementer`? (Leaning report-and-route; needs an ADR.)
3. **Exact new capability key name** — `capabilities.dynamic_security_testing` vs `capabilities.dast` vs reusing an existing flag (minimal-surface schema decision).
4. **`make.security` null fallback** — ship a bundled minimal security script (à la `ai-review-loop.sh`) or degrade entirely? (Affects `scripts/` surface and whether a null repo still gets SAST.)
5. **LLM-family gating signal** — composer deps, `clean-architecture-llm` artifacts, or a profile flag to switch the LLM Top 10 family on.
6. **Loop coupling with `make.ci`** — full `make.ci` per iteration (expensive) vs affected tests + family re-verify with one final `make.ci` (token/time vs safety trade-off).
