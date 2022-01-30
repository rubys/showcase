module HeatScheduler
  def schedule_heats
    Group.set_knobs(params)

    # extract heats
    @heats = Heat.eager_load({
      entry: [:dance, {lead: :studio}, {follow: :studio}]
    })

    # convert relevant data to numbers
    heat_categories = {'Closed' => 0, 'Open' => 1}

    subject_categories = Person.distinct.pluck(:category).compact.sort.
      each_with_index.to_h

    levels = Person.distinct.pluck(:level).compact.map {|level| 
      rank = 0
      rank += 1 if level.include? 'Bronze'
      rank += 3 if level.include? 'Silver'
      rank += 5 if level.include? 'Gold'
      rank += 1 if level.include? 'Full'
      [rank, level]
    }.sort.to_h.invert

    heats = @heats.map {|heat|
      [heat.entry.dance_id,
       heat_categories[heat.category],
       levels[heat.level],
       subject_categories[heat.entry.subject_category.split(' ').last],
       heat
      ]}.sort

    # convert relevant data to numbers
    groups = []
    while not heats.empty?
      group = Group.new(*heats.shift)

      assignment = []
      for entry in heats
        break unless entry[0] == group.dance

        if group.add? *entry
          heats.delete entry
        end
      end

      groups << group
    end

    groups.each_with_index do |group, index|
      group.each do |heat|
        heat.number = index + 1
      end
    end

    @heats = @heats.
      group_by {|heat| heat.number}.map do |number, heats|
        [number, heats.sort_by { |heat| heat.back } ]
      end.sort
  end

  class Group
    def self.set_knobs(params)
      @@category = params[:category].to_i
      @@level = params[:level].to_i
      @@age = params[:age].to_i
    end

    attr_reader :dance

    def initialize(dance, dcat, level, age, heat)
      @participants = Set.new
      @participants.add heat.lead
      @participants.add heat.follow

      @max_dcat = @min_dcat = dcat
      @max_level = @min_level = level
      @max_age = @min_age = age
      
      @group = [heat]
      @dance = dance
    end

    def add?(dance, dcat, level, age, heat)
      return if @participants.include? heat.lead
      return if @participants.include? heat.follow

      return unless (dcat-@max_dcat).abs <= @@category
      return unless (dcat-@min_dcat).abs <= @@category
      return unless (level-@max_level).abs <= @@level
      return unless (level-@min_level).abs <= @@level
      return unless (age-@max_age).abs <= @@age
      return unless (age-@min_age).abs <= @@age

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

    def each(&block)
      @group.each(&block)
    end
  end
end
