# Skill compile contract — turning a learned skill into a plugin skill

A skill that an agent learned inside one repository (for example one the
[autoharness](https://github.com/tigerless-labs/autoharness) plugin wrote into
`.claude/skills/<name>/` with a `.ledger.jsonl` and `.sidecar.json` beside it)
records one team's hard-won gotcha in that repository's own words: its make
targets, its paths, its version pins, and often the pull request that taught
the lesson. To ship in this plugin the same lesson has to load unchanged in any
repository shape the plugin serves. This page is the contract that
`/fe-sdlc-skill-compile` applies, and the checklist a reviewer uses on the
result. The plugin's own lint (`tools/plugin-quality/lint/lint_all.py` in the
marketplace repository) and the LLM judge enforce most of it mechanically.

## Sources to read before writing

- The learned `SKILL.md` and every sibling file in its directory.
- Its `.ledger.jsonl` when present: each entry says why the skill was created
  or patched and cites the evidence. A ledger entry is the strongest signal of
  which insight matters most; an insight the ledger calls out must survive.
- The repository facts the skill relies on, verified in the working tree
  (`Makefile`, `package.json`, config files) — never from memory.

## Frontmatter

```yaml
---
name: <kebab-case; equals the directory name>
description: Use when <concrete triggers — symptoms, error text, file kinds, tool names>
---
```

- Only `name` and `description`.
- The description contains `Use when`, is written in the third person, lists
  triggers only, and never summarizes the steps (an agent that reads a workflow
  summary follows it and skips the body). Keep it under 500 characters and above
  150. Two skills in the plugin must not fire on the same symptom — check the
  sibling descriptions and sharpen.

## Body shape

1. `# <Title>`
2. `## Profile keys consumed` — **always the first H2**. One bullet per profile
   key the body references, all from
   [`docs/profile-schema.md`](profile-schema.md). A skill that needs none says
   `- None — this skill is independent of the profile.`
3. `## Overview` — one to three sentences: what this is and the core principle.
4. `## When to use` — symptom bullets; the last bullet starts with `Not for:`.
5. `## Applicability by repository shape` — exactly three bullets:
   - `- **React SPA shape** (…): yes|partial|no — …`
   - `- **Next.js app shape** (…): yes|partial|no — …`
   - `- **Component-library shape** (…): yes|partial|no — …`

   `yes` means every target and path the body relies on exists in that shape;
   `partial` names what differs; `no` means nothing to do there.
6. One or more content sections: `## Core pattern` (before/after code),
   `## Procedure` (numbered steps), or `## Quick reference` (scannable table or
   bullets). No heading text repeats.
7. `## Common mistakes` — bullets in the form `- <mistake> — <fix>`.

## Generalization rules

- **Repository shapes, not repository names.** The body never names a
  repository, an organization, or a service by its own name; it says "in the
  React SPA shape" / "in the Next.js shape" / "in the component-library shape".
- **Profile keys, not make targets.** Where a target has a key in the profile
  schema, write "the target mapped by `make.<key>`" and say the step is skipped
  with a recorded note when the key maps to `null`. Where no key exists,
  describe the target by purpose and show the concrete command only inside a
  fenced `bash` block whose opening fence ends with `# profile-example`.
- **Denylist.** No `vilnacrm`, `user-service`, `src/user`, `src/oauth`,
  `apprunner` outside a `# profile-example` fence (the plugin lint enforces
  this).
- **No narrative.** No pull-request or issue numbers, dates, commit hashes,
  branch names, timestamps, or "we". A learned skill is a technique, not a
  session log.
- **No suppression advice.** Never recommend `eslint-disable`, `@ts-ignore`,
  `depcruise-ignore`, `--no-verify`, raising a threshold, or skipping a test to
  make a gate pass. Where the learned skill did, rewrite to the root-cause
  remedy and record the original advice as a dropped insight.
- **Every still-true insight survives.** An insight that turned out to be wrong,
  or that holds in no shape, is dropped — and the drop is recorded in the compile
  report with its reason. Nothing is dropped for brevity.
- **Fidelity over polish.** One excellent example beats several mediocre ones,
  but a number, a command, or a gotcha from the source is never rounded away.
- **Cross-references.** A backticked name followed by the word "agent" must be
  one of the plugin's agents; relative `.md` links must resolve; profile keys
  must exist in the schema.

## Compile report

The command writes a short report next to the compiled skill request (not into
the plugin tree):

```json
{
  "name": "<skill>",
  "source": "<path of the learned skill>",
  "shapes": { "spa": "yes", "nextjs": "partial", "library": "no" },
  "profile_keys": ["make.lint_dup"],
  "refs_verified": [{ "ref": "make.lint_dup → lint-dup", "exists": true }],
  "dropped_insights": [{ "insight": "…", "reason": "…" }],
  "lint": "clean"
}
```

## Verification

From the marketplace repository root:

```bash
python3 tools/plugin-quality/lint/lint_all.py plugins/react-frontend-sdlc
npx --yes markdownlint-cli2 "plugins/react-frontend-sdlc/skills/<name>/*.md"
```

Both must be clean. Then update the two meta-guides (`skills/AI-AGENT-GUIDE.md`
and `skills/SKILL-DECISION-GUIDE.md`) so the new skill is inventoried, the exact
skill count in `tests/component-counts.bats` and the README, and bump the
plugin `version` (MINOR) per the [release process](release-process.md).
