class FeedbacksController < ApplicationController
  before_action :set_feedback, only: %i[ show edit update destroy ]

  # GET /feedbacks or /feedbacks.json
  def index
    @feedbacks = Feedback.all.to_a

    if @feedbacks.empty?
      if Event.current.open_scoring == '+'
        @feedbacks << Feedback.new(order: 1, value: 'Dance & Frame', abbr: 'DF')
        @feedbacks << Feedback.new(order: 2, value: 'Timing', abbr: 'T')
        @feedbacks << Feedback.new(order: 3, value: 'Lead/Follow', abbr: 'LF')
        @feedbacks << Feedback.new(order: 4, value: 'Cuban Motion', abbr: 'CM')
        @feedbacks << Feedback.new(order: 5, value: 'Rise & Fall', abbr: 'RF')
        @feedbacks << Feedback.new(order: 6, value: 'Footwork', abbr: 'FW')
        @feedbacks << Feedback.new(order: 7, value: 'Balance', abbr: 'B')
        @feedbacks << Feedback.new(order: 8, value: 'Arm Styling', abbr: 'AS')
        @feedbacks << Feedback.new(order: 9, value: 'Contra-Body', abbr: 'CB')
        @feedbacks << Feedback.new(order: 10, value: 'Floor Craft', abbr: 'FC')
      else
        @feedbacks << Feedback.new(order: 1, value: 'Frame', abbr: 'F')
        @feedbacks << Feedback.new(order: 2, value: 'Posture', abbr: 'P')
        @feedbacks << Feedback.new(order: 3, value: 'Footwork', abbr: 'FW')
        @feedbacks << Feedback.new(order: 4, value: 'Lead/Follow', abbr: 'LF')
        @feedbacks << Feedback.new(order: 5, value: 'Timing', abbr: 'T')
        @feedbacks << Feedback.new(order: 6, value: 'Style', abbr: 'S')
      end
    end

    orders = @feedbacks.map(&:order)
    (1..orders.max/5*5+5).each do |order|
      next if orders.include?(order)
      feedback = Feedback.new(order: order)
      feedback.value = ""
      feedback.abbr = ""
      @feedbacks << feedback
    end

    @feedbacks.sort_by!(&:order)
  end

  def update_values
    params.each do |key, value|
      next unless key =~ /^\d+$/
      feedback = Feedback.find_or_create_by(order: key.to_i)
      if value.blank?
        feedback.destroy!
      elsif feedback.value != value
        feedback.value = value
        feedback.abbr = value.gsub(/[^A-Z]/, '')
        feedback.save!
      end
    end
    redirect_to feedbacks_path
  end

  def update_abbrs
    params.each do |key, abbr|
      next unless key =~ /^\d+$/
      feedback = Feedback.find_or_create_by(order: key.to_i)
      feedback.abbr = abbr
      feedback.save!
    end
    redirect_to feedbacks_path
  end

  def drop
    index

    source = @feedbacks.find { |feedback| feedback.order == params[:source].to_i }
    target = @feedbacks.find { |feedback| feedback.order == params[:target].to_i }
    return unless source && target

    @feedbacks.each do |feedback|
      feedback.save! if feedback.new_record? && !feedback.value.blank?
    end

    if source.order > target.order
      feedbacks = Feedback.where(order: target.order..source.order).order(:order)
      new_order = feedbacks.map(&:order).rotate(1)
    else
      feedbacks = Feedback.where(order: source.order..target.order).order(:order)
      new_order = feedbacks.map(&:order).rotate(-1)
    end

    Rails.logger.error "new_order: #{new_order.inspect}"

    Feedback.transaction do
      feedbacks.zip(new_order).each do |feedback, order|
        feedback.order = order
        feedback.save! validate: false
      end

      raise ActiveRecord::Rollback unless feedbacks.all? {|feedback| feedback.valid?}
    end

    index

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace('buttons',
        render_to_string(partial: 'buttons')) }
      format.html { redirect_to feedbacks_url }
    end
  end

  def reset
    Feedback.delete_all
    redirect_to feedbacks_path
  end

  # GET /feedbacks/1 or /feedbacks/1.json
  def show
  end

  # GET /feedbacks/new
  def new
    @feedback = Feedback.new
  end

  # GET /feedbacks/1/edit
  def edit
  end

  # POST /feedbacks or /feedbacks.json
  def create
    @feedback = Feedback.new(feedback_params)

    respond_to do |format|
      if @feedback.save
        format.html { redirect_to @feedback, notice: "Feedback was successfully created." }
        format.json { render :show, status: :created, location: @feedback }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @feedback.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /feedbacks/1 or /feedbacks/1.json
  def update
    respond_to do |format|
      if @feedback.update(feedback_params)
        format.html { redirect_to @feedback, notice: "Feedback was successfully updated." }
        format.json { render :show, status: :ok, location: @feedback }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @feedback.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /feedbacks/1 or /feedbacks/1.json
  def destroy
    @feedback.destroy!

    respond_to do |format|
      format.html { redirect_to feedbacks_path, status: :see_other, notice: "Feedback was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_feedback
      @feedback = Feedback.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def feedback_params
      params.expect(feedback: [ :order, :value, :abbr ])
    end
end
