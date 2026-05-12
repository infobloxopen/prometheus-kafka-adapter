// SMOKE-003: POST /receive — Endpoint reachability
// Without protobuf+snappy, we verify connectivity.
// A 400 (bad payload) confirms the endpoint is live and parsing.
import http from 'k6/http';
import { check, group } from 'k6';
import { isBadRequest } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';
import { getAuthParams } from '../helpers/auth.js';

export function runSMOKE003(baseUrl) {
  group('SMOKE-003: POST /receive - endpoint reachable', () => {
    const url = `${baseUrl}/receive`;
    const params = getAuthParams({ 'Content-Type': 'application/x-protobuf' });
    // Send minimal snappy-like bytes — service will reject but confirms endpoint is up
    const payload = '\x00\x00\x00\x00';
    const res = http.post(url, payload, params);
    logRequest('smoke-003', '/receive', 'POST', url, '[binary 4 bytes]', res);

    check(res, {
      'receive endpoint responds (not 404/405)': (r) => r.status !== 404 && r.status !== 405,
      'receive returns 400 for invalid payload': isBadRequest,
    });
  });
}
