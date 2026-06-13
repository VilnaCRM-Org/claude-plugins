---
stepsCompleted: [step-01-init, step-02-context, step-03-starter, step-04-decisions, step-05-patterns, step-06-structure, step-07-validation, step-08-complete]
inputDocuments:
  - specs/autonomous/2026-06-14-security-audit-skill/research.md
  - specs/autonomous/2026-06-14-security-audit-skill/product-brief.md
  - specs/autonomous/2026-06-14-security-audit-skill/prd.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/architecture.md
workflowType: 'architecture'
date: 2026-06-14
author: Winston (BMAD architect agent, autonomous run — interactive steps skipped, decisions recorded as ADRs)
---

# Architecture — `security-audit` Skill (+ `security-auditor` Agent) for `php-backend-sdlc`

The deliverable is a **delta on the existing `php-backend-sdlc` Claude Code plugin** (v1: 8 commands, 6 agents, 21 skills + 2 meta-guides). It adds exactly one skill (`skills/security-audit/SKILL.md` + three `reference/` files), one agent (`agents/security-auditor.md`), two profile keys (`make.security`, `capabilities.dynamic_security_testing`), and the count/guide integration edits — **no new command** (FR-2). Architecture inherits the parent plugin's idioms verbatim: runtime profile reads (ADR-1), the verified skill body format (§4 of the parent architecture), the six/eight-section agent spine (§3), container-only execution, raise-only thresholds (ADR-7), the `MAX_ITERATIONS=5` guard + canonical escalation block (§2), and the NFR-2/NFR-4 denylist + degrade rules. Conventions re-verified against the two anatomy precedents this feature mirrors: `agents/qa-manual-tester.md` (black-box HTTP probing, report-only, `make.start` boot, escalation block) and `agents/code-quality-reviewer.md` (read-only source analysis through `make.*`, opus model, suppression-prohibition). The multi-subagent fan-out reuses the proven parallel-`php-implementer` dispatch idiom (parent §7 stage 3) — no new infrastructure. Every section below traces to the PRD's FR-1..10 / NFR-1..9 and resolves the PRD's six Open Questions (OQ-1..6) as ADRs SA-1..SA-9.

## 1. Component Architecture

### 1.1 File tree (delta only — files added / modified)

```
plugins/php-backend-sdlc/
├── agents/
│   └── security-auditor.md                 # NEW agent #7 (FR-3): red-team subagent, one per OWASP family
├── skills/
│   ├── SKILL-DECISION-GUIDE.md             # MODIFY: "21"→"22"; add security-audit triage section + row (FR-10)
│   ├── AI-AGENT-GUIDE.md                   # MODIFY: "(21 Total)"→"(22 Total)"; add security-audit + security-auditor entries (FR-10)
│   └── security-audit/                      # NEW skill #22 (FR-1)
│       ├── SKILL.md                         # ≤ ~500 lines (NFR-9); enumerations delegated to reference/
│       └── reference/
│           ├── owasp-catalog.md             # FR-4: full OWASP/CWE corpus, edition-labelled
│           ├── attack-playbooks.md          # FR-5: per-family probe + reproduce-against-service step
│           └── remediation-patterns.md      # FR-6: secure-by-default, cheat-sheet-cited, suppression-free
├── commands/
│   └── sdlc-review.md                       # MODIFY: triage count "21"→"22" so security-audit gets a verdict row (FR-2)
├── docs/
│   └── profile-schema.md                    # MODIFY: add make.security row + capabilities.dynamic_security_testing row + example lines (FR-9)
├── tests/
│   └── component-counts.bats                # MODIFY: agents 6→7, skills 21→22, NFR-1 header comment (FR-10)
└── README.md                                # MODIFY: component counts 6→7 agents / 21→22 skills (FR-10)

Cross-spec count edits (parent plugin's own planning artifacts, FR-10):
specs/autonomous/2026-06-09-php-backend-sdlc-plugin/architecture.md   # §1.1 tree + §3 agent matrix gain the new agent (informational)
```

**No `scripts/` delta (SA-2):** there is no `make.security`-null bundled scanner script. The null fallback is the skill driving its bundled-tool lane (Psalm `--taint-analysis`, Semgrep, `composer audit`, secret-grep) directly through the existing container `make`/`docker compose exec php` surface — mirroring how `code-quality-reviewer` runs read-only `make.*` targets, not a new `scripts/security-loop.sh`. This keeps the scripts surface (and its bats suite) unchanged.

### 1.2 Dependency direction (inherits parent §1.2, strict, CI-checkable)

```
commands  ──►  agents (Task tool)            : /sdlc-review (or standalone) ─► security-auditor (parallel fan-out)
skills    ──►  agents?  NO                    : the security-audit SKILL is loaded BY the orchestrator that owns the Task tool;
                                               the skill body PRESCRIBES the fan-out, the orchestrator EXECUTES it (parent rule: "skills never invoke agents")
security-auditor ──► php-implementer?  NO     : the auditor reports; the ORCHESTRATOR routes verified findings to php-implementer (SA-3, A2)
skills    ──►  .claude/php-sdlc.yml (runtime read) + sibling reference/ files (relative links only)
agents    ──►  scripts? NO new edge          : security-auditor uses container make/docker, no plugin script (SA-2)
```

Re-stated forbidden edges (unchanged): the SKILL.md file never contains a Task-tool call (it is text the orchestrator follows); `security-auditor` never edits code (no `Edit`/`Write` in its tools — SA-3); `security-auditor` never invokes `php-implementer` or any command. The single new data dependency is **finding records** flowing auditor → orchestrator → `php-implementer` (SA-5 contract, §6).

## 2. Where it lives in the SDLC (FR-2, resolves A1)

`security-audit` is a **triaged skill**, not a command. Two entry points, identical body:

1. **Inside Stage 4 `/sdlc-review`** — the existing applicability triage (parent ADR-5) already records an EXECUTE / NOT-APPLICABLE verdict for every `skills/*/SKILL.md`. Raising the triage count 21→22 (FR-2 AC) makes `security-audit` one more triaged row. Its frontmatter `description` carries the trigger + gate so the reviewer can decide the verdict without loading the body (parent §4 convention). It is the *adversarial security lens* alongside the quality lens (`code-quality-reviewer`) and the spec lens (`fr-nfr-reviewer`).
2. **Standalone** — invokable directly as `php-backend-sdlc:security-audit` against an authorized target (NFR-1).

The **command surface stays 8** (FR-2 AC; no `/sdlc-security`). The skill **owns the loop** (triage→fan-out→find→verify→fix→regress→re-verify→loop); the `security-auditor` subagents are **find/verify only**; code edits route through the existing `php-implementer` (SA-3). On a verified-but-unfixable finding at iteration 5, the loop emits the parent's canonical escalation block (§2 of parent) and stops — never auto-resetting a breaker (NFR-2).

## 3. `security-auditor` Agent Anatomy (FR-3)

Frontmatter — the four mandatory keys (`component-counts.bats` asserts them), tools combining both precedents, model opus (judgment-heavy, like `code-quality-reviewer` / `fr-nfr-reviewer`):

```markdown
---
name: security-auditor
description: >-
  Authorized, defensive red-team subagent for the security-audit skill.
  Delegate one instance per OWASP/vuln family when an adversarial
  security verdict is needed for a PHP backend the caller owns: it
  attacks the RUNNING service (black-box HTTP/GraphQL probing, the
  qa-manual-tester shape) AND inspects source (SAST/taint, dependency,
  secret, config — the code-quality-reviewer shape) for its one assigned
  family, VERIFIES every candidate by reproducing it against the running
  service (no false positives), and reports verified findings mapped to
  CWE + OWASP id + CVSS-ish severity with a cited remediation. Use it
  for "red-team the auth family", "probe BOLA/IDOR", "SAST+DAST the SQLi
  surface". Authorized/defensive use only: it probes ONLY the
  profile-resolved local service, never exfiltrates, mutates state only
  through the service's own API, runs container-only, and never edits
  code — verified findings route to php-implementer by the caller.
tools: Bash, Read, Glob, Grep
model: opus
---
```

`tools` rationale: `Bash` (container `make`/`docker compose exec php` for SAST + `curl`/GraphQL POST for dynamic probing), `Read`/`Glob`/`Grep` (white/grey-box source inspection — the deliberate difference from `qa-manual-tester`, which forbids source reads; this agent is grey-box by design, FR-3). **No `Edit`/`Write`** (SA-3, report-and-route; NFR-7). Body = the **eight-section spine** (FR-3 AC), in this fixed order:

| # | Section | Content (mirrors precedent) |
|---|---|---|
| 1 | **Profile keys consumed** | `make.security`, `capabilities.dynamic_security_testing`, `make.start`, `make.ci`, `make.psalm`, `architecture.source_root`, `architecture.bounded_contexts`, `framework.api_platform`, `framework.graphql`, `persistence.mapper`, `persistence.engine` (the inline-code dotted-path convention, parent §4) |
| 2 | **Role** | the red-team unit for ONE assigned family; grey-box (MAY read source, unlike `qa-manual-tester`) but inherits "verdict from observed behavior, no false positives" and "mutate state only through the service's own API"; restates the NFR-5 authorized/defensive boundary verbatim (in-scope target only, no exfiltration, mutate-via-API-only, no destructive non-API ops, container-only) |
| 3 | **Inputs** | dispatch prompt (assigned OWASP family id, its `reference/attack-playbooks.md` entry, the report contract, the iteration number from the skill guard, prior ledger on re-dispatch); the profile; the running service base URL; the source tree |
| 4 | **Outputs** | the finding-record report (§6 schema): verified findings only, each with reproduction steps + CWE id + OWASP id + severity band-with-rationale + cited remediation from `reference/remediation-patterns.md`; or a clean-for-this-family verdict. Report-and-route — never edits code |
| 5 | **Allowed actions** | `Bash`: `make <make.security>` / `make <make.psalm>` / `docker compose exec php` for SAST-taint/dep/secret/config, and `curl`/`jq`/GraphQL POST for dynamic probing of the running service; `Read`/`Glob`/`Grep` for source localization. Forbidden (verbatim from precedents): editing any file; git commands; package installation on the host; out-of-band datastore mutation; probing any host/URL outside the profile-resolved local service; any destructive non-API operation; ignore semgrep `SEMGREP_APP_TOKEN` hook noise |
| 6 | **Degrade paths** | `make.security: null` ⇒ run the bundled/static lane for its family (Psalm `--taint-analysis`, Semgrep, `composer audit`, secret-grep) via container `make`/`docker`, no hard-fail (SA-2); `capabilities.dynamic_security_testing: false` OR `make.start: null` ⇒ static-only with a skip-note for dynamic probing (no improvised host boot); family N/A ⇒ recorded reason, no fabricated finding; never loop, never hard-fail (NFR-3) |
| 7 | **Iteration discipline** | own counter, `MAX_ITERATIONS=5`, never reset; stateless across dispatches — resumes from the dispatched iteration number; re-dispatched only while its family stays open; a verified finding is reported once then routed (re-probing unchanged code can't change the verdict); on exhaustion/blocking emit the canonical escalation block (`stage: security-audit (security-auditor:<family>)`) |
| 8 | **Smoke prompt** | happy path (one family — e.g. SQLi — verified finding with reproduction + CWE-89/A03:2021/severity + cited Doctrine-parameterization remediation, having written no files and run no git) + degrade path (`make.security: null` → static-only lane, skip-note for dynamic, no escalation, no FAIL) |

## 4. `security-audit` SKILL.md Section Structure (FR-1, NFR-9)

Frontmatter: `name: security-audit` (= dir name, asserted by `component-counts.bats`) + a trigger-rich `description` ("Use when red-teaming / security-auditing / penetration-testing an authorized PHP backend… Defensive/authorized use only. Skip dynamic probing with a note when `capabilities.dynamic_security_testing` is false"). Body sections, **in this fixed order** (mirrors the verified Context/Task/Steps/Constraints/Format/Verification format + the parent's "Profile keys consumed first H2" rule):

1. **`## Profile keys consumed`** (first H2 — mandatory, parent §4) — the same dotted-path list the agent consumes (§3 row 1), so `profile-keys-check` is green (FR-9 AC).
2. **`## Gating`** — defensive/authorized boundary restated verbatim (NFR-5); `capabilities.dynamic_security_testing: false` or `make.start: null` ⇒ static-only with note; `framework.graphql: false` ⇒ GraphQL family N/A; LLM family gated on detected LLM usage (SA-7).
3. **`## Context`** — what this skill is (adversarial multi-subagent red-team loop), where it runs (triaged in Stage 4 / standalone, FR-2), its no-false-positive + root-cause + container-only culture.
4. **`## Task`** — the single measurable goal: every OWASP family in `reference/owasp-catalog.md` triaged (PROBE / N/A-with-reason), every PROBE family driven to zero new verified findings, every fix root-cause + regression-tested.
5. **`## Steps`** — the canonical loop, each enumeration *delegated to a reference file* so SKILL stays ≤ ~500 lines (NFR-9):
   - **5.1 Triage** — read `reference/owasp-catalog.md`; record a per-family verdict table (PROBE / N/A-with-reason). No silent skips (NFR-6). N/A up front: Mobile, memory-safety CWEs, LLM-when-not-detected (NFR-8 cost gate).
   - **5.2 Fan-out** — dispatch one `security-auditor` subagent **per PROBE family in parallel** (the §5 dispatch design), passing each its `attack-playbooks.md` entry + the report contract + iteration number.
   - **5.3 Find → verify** — each subagent runs SAST/dep/secret/config **and** dynamic probing; a SAST candidate is **never** a finding until reproduced against the running service (FR-7, NFR-6).
   - **5.4 Aggregate / dedupe / promote** — the orchestrator collects subagent reports, dedupes by (CWE, sink, endpoint), promotes only reproduced candidates to findings (§5.2).
   - **5.5 Fix → regression-test** — route each verified finding to `php-implementer` (SA-5 contract, §6) with the cited remediation from `reference/remediation-patterns.md`; each fix carries a failing-then-passing regression test (FR-8, NFR-7).
   - **5.6 Re-verify → loop** — re-dispatch only still-open families; bounded `MAX_ITERATIONS=5`; run affected-family re-verify each iteration + one final `make.ci` at loop close (SA-6, resolves OQ-4); exit on a zero-new-verified-findings iteration; escalate on breach (NFR-2).
6. **`## Constraints`** — verbatim: defensive/authorized boundary (NFR-5); container-only (`make`/`docker compose exec php`, never host binaries); root-cause only, zero suppression / baseline / threshold-lowering / `deptrac.yaml` edit (NFR-7, binds ADR-7); generalization — no source-project literals outside `# profile-example` (NFR-4); SKILL ≤ ~500 lines (NFR-9).
7. **`## Format`** — the finding-record schema (§6) + the run report shape (per-family verdict table, per-iteration finding counts, `MAX_ITERATIONS=5` counter, zero-new-findings exit, SUCCESS-WITH-REPORT vs ESCALATED status).
8. **`## Verification`** — every family triaged; every reported finding carries reproduction + CWE + OWASP id + severity; a non-reproducible candidate is recorded downgraded/dropped; `make.ci` green at close; forbidden-suppression scan clean (inherited from `code-review` Step 6 / parent ADR-7).
9. **`## Related Skills`** (closing) — relative links: `../code-review/SKILL.md` (suppression scan + per-comment ledger it reuses), `../testing-workflow/SKILL.md` (regression-test home), `../ci-workflow/SKILL.md` (`make.ci` gate), `../bmad-fr-nfr-review-gate/SKILL.md` (sibling gate lens). All `../`-relative (parent ADR-11 keeps links valid in the install cache).

CI line-count check (NFR-9 AC): `wc -l skills/security-audit/SKILL.md` ≤ ~500; every enumeration (OWASP families, playbooks, remediations) lives in `reference/`, never inline.

## 5. Multi-Subagent Dispatch Design (FR-1, NFR-2, NFR-8 — resolves OQ-5)

### 5.1 Fan-out (parallel red-team)

The orchestrator (the `/sdlc-review` agent or a standalone invocation that holds the `Task` tool) executes Step 5.2 by **issuing N `Task`-tool dispatches in one turn**, one `security-auditor` per PROBE family — the proven parallel-`php-implementer` idiom (parent §7 stage 3), no new infrastructure. The family set (resolved from `reference/owasp-catalog.md`, gated by the profile):

| Family (OWASP id) | Probe lens | Profile gate |
|---|---|---|
| BOLA / IDOR (API1:2023) | object-id / IRI swap | always |
| BOPLA / mass-assignment (API3:2023) | write-group / denormalization probing | always |
| BFLA (API5:2023) | `#[IsGranted]` / `security` expression bypass | always |
| Injection — SQLi/DQL (A03:2021, CWE-89) | taint to DQL / native sink | always |
| SSTI (CWE-1336) | Twig `|raw` / dynamic-template injection | always |
| Insecure deserialization (A08:2021, CWE-502) | `unserialize`/object-injection sinks | always |
| SSRF (A10:2021, CWE-918) | URL-fetch sink probing | always |
| Auth / session (A07:2021) | JWT `none`/alg-confusion, hashing, expiry, fixation | always |
| Security misconfiguration (A05:2021) | `APP_ENV`/profiler/CORS/headers/TLS | always |
| Vulnerable / outdated deps (A06:2021) | `composer audit` + advisory DB | always |
| Cryptographic failures / secrets (A02:2021, CWE-798) | secret-scan + crypto-primitive review | always |
| File upload / SSRF-via-upload (CWE-434) | upload-handler probing | when an upload surface exists |
| Rate / resource exhaustion (API4:2023) | unbounded-query / no-rate-limit probing | always |
| GraphQL (introspection / deep-query / batching) | introspection + depth/batch abuse | `framework.graphql: true` only |
| LLM Top 10 (prompt-injection etc.) | prompt-injection / output-handling | LLM usage detected (SA-7) only |

N/A families (Mobile, memory-safety CWEs, LLM-when-not-detected) are **excluded before fan-out** (NFR-8 cost gate) with a recorded N/A-with-reason verdict (NFR-6) — never dispatched.

### 5.2 Aggregate / dedupe / verify / promote

The orchestrator collects the N subagent reports and:
- **Dedupes** findings by the tuple `(CWE id, sink location file:line, exploited endpoint)` — two families hitting the same sink collapse to one finding (NFR-8).
- **Promotes** only reproduced candidates to findings — a candidate without a working reproduction is recorded *downgraded/dropped*, never reported (FR-7, NFR-6); subagents already enforce this, the orchestrator is the second gate.
- **Orders** the promoted findings by severity band (Critical → Low) for the fix queue.

### 5.3 Bounded loop + escalation (NFR-2)

```
iteration ← 1
loop:
  dispatch security-auditor for each still-open PROBE family (parallel)   # 5.1
  collect + dedupe + promote verified findings                            # 5.2
  if zero new verified findings: exit SUCCESS-WITH-REPORT                 # exit condition
  route each finding → php-implementer (root-cause fix + regression test) # 5.5 / SA-5
  affected-family re-verify                                               # SA-6
  iteration ← iteration + 1
  if iteration > 5  OR  php-implementer/Ralph breaker tripped:            # NFR-2
     emit canonical escalation block; STOP (never auto-reset breaker)
final: run make.ci once; forbidden-suppression scan; emit run report
```

Re-dispatch each iteration covers **only still-open families** (NFR-8 AC: the re-dispatch set shrinks). The escalation block is the parent's canonical format (§2 of parent), with `stage: security-audit`, the open-family list, per-iteration finding counts, the last blocking finding, and a recommended action.

## 6. Finding-Record Contract (resolves OQ-5 / OQ-6, SA-5)

The single hand-off shape, emitted by `security-auditor` and consumed by the orchestrator → `php-implementer`:

```text
FINDING <family-id>-<n>
  cwe: CWE-<id>                 # mapped from reference/owasp-catalog.md
  owasp: <A0X:2021 | APIx:2023 | LLMxx>   # edition-labelled id
  severity: Critical|High|Medium|Low      # band + one-line rationale (SA-8; full CVSS vector optional)
  location: <source_root>/<path>:<line>   # the sink, profile-resolved path (no literals)
  endpoint: <METHOD> <path>               # the exploited surface
  reproduction:
    1. <exact container/curl command>
    2. <exact command>            # copy-pasteable against a freshly booted disposable instance
  expected: <secure behavior>   observed: <vulnerable behavior>
  remediation: <vetted library/primitive + cited OWASP cheat sheet>   # from remediation-patterns.md
  regression_test: <test path the fix must add>   # failing-before / passing-after
```

`php-implementer` receives `{location, remediation, regression_test}` and produces the root-cause fix + the failing-then-passing test (FR-8); the affected-family `security-auditor` then re-verifies that the reproduction no longer succeeds (SA-6). Severity is a **band-with-rationale** (SA-8, resolves OQ-6); a full CVSS v3.1/v4.0 vector is an optional field, never mandated (PRD §6).

## 7. Reference Catalog Files (FR-4, FR-5, FR-6, NFR-9)

| File | FR | Contents | Edition labels (NFR-9 AC) |
|---|---|---|---|
| `reference/owasp-catalog.md` | FR-4 | the **full corpus** with per-family CWE mapping + a PHP-relevance / N/A-with-reason column; the single source the triage table draws from | Top 10 web 2003/2004/2007/2010/2013/2017/2021; API Top 10 2019/2023; LLM Top 10 2025 v2.0; Mobile 2014/2016/2024 (N/A-for-backend + reason); ASVS 5.0 (L1/L2/L3, **L2 default bar**); WSTG 4.2 (test-methodology index); Proactive Controls / Cheat Sheet Series (remediation source-of-truth pointer); CWE Top 25 2024 (ordered, PHP-relevance, memory-safety CWEs N/A-with-reason); SANS = same Top 25 taxonomy |
| `reference/attack-playbooks.md` | FR-5 | per-family probing methodology, **WSTG-test-id mapped**; each entry states a concrete probe **and** the reproduce-against-running-service verification step; names the tool (`curl`/`jq`/GraphQL POST, Psalm `--taint-analysis`, Semgrep, `composer audit`, secret-scan); stack-generic (profile-resolved paths, no literals — NFR-4) | references WSTG 4.2 test ids |
| `reference/remediation-patterns.md` | FR-6 | secure-by-default, root-cause fix per class, citing the OWASP cheat sheet + vetted library: Symfony SecurityBundle `auto` password hasher; Doctrine parameterized queries / QueryBuilder (never concatenated DQL); Twig auto-escaping (never `|raw` on user input); Symfony Serializer write-groups (mass-assignment); API Platform voters / `security` expressions (BOLA/BFLA); Paragon Initiative crypto guidance. States **"root-cause only, zero suppression"** + **"every fix gets a failing-then-passing regression test"** verbatim; recommends **no** suppression/baseline/config-relaxation/threshold-reduction anywhere (NFR-7) | cheat-sheet edition pointer |

All three carry edition labels (NFR-9), use profile-resolved paths only (NFR-4 — the `generalization-audit` CI job runs over them), and are linked from SKILL.md with `../`-relative paths.

## 8. New Profile Keys (FR-9 — resolves OQ-1, OQ-2)

Two minimal keys, following the existing schema conventions exactly. Schema-table rows for `docs/profile-schema.md`:

Added to the **`make` — logical target map** table (after `make.load_tests`):

| Key | Required | Default target | Capability |
| --- | --- | --- | --- |
| `make.security` | yes (nullable) | `null` | Security/SAST suite; plugin runs its bundled static lane (Psalm taint / Semgrep / `composer audit` / secret-scan) when `null` (SA-2). Mirrors `make.ai_review_loop`/`make.pr_comments`/`make.fr_nfr_gate` null-substitution precedent. |

Added to the **`capabilities`** table (after `capabilities.load_testing`):

| Key | Required | Type | Default | Notes |
| --- | --- | --- | --- | --- |
| `capabilities.dynamic_security_testing` | no | bool | `false` | Gates **dynamic** (live-service) security probing in `security-audit`; pairs with `make.start` the way `capabilities.load_testing` pairs with `make.load_tests`. When `false` (or `make.start: null`), dynamic probing degrades to skip-with-note; static/SAST/dep/secret/config lanes still run (NFR-3). |

Annotated `# profile-example` block (FR-9 AC — both keys present): add `security: null` to the `make:` map and `dynamic_security_testing: false` to `capabilities:` in the canonical example. (Name resolved per SA-9: `capabilities.dynamic_security_testing` over `dast` — schema reads as prose, matches `load_testing`/`structurizr` style.) Both keys appear in the skill's and agent's `## Profile keys consumed` headers so `profile-keys-check` greps clean (FR-9 AC).

## 9. Integration Edits (FR-10)

| File | Edit | AC |
|---|---|---|
| `tests/component-counts.bats` | `@test "exactly 6 agent…"` → `7`; `@test "exactly 21 skills…"` → `22`; header comment "8 commands / 6 agents / 21 skills" → "8 commands / 7 agents / 22 skills"; the `claude plugin` smoke comment "6 agents, and 21 skills" → "7 agents, and 22 skills" | NFR-1: asserts 8/7/22 against install-cache layout |
| `skills/SKILL-DECISION-GUIDE.md` | "All 21 skills…" → 22 (every `21` occurrence in skill-count prose); add a `## Security audit` decision section + a `**Use**: [security-audit](security-audit/SKILL.md)` row + the disambiguation-table row ("security-audit vs code-review: **adversarial vuln-hunting against the running service** → security-audit; **PR-comment / quality review** → code-review") | FR-10: 22 + new row |
| `skills/AI-AGENT-GUIDE.md` | "Available Skills (21 Total)" → "(22 Total)"; add the `security-audit` usage entry (steps to read SKILL + reference/) and a `security-auditor` cross-agent entry | FR-10: 22 + entries |
| `commands/sdlc-review.md` | every "21" triage reference → "22" (`21-skill triage` in description, "21 in v1", "All 21 verdicts", "21/21 skills", "Skill triage (21/21 verdicts)", "all 21" comment) | FR-2 AC: triage list includes a `security-audit` row, count 22/22 |
| `docs/profile-schema.md` | the two §8 rows + the two example lines | FR-9 AC |
| `README.md` | component counts (6→7 agents, 21→22 skills) wherever stated | FR-10 AC: no stale count |
| parent `specs/.../2026-06-09-…/architecture.md` | §1.1 tree `agents/` (add `security-auditor.md`) + `skills/` (add `security-audit/`); §3 agent matrix gains a `security-auditor \| opus \| Bash, Read, Glob, Grep` row; counts "6 subagents"→7, "21 skills"→22 | FR-10: NFR-1 counts consistent across the plugin tree |

This feature's **own PRD NFR-1** already states 8/7/22 (verified in `prd.md`). The `generalization-audit` CI job (parent §6) runs over all NEW files (skill, agent, reference, schema edits) — the denylist (`VilnaCRM` outside manifests, `user-service`, `Mongo[A-Z]\w*Repository`, `AppRunner`, `src/User`, `src/OAuth`, workspace.dsl container names) must not appear outside `# profile-example` fences (NFR-4 AC).

## 10. Error Handling & Degrade Matrix (delta — extends parent §8)

| Condition | Detected by | Behavior | Status |
|---|---|---|---|
| `make.security: null` | profile | run bundled static lane (Psalm taint / Semgrep / `composer audit` / secret-scan) via container; no dynamic dependency added (SA-2) | SUCCESS-WITH-REPORT |
| `capabilities.dynamic_security_testing: false` or `make.start: null` | profile | dynamic probing skip-with-note; static/SAST/dep/secret/config lanes still run | SUCCESS-WITH-REPORT |
| `framework.graphql: false` | profile | GraphQL family N/A-with-reason; not dispatched | SUCCESS-WITH-REPORT |
| LLM usage not detected | composer deps / `clean-architecture-llm` artifacts / profile signal (SA-7) | LLM Top 10 family N/A-with-reason; not dispatched | SUCCESS-WITH-REPORT |
| No SAST tool resolvable | `make.security: null` + bundled lane tool absent | that lane degrades with a note; remaining lanes run | SUCCESS-WITH-REPORT |
| Verified finding unfixable at iter 5 | iteration counter = 5 | canonical escalation block (§5.3); run halts | ESCALATED |
| `php-implementer` / Ralph breaker open | `---RALPH_STATUS---` / breaker files | stop the loop, escalation report, never reset (NFR-2) | ESCALATED |
| Out-of-profile host targeted | NFR-5 boundary in skill/agent prompts | refuse; the action is forbidden by the agent's Allowed-actions / Constraints | n/a (blocked) |

Rule (inherits parent NFR-4): degrade paths never loop and never hard-fail; only guard breach / breaker / a verified-unfixable finding produce ESCALATED.

## 11. Architecture Decision Records

- **SA-1 — Skill + agent, no new command** (PRD A1, FR-2): `security-audit` is a triaged skill inside Stage 4 `/sdlc-review` (and standalone), not a `/sdlc-security` command. *Why:* the triage gate (parent ADR-5) already enumerates every skill; one more row gives the security lens first-class verdict coverage at zero command-surface cost. Command count stays 8. *Rejected:* a dedicated command — duplicates the review-gate orchestration and adds a surface the PRD scopes out (§6).
- **SA-2 — `make.security`-null = bundled static lane, no new script** (PRD A5, OQ-2): a null `make.security` runs the skill's own SAST/dep/secret/config lane (Psalm `--taint-analysis`, Semgrep, `composer audit`, secret-grep) directly through the existing container `make`/`docker compose exec php` surface — exactly how `code-quality-reviewer` runs read-only `make.*`. *Why:* keeps the `scripts/` surface and its bats suite unchanged; no `scripts/security-loop.sh` to vendor/maintain; null-substitution mirrors `make.ai_review_loop`. *Rejected:* shipping a bundled `scripts/security-loop.sh` (parent ADR-4 style) — heavier surface than the PRD's "minimal fallback" (§6) warrants, and the tools already run via `make`/container.
- **SA-3 — `security-auditor` is report-and-route, not an editor** (PRD A2, FR-3): the agent's tools are `Bash, Read, Glob, Grep` — **no `Edit`/`Write`**. Verified findings route through the existing `php-implementer`. *Why:* keeps the auditor's tool surface clean and reuses the proven container-only implementer; preserves the parent's "one agent edits, others report" separation (mirrors `code-quality-reviewer` / `qa-manual-tester` / `fr-nfr-reviewer`). *Rejected:* an editing auditor — two editing agents fragment the root-cause/regression discipline `php-implementer` already enforces.
- **SA-4 — Black-box + SAST hybrid, grey-box agent** (FR-3, FR-7): the auditor MAY read source (unlike `qa-manual-tester`) so it can taint-trace a SAST candidate to its sink, but a finding is **only** real when reproduced against the running service. *Why:* pure black-box misses source-evident classes (committed secrets, deserialization sinks); pure SAST is false-positive-prone. Grey-box + reproduce-to-promote (FR-7) gets coverage *and* zero false positives. *Rejected:* black-box-only (misses static classes) and SAST-only (false positives — violates NFR-6).
- **SA-5 — Finding-record hand-off contract** (PRD OQ-5, §6): a fixed finding record (`cwe / owasp / severity / location / endpoint / reproduction / remediation / regression_test`) is the single shape auditor → orchestrator → `php-implementer`. *Why:* a typed contract lets the orchestrator dedupe (NFR-8), lets `php-implementer` fix without re-discovery (the `code-quality-reviewer` precedent), and makes the regression-test requirement (FR-8) machine-checkable.
- **SA-6 — Affected-family re-verify each iteration, one final `make.ci`** (PRD OQ-4): per iteration, re-run only the affected family's reproduction + its regression test; run the full `make.ci` **once** at loop close. *Why:* full `make.ci` per iteration is expensive (token/time); the affected-family reproduction is the precise correctness signal, and the final `make.ci` is the safety net (FR-8 AC: loop closes with `make.ci` green). *Rejected:* `make.ci` every iteration (cost) and no `make.ci` at all (loses the safety gate).
- **SA-7 — LLM-family gating signal** (PRD A4, OQ-3): the LLM Top 10 family is PROBE only when target LLM usage is detected — composer deps (e.g. an LLM SDK), presence of `clean-architecture-llm` artifacts in the source tree, or an explicit profile signal. *Why:* avoids fabricating LLM findings on a non-AI backend (NFR-6) and saves the fan-out cost of a guaranteed-N/A family (NFR-8). Otherwise recorded N/A-with-reason.
- **SA-8 — Severity = band-with-rationale, CVSS optional** (PRD A3, OQ-6): findings carry a Critical/High/Medium/Low band + a one-line rationale; a full CVSS v3.1/v4.0 vector is an optional field. *Why:* a band drives fix-queue ordering without the precision-theatre of a full vector on a self-audit; PRD §6 scopes full CVSS out. Optional field keeps the door open for repos that want it.
- **SA-9 — Capability key name `capabilities.dynamic_security_testing`** (PRD OQ-1): over `capabilities.dast` or reusing an existing flag. *Why:* the schema's capability keys read as prose (`structurizr`, `observability_emf`, `load_testing`); `dynamic_security_testing` matches that house style and pairs legibly with `make.start`. *Rejected:* `dast` (jargon, breaks the naming pattern) and reusing `load_testing` (different capability, would conflate gates).
- **SA-10 — Authorized-use-only safety boundary** (NFR-5): both SKILL.md and `security-auditor.md` restate, verbatim, the four boundary rules — in-scope (profile-resolved local service) target only; no exfiltration; mutate state only through the service's own API; container-only, no destructive non-API operations. *Why:* the feature is offensive *technique* for a defensive *purpose*; the boundary must be unmissable in both the orchestration text and every dispatched subagent's prompt, not just documented once. Enforced at the Allowed-actions / Constraints level (a forbidden action), not merely as advisory prose.

## 12. Validation (self-check against PRD release gate §4)

- FR-1..10 each map to a § here (FR-1→§4/§5, FR-2→§2, FR-3→§3, FR-4..6→§7, FR-7→§5.2/SA-4, FR-8→§5.5/§6/SA-6, FR-9→§8, FR-10→§9). NFR-1..9 each map (NFR-1→§9, NFR-2→§5.3, NFR-3→§10, NFR-4→§7/§9, NFR-5→§3/SA-10, NFR-6→§5.2/§5.1, NFR-7→§4.6/§7, NFR-8→§5.1/§5.2, NFR-9→§4/§7).
- CI-automated ACs are covered by existing jobs unchanged in shape: `component-counts.bats` (8/7/22), `generalization-audit` (new files), markdownlint + SKILL line-count (NFR-9), `profile-keys-check` (both new keys declared in skill+agent headers and documented in schema). No new CI job is required — the deltas fit the parent §6 matrix.
- Every OQ resolved: OQ-1→SA-9/§8, OQ-2→SA-2, OQ-3→SA-7, OQ-4→SA-6, OQ-5→SA-5/§6, OQ-6→SA-8.
