---
description: "Compile a skill an agent learned inside one repository (an autoharness-written .claude/skills/<name> with its ledger, or any repo-local skill) into a plugin-ready skill: shape-generalized, profile-key driven, lint-clean, with every insight preserved and every drop recorded"
argument-hint: "[path-to-learned-skill-dir] [--target plugin-root]"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /fe-sdlc-skill-compile — learned skill → plugin skill

Skills learned inside a repository (the autoharness plugin writes them into
`.claude/skills/<name>/` with a `.ledger.jsonl` and `.sidecar.json`) hold
real lessons in one repository's vocabulary. This command rewrites one such
skill into the plugin's shape-generalized, profile-driven form so it loads in
every repository shape the plugin serves, and gates the result with the
plugin's own lint. The contract it applies is
[docs/skill-compile-contract.md](../docs/skill-compile-contract.md).

## Inputs

- First action: locate the marketplace checkout — the `--target` argument, or
  the directory that contains `plugins/react-frontend-sdlc/.claude-plugin/plugin.json`
  above the current working directory, or `${CLAUDE_PLUGIN_ROOT}` when it is a
  git checkout rather than an install cache. If none is writable, ABORT: the
  compiled skill has nowhere to land (an install cache is overwritten on the
  next update).
- The learned skill: the argument path (a directory holding `SKILL.md`;
  `.claude/skills/<name>` or `.claude/skills/.archive/<name>`). Read `SKILL.md`,
  every sibling file, and `.ledger.jsonl` when present.
- The working tree the skill was learned in (the current repository) — the
  only source for verifying its make targets, paths, and config facts.
- The contract: `../docs/skill-compile-contract.md`. The canonical key list:
  `../docs/profile-schema.md`.
- Profile keys consumed: none directly — this command reads the profile
  schema, not a project profile.

## Procedure

1. **Extract** every distinct insight from the source (rules, gotchas,
   commands, numbers, patterns) into a numbered list. Mark each with the
   ledger entry that motivated it when one exists. This list is the fidelity
   checklist for step 5.
2. **Verify** every make target, path, config file, version, and policy claim
   against the working tree (`grep`, `ls`, `cat` on the Makefile,
   `package.json`, configs). Map each make target to its profile key from
   `docs/profile-schema.md`; note targets that have no key (they become
   purpose descriptions plus a `# profile-example` fence).
3. **Decide applicability per shape** from the verified facts: React SPA,
   Next.js app, component library — `yes` / `partial` (name what differs) /
   `no`. Never mark `yes` for a shape whose target or path you could not
   verify.
4. **Write** `plugins/react-frontend-sdlc/skills/<name>/SKILL.md` in the
   contract's body shape: first H2 `## Profile keys consumed`, shape labels
   instead of repository names, profile keys instead of make targets, no
   narrative, no suppression advice, sibling files copied and transformed
   the same way. Choose a name that does not collide with an existing plugin
   skill and whose description fires on different symptoms than its
   neighbours (read the sibling descriptions).
5. **Fidelity check**: tick every item of the step-1 list against the draft.
   An insight that is wrong, or true in no shape, is dropped and recorded
   with its reason; everything else is present. Where the source recommended
   a suppression, the compiled text carries the root-cause remedy and the
   drop record carries the original advice.
6. **Lint** from the marketplace root until clean for the new files:

   ```bash
   python3 tools/plugin-quality/lint/lint_all.py plugins/react-frontend-sdlc
   npx --yes markdownlint-cli2 "plugins/react-frontend-sdlc/skills/<name>/*.md"
   ```

7. **Inventory**: add the skill to `skills/AI-AGENT-GUIDE.md` and
   `skills/SKILL-DECISION-GUIDE.md` (the meta-guide inventory is judged),
   bump the exact skill count in `tests/component-counts.bats` and in the
   README, bump the plugin `version` (MINOR), and run the bats suite:

   ```bash
   npx --yes bats plugins/react-frontend-sdlc/tests/component-counts.bats
   ```

8. **Report**: print the compile report JSON from the contract (name,
   source, shapes, profile keys, refs verified, dropped insights, lint
   state) and the list of files written. Do not commit; hand the tree back
   to the caller.

## Loop & exit condition

One iteration = write → lint → fidelity check. Exit condition: **lint clean
for every new file, bats green, and every source insight either present in
the compiled skill or recorded as dropped with a reason**.

## Iteration guard

`MAX_ITERATIONS=5`. Restate the counter every turn
(`skill-compile iteration <n>/5`). A lint finding that survives three
iterations points at a contract conflict (for example a make target with no
profile key that the body cannot describe by purpose) — stop and escalate
instead of weakening the contract.

## Failure escalation

Escalate — emit the canonical report and stop — when no writable marketplace
checkout exists, the source has no `SKILL.md`, a target or path cannot be
verified in any shape, or the guard is breached:

```text
=== SDLC ESCALATION ===
stage: skill-compile     iteration: <n>/5
exit_condition: lint clean, bats green, every insight present or recorded as dropped
status: NOT MET
blocking_finding: <one line — e.g. "no writable marketplace checkout", "L17 first-H2 finding persists">
iteration_log: <one line per iteration>
recommended_action: <human next step>
=== END ===
```
