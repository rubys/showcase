require 'set'

class TablesController < ApplicationController
  include Printable
  
  before_action :set_table, only: %i[ show edit update destroy ]
  before_action :set_option, only: %i[ index new create arrange assign studio move_person reset update_positions renumber ]

  # GET /tables or /tables.json
  def index
    @tables = Table.includes(people: :studio).where(option_id: @option&.id)
    @columns = Table.maximum(:col) || 8
    
    # Add capacity status for each table
    @tables.each do |table|
      # Get table size: individual table > option > event > default (10)
      table_size = table.size
      if table_size.nil? || table_size == 0
        if @option && @option.table_size && @option.table_size > 0
          table_size = @option.table_size
        elsif Event.current&.table_size && Event.current.table_size > 0
          table_size = Event.current.table_size
        else
          table_size = 10
        end
      end
      if table.option_id
        # For option tables, count people through person_options
        people_count = table.person_options.count
      else
        # For main event tables, count people directly
        people_count = table.people.count
      end
      
      table.define_singleton_method(:capacity_status) do
        if people_count < table_size
          :empty_seats
        elsif people_count == table_size
          :at_capacity
        else
          :over_capacity
        end
      end
      
      table.define_singleton_method(:people_count) { people_count }
      table.define_singleton_method(:table_size) { table_size }
    end
    
    # Get unassigned people (students, professionals, guests)
    if @option
      # For option tables, get people who have this option but no table assignment
      # Include Event Staff (Officials) for option tables since they can attend dinners/lunches
      @unassigned_people = Person.includes(:studio)
                                 .joins(:options)
                                 .where(person_options: { option_id: @option.id, table_id: nil })
                                 .where(type: ['Student', 'Professional', 'Guest', 'Official'])
                                 .order('studios.name, people.name')
    else
      # For main event tables, get people without any table assignment
      @unassigned_people = Person.includes(:studio)
                                 .where(table_id: nil)
                                 .where(type: ['Student', 'Professional', 'Guest'])
                                 .where.not(studio_id: 0)  # Exclude Event Staff
                                 .order('studios.name, people.name')
    end
    
    # If more than 10, group by studio for summary
    if @unassigned_people.count > 10
      @unassigned_by_studio = @unassigned_people.group_by(&:studio).map do |studio, people|
        {
          studio: studio,
          count: people.count,
          people: people
        }
      end.sort_by { |group| group[:studio].name }
    end
  end

  def arrange
    index
  end

  def studio
    @studio = Studio.find(params[:id])
    
    if @option
      # For option tables, find tables where people from this studio have this option
      @tables = Table.joins(:person_options => :person)
                     .where(person_options: { option_id: @option.id })
                     .where(people: { studio_id: @studio.id })
                     .distinct
                     .includes(:person_options => {:person => :studio})
                     .order(:number)
    else
      # For main event tables
      @tables = Table.joins(people: :studio)
                     .where(studios: { id: @studio.id })
                     .where(option_id: nil)
                     .distinct
                     .includes(people: :studio)
                     .order(:number)
    end
    
    @columns = Table.where(option_id: @option&.id).maximum(:col) || 8
    
    # Add capacity status for each table
    @tables.each do |table|
      table_size = table.size || Event.current&.table_size || 10
      if table.option_id
        # For option tables, count people through person_options
        people_count = table.person_options.count
      else
        # For main event tables, count people directly
        people_count = table.people.count
      end
      
      table.define_singleton_method(:capacity_status) do
        if people_count < table_size
          :empty_seats
        elsif people_count == table_size
          :at_capacity
        else
          :over_capacity
        end
      end
      
      table.define_singleton_method(:people_count) { people_count }
      table.define_singleton_method(:table_size) { table_size }
    end
  end

  # GET /tables/1 or /tables/1.json
  def show
  end

  # GET /tables/new
  def new
    @table = Table.new(option_id: @option&.id)
    @table.number = (Table.where(option_id: @option&.id).maximum(:number) || 0) + 1
    
    # Get studios that have unassigned people
    if @option
      # For option tables, get studios with people who have this option but no table
      # Include Event Staff for option tables
      @studios_with_unassigned = Studio.joins(:people => :options)
                                       .where(person_options: { option_id: @option.id, table_id: nil })
                                       .where(people: { type: ['Student', 'Professional', 'Guest', 'Official'] })
                                       .distinct
                                       .order(:name)
                                       .pluck(:id, :name)
    else
      # For main event tables, get studios with unassigned people
      @studios_with_unassigned = Studio.joins(:people)
                                       .where(people: { table_id: nil, type: ['Student', 'Professional', 'Guest'] })
                                       .where.not(id: 0)  # Exclude Event Staff
                                       .distinct
                                       .order(:name)
                                       .pluck(:id, :name)
    end
  end

  # GET /tables/1/edit
  def edit
    # Check if table has capacity for more people
    table_size = @table.size || Event.current&.table_size || 10
    table_size = 10 if table_size.nil? || table_size.zero?
    if @table.option_id
      # For option tables, count people through person_options
      current_people_count = @table.person_options.count
    else
      # For main event tables, count people directly
      current_people_count = @table.people.count
    end
    
    # Only show studio selection if table isn't at capacity
    if current_people_count < table_size
      @studios_with_unassigned = Studio.joins(:people)
                                       .where(people: { table_id: nil, type: ['Student', 'Professional', 'Guest'] })
                                       .where.not(id: 0)  # Exclude Event Staff
                                       .distinct
                                       .order(:name)
                                       .pluck(:id, :name)
      @available_seats = table_size - current_people_count
    end
  end

  # POST /tables or /tables.json
  def create
    @table = Table.new(table_params.except(:studio_id))
    @table.option_id = @option&.id

    respond_to do |format|
      if @table.save
        # Auto-fill table with people from selected studio if provided
        if params[:table][:studio_id].present?
          studio_id = params[:table][:studio_id].to_i
          fill_table_with_studio_people(@table, studio_id)
        end
        
        format.html { redirect_to tables_path(option_id: @option&.id), notice: "Table was successfully created." }
        format.json { render :show, status: :created, location: @table }
      else
        # Reload studio data for the form in case of errors
        @studios_with_unassigned = Studio.joins(:people)
                                         .where(people: { table_id: nil, type: ['Student', 'Professional', 'Guest'] })
                                         .where.not(id: 0)
                                         .distinct
                                         .order(:name)
                                         .pluck(:id, :name)
        
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @table.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /tables/1 or /tables/1.json
  def update
    respond_to do |format|
      # Check if we're changing the number and if there's a conflict
      new_number = table_params[:number].to_i
      if new_number != @table.number && Table.exists?(number: new_number)
        # Swap numbers with the existing table
        Table.transaction do
          other_table = Table.find_by(number: new_number)
          old_number = @table.number
          
          # Temporarily set the current table to 0 to avoid uniqueness constraint
          @table.update!(number: 0)
          
          # Update the other table to the old number
          other_table.update!(number: old_number)
          
          # Update the current table to the new number
          if @table.update(table_params.except(:studio_id))
            # Auto-fill table with people from selected studio if provided
            if params[:table][:studio_id].present?
              studio_id = params[:table][:studio_id].to_i
              fill_table_with_studio_people(@table, studio_id)
            end
            
            format.html { redirect_to tables_path(option_id: @table.option_id), notice: "Table was successfully updated. Swapped numbers with Table #{old_number}." }
            format.json { render :show, status: :ok, location: @table }
          else
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: @table.errors, status: :unprocessable_entity }
          end
        end
      elsif @table.update(table_params.except(:studio_id))
        # Auto-fill table with people from selected studio if provided
        if params[:table][:studio_id].present?
          studio_id = params[:table][:studio_id].to_i
          fill_table_with_studio_people(@table, studio_id)
        end
        
        format.html { redirect_to tables_path(option_id: @table.option_id), notice: "Table was successfully updated." }
        format.json { render :show, status: :ok, location: @table }
      else
        # Reload studio data for the form in case of errors
        table_size = @table.size || Event.current&.table_size || 10
        table_size = 10 if table_size.nil? || table_size.zero?
        if @table.option_id
          # For option tables, count people through person_options
          current_people_count = @table.person_options.count
        else
          # For main event tables, count people directly
          current_people_count = @table.people.count
        end
        
        if current_people_count < table_size
          @studios_with_unassigned = Studio.joins(:people)
                                           .where(people: { table_id: nil, type: ['Student', 'Professional', 'Guest'] })
                                           .where.not(id: 0)
                                           .distinct
                                           .order(:name)
                                           .pluck(:id, :name)
          @available_seats = table_size - current_people_count
        end
        
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @table.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /tables/1 or /tables/1.json
  def destroy
    @table.destroy!

    respond_to do |format|
      format.html { redirect_to tables_path(option_id: @table.option_id), status: :see_other, notice: "Table was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def update_positions
    if params[:commit] == 'Reset'
      Table.where(option_id: @option&.id).update_all(row: nil, col: nil)
      redirect_to tables_url(option_id: @option&.id), notice: "Table positions reset."
    else
      Table.transaction do
        # First, collect all table IDs that are being updated
        table_ids = params[:table].keys
        
        # Clear positions for all tables being updated to avoid constraint violations
        Table.where(id: table_ids, option_id: @option&.id).update_all(row: nil, col: nil)
        
        # Now apply the new positions
        params[:table].each do |id, position|
          table = Table.find(id)
          table.row = position['row'].to_i
          table.col = position['col'].to_i
          table.save! validate: false
        end
      end

      render plain: "Table positions updated"
    end
  end

  def assign
    Table.transaction do
      # Remove all existing tables for this option context
      if @option
        # For option tables, also clear table_id from person_options
        PersonOption.where(option_id: @option.id).update_all(table_id: nil)
        Table.where(option_id: @option.id).destroy_all
      else
        # For main event, clear people's table_id (dependent: :nullify will handle this)
        Table.where(option_id: nil).destroy_all
      end
      
      # Get table size: option > event > default (10)
      event = Event.first
      if @option && @option.table_size && @option.table_size > 0
        table_size = @option.table_size
      elsif event && event.table_size && event.table_size > 0
        table_size = event.table_size
      else
        table_size = 10
      end
      
      # Get people based on context
      if @option
        # For option tables, get people who have registered for this option
        people = Person.joins(:studio, :options)
                       .where(person_options: { option_id: @option.id })
                       .order('studios.name, people.name')
      else
        # For main event tables, get all people
        people = Person.joins(:studio).order('studios.name, people.name')
      end
      
      # TWO-PHASE ALGORITHM
      # Phase 1: Group people into tables (who sits together)
      people_groups = group_people_into_tables(people, table_size)
      
      # Phase 2: Place groups on grid (where tables go)
      created_tables = place_groups_on_grid(people_groups)
      
      # Renumber tables sequentially based on their final positions
      renumber_tables_by_position
      
    end
    
    redirect_to tables_path(option_id: @option&.id), notice: "Tables have been assigned successfully."
  end

  def renumber
    Table.transaction do
      # Get all tables ordered by their position (row first, then column)
      # Tables without positions will be at the end
      tables_by_position = Table.where(option_id: @option&.id).order(Arel.sql('row IS NULL, row, col IS NULL, col'))
      
      # First, temporarily set all numbers to negative values to avoid conflicts
      tables_by_position.each_with_index do |table, index|
        table.update!(number: -(index + 1))
      end
      
      # Then set them to their final positive values
      tables_by_position.each_with_index do |table, index|
        table.update!(number: index + 1)
      end
    end
    
    redirect_to arrange_tables_path(option_id: @option&.id), notice: "Tables have been renumbered successfully."
  end

  def list
    @event = Event.current
    @font_size = @event.font_size
    
    # Get main event tables (where option_id is nil)
    @main_tables = Table.includes(people: :studio).where(option_id: nil).order(:number)
    
    # Find unseated people
    @unseated_people = {}
    
    # Get all distinct option_ids that have tables
    option_ids_with_tables = Table.distinct.pluck(:option_id)
    
    # Process each option that has tables
    option_ids_with_tables.each do |option_id|
      if option_id.nil?
        # For main event (option_id = nil), find people without a table
        unseated = Person.includes(:studio)
                         .where(table_id: nil)
                         .where(type: ['Student', 'Professional', 'Guest'])
                         .order('studios.name, people.name')
        
        if unseated.any?
          @unseated_people[:main_event] = {
            name: "Main Event",
            people: unseated
          }
        end
      else
        # For specific options, find people who have the option but no table assignment
        option = Billable.find(option_id)
        unseated = Person.includes(:studio, :options)
                         .joins(:options)
                         .where(person_options: { option_id: option_id, table_id: nil })
                         .order('studios.name, people.name')
        
        if unseated.any?
          @unseated_people[option_id] = {
            name: option.name,
            people: unseated
          }
        end
      end
    end
    
    # Get all options with their tables
    @options_with_tables = []
    Billable.where(type: 'Option').order(:order, :name).each do |option|
      tables = Table.includes(:person_options => {:person => :studio})
                    .where(option_id: option.id)
                    .order(:number)
      
      # Only include options that have tables
      if tables.any?
        @options_with_tables << {
          option: option,
          tables: tables
        }
      end
    end
    
    # Analyze table assignments for issues
    @table_issues = analyze_table_contiguousness
    
    @nologo = true

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: "table-list"
      end
    end
  end

  def reset
    if @option
      # For option tables, also clear table assignments in person_options
      PersonOption.where(option_id: @option.id).update_all(table_id: nil)
      Table.where(option_id: @option.id).destroy_all
    else
      Table.where(option_id: nil).destroy_all
    end
    redirect_to tables_path(option_id: @option&.id), notice: "All tables have been deleted."
  end

  def move_person
    # Ignore requests to move tables
    return head :ok if params[:source].start_with?('table-')
    
    person_id = params[:source].gsub('person-', '').to_i
    
    # Handle both dropping on a table or on another person
    if params[:target].start_with?('table-')
      # Dropped directly on a table
      table_id = params[:target].gsub('table-', '').to_i
      table = Table.find(table_id)
    else
      # Dropped on another person - move to that person's table
      target_person_id = params[:target].gsub('person-', '').to_i
      target_person = Person.find(target_person_id)
      
      if @option
        # For option tables, find the table through person_options
        person_option = PersonOption.find_by(person_id: target_person_id, option_id: @option.id)
        table = person_option&.table
      else
        table = target_person.table
      end
    end
    
    person = Person.find(person_id)
    
    # Update the person's table assignment
    if @option
      # For option tables, update the person_options record
      PersonOption.where(person_id: person.id, option_id: @option.id).update_all(table_id: table&.id)
    else
      # For main event tables, update the person's table_id
      person.update!(table_id: table&.id)
    end
    
    # Refresh the data for the studio view
    @studio = person.studio
    if @option
      @tables = Table.joins(:person_options => :person)
                     .where(person_options: { option_id: @option.id })
                     .where(people: { studio_id: @studio.id })
                     .distinct
                     .includes(:person_options => {:person => :studio})
                     .order(:number)
    else
      @tables = Table.joins(people: :studio)
                     .where(studios: { id: @studio.id })
                     .where(option_id: nil)
                     .distinct
                     .includes(people: :studio)
                     .order(:number)
    end
    
    # Add capacity status for each table (same as studio action)
    @tables.each do |table|
      table_size = table.size || Event.current&.table_size || 10
      if table.option_id
        # For option tables, count people through person_options
        people_count = table.person_options.count
      else
        # For main event tables, count people directly
        people_count = table.people.count
      end
      
      table.define_singleton_method(:capacity_status) do
        if people_count < table_size
          :empty_seats
        elsif people_count == table_size
          :at_capacity
        else
          :over_capacity
        end
      end
      
      table.define_singleton_method(:people_count) { people_count }
      table.define_singleton_method(:table_size) { table_size }
    end
    
    # Return a Turbo Stream response to update both notice and tables
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("notice", "<p class=\"py-2 px-3 bg-green-50 mb-5 text-green-500 font-medium rounded-lg inline-block\" id=\"notice\">#{person.name} moved to Table #{table.number}</p>"),
          turbo_stream.replace("studio-tables", partial: "studio_tables")
        ]
      end
      format.html do
        render plain: "#{person.name} moved to Table #{table.number}"
      end
    end
  end

  private

  def analyze_table_contiguousness
    issues = []
    
    # Get all billable options that have tables
    option_ids_with_tables = Table.distinct.pluck(:option_id)
    
    option_ids_with_tables.each do |option_id|
      option = option_id ? Billable.find(option_id) : nil
      option_name = option ? option.name : "Main Event"
      
      # Get all tables for this option
      tables = Table.where(option_id: option_id).includes(:people, :person_options)
      
      # Group tables by studio for analysis
      studio_tables = {}
      
      tables.each do |table|
        # Get people for this table based on context
        people = if option_id
          # For option tables, get people through person_options
          table.person_options.includes(:person => :studio).map(&:person)
        else
          # For main event tables, get people directly
          table.people.includes(:studio)
        end
        
        # Group people by studio
        people.group_by(&:studio_id).each do |studio_id, studio_people|
          next if studio_id == 0 # Skip Event Staff
          
          studio_tables[studio_id] ||= []
          studio_tables[studio_id] << {
            table: table,
            people_count: studio_people.count,
            studio_name: studio_people.first.studio.name
          }
        end
      end
      
      # Check for studios with multiple tables
      studio_tables.each do |studio_id, table_data|
        next if table_data.length <= 1
        
        studio_name = table_data.first[:studio_name]
        table_numbers = table_data.map { |td| td[:table].number }.sort
        
        # Check if table numbers are contiguous
        unless contiguous_numbers?(table_numbers)
          issues << {
            type: :non_contiguous_studio,
            option: option_name,
            studio: studio_name,
            tables: table_numbers
          }
        end
        
        # Check if table positions are contiguous (adjacent)
        tables_with_positions = table_data.map { |td| td[:table] }.select { |t| t.row && t.col }
        if tables_with_positions.length > 1 && !contiguous?(tables_with_positions)
          positions = tables_with_positions.map { |t| "#{t.number}(#{t.row},#{t.col})" }
          issues << {
            type: :non_contiguous_studio,
            option: option_name,
            studio: studio_name,
            tables: positions
          }
        end
      end
      
      # Check studio pairs for adjacency
      StudioPair.includes(:studio1, :studio2).each do |pair|
        studio1_tables = studio_tables[pair.studio1.id] || []
        studio2_tables = studio_tables[pair.studio2.id] || []
        
        next if studio1_tables.empty? || studio2_tables.empty?
        
        # Check if any table from studio1 is adjacent to any table from studio2
        adjacent_found = false
        min_distance = Float::INFINITY
        
        studio1_tables.each do |s1_data|
          studio2_tables.each do |s2_data|
            table1 = s1_data[:table]
            table2 = s2_data[:table]
            
            if table1.row && table1.col && table2.row && table2.col
              # Calculate Manhattan distance
              distance = (table1.row - table2.row).abs + (table1.col - table2.col).abs
              min_distance = [min_distance, distance].min
              if distance <= 1
                adjacent_found = true
                break
              end
            end
          end
          break if adjacent_found
        end
        
        unless adjacent_found
          issues << {
            type: :non_adjacent_pair,
            option: option_name,
            studio1: pair.studio1.name,
            studio2: pair.studio2.name,
            distance: min_distance == Float::INFINITY ? "N/A" : min_distance
          }
        end
      end
    end
    
    issues
  end

  def contiguous_numbers?(numbers)
    return true if numbers.length <= 1
    
    numbers.each_cons(2).all? { |a, b| b == a + 1 }
  end

  def contiguous?(tables_with_positions)
    return true if tables_with_positions.length <= 1
    
    if tables_with_positions.length == 2
      # For 2 tables, check if they're adjacent (Manhattan distance = 1)
      table1, table2 = tables_with_positions
      distance = (table1.row - table2.row).abs + (table1.col - table2.col).abs
      return distance == 1
    else
      # For 3+ tables, check if they form a connected group
      return positions_form_connected_group(tables_with_positions)
    end
  end

  def positions_form_connected_group(tables_with_positions)
    positions = tables_with_positions.map { |t| [t.row, t.col] }.to_set
    
    # Start with the first position
    visited = Set.new
    to_visit = [positions.first]
    
    while !to_visit.empty?
      current = to_visit.pop
      next if visited.include?(current)
      
      visited.add(current)
      
      # Check all 4 adjacent positions
      row, col = current
      adjacent_positions = [
        [row - 1, col], [row + 1, col],
        [row, col - 1], [row, col + 1]
      ]
      
      adjacent_positions.each do |adj_pos|
        if positions.include?(adj_pos) && !visited.include?(adj_pos)
          to_visit << adj_pos
        end
      end
    end
    
    # All positions should be visited if they form a connected group
    visited.size == positions.size
  end

  def fill_table_with_studio_people(table, studio_id)
    # Determine table size
    table_size = table.size || Event.current&.table_size || 10
    table_size = 10 if table_size.nil? || table_size.zero?
    
    # Calculate available seats
    if table.option_id
      # For option tables, count people assigned via person_options
      current_people_count = PersonOption.where(table_id: table.id).count
    else
      # For main event tables, count people assigned directly
      current_people_count = table.people.count
    end
    available_seats = table_size - current_people_count
    
    # Don't add anyone if table is at or over capacity
    return if available_seats <= 0
    
    if table.option_id
      # Get unassigned people from the studio who have this option
      # Include Officials (Event Staff) for option tables
      unassigned_people = Person.joins(:options)
                                .where(studio_id: studio_id, type: ['Student', 'Professional', 'Guest', 'Official'])
                                .where(person_options: { option_id: table.option_id, table_id: nil })
                                .order(:name)
                                .limit(available_seats)
      
      # Assign them to the table via person_options
      unassigned_people.each do |person|
        PersonOption.where(person_id: person.id, option_id: table.option_id).update_all(table_id: table.id)
      end
    else
      # Get unassigned people from the studio for main event
      unassigned_people = Person.where(studio_id: studio_id, table_id: nil, type: ['Student', 'Professional', 'Guest'])
                                .order(:name)
                                .limit(available_seats)
      
      # Assign them to the table
      unassigned_people.each do |person|
        person.update!(table_id: table.id)
      end
    end
  end

  def create_and_assign_table(number, people)
    table = Table.create!(number: number, option_id: @option&.id)
    if @option
      # For option tables, update the person_options record
      people.each do |person|
        PersonOption.where(person_id: person.id, option_id: @option.id).update_all(table_id: table.id)
      end
    else
      # For main event tables, update the person's table_id
      people.each { |person| person.update!(table_id: table.id) }
    end
    table
  end
  
  def find_contiguous_block_for_studio(required_spots, positions, max_cols)
    # Find the best contiguous block for a studio's tables
    occupied = Set.new(positions.map { |p| "#{p[:row]},#{p[:col]}" })
    
    best_options = []
    
    # For 2 tables, try both horizontal and vertical
    if required_spots == 2
      # Try horizontal pairs - scan all rows systematically
      (1..5).each do |row|
        (1..max_cols-1).each do |col|
          if !occupied.include?("#{row},#{col}") && !occupied.include?("#{row},#{col+1}")
            # Prefer earlier positions (lower row, then lower col)
            best_options << { row: row, col: col, layout: :horizontal, score: row * 100 + col }
          end
        end
      end
      
      # Try vertical pairs - scan all positions systematically
      (1..4).each do |row|
        (1..max_cols).each do |col|
          if !occupied.include?("#{row},#{col}") && !occupied.include?("#{row+1},#{col}")
            # Slightly prefer horizontal over vertical by adding small penalty
            best_options << { row: row, col: col, layout: :vertical, score: row * 100 + col + 0.5 }
          end
        end
      end
    else
      # For 3+ tables, look for 2x2 blocks and L-shapes
      (1..4).each do |row|
        (1..max_cols-1).each do |col|
          all_free = true
          (0...required_spots).each do |idx|
            r = row + (idx / 2)
            c = col + (idx % 2)
            if r > 5 || c > max_cols || occupied.include?("#{r},#{c}")
              all_free = false
              break
            end
          end
          
          if all_free
            best_options << { row: row, col: col, layout: :block, score: row * 100 + col }
          end
        end
      end
      
      # If no perfect block found, try L-shapes and other patterns
      if best_options.empty? && required_spots <= 4
        # Try L-shape patterns for 3-4 tables
        (1..4).each do |row|
          (1..max_cols-1).each do |col|
            # L-shape: positions (0,0), (0,1), (1,0)
            l_positions = [[0,0], [0,1], [1,0]]
            if required_spots == 4
              l_positions << [1,1]  # Make it a 2x2 block
            end
            
            all_free = true
            l_positions.each do |dr, dc|
              r = row + dr
              c = col + dc
              if r > 5 || c > max_cols || occupied.include?("#{r},#{c}")
                all_free = false
                break
              end
            end
            
            if all_free
              best_options << { row: row, col: col, layout: :l_shape, score: row * 100 + col + 10 }
            end
          end
        end
      end
    end
    
    # Return the best option (prefer positions higher and to the left)
    best_option = best_options.min_by { |opt| opt[:score] }
    
    # If no perfect contiguous block found, try to find the best scattered adjacent positions
    if best_option.nil? && required_spots == 2
      # Try to find any two adjacent positions, even if not in a perfect block
      (1..5).each do |row|
        (1..max_cols).each do |col|
          pos1 = { row: row, col: col }
          pos1_key = "#{row},#{col}"
          next if occupied.include?(pos1_key)
          
          # Check all adjacent positions
          adjacent_candidates = [
            { row: row, col: col + 1 },     # Right
            { row: row, col: col - 1 },     # Left  
            { row: row + 1, col: col },     # Below
            { row: row - 1, col: col }      # Above
          ]
          
          adjacent_candidates.each do |pos2|
            next if pos2[:row] < 1 || pos2[:row] > 5 || pos2[:col] < 1 || pos2[:col] > max_cols
            pos2_key = "#{pos2[:row]},#{pos2[:col]}"
            next if occupied.include?(pos2_key)
            
            # Found two adjacent positions
            layout = (pos1[:row] == pos2[:row]) ? :horizontal : :vertical
            score = row * 100 + col + (layout == :vertical ? 0.5 : 0)
            return { row: row, col: col, layout: layout, score: score }
          end
        end
      end
    end
    
    best_option
  end

  def find_closest_position_to_group(placed_positions, positions, max_cols)
    # Find the available position that is closest to any of the placed positions
    return find_next_position(positions, max_cols) if placed_positions.empty?
    
    # First, try to find adjacent positions (distance = 1)
    placed_positions.each do |placed_pos|
      adjacent_candidates = [
        { row: placed_pos[:row] - 1, col: placed_pos[:col] },     # Above
        { row: placed_pos[:row] + 1, col: placed_pos[:col] },     # Below
        { row: placed_pos[:row], col: placed_pos[:col] - 1 },     # Left
        { row: placed_pos[:row], col: placed_pos[:col] + 1 }      # Right
      ]
      
      adjacent_candidates.each do |pos|
        # Check if position is valid and available
        if pos[:row] >= 1 && pos[:row] <= 5 && pos[:col] >= 1 && pos[:col] <= max_cols &&
           !positions.any? { |p| p[:row] == pos[:row] && p[:col] == pos[:col] }
          return pos
        end
      end
    end
    
    # If no adjacent positions found, find the closest available position
    best_position = nil
    best_distance = Float::INFINITY
    
    # Check all available positions
    (1..5).each do |row|
      (1..max_cols).each do |col|
        pos = { row: row, col: col }
        
        # Skip if position is already occupied
        next if positions.any? { |p| p[:row] == row && p[:col] == col }
        
        # Calculate minimum distance to any placed position from this studio
        min_distance = placed_positions.map { |placed_pos| 
          (pos[:row] - placed_pos[:row]).abs + (pos[:col] - placed_pos[:col]).abs 
        }.min
        
        if min_distance < best_distance
          best_distance = min_distance
          best_position = pos
        end
      end
    end
    
    best_position
  end

  
  def renumber_tables_by_position
    # Get all tables ordered by their position (row first, then column)
    tables_by_position = Table.where(option_id: @option&.id).order(:row, :col)
    
    # First, temporarily set all numbers to negative values to avoid conflicts
    tables_by_position.each_with_index do |table, index|
      table.update!(number: -(index + 1))
    end
    
    # Then set them to their final positive values
    tables_by_position.each_with_index do |table, index|
      table.update!(number: index + 1)
    end
  end
  
  def group_people_into_tables(people, table_size)
    # Phase 1: Group people into tables (who sits together)
    # Returns: Array of hashes with people and metadata
    
    # Group people by studio
    studio_groups = people.group_by(&:studio_id).map do |studio_id, studio_people|
      {
        studio_id: studio_id,
        people: studio_people,
        size: studio_people.size,
        studio_name: studio_people.first.studio.name
      }
    end
    
    people_groups = []  # Now stores hashes with metadata, not just arrays of people
    
    # 1. Handle Event Staff (studio_id = 0) first - keep them together
    event_staff_group = studio_groups.find { |g| g[:studio_id] == 0 }
    if event_staff_group
      if event_staff_group[:size] <= table_size
        # All Event Staff fit on one table
        people_groups << {
          people: event_staff_group[:people],
          studio_id: 0,
          studio_name: 'Event Staff',
          split_group: nil
        }
      else
        # Event Staff need multiple tables - keep them adjacent
        split_index = 0
        event_staff_group[:people].each_slice(table_size) do |people_slice|
          people_groups << {
            people: people_slice,
            studio_id: 0,
            studio_name: 'Event Staff',
            split_group: "event_staff_#{split_index}",
            split_total: (event_staff_group[:size] / table_size.to_f).ceil
          }
          split_index += 1
        end
      end
      studio_groups.reject! { |g| g[:studio_id] == 0 }
    end
    
    # 2. Handle studio pairs
    studio_pairs = StudioPair.includes(:studio1, :studio2).map do |pair|
      [pair.studio1.id, pair.studio2.id]
    end
    
    pair_lookup = {}
    studio_pairs.each do |id1, id2|
      pair_lookup[id1] = id2
      pair_lookup[id2] = id1
    end
    
    assigned_studios = Set.new
    remainder_groups = []  # Initialize early for studio pair overflow handling
    
    # Handle paired studios with enhanced logic for near-full tables
    studio_groups.each do |group|
      next if assigned_studios.include?(group[:studio_id])
      
      paired_studio_id = pair_lookup[group[:studio_id]]
      if paired_studio_id
        paired_group = studio_groups.find { |g| g[:studio_id] == paired_studio_id }
        
        if paired_group && !assigned_studios.include?(paired_studio_id)
          combined_size = group[:size] + paired_group[:size]
          
          if combined_size <= table_size
            # Both studios fit on one table
            people_groups << {
              people: group[:people] + paired_group[:people],
              studio_id: group[:studio_id],
              studio_name: "#{group[:studio_name]} & #{paired_group[:studio_name]}",
              is_paired: true,
              paired_studios: [group[:studio_id], paired_studio_id],
              split_group: nil
            }
            assigned_studios.add(group[:studio_id])
            assigned_studios.add(paired_studio_id)
          elsif (group[:size] == table_size && paired_group[:size] <= 3) ||
                (paired_group[:size] == table_size && group[:size] <= 3)
            # Special case: One studio exactly fills a table, but paired studio is small
            # Better to combine them and let larger studio split if needed
            # Example: Columbia (12) + Silver Spring (2) = 14, fits in table of 12 with 2 overflow
            all_people = group[:people] + paired_group[:people]
            
            # First table gets full capacity
            people_groups << {
              people: all_people.first(table_size),
              studio_id: group[:studio_id],
              studio_name: "#{group[:studio_name]} & #{paired_group[:studio_name]}",
              is_paired: true,
              paired_studios: [group[:studio_id], paired_studio_id],
              split_group: "paired_#{group[:studio_id]}_0",
              split_total: (combined_size / table_size.to_f).ceil
            }
            
            # Remainder goes to overflow handling
            if combined_size > table_size
              overflow = all_people.drop(table_size)
              remainder_groups << {
                studio_id: group[:size] > paired_group[:size] ? group[:studio_id] : paired_group[:studio_id],
                people: overflow,
                size: overflow.size,
                studio_name: group[:size] > paired_group[:size] ? group[:studio_name] : paired_group[:studio_name]
              }
            end
            
            assigned_studios.add(group[:studio_id])
            assigned_studios.add(paired_studio_id)
          else
            # Handle paired studios that exceed table size - treat as coordinated group
            # Example: Studio1(10) + Studio2(10) = 20 people, or Studio1(10) + Studio2(4) = 14 people
            # Each studio gets its own table(s), but they should be placed adjacent
            
            # Process the first studio
            if group[:size] <= table_size
              people_groups << {
                people: group[:people],
                studio_id: group[:studio_id],
                studio_name: group[:studio_name],
                split_group: nil,
                paired_with: paired_studio_id,
                coordination_group: "pair_#{[group[:studio_id], paired_studio_id].sort.join('_')}"
              }
            else
              # First studio needs multiple tables
              full_table_count = group[:size] / table_size
              remainder_size = group[:size] % table_size
              split_index = 0
              total_tables_needed = (group[:size] / table_size.to_f).ceil
              
              group[:people].first(full_table_count * table_size).each_slice(table_size) do |people_slice|
                people_groups << {
                  people: people_slice,
                  studio_id: group[:studio_id],
                  studio_name: group[:studio_name],
                  split_group: "studio_#{group[:studio_id]}_#{split_index}",
                  split_total: total_tables_needed,
                  split_index: split_index,
                  paired_with: paired_studio_id,
                  coordination_group: "pair_#{[group[:studio_id], paired_studio_id].sort.join('_')}"
                }
                split_index += 1
              end
              
              # Handle remainder if any
              if remainder_size > 0
                remainder_groups << {
                  studio_id: group[:studio_id],
                  people: group[:people].last(remainder_size),
                  size: remainder_size,
                  studio_name: group[:studio_name],
                  split_group: "studio_#{group[:studio_id]}_#{split_index}",
                  split_total: total_tables_needed,
                  split_index: split_index,
                  is_remainder: true,
                  paired_with: paired_studio_id,
                  coordination_group: "pair_#{[group[:studio_id], paired_studio_id].sort.join('_')}"
                }
              end
            end
            
            # Process the second studio
            if paired_group[:size] <= table_size
              people_groups << {
                people: paired_group[:people],
                studio_id: paired_group[:studio_id],
                studio_name: paired_group[:studio_name],
                split_group: nil,
                paired_with: group[:studio_id],
                coordination_group: "pair_#{[group[:studio_id], paired_studio_id].sort.join('_')}"
              }
            else
              # Second studio needs multiple tables
              full_table_count = paired_group[:size] / table_size
              remainder_size = paired_group[:size] % table_size
              split_index = 0
              total_tables_needed = (paired_group[:size] / table_size.to_f).ceil
              
              paired_group[:people].first(full_table_count * table_size).each_slice(table_size) do |people_slice|
                people_groups << {
                  people: people_slice,
                  studio_id: paired_group[:studio_id],
                  studio_name: paired_group[:studio_name],
                  split_group: "studio_#{paired_group[:studio_id]}_#{split_index}",
                  split_total: total_tables_needed,
                  split_index: split_index,
                  paired_with: group[:studio_id],
                  coordination_group: "pair_#{[group[:studio_id], paired_studio_id].sort.join('_')}"
                }
                split_index += 1
              end
              
              # Handle remainder if any
              if remainder_size > 0
                remainder_groups << {
                  studio_id: paired_group[:studio_id],
                  people: paired_group[:people].last(remainder_size),
                  size: remainder_size,
                  studio_name: paired_group[:studio_name],
                  split_group: "studio_#{paired_group[:studio_id]}_#{split_index}",
                  split_total: total_tables_needed,
                  split_index: split_index,
                  is_remainder: true,
                  paired_with: group[:studio_id],
                  coordination_group: "pair_#{[group[:studio_id], paired_studio_id].sort.join('_')}"
                }
              end
            end
            
            assigned_studios.add(group[:studio_id])
            assigned_studios.add(paired_studio_id)
          end
        end
      end
    end
    
    # 3. Handle large studios (need multiple tables)
    unassigned_groups = studio_groups.reject { |g| assigned_studios.include?(g[:studio_id]) }
    unassigned_groups.sort_by! { |g| -g[:size] }
    
    unassigned_groups.each do |group|
      next if assigned_studios.include?(group[:studio_id])
      
      if group[:size] <= table_size
        # Studio fits on one table - save for optimal packing
        remainder_groups << group
      else
        # Large studio needs multiple tables
        full_table_count = group[:size] / table_size
        remainder_size = group[:size] % table_size
        
        # Create full tables
        split_index = 0
        total_tables_needed = (group[:size] / table_size.to_f).ceil
        group[:people].first(full_table_count * table_size).each_slice(table_size) do |people_slice|
          people_groups << {
            people: people_slice,
            studio_id: group[:studio_id],
            studio_name: group[:studio_name],
            split_group: "studio_#{group[:studio_id]}_#{split_index}",
            split_total: total_tables_needed,
            split_index: split_index
          }
          split_index += 1
        end
        
        # If there's a remainder, save it for packing
        if remainder_size > 0
          remainder_groups << {
            studio_id: group[:studio_id],
            people: group[:people].last(remainder_size),
            size: remainder_size,
            studio_name: group[:studio_name],
            split_group: "studio_#{group[:studio_id]}_#{split_index}",
            split_total: total_tables_needed,
            split_index: split_index,
            is_remainder: true
          }
        end
      end
      
      assigned_studios.add(group[:studio_id])
    end
    
    # 4. Optimize remainder packing with studio pair preference
    # First pass: Handle studio pairs with absolute priority
    processed_studios = Set.new
    
    remainder_groups.dup.each do |group|
      next if processed_studios.include?(group[:studio_id])
      
      paired_studio_id = pair_lookup[group[:studio_id]]
      if paired_studio_id
        paired_remainder = remainder_groups.find { |g| g[:studio_id] == paired_studio_id && !processed_studios.include?(g[:studio_id]) }
        
        if paired_remainder && (group[:size] + paired_remainder[:size]) <= table_size
          # Create shared table for studio pair
          shared_table = group[:people] + paired_remainder[:people]
          remaining_capacity = table_size - shared_table.size
          
          # Fill remaining capacity with other non-paired studios
          remainder_groups.dup.each do |other_group|
            next if processed_studios.include?(other_group[:studio_id])
            next if other_group[:studio_id] == group[:studio_id] || other_group[:studio_id] == paired_studio_id
            next if pair_lookup[other_group[:studio_id]] # Skip studios that have pairs (they'll get their own pass)
            next if other_group[:studio_id] == 0 # Skip Event Staff - they should never be merged
            next if group[:studio_id] == 0 || paired_studio_id == 0 # Skip if this is an Event Staff table
            
            if other_group[:size] <= remaining_capacity
              shared_table.concat(other_group[:people])
              remaining_capacity -= other_group[:size]
              remainder_groups.delete(other_group)
              processed_studios.add(other_group[:studio_id])
              
              break if remaining_capacity < 1
            end
          end
          
          people_groups << {
            people: shared_table,
            studio_id: group[:studio_id],
            studio_name: "#{group[:studio_name]} & #{paired_remainder[:studio_name]}",
            is_paired: true,
            paired_studios: [group[:studio_id], paired_studio_id],
            split_group: group[:split_group] || paired_remainder[:split_group]
          }
          remainder_groups.delete(group)
          remainder_groups.delete(paired_remainder)
          processed_studios.add(group[:studio_id])
          processed_studios.add(paired_studio_id)
        end
      end
    end
    
    # Second pass: First try to fit remaining studios into existing tables
    remainder_groups.sort_by! { |g| g[:size] } # Sort by size (smallest first for easier fitting)
    
    remainder_groups.dup.each do |group|
      next if processed_studios.include?(group[:studio_id])
      
      # Skip Event Staff - they should never be merged with other studios
      next if group[:studio_id] == 0
      
      # Try to fit this group into an existing table
      fitted = false
      
      # First, try to fit with tables from the same studio (if this is a remainder)
      if group[:is_remainder] && group[:split_group]
        people_groups.each_with_index do |existing_group, idx|
          next unless existing_group[:split_group]
          # Check if this is part of the same split studio
          if existing_group[:split_group].start_with?("studio_#{group[:studio_id]}_")
            current_size = existing_group[:people].size
            available_space = table_size - current_size
            
            if group[:size] <= available_space
              existing_group[:people].concat(group[:people])
              remainder_groups.delete(group)
              processed_studios.add(group[:studio_id])
              fitted = true
              break
            end
          end
        end
      end
      
      # If not fitted yet, try any compatible table FROM THE SAME STUDIO
      unless fitted
        people_groups.each do |existing_group|
          current_size = existing_group[:people].size
          available_space = table_size - current_size
          
          # Don't add to Event Staff tables
          next if existing_group[:studio_id] == 0
          
          # ONLY fit with tables from the same studio - never mix studios
          next if existing_group[:studio_id] != group[:studio_id]
          
          if group[:size] <= available_space
            existing_group[:people].concat(group[:people])
            remainder_groups.delete(group)
            processed_studios.add(group[:studio_id])
            fitted = true
            break
          end
        end
      end
    end
    
    # Third pass: Handle any remaining groups that couldn't fit in existing tables
    remainder_groups.sort_by! { |g| -g[:size] }
    
    while remainder_groups.any?
      current_group = remainder_groups.shift
      next if processed_studios.include?(current_group[:studio_id])
      
      current_table = current_group[:people].dup
      remaining_capacity = table_size - current_group[:size]
      
      # Fill with other groups that fit
      remainder_groups.dup.each do |other_group|
        if other_group[:size] <= remaining_capacity && !processed_studios.include?(other_group[:studio_id])
          # Skip Event Staff - they should never be merged with other studios
          next if other_group[:studio_id] == 0 || current_group[:studio_id] == 0
          
          current_table.concat(other_group[:people])
          remaining_capacity -= other_group[:size]
          remainder_groups.delete(other_group)
          processed_studios.add(other_group[:studio_id])
          
          break if remaining_capacity < 1
        end
      end
      
      people_groups << {
        people: current_table,
        studio_id: current_group[:studio_id],
        studio_name: current_group[:studio_name],
        split_group: current_group[:split_group],
        is_mixed: remainder_groups.any? { |g| current_table.include?(g[:people].first) rescue false }
      }
      processed_studios.add(current_group[:studio_id])
    end
    
    people_groups
  end
  
  def place_groups_on_grid(people_groups)
    # Phase 2: Place groups on grid (where tables go)
    # Clean, plan-based approach:
    # 1. Identify studios that need multiple adjacent tables
    # 2. Place those multi-table groups first
    # 3. Fill in the remaining single tables
    
    positions = []
    max_cols = 8
    created_tables = []
    
    # Step 1: Build the placement plan
    placement_plan = build_table_placement_plan(people_groups)
    
    # Step 2: Place coordinated groups first (shared table clusters)
    placement_plan[:coordinated_groups].each do |group_plan|
      place_coordinated_group(group_plan, positions, max_cols, created_tables)
    end
    
    # Step 3: Place explicit multi-table groups (from Phase 1 splits)
    placement_plan[:explicit_multi_table_groups].each do |group_plan|
      place_multi_table_group(group_plan, positions, max_cols, created_tables)
    end
    
    # Step 4: Place studio pair coordination groups (paired studios that need adjacent placement)
    placement_plan[:pair_coordination_groups].each do |group_plan|
      place_pair_coordination_group(group_plan, positions, max_cols, created_tables)
    end
    
    # Step 5: Place single tables in remaining positions
    placement_plan[:single_tables].each do |group|
      place_single_table(group, positions, max_cols, created_tables)
    end
    
    # Renumber tables sequentially based on their final positions
    renumber_tables_by_position
    
    created_tables
  end
  
  def build_table_placement_plan(people_groups)
    # Build a plan that recognizes shared tables and groups studios accordingly
    
    # First, detect which groups are shared (contain multiple studios)
    shared_groups = []
    studio_only_groups = []
    
    people_groups.each do |group|
      studios_in_group = group[:people].map(&:studio_id).uniq
      if studios_in_group.size > 1
        shared_groups << group
      else
        studio_only_groups << group
      end
    end
    
    # Only create coordinated placement plans for shared groups where the studios
    # actually have additional tables that need adjacent placement
    coordinated_groups = []
    remaining_groups = studio_only_groups.dup
    processed_shared_groups = []
    
    shared_groups.each do |shared_group|
      # Find all studios that have people in this shared group
      studios_in_shared = shared_group[:people].map(&:studio_id).uniq
      
      # Find all other groups that belong to these studios
      related_studio_groups = []
      
      studios_in_shared.each do |studio_id|
        studio_groups = studio_only_groups.select do |group|
          group[:people].any? { |person| person.studio_id == studio_id }
        end
        related_studio_groups.concat(studio_groups)
      end
      
      # Only create a coordinated group if there are actually related studio tables
      # This avoids treating simple mixed tables (like small studios combined for efficiency) as coordinated groups
      if related_studio_groups.any?
        related_groups = [shared_group] + related_studio_groups
        
        coordinated_groups << {
          type: :shared_table_cluster,
          shared_table: shared_group,
          studio_tables: related_studio_groups,
          total_tables: related_groups.size,
          studios: studios_in_shared.map { |id| Person.find_by(id: shared_group[:people].find { |p| p.studio_id == id }.id).studio.name }.uniq
        }
        
        # Remove the related studio groups from remaining
        remaining_groups -= related_studio_groups
        processed_shared_groups << shared_group
      end
    end
    
    # Add unprocessed shared groups to single tables (they're just mixed tables for efficiency)
    unprocessed_shared_groups = shared_groups - processed_shared_groups
    remaining_groups.concat(unprocessed_shared_groups)
    
    # Handle studio pair coordination groups (tables that need adjacent placement due to studio pairing)
    pair_coordination_groups = []
    coordination_groups = remaining_groups.group_by { |group| group[:coordination_group] }
    
    coordination_groups.each do |coordination_key, groups|
      next if coordination_key.nil? || !coordination_key.start_with?('pair_')
      
      if groups.size > 1
        # This is a studio pair that needs coordinated placement
        pair_coordination_groups << {
          type: :studio_pair_coordination,
          coordination_key: coordination_key,
          tables: groups,
          total_tables: groups.size,
          studios: groups.map { |g| g[:studio_name] }.uniq
        }
        
        # Remove these groups from remaining
        remaining_groups -= groups
      end
    end
    
    # Handle remaining explicit split studios (from Phase 1)
    explicit_multi_table_groups = []
    split_studio_groups = {}
    processed_groups = []
    
    remaining_groups.each do |group|
      if group[:split_group]
        studio_id = group[:studio_id] || group[:people].first.studio_id
        split_studio_groups[studio_id] ||= []
        split_studio_groups[studio_id] << group
      end
    end
    
    split_studio_groups.each do |studio_id, groups|
      if groups.size > 1
        studio_name = groups.first[:people].first.studio.name
        explicit_multi_table_groups << {
          type: :explicit_split,
          studio_name: studio_name,
          studio_id: studio_id,
          tables: groups
        }
        processed_groups.concat(groups)
      end
    end
    
    # Remove only the groups that were actually processed into explicit multi-table groups
    remaining_groups -= processed_groups
    
    {
      coordinated_groups: coordinated_groups,
      explicit_multi_table_groups: explicit_multi_table_groups,
      pair_coordination_groups: pair_coordination_groups,
      single_tables: remaining_groups
    }
  end
  
  def place_coordinated_group(group_plan, positions, max_cols, created_tables)
    # Place a shared table cluster - one shared table with adjacent studio tables
    shared_table_group = group_plan[:shared_table]
    studio_table_groups = group_plan[:studio_tables]
    total_tables = group_plan[:total_tables]
    
    # Place the shared table at the position that maximizes adjacent available spots
    shared_table = create_and_assign_table(created_tables.size + 1, shared_table_group[:people])
    shared_pos = find_position_with_most_adjacent_spots(positions, max_cols, studio_table_groups.size)
    
    if shared_pos
      positions << shared_pos
      shared_table.update!(row: shared_pos[:row], col: shared_pos[:col])
      created_tables << shared_table
      
      # Now place the studio tables adjacent to the shared table
      adjacent_positions = [
        { row: shared_pos[:row], col: shared_pos[:col] + 1 },     # Right
        { row: shared_pos[:row], col: shared_pos[:col] - 1 },     # Left
        { row: shared_pos[:row] + 1, col: shared_pos[:col] },     # Below
        { row: shared_pos[:row] - 1, col: shared_pos[:col] }      # Above
      ]
      
      studio_table_groups.each_with_index do |studio_group, idx|
        studio_table = create_and_assign_table(created_tables.size + 1, studio_group[:people])
        
        # Try to place at an adjacent position
        placed = false
        adjacent_positions.each do |adj_pos|
          # Check if position is valid and available
          if adj_pos[:row] >= 1 && adj_pos[:row] <= 5 && adj_pos[:col] >= 1 && adj_pos[:col] <= max_cols &&
             !positions.any? { |p| p[:row] == adj_pos[:row] && p[:col] == adj_pos[:col] }
            
            positions << adj_pos
            studio_table.update!(row: adj_pos[:row], col: adj_pos[:col])
            created_tables << studio_table
            placed = true
            break
          end
        end
        
        # If no adjacent position available, place at next available position
        unless placed
          fallback_pos = find_next_position(positions, max_cols)
          if fallback_pos
            positions << fallback_pos
            studio_table.update!(row: fallback_pos[:row], col: fallback_pos[:col])
            created_tables << studio_table
          end
        end
      end
    end
  end

  def place_multi_table_group(group_plan, positions, max_cols, created_tables)
    # Place a studio's multiple tables adjacently
    studio_name = group_plan[:studio_name]
    tables = group_plan[:tables]
    required_spots = tables.size
    
    # Find the best contiguous block for this studio
    best_position = find_contiguous_block_for_studio(required_spots, positions, max_cols)
    
    if best_position
      # Place tables in the contiguous block
      tables.sort_by { |t| t[:split_index] || 0 }.each_with_index do |table_group, idx|
        # Calculate position within the block
        if required_spots == 2
          if best_position[:layout] == :horizontal
            pos = { row: best_position[:row], col: best_position[:col] + idx }
          else
            pos = { row: best_position[:row] + idx, col: best_position[:col] }
          end
        else
          # For 3+ tables, use 2x2 grid pattern
          row_offset = idx / 2
          col_offset = idx % 2
          pos = { row: best_position[:row] + row_offset, col: best_position[:col] + col_offset }
        end
        
        # Create and place the table
        table = create_and_assign_table(created_tables.size + 1, table_group[:people])
        table.update!(row: pos[:row], col: pos[:col])
        positions << pos
        created_tables << table
      end
    else
      # Fallback: place as close together as possible
      placed_positions = []
      
      tables.each_with_index do |table_group, idx|
        table = create_and_assign_table(created_tables.size + 1, table_group[:people])
        
        if idx == 0
          # First table - place at next available position
          pos = find_next_position(positions, max_cols)
        else
          # Subsequent tables - find position closest to previously placed tables
          pos = find_closest_position_to_group(placed_positions, positions, max_cols)
        end
        
        if pos
          positions << pos
          placed_positions << pos
          table.update!(row: pos[:row], col: pos[:col])
          created_tables << table
        end
      end
    end
  end
  
  def place_single_table(group, positions, max_cols, created_tables)
    # Place a single table at the next available position
    table = create_and_assign_table(created_tables.size + 1, group[:people])
    pos = find_next_position(positions, max_cols)
    
    if pos
      positions << pos
      table.update!(row: pos[:row], col: pos[:col])
      created_tables << table
    end
  end

  def place_pair_coordination_group(group_plan, positions, max_cols, created_tables)
    # Place paired studios' tables adjacent to each other
    # This handles cases like Studio1(10) + Studio2(10) where they need separate but adjacent tables
    
    tables = group_plan[:tables]
    required_spots = tables.size
    
    # Find the best contiguous block for this studio pair
    best_position = find_contiguous_block_for_studio(required_spots, positions, max_cols)
    
    if best_position
      # Place tables in the contiguous block
      tables.each_with_index do |table_group, idx|
        # Calculate position within the block
        if required_spots == 2
          if best_position[:layout] == :horizontal
            pos = { row: best_position[:row], col: best_position[:col] + idx }
          else # vertical
            pos = { row: best_position[:row] + idx, col: best_position[:col] }
          end
        else
          # For 3+ tables, use 2x2 block layout
          pos = { 
            row: best_position[:row] + (idx / 2), 
            col: best_position[:col] + (idx % 2) 
          }
        end
        
        table = create_and_assign_table(created_tables.size + 1, table_group[:people])
        positions << pos
        table.update!(row: pos[:row], col: pos[:col])
        created_tables << table
      end
    else
      # Fallback: place tables as close together as possible
      placed_positions = []
      
      tables.each_with_index do |table_group, idx|
        table = create_and_assign_table(created_tables.size + 1, table_group[:people])
        
        if idx == 0
          # First table - just find any available position
          pos = find_next_position(positions, max_cols)
        else
          # Subsequent tables - find position closest to previously placed tables from this pair
          pos = find_closest_position_to_group(placed_positions, positions, max_cols)
        end
        
        if pos
          positions << pos
          placed_positions << pos
          table.update!(row: pos[:row], col: pos[:col])
          created_tables << table
        end
      end
    end
  end
  
  def position_occupied?(pos, positions)
    positions.any? { |p| p[:row] == pos[:row] && p[:col] == pos[:col] }
  end
  
  
  
  def find_next_position(positions, max_cols, reserved_positions = [])
    # Find the next available position in the grid
    row = 1
    col = 1
    
    loop do
      # Check if this position is available AND not reserved for someone else
      pos = { row: row, col: col }
      unless position_occupied?(pos, positions) || position_reserved_for_others?(pos, reserved_positions)
        return pos
      end
      
      # Move to next position
      col += 1
      if col > max_cols
        col = 1
        row += 1
      end
      
      # Safety check to prevent infinite loop
      break if row > 20
    end
    
    nil
  end
  
  def position_reserved_for_others?(pos, reserved_positions)
    # Check if this position is reserved for someone else (not available for general use)
    reserved_positions.any? do |reservation|
      next if reservation[:used]
      
      res_pos = reservation[:position]
      res_pos[:row] == pos[:row] && res_pos[:col] == pos[:col]
    end
  end

  def find_position_with_most_adjacent_spots(positions, max_cols, needed_adjacent_spots)
    # Find the available position that has the most available adjacent spots
    # This avoids placing shared tables in corners where there are fewer adjacent positions
    
    best_position = nil
    best_score = -1
    
    # Check all available positions
    (1..5).each do |row|
      (1..max_cols).each do |col|
        pos = { row: row, col: col }
        
        # Skip if position is already occupied
        next if positions.any? { |p| p[:row] == row && p[:col] == col }
        
        # Count available adjacent positions
        adjacent_candidates = [
          { row: row - 1, col: col },     # Above
          { row: row + 1, col: col },     # Below
          { row: row, col: col - 1 },     # Left
          { row: row, col: col + 1 }      # Right
        ]
        
        available_adjacent = adjacent_candidates.count do |adj_pos|
          # Valid position within grid bounds and not occupied
          adj_pos[:row] >= 1 && adj_pos[:row] <= 5 && 
          adj_pos[:col] >= 1 && adj_pos[:col] <= max_cols &&
          !positions.any? { |p| p[:row] == adj_pos[:row] && p[:col] == adj_pos[:col] }
        end
        
        # Prefer positions with more available adjacent spots
        # Break ties by preferring upper-left positions (lower row + col values)
        tie_breaker = -(row * 10 + col)  # Negative to prefer lower values
        score = available_adjacent * 1000 + tie_breaker
        
        if score > best_score
          best_score = score
          best_position = pos
        end
      end
    end
    
    # If we found a good position with enough adjacent spots, use it
    # Otherwise fall back to the first available position
    if best_position && (best_score / 1000) >= [needed_adjacent_spots, 1].min
      best_position
    else
      find_next_position(positions, max_cols)
    end
  end

  # Use callbacks to share common setup or constraints between actions.
    def set_table
      @table = Table.find(params.expect(:id))
    end
    
    def set_option
      if params[:option_id].present?
        @option = Billable.find(params[:option_id])
        # Ensure it's actually an option, not a package
        raise ActiveRecord::RecordNotFound unless @option.type == 'Option'
      end
    end

    # Only allow a list of trusted parameters through.
    def table_params
      params.expect(table: [ :number, :row, :col, :size, :studio_id, :option_id ])
    end
end
