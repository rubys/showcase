class StudiosController < ApplicationController
  before_action :set_studio, only: %i[ show edit update unpair destroy ]

  # GET /studios or /studios.json
  def index
    @studios = Studio.all.order(:name)
  end

  # GET /studios/1 or /studios/1.json
  def show
  end

  # GET /studios/new
  def new
    @studio = Studio.new
    @pairs = @studio.pairs
    @avail = [nil] + Studio.all.map {|studio| studio.name}
  end

  # GET /studios/1/edit
  def edit
    @pairs = @studio.pairs
    @avail = [nil] + (Studio.all - @pairs).map {|studio| studio.name}
  end

  # POST /studios or /studios.json
  def create
    @studio = Studio.new(studio_params.except(:pair))

    respond_to do |format|
      if @studio.save
        add_pair
        format.html { redirect_to studio_url(@studio), notice: "Studio was successfully created." }
        format.json { render :show, status: :created, location: @studio }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @studio.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /studios/1 or /studios/1.json
  def update
    respond_to do |format|
      add_pair

      if @studio.update(studio_params.except(:pair))
        format.html { redirect_to studio_url(@studio), notice: "Studio was successfully updated." }
        format.json { render :show, status: :ok, location: @studio }
      else
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
        StudioPair.destroy_by(studio1: @studio, studio2: pair)
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
      params.require(:studio).permit(:name, :tables, :pair)
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
end
