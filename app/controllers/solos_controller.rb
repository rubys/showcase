class SolosController < ApplicationController
  before_action :set_solo, only: %i[ show edit update destroy ]

  # GET /solos or /solos.json
  def index
    @solos = {}

    Solo.order(:order).each do |solo|
      cat = solo.heat.dance.closed_category
      @solos[cat] ||= []
      @solos[cat] << solo.heat
    end

    sort_order = Category.pluck(:name, :order).to_h

    @solos = @solos.sort_by {|cat, heats| sort_order[cat.name]}
  end

  # GET /solos/1 or /solos/1.json
  def show
  end

  # GET /solos/new
  def new
    @solo = Solo.new

    form_init

    @partner = nil
    @age = @person.age_id
    @level = @person.level_id
  end

  # GET /solos/1/edit
  def edit
    form_init

    @age = @solo.heat.entry.age_id
    @level = @solo.heat.entry.level_id
    @dance = @solo.heat.dance.id
  end

  # POST /solos or /solos.json
  def create
    solo = params[:solo]

    @person = Person.find(solo[:primary])

    if @person.role == "Follower"
      lead = Person.find_by(name: solo[:partner])
      follow = @person
    else
      lead = @person
      follow = Person.find_by(name: solo[:partner])
    end

    dance = Dance.find(solo[:dance_id].to_i)

    @entry = Entry.find_or_create_by!(
      lead: lead,
      follow: follow,
      age_id: solo[:age],
      level_id: solo[:level]
    )

    @heat = Heat.create!({
      number: 0, 
      entry: @entry,
      category: "Solo",
      dance: dance
    })

    @solo = Solo.new(solo_params)
    @solo.heat = @heat

    if solo[:combo_dance_id] != ''
      @solo.combo_dance = Dance.find(solo[:combo_dance_id].to_i)
    end

    @solo.order = (Solo.maximum(:order) || 0) + 1

    respond_to do |format|
      if @solo.save
        format.html { redirect_to @person, notice: "Solo was successfully created." }
        format.json { render :show, status: :created, location: @solo }
      else
        @primary = @person
        form_init
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @solo.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /solos/1 or /solos/1.json
  def update
    solo = params[:solo]

    @person = Person.find(solo[:primary])

    if @person.role == "Follower"
      lead = Person.find_by(name: solo[:partner])
      follow = @person
    else
      lead = @person
      follow = Person.find_by(name: solo[:partner])
    end

    entry = @solo.heat.entry
    replace = Entry.find_or_create_by!(
      lead: lead,
      follow: follow,
      age_id: solo[:age],
      level_id: solo[:level]
    )

    if replace != entry
      @solo.heat.entry = replace
    end

    @solo.heat.dance = Dance.find(solo[:dance_id])
    @solo.heat.save!

    if solo[:combo_dance_id].empty?
      @solo.combo_dance = nil
    else
      @solo.combo_dance = Dance.find(solo[:combo_dance_id].to_i)
    end

    respond_to do |format|
      if @solo.update(solo_params)
        format.html { redirect_to @person, notice: "Solo was successfully updated." }
        format.json { render :show, status: :ok, location: @solo }
      else
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

    category = source.heat.dance.closed_category
    solos = Solo.order(:order).joins(heat: :dance).where(dance: {closed_category_id: category.id})

    if source.order > target.order
      slice = solos.where(order: target.order..source.order)
      new_order = slice.map(&:order).rotate(1)
    else
      slice = solos.where(order: source.order..target.order)
      new_order = slice.map(&:order).rotate(-1)
    end

    Solo.transaction do
      slice.zip(new_order).each do |solo, order|
        solo.order = order
        solo.save! validate: false
      end

      raise ActiveRecord::Rollback unless solos.all? {|solo| solo.valid?}
    end

    respond_to do |format|
      format.turbo_stream { 
        id = helpers.dom_id category
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
    @solo.heat.destroy
    entry.reload
    entry.destroy! if entry.heats.empty?

    respond_to do |format|
      format.html { redirect_to person_path(person), status: 303, notice: "Solo was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_solo
      @solo = Solo.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def solo_params
      params.require(:solo).permit(:heat_id, :combo_dance_id, :order, :song, :artist)
    end

    def form_init
      @person ||= Person.find(params[:primary])
      entries = @person.lead_entries + @person.follow_entries
      studios = [@person.studio] + @person.studio.pairs
  
      @dances = Dance.order(:name).all.map {|dance| [dance.name, dance.id]}
  
      seeking = @person.role == 'Leader' ? 'Follower' : 'Leader'
      teacher = Person.where(type: 'Professional', studio: studios, 
        role: [seeking, 'Both']).order(:name)
      student = Person.where(type: 'Student', studio: @person.studio, 
        role: [seeking, 'Both']).order(:name) +
        Person.where(type: 'Student', studio: @person.studio.pairs,
        role: [seeking, 'Both']).order(:name)
  
      @avail = teacher + student
      surname = @person.name.split(',').first + ','
      spouse = @avail.find {|person| person.name.start_with? surname}
      @avail = ([spouse] + @avail).uniq if spouse
  
      @avail = @avail.map {|person| [person.display_name, person.name]}.to_h
  
      @ages = Age.all.order(:id).map {|age| [age.description, age.id]}
      @levels = Level.all.order(:id).map {|level| [level.name, level.id]}

      @entries = {'Closed' => {}, 'Open' => {}}
    end
end
