# OWASP / CWE Catalog — full corpus, edition-labelled

This is the **single source of truth** for the `security-audit` triage table.
The skill's Step 5.1 reads this file and records a per-family verdict — **PROBE**
or **N/A-with-reason** — for every row below; no family is silently skipped
(NFR-6). Probing methodology per family lives in
[`attack-playbooks.md`](attack-playbooks.md); the secure-by-default fixes live in
[`remediation-patterns.md`](remediation-patterns.md).

Every entry carries an **edition label** so a corpus refresh is localized to one
row. Paths are profile-resolved (`architecture.source_root`,
`architecture.bounded_contexts`, `persistence.mapper`, `framework.api_platform`,
`framework.graphql`) — no source-project literals (NFR-4).

Editions current as of this catalog: OWASP Top 10 **2021**, API Security Top 10
**2023**, LLM Top 10 **2025 v2.0**, Mobile Top 10 **2024**, ASVS **5.0**, WSTG
**4.2**, CWE Top 25 **2024**.

## How to read the relevance column

- **PHP-relevant** — managed-PHP backends are exposed to this class; the family
  is dispatchable when its profile gate is satisfied.
- **N/A-with-reason** — recorded with an explicit reason, never probed, never
  fabricated as a finding (NFR-6, NFR-8). Memory-safety CWEs (buffer/overflow,
  use-after-free, OOB read/write) are N/A because PHP is a memory-managed runtime
  with no manual pointer arithmetic; OWASP Mobile is N/A because this plugin
  targets server-side backends, not mobile clients.

## OWASP Top 10 (web) — all editions

The 2021 edition is the **active triage baseline**; older editions are retained
so historical references in legacy specs resolve and so a category that moved
between editions is traceable to its current home.

| Edition | Category | Active 2021 home | Mapped CWE(s) | PHP relevance |
| --- | --- | --- | --- | --- |
| **2003** | A1 Unvalidated Parameters | A03 Injection | CWE-20, CWE-89 | PHP-relevant |
| **2003** | A2 Broken Access Control | A01 Broken Access Control | CWE-284, CWE-639 | PHP-relevant |
| **2003** | A3 Broken Account/Session Mgmt | A07 Identification & Auth Failures | CWE-287, CWE-384 | PHP-relevant |
| **2003** | A4 Cross-Site Scripting | A03 Injection | CWE-79 | PHP-relevant (Twig output) |
| **2003** | A5 Buffer Overflow | — (runtime-level) | CWE-120, CWE-119 | **N/A-with-reason**: memory-safety, managed runtime |
| **2003** | A6 Command Injection | A03 Injection | CWE-77, CWE-78 | PHP-relevant (shell sinks) |
| **2003** | A7 Error Handling | A05 Security Misconfiguration | CWE-209, CWE-200 | PHP-relevant (debug leakage) |
| **2003** | A8 Insecure Use of Cryptography | A02 Cryptographic Failures | CWE-327, CWE-326 | PHP-relevant |
| **2003** | A9 Remote Administration Flaws | A05 Security Misconfiguration | CWE-16 | PHP-relevant (profiler/admin) |
| **2003** | A10 Web/App Server Misconfig | A05 Security Misconfiguration | CWE-16 | PHP-relevant |
| **2004** | A1 Unvalidated Input | A03 Injection | CWE-20 | PHP-relevant |
| **2004** | A2 Broken Access Control | A01 Broken Access Control | CWE-284 | PHP-relevant |
| **2004** | A3 Broken Auth & Session Mgmt | A07 Auth Failures | CWE-287 | PHP-relevant |
| **2004** | A4 Cross-Site Scripting | A03 Injection | CWE-79 | PHP-relevant |
| **2004** | A5 Buffer Overflow | — (runtime-level) | CWE-120 | **N/A-with-reason**: memory-safety |
| **2004** | A6 Injection Flaws | A03 Injection | CWE-89, CWE-78 | PHP-relevant |
| **2004** | A7 Improper Error Handling | A05 Misconfiguration | CWE-209 | PHP-relevant |
| **2004** | A8 Insecure Storage | A02 Cryptographic Failures | CWE-311 | PHP-relevant |
| **2004** | A9 Application Denial of Service | API4 Resource Consumption | CWE-400 | PHP-relevant |
| **2004** | A10 Insecure Config Management | A05 Misconfiguration | CWE-16 | PHP-relevant |
| **2007** | A1 Cross-Site Scripting | A03 Injection | CWE-79 | PHP-relevant |
| **2007** | A2 Injection Flaws | A03 Injection | CWE-89 | PHP-relevant |
| **2007** | A3 Malicious File Execution | A03 / A08 | CWE-434, CWE-98 | PHP-relevant (RFI/LFI, upload) |
| **2007** | A4 Insecure Direct Object Reference | A01 Broken Access Control | CWE-639 | PHP-relevant (IDOR/BOLA) |
| **2007** | A5 Cross-Site Request Forgery | A01 Broken Access Control | CWE-352 | PHP-relevant (state-changing API) |
| **2007** | A6 Information Leakage & Error Handling | A05 Misconfiguration | CWE-209 | PHP-relevant |
| **2007** | A7 Broken Auth & Session Mgmt | A07 Auth Failures | CWE-287 | PHP-relevant |
| **2007** | A8 Insecure Cryptographic Storage | A02 Cryptographic Failures | CWE-311 | PHP-relevant |
| **2007** | A9 Insecure Communications | A02 Cryptographic Failures | CWE-319 | PHP-relevant (TLS) |
| **2007** | A10 Failure to Restrict URL Access | A01 Broken Access Control | CWE-285 | PHP-relevant (BFLA) |
| **2010** | A1 Injection | A03 Injection | CWE-89, CWE-78 | PHP-relevant |
| **2010** | A2 Cross-Site Scripting | A03 Injection | CWE-79 | PHP-relevant |
| **2010** | A3 Broken Auth & Session Mgmt | A07 Auth Failures | CWE-287, CWE-384 | PHP-relevant |
| **2010** | A4 Insecure Direct Object References | A01 Broken Access Control | CWE-639 | PHP-relevant |
| **2010** | A5 Cross-Site Request Forgery | A01 Broken Access Control | CWE-352 | PHP-relevant |
| **2010** | A6 Security Misconfiguration | A05 Misconfiguration | CWE-16 | PHP-relevant |
| **2010** | A7 Insecure Cryptographic Storage | A02 Cryptographic Failures | CWE-311 | PHP-relevant |
| **2010** | A8 Failure to Restrict URL Access | A01 Broken Access Control | CWE-285 | PHP-relevant |
| **2010** | A9 Insufficient Transport Layer Protection | A02 Cryptographic Failures | CWE-319 | PHP-relevant |
| **2010** | A10 Unvalidated Redirects & Forwards | A01 Broken Access Control | CWE-601 | PHP-relevant |
| **2013** | A1 Injection | A03 Injection | CWE-89, CWE-78 | PHP-relevant |
| **2013** | A2 Broken Authentication & Session Mgmt | A07 Auth Failures | CWE-287 | PHP-relevant |
| **2013** | A3 Cross-Site Scripting | A03 Injection | CWE-79 | PHP-relevant |
| **2013** | A4 Insecure Direct Object References | A01 Broken Access Control | CWE-639 | PHP-relevant |
| **2013** | A5 Security Misconfiguration | A05 Misconfiguration | CWE-16 | PHP-relevant |
| **2013** | A6 Sensitive Data Exposure | A02 Cryptographic Failures | CWE-311, CWE-319 | PHP-relevant |
| **2013** | A7 Missing Function Level Access Control | A01 Broken Access Control | CWE-285 | PHP-relevant (BFLA) |
| **2013** | A8 Cross-Site Request Forgery | A01 Broken Access Control | CWE-352 | PHP-relevant |
| **2013** | A9 Using Components with Known Vulnerabilities | A06 Vulnerable Components | CWE-1104, CWE-937 | PHP-relevant (`composer audit`) |
| **2013** | A10 Unvalidated Redirects & Forwards | A01 Broken Access Control | CWE-601 | PHP-relevant |
| **2017** | A1 Injection | A03 Injection | CWE-89, CWE-78 | PHP-relevant |
| **2017** | A2 Broken Authentication | A07 Auth Failures | CWE-287 | PHP-relevant |
| **2017** | A3 Sensitive Data Exposure | A02 Cryptographic Failures | CWE-311, CWE-319 | PHP-relevant |
| **2017** | A4 XML External Entities (XXE) | A05 Misconfiguration | CWE-611 | PHP-relevant (XML parsers) |
| **2017** | A5 Broken Access Control | A01 Broken Access Control | CWE-284, CWE-639 | PHP-relevant |
| **2017** | A6 Security Misconfiguration | A05 Misconfiguration | CWE-16 | PHP-relevant |
| **2017** | A7 Cross-Site Scripting | A03 Injection | CWE-79 | PHP-relevant |
| **2017** | A8 Insecure Deserialization | A08 Software & Data Integrity | CWE-502 | PHP-relevant (`unserialize`) |
| **2017** | A9 Using Components with Known Vulnerabilities | A06 Vulnerable Components | CWE-1104 | PHP-relevant |
| **2017** | A10 Insufficient Logging & Monitoring | A09 Logging & Monitoring Failures | CWE-778 | PHP-relevant |

### OWASP Top 10 — 2021 (active triage baseline)

| Id | Category | Mapped CWE(s) | PHP relevance | Dispatch family (see §5.1) |
| --- | --- | --- | --- | --- |
| **A01:2021** | Broken Access Control | CWE-284, CWE-639, CWE-285, CWE-352, CWE-601 | PHP-relevant | BOLA/IDOR, BFLA |
| **A02:2021** | Cryptographic Failures | CWE-327, CWE-326, CWE-311, CWE-319, CWE-798 | PHP-relevant | Cryptographic failures / secrets |
| **A03:2021** | Injection | CWE-89, CWE-78, CWE-79, CWE-77, CWE-1336, CWE-20 | PHP-relevant | SQLi/DQL, SSTI |
| **A04:2021** | Insecure Design | CWE-657, CWE-501 | PHP-relevant | spans families (design review) |
| **A05:2021** | Security Misconfiguration | CWE-16, CWE-611, CWE-209 | PHP-relevant | Security misconfiguration |
| **A06:2021** | Vulnerable & Outdated Components | CWE-1104, CWE-937 | PHP-relevant | Vulnerable / outdated deps |
| **A07:2021** | Identification & Authentication Failures | CWE-287, CWE-384, CWE-307, CWE-620 | PHP-relevant | Auth / session |
| **A08:2021** | Software & Data Integrity Failures | CWE-502, CWE-829, CWE-345 | PHP-relevant | Insecure deserialization |
| **A09:2021** | Security Logging & Monitoring Failures | CWE-778, CWE-117 | PHP-relevant | folds into misconfiguration |
| **A10:2021** | Server-Side Request Forgery (SSRF) | CWE-918 | PHP-relevant | SSRF |

## OWASP API Security Top 10

### API Security Top 10 — 2019

| Id | Category | Mapped CWE(s) | PHP relevance | 2023 home |
| --- | --- | --- | --- | --- |
| **API1:2019** | Broken Object Level Authorization | CWE-639, CWE-284 | PHP-relevant | API1:2023 |
| **API2:2019** | Broken User Authentication | CWE-287 | PHP-relevant | API2:2023 |
| **API3:2019** | Excessive Data Exposure | CWE-213 | PHP-relevant | merged into API3:2023 |
| **API4:2019** | Lack of Resources & Rate Limiting | CWE-770, CWE-400 | PHP-relevant | API4:2023 |
| **API5:2019** | Broken Function Level Authorization | CWE-285 | PHP-relevant | API5:2023 |
| **API6:2019** | Mass Assignment | CWE-915 | PHP-relevant | merged into API3:2023 |
| **API7:2019** | Security Misconfiguration | CWE-16 | PHP-relevant | API8:2023 |
| **API8:2019** | Injection | CWE-89, CWE-78 | PHP-relevant | folds to A03:2021 |
| **API9:2019** | Improper Assets Management | CWE-1059 | PHP-relevant | API9:2023 |
| **API10:2019** | Insufficient Logging & Monitoring | CWE-778 | PHP-relevant | folds to A09:2021 |

### API Security Top 10 — 2023 (active API baseline)

| Id | Category | Mapped CWE(s) | PHP relevance | Dispatch family (see §5.1) |
| --- | --- | --- | --- | --- |
| **API1:2023** | Broken Object Level Authorization | CWE-639, CWE-284 | PHP-relevant | BOLA/IDOR |
| **API2:2023** | Broken Authentication | CWE-287, CWE-307 | PHP-relevant | Auth / session |
| **API3:2023** | Broken Object Property Level Authorization | CWE-915, CWE-213 | PHP-relevant | BOPLA / mass-assignment |
| **API4:2023** | Unrestricted Resource Consumption | CWE-770, CWE-400 | PHP-relevant | Rate / resource exhaustion |
| **API5:2023** | Broken Function Level Authorization | CWE-285 | PHP-relevant | BFLA |
| **API6:2023** | Unrestricted Access to Sensitive Business Flows | CWE-840 | PHP-relevant | folds into BFLA / rate |
| **API7:2023** | Server-Side Request Forgery | CWE-918 | PHP-relevant | SSRF |
| **API8:2023** | Security Misconfiguration | CWE-16 | PHP-relevant | Security misconfiguration |
| **API9:2023** | Improper Inventory Management | CWE-1059 | PHP-relevant | folds into misconfiguration |
| **API10:2023** | Unsafe Consumption of APIs | CWE-1104 | PHP-relevant | folds into SSRF / deps |

## OWASP LLM Top 10 — 2025 v2.0

**Gate:** PROBE **only when target LLM usage is detected** (composer LLM SDK
deps, `clean-architecture-llm` artifacts in the source tree, or an explicit
profile signal — SA-7). When no LLM usage is detected, the whole family is
recorded **N/A-with-reason** up front and never dispatched (NFR-8 cost gate).

| Id | Category | Mapped CWE(s) | PHP relevance |
| --- | --- | --- | --- |
| **LLM01:2025** | Prompt Injection | CWE-1427 | PHP-relevant when LLM detected |
| **LLM02:2025** | Sensitive Information Disclosure | CWE-200 | PHP-relevant when LLM detected |
| **LLM03:2025** | Supply Chain | CWE-1104 | PHP-relevant when LLM detected |
| **LLM04:2025** | Data & Model Poisoning | CWE-349 | PHP-relevant when LLM detected |
| **LLM05:2025** | Improper Output Handling | CWE-79, CWE-89 | PHP-relevant when LLM detected |
| **LLM06:2025** | Excessive Agency | CWE-250 | PHP-relevant when LLM detected |
| **LLM07:2025** | System Prompt Leakage | CWE-200 | PHP-relevant when LLM detected |
| **LLM08:2025** | Vector & Embedding Weaknesses | CWE-200 | PHP-relevant when LLM detected |
| **LLM09:2025** | Misinformation | CWE-1426 | PHP-relevant when LLM detected |
| **LLM10:2025** | Unbounded Consumption | CWE-770, CWE-400 | PHP-relevant when LLM detected |

## OWASP Mobile Top 10 — N/A-for-backend

**N/A-with-reason (all editions):** this plugin audits a server-side PHP backend,
not a mobile client. The Mobile corpus is retained only so a mobile reference
resolves; **every row is recorded N/A-with-reason and never dispatched** (NFR-6).
Where a backend-side concern overlaps (e.g. insecure auth, weak crypto), it is
already covered by the web/API rows above and probed there, not here.

| Edition | Representative categories | Backend disposition |
| --- | --- | --- |
| **2014** | M1 Weak Server-Side Controls … M10 Lack of Binary Protections | **N/A-with-reason**: mobile-client scope; server overlaps covered by A01/A02/A07 |
| **2016** | M1 Improper Platform Usage … M10 Extraneous Functionality | **N/A-with-reason**: mobile-client scope |
| **2024** | M1 Improper Credential Usage … M10 Insufficient Cryptography | **N/A-with-reason**: mobile-client scope; crypto/credential overlaps covered by A02/A07 |

## OWASP ASVS 5.0 — coverage checklist

ASVS 5.0 is the **coverage checklist** the triage maps each family against. The
**default verification bar is L2** (standard apps handling sensitive data); raise
to L3 only when the profile/owner declares a high-assurance target. L1 is the
floor for opportunistic checks.

| Level | Bar | When applied |
| --- | --- | --- |
| **L1** | Opportunistic / fully black-box-checkable | minimum floor |
| **L2** | Standard — sensitive data, most backends | **default bar** |
| **L3** | High-assurance / critical | only when declared |

Relevant ASVS 5.0 chapters mapped to the dispatch families: V1 Encoding &
Sanitization (Injection), V2 Validation & Business Logic (BOPLA, rate), V3 Web
Frontend Security (XSS/headers), V6 Authentication, V7 Session Management, V8
Authorization (BOLA/BFLA), V9 Self-contained Tokens (JWT), V11 Cryptography, V12
Secure Communication (TLS), V13 Configuration, V14 Data Protection.

## OWASP WSTG 4.2 — test-methodology index

WSTG 4.2 is the **methodology index**: each dispatch family's probe in
[`attack-playbooks.md`](attack-playbooks.md) cites the WSTG 4.2 test id(s) below
so the probe traces to a published method.

| WSTG 4.2 area | Test-id prefix | Dispatch family |
| --- | --- | --- |
| Configuration & Deployment Mgmt | WSTG-CONF | Security misconfiguration |
| Identity Management | WSTG-IDNT | Auth / session |
| Authentication | WSTG-ATHN | Auth / session |
| Authorization | WSTG-ATHZ | BOLA/IDOR, BFLA |
| Session Management | WSTG-SESS | Auth / session |
| Input Validation | WSTG-INPV | SQLi/DQL, SSTI, SSRF |
| Error Handling | WSTG-ERRH | Security misconfiguration |
| Cryptography | WSTG-CRYP | Cryptographic failures / secrets |
| Business Logic | WSTG-BUSL | BOPLA / mass-assignment, rate |
| Client-side | WSTG-CLNT | folds into misconfiguration (headers/CORS) |
| API Testing | WSTG-APIT | GraphQL, BOLA, rate |

## OWASP Proactive Controls / Cheat Sheet Series — remediation source-of-truth

The **remediation source-of-truth pointer**: every fix in
[`remediation-patterns.md`](remediation-patterns.md) cites a specific **OWASP
Cheat Sheet** and (where relevant) the matching **Proactive Control (2018 C1–C10)**.
This file does not duplicate fix content — it only points the triage at the
authoritative remediation reference.

| Proactive Control (2018) | Cheat Sheet anchor | Dispatch family |
| --- | --- | --- |
| C1 Define Security Requirements | — | spans all |
| C2 Leverage Security Frameworks | Symfony / framework security | all |
| C3 Secure Database Access | SQL Injection Prevention | SQLi/DQL |
| C4 Encode & Escape Data | XSS Prevention, Injection Prevention | SSTI, output |
| C5 Validate All Inputs | Input Validation, Mass Assignment | BOPLA |
| C6 Digital Identity | Authentication, Session Management | Auth / session |
| C7 Enforce Access Controls | Authorization, IDOR Prevention | BOLA/IDOR, BFLA |
| C8 Protect Data Everywhere | Cryptographic Storage, TLS, Secrets Mgmt | Cryptographic failures / secrets |
| C9 Implement Security Logging | Logging | Security misconfiguration |
| C10 Handle Errors & Exceptions | Error Handling | Security misconfiguration |

## CWE / SANS Top 25 — 2024 (ordered)

The **CWE Top 25 Most Dangerous Software Weaknesses (2024)**, in rank order.
SANS is treated as the **same Top 25 taxonomy** (the list is jointly stewarded —
no separate SANS enumeration). Memory-safety CWEs are marked **N/A-with-reason**
for managed PHP (no manual memory management); they remain listed so a CWE
reference resolves.

| Rank | CWE | Name | PHP relevance | Dispatch family |
| --- | --- | --- | --- | --- |
| 1 | CWE-79 | Cross-site Scripting | PHP-relevant | SSTI / output (Twig) |
| 2 | CWE-787 | Out-of-bounds Write | **N/A-with-reason**: memory-safety, managed runtime | — |
| 3 | CWE-89 | SQL Injection | PHP-relevant | SQLi/DQL |
| 4 | CWE-352 | Cross-Site Request Forgery | PHP-relevant | BFLA / access control |
| 5 | CWE-22 | Path Traversal | PHP-relevant | file upload / misconfiguration |
| 6 | CWE-125 | Out-of-bounds Read | **N/A-with-reason**: memory-safety | — |
| 7 | CWE-78 | OS Command Injection | PHP-relevant | SQLi/DQL (command-sink lens) |
| 8 | CWE-416 | Use After Free | **N/A-with-reason**: memory-safety | — |
| 9 | CWE-862 | Missing Authorization | PHP-relevant | BFLA |
| 10 | CWE-434 | Unrestricted Upload of Dangerous File | PHP-relevant | File upload |
| 11 | CWE-94 | Code Injection | PHP-relevant | SSTI / deserialization |
| 12 | CWE-20 | Improper Input Validation | PHP-relevant | spans injection families |
| 13 | CWE-77 | Command Injection | PHP-relevant | SQLi/DQL (command-sink lens) |
| 14 | CWE-287 | Improper Authentication | PHP-relevant | Auth / session |
| 15 | CWE-269 | Improper Privilege Management | PHP-relevant | BFLA |
| 16 | CWE-502 | Deserialization of Untrusted Data | PHP-relevant | Insecure deserialization |
| 17 | CWE-200 | Exposure of Sensitive Information | PHP-relevant | Cryptographic failures / secrets |
| 18 | CWE-863 | Incorrect Authorization | PHP-relevant | BOLA/IDOR, BFLA |
| 19 | CWE-918 | Server-Side Request Forgery | PHP-relevant | SSRF |
| 20 | CWE-119 | Improper Restriction of Memory Buffer Operations | **N/A-with-reason**: memory-safety | — |
| 21 | CWE-476 | NULL Pointer Dereference | **N/A-with-reason**: memory-safety, managed runtime | — |
| 22 | CWE-798 | Use of Hard-coded Credentials | PHP-relevant | Cryptographic failures / secrets |
| 23 | CWE-190 | Integer Overflow or Wraparound | **N/A-with-reason**: memory-safety, managed runtime | — |
| 24 | CWE-400 | Uncontrolled Resource Consumption | PHP-relevant | Rate / resource exhaustion |
| 25 | CWE-306 | Missing Authentication for Critical Function | PHP-relevant | Auth / session, BFLA |

Additional PHP-pertinent CWEs cited by the families above but outside the 2024
Top 25: **CWE-639** (IDOR — BOLA/IDOR), **CWE-915** (mass assignment — BOPLA),
**CWE-1336** (template injection — SSTI), **CWE-611** (XXE — misconfiguration),
**CWE-601** (open redirect — access control), **CWE-307** (no rate limit on auth
— auth/session), **CWE-1104** (unmaintained components — vulnerable deps),
**CWE-327**/**CWE-326** (weak crypto — cryptographic failures), **CWE-770**
(allocation without limits — rate/resource).

## Dispatchable family set (derived rows → §5.1)

The skill's §5.1 fan-out table is **derivable from the rows above**. Each family
below is dispatched as one `security-auditor` instance when its profile gate
holds; the OWASP id and CWE(s) come straight from the tables above.

| Dispatch family | Primary OWASP id | Key CWE(s) | Profile gate |
| --- | --- | --- | --- |
| BOLA / IDOR | API1:2023 / A01:2021 | CWE-639, CWE-284 | always |
| BOPLA / mass-assignment | API3:2023 | CWE-915, CWE-213 | always |
| BFLA | API5:2023 / A01:2021 | CWE-285, CWE-862 | always |
| Injection — SQLi/DQL/NoSQL | A03:2021 | CWE-89, CWE-943, CWE-78, CWE-77 | always (CWE-943 NoSQL operator injection when `persistence.mapper` is doctrine-odm) |
| SSTI | A03:2021 | CWE-1336, CWE-94 | always |
| Insecure deserialization | A08:2021 | CWE-502 | always |
| SSRF | A10:2021 / API7:2023 | CWE-918 | always |
| Auth / session | A07:2021 / API2:2023 | CWE-287, CWE-384, CWE-307 | always |
| Security misconfiguration | A05:2021 / API8:2023 | CWE-16, CWE-611, CWE-209 | always |
| Vulnerable / outdated deps | A06:2021 | CWE-1104, CWE-937 | always |
| Cryptographic failures / secrets | A02:2021 | CWE-327, CWE-311, CWE-319, CWE-798 | always |
| File upload | A08:2021 (integrity) | CWE-434, CWE-22 | upload surface exists |
| Rate / resource exhaustion | API4:2023 | CWE-770, CWE-400 | always |
| GraphQL (introspection / deep-query / batching) | API4:2023 / API1:2023 | CWE-770, CWE-639 | `framework.graphql: true` only |
| LLM Top 10 | LLM01:2025 … LLM10:2025 | CWE-1427, CWE-77 | LLM usage detected (SA-7) only |

**Excluded before fan-out (NFR-8 cost gate), recorded N/A-with-reason:** OWASP
Mobile (all editions), the memory-safety CWEs (CWE-787, CWE-125, CWE-416,
CWE-119, CWE-476, CWE-190), and the LLM family when no LLM usage is detected.
