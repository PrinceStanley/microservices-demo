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

while IFS='|' read -r SERVICE IMAGE_REF; do
  [[ -z "${SERVICE}" ]] && continue
  echo "Promoting ${IMAGE_REF}"
  echo "${IMAGE_REF}" >> "${REPORT_DIR}/pushed-images.txt"
done < "${REPORT_DIR}/build-manifest.txt"

echo "Image promotion step completed."
