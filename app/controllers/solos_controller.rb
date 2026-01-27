class SolosController < ApplicationController
  before_action :set_solo, only: %i[ show edit update destroy ]
  include EntryForm
  include Printable
  include ActiveStorage::SetCurrent

  permit_site_owners(*%i[ show edit update ], trust_level: 25)
  permit_site_owners(*%i[ new create destroy ], trust_level: 50)
  before_action :set_studio_from_solo, only: %i[ edit update ]

  # GET /solos or /solos.json
  def index
    @solos = {}

    unscheduled = Struct.new(:id, :name).new(0, 'Unscheduled')
    Solo.ordered.each do |solo|
      next unless solo.heat.category == 'Solo'
      cat = solo.heat.dance_category
      cat = cat ? cat.base_category : unscheduled
      @solos[cat] ||= []
      @solos[cat] << solo.heat
    end

    sort_order = Category.pluck(:name, :order).to_h

    @solos = @solos.sort_by {|cat, heats| sort_order[cat&.name || ''] || 0}

    @track_ages = Event.current.track_ages
  end

  def djlist
    index

    @heats = @solos.map {|solo| solo.last}.flatten.sort_by {|heat| heat.number}
    @request_id = request.request_id

    respond_to do |format|
      format.html
      format.json {
        # Use request_id from params if provided (from JavaScript), otherwise use current request_id
        request_id = params[:request_id] || @request_id
        OfflinePlaylistJob.perform_later(Event.current.id, request_id)
        render json: { request_id: request_id, database: ENV['RAILS_APP_DB'], status: 'initiated' }
      }
      format.zip {
        filename = params[:filename]

        if filename.blank?
          render plain: "No filename provided", status: :bad_request
          return
        end

        # Security: only allow safe filenames (prevent directory traversal)
        unless filename.match?(/\Adj-playlist-\d+\.zip\z/)
          render plain: "Invalid filename", status: :bad_request
          return
        end

        file_path = Rails.root.join('tmp', 'offline_playlists', filename)

        if File.exist?(file_path)
          # Get file size for Content-Length header (needed for browser download progress)
          file_size = File.size(file_path)

          # Set headers to ensure proper download behavior
          response.headers['Content-Length'] = file_size.to_s
          response.headers['Content-Type'] = 'application/zip'
          response.headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
          response.headers['Cache-Control'] = 'no-cache, no-store'
          response.headers['Accept-Ranges'] = 'bytes'  # Enable range requests

          # Stream the file directly
          send_file file_path,
                    filename: filename,
                    type: 'application/zip',
                    disposition: 'attachment',
                    stream: true,         # Enable streaming
                    buffer_size: 65536   # 64KB chunks
        else
          Rails.logger.warn "Download failed - filename: #{filename}, file_exists: #{File.exist?(file_path)}"
          render plain: "Download link has expired or file not found. Please generate a new download.", status: :not_found
        end
      }
    end
  end

  def cleanup_cache
    filename = params[:filename]
    if filename.present?
      # Security: only allow safe filenames (prevent directory traversal)
      if filename.match?(/\Adj-playlist-\d+\.zip\z/)
        file_path = Rails.root.join('tmp', 'offline_playlists', filename)
        File.delete(file_path) if File.exist?(file_path)
      end
    end
    head :ok
  end

  # GET /solos/1 or /solos/1.json
  def show
  end

  # GET /solos/new
  def new
    @solo ||= Solo.new

    form_init(params[:primary])

    if params[:routine]
      @overrides = Category.where(routines: true).map {|category| [category.name, category.id]}
    end

    if Event.current.agenda_based_entries?
      # Use solo_category_id for agenda-based entries
      filtered_dances = Dance.where.not(solo_category_id: nil).by_name

      @dances = filtered_dances.all.map do |dance|
        if dance.order < 0
          id = Dance.find_by(name: dance.name, order: 0..)&.id || dance.id
          [dance.name, id]
        else
          [dance.name, dance.id]
        end
      end.uniq
    else
      @dances = Dance.where(order: 0...).by_name.all.map {|dance| [dance.name, dance.id]}
    end

    @partner = nil
    @age = @person&.age_id
    @level = @person&.level_id
  end

  # GET /solos/1/edit
  def edit
    event = Event.current
    form_init(params[:primary], @solo.heat.entry)

    @partner = @solo.heat.entry.partner(@person).id

    @instructor = @solo.heat.entry.instructor
    @age = @solo.heat.entry.age_id
    @level = @solo.heat.entry.level_id
    @dance = @solo.heat.dance.id
    @number = @solo.heat.number

    if event.agenda_based_entries?
      # Use solo_category_id for agenda-based entries
      dances = Dance.where.not(solo_category_id: nil).by_name

      @categories = dance_categories(@solo.heat.dance, true)

      @category = @dance

      if not dances.include? @solo.heat.dance
        @dance = dances.find {|dance| dance.name == @solo.heat.dance.name}&.id || @dance
      end

      @dances = dances.map do |dance|
        if dance.order < 0
          id = Dance.find_by(name: dance.name, order: 0..)&.id || dance.id
          [dance.name, id]
        else
          [dance.name, dance.id]
        end
      end.uniq
    else
      @dances = Dance.by_name.all.pluck(:name, :id)
    end

    if (@solo.category_override_id || Category.where(routines: true).any?) && !event.agenda_based_entries?
      @overrides = Category.where(routines: true).map {|category| [category.name, category.id]}
      cat = @solo.heat.dance.solo_category
      @overrides.unshift [cat.name, cat.id] if cat
    end

    @heat = params[:heat]
    @locked = Event.current.locked?
  end

  # POST /solos or /solos.json
  def create
    solo = params[:solo]
    formation = (solo[:formation]&.to_unsafe_h || {}).sort.to_h.values.map(&:to_i)
    solo[:instructor] ||= formation.first

    @heat = Heat.create!({
      number: solo[:number] || 0,
      entry: find_or_create_entry(solo),
      category: "Solo",
      dance: Dance.find(solo[:dance_id].to_i)
    })

    @solo = Solo.new(solo_params)
    @solo.heat = @heat

    if solo[:combo_dance_id] != ''
      @solo.combo_dance = Dance.find(solo[:combo_dance_id].to_i)
    end

    if solo[:category_override_id]
      @solo.category_override = Category.find(solo[:category_override_id].to_i)
    end

    @solo.order = (Solo.maximum(:order) || 0) + 1

    respond_to do |format|
      if @solo.save
        target = @person

        formation.each do |dancer|
          person = Person.find(dancer.to_i)
          Formation.create! solo: @solo, person: person,
            on_floor: (person.type != 'Professional' || solo[:on_floor] != '0')
          target = person.studio if target.id == 0
        end

        format.html { redirect_to target,
          notice: "#{formation.empty? ? 'Solo' : 'Formation'} was successfully created." }
        format.json { render :show, status: :created, location: @solo }
      else
        new
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @solo.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /solos/1 or /solos/1.json
  def update
    solo = params[:solo]
    formation = (solo[:formation]&.to_unsafe_h || {}).sort.to_h.values.map(&:to_i)
    solo[:instructor] ||= formation.first

    entry = @solo.heat.entry
    replace = find_or_create_entry(solo)

    if replace != entry
      @solo.heat.entry = replace
    end

    @solo.heat.dance = Dance.find(solo[:dance_id])
    @solo.heat.number = solo[:number] if solo[:number]
    @solo.heat.save!

    if solo[:combo_dance_id].empty?
      @solo.combo_dance = nil
    else
      @solo.combo_dance = Dance.find(solo[:combo_dance_id].to_i)
    end

    if solo[:category_override_id]
      @solo.category_override = Category.find(solo[:category_override_id].to_i)
    end

    if not formation.empty? or not @solo.formations.empty?
      @solo.formations.each do |record|
        if not formation.include? record.person_id
          Formation.delete(record)
        elsif record.person.type == "Professional"
          record.update on_floor: solo[:on_floor] == '1'
        end
      end

      formation.each do |person_id|
        unless @solo.formations.to_a.any? {|record| record.person_id == person_id}
          person = Person.find(person_id)
          Formation.create! solo: @solo, person: person,
            on_floor: (person.type != 'Professional' || solo[:on_floor] != '0')
        end
      end
    end

    respond_to do |format|
      # shouldn't happen, but apparently does.
      if Solo.where(order: @solo.order).count > 1
        @solo.order = Solo.maximum(:order) + 1
      end

      if @solo.update(solo_params)
        format.html { redirect_to params['return-to'] || @person,
          notice: "#{formation.empty? ? 'Solo' : 'Formation'} was successfully updated." }
        format.json { render :show, status: :ok, location: @solo }
      else
        edit
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @solo.errors, status: :unprocessable_content }
      end
    end

    if replace != entry
      entry.reload
      entry.destroy if entry.heats.empty?
    end
  end

   # POST /solos/drop
   def drop
    source = Solo.find(params[:source].to_i)
    target = Solo.find(params[:target].to_i)

    # First, detect and fix any duplicate order values
    all_solos = Solo.all.order(:order, :id)
    orders = all_solos.pluck(:order)
    duplicates = orders.select { |order| orders.count(order) > 1 }.uniq
    
    if duplicates.any?
      # Fix duplicate orders by reassigning sequential values
      Solo.transaction do
        # Temporarily set all orders to negative values to avoid uniqueness conflicts
        all_solos.each_with_index do |solo, index|
          solo.update_column(:order, -(index + 1))
        end
        
        # Now set them to proper sequential values
        all_solos.each_with_index do |solo, index|
          solo.update_column(:order, index + 1)
        end
      end
      
      # Reload source and target with new order values
      source.reload
      target.reload
    end

    # Call index to get all solos organized by category
    index
    
    # Find which category contains our source solo
    category = nil
    category_heats = []
    
    @solos.each do |cat, heats|
      if heats.any? { |heat| heat.id == source.heat_id }
        category = cat
        category_heats = heats
        break
      end
    end
    
    # Get the solos for this category from the heats
    solos = Solo.where(heat_id: category_heats.map(&:id)).ordered

    if source.order > target.order
      slice = solos.where(order: target.order..source.order)
      new_order = slice.map(&:order).rotate(1)
    else
      slice = solos.where(order: source.order..target.order)
      new_order = slice.map(&:order).rotate(-1)
    end

    scheduled = slice.select {|solo| solo.heat.number > 0}
    heat_numbers = scheduled.map {|solo| solo.heat.number}.sort
    new_heat_number = slice.map(&:order).zip(heat_numbers).to_h

    Solo.transaction do
      slice.zip(new_order).each do |solo, order|
        if new_heat_number[order]
          solo.heat.number = new_heat_number[order]
          solo.heat.save!
        end

        solo.order = order
        solo.save! validate: false
      end

      raise ActiveRecord::Rollback unless solos.all? {|solo| solo.valid?}
    end

    respond_to do |format|
      format.turbo_stream {
        # Call index again to get the updated heats after the order changes
        index
        
        # Find the updated heats for the affected category
        updated_heats = @solos.find { |cat, _| cat == category || (cat && category && cat.id == category.id) }&.last || []
        
        # Determine the DOM ID based on the category
        # Handle both Category instances and the unscheduled Struct
        id = if category.nil?
          'category_0'
        elsif category.is_a?(Category)
          helpers.dom_id(category)
        else
          # This is the unscheduled Struct with id=0
          "category_#{category.id}"
        end

        render turbo_stream: turbo_stream.replace(id,
          render_to_string(partial: 'cat', layout: false, locals: {heats: updated_heats, id: id, category: category})
        )
      }

      format.html { redirect_to categories_url }
    end
  end

  # DELETE /solos/1 or /solos/1.json
  def destroy
    person = Person.find(params[:primary])

    entry = @solo.heat.entry
    formation = @solo.formations.to_a

    if @solo.heat.number != 0
      notice = "#{formation.empty? ? 'Solo' : 'Formation'} was successfully #{@solo.heat.number < 0 ? 'restored' : 'scratched'}."
      @solo.heat.update_attribute(:number, -@solo.heat.number)
    else
      @solo.heat.destroy
      entry.reload
      entry.destroy! if entry.heats.empty?
      notice = "#{formation.empty? ? 'Solo' : 'Formation'} was successfully removed."
    end

    respond_to do |format|
      format.html { redirect_to person_path(person), status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  def sort_level
    solos = {}
    order = []

    # Group solos by category (e.g., Show 1, Show 2, Show 3) to keep shows separate
    unscheduled = Struct.new(:id, :name).new(0, 'Unscheduled')
    Solo.ordered.each do |solo|
      next unless solo.heat.category == 'Solo'
      cat = solo.heat.dance_category
      cat = cat ? cat.base_category : unscheduled
      solos[cat] ||= []
      solos[cat] << solo
    end

    # Sort categories by their order
    sort_order = Category.pluck(:name, :order).to_h
    solos = solos.sort_by {|cat, heats| sort_order[cat&.name || ''] || 0}

    solos.each do |cat, solos|
      # Check if category has a split point
      split_point = cat.respond_to?(:heats) ? cat.heats : nil

      if split_point && solos.length > split_point
        # Split into groups and sort each separately
        group1 = solos[0...split_point].sort_by {|solo| solo.heat.entry.level_id}
        group2 = solos[split_point..-1].sort_by {|solo| solo.heat.entry.level_id}
        order += group1 + group2
      else
        # No split, sort all together
        order += solos.sort_by {|solo| solo.heat.entry.level_id}
      end
    end

    new_heat_number = renumber_heats(order)

    Solo.transaction do
      order.zip(1..).each do |solo, new_order|
        solo.order = new_order

        # Update heat number if this solo was scheduled
        if new_heat_number[new_order]
          solo.heat.number = new_heat_number[new_order]
          solo.heat.save! validate: false
        end

        solo.save! validate: false
      end
    end

    respond_to do |format|
      format.html { redirect_to solos_path, notice: 'solos sorted by level' }
    end
  end

  def sort_gap
    order = []
    notice = "solos optimized for maximum gaps"
    solos = {}

    # Group solos by category (e.g., Show 1, Show 2, Show 3) to keep shows separate
    unscheduled = Struct.new(:id, :name).new(0, 'Unscheduled')
    Solo.all.each do |solo|
      next unless solo.heat.category == 'Solo'
      cat = solo.heat.dance_category
      cat = cat ? cat.base_category : unscheduled
      solos[cat] ||= []
      solos[cat] << solo
    end

    # Sort categories by their order
    sort_order = Category.pluck(:name, :order).to_h
    solos = solos.sort_by {|cat, heats| sort_order[cat&.name || ''] || 0}

    solos.each do |cat, category_solos|
      # Check if category has a split point
      split_point = cat.respond_to?(:heats) ? cat.heats : nil

      # Create groups based on split point
      groups = []
      if split_point && category_solos.length > split_point
        groups << category_solos[0...split_point]
        groups << category_solos[split_point..-1]
      else
        groups << category_solos
      end

      # Process each group separately with the gap optimization algorithm
      groups.each do |solos|
      # Shuffle-and-swap optimization algorithm
      # Start with a random order, then iteratively swap pairs to improve min gap
      schedule = solos.shuffle

      # Precompute people for each solo (excluding Nobody)
      solo_people = {}
      schedule.each do |solo|
        entry = solo.heat.entry
        people = [entry.lead, entry.follow] + solo.formations.map(&:person)
        solo_people[solo] = people.reject { |p| p.id == 0 }
      end

      # Calculate the sum of inverse gaps (lower is better) and minimum gap
      evaluate = ->(ordering) {
        last_pos = {}
        min_gap = ordering.length
        total_penalty = 0.0

        ordering.each_with_index do |solo, pos|
          solo_people[solo].each do |person|
            if last_pos[person]
              gap = pos - last_pos[person]
              min_gap = gap if gap < min_gap
              total_penalty += 1.0 / gap
            end
            last_pos[person] = pos
          end
        end

        [min_gap, total_penalty]
      }

      current_min_gap, current_penalty = evaluate.call(schedule)

      # Run swap iterations: try random swaps, keep improvements
      # More iterations for larger lists
      iterations = solos.length * solos.length * 3
      iterations.times do
        i = rand(schedule.length)
        j = rand(schedule.length)
        next if i == j

        schedule[i], schedule[j] = schedule[j], schedule[i]
        new_min_gap, new_penalty = evaluate.call(schedule)

        # Keep swap if it improves min gap, or same min gap with lower penalty
        if new_min_gap > current_min_gap ||
           (new_min_gap == current_min_gap && new_penalty < current_penalty)
          current_min_gap = new_min_gap
          current_penalty = new_penalty
        else
          # Revert swap
          schedule[i], schedule[j] = schedule[j], schedule[i]
        end
      end

      order += schedule
      end # groups.each
    end # solos.each

    new_heat_number = renumber_heats(order)

    Solo.transaction do
      order.zip(1..).each do |solo, new_order|
        solo.order = new_order

        # Update heat number if this solo was scheduled
        if new_heat_number[new_order]
          solo.heat.number = new_heat_number[new_order]
          solo.heat.save! validate: false
        end

        solo.save! validate: false
      end
    end

    respond_to do |format|
      format.html { redirect_to solos_path, notice: notice  }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_solo
      @solo = Solo.find(params[:id])
    end

    # Set @studio from the solo's lead or follow for ownership checking
    # This allows authenticate_site_owner to restrict access to owned studios only
    def set_studio_from_solo
      entry = @solo.heat.entry
      @studio = entry.lead.studio || entry.follow.studio
    end

    # Renumber heats to match new solo order
    # Takes an array of solos in their new order and returns a hash mapping
    # new solo order positions to heat numbers
    def renumber_heats(ordered_solos)
      scheduled = ordered_solos.select {|solo| solo.heat.number > 0}
      heat_numbers = scheduled.map {|solo| solo.heat.number}.sort
      ordered_solos.map.with_index(1) {|solo, idx| [idx, heat_numbers.shift]}.to_h
    end

    # Only allow a list of trusted parameters through.
    def solo_params
      params.require(:solo).permit(:heat_id, :combo_dance_id, :order, :song, :artist, :song_file)
    end
  end
