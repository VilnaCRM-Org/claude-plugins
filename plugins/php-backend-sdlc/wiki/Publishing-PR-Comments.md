# Publishing PR Comments

[Home](Home.md) › Deep dives › Publishing PR Comments

`/sdlc-review` runs three review lenses (security, FR/NFR, code quality)
and then, as an optional side effect, publishes what they found onto the
pull request. The poster behind that side effect is
[`scripts/post-review-findings.sh`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/scripts/post-review-findings.sh).
It turns each lens's findings ledger into **one consolidated, idempotent PR
comment per lens**, plus a single **conclusion comment** with cross-lens
counts and the loop duration.

The defining property of this script is its failure mode: it is
**degrade-first**. The capability flag being off, `gh` being absent, no PR
existing, an empty ledger, a malformed read, a mismatched base repo, or a
`gh` write failure all collapse to a logged note and `exit 0`. The poster
is fire-and-forget side output — it NEVER fails the review loop. This is
the deliberate inverse of the sibling
[`get-pr-comments.sh`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/scripts/get-pr-comments.sh)
read, which the finish-pr loop's exit condition depends on, so that one
dies when `gh` is absent. See
[Degrade and Resilience](Degrade-and-Resilience.md) for the full contract.

## 1. What it does

The poster has two modes, selected on the command line:

| Mode | Invocation | Output |
| --- | --- | --- |
| Per-lens | `post-review-findings.sh <lens> [options]` | One findings comment for that lens |
| Conclusion | `post-review-findings.sh --conclusion [options]` | One aggregate comment for the whole loop |

The valid lenses are exactly `security`, `fr-nfr`, and `code-review`. Any
other lens argument is rejected with usage.

### Per-lens comment

A per-lens comment is a Markdown table of the open findings for that lens,
sorted by severity rank (Critical → High → Medium → Low → unknown) and
deduplicated, followed by a one-line summary. The table columns are:

```text
| severity | id | cwe | owasp | location | endpoint | summary |
```

Findings whose `status` is `dropped` are pulled out into a separate
`### Dropped / not reproduced` table (`id`, `location`, `summary`) so the
main table reflects only live findings. The trailing summary line reads,
for example:

```text
_summary: 4 findings (1 critical, 1 high, 2 medium, 0 low); 2 auto-fixed root-cause with regression test._
```

A finding counts as auto-fixed only when `auto_fixed == true` AND a
`regression_test` value is present. If a lens has **zero open
(non-dropped) findings**, `render_lens` returns non-zero and the poster
skips that lens with a note rather than posting an empty table.

### Conclusion comment

The conclusion comment (`--conclusion`) reads all three lens ledgers and
renders three sections:

- **Findings by lens × severity** — a matrix with one row per lens plus a
  bold `**all**` total row, columns `Critical | High | Medium | Low |
  total`. Dropped findings are excluded from every count.
- **Auto-fixed root-cause (with regression test)** — one
  `auto-fixed / total` row per lens.
- **Iterations** and **Duration** — the orchestrator loop iteration count
  and a human-readable elapsed time (e.g. `1h 04m 12s`).

The header titles map the lens slug to a human label:

| Lens slug | Per-lens comment title |
| --- | --- |
| `security` | Security audit |
| `fr-nfr` | BMAD FR/NFR review |
| `code-review` | Code review |

## 2. The ledger record shape

A lens ledger is a single JSON object on disk. `/sdlc-review` writes one
per lens under `${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/` —
`security.json`, `fr-nfr.json`, `code-review.json`. The poster reads it via
`ledger_to_tsv`, which uses `jq` when present and falls back to a `python3`
projection so the rendered body is byte-identical with or without `jq`.

Top-level fields the poster reads:

| Field | Type | Used for |
| --- | --- | --- |
| `lens` | string (required) | Validates the ledger; a missing or non-string lens makes the JSON→TSV projection return `3` internally — per-lens mode then dies (`exit 1`) with `malformed ledger…`, conclusion mode skips that ledger |
| `findings` | array of objects | The rows to render |
| `started_at` | ISO-8601 UTC string | Conclusion duration fallback (min start) |
| `ended_at` | ISO-8601 UTC string | Conclusion duration fallback (max end) |

Each entry in `findings[]` is projected to one TSV line. The recognized
per-finding fields are:

| Field | Meaning |
| --- | --- |
| `severity` | `critical` / `high` / `medium` / `low` (drives sort + counts) |
| `id` | Stable finding id (dedup key for cwe-less lenses) |
| `cwe` | CWE id (security sink-tuple dedup key component) |
| `owasp` | OWASP category |
| `location` | `file:line` of the finding |
| `endpoint` | HTTP/GraphQL endpoint, if applicable |
| `summary` | One-line description |
| `status` | `dropped` routes the row to the dropped table |
| `auto_fixed` | `true` ⇒ counted as auto-fixed (with a regression test) |
| `regression_test` | The proving test; required for the auto-fixed count |

Absent optional fields render as `n/a`. Tabs and newlines inside values
are squashed to spaces to keep the TSV well-formed, and a `|` inside any
cell is escaped (`\|`) so a finding summary cannot inject phantom table
columns.

**Dedup key.** Security-style findings collapse on the sink tuple
`cwe|location|endpoint`, so the same vulnerable sink reported twice yields
one row. A cwe-less finding (FR/NFR or code-review) instead keys on its
unique `id`, so two distinct findings at the same location are NOT merged
away.

## 3. Gating: two flags, both must allow

Publishing is **opt-in and off by default**. Two independent controls
gate it; see [Permissions](Permissions.md) and
[Project Profile](Project-Profile.md).

### `capabilities.publish_pr_comments` (default `false`)

The capability gate is the **first real action** in `main()`, before any
`gh` call — and it is honored even by `--dry-run` and `--json`. The poster
reads `capabilities.publish_pr_comments` from the resolved project profile
(via the `lib/common.sh` helpers `profile_path` and `profile_get`). Only
the literal string `true` opens the gate:

```bash
gate_open() {
  local profile publish="false"
  profile="$(profile_path "$PWD")"
  if [[ -f "$profile" ]] && yaml_parses "$profile"; then
    publish="$(profile_get "$profile" capabilities.publish_pr_comments false)"
  fi
  [[ "$publish" == "true" ]]
}
```

When the flag is not `true` (false, absent, or no profile at all), the
poster logs `capabilities.publish_pr_comments is not true — skipping
publish (opt-in, default off)` and exits 0.

### `make.post_review_findings` (which binary runs)

`/sdlc-review` does not call the bundled script by name. It resolves the
poster from the profile `make` map, using the same null-substitution every
publish step uses: read `make.post_review_findings`, and fall back to the
bundled
[`scripts/post-review-findings.sh`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/scripts/post-review-findings.sh)
when the key is null. A non-null value lets a repo swap in a custom
publisher that honors the same CLI contract:

```bash
profile="$(profile_path)"
POSTER="$(profile_get "$profile" make.post_review_findings "")"
POSTER="${POSTER:-${CLAUDE_PLUGIN_ROOT}/scripts/post-review-findings.sh}"
```

So `make.post_review_findings` chooses **which** poster runs, and
`capabilities.publish_pr_comments` chooses **whether** it publishes.

## 4. Authorization, redaction, degrade-first

Three safety properties hold on every write path.

### Own-repo authorization guard

The poster writes only to the origin/`gh`-resolved repo's OWN PR.
`resolve_repo` derives the slug from `git remote get-url origin` (falling
back to `gh repo view`). Before any write, `authorize` reads the PR's base
repo and refuses to publish unless it matches the resolved slug:

```bash
authorize() {
  local slug=$1 pr=$2 base
  base="$(gh api "repos/$slug/pulls/$pr" --jq .base.repo.full_name 2>/dev/null || true)"
  if [[ -z "$base" ]]; then
    log_warn "...cannot read PR #$pr base repo — refusing to publish"; return 1
  fi
  if [[ "$(lower "$base")" != "$(lower "$slug")" ]]; then
    log_warn "...PR #$pr base repo '$base' != resolved repo '$slug' — refusing (in-scope only)"; return 1
  fi
}
```

A base-repo it cannot read, or one that differs from the resolved repo (a
fork PR pointing elsewhere), is refused — never published.

### Secret redaction before render

`redact` runs a single deterministic `python3` pass over the free-text
fields before they are rendered into the comment body, so a leaked secret
in a finding's `summary` or `location` is never echoed onto the PR. The
shape set, applied specific-first with the high-entropy catch-all last:

| Rule | Catches |
| --- | --- |
| `(AKIA\|ASIA)[0-9A-Z]{16}` | AWS access key ids |
| `eyJ…\.…\.…` | JWTs |
| `gh[pousr]_[A-Za-z0-9]{20,}` | GitHub tokens |
| `(password\|passwd\|secret\|token\|apikey\|api_key)\s*[=:]\s*<8+ chars>` | Keyword-assigned secrets |
| `scheme://user:pass@` | URL basic-auth credentials |
| `[A-Za-z0-9+]{32,}` containing a digit | Bounded high-entropy run |

The high-entropy rule requires a digit so ordinary long identifiers and
path segments are not over-redacted, and the keyword rule requires an
8-char value so prose like `token: expired` is left alone.

### Degrade-first everywhere else

Every other failure on the write path degrades to a `log_warn` and an
exit-0-friendly return: posting identity unresolved, comment list read
failing, create failing (HTTP/rate/abuse), update failing, or a duplicate
that cannot be minimized. All conclusion arithmetic uses the wrap-safe
`common.sh` digit-string helpers (`num_add`, `num_lt`) — never bash
`(( ))` over attacker-influenceable counts — and `human_duration` rejects
a duration string longer than 12 digits rather than risk a wrap.

## 5. Usage

### Per-lens render and publish

```bash
post-review-findings.sh security --pr 42 --file .sdlc/review-ledgers/security.json
```

```bash
post-review-findings.sh code-review --file .sdlc/review-ledgers/code-review.json
```

If `--file` is omitted, the ledger is read from stdin. If `--pr` is
omitted, the PR number is resolved from the current branch via
`gh pr view`.

### Conclusion

```bash
post-review-findings.sh --conclusion \
  --file .sdlc/review-ledgers/security.json \
  --file .sdlc/review-ledgers/fr-nfr.json \
  --file .sdlc/review-ledgers/code-review.json \
  --pr 42 --started-at "$REVIEW_STARTED_AT" \
  --ended-at "$REVIEW_ENDED_AT" --iterations 3
```

Duration is computed in priority order: explicit `--duration-seconds`,
then `--started-at` / `--ended-at`, and finally — if the orchestrator
passed no timing — the min `started_at` / max `ended_at` lexically sorted
from the ledgers themselves (ISO-8601 UTC `Z` strings sort
chronologically). `--conclusion` is mutually exclusive with a lens
argument.

### Inspection flags (no `gh` calls)

| Flag | Effect |
| --- | --- |
| `--dry-run` | Render the comment body to stdout; make ZERO `gh` calls |
| `--json` | Per-lens: emit the `ledger_to_tsv` projection rows as TSV to stdout. With `--conclusion`: identical to `--dry-run` (renders the Markdown conclusion body). ZERO `gh` calls either way |

Both still honor the capability gate first — a closed gate exits 0 before
either prints anything. Use `--dry-run` to preview exactly what would land
on the PR.

### Idempotency marker

Every comment the poster writes is prefixed with a hidden HTML marker so
it can find and **update** its own prior comment instead of spamming a new
one each run:

```text
<!-- sdlc-review:security -->
<!-- sdlc-review:fr-nfr -->
<!-- sdlc-review:code-review -->
<!-- sdlc-review:conclusion -->
```

On each run `publish` lists the PR's comments, collects those whose body
contains the marker AND whose author matches the resolved posting identity
(`--bot-login`, else `gh api user`), edits the oldest match (lowest
numeric id, compared wrap-safe), and minimizes any surplus duplicates as
`OUTDATED`. If the posting identity cannot be resolved, the update path is
disabled and a fresh comment is created — the poster will never edit a
human comment that merely quotes the marker.

## 6. How `/sdlc-review` wires it

The poster is a **post-exit side effect** of
[`/sdlc-review`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc-review.md),
not part of its gate. See [Review and Quality
Gates](Review-and-Quality-Gates.md) and [The SDLC
Loop](The-SDLC-Loop.md) for the surrounding stage.

1. The stage's first action captures
   `REVIEW_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"`. This records the
   loop start for the conclusion comment's duration (FR-10); it has **no
   effect** on the stage exit condition.
2. The review loop runs the multi-lens reviewers and the remediation gate
   until BOTH lenses are clean (zero new FR/NFR findings AND every
   non-skipped quality threshold row PASS). The poster is not invoked
   during the loop.
3. After the loop closes — exit condition met OR escalated — the stage
   captures `REVIEW_ENDED_AT` and posts the conclusion comment **exactly
   once for the whole loop** (never per iteration), resolving the poster
   from `make.post_review_findings` as shown in section 3 and passing the
   three lens ledgers, the captured timing, and the existing
   `iteration <n>/5` counter.

Because the conclusion post sits after the loop and degrades on every
failure, it can never fail the stage or re-enter the review loop.
Ownership is `/sdlc-review` only: a hand-off to
[`/sdlc-finish-pr`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc-finish-pr.md)
does NOT post a second conclusion (FR-10).

## See also

- [Review and Quality Gates](Review-and-Quality-Gates.md)
- [Security Audit](Security-Audit.md)
- [Degrade and Resilience](Degrade-and-Resilience.md)
- [Permissions](Permissions.md)
- [The SDLC Loop](The-SDLC-Loop.md)
