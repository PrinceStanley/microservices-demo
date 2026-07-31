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

REGISTRY="${REGISTRY:-$(get_yaml_value "${SERVICES_FILE}" "__platform__" "registry")}" 
REPOSITORY="${REPOSITORY:-$(get_yaml_value "${SERVICES_FILE}" "__platform__" "repository")}" 
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-$(get_yaml_value "${SERVICES_FILE}" "__platform__" "namespace")}" 
KANIKO_CONTAINER="${KANIKO_CONTAINER:-kaniko}"
REPORT_DIR="${REPORT_DIR:-reports/images}"
mkdir -p "${REPORT_DIR}"

if [[ -f "${CHANGED_FILE}" ]] && [[ -s "${CHANGED_FILE}" ]]; then
  mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' "${CHANGED_FILE}" || true)
else
  DEPLOYMENT_MODE="$(cat .deployment-mode 2>/dev/null || echo 'false')"
  if [[ "${DEPLOYMENT_MODE}" == "true" ]]; then
    echo "Initial deployment mode; building all enabled services."
    out_file="$(mktemp)"
    "${PYTHON_BIN}" "${PYTHON_SCRIPT}" --list-enabled-services "${SERVICES_FILE}" "$out_file"
    mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' "$out_file" || true)
    rm -f "$out_file"
  else
    echo "Changed services file not found; skipping image build." >&2
    exit 0
  fi
fi

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "No services to build; skipping image build."
  exit 0
fi

POD_NAME="${POD_NAME:-$(hostname)}"

if [[ -x "/kaniko/executor" ]]; then
  EXECUTOR_PREFIX=(/kaniko/executor)
elif command -v kubectl >/dev/null 2>&1 && kubectl get pod "${POD_NAME}" >/dev/null 2>&1; then
  EXECUTOR_PREFIX=(kubectl exec "${POD_NAME}" -c "${KANIKO_CONTAINER}" -- /kaniko/executor)
else
  echo "ERROR: Neither local /kaniko/executor nor kubectl exec is available." >&2
  exit 1
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
  elif [[ -d "/kaniko/.docker" ]]; then
    KANIKO_ARGS+=(--dockerconfig="/kaniko/.docker")
  fi

  if [[ "${EXECUTOR_PREFIX[0]}" == "kubectl" ]]; then
    echo "Executing Kaniko via kubectl in pod ${POD_NAME}, container ${KANIKO_CONTAINER}" >&2
    set +e
    if [[ -n "${JFROG_REGISTRY_HOST:-}" ]] && [[ -n "${JFROG_REGISTRY_IP:-}" ]]; then
      kubectl exec "${POD_NAME}" -c "${KANIKO_CONTAINER}" -- /bin/sh -c \
        "echo '${JFROG_REGISTRY_IP} ${JFROG_REGISTRY_HOST}' >> /etc/hosts" >/dev/null 2>&1 || true
    fi
    "${EXECUTOR_PREFIX[@]}" "${KANIKO_ARGS[@]}" >/tmp/kaniko-build.log 2>&1
    BUILD_EXIT_CODE=$?
    set -e
  else
    echo "Executing Kaniko directly in current container" >&2
    set +e
    "${EXECUTOR_PREFIX[@]}" "${KANIKO_ARGS[@]}" >/tmp/kaniko-build.log 2>&1
    BUILD_EXIT_CODE=$?
    set -e
  fi

  cat /tmp/kaniko-build.log
  if [[ ${BUILD_EXIT_CODE:-0} -ne 0 ]]; then
    echo "Kaniko build failed for ${SERVICE} with exit code ${BUILD_EXIT_CODE}" >&2
    exit ${BUILD_EXIT_CODE}
  fi
  echo "Build complete for ${SERVICE}."
  echo "${SERVICE}|${IMAGE_REPOSITORY}:${IMAGE_TAG}" >> "${REPORT_DIR}/build-manifest.txt"
done

echo "Image build pipeline completed."
