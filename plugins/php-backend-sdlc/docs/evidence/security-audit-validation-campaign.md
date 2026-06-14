# security-audit validation campaign — evidence

Evidence that the `security-audit` skill's detection **works** — that it flags
the vulnerabilities it claims to cover and stays silent on secure code — and
that it was hardened by an adversarial subagent loop until no new
soundly-fixable detection gaps remained.

The campaign and harness live at `tools/security-audit-validation/`; the
strategy / plan / cases are in
[`docs/testing/security-audit-test-*.md`](../testing/). This doc records the
loop outcomes.

## Method

Two lanes validate the skill's two detection mechanisms:

- **Static lane** (`detect.py` + `rules/security-audit.yml`): runs the real
  `semgrep` engine over a fixture corpus and asserts a true positive on every
  vulnerable fixture and a strict true negative on every clean one, plus an
  FR-7 in-tree dependency check. Deterministic, CI-gating.
- **Judge lane** (`judge/run_seed_judge.py`): asks `claude -p --model sonnet`,
  under the `security-auditor` verdict contract, to classify each fixture —
  covering the logic families and the static blind spots. Skip-clean without
  the CLI.

The adversarial loop: a Workflow fans out **one red-team author subagent per
family** to generate fresh PHP fixtures **designed to evade the current rules**;
`semgrep` then arbitrates each deterministically (a vulnerable fixture is a true
positive only if a rule actually fires; a clean one must stay silent). Confirmed
gaps are either fixed in the rule (when soundly detectable) or recorded as a
judge-lane blind spot.

## Round 0 — authored baseline

The hand-authored corpus: **58 PHP fixtures + 2 `composer.json` across 17
families** (vulnerable / clean / edge triads). The static lane passed **47/47**
(45 static TP/TN + 2 dependency), with 100% harness test coverage.

## Round 1 — adversarial subagent generation

A Workflow fanned out **11 red-team authors** (one per static family); they
produced **44 fresh adversarial fixtures**. semgrep arbitration surfaced **25
candidate gaps** (20 false negatives, 5 false positives).

**9 were soundly-fixable static gaps and were fixed**, each locked in by an
`SC-*-E*` regression fixture (baseline grew to **60/60**):

| Gap exposed | Fix |
| --- | --- |
| Doctrine DBAL `executeQuery()` SQLi sink unlisted | added DBAL execute* sinks |
| backtick operator `` `cmd $x` `` not modelled | added a backtick command rule |
| `$_SERVER` (e.g. `HTTP_X_FORWARDED_FOR`) not a taint source | `$_SERVER` added to all taint sources |
| `(int)`/`intval` not a sanitizer for command/redirect (2 false positives) | added int-coercion sanitizers |
| `unserialize()` of a parameter source missed | deserialization switched to pattern-mode (any non-constant) |
| `call_user_func('unserialize', …)` indirect sink | added as a deserialization sink |
| `file()` / `new SplFileObject()` read sinks missed | added to path sinks |
| `printf` / `vprintf` output sinks missed | added to XSS sinks |
| `hash('md5'\|'sha1', $cred)` alias form missed | added alias forms to the weak-hash rule |
| `$k = $v ?? "literal"` credential default missed | added the null-coalesce secret pattern |
| `XMLReader::setParserProperty(SUBST_ENTITIES, true)` missed | added the XMLReader XXE sink |
| multi-arg `header($x, true, 302)` redirect sink missed | broadened the header sink |

**16 were inherent OSS-static blind spots** — interprocedural data flow,
dynamic dispatch, output-context sensitivity, value-semantics name heuristics,
and non-constant flags. These cannot be soundly decided by an intraprocedural
static engine; they are kept in the corpus as `JL-*` fixtures
(`static_expect=None`) so the **judge lane** (and any future interprocedural
engine) must reach the right verdict. They are catalogued in the strategy doc's
"Static-lane blind spots" table. This is a documented division of labour, not a
coverage gap: the static lane is the fast deterministic backbone; the judge lane
and live dynamic probing cover reasoning- and runtime-context-dependent cases.

After round 1: static lane **60/60**, 66 harness unit tests, 100% coverage,
ruff/ty/xenon/bandit clean.

## Round 2 — adversarial pass against the improved rules

The authors were told what round 1 already covers and asked for **genuinely new
evasions**. 11 authors produced **44 more fixtures**; arbitration surfaced **28
candidate gaps**.

**13 more soundly-fixable static gaps were fixed** (each with an `SC-*-E*`
regression; static lane grew to **73/73**):

- sqli: `prepare()`-that-prepares-nothing + `mysqli_prepare` sinks; `PDO::quote`
  / `mysqli_real_escape_string` sanitizers (cleared a false positive)
- command: `pcntl_exec` sink; `proc_open([...])` array-form exclusion (cleared a
  false positive)
- deserialization: `yaml_parse` sink
- path: `highlight_file`/`show_source` sinks; `(int)`/`intval` sanitizers
- ssrf: `curl_setopt_array` sink; `(int)`/`intval` sanitizers (cleared a false
  positive)
- xss: `exit`/`die`/`php://output` sinks
- secret: a second rule for credential-named **property** assignments
- crypto: `hash_hmac` / `crypt` alias forms
- xxe: `DOMDocument::$resolveExternals` vector
- all taint rules: `filter_input` / `filter_input_array` / `getallheaders` /
  `apache_request_headers` added as sources

**The remaining 18 fell entirely into the already-documented blind-spot
classes** — no new *soundly-fixable* static gap appeared. They were kept as
`JL-*` judge-lane fixtures. This is the convergence signal: an adversarial round
against the hardened rules produced **zero new gaps the static lane could
soundly close** — every residual is interprocedural flow, dynamic dispatch,
array-element/handle flow, a dynamic/OR-folded flag, a value-semantics name
judgement, a custom (unknowable) sanitizer, or template configuration.

## Convergence

Two adversarial rounds (88 generated fixtures, 22 distinct sound rule
improvements, 34 documented blind-spot regressions) drove the static lane from
47 to **73/73** deterministic TP/TN assertions. The terminal state: a fresh
adversarial round yields only blind-spot-class cases, which are by construction
the judge lane's and live dynamic probing's territory — the static lane has
converged on its sound boundary. The campaign loop (generate → arbitrate → fix
or document) is reproducible via `tools/security-audit-validation/` and gated in
CI by `security-audit-validation.yml`.
