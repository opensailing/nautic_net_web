# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20210902-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.14.2-erlang-25.0.2-debian-bullseye-20210902-slim
#
ARG ELIXIR_VERSION=1.14.2
ARG OTP_VERSION=25.0.2
ARG DEBIAN_VERSION=bullseye-20210902-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# install build dependencies
RUN apt-get update -y && \
  apt-get install -y cmake build-essential git curl wget && \
  apt-get clean && \
  rm -f /var/lib/apt/lists/*_*

# Add Yarn respository, and install Yarn (https://stackoverflow.com/a/47680012)
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
  echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
  apt-get update -y && \
  apt-get install -y yarn

# install Rust non-interactively, and put it in the $PATH so the netcdf Elixir dep can find it
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.66.1
ENV PATH="/root/.cargo/bin:$PATH"

ENV CONDA_PREFIX=/opt/conda
ENV PATH=${CONDA_PREFIX}/bin:$PATH
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-$(arch).sh -O ~/miniconda.sh && /bin/bash ~/miniconda.sh -b -p ${CONDA_PREFIX}
RUN conda install -y -c conda-forge libnetcdf=4.8.1 hdf5=1.12.1
ENV NETCDF_BUILD=true

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets

# Fetch and compile assets
RUN cd assets && yarn install
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y libstdc++6 libncurses5 locales \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/nautic_net ./

USER nobody

CMD ["/app/bin/server"]

# Appended by flyctl
# ENV ECTO_IPV6 true
# ENV ERL_AFLAGS "-proto_dist inet6_tcp"
