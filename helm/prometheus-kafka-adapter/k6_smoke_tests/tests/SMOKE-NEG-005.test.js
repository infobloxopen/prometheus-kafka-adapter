// SMOKE-NEG-005: POST /receive — Invalid credentials
import http from 'k6/http';
import { check, group } from 'k6';
import { isUnauthorized } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';
import { getInvalidAuthParams } from '../helpers/auth.js';

export function runNEG005(baseUrl) {
  group('SMOKE-NEG-005: Invalid credentials', () => {
    const url = `${baseUrl}/receive`;
    const params = getInvalidAuthParams({ 'Content-Type': 'application/x-protobuf' });
    const res = http.post(url, 'test', params);
    logRequest('smoke-neg-005', '/receive', 'POST', url, '[bad creds]', res);

    check(res, {
      'invalid creds returns 401': isUnauthorized,
    });
  });
}
