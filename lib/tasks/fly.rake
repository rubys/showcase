# commands used to deploy a Rails application
namespace :fly do
  # BUILD step:
  #  - changes to the filesystem made here DO get deployed
  #  - NO access to secrets, volumes, databases
  #  - Failures here prevent deployment
  task :build => 'assets:precompile'

  # RELEASE step:
  #  - changes to the filesystem made here are DISCARDED
  #  - full access to secrets, databases
  #  - failures here prevent deployment
  task :release

  # SERVER step:
  #  - changes to the filesystem made here are deployed
  #  - full access to secrets, databases
  #  - failures here result in VM being stated, shutdown, and rolled back
  #    to last successful deploy (if any).
  task :server => %i(swapfile tenants dbus) do
    Bundler.with_original_env do
      sh "foreman start --procfile=Procfile.fly"
    end
  end

  # optional SWAPFILE task:
  #  - adjust fallocate size as needed
  #  - performance critical applications should scale memory to the
  #    point where swap is rarely used.  'fly scale help' for details.
  #  - disable by removing dependency on the :server task, thus:
  #        task :server => 'db:migrate' do
  task :swapfile do
    sh 'fallocate -l 1024M /swapfile'
    sh 'chmod 0600 /swapfile'
    sh 'mkswap /swapfile'
    sh 'echo 10 > /proc/sys/vm/swappiness'
    sh 'swapon /swapfile'
    sh 'echo 1 > /proc/sys/vm/overcommit_memory'
  end

  # set up regional databases and storage
  task :tenants do
    ENV['RAILS_DB_VOLUME'] = "/mnt/volume/db"
    mkdir_p ENV['RAILS_DB_VOLUME']

    ENV['RAILS_STORAGE'] = '/mnt/volume/storage'
    mkdir_p ENV['RAILS_STORAGE']

    if not File.exist? "#{ENV['RAILS_DB_VOLUME']}/htpasswd"
      sh "htpasswd -b -c #{ENV['RAILS_DB_VOLUME']}/htpasswd bootstrap password"
    end

    ruby 'config/tenant/nginx-config.rb'
  end

  # needed for chrome
  task :dbus do
    mkdir_p '/var/run/dbus'
    sh 'dbus-daemon --system'
  end

  task :build_deps do
    build_packages = %w{git build-essential wget curl gzip xz-utils libsqlite3-dev zlib1g-dev}

    sh 'apt-get update -qq'
    sh "apt-get install --no-install-recommends -y #{build_packages.join(' ')}"
  end

  task :install do
    # add passenger repository
    sh 'apt-get install -y dirmngr gnupg apt-transport-https ca-certificates curl'
    sh 'curl https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key.txt | gpg --dearmor > /etc/apt/trusted.gpg.d/phusion.gpg'
    sh 'echo deb https://oss-binaries.phusionpassenger.com/apt/passenger bullseye main > /etc/apt/sources.list.d/passenger.list'

    # add google chrome repository
    sh 'curl https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -'
    sh 'echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'

    deploy_packages=%w(file vim curl gzip nginx passenger libnginx-mod-http-passenger sqlite3 libsqlite3-0 google-chrome-stable ruby-foreman redis-server apache2-utils openssh-client rsync)
    sh 'apt-get update -qq'
    sh "apt-get install --no-install-recommends -y #{deploy_packages.join(' ')}"

    # configure redis
    sh "sed -i 's/^daemonize yes/daemonize no/' /etc/redis/redis.conf"
    sh "sed -i 's/^bind/# bind/' /etc/redis/redis.conf"
    sh "sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf"
    sh "sed -i 's/^logfile/# logfile/' /etc/redis/redis.conf"

    # configure nginx/passenger
    rm '/etc/nginx/sites-enabled/default'
    conf = IO.read('/etc/nginx/nginx.conf')
    conf.sub! /user .*;/, 'user root;'
    conf[/^()include/, 1] = "include /etc/nginx/main.d/*.conf;\n"
    conf.sub! /access_log\s.*;/, 'access_log /dev/stdout main;'
    conf.sub! /error_log\s.*;/, 'error_log /dev/stderr info;'
    conf[/^()\s*access_log/, 1] = "\tlog_format main '$http_fly_client_ip - $remote_user [$time_local] \"$request\"\n\t$status $body_bytes_sent \"$http_referer\" \"$http_user_agent\"';\n"
    IO.write('/etc/nginx/nginx.conf', conf)

    mkdir_p '/etc/nginx/main.d'
    open '/etc/nginx/main.d/env.conf', 'w' do |conf|
      conf.puts 'env RAILS_MASTER_KEY;'
      conf.puts 'env RAILS_LOG_TO_STDOUT;'
    end

  end
end
