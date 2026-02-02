class ShowcasesController < ApplicationController
  include Configurator
  include DbQuery

  before_action :set_showcase, only: %i[ show edit update destroy ]
  before_action :setup_form, only: %i[ new edit ]
  before_action :set_studio_for_auth, only: %i[ new_request create ]
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
  end

  # GET /showcases/1/edit
  def edit
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
    return create if request.post?

    if ENV['FLY_REGION']
      # Build the return URL for the studios page
      return_url = url_for(controller: 'event', action: 'showcases', only_path: false).sub('/showcase/events/', '/studios/') + params[:location_key]

      # Build the rubix URL preserving the current path and query parameters
      rubix_url = "https://rubix.intertwingly.net#{request.path}"

      # Add query parameters including return_to and submitted
      query_params = request.query_parameters.merge(return_to: return_url, submitted: true)
      rubix_url += "?#{query_params.to_query}" unless query_params.empty?

      redirect_to rubix_url, allow_other_host: true
      return
    end

    @showcase = Showcase.new
    @showcase.location_id = @location.id

    @locations = [[@location.name, @location.id]]
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

        if Rails.env.test? || User.index_auth?(@authuser)
          # For tests and admin users: Keep existing behavior (immediate redirect, no automation)
          # Redirect based on return_to parameter
          if params[:return_to].present?
            format.html { redirect_to params[:return_to],
              notice: "#{@showcase.name} was successfully created.", allow_other_host: true }
          else
            format.html { redirect_to events_location_url(@showcase.location),
              notice: "#{@showcase.name} was successfully created.", allow_other_host: true }
          end
        else
          # For regular users: Show progress bar with real-time updates
          user = User.find_by(userid: @authuser)

          if user
            # Determine target based on environment
            target = Rails.env.development? ? 'kamal' : 'fly'
            ConfigUpdateJob.perform_later(user.id, target: target) if Rails.env.production? || Rails.env.development?
          end

          # Set variables for progress view
          @location_key = @showcase.location&.key
          @location = @showcase.location
          @show_progress = true

          # Redirect to the new showcase page after progress completes
          # Better UX than studio list (which is prerendered and won't show new event yet)
          # URL pattern matches logic from create_db action:
          # - If key == 'showcase' AND only one event this year: /:year/:location
          # - Otherwise: /:year/:location/:event_key
          events_this_year = Showcase.where(
            location_id: @showcase.location_id,
            year: @showcase.year
          ).count

          # Determine base URL based on environment
          # Development: redirect to showcase.party (Kamal server)
          # Production: redirect within same app (Fly.io)
          base_url = if Rails.env.development?
            "https://showcase.party"
          else
            "/showcase"  # Relative URL for production (stays on smooth.fly.dev)
          end

          # Match URL structure from create_db action (lines 42-46)
          @return_to = if @showcase.key == 'showcase' && events_this_year == 1
            # Single 'showcase' event: /:year/:location_key
            "#{base_url}/#{@showcase.year}/#{@location_key}"
          else
            # Multiple events OR non-'showcase' key: /:year/:location_key/:event_key
            "#{base_url}/#{@showcase.year}/#{@location_key}/#{@showcase.key}"
          end

          logger.info "[#{request.request_id}] Showcase request submitted: #{@showcase.name}. Will redirect to: #{@return_to}"

          # Return Turbo Stream or HTML based on request
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "showcase-form-container",
              partial: "showcases/showcase_progress",
              locals: { showcase: @showcase, location_key: @location_key, redirect_url: @return_to }
            )
          end
          format.html { render :new_request, status: :ok }
        end

        format.json { render :show, status: :created, location: @showcase }
      else
        setup_form
        @return_to = params[:return_to]

        # If @return_to is set and there is a name error, remove key errors
        if @return_to && @showcase.errors[:name].present?
          @showcase.errors.delete(:key)
        end

        @location_key = @showcase.location&.key if @return_to

        format.turbo_stream do
          if @return_to
            render turbo_stream: turbo_stream.replace(
              "showcase-form-container",
              partial: "showcases/showcase_form_with_errors",
              locals: { showcase: @showcase, location_key: @location_key, location: @location }
            ), status: :unprocessable_entity
          else
            # For non-studio-request forms, render the standard new form
            render turbo_stream: turbo_stream.replace(
              "showcase-form-container",
              partial: "showcases/form",
              locals: { showcase: @showcase }
            ), status: :unprocessable_entity
          end
        end
        format.html { render @return_to ? :new_request : :new, status: :unprocessable_content }
        format.json { render json: @showcase.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /showcases/1 or /showcases/1.json
  def update
    respond_to do |format|
      if @showcase.update(showcase_params)
        generate_showcases

        format.html { redirect_to events_location_url(@showcase.location),
          notice: "#{@showcase.name} was successfully updated.", allow_other_host: true }
        format.json { render :show, status: :ok, location: @showcase }
      else
        setup_form
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @showcase.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /showcases/1 or /showcases/1.json
  def destroy
    @showcase.destroy
    generate_showcases

    respond_to do |format|
      format.html { redirect_to events_location_url(@showcase.location), status: 303,
        notice: "#{@showcase.name} was successfully destroyed.", allow_other_host: true }
      format.json { head :no_content }
    end
  end

    # POST /showcases/drop
    def drop
      source = Showcase.find(params[:source].to_i)
      target = Showcase.find(params[:target].to_i)
  
      if source.order > target.order
        showcases = Showcase.where(order: target.order..source.order).ordered
        new_order = showcases.map(&:order).rotate(1)
      else
        showcases = Showcase.where(order: source.order..target.order).ordered
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

      @location = source.location
    @showcases = @location.showcases.order(:year, :order).reverse.group_by(&:year)
  
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

    def setup_form
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

    def set_studio_for_auth
      # For new_request action, location comes from URL param
      if params[:location_key]
        @location = Location.find_by(key: params[:location_key])
      # For create action, location comes from form data
      elsif params[:showcase] && params[:showcase][:location_id]
        @location = Location.find_by(id: params[:showcase][:location_id])
      end
      
      if @location.nil?
        render file: "#{Rails.root}/public/404.html", status: :not_found, layout: false
        return
      end
      
      # Set @studio for authentication - create a struct with the location name
      @studio = Struct.new(:name).new(@location.name)
    end

    # Only allow a list of trusted parameters through.
    def showcase_params
      params.expect(showcase: [:year, :key, :name, :location_id, :start_date, :end_date])
    end
end
