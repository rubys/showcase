# frozen_string_literal: true

# Handles splitting multi-dances into competition divisions by level, age, and couple type.
#
# Multi-dances can be split into separate competition groups (each with its own Dance record)
# based on three layered criteria:
#   1. Level (e.g., Bronze vs Silver vs Gold)
#   2. Age (e.g., 20-40 vs 50+)
#   3. Couple type (e.g., Pro-Am vs Amateur Lead vs Amateur Follow vs Amateur Couple)
#
# Each split creates a new Dance record with negative order (to distinguish from the original)
# and a MultiLevel record to track the split criteria.
module MultiLevelSplitter
  extend ActiveSupport::Concern

  private

    # ===== HELPER METHODS =====

    # Format a multi-level name from level range
    def format_multi_level_name(start_level_obj, stop_level_obj)
      if start_level_obj.id == stop_level_obj.id
        start_level_obj.name
      else
        "#{start_level_obj.name} - #{stop_level_obj.name}"
      end
    end

    # Format level name from level IDs
    def format_level_name_from_ids(start_level_id, stop_level_id)
      format_multi_level_name(Level.find(start_level_id), Level.find(stop_level_id))
    end

    # Format age range name from age objects
    def format_age_range_name(start_age_obj, stop_age_obj)
      if start_age_obj.id == stop_age_obj.id
        start_age_obj.description
      else
        "#{start_age_obj.description} - #{stop_age_obj.description}"
      end
    end

    # Format split name including age
    def format_split_name(multi_level, start_obj, stop_obj, type)
      level_part = format_level_name_from_ids(multi_level.start_level, multi_level.stop_level)

      if type == :age
        age_part = start_obj.id == stop_obj.id ? start_obj.description : "#{start_obj.description} - #{stop_obj.description}"
        "#{level_part} #{age_part}"
      else
        level_part
      end
    end

    # Get base name without couple type suffix
    def base_name_without_couple(multi_level)
      name = multi_level.name
      # Remove any " - Pro-Am", " - Amateur Couple", etc. suffix
      name.sub(/ - (Pro-Am|Amateur Couple|Amateur Lead|Amateur Follow)$/, '')
    end

    # Calculate next negative order for split dances
    def next_negative_order
      [Dance.minimum(:order), 0].min - 1
    end

    # Create a split dance (copy of original with negative order)
    def create_split_dance(original_dance)
      Dance.create!(
        name: original_dance.name,
        order: next_negative_order,
        heat_length: original_dance.heat_length,
        semi_finals: original_dance.semi_finals,
        open_category_id: original_dance.open_category_id,
        closed_category_id: original_dance.closed_category_id,
        solo_category_id: original_dance.solo_category_id,
        multi_category_id: original_dance.multi_category_id,
        pro_open_category_id: original_dance.pro_open_category_id,
        pro_closed_category_id: original_dance.pro_closed_category_id,
        pro_solo_category_id: original_dance.pro_solo_category_id,
        pro_multi_category_id: original_dance.pro_multi_category_id
      )
    end

    # Copy multi_children from one dance to another
    def copy_multi_children(from_dance, to_dance)
      from_dance.multi_children.each do |child|
        Multi.create!(parent_id: to_dance.id, dance_id: child.dance_id)
      end
    end

    # Create a split dance with multi_children copied
    def create_split_dance_with_children(original_dance)
      new_dance = create_split_dance(original_dance)
      copy_multi_children(original_dance, new_dance)
      new_dance
    end

    # Check if we're back to a single multi_level and clean up if so
    def cleanup_if_single_remaining(all_dances, check_age_range: false)
      remaining_multi_levels = MultiLevel.where(dance: all_dances).to_a

      if remaining_multi_levels.length == 1
        remaining = remaining_multi_levels.first

        # If check_age_range is true, only cleanup if age range is nil
        if !check_age_range || (remaining.start_age.nil? && remaining.stop_age.nil?)
          remaining.destroy!
          all_dances.where(order: ...0).destroy_all
          return true
        end
      end
      false
    end

    # Group heats by couple type based on split type
    def group_heats_by_couple_type(heats, couple_split_type)
      heats_by_type = {}
      heats.each do |heat|
        ct = determine_couple_type(heat.entry)
        mapped_type = case ct
        when 'Amateur Lead'
          couple_split_type == 'amateur_lead_follow' ? 'Amateur Lead' : 'Pro-Am'
        when 'Amateur Follow'
          couple_split_type == 'amateur_lead_follow' ? 'Amateur Follow' : 'Pro-Am'
        when 'Amateur Couple'
          'Amateur Couple'
        else
          'Pro-Am'
        end
        heats_by_type[mapped_type] ||= []
        heats_by_type[mapped_type] << heat
      end
      heats_by_type
    end

    # Get split couple types based on split type parameter
    def split_couple_types_for(couple_split_type)
      case couple_split_type
      when 'pro_am_vs_amateur'
        ['Pro-Am', 'Amateur Couple']
      when 'amateur_lead_follow'
        ['Amateur Lead', 'Amateur Follow', 'Amateur Couple']
      end
    end

    # Determine the couple type for an entry
    # Returns: 'Professional', 'Amateur Lead', 'Amateur Follow', or 'Amateur Couple'
    # - Professional = Pro + Pro
    # - Amateur Lead = Pro-Am where the student is the lead
    # - Amateur Follow = Pro-Am where the student is the follow
    # - Amateur Couple = Student + Student
    def determine_couple_type(entry)
      lead_type = entry.lead.type
      follow_type = entry.follow.type

      if lead_type == 'Professional' && follow_type == 'Professional'
        'Professional'
      elsif lead_type == 'Student' && follow_type == 'Professional'
        # Student leading, Pro following = Amateur Lead
        'Amateur Lead'
      elsif lead_type == 'Professional' && follow_type == 'Student'
        # Pro leading, Student following = Amateur Follow
        'Amateur Follow'
      elsif lead_type == 'Student' && follow_type == 'Student'
        'Amateur Couple'
      else
        'Amateur Couple'
      end
    end

    # Check if an entry matches a multi_level's criteria
    def entry_matches_multi_level?(entry, ml)
      # Check level range
      return false unless entry.level_id >= ml.start_level && entry.level_id <= ml.stop_level

      # Check age range if specified
      if ml.start_age.present? && ml.stop_age.present?
        return false unless entry.age_id >= ml.start_age && entry.age_id <= ml.stop_age
      end

      # Check couple type if specified
      if ml.couple_type.present?
        entry_couple_type = determine_couple_type(entry)
        case ml.couple_type
        when 'Pro-Am'
          # Pro-Am matches both Amateur Lead and Amateur Follow
          return false unless ['Amateur Lead', 'Amateur Follow'].include?(entry_couple_type)
        when 'Amateur Couple'
          return false unless entry_couple_type == 'Amateur Couple'
        when 'Amateur Lead'
          return false unless entry_couple_type == 'Amateur Lead'
        when 'Amateur Follow'
          return false unless entry_couple_type == 'Amateur Follow'
        end
      end

      true
    end

    #
    # LEVEL SPLIT METHODS
    #

    # Initial level split when no multi_levels exist yet
    def perform_initial_split(dance_id, split_level)
      original_dance = Dance.find(dance_id)

      # Get level range from heats
      heats = Heat.where(dance_id: dance_id).includes(entry: :level)
      level_ids = heats.map { |h| h.entry.level_id }.uniq.sort
      min_level = level_ids.min
      max_level = level_ids.max

      return if split_level >= max_level # No split needed

      # Create new dance with multi_children
      new_dance = create_split_dance_with_children(original_dance)

      # Create first multi_level
      MultiLevel.create!(
        name: format_level_name_from_ids(min_level, split_level),
        dance: original_dance,
        start_level: min_level,
        stop_level: split_level
      )

      # Create second multi_level
      MultiLevel.create!(
        name: format_level_name_from_ids(split_level + 1, max_level),
        dance: new_dance,
        start_level: split_level + 1,
        stop_level: max_level
      )

      # Move heats to new dance
      heats.each do |heat|
        if heat.entry.level_id > split_level
          heat.update!(dance_id: new_dance.id)
        end
      end
    end

    # Update an existing level split (shrink or expand)
    def perform_update_split(multi_level_id, new_stop)
      multi_level = MultiLevel.find(multi_level_id)
      old_stop = multi_level.stop_level
      dance = multi_level.dance
      all_levels = Level.order(:id).all

      # Get all multi_levels for this dance set (same name)
      all_dances = Dance.where(name: dance.name)
      all_multi_levels = MultiLevel.where(dance: all_dances).order(:start_level).to_a

      current_index = all_multi_levels.index(multi_level)

      if new_stop < old_stop
        # Shrinking this range - need to handle heats and possibly create new split
        handle_shrink(multi_level, new_stop, old_stop, all_multi_levels, current_index, all_levels)
      elsif new_stop > old_stop
        # Expanding this range - adjust next multi_level
        handle_expand(multi_level, new_stop, old_stop, all_multi_levels, current_index, all_levels)
      end
    end

    def handle_shrink(multi_level, new_stop, old_stop, all_multi_levels, current_index, all_levels)
      # Update this multi_level
      multi_level.update!(stop_level: new_stop)
      multi_level.update!(name: format_level_name_from_ids(multi_level.start_level, new_stop))

      # Check if there's a next multi_level
      if current_index < all_multi_levels.length - 1
        next_multi = all_multi_levels[current_index + 1]

        # Adjust next multi_level's start
        next_multi.update!(start_level: new_stop + 1)
        next_multi.update!(name: format_level_name_from_ids(new_stop + 1, next_multi.stop_level))

        # Move heats from current dance to next dance if they're outside the new range
        Heat.where(dance: multi_level.dance).includes(entry: :level).each do |heat|
          if heat.entry.level_id > new_stop
            heat.update!(dance_id: next_multi.dance_id)
          end
        end
      else
        # This is the last multi_level, need to create a new one
        original_dance = Dance.find_by(name: multi_level.dance.name, order: 0..)
        new_dance = create_split_dance_with_children(original_dance)

        # Create new multi_level
        MultiLevel.create!(
          name: format_level_name_from_ids(new_stop + 1, old_stop),
          dance: new_dance,
          start_level: new_stop + 1,
          stop_level: old_stop
        )

        # Move heats
        Heat.where(dance: multi_level.dance).includes(entry: :level).each do |heat|
          if heat.entry.level_id > new_stop
            heat.update!(dance_id: new_dance.id)
          end
        end
      end
    end

    def handle_expand(multi_level, new_stop, old_stop, all_multi_levels, current_index, all_levels)
      # Update this multi_level
      multi_level.update!(stop_level: new_stop)
      multi_level.update!(name: format_level_name_from_ids(multi_level.start_level, new_stop))

      # Process all subsequent multi_levels that fall within the new range
      (current_index + 1...all_multi_levels.length).each do |idx|
        next_multi = all_multi_levels[idx]

        # Move heats from next dance to current dance if they fall within new stop level
        Heat.where(dance: next_multi.dance).includes(entry: :level).each do |heat|
          if heat.entry.level_id <= new_stop
            heat.update!(dance_id: multi_level.dance_id)
          end
        end

        # If this multi_level is completely subsumed by the expansion
        if next_multi.stop_level <= new_stop
          # Delete this multi_level and its dance if it has negative order
          next_dance = next_multi.dance
          next_multi.destroy!
          next_dance.destroy! if next_dance.order < 0
        elsif next_multi.start_level <= new_stop
          # This multi_level is partially subsumed - adjust its start
          next_multi.update!(start_level: new_stop + 1)
          next_multi.update!(name: format_level_name_from_ids(next_multi.start_level, next_multi.stop_level))

          # Stop processing - we've adjusted the adjacent split
          break
        else
          # This multi_level is completely beyond the new stop - stop processing
          break
        end
      end

      # Check if we're back to a single multi_level
      all_dances = Dance.where(name: multi_level.dance.name)
      cleanup_if_single_remaining(all_dances)
    end

    #
    # AGE SPLIT METHODS
    #

    # Initial age split when no multi_levels exist yet
    def perform_initial_age_split(dance_id, split_age)
      original_dance = Dance.find(dance_id)
      all_ages = Age.order(:id).all

      # Get heats and determine ranges
      heats = Heat.where(dance_id: dance_id).includes(entry: [:level, :age])
      age_ids = heats.map { |h| h.entry.age_id }.uniq.sort
      level_ids = heats.map { |h| h.entry.level_id }.uniq.sort

      return if age_ids.empty?

      min_age = age_ids.min
      max_age = age_ids.max
      min_level = level_ids.min
      max_level = level_ids.max

      return if split_age >= max_age # No split needed

      # Create new dance with multi_children
      new_dance = create_split_dance_with_children(original_dance)

      # Create first multi_level (for ages up to split_age)
      first_age = all_ages.find { |a| a.id == min_age }
      split_age_obj = all_ages.find { |a| a.id == split_age }
      level_name = format_level_name_from_ids(min_level, max_level)
      age_name = format_age_range_name(first_age, split_age_obj)

      MultiLevel.create!(
        name: "#{level_name} #{age_name}",
        dance: original_dance,
        start_level: min_level,
        stop_level: max_level,
        start_age: min_age,
        stop_age: split_age
      )

      # Create second multi_level (for ages after split_age)
      next_age = all_ages.find { |a| a.id == split_age + 1 }
      last_age = all_ages.find { |a| a.id == max_age }
      age_name2 = format_age_range_name(next_age, last_age)

      MultiLevel.create!(
        name: "#{level_name} #{age_name2}",
        dance: new_dance,
        start_level: min_level,
        stop_level: max_level,
        start_age: split_age + 1,
        stop_age: max_age
      )

      # Move heats to new dance
      heats.each do |heat|
        if heat.entry.age_id > split_age
          heat.update!(dance_id: new_dance.id)
        end
      end
    end

    # Update an existing age split (shrink or expand)
    def perform_age_split(multi_level_id, new_stop_age)
      multi_level = MultiLevel.find(multi_level_id)
      dance = multi_level.dance
      all_ages = Age.order(:id).all

      # Get all multi_levels in this level group
      all_dances = Dance.where(name: dance.name)
      level_siblings = MultiLevel.where(dance: all_dances)
        .where(start_level: multi_level.start_level, stop_level: multi_level.stop_level)
        .order(:start_age).to_a

      # Get heats for this level range across all dances
      level_heats = Heat.where(dance: all_dances).includes(entry: [:level, :age])
        .select { |h| h.entry.level_id >= multi_level.start_level && h.entry.level_id <= multi_level.stop_level }

      age_ids = level_heats.map { |h| h.entry.age_id }.uniq.sort
      return if age_ids.empty?

      min_age = multi_level.start_age || age_ids.min
      old_stop_age = multi_level.stop_age || age_ids.max

      # No change needed
      return if new_stop_age == old_stop_age

      original_dance = Dance.find_by(name: dance.name, order: 0..) || dance

      if new_stop_age < old_stop_age
        # Shrinking - create a new split for the remaining ages
        handle_age_shrink(multi_level, new_stop_age, old_stop_age, min_age, level_siblings, all_ages, original_dance, dance)
      else
        # Expanding - consume later age splits
        handle_age_expand(multi_level, new_stop_age, old_stop_age, min_age, level_siblings, all_ages, all_dances)
      end
    end

    def handle_age_shrink(multi_level, new_stop_age, old_stop_age, min_age, level_siblings, all_ages, original_dance, dance)
      current_index = level_siblings.index(multi_level)

      # Update this multi_level (must set both start_age and stop_age together for validation)
      multi_level.update!(start_age: min_age, stop_age: new_stop_age)
      first_age = all_ages.find { |a| a.id == min_age }
      new_stop_age_obj = all_ages.find { |a| a.id == new_stop_age }
      multi_level.update!(name: format_split_name(multi_level, first_age, new_stop_age_obj, :age))

      # Check if there's a next sibling in this level group
      if current_index && current_index < level_siblings.length - 1
        next_sibling = level_siblings[current_index + 1]

        # Adjust next sibling's start_age
        next_sibling.update!(start_age: new_stop_age + 1)
        next_start_age = all_ages.find { |a| a.id == new_stop_age + 1 }
        next_stop_age_obj = all_ages.find { |a| a.id == next_sibling.stop_age }
        next_sibling.update!(name: format_split_name(next_sibling, next_start_age, next_stop_age_obj, :age))

        # Move heats from current dance to next dance
        Heat.where(dance: dance).includes(entry: [:level, :age]).each do |heat|
          if heat.entry.level_id >= multi_level.start_level &&
             heat.entry.level_id <= multi_level.stop_level &&
             heat.entry.age_id > new_stop_age
            heat.update!(dance_id: next_sibling.dance_id)
          end
        end
      else
        # This is the last sibling, need to create a new one
        new_dance = create_split_dance_with_children(original_dance)

        next_age = all_ages.find { |a| a.id == new_stop_age + 1 }
        last_age = all_ages.find { |a| a.id == old_stop_age }
        MultiLevel.create!(
          name: format_split_name(multi_level, next_age, last_age, :age),
          dance: new_dance,
          start_level: multi_level.start_level,
          stop_level: multi_level.stop_level,
          start_age: new_stop_age + 1,
          stop_age: old_stop_age,
          couple_type: multi_level.couple_type
        )

        # Move heats to new dance
        Heat.where(dance: dance).includes(entry: [:level, :age]).each do |heat|
          if heat.entry.level_id >= multi_level.start_level &&
             heat.entry.level_id <= multi_level.stop_level &&
             heat.entry.age_id > new_stop_age
            heat.update!(dance_id: new_dance.id)
          end
        end
      end
    end

    def handle_age_expand(multi_level, new_stop_age, old_stop_age, min_age, level_siblings, all_ages, all_dances)
      current_index = level_siblings.index(multi_level)
      return unless current_index

      # Update this multi_level's age range (must set both start_age and stop_age together for validation)
      multi_level.update!(start_age: min_age, stop_age: new_stop_age)
      first_age = all_ages.find { |a| a.id == min_age }
      new_stop_age_obj = all_ages.find { |a| a.id == new_stop_age }
      multi_level.update!(name: format_split_name(multi_level, first_age, new_stop_age_obj, :age))

      # Process subsequent siblings that fall within the new range
      (current_index + 1...level_siblings.length).each do |idx|
        next_sibling = level_siblings[idx]

        # Move heats from next sibling's dance to current dance if they fall within new stop age
        Heat.where(dance: next_sibling.dance).includes(entry: [:level, :age]).each do |heat|
          if heat.entry.level_id >= multi_level.start_level &&
             heat.entry.level_id <= multi_level.stop_level &&
             heat.entry.age_id <= new_stop_age
            heat.update!(dance_id: multi_level.dance_id)
          end
        end

        if next_sibling.stop_age <= new_stop_age
          # This sibling is completely consumed - delete it
          next_dance = next_sibling.dance
          next_sibling.destroy!
          next_dance.destroy! if next_dance.order < 0
        elsif next_sibling.start_age <= new_stop_age
          # Partially consumed - adjust start_age
          next_sibling.update!(start_age: new_stop_age + 1)
          next_start_age = all_ages.find { |a| a.id == next_sibling.start_age }
          next_stop_age_obj = all_ages.find { |a| a.id == next_sibling.stop_age }
          next_sibling.update!(name: format_split_name(next_sibling, next_start_age, next_stop_age_obj, :age))
          break
        else
          # Beyond the new range - stop processing
          break
        end
      end

      # Check if we're back to a single age split in this level group
      remaining_siblings = MultiLevel.where(dance: all_dances)
        .where(start_level: multi_level.start_level, stop_level: multi_level.stop_level).to_a

      if remaining_siblings.length == 1
        # Remove age range to indicate no age split
        remaining = remaining_siblings.first
        remaining.update!(start_age: nil, stop_age: nil)
        remaining.update!(name: format_level_name_from_ids(remaining.start_level, remaining.stop_level))

        # Check if we're back to a single multi_level overall
        cleanup_if_single_remaining(all_dances)
      end
    end

    #
    # COUPLE TYPE SPLIT METHODS
    #

    # Initial couple split when no multi_levels exist yet
    def perform_initial_couple_split(dance_id, couple_split_type)
      original_dance = Dance.find(dance_id)

      # Get heats and determine ranges
      heats = Heat.where(dance_id: dance_id).includes(entry: [:lead, :follow, :level, :age])
      level_ids = heats.map { |h| h.entry.level_id }.uniq.sort

      return if heats.empty?

      min_level = level_ids.min
      max_level = level_ids.max

      split_couple_types = split_couple_types_for(couple_split_type)
      return unless split_couple_types

      heats_by_type = group_heats_by_couple_type(heats, couple_split_type)

      # Only proceed if we have heats in multiple categories
      return if heats_by_type.keys.length < 2

      level_name = format_level_name_from_ids(min_level, max_level)

      # Create multi_level for first type that has heats
      first_type = split_couple_types.find { |t| heats_by_type[t]&.any? }
      return unless first_type

      MultiLevel.create!(
        name: "#{level_name} - #{first_type}",
        dance: original_dance,
        start_level: min_level,
        stop_level: max_level,
        couple_type: first_type
      )

      # Create multi_levels and dances for other types
      split_couple_types.each do |ct|
        next if ct == first_type
        next unless heats_by_type[ct]&.any?

        new_dance = create_split_dance_with_children(original_dance)

        MultiLevel.create!(
          name: "#{level_name} - #{ct}",
          dance: new_dance,
          start_level: min_level,
          stop_level: max_level,
          couple_type: ct
        )

        # Move heats to new dance
        heats_by_type[ct].each do |heat|
          heat.update!(dance_id: new_dance.id)
        end
      end
    end

    # Split by couple type within an existing multi_level
    def perform_couple_split(multi_level_id, couple_split_type)
      multi_level = MultiLevel.find(multi_level_id)
      dance = multi_level.dance

      # Get heats for this dance that match this multi_level's criteria
      heats = Heat.where(dance: dance).includes(entry: [:lead, :follow, :level, :age])
        .select { |h| entry_matches_multi_level?(h.entry, multi_level) }

      return if heats.empty?

      split_couple_types = split_couple_types_for(couple_split_type)
      return unless split_couple_types

      original_dance = Dance.find_by(name: dance.name, order: 0..) || dance
      heats_by_type = group_heats_by_couple_type(heats, couple_split_type)

      # Only proceed if we have heats in multiple categories
      return if heats_by_type.keys.length < 2

      # Update current multi_level with first couple type that has heats
      first_type = split_couple_types.find { |t| heats_by_type[t]&.any? }
      return unless first_type

      multi_level.update!(
        couple_type: first_type,
        name: "#{multi_level.name} - #{first_type}"
      )

      # Create new multi_levels and dances for other couple types
      split_couple_types.each do |ct|
        next if ct == first_type  # Skip the first type (already assigned to current multi_level)
        next unless heats_by_type[ct]&.any?

        new_dance = create_split_dance_with_children(original_dance)

        MultiLevel.create!(
          name: "#{base_name_without_couple(multi_level)} - #{ct}",
          dance: new_dance,
          start_level: multi_level.start_level,
          stop_level: multi_level.stop_level,
          start_age: multi_level.start_age,
          stop_age: multi_level.stop_age,
          couple_type: ct
        )

        # Move heats to new dance
        heats_by_type[ct].each do |heat|
          heat.update!(dance_id: new_dance.id)
        end
      end
    end

    # Collapse couple type splits back to a single group
    def perform_couple_collapse(multi_level_id)
      multi_level = MultiLevel.find(multi_level_id)
      dance = multi_level.dance

      # Get all dances with the same name
      all_dances = Dance.where(name: dance.name)

      # Get all siblings with same level/age ranges but different couple types
      siblings = MultiLevel.where(dance: all_dances)
        .where(start_level: multi_level.start_level, stop_level: multi_level.stop_level)
        .where(start_age: multi_level.start_age, stop_age: multi_level.stop_age)
        .where.not(couple_type: nil)
        .to_a

      return if siblings.empty?

      # Move all heats from sibling dances to this dance
      siblings.each do |sibling|
        next if sibling == multi_level  # Skip self
        Heat.where(dance: sibling.dance).update_all(dance_id: multi_level.dance_id)

        # Delete the sibling's dance if it has negative order
        sibling_dance = sibling.dance
        sibling.destroy!
        sibling_dance.destroy! if sibling_dance.order < 0
      end

      # Remove couple_type from the remaining multi_level and update name
      multi_level.update!(couple_type: nil)
      multi_level.update!(name: base_name_without_couple(multi_level))

      # Check if we're back to a single multi_level overall
      cleanup_if_single_remaining(all_dances, check_age_range: true)
    end
end
