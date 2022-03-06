class ScoresController < ApplicationController
  before_action :set_score, only: %i[ show edit update destroy ]

  SCORES = {
    "Open" => %w(1 2 3 F),
    "Closed" => %w(B S G GH).reverse,
    "Solo" => %w(B S G GH).reverse
  }

  WEIGHTS = [5, 3, 2, 1]

  # GET /scores or /scores.json
  def heatlist
    @judge = Person.find(params[:judge].to_i)

    @heats = Heat.all.order(:number).group(:number).includes(:dance)

    @agenda = @heats.group_by(&:dance_category).map do |category, heats|
      [heats.map {|heat| heat.number}.min, category.name]
    end.to_h

    @scored = Score.includes(:heat).where(judge: @judge).group_by {|score| score.heat.number}.keys
  end

  # GET /scores or /scores.json
  def heat
    @judge = Person.find(params[:judge].to_i)
    @number = params[:heat].to_i

    @subjects = Heat.where(number: @number).includes(
      :dance, 
      entry: [:age, :level, :lead, :follow]
    ).sort_by {|heat| heat.entry.lead.back || 0}

    if @subjects.empty?
      @dance = '-'
      @scores = []
    else
      @dance = "#{@subjects.first.category} #{@subjects.first.dance.name}"
      @scores = SCORES[@subjects.first.category].dup
    end

    student_results = Score.where(judge: @judge, heat: @subjects).map {|score| [score.heat, score.value]}.to_h

    @results = {}
    @subjects.each do |subject|
      score = student_results[subject] || ''
      @results[score] ||= []
      @results[score] << subject
    end

    @scores << ''
 
    @heat = Heat.find_by(number: @number)
    @next = Heat.where(number: @number+1...).minimum(:number)
    @prev = Heat.where(number: ...@number).maximum(:number)

    @layout = 'mx-0'
    @nologo = true
  end

  def post
    judge = Person.find(params[:judge].to_i)
    heat = Heat.find(params[:heat].to_i)
    score = params[:score]

    score = Score.find_or_create_by(judge_id: judge.id, heat_id: heat.id)
    score.value = params[:score]
    if score.value.empty?
      score.destroy
      render json: score
    else
      score.value = params[:score]
      if score.save
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

        value = SCORES['Closed'].index score
        if value
          category = 'Closed'
        else
          category = 'Open'
          value = SCORES['Open'].index score
        end

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

        @scores[group][level][students][category][value] += count
        @scores[group][level][students]['points'] += count * WEIGHTS[value]
      end
    end
  end

  def by_age
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

        value = SCORES['Closed'].index score
        if value
          category = 'Closed'
        else
          category = 'Open'
          value = SCORES['Open'].index score
        end

        if students.length == 1
          age = ages[students.first.age_id]
        else
          age = ages[students.map {|student| student.age_id}.max]
        end

        @scores[group][age][students] ||= {
          'Open' => SCORES['Open'].map {0},
          'Closed' => SCORES['Closed'].map {0},
          'points' => 0
        }

        @scores[group][age][students][category][value] += count
        @scores[group][age][students]['points'] += count * WEIGHTS[value]
      end
    end      
  end

  def instructor
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
          where(follow: {type: 'Student'}, heat: {category: ['Open', 'Closed']}).
          count(:value),
        'Leaders' => Score.joins(heat: {entry: [:lead]}).
          group(:value, :lead_id).
          where(lead: {type: 'Student'}, heat: {category: ['Open', 'Closed']}).
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
        where(follow: {type: 'Professional'}, heat: {category: ['Open', 'Closed']}).
        count(:value).to_a +
      Score.joins(heat: {entry: [:lead]}).
        group(:value, :lead_id).
        where(lead: {type: 'Professional'}, heat: {category: ['Open', 'Closed']}).
        count(:value).to_a +
      Score.joins(heat: :entry).
        group(:value, :instructor_id).
        where.not(entry: {instructor_id: nil}).
        count(:value).to_a
    end
end