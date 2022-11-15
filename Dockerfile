# install ruby

FROM quay.io/evl.ms/fullstaq-ruby:3.1.2-jemalloc-slim as base

LABEL fly_launch_runtime="rails"

ENV RAILS_ENV=production

RUN mkdir /app
WORKDIR /app

RUN gem update --system --no-document && \
    gem install -N bundler -v 2.3.23

#######################################################################

# Install gems

FROM base as gems

COPY bin bin
COPY config config
COPY lib/tasks lib/tasks
COPY Gemfile* ./

RUN --mount=type=cache,id=dev-apt-cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=dev-apt-lib,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,id=dev-gem-cache,sharing=locked,target=/app/.cache \
    rake -f lib/tasks/fly.rake fly:build_gems

#######################################################################

# install deployment packages

FROM base

COPY lib/tasks lib/tasks

RUN --mount=type=cache,id=prod-apt-cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=prod-apt-lib,sharing=locked,target=/var/lib/apt \
    rake -f lib/tasks/fly.rake fly:install && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# copy installed gems
COPY --from=gems /app /app
COPY --from=gems /usr/local/bundle /usr/local/bundle

#######################################################################

# Deploy your application
COPY . .

# Run build task defined in lib/tasks/fly.rake
RUN SECRET_KEY_BASE=1 bin/rails fly:build

# start server
ENV PORT 8080
ENV RAILS_LOG_TO_STDOUT true

CMD ["bin/rails", "fly:server"]
