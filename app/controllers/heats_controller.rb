class HeatsController < ApplicationController
  include HeatScheduler
  include EntryForm
  include Printable
  
  skip_before_action :authenticate_user, only: %i[ mobile ]
  before_action :set_heat, only: %i[ show edit update destroy ]

  # GET /heats or /heats.json
  def index
    generate_agenda

    @solos = Solo.includes(:heat).order('heats.number').
      map {|solo| solo.heat.number}

    @stats = @heats.group_by {|number, heats| heats.length}.
      map {|size, entries| [size, entries.map(&:first)]}.
      sort

    event = Event.last
    @backnums = event.backnums
    @ballrooms = event.ballrooms
    @track_ages = event.track_ages
    @column_order = event.column_order
    @locked = event.locked?

    if @backnums
      if Entry.includes(:heats).where.not(heats: {category: 'Solo'}).empty?
        if Person.where.not(back: nil).empty?
          @backnums = false
        end
      end
    end

    @renumber = Heat.distinct.where.not(number: 0).pluck(:number).
      map(&:abs).sort.uniq.zip(1..).any? {|n, i| n != i}

    @issues = @heats.map {|number, heats|
      [number, heats.map {|heat| 
        e=heat.entry
        heat.number > 0 ? [e.lead_id, e.follow_id] : []
      }.flatten.tally.select {|person, count| number > 0 && count > 1}
      ]
    }.select {|number, issues| !issues.empty?}
  end

  def mobile
    index
    @event = Event.last
    @layout = 'mx-0'
    @nologo = true
    @search = params[:q] || params[:search]
  end

  def djlist
    @heats = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance)

    @agenda = @heats.group_by(&:dance_category).map do |category, heats|
      [heats.map {|heat| heat.number}.min, category&.name]
    end.to_h

    @layout = ''
    @nologo = true
    @font_size = Event.first.font_size

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: "djlist"
      end
    end
  end

  # GET /heats/book or /heats/book.json
  def book
    @type = params[:type]
    @event = Event.last
    @ballrooms = Event.last.ballrooms
    index
    @font_size = @event.font_size

    @assignments = {}
    if @event.assign_judges and @type == 'judge'
      @assignments = Score.joins(:judge).pluck(:heat_id, :name).to_h
    end

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: @type == 'judge' ? 'judge-heat-book' : "master-heat-book"
      end
    end
  end

  # GET /heats/1 or /heats/1.json
  def show
  end

  # GET /heats/knobs
  def knobs
    @categories = Person.distinct.pluck(:category).compact.length
    @levels = Person.distinct.pluck(:level).compact.length
  end

  # POST /heats/redo
  def redo
    schedule_heats
    redirect_to heats_url, notice: "#{Heat.maximum(:number).to_i} heats generated."
  end

  def renumber
    source = nil

    if params['before']
      before = params['before'].to_f
      after = params['after'].to_f
      heats = Heat.where(number: before)
      source = heats.first

      if before > 0 && after > 0
        # get a list of all affected heats, including scratches         
        heats = Heat.where(number: [
          Range.new(*[before, after].sort),
          Range.new(*[-before , -after].sort)
        ])

        # find unique heat numbers 
        numbers = heats.map(&:number).map(&:abs).sort.uniq

        solos = {}

        if numbers.include? after
          # heat number in use: rotate
          mappings = before < after ?
            numbers.zip(numbers.rotate(-1)) :
            numbers.zip(numbers.rotate)
        else
          # heat number not in use: take it
          mappings = [[before == before.to_i ? before.to_i : before, after]]
        end

        # convert to hash, including scratches
        mappings += mappings.map {|a, b| [-a, -b]}
        mappings = mappings.to_h

        # determine solo order numbers
        solos = {}
        heats.each do |heat|
          order = heat.solo&.order
          if order && mappings[heat.number]
            solos[heat.number] = order
          end
        end

        # only reorder solos if ALL solos that are to be moved have mappings
        unless heats.all? {|heat| not heat.solo or mappings[heat.number] == nil or solos[heat.number]}
          solos = {}
        end
        
        # apply mapping
        Heat.transaction do
          heats.each do |heat|
            if mappings[heat.number]
              heat.number = mappings[heat.number]
              heat.save(validate: false)

              if heat.solo && solos[heat.number]
                heat.solo.order = solos[heat.number]
                heat.solo.save(validate: false)
              else
                heat.save
              end
            end
          end
        end
      end
    
    else

      newnumbers = Heat.distinct.where(number: 0.1..).order(:number).pluck(:number).zip(1..).to_h
      count = newnumbers.select {|n, i| n != i}.length

      Heat.transaction do
        Heat.all.each do |heat|
          if heat.number != newnumbers[heat.number.to_f]
            heat.number = newnumbers[heat.number.to_f]
            heat.save
          end
        end
      end
    end

    if source
      respond_to do |format|
        format.turbo_stream {
          cat = source.dance_category
          generate_agenda
          catname = cat&.name || 'Uncategorized'
          heats = @agenda[catname]
          @locked = Event.last.locked?
          @renumber = Heat.distinct.where.not(number: 0).pluck(:number).
            map(&:abs).sort.uniq.zip(1..).any? {|n, i| n != i}

          render turbo_stream: [
            turbo_stream.replace("cat-#{ catname.downcase.gsub(' ', '-') }",
              render_to_string(partial: 'category', layout: false, locals: {cat: catname, heats: heats})
            ),
            turbo_stream.replace("renumber",
              render_to_string(partial: 'renumber')
            ),
          ]
        }

        format.html { redirect_to heats_url }
      end
    else
      redirect_to heats_url, notice: "#{count} heats renumbered."
    end
  end

  def drop
    if params[:source].start_with? '-'
      params[:before] = params[:source][1..]

      if params[:target].start_with? '-'
        params[:after] = params[:target][1..]
      else
        params[:after] = Heat.find(params[:target]).number
      end

      return renumber
    end

    source = Heat.find(params[:source])

    if params[:target].start_with? '-'
      source.number = params[:target][1..].to_f
    else
      source.number = Heat.find(params[:target]).number
    end

    source.save!

    respond_to do |format|
      format.turbo_stream {
        cat = source.dance_category
        generate_agenda
        heats = @agenda[cat.name]
        @locked = Event.last.locked?

        render turbo_stream: turbo_stream.replace("cat-#{ cat.name.downcase.gsub(' ', '-') }",
          render_to_string(partial: 'category', layout: false, locals: {cat: cat.name, heats: heats})
        )
      }

      format.html { redirect_to heats_url }
    end
  end

  # GET /heats/new
  def new
    @heat ||= Heat.new
    form_init(params[:primary])
    @dances = Dance.order(:name).pluck(:name, :id).to_h
  end

  # GET /heats/1/edit
  def edit
    form_init(params[:primary], @heat.entry)

    @dances = Dance.order(:name).pluck(:name, :id).to_h
    
    @partner = @heat.entry.partner(@person).id
    @age = @heat.entry.age_id
    @level = @heat.entry.level_id
    @instructor = @heat.entry.instructor_id
    @ballroom = Event.exists?(ballrooms: 2..) || Category.exists?(ballrooms: 2..)
    @locked = Event.last.locked
  end

  # POST /heats or /heats.json
  def create
    @heat = Heat.new(heat_params)
    @heat.entry = find_or_create_entry(params[:heat])
    @heat.number ||= 0

    respond_to do |format|
      if @heat.save
        format.html { redirect_to heat_url(@heat), notice: "Heat was successfully created." }
        format.json { render :show, status: :created, location: @heat }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @heat.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /heats/1 or /heats/1.json
  def update
    entry = @heat.entry
    params[:heat][:ballroom] = nil if params[:heat][:ballroom] == ''
    replace = find_or_create_entry(params[:heat])

    @heat.entry = replace
    @heat.number = 0

    respond_to do |format|
      if @heat.update(heat_params)
        format.html { redirect_to params['return-to'] || person_path(@person),
          notice: "Heat was successfully updated." }
        format.json { render :show, status: :ok, location: @heat }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @heat.errors, status: :unprocessable_entity }
      end
    end

    if replace != entry
      entry.reload
      entry.destroy if entry.heats.empty?
    end
  end

  # DELETE /heats/1 or /heats/1.json
  def destroy
    if @heat.number != 0
      notice = "Heat was successfully #{@heat.number < 0 ? 'restored' : 'scratched'}."
      @heat.update(number: -@heat.number)
    elsif @heat.entry.heats.length == 1
      @heat.entry.destroy
      notice = "Heat was successfully removed."
    else
      @heat.destroy
      notice = "Heat was successfully removed."
    end
    
    respond_to do |format|
      format.html { redirect_to params[:primary] ? person_url(params[:primary]) : heats_url, 
        status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  # attempt to schedule unscheduled heats when locked
  def schedule_unscheduled
    event = Event.first
    unscheduled = Heat.joins(:entry).where(number: 0)

    scheduled = {true => 0, false => 0}

    unscheduled.each do |heat|
      level = heat.entry.level_id

      avail = Heat.joins(:entry).where(dance_id: heat.dance_id, category: heat.category).group('number').
        pluck('number, AVG(entries.level_id) as avg_level, COUNT(heats.id) as count').
        sort_by {|number, level, count| (level - heat.entry.level_id).abs}

      avail.each do |number, level, count|
        on_floor = Entry.joins(:heats).where(heats: {number: number}).pluck(:lead_id, :follow_id).flatten
        next if on_floor.include?(heat.entry.lead_id) || on_floor.include?(heat.entry.follow_id)

        category = heat.dance_category
        next if count >= (category&.max_heat_size || event.max_heat_size || 9999)

        ballrooms = category&.ballrooms || event.ballrooms
        if ballrooms == 2
          if heats.entry.lead.type == 'Student'
            heat.ballroom = 'B'
          else
            heat.ballroom = 'B'
          end
        end

        heat.number = number
        heat.save!
        break
      end

      scheduled[heat.number != 0.0] += 1
    end

    if scheduled[false] == 0
      notice = "#{scheduled[true]} heats scheduled"
    elsif scheduled[true] == 0
      notice = "no heats scheduled"
    else
      notice = "#{scheduled[true]} heats scheduled; #{scheduled[false]} heats not scheduled"
    end

    redirect_to heats_url, notice: notice
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_heat
      @heat = Heat.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def heat_params
      params.require(:heat).permit(:number, :category, :dance_id, :ballroom)
    end
end
