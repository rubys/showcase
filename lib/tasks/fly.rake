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
end
