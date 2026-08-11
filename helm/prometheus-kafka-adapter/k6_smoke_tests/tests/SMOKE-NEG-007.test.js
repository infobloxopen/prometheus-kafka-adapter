// SMOKE-NEG-007: GET /receive — Wrong HTTP method
import http from 'k6/http';
import { check, group } from 'k6';
import { isNotFoundOrMethodNotAllowed } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';

export function runNEG007(baseUrl) {
  group('SMOKE-NEG-007: Wrong method on /receive', () => {
    const url = `${baseUrl}/receive`;
    const res = http.get(url);
    logRequest('smoke-neg-007', '/receive', 'GET', url, null, res);

    check(res, {
      'GET /receive returns 404 or 405': isNotFoundOrMethodNotAllowed,
    });
  });
}
