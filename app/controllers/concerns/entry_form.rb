module EntryForm
  def form_init(id = nil, entry = nil)
    @person ||= Person.find(id) if id

    if entry and @person&.type != 'Student'
      if entry.follow.type == "Student"
        @person = entry.follow
      else
        @person = entry.lead
      end
    end

    if @person
      entries = @person.lead_entries + @person.follow_entries
      studios = [@person.studio] + @person.studio.pairs

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
        @students = []
      else
        @students = Person.where(type: 'Student', studio: @person.studio, 
          role: [*seeking, 'Both']).order(:name) +
          Person.where(type: 'Student', studio: @person.studio.pairs,
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

    @entries = {'Closed' => {}, 'Open' => {}, 'Multi' => {}, 'Solo' => {}}

    @columns = Dance.maximum(:col) || 4

    @track_ages = Event.first.track_ages
  end

  def find_or_create_entry(params)
    @person = Person.find(params[:primary])
    partner = Person.find(params[:partner])

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

    Entry.find_or_initialize_by(
      lead: lead,
      follow: follow,
      age_id: params[:age] || Age.order(:order).pluck(:id).first,
      level_id: params[:level],
      instructor_id: instructor
    )
  end
end