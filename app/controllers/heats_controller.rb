class HeatsController < ApplicationController
  include HeatScheduler
  include EntryForm
  include Printable
  include Retriable

  skip_before_action :authenticate_user, only: %i[ mobile ]
  before_action :set_heat, only: %i[ show edit update destroy ]

  permit_site_owners :show, trust_level: 25
  permit_site_owners :edit, :update, :destroy, trust_level: 50

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
    @combine_open_and_closed = event.heat_range_cat == 1

    if @backnums
      if Entry.includes(:heats).where.not(heats: {category: 'Solo'}).empty?
        if Person.where.not(back: nil).empty?
          @backnums = false
        end
      end
    end

    @undoable = !@locked && undoable
    @renumber = !@locked && renumber_needed

    # detect if categories were reordered
    first_heats = @agenda.map {|category| category.last.first}.compact.map(&:first)
    @renumber ||= (first_heats != first_heats.sort)

    @issues = @heats.map {|number, heats|
      [number, heats.map {|heat|
        e=heat.entry
        heat.number > 0 && e.lead_id != 0 ? [e.lead_id, e.follow_id] : []
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

    @combine_open_and_closed = Event.last.heat_range_cat == 1

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
    @font_family = @event.font_family
    @font_size = @event.font_size

    @assignments = {}
    if @event.assign_judges and @type == 'judge'
      @assignments = Score.joins(:judge).pluck(:heat_id, :name).
        map {|heat, judge| [heat, Person.display_name(judge)]}.to_h

      if params[:judge]
        @judge = Person.find(params[:judge])
      end
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
    notice = "#{Heat.maximum(:number).to_i} heats generated."

    unless Heat.where(number: 0.0).empty?
      locked = Category.where(locked: true).count
      notice += " #{locked} categories locked." if locked > 0
    end

    redirect_to heats_url, notice: notice
  end

  # POST /heats/undo
  def undo
    count = Heat.where('prev_number != number').update_all 'number = prev_number'
    notice = "#{helpers.pluralize count, 'heat'} undone."
    redirect_to heats_url, notice: notice
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

      generate_agenda
      newnumbers = @agenda.map {|category, heats| heats.map {|heat| heat.first.to_f}}.
        flatten.select {|number| number > 0}.zip(1..).to_h
      count = newnumbers.select {|n, i| n.to_f != i.to_f}.length

      Heat.transaction do
        Heat.all.each do |heat|
          number = heat.number.to_f.abs
          if heat.number != newnumbers[number]
            if heat.number >= 0
              heat.number = newnumbers[number] || 0
            else
              heat.number = -newnumbers[number] || 0
            end

            if heat.number == 0
              heat.destroy
            else
              heat.save
            end
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
          @renumber = !@locked && renumber_needed
          @undoable = !@locked && undoable

          render turbo_stream: [
            turbo_stream.replace("cat-#{ catname.downcase.gsub(/[^\w]+/, '-') }",
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

        @renumber = !@locked && renumber_needed
        @undoable = !@locked && undoable

        render turbo_stream: [
          turbo_stream.replace("cat-#{ cat.name.downcase.gsub(/[^\w]+/, '-') }",
            render_to_string(partial: 'category', layout: false, locals: {cat: cat.name, heats: heats})
          ),
          turbo_stream.replace("renumber",
            render_to_string(partial: 'renumber')
          )
        ]
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

    @partner = @heat.entry.partner(@person).id
    @age = @heat.entry.age_id
    @level = @heat.entry.level_id
    @instructor = @heat.entry.instructor_id
    @ballroom = Event.exists?(ballrooms: 2..) || Category.exists?(ballrooms: 2..)
    @locked = Event.last.locked

    if Event.first.agenda_based_entries?
      dances = Dance.where(order: 0...).order(:name)

      if !dances.include?(@heat.dance) || !@heat.dance.freestyle_category
        @categories = dance_categories(@heat.dance, false)
        @category = @heat.dance.id
        @heat.dance_id = dances.find {|dance| dance.name == @heat.dance.name}&.id || @heat.dance_id
      end

      @dances = dances.map {|dance| [dance.name, dance.id]}
    else
      @dances = Dance.order(:name).all.pluck(:name, :id)
    end

    unless @avail.values.include? @partner
      partner = @heat.entry.partner(@person)
      @avail[partner.display_name] = @partner
      if partner.type == 'Professional'
        @instructors[partner.display_name] = @partner
      end
    end
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

    if Event.first.agenda_based_entries? and params[:heat][:number].to_i != 0
      heat = Heat.find_by(number: params[:heat][:number].to_i)
      category = heat&.dance_category
      if category&.routines == true
        dance = Dance.find(params[:heat][:dance_id])
        dance = Dance.where(name: dance.name).find {|dance| dance.freestyle_category == category}
        params[:heat][:dance_id] = dance.id
      end
    end

    if @heat.dance_id != params[:heat][:dance_id].to_i or @heat.category != params[:heat][:category]
      params[:heat].delete(:number)
      dance_limit = Event.last.dance_limit
      if dance_limit
        @heat.dance_id = params[:heat][:dance_id].to_i
        @heat.category = params[:heat][:category]
        count = 0

        entry = @heat.entry
        if entry.follow.type == 'Student'
          entries = Entry.where(lead_id: entry.follow_id).or(Entry.where(follow_id: entry.follow_id)).pluck(:id)
          count = Heat.where(entry_id: entries, dance_id: @heat.dance_id, category: @heat.category).count
        end

        if entry.lead.type == 'Student'
          entries = Entry.where(lead_id: entry.lead_id).or(Entry.where(follow_id: entry.lead_id)).pluck(:id)
          count = [count, Heat.where(entry_id: entries, dance_id: @heat.dance_id, category: @heat.category).count].max
        end

        if count >= dance_limit
          @heat.errors.add(:dance_id, "limit of #{dance_limit} reached for this category.")
        end
      end
    end

    respond_to do |format|
      if not @heat.errors.any? and @heat.update(heat_params)
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

    assign_unassigned_to_judges
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
          if heat.entry.lead.type == 'Student'
            heat.ballroom = 'B'
          else
            heat.ballroom = 'A'
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

    assign_unassigned_to_judges

    redirect_to heats_url, notice: notice
  end

  def reset_open
    count = Heat.where(category: 'Closed').update_all(category: 'Open')

    redirect_to settings_event_index_path(tab: 'Advanced'),
      notice: "#{helpers.pluralize(count, 'heat')} reset to open."
  end

  def reset_closed
    count = Heat.where(category: 'Open').update_all(category: 'Closed')

    redirect_to settings_event_index_path(tab: 'Advanced'),
      notice: "#{helpers.pluralize(count, 'heat')} reset to closed."
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_heat
      @heat = Heat.find(params[:id])

      @studio = @heat&.subject&.studio
    end

    # Only allow a list of trusted parameters through.
    def heat_params
      params.require(:heat).permit(:number, :category, :dance_id, :ballroom)
    end

    # Find heats that are not assigned to a judge, and assign them
    def assign_unassigned_to_judges
      return unless Event.last.assign_judges?
      return unless Score.where(value: nil, good: nil, bad: nil, comments: nil).any?

      # find heats that have not been assigned to a judge
      scored = Score.joins(:heat).distinct.where.not(heats: {number: ...0}).pluck(:number)
      heats = Heat.where.not(number: scored).where.not(number: ...0).
        where.not(id: Score.distinct.pluck(:heat_id)).
        where.not(category: "Solo").all

      return if heats.empty?

      # exclude judges that are not present
      exclude = Judge.where(present: false).pluck(:person_id)
      include = Person.where(type: 'Judge').where.not(id: exclude).all.shuffle.map {|judge| [judge.id, 0]}.to_h
      return if include.empty?

      retry_transaction do
        heats.each do |heat|
          # select judge with fewest couples in this heat
          judge_id = include.merge(Score.includes(:heat).where(judge_id: include).
            where(heat: {number: heat.number.to_f}).group(:judge_id).count).
            invert.sort.first.last

          next unless judge_id
          Score.create! heat_id: heat.id, judge_id: judge_id
        end
      end
    end
end
