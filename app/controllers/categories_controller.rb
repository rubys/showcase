class CategoriesController < ApplicationController
  before_action :set_category, only: %i[ show edit update destroy ]

  # GET /categories or /categories.json
  def index
    @categories = Category.order(:order)

    counts = Heat.group(:number, :category, :dance_id).count(:number)

    @heats = @categories.map {|category| [category, 0]}.to_h

    @heats.merge!(counts.map do |(heat, category, dance), count|
      dance = Dance.find(dance);

      case category
      when "Open"
        category = dance.open_category
      when "Solo"
        category = dance.solo_category
      else
        category = dance.closed_category
      end

      [category, 1]
    end.group_by {|category, counts| category}.
    map {|category, counts| [category, counts.map(&:last).sum]}.to_h)

    @entries = @categories.map {|category| [category, 0]}.to_h

    @entries.merge!(counts.map do |(heat, category, dance), count|
      dance = Dance.find(dance)

      case category
      when "Open"
        category = dance.open_category
      when "Solo"
        category = dance.solo_category
      else
        category = dance.closed_category
      end

      [category, count]
    end.group_by {|category, counts| category}.
    map {|category, counts| [category, counts.map(&:last).sum]}.to_h)
  end

  # GET /categories/1 or /categories/1.json
  def show
  end

  # GET /categories/new
  def new
    @category ||= Category.new
    @category.order ||= Category.pluck(:order).max.to_i + 1

    form_init
  end

  # GET /categories/1/edit
  def edit
    form_init
  end

  # POST /categories or /categories.json
  def create
    @category = Category.new(category_params)

    @category.order = (Category.maximum(:order) || 0) + 1

    respond_to do |format|
      if @category.save
        update_dances(params[:category][:include])

        format.html { redirect_to categories_url, notice: "#{@category.name} was successfully created." }
        format.json { render :show, status: :created, location: @category }
      else
        new
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

        format.html { redirect_to categories_url, notice: "#{@category.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @category }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /categories/drop
  def drop
    source = Category.find(params[:source].to_i)
    target = Category.find(params[:target].to_i)

    if source.order > target.order
      categories = Category.where(order: target.order..source.order).order(:order)
      new_order = categories.map(&:order).rotate(1)
    else
      categories = Category.where(order: source.order..target.order).order(:order)
      new_order = categories.map(&:order).rotate(-1)
    end

    Category.transaction do
      categories.zip(new_order).each do |category, order|
        category.order = order
        category.save! validate: false
      end

      raise ActiveRecord::Rollback unless categories.all? {|category| category.valid?}
    end

    index
    flash.now.notice = "#{source.name} was successfully moved."

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace('categories', 
        render_to_string(:index, layout: false))}
      format.html { redirect_to categories_url }
    end
  end

  # DELETE /categories/1 or /categories/1.json
  def destroy
    @category.destroy

    respond_to do |format|
      format.html { redirect_to categories_url, status: 303, notice: "#{@category.name} was successfully removed." }
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
      dances = Dance.order(:order).all
      @dances = dances.map(&:name)
      @entries = {'Closed' => {}, 'Open' => {}, 'Solo' => {}}

      dances.each do |dance|
        if dance.open_category == @category
          @entries['Open'][dance.name] = true
        end

        if dance.closed_category == @category
          @entries['Closed'][dance.name] = true
        end

        if dance.solo_category == @category
          @entries['Solo'][dance.name] = true
        end
      end
    end

    def update_dances(include)
      @total = 0

      Dance.all.each do |dance|
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

        if dance.solo_category == @category
          if include['Solo'][dance.name].to_i == 0
            dance.solo_category = nil
          end
        elsif include['Solo'][dance.name].to_i == 1
          dance.solo_category = @category
        end

        if dance.changed?
          dance.save!
          @total += 1 
        end
      end
    end
end
