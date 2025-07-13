class ScoresController < ApplicationController
  include Printable
  include Retriable
  before_action :set_score, only: %i[ show edit update destroy ]

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
    dances = Dance.where(semi_finals: true).includes(:heats).order(:order)
    @scores = {}
    
    dances.each do |dance|
      process_dance_for_callbacks(dance)
    end
    
    handle_post_request('callbacks')
  end

  # GET /scores or /scores.json
  def heatlist
    event = Event.first
    @judge = Person.find(params[:judge].to_i)
    @style = params[:style]
    @sort = @judge.sort_order
    @show = @judge.show_assignments
    @assign_judges = event.assign_judges?

    @heats = Heat.all.where(number: 1..).order(:number).group(:number).includes(
      dance: [:open_category, :closed_category, :multi_category, {solo_category: :extensions}],
      entry: %i[lead follow],
      solo: %i[category_override]
    )
    @combine_open_and_closed = Event.last.heat_range_cat == 1

    @agenda = @heats.group_by(&:dance_category).
      sort_by {|category, heats| [category&.order || 0, heats.map(&:number).min]}
    @heats = @agenda.to_h.values.flatten
    @agenda = @agenda.map do |category, heats|
      [heats.map(&:number).min, category&.name]
    end.to_h

    @scored = Score.includes(:heat).where(judge: @judge).
      select {|score| score.value || score.comments || score.good || score.bad}.
      group_by {|score| score.heat.number.to_f}
    @count = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance).count

    if event.assign_judges? and Score.where(judge: @judge).any?
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

    @unassigned = Event.current.assign_judges > 0 ? Heat.includes(:scores).where(scores: { id: nil }).distinct.pluck(:number) : []

    render :heatlist, status: (@browser_warn ? :upgrade_required : :ok)
  end

  # GET /scores/:judge/heat/:heat
  def heat
    @event = Event.first
    @judge = Person.find(params[:judge].to_i)
    @number = params[:heat].to_f
    @number = @number.to_i if @number == @number.to_i
    @slot = params[:slot]&.to_i
    @style = params[:style]
    @style = 'radio' if @style.blank?
    @subjects = Heat.where(number: @number).includes(
      dance: [:multi_children],
      entry: [:age, :level, :lead, :follow]
    ).to_a

    @slot ||= 1 if @subjects.first&.category == 'Multi' and @slot.nil?

    @combine_open_and_closed = @event.heat_range_cat == 1
    @column_order = @event.column_order

    category = @subjects.first.category
    category = 'Open' if category == 'Closed' and @event.closed_scoring == '='

    @heat = @subjects.first

    if @heat.dance.semi_finals?
      @style = 'radio'

      # Check if we should be in final mode
      # Only use final mode if:
      # 1. We're in a finals slot (> heat_length), OR
      # 2. We have ≤8 couples AND final scores actually exist
      has_final_scores = @subjects.length <= 8 && 
                        Score.where(heat: @subjects)
                             .where('slot > ?', @heat.dance.heat_length)
                             .where.not(value: '0').exists?
      
      @final = @slot > @heat.dance.heat_length || has_final_scores

      if @final
        # sort subjects by score
        @subjects = final_scores.map(&:heat).uniq
      else
        @callbacks = 6
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
      if category == 'Open' and @event.open_scoring == 'G'
        @scores = SCORES['Closed'].dup
      elsif category == 'Open' and %w(+ &).include? @event.open_scoring
        @scores = []
      elsif category == 'Multi' and @event.multi_scoring == 'G'
        @scores = SCORES['Closed'].dup
      else
        @scores = SCORES[category].dup
      end

      if @combine_open_and_closed and %w(Open Closed).include? category
        @dance.sub! /^\w+ /, ''
        @scores = SCORES['Closed'].dup if category == 'Open'
      end
    end

    scores = Score.where(judge: @judge, heat: @subjects, slot: @slot).all
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

    @subjects.sort_by! {|heat| [heat.dance_id, heat.entry.lead.back || 0]} unless @final
    ballrooms = @subjects.first&.dance_category&.ballrooms || @event.ballrooms
    @ballrooms = assign_rooms(ballrooms, @subjects, @number)

    @sort = @judge.sort_order || 'back' unless @final
    @show = @judge.show_assignments || 'first'
    @show = 'mixed' unless @event.assign_judges > 0 and @show != 'mixed' && Person.where(type: 'Judge').count > 1
    if @sort == 'level'
      @ballrooms.each do |ballroom, subjects|
        subjects.sort_by! do |subject|
          entry = subject.entry
          [entry.level_id || 0, entry.age_id || 0, entry.lead.back || 0]
        end
      end
    end
    if @show != 'mixed'
      @ballrooms.each do |ballroom, subjects|
        subjects.sort_by! do |subject|
          entry = subject.entry
          subject.scores.any? {|score| score.judge_id == @judge.id} ? 0 : 1
        end
      end
    end

    @scores << '' unless @scores.length == 0

    if @heat.category == 'Solo'
      @comments = Score.where(judge: @judge, heat: @subjects.first).first&.comments
    else
      @comments = Score.where(judge: @judge, heat: @subjects).
        map {|score| [score.heat_id, score.comments]}.to_h
    end

    @style = nil if @style == 'radio'
    options = {style: @style}

    heats = Heat.all.where(number: 1..).order(:number).group(:number).
      includes(
        dance: [:open_category, :closed_category, :multi_category, {solo_category: :extensions}],
        entry: %i[lead follow],
        solo: %i[category_override]
      )
    agenda = heats.group_by(&:dance_category).
      sort_by {|category, heats| [category&.order || 0, heats.map(&:number).min]}
    heats = agenda.to_h.values.flatten

    show_solos = params[:solos] || @judge&.judge&.review_solos&.downcase
    if show_solos == 'none'
      heats = heats.reject {|heat| heat.category == 'Solo'}
    elsif show_solos == 'even'
      heats = heats.reject {|heat| heat.category == 'Solo' && heat.number.odd?}
    elsif show_solos == 'odd'
      heats = heats.reject {|heat| heat.category == 'Solo' && heat.number.even?}
    end

    index = heats.index {|heat| heat.number == @heat.number}

    max_slots = (@heat.dance.heat_length || 0)
    max_slots *= 2 if @heat.dance.semi_finals && (!@final || @slot > @heat.dance.heat_length)
    if @heat.dance.heat_length and (@slot||0) < max_slots
      @next = judge_heat_slot_path(judge: @judge, heat: @number, slot: (@slot||0)+1, **options)
    else
      @next = index + 1 >= heats.length ? nil : heats[index + 1]
      if @next
        if @next.dance.heat_length
          @next = judge_heat_slot_path(judge: @judge, heat: @next.number, slot: 1, **options)
        else
          @next = judge_heat_path(judge: @judge, heat: @next.number, **options)
        end
      end
    end

    if @heat.dance.heat_length and (@slot||0) > 1
      @prev = judge_heat_slot_path(judge: @judge, heat: @number, slot: (@slot||2)-1, style: @style, **options)
    else
      @prev = index > 0 ? heats[index - 1] : nil
      if @prev
        if @prev.dance.heat_length
          max_slots = @prev.dance.heat_length || 0
          max_slots *= 2 if @prev.dance.semi_finals && (Heat.where(number: @prev.number).count > 8)
          @prev = judge_heat_slot_path(judge: @judge, heat: @prev.number, slot: max_slots, **options)
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

    @assign_judges = false # @event.assign_judges > 0 && @heat.category != 'Solo' && Person.where(type: 'Judge').count > 1

    @feedbacks = Feedback.all
  end

  def post
    judge = Person.find(params[:judge].to_i)
    heat = Heat.find(params[:heat].to_i)
    slot = params[:slot]&.to_i

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

      keep = score.good || score.bad || (!score.comments.blank?) || score.value || Event.first.assign_judges > 0
      if keep ? score.save : score.delete
        render json: score.as_json
      else
        render json: score.errors, status: :unprocessable_entity
      end
    elsif not params[:score].blank? or not score.comments.blank? or Event.first.assign_judges > 0
      if params[:name]
        value = score.value&.start_with?('{') ? JSON.parse(score.value) : {}
        value[params[:name]] = params[:score]
        score.value = value.to_json
      else
        score.value = params[:score]
      end

      if score.save
        render json: score.as_json
      else
        render json: score.errors, status: :unprocessable_entity
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
    @track_ages = Event.first.track_ages
    
    render turbo_stream: turbo_stream.replace("rank-heat-container", 
      partial: "scores/rank_heat", 
      locals: { judge: @judge, subjects: @subjects })
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

      keep = score.good || score.bad || (!score.comments.blank?) || score.value || Event.first.assign_judges > 0

      if keep ? score.save : score.delete
        render json: score.as_json
      else
        render json: score.errors, status: :unprocessable_entity
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
    @event = Event.first
    @open_scoring = @event.open_scoring
    @closed_scoring = @event.closed_scoring
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
          'Open' => %w(& +).include?(@open_scoring) ? [0]*5 : SCORES['Open'].map {0},
          'Closed' => SCORES['Closed'].map {0},
          'points' => 0
        }

        if @open_scoring == '#' || @closed_scoring == '#'
          @scores[group][level][students]['points'] += score.to_i
        else
          value = SCORES['Closed'].index score

          if value
            category = 'Open'
          else
            category = %w(G @).include?(@open_scoring) ? 'Open' : 'Closed'
            value = SCORES['Open'].index score
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
    @event = Event.first
    @open_scoring = @event.open_scoring
    @closed_scoring = @event.closed_scoring
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
            'Open' => %w(& +).include?(@open_scoring) ? [0]*5 : SCORES['Open'].map {0},
            'Closed' => SCORES['Closed'].map {0},
            'points' => 0,
            'count' => 0
          }

          @scores[total][studio] ||= {
            'Open' => %w(& +).include?(@open_scoring) ? [0]*5 : SCORES['Open'].map {0},
            'Closed' => SCORES['Closed'].map {0},
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
            value = SCORES['Closed'].index score
            if value
              category = %w(G @).include?(@open_scoring) ? 'Open' : 'Closed'
            else
              category = 'Open'
              value = SCORES['Open'].index score
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
    @event = Event.first
    @open_scoring = @event.open_scoring
    @closed_scoring = @event.closed_scoring
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
          'Open' => %w(& +).include?(@open_scoring) ? [0]*5 : SCORES['Open'].map {0},
          'Closed' => SCORES['Closed'].map {0},
          'points' => 0
        }

        if @open_scoring == '#' || @closed_scoring == '#'
          @scores[group][age][students]['points'] += score.to_i
        else
          value = SCORES['Closed'].index score
          if value
            category = 'Closed'
          else
            category = 'Open'
            value = SCORES['Open'].index score
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
    event = Event.first
    @multi_scoring = event.multi_scoring
    dances = Dance.where.not(multi_category_id: nil).
      includes(multi_children: :dance, heats: [{entry: [:lead, :follow]}, :scores]).
      order(:order)

    @score_range = SCORES['Multi']
    @score_range = SCORES['Closed'] if @multi_scoring == 'G'

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
    event = Event.first
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
    scores = Score.joins(heat: {entry: [:lead, :follow]}).where(lead: {type: 'Professional'}, follow: {type: 'Professional'})
    hscores = scores.group_by {|score| score.heat.number}
    dances = hscores.values.map(&:first).map {|score| [score.heat.number, score.heat.dance.name]}.to_h
    categories = hscores.values.map(&:first).map {|score| [score.heat.number, score.heat.dance_category.name]}.to_h

    if categories.values.uniq.length >= dances.values.uniq.length
      names = categories
    else
      names = dances
    end

    @score_range = SCORES[scores.first&.heat&.category || 'Open']

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
    @event = Event.first
    @open_scoring = @event.open_scoring
    @scores = {}

    people = Person.where(type: 'Professional').
      map {|person| [person.id, person]}.to_h

    instructor_results.each do |(score, instructor), count|
      person = people[instructor]

      @scores[person] ||= {
        'Open' => @open_scoring == '&' ? [0]*5 : SCORES['Open'].map {0},
        'Closed' => SCORES['Closed'].map {0},
        'points' => 0
      }

      if @open_scoring == '#'
        @scores[person]['points'] += score.to_i
      else
        value = SCORES['Closed'].index score
        if value
          category = 'Closed'
        else
          category = 'Open'
          value = SCORES['Open'].index score
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
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @score.errors, status: :unprocessable_entity }
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
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @score.errors, status: :unprocessable_entity }
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
          scores << [score.heat.number, score.heat.entry.lead.name, score.heat.entry.follow.name, score.heat.entry.lead.studio.name, score.judge.name, score.comments]
        end

        if score.heat.entry.follow.type == 'Student'
          scores << [score.heat.number, score.heat.entry.follow.name, score.heat.entry.lead.name, score.heat.entry.lead.studio.name, score.judge.name, score.comments]
        end

        scores
      end.flatten(1).sort

    respond_to do |format|
      format.html
      format.csv
      format.json
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

    def student_results
      event = Event.first
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
      event = Event.first
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
        # For small heats, check if all entries actually made it to finals
        heat_ids = subjects.map(&:id)
        final_scores = Score.joins(:heat).where(heat: heat_ids).where.not(slot: semi_final_slots)
        final_entry_ids = final_scores.map(&:heat).map(&:entry_id).uniq
        
        if final_entry_ids.length == subjects.length
          # All couples proceeded to finals without callback determination
          subjects.map(&:entry_id)
        else
          # Use callback ranking logic even for small heats
          ranks = Heat.rank_callbacks(heat_number, semi_final_slots)
            .map {|entry, rank| [entry.id, rank]}.group_by {|id, rank| rank}
          
          called_back = []
          ranks.each do |rank, entries|
            break if called_back.length + entries.length > 8
            called_back.concat(entries.map(&:first))
          end
          called_back
        end
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
      # select callbacks for finals using shared logic
      called_back = determine_callbacks(@number, @subjects, ..@heat.dance.heat_length)
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
