module HeatScheduler
  include Printable
  
  def schedule_heats
    Group.set_knobs

    # remove all scratches and orphaned entries
    Heat.where(number: ...0).each {|heat| heat.destroy}
    Entry.includes(:heats).where(heats: {id: nil}).each {|entry| entry.destroy}

    # extract heats
    @heats = Heat.eager_load(
      dance: [:open_category, :closed_category, :solo_category, :multi_category],
      entry: [{lead: :studio}, {follow: :studio}]
    )

    # convert relevant data to numbers
    heat_categories = {'Closed' => 0, 'Open' => 1, 'Solo' => 2, 'Multi' => 3}

    heats = @heats.map {|heat|
      [heat.dance_id,
       heat_categories[heat.category],
       heat.entry.level_id,
       heat.entry.age_id,
       heat
      ]}

    heats = Group.sort(heats)

    max = Event.last.max_heat_size || 9999

    # group entries into heats
    groups = []
    while not heats.empty?
      Group.max = 9999

      assignments = {}
      subgroups = []

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

      Group.max = max
      assignments = assignments.map {|index, group| [heats[index], group]}
      rebalance(assignments, subgroups, max)

      heats.shift assignments.length
      groups += subgroups.reverse
    end

    groups = reorder(groups)

    ActiveRecord::Base.transaction do
      groups.each_with_index do |group, index|
        group.each do |heat|
          heat.number = index + 1
          heat.save
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
    while subgroups.length * max < assignments.length
      subgroups.unshift Group.new
    end

    ceiling = (assignments.length.to_f / subgroups.length).ceil

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
    categories = Category.order(:order).all
    cats = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h
    solos = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h
    multis = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h

    groups.each do |group|
      if group.dcat == 'Open'
        cats[group.dance.open_category] << group
      elsif group.dcat == 'Solo'
        solos[group.dance.solo_category] << group
      elsif group.dcat == 'Multi'
        multis[group.dance.multi_category] << group
      else
        cats[group.dance.closed_category] << group
      end
    end

    new_order = []

    if Event.last.intermix
      cats.each do |cat, groups|
        dances = groups.group_by {|group| [group.dcat, group.dance.id]}
        candidates = []

        dances.each do |id, groups|
          denominator = groups.length.to_f + 1
          groups.each_with_index do |group, index|
            candidates << [(index+1)/denominator] + id + [group]
          end
        end

        new_order += candidates.sort_by {|candidate| candidate[0..2]}.map(&:last) +
          solos[cat].sort_by {|group| group.first.solo.order} +
          multis[cat]
      end
    else
      cats.each do |cat, groups|
        new_order += groups +
          solos[cat].sort_by {|group| group.first.solo.order} +
          multis[cat]
      end
    end

    new_order
  end

  class Group
    def self.set_knobs
      event = Event.last
      @@category = event.heat_range_cat
      @@level = event.heat_range_level
      @@age = event.heat_range_age
      @@max = event.max_heat_size || 9999
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
      @group.first.dance
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
      else
        '?'
      end
    end

    def initialize
      @group = []
    end

    def match?(dance, dcat, level, age, heat)
      return false unless @dance == dance
      return false unless @dcat == dcat or @@category > 0
      return false if dcat == 2 # Solo
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

      return false unless @dance == dance
      return false if dcat == 2 and @group.length > 0 # Solo
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

    def first
      @group.first
    end

    def size
      @group.size
    end
  end
end
