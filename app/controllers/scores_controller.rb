class ScoresController < ApplicationController
  include Printable
  include Retriable
  before_action :set_score, only: %i[ show edit update destroy ]

  # Skip CSRF for batch upload - offline sync scenario means CSRF token may be stale
  # Security: Still protected by HTTP Basic Auth, judge-specific URL prevents cross-judge attacks
  skip_before_action :verify_authenticity_token, only: [:batch_scores]

  include ActiveStorage::SetCurrent

  SCORES = {
    "Open" => %w(1 2 3 F),
    "Closed" => %w(B S G GH).reverse,
    "Solo" => %w(B S G GH).reverse,
    "Multi" => %w(1 2 3 F)
  }

  WEIGHTS = [5, 3, 2, 1]

  # GET /scores/callbacks
  def callbacks
    setup_score_view_params
    
    # Get scrutineering dances only
    dances = Dance.where(semi_finals: true).includes(:heats).ordered
    @scores = {}
    
    dances.each do |dance|
      process_dance_for_callbacks(dance)
    end
    
    handle_post_request('callbacks')
  end

  # GET /scores or /scores.json
  def heatlist
    event = Event.current
    @judge = Person.find(params[:judge].to_i)
    @style = params[:style]
    @sort = @judge.sort_order
    @show = @judge.show_assignments
    @assign_judges = event.assign_judges? && params[:style] != 'emcee' && Person.where(type: 'Judge').count > 1

    @heats = Heat.all.where(number: 1..).order(:number).group(:number).includes(
      dance: [:open_category, :closed_category, :multi_category, {solo_category: :extensions}],
      entry: %i[lead follow],
      solo: %i[category_override]
    ).to_a.sort_by(&:number)
    @combine_open_and_closed = Event.current.heat_range_cat == 1

    # Build agenda hash for category headers - show category at first occurrence
    @agenda = {}
    last_category = nil
    @heats.each do |heat|
      category = heat.dance_category
      if category != last_category
        cat_name = category&.name || 'Uncategorized'
        @agenda[heat.number] = cat_name
        last_category = category
      end
    end

    @scored = Score.includes(:heat).where(judge: @judge).
      select {|score| score.value || score.comments || score.good || score.bad}.
      group_by {|score| score.heat.number.to_f}
    @count = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance).count

    if @assign_judges and Score.where(judge: @judge).any?
      @missed = Score.includes(:heat).where(judge: @judge, good: nil, bad: nil, value: nil).distinct.pluck(:number)
      @missed += Solo.includes(:heat).pluck(:number).select {|number| !@scored[number]}
    else
      @missed = Heat.distinct.pluck(:number).select do |number|
        number = number.to_i == number ? number.to_i : number
        !@scored[number] || @scored[number].length != @count[number.to_f]
      end
    end

    @show_solos = @judge&.judge&.review_solos&.downcase

    @browser_warn = browser_warn

    @unassigned = @assign_judges ? Heat.includes(:scores).where(category: ['Open', 'Closed'], scores: { id: nil }).distinct.pluck(:number).select {it > 0} : []

    render :heatlist, status: (@browser_warn ? :upgrade_required : :ok)
  end

  # GET /scores/:judge/spa - SPA test page
  def spa
    @judge = Person.find(params[:judge].to_i)
    @heat_number = params[:heat]&.to_i  # nil if not provided - shows heatlist
    @style = params[:style] || 'radio'
    render layout: false
  end

  # GET /scores/:judge/heats.json - Returns all heats data for SPA rendering
  def heats_json
    event = Event.current
    judge = Person.find(params[:judge].to_i)

    # Load all heats with necessary associations
    heats = Heat.where(number: 1..).order(:number).includes(
      dance: [:open_category, :closed_category, :multi_category, :solo_category, :multi_children, :multi_dances, :songs],
      entry: [:age, :level, :lead, :follow, :instructor, :studio],
      solo: [:formations, :category_override],
      scores: []
    ).to_a

    # Build the response data structure
    data = {
      event: {
        id: event.id,
        name: event.name,
        open_scoring: event.open_scoring,
        closed_scoring: event.closed_scoring,
        multi_scoring: event.multi_scoring,
        solo_scoring: event.solo_scoring,
        heat_range_cat: event.heat_range_cat,
        assign_judges: event.assign_judges,
        backnums: event.backnums,
        track_ages: event.track_ages,
        ballrooms: event.ballrooms,
        column_order: event.column_order,
        judge_comments: event.judge_comments,
        pro_am: event.pro_am
      },
      judge: {
        id: judge.id,
        name: judge.name,
        display_name: judge.display_name,
        sort_order: judge.sort_order || 'back',
        show_assignments: judge.show_assignments || 'first',
        review_solos: judge&.judge&.review_solos&.downcase
      },
      heats: heats.group_by(&:number).map do |number, heat_group|
        first_heat = heat_group.first
        category = first_heat.category
        dance = first_heat.dance

        # Determine scoring type
        scoring = if category == 'Solo'
          event.solo_scoring
        elsif category == 'Multi'
          event.multi_scoring
        elsif category == 'Open' || (category == 'Closed' && event.closed_scoring == '=') || event.heat_range_cat > 0
          event.open_scoring
        else
          event.closed_scoring
        end

        # Build subjects list
        subjects = heat_group.map do |heat|
          entry = heat.entry
          {
            id: heat.id,
            dance_id: heat.dance_id,
            entry_id: heat.entry_id,
            pro: entry.pro,
            lead: {
              id: entry.lead.id,
              name: entry.lead.name,
              display_name: entry.lead.display_name,
              back: entry.lead.back,
              type: entry.lead.type,
              studio: entry.lead.studio ? {
                id: entry.lead.studio.id,
                name: entry.lead.studio.name
              } : nil
            },
            follow: {
              id: entry.follow.id,
              name: entry.follow.name,
              display_name: entry.follow.display_name,
              back: entry.follow.back,
              type: entry.follow.type,
              studio: entry.follow.studio ? {
                id: entry.follow.studio.id,
                name: entry.follow.studio.name
              } : nil
            },
            instructor: entry.instructor ? {
              id: entry.instructor.id,
              name: entry.instructor.name
            } : nil,
            studio: entry.invoice_studio,  # Use calculated invoice studio for display
            age: entry.age ? {
              id: entry.age.id,
              category: entry.age.category
            } : nil,
            level: entry.level ? {
              id: entry.level.id,
              name: entry.level.name,
              initials: entry.level.initials
            } : nil,
            solo: heat.solo ? {
              id: heat.solo.id,
              order: heat.solo.order,
              formations: heat.solo.formations.map do |formation|
                {
                  id: formation.id,
                  person_id: formation.person_id,
                  person_name: formation.person.display_name,
                  on_floor: formation.on_floor
                }
              end
            } : nil,
            scores: heat.scores.select { |s| s.judge_id == judge.id }.map do |score|
              {
                id: score.id,
                judge_id: score.judge_id,
                heat_id: score.heat_id,
                slot: score.slot,
                good: score.good,
                bad: score.bad,
                value: score.value,
                comments: score.comments
              }
            end
          }
        end

        {
          number: number,
          category: category,
          scoring: scoring,
          updated_at: heat_group.map(&:updated_at).compact.max&.iso8601(3),
          dance: {
            id: dance.id,
            name: dance.name,
            heat_length: dance.heat_length,
            uses_scrutineering: dance.uses_scrutineering?,
            multi_children: dance.multi_children.map { |c| { id: c.dance.id, name: c.dance.name } },
            multi_parent: dance.multi_dances.first&.parent ? {
              id: dance.multi_dances.first.parent.id,
              name: dance.multi_dances.first.parent.name,
              heat_length: dance.multi_dances.first.parent.heat_length
            } : nil,
            category_name: first_heat.dance_category&.name,
            ballrooms: first_heat.dance_category&.ballrooms || event.ballrooms,
            songs: dance.songs.map { |s| { id: s.id, title: s.title } }
          },
          subjects: subjects
        }
      end,
      feedbacks: Feedback.all.map { |f| { id: f.id, value: f.value, abbr: f.abbr } },
      score_options: {
        "Open" => get_scores_for_type(event.open_scoring).tap { |s| s << '' unless s.empty? },
        "Closed" => get_scores_for_type(event.closed_scoring == '=' ? event.open_scoring : event.closed_scoring).tap { |s| s << '' unless s.empty? },
        "Solo" => get_scores_for_type(event.solo_scoring).tap { |s| s << '' unless s.empty? },
        "Multi" => get_scores_for_type(event.multi_scoring).tap { |s| s << '' unless s.empty? }
      },
      qr_code: {
        url: judge_spa_url(judge),
        svg: RQRCode::QRCode.new(judge_spa_url(judge)).as_svg(viewbox: true)
      },
      assign_judges: event.assign_judges > 0,
      timestamp: Time.current.to_i
    }

    render json: data
  end

  # GET /scores/:judge/version/:heat - Lightweight version check for sync strategy
  def version_check
    heat_number = params[:heat].to_f

    # Get max updated_at from heats table
    max_updated_at = Heat.where('number >= ?', 1).maximum(:updated_at)

    # Get total heat count
    heat_count = Heat.where('number >= ?', 1).distinct.count(:number)

    render json: {
      heat_number: heat_number,
      max_updated_at: max_updated_at&.iso8601(3),
      heat_count: heat_count
    }
  end

  # POST /scores/:judge/batch - Batch score upload for offline sync
  def batch_scores
    judge = Person.find(params[:judge].to_i)
    scores_data = params[:scores] || []

    succeeded = []
    failed = []

    ActiveRecord::Base.transaction do
      scores_data.each do |score_params|
        begin
          heat = Heat.find(score_params[:heat])
          slot = score_params[:slot]&.to_i

          # Find or create score
          score = Score.find_or_create_by(
            judge_id: judge.id,
            heat_id: heat.id,
            slot: slot
          )

          # Update score attributes
          score.value = score_params[:score]
          score.comments = score_params[:comments]
          score.good = score_params[:good]
          score.bad = score_params[:bad]

          # Check if score is empty
          is_empty = score.value.blank? && score.comments.blank? &&
                     score.good.blank? && score.bad.blank?

          if is_empty && Event.current.assign_judges == 0
            # Delete empty scores when not assigning judges
            score.destroy if score.persisted?
          else
            # Save score
            score.save!
          end

          succeeded << { heat_id: heat.id, slot: slot }
        rescue => e
          failed << {
            heat_id: score_params[:heat],
            slot: score_params[:slot]&.to_i,
            error: e.message
          }
        end
      end
    end

    render json: {
      succeeded: succeeded,
      failed: failed
    }
  end

  # GET /scores/:judge/heat/:heat
  def heat
    @event = Event.current
    @judge = Person.find(params[:judge].to_i)
    @number = params[:heat].to_f
    @number = @number.to_i if @number == @number.to_i
    @slot = params[:slot]&.to_i
    @style = params[:style]
    @style = 'radio' if @style.blank?
    @subjects = Heat.where(number: @number).includes(
      dance: [:multi_children],
      entry: [:age, :level, :lead, :follow],
      scores: []
    ).to_a

    @slot ||= 1 if @subjects.first&.category == 'Multi' and @slot.nil?

    @combine_open_and_closed = @event.heat_range_cat == 1
    @column_order = @event.column_order

    # Handle case where heat doesn't exist
    if @subjects.empty?
      render plain: "Heat #{@number} not found", status: :not_found
      return
    end

    category = @subjects.first.category
    category = 'Open' if category == 'Closed' and @event.closed_scoring == '='

    @heat = @subjects.first

    slots = @slot

    # Only apply scrutineering logic for Multi category heats
    if @heat.category == 'Multi' && @heat.dance.uses_scrutineering?
      @style = 'radio' if params[:style].blank?

      # For multi-dance events, we need to check the parent dance's heat_length
      parent_dance = @heat.dance.multi_dances.first&.parent || @heat.dance
      heat_length = parent_dance.heat_length

      # Set default slot if not already set (for multi-dance child heats)
      @slot ||= 1 if heat_length && heat_length > 0

      @final = (@slot || 0) > heat_length || @subjects.length <= 8

      if @final
        # sort subjects by score
        @subjects = final_scores.map(&:heat).uniq
      else
        @callbacks = 6

        # Removed: Treat all slots in preliminary as slot 1 for scoring purposes
        # slots = (1..(heat_length || 1))
      end
    end

    if @subjects.empty?
      @dance = '-'
      @scores = []
    else
      if @subjects.first.dance_id == @subjects.last.dance_id
        @dance = "#{@subjects.first.category} #{@subjects.first.dance.name}"
      else
        @dance = "#{@subjects.first.category} #{@subjects.first.dance_category.name}"
      end
      # Determine scoring type for this heat
      scoring_type = case category
      when 'Open'
        @event.open_scoring
      when 'Closed'
        @event.closed_scoring == '=' ? @event.open_scoring : @event.closed_scoring
      when 'Multi'
        @event.multi_scoring
      else
        '1' # default
      end

      # Set scores based on scoring type
      @scores = get_scores_for_type(scoring_type)

      if @combine_open_and_closed and %w(Open Closed).include? category
        @dance.sub! /^\w+ /, ''
        # Use the closed scoring setting when combining open/closed
        if category == 'Open'
          @scores = get_scores_for_type(@event.closed_scoring)
        end
      end
    end

    scores = Score.where(judge: @judge, heat: @subjects, slot: slots).all
    student_results = scores.map {|score| [score.heat, score.value]}.
      select {|heat, value| value}.to_h

    @results = {}
    @subjects.each do |subject|
      score = student_results[subject] || ''
      if @style == 'radio' and @subjects.first.category != 'Solo'
        @results[subject] = score
      else
        score = student_results[subject] || ''
        @results[score] ||= []
        @results[score] << subject
      end
    end

    # 1 - 1/2/3/F
    # G - GH/G/S/B
    # # - Number (85, 95, ...)
    # + - Feedback (Needs Work On / Great Job With)
    # & - Number (1-5) and Feedback
    # S - Solo

    if @heat.category == 'Solo'
      @scoring = 'S'
    elsif @heat.category == 'Multi'
      @scoring = @event.multi_scoring
    elsif @heat.category == 'Open' || (@heat.category == 'Closed' && @event.closed_scoring == '=') || @event.heat_range_cat > 0
      @scoring = @event.open_scoring
    else
      @scoring = @event.closed_scoring
    end

    if %w(+ & @).include? @scoring
      @good = {}
      @bad = {}
      @value = {}
      scores.each do |score|
        @good[score.heat_id] = score.good
        @bad[score.heat_id] = score.bad
        @value[score.heat_id] = score.value
      end
    end

    @sort = @judge.sort_order || 'back' unless @final
    @show = @judge.show_assignments || 'first'
    @show = 'mixed' unless @event.assign_judges > 0 and @show != 'mixed' && Person.where(type: 'Judge').count > 1
    
    # Apply assignment sorting first, before ballroom assignment
    if @show != 'mixed'
      @subjects.sort_by! do |subject|
        assignment_priority = subject.scores.any? {|score| score.judge_id == @judge.id} ? 0 : 1
        [assignment_priority, subject.dance_id, subject.entry.lead.back || 0]
      end
    else
      @subjects.sort_by! {|heat| [heat.dance_id, heat.entry.lead.back || 0]}
    end
    
    @ballrooms_count = @subjects.first&.dance_category&.ballrooms || @event.ballrooms
    @ballrooms = assign_rooms(@ballrooms_count, @subjects, @number, preserve_order: @show != 'mixed')

    if @sort == 'level'
      @ballrooms.each do |ballroom, subjects|
        subjects.sort_by! do |subject|
          entry = subject.entry
          assignment_priority = @show != 'mixed' && subject.scores.any? {|score| score.judge_id == @judge.id} ? 0 : 1
          [assignment_priority, entry.level_id || 0, entry.age_id || 0, entry.lead.back || 0]
        end
      end
    end

    @scores << '' unless @scores.length == 0

    if @heat.category == 'Solo'
      @comments = Score.find_by(judge: @judge, heat: @subjects.first)&.comments
    else
      @comments = Score.where(judge: @judge, heat: @subjects).
        map {|score| [score.heat_id, score.comments]}.to_h
    end

    @style = nil if @style == 'radio'
    # Use params[:style] for navigation to preserve user's original style choice
    # (@style may have been overridden to 'radio' for scrutineering)
    options = {style: params[:style]}

    heats = Heat.all.where(number: 1..).order(:number).group(:number).
      includes(
        dance: [:open_category, :closed_category, :multi_category, {solo_category: :extensions}],
        entry: %i[lead follow],
        solo: %i[category_override]
      ).to_a.sort_by(&:number)

    show_solos = params[:solos] || @judge&.judge&.review_solos&.downcase
    if show_solos == 'none'
      heats = heats.reject {|heat| heat.category == 'Solo'}
    elsif show_solos == 'even'
      heats = heats.reject {|heat| heat.category == 'Solo' && heat.number.odd?}
    elsif show_solos == 'odd'
      heats = heats.reject {|heat| heat.category == 'Solo' && heat.number.even?}
    end

    index = heats.index {|heat| heat.number == @heat.number}

    # For multi-dance events, use parent dance's heat_length
    # Only apply slot-based navigation for Multi category heats
    if @heat.category == 'Multi'
      parent_dance = @heat.dance.multi_dances.first&.parent || @heat.dance
      effective_heat_length = parent_dance.heat_length || 0
    else
      effective_heat_length = 0
    end

    max_slots = effective_heat_length
    max_slots *= 2 if @heat.dance.uses_scrutineering? && (!@final || @slot > effective_heat_length)
    if effective_heat_length > 0 and (@slot||0) < max_slots
      @next = judge_heat_slot_path(judge: @judge, heat: @number, slot: (@slot||0)+1, **options)
    else
      @next = index + 1 >= heats.length ? nil : heats[index + 1]
      if @next
        # Only use slot-based navigation for Multi category heats
        if @next.category == 'Multi'
          next_parent = @next.dance.multi_dances.first&.parent || @next.dance
          if next_parent.heat_length
            @next = judge_heat_slot_path(judge: @judge, heat: @next.number, slot: 1, **options)
          else
            @next = judge_heat_path(judge: @judge, heat: @next.number, **options)
          end
        else
          @next = judge_heat_path(judge: @judge, heat: @next.number, **options)
        end
      end
    end

    if effective_heat_length > 0 and (@slot||0) > 1
      @prev = judge_heat_slot_path(judge: @judge, heat: @number, slot: (@slot||2)-1, style: @style, **options)
    else
      @prev = index > 0 ? heats[index - 1] : nil
      if @prev
        # Only use slot-based navigation for Multi category heats
        if @prev.category == 'Multi'
          prev_parent = @prev.dance.multi_dances.first&.parent || @prev.dance
          if prev_parent.heat_length
            max_slots = prev_parent.heat_length || 0
            max_slots *= 2 if @prev.dance.uses_scrutineering? && (Heat.where(number: @prev.number).count > 8)
            @prev = judge_heat_slot_path(judge: @judge, heat: @prev.number, slot: max_slots, **options)
          else
            @prev = judge_heat_path(judge: @judge, heat: @prev.number, **options)
          end
        else
          @prev = judge_heat_path(judge: @judge, heat: @prev.number, **options)
        end
      end
    end

    @style = 'radio' if @style.nil?

    if @style == 'emcee' and @heat.dance.songs.length > 0
      index = Heat.joins(:entry).where(dance_id: @heat.dance_id).distinct.order(:number).pluck(:number).index(@heat.number)
      @song = @heat.dance.songs[index % @heat.dance.songs.length]
    end

    @layout = 'mx-0 px-5'
    @nologo = true
    @backnums = @event.backnums
    @track_ages = @event.track_ages

    @assign_judges = @style != 'emcee' && @event.assign_judges > 0 && @heat.category != 'Solo' && Person.where(type: 'Judge').count > 1

    @feedbacks = Feedback.all
  end

  def post
    judge = Person.find(params[:judge].to_i)
    heat = Heat.find(params[:heat].to_i)
    slot = params[:slot]&.to_i

    if heat.dance.uses_scrutineering?
      # For multi-dance events, use parent dance's heat_length
      parent_dance = heat.dance.multi_dances.first&.parent || heat.dance
      heat_length = parent_dance.heat_length

      subject_count = Heat.where(number: heat.number).count
      final = slot > heat_length || subject_count <= 8

      # Removed: Treat all slots in preliminary as slot 1 for scoring purposes
      # slot = 1 unless final
    end

    retry_transaction do
      score = Score.find_or_create_by(judge_id: judge.id, heat_id: heat.id, slot: slot)
      if ApplicationRecord.readonly?
        render json: 'database is readonly', status: :service_unavailable
      elsif params[:comments]
        if params[:comments].empty?
          score.comments = nil
        else
          score.comments = params[:comments]
        end

        keep = score.good || score.bad || (!score.comments.blank?) || score.value || Event.current.assign_judges > 0
        if keep ? score.save : score.delete
          render json: score.as_json
        else
          render json: score.errors, status: :unprocessable_content
        end
      elsif not params[:score].blank? or not score.comments.blank? or Event.current.assign_judges > 0
        if params[:name] && heat.category == 'Solo' && Event.current.solo_scoring == '4'
          # Solo heats with 4-part scoring use JSON to store multiple named scores
          value = score.value&.start_with?('{') ? JSON.parse(score.value) : {}
          value[params[:name]] = params[:score]
          score.value = value.to_json
        else
          # All other scoring types (including solo with single score) store plain values
          score.value = params[:score]
        end

        if score.save
          render json: score.as_json
        else
          render json: score.errors, status: :unprocessable_content
        end
      else
        score.destroy
        render json: score
      end
    end
  end

  def update_rank
    @judge = Person.find(params[:judge].to_i)
    from_heat_id = params[:source].to_i
    to_heat_id = params[:target].to_i

    # Get slot from parent container if available
    @slot = nil
    if params[:id] && params[:id].match(/slot-(\d+)/)
      @slot = $1.to_i
    end

    from_heat = Heat.find_by(id: from_heat_id)
    @number = from_heat&.number || 0

    retry_transaction do
      @subjects = Heat.where(number: @number).includes(
        dance: [:multi_children],
        entry: [:age, :level, :lead, :follow]
      ).to_a

      @heat = @subjects.first

      scores = final_scores
    
      # Find the scores 
      from_score = scores.find { |score| score.heat_id == from_heat_id }
      to_score = scores.find { |score| score.heat_id == to_heat_id }
      
      if from_score && to_score
        from_rank = from_score.value.to_i
        to_rank = to_score.value.to_i
        
        # Get scores in the affected range and rotate their ranks
        if from_rank > to_rank
          # Moving up (e.g., 5 to 2)
          affected_scores = scores.select { |s| s.value.to_i >= to_rank && s.value.to_i <= from_rank }
          new_ranks = affected_scores.map { |s| s.value.to_i }.rotate(1)
        else
          # Moving down (e.g., 2 to 5)
          affected_scores = scores.select { |s| s.value.to_i >= from_rank && s.value.to_i <= to_rank }
          new_ranks = affected_scores.map { |s| s.value.to_i }.rotate(-1)
        end
        
        # Update all affected scores with their new ranks
        affected_scores.zip(new_ranks).each do |score, new_rank|
          score.update!(value: new_rank.to_s)
        end

        # Re-sort subjects by score
        @subjects = scores.to_a.map {|score| [score.value.to_i, score]}.sort
          .map {|value, score| score.heat}.uniq
      end
    end

    # Reload heat data and render updated partial      
    @track_ages = Event.current.track_ages
    @column_order = Event.current.column_order
    @combine_open_and_closed = Event.current.heat_range_cat == 1
    
    render turbo_stream: turbo_stream.replace("rank-heat-container", 
      partial: "scores/rank_heat", 
      locals: { judge: @judge, subjects: @subjects, column_order: @column_order, combine_open_and_closed: @combine_open_and_closed })
  end

  def post_feedback
    judge = Person.find(params[:judge].to_i)
    heat = Heat.find(params[:heat].to_i)
    slot = params[:slot]&.to_i

    retry_transaction do
    score = Score.find_or_create_by(judge_id: judge.id, heat_id: heat.id, slot: slot)
    if ApplicationRecord.readonly?
      render json: 'database is readonly', status: :service_unavailable
    else
      if params.include? :good
        feedback = score.good.to_s.split(' ')
        unless feedback.delete(params[:good])
          feedback << params[:good]
          feedback.sort!
        end
        score.good = feedback.empty? ? nil : feedback.join(' ')

        feedback = score.bad.to_s.split(' ')
        if feedback.delete(params[:good])
          score.bad = feedback.empty? ? nil : feedback.join(' ')
        end
      elsif params.include? :bad
        feedback = score.bad.to_s.split(' ')
        unless feedback.delete(params[:bad])
          feedback << params[:bad]
          feedback.sort!
        end
        score.bad = feedback.empty? ? nil : feedback.join(' ')

        feedback = score.good.to_s.split(' ')
        if feedback.delete(params[:bad])
          score.good = feedback.empty? ? nil : feedback.join(' ')
        end
      elsif params.include? :value
        if score.value == params[:value]
          score.value = nil
        else
          score.value = params[:value]
        end
      else
        render json: params, status: :bad_request
        return
      end

      keep = score.good || score.bad || (!score.comments.blank?) || score.value || Event.current.assign_judges > 0

      if keep ? score.save : score.delete
        render json: score.as_json
      else
        render json: score.errors, status: :unprocessable_content
      end
    end
    end
  end

  # GET /scores or /scores.json
  def index
    @scores = Score.all
  end

  def by_level
    setup_score_view_params
    @event = Event.current
    @open_scoring = @event.open_scoring
    @closed_scoring = @event.closed_scoring
    @open_scores = get_scores_for_type(@open_scoring)
    @closed_scores = get_scores_for_type(@closed_scoring == '=' ? @open_scoring : @closed_scoring)
    levels = Level.order(:id).all

    @last_score_update = Score.maximum(:updated_at)

    template1 = ->() {
      levels.map {|level| [level, {}]}.to_h
    }

    @scores = {
      'Followers' => template1[],
      'Leaders' => template1[],
      'Couples' => template1[]
    }

    people = Person.where(type: 'Student').
      map {|person| [person.id, person]}.to_h
    levels = Level.all.map {|level| [level.id, level]}.to_h

    student_results.each do |group, scores|
      scores.each do |(score, *students), count|
        students = students.map {|student| people[student]}

        if students.length == 1
          level = levels[students.first.level_id]
        else
          level = levels[students.map {|student| student.level_id}.max]
        end

        @scores[group][level][students] ||= {
          'Open' => %w(& +).include?(@open_scoring) ? [0]*5 : get_scores_for_type(@open_scoring).map {0},
          'Closed' => get_scores_for_type(@closed_scoring == '=' ? @open_scoring : @closed_scoring).map {0},
          'points' => 0
        }

        if @open_scoring == '#' || @closed_scoring == '#'
          @scores[group][level][students]['points'] += score.to_i
        else
          value = @closed_scores.index score

          if value
            category = 'Closed'
          else
            category = 'Open'
            value = @open_scores.index score
          end

          if not value and @open_scoring == '&' and score =~ /^\d+$/
            value = score.to_i - 1
            value = 4-value

            @scores[group][level][students][category][value] += count
            @scores[group][level][students]['points'] += count * value
          elsif value
            @scores[group][level][students][category][value] += count
            @scores[group][level][students]['points'] += count * WEIGHTS[value]
          end
        end
      end
    end

    unless @details
      @results = {}
      @scores.each do |group, levels|
        levels.each do |level, students|
          @results[level] ||= {}
          @results[level][group] = students
        end
      end
    end

    if request.post?
      partial_name = @details ? 'scores/details/by_level' : 'by_level'
      render turbo_stream: turbo_stream.replace("scores-by-level",
        render_to_string(partial: partial_name, layout: false)
      )
    end
  end

  def by_studio
    @event = Event.current
    @open_scoring = @event.open_scoring
    @closed_scoring = @event.closed_scoring
    @open_scores = get_scores_for_type(@open_scoring)
    @closed_scores = get_scores_for_type(@closed_scoring == '=' ? @open_scoring : @closed_scoring)
    levels = Level.order(:id).all
    total = Struct.new(:name).new('Total')

    @last_score_update = Score.maximum(:updated_at)

    @scores = levels.map {|level| [level, {}]}.to_h
    @scores[total] = {}

    people = Person.where(type: 'Student').
      map {|person| [person.id, person]}.to_h
    levels = Level.all.map {|level| [level.id, level]}.to_h

    student_results.each do |group, scores|
      scores.each do |(score, *students), count|
        students = students.map {|student| people[student]}
        count = count.to_f / students.length

        students.each do |student|
          level = student.level
          studio = student.studio.name

          @scores[level][studio] ||= {
            'Open' => %w(& +).include?(@open_scoring) ? [0]*5 : @open_scores.map {0},
            'Closed' => @closed_scores.map {0},
            'points' => 0,
            'count' => 0
          }

          @scores[total][studio] ||= {
            'Open' => %w(& +).include?(@open_scoring) ? [0]*5 : @open_scores.map {0},
            'Closed' => @closed_scores.map {0},
            'points' => 0,
            'count' => 0
          }

          points = 0

          if @open_scoring == '#'
            points = count * score.to_i
            category = 'Open'
          elsif @closed_scoring == '#'
            points = count * score.to_i
            category = 'Closed'
          else
            value = @closed_scores.index score
            if value
              category = 'Closed'
            else
              category = 'Open'
              value = @open_scores.index score
            end

            if not value and @open_scoring == '&' and score =~ /^\d+$/
              value = score.to_i - 1
              points = count * (value + 1)
              value = 4-value

            elsif value
              points = count * WEIGHTS[value]
            end
          end

          if points > 0
            if value and (!%(# +).include? @open_scoring or @closed_scoring == '#')
              @scores[level][studio][category][value] += count
              @scores[total][studio][category][value] += count
            end

            @scores[level][studio]['count'] += count
            @scores[level][studio]['points'] += points

            @scores[total][studio]['count'] += count
            @scores[total][studio]['points'] += points
          end
        end
      end
    end

    @scores.each do |level, studios|
      studios.each do |name, results|
        if results['count'] == 0 || results['points'] == nil
          results['avg'] = 0
        else
          results['avg'] = results['points'].to_f / results['count']
        end
      end
    end

    if request.post?
      render turbo_stream: turbo_stream.replace("scores-by-studio",
        render_to_string(partial: 'by_studio', layout: false)
      )
    end
  end

  def by_age
    setup_score_view_params
    @event = Event.current
    @open_scoring = @event.open_scoring
    @closed_scoring = @event.closed_scoring
    @open_scores = get_scores_for_type(@open_scoring)
    @closed_scores = get_scores_for_type(@closed_scoring == '=' ? @open_scoring : @closed_scoring)
    ages = Age.order(:id).all

    template1 = ->() {
      ages.map {|age| [age, {}]}.to_h
    }

    @scores = {
      'Followers' => template1[],
      'Leaders' => template1[],
      'Couples' => template1[]
    }

    people = Person.where(type: 'Student').
      map {|person| [person.id, person]}.to_h
    ages = Age.all.map {|age| [age.id, age]}.to_h

    student_results.each do |group, scores|
      scores.each do |(score, *students), count|
        students = students.map {|student| people[student]}

        if students.length == 1
          age = ages[students.first.age_id]
        else
          age = ages[students.map {|student| student.age_id || 0 }.max]
        end

        age ||= ages.first.last

        @scores[group][age][students] ||= {
          'Open' => %w(& +).include?(@open_scoring) ? [0]*5 : @open_scores.map {0},
          'Closed' => @closed_scores.map {0},
          'points' => 0
        }

        if @open_scoring == '#' || @closed_scoring == '#'
          @scores[group][age][students]['points'] += score.to_i
        else
          value = @closed_scores.index score
          if value
            category = 'Closed'
          else
            category = 'Open'
            value = @open_scores.index score
          end

          if not value and @open_scoring == '&' and score =~ /^\d+$/
            value = score.to_i - 1
            value = 4-value

            @scores[group][age][students][category][value] += count
            @scores[group][age][students]['points'] += count * value
          elsif value
            @scores[group][age][students][category][value] += count
            @scores[group][age][students]['points'] += count * WEIGHTS[value]
          end
        end
      end
    end

    unless @details
      @results = {}
      @scores.each do |group, ages|
        ages.each do |age, students|
          @results[age] ||= {}
          @results[age][group] = students
        end
      end
    end

    if request.post?
      partial_name = @details ? 'scores/details/by_age' : 'by_age'
      render turbo_stream: turbo_stream.replace("scores-by-age",
        render_to_string(partial: partial_name, layout: false)
      )
    end
  end

  def multis
    setup_score_view_params
    event = Event.current
    @multi_scoring = event.multi_scoring
    dances = Dance.where.not(multi_category_id: nil).
      includes(multi_children: :dance, heats: [{entry: [:lead, :follow]}, :scores]).
      ordered

    @score_range = get_scores_for_type(@multi_scoring)

    @scores = {}
    @scrutineering_results = {}
    
    dances.each do |dance|
      @scores[dance] = {}
      
      # Check if this dance uses semi-finals
      if dance.semi_finals?
        # Check if there are any scores for this dance
        total_scores = dance.heats.joins(:scores).count
        
        if total_scores > 0
          # Use scrutineering rankings
          summary, ranks = dance.scrutineering
          @scrutineering_results[dance] = {
            summary: summary,
            ranks: ranks
          }
          
          # Only show entries that have been ranked and have complete summary data
          # Filter out entries with no ranking, invalid ranks, or empty summaries
          ranks.select { |entry_id, rank| rank && rank > 0 && rank < 999 && summary[entry_id] && !summary[entry_id].empty? }.each do |entry_id, rank|
            entry = Entry.find(entry_id)
            @scores[dance][entry] = {
              'Multi' => @score_range.map {0},
              'points' => 0,
              'rank' => rank,
              'summary' => summary[entry_id] || {}
            }
          end
        end
      else
        # Use regular scoring
        dance.heats.map(&:scores).flatten.group_by {|score| score.heat.entry}.map do |entry, scores|
          @scores[dance][entry] = {
            'Multi' => @score_range.map {0},
            'points' => 0
          }

          scores.each do |score|
            if @multi_scoring == '#'
              @scores[dance][entry]['points'] += score.value.to_i
            else
              value = @score_range.index score.value
              if value
                @scores[dance][entry]['Multi'][value] += 1
                @scores[dance][entry]['points'] += WEIGHTS[value]
              end
            end
          end
        end
      end
    end

    if request.post?
      partial_name = @details ? 'scores/details/multis' : 'multis'
      render turbo_stream: turbo_stream.replace("multis-scores",
        render_to_string(partial: partial_name, layout: false)
      )
    end
  end

  def skating
    @dance = Dance.find(params[:dance_id])
    
    unless @dance.semi_finals?
      redirect_to scores_multis_path, alert: "This dance does not use skating system calculations."
      return
    end
    
    # Set up column order for consistent display
    event = Event.current
    @column_order = event.column_order
    @last_score_update = Score.maximum(:updated_at)
    
    # Get the detailed calculation steps
    summary, ranks, @explanations = @dance.scrutineering(with_explanations: true)
    
    # Convert to display format matching multis view
    @scrutineering_results = {
      summary: summary,
      ranks: ranks
    }
    
    # Build scores display for consistency with existing templates
    @scores = {}
    @scores[@dance] = {}
    
    ranks.select { |entry_id, rank| rank && rank > 0 && rank < 999 && summary[entry_id] && !summary[entry_id].empty? }.each do |entry_id, rank|
      entry = Entry.find(entry_id)
      @scores[@dance][entry] = {
        'rank' => rank,
        'summary' => summary[entry_id] || {}
      }
    end
    
    # Get dance names for proper display
    @dance_names = {}
    @dance.multi_children.includes(:dance).each_with_index do |child, index|
      @dance_names[child.dance.name] = child.dance.name
    end
    
    # Handle POST requests for live updates
    if request.post?
      render turbo_stream: turbo_stream.replace("skating-content",
        partial: 'scores/skating_content',
        locals: { 
          dance: @dance,
          scores: @scores,
          scrutineering_results: @scrutineering_results,
          explanations: @explanations,
          column_order: @column_order
        }
      )
    end
  end

  def pros
    @event = Event.current
    scores = Score.joins(heat: {entry: [:lead, :follow]}).where(lead: {type: 'Professional'}, follow: {type: 'Professional'})
    hscores = scores.group_by {|score| score.heat.number}
    dances = hscores.values.map(&:first).map {|score| [score.heat.number, score.heat.dance.name]}.to_h
    categories = hscores.values.map(&:first).map {|score| [score.heat.number, score.heat.dance_category.name]}.to_h

    if categories.values.uniq.length >= dances.values.uniq.length
      names = categories
    else
      names = dances
    end

    # Determine scoring type based on heat category
    heat_category = scores.first&.heat&.category || 'Open'
    scoring_type = case heat_category
    when 'Open'
      @event.open_scoring
    when 'Closed'
      @event.closed_scoring == '=' ? @event.open_scoring : @event.closed_scoring
    when 'Multi'
      @event.multi_scoring
    else
      '1'
    end
    @score_range = get_scores_for_type(scoring_type)

    @scores = {}
    hscores.each do |number, scores|
      name = names[number]
      @scores[name] = {}

      scores.each do |score|
        entry = score.heat.entry

        @scores[name][entry] ||= {
          'Values' => @score_range.map {0},
          'points' => 0
        }

        value = @score_range.index score.value
        if value
          @scores[name][entry]['Values'][value] += 1
          @scores[name][entry]['points'] += WEIGHTS[value]
        end
      end
    end

    if request.post?
      render turbo_stream: turbo_stream.replace("pros-scores",
        render_to_string(partial: 'pros', layout: false)
      )
    end
  end

  def instructor
    @event = Event.current
    @open_scoring = @event.open_scoring
    @closed_scoring = @event.closed_scoring
    @open_scores = get_scores_for_type(@open_scoring)
    @closed_scores = get_scores_for_type(@closed_scoring == '=' ? @open_scoring : @closed_scoring)
    @scores = {}

    people = Person.where(type: 'Professional').
      map {|person| [person.id, person]}.to_h

    instructor_results.each do |(score, instructor), count|
      person = people[instructor]

      @scores[person] ||= {
        'Open' => @open_scoring == '&' ? [0]*5 : @open_scores.map {0},
        'Closed' => @closed_scores.map {0},
        'points' => 0
      }

      if @open_scoring == '#'
        @scores[person]['points'] += score.to_i
      else
        value = @closed_scores.index score
        if value
          category = 'Closed'
        else
          category = 'Open'
          value = @open_scores.index score
        end

        if not value and @open_scoring == '&' and score =~ /^\d+$/
          value = score.to_i - 1
          value = 4-value

          @scores[person][category][value] += count
          @scores[person]['points'] += count * value
        elsif value
          @scores[person][category][value] += count
          @scores[person]['points'] += count * WEIGHTS[value]
        end
      end
    end

    if request.post?
      render turbo_stream: turbo_stream.replace("instructor-scores",
        render_to_string(partial: 'instructors', layout: false)
      )
    end
  end

  def sort
    judge = Judge.find_or_create_by(person_id: params[:judge])
    judge.update! sort: params[:sort]
    style = params[:style]
    style = nil if style == 'radio' || style == ''
    if params[:show].blank?
      redirect_to judge_heatlist_path(judge: params[:judge], style: style)
    else
      redirect_to judge_heatlist_path(judge: params[:judge], style: style)
    end
  end

  # GET /scores/1 or /scores/1.json
  def show
  end

  # GET /scores/new
  def new
    @score ||= Score.new
  end

  # GET /scores/1/edit
  def edit
  end

  # POST /scores or /scores.json
  def create
    @score = Score.new(score_params)

    respond_to do |format|
      if @score.save
        format.html { redirect_to score_url(@score), notice: "Score was successfully created." }
        format.json { render :show, status: :created, location: @score }
      else
        new
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @score.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /scores/1 or /scores/1.json
  def update
    respond_to do |format|
      if @score.update(score_params)
        format.html { redirect_to score_url(@score), notice: "Score was successfully updated." }
        format.json { render :show, status: :ok, location: @score }
      else
        edit
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @score.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /scores/1 or /scores/1.json
  def destroy
    @score.destroy

    respond_to do |format|
      format.html { redirect_to scores_url, notice: "Score was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  # POST /scores/reset
  def reset
    Score.delete_all
    redirect_to settings_event_index_path(tab: 'Advanced'), notice: 'Scores were successfully reset.'
  end

  def comments
    @comments = Score.includes(:judge, heat: {entry: [lead: :studio, follow: :studio]}).where.not(comments: nil).
      map do |score|
        scores = []

        if score.heat.entry.lead.type == 'Student'
          scores << [score.heat.number, score.heat.dance.name, score.heat.entry.lead.name, score.heat.entry.follow.name, score.heat.entry.lead.studio.name, score.judge.name, score.comments]
        end

        if score.heat.entry.follow.type == 'Student'
          scores << [score.heat.number, score.heat.dance.name, score.heat.entry.follow.name, score.heat.entry.lead.name, score.heat.entry.lead.studio.name, score.judge.name, score.comments]
        end

        scores
      end.flatten(1).sort

    respond_to do |format|
      format.html
      format.csv
      format.json
    end
  end

  def unscored
    # Get heats with no scores at all
    heats_without_scores = Heat.left_joins(:scores)
      .where(scores: { id: nil })
      .where.not(number: nil)
      .where.not(number: 0)

    # Get heats with scores but all fields are null
    heats_with_empty_scores = Heat.joins(:scores)
      .where(scores: { value: nil, comments: nil, good: nil, bad: nil })
      .where.not(number: nil)
      .where.not(number: 0)

    # Combine both sets of heats
    heat_ids = heats_without_scores.pluck(:id) + heats_with_empty_scores.pluck(:id)

    @unscored_heats = Heat.where(id: heat_ids.uniq)
      .includes(entry: [:lead, :follow], scores: :judge)
      .order(:number)

    # Get the column order setting from the event
    @column_order = Event.current.column_order

    respond_to do |format|
      format.html
      format.csv
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_score
      @score = Score.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def score_params
      params.require(:score).permit(:judge_id, :heat_id, :value)
    end
    
    def get_scores_for_type(scoring_type)
      case scoring_type
      when '1'
        %w(1 2 3 F)
      when 'G'
        %w(B S G GH).reverse
      when '#'
        [] # Number scoring doesn't use predefined scores
      when '+', '&', '@'
        [] # Feedback scoring doesn't use predefined scores
      else
        %w(1 2 3 F) # default
      end
    end

    def student_results
      event = Event.current
      strict = event.strict_scoring

      if not strict
        additional = {
          followers: nil,
          leaders: nil,
          couples: nil
        }
      elsif event.track_ages
        additional = {
          followers: 'follow.level_id = entries.level_id and follow.age_id = entries.age_id',
          leaders: 'lead.level_id = entries.level_id and lead.age_id = entries.age_id',
          couples: 'MAX(lead.level_id, follow.level_id) = entries.level_id and MIN(lead.age_id, follow.age_id) = entries.age_id'
        }
      else
        additional = {
          followers: 'follow.level_id = entries.level_id',
          leaders: 'lead.level_id = entries.level_id',
          couples: 'MAX(lead.level_id, follow.level_id) = entries.level_id'
        }
      end

      {
        'Followers' => Score.joins(heat: {entry: [:lead, :follow]}).
          group(:value, :follow_id).
          where(follow: {type: 'Student'}, lead: {type: 'Professional'}).
          where(additional[:followers]).
          count(:value),
        'Leaders' => Score.joins(heat: {entry: [:lead, :follow]}).
          group(:value, :lead_id).
          where(lead: {type: 'Student'}, follow: {type: 'Professional'}).
          where(additional[:leaders]).
          count(:value),
        'Couples' => Score.joins(heat: {entry: [:lead, :follow]}).
          group(:value, :follow_id, :lead_id).
          where(lead: {type: 'Student'}, follow: {type: 'Student'},
            heat: {category: ['Open', 'Closed']}).
          where(additional[:couples]).
          count(:value)
       }
    end

    def instructor_results
      Score.joins(heat: {entry: [:follow]}).
        group(:value, :follow_id).
        where(follow: {type: 'Professional'}).
        count(:value).to_a +
      Score.joins(heat: {entry: [:lead]}).
        group(:value, :lead_id).
        where(lead: {type: 'Professional'}).
        count(:value).to_a +
      Score.joins(heat: :entry).
        group(:value, :instructor_id).
        where.not(entry: {instructor_id: nil}).
        count(:value).to_a +
      Score.joins(heat: {solo: :formations}).
        group(:person_id, :value).
        count(:value).to_a
    end

    # Common setup for score view methods
    def setup_score_view_params
      @details = params[:details] == true || params[:details] == "true"
      event = Event.current
      @column_order = event.column_order
      @last_score_update = Score.maximum(:updated_at)
    end

    # Common POST request handling for score views
    def handle_post_request(partial_name)
      if request.post?
        render turbo_stream: turbo_stream.replace("#{partial_name}-scores",
          render_to_string(partial: partial_name, layout: false)
        )
      end
    end

    # Process callback data for a single dance
    def process_dance_for_callbacks(dance)
      # Check if there are any scores for this dance
      total_scores = dance.heats.joins(:scores).count
      
      return unless total_scores > 0
      
      heat_numbers = dance.heats.where(number: 1..).distinct.pluck(:number)
      
      heat_numbers.each do |heat_number|
        process_heat_for_callbacks(dance, heat_number, heat_numbers)
      end
    end

    # Process callback data for a single heat within a dance
    def process_heat_for_callbacks(dance, heat_number, heat_numbers)
      # Create a unique key for each dance/heat combination
      dance_heat_key = heat_numbers.length > 1 ? "#{dance.name} - Heat #{heat_number}" : dance.name
      @scores[dance_heat_key] = { dance: dance, heat_number: heat_number, entries: {} }
      
      heats = dance.heats.where(number: heat_number)
      scores = Score.joins(:heat).where(heat: heats).where.not(value: [nil, '']).includes(:judge, heat: :entry)
      
      return unless scores.any?
      
      # Group scores by slot to understand semi-finals vs finals
      scores_by_slot = scores.group_by(&:slot)
      valid_slots = scores_by_slot.keys.compact
      final_slot = valid_slots.max
      semi_final_slots = valid_slots.select { |slot| slot && final_slot && slot < final_slot }
      
      return unless semi_final_slots.any?
      
      # Get entries that were called back to finals
      called_back_entries = determine_called_back_entries(heat_number, heats, final_slot, semi_final_slots)
      
      # Process callback votes and create entry data
      process_callback_votes(dance_heat_key, scores_by_slot, semi_final_slots, called_back_entries)
    end

    # Determine which entries were called back to finals
    def determine_called_back_entries(heat_number, heats, final_slot, semi_final_slots)
      called_back_entries = Set.new
      if final_slot && semi_final_slots.any?
        called_back_entry_ids = determine_callbacks(heat_number, heats, semi_final_slots)
        called_back_entries = Set.new(Entry.where(id: called_back_entry_ids))
      end
      called_back_entries
    end

    # Process callback votes for semi-finals and create entry data
    def process_callback_votes(dance_heat_key, scores_by_slot, semi_final_slots, called_back_entries)
      entry_callbacks = {}
      entry_judges = {}
      
      semi_final_slots.each do |slot|
        slot_scores = scores_by_slot[slot]
        
        slot_scores.each do |score|
          entry = score.heat.entry
          entry_callbacks[entry] ||= 0
          entry_callbacks[entry] += 1 if score.value.to_i >= 1
          
          if score.value.to_i >= 1
            entry_judges[entry] ||= Set.new
            entry_judges[entry].add(score.judge)
          end
        end
      end
      
      # Create entries in the format expected by multis view
      entry_callbacks.each do |entry, votes|
        @scores[dance_heat_key][:entries][entry] = {
          'callbacks' => votes,
          'called_back' => called_back_entries.include?(entry),
          'judges' => entry_judges[entry] || Set.new
        }
      end
    end

    # Shared method to determine which entries were called back to finals
    def determine_callbacks(heat_number, heats_or_subjects, semi_final_slots)
      # Convert to array of Heat objects if needed
      subjects = heats_or_subjects.respond_to?(:includes) ? 
                   heats_or_subjects.includes(entry: [:lead, :follow]).to_a : 
                   heats_or_subjects
      
      if subjects.length <= 8
        # For heats with 8 or fewer couples, no semi-final round is required
        # All couples proceed directly to finals
        subjects.map(&:entry_id)
      else
        # Use the callback ranking logic for large heats
        ranks = Heat.rank_callbacks(heat_number, semi_final_slots)
          .map {|entry, rank| [entry.id, rank]}.group_by {|id, rank| rank}
        
        called_back = []
        ranks.each do |rank, entries|
          break if called_back.length + entries.length > 8
          called_back.concat(entries.map(&:first))
        end
        called_back
      end
    end

    def final_scores
      # For multi-dance events, use parent dance's heat_length
      parent_dance = @heat.dance.multi_dances.first&.parent || @heat.dance
      heat_length = parent_dance.heat_length

      # select callbacks for finals using shared logic
      called_back = determine_callbacks(@number, @subjects, ..heat_length)
      @subjects.select! {|heat| called_back.include? heat.entry_id}

      # find scores for finals, or create them in random order if they don't exist
      scores = Score.joins(:heat)
        .where(judge: @judge, heats: {number: @number}, slot: @slot)

      remove = scores.select {|score| !@subjects.any? {|heat| heat.entry_id == score.heat.entry_id}}
      remove.each {|score| score.destroy}
      scores -= remove

      scores.select! {|score| score.value.to_i <= @subjects.length}
      pending = @subjects.select {|heat| !scores.any? {|score| score.heat.entry_id == heat.entry_id}}.shuffle
      ranks = (1..@subjects.length).to_a - scores.map(&:value).map(&:to_i)

      pending.zip(ranks).each do |heat, rank|
        score = Score.find_or_create_by(judge: @judge, heat: heat, slot: @slot)
        score.value = rank.to_s
        score.save
        scores << score
      end

      scores.to_a.sort_by {|score| score.value.to_i}
    end
end
