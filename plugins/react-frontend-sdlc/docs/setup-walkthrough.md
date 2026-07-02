# `/fe-sdlc-setup` Walkthrough

`/fe-sdlc-setup` (stage 0) prepares a React frontend repository for the SDLC
loop. Run it once per repository from the repo root; re-running is safe. The
only files/directories it may touch are the project profile, the governance
blocks, the permissions allowlist, and — on a fresh repo only — a `_bmad/`
workspace created during the bootstrap step. The optional companion-skills
step writes solely under the user config dir, never the repository tree. An
existing profile is kept unless you pass `--refresh`.

```bash
cd your-react-frontend-repo
/fe-sdlc-setup            # first-time setup
/fe-sdlc-setup --refresh  # re-detect and regenerate the profile
```

## The seven setup steps

The command runs the following in order, aborting on the first hard failure.

1. **Preflight** — runs `scripts/setup-preflight.sh --report`. Checks the git
   work tree, the `claude` (>= 2.1) and `gh` (>= 2) CLIs, `gh` authentication,
   the bmalph version (>= 2.11.0) and its `bmalph doctor` state against any
   existing `_bmad/` workspace (deferred on a fresh repo, where bootstrap runs
   right after), a JavaScript package manager (any one of `bun`, `pnpm`, or
   `npm` — the consumer repos differ, so none is hard-required), Node.js
   (>= 20.0.0, the lowest `engines.node` floor across the repos), Docker
   presence (a running daemon is optional at setup time), the YAML toolchain
   (`yq` or `python3` + PyYAML), and the JSON toolchain (`jq` or `python3`). On
   any FAIL the command aborts before touching the repository (see
   [failing preflight](#what-a-failing-preflight-looks-like)).
2. **BMAD bootstrap (fresh repo only)** — if `_bmad/` is absent, runs
   `bmalph init` non-interactively. If `_bmad/` already exists, the step is
   skipped and reported as such. A failed bootstrap is surfaced verbatim and
   aborts the run — it is never masked or retried.
3. **Generate the project profile** — runs `scripts/generate-profile.sh`,
   detecting repository facts into `.claude/react-sdlc.yml`. Detection reads
   `package.json` (framework deps, package manager, Node engine), the
   `tsconfig`/bundler path aliases, the source-root layout under
   `architecture.source_root`, the `Makefile` (the logical→actual target map),
   the Stryker config's `break` threshold that seeds `quality.mutation_msi`,
   the CI workflows, and `.coderabbit.yaml`. Without `--refresh` an existing
   profile is preserved and only a detection drift diff is shown; with
   `--refresh` the profile is regenerated from detection.
4. **Validate the profile** — runs `scripts/validate-profile.sh`. On a
   `VIOLATION:` it aborts and tells you to fix the profile by hand or re-run
   `/fe-sdlc-setup --refresh` after correcting the repository signals the
   detector reads.
5. **Inject governance blocks** — runs `scripts/inject-governance.sh`, which
   maintains the managed `<!-- react-frontend-sdlc:begin/end -->` block in
   `CLAUDE.md` and `AGENTS.md`. Content outside the markers is never modified.
6. **Permissions allowlist** — merges the five allowlist entries into
   `.claude/settings.json` so plugin-spawned
   `claude -p … --permission-mode acceptEdits` sessions run the container-only
   workflow without interactive prompts. Existing settings are preserved
   (merge, never clobber).
7. **Install companion skills (optional)** — runs
   `scripts/install-companion-skills.sh`, which installs the optional
   ui-skills.com design / motion / accessibility companions the review and QA
   agents lean on when present. It is an enhancement, never a hard dependency:
   every gate runs without it, so a non-zero exit here is **non-fatal** — the
   warning is surfaced and noted, and the run continues.

A final **diff summary** step then lists exactly what changed this run
(`git status --short`, the profile detection diff from step 3, the
`inject-governance.sh` change log plus `git diff -- CLAUDE.md AGENTS.md`). The
companion-skills outcome is stated separately because it touches the user
environment, not the repo tree, so it never appears in `git status`. On an
unchanged re-run it reports a no-op.

## What each step produces

| Step | Artifact produced |
| --- | --- |
| 1 Preflight | A PASS/FAIL table; no files written |
| 2 BMAD bootstrap | `_bmad/` workspace (fresh repos only) |
| 3 Generate profile | `.claude/react-sdlc.yml` (the [project profile](profile-schema.md)) |
| 4 Validate profile | No files; pass/abort verdict only |
| 5 Inject governance | Managed block in `CLAUDE.md` and `AGENTS.md` |
| 6 Permissions | Allowlist entries merged into `.claude/settings.json` |
| 7 Companion skills | Optional companions under the user config dir (never the repo tree) |

The allowlist written in step 6 is:

```json
{
  "permissions": {
    "allow": [
      "Bash(make:*)",
      "Bash(bun:*)",
      "Bash(docker compose exec dev:*)",
      "Bash(git:*)",
      "Bash(gh:*)"
    ]
  }
}
```

These cover the container-only toolchain: Make drives every gate, the package
manager manages dependencies, `docker compose exec dev` reaches into the dev
container for single-test inner loops, and `git`/`gh` drive the PR. The
`bun` entry names the reference SPA's manager; a repo on `pnpm` or `npm`
simply does not exercise it, and generic tooling (`gh`, `git`) is invoked
directly regardless. `bypassPermissions` is a Ralph-driver opt-in only —
`/fe-sdlc-setup` never writes it and nothing in this plugin defaults to it.

## `--refresh` semantics

- **Without `--refresh`** (default): an existing `.claude/react-sdlc.yml` is
  never overwritten. Step 3 re-runs detection and shows a drift diff between
  what is on disk and what detection would now produce, so you can decide
  whether to adopt the changes — nothing is changed silently.
- **With `--refresh`**: step 3 regenerates the profile from detection,
  replacing the previous file. Use this after you have changed repository
  signals (added a make target, enabled visual testing, raised a quality
  floor) and want the profile to reflect them.

`--refresh` affects only the profile. Governance blocks and the permissions
allowlist are reconciled the same way on every run (managed block maintained,
allowlist entries merged), and the companion-skills step re-runs
best-effort.

## Multi-repo detection

The detector is repo-shape agnostic, so one profile schema serves three
divergent React repositories without assuming any single stack. It records
what it finds through the profile's logical `make.*` map, the
`capabilities.*` flags, `framework.*` facts, and the `architecture.*` layout
rather than hardcoding a raw target or a single toolchain:

- A **feature-module SPA** (for example an RSBuild + `bun` app) populates
  `architecture.modules` from the directories under `architecture.source_root`
  and maps the full `make.*` map, including `make.ci`, `make.lint_dup`, and
  `make.lint_metrics`.
- A **server-rendered app** (for example a Next.js + `pnpm` app) may ship no
  duplication or complexity gate; detection then leaves `make.lint_dup` and
  `make.lint_metrics` as `null`, and the dependent lanes degrade with a note
  instead of failing.
- A **component library** (for example a `bun`, Storybook-first package) may
  have no aggregate CI target and no feature modules at all; `make.ci` is
  `null`, `architecture.modules` is empty, and the Storybook lane is gated by
  `capabilities.storybook` paired with `make.storybook_build`.

A missing capability never fails generation — it becomes `null` (for a
`make.*` target) or `false` (for a `capabilities.*` flag). The distinction
between an explicit `null` (capability absent, plugin degrades with a note)
and a forgotten key (a validation error in step 4) is intentional.

## What a failing preflight looks like

Preflight prints one row per check. In its abort-on-first-FAIL mode a failure
looks like:

```text
PASS: git-repo — inside a git work tree
FAIL: gh-auth — gh is not authenticated
remediation: run: gh auth login
```

When any row is FAIL the command **aborts immediately** — it does not run
bootstrap, profile generation, governance, permissions, or the companion-skills
install. Apply the named remediation (for example install or upgrade
`claude`/`gh`/`bmalph` to the required floor, run `gh auth login`, install a JS
package manager, or install `yq` / PyYAML / `jq`) and re-run `/fe-sdlc-setup`.

A profile that fails validation (step 4) aborts the same way, printing every
`VIOLATION:` line. When a violation is a detection gap you can fix in place,
the command enters a bounded generate→validate retry loop capped at
`MAX_ITERATIONS=5` (restated as `setup iteration <n>/5` on each attempt). The
loop's regenerate step passes `--refresh` on purpose: the default step-3
generate keeps the existing file, so without `--refresh` every retry would be a
no-op and the loop could never converge. This in-loop overwrite is the
acknowledged remedy — you have already seen the `VIOLATION:` lines — not a
silent change. On guard breach or any abort the command emits the canonical
SDLC escalation block with the blocking finding (the first preflight FAIL row
or first `VIOLATION:` line) and the recommended action from the failing script.

The companion-skills install (step 7) is never part of this loop: its failure
degrades to a warning, is never retried, and never counts against
`MAX_ITERATIONS`.

## Exit condition

Setup is complete when `setup-preflight.sh` exits 0, `validate-profile.sh`
exits 0, the governance block exists in `CLAUDE.md` and `AGENTS.md`, and
`.claude/settings.json` carries the five allowlist entries. The companion-skills
install is best-effort and intentionally outside the exit condition — its
failure degrades to a warning and never blocks setup. After that the repository
is ready for `/fe-sdlc` and the per-stage commands.
