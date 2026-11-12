# REST API Load-Testing Patterns

This reference shows how a REST scenario of a template-derived Rust service is written. It belongs to the [load-testing skill](../SKILL.md); the configuration entry every scenario needs is described in [configuration.md](configuration.md).

The patterns assume the shape such a service exposes: JSON request and response bodies, identifiers as UUID strings in the path, plain JSON arrays for list pages, and problem documents (`application/problem+json`) for every failure. Endpoints are written `<path>`, relative to the base URL that `utils.getBaseHttpUrl()` returns (it already ends with the API prefix). Substitute the operations of your bounded context `<group>/<context>` and its `<Entity>`, and read every request field, response field and status code from the repository's OpenAPI snapshot or the handler, never from these examples.

## Script structure

Every scenario follows the structure of the shipped example scenario under `tests/Load/scripts/`:

```javascript
import http from 'k6/http';

import ScenarioUtils from '../utils/scenarioUtils.js';
import Utils from '../utils/utils.js';

const scenarioName = '<scenario>';

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);

export const options = scenarioUtils.getOptions();

const jsonParams = { headers: { 'Content-Type': 'application/json' } };

export function setup() {
  // Create, once and through the API, what every iteration needs; return it as plain data.
  return {};
}

// Name the default function after the scenario; add a `data` parameter to read what setup() returned.
export default function scenario() {
  // One operation per iteration, checked on its exact success response.
}

export function teardown() {
  // Remove what setup() created when the contract offers a delete operation.
}
```

Rules that hold for every pattern below:

- `scenarioName` equals the file stem and the `/endpoints/<scenario>` key.
- `options` is exported exactly as `scenarioUtils.getOptions()` returns it.
- Unique values come from `__VU` and `__ITER`; never from random numbers or the wall clock.
- One operation per iteration, so the latency budget measures that operation alone.
- Checks go through `utils.checkResponse` and assert the exact success status the contract documents, never a range such as "below 500".
- Only the K6 globals exist (`__ENV`, `__VU`, `__ITER`, `open`); `console` is forbidden by the lint and remote module imports are not used.

The shipped example scenario of a template-derived repository:

```javascript # profile-example
import http from 'k6/http';

import ScenarioUtils from '../utils/scenarioUtils.js';
import Utils from '../utils/utils.js';

const scenarioName = 'health';

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);

export const options = scenarioUtils.getOptions();

export default function health() {
  const response = http.get(`${utils.getBaseHttpUrl()}/health`);
  utils.checkResponse(response, 'is status 204', res => res.status === 204);
}
```

## Create

Each iteration creates one `<Entity>` with values unique to the virtual user and the iteration:

```javascript
export default function createEntity() {
  const payload = {
    name: `entity-${__VU}-${__ITER}`,
    // every other field the create request requires, within its documented limits
  };
  const response = http.post(
    `${utils.getBaseHttpUrl()}<path>`,
    JSON.stringify(payload),
    jsonParams
  );

  utils.checkResponse(response, 'is status 201', res => res.status === 201);
  utils.checkResponse(response, 'has a Location header', res => Boolean(res.headers.Location));
}
```

Send only the fields the contract defines: a request DTO that denies unknown fields rejects the request, and a missing JSON content type is rejected before the handler runs.

## Read one

`setup()` creates the items once; the iterations read them in a fixed rotation:

```javascript
const SEED_ITEMS = 10;

export function setup() {
  const ids = [];
  for (let i = 0; i < SEED_ITEMS; i += 1) {
    const response = http.post(
      `${utils.getBaseHttpUrl()}<path>`,
      JSON.stringify({ name: `entity-seed-${i}` }), // plus every other required field
      jsonParams
    );
    if (response.status !== 201) {
      throw new Error(`setup could not create a seed item: status ${response.status}`);
    }
    ids.push(response.json('id'));
  }
  return { ids };
}

export default function getEntity(data) {
  const id = data.ids[__ITER % data.ids.length];
  const response = http.get(`${utils.getBaseHttpUrl()}<path>/${id}`, {
    tags: { name: '<path>/{id}' },
  });

  utils.checkResponse(response, 'is status 200', res => res.status === 200);
  utils.checkResponse(
    response,
    'returns the requested item',
    res => res.status === 200 && res.json('id') === id
  );
}
```

- A `setup()` that cannot create its data throws, so the run fails visibly instead of measuring a stream of not-found responses.
- The `name` tag keeps one time series for the operation instead of one per identifier.
- `setup()` requests carry no profile tag, so seeding never counts against the budget.

## List a page

```javascript
export default function listEntities() {
  const response = http.get(`${utils.getBaseHttpUrl()}<path>?<paging query>`, {
    tags: { name: '<path>' },
  });

  utils.checkResponse(response, 'is status 200', res => res.status === 200);
  utils.checkResponse(
    response,
    'returns a page',
    res => res.status === 200 && Array.isArray(res.json())
  );
}
```

Read the paging parameter names and their bounds from the contract; a page size outside the documented range is a validation failure, not a measurement. Seed enough items in `setup()` that the page is full, so the budget measures a realistic page.

The paging query of a template-derived list operation:

```text # profile-example
GET <base URL><path>?page=1&itemsPerPage=30  ->  200, a JSON array of at most 30 items, newest first
```

## Update and delete

Write these scenarios only when the contract defines the operation.

- **Update:** seed items in `setup()`, then update `data.ids[__ITER % data.ids.length]` with values derived from `__VU` and `__ITER`, and check the documented success status.
- **Delete:** a deleted item cannot be deleted again, so each iteration creates its own item and deletes it. Both requests count against the budget; give each its own `name` tag so the summary separates them, and set the budget for the pair.

```javascript
export default function deleteEntity() {
  const created = http.post(
    `${utils.getBaseHttpUrl()}<path>`,
    JSON.stringify({ name: `entity-${__VU}-${__ITER}` }),
    Object.assign({ tags: { name: '<path> create' } }, jsonParams)
  );
  utils.checkResponse(created, 'is status 201', res => res.status === 201);
  if (created.status !== 201) {
    return;
  }
  const response = http.del(`${utils.getBaseHttpUrl()}<path>/${created.json('id')}`, null, {
    tags: { name: '<path>/{id} delete' },
  });

  // The delete status the contract documents (204 when the response has no body).
  utils.checkResponse(response, 'is the documented delete status', res => res.status === 204);
}
```

## Data generation

- Derive unique values from `__VU` and `__ITER` (`entity-${__VU}-${__ITER}`): reproducible within a run and unique across virtual users.
- Keep every value inside the limits the contract documents (lengths, ranges, formats); a value that fails validation measures the error path, not the operation.
- The isolated environment drops its database after every run, so data from an earlier run never collides; a scenario that would collide with its own earlier iterations needs a different derivation, not randomness.

## Failure responses

A failed request returns a problem document with `status`, `title`, an optional `detail` and, for a validation failure, `violations` with `propertyPath`, `message` and `code`. A check fails on the status; the cause is in the service log the isolated environment prints when the run fails (see [troubleshooting.md](troubleshooting.md)).

## Putting it together

A complete read scenario, ready to copy under `tests/Load/scripts/getEntity.js` once `<path>` and the payload are replaced:

```javascript
import http from 'k6/http';

import ScenarioUtils from '../utils/scenarioUtils.js';
import Utils from '../utils/utils.js';

const scenarioName = 'getEntity';
const SEED_ITEMS = 10;

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);

export const options = scenarioUtils.getOptions();

const jsonParams = { headers: { 'Content-Type': 'application/json' } };

export function setup() {
  const ids = [];
  for (let i = 0; i < SEED_ITEMS; i += 1) {
    const response = http.post(
      `${utils.getBaseHttpUrl()}<path>`,
      JSON.stringify({ name: `entity-seed-${i}` }), // plus every other required field
      jsonParams
    );
    if (response.status !== 201) {
      throw new Error(`setup could not create a seed item: status ${response.status}`);
    }
    ids.push(response.json('id'));
  }
  return { ids };
}

export default function getEntity(data) {
  const id = data.ids[__ITER % data.ids.length];
  const response = http.get(`${utils.getBaseHttpUrl()}<path>/${id}`, {
    tags: { name: '<path>/{id}' },
  });

  utils.checkResponse(response, 'is status 200', res => res.status === 200);
  utils.checkResponse(
    response,
    'returns the requested item',
    res => res.status === 200 && res.json('id') === id
  );
}
```

Then add `/endpoints/getEntity` to `tests/Load/config.json.dist` as [configuration.md](configuration.md) describes.
