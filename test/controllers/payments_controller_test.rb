require "test_helper"

class PaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @payment = payments(:one)
    @person = @payment.person
  end

  test "should get index" do
    get person_payments_url(@person)
    assert_response :success
  end

  test "should get new" do
    get new_person_payment_url(@person)
    assert_response :success
  end

  test "should create payment" do
    assert_difference("Payment.count") do
      post person_payments_url(@person), params: { payment: { amount: @payment.amount, comment: @payment.comment, date: @payment.date } }
    end

    assert_redirected_to person_payments_url(@person)
  end

  test "should show payment" do
    get person_payment_url(@person, @payment)
    assert_response :success
  end

  test "should get edit" do
    get edit_person_payment_url(@person, @payment)
    assert_response :success
  end

  test "should update payment" do
    patch person_payment_url(@person, @payment), params: { payment: { amount: @payment.amount, comment: @payment.comment, date: @payment.date } }
    assert_redirected_to person_payments_url(@person)
  end

  test "should destroy payment" do
    assert_difference("Payment.count", -1) do
      delete person_payment_url(@person, @payment)
    end

    assert_redirected_to person_payments_url(@person)
  end
end
