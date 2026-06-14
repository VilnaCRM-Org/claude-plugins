# Test Cases — `security-audit` skill validation campaign

Concrete positive / negative / edge cases per dispatch family. Each row maps to
a fixture under `tools/security-audit-validation/corpus/<family>/` and an entry
in `corpus.py`. `expect` is the **static-lane** expectation; `judge` is the
**judge-lane** expected verdict. IDs are stable across rounds.

Legend — `expect`: `finding` (rule must fire) · `clean` (rule must stay silent).
`judge`: `FINDING` · `CLEAN` · `NA`.

## Static-detectable families

### SC-SQLI — SQL injection (CWE-89, A03:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-SQLI-P | `sqli/vulnerable.php` | `$_GET['id']` concatenated into a `PDO::query` string | finding | FINDING |
| SC-SQLI-N | `sqli/clean.php` | prepared statement with a bound parameter | clean | CLEAN |
| SC-SQLI-E1 | `sqli/edge_commented.php` | the vulnerable `query()` line is **commented out** — must NOT flag | clean | CLEAN |
| SC-SQLI-E2 | `sqli/edge_laundered.php` | taint flows through an intermediate `$q` variable before the sink | finding | FINDING |
| SC-SQLI-E3 | `sqli/edge_intcast.php` | `(int)$_GET['id']` cast before concatenation — safe by coercion | clean | CLEAN |

### SC-CMD — OS command injection (CWE-78/77, A03:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-CMD-P | `command/vulnerable.php` | `shell_exec("ping " . $_GET['host'])` | finding | FINDING |
| SC-CMD-N | `command/clean.php` | `escapeshellarg` around the user value | clean | CLEAN |
| SC-CMD-E1 | `command/edge_escapeshellcmd.php` | `escapeshellcmd` used where `escapeshellarg` is required (still injectable via args) | finding | FINDING |
| SC-CMD-E2 | `command/edge_static.php` | `exec` with a fully static command, no user input | clean | CLEAN |

### SC-CODE — code injection / SSTI (CWE-94/1336, A03:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-CODE-P | `code/vulnerable.php` | `eval($_POST['expr'])` | finding | FINDING |
| SC-CODE-N | `code/clean.php` | a whitelisted-operation `match` expression, no `eval` | clean | CLEAN |
| SC-CODE-E1 | `code/edge_ssti.php` | Twig `createTemplate($_GET['tpl'])->render()` (SSTI sink) | finding | FINDING |
| SC-CODE-E2 | `code/edge_static_eval.php` | `eval` of a constant string literal (no taint) | clean | CLEAN |

### SC-DESER — insecure deserialization (CWE-502, A08:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-DESER-P | `deserialization/vulnerable.php` | `unserialize($_COOKIE['data'])` | finding | FINDING |
| SC-DESER-N | `deserialization/clean.php` | `json_decode($_COOKIE['data'], true)` | clean | CLEAN |
| SC-DESER-E1 | `deserialization/edge_allowed_classes.php` | `unserialize($x, ['allowed_classes' => false])` — hardened, still tainted input | finding | FINDING |
| SC-DESER-E2 | `deserialization/edge_static.php` | `unserialize` of a constant string | clean | CLEAN |

### SC-SSRF — server-side request forgery (CWE-918, A10:2021/API7:2023)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-SSRF-P | `ssrf/vulnerable.php` | `file_get_contents($_GET['url'])` | finding | FINDING |
| SC-SSRF-N | `ssrf/clean.php` | host allowlist check before the fetch | clean | CLEAN |
| SC-SSRF-E1 | `ssrf/edge_scheme_only.php` | only `https://` prefix checked — bypassable (`https://169.254.169.254`) | finding | FINDING |
| SC-SSRF-E2 | `ssrf/edge_constant_url.php` | fetch of a hardcoded internal URL, no user input | clean | CLEAN |

### SC-CRYPTO — weak cryptography (CWE-327/326, A02:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-CRYPTO-P | `crypto/vulnerable.php` | `md5($password)` for password storage | finding | FINDING |
| SC-CRYPTO-N | `crypto/clean.php` | `password_hash($password, PASSWORD_DEFAULT)` | clean | CLEAN |
| SC-CRYPTO-E1 | `crypto/edge_sha1.php` | `sha1` used for a password (still weak) | finding | FINDING |
| SC-CRYPTO-E2 | `crypto/edge_md5_checksum.php` | `md5` of a file for a **non-security** cache key (acceptable) | clean | CLEAN |

### SC-SECRET — hardcoded credentials (CWE-798, A02:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-SECRET-P | `secret/vulnerable.php` | `$apiKey = "FAKE-...";` literal credential assignment | finding | FINDING |
| SC-SECRET-N | `secret/clean.php` | `getenv('API_KEY')` | clean | CLEAN |
| SC-SECRET-E1 | `secret/edge_empty.php` | `$apiKey = "";` empty placeholder — not a real secret | clean | CLEAN |
| SC-SECRET-E2 | `secret/edge_config_default.php` | `$dsn = "mysql:host=localhost"` — connection string, no embedded credential | clean | CLEAN |

### SC-XXE — XML external entities (CWE-611, A05:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-XXE-P | `xxe/vulnerable.php` | `DOMDocument::loadXML($x, LIBXML_NOENT)` on user XML | finding | FINDING |
| SC-XXE-N | `xxe/clean.php` | `loadXML` with `LIBXML_NONET` and no `LIBXML_NOENT` | clean | CLEAN |
| SC-XXE-E1 | `xxe/edge_simplexml_noent.php` | `simplexml_load_string($x, ..., LIBXML_NOENT)` | finding | FINDING |
| SC-XXE-E2 | `xxe/edge_default_flags.php` | `loadXML` with default flags (entities off since libxml 2.9) | clean | CLEAN |

### SC-PATH — path traversal (CWE-22, CWE-434)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-PATH-P | `path/vulnerable.php` | `file_get_contents("uploads/" . $_GET['f'])` | finding | FINDING |
| SC-PATH-N | `path/clean.php` | `basename()` + `realpath()` containment check | clean | CLEAN |
| SC-PATH-E1 | `path/edge_include.php` | `include($_GET['page'] . ".php")` (LFI) | finding | FINDING |
| SC-PATH-E2 | `path/edge_basename_only.php` | `basename` only, no containment — still traversable via symlink note | finding | FINDING |

### SC-XSS — cross-site scripting (CWE-79, A03:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-XSS-P | `xss/vulnerable.php` | `echo $_GET['name']` unescaped | finding | FINDING |
| SC-XSS-N | `xss/clean.php` | `htmlspecialchars($_GET['name'], ENT_QUOTES)` | clean | CLEAN |
| SC-XSS-E1 | `xss/edge_raw_twig.php` | Twig `{{ name\|raw }}` on user data (template, byte-equivalent sink) | finding | FINDING |
| SC-XSS-E2 | `xss/edge_intval.php` | `echo (int)$_GET['n']` — coerced, safe | clean | CLEAN |

### SC-REDIR — open redirect (CWE-601, A01:2021)

| ID | Fixture | Description | expect | judge |
| --- | --- | --- | --- | --- |
| SC-REDIR-P | `redirect/vulnerable.php` | `header("Location: " . $_GET['next'])` | finding | FINDING |
| SC-REDIR-N | `redirect/clean.php` | allowlist of internal paths before redirect | clean | CLEAN |
| SC-REDIR-E1 | `redirect/edge_relative_only.php` | only leading-`/` checked — bypassable via `//evil.com` | finding | FINDING |
| SC-REDIR-E2 | `redirect/edge_constant.php` | redirect to a constant internal path | clean | CLEAN |

## Dependency family (in-tree demonstration, FR-7)

### SC-DEP — vulnerable / outdated component (CWE-1104, A06:2021)

| ID | Fixture | Description | expect |
| --- | --- | --- | --- |
| SC-DEP-P | `deps/vulnerable.composer.json` | pins a package at a version inside a recorded known-vulnerable range | in-range (promote) |
| SC-DEP-N | `deps/clean.composer.json` | pins the same package at the patched version | out-of-range (clean) |

## Logic families (judge lane only — no sound static signature)

### JC-BOLA — broken object level authorization / IDOR (CWE-639, API1:2023)

| ID | Fixture | Description | judge |
| --- | --- | --- | --- |
| JC-BOLA-P | `bola/vulnerable.php` | controller loads `Order` by `$_GET['id']` with no owner check | FINDING |
| JC-BOLA-N | `bola/clean.php` | ownership assertion (`$order->getOwner() === $user`) before return | CLEAN |
| JC-BOLA-E1 | `bola/edge_wrong_subject.php` | checks authentication but never authorization of *this* object | FINDING |

### JC-BFLA — broken function level authorization (CWE-285/862, API5:2023)

| ID | Fixture | Description | judge |
| --- | --- | --- | --- |
| JC-BFLA-P | `bfla/vulnerable.php` | admin-only `deleteUser` action with no role guard | FINDING |
| JC-BFLA-N | `bfla/clean.php` | `#[IsGranted('ROLE_ADMIN')]` / explicit role check | CLEAN |

### JC-BOPLA — broken object property level authz / mass assignment (CWE-915, API3:2023)

| ID | Fixture | Description | judge |
| --- | --- | --- | --- |
| JC-BOPLA-P | `bopla/vulnerable.php` | hydrates an entity from the full request body incl. `isAdmin` | FINDING |
| JC-BOPLA-N | `bopla/clean.php` | DTO with an explicit allowlist of writable fields | CLEAN |

### JC-AUTH — authentication / session (CWE-287/307, A07:2021)

| ID | Fixture | Description | judge |
| --- | --- | --- | --- |
| JC-AUTH-P | `auth/vulnerable.php` | `==` token comparison + no attempt throttling | FINDING |
| JC-AUTH-N | `auth/clean.php` | `hash_equals` + a rate-limit guard | CLEAN |

### JC-RATE — rate / resource exhaustion (CWE-770/400, API4:2023)

| ID | Fixture | Description | judge |
| --- | --- | --- | --- |
| JC-RATE-P | `rate/vulnerable.php` | unbounded `$limit = $_GET['limit']` into a query | FINDING |
| JC-RATE-N | `rate/clean.php` | clamped page size with a hard maximum | CLEAN |

## N/A discipline (negative — the skill must NOT fabricate)

### NC-NA — out-of-scope families

| ID | Fixture | Description | judge |
| --- | --- | --- | --- |
| NC-NA-MOBILE | `na/mobile_note.php` | a backend file with a comment mentioning a mobile client — must record N/A, not a finding | NA |
| NC-NA-MEMSAFE | `na/memsafe_note.php` | code referencing a buffer concept in managed PHP — N/A (memory-safety) | NA |

## Degrade-soundness (TI-5)

| ID | Assertion |
| --- | --- |
| DG-1 | Every degrade path in `SKILL.md` terminates in CLEAN / FINDINGS / N/A / SKIPPED / ESCALATED |
| DG-2 | `security-auditor.md` static-only degrade path allows FR-7 promotion of committed-secret + vulnerable-dep classes |
| DG-3 | No degrade path contains an unbounded "retry until …" without a counter bound |
