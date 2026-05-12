// SMOKE-001: GET /healthz — Health check returns 200
import http from 'k6/http';
import { check, group } from 'k6';
import { isOk, bodyFieldEquals, contentTypeContains } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';
import { getAuthParams } from '../helpers/auth.js';

export function runSMOKE001(baseUrl) {
  group('SMOKE-001: GET /healthz', () => {
    const url = `${baseUrl}/healthz`;
    const res = http.get(url);
    logRequest('smoke-001', '/healthz', 'GET', url, null, res);

    check(res, {
      'healthz returns 200': isOk,
      'healthz body has status UP': bodyFieldEquals('status', 'UP'),
      'healthz content-type is json': contentTypeContains('application/json'),
    });
  });
}
