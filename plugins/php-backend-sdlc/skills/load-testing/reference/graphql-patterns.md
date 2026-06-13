# GraphQL Load Testing Patterns

These templates apply only when `framework.graphql` is true. They use a
placeholder `Resource` entity with a single `dependency` relation; substitute
the resources and operations of your own service's bounded contexts
(`architecture.bounded_contexts`). The `@id`/IRI form shown for relation inputs
applies when `framework.api_platform` is a version string.

## Script Structure Template

```javascript
import http from 'k6/http';
import ScenarioUtils from '../utils/scenarioUtils.js';
import Utils from '../utils/utils.js';
import { randomString } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

const scenarioName = 'graphQLOperationResource'; // e.g., 'graphQLCreateResource'

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);

export const options = scenarioUtils.getOptions();

export function setup() {
  // Use REST API for faster setup of dependencies
  const dependencyData = { value: `TestDep_${Date.now()}` };
  const response = utils.createDependency(dependencyData);

  if (response.status === 201) {
    return { dependency: JSON.parse(response.body) };
  }

  return { dependency: null };
}

export default function graphQLOperationResource(data) {
  // Main GraphQL test logic
  // Note: buildGraphQLQuery must be implemented per scenario (see below)
  // Expected return: { query: string, variables?: object }
  const query = buildGraphQLQuery(data);
  const response = utils.executeGraphQL(query);

  utils.checkResponse(response, 'GraphQL operation successful', res => {
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      return body.data && !body.errors;
    }
    return false;
  });
}

export function teardown(data) {
  // Use REST API for faster cleanup
  if (data.dependency) {
    try {
      const deleteResponse = http.del(`${utils.getBaseHttpUrl()}${data.dependency['@id']}`);
      if (
        deleteResponse.status !== 204 &&
        deleteResponse.status !== 200 &&
        deleteResponse.status !== 404
      ) {
        console.warn(
          `Failed to clean up dependency: ${deleteResponse.status} - ${data.dependency['@id']}`
        );
      } else if (deleteResponse.status === 404) {
        console.info(`Dependency already deleted: ${data.dependency['@id']}`);
      }
    } catch (e) {
      console.error(`Error deleting dependency ${data.dependency['@id']}: ${e.message}`);
    }
  }
}

function buildGraphQLQuery(data) {
  return {
    query: `mutation CreateResource($input: CreateResourceInput!) {
      createResource(input: $input) {
        resource {
          id
          name
        }
      }
    }`,
    variables: {
      input: {
        name: `Resource_${randomString(8)}`,
        dependency: data.dependency['@id'],
      },
    },
  };
}
```

## GraphQL Load Test Types

### 1. Mutation Operations (Create)

**Purpose**: Test resource creation via GraphQL mutations

```javascript
export default function graphQLCreateResource(data) {
  const mutation = {
    query: `mutation CreateResource($input: CreateResourceInput!) {
      createResource(input: $input) {
        resource {
          id
          name
          email
          type
          status
        }
      }
    }`,
    variables: {
      input: {
        name: `Resource_${randomString(8)}`,
        email: `test_${Date.now()}@example.com`,
        phone: `+1-555-${Math.floor(Math.random() * 9000) + 1000}`,
        type: data.type['@id'], // Full IRI from setup phase, e.g., '/api/types/01K85E...'
        status: data.status['@id'], // Full IRI from setup phase, e.g., '/api/statuses/01K85E...'
        active: true,
      },
    },
  };

  const response = utils.executeGraphQL(mutation);

  utils.checkResponse(response, 'resource created via GraphQL', res => {
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      if (body.data?.createResource?.resource) {
        if (!data.createdResources) data.createdResources = [];
        data.createdResources.push(body.data.createResource.resource.id);
        return true;
      }
      if (body.errors) {
        console.error('GraphQL errors:', JSON.stringify(body.errors));
      }
    }
    return false;
  });
}
```

**Validation**:

- Check `response.status === 200`
- Verify `body.data` contains expected data
- Ensure `body.errors` is undefined or empty

### 2. Query Operations (Read)

**Get Single Resource**:

```javascript
export default function graphQLGetResource(data) {
  const query = {
    query: `query GetResource($id: ID!) {
      resource(id: $id) {
        id
        name
        email
        type
        status
        active
        createdAt
      }
    }`,
    variables: {
      id: data.resourceIri,
    },
  };

  const response = utils.executeGraphQL(query);

  utils.checkResponse(response, 'resource fetched via GraphQL', res => {
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      return body.data?.resource && !body.errors;
    }
    return false;
  });
}
```

**Get Collection with Filters**:

```javascript
export default function graphQLGetResources(data) {
  const query = {
    query: `query GetResources($page: Int, $itemsPerPage: Int, $status: String) {
      resources(page: $page, itemsPerPage: $itemsPerPage, status: $status) {
        collection {
          id
          name
          email
          status
        }
        paginationInfo {
          itemsPerPage
          lastPage
          totalCount
        }
      }
    }`,
    variables: {
      page: 1,
      itemsPerPage: 30,
      status: data.status['@id'],
    },
  };

  const response = utils.executeGraphQL(query);

  utils.checkResponse(response, 'resources collection fetched', res => {
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      return body.data?.resources?.collection && !body.errors;
    }
    return false;
  });
}
```

### 3. Mutation Operations (Update)

```javascript
export default function graphQLUpdateResource(data) {
  const mutation = {
    query: `mutation UpdateResource($input: UpdateResourceInput!) {
      updateResource(input: $input) {
        resource {
          id
          name
          email
        }
      }
    }`,
    variables: {
      input: {
        id: data.resourceIri,
        name: `Updated_${randomString(8)}`,
      },
    },
  };

  const response = utils.executeGraphQL(mutation);

  utils.checkResponse(response, 'resource updated via GraphQL', res => {
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      return body.data?.updateResource?.resource && !body.errors;
    }
    return false;
  });
}
```

### 4. Mutation Operations (Delete)

```javascript
export default function graphQLDeleteResource(data) {
  const mutation = {
    query: `mutation DeleteResource($input: DeleteResourceInput!) {
      deleteResource(input: $input) {
        resource {
          id
        }
      }
    }`,
    variables: {
      input: {
        id: data.resourceIri,
      },
    },
  };

  const response = utils.executeGraphQL(mutation);

  utils.checkResponse(response, 'resource deleted via GraphQL', res => {
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      return body.data?.deleteResource && !body.errors;
    }
    return false;
  });
}
```

## ID/IRI Handling in GraphQL

When `framework.api_platform` is a version string, GraphQL queries/mutations
expect the full IRI rather than a bare id.

### GraphQL Uses Full IRI Format

```javascript
// ✅ GOOD: Use full IRI in GraphQL
const mutation = {
  query: `mutation CreateResource($input: CreateResourceInput!) { ... }`,
  variables: {
    input: {
      type: '/api/types/01234', // Full IRI
      status: '/api/statuses/56789',
    },
  },
};
```

### Extracting IRI from GraphQL Response

```javascript
// GraphQL response returns the full IRI
const body = JSON.parse(response.body);
const resourceId = body.data.createResource.resource.id;
// resourceId will be the full IRI: "/api/resources/01K85E6755EFKTKPFMK6WHF99V"

// Store for later use
data.createdResources.push(resourceId);
```

### Using Stored IRIs in Subsequent Queries

```javascript
const query = {
  query: `query GetResource($id: ID!) {
    resource(id: $id) { ... }
  }`,
  variables: {
    id: data.resourceIri, // Use stored IRI
  },
};
```

## Data Generation

### Realistic GraphQL Input Data

```javascript
function generateResourceInput(data) {
  const domains = ['example.com', 'test.org', 'demo.net'];
  const categories = ['Alpha', 'Beta', 'Gamma'];
  const name = `Resource_${randomString(8)}`;

  return {
    name,
    email: `${name.toLowerCase()}@${domains[Math.floor(Math.random() * domains.length)]}`,
    phone: `+1-555-${Math.floor(Math.random() * 9000) + 1000}`,
    category: categories[Math.floor(Math.random() * categories.length)],
    type: data.type['@id'],
    status: data.status['@id'],
    active: Math.random() > 0.5,
    // Note: createdAt and updatedAt are set by the server
  };
}
```

### Handling Nested Objects

```javascript
function generateComplexInput(data) {
  return {
    resource: {
      name: `Resource_${randomString(8)}`,
      email: `test_${Date.now()}@example.com`,
      address: {
        street: `${Math.floor(Math.random() * 9999)} Main St`,
        city: 'Test City',
        country: 'US',
        postalCode: `${Math.floor(Math.random() * 90000) + 10000}`,
      },
    },
    type: data.type['@id'],
  };
}
```

## Best Practices

### Response Validation

Always check both status and GraphQL-specific errors:

```javascript
utils.checkResponse(response, 'operation description', res => {
  if (res.status !== 200) {
    return false;
  }

  const body = JSON.parse(res.body);

  // Check for GraphQL errors
  if (body.errors && body.errors.length > 0) {
    console.error('GraphQL errors:', JSON.stringify(body.errors));
    return false;
  }

  // Check for expected data
  if (!body.data || !body.data.expectedField) {
    console.error('Missing expected data in response');
    return false;
  }

  return true;
});
```

### Use REST for Setup/Teardown

GraphQL is slower for bulk operations. Use REST API for setup/teardown:

```javascript
export function setup() {
  // ✅ GOOD: Use REST for faster setup
  const typeResponse = http.post(
    `${utils.getBaseHttpUrl()}/api/types`,
    JSON.stringify({ value: `Type_${Date.now()}` }),
    utils.getJsonHeader()
  );

  return { type: JSON.parse(typeResponse.body) };
}

export function teardown(data) {
  // ✅ GOOD: Use REST for faster cleanup
  if (data.type) {
    http.del(`${utils.getBaseHttpUrl()}${data.type['@id']}`);
  }
}
```

### Error Handling

```javascript
const response = utils.executeGraphQL(mutation);

utils.checkResponse(response, 'operation successful', res => {
  if (res.status !== 200) {
    console.error(`HTTP error: ${res.status} ${res.statusText}`);
    return false;
  }

  try {
    const body = JSON.parse(res.body);

    if (body.errors) {
      body.errors.forEach(error => {
        console.error(`GraphQL error: ${error.message}`);
        if (error.extensions) {
          console.error('Extensions:', JSON.stringify(error.extensions));
        }
      });
      return false;
    }

    return body.data && body.data.expectedField;
  } catch (e) {
    console.error('Failed to parse response:', e);
    return false;
  }
});
```

### Query Variables Best Practices

```javascript
// ✅ GOOD: Use variables for all dynamic values
const query = {
  query: `query GetResources($status: String!, $page: Int) {
    resources(status: $status, page: $page) { ... }
  }`,
  variables: {
    status: data.status['@id'],
    page: 1,
  },
};

// ❌ BAD: Inline values in query string
const query = {
  query: `query {
    resources(status: "${data.status['@id']}", page: 1) { ... }
  }`,
};
```

### Field Selection

Only request fields you need to validate:

```javascript
// ✅ GOOD: Minimal field selection
const query = {
  query: `query GetResource($id: ID!) {
    resource(id: $id) {
      id
      name
    }
  }`,
  variables: { id: resourceId },
};

// ❌ BAD: Requesting all fields
const query = {
  query: `query GetResource($id: ID!) {
    resource(id: $id) {
      id
      name
      email
      phone
      address
      type
      status
      active
      createdAt
      updatedAt
      // ... many more fields
    }
  }`,
  variables: { id: resourceId },
};
```

## Deterministic Operations

```javascript
// ✅ GOOD: Use iteration-based patterns
export default function graphQLMixedOperations(data) {
  const operationIndex = __ITER % 4;

  const operations = [
    () => graphQLCreateResource(data),
    () => graphQLGetResource(data),
    () => graphQLUpdateResource(data),
    () => graphQLDeleteResource(data),
  ];

  operations[operationIndex]();
}

// ❌ BAD: Random operations
const operation = Math.random(); // Never do this!
```

## Putting It Together

Combine the structure template with the operation-specific blocks above to
build one script per operation (`graphQLCreateResource.js`,
`graphQLGetResource.js`, etc.), register each scenario in the config file (see
[configuration.md](configuration.md)), and use the REST-side helpers from
[utils-extensions.md](utils-extensions.md) for fast setup/teardown.
