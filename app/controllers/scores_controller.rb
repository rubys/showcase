class ScoresController < ApplicationController
  include Printable
  before_action :set_score, only: %i[ show edit update destroy ]

  SCORES = {
    "Open" => %w(1 2 3 F),
    "Closed" => %w(B S G GH).reverse,
    "Solo" => %w(B S G GH).reverse,
    "Multi" => %w(1 2 3 F)
  }

  WEIGHTS = [5, 3, 2, 1]

  # GET /scores or /scores.json
  def heatlist
    @judge = Person.find(params[:judge].to_i)
    @style = params[:style] || 'cards'
    @sort = params[:sort] || 'back'

    @heats = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance)

    @agenda = @heats.group_by(&:dance_category).
      sort_by {|category, heats| [category.order, heats.map(&:number).min]}
    @heats = @agenda.to_h.values.flatten
    @agenda = @agenda.map do |category, heats|
      [heats.map(&:number).min, category&.name]
    end.to_h

    @scored = Score.includes(:heat).where(judge: @judge).group_by {|score| score.heat.number}
    @count = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance).count
  end

  # GET /scores/:judge/heat/:heat
  def heat
    @event = Event.first
    @judge = Person.find(params[:judge].to_i)
    @number = params[:heat].to_f
    @number = @number.to_i if @number == @number.to_i
    @slot = params[:slot]&.to_i
    @style = params[:style] || 'cards'
    @subjects = Heat.where(number: @number).includes(
      dance: [:multi_children], 
      entry: [:age, :level, :lead, :follow]
    ).to_a

    if @subjects.empty?
      @dance = '-'
      @scores = []
    else
      category = @subjects.first.category
      if @subjects.first.dance_id == @subjects.last.dance_id
        @dance = "#{category} #{@subjects.first.dance.name}"
      else
        @dance = "#{category} #{@subjects.first.dance_category.name}"
      end
      if category == 'Open' and @event.open_scoring == 'G'
        @scores = SCORES['Closed'].dup
      elsif category == 'Open' and @event.open_scoring == '+'
        @scores = []
      elsif category == 'Multi' and @event.multi_scoring == 'G'
        @scores = SCORES['Closed'].dup
      else
        @scores = SCORES[category].dup
      end
    end

    scores = Score.where(judge: @judge, heat: @subjects, slot: @slot).all
    student_results = scores.map {|score| [score.heat, score.value]}.to_h

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

    if @event.open_scoring == '+' and @subjects.first.category == 'Open'
      @good = {}
      @bad = {}
      scores.each do |score|
        @good[score.heat_id] = score.good
        @bad[score.heat_id] = score.bad
      end
    end

    @subjects.sort_by! {|heat| [heat.dance_id, heat.entry.lead.back || 0]}
    ballrooms = @subjects.first.dance_category&.ballrooms || @event.ballrooms
    @ballrooms = assign_rooms(ballrooms, @subjects)

    @sort = params[:sort] || 'back'
    if @sort == 'level'
      @subjects.sort_by! do |subject|
        entry = subject.entry
        [entry.level_id || 0, entry.age_id || 0, entry.lead.back || 0]
      end
    end

    @scores << '' unless @scores.length == 0
 
    @heat = Heat.find_by(number: @number)

    if @heat.category == 'Solo'
      @comments = Score.where(judge: @judge, heat: @subjects.first).first&.comments
    else
      @comments = Score.where(judge: @judge, heat: @subjects).
        map {|score| [score.heat_id, score.comments]}.to_h
    end

    options = {style: @style, sort: @sort}

    heats = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance)
    agenda = heats.group_by(&:dance_category).
      sort_by {|category, heats| [category.order, heats.map(&:number).min]}
    heats = agenda.to_h.values.flatten
    index = heats.index {|heat| heat.number == @heat.number}

    if @heat.dance.heat_length and (@slot||0) < @heat.dance.heat_length
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
          @prev = judge_heat_slot_path(judge: @judge, heat: @prev.number, slot: @prev.dance.heat_length, **options)
        else
          @prev = judge_heat_path(judge: @judge, heat: @prev.number, **options)
        end
      end
    end

    @layout = 'mx-0 px-5'
    @nologo = true
    @backnums = @event.backnums
    @track_ages = @event.track_ages
  end

  def post
    judge = Person.find(params[:judge].to_i)
    heat = Heat.find(params[:heat].to_i)
    slot = params[:slot]&.to_i

    score = Score.find_or_create_by(judge_id: judge.id, heat_id: heat.id, slot: slot)
    if ApplicationRecord.readonly?
      render json: 'database is readonly', status: :service_unavailable
    elsif params[:comments]
      if params[:comments].empty?
        score.comments = nil
      else
        score.comments = params[:comments]
      end

      keep = score.good || score.bad || score.comments || score.value
      if keep ? score.save : score.delete
        render json: score.as_json
      else
        render json: score.errors, status: :unprocessable_entity
      end
    elsif not params[:score].blank? or not score.comments.blank?
      score.value = params[:score]
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

  def post_feedback
    judge = Person.find(params[:judge].to_i)
    heat = Heat.find(params[:heat].to_i)
    slot = params[:slot]&.to_i

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
      else
        render json: params, status: :bad_request
        return
      end

      keep = score.good || score.bad || score.comments || score.value

      if keep ? score.save : score.delete
        render json: score.as_json
      else
        render json: score.errors, status: :unprocessable_entity
      end
    end
  end

  # GET /scores or /scores.json
  def index
    @scores = Score.all
  end

  def by_level
    @open_scoring = Event.first.open_scoring
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
          'Open' => SCORES['Open'].map {0},
          'Closed' => SCORES['Closed'].map {0},
          'points' => 0
        }

        if @open_scoring == '#'
          @scores[group][level][students]['points'] += score.to_i
        else
          value = SCORES['Closed'].index score
          if value
            category = 'Closed'
          else
            category = 'Open'
            value = SCORES['Open'].index score
          end

          if value
            @scores[group][level][students][category][value] += count
            @scores[group][level][students]['points'] += count * WEIGHTS[value]
          end
        end
      end
    end

    if request.post?
      render turbo_stream: turbo_stream.replace("scores-by-level",
        render_to_string(partial: 'by_level', layout: false)
      )
    end
  end

  def by_studio
    @open_scoring = Event.first.open_scoring
    levels = Level.order(:id).all

    @last_score_update = Score.maximum(:updated_at)

    @scores = levels.map {|level| [level, {}]}.to_h

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
            'points' => 0,
            'count' => 0
          }

          @scores[level][studio]['count'] += count

          if @open_scoring == '#'
            @scores[level][studio]['points'] += count * score.to_i
          else
            value = SCORES['Closed'].index score
            if value
              category = 'Closed'
            else
              category = 'Open'
              value = SCORES['Open'].index score
            end

            if value
              @scores[level][studio]['points'] += count * WEIGHTS[value]
            end
          end
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
    @open_scoring = Event.first.open_scoring
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
          age = ages[students.map {|student| student.age_id}.max]
        end

        age ||= ages.first.last

        @scores[group][age][students] ||= {
          'Open' => SCORES['Open'].map {0},
          'Closed' => SCORES['Closed'].map {0},
          'points' => 0
        }

        if @open_scoring == '#'
          @scores[group][age][students]['points'] += score.to_i
        else
          value = SCORES['Closed'].index score
          if value
            category = 'Closed'
          else
            category = 'Open'
            value = SCORES['Open'].index score
          end
  
          if value
            @scores[group][age][students][category][value] += count
            @scores[group][age][students]['points'] += count * WEIGHTS[value]
          end
        end
      end
    end

    if request.post?
      render turbo_stream: turbo_stream.replace("scores-by-age",
        render_to_string(partial: 'by_age', layout: false)
      )
    end
  end

  def multis
    @multi_scoring = Event.first.multi_scoring
    dances = Dance.where.not(multi_category_id: nil).
      includes(multi_children: :dance, heats: [{entry: [:lead, :follow]}, :scores]).
      order(:order)

    @score_range = SCORES['Multi']
    @score_range = SCORES['Closed'] if @multi_scoring == 'G'

    @scores = {}
    dances.each do |dance|
      @scores[dance] = {}
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

    if request.post?
      render turbo_stream: turbo_stream.replace("multis-scores",
        render_to_string(partial: 'multis', layout: false)
      )
    end
  end

  def instructor
    @open_scoring = Event.first.open_scoring
    @scores = {}

    people = Person.where(type: 'Professional').
      map {|person| [person.id, person]}.to_h

    instructor_results.each do |(score, instructor), count|
      person = people[instructor]

      value = SCORES['Closed'].index score
      if value
        category = 'Closed'
      else
        category = 'Open'
        value = SCORES['Open'].index score
        next unless value
      end

      @scores[person] ||= {
        'Open' => SCORES['Open'].map {0},
        'Closed' => SCORES['Closed'].map {0},
        'points' => 0
      }

      @scores[person][category][value] += count
      @scores[person]['points'] += count * WEIGHTS[value]
    end

    if request.post?
      render turbo_stream: turbo_stream.replace("instructor-scores",
        render_to_string(partial: 'instructor', layout: false)
      )
    end
  end

  def sort
    judge = Judge.find_or_create_by(person_id: params[:judge])
    judge.update! sort: params[:sort]
    redirect_to judge_heatlist_path(judge: params[:judge], sort: params[:sort], style: params[:style])
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
      scores = {
        'Followers' => Score.joins(heat: {entry: [:lead, :follow]}).
          group(:value, :follow_id).
          where(follow: {type: 'Student'}, lead: {type: 'Professional'}).
          count(:value),
        'Leaders' => Score.joins(heat: {entry: [:lead, :follow]}).
          group(:value, :lead_id).
          where(lead: {type: 'Student'}, follow: {type: 'Professional'}).
          count(:value),
        'Couples' => Score.joins(heat: {entry: [:lead, :follow]}).
          group(:value, :follow_id, :lead_id).
          where(lead: {type: 'Student'}, follow: {type: 'Student'},
            heat: {category: ['Open', 'Closed']}).
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
end
