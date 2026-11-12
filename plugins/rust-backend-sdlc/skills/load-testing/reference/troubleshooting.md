# Load-Testing Troubleshooting

This reference diagnoses a failed smoke run or a failed required smoke check of a template-derived K6 kit. It belongs to the [load-testing skill](../SKILL.md), whose bounded fix loop (at most five fix-and-measure iterations, then the escalation block) governs every fix below. Configuration fields are described in [configuration.md](configuration.md).

Work in this order: classify the failure, collect its evidence, find the root cause, fix it, measure again. A budget is never raised, a check is never loosened and a failing scenario is never removed so that a run passes.

## Classify the failure

| What the run shows | Class | Section |
| --- | --- | --- |
| the environment script stops before any request and prints the project's logs | environment | [Environment failures](#environment-failures) |
| the runner finds no scenario, or prints its usage line | discovery | [Discovery and configuration failures](#discovery-and-configuration-failures) |
| the run stops while loading a script (invalid threshold, unreadable configuration, a missing entry) | configuration | [Discovery and configuration failures](#discovery-and-configuration-failures) |
| the preflight gate stage reports the load-test lint or format check | lint | [Lint failures](#lint-failures) |
| the summary marks the check-rate threshold of a profile as crossed | failed checks | [Failed checks](#failed-checks) |
| the summary marks the latency threshold of a profile as crossed | budget breach | [Budget breaches](#budget-breaches) |
| the summary reports dropped iterations | generator saturation | [Dropped iterations](#dropped-iterations) |

The messages a template-derived kit prints for these classes:

```text # profile-example
with-load-test-stack.sh: the isolated environment '<project>-load' did not become healthy      (exit 2, logs follow)
with-load-test-stack.sh: refusing to use project '<name>': it must differ from the development project   (exit 2)
This target needs a reachable container engine (docker).                                        (exit 2)
Error: No load test scenarios found.                                                            (exit 1)
Usage: execute-load-test.sh <scenario> [runSmoke] [runAverage] [runStress] [runSpike] [htmlPrefix]   (exit 2)
Invalid threshold value
Failed to load configuration from config.json and config.json.dist: <error>; <error>
with-load-test-stack.sh: the command failed with exit status <n>; logs of project '<project>-load':
```

## Environment failures

These stop the run before the first request, so no budget was measured; they are fixed like any failed gate run, never recorded as a pass.

### The isolated environment does not become healthy

- **Causes:** the production image does not build, a migration fails on the fresh database, the service exits at start-up (a missing or invalid configuration value), or the published port is taken.
- **Evidence:** the project's logs, which the environment script prints before it removes the project.
- **Fix:** the root cause in the service, its migrations or its configuration. Reproduce through the repository's own targets on the development stack; never point a load run at the development stack instead.

### The environment refuses the project name

The isolated project must differ from the development project. Leave the project name at its default; never set it to the development project's name.

### No container engine is reachable

The load targets need Docker. An optional local run records the smoke row `not run (no Docker)`, leaves the measurement to the required PR check and ends `SUCCESS-WITH-REPORT`. Inside the implement and review stages the smoke target is not run anyway (`not run (deferred to PR CI)`); a stage that runs a gate stage containing it applies its own Docker rule and escalates.

### A leftover project holds the port

The environment script removes its project on every exit path, but a killed run can leave one behind. Remove only the leftover isolated project (its name carries the load-test suffix), never the development project or the shared development stack.

## Discovery and configuration failures

### No scenario is found

The runners list `tests/Load/scripts/*.js` by file name. An empty directory, a misspelt extension or a script in a subdirectory leaves nothing to run.

### The runner prints its usage line

The scenario name given to the single-scenario runner is not the file stem of a script under `tests/Load/scripts/`. The stem, the `scenarioName` constant and the `/endpoints/<scenario>` key must be the same string.

### The run stops with an invalid threshold

A profile's `threshold` is missing, zero, negative or a string. Give it a positive number by the budget rule; never delete the profile instead.

### The configuration cannot be loaded

Both `tests/Load/config.json` and `tests/Load/config.json.dist` failed to parse; the error names both. Note that a malformed local `tests/Load/config.json` is skipped silently in favour of the distributed file, and a well-formed local file wins over it entirely: when a local run behaves differently from CI, delete or fix the local file first.

### The script fails while loading a profile

`ScenarioUtils` found no `/endpoints/<scenario>` entry, or an entry without one of the four profiles, in the file `Utils` loaded. Check the local override first, then the distributed file.

### `setup()` or `teardown()` times out

The scenario helper sets both timeouts. Seed fewer items, or speed up the create path; never change the helper to lengthen them.

## Lint failures

| Finding | Cause | Fix |
| --- | --- | --- |
| `no-console` | a debugging statement | remove it; use descriptive check names and tags instead |
| `eqeqeq` | `==` or `!=` | use `===` or `!==` |
| `no-undef` | a global outside the K6 set (`require`, `process`, a Node module) | use the K6 API and the kit's helpers |
| `no-unused-vars` | an unused parameter, variable or caught error | remove it; use `catch {` without a binding |
| a Prettier difference | formatting | format the file with the repository's settings |

Fix the code, never the lint configuration; when `cargo xtask config-guard --list` lists it, a needed change is a protected-configuration escalation.

## Failed checks

A failed check counts against the check-rate threshold of its profile; one failed request in a short smoke run can be enough to cross it.

### Every request fails

| Symptom | Likely cause |
| --- | --- |
| status 0, connection refused | the run targets the wrong host or port: an exported `API_HOST` or `API_PORT`, or a local `tests/Load/config.json`, overrides the isolated environment |
| not found on every request | `<path>` repeats the API prefix that `utils.getBaseHttpUrl()` already ends with, or the composition root does not mount the context's router |
| unsupported media type | the request has no JSON content type |
| bad request or validation failed | the payload breaks a documented rule or carries a field the request DTO does not accept |
| payload too large | the request body exceeds the body limit |
| HTTP 200 with `errors` (GraphQL) | see the error table of [graphql-patterns.md](graphql-patterns.md) |

### Some requests fail

- **Conflicts or duplicates:** two virtual users send the same value to a unique field; derive values from `__VU` and `__ITER`.
- **Not found for seeded items:** `setup()` returned fewer items than the iterations read; let `setup()` throw on the first failed create.
- **Intermittent server errors under load:** a real defect (an exhausted connection pool, a blocking call in async code, a lock held across `.await`, a race between requests). Find it in the service log; the async-runtime-safety and query-performance-analysis skills cover the usual causes. A connection-pool size change is a configuration decision with its own documentation (see the configuration-management skill), never a way to hide a code path that holds connections too long.

Never mark a failing response as expected, widen a check to a status range, or drop a check.

## Budget breaches

### A latency threshold is crossed

1. Read the summary: which profile's threshold was crossed and by how much.
2. Read the HTML dashboard under `tests/Load/results/` for the shape over time: steadily high latency points at a slow path; latency that grows during the run points at saturation (a pool, a queue, a lock); isolated spikes point at contention or first-request initialisation.
3. Read the service log the environment printed on failure: each access line carries the route, the status and the duration, so the slow route stands out.
4. Find the root cause and fix it: repeated or unindexed queries (query-performance-analysis skill), blocking work in async code or a guard held across `.await` (async-runtime-safety skill), an expensive read that is safe to cache (cache-management skill, only when its conditions hold).
5. Pin the fix with a test and measure again through the [load-testing skill](../SKILL.md)'s smoke step.

The access line a template-derived service writes for each request:

```json # profile-example
{"level":"INFO","message":"request completed","http.response.status_code":200,"duration_ms":7,"span":{"name":"http.request","http.request.method":"GET","http.route":"/api<path>/{id}","request_id":"<id>"}}
```

### Dropped iterations

K6 drops an iteration when every pre-allocated virtual user is still busy at the next arrival: the responses are slower than the configured rate allows. The latency breach that comes with it is the problem to fix. Raising a profile's `vus` lets the generator reach the configured rate without lowering the load, so it is acceptable only when the latency stays within the budget; lowering `rps` or shortening `duration` never is.

### Local runs cross the budget while the PR check passes

A busy development machine adds noise; the repository's table of measured values records such runs. Re-run on an idle machine, and treat the required PR check as the measurement that counts. Noise is never a reason to raise a budget.

### The PR check fails while local runs pass

The hosted runner is the reference hardware of the budget rule, so the regression is real until shown otherwise. Read the check's log and the uploaded results artifact, and compare with the same check on the base branch.

## Debugging tips

- Run one scenario with the smoke profile only through the repository's single-scenario target (named in its own skill and in `docs/load-testing.md`); this is a local tool for the engineer, never a plugin stage's measurement.
- Name every check after what it asserts, so the summary says which assertion failed.
- Separate a functional bug from a performance problem with the repository's own integration or end-to-end test of the operation.
- Keep debugging output out of the scripts: the lint forbids `console`, and nothing temporary is committed.

When five iterations do not fix the failure, or the fix needs a protected change, stop and hand the calling stage the escalation block of the [load-testing skill](../SKILL.md).
