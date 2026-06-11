# Test Strategy — php-backend-sdlc QA Campaign

Contract sources: shipped scripts/commands/agents/docs in
`plugins/php-backend-sdlc/` and the PRD at
`specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md`.
A bug is any behavior contradicting those contracts or reasonable user
expectations: crashes, wrong output, silent failures, security escapes,
doc-reality mismatches. Not bugs: deferred E7 live-evidence items, cosmetic
wording, unreproducible environment flukes.

## Scope — 9 Surfaces

| Surface | What is tested | Primary contract |
| --- | --- | --- |
| scripts-cli | 7 `scripts/*.sh`: flags, exit codes, stdout/stderr, edge inputs | script `--help`/headers, bats suites |
| profile-fuzz | `generate-profile.sh` / `validate-profile.sh` vs malformed, hostile, exotic `composer.json`/YAML | FR-17 schema, `docs/profile-schema.md` |
| governance-inject | `inject-governance.sh` managed-block idempotency, re-run, weird pre-existing CLAUDE.md/AGENTS.md | FR-2, NFR-3 |
| gh-integration | `get-pr-comments.sh`, `ai-review-loop.sh`, `fr-nfr-gate.sh` against stubbed `gh`/`claude` | FR-8, FR-18, script docs |
| review-loop | iteration counting, zero-new-findings exit, max-5 escalation | FR-6, FR-8 |
| commands-semantics | 8 `commands/*.md`: stage gates, guards, degrade paths, resumability as written | FR-1..FR-8 |
| agents-contracts | 6 `agents/*.md`: tool allowlists, output formats, no-source-read rule for QA, no-auto-reset rule | FR-5..FR-8 |
| install-lifecycle | real `claude` CLI install/enable/run/uninstall from local marketplace | plugin manifest, README |
| security-adversarial | injection via filenames, YAML payloads, PR comment bodies, env vars; path traversal; command injection in scripts | implicit safety contract |

## Risk-Based Prioritization

Test and fix in this order; a higher class always preempts a lower one:

1. **Security** — adversarial inputs that achieve code execution, file
   writes outside the repo, or secret leakage (security-adversarial,
   profile-fuzz, gh-integration inputs).
2. **Silent failure** — exit 0 on broken state: profile half-written,
   governance block dropped, review loop declaring PASS without running
   (scripts-cli, governance-inject, review-loop).
3. **Contract drift** — behavior differs from PRD/docs/command text:
   wrong guard counts, missing degrade path, schema mismatch
   (commands-semantics, agents-contracts, install-lifecycle).
4. **UX** — confusing errors, missing remediation hints, noisy output.

## Environments

- **Bash sandboxes**: disposable dirs under `/tmp/sdlc-test-<surface>/`,
  created per session, deleted afterwards. All destructive runs happen here.
- **Stub binaries**: fake `gh`, `claude`, `composer`, `git` on a prepended
  `PATH` (pattern from `tests/lib` and `tests/fixtures`) to drive
  gh-integration and review-loop deterministically.
- **Real `claude` CLI**: only for install-lifecycle, against a local
  marketplace pointing at the working tree. No git mutations in
  `/home/kravtsov/Projects/claude-plugins`.
- **QA template clone**: `/home/kravtsov/Projects/tmp/php-sdlc-qa/php-service-template`
  for realistic profile generation and governance injection. Mutations
  allowed; never push; reset with `git checkout . && git clean -fd` between
  rounds.

## Bug Severity

| Severity | Definition | Example |
| --- | --- | --- |
| S1 Critical | Security escape, data loss, destroys user files outside managed blocks | YAML value reaches `eval`; inject clobbers user CLAUDE.md content |
| S2 Major | Wrong result with exit 0, broken core flow, doc promises feature that fails | validate passes invalid profile; loop exits PASS at iteration 0 |
| S3 Minor | Wrong exit code, error without remediation, degraded edge case | crash on empty `composer.json` instead of clean FAIL |
| S4 Cosmetic-functional | Misleading message or report field; behavior otherwise correct | report says "5 iterations" after 3 |

All S1/S2 block exit; S3 fixed when confirmed twice; S4 logged, fixed
opportunistically.

## Entry Criteria

- PR #2 branch checked out, all 151 bats tests green, 7 CI jobs green.
- QA template clone present and clean.
- Stub-binary harness verified by one smoke run per stubbed tool.

## Exit Criteria

- Every surface exercised at least once per round with recorded
  pass/fail evidence.
- All confirmed S1/S2 bugs fixed with a regression test (bats where the
  surface allows; otherwise a documented manual repro).
- **One full round across all 9 surfaces yields zero new confirmed bugs.**
- Full bats suite and markdownlint still green after the final fix.

## Loop Protocol

Repeat per round until exit criteria hold:

1. **Test** — execute the surface's checklist in a fresh sandbox; capture
   command, expected, observed for every deviation.
2. **Judge** — classify each deviation: confirmed bug (reproduce twice),
   environment fluke (drop), or contract ambiguity (record, default to
   user expectation). Assign severity.
3. **Fix** — repair the shipped artifact (script/command/agent/doc), never
   the test expectation, unless the contract itself is wrong — then fix
   the doc and note the drift.
4. **Regression** — add or extend a bats test (or manual repro note),
   rerun the full bats suite plus the affected surface's checklist.
5. **Repeat** — next surface in priority order; after the last surface,
   start a new round. Clean up `/tmp/sdlc-test-*` and reset the QA clone.

Evidence per round lives in the tester's session output (not committed);
only fixes and regression tests land in the branch.
