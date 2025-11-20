# frozen_string_literal: true

# Helper module to load showcases from the appropriate location based on environment
# Also provides centralized path resolution for database and git root directories
module ShowcasesLoader
  # Get the git root directory - works both inside and outside Rails
  def self.root_path
    if defined?(Rails)
      Rails.root.to_s
    else
      File.realpath(File.expand_path('..', __dir__))
    end
  end

  # Get the database directory path
  # Production: /data/db (via RAILS_DB_VOLUME)
  # Development/Admin: {root}/db
  def self.db_path
    ENV['RAILS_DB_VOLUME'] || File.join(root_path, 'db')
  end

  # Load showcases from the appropriate location based on environment
  # Admin machine: db/showcases.yml
  # Production: /data/db/showcases.yml (via RAILS_DB_VOLUME)
  # Development: falls back to deployed-showcases.yml if showcases.yml doesn't exist
  def self.load
    file = File.join(db_path, 'showcases.yml')
    YAML.load_file(file)
  rescue Errno::ENOENT
    # Fall back to deployed-showcases.yml for development
    # Returns {} if that file also doesn't exist
    load_deployed
  end

  # Load deployed state for comparison (admin machine only)
  def self.load_deployed
    file = File.join(root_path, 'db/deployed-showcases.yml')
    YAML.load_file(file)
  rescue Errno::ENOENT
    # Fall back to current state if showcases.yml exists
    # Return empty hash otherwise to avoid infinite recursion
    File.exist?(File.join(db_path, 'showcases.yml')) ? load : {}
  end

  # Flatten showcases by year into a single hash of all studios
  # Useful for comparison operations that don't need year grouping
  def self.all_showcases
    load.values.reduce({}) { |a, b| a.merge(b) }
  end

  # Flatten deployed showcases by year into a single hash
  def self.deployed_showcases
    load_deployed.values.reduce({}) { |a, b| a.merge(b) }
  end
end
