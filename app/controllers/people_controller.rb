class PeopleController < ApplicationController
  include Printable
  
  before_action :set_person, only: 
    %i[ show edit update destroy get_entries post_entries ]

  def heats
    @ballrooms = Event.last.ballrooms
    heat_sheets
  end

  def individual_heats
    @ballrooms = Event.last.ballrooms
    @people = [set_person]
    heat_sheets
    render :heats
  end

  def scores
    score_sheets
  end

  def individual_scores
    @people = [set_person]
    score_sheets
    render :scores
  end

  # GET /people or /people.json
  def index
    @people ||= Person.includes(:studio).order(sort_order)

    @heats = (Heat.joins(:entry).group('entries.follow_id').count).merge(
      Heat.joins(:entry).group('entries.lead_id').count)

    if params[:sort] == 'heats'
      @people = @people.to_a.sort_by! {|person| @heats[person.id] || 0}
    end

    render :index
  end

  # GET /people/backs or /people.json
  def backs
    @people = Person.where(role: %w(Leader Both)).order(:back)
  end

  def assign_backs
    @people = Person.where(role: %w(Leader Both)).order(:type, :name)

    number = 101
    Person.transaction do
      @people.each do |person|
        number = 201 if number < 200 and person.type == "Student"
        person.back = number
        person.save! validate: false
        number += 1
      end

      raise ActiveRecord::Rollback unless @people.all? {|person| person.valid?}
    end

    redirect_to backs_people_path 
  end

  # GET /people/students or /students.json
  def students
    @people = Person.includes(:studio).where(type: 'Student').order(sort_order)
    @title = 'Students'

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
  end

  # GET /people/1 or /people/1.json
  def show
    Dance.all
    Person.all

    entries = @person.lead_entries + @person.follow_entries
    partners = (entries.map(&:follow) + entries.map(&:lead)).uniq
    partners.delete @person
    partners = partners.sort_by {|person| person.name.split(/,\s*/).last}.
      map {|partner| [partner, entries.select {|entry|
        entry.lead == partner || entry.follow == partner
      }]}.to_h

    heats = entries.map {|entry| entry.heats}.flatten

    @dances = Dance.order(:order).all.map {|dance|
      [dance, partners.map {|partner, entries|
        [partner, entries.map {|entry| entry.heats.count {|heat| heat.dance == dance}}.sum]
      }.to_h]
    }.select {|dance, partners| partners.values.any? {|count| count > 0}}.to_h

    @entries = partners
    @partners = partners.keys

    @heats = Heat.joins(:entry).
      includes(:dance, entry: [:lead, :follow]).
      where(entry: {lead: @person}).
      or(Heat.where(entry: {follow: @person})).
      or(Heat.where(id: Formation.joins(:solo).where(person: @person).pluck(:heat_id))).
      order(:number).to_a

    @solos = Solo.includes(:heat).all.map(&:heat) & @heats

    @scores = Score.joins(heat: :entry).
      where(entry: {follow_id: @person.id}).or(
        Score.joins(heat: :entry).where(entry: {lead_id: @person.id})
      ).group(:value, :dance_id).order(:dance_id).
      count(:value).
      group_by {|(value, dance), count| dance}.
      map {|dance, list| [dance, list.map {|(value, dance), count|
        [value, count]
      }.to_h]}.to_h
  end

  # GET /people/new
  def new
    @person ||= Person.new

    if params[:studio]
      @types = %w[Student Professional Guest]
      @person.studio_id = params[:studio]
    else
      @types = %w[Judge Emcee]
    end

    selections
  end

  # GET /people/1/edit
  def edit
    selections
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

  def post_type
    if params[:id]
      @person = Person.find(params[:id])
    else
      @person = Person.new
    end

    @person.type = params[:type]

    selections

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace('package-select', 
        render_to_string(partial: 'package'))}
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

        format.html { redirect_to person_url(@person), notice: "#{@person.display_name} was successfully added." }
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

  # DELETE /people/1 or /people/1.json
  def destroy
    studio = @person.studio
    @person.destroy

    respond_to do |format|
      format.html { redirect_to (studio ? studio_url(studio) : root_url),
         status: 303, notice: "#{@person.display_name} was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_person
      @person = Person.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def person_params
      params.require(:person).permit(:name, :studio_id, :type, :back, :level_id, :age_id, :category, :role, :exclude_id, :package_id, options: {})
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
        package_id: person[:package_id]
      }

      unless %w(Professional Student Guest).include? base[:type]
        base.delete :studio_id
      end

      unless %w(Student).include? base[:type]
        base.delete :level
        base.delete :age_id
      end

      unless %w(Professional Student).include? base[:type]
        base.delete :role
        base.delete :back
      end

      base
    end

    def selections
      @studios = Studio.all.map{|studio| [studio.name, studio.id]}.to_h
      @types = %w[Student Guest Professional Judge Emcee]
      @roles = %w[Follower Leader Both]

      @ages = Age.all.order(:id).map {|age| [age.description, age.id]}
      @levels = Level.all.order(:id).map {|level| [level.name, level.id]}

      @exclude = Person.where(studio: @person.studio).order(:name).to_a
      @exclude.delete(@person)
      @exclude = @exclude.map {|exclude| [exclude.name, exclude.id]}

      if %w(Student Guest).include? @person.type
        @packages = Billable.where(type: @person.type).order(:order).pluck(:name, :id)
      else
        @packages = []
      end

      @options = Billable.where(type: 'Option').order(:order)

      if @person.package_id
        @package_options = @person.package.package_includes.map(&:option)
      else
        @package_options = []
      end

      @person_options = @person.options.map(&:option)
    end

    def sort_order
      order = params[:sort] || 'name'
      order = 'studios.name' if order == 'studio'
      order = 'age_id' if order == 'age'
      order = 'level_id' if order == 'level'
      order = 'name' if order == 'heats'
      order
    end

    def set_exclude
      if @person.exclude_id != person_params[:exclude_id].to_i
        if @person.exclude_id
          @person.exclude.exclude = nil
          @person.exclude.save!
        end
  
        unless person_params[:exclude_id].empty?
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
      current_options = @person.options.map(&:option_id)
      Billable.where(type: 'Option').each do |option|
        if desired_options[option.id.to_s].to_i == 1
          unless current_options.include? option.id
            PersonOption.create! person: @person, option: option
          end
        else
          if current_options.include? option.id
            PersonOption.destroy_by person: @person, option: option
          end
        end
      end
    end
end
