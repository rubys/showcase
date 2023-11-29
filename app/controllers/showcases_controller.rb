class ShowcasesController < ApplicationController
  include Configurator
  include DbQuery

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
    return

    if @showcase.key == 'showcase' and @showcase.location.showcases.select {|showcase| showcase.year = @showcase.year}.count == 1
      @db = "#{@showcase.year}-#{@showcase.location.key}"
    else
      @db = "#{@showcase.year}-#{@showcase.location.key}-#{@showcase.key}"
    end

    unless Rails.env.test?
      @people = dbquery(@db, 'people', 'count(id)').first.values.first
      @entries = dbquery(@db, 'heats', 'count(id)', 'number > 0').first.values.first
      @heats = dbquery(@db, 'heats', 'count(distinct number)', 'number > 0').first.values.first
    end
  end

  # POST /showcases or /showcases.json
  def create
    @showcase = Showcase.new(showcase_params)

    @showcase.order = (Showcase.maximum(:order) || 0) + 1

    respond_to do |format|
      if @showcase.save
        generate_showcases

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
        generate_showcases

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
    generate_showcases

    respond_to do |format|
      format.html { redirect_to edit_location_url(@showcase.location), status: 303,
        notice: "#{@showcase.name} was successfully destroyed." }
      format.json { head :no_content }
    end
  end

    # POST /showcases/drop
    def drop
      source = Showcase.find(params[:source].to_i)
      target = Showcase.find(params[:target].to_i)
  
      if source.order > target.order
        showcases = Showcase.where(order: target.order..source.order).order(:order)
        new_order = showcases.map(&:order).rotate(1)
      else
        showcases = Showcase.where(order: source.order..target.order).order(:order)
        new_order = showcases.map(&:order).rotate(-1)
      end
  
      Showcase.transaction do
        showcases.zip(new_order).each do |dance, order|
          dance.order = order
          dance.save! validate: false
        end
  
        raise ActiveRecord::Rollback unless showcases.all? {|dance| dance.valid?}
      end

      generate_showcases
  
      flash.now.notice = "#{source.name} was successfully moved."

      @showcases = source.location.showcases.order(:year, :order).reverse.group_by(&:year)
  
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace('showcases', 
          render_to_string(partial: 'locations/showcases')) }
        format.html { redirect_to showcases_url }
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
