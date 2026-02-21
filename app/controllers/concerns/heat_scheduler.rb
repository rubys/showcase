module HeatScheduler
  include Printable
  include MultiLevelSplitter

  def build_true_order
    true_order = {}
    dance_orders = Dance.all.group_by(&:name).map {|name, list| [name, list.map(&:order)]}
    dance_orders.each do |name, orders|
      max = orders.max

      # Check if this dance has multi-level splits
      dances_with_name = Dance.where(name: name, order: orders)
      has_multi_level_splits = dances_with_name.any? { |d| d.multi_children.any? && MultiLevel.where(dance: dances_with_name).exists? }

      if has_multi_level_splits
        # Assign fractional orders to keep splits sorted together but separated during grouping
        sorted_orders = orders.sort.reverse
        sorted_orders.each_with_index do |order, index|
          true_order[order] = max + (index * 0.001)
        end
      else
        # For category-based splits (and non-splits), use the same true_order
        # This allows all splits of the same dance to be grouped together during scheduling,
        # then the reorder function will separate them by agenda category
        orders.each {|order| true_order[order] = max}
      end
    end
    true_order
  end

  def schedule_heats
    event = Event.current

    Group.set_knobs

    # reset judge assignments
    Score.where(value: nil, comments: nil, good: nil, bad: nil).delete_all

    # remove all scratches and orphaned entries
    Heat.where(number: ...0).each {|heat| heat.destroy}
    Entry.includes(:heats).where(heats: {id: nil}).each {|entry| entry.destroy}

    fixups

    # Ensure all multi-dance heats are on their correct split dances
    reassign_all_multi_dance_heats

    # extract heats
    @heats = Heat.eager_load(
      :solo,
      dance: [:open_category, :closed_category, :solo_category, :multi_category],
      entry: [{lead: :studio}, {follow: :studio}]
    )

    # convert relevant data to numbers
    heat_categories = {'Closed' => 0, 'Open' => 1, 'Solo' => 2, 'Multi' => 3}
    routines = Category.where(routines: true).all.zip(4..).map {|cat, num| [cat.id, num]}.to_h

    true_order = build_true_order

    # Calculate availability scores if using availability ordering
    availability_scores = {}
    if event.heat_order == 'A'
      people_with_constraints = Person.where.not(available: nil).index_by(&:id)
      
      @heats.each do |heat|
        score = calculate_heat_availability_score(heat, people_with_constraints)
        availability_scores[heat] = score
      end
    end

    heats = @heats.map {|heat|
      if heat.solo&.category_override_id and routines[heat.solo.category_override_id]
        category = routines[heat.solo.category_override_id]
        order = 1000 + heat.solo.order
      else
        category = heat_categories[heat.category]
        category += 4 if heat.entry.pro

        # When heat_range_cat=1, map Closed(0) to Open(1) for sorting
        # This allows Open/Closed mixing by treating them as the same category
        if event.heat_range_cat == 1 && category == 0
          category = 1
        end

        order = true_order[heat.dance.order]
      end

      # For availability ordering, add availability as third sort criterion
      availability = event.heat_order == 'A' ? (availability_scores[heat] || 10000) : 0
      
      # don't split semi-finals by level, age
      [
        order,
        category,
        availability,
        heat.entry.level_id,
        heat.entry.age_id,
        heat
      ]
    }

    heats = Group.sort(heats)

    # If block scheduling is enabled, replace eligible heats with blocks
    if event.heat_order == 'B'
      blocks_map = {}
      remaining_heats = []

      heats.each do |heat_tuple|
        heat = heat_tuple.last

        # Only block amateur open and closed heats
        if !heat.entry.pro && ['Open', 'Closed'].include?(heat.category)
          # Use base_dance_category to avoid dependency on stale heat numbers
          agenda_cat = heat.base_dance_category
          next unless agenda_cat # Skip if no agenda category

          # Create unique key for this block: entry_id + heat_category + agenda_category_id
          block_key = [heat.entry_id, heat.category, agenda_cat.id]

          if !blocks_map[block_key]
            blocks_map[block_key] = Block.new(heat.entry, heat.category, agenda_cat)
          end

          block = blocks_map[block_key]

          # Check if this dance is already in the block (constraint: no duplicate dances in a block)
          if block.heats.any? { |h| h.dance_id == heat.dance_id }
            # Keep non-blockable heat as-is (can't add duplicate dance to block)
            remaining_heats << heat_tuple
          else
            block.add_heat(heat)
          end
        else
          # Keep non-blockable heats as-is
          remaining_heats << heat_tuple
        end
      end

      # Replace heats list with blocks (as tuples) and remaining heats
      block_tuples = blocks_map.values.filter_map do |block|
        # Skip empty blocks (all heats were duplicates)
        next if block.heats.empty?

        # Create a tuple for the block using the first heat's dance order
        first_heat = block.heats.first
        heat_cat_num = heat_categories[block.heat_category]
        heat_cat_num += 4 if block.entry.pro

        if event.heat_range_cat == 1 && heat_cat_num == 0
          heat_cat_num = 1
        end

        # Use the dance order from the first heat in the block
        dance_order = true_order[first_heat.dance.order]

        [
          dance_order,
          heat_cat_num,
          0, # availability score (blocks don't have individual availability)
          block.entry.level_id,
          block.entry.age_id,
          block
        ]
      end

      # Sort blocks and remaining heats together
      # Use sort_by for consistent sorting of mixed Heat/Block collections
      combined = block_tuples + remaining_heats
      heats = combined.sort_by do |tuple|
        # For sorting, use the tuple values themselves, not the final object
        # tuple format: [dance_order, category, availability, level_id, age_id, heat_or_block]
        if event.heat_range_cat == 0
          # Reverse first two elements for category=0
          tuple[0..1].reverse + tuple[2..4]
        else
          tuple[0..4]
        end
      end
    end

    max = event.max_heat_size || 9999

    # group entries into heats
    groups = []
    while not heats.empty?
      Group.max = 9999

      assignments = {}
      subgroups = []

      if event.heat_order == 'R'

        # first, extract all heats in the group
        pending = []
        group = nil
        heats.each_with_index do |entry, index|
          if index == 0
            group = Group.new
            group.add? *entry
            pending << index
          else
            if group.match? *entry
              pending << index
            else
              break
            end
          end
        end

        # now organize heats into subgroups
        more = pending.first
        while more
          group = Group.new
          subgroups.unshift group
          more = nil

          pending.shuffle!
          pending.each do |index|
            next if assignments[index]
            entry = heats[index]

            if group.add? *entry
              assignments[index] = group
            else
              more ||= index
            end
          end
        end

      else

        # organize heats into groups
        more = heats.first
        while more
          group = Group.new
          subgroups.unshift group
          more = nil

          heats.each_with_index do |entry, index|
            next if assignments[index]
            if group.add? *entry
              assignments[index] = group
            elsif group.match? *entry
              more ||= entry
            else
              break
            end
          end
        end
      end

      Group.max = group.max_heat_size

      if event.heat_order == 'R'
        assignments = assignments.map {|index, assignment| [heats[index], assignment]}.to_h
      else
        assignments = (0...assignments.length).map {|index| [heats[index], assignments[index]]}.to_h
      end

      rebalance(assignments, subgroups, group.max_heat_size)

      heats.shift assignments.length
      groups += subgroups.reverse
    end

    groups = reorder(groups)

    if event.heat_range_level == 0
      i = 0
      groups.sort_by! {|group| [group.first.entry.level_id, i += 1]}
    end

    # Note: Availability ordering is now handled during initial heat sorting,
    # not as a post-processing step

    # Pack multi-dance split groups to reduce heat count
    groups = pack_multi_dance_splits(groups)

    ActiveRecord::Base.transaction do
      heat_number = 1

      groups.each do |group|
        # Check if this group contains blocks
        has_blocks = false
        group.each { |item| has_blocks = true if item.is_a?(Block) }

        if has_blocks
          # Unpack blocks: collect all heats from all blocks in this group
          all_heats = []
          group.each do |item|
            if item.is_a?(Block)
              all_heats.concat(item.heats)
            else
              all_heats << item
            end
          end

          # Sort and group by dance order
          heats_by_dance = all_heats.group_by { |heat| true_order[heat.dance.order] }
          sorted_dance_orders = heats_by_dance.keys.sort

          # Assign consecutive heat numbers to each dance group
          sorted_dance_orders.each do |dance_order|
            heats_by_dance[dance_order].each do |heat|
              heat.number = heat_number
              heat.save validate: false
            end
            heat_number += 1
          end
        else
          # Regular group without blocks
          group.each do |heat|
            heat.number = heat_number
            heat.save validate: false
          end
          heat_number += 1
        end
      end
    end

    limited_availability = Person.where.not(available: nil).all
    if limited_availability.any? && (Event.current.heat_order == "R" || Event.current.heat_order == "A")
      exchange_heats(limited_availability)
      rescue_individual_heats(limited_availability)
      unschedule_remaining_violations(limited_availability)
      @heats = Heat.eager_load(
        :solo,
        dance: [:open_category, :closed_category, :solo_category, :multi_category],
        entry: [{lead: :studio}, {follow: :studio}]
      ).all
    end

    @stats = groups.each_with_index.
      map {|group, index| [group, index+1]}.
      group_by {|group, heat| group.size}.
      map {|size, entries| [size, entries.map(&:last)]}.
      sort

    # Persist computed ballroom assignments to database for consistent display
    generate_agenda
    persist_ballroom_assignments

    # Reload heats since generate_agenda modifies @heats format
    @heats = Heat.eager_load(
      :solo,
      dance: [:open_category, :closed_category, :solo_category, :multi_category],
      entry: [{lead: :studio}, {follow: :studio}]
    ).all

    @heats = @heats.
      group_by {|heat| heat.number}.map do |number, heats|
        [number, heats.sort_by { |heat| heat.back || 0 } ]
      end.sort
  end

  def rebalance(assignments, subgroups, max)
    return if max <= 0
    while subgroups.length * max < assignments.length
      subgroups.unshift Group.new
    end

    ceiling = (assignments.length.to_f / subgroups.length).ceil
    floor = (assignments.length.to_f / subgroups.length).floor

    assignments.to_a.reverse.each do |(entry, source)|
      subgroups.each do |target|
        break if target == source
        next if target.size >= ceiling
        next if target.size >= source.size

        if target.add? *entry
          source.remove *entry
          assignments[entry] = target
          break
        end
      end
    end

    subgroups.select {|subgroup| subgroup.size < floor}.each do |target|
      assignments.each do |entry, source|
        next if source.size < max
        if target.add? *entry
          source.remove *entry
          assignments[entry] = target
          break if target.size >= max
        end
      end
    end

    if subgroups.any? {|subgroup| subgroup.size > max}
      assignments.each do |entry, target|
        next if target.size >= max
        subgroups.each do |source|
          next if source.size <= max
          if target.add? *entry
            source.remove *entry
            assignments[entry] = target
            break if target.size >= max
          end
        end
      end

      if subgroups.any? {|subgroup| subgroup.size > max}
        subgroups.unshift Group.new
        rebalance(assignments, subgroups, max)
      end
    end
  end

  def reorder(groups)
    categories = Category.ordered.all
    cats = Hash.new { |h, k| h[k] = [] }
    solos = Hash.new { |h, k| h[k] = [] }
    multis = Hash.new { |h, k| h[k] = [] }

    # Initialize with known categories to maintain order
    categories.each { |cat| cats[cat] = []; solos[cat] = []; multis[cat] = [] }
    cats[nil] = []; solos[nil] = []; multis[nil] = []

    groups.each do |group|
      heat = group.first
      next unless heat

      # Use the agenda_category that was stored when the group was created
      # instead of trying to derive it from dance properties
      cat = group.agenda_category

      if heat.category == 'Solo'
        solos[cat] << group
      elsif heat.category == 'Multi'
        multis[cat] << group
      else
        cats[cat] << group
      end
    end

    new_order = []
    agenda = {}

    true_order = build_true_order

    cats.each do |cat, groups|
      original_count = groups.length

      if Event.current.intermix
        dances = groups.group_by {|group| [group.dcat, true_order[group.dance.order]]}
        candidates = []

        max = dances.values.map(&:length).max || 1
        offset = 0.5/(max + 1)

        dances.each do |id, dance_groups|
          denominator = dance_groups.length.to_f + 1
          dance_groups.each_with_index do |group, index|
            slot = (((index+1.0)/denominator - offset)/offset/2).to_i
            candidates << [slot] + id + [group]
          end
        end

        groups = candidates.sort_by {|candidate| candidate[0..2]}.map(&:last)
      end

      # Debug: Check if groups were lost
      if groups.length != original_count
        Rails.logger.warn "Category #{cat&.name}: lost #{original_count - groups.length} groups during intermix (#{original_count} -> #{groups.length})"
      end

      groups +=
        solos[cat].sort_by {|group| group.first.solo.order} +
        multis[cat]

      if cat
        extensions_needed = 0

        if !cat.split.blank?
          split = cat.split.split(/[, ]+/).map(&:to_i)
          heat_count = groups.length
          loop do
            block = split.shift
            break if block >= heat_count || block <= 0
            extensions_needed += 1
            heat_count -= block
            split.push block if split.empty?
          end
        end

        extensions_found = cat.extensions.order(:part).all.to_a

        while extensions_found.length > extensions_needed
          extensions_found.pop.destroy!
        end

        while extensions_needed > extensions_found.length
          order = [Category.maximum(:order), CatExtension.maximum(:order)].compact.max + 1
          extensions_found << CatExtension.create!(category: cat, order: order, part: extensions_found.length + 2)
        end

        if extensions_needed > 0
          split = cat.split.split(/[, ]+/).map(&:to_i)
          block = split.shift
          remainder = groups[block..]
          groups = groups[0...block]
          extensions_found.each do |extension|
            split.push block if split.empty?
            block = split.shift
            break if block <= 0 || remainder.empty?
            agenda[extension] = remainder[0...block]
            remainder = remainder[block..]
          end
        end
      end

      agenda[cat] = groups
    end

    cats = agenda.to_a.sort_by {|cat, groups| cat&.order || 999}.to_h

    heat = 1
    cats.each do |cat, groups|
      if cat.instance_of? CatExtension
        cat.update! start_heat: heat
      elsif cat&.locked
        heats = groups.map {|group| group.each.to_a}.flatten.
          select {|heat| heat.number > 0}.sort_by {|heat| heat.number}
        groups = heats.group_by {|heat| heat.number}.values.
          map {|heats| Group.new(heats)}
        cats[cat] = groups
        cat.update! locked: false if groups.empty?
      end

      heat += groups.length
    end

    cats.values.flatten
  end

  # Pack consecutive multi-dance split groups to reduce heat count.
  # Packs multi-dance splits into fewer heats.
  # Applies to both MultiLevel-based splits (same dance name) and pre-split
  # dances (different names but same multi_category and heat_length).
  # Groups can be combined if:
  # 1. They are for the same multi-dance (same dance name or same multi_category)
  # 2. No dancer would appear twice in the combined group
  # 3. Combined size doesn't exceed max heat size
  def pack_multi_dance_splits(groups)
    return groups if groups.empty?

    event = Event.current

    # Identify which dance names have multi_level splits
    dances_with_splits = Set.new
    Dance.joins(:multi_levels).where(order: 1..).distinct.pluck(:name).each do |name|
      dances_with_splits.add(name)
    end

    packed = []
    i = 0

    while i < groups.length
      group = groups[i]
      heat = group.first

      # Check if this is a Multi heat for a dance with splits or pre-split multi_category
      if heat&.category == 'Multi' && (
           dances_with_splits.include?(heat.dance.name) ||
           heat.dance.multi_category_id.present?
         )
        # Find consecutive groups for the same multi-dance
        run_start = i
        run_end = i

        while run_end + 1 < groups.length
          next_group = groups[run_end + 1]
          next_heat = next_group.first
          break unless next_heat&.category == 'Multi' &&
                       next_group.agenda_category == group.agenda_category

          if dances_with_splits.include?(heat.dance.name)
            # MultiLevel case: same dance name
            break unless next_heat.dance.name == heat.dance.name
          else
            # Pre-split case: same heat_length, same multi_category, not a MultiLevel dance
            break unless next_heat.dance.heat_length == heat.dance.heat_length &&
                         next_heat.dance.multi_category_id == heat.dance.multi_category_id &&
                         next_heat.dance.multi_category_id.present? &&
                         !dances_with_splits.include?(next_heat.dance.name)
          end

          run_end += 1
        end

        if run_end > run_start
          # We have multiple groups that could potentially be combined
          run_groups = groups[run_start..run_end]
          packed_run = pack_group_run(run_groups, event)
          packed.concat(packed_run)
          i = run_end + 1
        else
          # Single group, no packing possible
          packed << group
          i += 1
        end
      else
        # Not a packable group
        packed << group
        i += 1
      end
    end

    packed
  end

  # Pack a run of groups for the same multi-dance
  # Each group represents a split (dance_id) and must stay together as a unit.
  # We combine entire splits into the same heat, never breaking up a split.
  # Only splits with matching couple_type can be combined.
  def pack_group_run(run_groups, event)
    return run_groups if run_groups.length <= 1

    # Get max heat size (use first group's category or event default)
    first_heat = run_groups.first.first
    agenda_cat = first_heat&.dance_category
    max_size = agenda_cat&.max_heat_size || event.max_heat_size || 9999

    # Build a lookup of dance_id -> couple_type from MultiLevel records
    dance_ids = run_groups.map { |g| g.first&.dance_id }.compact.uniq
    couple_type_by_dance = MultiLevel.where(dance_id: dance_ids).pluck(:dance_id, :couple_type).to_h

    # Greedy bin-packing: try to fit entire groups (splits) into as few packed groups as possible
    packed_groups = []

    run_groups.each do |group|
      # Get all heats and participants for this split
      group_heats = group.each.to_a
      group_participants = Set.new
      group_heats.each do |heat|
        group_participants.add(heat.entry.lead_id) if heat.entry.lead_id != 0
        group_participants.add(heat.entry.follow_id) if heat.entry.follow_id != 0
      end

      # Get couple_type for this group's dance
      group_couple_type = couple_type_by_dance[group.first&.dance_id]

      placed = false

      # Try to add entire group to an existing packed group
      packed_groups.each do |packed_group|
        if can_add_group_to_packed?(group_heats, group_participants, group_couple_type, packed_group, max_size)
          packed_group[:heats].concat(group_heats)
          packed_group[:participants].merge(group_participants)
          placed = true
          break
        end
      end

      # If not placed, create a new packed group
      unless placed
        packed_groups << {
          heats: group_heats,
          participants: group_participants,
          couple_type: group_couple_type,
          agenda_category: run_groups.first.agenda_category
        }
      end
    end

    # Rebalance: move entire splits from larger groups to smaller ones when possible
    packed_groups = rebalance_packed_groups(packed_groups, max_size)

    # Convert packed groups back to Group objects
    packed_groups.map do |pg|
      new_group = Group.new(pg[:heats])
      # Copy agenda_category to the new group
      new_group.instance_variable_set(:@agenda_category, pg[:agenda_category])
      new_group
    end
  end

  # Check if an entire group (split) can be added to a packed group
  def can_add_group_to_packed?(group_heats, group_participants, group_couple_type, packed_group, max_size)
    # Check couple_type compatibility - only combine splits with matching couple_type
    return false if group_couple_type != packed_group[:couple_type]

    # Check size limit
    return false if packed_group[:heats].size + group_heats.size > max_size

    # Check for participant conflicts
    return false unless (group_participants & packed_group[:participants]).empty?

    # Check exclude relationships
    group_heats.each do |heat|
      lead = heat.entry.lead
      follow = heat.entry.follow

      return false if lead.exclude_id && packed_group[:participants].include?(lead.exclude_id)
      return false if follow.exclude_id && packed_group[:participants].include?(follow.exclude_id)
    end

    # Also check reverse: existing participants' excludes against new group
    packed_group[:heats].each do |heat|
      lead = heat.entry.lead
      follow = heat.entry.follow

      return false if lead.exclude_id && group_participants.include?(lead.exclude_id)
      return false if follow.exclude_id && group_participants.include?(follow.exclude_id)
    end

    true
  end

  # Rebalance packed groups by moving entire splits to distribute heats more evenly.
  # Unlike the old rebalance which moved individual heats (breaking splits),
  # this moves complete splits as atomic units.
  # Only moves splits between groups with matching couple_type.
  def rebalance_packed_groups(packed_groups, max_size)
    return packed_groups if packed_groups.length <= 1

    # Track which heats belong to each split (dance_id)
    # so we can move them together as a unit
    splits_in_groups = packed_groups.map do |pg|
      splits = pg[:heats].group_by(&:dance_id)
      splits.transform_values do |heats|
        {
          heats: heats,
          participants: Set.new(heats.flat_map { |h| [h.entry.lead_id, h.entry.follow_id] }.reject(&:zero?))
        }
      end
    end

    # Keep trying to rebalance until no more moves are possible
    changed = true
    while changed
      changed = false

      # Sort by size descending to find largest groups first
      sorted_indices = packed_groups.each_index.sort_by { |i| -packed_groups[i][:heats].size }
      largest_idx = sorted_indices.first
      smallest_idx = sorted_indices.last

      largest = packed_groups[largest_idx]
      smallest = packed_groups[smallest_idx]

      # Only rebalance if difference is > 1 and couple_types match
      next unless largest[:heats].size - smallest[:heats].size > 1
      next unless largest[:couple_type] == smallest[:couple_type]

      # Try to move an entire split from largest to smallest
      splits_in_groups[largest_idx].each do |dance_id, split_data|
        split_heats = split_data[:heats]
        split_participants = split_data[:participants]

        # Check if moving this split would help (not make smallest bigger than largest)
        new_largest_size = largest[:heats].size - split_heats.size
        new_smallest_size = smallest[:heats].size + split_heats.size

        next if new_smallest_size > new_largest_size + 1  # Would reverse the imbalance
        next if new_smallest_size > max_size  # Would exceed max size

        # Check if split can be added to smallest group (couple_type already verified above)
        if can_add_group_to_packed?(split_heats, split_participants, largest[:couple_type], smallest, max_size)
          # Move the entire split
          split_heats.each { |heat| largest[:heats].delete(heat) }
          largest[:participants] -= split_participants

          smallest[:heats].concat(split_heats)
          smallest[:participants].merge(split_participants)

          # Update splits tracking
          splits_in_groups[smallest_idx][dance_id] = split_data
          splits_in_groups[largest_idx].delete(dance_id)

          changed = true
          break
        end
      end
    end

    # Remove any empty groups
    packed_groups.reject { |g| g[:heats].empty? }
  end

  class Group
    def self.set_knobs
      @@event = Event.current
      @@category = @@event.heat_range_cat
      @@level = @@event.heat_range_level
      @@age = @@event.heat_range_age
      @@max = @@event.max_heat_size || 9999

      # only combine open/closed dances if the category is the same
      if @@category == 0
        @@combinable = []
      else
        # Include dances where open and closed categories are the same
        combinable = Dance.all.select {|dance| dance.open_category && dance.open_category_id == dance.closed_category_id}.map(&:id)

        # Also include split dances that share an agenda category
        # Group dances by name
        Dance.all.group_by(&:name).each do |name, dances|
          next if dances.length == 1  # Skip non-split dances

          # For each agenda category, find all dances (splits) that belong to it
          category_to_dances = Hash.new { |h, k| h[k] = [] }
          dances.each do |dance|
            [dance.open_category_id, dance.closed_category_id].compact.each do |cat_id|
              category_to_dances[cat_id] << dance.id
            end
          end

          # Mark all splits in the same agenda category as combinable
          category_to_dances.each do |cat_id, dance_ids|
            combinable.concat(dance_ids) if dance_ids.length > 1
          end
        end

        @@combinable = combinable.uniq
      end
    end

    def self.max= max
      @@max = max
    end

    def self.sort(heats)
      if @@category == 0
        heats.sort_by {|heat| heat[0..1].reverse + heat[2..-1]}
      else
        heats.sort
      end
    end

    def dance
      @group.first&.dance
    end

    def override
      @group.first&.solo&.category_override
    end

    def dcat
      case @min_dcat
      when 0
        'Closed'
      when 1
        'Open'
      when 2
        'Solo'
      when 3
        'Multi'
      when 4
        'Pro Closed'
      when 5
        'Pro Open'
      when 6
        'Pro Solo'
      when 7
        'Pro Multi'
      else
        '?'
      end
    end

    def max_heat_size
      agenda_cat = case @min_dcat
      when 0
        dance&.closed_category
      when 1
        dance&.open_category
      when 2
        dance&.solo_category
      when 3
        dance&.multi_category
      when 4
        dance&.pro_closed_category
      when 5
        dance&.pro_open_category
      when 6
        dance&.pro_solo_category
      when 7
        dance&.pro_multi_category
      else
        nil
      end

      agenda_cat&.max_heat_size || @@event.max_heat_size || 9999
    end

    attr_reader :agenda_category

    def initialize(list = [])
      @group = list
      @agenda_category = nil
    end

    def match?(dance, dcat, availability, level, age, heat)
      return false unless @dance == dance
      return false unless @dcat == dcat or @@combinable.include? dance
      return false if heat.category == 'Solo'

      return true
    end

    def add?(dance, dcat, availability, level, age, heat)
      if @group.length == 0
        @participants = Set.new

        @max_dcat = @min_dcat = dcat
        @max_level = @min_level = level
        @max_age = @min_age = age

        @dance = dance
        @dcat = dcat
        # Use base_dance_category to avoid dependency on stale heat numbers
        @agenda_category = heat.base_dance_category
      end

      return if @group.size >= @@max
      # Skip participant checks for Nobody (id=0) - allows multiple partnerless entries
      return if heat.lead.id != 0 && @participants.include?(heat.lead)
      return if heat.follow.id != 0 && @participants.include?(heat.follow)
      return if heat.lead.exclude_id and @participants.include? heat.lead.exclude
      return if heat.follow.exclude_id and @participants.include? heat.follow.exclude

      formations = heat.solo&.formations&.map(&:person)
      return if formations and @participants.any? {|participant| formations.include? participant}

      return false unless @dance == dance
      return false if heat.category == 'Solo' and @group.length > 0
      return false unless dcat == @max_dcat or @@combinable.include? dance
      return false unless dcat == @min_dcat or @@combinable.include? dance
      return false unless (level-@max_level).abs <= @@level
      return false unless (level-@min_level).abs <= @@level
      return false unless (age-@max_age).abs <= @@age
      return false unless (age-@min_age).abs <= @@age

      # Check agenda category compatibility (use base category to avoid stale numbers)
      heat_agenda_cat = heat.base_dance_category
      return false unless @agenda_category == heat_agenda_cat

      @participants.add heat.lead
      @participants.add heat.follow
      @participants += formations if formations

      @max_dcat = dcat if dcat > @max_dcat
      @min_dcat = dcat if dcat < @min_dcat
      @min_level = level if level < @min_level
      @max_level = level if level > @max_level
      @min_age = age if age < @min_age
      @max_age = age if age > @max_age

      @group << heat
    end

    def remove(dance, dcat, availability, level, age, heat)
      @group.delete heat
      @participants.delete heat.lead
      @participants.delete heat.follow
    end

    def each(&block)
      @group.each(&block)
    end

    def first
      @group.first
    end

    def size
      @group.size
    end
  end

  # BlockDance: Virtual dance representing an agenda category for block scheduling
  class BlockDance
    attr_reader :agenda_category, :dance_order

    def initialize(agenda_category, dance_order)
      @agenda_category = agenda_category
      @dance_order = dance_order
    end

    def id
      "block_#{@agenda_category.id}"
    end

    def order
      @dance_order
    end

    def semi_finals
      false
    end

    # Return the agenda category for all category types
    def open_category
      @agenda_category
    end

    def closed_category
      @agenda_category
    end

    def solo_category
      @agenda_category
    end

    def multi_category
      @agenda_category
    end

    def pro_open_category
      @agenda_category
    end

    def pro_closed_category
      @agenda_category
    end

    def pro_solo_category
      @agenda_category
    end

    def pro_multi_category
      @agenda_category
    end
  end

  # Block: Container for multiple heats with the same entry and agenda category
  class Block

    attr_reader :heats, :entry, :heat_category, :agenda_category, :block_dance

    def initialize(entry, heat_category, agenda_category)
      @entry = entry
      @heat_category = heat_category
      @agenda_category = agenda_category
      @heats = []
      @block_dance = nil  # Will be set when first heat is added
    end

    def add_heat(heat)
      @heats << heat
      # Set block_dance based on first heat's dance order
      if @block_dance.nil?
        @block_dance = BlockDance.new(@agenda_category, heat.dance.order)
      end
    end

    def dance
      @block_dance
    end

    def dance_id
      @block_dance&.id
    end

    def category
      @heat_category
    end

    def lead
      @entry.lead
    end

    def follow
      @entry.follow
    end

    def dance_category
      @agenda_category
    end

    def base_dance_category
      @agenda_category
    end

    def solo
      nil
    end

    def number
      nil  # Blocks don't have heat numbers until unpacked
    end

    def number=(value)
      # Blocks can't be assigned numbers directly
    end

  end

  if ENV['RAILS_APP_DB'] == '2024-monterey'
    alias :schedule_heats_orig :schedule_heats

    def schedule_heats
      # Ensure Bill Giuliani's pro-am heats are scheduled to exactly correspond with his wife's pro-am heats
      entries = Entry.where(follow_id: 8, lead_id: 36)
      entry_attributes = entries.first.attributes
      Heat.where(entry: entries).delete_all

      entries = Entry.where(follow_id: 37).where.not(lead_id: 36)
      heats = Heat.where(entry: entries)

      heats.each do |heat|
        unless heat.solo
          solo = Solo.new(heat_id: heat.id)
          solo.order = (Solo.maximum(:order) || 0) + 1
          heat.solo = solo
          heat.save!
        end

        people = heat.solo.formations.pluck(:person_id)

        unless people.include? 36
          formation = Formation.new(solo_id: heat.solo.id, person_id: 36)
          formation.save!
        end

        unless people.include? 8
          formation = Formation.new(solo_id: heat.solo.id, person_id: 8)
          formation.save!
        end
      end

      schedule_heats_orig

      solos = Formation.includes(:solo).where(person_id: [8, 36]).map(&:solo).uniq
      entry = Entry.find_by(follow_id: 8, lead_id: 36)
      entry ||= Entry.create!(entry_attributes)

      solos.each do |solo|
        Heat.create!(
          number: solo.heat.number,
          category: solo.heat.category,
          dance_id: solo.heat.dance_id,
          entry_id: entry.id
        )

        solo.destroy!
      end
    end
  end

  def exchange_heats(people)
    pinned = Set.new
    problems = []

    @include_times = true
    generate_agenda

    return unless @start

    start_times = @heats.map {|heat| heat.first.to_f}.zip(@start.compact)

    people.each do |person|
      ok = person.eligible_heats(start_times)

      heats = Heat.joins(:entry).
        includes(:dance, entry: [:lead, :follow]).
        where(entry: {lead: person}).
        or(Heat.where(entry: {follow: person})).
        or(Heat.where(id: Formation.joins(:solo).where(person: person, on_floor: true).pluck(:heat_id)))

      heats.each do |heat|
        if ok.include? heat.number.to_f
          pinned.add heat.number.to_f
        else
          problems << [heat, ok, person]
        end
      end
    end

    # Sort problems by availability score - prioritize people with fewer available slots
    problems.sort_by! do |heat, available, person|
      [available.size, heat.number.to_f]
    end

    problems.each do |heat, available, person|
      numbers = available - pinned - [heat.number.to_f]
      
      # Find all potential alternates with availability scoring
      candidates = Heat.where(category: heat.category, dance_id: heat.dance_id, number: numbers).distinct.pluck(:number)
      
      if candidates.any?
        # Score each candidate by how many availability conflicts it would resolve/create
        best_alternate = candidates.max_by do |candidate_number|
          score_heat_swap(heat.number, candidate_number, people, start_times)
        end
        
        original = heat.number
        source = Heat.where(number: original).all.to_a
        destination = Heat.where(number: best_alternate).all.to_a

        ActiveRecord::Base.transaction do
          source.each {|heat| heat.update!(number: best_alternate)}
          destination.each {|heat| heat.update!(number: original)}
        end

        pinned.add best_alternate
      else
        # Don't unschedule solos even if no alternate can be found
        unless heat.category == 'Solo'
          heat.update(number: 0)
        end
      end
    end
  end

  # Score a potential heat swap based on availability conflict resolution
  def score_heat_swap(original_number, candidate_number, people, start_times)
    score = 0
    
    # Get all participants in both heats
    original_heats = Heat.includes(:entry, solo: :formations).where(number: original_number)
    candidate_heats = Heat.includes(:entry, solo: :formations).where(number: candidate_number)
    
    people.each do |person|
      person_ok = person.eligible_heats(start_times)
      
      # Check if person is in original heat
      in_original = original_heats.any? do |heat|
        [heat.entry&.lead_id, heat.entry&.follow_id].include?(person.id) ||
        heat.solo&.formations&.where(person: person, on_floor: true)&.exists?
      end
      
      # Check if person is in candidate heat  
      in_candidate = candidate_heats.any? do |heat|
        [heat.entry&.lead_id, heat.entry&.follow_id].include?(person.id) ||
        heat.solo&.formations&.where(person: person, on_floor: true)&.exists?
      end
      
      if in_original
        # Moving from original to candidate - score based on availability improvement
        original_ok = person_ok.include?(original_number.to_f)
        candidate_ok = person_ok.include?(candidate_number.to_f)
        
        if !original_ok && candidate_ok
          score += 10  # Resolves a conflict
        elsif original_ok && !candidate_ok
          score -= 10  # Creates a conflict
        end
      end
      
      if in_candidate
        # Moving from candidate to original - score based on availability impact
        original_ok = person_ok.include?(original_number.to_f)
        candidate_ok = person_ok.include?(candidate_number.to_f)
        
        if !candidate_ok && original_ok
          score += 10  # Resolves a conflict
        elsif candidate_ok && !original_ok
          score -= 10  # Creates a conflict
        end
      end
    end
    
    score
  end

  # Final pass to rescue individual heats that couldn't be handled by group swapping
  def rescue_individual_heats(people)
    @include_times = true
    generate_agenda
    return unless @start

    start_times = @heats.map {|heat| heat.first.to_f}.zip(@start.compact)
    
    # Find all problematic heats (unscheduled + availability violations)
    problematic_heats = []
    
    # Add unscheduled heats (heat 0)
    Heat.where(number: 0).each do |heat|
      if involves_availability_constrained_person?(heat, people)
        problematic_heats << heat
      end
    end
    
    # Add scheduled heats with availability violations
    people.each do |person|
      eligible = person.eligible_heats(start_times)
      
      heats = Heat.joins(:entry).where('number > 0').
        where('entries.lead_id = ? OR entries.follow_id = ?', person.id, person.id)
      
      formation_heats = Heat.joins(solo: :formations).
        where(formations: { person_id: person.id, on_floor: true }, heats: { number: (0.1..Float::INFINITY) })
      
      (heats + formation_heats).uniq.each do |heat|
        unless eligible.include?(heat.number.to_f)
          problematic_heats << heat unless problematic_heats.include?(heat)
        end
      end
    end
    
    # Try to rescue each problematic heat
    problematic_heats.each do |heat|
      rescue_single_heat(heat, people, start_times)
    end
  end
  
  # Try to move a single heat to a better time slot
  def rescue_single_heat(heat, people, start_times)
    # Get all participants in this heat
    participants = []
    participants += [heat.entry&.lead_id, heat.entry&.follow_id].compact if heat.entry
    heat.solo&.formations&.where(on_floor: true)&.each do |formation|
      participants << formation.person_id
    end
    
    # Find availability windows for all participants
    participant_people = people.select { |p| participants.include?(p.id) }
    return if participant_people.empty?
    
    # Get intersection of all participants' available time windows
    available_heats = nil
    participant_people.each do |person|
      person_available = person.eligible_heats(start_times)
      available_heats = available_heats ? (available_heats & person_available) : person_available
    end
    
    return if available_heats.empty?
    
    # Find candidate destination heats in available time windows
    candidates = Heat.where(
      category: heat.category,
      dance_id: heat.dance_id,
      number: available_heats.to_a
    ).where('number > 0')
    
    best_candidate = nil
    best_score = -Float::INFINITY
    
    candidates.each do |candidate_heat|
      # Check if this heat has room and no participant conflicts
      current_size = Heat.where(number: candidate_heat.number).count
      max_size = Event.current.max_heat_size || 9999
      
      next if current_size >= max_size
      
      # Check for participant conflicts in the destination heat
      has_conflict = false
      Heat.where(number: candidate_heat.number).each do |existing_heat|
        existing_participants = []
        existing_participants += [existing_heat.entry&.lead_id, existing_heat.entry&.follow_id].compact if existing_heat.entry
        existing_heat.solo&.formations&.where(on_floor: true)&.each do |formation|
          existing_participants << formation.person_id
        end
        
        if (participants & existing_participants).any?
          has_conflict = true
          break
        end
      end
      
      next if has_conflict
      
      # Score this candidate (prefer earlier heat numbers for better schedule flow)
      score = -candidate_heat.number.to_f
      
      if score > best_score
        best_score = score
        best_candidate = candidate_heat
      end
    end
    
    # Move the heat to the best candidate slot
    if best_candidate
      heat.update!(number: best_candidate.number)
    end
  end
  
  # Check if a heat involves anyone with availability constraints
  def involves_availability_constrained_person?(heat, people)
    participants = []
    participants += [heat.entry&.lead_id, heat.entry&.follow_id].compact if heat.entry
    heat.solo&.formations&.where(on_floor: true)&.each do |formation|
      participants << formation.person_id
    end
    
    people_ids = people.map(&:id)
    (participants & people_ids).any?
  end

  # Calculate availability score for a single heat
  def calculate_heat_availability_score(heat, people_with_constraints)
    earliest_constraint = Float::INFINITY
    has_early_departure = false
    has_late_arrival = false
    
    # Check lead and follow
    [heat.entry&.lead_id, heat.entry&.follow_id].compact.each do |person_id|
      if people_with_constraints[person_id]
        constraint = people_with_constraints[person_id].available
        if constraint[0] == '<'
          # Early departure - extract time and use as score (earlier departure = lower score)
          has_early_departure = true
          time_str = constraint[1..]
          # Parse as hours and minutes for comparison
          if time_str =~ /T(\d{2}):(\d{2})/
            time_score = $1.to_i * 60 + $2.to_i
            earliest_constraint = [earliest_constraint, time_score].min
          end
        elsif constraint[0] == '>'
          # Late arrival
          has_late_arrival = true
        end
      end
    end
    
    # Check formations
    heat.solo&.formations&.where(on_floor: true)&.each do |formation|
      if people_with_constraints[formation.person_id]
        constraint = people_with_constraints[formation.person_id].available
        if constraint[0] == '<'
          has_early_departure = true
          time_str = constraint[1..]
          if time_str =~ /T(\d{2}):(\d{2})/
            time_score = $1.to_i * 60 + $2.to_i
            earliest_constraint = [earliest_constraint, time_score].min
          end
        elsif constraint[0] == '>'
          has_late_arrival = true
        end
      end
    end
    
    # Calculate final score:
    # 1. Early departures get lowest scores (schedule first)
    # 2. No constraints get middle scores (schedule in middle)  
    # 3. Late arrivals get highest scores (schedule last)
    if has_early_departure
      earliest_constraint  # Lower time = earlier in schedule
    elsif has_late_arrival
      20000  # High score to schedule late
    else
      10000 + rand(100)  # Middle score for no constraints, with small random variation
    end
  end

  # Final cleanup: move any remaining availability violations to heat 0 (unscheduled)
  def unschedule_remaining_violations(people)
    @include_times = true
    generate_agenda
    return unless @start

    start_times = @heats.map {|heat| heat.first.to_f}.zip(@start.compact)
    
    people.each do |person|
      eligible = person.eligible_heats(start_times)
      
      # Find all heats this person is scheduled in
      heats = Heat.joins(:entry).where('number > 0').
        where('entries.lead_id = ? OR entries.follow_id = ?', person.id, person.id)
      
      formation_heats = Heat.joins(solo: :formations).
        where(formations: { person_id: person.id, on_floor: true }, heats: { number: (0.1..Float::INFINITY) })
      
      (heats + formation_heats).uniq.each do |heat|
        # Skip solos - don't unschedule them even if they violate availability
        next if heat.category == 'Solo'
        
        # If this heat violates their availability, unschedule it
        unless eligible.include?(heat.number.to_f)
          heat.update!(number: 0)
        end
      end
    end
  end

  def fixups
    open_orphans = Dance.joins(:open_category).where(order: ...0, open_category: {routines: false})
    open_orphans.each do |dance|
      base = Dance.find_by(name: dance.name, order: 1...)

      if base
        Heats.where(id: dance.heats.pluck(:id).update_all(dance_id base.id))
      else
        dance.update(order: Dance.maximum(:order) + 1)
      end
    end

    closed_orphans = Dance.joins(:closed_category).where(order: ...0, closed_category: {routines: false})
    closed_orphans.each do |dance|
      base = Dance.find_by(name: dance.name, order: 1...)

      if base
        Heats.where(id: dance.heats.pluck(:id).update_all(dance_id base.id))
      else
        dance.update(order: Dance.maximum(:order) + 1)
      end
    end
  end

end
