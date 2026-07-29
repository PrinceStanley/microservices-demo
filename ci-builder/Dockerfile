FROM alpine:3.20

LABEL maintainer="Platform Engineering"

ENV HELM_VERSION=3.18.4
ENV KUBECTL_VERSION=v1.33.3
ENV YQ_VERSION=v4.47.2
ENV JFROG_VERSION=2.80.0
ENV SONAR_VERSION=7.3.0.5189
ENV TRIVY_VERSION=0.71.2
ENV ARGOCD_VERSION=v3.1.0

###############################################################################
# Base Packages
###############################################################################

RUN apk add --no-cache \
    bash \
    git \
    curl \
    wget \
    unzip \
    jq \
    openssh-client \
    openssl \
    ca-certificates \
    python3 \
    py3-pip \
    tar \
    gzip \
    make \
    docker-cli \
    coreutils \
    grep \
    sed \
    findutils \
    libc6-compat \
    openjdk17-jre-headless

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"
###############################################################################
# Git Configuration
###############################################################################

RUN git config --system --add safe.directory '*'

###############################################################################
# kubectl
###############################################################################

RUN curl -fsSL \
    https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

###############################################################################
# Helm
###############################################################################

RUN wget -qO- \
    https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
    | tar -xz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64

###############################################################################
# yq
###############################################################################

RUN wget -q \
    https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
    -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

###############################################################################
# JFrog CLI
###############################################################################

RUN curl -fL https://install-cli.jfrog.io | sh 

###############################################################################
# Sonar Scanner
###############################################################################

RUN wget -q \
    https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_VERSION}.zip \
    -O /tmp/sonar-scanner.zip && \
    unzip /tmp/sonar-scanner.zip -d /opt && \
    mv /opt/sonar-scanner-${SONAR_VERSION} /opt/sonar-scanner && \
    rm -f /tmp/sonar-scanner.zip

ENV PATH="/opt/sonar-scanner/bin:${PATH}"

###############################################################################
# Trivy
###############################################################################

RUN wget -q \
    https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz \
    -O /tmp/trivy.tar.gz && \
    tar -xzf /tmp/trivy.tar.gz -C /tmp && \
    mv /tmp/trivy /usr/local/bin/trivy && \
    chmod +x /usr/local/bin/trivy && \
    rm -f /tmp/trivy.tar.gz

###############################################################################
# ArgoCD CLI
###############################################################################

RUN curl -fsSL \
    https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64 \
    -o /usr/local/bin/argocd && \
    chmod +x /usr/local/bin/argocd

###############################################################################
# Verify Installations
###############################################################################

RUN git --version && \
    kubectl version --client && \
    helm version --short && \
    yq --version && \
    jq --version && \
    jf --version && \
    java --version && \
    sonar-scanner --version && \
    trivy --version && \
    argocd version --client

###############################################################################

WORKDIR /workspace

CMD ["cat"]
