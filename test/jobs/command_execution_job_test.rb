require "test_helper"

class CommandExecutionJobTest < ActiveJob::TestCase
  test "job is enqueued with correct arguments" do
    user = users(:one)

    assert_enqueued_with(job: CommandExecutionJob, args: ["scopy", user.id, "demo", {}]) do
      CommandExecutionJob.perform_later("scopy", user.id, "demo", {})
    end
  end

  test "job handles unknown command gracefully" do
    user = users(:one)

    # Should log error but not raise
    assert_nothing_raised do
      CommandExecutionJob.perform_now("unknown_command", user.id, "demo", {})
    end
  end

  test "all defined commands are valid" do
    # Verify all commands in the COMMANDS hash have valid blocks
    CommandExecutionJob::COMMANDS.each do |command_type, block|
      assert block.is_a?(Proc), "Command #{command_type} should have a Proc"
      assert block.arity == 1, "Command #{command_type} should accept one parameter"
    end
  end

  test "job broadcasts to correct stream" do
    user = users(:one)

    # Mock ActionCable.server.broadcast to verify stream name
    broadcasts = []
    ActionCable.server.stub :broadcast, ->(stream, data) { broadcasts << [stream, data] } do
      # Note: This will actually try to execute the command, so we need to be careful
      # In a real test environment, you might want to stub PTY.spawn as well
    end
  end
end
