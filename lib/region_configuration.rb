# frozen_string_literal: true

# Shared module for region configuration logic used by:
# - script/reconfig 
# - app/controllers/concerns/configurator.rb
# - app/controllers/admin_controller.rb
module RegionConfiguration
  extend self

  # File path constants
  DEPLOYED_JSON_PATH = File.join(Rails.root, 'tmp', 'deployed.json')
  REGIONS_JSON_PATH = File.join(Rails.root, 'tmp', 'regions.json')

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
  def load_deployed_regions(file_path = nil)
    file_path ||= Rails.env.test? ? 'test/fixtures/files/deployed.json' : DEPLOYED_JSON_PATH
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
  end

  # Load deployed regions data with pending changes
  def load_deployed_data(file_path = nil)
    file_path ||= Rails.env.test? ? 'test/fixtures/files/deployed.json' : DEPLOYED_JSON_PATH
    JSON.parse(File.read(file_path))
  end

  # Load all regions data from regions.json
  def load_regions_data(file_path = nil)
    file_path ||= Rails.env.test? ? 'test/fixtures/files/regions.json' : REGIONS_JSON_PATH
    JSON.parse(File.read(file_path))
  end

  # Update pending changes in deployed.json
  def update_pending_changes(changes, file_path = nil)
    file_path ||= Rails.env.test? ? 'test/fixtures/files/deployed.json' : DEPLOYED_JSON_PATH
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
    file_path ||= Rails.env.test? ? 'test/fixtures/files/deployed.json' : DEPLOYED_JSON_PATH
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
    file_path ||= Rails.env.test? ? 'test/fixtures/files/deployed.json' : DEPLOYED_JSON_PATH
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
    if location.region.present? && available_regions.keys.include?(location.region)
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

    studios_data = Location.order(:key).map do |location|
      [location.key, {
        'name' => location.name,
        'lat' => location.latitude,
        'lon' => location.longitude,
        'region' => select_region_for_location(location, available_regions),
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
    
    showcases = Showcase.preload(:location).order(:year, :order).reverse
      .group_by(&:year).to_a

    showcases.map do |year, year_showcases|
      events = year_showcases.group_by { |showcase| showcase.location.key }
        .to_a.sort

      events_data = events.map do |location_key, location_events|
        location = location_events.first.location
        
        entry = {
          name: location.name,
          region: select_region_for_location(location, available_regions)
        }

        # Only include non-default values (normalize underscores first)
        normalized_locale = location.locale&.gsub('_', '-')
        if normalized_locale.present? && normalized_locale != 'en-US'
          entry[:locale] = normalized_locale
        end

        if location.logo.present? && location.logo != 'arthur-murray-logo.gif'
          entry[:logo] = location.logo
        end

        if location_events.length == 1 && location_events.first.key == 'showcase'
          showcase = location_events.first
          entry[:date] = showcase.date if showcase.date.present?
        elsif location_events.length > 0
          entry[:events] = location_events.reverse.map do |event|
            event_data = { name: event.name }
            event_data[:date] = event.date if event.date.present?
            [event.key, event_data]
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