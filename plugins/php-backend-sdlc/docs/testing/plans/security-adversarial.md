# Test Plan — security-adversarial (Round 1)

Surface: every shipped `scripts/*.sh` run against a deliberately hostile
target repository — symlinks at every interesting write path, command-
injection payloads in repo-derived text (composer name, origin URL, src/
context dirs, Makefile targets, workflow names, `.env`, PR numbers, agent
lists), YAML-breaking strings, path traversal, malicious `.git/config`,
and huge/deeply-nested/alias-bombed inputs.

Contract: the implicit safety contract (test-strategy §"security-
adversarial") plus the explicit anti-escape comments in the scripts
(`generate-profile.sh` symlink/realpath containment lines 361-370 and
`sanitize_inline` lines 89-92; `inject-governance.sh` `reject_symlink`;
`fr-nfr-gate.sh` `--spec-path` containment). PRD: managed-block injection
"existing content never clobbered". Severity per test-strategy §"Bug
Severity" (S1 security escape … S4 cosmetic).

Pass bar for this surface, checked after every case:

- No write (file or directory) is created outside the target repo.
- No injected command executes (canary files planted in
  `/tmp/sdlc-test-sec-OUTSIDE/`; sentinel byte-stable).
- The emitted profile is valid YAML that round-trips with no
  attacker-injected keys or structure.
- User content outside managed blocks is never modified.

Environment: hostile repo and sub-sandboxes under `/tmp/sdlc-test-sec/`;
out-of-repo canary/sentinel dir `/tmp/sdlc-test-sec-OUTSIDE/`; stub `gh`
and `claude` on a prepended PATH. `yq` absent on host → python3+PyYAML
backend exercised (yq path covered by CI bats). Sandboxes deleted after
the round.

## Positive cases — legitimate behavior still works

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| SEC-P1 | generate-profile on hostile repo (injection payloads in every detected field) | exit 0; profile written inside repo `.claude/`; no canary | PASS |
| SEC-P2 | Emitted hostile-derived profile parses as YAML and round-trips | `yaml.safe_load` OK; only the 11 schema top-keys present; no injected keys in `framework`/root | PASS |
| SEC-P3 | validate-profile on the hostile-derived profile | exit 0 `profile valid` (all values legal after quoting/sanitization) | PASS |
| SEC-P4 | get-pr-comments against hostile origin URL, stubbed gh, `--pr 1 --json` | exit 0; clean canonical JSON; no canary (slug never shell-evaluated) | PASS |
| SEC-P5 | inject-governance on hostile pre-existing CLAUDE.md (shell metachars + orphan/nested markers) | exit 0; all user lines preserved verbatim; exactly one begin/one end marker; no canary | PASS |
| SEC-P6 | fr-nfr-gate with a legitimate in-repo `--spec-path specs` | spec-path accepted, gate proceeds to call claude (stub) | PASS |

## Negative cases — hostile input must be refused or neutralized

| ID | Attack | Expected | Result |
| --- | --- | --- | --- |
| SEC-N1 | `.claude/` is a symlink to an existing dir outside the repo (generate-profile) | die "profile parent (.claude) is a symlink; refusing to write"; nothing written outside | PASS |
| SEC-N2 | `.claude/` is a dangling symlink to a nonexistent dir outside the repo | exit non-zero; the out-of-repo target dir is NOT created | PASS |
| SEC-N3 | `.claude/php-sdlc.yml` itself is a symlink pointing outside the repo | die "profile path is a symlink; refusing to write"; no out-of-repo file created | PASS |
| SEC-N4 | `CLAUDE.md` is a symlink to a secret file outside the repo (inject-governance) | die "refusing to follow symlink"; victim file byte-unchanged | PASS |
| SEC-N5 | Same symlinked CLAUDE.md via `--diff` (read path) | die "refusing to follow symlink"; victim file untouched | PASS |
| SEC-N6 | fr-nfr-gate `--spec-path` is an absolute path outside the repo | die "spec path escapes the repository boundary" | PASS |
| SEC-N7 | fr-nfr-gate `--spec-path` uses `..` and resolves outside the repo | die "spec path escapes the repository boundary" | PASS |
| SEC-N8 | fr-nfr-gate `--spec-path` is a symlink (dir) pointing outside the repo | die "refusing to follow symlink for --spec-path" | PASS |
| SEC-N9 | fr-nfr-gate `--spec-path` is a symlinked FILE pointing outside the repo | die "refusing to follow symlink for --spec-path" | PASS |
| SEC-N10 | get-pr-comments `--pr` with `;`/`$()`/SQL-ish/negative payloads | die "--pr must be a number"; no canary | PASS |
| SEC-N11 | composer.json `name` carrying `"`, newline, `$()`, backticks; origin URL with `$()`/backticks | values quoted+sanitized in profile; no structural YAML injection; no canary | PASS |
| SEC-N12 | src/ bounded-context dirs named with `$()`, backticks, `"quote: yes`, `;rm -rf`, embedded newline | each name sanitized + quoted in flow list; profile parses; no canary | PASS |
| SEC-N13 | Makefile with a quoted hostile target name (`"evil; touch …":`) | only `^[A-Za-z0-9_-]+:` targets captured; hostile target ignored; no canary | PASS |
| SEC-N14 | `.env` with shell metachars + YAML-breaking `DATABASE_URL`/secret values | engine detected by hint match only; raw `.env` values never emitted; no canary | PASS |
| SEC-N15 | ai-review-loop hostile `review.ai_review_agents` (`claude; touch …`, `$()`) and `--agents` override | agent names compared/logged as strings, never eval'd; warn+skip; no canary | PASS |
| SEC-N16 | Malicious `.git/config` (`core.fsmonitor`, `core.pager`, alias) in the untrusted repo | plugin git calls (`rev-parse --is-inside-work-tree`, `remote get-url`, `rev-parse --show-toplevel`, `rev-parse HEAD`) do not refresh the index/page → no command runs; no canary | PASS |
| SEC-N17 | Symlinked composer.json → /etc/passwd, symlinked Makefile/.env (read paths) | read-only; unparseable composer degrades to null (no /etc/passwd leak into profile); exit 0; no escape | PASS |

## Edge cases — robustness / DoS

| ID | Input | Expected | Result |
| --- | --- | --- | --- |
| SEC-E1 | composer.json deeply nested (5000 levels) + 200 KB `name` | exit 0 within timeout; degrades to basename when jq rejects the depth; no crash/hang | PASS |
| SEC-E2 | Billion-laughs (anchor/alias bomb) profile → validate-profile | no exponential blow-up (PyYAML resolves aliases to shared refs); clean violations in <1 s; bounded memory | PASS |
| SEC-E3 | Billion-laughs anchors inside a `.github/workflows/*.yml` → generate-profile name parse | workflow name folded to a benign scalar; exit 0; no DoS | PASS |
| SEC-E4 | Workflow **filename** containing a newline, with no `name:` key (basename fallback) | control chars stripped, value on a single YAML line (per `sanitize_inline` invariant) | FAIL → BUG-1 |

## Findings

- **BUG-1 (SEC-E4, S3 minor)**: `generate-profile.sh` line 247 — the
  workflow-name basename fallback
  (`name="$(basename "$wf" | sed …)"`) is NOT wrapped in
  `sanitize_inline`, unlike the `name:`-content path on line 246 and every
  other repo-derived value. A workflow file whose filename contains a
  newline and which has no internal `name:` key therefore leaks a raw
  newline into the emitted profile, producing a multi-line
  `ci.workflows` value:

  ```text
    workflows: ["evil
  INJECT: x"]
  ```

  This violates the script's own documented invariant (lines 89-92:
  "drop control characters (incl. newline/CR) … profile values are
  emitted on a single YAML line") and is inconsistent with the sanitized
  sibling path. It is NOT a structural injection: YAML double-quote line
  folding collapses the value to the harmless string
  `evil INJECT: x`, the profile still parses with no attacker-injected
  keys, and `validate-profile.sh` never reads `ci.workflows` — so it is
  contained, hence minor. Fix: wrap the line-247 fallback in
  `sanitize_inline`. Confirmed twice; control case (newline inside the
  `name:` field) is correctly sanitized to a single line.

## Round-1 verdict

27 cases executed (6 positive + 17 negative + 4 edge). 26 PASS, 1 FAIL.

No write or directory was created outside the target repo, no planted
canary command executed across any script, the sentinel stayed
byte-stable, every symlink write target and out-of-repo `--spec-path` was
refused, and no hostile value achieved structural YAML or key injection.
The sole defect is BUG-1, a contained control-character sanitization gap
on one untrusted-input path (S3 minor).
