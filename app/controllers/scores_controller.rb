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

    @agenda = @heats.group_by do |heat|
      if heat.category == 'Open'
        heat.dance.open_category
      else
        heat.dance.closed_category
      end
    end.map do |category, heats|
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

    results = Score.where(judge: @judge, heat: @subjects).map {|score| [score.heat, score.value]}.to_h

    @results = {}
    @subjects.each do |subject|
      score = results[subject] || ''
      @results[score] ||= []
      @results[score] << subject
    end

    @scores << ''
 
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

    scores = Score.includes(heat: {entry: [:lead, :follow]}).all

    scores.each do |score|
      category = score.heat.category
      next if category == 'Solo'
      value = SCORES[category].index score.value
      next unless value

      tally = []

      entry = score.heat.entry

      if entry.lead.type == 'Professional'
        tally << ['Followers', entry.follow.display_name]
        level = entry.follow.level
      elsif entry.follow.type == 'Professional'
        tally << ['Leaders', entry.lead.display_name]
        level = entry.lead.level
      else
        tally << ['Followers', entry.follow.display_name]
        tally << ['Leaders', entry.lead.display_name]
        tally << ['Couples', entry.follow.join(entry.lead)]
        level = [entry.follow.level, entry.lead.level].max
      end

      tally.each do |group, students|
        @scores[group][level][students] ||= {
          'Open' => SCORES['Open'].map {0},
          'Closed' => SCORES['Closed'].map {0},
          'points' => 0
        }

        @scores[group][level][students][category][value] += 1
      end
    end

    @scores.each do |group, levels|
      levels.each do |level, students|
        students.each do |student, results|
          results['points'] =
            results['Closed'].zip(WEIGHTS).sum {|value, weight| value*weight} +
              results['Open'].zip(WEIGHTS).sum {|value, weight| value*weight}
        end
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

    scores = Score.includes(heat: {entry: [:lead, :follow]}).all

    scores.each do |score|
      category = score.heat.category
      next if category == 'Solo'
      value = SCORES[category].index score.value
      next unless value

      tally = []

      entry = score.heat.entry

      if entry.lead.type == 'Professional'
        tally << ['Followers', entry.follow.display_name]
        age = entry.follow.age
      elsif entry.follow.type == 'Professional'
        tally << ['Leaders', entry.lead.display_name]
        age = entry.lead.age
      else
        tally << ['Followers', entry.follow.display_name]
        tally << ['Leaders', entry.lead.display_name]
        tally << ['Couples', entry.follow.join(entry.lead)]
        age = [entry.follow.age, entry.lead.age].max
      end

      tally.each do |group, students|
        @scores[group][age][students] ||= {
          'Open' => SCORES['Open'].map {0},
          'Closed' => SCORES['Closed'].map {0},
          'points' => 0
        }

        @scores[group][age][students][category][value] += 1
      end
    end

    @scores.each do |group, ages|
      ages.each do |age, students|
        students.each do |student, results|
          results['points'] =
            results['Closed'].zip(WEIGHTS).sum {|value, weight| value*weight} +
              results['Open'].zip(WEIGHTS).sum {|value, weight| value*weight}
        end
      end
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
end
