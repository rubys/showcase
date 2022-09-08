class StudiosController < ApplicationController
  include Printable

  before_action :set_studio, only: %i[ show edit update unpair destroy heats scores invoice student_invoices send_invoice ]

  # GET /studios or /studios.json
  def index
    @studios = Studio.all.order(:name).to_a
    staff = @studios.find {|studio| studio.id == 0}
    @studios.push @studios.delete staff

    generate_invoice @studios, @student

    @total_count = Person.where.not(studio_id: nil).count
    @total_tables = Studio.sum(:tables)
    @total_invoice = @invoices.values.map {|info| info[:total_cost]}.sum
  end

  def invoices
    index

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: "invoices"
      end
    end
  end

  def labels
    data = ['Name', 'Studio'].to_csv
    
    Studio.order(:name).each do |studio|
      studio.people.order(:name).each do |person|
        data << [person.display_name, studio.name].to_csv
      end
    end

    response.headers['Content-Type'] = 'text/csv'
    response.headers['Content-Disposition'] = "attachment; filename=event.csv"
    render plain: data
  end

  # GET /studios/1 or /studios/1.json
  def show
    @packages = Billable.group(:type).count
  end

  def heats
    @people = Person.where(type: ['Student', 'Professional'], studio: @studio).order(:name)
    heat_sheets

    respond_to do |format|
       format.html { render 'people/heats' }
       format.pdf do
         render_as_pdf basename: "#{@studio.name}-heat-sheets"
       end
    end
  end

  def scores
    @people = @studio.people
    score_sheets

    solos = Solo.includes(heat: {entry: [:lead, :follow]}).where(follow: {studio_id: @studio}).
      or(Solo.includes(heat: {entry: [:lead, :follow]}).where(follow: {studio_id: @studio})).
      order('number')

    results = solos.map do |solo|
      file = "scans/#{ENV.fetch("RAILS_APP_DB") { 'development' }}/Solo-#{solo.heat.number}.pdf"
      File.exist?(file) ? file : nil
    end.compact

    respond_to do |format|
      format.html { render 'people/scores' }
      format.pdf do
        render_as_pdf basename: "#{@studio.name}-scores", concat: results
      end
    end
  end

  def invoice
    generate_invoice([@studio])

    respond_to do |format|
      format.html
      format.pdf do
        render_as_pdf basename: "#{@studio.name}-invoice"
      end
    end
  end


  def student_invoices
    @student = true
    generate_invoice([@studio], true)

    event = Event.first

    @registration = @studio.student_registration_cost
    @heat_cost = @studio.student_heat_cost || @studio.heat_cost || event.heat_cost || 0
    @solo_cost = @studio.student_solo_cost || @studio.solo_cost || event.solo_cost || 0
    @multi_cost = @studio.student_multi_cost || @studio.multi_cost || event.multi_cost || 0

    unless @registration
      if @studio.default_student_package_id
        @registration = Billable.find(@studio.default_student_package_id).price
      else
        @registration = Billable.where(type: 'Student').order(:order).pluck(:price).first
      end
    end

    respond_to do |format|
      format.html { render 'invoice' }
      format.pdf do
        render_as_pdf basename: "student-invoices"
      end
    end
  end

  def send_invoice
    @event = Event.last

    if request.post?
      begin
        # do job NOW
        SendInvoiceJob.perform_now URI.join(request.original_url, invoice_studio_path(@studio)),
          params.except(:authenticity_token, :commit, :id).
          permit(:from, :to, :subject, :body).
          to_h

        @event.update!(email: params['from']) unless @event.email == params['from']
        @studio.update!(email: params['to']) unless @event.email == params['to']

        respond_to do |format|
          format.html { redirect_to studio_url(@studio), notice: "Invoice sent to #{params['to']}." }
          format.json { render :show, status: :created, location: @studio }
        end
      rescue => exception
        Rails.logger.error "Exception: #{exception}."
        Rails.logger.error "Message: #{exception.message}."
        Rails.logger.error "Backtrace:  \n #{exception.backtrace.join("\n")}"

        respond_to do |format|
          format.html { redirect_to studio_url(@studio), status: :unprocessable_entity,
            notice: "Error Occurred: #{exception}." }
          format.json { render status: :unprocessable_entity,
            json: {exception: exception.to_s, message: exception.message, backtrace: exception.backtrace } }
        end
      end
    else  
      @from = @event.email
      @to = @studio.email
      @subject = "Invoice/Confirmation - #{@event.name}"
      @body = 'See attached.'
    end
  end

  # GET /studios/new
  def new
    @studio ||= Studio.new
    @pairs = @studio.pairs
    @avail = Studio.all.map {|studio| studio.name}
    @cost_override = !!(@studio.heat_cost || @studio.solo_cost || @studio.multi_cost)
    @student_cost_override = !!(@studio.student_heat_cost || @studio.student_solo_cost || @studio.student_multi_cost)

    event = Event.last
    @studio.heat_cost ||= event.heat_cost
    @studio.solo_cost ||= event.solo_cost
    @studio.multi_cost ||= event.multi_cost

    @studio.student_heat_cost ||= @studio.heat_cost;
    @studio.student_solo_cost ||= @studio.solo_cost;
    @studio.student_multi_cost ||= @studio.multi_cost;

    @student_packages = Billable.where(type: 'Student').order(:order).pluck(:name, :id).to_h
    @professional_packages = Billable.where(type: 'Professional').order(:order).pluck(:name, :id).to_h
    @guest_packages = Billable.where(type: 'Guest').order(:order).pluck(:name, :id).to_h

    if @studio.default_student_package_id
      @studio.student_registration_cost ||= Billable.find(@studio.default_student_package_id).price
    elsif not @student_packages.empty?
      @studio.student_registration_cost ||= Billable.find(@student_packages.first.last).price
    end
  end

  # GET /studios/1/edit
  def edit
    new
    @locked = Event.last.locked?
  end

  # POST /studios or /studios.json
  def create
    @studio = Studio.new(studio_params.except(:pair, :cost_override, :student_cost_override))

    cost_override

    respond_to do |format|
      if @studio.save
        add_pair
        format.html { redirect_to studio_url(@studio), notice: "#{@studio.name} was successfully created." }
        format.json { render :show, status: :created, location: @studio }
      else
        new
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @studio.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /studios/1 or /studios/1.json
  def update
    respond_to do |format|
      add_pair
      cost_override

      if @studio.update(studio_params.except(:pair, :cost_override, :student_cost_override))
        format.html { redirect_to studio_url(@studio), notice: "#{@studio.name} was successfully updated." }
        format.json { render :show, status: :ok, location: @studio }
      else
        edit
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @studio.errors, status: :unprocessable_entity }
      end
    end
  end

  def unpair
    pair = params.require(:pair)
    if pair
      pair = Studio.find_by(name: pair)
      if pair and @studio.pairs.include? pair
        StudioPair.destroy_by(studio1: @studio, studio2: pair)
        StudioPair.destroy_by(studio2: @studio, studio1: pair)
        redirect_to edit_studio_url(@studio), notice: "#{pair.name} was successfully unpaired."
      end
    end
  end

  # DELETE /studios/1 or /studios/1.json
  def destroy
    @studio.destroy

    respond_to do |format|
      format.html { redirect_to studios_url, status: 303,
         notice: "#{@studio.name} was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_studio
      @studio = Studio.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def studio_params
      params.require(:studio).permit(:name, :tables, :pair,
        :default_student_package_id,
        :cost_override, :heat_cost, :solo_cost, :multi_cost,
        :student_cost_override, :student_registration_cost,
        :student_heat_cost, :student_solo_cost, :student_multi_cost)
    end

    def add_pair
      pair = studio_params.delete :pair
      if pair
        pair = Studio.find_by(name: pair)
        if pair and not @studio.pairs.include? pair
          pair = StudioPair.new(studio1: @studio, studio2: pair)
          pair.save!
        end
      end
    end

    def cost_override
      if studio_params[:cost_override] == '0'
        params[:studio][:heat_cost] = nil
        params[:studio][:solo_cost] = nil
        params[:studio][:multi_cost] = nil
      end

      if studio_params[:student_cost_override] == '0'
        params[:studio][:student_heat_cost] = nil
        params[:studio][:student_solo_cost] = nil
        params[:studio][:student_multi_cost] = nil
      end
    end
end
