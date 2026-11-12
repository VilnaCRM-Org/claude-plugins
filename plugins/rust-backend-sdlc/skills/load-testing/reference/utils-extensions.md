# Extending the Utils Helpers

This reference shows how shared request code of K6 scenarios is added to a template-derived kit without changing what the existing scenarios measure. It belongs to the [load-testing skill](../SKILL.md); the scenario patterns that use these helpers are in [rest-api-patterns.md](rest-api-patterns.md) and [graphql-patterns.md](graphql-patterns.md).

## What the kit provides

Read the live files under `tests/Load/utils/` first; a repository may already have added helpers. A template-derived kit ships four modules:

| Module | Provides | Who may change it |
| --- | --- | --- |
| `utils.js` | `Utils`: the base URL from `API_HOST` and `API_PORT` or the configuration, `getConfig()` (the local configuration first, the distributed file as fallback, one error naming both on failure), `getBaseHttpUrl()`, `getEnv(name)` (`undefined` for an unset or empty value), `getCLIVariable(name)`, and `checkResponse(response, name, fn)` (a named K6 check that returns nothing) | additions only; never a change to behaviour other scenarios rely on |
| `scenarioUtils.js` | `ScenarioUtils`: the options, profile switches and start times of one scenario | not changed by a scenario change: its arithmetic shapes every scenario's load |
| `scenariosBuilder.js` | the K6 executors and stages of each profile | not changed by a scenario change, for the same reason |
| `thresholdsBuilder.js` | the latency and check-rate thresholds of each profile | never: it turns the protected budgets into thresholds; whether the file itself is protected is read with `cargo xtask config-guard --list` |

## When to extend

Extend when two or more scenarios repeat the same request code: JSON request parameters, a GraphQL call, seeding items in `setup()`, a guarded JSON read, a check whose result decides the next request. Code that one scenario needs stays in that scenario.

Put the extension in a new module under `tests/Load/utils/` and import it from the scenarios that need it. A new module cannot change the measurement of a scenario that does not import it, so it never weakens the smoke gate.

## Option 1: composition (preferred)

A small client takes a `Utils` instance and adds the request helpers; `Utils` and `ScenarioUtils` stay untouched:

```javascript
// tests/Load/utils/apiClient.js
import { check } from 'k6';
import http from 'k6/http';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

/**
 * JSON and GraphQL requests against the service under test.
 */
export default class ApiClient {
  /**
   * @param {import('./utils.js').default} utils
   */
  constructor(utils) {
    this.baseUrl = utils.getBaseHttpUrl();
  }

  /**
   * Sends a JSON body; `name` tags the request with its operation.
   *
   * @param {string} path
   * @param {object} body
   * @param {string} name
   */
  postJson(path, body, name) {
    return http.post(`${this.baseUrl}${path}`, JSON.stringify(body), {
      headers: JSON_HEADERS,
      tags: { name },
    });
  }

  /**
   * Sends a GET request; `name` tags the request with its operation.
   *
   * @param {string} path
   * @param {string} name
   */
  get(path, name) {
    return http.get(`${this.baseUrl}${path}`, { tags: { name } });
  }

  /**
   * Runs one GraphQL operation with its variables.
   *
   * @param {string} path
   * @param {string} query
   * @param {object} variables
   * @param {string} name
   */
  graphql(path, query, variables, name) {
    return this.postJson(path, { query, variables }, name);
  }

  /**
   * A named check that returns its result, so a scenario can stop an iteration early.
   *
   * @param {import('k6/http').RefinedResponse<'text'>} response
   * @param {string} checkName
   * @param {(response: import('k6/http').RefinedResponse<'text'>) => boolean} checkFunction
   * @returns {boolean}
   */
  checked(response, checkName, checkFunction) {
    return check(response, { [checkName]: res => checkFunction(res) });
  }
}
```

A scenario that uses it:

```javascript
import ApiClient from '../utils/apiClient.js';
import ScenarioUtils from '../utils/scenarioUtils.js';
import Utils from '../utils/utils.js';

const scenarioName = '<scenario>';

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);
const api = new ApiClient(utils);

export const options = scenarioUtils.getOptions();

export default function createEntity() {
  const response = api.postJson('<path>', { name: `entity-${__VU}-${__ITER}` }, 'create<Entity>');
  api.checked(response, 'is status 201', res => res.status === 201);
}
```

## Option 2: a subclass

When every helper needs the configuration as well, a subclass keeps one object. `ScenarioUtils` calls only `getConfig()` and `getCLIVariable()`, which the subclass inherits unchanged:

```javascript
// tests/Load/utils/entityUtils.js
import http from 'k6/http';

import Utils from './utils.js';

/**
 * `Utils` plus the requests of the <Entity> scenarios.
 */
export default class EntityUtils extends Utils {
  /**
   * Creates `count` items and returns their identifiers; throws when one cannot be created.
   *
   * @param {number} count
   * @returns {string[]}
   */
  seedEntities(count) {
    const ids = [];
    for (let i = 0; i < count; i += 1) {
      const response = http.post(
        `${this.getBaseHttpUrl()}<path>`,
        JSON.stringify({ name: `entity-seed-${i}` }),
        { headers: { 'Content-Type': 'application/json' }, tags: { name: 'seed' } }
      );
      if (response.status !== 201) {
        throw new Error(`could not create a seed item: status ${response.status}`);
      }
      ids.push(response.json('id'));
    }
    return ids;
  }
}
```

The scenario constructs `new EntityUtils()` instead of `new Utils()` and passes it to `ScenarioUtils` as before. Never override an inherited method in the subclass.

## Common helpers

| Helper | Purpose | Rule |
| --- | --- | --- |
| guarded JSON read | return `undefined` instead of throwing on a body that is not JSON | an exception inside a check aborts the iteration instead of failing the check |
| check with a result | return the check's boolean so the next request runs only after a success | built on K6's `check`, which returns the result; the kit's `checkResponse` returns nothing |
| seed factory | create the items `setup()` needs and return their identifiers | throws on the first failure, so a broken setup fails the run visibly |
| payload builder | build a request body from `__VU` and `__ITER` | a pure function: the same inputs give the same body |
| GraphQL result check | HTTP 200, no `errors`, a non-null result field | see [graphql-patterns.md](graphql-patterns.md) |

A guarded JSON read:

```javascript
/**
 * The value at `selector` of a JSON body, or `undefined` when the body is not JSON.
 *
 * @param {import('k6/http').RefinedResponse<'text'>} response
 * @param {string} selector
 */
export function jsonField(response, selector) {
  try {
    return response.json(selector);
  } catch {
    return undefined;
  }
}
```

## Rules for every helper

- Stateless: no module-level value that changes between iterations; a helper that remembers earlier responses makes the measurement depend on the order of iterations.
- Deterministic: no random numbers and no wall-clock values; unique values come from `__VU` and `__ITER`.
- K6 only: the globals `__ENV`, `__VU`, `__ITER` and `open` exist, Node modules and `console` do not, and no module is imported from a remote URL.
- `open()` works only while the module is initialised, so a helper that reads a file is constructed at module level, never inside the default function, `setup()` or `teardown()`.
- Documented: every exported function and method carries a JSDoc comment, as `utils.js` does.
- Lint-clean: the kit's ESLint and Prettier settings apply; fix the code, never the lint configuration.
- No thresholds: a helper never adds, spreads or replaces `options.thresholds`, and never sets the `test_type` tag the latency threshold selects on.

The formatting settings a template-derived repository applies to the kit:

```text # profile-example
.prettierrc.yml: semi true, trailingComma es5, singleQuote true, printWidth 100, tabWidth 2, arrowParens avoid
tests/Load/eslint.config.js: @eslint/js recommended, ecmaVersion 2023 modules, globals __ENV __VU __ITER open, no-console error, eqeqeq error
```

## Verifying an extension

The kit has no unit-test harness for its helpers. An extension is verified by the repository's preflight gate stage (lint and format check) and by the smoke gate of every scenario that imports it, as the [load-testing skill](../SKILL.md) describes: inside the implement and review stages the smoke row is deferred to PR CI, and the required smoke check in the pull request measures every importing scenario. A helper whose change makes an importing scenario slower is a breach like any other: fix the helper, never the budget.
