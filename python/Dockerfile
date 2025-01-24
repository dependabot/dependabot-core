# This list must match the versions specified in
# python/lib/dependabot/python/language_version_manager.rb: PRE_INSTALLED_PYTHON_VERSIONS
ARG PY_3_13=3.13.1
ARG PY_3_12=3.12.7
ARG PY_3_11=3.11.9
ARG PY_3_10=3.10.15
ARG PY_3_9=3.9.18
ARG PY_3_8=3.8.20
ARG PYENV_VERSION=v2.4.22

FROM ghcr.io/dependabot/dependabot-updater-core as python-core
ARG PY_3_13
ARG PY_3_12
ARG PY_3_11
ARG PY_3_10
ARG PY_3_9
ARG PY_3_8
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
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
RUN git -c advice.detachedHead=false clone https://github.com/pyenv/pyenv.git --branch $PYENV_VERSION --single-branch --depth=1 /usr/local/.pyenv

# We used to use `pyenv install 3.x.y` but it's really slow because it compiles from source (~500s). So instead, we hack
# around that by downloading pre-compiled versions, then placing them where pyenv expects it in the `versions` subfolder.
# In the future, we should consider dropping pyenv completely, as it's mostly used here for legacy reasons...
# Although it is convenient when debugging to be able to quickly flip through environments.
RUN mkdir "${PYENV_ROOT}/versions"

## 3.8
# Docker doesn't support parametrizing `COPY --from:python:$PY_1_23-bookworm`, so work around it using an alias.
# TODO: If upstream adds support for Ubuntu, use that instead of Debian as the base suffix: https://github.com/docker-library/python/pull/791
FROM docker.io/library/python:$PY_3_8-bookworm as upstream-python-3.8
FROM python-core as python-3.8
ARG PYTHON_INSTALL_LOCATION="$PYENV_ROOT/versions/$PY_3_8"
COPY --from=upstream-python-3.8 --chown=dependabot:dependabot /usr/local/bin $PYTHON_INSTALL_LOCATION/bin
COPY --from=upstream-python-3.8 --chown=dependabot:dependabot /usr/local/include $PYTHON_INSTALL_LOCATION/include
COPY --from=upstream-python-3.8 --chown=dependabot:dependabot /usr/local/lib $PYTHON_INSTALL_LOCATION/lib
# `pip` and other scripts need their shebangs rewritten for the new location
RUN find $PYTHON_INSTALL_LOCATION/bin -type f -exec sed -i "1s|^#!/usr/local/bin/python|#!$PYTHON_INSTALL_LOCATION/bin/python|" {} +
# Ensure pyenv works and it's the python version we expect
RUN PYENV_VERSION=$PY_3_8 pyenv exec python --version | grep "Python $PY_3_8" || exit 1
RUN bash /opt/python/helpers/build $PY_3_8
# This python environment occupies ~0.5 GB and gets used for a fraction of jobs, so store it compressed.
RUN cd $PYENV_ROOT/versions \
  && tar -acf $PY_3_8.tar.zst $PY_3_8

## 3.9
# Docker doesn't support parametrizing `COPY --from:python:$PY_1_23-bookworm`, so work around it using an alias.
# TODO: If upstream adds support for Ubuntu, use that instead of Debian as the base suffix: https://github.com/docker-library/python/pull/791
FROM docker.io/library/python:$PY_3_9-bookworm as upstream-python-3.9
FROM python-core as python-3.9
ARG PYTHON_INSTALL_LOCATION="$PYENV_ROOT/versions/$PY_3_9"
COPY --from=upstream-python-3.9 --chown=dependabot:dependabot /usr/local/bin $PYTHON_INSTALL_LOCATION/bin
COPY --from=upstream-python-3.9 --chown=dependabot:dependabot /usr/local/include $PYTHON_INSTALL_LOCATION/include
COPY --from=upstream-python-3.9 --chown=dependabot:dependabot /usr/local/lib $PYTHON_INSTALL_LOCATION/lib
# `pip` and other scripts need their shebangs rewritten for the new location
RUN find $PYTHON_INSTALL_LOCATION/bin -type f -exec sed -i "1s|^#!/usr/local/bin/python|#!$PYTHON_INSTALL_LOCATION/bin/python|" {} +
# Ensure pyenv works and it's the python version we expect
RUN PYENV_VERSION=$PY_3_9 pyenv exec python --version | grep "Python $PY_3_9" || exit 1
RUN bash /opt/python/helpers/build $PY_3_9
# This python environment occupies ~0.5 GB and gets used for a fraction of jobs, so store it compressed.
RUN cd $PYENV_ROOT/versions \
  && tar -acf $PY_3_9.tar.zst $PY_3_9

## 3.10
# Docker doesn't support parametrizing `COPY --from:python:$PY_1_23-bookworm`, so work around it using an alias.
# TODO: If upstream adds support for Ubuntu, use that instead of Debian as the base suffix: https://github.com/docker-library/python/pull/791
FROM docker.io/library/python:$PY_3_10-bookworm as upstream-python-3.10
FROM python-core as python-3.10
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
FROM docker.io/library/python:$PY_3_11-bookworm as upstream-python-3.11
FROM python-core as python-3.11
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
FROM docker.io/library/python:$PY_3_12-bookworm as upstream-python-3.12
FROM python-core as python-3.12
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
FROM docker.io/library/python:$PY_3_13-bookworm as upstream-python-3.13
FROM python-core as python-3.13
ARG PYTHON_INSTALL_LOCATION="$PYENV_ROOT/versions/$PY_3_13"
COPY --from=upstream-python-3.13 --chown=dependabot:dependabot /usr/local/bin $PYTHON_INSTALL_LOCATION/bin
COPY --from=upstream-python-3.13 --chown=dependabot:dependabot /usr/local/include $PYTHON_INSTALL_LOCATION/include
COPY --from=upstream-python-3.13 --chown=dependabot:dependabot /usr/local/lib $PYTHON_INSTALL_LOCATION/lib
# `pip` and other scripts need their shebangs rewritten for the new location
RUN find $PYTHON_INSTALL_LOCATION/bin -type f -exec sed -i "1s|^#!/usr/local/bin/python|#!${PYTHON_INSTALL_LOCATION}/bin/python|" {} +
# Ensure pyenv works and it's the python version we expect
RUN PYENV_VERSION=$PY_3_13 pyenv exec python --version | grep "Python $PY_3_13" || exit 1
RUN bash /opt/python/helpers/build $PY_3_13
# This is the default Python, so no need to tar it

FROM python-core
# Install C-libs needed to build users' Python packages. Please document why each package is needed.
USER root
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    # Used by pycurl
    libcurl4-openssl-dev \
    # Used by mysqlclient
    libmysqlclient-dev \
    pkg-config \
    # Used by psycopg Postgres Client
    libpq-dev \
    # Used by python zoneinfo core lib
    tzdata \
    # Needed to build `gssapi`/`krb5`
    libkrb5-dev \
  && rm -rf /var/lib/apt/lists/*

USER dependabot

COPY --chown=dependabot:dependabot python $DEPENDABOT_HOME/python
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

# Running these steps last means that if the builds in the concurrent stages take longer it doesn't block the pipeline until the end.
COPY --from=python-3.8 $PYENV_ROOT/versions/$PY_3_8.tar.zst $PYENV_ROOT/versions/$PY_3_8.tar.zst
COPY --from=python-3.9 $PYENV_ROOT/versions/$PY_3_9.tar.zst $PYENV_ROOT/versions/$PY_3_9.tar.zst
COPY --from=python-3.10 $PYENV_ROOT/versions/$PY_3_10.tar.zst $PYENV_ROOT/versions/$PY_3_10.tar.zst
COPY --from=python-3.11 $PYENV_ROOT/versions/$PY_3_11.tar.zst $PYENV_ROOT/versions/$PY_3_11.tar.zst
COPY --from=python-3.12 $PYENV_ROOT/versions/$PY_3_12.tar.zst $PYENV_ROOT/versions/$PY_3_12.tar.zst
COPY --from=python-3.13 $PYENV_ROOT/versions/ $PYENV_ROOT/versions/

# Copy the output of the build script, it should be identical across Python versions
COPY --from=python-3.13 /opt/python/ /opt/python/

# Set pyenv global Python version
RUN pyenv global $PY_3_13

# Set Python version to $PY_3_13
ENV PYENV_VERSION=$PY_3_13

# Set PYTHONPATH explicitly
ENV PYTHONPATH="/opt/pyenv/versions/3.13.1/lib/python3.13/site-packages"

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    python3-dev \
    python3-distutils \
    gfortran \
    libatlas-base-dev \
    liblapack-dev \
    libopenblas-dev \
    libsqlite3-dev \
    libjpeg-dev \
    libproj-dev \
    libgeos-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    wget \
    curl \
    libssl-dev

# Install dependencies for building GDAL
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libgif-dev \
    liblzma-dev \
    libnetcdf-dev \
    libhdf5-serial-dev \
    libhdf4-alt-dev \
    libpq-dev \
    libxerces-c-dev \
    libspatialite-dev \
    libwebp-dev \
    libpoppler-dev \
    libpoppler-private-dev \
    libfreexl-dev \
    libgeotiff-dev \
    liblcms2-dev \
    libpodofo-dev \
    swig \
    cmake \
    python3-numpy

# Install Python bindings for GDAL
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3

# Install pip, setuptools, and wheel
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel

# Download and build GDAL from source using CMake
WORKDIR /tmp
RUN wget --no-check-certificate http://download.osgeo.org/gdal/3.10.1/gdal-3.10.1.tar.gz && \
    tar -xvf gdal-3.10.1.tar.gz

WORKDIR /tmp/gdal-3.10.1
RUN mkdir build && cd build && \
    cmake .. -DBUILD_PYTHON_BINDINGS=ON -DGDAL_BUILD_OPTIONAL_DRIVERS=ON -DCMAKE_EXE_LINKER_FLAGS="-lssl -lcrypto" && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Set GDAL environment variables
ENV CPLUS_INCLUDE_PATH=/usr/include/gdal
ENV C_INCLUDE_PATH=/usr/include/gdal

# Set PIP_NO_SSL_VERIFY to true to disable SSL verification for pip
ENV PIP_NO_SSL_VERIFY=true

WORKDIR /home/dependabot/dependabot-updater
# Install numpy and GDAL Python bindings, ensuring the version matches the installed libgdal
RUN python3 -m pip install --no-cache-dir --prefer-binary gdal==3.10.1 numpy
