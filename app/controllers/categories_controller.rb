class CategoriesController < ApplicationController
  before_action :set_category, only: %i[ show edit update destroy ]

  # GET /categories or /categories.json
  def index
    @categories = Category.all
  end

  # GET /categories/1 or /categories/1.json
  def show
  end

  # GET /categories/new
  def new
    @category = Category.new
    @category.order = Category.pluck(:order).max.to_i + 1

    form_init
  end

  # GET /categories/1/edit
  def edit
    form_init
  end

  # POST /categories or /categories.json
  def create
    @category = Category.new(category_params)

    respond_to do |format|
      if @category.save
        update_dances(params[:category][:include])

        format.html { redirect_to categories_url, notice: "Category was successfully created." }
        format.json { render :show, status: :created, location: @category }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /categories/1 or /categories/1.json
  def update
    respond_to do |format|
      if @category.update(category_params)
        update_dances(params[:category][:include])

        format.html { redirect_to categories_url, notice: "Category was successfully updated." }
        format.json { render :show, status: :ok, location: @category }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /categories/1 or /categories/1.json
  def destroy
    @category.destroy

    respond_to do |format|
      format.html { redirect_to categories_url status: 303, notice: "Category was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_category
      @category = Category.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def category_params
      params.require(:category).permit(:name, :order, :time)
    end

    def form_init
      dances = Dance.all
      @dances = dances.map(&:name)
      @entries = {'Closed' => {}, 'Open' => {}}

      dances.each do |dance|
        if dance.open_category == @category
          @entries['Open'][dance.name] = true
        end

        if dance.closed_category == @category
          @entries['Closed'][dance.name] = true
        end
      end
    end

    def update_dances(include)
      @total = 0

      Dance.all.each do |dance|
        STDERR.puts [dance.name, include['Open'][dance.name], include['Closed'][dance.name]].inspect
        if dance.open_category == @category
          if include['Open'][dance.name].to_i == 0
            dance.open_category = nil
          end
        elsif include['Open'][dance.name].to_i == 1
          dance.open_category = @category
        end

        if dance.closed_category == @category
          if include['Closed'][dance.name].to_i == 0
            dance.closed_category = nil
          end
        elsif include['Closed'][dance.name].to_i == 1
          dance.closed_category = @category
        end

        if dance.changed?
          dance.save!
          @total += 1 
        end
      end
    end
end
