require "test_helper"

# Agenda start times are typed into a plain text field (so entry works in
# every browser) and normalized to 24-hour "HH:MM".
#
# test/javascript/start_time.test.js runs the same cases against the
# JavaScript copy of the parser; keep the two in step.
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

  test "reads early hours without am/pm as afternoon" do
    {
      "1:30"  => "13:30",
      "2"     => "14:00",
      "130"   => "13:30",
      "6:00"  => "18:00",
      "7:00"  => "07:00",
      "8:30"  => "08:30",
      "11"    => "11:00",
      "12:15" => "12:15",
      "19:00" => "19:00",
    }.each do |input, expected|
      assert_equal expected, StartTime.parse(input), "parsing #{input.inspect}"
    end
  end

  test "treats a leading zero as 24-hour time" do
    assert_equal "01:30", StartTime.parse("01:30")
    assert_equal "01:30", StartTime.parse("0130")
    assert_equal "00:15", StartTime.parse("00:15")
    assert_equal "01:30", StartTime.parse("1:30 am")
  end

  test "leaves canonical times unchanged" do
    %w[00:00 01:30 06:00 08:30 12:00 13:30 23:59].each do |time|
      assert_equal time, StartTime.parse(time)
    end
  end

  test "rejects things that are not times" do
    ["", nil, "after lunch", "TBD", "9am Sunday", "25:00", "8:75", "13 pm", "0 am", "8:30 xm", 2500].each do |input|
      assert_nil StartTime.parse(input), "parsing #{input.inspect}"
    end
  end

  test "recognizes attempts at a time" do
    ["25:00", "8:75", "13 pm", "0 am", "8:30 xm", "2500", 2500, "99:99", "8:30 pm"].each do |input|
      assert StartTime.time_like?(input), input.inspect
    end
  end

  test "leaves free text alone" do
    ["", nil, "after lunch", "TBD", "9am Sunday", "noon-ish"].each do |input|
      assert_not StartTime.time_like?(input), input.inspect
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

  test "category reads a time typed without am/pm as afternoon" do
    category = Category.create!(name: "Bare Time", order: 9005, time: "1:30")
    assert_equal "13:30", category.reload.time
  end

  test "category allows a blank time" do
    category = Category.new(name: "No Time", order: 9002, time: "")
    assert category.valid?
  end

  test "category keeps free text as typed" do
    ["TBD", "after lunch", "9am Sunday"].each_with_index do |text, index|
      category = Category.create!(name: "Free Text #{index}", order: 9010 + index, time: " #{text} ")
      assert_equal text, category.reload.time
    end
  end

  test "category rejects something that looks like a time but is not one" do
    ["25:00", "8:75 pm", "13 pm", "8:30 xm"].each do |text|
      category = Category.new(name: "Bad Time", order: 9003, time: text)
      assert_not category.valid?, text
      assert_match(/isn't a time we recognize/, category.errors[:time].first)
    end
  end

  test "category rejects a number that is not a time without raising" do
    category = Category.new(name: "Numeric Time", order: 9006, time: 2500)
    assert_not category.valid?
    assert_match(/isn't a time we recognize/, category.errors[:time].first)
  end

  test "validation checks the time itself, not just its shape" do
    category = Category.create!(name: "Bypass", order: 9007)

    # written around the normalizer: shaped like HH:MM, but not a time
    category.update_column(:time, "99:99")
    category.reload.time_will_change!
    assert_not category.valid?
  end

  test "category extension normalizes typed times" do
    extension = CatExtension.create!(category: categories(:one), order: 9004, part: 2, time: "2:45 pm")
    assert_equal "14:45", extension.reload.time
  end
end
