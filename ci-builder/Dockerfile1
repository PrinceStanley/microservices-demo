FROM alpine:3.20

LABEL maintainer="Platform Engineering"

ENV HELM_VERSION=3.18.4
ENV KUBECTL_VERSION=v1.33.3
ENV YQ_VERSION=v4.47.2
ENV JFROG_VERSION=2.80.0
ENV SONAR_VERSION=7.3.0.5189

RUN apk add --no-cache \
    bash \
    git \
    curl \
    wget \
    unzip \
    jq \
    openssh \
    ca-certificates \
    python3 \
    py3-pip \
    tar \
    gzip \
    make

#
# kubectl
#

RUN curl -L \
https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
-o /usr/local/bin/kubectl \
&& chmod +x /usr/local/bin/kubectl

#
# Helm
#

RUN wget -qO- \
https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
| tar xz

RUN mv linux-amd64/helm /usr/local/bin/

RUN rm -rf linux-amd64

#
# yq
#

RUN wget \
https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
-O /usr/local/bin/yq

RUN chmod +x /usr/local/bin/yq

#
# JFrog CLI
#

RUN curl -fL https://install-cli.jfrog.io | sh

#RUN mv jf /usr/local/bin/

#
# Sonar Scanner
#
#
# Sonar Scanner
#

RUN wget -O /tmp/sonar-scanner.zip \
https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_VERSION}.zip

RUN unzip /tmp/sonar-scanner.zip -d /opt

RUN mv /opt/sonar-scanner-${SONAR_VERSION} /opt/sonar-scanner

RUN rm /tmp/sonar-scanner.zip

ENV PATH="/opt/sonar-scanner/bin:${PATH}"

WORKDIR /workspace

CMD ["cat"]
