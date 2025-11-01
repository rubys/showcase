require "test_helper"

class CommandOutputChannelTest < ActionCable::Channel::TestCase
  test "subscribes with valid parameters" do
    subscribe database: "demo", user_id: 1, job_id: "test-job-id"

    assert subscription.confirmed?
    assert_has_stream "command_output_demo_1_test-job-id"
  end

  test "subscribes to correct stream format" do
    database = "2025-boston"
    user_id = 42
    job_id = "abc123"

    subscribe database: database, user_id: user_id, job_id: job_id

    assert_has_stream "command_output_#{database}_#{user_id}_#{job_id}"
  end
end
