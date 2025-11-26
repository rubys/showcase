class LocationsController < ApplicationController
  include Configurator
  include DbQuery

  before_action :set_location, only: %i[ show edit events auth add_auth sisters update destroy ]
  before_action :admin_home

  # GET /locations or /locations.json
  def index
    @locations = Location.order(:key).all
  end

  # GET /locations/1 or /locations/1.json
  def show
  end

  # GET /locations/new
  def new
    @location ||= Location.new

    if params[:user_id] and @location.new_record?
      user = User.find(params[:user_id])
      @location.user = user
      @location.key = user.userid
      @location.name = user.userid.capitalize
    end

    @users = User.order(:userid).pluck(:userid, :name1, :name2, :id).
    map do |userid, name1, name2, id|
      if name2.blank?
        ["#{userid}: #{name1}", id]
      else
        ["#{userid}: #{name1}/#{name2}", id]
      end
    end

    regions = RegionConfiguration.load_deployed_regions
    regions_data = RegionConfiguration.load_regions_data
    @regions = regions_data.
      select {|region| regions.include? region['code']}.
      map {|region| [region['name'], region['code']]}.
      sort
    @regions.unshift ["", nil]

    Dir.chdir 'public' do
      @logos = Dir['*'].select do |name|
        name.include? '.' and not name.include? '.html' and not name.start_with? 'apple-' and not name.include? '.txt'
      end
    end
  end

  def first_event(status=:ok)
    new
    @user ||= User.new
    @showcase ||= Showcase.new
    @first_event = true

    @showcase.year ||= Showcase.maximum(:year) || Time.now.year

    unless @showcase.location&.showcases&.any? {|showcase| showcase.year == @showcase.year}
      @showcase.name ||= 'Showcase'
      @showcase.key ||= 'showcase'
    end

    render :new, status: status
  end

  # GET /locations/1/edit
  def edit
    new

    @showcases = @location.showcases.order(:year, :order).reverse.group_by(&:year)
  end

  def events
    edit
  end

  def auth
    edit

    studios = []
    dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
    Dir["#{dbpath}/20*.sqlite3"].each do |db|
      next unless db =~ /^#{dbpath}\/\d+-#{@location.key}[-.]/
      studios += dbquery(File.basename(db, '.sqlite3'), 'studios', 'name')
    end

    locations = Location.joins(:user).pluck(:name, :sisters, :userid).
      map {|name, sisters, userid| ([name] + sisters.to_s.split(',')).
      map {|site| [site, userid]}}.flatten(1).to_h

    owners = studios.uniq.map {|studio| locations[studio['name']]}.compact.sort
    @studios = @location.key

    @checked = {}
    @auth = User.order(:userid).select do |user|
      if user.sites.to_s.split(',').include? @location.name
        @checked[user.id] = true
      elsif owners.include?(user.userid)
        true
      elsif user.sites.to_s.split(',').include? @location.name
        true
      else
        false
      end
    end

    # Build list of users not already in @auth for the add dropdown
    auth_ids = @auth.map(&:id)
    @available_users = @users.reject { |label, id| auth_ids.include?(id) }
  end

  def add_auth
    auth

    # Restore checkbox state from params and add any users not in the original list
    if params[:auth].present?
      auth_ids = @auth.map(&:id)
      @checked = {}
      params[:auth].each do |user_id, checked|
        id = user_id.to_i
        @checked[id] = true if checked == '1'
        unless auth_ids.include?(id)
          user = User.find_by(id: id)
          @auth << user if user
        end
      end
    end

    # Add the selected user
    if params[:add_user_id].present?
      new_user_id = params[:add_user_id].to_i
      unless @auth.any? { |u| u.id == new_user_id }
        new_user = User.find_by(id: new_user_id)
        if new_user
          @auth << new_user
          @checked[new_user_id] = true
        end
      end
    end

    @auth = @auth.sort_by(&:userid)

    # Rebuild available users after adding
    auth_ids = @auth.map(&:id)
    @available_users = @users.reject { |label, id| auth_ids.include?(id) }

    render :auth
  end

  def sisters
    edit

    studios = []
    dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
    Dir["#{dbpath}/20*.sqlite3"].each do |db|
      studios += dbquery(File.basename(db, '.sqlite3'), 'studios', 'name')
    end

    @studios = studios.flatten.map {|studio| studio['name'].strip}.sort.uniq
    @studios -= Location.pluck(:name)
    @studios.delete 'Event Staff'

    Location.all.each do |location|
      @studios -= location.sisters.to_s.split(',') unless location == @location
    end

    @checked = {}
    @location.sisters.to_s.split(',').each do |location|
      @checked[location] = true
    end
  end

  def update_sisters
    location = Location.find(params[:location])

    before = location.sisters.to_s.split(',')

    sisters = []

    params[:sisters].each do |location, checked|
      sisters << location if checked == '1'
    end

    added = (sisters - before).length
    removed = (before - sisters).length

    notices = []
    notices << "#{added} sister #{"location".pluralize(added)} added" if added > 0
    notices << "#{removed} sister #{"location".pluralize(removed)} removed" if removed > 0
    notices << "Sister locations didn't change" if notices.length == 0

    location.update!(sisters: sisters.join(','))

    redirect_to edit_location_url(location.id), notice: notices.join(' and '), allow_other_host: true
  end

  # POST /locations or /locations.json
  def create
    @location = Location.new(location_params)
    @location.name = @location.name.split(',').first

    if params[:user]
      @user = User.new(user_params)
      if not @user.save
        @showcase = Showcase.new(showcase_params)
        logger.info @showcase.inspect
        first_event(:unprocessable_content)
        return
      end

      @user.update!(sites: @location.name)

      @location.user_id = @user.id
      @location.key = @user.userid
    end

    respond_to do |format|
      if @location.save
        if params[:showcase] && !showcase_params[:name].blank?
          @showcase = Showcase.new(showcase_params)
          @showcase.location_id = @location.id
          @showcase.order = (Showcase.maximum(:order) || 0) + 1

          if not @showcase.save
            @user.destroy!
            @location.destroy!
            first_event(:unprocessable_content)
            return
          end
        end

        generate_showcases
        generate_map

        sites = @location.user&.sites&.to_s&.split(',')
        unless !sites || sites.include?(@location.name)
          sites.push @location.name
          @location.user.sites = sites.join(',')
          @location.user.save!
        end

        format.html { redirect_to locations_url, notice: "#{@location.name} was successfully created." }
        format.json { render :show, status: :created, location: @location }
      elsif params[:user]
        @user.destroy!
        @showcase = Showcase.new(showcase_params)
        format.html { first_event(:unprocessable_content) }
      else
        new
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @location.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /locations/1 or /locations/1.json
  def update
    trust_level = @location.trust_level

    respond_to do |format|
      if @location.update(location_params)
        generate_showcases
        generate_map

        if Rails.env.production? and trust_level != @location.trust_level
          ConfigUpdateJob.perform_later
        end

        format.html { redirect_to locations_url, notice: "#{@location.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @location }
      else
        edit
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @location.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /locations/1 or /locations/1.json
  def destroy
    @location.destroy

    respond_to do |format|
      generate_showcases
      generate_map

      format.html { redirect_to locations_url, notice: "#{@location.name} was successfully destroyed.", status: 303 }
      format.json { head :no_content }
    end
  end

  def locale
    latitude = params[:lat].to_f
    longitude = params[:lng].to_f

    locale = suggest_locale(latitude, longitude) rescue "en_US"

    render json: {locale: locale}
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_location
      @location = Location.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def location_params
      params.require(:location).permit(:key, :name, :latitude, :longitude, :user_id, :region, :logo, :trust_level, :locale)
    end

    def user_params
      params.require(:user).permit(:userid, :email, :name1, :name2)
    end

    def showcase_params
      params.require(:showcase).permit(:year, :key, :name)
    end

    def suggest_locale(lat, lng)
      return "en_US" if lat.blank? || lng.blank?
      result = Geocoder.search([lat, lng]).first
      return "en_US" unless result

      country_code = result.country_code&.upcase
      case country_code
      when "US"
        "en_US"
      when "GB"
        "en_GB"
      when "AU"
        "en_AU"
      when "CA"
        if in_quebec?(lat, lng) || result.state_code == "QC"
          "fr_CA"
        else
          "en_CA"
        end
      when "NL"
        "nl_NL"
      when "PL"
        "pl_PL"
      when "IT"
        "it_IT"
      when "UA"
        "uk_UA"
      when "JP"
        "ja_JP"
      else
        "en_US"
      end
    end

    def in_quebec?(lat, lng)
      # Montreal region boundaries (approximate)
      montreal_bounds = {
        north: 46.0,  # Northern boundary
        south: 45.0,  # Southern boundary
        east: -73.0,  # Eastern boundary
        west: -74.0   # Western boundary
      }

      lat.between?(montreal_bounds[:south], montreal_bounds[:north]) &&
        lng.between?(montreal_bounds[:west], montreal_bounds[:east])
    end
end
