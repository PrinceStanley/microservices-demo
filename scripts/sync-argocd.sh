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

NAMESPACE="${NAMESPACE:-online-boutique}"

if ! argocd app get "${ARGOCD_APP_NAME}" >/dev/null 2>&1; then
    echo "ArgoCD application ${ARGOCD_APP_NAME} does not exist, creating..."
    if ! argocd app create "${ARGOCD_APP_NAME}" \
      --repo https://github.com/PrinceStanley/microservices-demo \
      --path helm-chart \
      --dest-server https://kubernetes.default.svc \
      --dest-namespace "${NAMESPACE}" \
      --sync-policy automated \
      --upsert 2>/dev/null; then
      echo "WARNING: Failed to create ArgoCD application. This may be because no git repository is configured in ArgoCD."
      echo "Please add a repository in ArgoCD UI (Settings > Repositories) or configure the correct repo URL in sync-argocd.sh."
    fi
fi

argocd app sync "${ARGOCD_APP_NAME}" --prune --retry-limit 3 --timeout 600
argocd app wait "${ARGOCD_APP_NAME}" --health --sync --timeout 600

echo "ArgoCD sync completed."
