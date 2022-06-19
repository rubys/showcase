require 'open3'

class UsersController < ApplicationController
  include ActionView::RecordIdentifier
  skip_before_action :authenticate_user
  before_action :get_authentication
  before_action :authenticate_index, except: %i[ password_reset password_verify ]
  before_action :set_user, only: %i[ show edit update destroy ]

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
    load_studios
  end

  # GET /users/1/edit
  def edit
    new
  end

  # POST /users or /users.json
  def create
    set_password
    set_sites
    @user = User.new(user_params)

    respond_to do |format|
      if @user.save
        update_htpasswd

        format.html { redirect_to users_url, notice: "#{@user.userid} was successfully created." }
        format.json { render :show, status: :created, location: @user }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /users/1 or /users/1.json
  def update
    set_password
    set_sites

    respond_to do |format|
      link = @user.link

      if @user.update(user_params)
        update_htpasswd

        if not @user.token.blank?
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
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /users/1 or /users/1.json
  def destroy
    @user.destroy
    update_htpasswd

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
      render :request_reset
    else
      user = @user = User.find(params[:id])
      @user.token = Random.alphanumeric(8)
      @user.link = params[:link]
      @user.save!

      # hack for now
      Mail.defaults do
        delivery_method :smtp, address: 'mail.twc.com'
      end

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
  
      mail.deliver!

      redirect_to root_path, notice: "Password reset email sent."
    end
  end

  def password_verify
    @user = User.where(token: params[:token]).first
    if request.get?
      render :reset
    elsif @user and not params[:user][:password].blank?
      # note: packet sniffers could pick up the token from the url and get past this
      # point, but will be blocked by the authenticity token later in the processing.
      update
    else
      render file: 'public/422.html', status: :unprocessable_entity, layout: false
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = User.find(params[:id])
    end

    def authenticate_index
      # deny access if there is a user with 'index' access and this user does not
      return unless @authuser

      sites = User.pluck(:sites).map {|sites| sites.to_s.split(',')}.flatten.
        select {|site| not site.blank?}
      return unless sites.include? 'index'

      return if User.where(userid: @authuser).pluck(:sites).first.to_s.split(',').include? 'index'

      request_http_basic_authentication "Showcase" unless request.local?
    end

    def set_password
      params = self.params[:user]
      return unless params[:userid]
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
      return unless params[:sites]
      params[:sites] = params[:sites].select {|name, value| value.to_i > 0}.keys.join(',')
    end

    # Only allow a list of trusted parameters through.
    def user_params
      if (@@encryptor.decrypt_and_verify(params[:admin].to_s) == dom_id(@user) rescue false)
        params.require(:user).permit(:userid, :password, :password_confirmation, :email, :name1, :name2, :token, :link, :sites)
      else
        params.require(:user).permit(:userid, :password, :password_confirmation, :email, :name1, :name2)
      end
    end

    def load_studios
      if Rails.env.test?
        @studios = Studio.pluck(:name)
        return
      end

      @studios = YAML.load_file('config/tenant/showcases.yml').values.
        map {|hash| hash.values}.flatten

      Dir['db/20*.sqlite3'].each do |db|
        json = `sqlite3 #{db} --json 'select name from studios'`
        @studios += JSON.parse(json) unless json.empty?
      end

      @studios = @studios.map {|studio| studio['name'] || studio[:name]}.uniq.sort

      @studios.unshift 'index'
    end

    def update_htpasswd
      return if Rails.env.test?
      contents = User.order(:password).pluck(:password).join("\n")
      return if contents == (IO.read 'db/htpasswd' rescue '')
      IO.write 'db/htpasswd', contents
    end

    @@encryptor = ActiveSupport::MessageEncryptor.new(IO.read 'config/master.key')
end
