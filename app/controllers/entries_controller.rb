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
    @entry = Entry.new

    @person = Person.find(params[:primary])
    entries = @person.lead_entries + @person.follow_entries
    studios = [@person.studio] + @person.studio.pairs

    @dances = Dance.all.map(&:name)

    seeking = @person.role == 'Leader' ? 'Follower' : 'Leader'
    teacher = Person.where(type: 'Professional', studio: studios, 
      role: [seeking, 'Both']).order(:name)
    student = Person.where(type: 'Student', studio: @person.studio, 
      role: [seeking, 'Both']).order(:name)

    @avail = teacher + student
    surname = @person.name.split(',').first + ','
    spouse = @avail.find {|person| person.name.start_with? surname}
    @avail = ([spouse] + @avail).uniq if spouse

    @avail = @avail.map {|person| [person.display_name, person.name]}.to_h

    @ages = Age.all.order(:id).map {|age| [age.description, age.id]}
    @levels = Level.all.order(:id).map {|level| [level.name, level.id]}
  end

  # GET /entries/1/edit
  def edit
  end

  # POST /entries or /entries.json
  def create
    entry = params[:entry]

    @person = Person.find(entry[:primary])

    if @person.role = "Follower"
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

    total = 0
    %w(Closed Open).each do |category|
      Dance.all.each do |dance|
        count = entry[:entries][category][dance.name].to_i
        if count > 0
          total += count

          (count..1).each do |heat|
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

    respond_to do |format|
      if @entry.save
        format.html { redirect_to @person, notice: "#{total} heats successfully created." }
        format.json { render :show, status: :created, location: @entry }
      else
        @primary = @person
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @entry.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /entries/1 or /entries/1.json
  def update
    respond_to do |format|
      if @entry.update(entry_params)
        format.html { redirect_to entry_url(@entry), notice: "Entry was successfully updated." }
        format.json { render :show, status: :ok, location: @entry }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @entry.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /entries/1 or /entries/1.json
  def destroy
    @entry.destroy

    respond_to do |format|
      format.html { redirect_to entries_url, notice: "Entry was successfully destroyed." }
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
end
