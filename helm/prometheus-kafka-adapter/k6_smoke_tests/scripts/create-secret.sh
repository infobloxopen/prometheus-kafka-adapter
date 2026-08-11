#!/usr/bin/env bash
# create-secret.sh — Create the K6 smoke test credentials Secret
set -euo pipefail

NAMESPACE="${1:-smoke-test-service}"
SECRET_NAME="pka-smoke-test-config"

: "${BASIC_AUTH_USERNAME:?ERROR: Set BASIC_AUTH_USERNAME}"
: "${BASIC_AUTH_PASSWORD:?ERROR: Set BASIC_AUTH_PASSWORD}"

echo "Creating secret/${SECRET_NAME} in ${NAMESPACE}..."

kubectl create secret generic "${SECRET_NAME}" \
  -n "${NAMESPACE}" \
  --from-literal=basic-auth-username="${BASIC_AUTH_USERNAME}" \
  --from-literal=basic-auth-password="${BASIC_AUTH_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret ${SECRET_NAME} created/updated"
