// Resource lifecycle and prefix validation helpers

/**
 * Validate that a value uses the AUTO_TEST_ prefix.
 */
export const isAutoTestResource = (value) =>
  typeof value === 'string' && value.startsWith('AUTO_TEST_');

/**
 * Ensure a created resource exists by checking a field in a GET response.
 */
export const resourceExists = (getResponse, idField, expectedId) => {
  try {
    const body = JSON.parse(getResponse.body);
    return body[idField] === expectedId;
  } catch (e) {
    return false;
  }
};

/**
 * Ensure a resource has been deleted (404 or empty results).
 */
export const resourceDeleted = (getResponse) => {
  if (getResponse.status === 404) return true;
  try {
    const body = JSON.parse(getResponse.body);
    return (body.results || []).length === 0;
  } catch (e) {
    return false;
  }
};
