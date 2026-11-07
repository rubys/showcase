class CategoriesController < ApplicationController
  include Printable
  include HeatScheduler
  before_action :set_category, only: %i[ show edit update destroy ]

  permit_site_owners :toggle_lock, trust_level: 100

  # One row of the Agenda page: a run of consecutive heats belonging to a
  # category or part.  A category interrupted by another has several rows; its
  # occurrence counts them, and any after the first are its "(continued)" rows.
  # Categories with no heats, such as breaks, have a single row with no heats.
  AgendaRow = Struct.new(:key, :name, :cat, :occurrence, :heats, keyword_init: true) do
    def continued? = occurrence > 0
    def scheduled? = heats.any?
    def drag_id = "#{cat.id}#{"-#{cat.part}" if cat.part}#{":#{occurrence}" if continued?}"
  end

  # GET /categories or /categories.json
  def index
    @include_times = true  # Override for admin view
    generate_agenda
    @agenda = @agenda.to_h
    @categories = (Category.all + CatExtension.all).sort_by {|cat| cat.order}
    @agenda_rows = agenda_rows
    @locked = Event.current.locked?
    @settings = params[:settings]

    if @settings
      @event = Event.current
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
    @event_date = Event.current.date

    form_init
  end

  # GET /categories/1/edit
  def edit
    @include_times = true  # Override for admin view
    generate_agenda
    @day_placeholder = Date::DAYNAMES[@cat_start&.dig(@category.name)&.wday || 7]
    @event_date = Event.current.date

    # canonicalize time
    if @event_date =~ /\d{4}-\d{2}-\d{2}/ && !@category.time.blank? && @category.time !~ /\d{2}:\d{2}$/
      @category.time = Chronic.parse(@category.time).iso8601[11..15]
    end

    form_init
  end

  # POST /categories or /categories.json
  def create
    if params[:category][:customize] != '1'
      params[:category][:ballrooms] = ''
      params[:category][:max_heat_size] = ''
      params[:category][:split] = ''
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
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @category.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /categories/1 or /categories/1.json
  def update
    params[:category] ||= params[:cat_extension]

    if params[:category][:customize] != '1' and @category.instance_of? Category
      params[:category][:ballrooms] = ''
      params[:category][:max_heat_size] = ''
      params[:category][:split] = ''
    end

    needs_renumbering = false
    redo_agenda = false

    if @category.instance_of?(Category) && (!params[:category][:split].blank? || @category.extensions.any?)
      @include_times = true  # Override for admin view
      generate_agenda

      # Collect all agenda entries for this category (including split/continued versions)
      category_heats = @agenda.select { |key, _| key == @category.name || key.start_with?("#{@category.name} (continued") }.values.flatten(1)
      extension_heats = @category.extensions.flat_map { |ext|
        @agenda.select { |key, _| key == ext.name || key.start_with?("#{ext.name} (continued") }.values
      }.flatten(1)

      heats = category_heats.length + extension_heats.length
      extensions_found = @category.extensions.order(:part).all.to_a
      extensions_needed = 0
      if !params[:category][:split].blank?
        split = params[:category][:split].split(/[, ]+/).map(&:to_i)
        heat_count = heats
         loop do
           block = split.shift
           break if block >= heat_count || block <= 0
           extensions_needed += 1
           heat_count -= block
           split.push block if split.empty?
         end
      end

      while extensions_found.length > extensions_needed
        extensions_found.pop&.destroy!
        redo_agenda = true
      end

      while extensions_needed > extensions_found.length
        order = [Category.maximum(:order), CatExtension.maximum(:order)].compact.max + 1
        extensions_found << CatExtension.create!(category: @category, order: order, part: extensions_found.length + 2)
        needs_renumbering = true
        redo_agenda = true
      end
    end

    respond_to do |format|
      if @category.update(category_params)
        update_dances(params[:category][:include], params[:category][:pro])

        renumber_extensions if needs_renumbering

        if redo_agenda
          ActiveRecord::Base.connection.query_cache.clear
          @include_times = true  # Override for admin view
          generate_agenda
        end

        format.html { redirect_to categories_url, notice: "#{@category.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @category }
      else
        edit
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @category.errors, status: :unprocessable_content }
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
      event = Event.current
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
    @include_times = true  # Override for admin view
    generate_agenda
    rows = agenda_rows
    source = rows.find {|row| row.drag_id == params[:source].to_s}
    target = rows.find {|row| row.drag_id == params[:target].to_s}

    problem = if Event.current.locked?
      "The agenda is locked; unlock it to rearrange the agenda."
    elsif source.nil? || target.nil?
      "The agenda has changed; please try again."
    else
      section_move_problem(rows, source, target)
    end

    move_section(rows, source, target) unless problem

    index

    if problem
      flash.now.alert = problem
    else
      flash.now.notice = "#{source.name} was successfully moved."
    end

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
      params.expect(category: [:name, :order, :day, :time, :ballrooms, :max_heat_size, :split, :duration, :routines, :cost_override, :pro, :studio_cost_override, :use_category_scoring])
    end

    def form_init
      dances = Dance.ordered.all
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

      event = Event.current
      @pro_option = event.pro_heats
      @include_open = event.include_open || Heat.where(category: 'Open').size > 0
      @include_closed = event.include_closed || Heat.where(category: 'Closed').size > 0
    end

    # Remove a split dance that is no longer part of the category, unless it is
    # still in use.  Solos that reference it as a combo dance are pointed at the
    # canonical dance of the same name; if there isn't one, the dance is left
    # alone rather than leaving those solos with a dangling reference.
    def remove_split_dance(dance)
      return if dance.heats.any?

      combos = Solo.where(combo_dance_id: dance.id)
      if combos.any?
        canonical = Dance.find_by(name: dance.name, order: 0...)
        return unless canonical
        combos.update_all(combo_dance_id: canonical.id)
      end

      dance.destroy!
    end

    def update_dances(include, pro)
      @total = 0

      categories = [
        ['Open', :open_category, :pro_open_category],
        ['Closed', :closed_category, :pro_closed_category],
        ['Solo', :solo_category, :pro_solo_category],
        ['Multi', :multi_category, :pro_multi_category]
      ]

      if Event.current.agenda_based_entries?
        if @category.routines?
          categories.each do |cat, normal, pro|
            # Delete all dances that are not longer in the category
            # resetting the included count for those that are
            Dance.all.each do |dance|
              next if dance.order >= 0
              if dance.send(normal) == @category
                if pro == '1' || include[cat]&.[](dance.name).to_i == 0
                  remove_split_dance(dance)
                elsif include[cat]&.[](dance.name).to_i > 0
                  include[cat][dance.name] = 0
                end
              end

              if dance.send(pro) == @category
                if pro == '0' || include[cat]&.[](dance.name).to_i == 0
                  remove_split_dance(dance)
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
            real = Dance.find_by(name: dupe.name, order: 0...)
            dupe.heats.each do |heat|
              heat.dance = real
              heat.save!
            end
            Solo.where(combo_dance_id: dupe.id).update_all(combo_dance_id: real&.id)
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

    # The rows of the Agenda page, in the order they happen: by heat number, with
    # each category that has no heats following the category before it in the
    # stored order, so that it holds its place until it has heats of its own.
    # Requires generate_agenda to have been run.
    def agenda_rows
      categories = (Category.all.to_a + CatExtension.all.to_a).sort_by(&:order)
      by_name = categories.index_by(&:name)
      occurrences = Hash.new(0)
      rows = []

      @agenda.each do |key, heats|
        next if %w[Unscheduled Uncategorized].include?(key)

        name = @agenda_display_names&.dig(key) || key
        cat = @agenda_cat&.dig(key) || by_name[name.sub(/ \(continued.*\)$/, '')]
        next unless cat

        rows << AgendaRow.new(key: key, name: name, cat: cat, occurrence: occurrences[cat], heats: heats)
        occurrences[cat] += 1
      end

      previous = nil
      categories.each do |cat|
        unless occurrences.key?(cat)
          after = previous && rows.rindex {|row| row.cat == previous}
          rows.insert(after ? after + 1 : 0, AgendaRow.new(key: cat.name, name: cat.name, cat: cat, occurrence: 0, heats: []))
        end
        previous = cat
      end

      rows
    end

    # Which part a heat belongs to is worked out from its position within its
    # category, so a row can't pass another row of the same category: the heats
    # would move, but the labels would stay where they were.  Returns the reason
    # a move isn't possible, if any.
    def section_move_problem(rows, source, target)
      return unless source.scheduled?

      from, to = rows.index(source), rows.index(target)
      crossed = rows[([from, to].min)..([from, to].max)] - [source]
      blocker = crossed.find {|row| row.scheduled? && row.cat.base_category == source.cat.base_category}

      return unless blocker
      "#{source.name} can't move past #{blocker.name}: parts of a category need to stay in sequence."
    end

    # Put source where target is.  Heats move along with their row, and every
    # other row keeps its heats and its place relative to the others.
    def move_section(rows, source, target)
      reordered = rows.dup
      reordered.insert(rows.index(target), reordered.delete(source))

      ActiveRecord::Base.transaction do
        renumber_heats_to_match(reordered)

        # Keep the stored order in step, so that Redo and the positions of
        # categories without heats both follow what is shown on the page.
        ordered = reordered.map(&:cat).uniq
        ordered.zip(ordered.map(&:order).sort).each do |cat, order|
          cat.update_column(:order, order) unless cat.order == order
        end

        refresh_extension_starts
      end
    end

    def renumber_extensions
      @include_times = true  # Override for admin view
      generate_agenda

      ActiveRecord::Base.transaction do
        renumber_heats_to_match(agenda_rows)
        refresh_extension_starts
      end
    end

    # Number heats 1..N following rows.  Uncategorized heats follow all of the
    # rows, which is where the agenda shows them.  Scratched heats have negative
    # numbers, and are moved along with the rest without being restored.
    def renumber_heats_to_match(rows)
      heats = Heat.where.not(number: 0).pluck(:id, :number)

      sequence = rows.flat_map(&:heats) + (@agenda['Uncategorized'] || [])
      sequence = sequence.map {|number, _ballrooms| number.to_f.abs}
      sequence += heats.map {|_id, number| number.abs}.sort

      new_numbers = sequence.uniq.each_with_index.to_h {|number, index| [number, index + 1.0]}

      heats.group_by {|_id, number| number.negative? ? -new_numbers[-number] : new_numbers[number]}.each do |number, group|
        ids = group.reject {|_id, previous| previous == number}.map(&:first)
        Heat.where(id: ids).update_all(number: number, updated_at: Time.current) if ids.any?
      end
    end

    # Heat#dance_category identifies a part by the heat it starts with.
    def refresh_extension_starts
      generate_agenda

      CatExtension.all.each do |ext|
        ext.update_column(:start_heat, @agenda[ext.name]&.first&.first)
      end
    end
end
