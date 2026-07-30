#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CHANGED_FILE="${CHANGED_FILE:-changed-services.txt}"
SERVICES_FILE="${SERVICES_FILE:-ci/services.yaml}"
IMAGE_TAG="${IMAGE_TAG:-${GIT_COMMIT_SHORT:-latest}}"
VALUES_FILE="${VALUES_FILE:-helm-chart/values.yaml}"
REPORT_DIR="${REPORT_DIR:-reports/images}"
mkdir -p "${REPORT_DIR}"

if [[ ! -f "${CHANGED_FILE}" ]]; then
  echo "Changed services file not found; skipping Helm update." >&2
  exit 0
fi

mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' "${CHANGED_FILE}" || true)
if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "No changed services detected; skipping Helm update."
  exit 0
fi

for SERVICE in "${SERVICES[@]}"; do
  VALUES_KEY="$(yq e ".services.${SERVICE}.helm.valuesKey" "${SERVICES_FILE}")"
  if [[ -z "${VALUES_KEY}" || "${VALUES_KEY}" == "null" ]]; then
    continue
  fi
  yq e -i "${VALUES_KEY} = \"${IMAGE_TAG}\"" "${VALUES_FILE}"
  echo "Updated ${SERVICE} image tag to ${IMAGE_TAG} in ${VALUES_FILE}"
done

if command -v git >/dev/null 2>&1; then
  git add "${VALUES_FILE}"
  if git diff --cached --quiet; then
    echo "No Helm changes to commit."
  else
    git commit -m "chore: update image tags for ${IMAGE_TAG}" || true
    echo "Helm values updated and committed."
  fi
fi

echo "Helm values update completed."
