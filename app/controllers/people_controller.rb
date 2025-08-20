class PeopleController < ApplicationController
  include Printable
  include Retriable

  before_action :set_person, only:
    %i[ show edit update destroy get_entries post_entries toggle_present ballroom review_solos remove_option invoice instructor_invoice ]

  permit_site_owners :show, :get_entries, trust_level: 25
  permit_site_owners :new, :create, :post_type, :edit, :update, :destroy,
    :post_entries, :instructor_invoice, :invoice,
    trust_level: 50

  def heats
    event = Event.current
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
    event = Event.current
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

    @event ||= Event.current
    @font_size = @event.font_size

    respond_to do |format|
      format.html { render 'studios/invoice' }
      format.pdf do
        render_as_pdf basename: "#{@person.display_name.gsub(/\W+/, '-')}-invoice"
      end
    end
  end

  def invoice
    @studio = @person.studio
    @student = @person if @person.type == 'Student'
    @instructor = @person
    generate_invoice([@studio], true, @person)

    @heat_cost = @studio.student_heat_cost || @studio.heat_cost || @event.heat_cost || 0
    @solo_cost = @studio.student_solo_cost || @studio.solo_cost || @event.solo_cost || 0
    @multi_cost = @studio.student_multi_cost || @studio.multi_cost || @event.multi_cost || 0

    @event ||= Event.current
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
      @studios = [['-- all studios --', nil]] + Studio.by_name.pluck(:name, :id)
    else
      @people = Person.joins(:studio).where(type: 'Student').order('studios.name', :name).to_a

      if not params[:person_id].blank?
        person_id = params[:person_id].to_i
        @people.select! {|person| person.id == person_id}
      elsif not params[:studio_id].blank?
        studio_id = params[:studio_id].to_i
        @people.select! {|person| person.studio_id == studio_id}
      end

      unless params[:template].content_type == 'application/pdf'
        flash[:alert] = "template must be a PDF file."
        @studios = [['-- all studios --', nil]] + Studio.by_name.pluck(:name, :id)
        render :certificates, status: :unprocessable_content
        return
      end

      pdf = CombinePDF.new
      @people.each do |name|
        pdf << CombinePDF.load(params[:template].tempfile.path)
      end

      pdf.pages.zip(@people) do |page, person|
        next unless person
        page.textbox person.display_name, height: params[:height].to_i, width: params[:width].to_i,
          y: params[:y].to_i, x: params[:x].to_i, font: :'Times-Bold', font_size: params['font-size'].to_i,
          font_color: params['font-color'].split(' ').map(&:to_i)
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
      Heat.joins(:entry).where(number: 0..).group(:category, 'entries.follow_id').count.to_a +
      Heat.joins(:entry).where(number: 0..).group(:category, 'entries.lead_id').count.to_a +
      Formation.pluck(:person_id).map {|id| [['Solo', id], 1]}

    counts.each do |(category, id), count|
      next unless @people.find {|person| person.id == id}

      list = case category
        when "Solo"
          @solos
        when "Multi"
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

    @track_ages = Event.current.track_ages

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
    people = Person.where(id: leaders).order(:name)

    pro_numbers = (params[:pro_numbers] || 101).to_i
    student_numbers = (params[:student_numbers] || 101).to_i

    Person.transaction do
      Person.where.not(back: nil).where.not(id: leaders).update_all(back: nil)

      people.each do |person|
        if person.type == "Student"
          person.back = student_numbers
          student_numbers += 1
        else
          person.back = pro_numbers
          pro_numbers += 1
        end

        person.save! validate: false
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
    if params[:sort] == 'amcouples'
      @people = Person.joins("INNER JOIN entries ON entries.instructor_id = people.id")
        .joins("INNER JOIN heats ON heats.entry_id = entries.id")
        .group("people.id")
        .order("COUNT(heats.id) DESC")

      pros = Person.includes(:studio).where(type: 'Professional').by_name
      @people += (pros - @people)
    else
     @people = Person.includes(:studio).where(type: 'Professional').order(sort_order)
    end
    
    @title = 'Professionals'

    @amcouples = Heat.joins(:entry).where.not(entries: {instructor_id: nil }).group('entries.instructor_id').count

    index
  end

  def staff
    @professionals = Person.includes(:studio).where(type: 'Professional').order(sort_order)
    @staff = Studio.find(0)
    @font_size = Event.current.font_size

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
    @track_ages = Event.current.track_ages
  end

  # GET /people/labels
  def labels
    @event = Event.current
    @people = Person.where.not(studio_id: nil).includes(:studio).order('studios.name', 'people.name COLLATE NOCASE').to_a
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
    @event = Event.current
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
    
    if package.type == 'Option'
      # For options, show all people who have access to this option (through packages or direct selection)
      @people = Person.with_option(package_id).includes(:studio).by_name
      @packages = package.option_included_by.map(&:package).sort_by {|package| [package.type, package.order]}
      @option = package
      
      # Strike through people who don't have the option selected AND aren't seated at a table for it
      @strike = @people.reject do |person| 
        person_option = PersonOption.find_by(person_id: person.id, option_id: package_id)
        # Include if they have a PersonOption record (selected or seated at table)
        person_option.present?
      end
    else
      # For packages, show people who have this package
      @people = package.people.includes(:studio).by_name
    end
    
    @title = "#{package.type} - #{package.name}"

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

    @dances = Dance.ordered.all.map {|dance|
      [dance, partners.map {|partner, entries|
        [partner, entries.map {|entry| entry.active_heats.count {|heat| heat.category != 'Solo' and heat.dance == dance}}.sum]
      }.to_h]
    }.select {|dance, partners| partners.values.any? {|count| count > 0}}.to_h

    @entries = partners
    @partners = partners.keys

    @routines = Category.where(routines: true).any? && !Event.current.agenda_based_entries?

    @heats = Heat.joins(:entry).
      includes(:dance, entry: [:lead, :follow]).
      where(entry: {lead: @person}).
      or(Heat.where(entry: {follow: @person})).
      or(Heat.where(id: Formation.joins(:solo).where(person: @person, on_floor: true).pluck(:heat_id))).
      order('abs(number)').to_a

    @solos = Solo.includes(:heat, :formations).all.map(&:heat) & @heats
    @solos.select! {|heat| heat.category == 'Solo'}

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
      @dancing_judge = Person.where(name: @person.name, type: "Professional").pluck(:id).first
    end

    @event = Event.current
    @track_ages = @event.track_ages

    @score_bgcolor = []
    if @event.open_scoring == '#'
      @score_range = @scores.values.map(&:keys).flatten.compact.sort.uniq
    elsif @event.open_scoring == '1'
      @score_range = ScoresController::SCORES['Closed'] + ScoresController::SCORES['Open']
      @score_bgcolor = ScoresController::SCORES['Closed']
    else
      @score_range = ScoresController::SCORES['Closed']
    end

    @disable_judge_assignments = true if ENV['RAILS_APP_DB'] == '2025-coquitlam-showcase'
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
    @locked = Event.current.locked?
    @heats = list_heats
    @return_to = params[:return_to]
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
      role: [seeking, 'Both']).by_name
    student = Person.where(type: 'Student', studio: @person.studio,
      role: [seeking, 'Both']).by_name

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
      Person.where(type: 'Student', studio_id: params[:studio_id].to_i).by_name.
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
        params[:studio] = @person.studio_id
        new
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @person.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /people/1 or /people/1.json
  def update
    selections

    set_exclude

    params[:independent] = false unless @event.independent_instructors

    update = filtered_params(person_params).except(:options)
    if update[:exclude_id] != nil and !update[:name]
      update = {exclude_id: update[:exclude_id]}
    end

    if params[:avail_direction] && params[:avail_direction] != "*"
      update[:available] = "#{params[:avail_direction]}#{params[:avail_date]}T#{params[:avail_time]}"
    else
      update[:available] = nil
    end

    respond_to do |format|
      if @person.update(update)
        update_options

        format.html { 
          redirect_url = params[:return_to].presence || person_url(@person)
          redirect_to redirect_url, notice: "#{@person.display_name} was successfully updated." 
        }
        format.json { render :show, status: :ok, location: @person }
      else
        edit
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @person.errors, status: :unprocessable_content }
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
        format.json { render json: { present: @person.present? }, status: :unprocessable_content }
      end
    end
  end

  def ballroom
    respond_to do |format|
      judge = Judge.find_or_create_by(person_id: @person.id)
      if judge.update({ballroom: params[:ballroom] || 'Both'})
        format.json { render json: { ballroom: judge.ballroom } }
      else
        format.json { render json: { ballroom: judge.ballroom }, status: :unprocessable_content }
      end
    end
  end

  def review_solos
    respond_to do |format|
      judge = Judge.find_or_create_by(person_id: @person.id)
      if judge.update({review_solos: params[:review_solos] || 'Both'})
        format.json { render json: { review_solos: judge.review_solos } }
      else
        format.json { render json: { review_solos: judge.review_solos }, status: :unprocessable_content }
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
    delete_judge_assignments_in_unscored_heats

    unless Person.includes(:judge).where(type: 'Judge').all.any?(&:present?)
      redirect_to person_path(params[:id]), alert: "No judges are marked as present."
      return
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

      @event = Event.current

      if Category.where.not(ballrooms: nil).any?
        @include_times = true  # Override for admin view
        generate_agenda unless @agenda
        cat_ballrooms = Category.pluck(:name, :ballrooms).to_h
        heat_ballrooms = @agenda.map {|cat, heats|
          [cat, heats.map {|heat, ballrooms| [heat, cat_ballrooms[cat] || @event.ballrooms]}]
        }.to_h.values.flatten(1).to_h
      else
        heat_ballrooms = {}
      end

      if @event.ballrooms > 1 || heat_ballrooms.any?
        eligable = {
          A: judges.select {|judge| Person.find(judge).judge&.ballroom != 'B'},
          B: judges.select {|judge| Person.find(judge).judge&.ballroom != 'A'}
        }
      end

      judge_dancers = Person.where(type: 'Judge').where.not(exclude_id: nil).pluck(:id, :exclude_id).to_h
      if judge_dancers.any?
        @include_times = true  # Override for admin view
        generate_agenda
        dancers = @heats.map {|number, heats| [number.to_f, heats.map {|heat| [heat.entry.lead_id, heat.entry.follow_id]}.flatten]}.to_h
      end

      counts = judges.map {|id| [id, 0]}.to_h
      queue = []
      unscored = Heat.where.not(number: scored).where.not(number: ...0).where.not(category: "Solo").order(:number).group_by(&:number)
      splittable = Judge.where.not(ballroom: 'Both').any? && !eligable[:A].empty? && !eligable[:B].empty?

      Score.transaction do
        unscored.each do |number, heats|
          ballrooms = splittable ? (heat_ballrooms[heats.first.number] || @event.ballrooms) : 1
          if ballrooms > 1
            assign_rooms(ballrooms, heats, -number).each do |room, heats|
              heats.each do |heat|
                judge = counts.sort_by(&:last).find {|id, count| eligable[room.to_sym].include? id}.first
                counts[judge] += 1
                redo if judge_dancers.include?(judge) and dancers[number.to_f].include?(judge_dancers[judge])
                Score.create! heat_id: heat.id, judge_id: judge
              end
            end
          else
            heats.each do |heat|
              queue = judges.dup if queue.empty?
              judge = queue.pop
              redo if judge_dancers.include?(judge) and dancers[number].include?(judge_dancers[judge])
              Score.create! heat_id: heat.id, judge_id: judge
            end
          end
        end
      end
    end

    redirect_to person_path(params[:id]), notice: "#{unscored.count} entries assigned to #{judges.count} judges."
  end

  def reset_assignments
    delete_judge_assignments_in_unscored_heats

    redirect_to person_path(params[:id]), :notice => "Assignments cleared"
  end

  # DELETE /people/1 or /people/1.json
  def destroy
    studio = @person.studio

    if not Event.current.locked?
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
      @person
    end

    # Only allow a list of trusted parameters through.
    def person_params
      params.expect(person: [:name, :studio_id, :type, :back, :level_id, :age_id, :category, :role, :exclude_id, :package_id, :independent, :invoice_to_id, :available, :table_id, { options: {} }])
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
        independent: person[:independent],
        invoice_to_id: person[:invoice_to_id],
        table_id: person[:table_id]
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
      @event = Event.current

      @studios = Studio.all.map{|studio| [studio.name, studio.id]}.to_h
      @types ||= %w[Student Guest Professional Judge DJ Emcee Official Organizer]
      @roles = %w[Follower Leader Both]

      @ages = Age.all.order(:id).map {|age| [age.description, age.id]}
      @levels = Level.all.order(:id).map {|level| [level.name, level.id]}
      if @event.solo_level_id
        @levels.select! {|name, id| id < @event.solo_level_id}
      end

      @exclude = Person.where(studio: @person.studio).by_name.to_a
      @exclude.delete(@person)
      @exclude = @exclude.map {|exclude| [exclude.name, exclude.id]}

      @invoiceable = Person.where(studio: @person.studio, type: 'Student', invoice_to: nil).
        where.not(id: @person.id).by_name.to_a
      related = @invoiceable.select {|person| person.last_name == @person.last_name}
      @invoiceable = (related + (@invoiceable - related)).map {|person| [person.name, person.id]}

      @packages = Billable.where(type: @person.type).ordered.pluck(:name, :id)
      
      # Add table options for all person types
      if Table.exists?
        @tables = Table.where(option: nil).includes(:people).order(:number).map do |table|
          ["Table #{table.number} - #{table.name}", table.id]
        end
      end

      unless @packages.empty?
        if %w(Student Professional).include? @person.type
          @packages.unshift ['', ''] unless @event.package_required and @person.active?
        else
          @packages.unshift ['', ''] unless @event.package_required
        end
      end

      @person.default_package

      @options = Billable.where(type: 'Option').ordered

      if @person.package_id
        package = @person.package || Billable.find(@person.package_id)
        @package_options = package.package_includes.map(&:option)
      else
        @package_options = []
      end

      @person_options = @person.options.group_by(&:option).
        map {|option, list| [option, list.length]}.to_h
      
      # Get person's current option table assignments
      @person_option_tables = PersonOption.where(person: @person).includes(:table).map do |po|
        [po.option_id, po.table_id]
      end.to_h
      
      # Get available tables for each option with capacity information
      @option_tables = {}
      @option_table_capacities = {}
      @options.each do |option|
        tables = Table.where(option: option).includes(:person_options => {:person => :studio})
        if tables.any?
          @option_tables[option.id] = []
          @option_table_capacities[option.id] = {}
          
          # Collect table data for sorting
          table_data = tables.map do |table|
            # Calculate table capacity info
            table_size = table.computed_table_size
            
            # Count people assigned to this table for this option
            people_count = table.person_options.count
            
            # Calculate capacity status and corresponding Unicode symbol
            capacity_status, capacity_symbol = if people_count < table_size
              ['empty_seats', '🟢']
            elsif people_count == table_size
              ['at_capacity', '🟡']
            else
              ['over_capacity', '🔴']
            end
            
            # Check if this table has people from the same studio as the current person
            has_same_studio = table.person_options.joins(:person).exists?(people: { studio_id: @person.studio_id })
            
            # Assign sort priority for capacity status (lower number = higher priority)
            capacity_priority = case capacity_status
            when 'empty_seats' then 1
            when 'at_capacity' then 2
            when 'over_capacity' then 3
            end
            
            {
              table: table,
              table_size: table_size,
              people_count: people_count,
              capacity_status: capacity_status,
              capacity_symbol: capacity_symbol,
              has_same_studio: has_same_studio,
              capacity_priority: capacity_priority
            }
          end
          
          # Sort tables by: 1) Same studio (true first), 2) Capacity priority, 3) Table number
          sorted_table_data = table_data.sort_by do |data|
            [
              data[:has_same_studio] ? 0 : 1,  # Same studio tables first (0 sorts before 1)
              data[:capacity_priority],         # Empty seats, then at capacity, then over capacity
              data[:table].number               # Table number ascending
            ]
          end
          
          # Build the final arrays using sorted data
          sorted_table_data.each do |data|
            table = data[:table]
            @option_tables[option.id] << ["#{data[:capacity_symbol]} Table #{table.number} - #{table.name} (#{data[:people_count]}/#{data[:table_size]})", table.id]
            @option_table_capacities[option.id][table.id] = data[:capacity_status]
          end
        end
      end

      @track_ages = @event.track_ages
      @include_independent_instructors = @event.independent_instructors

      if Event.current.date.blank?
        @date_range = []
      elsif Event.current.date =~ /(\d{4})-(\d{2})-(\d{2}) - (\d{4})-(\d{2})-(\d{2})/
        start = Date.new($1.to_i, $2.to_i, $3.to_i)
        finish = Date.new($4.to_i, $5.to_i, $6.to_i)
        @date_range = (start..finish).map {|date| date.strftime('%Y-%m-%d')}
      else
        @date_range = [Event.parse_date(Event.current.date).strftime('%Y-%m-%d')]
      end

      if @person.available =~ /([<>])(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/
        @avail_direction = $1
        @avail_date = $2
        @avail_time = $3
      else
        @avail_date = @date_range.first
        @avail_time = "12:00"
      end
    end

    def sort_order
      order = params[:sort] || 'name COLLATE NOCASE'
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
      option_tables = params[:person][:option_tables] || {}
      current_options = @person.options.group_by(&:option_id)
      
      Billable.where(type: 'Option').each do |option|
        got = current_options[option.id]&.length || 0
        want = desired_options[option.id.to_s].to_i
        table_id = option_tables[option.id.to_s].presence

        # Create new PersonOption records as needed
        while got < want
          PersonOption.create! person: @person, option: option, table_id: table_id
          got += 1
        end

        # Remove excess PersonOption records
        while got > want
          current_options[option.id].pop.destroy
          got -= 1
        end
        
        # Update table assignment for existing PersonOption records
        if got > 0 && current_options[option.id]
          current_options[option.id].each do |person_option|
            if person_option.table_id != table_id
              person_option.update(table_id: table_id)
            end
          end
        end
      end
    end

    def list_heats
      Heat.joins(:entry).where(entry: {follow_id: @person.id}).
        or(Heat.joins(:entry).where(entry: {lead_id: @person.id}))
    end

    def delete_judge_assignments_in_unscored_heats
      retry_transaction do
        # find heats that have scores with one or more of: a value, comments, good, or bad
        completed = Heat.joins(:scores)
          .where.not(scores: { value: nil, comments: nil, good: nil, bad: nil })
          .pluck(:number).uniq

        # delete scores that have no value, comments, good, or bad (i.e., are judge assignments)
        # and are not in completed heats
        Score.joins(:heat)
          .where(value: nil, comments: nil, good: nil, bad: nil)
          .where.not(heats: { number: completed })
          .delete_all

        # Use SQL to check for blank comments (NULL or only whitespace) using TRIM
        Score.joins(:heat)
          .where(value: nil, good: nil, bad: nil)
          .where("TRIM(COALESCE(comments, '')) = ''")
          .where.not(heats: { number: completed })
          .delete_all
      end
    end
end
