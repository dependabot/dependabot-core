FROM dependabot/dependabot-common

# cargo install
RUN apk add --no-cache \
        cargo

# composer install
RUN apk add --no-cache \
        php7 \
        php7-json \
        php7-openssl \
        php7-phar \
        php7-zip \
        php7-zlib

# dep install
RUN apk add --no-cache \
        dep

# elm install
RUN apk add --no-cache \
        gmp \
        ncurses-libs
COPY --from=wunsh/alpine-elm:0.19 /elm/0.19/bin/elm /usr/local/bin/elm19
COPY --from=wunsh/alpine-elm:0.18 /elm/0.18/bin/elm /usr/local/bin/elm18

# go_modules install
RUN apk add --no-cache \
        go

# hex install
RUN apk add --no-cache \
        elixir

# npm_and_yarn install
RUN apk add --no-cache \
        nodejs

# python install
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

# helpers
COPY --from=dependabot/dependabot-composer     /opt /opt
COPY --from=dependabot/dependabot-dep          /opt /opt
COPY --from=dependabot/dependabot-go_modules   /opt /opt
COPY --from=dependabot/dependabot-hex          /opt /opt
COPY --from=dependabot/dependabot-npm_and_yarn /opt /opt
COPY --from=dependabot/dependabot-python       /opt /opt
COPY --from=dependabot/dependabot-terraform    /opt /opt
