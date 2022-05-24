require "test_helper"

class EventControllerTest < ActionDispatch::IntegrationTest
  test "should get root" do
    get root_url
    assert_response :success
    assert_select 'h1', text: /Showcase/ # matches public/index.html
  end

  test "should get summary" do
    get summary_event_index_path
    assert_response :success
    assert_select 'h1', text: 'Event Summary'
  end

  test "should get settings" do
    get settings_event_index_path
    assert_response :success
  end

  test "should update settings" do
    @event = Event.last
    patch event_url(@event), params: { event: {
      name: @event.name,
      location: @event.location,
      date: @event.date,
      heat_range_cat: @event.heat_range_cat,
      heat_range_level: @event.heat_range_level,
      heat_range_age: @event.heat_range_age,
      intermix: @event.intermix
    } }

    assert_redirected_to settings_event_index_path(anchor: 'adjust')
  end

  test "should get publish" do
    get publish_event_index_path
    assert_response :success
  end

end
