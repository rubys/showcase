class RecordingsController < ApplicationController
  include ActiveStorage::SetCurrent
  
  skip_before_action :authenticate_user, only: %i[ student ]
  before_action :set_recording, only: %i[ show edit update destroy ]

  # GET /recordings/:judge/heat/:heat
  def heat
    @event = Event.first
    @judge = Person.find(params[:judge].to_i)
    @number = params[:heat].to_f
    @number = @number.to_i if @number == @number.to_i
    @slot = params[:slot]&.to_i
    @subjects = Heat.where(number: @number).includes(
      dance: [:multi_children],
      entry: [:age, :level, :lead, :follow]
    ).to_a

    @slot ||= 1 if @subjects.first&.category == 'Multi' and @slot.nil?

    @combine_open_and_closed = @event.heat_range_cat == 1

    category = @subjects.first&.category
    category = 'Open' if category == 'Closed' and @event.closed_scoring == '='

    if @subjects.empty?
      @dance = '-'
      @scores = []
    else
      if @subjects.first.dance_id == @subjects.last.dance_id
        @dance = "#{@subjects.first.category} #{@subjects.first.dance.name}"
      else
        @dance = "#{@subjects.first.category} #{@subjects.first.dance_category.name}"
      end
      
      if @combine_open_and_closed and %w(Open Closed).include? category
        @dance.sub! /^\w+ /, ''
      end
    end

    # Get recordings for this heat
    judge_record = @judge.judge
    recordings = judge_record ? Recording.where(judge: judge_record, heat: @subjects).all : []
    @recordings = {}
    @subjects.each do |subject|
      recording = recordings.find { |r| r.heat_id == subject.id }
      @recordings[subject] = recording
    end

    @subjects.sort_by! {|heat| [heat.dance_id, heat.entry.lead.back || 0]}

    @sort = @judge.sort_order || 'back'
    @show = @judge.show_assignments || 'first'
    @show = 'mixed' unless @event.assign_judges > 0 and @show != 'mixed' && Person.where(type: 'Judge').count > 1
    if @sort == 'level'
      @subjects.sort_by! do |subject|
        entry = subject.entry
        [entry.level_id || 0, entry.age_id || 0, entry.lead.back || 0]
      end
    end

    # Navigation logic
    @heat = @subjects.first
    return unless @heat
    
    options = {}

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

    if @heat.dance.heat_length and (@slot||0) < @heat.dance.heat_length * (@heat.dance.semi_finals ? 2 : 1)
      @next = recording_heat_slot_path(judge: @judge, heat: @number, slot: (@slot||0)+1, **options)
    else
      @next = index + 1 >= heats.length ? nil : heats[index + 1]
      if @next
        if @next.dance.heat_length
          @next = recording_heat_slot_path(judge: @judge, heat: @next.number, slot: 1, **options)
        else
          @next = recording_heat_path(judge: @judge, heat: @next.number, **options)
        end
      end
    end

    if @heat.dance.heat_length and (@slot||0) > 1
      @prev = recording_heat_slot_path(judge: @judge, heat: @number, slot: (@slot||2)-1, **options)
    else
      @prev = index > 0 ? heats[index - 1] : nil
      if @prev
        if @prev.dance.heat_length
          @prev = recording_heat_slot_path(judge: @judge, heat: @prev.number, slot: @prev.dance.heat_length, **options)
        else
          @prev = recording_heat_path(judge: @judge, heat: @prev.number, **options)
        end
      end
    end

    @layout = 'mx-0 px-5'
    @nologo = true
    @backnums = @event.backnums
    @track_ages = @event.track_ages

    @assign_judges = false
  end

  # GET /recordings or /recordings.json
  def index
    @recordings = Recording.all
  end

  # GET /recordings/student/:token
  def student
    student_id = decode_student_token(params[:token])
    @student = Person.find(student_id)
    
    # Find all heats where this student participated (as lead or follow)
    @recordings = Recording.includes(:judge, heat: [entry: [:lead, :follow]])
                           .joins(heat: :entry)
                           .where(
                             'entries.lead_id = ? OR entries.follow_id = ?',
                             @student.id, @student.id
                           )
                           .order('heats.number')
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'Student not found'
  end

  # GET /recordings/1 or /recordings/1.json
  def show
  end

  # GET /recordings/new
  def new
    @recording = Recording.new
  end

  # GET /recordings/1/edit
  def edit
  end

  # POST /recordings or /recordings.json
  def create
    @recording = Recording.new(recording_params)

    respond_to do |format|
      if @recording.save
        format.html { redirect_to @recording, notice: "Recording was successfully created." }
        format.json { render :show, status: :created, location: @recording }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @recording.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /recordings/1 or /recordings/1.json
  def update
    respond_to do |format|
      if @recording.update(recording_params)
        format.html { redirect_to @recording, notice: "Recording was successfully updated." }
        format.json { render :show, status: :ok, location: @recording }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @recording.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /recordings/1 or /recordings/1.json
  def destroy
    @recording.destroy!

    respond_to do |format|
      format.html { redirect_to recordings_path, status: :see_other, notice: "Recording was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  # POST /recordings/:judge_id/heat/:heat_id/upload
  def upload
    person = Person.find(params[:judge_id])
    heat = Heat.find(params[:heat_id])
    
    # Get or create the Judge record for this Person
    judge = person.judge || person.create_judge!
    
    if request.body
      recording = Recording.find_or_initialize_by(judge: judge, heat: heat)
      recording.audio.attach(
        io: request.body,
        filename: "recording-#{person.id}-#{heat.id}-#{Time.current.to_i}.#{request.content_type.split('/').last}",
        content_type: request.content_type
      )
      
      if recording.save
        render json: { status: 'success', message: 'Recording uploaded successfully', url: url_for(recording.audio) }
      else
        render json: { status: 'error', message: recording.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    else
      render json: { status: 'error', message: 'Missing audio data' }, status: :bad_request
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_recording
      @recording = Recording.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def recording_params
      params.expect(recording: [ :judge_id, :heat_id, :audio ])
    end

    # Encode student ID for non-guessable URLs using encryption
    def self.encode_student_token(student_id)
      encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
      encrypted = encryptor.encrypt_and_sign({ student_id: student_id, timestamp: Time.current.to_i })
      Base64.urlsafe_encode64(encrypted)
    end

    # Decode student token back to ID
    def decode_student_token(token)
      encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
      encrypted = Base64.urlsafe_decode64(token)
      decrypted = encryptor.decrypt_and_verify(encrypted)
      
      # Add timestamp validation for additional security (tokens expire after 30 days)
      if Time.current.to_i - decrypted[:timestamp] > 30.days.to_i
        raise ActiveRecord::RecordNotFound
      end
      
      decrypted[:student_id]
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError
      raise ActiveRecord::RecordNotFound
    end
end
