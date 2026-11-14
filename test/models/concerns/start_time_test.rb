require "test_helper"

# Agenda start times are typed into a plain text field (so entry works in
# every browser) and normalized to 24-hour "HH:MM".
class StartTimeTest < ActiveSupport::TestCase
  test "parses common ways of typing a time" do
    {
      "8:30 am"    => "08:30",
      "8:30am"     => "08:30",
      "8:30 AM"    => "08:30",
      "8:30 a.m."  => "08:30",
      "10 a.m."    => "10:00",
      "1 pm"       => "13:00",
      "1p"         => "13:00",
      "1:15 P.M."  => "13:15",
      "830 pm"     => "20:30",
      "12 pm"      => "12:00",
      "12:30 am"   => "00:30",
      "noon"       => "12:00",
      "midnight"   => "00:00",
      "13:00"      => "13:00",
      "08:30"      => "08:30",
      "1300"       => "13:00",
      "8.30"       => "08:30",
      "  9:05 pm " => "21:05",
    }.each do |input, expected|
      assert_equal expected, StartTime.parse(input), "parsing #{input.inspect}"
    end
  end

  test "times without am/pm are read as 24-hour" do
    assert_equal "01:00", StartTime.parse("1:00")
    assert_equal "19:00", StartTime.parse("19:00")
  end

  test "rejects things that are not times" do
    ["", nil, "after lunch", "25:00", "8:75", "13 pm", "0 am", "8:30 xm"].each do |input|
      assert_nil StartTime.parse(input), "parsing #{input.inspect}"
    end
  end

  test "displays times in 12-hour form" do
    assert_equal "8:30 AM", StartTime.display("08:30")
    assert_equal "1:00 PM", StartTime.display("13:00")
    assert_equal "12:00 PM", StartTime.display("12:00")
    assert_equal "12:15 AM", StartTime.display("00:15")
    assert_equal "10:00 AM", StartTime.display("10 a.m.")
    assert_equal "", StartTime.display(nil)
    assert_equal "after lunch", StartTime.display("after lunch")
  end

  test "category normalizes typed times when saved" do
    category = Category.create!(name: "Typed Time", order: 9001, time: "8:30 pm")
    assert_equal "20:30", category.reload.time
  end

  test "category allows a blank time" do
    category = Category.new(name: "No Time", order: 9002, time: "")
    assert category.valid?
  end

  test "category rejects an unrecognized time with a helpful message" do
    category = Category.new(name: "Bad Time", order: 9003, time: "after lunch")
    assert_not category.valid?
    assert_match(/isn't a time we recognize/, category.errors[:time].first)
  end

  test "category extension normalizes typed times" do
    extension = CatExtension.create!(category: categories(:one), order: 9004, part: 2, time: "2:45 pm")
    assert_equal "14:45", extension.reload.time
  end
end
