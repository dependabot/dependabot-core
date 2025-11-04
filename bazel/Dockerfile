FROM ghcr.io/dependabot/dependabot-updater-core

# Install Bazel and Bazelisk for lockfile generation
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  curl \
  && rm -rf /var/lib/apt/lists/*

# Install Bazelisk (which can manage multiple Bazel versions)
RUN curl -L "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64" \
  -o /usr/local/bin/bazelisk \
  && chmod +x /usr/local/bin/bazelisk \
  && ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel

USER dependabot

COPY --chown=dependabot:dependabot bazel $DEPENDABOT_HOME/bazel
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
