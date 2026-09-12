# syntax=docker.io/docker/dockerfile:1.20
# This list must match the versions specified in
# python/lib/dependabot/python/language.rb: PRE_INSTALLED_PYTHON_VERSIONS_RAW
# python/spec/dependabot/python/file_fetcher_spec.rb: exposes the expected ecosystem_versions metric spec
# Python versions are pinned to the release of each minor/patch version.
ARG PY_3_14=3.14.5
ARG PY_3_13=3.13.13
ARG PY_3_12=3.12.13
ARG PY_3_11=3.11.15
ARG PY_3_10=3.10.20
# https://github.com/pyenv/pyenv/releases
ARG PYENV_VERSION=v2.6.16

FROM ghcr.io/dependabot/dependabot-updater-core AS python-core
ARG PY_3_14
ARG PY_3_13
ARG PY_3_12
ARG PY_3_11
ARG PY_3_10
ARG PYENV_VERSION
USER root

COPY --chown=dependabot:dependabot python/helpers /opt/python/helpers

# TODO: Now that switched from `pyenv install` which compiled from source to downloading / copying a pre-compiled python
# we could entirely drop pyenv if we change our ruby code that calls `pyenv exec` to track which version of python to
# call and uses the full python paths.
ENV PYENV_ROOT=/usr/local/.pyenv \
  PATH="/usr/local/.pyenv/bin:$PATH"
RUN mkdir -p "$PYENV_ROOT" && chown dependabot:dependabot "$PYENV_ROOT"
USER dependabot
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
RUN git -c advice.detachedHead=false clone https://github.com/pyenv/pyenv.git --branch $PYENV_VERSION --single-branch --depth=1 /usr/local/.pyenv

# We used to use `pyenv install 3.x.y` but it's really slow because it compiles from source (~500s). So instead, we hack
# around that by downloading pre-compiled versions, then placing them where pyenv expects it in the `versions` subfolder.
# In the future, we should consider dropping pyenv completely, as it's mostly used here for legacy reasons...
# Although it is convenient when debugging to be able to quickly flip through environments.
RUN mkdir "${PYENV_ROOT}/versions"

## 3.10
# Docker doesn't support parametrizing `COPY --from:python:$PY_1_23-bookworm`, so work around it using an alias.
# TODO: If upstream adds support for Ubuntu, use that instead of Debian as the base suffix: https://github.com/docker-library/python/pull/791
FROM docker.io/library/python:$PY_3_10-bookworm AS upstream-python-3.10
FROM python-core AS python-3.10
ARG PYTHON_INSTALL_LOCATION="$PYENV_ROOT/versions/$PY_3_10"
COPY --from=upstream-python-3.10 --chown=dependabot:dependabot /usr/local/bin $PYTHON_INSTALL_LOCATION/bin
COPY --from=upstream-python-3.10 --chown=dependabot:dependabot /usr/local/include $PYTHON_INSTALL_LOCATION/include
COPY --from=upstream-python-3.10 --chown=dependabot:dependabot /usr/local/lib $PYTHON_INSTALL_LOCATION/lib
# `pip` and other scripts need their shebangs rewritten for the new location
RUN find $PYTHON_INSTALL_LOCATION/bin -type f -exec sed -i "1s|^#!/usr/local/bin/python|#!$PYTHON_INSTALL_LOCATION/bin/python|" {} +
# Ensure pyenv works and it's the python version we expect
RUN PYENV_VERSION=$PY_3_10 pyenv exec python --version | grep "Python $PY_3_10" || exit 1
RUN bash /opt/python/helpers/build $PY_3_10
# This python environment occupies ~0.5 GB and gets used for a fraction of jobs, so store it compressed.
RUN cd $PYENV_ROOT/versions \
  && tar -acf $PY_3_10.tar.zst $PY_3_10

## 3.11
# Docker doesn't support parametrizing `COPY --from:python:$PY_1_23-bookworm`, so work around it using an alias.
# TODO: If upstream adds support for Ubuntu, use that instead of Debian as the base suffix: https://github.com/docker-library/python/pull/791
FROM docker.io/library/python:$PY_3_11-bookworm AS upstream-python-3.11
FROM python-core AS python-3.11
ARG PYTHON_INSTALL_LOCATION="$PYENV_ROOT/versions/$PY_3_11"
COPY --from=upstream-python-3.11 --chown=dependabot:dependabot /usr/local/bin $PYTHON_INSTALL_LOCATION/bin
COPY --from=upstream-python-3.11 --chown=dependabot:dependabot /usr/local/include $PYTHON_INSTALL_LOCATION/include
COPY --from=upstream-python-3.11 --chown=dependabot:dependabot /usr/local/lib $PYTHON_INSTALL_LOCATION/lib
# `pip` and other scripts need their shebangs rewritten for the new location
RUN find $PYTHON_INSTALL_LOCATION/bin -type f -exec sed -i "1s|^#!/usr/local/bin/python|#!${PYTHON_INSTALL_LOCATION}/bin/python|" {} +
# Ensure pyenv works and it's the python version we expect
RUN PYENV_VERSION=$PY_3_11 pyenv exec python --version | grep "Python $PY_3_11" || exit 1
RUN bash /opt/python/helpers/build $PY_3_11
# This python environment occupies ~0.5 GB and gets used for a fraction of jobs, so store it compressed.
RUN cd $PYENV_ROOT/versions \
  && tar -acf $PY_3_11.tar.zst $PY_3_11

## 3.12
# Docker doesn't support parametrizing `COPY --from:python:$PY_1_23-bookworm`, so work around it using an alias.
# TODO: If upstream adds support for Ubuntu, use that instead of Debian as the base suffix: https://github.com/docker-library/python/pull/791
FROM docker.io/library/python:$PY_3_12-bookworm AS upstream-python-3.12
FROM python-core AS python-3.12
ARG PYTHON_INSTALL_LOCATION="$PYENV_ROOT/versions/$PY_3_12"
COPY --from=upstream-python-3.12 --chown=dependabot:dependabot /usr/local/bin $PYTHON_INSTALL_LOCATION/bin
COPY --from=upstream-python-3.12 --chown=dependabot:dependabot /usr/local/include $PYTHON_INSTALL_LOCATION/include
COPY --from=upstream-python-3.12 --chown=dependabot:dependabot /usr/local/lib $PYTHON_INSTALL_LOCATION/lib
# `pip` and other scripts need their shebangs rewritten for the new location
RUN find $PYTHON_INSTALL_LOCATION/bin -type f -exec sed -i "1s|^#!/usr/local/bin/python|#!${PYTHON_INSTALL_LOCATION}/bin/python|" {} +
# Ensure pyenv works and it's the python version we expect
RUN PYENV_VERSION=$PY_3_12 pyenv exec python --version | grep "Python $PY_3_12" || exit 1
RUN bash /opt/python/helpers/build $PY_3_12
# This python environment occupies ~0.5 GB and gets used for a fraction of jobs, so store it compressed.
RUN cd $PYENV_ROOT/versions \
  && tar -acf $PY_3_12.tar.zst $PY_3_12

## 3.13
# Docker doesn't support parametrizing `COPY --from:python:$PY_1_23-bookworm`, so work around it using an alias.
# TODO: If upstream adds support for Ubuntu, use that instead of Debian as the base suffix: https://github.com/docker-library/python/pull/791
FROM docker.io/library/python:$PY_3_13-bookworm AS upstream-python-3.13
FROM python-core AS python-3.13
ARG PYTHON_INSTALL_LOCATION="$PYENV_ROOT/versions/$PY_3_13"
COPY --from=upstream-python-3.13 --chown=dependabot:dependabot /usr/local/bin $PYTHON_INSTALL_LOCATION/bin
COPY --from=upstream-python-3.13 --chown=dependabot:dependabot /usr/local/include $PYTHON_INSTALL_LOCATION/include
COPY --from=upstream-python-3.13 --chown=dependabot:dependabot /usr/local/lib $PYTHON_INSTALL_LOCATION/lib
# `pip` and other scripts need their shebangs rewritten for the new location
RUN find $PYTHON_INSTALL_LOCATION/bin -type f -exec sed -i "1s|^#!/usr/local/bin/python|#!${PYTHON_INSTALL_LOCATION}/bin/python|" {} +
# Ensure pyenv works and it's the python version we expect
RUN PYENV_VERSION=$PY_3_13 pyenv exec python --version | grep "Python $PY_3_13" || exit 1
RUN bash /opt/python/helpers/build $PY_3_13
RUN cd $PYENV_ROOT/versions \
  && tar -acf $PY_3_13.tar.zst $PY_3_13

## 3.14
# Docker doesn't support parametrizing `COPY --from:python:$PY_1_23-bookworm`, so work around it using an alias.
# TODO: If upstream adds support for Ubuntu, use that instead of Debian as the base suffix: https://github.com/docker-library/python/pull/791
FROM docker.io/library/python:$PY_3_14-bookworm AS upstream-python-3.14
FROM python-core AS python-3.14
ARG PYTHON_INSTALL_LOCATION="$PYENV_ROOT/versions/$PY_3_14"
COPY --from=upstream-python-3.14 --chown=dependabot:dependabot /usr/local/bin $PYTHON_INSTALL_LOCATION/bin
COPY --from=upstream-python-3.14 --chown=dependabot:dependabot /usr/local/include $PYTHON_INSTALL_LOCATION/include
COPY --from=upstream-python-3.14 --chown=dependabot:dependabot /usr/local/lib $PYTHON_INSTALL_LOCATION/lib
# `pip` and other scripts need their shebangs rewritten for the new location
RUN find $PYTHON_INSTALL_LOCATION/bin -type f -exec sed -i "1s|^#!/usr/local/bin/python|#!${PYTHON_INSTALL_LOCATION}/bin/python|" {} +
# Ensure pyenv works and it's the python version we expect
RUN PYENV_VERSION=$PY_3_14 pyenv exec python --version | grep "Python $PY_3_14" || exit 1
RUN bash /opt/python/helpers/build $PY_3_14
# This is the default Python, so no need to tar it

FROM ghcr.io/dependabot/dependabot-updater-python-runtime
ARG PY_3_14
ARG PY_3_13
ARG PY_3_12
ARG PY_3_11
ARG PY_3_10
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
  SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

COPY --chown=dependabot:dependabot --parents python common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

# Running these steps last means that if the builds in the concurrent stages take longer it doesn't block the pipeline until the end.
COPY --from=python-3.10 $PYENV_ROOT/versions/$PY_3_10.tar.zst $PYENV_ROOT/versions/$PY_3_10.tar.zst
COPY --from=python-3.11 $PYENV_ROOT/versions/$PY_3_11.tar.zst $PYENV_ROOT/versions/$PY_3_11.tar.zst
COPY --from=python-3.12 $PYENV_ROOT/versions/$PY_3_12.tar.zst $PYENV_ROOT/versions/$PY_3_12.tar.zst
COPY --from=python-3.13 $PYENV_ROOT/versions/$PY_3_13.tar.zst $PYENV_ROOT/versions/$PY_3_13.tar.zst
COPY --from=python-3.14 $PYENV_ROOT/versions/ $PYENV_ROOT/versions/

# Copy the output of the build script, it should be identical across Python versions
COPY --from=python-3.14 /opt/python/ /opt/python/

RUN pyenv global $PY_3_14

COPY --chown=dependabot:dependabot --parents cargo common $DEPENDABOT_HOME/

COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
