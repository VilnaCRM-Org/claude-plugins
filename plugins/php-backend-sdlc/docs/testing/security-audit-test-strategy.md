# Test Strategy — `security-audit` skill validation campaign

Validates that the `security-audit` skill and its `security-auditor` subagent
**actually detect the vulnerabilities they claim to cover**, do **not** flag
secure code (no false positives), and **degrade** as their contracts promise.

Contract sources:

- `plugins/php-backend-sdlc/skills/security-audit/SKILL.md` (FR-1..FR-8, the
  triage → find → verify → fix → re-verify loop);
- `plugins/php-backend-sdlc/agents/security-auditor.md` (the per-family
  red-team contract, NFR-5/NFR-6 boundaries);
- `plugins/php-backend-sdlc/skills/security-audit/reference/{owasp-catalog,attack-playbooks,remediation-patterns}.md`
  (the dispatchable family set and per-family methodology);
- `specs/autonomous/2026-06-14-security-audit-skill/prd.md` (FR-1..FR-9,
  NFR-1..NFR-9).

A **bug** is any behavior contradicting those contracts: a seeded vulnerability
the detection lane misses (false negative), a secure construct it flags (false
positive), a family whose methodology cannot in principle reach its own CWE, a
degrade path that loops or hard-fails, or a documented capability the corpus
proves does not hold. **Not bugs:** runtime-only logic flaws unreachable by any
static signal AND not exercised by the judge lane (recorded as judge-lane-only),
cosmetic wording, model nondeterminism within the N-vote band.

## Two-lane model

The skill detects via two complementary lanes; the campaign validates both.

| Lane | What it proves | Determinism | Gates CI |
| --- | --- | --- | --- |
| **Static lane** | semgrep/SAST signatures fire on the seeded sink and stay silent on the secure counterpart — the deterministic backbone of `security-auditor`'s SAST pass | Fully deterministic (same input → same verdict) | **Yes** — TP/TN assertions hard-fail |
| **Judge lane** | an LLM acting under the `security-auditor` contract reaches the correct verdict (FINDING for vulnerable, CLEAN for secure), including for **logic** families no static rule can reach (BOLA/IDOR, BFLA, BOPLA, auth, rate) | Bounded nondeterminism (N-vote median) | **Skip-clean** when the `claude` CLI is absent (never a false green), matching the prompt-quality judge |

Neither lane alone is sufficient: the static lane cannot reach authorization
logic; the judge lane is nondeterministic. Together they cover every
dispatchable family in `owasp-catalog.md` §"Dispatchable family set".

## Scope — coverage matrix by family

Every **PHP-relevant, dispatchable** family from `owasp-catalog.md` is covered by
at least one lane. `N/A-with-reason` families (OWASP Mobile, memory-safety CWEs,
the LLM family with no LLM usage) are **out of scope by the catalog's own
contract** and are asserted only as *negative* expectations (the skill must
record them N/A, never fabricate a finding).

| Dispatch family | Primary CWE | Static lane | Judge lane |
| --- | --- | --- | --- |
| Injection — SQLi/DQL | CWE-89 | ✅ | ✅ |
| Injection — command sink | CWE-78/77 | ✅ | ✅ |
| Code injection / SSTI | CWE-94/1336 | ✅ | ✅ |
| Insecure deserialization | CWE-502 | ✅ | ✅ |
| SSRF | CWE-918 | ✅ | ✅ |
| Cryptographic failures (weak hash/cipher) | CWE-327/326 | ✅ | ✅ |
| Hardcoded secrets | CWE-798 | ✅ (in-tree demo, FR-7) | ✅ |
| XML external entities (XXE) | CWE-611 | ✅ | ✅ |
| Path traversal / file upload | CWE-22/434 | ✅ | ✅ |
| XSS / output encoding | CWE-79 | ✅ | ✅ |
| Open redirect | CWE-601 | ✅ | ✅ |
| Vulnerable / outdated deps | CWE-1104 | ✅ (pinned-version in-tree demo, FR-7) | — |
| BOLA / IDOR | CWE-639 | — (logic) | ✅ |
| BFLA | CWE-285/862 | — (logic) | ✅ |
| BOPLA / mass-assignment | CWE-915 | — (logic) | ✅ |
| Auth / session | CWE-287/307 | — (logic) | ✅ |
| Rate / resource exhaustion | CWE-770/400 | — (logic) | ✅ |

"Logic" families carry a **`-` in the static column by design, not by gap**: no
sound static rule decides "this object access is missing an ownership check"
without the runtime request context. They are validated by the judge lane and,
in the live skill, by dynamic reproduction against the running service.

## Fixture taxonomy — positive / negative / edge

Each family ships a triad (the "vulnerable PRs" the campaign generates and the
skill must classify):

- **`vulnerable.php`** (positive / true-positive): the seeded sink. The static
  lane MUST flag it; the judge MUST return FINDING.
- **`clean.php`** (negative / true-negative): the secure-by-default counterpart
  using the remediation from `remediation-patterns.md`. The static lane MUST
  stay silent; the judge MUST return CLEAN.
- **`edge_*.php`** (edge): adversarial cases that probe the *boundary* of the
  signature — sanitizer present but bypassable, a tainted value laundered
  through a variable, a safe API used unsafely, a commented-out sink (must NOT
  flag), a sink reached only on a non-default branch. Each edge fixture carries
  its own expected verdict so a too-greedy rule (false positive on a
  commented-out sink) and a too-narrow rule (false negative on a laundered
  taint) both fail the campaign.

## Risk-based prioritization

Test and fix in this order; a higher class preempts a lower one:

1. **False negative on a critical sink** (SQLi, command, code injection,
   deserialization, SSRF) — the skill claiming coverage it does not deliver is
   the worst failure; it gives false assurance.
2. **False positive on secure code** — erodes trust and, in the live loop,
   routes a non-bug to `php-implementer`, burning an iteration.
3. **Edge-case miss** — a bypassable sanitizer flagged clean, or a laundered
   taint missed.
4. **Degrade / contract drift** — a documented degrade path that loops or
   hard-fails, or a family whose playbook cannot reach its own CWE.

## Environments

- **Static lane:** `semgrep` (pinned in CI via `uvx`) over the fixture corpus,
  using `tools/security-audit-validation/rules/security-audit.yml`. Hermetic,
  offline, deterministic.
- **Judge lane:** the `claude` CLI (`sonnet` default, the prompt-quality judge
  convention) under `tools/security-audit-validation/judge/`. Skips with an
  explicit message + exit 0 when the CLI is absent.
- **Dep-demo lane:** an in-tree pinned-version assertion (no network) — the
  fixture `composer.json` pins a version inside a recorded known-vulnerable
  range; the harness asserts the pin matches the range (FR-7 in-tree
  demonstration), standing in for an online `composer audit`.
- No mutation of the real repo; fixtures are inert PHP/JSON under
  `tools/security-audit-validation/corpus/` and never executed.

## Bug severity

| Severity | Definition | Example |
| --- | --- | --- |
| S1 Critical | False negative on a critical-sink family, OR the skill fabricates a finding on an N/A family | semgrep misses `unserialize($_POST)`; auditor reports a finding on OWASP Mobile |
| S2 Major | False positive on a secure counterpart, OR a degrade path that loops/hard-fails | `password_hash` flagged as weak crypto |
| S3 Minor | Edge-case miss (bypassable sanitizer passed, laundered taint missed) | tainted value via intermediate var not traced |
| S4 Cosmetic | Wrong CWE label on an otherwise-correct finding | reports CWE-89 for a CWE-78 sink |

All S1/S2 block exit; S3 fixed when confirmed; S4 corrected opportunistically.

## Entry criteria

- PR #7 branch checked out; the static harness runnable (`semgrep` resolvable).
- Corpus present with at least the positive+negative triad per static family.
- The `security-audit` skill and `security-auditor` agent unchanged since the
  last green CI (so the campaign tests the shipped contract, not a draft).

## Exit criteria

- Every static-lane family has a passing TP (vulnerable flagged) and TN (clean
  silent); every edge fixture matches its recorded expected verdict.
- Every judge-lane family scores its seeded fixture FINDING and its clean
  fixture CLEAN at the configured vote count (when the CLI is available).
- The dep-demo lane confirms the pinned vulnerable version and the bumped clean
  version.
- **One full round of subagent-generated adversarial fixtures across all
  families yields zero new detection gaps** (the convergence condition).
- The new CI job (`security-audit-validation`) is green; existing CI stays green.

## Static-lane blind spots (judge-lane territory)

The deterministic static lane is **intraprocedural** (semgrep OSS taint) plus
**structural patterns**. The adversarial campaign (round 1) confirmed five
classes it cannot soundly decide — these are routed to the **judge lane** (and,
in the live skill, to dynamic reproduction), and are kept in the corpus as
`JL-*` fixtures with `static_expect=None`:

| Class | Example fixture | Why static cannot decide it |
| --- | --- | --- |
| **Interprocedural flow** | `path/jl_alias_sink_interproc.php`, `ssrf/jl_realpath_offpath.php`, `xss/jl_printf_interproc.php`, `redirect/jl_host_prefix_bypass.php` | the user source arrives as a parameter, or the sink is reached through a property bag / helper method — OSS taint does not cross function boundaries |
| **Dynamic dispatch** | `ssrf/jl_guzzle_dynamic_method.php`, `deserialization/jl_dynamic_dispatch.php`, `code/jl_variable_assert.php` | the sink is a variable function/method name or a string-built identifier (`$client->$verb()`, `'un'.'serialize'`) — no fixed call site to match |
| **Context-sensitivity** | `xss/jl_js_context.php` | `htmlspecialchars` is a valid HTML-context sanitizer but is insufficient when the value lands in a `<script>` JS context — deciding this needs output-context tracking |
| **Value-semantics name heuristics** | `crypto/jl_hash_alias_laundered.php`, `crypto/jl_cachekey_public_id_clean.php`, `secret/jl_array_key.php` | whether an `md5`'d / array-keyed value is *actually* a secret is a semantic judgement; the name regex both misses laundered names (FN) and over-fires on public ids (FP) |
| **Non-constant flags** | `xxe/jl_numeric_flag.php`, `code/jl_preg_replace_e.php` | the dangerous flag/modifier is an OR-folded integer or a concat-built `/e` — never the literal constant the pattern keys on |

This is a deliberate, documented division of labour, not a coverage gap: the
static lane gives a fast, deterministic, CI-gating backbone; the judge lane and
live dynamic probing cover the cases that require reasoning or runtime context.
Round 1 of the campaign also **closed nine** soundly-fixable gaps the same
fixtures exposed (Doctrine DBAL `executeQuery`, the backtick operator, `$_SERVER`
sources, `printf`/`file`/`SplFileObject`/`hash`/`call_user_func` sinks, the
null-coalesce credential default, `XMLReader` entity substitution, and missing
integer-coercion sanitizers) — each locked in by an `SC-*-E*` regression fixture.

## Loop protocol (subagent campaign)

Repeat per round until the convergence condition holds:

1. **Generate** — one red-team author subagent per family produces a fresh
   adversarial triad (a new "vulnerable PR" the skill has not seen).
2. **Detect** — run the static lane (+ judge lane when available) over each new
   fixture; record TP/TN/FN/FP.
3. **Verify** — a separate adversarial verifier subagent confirms each claimed
   gap reproduces (a real false negative/positive, not a mislabeled fixture).
4. **Fix** — repair the *rule* or the *skill/agent contract* (never the fixture
   expectation, unless the fixture itself is wrong); add a regression fixture.
5. **Re-detect** — rerun the full corpus; the round is clean only when zero
   confirmed new gaps remain.

Evidence per round lands in
`plugins/php-backend-sdlc/docs/evidence/security-audit-dogfood-run.md`; the
corpus, rules, harness, and any contract fix land in the branch.
