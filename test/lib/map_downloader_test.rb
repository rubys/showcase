require "test_helper"
require "map_downloader"

class MapDownloaderTest < ActiveSupport::TestCase
  test "MAP_FILES contains all four map regions" do
    assert_equal %w[_usmap _eumap _aumap _jpmap], MapDownloader::MAP_FILES
  end

  test "erb_paths returns correct paths" do
    paths = MapDownloader.erb_paths(rails_root: '/rails')

    assert_equal 4, paths.length
    assert paths.all? { |p| p.start_with?('/rails/app/views/event/') }
    assert paths.all? { |p| p.end_with?('.html.erb') }
  end

  test "s3_env_vars_present? returns false when vars missing" do
    # Clear any existing env vars
    original_values = {}
    %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3].each do |var|
      original_values[var] = ENV[var]
      ENV.delete(var)
    end

    assert_not MapDownloader.s3_env_vars_present?

    # Restore
    original_values.each { |k, v| ENV[k] = v if v }
  end

  test "s3_env_vars_present? returns true when all vars set" do
    # Save and set
    original_values = {}
    %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3].each do |var|
      original_values[var] = ENV[var]
      ENV[var] = 'test_value'
    end

    assert MapDownloader.s3_env_vars_present?

    # Restore
    original_values.each do |k, v|
      if v
        ENV[k] = v
      else
        ENV.delete(k)
      end
    end
  end

  test "download returns git fallback when no S3 and no /data/db" do
    # Clear S3 env vars
    original_values = {}
    %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3].each do |var|
      original_values[var] = ENV[var]
      ENV.delete(var)
    end

    # This should return the fallback since /data/db doesn't exist on dev machine
    result = MapDownloader.download(rails_root: Rails.root.to_s)

    assert_equal [], result[:downloaded]
    assert result[:skipped].all? { |s| s.include?('git fallback') }

    # Restore
    original_values.each { |k, v| ENV[k] = v if v }
  end
end
