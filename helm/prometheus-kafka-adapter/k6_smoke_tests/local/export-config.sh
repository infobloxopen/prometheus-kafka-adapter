#!/usr/bin/env bash
# export-config.sh — Export environment variables for local K6 run
set -euo pipefail

export BASE_URL="${BASE_URL:-http://localhost:8080}"
export CLUSTER="${CLUSTER:-us-dev-5}"
export CHART_VERSION="${CHART_VERSION:-local}"
export K6_PROMETHEUS_RW_SERVER_URL="${K6_PROMETHEUS_RW_SERVER_URL:-}"
export K6_PROMETHEUS_RW_HEADERS_X-Scope-OrgID="${CLUSTER}"

echo "Exported config:"
echo "  BASE_URL=${BASE_URL}"
echo "  CLUSTER=${CLUSTER}"
echo "  CHART_VERSION=${CHART_VERSION}"
echo "  K6_PROMETHEUS_RW_SERVER_URL=${K6_PROMETHEUS_RW_SERVER_URL:-<not set, no remote write>}"
