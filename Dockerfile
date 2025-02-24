# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.2
FROM ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT="1"

# Update gems and bundler
RUN gem update --system --no-document && \
    gem install -N bundler sentry-ruby

# Install packages needed to install passenger
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl gnupg && \
    curl https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key.txt | \
      gpg --dearmor > /etc/apt/trusted.gpg.d/phusion.gpg && \
    bash -c 'echo deb https://oss-binaries.phusionpassenger.com/apt/passenger $(source /etc/os-release; echo $VERSION_CODENAME) main > /etc/apt/sources.list.d/passenger.list' && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y curl gnupg passenger && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libyaml-dev pkg-config zlib1g-dev

# Install application gems
COPY --link Gemfile Gemfile.lock ./
RUN bundle install && \
    bundle exec bootsnap precompile --gemfile && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Compile passenger native support
RUN passenger-config build-native-support

# Copy application code
COPY --link . .

# Install esbuild
RUN chdir /usr/local/bin && \
    curl -fsSL https://esbuild.github.io/dl/latest | sh


# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE=DUMMY ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl dnsutils libnginx-mod-http-passenger nginx openssh-server poppler-utils procps redis-server rsync ruby-foreman sqlite3 sudo vim unzip && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# configure nginx and passenger
COPY <<-'EOF' /etc/nginx/sites-enabled/default
server {
    listen 3000;
    root /rails/public;
    passenger_enabled on;
}
EOF
RUN echo "daemon off;" >> /etc/nginx/nginx.conf && \
    sed -i 's/access_log\s.*;/access_log stdout;/' /etc/nginx/nginx.conf && \
    sed -i 's/error_log\s.*;/error_log stderr info;/' /etc/nginx/nginx.conf && \
    sed -i 's/user www-data/user rails/' /etc/nginx/nginx.conf && \
    mkdir /var/run/passenger-instreg

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Copy in rclone binary
COPY --from=rclone/rclone:latest /usr/local/bin/rclone /usr/local/bin/rclone

# Copy passenger native support
COPY --from=build /root/.passenger/native_support /root/.passenger/native_support

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
    mkdir /data && \
    chown -R rails:rails db log storage tmp /data

# configure redis
RUN sed -i 's/^daemonize yes/daemonize no/' /etc/redis/redis.conf &&\
  sed -i 's/^bind/# bind/' /etc/redis/redis.conf &&\
  sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf &&\
  sed -i 's/^logfile/# logfile/' /etc/redis/redis.conf &&\
  echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf

# configure sshd
RUN sed -i 's/^#\s*Port.*/Port 2222/' /etc/ssh/sshd_config && \
    sed -i 's/^#\s*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    mkdir /var/run/sshd && \
    chmod 0755 /var/run/sshd

# Authorize rails user to run passenger-status
COPY <<-"EOF" /etc/sudoers.d/rails
rails ALL=(root) NOPASSWD: /usr/sbin/passenger-status
EOF

# configure rsync
COPY <<-"EOF" /etc/rsyncd.conf
lock file = /var/run/rsync.lock
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid

[data]
  path = /data
  comment = Showcase data
  uid = rails
  gid = rails
  read only = no
  hosts allow = *
  list = yes

[ssh]
  path = /data/.ssh
  comment = Ssh config
  uid = root
  gid = root
  read only = no
  hosts allow = *
  list = yes
EOF

# Prep demo
RUN SECRET_KEY_BASE=DUMMY RAILS_APP_DB=demo bin/rails db:prepare

# Deployment options
ENV DATABASE_URL="sqlite3:///data/production.sqlite3" \
    RAILS_DB_VOLUME="/data/db" \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_LOG_VOLUME="/data/log" \
    RAILS_SERVE_STATIC_FILES="true" \
    RAILS_STORAGE="/data/storage"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
VOLUME /data
CMD ["foreman", "start", "--procfile=Procfile.kamal"]
