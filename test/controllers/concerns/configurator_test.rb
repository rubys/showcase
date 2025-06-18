require "test_helper"

# Comprehensive tests for the Configurator concern which handles geographic
# configuration and deployment management. Configurator is important for:
#
# - Managing geographic regions and their deployment status
# - Generating map configurations for studio locations
# - Creating showcase configurations with regional assignments
# - Calculating geographic distances using Haversine formula
# - Processing deployment data and regional filtering
# - File generation for mapping and showcase data
#
# Tests cover:
# - Geographic distance calculations (haversine_distance)
# - Region filtering and deployment management
# - Map generation from location data
# - Showcase configuration with regional assignments
# - File handling and YAML output generation
# - Edge cases and error handling

class ConfiguratorTest < ActiveSupport::TestCase
  include Configurator

  setup do
    # Tests now use fixtures in test/fixtures/files/, no need for tmp files
  end

  teardown do
    # No cleanup needed since we use fixtures, not tmp files
  end

  # ===== HAVERSINE DISTANCE TESTS =====
  
  test "haversine_distance calculates distance between coordinates" do
    # New York to Los Angeles (approximately 2445 miles / 3944 km)
    nyc = [40.7128, -74.0060]
    lax = [34.0522, -118.2437]
    
    distance_km = RegionConfiguration.haversine_distance(nyc, lax)
    distance_miles = RegionConfiguration.haversine_distance(nyc, lax, true)
    
    # Should be approximately 3944 km and 2445 miles
    assert_in_delta 3944, distance_km, 100 # Within 100km
    assert_in_delta 2445, distance_miles, 100 # Within 100 miles
  end
  
  test "haversine_distance handles same coordinates" do
    nyc = [40.7128, -74.0060]
    
    distance = RegionConfiguration.haversine_distance(nyc, nyc)
    
    # Distance should be 0 for same coordinates
    assert_in_delta 0, distance, 0.01
  end
  
  test "haversine_distance handles close coordinates" do
    # Two points very close to each other
    point1 = [40.7128, -74.0060]
    point2 = [40.7129, -74.0061] # About 0.01 degree difference
    
    distance = RegionConfiguration.haversine_distance(point1, point2)
    
    # Should be very small distance (less than 1 km)
    assert distance < 1
    assert distance > 0
  end
  
  test "haversine_distance works with negative coordinates" do
    # Test with southern hemisphere coordinates
    sydney = [-33.8688, 151.2093]
    melbourne = [-37.8136, 144.9631]
    
    distance = RegionConfiguration.haversine_distance(sydney, melbourne)
    
    # Sydney to Melbourne is approximately 714 km
    assert_in_delta 714, distance, 50
  end
  
  # ===== NEW_REGIONS TESTS =====
  
  test "load_deployed_regions returns deployed regions" do
    regions = RegionConfiguration.load_deployed_regions
    
    # Should load from test fixtures (sorted for consistent comparison)
    assert_equal ['CA', 'FL', 'NYC'], regions.sort
  end
  
  test "load_deployed_regions handles fixture data" do
    # Test that it loads from fixtures in test mode
    regions = RegionConfiguration.load_deployed_regions
    
    assert_includes regions, 'NYC'
    assert_includes regions, 'FL'
    assert_includes regions, 'CA'
  end
  
  # ===== GENERATE_MAP TESTS =====
  
  test "generate_map works in test environment" do
    # Should now work with fixtures instead of returning early
    result = generate_map
    
    # Should complete without error (returns result of write_yaml_if_changed)
    assert_nothing_raised { result }
  end
  
  test "generate_map creates proper map structure" do
    # Now works in test environment with fixtures
    
    # Create test locations
    location1 = Location.create!(
      key: 'test1',
      name: 'Test Location 1',
      latitude: 40.7128,
      longitude: -74.0060
    )
    
    location2 = Location.create!(
      key: 'test2',
      name: 'Test Location 2',
      latitude: 34.0522,
      longitude: -118.2437
    )
    
    generate_map
    
    # In test mode, verify the structure by calling the data generation directly
    # since files aren't actually written in test mode
    map_data = RegionConfiguration.generate_map_data
    assert map_data.key?('regions')
    assert map_data.key?('studios')
    
    # Verify regions structure (from fixtures)
    assert map_data['regions'].key?('NYC')
    assert map_data['regions'].key?('FL')
    assert map_data['regions'].key?('CA')
    
    # Verify studios structure (from test data)
    assert map_data['studios'].key?('test1')
    assert map_data['studios'].key?('test2')
    assert_equal 40.7128, map_data['studios']['test1']['lat']
    assert_equal(-74.0060, map_data['studios']['test1']['lon'])
  end
  
  # ===== GENERATE_SHOWCASES TESTS =====
  
  test "generate_showcases works in test environment" do
    # Should now work with fixtures instead of returning early
    result = generate_showcases
    
    # Should complete without error (returns result of write_yaml_if_changed)
    assert_nothing_raised { result }
  end
  
  test "generate_showcases creates proper showcase structure" do
    # Now works in test environment with fixtures
    
    # Create test location and showcase
    location = Location.create!(
      key: 'test_studio',
      name: 'Test Studio',
      latitude: 40.7128,
      longitude: -74.0060,
      region: 'NYC'
    )
    
    showcase = Showcase.create!(
      year: 2024,
      order: 1,
      key: 'test_event',
      name: 'Test Event',
      location: location
    )
    
    generate_showcases
    
    # In test mode, verify the structure by calling the data generation directly
    # since files aren't actually written in test mode
    showcases_data = RegionConfiguration.generate_showcases_data
    assert showcases_data.key?(2024)
    assert showcases_data[2024].key?('test_studio')
    assert_equal 'Test Studio', showcases_data[2024]['test_studio'][:name]
    assert_equal 'NYC', showcases_data[2024]['test_studio'][:region]
  end
  
  # ===== INTEGRATION TESTS =====
  
  test "dbpath constant is defined" do
    assert_not_nil Configurator::DBPATH
    assert Configurator::DBPATH.is_a?(String)
  end
  
  test "configurator uses fixtures in test environment" do
    # Should use fixtures instead of tmp files in test mode
    regions = RegionConfiguration.load_deployed_regions
    
    # Should get data from fixtures, not tmp files
    assert_includes regions, 'NYC'
    assert_includes regions, 'FL'
    assert_includes regions, 'CA'
    assert_equal 3, regions.length
  end
  
  # ===== EDGE CASES =====
  
  test "haversine_distance with extreme coordinates" do
    # Test with coordinates at extremes
    north_pole = [90, 0]
    south_pole = [-90, 0]
    
    distance = RegionConfiguration.haversine_distance(north_pole, south_pole)
    
    # Should be approximately half the Earth's circumference (about 20,000 km)
    assert_in_delta 20000, distance, 1000
  end
  
  test "haversine_distance across date line" do
    # Test coordinates on opposite sides of date line
    point1 = [0, 179]  # Near date line, east
    point2 = [0, -179] # Near date line, west
    
    distance = RegionConfiguration.haversine_distance(point1, point2)
    
    # Should be short distance (about 222 km), not around the world
    assert distance < 500
  end
  
  test "haversine_distance with zero coordinates" do
    # Test with null island (0, 0)
    origin = [0, 0]
    point = [1, 1]
    
    distance = RegionConfiguration.haversine_distance(origin, point)
    
    # Should calculate valid distance
    assert distance > 0
    assert distance < 200 # Should be reasonable for 1 degree difference
  end
  
  # ===== HELPER METHOD TESTS =====
  
  test "constants are properly defined" do
    assert defined?(Configurator::DBPATH)
    assert Configurator::DBPATH.include?('db')
  end
  
  # ===== ERROR HANDLING TESTS =====
  
  test "methods handle test environment correctly" do
    # Methods should now work in test environment using fixtures
    assert_nothing_raised { generate_map }
    assert_nothing_raised { generate_showcases }
    
    # Verify we're in test environment
    assert Rails.env.test?
  end
end