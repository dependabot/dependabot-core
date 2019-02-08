FROM dependabot/dependabot-common

RUN apk add --no-cache \
        bash \
        build-base \
        libffi-dev \
        openssl-dev \
        bzip2-dev \
        zlib-dev \
        readline-dev \
        sqlite-dev

ENV PYENV_ROOT=/usr/local/.pyenv \
    PATH="/usr/local/.pyenv/bin:$PATH"
RUN git clone https://github.com/pyenv/pyenv.git /usr/local/.pyenv \
    && cd /usr/local/.pyenv && git checkout v1.2.15 && cd - \
    && pyenv install 3.8.0 \
    && pyenv install 2.7.17 \
    && pyenv global 3.8.0

COPY helpers /opt/python/helpers
RUN ash /opt/python/helpers/build /opt/python
