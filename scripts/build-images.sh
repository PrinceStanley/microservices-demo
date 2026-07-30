#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CHANGED_FILE="${CHANGED_FILE:-changed-services.txt}"
SERVICES_FILE="${SERVICES_FILE:-ci/services.yaml}"
BUILD_NUMBER="${BUILD_NUMBER:-0}"
GIT_COMMIT_SHORT="${GIT_COMMIT_SHORT:-$(git rev-parse --short HEAD)}"
IMAGE_TAG="${IMAGE_TAG:-${GIT_COMMIT_SHORT}}"
PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "Python is required to read ${SERVICES_FILE}." >&2
    exit 1
  fi
fi

get_yaml_value() {
  local file="$1"
  local service="$2"
  local field="$3"
  "${PYTHON_BIN}" - "$file" "$service" "$field" <<'PY'
import sys
import yaml

file_path, service, field = sys.argv[1:4]
with open(file_path, encoding='utf-8') as handle:
    data = yaml.safe_load(handle) or {}

if service == "__platform__":
    value = (data.get("platform", {}) or {}).get(field)
else:
    value = (data.get("services", {}) or {}).get(service, {}).get(field)

print(value if value is not None else "")
PY
}

REGISTRY="${REGISTRY:-$(get_yaml_value "${SERVICES_FILE}" "__platform__" "registry")}" 
REPOSITORY="${REPOSITORY:-$(get_yaml_value "${SERVICES_FILE}" "__platform__" "repository")}" 
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-$(get_yaml_value "${SERVICES_FILE}" "__platform__" "namespace")}" 
KANIKO_CONTAINER="${KANIKO_CONTAINER:-kaniko}"
REPORT_DIR="${REPORT_DIR:-reports/images}"
mkdir -p "${REPORT_DIR}"

if [[ ! -f "${CHANGED_FILE}" ]]; then
  echo "Changed services file not found; skipping image build." >&2
  exit 0
fi

mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' "${CHANGED_FILE}" || true)
if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "No changed services detected; skipping image build."
  exit 0
fi

POD_NAME="${POD_NAME:-$(hostname)}"

if command -v kubectl >/dev/null 2>&1 && kubectl get pod "${POD_NAME}" >/dev/null 2>&1; then
  EXECUTOR_PREFIX=(kubectl exec "${POD_NAME}" -c "${KANIKO_CONTAINER}" -- /busybox/sh -c)
else
  EXECUTOR_PREFIX=(/kaniko/executor)
fi

for SERVICE in "${SERVICES[@]}"; do
  SOURCE_DIR="$(get_yaml_value "${SERVICES_FILE}" "${SERVICE}" "source")"
  DOCKERFILE="$(get_yaml_value "${SERVICES_FILE}" "${SERVICE}" "dockerfile")"
  IMAGE_NAME="$(get_yaml_value "${SERVICES_FILE}" "${SERVICE}" "image")"
  if [[ -z "${SOURCE_DIR}" || "${SOURCE_DIR}" == "null" ]]; then
    echo "Skipping ${SERVICE}: no source path found." >&2
    continue
  fi

  IMAGE_REPOSITORY="${REGISTRY}/${REPOSITORY}/${IMAGE_NAMESPACE}/${IMAGE_NAME}"
  DESTINATIONS=(
    "${IMAGE_REPOSITORY}:${IMAGE_TAG}"
    "${IMAGE_REPOSITORY}:${BUILD_NUMBER}"
    "${IMAGE_REPOSITORY}:latest"
  )

  echo "=========================================================="
  echo "Building service: ${SERVICE}"
  echo "Source         : ${SOURCE_DIR}"
  echo "Dockerfile     : ${DOCKERFILE}"
  echo "Destination    : ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
  echo "=========================================================="

  KANIKO_ARGS=(
    --context="${ROOT_DIR}/${SOURCE_DIR}"
    --dockerfile="${ROOT_DIR}/${DOCKERFILE}"
    --reproducible
    --single-snapshot
    --cache=true
    --cache-repo="${IMAGE_REPOSITORY}:cache"
    --skip-tls-verify
    --destination="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
    --destination="${IMAGE_REPOSITORY}:${BUILD_NUMBER}"
    --destination="${IMAGE_REPOSITORY}:latest"
  )

  if [[ -n "${DOCKER_CONFIG:-}" ]]; then
    KANIKO_ARGS+=(--dockerconfig="${DOCKER_CONFIG}")
  fi

  if [[ "${EXECUTOR_PREFIX[0]}" == "kubectl" ]]; then
    "${EXECUTOR_PREFIX[@]}" "cd /workspace && /kaniko/executor ${KANIKO_ARGS[*]}" >/tmp/kaniko-build.log 2>&1
  else
    /kaniko/executor "${KANIKO_ARGS[@]}" >/tmp/kaniko-build.log 2>&1
  fi

  cat /tmp/kaniko-build.log
  echo "Build complete for ${SERVICE}."
  echo "${SERVICE}|${IMAGE_REPOSITORY}:${IMAGE_TAG}" >> "${REPORT_DIR}/build-manifest.txt"
done

echo "Image build pipeline completed."
