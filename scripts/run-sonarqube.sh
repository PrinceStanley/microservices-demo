#!/usr/bin/env bash
set -Eeuo pipefail
################################################################################
# SonarQube Scan
################################################################################
SONAR_HOST="${SONAR_HOST:-http://sonarqube-sonarqube.sonarqube.svc.cluster.local:9000}"
SONAR_TOKEN="${SONAR_TOKEN:?SONAR_TOKEN not defined}"
PROJECT_KEY="${PROJECT_KEY:-online-boutique}"
PROJECT_NAME="${PROJECT_NAME:-Online Boutique}"
echo "=========================================================="
echo "SonarQube Analysis"
echo "=========================================================="
echo "Host        : ${SONAR_HOST}"
echo "Project Key : ${PROJECT_KEY}"
mkdir -p reports/sonar
sonar-scanner \
    -Dsonar.host.url="${SONAR_HOST}" \
    -Dsonar.login="${SONAR_TOKEN}" \
    -Dsonar.projectKey="${PROJECT_KEY}" \
    -Dsonar.projectName="${PROJECT_NAME}" \
    -Dsonar.projectVersion="$(git rev-parse --short HEAD)" \
    -Dsonar.sources=src \
    -Dsonar.sourceEncoding=UTF-8 \
    -Dsonar.working.directory=.scannerwork \
    -Dsonar.scm.provider=git
echo
echo "SonarQube scan completed."
