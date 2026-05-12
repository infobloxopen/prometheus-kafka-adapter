#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy-smoke-tests.sh — Deploy K6 smoke test resources for prometheus-kafka-adapter
#
# Usage:
#   ./scripts/deploy-smoke-tests.sh [OPTIONS]
#
# Options:
#   --namespace <ns>         Target namespace (default: smoke-test-service)
#   --cluster <name>         Cluster identifier (default: us-dev-5)
#   --base-url <url>         Base URL for the adapter service (required)
#   --basic-auth             Enable Basic Auth for /receive endpoint
#   --basic-auth-user <u>    Basic Auth username (or set BASIC_AUTH_USERNAME env)
#   --basic-auth-pass <p>    Basic Auth password (or set BASIC_AUTH_PASSWORD env)
#   --helm                   Use Helm install (default: kubectl manual deploy)
#   --upgrade                Helm upgrade instead of install
#   --dashboard              Enable Grafana dashboard deployment
#   --dry-run                Print what would be done without applying
#   --help                   Show this help
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
NAMESPACE="smoke-test-service"
CLUSTER="us-dev-5"
BASE_URL=""
BASIC_AUTH_ENABLED=false
BASIC_AUTH_USER="${BASIC_AUTH_USERNAME:-}"
BASIC_AUTH_PASS="${BASIC_AUTH_PASSWORD:-}"
USE_HELM=false
HELM_UPGRADE=false
DASHBOARD_ENABLED=false
DRY_RUN=false

K6_IMAGE="harbor.services.sdp.infoblox.com/proxy_cache_docker_hub/grafana/k6:1.7.1"
KUBECTL_IMAGE="harbor.services.sdp.infoblox.com/infobloxcto/kubectl:1.30.7"
CORTEX_URL="http://cortex.services.sdp.infoblox.com/api/v1/push"

# Resource naming
SERVICE_NAME="pka"
SA_NAME="${SERVICE_NAME}-k6-smoke-test-sa"
CR_HR="${SERVICE_NAME}-k6-smoke-test-hr-reader"
CRB_HR="${SERVICE_NAME}-k6-smoke-test-hr-reader-binding"
ROLE_NAME="${SERVICE_NAME}-k6-smoke-test-role"
RB_NAME="${SERVICE_NAME}-k6-smoke-test-binding"
SCRIPTS_CM="${SERVICE_NAME}-k6-scripts"
JOB_TEMPLATE_CM="${SERVICE_NAME}-k6-job-template"
STATE_CM="${SERVICE_NAME}-smoke-test-state"
RESULTS_CM="${SERVICE_NAME}-k6-results"
SECRET_NAME="${SERVICE_NAME}-smoke-test-config"
CRONJOB_NAME="${SERVICE_NAME}-hr-watcher"

# ─── Script directory detection ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6_SMOKE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${K6_SMOKE_DIR}/../.." && pwd)"
HELM_DIR="${REPO_ROOT}/helm/prometheus-kafka-adapter"
SMOKE_TESTS_DIR="${K6_SMOKE_DIR}/k6"

# ─── Parse arguments ────────────────────────────────────────────────────────
usage() {
  sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)    NAMESPACE="$2"; shift 2 ;;
    --cluster)      CLUSTER="$2"; shift 2 ;;
    --base-url)     BASE_URL="$2"; shift 2 ;;
    --basic-auth)   BASIC_AUTH_ENABLED=true; shift ;;
    --basic-auth-user) BASIC_AUTH_USER="$2"; shift 2 ;;
    --basic-auth-pass) BASIC_AUTH_PASS="$2"; shift 2 ;;
    --helm)         USE_HELM=true; shift ;;
    --upgrade)      HELM_UPGRADE=true; USE_HELM=true; shift ;;
    --dashboard)    DASHBOARD_ENABLED=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --help|-h)      usage ;;
    *) echo "ERROR: Unknown option: $1"; usage ;;
  esac
done

# ─── Validation ──────────────────────────────────────────────────────────────
APPROVED_CLUSTERS=("us-dev-5" "us-dev-2" "env-2a" "stage")

validate_cluster() {
  local found=false
  for c in "${APPROVED_CLUSTERS[@]}"; do
    if [[ "$CLUSTER" == "$c" ]]; then
      found=true
      break
    fi
  done
  if [[ "$found" == "false" ]]; then
    echo "WARNING: Cluster '${CLUSTER}' is not in the approved list: ${APPROVED_CLUSTERS[*]}"
    echo "         Proceeding anyway (service may be deployed standalone)."
  fi
}

validate_prereqs() {
  if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl is required but not found in PATH"
    exit 1
  fi

  if [[ "$USE_HELM" == "true" ]] && ! command -v helm &>/dev/null; then
    echo "ERROR: --helm specified but helm is not found in PATH"
    exit 1
  fi

  if [[ -z "$BASE_URL" && "$USE_HELM" == "false" ]]; then
    echo "ERROR: --base-url is required for kubectl deployment"
    echo "       Example: --base-url http://prometheus-kafka-adapter.default.svc.cluster.local:8080"
    exit 1
  fi

  if [[ "$BASIC_AUTH_ENABLED" == "true" ]]; then
    if [[ -z "$BASIC_AUTH_USER" ]]; then
      echo "ERROR: --basic-auth requires --basic-auth-user or BASIC_AUTH_USERNAME env var"
      exit 1
    fi
    if [[ -z "$BASIC_AUTH_PASS" ]]; then
      echo "ERROR: --basic-auth requires --basic-auth-pass or BASIC_AUTH_PASSWORD env var"
      exit 1
    fi
  fi
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
kube_apply() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] kubectl apply (shown below):"
    cat
    echo "---"
  else
    kubectl apply -f -
  fi
}

kube_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

step() {
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  $1"
  echo "═══════════════════════════════════════════════════════════════"
}

ok() {
  echo "  ✓ $1"
}

# ─── Helm Deploy ─────────────────────────────────────────────────────────────
deploy_helm() {
  step "Deploying via Helm"

  local CMD="install"
  if [[ "$HELM_UPGRADE" == "true" ]]; then
    CMD="upgrade"
  fi

  local HELM_ARGS=(
    "${SERVICE_NAME}-smoke-tests" "${HELM_DIR}"
    -n "${NAMESPACE}"
    --set "smokeTests.enabled=true"
    --set "smokeTests.cluster=${CLUSTER}"
    --set "smokeTests.cortex.orgId=${CLUSTER}"
  )

  if [[ -n "$BASE_URL" ]]; then
    HELM_ARGS+=(--set "smokeTests.baseUrl=${BASE_URL}")
  fi

  if [[ "$BASIC_AUTH_ENABLED" == "true" ]]; then
    HELM_ARGS+=(
      --set "smokeTests.basicAuth.enabled=true"
      --set "smokeTests.basicAuth.username=${BASIC_AUTH_USER}"
      --set "smokeTests.basicAuth.password=${BASIC_AUTH_PASS}"
    )
  fi

  if [[ "$DASHBOARD_ENABLED" == "true" ]]; then
    HELM_ARGS+=(--set "smokeTests.dashboard.enabled=true")
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] helm ${CMD} ${HELM_ARGS[*]}"
    helm template "${HELM_ARGS[@]}"
  else
    helm "${CMD}" "${HELM_ARGS[@]}"
  fi

  ok "Helm ${CMD} complete"
}

# ─── kubectl Manual Deploy ───────────────────────────────────────────────────

deploy_namespace() {
  step "Step 0: Ensure namespace exists"
  kube_cmd kubectl get ns "${NAMESPACE}" &>/dev/null 2>&1 || {
    echo "  Creating namespace ${NAMESPACE}..."
    kubectl create namespace "${NAMESPACE}" <<< "" | kube_apply
  }
  ok "Namespace ${NAMESPACE}"
}

deploy_secret() {
  step "Step 1: Deploy Secret (Basic Auth credentials)"

  if [[ "$BASIC_AUTH_ENABLED" != "true" ]]; then
    echo "  Basic Auth not enabled — skipping secret creation."
    return
  fi

  cat <<EOF | kube_apply
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
    app.kubernetes.io/component: credentials
type: Opaque
stringData:
  basic-auth-username: "${BASIC_AUTH_USER}"
  basic-auth-password: "${BASIC_AUTH_PASS}"
EOF
  ok "Secret ${SECRET_NAME}"
}

deploy_rbac() {
  step "Step 2: Deploy RBAC"

  # ServiceAccount
  cat <<EOF | kube_apply
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
    app.kubernetes.io/component: automation
EOF
  ok "ServiceAccount ${SA_NAME}"

  # ClusterRole: HelmRelease reader
  cat <<EOF | kube_apply
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${CR_HR}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
rules:
  - apiGroups: ["helm.toolkit.fluxcd.io"]
    resources: ["helmreleases"]
    verbs: ["get", "list"]
EOF
  ok "ClusterRole ${CR_HR}"

  # ClusterRoleBinding: SA → HR reader
  cat <<EOF | kube_apply
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${CRB_HR}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${CR_HR}
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${NAMESPACE}
EOF
  ok "ClusterRoleBinding ${CRB_HR}"

  # Role: manage ConfigMaps + Jobs in namespace
  cat <<EOF | kube_apply
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${ROLE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "create", "update", "patch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "create", "delete"]
EOF
  ok "Role ${ROLE_NAME}"

  # RoleBinding
  cat <<EOF | kube_apply
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${RB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${ROLE_NAME}
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${NAMESPACE}
EOF
  ok "RoleBinding ${RB_NAME}"

  # Role in SERVICE namespace: read pods/deployments for rollout validation
  SVC_NS="default"
  cat <<EOF | kube_apply
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${SERVICE_NAME}-k6-smoke-test-pod-reader
  namespace: ${SVC_NS}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list"]
EOF
  ok "Role ${SERVICE_NAME}-k6-smoke-test-pod-reader (ns: ${SVC_NS})"

  cat <<EOF | kube_apply
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${SERVICE_NAME}-k6-smoke-test-pod-reader-binding
  namespace: ${SVC_NS}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${SERVICE_NAME}-k6-smoke-test-pod-reader
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${NAMESPACE}
EOF
  ok "RoleBinding ${SERVICE_NAME}-k6-smoke-test-pod-reader-binding (ns: ${SVC_NS})"
}

deploy_configmaps() {
  step "Step 3: Deploy ConfigMaps"

  # ── Scripts ConfigMap ──
  local FROM_FILE_ARGS=(
    "--from-file=config.js=${SMOKE_TESTS_DIR}/modular-config.js"
    "--from-file=auth.js=${SMOKE_TESTS_DIR}/modular-auth.js"
    "--from-file=validators.js=${SMOKE_TESTS_DIR}/modular-http-client.js"
    "--from-file=utils.js=${SMOKE_TESTS_DIR}/modular-scenario-runner.js"
    "--from-file=resourceHelpers.js=${SMOKE_TESTS_DIR}/modular-resource-tracker.js"
  )

  # Add main.js if it exists
  if [[ -f "${SMOKE_TESTS_DIR}/smoke-tests-modular.js" ]]; then
    FROM_FILE_ARGS+=("--from-file=main.js=${SMOKE_TESTS_DIR}/smoke-tests-modular.js")
  fi

  # Add smoke-test-config.json if it exists
  if [[ -f "${SMOKE_TESTS_DIR}/smoke-test-config.json" ]]; then
    FROM_FILE_ARGS+=("--from-file=smoke-test-plan.json=${SMOKE_TESTS_DIR}/smoke-test-config.json")
  fi

  # Add test files if they exist
  if [[ -d "${SMOKE_TESTS_DIR}/tests" ]]; then
    for TEST_FILE in "${SMOKE_TESTS_DIR}/tests/"*.test.js; do
      if [[ -f "$TEST_FILE" ]]; then
        local BASENAME
        BASENAME="$(basename "$TEST_FILE")"
        FROM_FILE_ARGS+=("--from-file=${BASENAME}=${TEST_FILE}")
      fi
    done
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] kubectl create configmap ${SCRIPTS_CM} -n ${NAMESPACE} ${FROM_FILE_ARGS[*]} --dry-run=client -o yaml | kubectl apply -f -"
  else
    kubectl create configmap "${SCRIPTS_CM}" -n "${NAMESPACE}" \
      "${FROM_FILE_ARGS[@]}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
  ok "ConfigMap ${SCRIPTS_CM}"

  # ── State ConfigMap ──
  cat <<EOF | kube_apply
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${STATE_CM}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
    app.kubernetes.io/component: state
data:
  last-chart-version: "initial"
EOF
  ok "ConfigMap ${STATE_CM}"

  # ── Results ConfigMap ──
  cat <<EOF | kube_apply
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${RESULTS_CM}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
    app.kubernetes.io/component: results
EOF
  ok "ConfigMap ${RESULTS_CM}"
}

deploy_job_template() {
  step "Step 4: Deploy Job Template ConfigMap"

  # Build env section for Basic Auth
  local BASIC_AUTH_ENV=""
  if [[ "$BASIC_AUTH_ENABLED" == "true" ]]; then
    BASIC_AUTH_ENV="
            - name: BASIC_AUTH_USERNAME
              valueFrom:
                secretKeyRef:
                  name: ${SECRET_NAME}
                  key: basic-auth-username
            - name: BASIC_AUTH_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${SECRET_NAME}
                  key: basic-auth-password"
  fi

  local JOB_YAML
  JOB_YAML=$(cat <<JOBEOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${SERVICE_NAME}-k6-smoke-test
  namespace: ${NAMESPACE}
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
      serviceAccountName: ${SA_NAME}
      restartPolicy: Never
      containers:
        - name: k6-runner
          image: ${K6_IMAGE}
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -e
              echo "=== Prometheus-Kafka-Adapter K6 Smoke Tests ==="
              echo "  Base URL: \${BASE_URL}"
              echo "  Metrics -> Cortex (\${K6_PROMETHEUS_RW_SERVER_URL})"
              echo "  Tags: version=\${CHART_VERSION}, service=prometheus-kafka-adapter, cluster=\${CLUSTER}"
              echo ""

              set +e
              k6 run /scripts/main.js \\
                --out experimental-prometheus-rw \\
                --tag version="\${CHART_VERSION}" \\
                --tag service=prometheus-kafka-adapter \\
                --tag cluster="\${CLUSTER}" \\
                --log-format json \\
                --verbose
              K6_EXIT=\$?
              set -e

              echo ""
              echo "K6 exit code: \${K6_EXIT}"
              echo "Metrics pushed to Cortex."
              exit \${K6_EXIT}
          env:
            - name: BASE_URL
              value: "${BASE_URL}"
            - name: CLUSTER
              value: "${CLUSTER}"${BASIC_AUTH_ENV}
            - name: CHART_VERSION
              valueFrom:
                configMapKeyRef:
                  name: ${STATE_CM}
                  key: last-chart-version
            - name: K6_PROMETHEUS_RW_SERVER_URL
              value: "${CORTEX_URL}"
            - name: K6_PROMETHEUS_RW_HEADERS_X-Scope-OrgID
              value: "${CLUSTER}"
            - name: K6_PROMETHEUS_RW_TREND_STATS
              value: "avg,p(95)"
          resources:
            requests:
              cpu: "200m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          volumeMounts:
            - name: k6-scripts
              mountPath: /scripts
              readOnly: true
      volumes:
        - name: k6-scripts
          configMap:
            name: ${SCRIPTS_CM}
            defaultMode: 0644
JOBEOF
)

  local TMPFILE
  TMPFILE="$(mktemp /tmp/pka-k6-runner-job.XXXXXX.yaml)"
  echo "${JOB_YAML}" > "${TMPFILE}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] kubectl create configmap ${JOB_TEMPLATE_CM} -n ${NAMESPACE} --from-file=k6-runner-job.yaml=${TMPFILE} --dry-run=client -o yaml | kubectl apply -f -"
    echo "[DRY-RUN] Rendered Job YAML:"
    cat "${TMPFILE}"
  else
    kubectl create configmap "${JOB_TEMPLATE_CM}" -n "${NAMESPACE}" \
      --from-file="k6-runner-job.yaml=${TMPFILE}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  rm -f "${TMPFILE}"
  ok "ConfigMap ${JOB_TEMPLATE_CM}"
}

deploy_cronjob() {
  step "Step 5: Deploy CronJob (HelmRelease Watcher)"

  cat <<EOF | kube_apply
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${CRONJOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: k6-smoke-tests
    app.kubernetes.io/part-of: prometheus-kafka-adapter
    app.kubernetes.io/component: hr-watcher
spec:
  schedule: "*/3 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 0
      ttlSecondsAfterFinished: 600
      template:
        metadata:
          labels:
            app.kubernetes.io/name: k6-smoke-tests
            app.kubernetes.io/part-of: prometheus-kafka-adapter
            app.kubernetes.io/component: hr-watcher
        spec:
          serviceAccountName: ${SA_NAME}
          restartPolicy: Never
          containers:
            - name: watcher
              image: ${KUBECTL_IMAGE}
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -eu

                  SERVICE_NAME="${SERVICE_NAME}"
                  HR_NAME="prometheus-kafka-adapter"
                  HR_NAMESPACE="vela-system"
                  STATE_CM="${STATE_CM}"
                  JOB_NAMESPACE="${NAMESPACE}"

                  echo "=== Prometheus-Kafka-Adapter HelmRelease Watcher ==="
                  echo "Checking \${HR_NAMESPACE}/\${HR_NAME}..."

                  CURRENT_VERSION=\$(kubectl get hr "\${HR_NAME}" -n "\${HR_NAMESPACE}" \
                    -o jsonpath='{.spec.chart.spec.version}' 2>/dev/null)

                  if [ -z "\${CURRENT_VERSION}" ]; then
                    echo "ERROR: Could not read HelmRelease chart version"
                    exit 1
                  fi
                  echo "Current chart version: \${CURRENT_VERSION}"

                  DEPLOY_STATUS=\$(kubectl get hr "\${HR_NAME}" -n "\${HR_NAMESPACE}" \
                    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

                  if [ "\${DEPLOY_STATUS}" != "True" ]; then
                    echo "HelmRelease is not Ready (status=\${DEPLOY_STATUS}). Skipping."
                    exit 0
                  fi

                  LAST_VERSION=\$(kubectl get configmap "\${STATE_CM}" -n "\${JOB_NAMESPACE}" \
                    -o jsonpath='{.data.last-chart-version}' 2>/dev/null || echo "")

                  if [ -z "\${LAST_VERSION}" ]; then
                    echo "ERROR: State ConfigMap \${STATE_CM} not found."
                    exit 1
                  fi

                  echo "Last known version: \${LAST_VERSION}"

                  if [ "\${CURRENT_VERSION}" = "\${LAST_VERSION}" ]; then
                    echo "Version unchanged. No action needed."
                    exit 0
                  fi

                  echo ""
                  echo "*** VERSION CHANGE DETECTED ***"
                  echo "  \${LAST_VERSION} -> \${CURRENT_VERSION}"
                  echo ""

                  TARGET_NS="ngp-cp"
                  DEPLOY_NAME="prometheus-kafka-adapter"
                  MAX_WAIT=300

                  echo "=== Validating deployment/\${DEPLOY_NAME} in '\${TARGET_NS}' ==="

                  echo "Waiting for deployment/\${DEPLOY_NAME} rollout..."
                  if ! kubectl rollout status deployment/"\${DEPLOY_NAME}" -n "\${TARGET_NS}" \
                    --timeout="\${MAX_WAIT}s" 2>/dev/null; then
                    echo "ERROR: Deployment \${DEPLOY_NAME} rollout not complete after \${MAX_WAIT}s. Skipping."
                    exit 0
                  fi
                  echo "  ✓ deployment/\${DEPLOY_NAME} rollout complete"

                  echo ""
                  echo "=== Pod status ==="
                  kubectl get pods -n "\${TARGET_NS}" -l app=prometheus-kafka-adapter \
                    -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status' \
                    --no-headers 2>/dev/null || true
                  echo ""

                  kubectl patch configmap "\${STATE_CM}" -n "\${JOB_NAMESPACE}" \
                    --type merge -p "{\"data\":{\"last-chart-version\":\"\${CURRENT_VERSION}\"}}"
                  echo "State updated to \${CURRENT_VERSION}"

                  ACTIVE_PODS=\$(kubectl get job ${SERVICE_NAME}-k6-smoke-test -n "\${JOB_NAMESPACE}" \
                    -o jsonpath='{.status.active}' 2>/dev/null || echo "0")

                  if [ "\${ACTIVE_PODS}" != "" ] && [ "\${ACTIVE_PODS}" != "0" ]; then
                    echo "K6 Job still running. Waiting..."
                    kubectl wait --for=condition=complete job/${SERVICE_NAME}-k6-smoke-test \
                      -n "\${JOB_NAMESPACE}" --timeout=600s 2>/dev/null || true
                  fi

                  kubectl delete job ${SERVICE_NAME}-k6-smoke-test -n "\${JOB_NAMESPACE}" \
                    --ignore-not-found=true 2>/dev/null
                  echo "Cleaned up previous Job"

                  echo "Creating K6 smoke test Job..."
                  kubectl get configmap "\${SERVICE_NAME}-k6-job-template" -n "\${JOB_NAMESPACE}" \
                    -o jsonpath='{.data.k6-runner-job\.yaml}' | kubectl apply -f -

                  echo "K6 smoke test Job created for version \${CURRENT_VERSION}"
              resources:
                requests:
                  cpu: "50m"
                  memory: "32Mi"
                limits:
                  cpu: "100m"
                  memory: "64Mi"
EOF
  ok "CronJob ${CRONJOB_NAME}"
}

# ─── Verify ──────────────────────────────────────────────────────────────────
verify_deployment() {
  step "Verification"

  local FAILED=0

  for RESOURCE in \
    "sa/${SA_NAME}:${NAMESPACE}" \
    "clusterrole/${CR_HR}:" \
    "clusterrolebinding/${CRB_HR}:" \
    "role/${ROLE_NAME}:${NAMESPACE}" \
    "rolebinding/${RB_NAME}:${NAMESPACE}" \
    "configmap/${SCRIPTS_CM}:${NAMESPACE}" \
    "configmap/${JOB_TEMPLATE_CM}:${NAMESPACE}" \
    "configmap/${STATE_CM}:${NAMESPACE}" \
    "configmap/${RESULTS_CM}:${NAMESPACE}" \
    "cronjob/${CRONJOB_NAME}:${NAMESPACE}" \
  ; do
    local KIND_NAME="${RESOURCE%%:*}"
    local RES_NS="${RESOURCE##*:}"
    local NS_FLAG=""
    if [[ -n "$RES_NS" ]]; then
      NS_FLAG="-n ${RES_NS}"
    fi

    if kubectl get ${KIND_NAME} ${NS_FLAG} &>/dev/null 2>&1; then
      ok "${KIND_NAME}"
    else
      echo "  ✗ MISSING: ${KIND_NAME} ${NS_FLAG}"
      FAILED=$((FAILED + 1))
    fi
  done

  if [[ "$BASIC_AUTH_ENABLED" == "true" ]]; then
    if kubectl get "secret/${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null 2>&1; then
      ok "secret/${SECRET_NAME}"
    else
      echo "  ✗ MISSING: secret/${SECRET_NAME} -n ${NAMESPACE}"
      FAILED=$((FAILED + 1))
    fi
  fi

  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "  All resources verified successfully."
  else
    echo "  WARNING: ${FAILED} resource(s) missing. Check output above."
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║  prometheus-kafka-adapter — K6 Smoke Tests Deployment       ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Namespace:   ${NAMESPACE}"
  echo "  Cluster:     ${CLUSTER}"
  echo "  Base URL:    ${BASE_URL:-<from values.yaml>}"
  echo "  Basic Auth:  ${BASIC_AUTH_ENABLED}"
  echo "  Deploy mode: $(if [[ "$USE_HELM" == "true" ]]; then echo "Helm"; else echo "kubectl"; fi)"
  echo "  Dry run:     ${DRY_RUN}"
  echo ""

  validate_cluster
  validate_prereqs

  if [[ "$USE_HELM" == "true" ]]; then
    deploy_helm
  else
    deploy_namespace
    deploy_secret
    deploy_rbac
    deploy_configmaps
    deploy_job_template
    deploy_cronjob
  fi

  if [[ "$DRY_RUN" != "true" ]]; then
    verify_deployment
  fi

  step "Done"
  echo ""
  echo "  To trigger a manual test run:"
  echo "    kubectl delete job ${SERVICE_NAME}-k6-smoke-test -n ${NAMESPACE} --ignore-not-found"
  echo "    kubectl get configmap ${JOB_TEMPLATE_CM} -n ${NAMESPACE} -ojsonpath='{.data.k6-runner-job\\.yaml}' | kubectl apply -f -"
  echo "    kubectl logs -f job/${SERVICE_NAME}-k6-smoke-test -n ${NAMESPACE} -c k6-runner"
  echo ""
}

main
