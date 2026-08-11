// SMOKE-002: GET /metrics — Prometheus metrics endpoint
import http from 'k6/http';
import { check, group } from 'k6';
import { isOk, hasPrometheusMetric, contentTypeContains } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';

export function runSMOKE002(baseUrl) {
  group('SMOKE-002: GET /metrics', () => {
    const url = `${baseUrl}/metrics`;
    const res = http.get(url);
    logRequest('smoke-002', '/metrics', 'GET', url, null, res);

    check(res, {
      'metrics returns 200': isOk,
      'metrics has http_requests_total': hasPrometheusMetric('http_requests_total'),
      'metrics has kafka_queue_size': hasPrometheusMetric('kafka_queue_size'),
      'metrics content-type is text': contentTypeContains('text/plain'),
    });
  });
}
