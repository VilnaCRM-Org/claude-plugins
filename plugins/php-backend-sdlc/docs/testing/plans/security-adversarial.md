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

## Round-2 (verification + regression hunt)

Re-ran every re-runnable round-1 case against the FIXED scripts (HEAD
`ad6497e`), then added new adversarial cases targeting the round-1
fixes themselves: the inject-governance atomic-mv rewrite (the commit
calls it a "lockfile"; it is mv-based last-writer-wins, no lock), the
TOCTOU window between `reject_symlink` and the write, the
validate-profile `num_gt`/`num_lt` wrap-safe ceiling/floor comparison,
the `:=` Makefile parsing regex, the work-tree preflight, hostile
profile values flowing into the claude prompt, and `git config` hooks
in the target repo. Environment as round 1: `yq` absent (python3+PyYAML
backend), `jq` present, stub `gh`/`claude` on a prepended PATH,
canary/sentinel dir `/tmp/sdlc-test2-OUTSIDE/`, sandboxes under
`/tmp/sdlc-test2-security-adversarial/`. All 164 regression bats pass.

### Round-1 cases re-run (verification)

| ID | Result R2 | Note |
| --- | --- | --- |
| SEC-P1 | PASS | hostile repo → profile inside `.claude/`, no canary |
| SEC-P2 | PASS | only the 11 schema top-keys; hostile values inert quoted scalars |
| SEC-P3 | PASS | validate-profile exit 0 on hostile-derived profile |
| SEC-P4 | PASS | hostile origin URL → clean JSON `pr:1`, slug never eval'd |
| SEC-P5 | PASS | orphan/nested markers → one block, all user lines verbatim |
| SEC-P6 | PASS | in-repo `--spec-path` accepted; claude stub PASS, status posted |
| SEC-N1 | PASS | `.claude` symlink-to-existing-dir refused; nothing written out |
| SEC-N2 | PASS | dangling `.claude` symlink: out-of-repo dir NOT created |
| SEC-N3 | PASS | symlinked profile file refused; no out-of-repo file |
| SEC-N4 | PASS | symlinked CLAUDE.md (write) refused; victim byte-stable |
| SEC-N5 | PASS | symlinked CLAUDE.md (`--diff` read) refused; victim untouched |
| SEC-N6 | PASS | absolute out-of-repo `--spec-path` → boundary die |
| SEC-N7 | PASS | `..`-escaping `--spec-path` → boundary die |
| SEC-N8 | PASS | symlinked-dir `--spec-path` → symlink die |
| SEC-N9 | PASS | symlinked-file `--spec-path` → symlink die |
| SEC-N10 | PASS | all `--pr` injection/negative payloads → "must be a number" |
| SEC-N11 | PASS | composer name / origin metachars quoted+sanitized, no injection |
| SEC-N12 | PASS | hostile src/ dir names sanitized+quoted in flow list |
| SEC-N13 | PASS | hostile quoted Makefile target ignored (only legit targets) |
| SEC-N14 | PASS | `.env` engine by hint only; raw values never emitted |
| SEC-N15 | PASS | hostile agent names compared/logged as strings, never eval'd |
| SEC-N16 | PASS | malicious `.git/config` plumbing reads run no command |
| SEC-N17 | PASS | symlinked composer→/etc/passwd read-only, degrades, no leak |
| SEC-E1 | PASS | 5000-deep + 200 KB name → basename degrade, no hang |
| SEC-E2 | PASS | billion-laughs profile validates fast, bounded memory |
| SEC-E3 | PASS | billion-laughs workflow name folds to benign scalar |
| SEC-E4 | **PASS (was FAIL→BUG-1)** | workflow-filename newline now sanitized: single-line `["evilINJECT"]`, no raw newline |

### Round-2 new adversarial cases

| ID | Attack | Expected | Result |
| --- | --- | --- | --- |
| SEC-R2-1 | Pre-plant symlinks at guessed lock/temp paths (`.sdlc-governance`, `.sdlc-governance.lock`) before inject-governance | mktemp's random `.XXXXXX` never reuses a planted path; victims byte-stable; write still succeeds | PASS |
| SEC-R2-2 | TOCTOU: attacker swaps CLAUDE.md→symlink-to-outside-victim 2000× during 50 inject runs | atomic `mv -f` over the swapped-in symlink replaces it (never follows); out-of-repo victim byte-stable | PASS |
| SEC-R2-3 | Prompt-injection canary in `--impact-context` (`$(touch …)` + fake `FR_NFR_NEW_FINDINGS: 999`) | text passed to claude as a single data arg, never shell-eval'd; gate parses claude OUTPUT not the prompt; no canary | PASS |
| SEC-R2-4 | `git config` `core.hooksPath`/`core.fsmonitor`/`core.pager`/`alias` planted, then run every plugin git call (rev-parse, remote get-url, show-toplevel, rev-parse HEAD) across all 4 git-using scripts | read-only plumbing invokes no hook/fsmonitor/pager/alias; no canary | PASS |
| SEC-R2-5 | `:=`/`::=`/`:::=`/`+=`/`!=`/`?=` variable assignments + double-colon + pattern + recipe-bearing targets in one Makefile | every assignment flavor excluded; every legit target (incl. `infection::`) detected | PASS |
| SEC-R2-6 | setup-preflight git-repo across topologies: work tree, bare repo, `.git/` interior, non-git, linked worktree | work tree + linked worktree PASS; bare/`.git`/non-git FAIL — no false negative on legit worktree | PASS |
| SEC-R2-7 | validate-profile ceiling matrix: `0,1,2^64-1,2^64,10^30,-1,0x10,007,1e3,"5"` | wrap-safe: `2^64-1` rejected (not wrapped to -1); huge values rejected; `-1`/`1e3` non-integer; correct otherwise | PASS |
| SEC-R2-8 | validate-profile floor matrix incl. `2^64-1` raise | large valid raise accepted (not falsely rejected by wrap); lowered values flagged | PASS |
| SEC-R2-9 | `num_gt`/`strip_zeros` fuzzed against Python ground truth across magnitudes | all comparisons match `int()` ground truth; no wrap bug either direction | PASS |
| SEC-R2-10 | Asymmetric CRLF markers (begin CR, end LF) in pre-existing CLAUDE.md | recognized, collapsed to one block, old body replaced, footer kept | PASS |
| SEC-R2-11 | CRLF (Windows) markers: full CRLF CLAUDE.md with existing block | recognized (not duplicated); user content keeps CRLF, block written LF | PASS |
| SEC-R2-12 | 20 concurrent inject-governance runs on a shared CLAUDE.md | last-writer-wins: exactly one begin/one end, user content kept, no temp litter | PASS |
| SEC-R2-13 | Idempotency: re-run inject-governance on a written file | byte-stable; second run logs "unchanged" | PASS |
| SEC-R2-14 | get-pr-comments: gh exits 0 emitting HTML (proxy 502 page) | clean `[php-sdlc][ERROR]` non-JSON diagnostic + remediation, exit 1, no traceback | PASS |
| SEC-R2-15 | validate-profile on malformed YAML (unterminated quote, stray colons) | clean `[php-sdlc][ERROR] not valid YAML` diagnostic, no PyYAML traceback | PASS |
| SEC-R2-16 | Counter-transport audit: every counter-bearing agent declares its dispatched counter input | sdlc-qa↔qa-manual-tester and sdlc-finish-pr↔pr-comment-resolver transports coherent end-to-end | PASS |

### Round-2 findings

No new security escape, crash, silent failure, or contract violation was
found. Every round-1 FAIL re-run (SEC-E4 / BUG-1) now PASSES: the
workflow-filename basename fallback is wrapped in `sanitize_inline`, so a
newline-bearing filename folds to a single-line scalar. All other round-1
PASS cases still PASS.

Notes on the fixes (not bugs):

- The inject-governance write path is now TOCTOU-safe by construction:
  even when an attacker wins the race between `reject_symlink` and the
  write, `mv -f $tmp $file` renames over a swapped-in symlink rather than
  following it (verified with a 2000-swap race; the out-of-repo victim
  stayed byte-stable). This strictly improves on the old `cat >"$file"`,
  which would have followed the link.
- The round-1 commit message says inject-governance "takes a lockfile
  against concurrent runs." The implementation has no lockfile; it relies
  on per-file atomic `mktemp`+`mv` (last-writer-wins). The behavior is
  correct (20-way concurrency leaves exactly one well-formed block) and
  the in-script comment describes the mv mechanism accurately, so this is
  a commit-message wording inaccuracy only, not a code or user-doc defect.

## Round-2 verdict

43 cases executed (27 round-1 re-runs + 16 new). 43 PASS, 0 FAIL. The
one round-1 FAIL (SEC-E4/BUG-1) is confirmed fixed. No new bug, no
regression introduced by any round-1 fix. No out-of-repo write, no canary
execution, sentinel byte-stable, and no hostile value achieved YAML/key
injection, prompt shell-escape, git-hook execution, or threshold-ceiling
wrap bypass.
