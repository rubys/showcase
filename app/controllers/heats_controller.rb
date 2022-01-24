class HeatsController < ApplicationController
  before_action :set_heat, only: %i[ show edit update destroy ]

  # GET /heats or /heats.json
  def index
    @heats = Heat.order(:number).eager_load({entry: [:dance, :lead, :follow]}).
      group_by {|heat| heat[:number]}.map do |number, heats|
      [number, heats.sort_by {|heat| heat.entry.lead.back}.map do |heat|
        entry = heat.entry
        if entry.lead.type == 'Professional'
          subject = entry.follow
          category = "L - #{subject.category}"
        elsif entry.follow.type == 'Professional'
          subject = entry.lead
          category = "G - #{subject.category}"
        else
          subject = entry.lead
          category = "AC - #{subject.category}"
        end

        [entry, category, subject]
      end]
    end
  end

  # GET /heats/1 or /heats/1.json
  def show
  end

  # GET /heats/new
  def new
    @heat = Heat.new
  end

  # GET /heats/1/edit
  def edit
  end

  # POST /heats or /heats.json
  def create
    @heat = Heat.new(heat_params)

    respond_to do |format|
      if @heat.save
        format.html { redirect_to heat_url(@heat), notice: "Heat was successfully created." }
        format.json { render :show, status: :created, location: @heat }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @heat.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /heats/1 or /heats/1.json
  def update
    respond_to do |format|
      if @heat.update(heat_params)
        format.html { redirect_to heat_url(@heat), notice: "Heat was successfully updated." }
        format.json { render :show, status: :ok, location: @heat }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @heat.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /heats/1 or /heats/1.json
  def destroy
    @heat.destroy

    respond_to do |format|
      format.html { redirect_to heats_url, notice: "Heat was successfully destroyed." }
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
      params.require(:heat).permit(:number, :entry_id)
    end
end
