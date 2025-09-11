require 'open3'

class UsersController < ApplicationController
  include DbQuery
  include ActionView::RecordIdentifier

  skip_before_action :authenticate_user
  before_action :get_authentication
  before_action :authenticate_index, except: %i[ password_reset password_verify ]
  before_action :set_user, only: %i[ show edit auth update destroy ]
  before_action :admin_home

  # GET /users or /users.json
  def index
    @users = User.order(:userid).all
  end

  # GET /users/1 or /users/1.json
  def show
  end

  # GET /users/new
  def new
    @user ||= User.new
    @admin = @@encryptor.encrypt_and_sign(dom_id(@user))
    load_studios(@user.sites.to_s.split(','), @user.userid)
  end

  # GET /users/1/edit
  def edit
    new
  end

  # GET /users/1/auth
  def auth
    edit
    @auth = true
    render :edit
  end

  # POST /users or /users.json
  def create
    set_password
    set_sites
    @user = User.new(user_params)

    respond_to do |format|
      if @user.save
        update_htpasswd_everywhere

        format.html { redirect_to users_url, notice: "#{@user.userid} was successfully created." }
        format.json { render :show, status: :created, location: @user }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @user.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /users/1 or /users/1.json
  def update
    admin = params[:user] && !!params[:user][:sites]

    set_password
    set_sites

    respond_to do |format|
      link = @user.link

      if @user.update(user_params)
        update_htpasswd_everywhere

        if not @user.token.blank? and not admin
          @user.link = ""
          @user.token = ""
          @user.save!

          format.html { redirect_to link || root_path,
            notice: "#{@user.userid} was successfully updated.",
            status: 303, allow_other_host: true }
        else
          format.html { redirect_to users_url, notice: "#{@user.userid} was successfully updated." }
          format.json { render :show, status: :ok, location: @user }
        end
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @user.errors, status: :unprocessable_content }
      end
    end
  end

  def update_location
    location = Location.find(params[:location])

    added = 0
    removed = 0

    params[:auth].each do |user_id, auth|
      user = User.find(user_id)
      sites = user.sites.split(',')
      before = sites.dup

      if auth == "0"
        if sites.include? location.name
          sites.delete(location.name)
          user.sites = sites.join(',')
          user.save!
          removed += 1
        end
      else
        unless sites.include? location.name
          sites.push(location.name)
          user.sites = sites.join(',')
          user.save!
          added += 1
        end
      end
    end

    notices = []
    notices << "#{added} #{"site".pluralize(added)} added" if added > 0
    notices << "#{removed} #{"site".pluralize(removed)} removed" if removed > 0
    notices << "Auth didn't change" if notices.length == 0

    redirect_to edit_location_url(location.id, anchor: 'authorization'), notice: notices.join(' and ')
  end

  # DELETE /users/1 or /users/1.json
  def destroy
    @user.destroy
    update_htpasswd_everywhere

    respond_to do |format|
      format.html { redirect_to users_url, status: 303,
        notice: "#{@user.userid} was successfully removed." }
      format.json { head :no_content }
    end
  end

  def password_reset
    if request.get?
      @users = User.order(:userid).pluck(:userid, :id).to_h
      @user = User.where(userid: @authuser).first.id if @authuser
      @user = User.find(params[:user]).id if @user = params[:user]

      if @user
        user = User.find(@user)
        @link = user.link

        if @link.blank?
          location = user.locations.first
          @link = "#{Showcase.url}/studios/#{location.key}" if location
        end
      end

      render :request_reset
    else
      user = @user = User.find(params[:id])
      @user.token = Random.alphanumeric(8)
      @user.link = params[:link]
      @user.save!

      mail = Mail.new do
        from 'Sam Ruby <rubys@intertwingly.net>'
        to "#{user.name1.inspect} <#{user.email}>"
        subject "Showcase password reset for #{user.userid}"
      end

      mail.part do |part|
        part.content_type = 'multipart/related'
        part.attachments.inline[EventController.logo] =
          IO.read "public/#{EventController.logo}"
        @logo = part.attachments.first.url
        part.html_part = render_to_string(:reset_email, formats: %i(html), layout: false)
      end

      mail.delivery_method :smtp,
        Rails.application.credentials.smtp || { address: 'mail.twc.com' }

      mail.deliver!

      redirect_to users_url, notice: "Password reset email sent to #{user.name1.inspect} <#{user.email}>"
    end
  end

  def password_verify
    @user = User.where(token: params[:token]).first
    if request.get?
      @verify= true
      render :reset
    elsif @user and not params[:user][:password].blank?
      # note: packet sniffers could pick up the token from the url and get past this
      # point, but will be blocked by the authenticity token later in the processing.
      update
    else
      render file: 'public/422.html', status: :unprocessable_content, layout: false
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = User.find(params[:id])
    end

    def authenticate_index
      unless request.local? or User.index_auth?(@authuser)
        request_http_basic_authentication "Showcase" unless request.local?
      end
    end

    def set_password
      params = self.params[:user]
      return unless params and params[:userid]
      return unless params[:password] and params[:password] == params[:password_confirmation]

      if params[:password].blank?
        params.delete :password
        params.delete :password_confirmation
      else
        htpasswd, status = Open3.capture2("htpasswd -ni #{params[:userid]}",
          stdin_data: params[:password])
        if status.success?
          params[:password] = params[:password_confirmation] = htpasswd.strip
        end
      end
    end

    def set_sites
      params = self.params[:user]
      return unless params and params[:sites]
      params[:sites] = params[:sites].select {|name, value| value.to_i > 0}.keys.join(',')
    end

    # Only allow a list of trusted parameters through.
    def user_params
      return unless self.params[:user]
      if (@@encryptor.decrypt_and_verify(params[:admin].to_s) == dom_id(@user) rescue false)
        params.require(:user).permit(:userid, :password, :password_confirmation, :email, :name1, :name2, :token, :link, :sites)
      else
        params.require(:user).permit(:userid, :password, :password_confirmation, :email, :name1, :name2, :sites)
      end
    end

    def load_studios(studios=[], site=nil)
      if Rails.env.test?
        @studios = Studio.pluck(:name)
        return
      end

      # @studios = studios
      @studios = studios.map {|name| {name: name}}
      @studios += YAML.load_file('config/tenant/showcases.yml').values.
        map {|hash| hash.values}.flatten

      if site
        dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
        Dir["#{dbpath}/20*.sqlite3"].each do |db|
          next unless site == 'index' || db =~ /^#{dbpath}\/\d+-#{site}[-.]/
          @studios += dbquery(File.basename(db, '.sqlite3'), 'studios', 'name')
        end
      end

      studios = @studios.map {|studio| (studio['name'] || studio[:name]).strip}
      locations = Location.order(:key).pluck(:name)

      @studios = (studios + locations).uniq.sort

      @studios.unshift 'index'
    end

    def update_htpasswd_everywhere
      return if Rails.env.test?
      User.update_htpasswd

      if Rails.env.production?
        spawn RbConfig.ruby, Rails.root.join('script/user-update').to_s
      end
    end

    @@encryptor = ActiveSupport::MessageEncryptor.new(ENV['RAILS_MASTER_KEY'] || IO.read('config/master.key'))
end
