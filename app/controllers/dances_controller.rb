class DancesController < ApplicationController
  before_action :set_dance, only: %i[ show edit update destroy ]

  # GET /dances or /dances.json
  def index
    @dances = Dance.includes(:open_category, :closed_category, :solo_category, :multi_category).order(:order).all
    @heats = Heat.where(number: 1..).group(:dance_id).distinct.count(:number)
    @entries = Heat.where(number: 1..).group(:dance_id).count
    @songs = Song.group(:dance_id).count

    @separate = @dances.select {|dance| dance.order < 0}.group_by(&:name)

    @dances.each do |dance|
      next if dance.order < 0
      separate = @separate[dance.name]
      next unless separate
      separate.each do |separate_dance|
        @heats[dance.id] = (@heats[dance.id] || 0) + (@heats[separate_dance.id] || 0)
        @entries[dance.id] = (@entries[dance.id] || 0) + (@entries[separate_dance.id] || 0)

        if @songs[dance.id] || @songs[separate_dance.id]
          @songs[dance.id] = (@songs[dance.id] || 0) + (@songs[separate_dance.id] || 0)
        end
      end
    end
  end

  # GET /dances/1 or /dances/1.json
  def show
  end

  # GET /dances/new
  def new
    @dance ||= Dance.new

    form_init
  end

  # GET /dances/1/edit
  def edit
    form_init

    @locked = Event.first.locked?
  end

  # POST /dances or /dances.json
  def create
    @dance = Dance.new(dance_params)

    @dance.order = (Dance.maximum(:order) || 0) + 1

    if dance_params[:multi]
      dance_params[:multi].each do |dance, count|
        next if count.to_i == 0
        @dance.multi_dances.build(parent: @dance, dance: Dance.find_by_name(dance), slot: count.to_i)
      end
    end

    respond_to do |format|
      if @dance.save
        format.html { redirect_to dances_url, notice: "#{@dance.name} was successfully created." }
        format.json { render :show, status: :created, location: @dance }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @dance.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /dances/1 or /dances/1.json
  def update
    respond_to do |format|
      if @dance.update(dance_params)
        format.html { redirect_to dances_url, notice: "#{@dance.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @dance }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @dance.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /dances/drop
  def drop
    source = Dance.find(params[:source].to_i)
    target = Dance.find(params[:target].to_i)

    if source.order > target.order
      dances = Dance.where(order: target.order..source.order).order(:order)
      new_order = dances.map(&:order).rotate(1)
    else
      dances = Dance.where(order: source.order..target.order).order(:order)
      new_order = dances.map(&:order).rotate(-1)
    end

    Dance.transaction do
      dances.zip(new_order).each do |dance, order|
        dance.order = order
        dance.save! validate: false
      end

      raise ActiveRecord::Rollback unless dances.all? {|dance| dance.valid?}
    end

    index
    flash.now.notice = "#{source.name} was successfully moved."

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace('dances',
        render_to_string(:index, layout: false))}
      format.html { redirect_to dances_url }
    end
  end

  def form
    @dances = Dance.where(heat_length: nil).order(:order).all
    @columns = Dance.maximum(:col) || 4
  end

  def form_update
    if params[:commit] == 'Reset'
      Dance.update_all(row: nil, col: nil)

      redirect_to form_dances_url, notice: "Form reset."
    else
      Dance.transaction do
        params[:dance].each do |id, position|
          dance = Dance.find(id)
          dance.row = position['row'].to_i
          dance.col = position['col'].to_i
          dance.save!
        end
      end

      render plain: "Dance form updated"
    end
  end

  # DELETE /dances/1 or /dances/1.json
  def destroy
    @dance.destroy

    respond_to do |format|
      format.html { redirect_to dances_url, status: 303, notice: "#{@dance.name} was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    def form_init
      @categories = Category.order(:order).pluck(:name, :id)

      @affinities = Category.all.map do |category|
        dances = category.open_dances + category.closed_dances + category.solo_dances

        associations = {}
        open = dances.map(&:open_category_id).uniq
        closed = dances.map(&:closed_category_id).uniq
        solo = dances.map(&:solo_category_id).uniq

        if open.length == 1
          associations[:dance_open_category_id] = open.first
        end

        if closed.length == 1
          associations[:dance_closed_category_id] = closed.first
        end

        if closed.length == 1
          associations[:dance_solo_category_id] = solo.first
        end

        [category.id, associations]
      end.to_h
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_dance
      @dance = Dance.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def dance_params
      params.require(:dance).permit(:name, :category,
        :closed_category_id, :open_category_id, :solo_category_id,
        :heat_length, :multi_category_id, :multi)
    end
end
