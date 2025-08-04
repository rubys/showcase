class FormationsController < ApplicationController
  before_action :set_formation, only: %i[ show edit update destroy ]
  include EntryForm
  include ActiveStorage::SetCurrent

  permit_site_owners *%i[ show ], trust_level: 25
  permit_site_owners *%i[ new edit update create destroy ], trust_level: 50

  # GET /formations or /formations.json
  def index
    @formations = Formation.all
  end

  # GET /formations/1 or /formations/1.json
  def show
  end

  # GET /formations/new
  def new
    @solo ||= Solo.new
    @formation = [nil]

    if params[:studio]
      @studio = Studio.find(params[:studio])
    end

    form_init(params[:primary])
    @levels.push ["All Levels", 0]
    @ages.push ["All Ages", 0]

    @dances = Dance.by_name.all.map {|dance| [dance.name, dance.id]}

    @partner = nil
    @age = @person&.age_id
    @level = @person&.level_id
    @on_floor = true

    # if there is only one instructor, select a student as a partner so
    # the instructors box can be filled in
    if @instructors.length == 1
      @partner = @students.find {|student| student.id != @person.id}&.id 
    end
  end

  # GET /formations/1/edit
  def edit
    @formation = @solo.formations.map {|record| record.person_id}
    form_init(params[:primary], @solo.heat.entry)
    @levels.push ["All Levels", 0]
    @ages.push ["All Ages", 0]

    @partner = @solo.heat.entry.partner(@person).id

    if Event.current.agenda_based_entries?
      dances = Dance.where(order: 0...).by_name

      @categories = dance_categories(@solo.heat.dance, true)

      @category = @solo.heat.dance.id

      if not dances.include? @solo.heat.dance
        @dance = dances.find {|dance| dance.name == @solo.heat.dance.name}&.id || @dance
      end

      @dances = dances.map {|dance| [dance.name, dance.id]}
    else
      @dances = Dance.by_name.all.pluck(:name, :id)
    end

    @instructor = @solo.heat.entry.instructor
    @age = @solo.heat.entry.age_id
    @level = @solo.heat.entry.level_id
    @dance = @solo.heat.dance.id
    @number = @solo.heat.number

    if @instructor and @formation.include? @instructor.id
      @formation.rotate! @formation.index(@instructor.id)
    end

    if (@solo.category_override_id || Category.where(routines: true).any?) && !Event.current.agenda_based_entries?
      @overrides = Category.where(routines: true).map {|category| [category.name, category.id]}
      cat = @solo.heat.dance.solo_category
      @overrides.unshift [cat.name, cat.id] if cat
    end

    @on_floor = @solo.formations.all? {|formation| formation.on_floor}
    @heat = params[:heat]
    @locked = Event.current.locked?
  end

  # POST /formations or /formations.json
  def create
    @formation = Formation.new(formation_params)

    respond_to do |format|
      if @formation.save
        format.html { redirect_to formation_url(@formation), notice: "Formation was successfully created." }
        format.json { render :show, status: :created, location: @formation }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @formation.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /formations/1 or /formations/1.json
  def update
    respond_to do |format|
      if @formation.update(formation_params)
        format.html { redirect_to formation_url(@formation), notice: "Formation was successfully updated." }
        format.json { render :show, status: :ok, location: @formation }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @formation.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /formations/1 or /formations/1.json
  def destroy
    @formation.destroy

    respond_to do |format|
      format.html { redirect_to formations_url, notice: "Formation was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_formation
      @solo = Solo.find(params[:id])
      @studio = @solo.heat.entry.subject.studio
    end

    # Only allow a list of trusted parameters through.
    def formation_params
      params.require(:formation).permit(:person_id, :solo_id)
    end
end
