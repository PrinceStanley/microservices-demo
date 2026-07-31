#!/usr/bin/env bash
set -Eeuo pipefail

SERVICES_FILE="${1:-ci/services.yaml}"
NAMESPACE="${2:-online-boutique}"

python3 scripts/yaml_support.py --list-enabled-services "${SERVICES_FILE}" /tmp/enabled-services.txt

missing=0
while IFS= read -r svc; do
    deployment=$(python3 scripts/yaml_support.py --service-value "${SERVICES_FILE}" "${svc}" "deployment")
    ready=$(kubectl get deployment "${deployment}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ -z "${ready}" || "${ready}" == "0" ]]; then
        echo "MISSING: ${svc} (deployment: ${deployment})"
        missing=$((missing + 1))
    fi
done < /tmp/enabled-services.txt

echo "${missing}"
