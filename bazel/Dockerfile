FROM ghcr.io/dependabot/dependabot-updater-core

USER root

# Install Java and ca-certificates-java for Bazel (which uses embedded Java)
RUN apt-get update && \
    apt-get install -y --reinstall ca-certificates default-jre-headless ca-certificates-java && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL -o /usr/local/bin/bazelisk \
    https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 && \
    chmod +x /usr/local/bin/bazelisk && \
    ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel

# Create a system-wide .bazelrc to configure Bazel's JVM to use system certificates
# Bazel ignores JAVA_TOOL_OPTIONS, so we must use startup options
RUN echo "startup --host_jvm_args=-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts" > /etc/bazel.bazelrc && \
    echo "startup --host_jvm_args=-Djavax.net.ssl.trustStoreType=jks" >> /etc/bazel.bazelrc

USER dependabot

# Set SSL certificate paths for system tools
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    BAZEL_SYSTEM_BAZELRC=/etc/bazel.bazelrc

COPY --chown=dependabot:dependabot bazel $DEPENDABOT_HOME/bazel
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
