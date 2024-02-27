# syntax = docker/dockerfile:1

# Adjust BUN_VERSION as desired
ARG BUN_VERSION=1.0.29
FROM oven/bun:${BUN_VERSION}-slim as base

LABEL fly_launch_runtime="Bun"

# Bun app lives here
WORKDIR /app

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
COPY --link bun.lockb package.json ./
RUN bun install --production --frozen-lockfile

# Create a non-root user to run the app
RUN useradd chrome --create-home --shell /bin/bash && \
    chmod -R +r /app/node_modules
USER chrome:chrome

# Copy application code
COPY --link . .

# Start the server
CMD [ "bun", "server.ts" ]
