class LocationsController < ApplicationController
  include Configurator
  include DbQuery

  before_action :set_location, only: %i[ show edit events auth sisters update destroy ]
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
      if name2.empty?
        ["#{userid}: #{name1}", id]
      else
        ["#{userid}: #{name1}/#{name2}", id]
      end
    end

    regions = new_regions
    @regions = JSON.parse(IO.read 'tmp/regions.json').
      select {|region| regions.include? region['Code']}.
      map {|region| [region['Name'], region['Code']]}.
      sort
    @regions.unshift ["", nil]
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
      if user.sites.split(',').include? @location.name
        @checked[user.id] = true
      elsif owners.include?(user.userid)
        true
      elsif user.sites.split(',').include? @location.name
        true
      else
        false
      end
    end
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

    redirect_to edit_location_url(location.id), notice: notices.join(' and ')
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
        first_event(:unprocessable_entity)
        return
      end

      @location.user_id = @user.id
      @location.key = @user.userid
    end

    respond_to do |format|
      if @location.save
        if params[:showcase]
          @showcase = Showcase.new(showcase_params)
          @showcase.location_id = @location.id
          @showcase.order = (Showcase.maximum(:order) || 0) + 1

          if not @showcase.save
            @user.destroy!
            @location.destroy!
            first_event(:unprocessable_entity)
            return
          end
        end

        generate_showcases
        generate_map

        sites = @location.user.sites.to_s.split(',')
        unless sites.include? @location.name
          sites.push @location.name
          @location.user.sites = sites.join(',')
          @location.user.save!
        end

        format.html { redirect_to locations_url, notice: "#{@location.name} was successfully created." }
        format.json { render :show, status: :created, location: @location }
      elsif params[:user]
        @user.destroy!
        @showcase = Showcase.new(showcase_params)
        format.html { first_event(:unprocessable_entity) }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @location.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /locations/1 or /locations/1.json
  def update
    respond_to do |format|
      if @location.update(location_params)
        generate_showcases
        generate_map

        format.html { redirect_to locations_url, notice: "#{@location.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @location }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @location.errors, status: :unprocessable_entity }
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

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_location
      @location = Location.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def location_params
      params.require(:location).permit(:key, :name, :latitude, :longitude, :user_id, :region)
    end

    def user_params
      params.require(:user).permit(:userid, :email, :name1, :name2)
    end

    def showcase_params
      params.require(:showcase).permit(:year, :key, :name)
    end
end
