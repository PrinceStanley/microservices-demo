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

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "Python is required to update Helm values." >&2
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/yaml_support.py"
if [[ ! -f "${PYTHON_SCRIPT}" ]]; then
  echo "Required helper ${PYTHON_SCRIPT} not found." >&2
  exit 1
fi

if [[ -f "${CHANGED_FILE}" ]] && [[ -s "${CHANGED_FILE}" ]]; then
  mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' "${CHANGED_FILE}" || true)
else
  DEPLOYMENT_MODE="$(cat .deployment-mode 2>/dev/null || echo 'false')"
  if [[ "${DEPLOYMENT_MODE}" == "true" ]]; then
    echo "Initial deployment mode; updating Helm values for all enabled services."
    out_file="$(mktemp)"
    "${PYTHON_BIN}" "${PYTHON_SCRIPT}" --list-enabled-services "${SERVICES_FILE}" "$out_file"
    mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' "$out_file" || true)
    rm -f "$out_file"
  else
    echo "Changed services file not found; skipping Helm update." >&2
    exit 0
  fi
fi

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "No services to update; skipping Helm update."
  exit 0
fi

"${PYTHON_BIN}" "${PYTHON_SCRIPT}" --update-helm-values "${SERVICES_FILE}" "${VALUES_FILE}" "${IMAGE_TAG}" "${REPORT_DIR}" "${CHANGED_FILE}"

echo "Helm values update completed."
