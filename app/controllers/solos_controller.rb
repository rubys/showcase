class SolosController < ApplicationController
  before_action :set_solo, only: %i[ show edit update destroy ]
  include EntryForm
  include Printable
  include ActiveStorage::SetCurrent

  permit_site_owners(*%i[ show ], trust_level: 25)
  permit_site_owners(*%i[ new create edit update destroy ], trust_level: 50)

  # GET /solos or /solos.json
  def index
    @solos = {}

    unscheduled = Struct.new(:id, :name).new(0, 'Unscheduled')
    Solo.order(:order).each do |solo|
      next unless solo.heat.category == 'Solo'
      cat = solo.heat.dance_category
      cat = cat ? cat.base_category : unscheduled
      @solos[cat] ||= []
      @solos[cat] << solo.heat
    end

    sort_order = Category.pluck(:name, :order).to_h

    @solos = @solos.sort_by {|cat, heats| sort_order[cat&.name || ''] || 0}

    @track_ages = Event.last.track_ages
  end

  def djlist
    index

    @heats = @solos.map {|solo| solo.last}.flatten.sort_by {|heat| heat.number}
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

    if Event.first.agenda_based_entries?
      category = (@person.type == 'Professional') ? :pro_solo_category : :solo_category
      @dances = Dance.where(order: 0...).where.not(category => nil).order(:name).all.map {|dance| [dance.name, dance.id]}
    else
      @dances = Dance.where(order: 0...).order(:name).all.map {|dance| [dance.name, dance.id]}
    end

    @partner = nil
    @age = @person&.age_id
    @level = @person&.level_id
  end

  # GET /solos/1/edit
  def edit
    event = Event.last
    form_init(params[:primary], @solo.heat.entry)

    @partner = @solo.heat.entry.partner(@person).id

    @instructor = @solo.heat.entry.instructor
    @age = @solo.heat.entry.age_id
    @level = @solo.heat.entry.level_id
    @dance = @solo.heat.dance.id
    @number = @solo.heat.number

    if event.agenda_based_entries?
      category = (@person.type == 'Professional' && Person.find(@partner)&.type == 'Professional') ? :pro_solo_category : :solo_category
      dances = Dance.where(order: 0...).where.not(category => nil).order(:name)

      @categories = dance_categories(@solo.heat.dance, true)

      @category = @dance

      if not dances.include? @solo.heat.dance
        @dance = dances.find {|dance| dance.name == @solo.heat.dance.name}&.id || @dance
      end

      @dances = dances.map {|dance| [dance.name, dance.id]}
    else
      @dances = Dance.order(:name).all.pluck(:name, :id)
    end

    if (@solo.category_override_id || Category.where(routines: true).many?) && !event.agenda_based_entries?
      @overrides = Category.where(routines: true).map {|category| [category.name, category.id]}
    end

    @heat = params[:heat]
    @locked = Event.last.locked?
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
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @solo.errors, status: :unprocessable_entity }
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
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @solo.errors, status: :unprocessable_entity }
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

    category = source.heat.solo.category_override
    if category
      solos = Solo.order(:order).where(category_override_id: category.id)
    else
      category = source.heat.dance.solo_category
      solos = Solo.where(category_override_id: nil).order(:order).joins(heat: :dance).where(dance: {solo_category_id: category&.id})
    end

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
        id = category ? helpers.dom_id(category) : 'category_0'
        heats = solos.map(&:heat)

        render turbo_stream: turbo_stream.replace(id,
          render_to_string(partial: 'cat', layout: false, locals: {heats: heats, id: id})
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

    Solo.order(:order).each do |solo|
      cat = solo.heat.dance.solo_category
      solos[cat] ||= []
      solos[cat] << solo
    end

    solos.each do |cat, solos|
      order += solos.sort_by {|solo| solo.heat.entry.level_id}
    end

    Solo.transaction do
      order.zip(1..).each do |solo, order|
        solo.order = order
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
    notice = "solos remixed"
    solos = {}

    Solo.all.each do |solo|
      cat = solo.heat.dance.solo_category
      solos[cat] ||= []
      solos[cat] << solo
    end

    solos.each do |cat, solos|
      participants = {}
      solos.shuffle.sort_by {|solo| solo.heat.entry.level_id}.each do |solo|
        entry = solo.heat.entry
        participants[entry.lead] ||= []
        participants[entry.lead] << solo
        participants[entry.follow] ||= []
        participants[entry.follow] << solo
      end

      weights = solos.map {|solo| [solo, 0]}.to_h

      singles = []
      levels = Level.maximum(:id)

      participants.each do |person, solos|
        singles << solos.first if solos.length == 1
      end

      singles.sort_by! {|solo| solo.heat.entry.level_id}

      participants.each do |person, solos|
        if solos.length == 1
          weights[solos.first] += (singles.find_index(solos.first).to_f + 1) / (levels + 1)
        else
          solos.sort_by! {|solo| solo.heat.entry.level_id}
          solos.each_with_index do |solo, index|
            weights[solo] += (index.to_f + 1) / (solos.length + 1)
          end
        end
      end

      weights = weights.to_a.sort_by {|solo, weight| weight}.to_h

      solo_count = solos.count.to_f
      ideal = solo_count / participants.values.map(&:length).max

      cat_order = weights.keys

      solo_count.to_i.times do |iteration|
        new_order = []

        last_seen = participants.map {|person| [person, nil]}.to_h

        cat_order.reverse! if iteration % 2 == 1
        solo1 = cat_order.first
        entry1 = solo1.heat.entry
        last_seen[entry1.lead] = -1
        last_seen[entry1.follow] = -1

        cat_order[1..].each_with_index do |solo2, index|

          weight1 = entry1.level_id
          [entry1.lead, entry1.follow].each do |person|
            count = participants[person].length
            if count > 1
              seen = last_seen[person]
              span = seen ? index-seen : index
              weight1 += ideal - span
            end
          end

          entry2 = solo2.heat.entry
          weight2 = entry2.level_id
          [entry2.lead, entry2.follow].each do |person|
            count = participants[person].length
            if count > 1
              seen = last_seen[person]
              span = seen ? index-seen : index
              weight2 += ideal - span
            end
            last_seen[person] = index
          end

          if weight2 < weight1
            new_order << solo2
          else
            new_order << solo1
            solo1, entry1 = solo2, entry2
          end
        end

        new_order << solo1
        break if new_order == cat_order
        new_order.reverse! if iteration % 2 == 1
        cat_order = new_order
      end

      order += cat_order
    end

    Solo.transaction do
      order.zip(1..).each do |solo, order|
        solo.order = order
        solo.save! validate: false
      end

      raise ActiveRecord::Rollback unless order.all? {|solo| solo.valid?}
    end

    respond_to do |format|
      format.html { redirect_to solos_path, notice: notice  }
    end
  end

  def critiques
    index
    @judges = Person.where(type: 'Judge').all
    @event = Event.first
    @layout = 'mx-0'
    @nologo = true
    @font_size = @event.font_size
  end

  def critiques0
    critiques

    respond_to do |format|
      format.html { render :critique0 }
      format.pdf do
        render_as_pdf basename: "solo-critiques"
      end
    end
  end

  def critiques1
    critiques

    respond_to do |format|
      format.html { render :critique1 }
      format.pdf do
        render_as_pdf basename: "solo-critiques"
      end
    end
  end

  def critiques2
    critiques

    respond_to do |format|
      format.html { render :critique2 }
      format.pdf do
        render_as_pdf basename: "solo-critiques"
      end
    end
  end
  private
    # Use callbacks to share common setup or constraints between actions.
    def set_solo
      @solo = Solo.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def solo_params
      params.require(:solo).permit(:heat_id, :combo_dance_id, :order, :song, :artist, :song_file)
    end
  end
