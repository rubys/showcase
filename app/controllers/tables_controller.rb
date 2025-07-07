class TablesController < ApplicationController
  include Printable
  
  before_action :set_table, only: %i[ show edit update destroy ]
  before_action :set_option, only: %i[ index new create arrange assign studio list move_person reset update_positions renumber ]

  # GET /tables or /tables.json
  def index
    @tables = Table.includes(people: :studio).where(option_id: @option&.id)
    @columns = Table.maximum(:col) || 8
    
    # Add capacity status for each table
    @tables.each do |table|
      table_size = table.size || Event.current&.table_size || 10
      people_count = table.people.count
      
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
      @unassigned_people = Person.includes(:studio)
                                 .joins(:options)
                                 .where(person_options: { option_id: @option.id, table_id: nil })
                                 .where(type: ['Student', 'Professional', 'Guest'])
                                 .where.not(studio_id: 0)  # Exclude Event Staff
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
      people_count = table.people.count
      
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
      @studios_with_unassigned = Studio.joins(:people => :options)
                                       .where(person_options: { option_id: @option.id, table_id: nil })
                                       .where(people: { type: ['Student', 'Professional', 'Guest'] })
                                       .where.not(id: 0)  # Exclude Event Staff
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
    current_people_count = @table.people.count
    
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
        current_people_count = @table.people.count
        
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
      
      # Get table size from event, defaulting to 10
      event = Event.first
      table_size = (event.table_size.nil? || event.table_size == 0) ? 10 : event.table_size
      
      # Get people based on context
      if @option
        # For option tables, get people who have registered for this option
        people = Person.joins(:studio, :options)
                       .where(person_options: { option_id: @option.id })
                       .where.not(studios: { id: 0 })
                       .order('studios.name, people.name')
      else
        # For main event tables, get all people
        people = Person.joins(:studio).where.not(studios: { id: 0 }).order('studios.name, people.name')
      end
      
      # Group people by studio
      studio_groups = people.group_by(&:studio_id).map do |studio_id, studio_people|
        {
          studio_id: studio_id,
          people: studio_people,
          size: studio_people.size,
          studio_name: studio_people.first.studio.name,
          studio: studio_people.first.studio
        }
      end
      
      # Get all studio pairs
      studio_pairs = StudioPair.includes(:studio1, :studio2).map do |pair|
        [pair.studio1.id, pair.studio2.id]
      end
      
      # Create a hash for quick pair lookup
      pair_lookup = {}
      studio_pairs.each do |id1, id2|
        pair_lookup[id1] = id2
        pair_lookup[id2] = id1
      end
      
      # Track which studios have been assigned
      assigned_studios = Set.new
      
      table_number = 1
      tables = []
      
      # First pass: handle paired studios where both fit on one table
      studio_groups.each do |group|
        next if assigned_studios.include?(group[:studio_id])
        
        paired_studio_id = pair_lookup[group[:studio_id]]
        if paired_studio_id
          # Find the paired studio group
          paired_group = studio_groups.find { |g| g[:studio_id] == paired_studio_id }
          
          if paired_group && !assigned_studios.include?(paired_studio_id)
            # Check if both studios can fit on one table completely
            combined_size = group[:size] + paired_group[:size]
            
            if combined_size <= table_size
              # Both studios fit on one table
              table = { 
                number: table_number, 
                people: group[:people] + paired_group[:people],
                studios: [group[:studio_name], paired_group[:studio_name]]
              }
              tables << table
              table_number += 1
              assigned_studios.add(group[:studio_id])
              assigned_studios.add(paired_studio_id)
            end
            # Don't handle the case where they don't fit - we'll handle them separately
            # to allow for better remainder grouping
          end
        end
      end
      
      # Second pass: handle studios that fit exactly on one table
      studio_groups.each do |group|
        next if assigned_studios.include?(group[:studio_id])
        
        if group[:size] == table_size
          # Perfect fit - create a table just for this studio
          table = { 
            number: table_number, 
            people: group[:people],
            studios: [group[:studio_name]]
          }
          tables << table
          table_number += 1
          assigned_studios.add(group[:studio_id])
        end
      end
      
      # Third pass: handle remaining studios
      unassigned_groups = studio_groups.reject { |g| assigned_studios.include?(g[:studio_id]) }
      unassigned_groups.sort_by! { |g| -g[:size] }
      
      # Collect partial tables (remainders from large studios)
      partial_tables = []
      
      # Separate paired and unpaired unassigned groups
      paired_unassigned = []
      unpaired_unassigned = []
      
      unassigned_groups.each do |group|
        next if assigned_studios.include?(group[:studio_id])
        
        if pair_lookup[group[:studio_id]]
          paired_unassigned << group
        else
          unpaired_unassigned << group
        end
      end
      
      # Process unpaired studios first
      unpaired_unassigned.each do |group|
        if group[:size] <= table_size
          # Studio fits on one table - add to partial tables for optimal packing
          partial_tables << {
            studio_id: group[:studio_id],
            studio_name: group[:studio_name],
            people: group[:people],
            size: group[:size],
            parent_tables: [] # No parent tables for small studios
          }
          assigned_studios.add(group[:studio_id])
        else
          # Large studio needs multiple tables
          full_table_count = group[:size] / table_size
          remainder_size = group[:size] % table_size
          
          # Create full tables
          parent_table_numbers = []
          group[:people].first(full_table_count * table_size).each_slice(table_size) do |people_slice|
            table = { 
              number: table_number, 
              people: people_slice,
              studios: [group[:studio_name]]
            }
            tables << table
            parent_table_numbers << table_number
            table_number += 1
          end
          
          # If there's a remainder, add it to partial tables
          if remainder_size > 0
            remainder_people = group[:people].last(remainder_size)
            partial_tables << {
              studio_id: group[:studio_id],
              studio_name: group[:studio_name],
              people: remainder_people,
              size: remainder_size,
              parent_tables: parent_table_numbers # Track which tables this studio already has
            }
          end
          
          assigned_studios.add(group[:studio_id])
        end
      end
      
      # First, process all paired studios to create full tables and identify ALL remainders
      paired_unassigned.sort_by! { |g| -g[:size] }  # Process largest first
      
      paired_unassigned.each do |group|
        next if assigned_studios.include?(group[:studio_id])
        
        if group[:size] > table_size
          # Large studio needs multiple tables
          full_table_count = group[:size] / table_size
          remainder_size = group[:size] % table_size
          
          # Create full tables
          parent_table_numbers = []
          group[:people].first(full_table_count * table_size).each_slice(table_size) do |people_slice|
            table = { 
              number: table_number, 
              people: people_slice,
              studios: [group[:studio_name]]
            }
            tables << table
            parent_table_numbers << table_number
            table_number += 1
          end
          
          # If there's a remainder, add it to partial tables
          if remainder_size > 0
            remainder_people = group[:people].last(remainder_size)
            partial_tables << {
              studio_id: group[:studio_id],
              studio_name: group[:studio_name],
              people: remainder_people,
              size: remainder_size,
              parent_tables: parent_table_numbers # Track which tables this studio already has
            }
          end
          
          assigned_studios.add(group[:studio_id])
        end
      end
      
      # Now process small paired studios that can combine with remainders
      paired_unassigned.each do |group|
        next if assigned_studios.include?(group[:studio_id])
        
        if group[:size] <= table_size
          # Check if the paired studio has a remainder in partial_tables
          paired_studio_id = pair_lookup[group[:studio_id]]
          paired_remainder = partial_tables.find { |pt| pt[:studio_id] == paired_studio_id }
          
          if paired_remainder && (group[:size] + paired_remainder[:size] <= table_size)
            # Combine this small studio with the paired studio's remainder
            # Remove the remainder from partial_tables
            partial_tables.delete(paired_remainder)
            
            # Create a combined table
            table = { 
              number: table_number, 
              people: group[:people] + paired_remainder[:people],
              studios: [group[:studio_name], paired_remainder[:studio_name]]
            }
            tables << table
            table_number += 1
            assigned_studios.add(group[:studio_id])
          else
            # Can't combine, add to partial tables
            partial_tables << {
              studio_id: group[:studio_id],
              studio_name: group[:studio_name],
              people: group[:people],
              size: group[:size],
              parent_tables: [] # No parent tables for small studios
            }
            assigned_studios.add(group[:studio_id])
          end
        end
      end
      
      # Fourth pass: optimally pack partial tables
      # First, group partials by whether they have paired studios
      paired_partials = []
      unpaired_partials = []
      
      partial_tables.each do |pt|
        if pair_lookup[pt[:studio_id]]
          paired_partials << pt
        else
          unpaired_partials << pt
        end
      end
      
      # Process paired partials first
      while paired_partials.any?
        current_partial = paired_partials.shift
        
        # Check if this partial's pair is also in the partial list
        paired_studio_id = pair_lookup[current_partial[:studio_id]]
        paired_partial = paired_partials.find { |pt| pt[:studio_id] == paired_studio_id }
        
        if paired_partial && (current_partial[:size] + paired_partial[:size] <= table_size)
          # Combine the paired partials
          table = { 
            number: table_number, 
            people: current_partial[:people] + paired_partial[:people],
            studios: [current_partial[:studio_name], paired_partial[:studio_name]],
            studio_parent_tables: { 
              current_partial[:studio_name] => current_partial[:parent_tables],
              paired_partial[:studio_name] => paired_partial[:parent_tables]
            }
          }
          paired_partials.delete(paired_partial)
          
          # Fill remaining capacity with other partials if possible
          remaining_capacity = table_size - current_partial[:size] - paired_partial[:size]
          if remaining_capacity >= 2
            # Try unpaired partials first
            unpaired_partials.dup.each do |other_partial|
              if other_partial[:size] <= remaining_capacity
                table[:people].concat(other_partial[:people])
                table[:studios] << other_partial[:studio_name]
                table[:studio_parent_tables][other_partial[:studio_name]] = other_partial[:parent_tables]
                remaining_capacity -= other_partial[:size]
                unpaired_partials.delete(other_partial)
                break if remaining_capacity < 2
              end
            end
          end
          
          tables << table
          table_number += 1
        else
          # Can't combine with pair, treat as unpaired
          unpaired_partials << current_partial
        end
      end
      
      # Now handle remaining unpaired partials with standard bin packing
      unpaired_partials.sort_by! { |pt| -pt[:size] }
      
      while unpaired_partials.any?
        current_partial = unpaired_partials.shift
        table = { 
          number: table_number, 
          people: current_partial[:people],
          studios: [current_partial[:studio_name]],
          studio_parent_tables: { current_partial[:studio_name] => current_partial[:parent_tables] }
        }
        remaining_capacity = table_size - current_partial[:size]
        
        # Fill with other unpaired partials that fit
        unpaired_partials.dup.each do |other_partial|
          if other_partial[:size] <= remaining_capacity
            table[:people].concat(other_partial[:people])
            table[:studios] << other_partial[:studio_name]
            table[:studio_parent_tables][other_partial[:studio_name]] = other_partial[:parent_tables]
            remaining_capacity -= other_partial[:size]
            unpaired_partials.delete(other_partial)
            
            break if remaining_capacity < 2
          end
        end
        
        tables << table
        table_number += 1
      end
      
      # Optimization pass: combine small tables if possible
      optimized_tables = []
      tables_to_combine = []
      
      tables.each do |table_info|
        # Consider tables that are significantly under capacity for combination
        # Use 75% as threshold - tables with 25% or more empty seats can be combined
        if table_info[:people].size <= table_size * 0.75
          tables_to_combine << table_info
        else
          optimized_tables << table_info
        end
      end
      
      # Try to combine small tables
      while tables_to_combine.any?
        current_table = tables_to_combine.shift
        combined = false
        
        tables_to_combine.each_with_index do |other_table, index|
          if current_table[:people].size + other_table[:people].size <= table_size
            # Combine these tables
            current_table[:people].concat(other_table[:people])
            current_table[:studios].concat(other_table[:studios])
            current_table[:studios].uniq!
            
            # Merge parent tables if any
            if current_table[:studio_parent_tables] && other_table[:studio_parent_tables]
              current_table[:studio_parent_tables].merge!(other_table[:studio_parent_tables])
            elsif other_table[:studio_parent_tables]
              current_table[:studio_parent_tables] = other_table[:studio_parent_tables]
            end
            
            tables_to_combine.delete_at(index)
            combined = true
            break
          end
        end
        
        # If we combined with another table, try to combine more
        if combined && current_table[:people].size < table_size
          tables_to_combine.unshift(current_table)
        else
          optimized_tables << current_table
        end
      end
      
      # Renumber tables sequentially
      optimized_tables.each_with_index do |table_info, index|
        table_info[:number] = index + 1
      end
      
      # Now create actual table records and assign people
      created_tables = []
      table_metadata = {}
      
      optimized_tables.each do |table_info|
        table = create_and_assign_table(table_info[:number], table_info[:people])
        created_tables << table
        
        # Store metadata about studio parent tables for mixed tables
        if table_info[:studio_parent_tables]
          table_metadata[table.id] = table_info[:studio_parent_tables]
        end
      end
      
      # Assign rows and columns to tables, grouping by studio proximity
      assign_table_positions(created_tables, table_metadata)
      
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
    @tables = Table.includes(people: :studio).where(option_id: @option&.id).order(:number)
    @event = Event.current
    
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
      people_count = table.people.count
      
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
      unassigned_people = Person.joins(:options)
                                .where(studio_id: studio_id, type: ['Student', 'Professional', 'Guest'])
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

  def assign_table_positions(tables, table_metadata = {})
    # First, identify all studios and their tables (including mixed tables)
    studio_tables = {}
    mixed_tables = []
    
    tables.each do |table|
      studios_at_table = table.people.includes(:studio).group_by(&:studio)
      if studios_at_table.size == 1
        # Single studio table
        studio_name = studios_at_table.keys.first.name
        studio_tables[studio_name] ||= []
        studio_tables[studio_name] << table
      else
        # Mixed studio table - we'll handle these specially
        mixed_table_info = {
          table: table,
          studios: studios_at_table.map { |studio, people| { name: studio.name, count: people.size } }
        }
        
        # Add parent tables metadata if available
        if table_metadata[table.id]
          mixed_table_info[:parent_tables] = table_metadata[table.id]
        end
        
        mixed_tables << mixed_table_info
      end
    end
    
    # Clear existing positions first to avoid uniqueness conflicts
    tables.each { |table| table.update!(row: nil, col: nil) }
    
    # Use a smarter placement strategy
    positions = []
    max_cols = 8
    
    # First, place studio pairs together (both multi-table and single-table studios)
    placed_studios = Set.new
    place_studio_pairs(studio_tables, positions, max_cols, placed_studios)
    
    # Then place remaining multi-table studios
    studio_tables.select { |studio, tables| tables.size > 1 && !placed_studios.include?(studio) }.each do |studio_name, studio_table_list|
      place_studio_tables(studio_name, studio_table_list, positions, max_cols)
      placed_studios.add(studio_name)
    end
    
    # Finally place remaining single tables
    studio_tables.select { |studio, tables| tables.size == 1 && !placed_studios.include?(studio) }.each do |studio_name, studio_table_list|
      place_studio_tables(studio_name, studio_table_list, positions, max_cols)
      placed_studios.add(studio_name)
    end
    
    # Finally, place mixed tables near their constituent studios
    mixed_tables.each do |mixed_table_info|
      place_mixed_table(mixed_table_info, positions, max_cols, studio_tables)
    end
  end
  
  def place_studio_pairs(studio_tables, positions, max_cols, placed_studios)
    # Get all studio pairs from the database
    studio_pairs = StudioPair.joins(:studio1, :studio2).map do |pair|
      [pair.studio1.name, pair.studio2.name]
    end
    
    studio_pairs.each do |studio1_name, studio2_name|
      studio1_tables = studio_tables[studio1_name] || []
      studio2_tables = studio_tables[studio2_name] || []
      
      # Skip if either studio doesn't have tables or is already placed
      next if studio1_tables.empty? || studio2_tables.empty?
      next if placed_studios.include?(studio1_name) || placed_studios.include?(studio2_name)
      
      # Place both studios together as a group
      place_paired_studios(studio1_name, studio1_tables, studio2_name, studio2_tables, positions, max_cols)
      
      # Mark both as placed
      placed_studios.add(studio1_name)
      placed_studios.add(studio2_name)
    end
  end
  
  def place_paired_studios(studio1_name, studio1_tables, studio2_name, studio2_tables, positions, max_cols)
    # Calculate total tables needed for both studios
    total_tables = studio1_tables.size + studio2_tables.size
    
    # Try to place them in a compact block if possible
    if total_tables <= 4
      # Try to place them in a 2x2 or horizontal line
      block_positions = find_compact_block(positions, max_cols, total_tables)
      if block_positions
        # Place studio1 tables first
        studio1_tables.each_with_index do |table, idx|
          pos = block_positions[idx]
          positions << pos
          table.update!(row: pos[:row], col: pos[:col])
        end
        
        # Then place studio2 tables
        studio2_tables.each_with_index do |table, idx|
          pos = block_positions[studio1_tables.size + idx]
          positions << pos
          table.update!(row: pos[:row], col: pos[:col])
        end
        return
      end
    end
    
    # Fall back to placing them sequentially but together
    all_tables = studio1_tables + studio2_tables
    all_tables.each do |table|
      pos = find_next_available_position(positions, max_cols)
      positions << pos
      table.update!(row: pos[:row], col: pos[:col])
    end
  end

  def place_studio_tables(studio_name, studio_table_list, positions, max_cols)
    studio_table_count = studio_table_list.size
    
    if studio_table_count == 1
      # Single table - place anywhere available
      pos = find_next_available_position(positions, max_cols)
      positions << pos
      studio_table_list.first.update!(row: pos[:row], col: pos[:col])
    elsif studio_table_count == 2
      # Two tables - try to place them adjacently
      adjacent_positions = find_adjacent_positions(positions, max_cols, 2)
      if adjacent_positions
        adjacent_positions.each_with_index do |pos, idx|
          positions << pos
          studio_table_list[idx].update!(row: pos[:row], col: pos[:col])
        end
      else
        # Fall back to sequential placement
        studio_table_list.each do |table|
          pos = find_next_available_position(positions, max_cols)
          positions << pos
          table.update!(row: pos[:row], col: pos[:col])
        end
      end
    else
      # Multiple tables - try to place them in a compact block
      block_positions = find_compact_block(positions, max_cols, studio_table_count)
      if block_positions
        block_positions.each_with_index do |pos, idx|
          positions << pos
          studio_table_list[idx].update!(row: pos[:row], col: pos[:col])
        end
      else
        # Fall back to sequential placement
        studio_table_list.each do |table|
          pos = find_next_available_position(positions, max_cols)
          positions << pos
          table.update!(row: pos[:row], col: pos[:col])
        end
      end
    end
  end
  
  def place_mixed_table(mixed_table_info, positions, max_cols, studio_tables)
    table = mixed_table_info[:table]
    studios = mixed_table_info[:studios]
    parent_tables = mixed_table_info[:parent_tables] || {}
    
    # Find the best position near studios that have people at this table
    best_pos = nil
    min_total_penalty = Float::INFINITY
    
    # Try each available position and calculate penalty for related studios
    (1..10).each do |row|
      (1..max_cols).each do |col|
        pos = { row: row, col: col }
        next if positions.include?(pos)
        
        total_penalty = 0
        studios.each do |studio_info|
          studio_name = studio_info[:name]
          studio_people_count = studio_info[:count]
          
          # Check if this is a partial table with parent tables
          studio_parent_table_numbers = parent_tables[studio_name] || []
          
          if studio_parent_table_numbers.any?
            # This is a remainder group - prioritize being near parent tables
            parent_table_positions = Table.where(number: studio_parent_table_numbers)
                                         .where.not(row: nil, col: nil)
                                         .map { |t| { row: t.row, col: t.col } }
            
            if parent_table_positions.any?
              # Calculate distance to closest parent table
              min_parent_distance = parent_table_positions.map do |parent_pos|
                manhattan_distance(pos, parent_pos)
              end.min
              
              # Heavy penalty for being far from parent tables
              penalty = min_parent_distance * studio_people_count * 3.0
              total_penalty += penalty
            end
          else
            # Regular mixed table logic - find existing tables for this studio
            existing_studio_tables = find_all_studio_tables(studio_name, positions)
            
            if existing_studio_tables.any?
              # Calculate distance to closest table of this studio
              min_studio_distance = existing_studio_tables.map do |existing_pos|
                manhattan_distance(pos, existing_pos)
              end.min
              
              # Use a balanced penalty that considers both people count and fairness
              # Give more weight to studios with fewer total tables to avoid extreme splits
              studio_table_count = existing_studio_tables.size
              fairness_weight = studio_table_count > 1 ? 2.0 : 1.0
              
              penalty = min_studio_distance * studio_people_count * fairness_weight
              total_penalty += penalty
            end
          end
        end
        
        if total_penalty < min_total_penalty
          min_total_penalty = total_penalty
          best_pos = pos
        end
      end
    end
    
    # Use the best position found, or fall back to next available
    final_pos = best_pos || find_next_available_position(positions, max_cols)
    positions << final_pos
    table.update!(row: final_pos[:row], col: final_pos[:col])
  end
  
  def find_all_studio_tables(studio_name, positions)
    # Find all positioned tables that have people from this studio
    positioned_tables = Table.joins(:people).joins('JOIN studios ON people.studio_id = studios.id')
                            .where('studios.name = ?', studio_name)
                            .where.not(row: nil, col: nil)
                            .distinct
    
    positioned_tables.map { |table| { row: table.row, col: table.col } }
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
  
  def find_next_available_position(used_positions, max_cols)
    row = 1
    col = 1
    
    loop do
      pos = { row: row, col: col }
      return pos unless used_positions.include?(pos)
      
      col += 1
      if col > max_cols
        row += 1
        col = 1
      end
    end
  end
  
  def find_adjacent_positions(used_positions, max_cols, count)
    # Try to find horizontal adjacent positions first
    (1..10).each do |row|
      (1..max_cols-count+1).each do |start_col|
        positions = (start_col...start_col+count).map { |col| { row: row, col: col } }
        return positions if positions.none? { |pos| used_positions.include?(pos) }
      end
    end
    
    # Try vertical adjacent positions
    (1..max_cols).each do |col|
      (1..10).each do |start_row|
        positions = (start_row...start_row+count).map { |row| { row: row, col: col } }
        return positions if positions.none? { |pos| used_positions.include?(pos) }
      end
    end
    
    nil
  end
  
  def find_compact_block(used_positions, max_cols, count)
    # For 3+ tables, try to create a compact rectangular block
    # Try different block configurations (e.g., 2x2 for 4 tables, 3x1 for 3 tables)
    
    if count <= 3
      # Try horizontal line first
      return find_adjacent_positions(used_positions, max_cols, count)
    elsif count == 4
      # Try 2x2 block
      (1..10).each do |start_row|
        (1..max_cols-1).each do |start_col|
          positions = [
            { row: start_row, col: start_col },
            { row: start_row, col: start_col + 1 },
            { row: start_row + 1, col: start_col },
            { row: start_row + 1, col: start_col + 1 }
          ]
          return positions if positions.none? { |pos| used_positions.include?(pos) }
        end
      end
    end
    
    # Fall back to trying horizontal placement
    find_adjacent_positions(used_positions, max_cols, count)
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
