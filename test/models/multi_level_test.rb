require "test_helper"

class MultiLevelTest < ActiveSupport::TestCase
  setup do
    @dance = dances(:waltz)
  end

  test "valid with both start_age and stop_age present" do
    ml = MultiLevel.new(dance: @dance, start_age: 1, stop_age: 3)
    assert ml.valid?
  end

  test "valid with both start_age and stop_age absent" do
    ml = MultiLevel.new(dance: @dance)
    assert ml.valid?
  end

  test "invalid with only start_age present" do
    ml = MultiLevel.new(dance: @dance, start_age: 1)
    assert_not ml.valid?
    assert_includes ml.errors.full_messages, "start_age and stop_age must both be present or both be absent"
  end

  test "invalid with only stop_age present" do
    ml = MultiLevel.new(dance: @dance, stop_age: 3)
    assert_not ml.valid?
    assert_includes ml.errors.full_messages, "start_age and stop_age must both be present or both be absent"
  end

  test "valid with both start_level and stop_level present" do
    ml = MultiLevel.new(dance: @dance, start_level: 1, stop_level: 3)
    assert ml.valid?
  end

  test "valid with both start_level and stop_level absent" do
    ml = MultiLevel.new(dance: @dance)
    assert ml.valid?
  end

  test "invalid with only start_level present" do
    ml = MultiLevel.new(dance: @dance, start_level: 1)
    assert_not ml.valid?
    assert_includes ml.errors.full_messages, "start_level and stop_level must both be present or both be absent"
  end

  test "invalid with only stop_level present" do
    ml = MultiLevel.new(dance: @dance, stop_level: 3)
    assert_not ml.valid?
    assert_includes ml.errors.full_messages, "start_level and stop_level must both be present or both be absent"
  end

  test "valid with both age and level ranges" do
    ml = MultiLevel.new(dance: @dance, start_age: 1, stop_age: 3, start_level: 2, stop_level: 4)
    assert ml.valid?
  end
end
