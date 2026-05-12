// SMOKE-NEG-003: POST /receive — Empty body
import http from 'k6/http';
import { check, group } from 'k6';
import { logRequest } from '../helpers/utils.js';
import { getAuthParams } from '../helpers/auth.js';

export function runNEG003(baseUrl) {
  group('SMOKE-NEG-003: Empty body', () => {
    const url = `${baseUrl}/receive`;
    const params = getAuthParams({ 'Content-Type': 'application/x-protobuf' });
    const res = http.post(url, '', params);
    logRequest('smoke-neg-003', '/receive', 'POST', url, '[empty]', res);

    check(res, {
      'empty body returns 400 or 500': (r) => r.status === 400 || r.status === 500,
    });
  });
}
