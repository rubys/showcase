# RegionConfiguration will be autoloaded by Rails since we added lib to autoload_paths

module Configurator
  DBPATH = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s

  def generate_map
    map_data = RegionConfiguration.generate_map_data
    file = File.join(DBPATH, 'map.yml')
    RegionConfiguration.write_yaml_if_changed(file, map_data)
  end

  def generate_showcases
    showcases_data = RegionConfiguration.generate_showcases_data
    file = File.join(DBPATH, 'showcases.yml')
    RegionConfiguration.write_yaml_if_changed(file, showcases_data)
  end
end
