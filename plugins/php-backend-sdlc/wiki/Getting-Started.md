# Getting Started

[Home](Home.md) › Start here › Getting Started

This page takes you from a clean PHP backend checkout to a finished pull
request: install the plugin, satisfy the prerequisites, run the six
`/sdlc-setup` steps, and drive a first task end-to-end with `/sdlc`. Every
step here is grounded in the plugin source — the
[`/sdlc-setup` command](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc-setup.md),
the
[setup walkthrough](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/setup-walkthrough.md),
and the
[`/sdlc` orchestrator](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/commands/sdlc.md).

## Prerequisites

`/sdlc-setup` step 1 (preflight) checks all of these and prints a named
remediation for each failure, so you do not have to verify them by hand
first. The full list:

| Requirement | Floor | Notes |
| --- | --- | --- |
| Git repository | — | Run from the repo root of your PHP backend; preflight enforces a git work tree |
| Claude Code CLI | `>= 2.1` | The harness running this plugin |
| GitHub CLI (`gh`) | `>= 2`, authenticated | Run `gh auth login` first; used for issues and PRs |
| bmalph | `>= 2.11.0` | Healthy `_bmad/` workspace when one exists (`bmalph doctor`); fresh repos are bootstrapped by `/sdlc-setup` |
| YAML toolchain | — | `yq`, or `python3` with PyYAML |
| JSON toolchain | — | `jq`, or `python3` (also checked by preflight) |

If any preflight row is `FAIL`, the command aborts before touching the
repository — apply the printed remediation and re-run. See
[what a failing preflight looks like](#first-run-with-sdlc) below and the
[Troubleshooting](Troubleshooting.md) page for recovery details.

## Install

Add the marketplace and install the plugin through the Claude Code CLI:

```bash
claude plugin marketplace add VilnaCRM-Org/claude-plugins
claude plugin install php-backend-sdlc@vilnacrm-plugins
```

The plugin ships 8 commands, 7 subagents, and a 22-skill library (plus two
meta-guides:
[`AI-AGENT-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/AI-AGENT-GUIDE.md)
and
[`SKILL-DECISION-GUIDE.md`](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/skills/SKILL-DECISION-GUIDE.md)).
See [Commands](Commands.md), [Agents](Agents.md), and [Skills](Skills.md)
for the full inventory.

## `/sdlc-setup` walkthrough

`/sdlc-setup` is stage 0. Run it once per repository from the repo root;
re-running is safe. The only files it may touch are the project profile, the
governance blocks, the permissions allowlist, and — on a fresh repo only — a
`_bmad/` workspace created during bootstrap. An existing profile is kept
unless you pass `--refresh`.

```bash
cd your-php-backend-repo

/sdlc-setup            # first-time setup
/sdlc-setup --refresh  # re-detect and regenerate the profile
```

### The six steps

The command runs these in order, aborting on the first hard failure.

| Step | What it does | Artifact produced |
| --- | --- | --- |
| 1. Preflight | Runs `scripts/setup-preflight.sh --report`: git work tree, `claude`/`gh` versions, `gh` auth, bmalph version/doctor, YAML and JSON toolchains | PASS/FAIL table; no files written |
| 2. BMAD bootstrap | Fresh repo only: if `_bmad/` is absent, runs `bmalph init` non-interactively; skipped (and reported) when `_bmad/` exists | `_bmad/` workspace (fresh repos only) |
| 3. Generate profile | Runs `scripts/generate-profile.sh` to detect repository facts; without `--refresh` an existing profile is preserved and only a drift diff is shown | `.claude/php-sdlc.yml` (the [Project Profile](Project-Profile.md)) |
| 4. Validate profile | Runs `scripts/validate-profile.sh`; a `VIOLATION:` aborts the run | No files; pass/abort verdict only |
| 5. Inject governance | Runs `scripts/inject-governance.sh` to maintain the managed `<!-- php-backend-sdlc:begin/end -->` block; content outside the markers is never modified | Managed block in `CLAUDE.md` and `AGENTS.md` |
| 6. Permissions allowlist | Merges four allowlist entries into `.claude/settings.json` so plugin-spawned `claude -p … acceptEdits` sessions run without interactive prompts | Allowlist entries merged into `.claude/settings.json` |

A final diff-summary step lists exactly what changed this run
(`git status --short`, the profile detection diff, the governance change
log, and `git diff -- CLAUDE.md AGENTS.md`). On an unchanged re-run it
reports a no-op.

The allowlist written in step 6 is:

```json
{
  "permissions": {
    "allow": [
      "Bash(make:*)",
      "Bash(docker compose exec php:*)",
      "Bash(git:*)",
      "Bash(gh:*)"
    ]
  }
}
```

It merges, never clobbers — existing settings are preserved.
`bypassPermissions` is a Ralph-driver opt-in only: `/sdlc-setup` never
writes it and nothing in this plugin defaults to it. See
[Permissions](Permissions.md) for the full policy.

### `--refresh` semantics

| Mode | Step 3 behavior |
| --- | --- |
| Without `--refresh` (default) | An existing `.claude/php-sdlc.yml` is never overwritten; detection re-runs and a drift diff is shown so you can decide whether to adopt the changes — nothing changes silently |
| With `--refresh` | The profile is regenerated from detection, replacing the previous file; use this after changing repository signals (added a make target, enabled GraphQL, raised a quality floor) |

`--refresh` affects only the profile. Governance blocks and the permissions
allowlist are reconciled the same way on every run (managed block
maintained, allowlist entries merged).

The generate→validate retry loop is bounded at five iterations
(`setup iteration <n>/5`). On guard breach or any abort, the command emits
the canonical SDLC escalation block with the blocking finding and the
recommended action. See the
[full setup walkthrough](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/setup-walkthrough.md)
for the failing-preflight example.

### Setup exit condition

Setup is complete when `setup-preflight.sh` exits 0, `validate-profile.sh`
exits 0, the governance block exists in `CLAUDE.md` and `AGENTS.md`, and
`.claude/settings.json` carries the four allowlist entries. After that the
repository is ready for `/sdlc` and the per-stage commands.

## First run with `/sdlc`

Once setup is green, hand a task to the end-to-end orchestrator. The
argument is either a free-text task description or an existing issue URL:

```bash
/sdlc "Add a Currency resource with code and name fields and REST CRUD endpoints"
```

`/sdlc` drives all seven stages with gated transitions — a stage starts
only when the prior stage's exit condition is verifiably met — and the run
ends in exactly one of two states, SUCCESS or ESCALATED:

| # | Stage | Delegates to | Exit condition |
| --- | --- | --- | --- |
| 0 | setup-check | profile + preflight validation | valid `.claude/php-sdlc.yml`, preflight fresh (halts to `/sdlc-setup`; never generates the profile in-loop) |
| 1 | issue | [`/sdlc-issue`](Commands.md) | GitHub issue URL exists with testable acceptance criteria |
| 2 | plan | [`/sdlc-plan`](Commands.md) | `specs/<slug>/` chain complete, readiness PASS |
| 3 | implement | [`/sdlc-implement`](Commands.md) | Ralph `EXIT_SIGNAL` success, all stories done |
| 4 | review | [`/sdlc-review`](Commands.md) | zero new findings in the last gate iteration |
| 5 | qa | [`/sdlc-qa`](Commands.md) | QA verdict PASS (FAIL routes back to stage 3) |
| 6 | finish-pr | [`/sdlc-finish-pr`](Commands.md) | CI green + 0 unresolved AI review comments |

The run is resumable: on every invocation it detects the current stage from
durable artifacts (it queries open `php-backend-sdlc`-labeled GitHub issues
rather than transient stdout) and resumes at the first stage whose exit
condition is not yet met — never restarting from scratch. Each stage carries
its own `MAX_ITERATIONS=5` guard; counters survive loop-backs (a QA→implement
route does not refresh stage 3's budget), and a Ralph circuit-breaker trip in
stage 3 is terminal. See [The SDLC Loop](The-SDLC-Loop.md) for the full
stage diagram and exit conditions.

You can also run any stage on its own — for example `/sdlc-plan` after you
already have an issue. Every per-stage command except `/sdlc-setup`
validates the profile as its first action and aborts with "run
`/sdlc-setup`" if it is missing or invalid.

If the preflight or setup-check ever fails mid-run, you will see a row like:

```text
PASS: git-repo — inside a git work tree
FAIL: gh-auth — gh is not authenticated
remediation: run: gh auth login
```

Apply the named remediation and re-run. See [Troubleshooting](Troubleshooting.md)
and [Degrade and Resilience](Degrade-and-Resilience.md) for how the loop
behaves when a capability is missing.

## Where artifacts land

A complete run leaves these in your repository and on GitHub:

| Artifact | Location | Written by |
| --- | --- | --- |
| Project profile | `.claude/php-sdlc.yml` | `/sdlc-setup` step 3 ([Project Profile](Project-Profile.md)) |
| Governance blocks | managed block in `CLAUDE.md`, `AGENTS.md` | `/sdlc-setup` step 5 |
| Permissions allowlist | `.claude/settings.json` | `/sdlc-setup` step 6 ([Permissions](Permissions.md)) |
| Planning artifacts | `specs/<slug>/` (six files, see below) | `/sdlc-plan` (stage 2) |
| GitHub issue | the `php-backend-sdlc`-labeled issue | `/sdlc-issue` (stage 1) |
| Pull request | the project's GitHub repo | `/sdlc-finish-pr` (stage 6) |

`<slug>` is the kebab-case issue title prefixed with the issue number
(for example `42-currency-crud`). The six planning artifacts, written in
order under `specs/<slug>/`, are:

1. `research.md` — domain/technical research for the issue
2. `brief.md` — product brief
3. `prd.md` — requirements, with the issue's acceptance criteria traced
   into FRs
4. `architecture.md` — technical design
5. `epics-stories.md` — epics and stories, each marked independent or
   dependent (the `/sdlc-implement` parallel-dispatch input)
6. `readiness.md` — implementation-readiness verdict (PASS/FAIL with named
   findings)

## One-time GitHub wiki seed

A GitHub wiki must contain at least one page before pages pushed from this
`wiki/` directory will appear. If the project wiki is empty, create the
initial `Home` page once through the GitHub web UI (or push a first commit
to the wiki's git remote), then the remaining pages — including this one —
can be published. The seed and the publish procedure are documented on the
[Contributing and Releases](Contributing-and-Releases.md) page.

## See also

- [Home](Home.md)
- [The SDLC Loop](The-SDLC-Loop.md)
- [Project Profile](Project-Profile.md)
- [Permissions](Permissions.md)
- [Contributing and Releases](Contributing-and-Releases.md)
