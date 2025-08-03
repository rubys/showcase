module Printable
  def generate_agenda(expand_multi_heats: true)
    event = Event.current

    @heats = Heat.order('abs(number)').includes(
      dance: [
        :open_category, :closed_category, :solo_category, :multi_category,
        :pro_open_category, :pro_closed_category, :pro_solo_category, :pro_multi_category,
        { multi_children: :dance },
        { open_category: :extensions },
        { closed_category: :extensions },
        { solo_category: :extensions },
        { multi_category: :extensions },
        { pro_open_category: :extensions },
        { pro_closed_category: :extensions },
        { pro_solo_category: :extensions },
        { pro_multi_category: :extensions }
      ],
      entry: [:age, :level, { lead: :studio }, { follow: :studio }],
      solo: [:formations, :combo_dance, :category_override]
    )

    @heats = @heats.to_a.group_by {|heat| heat.number.abs}.
      map do |number, heats|
        [number, heats.sort_by { |heat| [heat.dance_id, heat.back || 0, heat.entry.lead.type] } ]
      end

    @categories = (Category.includes(:extensions).all + CatExtension.includes(:category).all).sort_by {|cat| cat.order}.
      map {|category| [category.name, category]}.to_h

    # copy start time/date to subsequent entries
    last_cat = nil
    first_time = nil
    @categories.each do |name, category|
      if last_cat
        category.day = last_cat.day if category.day.blank?
        first_time = nil if category.day != last_cat.day
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
    heat_length = Event.current.heat_length
    solo_length = Event.current.solo_length || heat_length
    if not Event.current.date.blank? and heat_length and @categories.values.any? {|category| not category.time.blank?}
      start = Event.parse_date(Event.current.date, guess: false)&.begin || Time.now

      if not @categories.empty? and not @categories.values.first.day.blank?
        start = Chronic.parse(@categories.values.first.day, guess: false)&.begin || start
      end
    end

    @oneday = event.date.blank? || !!(event.date =~ /^\d{4}-\d{2}-\d{2}$/)
    @oneday ||= @categories.values.map(&:day).uniq.length <= 1

    # sort heats into categories

    @agenda = {}

    @agenda['Unscheduled'] = []
    @categories.each do |name, cat|
      @agenda[name] = []
    end
    @agenda['Uncategorized'] = []

    current = @categories.values.first

    judge_ballrooms = Judge.where.not(ballroom: 'Both').exists?

    extensions = CatExtension.includes(:category).order(:part).all.group_by(&:category)

    @heats.each do |number, heats|
      if number == 0
        @agenda['Unscheduled'] << [number, {nil => heats}]
      else
        cat = heats.first.dance_category
        cat = cat.category if cat.is_a? CatExtension
        cat = current if cat != current and event.heat_range_cat == 1 and heats.first.category != 'Solo' and (heats.first.dance.open_category == current or heats.first.dance.closed_category == current)
        current = cat
        ballrooms = cat&.ballrooms || event.ballrooms || 1

        if cat && cat.instance_of?(Category)
          split = cat.split.to_s.split(/[, ]+/).map(&:to_i)
          max = split.shift

          if max && @agenda[cat.name].length >= max
            (extensions[cat] || []).each do |extension|
              split.push max if split.empty?
              max = split.shift

              if @agenda[extension.name].length < max
                cat = extension
                break
              end
            end
          end

          cat = cat.name
        else
          cat = 'Uncategorized'
        end

        # Check if this is a multi-heat with children that should be expanded
        if expand_multi_heats && heats.first.category == 'Multi' && heats.first.dance.multi_children.any?
          # Create a separate entry for each child dance
          heats.first.dance.multi_children.sort_by { |child| child.slot || child.id }.each do |child_dance|
            # Create copies of heats with the child dance name
            heat_copies = heats.map do |heat|
              # Create a new Heat instance with the same attributes
              copy = Heat.new(heat.attributes.except('id'))
              copy.id = heat.id  # Preserve ID for routing
              copy.child_dance_name = child_dance.dance.name
              # Copy associations
              copy.dance = heat.dance
              copy.entry = heat.entry
              copy.solo = heat.solo if heat.solo
              # Mark as readonly to prevent accidental database operations
              copy.readonly!
              copy
            end
            
            @agenda[cat] << [number, assign_rooms(ballrooms, heat_copies,
              (judge_ballrooms && ballrooms == 2) ? -number : nil)]
          end
        else
          @agenda[cat] << [number, assign_rooms(ballrooms, heats,
            (judge_ballrooms && ballrooms == 2) ? -number : nil)]
        end
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
          if cat.time =~ /^\d{1,2}:\d{2}$/
            cattime = Time.parse(cat.time)
            time = start.change(hour: cattime.hour, min: cattime.min)
          else
            time = Chronic.parse(cat.time, now: start) || start
          end
          start = time if time and time > start
        end

        @cat_start[name] = start

        last_number_processed = nil
        heats.each do |number, ballrooms|
          heats = ballrooms.values.flatten

          @start[number] ||= start

          # Only add time for the first occurrence of each heat number
          # (to avoid double-counting when multi-heats are expanded)
          if last_number_processed != number
            if heats.first.dance.heat_length
              start += heat_length * heats.first.dance.heat_length
              # Only add semi-finals time if there are more than 8 couples
              if heats.first.dance.semi_finals && heats.length > 8
                start += heat_length * heats.first.dance.heat_length
              end
            elsif heats.any? {|heat| heat.number > 0}
              if heats.length == 1 and heats.first.category == 'Solo'
                start += solo_length
              else
                start += heat_length
              end
            end
            last_number_processed = number
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

    if event.heat_range_level == 0
      heat_level = Heat.joins(:entry).pluck(:number, :level_id).to_h
      agenda = @agenda
      @agenda = {}

      Level.order(:id).each do |level|
        heats_for_level = heat_level.select {|number, level_id| level_id == level.id}.keys

        agenda.each do |name, heats|
          category = heats.select {|number, rooms| heats_for_level.include? rooms.values.flatten.first.number}
          @agenda["#{level.name} #{name}"] = category unless category.empty?
        end
      end
    end
  end

  def assign_rooms(ballrooms, heats, number)
    if heats.all? {|heat| heat.category == 'Solo'}
      {nil => heats}
    elsif heats.all? {|heat| !heat.ballroom.nil?}
      heats.group_by(&:ballroom)
    elsif ballrooms == 1
      {nil => heats}
    elsif ballrooms == 2
      b = heats.select {|heat| heat.entry.lead.type == "Student"}
      {'A': heats - b, 'B': b}
    else
      if number && (number < 0 || Judge.where.not(ballroom: 'Both').exists?)
        # negative number means it has already been determined that
        # judges ae assigned to a specific ballroom.
        heats = heats.sort_by(&:id)
        heats = heats.shuffle(random: Random.new(number.to_f.abs))
      end

      groups = {nil => [], 'A' => [], 'B' => []}.merge(heats.group_by do |heat|
        next heat.ballroom unless heat.ballroom.blank?
        next heat.subject.studio.ballroom if ballrooms != 3 && !heat.subject.studio.ballroom.blank?
      end)
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

    studios ||= Studio.all.order(:name).preload(:studio1_pairs, :studio2_pairs, people: {options: :option, package: {package_includes: :option}})

    @event = Event.current
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
      other_charges = {}

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

      @pcost = @cost.merge(
        'Closed' => @event.pro_heat_cost || 0.0,
        'Open' => @event.pro_heat_cost || 0.0,
        'Solo' => @event.pro_solo_cost || 0.0,
        'Multi' => @event.pro_multi_cost || 0.0
    )

      preload = {
        lead: [:studio, {options: :option, package: {package_includes: :option}}],
        follow: [:studio, {options: :option, package: {package_includes: :option}}],
        heats: {dance: [:open_category, :closed_category, :solo_category]}
      }
      entries = (Entry.joins(:follow).preload(preload).where(people: {type: 'Student', studio: studio}) +
        Entry.joins(:lead).preload(preload).where(people: {type: 'Student', studio: studio})).uniq

      # add professional entries - this one is used to detect pros who are not in the studio
      pentries = (Entry.joins(:follow).preload(preload).where(people: {type: 'Professional', studio: studio}) +
        Entry.joins(:lead).preload(preload).where(people: {type: 'Professional', studio: studio})).uniq

      # add professional entries - this one is contains all pro entries
      pro_entries = pentries.select {|entry| entry.lead.type == 'Professional' && entry.follow.type == 'Professional'}

      pentries -= pro_entries

      if instructor
        people = [instructor] + instructor.responsible_for
        entries.select! {|entry| [entry.lead, entry.follow, entry.instructor].intersect?(people)}
        pentries.select! {|entry| [entry.lead, entry.follow, entry.instructor].intersect?(people)}
      else
        studios = Set.new(studio.pairs + [studio])
        entries.select! {|entry| studios.include?(entry.follow.studio) && studios.include?(entry.lead.studio)}
        pentries.select! {|entry| !studios.include?(entry.follow.studio) || !studios.include?(entry.lead.studio)}
      end

      entries += pentries + pro_entries

      people = entries.map {|entry| [entry.lead, entry.follow]}.flatten

      if instructor
        people << @person
        people += @person.responsible_for
      elsif student && @person
        people = [@person]

        entries.reject! {|entry| entry.lead != @person && entry.follow != @person}
        pentries.reject! {|entry| entry.lead != @person && entry.follow != @person}
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
        elsif entry.lead.type == "Professional" and entry.lead.studio != studio
          split = 2.0
        elsif entry.follow.type == "Professional" and entry.follow.studio != studio
          split = 2.0
        else
          split = 1
        end

        entry.heats.each do |heat|
          next if heat.number < 0
          category = heat.category

          dance_category = heat.dance_category
          dance_category = dance_category.category if dance_category.is_a? CatExtension
          category = dance_category.name if dance_category&.cost_override
          category = heat.dance.name if heat.dance.cost_override

          if dance_category&.studio_cost_override
            split = 1 if dance_category.cost_override == 0 && entry.lead.studio == entry.follow.studio

            other_charges[dance_category.name] ||= {entries: 0, count: 0, cost: 0}
            other_charges[dance_category.name] = {
              entries: other_charges[dance_category.name][:entries] + 1,
              count: other_charges[dance_category.name][:count] + 1 / split,
              cost: other_charges[dance_category.name][:cost] + dance_category.studio_cost_override / split
            }

            next if dance_category.cost_override == 0
          end

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

      pro_entries.uniq.each do |entry|
        entry.heats.each do |heat|
          next if heat.number <= 0
          category = heat.category

          dance_category = heat.dance_category
          dance_category = dance_category.category if dance_category.is_a? CatExtension
          category = dance_category.name if dance_category&.cost_override

          if @pcost[category] > 0
            @dances[entry.lead][:dances] += 0.5
            @dances[entry.lead][:cost] += @pcost[category] / 2.0

            @dances[entry.follow][:dances] += 0.5
            @dances[entry.follow][:cost] += @pcost[category] / 2.0
          end
        end
      end

      if @event.independent_instructors && !instructor
        @dances.each do |person, info|
          next if person.type == "Professional" and not person.independent
          info[:purchases] = 0 if info[:dances] == 0
        end
      end

      @dances.reject! do |person, info|
        person.type == "Professional" and person.studio != studio
      end

      total_other_charges = {
        count: other_charges.values.map {|charge| charge[:count]}.sum,
        cost: other_charges.values.map {|charge| charge[:cost]}.sum
      }

      @invoices[studio] = {
        dance_count: @dances.map {|person, info| info[:dances]}.sum + total_other_charges[:count],
        purchases: @dances.map {|person, info| info[:purchases]}.sum,
        dance_cost: @dances.map {|person, info| info[:cost]}.sum + total_other_charges[:cost],
        total_cost: @dances.map {|person, info| info[:cost] + info[:purchases]}.sum  + total_other_charges[:cost],
        other_charges: other_charges,

        dances: @dances,

        entries: Entry.where(id: entries.map(&:id)).
          order(:level_id, :age_id).
          includes(lead: [:studio], follow: [:studio], heats: [:dance]).group_by {|entry|
            entry.follow.type == "Student" ? [entry.follow, entry.lead] : [entry.lead, entry.follow]
          }.sort_by {|key, value| key}
      }
    end

    # Identify dances being offered
    @offered = {
      freestyles: (Dance.where.not(open_category_id: nil).count + Dance.where.not(closed_category_id: nil).count) > 0,
      solos: (Dance.where.not(solo_category_id: nil).count) > 0,
      multis: (Dance.where.not(multi_category_id: nil).count) > 0
    }
  end

  def heat_sheets
    generate_agenda
    @people ||= Person.where(type: ['Student', 'Professional']).order('name COLLATE NOCASE')

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
    @event = Event.current
  end

  def score_sheets
    @judges = Person.where(type: 'Judge').order(:name)
    @people ||= Person.joins(:studio).where(type: 'Student').order('studios.name, name')
    @heats = Heat.includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).all.order(:number)
    @formations = Formation.joins(solo: :heat).where(on_floor: true).pluck(:person_id, :number)
    @layout = 'mx-0 px-5'
    @nologo = true
    @event = Event.current
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

  def undoable
    Heat.where('number != prev_number AND prev_number != 0').any?
  end

  def renumber_needed
    Heat.distinct.where.not(number: 0).pluck(:number).
      map(&:abs).sort.uniq.zip(1..).any? {|n, i| n != i}
  end
end
