# REST API Load Testing Patterns

These templates are generic. They use a placeholder `Resource` entity with a
single `dependency` relation; substitute the resources of your own service's
bounded contexts (`architecture.bounded_contexts`). IRI-based patterns (`@id`,
`hydra:member`) apply when `framework.api_platform` is a version string; for a
plain REST API drop the IRI/Hydra specifics and use whatever identifier and
collection envelope your endpoints return.

## Script Structure Template

```javascript
import http from 'k6/http';
import ScenarioUtils from '../utils/scenarioUtils.js';
import Utils from '../utils/utils.js';
import { randomString } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

const scenarioName = 'operationResource'; // e.g., 'createResource'

const utils = new Utils();
const scenarioUtils = new ScenarioUtils(utils, scenarioName);

export const options = scenarioUtils.getOptions();

export function setup() {
  // Create required dependencies (types, statuses, etc.)
  const dependencyData = { value: `TestDep_${Date.now()}` };
  const response = utils.createDependency(dependencyData);

  if (response.status === 201) {
    return { dependency: JSON.parse(response.body) };
  }

  return { dependency: null };
}

export default function operationResource(data) {
  // Main test logic here
  const resourceData = generateResourceData(data);
  const response = utils.createResource(resourceData);

  utils.checkResponse(response, 'is status 201', res => res.status === 201);
}

export function teardown(data) {
  // Clean up created test data
  if (data.dependency) {
    http.del(`${utils.getBaseHttpUrl()}${data.dependency['@id']}`);
  }
}

function generateResourceData(data) {
  // Generate realistic test data
  const resourceData = {
    name: `TestResource_${randomString(8)}`,
    // ... other fields
  };

  // Add dependencies if available
  if (data && data.dependency) {
    resourceData.dependency = data.dependency['@id'];
  }

  return resourceData;
}
```

## REST Load Test Types

### 1. Create Operations

**Purpose**: Test resource creation endpoints

```javascript
export default function createResource(data) {
  const resourceData = {
    name: `Resource_${randomString(8)}`,
    field1: `Value_${Date.now()}`,
    dependency: data.dependency['@id'],
  };

  const response = http.post(
    `${utils.getBaseHttpUrl()}/resources`,
    JSON.stringify(resourceData),
    utils.getJsonHeader()
  );

  utils.checkResponse(response, 'is status 201', res => res.status === 201);
}
```

**Validation**: Check for 201 status codes

### 2. Read Operations

**Get Single Resource**:

```javascript
export default function getResource(data) {
  const response = http.get(`${utils.getBaseHttpUrl()}${data.resourceIri}`);

  utils.checkResponse(response, 'is status 200', res => res.status === 200);
}
```

**Get Collection with Filters**:

This pattern assumes JSON-LD/Hydra-compliant API responses (standard for
API Platform — i.e. when `framework.api_platform` is a version string). For a
plain REST API, validate against your own collection envelope instead.

```javascript
export default function getResources(data) {
  const url = `${utils.getBaseHttpUrl()}/resources?page=1&itemsPerPage=30`;
  const response = http.get(url);

  utils.checkResponse(response, 'is status 200', res => {
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      return body['hydra:member'] && body['hydra:totalItems'] >= 0;
    }
    return false;
  });
}
```

### 3. Update Operations

**Partial Update (PATCH)**:

```javascript
export default function updateResource(data) {
  const updates = {
    name: `Updated_${randomString(8)}`,
  };

  const response = http.patch(
    `${utils.getBaseHttpUrl()}${data.resourceIri}`,
    JSON.stringify(updates),
    utils.getMergePatchHeader()
  );

  utils.checkResponse(response, 'is status 200', res => res.status === 200);
}
```

**Full Replace (PUT)**:

```javascript
export default function replaceResource(data) {
  const resourceData = {
    name: `Replaced_${randomString(8)}`,
    field1: `NewValue_${Date.now()}`,
    dependency: data.dependency['@id'],
  };

  const response = http.put(
    `${utils.getBaseHttpUrl()}${data.resourceIri}`,
    JSON.stringify(resourceData),
    utils.getJsonHeader()
  );

  utils.checkResponse(response, 'is status 200', res => res.status === 200);
}
```

### 4. Delete Operations

```javascript
export default function deleteResource(data) {
  const response = http.del(`${utils.getBaseHttpUrl()}${data.resourceIri}`);

  utils.checkResponse(response, 'is status 204', res => res.status === 204);
}
```

## IRI Handling

Applies when `framework.api_platform` is a version string. For a plain REST
API, store and reuse whatever identifier your endpoints return.

### Storing IRIs

```javascript
// When creating resources, store the full IRI
if (response.status === 201) {
  const resource = JSON.parse(response.body);
  createdResources.push(resource['@id']); // e.g., "/api/resources/01234"
}
```

### Using IRIs

```javascript
// Use IRI directly in HTTP requests
http.del(`${utils.getBaseHttpUrl()}${resourceIri}`);
// Results in: DELETE https://localhost/api/resources/01234
```

### Extracting IDs from IRIs

```javascript
// If you need just the ID part
const id = resourceIri.split('/').pop(); // "01234"
```

## Data Generation

### Realistic Test Data

Generate fields that match your own resource's schema. The example below uses
a placeholder resource with a few representative fields and two dependency
relations.

```javascript
function generateResourceData(data) {
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

### Timestamp-Based Uniqueness

```javascript
// Ensure unique values with timestamps
const uniqueValue = `TestValue_${Date.now()}_${randomString(6)}`;
const email = `test_${Date.now()}@example.com`;
```

## Best Practices

### Content-Type Headers

```javascript
// For JSON-LD (default API Platform format)
utils.getJsonHeader(); // Content-Type: application/ld+json

// For PATCH operations
utils.getMergePatchHeader(); // Content-Type: application/merge-patch+json
```

### Error Handling

```javascript
utils.checkResponse(response, 'resource created', res => {
  if (res.status === 201) {
    try {
      const resource = JSON.parse(res.body);
      if (resource['@id']) {
        data.createdResources.push(resource['@id']);
        return true;
      }
    } catch (e) {
      console.error('Failed to parse response:', e);
    }
  }
  return false;
});
```

### Deterministic Operations

```javascript
// ✅ GOOD: Use iteration-based patterns
export default function mixedOperations(data) {
  const operationIndex = __ITER % 4;

  switch (operationIndex) {
    case 0:
      createResource(data);
      break;
    case 1:
      getResource(data);
      break;
    case 2:
      updateResource(data);
      break;
    case 3:
      deleteResource(data);
      break;
  }
}

// ❌ BAD: Random operations
const operation = Math.random(); // Never do this!
```

## Putting It Together

Combine the structure template with the operation-specific blocks above to
build one script per endpoint (`createResource.js`, `getResource.js`,
`updateResource.js`, `deleteResource.js`), then register each scenario in the
config file (see [configuration.md](configuration.md)) and extend the `Utils`
class with any service-specific helpers (see
[utils-extensions.md](utils-extensions.md)).
