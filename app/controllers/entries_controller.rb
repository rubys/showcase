class EntriesController < ApplicationController
  before_action :set_entry, only: %i[ show edit update destroy ]
  include EntryForm

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

    form_init(params[:primary])
    agenda_init

    @partner = nil
    @age = @person.age_id
    @level = @person.level_id

    agenda_init
  end

  # GET /entries/1/edit
  def edit
    form_init(params[:primary], @entry)
    agenda_init
    
    @partner = @entry.partner(@person).id
    @age = @entry.age_id
    @level = @entry.level_id

    @next = params[:next]

    tally_entry

    event = Event.first
    if !event.include_open && event.include_closed
      @entries['Open'].each do |dance, heats|
        @entries['Closed'][dance] ||= []
        @entries['Closed'][dance] += heats
      end
    elsif event.include_open && !event.include_closed
      @entries['Closed'].each do |dance, heats|
        @entries['Open'][dance] ||= []
        @entries['Open'][dance] += heats
      end
    end

    unless @avail.values.include? @partner
      partner = @entry.partner(@person)
      @avail[partner.display_name] = @partner
      if partner.type == 'Professional'
        @instructors[partner.display_name] = @partner
      end
    end
  end

  # POST /entries or /entries.json
  def create
    entry = params[:entry]

    @entry = find_or_create_entry(entry)

    Entry.transaction do
      update_heats(entry, new: true)

      if @entry.errors.any?
        entries = @entries
        new
        @entries = entries
        return render :edit, status: :unprocessable_entity
      end
    end

    respond_to do |format|
      if @entry.save
        if Event.first.package_required
          @entry.lead.default_package!
          @entry.follow.default_package!
        end
        
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
    replace = find_or_create_entry(entry)

    event = Event.first
    if event.include_open && !event.include_closed
      params[:entry][:entries]['Closed'] ||= {}
      params[:entry][:entries]['Open'].each {|dance, count| params[:entry][:entries]['Closed'][dance] = 0}
    elsif !event.include_open && event.include_closed
      params[:entry][:entries]['Open'] ||= {}
      params[:entry][:entries]['Closed'].each {|dance, count| params[:entry][:entries]['Open'][dance] = 0}
    end

    params[:entry][:age_id] = 1 if !event.track_ages

    previous = @entry.heats.length

    Entry.transaction do
      update_heats(entry)

      if @entry.errors.any?
        entries = @entries
        edit
        @entries = entries
        return render :edit, status: :unprocessable_entity
      end
    end

    if not replace
      @entry.lead = lead
      @entry.follow = follow
      @entry.age_id = entry[:age] if entry[:age]
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
        format.html { redirect_to entry[:next] || @person, notice: "#{helpers.pluralize @total, 'heat'} #{operation}." }
        format.json { render :show, status: :ok, location: @entry }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @entry.errors, status: :unprocessable_entity }
      end
    end
  end

    # GET /entriese/couples or /entries.json
    def couples
      @entries = Entry.preload(:lead, :follow).joins(:lead, :follow).
        where(lead: {type: 'Student'}, follow: {type: 'Student'}).
        order('lead.name').all
    end

  # DELETE /entries/1 or /entries/1.json
  def destroy
    person = Person.find(params[:primary])

    heats = 0

    if @entry.heats.any? {|heat| heat.number < 0}
      @entry.heats.each do |heat|
        if heat.number < 0
          heat.update(number: -heat.number)
          heats += 1
        end
      end
      notice = "#{helpers.pluralize heats, 'heat'} restored."
    elsif @entry.heats.any? {|heat| heat.number > 0}
      @entry.heats.each do |heat|
        if heat.number > 0
          heat.update(number: -heat.number)
          heats += 1
        end
      end
      notice = "#{helpers.pluralize heats, 'heat'} scratched."
    else
      heats = @entry.heats.length
      @entry.destroy
      notice = "#{helpers.pluralize heats, 'heat'} successfully removed."
    end

    respond_to do |format|
      format.html { redirect_to person_path(person), status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  def reset_ages
    people_count = Person.where.not(age_id: 1).update(age_id: 1).count

    entry_count = Entry.where.not(age_id: 1).update(age_id: 1).count
    groups = Entry.all.group_by {|entry| [entry.level_id, entry.lead_id, entry.follow_id]}
    groups.each do |group, entries|
      next if entries.length < 2
      entries[1..].each do |entry|
        entry.heats.update_all(entry_id: entries[0].id)
        entry.destroy!
      end
    end

    redirect_to settings_event_index_path(tab: 'Advanced'),
      notice: "#{helpers.pluralize people_count, 'person'} and #{helpers.pluralize entry_count, 'entry'} updated."
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

    def agenda_init
      event = Event.first

      dances = Dance.order(:order).where(heat_length: nil)
      multis = Dance.order(:order).where.not(heat_length: nil)

      @include_open = event.include_open
      @include_closed = event.include_closed

      pro = @person&.type == 'Professional'

      # current restrictions: no category contains a mix of open/closed/solos/etc, and no
      # category is a "routines" category.
      if pro
        cat_ids = %i{pro_open_category_id pro_closed_category_id pro_solo_category_id pro_multi_category_id}
      else
        cat_ids = %i{open_category_id closed_category_id solo_category_id multi_category_id}
      end

      used = []
      clean = (Category.where(routines: true).count == 0)
      all = dances + multis
      cat_ids.each do |id|
        cats = all.map(&id).compact.uniq
        clean = false if cats.any? {|cat| used.include? cat}
        used += cats
      end
  
      if clean and (pro or event.agenda_based_entries)
        if pro
          dance_ids = {
            pro_open_dances: "Open",
            pro_closed_dances: "Closed",
            pro_solo_dances: "Solo",
            pro_multi_dances: "Multi"
          }
        else
          dance_ids = {
            open_dances: "Open",
            closed_dances: "Closed",
            solo_dances: "Solo",
            multi_dances: "Multi"
          }
        end

        @agenda = []
        Category.order(:order).each do |cat|
          next if cat.pro ^ pro
          dances = []
          category = nil
          dance_ids.each do |id, name|
            dances = cat.send(id).order(:order)
            if dances.length > 0
              category = name
              break
            end
          end

          @agenda.push(title: cat.name, dances: dances, category: category)
        end
      else
        @agenda = [
          {title: 'CLOSED CATEGORY', dances: dances, category: 'Closed'},
          {title: 'OPEN CATEGORY', dances: dances, category: 'Open'}
        ]
    
        unless multis.empty?
          @agenda.push({title: 'MULTI CATEGORY', dances: multis, category: 'Multi'})
        end
      end
    end

    def tally_entry
      @entries = {'Closed' => {}, 'Open' => {}, 'Multi' => {}, 'Solo' => {}}

      @entries.merge!(@entry.heats.
        group_by {|heat| heat.category}.map do |category, heats|
        [category, heats.group_by {|heat| heat.dance.name}]
      end.to_h)

    end

    def update_heats(entry, new: false)
      return unless entry[:entries]
      tally_entry

      dance_limit = Event.first.dance_limit

      if dance_limit
        entries = Entry.where(lead_id: 63).or(Entry.where(follow_id: 63)).pluck(:id)
        entries.delete @entry.id
        counts = Heat.where(entry_id: entries).group(:dance_id, :category).count
      end

      @total = 0
      %w(Closed Open Multi Solo).each do |category|
        Dance.all.each do |dance|
          next unless entry[:entries][category]
          heats = @entries[category][dance.name] || []
          was = new ? 0 : heats.count {|heat| heat.number >= 0}
          wants = entry[:entries][category][dance.name].to_i

          if wants != was
            if wants > was and dance_limit and (counts[[dance.id, category]] || 0) + wants > dance_limit
              @entry.errors.add(:base, :dance_limit_exceeded,
                message: "#{dance.name} #{category} heats are limited to #{dance_limit}.")
              @entries[category][dance.name] = [Heat.new(number: 9999)] * wants
              next
            end

            @total += (wants - was).abs
  
            (wants...was).each do |index|
              heat = heats[index]
              if heat.number == 0
                heat.destroy!
              elsif heat.number > 0
                heat.update(number: -heat.number)
              end
            end
  
            (was...wants).each do
              heat = heats.find {|heat| heat.number < 0}
              if heat
                heat.update(number: -heat.number)
              else
                @heat = Heat.create({
                  number: 0, 
                  entry: @entry,
                  category: category,
                  dance: dance
                })

                if category == 'Solo'
                  solo = Solo.new()
                  solo.heat = @heat
                  solo.order = (Solo.maximum(:order) || 0) + 1
                  solo.save!
                end
              end
            end
          end
        end
      end
    end
end
