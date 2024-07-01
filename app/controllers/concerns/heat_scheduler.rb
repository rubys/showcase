module HeatScheduler
  include Printable

  def schedule_heats
    event = Event.last

    Group.set_knobs

    # reset judge assignments
    Score.where(value: nil, comments: nil, good: nil, bad: nil).delete_all

    # remove all scratches and orphaned entries
    Heat.where(number: ...0).each {|heat| heat.destroy}
    Entry.includes(:heats).where(heats: {id: nil}).each {|entry| entry.destroy}

    # extract heats
    @heats = Heat.eager_load(
      :solo,
      dance: [:open_category, :closed_category, :solo_category, :multi_category],
      entry: [{lead: :studio}, {follow: :studio}]
    )

    # convert relevant data to numbers
    heat_categories = {'Closed' => 0, 'Open' => 1, 'Solo' => 2, 'Multi' => 3}
    routines = Category.where(routines: true).all.zip(4..).map {|cat, num| [cat.id, num]}.to_h

    heats = @heats.map {|heat|
      if heat.solo&.category_override_id and routines[heat.solo.category_override_id]
        category = routines[heat.solo.category_override_id]
        order = 1000 + heat.solo.order
      else
        category = heat_categories[heat.category]
        category += 4 if heat.entry.pro
        order = heat.dance.order
      end

      if heat.dance.semi_finals
        # don't split semi-finals by level, age
        [
          order,
          category,
          1,
          1,
          heat
        ]
      else
        [
          order,
          category,
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

    if event.heat_range_level == 0 && ENV['RAILS_APP_DB'] == '2024-lakeview-graduation-nights'
      i = 0
      groups.sort_by! {|group| [group.first.entry.level_id, i += 1]}
    end

    ActiveRecord::Base.transaction do
      groups.each_with_index do |group, index|
        group.each do |heat|
          heat.number = index + 1
          heat.save validate: false
        end
      end
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
    categories = Category.order(:order).all
    cats = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h
    solos = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h
    multis = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h

    groups.each do |group|
      dcat = group.dcat
      next unless group.first

      if dcat == 'Open'
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

    cats.each do |cat, groups|
      if Event.last.intermix
        dances = groups.group_by {|group| [group.dcat, group.dance.order]}
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
        if cat.heats and groups.length > cat.heats
          extensions_needed = 1 # (groups.length.to_f / cat.heats).ceil - 1
        else
          extensions_needed = 0
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
          agenda[extensions_found.first] = groups[cat.heats..]
          groups = groups[..cat.heats-1]
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
      @@event = Event.last
      @@category = @@event.heat_range_cat
      @@level = @@event.heat_range_level
      @@age = @@event.heat_range_age
      @@max = @@event.max_heat_size || 9999

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

    def match?(dance, dcat, level, age, heat)
      return false unless @dance == dance
      return false unless @dcat == dcat or @@combinable.include? dance
      return false if heat.category == 'Solo'
      return true
    end

    def add?(dance, dcat, level, age, heat)
      if @group.length == 0
        @participants = Set.new

        @max_dcat = @min_dcat = dcat
        @max_level = @min_level = level
        @max_age = @min_age = age

        @dance = dance
        @dcat = dcat
      end

      return if @group.size >= @@max
      return if @participants.include? heat.lead
      return if @participants.include? heat.follow
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

    def remove(dance, dcat, level, age, heat)
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

end
