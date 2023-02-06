# syntax = docker/dockerfile:experimental

# Dockerfile used to build a deployable image for a Rails application.
# Adjust as required.
#
# Common adjustments you may need to make over time:
#  * Modify version numbers for Ruby, Bundler, and other products.
#  * Add library packages needed at build time for your gems, node modules.
#  * Add deployment packages needed by your application
#  * Add (often fake) secrets needed to compile your assets

#######################################################################

# Learn more about the chosen Ruby stack, Fullstaq Ruby, here:
#   https://github.com/evilmartians/fullstaq-ruby-docker.
#
# We recommend using the highest patch level for better security and
# performance.

ARG RUBY_VERSION=3.2.0
ARG VARIANT=jemalloc-slim
FROM quay.io/evl.ms/fullstaq-ruby:${RUBY_VERSION}-${VARIANT} as base

LABEL fly_launch_runtime="rails"

ARG BUNDLER_VERSION=2.3.23

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}

ARG BUNDLE_WITHOUT=development:test
ARG BUNDLE_PATH=vendor/bundle
ENV BUNDLE_PATH ${BUNDLE_PATH}
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}

RUN mkdir /app
WORKDIR /app
RUN mkdir -p tmp/pids

RUN gem update --system --no-document && \
    gem install -N bundler -v ${BUNDLER_VERSION}

#######################################################################

# install packages only needed at build time

FROM base as build_deps

ARG BUILD_PACKAGES="git build-essential wget curl gzip xz-utils libsqlite3-dev zlib1g-dev"
ENV BUILD_PACKAGES ${BUILD_PACKAGES}

RUN --mount=type=cache,id=dev-apt-cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=dev-apt-lib,sharing=locked,target=/var/lib/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y ${BUILD_PACKAGES} \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

#######################################################################

# install gems

FROM build_deps as gems

COPY Gemfile* ./
RUN bundle install &&  rm -rf vendor/bundle/ruby/*/cache

#######################################################################

# install deployment packages

FROM base

# add passenger repository
RUN apt-get install -y dirmngr gnupg apt-transport-https ca-certificates curl && \
  curl https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key.txt | \
    gpg --dearmor > /etc/apt/trusted.gpg.d/phusion.gpg && \
  sh -c 'echo deb https://oss-binaries.phusionpassenger.com/apt/passenger bullseye main > /etc/apt/sources.list.d/passenger.list'

# add google chrome repository
RUN curl https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
 && echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list

ARG DEPLOY_PACKAGES="file vim curl gzip nginx passenger libnginx-mod-http-passenger sqlite3 libsqlite3-0 google-chrome-stable ruby-foreman redis-server apache2-utils openssh-server rsync"
ENV DEPLOY_PACKAGES=${DEPLOY_PACKAGES}

RUN --mount=type=cache,id=prod-apt-cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=prod-apt-lib,sharing=locked,target=/var/lib/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    ${DEPLOY_PACKAGES} \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# configure redis
RUN sed -i 's/^daemonize yes/daemonize no/' /etc/redis/redis.conf &&\
  sed -i 's/^bind/# bind/' /etc/redis/redis.conf &&\
  sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf &&\
  sed -i 's/^logfile/# logfile/' /etc/redis/redis.conf 

# copy installed gems
COPY --from=gems /app /app
COPY --from=gems /usr/lib/fullstaq-ruby/versions /usr/lib/fullstaq-ruby/versions
COPY --from=gems /usr/local/bundle /usr/local/bundle

#######################################################################

# configure sshd
RUN sed -i 's/^#\s*Port.*/Port 2222/' /etc/ssh/sshd_config && \
    sed -i 's/^#\s*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    mkdir /var/run/sshd && \
    chmod 0755 /var/run/sshd

# configure nginx/passenger
RUN rm /etc/nginx/sites-enabled/default && \
    sed -i 's/user .*;/user root;/' /etc/nginx/nginx.conf && \
    sed -i '/^include/i include /etc/nginx/main.d/*.conf;' /etc/nginx/nginx.conf && \
    sed -i 's/access_log\s.*;/access_log \/dev\/stdout main;/' /etc/nginx/nginx.conf && \
    sed -i 's/error_log\s.*;/error_log \/dev\/stderr info;/' /etc/nginx/nginx.conf && \
    sed -i "/access_log/i\ \n\tlog_format main '\$http_fly_client_ip - \$remote_user [\$time_local] "\$request" '\n\t'\$status \$body_bytes_sent \"\$http_referer\" \"\$http_user_agent\"';" /etc/nginx/nginx.conf && \
    mkdir /etc/nginx/main.d && \
    echo 'env RAILS_MASTER_KEY;' >> /etc/nginx/main.d/env.conf &&\
    echo 'env RAILS_LOG_TO_STDOUT;' >> /etc/nginx/main.d/env.conf
RUN mkdir /var/run/passenger-instreg

RUN mkdir /root/.ssh && \
    echo ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8yIJ1gPtLXWSTH5bJXk+5VaO8QlvQ5KBdMvY1yzqBf8OI23rBI1j9yrXL175FDHCCTI80tx8DVsvegA2pdh2oYX4pyYpSpy01d0dQJrDuBHA1ii9+bIqP6gq4TPajZi97nXtKnjIh2sfGXSxwzkNC3J5MX6xXeDvCFGFDWDVaTJhg6PGP/D5FfkKqWMIzztvwvGsXcNg4oyzYQlDQWr5QLDK+9BmY/JgROArC/Feo3y8M8n/u2lpLGgAb21RgdJhcjT8qCuqtKtFIolM9MPQmU5s7YtSsTsXLHB1midVouta/VCK+4DdFkdapsDbj+LsPST1AEhN9pMrtotXUSFJR rubys@rubixb > /root/.ssh/authorized_keys

# Deploy your application
COPY . .

# Adjust binstubs to run on Linux and set current working directory
# RUN chmod +x /app/bin/* && \
#     sed -i 's/ruby.exe/ruby/' /app/bin/* && \
#     sed -i '/^#!/aDir.chdir File.expand_path("..", __dir__)' /app/bin/*

# The following enable assets to precompile on the build server.  Adjust
# as necessary.  If no combination works for you, see:
# https://fly.io/docs/rails/getting-started/existing/#access-to-environment-variables-at-build-time
ENV SECRET_KEY_BASE 1
# ENV AWS_ACCESS_KEY_ID=1
# ENV AWS_SECRET_ACCESS_KEY=1

# Run build task defined in lib/tasks/fly.rake
ARG BUILD_COMMAND="bin/rails fly:build"
RUN ${BUILD_COMMAND}

# Default server start instructions.  Generally Overridden by fly.toml.
ENV PORT 8080
ENV RAILS_LOG_TO_STDOUT true
ARG SERVER_COMMAND="bin/rails fly:server"
ENV SERVER_COMMAND ${SERVER_COMMAND}
CMD ${SERVER_COMMAND}
