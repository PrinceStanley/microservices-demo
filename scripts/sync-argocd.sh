#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ARGOCD_SERVER="${ARGOCD_SERVER:-argocd-server.argocd.svc.cluster.local}"
ARGOCD_PORT="${ARGOCD_PORT:-80}"
ARGOCD_APP_NAME="${ARGOCD_APP_NAME:-online-boutique}"
ARGOCD_USERNAME="${ARGOCD_USERNAME:-admin}"
ARGOCD_PASSWORD="${ARGOCD_PASSWORD:-}"

if [[ -z "${ARGOCD_PASSWORD}" ]]; then
  echo "ARGOCD_PASSWORD is not available. Store the ArgoCD admin password in Jenkins as a Secret Text credential with ID 'argocd-admin-password'." >&2
  exit 1
fi

if ! command -v argocd >/dev/null 2>&1; then
  echo "argocd CLI is not installed in the Jenkins agent image." >&2
  exit 1
fi

argocd login "${ARGOCD_SERVER}:${ARGOCD_PORT}" \
  --username "${ARGOCD_USERNAME}" \
  --password "${ARGOCD_PASSWORD}" \
  --plaintext \
  --grpc-web

argocd app sync "${ARGOCD_APP_NAME}" --prune --retry-limit 3 --timeout 600
argocd app wait "${ARGOCD_APP_NAME}" --health --sync --timeout 600

echo "ArgoCD sync completed."
