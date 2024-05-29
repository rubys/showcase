class PeopleController < ApplicationController
  include Printable
  include Retriable

  before_action :set_person, only:
    %i[ show edit update destroy get_entries post_entries toggle_present ballroom remove_option instructor_invoice ]

  permit_site_owners :new, :create, :show, :post_type, :edit, :update, :destroy,
    :get_entries, :post_entries, :instructor_invoice,
    trust_level: 50

  def heats
    event = Event.last
    @ballrooms = event.ballrooms
    @track_ages = event.track_ages
    @font_size = event.font_size
    heat_sheets

    respond_to do |format|
      format.html { render 'people/heats' }
      format.pdf do
        render_as_pdf basename: "heat-sheets"
      end
    end
  end

  def individual_heats
    event = Event.last
    @ballrooms = event.ballrooms
    @track_ages = event.track_ages
    @font_size = event.font_size
    @people = [set_person]
    heat_sheets

    respond_to do |format|
      format.html { render 'people/heats' }
      format.pdf do
        render_as_pdf basename: "#{@person.name.gsub(/\W+/, '-')}-heat-sheet"
      end
    end
  end

  def scores
    score_sheets
    @font_size = @event.font_size

    respond_to do |format|
      format.html { render 'people/scores' }
      format.pdf do
        render_as_pdf basename: "scores"
      end
    end
  end

  def individual_scores
    @people = [set_person]
    score_sheets
    @font_size = @event.font_size

    respond_to do |format|
      format.html { render 'people/scores' }
      format.pdf do
        render_as_pdf basename: "#{@person.name.gsub(/\W+/, '-')}-scores"
      end
    end
  end

  def instructor_invoice
    @studio = @person.studio
    @instructor = @person
    generate_invoice([@studio], false, @person)

    @event ||= Event.first
    @font_size = @event.font_size

    respond_to do |format|
      format.html { render 'studios/invoice' }
      format.pdf do
        render_as_pdf basename: "#{@person.display_name.gsub(/\W+/, '-')}-invoice"
      end
    end
  end

  def certificates
    if request.get?
      @studios = [['-- all studios --', nil]] + Studio.order(:name).pluck(:name, :id)
    else
      @people = Person.joins(:studio).where(type: 'Student').order('studios.name', :name).to_a

      if not params[:person_id].blank?
        person_id = params[:person_id].to_i
        @people.select! {|person| person.id == person_id}
      elsif not params[:studio_id].blank?
        studio_id = params[:studio_id].to_i
        @people.select! {|person| person.studio_id == studio_id}
      end

      pdf = CombinePDF.new
      @people.each do |name|
        pdf << CombinePDF.load(params[:template].tempfile.path)
      end

      pdf.pages.zip(@people) do |page, person|
        page.textbox person.display_name, height: params[:height].to_i, width: params[:width].to_i,
          y: params[:y].to_i, x: params[:x].to_i, font: :'Times-Bold', font_size: params['font-size'].to_i,
          font_color: [0, 0, 0]
      end

      send_data pdf.to_pdf, disposition: 'inline', filename: "certificates.pdf",
        type: 'application/pdf'
    end
  end

  # GET /people or /people.json
  def index
    if not @people
      @people ||= Person.includes(:studio).order(sort_order)

      title = []
      where = {}

      if params[:age]
        age_id = params[:age].to_i
        where[:age] = age_id
        title << "Age #{Age.find(age_id).description}"
      end

      if params[:level]
        level_id = params[:level].to_i
        where[:level] = level_id
        title << Level.find(level_id).name
      end

      if params[:type]
        where[:type] = params[:type]
        title << params[:type]
      end

      if params[:role]
        where[:role] = params[:role]
        title << params[:role]
      end

      @title = title.join(' ') unless title.empty?
      @people = @people.where(where) unless where.empty?
    end

    @heats = {}
    @solos = {}
    @multis = {}

    counts =
      Heat.joins(:entry).group(:category, 'entries.follow_id').count.to_a +
      Heat.joins(:entry).group(:category, 'entries.lead_id').count.to_a +
      Formation.pluck(:person_id).map {|id| [['Solo', id], 1]}

    counts.each do |(category, id), count|
      next unless @people.find {|person| person.id == id}

      list = case category
        when "Solo"
          @solos
        when "Mutli"
          @multis
        else
          @heats
      end

      list[id] = (list[id] ||= 0) + count
    end

    if params[:sort] == 'heats'
      @people = @people.to_a.sort_by! {|person| @heats[person.id] || 0}
    elsif params[:sort] == 'solos'
      @people = @people.to_a.sort_by! {|person| @solos[person.id] || 0}
    elsif params[:sort] == 'multis'
      @people = @people.to_a.sort_by! {|person| @multis[person.id] || 0}
    end

    @track_ages = Event.first.track_ages

    render :index
  end

  # GET /people/backs or /people.json
  def backs
    leaders = Entry.includes(:heats).where.not(heats: {category: 'Solo'}).distinct.pluck(:lead_id)
    @people = Person.where(id: leaders).
      or(Person.where.not(back: nil)).includes(:lead_entries, :studio).order(:back, :type, :name)

    @pro_numbers = Person.where(type: 'Professional').minimum(:back)
    @student_numbers = Person.where(type: 'Student').minimum(:back)
  end

  def assign_backs
    leaders = Entry.includes(:heats).where.not(heats: {category: 'Solo'}).distinct.pluck(:lead_id)
    people = Person.where(id: leaders).order(:type, :name)

    pro_numbers = (params[:pro_numbers] || 101).to_i
    student_numbers = (params[:student_numbers] || 101).to_i

    number = pro_numbers
    Person.transaction do
      Person.where.not(back: nil).where.not(id: leaders).update_all(back: nil)

      people.each do |person|
        number = student_numbers if number < student_numbers and person.type == "Student"
        person.back = number
        person.save! validate: false
        number += 1
      end

      raise ActiveRecord::Rollback unless people.all? {|person| person.valid?}
    end

    redirect_to backs_people_path
  end

  # GET /people/students or /students.json
  def students
    @people = Person.includes(:studio).where(type: 'Student').order(sort_order)
    @title = 'Students'

    index
  end

  # GET /people/professionals or /professionals.json
  def professionals
    @people = Person.includes(:studio).where(type: 'Professional').order(sort_order)
    @title = 'Professionals'

    index
  end

  def staff
    @professionals = Person.includes(:studio).where(type: 'Professional').order(sort_order)
    @staff = Studio.find(0)
    @font_size = Event.first.font_size

    respond_to do |format|
      format.html { render }
      format.pdf do
        render_as_pdf basename: "staff"
      end
    end
  end

  # GET /people/professionals or /professionals.json
  def guests
    @people = Person.includes(:studio).where(type: 'Guest').order(sort_order)
    @title = 'Guests'

    index
  end

  # GET /people/couples or /couples.json
  def couples
    @couples = Entry.preload(:lead, :follow).joins(:lead, :follow).
      where(lead: {type: 'Student'}, follow: {type: 'Student'}).
      group_by {|entry| [entry.lead, entry.follow]}.
      map do |(lead, follow), entries|
        [lead, follow, entries.sum {|entry| entry.heats.count}]
      end.
      sort_by {|(lead, follow), count| level = lead.level_id}
    @track_ages = Event.first.track_ages
  end

  # GET /people/labels
  def labels
    @event = Event.first
    @people = Person.where.not(studio_id: nil).includes(:studio).order('studios.name', :name).to_a
    staff = @people.select {|person| person.studio_id == 0}
    @people -= staff
    @people += staff

    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        render_as_pdf basename: "labels"
      end
    end
  end


  # GET /people/back-numbers
  def back_numbers
    @event = Event.first
    @people = Person.where.not(back: nil).order(:back).to_a

    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        render_as_pdf basename: "back-numbers"
      end
    end
  end

  def package
    package_id = params[:package_id].to_i
    package = Billable.find(package_id)
    @people = package.people.includes(:studio).order(:name)
    @title = "#{package.type} - #{package.name}"

    if package.type == 'Option'
      @packages = package.option_included_by.map(&:package).sort_by {|package| [package.type, package.order]}

      @option = package
      @strike = @people.reject {|person| person.selected_options.map(&:id).include? package_id}
    end

    index
  end

  # GET /people/1 or /people/1.json
  def show
    Dance.all
    Person.all

    preload = [:lead, :follow, :level, heats: [:dance]]
    entries = @person.lead_entries.preload(preload) + @person.follow_entries.preload(preload)
    partners = (entries.map(&:follow) + entries.map(&:lead)).uniq
    partners.delete @person
    partners = partners.sort_by {|person| person.name.split(/,\s*/).last}.
      map {|partner| [partner, entries.select {|entry|
        entry.lead == partner || entry.follow == partner
      }]}.to_h

    heats = entries.map {|entry| entry.heats}.flatten

    @dances = Dance.order(:order).all.map {|dance|
      [dance, partners.map {|partner, entries|
        [partner, entries.map {|entry| entry.active_heats.count {|heat| heat.category != 'Solo' and heat.dance == dance}}.sum]
      }.to_h]
    }.select {|dance, partners| partners.values.any? {|count| count > 0}}.to_h

    @entries = partners
    @partners = partners.keys

    @routines = !Category.where(routines: true).blank?

    @heats = Heat.joins(:entry).
      includes(:dance, entry: [:lead, :follow]).
      where(entry: {lead: @person}).
      or(Heat.where(entry: {follow: @person})).
      or(Heat.where(id: Formation.joins(:solo).where(person: @person, on_floor: true).pluck(:heat_id))).
      order('abs(number)').to_a

    @solos = Solo.includes(:heat, :formations).all.map(&:heat) & @heats

    @scores = Score.joins(heat: :entry).
      where(entry: {follow_id: @person.id}).or(
        Score.joins(heat: :entry).where(entry: {lead_id: @person.id})
      ).group(:value, :dance_id).order(:dance_id).
      count(:value).
      group_by {|(value, dance), count| dance}.
      map {|dance, list| [dance, list.map {|(value, dance), count|
        [value, count]
      }.to_h]}.to_h

    if @person.type == 'Judge'
      @multi = Dance.where.not(multi_category: nil).count
    end

    @event = Event.first
    @track_ages = @event.track_ages

    @score_bgcolor = []
    if @event.open_scoring == '#'
      @score_range = @scores.values.map(&:keys).flatten.sort.uniq
    elsif @event.open_scoring == '1'
      @score_range = ScoresController::SCORES['Closed'] + ScoresController::SCORES['Open']
      @score_bgcolor = ScoresController::SCORES['Closed']
    else
      @score_range = ScoresController::SCORES['Closed']
    end
  end

  # GET /people/new
  def new
    @person ||= Person.new

    params[:studio] = nil if params[:studio].to_s == '0'

    if params[:studio]
      @types = %w[Student Professional Guest]
      @person.studio = Studio.find(params[:studio])
      @person.type ||= 'Student'
    else
      @types = %w[Judge DJ Emcee Official Organizer Guest]
    end

    selections

    @entries = 0
    @source = params[:source]
  end

  # GET /people/1/edit
  def edit
    if @person.studio_id == 0
      @types = %w[Judge DJ Emcee Official Organizer Guest]
    elsif @person.studio_id
      @types = %w[Student Professional Guest]
    end

    selections

    @entries = @person.lead_entries.count + @person.follow_entries.count
    @locked = Event.first.locked?
    @heats = list_heats
  end

  def get_entries
    selections

    entries = @person.lead_entries + @person.follow_entries
    studios = [@person.studio] + @person.studio.pairs

    dances = Dance.all.to_a
    @dances = dances.map(&:name)

    @entries = %w(Open Closed).map do |cat|
      [cat, dances.map do |dance|
        [dance.name, entries.find do |entry|
          entry.category == cat && entry.dance == dance
        end&.count || 0]
      end.to_h]
    end.to_h

    seeking = @person.role == 'Leader' ? 'Follower' : 'Leader'
    teacher = Person.where(type: 'Professional', studio: studios,
      role: [seeking, 'Both']).order(:name)
    student = Person.where(type: 'Student', studio: @person.studio,
      role: [seeking, 'Both']).order(:name)

    @avail = teacher + student
    surname = @person.name.split(',').first + ','
    spouse = @avail.find {|person| person.name.start_with? surname}
    @avail = ([spouse] + @avail).uniq if spouse

    @avail = @avail.map {|person| [person.display_name, person.name]}.to_h

    render :entries
  end

  def post_entries
    if @person.role = "Follower"
      lead = Person.find_by(name: params[:partner])
      follow = @person
    else
      lead = @person
      follow = Person.find_by(name: params[:partner])
    end

    total = 0
    %w(Closed Open).each do |category|
      Dance.all.each do |dance|
        count = params[:entries][category][dance.name].to_i
        if count > 0
          total += count

          entry = {
            category: category,
            dance: dance,
            lead: lead,
            follow: follow,
            count: count
          }

          entry = Entry.create! entry

          (count..1).each do |heat|
            Heat.create!({number: 0, entry: entry})
          end
        end
      end
    end

    redirect_to person_url(@person), notice: "#{helpers.pluralize total, 'heat'} successfully added."
  end

  def studio_list
    @people = [['-- all students --', nil]] +
      Person.where(type: 'Student', studio_id: params[:studio_id].to_i).order(:name).
         map {|person| [person.display_name, person.id]}

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace('select-person',
        render_to_string(partial: 'studio_list'))}
      format.html { redirect_to people_certificates_url }
    end
  end

  def post_type
    if params[:id]
      @person = Person.find(params[:id])
    else
      @person = Person.new

      if params[:studio_id]
        @person.studio = Studio.find(params[:studio_id])
      end
    end

    @person.type = params[:type]

    selections

    respond_to do |format|
      format.turbo_stream { render turbo_stream: [
        turbo_stream.replace('package-select', render_to_string(partial: 'package')),
        turbo_stream.replace('options-select', render_to_string(partial: 'options'))
      ]}
      format.html { redirect_to people_url }
    end
  end

  def post_package
    if params[:id]
      @person = Person.find(params[:id])
    else
      @person = Person.new
    end

    @person.type = params[:type]
    @person.package_id = params[:package_id].to_i

    selections

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace('options-select',
        render_to_string(partial: 'options'))}
      format.html { redirect_to people_url }
    end
  end

  # POST /people or /people.json
  def create
    person = params[:person]

    @person = Person.new(filtered_params(person).except(:options))

    selections

    set_exclude

    respond_to do |format|
      if @person.save
        update_options

        format.html { redirect_to (params[:source] == 'settings' ? settings_event_index_path(tab: 'Staff') : person_url(@person)),
          notice: "#{@person.display_name} was successfully added." }
        format.json { render :show, status: :created, location: @person }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @person.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /people/1 or /people/1.json
  def update
    selections

    set_exclude

    params[:independent] = false unless @event.independent_instructors

    respond_to do |format|
      if @person.update(filtered_params(person_params).except(:options))
        update_options

        format.html { redirect_to person_url(@person), notice: "#{@person.display_name} was successfully updated." }
        format.json { render :show, status: :ok, location: @person }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @person.errors, status: :unprocessable_entity }
      end
    end
  end

  def remove_option
    option = Billable.find(params[:option])
    removed = PersonOption.destroy_by person: @person, option: option
    redirect_to people_package_path(@person, package_id: option.id),
      notice: removed.empty? ? "no options removed from #{@person.display_name}."
        : "option #{option.name} removed from "#{@person.display_name}."
  end

  def toggle_present
    respond_to do |format|
      judge = Judge.find_or_create_by(person_id: @person.id)
      if judge.update({present: !judge.present})
        format.json { render json: { present: @person.present? } }
      else
        format.json { render json: { present: @person.present? }, status: :unprocessable_entity }
      end
    end
  end

  def ballroom
    respond_to do |format|
      judge = Judge.find_or_create_by(person_id: @person.id)
      if judge.update({ballroom: params[:ballroom] || 'Both'})
        format.json { render json: { ballroom: judge.ballroom } }
      else
        format.json { render json: { ballroom: judge.ballroom }, status: :unprocessable_entity }
      end
    end
  end

  # POST /people/1/show_assignments
  def show_assignments
    judge = Judge.find_or_create_by(person_id: params[:id])
    judge.update! show_assignments: params[:show]
    style = params[:style]
    style = nil if style == 'radio' || style == ''
    redirect_to judge_heatlist_path(judge: params[:id], style: style)
  end

  def assign_judges
    retry_transaction do
      Score.where(value: nil, comments: nil, good: nil, bad: nil).delete_all
    end

    judges = Person.includes(:judge).where(type: 'Judge').
      select {|person| person.present?}.map(&:id).shuffle
    scored = Score.joins(:heat).distinct.where.not(heats: {number: ...0}).pluck(:number)

    if ENV['RAILS_APP_DB'] == '2024-glenview'
      unscored = Heat.where.not(number: scored).where.not(number: ...0).where.not(category: "Solo").order(:number).pluck(:number, :id)

      counts = unscored.group_by(&:first).map {|number, heats| [number, heats.length]}.to_h

      limits = counts.map {|number, count|
        if count <= 11
          [number, 0]
        elsif count <= 15
          [number, 1]
        elsif count <= 17
          [number, 2]
        else
          [number, 3]
        end
      }.to_h

      current = 0
      count = 0

      queue = []
      retry_transaction do
        unscored.each do |number, heat_id|
          queue = judges.dup if queue.empty?
          judge = queue.pop

          if judge == 142
            if current != number
              current = number
              count = 0
            end

            if count >= limits[number]
              queue = judges.dup if queue.empty?
              judge = queue.pop
            else
              count += 1
            end
          end

          Score.create! heat_id: heat_id, judge_id: judge
        end
      end

    else

      unscored = Heat.where.not(number: scored).where.not(number: ...0).where.not(category: "Solo").order(:number).pluck(:id)

      @event = Event.last
      if @event.ballrooms > 1
        eligable = {
          A: judges.select {|judge| Person.find(judge).judge&.ballroom != 'B'},
          B: judges.select {|judge| Person.find(judge).judge&.ballroom != 'A'}
        }
      end

      if @event.ballrooms > 1 && Judge.where.not(ballroom: 'Both').any? && !eligable[:A].empty? && !eligable[:B].empty?
        counts = judges.map {|id| [id, 0]}.to_h
        unscored = Heat.where.not(number: scored).where.not(number: ...0).where.not(category: "Solo").order(:number).group_by(&:number)
        unscored.each do |number, heats|
          assign_rooms(@event.ballrooms, heats).each do |room, heats|
            heats.each do |heat|
              judge = counts.sort_by(&:last).find {|id, count| eligable[room].include? id}.first
              counts[judge] += 1
              Score.create! heat_id: heat.id, judge_id: judge
            end
          end
        end
      else
        unscored = Heat.where.not(number: scored).where.not(number: ...0).where.not(category: "Solo").order(:number).pluck(:id)

        queue = []
        Score.transaction do
          unscored.each do |heat_id|
            queue = judges.dup if queue.empty?
            Score.create! heat_id: heat_id, judge_id: queue.pop
          end
        end
      end

    end

    redirect_to person_path(params[:id]), notice: "#{unscored.count} entries assigned to #{judges.count} judges."
  end

  def reset_assignments
    Score.where(value: nil, comments: nil, good: nil, bad: nil).delete_all

    redirect_to person_path(params[:id]), :notice => "Assignments cleared"
  end

  # DELETE /people/1 or /people/1.json
  def destroy
    studio = @person.studio

    if not Event.first.locked?
      @person.destroy

      notice = "#{@person.display_name} was successfully removed."
    else
      @heats = list_heats
      count = @heats.count {|heat| heat.number < 0}
      if count > 0
        Heat.transaction do
          @heats.each do |heat|
            heat.update(number: -heat.number) if heat.number < 0
          end
        end
        notice = "#{count} heats successfully restored."
      else
        count = @heats.count {|heat| heat.number > 0}
        Heat.transaction do
          @heats.each do |heat|
            heat.update(number: -heat.number) if heat.number > 0
          end
        end
        notice = "#{count} heats successfully scratched."
      end
    end

    respond_to do |format|
      format.html { redirect_to (studio ? studio_url(studio) : root_url),
        status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_person
      @person = Person.find(params[:id])
      @studio = @person.studio
    end

    # Only allow a list of trusted parameters through.
    def person_params
      params.require(:person).permit(:name, :studio_id, :type, :back, :level_id, :age_id, :category, :role, :exclude_id, :package_id, :independent, options: {})
    end

    def filtered_params(person)
      base = {
        name: person[:name],
        studio_id: person[:studio_id],
        type: person[:type],
        level: person[:level_id] && Level.find(person[:level_id]),
        age_id: person[:age_id],
        role: person[:role],
        back: person[:back],
        exclude_id: person[:exclude_id],
        package_id: person[:package_id],
        independent: person[:independent]
      }

      unless %w(Student).include? base[:type]
        base.delete :level
        base.delete :age_id
      end

      unless %w(Professional Student).include? base[:type]
        base.delete :role
        base.delete :back
      end

      unless base[:type] == 'Professional' && @event&.independent_instructors
        base.delete :independent
      end

      base
    end

    def selections
      @event = Event.last

      @studios = Studio.all.map{|studio| [studio.name, studio.id]}.to_h
      @types ||= %w[Student Guest Professional Judge DJ Emcee Official Organizer]
      @roles = %w[Follower Leader Both]

      @ages = Age.all.order(:id).map {|age| [age.description, age.id]}
      @levels = Level.all.order(:id).map {|level| [level.name, level.id]}
      if @event.solo_level_id
        @levels.select! {|name, id| id < @event.solo_level_id}
      end

      @exclude = Person.where(studio: @person.studio).order(:name).to_a
      @exclude.delete(@person)
      @exclude = @exclude.map {|exclude| [exclude.name, exclude.id]}

      @packages = Billable.where(type: @person.type).order(:order).pluck(:name, :id)

      unless @packages.empty?
        if %w(Student Professional).include? @person.type
          @packages.unshift ['', ''] unless @event.package_required and @person.active?
        else
          @packages.unshift ['', ''] unless @event.package_required
        end
      end

      @person.default_package

      @options = Billable.where(type: 'Option').order(:order)

      if @person.package_id
        package = @person.package || Billable.find(@person.package_id)
        @package_options = package.package_includes.map(&:option)
      else
        @package_options = []
      end

      @person_options = @person.options.group_by(&:option).
        map {|option, list| [option, list.length]}.to_h

      @track_ages = @event.track_ages
      @include_independent_instructors = @event.independent_instructors
    end

    def sort_order
      order = params[:sort] || 'name'
      order = 'studios.name' if order == 'studio'
      order = 'age_id' if order == 'age'
      order = 'level_id' if order == 'level'
      order = 'name' if %w(heats solos multis).include? order
      order
    end

    def set_exclude
      if @person.exclude_id != person_params[:exclude_id].to_i
        if @person.exclude_id
          @person.exclude.exclude = nil
          @person.exclude.save!
        end

        if person_params[:exclude_id] and not person_params[:exclude_id].empty?
          exclude = Person.find(person_params[:exclude_id])

          if exclude.exclude
            exclude.exclude.exclude = nil
            exclude.exclude.save!
          end

          exclude.exclude = @person
          exclude.save!
        end
      end
    end

    def update_options
      desired_options = person_params[:options] || {}
      current_options = @person.options.group_by(&:option_id)
      Billable.where(type: 'Option').each do |option|
        got = current_options[option.id]&.length || 0
        want = desired_options[option.id.to_s].to_i

        while got < want
          PersonOption.create! person: @person, option: option
          got += 1
        end

        while got > want
          current_options[option.id].pop.destroy
          got -= 1
        end
      end
    end

    def list_heats
      Heat.joins(:entry).where(entry: {follow_id: @person.id}).
        or(Heat.joins(:entry).where(entry: {lead_id: @person.id}))
    end
end
