# frozen_string_literal: true

# Helper module to load showcases from the appropriate location based on environment
module ShowcasesLoader
  # Get the root directory - works both inside and outside Rails
  def self.root_path
    if defined?(Rails)
      Rails.root.to_s
    else
      File.realpath(File.expand_path('..', __dir__))
    end
  end

  # Load showcases from the appropriate location based on environment
  # Admin machine: db/showcases.yml
  # Production: /data/db/showcases.yml (via RAILS_DB_VOLUME)
  def self.load
    dbpath = ENV['RAILS_DB_VOLUME'] || File.join(root_path, 'db')
    file = File.join(dbpath, 'showcases.yml')
    YAML.load_file(file)
  rescue Errno::ENOENT
    # For tests or initial setup when no showcases.yml exists yet
    {}
  end

  # Load deployed state for comparison (admin machine only)
  def self.load_deployed
    file = File.join(root_path, 'db/deployed-showcases.yml')
    YAML.load_file(file)
  rescue Errno::ENOENT
    # For initial setup: use current state as baseline
    load
  end
end
