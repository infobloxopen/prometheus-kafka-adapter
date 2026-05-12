#!/usr/bin/env bash
# run-smoke-tests.sh — Run K6 smoke tests locally
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6_DIR="${SCRIPT_DIR}/../k6"

: "${BASE_URL:?ERROR: Set BASE_URL (e.g. http://localhost:8080)}"
export CLUSTER="${CLUSTER:-us-dev-5}"
export CHART_VERSION="${CHART_VERSION:-local}"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  prometheus-kafka-adapter — Local K6 Smoke Tests             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "  BASE_URL: ${BASE_URL}"
echo "  CLUSTER:  ${CLUSTER}"
echo "  VERSION:  ${CHART_VERSION}"
echo ""

K6_ARGS=("${K6_DIR}/smoke-tests-modular.js")
K6_ARGS+=("--tag" "version=${CHART_VERSION}")
K6_ARGS+=("--tag" "service=prometheus-kafka-adapter")
K6_ARGS+=("--tag" "cluster=${CLUSTER}")
K6_ARGS+=("--log-format" "json")
K6_ARGS+=("--verbose")

if [[ -n "${K6_PROMETHEUS_RW_SERVER_URL:-}" ]]; then
  K6_ARGS+=("--out" "experimental-prometheus-rw")
  echo "  Cortex:   ${K6_PROMETHEUS_RW_SERVER_URL}"
fi
echo ""

k6 run "${K6_ARGS[@]}" "$@"
EXIT_CODE=$?

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "✅ All smoke tests PASSED"
else
  echo "❌ Smoke tests FAILED (exit code: ${EXIT_CODE})"
fi
exit $EXIT_CODE
