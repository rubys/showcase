module HeatScheduler
  include Printable

  def build_true_order
    true_order = {}
    dance_orders = Dance.all.group_by(&:name).map {|name, list| [name, list.map(&:order)]}
    dance_orders.each do |name, orders|
      max = orders.max

      # Check if this dance has multi-level splits
      dances_with_name = Dance.where(name: name, order: orders)
      has_splits = dances_with_name.any? { |d| d.multi_children.any? && MultiLevel.where(dance: dances_with_name).exists? }

      if has_splits
        # Assign fractional orders to keep splits sorted together but separated during grouping
        sorted_orders = orders.sort.reverse
        sorted_orders.each_with_index do |order, index|
          true_order[order] = max + (index * 0.001)
        end
      else
        # Original behavior for non-split dances
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
      
      if heat.dance.semi_finals
        # don't split semi-finals by level, age
        [
          order,
          category,
          availability,
          1,
          1,
          heat
        ]
      else
        [
          order,
          category,
          availability,
          heat.entry.level_id,
          heat.entry.age_id,
          heat
        ]
      end
    }

    heats = Group.sort(heats)

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

    ActiveRecord::Base.transaction do
      groups.each_with_index do |group, index|
        group.each do |heat|
          heat.number = index + 1
          heat.save validate: false
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

    @heats = @heats.
      group_by {|heat| heat.number}.map do |number, heats|
        [number, heats.sort_by { |heat| heat.back || 0 } ]
      end.sort
  end

  def rebalance(assignments, subgroups, max)
    return if subgroups.first.dance&.semi_finals
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
    cats = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h
    solos = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h
    multis = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h

    groups.each do |group|
      dcat = group.dcat
      heat = group.first
      next unless heat

      if heat&.solo&.category_override_id
        solos[heat.solo.category_override] << group
      elsif dcat == 'Open'
        cats[group.dance.open_category] << group
      elsif dcat == 'Closed'
        cats[group.dance.closed_category] << group
      elsif dcat == 'Solo'
        solos[group.dance.solo_category] << group
      elsif dcat == 'Multi'
        multis[group.dance.multi_category] << group
      elsif dcat == 'Pro Open'
        cats[group.dance.pro_open_category] << group
      elsif dcat == 'Pro Closed'
        cats[group.dance.pro_closed_category] << group
      elsif dcat == 'Pro Solo'
        solos[group.dance.pro_solo_category] << group
      elsif dcat == 'Pro Multi'
        multis[group.dance.pro_multi_category] << group
      else
        cats[group.override || group.dance.closed_category] << group
      end
    end

    new_order = []
    agenda = {}

    true_order = build_true_order

    cats.each do |cat, groups|
      if Event.current.intermix
        dances = groups.group_by {|group| [group.dcat, true_order[group.dance.order]]}
        candidates = []

        max = dances.values.map(&:length).max || 1
        offset = 0.5/(max + 1)

        dances.each do |id, groups|
          denominator = groups.length.to_f + 1
          groups.each_with_index do |group, index|
            slot = (((index+1.0)/denominator - offset)/offset/2).to_i
            candidates << [slot] + id + [group]
          end
        end

        groups = candidates.sort_by {|candidate| candidate[0..2]}.map(&:last)
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

  class Group
    def self.set_knobs
      @@event = Event.current
      @@category = @@event.heat_range_cat
      @@level = @@event.heat_range_level
      @@age = @@event.heat_range_age
      @@max = @@event.max_heat_size || 9999
      @@skating = Dance.where(semi_finals: true).pluck(:id)

      # only combine open/closed dances if the category is the same
      @@combinable = @@category == 0 ? [] :
        Dance.all.select {|dance| dance.open_category && dance.open_category_id == dance.closed_category_id}.map(&:id)
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

    def initialize(list = [])
      @group = list
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
      end

      unless @@skating.include? heat.dance_id
        return if @group.size >= @@max
        return if @participants.include? heat.lead
        return if @participants.include? heat.follow
        return if heat.lead.exclude_id and @participants.include? heat.lead.exclude
        return if heat.follow.exclude_id and @participants.include? heat.follow.exclude
      end

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
      entry = Entry.where(follow_id: 8, lead_id: 36).first
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
      base = Dance.where(name: dance.name, order: 1...).first

      if base
        Heats.where(id: dance.heats.pluck(:id).update_all(dance_id base.id))
      else
        dance.update(order: Dance.maximum(:order) + 1)
      end
    end

    closed_orphans = Dance.joins(:closed_category).where(order: ...0, closed_category: {routines: false})
    closed_orphans.each do |dance|
      base = Dance.where(name: dance.name, order: 1...).first

      if base
        Heats.where(id: dance.heats.pluck(:id).update_all(dance_id base.id))
      else
        dance.update(order: Dance.maximum(:order) + 1)
      end
    end
  end
end
