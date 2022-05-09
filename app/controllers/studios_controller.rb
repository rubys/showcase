class StudiosController < ApplicationController
  include Printable

  before_action :set_studio, only: %i[ show edit update unpair destroy heats scores invoice ]

  # GET /studios or /studios.json
  def index
    @studios = Studio.all.order(:name)
    @tables = Studio.sum(:tables)
  end

  # GET /studios/1 or /studios/1.json
  def show
  end

  def heats
    @people = @studio.people
    heat_sheets
    render 'people/heats'
  end

  def scores
    @people = @studio.people
    score_sheets
    render 'people/scores'
  end

  def invoice
    @event = Event.last

    @people = @studio.people.where(type: ['Student', 'Guest']).order(:name)

    @cost = {
      'Closed' => @studio.heat_cost || @event.heat_cost || 0,
      'Open' => @studio.heat_cost || @event.heat_cost || 0,
      'Solo' => @studio.solo_cost || @event.solo_cost || 0,
      'Multi' => @studio.multi_cost || @event.multi_cost || 0
    }

    entries = (Entry.joins(:follow).where(people: {type: 'Student', studio: @studio}) +
      Entry.joins(:lead).where(people: {type: 'Student', studio: @studio})).uniq

    @dances = @people.map {|person| [person, {dances: 0, cost: 0}]}.to_h

    @dance_count = 0

    entries.each do |entry|
      if entry.lead.type == 'Student' and entry.follow.type == 'Student'
        split = 2
      else
        split = 1
      end

      entry.heats.each do |heat|
        if entry.lead.type == 'Student'
          @dances[entry.lead][:dances] += 1
          @dances[entry.lead][:cost] += @cost[heat.category] / split
        end

        if entry.follow.type == 'Student'
          @dances[entry.follow][:dances] += 1
          @dances[entry.follow][:cost] += @cost[heat.category] / split
        end
      end

      @dance_count += entry.heats.length
    end

    @entries = Entry.where(id: entries.map(&:id)).
      order(:levei_id, :age_id).
      includes(lead: [:studio], follow: [:studio], heats: [:dance]).group_by {|entry| 
         entry.follow.type == "Student" ? [entry.follow.name, entry.lead.name] : [entry.lead.name, entry.follow.name]
       }.sort_by {|key, value| key}

    @purchases_made = @people.any? {|person| person.package_id} or
      @people.any? {|person| not person.options.empty?}
  end

  # GET /studios/new
  def new
    @studio ||= Studio.new
    @pairs = @studio.pairs
    @avail = Studio.all.map {|studio| studio.name}
    @cost_override = !!(@studio.heat_cost || @studio.solo_cost || @studio.multi_cost)

    event = Event.last
    @studio.heat_cost ||= event.heat_cost
    @studio.solo_cost ||= event.solo_cost
    @studio.multi_cost ||= event.multi_cost
  end

  # GET /studios/1/edit
  def edit
    new
  end

  # POST /studios or /studios.json
  def create
    @studio = Studio.new(studio_params.except(:pair, :cost_override))

    cost_override

    respond_to do |format|
      if @studio.save
        add_pair
        format.html { redirect_to studio_url(@studio), notice: "#{@studio.name} was successfully created." }
        format.json { render :show, status: :created, location: @studio }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @studio.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /studios/1 or /studios/1.json
  def update
    respond_to do |format|
      add_pair
      cost_override

      if @studio.update(studio_params.except(:pair, :cost_override))
        format.html { redirect_to studio_url(@studio), notice: "#{@studio.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @studio }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @studio.errors, status: :unprocessable_entity }
      end
    end
  end

  def unpair
    pair = params.require(:pair)
    if pair
      pair = Studio.find_by(name: pair)
      if pair and @studio.pairs.include? pair
        StudioPair.destroy_by(studio1: @studio, studio2: pair)
        StudioPair.destroy_by(studio2: @studio, studio1: pair)
        redirect_to edit_studio_url(@studio), notice: "#{pair.name} was successfully unpaired."
      end
    end
  end

  # DELETE /studios/1 or /studios/1.json
  def destroy
    @studio.destroy

    respond_to do |format|
      format.html { redirect_to studios_url, status: 303,
         notice: "#{@studio.name} was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_studio
      @studio = Studio.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def studio_params
      params.require(:studio).permit(:name, :tables, :pair, :cost_override, :heat_cost, :solo_cost, :multi_cost)
    end

    def add_pair
      pair = studio_params.delete :pair
      if pair
        pair = Studio.find_by(name: pair)
        if pair and not @studio.pairs.include? pair
          pair = StudioPair.new(studio1: @studio, studio2: pair)
          pair.save!
        end
      end
    end

    def cost_override
      if studio_params[:cost_override] == '0'
        params[:studio][:heat_cost] = nil
        params[:studio][:solo_cost] = nil
        params[:studio][:multi_cost] = nil
      end
    end
end
