FROM ghcr.io/dependabot/dependabot-updater-core
USER root

RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    dirmngr \
    gnupg2 \
    zlib1g-dev \
    liblzma-dev \
    libgdbm-dev \
    bison \
    tzdata \
    zip \
    unzip \
    openssh-client \
    software-properties-common \
    curl \
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
    python3-enchant

### PYTHON
COPY --chown=dependabot:dependabot python/helpers /opt/python/helpers
# Install Python with pyenv.
USER root
ENV PYENV_ROOT=/usr/local/.pyenv \
  PATH="/usr/local/.pyenv/bin:$PATH"
RUN mkdir -p "$PYENV_ROOT" && chown dependabot:dependabot "$PYENV_ROOT"
USER dependabot
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
RUN git -c advice.detachedHead=false clone https://github.com/pyenv/pyenv.git --branch v2.3.9 --single-branch --depth=1 /usr/local/.pyenv \
  # This is the version of CPython that gets installed
  && pyenv install 3.11.1 \
  && pyenv global 3.11.1 \
  && pyenv install 3.10.9 \
  && pyenv install 3.9.16 \
  && pyenv install 3.8.16 \
  && pyenv install 3.7.16 \
  && rm -Rf /tmp/python-build* \
  && bash /opt/python/helpers/build \
  && cd /usr/local/.pyenv \
  && tar czf 3.10.tar.gz versions/3.10.9 \
  && tar czf 3.9.tar.gz versions/3.9.16 \
  && tar czf 3.8.tar.gz versions/3.8.16 \
  && tar czf 3.7.tar.gz versions/3.7.16 \
  && rm -Rf versions/3.10.9 \
  && rm -Rf versions/3.9.16 \
  && rm -Rf versions/3.8.16 \
  && rm -Rf versions/3.7.16

USER dependabot
COPY --chown=dependabot:dependabot python /home/dependabot/python