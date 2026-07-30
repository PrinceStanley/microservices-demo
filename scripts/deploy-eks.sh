#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SERVICES_FILE="${SERVICES_FILE:-ci/services.yaml}"
CHANGED_FILE="${CHANGED_FILE:-changed-services.txt}"
NAMESPACE="${NAMESPACE:-}"
HELM_RELEASE="${HELM_RELEASE:-online-boutique}"
HELM_VALUES_FILE="${HELM_VALUES_FILE:-helm-chart/values.yaml}"
HELM_CHART_DIR="${HELM_CHART_DIR:-helm-chart}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "Python is required to deploy the Helm chart." >&2
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/yaml_support.py"
if [[ ! -f "${PYTHON_SCRIPT}" ]]; then
  echo "Required helper ${PYTHON_SCRIPT} not found." >&2
  exit 1
fi

get_yaml_value() {
  local file="$1"
  local service="$2"
  local field="$3"
  if [[ "${service}" == "__platform__" ]]; then
    "${PYTHON_BIN}" "${PYTHON_SCRIPT}" --platform-value "$file" "$field"
  else
    "${PYTHON_BIN}" "${PYTHON_SCRIPT}" --service-value "$file" "$service" "$field"
  fi
}

list_enabled_services() {
  "${PYTHON_BIN}" "${PYTHON_SCRIPT}" --list-enabled-services "$SERVICES_FILE"
}

if [[ -z "${NAMESPACE}" ]]; then
  NAMESPACE="$(get_yaml_value "${SERVICES_FILE}" "__platform__" "namespace")"
fi

if [[ -z "${NAMESPACE}" ]]; then
  echo "Unable to resolve the target namespace from ${SERVICES_FILE}." >&2
  exit 1
fi

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Creating namespace ${NAMESPACE} for the initial deployment."
  kubectl create namespace "${NAMESPACE}"
fi

if [[ -f "${CHANGED_FILE}" ]] && [[ -s "${CHANGED_FILE}" ]]; then
  mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' "${CHANGED_FILE}" || true)
else
  echo "No changed-services file found; deploying all enabled services."
  mapfile -t SERVICES < <(list_enabled_services)
fi

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "No deployable services were resolved; skipping Helm deployment." >&2
  exit 0
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required to deploy the application." >&2
  exit 1
fi

IMAGE_TAG="${IMAGE_TAG:-${GIT_COMMIT_SHORT:-latest}}"
helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set "images.tag=${IMAGE_TAG}" \
  --wait \
  --timeout "${TIMEOUT_SECONDS}s" \
  -f "${HELM_VALUES_FILE}"

echo "Helm deployment completed for ${HELM_RELEASE}."
