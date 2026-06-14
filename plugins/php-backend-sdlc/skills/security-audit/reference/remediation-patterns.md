# Remediation Patterns — Secure-by-Default, Root-Cause Fixes

The fix catalog the `security-audit` loop cites when it routes a verified
finding to `php-implementer`. One entry per PHP-relevant OWASP/CWE family
from [`owasp-catalog.md`](owasp-catalog.md), each pairing a **vetted
library / framework primitive** with the **OWASP cheat sheet** it derives
from. Every pattern is generic: substitute your own profile values
(`architecture.source_root`, `architecture.bounded_contexts`,
`persistence.mapper`, `framework.api_platform`, `framework.graphql`) — no
source-project literals appear outside a `# profile-example` fence.

**Edition pointer (NFR-9):** all citations track the OWASP Cheat Sheet
Series **2024 index** and OWASP Proactive Controls **v3.0 (2018)**. When a
cheat sheet is revised, update the dated pointer here and re-confirm the
named primitive is still the project's first-class control — do not pin a
fix to a deprecated API.

## Policy (verbatim, non-negotiable)

> root-cause only, zero suppression

And:

> every fix gets a failing-then-passing regression test

A remediation closes the **sink**, not the alert. The failing-then-passing
regression test lives under the project's test root (the
[`testing-workflow`](../../testing-workflow/SKILL.md) home): it reproduces
the exploit from [`attack-playbooks.md`](attack-playbooks.md) and **fails**
on the unfixed code, then **passes** once the root-cause fix lands. A fix
without that test is not a fix.

### Forbidden remediations (none of the patterns below use them)

A finding is **never** "remediated" by making the detector quiet. The
following are prohibited everywhere in this catalog and in any fix it
drives — they lower the bar instead of closing the vulnerability:

- A suppression annotation (`@psalm-suppress`, `@SuppressWarnings`,
  `phpcs:ignore`, inline `// nosemgrep`, or any equivalent).
- A baseline / ignore file entry, or extending an existing one, to absorb
  the finding.
- Relaxing a tool's configuration (loosening a Psalm/Semgrep rule, removing
  a taint sink, widening an allowlist) so the candidate stops firing.
- Lowering a `quality.*` threshold or any score floor — thresholds are
  **raise-only** (ADR-7); fix the code instead.
- Editing `deptrac.yaml` (or any layer-boundary config) to make a
  dependency violation disappear rather than refactoring the dependency.
- Reducing test coverage, mutation-score, or assertion strength to dodge
  the regression test.

If a fix appears to require any of the above, it is the wrong fix: trace
back to the sink and remediate there.

## Pattern catalog

### Injection — SQLi / DQL (A03:2021, CWE-89)

- **Primitive:** Doctrine **parameterized queries** —
  `QueryBuilder::setParameter()` / DQL named or positional parameters, or
  prepared statements via the DBAL `Connection`. **Never** concatenate or
  interpolate request data into a DQL/SQL string. For `doctrine-odm`, build
  filters as PHP arrays through the document-manager API, never as
  string-spliced query fragments.
- **Cheat sheet:** *SQL Injection Prevention* + *Query Parameterization*.
- **Root cause:** untrusted input reaches a query sink unparameterized.
  Replace the concatenation with a bound parameter at the sink; keep the
  value typed.
- **Regression test:** an integration test that sends the injection payload
  (e.g. `' OR '1'='1`) to the affected endpoint and asserts the parameter
  is treated as a literal — failing before, passing after.

### Broken access control — BOLA / IDOR (API1:2023, CWE-639)

- **Primitive:** API Platform **`security` expressions** + Symfony
  **voters** (`#[IsGranted]` / `Voter` subclass) enforcing
  resource-ownership on every item operation. The object's owner is checked
  server-side; the IRI/object id is never trusted as authorization.
- **Cheat sheet:** *Authorization* + *Access Control* (and *Insecure Direct
  Object Reference Prevention*).
- **Root cause:** an item operation returns/mutates a resource without an
  ownership check. Add the voter / `security` expression at the operation,
  scoped to the authenticated principal — not a client-supplied id.
- **Regression test:** a functional test where principal A requests
  principal B's IRI and asserts `403`/`404`, not `200` — failing before,
  passing after.

### Broken function-level authorization — BFLA (API5:2023, CWE-285)

- **Primitive:** Symfony **`#[IsGranted]`** / access-control rules and API
  Platform operation-level `security` expressions on **every** privileged
  operation; deny-by-default `access_control` in the firewall.
- **Cheat sheet:** *Authorization* + *REST Security*.
- **Root cause:** an admin/privileged operation lacks a role check, or a
  role expression is bypassable. Attach the explicit role requirement at the
  operation and default the firewall to deny.
- **Regression test:** a low-privilege principal calls the privileged
  operation and is denied — failing before, passing after.

### Mass assignment — BOPLA (API3:2023, CWE-915)

- **Primitive:** Symfony **Serializer write groups**
  (`#[Groups]` + `denormalization_context`) so only explicitly allowlisted
  properties are writable; sensitive fields (roles, ids, balances) are
  excluded from every write group.
- **Cheat sheet:** *Mass Assignment Prevention*.
- **Root cause:** denormalization accepts unlisted properties. Define a
  narrow write group and bind operations to it; remove blanket
  `denormalizationContext` exposure.
- **Regression test:** a write request carrying an unlisted privileged field
  (e.g. `roles`) asserts the field is ignored/rejected — failing before,
  passing after.

### Cross-site scripting / template injection — SSTI (CWE-79, CWE-1336)

- **Primitive:** **Twig auto-escaping** (on by default). Never apply `|raw`
  to user input and never build a template name or template source from
  request data; render data through variables, not concatenated markup.
- **Cheat sheet:** *Cross Site Scripting Prevention* + *Server Side Template
  Injection Prevention*.
- **Root cause:** user input flows to `|raw` or to a dynamic template
  name/source. Remove `|raw`, render via an escaped variable, and select
  templates from a fixed server-side allowlist.
- **Regression test:** a response-rendering test feeds a markup/`{{7*7}}`
  payload and asserts it is escaped, not executed/evaluated — failing
  before, passing after.

### Insecure deserialization (A08:2021, CWE-502)

- **Primitive:** use the Symfony **Serializer** (JSON) for untrusted data;
  **never** call `unserialize()` on request-derived bytes. If PHP
  serialization is unavoidable, pass `['allowed_classes' => false]` and
  validate against a strict allowlist.
- **Cheat sheet:** *Deserialization* (Insecure Deserialization).
- **Root cause:** untrusted bytes reach a deserialization sink that can
  instantiate arbitrary classes. Replace the sink with safe structured
  decoding; constrain allowed classes at the boundary.
- **Regression test:** a crafted object-injection payload to the sink
  asserts no unexpected class is instantiated / the request is rejected —
  failing before, passing after.

### Server-side request forgery — SSRF (A10:2021, CWE-918)

- **Primitive:** an **allowlist of destination hosts/schemes** enforced
  before any outbound `HttpClientInterface` (Symfony HTTP Client) call;
  block private/link-local/metadata ranges; disable transparent redirects to
  unvetted hosts. Resolve and re-check the host after DNS, not just the raw
  URL.
- **Cheat sheet:** *Server Side Request Forgery Prevention*.
- **Root cause:** a user-controlled URL reaches a fetch sink unfiltered.
  Insert the allowlist/validation immediately before the outbound call.
- **Regression test:** a request supplying an internal/metadata URL
  (`http://169.254.169.254/...`) asserts the fetch is refused — failing
  before, passing after.

### Identification & authentication / session (A07:2021, CWE-287, CWE-384)

- **Primitive:** Symfony **SecurityBundle** with the **`auto`** password
  hasher (bcrypt/argon2id, never plain/MD5/SHA1); for JWT use a library that
  pins the signing algorithm and **rejects `alg: none`** and
  algorithm-confusion; enforce token expiry and rotate the session id on
  authentication (fixation defense).
- **Cheat sheet:** *Authentication* + *Password Storage* + *Session
  Management* + *JSON Web Token for Java* (alg-pinning guidance applies
  cross-language).
- **Root cause:** weak hashing, unpinned JWT algorithm, missing expiry, or
  un-rotated session id. Switch the hasher to `auto`, pin the algorithm,
  set/validate `exp`, and migrate the session on login.
- **Regression test:** an auth test asserting an `alg: none` / wrong-alg
  token is rejected and the session id changes on login — failing before,
  passing after.

### Cryptographic failures / secrets (A02:2021, CWE-327, CWE-798)

- **Primitive:** **Paragon Initiative** crypto guidance — use `libsodium`
  (sodium\_\*) or a vetted high-level library for encryption/signing; never
  hand-roll ECB/static-IV constructions. Keep secrets in environment / a
  secrets manager (Symfony **Secrets** vault), never committed; rotate any
  leaked credential at the source.
- **Cheat sheet:** *Cryptographic Storage* + *Secrets Management* (with
  Paragon's *Choosing the Right Cryptographic Primitive*).
- **Root cause:** a weak/broken primitive or a committed secret. Replace the
  primitive with the vetted authenticated-encryption API; move the secret to
  config and rotate it (a leaked secret is compromised even after removal).
- **Regression test:** a unit test asserting authenticated encryption /
  rejecting a tampered ciphertext, plus a secret-scan assertion that the
  tree is clean — failing before, passing after.

### Security misconfiguration (A05:2021, CWE-16)

- **Primitive:** production hardening via **framework config** — `APP_ENV`
  set to a non-debug value, the Symfony **profiler/web debug toolbar
  disabled** in production, an explicit **CORS allowlist** (nelmio/cors or
  equivalent, no `*` with credentials), security headers
  (`Content-Security-Policy`, `X-Content-Type-Options`,
  `Strict-Transport-Security`), and enforced TLS.
- **Cheat sheet:** *Security Headers* + *HTTP Strict Transport Security* +
  *Content Security Policy* + *Cross-Origin Resource Sharing*.
- **Root cause:** a permissive/debug default ships to production. Set the
  hardened value in config; do not paper over it with a WAF rule.
- **Regression test:** a config/response test asserting debug is off, CORS
  is scoped, and the headers are present — failing before, passing after.

### Vulnerable & outdated components (A06:2021, CWE-1104)

- **Primitive:** **`composer audit`** against the advisory database in CI;
  **upgrade** the affected package to a patched version (or apply the
  upstream patch). Pin via `composer.lock`; track transitive advisories.
- **Cheat sheet:** *Vulnerable Dependency Management* + *Third Party
  Javascript Management* (dependency hygiene).
- **Root cause:** a dependency with a known CVE is in the lockfile. Bump to
  the fixed release and re-run the audit; **never** add an audit ignore to
  silence it.
- **Regression test:** a CI assertion that `composer audit` reports no
  advisory for the affected package after the bump — failing before, passing
  after.

### Unrestricted file upload (CWE-434)

- **Primitive:** validate uploads with Symfony **`File`/`Image`
  constraints** — allowlist MIME type and extension (verify content, not
  just the declared type), cap size, store outside the web root with a
  generated non-executable name, and never serve uploads from a
  PHP-executable path.
- **Cheat sheet:** *File Upload*.
- **Root cause:** an upload handler trusts the client-declared type/name or
  stores into an executable path. Add content-based validation and relocate
  storage.
- **Regression test:** an upload of a disguised executable (e.g. a `.php`
  renamed `.jpg`) asserts rejection / non-executable storage — failing
  before, passing after.

### Rate & resource exhaustion (API4:2023, CWE-770)

- **Primitive:** Symfony **RateLimiter** on sensitive/expensive operations,
  **pagination caps** on collection endpoints, and query/depth limits so a
  single request cannot exhaust the backend.
- **Cheat sheet:** *Denial of Service* + *REST Security* (rate limiting).
- **Root cause:** an unbounded or unthrottled operation. Add the limiter /
  pagination ceiling at the operation; bound the worst-case work per
  request.
- **Regression test:** a burst/oversized-page request asserts throttling /
  the enforced ceiling — failing before, passing after.

### GraphQL — introspection / depth / batching (CWE-770)

- **Primitive:** disable **introspection in production**, enforce
  **query-depth and complexity limits** and a **batch cap** via the GraphQL
  layer's config (e.g. webonyx limits through the framework integration).
  Apply only when `framework.graphql` is `true`; otherwise the family is
  N/A.
- **Cheat sheet:** *GraphQL*.
- **Root cause:** unbounded introspection/depth/batching lets a client map
  or overload the schema. Set the limits in config at the GraphQL endpoint.
- **Regression test:** a deeply nested / oversized-batch / production
  introspection query asserts rejection — failing before, passing after.

### LLM-backed surfaces (LLM Top 10 2025 v2.0, gated)

- **Primitive:** treat model output as untrusted — **validate and escape**
  it at every sink, isolate tool/function calls behind allowlists, and keep
  the trust boundary explicit (the
  [`clean-architecture-llm`](../../clean-architecture-llm/SKILL.md) ports).
  Probe only when LLM usage is detected (SA-7); otherwise N/A-with-reason.
- **Cheat sheet:** *LLM Prompt Injection Prevention* (Cheat Sheet Series
  2024) + OWASP LLM Top 10 (LLM01 prompt injection, LLM02 insecure output
  handling).
- **Root cause:** model output reaches a sink without validation, or a
  prompt mixes trusted instructions with untrusted data. Constrain the
  output at the sink and separate instruction from data.
- **Regression test:** a prompt-injection / malicious-output payload asserts
  the downstream sink is not driven by attacker text — failing before,
  passing after.

## How a fix lands (loop contract)

1. The orchestrator hands `php-implementer` the verified finding's
   `{location, remediation, regression_test}` (the
   [SKILL.md](../SKILL.md) finding-record contract).
2. `php-implementer` writes the **failing** regression test first, then the
   **root-cause** fix from the pattern above — no suppression, no baseline,
   no threshold or `deptrac.yaml` edit.
3. The affected-family `security-auditor` **re-verifies**: the
   [`attack-playbooks.md`](attack-playbooks.md) reproduction must now fail
   to exploit.
4. The loop closes only when `make.ci` is green
   ([`ci-workflow`](../../ci-workflow/SKILL.md)) and the
   forbidden-suppression scan (inherited from
   [`code-review`](../../code-review/SKILL.md) Step 6) reports zero
   suppressions introduced.

## Related references

- [`owasp-catalog.md`](owasp-catalog.md) — the family/CWE/edition corpus
  these patterns remediate.
- [`attack-playbooks.md`](attack-playbooks.md) — the probe + reproduce step
  each regression test is built from.
