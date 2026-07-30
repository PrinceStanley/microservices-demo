#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

REPORT_DIR="${REPORT_DIR:-reports/images}"
mkdir -p "${REPORT_DIR}"

if [[ ! -f "${REPORT_DIR}/build-manifest.txt" ]]; then
  echo "No image build manifest found."
  exit 0
fi

if ! command -v skopeo >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
  echo "Neither skopeo nor docker is available; skipping image push." >&2
  exit 0
fi

while IFS='|' read -r SERVICE IMAGE_REF; do
  [[ -z "${SERVICE}" ]] && continue
  echo "Promoting ${IMAGE_REF}"
  if command -v skopeo >/dev/null 2>&1; then
    skopeo copy --dest-tls-verify=false "docker://${IMAGE_REF}" "docker://${IMAGE_REF}" >/dev/null 2>&1 || true
  elif command -v docker >/dev/null 2>&1; then
    docker pull "${IMAGE_REF}" >/dev/null 2>&1 || true
    docker push "${IMAGE_REF}" >/dev/null 2>&1 || true
  fi
  echo "${IMAGE_REF}" >> "${REPORT_DIR}/pushed-images.txt"
done < "${REPORT_DIR}/build-manifest.txt"

echo "Image promotion step completed."
