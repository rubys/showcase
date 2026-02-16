# frozen_string_literal: true

require 'sqlite3'
require 'date'
require 'time'

# Removes stale empty showcases from index.sqlite3
# A showcase is considered stale when:
#   1. Its event date has passed
#   2. It was created more than age_days ago
#   3. Its event database has zero people and zero scheduled heats (or doesn't exist)
module ShowcaseCleanup
  class << self
    def cleanup(quiet: false, dry_run: false, age_days: 30)
      dbpath = ENV.fetch('RAILS_DB_VOLUME') { db_path }
      index_db = File.join(dbpath, 'index.sqlite3')

      return { removed: [], skipped: [], errors: [] } unless File.exist?(index_db)

      removed = []
      skipped = []
      errors = []
      today = Date.today
      cutoff = today - age_days

      SQLite3::Database.new(index_db) do |db|
        db.results_as_hash = true

        # Get all showcases with their location keys
        showcases = db.execute(<<~SQL)
          SELECT s.id, s.year, s.date, s.created_at, s.name,
                 l.key as location_key, s.key as showcase_key
          FROM showcases s
          JOIN locations l ON s.location_id = l.id
        SQL

        showcases.each do |showcase|
          begin
            # Check 1: Is the event date in the past?
            unless date_in_past?(showcase['date'], showcase['year'], today)
              next
            end

            # Check 2: Was it created more than age_days ago?
            created_at = parse_created_at(showcase['created_at'])
            unless created_at && created_at.to_date <= cutoff
              next
            end

            # Build the database filename (same pattern as ShowcaseDateSync)
            event_db_name = build_db_name(showcase)
            event_db_path = File.join(dbpath, event_db_name)

            # Check 3: Is the event database empty?
            unless event_empty?(event_db_path)
              skipped << event_db_name
              next
            end

            label = "#{showcase['name']} (#{event_db_name})"

            if dry_run
              puts "  Would remove: #{label}" unless quiet
            else
              db.execute("DELETE FROM showcases WHERE id = ?", [showcase['id']])
              if File.exist?(event_db_path)
                File.delete(event_db_path)
                puts "  Removed: #{label} (database deleted)" unless quiet
              else
                puts "  Removed: #{label} (no database file)" unless quiet
              end
            end

            removed << label
          rescue => e
            event_db_name ||= "#{showcase['year']}-#{showcase['location_key']}"
            errors << { db: event_db_name, error: e.message }
            puts "  Error processing #{event_db_name}: #{e.message}" unless quiet
          end
        end
      end

      { removed: removed, skipped: skipped, errors: errors }
    end

    private

    def db_path
      if defined?(Rails)
        Rails.root.join('db').to_s
      else
        File.expand_path('../db', __dir__)
      end
    end

    # Build the database filename following the same convention as ShowcaseDateSync
    def build_db_name(showcase)
      if showcase['showcase_key'].nil? || showcase['showcase_key'].empty? || showcase['showcase_key'] == 'showcase'
        "#{showcase['year']}-#{showcase['location_key']}.sqlite3"
      else
        "#{showcase['year']}-#{showcase['location_key']}-#{showcase['showcase_key']}.sqlite3"
      end
    end

    # Determine if the showcase date is in the past
    def date_in_past?(date_str, year, today)
      if date_str.nil? || date_str.to_s.strip.empty?
        # No date set — fall back to year comparison
        return year.to_i < today.year
      end

      # Year-only string (e.g. "2025")
      if date_str.to_s.strip.match?(/\A\d{4}\z/)
        return date_str.to_i < today.year
      end

      # Date ranges use " - " separator; take the end date
      check_str = date_str.include?(' - ') ? date_str.split(' - ').last : date_str

      begin
        Date.parse(check_str) < today
      rescue ArgumentError
        # Unparseable date — fall back to year comparison
        year.to_i < today.year
      end
    end

    # Parse created_at from the database (stored as ISO 8601 string by Rails)
    def parse_created_at(created_at_str)
      return nil if created_at_str.nil? || created_at_str.to_s.strip.empty?
      Time.parse(created_at_str)
    rescue ArgumentError
      nil
    end

    # Check if the event database is empty (zero people and zero scheduled heats)
    def event_empty?(event_db_path)
      return true unless File.exist?(event_db_path)

      empty = true
      SQLite3::Database.new(event_db_path) do |event_db|
        people_count = event_db.get_first_value("SELECT count(id) FROM people") || 0
        heat_count = event_db.get_first_value("SELECT count(DISTINCT number) FROM heats WHERE number > 0") || 0
        empty = people_count.to_i == 0 && heat_count.to_i == 0
      end
      empty
    rescue SQLite3::SQLException
      # If tables don't exist, treat as empty
      true
    end
  end
end
