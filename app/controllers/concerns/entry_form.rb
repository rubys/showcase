module EntryForm
  def form_init(id = nil)
    @person ||= Person.find(id) if id

    if @person
      entries = @person.lead_entries + @person.follow_entries
      studios = [@person.studio] + @person.studio.pairs

      seeking = @person.role == 'Leader' ? 'Follower' : 'Leader'
      @instructors = Person.where(type: 'Professional', studio: studios, 
        role: [seeking, 'Both']).order(:name)
      students = Person.where(type: 'Student', studio: @person.studio, 
        role: [seeking, 'Both']).order(:name) +
        Person.where(type: 'Student', studio: @person.studio.pairs,
        role: [seeking, 'Both']).order(:name)

      @avail = @instructors + students
      surname = @person.name.split(',').first + ','
      spouse = @avail.find {|person| person.name.start_with? surname}
      @avail = ([spouse] + @avail).uniq if spouse

      @avail = @avail.map {|person| [person.display_name, person.id]}.to_h
      @instructors = @instructors.map {|person| [person.display_name, person.id]}.to_h
    else
      @followers = Person.where(role: %w(Follower Both)).order(:name).pluck(:name, :id)
      @leads = Person.where(role: %w(Leader Both)).order(:name).pluck(:name, :id)
      @instructors = Person.where(type: 'Professional').order(:name).pluck(:name, :id)
    end

    @ages = Age.all.order(:id).map {|age| [age.description, age.id]}
    @levels = Level.all.order(:id).map {|level| [level.name, level.id]}

    @entries = {'Closed' => {}, 'Open' => {}}
  end

  def find_or_create_entry(params)
    @person = Person.find(params[:primary])

    if @person.role == "Follower"
      lead = Person.find(params[:partner])
      follow = @person
    else
      lead = @person
      follow = Person.find(params[:partner])
    end

    if lead.type == 'Professional' or follow.type == 'Professional'
      instructor = nil
    else
      instructor = params[:instructor]
    end

    Entry.find_or_initialize_by(
      lead: lead,
      follow: follow,
      age_id: params[:age],
      level_id: params[:level],
      instructor_id: instructor
    )
  end
end