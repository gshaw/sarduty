# cspell:ignore rebar trixie libvips musl esac

# Debian rather than Alpine, to avoid DNS resolution issues in production.
# Keep the versions in step with .mise.toml. Image tags:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags?name=debian-trixie - build image
#   - https://hub.docker.com/_/debian/tags?name=trixie - release image
#
ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.1.2
ARG DEBIAN_VERSION=trixie-20261020-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

# Typst makes tax credit letters (#918): the release's static build, checked against its
# checksum. Keep TYPST_VERSION in step with .mise.toml and Service.Typst.
FROM ${RUNNER_IMAGE} AS typst

ARG TYPST_VERSION=0.15.1
ARG TARGETARCH

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH:-amd64}" in \
    amd64) arch=x86_64 sha=a6d077d0a95eed5a2eba715b2dae06be954f624ccbf85758a03f389ded33118c ;; \
    arm64) arch=aarch64 sha=5aa8d74a3d906e60ea12a66ac2f37f8eef1b14cbad7182a745e393a10c23dcee ;; \
    *) echo "No Typst build for ${TARGETARCH}" >&2; exit 1 ;; \
  esac \
  && curl -fsSL -o /tmp/typst.tar.xz \
    "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${arch}-unknown-linux-musl.tar.xz" \
  && echo "${sha}  /tmp/typst.tar.xz" | sha256sum -c - \
  && tar -xJf /tmp/typst.tar.xz -C /tmp \
  && install -m 755 "/tmp/typst-${arch}-unknown-linux-musl/typst" /usr/local/bin/typst \
  && typst --version

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
# libvips-dev: vix builds against Debian's libvips rather than downloading its own (#497)
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git libvips-dev pkg-config \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"
ENV VIX_COMPILATION_MODE="PLATFORM_PROVIDED_LIBVIPS"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Web.StyleGuideHTML embeds assets/css/tokens.css and docs/writing.md at compile time,
# and Web.ChangelogLive embeds CHANGELOG.md
COPY assets assets
COPY docs/writing.md docs/
COPY CHANGELOG.md ./

# Compile the release
RUN mix compile

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates libvips42t64 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=docker.io/litestream/litestream:0.5.17 /usr/local/bin/litestream /usr/local/bin/litestream
COPY --from=typst /usr/local/bin/typst /usr/local/bin/typst

# Debian's built-in UTF-8 locale; the BEAM needs UTF-8 for filenames and I/O
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/sarduty ./

# Copy Litestream configuration
COPY --chown=nobody:root litestream.yml /app/litestream.yml

USER nobody

CMD ["/app/bin/server"]
