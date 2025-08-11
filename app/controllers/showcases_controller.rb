require 'mail'

class ShowcasesController < ApplicationController
  include Configurator
  include DbQuery

  before_action :set_showcase, only: %i[ show edit update destroy ]
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
    unless Showcase.where(location_id: @location.id, year: Time.now.year).exists?
      @showcase.name = 'Showcase'
      @showcase.key = 'showcase'
    end
    
    @locations = [[@location.name, @location.id]]
    @location_key = params[:location_key]
    
    # Set return_to URL from params or default to studios page
    @return_to = params[:return_to] || "/studios/#{params[:location_key]}"
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

        # Send email confirmation unless user is index authorized
        unless Rails.env.test? || User.index_auth?(@authuser)
          send_showcase_request_email(@showcase)
        end

        # Redirect based on user type and return_to parameter
        if params[:return_to].present?
          format.html { redirect_to params[:return_to], 
            notice: "#{@showcase.name} was successfully #{User.index_auth?(@authuser) ? 'created' : 'requested'}." }
        elsif User.index_auth?(@authuser)
          format.html { redirect_to events_location_url(@showcase.location),
            notice: "#{@showcase.name} was successfully created." }
        else
          format.html { redirect_to events_location_url(@showcase.location),
            notice: "#{@showcase.name} was successfully requested." }
        end
        format.json { render :show, status: :created, location: @showcase }
      else
        new
        @return_to = params[:return_to]
        format.html { render :new, status: :unprocessable_content }
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
          notice: "#{@showcase.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @showcase }
      else
        edit
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
        notice: "#{@showcase.name} was successfully destroyed." }
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

    def send_showcase_request_email(showcase)
      # Get the requesting user's information
      requester_email = @authuser ? User.find_by(userid: @authuser)&.email : nil
      requester_name = @authuser ? User.find_by(userid: @authuser)&.name1 : 'Unknown User'
      
      mail = Mail.new do
        from 'Sam Ruby <rubys@intertwingly.net>'
        to "#{requester_name} <#{requester_email}>" if requester_email
        bcc 'Sam Ruby <rubys@intertwingly.net>'
        subject "Showcase Request: #{showcase.location.name} #{showcase.year} - #{showcase.name}"
      end

      mail.part do |part|
        part.content_type = 'multipart/related'
        part.attachments.inline[EventController.logo] =
          IO.read "public/#{EventController.logo}"
        @logo = part.attachments.first.url
        @showcase = showcase
        @requester_name = requester_name
        part.html_part = render_to_string('showcases/request_email', formats: %i(html), layout: false)
      end

      mail.delivery_method :smtp,
        Rails.application.credentials.smtp || { address: 'mail.twc.com' }

      mail.deliver!
    rescue => e
      Rails.logger.error "Failed to send showcase request email: #{e.message}"
    end
end
