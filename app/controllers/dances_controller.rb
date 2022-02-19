class DancesController < ApplicationController
  before_action :set_dance, only: %i[ show edit update destroy ]

  # GET /dances or /dances.json
  def index
    @dances = Dance.includes(:open_category, :closed_category).order(:order).all
    @heats = Heat.group(:dance_id).distinct.count(:number)
    @entries = Heat.group(:dance_id).count
  end

  # GET /dances/1 or /dances/1.json
  def show
  end

  # GET /dances/new
  def new
    @dance = Dance.new

    @categories = Category.order(:order).pluck(:name, :id)
  end

  # GET /dances/1/edit
  def edit
    @categories = Category.order(:order).pluck(:name, :id)
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

    ActiveRecord::Base.transaction do
      dances.zip(new_order).each do |dance, order|
        dance.order = order
        dance.save!
      end
    end

    @dances = Dance.includes(:open_category, :closed_category).order(:order).all
    @heats = Heat.group(:dance_id).distinct.count(:number)
    @entries = Heat.group(:dance_id).count
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
