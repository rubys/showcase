require 'set'

class TablesController < ApplicationController
  include Printable
  include TableAssigner
  
  before_action :set_table, only: %i[ show edit update destroy ]
  before_action :set_option, only: %i[ index new create arrange assign pack studio move_person reset update_positions renumber ]

  # GET /tables or /tables.json
  def index
    @tables = Table.includes(people: :studio).where(option_id: @option&.id).order(:row, :col)
    @columns = (Table.maximum(:col) || 7) + 1
    
    # Add capacity status for each table
    @tables.each do |table|
      # Get table size: individual table > option > event > default (10)
      table_size = table.size
      if table_size.nil? || table_size == 0
        table_size = @option&.computed_table_size || Event.current&.table_size || 10
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
      # Get table size: individual table > option > event > default (10)
      table_size = table.size
      if table_size.nil? || table_size == 0
        table_size = @option&.computed_table_size || Event.current&.table_size || 10
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
    table_size = @table.computed_table_size
    if @table.option_id
      # For option tables, count people through person_options
      current_people_count = @table.person_options.count
    else
      # For main event tables, count people directly
      current_people_count = @table.people.count
    end
    
    # Get studios with unassigned people
    if @table.option_id
      # For option tables, get studios with people who have this option but no table
      @studios_with_unassigned = Studio.joins(:people => :options)
                                       .where(person_options: { option_id: @table.option_id, table_id: nil })
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
    
    # Set available seats if table has capacity
    if current_people_count < table_size
      @available_seats = table_size - current_people_count
    end
  end

  # POST /tables or /tables.json
  def create
    @table = Table.new(table_params.except(:studio_id, :create_additional_tables))
    @table.option_id = @option&.id

    respond_to do |format|
      if @table.save
        created_tables = [@table]
        
        # Auto-fill table with people from selected studio if provided
        if params[:table][:studio_id].present?
          studio_id = params[:table][:studio_id].to_i
          
          if params[:table][:create_additional_tables] == '1'
            # Create multiple tables if needed
            created_tables = create_tables_for_studio_with_pairs(@table, studio_id)
          else
            # Just fill the current table
            fill_table_with_studio_people(@table, studio_id)
          end
        end
        
        if created_tables.size > 1
          format.html { redirect_to tables_path(option_id: @option&.id), notice: "#{created_tables.size} tables were successfully created." }
        else
          format.html { redirect_to tables_path(option_id: @option&.id), notice: "Table was successfully created." }
        end
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
          if @table.update(table_params.except(:studio_id, :create_additional_tables))
            # Auto-fill table with people from selected studio if provided
            if params[:table][:studio_id].present?
              studio_id = params[:table][:studio_id].to_i
              
              if params[:table][:create_additional_tables] == '1'
                # Create multiple tables if needed
                created_tables = create_tables_for_studio_with_pairs(@table, studio_id)
                notice_msg = "Table was successfully updated. Swapped numbers with Table #{old_number}."
                notice_msg += " #{created_tables.size - 1} additional tables were created." if created_tables.size > 1
              else
                fill_table_with_studio_people(@table, studio_id)
                notice_msg = "Table was successfully updated. Swapped numbers with Table #{old_number}."
              end
            else
              notice_msg = "Table was successfully updated. Swapped numbers with Table #{old_number}."
            end
            
            format.html { redirect_to tables_path(option_id: @table.option_id), notice: notice_msg }
            format.json { render :show, status: :ok, location: @table }
          else
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: @table.errors, status: :unprocessable_entity }
          end
        end
      elsif @table.update(table_params.except(:studio_id, :create_additional_tables))
        # Auto-fill table with people from selected studio if provided
        if params[:table][:studio_id].present?
          studio_id = params[:table][:studio_id].to_i
          
          if params[:table][:create_additional_tables] == '1'
            # Create multiple tables if needed
            created_tables = create_tables_for_studio_with_pairs(@table, studio_id)
            notice_msg = created_tables.size > 1 ? "Table was successfully updated. #{created_tables.size - 1} additional tables were created." : "Table was successfully updated."
          else
            fill_table_with_studio_people(@table, studio_id)
            notice_msg = "Table was successfully updated."
          end
        else
          notice_msg = "Table was successfully updated."
        end
        
        format.html { redirect_to tables_path(option_id: @table.option_id), notice: notice_msg }
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
    assign_tables(pack: false)
  end

  def pack
    assign_tables(pack: true)
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
  
  def by_studio
    @event = Event.current
    @font_size = @event.font_size
    @nologo = true
    
    # Data structure: {option => {studio => [tables]}}
    @options_studios_tables = {}
    
    # Process main event tables first
    main_tables = Table.includes(people: :studio).where(option_id: nil).order(:number)
    if main_tables.any?
      studios_tables = {}
      
      main_tables.each do |table|
        table.people.group_by(&:studio).each do |studio, people|
          studios_tables[studio] ||= []
          studios_tables[studio] << {
            table: table,
            people: people
          }
        end
      end
      
      # Sort by studio name and remove duplicates
      sorted_studios_tables = {}
      studios_tables.keys.sort_by(&:name).each do |studio|
        sorted_studios_tables[studio] = studios_tables[studio].uniq { |st| st[:table].id }
      end
      
      @options_studios_tables["Main Event"] = sorted_studios_tables if sorted_studios_tables.any?
    end
    
    # Process option tables
    Billable.where(type: 'Option').order(:order, :name).each do |option|
      option_tables = Table.includes(:person_options => {:person => :studio})
                           .where(option_id: option.id)
                           .order(:number)
      
      next unless option_tables.any?
      
      studios_tables = {}
      
      option_tables.each do |table|
        # Group people at this table by studio
        people_by_studio = {}
        table.person_options.each do |po|
          studio = po.person.studio
          people_by_studio[studio] ||= []
          people_by_studio[studio] << po.person
        end
        
        people_by_studio.each do |studio, people|
          studios_tables[studio] ||= []
          studios_tables[studio] << {
            table: table,
            people: people
          }
        end
      end
      
      # Sort by studio name and remove duplicates
      sorted_studios_tables = {}
      studios_tables.keys.sort_by(&:name).each do |studio|
        sorted_studios_tables[studio] = studios_tables[studio].uniq { |st| st[:table].id }
      end
      
      @options_studios_tables[option.name] = sorted_studios_tables if sorted_studios_tables.any?
    end

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: "tables-by-studio"
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
      table_size = table.computed_table_size
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
          
          studio_tables[studio_id] ||= []
          studio_tables[studio_id] << {
            table: table,
            people_count: studio_people.count,
            studio_name: studio_people.first.studio&.name || "Event Staff"
          }
        end
      end
      
      # Check for studios with multiple tables
      studio_tables.each do |studio_id, table_data|
        next if table_data.length <= 1
        
        studio_name = table_data.first[:studio_name]
        table_numbers = table_data.map { |td| td[:table].number }.sort
        
        # Check if this studio's tables are properly contiguous
        # This includes both direct adjacency and hub-and-spoke patterns
        tables_with_positions = table_data.map { |td| td[:table] }.select { |t| t.row && t.col }
        
        is_non_contiguous = false
        
        if tables_with_positions.length > 1
          # Check if tables are contiguous using enhanced logic
          if !studio_tables_contiguous?(studio_id, tables_with_positions, tables)
            is_non_contiguous = true
          end
        elsif tables_with_positions.length == 0
          # No position data available, fall back to table number contiguity
          if !contiguous_numbers?(table_numbers)
            is_non_contiguous = true
          end
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

  def studio_tables_contiguous?(studio_id, tables_with_positions, all_tables)
    return true if tables_with_positions.length <= 1
    
    # First check if tables are directly contiguous
    if contiguous?(tables_with_positions)
      return true
    end
    
    # If not directly contiguous, check for hub-and-spoke pattern
    # Look for mixed tables that might connect this studio's tables
    mixed_tables = find_mixed_tables_for_studio(studio_id, all_tables)
    
    return false if mixed_tables.empty?
    
    # Check if all studio tables are adjacent to at least one mixed table
    mixed_table_positions = mixed_tables.map { |t| [t.row, t.col] }
    
    tables_with_positions.all? do |studio_table|
      # Check if this studio table is adjacent to any mixed table
      mixed_table_positions.any? do |mixed_pos|
        distance = (studio_table.row - mixed_pos[0]).abs + (studio_table.col - mixed_pos[1]).abs
        distance == 1
      end
    end
  end

  def find_mixed_tables_for_studio(studio_id, all_tables)
    mixed_tables = []
    
    all_tables.each do |table|
      # Get all people at this table
      people = if table.option_id
        table.person_options.includes(:person => :studio).map(&:person)
      else
        table.people.includes(:studio)
      end
      
      # Group by studio
      studios_at_table = people.group_by(&:studio_id).keys.reject { |id| id == 0 } # Exclude Event Staff
      
      # If this table has our studio AND other studios, it's a mixed table
      if studios_at_table.include?(studio_id) && studios_at_table.length > 1
        mixed_tables << table
      end
    end
    
    mixed_tables
  end

  def fill_table_with_studio_people(table, studio_id)
    # Determine table size
    table_size = table.size
    if table_size.nil? || table_size.zero?
      option = Billable.find_by(id: table.option_id) if table.option_id
      table_size = option&.computed_table_size || Event.current&.table_size || 10
    end
    
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
  
  def create_tables_for_studio_with_pairs(first_table, studio_id)
    created_tables = [first_table]
    
    # Determine table size
    table_size = first_table.size
    if table_size.nil? || table_size.zero?
      option = Billable.find_by(id: first_table.option_id) if first_table.option_id
      table_size = option&.computed_table_size || Event.current&.table_size || 10
    end
    
    # Get current people count at the first table
    if first_table.option_id
      # For option tables, count people assigned via person_options
      current_people_count = PersonOption.where(table_id: first_table.id).count
    else
      # For main event tables, count people assigned directly
      current_people_count = first_table.people.count
    end
    
    # Get all people from the studio and paired studios
    studio_ids = [studio_id]
    
    # Find paired studios
    paired_studios = StudioPair.where('studio1_id = ? OR studio2_id = ?', studio_id, studio_id)
    paired_studios.each do |pair|
      studio_ids << (pair.studio1_id == studio_id ? pair.studio2_id : pair.studio1_id)
    end
    
    # Get all unassigned people from these studios
    if first_table.option_id
      # For option tables
      all_people = Person.joins(:options)
                         .where(studio_id: studio_ids, type: ['Student', 'Professional', 'Guest', 'Official'])
                         .where(person_options: { option_id: first_table.option_id, table_id: nil })
                         .order('studio_id, name')
    else
      # For main event tables
      all_people = Person.where(studio_id: studio_ids, table_id: nil, type: ['Student', 'Professional', 'Guest'])
                         .order('studio_id, name')
    end
    
    # Group people by studio to maintain studio cohesion
    people_by_studio = all_people.group_by(&:studio_id)
    
    # Fill the first table with its remaining capacity
    current_table = first_table
    seats_filled = current_people_count # Start with existing people count
    
    # Process the main studio first
    if people_by_studio[studio_id]
      people_by_studio[studio_id].each do |person|
        if seats_filled >= table_size
          # Create a new table
          next_number = (Table.where(option_id: first_table.option_id).maximum(:number) || 0) + 1
          current_table = Table.create!(
            number: next_number,
            option_id: first_table.option_id,
            size: first_table.size
          )
          created_tables << current_table
          seats_filled = 0
        end
        
        # Assign person to current table
        if first_table.option_id
          PersonOption.where(person_id: person.id, option_id: first_table.option_id).update_all(table_id: current_table.id)
        else
          person.update!(table_id: current_table.id)
        end
        seats_filled += 1
      end
    end
    
    # Then process paired studios
    people_by_studio.each do |studio_id_in_group, people|
      next if studio_id_in_group == studio_id # Skip main studio as it's already processed
      
      people.each do |person|
        if seats_filled >= table_size
          # Create a new table
          next_number = (Table.where(option_id: first_table.option_id).maximum(:number) || 0) + 1
          current_table = Table.create!(
            number: next_number,
            option_id: first_table.option_id,
            size: first_table.size
          )
          created_tables << current_table
          seats_filled = 0
        end
        
        # Assign person to current table
        if first_table.option_id
          PersonOption.where(person_id: person.id, option_id: first_table.option_id).update_all(table_id: current_table.id)
        else
          person.update!(table_id: current_table.id)
        end
        seats_filled += 1
      end
    end
    
    created_tables
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
      params.expect(table: [ :number, :row, :col, :size, :studio_id, :option_id, :create_additional_tables ])
    end
end
