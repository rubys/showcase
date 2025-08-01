class ShowcasesController < ApplicationController
  include Configurator
  include DbQuery

  before_action :set_showcase, only: %i[ show edit update destroy ]
  before_action :admin_home

  permit_site_owners :new_request, :create

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

    if @showcase.key == 'showcase' and @showcase.location.showcases.select {|showcase| showcase.year == @showcase.year}.count == 1
      @db = "#{@showcase.year}-#{@showcase.location.key}"
    else
      @db = "#{@showcase.year}-#{@showcase.location.key}-#{@showcase.key}"
    end

    unless Rails.env.test?
      begin
        @people = dbquery_raw(@db, 'SELECT count(id) FROM people').first&.values&.first || 0
        @entries = dbquery_raw(@db, 'SELECT count(id) FROM heats WHERE number > 0').first&.values&.first || 0
        @heats = dbquery_raw(@db, 'SELECT count(distinct number) FROM heats WHERE number > 0').first&.values&.first || 0
      rescue SQLite3::SQLException, Errno::ENOENT
        # Database doesn't exist yet - this is expected for requested but not yet created showcases
        @people = 0
        @entries = 0
        @heats = 0
      end
    end
  end

  # GET /studios/:location_key/request
  def new_request
    location = Location.find_by(key: params[:location_key])
    
    if location.nil?
      redirect_to root_path, alert: "Location not found"
      return
    end
    
    @showcase = Showcase.new
    @showcase.location_id = location.id
    @showcase.name = 'Showcase'
    @showcase.key = 'showcase'
    
    @locations = [[location.name, location.id]]
    @location_key = params[:location_key]
  end

  # POST /showcases or /showcases.json
  def create
    @showcase = Showcase.new(showcase_params)

    # Infer year from start_date if year is not provided
    if @showcase.year.blank? && params[:showcase][:start_date].present?
      # Parse the date from params
      @showcase.year = Date.parse(params[:showcase][:start_date]).year
    end

    @showcase.order = (Showcase.maximum(:order) || 0) + 1

    respond_to do |format|
      if @showcase.save
        generate_showcases

        # Redirect based on user type
        if User.index_auth?(@authuser)
          format.html { redirect_to events_location_url(@showcase.location),
            notice: "#{@showcase.name} was successfully created." }
        else
          # Use the same redirect for now, can be customized later
          format.html { redirect_to events_location_url(@showcase.location),
            notice: "#{@showcase.name} was successfully requested." }
        end
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

        format.html { redirect_to events_location_url(@showcase.location),
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
      format.html { redirect_to events_location_url(@showcase.location), status: 303,
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
      params.require(:showcase).permit(:year, :key, :name, :location_id, :start_date, :end_date)
    end
end
