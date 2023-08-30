# This list must match the versions specified in
# python/lib/dependabot/python/language_version_manager.rb: PRE_INSTALLED_PYTHON_VERSIONS
ARG PY_3_11=3.11.5
ARG PY_3_10=3.10.13
ARG PY_3_9=3.9.18
ARG PY_3_8=3.8.18
ARG PYENV_VERSION=v2.3.25

FROM ghcr.io/dependabot/dependabot-updater-core as python-core
ARG PY_3_11
ARG PY_3_10
ARG PY_3_9
ARG PY_3_8
ARG PYENV_VERSION
USER root

# Install *only* the apt packages required for this builder image to build Python.
# C-libs needed by users to build their Python packages should be installed down below in the final docker image.
# TODO: not all these packages may be needed now that we've switched from `pyenv install` which compiled from source to
# downloading / copying pre-compiled python
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    build-essential \
    libbz2-dev \
    libffi-dev \
    liblzma-dev \
    libncursesw5-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libxml2-dev \
    libxmlsec1-dev \
    tk-dev \
    xz-utils \
    zlib1g-dev \
    # jq isn't necessary to build Python from source, it's used below for locating the download URLs
    jq \
  && rm -rf /var/lib/apt/lists/*

COPY --chown=dependabot:dependabot python/helpers /opt/python/helpers
USER root
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
# around that by downloading a pre-compiled version, then symlinking the `bin` folder to where pyenv expects it.
# In the future, we should consider dropping pyenv completely, as it's mostly used here for legacy reasons.

FROM python-core as python-3.8
RUN mkdir -p /opt/hostedtoolcache/Python/$PY_3_8/x64/ \
  && cd /opt/hostedtoolcache/Python/$PY_3_8/x64/ \
  && curl -L https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json \
  | jq 'map(select(.version == '\"$PY_3_8\"')) [].files | map(select(.platform == "linux" and .arch == "x64" and .platform_version == "22.04"))[] | .download_url' \
  | xargs -i -- curl -L {} \
  | tar xz \
  && rm build_output.txt Python-$PY_3_8.tgz tools_structure.txt setup.sh \
  && mkdir /usr/local/.pyenv/versions/ \
  && ln -s /opt/hostedtoolcache/Python/$PY_3_8/x64 /usr/local/.pyenv/versions/$PY_3_8 \
  && bash /opt/python/helpers/build $PY_3_8 \
  && cd /opt/hostedtoolcache/Python \
  && tar czf $PY_3_8.tar.gz $PY_3_8

FROM python-core as python-3.9
RUN mkdir -p /opt/hostedtoolcache/Python/$PY_3_9/x64/ \
  && cd /opt/hostedtoolcache/Python/$PY_3_9/x64/ \
  && curl -L https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json \
  | jq 'map(select(.version == '\"$PY_3_9\"')) [].files | map(select(.platform == "linux" and .arch == "x64" and .platform_version == "22.04"))[] | .download_url' \
  | xargs -i -- curl -L {} \
  | tar xz \
  && rm build_output.txt Python-$PY_3_9.tgz tools_structure.txt setup.sh \
  && mkdir /usr/local/.pyenv/versions/ \
  && ln -s /opt/hostedtoolcache/Python/$PY_3_9/x64 /usr/local/.pyenv/versions/$PY_3_9 \
  && bash /opt/python/helpers/build $PY_3_9 \
  && cd /opt/hostedtoolcache/Python \
  && tar czf $PY_3_9.tar.gz $PY_3_9

FROM python-core as python-3.10
RUN mkdir -p /opt/hostedtoolcache/Python/$PY_3_10/x64/ \
  && cd /opt/hostedtoolcache/Python/$PY_3_10/x64/ \
  && curl -L https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json \
  | jq 'map(select(.version == '\"$PY_3_10\"')) [].files | map(select(.platform == "linux" and .arch == "x64" and .platform_version == "22.04"))[] | .download_url ' \
  | xargs -i -- curl -L {} \
  | tar xz \
  && rm build_output.txt Python-$PY_3_10.tgz tools_structure.txt setup.sh \
  && mkdir /usr/local/.pyenv/versions/ \
  && ln -s /opt/hostedtoolcache/Python/$PY_3_10/x64 /usr/local/.pyenv/versions/$PY_3_10 \
  && bash /opt/python/helpers/build $PY_3_10 \
  && cd /opt/hostedtoolcache/Python \
  && tar czf $PY_3_10.tar.gz $PY_3_10

FROM python-core
# The pre-compiled Python expects to be installed to this dir
RUN mkdir -p /opt/hostedtoolcache/Python/$PY_3_11/x64/ \
  && cd /opt/hostedtoolcache/Python/$PY_3_11/x64/ \
  # TODO: Add support for arm64 on Ubuntu whenever actions/python-versions adds support for it. Currently not available.
  && curl -L https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json \
  | jq 'map(select(.version == '\"$PY_3_11\"')) [].files | map(select(.platform == "linux" and .arch == "x64" and .platform_version == "22.04"))[] | .download_url' \
  | xargs -i -- curl -L {} \
  | tar xz \
  # These files are part of the actions/python-versions install wrapper and aren't necessary.
  && rm build_output.txt Python-$PY_3_11.tgz tools_structure.txt setup.sh \
  # pyenv expects the python installation files in the `versions` folder, but the pre-compiled python3 / pip3
  # expect to reside in the /opt/hostedtoolcache/Python/x.y.z/x64 dir, so need a symlink to make them play nice.
  && mkdir /usr/local/.pyenv/versions/ \
  && ln -s /opt/hostedtoolcache/Python/$PY_3_11/x64 /usr/local/.pyenv/versions/$PY_3_11 \
  && pyenv global $PY_3_11 \
  && bash /opt/python/helpers/build $PY_3_11

COPY --from=python-3.8 /opt/hostedtoolcache/Python/$PY_3_8.tar.gz /opt/hostedtoolcache/Python/$PY_3_8.tar.gz
COPY --from=python-3.9 /opt/hostedtoolcache/Python/$PY_3_9.tar.gz /opt/hostedtoolcache/Python/$PY_3_9.tar.gz
COPY --from=python-3.10 /opt/hostedtoolcache/Python/$PY_3_10.tar.gz /opt/hostedtoolcache/Python/$PY_3_10.tar.gz

# Install C-libs needed to build users' Python packages. Please document why each package is needed.
USER root
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    # Used by pycurl
    libcurl4-openssl-dev \
    # Used by mysqlclient
    libmysqlclient-dev \
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
