# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.7
FROM ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT="1"

# Update gems and bundler; install sentry-ruby for error reporting
RUN gem update --system --no-document && \
    gem install -N bundler sentry-ruby

# Install curl
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl 


# Throw-away build stage to reduce size of final image
FROM base AS build

# Build argument for deployment target (used during prerendering)
ARG RAILS_PROXY_HOST

# Install packages needed to build gems
RUN apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config zlib1g-dev

# Install application gems
COPY --link Gemfile Gemfile.lock ./
RUN bundle install && \
    bundle exec bootsnap precompile --gemfile && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY --link . .

# Install esbuild
RUN cd /usr/local/bin && \
    curl -fsSL https://esbuild.github.io/dl/latest | sh

# Precompile bootsnap code for faster boot times
RUN ls /usr/local/bin && bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE=DUMMY ./bin/rails assets:precompile

# Prerender static HTML pages (requires showcases.yml, map.yml, and index.sqlite3)
# This runs during build so static pages are baked into the image
# Eliminates need to start index tenant on first request
# Note: index.sqlite3 is included via .dockerignore exception
# RAILS_PROXY_HOST build arg controls server warnings and banners in pre-rendered pages
RUN SECRET_KEY_BASE=DUMMY RAILS_ENV=production RAILS_APP_DB=index \
    RAILS_PROXY_HOST=${RAILS_PROXY_HOST} \
    bundle exec rake prerender && \
    rm -f db/index.sqlite3*

# Generate maintenance mode configuration
# This config is used during startup before full config generation
# Includes all infrastructure (routes, auth, managed processes) but no tenants
RUN SECRET_KEY_BASE=DUMMY RAILS_ENV=production \
    bundle exec rake nav:maintenance


# Build Navigator
FROM golang:trixie AS build-nav

# Set working directory for Go build
WORKDIR /app

# Copy navigator submodule
COPY navigator .

# Download Go dependencies
RUN go mod download

# Build navigator with version info from build args
RUN NAV_BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ); \
    echo "Building Navigator" && \
    go build -ldflags="-X 'main.buildTime=${NAV_BUILD_TIME}'" \
        -o /usr/local/bin/navigator cmd/navigator/main.go

# Nats CLI
RUN go install github.com/nats-io/natscli/nats@latest


# Final stage for app image
FROM base

# Install packages needed for deployment
RUN bash -c "$(curl -L https://setup.vector.dev)" && \
    apt-get install --no-install-recommends -y dnsutils nats-server poppler-utils procps ruby-foreman sqlite3 sudo vector vim unzip && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails
COPY --from=build-nav /usr/local/bin/navigator /usr/local/bin/
COPY --from=build-nav /go/bin/nats /usr/local/bin/nats

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
    mkdir /data && \
    chown -R rails:rails db log storage tmp /data

# Prep demo
RUN SECRET_KEY_BASE=DUMMY RAILS_APP_DB=demo bin/rails db:prepare

# Deployment options
ENV DATABASE_URL="sqlite3:///data/production.sqlite3" \
    RAILS_DB_VOLUME="/data/db" \
    RAILS_LOG_VOLUME="/data/log" \
    RAILS_SERVE_STATIC_FILES="true" \
    RAILS_STORAGE="/data/storage" \
    LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"

# Start navigator with maintenance config
# Navigator will execute the ready hook (script/nav_initialization.rb) which:
# - Syncs databases from S3
# - Updates htpasswd
# - Generates full navigator config
# - Returns, triggering navigator config reload
# After reload, ready hook (script/ready.sh) updates prerendered content
EXPOSE 3000
VOLUME /data
CMD [ "navigator", "config/navigator-maintenance.yml" ]
