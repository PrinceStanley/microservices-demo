#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p reports/trivy/secrets
echo "=========================================================="
echo "Secret Scan"
echo "=========================================================="
trivy fs \
    --scanners secret \
    --severity HIGH,CRITICAL \
    --format json \
    --output reports/trivy/secrets/trivy-secret-report.json \
    .
EXIT_CODE=$?
trivy fs \
    --scanners secret \
    --severity HIGH,CRITICAL \
    .
echo
echo "Secret scan completed."
exit ${EXIT_CODE}
