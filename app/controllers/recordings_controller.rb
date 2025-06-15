class RecordingsController < ApplicationController
  before_action :set_recording, only: %i[ show edit update destroy ]

  # GET /recordings or /recordings.json
  def index
    @recordings = Recording.all
  end

  # GET /recordings/1 or /recordings/1.json
  def show
  end

  # GET /recordings/new
  def new
    @recording = Recording.new
  end

  # GET /recordings/1/edit
  def edit
  end

  # POST /recordings or /recordings.json
  def create
    @recording = Recording.new(recording_params)

    respond_to do |format|
      if @recording.save
        format.html { redirect_to @recording, notice: "Recording was successfully created." }
        format.json { render :show, status: :created, location: @recording }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @recording.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /recordings/1 or /recordings/1.json
  def update
    respond_to do |format|
      if @recording.update(recording_params)
        format.html { redirect_to @recording, notice: "Recording was successfully updated." }
        format.json { render :show, status: :ok, location: @recording }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @recording.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /recordings/1 or /recordings/1.json
  def destroy
    @recording.destroy!

    respond_to do |format|
      format.html { redirect_to recordings_path, status: :see_other, notice: "Recording was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_recording
      @recording = Recording.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def recording_params
      params.expect(recording: [ :judge_id, :heat_id, :audio ])
    end
end
