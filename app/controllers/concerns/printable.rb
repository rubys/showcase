module Printable
  def generate_agenda
    event = Event.last

    @heats = Heat.order('abs(number)').includes(
      dance: [:open_category, :closed_category, :solo_category, :multi_category], 
      entry: [:age, :level, lead: [:studio], follow: [:studio]],
      solo: [:formations]
    )

    @heats = @heats.to_a.group_by {|heat| heat.number.abs}.
      map do |number, heats|
        [number, heats.sort_by { |heat| [heat.back || 0, heat.entry.lead.type] } ]
      end

    @categories = Category.order(:order).map {|category| [category.name, category]}.to_h

    # copy start time/date to subsequent entries
    last_cat = nil
    first_time = nil
    @categories.each do |name, category|
      if last_cat
        category.day = last_cat.day if category.blank?
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
    heat_length = Event.last.heat_length
    solo_length = Event.last.solo_length || heat_length
    if not Event.last.date.blank? and heat_length and @categories.values.any? {|category| not category.time.blank?}
      start = Chronic.parse(
        Event.last.date.sub(/(^|[a-z]+ )?\d+\s*[-&]\s*\d+/) {|str| str.sub(/\s*[-&]\s*.*/, '')},
        guess: false
      )&.begin || Time.now

      if not @categories.empty? and not @categories.values.first.day.blank?
        start = Chronic.parse(@categories.values.first.day, guess: false)&.begin || start
      end
    end

    @agenda = {}
    @start = [] if start
    @finish = [] if start
    last_cat = nil

    @heats.each do |number, heats|
      if number == 0
        @agenda['Unscheduled'] ||= []
        @agenda['Unscheduled'] << [number, {nil => heats}]
      else
        cat = heats.first.dance_category
        ballrooms = cat&.ballrooms || event.ballrooms || 1

        if cat and start
          cat = @categories[cat.name]

          if cat != last_cat and not cat.day.blank?
            yesterday = Chronic.parse('yesterday', now: start)
            day = Chronic.parse(cat.day, now: yesterday, guess: false)&.begin || start
            start = day if day > start and day < start + 86_400
          end

          if not cat.time.blank?
            if cat != last_cat
              time = Chronic.parse(cat.time, now: start) || start
              start = time if time and time > start
            end

            @start[number] ||= start

            if heats.first.dance.heat_length
              start += heat_length * heats.first.dance.heat_length
            elsif heats.any? {|heat| heat.number > 0}
              if heats.length == 1 and heats.first.category == 'Solo'
                start += solo_length
              else
                start += heat_length
              end
            end

            @finish[number] ||= start
          end

          last_cat = cat
        end
        
        cat = cat&.name || 'Uncategorized'

        @agenda[cat] ||= []
        @agenda[cat] << [number, assign_rooms(ballrooms, heats)]
      end
    end

    @oneday = @categories.values.map(&:day).uniq.length <= 1
  end

  def assign_rooms(ballrooms, heats)
    if ballrooms == 1 or heats.all? {|heat| heat.category == 'Solo'}
      {nil => heats}
    elsif ballrooms == 2
      b = heats.select {|heat| heat.entry.lead.type == "Student"}
      {'A': heats - b, 'B': b}
    else
      groups = {nil => [], 'A' => [], 'B' => []}.merge(heats.group_by(&:ballroom))
      heats = groups[nil]
      n = (heats.length / 2).to_i
      n += 1 if heats.length % 2 == 1 and heats[n].entry.lead.type != 'Student'
      {'A': heats[...n] + groups['A'], 'B': heats[n..] + groups['B']}
    end
  end

  def generate_invoice(studios = nil, student=false)
    studios ||= Studio.all(order: name)

    @event = Event.last
    @track_ages = @event.track_ages
    @column_order = @event.column_order

    @invoices = {}

    studios.each do |studio|
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

      entries = (Entry.joins(:follow).where(people: {type: 'Student', studio: studio}) +
        Entry.joins(:lead).where(people: {type: 'Student', studio: studio})).uniq

      @dances = studio.people.order(:name).map do |person|
        purchases = (person.package&.price || 0) + person.options.map(&:option).map(&:price).sum
        [person, {dances: 0, cost: 0, purchases: purchases}]
      end.to_h

      entries.each do |entry|
        if entry.lead.type == 'Student' and entry.follow.type == 'Student' 
          split = 2.0
        else
          split = 1
        end

        entry.heats.each do |heat|
          if entry.lead.type == 'Student' and @dances[entry.lead]
            @dances[entry.lead][:dances] += 1 / split
            @dances[entry.lead][:cost] += @cost[heat.category] / split

            if @student
              @dances[entry.lead][heat.category] = (@dances[entry.lead][heat.category] || 0) + 1/split
            end
          end

          if entry.follow.type == 'Student' and @dances[entry.follow]
            @dances[entry.follow][:dances] += 1 / split
            @dances[entry.follow][:cost] += @cost[heat.category] / split

            if @student
              @dances[entry.follow][heat.category] = (@dances[entry.follow][heat.category] || 0) + 1/split
            end
          end
        end
      end

      @invoices[studio] = {
        dance_count: @dances.map {|person, info| info[:dances]}.sum,
        purchases: @dances.map {|person, info| info[:purchases]}.sum,
        dance_cost: @dances.map {|person, info| info[:cost]}.sum,
        total_cost: @dances.map {|person, info| info[:cost] + info[:purchases]}.sum,

        dances: @dances,

        entries: Entry.where(id: entries.map(&:id)).
          order(:levei_id, :age_id).
          includes(lead: [:studio], follow: [:studio], heats: [:dance]).group_by {|entry| 
            entry.follow.type == "Student" ? [entry.follow.name, entry.lead.name] : [entry.lead.name, entry.follow.name]
          }.sort_by {|key, value| key}
      }
    end
  end

  def heat_sheets
    generate_agenda
    @people ||= Person.where(type: ['Student', 'Professional']).order(:name)

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
    @event = Event.last
  end

  def score_sheets
    @judges = Person.where(type: 'Judge').order(:name)
    @people ||= Person.joins(:studio).where(type: 'Student').order('studios.name, name')
    @heats = Heat.includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).all.order(:number)
    @layout = 'mx-0 px-5'
    @nologo = true
    @event = Event.last
    @track_ages = @event.track_ages
  end

  def render_as_pdf(basename:, concat: [])
    tmpfile = Tempfile.new(basename)

    url = URI.parse(request.url.sub(/\.pdf($|\?)/, '.html\\1'))
    url.scheme = 'http'
    url.hostname = 'localhost'
    url.port = request.headers['SERVER_PORT']

    if RUBY_PLATFORM =~ /darwin/
      chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    else
      chrome="google-chrome"
    end

    system chrome, '--headless', '--disable-gpu', '--print-to-pdf-no-header',
      "--print-to-pdf=#{tmpfile.path}", url.to_s

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
end
