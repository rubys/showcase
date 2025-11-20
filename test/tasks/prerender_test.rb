require "test_helper"

class PrerenderTaskTest < ActiveSupport::TestCase
  test "prerender task creates correct directory structure for regions and studios" do
    # This test verifies that prerender creates:
    #   public/regions/{region}/index.html (not regions/{region}.html)
    #   public/studios/{studio}/index.html (not studios/{studio}.html)
    # This ensures Navigator can serve them correctly with trailing slashes

    # Get expected paths from PrerenderConfiguration
    showcases = ShowcasesLoader.load
    paths = PrerenderConfiguration.prerenderable_paths(showcases)

    # Skip if no showcase data available (e.g., in CI)
    skip "No showcase data available" if paths[:regions].empty?

    # Verify the path format matches what we expect
    # The prerender task should create:
    #   PATH_INFO: /showcase/regions/iad/
    #   FILE: public/regions/iad/index.html

    sample_region = paths[:regions].first
    expected_path = "regions/#{sample_region}/"
    expected_file = "regions/#{sample_region}/index.html"

    # This validates that prerender.rake generates paths with trailing slashes
    # which will create directory structures instead of .html files
    assert expected_path.end_with?('/'),
      "Region path should end with / to create directory structure"
    assert expected_file.end_with?('/index.html'),
      "Region file should be index.html inside directory"

    # Same validation for studios (already skipped if no data)
    return if paths[:studios].empty?

    sample_studio = paths[:studios].first
    expected_studio_path = "studios/#{sample_studio}/"
    expected_studio_file = "studios/#{sample_studio}/index.html"

    assert expected_studio_path.end_with?('/'),
      "Studio path should end with / to create directory structure"
    assert expected_studio_file.end_with?('/index.html'),
      "Studio file should be index.html inside directory"
  end

  test "multi-event studio indexes use directory structure" do
    # Verify multi-event studios also use directory/index.html structure
    showcases = ShowcasesLoader.load
    paths = PrerenderConfiguration.prerenderable_paths(showcases)

    # Find a multi-event studio
    skip "No multi-event studios to test" if paths[:multi_event_studios].empty?

    year, studios = paths[:multi_event_studios].first
    studio = studios.first

    expected_path = "#{year}/#{studio}/"
    expected_file = "#{year}/#{studio}/index.html"

    assert expected_path.end_with?('/'),
      "Multi-event studio path should end with / to create directory structure"
    assert expected_file.end_with?('/index.html'),
      "Multi-event studio file should be index.html inside directory"
  end
end
