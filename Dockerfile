FROM elixir:1.19.5-otp-28-slim AS builder

RUN apt-get update -y && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
RUN mix release

# ---- Runner ----
FROM debian:trixie-slim

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/planning_poker ./

USER nobody

CMD ["/app/bin/planning_poker", "start"]
