class SolosController < ApplicationController
  before_action :set_solo, only: %i[ show edit update destroy ]
  include EntryForm
  include ActiveStorage::SetCurrent

  # GET /solos or /solos.json
  def index
    @solos = {}

    Solo.order(:order).each do |solo|
      cat = solo.heat.dance.solo_category
      @solos[cat] ||= []
      @solos[cat] << solo.heat
    end

    sort_order = Category.pluck(:name, :order).to_h

    @solos = @solos.sort_by {|cat, heats| sort_order[cat&.name]}

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

    @dances = Dance.order(:name).all.map {|dance| [dance.name, dance.id]}

    @partner = nil
    @age = @person&.age_id
    @level = @person&.level_id
  end

  # GET /solos/1/edit
  def edit
    form_init(params[:primary], @solo.heat.entry)

    @partner = @solo.heat.entry.partner(@person).id

    @dances = Dance.order(:name).all.map {|dance| [dance.name, dance.id]}

    @instructor = @solo.heat.entry.instructor
    @age = @solo.heat.entry.age_id
    @level = @solo.heat.entry.level_id
    @dance = @solo.heat.dance.id
    @number = @solo.heat.number

    @heat = params[:heat]
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

    @solo.order = (Solo.maximum(:order) || 0) + 1

    respond_to do |format|
      if @solo.save
        formation.each do |dancer|
          person = Person.find(dancer.to_i)
          Formation.create! solo: @solo, person: person,
            on_floor: (person.type != 'Professional' || solo[:on_floor] != '0')
        end

        format.html { redirect_to @person, 
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
      if @solo.update(solo_params)
        format.html { redirect_to @person,
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

    category = source.heat.dance.solo_category
    solos = Solo.order(:order).joins(heat: :dance).where(dance: {solo_category_id: category&.id})

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

    Solo.order(:order).each do |solo|
      cat = solo.heat.dance.solo_category
      solos[cat] ||= []
      solos[cat] << solo
    end

    order = []
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

  def critiques
    index
    @judges = Person.where(type: 'Judge').all
    @event = Event.first
    render :critique, layout: false
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
