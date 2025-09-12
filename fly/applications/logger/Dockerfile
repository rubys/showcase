# syntax = docker/dockerfile:1

# Adjust BUN_VERSION as desired
ARG BUN_VERSION=1.2.16
FROM oven/bun:${BUN_VERSION}-slim AS base

LABEL fly_launch_runtime="Bun"

# Bun app lives here
WORKDIR /app

# Set production environment
ENV NODE_ENV="production"


# Build thruster
FROM base AS thruster
ARG GO_VERSION=1.23.6
ARG THRUSTER_VERSION=0.1.10
RUN apt-get update \
 && apt-get install -y wget \
 && cd /root \
 && wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz \
 && tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz \
 && wget https://github.com/basecamp/thruster/archive/refs/tags/v${THRUSTER_VERSION}.tar.gz \
 && tar -xzf v${THRUSTER_VERSION}.tar.gz \
 && cd thruster-${THRUSTER_VERSION} \
 && /usr/local/go/bin/go build -o bin/ ./cmd/... \
 && cp bin/thrust /usr/local/bin/


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build node modules
RUN apt-get update -qq && \
    apt-get install -y build-essential pkg-config python-is-python3

# Install node modules
COPY --link bun.lock package.json ./
RUN bun install --ci

# Copy application code
COPY --link . .


# Final stage for app image
FROM base

# Install packages needed for deployment and Vector
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y dnsutils openssh-server procps rsync vim curl ca-certificates gnupg && \
    curl -1sLf 'https://repositories.timber.io/public/vector/gpg.3543DB2D0A2BC4B8.key' | gpg --dearmor -o /usr/share/keyrings/timber-vector-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/timber-vector-archive-keyring.gpg] https://repositories.timber.io/public/vector/deb/debian bookworm main" > /etc/apt/sources.list.d/timber-vector.list && \
    apt-get update && \
    apt-get install --no-install-recommends -y vector && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built application
COPY --from=build /app /app

# Copy thruster
COPY --from=thruster /usr/local/bin/thrust /usr/local/bin/

# Copy Vector configuration and entrypoint
COPY vector.toml /etc/vector/vector.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create log directory
RUN mkdir -p /logs/showcase && chmod 755 /logs/showcase

# Start both services
EXPOSE 3000 9000
CMD [ "/usr/local/bin/entrypoint.sh" ]
