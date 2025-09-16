require "application_system_test_case"

class PaymentsTest < ApplicationSystemTestCase
  setup do
    @payment = payments(:one)
    @person = @payment.person
  end

  test "visiting the index" do
    visit person_payments_url(@person)
    assert_selector "h1", text: "Payments for #{@person.name}"
  end

  test "should create payment" do
    visit person_payments_url(@person)
    click_on "New Payment"

    fill_in "Amount", with: @payment.amount
    fill_in "Comment", with: @payment.comment
    fill_in "Date", with: @payment.date
    click_on "Create Payment"

    assert_text "Payment was successfully created"
    # Should automatically redirect to payments list after creation
  end

  test "should update Payment" do
    visit person_payment_url(@person, @payment)
    click_on "Edit this payment", match: :first

    fill_in "Amount", with: @payment.amount
    fill_in "Comment", with: @payment.comment
    fill_in "Date", with: @payment.date
    click_on "Update Payment"

    assert_text "Payment was successfully updated"
    # Should automatically redirect to payments list after update
  end

  test "should destroy Payment" do
    visit person_payment_url(@person, @payment)
    accept_confirm { click_on "Destroy this payment", match: :first }

    assert_text "Payment was successfully destroyed"
  end
end
