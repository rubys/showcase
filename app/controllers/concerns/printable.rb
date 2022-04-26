module Printable
  def generate_agenda
    @heats = Heat.order(:number).includes(
      dance: [:open_category, :closed_category, :solo_category], 
      entry: [:age, :level, lead: [:studio], follow: [:studio]],
      solo: [:formations]
    )

    @heats = @heats.to_a.group_by {|heat| heat.number}.
      map do |number, heats|
        [number, heats.sort_by { |heat| heat.back || 0 } ]
      end
      
    start = nil
    heat_length = Event.last.heat_length
    if Event.last.date and heat_length and not @categories.values.first.time.empty?
      start = Chronic.parse(
        Event.last.date.sub(/[a-z]+ \d+-\d+/) {|str| str.sub(/-.*/, '')},
        guess: false
      ).begin
    end

    @agenda = {}
    @start = [] if start

    @heats.each do |number, heats|
      if number == 0
        @agenda['Unscheduled'] ||= []
        @agenda['Unscheduled'] << [number, heats]
      else
        cat = heats.first.dance_category

        if cat and start
          if cat.day and not cat.day.empty?
            yesterday = Chronic.parse('yesterday', now: start)
            day = Chronic.parse(cat.day, now: yesterday, guess: false).begin
            start = day if day > start
          end

          if cat.time and not cat.time.empty?
            time = Chronic.parse(cat.time, now: start)
            start = time if time and time > start
          end

          @start[number] ||= start
          start += heat_length
        end
        
        cat = cat&.name || 'Uncategorized'
        @agenda[cat] ||= []
        @agenda[cat] << [number, heats]
      end
    end

    @oneday = !@start || @start.compact.first.to_date == @start.last.to_date
  end

  def heat_sheets
    @people ||= Person.where(type: ['Student', 'Professional']).order(:name)
    @heats = Heat.includes(:dance, entry: [:level, :age, :lead, :follow]).all.order(:number)

    @heatlist = @people.map {|person| [person, []]}.to_h
    @heats.each do |heat|
      @heatlist[heat.lead] << heat.id rescue nil
      @heatlist[heat.follow] << heat.id rescue nil
    end

    Formation.includes(:person, solo: :heat).each do |formation|
      @heatlist[formation.person] << formation.solo.heat.id rescue nil
    end

    @layout = 'mx-0 px-5'
    @nologo = true
    @event = Event.last
  end

  def score_sheets
    @judges = Person.where(type: 'Judge').order(:name)
    @people ||= Person.joins(:studio).where(type: 'Student').order('studios.name, name')
    @heats = Heat.includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).all.order(:number)
    @layout = 'mx-0 px-5'
    @nologo = true
    @event = Event.last
  end
end
