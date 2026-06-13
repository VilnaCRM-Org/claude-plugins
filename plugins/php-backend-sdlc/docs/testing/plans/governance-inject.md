# Test Plan — governance-inject

Surface owner: QA subagent, round 1. Contract sources:

- `scripts/inject-governance.sh` header comment (usage, marker-repair
  semantics, `--diff`).
- PRD FR-2 (governance injection bullet) and NFR-3 (idempotency, "no
  duplicate blocks ever", content outside markers never clobbered) in
  `specs/autonomous/2026-06-09-php-backend-sdlc-plugin/prd.md`.
- `docs/testing/test-strategy.md` (severity ladder, sandbox rules).

## Method

- Sandboxes: `/tmp/sdlc-test-governance-inject/<case-id>/`, deleted after
  the run. QA template clone used only for X06; reset afterwards.
- NFR-3 verification on **every mutating case**: sha256 of the content
  outside the managed region (exact `<!-- php-backend-sdlc:begin -->` /
  `<!-- php-backend-sdlc:end -->` lines and everything between balanced
  pairs stripped) is captured before and after and must match, modulo the
  documented separator newline on first append.
- Every FAIL is re-run once before being recorded (strategy: confirm
  twice, drop environment flukes).

## Positive cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| P01 | Both files missing | Both created, exit 0, exactly one marker pair each, all three governance sections present | PASS |
| P02 | Existing non-empty `CLAUDE.md`/`AGENTS.md`, no markers | Block appended after blank separator; original bytes are an untouched prefix | PASS |
| P03 | Second run after P02 (NFR-3 AC) | Exit 0, `unchanged` logged, files byte-identical (sha256) | PASS |
| P04 | Stale block between user sections | Block replaced in place; outside-markers bytes identical; position preserved | PASS |
| P05 | `--diff` vs apply parity | `--diff` writes nothing; applying its unified diff with `patch` yields byte-identical file to a real run | PASS |
| P06 | `generate-profile.sh` + inject sequence on QA clone, then re-run both, then `generate-profile.sh --refresh` | Second full run leaves `git diff` empty; `--refresh` never touches `CLAUDE.md`/`AGENTS.md` (sha256 stable) | PASS |

## Negative cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| N01 | Nonexistent target dir | Exit 1, `target directory not found` | PASS |
| N02 | Unknown flag `--bogus` | Exit 1, usage error naming the flag | PASS |
| N03 | Target path is a regular file | Exit 1, `target directory not found` | PASS |
| N04 | Read-only (0444) `CLAUDE.md` that needs a change | Non-zero exit, no silent exit-0, file unmodified | PASS |
| N05 | Read-only (0555) target dir, files missing | Non-zero exit, no partial file created | PASS |
| N06 | `CLAUDE.md` symlink to a file outside the repo | Exit 1, `refusing to follow symlink`, link target byte-identical | PASS |
| N07 | `CLAUDE.md` is a directory | Non-zero exit (no exit-0 silent failure), directory left intact | PASS |

## Edge cases

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| E01 | File with only the BEGIN marker | Marker line removed, all user lines preserved, one fresh block appended | PASS |
| E02 | File with only the END marker | Same repair semantics as E01 | PASS |
| E03 | Two balanced marker pairs with user text between blocks | Collapse to one block at the first pair's position; all user lines byte-preserved | PASS |
| E04 | Three balanced pairs interleaved with user text | Same collapse-to-first semantics | PASS |
| E05 | END before BEGIN, counts balanced | Marker lines removed, user lines preserved, fresh well-ordered block appended | PASS |
| E06 | Nested BEGIN BEGIN END END | Treated as corrupt: markers removed, user lines preserved, one block appended | PASS |
| E07 | Marker pair inside a ```` ``` ```` code fence with example text between | Recorded: behavior must not destroy user content silently | FAIL — see Bug 1 |
| E08 | Markers indented by 4 spaces (indented code block) | Not whole-line matches; treated as user content, preserved; real block appended | PASS |
| E09 | Marker as a substring of a longer line / marker with trailing space | Not matched; preserved as user content | PASS |
| E10 | CRLF file without a block | Block appended (LF); CRLF user bytes preserved as prefix; second run idempotent | PASS |
| E11 | CRLF file whose existing managed block has CRLF line endings | NFR-3 "no duplicate blocks ever": stale governance text must not end up duplicated | FAIL — see Bug 2 |
| E12 | Existing file without trailing newline | Newline added, then separator + block; original bytes still a prefix | PASS |
| E13 | Empty (0-byte) existing file | Block written; rerun idempotent | PASS |
| E14 | Very large file (200k lines, ~12 MB) above and below the block | Completes < 60 s; outside-markers sha256 identical | PASS |
| E15 | 10 concurrent runs against one target | Final state equals a single clean run (one block, byte-identical); run twice | FAIL — see Bug 3 |
| E16 | `--diff` when files are missing | Reports would-be creation, exit 0, nothing written | PASS |
| E17 | No TARGET argument (defaults to `$PWD`) | Operates on the current directory | PASS |
| E18 | Target path containing spaces, with trailing slash | Works; files created in the right place | PASS |
| E19 | File containing only an empty marker pair | Replaced in place with full block; rerun idempotent | PASS |

## Results summary

- Cases run: 32 (6 positive, 7 negative, 19 edge).
- PASS: 29. FAIL: 3 (E07, E11, E15) — each confirmed at least twice.

### Bug 1 (E07) — fenced marker examples are parsed as real markers

`printf` a CLAUDE.md that documents the markers inside a fenced code
block (` ``` ` fence, marker lines at column 0, example text between
them), then run `inject-governance.sh`. The fenced example text between
the documented markers is deleted and the governance block is spliced
inside the user's code fence, corrupting the fence and destroying user
content outside any real managed region. Severity S2 (user content
between documented-example markers is clobbered with exit 0 — PRD FR-2:
"existing content never clobbered"). See the bug report for the exact
repro.

### Bug 2 (E11) — CRLF managed block duplicates governance text

A CLAUDE.md containing the managed block with CRLF line endings (for
example after a Windows editor or `unix2dos` pass over the whole file)
is not recognized (`$0 == begin` never matches `marker\r`), so a second
LF managed block is appended. The file then carries two full governance
texts; NFR-3's "no duplicate blocks ever" AC is violated with exit 0.
Severity S3 (edge-case duplication; stable after the second run, no
user content lost). See the bug report for the exact repro.

### Bug 3 (E15) — concurrent runs corrupt files and can drop user content

`render_managed` reads the target file several times (two `grep` counts,
`markers_paired`, the rewrite `awk`) and then writes with a non-atomic
truncating `cat >"$file"`. Ten parallel invocations against one target
produced, across four trials: duplicate managed blocks in `CLAUDE.md`
(2 marker pairs), an `AGENTS.md` with three interleaved governance
copies inside one marker pair, and one trial where the user's own line
above the block was lost entirely — all with every process exiting 0.
Violates NFR-3 ("no duplicate blocks ever") and the never-clobber
contract. Severity S2. `generate-profile.sh` already solves this with
in-dir `mktemp` + `mv`; `inject-governance.sh` uses `cat >` to preserve
file modes, which is the unprotected window. See the bug report for the
exact repro.

## Cleanup

- `/tmp/sdlc-test-governance-inject/` removed after execution.
- QA clone reset with `git checkout . && git clean -fd`.

## Round 2

Round-1 fixes under test (working tree): CR-tolerant marker matching
(`count_marker_lines` / `norm()` in every awk matcher — Bug 2),
snapshot-once rendering plus atomic `write_managed` (in-target-dir
`mktemp` + `mv -f`, `chmod --reference` on overwrite, umask-derived mode
on create — Bug 3). No fix landed for Bug 1 (fenced markers).

Method unchanged: sandboxes under `/tmp/sdlc-test-governance-inject/`,
NFR-3 verified on every mutating case by comparing sha256 of the
outside-markers content (managed regions stripped CR-tolerantly) before
and after, modulo the documented separator newline on first append.
Every FAIL re-run before recording.

### Round-2 re-runs (highest-risk round-1 cases)

| ID | Re-runs | Scenario | Expected | Result |
| --- | --- | --- | --- | --- |
| R01 | P04 | Stale block between user sections | Replaced in place; outside-markers sha256 identical | PASS |
| R02 | P05 | `--diff` vs apply parity | `--diff` writes nothing; `patch` applying its output reproduces a real run byte-for-byte | PASS |
| R03 | P06 | generate-profile + inject on QA clone, re-run both, then `--refresh` | Second run leaves `git diff` empty; `--refresh` never touches `CLAUDE.md`/`AGENTS.md` | PASS |
| R04 | E01+E02 | Only-BEGIN file, only-END file | Marker line removed, user lines preserved, one fresh block appended | PASS |
| R05 | E03 | Two balanced pairs with user text between | Collapse to first pair's position; user lines byte-preserved | PASS |
| R06 | E07 | Marker pair documented inside a code fence | User content between fenced example markers must survive | FAIL — Bug 1 unfixed, see R2 Bug 1 |
| R07 | E10 | CRLF file without a block | Block appended (LF); CRLF user bytes preserved; second run idempotent | PASS |
| R08 | E11 | Managed block with CRLF endings (unix2dos) | Recognized and replaced in place; exactly one governance copy; CRLF user lines untouched | PASS — Bug 2 fixed |
| R09 | E14 | 200k-line (~12 MB) file around the block | Completes < 60 s; outside-markers sha256 identical | PASS |
| R10 | E15 | 10 concurrent runs, 5 trials | Final state equals one clean run: one block per file, user line intact, no temp litter | PASS — Bug 3 fixed |
| R11 | N04 | Read-only (0444) `CLAUDE.md` needing a change | Round-1 verified contract: non-zero exit, file unmodified | FAIL — see R2 Bug 2 |
| R12 | N05 | Read-only (0555) target dir, files missing | Non-zero exit, no partial file, no temp litter | PASS |
| R13 | N06 | `CLAUDE.md` symlink outside the repo | Exit 1 `refusing to follow symlink`; link target byte-identical | PASS |
| R14 | N07 | `CLAUDE.md` is a directory | Non-zero exit; directory intact; no stray files | FAIL — see R2 Bug 3 |

### Round-2 new cases (targeting the fixes)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| X01 | Mixed endings: first pair CRLF, second pair LF, user text between | Collapse to first pair's position; user lines byte-preserved | PASS |
| X02 | `marker<space>CR` and `markerCRCR` lines | Not matched (only one trailing CR tolerated); preserved as user content; real block appended | PASS |
| X03 | CRLF stale block + 10 concurrent runs, 3 trials | One LF block, CRLF user lines intact, no temp litter | PASS |
| X04 | Temp-file hygiene: normal run, failed run (read-only dir), `--diff` run | Zero `.sdlc-governance.*` files left in target after each | PASS |
| X05 | Mode preservation: 0600 existing file; create under `umask 027` | Overwrite keeps 0600; create yields 0640 | PASS |
| X06 | `--diff` on a CRLF stale block | Exit 0; file sha256 untouched; preview shows in-place replacement (no append) | PASS |
| X07 | Idempotency after CRLF repair | Second run logs `unchanged`; file byte-identical | PASS |
| X08 | CR-only (classic Mac, no LF) file | Treated as block-absent user content, preserved as prefix; second run idempotent | PASS |
| X09 | Stale block whose body (not markers) carries CRLF | Whole region replaced; one governance copy; outside content untouched | PASS |

### Round-2 results summary

- Cases run: 23 (14 re-runs, 9 new). PASS: 20. FAIL: 3 — each confirmed
  twice in fresh sandboxes.
- Bug 2 (CRLF duplicate block) and Bug 3 (concurrent corruption) from
  round 1: fixes verified effective, including the combined CRLF+
  concurrency case (X03).

### R2 Bug 1 (R06, carries over round-1 Bug 1) — fenced marker examples still parsed as real markers

Unchanged from round 1; no fix landed. A CLAUDE.md documenting the
markers inside a ``` fence loses the fenced example text and gets the
governance block spliced into the user's code fence, exit 0. Violates
FR-2 "existing content never clobbered". Severity S2.

### R2 Bug 2 (R11) — regression: read-only managed file is silently rewritten

`write_managed` replaces files via `mv -f` (rename), which needs write
permission only on the directory, so a `chmod 0444 CLAUDE.md` that needs
a change is now rewritten with exit 0 (mode preserved). Round 1 verified
the previous contract on the same tree: write refused, non-zero exit,
file unmodified (N04 PASS). The fix changed user-visible behavior from
refuse to silent overwrite of a file the user marked unwritable.
Severity S3 (degraded edge case, surprising permission bypass; no
content outside markers is lost).

### R2 Bug 3 (R14) — regression: target file that is a directory ⇒ exit 0, temp file dropped inside it

When `CLAUDE.md` is a directory, `render_managed` treats it as a missing
file (`[[ ! -f ]]`), and `write_managed`'s `mv -f "$out_file"
"$TARGET/CLAUDE.md"` moves the temp file INTO the directory
(`CLAUDE.md/.sdlc-governance.XXXXXX`). The script logs `managed block
written` and exits 0, but no governance file exists, every rerun drops
another randomly-named file into the user's directory, and `--diff`
claims the file "would be created". Round 1 verified non-zero exit here
(N07 PASS, `cat > dir` failed). Silent failure with exit 0 on broken
state. Severity S2.

### Round-2 cleanup

- `/tmp/sdlc-test-governance-inject/` removed after execution.
- QA clone reset with `git checkout . && git clean -fd`.

## Round 2 — verification pass (independent re-run)

Independent verification of the committed round-1 fixes, run against the
working-tree `scripts/inject-governance.sh` at commit `ad6497e`.
Sandboxes under `/tmp/sdlc-test2-governance-inject/<case>/`, removed after
the run. NFR-3 checked on every mutating case by comparing the sha256 of
the outside-markers content (managed regions stripped CR-tolerantly)
before and after.

Headline finding: the script ships **no lockfile**. Every `lock`
substring in the source is part of `block`/`blockfile`/`inblock`. The
committed concurrency fix is atomic in-target-dir `mktemp` + `mv -f`
(last-writer-wins) plus snapshot-once rendering — not a lock. The commit
message ("inject-governance takes a lockfile against concurrent runs")
and the round-1 plan's R2 note ("lockfile") therefore describe a
mechanism that does not exist in the code (doc-reality mismatch, see R2V
Bug 4). The atomic-rename mechanism itself is correct and holds under
load.

### Round-2 verification re-runs

| ID | Re-runs | Scenario | Expected | Result |
| --- | --- | --- | --- | --- |
| R2V-01 | R08/E11 | unix2dos CRLF managed block | recognized, replaced in place, one copy, CRLF user lines kept | PASS — Bug 2 fix holds |
| R2V-02 | R10/E15 | 10 concurrent runs, 5 fresh trials | one block per file, user line intact, zero temp litter, matches single clean run byte-for-byte | PASS — Bug 3 fix holds |
| R2V-03 | X03 | CRLF stale block + 10 concurrent runs, 3 trials | one LF block, stale gone, CRLF user lines intact, no litter | PASS |
| R2V-04 | R01/P04 | stale block between user sections | replaced in place, position preserved, outside-markers sha identical | PASS |
| R2V-05 | R04/E01+E02 | only-BEGIN and only-END orphan files | orphan marker line removed, every user line kept, one fresh well-ordered block appended | PASS |
| R2V-06 | R05/E03 | two balanced pairs with user text between | collapse to first pair's position, both stale bodies gone, MID kept, outside sha identical | PASS |
| R2V-07 | E05 (CRLF) | END-before-BEGIN, CRLF endings | `markers_paired` norm() detects unbalanced, marker lines removed, all user content kept, fresh block appended | PASS |
| R2V-08 | R07/E10 | CRLF file without a block | block appended (LF), CRLF prefix byte-preserved, second run idempotent | PASS |
| R2V-09 | X09 | stale block body CRLF, markers LF | whole region replaced, one copy, outside sha identical | PASS |
| R2V-10 | X01 | mixed-ending pairs (CRLF pair + LF pair) | collapse to first position, both stales gone, MIDDLE kept, outside sha identical | PASS |
| R2V-11 | X02 | `markerCRCR` and `marker SPACE CR` lines | only one trailing CR tolerated; malformed lines kept as user content; exactly one fresh block | PASS |
| R2V-12 | X08 | CR-only (classic Mac, no LF) file | treated block-absent, CR-only bytes preserved as prefix, second run idempotent | PASS |
| R2V-13 | X05 | mode preservation across umask 022/027/077/000 | overwrite keeps 0600; create yields 0640/0600/0666 per umask | PASS |
| R2V-14 | X04/X07 | temp hygiene + idempotency | zero `.sdlc-governance.*` after normal/`--diff`; rerun byte-identical, `unchanged` logged | PASS |
| R2V-15 | R02/P05 | `--diff` vs apply parity | `--diff` writes nothing; `patch` applying its output reproduces the real run byte-for-byte | PASS |
| R2V-16 | R03 (seq) | two sequential runs (lock-free serialization) | run2 byte-identical to run1, both files `unchanged` | PASS |
| R2V-17 | R09/E14 | ~200k-line file around the block | completes well under 60 s (0.22 s), outside-markers sha identical | PASS |
| R2V-18 | R13/N06 | `CLAUDE.md` symlink outside repo | exit 1, `refusing to follow symlink`, outside target byte-identical, symlink intact | PASS |
| R2V-19 | R06/E07 | marker pair documented inside a `` ``` `` fence | user example content between the fenced markers must survive | FAIL — Bug 1 carryover (unfixed) |
| R2V-20 | R11/N04 | read-only (0444) `CLAUDE.md` needing a change | round-1 contract: non-zero exit, file unmodified | FAIL — R2V Bug 1 (regression confirmed) |
| R2V-21 | R14/N07 | `CLAUDE.md` is a directory | round-1 contract: non-zero exit, directory intact, no stray files | FAIL — R2V Bug 2 (regression confirmed) |

### Round-2 new probes (targeting the fixes)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| R2V-N1 | symlink to a file *inside* the target | still refused (exit 1), symlink intact | PASS |
| R2V-N2 | `--diff` on a symlinked `CLAUDE.md` | `reject_symlink` fires before preview, exit 1 | PASS |
| R2V-N3 | `AGENTS.md` symlink while `CLAUDE.md` is a normal new file | `CLAUDE.md` written atomically, then die on the symlink, exit 1, symlink target untouched | PASS |
| R2V-N4 | SIGKILL mid-write, 15 timings | managed file never torn (`begin==end` always); a stray temp can remain only because the EXIT trap cannot run on SIGKILL (inherent, matches generate-profile.sh) | PASS |
| R2V-N5 | `CLAUDE.md` is a FIFO (named pipe) | — | FAIL — R2V Bug 2 variant: `[[ ! -f ]]` treats the FIFO as missing, `mv -f` clobbers it into a regular file, exit 0 |
| R2V-N6 | `--diff` when `CLAUDE.md` is a directory | preview should reflect the broken state | FAIL — R2V Bug 2: preview claims "does not exist; it would be created" |
| R2V-N7 | unreadable (0000) `CLAUDE.md` needing a change | non-zero exit, no partial write, no litter | PASS |

### Round-2 verification results summary

- Cases run: 28 (21 verification re-runs, 7 new probes). PASS: 24.
  FAIL: 4 (R2V-19 Bug 1 carryover; R2V-20 / R2V-21 / R2V-N5–N6
  regressions). Each FAIL re-run in a fresh sandbox.
- Bug 2 (CRLF duplicate) and Bug 3 (concurrent corruption) round-1
  fixes: re-verified effective, including the combined CRLF+concurrency
  case and 5+3 fresh concurrency trials with zero defects.
- Both round-1 regressions noted in the prior Round-2 section (read-only
  rewrite, directory clobber) reproduce on the committed code and have
  **not** been fixed; the FIFO and `--diff`-on-directory probes are the
  same `[[ ! -f ]]` root cause.

### R2V Bug 1 (R2V-20) — read-only managed file is silently rewritten (regression)

A `chmod 0444 CLAUDE.md` that needs a change is rewritten with exit 0
(mode preserved at 444), because `write_managed` replaces files via
`mv -f` (rename), which needs write permission only on the directory.
Round 1 verified the opposite contract on the same tree (N04 PASS: write
refused, non-zero exit, file unmodified). No bats test guards N04 after
the fix. Severity minor (surprising permission bypass, no content lost).

### R2V Bug 2 (R2V-21, R2V-N5, R2V-N6) — non-regular-file target ⇒ exit 0 on broken state (regression)

`render_managed` gates on `[[ ! -f "$file" ]]`, so any non-regular file
is treated as "missing". When `CLAUDE.md` is a directory, `mv -f` moves
the temp file *into* it (`CLAUDE.md/.sdlc-governance.XXXXXX`); the script
logs "managed block written" and exits 0, no governance file exists, and
every rerun drops another randomly-named file inside the user's directory
(observed litter 1 → 2). When `CLAUDE.md` is a FIFO, the same path
clobbers the pipe into a regular file (exit 0). `--diff` on the directory
target reports "does not exist; it would be created", contradicting
reality. Round 1 verified non-zero exit here (N07 PASS, `cat > dir`
failed). Severity major (silent failure with exit 0 on a broken state;
litter accumulation; FR-2/NFR-3 contract regressed).

### R2V Bug 3 (R2V-19) — fenced marker examples still parsed as real markers (Bug 1 carryover)

Unchanged from round 1; no fix landed. A `CLAUDE.md` documenting the
markers inside a `` ``` `` fence loses the fenced example text and gets
the governance block spliced into the user's code fence, exit 0. The
documented example "EXAMPLE governance text the user is documenting" is
deleted. Violates FR-2 "existing content never clobbered". Severity
major (silent user-content loss with exit 0).

### R2V Bug 4 (doc-reality) — "lockfile" claim does not match the code

The committed commit message states "inject-governance takes a lockfile
against concurrent runs" and the prior Round-2 plan note repeats the
"lockfile" framing, but the source contains no lock primitive
(`flock`/lockfile/`mkdir` lock). The concurrency safety actually comes
from atomic in-dir `mktemp` + `mv -f` plus snapshot-once rendering. The
mechanism works; only the description is wrong. Severity minor
(documentation/commit-message vs. code mismatch; no runtime impact).

### Round-2 verification cleanup

- `/tmp/sdlc-test2-governance-inject/` removed after execution.
- No QA clone was mutated (all cases used disposable sandboxes).

## Round 3

Independent re-run against the working-tree `scripts/inject-governance.sh`
(branch `feature/php-backend-sdlc-plugin`, after the round-2 fix commit).
Goal: prove every round-1 and round-2 fix HOLDS, attack the concurrency
mechanism the prior rounds called a "lockfile", and re-confirm NFR-3
byte-preservation with sha256 on every mutating case. Sandboxes under
`/tmp/sdlc-test3-governance-inject/<case>/`, removed after the run. Each
result was reproduced; FAILs (none) would be re-run in a fresh sandbox.

Headline: the script ships **no lockfile** (re-confirming R2V Bug 4). A
source grep for `flock`/`lockfile`/`mkdir.*lock`/`.lock` matches only the
`block`/`blockfile` substrings; concurrency safety is the atomic in-dir
`mktemp` + `mv -f` rename plus snapshot-once rendering, which is correct
and holds under load. The "lockfile" framing in the task brief and the
earlier commit message remains a documentation/commit-message vs. code
mismatch (no runtime impact). All three round-1 FAIL bugs (E07 fenced,
E15 concurrency, E11 CRLF) and all four round-2 regressions (read-only,
directory, FIFO, `--diff`-on-directory) are now **fixed and guarded by
bats tests** (23/23 pass).

### Round-3 prior-case re-runs (every round-1 + round-2 case)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| P01 | both files missing | both created, one marker pair each, three sections | PASS |
| P02 | non-empty file, no markers | block appended; original bytes intact prefix | PASS |
| P03 | second run | `unchanged` logged, sha256 identical | PASS |
| P04 | stale block between user sections | replaced in place, position preserved, outside-sha stable | PASS |
| P05 | `--diff` vs apply parity | `--diff` writes nothing; `patch` reproduces real run byte-for-byte (CLAUDE+AGENTS) | PASS |
| P06 | generate-profile + inject on QA clone, re-run both, `--refresh` | second full run byte-stable; `--refresh` never touches CLAUDE/AGENTS | PASS |
| N01 | nonexistent target dir | exit 1, `target directory not found` | PASS |
| N02 | unknown flag `--bogus` | exit 1, names the flag | PASS |
| N03 | target is a regular file | exit 1, `target directory not found` | PASS |
| N04 | read-only (0444) file needing a change | exit 1, file unmodified, no litter — **R2V Bug 1 fixed** | PASS |
| N05 | read-only (0555) dir, files missing | exit 1, no partial file | PASS |
| N06 | symlink to a file outside the repo | exit 1, `refusing to follow symlink`, target byte-identical, link intact | PASS |
| N07 | `CLAUDE.md` is a directory | exit 1, dir intact, zero litter inside — **R2V Bug 2 fixed** | PASS |
| E01 | only BEGIN marker | orphan removed, user lines kept, one fresh block | PASS |
| E02 | only END marker | same repair as E01 | PASS |
| E03 | two balanced pairs, user text between | collapse to first position, both stales gone, outside-sha stable | PASS |
| E04 | three balanced pairs interleaved | collapse to first, all user lines kept, outside-sha stable | PASS |
| E05 | END before BEGIN, balanced | markers removed, user kept, fresh well-ordered block | PASS |
| E06 | nested BEGIN BEGIN END END | corrupt: markers removed, user A/B kept, one block | PASS |
| E07 | marker pair inside a `` ``` `` fence | fenced example survives, fence intact, real block appended outside — **Bug 1 fixed** | PASS |
| E08 | markers indented 4 spaces | treated as content, preserved, real block appended | PASS |
| E09 | marker as substring / trailing space | not matched, preserved as content | PASS |
| E10 | CRLF file without a block | block appended (LF), CRLF prefix preserved, idempotent | PASS |
| E11 | unix2dos CRLF managed block | recognized, replaced in place, one copy, CRLF kept — **Bug 2 fixed** | PASS |
| E12 | file without trailing newline | newline + separator + block; original bytes still prefix | PASS |
| E13 | empty 0-byte file | block written, rerun idempotent | PASS |
| E14 | 200k-line (~13 MB) file around block | completes in 1.9 s (< 60 s), outside-sha identical | PASS |
| E15 | 10 concurrent runs, 5 trials | one block per file, user line kept, zero litter, byte-identical to single run — **Bug 3 fixed** | PASS |
| E16 | `--diff` when files missing | reports would-be creation, exit 0, nothing written | PASS |
| E17 | no TARGET arg | operates on `$PWD` | PASS |
| E18 | target path with spaces + trailing slash | files created in the right place | PASS |
| E19 | empty marker pair only | replaced with full block, rerun idempotent | PASS |
| X01 | mixed-ending pairs (CRLF + LF) | collapse to first, MIDDLE kept, outside-sha stable | PASS |
| X02 | `marker SPACE CR` and `marker CRCR` | only one trailing CR tolerated; malformed lines kept | PASS |
| X03 | CRLF stale block + 10 concurrent, 3 trials | one LF block, CRLF user lines kept, no litter | PASS |
| X04 | temp hygiene (normal, `--diff`, failed run) | zero `.sdlc-governance.*` after each | PASS |
| X05 | mode preservation (overwrite 0600; create umask 027/077) | 0600 / 0640 / 0600 | PASS |
| X08 | CR-only (classic Mac) file | block-absent, CR-only bytes preserved, idempotent | PASS |
| X09 | stale block body CRLF, markers LF | whole region replaced, one copy, outside-sha stable | PASS |
| R2V-N1 | symlink to a file inside the target | refused (exit 1), symlink intact | PASS |
| R2V-N5 | FIFO `CLAUDE.md` | exit 1, FIFO intact, no litter — **R2V Bug 2 variant fixed** | PASS |
| R2V-N6 | `--diff` on a directory target | exit 1, no false "would be created", reflects broken state — **R2V Bug 2 fixed** | PASS |
| R2V-N7 | unreadable (0000) file needing a change | exit 1, no partial write, no litter | PASS |

### Round-3 new probes (lockfile attack surface + fence-fix hardening)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| L01 | lockfile source probe | no `flock`/`lockfile`/`mkdir lock`/`.lock` primitive exists — re-confirms R2V Bug 4 doc mismatch | PASS (no lock; atomic-rename mechanism is the real safeguard) |
| L02 | SIGKILL mid-write, 20 timings | managed file never torn (`begin==end` always), user line never lost | PASS (0/20 torn) |
| L03 | two real processes racing, 50 races | exactly one block/file, no litter, user lines intact | PASS (0/50 bad) |
| L04 | planted stale `.sdlc-governance.*` temps before a run | run ignores foreign temps, writes correct block, stays idempotent (mktemp uses a random suffix) | PASS |
| L05 | 30 SIGKILL-killed runs on one dir | no managed-file corruption; converges to one block on a clean run; SIGKILL temp litter is inherent (EXIT trap cannot run), matches generate-profile.sh | PASS |
| L06 | TARGET dir is a symlink to a real dir | works (only managed *files*, not the target dir, are refused), no litter | PASS |
| L07 | planted `.sdlc-governance.PLANTED` symlink to an outside file | outside file untouched (mktemp picks a random name, never the planted one) | PASS |
| L08 | NFR-3 rigorous: multi-section UTF-8 file (café/日本語), tabs, `$VAR`, quotes | outside-markers sha256 byte-identical, every section + special char preserved | PASS |
| F01 | unclosed (odd) fence around a marker | fence suppression disabled, whole-line fallback, idempotent (no duplicate block) | PASS |
| F02 | tilde `~~~` fenced marker example | example preserved, real block appended, idempotent | PASS |
| F03 | info-string fence (` ```markdown `) | example preserved, idempotent | PASS |
| F04 | real stale block AND a fenced example coexist | fenced example kept, real block replaced in place, idempotent | PASS |
| F05 | stale block body containing a stray fence opener (odd global count) | whole-line fallback replaces the block in place, outside-sha stable, idempotent | PASS |
| F06 | real stale block after an unclosed fenced example | whole-line fallback strips example marker lines, keeps example text, appends one block, idempotent | PASS |
| F07 | doc-only fenced example, no real block | exactly one real block appended, example body kept, idempotent | PASS |
| F08 | `--diff` parity on a fenced-example file | `--diff` writes nothing; `patch` reproduces the real run byte-for-byte | PASS |
| F09 | CRLF fence lines + CRLF markers documenting the block | CRLF fenced example kept, real block appended, idempotent | PASS |

### Round-3 results summary

- Cases run: 60 (43 prior re-runs covering every round-1 + round-2 case,
  17 new probes). PASS: 60. FAIL: 0.
- Prior FAILs re-checked: 7 (round-1 E07/E11/E15 = Bug 1/2/3; round-2
  R2V-20 read-only, R2V-21 directory, R2V-N5 FIFO, R2V-N6 `--diff`-on-dir).
  Prior FAILs now passing: 7 — every one is fixed in the working tree and
  guarded by a dedicated bats case (`tests/inject-governance.bats`, 23/23).
- NFR-3 byte-preservation re-confirmed with sha256 on the outside-markers
  content for every mutating case (P02, P04, E03, E04, E07, E11, E14,
  X01, X09, L08, F04, F05 …) — all identical before/after.
- Concurrency: the "lockfile" the brief asks to attack does not exist; the
  real mechanism (atomic in-dir `mktemp` + `mv -f`, snapshot-once render)
  withstood SIGKILL mid-write (0/20 torn), 50 two-process races (0 bad),
  and 5×10 + 3×10 concurrent trials with zero defects.
- No remaining or fix-introduced bug found.

### Round-3 cleanup

- `/tmp/sdlc-test3-governance-inject/` removed after execution.
- QA clone reset with `git checkout . && git clean -fd` (no push).

## Round 4 (convergence)

Independent convergence re-run against the working-tree
`scripts/inject-governance.sh` (branch `feature/php-backend-sdlc-plugin`,
13853 bytes, unmodified during this round). Goal: prove every round-1,
round-2, and round-3 fix HOLDS and surface any genuine remaining defect.
Sandboxes under `/tmp/sdlc-test4-governance-inject/<case>/`, removed after
the run. QA clone `php-sdlc-qa/php-service-template` used for the
generate-profile sequence (P06) only, then reset with
`git checkout . && git clean -fd` (no push). NFR-3 verified on every
mutating case: the original bytes are confirmed an exact `cmp` prefix or
the outside-markers content is byte-stable; for repair cases the result is
inspected line-by-line (`diff` shows additions only, zero deletions).
Every result was reproduced twice in fresh sandboxes.

Headline: the surface is clean. All 23 dedicated bats cases pass twice
(`tests/inject-governance.bats`). The script still ships **no lockfile**
(re-confirming R2V Bug 4 / the brief's framing); a source grep for
`flock`/`lockfile`/`mkdir.*lock`/`.lock` matches only `block`/`blockfile`
substrings. Concurrency safety is the atomic in-dir `mktemp` + `mv -f`
rename plus snapshot-once rendering, which withstood every adversarial
probe below. No remaining or fix-introduced bug found.

### Round-4 mandated re-runs (every governance-inject case)

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| C-L01 | lockfile source probe | no lock primitive; atomic mktemp+mv is the real safeguard | PASS (re-confirms R2V Bug 4 doc mismatch, no runtime impact) |
| C-N06 | `CLAUDE.md` symlink outside repo | exit 1, `refusing to follow symlink`, target byte-identical, link intact | PASS |
| C-N07 | `CLAUDE.md` is a directory | exit 1, `not a regular file`, dir intact, zero litter inside | PASS |
| C-FIFO | `CLAUDE.md` is a FIFO | exit 1, `not a regular file`, FIFO intact, no litter | PASS |
| C-N04 | read-only (0444) `CLAUDE.md` needing a change | exit 1, `refusing to overwrite read-only`, file unmodified, no litter | PASS |
| C-N05 | read-only (0555) target dir, files missing | exit 1, no partial file, no litter | PASS |
| C-N01 | nonexistent target dir | exit 1, `target directory not found` | PASS |
| C-N02 | unknown flag `--bogus` | exit 1, names the flag | PASS |
| C-N03 | target path is a regular file | exit 1, `target directory not found` | PASS |
| C-P01 | both files missing | both created, one marker pair each, three governance sections | PASS |
| C-P02 | non-empty file, no markers | block appended; original bytes exact `cmp` prefix | PASS |
| C-P03 | second run | `unchanged` logged ×2, sha256 identical | PASS |
| C-P04 | stale block between user sections | replaced in place, position preserved (line 3), outside-sha stable, both user sections kept | PASS |
| C-P05 | `--diff` vs apply parity | `--diff` writes nothing; `patch` reproduces the real run byte-for-byte; preview shows pending block | PASS |
| C-P06 | generate-profile + inject on QA clone, re-run inject, `--refresh` | inject creates one block/file, re-run idempotent (`unchanged`), `--refresh` never touches CLAUDE/AGENTS; original committed content kept as exact prefix; `git diff` 50 insertions, 0 deletions | PASS |
| C-E01 | orphan BEGIN only | marker line removed, user A/B kept, one fresh block | PASS |
| C-E03 | two balanced pairs, user text between | collapse to first position, HEADER/MIDDLE/FOOTER kept, both stales gone, outside-sha stable | PASS |
| C-E05 | END before BEGIN (balanced count) | markers removed, X/MID/Y kept, fresh well-ordered block | PASS |
| C-E07 | marker pair documented inside a `` ``` `` fence | fenced example + both markers survive, fence intact, original bytes exact `cmp` prefix, real block appended outside, idempotent | PASS (Bug 1 fix holds) |
| C-E08 | markers indented 4 spaces | treated as content, indented body kept, real block appended | PASS |
| C-E09 | marker as substring / trailing space | not matched, both kept as content, one real block | PASS |
| C-E11 | unix2dos CRLF managed block round-trip | recognized, replaced in place, exactly one pair, CRLF user lines (top+bottom) kept with CR, outside-content sha stable, idempotent | PASS (Bug 2 fix holds) |
| C-E12 | file without trailing newline | newline + separator + block; original bytes exact prefix | PASS |
| C-E13 | empty 0-byte file | block written, rerun idempotent | PASS |
| C-E14 | ~200k-line (~6 MB) file around the block | completes in 5.3 s (< 60 s), outside-markers sha identical, one pair | PASS |
| C-E17 | no TARGET arg | operates on `$PWD`, one pair | PASS |
| C-E18 | target path with spaces + trailing slash | files created in the right place, one pair | PASS |
| C-X05 | mode preservation (overwrite 0600; create umask 027) | overwrite keeps 600; create yields 640 | PASS |

### Round-4 adversarial-new probes

| ID | Scenario | Expected | Result |
| --- | --- | --- | --- |
| A1 | lock acquired then SIGKILL (stale-lock/temp recovery): 30 kills mid-run × 2 trials, then a clean run | managed file never torn (`begin==end` always), user line never lost, clean run converges to one block, idempotent, no inherent litter observed | PASS (0/60 torn or lost) |
| A2 | two genuinely concurrent processes (background `&`): 40 races × 2 trials | exactly one block per `CLAUDE.md`/`AGENTS.md`, user line intact, zero litter, final state byte-identical to a single clean run | PASS (0/80 bad iterations) |
| A3 | stale planted `.sdlc-governance.STALE*` temps (lock-like) + concurrent runs | one block, user intact, planted foreign temps untouched (mktemp random suffix never collides), idempotent after cleanup | PASS |
| A4 | marker text containing regex metacharacters: user lines with `.* [a-z]+ (foo\|bar)$ ^anchored \d{3}`, `$1.50`, `100%`, `back\reference \1`, a near-marker substring line, and a `begin -->.*`-suffixed line | awk `==` is literal, so metacharacters are never interpreted; the only whole-line marker (an orphan END) is stripped, every regex line preserved (verified line-by-line, additions only), one fresh well-ordered block appended, idempotent | PASS |
| A5 | managed block whose body contains the END marker string as literal content (input counts 1 BEGIN / 2 END = unbalanced) | unbalanced → strip ONLY the exact marker lines, preserve all user body (header/footer/literal-end-body line), append one fresh block, converge to one pair, idempotent | PASS |
| A6 | temp-litter audit across all 4 sandboxes after the full run | zero `.sdlc-governance.*` files remain | PASS (0 left) |

### Round-4 results summary

- Cases run: 34 (28 mandated re-runs covering every governance-inject
  case, 6 adversarial-new probes). PASS: 34. FAIL: 0.
- Prior FAILs re-checked: 7 (round-1 E07 fenced / E11 CRLF / E15
  concurrency = Bug 1/2/3; round-2 R2V-20 read-only, R2V-21 directory,
  R2V-N5 FIFO, R2V-N6 `--diff`-on-dir). All 7 still pass and remain
  guarded by dedicated bats cases — every prior fix HOLDS.
- NFR-3 byte-preservation re-confirmed on every mutating case via exact
  `cmp` prefix, outside-markers sha256, or line-by-line `diff`
  (additions-only) — no user content outside a real managed region was
  ever touched, including the QA-clone integration (`git diff` 50
  insertions, 0 deletions).
- Concurrency / "lock" attack: no lockfile exists; the atomic-rename
  mechanism withstood 60 SIGKILLs mid-write (0 torn), 80 two-process
  races (0 bad), and planted stale-temp recovery with zero defects and
  zero litter.
- One non-defect noted twice during testing was traced to the QA harness,
  not the script: a fence-aware "outside-markers" strip helper reports a
  changed sha for E07 and A3/A4 because it cannot model the post-append
  fence/orphan state; the script's own output is byte-correct (exact
  `cmp` prefix; `diff` shows additions only). Not a bug.

### Round-4 cleanup

- `/tmp/sdlc-test4-governance-inject/` removed after execution.
- QA clone reset with `git checkout . && git clean -fd` (no push).
