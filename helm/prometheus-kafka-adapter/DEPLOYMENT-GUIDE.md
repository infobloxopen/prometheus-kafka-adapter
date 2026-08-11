# K6 Smoke Tests — Deployment Guide (prometheus-kafka-adapter)

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [First-Time Deployment](#first-time-deployment)
- [What to Redeploy When Things Change](#what-to-redeploy-when-things-change)
- [Local Development Runs](#local-development-runs)
- [Verification Commands](#verification-commands)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  Namespace: smoke-test-service                                      │
│                                                                     │
│  CronJob: pka-hr-watcher (every 3 min)                              │
│    └─ Watches HelmRelease "prometheus-kafka-adapter" in vela-system │
│    └─ On version change → creates Job from template                 │
│                                                                     │
│  Job: pka-k6-smoke-test (created dynamically)                       │
│    └─ container: k6-runner                                          │
│        └─ Runs main.js (modular K6 test suite)                      │
│        └─ Pushes metrics → Cortex                                   │
│                                                                     │
│  ConfigMaps:                                                        │
│    ├─ pka-k6-scripts           (JS test files + plan JSON)          │
│    ├─ pka-k6-job-template      (rendered Job YAML)                  │
│    ├─ pka-smoke-test-state     (tracks last-chart-version)          │
│    └─ pka-k6-results           (per-version result blobs)           │
│                                                                     │
│  Secret (optional):                                                 │
│    └─ pka-smoke-test-config    (Basic Auth credentials)             │
│                                                                     │
│  RBAC:                                                              │
│    ├─ ServiceAccount: pka-k6-smoke-test-sa                          │
│    ├─ ClusterRole: pka-k6-smoke-test-hr-reader → HelmRelease access│
│    ├─ Role: pka-k6-smoke-test-role             → ConfigMap/Job mgmt │
│    └─ (+ corresponding bindings)                                    │
│                                                                     │
│  GrafanaDashboard: pka-k6-smoke-tests (CRD, optional)              │
└─────────────────────────────────────────────────────────────────────┘
```

### Authentication Note

prometheus-kafka-adapter uses **optional HTTP Basic Auth** on the `/receive` endpoint (not CSP JWT or S2S tokens). No init container is needed for dynamic token fetch. If Basic Auth is enabled, credentials are injected from the Kubernetes Secret as environment variables.

---

## Prerequisites

| Requirement | Details |
|---|---|
| `kubectl` access | Must have cluster access to target cluster (e.g., `us-dev-5`) |
| Namespace | `smoke-test-service` must exist |
| Helm (optional) | Only needed for full Helm-based deployment. Manual `kubectl` works without it |
| Flux HelmRelease | `prometheus-kafka-adapter` HelmRelease in `vela-system` namespace (for CronJob auto-trigger) |

### Verify Prerequisites

```bash
# Check namespace exists
kubectl get ns smoke-test-service

# Check HelmRelease exists (for CronJob auto-trigger)
kubectl get hr prometheus-kafka-adapter -n vela-system
```

---

## First-Time Deployment

### Option A: Helm Install (Recommended)

```bash
cd prometheus-kafka-adapter/helm/prometheus-kafka-adapter

# Without Basic Auth
helm install pka-smoke-tests . \
  -n smoke-test-service \
  --set smokeTests.enabled=true \
  --set smokeTests.cluster=us-dev-5 \
  --set smokeTests.baseUrl=http://prometheus-kafka-adapter.default.svc.cluster.local:8080

# With Basic Auth
helm install pka-smoke-tests . \
  -n smoke-test-service \
  --set smokeTests.enabled=true \
  --set smokeTests.cluster=us-dev-5 \
  --set smokeTests.baseUrl=http://prometheus-kafka-adapter.default.svc.cluster.local:8080 \
  --set smokeTests.basicAuth.enabled=true \
  --set smokeTests.basicAuth.username=$BASIC_AUTH_USERNAME \
  --set smokeTests.basicAuth.password=$BASIC_AUTH_PASSWORD
```

This creates all resources in one command:
- ServiceAccount + RBAC (SA, 1 ClusterRole, 1 ClusterRoleBinding, 1 Role, 1 RoleBinding)
- ConfigMaps (scripts, job-template, state, results)
- CronJob (pka-hr-watcher)
- Secret (pka-smoke-test-config, if Basic Auth enabled)
- GrafanaDashboard CRD (if dashboard.enabled=true)

### Option B: Manual kubectl (Step-by-Step)

Use this if Helm is not available or you want granular control.

#### Step 1: Create the config secret (only if Basic Auth is enabled)

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: pka-smoke-test-config
  namespace: smoke-test-service
type: Opaque
stringData:
  basic-auth-username: "$BASIC_AUTH_USERNAME"
  basic-auth-password: "$BASIC_AUTH_PASSWORD"
EOF
```

#### Step 2: Deploy RBAC

```bash
# ServiceAccount
kubectl create sa pka-k6-smoke-test-sa -n smoke-test-service

# ClusterRole: read HelmRelease
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pka-k6-smoke-test-hr-reader
rules:
  - apiGroups: ["helm.toolkit.fluxcd.io"]
    resources: ["helmreleases"]
    verbs: ["get", "list"]
EOF

# ClusterRoleBinding: SA → HR reader
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pka-k6-smoke-test-hr-reader-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pka-k6-smoke-test-hr-reader
subjects:
  - kind: ServiceAccount
    name: pka-k6-smoke-test-sa
    namespace: smoke-test-service
EOF

# Role: manage ConfigMaps + Jobs in namespace
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pka-k6-smoke-test-role
  namespace: smoke-test-service
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "create", "update", "patch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "create", "delete"]
EOF

# RoleBinding
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pka-k6-smoke-test-binding
  namespace: smoke-test-service
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pka-k6-smoke-test-role
subjects:
  - kind: ServiceAccount
    name: pka-k6-smoke-test-sa
    namespace: smoke-test-service
EOF
```

#### Step 3: Deploy ConfigMaps

```bash
cd prometheus-kafka-adapter

# Scripts ConfigMap
kubectl create configmap pka-k6-scripts -n smoke-test-service \
  --from-file=main.js=smoke-tests/main.js \
  --from-file=config.js=smoke-tests/config/config.js \
  --from-file=auth.js=smoke-tests/helpers/auth.js \
  --from-file=validators.js=smoke-tests/helpers/validators.js \
  --from-file=utils.js=smoke-tests/helpers/utils.js \
  --from-file=resourceHelpers.js=smoke-tests/helpers/resourceHelpers.js \
  --from-file=smoke-test-plan.json=smoke-test-plan.json \
  --dry-run=client -o yaml | kubectl apply -f -

# State ConfigMap
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: pka-smoke-test-state
  namespace: smoke-test-service
data:
  last-chart-version: "initial"
EOF

# Results ConfigMap
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: pka-k6-results
  namespace: smoke-test-service
data: {}
EOF
```

#### Step 4: Deploy Job Template ConfigMap

The job template needs to be a **rendered** YAML (not a Helm template with `{{ }}` placeholders).

```bash
cat <<'JOBEOF' > /tmp/pka-k6-runner-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pka-k6-smoke-test
  namespace: smoke-test-service
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
    app.kubernetes.io/component: k6-runner
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: k6-smoke-tests
        app.kubernetes.io/part-of: prometheus-kafka-adapter
        app.kubernetes.io/component: k6-runner
    spec:
      serviceAccountName: pka-k6-smoke-test-sa
      restartPolicy: Never
      containers:
        - name: k6-runner
          image: harbor.services.sdp.infoblox.com/proxy_cache_docker_hub/grafana/k6:1.7.1
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -e
              echo "=== Prometheus-Kafka-Adapter K6 Smoke Tests ==="
              echo "  Base URL: ${BASE_URL}"
              echo "  Metrics -> Cortex (${K6_PROMETHEUS_RW_SERVER_URL})"
              echo ""

              set +e
              k6 run /scripts/main.js \
                --out experimental-prometheus-rw \
                --tag version="${CHART_VERSION}" \
                --tag service=prometheus-kafka-adapter \
                --tag cluster="${CLUSTER}" \
                --log-format json --verbose
              K6_EXIT=$?
              set -e
              echo "K6 exit code: ${K6_EXIT}"
              exit ${K6_EXIT}
          env:
            - name: BASE_URL
              value: "http://prometheus-kafka-adapter.default.svc.cluster.local:8080"
            - name: CLUSTER
              value: "us-dev-5"
            - name: CHART_VERSION
              valueFrom:
                configMapKeyRef:
                  name: pka-smoke-test-state
                  key: last-chart-version
            - name: K6_PROMETHEUS_RW_SERVER_URL
              value: "http://cortex.services.sdp.infoblox.com/api/v1/push"
            - name: K6_PROMETHEUS_RW_HEADERS_X-Scope-OrgID
              value: "us-dev-5"
            - name: K6_PROMETHEUS_RW_TREND_STATS
              value: "avg,p(95)"
          resources:
            requests: { cpu: "200m", memory: "256Mi" }
            limits:   { cpu: "500m", memory: "512Mi" }
          volumeMounts:
            - name: k6-scripts
              mountPath: /scripts
              readOnly: true
      volumes:
        - name: k6-scripts
          configMap:
            name: pka-k6-scripts
            defaultMode: 0644
JOBEOF

kubectl create configmap pka-k6-job-template -n smoke-test-service \
  --from-file=k6-runner-job.yaml=/tmp/pka-k6-runner-job.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### Step 5: Deploy CronJob

```bash
helm template pka-smoke-tests . \
  -n smoke-test-service \
  --set smokeTests.enabled=true \
  --set smokeTests.cluster=us-dev-5 \
  -s templates/smoke-tests/smoke-tests-cronjob.yaml | kubectl apply -f -
```

Or use `kubectl apply` with the rendered CronJob YAML.

---

## What to Redeploy When Things Change

### Quick Reference Matrix

| What Changed | What to Redeploy | Command |
|---|---|---|
| **Test logic** (any `.js` file) | `pka-k6-scripts` ConfigMap | [Scripts ConfigMap](#redeploy-scripts-configmap) |
| **Test credentials** (Basic Auth) | `pka-smoke-test-config` Secret | [Config Secret](#redeploy-config-secret) |
| **Job spec** (images, env vars, containers) | `pka-k6-job-template` ConfigMap | [Job Template](#redeploy-job-template) |
| **CronJob schedule or watcher logic** | CronJob `pka-hr-watcher` | [CronJob](#redeploy-cronjob) |
| **Grafana dashboard JSON** | GrafanaDashboard CRD | [Dashboard](#redeploy-dashboard) |
| **Target cluster change** | Job template + CronJob + Secret + values.yaml | [Cluster Change](#cluster-change) |
| **Container image version** (k6 or kubectl) | `pka-k6-job-template` + CronJob | [Job Template](#redeploy-job-template) + [CronJob](#redeploy-cronjob) |

### Redeploy Scripts ConfigMap

**When:** Any `.js` file in `smoke-tests/` is modified.

```bash
cd prometheus-kafka-adapter

kubectl create configmap pka-k6-scripts -n smoke-test-service \
  --from-file=main.js=smoke-tests/main.js \
  --from-file=config.js=smoke-tests/config/config.js \
  --from-file=auth.js=smoke-tests/helpers/auth.js \
  --from-file=validators.js=smoke-tests/helpers/validators.js \
  --from-file=utils.js=smoke-tests/helpers/utils.js \
  --from-file=resourceHelpers.js=smoke-tests/helpers/resourceHelpers.js \
  --from-file=smoke-test-plan.json=smoke-test-plan.json \
  --dry-run=client -o yaml | kubectl replace -f -
```

> **Note:** Uses `kubectl replace` (not `apply`) because the ConfigMap may exceed server-side apply annotation limits.

### Redeploy Config Secret

**When:** Basic Auth credentials change.

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: pka-smoke-test-config
  namespace: smoke-test-service
type: Opaque
stringData:
  basic-auth-username: "$BASIC_AUTH_USERNAME"
  basic-auth-password: "$BASIC_AUTH_PASSWORD"
EOF
```

### Redeploy Job Template

**When:** Container images updated, environment variables changed, or volume mounts added.

1. Edit the rendered YAML in `/tmp/pka-k6-runner-job.yaml` (or regenerate per [Step 4](#step-4-deploy-job-template-configmap))
2. Replace the ConfigMap:

```bash
kubectl create configmap pka-k6-job-template -n smoke-test-service \
  --from-file=k6-runner-job.yaml=/tmp/pka-k6-runner-job.yaml \
  --dry-run=client -o yaml | kubectl replace -f -
```

> **Important:** This ConfigMap contains **rendered** YAML, not Helm templates. Don't put `{{ }}` placeholders in it.

### Redeploy CronJob

**When:** Polling schedule, watcher container image, or HelmRelease name/namespace changes.

```bash
helm template pka-smoke-tests . \
  -n smoke-test-service \
  --set smokeTests.enabled=true \
  --set smokeTests.cluster=us-dev-5 \
  -s templates/smoke-tests/smoke-tests-cronjob.yaml | kubectl apply -f -
```

### Redeploy Dashboard

**When:** Grafana dashboard JSON or cluster name changes.

```bash
helm template pka-smoke-tests . \
  -n smoke-test-service \
  --set smokeTests.enabled=true \
  --set smokeTests.cluster=us-dev-5 \
  --set smokeTests.dashboard.enabled=true \
  -s templates/smoke-tests/smoke-tests-dashboard.yaml | kubectl apply -f -
```

### Cluster Change

**When:** Deploying to a different cluster (e.g., `us-dev-5` → `us-dev-2`).

1. Update `values.yaml`:
   - `smokeTests.cluster`
   - `smokeTests.baseUrl`
   - `smokeTests.cortex.orgId`
2. Redeploy **all** resources:
   - Config Secret (new credentials if different per cluster)
   - Scripts ConfigMap (if cluster referenced in JS)
   - Job Template (cluster env var, Cortex orgId, baseUrl)
   - CronJob (kubectl image may differ)
   - Dashboard (cluster in title)

Or simply:
```bash
helm upgrade pka-smoke-tests . \
  -n smoke-test-service \
  --set smokeTests.enabled=true \
  --set smokeTests.cluster=NEW-CLUSTER \
  --set smokeTests.baseUrl=NEW-BASE-URL
```

---

## Local Development Runs

### Quick Local Run

```bash
cd prometheus-kafka-adapter

# Run all scenarios
k6 run smoke-tests/main.js \
  -e BASE_URL=http://localhost:8080 \
  --verbose

# With Basic Auth
k6 run smoke-tests/main.js \
  -e BASE_URL=http://localhost:8080 \
  -e BASIC_AUTH_USERNAME=myuser \
  -e BASIC_AUTH_PASSWORD=mypass \
  --verbose
```

---

## Verification Commands

### Check All Resources Exist

```bash
NS=smoke-test-service

# ConfigMaps
kubectl get configmap pka-k6-scripts -n $NS
kubectl get configmap pka-k6-job-template -n $NS
kubectl get configmap pka-smoke-test-state -n $NS
kubectl get configmap pka-k6-results -n $NS

# Secret (only if Basic Auth enabled)
kubectl get secret pka-smoke-test-config -n $NS

# RBAC
kubectl get sa pka-k6-smoke-test-sa -n $NS
kubectl get clusterrole pka-k6-smoke-test-hr-reader
kubectl get clusterrolebinding pka-k6-smoke-test-hr-reader-binding
kubectl get role pka-k6-smoke-test-role -n $NS
kubectl get rolebinding pka-k6-smoke-test-binding -n $NS

# CronJob
kubectl get cronjob pka-hr-watcher -n $NS

# Dashboard (optional)
kubectl get grafanadashboards.grafana.integreatly.org pka-k6-smoke-tests -n $NS
```

### Trigger a Manual Test Run

```bash
# Delete existing job if present
kubectl delete job pka-k6-smoke-test -n smoke-test-service --ignore-not-found

# Apply job from template
kubectl get configmap pka-k6-job-template -n smoke-test-service \
  -ojsonpath='{.data.k6-runner-job\.yaml}' | kubectl apply -f -

# Watch logs
kubectl logs -f job/pka-k6-smoke-test -n smoke-test-service -c k6-runner
```

### Check CronJob Status

```bash
# Last trigger time
kubectl get cronjob pka-hr-watcher -n smoke-test-service

# Recent watcher pod logs
kubectl logs -l app.kubernetes.io/component=hr-watcher -n smoke-test-service --tail=20

# Check tracked version
kubectl get configmap pka-smoke-test-state -n smoke-test-service -ojsonpath='{.data.last-chart-version}'
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Job fails with `connection refused` | BASE_URL incorrect or service not running | Verify `smokeTests.baseUrl` points to the correct service endpoint |
| K6 tests fail on `/receive` with 401 | Basic Auth enabled but credentials not set | Deploy the secret with correct `BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD` |
| K6 tests fail on `/receive` with 500 | Kafka broker unreachable from the adapter | Check Kafka connectivity from the adapter pod |
| ConfigMap too large for `apply` | Annotation limit exceeded | Use `kubectl replace` instead |
| Job not auto-created | CronJob not detecting version change | Check `pka-smoke-test-state` ConfigMap version |
| Job template has `{{ }}` in logs | Raw Helm template stored instead of rendered YAML | Re-render and [redeploy job template](#redeploy-job-template) |
| RBAC forbidden errors | ServiceAccount not bound to role | Redeploy [RBAC](#step-2-deploy-rbac) |
