---
name: load-testing
description: Use when adding or changing a K6 load-test scenario under tests/Load/scripts/ and its latency budget in tests/Load/config.json.dist, or when a smoke load-test run or its required PR check fails on a crossed budget or a failed check. Skip when capabilities.load_testing is false (print SKIPPED, write no scenario, never run K6 directly). Not for unit, integration, end-to-end or mutation tests (use testing-workflow), not for the catalogue of all quality bars (use quality-standards), and not for tuning the slow SQL a breach points at (use query-performance-analysis).
---

# Load Testing

## Profile keys consumed

- `capabilities.load_testing` — whether the repository ships a K6 load-test kit with a mapped smoke target; false takes the skip path of the capability gate.
- `make.smoke_load_tests` — the gate target that runs every scenario with the smoke profile in an isolated production-image environment; the only load target the plugin's stages refer to, and only to record or judge it.
- `make.load_tests` — the target that runs every scenario with all four profiles; guidance for a human measurement only, never run by a command, an agent or this skill.
- `quality.max_smoke_budget_breaches` — the ceiling on smoke budget breaches; its only legal value is 0.

## Repository precedence

Read `.claude/skills/load-testing/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line.

The repository skill and the repository's `docs/load-testing.md` hold the kit's own rules: the profiles, the budget rule, the table of measured values and the steps for adding a scenario. Read both before the first edit. When the repository has no such skill file, the rules below stand alone. When the repository skill and this skill disagree, follow the repository skill and record the difference in the evidence; a disagreement never permits relaxing a budget.

## Capability gate

Check `capabilities.load_testing` before anything else, then `make.smoke_load_tests`.

- **False:** the repository has no load-test kit. Print `SKIPPED: capabilities.load_testing is false`, record the smoke row as `not run (capability absent)`, print the verdict line `load-testing: SUCCESS-WITH-REPORT` and stop. Never create `tests/Load/`, never write a scenario, and never run K6, a runner script or a container image of K6 directly.
- **True and `make.smoke_load_tests` mapped:** the designed path (the profile generator sets the capability only when `tests/Load/` exists and the smoke target is mapped); continue with the Steps.
- **True and `make.smoke_load_tests` null** (a hand-edited profile): write the scenario and its configuration by the Steps, record the smoke row as `not run (capability absent)` (degrade D1), end `SUCCESS-WITH-REPORT` and never report the budget as proven.

## Context

- **The kit.** A scenario is one script `tests/Load/scripts/<scenario>.js` plus one entry `/endpoints/<scenario>` in `tests/Load/config.json.dist`; the runners discover scenarios by file name, so no runner needs an edit. Every entry declares the four profiles `smoke`, `average`, `stress` and `spike`, each with a latency budget `threshold` in milliseconds, a request rate `rps`, the pre-allocated virtual users `vus` and a `duration`. The helpers under `tests/Load/utils/` turn an entry into K6 options and thresholds; [reference/configuration.md](reference/configuration.md) describes every field and the shape of each profile.
- **Where each profile runs.** Only the smoke profile is a gate: the target mapped by `make.smoke_load_tests` runs it in pull-request CI as a required check, and the plugin's finish-pr stage judges that check. The implement and review stages never run it and record `<smoke target>: not run (deferred to PR CI)`, where `<smoke target>` is the value of `make.smoke_load_tests`. The target mapped by `make.load_tests` runs all four profiles one after the other; it exists for a human who measures the larger profiles on demand, and no plugin component runs it.
- **The isolated environment.** The load targets build the production image, start a compose project of their own (never the development stack), prepare its database, run the scenarios against it and remove the project with its volumes on every exit path. A failed run prints the project's logs, the service's included, before the removal; that log is the first evidence of a slow path.
- **The budget.** The bar `quality.max_smoke_budget_breaches` is 0: one crossed smoke threshold or one failed check rate fails the gate. Its source is the protected `tests/Load/config.json.dist`, whose thresholds the helpers under `tests/Load/utils/` turn into K6 thresholds; the protected items are read at runtime (`cargo xtask config-guard --list`), never assumed. A budget is quoted from that file in the evidence, never copied from this skill, and never raised, removed or worked around.
- **Supporting files.** REST scenarios follow [reference/rest-api-patterns.md](reference/rest-api-patterns.md), GraphQL scenarios follow [reference/graphql-patterns.md](reference/graphql-patterns.md), shared request helpers follow [reference/utils-extensions.md](reference/utils-extensions.md), and failures are diagnosed with [reference/troubleshooting.md](reference/troubleshooting.md).

A sourced example of the protected load-test items in a template-derived repository, as the guard lists them:

```text # profile-example
$ cargo xtask config-guard --list | grep '^tests/Load/'
tests/Load/eslint.config.js
tests/Load/utils/thresholdsBuilder.js
tests/Load/config.json.dist#/endpoints/health/smoke/threshold
tests/Load/config.json.dist#/endpoints/health/average/threshold
tests/Load/config.json.dist#/endpoints/health/stress/threshold
tests/Load/config.json.dist#/endpoints/health/spike/threshold
```

## Task

Add or change one K6 scenario per operation, with its configuration entry, the template's way: deterministic requests, checks on the exact success response, options built only by the kit's helpers, and budgets that follow the repository's budget rule. Keep every existing budget as it is, hold `quality.max_smoke_budget_breaches` at 0, and when the smoke gate fails, fix the slow path within at most five fix-and-measure iterations; report the result as the evidence block and one verdict line.

## Success criteria

- The new or changed script lives under `tests/Load/scripts/`, its file stem equals its `scenarioName` and its `/endpoints/<scenario>` key, and its options come unmodified from the kit's scenario helper.
- The entry declares all four profiles with a positive numeric `threshold`, and no threshold present on the base commit was raised or removed; no smoke `rps`, `vus` or `duration` of an existing scenario was lowered.
- Every protected load-test item listed by `cargo xtask config-guard --list` is unchanged.
- The smoke row reads `not run (deferred to PR CI)` in implement and review, and the required smoke check passed in finish-pr; or the row reads `not run (capability absent)` on a degrade path.
- `tests/Load/config.json` and `tests/Load/results/` stay untracked.

## Steps

### 1. Read the kit and quote the budgets

1. Read `.claude/skills/load-testing/SKILL.md`, `docs/load-testing.md`, the shipped example scenario under `tests/Load/scripts/` and the helpers under `tests/Load/utils/`.
2. List the protected load-test items through the execution route of [verification-workflow](../verification-workflow/SKILL.md) (host, or the container route in container mode):

   ```bash
   cargo xtask config-guard --list | grep '^tests/Load/'
   ```

   When neither the host toolchain nor the container route is available, read the same items from `protected-config.toml` with python3 `tomllib` (python3 3.11 or newer) and record the fallback in the evidence:

   ```bash
   python3 -c 'import tomllib; c = tomllib.load(open("protected-config.toml", "rb")); items = c.get("files", []) + c.get("directories", []) + ["%s#%s" % (v["file"], p) for v in c.get("json_values", []) for p in v.get("pointers", [])]; print("\n".join(i for i in items if i.startswith("tests/Load/")))'
   ```

3. Quote the budget of every existing scenario from the live file and keep the output for the evidence:

   ```bash
   python3 -c 'import json; c = json.load(open("tests/Load/config.json.dist")); print("\n".join("%s %s threshold %s ms" % (s, p, c["endpoints"][s][p]["threshold"]) for s in sorted(c["endpoints"]) for p in ("smoke", "average", "stress", "spike")))'
   ```

### 2. Decide the scenario

1. One scenario per operation: a create, a read of one item, a list page or a GraphQL operation each get their own script; never a script that picks operations at random.
2. Name the scenario after the operation in camelCase (`create<Entity>`, `get<Entity>`, `list<Entities>`; GraphQL scenarios prefixed `graphQL` unless the repository already uses another convention). The name is the file stem, the `scenarioName` constant and the configuration key.
3. Write a GraphQL scenario only when the service's router serves a GraphQL endpoint (its contract snapshot and router say so); otherwise write REST scenarios only.
4. Read the operation's request and response shape from the repository's contract snapshot or handler, never from this skill's examples. Endpoints in the examples are written `<path>`.

### 3. Write the script

Follow [reference/rest-api-patterns.md](reference/rest-api-patterns.md) or [reference/graphql-patterns.md](reference/graphql-patterns.md). In every script:

- import the kit's `Utils` and `ScenarioUtils`, and export `options` exactly as `scenarioUtils.getOptions()` returns them; never spread, replace or extend `options.thresholds` or the scenarios in the script;
- derive every unique value from the K6 globals `__VU` and `__ITER`, never from random numbers or the wall clock, so a run is reproducible;
- assert the exact success status (and, for GraphQL, the absence of `errors`) through `utils.checkResponse` with a descriptive check name;
- create dependencies in `setup()` and remove what the scenario created in `teardown()` when the contract offers a delete operation; the isolated environment removes its database afterwards, so the scenario never needs a shared service;
- use only the K6 globals (`__ENV`, `__VU`, `__ITER`, `open`), no `console`, and no remote module imports; shared request code goes into a helper module as [reference/utils-extensions.md](reference/utils-extensions.md) shows.

### 4. Add the configuration entry and its budget

1. Add `/endpoints/<scenario>` to `tests/Load/config.json.dist` with the four profiles in the shapes of [reference/configuration.md](reference/configuration.md); copy the shape of an existing entry, not its numbers.
2. Set each `threshold` by the budget rule of `docs/load-testing.md`, quoted in the evidence with its source. Without a hosted-runner measurement for the new scenario, the rule's ceiling for that profile is the budget; once a measurement exists, the rule derives a budget at or below the ceiling. Never pick a number above the rule's result. When the repository states no budget rule, record `budget rule: absent` and give each profile a `threshold` no higher than the tightest existing budget of the same profile.
3. Never change an existing scenario's `threshold`, and never lower its smoke `rps`, `vus` or `duration`; both weaken the gate.
4. When a measurement exists, add a row to the measured-values table of `docs/load-testing.md` and keep the documentation in step with [documentation-sync](../documentation-sync/SKILL.md).

The budget rule as the template states it in `docs/load-testing.md` (quoted, read the live file):

```text # profile-example
budget = min(ceiling, max(50, 3 x measured p99 rounded up to 10))
ceilings: smoke 500 ms, average 200 ms, stress 1000 ms, spike 5000 ms
```

### 5. Lint, then the smoke gate

1. The load-test JavaScript is linted and format-checked by a target of the repository's preflight gate stage (the stage list is read at runtime, never from this skill); run that stage through [verification-workflow](../verification-workflow/SKILL.md) and fix the code, never the lint configuration.
2. Branch on `make.smoke_load_tests`:
   - **mapped, in the implement or review stage:** never run it. Record `<smoke target>: not run (deferred to PR CI)`.
   - **mapped, in the finish-pr stage:** the measurement is the required PR check that runs the smoke target (read its name from `docs/repository-settings.md`): a passed check is measured 0; a failed check is `≥ 1` and goes to step 6.
   - **mapped, anywhere else** (a gate stage whose target list includes it, or a local run on the engineer's request): run `make` with the target mapped by `make.smoke_load_tests` only through the execution route of [verification-workflow](../verification-workflow/SKILL.md) (in the background, logged under `target/rust-sdlc/logs/`). Exit 0 is measured 0; any other exit is `≥ 1 (exit <n>)` and goes to step 6. The target needs a reachable Docker engine. Without one, a calling stage applies its own Docker rule (degrade D2: it escalates); an optional local run records `<smoke target>: not run (no Docker)`, leaves the measurement to the required PR check and ends `SUCCESS-WITH-REPORT`. A local run on a busy machine can cross the budget from noise; the required PR check is the measurement that counts, and noise is never a reason to raise a budget.
   - **null:** record `<smoke target>: not run (capability absent)` and end `SUCCESS-WITH-REPORT`; never substitute a runner script or a raw K6 call.
3. Branch on `make.load_tests`:
   - **mapped:** name it in the evidence as the human's on-demand four-profile run (for example, to measure the larger profiles on comparable hardware under the budget rule); never run it.
   - **null:** record that no four-profile target exists; the larger profiles keep the budgets the repository rule assigns, and nothing replaces the missing target.

### 6. Fix a breach within the budget

A failed smoke run or a failed required smoke check is one breach or more, measured as `≥ 1 (exit <n>)` against the bound 0. Classify it first ([reference/troubleshooting.md](reference/troubleshooting.md)): a crossed latency threshold, a failed check rate, or an environment failure before any request (an unhealthy environment, no scenario found, an unknown scenario, a configuration error).

1. Read the run's summary for the profile and scenario that failed, then the service log the isolated environment printed. Find the slow or failing path by its root cause:
   - repeated or unindexed queries: [query-performance-analysis](../query-performance-analysis/SKILL.md);
   - blocking work or a lock held across `.await`: [async-runtime-safety](../async-runtime-safety/SKILL.md);
   - an expensive read that is hot and safe to cache: [cache-management](../cache-management/SKILL.md), only when its conditions hold;
   - a failed check: the request is wrong (payload, headers, missing setup data) or the endpoint has a bug; fix the request only when the contract says the scenario is wrong, otherwise fix the endpoint.
2. Fix one root cause per iteration, add or adjust the unit or integration test that pins it ([testing-workflow](../testing-workflow/SKILL.md)), and measure again: in finish-pr the next measurement is the re-run required check, otherwise a local smoke run of step 5.
3. Log `load-testing iteration <n>/5: <scenario> <profile> -> <passed | failed: what crossed>`. The budget is 5 iterations; inside a stage the stage's own counter governs (in finish-pr, its CI-fix counter) and these iterations count against it, never in addition. The counter never resets within a run.
4. Passed: print the `SUCCESS` verdict. Still failing after iteration 5/5, or a fix that would need a protected change (degrade D23): stop and hand the calling stage the escalation block below. Raising a budget is never the way out.

```text
=== SDLC ESCALATION ===
stage: <calling stage id>
iteration: <n>/<cap>[ (<counter label>)]
exit_condition: <the calling stage's exit string, verbatim>
status: NOT MET
blocking_finding: <smoke check name> + <check URL> | <smoke target> exit <n>: <scenario> <profile> crossed <what> (budget quoted from tests/Load/config.json.dist)
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: find the slow path of <scenario> in a dedicated story, the budget staying as the protected file states it | for D23: the protected change to <path>, decided by a human under the approval label named in protected-config.toml, in a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1
=== END ===
```

### 7. Report the evidence and the verdict

```text
load-testing evidence
capabilities.load_testing: true | false
scenario: <scenario> -> tests/Load/scripts/<scenario>.js, /endpoints/<scenario> in tests/Load/config.json.dist
budgets (tests/Load/config.json.dist): <scenario> smoke <threshold> ms, average <threshold> ms, stress <threshold> ms, spike <threshold> ms
budget rule (docs/load-testing.md): <quoted rule> | absent
protected load-test items (config-guard --list): <n> listed, unchanged
<smoke target>: passed | failed | not run (deferred to PR CI) | not run (no Docker) | not run (capability absent)
quality.max_smoke_budget_breaches: measured <0 | ≥ 1 (exit <n>) | not measured> bound 0
four-profile run: guidance only (<value of make.load_tests> | unmapped)
load-testing: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
```

`SUCCESS`: every success criterion holds, with the smoke row deferred to PR CI or passed. `SUCCESS-WITH-REPORT`: the skip path, an unmapped smoke target, or an optional local run without Docker. `ESCALATED`: the escalation block above was printed.

## Constraints

- Never raise, remove or work around a `threshold` in `tests/Load/config.json.dist`, protected or not, and never lower an existing scenario's smoke `rps`, `vus` or `duration`, so that a run passes.
- Never edit a protected load-test item listed by `cargo xtask config-guard --list`; a needed change there is a protected-configuration escalation, never part of this skill.
- Never set `quality.max_smoke_budget_breaches` to any value but 0.
- Never override or extend `options.thresholds` in a scenario script, never remove or loosen a check, and never mark a failed check as expected.
- Never run the target mapped by `make.load_tests`, a runner script, K6 itself or a cloud load-test runner from a command, an agent or this skill; the smoke profile runs only through the target mapped by `make.smoke_load_tests`.
- Never point a load run at the shared development stack or at a service other than the isolated environment.
- Never use random numbers, wall-clock values, `console` or remote module imports in a scenario.
- Never commit `tests/Load/config.json` or anything under `tests/Load/results/`.
- Write example contexts as `<group>/<context>`, types as `<Entity>` and endpoints as `<path>`; read the real names from the repository.

## Verification

1. No budget present on the base commit was raised or removed, and no existing smoke load was lowered (prints nothing; `<base>` is the merge base the calling stage computed):

   ```bash
   python3 -c 'import json, subprocess, sys
   num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
   base = json.loads(subprocess.run(["git", "show", sys.argv[1] + ":tests/Load/config.json.dist"], capture_output=True, text=True, check=True).stdout)["endpoints"]
   head = json.load(open("tests/Load/config.json.dist")).get("endpoints", {})
   for s in sorted(base):
       for p in sorted(base[s]):
           old, new = base[s][p].get("threshold"), head.get(s, {}).get(p, {}).get("threshold")
           if num(old) and (not num(new) or new > old):
               print("RELAXED: /endpoints/%s/%s/threshold %s -> %s" % (s, p, old, new))
       for k in ("rps", "vus", "duration"):
           old, new = base[s].get("smoke", {}).get(k), head.get(s, {}).get("smoke", {}).get(k)
           if num(old) and (not num(new) or new < old):
               print("LOWERED: /endpoints/%s/smoke/%s %s -> %s" % (s, k, old, new))' <base>
   ```

2. Every scenario script has a complete entry with positive thresholds (prints nothing):

   ```bash
   python3 -c 'import json, pathlib
   c = json.load(open("tests/Load/config.json.dist"))["endpoints"]
   for f in sorted(pathlib.Path("tests/Load/scripts").glob("*.js")):
       e = c.get(f.stem, {})
       for p in ("smoke", "average", "stress", "spike"):
           t = e.get(p, {}).get("threshold")
           if not isinstance(t, (int, float)) or isinstance(t, bool) or t <= 0:
               print("INCOMPLETE: %s %s threshold %r" % (f.stem, p, t))'
   ```

3. Every protected load-test item is unchanged: a listed file is byte-equal to the base, a listed JSON pointer holds the base value (prints nothing):

   ```bash
   cargo xtask config-guard --list | grep '^tests/Load/' | python3 -c 'import json, subprocess, sys
   def at(doc, pointer):
       for part in pointer.split("/")[1:]:
           doc = doc.get(part.replace("~1", "/").replace("~0", "~")) if isinstance(doc, dict) else None
       return doc
   for item in sys.stdin.read().split():
       path, _, pointer = item.partition("#")
       if not pointer:
           if subprocess.run(["git", "diff", "--quiet", sys.argv[1], "--", path]).returncode:
               print("CHANGED: " + path)
           continue
       base = json.loads(subprocess.run(["git", "show", sys.argv[1] + ":" + path], capture_output=True, text=True, check=True).stdout)
       if at(base, pointer) != at(json.load(open(path)), pointer):
           print("CHANGED: " + item)' <base>
   ```

4. No script overrides the thresholds, and neither the local configuration nor a result is tracked (each command prints nothing):

   ```bash
   grep -rn 'thresholds' tests/Load/scripts
   git ls-files -- tests/Load/config.json tests/Load/results | grep -v '/\.gitignore$'
   ```

5. The evidence block holds the smoke row and the verdict line of step 7; a `SUCCESS` verdict in finish-pr cites the passed required smoke check.
