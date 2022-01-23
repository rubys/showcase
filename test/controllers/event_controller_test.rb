require "test_helper"

class EventControllerTest < ActionDispatch::IntegrationTest
  test "should get root" do
    get event_root_url
    assert_response :success
  end
end
