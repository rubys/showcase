class TablesController < ApplicationController
  include Printable
  
  before_action :set_table, only: %i[ show edit update destroy ]

  # GET /tables or /tables.json
  def index
    @tables = Table.includes(people: :studio).all
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
  end

  def arrange
    index
  end

  def studio
    @studio = Studio.find(params[:id])
    @tables = Table.joins(people: :studio).where(studios: { id: @studio.id }).distinct.includes(people: :studio).order(:number)
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
  end

  # GET /tables/1 or /tables/1.json
  def show
  end

  # GET /tables/new
  def new
    @table = Table.new
    @table.number = (Table.maximum(:number) || 0) + 1
  end

  # GET /tables/1/edit
  def edit
  end

  # POST /tables or /tables.json
  def create
    @table = Table.new(table_params)

    respond_to do |format|
      if @table.save
        format.html { redirect_to tables_path, notice: "Table was successfully created." }
        format.json { render :show, status: :created, location: @table }
      else
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
          if @table.update(table_params)
            format.html { redirect_to tables_path, notice: "Table was successfully updated. Swapped numbers with Table #{old_number}." }
            format.json { render :show, status: :ok, location: @table }
          else
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: @table.errors, status: :unprocessable_entity }
          end
        end
      elsif @table.update(table_params)
        format.html { redirect_to tables_path, notice: "Table was successfully updated." }
        format.json { render :show, status: :ok, location: @table }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @table.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /tables/1 or /tables/1.json
  def destroy
    @table.destroy!

    respond_to do |format|
      format.html { redirect_to tables_path, status: :see_other, notice: "Table was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def update_positions
    if params[:commit] == 'Reset'
      Table.update_all(row: nil, col: nil)
      redirect_to tables_url, notice: "Table positions reset."
    else
      Table.transaction do
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
      # Remove all existing tables (dependent: :nullify will clear people's table_id)
      Table.destroy_all
      
      # Get table size from event, defaulting to 10
      event = Event.first
      table_size = (event.table_size.nil? || event.table_size == 0) ? 10 : event.table_size
      
      # Get all people excluding Event Staff (studio_id 0)
      people = Person.joins(:studio).where.not(studios: { id: 0 }).order('studios.name, people.name')
      
      # Group people by studio
      studio_groups = people.group_by(&:studio_id).map do |studio_id, studio_people|
        {
          studio_id: studio_id,
          people: studio_people,
          size: studio_people.size,
          studio_name: studio_people.first.studio.name
        }
      end
      
      # Sort all studios by size (largest first) for optimal packing
      studio_groups.sort_by! { |g| -g[:size] }
      
      # Use a hybrid approach: keep studios together when possible, but optimize packing
      table_number = 1
      tables = []
      remaining_people = []
      
      # First pass: handle studios that fit exactly
      studio_groups.each do |group|
        if group[:size] == table_size
          # Perfect fit - create a table just for this studio
          table = { number: table_number, people: group[:people] }
          tables << table
          table_number += 1
        else
          # All other studios - add to remaining people for optimal packing
          remaining_people.concat(group[:people])
        end
      end
      
      # Second pass: optimally pack remaining people from small studios
      while remaining_people.any?
        # Take up to table_size people for this table
        table_people = remaining_people.shift(table_size)
        table = { number: table_number, people: table_people }
        tables << table
        table_number += 1
      end
      
      # Now create actual table records and assign people
      created_tables = []
      tables.each do |table_info|
        table = create_and_assign_table(table_info[:number], table_info[:people])
        created_tables << table
      end
      
      # Assign rows and columns to tables, grouping by studio proximity
      assign_table_positions(created_tables)
      
      # Renumber tables sequentially based on their final positions
      renumber_tables_by_position
    end
    
    redirect_to tables_path, notice: "Tables have been assigned successfully."
  end

  def renumber
    Table.transaction do
      # Get all tables ordered by their position (row first, then column)
      # Tables without positions will be at the end
      tables_by_position = Table.order(Arel.sql('row IS NULL, row, col IS NULL, col'))
      
      # First, temporarily set all numbers to negative values to avoid conflicts
      tables_by_position.each_with_index do |table, index|
        table.update!(number: -(index + 1))
      end
      
      # Then set them to their final positive values
      tables_by_position.each_with_index do |table, index|
        table.update!(number: index + 1)
      end
    end
    
    redirect_to arrange_tables_path, notice: "Tables have been renumbered successfully."
  end

  def list
    @tables = Table.includes(people: :studio).order(:number)
    @event = Event.current
    
    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: "table-list"
      end
    end
  end

  def reset
    Table.destroy_all
    redirect_to tables_path, notice: "All tables have been deleted."
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
      table = target_person.table
    end
    
    person = Person.find(person_id)
    
    # Update the person's table assignment
    person.update!(table_id: table.id)
    
    # Refresh the data for the studio view
    @studio = person.studio
    @tables = Table.joins(people: :studio).where(studios: { id: @studio.id }).distinct.includes(people: :studio).order(:number)
    
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

  def create_and_assign_table(number, people)
    table = Table.create!(number: number)
    people.each { |person| person.update!(table_id: table.id) }
    table
  end

  def assign_table_positions(tables)
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
        mixed_tables << {
          table: table,
          studios: studios_at_table.map { |studio, people| { name: studio.name, count: people.size } }
        }
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
          
          # Find existing tables for this studio (including other mixed tables)
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
    tables_by_position = Table.order(:row, :col)
    
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

    # Only allow a list of trusted parameters through.
    def table_params
      params.expect(table: [ :number, :row, :col, :size ])
    end
end
