# Security Audit

[Home](Home.md) › Deep dives › Security Audit

The plugin's **adversarial security lens**: an authorized, multi-subagent
red-team loop that drives an authorized PHP backend you own to **zero new
verified security findings**. It is offensive technique applied to a defensive
purpose — a repo owner penetration-testing their own running service — and it
is enforced by four hard boundary rules, capability degrade gates, and a
no-false-positive culture.

This page is grounded in the
[`security-audit` skill](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/security-audit/SKILL.md),
the
[`security-auditor` agent](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/agents/security-auditor.md),
and the
[security-audit test strategy](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/testing/security-audit-test-strategy.md).

## What it is

The security lens is one **skill** (`security-audit`) that owns a bounded loop,
plus one **agent** (`security-auditor`) that the loop fans out — one instance
per OWASP/vuln family, in parallel. The skill is the orchestrator; the agent is
a find/verify-only red-team unit. The skill body contains **no Task-tool call**
— it prescribes the fan-out as text, and whichever orchestrator loaded it (the
`/sdlc-review` agent, or a standalone invocation that holds the `Task` tool)
issues the dispatches.

The division of labour is deliberate and strict:

| Component | Owns | Never does |
| --- | --- | --- |
| `security-audit` skill | the loop (triage → fan-out → aggregate → fix → re-verify), dedupe, fix routing, publish | probe, verify, or edit code itself |
| `security-auditor` agent | one family's SAST + dynamic probing, candidate verification | wander to other families; edit code; call `php-implementer` |
| `php-implementer` agent | every root-cause fix + regression test | (receives `{location, remediation, regression_test}` from the orchestrator) |

The auditor's tool surface is intentionally `Bash, Read, Glob, Grep` — there is
**no `Edit`/`Write`**, so a finding cannot be fixed inside the agent. Verified
findings route to `php-implementer` through the orchestrator. The auditor is
grey-box by design: it MAY read source (unlike `qa-manual-tester`) to taint-trace
a candidate to its sink, but a finding is real **only** when reproduced against
the running service.

### Two entry points, one identical body

| Entry point | How it starts | Role |
| --- | --- | --- |
| **Inside `/sdlc-review` triage** | The Stage-4 review gate's applicability triage records an EXECUTE / NOT-APPLICABLE verdict for it like every other skill. | The adversarial counterpart to the quality lens (`code-quality-reviewer`) and the spec lens (`fr-nfr-reviewer`). |
| **Standalone** | Invoked directly as `php-backend-sdlc:security-audit` against an authorized target. | An on-demand red-team / pen-test / vuln-hunt run. |

There is **no dedicated security slash-command** — the command surface stays at
8 ([Commands](Commands.md)). The security lens runs inside
[`/sdlc-review` triage](Review-and-Quality-Gates.md) or standalone, never as its
own command.

## The loop

The canonical loop is `triage → fan-out → find → verify → fix → regress →
re-verify → loop`, bounded by `MAX_ITERATIONS=5`. Every enumeration (OWASP
families, per-family probes, remediations) lives in a `reference/` file beside
the skill, never inline, so the skill body stays small.

| Step | Stage | What happens |
| --- | --- | --- |
| 5.1 | **Triage** | Read `reference/owasp-catalog.md` and record a per-family verdict — **PROBE** or **N/A-with-reason** — for the entire corpus. 100% triaged, no silent skips. N/A families are excluded **before** fan-out to control token cost. |
| 5.2 | **Fan-out** | Boot the service (when dynamic testing is in scope) via `make.start`, capture its in-scope base URL and runtime env, then dispatch one `security-auditor` per PROBE family in parallel — N `Task` dispatches in one turn. |
| 5.3 | **Find → verify** | Each auditor runs SAST/dep/secret/config analysis **and** adversarial dynamic probing. A static result is a *candidate*, never a finding, until reproduced against the running service. |
| 5.4 | **Aggregate / dedupe / promote** | The orchestrator collects N reports, dedupes by `(CWE id, sink file:line, exploited endpoint)`, promotes only reproduced candidates, and orders them Critical → Low. |
| 5.5 | **Fix → regression-test** | Each verified finding routes to `php-implementer` with its `{location, remediation, regression_test}` slice. Every fix is root-cause and secure-by-default and ships a failing-then-passing regression test. |
| 5.6 | **Re-verify → loop** | Re-dispatch **only still-open families** (the set shrinks each iteration). The affected family's auditor re-verifies its reproduction no longer succeeds. Exit on the first iteration with zero new verified findings. |
| 5.7 | **Publish (gated)** | When `capabilities.publish_pr_comments` is true, project the promoted records to `${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/security.json` and publish one idempotent PR comment. |

The loop's control flow, restated from the skill:

```text
iteration ← 1
loop:
  dispatch security-auditor for each still-open PROBE family (parallel)   # 5.2
  collect + dedupe + promote verified findings                            # 5.4
  if zero new verified findings: exit SUCCESS-WITH-REPORT                 # exit
  route each finding → php-implementer (root-cause fix + regression test) # 5.5
  affected-family re-verify                                               # SA-6
  iteration ← iteration + 1
  if iteration > 5  OR  php-implementer / Ralph breaker tripped:
     emit canonical escalation block; STOP (never auto-reset the breaker)
final: run the make.ci target once; forbidden-suppression scan; emit report
```

`make.ci` runs **once at loop close**, not per iteration — the per-iteration
correctness signal is the affected-family reproduction; the final `make.ci` is
the safety net. On `iteration > 5`, or on a tripped `php-implementer` / Ralph
circuit breaker, the loop emits the canonical escalation block and stops — it
**never auto-resets a breaker**. See
[Degrade and Resilience](Degrade-and-Resilience.md) for the breaker contract.

### Dispatchable families

Each PROBE family becomes one parallel auditor. The family set, primary OWASP
id, and profile gate are derived from `reference/owasp-catalog.md`:

| Dispatch family | Primary OWASP id | Profile gate |
| --- | --- | --- |
| BOLA / IDOR | API1:2023 / A01:2021 | always |
| BOPLA / mass-assignment | API3:2023 | always |
| BFLA | API5:2023 / A01:2021 | always |
| Injection — SQLi/DQL/NoSQL | A03:2021 | always (NoSQL operator injection when `persistence.mapper` is `doctrine-odm`) |
| SSTI | A03:2021 | always |
| Insecure deserialization | A08:2021 | always |
| SSRF | A10:2021 / API7:2023 | always |
| Auth / session | A07:2021 / API2:2023 | always |
| Security misconfiguration | A05:2021 / API8:2023 | always |
| Vulnerable / outdated deps | A06:2021 | always |
| Cryptographic failures / secrets | A02:2021 | always |
| File upload | A08:2021 (integrity) | upload surface exists |
| Rate / resource exhaustion | API4:2023 | always |
| GraphQL (introspection / deep-query / batching) | API4:2023 / API1:2023 | `framework.graphql: true` only |
| LLM Top 10 | LLM01:2025 … LLM10:2025 | LLM usage detected only |

Excluded before fan-out and recorded N/A-with-reason: OWASP Mobile (all
editions), the memory-safety CWEs (managed PHP runtime), and the LLM family
when no LLM usage is detected.

### Runtime env matters

The orchestrator captures and reports the booted runtime env (e.g. `APP_ENV`)
alongside the base URL. A fuzz/test/CI env that disables security middleware
(rate limiter), or enables debug/verbose errors and GraphQL introspection, will
**mask or inflate** env-sensitive families — rate / resource exhaustion can read
falsely CLEAN, while error-disclosure (CWE-209) and introspection can read
falsely as findings. So the env is passed in every dispatch, and a family whose
verdict depends on an env-toggled control must cross-check the prod/dev config
source before reporting CLEAN or promoting a finding. A prod/dev-like profile is
preferred for the dynamic pass when one exists.

## The four hard boundary rules

These are a **hard contract**, restated verbatim in both the skill and the
agent, and enforced at the Allowed-actions / Constraints level — a forbidden
action, not advisory prose. Every action in the loop is bound by all four:

1. **In-scope target only (verified, not assumed)** — probe ONLY the
   profile-resolved local service (the base URL of the `make.start`-booted
   service). BEFORE any dynamic probe, verify the target host resolves to
   loopback (`127.0.0.0/8`, `::1`), an RFC1918/private range (`10.0.0.0/8`,
   `172.16.0.0/12`, `192.168.0.0/16`, `fc00::/7`), or a known
   container/compose network name. If it does not, **refuse** — skip dynamic
   probing with a note and record a boundary-violation. Never probe a public,
   remote, or third-party host even if one is supplied in the dispatch.
2. **No exfiltration** — never copy data, secrets, or credentials out of the
   disposable container instance.
3. **Mutate via the API only** — change state only through the service's own
   API; no out-of-band datastore writes to force a reproduction.
4. **Container-only, no destructive non-API operations** — run through `make`
   / `docker compose exec php`, never host binaries; use the minimal payload
   needed to prove a vuln on a disposable instance.

The auditor's allowed `Bash` surface is correspondingly narrow: the
`make.security` suite (or the bundled static lane), `curl`/`jq` and GraphQL
POSTs against the profile-resolved base URL only, and read-only container
introspection. Forbidden without exception: any file write/edit, any git
command, host-level `php`/`composer`/`vendor/bin/*`, package installs on the
host, probing an out-of-profile host, exfiltration, out-of-band datastore
mutation, and any destructive non-API operation. (`semgrep`
`SEMGREP_APP_TOKEN` hook errors in command output are environmental noise, not
findings.)

## Degrade gates

Every degrade completes the stage **SUCCESS-WITH-REPORT** — never a loop, never
a hard-fail. Static/SAST lanes keep running even when dynamic probing is off.

| Condition | Behavior |
| --- | --- |
| `make.security: null` | Run the bundled static lane directly through the container — `make.psalm` with `--taint-analysis`, Semgrep, `composer audit`, secret-scan. Adds no dynamic dependency. |
| `capabilities.dynamic_security_testing: false` **OR** `make.start: null` | Dynamic probing is skipped with a note; static/SAST/dep/secret/config lanes still run. No base URL is passed; never improvise a host boot command. |
| Base URL stays unreachable | Same as above — dynamic probing skips with a note, static lanes run. |
| `framework.graphql: false` | The GraphQL family is recorded N/A-with-reason and not dispatched. |
| LLM Top 10 family | PROBE only when LLM usage is detected (composer deps, `clean-architecture-llm` artifacts in `architecture.source_root`, or an explicit profile signal); otherwise N/A-with-reason. |
| Assigned family N/A for target | Memory-safety/Mobile CWEs against a PHP backend record an explicit N/A-with-reason verdict; no probe, no fabricated finding. |
| SAST lane tool unresolvable | That lane degrades with a note; remaining lanes run. |
| Bundled-lane / probe command fails for environmental reasons | Retry once within the iteration; on second failure, record the raw error in the degrade notes (recommended fix: restore `make.security` or map it to null) and continue. A genuine reproduced vuln is a FINDING, never a degrade. |

Under static-only mode the no-false-positive rule still holds: the two
static-only classes — a committed secret (CWE-798) and a vulnerable pinned
dependency — are promotable by a **deterministic in-tree demonstration** (the
secret present and live-shaped; the pinned version inside a known-vulnerable CVE
range). Every other SAST candidate that cannot be reproduced stays
downgraded/dropped, never promoted on source evidence alone. See the
[degrade matrix](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md).

## Finding-record schema and run report

A verified finding is the single hand-off shape: emitted by each auditor,
deduped/promoted by the orchestrator, and consumed by `php-implementer`. Each
finding carries a reproduction, a CWE id, an OWASP id, and a severity
band-with-rationale (a full CVSS vector is optional, never mandated).

```text
FINDING <family-id>-<n>
  cwe: CWE-<id>                           # mapped from reference/owasp-catalog.md
  owasp: <A0X:2021 | APIx:2023 | LLMxx>   # edition-labelled id
  severity: Critical|High|Medium|Low      # band + one-line rationale (CVSS vector optional)
  location: <architecture.source_root>/<path>:<line>   # the sink, profile-resolved (no literals)
  endpoint: <METHOD> <path>               # the exploited surface
  reproduction:
    1. <exact container/curl command>     # copy-pasteable against a freshly
    2. <exact command>                    #   booted disposable instance
  expected: <secure behavior>   observed: <vulnerable behavior>
  remediation: <vetted library/primitive + cited OWASP cheat sheet>
  regression_test: <test path the fix must add>        # failing-before / passing-after
```

`php-implementer` receives `{location, remediation, regression_test}`, produces
the root-cause fix plus the failing-then-passing test, and the affected-family
auditor re-verifies the reproduction no longer succeeds. A candidate with no
working reproduction is recorded **downgraded/dropped**, never reported — the
auditors enforce this and the orchestrator is the second gate.

At loop close the orchestrator emits a run report:

```text
SECURITY-AUDIT RUN REPORT
  per-family verdict table: <family> → PROBE | N/A (<reason>)
  per-iteration finding counts: iter 1: <n> … iter k: <n>
  iterations used: k / MAX_ITERATIONS=5
  promoted findings: <count by severity band>
  dropped candidates: <count> (non-reproducible)
  make.ci: <PASS|FAIL>   forbidden-suppression scan: <CLEAN|VIOLATION>
  status: SUCCESS-WITH-REPORT | ESCALATED
```

On a `MAX_ITERATIONS=5` breach or a breaker trip, the loop instead emits the
canonical escalation block (`stage`, `iteration`, `exit_condition`,
`blocking_finding`, `iteration_log`, `recommended_action`) and stops.

### No suppression, ever

Fixes are root-cause only. The loop never adds a suppression/ignore annotation,
a baseline, a config relaxation, a threshold reduction, or a `deptrac.yaml`
edit to make a finding disappear — thresholds are raise-only; fix the code. At
loop close the diff is scanned for forbidden suppressions (the
[`code-review` skill](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/code-review/SKILL.md)
Step 6 scan) before success is declared.

## Authorized / defensive use only

This skill exercises offensive technique for a **defensive purpose**: a repo
owner auditing their own service. It is for red-teaming, security-auditing,
penetration-testing, vuln-hunting, or threat-modeling an **authorized** PHP
backend. The boundary rules above make that scope a checkable invariant rather
than a promise — the in-scope host check is verified before every dynamic probe,
and an out-of-scope host is refused even when supplied in the dispatch.

The detection contract is validated by a two-lane test campaign: a deterministic
**static lane** (semgrep/SAST signatures, CI-gating) and a nondeterministic
**judge lane** (an LLM under the auditor contract, for logic families no static
rule can reach — BOLA/IDOR, BFLA, BOPLA, auth, rate). See
[Testing and Validation](Testing-and-Validation.md) and the
[security-audit test strategy](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/testing/security-audit-test-strategy.md)
for the coverage matrix and the dogfood evidence runs.

## See also

- [Review and Quality Gates](Review-and-Quality-Gates.md)
- [Agents](Agents.md)
- [Skills](Skills.md)
- [Degrade and Resilience](Degrade-and-Resilience.md)
- [Publishing PR Comments](Publishing-PR-Comments.md)
