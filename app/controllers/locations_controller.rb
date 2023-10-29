class LocationsController < ApplicationController
  before_action :set_location, only: %i[ show edit update destroy ]

  # GET /locations or /locations.json
  def index
    @locations = Location.order(:key).all
  end

  # GET /locations/1 or /locations/1.json
  def show
  end

  # GET /locations/new
  def new
    @location ||= Location.new

    @users = User.order(:userid).pluck(:userid, :name1, :name2, :id).
    map do |userid, name1, name2, id|
      if name2.empty?
        ["#{userid}: #{name1}", id]
      else
        ["#{userid}: #{name1}/#{name2}", id]
      end
    end
  end

  # GET /locations/1/edit
  def edit
    new

    @showcases = @location.showcases.order(:year, :order).reverse.group_by(&:year)
  end

  # POST /locations or /locations.json
  def create
    @location = Location.new(location_params)

    respond_to do |format|
      if @location.save
        format.html { redirect_to locations_url, notice: "#{@location.name} was successfully created." }
        format.json { render :show, status: :created, location: @location }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @location.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /locations/1 or /locations/1.json
  def update
    respond_to do |format|
      if @location.update(location_params)
        format.html { redirect_to locations_url, notice: "#{@location.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @location }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @location.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /locations/1 or /locations/1.json
  def destroy
    @location.destroy

    respond_to do |format|
      format.html { redirect_to locations_url, notice: "#{@location.name} was successfully destroyed.", status: 303 }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_location
      @location = Location.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def location_params
      params.require(:location).permit(:key, :name, :latitude, :longitude, :user_id)
    end
end
