// Common utilities for smoke tests

/**
 * Safely parse a JSON response body.
 */
export function parseBody(r) {
  try {
    return JSON.parse(r.body);
  } catch (e) {
    return {};
  }
}

/**
 * Structured request/response logging.
 */
export function logRequest(phase, endpoint, method, url, payload, response) {
  const logEntry = {
    phase: phase,
    endpoint: endpoint,
    method: method,
    url: url,
    requestPayload: payload,
    status: response ? response.status : null,
    responseBody: response ? truncate(response.body, 2000) : null,
  };
  console.log(JSON.stringify(logEntry));
}

/**
 * Truncate a string to a maximum length.
 */
export function truncate(str, maxLen) {
  if (typeof str !== 'string') return str;
  if (str.length <= maxLen) return str;
  return str.substring(0, maxLen) + '...[truncated]';
}

/**
 * Parse a Prometheus metric value from text exposition format.
 * Returns the numeric value of the first matching line, or null if not found.
 */
export function parsePrometheusMetric(body, metricName) {
  if (typeof body !== 'string') return null;
  const lines = body.split('\n');
  for (const line of lines) {
    if (line.startsWith('#')) continue;
    if (line.startsWith(metricName + ' ') || line.startsWith(metricName + '{')) {
      const parts = line.split(' ');
      const value = parseFloat(parts[parts.length - 1]);
      return isNaN(value) ? null : value;
    }
  }
  return null;
}

/**
 * Generate a unique identifier for test isolation.
 */
export function uniqueId() {
  return `AUTO_TEST_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
}
