// Reusable validation helpers for smoke tests

import { parseBody } from './utils.js';

// Status validation
export const isOk = (r) => r.status === 200;
export const isCreated = (r) => r.status === 200 || r.status === 201;
export const isBadRequest = (r) => r.status === 400;
export const isUnauthorized = (r) => r.status === 401;
export const isNotFound = (r) => r.status === 404;
export const isClientError = (r) => r.status >= 400 && r.status < 500;
export const isServerError = (r) => r.status >= 500 && r.status < 600;
export const isBadRequestOrServerError = (r) => r.status === 400 || r.status === 500;
export const isNotFoundOrMethodNotAllowed = (r) => r.status === 404 || r.status === 405;

// Response parsing validations
export const hasNoError = (r) => !parseBody(r).error;

// Generic field validation
export const bodyFieldEquals = (field, expected) => (r) => parseBody(r)[field] === expected;

// Content type validation
export const contentTypeContains = (expected) => (r) => {
  const ct = r.headers['Content-Type'] || '';
  return ct.toLowerCase().includes(expected.toLowerCase());
};

// Body contains string
export const bodyContains = (expected) => (r) => {
  return typeof r.body === 'string' && r.body.includes(expected);
};

// Prometheus metric presence check
export const hasPrometheusMetric = (metricName) => (r) => {
  return typeof r.body === 'string' && r.body.includes(metricName);
};
