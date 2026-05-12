// SMOKE-004: GET /metrics — Counter incremented after request
import http from 'k6/http';
import { check, group } from 'k6';
import { isOk, hasPrometheusMetric } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';

export function runSMOKE004(baseUrl) {
  group('SMOKE-004: Metrics counter validation', () => {
    const url = `${baseUrl}/metrics`;
    const res = http.get(url);
    logRequest('smoke-004', '/metrics', 'GET', url, null, res);

    check(res, {
      'metrics returns 200 (post-request)': isOk,
      'http_requests_total incremented': hasPrometheusMetric('http_requests_total'),
      'incoming_prometheus_batches_total present': hasPrometheusMetric('incoming_prometheus_batches_total'),
    });
  });
}
