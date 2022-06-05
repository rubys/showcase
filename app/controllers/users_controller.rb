require 'open3'

class UsersController < ApplicationController
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
      if @user.update(user_params)
        format.html { redirect_to users_url, notice: "#{@user.userid} was successfully updated." }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /users/1 or /users/1.json
  def destroy
    @user.destroy

    respond_to do |format|
      format.html { redirect_to users_url, status: 303,
        notice: "#{@user.userid} was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = User.find(params[:id])
    end

    def set_password
      params = self.params[:user]
      return unless params[:userid]
      return unless params[:password] and params[:password] == params[:password_confirmation]
      htpasswd, status = Open3.capture2("htpasswd -ni #{params[:userid]}",
        stdin_data: params[:password])
      if status.success?
        params[:password] = params[:password_confirmation] = htpasswd.strip
      end
    end

    def set_sites
      params = self.params[:user]
      return unless params[:sites]
      params[:sites] = params[:sites].select {|name, value| value.to_i > 0}.keys.join(',')
    end

    # Only allow a list of trusted parameters through.
    def user_params
      params.require(:user).permit(:userid, :password, :password_confirmation, :email, :name1, :name2, :token, :link, :sites)
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
end
