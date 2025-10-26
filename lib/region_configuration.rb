# frozen_string_literal: true

require 'sqlite3'
require 'json'

# Shared module for region configuration logic used by:
# - script/reconfig
# - app/controllers/concerns/configurator.rb
# - app/controllers/admin_controller.rb
#
# Uses direct SQLite queries for performance - no ActiveRecord overhead.
# Can run standalone (scripts) or within Rails (controllers).
module RegionConfiguration
  extend self

  # Get git root path
  def git_root
    if defined?(Rails)
      Rails.root.to_s
    else
      File.realpath(File.expand_path('../../', __FILE__))
    end
  end

  # File path helper methods (not constants since Rails may not be loaded)
  def deployed_json_path
    File.join(git_root, 'tmp', 'deployed.json')
  end

  def regions_json_path
    File.join(git_root, 'tmp', 'regions.json')
  end

  # Get path to index database
  # Uses Rails conventions if available, otherwise falls back to environment or default
  def index_db_path
    dbpath = ENV.fetch('RAILS_DB_VOLUME') { File.join(git_root, 'db') }
    File.join(dbpath, 'index.sqlite3')
  end

  # Calculate haversine distance between two geographic points
  def haversine_distance(geo_a, geo_b, miles = false)
    lat1, lon1 = geo_a
    lat2, lon2 = geo_b

    # Calculate radial arcs for latitude and longitude
    d_lat = (lat2 - lat1) * Math::PI / 180
    d_lon = (lon2 - lon1) * Math::PI / 180

    a = Math.sin(d_lat / 2) * Math.sin(d_lat / 2) +
        Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) *
        Math.sin(d_lon / 2) * Math.sin(d_lon / 2)

    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    
    6371 * c * (miles ? 1 / 1.6 : 1)
  end

  # Load deployed regions from JSON file
  # Falls back to querying Region model from index database if file doesn't exist
  def load_deployed_regions(file_path = nil)
    file_path ||= defined?(Rails) && Rails.env.test? ? 'test/fixtures/files/deployed.json' : deployed_json_path

    begin
      deployed = JSON.parse(File.read(file_path))
      pending = deployed['pending'] || {}

      regions = deployed['ProcessGroupRegions']
        .find { |process| process['Name'] == 'app' }['Regions']

      # Apply pending changes
      (pending['add'] || []).each do |region|
        regions.push(region) unless regions.include?(region)
      end

      (pending['delete'] || []).each do |region|
        regions.delete(region)
      end

      regions
    rescue Errno::ENOENT, JSON::ParserError
      # Fallback: Query Region model from index database
      db = SQLite3::Database.new(index_db_path, results_as_hash: true)
      regions = db.execute("SELECT DISTINCT code FROM regions WHERE type = 'fly' ORDER BY code")
        .map { |row| row['code'] }
      db.close
      regions
    end
  end

  # Load deployed regions data with pending changes
  def load_deployed_data(file_path = nil)
    file_path ||= defined?(Rails) && Rails.env.test? ? 'test/fixtures/files/deployed.json' : deployed_json_path
    JSON.parse(File.read(file_path))
  end

  # Load all regions data from regions.json
  # Falls back to querying regions table from index database if file doesn't exist
  def load_regions_data(file_path = nil)
    file_path ||= defined?(Rails) && Rails.env.test? ? 'test/fixtures/files/regions.json' : regions_json_path

    begin
      JSON.parse(File.read(file_path))
    rescue Errno::ENOENT, JSON::ParserError
      # Fallback: Query regions table from index database
      db = SQLite3::Database.new(index_db_path, results_as_hash: true)
      regions = db.execute("SELECT code, location AS name, latitude, longitude FROM regions WHERE type = 'fly' ORDER BY code")
      db.close
      regions
    end
  end

  # Update pending changes in deployed.json
  def update_pending_changes(changes, file_path = nil)
    file_path ||= defined?(Rails) && Rails.env.test? ? 'test/fixtures/files/deployed.json' : deployed_json_path
    deployed = load_deployed_data(file_path)
    deployed['pending'] ||= {}
    deployed['pending'].merge!(changes)
    
    # Don't write to fixture files in test mode
    unless Rails.env.test?
      File.write(file_path, JSON.pretty_generate(deployed))
    end
    deployed
  end

  # Add region to pending additions
  def add_pending_region(code, file_path = nil)
    file_path ||= defined?(Rails) && Rails.env.test? ? 'test/fixtures/files/deployed.json' : deployed_json_path
    deployed = load_deployed_data(file_path)
    deployed['pending'] ||= {}
    deployed['pending']['add'] ||= []
    deployed['pending']['delete'] ||= []

    if deployed['pending']['delete'].include?(code)
      # Undo pending deletion
      deployed['pending']['delete'].delete(code)
      message = "Region #{code} pending deletion undone."
    elsif !deployed['pending']['add'].include?(code)
      # Add to pending additions
      deployed['pending']['add'] << code
      message = "Region #{code} addition pending."
    else
      message = "Region #{code} already pending addition."
    end

    # Don't write to fixture files in test mode
    unless Rails.env.test?
      File.write(file_path, JSON.pretty_generate(deployed))
    end
    { deployed: deployed, message: message }
  end

  # Remove region from pending additions or add to pending deletions
  def remove_pending_region(code, file_path = nil)
    file_path ||= defined?(Rails) && Rails.env.test? ? 'test/fixtures/files/deployed.json' : deployed_json_path
    deployed = load_deployed_data(file_path)
    deployed['pending'] ||= {}
    deployed['pending']['add'] ||= []
    deployed['pending']['delete'] ||= []

    if deployed['pending']['add'].include?(code)
      # Undo pending addition
      deployed['pending']['add'].delete(code)
      message = "Region #{code} pending addition undone."
    elsif !deployed['pending']['delete'].include?(code)
      # Add to pending deletions
      deployed['pending']['delete'] << code
      message = "Region #{code} deletion pending."
    else
      message = "Region #{code} already pending deletion."
    end

    # Don't write to fixture files in test mode
    unless Rails.env.test?
      File.write(file_path, JSON.pretty_generate(deployed))
    end
    { deployed: deployed, message: message }
  end

  # Synchronize Region model records with deployed regions
  def synchronize_region_models
    deployed_data = load_deployed_data
    regions_data = load_regions_data
    pending = deployed_data['pending'] || {}
    
    # Get currently deployed regions including pending additions
    current_regions = deployed_data['ProcessGroupRegions']
      .find { |process| process['Name'] == 'app' }['Regions']
    current_regions += (pending['add'] || [])
    current_regions = current_regions.uniq.sort

    # Create hash of region data for easy lookup
    regions_lookup = regions_data.index_by { |region| region['code'] }

    # Find existing region codes in database
    existing_codes = Region.where(code: current_regions).pluck(:code)

    # Create missing regions
    current_regions.each do |code|
      next if existing_codes.include?(code)
      
      region_info = regions_lookup[code]
      next unless region_info # Skip if region data not found
      
      Region.create!(
        code: code,
        type: 'fly',
        location: region_info['name'],
        latitude: region_info['latitude'],
        longitude: region_info['longitude']
      )
    end

    # Remove regions no longer deployed
    Region.where.not(code: current_regions).each do |region|
      region.destroy! if region.type == 'fly'
    end

    current_regions
  end

  # Load available regions with coordinates from JSON file
  def load_available_regions
    regions_data = load_regions_data
    deployed_regions = load_deployed_regions

    regions_data
      .select { |region| deployed_regions.include?(region['code']) }
      .map { |region| [region['code'], [region['latitude'], region['longitude']]] }
      .to_h
  end

  # Select the best region for a location using fallback strategy
  def select_region_for_location(location, available_regions = nil, region_mapping = {})
    available_regions ||= load_available_regions

    # First try explicit region from location database column
    if location.region && !location.region.empty? && available_regions.keys.include?(location.region)
      return location.region
    end

    # Then try region mapping (for custom overrides)
    mapped_region = region_mapping[location.key]
    if mapped_region && available_regions.keys.include?(mapped_region)
      return mapped_region
    end

    # Finally, find closest available region by geographic distance
    return nil unless location.latitude && location.longitude

    geo_a = [location.latitude, location.longitude]
    best_region = nil
    best_distance = Float::INFINITY

    available_regions.each do |region_code, geo_b|
      distance = haversine_distance(geo_a, geo_b)
      if distance < best_distance
        best_region = region_code
        best_distance = distance
      end
    end

    best_region
  end

  # Generate map YAML structure
  def generate_map_data
    available_regions = load_available_regions
    regions_data_all = load_regions_data

    regions_data = available_regions.map do |code, (lat, lon)|
      region_info = regions_data_all.find { |r| r['code'] == code }

      [code, {
        'name' => region_info['name'],
        'lat' => lat,
        'lon' => lon
      }]
    end.to_h

    # Query locations directly from SQLite
    db = SQLite3::Database.new(index_db_path, results_as_hash: true)
    locations = db.execute("SELECT key, name, latitude, longitude, region FROM locations ORDER BY key")
    db.close

    studios_data = locations.map do |loc|
      # Build location-like struct for select_region_for_location
      location_struct = Struct.new(:key, :region, :latitude, :longitude).new(
        loc['key'],
        loc['region'],
        loc['latitude'],
        loc['longitude']
      )

      [loc['key'], {
        'name' => loc['name'],
        'lat' => loc['latitude'],
        'lon' => loc['longitude'],
        'region' => select_region_for_location(location_struct, available_regions),
      }]
    end.to_h

    {
      'regions' => regions_data,
      'studios' => studios_data
    }
  end

  # Generate showcases YAML structure
  def generate_showcases_data
    available_regions = load_available_regions

    # Query showcases with location data directly from SQLite
    db = SQLite3::Database.new(index_db_path, results_as_hash: true)
    rows = db.execute(<<~SQL)
      SELECT
        s.year, s.key AS showcase_key, s.name AS showcase_name,
        s.date, s."order" AS showcase_order,
        l.key AS location_key, l.name AS location_name,
        l.latitude, l.longitude, l.region, l.locale, l.logo
      FROM showcases s
      JOIN locations l ON s.location_id = l.id
      ORDER BY s.year DESC, s."order" DESC
    SQL
    db.close

    # Group by year, then by location
    by_year = rows.group_by { |row| row['year'] }

    by_year.map do |year, year_rows|
      by_location = year_rows.group_by { |row| row['location_key'] }
        .to_a.sort

      events_data = by_location.map do |location_key, location_rows|
        # All rows have same location data, use first
        first_row = location_rows.first

        # Build location-like struct for select_region_for_location
        location_struct = Struct.new(:key, :region, :latitude, :longitude).new(
          first_row['location_key'],
          first_row['region'],
          first_row['latitude'],
          first_row['longitude']
        )

        entry = {
          name: first_row['location_name'],
          region: select_region_for_location(location_struct, available_regions)
        }

        # Only include non-default values (normalize underscores first)
        normalized_locale = first_row['locale']&.gsub('_', '-')
        if normalized_locale && !normalized_locale.empty? && normalized_locale != 'en-US'
          entry[:locale] = normalized_locale
        end

        if first_row['logo'] && !first_row['logo'].empty? && first_row['logo'] != 'arthur-murray-logo.gif'
          entry[:logo] = first_row['logo']
        end

        # Single event with key='showcase' vs multiple events
        if location_rows.length == 1 && location_rows.first['showcase_key'] == 'showcase'
          showcase = location_rows.first
          entry[:date] = showcase['date'] if showcase['date'] && !showcase['date'].empty?
        elsif location_rows.length > 0
          # Multiple events - reverse order for events hash
          entry[:events] = location_rows.reverse.map do |event_row|
            event_data = { name: event_row['showcase_name'] }
            event_data[:date] = event_row['date'] if event_row['date'] && !event_row['date'].empty?
            [event_row['showcase_key'], event_data]
          end.to_h
        end

        [location_key, entry]
      end.to_h

      [year, events_data]
    end.to_h
  end

  # Write YAML file only if content has changed
  def write_yaml_if_changed(file_path, data, logger = nil)
    output = YAML.dump(data)
    existing_content = File.read(file_path) rescue nil
    
    unless existing_content == output
      # In test mode, don't actually write files to avoid side effects
      unless Rails.env.test?
        File.write(file_path, output)
      end
      logger&.info("✓ Updated #{file_path}")
      true
    else
      logger&.info("- No changes needed for #{file_path}")
      false
    end
  end
end