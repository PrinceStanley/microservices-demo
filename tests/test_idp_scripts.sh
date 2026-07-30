#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in build-images.sh push-images.sh update-helm.sh; do
  SCRIPT_PATH="${REPO_DIR}/scripts/${script}"
  if [[ ! -s "${SCRIPT_PATH}" ]]; then
    echo "Missing implementation in ${SCRIPT_PATH}" >&2
    exit 1
  fi
  if ! grep -q "kaniko\|helm\|argocd" "${SCRIPT_PATH}"; then
    echo "${SCRIPT_PATH} is missing release automation content" >&2
    exit 1
  fi
done

echo "IDP automation scripts are present and populated."
