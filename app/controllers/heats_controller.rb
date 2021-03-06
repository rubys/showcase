class HeatsController < ApplicationController
  include HeatScheduler
  include EntryForm
  include Printable
  
  skip_before_action :authenticate_user, only: %i[ mobile ]
  before_action :set_heat, only: %i[ show edit update destroy ]

  # GET /heats or /heats.json
  def index
    generate_agenda

    @solos = Solo.includes(:heat).order('heats.number').
      map {|solo| solo.heat.number}

    @stats = @heats.group_by {|number, heats| heats.length}.
      map {|size, entries| [size, entries.map(&:first)]}.
      sort

    event = Event.last
    @ballrooms = event.ballrooms
    @track_ages = event.track_ages
    @column_order = event.column_order
  end

  def mobile
    index
    @event = Event.last
    @layout = 'mx-0'
    @nologo = true
  end

  def djlist
    @heats = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance)

    @agenda = @heats.group_by(&:dance_category).map do |category, heats|
      [heats.map {|heat| heat.number}.min, category&.name]
    end.to_h

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: "djlist"
      end
    end
  end

  # GET /heats/book or /heats/book.json
  def book
    @type = params[:type]
    @event = Event.last
    @ballrooms = Event.last.ballrooms
    index

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: @type == 'judget' ? 'judge-heat-book' : "master-heat-book"
      end
    end
  end

  # GET /heats/1 or /heats/1.json
  def show
  end

  # GET /heats/knobs
  def knobs
    @categories = Person.distinct.pluck(:category).compact.length
    @levels = Person.distinct.pluck(:level).compact.length
  end

  # POST /heats/redo
  def redo
    schedule_heats
    redirect_to heats_url, notice: "#{Heat.maximum(:number)} heats generated."
  end

  # GET /heats/new
  def new
    @heat ||= Heat.new
    form_init(params[:primary])
    @dances = Dance.order(:name).pluck(:name, :id).to_h
  end

  # GET /heats/1/edit
  def edit
    form_init(params[:primary], @heat.entry)

    @dances = Dance.order(:name).pluck(:name, :id).to_h
    
    @partner = @heat.entry.partner(@person).id
    @age = @heat.entry.age_id
    @level = @heat.entry.level_id
    @instructor = @heat.entry.instructor_id
  end

  # POST /heats or /heats.json
  def create
    @heat = Heat.new(heat_params)
    @heat.entry = find_or_create_entry(params[:heat])
    @heat.number ||= 0

    respond_to do |format|
      if @heat.save
        format.html { redirect_to heat_url(@heat), notice: "Heat was successfully created." }
        format.json { render :show, status: :created, location: @heat }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @heat.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /heats/1 or /heats/1.json
  def update
    entry = @heat.entry
    replace = find_or_create_entry(params[:heat])

    @heat.entry = replace
    @heat.number = 0

    respond_to do |format|
      if @heat.update(heat_params)
        format.html { redirect_to person_path(@person), notice: "Heat was successfully updated." }
        format.json { render :show, status: :ok, location: @heat }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @heat.errors, status: :unprocessable_entity }
      end
    end

    if replace != entry
      entry.reload
      entry.destroy if entry.heats.empty?
    end
  end

  # DELETE /heats/1 or /heats/1.json
  def destroy
    if @heat.number != 0
      notice = "Heat was successfully #{@heat.number < 0 ? 'restored' : 'scratched'}."
      @heat.update(number: -@heat.number)
    elsif @heat.entry.heats.length == 1
      @heat.entry.destroy
      notice = "Heat was successfully removed."
    else
      @heat.destroy
      notice = "Heat was successfully removed."
    end
    

    respond_to do |format|
      format.html { redirect_to params[:primary] ? person_url(params[:primary]) : heats_url, 
        status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_heat
      @heat = Heat.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def heat_params
      params.require(:heat).permit(:number, :category, :dance_id)
    end
end
