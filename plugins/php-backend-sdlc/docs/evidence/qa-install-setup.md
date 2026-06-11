# QA Evidence — install + setup surface (black-box)

Black-box QA of the `php-backend-sdlc` plugin's install and setup
surface. Every claim below is backed by an actually-run command and
captured output. No git commands were issued against either repository
by the tester (the only `git rev-parse`/`git remote` calls that appear
are internal to the scripts under test). Semgrep `SEMGREP_APP_TOKEN`
hook errors, where present, are environmental noise and not findings.

- Plugin source tree (scripts run from here):
  `/home/kravtsov/Projects/claude-plugins/plugins/php-backend-sdlc`
- Scripts invoked with
  `CLAUDE_PLUGIN_ROOT=/home/kravtsov/Projects/claude-plugins/plugins/php-backend-sdlc`.
- QA target (disposable fresh clone; mutations allowed, no pushes):
  `/home/kravtsov/Projects/tmp/php-sdlc-qa/php-service-template`.

## Toolchain present on the QA host

| Tool | Version | Floor | Note |
| --- | --- | --- | --- |
| claude CLI | 2.1.173 | 2.1 | above floor |
| gh CLI | 2.92.0 | 2 | above floor; authenticated |
| bmalph | 2.11.0 | 2.11.0 | exact ADR-10 floor |
| jq | 1.8.1 | — | JSON toolchain |
| python3 + PyYAML | PyYAML 6.0.3 | — | YAML + JSON fallback |
| yq | absent | — | YAML satisfied by PyYAML |

## Install verification (already-captured facts)

These four facts were captured during installation, before the matrix
run below:

- `claude plugin marketplace add /home/kravtsov/Projects/claude-plugins`
  → `Successfully added marketplace: vilnacrm-plugins`
- `claude plugin install php-backend-sdlc@vilnacrm-plugins`
  → `Successfully installed (scope: user)`
- `claude plugin details php-backend-sdlc` inventory:
  - 29 skill-entries (21 skills + 8 commands)
  - 6 agents
  - meta-guides not discovered (expected — they are reference docs, not
    discoverable skill/command/agent entries)
  - approximately 5.2k always-on tokens

The installed copy lives at
`/home/kravtsov/.claude/plugins/cache/vilnacrm-plugins/php-backend-sdlc/0.1.0`;
the scripts exercised below are byte-identical to that cache and were
run from the source tree for traceability.

## Matrix 1 — `setup-preflight.sh --report` (PASS)

Command:

```bash
cd <target> && CLAUDE_PLUGIN_ROOT=<plugin> \
  bash <plugin>/scripts/setup-preflight.sh --report
```

Exit code: `0`. Output:

```text
CHECK            RESULT DETAIL
-----            ------ ------
git-repo         PASS   inside a git work tree
claude-cli       PASS   version 2.1.173 (floor 2.1)
gh-cli           PASS   version 2.92.0 (floor 2)
gh-auth          PASS   gh is authenticated
bmalph           PASS   version 2.11.0 (floor 2.11.0)
bmalph-doctor    PASS   fresh repo (no _bmad/) — doctor deferred to post-init
yaml-toolchain   PASS   python3 + PyYAML available
json-toolchain   PASS   jq available
[php-sdlc][INFO] preflight OK: all checks passed
```

Version floors recorded: claude >= 2.1 (got 2.1.173), gh >= 2 (got
2.92.0), bmalph >= 2.11.0 (got exactly 2.11.0). `bmalph doctor` is
correctly deferred on the fresh repo (no `_bmad/` yet). gh is
authenticated.

**Verdict: PASS** — full 8-row PASS table, exit 0.

## Matrix 2 — `generate-profile.sh` (PASS)

Command:

```bash
cd <target> && CLAUDE_PLUGIN_ROOT=<plugin> \
  bash <plugin>/scripts/generate-profile.sh <target>
```

Exit code: `0`. Output:
`[php-sdlc][INFO] profile created: <target>/.claude/php-sdlc.yml`.

Generated `.claude/php-sdlc.yml`:

```yaml
schema_version: 1
project:
  name: "php-serice-template"
  repo: "VilnaCRM-Org/php-service-template"
php:
  version: "8.2"
framework:
  name: symfony
  version: "7.2."
  api_platform: "4.0"
  graphql: true
persistence:
  mapper: doctrine-orm
  engine: mysql
architecture:
  source_root: src
  bounded_contexts: ["CompanySubdomain", "Internal"]
  shared_context: Shared
make:
  ci: ci
  start: start
  tests: test
  e2e: null
  psalm: psalm
  deptrac: deptrac
  phpinsights: phpinsights
  infection: infection
  ai_review_loop: null
  pr_comments: null
  fr_nfr_gate: null
  load_tests: load-tests
quality:
  phpinsights:
    quality: 100
    architecture: 100
    style: 100
    complexity: 94
  deptrac_violations: 0
  psalm_errors: 0
  infection_msi: 100
ci:
  provider: github-actions
  workflows: ["Generate Changelog and Create Release", "CLI testing", ...]
  required_checks: []
review:
  coderabbit: true
  ai_review_agents: [claude]
  request_changes_blocking: true
capabilities:
  structurizr: true
  observability_emf: false
  load_testing: true
```

(The `ci.workflows` list above is truncated for readability; the file
holds all 20 detected workflow names.)

Sanity-check of detected values against the template's
`composer.json`, `Makefile`, `src/`, and config:

| Profile key | Detected | Source-of-truth | Match |
| --- | --- | --- | --- |
| `php.version` | `8.2` | composer `php: ">=8.2"` | yes |
| `framework.name` | `symfony` | `symfony/framework-bundle` present | yes |
| `framework.version` | `7.2.` | `symfony/framework-bundle: 7.2.*` | yes (cosmetic trailing dot, see defect D1) |
| `framework.api_platform` | `4.0` | `api-platform/core: ^4.0` | yes |
| `framework.graphql` | `true` | `webonyx/graphql-php` present | yes |
| `persistence.mapper` | `doctrine-orm` | `doctrine/orm` + `doctrine-bundle` | yes |
| `persistence.engine` | `mysql` | `.env` (see defect D2) | partial — active config is postgres |
| `architecture.bounded_contexts` | `CompanySubdomain, Internal` | `src/CompanySubdomain`, `src/Internal` | yes |
| `architecture.shared_context` | `Shared` | `src/Shared` | yes |
| `make.tests` | `test` | Makefile has `test:` (no `tests:`) | yes (fallback) |
| `make.e2e` | `null` | Makefile has no `e2e`/`e2e-tests` | yes (degrade) |
| `make.load_tests` | `load-tests` | Makefile `load-tests:` | yes |
| `make.ai_review_loop` / `pr_comments` / `fr_nfr_gate` | `null` | Makefile lacks these plugin targets | yes (degrade) |
| `review.coderabbit` | `true` | `.coderabbit.yaml` present | yes |
| `capabilities.structurizr` | `true` | `workspace.dsl` present | yes |

**Verdict: PASS** — profile generated, exit 0, detected values match
the template (two cosmetic/detection nuances recorded as D1/D2 below;
neither blocks generation or validation).

## Matrix 3 — `validate-profile.sh` on the generated profile (PASS)

Command:

```bash
CLAUDE_PLUGIN_ROOT=<plugin> \
  bash <plugin>/scripts/validate-profile.sh <target>/.claude/php-sdlc.yml
```

Exit code: `0`. Output:
`[php-sdlc][INFO] profile valid: <target>/.claude/php-sdlc.yml`.

No violations: required keys present, enums legal
(`doctrine-orm`/`mysql`), `schema_version == 1`, all 12 `make.*` keys
declared (nulls legal), quality thresholds at or above the ADR-7
shipped defaults, violation ceilings at 0.

**Verdict: PASS.**

## Matrix 4 — `inject-governance.sh` idempotency (NFR-3) (PASS)

A sentinel line was appended to both `CLAUDE.md` and `AGENTS.md`
**outside any marker** before the first run, to prove content outside
the managed block is never touched.

First run:

```bash
CLAUDE_PLUGIN_ROOT=<plugin> bash <plugin>/scripts/inject-governance.sh <target>
```

Exit code: `0`. Output:

```text
[php-sdlc][INFO] CLAUDE.md: managed block written
[php-sdlc][INFO] AGENTS.md: managed block written
```

After the first run: exactly one `begin`/`end` marker pair in each
file; both sentinel lines still present.

`md5sum` after first run:

```text
02f4ba312cdc6a1aea8823bb2f3ff02c  CLAUDE.md
300201c7e59b460db761c0877cd59982  AGENTS.md
```

Second run (idempotency):

```text
[php-sdlc][INFO] CLAUDE.md: unchanged
[php-sdlc][INFO] AGENTS.md: unchanged
[php-sdlc][INFO] governance blocks already up to date
```

Exit code: `0`. `md5sum` after the second run is byte-for-byte
identical to the first (same two hashes), and both sentinel lines
survive.

**Verdict: PASS** — second run reports unchanged, output is byte-stable
(NFR-3), user content outside the markers is untouched.

## Matrix 5 — Symlink defense (security regression) (PASS)

`CLAUDE.md` was replaced with a symlink to an out-of-repo file
(`/tmp/qa-symlink-outside-target.txt`, holding a known marker string),
then `inject-governance.sh` was run:

```bash
ln -s /tmp/qa-symlink-outside-target.txt <target>/CLAUDE.md
CLAUDE_PLUGIN_ROOT=<plugin> bash <plugin>/scripts/inject-governance.sh <target>
```

Exit code: `1`. Output:

```text
[php-sdlc][ERROR] refusing to follow symlink: <target>/CLAUDE.md
(managed governance files must be regular files inside the target repo)
```

The out-of-repo file's `md5sum` was identical before and after
(`b21b05736ff948e24cefd6ce49e40ff6`), and its contents
(`ORIGINAL-OUTSIDE-CONTENT-DO-NOT-MODIFY`) were unchanged.

**Verdict: PASS** — the tool refused to follow the symlink and the
out-of-repo file was never written.

## Matrix 6a — Degrade: missing Makefile (NFR-4) (PASS)

The target `Makefile` was temporarily renamed and the profile
regenerated:

```bash
mv <target>/Makefile <target>/Makefile.qa-renamed
CLAUDE_PLUGIN_ROOT=<plugin> bash <plugin>/scripts/generate-profile.sh <target>
```

Exit code: `0` (generation never fails on a missing capability — A3).
All `make.*` keys became `null` and `capabilities.load_testing` became
`false`:

```yaml
make:
  ci: null
  start: null
  tests: null
  e2e: null
  psalm: null
  deptrac: null
  phpinsights: null
  infection: null
  ai_review_loop: null
  pr_comments: null
  fr_nfr_gate: null
  load_tests: null
```

`validate-profile.sh` on this degraded profile returned exit `0`
(`profile valid`) — all-null `make.*` keys are legal (capability
absent). The `Makefile` and the original profile were then restored.

Note on "warnings": the script degrades the make map to nulls
*silently* — no per-key WARN line is emitted for the absent Makefile
(its design contract is "a missing capability NEVER fails generation —
it becomes null/false"). The detectable, asserted degrade signal is the
null make map plus `load_testing: false`, which is what downstream
skills/agents key off. Recorded as observation O1, not a defect.

**Verdict: PASS** — generation succeeds with null `make.*`, profile
still validates.

## Matrix 6b — Degrade: no `jq` on PATH, python fallback (NFR-4) (PASS)

A sandbox PATH was built containing python3, git, and a `gh` stub
(emitting the `tests/fixtures/gh/pr-comments.json` GraphQL payload for
`gh api graphql` and `acme/sample-api` for `gh repo view`) but
**deliberately no `jq`**:

```bash
PATH=<sandbox-bin-only> CLAUDE_PLUGIN_ROOT=<plugin> \
  bash <plugin>/scripts/get-pr-comments.sh --pr 7 --json
```

(`command -v jq` returns nothing on the sandbox PATH.) Exit code: `0`.
The script took the python3 fallback and emitted the canonical JSON
shape correctly, e.g.:

```json
{
  "pr": 7,
  "review_threads": [
    { "is_resolved": false,
      "comments": [
        { "author": "coderabbitai",
          "body": "Consider validating the input length here.",
          "path": "src/Catalog/Handler.php", "line": 42, "url": "...r100" },
        { "author": "maintainer", "body": "Good catch, will fix.",
          "path": "src/Catalog/Handler.php", "line": 42, "url": "...r101" } ] },
    { "is_resolved": true,
      "comments": [
        { "author": "reviewer", "body": "Rename this method for clarity.",
          "path": "src/Order/Service.php", "line": 17, "url": "...r102" } ] }
  ],
  "issue_comments": [
    { "author": "ci-bot",
      "body": "Overall summary: 2 findings, 1 addressed.", "url": "...900" }
  ]
}
```

The human rendering and `--unresolved-only` modes were also run on the
no-jq PATH and produced the correct listing, including
`unresolved threads: 1` (and, under `--unresolved-only`, the resolved
thread and issue comments correctly suppressed). All three invocations
exited `0`.

(There is no `--help` flag on `get-pr-comments.sh`; an unknown argument
intentionally `die`s. The fixture-stub-driven invocation above is the
sanctioned way to exercise the script without a live PR, mirroring the
bats fixtures approach.)

**Verdict: PASS** — full python3 fallback works with `jq` absent.

## Matrix 7 — Seeded-defect QA demonstration (FR-7 evidence, scoped)

This item demonstrates how the `qa-manual-tester` agent produces a FAIL
verdict against a running service, using a stub HTTP service in place of
the booted PHP service. A `python3 -m http.server` was booted on port
8099 serving a stub root; the deliberately-absent endpoint
`/api/missing` was probed.

Commands actually run:

```bash
cd /tmp/qa-stub-service && python3 -m http.server 8099 &   # boot stub "service"
curl -s -o /dev/null -w 'GET / -> HTTP %{http_code}\n' http://localhost:8099/
curl -s -o /dev/null -w 'GET /api/missing -> HTTP %{http_code}\n' \
  http://localhost:8099/api/missing
```

Observed:

```text
GET / -> HTTP 200
GET /api/missing -> HTTP 404
HTTP/1.0 404 File not found
```

The agent's degrade rule is explicit: "Service boots but a single
endpoint is missing or erroring → that is a finding (FAIL on the mapped
AC with repro steps), never a degrade." The probe maps to a FAIL.
Rendered in the exact report contract from
`agents/qa-manual-tester.md`:

```text
# qa-manual-tester report — iteration 1/5
service: make.start = start, base URL = http://localhost:8099

## Checks (every AC maps to >=1 executed check)
| AC | kind | request | expected | observed | verdict |
|---|---|---|---|---|---|
| AC-1 | positive | GET / | HTTP 200 service reachable | HTTP 200 | PASS |
| AC-2 | negative | GET /api/missing | HTTP 200 + resource JSON | HTTP 404 File not found | FAIL |

## Failures and reproduction steps
### AC-2 — FAIL
reproduction:
  1. cd /tmp/qa-stub-service && python3 -m http.server 8099 &
  2. curl -i http://localhost:8099/api/missing
expected: HTTP 200 with the resource document for the endpoint under test
observed: HTTP/1.0 404 File not found (endpoint not exposed by the running service)

## Degrade notes
- none

## Verdict: FAIL
```

A FAIL verdict routes back to `/sdlc-implement`; the agent only
delivers the evidence and never fixes. The stub service was killed and
its port freed after the run (verified: post-kill `GET /` → connection
refused / HTTP 000).

**Verdict: PASS** (the matrix item — demonstrating that a missing
endpoint yields a correctly-formatted FAIL verdict — succeeded; the
*service-under-test verdict it demonstrates* is FAIL by construction).

## Matrix 8 — Permission evidence (E7-S4, scoped)

- Implementation-phase Ralph loops in this repo ran with
  `bypassPermissions`: confirmed by
  `/home/kravtsov/Projects/claude-plugins/.ralph/.ralphrc`, which sets
  `CLAUDE_PERMISSION_MODE="bypassPermissions"` (a deliberate,
  documented opt-in for the unattended `bmalph run` driver).
- The plugin's documented default is `acceptEdits`:
  `docs/permissions.md` states every `claude -p` invocation the plugin
  makes runs with `--permission-mode acceptEdits`, and `bypassPermissions`
  "is NEVER a default anywhere in this plugin"; `/sdlc-setup` never
  writes it. The `claude_run_once` helper in `scripts/lib/common.sh`
  hard-codes `--permission-mode acceptEdits`, matching the doc.
- Permission prompts hit during this QA run: **none**. Every script
  exercised here is plain bash (no `claude -p` calls were triggered),
  so no permission negotiation occurred — exactly as expected.

**Verdict: PASS** — Ralph-loop `bypassPermissions` and the plugin's
`acceptEdits` default are both substantiated from on-disk config, and
no prompts surfaced.

## Defects and observations

These are reported, not fixed (QA does not edit plugin code).

- **D1 (cosmetic).** `framework.version` is emitted as `"7.2."` (with a
  trailing dot) for the constraint `symfony/framework-bundle: 7.2.*`.
  `strip_constraint` strips the leading `^`/`>=` and trailing wildcard
  but leaves the dot before `*`. Cosmetic only — does not affect
  validation or any consumer that reads a major.minor prefix. Source:
  `scripts/generate-profile.sh` `strip_constraint`.
- **D2 (detection nuance).** `persistence.engine` is detected as
  `mysql`, but the target's *active* `.env` config is
  `DB_URL=postgres://...@database:5432`. The detector greps the whole
  concatenated `.env` text and matches the **commented-out** example
  line `# DB_URL="mysql://..."` before reaching the postgres pattern
  (mysql is checked before postgresql, and comment lines are not
  stripped). The engine enum is still legal so validation passes, but
  the value is a false positive for this particular template. Source:
  `scripts/generate-profile.sh` engine detection block.
- **O1 (observation, not a defect).** On a missing `Makefile`,
  `generate-profile.sh` degrades the make map to nulls silently (no
  per-key WARN). This matches its stated contract (A3/NFR-4: a missing
  capability becomes null and never fails generation). The asserted
  degrade signal is the null make map, not a stderr warning.

## Scope notes (honest)

- The full G3 reference run (a live issue → PR cycle driven on a real
  service repository) and the FR-8 live `finish-pr` demonstration are
  **out of scope for this install/setup QA pass**. They are captured
  separately on the plugin's own PR during the PR finishing phase —
  cross-reference `docs/evidence/finish-pr-run.md` ("captured in PR
  finishing phase"; that file is produced by the finish-pr run, not by
  this setup QA).
- Matrix 7 uses a `python3 -m http.server` stub in place of a booted
  PHP service to demonstrate the FAIL verdict mechanics and report
  format; it does not exercise a real `make.start` boot of the
  template.
- No git commands were issued against either repository by the tester.
- All QA-target mutations were reverted except the intentionally-kept
  generated profile (`.claude/php-sdlc.yml`) and the governance blocks
  in `CLAUDE.md`/`AGENTS.md`. The renamed `Makefile`, the symlink test
  artifacts, the QA sentinel lines, the no-jq sandbox, and the stub
  service were all removed.

## Defect resolution

Both defects found by this QA run were fixed root-cause in
`scripts/generate-profile.sh` and locked with regression bats
(`tests/generate-profile.bats`):

- D1: wildcard composer constraints no longer leave a trailing dot
  (`7.2.*` → `7.2`).
- D2: engine detection strips comment lines from every hint source and
  takes the first active driver hint, so the active `postgres://` DSN
  now yields `persistence.engine: postgresql` on this template.

Regenerated profile on the QA clone after the fix: `framework.version:
"7.2"`, `persistence.engine: postgresql`, `validate-profile.sh` PASS.
