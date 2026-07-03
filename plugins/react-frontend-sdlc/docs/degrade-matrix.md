# Degrade Matrix

What happens when an optional capability is unset or a `make.<key>` maps to
`null` in the [project profile](profile-schema.md). The governing invariant:
**a degrade is always skip-with-an-explicit-note** — the missing lane is
recorded in the run report, the run continues, and it finishes
SUCCESS-WITH-REPORT. A degrade **never silently drops** a check and **never
lowers a `quality.*` threshold**: a floor stays where it is and a fixed `0`
ceiling stays `0`; the lane simply does not execute, so there is nothing to
measure against the unchanged bar. Only iteration guards, the circuit breaker,
and preflight / profile validation ever produce a terminal ESCALATED/HALTED
status (see [Reading the status column](#reading-the-status-column)).

Detection is entirely profile-driven: a `capabilities.<x>: false` (or absent)
flag, or a `make.<key>: null` mapping. The reference repositories in the
VilnaCRM org diverge widely — a React SPA with a full `make.ci` aggregate and
`src/modules`, a Next.js app with no duplication/complexity gates, and a
Storybook-first component library with no bootable app and no aggregate CI
target — so almost every row below is exercised by at least one of them.

## Capability lanes (`capabilities.*`)

Every row is SUCCESS-WITH-REPORT: the paired skill or agent records "capability
absent" and skips its lane. Where a capability pairs with a `make.*` target,
**both** must be present for the lane to run; either one `null`/`false`
degrades the same way.

| Capability                          | Off / absent when                                                          | Degrade behavior (skip-with-note)                                                                                                                                                      | Grounded in                                                                                                                                                                          |
| ----------------------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `capabilities.visual_testing`       | flag `false` or `make.test_visual: null`                                   | `qa-visual-tester` and the frontend-testing-workflow skill skip the Playwright visual-regression pass; the `quality.visual_diffs: 0` ceiling has no lane to evaluate and is not raised | The component library covers visual states through Storybook rather than a routed Playwright app, so it ships `visual_testing: false` while the SPA runs the full lane.              |
| `capabilities.lighthouse`           | flag `false` or `make.lighthouse_desktop` / `make.lighthouse_mobile: null` | the frontend-performance-accessibility skill skips both Lighthouse audits; the `quality.lighthouse_desktop: 95` and `quality.lighthouse_mobile: 85` floors stay put, unmeasured    | A headless component library has no routable page or app shell to audit, so `lighthouse: false`; the SPA audits its auth route on every PR.                                          |
| `capabilities.mutation_testing`     | flag `false` or `make.test_mutation: null`                                 | the frontend-testing-workflow skill skips Stryker and the sharded `make.merge_mutation_reports` re-enforcement; the `quality.mutation_msi` floor is neither run nor lowered            | The Next.js app wires no Stryker config, so `mutation_testing: false`; the SPA runs the sharded matrix plus its merge-and-enforce gate.                                              |
| `capabilities.storybook`            | flag `false` or `make.storybook_build: null`                               | the Storybook story-writing lane in the frontend-component-development skill is skipped with a note                                                                                    | The Next.js app ships no Storybook, so `storybook: false`; the component library is Storybook-first and leaves it `true`.                                                            |
| `capabilities.load_testing`         | flag `false` or `make.test_load: null`                                     | the load-testing skill skips the k6 scenarios                                                                                                                                          | A component library exposes no HTTP endpoints to drive, so `load_testing: false`; the SPA runs k6 against its dev/prod host.                                                         |
| `capabilities.memory_leak_testing`  | flag `false` or `make.test_memory_leak: null`                              | the frontend-testing-workflow skill skips the memlab leak-detection run                                                                                                                | A component library has no multi-page navigation flow for memlab to diff, so `memory_leak_testing: false`.                                                                           |
| `capabilities.figma`                | flag `false`                                                               | the figma-design-check skill skips the design-parity pass                                                                                                                              | A repo with no Figma design source wired (the Next.js app) sets `figma: false`; the SPA pins Figma node ids.                                                                         |
| `capabilities.observability`        | flag `false`                                                               | the observability-instrumentation skill skips the web-vitals / RUM wiring pass                                                                                                         | The reference SPA profile itself ships `observability: false` — the annotated example proves the default-off path; a repo that wires web-vitals sets it `true`.                      |
| `capabilities.accessibility_audit`  | flag `false` (see the note below on `make.a11y`)                           | the `accessibility-auditor` **static** lane (axe-core / ARIA / semantic checks via the accessibility-audit skill) is skipped with a note; no a11y threshold is invented or relaxed     | A repo that has not opted into the a11y gate leaves it `false` (the default); the SPA turns it on.                                                                                   |
| `capabilities.dynamic_a11y_testing` | flag `false` **or** `make.start: null`                                     | only the **dynamic** (live-browser) probing in `accessibility-auditor` degrades to skip-with-note; the static a11y lane still runs over source                                         | The component library has no bootable app dev server (`make.start: null` — components render only in Storybook), so live probing cannot attach; the static axe/ARIA lane still runs. |
| `capabilities.publish_pr_comments`  | flag `false` (the default)                                                 | the Publish step of `/fe-sdlc-review` and the `post-review-findings.sh` write path skip-with-note; findings are still computed and listed in the run report, just not posted to the PR | The reference SPA profile ships `publish_pr_comments: false` (opt-in); publishing is enabled per-repo, never by default.                                                             |

`capabilities.accessibility_audit` gates the static lane and pairs with
`make.a11y`; `make.a11y: null` does **not** disable the lane — it swaps the
target for the plugin's bundled a11y lane (see the substitution table below).
The flag is what turns the static lane off.

## Optional `make` targets (`make.<key>: null`)

These `null` mappings are the largest source of cross-repo divergence.

| Target              | `null` when                           | Degrade behavior (skip-with-note)                                                                                                                                                                                                                                  | Grounded in                                                                                                                                           |
| ------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `make.ci`           | no aggregate CI target exists         | `/fe-sdlc-qa` and the ci-workflow skill fan out to the mapped sub-targets (`make.lint`, `make.lint_eslint`, `make.lint_tsc`, `make.format`, `make.test_unit_client`, …) in sequence instead of one aggregate, noting the aggregate is absent — no check is dropped | The component library defines no `ci` target (it uses a format-check plus a single test-unit lane), so `make.ci: null`; the SPA has a full `make ci`. |
| `make.lint_dup`     | no jscpd gate configured              | the frontend-quality-workflow skill skips the copy/paste duplication gate with a note; the `quality.jscpd_clones: 0` ceiling is not raised — there is simply no lane; the rest of `make.lint` still runs                                                           | The Next.js app configures no jscpd gate, so `make.lint_dup: null`; the SPA enforces it.                                                              |
| `make.lint_metrics` | no rust-code-analysis gate configured | the frontend-quality-workflow skill skips the complexity gate with a note; `quality.metrics_enforced` stays `true` but there is no lane to run; the rest of `make.lint` still runs                                                                                 | The Next.js app configures no rust-code-analysis gate, so `make.lint_metrics: null`; the SPA enforces the hard-fail metrics policy.                   |

## Review-machinery substitution (bundled `scripts/*`)

These five targets ship a **`null` default in every repo** and are the one
case where `null` is not a capability loss: the plugin substitutes its own
bundled implementation, so the behavior is fully provided. The note in the run
report records the substitution, not a skip.

| Target                      | `null` default substitutes                                                          | Provided by                                                                                                |
| --------------------------- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `make.ai_review_loop`       | `scripts/ai-review-loop.sh`                                                         | the bundled AI review loop that drives `/fe-sdlc-review`                                                   |
| `make.pr_comments`          | `scripts/get-pr-comments.sh`                                                        | the PR-comment listing consumed by `pr-comment-resolver`                                                   |
| `make.fr_nfr_gate`          | `scripts/fr-nfr-gate.sh`                                                            | the FR/NFR gate backing `fr-nfr-reviewer`                                                                  |
| `make.post_review_findings` | `scripts/post-review-findings.sh`                                                   | the PR-comment publisher (write path gated by `capabilities.publish_pr_comments`)                          |
| `make.a11y`                 | the plugin's bundled a11y lane (axe-core / Playwright a11y probing + static checks) | `accessibility-auditor`, gated by `capabilities.accessibility_audit` / `capabilities.dynamic_a11y_testing` |

All five share `scripts/lib/common.sh`. A repo that owns a first-class Make
target for any of these can map the key to it; the substitution is only the
`null` fallback.

## Reading the status column

- **SUCCESS-WITH-REPORT** — every degrade above. The run continues to
  completion and the final run report lists each degrade note taken along the
  way, so a skipped lane is always visible, never silent.
- **ESCALATED / HALTED** — terminal states, and none of them come from a
  degrade. Only iteration guards, the circuit breaker, and preflight /
  `validate-profile.sh` failures halt or escalate a run; those live in the
  [SDLC loop](sdlc-loop.md), not in this matrix.
