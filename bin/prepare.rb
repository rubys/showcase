#!/usr/bin/env ruby

require "bundler/setup"
require 'sqlite3'
require 'aws-sdk-s3'
require 'json'
require 'yaml'
require 'fileutils'
require 'etc'

require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.on('--verbose', 'Enable verbose output') do
    options[:verbose] = true
  end
end.parse!(ARGV)

migrations = Dir["db/migrate/2*"].map {|name| name[/\d+/]}

git_path = File.realpath(File.expand_path('..', __dir__))
inventory_path = "#{git_path}/tmp/inventory"
inventory_path = File.expand_path("inventory", File.dirname(ENV['RAILS_DB_VOLUME'])) if ENV['RAILS_DB_VOLUME']

inventory = {}
Dir["#{inventory_path}/*.json"].each do |file|
  inventory.merge! JSON.parse(File.read(file)) rescue nil
end

# Check for required S3 environment variables
required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }
s3_client = nil
if missing_env.empty? && ENV["RAILS_ENV"] == "production" && ENV['FLY_APP_NAME']
  # Initialize S3 client
  s3_client = Aws::S3::Client.new(
    region: ENV['AWS_REGION'] || 'auto',
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
    endpoint: ENV['AWS_ENDPOINT_URL_S3'],
    force_path_style: true
  )

  bucket_name = ENV.fetch('BUCKET_NAME', 'showcase')
end

# Get rails user/group IDs once for file ownership changes
rails_uid = nil
rails_gid = nil
log_volume = nil
if ENV['FLY_REGION']
  begin
    rails_uid = Etc.getpwnam('rails').uid
    rails_gid = Etc.getgrnam('rails').gid
    log_volume = ENV['RAILS_LOG_VOLUME'] || '/data/log'
  rescue ArgumentError => e
    # rails user/group doesn't exist (e.g., in development)
    puts "Warning: Could not get rails user/group: #{e.message}"
  end
end

ARGV.each do |database|
  db_name = File.basename(database)
  lock_file = database.sub('.sqlite3', '.lock')

  File.open(lock_file, 'w') do |file|
    if file.flock(File::LOCK_EX)
      # download from s3 if s3 is newer
      if s3_client 
        begin                                        
          # Extract the mtime from inventory
          if inventory && inventory[db_name] && inventory[db_name]['last_modified']
            actual_mtime = Time.parse(inventory[db_name]['last_modified'])
          else
            actual_mtime = nil
          end
          
          local_mtime = File.exist?(database) ? File.mtime(database) : nil

          if !local_mtime || (actual_mtime && actual_mtime.to_i > local_mtime.to_i) || File.size(database) == 0
            # Try to download from S3
            response = s3_client.get_object(bucket: bucket_name, key: "db/#{db_name}")

            # Set the mtime on the file
            if !actual_mtime && response.last_modified
              actual_mtime = response.last_modified
            end

            # Write the database file
            File.open(database, 'wb') do |db_file|
              db_file.write(response.body.read)
              File.utime(actual_mtime, actual_mtime, database) if actual_mtime
            end

            puts "Downloaded #{db_name} from S3"

            # avoid throttling
            sleep 1 if ENV['FLY_REGION'] && ARGV.length > 1
          elsif options[:verbose]
            puts "Local database #{db_name} is up to date"
          end
          
        rescue Aws::S3::Errors::NoSuchKey
          puts "Database #{db_name} not found in S3"
        rescue => e
          puts "Error downloading #{db_name} from S3: #{e.message}"
        end
      else
        puts "S3 environment variables not configured, skipping S3 download"
      end

      # determine which migrations have already been applied
      applied = []
      if File.exist?(database) and File.size(database) > 0
        begin
          db = SQLite3::Database.new(database)
          applied = db.execute("SELECT version FROM schema_migrations").flatten
        rescue
        ensure
          db.close if db
        end
      end

      # only run migrations if there are new ones to apply
      unless (migrations - applied).empty?
        ENV['DATABASE_URL'] = "sqlite3://#{File.realpath(database) rescue database}"

        # only run migrations in one place - fly.io; rely on rsync to update others
        system 'bin/rails db:prepare'

        # not sure why this is needed...
        count = `sqlite3 #{database} "select count(*) from events"`.to_i
        system 'bin/rails db:seed' if count == 0

        # avoid throttling
        sleep 1 if ENV['FLY_REGION'] && ARGV.length > 1
      end

      # Ensure database and log files are owned by rails user
      if rails_uid && rails_gid
        log_file = File.join(log_volume, db_name.sub('.sqlite3', '.log'))

        # Change ownership of database file if it exists
        if File.exist?(database)
          File.chown(rails_uid, rails_gid, database)
        end

        # Change ownership of log file if it exists
        if File.exist?(log_file)
          File.chown(rails_uid, rails_gid, log_file)
        end
      end

      file.flock(File::LOCK_UN)
    end
  end

  File.unlink(lock_file) if File.exist?(lock_file)
end