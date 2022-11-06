# install ruby

FROM quay.io/evl.ms/fullstaq-ruby:3.1.2-jemalloc-slim as base

LABEL fly_launch_runtime="rails"

ENV RAILS_ENV=production

RUN mkdir /app
WORKDIR /app

RUN gem update --system --no-document && \
    bundle config set app_config .bundle && \
    bundle config set without 'development test' && \
    bundle config set path vendor/bundle && \
    gem install -N bundler -v 2.3.23

#######################################################################

# install packages only needed at build time

FROM base as build_deps

COPY bin bin
COPY config config
COPY lib/tasks lib/tasks

RUN --mount=type=cache,id=dev-apt-cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=dev-apt-lib,sharing=locked,target=/var/lib/apt \
    rake -f lib/tasks/fly.rake fly:build_deps && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

#######################################################################

# install gems

FROM build_deps as gems

COPY Gemfile* ./

RUN bundle lock --add-platform x86_64-linux && \
    bundle install && \
    rm -rf /tmp/bundle/ruby/*/cache

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
COPY --from=gems /usr/lib/fullstaq-ruby/versions /usr/lib/fullstaq-ruby/versions
COPY --from=gems /usr/local/bundle /usr/local/bundle

#######################################################################

# Deploy your application
COPY . .

# Run build task defined in lib/tasks/fly.rake
RUN SECRET_KEY_BASE=1 bin/rails fly:build

# start server
ENV PORT 8080
ENV RAILS_LOG_TO_STDOUT true
ARG SERVER_COMMAND="bin/rails fly:server"
ENV SERVER_COMMAND ${SERVER_COMMAND}
CMD ${SERVER_COMMAND}
