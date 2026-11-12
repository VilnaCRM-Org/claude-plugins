# GraphQL Load-Testing Patterns

This reference shows how a GraphQL scenario of a template-derived Rust service is written. It belongs to the [load-testing skill](../SKILL.md) and applies only when the service's router serves a GraphQL endpoint (the repository then keeps a GraphQL schema snapshot); a service without one gets REST scenarios only ([rest-api-patterns.md](rest-api-patterns.md)). The configuration entry every scenario needs is described in [configuration.md](configuration.md).

The patterns assume the transport such a service exposes:

- one `POST` endpoint, written `<path>` relative to `utils.getBaseHttpUrl()`, that takes a JSON body `{ "query": ..., "variables": ... }`;
- an operation error comes back with HTTP 200 and an `errors` array whose entries carry a stable `extensions.code`, so a status check alone proves nothing;
- a body that is not a GraphQL request is rejected with a problem document before any resolver runs;
- field and argument names are camelCase (the GraphQL library renames the Rust snake_case names), and identifiers use the `ID` scalar holding the UUID string.

Read the operation names, argument names, input types and error codes from the repository's GraphQL schema snapshot, never from these examples. Substitute your bounded context `<group>/<context>` and its `<Entity>`.

## Script structure

```javascript
import http from 'k6/http';

import ScenarioUtils from '../utils/scenarioUtils.js';
import Utils from '../utils/utils.js';

const scenarioName = '<scenario>';

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);

export const options = scenarioUtils.getOptions();

const GRAPHQL_URL = `${utils.getBaseHttpUrl()}<path>`;
const JSON_HEADERS = { 'Content-Type': 'application/json' };

function graphql(query, variables, name) {
  return http.post(GRAPHQL_URL, JSON.stringify({ query, variables }), {
    headers: JSON_HEADERS,
    tags: { name },
  });
}

// True when the operation answered with data for `field` and without errors.
function succeeded(response, field) {
  if (response.status !== 200) {
    return false;
  }
  try {
    const body = response.json();
    return !body.errors && body.data !== null && body.data[field] !== null;
  } catch {
    return false;
  }
}
```

Rules that hold for every pattern below:

- Values travel as `variables`; never interpolate them into the query string, which defeats caching of the parsed operation and invites escaping errors.
- The check asserts HTTP 200, no `errors` and a non-null result field; `succeeded` catches a body that is not JSON, because an exception inside a check aborts the iteration instead of failing the check.
- Every operation gets a `name` tag with the operation name, so the summary separates the operations of a scenario.
- Unique values come from `__VU` and `__ITER`; `console`, random numbers, the wall clock and remote module imports are not used.
- Scenario names carry the prefix `graphQL` (`graphQLCreateEntity`, `graphQLGetEntity`) unless the repository already uses another convention.

The endpoint as a template-derived repository serves it:

```text # profile-example
POST http://localhost:<port>/api/graphql   (utils.getBaseHttpUrl() ends with /api, so <path> is /graphql)
GET  http://localhost:<port>/api/graphql   the development explorer page, never a load target
```

## Mutation: create

```javascript
const CREATE = `
  mutation Create($input: Create<Entity>Input!) {
    create<Entity>(input: $input) { id }
  }
`;

export default function graphQLCreateEntity() {
  const input = {
    name: `entity-${__VU}-${__ITER}`,
    // every other field the input type requires, within its documented limits
  };
  const response = graphql(CREATE, { input }, 'create<Entity>');

  utils.checkResponse(response, 'created without errors', res => succeeded(res, 'create<Entity>'));
}
```

## Query: read one by ID

`setup()` creates the items once, through the REST create operation when the service has one (fewer moving parts) or through the mutation otherwise; the iterations read them in a fixed rotation:

```javascript
const GET = `
  query Get($id: ID!) {
    <entity>(id: $id) { id }
  }
`;

export function setup() {
  const ids = [];
  for (let i = 0; i < 10; i += 1) {
    const response = graphql(CREATE, { input: { name: `entity-seed-${i}` } }, 'seed');
    if (!succeeded(response, 'create<Entity>')) {
      throw new Error(`setup could not create a seed item: status ${response.status}`);
    }
    ids.push(response.json('data.create<Entity>.id'));
  }
  return { ids };
}

export default function graphQLGetEntity(data) {
  const id = data.ids[__ITER % data.ids.length];
  const response = graphql(GET, { id }, 'get<Entity>');

  utils.checkResponse(response, 'found without errors', res => succeeded(res, '<entity>'));
}
```

A query for an unknown identifier answers `null` without an error; `succeeded` treats that as a failed check, which is what a read of a seeded item expects.

## Query: list a page

```javascript
const LIST = `
  query List(<paging variables>) {
    <entities>(<paging arguments>) { id }
  }
`;

export default function graphQLListEntities() {
  const variables = {}; // the paging variables the list query declares
  const response = graphql(LIST, variables, 'list<Entities>');

  utils.checkResponse(response, 'listed without errors', res => succeeded(res, '<entities>'));
}
```

The paging arguments of a template-derived list query:

```text # profile-example
query List($page: Int!, $itemsPerPage: Int!) { <entities>(page: $page, itemsPerPage: $itemsPerPage) { id } }
variables: { "page": 1, "itemsPerPage": 30 }
```

## Field selection

Select the fields the operation's real clients select, and no more. A selection that is too small measures less work than production does; a selection of every field measures serialization nobody needs. The check reads only what it asserts (usually `id`).

## Errors

| Response | Meaning | Where to look |
| --- | --- | --- |
| HTTP 200 with `errors` and a validation code | the input broke a documented rule; the entry lists the violations | the input values against the schema snapshot's limits |
| HTTP 200 with `errors` and an internal code | the resolver failed; the response carries no detail by design | the service log the isolated environment prints when the run fails |
| HTTP 200 with `errors` and no code | the query does not match the schema (unknown field, wrong argument type) | the operation text against the schema snapshot |
| a problem document | the body is not a GraphQL request, is not JSON or is too large | the request body and its content type |

The error codes of a template-derived service:

```json # profile-example
{
  "data": null,
  "errors": [
    {
      "message": "<detail of the validation problem>",
      "extensions": {
        "code": "VALIDATION_FAILED",
        "violations": [{ "propertyPath": "name", "message": "<rule>", "code": "<code>" }]
      }
    }
  ]
}
```

Every failure other than a validation failure carries the service's internal error code and no detail:

```text # profile-example
every other failure: extensions.code INTERNAL_SERVER_ERROR, message "Internal server error", no detail
```

## Setup and teardown

- Requests in `setup()` and `teardown()` run outside the profiles and never count against the budget, so seeding through REST or GraphQL does not change the measurement.
- `teardown()` removes what `setup()` created only when the contract offers a delete operation; the isolated environment drops its database after every run either way.

## Putting it together

A complete read scenario, ready to copy under `tests/Load/scripts/graphQLGetEntity.js` once the placeholders are replaced from the schema snapshot:

```javascript
import http from 'k6/http';

import ScenarioUtils from '../utils/scenarioUtils.js';
import Utils from '../utils/utils.js';

const scenarioName = 'graphQLGetEntity';
const SEED_ITEMS = 10;

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);

export const options = scenarioUtils.getOptions();

const GRAPHQL_URL = `${utils.getBaseHttpUrl()}<path>`;
const JSON_HEADERS = { 'Content-Type': 'application/json' };

const CREATE = `
  mutation Create($input: Create<Entity>Input!) {
    create<Entity>(input: $input) { id }
  }
`;
const GET = `
  query Get($id: ID!) {
    <entity>(id: $id) { id }
  }
`;

function graphql(query, variables, name) {
  return http.post(GRAPHQL_URL, JSON.stringify({ query, variables }), {
    headers: JSON_HEADERS,
    tags: { name },
  });
}

function succeeded(response, field) {
  if (response.status !== 200) {
    return false;
  }
  try {
    const body = response.json();
    return !body.errors && body.data !== null && body.data[field] !== null;
  } catch {
    return false;
  }
}

export function setup() {
  const ids = [];
  for (let i = 0; i < SEED_ITEMS; i += 1) {
    const response = graphql(CREATE, { input: { name: `entity-seed-${i}` } }, 'seed');
    if (!succeeded(response, 'create<Entity>')) {
      throw new Error(`setup could not create a seed item: status ${response.status}`);
    }
    ids.push(response.json('data.create<Entity>.id'));
  }
  return { ids };
}

export default function graphQLGetEntity(data) {
  const id = data.ids[__ITER % data.ids.length];
  const response = graphql(GET, { id }, 'get<Entity>');

  utils.checkResponse(response, 'found without errors', res => succeeded(res, '<entity>'));
}
```

Then add `/endpoints/graphQLGetEntity` to `tests/Load/config.json.dist` as [configuration.md](configuration.md) describes. When two scenarios share the `graphql` and `succeeded` helpers, move them into a helper module as [utils-extensions.md](utils-extensions.md) shows.
