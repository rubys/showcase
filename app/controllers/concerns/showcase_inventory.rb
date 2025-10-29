# frozen_string_literal: true

module ShowcaseInventory
  extend ActiveSupport::Concern

  private

  def build_inventory(full_inventory: true, showcases: nil)
    @inventory ||= JSON.parse(File.read('tmp/inventory.json')) rescue []
    showcases_to_process = showcases || (@showcases ||= ShowcasesLoader.load)

    events = []
    
    # Extract events from showcases structure
    showcases_to_process.each do |year, sites|
      sites.each do |token, info|
        if info[:events]
          info[:events].each do |subtoken, subinfo|
            events << {
              db: "#{year}-#{token}-#{subtoken}",
              studio: info[:name],
              year: year,
              info: subinfo
            }
          end
        else
          events << {
            db: "#{year}-#{token}",
            studio: info[:name], 
            year: year,
            info: info
          }
        end
      end
    end
    
    # Process each event with caching
    events.each do |event|
      process_event_inventory(event, full_inventory: full_inventory)
    end
    
    # Update inventory cache
    json = JSON.pretty_generate(@inventory)
    if !File.exist?('tmp/inventory.json') || File.read('tmp/inventory.json') != json
      File.write('tmp/inventory.json', json)
    end

    if showcases
      # read inventory files for event dates
      inventory = {}
      dbpath = ENV.fetch("RAILS_DB_VOLUME", Rails.root.join('db').to_s)
      inventory_path = "#{File.dirname(dbpath)}/inventory"
      if Dir.exist?(inventory_path)
        Dir["#{inventory_path}/*.json"].each do |file|
          inventory.merge! JSON.parse(File.read(file)) rescue nil
        end
      end

      this_year = Time.now.year

      # Update showcases with event dates from inventory
      showcases.each do |year, sites|
        sites.each do |token, info|
          if info[:events]
            info[:events].each do |name, info|
              next unless info["date"].blank?
              db = "#{year}-#{token}-#{name}.sqlite3"
              if inventory[db] && inventory[db]['date']
                info["date"] = inventory[db]['date']
              elsif year.to_i >= this_year
                info["date"] = "TBD"
              end
            end
          else
            next unless info["date"].blank?
            db = "#{year}-#{token}.sqlite3"
            if inventory[db] && inventory[db]['date']
              info["date"] = inventory[db]['date']
            elsif year.to_i >= this_year
              info["date"] = "TBD"
            end
          end
        end
      end
    end

    events
  end

  def process_event_inventory(event, full_inventory: true)
    dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
    mtime = File.mtime(File.join(dbpath, "#{event[:db]}.sqlite3")).to_i rescue nil
    cache = @inventory.find { |e| e['db'] == event[:db] }
    
    if full_inventory
      # AdminController logic - check for complete cache
      if cache&.fetch('mtime') == mtime && cache['rows'] && cache['event'] && !cache['heats'].blank?
        return apply_full_cache(event, cache)
      end
      build_full_inventory_data(event, mtime)
    else
      # EventController logic - minimal cache
      if cache && cache['mtime'] == mtime
        return apply_minimal_cache(event, cache)
      end
      build_minimal_inventory_data(event, mtime)
    end
  end

  def build_full_inventory_data(event, mtime)
    event[:mtime] = mtime
    event[:date] = event[:year].to_s

    # Get event data, heat count, table info, and row counts in optimized queries
    begin
      # Single query to get both event name and full event data
      event_row = dbquery(event[:db], 'events').first
      event[:event] = event_row || {}
      event[:name] ||= event_row&.fetch('name', nil) || 'Showcase'

      if !event_row["date"].blank?
        event[:date] = Event.parse_date(event_row["date"], now: Time.local(event[:year], 1, 1)).to_date.iso8601
      end
      
      # Get table names using dbquery
      tables_query = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
      table_names = dbquery_raw(event[:db], tables_query).map { |row| row['name'] }
      
      if !table_names.empty?
        # Build counts query for all tables plus heat count
        counts_parts = table_names.map do |table_name|
          if table_name == 'entries'
            # For entries, count heats where number > 0
            "SELECT 'entries' as table_name, COUNT(*) as count FROM heats WHERE number >= 0"
          elsif table_name == 'heats'
            # For heats, get both total count and distinct number count
            "SELECT 'heats' as table_name, COUNT(*) as count FROM heats UNION ALL SELECT 'heat_numbers' as table_name, COUNT(DISTINCT number) as count FROM heats WHERE number > 0"
          else
            "SELECT '#{table_name}' as table_name, COUNT(*) as count FROM [#{table_name}]"
          end
        end
        
        counts_query = counts_parts.join(' UNION ALL ')
        counts_results = dbquery_raw(event[:db], counts_query)
        
        event[:rows] = {}
        counts_results.each do |row|
          if row['table_name'] == 'heat_numbers'
            event[:heats] = row['count'].to_i
          else
            event[:rows][row['table_name']] = row['count'].to_i
          end
        end
        
        # Fallback for heat count if not set
        event[:heats] ||= 0
      else
        event[:rows] = {}
        event[:heats] = 0
      end
      
      # Extract function information using a single UNION ALL query
      event[:functions] = {}
      
      if defined?(AdminController::FUNCTIONS) && AdminController::FUNCTIONS.any?
        # Build a single query for all functions
        function_queries = AdminController::FUNCTIONS.map do |function_key, function_def|
          "SELECT '#{function_key}' as function_name, (#{function_def[:query]}) as result"
        end
        
        combined_query = function_queries.join(' UNION ALL ')
        
        begin
          results = dbquery_raw(event[:db], combined_query)
          
          # Process results
          results.each do |row|
            function_key = row['function_name']
            event[:functions][function_key] = row['result'] == 1
          end
          
          # Set any missing functions to false
          AdminController::FUNCTIONS.keys.each do |key|
            event[:functions][key] ||= false
          end
        rescue => e
          # If the combined query fails, set all functions to false
          AdminController::FUNCTIONS.keys.each { |key| event[:functions][key] = false }
        end
      end
      
    rescue => e
      # If there's an error, set defaults
      event[:event] = {}
      event[:name] ||= 'Showcase'
      event[:rows] = {}
      event[:heats] = 0
      event[:functions] = {}
      if defined?(AdminController::FUNCTIONS)
        AdminController::FUNCTIONS.keys.each { |key| event[:functions][key] = false }
      end
    end

    # Update inventory cache
    update_full_inventory_cache_entry(event)
  end

  def build_minimal_inventory_data(event, mtime)
    begin
      event[:info].merge! dbquery(event[:db], 'events', 'date').first
      update_minimal_inventory_cache_entry(event, mtime)
    rescue
      # Error handling - no action needed for minimal inventory
    end
  end

  def apply_full_cache(event, cache)
    event[:mtime] = cache['mtime']
    event[:date] = cache['date']
    event[:name] = cache['name']
    event[:heats] = cache['heats']
    event[:rows] = cache['rows']
    event[:event] = cache['event']
    event[:functions] = cache['functions']
  end

  def apply_minimal_cache(event, cache)
    return unless cache
    event[:info]['date'] = cache['date'] unless cache['date'] =~ /^\d{4}$/
  end

  def update_full_inventory_cache_entry(event)
    cache = @inventory.find { |e| e['db'] == event[:db] }
    @inventory.delete(cache) if cache
    @inventory << {
      'db' => event[:db],
      'mtime' => event[:mtime],
      'date' => event[:date],
      'name' => event[:name],
      'heats' => event[:heats],
      'rows' => event[:rows],
      'event' => event[:event],
      'functions' => event[:functions]
    }
  end

  def update_minimal_inventory_cache_entry(event, mtime)
    cache = @inventory.find { |e| e['db'] == event[:db] }
    @inventory.delete(cache) if cache
    @inventory << {
      'db' => event[:db],
      'mtime' => mtime,
      'date' => event[:info]['date']
    }
  end

  def load_inventory_data
    JSON.parse(File.read('tmp/inventory.json')) rescue []
  end

  def set_scope
    @scope = ENV.fetch("RAILS_APP_SCOPE", '')
    @scope = '/' + @scope unless @scope.empty?
    @scope = ENV['RAILS_RELATIVE_URL_ROOT'] + '/' + @scope if ENV['RAILS_RELATIVE_URL_ROOT']
  end
end