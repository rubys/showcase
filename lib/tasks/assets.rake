require 'aws-sdk-s3'
require 'fileutils'
require 'rack/mime'

namespace :assets do
  desc "Bridge assets between S3 and local public/assets directory"
  task :bridge do
    # Check for required S3 environment variables
    required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
    missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }
    
    if !missing_env.empty?
      puts "Missing required environment variables: #{missing_env.join(', ')}"
      puts "Exiting assets:bridge task"
      exit 0
    end

    # Initialize S3 client
    s3_client = Aws::S3::Client.new(
      region: ENV['AWS_REGION'] || 'auto',
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      endpoint: ENV['AWS_ENDPOINT_URL_S3'],
      force_path_style: true
    )

    bucket_name = ENV.fetch('BUCKET_NAME', 'showcase')
    
    begin
      # Verify bucket exists
      s3_client.head_bucket(bucket: bucket_name)
    rescue Aws::S3::Errors::NotFound
      puts "Bucket '#{bucket_name}' does not exist"
      exit 1
    rescue => e
      puts "Error accessing bucket: #{e.message}"
      exit 1
    end

    # Get all objects in S3 assets/ directory using pagination
    s3_objects = {}
    continuation_token = nil
    
    loop do
      params = {
        bucket: bucket_name,
        prefix: 'assets/',
        max_keys: 1000
      }
      params[:continuation_token] = continuation_token if continuation_token
      
      response = s3_client.list_objects_v2(params)
      
      response.contents.each do |object|
        # Remove 'assets/' prefix to get relative path
        relative_path = object.key.sub(/^assets\//, '')
        s3_objects[relative_path] = object.last_modified
      end
      
      break unless response.is_truncated
      continuation_token = response.next_continuation_token
    end

    # Get local assets directory contents
    assets_dir = Rails.root.join('public', 'assets')
    FileUtils.mkdir_p(assets_dir) unless Dir.exist?(assets_dir)
    
    local_files = {}
    Dir.glob("#{assets_dir}/**/*", File::FNM_DOTMATCH).each do |file|
      next unless File.file?(file)
      
      relative_path = Pathname.new(file).relative_path_from(assets_dir).to_s
      local_files[relative_path] = {
        last_modified: File.mtime(file),
        size: File.size(file)
      }
    end

    puts "Found #{s3_objects.size} objects in S3 and #{local_files.size} local files"

    one_week_ago = Time.now - (7 * 24 * 60 * 60)
    three_days_ago = Time.now - (3 * 24 * 60 * 60)

    # Process files that are only in S3
    (s3_objects.keys - local_files.keys).each do |file_path|
      s3_mtime = s3_objects[file_path]
      
      if s3_mtime < one_week_ago
        # Delete old file from S3
        puts "Deleting old file from S3: #{file_path}"
        s3_client.delete_object(bucket: bucket_name, key: "assets/#{file_path}")
      else
        # Download file to local directory
        puts "Downloading from S3: #{file_path}"
        local_file_path = assets_dir.join(file_path)
        FileUtils.mkdir_p(File.dirname(local_file_path))
        
        s3_client.get_object(
          bucket: bucket_name,
          key: "assets/#{file_path}",
          response_target: local_file_path.to_s
        )
        
        # Set the local file's mtime to match S3
        File.utime(s3_mtime, s3_mtime, local_file_path)
      end
    end

    # Process files that are only in local directory
    (local_files.keys - s3_objects.keys).each do |file_path|
      puts "Uploading to S3: #{file_path}"
      local_file_path = assets_dir.join(file_path)
      
      s3_client.put_object(
        bucket: bucket_name,
        key: "assets/#{file_path}",
        body: File.read(local_file_path),
        content_type: Rack::Mime.mime_type(File.extname(file_path))
      )
    end

    # Process files that exist in both locations
    (s3_objects.keys & local_files.keys).each do |file_path|
      s3_mtime = s3_objects[file_path]
      local_mtime = local_files[file_path][:last_modified]
      
      # If file hasn't been modified in more than 3 days, update timestamp with server-side copy
      if [s3_mtime, local_mtime].max < three_days_ago
        puts "Updating timestamp for: #{file_path}"
        s3_client.copy_object(
          bucket: bucket_name,
          copy_source: "#{bucket_name}/assets/#{file_path}",
          key: "assets/#{file_path}",
          metadata_directive: 'REPLACE'
        )
      end
    end

    puts "Assets bridge synchronization complete"
  end
end