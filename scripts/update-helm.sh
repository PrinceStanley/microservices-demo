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

if [[ ! -f "${CHANGED_FILE}" ]]; then
  echo "Changed services file not found; skipping Helm update." >&2
  exit 0
fi

mapfile -t SERVICES < <(awk 'NF && $0 !~ /^#/ { print $0 }' "${CHANGED_FILE}" || true)
if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "No changed services detected; skipping Helm update."
  exit 0
fi

"${PYTHON_BIN}" - "${SERVICES_FILE}" "${VALUES_FILE}" "${IMAGE_TAG}" "${REPORT_DIR}" "${CHANGED_FILE}" <<'PY'
import os
import sys
from pathlib import Path
import yaml

services_file = Path(sys.argv[1])
values_file = Path(sys.argv[2])
image_tag = sys.argv[3]
report_dir = Path(sys.argv[4])
changed_file = Path(sys.argv[5])

with services_file.open(encoding='utf-8') as handle:
    services_data = yaml.safe_load(handle) or {}
with values_file.open(encoding='utf-8') as handle:
    values_data = yaml.safe_load(handle) or {}

changed_services = []
if changed_file.exists():
    changed_services = [line.strip() for line in changed_file.read_text(encoding='utf-8').splitlines() if line.strip()]

for service in changed_services:
    config = (services_data.get('services', {}) or {}).get(service, {})
    values_key = config.get('helm', {}).get('valuesKey')
    if not values_key:
        continue
    value_path = values_key.split('.')
    current = values_data
    for part in value_path[:-1]:
        current = current.setdefault(part, {})
    current[value_path[-1]] = image_tag

with values_file.open('w', encoding='utf-8') as handle:
    yaml.safe_dump(values_data, handle, sort_keys=False)

report_dir.mkdir(parents=True, exist_ok=True)
Path(report_dir / 'helm-values-overrides.yaml').write_text(
    '\n'.join(f'{service}: {image_tag}' for service in changed_services if service) + '\n',
    encoding='utf-8',
)
PY

echo "Helm values update completed."
