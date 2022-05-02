class MultisController < ApplicationController
  before_action :set_multi, only: %i[ show edit update destroy ]

  # GET /multis or /multis.json
  def index
    @multis = Multi.all
  end

  # GET /multis/1 or /multis/1.json
  def show
  end

  # GET /multis/new
  def new
    @dance ||= Dance.new
    @dance.heat_length ||= 3

    @dances = Dance.order(:order).where(heat_length: nil).pluck(:name)
    @multi = {}

    @categories = Category.order(:order).pluck(:name, :id)

    previous = Dance.where.not(multi_category_id: nil).select(:multi_category_id).distinct.pluck(:multi_category_id)
    @dance.multi_category_id ||= previous.first if previous.length == 1

    @url = multis_path
  end

  # GET /multis/1/edit
  def edit
    new

    @dance.multi_children.each do |multi|
      @multi[multi.dance.name] = multi.slot
    end

    @url = multi_path(@dance.id)
  end

  # POST /multi/categories/:category or /multi/categories/:category.json
  def create
    @dance = Dance.new(dance_params.except(:multi))

    @dance.order = (Dance.maximum(:order) || 0) + 1

    respond_to do |format|
      if @dance.save
        update_multis dance_params[:multi]
        format.html { redirect_to dances_url, notice: "#{@dance.name} was successfully created." }
        format.json { render :show, status: :created, location: @dance }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @dance.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /multis/1 or /multis/1.json
  def update
    respond_to do |format|
      if @dance.update(dance_params.except(:multi))
        update_multis params[:dance][:multi]
        format.html { redirect_to dances_url, notice: "#{@dance.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @multi }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @multi.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /multis/1 or /multis/1.json
  def destroy
    @dance.destroy

    respond_to do |format|
      format.html { redirect_to dances_url, status: 303, notice: "#{@dance.name} was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_multi
      @dance = Dance.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def dance_params
      params.require(:dance).permit(:name,
        :heat_length, :multi_category_id, :dances, multi: {})
    end

    def update_multis dances
      multis = @dance.multi_children

      Dance.all.each do |dance|
        slot = dances[dance.name]&.to_i || 0
        multi = multis.find {|multi| multi.dance_id == dance.id}

        if slot == 0
          multi.destroy if multi
        elsif !multi
          Multi.create! parent: @dance, dance: dance, slot: slot
        elsif multi.slot != slot
          multi.slot = slot
          multi.save!
        end
      end
    end
end
