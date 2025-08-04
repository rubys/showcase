class SongsController < ApplicationController
  before_action :set_song, only: %i[ show edit update destroy ]

  include ActiveStorage::SetCurrent

  # GET /songs or /songs.json
  def index
    @songs = Song.all
  end

  # GET /songs/1 or /songs/1.json
  def show
  end

  # GET /songs/new
  def new
    @song = Song.new
    @dances = Dance.order(:name).all.map {|dance| [dance.name, dance.id]}
  end

  # GET /songs/1/edit
  def edit
    @dances = Dance.order(:name).all.map {|dance| [dance.name, dance.id]}
  end

  # POST /songs or /songs.json
  def create
    @song = Song.new(song_params)
    @song.order = (Song.maximum(:order) || 0) + 1

    respond_to do |format|
      if @song.save
        format.html { redirect_to song_url(@song), notice: "Song was successfully created." }
        format.json { render :show, status: :created, location: @song }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @song.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /songs/1 or /songs/1.json
  def update
    respond_to do |format|
      if @song.update(song_params)
        format.html { redirect_to song_url(@song), notice: "Song was successfully updated." }
        format.json { render :show, status: :ok, location: @song }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @song.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /songs/1 or /songs/1.json
  def destroy
    dance_id = @song.dance_id
    @song.song_file.purge if @song.song_file.attached?
    @song.destroy

    respond_to do |format|
      format.html { redirect_to dance_songlist_path(dance_id), status: 303, notice: "Song was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def dancelist
    @dance = Dance.find(params[:dance])
    @heats = @dance.heats.select(:number).distinct.count
    @songs = @dance.songs.ordered
    @preload = 'auto'
  end

  def upload
    dance = Dance.find(params[:dance])

    order = Song.pluck(:order).max.to_i
    count = 0
    
    params[:song][:files].each do |file|
      next if file.blank?

      count += 1

      Song.create!(
        dance: dance,
        order: order + count,
        title: File.basename(file.original_filename).sub(/\.\w+\Z/, ''),
        song_file: file
      )
    end

    redirect_to dance_songlist_url(dance), notice: ""#{helpers.pluralize count, 'Song'} successfully uploaded."
  end

  # POST /dances/drop
  def drop
    source = Song.find(params[:source].to_i)
    target = Song.find(params[:target].to_i)

    if source.order > target.order
      songs = Song.where(order: target.order..source.order).ordered
      new_order = songs.map(&:order).rotate(1)
    else
      songs = Song.where(order: source.order..target.order).ordered
      new_order = songs.map(&:order).rotate(-1)
    end

    Song.transaction do
      songs.zip(new_order).each do |song, order|
        song.order = order
        song.save! validate: false
      end

      raise ActiveRecord::Rollback unless songs.all? {|song| song.valid?}
    end

    index
    flash.now.notice = "#{source.title} was successfully moved."

    params[:dance] = source.dance_id
    dancelist
    @preload = 'none'

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace('dancelist', 
        render_to_string(partial: 'list', layout: false))}
      format.html { redirect_to dance_songlist_url(source.dance) }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_song
      @song = Song.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def song_params
      params.require(:song).permit(:dance_id, :order, :title, :artist)
    end
end
