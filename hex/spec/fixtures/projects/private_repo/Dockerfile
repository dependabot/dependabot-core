FROM hexpm/elixir:1.13.3-erlang-24.2.1-alpine-3.15.0 as build

WORKDIR /app

ENV MIX_ENV=prod

# Dependencies

RUN mix local.hex --force && mix local.rebar --force

# Mix/Hex Dependencies

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
COPY lib lib
COPY priv priv
RUN mix do compile, release

# Released

FROM alpine:3.15.0 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/dependabot ./

ENV HOME=/app
ENV MIX_ENV=prod

ENTRYPOINT ["bin/dependabot"]
CMD ["start"]
networks:
    service_tier:
      name: service_tier