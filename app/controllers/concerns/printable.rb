module Printable
  def generate_agenda(expand_multi_heats: true)
    event = Event.current

    @heats = Heat.order('abs(number)').includes(
      dance: [
        :open_category, :closed_category, :solo_category, :multi_category,
        :pro_open_category, :pro_closed_category, :pro_solo_category, :pro_multi_category,
        { multi_children: :dance },
        { open_category: :extensions },
        { closed_category: :extensions },
        { solo_category: :extensions },
        { multi_category: :extensions },
        { pro_open_category: :extensions },
        { pro_closed_category: :extensions },
        { pro_solo_category: :extensions },
        { pro_multi_category: :extensions }
      ],
      entry: [:age, :level, { lead: :studio }, { follow: :studio }],
      solo: [:formations, :combo_dance, :category_override]
    )

    @heats = @heats.to_a.group_by {|heat| heat.number.abs}.
      map do |number, heats|
        [number, heats.sort_by { |heat| [heat.dance_id, heat.back || 0, heat.entry.lead.type] } ]
      end.to_h

    @categories = (Category.includes(:extensions).all + CatExtension.includes(:category).all).sort_by {|cat| cat.order}.
      map {|category| [category.name, category]}.to_h

    # copy start time/date to subsequent entries
    last_cat = nil
    first_time = nil
    @categories.each do |name, category|
      if last_cat
        category.day = last_cat.day if category.day.blank?
        first_time = nil if category.day != last_cat.day
        if category.time.blank?
          if last_cat&.day == category.day
            category.time = last_cat&.time
          else
            category.time = first_time
          end
        else
          first_time ||= category.time
        end
        category.time ||= last_cat.time
      end
      last_cat = category
    end

    start = nil
    heat_length = Event.current.heat_length
    solo_length = Event.current.solo_length || heat_length
    if not Event.current.date.blank? and heat_length and @categories.values.any? {|category| not category.time.blank?}
      start = Event.parse_date(Event.current.date, guess: false)&.begin || Time.now

      if not @categories.empty? and not @categories.values.first.day.blank?
        cat_start = Chronic.parse(@categories.values.first.day, guess: false)&.begin || start
        start = cat_start if cat_start > start and cat_start < start + 3*86_400
      end
    end

    @oneday = event.date.blank? || !!(event.date =~ /^\d{4}-\d{2}-\d{2}$/)
    @oneday ||= @categories.values.map(&:day).uniq.length <= 1

    # sort heats into categories

    @agenda = {}

    @agenda['Unscheduled'] = []
    @categories.each do |name, cat|
      @agenda[name] = []
    end
    @agenda['Uncategorized'] = []

    current = @categories.values.first

    judge_ballrooms = Judge.where.not(ballroom: 'Both').exists?

    extensions = CatExtension.includes(:category).order(:part).all.group_by(&:category)

    # State for rotating ballroom assignment (used when ballrooms >= 3)
    @ballroom_state = {
      person_ballroom: {},    # person_id → current ballroom letter
      block_number: 0,        # increments when dance order decreases
      last_dance_order: nil   # to detect block boundaries
    }

    # Clear in-memory ballroom assignments so the algorithm starts fresh.
    # Previously persisted ballrooms would otherwise be treated as manual overrides,
    # preventing rebalancing on subsequent runs (redo).
    @heats.each do |_number, heats|
      heats.each { |heat| heat.ballroom = nil }
    end

    pending_block = []
    pending_last_dance_order = nil

    @heats.each do |number, heats|
      if number == 0
        @agenda['Unscheduled'] << [number, {nil => heats}]
      else
        cat = heats.first.dance_category
        cat = cat.category if cat.is_a? CatExtension
        cat = current if cat != current && event.heat_range_cat == 1 && heats.first.category != 'Solo' && heats.first.dance.open_category_id == heats.first.dance.closed_category_id && (heats.first.dance.open_category == current || heats.first.dance.closed_category == current)
        current = cat
        ballrooms = cat&.ballrooms || event.ballrooms || 1
        max_heat_size = cat&.max_heat_size || event.max_heat_size

        if cat && cat.instance_of?(Category)
          split = cat.split.to_s.split(/[, ]+/).map(&:to_i)
          max = split.shift

          if max && @agenda[cat.name].length >= max
            (extensions[cat] || []).each do |extension|
              split.push max if split.empty?
              max = split.shift

              if @agenda[extension.name].length < max
                cat = extension
                break
              end
            end
          end

          cat = cat.name
        else
          cat = 'Uncategorized'
        end

        # Determine number of rotating rooms for block-level logic
        num_rooms = case ballrooms
                    when 3, 4 then 2
                    when 5 then 3
                    when 6 then 4
                    else nil
                    end

        if num_rooms
          # Block-level ballroom assignment for rotating ballrooms (>= 3)
          current_order = heats.first&.dance&.order

          # Detect block boundary: dance order decreased means new interleave cycle
          if pending_block.any? && pending_last_dance_order && current_order && current_order < pending_last_dance_order
            flush_block(pending_block, @ballroom_state)
            pending_block = []
          end
          pending_last_dance_order = current_order

          cap = max_heat_size ? (max_heat_size.to_f / num_rooms).ceil : nil

          # Check if this is a multi-heat with children that should be expanded
          if expand_multi_heats && heats.first.category == 'Multi' && heats.first.dance.multi_children.any?
            heats.first.dance.multi_children.sort_by { |child| child.slot || child.id }.each do |child_dance|
              heat_copies = heats.map do |heat|
                copy = Heat.new(heat.attributes.except('id'))
                copy.id = heat.id
                copy.child_dance_name = child_dance.dance.name
                copy.dance = heat.dance
                copy.entry = heat.entry
                copy.solo = heat.solo if heat.solo
                copy.readonly!
                copy
              end

              pending_block << { heats: heat_copies, num_rooms: num_rooms,
                                 cap: cap, cat: cat, number: number }
            end
          else
            pending_block << { heats: heats, num_rooms: num_rooms,
                               cap: cap, cat: cat, number: number }
          end
        else
          # Flush any pending block before switching to non-rotating
          if pending_block.any?
            flush_block(pending_block, @ballroom_state)
            pending_block = []
            pending_last_dance_order = nil
          end

          # Original assign_rooms call for ballrooms 1-2
          if expand_multi_heats && heats.first.category == 'Multi' && heats.first.dance.multi_children.any?
            heats.first.dance.multi_children.sort_by { |child| child.slot || child.id }.each do |child_dance|
              heat_copies = heats.map do |heat|
                copy = Heat.new(heat.attributes.except('id'))
                copy.id = heat.id
                copy.child_dance_name = child_dance.dance.name
                copy.dance = heat.dance
                copy.entry = heat.entry
                copy.solo = heat.solo if heat.solo
                copy.readonly!
                copy
              end

              @agenda[cat] << [number, assign_rooms(ballrooms, heat_copies,
                (judge_ballrooms && ballrooms == 2) ? -number : nil, state: @ballroom_state, max_heat_size: max_heat_size)]
            end
          else
            @agenda[cat] << [number, assign_rooms(ballrooms, heats,
              (judge_ballrooms && ballrooms == 2) ? -number : nil, state: @ballroom_state, max_heat_size: max_heat_size)]
          end
        end
      end
    end

    # Flush any remaining pending block
    flush_block(pending_block, @ballroom_state) if pending_block.any?

    @agenda.delete 'Unscheduled' if @agenda['Unscheduled'].empty?
    @agenda.delete 'Uncategorized' if @agenda['Uncategorized'].empty?

    # Re-order agenda by sequential heat number, splitting categories when they change
    # This ensures categories appear in the order heats are actually performed
    special_categories = ['Uncategorized', 'Unscheduled']

    # Flatten all heats with their category names, excluding special categories
    all_heats_with_cats = []
    @agenda.each do |cat, heats|
      next if special_categories.include?(cat)
      heats.each do |heat_num, rooms|
        all_heats_with_cats << { cat: cat, num: heat_num, rooms: rooms }
      end
    end

    # Sort by heat number
    all_heats_with_cats.sort_by! { |h| h[:num] }

    # Group consecutive heats by category
    category_sections = []
    current_section = nil
    seen_categories = Hash.new(0)

    all_heats_with_cats.each do |heat_data|
      if current_section.nil? || current_section[:cat] != heat_data[:cat]
        # Category changed, start a new section
        if current_section
          category_sections << current_section
        end

        seen_categories[heat_data[:cat]] += 1
        current_section = {
          cat: heat_data[:cat],
          occurrence: seen_categories[heat_data[:cat]],
          heats: []
        }
      end

      current_section[:heats] << [heat_data[:num], heat_data[:rooms]]
    end

    # Don't forget the last section
    category_sections << current_section if current_section

    # Build final agenda with appropriate naming
    final_agenda = {}
    category_counts = Hash.new(0)

    category_sections.each do |section|
      cat_name = section[:cat]
      category_counts[cat_name] += 1

      # Generate display name
      if category_counts[cat_name] == 1
        display_name = cat_name
      else
        # This is a continuation
        display_name = "#{cat_name} (continued)"
        counter = 2
        while final_agenda.key?(display_name)
          display_name = "#{cat_name} (continued #{counter})"
          counter += 1
        end
      end

      final_agenda[display_name] = section[:heats]
    end

    # Add special categories at the end, sorted by heat number
    special_categories.each do |cat|
      if @agenda.key?(cat)
        final_agenda[cat] = @agenda[cat].sort_by { |heat_num, _| heat_num }
      end
    end

    # Preserve categories with duration (breaks, warm-ups) even if they have no heats
    # Insert them into final_agenda at the appropriate position based on category order
    @categories.values.sort_by(&:order).reverse.each do |cat|
      next unless cat.duration && @agenda.key?(cat.name) && !final_agenda.key?(cat.name)

      # Find the position where this category should be inserted
      # It should appear just before the next category in order
      next_cat = @categories.values.sort_by(&:order).find { |c| c.order > cat.order }

      if next_cat && final_agenda.key?(next_cat.name)
        # Insert before the next category
        new_agenda = {}
        final_agenda.each do |key, value|
          if key == next_cat.name || key.start_with?("#{next_cat.name} (continued")
            new_agenda[cat.name] = []
            break
          end
          new_agenda[key] = value
        end
        # Add remaining entries
        final_agenda.each { |key, value| new_agenda[key] = value unless new_agenda.key?(key) }
        final_agenda = new_agenda
      else
        # Append at the end (before special categories)
        final_agenda[cat.name] = []
      end
    end

    @agenda = final_agenda

    # assign start and finish times

    @include_times = event.include_times if @include_times.nil?
    if start and @include_times
      @start = []
      @finish = []

      @cat_start = {}
      @cat_finish = {}

      @agenda.each do |name, heats|
        cat = @categories[name]

        if cat and not cat.day.blank?
          yesterday = Chronic.parse('yesterday', now: start)
          day = Chronic.parse(cat.day, now: yesterday, guess: false)&.begin || start
          start = day if day > start and day < start + 3*86_400
        end

        if cat and not cat.time.blank?
          if cat.time =~ /^\d{1,2}:\d{2}$/
            cattime = Time.parse(cat.time)
            time = start.change(hour: cattime.hour, min: cattime.min)
          else
            time = Chronic.parse(cat.time, now: start) || start
          end
          start = time if time and time > start
        end

        @cat_start[name] = start

        last_number_processed = nil
        heats.each do |number, ballrooms|
          heats = ballrooms.values.flatten

          @start[number] ||= start

          # Only add time for the first occurrence of each heat number
          # (to avoid double-counting when multi-heats are expanded)
          if last_number_processed != number
            if heats.first.dance.heat_length
              start += heat_length * heats.first.dance.heat_length
              # Only add semi-finals time if there are more than 8 couples
              if heats.first.dance.semi_finals && heats.length > 8
                start += heat_length * heats.first.dance.heat_length
              end
            elsif heats.any? {|heat| heat.number > 0}
              if heats.length == 1 and heats.first.category == 'Solo'
                start += solo_length
              else
                start += heat_length
              end
            end
            last_number_processed = number
          end

          @finish[number] ||= start
        end

        # Handle categories with a minimum duration (e.g., breaks, warm-ups)
        # Set finish time to either current time or start + duration, whichever is later
        if cat&.duration
          start = @cat_finish[name] = [start, @cat_start[name] + cat.duration*60].max
        else
          @cat_finish[name] = start
        end
      end
    end

    if event.heat_range_level == 0
      heat_level = Heat.joins(:entry).pluck(:number, :level_id).to_h
      agenda = @agenda
      @agenda = {}

      Level.order(:id).each do |level|
        heats_for_level = heat_level.select {|number, level_id| level_id == level.id}.keys

        agenda.each do |name, heats|
          category = heats.select {|number, rooms| heats_for_level.include? rooms.values.flatten.first.number}
          @agenda["#{level.name} #{name}"] = category unless category.empty?
        end
      end
    end
  end

  def assign_rooms(ballrooms, heats, number, preserve_order: false, state: nil, max_heat_size: nil)
    result = if heats.all? {|heat| heat.category == 'Solo'}
      {nil => heats}
    elsif heats.all? {|heat| !heat.ballroom.nil?}
      heats.group_by(&:ballroom)
    elsif ballrooms == 1
      {nil => heats}
    elsif ballrooms == 2
      b = heats.select {|heat| heat.entry.lead.type == "Student"}
      {'A': heats - b, 'B': b}
    else
      # Rotating assignment for ballrooms >= 3 (setting values 3, 4, 5, 6)
      num_rooms = case ballrooms
                  when 3, 4 then 2
                  when 5 then 3
                  when 6 then 4
                  else 2
                  end

      # Calculate per-ballroom cap from max_heat_size
      cap = max_heat_size ? (max_heat_size.to_f / num_rooms).ceil : nil

      assign_rooms_rotating(num_rooms, heats, state, cap: cap)
    end

    # Sort by ballroom letter (nil sorts first)
    result.sort_by { |k, _| k.to_s }.to_h
  end

  def assign_rooms_rotating(num_rooms, heats, state, cap: nil)
    # Create default state if not provided (for callers that don't track state)
    state ||= {
      person_ballroom: {},
      block_number: 0,
      last_dance_order: nil
    }

    # Detect new block: when dance order decreases, we've started a new interleave cycle
    current_order = heats.first&.dance&.order
    if state[:last_dance_order] && current_order && current_order < state[:last_dance_order]
      state[:block_number] += 1
    end
    state[:last_dance_order] = current_order

    result = Hash.new { |h, k| h[k] = [] }

    # Track dance_id → ballroom so packed multi-dance splits stay together.
    # Only applies when multiple dances share the same heat number.
    multi_dance = heats.map(&:dance_id).uniq.size > 1
    dance_room = {}

    heats.each do |heat|
      # Check if this is a manual override before determining ballroom
      manual_override = heat.ballroom.present?

      assigned = if manual_override
        heat.ballroom
      elsif multi_dance && dance_room[heat.dance_id]
        # Same dance_id already assigned — keep together (bypasses cap)
        dance_room[heat.dance_id]
      else
        determine_ballroom(heat, num_rooms, state, result, cap: cap)
      end

      result[assigned] << heat

      # Only update state for automatic assignments - manual overrides should not
      # affect the deterministic placement of other participants
      unless manual_override
        state[:person_ballroom][heat.entry.lead_id] = assigned if heat.entry.lead_id != 0
        state[:person_ballroom][heat.entry.follow_id] = assigned if heat.entry.follow_id != 0
        dance_room[heat.dance_id] = assigned if multi_dance
      end
    end

    result
  end

  # Flush a pending block of heat-numbers, assigning ballrooms at the block level.
  # Each person gets a stable "home ballroom" for the entire block, then per-heat-number
  # assignments respect those homes for better balance and reduced bouncing.
  def flush_block(pending_block, state)
    return if pending_block.empty?

    num_rooms = pending_block.first[:num_rooms]

    # Collect all people across all heat-numbers in the block, counting how many
    # heat-numbers each person appears in (their "weight").
    # Also build per-heat-number people sets to balance per-heat counts,
    # and entry pairs to keep partners together.
    person_weights = Hash.new(0)
    person_studios = {}
    heat_number_people = []  # array of Sets, one per item in pending_block
    pair_counts = Hash.new(0) # [lead_id, follow_id] → count of heats together

    pending_block.each do |item|
      people_in_heat_number = Set.new
      item[:heats].each do |heat|
        lead_id = heat.entry.lead_id
        follow_id = heat.entry.follow_id

        if lead_id != 0 && !people_in_heat_number.include?(lead_id)
          people_in_heat_number << lead_id
          person_studios[lead_id] ||= heat.entry.lead.studio&.ballroom
        end

        if follow_id != 0 && !people_in_heat_number.include?(follow_id)
          people_in_heat_number << follow_id
          person_studios[follow_id] ||= heat.entry.follow.studio&.ballroom
        end

        # Track entry pairs (ordered by ID for consistency)
        if lead_id != 0 && follow_id != 0
          pair = lead_id < follow_id ? [lead_id, follow_id] : [follow_id, lead_id]
          pair_counts[pair] += 1
        end
      end

      heat_number_people << people_in_heat_number
      people_in_heat_number.each { |pid| person_weights[pid] += 1 }
    end

    # Assign home ballrooms for everyone in this block
    homes = assign_home_ballrooms(person_weights, person_studios, num_rooms, state, heat_number_people, pair_counts)

    # For each heat-number in the block, assign ballrooms respecting homes
    pending_block.each do |item|
      rooms = assign_heat_with_homes(item[:heats], homes, num_rooms, state, cap: item[:cap])
      @agenda[item[:cat]] << [item[:number], rooms]
    end

    # Update state with final home assignments for carry-forward to next block
    homes.each do |person_id, room|
      state[:person_ballroom][person_id] = room
    end

    state[:block_number] += 1
  end

  # Assign each person a stable "home ballroom" for a block using three-pass weighted greedy.
  #
  # Pass 1 — Studio preferences: People whose studio has a ballroom preference are locked.
  # Pass 2 — Carry-forward: People who had a home in the prior block keep it, unless
  #           doing so would exceed a tolerance threshold.
  # Pass 3 — New assignments: Remaining people go to the room with the lowest
  #           per-heat-number imbalance score.
  #
  # Weight = number of heat-numbers a person appears in within this block.
  # heat_number_people = array of Sets, one per heat-number, listing person_ids in that heat-number.
  def assign_home_ballrooms(person_weights, person_studios, num_rooms, state, heat_number_people = [], pair_counts = {})
    homes = {}
    room_weights = Hash.new(0)
    total_weight = person_weights.values.sum
    tolerance = total_weight.to_f / num_rooms * 1.3

    room_letters = num_rooms.times.map { |i| ('A'.ord + i).chr }

    # Per-heat-number room counts: how many people in each heat-number are assigned to each room
    # This is used to balance per-heat-number counts, not just total weight.
    heat_room_counts = heat_number_people.map { Hash.new(0) }

    # Helper to assign a person to a room and update all tracking
    assign_person = lambda do |person_id, room|
      homes[person_id] = room
      room_weights[room] += person_weights[person_id]
      heat_number_people.each_with_index do |people_set, idx|
        heat_room_counts[idx][room] += 1 if people_set.include?(person_id)
      end
    end

    # Helper: compute the maximum per-heat-number imbalance if person_id were assigned to room.
    # Returns the worst (max over all heat-numbers) difference between the largest and smallest
    # room count for heat-numbers this person participates in.
    heat_imbalance_for = lambda do |person_id, room|
      max_imbalance = 0
      heat_number_people.each_with_index do |people_set, idx|
        next unless people_set.include?(person_id)
        counts = heat_room_counts[idx].dup
        counts[room] += 1
        room_counts = room_letters.map { |r| counts[r] }
        imbalance = room_counts.max - room_counts.min
        max_imbalance = imbalance if imbalance > max_imbalance
      end
      max_imbalance
    end

    # Pass 1: Studio preferences
    person_weights.each do |person_id, weight|
      studio_pref = person_studios[person_id]
      if studio_pref.present? && room_letters.include?(studio_pref)
        assign_person.call(person_id, studio_pref)
      end
    end

    # Pass 2: Carry-forward from previous block (heaviest-weight people first)
    carry_forward = person_weights.keys
      .reject { |pid| homes.key?(pid) }
      .select { |pid| state[:person_ballroom][pid] }
      .sort_by { |pid| -person_weights[pid] }

    carry_forward.each do |person_id|
      prior_room = state[:person_ballroom][person_id]
      weight = person_weights[person_id]

      if room_letters.include?(prior_room) && (room_weights[prior_room] + weight) <= tolerance
        assign_person.call(person_id, prior_room)
      end
      # If would exceed tolerance, leave unassigned for Pass 3
    end

    # Pass 3: New assignments — assign to room that minimizes per-heat-number imbalance
    unassigned = person_weights.keys
      .reject { |pid| homes.key?(pid) }
      .sort_by { |pid| [-person_weights[pid], pid] }

    unassigned.each do |person_id|
      # Score each room by per-heat-number imbalance, then by total weight as tiebreaker
      best_room = room_letters.min_by do |room|
        [heat_imbalance_for.call(person_id, room), room_weights[room]]
      end

      # If multiple rooms tie on both metrics, use deterministic tiebreaker
      best_score = [heat_imbalance_for.call(person_id, best_room), room_weights[best_room]]
      candidates = room_letters.select do |room|
        [heat_imbalance_for.call(person_id, room), room_weights[room]] == best_score
      end

      if candidates.length == 1
        room = candidates.first
      else
        index = (person_id + state[:block_number]) % candidates.length
        room = candidates.sort[index]
      end

      assign_person.call(person_id, room)
    end

    # Pass 4: Pair reconciliation — reduce bouncing by aligning conflicting partners.
    # For each pair where lead and follow got different homes, try moving the lighter
    # partner to match the heavier one, if it doesn't worsen per-heat-number imbalance.
    if pair_counts.any?
      # Helper to move a person from their current room to a new room
      move_person = lambda do |person_id, old_room, new_room|
        homes[person_id] = new_room
        weight = person_weights[person_id]
        room_weights[old_room] -= weight
        room_weights[new_room] += weight
        heat_number_people.each_with_index do |people_set, idx|
          if people_set.include?(person_id)
            heat_room_counts[idx][old_room] -= 1
            heat_room_counts[idx][new_room] += 1
          end
        end
      end

      # Helper: current max imbalance across all heat-numbers a person participates in
      current_imbalance_for = lambda do |person_id|
        max_imbalance = 0
        heat_number_people.each_with_index do |people_set, idx|
          next unless people_set.include?(person_id)
          room_counts = room_letters.map { |r| heat_room_counts[idx][r] }
          imbalance = room_counts.max - room_counts.min
          max_imbalance = imbalance if imbalance > max_imbalance
        end
        max_imbalance
      end

      # Sort conflicting pairs by heat count together (most heats first = most bounce reduction)
      conflicting_pairs = pair_counts.select { |pair, _| homes[pair[0]] != homes[pair[1]] }
        .sort_by { |_, count| -count }

      conflicting_pairs.each do |pair, count|
        pid_a, pid_b = pair
        next unless homes[pid_a] && homes[pid_b]
        next if homes[pid_a] == homes[pid_b]  # may have been resolved by earlier move

        # Decide who moves: lighter weight moves to heavier's room
        if person_weights[pid_a] >= person_weights[pid_b]
          mover, stayer = pid_b, pid_a
        else
          mover, stayer = pid_a, pid_b
        end

        old_room = homes[mover]
        new_room = homes[stayer]

        # Check if moving would worsen any per-heat-number imbalance beyond 2
        would_worsen = false
        heat_number_people.each_with_index do |people_set, idx|
          next unless people_set.include?(mover)
          new_count = heat_room_counts[idx][new_room] + 1
          old_count = heat_room_counts[idx][old_room] - 1
          all_counts = room_letters.map do |r|
            if r == new_room then heat_room_counts[idx][r] + 1
            elsif r == old_room then heat_room_counts[idx][r] - 1
            else heat_room_counts[idx][r]
            end
          end
          if all_counts.max - all_counts.min > 2
            would_worsen = true
            break
          end
        end

        move_person.call(mover, old_room, new_room) unless would_worsen
      end
    end

    homes
  end

  # Assign ballrooms for heats within a single heat-number, respecting home assignments.
  # Priority: heat-level override > studio preference > home ballroom > fallback.
  # Enforces a per-heat-number balance cap so no room gets too many heats.
  def assign_heat_with_homes(heats, homes, num_rooms, state, cap: nil)
    result = Hash.new { |h, k| h[k] = [] }

    # Per-heat-number balance cap
    non_override_count = heats.count { |h| h.ballroom.blank? }
    balance_cap = (non_override_count.to_f / num_rooms).ceil
    # Use the stricter of event cap and balance cap
    effective_cap = if cap && balance_cap
                     [cap, balance_cap].min
                   else
                     cap || balance_cap
                   end

    # Track dance_id → ballroom so packed multi-dance splits stay together.
    # Only applies when multiple dances share the same heat number.
    multi_dance = heats.map(&:dance_id).uniq.size > 1
    dance_room = {}

    heats.each do |heat|
      assigned = if heat.ballroom.present?
        # Heat-level override — use as-is (bypasses cap)
        heat.ballroom
      elsif multi_dance && dance_room[heat.dance_id]
        # Same dance_id already assigned — keep together (bypasses cap)
        dance_room[heat.dance_id]
      else
        # Try studio preference
        studio_pref = heat.subject&.studio&.ballroom
        if studio_pref.present? && ballroom_under_cap?(studio_pref, result, effective_cap)
          studio_pref
        else
          # Use home ballrooms for lead and follow
          lead_home = homes[heat.entry.lead_id]
          follow_home = homes[heat.entry.follow_id]

          preferred = if lead_home.nil? && follow_home.nil?
            nil
          elsif lead_home && follow_home.nil?
            lead_home
          elsif follow_home && lead_home.nil?
            follow_home
          elsif lead_home == follow_home
            lead_home
          else
            resolve_ballroom_conflict(heat, lead_home, follow_home)
          end

          if preferred && ballroom_under_cap?(preferred, result, effective_cap)
            preferred
          else
            least_loaded_ballroom(num_rooms, state[:block_number], heat.entry.id, result, cap: effective_cap)
          end
        end
      end

      result[assigned] << heat
      dance_room[heat.dance_id] = assigned if multi_dance && !heat.ballroom.present?
    end

    # Sort by ballroom letter (nil sorts first)
    result.sort_by { |k, _| k.to_s }.to_h
  end

  def determine_ballroom(heat, num_rooms, state, current_heat_assignments = {}, cap: nil)
    # Check heat-level override first (bypasses cap - trust the event owner)
    return heat.ballroom unless heat.ballroom.blank?

    # Check studio preference (subject to cap)
    studio_pref = heat.subject&.studio&.ballroom
    if studio_pref.present? && ballroom_under_cap?(studio_pref, current_heat_assignments, cap)
      return studio_pref
    end

    # Look up existing assignments for lead and follow
    lead_room = state[:person_ballroom][heat.entry.lead_id]
    follow_room = state[:person_ballroom][heat.entry.follow_id]

    if lead_room.nil? && follow_room.nil?
      # New participants - assign to least-loaded ballroom under cap
      least_loaded_ballroom(num_rooms, state[:block_number], heat.entry.id, current_heat_assignments, cap: cap)
    elsif lead_room && follow_room.nil?
      # Follow lead's room if under cap, otherwise find alternative
      if ballroom_under_cap?(lead_room, current_heat_assignments, cap)
        lead_room
      else
        least_loaded_ballroom(num_rooms, state[:block_number], heat.entry.id, current_heat_assignments, cap: cap)
      end
    elsif follow_room && lead_room.nil?
      # Follow follow's room if under cap, otherwise find alternative
      if ballroom_under_cap?(follow_room, current_heat_assignments, cap)
        follow_room
      else
        least_loaded_ballroom(num_rooms, state[:block_number], heat.entry.id, current_heat_assignments, cap: cap)
      end
    elsif lead_room == follow_room
      # Both in same room - use it if under cap
      if ballroom_under_cap?(lead_room, current_heat_assignments, cap)
        lead_room
      else
        least_loaded_ballroom(num_rooms, state[:block_number], heat.entry.id, current_heat_assignments, cap: cap)
      end
    else
      # Conflict - resolve then check cap
      preferred = resolve_ballroom_conflict(heat, lead_room, follow_room)
      if ballroom_under_cap?(preferred, current_heat_assignments, cap)
        preferred
      else
        # Try the other room
        other = (preferred == lead_room) ? follow_room : lead_room
        if ballroom_under_cap?(other, current_heat_assignments, cap)
          other
        else
          least_loaded_ballroom(num_rooms, state[:block_number], heat.entry.id, current_heat_assignments, cap: cap)
        end
      end
    end
  end

  def ballroom_under_cap?(room, current_assignments, cap)
    return true if cap.nil?  # No cap means always under
    (current_assignments[room]&.length || 0) < cap
  end

  def least_loaded_ballroom(num_rooms, block_number, entry_id, current_assignments, cap: nil)
    # Get counts for each ballroom
    counts = {}
    num_rooms.times do |i|
      room = ('A'.ord + i).chr
      counts[room] = current_assignments[room]&.length || 0
    end

    # If cap is set, filter to only ballrooms under cap
    if cap
      under_cap = counts.select { |_, count| count < cap }
      counts = under_cap if under_cap.any?
    end

    min_count = counts.values.min

    # Find all ballrooms with the minimum count
    candidates = counts.select { |_, count| count == min_count }.keys

    if candidates.length == 1
      candidates.first
    else
      # Tiebreaker: use original rotation formula among candidates
      base = entry_id % candidates.length
      index = (base + block_number) % candidates.length
      candidates.sort[index]
    end
  end

  # Persist computed ballroom assignments to database after scheduling
  # This ensures consistent ballroom display across all views
  def persist_ballroom_assignments
    return unless @agenda

    updates_by_ballroom = Hash.new { |h, k| h[k] = [] }

    @agenda.each do |_category, heats_by_number|
      heats_by_number.each do |_number, rooms|
        next unless rooms.is_a?(Hash)

        rooms.each do |ballroom, heats|
          next if ballroom.nil?  # Skip unassigned (solos, single ballroom)

          heats.each do |heat|
            next if heat.readonly?  # Skip copied heats used for multi-dance expansion

            # Only update heats that don't have a manual override
            # (manual overrides already have ballroom set in the DB)
            if heat.ballroom.blank?
              updates_by_ballroom[ballroom.to_s] << heat.id
            end
          end
        end
      end
    end

    # Batch update heats by ballroom for efficiency
    updates_by_ballroom.each do |ballroom, heat_ids|
      Heat.where(id: heat_ids).update_all(ballroom: ballroom) if heat_ids.any?
    end
  end

  def resolve_ballroom_conflict(heat, lead_room, follow_room)
    lead_is_student = heat.entry.lead.type == 'Student'
    follow_is_student = heat.entry.follow.type == 'Student'

    # Prefer keeping student stationary over professional
    return lead_room if lead_is_student && !follow_is_student
    return follow_room if follow_is_student && !lead_is_student

    # Both same type - lower person ID stays in their ballroom
    heat.entry.lead_id < heat.entry.follow_id ? lead_room : follow_room
  end

  def find_couples
    people = Person.joins(:package).where(package: {couples: true})
    couples = Entry.where(lead: people, follow: people).pluck(:follow_id, :lead_id).to_h
    @paired = (couples.keys + couples.values).group_by(&:itself).
      select {|id, list| list.length == 1}.keys
    @couples = couples.select {|follow, lead| @paired.include?(lead) && @paired.include?(follow)}
  end

  def generate_invoice(studios = nil, student=false, instructor=nil)
    find_couples

    studios ||= Studio.all.by_name.preload(:studio1_pairs, :studio2_pairs, people: {options: :option, package: {package_includes: :option}})

    @event = Event.current
    @track_ages = @event.track_ages
    @column_order = @event.column_order

    @invoices = {}

    overrides = {}

    Category.where.not(cost_override: nil).each do |category|
      overrides[category.name] = category.cost_override
    end

    Dance.where.not(cost_override: nil).each do |dance|
      overrides[dance.name] = dance.cost_override
    end

    studios.each do |studio|
      other_charges = {}

      @cost = {
        'Closed' => studio.heat_cost || @event.heat_cost || 0,
        'Open' => studio.heat_cost || @event.heat_cost || 0,
        'Solo' => studio.solo_cost || @event.solo_cost || 0,
        'Multi' => studio.multi_cost || @event.multi_cost || 0
      }

      if @student
        @cost = {
          'Closed' => studio.student_heat_cost || @cost['Closed'],
          'Open' => studio.student_heat_cost || @cost['Open'],
          'Solo' => studio.student_solo_cost || @cost['Solo'],
          'Multi' => studio.student_multi_cost || @cost['Multi']
        }
      end

      @cost.merge! overrides

      @pcost = @cost.merge(
        'Closed' => @event.pro_heat_cost || 0.0,
        'Open' => @event.pro_heat_cost || 0.0,
        'Solo' => @event.pro_solo_cost || 0.0,
        'Multi' => @event.pro_multi_cost || 0.0
      )

      preload = {
        lead: [:studio, {options: :option, package: {package_includes: :option}}],
        follow: [:studio, {options: :option, package: {package_includes: :option}}],
        heats: {dance: [:open_category, :closed_category, :solo_category]}
      }

      # Get entries where the studio might be involved (via direct assignment, lead, follow, or instructor)
      # Using a single query with OR conditions to filter at the database level
      entries = Entry.left_joins(:lead, :follow, :instructor)
        .where(
          "entries.studio_id = :studio_id OR " +
          "people.studio_id = :studio_id OR " +
          "follows_entries.studio_id = :studio_id OR " +
          "instructors_entries.studio_id = :studio_id",
          studio_id: studio.id
        )
        .preload(preload)
        .distinct
        .to_a
        .select { |entry| entry.invoice_studios.keys.include?(studio) }

      # add professional entries - this one is used to detect pros who are not in the studio
      pentries = (Entry.joins(:follow).preload(preload).where(people: {type: 'Professional', studio: studio}) +
        Entry.joins(:lead).preload(preload).where(people: {type: 'Professional', studio: studio})).uniq

      # add professional entries - this one is contains all pro entries
      pro_entries = pentries.select {|entry| entry.lead.type == 'Professional' && entry.follow.type == 'Professional'}

      pentries -= pro_entries

      if instructor
        people = [instructor] + instructor.responsible_for
        entries.select! {|entry| [entry.lead, entry.follow, entry.instructor].intersect?(people)}
        pentries.select! {|entry| [entry.lead, entry.follow, entry.instructor].intersect?(people)}
        pro_entries.select! {|entry| [entry.lead, entry.follow, entry.instructor].intersect?(people)}
        # For instructor invoices (not student invoices), only include pro-pro entries
        unless student
          entries.reject! {|entry| entry.lead.type == 'Student' || entry.follow.type == 'Student'}
          pentries.reject! {|entry| entry.lead.type == 'Student' || entry.follow.type == 'Student'}
        end
      else
        studios = Set.new(studio.pairs + [studio])
        entries.select! {|entry| studios.include?(entry.follow.studio) && studios.include?(entry.lead.studio)}
        pentries.select! {|entry| !studios.include?(entry.follow.studio) || !studios.include?(entry.lead.studio)}
      end

      entries += pentries + pro_entries

      # Pre-load age cost overrides once for efficiency
      age_cost = @track_ages ? AgeCost.all.index_by(&:age_id) : {}

      people = entries.map {|entry| [entry.lead, entry.follow]}.flatten

      if instructor
        people << instructor
        people += instructor.responsible_for
      elsif student && instructor
        people = [instructor]

        entries.reject! {|entry| entry.lead != instructor && entry.follow != instructor}
        pentries.reject! {|entry| entry.lead != instructor && entry.follow != instructor}
      else
        people = (people + studio.people.preload({options: :option, package: {package_includes: :option}})).uniq

        independents = people.select {|person| person.independent}
        unless independents.empty?
          entries.reject! {|entry| independents.include?(entry.lead) || independents.include?(entry.follow)}
          pentries.reject! {|entry| independents.include?(entry.lead) || independents.include?(entry.follow)}
        end
      end

      @dances = people.sort_by(&:name).map do |person|
        package = person.package&.price || 0
        package = @registration if @registration && person.type == "Student"
        package/=2 if @paired.include? person.id
        purchases = package + person.selected_options.map(&:price).sum || 0
        purchases = 0 unless person.studio == studio
        [person, {dances: 0, cost: 0, purchases: purchases}]
      end.to_h

      entries.uniq.each do |entry|
        if entry.lead.type == 'Student' and entry.follow.type == 'Student'
          split = 2.0
        else
          split = 1
        end

        # For student invoices, don't split billing between paired studios
        if split != 1.0 && student
          # Check if the professional's studio is paired with the student's studio
          other_studio = nil
          if entry.lead.type == "Professional" && entry.lead.studio != studio
            other_studio = entry.lead.studio
          elsif entry.follow.type == "Professional" && entry.follow.studio != studio
            other_studio = entry.follow.studio
          end

          if other_studio && studio && studio.pairs.include?(other_studio)
            split = 1.0
          end
        end

        entry.heats.each do |heat|
          next if heat.number < 0
          category = heat.category

          dance_category = heat.dance_category
          dance_category = dance_category.category if dance_category.is_a? CatExtension
          category = dance_category.name if dance_category&.cost_override
          category = heat.dance.name if heat.dance.cost_override

          # Apply age cost overrides (same logic as in _entry.html.erb)
          base_cost = @cost[category] || 0
          # Apply the same age cost override logic as the entry view
          if @track_ages && age_cost[entry.age_id]&.heat_cost
            base_cost = age_cost[entry.age_id].heat_cost
          end

          if dance_category&.studio_cost_override
            split = 1 if dance_category.cost_override == 0 && entry.lead.studio == entry.follow.studio

            other_charges[dance_category.name] ||= {entries: 0, count: 0, cost: 0}
            other_charges[dance_category.name] = {
              entries: other_charges[dance_category.name][:entries] + 1,
              count: other_charges[dance_category.name][:count] + 1.0 / split,
              cost: other_charges[dance_category.name][:cost] + dance_category.studio_cost_override / split
            }

            next if dance_category.cost_override == 0
          end

          if entry.lead.type == 'Student' and @dances[entry.lead]
            @dances[entry.lead][:dances] += 1.0 / split
            @dances[entry.lead][:cost] += base_cost / split

            if @student
              @dances[entry.lead][category] = (@dances[entry.lead][category] || 0) + 1.0/split
            end
          end

          if entry.follow.type == 'Student' and @dances[entry.follow]
            @dances[entry.follow][:dances] += 1.0 / split
            @dances[entry.follow][:cost] += base_cost / split

            if @student
              @dances[entry.follow][category] = (@dances[entry.follow][category] || 0) + 1.0/split
            end
          end
        end
      end

      pro_entries.uniq.each do |entry|
        entry.heats.each do |heat|
          next if heat.number < 0
          category = heat.category

          dance_category = heat.dance_category
          dance_category = dance_category.category if dance_category.is_a? CatExtension
          category = dance_category.name if dance_category&.cost_override

          if @pcost[category] > 0
            @dances[entry.lead][:dances] += 0.5
            @dances[entry.lead][:cost] += @pcost[category] / 2.0

            @dances[entry.follow][:dances] += 0.5
            @dances[entry.follow][:cost] += @pcost[category] / 2.0
          end
        end
      end

      if @event.independent_instructors && !instructor
        @dances.each do |person, info|
          next if person.type == "Professional" and not person.independent
          info[:purchases] = 0 if info[:dances] == 0
        end
      end

      @dances.reject! do |person, info|
        person.type == "Professional" and person.studio != studio
      end

      unless student || instructor
        studio_formations = Heat.joins(entry: :instructor)
          .where(category: "Solo", entries: { lead_id: 0, follow_id: 0 }, people: { studio_id: studio.id })
        studio_formations.each do |heat|
          cost = @event.studio_formation_cost || 0
          cost = @event.pro_solo_cost || 0 if heat.solo.formations.all? {|formation| formation.person.type == "Professional"}
          other_charges["#{heat.dance.name} Formation"] ||= {entries: 1, count: 1, cost: cost}
        end
      end

      total_other_charges = {
        count: other_charges.values.map {|charge| charge[:count]}.sum,
        cost: other_charges.values.map {|charge| charge[:cost]}.sum
      }

      @invoices[studio] = {
        dance_count: @dances.map {|person, info| info[:dances]}.sum + total_other_charges[:count],
        purchases: @dances.map {|person, info| info[:purchases]}.sum,
        dance_cost: @dances.map {|person, info| info[:cost]}.sum + total_other_charges[:cost],
        total_cost: @dances.map {|person, info| info[:cost] + info[:purchases]}.sum  + total_other_charges[:cost],
        other_charges: other_charges,

        dances: @dances,

        entries: Entry.where(id: entries.map(&:id)).
          order(:level_id, :age_id).
          includes(lead: [:studio], follow: [:studio], heats: [:dance]).group_by {|entry|
            entry.follow.type == "Student" ? [entry.follow, entry.lead] : [entry.lead, entry.follow]
          }.sort_by {|key, value| key}
      }
    end

    # Identify dances being offered
    @offered = {
      freestyles: (Dance.where.not(open_category_id: nil).count + Dance.where.not(closed_category_id: nil).count) > 0,
      solos: (Dance.where.not(solo_category_id: nil).count) > 0,
      multis: (Dance.where.not(multi_category_id: nil).count) > 0
    }
  end

  def heat_sheets
    generate_agenda
    @people ||= Person.where(type: ['Student', 'Professional']).order('name COLLATE NOCASE')

    @heatlist = @people.map {|person| [person, []]}.to_h
    @heats.each do |number, heats|
      heats.each do |heat|
        @heatlist[heat.lead] << heat.id rescue nil
        @heatlist[heat.follow] << heat.id rescue nil
      end
    end

    Formation.includes(:person, solo: :heat).each do |formation|
      next unless formation.on_floor
      @heatlist[formation.person] << formation.solo.heat.id rescue nil
    end

    @layout = 'mx-0 px-5'
    @nologo = true
    @event = Event.current
  end

  def score_sheets
    @judges = Person.where(type: 'Judge').by_name
    @people ||= Person.joins(:studio).where(type: 'Student').order('studios.name, name')
    @heats = Heat.includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).all.order(:number)
    @formations = Formation.joins(solo: :heat).where(on_floor: true).pluck(:person_id, :number)
    @layout = 'mx-0 px-5'
    @nologo = true
    @event = Event.current
    @track_ages = @event.track_ages

    # Load category scores for students
    # Group by person_id and category_id for easy lookup
    @category_scores = Score.where('heat_id < 0').
      where.not(good: [nil, '']).
      includes(:judge).
      group_by { |score| [score.person_id, score.heat_id.abs] }.
      transform_values { |scores| scores.index_by(&:judge_id) }

    # Load categories for category score display
    category_ids = @category_scores.keys.map(&:last).uniq
    @categories = Category.where(id: category_ids).index_by(&:id)
  end

  def render_as_pdf(basename:, concat: [])
    tmpfile = Tempfile.new(basename)

    url = URI.parse(request.url.sub(/\.pdf($|\?)/, '.html\\1'))
    url.scheme = 'http'
    url.hostname = 'localhost'
    url.port = (ENV['FLY_APP_NAME'] && 3000) || request.headers['SERVER_PORT']

    if RUBY_PLATFORM =~ /darwin/
      chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      headless="--headless"
    else
      chrome="google-chrome-stable"
      headless="--headless=new"
    end

    system chrome, headless, '--disable-gpu', '--no-pdf-header-footer',
      "--no-sandbox", "--print-to-pdf=#{tmpfile.path}", url.to_s

    unless concat.empty?
      concat.unshift tmpfile.path
      tmpfile = Tempfile.new(basename)
      system "pdfunite", *concat, tmpfile.path
    end

    send_data tmpfile.read, disposition: 'inline', filename: "#{basename}.pdf",
      type: 'application/pdf'
  ensure
    tmpfile.unlink
  end

  def undoable
    Heat.where('number != prev_number AND prev_number != 0').any?
  end

  def renumber_needed
    Heat.distinct.where.not(number: 0).pluck(:number).
      map(&:abs).sort.uniq.zip(1..).any? {|n, i| n != i}
  end
end
