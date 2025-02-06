# syntax = docker/dockerfile:1

# Adjust BUN_VERSION as desired
ARG BUN_VERSION=1.2.2
FROM oven/bun:${BUN_VERSION}-slim AS base

LABEL fly_launch_runtime="Bun"

# Bun app lives here
WORKDIR /app


# Build thruster
FROM base AS thruster
ARG GO_VERSION=1.23.4
ARG THRUSTER_VERSION=0.1.8
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


FROM base
# Install chrome
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl gnupg && \
    curl https://dl-ssl.google.com/linux/linux_signing_key.pub | \
      gpg --dearmor > /etc/apt/trusted.gpg.d/google-archive.gpg && \
    echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y google-chrome-stable && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install npm modules
COPY --link bun.lock package.json ./
RUN bun install --production --frozen-lockfile

# Copy thruster
COPY --from=thruster /usr/local/bin/thrust /usr/local/bin/

# Create a non-root user to run the app
RUN useradd chrome --create-home --shell /bin/bash && \
    chmod -R +r /app/node_modules
USER chrome:chrome

# Copy application code
COPY --link . .

# Start the server
CMD [ "thrust", "bun", "server.ts", "--colors" ]
