class EntriesController < ApplicationController
  before_action :set_entry, only: %i[ show edit update destroy ]

  # GET /entries or /entries.json
  def index
    @entries = Entry.all
  end

  # GET /entries/1 or /entries/1.json
  def show
  end

  # GET /entries/new
  def new
    @entry ||= Entry.new

    form_init

    @partner = nil
    @age = @person.age_id
    @level = @person.level_id
  end

  # GET /entries/1/edit
  def edit
    form_init

    if @person.role = "Follower"
      @partner = @entry.lead.name
    else
      @partner = @entry.follow.name
    end

    @age = @entry.age_id
    @level = @entry.level_id

    tally_entry
  end

  # POST /entries or /entries.json
  def create
    entry = params[:entry]

    @person = Person.find(entry[:primary])

    if @person.role == "Follower"
      lead = Person.find_by(name: entry[:partner])
      follow = @person
    else
      lead = @person
      follow = Person.find_by(name: entry[:partner])
    end

    @entry = Entry.find_or_create_by(
      lead: lead,
      follow: follow,
      age_id: entry[:age],
      level_id: entry[:level]
    )

    update_heats(entry, new: true)

    respond_to do |format|
      if @entry.save
        format.html { redirect_to @person, notice: "#{helpers.pluralize @total, 'heat'} successfully created." }
        format.json { render :show, status: :created, location: @entry }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @entry.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /entries/1 or /entries/1.json
  def update
    entry = params[:entry]

    @person = Person.find(entry[:primary])

    if @person.role == "Follower"
      lead = Person.find_by(name: entry[:partner])
      follow = @person
    else
      lead = @person
      follow = Person.find_by(name: entry[:partner])
    end

    previous = @entry.heats.length

    update_heats(entry)

    replace = Entry.find_by(
      lead: lead,
      follow: follow,
      age_id: entry[:age],
      level_id: entry[:level]
    )

    if not replace
      @entry.lead = lead
      @entry.follow = follow
      @entry.age_id = entry[:age]
      @entry.level_id = entry[:level]
    elsif replace != @entry
      @entry.reload
      @total = 0
      @entry.heats.to_a.each do |heat|
        if heat.category != 'Solo'
          heat.entry = replace
          heat.save!
          @total += 1
        end
      end
      @entry.reload
      @entry.destroy!
      @entry = replace
    end

    respond_to do |format|
      @entry.reload
      case @entry.heats.length - previous
      when @total
        operation = 'added'
      when -@total
        operation = 'removed'
      else
        operation = 'changed'
      end

      if @entry.update(entry_params)
        format.html { redirect_to @person, notice: "#{helpers.pluralize @total, 'heat'} #{operation}." }
        format.json { render :show, status: :ok, location: @entry }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @entry.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /entries/1 or /entries/1.json
  def destroy
    person = Person.find(params[:primary])
    heats = @entry.heats.length

    @entry.destroy

    respond_to do |format|
      format.html { redirect_to person_path(person), status: 303, notice: "#{helpers.pluralize heats, 'heat'} successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_entry
      @entry = Entry.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def entry_params
      params.require(:entry).permit(:count, :dance_id, :lead_id, :follow_id)
    end

    def form_init
      @person ||= Person.find(params[:primary])
      entries = @person.lead_entries + @person.follow_entries
      studios = [@person.studio] + @person.studio.pairs
  
      @dances = Dance.order(:order).all.map(&:name)
  
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

    def tally_entry
      @entries = {'Closed' => {}, 'Open' => {}}

      @entries.merge!(@entry.heats.
        select {|heat| heat.category != 'Solo'}.
        group_by {|heat| heat.category}.map do |category, heats|
        [category, heats.group_by {|heat| heat.dance.name}]
      end.to_h)
    end

    def update_heats(entry, new: false)
      tally_entry

      @total = 0
      %w(Closed Open).each do |category|
        Dance.all.each do |dance|
          was = new ? 0 : @entries[category][dance.name]&.length || 0
          wants = entry[:entries][category][dance.name].to_i
          if wants != was
            @total += (wants - was).abs
  
            (wants...was).each do |heat|
              @entries[category][dance.name][heat].destroy!
            end
  
            (was...wants).each do |heat|
              Heat.create({
                number: 0, 
                entry: @entry,
                category: category,
                dance: dance
              })
            end
          end
        end
      end
    end
end
