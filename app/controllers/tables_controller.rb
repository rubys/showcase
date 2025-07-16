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
  
  def manhattan_distance(pos1, pos2)
    (pos1[:row] - pos2[:row]).abs + (pos1[:col] - pos2[:col]).abs
  end

  # TWO-PHASE ALGORITHM METHODS
  
  def group_people_into_tables(people, table_size)
    # Phase 1: Group people into tables (who sits together)
    # Returns: Array of arrays of people (each sub-array = one table)
    
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
    
    # 1. Handle Event Staff (studio_id = 0) first - keep them together
    event_staff_group = studio_groups.find { |g| g[:studio_id] == 0 }
    if event_staff_group
      if event_staff_group[:size] <= table_size
        # All Event Staff fit on one table
        people_groups << event_staff_group[:people]
      else
        # Event Staff need multiple tables - keep them adjacent
        event_staff_group[:people].each_slice(table_size) do |people_slice|
          people_groups << people_slice
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
            people_groups << (group[:people] + paired_group[:people])
            assigned_studios.add(group[:studio_id])
            assigned_studios.add(paired_studio_id)
          elsif (group[:size] == table_size && paired_group[:size] <= 3) ||
                (paired_group[:size] == table_size && group[:size] <= 3)
            # Special case: One studio exactly fills a table, but paired studio is small
            # Better to combine them and let larger studio split if needed
            # Example: Columbia (12) + Silver Spring (2) = 14, fits in table of 12 with 2 overflow
            all_people = group[:people] + paired_group[:people]
            
            # First table gets full capacity
            people_groups << all_people.first(table_size)
            
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
        group[:people].first(full_table_count * table_size).each_slice(table_size) do |people_slice|
          people_groups << people_slice
        end
        
        # If there's a remainder, save it for packing
        if remainder_size > 0
          remainder_groups << {
            studio_id: group[:studio_id],
            people: group[:people].last(remainder_size),
            size: remainder_size,
            studio_name: group[:studio_name]
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
          
          people_groups << shared_table
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
      people_groups.each do |existing_table|
        current_size = existing_table.size
        available_space = table_size - current_size
        
        # Don't add to Event Staff tables
        next if existing_table.any? { |person| person.studio_id == 0 }
        
        if group[:size] <= available_space
          existing_table.concat(group[:people])
          remainder_groups.delete(group)
          processed_studios.add(group[:studio_id])
          fitted = true
          break
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
      
      people_groups << current_table
      processed_studios.add(current_group[:studio_id])
    end
    
    people_groups
  end
  
  def place_groups_on_grid(people_groups)
    # Phase 2: Place groups on grid (where tables go)
    # Input: Array of arrays of people
    # Output: Tables with row/col positions
    
    positions = []
    max_cols = 8
    reserved_positions = [] # Global position reservations
    
    # Analyze and group by studio relationships
    analyzed_groups = people_groups.map.with_index do |people, index|
      studios = people.map { |person| person.studio.name }.uniq.sort
      large_studios = ['Columbia', 'Bucharest', 'Lincolnshire', 'NY-Broadway', 'Waco', 'Greenwich']
      
      {
        people: people,
        studios: studios,
        primary_studio: studios.first, # For grouping related tables
        is_event_staff: studios == ['Event Staff'],
        is_multi: studios.size > 1,
        has_large_studios: studios.any? { |s| large_studios.include?(s) },
        priority: calculate_group_priority(studios, large_studios),
        index: index
      }
    end
    
    # Pre-analyze all multi-table conflicts and reserve critical positions
    global_reservations = analyze_global_conflicts_and_reserve_positions(analyzed_groups, max_cols)
    reserved_positions.concat(global_reservations)
    
    # Group by studio relationships
    studio_group_sets = group_by_studio_relationships(analyzed_groups)
    
    created_tables = []
    
    # Place studio group sets in priority order
    studio_group_sets.each do |studio_set|
      place_studio_set(studio_set, positions, max_cols, created_tables, reserved_positions)
    end
    
    # Post-placement optimization: improve adjacency for both studio pairs and multi-table studios
    optimize_placement_for_adjacency(created_tables, analyzed_groups, max_cols)
    
    created_tables
  end
  
  def analyze_global_conflicts_and_reserve_positions(analyzed_groups, max_cols)
    # Pre-analyze all conflicts across all studio sets and reserve positions
    # Priority order: Studio Pairs → Complex Conflicts → Simple Splits
    
    reservations = []
    used_positions = Set.new
    processed_groups = Set.new  # Track which groups are already handled
    large_studios = ['Columbia', 'Bucharest', 'Lincolnshire', 'NY-Broadway', 'Waco', 'Greenwich']
    
    # PRIORITY 0: Studio Pair Coordination (highest priority)
    studio_pairs = StudioPair.includes(:studio1, :studio2)
    
    studio_pairs.each do |pair|
      studio1_name = pair.studio1.name
      studio2_name = pair.studio2.name
      
      # Find groups for both studios in the pair
      studio1_groups = analyzed_groups.select { |g| g[:primary_studio] == studio1_name }
      studio2_groups = analyzed_groups.select { |g| g[:primary_studio] == studio2_name }
      
      # Debug logging for Silver Spring ↔ Columbia
      if (studio1_name == 'Silver Spring' && studio2_name == 'Columbia') ||
         (studio1_name == 'Columbia' && studio2_name == 'Silver Spring')
        Rails.logger.debug "Priority 0 Debug: #{studio1_name} ↔ #{studio2_name}"
        Rails.logger.debug "  #{studio1_name} groups: #{studio1_groups.size}"
        Rails.logger.debug "  #{studio2_name} groups: #{studio2_groups.size}"
        if studio1_groups.empty? || studio2_groups.empty?
          Rails.logger.debug "  SKIPPING: One or both studios have no groups"
        end
      end
      
      next if studio1_groups.empty? || studio2_groups.empty?
      
      # Calculate total people and tables needed for the pair
      total_groups = studio1_groups + studio2_groups
      total_people = total_groups.sum { |g| g[:people].size }
      total_tables = total_groups.size
      
      # Debug logging continued
      if (studio1_name == 'Silver Spring' && studio2_name == 'Columbia') ||
         (studio1_name == 'Columbia' && studio2_name == 'Silver Spring')
        Rails.logger.debug "  Total people: #{total_people}, Total tables: #{total_tables}"
        Rails.logger.debug "  Should share: #{total_people <= 10 && total_tables <= 2}"
      end
      
      # Determine if pair should share tables or be adjacent
      if total_people <= 10 && total_tables <= 2
        # Small combined group - try to place in same table(s)
        pair_position = find_optimal_pair_position_shared(total_tables, max_cols, used_positions)
      else
        # Larger combined group - place adjacent tables
        pair_position = find_optimal_pair_position_adjacent(total_tables, max_cols, used_positions)
      end
      
      # Debug position finding
      if (studio1_name == 'Silver Spring' && studio2_name == 'Columbia') ||
         (studio1_name == 'Columbia' && studio2_name == 'Silver Spring')
        Rails.logger.debug "  Pair position found: #{pair_position.present?}"
        Rails.logger.debug "  Position: #{pair_position}" if pair_position
      end
      
      if pair_position
        # Reserve positions for this studio pair
        total_groups.each_with_index do |group, i|
          pos = calculate_pair_position(pair_position, i, total_tables, total_people <= 10)
          
          if pos && pos[:row] >= 1 && pos[:col] >= 1 && pos[:col] <= max_cols &&
             !used_positions.include?("#{pos[:row]},#{pos[:col]}")
            
            used_positions.add("#{pos[:row]},#{pos[:col]}")
            processed_groups.add(group[:index])
            
            reservations << {
              position: pos,
              purpose: :studio_pair,
              priority: 0,
              pair: "#{studio1_name} ↔ #{studio2_name}",
              studio: group[:primary_studio],
              group: group,
              shared_table: total_people <= 10
            }
          end
        end
      end
    end
    
    # PRIORITY 1: Multi-table conflicts (multiple large studios sharing one multi-table)
    # Skip groups already processed by Priority 0
    multi_tables_with_conflicts = analyzed_groups.select do |group|
      !processed_groups.include?(group[:index]) &&
      group[:is_multi] && 
      group[:has_large_studios] && 
      group[:studios].count { |s| large_studios.include?(s) } > 1
    end
    
    multi_tables_with_conflicts.each do |multi_group|
      conflicted_large_studios = multi_group[:studios].select { |s| large_studios.include?(s) }
      
      # Find corresponding pure tables for these studios (skip already processed)
      pure_tables_needed = conflicted_large_studios.map do |studio_name|
        analyzed_groups.find do |group|
          !processed_groups.include?(group[:index]) &&
          !group[:is_multi] && 
          group[:studios] == [studio_name]
        end
      end.compact
      
      if pure_tables_needed.size >= 2
        # This multi-table needs multiple adjacent positions reserved
        center_pos = find_optimal_center_position_for_conflict(max_cols, used_positions)
        
        if center_pos
          used_positions.add("#{center_pos[:row]},#{center_pos[:col]}")
          processed_groups.add(multi_group[:index])
          
          # Reserve the center position for the multi-table
          reservations << {
            position: center_pos,
            purpose: :multi_table_conflict,
            priority: 1,
            multi_group: multi_group,
            pure_groups: pure_tables_needed,
            studios: conflicted_large_studios
          }
          
          # Reserve adjacent positions for the pure tables
          adjacent_positions = [
            { row: center_pos[:row] - 1, col: center_pos[:col] },
            { row: center_pos[:row] + 1, col: center_pos[:col] },
            { row: center_pos[:row], col: center_pos[:col] - 1 },
            { row: center_pos[:row], col: center_pos[:col] + 1 }
          ].select { |pos| pos[:row] >= 1 && pos[:col] >= 1 && pos[:col] <= max_cols }
          
          pure_tables_needed.take(adjacent_positions.size).each_with_index do |pure_group, i|
            pos = adjacent_positions[i]
            used_positions.add("#{pos[:row]},#{pos[:col]}")
            processed_groups.add(pure_group[:index])
            
            reservations << {
              position: pos,
              purpose: :conflict_pure_table,
              priority: 1,
              multi_group: multi_group,
              pure_group: pure_group,
              studio: pure_group[:studios].first
            }
          end
        end
      end
    end
    
    # PRIORITY 2: Simple large studio splits (like Lincolnshire)
    # Find large studios that have multiple tables but no complex conflicts
    priority2_studios = []
    large_studio_groups = analyzed_groups.group_by { |g| g[:primary_studio] }
    
    large_studio_groups.each do |studio_name, groups|
      next unless large_studios.include?(studio_name)
      next if groups.size < 2  # Only care about studios with multiple tables
      
      # Check if this studio is already handled by priority 0 or 1
      already_handled = groups.any? { |g| processed_groups.include?(g[:index]) } ||
                       reservations.any? do |res|
                         (res[:priority] <= 1) && 
                         (res[:studios]&.include?(studio_name) || res[:studio] == studio_name)
                       end
      
      next if already_handled
      
      # This is a simple split studio case
      pure_groups = groups.select { |g| !g[:is_multi] }
      mixed_groups = groups.select { |g| g[:is_multi] }
      
      if pure_groups.size >= 2 || (pure_groups.size >= 1 && mixed_groups.size >= 1)
        priority2_studios << {
          studio: studio_name,
          pure_groups: pure_groups,
          mixed_groups: mixed_groups,
          total_tables: pure_groups.size + mixed_groups.size,
          people_count: (pure_groups + mixed_groups).sum { |g| g[:people].size }
        }
      end
    end
    
    # Sort Priority 2 studios by people count (larger studios get first pick of positions)
    priority2_studios.sort_by! { |s| -s[:people_count] }
    
    # Distribute Priority 2 studios across different grid areas to avoid conflicts
    grid_areas = [
      { name: "top-left", rows: (1..2), cols: (1..3) },
      { name: "top-right", rows: (1..2), cols: (6..8) },
      { name: "bottom-left", rows: (3..4), cols: (1..3) },
      { name: "bottom-right", rows: (3..4), cols: (6..8) },
      { name: "center", rows: (2..3), cols: (4..5) }
    ]
    
    priority2_studios.each_with_index do |studio_info, index|
      # Assign studio to a grid area (cycle through areas to distribute)
      area = grid_areas[index % grid_areas.size]
      
      # Find best available block within this area
      block_position = find_available_block_in_area(
        studio_info[:total_tables], 
        area[:rows], 
        area[:cols], 
        used_positions
      )
      
      if block_position
        # Reserve positions for all tables from this studio
        all_studio_groups = studio_info[:pure_groups] + studio_info[:mixed_groups]
        all_studio_groups.each_with_index do |group, i|
          pos = calculate_block_position(block_position, i, studio_info[:total_tables])
          
          # Make sure position is valid and available
          if pos[:row] >= 1 && pos[:col] >= 1 && pos[:col] <= max_cols && 
             !used_positions.include?("#{pos[:row]},#{pos[:col]}")
            
            used_positions.add("#{pos[:row]},#{pos[:col]}")
            processed_groups.add(group[:index])
            
            reservations << {
              position: pos,
              purpose: :large_studio_split,
              priority: 2,
              studio: studio_info[:studio],
              group: group,
              grid_area: area[:name]
            }
          end
        end
      else
        # Fallback: use original block positioning if area-based fails
        block_position = find_available_block_position(studio_info[:total_tables], max_cols, used_positions)
        
        if block_position
          all_studio_groups = studio_info[:pure_groups] + studio_info[:mixed_groups]
          all_studio_groups.each_with_index do |group, i|
            pos = {
              row: block_position[:row] + (i / 2),  # Two tables per row
              col: block_position[:col] + (i % 2)
            }
            
            if pos[:row] >= 1 && pos[:col] >= 1 && pos[:col] <= max_cols && 
               !used_positions.include?("#{pos[:row]},#{pos[:col]}")
              
              used_positions.add("#{pos[:row]},#{pos[:col]}")
              processed_groups.add(group[:index])
              
              reservations << {
                position: pos,
                purpose: :large_studio_split,
                priority: 2,
                studio: studio_info[:studio],
                group: group,
                grid_area: "fallback"
              }
            end
          end
        end
      end
    end
    
    reservations
  end
  
  def find_optimal_center_position_for_conflict(max_cols, used_positions = Set.new)
    # Find a good center position for high-conflict multi-tables
    # Prefer positions with maximum adjacent slots available and not already used
    
    center_candidates = []
    
    # Check positions in the center area (avoid edges)
    (2..3).each do |row|
      (3..6).each do |col|
        next if used_positions.include?("#{row},#{col}")
        
        # Count available adjacent positions (not used)
        adjacent_positions = [
          { row: row - 1, col: col },
          { row: row + 1, col: col },
          { row: row, col: col - 1 },
          { row: row, col: col + 1 }
        ].select { |pos| pos[:row] >= 1 && pos[:col] >= 1 && pos[:col] <= max_cols }
        
        available_adjacent = adjacent_positions.count do |pos|
          !used_positions.include?("#{pos[:row]},#{pos[:col]}")
        end
        
        center_candidates << { row: row, col: col, available_adjacent: available_adjacent }
      end
    end
    
    # Return position with most available adjacent slots
    best_candidate = center_candidates.max_by { |pos| pos[:available_adjacent] }
    best_candidate ? { row: best_candidate[:row], col: best_candidate[:col] } : nil
  end
  
  def find_available_block_position(table_count, max_cols, used_positions)
    # Find a contiguous block of positions for a studio's tables
    # Try to place them in a 2x2 or 2x1 pattern for adjacency
    
    # For 2 tables, try horizontal pairs first, then vertical
    if table_count == 2
      # Try horizontal pairs (side by side)
      (1..4).each do |row|
        (1..max_cols-1).each do |col|
          pos1 = "#{row},#{col}"
          pos2 = "#{row},#{col+1}"
          
          unless used_positions.include?(pos1) || used_positions.include?(pos2)
            return { row: row, col: col }
          end
        end
      end
      
      # Try vertical pairs (one above the other)
      (1..3).each do |row|
        (1..max_cols).each do |col|
          pos1 = "#{row},#{col}"
          pos2 = "#{row+1},#{col}"
          
          unless used_positions.include?(pos1) || used_positions.include?(pos2)
            return { row: row, col: col }
          end
        end
      end
    end
    
    # For 3+ tables, try 2x2 blocks
    if table_count >= 3
      (1..3).each do |row|
        (1..max_cols-1).each do |col|
          block_positions = [
            "#{row},#{col}", "#{row},#{col+1}",
            "#{row+1},#{col}", "#{row+1},#{col+1}"
          ]
          
          if block_positions.none? { |pos| used_positions.include?(pos) }
            return { row: row, col: col }
          end
        end
      end
    end
    
    # Fallback: just find any available position
    (1..4).each do |row|
      (1..max_cols).each do |col|
        unless used_positions.include?("#{row},#{col}")
          return { row: row, col: col }
        end
      end
    end
    
    nil
  end
  
  def find_optimal_pair_position_shared(table_count, max_cols, used_positions)
    # Find position for studio pairs that should share tables
    # Priority: good central locations that can accommodate the pair
    
    (1..4).each do |row|
      (2..6).each do |col|
        if table_count == 1
          unless used_positions.include?("#{row},#{col}")
            return { row: row, col: col }
          end
        else
          # Two tables - try adjacent positions
          positions_needed = ["#{row},#{col}", "#{row},#{col+1}"]
          if col+1 <= max_cols && positions_needed.none? { |pos| used_positions.include?(pos) }
            return { row: row, col: col }
          end
        end
      end
    end
    
    nil
  end
  
  def find_optimal_pair_position_adjacent(table_count, max_cols, used_positions)
    # Find position for studio pairs that need adjacent tables
    # Similar to block positioning but prioritize adjacency
    
    find_available_block_position(table_count, max_cols, used_positions)
  end
  
  def calculate_pair_position(pair_start, table_index, total_tables, shared_table)
    if shared_table || total_tables == 1
      # All tables in same position (shared) or single table
      pair_start
    else
      # Adjacent positioning
      case total_tables
      when 2
        if table_index == 0
          pair_start
        else
          { row: pair_start[:row], col: pair_start[:col] + 1 }
        end
      else
        # More complex positioning for larger pairs
        row_offset = table_index / 2
        col_offset = table_index % 2
        { row: pair_start[:row] + row_offset, col: pair_start[:col] + col_offset }
      end
    end
  end
  
  def find_available_block_in_area(table_count, row_range, col_range, used_positions)
    # Find a contiguous block within a specific grid area
    
    # For 2 tables, try horizontal and vertical pairs within the area
    if table_count == 2
      # Try horizontal pairs (side by side)
      row_range.each do |row|
        col_range.each do |col|
          next if col == col_range.last  # Can't place horizontally if at right edge
          
          pos1 = "#{row},#{col}"
          pos2 = "#{row},#{col+1}"
          
          if !used_positions.include?(pos1) && !used_positions.include?(pos2) &&
             col_range.include?(col+1)  # Make sure second position is in range
            return { row: row, col: col }
          end
        end
      end
      
      # Try vertical pairs (one above the other)
      row_range.each do |row|
        next if row == row_range.last  # Can't place vertically if at bottom edge
        
        col_range.each do |col|
          pos1 = "#{row},#{col}"
          pos2 = "#{row+1},#{col}"
          
          if !used_positions.include?(pos1) && !used_positions.include?(pos2) &&
             row_range.include?(row+1)  # Make sure second position is in range
            return { row: row, col: col }
          end
        end
      end
    end
    
    # For 3+ tables, try 2x2 blocks within the area
    if table_count >= 3
      row_range.each do |row|
        next if row == row_range.last  # Need space for row+1
        
        col_range.each do |col|
          next if col == col_range.last  # Need space for col+1
          
          block_positions = [
            "#{row},#{col}", "#{row},#{col+1}",
            "#{row+1},#{col}", "#{row+1},#{col+1}"
          ]
          
          if block_positions.none? { |pos| used_positions.include?(pos) } &&
             row_range.include?(row+1) && col_range.include?(col+1)
            return { row: row, col: col }
          end
        end
      end
    end
    
    # Fallback: find any single position in the area
    row_range.each do |row|
      col_range.each do |col|
        unless used_positions.include?("#{row},#{col}")
          return { row: row, col: col }
        end
      end
    end
    
    nil
  end
  
  def calculate_block_position(block_start, table_index, total_tables)
    # Calculate position for a table within a reserved block
    case total_tables
    when 2
      # For 2 tables, place horizontally first, then vertically
      if table_index == 0
        { row: block_start[:row], col: block_start[:col] }
      else
        # Try horizontal first
        { row: block_start[:row], col: block_start[:col] + 1 }
      end
    when 3, 4
      # For 3-4 tables, use 2x2 block pattern
      row_offset = table_index / 2
      col_offset = table_index % 2
      { row: block_start[:row] + row_offset, col: block_start[:col] + col_offset }
    else
      # Fallback for more tables
      row_offset = table_index / 2
      col_offset = table_index % 2
      { row: block_start[:row] + row_offset, col: block_start[:col] + col_offset }
    end
  end
  
  def group_by_studio_relationships(analyzed_groups)
    # Group related tables together
    studio_sets = []
    processed_indices = Set.new
    
    # 1. Event Staff (highest priority)
    event_staff_groups = analyzed_groups.select { |g| g[:is_event_staff] }
    if event_staff_groups.any?
      studio_sets << {
        type: :event_staff,
        priority: 100,
        groups: event_staff_groups
      }
      event_staff_groups.each { |g| processed_indices.add(g[:index]) }
    end
    
    # 2. Large studios (group all tables from same studio)
    large_studios = ['Columbia', 'Bucharest', 'Lincolnshire', 'NY-Broadway', 'Waco', 'Greenwich']
    large_studios.each do |studio_name|
      studio_groups = analyzed_groups.select do |g|
        !processed_indices.include?(g[:index]) && 
        (g[:studios].include?(studio_name) || g[:primary_studio] == studio_name)
      end
      
      if studio_groups.any?
        # Sort: multi-tables first, then pure tables
        studio_groups.sort_by! { |g| [g[:is_multi] ? 0 : 1, -g[:priority]] }
        
        studio_sets << {
          type: :large_studio,
          studio_name: studio_name,
          priority: 70,
          groups: studio_groups
        }
        studio_groups.each { |g| processed_indices.add(g[:index]) }
      end
    end
    
    # 3. Remaining groups (small studios)
    remaining_groups = analyzed_groups.reject { |g| processed_indices.include?(g[:index]) }
    if remaining_groups.any?
      studio_sets << {
        type: :remaining,
        priority: 10,
        groups: remaining_groups
      }
    end
    
    # Sort studio sets by priority
    studio_sets.sort_by { |set| -set[:priority] }
  end
  
  def place_studio_set(studio_set, positions, max_cols, created_tables, reserved_positions)
    if studio_set[:type] == :event_staff
      # Place Event Staff in a compact block
      place_event_staff_set(studio_set[:groups], positions, max_cols, created_tables, reserved_positions)
    elsif studio_set[:type] == :large_studio
      # Place large studio tables adjacent to each other
      place_large_studio_set(studio_set, positions, max_cols, created_tables, reserved_positions)
    else
      # Place remaining groups individually
      place_remaining_groups_set(studio_set[:groups], positions, max_cols, created_tables, reserved_positions)
    end
  end
  
  def place_event_staff_set(event_staff_groups, positions, max_cols, created_tables, reserved_positions)
    event_staff_groups.each_with_index do |group_info, index|
      table = create_and_assign_table(created_tables.size + 1, group_info[:people])
      pos = find_event_staff_position(positions, max_cols, index)
      
      if pos
        positions << pos
        table.update!(row: pos[:row], col: pos[:col])
      end
      
      created_tables << table
    end
  end
  
  def place_large_studio_set(studio_set, positions, max_cols, created_tables, reserved_positions)
    groups = studio_set[:groups]
    
    # Check if any groups have reserved positions
    groups.each do |group|
      reservation = find_reservation_for_group(group, reserved_positions)
      
      if reservation
        # This group has a reserved position - use it
        table = create_and_assign_table(created_tables.size + 1, group[:people])
        pos = reservation[:position]
        
        if pos && !position_occupied?(pos, positions)
          positions << pos
          table.update!(row: pos[:row], col: pos[:col])
          created_tables << table
          
          # Mark this reservation as used
          mark_reservation_used(reservation, reserved_positions)
        else
          # Fallback if reserved position is somehow occupied
          fallback_placement_for_group(group, positions, max_cols, created_tables, reserved_positions)
        end
      else
        # No reservation - use normal placement logic
        fallback_placement_for_group(group, positions, max_cols, created_tables, reserved_positions)
      end
    end
  end
  
  def find_reservation_for_group(group, reserved_positions)
    # Find a reservation that matches this group
    reserved_positions.find do |reservation|
      next if reservation[:used]
      
      case reservation[:purpose]
      when :studio_pair
        # Check if this is one of the groups in the studio pair
        reservation[:group][:index] == group[:index]
      when :multi_table_conflict
        # Check if this is the multi-table for this reservation
        reservation[:multi_group][:index] == group[:index]
      when :conflict_pure_table
        # Check if this is one of the pure tables for this reservation
        reservation[:pure_group][:index] == group[:index]
      when :large_studio_split
        # Check if this is one of the groups for this studio
        reservation[:group][:index] == group[:index]
      else
        false
      end
    end
  end
  
  def mark_reservation_used(reservation, reserved_positions)
    reservation[:used] = true
  end
  
  def position_occupied?(pos, positions)
    positions.any? { |p| p[:row] == pos[:row] && p[:col] == pos[:col] }
  end
  
  def fallback_placement_for_group(group, positions, max_cols, created_tables, reserved_positions)
    # Original placement logic for groups without reservations
    table = create_and_assign_table(created_tables.size + 1, group[:people])
    
    if group[:is_multi] && group[:has_large_studios]
      pos = find_center_position(positions, max_cols, reserved_positions)
    else
      pos = find_next_position(positions, max_cols, reserved_positions)
    end
    
    if pos
      positions << pos
      table.update!(row: pos[:row], col: pos[:col])
    end
    
    created_tables << table
  end
  
  
  def place_remaining_groups_set(remaining_groups, positions, max_cols, created_tables, reserved_positions)
    remaining_groups.each do |group_info|
      table = create_and_assign_table(created_tables.size + 1, group_info[:people])
      pos = find_next_position(positions, max_cols, reserved_positions)
      
      if pos
        positions << pos
        table.update!(row: pos[:row], col: pos[:col])
      end
      
      created_tables << table
    end
  end
  
  def calculate_group_priority(studios, large_studios)
    # Higher priority = placed first
    if studios == ['Event Staff']
      100  # Highest priority
    elsif studios.size > 1 && studios.any? { |s| large_studios.include?(s) }
      80   # High-priority multi-tables
    elsif studios.size == 1 && large_studios.include?(studios.first)
      70   # Large studio pure tables
    elsif studios.size > 1
      30   # Low-priority multi-tables
    else
      10   # Small studio pure tables
    end
  end
  
  def find_event_staff_position(positions, max_cols, event_staff_table_index)
    # Place Event Staff tables in a compact block starting at (4, 1)
    base_row = 4
    base_col = 1
    
    # Try positions in order: (4,1), (4,2), (4,3)..., then (5,1), (5,2)...
    attempt = 0
    loop do
      row = base_row + (attempt / max_cols)
      col = base_col + (attempt % max_cols)
      
      pos = { row: row, col: col }
      
      # Check if this position is available
      unless positions.any? { |p| p[:row] == row && p[:col] == col }
        return pos
      end
      
      attempt += 1
      
      # Safety check
      break if attempt > 50
    end
    
    # Fallback
    find_next_position(positions, max_cols)
  end
  
  
  def find_center_position(positions, max_cols, reserved_positions = [])
    # Find center positions first (maximize adjacency options)
    # Priority order: center positions with 4 adjacent spots, then 3, then 2
    
    # Start from center and work outward
    center_row = 3
    center_col = max_cols / 2
    
    # Try positions in order of adjacency value (4 adjacent spots first)
    center_positions = [
      # 4 adjacent spots (interior positions)
      [2, 3], [2, 4], [2, 5], [2, 6],
      [3, 3], [3, 4], [3, 5], [3, 6],
      [4, 3], [4, 4], [4, 5], [4, 6],
      # 3 adjacent spots (edge but not corner)
      [2, 2], [2, 7], [3, 2], [3, 7], [4, 2], [4, 7],
      [1, 3], [1, 4], [1, 5], [1, 6],
      # 2 adjacent spots (corners)
      [1, 1], [1, 8]
    ]
    
    center_positions.each do |row, col|
      next if row < 1 || col < 1 || col > max_cols
      
      # Check if position is occupied OR reserved for someone else
      unless position_occupied?({row: row, col: col}, positions) || position_reserved_for_others?({row: row, col: col}, reserved_positions)
        return { row: row, col: col }
      end
    end
    
    # Fall back to sequential search if no center positions available
    find_next_position(positions, max_cols, reserved_positions)
  end
  
  def optimize_placement_for_adjacency(created_tables, analyzed_groups, max_cols)
    # Post-placement optimization to improve adjacency for both studio pairs and multi-table studios
    # This is particularly important for cases like Friday Lunch where Columbia could move
    # to help both Silver Spring pairing and NY-Broadway adjacency
    
    
    # Build a map of current table positions and their contents
    table_positions = {}
    position_to_table = {}
    
    created_tables.each do |table|
      next unless table.row && table.col
      pos_key = "#{table.row},#{table.col}"
      position_to_table[pos_key] = table
      
      # Get studio info for this table
      studios = if table.option_id
                  table.person_options.includes(:person => :studio).map { |po| po.person.studio.name }.uniq.sort
                else
                  table.people.includes(:studio).map { |p| p.studio.name }.uniq.sort
                end
      
      table_positions[table.id] = {
        table: table,
        studios: studios,
        is_single_studio: studios.size == 1,
        primary_studio: studios.first,
        row: table.row,
        col: table.col
      }
    end
    
    # Find multi-table studios that need adjacency
    studio_tables = {}
    table_positions.each do |table_id, info|
      if info[:is_single_studio]
        studio_name = info[:primary_studio]
        studio_tables[studio_name] ||= []
        studio_tables[studio_name] << info
      end
    end
    
    # Find studios with multiple tables that aren't adjacent
    non_adjacent_studios = []
    studio_tables.each do |studio_name, tables|
      next if tables.size < 2
      
      # Check if all tables are adjacent
      all_adjacent = true
      tables.combination(2).each do |t1, t2|
        distance = (t1[:row] - t2[:row]).abs + (t1[:col] - t2[:col]).abs
        if distance > 1
          all_adjacent = false
          break
        end
      end
      
      unless all_adjacent
        non_adjacent_studios << {
          studio: studio_name,
          tables: tables,
          table_count: tables.size
        }
      end
    end
    
    # Find studio pairs that aren't adjacent or sharing tables
    studio_pairs = StudioPair.includes(:studio1, :studio2)
    non_adjacent_pairs = []
    
    studio_pairs.each do |pair|
      studio1_tables = studio_tables[pair.studio1.name] || []
      studio2_tables = studio_tables[pair.studio2.name] || []
      
      next if studio1_tables.empty? || studio2_tables.empty?
      
      # Check if they share any tables
      shared = false
      table_positions.each do |_, info|
        if info[:studios].include?(pair.studio1.name) && info[:studios].include?(pair.studio2.name)
          shared = true
          break
        end
      end
      
      next if shared
      
      # Check minimum distance between their tables
      min_distance = Float::INFINITY
      studio1_tables.each do |t1|
        studio2_tables.each do |t2|
          distance = (t1[:row] - t2[:row]).abs + (t1[:col] - t2[:col]).abs
          min_distance = [min_distance, distance].min
        end
      end
      
      if min_distance > 1
        non_adjacent_pairs << {
          studio1: pair.studio1.name,
          studio2: pair.studio2.name,
          studio1_tables: studio1_tables,
          studio2_tables: studio2_tables,
          min_distance: min_distance
        }
      end
    end
    
    # Try to fix adjacency issues by swapping single-table studios
    # Priority: Fix multi-table adjacency first, then studio pairs
    non_adjacent_studios.sort_by! { |s| -s[:table_count] } # Larger studios first
    
    non_adjacent_studios.each do |studio_info|
      # For each non-adjacent multi-table studio, try to find better positions
      tables = studio_info[:tables]
      
      # Find a contiguous block that could fit all tables
      best_block = find_best_contiguous_block(tables.size, position_to_table, max_cols)
      
      next unless best_block
      
      # Check if we can swap with single-table studios currently in those positions
      can_swap = true
      tables_to_swap = []
      
      best_block.each do |pos_key|
        current_table = position_to_table[pos_key]
        if current_table
          info = table_positions[current_table.id]
          # Only swap with single-studio, single-table studios (not Event Staff)
          if info[:is_single_studio] && info[:primary_studio] != 'Event Staff'
            studio_table_count = studio_tables[info[:primary_studio]].size
            if studio_table_count == 1
              tables_to_swap << current_table
            else
              can_swap = false
              break
            end
          else
            can_swap = false
            break
          end
        end
      end
      
      if can_swap && tables_to_swap.size > 0
        # Perform the swap
        perform_table_position_swap(tables, tables_to_swap, best_block, position_to_table, table_positions)
        
        # Update studio_tables for future iterations
        studio_tables[studio_info[:studio]] = []
        table_positions.each do |_, info|
          if info[:is_single_studio] && info[:primary_studio] == studio_info[:studio]
            studio_tables[studio_info[:studio]] << info
          end
        end
      end
    end
    
    # Now try to fix studio pairs by moving single-table studios
    non_adjacent_pairs.each do |pair_info|
      # Skip if either studio has multiple tables (handled above)
      next if pair_info[:studio1_tables].size > 1 || pair_info[:studio2_tables].size > 1
      
      # Both are single tables - try to move one next to the other
      table1 = pair_info[:studio1_tables].first
      table2 = pair_info[:studio2_tables].first
      
      # Find adjacent positions to table1
      adjacent_positions = [
        { row: table1[:row] - 1, col: table1[:col] },
        { row: table1[:row] + 1, col: table1[:col] },
        { row: table1[:row], col: table1[:col] - 1 },
        { row: table1[:row], col: table1[:col] + 1 }
      ].select { |pos| pos[:row] >= 1 && pos[:row] <= 5 && pos[:col] >= 1 && pos[:col] <= max_cols }
      
      # Try to move table2 to an adjacent position
      adjacent_positions.each do |new_pos|
        pos_key = "#{new_pos[:row]},#{new_pos[:col]}"
        current_occupant = position_to_table[pos_key]
        
        if current_occupant.nil?
          # Empty position - just move table2 here
          table2[:table].update!(row: new_pos[:row], col: new_pos[:col])
          old_pos_key = "#{table2[:row]},#{table2[:col]}"
          position_to_table.delete(old_pos_key)
          position_to_table[pos_key] = table2[:table]
          table2[:row] = new_pos[:row]
          table2[:col] = new_pos[:col]
          break
        elsif current_occupant != table2[:table]
          # Check if we can swap
          occupant_info = table_positions[current_occupant.id]
          if occupant_info[:is_single_studio] && 
             occupant_info[:primary_studio] != 'Event Staff' &&
             studio_tables[occupant_info[:primary_studio]].size == 1
            # Perform swap
            perform_simple_table_swap(table2[:table], current_occupant, table_positions, position_to_table)
            break
          end
        end
      end
    end
  end
  
  def find_best_contiguous_block(table_count, position_to_table, max_cols)
    # Find the best contiguous block of positions for the given number of tables
    best_block = nil
    best_score = Float::INFINITY
    
    # Try different block configurations
    if table_count == 2
      # Try horizontal pairs
      (1..5).each do |row|
        (1..max_cols-1).each do |col|
          block = ["#{row},#{col}", "#{row},#{col+1}"]
          score = calculate_block_disruption_score(block, position_to_table)
          if score < best_score
            best_score = score
            best_block = block
          end
        end
      end
      
      # Try vertical pairs
      (1..4).each do |row|
        (1..max_cols).each do |col|
          block = ["#{row},#{col}", "#{row+1},#{col}"]
          score = calculate_block_disruption_score(block, position_to_table)
          if score < best_score
            best_score = score
            best_block = block
          end
        end
      end
    elsif table_count == 3
      # Try L-shapes and lines
      (1..4).each do |row|
        (1..max_cols-1).each do |col|
          # Horizontal L
          block = ["#{row},#{col}", "#{row},#{col+1}", "#{row+1},#{col}"]
          score = calculate_block_disruption_score(block, position_to_table)
          if score < best_score
            best_score = score
            best_block = block
          end
        end
      end
    end
    
    best_block
  end
  
  def calculate_block_disruption_score(block, position_to_table)
    # Lower score = less disruption
    # Prefer blocks that are empty or contain only single-table studios
    score = 0
    
    block.each do |pos_key|
      if position_to_table[pos_key]
        score += 10  # Occupied position
      else
        score += 1   # Empty position (slight preference for occupied to minimize gaps)
      end
    end
    
    score
  end
  
  def perform_table_position_swap(moving_tables, displaced_tables, new_positions, position_to_table, table_positions)
    # Save old positions of moving tables
    old_positions = moving_tables.map { |t| "#{t[:row]},#{t[:col]}" }
    
    # Move displaced tables to old positions of moving tables
    displaced_tables.each_with_index do |table, i|
      if i < old_positions.size
        old_pos = old_positions[i]
        row, col = old_pos.split(',').map(&:to_i)
        
        # Update position maps
        current_pos = "#{table.row},#{table.col}"
        position_to_table.delete(current_pos)
        position_to_table[old_pos] = table
        
        # Update table
        table.update!(row: row, col: col)
        
        # Update table_positions
        if table_positions[table.id]
          table_positions[table.id][:row] = row
          table_positions[table.id][:col] = col
        end
      end
    end
    
    # Move moving tables to new positions
    moving_tables.each_with_index do |table_info, i|
      if i < new_positions.size
        new_pos = new_positions[i]
        row, col = new_pos.split(',').map(&:to_i)
        
        # Update position maps
        old_pos = "#{table_info[:row]},#{table_info[:col]}"
        position_to_table.delete(old_pos)
        position_to_table[new_pos] = table_info[:table]
        
        # Update table
        table_info[:table].update!(row: row, col: col)
        
        # Update table_positions
        table_info[:row] = row
        table_info[:col] = col
      end
    end
  end
  
  def perform_simple_table_swap(table1, table2, table_positions, position_to_table)
    # Swap positions of two tables
    t1_row, t1_col = table1.row, table1.col
    t2_row, t2_col = table2.row, table2.col
    
    t1_pos = "#{t1_row},#{t1_col}"
    t2_pos = "#{t2_row},#{t2_col}"
    
    # Update position map
    position_to_table[t1_pos] = table2
    position_to_table[t2_pos] = table1
    
    # Update tables
    table1.update!(row: t2_row, col: t2_col)
    table2.update!(row: t1_row, col: t1_col)
    
    # Update table_positions
    if table_positions[table1.id]
      table_positions[table1.id][:row] = t2_row
      table_positions[table1.id][:col] = t2_col
    end
    if table_positions[table2.id]
      table_positions[table2.id][:row] = t1_row
      table_positions[table2.id][:col] = t1_col
    end
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
