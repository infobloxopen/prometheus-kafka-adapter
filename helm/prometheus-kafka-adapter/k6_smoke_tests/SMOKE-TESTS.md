# Prometheus Kafka Adapter — K6 Smoke Tests

## Overview

Automated K6 smoke tests for `prometheus-kafka-adapter`. Tests run on every HelmRelease version change via a CronJob watcher.

## Scenarios

| ID | Scenario | Method | Endpoint | Expected |
|:---|:---------|:-------|:---------|:---------|
| SMOKE-001 | Health Check | GET | /healthz | 200 + `{"status":"UP"}` |
| SMOKE-002 | Metrics Endpoint | GET | /metrics | 200 + prometheus format |
| SMOKE-003 | Receive Reachability | POST | /receive | 400 (invalid payload) |
| SMOKE-004 | Counter Validation | GET | /metrics | counters incremented |
| SMOKE-NEG-001 | Non-Snappy Body | POST | /receive | 400 |
| SMOKE-NEG-002 | Invalid Protobuf | POST | /receive | 400 |
| SMOKE-NEG-003 | Empty Body | POST | /receive | 400/500 |
| SMOKE-NEG-004 | No Auth (if enabled) | POST | /receive | 401 |
| SMOKE-NEG-005 | Invalid Creds (if enabled) | POST | /receive | 401 |
| SMOKE-NEG-006 | Undefined Route | GET | /nonexistent | 404/405 |
| SMOKE-NEG-007 | Wrong Method | GET | /receive | 404/405 |

## Architecture

```
CronJob (*/3) → detect HelmRelease version change → validate rollout → trigger K6 Job
                                                                            ↓
                                                              Run smoke tests → push metrics to Cortex
                                                                            ↓
                                                              Grafana dashboard (pka-k6-smoke-tests)
```

## Deployment

### Deploy to cluster (kubectl)

```bash
./scripts/deploy-to-cluster.sh --base-url http://prometheus-kafka-adapter.ngp-cp.svc.cluster.local:8080
```

### Deploy via Helm

```bash
helm upgrade --install pka-smoke-tests ./helm/prometheus-kafka-adapter \
  -n smoke-test-service \
  --set smokeTests.enabled=true \
  --set smokeTests.baseUrl=http://prometheus-kafka-adapter.ngp-cp.svc.cluster.local:8080
```

### Run locally

```bash
export BASE_URL=http://localhost:8080
cd k6/ && k6 run smoke-tests-modular.js
```

Or use the local helper:

```bash
cd local/ && ./run-smoke-tests.sh
```

## Manual Trigger

```bash
kubectl delete job pka-k6-smoke-test -n smoke-test-service --ignore-not-found
kubectl get configmap pka-k6-job-template -n smoke-test-service \
  -ojsonpath='{.data.k6-runner-job\.yaml}' | kubectl apply -f -
kubectl logs -f job/pka-k6-smoke-test -n smoke-test-service -c k6-runner
```

## Dashboard

- **UID**: `pka-k6-smoke-tests`
- **Folder**: K6 Smoke Tests
- **Datasource**: Prometheus (Cortex, OrgID: us-dev-5)
- **Metrics**: `k6_checks_rate`, `k6_iterations_total`, `k6_http_req_duration_avg/p95`

## Pass Criteria

≥ 80% of all K6 checks must pass for the test run to be considered successful.
