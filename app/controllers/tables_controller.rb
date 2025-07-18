require 'set'

class TablesController < ApplicationController
  include Printable
  
  before_action :set_table, only: %i[ show edit update destroy ]
  before_action :set_option, only: %i[ index new create arrange assign studio move_person reset update_positions renumber ]

  # GET /tables or /tables.json
  def index
    @tables = Table.includes(people: :studio).where(option_id: @option&.id).order(:row, :col)
    @columns = (Table.maximum(:col) || 7) + 1
    
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
        
        # Check if table numbers are contiguous OR if table positions are contiguous
        tables_with_positions = table_data.map { |td| td[:table] }.select { |t| t.row && t.col }
        
        is_non_contiguous = false
        
        # Check table number contiguity
        if !contiguous_numbers?(table_numbers)
          is_non_contiguous = true
        end
        
        # Also check position contiguity if we have position data
        if tables_with_positions.length > 1 && !contiguous?(tables_with_positions)
          is_non_contiguous = true
        end
        
        # Create single issue if non-contiguous
        if is_non_contiguous
          issues << {
            type: :non_contiguous_studio,
            option: option_name,
            studio: studio_name,
            tables: table_numbers
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
    # Priority order:
    # 1. Same studio together (split if needed)
    # 2. Paired studios together (if space available)
    # 3. Combine unfull tables
    
    # Group people by studio
    studio_groups = people.group_by(&:studio_id).map do |studio_id, studio_people|
      {
        studio_id: studio_id,
        people: studio_people,
        size: studio_people.size,
        studio_name: studio_people.first.studio.name
      }
    end
    
    people_groups = []
    assigned_studios = Set.new
    
    # 1. Handle Event Staff (studio_id = 0) first - keep them together
    event_staff_group = studio_groups.find { |g| g[:studio_id] == 0 }
    if event_staff_group
      if event_staff_group[:size] <= table_size
        # All Event Staff fit on one table
        people_groups << {
          people: event_staff_group[:people],
          studio_id: 0,
          studio_name: 'Event Staff',
          studio_ids: [0],
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
            studio_ids: [0],
            split_group: "event_staff_#{split_index}",
            split_total: (event_staff_group[:size] / table_size.to_f).ceil
          }
          split_index += 1
        end
      end
      studio_groups.reject! { |g| g[:studio_id] == 0 }
      assigned_studios.add(0)
    end
    
    # 2. PRIORITY 1: Handle each studio individually first (same studio together)
    # Process studios by size (largest first) to handle big studios before small ones
    studio_groups.sort_by! { |g| -g[:size] }
    
    studio_groups.each do |group|
      next if assigned_studios.include?(group[:studio_id])
      
      if group[:size] <= table_size
        # Studio fits in one table - create it but don't assign yet
        # (we'll try to combine with paired studios in next step)
        people_groups << {
          people: group[:people].dup,
          studio_id: group[:studio_id],
          studio_name: group[:studio_name],
          studio_ids: [group[:studio_id]],
          split_group: nil,
          available_space: table_size - group[:size]
        }
      else
        # Studio needs multiple tables - split them
        total_tables_needed = (group[:size] / table_size.to_f).ceil
        split_index = 0
        
        group[:people].each_slice(table_size) do |people_slice|
          people_groups << {
            people: people_slice,
            studio_id: group[:studio_id],
            studio_name: group[:studio_name],
            studio_ids: [group[:studio_id]],
            split_group: "studio_#{group[:studio_id]}_#{split_index}",
            split_total: total_tables_needed,
            split_index: split_index,
            available_space: table_size - people_slice.size
          }
          split_index += 1
        end
      end
      
      assigned_studios.add(group[:studio_id])
    end
    
    # 3. PRIORITY 2: Try to combine paired studios into same tables
    studio_pairs = StudioPair.includes(:studio1, :studio2).map do |pair|
      [pair.studio1.id, pair.studio2.id]
    end
    
    # Build connected components for associative pairing
    studio_components = build_connected_components(studio_pairs)
    
    # Track which pairs were successfully combined and which need adjacent placement
    combined_pairs = Set.new
    pairs_needing_adjacency = []
    
    # For each component, try to combine studios that have available space
    studio_components.each do |component|
      # Get all groups for studios in this component
      component_groups = people_groups.select { |group| 
        component.include?(group[:studio_id]) && group[:available_space] && group[:available_space] > 0
      }
      
      # Track which studios in this component were combined
      component_combined = Set.new
      
      # Try to combine studios in this component
      # Use a more systematic approach: for each studio, try to fit it with any other studio in the component
      component.each do |studio1_id|
        component.each do |studio2_id|
          next if studio1_id >= studio2_id # Avoid duplicates and self-pairing
          
          # Get all groups for both studios
          studio1_groups = people_groups.select { |g| g[:studio_id] == studio1_id && !g[:is_paired] }
          studio2_groups = people_groups.select { |g| g[:studio_id] == studio2_id && !g[:is_paired] }
          
          # Try all combinations to find a fit
          studio1_groups.each do |group1|
            studio2_groups.each do |group2|
              # Check if either group can fit into the other
              if group1[:available_space] >= group2[:people].size
                # group2 fits into group1
                group1[:people] += group2[:people]
                group1[:studio_name] = "#{group1[:studio_name]} & #{group2[:studio_name]}"
                group1[:studio_ids] = (group1[:studio_ids] + group2[:studio_ids]).uniq
                group1[:available_space] -= group2[:people].size
                group1[:is_paired] = true
                group1[:paired_studios] = component
                group1[:coordination_group] = "component_#{component.sort.join('_')}"
                
                # Mark the combined group for removal
                group2[:remove] = true
                
                # Track successful combination
                component_combined.add(studio1_id)
                component_combined.add(studio2_id)
                
                break # Move to next studio pair
              elsif group2[:available_space] >= group1[:people].size
                # group1 fits into group2
                group2[:people] += group1[:people]
                group2[:studio_name] = "#{group2[:studio_name]} & #{group1[:studio_name]}"
                group2[:studio_ids] = (group2[:studio_ids] + group1[:studio_ids]).uniq
                group2[:available_space] -= group1[:people].size
                group2[:is_paired] = true
                group2[:paired_studios] = component
                group2[:coordination_group] = "component_#{component.sort.join('_')}"
                
                # Mark the combined group for removal
                group1[:remove] = true
                
                # Track successful combination
                component_combined.add(studio1_id)
                component_combined.add(studio2_id)
                
                break # Move to next studio pair
              end
            end
            
            # If we found a combination, break out of the outer loop too
            break if component_combined.include?(studio1_id) && component_combined.include?(studio2_id)
          end
          
          # If we successfully combined these studios, move to the next pair
          if component_combined.include?(studio1_id) && component_combined.include?(studio2_id)
            break
          end
        end
      end
      
      # For studios in this component that couldn't be combined, mark them for adjacent placement
      component.each do |studio1_id|
        component.each do |studio2_id|
          next if studio1_id >= studio2_id # Avoid duplicates
          
          # Check if this pair was combined successfully
          if !component_combined.include?(studio1_id) || !component_combined.include?(studio2_id)
            # This pair needs adjacent placement
            pairs_needing_adjacency << [studio1_id, studio2_id]
          end
        end
      end
    end
    
    # Remove groups that were combined
    people_groups.reject! { |group| group[:remove] }
    
    # Mark groups for studios that need adjacent placement
    pairs_needing_adjacency.each do |studio1_id, studio2_id|
      # Find groups for these studios and mark them for adjacent placement
      studio1_groups = people_groups.select { |group| group[:studio_id] == studio1_id }
      studio2_groups = people_groups.select { |group| group[:studio_id] == studio2_id }
      
      if studio1_groups.any? && studio2_groups.any?
        # Create coordination group for adjacent placement
        coord_key = "adjacent_pair_#{[studio1_id, studio2_id].sort.join('_')}"
        
        (studio1_groups + studio2_groups).each do |group|
          group[:coordination_group] = coord_key
          group[:needs_adjacency] = true
        end
      end
    end
    
    # Clean up available_space field
    people_groups.each { |group| group.delete(:available_space) }
    
    # 4. PRIORITY 3: Combine unfull tables (this is handled by consolidation later)
    # All studios are now assigned, unfull tables will be combined in consolidation phase
    
    # Consolidate small tables to minimize table count
    people_groups = consolidate_small_tables(people_groups, table_size)
    
    # Post-processing: eliminate ANY remaining small tables (1-3 people)
    # BUT avoid breaking studio contiguity for remainder groups
    people_groups = eliminate_remaining_small_tables_with_contiguity(people_groups, table_size)
    
    people_groups
  end
  
  def consolidate_small_tables(people_groups, table_size)
    # Consolidate small tables to minimize table count
    # Be more aggressive about consolidating very small tables
    
    # Find small tables that can be consolidated
    small_tables = []
    remaining_tables = []
    
    people_groups.each do |group|
      group_size = group[:people].size
      
      # Consolidate small tables (1-4 people) but protect paired studios
      if group_size <= 4 && 
         group[:studio_id] != 0 &&  # Don't consolidate Event Staff
         !group[:coordination_group] &&  # Don't consolidate connected components
         !group[:is_paired] &&  # Don't consolidate paired studios
         !group[:needs_adjacency]  # Don't consolidate studios that need adjacency
        
        small_tables << group
      else
        remaining_tables << group
      end
    end
    
    # Sort small tables by size (smallest first for better packing)
    small_tables.sort_by! { |group| group[:people].size }
    
    # Smart consolidation: only consolidate truly independent small studios
    # Preserve studio integrity for paired/connected studios
    consolidated_tables = []
    current_table = []
    current_studios = []
    current_studio_ids = []
    
    small_tables.each do |group|
      # Check if this group can fit in the current consolidated table
      if current_table.size + group[:people].size <= table_size
        # Add to current table
        current_table += group[:people]
        current_studios << group[:studio_name]
        current_studio_ids += (group[:studio_ids] || [group[:studio_id]])
      else
        # Start a new consolidated table
        if current_table.any?
          consolidated_tables << {
            people: current_table,
            studio_id: current_studios.size == 1 ? current_table.first.studio_id : nil,
            studio_name: current_studios.join(' & '),
            studio_ids: current_studio_ids.uniq,
            split_group: nil,
            is_mixed: current_studios.size > 1
          }
        end
        
        # Start new table with current group
        current_table = group[:people].dup
        current_studios = [group[:studio_name]]
        current_studio_ids = (group[:studio_ids] || [group[:studio_id]]).dup
      end
    end
    
    # Add the last consolidated table if any
    if current_table.any?
      consolidated_tables << {
        people: current_table,
        studio_id: current_studios.size == 1 ? current_table.first.studio_id : nil,
        studio_name: current_studios.join(' & '),
        studio_ids: current_studio_ids.uniq,
        split_group: nil,
        is_mixed: current_studios.size > 1
      }
    end
    
    # Return the consolidated result
    result = remaining_tables + consolidated_tables
    
    # Log the consolidation if any occurred
    if consolidated_tables.any?
      original_count = people_groups.count
      new_count = result.count
      Rails.logger.info "Consolidated #{small_tables.count} small tables into #{consolidated_tables.count} tables, reducing total from #{original_count} to #{new_count}"
    end
    
    result
  end
  
  def eliminate_remaining_small_tables(people_groups, table_size)
    # Final pass: eliminate any remaining small tables (1-3 people)
    # by fitting them into existing tables with available capacity
    
    small_tables = []
    large_tables = []
    
    people_groups.each do |group|
      if group[:people].size <= 3
        small_tables << group
      else
        large_tables << group
      end
    end
    
    # Try to fit small tables into large tables with available space
    # PREFER tables that already contain people from the same studio
    small_tables.each do |small_group|
      fitted = false
      small_group_studio_ids = (small_group[:studio_ids] || [small_group[:studio_id]])
      
      # First pass: try to fit into tables that already contain people from this studio
      large_tables.each do |large_group|
        available_space = table_size - large_group[:people].size
        next if small_group[:people].size > available_space
        
        large_group_studio_ids = (large_group[:studio_ids] || [large_group[:studio_id]])
        
        # Check if this large table already has people from this studio
        if (small_group_studio_ids & large_group_studio_ids).any?
          # Fit the small group into this large table
          large_group[:people] += small_group[:people]
          
          # Update the studio name and studio_ids to reflect the mix
          if large_group[:studio_name] && !large_group[:studio_name].include?(small_group[:studio_name])
            large_group[:studio_name] = "#{large_group[:studio_name]} & #{small_group[:studio_name]}"
            large_group[:is_mixed] = true
          end
          
          # Update studio_ids to include all represented studios
          large_group[:studio_ids] = (large_group[:studio_ids] || [large_group[:studio_id]]) + 
                                   (small_group[:studio_ids] || [small_group[:studio_id]])
          large_group[:studio_ids].uniq!
          
          fitted = true
          break
        end
      end
      
      # Second pass: if we couldn't fit into same-studio table, try any available table
      unless fitted
        large_tables.each do |large_group|
          available_space = table_size - large_group[:people].size
          
          if small_group[:people].size <= available_space
            # Fit the small group into this large table
            large_group[:people] += small_group[:people]
            
            # Update the studio name and studio_ids to reflect the mix
            if large_group[:studio_name] && !large_group[:studio_name].include?(small_group[:studio_name])
              large_group[:studio_name] = "#{large_group[:studio_name]} & #{small_group[:studio_name]}"
              large_group[:is_mixed] = true
            end
            
            # Update studio_ids to include all represented studios
            large_group[:studio_ids] = (large_group[:studio_ids] || [large_group[:studio_id]]) + 
                                     (small_group[:studio_ids] || [small_group[:studio_id]])
            large_group[:studio_ids].uniq!
            
            fitted = true
            break
          end
        end
      end
      
      # If we couldn't fit it, keep it as a separate table (shouldn't happen with proper space)
      unless fitted
        large_tables << small_group
      end
    end
    
    large_tables
  end
  
  def eliminate_remaining_small_tables_with_contiguity(people_groups, table_size)
    # Enhanced version that avoids breaking studio contiguity
    # Specifically handles remainder groups from split studios
    
    small_tables = []
    large_tables = []
    
    people_groups.each do |group|
      if group[:people].size <= 3
        small_tables << group
      else
        large_tables << group
      end
    end
    
    # Check if any small tables are remainder groups from split studios
    remainder_groups = small_tables.select { |group| group[:is_remainder] }
    other_small_groups = small_tables.reject { |group| group[:is_remainder] }
    
    # For remainder groups, avoid consolidation that would break studio contiguity
    remainder_groups.each do |small_group|
      fitted = false
      small_group_studio_ids = (small_group[:studio_ids] || [small_group[:studio_id]])
      
      # FIRST: try to fit with tables from the SAME studio
      large_tables.each do |large_group|
        available_space = table_size - large_group[:people].size
        next if small_group[:people].size > available_space
        
        large_group_studio_ids = (large_group[:studio_ids] || [large_group[:studio_id]])
        
        # Check if this large table contains ONLY people from the same studio
        if small_group_studio_ids.length == 1 && large_group_studio_ids.length == 1 && 
           small_group_studio_ids.first == large_group_studio_ids.first
          
          # Perfect match - same studio only
          large_group[:people] += small_group[:people]
          fitted = true
          break
        end
      end
      
      # If we couldn't fit with same studio, keep as separate table to preserve contiguity
      unless fitted
        large_tables << small_group
      end
    end
    
    # For other small groups, use normal consolidation
    other_small_groups.each do |small_group|
      fitted = false
      small_group_studio_ids = (small_group[:studio_ids] || [small_group[:studio_id]])
      
      # First pass: try to fit into tables that already contain people from this studio
      large_tables.each do |large_group|
        available_space = table_size - large_group[:people].size
        next if small_group[:people].size > available_space
        
        large_group_studio_ids = (large_group[:studio_ids] || [large_group[:studio_id]])
        
        # Check if this large table already has people from this studio
        if (small_group_studio_ids & large_group_studio_ids).any?
          # Fit the small group into this large table
          large_group[:people] += small_group[:people]
          
          # Update the studio name and studio_ids to reflect the mix
          if large_group[:studio_name] && !large_group[:studio_name].include?(small_group[:studio_name])
            large_group[:studio_name] = "#{large_group[:studio_name]} & #{small_group[:studio_name]}"
            large_group[:is_mixed] = true
          end
          
          # Update studio_ids to include all represented studios
          large_group[:studio_ids] = (large_group[:studio_ids] || [large_group[:studio_id]]) + 
                                   (small_group[:studio_ids] || [small_group[:studio_id]])
          large_group[:studio_ids].uniq!
          
          fitted = true
          break
        end
      end
      
      # Second pass: if we couldn't fit into same-studio table, try any available table
      unless fitted
        large_tables.each do |large_group|
          available_space = table_size - large_group[:people].size
          
          if small_group[:people].size <= available_space
            # Fit the small group into this large table
            large_group[:people] += small_group[:people]
            
            # Update the studio name and studio_ids to reflect the mix
            if large_group[:studio_name] && !large_group[:studio_name].include?(small_group[:studio_name])
              large_group[:studio_name] = "#{large_group[:studio_name]} & #{small_group[:studio_name]}"
              large_group[:is_mixed] = true
            end
            
            # Update studio_ids to include all represented studios
            large_group[:studio_ids] = (large_group[:studio_ids] || [large_group[:studio_id]]) + 
                                     (small_group[:studio_ids] || [small_group[:studio_id]])
            large_group[:studio_ids].uniq!
            
            fitted = true
            break
          end
        end
      end
      
      # If we couldn't fit it, keep it as a separate table
      unless fitted
        large_tables << small_group
      end
    end
    
    large_tables
  end
  
  def build_connected_components(studio_pairs)
    # Build connected components from studio pairs using Union-Find algorithm
    # This handles associative grouping: if A-B and B-C, then A-B-C are all connected
    
    # Create adjacency list
    graph = Hash.new { |h, k| h[k] = [] }
    all_studios = Set.new
    
    studio_pairs.each do |studio1_id, studio2_id|
      graph[studio1_id] << studio2_id
      graph[studio2_id] << studio1_id
      all_studios.add(studio1_id)
      all_studios.add(studio2_id)
    end
    
    # Find connected components using DFS
    visited = Set.new
    components = []
    
    all_studios.each do |studio_id|
      next if visited.include?(studio_id)
      
      # Start a new component
      component = []
      stack = [studio_id]
      
      while !stack.empty?
        current = stack.pop
        next if visited.include?(current)
        
        visited.add(current)
        component << current
        
        # Add all neighbors to stack
        graph[current].each do |neighbor|
          stack << neighbor unless visited.include?(neighbor)
        end
      end
      
      components << component.sort if component.any?
    end
    
    components
  end
  
  def place_groups_on_grid(people_groups)
    # Phase 2: Place groups on grid (where tables go)
    # Simplified approach that handles connected components properly
    
    positions = []
    max_cols = 8
    created_tables = []
    
    # Step 1: Group tables by coordination groups and studio splits
    # For coordination groups, remove the index suffix to group split tables together
    coordination_groups = people_groups.group_by do |group|
      coord_group = group[:coordination_group]
      if coord_group && coord_group.split('_').length > 4 && coord_group.start_with?('component_')
        # Remove the index suffix (e.g., "component_18_35_54_0" -> "component_18_35_54")
        coord_group.split('_')[0..-2].join('_')
      else
        coord_group
      end
    end
    split_groups = people_groups.group_by { |group| group[:split_group]&.split('_')&.first(2)&.join('_') }
    
    
    # Step 1.5: Build a lookup of which groups each studio appears in
    studio_to_groups = Hash.new { |h, k| h[k] = [] }
    people_groups.each_with_index do |group, index|
      studio_ids = group[:studio_ids] || [group[:studio_id]]
      studio_ids.each do |studio_id|
        studio_to_groups[studio_id] << { group: group, index: index }
      end
    end
    
    # Debug: log studios that appear in multiple groups
    multi_table_studios = studio_to_groups.select { |studio_id, group_refs| 
      studio_id && studio_id != 0 && group_refs.length > 1 
    }
    
    # Step 1.6: Fix coordination groups for studios that appear in multiple groups
    # This handles cases where consolidation created mixed tables without proper grouping
    multi_table_studios.each do |studio_id, group_refs|
      # For any studio that appears in multiple groups, create a unified coordination group
      # This is simpler and more reliable than trying to detect all the different cases
      if group_refs.length > 1
        coord_key = "multi_studio_#{studio_id}"
        
        group_refs.each do |ref|
          # Preserve original grouping information
          ref[:group][:original_coordination_group] = ref[:group][:coordination_group] if ref[:group][:coordination_group]
          ref[:group][:original_split_group] = ref[:group][:split_group] if ref[:group][:split_group]
          
          # Override with unified coordination group
          ref[:group][:coordination_group] = coord_key
          ref[:group][:split_group] = nil
        end
      end
    end
    
    # Re-group after fixing coordination groups
    coordination_groups = people_groups.group_by do |group|
      coord_group = group[:coordination_group]
      if coord_group && coord_group.split('_').length > 4 && coord_group.start_with?('component_')
        # Remove the index suffix (e.g., "component_18_35_54_0" -> "component_18_35_54")
        coord_group.split('_')[0..-2].join('_')
      else
        coord_group
      end
    end
    
    # Step 2: Place connected components first (highest priority)
    coordination_groups.each do |coordination_key, groups|
      next if coordination_key.nil?
      
      # Place all tables in this coordination group together
      place_connected_component(groups, positions, max_cols, created_tables)
    end
    
    # Step 3: Place multi-table studios (studios with split groups)
    split_groups.each do |split_key, groups|
      next if split_key.nil? || split_key.empty?
      next if groups.any? { |g| g[:coordination_group] } # Skip if already placed
      
      # Place all tables for this studio together
      place_multi_table_studio(groups, positions, max_cols, created_tables)
    end
    
    # Step 3.5: Place multi-table studios that haven't been placed yet
    # This handles studios that were split during consolidation
    placed_group_indices = Set.new
    
    multi_table_studios.each do |studio_id, group_refs|
      next if studio_id == 0 # Skip Event Staff
      
      # Extract the groups for this studio
      studio_groups = group_refs.map { |ref| ref[:group] }
      
      # Skip if any of these groups have already been placed
      if group_refs.any? { |ref| 
        group = ref[:group]
        group[:coordination_group] || group[:split_group] ||
        placed_group_indices.include?(ref[:index])
      }
        next
      end
      
      # This studio has multiple tables that need to be placed together
      place_multi_table_studio(studio_groups, positions, max_cols, created_tables)
      
      # Mark these groups as placed
      group_refs.each { |ref| placed_group_indices.add(ref[:index]) }
    end
    
    # Step 4: Place remaining single tables
    remaining_groups = people_groups.each_with_index.reject do |group, index|
      group[:coordination_group] || 
      (group[:split_group] && !group[:split_group].empty?) ||
      placed_group_indices.include?(index)
    end.map { |group, index| group }
    
    remaining_groups.each do |group|
      place_single_table(group, positions, max_cols, created_tables)
    end
    
    # Renumber tables sequentially based on their final positions
    renumber_tables_by_position
    
    created_tables
  end
  
  def place_connected_component(groups, positions, max_cols, created_tables)
    # Place all tables in a connected component together as a contiguous block
    return if groups.empty?
    
    # Find the best position for this component
    component_size = groups.size
    best_position = find_best_contiguous_position(component_size, positions, max_cols)
    
    # Place all tables in the component at adjacent positions
    groups.each_with_index do |group, index|
      row, col = best_position[index]
      table = create_table_at_position(group, row, col)
      created_tables << table
      positions << [row, col]
    end
  end
  
  def place_multi_table_studio(groups, positions, max_cols, created_tables)
    # Place all tables for a studio together as a contiguous block
    return if groups.empty?
    
    # Sort groups by split index if available
    sorted_groups = groups.sort_by do |group|
      if group[:split_group] && group[:split_group].include?('_')
        group[:split_group].split('_').last.to_i
      else
        0
      end
    end
    
    # Find the best position for this studio's tables
    studio_size = sorted_groups.size
    best_position = find_best_contiguous_position(studio_size, positions, max_cols)
    
    # Place all tables for this studio at adjacent positions
    sorted_groups.each_with_index do |group, index|
      row, col = best_position[index]
      table = create_table_at_position(group, row, col)
      created_tables << table
      positions << [row, col]
    end
  end
  
  def find_best_contiguous_position(size, positions, max_cols)
    # Find the best contiguous block of positions for the given size
    occupied = positions.to_set
    
    # Try to find a horizontal block first
    (0..Float::INFINITY).each do |row|
      (0..max_cols - size).each do |start_col|
        block_positions = (0...size).map { |i| [row, start_col + i] }
        
        if block_positions.none? { |pos| occupied.include?(pos) }
          return block_positions
        end
      end
    end
    
    # Fallback: return individual positions (shouldn't happen with proper grid)
    positions_array = []
    row = 0
    col = 0
    
    size.times do
      while occupied.include?([row, col])
        col += 1
        if col >= max_cols
          col = 0
          row += 1
        end
      end
      positions_array << [row, col]
      col += 1
      if col >= max_cols
        col = 0
        row += 1
      end
    end
    
    positions_array
  end
  
  def create_table_at_position(group, row, col)
    # Create a table at the specified grid position
    if @option
      # Use a temporary unique number (row * 1000 + col) to avoid conflicts
      temp_number = row * 1000 + col + 1
      table = Table.create!(
        option_id: @option.id,
        number: temp_number, # Will be renumbered later
        row: row,
        col: col
      )
      
      # Assign people to the table through person_options
      group[:people].each do |person|
        person_option = PersonOption.find_by(person: person, option: @option)
        person_option&.update!(table: table)
      end
    else
      # Main event table
      # Use a temporary unique number (row * 1000 + col) to avoid conflicts
      temp_number = row * 1000 + col + 1
      table = Table.create!(
        number: temp_number, # Will be renumbered later
        row: row,
        col: col
      )
      
      # Assign people directly to the table
      group[:people].each do |person|
        person.update!(table: table)
      end
    end
    
    table
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
    occupied = positions.to_set
    
    # Find next available position
    row = 0
    col = 0
    
    while occupied.include?([row, col])
      col += 1
      if col >= max_cols
        col = 0
        row += 1
      end
    end
    
    # Create table at this position
    table = create_table_at_position(group, row, col)
    created_tables << table
    positions << [row, col]
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
