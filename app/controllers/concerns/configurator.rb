module Configurator

  DBPATH = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s

  def generate_map
    return if Rails.env.test?

    deployed = new_regions
    regions = JSON.parse(IO.read 'tmp/regions.json').
      select {|region| deployed.include? region['Code']}

    map = {}

    map['regions'] = regions.map do |region|
      [region['Code'], {
        'name' => region['Name'],
        'lat' => region['Latitude'],
        'lon' => region['Longitude']
      }]
    end.to_h

    map['studios'] = Location.order(:key).map do |location|
      [location.key, {
        'lat' => location.latitude,
        'lon' => location.longitude
      }]
    end.to_h

    file = File.join(DBPATH, 'map.yml')
    output = YAML.dump(map.to_h)
    unless (IO.read(file) rescue nil) == output
      IO.write file, output
    end
  end

  def generate_showcases
    return if Rails.env.test?

    deployed = new_regions

    regions = JSON.parse(IO.read 'tmp/regions.json').
      map {|region| [region['Code'], [region["Latitude"], region["Longitude"]]]}.
      select {|region, geo| deployed.include? region}.to_h

    select_region = lambda do |location|
      return location.region if regions.keys.include? location.region

      geo_a = [location.latitude, location.longitude]

      code = nil
      best = Float::INFINITY

      regions.each do |region, geo_b|
        distance = haversine_distance(geo_a, geo_b)
        if distance < best
          code = region
          best = distance 
        end
      end

      code
    end

    showcases = Showcase.preload(:location).order(:year, :order).reverse.
      group_by(&:year).to_a

    showcases.map! do |year, showcases|
      events = showcases.group_by {|showcase| showcase.location.key}.
        to_a.sort

      events.map! do |location, events|
        entry = {
          name: events.first.location.name,
          region: select_region[events.first.location],
          logo: events.first.location.logo || 'arthur-murray-logo.gif'
        }

        if events.length > 1
          entry[:events] = events.reverse.
            map {|event| [event.key, {name: event.name}]}.to_h
        end

        [location, entry]
      end

      [year, events.to_h]
    end

    file = File.join(DBPATH, 'showcases.yml')
    output = YAML.dump(showcases.to_h)
    unless (IO.read(file) rescue nil) == output
      IO.write file, output
    end
  end

private

  def haversine_distance(geo_a, geo_b, miles=false)
    # Get latitude and longitude
    lat1, lon1 = geo_a
    lat2, lon2 = geo_b

    # Calculate radial arcs for latitude and longitude
    dLat = (lat2 - lat1) * Math::PI / 180
    dLon = (lon2 - lon1) * Math::PI / 180

    a = Math.sin(dLat / 2) * 
        Math.sin(dLat / 2) +
        Math.cos(lat1 * Math::PI / 180) * 
        Math.cos(lat2 * Math::PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2)

    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))

    d = 6371 * c * (miles ? 1 / 1.6 : 1)
  end

  def new_regions
    deployed = JSON.parse(IO.read 'tmp/deployed.json')
    pending = deployed['pending'] || {}
    deployed = deployed['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"]

    (pending['add'] || []).each do |region|
      deployed.push(region) unless deployed.include? region
    end

    (pending['delete'] || []).each do |region|
      deployed.delete(region)
    end

    deployed
  end

end