# frozen_string_literal: true

require 'sqlite3'

# Syncs event dates from individual event databases to the showcases table in index.sqlite3
# This ensures dates are available at prerender time without needing inventory files.
module ShowcaseDateSync
  class << self
    def sync(quiet: false)
      dbpath = ENV.fetch('RAILS_DB_VOLUME') { db_path }
      index_db = File.join(dbpath, 'index.sqlite3')

      return { updated: [], errors: [] } unless File.exist?(index_db)

      updated = []
      errors = []

      SQLite3::Database.new(index_db) do |db|
        db.results_as_hash = true

        # Get all showcases with their location keys
        showcases = db.execute(<<~SQL)
          SELECT s.id, s.year, l.key as location_key, s.key as showcase_key, s.name, s.date
          FROM showcases s
          JOIN locations l ON s.location_id = l.id
        SQL

        showcases.each do |showcase|
          # Build the database filename
          # Multi-event: 2025-raleigh-disney.sqlite3
          # Single-event: 2025-raleigh.sqlite3
          if showcase['showcase_key'].nil? || showcase['showcase_key'].empty? || showcase['showcase_key'] == 'showcase'
            event_db_name = "#{showcase['year']}-#{showcase['location_key']}.sqlite3"
          else
            event_db_name = "#{showcase['year']}-#{showcase['location_key']}-#{showcase['showcase_key']}.sqlite3"
          end

          event_db_path = File.join(dbpath, event_db_name)

          next unless File.exist?(event_db_path)

          begin
            # Read date from the event database
            event_date = nil
            SQLite3::Database.new(event_db_path) do |event_db|
              event_db.results_as_hash = true
              result = event_db.get_first_row("SELECT date FROM events LIMIT 1")
              event_date = result['date'] if result
            end

            next if event_date.nil? || event_date.empty?

            # Parse and normalize the date
            normalized_date = normalize_date(event_date, showcase['year'])

            next if normalized_date.nil?

            # Check if update is needed
            current_date = showcase['date']
            if current_date != normalized_date
              db.execute("UPDATE showcases SET date = ? WHERE id = ?", [normalized_date, showcase['id']])
              updated << {
                name: "#{showcase['year']}-#{showcase['location_key']}-#{showcase['showcase_key'] || 'showcase'}",
                old_date: current_date,
                new_date: normalized_date
              }
              puts "  Updated #{event_db_name}: #{current_date} -> #{normalized_date}" unless quiet
            end
          rescue => e
            errors << { db: event_db_name, error: e.message }
            puts "  Error reading #{event_db_name}: #{e.message}" unless quiet
          end
        end
      end

      { updated: updated, errors: errors }
    end

    private

    def db_path
      if defined?(Rails)
        Rails.root.join('db').to_s
      else
        File.expand_path('../db', __dir__)
      end
    end

    # Return date as-is from event database
    # We don't normalize because dates may be intentionally in various formats
    # (ISO, locale-specific, text descriptions, etc.)
    def normalize_date(date_string, year)
      return nil if date_string.nil? || date_string.strip.empty?
      date_string
    end
  end
end
