class DancesController < ApplicationController
  before_action :set_dance, only: %i[ show edit update destroy ]

  # GET /dances or /dances.json
  def index
    @dances = Dance.all
    @heats = Heat.group(:dance_id).distinct.count(:number)
    @entries = Heat.group(:dance_id).count
  end

  # GET /dances/1 or /dances/1.json
  def show
  end

  # GET /dances/new
  def new
    @dance = Dance.new
  end

  # GET /dances/1/edit
  def edit
    @categories = [nil] + Category.order(:order).pluck(:name, :id)
  end

  # POST /dances or /dances.json
  def create
    @dance = Dance.new(dance_params)

    respond_to do |format|
      if @dance.save
        format.html { redirect_to dance_url(@dance), notice: "Dance was successfully created." }
        format.json { render :show, status: :created, location: @dance }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @dance.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /dances/1 or /dances/1.json
  def update
    respond_to do |format|
      if @dance.update(dance_params)
        format.html { redirect_to dance_url(@dance), notice: "Dance was successfully updated." }
        format.json { render :show, status: :ok, location: @dance }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @dance.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /dances/1 or /dances/1.json
  def destroy
    @dance.destroy

    respond_to do |format|
      format.html { redirect_to dances_url, notice: "Dance was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_dance
      @dance = Dance.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def dance_params
      params.require(:dance).permit(:name, :category)
    end
end
