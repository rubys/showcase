class ShowcasesController < ApplicationController
  before_action :set_showcase, only: %i[ show edit update destroy ]

  # GET /showcases or /showcases.json
  def index
    @showcases = Showcase.all
  end

  # GET /showcases/1 or /showcases/1.json
  def show
  end

  # GET /showcases/new
  def new
    @showcase ||= Showcase.new

    @showcase.year ||= Showcase.maximum(:year) || Time.now.year

    @locations = Location.pluck(:name, :id)

    if params[:location]
      @showcase.location_id = params[:location]

      unless @showcase.location.showcases.any? {|showcase| showcase.year == @showcase.year}
        @showcase.name ||= 'Showcase'
        @showcase.key ||= 'showcase'
      end
    end
  end

  # GET /showcases/1/edit
  def edit
    new
  end

  # POST /showcases or /showcases.json
  def create
    @showcase = Showcase.new(showcase_params)

    @showcase.order = (Showcase.maximum(:order) || 0) + 1

    respond_to do |format|
      if @showcase.save
        format.html { redirect_to edit_location_url(@showcase.location),
          notice: "#{@showcase.name} was successfully created." }
        format.json { render :show, status: :created, location: @showcase }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @showcase.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /showcases/1 or /showcases/1.json
  def update
    respond_to do |format|
      if @showcase.update(showcase_params)
        format.html { redirect_to edit_location_url(@showcase.location),
          notice: "#{@showcase.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @showcase }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @showcase.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /showcases/1 or /showcases/1.json
  def destroy
    @showcase.destroy

    respond_to do |format|
      format.html { redirect_to edit_location_url(@showcase.location), status: 303,
        notice: "#{@showcase.name} was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_showcase
      @showcase = Showcase.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def showcase_params
      params.require(:showcase).permit(:year, :key, :name, :location_id)
    end
end
