#!/usr/bin/env bash

set -Eeuo pipefail

mkdir -p reports/trivy/dependencies

echo "=========================================================="
echo "Dependency Vulnerability Scan"
echo "=========================================================="

trivy fs \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    --format json \
    --output reports/trivy/dependencies/trivy-dependency-report.json \
    .

EXIT_CODE=$?

trivy fs \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    .

echo

echo "Dependency scan completed."

exit ${EXIT_CODE}
