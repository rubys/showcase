class ScoresController < ApplicationController
  before_action :set_score, only: %i[ show edit update destroy ]

  # GET /scores or /scores.json
  def heatlist
    @judge = Person.find(params[:judge].to_i)

    @heats = Heat.all.order(:number).group(:number).includes(:dance)

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

    if @subjects.first&.category == 'Closed'
      @scores = %w(B S G GH).reverse
    else
      @scores = %w(1 2 3 F)
    end

    if @subjects.empty?
      @dance = '-'
    else
      @dance = "#{@subjects.first.category} #{@subjects.first.dance.name}"
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

  # GET /scores/1 or /scores/1.json
  def show
  end

  # GET /scores/new
  def new
    @score = Score.new
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
      params.require(:score).permit(:judge_id, :entry_id, :value)
    end
end
