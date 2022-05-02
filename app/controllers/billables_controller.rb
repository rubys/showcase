class BillablesController < ApplicationController
  before_action :set_billable, only: %i[ show edit update destroy ]

  # GET /billables or /billables.json
  def index
    @student_packages = Billable.where(type: 'Student').order(:order)
    @guest_packages = Billable.where(type: 'Guest').order(:order)
    @options = Billable.where(type: 'Option').order(:order)
    @event = Event.last
  end

  # GET /billables/1 or /billables/1.json
  def show
  end

  # GET /billables/new
  def new
    @billable ||= Billable.new
    @type ||= params[:type]

    if @type == 'package'
      current_options = @billable.package_includes.map(&:option_id)
      @options = Billable.where(type: 'Option').order(:order).
        map {|option| [option, current_options.include?(option.id)]}
    else
      current_packages = @billable.option_included_by.map(&:package_id)
      @packages = (Billable.where(type: 'Student').order(:order) +
        Billable.where(type: 'Guest').order(:order)).
        map {|package| [package, current_packages.include?(package.id)]}
    end
  end

  # GET /billables/1/edit
  def edit
    if @billable.type == "Option"
      @type = 'option'
    else
      @type = 'package'
    end

    new
  end

  # POST /billables or /billables.json
  def create
    @billable = Billable.new(billable_params.except(:options, :packages))

    @billable.order = (Billable.maximum(:order) || 0) + 1

    respond_to do |format|
      if @billable.save
        update_includes

        format.html { redirect_to settings_event_index_path(anchor: 'prices'),
          notice: "#{@billable.name} was successfully created." }
        format.json { render :show, status: :created, location: @billable }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @billable.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /billables/1 or /billables/1.json
  def update
    respond_to do |format|
      if @billable.update(billable_params.except(:options, :packages))
        update_includes

        format.html { redirect_to settings_event_index_path(anchor: 'prices'),
          notice: "#{@billable.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @billable }
      else
        new
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @billable.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /billables/1 or /billables/1.json
  def destroy
    @billable.destroy

    respond_to do |format|
      format.html { redirect_to settings_event_index_path(anchor: 'prices'),
        status: 303, notice: "#{@billable.name} was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_billable
      @billable = Billable.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def billable_params
      params.require(:billable).permit(:type, :name, :price, :order, options: {}, packages: {})
    end

    def update_includes
      if @billable.type == 'Option'
        desired_packages = billable_params[:packages]
        current_packages = @billable.option_included_by.map(&:package_id)
        Billable.where(type: ['Student', 'Guest']).each do |package|
          if desired_packages[package.id.to_s].to_i == 1
            unless current_packages.include? package.id
              PackageInclude.create! package: package, option: @billable
            end
          else
            if current_packages.include? package.id
              PackageInclude.destroy_by package: package, option: @billable
            end
          end
        end
      else
        desired_options = billable_params[:options]
        current_options = @billable.package_includes.map(&:option_id)
        Billable.where(type: 'Option').each do |option|
          if desired_options[option.id.to_s].to_i == 1
            unless current_options.include? option.id
              PackageInclude.create! package: @billable, option: option
            end
          else
            if current_options.include? option.id
              PackageInclude.destroy_by package: @billable, option: option
            end
          end
        end
      end
    end
end
