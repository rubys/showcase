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
          render_to_string(partial: 'cat', layout: false, locals: {heats: updated_heats, id: id})
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
      @solo.heat.update(number: -@solo.heat.number)
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

    Solo.ordered.each do |solo|
      cat = solo.heat.dance.solo_category
      solos[cat] ||= []
      solos[cat] << solo
    end

    solos.each do |cat, solos|
      order += solos.sort_by {|solo| solo.heat.entry.level_id}
    end

    new_heat_number = renumber_heats(order)

    Solo.transaction do
      order.zip(1..).each do |solo, new_order|
        solo.order = new_order

        # Update heat number if this solo was scheduled
        if new_heat_number[new_order]
          solo.heat.number = new_heat_number[new_order]
          solo.heat.save!
        end

        solo.save! validate: false
      end

      raise ActiveRecord::Rollback unless order.all? {|solo| solo.valid?}
    end

    respond_to do |format|
      format.html { redirect_to solos_path, notice: 'solos sorted by level' }
    end
  end

  def sort_gap
    order = []
    notice = "solos optimized for maximum gaps"
    solos = {}

    Solo.all.each do |solo|
      cat = solo.heat.dance.solo_category
      solos[cat] ||= []
      solos[cat] << solo
    end

    solos.each do |cat, solos|
      # Build participants hash with ALL people in each solo (lead, follow, formations)
      # Exclude Nobody (person 0) who is a placeholder for studio formations
      participants = {}
      solos.each do |solo|
        entry = solo.heat.entry
        people = [entry.lead, entry.follow] + solo.formations.map(&:person)
        people.reject! { |person| person.id == 0 }  # Exclude Nobody

        people.each do |person|
          participants[person] ||= []
          participants[person] << solo
        end
      end

      # Calculate minimum gap for a given ordering
      calculate_min_gap = ->(ordering) {
        min_gap = Float::INFINITY
        last_positions = {}

        ordering.each_with_index do |solo, position|
          entry = solo.heat.entry
          people = [entry.lead, entry.follow] + solo.formations.map(&:person)
          people.reject! { |person| person.id == 0 }  # Exclude Nobody

          people.each do |person|
            if last_positions[person]
              gap = position - last_positions[person]
              min_gap = gap if gap < min_gap
            end
            last_positions[person] = position
          end
        end

        min_gap == Float::INFINITY ? solos.length : min_gap
      }

      # Round-robin slot distribution algorithm
      # Place high-frequency performers first, distributing evenly across slots

      # Create empty schedule slots
      schedule = Array.new(solos.length, nil)
      placed_solos = Set.new

      # Track ALL positions of each person for conflict checking
      person_positions = Hash.new { |h, k| h[k] = [] }

      # Sort people by number of appearances (descending), shuffle to randomize ties
      sorted_people = participants.sort_by { |person, person_solos|
        [-person_solos.length, rand]
      }.map(&:first)

      # Process each person in order
      sorted_people.each do |person|
        person_solos = participants[person].reject { |solo| placed_solos.include?(solo) }
        next if person_solos.empty?

        # Calculate ideal spacing for this person's solos
        count = person_solos.length
        spacing = solos.length.to_f / count

        # Find available slots, trying to space evenly
        target_positions = count.times.map { |i| (i * spacing).round }

        # For each of this person's solos, find the best available slot
        person_solos.each_with_index do |solo, idx|
          target = target_positions[idx]

          # Find nearest available slot to target
          best_slot = nil
          best_score = -Float::INFINITY

          schedule.each_with_index do |slot_solo, slot_idx|
            next if slot_solo  # Slot already filled

            # Check if placing this solo here would conflict with other people in it
            entry = solo.heat.entry
            people_in_solo = [entry.lead, entry.follow] + solo.formations.map(&:person)
            people_in_solo.reject! { |p| p.id == 0 }

            # Check for conflicts (other people in this solo already placed nearby)
            conflict = false
            min_gap = Float::INFINITY

            people_in_solo.each do |other_person|
              # Check all existing positions for this person
              person_positions[other_person].each do |pos|
                gap = (slot_idx - pos).abs
                min_gap = gap if gap < min_gap

                # Hard conflict: too close to any appearance
                if gap < 2
                  conflict = true
                  break
                end
              end
              break if conflict
            end

            next if conflict

            # Calculate score: prioritize min gap, then distance from target
            distance = (slot_idx - target).abs
            score = min_gap * 1000 - distance

            if score > best_score
              best_score = score
              best_slot = slot_idx
            end
          end

          # Place the solo in the best available slot
          if best_slot
            schedule[best_slot] = solo
            placed_solos.add(solo)

            # Update positions for all people in this solo
            entry = solo.heat.entry
            people_in_solo = [entry.lead, entry.follow] + solo.formations.map(&:person)
            people_in_solo.reject! { |p| p.id == 0 }
            people_in_solo.each { |p| person_positions[p] << best_slot }
          end
        end
      end

      # Fill any remaining empty slots with unplaced solos
      remaining_solos = solos.reject { |solo| placed_solos.include?(solo) }
      schedule.each_with_index do |slot_solo, idx|
        if slot_solo.nil? && remaining_solos.any?
          schedule[idx] = remaining_solos.shift
        end
      end

      # Remove any nils and add to order
      order += schedule.compact
    end

    new_heat_number = renumber_heats(order)

    Solo.transaction do
      order.zip(1..).each do |solo, new_order|
        solo.order = new_order

        # Update heat number if this solo was scheduled
        if new_heat_number[new_order]
          solo.heat.number = new_heat_number[new_order]
          solo.heat.save!
        end

        solo.save! validate: false
      end

      raise ActiveRecord::Rollback unless order.all? {|solo| solo.valid?}
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
