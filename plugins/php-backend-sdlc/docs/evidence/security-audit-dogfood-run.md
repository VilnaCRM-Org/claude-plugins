# security-audit dogfood run — evidence

Evidence that the `security-audit` skill's methodology works, produced by
**dogfooding it on its own PR** (the multi-subagent OWASP red-team → verify →
root-cause-fix → re-verify loop, run against this change set).

## Method (as the skill prescribes)

A red-team workflow fanned out **one subagent per OWASP/vuln family** in
parallel over the change set's executable surface (the plugin's shell scripts:
command-injection, path-traversal/symlink, insecure-temp/TOCTOU, secret-leakage,
SSRF, unsafe-parse/deser) **plus** adversarial review lenses over the new
security content (safety-boundary, generalization, dead-refs/inventory,
contract-quality). Every candidate was then **3-vote, refute-by-default
verified** before promotion to a finding — exactly the "no false positives /
verify by reproduction" rule the skill enforces. Confirmed findings were
fixed at **root cause** (no suppression) and the loop re-run to convergence.

## Round 1 — 4 candidates → 3 confirmed (3/3 votes), all fixed

| # | Family/lens | File | CWE | Severity | Outcome |
| --- | --- | --- | --- | --- | --- |
| 1 | SSRF safety-boundary | `reference/attack-playbooks.md` | CWE-918 | medium | **Fixed** — the SSRF probe named the live cloud instance-metadata endpoint (`169.254.169.254` IMDS) as a target, contradicting the no-exfiltration / in-scope-only boundary. Removed as a target; it now appears only in an explicit prohibition, and the probe uses a benign in-container listener / local IMDS stub. (commit `8cac637`) |
| 2 | contract-quality | `security-audit/SKILL.md` | N/A | medium | **Fixed** — the escalation block used a non-canonical `---SECURITY-AUDIT ESCALATION---` marker the `/sdlc` loop aggregator (which greps `=== SDLC ESCALATION ===`) could not collate. Replaced with the canonical block + 7 standard fields. (commit `8cac637`) |
| 3 | dead-refs/inventory | `skills/AI-AGENT-GUIDE.md` | N/A | low | **Fixed** — stale "only `load-testing/` ships a `reference/` directory" (security-audit ships one too). (commit `8cac637`) |
| — | command-inj / path / temp / secret / unsafe-parse (shell scripts) | `scripts/*.sh` | — | — | **Clean** — no confirmed finding; the scripts' existing hardening (safe `mktemp`, atomic `mv`, symlink refusal, quoted expansion, `--` terminators, fixed-argv `gh`/`git`) held against the red-team. |

A follow-up review pass (CodeRabbit) caught two additional real issues, both
fixed at root cause: a prompt-lint dead-command token (`/sdlc-security`) that
also tripped the toolkit's own real-plugin-clean tests, and a non-executable
`git log -p` in the secret-scan lane (the auditor has no `git` — switched to
filesystem-mode secret scanning). (commit `5cc2736`)

## Round 2 — convergence

The identical red-team workflow was re-run against the fixed change set to
confirm zero new confirmed findings (the skill's "loop until a clean pass"
exit). Result recorded in the PR; the deterministic gates (prompt-lint,
generalization-audit, the toolkit's real-plugin-clean suite) are green.

## Dynamic (live-service) lanes

The skill's dynamic lanes (black-box HTTP/GraphQL probing of a **running**
service) require an authorized target service booted via `make.start` — they
are out of scope for this plugin-internal PR (the plugin ships markdown +
shell, not a runnable PHP service). The `attack-playbooks.md` per-family
**reproduce-against-running-service** steps document the exact dynamic
procedure the plugin's users run against their own authorized service; here the
dynamic lanes correctly **degrade to skip-with-note** (`capabilities.
dynamic_security_testing` absent / `make.start` null), and the **static lanes**
(SAST/taint, dependency, secret, config) plus the content red-team carried the
audit — which is precisely the NFR-3 degrade behavior the skill specifies.

## Boundary observance

Every probe stayed **defensive / authorized**: in-scope local change set only,
no exfiltration, no out-of-profile host, no destructive operation — matching
the skill + agent boundary rules.
