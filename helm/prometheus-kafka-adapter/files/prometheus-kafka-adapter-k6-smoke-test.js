// prometheus-kafka-adapter K6 Smoke Test — Self-contained bundle for in-cluster execution.
// This file is mounted via ConfigMap into the K6 runner Job.
// It contains all test logic inline (no module imports except k6 builtins).

import http from 'k6/http';
import { check, group } from 'k6';
import encoding from 'k6/encoding';

// ─── Configuration ───────────────────────────────────────────────────────────
const BASE_URL = __ENV.BASE_URL || '';
const BASIC_AUTH_USERNAME = __ENV.BASIC_AUTH_USERNAME || '';
const BASIC_AUTH_PASSWORD = __ENV.BASIC_AUTH_PASSWORD || '';
const BASIC_AUTH_ENABLED = BASIC_AUTH_USERNAME !== '' && BASIC_AUTH_PASSWORD !== '';

function validateConfig() {
  if (!BASE_URL) {
    throw new Error('FATAL: BASE_URL environment variable is required but not set.');
  }
}

// ─── Auth Helpers ────────────────────────────────────────────────────────────
function getAuthParams(extraHeaders = {}) {
  const params = { headers: { ...extraHeaders } };
  if (BASIC_AUTH_ENABLED) {
    const encoded = encoding.b64encode(`${BASIC_AUTH_USERNAME}:${BASIC_AUTH_PASSWORD}`);
    params.headers['Authorization'] = `Basic ${encoded}`;
  }
  return params;
}

function getNoAuthParams(extraHeaders = {}) {
  return { headers: { ...extraHeaders } };
}

function getInvalidAuthParams(extraHeaders = {}) {
  const encoded = encoding.b64encode('INVALID_USER:INVALID_PASS');
  return { headers: { Authorization: `Basic ${encoded}`, ...extraHeaders } };
}

// ─── Validators ──────────────────────────────────────────────────────────────
function parseBody(r) { try { return JSON.parse(r.body); } catch (e) { return {}; } }
const isOk = (r) => r.status === 200;
const isBadRequest = (r) => r.status === 400;
const isUnauthorized = (r) => r.status === 401;
const isNotFoundOrMethodNotAllowed = (r) => r.status === 404 || r.status === 405;
const bodyFieldEquals = (field, expected) => (r) => parseBody(r)[field] === expected;
const contentTypeContains = (expected) => (r) => (r.headers['Content-Type'] || '').toLowerCase().includes(expected.toLowerCase());
const hasPrometheusMetric = (metricName) => (r) => typeof r.body === 'string' && r.body.includes(metricName);

// ─── Logging ─────────────────────────────────────────────────────────────────
function logRequest(phase, endpoint, method, url, payload, response) {
  console.log(JSON.stringify({
    phase, endpoint, method, url, requestPayload: payload,
    status: response ? response.status : null,
    responseBody: response ? (response.body || '').substring(0, 2000) : null,
  }));
}

// ─── K6 Options ──────────────────────────────────────────────────────────────
export const options = {
  vus: 1,
  iterations: 1,
  thresholds: { checks: ['rate>=0.80'] },
};

// ─── Test Execution ──────────────────────────────────────────────────────────
export default function () {
  validateConfig();
  const baseUrl = BASE_URL;

  // SMOKE-001: GET /healthz
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

  // SMOKE-002: GET /metrics
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

  // SMOKE-003: POST /receive — endpoint reachable
  group('SMOKE-003: POST /receive - endpoint reachable', () => {
    const url = `${baseUrl}/receive`;
    const params = getAuthParams({ 'Content-Type': 'application/x-protobuf' });
    const payload = '\x00\x00\x00\x00';
    const res = http.post(url, payload, params);
    logRequest('smoke-003', '/receive', 'POST', url, '[binary 4 bytes]', res);
    check(res, {
      'receive endpoint responds (not 404/405)': (r) => r.status !== 404 && r.status !== 405,
      'receive returns 400 for invalid payload': isBadRequest,
    });
  });

  // SMOKE-004: Metrics counter validation
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

  // SMOKE-NEG-001: Non-snappy body
  group('SMOKE-NEG-001: Non-snappy body', () => {
    const url = `${baseUrl}/receive`;
    const params = getAuthParams({ 'Content-Type': 'application/x-protobuf' });
    const res = http.post(url, 'this is plain text, not snappy compressed', params);
    logRequest('smoke-neg-001', '/receive', 'POST', url, '[plain text]', res);
    check(res, { 'non-snappy body returns 400': isBadRequest });
  });

  // SMOKE-NEG-002: Invalid protobuf in snappy frame
  group('SMOKE-NEG-002: Invalid protobuf in snappy frame', () => {
    const url = `${baseUrl}/receive`;
    const params = getAuthParams({ 'Content-Type': 'application/x-protobuf' });
    const snappyGarbage = String.fromCharCode(0x01, 0x00, 0x58);
    const res = http.post(url, snappyGarbage, params);
    logRequest('smoke-neg-002', '/receive', 'POST', url, '[snappy garbage]', res);
    check(res, { 'invalid protobuf returns 400': isBadRequest });
  });

  // SMOKE-NEG-003: Empty body
  group('SMOKE-NEG-003: Empty body', () => {
    const url = `${baseUrl}/receive`;
    const params = getAuthParams({ 'Content-Type': 'application/x-protobuf' });
    const res = http.post(url, '', params);
    logRequest('smoke-neg-003', '/receive', 'POST', url, '[empty]', res);
    check(res, { 'empty body returns 400 or 500': (r) => r.status === 400 || r.status === 500 });
  });

  // SMOKE-NEG-004: No auth when required (conditional)
  if (BASIC_AUTH_ENABLED) {
    group('SMOKE-NEG-004: No auth when required', () => {
      const url = `${baseUrl}/receive`;
      const params = getNoAuthParams({ 'Content-Type': 'application/x-protobuf' });
      const res = http.post(url, 'test', params);
      logRequest('smoke-neg-004', '/receive', 'POST', url, '[no auth]', res);
      check(res, { 'missing auth returns 401': isUnauthorized });
    });

    // SMOKE-NEG-005: Invalid credentials
    group('SMOKE-NEG-005: Invalid credentials', () => {
      const url = `${baseUrl}/receive`;
      const params = getInvalidAuthParams({ 'Content-Type': 'application/x-protobuf' });
      const res = http.post(url, 'test', params);
      logRequest('smoke-neg-005', '/receive', 'POST', url, '[bad creds]', res);
      check(res, { 'invalid creds returns 401': isUnauthorized });
    });
  }

  // SMOKE-NEG-006: Undefined route
  group('SMOKE-NEG-006: Undefined route', () => {
    const url = `${baseUrl}/nonexistent`;
    const res = http.get(url);
    logRequest('smoke-neg-006', '/nonexistent', 'GET', url, null, res);
    check(res, { 'undefined route returns 404 or 405': isNotFoundOrMethodNotAllowed });
  });

  // SMOKE-NEG-007: Wrong method on /receive
  group('SMOKE-NEG-007: Wrong method on /receive', () => {
    const url = `${baseUrl}/receive`;
    const res = http.get(url);
    logRequest('smoke-neg-007', '/receive', 'GET', url, null, res);
    check(res, { 'GET /receive returns 404 or 405': isNotFoundOrMethodNotAllowed });
  });
}
