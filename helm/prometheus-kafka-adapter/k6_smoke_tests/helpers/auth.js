// Authentication helper for prometheus-kafka-adapter smoke tests
// This service uses optional HTTP Basic Auth (NOT CSP JWT).

import encoding from 'k6/encoding';
import { config } from '../config/config.js';

/**
 * Returns HTTP params with Basic Auth headers if enabled.
 */
export function getAuthParams(extraHeaders = {}) {
  const params = { headers: { ...extraHeaders } };

  if (config.BASIC_AUTH_ENABLED) {
    const encoded = encoding.b64encode(`${config.BASIC_AUTH_USERNAME}:${config.BASIC_AUTH_PASSWORD}`);
    params.headers['Authorization'] = `Basic ${encoded}`;
  }

  return params;
}

/**
 * Returns HTTP params WITHOUT auth (for unauthorized test scenarios).
 */
export function getNoAuthParams(extraHeaders = {}) {
  return { headers: { ...extraHeaders } };
}

/**
 * Returns HTTP params with INVALID Basic Auth credentials.
 */
export function getInvalidAuthParams(extraHeaders = {}) {
  const encoded = encoding.b64encode('INVALID_USER:INVALID_PASS');
  return {
    headers: {
      Authorization: `Basic ${encoded}`,
      ...extraHeaders,
    },
  };
}
