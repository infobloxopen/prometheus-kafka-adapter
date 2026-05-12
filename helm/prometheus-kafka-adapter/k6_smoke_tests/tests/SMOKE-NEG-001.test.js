// SMOKE-NEG-001: POST /receive — Non-snappy body
import http from 'k6/http';
import { check, group } from 'k6';
import { isBadRequest } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';
import { getAuthParams } from '../helpers/auth.js';

export function runNEG001(baseUrl) {
  group('SMOKE-NEG-001: Non-snappy body', () => {
    const url = `${baseUrl}/receive`;
    const params = getAuthParams({ 'Content-Type': 'application/x-protobuf' });
    const res = http.post(url, 'this is plain text, not snappy compressed', params);
    logRequest('smoke-neg-001', '/receive', 'POST', url, '[plain text]', res);

    check(res, {
      'non-snappy body returns 400': isBadRequest,
    });
  });
}
