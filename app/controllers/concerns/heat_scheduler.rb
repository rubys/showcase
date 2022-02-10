module HeatScheduler
  def schedule_heats
    Group.set_knobs

    # extract heats
    @heats = Heat.eager_load(
      :dance, {entry: [{lead: :studio}, {follow: :studio}]}
    )

    # convert relevant data to numbers
    heat_categories = {'Closed' => 0, 'Open' => 1}

    heats = @heats.map {|heat|
      [heat.dance_id,
       heat_categories[heat.category],
       heat.entry.level_id,
       heat.entry.age_id,
       heat
      ]}

    heats = Group.sort(heats)

    # convert relevant data to numbers
    groups = []
    assignments = {}
    subgroups = []
    lastgroup = nil
    while not heats.empty?
      if lastgroup and not lastgroup.match? *heats.first
        rebalance(assignments, subgroups) unless subgroups.empty?

        assignments = {}
        subgroups = []
      end

      group = Group.new(*heats.shift)

      subgroups.unshift group

      for entry in heats.dup
        if group.add? *entry
          heats.delete entry
          assignments[entry] = group
        elsif not group.match? *entry
          break
        end
      end

      groups << group
      lastgroup = group
    end

    rebalance(assignments, subgroups) unless subgroups.empty?

    groups = reorder(groups)

    ActiveRecord::Base.transaction do
      groups.each_with_index do |group, index|
        group.each do |heat|
          heat.number = index + 1
          heat.save!
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
        [number, heats.sort_by { |heat| heat.back } ]
      end.sort
  end

  def rebalance(assignments, subgroups)
    ceiling = (assignments.length.to_f / subgroups.length).ceil + 1

    assignments.to_a.reverse.each do |(entry, source)|
      subgroups.each do |target|
        break if target == source
        next if target.size >= ceiling
        next if target.size >= source.size - 1

        if target.add? *entry
          source.remove *entry
          break
        end
      end
    end
  end

  def reorder(groups)
    cats = (Category.all.map {|cat| [cat, []]} + [[nil, []]]).to_h

    groups.each do |group|
      if group.dcat == 'Open'
        cats[group.dance.open_category] << group
      else
        cats[group.dance.closed_category] << group
      end
    end

    new_order = []
    cats.each do |cat, groups|
      dances = groups.group_by {|group| [group.dcat, group.dance.id]}
      candidates = []

      dances.each do |id, groups|
        denominator = groups.length.to_f + 1
        groups.each_with_index do |group, index|
          candidates << [(index+1)/denominator] + id + [group]
        end
      end

      new_order += candidates.sort_by {|candidate| candidate[0..2]}.map(&:last)
    end

    new_order
  end

  class Group
    def self.set_knobs
      event = Event.last
      @@category = event.heat_range_cat
      @@level = event.heat_range_level
      @@age = event.heat_range_age
    end

    def self.sort(heats)
      if @@category == 0
        heats.sort_by {|heat| heat[0..1].reverse + heat[2..-1]}
      else
        heats.sort
      end
    end

    def dance
      @group.first.dance
    end

    def dcat
      @min_dcat == 0 ? 'Closed' : 'Open'
    end

    def initialize(dance, dcat, level, age, heat)
      @participants = Set.new
      @participants.add heat.lead
      @participants.add heat.follow

      @max_dcat = @min_dcat = dcat
      @max_level = @min_level = level
      @max_age = @min_age = age
      
      @group = [heat]
      @dance = dance
      @dcat = dcat
    end

    def match?(dance, dcat, level, age, heat)
      return false unless @dance == dance
      return false unless @dcat == dcat or @@category > 0
      return true
    end

    def add?(dance, dcat, level, age, heat)
      return if @participants.include? heat.lead
      return if @participants.include? heat.follow

      return false unless @dance == dance
      return false unless (dcat-@max_dcat).abs <= @@category
      return false unless (dcat-@min_dcat).abs <= @@category
      return false unless (level-@max_level).abs <= @@level
      return false unless (level-@min_level).abs <= @@level
      return false unless (age-@max_age).abs <= @@age
      return false unless (age-@min_age).abs <= @@age

      @participants.add heat.lead
      @participants.add heat.follow

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

    def size
      @group.size
    end
  end
end
