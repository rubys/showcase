class CategoriesController < ApplicationController
  include Printable
  include HeatScheduler
  before_action :set_category, only: %i[ show edit update destroy ]

  permit_site_owners :toggle_lock, trust_level: 100

  # GET /categories or /categories.json
  def index
    generate_agenda
    @agenda = @agenda.to_h
    @categories = (Category.all + CatExtension.all).sort_by {|cat| cat.order}
    @locked = Event.last.locked?
    @settings = params[:settings]

    if @settings
      @event = Event.first
      @ages = Age.all.size
      @levels = Level.all.order(:id).map {|level| [level.name, level.id]}
    end
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
    generate_agenda
    @day_placeholder = Date::DAYNAMES[@cat_start&.dig(@category.name)&.wday || 7]

    form_init
  end

  # POST /categories or /categories.json
  def create
    if params[:category][:customize] != '1'
      params[:category][:ballrooms] = ''
      params[:category][:max_heat_size] = ''
      params[:category][:heats] = ''
    end

    @category = Category.new(category_params)

    @category.order = ([Category.maximum(:order) || 0, CatExtension.maximum(:order) || 0]).max + 1

    respond_to do |format|
      if @category.save
        update_dances(params[:category][:include], params[:category][:pro])

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
    params[:category] ||= params[:cat_extension]

    if params[:category][:customize] != '1' and @category.instance_of? Category
      params[:category][:ballrooms] = ''
      params[:category][:max_heat_size] = ''
      params[:category][:heats] = ''
    end

    if @category.instance_of?(Category) && (!params[:category][:heats].blank? || @category.extensions.any?)
      generate_agenda
      heats = @agenda[@category.name].length + @category.extensions.map {|ext| @agenda[ext.name].length}.sum
      extensions_found = @category.extensions.order(:part).all.to_a
      if params[:category][:heats].blank?
        extensions_needed = 0
      else
        extensions_needed = (heats.to_f / params[:category][:heats].to_i).ceil - 1
      end


      while extensions_found.length > extensions_needed
        extensions_found.pop.destroy!
      end

      while extensions_needed > extensions_found.length
        order = [Category.maximum(:order), CatExtension.maximum(:order)].compact.max + 1
        extensions_found << CatExtension.create!(category: @category, order: order, part: extensions_found.length + 2)
      end
    end

    respond_to do |format|
      if @category.update(category_params)
        update_dances(params[:category][:include], params[:category][:pro])

        format.html { redirect_to categories_url, notice: "#{@category.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @category }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  def toggle_lock
    if params[:id]
      set_category
      @category.update(locked: !@category.locked)
      anchor = "cat-#{@category.name.downcase.gsub(' ', '-')}"
      redirect_to heats_url(anchor: anchor),
        notice: "Category #{@category.name} #{@category.locked ? '' : 'un'}locked."
    else
      event = Event.first
      event.update(locked: !event.locked)
      Heat.where('prev_number != number').update_all 'prev_number = number' if event.locked
      redirect_to params[:return_to] || categories_url,
        notice: "Agenda #{event.locked ? '' : 'un'}locked."
    end
  end

  # POST /categories/redo
  def redo
    schedule_heats
    redirect_to categories_url, notice: "#{Heat.maximum(:number).to_i} heats generated."
  end

  # POST /categories/drop
  def drop
    if params[:source].include? '-'
      source = CatExtension.find(params[:source].split('-').first.to_i)
    else
      source = Category.find(params[:source].to_i)
    end

    if params[:target].include? '-'
      target = CatExtension.find(params[:target].split('-').first.to_i)
    else
      target = Category.find(params[:target].to_i)
    end

    categories = (Category.all.to_a + CatExtension.all.to_a).sort_by(&:order)

    if source.order > target.order
      categories = categories.select {|cat| (target.order..source.order).include? cat.order}
      new_order = categories.map(&:order).rotate(1)
    else
      categories = categories.select {|cat| (source.order..target.order).include? cat.order}
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
      if params[:part]
        @category = CatExtension.find(params[:id])
      else
        @category = Category.find(params[:id])
      end
    end

    # Only allow a list of trusted parameters through.
    def category_params
      params.require(:category).permit(:name, :order, :day, :time, :ballrooms, :max_heat_size, :heats, :duration, :routines, :cost_override, :pro, :studio_cost_override)
    end

    def form_init
      dances = Dance.order(:order).all
      @dances = dances.select {|dance| dance.heat_length == nil && dance.order >= 0}
      @multis = dances.select {|dance| dance.heat_length != nil && dance.order >= 0}
      @entries = {'Closed' => {}, 'Open' => {}, 'Solo' => {}, 'Multi' => {}}
      @columns = Dance.maximum(:col)

      if @category.id
        dances.each do |dance|
          # ensure dance is in the list
          if dance.heat_length == nil
            if !@dances.any? {|d| d.name == dance.name}
              @dances << dance
            end
          else
            if !@multis.any? {|d| d.name == dance.name}
              @multis << dance
            end
          end

          # mark dances that are in the category
          if @category.pro
            if dance.pro_open_category_id == @category.id
              @entries['Open'][dance.name] = true
            end

            if dance.pro_closed_category_id == @category.id
              @entries['Closed'][dance.name] = true
            end

            if dance.pro_solo_category_id == @category.id
              @entries['Solo'][dance.name] = true
            end

            if dance.pro_multi_category_id == @category.id
              @entries['Multi'][dance.name] = true
            end
          else
            if dance.open_category_id == @category.id
              @entries['Open'][dance.name] = true
            end

            if dance.closed_category_id == @category.id
              @entries['Closed'][dance.name] = true
            end

            if dance.solo_category_id == @category.id
              @entries['Solo'][dance.name] = true
            end

            if dance.multi_category_id == @category.id
              @entries['Multi'][dance.name] = true
            end
          end
        end
      end

      event = Event.first
      @pro_option = event.pro_heats
      @include_open = event.include_open || Heat.where(category: 'Open').size > 0
      @include_closed = event.include_closed || Heat.where(category: 'Closed').size > 0
    end

    def update_dances(include, pro)
      @total = 0

      categories = [
        ['Open', :open_category, :pro_open_category],
        ['Closed', :closed_category, :pro_closed_category],
        ['Solo', :solo_category, :pro_solo_category],
        ['Multi', :multi_category, :pro_multi_category]
      ]

      if Event.first.agenda_based_entries?
        if @category.routines?
          categories.each do |cat, normal, pro|
            # Delete all dances that are not longer in the category
            # resetting the included count for those that are
            Dance.all.each do |dance|
              next if dance.order >= 0
              if dance.send(normal) == @category
                if pro == '1' || include[cat]&.[](dance.name).to_i == 0
                  dance.destroy! unless dance.heats.any?
                elsif include[cat]&.[](dance.name).to_i > 0
                  include[cat][dance.name] = 0
                end
              end

              if dance.send(pro) == @category
                if pro == '0' || include[cat]&.[](dance.name).to_i == 0
                  dance.destroy! unless dance.heats.any?
                elsif include[cat]&.[](dance.name).to_i > 0
                  include[cat][dance.name] = 0
                end
              end
            end

            # Create new dances for those that are now in the category
            # again, resetting the included count
            include[cat]&.each do |name, value|
              next if value.to_i == 0
              order = [Dance.minimum(:order), 0].min - 1
              if pro == '1'
                Dance.create!(name: name, pro => @category, order: order)
              else
                Dance.create!(name: name, normal => @category, order: order)
              end
              @total += 1
              include[cat][name] = 0
            end
          end
        else
          # Move all heats that are in the category back to main program dances
          dupes = Dance.all.select do |dance|
            dance.order < 0 && (dance.freestyle_category == @category || dance.solo_category == @category)
          end

          dupes.each do |dupe|
            real = Dance.where(name: dupe.name, order: 0...).first
            dupe.heats.each do |heat|
              heat.dance = real
              heat.save!
            end
            dupe.delete
          end
        end
      end

      Dance.all.each do |dance|
        next if dance.order < 0
        if pro == "1"
          if dance.open_category == @category
            dance.open_category = nil
          end

          if dance.closed_category == @category
            dance.closed_category = nil
          end

          if dance.solo_category == @category
            dance.solo_category = nil
          end

          if dance.multi_category == @category
            dance.multi_category = nil
          end

          if dance.pro_open_category == @category
            if include['Open']&.[](dance.name).to_i == 0
              dance.pro_open_category = nil
            end
          elsif include['Open']&.[](dance.name).to_i == 1
            dance.pro_open_category = @category
          end

          if dance.pro_closed_category == @category
            if include['Closed']&.[](dance.name).to_i == 0
              dance.pro_closed_category = nil
            end
          elsif include['Closed']&.[](dance.name).to_i == 1
            dance.pro_closed_category = @category
          end

          if dance.pro_solo_category == @category
            if include['Solo']&.[](dance.name).to_i == 0
              dance.pro_solo_category = nil
            end
          elsif include['Solo']&.[](dance.name).to_i == 1
            dance.pro_solo_category = @category
          end

          if dance.pro_multi_category == @category
            if include['Multi']&.[](dance.name).to_i == 0
              dance.pro_multi_category = nil
            end
          elsif include['Multi']&.[](dance.name).to_i == 1
            dance.pro_multi_category = @category
          end

        else

          if dance.pro_open_category == @category
            dance.pro_open_category = nil
          end

          if dance.pro_closed_category == @category
            dance.pro_closed_category = nil
          end

          if dance.pro_solo_category == @category
            dance.pro_solo_category = nil
          end

          if dance.pro_multi_category == @category
            dance.pro_multi_category = nil
          end

          if include
            if include['Open']
              if dance.open_category == @category
                if include['Open'][dance.name].to_i == 0
                  dance.open_category = nil
                end
              elsif include['Open'][dance.name].to_i == 1
                dance.open_category = @category
              end
            end

            if include['Closed']
              if dance.closed_category == @category
                if include['Closed'][dance.name].to_i == 0
                  dance.closed_category = nil
                end
              elsif include['Closed'][dance.name].to_i == 1
                dance.closed_category = @category
              end
            end

            if dance.solo_category == @category
              if include['Solo'][dance.name].to_i == 0
                dance.solo_category = nil
              end
            elsif include['Solo'][dance.name].to_i == 1
              dance.solo_category = @category
            end

            if dance.multi_category == @category
              if include['Multi'][dance.name].to_i == 0
                dance.multi_category = nil
              end
            elsif include['Multi'] and include['Multi'][dance.name].to_i == 1
              dance.multi_category = @category
            end
          end
        end

        if dance.changed?
          dance.save!
          @total += 1
        end
      end
    end
end
