class EntriesController < ApplicationController
  before_action :set_entry, only: %i[ show edit update destroy ]
  include EntryForm
  include DanceLimitCalculator

  permit_site_owners :new, :edit, :create, :update, :destroy,
    trust_level: 50

  # GET /entries or /entries.json
  def index
    @track_ages = Event.current.track_ages

    where = {}

    @dance = params[:dance]
    @dance_name = nil
    unless @dance.blank?
      dance = Dance.find_by(id: params[:dance])
      if dance
        @dance_name = dance.name
        dance_ids = Dance.where(name: dance.name).pluck(:id)
        where[:dance_id] = dance_ids
      else
        where[:dance_id] = params[:dance]
      end
    end

    @age = params[:age]
    where[:age] = {id: params[:age]} unless @age.blank?

    @level = params[:level]
    where[:level] = {id: params[:level]} unless @level.blank?

    plus = nil

    @couple = params[:couple]
    if @couple == 'Pro-Am'
      where[:lead] = {type: 'Professional'}
      where[:follow] = {type: 'Student'}
      plus = Heat.where(where.merge(lead: {type: 'Student'}, follow: {type: 'Professional'}))
    elsif @couple == 'Amateur Couple'
      where[:lead] = {type: 'Student'}
      where[:follow] = {type: 'Student'}
    elsif @couple == 'Professional'
      where[:lead] = {type: 'Professional'}
      where[:follow] = {type: 'Professional'}
    end

    @ages = Age.order(:id).pluck(:description, :id)
    @levels = Level.order(:id).pluck(:name, :id)
    @couple_types = ['Pro-Am', 'Amateur Couple', 'Professional']

    selected = Heat.where(where)
    selected = selected.or(plus) if plus
    selected = selected.includes(entry: [:lead, :follow, :level, :age], dance: [])

    # Apply sorting based on the sort parameter
    case params[:sort]
    when 'lead'
      selected = selected.joins(entry: :lead).order('people.name')
    when 'follow'
      selected = selected.joins(entry: :follow).order('people.name')
    when 'dance'
      selected = selected.joins(:dance).order('dances.name')
    when 'level'
      selected = selected.joins(entry: :level).order('levels.id')
    when 'age'
      selected = selected.joins(entry: :age).order('ages.id')
    end

    @heats = selected.all
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
  end

  # GET /entries/1/edit
  def edit
    form_init(params[:primary], @entry)
    agenda_init

    partner = @entry.partner(@person)
    @partner = partner.id
    @age = @entry.age_id
    @level = @entry.level_id

    @next = params[:next]

    tally_entry

    event = Event.current
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

    if @entry.lead.type != 'Professional' or @entry.follow.type != 'Professional'
      @studios = [@person.studio, partner.studio, @entry.instructor&.studio].compact.uniq
      @studio = @studios.find {|studio| studio.name == @entry.invoice_studio}&.id if @studios.length > 1
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
        return render :edit, status: :unprocessable_content
      end
    end

    respond_to do |format|
      if @entry.save
        if Event.current.package_required
          @entry.lead.default_package!
          @entry.follow.default_package!
        end

        format.html { redirect_to @person, notice: "#{helpers.pluralize @total, 'heat'} successfully created." }
        format.json { render :show, status: :created, location: @entry }
      else
        new
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @entry.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /entries/1 or /entries/1.json
  def update
    entry = params[:entry]
    replace = find_or_create_entry(entry)

    # Store lead and follow for later use
    @person = Person.find(entry[:primary] || 0)
    partner = Person.find(entry[:partner] || 0)
    if @person.role == "Follower" || partner.role == 'Leader' || entry[:role] == 'Follower'
      lead = partner
      follow = @person
    else
      lead = @person
      follow = partner
    end

    event = Event.current
    if event.include_open && !event.include_closed
      params[:entry][:entries]['Closed'] ||= {}
      params[:entry][:entries]['Open'].each {|dance, count| params[:entry][:entries]['Closed'][dance] = 0}
    elsif !event.include_open && event.include_closed
      params[:entry][:entries]['Open'] ||= {}
      params[:entry][:entries]['Closed'].each {|dance, count| params[:entry][:entries]['Open'][dance] = 0}
    end

    params[:entry][:age_id] = 1 if !event.track_ages

    previous = @entry.heats.length

    begin
      Entry.transaction do
        update_heats(entry)

        if @entry.errors.any?
          raise ActiveRecord::Rollback
        end

        # Also validate the replacement entry if it's different
        if replace && replace != @entry && !replace.valid?
          # Copy validation errors from replace to @entry so they show in the form
          replace.errors.each do |error|
            @entry.errors.add(error.attribute, error.message)
          end
          raise ActiveRecord::Rollback
        end
      end
    rescue ActiveRecord::Rollback
      # Transaction rolled back, errors are preserved
    end

    if @entry.errors.any? || (replace && replace != @entry && !replace.valid?)
      # Need to set up the form variables without losing errors
      entries = @entries
      form_init(params[:entry][:primary], @entry)
      agenda_init

      partner = @entry.partner(@person)
      @partner = partner.id
      @age = @entry.age_id
      @level = @entry.level_id
      @next = params[:next]

      # Restore the entries that were tallied during update_heats
      @entries = entries

      return render :edit, status: :unprocessable_content
    end

    if not replace
      @entry.lead = lead
      @entry.follow = follow
      @entry.age_id = entry[:age] if entry[:age]
      @entry.level_id = entry[:level]
    elsif replace != @entry
      @total = 0
      @entry.reload
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
      operation = 'changed'
      if @total
        case @entry.heats.length - previous
        when @total
          operation = 'added'
        when -@total
          operation = 'removed'
        else
          operation = 'changed'
        end
      end

      if @entry.update(entry_params)
        format.html { redirect_to entry[:next] || @person, notice: "#{helpers.pluralize @total, 'heat'} #{operation}." }
        format.json { render :show, status: :ok, location: @entry }
      else
        edit
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @entry.errors, status: :unprocessable_content }
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
      @studio = @entry.subject.studio
    end

    # Only allow a list of trusted parameters through.
    def entry_params
      params.require(:entry).permit(:count, :dance_id, :lead_id, :follow_id, :studio_id)
    end

    def agenda_init
      event = Event.current

      dances = Dance.ordered.where(heat_length: nil)
      multis = Dance.ordered.where.not(heat_length: nil)

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
      clean = (Category.where(routines: true).count == 0) || event.agenda_based_entries
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
        reorder = nil
        Category.ordered.each do |cat|
          next if cat.pro ^ pro
          dances = []
          category = nil
          dance_ids.each do |id, name|
            dances = cat.send(id).ordered

            if dances.length > 0
              if dances.first.order < 0
                reorder ||= Dance.where(order: 0...).pluck(:name, :order).to_h
                dances = dances.sort_by {|dance| reorder[dance.name] || dance.order}
              end

              category = name
              break
            end
          end

          @agenda.push(title: cat.name, dances: dances, category: category)
        end
      else
        dances = dances.all.to_a.select {|dance| dance.order > 0} if event.agenda_based_entries and !clean

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
        [category, heats.group_by {|heat| heat.dance.id}]
      end.to_h)
    end

    def update_heats(entry, new: false)
      return unless entry[:entries]
      tally_entry

      dance_limit = Event.current.dance_limit
      dance_override = Dance.where.not(limit: nil).any?

      @total = 0
      %w(Closed Open Multi Solo).each do |category|
        next unless entry[:entries][category]
        Dance.all.each do |dance|
          heats = @entries[category][dance.id] || []
          was = new ? 0 : heats.count {|heat| heat.number >= 0}
          wants = entry[:entries][category][dance.id.to_s].to_i

          if wants != was
            # Check for dance limit violations using the new concern
            if dance_limit || dance_override
              additional_heats = wants - was

              # Check limit for both lead and follow if they are students
              violations = []

              if @entry.lead.type == 'Student' || dance_override
                violation = self.class.check_limit_violation(
                  @entry.lead_id, dance, category,
                  additional_heats: additional_heats,
                  exclude_entry_id: @entry.id
                )
                violations << violation if violation
              end

              if @entry.follow.type == 'Student' || dance_override
                violation = self.class.check_limit_violation(
                  @entry.follow_id, dance, category,
                  additional_heats: additional_heats,
                  exclude_entry_id: @entry.id
                )
                violations << violation if violation
              end

              if violations.any? && wants > was
                violation = violations.first
                limit_text = dance.semi_finals? ? "1 (scrutineering)" : violation[:limit].to_s
                category_text = violation[:category]
                @entry.errors.add(:base, :dance_limit_exceeded,
                  message: "#{dance.name} #{category_text} heats are limited to #{limit_text}.")
                @entries[category][dance.id] = [Heat.new(number: 9999)] * wants
                next
              elsif @entry.errors.any?
                # no additional error, but we need to update the entries to match the form
                @entries[category][dance.id] = [Heat.new(number: 9999)] * wants
                next
              end
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
