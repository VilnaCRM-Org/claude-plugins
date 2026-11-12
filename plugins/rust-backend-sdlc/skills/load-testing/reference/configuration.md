# K6 Load-Test Configuration

This reference describes the scenario configuration of a template-derived K6 kit: the file `tests/Load/config.json.dist`, the helpers under `tests/Load/utils/` that turn it into K6 options, the environment variables the runners pass, and the rules that keep every budget tighten-only. It belongs to the [load-testing skill](../SKILL.md). Read the live files before relying on any detail here; concrete numbers appear only in fences marked `# profile-example`, quoted from a template-derived repository.

## File structure

`tests/Load/config.json.dist` is one JSON object:

| Key | Meaning |
| --- | --- |
| `apiHost` | host of the service under test when `API_HOST` is unset |
| `apiPort` | port of the service under test when `API_PORT` is unset |
| `delayBetweenScenarios` | pause in seconds between two profiles of one multi-profile run |
| `endpoints` | one object per scenario, keyed by the scenario name (the script's file stem) |

Each scenario object declares the four profiles `smoke`, `average`, `stress` and `spike`. The shape, with placeholders:

```text
{
  "apiHost": "<host>",
  "apiPort": "<port>",
  "delayBetweenScenarios": <seconds>,
  "endpoints": {
    "<scenario>": {
      "smoke": { "threshold": <ms>, "rps": <n>, "vus": <n>, "duration": <seconds> },
      "average": { "threshold": <ms>, "rps": <n>, "vus": <n>, "duration": { "rise": <s>, "plateau": <s>, "fall": <s> } },
      "stress": { "threshold": <ms>, "rps": <n>, "vus": <n>, "duration": { "rise": <s>, "plateau": <s>, "fall": <s> } },
      "spike": { "threshold": <ms>, "rps": <n>, "vus": <n>, "duration": { "rise": <s>, "fall": <s> } }
    }
  }
}
```

The file as a template-derived repository ships it, with its one example scenario:

```json # profile-example
{
  "apiHost": "localhost",
  "apiPort": "8081",
  "delayBetweenScenarios": 60,
  "endpoints": {
    "health": {
      "smoke": { "threshold": 50, "rps": 10, "vus": 5, "duration": 10 },
      "average": {
        "threshold": 200,
        "rps": 25,
        "vus": 25,
        "duration": { "rise": 3, "plateau": 10, "fall": 3 }
      },
      "stress": {
        "threshold": 1000,
        "rps": 150,
        "vus": 150,
        "duration": { "rise": 3, "plateau": 10, "fall": 3 }
      },
      "spike": { "threshold": 5000, "rps": 200, "vus": 200, "duration": { "rise": 5, "fall": 5 } }
    }
  }
}
```

A local `tests/Load/config.json` (git-ignored) is read before the distributed file, and the distributed file is the fallback. The local file changes only a local run: it is never committed, never evidence of a budget, and never a way around one.

## Profile fields

| Field | Type | Meaning | Rule |
| --- | --- | --- | --- |
| `threshold` | positive number | the latency budget of the profile in milliseconds, at the percentile the threshold builder applies | any other value stops the run with `Invalid threshold value` before the first request; never raised so that a run passes |
| `rps` | positive integer | the arrival rate in requests per second: constant for `smoke`, the ramp target for the other profiles | never lowered on an existing scenario's `smoke` profile |
| `vus` | positive integer | the virtual users K6 pre-allocates to sustain the rate | too few for the observed latency makes K6 drop iterations (see [troubleshooting.md](troubleshooting.md)) |
| `duration` | integer or object | `smoke`: seconds; `average` and `stress`: `rise`, `plateau`, `fall` in seconds; `spike`: `rise`, `fall` in seconds | never shortened on an existing scenario's `smoke` profile |

## Profile shapes

The scenario builder under `tests/Load/utils/` maps each enabled profile to one K6 scenario named after the profile and tags its requests with `test_type: <profile>`:

| Profile | K6 executor | Stages |
| --- | --- | --- |
| `smoke` | `constant-arrival-rate` | `rps` per second for `duration` seconds |
| `average` | `ramping-arrival-rate` from 0 | up to `rps` over `rise`, hold over `plateau`, down to 0 over `fall` |
| `stress` | `ramping-arrival-rate` from 0 | up to `rps` over `rise`, hold over `plateau`, down to 0 over `fall` |
| `spike` | `ramping-arrival-rate` from 0 | up to `rps` over `rise`, down to 0 over `fall` |

The scenario helper computes each profile's start time from the durations of the profiles before it plus `delayBetweenScenarios`. The per-profile runners enable one profile at a time; only the full run enables all four.

## How a script gets its options

A scenario script never writes its own options:

```javascript
const scenarioName = '<scenario>';

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);

export const options = scenarioUtils.getOptions();
```

- `new ScenarioUtils(utils, scenarioName)` reads `/endpoints/<scenario>`; a missing entry fails when the script is loaded.
- `getOptions()` returns the setup and teardown timeouts, the enabled profiles as K6 scenarios and their thresholds.
- The runners switch profiles with the K6 environment variables `run_smoke`, `run_average`, `run_stress` and `run_spike` (the string `false` disables one). A script never reads or sets them.
- The threshold builder adds, per enabled profile, one latency threshold on `http_req_duration{test_type:<profile>}` and one check-rate threshold on `checks{scenario:<profile>}`. Requests made in `setup()` and `teardown()` run outside the profiles, so they carry neither tag and never count against a budget.

The threshold builder of a template-derived repository and the options it yields for the smoke profile of the example scenario:

```javascript # profile-example
// tests/Load/utils/thresholdsBuilder.js
this.thresholds[`http_req_duration{test_type:${scenarioName}}`] = [`p(99)<${config.threshold}`];
this.thresholds[`checks{scenario:${scenarioName}}`] = ['rate>0.99'];

// options.thresholds for the smoke profile of tests/Load/config.json.dist
// { 'http_req_duration{test_type:smoke}': ['p(99)<50'], 'checks{scenario:smoke}': ['rate>0.99'] }
```

## Budgets

### Where a budget comes from

1. The protected items are read at runtime with `cargo xtask config-guard --list` (falling back to a python3 `tomllib` read of `protected-config.toml`). A listed file is protected as a whole; a listed `tests/Load/config.json.dist#<pointer>` protects one JSON value.
2. The budget rule and the table of measured values live in the repository's `docs/load-testing.md`. A new scenario takes its budgets from that rule, quoted in the evidence with its source; without a measurement on the reference hardware the rule's ceiling applies.
3. A budget that the protected list does not name yet (a new scenario's) is still tighten-only for the plugin: once committed, it is never raised. Adding its pointers to the protected list is a maintainer's labelled change, never part of a scenario change.

The protected load-test items of a template-derived repository and the rule its `docs/load-testing.md` states:

```text # profile-example
$ cargo xtask config-guard --list | grep '^tests/Load/'
tests/Load/eslint.config.js
tests/Load/utils/thresholdsBuilder.js
tests/Load/config.json.dist#/endpoints/health/smoke/threshold
tests/Load/config.json.dist#/endpoints/health/average/threshold
tests/Load/config.json.dist#/endpoints/health/stress/threshold
tests/Load/config.json.dist#/endpoints/health/spike/threshold

budget = min(ceiling, max(50, 3 x measured p99 rounded up to 10))
ceilings: smoke 500 ms, average 200 ms, stress 1000 ms, spike 5000 ms
```

### What counts as relaxing a budget

Each of these weakens the smoke gate and is never done so that a run passes:

- raising or removing a `threshold`, or removing a profile or a scenario that has one;
- lowering an existing scenario's `smoke` `rps` or `vus`, or shortening its `duration`;
- adding, spreading or replacing `thresholds` in a scenario script;
- editing the threshold builder, the scenario helpers' arithmetic or the lint configuration;
- pointing a run at a different service, or measuring with a local `tests/Load/config.json`.

A protected budget changes only through the repository's protected-configuration process (the approval label named in `protected-config.toml` and a recorded measurement in `docs/load-testing.md`), decided by a human; a plugin stage escalates instead.

## Environment variables

| Variable | Read by | Meaning |
| --- | --- | --- |
| `API_HOST`, `API_PORT` | `Utils` | the service under test; the load targets set them to the isolated environment, so `apiHost` and `apiPort` matter only for a direct run against an already running service |
| `K6_IMAGE` | the scenario runner | the K6 container image, pinned in the repository's tool-version file |
| `run_smoke`, `run_average`, `run_stress`, `run_spike` | `ScenarioUtils` | the profile switches, set by the runners |
| the isolated environment's project name, published port and image-build switch | the environment script | read their names and defaults from the header of the script the load targets wrap |

A script reads an optional variable through `utils.getEnv('<NAME>')`, which returns `undefined` for an unset or empty value. Never read a secret into a scenario; the isolated environment needs none.

The names and defaults a template-derived repository uses:

```text # profile-example
scripts/with-load-test-stack.sh: LOAD_TEST_PROJECT (default <directory>-load), LOAD_TEST_APP_PORT (default 18081), BUILD_IMAGE (default 1)
make/tool-versions.mk pins K6_IMAGE to grafana/k6:<version>@sha256:<digest>
```

## Tags and custom metrics

- A request to a URL that contains an identifier gets a `name` tag with a fixed template (`{ tags: { name: '<path>/{id}' } }`), so K6 keeps one time series per operation instead of one per identifier.
- Never set a `test_type` tag yourself: the scenario builder sets it and the latency threshold selects on it.
- A custom `Trend` or `Counter` metric is allowed for diagnosis; it never gets a threshold in the script.

## Results

Every run writes one self-contained HTML dashboard to `tests/Load/results/<prefix><scenario>.html`, the prefix naming the runner's profile, and prints the K6 end-of-run summary. The directory is git-ignored apart from its own ignore file; CI uploads it as an artifact (its name and retention are in the repository's `docs/load-testing.md`).

## Validating a configuration change

Before the lint and the smoke gate, check the file and the scripts together (prints nothing when every script has a complete entry):

```bash
python3 -c 'import json, pathlib
c = json.load(open("tests/Load/config.json.dist"))["endpoints"]
shapes = {"smoke": int, "average": dict, "stress": dict, "spike": dict}
for f in sorted(pathlib.Path("tests/Load/scripts").glob("*.js")):
    e = c.get(f.stem)
    if not isinstance(e, dict):
        print("MISSING: /endpoints/%s" % f.stem)
        continue
    for p, shape in shapes.items():
        cfg = e.get(p, {})
        t = cfg.get("threshold")
        if not isinstance(t, (int, float)) or isinstance(t, bool) or t <= 0:
            print("BAD THRESHOLD: /endpoints/%s/%s %r" % (f.stem, p, t))
        if not isinstance(cfg.get("duration"), shape):
            print("BAD DURATION: /endpoints/%s/%s %r" % (f.stem, p, cfg.get("duration")))'
```

Then let the repository's preflight gate stage lint and format-check the JavaScript, and let the smoke gate measure the budget as the [load-testing skill](../SKILL.md) describes.
