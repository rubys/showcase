class AdminController < ApplicationController
  include Configurator
  include DbQuery

  before_action :admin_home

  # Registry of functions that return boolean values based on SQL queries
  FUNCTIONS = {
    'scrutineering' => {
      name: 'Scrutineering',
      description: 'Events using scrutineering (semi-finals)',
      query: "SELECT EXISTS(SELECT 1 FROM dances WHERE semi_finals = 1) as result"
    }
  }.freeze

  def index
    if ENV['FLY_REGION']
      redirect_to 'https://rubix.intertwingly.net/showcase/admin',
        allow_other_host: true
      return
    end

    showcases = YAML.load_file('config/tenant/showcases.yml')

    cities = Set.new
    @events = 0

    showcases.each do |year, info|
      info.each do |city, defn|
        cities << city
        if defn[:events]
          @events += defn[:events].length
        else
          @events += 1
        end
      end
    end

    @cities = cities.count
  end

  def regions
    fly = File.join(Dir.home, '.fly/bin/flyctl')

    thread1 = Thread.new do
      original = IO.read RegionConfiguration::DEPLOYED_JSON_PATH rescue '{}'
      pending = JSON.parse(original)["pending"]
      stdout, status = Open3.capture2(fly, 'regions', 'list', '--json')

      if pending
        deployed = JSON.parse(stdout)
        deployed["pending"] = pending

        regions = deployed['ProcessGroupRegions'].
          find {|process| process['Name'] == 'app'}["Regions"]

        (pending['add'] || []).dup.each do |region|
          pending['add'].delete(region) if regions.include? region
        end

        (pending['delete'] || []).dup.each do |region|
          pending['delete'].delete(region) unless regions.include? region
        end

        stdout = JSON.pretty_generate(deployed)
      end

      if status.success? and stdout != original
        IO.write RegionConfiguration::DEPLOYED_JSON_PATH, stdout
      end
    end

    thread2 = Thread.new do
      stdout, status = Open3.capture2(fly, 'platform', 'regions', '--json')
      if status.success? and stdout != (IO.read RegionConfiguration::REGIONS_JSON_PATH rescue nil)
        IO.write RegionConfiguration::REGIONS_JSON_PATH, stdout
      end
    end

    thread1.join
    thread2.join

    deployed = RegionConfiguration.load_deployed_data
    @regions = RegionConfiguration.load_regions_data
    @pending = deployed["pending"] || {}
    @deployed = (deployed['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"]+ (@pending['add'] || [])).sort.
      map {|code| [code, @regions.find {|region| region['code'] == code}]}.to_h

    # Synchronize Region model records
    RegionConfiguration.synchronize_region_models
  end

  def show_region
    @primary_region = Tomlrb.load_file('fly.toml')['primary_region'] || 'iad'
    @pending = RegionConfiguration.load_deployed_data['pending'] || {}
    @code = params[:code]
    @region = RegionConfiguration.load_regions_data.find { |region| region['Code'] == @code }
    render :region
  end

  def destroy_region
    code = params[:code]
    result = RegionConfiguration.remove_pending_region(code)
    notice = result[:message]

    generate_map

    respond_to do |format|
      format.html { redirect_to admin_regions_url, status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  def new_region
    deployed_data = RegionConfiguration.load_deployed_data
    pending = deployed_data["pending"] || {}
    deployed = deployed_data['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"]
    
    # Apply pending changes to get current effective deployment
    deployed += pending["add"] || []
    deployed -= pending["delete"] || []

    @regions = RegionConfiguration.load_regions_data.
      select {|region| not deployed.include?(region['Code'])}.
      map {|region| [region['Name'], region['Code']]}.to_h
  end

  def create_region
    code = params[:code]
    result = RegionConfiguration.add_pending_region(code)
    notice = result[:message]

    generate_map

    respond_to do |format|
      format.html { redirect_to admin_regions_url, status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  def apply
    @stream = OutputChannel.register(:apply)

    generate_showcases
    before = YAML.load_file('config/tenant/showcases.yml').values.reduce {|a, b| a.merge(b)}
    after = YAML.load_file('db/showcases.yml').values.reduce {|a, b| a.merge(b)}

    @move = {}
    after.to_a.sort.each do |site, info|
      was = before[site]
      next unless was
      next if was[:region] == info[:region]
      @move[site] = {from: was[:region], to: info[:region]}
    end

    previous = parse_showcases('config/tenant/showcases.yml')
    showcases = parse_showcases('db/showcases.yml')
    @showcases_modified = showcases - previous
    @showcases_removed = previous - showcases - @showcases_modified

    deployed = RegionConfiguration.load_deployed_data
    @pending = deployed['pending'] || {}
    regions = deployed['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"]

    (@pending['add'] ||= []).select! {|region| !regions.include? region}
    (@pending['delete'] ||= []).select! {|region| regions.include? region}
  end

  def inventory
    @inventory = JSON.parse(File.read('tmp/inventory.json')) rescue []
    @showcases = YAML.load_file('config/tenant/showcases.yml')

    @events = []

    @showcases.each do |year, sites|
      sites.each do |token, info|
        if info[:events]
          info[:events].each do |subtoken, subinfo|
            subinfo[:db] = "#{year}-#{token}-#{subtoken}"
            subinfo[:studio] = info[:name]
            subinfo[:year] = year
            @events << subinfo
          end
        else
          info[:db] = "#{year}-#{token}"
          info[:studio] = info[:name]
          info[:name] = nil
          info[:year] = year
          @events << info
        end
      end
    end

    @events.each do |event|
       mtime = File.mtime(File.join('db', "#{event[:db]}.sqlite3")).to_i rescue nil

       cache = @inventory.find {|e| e['db'] == event[:db]}
       if cache and cache['mtime'] == mtime and cache['rows'] and cache['event'] and !cache['heats'].blank?
         event[:mtime] = cache['mtime']
         event[:date] = cache['date']
         event[:name] = cache['name']
         event[:heats] = cache['heats']
         event[:rows] = cache['rows']
         event[:event] = cache['event']
          event[:functions] = cache['functions']
         next
       end

       event[:mtime] = mtime

      if event["date"].blank?
        event[:date] = event[:year].to_s
      else
        event[:date] = Event.parse_date(event["date"], now: Time.local(event[:year], 1, 1)).to_date.iso8601
        event[:date] ||= event["date"]
      end

      # Get event data, heat count, table info, and row counts in optimized queries
      begin
        # Single query to get both event name and full event data
        event_row = dbquery(event[:db], 'events').first
        event[:event] = event_row || {}
        event[:name] ||= event_row&.fetch('name', nil) || 'Showcase'
        
        # Single query to get heat count and table row counts via direct SQLite command
        dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
        
        # Build a comprehensive query that gets both heat count and all table row counts
        tables_query = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        tables_csv = `sqlite3 --csv --header #{dbpath}/#{event[:db]}.sqlite3 "#{tables_query}"`
        
        if !tables_csv.empty?
          table_names = CSV.parse(tables_csv, headers: true).map { |row| row['name'] }
          
          # Build counts query for all tables plus heat count
          counts_parts = table_names.map do |table_name|
            if table_name == 'entries'
              # For entries, count heats where number > 0
              "SELECT 'entries' as table_name, COUNT(*) as count FROM heats WHERE number > 0"
            elsif table_name == 'heats'
              # For heats, get both total count and distinct number count
              "SELECT 'heats' as table_name, COUNT(*) as count FROM heats UNION ALL SELECT 'heat_numbers' as table_name, COUNT(DISTINCT number) as count FROM heats WHERE number > 0"
            else
              "SELECT '#{table_name}' as table_name, COUNT(*) as count FROM [#{table_name}]"
            end
          end
          
          counts_query = counts_parts.join(' UNION ALL ')
          counts_csv = `sqlite3 --csv --header #{dbpath}/#{event[:db]}.sqlite3 "#{counts_query}"`
          
          event[:rows] = {}
          unless counts_csv.empty?
            CSV.parse(counts_csv, headers: true).each do |row|
              if row['table_name'] == 'heat_numbers'
                event[:heats] = row['count'].to_i
              else
                event[:rows][row['table_name']] = row['count'].to_i
              end
            end
          end
          
          # Fallback for heat count if not set
          event[:heats] ||= 0
        else
          event[:rows] = {}
          event[:heats] = 0
        end
        
        # Extract function information
        event[:functions] = {}
        FUNCTIONS.each do |function_key, function_def|
          begin
            result = `sqlite3 #{dbpath}/#{event[:db]}.sqlite3 "#{function_def[:query]}"`
            # Parse the result - SQLite returns 1 for true, 0 for false
            event[:functions][function_key] = result.strip == '1'
          rescue => func_error
            # If there's an error (e.g., table doesn't exist), assume false
            event[:functions][function_key] = false
          end
        end
        
      rescue => e
        # If there's an error, set defaults
        event[:event] = {}
        event[:name] ||= 'Showcase'
        event[:rows] = {}
        event[:heats] = 0
        event[:functions] = {}
        FUNCTIONS.keys.each { |key| event[:functions][key] = false }
      end
    end

    # Write complete data to cache BEFORE filtering
    File.write('tmp/inventory.json', JSON.pretty_generate(@events))

    # Create a copy for filtering (don't modify the original @events)
    filtered_events = @events.dup

    # Get list of database tables for filtering
    tables = ActiveRecord::Base.connection.tables

    # Filter events based on Event attributes and table row counts passed as parameters
    params.each do |param_name, param_value|
      next unless param_value.present?
      
      if Event.attribute_names.include?(param_name)
        # Handle Event attribute filtering
        filtered_events.select! do |event|
          event_data = event[:event] || {}
          event_data[param_name].to_s == param_value.to_s
        end
      elsif FUNCTIONS.keys.include?(param_name)
        # Handle function-based filtering
        # Supports: function_name=true, function_name=false
        expected_value = param_value.downcase == 'true'
        filtered_events.select! do |event|
          functions_data = event[:functions] || {}
          actual_value = functions_data[param_name] || false
          actual_value == expected_value
        end
      elsif tables.include?(param_name)
        # Handle table-based filtering with comparison operators
        # Supports: table_name>5, table_name>=10, table_name<3, table_name<=0, table_name=0
        table_name = param_name
        filter_value = param_value
        
        # Parse comparison operator and value
        if filter_value =~ /^(>=|<=|>|<|=)(\d+)$/
          operator = $1
          threshold = $2.to_i
          
          filtered_events.select! do |event|
            rows_data = event[:rows] || {}
            actual_count = rows_data[table_name] || 0
            
            case operator
            when '>'
              actual_count > threshold
            when '>='
              actual_count >= threshold
            when '<'
              actual_count < threshold
            when '<='
              actual_count <= threshold
            when '='
              actual_count == threshold
            else
              false
            end
          end
        elsif filter_value =~ /^\d+$/
          # Handle plain number as equality check
          threshold = filter_value.to_i
          filtered_events.select! do |event|
            rows_data = event[:rows] || {}
            actual_count = rows_data[table_name] || 0
            actual_count == threshold
          end
        end
      end
    end

    # Use filtered events for display
    @events = filtered_events

    @events.sort_by! {|event| event[:studio]}
    @events.reverse!
    @events.sort_by! {|event| event[:date]}
    @events.reverse!

    @events.sort_by! {|event| -event[:heats].to_i} if params[:sort] == 'heats'
    @events.sort_by! {|event| -(event[:rows]['people'] || 0)} if params[:sort] == 'people'
    @events.sort_by! {|event| -(event[:rows]['entries'] || 0)} if params[:sort] == 'entries'

    set_scope
  end

  def inventory_options
    
    # Load all events from tmp/inventory.json
    @events = JSON.parse(File.read('tmp/inventory.json')) rescue []
    
    
    # Group options by their values
    @option_counts = {}
    
    # Column order options
    @option_counts[:column_order] = {
      1 => { label: 'Lead, Follow', count: 0 },
      2 => { label: 'Student, Instructor (Lead, Follow for Amateur Couples)', count: 0 }
    }
    
    # Ballroom options
    @option_counts[:ballrooms] = {
      1 => { label: 'One ballroom', count: 0 },
      2 => { label: 'Two ballrooms: A: Amateur follower with instructor, B: Amateur leader (includes amateur couples)', count: 0 },
      3 => { label: 'Attempt to evenly split couples between ballrooms', count: 0 },
      4 => { label: 'Assign ballrooms by studio', count: 0 }
    }
    
    
    # Pro/Am options
    @option_counts[:pro_am] = {
      'G' => { label: 'L=Lady, G=Gentleman', count: 0 },
      'L' => { label: 'F=Follower, L=Leader', count: 0 }
    }
    
    # Heat order options
    @option_counts[:heat_order] = {
      'L' => { label: 'Newcomer to Advanced', count: 0 },
      'R' => { label: 'Random', count: 0 }
    }
    
    # Boolean options (only those on the Options settings page)
    boolean_options = [:intermix, :backnums, :track_ages, :include_open, :include_closed,
                      :pro_heats, :agenda_based_entries, :independent_instructors, :strict_scoring]
    
    boolean_options.each do |option|
      @option_counts[option] = {
        '1' => { label: 'Yes', count: 0 },
        '0' => { label: 'No', count: 0 }
      }
    end
    
    # Count events for each option
    @events.each do |event|
      event_data = event['event'] || {}
      
      @option_counts.each do |option_name, values|
        # Access with string key since JSON doesn't symbolize
        value = event_data[option_name.to_s]
        next if value.nil? || value == ""
        
        # Convert string numbers to integers for numeric options
        value = value.to_i if [:column_order, :ballrooms].include?(option_name)
        # Keep string values for boolean options ("0" or "1")
        if boolean_options.include?(option_name)
          value = value.to_s
        end
        # Keep string values for pro_am and heat_order
        value = value.to_s if [:pro_am, :heat_order].include?(option_name)
        
        if values[value]
          values[value][:count] += 1
        end
      end
    end
    
    set_scope
  end

  def inventory_judging
    
    # Load all events from tmp/inventory.json
    @events = JSON.parse(File.read('tmp/inventory.json')) rescue []
    
    # Group judging options by their values
    @option_counts = {}
    
    # Open scoring options
    @option_counts[:open_scoring] = {
      '1' => { label: '1/2/3/F', count: 0 },
      'G' => { label: 'GH/G/S/B', count: 0 },
      '#' => { label: 'Number (85, 95, ...)', count: 0 },
      '+' => { label: 'Feedback (Needs Work On / Great Job With)', count: 0 },
      '&' => { label: 'Number (1-5) and Feedback', count: 0 },
      '@' => { label: 'GH/G/S/B and Feedback', count: 0 },
      '0' => { label: 'None', count: 0 }
    }
    
    # Closed scoring options
    @option_counts[:closed_scoring] = {
      '1' => { label: '1/2/3/F', count: 0 },
      'G' => { label: 'GH/G/S/B', count: 0 },
      '#' => { label: 'Number (85, 95, ...)', count: 0 },
      '=' => { label: 'Same as Open', count: 0 }
    }
    
    # Multi scoring options
    @option_counts[:multi_scoring] = {
      1 => { label: '1/2/3/F', count: 0 },
      'G' => { label: 'GH/G/S/B', count: 0 },
      '#' => { label: 'Number (85, 95, ...)', count: 0 }
    }
    
    # Solo scoring options
    @option_counts[:solo_scoring] = {
      1 => { label: 'One number (0-100)', count: 0 },
      4 => { label: 'Technique, Execution, Poise, Showmanship (each 0-25)', count: 0 }
    }
    
    # Boolean judging options
    boolean_options = [:judge_comments, :judge_recordings, :assign_judges]
    
    boolean_options.each do |option|
      @option_counts[option] = {
        '1' => { label: 'Yes', count: 0 },
        '0' => { label: 'No', count: 0 }
      }
    end
    
    # Count events for each option
    @events.each do |event|
      event_data = event['event'] || {}
      
      @option_counts.each do |option_name, values|
        # Access with string key since JSON doesn't symbolize
        value = event_data[option_name.to_s]
        next if value.nil? || value == ""
        
        # Convert string numbers to integers for numeric options
        value = value.to_i if [:solo_scoring].include?(option_name)
        # Keep string values for multi_scoring and scoring options
        value = value.to_s if [:multi_scoring, :open_scoring, :closed_scoring].include?(option_name)
        # Keep string values for boolean options ("0" or "1")
        if boolean_options.include?(option_name)
          value = value.to_s
        end
        
        if values[value]
          values[value][:count] += 1
        end
      end
    end
    
    set_scope
  end

  def inventory_heats
    # Load all events from tmp/inventory.json
    @events = JSON.parse(File.read('tmp/inventory.json')) rescue []
    
    # Group heat options by their values
    @option_counts = {}
    
    # Max heat size - group by common sizes
    @option_counts[:max_heat_size] = {}
    
    # Heat range level - need to convert numeric values to meaningful labels
    @option_counts[:heat_range_level] = {}
    
    # Heat range age - need to convert numeric values to meaningful labels  
    @option_counts[:heat_range_age] = {}
    
    # Heat range category (open/closed) - 0 = separate, 1 = combined
    @option_counts[:heat_range_cat] = {
      0 => { label: 'Open and Closed ranges may differ', count: 0 },
      1 => { label: 'Combine Open and Closed', count: 0 }
    }
    
    # First pass: collect all unique values to build proper labels
    max_heat_sizes = Set.new
    heat_range_levels = Set.new
    heat_range_ages = Set.new
    
    @events.each do |event|
      event_data = event['event'] || {}
      
      # Collect max heat sizes
      size = event_data['max_heat_size']
      max_heat_sizes.add(size.to_i) if size && size != ""
      
      # Collect heat range levels
      level = event_data['heat_range_level']
      heat_range_levels.add(level.to_i) if level && level != ""
      
      # Collect heat range ages
      age = event_data['heat_range_age']
      heat_range_ages.add(age.to_i) if age && age != ""
    end
    
    # Build max heat size options
    max_heat_sizes.sort.each do |size|
      @option_counts[:max_heat_size][size] = { 
        label: size == 0 ? 'No limit' : "#{size} dancers per heat", 
        count: 0 
      }
    end
    
    # Build heat range level options - these are slider positions (0 = strictest, higher = more permissive)
    heat_range_levels.sort.each do |level|
      label = case level
              when 0 then 'Strictest level separation'
              when 1 then 'Allow one level difference'  
              when 2 then 'Allow two level difference'
              when 3 then 'Allow three level difference'
              else "Allow up to #{level} level difference"
              end
      @option_counts[:heat_range_level][level] = { label: label, count: 0 }
    end
    
    # Build heat range age options - these are slider positions (0 = strictest, higher = more permissive)
    heat_range_ages.sort.each do |age|
      label = case age
              when 0 then 'Strictest age separation'
              when 1 then 'Allow one age category difference'
              when 2 then 'Allow two age category difference'  
              when 3 then 'Allow three age category difference'
              else "Allow up to #{age} age category difference"
              end
      @option_counts[:heat_range_age][age] = { label: label, count: 0 }
    end
    
    # Count events for each option
    @events.each do |event|
      event_data = event['event'] || {}
      
      # Count max heat size
      size = event_data['max_heat_size']
      if size && size != ""
        size_int = size.to_i
        if @option_counts[:max_heat_size][size_int]
          @option_counts[:max_heat_size][size_int][:count] += 1
        end
      end
      
      # Count heat range level
      level = event_data['heat_range_level']
      if level && level != ""
        level_int = level.to_i
        if @option_counts[:heat_range_level][level_int]
          @option_counts[:heat_range_level][level_int][:count] += 1
        end
      end
      
      # Count heat range age
      age = event_data['heat_range_age']
      if age && age != ""
        age_int = age.to_i
        if @option_counts[:heat_range_age][age_int]
          @option_counts[:heat_range_age][age_int][:count] += 1
        end
      end
      
      # Count heat range category
      cat = event_data['heat_range_cat']
      if cat && cat != ""
        cat_int = cat.to_i
        if @option_counts[:heat_range_cat][cat_int]
          @option_counts[:heat_range_cat][cat_int][:count] += 1
        end
      end
    end
    
    set_scope
  end

  def inventory_tables
    # Load all events from tmp/inventory.json
    @events = JSON.parse(File.read('tmp/inventory.json')) rescue []
    
    # Define the tables we want to track
    @tracked_tables = %w[
      active_storage_blobs
      billables
      feedbacks
      age_costs
      cat_extensions
      formations
      multis
      package_includes
      scores
      songs
      studio_pairs
      recordings
      tables
    ].sort
    
    # Count events that have data in each table
    @table_counts = {}
    
    @tracked_tables.each do |table_name|
      @table_counts[table_name] = {
        count: 0,
        events: []
      }
      
      @events.each do |event|
        rows_data = event['rows'] || {}
        table_count = rows_data[table_name] || 0
        
        if table_count > 0
          @table_counts[table_name][:count] += 1
          @table_counts[table_name][:events] << {
            db: event['db'],
            studio: event['studio'],
            name: event['name'],
            date: event['date'],
            count: table_count
          }
        end
      end
      
      # Sort events by count descending
      @table_counts[table_name][:events].sort_by! { |e| -e[:count] }
    end
    
    set_scope
  end

  def inventory_functions
    # Load all events from tmp/inventory.json
    @events = JSON.parse(File.read('tmp/inventory.json')) rescue []
    
    # Count events that have each function enabled
    @function_counts = {}
    
    FUNCTIONS.keys.sort.each do |function_key|
      function_def = FUNCTIONS[function_key]
      @function_counts[function_key] = {
        name: function_def[:name],
        count: 0,
        events: []
      }
      
      @events.each do |event|
        functions_data = event['functions'] || {}
        
        if functions_data[function_key] == true
          @function_counts[function_key][:count] += 1
          @function_counts[function_key][:events] << {
            db: event['db'],
            studio: event['studio'],
            name: event['name'],
            date: event['date']
          }
        end
      end
      
      # Sort events by date descending
      @function_counts[function_key][:events].sort_by! { |e| e[:date] }.reverse!
    end
    
    set_scope
  end

private

  def set_scope
    @scope = ENV.fetch("RAILS_APP_SCOPE", '')
    @scope = '/' + @scope unless @scope.empty?
    @scope = ENV['RAILS_RELATIVE_URL_ROOT'] + '/' + @scope if ENV['RAILS_RELATIVE_URL_ROOT']
  end

  def parse_showcases(file)
    showcases = []

    YAML.load_file(file).each do |year, studios|
      studios.each do |token, studio|
        if studio[:events]
          studio[:events].each_with_index do |(event, info), index|
            showcases << [year, token, info[:name], index]
          end
        else
          showcases << [year, token, 'Showcase', -1]
        end
      end
    end

    showcases
  end
end
