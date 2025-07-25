module TableAssigner
  extend ActiveSupport::Concern

  included do
    # Any class-level configuration can go here
  end

  def assign_tables(pack:)
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
      
      # Get table size using computed method
      table_size = @option&.computed_table_size || Event.current&.table_size || 10
      
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
      people_groups = if pack
        group_people_into_packed_tables(people, table_size)
      else
        group_people_into_tables(people, table_size)
      end
      
      # Phase 2: Place groups on grid (where tables go)
      created_tables = place_groups_on_grid(people_groups)
      
      # Renumber tables sequentially based on their final positions
      renumber_tables_by_position
    end
    
    redirect_to tables_path(option_id: @option&.id), notice: "Tables have been assigned successfully."
  end

  private

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
      assigned_studios.add(0)
      # Event Staff get their own tables - never mixed
      table_index = 0
      event_staff_group[:people].each_slice(table_size) do |people_slice|
        people_groups << {
          people: people_slice,
          studio_ids: [0],
          studio_names: ['Event Staff'],
          size: people_slice.size,
          coordination_group: "event_staff_#{table_index}"
        }
        table_index += 1
      end
    end
    
    # 2. Get all paired studio relationships
    studio_pairs = get_all_paired_studio_ids
    components = build_connected_components(studio_pairs)
    
    # 3. Process each connected component (group of studios linked by pairing relationships)
    components.each_with_index do |component_studio_ids, component_index|
      # Get all groups in this component that haven't been assigned yet
      component_groups = studio_groups.select do |g|
        component_studio_ids.include?(g[:studio_id]) && !assigned_studios.include?(g[:studio_id])
      end
      
      next if component_groups.empty?
      
      # Calculate total people and tables needed for this component
      total_people = component_groups.sum { |g| g[:size] }
      tables_needed = (total_people.to_f / table_size).ceil
      people_per_table = (total_people.to_f / tables_needed).ceil
      
      # Sort groups by size (largest first) for better packing
      component_groups.sort_by! { |g| -g[:size] }
      
      # Mark all studios as assigned
      component_groups.each { |g| assigned_studios.add(g[:studio_id]) }
      
      # Create coordination group identifier for this component
      coordination_group = "component_#{component_studio_ids.sort.join('_')}"
      
      # Distribute people across tables for this component
      current_table_people = []
      current_table_studios = Set.new
      current_table_studio_names = Set.new
      table_index = 0
      
      component_groups.each do |group|
        people_to_assign = group[:people].dup
        
        while people_to_assign.any?
          # Calculate remaining space in current table
          remaining_space = people_per_table - current_table_people.size
          
          # If current table is full or this is a new studio that won't fit, start a new table
          if remaining_space <= 0 || (remaining_space < people_to_assign.size && current_table_people.size > 0)
            # Save current table if it has people
            if current_table_people.any?
              people_groups << {
                people: current_table_people,
                studio_ids: current_table_studios.to_a.sort,
                studio_names: current_table_studio_names.to_a.sort,
                size: current_table_people.size,
                coordination_group: "#{coordination_group}_#{table_index}"
              }
              table_index += 1
            end
            
            # Start new table
            current_table_people = []
            current_table_studios = Set.new
            current_table_studio_names = Set.new
            remaining_space = people_per_table
          end
          
          # Add people to current table
          people_to_add = people_to_assign.shift([remaining_space, people_to_assign.size].min)
          current_table_people.concat(people_to_add)
          current_table_studios.add(group[:studio_id])
          current_table_studio_names.add(group[:studio_name])
        end
      end
      
      # Don't forget the last table
      if current_table_people.any?
        people_groups << {
          people: current_table_people,
          studio_ids: current_table_studios.to_a.sort,
          studio_names: current_table_studio_names.to_a.sort,
          size: current_table_people.size,
          coordination_group: "#{coordination_group}_#{table_index}"
        }
      end
    end
    
    # 4. Process remaining unpaired studios
    remaining_groups = studio_groups.select { |g| !assigned_studios.include?(g[:studio_id]) }
    
    remaining_groups.each do |group|
      # Each unpaired studio gets its own table(s)
      table_index = 0
      group[:people].each_slice(table_size) do |people_slice|
        people_groups << {
          people: people_slice,
          studio_ids: [group[:studio_id]],
          studio_names: [group[:studio_name]],
          size: people_slice.size,
          coordination_group: "studio_#{group[:studio_id]}_#{table_index}"
        }
        table_index += 1
      end
    end
    
    # 5. Final consolidation pass
    people_groups = consolidate_small_tables(people_groups, table_size)
    
    # 6. Ensure multi-table studios remain contiguous after consolidation
    people_groups = ensure_multi_table_studio_contiguity(people_groups)
    
    people_groups
  end
  
  def group_people_into_packed_tables(people, table_size)
    # Pack tables algorithm based on documentation:
    # - Fill tables to capacity (never exceed table_size)
    # - Split studios across adjacent tables when needed
    # - Never leave anyone sitting alone
    # - Priority is filling tables over keeping studios together
    
    people_groups = []
    
    # 1. Handle Event Staff (studio_id = 0) first - they never mix with others
    event_staff = people.select { |p| p.studio_id == 0 }
    remaining_people = people - event_staff
    
    # Event Staff tables (strict table size limit)
    table_index = 0
    event_staff.each_slice(table_size) do |people_slice|
      people_groups << create_packed_table_group(people_slice, [0], ['Event Staff'], table_index)
      table_index += 1
    end
    
    # 2. Pack tables by filling them sequentially to capacity
    studio_pairs = get_all_paired_studio_ids
    components = build_connected_components(studio_pairs)
    
    # Group remaining people by connected components
    component_people_groups = []
    assigned_people = Set.new
    
    components.each_with_index do |component_studio_ids, component_index|
      component_people = remaining_people.select { |p| component_studio_ids.include?(p.studio_id) }
      next if component_people.empty?
      
      component_people.each { |p| assigned_people.add(p) }
      
      # Create coordination group for this component
      coordination_group = "packed_component_#{component_studio_ids.sort.join('_')}"
      component_people_groups << {
        people: component_people,
        coordination_group: coordination_group,
        component_index: component_index
      }
    end
    
    # Add any remaining unpaired studios as individual components
    unpaired_people = remaining_people - assigned_people.to_a
    unpaired_by_studio = unpaired_people.group_by(&:studio_id)
    
    unpaired_by_studio.each_with_index do |(studio_id, studio_people), index|
      coordination_group = "packed_studio_#{studio_id}"
      component_people_groups << {
        people: studio_people,
        coordination_group: coordination_group,
        component_index: components.size + index
      }
    end
    
    # 3. Pack each component's people into tables
    component_people_groups.each do |component_group|
      component_people = component_group[:people]
      coordination_group = component_group[:coordination_group]
      
      # Create packed tables for this component
      current_table = []
      table_index = 0
      
      component_people.each do |person|
        current_table << person
        
        # If table is full, save it and start a new one
        if current_table.size == table_size
          studio_ids = current_table.map(&:studio_id).uniq.sort
          studio_names = current_table.map { |p| p.studio.name }.uniq.sort
          
          people_groups << {
            people: current_table,
            studio_ids: studio_ids,
            studio_names: studio_names,
            size: current_table.size,
            coordination_group: "#{coordination_group}_#{table_index}",
            split_group: coordination_group
          }
          
          current_table = []
          table_index += 1
        end
      end
      
      # Handle remaining people
      if current_table.any?
        studio_ids = current_table.map(&:studio_id).uniq.sort
        studio_names = current_table.map { |p| p.studio.name }.uniq.sort
        
        people_groups << {
          people: current_table,
          studio_ids: studio_ids,
          studio_names: studio_names,
          size: current_table.size,
          coordination_group: "#{coordination_group}_#{table_index}",
          split_group: coordination_group
        }
      end
    end
    
    # 4. Final pass to eliminate tables with only 1-2 people
    people_groups = eliminate_remaining_small_tables_with_contiguity(people_groups, table_size)
    
    people_groups
  end

  def create_packed_table_group(people, studio_ids, studio_names, table_index)
    {
      people: people,
      studio_ids: studio_ids,
      studio_names: studio_names,
      size: people.size,
      coordination_group: "event_staff_#{table_index}"
    }
  end

  def consolidate_small_tables(people_groups, table_size)
    # Consolidate small tables while preserving relationships
    # This is a more conservative consolidation that respects coordination groups
    
    consolidated = []
    groups_by_coordination = people_groups.group_by { |g| g[:coordination_group]&.split('_')&.first(2)&.join('_') }
    
    groups_by_coordination.each do |coord_prefix, groups|
      if coord_prefix.nil? || groups.size == 1
        # Single tables or no coordination group - add as-is
        consolidated.concat(groups)
      else
        # Multiple tables in same coordination group - try to consolidate small ones
        large_tables = groups.select { |g| g[:size] > table_size / 2 }
        small_tables = groups.select { |g| g[:size] <= table_size / 2 }
        
        # Add large tables as-is
        consolidated.concat(large_tables)
        
        # Try to combine small tables
        while small_tables.size >= 2
          table1 = small_tables.shift
          table2 = small_tables.find { |t| table1[:size] + t[:size] <= table_size }
          
          if table2
            small_tables.delete(table2)
            # Combine the tables
            consolidated << {
              people: table1[:people] + table2[:people],
              studio_ids: (table1[:studio_ids] + table2[:studio_ids]).uniq.sort,
              studio_names: (table1[:studio_names] + table2[:studio_names]).uniq.sort,
              size: table1[:size] + table2[:size],
              coordination_group: table1[:coordination_group]
            }
          else
            # Can't combine this table with any other
            consolidated << table1
          end
        end
        
        # Add any remaining small tables
        consolidated.concat(small_tables)
      end
    end
    
    consolidated
  end

  def eliminate_remaining_small_tables_with_contiguity(people_groups, table_size)
    # Final pass to eliminate tables with only 1-2 people
    # Preserves contiguity for split groups
    
    loop do
      small_table = people_groups.find { |g| g[:size] <= 2 }
      break unless small_table
      
      people_groups.delete(small_table)
      
      # Find best table to add these people to
      # Prefer tables from the same split_group
      same_split_tables = people_groups.select do |g|
        g[:split_group] == small_table[:split_group] && g[:size] + small_table[:size] <= table_size
      end
      
      target_table = same_split_tables.min_by { |g| g[:size] } ||
                     people_groups.select { |g| g[:size] + small_table[:size] <= table_size }.min_by { |g| g[:size] }
      
      if target_table
        # Merge into target table
        target_table[:people].concat(small_table[:people])
        target_table[:studio_ids] = (target_table[:studio_ids] + small_table[:studio_ids]).uniq.sort
        target_table[:studio_names] = (target_table[:studio_names] + small_table[:studio_names]).uniq.sort
        target_table[:size] = target_table[:people].size
      else
        # No suitable table found - redistribute people to any tables with space
        small_table[:people].each do |person|
          table_with_space = people_groups.find { |g| g[:size] < table_size }
          if table_with_space
            table_with_space[:people] << person
            unless table_with_space[:studio_ids].include?(person.studio_id)
              table_with_space[:studio_ids] << person.studio_id
              table_with_space[:studio_ids].sort!
              table_with_space[:studio_names] << person.studio.name
              table_with_space[:studio_names].sort!
            end
            table_with_space[:size] = table_with_space[:people].size
          else
            # Last resort: create a new table for this person
            people_groups << {
              people: [person],
              studio_ids: [person.studio_id],
              studio_names: [person.studio.name],
              size: 1,
              coordination_group: "emergency_#{person.studio_id}",
              split_group: small_table[:split_group]
            }
          end
        end
      end
    end
    
    people_groups
  end

  def ensure_multi_table_studio_contiguity(people_groups)
    # Ensure that tables from the same coordination group stay together
    # This is important for multi-table studios to maintain contiguity
    
    # Group tables by their coordination group prefix (without table index)
    groups_by_coord_prefix = people_groups.group_by do |g|
      coord = g[:coordination_group]
      if coord
        parts = coord.split('_')
        if parts.last =~ /^\d+$/
          parts[0...-1].join('_')
        else
          coord
        end
      else
        nil
      end
    end
    
    # Sort to ensure multi-table groups stay together
    sorted_groups = []
    
    groups_by_coord_prefix.each do |prefix, groups|
      if prefix && groups.size > 1
        # Multi-table coordination group - keep them together
        sorted_groups.concat(groups.sort_by { |g| g[:coordination_group] })
      else
        # Single table or no coordination - add as-is
        sorted_groups.concat(groups)
      end
    end
    
    sorted_groups
  end

  def get_all_paired_studio_ids
    StudioPair.all.flat_map { |sp| [[sp.studio1_id, sp.studio2_id], [sp.studio2_id, sp.studio1_id]] }
  end

  def build_connected_components(studio_pairs)
    # Build connected components from studio pairs using Union-Find
    parent = {}
    
    # Initialize each studio as its own parent
    all_studios = studio_pairs.flatten.uniq
    all_studios.each { |studio_id| parent[studio_id] = studio_id }
    
    # Find with path compression
    find = lambda do |x|
      return x if parent[x] == x
      parent[x] = find.call(parent[x])
    end
    
    # Union operation
    studio_pairs.each do |studio1_id, studio2_id|
      root1 = find.call(studio1_id)
      root2 = find.call(studio2_id)
      parent[root1] = root2 if root1 != root2
    end
    
    # Group studios by their root parent
    components = all_studios.group_by { |studio_id| find.call(studio_id) }.values
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
    
    # Step 2: Sort coordination groups by priority
    # Priority order:
    # 1. Connected components (component_*)
    # 2. Packed components (packed_component_*)
    # 3. Event staff
    # 4. Individual studios
    sorted_coord_groups = coordination_groups.sort_by do |coord_group, groups|
      if coord_group&.start_with?('component_')
        [0, -groups.sum { |g| g[:people].size }]  # Larger components first
      elsif coord_group&.start_with?('packed_component_')
        [1, -groups.sum { |g| g[:people].size }]
      elsif coord_group&.start_with?('event_staff')
        [2, 0]
      elsif coord_group&.start_with?('packed_studio_')
        [3, -groups.sum { |g| g[:people].size }]
      else
        [4, -groups.sum { |g| g[:people].size }]
      end
    end
    
    # Step 3: Place each coordination group
    sorted_coord_groups.each do |coord_group, groups|
      if split_groups[coord_group] && split_groups[coord_group].size > 1
        # This is a split group (packed tables) - place them contiguously
        place_linear_mixed_table_coordination_group(split_groups[coord_group], positions, max_cols, created_tables)
      elsif coord_group&.start_with?('component_') && groups.size > 3
        # Large connected component - use hub placement
        place_connected_component(groups, positions, max_cols, created_tables)
      elsif groups.size > 3
        # Multiple tables from same coordination group - keep them together
        place_mixed_table_coordination_group(groups, positions, max_cols, created_tables)
      elsif groups.size > 1
        # Multi-table studio - place contiguously
        place_multi_table_studio(groups, positions, max_cols, created_tables)
      else
        # Single table
        place_single_table(groups.first, positions, max_cols, created_tables)
      end
    end
    
    created_tables
  end

  def place_connected_component(groups, positions, max_cols, created_tables)
    # Place a connected component using hub-and-spoke pattern
    # Find position for hub with enough adjacent spots
    needed_adjacent_spots = groups.size - 1
    hub_pos = find_hub_position_with_adjacent_spots(positions, max_cols, needed_adjacent_spots)
    
    if hub_pos
      hub_row, hub_col = hub_pos
      
      # Place first (largest) table as hub
      hub_group = groups.first
      positions << [hub_row, hub_col]
      created_tables << create_table_at_position(hub_group, hub_row, hub_col)
      
      # Place remaining tables around the hub
      adjacent_positions = [
        [hub_row - 1, hub_col], [hub_row + 1, hub_col],  # Above and below
        [hub_row, hub_col - 1], [hub_row, hub_col + 1],  # Left and right
        [hub_row - 1, hub_col - 1], [hub_row - 1, hub_col + 1],  # Diagonal top
        [hub_row + 1, hub_col - 1], [hub_row + 1, hub_col + 1]   # Diagonal bottom
      ].select { |r, c| r >= 0 && c >= 0 && c < max_cols && !positions.include?([r, c]) }
      
      groups[1..].each_with_index do |group, idx|
        if idx < adjacent_positions.size
          row, col = adjacent_positions[idx]
          positions << [row, col]
          created_tables << create_table_at_position(group, row, col)
        else
          # Fallback if we run out of adjacent positions
          place_single_table(group, positions, max_cols, created_tables)
        end
      end
    else
      # Fallback to linear placement
      place_linear_mixed_table_coordination_group(groups, positions, max_cols, created_tables)
    end
  end

  def place_mixed_table_coordination_group(groups, positions, max_cols, created_tables)
    # For mixed table coordination groups, place tables in a cluster
    # This maintains visual grouping while being flexible about exact positioning
    
    # Sort groups by size (largest first)
    sorted_groups = groups.sort_by { |g| -g[:people].size }
    
    # Find a starting position that can accommodate the cluster
    start_row, start_col = find_next_available_position(positions, max_cols)
    
    # Place tables in a rectangular cluster
    groups_placed = 0
    current_row = start_row
    
    while groups_placed < sorted_groups.size
      # Place tables in this row
      col = start_col
      while col < max_cols && groups_placed < sorted_groups.size
        if !positions.include?([current_row, col])
          group = sorted_groups[groups_placed]
          positions << [current_row, col]
          created_tables << create_table_at_position(group, current_row, col)
          groups_placed += 1
        end
        col += 1
      end
      current_row += 1
    end
  end

  def find_hub_position_with_adjacent_spots(positions, max_cols, needed_adjacent_spots)
    # Find a position that has enough free adjacent spots for spoke tables
    (0..20).each do |row|
      (0...max_cols).each do |col|
        next if positions.include?([row, col])
        
        # Count available adjacent positions
        adjacent = [
          [row - 1, col], [row + 1, col],
          [row, col - 1], [row, col + 1],
          [row - 1, col - 1], [row - 1, col + 1],
          [row + 1, col - 1], [row + 1, col + 1]
        ]
        
        available_adjacent = adjacent.count do |r, c|
          r >= 0 && c >= 0 && c < max_cols && !positions.include?([r, c])
        end
        
        return [row, col] if available_adjacent >= needed_adjacent_spots
      end
    end
    
    nil
  end

  def find_next_available_position(positions, max_cols)
    # Find the next available position in reading order
    (0..100).each do |row|
      (0...max_cols).each do |col|
        return [row, col] unless positions.include?([row, col])
      end
    end
    [0, 0]  # Fallback
  end

  def place_linear_mixed_table_coordination_group(groups, positions, max_cols, created_tables)
    # Place groups from the same coordination group linearly (for split studios)
    # This ensures split studios remain adjacent
    
    # Find a row that can fit all tables
    start_row = 0
    start_col = 0
    found_space = false
    
    (0..100).each do |row|
      # Check if we can fit all groups in this row starting from column 0
      can_fit = true
      (0...groups.size).each do |i|
        if positions.include?([row, i]) || i >= max_cols
          can_fit = false
          break
        end
      end
      
      if can_fit
        start_row = row
        start_col = 0
        found_space = true
        break
      end
      
      # If not, try to find contiguous space in this row
      (0...(max_cols - groups.size + 1)).each do |col|
        can_fit_here = true
        (0...groups.size).each do |i|
          if positions.include?([row, col + i])
            can_fit_here = false
            break
          end
        end
        
        if can_fit_here
          start_row = row
          start_col = col
          found_space = true
          break
        end
      end
      
      break if found_space
    end
    
    # Place tables linearly
    groups.each_with_index do |group, idx|
      col = start_col + idx
      if col < max_cols
        positions << [start_row, col]
        created_tables << create_table_at_position(group, start_row, col)
      else
        # Wrap to next row if needed
        start_row += 1
        col = idx - max_cols
        positions << [start_row, col]
        created_tables << create_table_at_position(group, start_row, col)
      end
    end
  end

  def place_multi_table_studio(groups, positions, max_cols, created_tables)
    # Place tables from the same studio contiguously
    best_pos = find_best_contiguous_position(groups.size, positions, max_cols)
    
    if best_pos
      row, col = best_pos
      groups.each_with_index do |group, idx|
        positions << [row, col + idx]
        created_tables << create_table_at_position(group, row, col + idx)
      end
    else
      # Fallback: place individually
      groups.each { |group| place_single_table(group, positions, max_cols, created_tables) }
    end
  end

  def find_best_contiguous_position(size, positions, max_cols)
    # Find a contiguous horizontal space for the given number of tables
    (0..100).each do |row|
      (0...(max_cols - size + 1)).each do |col|
        # Check if all positions are free
        all_free = (0...size).all? { |i| !positions.include?([row, col + i]) }
        return [row, col] if all_free
      end
    end
    nil
  end

  def create_table_at_position(group, row, col)
    # Use a temporary negative number to avoid conflicts
    temp_number = -(Table.count + rand(1000) + 1)
    table = Table.create!(
      number: temp_number,  # Will be renumbered later
      row: row,
      col: col,
      option_id: @option&.id
    )
    
    # Assign people to this table
    if @option
      # For option tables, update person_options
      group[:people].each do |person|
        person_option = PersonOption.find_by(person_id: person.id, option_id: @option.id)
        person_option&.update!(table_id: table.id)
      end
    else
      # For main event tables, update people directly
      group[:people].each do |person|
        person.update!(table_id: table.id)
      end
    end
    
    table
  end

  def place_single_table(group, positions, max_cols, created_tables)
    # Place a single table at the next available position
    row, col = find_next_available_position(positions, max_cols)
    positions << [row, col]
    created_tables << create_table_at_position(group, row, col)
  end
end