class PeopleController < ApplicationController
  before_action :set_person, only: %i[ show edit update destroy ]

  # GET /people or /people.json
  def index
    @people = Person.all
  end

  # GET /people/backs or /people.json
  def backs
    @people = Person.where(role: %w(Leader Both)).
      sort_by {|person| person.back.to_s}
  end

  # GET /people/backs or /people.json
  def couples
    @couples = Entry.preload(:lead, :follow).joins(:lead, :follow).
      where(lead: {type: 'Student'}, follow: {type: 'Student'}).
      group_by {|entry| [entry.lead, entry.follow]}.
      map do |(lead, follow), entries| 
        [lead, follow, entries.sum {|entry| entry.count}]
      end.
      sort_by do |(lead, follow), count|
        level = lead.level.to_s
        (level.include?('Gold') ? 5 : 0) +
          (level.include?('Silver') ? 3 : 0) +
          (level.include?('Bronze') ? 1 : 0) +
          (level.include?('Full') ? 1 : 0)
      end
  end

  # GET /people/1 or /people/1.json
  def show
    @entries = @person.lead_entries + @person.follow_entries
    @partners = (@entries.map(&:follow) + @entries.map(&:lead)).uniq
    @partners.delete @person
    @partners = @partners.sort_by {|person| person.name.split(/,\s*/).last}.
      map {|partner| [partner, @entries.select {|entry|
        entry.lead == partner || entry.follow == partner
      }]}.to_h
    @dances = Dance.all
    @entries = @dances.map {|dance|
      [dance, @partners.map {|partner, entries|
        [partner, entries.select {|entry| entry.dance == dance}.sum(&:count)]
      }.to_h]
    }.to_h
    @partners = @partners.keys

    @meals = []
    @meals << 'Friday dinner' if @person.friday_dinner
    @meals << 'Saturday lunch' if @person.saturday_lunch
    @meals << 'Saturday dinner' if @person.saturday_dinner
    @meals << 'none' if @meals.empty?
    @meals = @meals.join(', ')

    @heats = Heat.joins(:entry).
      where(entry: {lead: @person}).
      or(Heat.where(entry: {follow: @person})).
      order(:number).to_a
  end

  # GET /people/new
  def new
    @person = Person.new

    selections

    if params[:studio]
      @person.studio_id = params[:studio]
    end
  end

  # GET /people/1/edit
  def edit
    selections
  end

  # POST /people or /people.json
  def create
    @person = Person.new(person_params)
    selections

    respond_to do |format|
      if @person.save
        format.html { redirect_to person_url(@person), notice: "Person was successfully created." }
        format.json { render :show, status: :created, location: @person }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @person.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /people/1 or /people/1.json
  def update
    selections

    respond_to do |format|
      if @person.update(person_params)
        format.html { redirect_to person_url(@person), notice: "Person was successfully updated." }
        format.json { render :show, status: :ok, location: @person }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @person.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /people/1 or /people/1.json
  def destroy
    @person.destroy

    respond_to do |format|
      format.html { redirect_to people_url, notice: "Person was successfully destroyed." }
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
      params.require(:person).permit(:name, :studio_id, :type, :back, :level, :category, :role, :friday_dinner, :saturday_lunch, :saturday_dinner)
    end

    def selections
      @studios = Studio.all.map{|studio| [studio.name, studio.id]}.to_h
      @types = %w[Student Guest Professional Judge Emcee]
      @roles = %w[Follower Leader Both]
      @levels = [
        'Assoc. Bronze',
        'Full Bronze',
        'Assoc. Silver',
        'Full Silver',
        'Assoc. Gold',
        'Full Gold',
      ]
    end
end
