class DancesController < ApplicationController
  before_action :set_dance, only: %i[ show edit update destroy ]

  # GET /dances or /dances.json
  def index
    @dances = Dance.includes(:open_category, :closed_category, :solo_category).order(:order).all
    @heats = Heat.group(:dance_id).distinct.count(:number)
    @entries = Heat.group(:dance_id).count
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
  end

  # POST /dances or /dances.json
  def create
    @dance = Dance.new(dance_params)

    @dance.order = (Dance.maximum(:order) || 0) + 1

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
      params.require(:dance).permit(:name, :category, :closed_category_id, :open_category_id, :solo_category_id)
    end
end
