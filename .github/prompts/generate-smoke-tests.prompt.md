---
agent: smokeTestAgent
---

# TASK

Generate K6-based smoke test implementation using the approved smoke-test-plan.json.

Treat the plan as the authoritative specification.

Do not redesign the plan.

# INPUTS

- smoke-test-plan.json
- Service repositories (optional)
- Swagger/OpenAPI (optional)
- Environment configuration references

# PLAN INTERPRETATION RULES

The plan may include a "documentation_context" section with sources and gaps identified during planning.
Use this context to understand service behavior when implementing test logic.
Do not re-query Glean during this phase — the plan already incorporates documentation findings.

You must:
- Implement exactly the defined smoke scenarios
- Follow endpoint coverage mapping
- Follow verification strategy
- Follow cleanup strategy
- Ask clarification questions only if implementation is impossible

Do not:
- Add new scenarios
- Remove scenarios
- Modify endpoint coverage
- Invent payload structures

# AUTHENTICATION SPECIFICATION

The test framework uses a two-step authentication process.

Step 1 – Obtain User JWT
Endpoint: POST /v2/session/users/sign_in
Body:
{
  "email": "<USER_EMAIL>",
  "password": "<USER_PASSWORD>"
}

The JWT may be returned in:
- access_token
- token
- jwt

Implementation must dynamically extract the correct field.

Step 2 – Use JWT for Subsequent Requests
All secured requests must include:
Authorization: Bearer <JWT>

Environment Variables Required:
- BASE_URL
- USER_EMAIL
- USER_PASSWORD

If an endpoint explicitly requires a different authentication type, follow the plan and endpoint metadata.
Do not assume S2S token is required unless the endpoint or plan explicitly says so.

## CREDENTIAL HANDLING RULE

You must NOT ask for actual credential values.

The following are assumed to be provided at runtime via environment variables:
- S2S_TOKEN
- USER_EMAIL
- USER_PASSWORD
- BASE_URL

These values are not required during planning or code generation.

You must:
- Reference them only as environment variables
- Fail fast at runtime if they are missing
- Never request credential values in clarification

Clarification regarding authentication is only allowed if:
- Authentication endpoint is missing
- Authentication flow is technically inconsistent

# GUARDRAIL RULES

## Cluster Execution Guardrail

Smoke tests must only be executed against approved clusters.

Default allowed cluster:
- us-dev-5

If the cluster is not in the approved cluster list:
- Do not generate execution targeting it
- Fail fast or mark it unsupported

The approved cluster must be represented as a configurable allowlist in the generated test or execution metadata.

## RESOURCE PREFIX ENFORCEMENT

All resources created during test execution must use the prefix:

AUTO_TEST_<unique_identifier>

This prefix must be applied consistently across:
- Request payloads
- Resource names
- Identifiers used in validation

Any deviation from this naming convention is not allowed.

These rules are mandatory and override any implicit assumptions.

Critical enforcement:

- Only create and operate on test-owned resources
- Never use or modify existing system data
- Always follow AUTO_TEST_* naming convention
- Never fetch IDs via GET calls
- No fallback logic is allowed
- Each scenario must be fully isolated
- Cleanup must only target created resources

If any scenario violates these rules:
- Modify implementation to comply
- Do not proceed with invalid logic

## IMPLEMENTATION REQUIREMENTS

Generate K6 JavaScript that includes:

SETUP
- JWT acquisition
- Required configuration creation
- Dynamic test data generation

ENDPOINT EXECUTION
- Execute endpoints defined in smoke plan
- Validate HTTP status codes
- Validate basic response schema

## NEGATIVE TEST EXECUTION

You must implement negative scenarios defined in the smoke plan.

For update and delete endpoints, you must implement negative safety tests that attempt to operate on resources without the AUTO_TEST_ prefix.

Validation must ensure:
- The operation is rejected or skipped
- Existing resources are not modified
- Existing resources are not deleted
- The response indicates the correct failure behavior

For each negative scenario:

- Execute the endpoint with invalid or malformed input
- Validate expected failure response

Validation must include:
- Correct HTTP error status (4xx or 5xx)
- Error response structure (if defined)
- No unintended resource creation

Negative tests must not affect existing or test-created resources.

## RESOURCE SAFETY VALIDATION

Before performing any UPDATE or DELETE operation:

- You must validate that the target resource identifier or name starts with:
  AUTO_TEST_

- If the resource does not match this prefix:
  - The operation must be skipped OR
  - The test must fail with a clear error

This validation must be explicitly implemented in the test code.

# VERIFICATION
- Validate expected success conditions
- Validate response content as defined in plan

# CLEANUP
- Delete all created resources
- Ensure cleanup executes even on failure

# LOGGING REQUIREMENTS

Generated smoke tests must include explicit structured logging for every request.

For each endpoint execution, log:

- Endpoint name
- HTTP method
- Full request URL
- Request headers (excluding sensitive values)
- Request payload
- Response status code
- Response body (stringified and truncated if large)

Use console.log for structured logging in JSON format:

Example pattern:

console.log(JSON.stringify({
  phase: "execution",
  endpoint: "<endpoint_name>",
  method: "<HTTP_METHOD>",
  url: url,
  requestPayload: payload,
  status: response.status,
  responseBody: response.body
}));

Logs must be visible during test execution without requiring --verbose mode.

Do not suppress logs for passed tests.
Logs must appear for every executed endpoint.

# HELPER FUNCTION REQUIREMENTS

Generated smoke tests must use reusable helper functions for validation and response handling.

Do not repeat inline validation logic across scenarios.

You must:

1. Create a helper section at the top of the test file.

2. Extract common validation patterns into reusable functions.

Minimum required helpers:

// Status validation
const isOk = (r) => r.status === 200;
const isCreated = (r) => r.status === 200 || r.status === 201;

// Response parsing
const parseBody = (r) => {
  try { return JSON.parse(r.body); } catch (e) { return {}; }
};

// Common validations
const hasId = (r) => typeof parseBody(r).id === 'string' && parseBody(r).id.length > 0;
const hasResultsArray = (r) => Array.isArray(parseBody(r).results);
const hasNoError = (r) => !parseBody(r).error;

// Generic field validation
const bodyFieldEquals = (field, expected) => (r) => parseBody(r)[field] === expected;

// Type validation
const hasAllowedBoolean = (r) => typeof parseBody(r).allowed === 'boolean';

3. Use these helpers inside check() instead of inline lambdas.

Example:

check(response, {
  'status is 200': isOk,
  'has id': hasId,
  'name matches': bodyFieldEquals('name', expectedName),
});

4. Avoid repeating parseBody(r) multiple times inline.

5. Ensure helpers are reusable across all scenarios.

---

RESOURCE VALIDATION HELPERS

You must also include helper functions for validating resource lifecycle:

// Ensure created resource exists
const resourceExists = (getResponse, idField, expectedId) =>
  parseBody(getResponse)[idField] === expectedId;

// Ensure resource cleanup
const resourceDeleted = (getResponse) =>
  getResponse.status === 404 || (parseBody(getResponse).results || []).length === 0;

These must be used for:

- Post-create validation
- Post-delete validation
- Cleanup verification

// Ensure resource is safe to modify
const isAutoTestResource = (value) =>
  typeof value === 'string' && value.startsWith('AUTO_TEST_');
---

# CODE STRUCTURE REQUIREMENT (MODULAR)

Generated smoke tests must follow a modular multi-file structure.

You must NOT generate a single monolithic test file.

---

## REQUIRED FILE STRUCTURE

smoke-tests/
├── config/
│   └── config.js                  # Environment variables, base URL, cluster config
│
├── helpers/
│   ├── auth.js                    # Authentication logic (JWT generation)
│   ├── validators.js              # All reusable validation helpers
│   ├── utils.js                   # Common utilities (parseBody, logging helpers)
│   └── resourceHelpers.js         # Resource lifecycle + prefix validation
│
├── tests/
│   ├── <scenario1>.test.js
│   ├── <scenario2>.test.js
│   └── ...
│
└── main.js                        # Entry point that executes all scenarios

---

## STRUCTURE RULES

1. Helpers must NOT be defined inside test files
2. Each scenario must be implemented in a separate test file
3. Common logic must be imported from helpers
4. Authentication must be implemented in helpers/auth.js
5. Validation logic must be centralized in helpers/validators.js
6. Logging utilities must be reusable and not duplicated
7. main.js must orchestrate execution of all scenario files

---

## IMPORT RULES

Test files must import:

- Config from config/config.js
- Auth from helpers/auth.js
- Validators from helpers/validators.js
- Utilities from helpers/utils.js

---

## PROHIBITED

- Do not generate all tests in one file
- Do not duplicate helper functions across files
- Do not inline validation logic inside test files
- Do not define authentication logic inside test scenarios

# REVIEW PHASE

After generating tests, validate:

1. Coverage Validation
- All endpoints in smoke plan are implemented
- No extra endpoints included

2. Authentication Validation
- Two-step auth correctly implemented
- No hardcoded credentials

3. Cleanup Validation
- All resources deleted
- Teardown guaranteed

4. Determinism Validation
- Parallel-safe execution
- No static data collisions

5. Guardrail Validation

- Ensure no existing resources are used
- Ensure all resources follow AUTO_TEST_* naming
- Ensure IDs are only captured from create responses
- Ensure no GET-based ID discovery
- Ensure no fallback logic is present
- Ensure strict test isolation

If inconsistencies exist, correct before final output.

# OUTPUT REQUIREMENTS

Return ONLY:

1. Implementation Summary
2. K6 Smoke Test Code

Do not generate planning content.
Do not generate documentation.
Do not output analysis text.

# SUCCESS CRITERIA

- All scenarios from smoke plan implemented
- Endpoint coverage matches plan
- Authentication correctly implemented
- Cleanup guaranteed
- Deterministic and parallel-safe
