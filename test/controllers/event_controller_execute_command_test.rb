require "test_helper"

class EventControllerExecuteCommandTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "execute_command returns stream name for valid command" do
    # Stub authentication to return our test user
    EventController.any_instance.stubs(:instance_variable_get).with(:@authuser).returns(@user.userid)

    post event_execute_command_url(command_type: "scopy"),
         params: { params: {} },
         as: :json

    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("stream"), "Response should include stream key"
    assert_match /command_output_/, json["stream"], "Stream should follow naming pattern"
  end

  test "execute_command rejects invalid command" do
    EventController.any_instance.stubs(:instance_variable_get).with(:@authuser).returns(@user.userid)

    post event_execute_command_url(command_type: "invalid_command"),
         params: { params: {} },
         as: :json

    assert_response :bad_request

    json = JSON.parse(response.body)
    assert_equal "Invalid command", json["error"]
  end

  test "execute_command creates development user when unauthenticated in development" do
    # Simulate development environment without authentication
    Rails.env.stub :development?, true do
      EventController.any_instance.stubs(:instance_variable_get).with(:@authuser).returns(nil)

      assert_difference("User.count", 1) do
        post event_execute_command_url(command_type: "scopy"),
             params: { params: {} },
             as: :json
      end

      assert_response :success

      dev_user = User.find_by(userid: "dev")
      assert_not_nil dev_user, "Development user should be created"
      assert_equal "dev@localhost", dev_user.email
    end
  end

  test "execute_command enqueues job with correct parameters" do
    EventController.any_instance.stubs(:instance_variable_get).with(:@authuser).returns(@user.userid)

    assert_enqueued_with(job: CommandExecutionJob) do
      post event_execute_command_url(command_type: "scopy"),
           params: { params: {} },
           as: :json
    end
  end

  test "execute_command stream name includes database, user_id, and job_id" do
    EventController.any_instance.stubs(:instance_variable_get).with(:@authuser).returns(@user.userid)
    ENV["RAILS_APP_DB"] = "test-db"

    post event_execute_command_url(command_type: "scopy"),
         params: { params: {} },
         as: :json

    json = JSON.parse(response.body)
    stream = json["stream"]

    assert_match /command_output_test-db_#{@user.id}_/, stream,
                 "Stream should include database and user_id"
  end
end
