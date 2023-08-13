class FormationsController < ApplicationController
  before_action :set_formation, only: %i[ show edit update destroy ]
  include EntryForm

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

    form_init(params[:primary])

    @dances = Dance.order(:name).all.map {|dance| [dance.name, dance.id]}

    @partner = nil
    @age = @person&.age_id
    @level = @person&.level_id
    @on_floor = true

    # if there is only one instructor, select a student as a partner so
    # the instructors box can be filled in
    @partner = @students.find {|student| student.id != @person.id}.id if @instructors.length == 1
  end

  # GET /formations/1/edit
  def edit
    @formation = @solo.formations.map {|record| record.person_id}
    form_init(params[:primary], @solo.heat.entry)

    @partner = @solo.heat.entry.partner(@person).id

    @dances = Dance.order(:name).all.map {|dance| [dance.name, dance.id]}

    @instructor = @solo.heat.entry.instructor
    @age = @solo.heat.entry.age_id
    @level = @solo.heat.entry.level_id
    @dance = @solo.heat.dance.id
    @number = @solo.heat.number

    if @instructor and @formation.include? @instructor.id
      @formation.rotate! @formation.index(@instructor.id)
    end

    @on_floor = @solo.formations.all? {|formation| formation.on_floor}
    @heat = params[:heat]
  end

  # POST /formations or /formations.json
  def create
    @formation = Formation.new(formation_params)

    respond_to do |format|
      if @formation.save
        format.html { redirect_to formation_url(@formation), notice: "Formation was successfully created." }
        format.json { render :show, status: :created, location: @formation }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @formation.errors, status: :unprocessable_entity }
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
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @formation.errors, status: :unprocessable_entity }
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
    end

    # Only allow a list of trusted parameters through.
    def formation_params
      params.require(:formation).permit(:person_id, :solo_id)
    end
end
