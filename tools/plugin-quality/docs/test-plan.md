# Prompt-Quality Guardrails — Test Plan

The check matrix. Every row is one automated check, its tier, the contract it
pins, its CI gating, and where its positive/negative/edge cases live. Concrete
case text is in `test-cases.md`.

Legend — **Tier**: T1 static lint · T2 manifest · T3 LLM-judge.
**Gate**: BLOCK (fails CI) · ADVISORY (reported, never fails) · BLOCK* (judge:
blocks ONLY a *critical* dimension scoring `<= block_floor` (2); a critical
score below the floor (4) but above 2 — i.e. 3 — is ADVISORY, reported but
never blocking).

## Tier 1 — Static lint

| # | Check | Module | Pins | Gate | Cases |
| --- | --- | --- | --- | --- | --- |
| L0 | Any artifact whose YAML frontmatter is unparseable/unreadable surfaces a `frontmatter.parse-error` (S2) rather than being silently skipped | frontmatter | arch §2/§3/§4 | BLOCK | FM-1 |
| L1 | Command frontmatter has `description` + `argument-hint` | frontmatter | arch §2; epics E6 | BLOCK | FM-1 |
| L2 | Command `allowed-tools`, when present, is a JSON array of known tools; report-only commands exclude Write/Edit | frontmatter | arch §2; FR-6/FR-7 | BLOCK | FM-2 |
| L3 | Agent frontmatter has `name`+`description`+`tools`+`model` | frontmatter | arch §3; epics E5 | BLOCK | FM-3 |
| L4 | SKILL.md frontmatter has `name`+`description`; no `tools`/`model` | frontmatter | arch §4 | BLOCK | FM-4 |
| L5 | Meta-guide (`skills/*.md` not in a subdir) has NO frontmatter | frontmatter | ADR-11 | BLOCK | FM-5 |
| L6 | Agent `name` == filename stem == H1 | naming | arch §6 | BLOCK | NM-1 |
| L7 | Skill `name` == parent directory name | naming | arch §6 | BLOCK | NM-2 |
| L8 | `model` ∈ {sonnet,opus,haiku,fable,inherit} | naming | plugin docs; ADR-8 | BLOCK | NM-3 |
| L9 | `argument-hint` is one or more bracketed `[...]` groups (e.g. `[a]` or `[a] [b]`) — multi-group is allowed per Claude Code docs | naming | observed; plugin docs | BLOCK | NM-4 |
| L10 | Command/agent/skill names are kebab-case `[a-z0-9-]+` | naming | plugin docs | BLOCK | NM-5 |
| L11 | description (skill+`when_to_use`) ≤ 1536 chars | descriptions | plugin docs (cap) | BLOCK | DS-1 |
| L12 | Skill description has a trigger clause ("Use when"/"When to use") | descriptions | FR-15; plugin docs | BLOCK | DS-2 |
| L13 | Agent description has a delegation trigger ("Delegate"/"Use when"/"Use this agent"/"Proactively") | descriptions | arch §3; plugin docs | BLOCK | DS-3 |
| L14 | description not empty / ≥ 20 chars | descriptions | plugin docs | BLOCK | DS-4 |
| L15 | Command 5-section spine present (Inputs/Procedure/Loop & exit condition/Iteration guard/Failure escalation) | structure | arch §2; epics E6 | BLOCK | ST-1 |
| L16 | Agent 8-section spine present (Profile keys consumed/Role/Inputs/Outputs/Allowed actions/Degrade paths/Iteration discipline/Smoke prompt) | structure | arch §3; epics E5 | BLOCK | ST-2 |
| L17 | SKILL.md first H2 == `## Profile keys consumed` | structure | arch §4; observed (21/21) | BLOCK | ST-3 |
| L18 | Every gated skill (`## *gate`/`## Gating`) documents its skip path — the literal `SKIPPED:` token OR an in-body skip note (a `skip`/`skipped`/`skipping` degrade word) | structure | NFR-4; observed | BLOCK | ST-4 |
| L19 | `${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh` resolves to a real file | references | arch §5; FR-18 | BLOCK | RF-1 |
| L20 | `${CLAUDE_PLUGIN_ROOT}/skills/<x>/SKILL.md` resolves (glob `*/SKILL.md` exempt) | references | arch §4 | BLOCK | RF-2 |
| L21 | Relative `](../<skill>/SKILL.md)` and intra-skill `](file.md)` links resolve | references | arch §4; ADR-11 | BLOCK | RF-3 |
| L22 | `/sdlc-*` token → `commands/*.md` exists (longest-match) | references | FR-1 | BLOCK | RF-4 |
| L23 | Backticked agent name → `agents/*.md` exists | references | FR-9..14 | BLOCK | RF-5 |
| L24 | "X skill" / backticked skill name → `skills/X/` dir exists | references | FR-15 | BLOCK | RF-6 |
| L25 | Backticked profile key (`make.*`,`quality.*`,`capabilities.*`,`framework.*`,`persistence.*`,`architecture.*`,`ci.*`,`project.*`) declared in `docs/profile-schema.md` (`.*` wildcards exempt) | references | FR-17; ci.yml profile-keys-check | BLOCK | RF-7 |
| L26 | Command `## Iteration guard` + agent `## Iteration discipline` state `MAX_ITERATIONS=5` (prose "max 5" normalized) | escalation | NFR-6; arch §2 | BLOCK | ES-1 |
| L27 | `=== SDLC ESCALATION ===` block carries all canonical fields (stage/iteration/exit_condition/status/blocking_finding/iteration_log/recommended_action); orchestrator `=== SDLC RUN REPORT ===` exempt | escalation | arch §2 | BLOCK | ES-2 |
| L28 | NFR-2 denylist over skills/commands/agents/scripts with `# profile-example` fences stripped | generalization | NFR-2; ci.yml generalization-audit | BLOCK | GN-1 |
| L29 | NFR-7 tree hygiene: no `_bmad/`/`.ralph/` inside plugin tree | generalization | NFR-7; ADR-10 | BLOCK | GN-2 |
| L30 | Meta-guide whose filename contains `DECISION` carries the BMAD triage clause ("no silent skips / every skill verdict recorded") — rule `metaguide.decision-guide.triage` (S3) | check_metaguides | FR-16 | BLOCK | MG-1 |
| L33 | A `qa`-named command/agent must not list `Write`/`Edit` in its tool allowlist, regardless of body phrasing — rule `frontmatter.qa.no-mutating-tools` (S2), name-targeted, body-independent | frontmatter | FR-7; FR-12 | BLOCK | FM-6 |

## Tier 2 — Manifest validation

| # | Check | Module | Pins | Gate | Cases |
| --- | --- | --- | --- | --- | --- |
| M1 | `plugin.json` parses; has name+description+version+author.name+homepage+repository+license+keywords | manifest | FR-19; ci.yml | BLOCK | MF-1 |
| M2 | `version` is semver `^\d+\.\d+\.\d+$` | manifest | ADR-9 | BLOCK | MF-2 |
| M3 | `plugin.json` name == plugin dir name | manifest | FR-19 | BLOCK | MF-3 |
| M4 | `marketplace.json` parses; name+owner.name+≥1 plugin; each entry source == `./plugins/<name>` and dir exists | manifest | ADR-9 | BLOCK | MF-4 |
| M5 | `claude plugin validate <plugin> --strict` passes (when `claude` present; else skip-with-message) | manifest | plugin docs | BLOCK-if-present | MF-5 |

## Tier 3 — LLM-as-judge (sonnet via `claude -p <prompt> --output-format json`)

Each row is a rubric dimension. `crit` = a dimension that *can* block — but only
at score `<= block_floor` (2). A crit dimension scoring 3 (below the floor of 4
but above 2) is ADVISORY, as are all non-crit dimensions at any score. Advisory
findings are reported, never block. Floor (advisory threshold) is 4/5;
block_floor (hard-block threshold) is 2 for crit dimensions.

| # | Dimension | Rubric | Type(s) | Pins | crit? | Cases |
| --- | --- | --- | --- | --- | --- | --- |
| J1 | Trigger specificity — would the router fire on the right tasks and not adjacent ones | skill, agent | skill / agent | FR-15; arch §3/§4 | crit | JD-1 |
| J2 | Body↔description fidelity — body delivers what description promises, no over/under-claim or self-contradiction | skill, agent, command | all | FR-15 | crit | JD-2 |
| J3 | Degrade-path soundness — described path terminates, never loops/hard-fails, matches §8 matrix | agent, command, skill | all | NFR-4; arch §8 | crit | JD-3 |
| J4 | Exit-condition consistency (internal: the command states its exit condition consistently across its own sections; the judge is never given the FR-1 stage table, so it cannot and does not verify fidelity to it) | command | command | FR-1 | advisory | JD-4 |
| J5 | Loop/escalation soundness — prose loop logic actually bounds iterations, restates counter, never auto-resets breaker | command, agent | command/agent | NFR-6 | advisory | JD-5 |
| J6 | Profile-key branching completeness — body branches on every key it lists; both conditional branches present | skill | skill | FR-15 | advisory | JD-6 |
| J7 | Semantic generalization — paraphrased/structural user-service leakage the denylist misses | generalization | all | NFR-2 | crit | JD-7 |
| J8 | Root-cause-culture adherence — prose forbids suppression/threshold-lowering with no loophole | agent, skill | agent/skill | FR-9/10/13; ADR-7 | advisory | JD-8 |
| J9 | QA black-box discipline — qa prompts derive verdicts from observed behavior only, never source reads | agent, command | qa | FR-12 | advisory | JD-9 |
| J10 | Meta-guide inventory accuracy — enumerates exactly the shipped skills, no stale/missing | meta-guide | meta-guide | FR-16; ADR-11 | crit | JD-10 |
| J11 | Instruction unambiguity — no step open to multiple readings | all | all | arch §2/§3/§4 | advisory | JD-11 |

## CI job → check mapping (`prompt-quality.yml`)

| Job | Tier(s) | Runs when | Gate |
| --- | --- | --- | --- |
| `prompt-lint` | T1 + T2 (M1–M4) | always (no network) | BLOCK |
| `lint-selftest` | T1/T3-engine unittest | always (no network) | BLOCK |
| `plugin-validate-cli` | T2 (M5) | when `claude` is installable (auth-gating detected from validate output -> skip-with-message) | BLOCK if it runs, else skip-with-message |
| `prompt-judge` | T3 | when Anthropic creds present | BLOCK* (crit floor) / ADVISORY summary |

There is no separate `manifest-validate-py` job: M1–M4 (the Python manifest
checks) run *inside* `prompt-lint`, because `lint_all.py` invokes
`check_manifest` as part of the Tier-1 aggregate.

## Coverage map (FR/NFR → checks)

| Requirement | Covered by |
| --- | --- |
| FR-1 orchestrator exit conditions | RF-4 (command refs resolve) + ES-1/2 (iteration guard + escalation block) + JD-5 (loop soundness) + J4 (internal exit-condition consistency, advisory). NOTE: no check verifies fidelity to the authoritative FR-1 stage-table row — the judge is never given that table, so J4 only checks that the command states its exit condition consistently within its own sections. |
| FR-6 review triage / thresholds | ST-1 (generic command spine), JD-3 (degrade-path soundness) — these are all that is statically/judge-checkable here. The 21/21 skill-applicability triage with no silent skips is a *runtime-evidence* concern (it depends on observed per-run behavior), NOT statically checkable, so it is intentionally NOT pinned by any check in this layer. |
| FR-7/FR-12 QA black-box | L2, L33, JD-9 — L2 fires only on body phrasing; L33 enforces qa read-only tools structurally (name-targeted, body-independent: a qa-named command/agent must not list Write/Edit in its allowlist); JD-9 judges black-box discipline |
| FR-9..14 agent contracts | L3, L6, ST-2, RF-5, JD-1/2/3 |
| FR-15 generalized 21 skills | L4, L7, L12, ST-3, RF-6, JD-1/2/6, GN-1, JD-7 |
| FR-16 meta-guides | L5, L30, JD-10 — L30 pins the verbatim BMAD triage clause ("no silent skips / every skill verdict recorded") in any DECISION-named meta-guide |
| FR-17 profile schema | RF-7 |
| FR-18 shipped scripts | RF-1 |
| FR-19 manifest | MF-1..5 |
| FR-20 CI exists | the workflow itself + lint-selftest |
| NFR-2 generalization | GN-1, JD-7 |
| NFR-4 degrade paths | L18, JD-3 |
| NFR-6 loop safety | ES-1/2, JD-5 |
| NFR-7 no vendored assets | GN-2 |
| NFR-8 docs accuracy | RF-7, JD-2 (advisory) |
| ADR-8 driver/model | L8 |
| ADR-9 release tagging | MF-2/3/4 |
| ADR-11 meta-guides loose | L5, L7, RF-3 |
