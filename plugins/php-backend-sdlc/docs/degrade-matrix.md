# Degrade Matrix

What happens when an external capability is missing or a safety limit
fires (architecture §8). The governing rule (NFR-4): **degrade paths
never loop and never hard-fail the run** — only guards, breakers, and
preflight produce ESCALATED/HALTED. Capability detection lives in the
[project profile](profile-schema.md) (`make.<key>: null`,
`ci.provider: null`, `review.coderabbit: false`).

| Condition | Detected by | Behavior | Status |
| --- | --- | --- | --- |
| No CodeRabbit / reviewer app | `review.coderabbit: false` | `ai-review-loop.sh` is the comment source for stage 6 | SUCCESS-WITH-REPORT |
| Missing make target | profile `make.<key>: null` | skill/agent records "capability absent", skips that check | SUCCESS-WITH-REPORT |
| No CI workflows | `ci.provider: null` / zero checks on PR | ci-fixer skip-with-report | SUCCESS-WITH-REPORT |
| Ralph circuit breaker open | `---RALPH_STATUS---` / breaker files | stop stage 3, escalation report, never reset, honor cooldown | ESCALATED |
| Guard breach (any stage) | iteration counter = 5 | canonical escalation block, run halts | ESCALATED |
| Preflight FAIL / profile invalid | setup-preflight / validate-profile | abort before stage 1 with named remediation | HALTED |
| `claude -p` non-zero / malformed JSON | ai-review-loop.sh | retry once, then count as failed iteration (never infinite) | per-loop |
| Permission denial mid-loop | non-interactive `claude` error output | surface verbatim in escalation report; point to [permissions](permissions.md) | ESCALATED |

## Reading the status column

- **SUCCESS-WITH-REPORT** — the run continues and finishes; the final
  run report lists every degrade note taken along the way.
- **ESCALATED / HALTED** — terminal; the run report embeds the failing
  stage's escalation block (see [the SDLC loop](sdlc-loop.md)).
- **per-loop** — handled inside the owning loop's iteration budget,
  invisible at run level unless the budget is exhausted.
