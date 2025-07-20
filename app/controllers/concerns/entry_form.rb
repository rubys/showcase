module EntryForm
  def form_init(id = nil, entry = nil)
    event = Event.current
    @person ||= Person.find(id) if id
    @person ||= Person.nobody if @studio

    if entry and @person&.type != 'Student'
      if entry.follow.type == "Student"
        @person = entry.follow
      else
        @person = entry.lead
      end
    end

    if @person
      studio = @studio || @person.studio
      studios = [studio] + studio.pairs

      seeking = case @person.role
      when 'Leader'
          ['Follower']
      when 'Follower'
          ['Leader']
      else
        if entry and entry.follow == @person
          @role = 'Follower'
        else
          @role = 'Leader'
        end

        ['Leader', 'Follower']
      end

      seeking = ['Leader', 'Follower'] if @formation
      @seeking = seeking

      instructors = Person.where(type: 'Professional', studio: studios,
        role: [*seeking, 'Both']).order(:name)

      if @person.type == "Professional"
        more = Person.where(type: 'Professional',
          role: [*seeking, 'Both']).order(:name) - instructors
        instructors += more
        @students = []
      else
        @students = Person.where(type: 'Student', studio: studio,
          role: [*seeking, 'Both']).order(:name) +
          Person.where(type: 'Student', studio: studio.pairs,
          role: [*seeking, 'Both']).order(:name)
      end

      @avail = instructors + @students
      surname = @person.name.split(',').first + ','
      spouse = @avail.find {|person| person.name.start_with? surname}
      @avail = ([spouse] + @avail).uniq if spouse
      @avail.delete(@person)

      if @person.role == 'Both'
        @boths = @avail.select {|person| person.role == 'Both'}.map(&:id)
      end

      @avail = @avail.map {|person| [person.display_name, person.id]}.to_h
      @instructors = Person.where(type: 'Professional', studio: studios).
        all.map {|person| [person.display_name, person.id]}.sort.to_h
    else
      @followers = Person.where(role: %w(Follower Both)).order(:name).pluck(:name, :id)
      @leads = Person.where(role: %w(Leader Both)).order(:name).pluck(:name, :id)
      @instructors = Person.where(type: 'Professional').order(:name).pluck(:name, :id)
      @students = Person.where(type: 'Student').order(:name)
    end

    @ages = Age.all.order(:id).map {|age| [age.description, age.id]}
    @levels = Level.all.order(:id).map {|level| [level.name, level.id]}
    if event.solo_level_id
      if @solo
        @levels.select! {|name, id| id >= event.solo_level_id}
      else
        @levels.select! {|name, id| id < event.solo_level_id}
      end
    end

    @entries = {'Closed' => {}, 'Open' => {}, 'Multi' => {}, 'Solo' => {}}

    @columns = Dance.maximum(:col) || 4

    @track_ages = event.track_ages
  end

  def find_or_create_entry(params)
    @person = Person.find(params[:primary] || 0)
    partner = Person.find(params[:partner] || 0)

    if @person.role == "Follower" || partner.role == 'Leader' || params[:role] == 'Follower'
      lead = partner
      follow = @person
    else
      lead = @person
      follow = partner
    end

    if lead.type == 'Professional' or follow.type == 'Professional'
      instructor = nil
    else
      instructor = params[:instructor]
    end

    level = Level.where(id: params[:level]).first
    if not level and params[:level] == '0'
      level = Level.create!(id: 0, name: 'All Levels')
    end

    if not params[:age]
      age = Age.order(:order).first
    else
      age = Age.where(id: params[:age]).first
      if not age and params[:age] == '0'
        age = Age.create!(id: 0, category: '*', description: 'All Ages')
      end
    end

    Entry.find_or_initialize_by(
      lead: lead,
      follow: follow,
      age: age,
      level: level,
      instructor_id: instructor
    )
  end

  def dance_categories(dance, solo=false)
    if solo
      Dance.where(name: dance.name).select {|dance| dance.solo_category}.
        sort_by {|dance| dance.solo_category.order || 0}.
        map {|dance| [dance.solo_category.name, dance.id]}
    else
      Dance.where(name: dance.name).select {|dance| dance.freestyle_category}.
        sort_by {|dance| dance.freestyle_category.order || 0}.
        map {|dance| [dance.freestyle_category.name, dance.id]}
    end
  end
end
