// SMOKE-NEG-006: GET /nonexistent — Undefined route
import http from 'k6/http';
import { check, group } from 'k6';
import { isNotFoundOrMethodNotAllowed } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';

export function runNEG006(baseUrl) {
  group('SMOKE-NEG-006: Undefined route', () => {
    const url = `${baseUrl}/nonexistent`;
    const res = http.get(url);
    logRequest('smoke-neg-006', '/nonexistent', 'GET', url, null, res);

    check(res, {
      'undefined route returns 404 or 405': isNotFoundOrMethodNotAllowed,
    });
  });
}
