---
agent: smokeTestAgent
---

TASK

Review the generated K6 smoke test code against the approved smoke-test-plan.json and project guardrails.

Do not generate new tests.

You must validate and correct the existing implementation.

---

INPUTS

- smoke-test-plan.json
- Generated K6 test code

---

REVIEW REQUIREMENTS

You must validate:

1. Coverage
- All endpoints from plan are implemented
- No extra endpoints exist

2. Authentication
- Two-step auth implemented correctly
- No hardcoded credentials

3. Guardrails
- No usage of existing resources
- AUTO_TEST_* naming followed
- No GET-based ID discovery
- No fallback logic

4. Helper Functions
- Helper functions are defined
- No repeated inline validation logic
- parseBody is not repeatedly used inline

5. Logging
- All requests and responses are logged
- Logs include payload, status, response

6. Response Validation
- Response correctness is validated
- Data is scoped correctly
- No weak assertions

7. Cleanup
- All created resources are deleted
- Cleanup runs even on failure

8. Determinism
- No shared state
- Parallel-safe execution

9. Resource Prefix Safety

- Ensure all created resources use AUTO_TEST_* prefix
- Ensure UPDATE and DELETE operations validate prefix before execution
- Ensure no operation is performed on non-test resources

10. Negative Scenario Validation

- Ensure negative scenarios are implemented for each applicable endpoint
- Ensure invalid inputs are tested
- Ensure correct failure responses are validated
- Ensure negative tests do not create or modify resources
- Ensure update/delete negative scenarios validate rejection of non-AUTO_TEST_ resources
- Ensure no unsafe update or delete operation is performed on external or pre-existing resources

11. Cluster Validation

- Ensure tests are only intended for approved clusters
- Ensure the default allowed cluster list includes us-dev-5
- Ensure the generated implementation does not target unapproved clusters
---

OUTPUT

Return ONLY:

1. Review Summary
2. Issues Found (if any)
3. Corrected K6 Test Code

If no issues:
- Return confirmation + code