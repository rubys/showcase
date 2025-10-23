require "test_helper"

# Integration tests to ensure prerender.rake and configurator.rb stay in sync.
# These tests verify that:
# 1. Pages that ARE prerendered are marked as public (no auth)
# 2. Pages that ARE prerendered are excluded from fly-replay
# 3. Pages that are NOT prerendered require auth and trigger fly-replay
# 4. Region index pages are prerendered and excluded from fly-replay
class PrerenderConfigurationSyncTest < ActiveSupport::TestCase
  include Configurator

  setup do
    @showcases = YAML.load_file(Rails.root.join('config/tenant/showcases.yml'))
    @root = '/showcase'
  end

  # ===== STUDIO INDEX PAGE TESTS =====

  test "prerendered studio indexes match auth patterns for public access" do
    # Get studios that ARE prerendered (have :events)
    prerendered_studios = collect_prerendered_studios

    # Build auth config and extract patterns
    auth_config = build_auth_config
    auth_patterns = auth_config['auth_patterns']

    # Verify each prerendered studio has a public auth pattern
    prerendered_studios.each do |year, tokens|
      tokens.each do |token|
        path = "#{@root}/#{year}/#{token}/"

        # Check if path matches any public auth pattern
        is_public = auth_patterns.any? do |pattern|
          pattern['action'] == 'off' && path =~ Regexp.new(pattern['pattern'])
        end

        assert is_public,
          "Prerendered studio index #{path} should be public but no auth pattern matches. " \
          "This means prerender.rake includes #{year}/#{token}/ but configurator.rb doesn't mark it public."
      end
    end
  end

  test "non-prerendered studio pages require authentication" do
    # Get studios that are NOT prerendered (no :events)
    non_prerendered = collect_non_prerendered_studios

    skip "No non-prerendered studios to test" if non_prerendered.empty?

    # Build auth config
    auth_config = build_auth_config
    auth_patterns = auth_config['auth_patterns']
    public_paths = auth_config['public_paths']

    # Verify non-prerendered studios do NOT match public patterns
    non_prerendered.each do |studio|
      path = "#{@root}/#{studio[:year]}/#{studio[:token]}/"

      # Check if path matches any public auth pattern
      is_public = auth_patterns.any? do |pattern|
        pattern['action'] == 'off' && path =~ Regexp.new(pattern['pattern'])
      end

      # Also check public_paths (though these are usually prefixes)
      is_public ||= public_paths.any? { |pp| path.start_with?(pp) }

      assert_not is_public,
        "Non-prerendered studio #{path} should require auth but matches public pattern. " \
        "Studios without :events should NOT be public."
    end
  end

  test "prerendered studio indexes excluded from fly-replay" do
    # Get studios that ARE prerendered with regions
    prerendered_studios = collect_prerendered_studios_with_regions

    skip "No cross-region prerendered studios to test" if prerendered_studios.empty?

    # Build routes config
    ENV['FLY_APP_NAME'] = 'test-app'
    ENV['FLY_REGION'] = 'dfw'
    routes = build_routes_config
    ENV.delete('FLY_APP_NAME')
    ENV.delete('FLY_REGION')

    replay_rules = routes.dig('fly', 'replay') || []

    # Verify prerendered studio index pages don't match fly-replay patterns
    prerendered_studios.each do |studio|
      # Only test studios in different regions
      next if studio[:region] == 'dfw'

      path = "#{@root}/#{studio[:year]}/#{studio[:token]}/"

      # Should NOT match any fly-replay rule
      matches_replay = replay_rules.any? do |rule|
        path =~ Regexp.new(rule['path'])
      end

      assert_not matches_replay,
        "Prerendered studio index #{path} should NOT trigger fly-replay but pattern matches. " \
        "This means the fly-replay pattern is too broad and will cause unnecessary cross-region routing."
    end
  end

  test "prerendered studio sub-paths trigger fly-replay to correct region" do
    # Get studios that ARE prerendered with regions
    prerendered_studios = collect_prerendered_studios_with_regions

    skip "No cross-region prerendered studios to test" if prerendered_studios.empty?

    # Build routes config
    ENV['FLY_APP_NAME'] = 'test-app'
    ENV['FLY_REGION'] = 'dfw'
    routes = build_routes_config
    ENV.delete('FLY_APP_NAME')
    ENV.delete('FLY_REGION')

    replay_rules = routes.dig('fly', 'replay') || []

    # Verify sub-paths DO trigger fly-replay
    prerendered_studios.each do |studio|
      next if studio[:region] == 'dfw'

      # Test sub-paths (these are tenant URLs with events)
      studio[:events].each do |event_token, _event_info|
        path = "#{@root}/#{studio[:year]}/#{studio[:token]}/#{event_token}/"

        # Should match fly-replay rule for the correct region
        matching_rule = replay_rules.find do |rule|
          path =~ Regexp.new(rule['path'])
        end

        assert matching_rule,
          "Studio sub-path #{path} should trigger fly-replay but no pattern matches"

        assert_equal studio[:region], matching_rule['region'],
          "Studio sub-path #{path} should fly-replay to #{studio[:region]} but rule sends to #{matching_rule['region']}"
      end
    end
  end

  test "non-prerendered studio pages trigger fly-replay" do
    # Get studios WITHOUT :events (not prerendered) in other regions
    non_prerendered = collect_non_prerendered_studios

    skip "No cross-region non-prerendered studios to test" if non_prerendered.empty?

    # Build routes config
    ENV['FLY_APP_NAME'] = 'test-app'
    ENV['FLY_REGION'] = 'dfw'
    routes = build_routes_config
    ENV.delete('FLY_APP_NAME')
    ENV.delete('FLY_REGION')

    replay_rules = routes.dig('fly', 'replay') || []

    # Verify non-prerendered studios DO match fly-replay
    non_prerendered.each do |studio|
      next if studio[:region] == 'dfw' || studio[:region].nil?

      path = "#{@root}/#{studio[:year]}/#{studio[:token]}/"

      matching_rule = replay_rules.find do |rule|
        path =~ Regexp.new(rule['path'])
      end

      assert matching_rule,
        "Non-prerendered studio #{path} should trigger fly-replay but no pattern matches"

      assert_equal studio[:region], matching_rule['region'],
        "Non-prerendered studio #{path} should fly-replay to #{studio[:region]} but rule sends to #{matching_rule['region']}"
    end
  end

  # ===== REGION INDEX PAGE TESTS =====

  test "region index pages are public" do
    regions = collect_regions

    # Build auth config
    auth_config = build_auth_config
    public_paths = auth_config['public_paths']

    # Verify regions/ is in public paths
    assert public_paths.include?("#{@root}/regions/"),
      "The #{@root}/regions/ path should be in public_paths for region index pages"
  end

  test "region index pages excluded from fly-replay" do
    regions = collect_regions

    skip "Need multiple regions to test" if regions.size < 2

    # Build routes config from a specific region
    ENV['FLY_APP_NAME'] = 'test-app'
    ENV['FLY_REGION'] = regions.first
    routes = build_routes_config
    ENV.delete('FLY_APP_NAME')
    ENV.delete('FLY_REGION')

    replay_rules = routes.dig('fly', 'replay') || []

    # Verify region index pages don't match fly-replay
    regions.each do |region|
      next if region == regions.first

      path = "#{@root}/regions/#{region}/"

      matches = replay_rules.any? { |rule| path =~ Regexp.new(rule['path']) }

      assert_not matches,
        "Region index #{path} should NOT trigger fly-replay but pattern matches. " \
        "Region index pages are prerendered and should be served locally."
    end
  end

  test "region sub-paths trigger fly-replay to correct region" do
    regions = collect_regions

    skip "Need multiple regions to test" if regions.size < 2

    # Build routes config from a specific region
    ENV['FLY_APP_NAME'] = 'test-app'
    ENV['FLY_REGION'] = regions.first
    routes = build_routes_config
    ENV.delete('FLY_APP_NAME')
    ENV.delete('FLY_REGION')

    replay_rules = routes.dig('fly', 'replay') || []

    # Verify region sub-paths DO trigger fly-replay
    regions.each do |region|
      next if region == regions.first

      test_paths = [
        "#{@root}/regions/#{region}/demo/",
        "#{@root}/regions/#{region}/anything"
      ]

      test_paths.each do |path|
        matching_rule = replay_rules.find { |rule| path =~ Regexp.new(rule['path']) }

        assert matching_rule,
          "Region sub-path #{path} should trigger fly-replay but no pattern matches"

        assert_equal region, matching_rule['region'],
          "Region sub-path #{path} should fly-replay to #{region} but rule sends to #{matching_rule['region']}"
      end
    end
  end

  # ===== CONSISTENCY TESTS =====

  test "all public studio indexes are prerendered" do
    # This is the reverse check: if configurator marks something public,
    # prerender should generate it

    # Get public studio patterns from configurator
    auth_config = build_auth_config
    auth_patterns = auth_config['auth_patterns']

    # Extract studio patterns
    studio_patterns = auth_patterns.select do |pattern|
      pattern['action'] == 'off' &&
      pattern['pattern'].include?('/(?:') # Grouped studio pattern
    end

    # Get prerendered studios
    prerendered = collect_prerendered_studios

    # For each public pattern, verify the studios are prerendered
    studio_patterns.each do |pattern|
      # Extract year from pattern like ^/showcase/2025/(?:boston|raleigh)/?$
      if pattern['pattern'] =~ %r{/(\d{4})/\(\?:([\w|]+)\)}
        year = $1.to_i
        tokens = $2.split('|')

        tokens.each do |token|
          assert prerendered[year]&.include?(token),
            "Studio #{year}/#{token}/ is marked public in configurator but not prerendered. " \
            "Either add :events to the studio or remove from public auth patterns."
        end
      end
    end
  end

  test "fly-replay exclusions match prerendered studio indexes" do
    # Verify that studios excluded from fly-replay are exactly the prerendered ones

    prerendered = collect_prerendered_studios_with_regions

    skip "No cross-region prerendered studios to test" if prerendered.empty?

    # Build routes from multiple regions to get all patterns
    ENV['FLY_APP_NAME'] = 'test-app'

    collect_regions.each do |test_region|
      ENV['FLY_REGION'] = test_region
      routes = build_routes_config
      replay_rules = routes.dig('fly', 'replay') || []

      # For studios in OTHER regions, check pattern
      prerendered.each do |studio|
        next if studio[:region] == test_region

        index_path = "#{@root}/#{studio[:year]}/#{studio[:token]}/"
        sub_path = "#{@root}/#{studio[:year]}/#{studio[:token]}/event1/"

        # Index should NOT match
        index_matches = replay_rules.any? { |rule| index_path =~ Regexp.new(rule['path']) }
        assert_not index_matches,
          "From region #{test_region}: prerendered index #{index_path} should not match fly-replay"

        # Sub-path SHOULD match
        sub_matches = replay_rules.any? { |rule| sub_path =~ Regexp.new(rule['path']) }
        assert sub_matches,
          "From region #{test_region}: studio sub-path #{sub_path} should match fly-replay"
      end
    end

    ENV.delete('FLY_APP_NAME')
    ENV.delete('FLY_REGION')
  end

  private

  def collect_prerendered_studios
    # Studios that ARE prerendered (have :events)
    prerendered = {}
    @showcases.each do |year, sites|
      sites.each do |token, info|
        if info[:events]
          prerendered[year] ||= []
          prerendered[year] << token
        end
      end
    end
    prerendered
  end

  def collect_prerendered_studios_with_regions
    # Studios that ARE prerendered with region info
    prerendered = []
    @showcases.each do |year, sites|
      sites.each do |token, info|
        if info[:events] && info[:region]
          prerendered << {
            year: year,
            token: token,
            region: info[:region],
            events: info[:events]
          }
        end
      end
    end
    prerendered
  end

  def collect_non_prerendered_studios
    # Studios that are NOT prerendered (no :events)
    non_prerendered = []
    @showcases.each do |year, sites|
      sites.each do |token, info|
        unless info[:events]
          non_prerendered << {
            year: year,
            token: token,
            region: info[:region]
          }
        end
      end
    end
    non_prerendered
  end

  def collect_regions
    regions = Set.new
    @showcases.each do |_year, sites|
      sites.each do |_token, info|
        regions << info[:region] if info[:region]
      end
    end
    regions.to_a
  end
end
