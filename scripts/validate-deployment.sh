#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

NAMESPACE="${NAMESPACE:-online-boutique}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"

if [[ ! -f changed-services.txt ]]; then
  echo "No changed services file found; skipping deployment validation." >&2
  exit 0
fi

mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' changed-services.txt || true)
if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "No changed services detected; skipping deployment validation."
  exit 0
fi

for SERVICE in "${SERVICES[@]}"; do
  echo "Validating deployment for ${SERVICE}"
  kubectl -n "${NAMESPACE}" rollout status "deploy/${SERVICE}" --timeout="${TIMEOUT_SECONDS}s" || exit 1
  kubectl -n "${NAMESPACE}" get svc "${SERVICE}" >/dev/null || exit 1
  kubectl -n "${NAMESPACE}" get virtualservice "${SERVICE}" >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" get destinationrule "${SERVICE}" >/dev/null 2>&1 || true
  echo "Deployment validated for ${SERVICE}."
done

echo "Deployment validation completed."
