#!/usr/bin/env bash

set -Eeuo pipefail

################################################################################
# Enterprise Service Change Detection
################################################################################

SERVICES_FILE="${SERVICES_FILE:-ci/services.yaml}"
OUTPUT_FILE="${OUTPUT_FILE:-changed-services.txt}"
INITIAL_DEPLOYMENT="${INITIAL_DEPLOYMENT:-false}"

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_BIN="python"
    else
        echo "Python is required to parse ${SERVICES_FILE}." >&2
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/yaml_support.py"
if [[ ! -f "${PYTHON_SCRIPT}" ]]; then
    echo "Required helper ${PYTHON_SCRIPT} not found." >&2
    exit 1
fi

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

if [[ "${INITIAL_DEPLOYMENT}" == "true" ]]; then
    echo "Initial deployment requested; selecting enabled services."
    "${PYTHON_BIN}" "${PYTHON_SCRIPT}" --list-enabled-services "${SERVICES_FILE}" "${OUTPUT_FILE}"
    echo
    echo "=========================================================="
    echo "Changed Services"
    echo "=========================================================="
    cat "${OUTPUT_FILE}"
    echo
    echo "Output File"
    echo "${OUTPUT_FILE}"
    echo
    echo "Done."
    exit 0
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
"${PYTHON_BIN}" "${PYTHON_SCRIPT}" --match-services "${SERVICES_FILE}" "${OUTPUT_FILE}" "$CHANGED_FILES"

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
