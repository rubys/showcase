class ScoresController < ApplicationController
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

    @heats = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance)

    @agenda = @heats.group_by(&:dance_category).map do |category, heats|
      [heats.map {|heat| heat.number}.min, category&.name]
    end.to_h

    @scored = Score.includes(:heat).where(judge: @judge).group_by {|score| score.heat.number}
    @count = Heat.all.where(number: 1..).order(:number).group(:number).includes(:dance).count
  end

  # GET /scores/:judge/heat/:heat
  def heat
    @event = Event.first
    @judge = Person.find(params[:judge].to_i)
    @number = params[:heat].to_i
    @slot = params[:slot]&.to_i
    @style = params[:style] || 'cards'
    @subjects = Heat.where(number: @number).includes(
      dance: [:multi_children], 
      entry: [:age, :level, :lead, :follow]
    ).sort_by {|heat| heat.entry.lead.back || 0}

    if @subjects.empty?
      @dance = '-'
      @scores = []
    else
      category = @subjects.first.category
      @dance = "#{category} #{@subjects.first.dance.name}"
      if category == 'Open' and @event.open_scoring == 'G'
        @scores = SCORES['Closed'].dup
      else
        @scores = SCORES[category].dup
      end

      @ballrooms = @subjects.first.dance_category.ballrooms || @event.ballrooms
    end

    student_results = Score.where(judge: @judge, heat: @subjects, slot: @slot).
      map {|score| [score.heat, score.value]}.to_h

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

    @scores << ''
 
    @heat = Heat.find_by(number: @number)

    if @heat.category == 'Solo'
      @comments = Score.where(judge: @judge, heat: @subjects.first).first&.comments
    end

    if @heat.dance.heat_length and (@slot||0) < @heat.dance.heat_length
      @next = judge_heat_slot_path(judge: @judge, heat: @number, slot: (@slot||0)+1, style: @style)
    else
      @next = Heat.where(number: @number+1...).order(:number).first
      if @next
        if @next.dance.heat_length
          @next = judge_heat_slot_path(judge: @judge, heat: @next.number, slot: 1, style: @style)
        else
          @next = judge_heat_path(judge: @judge, heat: @next.number, style: @style)
        end
      end
    end

    if @heat.dance.heat_length and (@slot||0) > 1
      @prev = judge_heat_slot_path(judge: @judge, heat: @number, slot: (@slot||2)-1, style: @style)
    else
      @prev = Heat.where(number: 1...@number).order(:number).last
      if @prev
        if @prev.dance.heat_length
          @prev = judge_heat_slot_path(judge: @judge, heat: @prev.number, slot: @prev.dance.heat_length, style: @style)
        else
          @prev = judge_heat_path(judge: @judge, heat: @prev.number, style: @style)
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
      score.comments = params[:comments]
      if score.save
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

  # GET /scores or /scores.json
  def index
    @scores = Score.all
  end

  def by_level
    @open_scoring = Event.first.open_scoring
    levels = Level.order(:id).all

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
  end

  def multis
    @open_scoring = Event.first.open_scoring
    dances = Dance.where.not(multi_category_id: nil).
      includes(multi_children: :dance, heats: [{entry: [:lead, :follow]}, :scores]).
      order(:order)

    @scores = {}
    dances.each do |dance|
      @scores[dance] = {}
      dance.heats.map(&:scores).flatten.group_by {|score| score.heat.entry}.map do |entry, scores|
        @scores[dance][entry] = {
          'Multi' => SCORES['Multi'].map {0},
          'points' => 0
        }

        scores.each do |score|
          if @open_scoring == '#'
            @scores[dance][entry]['points'] += score.value.to_i
          else
            value = SCORES['Multi'].index score.value
            if value
              @scores[dance][entry]['Multi'][value] += 1
              @scores[dance][entry]['points'] += WEIGHTS[value]
            end
          end
        end
      end
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
      end

      @scores[person] ||= {
        'Open' => SCORES['Open'].map {0},
        'Closed' => SCORES['Closed'].map {0},
        'points' => 0
      }

      @scores[person][category][value] += count
      @scores[person]['points'] += count * WEIGHTS[value]
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
        'Followers' => Score.joins(heat: {entry: [:follow]}).
          group(:value, :follow_id).
          where(follow: {type: 'Student'}).
          count(:value),
        'Leaders' => Score.joins(heat: {entry: [:lead]}).
          group(:value, :lead_id).
          where(lead: {type: 'Student'}).
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
