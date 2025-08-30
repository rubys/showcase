#!/usr/bin/env ruby

require "bundler/setup"
require 'sqlite3'
require 'aws-sdk-s3'
require 'json'
require 'yaml'
require 'fileutils'

migrations = Dir["db/migrate/2*"].map {|name| name[/\d+/]}

# Check for required S3 environment variables
required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }
s3_client = nil
if missing_env.empty? && Rails.env.production?
  # Initialize S3 client
  s3_client = Aws::S3::Client.new(
    region: ENV['AWS_REGION'] || 'auto',
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
    endpoint: ENV['AWS_ENDPOINT_URL_S3'],
    force_path_style: true
  )
end

ARGV.each do |database|
  lock_file = database.sub('.sqlite3', '.lock')
  applied = []

  File.open(lock_file, 'w') do |file|
    if file.flock(File::LOCK_EX)
      if s3_client 
        # Check if database is up to date, if not fetch from S3; skip if FLY_APP_NAME is smooth and database exists
        if !(File.exist?(database) && File.size(database) > 0) || (ENV['FLY_APP_NAME'] && ENV['FLY_APP_NAME'] != 'smooth')
          begin            
            bucket_name = ENV.fetch('BUCKET_NAME', 'showcase')
            db_name = File.basename(database)
            s3_key = "db/#{db_name}"
            
            # Try to download from S3
            begin
              response = s3_client.get_object(bucket: bucket_name, key: s3_key)
              
              # Load showcases to determine region
              git_path = File.realpath(File.expand_path('..', __dir__))
              showcases = YAML.load_file("#{git_path}/config/tenant/showcases.yml")
              tenant_name = db_name.sub(/\.sqlite3$/, '')
              owner_region = nil
              
              # Determine the region for this database
              if tenant_name == "index"
                owner_region = "index"
              else
                showcases.each do |year, list|
                  list.each do |token, info|
                    if info[:events]
                      info[:events].each do |subtoken, subinfo|
                        label = "#{year}-#{token}-#{subtoken}"
                        if label == tenant_name
                          owner_region = info[:region] || 'index'
                          break
                        end
                      end
                    else
                      label = "#{year}-#{token}"
                      if label == tenant_name
                        owner_region = info[:region] || 'index'
                        break
                      end
                    end
                    break if owner_region
                  end
                  break if owner_region
                end
              end
              
              owner_region ||= 'index'
              
              # Determine inventory path
              dbpath = File.dirname(database)
              inventory_path = "#{git_path}/tmp/inventory"
              inventory_path = File.expand_path("inventory", File.dirname(dbpath)) if ENV['RAILS_DB_VOLUME']
              FileUtils.mkdir_p(inventory_path)
              
              # Try to load inventory from disk first, fetch from S3 if not present
              inventory_file = "#{inventory_path}/#{owner_region}.json"
              inventory = nil
              
              if File.exist?(inventory_file)
                # Load from disk
                inventory = JSON.parse(File.read(inventory_file))
              else
                # Fetch from S3 and save to disk
                begin
                  inventory_key = "inventory/#{owner_region}.json"
                  inventory_response = s3_client.get_object(bucket: bucket_name, key: inventory_key)
                  inventory = JSON.parse(inventory_response.body.read)
                  
                  # Write to disk for future use
                  File.write(inventory_file, JSON.pretty_generate(inventory))
                  File.utime(inventory_response.last_modified, inventory_response.last_modified, inventory_file)
                rescue Aws::S3::Errors::NoSuchKey
                  # Inventory doesn't exist yet
                rescue => e
                  puts "Error loading inventory from S3: #{e.message}"
                end
              end

              # Get the actual last_modified from inventory
              actual_mtime = nil
              
              # Extract the mtime from inventory
              if inventory && inventory[db_name] && inventory[db_name]['last_modified']
                actual_mtime = Time.parse(inventory[db_name]['last_modified'])
              end
              
              # Set the mtime on the file
              if !actual_mtime && response.last_modified
                actual_mtime = response.last_modified
              end

              local_time = File.exist?(database) ? File.mtime(database) : nil

              if !local_time || (actual_mtime && actual_mtime > local_time)
                # Write the database file
                File.open(database, 'wb') do |db_file|
                  db_file.write(response.body.read)
                  File.utime(actual_mtime, actual_mtime, database) if actual_mtime
                end
              end
              
              puts "Downloaded #{db_name} from S3"
              
            rescue Aws::S3::Errors::NoSuchKey
              puts "Database #{db_name} not found in S3"
            rescue => e
              puts "Error downloading #{db_name} from S3: #{e.message}"
            end
          rescue => e
            puts "Error initializing S3 client: #{e.message}"
          end
        end
      else
        puts "S3 environment variables not configured, skipping S3 download"
      end
      
      if File.exist?(database) and File.size(database) > 0
        begin
          db = SQLite3::Database.new(database)
          applied = db.execute("SELECT version FROM schema_migrations").flatten
        rescue
        ensure
          db.close if db
        end
      end

      unless (migrations - applied).empty?
        ENV['DATABASE_URL'] = "sqlite3://#{File.realpath(database)}"

        # only run migrations in one place - fly.io; rely on rsync to update others
        system 'bin/rails db:prepare'

        # not sure why this is needed...
        count = `sqlite3 #{database} "select count(*) from events"`.to_i
        system 'bin/rails db:seed' if count == 0

        # avoid throttling
        sleep 1 if ENV['FLY_REGION']
      end

      file.flock(File::LOCK_UN)
    end
  end

  File.unlink(lock_file) if File.exist?(lock_file)
end

s3_client.close if s3_client