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
      
      # TWO-PHASE ALGORITHM for both regular and pack modes
      if pack
        # Pack mode: Aggressive grouping algorithm for who sits together
        people_groups = group_people_into_packed_tables(people, table_size)
      else
        # Regular mode: Relationship-preserving grouping algorithm
        people_groups = group_people_into_tables(people, table_size)
      end
      
      # Phase 2: Use smart grid placement algorithm for both modes
      # This handles spatial arrangement, star patterns, adjacency optimization
      created_tables = place_groups_on_grid(people_groups)
      
      # Return created tables for controller to use
      created_tables
    end
  end

  private

  def renumber_tables_by_position
    # Get all tables ordered by their position (row first, then column)
    tables_by_position = Table.where(option_id: @option&.id).order(:row, :col)
    
    return if tables_by_position.empty?
    
    # Use a unique negative base to avoid conflicts with other operations
    timestamp = Time.current.to_i
    negative_base = -(timestamp * 1000)
    
    # First, temporarily set all numbers to unique negative values to avoid conflicts
    tables_by_position.each_with_index do |table, index|
      table.update!(number: negative_base - index)
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
    # Pack tables algorithm following original specification:
    # 1. Group studios with their paired studios (components)
    # 2. Process components sequentially, one by one
    # 3. Fill current table completely before starting new one
    # 4. Avoid leaving exactly 1 seat or needing exactly 1 more seat
    # 5. Never split studios ≤3 people
    # 6. Ensure no one sits alone from their studio
    
    people_groups = []
    
    # 1. Handle Event Staff (studio_id = 0) first - they never mix with others
    event_staff = people.select { |p| p.studio_id == 0 }
    remaining_people = people - event_staff
    
    # Event Staff tables (pack to capacity)
    event_staff.each_slice(table_size) do |people_slice|
      people_groups << {
        people: people_slice,
        studio_ids: [0],
        studio_names: ['Event Staff'],
        size: people_slice.size,
        coordination_group: "event_staff"
      }
    end
    
    # 2. Group studios with their paired studios (components)
    studio_pairs = get_all_paired_studio_ids
    components = build_connected_components(studio_pairs)
    
    # Build component groups with all people from paired studios
    component_groups = []
    assigned_studios = Set.new
    
    components.each_with_index do |component_studio_ids, component_index|
      component_people = remaining_people.select { |p| component_studio_ids.include?(p.studio_id) }
      next if component_people.empty?
      
      component_studio_ids.each { |id| assigned_studios.add(id) }
      component_groups << {
        people: component_people,
        size: component_people.size,
        studio_ids: component_studio_ids,
        studio_names: component_people.map { |p| p.studio.name }.uniq.sort,
        can_split: component_people.size > 3,
        component_index: component_index
      }
    end
    
    # Add unpaired studios as individual components
    remaining_people.group_by(&:studio_id).each do |studio_id, studio_people|
      next if assigned_studios.include?(studio_id)
      
      component_groups << {
        people: studio_people,
        size: studio_people.size,
        studio_ids: [studio_id],
        studio_names: [studio_people.first.studio.name],
        can_split: studio_people.size > 3,
        component_index: components.size + studio_id
      }
    end
    
    # Sort components: large first for better packing
    component_groups.sort_by! { |cg| -cg[:size] }
    
    # 3. Pack components sequentially using original algorithm
    current_table = []
    table_index = 0
    
    while component_groups.any?
      remaining_seats = table_size - current_table.size
      
      if remaining_seats == 0
        # Current table is full, save it and start new one
        if current_table.any?
          save_packed_table(people_groups, current_table, table_index)
          table_index += 1
        end
        current_table = []
        remaining_seats = table_size
      end
      
      # Find best component to add to current table
      best_component = find_best_component_for_packing(component_groups, remaining_seats, table_size)
      
      if best_component.nil?
        # No suitable component found - save current table and start fresh
        if current_table.any?
          save_packed_table(people_groups, current_table, table_index)
          table_index += 1
        end
        current_table = []
        remaining_seats = table_size
        
        # Take the largest remaining component
        best_component = component_groups.max_by { |cg| cg[:size] } if component_groups.any?
      end
      
      next unless best_component
      
      # Add people from best component
      if best_component[:combination_with]
        # This is a multi-component combination
        components_to_add = [best_component] + best_component[:combination_with]
        total_size = components_to_add.sum { |cg| cg[:size] }
        
        if total_size <= remaining_seats
          # Add all components in the combination
          components_to_add.each do |component|
            current_table.concat(component[:people])
            component_groups.delete(component)
          end
        else
          # Combination too large - revert to single component logic
          best_component.delete(:combination_with)
          if best_component[:size] <= remaining_seats
            current_table.concat(best_component[:people])
            component_groups.delete(best_component)
          end
        end
      elsif best_component[:size] <= remaining_seats
        # Add entire component
        current_table.concat(best_component[:people])
        component_groups.delete(best_component)
      else
        # Split component (only if allowed)
        if best_component[:can_split] && remaining_seats >= 2
          people_to_add = best_component[:people].shift(remaining_seats)
          current_table.concat(people_to_add)
          best_component[:size] = best_component[:people].size
          
          # Remove component if depleted
          component_groups.delete(best_component) if best_component[:size] == 0
        else
          # Can't split - save current table and start fresh
          if current_table.any?
            save_packed_table(people_groups, current_table, table_index)
            table_index += 1
          end
          current_table = []
        end
      end
    end
    
    # Save final table if any
    if current_table.any?
      save_packed_table(people_groups, current_table, table_index)
    end
    
    people_groups
  end
  
  def find_best_component_for_packing(components, remaining_seats, table_size)
    return nil if components.empty? || remaining_seats <= 0
    
    # Priority order following original specification:
    # 1. Components that fill the table exactly
    exact_fit = components.find { |cg| cg[:size] == remaining_seats }
    return exact_fit if exact_fit
    
    # 2. Look for optimal multi-component combinations first
    if remaining_seats > 2
      optimal_combo = find_optimal_component_combination(components, remaining_seats)
      return optimal_combo if optimal_combo
    end
    
    # 3. Avoid choices that would result in exactly table_size - 1 people
    # This prevents 9-person tables when table_size = 10
    forbidden_total = table_size - 1
    
    # 4. Components that leave good room for others (avoid leaving exactly 1 seat)
    good_fit = components.select { |cg| cg[:size] < remaining_seats && (remaining_seats - cg[:size]) >= 2 }
                       .reject { |cg| would_create_forbidden_table?(components, cg, remaining_seats, forbidden_total) }
                       .max_by { |cg| cg[:size] }  # Take largest that fits well
    return good_fit if good_fit
    
    # 5. Components that fit entirely but check for bad combinations
    fitting_components = components.select { |cg| cg[:size] <= remaining_seats }
                                   .reject { |cg| would_create_forbidden_table?(components, cg, remaining_seats, forbidden_total) }
    
    # If we have a component that would leave exactly 1 seat, check if combining with another would be better
    if fitting_components.any?
      best_fit = fitting_components.max_by { |cg| cg[:size] }
      
      # Check if this would leave exactly 1 seat
      if best_fit && (remaining_seats - best_fit[:size]) == 1
        # Look for a component of size 1 to fill the gap
        single_person_component = components.find { |cg| cg[:size] == 1 }
        if single_person_component.nil?
          # No single person available - this is a bad choice
          # Try to find a different component that avoids this
          alternative = fitting_components.find { |cg| cg[:size] < best_fit[:size] && (remaining_seats - cg[:size]) >= 2 }
          return alternative if alternative
        end
      end
      
      return best_fit
    end
    
    # 6. As last resort, allow any fitting component (even if it creates forbidden table)
    fallback_components = components.select { |cg| cg[:size] <= remaining_seats }
    if fallback_components.any?
      return fallback_components.max_by { |cg| cg[:size] }
    end
    
    # 7. Splittable components - avoid creating exactly 1 person remainder
    splittable = components.select do |cg|
      cg[:can_split] && cg[:size] > remaining_seats &&
      (cg[:size] - remaining_seats) >= 2  # Ensure remainder has 2+ people
    end
    
    splittable.min_by { |cg| cg[:size] - remaining_seats }  # Minimize remainder size
  end
  
  def would_create_forbidden_table?(components, chosen_component, remaining_seats, forbidden_total)
    # Check if choosing this component might lead to a table with forbidden_total people
    remaining_after_choice = remaining_seats - chosen_component[:size]
    
    # If table would be full or have 2+ seats remaining, it's safe
    return false if remaining_after_choice == 0 || remaining_after_choice >= 2
    
    # If exactly 1 seat remaining, check if there's a size-1 component to fill it
    if remaining_after_choice == 1
      available_components = components - [chosen_component]
      single_person = available_components.find { |cg| cg[:size] == 1 }
      
      # If no single person available, this choice would create forbidden table
      return single_person.nil?
    end
    
    false
  end
  
  def find_optimal_component_combination(components, remaining_seats)
    # Look for perfect combinations that fill exactly or leave optimal space
    # Priority: exact fill > leave 2+ seats > leave 0 seats (next table starts fresh)
    
    # Check 2-component combinations
    components.combination(2).each do |combo|
      total_size = combo.sum { |cg| cg[:size] }
      
      # Perfect fill
      if total_size == remaining_seats
        # Mark the first component for multi-add, referencing the actual objects
        combo[0][:combination_with] = [combo[1]]
        return combo[0]
      end
    end
    
    # Check 3-component combinations (less likely but possible)
    components.combination(3).each do |combo|
      total_size = combo.sum { |cg| cg[:size] }
      
      # Perfect fill
      if total_size == remaining_seats
        # Mark the first component for multi-add, referencing the actual objects
        combo[0][:combination_with] = combo[1..-1]
        return combo[0]
      end
    end
    
    nil
  end
  
  def find_best_component_with_lookahead(components, remaining_seats, table_size)
    return nil if components.empty? || remaining_seats <= 0
    
    # Try to find a choice that doesn't lead to exactly 1 empty seat problems
    candidate_components = []
    
    # 1. First, collect all possible choices
    exact_fit = components.find { |cg| cg[:size] == remaining_seats }
    candidate_components << { component: exact_fit, score: 100 } if exact_fit
    
    # 2. Look for optimal combinations
    if remaining_seats > 2
      optimal_combo = find_optimal_component_combination(components, remaining_seats)
      if optimal_combo && !candidate_components.any? { |c| c[:component] == optimal_combo }
        candidate_components << { component: optimal_combo, score: 95 }
      end
    end
    
    # 3. Good fits that leave 2+ seats
    good_fits = components.select { |cg| cg[:size] < remaining_seats && (remaining_seats - cg[:size]) >= 2 }
    good_fits.each do |component|
      next if candidate_components.any? { |c| c[:component] == component }
      candidate_components << { component: component, score: 80 - (remaining_seats - component[:size]) }
    end
    
    # 4. Components that fit but might leave exactly 1 seat
    risky_fits = components.select { |cg| cg[:size] <= remaining_seats }
    risky_fits.each do |component|
      next if candidate_components.any? { |c| c[:component] == component }
      
      # Check if this would leave exactly 1 seat
      if (remaining_seats - component[:size]) == 1
        # This is risky - score lower and check for alternatives
        candidate_components << { component: component, score: 20 }
      else
        candidate_components << { component: component, score: 60 }
      end
    end
    
    # 5. Evaluate each candidate with lookahead
    best_choice = nil
    best_score = -1
    
    candidate_components.each do |candidate|
      component = candidate[:component]
      base_score = candidate[:score]
      
      # Simulate what happens after this choice
      lookahead_score = evaluate_choice_with_lookahead(components, component, remaining_seats, table_size)
      total_score = base_score + lookahead_score
      
      if total_score > best_score
        best_score = total_score
        best_choice = component
      end
    end
    
    best_choice
  end
  
  def evaluate_choice_with_lookahead(components, chosen_component, remaining_seats, table_size)
    # Simulate making this choice and see what problems it might create
    score = 0
    
    # Create a copy of components without the chosen one(s)
    remaining_components = components.dup
    
    if chosen_component[:combination_with]
      # Remove all components in the combination
      components_to_remove = [chosen_component] + chosen_component[:combination_with]
      components_to_remove.each { |comp| remaining_components.delete(comp) }
      remaining_seats_after = 0  # Table would be full
    else
      remaining_components.delete(chosen_component)
      remaining_seats_after = remaining_seats - chosen_component[:size]
    end
    
    # If table would be full, check next table scenarios
    if remaining_seats_after == 0
      # Table is perfectly filled - good!
      score += 50
      
      # Check if remaining components can form good combinations
      if remaining_components.any?
        next_table_potential = check_next_table_potential(remaining_components, table_size)
        score += next_table_potential
      end
    else
      # Table partially filled - check what can fill the remainder
      fill_options = remaining_components.select { |cg| cg[:size] <= remaining_seats_after }
      
      if fill_options.empty?
        # Nothing can fill the remainder - table must be closed early
        score -= (remaining_seats_after * 5)  # Penalty for wasted seats
      elsif fill_options.any? { |cg| cg[:size] == remaining_seats_after }
        # Perfect fill available
        score += 30
      elsif fill_options.any? { |cg| (remaining_seats_after - cg[:size]) >= 2 }
        # Good fills available
        score += 10
      else
        # Only risky fills (would leave exactly 1 seat)
        single_seat_waste = fill_options.select { |cg| (remaining_seats_after - cg[:size]) == 1 }
        if single_seat_waste.any?
          score -= 30  # Heavy penalty for creating 1-seat waste
        end
      end
    end
    
    score
  end
  
  def check_next_table_potential(components, table_size)
    return 0 if components.empty?
    
    score = 0
    
    # Check if we can form good combinations for the next table
    exact_fits = components.select { |cg| cg[:size] == table_size }
    score += exact_fits.count * 20
    
    # Check for good 2-component combinations
    components.combination(2).each do |combo|
      total = combo.sum { |cg| cg[:size] }
      if total == table_size
        score += 15
      elsif total < table_size && (table_size - total) >= 2
        score += 5
      elsif total < table_size && (table_size - total) == 1
        score -= 15  # Penalty for future 1-seat waste
      end
    end
    
    # Limit the bonus to avoid over-optimizing
    [score, 30].min
  end
  
  def find_best_studio_to_pack(studios, remaining_seats)
    return nil if studios.empty? || remaining_seats <= 0
    
    # Priority order with predictive efficiency:
    # 1. Studios that fill exactly
    exact_fit = studios.find { |sg| sg[:size] == remaining_seats }
    return exact_fit if exact_fit
    
    # 2. Studios that fit entirely and leave room for others
    good_fit = studios.select { |sg| sg[:size] < remaining_seats && (remaining_seats - sg[:size]) >= 2 }
                     .min_by { |sg| sg[:size] }
    return good_fit if good_fit
    
    # 3. Studios that fit entirely
    any_fit = studios.select { |sg| sg[:size] <= remaining_seats }.max_by { |sg| sg[:size] }
    return any_fit if any_fit
    
    # 4. Splittable studios - but choose wisely to avoid waste
    splittable = studios.select { |sg| sg[:can_split] && sg[:size] > remaining_seats }
    if splittable.any?
      # Choose splittable studio that minimizes waste
      # Avoid studios that would result in tables with only 1-2 people
      best_splittable = splittable.min_by do |sg|
        remainder_after_split = sg[:size] - remaining_seats
        table_size = remaining_seats + (sg[:size] - remaining_seats) # This logic needs table_size
        
        # We need table_size context here - let's approximate as 10 for now
        # TODO: Pass table_size to this method
        estimated_table_size = 10
        
        if remainder_after_split <= 2
          # Very bad - would leave 1-2 people alone
          1000
        elsif remainder_after_split < estimated_table_size / 2
          # Moderate waste - small partial table
          remainder_after_split
        else
          # Good - reasonable partial table
          0
        end
      end
      return best_splittable
    end
    
    nil
  end
  
  def optimize_single_table_groups(people_groups, table_size)
    # Separate multi-table groups (already optimized) from single-table groups
    multi_table_groups = people_groups.select { |g| g[:multi_table_studio] }
    single_table_groups = people_groups.select { |g| !g[:multi_table_studio] }
    
    optimized_groups = multi_table_groups.dup
    
    # Group single-table groups by component for adjacency preference
    single_by_component = single_table_groups.group_by { |g| g[:component_index] }
    
    single_by_component.each do |component_index, component_groups|
      # Try to fill tables optimally within each component
      current_table = []
      
      # Sort by size (largest first) for better packing
      sorted_groups = component_groups.sort_by { |g| -g[:size] }
      
      sorted_groups.each do |group|
        if current_table.empty?
          # Start new table
          current_table = [group]
        elsif current_table.sum { |g| g[:size] } + group[:size] <= table_size
          # Add to current table
          current_table << group
        else
          # Current table is full, save it and start new one
          if current_table.size == 1
            # Single studio table
            optimized_groups << current_table.first
          else
            # Mixed table
            optimized_groups << create_mixed_table(current_table, component_index)
          end
          current_table = [group]
        end
      end
      
      # Handle final table
      if current_table.any?
        if current_table.size == 1
          optimized_groups << current_table.first
        else
          optimized_groups << create_mixed_table(current_table, component_index)
        end
      end
    end
    
    optimized_groups
  end
  
  def create_mixed_table(studio_groups, component_index)
    all_people = studio_groups.flat_map { |g| g[:people] }
    all_studio_ids = studio_groups.flat_map { |g| g[:studio_ids] }.uniq.sort
    all_studio_names = studio_groups.flat_map { |g| g[:studio_names] }.uniq.sort
    
    {
      people: all_people,
      studio_ids: all_studio_ids,
      studio_names: all_studio_names,
      size: all_people.size,
      coordination_group: "mixed_component_#{component_index}",
      table_sequence: 0,
      multi_table_studio: false,
      component_index: component_index,
      mixed_table: true
    }
  end
  
  def find_best_studio_for_packing(studio_groups, remaining_seats, current_table)
    # Priority order for selecting studios:
    # 1. Studios that fill the table exactly
    # 2. Studios that leave 2+ seats (avoiding leaving exactly 1)
    # 3. Splittable studios that need exactly 1 more seat (avoiding exactly 1 person alone)
    # 4. Paired studios if any already at the table (to maintain some relationships)
    # 5. Any studio that fits
    
    # Get studio pairs for relationship checking
    studio_pairs = get_all_paired_studio_ids
    current_studio_ids = current_table.map(&:studio_id).uniq
    
    # First pass: exact fit
    exact_fit = studio_groups.find { |s| s[:size] == remaining_seats }
    return exact_fit if exact_fit
    
    # Second pass: studios that fit and leave 2+ seats
    good_fit = studio_groups.find { |s| s[:size] < remaining_seats && (remaining_seats - s[:size]) >= 2 }
    return good_fit if good_fit
    
    # Third pass: splittable studios where we can avoid isolation
    splittable = studio_groups.find do |s|
      s[:can_split] && s[:size] > remaining_seats && 
      (s[:size] - remaining_seats) >= 2  # At least 2 people would remain
    end
    return splittable if splittable
    
    # Fourth pass: paired studios (if any already at table)
    if current_studio_ids.any?
      paired = studio_groups.find do |s|
        s[:size] <= remaining_seats &&
        current_studio_ids.any? { |id| studio_pairs.include?([id, s[:studio_id]]) }
      end
      return paired if paired
    end
    
    # Fifth pass: any studio that fits entirely
    any_fit = studio_groups.find { |s| s[:size] <= remaining_seats }
    return any_fit if any_fit
    
    # Last resort: any splittable studio
    studio_groups.find { |s| s[:can_split] }
  end
  
  def save_packed_table(people_groups, people, table_index)
    studio_ids = people.map(&:studio_id).uniq.sort
    studio_names = people.map { |p| p.studio.name }.uniq.sort
    
    # Create coordination group that follows the same pattern as regular algorithm
    # For multi-studio tables, use a generic mixed group
    # For single-studio tables, use studio_X_Y pattern to enable contiguity
    coordination_group = if studio_ids.size == 1
      # Single studio - use pattern that grid placement can group: studio_ID_sequence
      studio_id = studio_ids.first
      existing_tables_for_studio = people_groups.count { |g| g[:studio_ids] == [studio_id] }
      "studio_#{studio_id}_#{existing_tables_for_studio}"
    else
      # Multi-studio mixed table - use generic packed group
      "packed_mixed_#{table_index}"
    end
    
    people_groups << {
      people: people,
      studio_ids: studio_ids,
      studio_names: studio_names,
      size: people.size,
      coordination_group: coordination_group
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
      if coord_group
        parts = coord_group.split('_')
        if parts.length > 4 && coord_group.start_with?('component_')
          # Remove the index suffix (e.g., "component_18_35_54_0" -> "component_18_35_54")
          parts[0..-2].join('_')
        elsif parts.length >= 3 && coord_group.start_with?('studio_') && parts.last =~ /^\d+$/
          # Remove the index suffix for studio groups (e.g., "studio_66_0" -> "studio_66")
          parts[0..-2].join('_')
        else
          coord_group
        end
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
    # Calculate final table number based on grid position
    # Use row-major order: table number = (row * max_cols) + col + 1
    max_cols = 8  # Standard grid width
    final_number = (row * max_cols) + col + 1
    
    table = Table.create!(
      number: final_number,
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