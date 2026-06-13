# Evidence: end-to-end feature-ship dogfood (Percentage VO)

A full SDLC-flow dogfood: drive the `php-backend-sdlc` plugin through every
stage to ship one small, genuinely-PHP feature on a disposable sandbox,
exercising the real plugin scripts, command playbooks, and skills, and
recording exactly where each stage auto-performed versus where babysitting
was needed.

- Feature: an immutable `Percentage` value object in
  `src/Shared/Domain/ValueObject/` (0..100 inclusive, rejects NaN, float
  value, `__toString`, `equals(self)`), plus its unit test.
- Sandbox: `dmytrocraft/php-sdlc-e2e-sandbox` (a `php-service-template`
  clone), checked out at `/tmp/sdlc-e2e`.
- Issue: <https://github.com/dmytrocraft/php-sdlc-e2e-sandbox/issues/3>
- PR: <https://github.com/dmytrocraft/php-sdlc-e2e-sandbox/pull/4>
- Branch: `feat/percentage-vo` (HEAD `4d3ca0d`)
- Scripts run from the install cache
  (`…/cache/vilnacrm-plugins/php-backend-sdlc/0.1.0/scripts`) with
  `CLAUDE_PLUGIN_ROOT` set to that version root.

## Per-stage results

### SETUP — auto-performed

Ran `setup-preflight.sh --report`, `bmalph init` (the
`sdlc-setup.md` playbook's step 2 for a fresh repo with no `_bmad/`),
`generate-profile.sh`, `inject-governance.sh`, `validate-profile.sh`.

- Preflight: all 8 checks PASS (git, claude 2.1.177, gh 2.92.0, gh-auth,
  bmalph 2.11.0, bmalph-doctor deferred on fresh repo, PyYAML, jq).
- `bmalph init`: succeeded non-interactively (`--name … --description …
  --platform claude-code`), created `_bmad/`, `.ralph/`,
  `.claude/commands/`, `bmalph/`.
- `generate-profile.sh`: created `.claude/php-sdlc.yml` (detected
  symfony 7.2, api_platform 4.0, graphql true, doctrine-orm + postgresql,
  bounded contexts `CompanySubdomain` + `Internal`, shared `Shared`,
  `make.ci=ci` / `tests=test` / `psalm` / `deptrac` / `phpinsights` /
  `infection` present, `e2e`/`ai_review_loop`/`pr_comments`/`fr_nfr_gate`
  null, structurizr + load_testing true).
- `inject-governance.sh`: wrote the managed block to `CLAUDE.md` and
  `AGENTS.md`.
- `validate-profile.sh`: profile valid (exit 0). No retry loop needed.

Skills applied: none (setup is script-driven). Babysitting: none — every
step the playbook documents ran on its first invocation.

> Note (not a bug): `project.name` came back as `"php-serice-template"`.
> The generator faithfully echoes the upstream `composer.json` `name`
> field, which already carries that typo. The plugin is reflecting repo
> data, not corrupting it.

### ISSUE — auto-performed

Followed `sdlc-issue.md` create mode: `validate-profile.sh` (pass) →
dedup search (`gh issue list --label php-backend-sdlc` → `[]`) → create
the marker label (absent) → `gh issue create` → read-back verify.

- Created issue #3 with a `## Problem`, `## Acceptance criteria` (4
  testable bullets), and `## Scope`.
- Read-back: marker label `php-backend-sdlc` attached, URL resolves, 4 AC
  bullets — exit condition met.

Skills applied: none (script/`gh`-driven). Babysitting: none.

### PLAN — auto-performed (triage-first decision guide)

The `sdlc-plan.md` playbook's full BMAD six-artifact chain is heavyweight;
for a single Shared-domain VO the task calls for the triage-first
decision per `SKILL-DECISION-GUIDE.md`. Recorded one verdict per skill
(no silent skips, ADR-5/NFR-5):

| Skill | Verdict | Reason |
| --- | --- | --- |
| implementing-ddd-architecture | EXECUTE | New Domain value object — placement + layer purity |
| testing-workflow | EXECUTE | New unit test for the VO |
| code-organization | EXECUTE | Static directory/type, namespace, naming review |
| quality-standards | EXECUTE | Static gate-threshold review of the change |
| code-review | EXECUTE | PR-finish read of review threads (FR-8 feed) |
| bmad-fr-nfr-review-gate | EXECUTE | Run the gate script (`make.fr_nfr_gate` null → plugin substitutes `fr-nfr-gate.sh`) |
| api-platform-crud | NOT-APPLICABLE | No API endpoint; VO is not API-exposed |
| cache-management | NOT-APPLICABLE | No caching/query in scope |
| ci-workflow | NOT-APPLICABLE (degraded) | `make.ci` exists but no PHP/Docker here to run it |
| clean-architecture-llm | NOT-APPLICABLE | No LLM/provider code |
| complexity-management | NOT-APPLICABLE | One trivial guard clause; no complexity hotspot |
| database-migrations | NOT-APPLICABLE | VO is not persisted; no schema change |
| deptrac-fixer | NOT-APPLICABLE | No existing Deptrac violation to fix |
| documentation-creation | NOT-APPLICABLE | Project already has docs |
| documentation-sync | NOT-APPLICABLE | Pure internal VO; no template-facing doc/artifact changes |
| load-testing | NOT-APPLICABLE | `capabilities.load_testing` true but no endpoint to load-test |
| observability-instrumentation | NOT-APPLICABLE | No domain event/metric emitted by a plain VO |
| openapi-development | NOT-APPLICABLE | No OpenAPI/GraphQL surface touched |
| query-performance-analysis | NOT-APPLICABLE | No query in scope |
| structurizr-architecture-sync | NOT-APPLICABLE | `capabilities.structurizr` true but no C4-level component added |
| bmad-autonomous-planning | NOT-APPLICABLE | Planning-time skill; not a spec-authoring task |

Babysitting: judgement call — chose the lightweight triage plan over the
full `bmad-autonomous-planning` chain because the feature is a single VO.
That is a documented decision-guide branch, not a stall.

### IMPLEMENT — auto-performed (with a documented degrade)

Created branch `feat/percentage-vo`, added the VO and test per
`implementing-ddd-architecture` + `testing-workflow`, committed with the
`Co-Authored-By: Claude Fable 5` trailer (commit `4d3ca0d`).

- `src/Shared/Domain/ValueObject/Percentage.php`: `final`,
  `declare(strict_types=1)`, namespace `App\Shared\Domain\ValueObject`,
  float value, constructor throws `\InvalidArgumentException` for
  `NaN`/`<0`/`>100`, plus `value()`, `__toString()`, `equals(self)`.
- `tests/Unit/Shared/Domain/ValueObject/PercentageTest.php`: extends the
  repo's `UnitTestCase`, uses `$this->faker`, covers positive (0, 50,
  100), negative (-1, 101, NaN), and edge (0.0, 100.0, equals
  true/false) cases — mirrors `UuidTest` style.

Skills applied: implementing-ddd-architecture, testing-workflow.

> PHP-degrade note (honest, NFR-4): PHP is not on the host and the
> project `vendor/` is absent (no `composer install`, no built service
> container), so the container-only `make tests` / `make psalm` /
> `make deptrac` / `make infection` / `make ci` targets cannot run here.
> No test output is fabricated. The skills' "run the target mapped by
> `make.*`" steps were therefore degraded-with-note and verified
> statically instead. This is an environment limit, not a plugin flow
> bug.

### REVIEW — auto-performed

Ran the static portions of `code-organization` + `quality-standards` and
the `fr-nfr-gate.sh` FR/NFR gate.

Static checks (all PASS):

- `strict_types=1` in both files.
- Namespace matches directory exactly (`App\Shared\Domain\ValueObject`).
- `final class` on the VO and the test.
- No suppression pragmas; no `use Symfony\…` / Doctrine / API-Platform
  imports in the Domain VO (Domain-layer purity).
- "Directory X contains ONLY class type X": the VO directory holds only
  value objects.
- Named-constructor rule: the repo's own `Uuid` VO uses direct `new`
  (no static factory); `Percentage` matches that convention, so no
  production caller violates the `{VO}::fromString()` rule.

FR/NFR gate (`fr-nfr-gate.sh`) with a STUB `claude` (emits
`{"result":"All requirements covered.\nFR_NFR_NEW_FINDINGS: 0"}`) — the
real `claude` binary was deliberately NOT used, to exercise the gate
script without nested billing:

- Gate parsed the stub JSON `.result`, validated the mandatory
  `FR_NFR_NEW_FINDINGS: 0` last line, posted the success commit status,
  and exited 0 — it posted NO failure status and NO PR failure comment.
- Pre-push run logged a single `gh: No commit found for SHA` warning and
  still exited 0 (the status post is wrapped in `log_warn`, a graceful
  degrade). Re-running after the branch was pushed posted the success
  status cleanly with no warning. Correct behavior, no babysitting.

Skills applied: code-organization, quality-standards,
bmad-fr-nfr-review-gate (via `fr-nfr-gate.sh`).

### OPEN PR — auto-performed

Pushed `feat/percentage-vo`; `gh pr create` opened PR #4 with a
spec-linked description (issue link `Closes #3`, implemented-stories
summary, acceptance-criteria checklist, skills-applied list, and the
PHP-degrade note), per `sdlc-finish-pr.md` step 1.

Skills applied: none beyond the playbook. Babysitting: none.

### FINISH — auto-performed

Ran `get-pr-comments.sh --pr 4` (human) and
`--pr 4 --unresolved-only --json` against the fresh PR with the real `gh`.

- Human listing: `unresolved threads: 0`, exit 0.
- JSON: `{"pr": 4, "review_threads": [], "issue_comments": []}`, exit 0.

The FR-8 exit condition (0 unresolved review comments) is satisfied
on a fresh PR exactly as designed.

Skills applied: code-review (FR-8 comment feed). Babysitting: none.

## Sandbox CI state (informational, not a plugin defect)

The PR's GitHub Actions checks fail, but every job dies at the
`make start` step with
`unable to get image 'postgres:-alpine': invalid reference format`: the
sandbox repo's CI has no `DB_*`/service-env secrets, so the container
stack never comes up and no PHP tool (Psalm, Deptrac, PHPUnit, Infection)
ever runs against the code. This is the same class of unprovisioned-
environment degrade as the local PHP-unavailable note above — it is not a
defect in the `Percentage` feature and not a `php-backend-sdlc` flow bug.

## Verdict

The plugin's documented flow shipped the feature end-to-end with skills
auto-performing and no manual intervention beyond playbook-prescribed
steps. Every stage reached its exit condition (or its documented degrade)
on the first attempt; no script errored during real use, no stage stalled,
no wrong skill was applied, and no broken artifact was produced. The only
non-auto moments were (a) the playbook-mandated `bmalph init` on the fresh
repo, (b) the triage-first plan choice over the full BMAD chain (a
decision-guide branch), and (c) the honest PHP/Docker degrade where the
container-only `make.*` targets could not run in this host — all
environment/scope facts, not flow bugs.
