FROM dependabot/dependabot-common

RUN apk add --no-cache \
        gmp \
        ncurses-libs

COPY --from=wunsh/alpine-elm:0.19 /elm/0.19/bin/elm /usr/local/bin/elm19
COPY --from=wunsh/alpine-elm:0.18 /elm/0.18/bin/elm /usr/local/bin/elm18
