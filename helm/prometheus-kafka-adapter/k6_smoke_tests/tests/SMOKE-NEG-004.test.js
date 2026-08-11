// SMOKE-NEG-004: POST /receive — No auth when required
import http from 'k6/http';
import { check, group } from 'k6';
import { isUnauthorized } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';
import { getNoAuthParams } from '../helpers/auth.js';

export function runNEG004(baseUrl) {
  group('SMOKE-NEG-004: No auth when required', () => {
    const url = `${baseUrl}/receive`;
    const params = getNoAuthParams({ 'Content-Type': 'application/x-protobuf' });
    const res = http.post(url, 'test', params);
    logRequest('smoke-neg-004', '/receive', 'POST', url, '[no auth]', res);

    check(res, {
      'missing auth returns 401': isUnauthorized,
    });
  });
}
