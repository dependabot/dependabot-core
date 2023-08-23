# This list must match the versions specified in
# python/lib/dependabot/python/language_version_manager.rb: PRE_INSTALLED_PYTHON_VERSIONS
ARG PY_3_11=3.11.4
ARG PY_3_10=3.10.12
ARG PY_3_9=3.9.17
ARG PY_3_8=3.8.17
ARG PYENV_VERSION=v2.3.19

FROM ghcr.io/dependabot/dependabot-updater-core as python-core
ARG PY_3_11
ARG PY_3_10
ARG PY_3_9
ARG PY_3_8
ARG PYENV_VERSION
USER root

# Install *only* the apt packages required for this builder image to build Python.
# C-libs needed by users to build their Python packages should be installed down below in the final docker image.
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    dirmngr \
    zlib1g-dev \
    liblzma-dev \
    libgdbm-dev \
    bison \
    tzdata \
    zip \
    openssh-client \
    build-essential \
    make \
    libpq-dev \
    libssl-dev \
    libbz2-dev \
    libffi-dev \
    libreadline-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    llvm \
    libncurses5-dev \
    libncursesw5-dev \
    libmysqlclient-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libgeos-dev \
    python3-enchant \
  && rm -rf /var/lib/apt/lists/*

COPY --chown=dependabot:dependabot python/helpers /opt/python/helpers
USER root
ENV PYENV_ROOT=/usr/local/.pyenv \
  PATH="/usr/local/.pyenv/bin:$PATH"
RUN mkdir -p "$PYENV_ROOT" && chown dependabot:dependabot "$PYENV_ROOT"
USER dependabot
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
RUN git -c advice.detachedHead=false clone https://github.com/pyenv/pyenv.git --branch $PYENV_VERSION --single-branch --depth=1 /usr/local/.pyenv

FROM python-core as python-3.8
RUN pyenv install $PY_3_8 \
  && bash /opt/python/helpers/build $PY_3_8 \
  && cd /usr/local/.pyenv \
  && tar czf 3.8.tar.gz versions/$PY_3_8

FROM python-core as python-3.9
RUN pyenv install $PY_3_9 \
  && bash /opt/python/helpers/build $PY_3_9 \
  && cd /usr/local/.pyenv \
  && tar czf 3.9.tar.gz versions/$PY_3_9

FROM python-core as python-3.10
RUN pyenv install $PY_3_10 \
  && bash /opt/python/helpers/build $PY_3_10 \
  && cd /usr/local/.pyenv \
  && tar czf 3.10.tar.gz versions/$PY_3_10

FROM python-core
RUN pyenv install $PY_3_11 \
  && pyenv global $PY_3_11 \
  && bash /opt/python/helpers/build $PY_3_11

COPY --from=python-3.10 /usr/local/.pyenv/3.10.tar.gz /usr/local/.pyenv/3.10.tar.gz
COPY --from=python-3.9 /usr/local/.pyenv/3.9.tar.gz /usr/local/.pyenv/3.9.tar.gz
COPY --from=python-3.8 /usr/local/.pyenv/3.8.tar.gz /usr/local/.pyenv/3.8.tar.gz

USER dependabot

COPY --chown=dependabot:dependabot python $DEPENDABOT_HOME/python
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
