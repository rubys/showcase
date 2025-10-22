require "test_helper"

class OfflinePlaylistJobTest < ActiveJob::TestCase
  test "generates valid ZIP file with rubyzip 3.x" do
    # Create a minimal test event
    event = events(:one)

    # Test the core ZIP generation logic matches our app's usage pattern
    require 'zip'
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, "test-playlist.zip")

      # Replicate the exact pattern used in OfflinePlaylistJob#generate_zip_file
      Zip::OutputStream.open(zip_path) do |zip|
        zip.put_next_entry("test.html")
        zip.write("<html><body>Test content</body></html>")

        zip.put_next_entry("README.txt")
        zip.write("Test README")
      end

      # Verify ZIP was created and is readable
      assert File.exist?(zip_path), "ZIP file should be created"
      assert File.size(zip_path) > 0, "ZIP file should not be empty"

      # Verify ZIP contents are readable (ensures rubyzip 3.x compatibility)
      Zip::File.open(zip_path) do |zip_file|
        assert_equal 2, zip_file.size, "ZIP should contain 2 entries"

        html_entry = zip_file.find_entry("test.html")
        assert_not_nil html_entry, "Should find test.html entry"
        assert_includes html_entry.get_input_stream.read, "Test content"

        readme_entry = zip_file.find_entry("README.txt")
        assert_not_nil readme_entry, "Should find README.txt entry"
        assert_equal "Test README", readme_entry.get_input_stream.read
      end
    end
  end
end
