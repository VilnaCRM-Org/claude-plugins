---
description: "Prepare a React frontend repository for the SDLC loop: preflight, project profile, governance blocks, permissions, companion skills"
argument-hint: "[--refresh]"
---

# /fe-sdlc-setup — environment and profile setup (FR-2)

Prepare the current repository for the react-frontend-sdlc loop. Re-running
is safe: outside the managed artifacts (profile, governance blocks,
permissions allowlist) nothing is touched, and an existing profile is
never overwritten unless the user passed `--refresh` (NFR-3).

## Inputs

- Target repository: the current working directory (must be a git work
  tree — preflight enforces this).
- Optional argument `--refresh`: regenerate `.claude/react-sdlc.yml` from
  detection even when it already exists. Without it, an existing profile
  is kept and only a drift diff is shown.
- No profile is required on entry — this command creates it (the
  "first action is `validate-profile.sh`" rule from the stage contract
  applies to every other command, not to `/fe-sdlc-setup` itself).

## Procedure

1. **Preflight** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/setup-preflight.sh" --report
   ```

   If it exits non-zero, ABORT immediately: print the FAIL rows and
   their named remediations verbatim and stop. Do not attempt later
   steps with a broken toolchain (FR-2 abort-on-FAIL).

2. **BMAD bootstrap (fresh repo only)** — if `_bmad/` does not exist in
   the target repository, run `bmalph init` non-interactively. Surface
   any failure output verbatim and abort — never mask or retry a failed
   bootstrap (A2). If `_bmad/` already exists, skip this step and say so.

3. **Generate the project profile** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh"
   ```

   Append `--refresh` if and only if the user passed it. Default mode
   keeps an existing profile and prints the detection diff; report that
   diff to the user instead of silently changing anything (NFR-3). The
   detector reads the React frontend's signals — `package.json`, the
   `Makefile` target list, `tsconfig`/bundler path aliases, the module
   directories under `architecture.source_root`, `stryker.config.mjs`'s
   `break` threshold, and the Lighthouse configs — into the typed
   `.claude/react-sdlc.yml` profile.

4. **Validate the profile** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
   ```

   On exit 1, show every `VIOLATION:` line, then enter the bounded
   fix-retry loop below: if a violation is a detection gap the user can
   fix in place, regenerate and re-validate (step 4), counting the
   attempt against `MAX_ITERATIONS`. Crucially, the loop's regenerate
   step MUST pass `--refresh` so the corrected repository signals
   actually overwrite the invalid profile — the default step-3 generate
   keeps the existing file (NFR-3) and would make every retry a no-op,
   so the loop can never converge without it. This in-loop `--refresh`
   does not violate NFR-3's no-silent-overwrite rule: the user has
   already seen the `VIOLATION:` lines and is explicitly correcting the
   detection gap, so the overwrite is the acknowledged remedy, not a
   silent change. Concretely, each retry runs:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh" --refresh
   "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
   ```

   Only ABORT once the loop is exhausted or a violation is not fixable
   by re-detection — then tell the user to either fix the profile by
   hand or re-run `/fe-sdlc-setup --refresh` after correcting the
   repository signals the detector reads.

5. **Inject governance blocks** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/inject-governance.sh"
   ```

   This maintains the managed `<!-- react-frontend-sdlc:begin/end -->`
   block in `CLAUDE.md` and `AGENTS.md`; user content outside the
   markers is never modified.

6. **Permissions allowlist (ADR-6)** — ensure `.claude/settings.json`
   in the target repository carries the allowlist that lets
   plugin-spawned `claude -p … --permission-mode acceptEdits` sessions
   run the container-only workflow without interactive prompts:

   ```json
   {
     "permissions": {
       "allow": [
         "Bash(bmalph:*)",
         "Bash(make:*)",
         "Bash(bun:*)",
         "Bash(docker compose exec dev:*)",
         "Bash(git:*)",
         "Bash(gh:*)"
       ]
     }
   }
   ```

   Merge, do not clobber: if the file exists, add only the missing
   entries to `permissions.allow` and leave every other setting intact.
   These cover the container-only toolchain — `bmalph` drives the
   bootstrap (step 2) and the stage-3 Ralph loop, Make drives every
   gate, `bun` manages dependencies, `docker compose exec dev` reaches
   into the dev container for single-test inner loops, and `git`/`gh`
   drive the PR. The package-manager entry tracks
   `framework.package_manager`: on a repo whose profile says `pnpm` or
   `npm`, write `Bash(pnpm:*)` / `Bash(npm:*)` instead of `Bash(bun:*)`
   (docs/permissions.md). Document in your summary that
   `bypassPermissions` is a Ralph-driver opt-in only — `/fe-sdlc-setup`
   never writes it and nothing in this plugin defaults to it.

7. **Install companion skills (optional enhancement)** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/install-companion-skills.sh"
   ```

   This installs the optional ui-skills.com design / motion /
   accessibility companion suite recorded under the profile's
   `companion.skills` / `companion.agents` (install method in
   `companion.install_command`) that the review and QA agents lean on
   when present — the MUI `sx`/`styled()`/theme translation of the
   Tailwind-and-shadcn-oriented design and a11y guidance. They are an
   enhancement, never a hard dependency: every gate runs without them,
   so a non-zero exit here is **non-fatal** — surface the warning, note
   it in the run summary, and continue (do not abort, and do not count
   the attempt against `MAX_ITERATIONS`). The catalog and the MUI
   translation of each skill live in `docs/companion-skills.md`; the
   install is a global, user-environment action and never alters the
   target repository tree.

8. **Diff summary** — finish by listing exactly what changed this run:
   `git status --short`, the profile diff from step 3, and the
   governance change from step 5 — reported as the script's own change
   log (the `managed block written` / `unchanged` lines it printed in
   apply mode; `inject-governance.sh` emits no diff there, only behind
   the `--diff` preview flag) plus the actual content delta from
   `git diff -- CLAUDE.md AGENTS.md`. State the companion-skills outcome
   from step 7 separately (it touches the user environment, not the repo
   tree, so it never appears in `git status`). On an unchanged re-run
   (every managed file reported `unchanged`), state that the run was a
   no-op.

## Loop & exit condition

Single-pass command with one bounded fix-retry loop around steps 3–4:
when validation fails because of a detection gap the user has since
fixed, regenerate **with `--refresh`** (so the corrected signals
overwrite the invalid profile — without it the retry is a no-op) and
re-validate. Exit condition (measurable):
`setup-preflight.sh` exits 0 AND `validate-profile.sh` exits 0 AND the
governance block exists in `CLAUDE.md`/`AGENTS.md` AND
`.claude/settings.json` contains the six allowlist entries. The
companion-skills install is best-effort and is intentionally outside the
exit condition — its failure degrades to a warning and never blocks
setup.

## Iteration guard

`MAX_ITERATIONS=5` for the generate→validate retry loop. Keep an
explicit counter and restate it on every attempt
(`setup iteration <n>/5`). Preflight and bootstrap failures are not
retried at all — they abort on first failure, and the optional
companion-skills install in step 7 is never retried (its failure
degrades to a warning).

## Failure escalation

On guard breach or any abort above, emit the canonical report and stop:

```text
=== SDLC ESCALATION ===
stage: setup             iteration: <n>/5
exit_condition: preflight PASS + profile valid + governance + allowlist
status: NOT MET
blocking_finding: <one line — e.g. first preflight FAIL row or first VIOLATION line>
iteration_log: <one line per attempt>
recommended_action: <the named remediation from the failing script>
=== END ===
```
