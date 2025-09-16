class PaymentsController < ApplicationController
  before_action :set_person
  before_action :set_payment, only: %i[ show edit update destroy ]

  # GET /people/:person_id/payments
  def index
    @payments = @person.payments.order(date: :desc)
  end

  # GET /payments/1 or /payments/1.json
  def show
  end

  # GET /people/:person_id/payments/new
  def new
    @payment = @person.payments.build
    @payment.date = Date.today
  end

  # GET /people/:person_id/payments/:id/edit
  def edit
  end

  # POST /people/:person_id/payments
  def create
    @payment = @person.payments.build(payment_params)

    respond_to do |format|
      if @payment.save
        format.html { redirect_to person_payments_path(@person), notice: "Payment was successfully created." }
        format.json { render :show, status: :created, location: @payment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /people/:person_id/payments/:id
  def update
    respond_to do |format|
      if @payment.update(payment_params)
        format.html { redirect_to person_payments_path(@person), notice: "Payment was successfully updated." }
        format.json { render :show, status: :ok, location: @payment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /people/:person_id/payments/:id
  def destroy
    @payment.destroy!

    respond_to do |format|
      format.html { redirect_to person_payments_path(@person), status: :see_other, notice: "Payment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    def set_person
      @person = Person.find(params[:person_id])
    end

    def set_payment
      @payment = @person.payments.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def payment_params
      params.expect(payment: [ :amount, :date, :comment ])
    end
end
