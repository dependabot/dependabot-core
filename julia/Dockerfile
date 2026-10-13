# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

USER dependabot

# Install Julia, pinned to the 1.13 release channel rather than juliaup's default
# `release` channel so a new minor Julia release cannot change the image under us.
#
# The install is retried because juliaup fetches its version database from
# julialang-s3.julialang.org, which intermittently times out during image builds.
# The failing request is made by the juliaup binary itself, whose reqwest blocking
# client has a fixed ~30s request timeout that juliaup does not expose for tuning,
# and julialang-s3 has no faster official mirror we'd want to pin to, so retrying is
# the only clean lever. The repo's `curl --retry` convention only covers artifact
# downloads; here the flaky request is juliaup's own, so a single retry loop around
# the whole install is used. Each attempt removes any juliaup state first, because a
# failed install leaves ~/.julia/juliaup/juliaup.json behind and the non-interactive
# installer then refuses to run ("configuration file present from a previous
# installation").
RUN attempts=8; delay=10; \
    for attempt in $(seq 1 $attempts); do \
      rm -rf ~/.juliaup ~/.julia/juliaup; \
      if curl -fsSL https://install.julialang.org | sh -s -- -y --default-channel 1.13; then \
        break; \
      fi; \
      if [ "$attempt" -eq "$attempts" ]; then \
        echo "juliaup install failed after ${attempts} attempts" >&2; exit 1; \
      fi; \
      echo "juliaup install attempt ${attempt}/${attempts} failed; retrying in ${delay}s..." >&2; \
      sleep "$delay"; delay=$((delay * 2)); \
    done \
    && . ~/.bashrc \
    && /home/dependabot/.juliaup/bin/julia --version

ENV PATH="/home/dependabot/.juliaup/bin:$PATH"

# Use the eager registry flavor for more up-to-date package information
# See: https://pkgdocs.julialang.org/v1/registries/#Registry-flavors
ENV JULIA_PKG_SERVER_REGISTRY_PREFERENCE="eager"

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --chown=dependabot:dependabot julia/helpers /opt/julia/helpers
RUN bash /opt/julia/helpers/build

# The Julia depot (~/.julia) is already in place from the build step above
# It contains precompiled packages, registries, and artifacts for fast startup

COPY --chown=dependabot:dependabot --parents julia common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
