# frozen_string_literal: true

# Helper module to load showcases from the appropriate location based on environment
# Provides safe fallbacks during migration from git-tracked to generated showcases.yml
module ShowcasesLoader
  # Load showcases from the appropriate location based on environment
  # Admin machine: db/showcases.yml
  # Production: /data/db/showcases.yml (via RAILS_DB_VOLUME)
  def self.load
    dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
    file = File.join(dbpath, 'showcases.yml')
    YAML.load_file(file)
  rescue Errno::ENOENT
    # Fallback to git-tracked file during migration
    fallback_file = Rails.root.join('config/tenant/showcases.yml')
    if File.exist?(fallback_file)
      YAML.load_file(fallback_file)
    else
      # For tests or initial setup
      {}
    end
  end

  # Load deployed state for comparison (admin machine only)
  def self.load_deployed
    file = Rails.root.join('db/deployed-showcases.yml')
    YAML.load_file(file)
  rescue Errno::ENOENT
    # Fallback to git-tracked file if no deployed snapshot exists yet
    YAML.load_file(Rails.root.join('config/tenant/showcases.yml'))
  end
end
