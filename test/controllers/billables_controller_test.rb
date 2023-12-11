require "test_helper"

class BillablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @billable = billables(:one)
  end

  test "should get index" do
    get billables_url
    assert_response :success
  end

  test "should get new" do
    get new_billable_url(type: 'package')
    assert_response :success
    get new_billable_url(type: 'option')
    assert_response :success
  end

  test "should create billable" do
    assert_difference("Billable.count") do
      post billables_url, params: { type: 'package', billable: { price: @billable.price, name: @billable.name + '2', order: @billable.order, type: @billable.type, options: {'2' => '1'} } }
    end

    assert_redirected_to settings_event_index_path(tab: 'Prices')
  end

  test "should show billable" do
    get billable_url(@billable)
    assert_response :success
  end

  test "should get edit" do
    get edit_billable_url(@billable)
    assert_response :success
  end

  test "should update billable" do
    patch billable_url(@billable), params: { billable: { price: @billable.price, name: @billable.name, order: @billable.order, type: @billable.type, options: {'2' => '1'} } }
    assert_redirected_to settings_event_index_path(anchor: 'prices')
  end

  test "should destroy billable" do
    assert_difference("Billable.count", -1) do
      delete billable_url(@billable)
    end

    assert_redirected_to settings_event_index_path(anchor: 'prices')
  end
end
