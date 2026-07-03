---
agent: smokeTestAgent
---

TASK

Analyze the provided service repositories and Swagger/OpenAPI specification to generate a structured Smoke Test Coverage Plan.

You must output the plan in structured JSON format and save it as:

smoke-test-plan.json

Do not generate test code in this phase.

INPUTS

You may receive:
- One or multiple service repositories
- Swagger/OpenAPI JSON specification
- Configuration documentation
- Service name (for documentation lookup)

Swagger is authoritative for endpoint discovery and schema definition.
Repositories are authoritative for service behavior understanding.
Organizational documentation (via Glean) provides context for service architecture, auth flows, and dependencies.

---

PHASE 0 – DOCUMENTATION LOOKUP

Before analyzing code or Swagger, search organizational documentation for context about the target service.

You must:

1. Search Glean for the service using queries such as:
   - "{service_name} API documentation"
   - "{service_name} architecture"
   - "{service_name} authentication flow"
   - "{service_name} HLD" or "{service_name} high-level design"
   - "{service_name} dependencies"

2. From retrieved documentation, extract:
   - Service purpose and description
   - API endpoint overview (if documented)
   - Authentication type and flow (user JWT, S2S token, API key, etc.)
   - External dependencies and their behavior
   - Resource lifecycle patterns (create/read/update/delete behavior)
   - Known constraints or limitations

3. Record what was found and what was NOT found. Documentation gaps will be filled by Swagger and repository analysis in subsequent phases.

4. If Glean is unavailable or returns no results, proceed to the next phase without documentation context. Do not fail or block on missing documentation.

Documentation from Glean must NOT override explicit Swagger/OpenAPI definitions or verifiable code behavior. Use it as context, not as ground truth for endpoint schemas.

---

SWAGGER FALLBACK RULE

If a Swagger/OpenAPI specification is NOT provided:

You must identify and construct a JSON catalog of ALL REST endpoints directly from the repository codebase.

You must:

1. Scan all repositories provided.
2. Identify all HTTP route registrations including:
   - router.Handle
   - router.HandleFunc
   - mux.Router
   - gin router definitions
   - echo router definitions
   - http.NewServeMux
   - grpc-gateway annotations (google.api.http)
   - Any HTTP handler registration patterns
3. Extract:
   - HTTP method
   - Route path
   - Handler name (if identifiable)
   - Source file location
4. Include BOTH public and private/internal endpoints.
5. Do not filter endpoints by visibility.
6. Do not assume endpoint purpose.

You must consolidate all discovered endpoints into an internal endpoint catalog before continuing.

If Swagger is provided:
- Use Swagger as authoritative.
- Repository scanning may be used only for behavioral understanding.

If Swagger is NOT provided:
- Repository scanning becomes authoritative for endpoint discovery.

You must not guess endpoint definitions.
You must not infer undocumented endpoints.

If endpoint identification is incomplete:
- Add details under "clarifications_required".

---

PHASE 1 – SERVICE UNDERSTANDING

Using documentation context from Phase 0 (if available), determine:
- Service purpose
- Core resource lifecycle patterns
- Authentication flow
- External dependencies
- Endpoint grouping by domain

Where documentation provided clear answers, use them as the starting point.
Where documentation was incomplete or unavailable, derive understanding from repository code.

Do not assume unclear behavior.

---

PHASE 2 – ENDPOINT CATEGORIZATION

Using Swagger OR repository-derived endpoint catalog:

- List all endpoints
- Categorize into:
  - configuration
  - crud
  - workflow_trigger
  - retrieval
  - administration
  - observability

---

PHASE 3 – SMOKE SCENARIO IDENTIFICATION

For each smoke scenario define:

- scenario_id
- scenario_name
- objective
- involved_endpoints
- auth_type
- expected_success_conditions
- cleanup_requirements
- dependency_assumptions

NEGATIVE SCENARIO REQUIREMENT

For each endpoint, you must also define negative scenarios where applicable.

Negative scenarios must include:

- Invalid input payloads (missing required fields, incorrect types)
- Unauthorized or invalid authentication cases
- Invalid resource identifiers
- Boundary condition violations (limits, empty values)

For update and delete endpoints, you must also define negative scenarios that attempt to operate on resources that do NOT start with AUTO_TEST_.

These scenarios must validate:
- The operation is rejected
- No modification occurs
- No deletion occurs
- The correct error response is returned, if defined

These scenarios must not use pre-existing data to discover targets.

Each negative scenario must include:
- scenario_id
- scenario_name
- objective
- involved_endpoints
- expected_failure_conditions
- auth_type

Negative scenarios must not rely on existing system data.
They must follow the same isolation and guardrail rules as positive scenarios.

---

PHASE 4 – COVERAGE DESIGN

Define:

- endpoint_coverage_map
- verification_strategy
- cleanup_strategy
- authentication_strategy
- data_generation_strategy
- parallel_execution_safety_notes

authentication_strategy:
- Define authentication type per endpoint or scenario
- Mark each endpoint as user JWT, S2S, or no auth
- Do not leave authentication type implicit

---

PHASE 5 – UNCERTAINTY HANDLING

Before adding any item to clarifications_required, you must first attempt to resolve it using Glean:

1. For each uncertainty, search Glean with a targeted query about the specific unclear behavior.
2. If Glean returns a clear answer supported by documentation, use that answer and do NOT add it to clarifications.
3. If Glean returns ambiguous or conflicting information, add the item to clarifications and note what documentation was found.
4. If Glean returns no results or is unavailable, add the item to clarifications as before.

Only add entries under "clarifications_required" after exhausting documentation lookup.
Do not guess.

---

OUTPUT FORMAT

Return ONLY valid JSON with this structure:

{
  "service_summary": {},
  "documentation_context": {
    "sources_found": [],
    "gaps_identified": []
  },
  "endpoint_catalog": {
    "source": "swagger" | "repository_scan",
    "endpoints": []
  },
  "smoke_scenarios": [],
  "coverage_design": {},
  "clarifications_required": []
}

---

FILE SAVE REQUIREMENT

Save output as smoke-test-plan.json in workspace root.
Do not generate commentary or markdown.
Do not generate test code.

---

SUCCESS CRITERIA

- JSON is valid
- All REST endpoints are identified
- Endpoint source is correctly specified
- Endpoint mapping is complete
- No hidden assumptions
- Clarifications listed if required
