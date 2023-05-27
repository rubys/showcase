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

    @renumber = Heat.distinct.where.not(number: 0).pluck(:number).
      map(&:abs).sort.uniq.zip(1..).any? {|n, i| n != i}
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

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: @type == 'judget' ? 'judge-heat-book' : "master-heat-book"
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
        
        # apply mapping
        Heat.transaction do
          heats.each do |heat|
            if mappings[heat.number]
              heat.number = mappings[heat.number]
              heat.save
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

          render turbo_stream: turbo_stream.replace("cat-#{ catname.downcase.gsub(' ', '-') }",
            render_to_string(partial: 'category', layout: false, locals: {cat: catname, heats: heats})
          )
        }

        format.html { redirect_to heats_url }
      end
    else
      redirect_to heats_url, notice: "#{count} heats renumbered."
    end
  end

  def drop
    source = Heat.find(params[:source])
    target = Heat.find(params[:target])

    source.number = target.number
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
