# Map download/upload utilities for S3 and local file operations
# Used by nav_initialization.rb and update_configuration.rb
require 'fileutils'

module MapDownloader
  MAP_FILES = %w[_usmap _eumap _aumap _jpmap].freeze

  # Main entry point - auto-detects environment and downloads accordingly
  def self.download(rails_root: '/rails', quiet: false)
    if s3_env_vars_present?
      # Fly.io: Download from S3
      download_from_s3(rails_root: rails_root, quiet: quiet)
    elsif Dir.exist?('/data/db')
      # Hetzner: Copy from /data/db (synced via webhook)
      copy_from_data_db(rails_root: rails_root, quiet: quiet)
    else
      # Rubix or fallback: Do nothing, use git-tracked files
      { downloaded: [], skipped: MAP_FILES.map { |f| "#{f} (using git fallback)" } }
    end
  end

  def self.s3_env_vars_present?
    %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3].all? { |var| ENV[var] }
  end

  def self.download_from_s3(rails_root:, quiet: false)
    require 'aws-sdk-s3'

    downloaded = []
    skipped = []

    s3_client = Aws::S3::Client.new(
      region: 'auto',
      endpoint: ENV['AWS_ENDPOINT_URL_S3'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )

    bucket = ENV.fetch('AWS_S3_BUCKET', 'showcase')

    MAP_FILES.each do |map_name|
      s3_key = "views/event/#{map_name}.html.erb"
      local_path = File.join(rails_root, 'app/views/event', "#{map_name}.html.erb")

      begin
        # Get S3 object metadata to check if it exists and get mtime
        head_response = s3_client.head_object(bucket: bucket, key: s3_key)
        s3_mtime = head_response.last_modified

        local_mtime = File.exist?(local_path) ? File.mtime(local_path) : Time.at(0)

        if s3_mtime > local_mtime
          # Ensure directory exists
          FileUtils.mkdir_p(File.dirname(local_path))

          # Download from S3
          s3_client.get_object(
            bucket: bucket,
            key: s3_key,
            response_target: local_path
          )
          downloaded << map_name
        else
          skipped << "#{map_name} (already current)"
        end
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
        skipped << "#{map_name} (not in S3)"
      rescue => e
        puts "  ✗ Failed to download #{map_name}: #{e.message}" unless quiet
        skipped << "#{map_name} (error: #{e.message})"
      end
    end

    { downloaded: downloaded, skipped: skipped }
  end

  def self.copy_from_data_db(rails_root:, quiet: false)
    downloaded = []
    skipped = []

    MAP_FILES.each do |map_name|
      source_path = "/data/db/views/event/#{map_name}.html.erb"
      local_path = File.join(rails_root, 'app/views/event', "#{map_name}.html.erb")

      begin
        if File.exist?(source_path)
          source_mtime = File.mtime(source_path)
          local_mtime = File.exist?(local_path) ? File.mtime(local_path) : Time.at(0)

          if source_mtime > local_mtime
            # Ensure directory exists
            FileUtils.mkdir_p(File.dirname(local_path))
            FileUtils.cp(source_path, local_path)
            downloaded << map_name
          else
            skipped << "#{map_name} (already current)"
          end
        else
          skipped << "#{map_name} (not in /data/db)"
        end
      rescue => e
        puts "  ✗ Failed to copy #{map_name}: #{e.message}" unless quiet
        skipped << "#{map_name} (error: #{e.message})"
      end
    end

    { downloaded: downloaded, skipped: skipped }
  end

  # Returns paths for all map ERB files relative to rails_root
  def self.erb_paths(rails_root: Dir.pwd)
    MAP_FILES.map { |name| File.join(rails_root, 'app/views/event', "#{name}.html.erb") }
  end
end
