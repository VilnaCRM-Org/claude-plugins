# Research: `security-audit` Skill (+ `security-auditor` Agent) for `php-backend-sdlc`

Date: 2026-06-14 | Stage: BMAD Analysis (research) | Analyst: Mary (BMAD analyst agent, autonomous run)
Feature input: add a `skills/security-audit/SKILL.md` + `agents/security-auditor.md` to the EXISTING plugin at `plugins/php-backend-sdlc/`, running an adversarial, multi-subagent red-team/pentest loop over the target PHP backend (authorized, defensive use only) that finds → verifies → root-cause-fixes → regression-tests → loops until zero new vulnerabilities remain.
Context read: `plugins/php-backend-sdlc/skills/code-review/SKILL.md`, `plugins/php-backend-sdlc/agents/qa-manual-tester.md`, `plugins/php-backend-sdlc/agents/code-quality-reviewer.md`, `plugins/php-backend-sdlc/docs/profile-schema.md`, `plugins/php-backend-sdlc/tests/component-counts.bats`, `specs/autonomous/2026-06-09-php-backend-sdlc-plugin/{research,architecture}.md`.

## 1. Feature framing within the existing plugin

The plugin (v1, six-artifact BMAD spec at `specs/autonomous/2026-06-09-php-backend-sdlc-plugin/`) ships **8 commands / 6 agents / 21 skills + 2 meta-guides** and generalizes every component to any PHP backend through the runtime project profile `.claude/php-sdlc.yml` (ADR-1, FR-17). The two SDLC verification stages this feature sits beside are:

- **Stage 4 `/sdlc-review`** — read-only quality lens (`code-quality-reviewer`, opus) runs `make.psalm`/`make.deptrac`/`make.phpinsights`/`make.infection` against raise-only `quality.*` thresholds; **suppression-free, root-cause-only, never lowers a bar** (agent body lines 54–59; ADR-7). The `code-review` skill already names "security" as one of its AI-review-loop scopes (SKILL.md line 211) but performs **no dedicated vulnerability hunt** — there is no SAST taint pass, no dependency/secret scan, no dynamic attack probing.
- **Stage 5 `/sdlc-qa`** — black-box lens (`qa-manual-tester`, sonnet) boots the service via `make.start` and renders verdicts **purely from observed HTTP behavior** (`curl`/`jq`, GraphQL POSTs), never reading application source (agent body lines 37–47). It verifies acceptance criteria, **not adversarial inputs**.

The gap this feature fills: neither stage performs an **adversarial** pass. `security-audit` becomes the plugin's security lens, reusing both proven patterns at once — black-box HTTP probing (the `qa-manual-tester` shape) **plus** static/SAST/dependency/secret/config analysis (the `code-quality-reviewer` shape) — and adding the find→verify→fix→regress→loop discipline already canonical in `code-review`/`code-quality-reviewer` (bounded `MAX_ITERATIONS=5`, escalation block, NFR-4 degrade paths). This makes it the first skill that BOTH reads source AND attacks the running service, and the first to **fix** (most lenses are report-only).

**Multi-subagent shape.** Unlike the existing single-agent stages, the skill **fans out one `security-auditor` red-team subagent per OWASP/vuln family** in parallel — the pattern the plugin already uses for parallel `php-implementer` dispatch on independent stories (architecture §7) and the generic Claude Code parallel-Task idiom. Each subagent owns one family, attempts to break the service, verifies (reproduces, no false positives), maps the finding to CWE + OWASP id + severity, then the skill drives root-cause fixes (re-using `php-implementer` for code edits), re-tests, and re-dispatches the families that still report findings until a clean pass.

## 2. The OWASP corpus — full enumeration across the years (coverage scope)

The feature's coverage requirement is "ALL OWASP vulnerabilities across the years." Catalogued below for `reference/owasp-catalog.md`. Categories cited verbatim from primary OWASP / MITRE / CISA sources.

### 2.1 OWASP Top 10 (web) — every edition

Editions: **2003, 2004, 2007, 2010, 2013, 2017, 2021** (OWASP now targets a refresh every 3–4 years; a 2025 edition is in progress at research time). Evolution per the OWASP Developer Guide and edition histories:

- **2003/2004** — classic web flaws: Unvalidated Input, Broken Access Control, Broken Authentication & Session Management, Cross-Site Scripting (XSS), Buffer Overflows, Injection Flaws, Improper Error Handling, Insecure Storage, Denial of Service, Insecure Configuration Management.
- **2007** — re-structured around risk; surfaced Insecure Communications and Failure to Restrict URL Access; XSS elevated.
- **2010** — risk-rating methodology; Security Misconfiguration, Insufficient Transport Layer Protection.
- **2013** — A9 *Using Components with Known Vulnerabilities* added (third-party dependency risk).
- **2017** — A4 XML External Entities (XXE), A8 Insecure Deserialization, A10 Insufficient Logging & Monitoring.
- **2021** (current) — A01 Broken Access Control, A02 Cryptographic Failures, A03 Injection (XSS folded in), A04 **Insecure Design** (new), A05 Security Misconfiguration, A06 Vulnerable & Outdated Components, A07 Identification & Authentication Failures, A08 **Software & Data Integrity Failures** (new — incl. insecure deserialization, CI/CD supply chain), A09 Security Logging & Monitoring Failures, A10 Server-Side Request Forgery (SSRF, new). [OWASP Developer Guide — Top 10; edition histories]

### 2.2 OWASP API Security Top 10

Editions **2019** and **2023**. The 2023 list (primary source, `owasp.org/API-Security/editions/2023`): **API1 Broken Object Level Authorization (BOLA/IDOR), API2 Broken Authentication, API3 Broken Object Property Level Authorization** (merges 2019's Excessive Data Exposure + Mass Assignment), **API4 Unrestricted Resource Consumption, API5 Broken Function Level Authorization, API6 Unrestricted Access to Sensitive Business Flows (new), API7 Server Side Request Forgery (new), API8 Security Misconfiguration, API9 Improper Inventory Management (renamed from Improper Assets Management), API10 Unsafe Consumption of APIs (new)**. 2019→2023 dropped standalone Injection and Insufficient Logging & Monitoring (covered by other OWASP projects). This is the **most load-bearing list for an API-Platform/Symfony backend** — BOLA/BFLA/BOPLA authorization flaws are the dominant real-world API class.

### 2.3 OWASP Top 10 for LLM Applications

Edition **2025** (v2.0, published 2024-11-18, OWASP GenAI project): **LLM01 Prompt Injection, LLM02 Sensitive Information Disclosure, LLM03 Supply Chain, LLM04 Data & Model Poisoning, LLM05 Improper Output Handling, LLM06 Excessive Agency, LLM07 System Prompt Leakage, LLM08 Vector & Embedding Weaknesses, LLM09 Misinformation, LLM10 Unbounded Consumption.** Conditionally relevant: applies only when the target backend itself integrates an LLM (the plugin has a `clean-architecture-llm` skill, so LLM-backed PHP backends are in scope). Gate this family on detected LLM usage; otherwise mark N/A-with-reason.

### 2.4 OWASP Mobile Top 10

Editions 2014/2016/2024. **Mark N/A for a backend service** (no mobile client surface in scope) — but note the API tier behind a mobile app inherits the API Top 10; record the N/A with that reasoning rather than silently dropping it.

### 2.5 Supporting OWASP standards (verification depth, not a ranked list)

- **ASVS — Application Security Verification Standard** (first 2008; current **5.0.0**, published May 2025): ~350 requirements across 17 chapters, three assurance levels **L1/L2/L3**. Use as the *requirements/coverage checklist* per family (what "verified secure" means), not as an attack list. L2 is the sane default bar for a typical backend.
- **WSTG — Web Security Testing Guide** (current v4.2): the *how-to-test* methodology — the concrete probing techniques each `security-auditor` subagent executes (e.g. testing for SQLi, auth bypass, SSRF, file upload). Maps WSTG test IDs to families in `reference/attack-playbooks.md`.
- **OWASP Proactive Controls** and the **OWASP Cheat Sheet Series** — the *remediation* source of truth; root-cause fixes cite the relevant cheat sheet (e.g. the Symfony, SQL Injection Prevention, Authorization, Mass Assignment, Deserialization cheat sheets). Feeds `reference/remediation-patterns.md`.

## 3. CWE Top 25 + SANS (finding taxonomy)

Every finding maps to a **CWE id** alongside its OWASP id + severity. The **2024 CWE Top 25** (CISA/MITRE, from 31,770 analyzed CVE records; primary source `cwe.mitre.org/top25/archive/2024`), ordered, with backend relevance:

1. CWE-79 XSS · 2. CWE-787 Out-of-bounds Write* · 3. CWE-89 SQL Injection · 4. CWE-352 CSRF · 5. CWE-22 Path Traversal · 6. CWE-125 Out-of-bounds Read* · 7. CWE-78 OS Command Injection · 8. CWE-416 Use After Free* · 9. CWE-862 Missing Authorization · 10. CWE-434 Unrestricted File Upload · 11. CWE-94 Code Injection · 12. CWE-20 Improper Input Validation · 13. CWE-77 Command Injection · 14. CWE-287 Improper Authentication · 15. CWE-269 Improper Privilege Management · 16. CWE-502 Deserialization of Untrusted Data · 17. CWE-200 Sensitive Information Exposure · 18. CWE-863 Incorrect Authorization · 19. CWE-918 SSRF · 20. CWE-119 Improper Memory-Bounds Restriction* · 21. CWE-476 NULL Pointer Dereference* · 22. CWE-798 Hard-coded Credentials · 23. CWE-190 Integer Overflow* · 24. CWE-400 Uncontrolled Resource Consumption · 25. CWE-306 Missing Authentication for Critical Function.

(*) memory-safety CWEs (787, 125, 416, 119, 476, 190) are largely **not applicable to managed PHP** — record them N/A-with-reason rather than fabricating findings; the PHP-relevant majority (79, 89, 352, 22, 78, 862/863/306/287/269 authz/authn, 434, 94/77 injection, 502 deser, 200, 918 SSRF, 798 secrets, 400 DoS) drive the playbooks. **SANS Top 25** historically co-published with MITRE CWE; treat "CWE/SANS Top 25" as the same taxonomy. Severity is recorded **CVSS-ish** (Critical/High/Medium/Low with a vector rationale) — full CVSS v3.1/v4.0 scoring is optional precision, not a hard requirement, to stay actionable.

## 4. PHP / Symfony / API-Platform vulnerability classes (the real attack surface)

Concentrating the abstract corpus onto the plugin's actual target stack (Symfony + API Platform + Doctrine ORM/ODM, per the profile). Primary refs: HackTricks Symfony page, Vaadata Symfony security guide, OWASP Symfony Cheat Sheet, API-Platform security docs.

| Class | Where it bites in this stack | OWASP / CWE |
|---|---|---|
| **BOLA / IDOR** | API Platform exposes IRIs (`/api/resource/{id}`); missing per-object voters → reading/writing others' objects | API1:2023 / CWE-639/862 |
| **BOPLA / Mass assignment** | API Platform denormalization writing fields not in a write group; over-broad serialization groups leaking fields | API3:2023 / CWE-915/213 |
| **BFLA** | Missing `#[IsGranted]` / `security:` on an operation; admin operation reachable by a normal role | API5:2023 / CWE-862 |
| **SQL injection** | Raw DQL/SQL string concatenation, unparameterized native queries, `LIKE` building | A03:2021 / CWE-89 |
| **SSTI** | User input reaching `createTemplate()`/dynamic Twig → RCE (Twig <2.4.4 historic CVE) | A03 / CWE-1336/94 |
| **Insecure deserialization** | PHP `unserialize()` on untrusted input; Symfony Serializer on attacker-controlled type | A08:2021 / CWE-502 |
| **SSRF** | URL fetchers, webhook callers, file/image proxies, XXE-driven fetches | A10:2021, API7 / CWE-918 |
| **Auth/session** | Weak password hashing, JWT alg-confusion/`none`, missing token expiry, fixation | A07:2021, API2 / CWE-287/798 |
| **Security misconfiguration** | `APP_ENV=dev`/debug toolbar in prod, verbose stack traces, permissive CORS, default creds, exposed `/_profiler` | A05:2021, API8 / CWE-16/200 |
| **Vulnerable dependencies** | Outdated composer packages with known CVEs | A06:2021, LLM03 / CWE-1104/1395 |
| **Secrets** | Hard-coded keys/tokens in source, committed `.env`, secrets in logs | CWE-798/200 |
| **File upload** | Unrestricted type/size, web-accessible upload dir, path traversal in name | API4, A05 / CWE-434/22 |
| **Rate/resource** | No throttling → resource exhaustion, brute force, enumeration | API4:2023 / CWE-400/770 |
| **GraphQL-specific** | Introspection on in prod, deep/aliased query DoS, batching abuse (when `framework.graphql`) | API4/API8 |

These rows justify the **one-subagent-per-family** decomposition: each maps cleanly to a `security-auditor` dispatch with its own WSTG playbook and remediation cheat sheet.

## 5. Tooling — static, dependency, secret, config, dynamic (the auditor's instruments)

Each `security-auditor` subagent uses container-only tools (the plugin's hard rule — `make` / `docker compose exec php`, never host binaries):

- **SAST / taint:** **Psalm taint analysis** (`--taint-analysis`) tracks `$_GET/$_POST/$_COOKIE` sources → SQL/HTML/shell sinks for SQLi/XSS/command-injection (Psalm is already a plugin profile target, `make.psalm`); **Semgrep** PHP/Symfony rulesets (an installed Semgrep MCP/plugin exists in this environment) for broader pattern coverage. SAST is the cheap first pass that *localizes* candidates for dynamic verification.
- **Dependency / SCA:** `composer audit` (built into Composer, reads `composer.lock` against the PHP advisories DB) and/or the **Symfony Security Checker**; optionally **Trivy** for OS+app layers. Covers A06/API-supply-chain.
- **Secret scanning:** `gitleaks`/`trufflehog`-class scan of tree + git history for hard-coded credentials (CWE-798).
- **Config audit:** prod-mode env, debug/profiler exposure, CORS, headers (CSP/HSTS/X-Frame-Options), TLS — partly static (config files) and partly dynamic (response headers on the booted service).
- **DAST / dynamic probing:** the `qa-manual-tester` instrument set — `curl`/`jq`, GraphQL POSTs, readiness polling — turned **adversarial** (malicious payloads, auth-swap requests for BOLA, fuzzed inputs). This is where a SAST candidate is **verified/reproduced** against the running service to eliminate false positives.

Many of these naturally live behind a single repo make target: the new **nullable `make.security`** profile key (the repo's own security/SAST suite, e.g. `make security`), substituted/degraded when `null` — exactly mirroring `make.ai_review_loop`/`make.pr_comments` precedent (profile-schema.md lines 76–78). Dynamic probing is gated by a new **capability** flag (mirroring `capabilities.load_testing`) so a repo with no bootable service degrades the dynamic stage to "capability absent — skipped" (NFR-4) instead of failing.

## 6. Multi-agent red-team patterns + automated-pentest / auto-remediation best practices

### 6.1 Multi-agent red-team architecture (external state of the art)

The literature converges on **role/phase-specialized agents coordinating in parallel** rather than one monolithic agent: **PentestGPT** (Reasoning–Generation–Parsing to fight context loss), **LLM4Pentest / VulnBot / xOffense / CurriculumPT / PENTEST-AI** all split recon → scan → exploit across specialized agents with a task graph and inter-agent messaging; the Hadrian survey notes 70+ AI offensive tools in 18 months and that, unlike a human pentester, these "operate not sequentially … but in parallel across an entire attack surface at once." Direct design implications adopted here:

- **Decompose by attack surface, fan out in parallel** → one `security-auditor` per OWASP family (this plugin's own parallel-`php-implementer` precedent makes this idiomatic, no new infra).
- **Bound the loop** → the SDLC `MAX_ITERATIONS=5` per stage (NFR-6) is the antidote to the well-documented context-loss/looping failure mode; honor the escalation block on exhaustion (architecture §2).
- **Verify before reporting** → the plugin's existing "verdicts from observed behavior, not what the code suggests" rule (`qa-manual-tester`) is exactly the false-positive guard the pentest literature demands.

### 6.2 Authorized / defensive scoping (non-negotiable)

This is a **defensive, authorized** capability run **by the repo owner against their own service**. Constraints to encode: explicit authorized-target framing in SKILL.md and the agent prompt; **never** probe hosts/URLs outside the profile-resolved local service; no exfiltration, no destructive payloads beyond what's needed to *prove* a vuln against a disposable local/container instance; mutate state only through the service's own API (the `qa-manual-tester` rule); container-only execution. The skill description must read as defensive security research, matching the safe-by-construction tone of the existing agents.

### 6.3 Auto-remediation best practices (the fix half of the loop)

- **Root-cause fixes only, zero suppression** — the plugin's bedrock rule (`code-quality-reviewer` lines 54–59, `code-review` suppression-scan Step 6, ADR-7): never silence a finding, never add a baseline/ignore, never lower a threshold. A security finding is fixed in code or it stays open.
- **Secure-by-default remediation citing vetted libraries + OWASP cheat sheets** — prefer framework-native, audited primitives over hand-rolled crypto/escaping: Symfony SecurityBundle `auto` password hasher (selects the strongest available algorithm, supports migration), Doctrine **parameterized** queries/QueryBuilder (never string-concatenated DQL), Twig **auto-escaping** (never `|raw` on user data, never dynamic templates from input), Symfony Serializer **write groups** to close mass-assignment, API Platform **voters/`security` expressions** for BOLA/BFLA, Paragon Initiative guidance on which PHP crypto functions to never use. Every fix names the cheat sheet / library it derives from.
- **Every fixed vuln gets a regression test** — a failing-then-passing test that reproduces the exploit and then proves it's closed (the plugin's `testing-workflow`/Infection MSI culture makes this enforceable; the fix is incomplete without it). This is the auto-remediation equivalent of TDD and prevents silent regression.
- **Re-test the same finding after the fix, then re-dispatch only still-open families** — the find→verify→fix→regress→re-verify→loop discipline, bounded at 5 iterations, identical in shape to the `code-review` AI-loop and `code-quality-reviewer` iteration discipline.

## 7. How this fits the plugin's SDLC, profile, and CI integration deltas

**Where it runs.** Most naturally an extension of (or sibling to) Stage 4 `/sdlc-review` — the verification gate — invoked as a skill the way `code-review` is, or dispatched after the quality lens passes. The skill orchestrates `security-auditor` subagents (find/verify) and routes fixes through the existing `php-implementer` agent (code edits), keeping the new agent **report-and-route** for findings but the **skill** owning the fix→regress→loop, paralleling how `/sdlc-review` drives remediation.

**New agent (`agents/security-auditor.md`).** Mirrors the verified agent anatomy (architecture §3): frontmatter `name`/`description`/`tools`/`model`; an 8-section body spine matching `qa-manual-tester`/`code-quality-reviewer` — **Profile keys consumed, Role, Inputs, Outputs, Allowed actions, Degrade paths, Iteration discipline, Smoke prompt**. Tools combine both precedents: `Bash, Read, Glob, Grep` (SAST/dep/secret/config + dynamic probing). Model **opus** (judgment-heavy, like `code-quality-reviewer`/`fr-nfr-reviewer`). Black-box-style probing of the running service + source-aware SAST — so, unlike `qa-manual-tester`, it MAY read source (it's white/grey-box by design), but it inherits the "verify against observed behavior, no false positives" rule and the "mutate only via the API" rule.

**New profile keys (add to `docs/profile-schema.md`).** Minimal, fitting existing conventions:
- `make.security` — nullable logical target for the repo's security/SAST suite (row in the `make` map; `null` ⇒ plugin runs its own bundled fallback or degrades, exactly like `make.ai_review_loop`/`make.pr_comments`/`make.fr_nfr_gate`).
- a `capabilities.*` boolean gating **dynamic** testing (e.g. `capabilities.dynamic_security_testing`), pairing with `make.start` the way `capabilities.load_testing` pairs with `make.load_tests` (schema lines 124–128). When false (or `make.start: null`), the dynamic probing stage degrades to skip-with-note; static/SAST/dep/secret/config still run.
The `profile-keys-check` CI job greps each skill's `## Profile keys consumed` header against `docs/profile-schema.md` — so both new keys MUST be documented there or CI fails (schema lines 5–13).

**Integration deltas (counts to bump — verified exact locations):**
- `tests/component-counts.bats`: **21→22 skills** (lines 11, 63–67 assertion `[ "$output" -eq 21 ]`), **6→7 agents** (lines 11, 57–61 `-eq 6`), and the NFR-1 header comment (lines 5–13).
- `skills/SKILL-DECISION-GUIDE.md` (line 118 "All 21 skills…") and `skills/AI-AGENT-GUIDE.md` (line 126 "Available Skills (21 Total)") → 22; add the new skill's triage row + cross-agent usage entry.
- PRD **NFR-1** "8/8 commands, 6/6 agents, 21/21 skills" → 6→7 agents, 21→22 skills; architecture §1.1 file-tree and §3 agent matrix add the new agent; README/docs component counts.
- New supporting files keep SKILL.md under ~500 lines: `reference/owasp-catalog.md` (§2/§3 enumerations), `reference/attack-playbooks.md` (§4 + WSTG techniques per family), `reference/remediation-patterns.md` (§6.3 secure-by-default fixes + cheat-sheet citations).

**Generalization (NFR-2).** No `user-service`/`VilnaCRM`/`Mongo*Repository`/`AppRunner`/`src/User`/`src/OAuth` literals outside `# profile-example` fences; the `generalization-audit` CI job (architecture §6) greps the denylist. All paths/contexts come from the profile (`architecture.source_root`, `architecture.bounded_contexts`, `persistence.mapper`, `framework.api_platform`, `framework.graphql`).

## 8. Risks

1. **False positives** — the #1 pentest failure mode. Mitigation: mandatory **reproduce-against-running-service** verification before any finding is reported or fixed; SAST output is a *candidate*, not a finding (§5, §6.1). A finding with no working reproduction is downgraded/dropped.
2. **Destructive / out-of-scope probing** — adversarial payloads against a real datastore. Mitigation: container-only, disposable instance, mutate-only-via-API, never touch hosts outside the profile-resolved local service, defensive/authorized framing throughout (§6.2).
3. **Token/time cost of fan-out** — many parallel opus subagents × 5 iterations is expensive. Mitigation: SAST-first triage to skip families with zero candidates; gate LLM/Mobile/memory-safety families as N/A-with-reason up front; bound at `MAX_ITERATIONS=5` (NFR-6); only re-dispatch still-open families.
4. **Capability variance** — repos with no `make.security`, no SAST configured, no bootable service, no GraphQL. Mitigation: nullable `make.security` + dynamic-testing capability gate + per-family N/A reasons (NFR-4 degrade-matrix); never hard-fail on absent capability.
5. **Fix-induced regressions / scope creep** — security fixes touching behavior. Mitigation: every fix carries a regression test, then the full quality gate (`make.ci`) and the affected family re-verify before the loop closes; route edits through the existing `php-implementer` rather than a new editing path.
6. **Suppression temptation under time pressure** — the loop could "pass" by silencing tools. Mitigation: the `code-review` forbidden-suppression diff scan (Step 6) and ADR-7 raise-only thresholds already block this; restate the prohibition in the new agent/skill.
7. **Corpus drift** — OWASP/CWE editions update (Top 10 2025 in progress, ASVS 5.0 new, CWE Top 25 annual). Mitigation: enumerations live in versioned `reference/` files with edition labels, not hard-coded in SKILL.md, so refreshes are localized.

## 9. Open questions (for PRD / architecture)

1. **Placement** — is `security-audit` a standalone skill invoked within `/sdlc-review`, a new sub-stage, or its own command surface? (Feature scope says skill + agent only — likely a skill triaged inside Stage 4, no new command — but the PRD must pin it.)
2. **Who fixes** — does `security-auditor` itself edit code, or strictly report/route while the skill dispatches `php-implementer` for fixes? (Leaning report-and-route to keep agent tool surface clean and reuse the implementer; needs an ADR.)
3. **Exact new capability key name** — `capabilities.dynamic_security_testing` vs `capabilities.dast` vs reusing existing flags; minimal-surface decision for the schema.
4. **Severity rigor** — CVSS-ish band (Critical/High/Medium/Low + rationale) vs full CVSS v3.1/v4.0 vector. (Leaning band-with-rationale for actionability; §3.)
5. **`make.security` fallback** — when `null`, does the plugin ship a bundled security script (à la ADR-4 `ai-review-loop.sh`) or degrade entirely? Affects `scripts/` surface and whether a `make.security`-null repo still gets SAST.
6. **LLM-family gating signal** — how to detect the target uses an LLM to switch the LLM Top 10 family on (composer deps? `clean-architecture-llm` artifacts? a profile flag?).
7. **Loop coupling with `make.ci`** — must every security fix re-run the full `make.ci` (expensive) each iteration, or only the affected tests + the family re-verify, with one final `make.ci`? (Token/time vs safety trade-off.)

## Sources

- OWASP Developer Guide — Top 10 history: https://devguide.owasp.org/en/07-training-education/05-top-ten/
- OWASP Top 10 (2010/2013/2017) categories: https://www.51sec.org/2021/10/30/owasp-top-10-2010-2013-2017/ ; evolution: https://www.rarefied.co/blog/owasp-top-10-evolution/
- OWASP API Security Top 10 2023 (primary): https://owasp.org/API-Security/editions/2023/en/0x11-t10/ ; 2019→2023 changes: https://www.veracode.com/blog/breaking-down-owasp-top-10-api-security-risks-2023-what-changed-2019/
- OWASP Top 10 for LLM Applications 2025 (primary): https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/
- OWASP ASVS (project + 5.0.0): https://owasp.org/www-project-application-security-verification-standard/
- OWASP Web Security Testing Guide & Cheat Sheet Series: https://owasp.org/www-project-web-security-testing-guide/ ; https://cheatsheetseries.owasp.org/cheatsheets/Symfony_Cheat_Sheet.html
- 2024 CWE Top 25 (primary, ordered list): https://cwe.mitre.org/top25/archive/2024/2024_cwe_top25.html ; CISA announcement: https://www.cisa.gov/news-events/alerts/2024/11/20/2024-cwe-top-25-most-dangerous-software-weaknesses
- Symfony / API-Platform vuln classes: https://hacktricks.wiki/en/network-services-pentesting/pentesting-web/symphony.html ; https://www.vaadata.com/blog/symfony-security-best-practices-vulnerabilities-and-attacks/ ; https://dev.to/pentest_testing_corp/idor-vulnerability-in-symfony-how-to-detect-and-fix-it-3g0e
- Multi-agent pentest frameworks: PentestGPT/LLM4Pentest https://github.com/simon-p-j-r/LLM4Pentest ; PENTEST-AI (MITRE ATT&CK) https://www.researchgate.net/publication/384299218 ; CurriculumPT https://www.mdpi.com/2076-3417/15/16/9096 ; AI offensive-tool survey https://hadrian.io/blog/the-ai-offensive-security-boom-seventy-tools-in-eighteen-months
- PHP SAST / SCA / secret tooling: Psalm taint analysis https://psalm.dev/docs/security_analysis/ ; Semgrep / Gitleaks / Trivy pipeline https://manabpokhrel7.medium.com/building-a-secure-gitlab-ci-cd-pipeline-with-sast-tools-gitleaks-hadolint-checkov-semgrep-8bd5501ec841
- Secure-by-default remediation: Symfony password hashing https://symfony.com/doc/current/security/passwords.html ; Paragon Initiative crypto guidance https://paragonie.com/blog/2017/02/cryptographically-secure-php-development
