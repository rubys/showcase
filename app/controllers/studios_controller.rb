class StudiosController < ApplicationController
  before_action :set_studio, only: %i[ show edit update destroy ]

  # GET /studios or /studios.json
  def index
    @studios = Studio.all
  end

  # GET /studios/1 or /studios/1.json
  def show
  end

  # GET /studios/new
  def new
    @studio = Studio.new
  end

  # GET /studios/1/edit
  def edit
  end

  # POST /studios or /studios.json
  def create
    @studio = Studio.new(studio_params)

    respond_to do |format|
      if @studio.save
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
      if @studio.update(studio_params)
        format.html { redirect_to studio_url(@studio), notice: "Studio was successfully updated." }
        format.json { render :show, status: :ok, location: @studio }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @studio.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /studios/1 or /studios/1.json
  def destroy
    @studio.destroy

    respond_to do |format|
      format.html { redirect_to studios_url, notice: "Studio was successfully destroyed." }
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
      params.require(:studio).permit(:name)
    end
end
