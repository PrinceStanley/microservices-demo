# Enterprise IDP Implementation Guide

## Overview

This repository now includes the next phase of an enterprise-grade Internal Developer Platform implementation for Amazon EKS with Jenkins, Istio, ArgoCD, SonarQube, Trivy, and container image promotion.

## What is implemented

- Jenkins pipeline stages for checkout, metadata validation, service detection, SonarQube, secret scanning, dependency scanning, image build, image promotion, GitOps updates, ArgoCD sync, and deployment validation.
- Reusable scripts under scripts/ for build, push, Helm update, ArgoCD sync, and deployment validation.
- Regression coverage for the new automation scripts.

## Required Jenkins configuration

1. Create Jenkins credentials:
   - `sonarqube-token`
   - `argocd-admin-password`
   - `jfrog-docker-config` as a Kubernetes secret mounted into the Kaniko agent pod
2. Ensure the Jenkins Kubernetes cloud can launch the pod defined in jenkins/pod-kaniko.yaml.
3. Ensure the pipeline job points to jenkins/Jenkinsfile.

## Required cluster prerequisites

- ArgoCD available in the `argocd` namespace and accessible internally via ClusterIP service name.
- Istio ingress gateway and VirtualService resources already present for the application.
- Kubernetes namespace `online-boutique` exists.
- `kubectl` access from the Jenkins agent to the EKS cluster.

## Execution flow

1. Jenkins checks out the repository.
2. The pipeline detects changed services.
3. SonarQube, Trivy secret scan, and Trivy dependency scan run in parallel.
4. If changes are detected, images are built and promoted.
5. Helm values are updated and committed.
6. ArgoCD syncs the application.
7. Rollout and service validation complete.

## Important notes

- All internal cluster communications should continue to use Kubernetes ClusterIP service names rather than public URLs.
- All application traffic must traverse Istio so it remains visible in Kiali.
- Production deployments should use environment-specific credentials and secrets, not hard-coded values.
