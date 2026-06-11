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
