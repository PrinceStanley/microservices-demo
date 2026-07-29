#!/usr/bin/env bash

set -euo pipefail

################################################################################
# Enterprise Service Change Detection
################################################################################

SERVICES_FILE="ci/services.yaml"
OUTPUT_FILE="changed-services.txt"

echo "=========================================================="
echo " Online Boutique - Service Change Detection"
echo "=========================================================="

rm -f "${OUTPUT_FILE}"
touch "${OUTPUT_FILE}"

################################################################################
# Verify repository
################################################################################

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: Current directory is not a Git repository."
    exit 1
fi

################################################################################
# Verify services metadata
################################################################################

if [[ ! -f "${SERVICES_FILE}" ]]; then
    echo "ERROR: ${SERVICES_FILE} not found."
    exit 1
fi

################################################################################
# Determine comparison commit
################################################################################

if git rev-parse HEAD~1 >/dev/null 2>&1; then
    BASE_COMMIT=$(git rev-parse HEAD~1)
else
    BASE_COMMIT=$(git rev-list --max-parents=0 HEAD)
fi
CURRENT_COMMIT=$(git rev-parse HEAD)
echo
echo "Base Commit    : ${BASE_COMMIT}"
echo "Current Commit : ${CURRENT_COMMIT}"
echo

################################################################################
# Changed files
################################################################################
echo "Scanning changed files..."
CHANGED_FILES=$(git diff --name-only "${BASE_COMMIT}" "${CURRENT_COMMIT}")
if [[ -z "${CHANGED_FILES}" ]]; then
    echo
    echo "No changed files detected."
    exit 0
fi
echo
echo "${CHANGED_FILES}"
echo

################################################################################
# Extract source directories from services.yaml
################################################################################
echo "Matching services..."
SERVICE_NAMES=$(yq e '.services | keys | .[]' "${SERVICES_FILE}")
for SERVICE in ${SERVICE_NAMES}; do
    ENABLED=$(yq e ".services.${SERVICE}.enabled" "${SERVICES_FILE}")
    if [[ "${ENABLED}" != "true" ]]; then
        continue
    fi
    SOURCE=$(yq e ".services.${SERVICE}.source" "${SERVICES_FILE}")
    if echo "${CHANGED_FILES}" | grep -q "^${SOURCE}/"; then
        echo "${SERVICE}" >> "${OUTPUT_FILE}"
    fi
done
################################################################################
# Remove duplicates
################################################################################

sort -u "${OUTPUT_FILE}" -o "${OUTPUT_FILE}"

################################################################################
# Display result
################################################################################
echo
echo "=========================================================="
echo "Changed Services"
echo "=========================================================="
if [[ ! -s "${OUTPUT_FILE}" ]]; then
    echo "No deployable services changed."
else
    cat "${OUTPUT_FILE}"
fi
echo
echo "Output File"
echo "${OUTPUT_FILE}"
echo
echo "Done."
