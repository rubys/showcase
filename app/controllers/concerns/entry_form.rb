module EntryForm
  def form_init(id = nil)
    @person ||= Person.find(id) if id
    entries = @person.lead_entries + @person.follow_entries
    studios = [@person.studio] + @person.studio.pairs

    seeking = @person.role == 'Leader' ? 'Follower' : 'Leader'
    teacher = Person.where(type: 'Professional', studio: studios, 
      role: [seeking, 'Both']).order(:name)
    student = Person.where(type: 'Student', studio: @person.studio, 
      role: [seeking, 'Both']).order(:name) +
      Person.where(type: 'Student', studio: @person.studio.pairs,
      role: [seeking, 'Both']).order(:name)

    @avail = teacher + student
    surname = @person.name.split(',').first + ','
    spouse = @avail.find {|person| person.name.start_with? surname}
    @avail = ([spouse] + @avail).uniq if spouse

    @avail = @avail.map {|person| [person.display_name, person.name]}.to_h

    @ages = Age.all.order(:id).map {|age| [age.description, age.id]}
    @levels = Level.all.order(:id).map {|level| [level.name, level.id]}

    @entries = {'Closed' => {}, 'Open' => {}}
  end

  def find_or_create_entry(params)
    @person = Person.find(params[:primary])

    if @person.role == "Follower"
      lead = Person.find_by(name: params[:partner])
      follow = @person
    else
      lead = @person
      follow = Person.find_by(name: params[:partner])
    end

    Entry.find_or_create_by(
      lead: lead,
      follow: follow,
      age_id: params[:age],
      level_id: params[:level]
    )
  end
end