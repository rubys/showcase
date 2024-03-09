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
        [number, heats.sort_by { |heat| [heat.dance_id, heat.back || 0, heat.entry.lead.type] } ]
      end

    @categories = (Category.all + CatExtension.all).sort_by {|cat| cat.order}.
      map {|category| [category.name, category]}.to_h

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
      start = Event.parse_date(Event.last.date, guess: false)&.begin || Time.now

      if not @categories.empty? and not @categories.values.first.day.blank?
        start = Chronic.parse(@categories.values.first.day, guess: false)&.begin || start
      end
    end

    @oneday = @categories.values.map(&:day).uniq.length <= 1

    # sort heats into categories

    @agenda = {}

    @agenda['Unscheduled'] = []
    @categories.each do |name, cat|
      @agenda[name] = []
    end
    @agenda['Uncategorized'] = []

    current = @categories.values.first
    @heats.each do |number, heats|
      if number == 0
        @agenda['Unscheduled'] << [number, {nil => heats}]
      else
        cat = heats.first.dance_category
        cat = current if cat != current and event.heat_range_cat == 1 and (heats.first.dance.open_category == current or heats.first.dance.closed_category == current)
        current = cat
        ballrooms = cat&.ballrooms || event.ballrooms || 1
        
        cat = cat&.name || 'Uncategorized'
        @agenda[cat] << [number, assign_rooms(ballrooms, heats)]
      end
    end

    @agenda.delete 'Unscheduled' if @agenda['Unscheduled'].empty?
    @agenda.delete 'Uncategorized' if @agenda['Uncategorized'].empty?

    # assign start and finish times

    if start and event.include_times
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
          time = Chronic.parse(cat.time, now: start) || start
          start = time if time and time > start
        end

        @cat_start[name] = start

        heats.each do |number, ballrooms|
          heats = ballrooms.values.flatten

          @start[number] ||= start

          if heats.first.dance.heat_length
            start += heat_length * heats.first.dance.heat_length
            if heats.first.dance.semi_finals
              start += heat_length * heats.first.dance.heat_length
            end
          elsif heats.any? {|heat| heat.number > 0}
            if heats.length == 1 and heats.first.category == 'Solo'
              start += solo_length
            else
              start += heat_length
            end
          end

          @finish[number] ||= start
        end

        if cat&.duration
          start = @cat_finish[name] = [start, @cat_start[name] + cat.duration*60].max
        else
          @cat_finish[name] = start
        end
      end
    end
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

  def find_couples
    people = Person.joins(:package).where(package: {couples: true})
    couples = Entry.where(lead: people, follow: people).pluck(:follow_id, :lead_id).to_h
    @paired = (couples.keys + couples.values).group_by(&:itself).
      select {|id, list| list.length == 1}.keys
    @couples = couples.select {|follow, lead| @paired.include?(lead) && @paired.include?(follow)}
  end

  def generate_invoice(studios = nil, student=false, instructor=nil)
    find_couples

    studios ||= Studio.all(order: name).preload(:studio1_pairs, :studio2_pairs, people: {options: :option, package: {package_includes: :option}})

    @event = Event.last
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

      preload = {
        lead: [:studio, {options: :option, package: {package_includes: :option}}],
        follow: [:studio, {options: :option, package: {package_includes: :option}}],
        heats: {dance: [:open_category, :closed_category, :solo_category]}
      }
      entries = (Entry.joins(:follow).preload(preload).where(people: {type: 'Student', studio: studio}) +
        Entry.joins(:lead).preload(preload).where(people: {type: 'Student', studio: studio})).uniq

      pentries = (Entry.joins(:follow).preload(preload).where(people: {type: 'Professional', studio: studio}) +
        Entry.joins(:lead).preload(preload).where(people: {type: 'Professional', studio: studio})).uniq

      if instructor
        entries.select! {|entry| entry.lead == instructor || entry.follow == instructor || entry.instructor == instructor}
        pentries.select! {|entry| entry.lead == instructor || entry.follow == instructor || entry.instructor == instructor}
      else
        studios = Set.new(studio.pairs + [studio])
        entries.select! {|entry| studios.include?(entry.follow.studio) && studios.include?(entry.lead.studio)}
        pentries.select! {|entry| !studios.include?(entry.follow.studio) || !studios.include?(entry.lead.studio)}
      end

      entries += pentries

      people = entries.map {|entry| [entry.lead, entry.follow]}.flatten

      if instructor
        people << @person
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

        entry.heats.each do |heat|
          category = heat.category
          category = heat.dance_category.name if heat.dance_category&.cost_override
          category = heat.dance.name if heat.dance.cost_override

          if entry.lead.type == 'Student' and @dances[entry.lead]
            @dances[entry.lead][:dances] += 1 / split
            @dances[entry.lead][:cost] += @cost[category] / split

            if @student
              @dances[entry.lead][category] = (@dances[entry.lead][category] || 0) + 1/split
            end
          end

          if entry.follow.type == 'Student' and @dances[entry.follow]
            @dances[entry.follow][:dances] += 1 / split
            @dances[entry.follow][:cost] += @cost[category] / split

            if @student
              @dances[entry.follow][category] = (@dances[entry.follow][category] || 0) + 1/split
            end
          end
        end
      end

      if @event.independent_instructors && !instructor
        @dances.each do |person, info|
          next if person.type == "Professional" and not person.independent
          info[:purchases] = 0 if info[:dances] == 0
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
            entry.follow.type == "Student" ? [entry.follow, entry.lead] : [entry.lead, entry.follow]
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
    @formations = Formation.joins(solo: :heat).where(on_floor: true).pluck(:person_id, :number)
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
end
